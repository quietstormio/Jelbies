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
constant float3 TE_O = float3(0.35000,1.17621,0.03588);
constant float3 TE_U = float3(0.71549,-0.59071,-0.37301);
constant float3 TE_V = float3(0.61910,0.78350,-0.05326);
constant float3 TE_F = float3(0.32371,-0.19282,0.92630);
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
#include "PandaMarks.h"

constant int fastTier [[function_constant(0)]];
// Species specialisation (tier 0 and up): a body without the lighter-front marking compiles the whole belly block out; one that is not Teddy
// compiles the ear / pom masks out. MelonRenderer picks the pipeline from the body's shape.w (= BlueBelly.mode) each frame.
constexpr sampler lutSamp(coord::normalized, filter::linear, address::repeat);
constant bool hasBelly [[function_constant(1)]];
constant bool hasTeddy [[function_constant(2)]];
// Measurement probe (GpuBodyCostTests only; 0 in the app): 1 = flat colour, 2 = no fibre, 3 = no crinkle/fibre bump, 4 = no colour-noise terms.
constant int probeMode [[function_constant(3)]];
// -FibreLUT (opt-in, changes pixels): bit 0 = value noise from a tiling texture (one fetch instead of 8 hashes), bit 1 = the fibre ridge uses one octave
// (variance-matched) instead of two.
constant int fibreMode [[function_constant(4)]];
constant bool fibreLUT = (fibreMode & 1) != 0;
constant bool fibreHalf = (fibreMode & 2) != 0;
// Jelly look (JellyLook.swift, a lab switch): function constant 5 compiles the jelly maths in. The stock pipelines never set it, so for them every
// line guarded by `jellyC` is removed at specialisation and the shader is as before. The look parameters arrive in fragment buffer 7 (4 x float4).
constant bool jellyOn [[function_constant(5)]];
constant bool jellyC = is_function_constant_defined(jellyOn) && jellyOn;

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
static float fvnoise(float3 p, texture3d<float> lut) {
    if (fibreLUT) {
        // lattice hashes from a tiling 64^3 texture: smooth the fractional part first, then ONE trilinear fetch interpolates the cell's 8 corners
        float3 i = floor(p), f = fract(p);
        float3 u = f * f * (3.0 - 2.0 * f);
        return lut.sample(lutSamp, (i + u + 0.5) * (1.0 / 64.0)).r;
    }
    float3 i = floor(p); float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float a = mix(mix(fhash3(i + float3(0,0,0)), fhash3(i + float3(1,0,0)), u.x), mix(fhash3(i + float3(0,1,0)), fhash3(i + float3(1,1,0)), u.x), u.y);
    float b = mix(mix(fhash3(i + float3(0,0,1)), fhash3(i + float3(1,0,1)), u.x), mix(fhash3(i + float3(0,1,1)), fhash3(i + float3(1,1,1)), u.x), u.y);
    return mix(a, b, u.z);
}
static float fCrinkle(float3 Q, texture3d<float> lut) { return 0.6 * fvnoise(Q * 46.0, lut) + 0.4 * fvnoise(Q * 97.0 + 3.1, lut); }
static float fRidge(float3 w, texture3d<float> lut) {
    float n = fibreHalf ? 0.5 + 0.76 * (fvnoise(w, lut) - 0.5) : 0.7 * fvnoise(w, lut) + 0.3 * fvnoise(w * 2.3 + 5.5, lut);
    return smoothstep(0.88, 0.985, 1.0 - abs(2.0 * n - 1.0));
}
static float fFibre(float3 Q, texture3d<float> lut) {
    float3 wq = Q * 72.0 + 0.7 * float3(fvnoise(Q * 14.0 + 1.7, lut), fvnoise(Q * 14.0 + 9.1, lut), fvnoise(Q * 14.0 + 4.2, lut));
    float dk = fRidge(wq, lut) * smoothstep(0.38, 0.62, fvnoise(Q * 34.0 + 7.7, lut));
    float lt = fRidge(wq * 0.93 + float3(17.3, 3.1, 9.7), lut) * smoothstep(0.38, 0.62, fvnoise(Q * 34.0 + 21.1, lut));
    return lt - dk;
}

