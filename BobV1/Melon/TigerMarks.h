//
//  TigerMarks.h
//  The Tiger's rust stripes (character 7, TigerLook.swift) for the matte, bath and jersey body shaders: three on the crown, two on each cheek and three bands across the back.
//  Body mode 61 = the egg (orange, striped where the masks below say); mode 62 = a piece in the plain body colour (the walking arm capsules and foot beans:
//  MelonRenderer draws them again with the shape.w mode set to 62, so no stripe is ever painted on a limb piece). Everything is in the body's REST space (Q), so the stripes ride the body.
//  Include it AFTER PandaMarks.h: the stripes stop at the rest arm's own crease (pandaArmD).
//  The numbers are fitted to the "Jelmiko Lineup" picture of the Tiger (2026-11-15), refitted 2026-11-16 through the real capture camera AND the body's standing lean:
//  in every capture the rest egg leans back ~15.5 degrees, so a stripe that looks level in the picture lies lower toward its face end (the cheeks) or its tips (the back bands)
//  in rest space. That is why the cheek stripes slope and the band tips drop. No ears, no tail.
//  Second pass (2026-11-16): each cheek stripe fitted on its own to the drawing's thickness, gap, length and levelness in the front, side and back views
//  (an overlap score had let one thick stripe cover both drawn stripes, so they nearly touched); the middle and bottom bands wrap a little less far round the sides.
//
#ifndef TIGER_MARKS_H
#define TIGER_MARKS_H

/// A lens with a crisp ~6 mm edge: inside where |dv| < h * k. `k` = 1 - t * t along the lens (1 at its middle, 0 at the two tips, negative beyond them).
static float tigerLens(float dv, float k, float h) {
    return 1.0 - smoothstep(-0.003, 0.003, fabs(dv) - h * k);
}
/// One cheek stripe: a lens lying along the side of the body, its centre line at height `yc` where a = `c` and sloping by `s` (height per radian of a: negative = lower toward the face),
/// half thickness `h`. `a` = the angle from the side axis toward the face; the lens reaches `sf` further toward the face and `sb` toward the back (radians).
/// A little rounder than a parabola (power 0.85).
static float tigerCheek(float a, float y, float yc, float h, float c, float sf, float sb, float s) {
    float t = (a - c) / (a > c ? sf : sb);
    float k = 1.0 - t * t;
    float w = k > 0.0 ? h * pow(max(k, 0.0), 0.85) : h * k;
    return 1.0 - smoothstep(-0.003, 0.003, fabs(y - yc - s * (a - c)) - w);
}
/// One band across the back: a lens wrapped round the back, at height `yc` on the spine, its centre line `rise` higher at the two tips (negative: lower), half thickness `h`.
/// `b` = the angle from the spine; the band reaches `s` either side (radians).
static float tigerBand(float b, float y, float yc, float rise, float h, float s) {
    float t = b / s;
    return tigerLens(y - yc - rise * t * t, 1.0 - t * t, h);
}

/// The whole Tiger paint. `col` is the shaded orange; bm 1 = the egg, 2 = a plain piece (returned as it is).
/// The rust is the body's own shaded colour times a tint, so the stripes keep the light of the skin they lie on.
static float3 tigerPaint(float3 col, float3 Q, float bm) {
    if (bm > 1.5) { return col; }
    const float rad = 0.01745329;
    float ax = fabs(Q.x);
    // the cheeks: two stripes on each side (a wedge at the edge of the front view, a level spindle in the side view)
    float a = atan2(Q.z, ax + 1.0e-5);
    float m = tigerCheek(a, Q.y, 0.944, 0.0544, 9.0 * rad, 25.25 * rad, 23.0 * rad, -0.17);
    m = max(m, tigerCheek(a, Q.y, 0.746, 0.0572, 10.5 * rad, 22.0 * rad, 26.5 * rad, -0.18));
    // the back: three bands (the top one on the back of the crown)
    float b = atan2(ax + 1.0e-5, -Q.z);
    m = max(m, tigerBand(b, Q.y, 1.289, -0.0345, 0.0247, 71.0 * rad));
    m = max(m, tigerBand(b, Q.y, 1.165, -0.075, 0.038, 66.0 * rad));
    m = max(m, tigerBand(b, Q.y, 0.9842, -0.0885, 0.0465, 55.0 * rad));
    // the crown: one upright stripe on the middle of the forehead and one leaning in from each side (45 degrees, toward the top middle); on the front only
    float tc = (Q.y - 1.1735) / 0.09;
    float crown = tigerLens(Q.x, 1.0 - tc * tc, 0.061);
    float du = ((Q.y - 1.2085) - (ax - 0.17)) * 0.7071 / 0.0845;
    float dv = ((Q.y - 1.2085) + (ax - 0.17)) * 0.7071;
    crown = max(crown, tigerLens(dv, 1.0 - du * du, 0.0345)) * smoothstep(0.05, 0.15, Q.z);
    m = max(m, crown);
    // no stripe on the arm lobe: the paint stops at the arm's own crease (the body's fillet lies inside d ~ 0.02)
    m = m * smoothstep(0.017, 0.023, pandaArmD(float3(ax, Q.y, Q.z)));
    return mix(col, col * float3(0.607, 0.253, 0.108), m);
}

#endif
