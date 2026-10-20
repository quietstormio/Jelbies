//
//  GfxJersey.metal
//  The Circuit JERSEY: a team-colour band round the egg (rest y 0.22 ... 0.51, cream trim at both edges, soft edges). The locked body shader
//  (fsSoftMatte / vsJelly in Shaders.metal) stays byte-for-byte untouched (BaseBodyLock); a Jelly that wears a jersey is drawn with these two functions
//  instead, a copy of the locked maths plus the band, and a Jelly with no jersey is drawn with the locked ones exactly as before.
//
//  The body shader has no SDF, so the band is a function of the REST position the shader already receives (Q.y) and a per-vertex flag, `egg`
//  (1 for the egg, 0 for the arm capsules and foot beans, which share the render mesh and whose rest y overlaps the band). The flag comes from a small
//  byte buffer indexed by [[vertex_id]] (no change to the vertex format). The band's top (0.51) is below the mouth keep-out (0.551).
//  The jersey ignores -FastMatte (the fast tiers only apply to jersey-less bodies).
//

#include <metal_stdlib>
using namespace metal;

struct JerseyUniforms {
    float4x4 viewProj; float4x4 view; float4x4 invViewProj; float4x4 lightVP; float4x4 topVP;
    float4 camPos; float4 camFwd; float4 keyDir; float4 screen; float4 flesh; float4 fleshDeep; float4 pale;
    float4 skin; float4 stripe; float4 seed; float4 shape; float4 misc; float4 bg; float4 shadowTint;
};
static_assert(sizeof(JerseyUniforms) == 544, "JerseyUniforms must mirror Uniforms (544 bytes)");

/// rgb = linear colour; the "deep" ones are the shadow side of the same cloth (the body shader mixes fleshDeep -> flesh by the lighting).
struct JerseyParams {
    float4 team; float4 teamDeep; float4 trim; float4 trimDeep;
    float4 band;            // x = y0, y = y1, z = edge softness, w = trim height
};

struct JerseyMeshIn {
    float3 p    [[attribute(0)]];
    float3 n    [[attribute(1)]];
    float3 rest [[attribute(2)]];
    float  mat  [[attribute(3)]];
};
struct JerseyOut {
    float4 pos [[position]];
    float3 wp;
    float3 n;
    float3 rest;
    float mat;
    float egg;
};

vertex JerseyOut vsJellyJersey(JerseyMeshIn v [[stage_in]], uint vid [[vertex_id]],
                               constant JerseyUniforms& u [[buffer(0)]], constant uchar* eggFlag [[buffer(3)]]) {
    JerseyOut o;
    o.pos = u.viewProj * float4(v.p, 1.0);
    o.wp = v.p; o.n = v.n; o.rest = v.rest; o.mat = v.mat;
    o.egg = eggFlag[vid] != 0 ? 1.0 : 0.0;
    return o;
}

// identical maths to hash3 / vnoise / matteCrinkle / matteRidge / matteFibre in Shaders.metal
static float jhash3(float3 p) {
    float3 q = fract(p * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
static float jvnoise(float3 p) {
    float3 i = floor(p); float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float a = mix(mix(jhash3(i + float3(0,0,0)), jhash3(i + float3(1,0,0)), u.x), mix(jhash3(i + float3(0,1,0)), jhash3(i + float3(1,1,0)), u.x), u.y);
    float b = mix(mix(jhash3(i + float3(0,0,1)), jhash3(i + float3(1,0,1)), u.x), mix(jhash3(i + float3(0,1,1)), jhash3(i + float3(1,1,1)), u.x), u.y);
    return mix(a, b, u.z);
}
static float jCrinkle(float3 Q) { return 0.6 * jvnoise(Q * 46.0) + 0.4 * jvnoise(Q * 97.0 + 3.1); }
static float jRidge(float3 w) {
    float n = 0.7 * jvnoise(w) + 0.3 * jvnoise(w * 2.3 + 5.5);
    return smoothstep(0.88, 0.985, 1.0 - abs(2.0 * n - 1.0));
}
static float jFibre(float3 Q) {
    float3 wq = Q * 72.0 + 0.7 * float3(jvnoise(Q * 14.0 + 1.7), jvnoise(Q * 14.0 + 9.1), jvnoise(Q * 14.0 + 4.2));
    float dk = jRidge(wq) * smoothstep(0.38, 0.62, jvnoise(Q * 34.0 + 7.7));
    float lt = jRidge(wq * 0.93 + float3(17.3, 3.1, 9.7)) * smoothstep(0.38, 0.62, jvnoise(Q * 34.0 + 21.1));
    return lt - dk;
}

fragment float4 fsSoftMatteJersey(JerseyOut i [[stage_in]],
                                  bool ff [[front_facing]],
                                  constant JerseyUniforms& u [[buffer(0)]],
                                  constant JerseyParams& jp [[buffer(1)]]) {
    float3 N = normalize(i.n);
    if (!ff) { N = -N; }
    float3 Q = i.rest;
    float e = 0.012;
    float c0 = jCrinkle(Q);
    float3 g = float3(jCrinkle(Q + float3(e, 0, 0)) - c0, jCrinkle(Q + float3(0, e, 0)) - c0, jCrinkle(Q + float3(0, 0, e)) - c0) / e;
    g -= N * dot(g, N);
    N = normalize(N - g * 0.0022);
    float fb = jFibre(Q);
    float ef = 0.0018;
    float3 gf = float3(jFibre(Q + float3(ef, 0, 0)) - fb, jFibre(Q + float3(0, ef, 0)) - fb, jFibre(Q + float3(0, 0, ef)) - fb) / ef;
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
    col += float3(0.02, 0.0, -0.004) * smoothstep(0.0, 0.2, s) * (1.0 - smoothstep(0.2, 0.55, s));
    col *= 1.0 + (jCrinkle(Q * 1.7 + 11.0) - 0.5) * 0.045;
    col *= 1.0 + 0.04 * fb;

    // ---- the jersey band (egg only)
    float y0 = jp.band.x, y1 = jp.band.y, sf = jp.band.z, th = jp.band.w;
    float inBand = smoothstep(y0 - sf, y0 + sf, Q.y) * (1.0 - smoothstep(y1 - sf, y1 + sf, Q.y)) * step(0.5, i.egg);
    if (inBand > 0.001) {
        float trimM = (1.0 - smoothstep(y0 + th - sf, y0 + th + sf, Q.y)) + smoothstep(y1 - th - sf, y1 - th + sf, Q.y);
        trimM = clamp(trimM, 0.0, 1.0);
        // cloth shaded like the body (same lighting term), then a touch of the same crinkle / fibre so it reads as knit, not paint
        float3 cloth = mix(jp.teamDeep.rgb, jp.team.rgb, t);
        float3 trim = mix(jp.trimDeep.rgb, jp.trim.rgb, t);
        float3 jc = mix(cloth, trim, trimM);
        jc *= 1.0 + (jCrinkle(Q * 1.7 + 11.0) - 0.5) * 0.06;
        jc *= 1.0 + 0.04 * fb;
        col = mix(col, jc, inBand);
    }

    // mouth: same block as the locked shader (the band never reaches it: its top is below the keep-out)
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
    return float4(col / max(u.misc.x, 1e-3), 0.0);
}
