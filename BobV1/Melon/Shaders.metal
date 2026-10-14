//
//  Shaders.metal
//  Melon Jelly: MSL port of the WGSL shaders (shaders.js).
//
//  Uniforms MUST mirror `MelonUniforms` in Renderer.swift:
//  5 x float4x4 then 14 x float4 = 544 bytes.
//
//  Buffer slots: buffer(0) = Uniforms (or a bare float4x4 for the depth pass),
//  buffer(1) = dynamic vertex stream (pos+normal, stride 24) / position-only stream,
//  buffer(2) = static vertex stream (rest xyz + mat, stride 16).
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 viewProj;
    float4x4 view;
    float4x4 invViewProj;
    float4x4 lightVP;
    float4x4 topVP;
    float4 camPos;     // xyz, w = time
    float4 camFwd;
    float4 keyDir;     // xyz toward light, w = intensity
    float4 screen;     // w, h, 1/w, 1/h
    float4 flesh;
    float4 fleshDeep;
    float4 pale;
    float4 skin;
    float4 stripe;
    float4 seed;
    float4 shape;      // melon leftovers; ignored by the Bob shader
    float4 misc;       // exposure, meshAlpha, floorY, unused
    float4 bg;
    float4 shadowTint;
};
static_assert(sizeof(Uniforms) == 544, "Uniforms must be 544 bytes (see MelonUniforms in Renderer.swift)");

constant float PI = 3.14159265;

constexpr sampler linSamp(coord::normalized, filter::linear, address::clamp_to_edge);
constexpr sampler cmpSamp(coord::normalized, filter::linear, address::clamp_to_edge, compare_func::less);

// ───────────────────────── common ─────────────────────────

static float hash3(float3 p) {
    float3 q = fract(p * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

static float vnoise(float3 p) {
    float3 i = floor(p); float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float a = mix(mix(hash3(i + float3(0,0,0)), hash3(i + float3(1,0,0)), u.x), mix(hash3(i + float3(0,1,0)), hash3(i + float3(1,1,0)), u.x), u.y);
    float b = mix(mix(hash3(i + float3(0,0,1)), hash3(i + float3(1,0,1)), u.x), mix(hash3(i + float3(0,1,1)), hash3(i + float3(1,1,1)), u.x), u.y);
    return mix(a, b, u.z);
}

static float lavaN(float3 p) { return 0.7 * vnoise(p) + 0.3 * vnoise(p * 2.0 + 7.1); }
static float fbm(float3 p) {
    return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.13 + 7.1) + 0.15 * vnoise(p * 4.37 + 3.3);
}

static float softbox(float3 d, float3 c, float3 up, float2 size, float blur) {
    float cd = dot(d, c);
    if (cd <= 0.0) { return 0.0; }
    float3 t1 = normalize(cross(up, c));
    float3 t2 = cross(c, t1);
    float2 uv = float2(dot(d, t1), dot(d, t2)) / cd;
    float2 q = abs(uv) - size;
    float sd = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - 0.04;
    return 1.0 - smoothstep(-blur, blur, sd);
}

static float3 studioEnv(float3 d, float rough, float3 bg) {
    float b = 0.012 + rough * 0.55;
    float y = d.y;
    float3 col = mix(bg * 0.62, bg * 1.05, smoothstep(-0.35, 0.25, y));
    col += bg * 0.55 * (1.0 - smoothstep(0.0, 0.3, abs(y + 0.08)));
    col = mix(col, bg * 0.8, smoothstep(0.3, 1.0, y));
    col += float3(1.0, 0.985, 0.96) * 3.2 * softbox(d, normalize(float3(0.05, 1.0, -0.15)), float3(0.0, 0.0, 1.0), float2(0.55, 0.32), b);
    col += float3(1.0, 0.98, 0.95) * 3.0 * softbox(d, normalize(float3(-0.42, 0.34, -0.8)), float3(0.0, 1.0, 0.0), float2(0.7, 0.06), b);
    col += float3(1.0, 0.97, 0.93) * 4.0 * softbox(d, normalize(float3(-0.8, 0.38, -0.2)), float3(0.0, 1.0, 0.0), float2(0.08, 0.55), b);
    col += float3(0.95, 0.97, 1.0) * 1.2 * softbox(d, normalize(float3(0.85, 0.3, 0.55)), float3(0.0, 1.0, 0.0), float2(0.45, 0.5), b * 1.3);
    return col;
}

static float ggx(float3 N, float3 V, float3 L, float rough) {
    float3 H = normalize(V + L);
    float a = max(rough * rough, 0.002);
    float a2 = a * a;
    float NdH = max(dot(N, H), 0.0);
    float NdL = max(dot(N, L), 0.0);
    float NdV = max(dot(N, V), 1e-3);
    float dd = NdH * NdH * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * dd * dd);
    float k = a * 0.5;
    float G = (NdL / (NdL * (1.0 - k) + k)) * (NdV / (NdV * (1.0 - k) + k));
    return D * G / max(4.0 * NdL * NdV, 1e-3) * NdL;
}

