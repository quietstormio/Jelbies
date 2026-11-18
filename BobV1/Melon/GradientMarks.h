//
//  GradientMarks.h
//  The gradient family's paint (Sunset 16, Cotton Candy 19, Ocean 20, Lemon-Lime 21, Lagoon 22; GradientLook.swift) for the matte, bath and jersey body shaders:
//  the body colour changes with its height, bottom colour at the feet through the middle stop (the palette's flesh) to the top colour at the crown.
//  Body modes 81...85 (tone 8, shape mode 1...5): the whole body is one draw (the colour follows the height of whatever piece is drawn, so a foot or limb piece takes the
//  colour of its own height). Everything is in the body's REST space (Q), so the colours ride the body.
//  THE STOPS BELOW ARE MIRRORED IN GradientLook.swift (sRGB 0...1): the two must match.
//
#ifndef GRADIENT_MARKS_H
#define GRADIENT_MARKS_H

// bm 1...5 = Sunset, Cotton Candy, Ocean, Lemon-Lime, Lagoon (body modes 81...85). `col` is the shaded body colour (the palette's flesh = the middle stop, lit);
// the paint keeps that light: col * (stop colour / middle stop). Rest space (Q): the colour rides the body. Feet and limb pieces take the colour of their own height.
static float3 gradientPaint(float3 col, float3 Q, float bm) {
    const float lift = 0.1039, height = 1.2419;                  // the rest egg (bottom, height): t = 0 at the feet, 1 at the crown
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