// LEGS-BLEND (legs-blend-r1; the user's yes of 2026-11-12 to a small edit of the locked body shading at the leg / belly join).
// While a foot piece is out, the CPU finds, per leg, where the piece's surface crosses the belly along 32 directions round the leg axis (radius, height in the
// leg's frame) and the smooth-union normal there (the two surfaces' normals averaged). Every pixel of the piece and of the belly near that crossing curve is
// shaded with its normal, crease shadow and fur / paint coordinate blended toward the SAME values on both sides of the curve, so neither the lighting, the
// shadow nor the fur jumps there; above the join (up to lb[0].w) the fur coordinate is un-stretched and the normal eased toward the fitted belly.
// Fragment buffer 6, a flat float4 array: [0] (x = on, y = join mat, z = blend width m, w = calm patch height m), [1...4] world -> rest columns,
// [5, 6] leg centre (w = 1 while out), [7, 8] leg axis, [9, 10] frame x, [11...26] / [27...42] (radius, height) pairs, [43...74] / [75...106] union normals,
// [107...138] / [139...170] the fitted belly's normal above each crossing.
// lb[0].x = 0 (-LegsBlend 0, no piece out, shoes): nothing below runs (pixel-identical).
static float legBlendAt(float3 p, constant float4* lb, thread float3& nOut, thread float& wUp) {
    float wBest = 0.0, uBest = 0.0;
    float3 nb = float3(0.0, 1.0, 0.0);
    float k = lb[0].z, ku = lb[0].w;
    for (int s = 0; s < 2; s++) {
        if (lb[5 + s].w < 0.5) { continue; }
        float3 a = lb[7 + s].xyz, e1 = lb[9 + s].xyz, e2 = cross(a, e1);
        float3 q = p - lb[5 + s].xyz;
        float h = dot(q, a), x = dot(q, e1), y = dot(q, e2), rho = length(float2(x, y));
        float f = fract(atan2(y, x) / 6.2831853 + 1.0) * 32.0;
        int j0 = int(floor(f)) % 32, j1 = (j0 + 1) % 32;
        float t = fract(f);
        float4 p0 = lb[11 + 16 * s + j0 / 2], p1 = lb[11 + 16 * s + j1 / 2];
        float2 x0 = (j0 % 2 == 0) ? p0.xy : p0.zw, x1 = (j1 % 2 == 0) ? p1.xy : p1.zw;
        float2 X = mix(x0, x1, t);
        float dh = h - X.y;
        float w = 1.0 - smoothstep(0.0, k, length(float2(rho - X.x, dh)));
        float u = (ku > 0.0 && dh > 0.0) ? (1.0 - smoothstep(0.0, ku, dh)) * (1.0 - smoothstep(X.x, X.x + ku, rho)) : 0.0;
        if (max(w, u) > max(wBest, uBest)) {
            float3 nj = normalize(mix(lb[43 + 32 * s + j0].xyz, lb[43 + 32 * s + j1].xyz, t));
            float3 nu = ku > 0.0 ? normalize(mix(lb[107 + 32 * s + j0].xyz, lb[107 + 32 * s + j1].xyz, t)) : nj;
            nb = normalize(mix(nj, nu, ku > 0.0 ? clamp(dh / (0.5 * ku), 0.0, 1.0) : 0.0));
            wBest = w; uBest = u;
        }
    }
    nOut = nb;
    wUp = uBest;
    return wBest;
}

