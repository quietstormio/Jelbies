//
//  GfxBodyFast.metal
//  OPT-IN cheaper copies of the locked matte body shader (fsSoftMatte in Shaders.metal stays byte-for-byte untouched; BaseBodyLock).
//  Selected with -FastMatte <tier> (MelonRenderer.gfxOpt.fastMatteTier). Every tier CHANGES PIXELS a little (the micro-normal is built
//  from fewer noise samples); the default tier 0 keeps the locked shader. The per-pixel cost of fsSoftMatte is ~46 value-noise evaluations:
//  10 for the crinkle (4 evaluations x 2 octaves + the colour one) and 36 for the fibre (4 evaluations x 9), nearly all of it the
//  finite-difference gradients used for the bump normal.
//    tier 1  tangent-plane gradients: 2 directional differences in the surface plane instead of 3 axis differences + projection
//            (the projected gradient is the same quantity) -> 35 noise evaluations (-24 %)
//    tier 2  as tier 1 but the fibre bump (gf * 0.0003) is dropped; the fibre still tints the colour -> 17 evaluations (-63 %)
//    tier 3  no bump normals at all (crinkle colour + fibre colour only) -> 11 evaluations (-76 %)
//

#include <metal_stdlib>
using namespace metal;

constant int fastTier [[function_constant(0)]];

struct FastUniforms {
    float4x4 viewProj; float4x4 view; float4x4 invViewProj; float4x4 lightVP; float4x4 topVP;
    float4 camPos; float4 camFwd; float4 keyDir; float4 screen; float4 flesh; float4 fleshDeep; float4 pale;
    float4 skin; float4 stripe; float4 seed; float4 shape; float4 misc; float4 bg; float4 shadowTint;
};
static_assert(sizeof(FastUniforms) == 544, "FastUniforms must mirror Uniforms (544 bytes)");

struct FastJellyIn {
    float4 pos [[position]];
    float3 wp;
    float3 n;
    float3 rest;
    float mat;
};

// identical maths to hash3 / vnoise / matteCrinkle / matteRidge / matteFibre in Shaders.metal
static float fhash3(float3 p) {
    float3 q = fract(p * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
static float fvnoise(float3 p) {
    float3 i = floor(p); float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float a = mix(mix(fhash3(i + float3(0,0,0)), fhash3(i + float3(1,0,0)), u.x), mix(fhash3(i + float3(0,1,0)), fhash3(i + float3(1,1,0)), u.x), u.y);
    float b = mix(mix(fhash3(i + float3(0,0,1)), fhash3(i + float3(1,0,1)), u.x), mix(fhash3(i + float3(0,1,1)), fhash3(i + float3(1,1,1)), u.x), u.y);
    return mix(a, b, u.z);
}
static float fCrinkle(float3 Q) { return 0.6 * fvnoise(Q * 46.0) + 0.4 * fvnoise(Q * 97.0 + 3.1); }
static float fRidge(float3 w) {
    float n = 0.7 * fvnoise(w) + 0.3 * fvnoise(w * 2.3 + 5.5);
    return smoothstep(0.88, 0.985, 1.0 - abs(2.0 * n - 1.0));
}
static float fFibre(float3 Q) {
    float3 wq = Q * 72.0 + 0.7 * float3(fvnoise(Q * 14.0 + 1.7), fvnoise(Q * 14.0 + 9.1), fvnoise(Q * 14.0 + 4.2));
    float dk = fRidge(wq) * smoothstep(0.38, 0.62, fvnoise(Q * 34.0 + 7.7));
    float lt = fRidge(wq * 0.93 + float3(17.3, 3.1, 9.7)) * smoothstep(0.38, 0.62, fvnoise(Q * 34.0 + 21.1));
    return lt - dk;
}

fragment float4 fsSoftMatteFast(FastJellyIn i [[stage_in]],
                                bool ff [[front_facing]],
                                constant FastUniforms& u [[buffer(0)]]) {
    float3 N = normalize(i.n);
    if (!ff) { N = -N; }
    float3 Q = i.rest;
    // surface tangent frame for the directional differences
    float3 T = normalize(cross(abs(N.y) < 0.9 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0), N));
    float3 B = cross(N, T);
    if (fastTier <= 2) {
        float e = 0.012;
        float c0 = fCrinkle(Q);
        float3 g = (T * (fCrinkle(Q + T * e) - c0) + B * (fCrinkle(Q + B * e) - c0)) / e;
        N = normalize(N - g * 0.0022);
    }
    float fb = fFibre(Q);
    if (fastTier <= 1) {
        float ef = 0.0018;
        float3 gf = (T * (fFibre(Q + T * ef) - fb) + B * (fFibre(Q + B * ef) - fb)) / ef;
        gf -= N * dot(gf, N);
        N = normalize(N - gf * 0.0003);
    }

    float3 L = normalize(u.keyDir.xyz);
    float d = dot(N, L);
    float occ = clamp(i.mat / 0.4, 0.0, 1.0);
    float down = clamp(-N.y, 0.0, 1.0);
    float s = clamp(0.26 + 0.80 * d - 0.5 * max(-d - 0.04, 0.0) - 0.16 * down, 0.0, 1.0);
    s *= 1.0 - 0.62 * occ;
    float3 t = pow(float3(s), float3(0.55, 1.0, 1.25));
    float3 col = mix(u.fleshDeep.rgb, u.flesh.rgb, t);
    col += float3(0.02, 0.0, -0.004) * smoothstep(0.0, 0.2, s) * (1.0 - smoothstep(0.2, 0.55, s));
    col *= 1.0 + (fCrinkle(Q * 1.7 + 11.0) - 0.5) * 0.045;
    col *= 1.0 + 0.04 * fb;
    // mouth: same block as the locked shader
    float mo = u.stripe.w;
    if (mo > 0.002 && Q.z > 0.15) {
        float o = clamp(mo, 0.0, 1.0);
        float2 p = float2(Q.x, Q.y - 0.665);
        float hw = mix(0.030, 0.088, smoothstep(0.0, 1.0, o));
        float hh = mix(0.0045, 0.066, o * o * (3.0 - 2.0 * o));
        float2 q = p / float2(hw, hh);
        q.y *= (q.y > 0.0) ? 1.45 : 0.9;
        float dd = length(q) - 1.0;
        float aa = max(fwidth(dd) * 1.2, 0.04);
        float cover = 1.0 - smoothstep(-aa, aa, dd);
        float3 eyeC = float3(0.0423, 0.0194, 0.0144);
        float3 tongue = float3(0.13, 0.045, 0.040);
        float tg = smoothstep(-0.05, -0.75, q.y) * smoothstep(1.0, 0.35, abs(q.x)) * smoothstep(0.35, 0.8, o);
        float3 mc = mix(eyeC, tongue, tg * 0.85);
        col = mix(col, mc, cover);
    }
    // Blush (rest space, follows the body): a soft pink cheek tint below and outside each eye, clear of the mouth; only exists while u.seed.w (blush) > 0.
    float bl = u.seed.w;
    if (bl > 0.002 && Q.z > 0.15) {
        float2 bc = float2(abs(Q.x) - 0.315, Q.y - 0.69);
        float bd = length(bc / float2(0.078, 0.050));
        float bk = (1.0 - smoothstep(0.30, 1.0, bd)) * clamp(bl, 0.0, 1.0);
        float lum = dot(col, float3(0.299, 0.587, 0.114));
        col = mix(col, float3(0.95, 0.40, 0.50) * (0.55 + lum), bk * 0.62);
    }
    return float4(col / max(u.misc.x, 1e-3), 0.0);
}
