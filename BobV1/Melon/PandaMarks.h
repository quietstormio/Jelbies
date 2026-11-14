//
//  PandaMarks.h
//  The Panda's black markings (character 6, PandaLook.swift) for the two matte body shaders (Shaders.metal fsSoftMatte, GfxBodyFast.metal fsSoftMatteFast).
//  Body mode 51 = the egg (white, painted black where the masks below say); mode 52 = a piece that is black all over (the ears, the pom, the walking arm
//  capsules and foot beans: MelonRenderer draws them again with the shape.w mode set to 52). Everything is in the body's REST space (Q), so the marks ride the body.
//  The arm and foot masks are the body's own arm / foot shapes (BobForm.armSDF / footSDF in Contracts.swift, ported), so the black stops at their crease.
//
#ifndef PANDA_MARKS_H
#define PANDA_MARKS_H

// charcoal (not pure black): the shaded white colour `col` rides through a curve so the key light still models the black form and the fibre shows
static float3 pandaBlack(float3 col) {
    return pow(max(col, float3(0.0)), float3(2.2)) * float3(0.046, 0.046, 0.054) + float3(0.0040, 0.0040, 0.0055);
}

static float pandaSmooth01(float t) { t = clamp(t, 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
static float pandaSmin(float a, float b, float k) { float h = max(k - fabs(a - b), 0.0) / k; return min(a, b) - h * h * k * 0.25; }

// BobForm.roundCone
static float pandaRoundCone(float3 p, float3 a, float3 b, float r1, float r2) {
    float3 ba = b - a; float l2 = dot(ba, ba), rr = r1 - r2, a2 = l2 - rr * rr, il2 = 1.0 / l2;
    float3 pa = p - a; float y = dot(pa, ba), z = y - l2;
    float3 w = pa * l2 - ba * y;
    float x2 = dot(w, w), y2 = y * y * l2, z2 = z * z * l2;
    float k = (rr < 0.0 ? -1.0 : 1.0) * rr * rr * x2;
    if ((z < 0.0 ? -1.0 : 1.0) * a2 * z2 > k) { return sqrt(x2 + z2) * il2 - r2; }
    if ((y < 0.0 ? -1.0 : 1.0) * a2 * y2 < k) { return sqrt(x2 + y2) * il2 - r1; }
    return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}
// BobForm.armSDF (the right arm; callers mirror x)
static float pandaArmD(float3 q) {
    const float fl = 1.15;
    float3 a = float3(0.517, 0.605, 0.06 * fl), b = float3(0.55, 0.46, 0.06 * fl);
    return pandaRoundCone(float3(q.x, q.y, q.z * fl), a, b, 0.058, 0.15) / sqrt(fl);
}
// BobForm.footSDF (the right foot; callers mirror x)
static float pandaFootD(float3 q) {
    const float footX = 0.2154, footZ = 0.075, toeLen = 0.185, heelR = 0.135, rx = 0.155;
    float v = (q.z - footZ) / (q.z >= footZ ? toeLen : heelR);
    float t = clamp((v - 0.45) / 0.55, 0.0, 1.3);
    float yy = q.y - 0.006 * t * t;
    float taper = (1.0 - 0.20 * pandaSmooth01(yy / 0.13)) * (1.0 - 0.08 * pandaSmooth01((v - 0.1) / 0.9));
    float u = (q.x - footX) / (rx * taper);
    float arch = pandaSmooth01((v + 0.1) / 1.1);
    float top = 0.260 + (0.104 - 0.260) * arch;
    float hh = top * 0.5, cy = hh * 0.80;
    float w = (yy - cy) / hh;
    float kxz = pow(pow(fabs(u), 2.1) + pow(fabs(v), 2.1), 1.0 / 2.1);
    float kn = pow(pow(kxz, 2.6) + pow(fabs(w), 2.6), 1.0 / 2.6);
    return -pandaSmin(-(kn - 1.0) * 0.10, yy, 0.02);
}

/// The eye patch mask: a soft tilted oval round each eye (eyes at |x| .215, y .82), outer end drooping, clear of the brows (y .945) and the mouth (x < .09, y < .73).
static float pandaEyePatch(float3 Q) {
    float2 p = float2(fabs(Q.x) - 0.222, Q.y - 0.800);
    const float ca = 0.883, sa = 0.469;                    // 28 degrees, the outer end lower
    float u = p.x * ca - p.y * sa, v = p.x * sa + p.y * ca;
    float d = length(float2(u / 0.130, v / 0.105));
    return (1.0 - smoothstep(0.86, 0.92, d)) * smoothstep(0.05, 0.20, Q.z);          // crisp ~7 mm edge (user 11-04: the soft grey rim looked smudged)
}
/// The shoulder band: a ring about the body between the chest and the shoulders, high on the back and kept low at the front (under the mouth).
static float pandaBand(float3 Q) {
    float cz = Q.z / max(length(Q.xz), 0.05);              // 1 = straight ahead, -1 = back
    // a saddle: low and thin across the chest (under the mouth, between the arms), wider at the sides, swooping up over the shoulders at the back (the pom sits below it, on white)
    float top = mix(0.93, 0.68, smoothstep(-1.0, -0.10, cz));
    float bottom = mix(0.66, 0.40, smoothstep(-1.0, -0.10, cz));
    // the yoke narrows into the arm: from the saddle's full height (cz -0.10) the top / bottom edges close in to the arm's own height band (y .50 ... .60), and the end (cz +0.09)
    // lies inside the arm's charcoal (arm centre z ~ .07), so the band runs INTO the shoulder like a real panda's yoke: no white wedge, no separate sharp end beside the arm.
    float into = smoothstep(-0.10, 0.08, cz);
    top = mix(top, 0.600, into); bottom = mix(bottom, 0.500, into);
    float edge = smoothstep(bottom - 0.008, bottom + 0.014, Q.y) * (1.0 - smoothstep(top - 0.016, top, Q.y));          // crisp edges: no grey halo on the white body
    return edge * (1.0 - smoothstep(0.085, 0.095, cz));          // ends inside the arm (the chest / tummy in front of the arms stays white)
}
/// Black arms and feet on the egg (the rest-space arm / foot shapes; soft over their fillet into the body).
static float pandaLimbs(float3 Q) {
    float3 q = float3(fabs(Q.x), Q.y, Q.z);
    float arm = 1.0 - smoothstep(0.017, 0.023, pandaArmD(q));         // crisp: the arm is solid charcoal out to its own crease (the body's fillet lies inside d ~ 0.02), a ~6 mm anti-aliased edge
    float foot = 1.0 - smoothstep(0.004, 0.075, pandaFootD(q));      // (a wide soft fillet: the belly's underside crumples toward a lifted foot when he walks)
    return max(arm, foot);
}

/// The feet only (pandaLimbs without the arm): the waving arm side swaps the rest-space arm mask for the per-pixel posed-arm mask (GfxBodyFast.metal armBlend).
static float pandaFeetOnly(float3 Q) {
    float3 q = float3(fabs(Q.x), Q.y, Q.z);
    return 1.0 - smoothstep(0.004, 0.075, pandaFootD(q));
}

/// The belly oval: Teddy's B2 belly (Shaders.metal / GfxBodyFast.metal belly block, crisp mode 3) maths 1:1, painted charcoal instead of cream.
static float pandaBelly(float3 Q) {
    float2 bp2 = float2(Q.x, Q.y - 0.335) / float2(0.335, 0.205);
    return (1.0 - smoothstep(0.82, 0.88, length(bp2))) * smoothstep(0.08, 0.30, Q.z);
}

/// The whole Panda paint. `col` is the shaded white; bm 1 = the egg, 2 = a black piece. `patch` returns the eye-patch weight (blush stays off it).
/// `ink` (0...1) = the raised arm's own black (GfxBodyFast.metal decodes it from the mat channel while a Panda waves): the posed arm and the join collar that the
/// arm pulls out of the egg are painted by where they ARE now (their displacement), not by the rest-space arm mask, whose crisp edge cut the stretched collar into torn teeth.
static float3 pandaPaint(float3 col, float3 Q, float bm, thread float &patch, float ink) {
    float3 blk = pandaBlack(col);
    patch = 0.0;
    if (bm > 1.5) { return blk; }
    patch = pandaEyePatch(Q);
    float m = max(max(max(patch, pandaBand(Q)), pandaLimbs(Q)), pandaBelly(Q));
    m = max(m, smoothstep(0.2, 0.6, ink));
    return mix(col, blk, m);
}
/// ARM BLEND paint (`ink` = the per-vertex ink of the mat channel): EXACTLY pandaPaint (rest-space marks + the displacement ink, the look that reads as one clean lobe) plus the posed arm's per-pixel
/// distance mask `armMask`, which only counts where the vertex ink says the skin was moved by the arm (smoothstep 0...0.2 of the decoded ink): its smooth edge replaces the ink's per-triangle edge on the
/// collar, but it can never paint skin the arm did not touch (the cone reaches 12 cm into the body: unguarded it painted a black leaf on the front skin over the buried root, with a white wedge to the arm).
/// `armSide` is unused (kept for the call sites): the rest-space arm mask stays, as before the blend.
static float3 pandaPaintArm(float3 col, float3 Q, float bm, thread float &patch, float armMask, float armSide, float ink) {
    float3 blk = pandaBlack(col);
    patch = 0.0;
    if (bm > 1.5) { return blk; }
    patch = pandaEyePatch(Q);
    float m = max(max(max(patch, pandaBand(Q)), pandaLimbs(Q)), pandaBelly(Q));
    m = max(m, smoothstep(0.2, 0.6, ink));
    m = max(m, armMask * smoothstep(0.0, 0.2, ink));
    return mix(col, blk, m);
}
static float3 pandaPaint(float3 col, float3 Q, float bm, thread float &patch) { return pandaPaint(col, Q, bm, patch, 0.0); }

/// The waving Panda's ink rides in the mat channel as a NEGATIVE value (BlobBrain.pandaInkMat: mat = ao - 4 ink for ink > 0.1; real AO is 0...0.4, Teddy's ear hollow is the only other negative
/// and is never in a Panda's egg range; the inked area's own crease AO is dropped: it is black there anyway). Negative is on purpose: a body shader that does not decode it (the locked fsSoftMatte) reads occ = 0, never a fully occluded arm.
/// `modeW` = the body mode (u.shape.w): only the Panda egg (51) is decoded.
static float pandaInkOfMat(float mat, float modeW) { return (modeW > 50.5 && modeW < 51.5 && mat < 0.0) ? clamp(-mat * 0.25, 0.0, 1.0) : 0.0; }
static float pandaAOOfMat(float mat, float ink) { return ink > 0.0 ? clamp(mat + 4.0 * ink, 0.0, 0.4) : mat; }

#endif

// ARM BLEND for the bath and jersey body shaders (panda-wave-r1): the same posed-arm cone / normal ease as GfxBodyFast.metal (fragment buffer 8: 7 float4, layout in Skinner.setWaveBlend; zeros = off).
// Returns the distance to the posed wave arm (1e3 = none) and eases `N` toward the arm's own normal within 3.5 cm; `w2` = the weight the crease AO takes toward the calm join value.
static float armBlendConeB(float3 P, constant float4* ab) {
    float sg = ab[0].y, fl = ab[0].z;
    float3 a = ab[5].xyz, b = ab[6].xyz;
    a.z *= fl; b.z *= fl;
    return pandaRoundCone(float3(P.x * sg, P.y, P.z * fl), a, b, ab[5].w, ab[6].w) / sqrt(fl);
}
constant float armBlendReachB = 0.035;
constant float armBlendOccB = 0.06 / 0.4;          // the calm AO of the join, as the shaders' occ (0...1)
static float armBlendEase(constant float4* ab, float3 wp, thread float3& N, thread float& w2) {
    w2 = 0.0;
    float dc = 1.0e3;
    if (ab[0].x > 0.5) {
        float3x3 Mw = float3x3(ab[1].xyz, ab[2].xyz, ab[3].xyz);
        float3 P = Mw * wp + ab[4].xyz;
        dc = armBlendConeB(P, ab);
        if (dc < armBlendReachB) {
            const float e = 0.003;
            float3 g = float3(armBlendConeB(P + float3(e, 0, 0), ab) - armBlendConeB(P - float3(e, 0, 0), ab), armBlendConeB(P + float3(0, e, 0), ab) - armBlendConeB(P - float3(0, e, 0), ab), armBlendConeB(P + float3(0, 0, e), ab) - armBlendConeB(P - float3(0, 0, e), ab));
            if (length(g) > 1e-6) {
                float3 gw = normalize(g * Mw);
                float w = 1.0 - smoothstep(0.0, armBlendReachB, max(dc, 0.0));
                if (dot(gw, N) > 0.0) { N = normalize(mix(N, gw, w)); }
                w2 = w * w;
            }
        }
    }
    return dc;
}
