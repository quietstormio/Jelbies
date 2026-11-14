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

// ARM-BLEND (panda-wave-r1 spike; fast body pipeline, Panda + Blue, the keyframed wave only; -ArmBlend 0 / zeros = off, pixel-identical).
// The CPU hands over the posed wave arm in body space (Skinner.setArmBlend, fragment buffer 8, 7 float4): [0] (on, side sigma, z-flatten, grow), [1...3] world -> body linear
// columns, [4] translation, [5] (root centre, r1), [6] (tip centre, r2). Per pixel, from the DRAWN world position (not the rest coordinate: the skin that the arm pulls out keeps its
// rest coordinate), dc = distance to the posed arm's round cone (the same cone and z-flatten as pandaArmD). Two uses: (1) the Panda's black arm is dc < ~2 cm, a smooth curve hugging the arm,
// instead of the per-vertex ink; (2) the normal and the crease AO of everything within armBlendReach of the arm ease toward the arm's own normal / a calm AO, so skin and arm shade as one piece.
static float armBlendCone(float3 P, constant float4* ab) {
    float sg = ab[0].y, fl = ab[0].z;
    float3 a = ab[5].xyz, b = ab[6].xyz;
    a.z *= fl; b.z *= fl;
    return pandaRoundCone(float3(P.x * sg, P.y, P.z * fl), a, b, ab[5].w, ab[6].w) / sqrt(fl);
}
constant float armBlendReach = 0.035;          // metres from the arm surface over which the shading eases toward the arm
constant float armBlendMat = 0.06;          // the calm AO the join takes (the legs blend uses 0.10)

