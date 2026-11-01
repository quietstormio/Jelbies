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
// TEDDYEAR-BEGIN (generated from TeddyBean.shaderConstants; TeddyBeanTests checks it still matches)
constant float3 TE_O = float3(0.32355,1.19294,0.06709);
constant float3 TE_U = float3(0.76821,-0.52312,-0.36906);
constant float3 TE_V = float3(0.57131,0.82031,0.02647);
constant float3 TE_F = float3(0.28890,-0.23118,0.92903);
constant float4 TE_PC = float4(0.00000,0.49466,-0.54430,0.11200);         // the pom: rest-space centre, radius
constant float4 TE_P = float4(0.13000,0.11251,0.20435,0.03951);          // cream half width, U-cap centre height, top height, skin-line height (ear-local v)
/// Teddy's inner ear (right ear in rest space, mirrored by |x|): a clean U / half-moon, per pixel, open at the root; 0 anywhere else on the body.
static float teddyEarMask(float3 Q) {
    float3 d = float3(fabs(Q.x), Q.y, Q.z) - TE_O;
    float lx = dot(d, TE_U), ly = dot(d, TE_V), lz = dot(d, TE_F);
    if (lz < 0.0 || lz > 0.10 || fabs(lx) > 0.2 || ly < TE_P.w - 0.02 || ly > TE_P.z + 0.03) return 0.0;
    float hv = TE_P.z - TE_P.y;
    float e = ly > TE_P.y ? length(float2(lx / TE_P.x, (ly - TE_P.y) / hv)) : fabs(lx) / TE_P.x;
    float m = 1.0 - smoothstep(0.965, 1.035, e);
    return m * smoothstep(TE_P.w - 0.01, TE_P.w + 0.012, ly);
}
/// Teddy's pom: cream on the ball (rest distance <= radius), fading into the fur over the fillet at its base (~1.5 cm).
static float teddyPomMask(float3 Q) {
    float dd = length(Q - TE_PC.xyz);
    float f = 1.0 - smoothstep(TE_PC.w + 0.001, TE_PC.w + 0.015, dd);
    return f * f;
}
// TEDDYEAR-END

