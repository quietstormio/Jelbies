//
//  RoomShaders.metal
//  Living-room shading: wrapped key diffuse + sky ambient, procedural chevron floor, rug rings,
//  baked vertex AO, optional shadow map, gentle depth fog. Outputs LINEAR colour (the caller tone-maps).
//  All symbols are prefixed `room` to avoid clashing with the jelly shaders.
//  Layout of RoomUniforms must match RoomRenderer.swift (RoomUniforms).
//

#include <metal_stdlib>
using namespace metal;

struct RoomUniforms {
    float4x4 viewProj;
    float4x4 lightVP;
    float4 camPos;      // xyz, w = 1 when the shadow map is valid
    float4 keyDir;      // xyz toward light, w = intensity
    float4 rug;         // cx, cz, radius, unused
    float4 bounds;      // minX, maxX, minZ, maxZ
    float4 fog;         // start, end, max, unused
    float4 pal0; float4 pal1; float4 pal2; float4 pal3; float4 pal4;
    float4x4 topVP;     // Bob's top-down height map (contact AO)
};

struct RoomVertexIn {
    float4 pos    [[attribute(0)]];   // w = material
    float4 normal [[attribute(1)]];   // w = ao
    float4 color  [[attribute(2)]];
};

struct RoomVOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 color;
    float ao;
    float mat [[flat]];
};

vertex RoomVOut roomVS(RoomVertexIn v [[stage_in]], constant RoomUniforms& u [[buffer(0)]]) {
    RoomVOut o;
    o.world = v.pos.xyz;
    o.position = u.viewProj * float4(v.pos.xyz, 1.0);
    o.normal = v.normal.xyz;
    o.ao = v.normal.w;
    o.color = v.color.rgb;
    o.mat = v.pos.w;
    return o;
}

static float roomHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

constexpr sampler roomCmp(coord::normalized, address::clamp_to_edge, filter::linear, compare_func::less_equal);

static float roomShadow(constant RoomUniforms& u, depth2d<float> sm, float3 P, float3 N) {
    if (u.camPos.w < 0.5) { return 1.0; }
    float4 lp = u.lightVP * float4(P + N * 0.01, 1.0);
    float2 uv = float2(lp.x * 0.5 + 0.5, 0.5 - lp.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return 1.0; }
    float z = lp.z - 0.0015;
    float s = 0.0;
    float2 texel = float2(1.0 / float(sm.get_width()), 1.0 / float(sm.get_height()));
    // wide, soft penumbra (Nintendogs-style blob rather than a cut-out): 5x5 taps, 4.5 texels apart, then only a partial darkening
    for (int j = -2; j <= 2; j++) {
        for (int i = -2; i <= 2; i++) {
            s += sm.sample_compare(roomCmp, uv + float2(i, j) * texel * 4.5, z);
        }
    }
    return mix(1.0, s / 25.0, 0.62);
}

/// Soft contact occlusion from Bob's top-down height map (same sampling as the studio floor, scaled to the room).
static float roomContactAO(constant RoomUniforms& u, depth2d<float> heightMap, float3 P) {
    float4 tp = u.topVP * float4(P, 1.0);
    float2 uv = float2(tp.x * 0.5 + 0.5, 0.5 - tp.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return 0.0; }
    uint2 idim = uint2(heightMap.get_width(), heightMap.get_height());
    float2 dims = float2(idim);
    float occ = 0.0;
    for (int ring = 0; ring < 3; ring++) {
        float rad = 0.010 + float(ring) * 0.022;
        for (int i = 0; i < 8; i++) {
            float a = float(i) * 0.785398 + float(ring) * 0.39;
            float2 s = uv + float2(cos(a), sin(a)) * rad;
            if (s.x < 0.0 || s.x > 1.0 || s.y < 0.0 || s.y > 1.0) { continue; }
            float d = heightMap.read(min(uint2(s * dims), idim - 1));
            float h = d * 5.0 - 1.0;
            if (d < 0.9999) {
                float dist = float(ring) * 0.022 * 5.2 + 0.05;
                occ += (1.0 - smoothstep(0.0, 0.32 + dist, h)) * (1.0 - float(ring) * 0.22);
            }
        }
    }
    return clamp(occ / 16.0, 0.0, 1.0);
}

