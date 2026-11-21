//
//  CowMarks.h
//  The cow family's paint (Moo 13, Cocoa 14, Blush 15; CowLook.swift) for the matte, bath and jersey body shaders: ONE patch layout (a few large irregular rounded patches, as on a cow)
//  in three palettes. Body modes 91 (Moo, near-black patches), 93 (Cocoa, brown), 95 (Blush, pink); tone 9, shape mode 1 / 3 / 5. The whole body is one draw (a foot or limb piece takes
//  the patch of its own rest position). Everything is in the body's REST space (Q), so the patches ride the body. The face stays clear (eyes, brows, mouth), no patch on the foot soles.
//  THE TINTS AND THE BALLS BELOW ARE MIRRORED IN CowLook.swift (sRGB 0...1): the two must match.
//
#ifndef COW_MARKS_H
#define COW_MARKS_H

// 0...1 coverage of the cow patches at rest-space point Q: a smooth union of balls (centre.xyz, radius) with a wobbly edge, then the face / sole clearances.
static float cowPatch(float3 Q) {
    const float4 balls[10] = {
        float4( 0.06, 0.66, -0.46, 0.27),     // the big back patch ...
        float4(-0.20, 0.92, -0.36, 0.17),     // ... running up toward the shoulders
        float4( 0.30, 0.38, -0.34, 0.15),     // ... and down the other flank
        float4( 0.50, 0.58, -0.02, 0.20),     // the side patch (the character's left)
        float4( 0.47, 0.40,  0.16, 0.12),     // ... trailing toward the belly
        float4(-0.41, 1.03,  0.17, 0.15),     // over one eye area (the temple, above and beside the eye; the face clearance keeps eye, brow and mouth bare)
        float4( 0.12, 1.27,  0.02, 0.10),     // the small one on the head
        float4(-0.47, 0.50, -0.14, 0.15),     // the other side, low
        float4(-0.10, 0.30, -0.45, 0.11),     // a small one near the tail end
        float4(-0.43, 0.42,  0.24, 0.12)      // one low on the front flank
    };
    float f = 1.0e3;
    for (int i = 0; i < 10; i++) {
        float d = length(Q - balls[i].xyz) - balls[i].w;
        float h = clamp(0.5 + 0.5 * (f - d) / 0.07, 0.0, 1.0);          // smooth min (k .07): neighbouring balls fuse into one irregular blob
        f = mix(f, d, h) - 0.07 * h * (1.0 - h);
    }
    f += 0.028 * sin(9.0 * Q.x + 4.0 * Q.y + 1.3) * sin(7.0 * Q.z - 5.0 * Q.y + 0.7);          // the wobbly, hand-cut edge
    float m = 1.0 - smoothstep(-0.004, 0.006, f);
    // the face stays clear: an oval round eyes, brows and mouth on the front
    float2 fp = float2(Q.x / 0.31, (Q.y - 0.80) / 0.23);
    float face = (1.0 - smoothstep(0.92, 1.08, length(fp))) * smoothstep(0.02, 0.14, Q.z);
    m *= 1.0 - face;
    m *= smoothstep(0.17, 0.23, Q.y);                                  // no patch on the foot soles
    return m;
}

// bm 1 = Moo, 3 = Cocoa, 5 = Blush. `col` is the shaded body colour (the palette's flesh, lit); the patch keeps that light: col * (patch tint / flesh).
static float3 cowPaint(float3 col, float3 Q, float bm) {
    float3 flesh, tint;
    if (bm < 2.0) { flesh = float3(0.957, 0.945, 0.925); tint = float3(0.13, 0.13, 0.16); }          // (the drawing's 0.26 / 0.26 / 0.29, stretched: the jelly shading lifts a patch toward grey)
    else if (bm < 4.0) { flesh = float3(0.953, 0.902, 0.812); tint = float3(0.40, 0.23, 0.16); }
    else { flesh = float3(0.976, 0.890, 0.910); tint = float3(0.90, 0.36, 0.52); }
    return mix(col, col * (tint / flesh), cowPatch(Q));
}

#endif