// The body of fsSoftMatteFast, shared with the see-through entry point fsSoftMatteFastSee (JellyLook.swift). `tint` = the dual-source blend factor
// (what the body lets through of the colour behind it); only the see-through jelly path writes it.
static float4 softMatteFastBody(FastJellyIn i, bool ff, constant FastUniforms& u, texture3d<float> lut, constant float4* lb, constant float4* jl, thread float4& tint) {
    tint = float4(0.0);
    float3 N = normalize(i.n);
    if (!ff) { N = -N; }
    float3 Q = i.rest;
    float mt = i.mat;
    if (lb[0].x > 0.5) {          // LEGS-BLEND (the same maths as fsSoftMatte)
        float3 nj;
        float wu;
        float wj = legBlendAt(i.wp, lb, nj, wu);
        float wn = max(wj, 0.7 * wu), wq = max(wj, wu);
        if (wq > 0.0) { N = normalize(mix(N, nj, wn)); Q = mix(Q, (float4x4(lb[1], lb[2], lb[3], lb[4]) * float4(i.wp, 1.0)).xyz, wq); mt = mix(mt, lb[0].y, wj); }
    }
    float3 Ns = N;          // JELLY: the smooth (blended) normal, before the micro bumps
    if (probeMode == 1) { return float4(0.5, 0.5, 0.5, 0.0); }
    float fb;
    if (fastTier == 0) {
        // exactly the locked fsSoftMatte
        float e = 0.012;
        float c0 = fCrinkle(Q, lut);
        float3 g = float3(fCrinkle(Q + float3(e, 0, 0), lut) - c0, fCrinkle(Q + float3(0, e, 0), lut) - c0, fCrinkle(Q + float3(0, 0, e), lut) - c0) / e;
        g -= N * dot(g, N);
        if (probeMode != 3) { N = normalize(N - g * 0.0022); }
        float ef = 0.0018;
        fb = probeMode == 2 || probeMode == 3 ? 0.0 : fFibre(Q, lut);
        if (probeMode == 0 || probeMode == 4) {
            float3 gf = float3(fFibre(Q + float3(ef, 0, 0), lut) - fb, fFibre(Q + float3(0, ef, 0), lut) - fb, fFibre(Q + float3(0, 0, ef), lut) - fb) / ef;
            gf -= N * dot(gf, N);
            N = normalize(N - gf * 0.0003);
        }
    } else {
    // surface tangent frame for the directional differences
    float3 T = normalize(cross(abs(N.y) < 0.9 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0), N));
    float3 B = cross(N, T);
    if (fastTier <= 2) {
        float e = 0.012;
        float c0 = fCrinkle(Q, lut);
        float3 g = (T * (fCrinkle(Q + T * e, lut) - c0) + B * (fCrinkle(Q + B * e, lut) - c0)) / e;
        N = normalize(N - g * 0.0022);
    }
    fb = fFibre(Q, lut);
    if (fastTier <= 1) {
        float ef = 0.0018;
        float3 gf = (T * (fFibre(Q + T * ef, lut) - fb) + B * (fFibre(Q + B * ef, lut) - fb)) / ef;
        gf -= N * dot(gf, N);
        N = normalize(N - gf * 0.0003);
    }
    }

    float3 L = normalize(u.keyDir.xyz);
    bool jelly = false;
    if (jellyC) { jelly = jl[0].x > 0.5; if (jelly) { N = normalize(mix(N, Ns, jl[1].w)); } }          // JELLY: smooth, wet surface instead of felt
    float d = dot(N, L);
    float occ = clamp(mt / 0.4, 0.0, 1.0);
    float down = clamp(-N.y, 0.0, 1.0);
    float s = clamp(0.26 + 0.80 * d - 0.5 * max(-d - 0.04, 0.0) - 0.16 * down, 0.0, 1.0);
    s *= 1.0 - 0.62 * occ;
    float3 t = pow(float3(s), float3(0.55, 1.0, 1.25));
    float3 col = mix(u.fleshDeep.rgb, u.flesh.rgb, t);
    col += float3(0.02, 0.0, -0.004) * smoothstep(0.0, 0.2, s) * (1.0 - smoothstep(0.2, 0.55, s));
    if (jellyC && jelly) {          // JELLY: light scatters inside: the unlit side is lifted and the terminator is soft (same colour ramp)
        float sj = mix(s, clamp(0.50 + 0.50 * dot(Ns, L), 0.0, 1.0) * (1.0 - 0.35 * occ), 0.55 * jl[1].x);
        col = mix(u.fleshDeep.rgb, u.flesh.rgb, pow(float3(sj), float3(0.55, 1.0, 1.25)));
        col += float3(0.02, 0.0, -0.004) * smoothstep(0.0, 0.2, sj) * (1.0 - smoothstep(0.2, 0.55, sj));
    }
    if (jellyC && jelly) {
        float sm = jl[1].w;
        if (probeMode != 4) { col *= 1.0 + (fCrinkle(Q * 1.7 + 11.0, lut) - 0.5) * 0.045 * (1.0 - 0.75 * sm); }
        col *= 1.0 + 0.04 * fb * (1.0 - sm);
    } else {
    if (probeMode != 4) { col *= 1.0 + (fCrinkle(Q * 1.7 + 11.0, lut) - 0.5) * 0.045; }
    col *= 1.0 + 0.04 * fb;
    }
    float3 jV = float3(0.0, 0.0, 1.0);
    float jThin = 0.0, jNdv = 1.0, jRim = 0.0;
    if (jellyC && jelly) {
        // JELLY: light goes through the body (lifted unlit side, soft terminator), a thicker / deeper middle, a lighter and clearer edge
        float glow = jl[1].x, sat = jl[1].z;
        jV = normalize(u.camPos.xyz - i.wp);
        jNdv = saturate(dot(Ns, jV));
        jThin = pow(1.0 - jNdv, 2.0);          // 0 in the middle, 1 at the silhouette
        float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
        float3 satc = saturate(float3(lum) + (col - lum) * 1.6);
        col = mix(col, satc, sat * (1.0 - jThin));          // a deeper, more saturated middle
        // R2: a DENSE edge (a solid jelly is deeper at the silhouette, not whiter)
        float3 deepc = mix(u.flesh.rgb, u.fleshDeep.rgb, 0.65);
        float ld = dot(deepc, float3(0.2126, 0.7152, 0.0722));
        deepc = saturate(float3(ld) + (deepc - ld) * 1.3);
        col = mix(col, deepc, jl[2].y * smoothstep(0.15, 0.9, jThin));
        // R2: light collects inside, on the side away from the lamp, low on the body (a luminous patch, still clearly blue)
        float inner = pow(saturate(dot(Ns, normalize(-L + float3(0.0, -0.35, 0.0))) * 0.5 + 0.5), 3.0) * (1.0 - 0.7 * jThin);
        col = mix(col, saturate(u.flesh.rgb * 1.28 + 0.03), saturate(0.55 * glow * inner));
        // R3: a soft bright band just inside the whole silhouette (the edge glows as if lit from behind), brightest toward the lamp
        jRim = pow(1.0 - jNdv, 2.2);
        col = mix(col, saturate(mix(u.flesh.rgb * 1.25, float3(1.0), 0.45)), jl[1].y * jRim * (0.65 + 0.35 * saturate(dot(Ns, L) * 0.5 + 0.5)));
    }
    Q = i.rest;          // LEGS-BLEND: the paint (belly / Teddy / Panda marks, mouth) keeps the unblended rest coordinate: no smear of the painted boundaries
    // Blue belly (rest space, follows the body): a lighter blue on the front of the blue Jelbie only; exists only while u.shape.w (mode: 1 = A front, 2 = B1 belly subtle, 3 = B2 belly clear) > 0.5.
    float bb = u.shape.w;
    float tn = floor(bb / 10.0 + 0.05);                  // tone: 0 = pale (k .44 toward white), 1 = D1, 2 = D2 (a lighter but still saturated sky blue)
    float bm = bb - 10.0 * tn;                           // shape mode 1...9
    float pandaPatch = 0.0;
    float jCover = 0.0, jBlush = 0.0;
    if (hasBelly && hasTeddy && tn > 4.5) {              // Panda (modes 51 / 52): the black markings, no belly (PandaMarks.h)
        col = pandaPaint(col, Q, bm, pandaPatch);
    } else if (hasBelly && bb > 0.5) {
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
        if (jellyC) { jCover = cover; }
    }
    // Blush (rest space, follows the body): a soft pink cheek tint below and outside each eye, clear of the mouth; only exists while u.seed.w (blush) > 0.
    float bl = u.seed.w;
    if (bl > 0.002 && Q.z > 0.15) {
        float2 bc = float2(abs(Q.x) - 0.315, Q.y - 0.69);
        float bd = length(bc / float2(0.078, 0.050));
        float bk = (1.0 - smoothstep(0.30, 1.0, bd)) * clamp(bl, 0.0, 1.0) * (1.0 - pandaPatch);
        float lum = dot(col, float3(0.299, 0.587, 0.114));
        col = mix(col, float3(0.95, 0.40, 0.50) * (0.55 + lum), bk * 0.62);
        if (jellyC) { jBlush = bk; }
    }
    if (jellyC && jelly) {
        // JELLY: wet highlights on the smooth normal (white, on top of the paint, not on the open mouth), a soft sky-white rim, optional see-through
        float gloss = jl[0].w, rim = jl[1].y;
        // R3: tiny bubbles inside (rest space, front of the body, clear of the face)
        if (jl[3].x > 0.0 && Q.z > 0.1) {
            const float3 bubs[3] = { float3(-0.30, 0.42, 0.028), float3(-0.33, 0.33, 0.020), float3(0.12, 0.22, 0.024) };
            float3 lt = saturate(mix(u.flesh.rgb * 1.25, float3(1.0), 0.45));
            for (int k = 0; k < 3; k++) {
                float r = length(Q.xy - bubs[k].xy) / bubs[k].z;
                float ring = smoothstep(0.75, 0.9, r) * (1.0 - smoothstep(0.95, 1.1, r));
                float fill = 1.0 - smoothstep(0.9, 1.0, r);
                float dotb = 1.0 - smoothstep(0.6, 1.0, length(Q.xy - (bubs[k].xy + float2(-0.35, 0.35) * bubs[k].z)) / (0.28 * bubs[k].z));
                float bub = jl[3].x * smoothstep(0.1, 0.15, Q.z) * (1.0 - jCover);
                col = mix(col, lt, bub * (0.55 * ring + 0.12 * fill));
                col += float3(0.7) * dotb * bub;
            }
        }
        float3 cr = float3(u.view[0][0], u.view[1][0], u.view[2][0]), cu = float3(u.view[0][1], u.view[1][1], u.view[2][1]);
        // R3: one big soft-edged tilted oval highlight up-left on the head and a small round dot below-right of it, fixed to the camera
        float3 ax = normalize(cu + cr);
        float3 Nq = normalize(Ns - ax * dot(Ns, ax) * 0.4);
        float3 Hb = normalize(jV + cu * 0.75 - cr * 0.55);
        float big = smoothstep(0.900, 0.945, dot(Nq, Hb));
        float3 Hd = normalize(jV + cu * 0.38 - cr * 0.22);
        float dot2 = smoothstep(0.9965, 0.9985, dot(Ns, Hd));
        float spec = max(big * 0.80, dot2 * 0.95) * gloss;
        spec *= 1.0 - jCover;
        // R3: a thin warm fringe at the very outside edge on the side away from the lamp
        float warm = pow(1.0 - jNdv, 5.0) * saturate(-dot(Ns, L) * 0.5 + 0.5);
        float3 rimC = jl[2].w * 0.35 * warm * float3(1.0, 0.62, 0.38);
        float see = jl[0].y;
        if (see > 0.0) {
            float a = 1.0 - see * pow(jNdv, 1.3) * (1.0 - jRim);          // opacity rises toward the edge (jl[0].z "core" is unused since round 2)
            a = max(a, saturate(spec * 2.0));
            a = mix(a, 1.0, jCover);
            a = max(a, 0.9 * jBlush);
            float3 fl = u.flesh.rgb;
            tint = float4((1.0 - a) * pow(fl / max(max(fl.r, fl.g), max(fl.b, 1e-3)), float3(jl[2].z)), 0.0);          // what shows through is filtered by the body's colour
            return float4((col * a + float3(spec) + rimC) / max(u.misc.x, 1e-3), a);
        }
        return float4((col + float3(spec) + rimC) / max(u.misc.x, 1e-3), 0.0);
    }
    return float4(col / max(u.misc.x, 1e-3), 0.0);
}

