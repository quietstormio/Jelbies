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
    // time of day (DayLight.swift); the day values are the identity
    float4 sky0;        // rgb window sky top, w = star amount
    float4 sky1;        // rgb window sky horizon, w = sky mix (0 = the palette pane)
    float4 keyCol;      // rgb key light colour
    float4 ambCol;      // rgb ambient tint, w = ambient multiplier
    float4 lamp;        // rgb lamp colour, w = glow amount
    float4 lampPos;     // xyz lamp position, w = pool radius
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
    float alpha;
    float mat [[flat]];
    float pack [[flat]];     // shoes: the body colour as 3 sRGB bytes (normal.w)
};

vertex RoomVOut roomVS(RoomVertexIn v [[stage_in]], constant RoomUniforms& u [[buffer(0)]]) {
    RoomVOut o;
    o.world = v.pos.xyz;
    o.position = u.viewProj * float4(v.pos.xyz, 1.0);
    o.normal = v.normal.xyz;
    o.ao = v.normal.w;
    o.pack = v.normal.w;
    o.color = v.color.rgb;
    o.alpha = v.color.a;
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


// ---- shoes: the paint specs evaluated per pixel (ShoeGPU.swift builds the table) ----

static float3 roomSrgbToLin(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}
static float roomSmooth(float a, float b, float x) { float t = saturate((x - a) / max(b - a, 1e-6)); return t * t * (3.0 - 2.0 * t); }
static float roomWin(float4 w, float x) {
    float r = 1.0;
    if (w.x > -100.0) { r *= roomSmooth(w.x - w.z, w.x + w.z, x); }
    if (w.y < 100.0) { r *= 1.0 - roomSmooth(w.y - w.z, w.y + w.z, x); }
    return r;
}
/// A hard edge at 0.5 that is one pixel wide on screen (so the band is crisp, never stair-stepped or shimmering).
static float roomEdge(float x) {
    float f = max(fwidth(x) * 0.75, 1e-4);
    return smoothstep(0.5 - f, 0.5 + f, x);
}

constant int ROOM_SHOE_LAYERS = 12;
constant int ROOM_SHOE_LOOK_STRIDE = 1 + 12 * 9;

static void roomShoe(constant float4* T, int look, float3 uvs, float ph, float pack, thread float3& albedo, thread float& emit) {
    float u = uvs.x, v = uvs.y, sx = uvs.z;
    int o = look * ROOM_SHOE_LOOK_STRIDE;
    float4 head = T[o];
    int n = int(head.w + 0.5);
    uint pk = uint(pack + 0.5);
    float3 body = roomSrgbToLin(float3(float((pk >> 16) & 255u), float((pk >> 8) & 255u), float(pk & 255u)) / 255.0);
    float3 c = head.rgb;
    float g = 0.0;
    for (int k = 0; k < n; k++) {
        int b = o + 1 + k * 9;
        float4 colA = T[b], fl = T[b + 1];
        float w = roomWin(T[b + 2], u) * roomWin(T[b + 3], v) * roomWin(T[b + 4], sx);
        float4 e6 = T[b + 6];
        if (e6.y > 0.5) {
            float4 el = T[b + 5];
            float dv = (v - el.x) / el.z, ds = (sx - el.y) / el.w;
            w *= 1.0 - roomSmooth(1.0 - e6.x, 1.0, sqrt(dv * dv + ds * ds));
        }
        if (e6.z > 0.5) {
            float4 b0 = T[b + 7], b1 = T[b + 8];
            float hw = e6.w, be = b1.z, m = 0.0;
            float cs[6] = { b0.x, b0.y, b0.z, b0.w, b1.x, b1.y };
            for (int j = 0; j < 6; j++) {
                if (float(j) < e6.z) { m = max(m, 1.0 - roomSmooth(hw - be, hw + be, abs(v - cs[j]))); }
            }
            w *= m;
        }
        float alpha = colA.w;
        if (fl.w > 0.0) {
            // glitter: round dots on a cell grid in the shoe's own coordinates (cell hash, anti-aliased), not a per-pixel noise
            float2 p = float2(v * 20.0, u * 13.0 + sx * 9.0);
            float2 id = floor(p), f = fract(p);
            float h = roomHash(id + 17.0);
            float2 jit = 0.32 + 0.36 * float2(roomHash(id + 3.3), roomHash(id + 9.1));
            float fw = max(fwidth(p.x), 1e-3);
            float dot_ = 1.0 - smoothstep(0.3 - fw, 0.3 + fw, length(f - jit));
            w = roomEdge(w) * step(1.0 - min(fl.w * 2.2, 0.9), h) * dot_;
        }
        float a;
        if (fl.z > 0.5) { a = w * alpha; }                         // gradients by design (sheen, shine, ombre): smooth
        else if (alpha >= 0.99) { a = fl.w > 0.0 ? w : roomEdge(w); }
        else { a = roomEdge(w / alpha) * alpha; }
        if (a <= 0.0) { continue; }
        float3 lc = fl.y > 0.5 ? body : colA.rgb;
        c += (lc - c) * min(a, 1.0);
        if (fl.x > 0.5) { g = max(g, a); } else { g *= 1.0 - min(a, 1.0); }
    }
    if (g > 0.02) {
        float3 cyan = roomSrgbToLin(float3(0.25, 0.92, 1.0)), pink = roomSrgbToLin(float3(1.0, 0.45, 0.78));
        c = mix(c, mix(cyan, pink, ph), g);
        emit = g * (0.65 + 0.35 * ph);
    }
    albedo = c;
}

fragment float4 roomFS(RoomVOut in [[stage_in]],
                       constant RoomUniforms& u [[buffer(0)]],
                       constant float4* shoeTable [[buffer(2)]],
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
    // baked AO above 1 marks an EMISSIVE vertex (the light-up sneakers' glow): the excess is the glow weight (every other mesh has ao <= 1)
    float emit = max(ao - 1.0, 0.0);
    ao = min(ao, 1.0);
    float gloss = 0.0;
    if (m >= 16) {            // a shoe: painted per pixel from its (u, v, sx), the glow phase in colour.a
        ao = 1.0; emit = 0.0;
        roomShoe(shoeTable, m - 16, in.color, in.alpha, in.pack, albedo, emit);
    }

    if (m == 4) {
        // glowing pane: emissive, only the fog-free light
        float t = saturate((P.y - 1.5) / 2.8);
        float soft = 1.0 + 0.5 * smoothstep(0.0, 1.0, t);
        float3 pane = albedo * soft * 1.25;
        if (u.sky1.w > 0.001) {
            float3 sky = mix(u.sky1.rgb, u.sky0.rgb, smoothstep(0.0, 1.0, t));
            pane = mix(pane, sky, u.sky1.w);
            if (u.sky0.w > 0.001) {      // a few stars (cell hash), only in the upper part of the sky
                float2 g = P.xy * 12.0;
                float2 id = floor(g);
                float h = roomHash(id + 3.1);
                float2 c = (fract(g) - 0.5) - (float2(roomHash(id + 7.7), roomHash(id + 1.9)) - 0.5) * 0.45;
                float star = step(0.972, h) * smoothstep(0.24, 0.0, length(c));
                pane += star * u.sky0.w * smoothstep(0.15, 0.6, t) * float3(1.0, 0.96, 0.85) * 1.7;
            }
        }
        return float4(pane, 1.0);
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
    float3 keyCol = u.keyCol.rgb * u.keyDir.w;
    float3 sky = u.pal4.rgb * 0.9 + float3(0.1);
    float3 ground = u.pal2.rgb * 0.8;
    float3 amb = mix(ground, sky, N.y * 0.5 + 0.5) * 0.62 * u.ambCol.rgb * u.ambCol.w;
    float3 col = albedo * (amb * ao + keyCol * ndl * sh * mix(0.55, 1.0, ao) * 0.62);

    // the table lamp: a warm pool of light around it, and the shade itself glows (material 5)
    if (u.lamp.w > 0.001) {
        float3 toL = u.lampPos.xyz - P;
        float d2 = dot(toL, toL);
        float pool = exp(-d2 / (u.lampPos.w * u.lampPos.w));
        float facing = saturate(dot(N, normalize(toL)) * 0.5 + 0.5);
        col += albedo * u.lamp.rgb * (u.lamp.w * pool * facing * 1.25) * ao;
        if (m == 5) { col += u.lamp.rgb * albedo * (u.lamp.w * 2.6); }
    }

    // soft sheen from the key (floor planks) and a faint window-light fresnel
    float3 H = normalize(L + V);
    float spec = pow(saturate(dot(N, H)), 40.0) * gloss * sh * 0.22;
    float fres = pow(1.0 - saturate(dot(N, V)), 4.0) * gloss * 0.08;
    col += (keyCol * spec + u.pal4.rgb * fres) * ao;
    col += albedo * emit * 1.7;
    if ((m == 1 || m == 3) && u.camPos.w > 0.5) { col *= 1.0 - 0.62 * roomContactAO(u, heightMap, P); }

    // fog toward the background swatch
    float f = saturate((dist - u.fog.x) / (u.fog.y - u.fog.x)) * u.fog.z;
    col = mix(col, u.pal3.rgb * 0.62 * u.ambCol.rgb * u.ambCol.w, f);
    return float4(col, m >= 16 ? 1.0 : in.alpha);   // alpha only matters for the blended pipeline (dining puffs / contact shadows); opaque ones are 1
}

/// Optional final-composite helper: darken screen corners. uv in 0..1.
static inline float roomVignette(float2 uv, float strength) {
    float2 d = uv - 0.5;
    return 1.0 - strength * smoothstep(0.25, 0.85, dot(d, d) * 2.0);
}
