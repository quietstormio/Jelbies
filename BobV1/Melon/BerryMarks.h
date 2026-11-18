//
//  BerryMarks.h
//  The Berry's marks (character 8, BerryLook.swift) for the matte, bath and jersey body shaders: cream seeds dotted over the body (none on the face, none on the arm lobes)
//  and a leafy green top (a cap of six lobes hanging from the crown).
//  Body mode 71 = the egg (pink, painted where the masks below say); mode 72 = a piece in the plain body colour (the walking arm capsules and foot beans:
//  MelonRenderer draws them again with the shape.w mode set to 72, so no seed is ever painted on a limb piece). Everything is in the body's REST space (Q), so the marks ride the body.
//  Include it AFTER PandaMarks.h: a seed next to the rest arm lobe is left out (pandaArmD).
//  The numbers are fitted to the "Jelmiko Lineup" picture of the Berry (2026-11-15); the leaf refitted 2026-11-16 through the real capture camera AND the body's standing lean
//  (the rest egg leans back ~15.5 degrees in every capture, so the cap that looks level in the picture is lower at the face than at the back in rest space).
//  The tiny stem nub is NOT here: it is a 3D piece for a later round.
//
#ifndef BERRY_MARKS_H
#define BERRY_MARKS_H

/// The seed mask: five rows of fifteen seeds round the body, some rows shifted by half a seed. Each seed is a small upright oval (half width 0.015 along the row, half height 0.019).
/// A seed is drawn whole or not at all: none whose centre lies on the face, none whose centre is on or right next to the rest arm lobe.
static float berrySeeds(float3 Q) {
    const float cellW = 0.41887902;                      // 2 pi / 15: fifteen seeds round the body
    // the row this height belongs to: the row's height and its shift (in seeds)
    float yr = 0.970;
    float ph = 0.5;
    if (Q.y < 0.8915) { yr = 0.813; ph = 0.5; }
    if (Q.y < 0.7345) { yr = 0.656; ph = 0.0; }
    if (Q.y < 0.585) { yr = 0.514; ph = 0.5; }
    if (Q.y < 0.4555) { yr = 0.397; ph = 0.0; }
    float dy = Q.y - yr;
    if (fabs(dy) > 0.03) { return 0.0; }
    float rho = length(Q.xz);
    float psi = atan2(Q.x, -Q.z);                        // 0 = the middle of the back
    float cell = psi / cellW - ph;
    float j = floor(cell + 0.5);
    float pc = (j + ph) * cellW;                         // the angle of this seed's centre
    float arc = (cell - j) * cellW * rho;                // the distance along the row from the seed's centre
    float xc = rho * sin(pc);
    float zc = -rho * cos(pc);
    if (zc > 0.0 && fabs(xc) < 0.43 && yr > 0.56) { return 0.0; }                 // the face stays clear (the two lowest rows run on across the tummy)
    if (pandaArmD(float3(fabs(xc), yr, zc)) < 0.045) { return 0.0; }              // the arm lobe stays clear (its crease lies at d ~ 0.02; a seed is 0.038 tall)
    float d = length(float2(arc / 0.015, dy / 0.019));
    return 1.0 - smoothstep(0.80, 1.0, d);
}

/// The leaf mask: the leafy top. Its lower edge is a broken line round the body through seven knots in `at` = |atan2(x, z)| (degrees round from the face, 0..180):
/// a notch under the stem at the face centre (y 1.235), the two front lobe tips at 26.25 degrees (1.085: the one on the +x side hangs 0.028 lower, the other 0.028 higher,
/// as drawn), a notch at 50 (1.2675), the side lobe tips at 77.38 (1.205), a notch at 89.88 (1.3213), the back lobe tips at 134.75 (1.2775) and the notch at the back centre (1.330).
/// Above y 1.335 it is all leaf (the crown under the stem); below 1.05 there is none. Crisp ~6 mm edge.
static float berryLeaf(float3 Q) {
    if (Q.y < 1.05) { return 0.0; }
    if (Q.y > 1.335) { return 1.0; }
    float at = fabs(atan2(Q.x, Q.z)) * 57.29578;
    float tip = Q.x > 0.0 ? 1.057 : 1.113;               // the two front lobe tips (1.085 -/+ 0.028)
    float edge;
    if (at < 26.25) { edge = mix(1.235, tip, at / 26.25); }
    else if (at < 50.0) { edge = mix(tip, 1.2675, (at - 26.25) / 23.75); }
    else if (at < 77.38) { edge = mix(1.2675, 1.205, (at - 50.0) / 27.38); }
    else if (at < 89.88) { edge = mix(1.205, 1.3213, (at - 77.38) / 12.5); }
    else if (at < 134.75) { edge = mix(1.3213, 1.2775, (at - 89.88) / 44.87); }
    else { edge = mix(1.2775, 1.330, (at - 134.75) / 45.25); }
    return smoothstep(edge - 0.003, edge + 0.003, Q.y);
}

/// The whole Berry paint. `col` is the shaded pink; bm 1 = the egg, 2 = a plain piece (returned as it is).
/// The cream and the green take the body's own shading (the shaded pink's luminance against the lit pink's 0.47), so the marks sit in the same light as the skin. Seeds first, the leaf on top.
static float3 berryPaint(float3 col, float3 Q, float bm) {
    if (bm > 1.5) { return col; }
    float shade = clamp(dot(col, float3(0.2126, 0.7152, 0.0722)) / 0.47, 0.6, 1.06);
    float3 c = mix(col, float3(0.973, 0.831, 0.521) * shade, berrySeeds(Q));
    return mix(c, float3(0.296, 0.737, 0.212) * shade, berryLeaf(Q));
}

#endif
