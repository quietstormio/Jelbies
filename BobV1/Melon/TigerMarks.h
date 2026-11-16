//
//  TigerMarks.h
//  The Tiger's rust stripes (character 7, TigerLook.swift) for the matte, bath and jersey body shaders: three on the crown, two on each cheek and three bands across the back.
//  Body mode 61 = the egg (orange, striped where the masks below say); mode 62 = a piece in the plain body colour (the walking arm capsules and foot beans:
//  MelonRenderer draws them again with the shape.w mode set to 62, so no stripe is ever painted on a limb piece). Everything is in the body's REST space (Q), so the stripes ride the body.
//  Include it AFTER PandaMarks.h: the stripes stop at the rest arm's own crease (pandaArmD).
//  The numbers are fitted to the "Jelmiko Lineup" picture of the Tiger (2026-11-15); no ears, no tail.
//
#ifndef TIGER_MARKS_H
#define TIGER_MARKS_H

/// A lens with a crisp ~6 mm edge: inside where |dv| < h * k. `k` = 1 - t * t along the lens (1 at its middle, 0 at the two tips, negative beyond them).
static float tigerLens(float dv, float k, float h) {
    return 1.0 - smoothstep(-0.003, 0.003, fabs(dv) - h * k);
}
/// One cheek stripe: a lens lying along the side of the body at height `yc` (half thickness `h`). `a` = the angle from the side axis toward the face; the lens is centred at `c`,
/// reaches `sf` further toward the face and `sb` toward the back (radians). A little rounder than a parabola (power 0.85).
static float tigerCheek(float a, float y, float yc, float h, float c, float sf, float sb) {
    float t = (a - c) / (a > c ? sf : sb);
    float k = 1.0 - t * t;
    float w = k > 0.0 ? h * pow(max(k, 0.0), 0.85) : h * k;
    return 1.0 - smoothstep(-0.003, 0.003, fabs(y - yc) - w);
}
/// One band across the back: a lens wrapped round the back, at height `yc` on the spine, its centre line `rise` higher at the two tips, half thickness `h`.
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
    // the cheeks: two stripes on each side
    float a = atan2(Q.z, ax + 1.0e-5);
    float m = tigerCheek(a, Q.y, 0.892, 0.056, 6.0 * rad, 30.0 * rad, 20.5 * rad);
    m = max(m, tigerCheek(a, Q.y, 0.716, 0.051, 8.0 * rad, 31.0 * rad, 20.0 * rad));
    // the back: three bands
    float b = atan2(ax + 1.0e-5, -Q.z);
    m = max(m, tigerBand(b, Q.y, 1.140, 0.020, 0.0405, 47.0 * rad));
    m = max(m, tigerBand(b, Q.y, 0.961, 0.011, 0.045, 60.0 * rad));
    m = max(m, tigerBand(b, Q.y, 0.752, 0.0, 0.051, 58.0 * rad));
    // the crown: one upright stripe on the middle of the forehead and one leaning in from each side (45 degrees, toward the top middle); on the front only
    float tc = (Q.y - 1.1975) / 0.0825;
    float crown = tigerLens(Q.x, 1.0 - tc * tc, 0.052);
    float du = ((Q.y - 1.2325) - (ax - 0.1625)) * 0.7071 / 0.074;
    float dv = ((Q.y - 1.2325) + (ax - 0.1625)) * 0.7071;
    crown = max(crown, tigerLens(dv, 1.0 - du * du, 0.024)) * smoothstep(0.05, 0.15, Q.z);
    m = max(m, crown);
    // no stripe on the arm lobe: the paint stops at the arm's own crease (the body's fillet lies inside d ~ 0.02)
    m = m * smoothstep(0.017, 0.023, pandaArmD(float3(ax, Q.y, Q.z)));
    return mix(col, col * float3(0.607, 0.253, 0.108), m);
}

#endif
