//
//  JellyFinish.h
//  Jelly look (JellyLook.swift) for the body shaders other than fsSoftMatteFast: the bath shaders (dirt, soot, suds, wet, sparkle) and the jersey shader.
//  Function constant 5 compiles it in (stock pipelines never set it: every line guarded by `jellyB` is removed at specialisation, so they stay bit-identical).
//  STYLE (jl[0].x: 1 = B, round 5; 2 = A, round 4, the owner's locked Blue look): style A keeps the round-4 colour maths (jellyColourA) and highlight shapes (jellyHi);
//  both styles run in all three shader paths (plain, bath, jersey), picked per draw by the parameter buffer, never by a pipeline of their own.
//  The maths is a copy of the jelly block of fsSoftMatteFast (GfxBodyFast.metal, round 5), opaque only (the see-through levels fall back to the opaque look on these bodies).
//    jellyBase : after the matte colour and before the paint (belly, soot, jersey band): flat lit colour, saturated + lifted species colour, inner light, rim band
//    jellyTop  : last, before the exposure division: bubbles, glossy highlights (dimmed under soot)
//
#ifndef JELLY_FINISH_H
#define JELLY_FINISH_H

constant bool jfOn [[function_constant(5)]];
constant bool jellyB = is_function_constant_defined(jfOn) && jfOn;

// Round 4 body colour (style A): darker and more saturated by a plain luminance scale and chroma push (no neon cap, no clip). Copied from c567855c.
static float3 jellyColourA(float3 col, constant float4* jl) {
    float Y = max(dot(col, float3(0.2126, 0.7152, 0.0722)), 1e-4);
    float3 dcol = (Y * jl[3].z) * (1.0 + jl[3].w * (col / Y - 1.0));
    return mix(col, max(dcol, 0.0), jl[3].y);
}

// Highlight shapes: round 4 (style A) or round 5 (style B). x = the big oval, y = the small dot (0..1 each, before the strength factors).
static float2 jellyHi(float2 nq, bool styleA) {
    const float2 hax = float2(0.819, 0.574);
    float2 dd = nq - (styleA ? float2(-0.03, 0.15) : float2(-0.04, 0.19));
    float2 ee = float2(dot(dd, hax), dot(dd, float2(-hax.y, hax.x))) / (styleA ? float2(0.23, 0.09) : float2(0.17, 0.066));
    float big = 1.0 - (styleA ? smoothstep(0.80, 1.0, length(ee)) : smoothstep(0.55, 1.0, length(ee)));
    float2 dq = styleA ? (nq - float2(0.06, 0.0)) / 0.045 : (nq - float2(0.045, 0.06)) / 0.036;
    float dot2 = 1.0 - (styleA ? smoothstep(0.75, 1.0, length(dq)) : smoothstep(0.55, 1.0, length(dq)));
    return float2(big, dot2);
}

static float3 jellyBase(float3 col, float s, float occ, float3 flesh, float3 fleshDeep, float3 Ns, float3 L, float3 wp, float3 camPos, float4x4 view, constant float4* jl) {
    float glow = jl[1].x, sat = jl[1].z, rimK = jl[1].y, warmK = jl[2].w;
    float sj = mix(s, clamp(0.50 + 0.50 * dot(Ns, L), 0.0, 1.0) * (1.0 - 0.35 * occ), 0.55 * glow);
    sj = mix(sj, 0.62, jl[4].z);
    col = mix(fleshDeep, flesh, pow(float3(sj), float3(0.55, 1.0, 1.25)));
    col += float3(0.02, 0.0, -0.004) * smoothstep(0.0, 0.2, sj) * (1.0 - smoothstep(0.2, 0.55, sj));
    float3 jV = normalize(camPos - wp);
    float3 jCr = float3(view[0][0], view[1][0], view[2][0]), jCu = float3(view[0][1], view[1][1], view[2][1]);
    float jNdv = saturate(dot(Ns, jV));
    float jThin = pow(1.0 - jNdv, 2.0);
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    float3 satc = saturate(float3(lum) + (col - lum) * 1.6);
    col = mix(col, satc, sat * (1.0 - jThin));
    if (jl[0].x > 1.5) {          // style A (round 4)
        col = jellyColourA(col, jl);
    } else {
        float Y = max(dot(col, float3(0.2126, 0.7152, 0.0722)), 1e-4);
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
    float inner = pow(saturate(dot(Ns, normalize(-L + float3(0.0, -0.35, 0.0))) * 0.5 + 0.5), 3.0) * (1.0 - 0.7 * jThin);
    col = mix(col, mix(col, float3(1.0), 0.25), saturate(0.55 * glow * inner));
    float band = 1.0 - smoothstep(jl[5].x, jl[5].y, jNdv);
    float side = smoothstep(-0.1, 0.6, dot(Ns, normalize(jCr + 0.3 * jCu)));
    float3 jCoolC = saturate(col * jl[5].z + 0.03);
    float3 bandC = mix(jCoolC, float3(1.0, 0.86, 0.74), saturate(warmK * side));
    col = mix(col, bandC, rimK * band * (0.75 + 0.25 * saturate(dot(Ns, L) * 0.5 + 0.5)));
    col = mix(col, float3(1.0, 0.78, 0.62), saturate(warmK * 0.8 * pow(1.0 - jNdv, 4.0) * side));
    return col;
}

static float3 jellyTop(float3 col, float3 Ns, float3 wp, float3 camPos, float4x4 view, float3 Q, constant float4* jl, float jCover, float soot) {
    float gloss = jl[0].w * (1.0 - 0.5 * soot);
    float3 jV = normalize(camPos - wp);
    float3 jCr = float3(view[0][0], view[1][0], view[2][0]), jCu = float3(view[0][1], view[1][1], view[2][1]);
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
    float2 nq = float2(dot(Ns, jCr), dot(Ns, jCu)) - jl[4].xy;
    bool styleA = jl[0].x > 1.5;
    float2 hi = jellyHi(nq, styleA);
    float big = hi.x, dot2 = hi.y;
    float sheen = 1.0 - smoothstep(0.2, 1.0, length((nq - float2(-0.45, 0.55)) / float2(0.34, 0.26)));
    float front = step(0.05, dot(Ns, jV));
    col = mix(col, float3(1.0), 0.28 * gloss * sheen * front);
    float spec = (styleA ? max(big * 0.92, dot2 * 0.95) : max(big * 0.80, dot2 * 0.65)) * gloss * front;
    spec *= 1.0 - jCover;
    return col + float3(spec);
}
#endif
