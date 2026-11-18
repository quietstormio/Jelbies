//
//  GradientMarks.h
//  The gradient family's paint (Sunset 16, Cotton Candy 19, Ocean 20, Lemon-Lime 21, Lagoon 22; GradientLook.swift) for the matte, bath and jersey body shaders:
//  the body colour changes with its height, bottom colour at the feet through the middle stop (the palette's flesh) to the top colour at the crown.
//  Body modes 81...85 (tone 8, shape mode 1...5): the whole body is one draw (the colour follows the height of whatever piece is drawn, so a foot or limb piece takes the
//  colour of its own height). Everything is in the body's REST space (Q), so the colours ride the body.
//  Body mode 86 (shape mode 6) is Opal 12: not a height gradient but one plane wave of colour (see the bm 6 branch).
//  THE STOPS BELOW ARE MIRRORED IN GradientLook.swift (sRGB 0...1): the two must match.
//
#ifndef GRADIENT_MARKS_H
#define GRADIENT_MARKS_H

// bm 1...5 = Sunset, Cotton Candy, Ocean, Lemon-Lime, Lagoon (body modes 81...85). `col` is the shaded body colour (the palette's flesh = the middle stop, lit);
// the paint keeps that light: col * (stop colour / middle stop). Rest space (Q): the colour rides the body. Feet and limb pieces take the colour of their own height.
static float3 gradientPaint(float3 col, float3 Q, float bm) {
    const float lift = 0.1039, height = 1.2419;                  // the rest egg (bottom, height): t = 0 at the feet, 1 at the crown
    if (bm > 5.5) {          // Opal (mode 86): ONE cyclic plane wave of colour through the rest body (the same 3D wave from the front, back and side: no seam)
        // phase = 1.40 * dot(Q, n) + 0.025, n = (0.640, 0.583, 0.502); five stops pink, peach, mint, sky, lilac, the fifth blending back into the first
        const float3 opalFlesh = float3(0.871, 0.829, 0.869);   // the palette's flesh (GradientLook.swift)
        const float3 stops[5] = { float3(0.976, 0.761, 0.824), float3(0.969, 0.839, 0.753), float3(0.784, 0.902, 0.839), float3(0.769, 0.855, 0.965), float3(0.839, 0.796, 0.957) };
        float phase = 1.40 * dot(Q, float3(0.640, 0.583, 0.502)) + 0.025;
        float u = fract(phase) * 5.0;
        int i = min(int(floor(u)), 4);
        float f = u - float(i); f = f * f * (3.0 - 2.0 * f);
        float3 c = mix(stops[i], stops[(i + 1) % 5], f);
        return col * (c / opalFlesh);
    }
    float t = clamp((Q.y - lift) / height, 0.0, 1.0);
    float3 lo, mid, hi; float tLo, tMid, tHi;
    if (bm < 1.5) {          // Sunset
        lo = float3(0.988, 0.847, 0.353); mid = float3(0.976, 0.545, 0.227); hi = float3(0.933, 0.231, 0.231); tLo = 0.28; tMid = 0.52; tHi = 0.84;
    } else if (bm < 2.5) {   // Cotton Candy
        lo = float3(0.561, 0.784, 0.973); mid = float3(0.804, 0.659, 0.941); hi = float3(0.969, 0.612, 0.753); tLo = 0.30; tMid = 0.55; tHi = 0.86;
    } else if (bm < 3.5) {   // Ocean
        lo = float3(0.153, 0.224, 0.604); mid = float3(0.310, 0.663, 0.910); hi = float3(0.616, 0.922, 0.851); tLo = 0.32; tMid = 0.56; tHi = 0.86;
    } else if (bm < 4.5) {   // Lemon-Lime
        lo = float3(0.659, 0.886, 0.298); mid = float3(0.821, 0.886, 0.325); hi = float3(0.984, 0.886, 0.353); tLo = 0.36; tMid = 0.58; tHi = 0.80;
    } else {                 // Lagoon
        lo = float3(0.949, 0.420, 0.710); mid = float3(0.627, 0.439, 0.910); hi = float3(0.373, 0.878, 0.839); tLo = 0.34; tMid = 0.58; tHi = 0.86;
    }
    float3 c = t < tMid ? mix(lo, mid, smoothstep(tLo, tMid, t)) : mix(mid, hi, smoothstep(tMid, tHi, t));
    return col * (c / max(mid, float3(1.0e-3)));
}

#endif
