//
//  FinishMarks.h
//  The "finish" family's paint (Gold 10, Silver 11, Bronze 26 = the metals; Ruby 17, Emerald 23, Sapphire 24, Amethyst 25 = the jewels; FinishLook.swift) for the matte, bath and jersey
//  body shaders. Body modes 101 Gold, 102 Silver, 103 Bronze, 104 Ruby, 105 Emerald, 106 Sapphire, 107 Amethyst (tone 10, shape mode 1...7). The whole body is one draw.
//  Every look wears a few tiny white sparkle stars on the surface (fixed spots of the rest body, so they ride it). The metals add a polished mirror sheen: a studio-like banded
//  reflection (bright overhead band, dark horizon, soft bounce below) mixed into the jelly body colour. The jewels keep their deep saturated glossy jelly and only add the stars.
//  THE TINTS BELOW ARE MIRRORED IN FinishLook.swift (sRGB 0...1): the two must match.
//
#ifndef FINISH_MARKS_H
#define FINISH_MARKS_H

// One sparkle star at unit direction `dk` (from the body centre, in the body's squashed unit space) of size `sz`: a thin four-point star in the surface's tangent plane.
static float finishStar(float3 p, float3 dk, float sz) {
    float dp = dot(p, dk);
    if (dp < 0.6) { return 0.0; }
    float3 t1 = normalize(cross(float3(0.0, 1.0, 0.0), dk));
    float3 t2 = cross(dk, t1);
    float3 dd = p - dk;
    float a = abs(dot(dd, t1)) / sz, b = abs(dot(dd, t2)) / sz;
    float r = sqrt(a) + sqrt(b);
    float arms = 1.0 - smoothstep(0.55, 1.0, r);
    float core = 1.0 - smoothstep(0.0, 0.34, length(float2(a, b)));
    return saturate(arms + core);
}

// bm 1...3 = Gold, Silver, Bronze; 4...7 = Ruby, Emerald, Sapphire, Amethyst. `col` = the shaded jelly body colour (the palette's flesh, lit); N the world normal, V the unit vector to the eye, Q the rest point.
static float3 finishPaint(float3 col, float3 Q, float bm, float3 N, float3 V) {
    if (bm < 3.5) {          // the metals: a polished mirror sheen
        float3 tint = bm < 1.5 ? float3(1.00, 0.78, 0.28) : (bm < 2.5 ? float3(0.86, 0.89, 0.96) : float3(0.84, 0.47, 0.22));
        float3 R = reflect(-V, N);
        float hz = R.y;
        float sky = smoothstep(0.05, 0.75, hz);                                  // the bright overhead softbox
        float band = exp(-pow((hz - 0.22) * 5.0, 2.0));                          // a bright strip just above the horizon
        float dark = smoothstep(0.10, -0.15, hz) * smoothstep(-0.95, -0.35, hz); // the dark horizon below it
        float bounce = smoothstep(-0.45, -0.95, hz);                             // the floor's soft bounce
        float env = 0.55 + 0.55 * sky + 0.45 * band - 0.38 * dark + 0.22 * bounce;
        float fres = pow(1.0 - saturate(dot(N, V)), 3.0);
        float3 mirror = tint * env + float3(0.30) * fres;
        col = mix(col, mirror * 0.86, 0.42);
        float sp = pow(saturate(dot(N, normalize(normalize(float3(-0.4, 0.8, 0.5)) + V))), 90.0);
        col += tint * 0.25 * sp;
    }
    // the jelly look's warm / cool rim band must not tint these looks: near the silhouette the colour goes back to the look's own hue (anchor = the palette flesh, FinishLook.swift) at the shaded brightness
    float3 anchor = bm < 1.5 ? float3(0.941, 0.761, 0.235) : bm < 2.5 ? float3(0.788, 0.808, 0.839) : bm < 3.5 ? float3(0.722, 0.412, 0.180) : bm < 4.5 ? float3(0.784, 0.137, 0.310)
                  : bm < 5.5 ? float3(0.122, 0.710, 0.478) : bm < 6.5 ? float3(0.141, 0.286, 0.784) : float3(0.604, 0.271, 0.839);
    float ndv = saturate(dot(N, V));
    float lumC = dot(col, float3(0.2126, 0.7152, 0.0722)), lumA = dot(anchor, float3(0.2126, 0.7152, 0.0722));
    col = mix(col, anchor * (lumC / max(lumA, 1.0e-3)), smoothstep(0.55, 0.15, ndv) * 0.9);
    // the drawing's colour: the jelly shading above lifts and drifts every body (ruby toward pink, sapphire toward sky), so each look is pulled back to the drawing's tone (a per-channel gain on the shaded colour)
    float3 gain = bm < 1.5 ? float3(0.935, 0.81, 0.58) : bm < 2.5 ? float3(0.86, 0.91, 0.956) : bm < 3.5 ? float3(0.755, 0.55, 0.45) : bm < 4.5 ? float3(0.72, 0.29, 0.27)
                : bm < 5.5 ? float3(0.98, 0.81, 0.65) : bm < 6.5 ? float3(0.27, 0.39, 0.72) : float3(0.52, 0.29, 0.68);
    col *= gain;
    // the darker lower band round the body (the drawings' shaded belly band) and, on the back, the big soft gloss highlight
    float3 pb = normalize((Q - float3(0.0, 0.725, 0.0)) / float3(0.55, 0.62, 0.55));
    col *= 1.0 - 0.30 * smoothstep(-0.12, -0.32, pb.y) * smoothstep(-0.78, -0.50, pb.y);
    float2 gq = (float2(pb.x - 0.02, pb.y - 0.56)) / float2(0.22, 0.12);
    float gl = (1.0 - smoothstep(0.55, 1.0, length(gq))) * smoothstep(-0.25, -0.55, pb.z);
    float2 gd = (float2(pb.x - 0.03, pb.y - 0.38)) / float2(0.035, 0.028);
    gl = max(gl, (1.0 - smoothstep(0.6, 1.0, length(gd))) * smoothstep(-0.25, -0.55, pb.z));
    col = mix(col, float3(1.0), gl * 0.55);
    // the sparkle stars (every look)
    float3 p = normalize((Q - float3(0.0, 0.725, 0.0)) / float3(0.55, 0.62, 0.55));
    float st = 0.0;
    st = max(st, finishStar(p, normalize(float3(-0.30, 0.90, 0.30)), 0.085));
    st = max(st, finishStar(p, normalize(float3(0.36, -0.30, 0.88)), 0.060));
    st = max(st, finishStar(p, normalize(float3(-0.52, -0.34, 0.78)), 0.050));
    st = max(st, finishStar(p, normalize(float3(0.74, 0.52, 0.42)), 0.060));
    st = max(st, finishStar(p, normalize(float3(0.02, 0.97, -0.22)), 0.070));
    st = max(st, finishStar(p, normalize(float3(-0.52, 0.30, -0.80)), 0.075));
    st = max(st, finishStar(p, normalize(float3(0.60, 0.28, -0.75)), 0.065));
    st = max(st, finishStar(p, normalize(float3(0.18, -0.30, -0.93)), 0.055));
    st = max(st, finishStar(p, normalize(float3(-0.95, 0.12, 0.15)), 0.060));
    st = max(st, finishStar(p, normalize(float3(0.96, 0.15, -0.20)), 0.060));
    return mix(col, float3(1.0, 1.0, 1.0), st * 0.95);
}

#endif