/// Chevron plank floor. Returns albedo; `seam` out = 1 inside a plank, 0 on a seam.
static float3 roomFloor(constant RoomUniforms& u, float2 xz, float3 base, float3 light, thread float& seam) {
    const float S = 0.9;     // chevron half period (plank run along x)
    const float W = 0.26;    // plank width measured along z
    float tri = abs(fract(xz.x / (2.0 * S)) * 2.0 - 1.0) * S;
    float v = (xz.y + tri) / W;
    float row = floor(v), fv = fract(v);
    float cx = xz.x / S;
    float col = floor(cx), fx = fract(cx);
    float dv = min(fv, 1.0 - fv) * W * 0.7071;
    float dx = min(fx, 1.0 - fx) * S;
    float aa = max(fwidth(v) * W * 0.7071, 0.002);
    seam = smoothstep(0.004, 0.004 + aa * 1.5, min(dv, dx));
    float h = roomHash(float2(col * 1.37 + 11.0, row * 0.73 + 5.0));
    float grain = sin(xz.x * 38.0 + h * 40.0) * 0.5 + 0.5;
    float3 c = mix(base, light, 0.15 + 0.55 * h);
    c *= 0.97 + 0.03 * grain;
    return c;
}

fragment float4 roomFS(RoomVOut in [[stage_in]],
                       constant RoomUniforms& u [[buffer(0)]],
                       depth2d<float> shadowMap [[texture(0)]],
                       depth2d<float> heightMap [[texture(1)]]) {
    float3 N = normalize(in.normal);
    float3 P = in.world;
    float3 camVec = u.camPos.xyz - P;
    float dist = length(camVec);
    float3 V = camVec / max(dist, 1e-4);
    int m = int(in.mat + 0.5);

    float3 albedo = in.color;
    float ao = in.ao;
    float gloss = 0.0;

    if (m == 4) {
        // glowing pane: emissive, only the fog-free light
        float soft = 1.0 + 0.5 * smoothstep(0.0, 1.0, (P.y - 1.5) / 2.8);
        return float4(albedo * soft * 1.25, 1.0);
    } else if (m == 1) {
        float seam;
        albedo = roomFloor(u, P.xz, u.pal2.rgb, u.pal3.rgb, seam);
        albedo *= mix(0.78, 1.0, seam);
        gloss = 0.5 * seam;
    } else if (m == 2) {
        // wall: soft vertical gradient and corner / floor occlusion
        ao *= mix(0.72, 1.0, smoothstep(0.0, 1.0, P.y));
        ao *= mix(0.85, 1.0, smoothstep(0.0, 0.8, min(P.x - u.bounds.x, u.bounds.y - P.x)));
        ao *= mix(0.92, 1.0, smoothstep(1.0, 3.0, 10.0 - P.y));
    } else if (m == 3) {
        float r = length(P.xz - u.rug.xy);
        float R = u.rug.z;
        float band = smoothstep(0.03, 0.0, abs(r - (R - 0.22)) - 0.07) ;         // wide outer band
        float line = smoothstep(0.02, 0.0, abs(r - (R - 0.5)) - 0.015);          // thin inner line
        float centre = smoothstep(1.2, 0.0, r) * 0.35;                           // soft centre medallion
        albedo = mix(u.pal4.rgb, u.pal3.rgb, saturate(band + line * 0.8));
        albedo = mix(albedo, u.pal3.rgb, centre * 0.5);
        albedo *= 0.96 + 0.04 * roomHash(floor(P.xz * 90.0));                    // fibre speckle
    } else {
        ao = ao; // baked
    }

    // ---- lighting ----
    float3 L = normalize(u.keyDir.xyz);
    float wrapW = 0.55;
    float ndl = (dot(N, L) + wrapW) / (1.0 + wrapW);
    ndl = saturate(ndl);
    ndl = ndl * ndl * (3.0 - 2.0 * ndl) * 0.35 + ndl * 0.65;
    float sh = roomShadow(u, shadowMap, P, N);
    float3 keyCol = float3(1.0, 0.95, 0.88) * u.keyDir.w;
    float3 sky = u.pal4.rgb * 0.9 + float3(0.1);
    float3 ground = u.pal2.rgb * 0.8;
    float3 amb = mix(ground, sky, N.y * 0.5 + 0.5) * 0.62;
    float3 col = albedo * (amb * ao + keyCol * ndl * sh * mix(0.55, 1.0, ao) * 0.62);

    // soft sheen from the key (floor planks) and a faint window-light fresnel
    float3 H = normalize(L + V);
    float spec = pow(saturate(dot(N, H)), 40.0) * gloss * sh * 0.22;
    float fres = pow(1.0 - saturate(dot(N, V)), 4.0) * gloss * 0.08;
    col += (keyCol * spec + u.pal4.rgb * fres) * ao;
    if ((m == 1 || m == 3) && u.camPos.w > 0.5) { col *= 1.0 - 0.62 * roomContactAO(u, heightMap, P); }

    // fog toward the background swatch
    float f = saturate((dist - u.fog.x) / (u.fog.y - u.fog.x)) * u.fog.z;
    col = mix(col, u.pal3.rgb * 0.62, f);
    return float4(col, 1.0);
}

/// Optional final-composite helper: darken screen corners. uv in 0..1.
static inline float roomVignette(float2 uv, float strength) {
    float2 d = uv - 0.5;
    return 1.0 - strength * smoothstep(0.25, 0.85, dot(d, d) * 2.0);
}