static float linearDepth(constant Uniforms& u, float3 p) {
    return dot(p - u.camPos.xyz, u.camFwd.xyz);
}

static float2 fullscreenPos(uint i) {
    return float2(float((i << 1) & 2u), float(i & 2u)) * 2.0 - 1.0;
}

// ───────────────────────── depth (shadow / height map) ─────────────────────────

struct PosIn { float3 p [[attribute(0)]]; };

vertex float4 depthVS(PosIn v [[stage_in]], constant float4x4& m [[buffer(0)]]) {
    return m * float4(v.p, 1.0);
}

// ───────────────────────── scene ─────────────────────────

struct FSOut { float4 pos [[position]]; float2 ndc; };

vertex FSOut sceneVsFull(uint i [[vertex_id]]) {
    FSOut o;
    float2 p = fullscreenPos(i);
    o.pos = float4(p, 0.0, 1.0); o.ndc = p; return o;
}

constant float2 POISSON[16] = {
    float2(-0.94201624, -0.39906216), float2(0.94558609, -0.76890725), float2(-0.094184101, -0.92938870), float2(0.34495938, 0.29387760),
    float2(-0.91588581, 0.45771432), float2(-0.81544232, -0.87912464), float2(-0.38277543, 0.27676845), float2(0.97484398, 0.75648379),
    float2(0.44323325, -0.97511554), float2(0.53742981, -0.47373420), float2(-0.26496911, -0.41893023), float2(0.79197514, 0.19090188),
    float2(-0.24188840, 0.99706507), float2(-0.81409955, 0.91437590), float2(0.19984126, 0.78641367), float2(0.14383161, -0.14100790)
};

static float keyShadow(constant Uniforms& u, depth2d<float> shadowMap, float3 P) {
    float4 lp = u.lightVP * float4(P, 1.0);
    float2 uv = float2(lp.x * 0.5 + 0.5, 0.5 - lp.y * 0.5);
    float z = lp.z;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return 1.0; }
    uint2 idim = uint2(shadowMap.get_width(), shadowMap.get_height());
    float2 dims = float2(idim);
    float blk = 0.0; float nb = 0.0;
    for (int i = 0; i < 16; i++) {
        float2 s = uv + POISSON[i] * 0.02;
        uint2 px = min(uint2(clamp(s, float2(0.0), float2(0.999)) * dims), idim - 1);
        float d = shadowMap.read(px);
        if (d < z - 0.002) { blk += d; nb += 1.0; }
    }
    if (nb < 0.5) { return 1.0; }
    blk /= nb;
    float pen = clamp((z - blk) * 0.45, 0.003, 0.022);
    float sum = 0.0;
    float rot = hash3(P * 91.7) * 6.2831;
    float2 cs = float2(cos(rot), sin(rot));
    for (int i = 0; i < 16; i++) {
        float2 o = POISSON[i];
        float2 r = float2(o.x * cs.x - o.y * cs.y, o.x * cs.y + o.y * cs.x);
        sum += shadowMap.sample_compare(cmpSamp, uv + r * pen, z - 0.0015, level(0));
    }
    return sum / 16.0;
}