// The body of fsSoftMatteFast, shared with the see-through entry point fsSoftMatteFastSee (JellyLook.swift). `tint` = the dual-source blend factor
// (what the body lets through of the colour behind it); only the see-through jelly path writes it.
static float4 softMatteFastBody(FastJellyIn i, bool ff, constant FastUniforms& u, texture3d<float> lut, constant float4* lb, constant float4* jl, constant float4* ab, thread float4& tint) {
    tint = float4(0.0);
    float3 N = normalize(i.n);
    if (!ff) { N = -N; }
    float3 Q = i.rest;
    float mt = i.mat;
    float pandaInk = pandaInkOfMat(mt, hasTeddy ? u.shape.w : 0.0);          // PANDA wave: the raised arm's ink rides in the mat channel (PandaMarks.h); the crease AO is kept
    mt = pandaAOOfMat(mt, pandaInk);
    if (lb[0].x > 0.5) {          // LEGS-BLEND (the same maths as fsSoftMatte)
        float3 nj;
        float wu;
        float wj = legBlendAt(i.wp, lb, nj, wu);
        float wn = max(wj, 0.7 * wu), wq = max(wj, wu);
        if (wq > 0.0) { N = normalize(mix(N, nj, wn)); Q = mix(Q, (float4x4(lb[1], lb[2], lb[3], lb[4]) * float4(i.wp, 1.0)).xyz, wq); mt = mix(mt, lb[0].y, wj); }
    }
    float armDc = 1.0e3;          // ARM BLEND: distance to the posed wave arm (1e3 = no arm)
    if (ab[0].x > 0.5) {
        float3x3 Mw = float3x3(ab[1].xyz, ab[2].xyz, ab[3].xyz);          // world -> body (a rotation: its transpose is the way back)
        float3 P = Mw * i.wp + ab[4].xyz;
        armDc = armBlendCone(P, ab);
        if (armDc < armBlendReach) {
            const float e = 0.003;
            float3 g = float3(armBlendCone(P + float3(e, 0, 0), ab) - armBlendCone(P - float3(e, 0, 0), ab), armBlendCone(P + float3(0, e, 0), ab) - armBlendCone(P - float3(0, e, 0), ab), armBlendCone(P + float3(0, 0, e), ab) - armBlendCone(P - float3(0, 0, e), ab));
            float gl = length(g);
            if (gl > 1e-6) {
                float3 gw = normalize(g * Mw);          // body -> world (row-vector product = transpose(Mw) * g)
                float w = 1.0 - smoothstep(0.0, armBlendReach, max(armDc, 0.0));
                if (dot(gw, N) > 0.0) { N = normalize(mix(N, gw, w)); }
                mt = mix(mt, armBlendMat, w * w);
            }
        }
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
    bool jelly = false, styleA = false;
    if (jellyC) { jelly = jl[0].x > 0.5; styleA = jl[0].x > 1.5; if (jelly) { N = normalize(mix(N, Ns, jl[1].w)); } }          // JELLY: smooth, wet surface instead of felt
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
        sj = mix(sj, 0.62, jl[4].z);          // R4: a flat body (the reference has no dark side and no lit middle)
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
    float3 jV = float3(0.0, 0.0, 1.0), jCr = float3(1.0, 0.0, 0.0), jCu = float3(0.0, 1.0, 0.0);
    float jThin = 0.0, jNdv = 1.0, jRim = 0.0, jCool = 0.0;
    float3 jCoolC = float3(1.0);
    if (jellyC && jelly) {
        // JELLY (round 4, matched to the reference picture by measured numbers)
        float glow = jl[1].x, sat = jl[1].z, rimK = jl[1].y, warmK = jl[2].w;
        jV = normalize(u.camPos.xyz - i.wp);
        jCr = float3(u.view[0][0], u.view[1][0], u.view[2][0]); jCu = float3(u.view[0][1], u.view[1][1], u.view[2][1]);
        jNdv = saturate(dot(Ns, jV));
        jThin = pow(1.0 - jNdv, 2.0);          // 0 in the middle, 1 at the silhouette
        float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
        float3 satc = saturate(float3(lum) + (col - lum) * 1.6);
        col = mix(col, satc, sat * (1.0 - jThin));          // (preset 0 since round 4: `deep` below does the saturating)
        // STYLE A = round 4 (the owner's locked Blue look, copied from c567855c), B = round 5; the same switch runs in JellyFinish.h for the bath and jersey shaders
        if (styleA) {
            float Y = max(dot(col, float3(0.2126, 0.7152, 0.0722)), 1e-4);
            float3 dcol = (Y * jl[3].z) * (1.0 + jl[3].w * (col / Y - 1.0));
            col = mix(col, max(dcol, 0.0), jl[3].y);
        } else {
            // R4.1: a deeper, more saturated body colour (species-generic): darker, chroma pushed out
            float Y = max(dot(col, float3(0.2126, 0.7152, 0.0722)), 1e-4);
            // R5: species-generic: pale bodies (Pearl) keep their lightness, already saturated ones (yellow, Teddy) get less chroma push, nothing clips
            float cMax = max(col.r, max(col.g, col.b));
            float cSat = (cMax - min(col.r, min(col.g, col.b))) / max(cMax, 1e-3);
            float dkE = mix(jl[3].z, 1.0, smoothstep(0.55, 0.85, Y));
            float ckE = 1.0 + (jl[3].w - 1.0) * mix(1.0, 0.35, smoothstep(0.50, 0.72, cSat));
            float3 dcol = max((Y * dkE) * (1.0 + ckE * (col / Y - 1.0)), 0.0);
            dcol *= min(1.0, 0.96 / max(max(dcol.r, max(dcol.g, dcol.b)), 1e-3));
            // NEON CAP (species-generic, off at soft = deep = 0): a colour that is both bright and saturated (yellow, green) is softened and deepened; w is 0 for
            // everything at or below luminance y0 (Blue, Lavender, Teddy) and for low-chroma bodies (Pearl, Panda), so those do not change.
            if (jl[6].x > 0.0 || jl[6].y > 0.0) {
                float nY = dot(dcol, float3(0.2126, 0.7152, 0.0722));
                float nM = max(dcol.r, max(dcol.g, dcol.b));
                float nS = (nM - min(dcol.r, min(dcol.g, dcol.b))) / max(nM, 1e-3);
                float nw = smoothstep(jl[6].z, jl[6].w, nY) * smoothstep(0.30, 0.60, nS);
                dcol = (float3(nY) + (dcol - nY) * (1.0 - jl[6].x * nw)) * (1.0 - jl[6].y * nw);
            }
            col = mix(col, dcol, jl[3].y);
        }
        // R2.2: light collects inside, on the side away from the lamp, low on the body: a lighter patch of the same body colour
        float inner = pow(saturate(dot(Ns, normalize(-L + float3(0.0, -0.35, 0.0))) * 0.5 + 0.5), 3.0) * (1.0 - 0.7 * jThin);
        col = mix(col, mix(col, float3(1.0), 0.25), saturate(0.55 * glow * inner));
        // R4.2 / R4.3: a light band inside the whole silhouette, blue-white on the camera-left, peach-white on the camera-right, a thin peach line at the edge
        float band = 1.0 - smoothstep(jl[5].x, jl[5].y, jNdv);
        float side = smoothstep(-0.1, 0.6, dot(Ns, normalize(jCr + 0.3 * jCu)));
        jCoolC = saturate(col * jl[5].z + 0.03);          // lighter but keeps its chroma (the reference's band is #96B4DF, not white)
        float3 bandC = mix(jCoolC, float3(1.0, 0.86, 0.74), saturate(warmK * side));
        col = mix(col, bandC, rimK * band * (0.75 + 0.25 * saturate(dot(Ns, L) * 0.5 + 0.5)));
        col = mix(col, float3(1.0, 0.78, 0.62), saturate(warmK * 0.8 * pow(1.0 - jNdv, 4.0) * side));
        jRim = band;
    }
    Q = i.rest;          // LEGS-BLEND: the paint (belly / Teddy / Panda marks, mouth) keeps the unblended rest coordinate: no smear of the painted boundaries
    // Blue belly (rest space, follows the body): a lighter blue on the front of the blue Jelbie only; exists only while u.shape.w (mode: 1 = A front, 2 = B1 belly subtle, 3 = B2 belly clear) > 0.5.
    float bb = u.shape.w;
    float tn = floor(bb / 10.0 + 0.05);                  // tone: 0 = pale (k .44 toward white), 1 = D1, 2 = D2 (a lighter but still saturated sky blue)
    float bm = bb - 10.0 * tn;                           // shape mode 1...9
    float pandaPatch = 0.0;
    float jCover = 0.0, jBlush = 0.0;
    if (hasBelly && hasTeddy && tn > 4.5) {              // Panda (modes 51 / 52): the black markings, no belly (PandaMarks.h)
        if (ab[0].x > 0.5) { col = pandaPaintArm(col, Q, bm, pandaPatch, 1.0 - smoothstep(0.017, 0.023, armDc), ab[0].y); }          // ARM BLEND: the posed arm's own per-pixel mask
        else { col = pandaPaint(col, Q, bm, pandaPatch, pandaInk); }
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
        float pm = max(max(bk, ek), pk);
        if (jellyC && jelly) { pm *= (tn > 2.5 ? 0.85 : jl[4].w); }          // R4: the jelly body keeps only a hint of the lighter belly / forehead paint
        col = mix(col, lt * (1.0 - ek * 0.25 * (1.0 - s) - pk * (1.0 - s) * float3(0.12, 0.20, 0.32)), pm);          // (the pom / inner ear keep the light falloff: the pom shades toward warm brown, never grey)
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
        // JELLY: highlights, bubbles, optional see-through
        float gloss = jl[0].w;
        // R4.5: tiny bubbles inside (rest space, front of the body, clear of the face): a ring, a faint fill and a white dot at the upper left
        if (jl[3].x > 0.0 && Q.z > 0.1) {
            const float3 bubs[3] = { float3(-0.30, 0.42, 0.036), float3(-0.33, 0.32, 0.028), float3(-0.10, 0.22, 0.030) };
            for (int k = 0; k < 3; k++) {
                float r = length(Q.xy - bubs[k].xy) / bubs[k].z;
                float ring = smoothstep(0.70, 0.88, r) * (1.0 - smoothstep(0.95, 1.12, r));
                float fill = 1.0 - smoothstep(0.9, 1.0, r);
                float dotb = 1.0 - smoothstep(0.55, 1.0, length(Q.xy - (bubs[k].xy + float2(-0.38, 0.38) * bubs[k].z)) / (0.24 * bubs[k].z));
                float bub = jl[3].x * smoothstep(0.1, 0.15, Q.z) * (1.0 - jCover);
                col = mix(col, mix(col, float3(1.0), 0.72), bub * (0.8 * ring + 0.15 * fill));
                col += float3(0.8) * dotb * bub;
            }
        }
        // R4.4: highlights on the face side, fixed to the camera (camera-space normal coordinates: x right, y up)
        float2 nq = float2(dot(Ns, jCr), dot(Ns, jCu)) - jl[4].xy;
        const float2 hax = float2(0.819, 0.574);
        float2 dd = nq - (styleA ? float2(-0.03, 0.15) : float2(-0.04, 0.19));
        float2 ee = float2(dot(dd, hax), dot(dd, float2(-hax.y, hax.x))) / (styleA ? float2(0.23, 0.09) : float2(0.17, 0.066));
        float big = 1.0 - (styleA ? smoothstep(0.80, 1.0, length(ee)) : smoothstep(0.55, 1.0, length(ee)));          // R5: softer edge
        float2 dq = styleA ? (nq - float2(0.06, 0.0)) / 0.045 : (nq - float2(0.045, 0.06)) / 0.036;
        float dot2 = 1.0 - (styleA ? smoothstep(0.75, 1.0, length(dq)) : smoothstep(0.55, 1.0, length(dq)));
        float sheen = 1.0 - smoothstep(0.2, 1.0, length((nq - float2(-0.45, 0.55)) / float2(0.34, 0.26)));
        float front = step(0.05, dot(Ns, jV));
        col = mix(col, float3(1.0), 0.28 * gloss * sheen * front);
        float spec = (styleA ? max(big * 0.92, dot2 * 0.95) : max(big * 0.80, dot2 * 0.65)) * gloss * front;
        spec *= 1.0 - jCover;
        float3 rimC = float3(0.0);
        float see = jl[0].y;
        if (see > 0.0) {
            // R5: level 2 = see-through at the rim band only (core stays opaque); level 3 adds the core (jl[0].z = how much of the middle lets light through)
            float edgeT = smoothstep(0.30, 0.95, 1.0 - jNdv);
            float a = 1.0 - see * (edgeT + jl[0].z * (1.0 - edgeT) * pow(jNdv, 1.3));
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
                                constant float4* jl [[buffer(7), function_constant(jellyC)]],
                                constant float4* ab [[buffer(8)]]) {
    constant float4* jp = lb;
    if (jellyC) { jp = jl; }
    float4 tint;
    return softMatteFastBody(i, ff, u, lut, lb, jp, ab, tint);
}

// The see-through jelly (dual-source blending: colour one + what is behind it times `tint`); built only with function constant 5 = true.
struct SeeOut { float4 c0 [[color(0), index(0)]]; float4 c1 [[color(0), index(1)]]; };
fragment SeeOut fsSoftMatteFastSee(FastJellyIn i [[stage_in]],
                                   bool ff [[front_facing]],
                                   constant FastUniforms& u [[buffer(0)]],
                                   texture3d<float> lut [[texture(0)]],
                                   constant float4* lb [[buffer(6)]],
                                   constant float4* jl [[buffer(7)]],
                                   constant float4* ab [[buffer(8)]]) {
    float4 tint;
    SeeOut o;
    o.c0 = softMatteFastBody(i, ff, u, lut, lb, jl, ab, tint);
    o.c1 = tint;
    return o;
}