constant int fastTier [[function_constant(0)]];
// Species specialisation (tier 0 and up): a body without the lighter-front marking compiles the whole belly block out; one that is not Teddy
// compiles the ear / pom masks out. MelonRenderer picks the pipeline from the body's shape.w (= BlueBelly.mode) each frame.
constant bool hasBelly [[function_constant(1)]];
constant bool hasTeddy [[function_constant(2)]];
// Measurement probe (GpuBodyCostTests only; 0 in the app): 1 = flat colour, 2 = no fibre, 3 = no crinkle/fibre bump, 4 = no colour-noise terms.
constant int probeMode [[function_constant(3)]];

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
    if (probeMode == 1) { return float4(0.5, 0.5, 0.5, 0.0); }
    float fb;
    if (fastTier == 0) {
        // exactly the locked fsSoftMatte
        float e = 0.012;
        float c0 = fCrinkle(Q);
        float3 g = float3(fCrinkle(Q + float3(e, 0, 0)) - c0, fCrinkle(Q + float3(0, e, 0)) - c0, fCrinkle(Q + float3(0, 0, e)) - c0) / e;
        g -= N * dot(g, N);
        if (probeMode != 3) { N = normalize(N - g * 0.0022); }
        float ef = 0.0018;
        fb = probeMode == 2 || probeMode == 3 ? 0.0 : fFibre(Q);
        if (probeMode == 0 || probeMode == 4) {
            float3 gf = float3(fFibre(Q + float3(ef, 0, 0)) - fb, fFibre(Q + float3(0, ef, 0)) - fb, fFibre(Q + float3(0, 0, ef)) - fb) / ef;
            gf -= N * dot(gf, N);
            N = normalize(N - gf * 0.0003);
        }
    } else {
    // surface tangent frame for the directional differences
    float3 T = normalize(cross(abs(N.y) < 0.9 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0), N));
    float3 B = cross(N, T);
    if (fastTier <= 2) {
        float e = 0.012;
        float c0 = fCrinkle(Q);
        float3 g = (T * (fCrinkle(Q + T * e) - c0) + B * (fCrinkle(Q + B * e) - c0)) / e;
        N = normalize(N - g * 0.0022);
    }
    fb = fFibre(Q);
    if (fastTier <= 1) {
        float ef = 0.0018;
        float3 gf = (T * (fFibre(Q + T * ef) - fb) + B * (fFibre(Q + B * ef) - fb)) / ef;
        gf -= N * dot(gf, N);
        N = normalize(N - gf * 0.0003);
    }
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
    if (probeMode != 4) { col *= 1.0 + (fCrinkle(Q * 1.7 + 11.0) - 0.5) * 0.045; }
    col *= 1.0 + 0.04 * fb;
    // Blue belly (rest space, follows the body): a lighter blue on the front of the blue Jelbie only; exists only while u.shape.w (mode: 1 = A front, 2 = B1 belly subtle, 3 = B2 belly clear) > 0.5.
    float bb = u.shape.w;
    float tn = floor(bb / 10.0 + 0.05);                  // tone: 0 = pale (k .44 toward white), 1 = D1, 2 = D2 (a lighter but still saturated sky blue)
    float bm = bb - 10.0 * tn;                           // shape mode 1...9
    if (hasBelly && bb > 0.5) {
        float bk;
        float lk = 0.40;                                           // ~40 % toward white, applied to the shaded colour so the light blue keeps the body's shading
        if (bm < 1.5) {
            float cz = Q.z / max(length(Q.xz), 0.05);              // 1 = straight ahead, 0 = side, -1 = back
            bk = smoothstep(0.0, 0.62, cz) * (1.0 - smoothstep(0.98, 1.22, Q.y)) * smoothstep(0.02, 0.14, Q.y);
        } else if (bm > 3.5) {
            // C1 tall oval / C2 egg: one continuous marking from the belly up to the forehead (above the brows, well under the crown), B2's tone and crisp edge
            float py = (Q.y - 0.665) / 0.535;
            float hw = 0.345;
            if (bm > 4.5) { float2 ew = bm > 8.5 ? float2(0.475, 0.41) : bm > 7.5 ? float2(0.44, 0.38) : bm > 6.5 ? float2(0.41, 0.35) : (bm > 5.5 ? float2(0.375, 0.32) : float2(0.335, 0.285)); hw = mix(ew.x, ew.y, smoothstep(0.35, 1.05, Q.y)); }          // C2 / C2w (+12 %) / C2ww (+22 %) / C2w3 (+32 %) / C2w4 (+42 %)          // egg: B2's width at the belly, narrower toward the forehead
            float px = Q.x / hw;
            float dd = pow(pow(abs(px), 2.4) + pow(abs(py), 2.4), 1.0 / 2.4);
            bk = (1.0 - smoothstep(0.70, 1.0, dd)) * smoothstep(0.08, 0.30, Q.z);
            lk = 0.44;
        } else {
            bool crisp = bm > 2.5;
            float2 bp2 = (float2(Q.x, Q.y - (crisp ? 0.335 : 0.325))) / (crisp ? float2(0.335, 0.205) : float2(0.285, 0.170));
            bk = (1.0 - smoothstep(crisp ? 0.70 : 0.30, 1.0, length(bp2))) * smoothstep(0.08, 0.30, Q.z);
            lk = crisp ? 0.44 : 0.36;
        }
        float3 lt = mix(col, float3(1.0), lk);
        if (tn > 2.5) { lt = mix(col, float3(1.0, 0.92, 0.76), 0.50); }          // tone 3 (Teddy): a warm cream-tan lift of the shaded body colour
        else if (tn > 0.5) {                                          // D1 / D2: lift a little toward white, then restore the chroma so it stays a clear sky BLUE (never a white face-paint tone)
            lt = mix(col, float3(1.0), tn < 1.5 ? 0.26 : 0.16);
            float ll = dot(lt, float3(0.2126, 0.7152, 0.0722));
            lt = saturate(ll + (lt - ll) * 1.1);
        }
        float ek = hasTeddy && tn > 3.5 ? teddyEarMask(Q) : 0.0;
        float pk = hasTeddy && tn > 3.5 ? teddyPomMask(Q) : 0.0;
        col = mix(col, lt * (1.0 - ek * 0.25 * (1.0 - s) - pk * (1.0 - s) * float3(0.12, 0.20, 0.32)), max(max(bk, ek), pk));          // (the pom / inner ear keep the light falloff: the pom shades toward warm brown, never grey)
    }
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