static float contactAO(constant Uniforms& u, depth2d<float> heightMap, float3 P) {
    float4 tp = u.topVP * float4(P, 1.0);
    float2 uv = float2(tp.x * 0.5 + 0.5, 0.5 - tp.y * 0.5);
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

fragment float4 fsBackground(FSOut i [[stage_in]],
                             constant Uniforms& u [[buffer(0)]],
                             depth2d<float> shadowMap [[texture(0)]],
                             depth2d<float> heightMap [[texture(1)]]) {
    float4 a = u.invViewProj * float4(i.ndc, 0.0, 1.0);
    float4 b = u.invViewProj * float4(i.ndc, 1.0, 1.0);
    float3 ro = a.xyz / a.w;
    float3 rd = normalize(b.xyz / b.w - ro);
    float3 col = u.bg.rgb;
    float dep = 1000.0;
    col *= 1.0 - (u.shadowTint.w > 1.5 ? 0.0 : 0.08) * smoothstep(0.0, 0.6, rd.y);
    if (rd.y < -1e-4) {
        float t = (u.misc.z - ro.y) / rd.y;
        float3 P = ro + rd * t;
        dep = linearDepth(u, P);
        float sh = keyShadow(u, shadowMap, P);
        float ao = contactAO(u, heightMap, P);
        bool matteMode = u.shadowTint.w > 1.5;
        if (matteMode) { sh = mix(1.0, sh, 0.08); }              // studio look: only a very soft, broad shadow
        float3 shadowCol = mix(float3(1.0), u.shadowTint.rgb, 1.0 - sh);
        float3 fl = u.bg.rgb * (0.9 + 0.1 * clamp(1.0 - length(P.xz - float2(0.0, 0.8)) * 0.12, 0.0, 1.0));
        if (matteMode) { fl = u.bg.rgb * (0.97 + 0.03 * clamp(1.0 - length(P.xz - float2(0.0, 0.8)) * 0.12, 0.0, 1.0)); }
        fl *= shadowCol;
        fl *= 1.0 - clamp(ao * (matteMode ? 0.42 : 0.72), 0.0, 0.8);
        float fade = smoothstep(7.0, 22.0, t);
        col = mix(fl, col, fade);
    }
    return float4(col, dep);
}

struct MeshIn {
    float3 p    [[attribute(0)]];
    float3 n    [[attribute(1)]];
    float3 rest [[attribute(2)]];
    float  mat  [[attribute(3)]];
};
struct MeshOut {
    float4 pos [[position]];
    float3 wp;
    float3 n;
    float3 rest;
    float  mat;
};

vertex MeshOut vsMesh(MeshIn v [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    MeshOut o;
    o.pos = u.viewProj * float4(v.p, 1.0);
    o.wp = v.p; o.n = v.n; o.rest = v.rest; o.mat = v.mat;
    return o;
}

fragment float4 fsProps(MeshOut i [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float3 N = normalize(i.n);
    float3 V = normalize(u.camPos.xyz - i.wp);
    float NdV = max(dot(N, V), 1e-3);
    float3 L = u.keyDir.xyz;
    float3 col;
    if (i.mat < 1.5) {
        // Bob's eyes: near-black lacquer (u.seed #2A2233) with a small soft sheen; the jelly above supplies most gloss.
        float dif = max(dot(N, L), 0.0) * 0.10 + 0.90;
        float fres = 0.04 + 0.96 * pow(1.0 - NdV, 5.0);
        float3 env = studioEnv(reflect(-V, N), 0.4, u.bg.rgb);
        float3 H = normalize(L + V);
        float sheen = pow(max(dot(N, H), 0.0), 60.0) * 0.25;
        col = u.seed.rgb * dif + min(env, float3(1.0)) * fres * 0.05 + sheen;
    } else if (i.mat > 3.5) {
        // Brow lines: flat matte dark brown (u.seed), barely any sheen.
        float dif = max(dot(N, L), 0.0) * 0.12 + 0.88;
        col = u.seed.rgb * dif * 1.05;
    } else {
        // Eye glint: unlit HDR white sparkle, soft edge falling back to the eye colour.
        float e = smoothstep(0.30, 0.42, NdV);
        col = mix(u.seed.rgb, float3(3.0), e);
    }
    return float4(col, linearDepth(u, i.wp));
}

// ───────────────────────── back faces → linear depth ─────────────────────────

struct BackOut { float4 pos [[position]]; float3 wp; };

vertex BackOut backVS(PosIn v [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    BackOut o; o.pos = u.viewProj * float4(v.p, 1.0); o.wp = v.p; return o;
}
fragment float4 backFS(BackOut i [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    return float4(linearDepth(u, i.wp), 0.0, 0.0, 1.0);
}

// ───────────────────────── main: copy, jelly, mesh overlay ─────────────────────────

vertex float4 mainVsFull(uint i [[vertex_id]]) {
    return float4(fullscreenPos(i), 0.0, 1.0);
}

fragment float4 fsCopy(float4 fc [[position]], texture2d<float> sceneTex [[texture(0)]]) {
    uint2 px = min(uint2(fc.xy), uint2(sceneTex.get_width() - 1, sceneTex.get_height() - 1));
    return float4(sceneTex.read(px).rgb, 1.0);
}

struct JellyOut {
    float4 pos [[position]];
    float3 wp;
    float3 n;
    float3 rest;
    float mat;
};

vertex JellyOut vsJelly(MeshIn v [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    JellyOut o;
    o.pos = u.viewProj * float4(v.p, 1.0);
    o.wp = v.p; o.n = v.n; o.rest = v.rest; o.mat = v.mat;
    return o;
}

static float2 toUV(constant Uniforms& u, float3 p) {
    float4 c = u.viewProj * float4(p, 1.0);
    float2 n = c.xy / c.w;
    return float2(n.x * 0.5 + 0.5, 0.5 - n.y * 0.5);
}

fragment float4 fsJelly(JellyOut i [[stage_in]],
                        bool ff [[front_facing]],
                        constant Uniforms& u [[buffer(0)]],
                        texture2d<float> sceneTex [[texture(0)]],
                        texture2d<float> backTex [[texture(1)]]) {
    float3 N = normalize(i.n);
    if (!ff) { N = -N; }
    float3 P = i.wp;
    float3 V = normalize(u.camPos.xyz - P);
    float3 L = u.keyDir.xyz;
    float key = u.keyDir.w;
    float NdV = max(dot(N, V), 1e-3);

    // Bob uses the SAME flesh material as the original watermelon jelly (absorption, scattering, refraction,
    // back-lit glow, sugar sparkle, Fresnel/GGX), minus the rind / pale / stripe layers.
    float3 Q = i.rest;
    float r = length(Q.xz);
    float th = atan2(Q.x, Q.z);

    float2 uv = i.pos.xy * u.screen.zw;
    uint2 sdim = uint2(sceneTex.get_width() - 1, sceneTex.get_height() - 1);
    uint2 pix = min(uint2(i.pos.xy), sdim);
    float fz = linearDepth(u, P);
    float bz = backTex.read(pix).r;
    float sz = sceneTex.read(pix).a;
    float cosv = max(dot(-V, u.camFwd.xyz), 0.35);
    float thick = clamp((min(bz, sz) - fz) / cosv, 0.0, 3.0);
    float thickBack = clamp((bz - fz) / cosv, 0.0, 3.0);

    float grain = fbm(float3(r * 26.0, th * 18.0, Q.y * 14.0));
    float grain2 = vnoise(Q * 55.0);
    float dens = 1.0 + (grain - 0.5) * 0.5 + (grain2 - 0.5) * 0.18;

    // Lava lamp colouring: slowly drifting, domain-warped noise in REST space (rides with the jelly) picks soft
    // weights for pink / yellow / blue; the blended tints then go through the same absorption / scatter / glow.
    float3 fleshC = u.flesh.rgb, deepC = u.fleshDeep.rgb;
    float scatBoost = 0.0;
    {
        float t = u.camPos.w;
        float3 a = Q * 0.6 + float3(0.0, 0.0, t * 0.03);
        float3 w = float3(lavaN(a), lavaN(a + 5.2), lavaN(a + 9.7)) - 0.5;
        float f = lavaN(Q * 0.85 + w * 1.3 + float3(0.0, -t * 0.045, 0.0));
        f = (f - 0.5) * 1.9 + 0.5 + 0.12 * sin(t * 0.3 + Q.y * 1.2);
        float3 g = (float3(f) - float3(0.12, 0.5, 0.88)) / 0.33;
        float3 wt = exp(-g * g);
        wt /= (wt.x + wt.y + wt.z);
        // wt.x deep tone, wt.y base tone, wt.z milky white (lighter absorption, a bit more scattering)
        fleshC = u.pale.rgb * wt.x + u.flesh.rgb * wt.y + u.stripe.rgb * wt.z;
        deepC = u.skin.rgb * wt.x + u.fleshDeep.rgb * wt.y + u.shape.rgb * wt.z;
        scatBoost = 1.0 * wt.z;
    }
    float3 fleshT = clamp(fleshC, float3(0.002), float3(0.999));
    float3 sigma = -log(fleshT) * 3.4 * dens;
    float scatK = 1.7 + 1.1 * scatBoost;
    float rough = 0.1;

    float ior = 1.42;
    float3 Rr = refract(-V, N, 1.0 / ior);
    // offset/blur sized by the distance to what is actually behind the surface (prop or back wall), not the full body
    float3 exitP = P + Rr * min(thick, 0.9) * 0.55;
    float2 ruv = toUV(u, exitP);
    ruv = mix(uv, ruv, 0.85);
    float blurR = (0.0002 + 0.0078 * min(thick, 1.0)) * (0.6 + scatK * 0.02);
    float3 transmitted = float3(0.0);
    float pathL = 0.0;
    // a prop (eye/bubble) just behind the surface: thin film only, so dark eyes stay dark and glints stay white
    float propK = 0.0;
    for (int k = 0; k < 7; k++) {
        float a = float(k) * 0.8976 + 0.3;
        float2 o = select(float2(cos(a), sin(a)) * blurR, float2(0.0), k == 6);
        float4 s = sceneTex.sample(linSamp, clamp(ruv + o, float2(0.001), float2(0.999)), level(0));
        // The offset tap landed on a prop (eye) much nearer than this pixel's own exit point: that prop belongs to
        // its own, un-offset pixels, so re-sample here instead of showing a displaced ghost copy of it.
        if ((s.a - fz) / cosv < thick * 0.6 - 0.03) {
            s = sceneTex.sample(linSamp, clamp(uv + o, float2(0.001), float2(0.999)), level(0));
        }
        float pl = clamp(min(thickBack, max(s.a - fz, 0.0) / cosv + 0.03), 0.0, 3.0);
        float pk = smoothstep(0.03, 0.08, length(s.rgb - float3(0.55, 0.55, 0.57)))
                 * smoothstep(0.06, 0.14, (bz - s.a) / cosv) * (1.0 - smoothstep(0.08, 0.16, (s.a - fz) / cosv));
        pl *= 1.0 - 0.7 * pk;
        propK += pk;
        transmitted += s.rgb * exp(-sigma * pl);
        pathL += pl;
    }
    transmitted /= 7.0; pathL /= 7.0; propK /= 7.0;
    float scat = (1.0 - exp(-scatK * pathL * 0.5 - scatK * 0.02)) * (1.0 - 0.75 * propK);

    float NdL = dot(N, L);
    float wrap = clamp((NdL + 0.6) / 1.6, 0.0, 1.0);
    float3 amb = u.bg.rgb * mix(0.3, 0.75, N.y * 0.5 + 0.5);
    float3 albedo = deepC;
    float3 inner = albedo * (amb + float3(1.0, 0.97, 0.92) * key * 0.45 * wrap);

    float back = pow(clamp(dot(V, -L), 0.0, 1.0), 3.0) * 1.4 + 0.25;
    float3 thinK = exp(-sigma * (pathL * 0.6 + 0.05));
    float3 glow = fleshC * thinK * back * key * 0.42 * clamp(1.0 - NdL * 0.6, 0.0, 1.0) * (1.0 - 0.8 * propK);

    float3 body = transmitted * (1.0 - scat) + inner * scat + glow;

    float3 R = reflect(-V, N);
    float3 cell = floor(Q * float3(70.0, 70.0, 70.0));
    float spark = step(0.985, hash3(cell)) * pow(max(dot(R, L), 0.0), 40.0);
    body += float3(1.0, 0.85, 0.8) * spark * 0.2;

    float F0 = 0.034;
    float F = F0 + (1.0 - F0) * pow(1.0 - NdV, 5.0);
    float3 env = studioEnv(R, rough, u.bg.rgb);
    float3 spec = ggx(N, V, L, rough) * key * float3(1.0, 0.97, 0.93);
    float3 col = body * (1.0 - F) + env * F + spec * 0.9 * (F0 / 0.04);

    return float4(col, 1.0);
}


// ───────────────────────── soft matte (Bob) ─────────────────────────
// Opaque, diffuse-only soft-vinyl skin. Writes DISPLAY-linear colour straight to the HDR target with alpha 0; the post pass
// skips the film curve for alpha-0 pixels so the reference colours come out exactly. Body vertices carry baked crease
// occlusion in `mat` (0...0.4).

static float matteCrinkle(float3 Q) {
    return 0.6 * vnoise(Q * 46.0) + 0.4 * vnoise(Q * 97.0 + 3.1);
}

// Felted-fibre micro texture: thin, short, wiggly ridge lines (domain-warped |noise|), like the reference's matted surface.
static float matteRidge(float3 w) {
    float n = 0.7 * vnoise(w) + 0.3 * vnoise(w * 2.3 + 5.5);
    return smoothstep(0.88, 0.985, 1.0 - abs(2.0 * n - 1.0));
}
// signed: lighter (+) and darker (-) short fibres
static float matteFibre(float3 Q) {
    float3 wq = Q * 72.0 + 0.7 * float3(vnoise(Q * 14.0 + 1.7), vnoise(Q * 14.0 + 9.1), vnoise(Q * 14.0 + 4.2));
    float dk = matteRidge(wq) * smoothstep(0.38, 0.62, vnoise(Q * 34.0 + 7.7));
    float lt = matteRidge(wq * 0.93 + float3(17.3, 3.1, 9.7)) * smoothstep(0.38, 0.62, vnoise(Q * 34.0 + 21.1));
    return lt - dk;
}

fragment float4 fsSoftMatte(JellyOut i [[stage_in]],
                            bool ff [[front_facing]],
                            constant Uniforms& u [[buffer(0)]]) {
    float3 N = normalize(i.n);
    if (!ff) { N = -N; }
    float3 Q = i.rest;
    // faint crinkled micro-normal in rest space (rides with the body, no streaks)
    float e = 0.012;
    float c0 = matteCrinkle(Q);
    float3 g = float3(matteCrinkle(Q + float3(e, 0, 0)) - c0, matteCrinkle(Q + float3(0, e, 0)) - c0, matteCrinkle(Q + float3(0, 0, e)) - c0) / e;
    g -= N * dot(g, N);
    N = normalize(N - g * 0.0022);
    float fb = matteFibre(Q);
    float ef = 0.0018;
    float3 gf = float3(matteFibre(Q + float3(ef, 0, 0)) - fb, matteFibre(Q + float3(0, ef, 0)) - fb, matteFibre(Q + float3(0, 0, ef)) - fb) / ef;
    gf -= N * dot(gf, N);
    N = normalize(N - gf * 0.0003);

    float3 L = normalize(u.keyDir.xyz);
    float d = dot(N, L);
    float occ = clamp(i.mat / 0.4, 0.0, 1.0);
    float down = clamp(-N.y, 0.0, 1.0);
    float s = clamp(0.26 + 0.80 * d - 0.5 * max(-d - 0.04, 0.0) - 0.16 * down, 0.0, 1.0);
    s *= 1.0 - 0.62 * occ;
    float3 t = pow(float3(s), float3(0.55, 1.0, 1.25));
    float3 col = mix(u.fleshDeep.rgb, u.flesh.rgb, t);
    // a touch of warm scatter near the terminator
    col += float3(0.02, 0.0, -0.004) * smoothstep(0.0, 0.2, s) * (1.0 - smoothstep(0.2, 0.55, s));
    col *= 1.0 + (matteCrinkle(Q * 1.7 + 11.0) - 0.5) * 0.045;
    col *= 1.0 + 0.04 * fb;
    return float4(col / max(u.misc.x, 1e-3), 0.0);
}

// Bob's face in the matte look: chocolate domed beads and raised brown brow bars. Glints are discarded.
fragment float4 fsEyesMatte(MeshOut i [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    if (i.mat > 1.5 && i.mat < 3.5) { discard_fragment(); }
    float3 N = normalize(i.n);
    float3 V = normalize(u.camPos.xyz - i.wp);
    float3 L = normalize(u.keyDir.xyz);
    float NdV = max(dot(N, V), 1e-3);
    float3 col;
    if (i.mat < 1.5) {
        float3 lo = float3(0.091, 0.041, 0.027);     // #55392E
        float3 mid = float3(0.138, 0.076, 0.054);    // #684E42
        float3 hi = float3(0.262, 0.150, 0.109);     // #8C6C5D
        float tl = dot(N, normalize(float3(-0.55, 0.65, 0.52))) * 0.5 + 0.5;
        tl = clamp((tl - 0.76) * 2.6 + 0.47, 0.0, 1.0);
        col = mix(lo, mid, smoothstep(0.12, 0.5, tl));
        col = mix(col, hi, smoothstep(0.6, 0.98, tl) * 0.9);
        col += float3(0.012) * pow(max(dot(N, normalize(L + V)), 0.0), 9.0);          // broad satin sheen, no dot
        col *= 0.55 + 0.45 * smoothstep(0.05, 0.55, NdV);                            // darker edge
        // bead set into the surface: a thin darker rim just inside the edge and a faint light rim along the very edge (strongest below)
        float rimD = smoothstep(0.03, 0.16, NdV) * (1.0 - smoothstep(0.16, 0.36, NdV));
        col *= 1.0 - 0.30 * rimD;
        float edgeL = 1.0 - smoothstep(0.03, 0.22, NdV);
        float below = smoothstep(-0.25, 0.7, -N.y);
        col = mix(col, float3(0.80, 0.60, 0.56), edgeL * (0.35 + 0.6 * below));
    } else {
        float3 base = float3(0.133, 0.070, 0.045);   // #664B3C
        float bevel = clamp(N.y * 0.5 + 0.5, 0.0, 1.0);
        col = base * (0.62 + 0.55 * smoothstep(0.2, 0.8, bevel));
    }
    return float4(col / max(u.misc.x, 1e-3), 0.0);
}

struct LineIn { float3 p [[attribute(0)]]; };
struct LOut { float4 pos [[position]]; float d; };

vertex LOut vsLine(LineIn v [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    LOut o; o.pos = u.viewProj * float4(v.p, 1.0); o.d = linearDepth(u, v.p); return o;
}
fragment float4 fsLine(LOut i [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float a = u.misc.y * mix(0.9, 0.35, clamp((i.d - 5.0) * 0.5, 0.0, 1.0));
    return float4(float3(0.04, 0.05, 0.06) * a, a);
}

// ───────────────────────── post ─────────────────────────

vertex float4 postVS(uint i [[vertex_id]]) {
    return float4(fullscreenPos(i), 0.0, 1.0);
}

static float3 neutral(float3 c0) {
    float startC = 0.8 - 0.04;
    float desat = 0.15;
    float x = min(c0.r, min(c0.g, c0.b));
    float off = select(0.04, x - 6.25 * x * x, x < 0.08);
    float3 c = c0 - off;
    float peak = max(c.r, max(c.g, c.b));
    if (peak < startC) { return c; }
    float d = 1.0 - startC;
    float np = 1.0 - d * d / (peak + d - startC);
    c *= np / peak;
    float g = 1.0 - 1.0 / (desat * (peak - np) + 1.0);
    return mix(c, float3(np), g);
}

static float3 oetf(float3 c) {
    return select(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, c * 12.92, c <= float3(0.0031308));
}

fragment float4 postFS(float4 fc [[position]],
                       constant Uniforms& u [[buffer(0)]],
                       texture2d<float> hdr [[texture(0)]]) {
    uint2 px = min(uint2(fc.xy), uint2(hdr.get_width() - 1, hdr.get_height() - 1));
    float4 hv = hdr.read(px);
    float3 c = hv.rgb * u.misc.x;
    // alpha 0 marks matte pixels that already hold display-linear colour (no film curve)
    float3 cm = clamp(c, float3(0.0), float3(1.0));
    c = u.shadowTint.w > 1.5 ? cm : mix(cm, neutral(max(c, float3(0.0))), clamp(hv.a, 0.0, 1.0));
    float3 s = oetf(clamp(c, float3(0.0), float3(1.0)));
    s += (hash3(float3(fc.xy, 1.0)) - 0.5) / 255.0;
    return float4(s, 1.0);
}