fragment float4 fsSoftMatteFast(FastJellyIn i [[stage_in]],
                                bool ff [[front_facing]],
                                constant FastUniforms& u [[buffer(0)]],
                                texture3d<float> lut [[texture(0)]],
                                constant float4* lb [[buffer(6)]],
                                constant float4* jl [[buffer(7), function_constant(jellyC)]]) {
    constant float4* jp = lb;
    if (jellyC) { jp = jl; }
    float4 tint;
    return softMatteFastBody(i, ff, u, lut, lb, jp, tint);
}

// The see-through jelly (dual-source blending: colour one + what is behind it times `tint`); built only with function constant 5 = true.
struct SeeOut { float4 c0 [[color(0), index(0)]]; float4 c1 [[color(0), index(1)]]; };
fragment SeeOut fsSoftMatteFastSee(FastJellyIn i [[stage_in]],
                                   bool ff [[front_facing]],
                                   constant FastUniforms& u [[buffer(0)]],
                                   texture3d<float> lut [[texture(0)]],
                                   constant float4* lb [[buffer(6)]],
                                   constant float4* jl [[buffer(7)]]) {
    float4 tint;
    SeeOut o;
    o.c0 = softMatteFastBody(i, ff, u, lut, lb, jl, tint);
    o.c1 = tint;
    return o;
}
