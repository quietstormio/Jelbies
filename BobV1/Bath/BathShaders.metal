//
//  BathShaders.metal
//  Bath shading. New file so the locked body shader functions in Shaders.metal stay byte-for-byte untouched.
//    fsSoftMatteBath   Bob's matte skin + suds / wet look / sparkle. Same maths as fsSoftMatte (BaseBodyLock); the dry look keeps
//                      using the ORIGINAL pipeline, so zero bath controls are pixel-identical by construction.
//    bathVS / bathFS   the bathroom set (tiles, ceramic, fabric), translucent water, dirt, held tools, sud bubbles, spray.
//  Struct layouts mirror MelonBathParams / BathSetUniforms in Renderer.swift / BathSet.swift.
//

#include <metal_stdlib>
using namespace metal;

constant float BATH_PI = 3.14159265;

// Function constants (MelonRenderer builds one fsSoftMatteBath pipeline per combination the frame needs, from BodySlot.sootAny / foamAny /
// wet / sparkle): the unused blocks are compiled out instead of branched over per fragment, which frees registers for the live ones.
// The all-true variant is the original shader.
constant bool bathHasSoot [[function_constant(0)]];
constant bool bathHasFoam [[function_constant(1)]];
constant bool bathHasWet [[function_constant(2)]];
constant bool bathHasSparkle [[function_constant(3)]];

static float bhash3(float3 p) {
    float3 q = fract(p * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
static float3 bhash33(float3 p) {
    return float3(bhash3(p), bhash3(p + 17.31), bhash3(p + 43.77));
}
static float bvnoise(float3 p) {
    float3 i = floor(p); float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float a = mix(mix(bhash3(i + float3(0,0,0)), bhash3(i + float3(1,0,0)), u.x), mix(bhash3(i + float3(0,1,0)), bhash3(i + float3(1,1,0)), u.x), u.y);
    float b = mix(mix(bhash3(i + float3(0,0,1)), bhash3(i + float3(1,0,1)), u.x), mix(bhash3(i + float3(0,1,1)), bhash3(i + float3(1,1,1)), u.x), u.y);
    return mix(a, b, u.z);
}
static float bCrinkle(float3 Q) { return 0.6 * bvnoise(Q * 46.0) + 0.4 * bvnoise(Q * 97.0 + 3.1); }
static float bRidge(float3 w) {
    float n = 0.7 * bvnoise(w) + 0.3 * bvnoise(w * 2.3 + 5.5);
    return smoothstep(0.88, 0.985, 1.0 - abs(2.0 * n - 1.0));
}
static float bFibre(float3 Q) {
    float3 wq = Q * 72.0 + 0.7 * float3(bvnoise(Q * 14.0 + 1.7), bvnoise(Q * 14.0 + 9.1), bvnoise(Q * 14.0 + 4.2));
    float dk = bRidge(wq) * smoothstep(0.38, 0.62, bvnoise(Q * 34.0 + 7.7));
    float lt = bRidge(wq * 0.93 + float3(17.3, 3.1, 9.7)) * smoothstep(0.38, 0.62, bvnoise(Q * 34.0 + 21.1));
    return lt - dk;
}
static float bGGX(float3 N, float3 V, float3 L, float rough) {
    float3 H = normalize(V + L);
    float a = max(rough * rough, 0.002);
    float a2 = a * a;
    float NdH = max(dot(N, H), 0.0), NdL = max(dot(N, L), 0.0), NdV = max(dot(N, V), 1e-3);
    float dd = NdH * NdH * (a2 - 1.0) + 1.0;
    float D = a2 / (BATH_PI * dd * dd);
    float k = a * 0.5;
    float G = (NdL / (NdL * (1.0 - k) + k)) * (NdV / (NdV * (1.0 - k) + k));
    return D * G / max(4.0 * NdL * NdV, 1e-3) * NdL;
}

// Same layout as `Uniforms` / MelonUniforms (544 bytes).
struct BathBase {
    float4x4 viewProj; float4x4 view; float4x4 invViewProj; float4x4 lightVP; float4x4 topVP;
    float4 camPos; float4 camFwd; float4 keyDir; float4 screen; float4 flesh; float4 fleshDeep; float4 pale;
    float4 skin; float4 stripe; float4 seed; float4 shape; float4 misc; float4 bg; float4 shadowTint;
};
static_assert(sizeof(BathBase) == 544, "BathBase must mirror Uniforms (544 bytes)");

/// fragment buffer(3) of the bath body shader (MelonBathParams in Renderer.swift): 146 float4 = 2336 bytes.
struct BathParams {
    float4 a;         // wet, sparkle, foamOn, dirt (0...1)
    float4 centre;    // body centre in the REST frame (xyz); w = this Jelly's soot placement seed (0 = Bob, exactly the original spots)
    float4 foam[72];  // 12 x 24 grid, row-major (row = polar, col = azimuth), 4 cells per float4
    float4 soot[72];  // the same grid for the soot on his skin
};
static_assert(sizeof(BathParams) == 2336, "BathParams must be 2336 bytes (MelonBathParams in Renderer.swift)");

struct BathJellyIn {
    float4 pos [[position]];
    float3 wp;
    float3 n;
    float3 rest;
    float mat;
};

static float bFoamCell(constant BathParams& bp, int r, int c) {
    r = clamp(r, 0, 11);
    c = ((c % 24) + 24) % 24;
    int i = r * 24 + c;
    return bp.foam[i >> 2][i & 3];
}
static float bFoamAt(constant BathParams& bp, float3 d) {
    float l = length(d);
    if (l < 1e-5) { return 0.0; }
    float pol = acos(clamp(d.y / l, -1.0, 1.0)) / BATH_PI;
    float az = atan2(d.x, d.z); if (az < 0.0) { az += 2.0 * BATH_PI; }
    float fr = pol * 12.0 - 0.5, fc = az / (2.0 * BATH_PI) * 24.0 - 0.5;
    int r0 = int(floor(fr)), c0 = int(floor(fc));
    float tr = fr - float(r0), tc = fc - float(c0);
    float top = mix(bFoamCell(bp, r0, c0), bFoamCell(bp, r0, c0 + 1), tc);
    float bot = mix(bFoamCell(bp, r0 + 1, c0), bFoamCell(bp, r0 + 1, c0 + 1), tc);
    return mix(top, bot, tr);
}

static float bSootCell(constant BathParams& bp, int r, int c) {
    r = clamp(r, 0, 11);
    c = ((c % 24) + 24) % 24;
    int i = r * 24 + c;
    return bp.soot[i >> 2][i & 3];
}
static float bSootAt(constant BathParams& bp, float3 d) {
    float l = length(d);
    if (l < 1e-5) { return 0.0; }
    float pol = acos(clamp(d.y / l, -1.0, 1.0)) / BATH_PI;
    float az = atan2(d.x, d.z); if (az < 0.0) { az += 2.0 * BATH_PI; }
    float fr = pol * 12.0 - 0.5, fc = az / (2.0 * BATH_PI) * 24.0 - 0.5;
    int r0 = int(floor(fr)), c0 = int(floor(fc));
    float tr = fr - float(r0), tc = fc - float(c0);
    float top = mix(bSootCell(bp, r0, c0), bSootCell(bp, r0, c0 + 1), tc);
    float bot = mix(bSootCell(bp, r0 + 1, c0), bSootCell(bp, r0 + 1, c0 + 1), tc);
    return mix(top, bot, tr);
}

/// One sooty wipe: an elongated, rotated, feathered streak in the face plane (p = rest x,y), its outline domain-warped by smooth noise,
/// streaky texture stretched ALONG the wipe, a darker core that breaks into grainy speckle at the edges. 0...~1.3.
static float bSmear(float2 p, float2 c, float ang, float len, float wid, float3 Q, float seed) {
    // Cheap reject BEFORE the noise: the streak is exactly 0 beyond |a| = len (feathered end) and <= ~1e-11 beyond 5 widths across (~1e-11)
    // (wid * 1.35 is the widest wobble); the domain warp moves the outline by at most 0.5 * 0.045 + 0.5 * 0.014 = 0.0295. Most pixels
    // are outside most of the 23 streaks, so they skip the ~10 noise evaluations each (this was the whole cost of the soot).
    {
        float2 q0 = p - c;
        float ca0 = cos(ang), sa0 = sin(ang);
        float a0 = q0.x * ca0 + q0.y * sa0, b0 = -q0.x * sa0 + q0.y * ca0;
        if (abs(a0) > len + 0.032 || abs(b0) > wid * 6.75 + 0.032) { return 0.0; }
    }
    float2 w1 = float2(bvnoise(float3(p * 9.0, seed)), bvnoise(float3(p * 9.0 + 7.3, seed + 3.0))) - 0.5;
    float2 w2 = float2(bvnoise(float3(p * 21.0 + 2.0, seed + 5.0)), bvnoise(float3(p * 21.0 + 9.1, seed + 8.0))) - 0.5;
    float2 q = p - c + w1 * 0.045 + w2 * 0.014;
    float ca = cos(ang), sa = sin(ang);
    float a = q.x * ca + q.y * sa, b = -q.x * sa + q.y * ca;
    float along = 1.0 - smoothstep(0.30, 1.0, abs(a) / len);                           // feathered ends
    float wv = wid * (0.65 + 0.7 * bvnoise(float3(a * 12.0, seed, 1.0)));               // wobbling width
    float across = exp(-(b * b) / (wv * wv));
    float shape = along * across;
    float streak = bvnoise(float3(a * 4.0, b * 34.0, seed * 1.7 + Q.z * 3.0));            // stretched along the wipe
    float dens = shape * (0.5 + 0.9 * streak);
    float grainy = smoothstep(0.15, 0.75, bvnoise(Q * 46.0 + seed) + 0.30);                // speckle
    return dens * mix(1.0, grainy, 1.0 - smoothstep(0.25, 0.8, shape));
}

/// A soot wipe anywhere on the body: the same bSmear, in the tangent plane at body direction `dir` (t1 = sideways around y, t2 = up). ang 0 =
/// sideways, pi/2 = a vertical drip. Masked to the hemisphere facing `dir`.
static float bSmearAt(float3 sd, float3 d, float3 dir, float ang, float len, float wid, float3 Q, float seed) {
    float3 c = normalize(dir);
    float3 up = abs(c.y) > 0.95 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
    float3 t1 = normalize(cross(up, c));
    float3 t2 = cross(c, t1);
    float m = smoothstep(0.12, 0.5, dot(d, c));
    if (m <= 0.0) { return 0.0; }
    return m * bSmear(float2(dot(sd, t1), dot(sd, t2)), float2(0.0), ang, len, wid, Q, seed);
}

/// Cheap hash for the per-Jelly soot placement: 0...1 from a smear key and the Jelly's seed.
static float bjit(float k, float ps) {
    return fract(sin(k * 12.9898 + ps * 78.233) * 43758.5453);
}

/// A body smear placed for this Jelly: ps = 0 (Bob) is the original direction / angle exactly; other seeds turn the field around the body and
/// nudge each smear's height and slant, so every Jelly's streaks sit in their own places at the same strength.
static float bSmearBody(float3 sd, float3 d, float3 dir, float ang, float len, float wid, float3 Q, float seed, float ps) {
    float on = ps > 0.5 ? 1.0 : 0.0;
    float rot = on * ps * 2.399;
    float cr = cos(rot), sr = sin(rot);
    float3 r = float3(dir.x * cr + dir.z * sr, dir.y + on * (bjit(seed, ps) - 0.5) * 0.6, -dir.x * sr + dir.z * cr);
    return bSmearAt(sd, d, r, ang + on * (bjit(seed + 0.37, ps) - 0.5) * 1.2, len, wid, Q, seed + ps * 31.0);
}

/// A face smear placed for this Jelly (ps = 0: the original, exactly).
static float bSmearFace(float2 fp, float2 c, float ang, float len, float wid, float3 Q, float seed, float ps) {
    float on = ps > 0.5 ? 1.0 : 0.0;
    float2 j = on * float2(bjit(seed, ps) - 0.5, bjit(seed + 0.21, ps) - 0.5) * float2(0.09, 0.06);
    return bSmear(fp, c + j, ang + on * (bjit(seed + 0.37, ps) - 0.5) * 1.3, len, wid, Q, seed + ps * 31.0);
}

fragment float4 fsSoftMatteBath(BathJellyIn i [[stage_in]],
                                bool ff [[front_facing]],
                                constant BathBase& u [[buffer(0)]],
                                constant BathParams& bp [[buffer(3)]]) {
    float3 N = normalize(i.n);
    if (!ff) { N = -N; }
    float3 Q = i.rest;
    float e = 0.012;
    float c0 = bCrinkle(Q);
    float3 g = float3(bCrinkle(Q + float3(e, 0, 0)) - c0, bCrinkle(Q + float3(0, e, 0)) - c0, bCrinkle(Q + float3(0, 0, e)) - c0) / e;
    g -= N * dot(g, N);
    N = normalize(N - g * 0.0022);
    float fb = bFibre(Q);
    float ef = 0.0018;
    float3 gf = float3(bFibre(Q + float3(ef, 0, 0)) - fb, bFibre(Q + float3(0, ef, 0)) - fb, bFibre(Q + float3(0, 0, ef)) - fb) / ef;
    gf -= N * dot(gf, N);
    N = normalize(N - gf * 0.0003);

    float3 L = normalize(u.keyDir.xyz);
    float d = dot(N, L);
    float occ = clamp(i.mat / 0.4, 0.0, 1.0);
    float down = clamp(-N.y, 0.0, 1.0);
    float s = clamp(0.26 + 0.80 * d - 0.5 * max(-d - 0.04, 0.0) - 0.16 * down, 0.0, 1.0);
    s *= 1.0 - 0.62 * occ;
    float3 t = pow(float3(s), float3(0.55, 1.0, 1.25));
    float3 col = mix(u.fleshDeep.rgb, u.flesh.rgb, t);
    col += float3(0.02, 0.0, -0.004) * smoothstep(0.0, 0.2, s) * (1.0 - smoothstep(0.2, 0.55, s));
    col *= 1.0 + (bCrinkle(Q * 1.7 + 11.0) - 0.5) * 0.045;
    col *= 1.0 + 0.04 * fb;

    // ---- soot: mostly a light DUSTY film (matte, a touch desaturated, faint warm-grey, powdery grain), heavier on the lower half and
    // feet like settled dust, plus (when quite dirty) one or two very faint soft cheek / belly smudges. The 12 x 24 grid is ONLY the wash
    // mask (1 = still dusty), sampled bilinearly; nothing here has cells. His colour stays his colour: <= ~10 % darker, ~15 % desaturated at 1.0.
    float dirtK = clamp(bp.a.w, 0.0, 1.0);
    float ps = bp.centre.w;                                                                            // per-Jelly soot placement seed (Bob = 0)
    float sootHere = 0.0;
    float3 sd = Q - bp.centre.xyz;
    float wash = smoothstep(0.0, 0.7, bSootAt(bp, sd));
    if (wash > 0.003 && dirtK > 0.01) {
        float3 d = normalize(sd + float3(0.0, 1e-4, 0.0));
        float film = pow(dirtK, 0.75) * wash;
        float low = mix(1.0, 0.3, smoothstep(-0.25, 0.85, d.y));                              // dust settles low, thin on the crown
        float dustAmt = film * low;
        float grain = 1.0 + (bvnoise(Q * 44.0 + 2.0) - 0.5) * 0.09 * film;                  // faint powder, seen up close
        float lum = dot(col, float3(0.299, 0.587, 0.114));
        float3 dustTint = float3(lum) * float3(1.04, 1.0, 0.93);                                // faint warm grey
        col = mix(col, mix(col, dustTint, 0.24), dustAmt);                                      // up to ~15 % desaturated
        col *= (1.0 - 0.14 * dustAmt) * grain;                                                  // up to ~10 % darker
        // charcoal soot WIPES, mainly on the face (like a sooty hand smeared across it): sideways / diagonal streaks on the cheeks, one across the
        // brow, grime beside the eyes and nose, a chin smear and an uneven dusting of the whole face; a couple of fainter ones on the body.
        // Elongated feathered ellipses in the face plane (see bSmear), no round blobs. Eyes / brows are separate draws on top, so they stay crisp.
        float2 fp = Q.xy;
        float front = smoothstep(0.22, 0.6, d.z);
        float field = 0.0;
        field += smoothstep(0.05, 0.28, dirtK) * bSmearFace(fp, float2( 0.15, 0.655), -0.38, 0.150, 0.034, Q, 1.0, ps);       // right cheek wipe
        field += smoothstep(0.26, 0.50, dirtK) * bSmearFace(fp, float2(-0.16, 0.620), 0.20, 0.140, 0.032, Q, 2.0, ps);       // left cheek wipe
        field += smoothstep(0.30, 0.52, dirtK) * 0.9 * bSmearFace(fp, float2(0.04, 0.445), 0.45, 0.140, 0.030, Q, 3.0, ps);   // chin smear
        field += smoothstep(0.40, 0.62, dirtK) * 0.8 * bSmearFace(fp, float2(-0.03, 0.985), 0.08, 0.190, 0.032, Q, 4.0, ps);  // brow / forehead
        field += smoothstep(0.34, 0.58, dirtK) * 0.7 * bSmearFace(fp, float2( 0.115, 0.775), 1.25, 0.075, 0.024, Q, 5.0, ps); // beside the right eye / nose
        field += smoothstep(0.42, 0.66, dirtK) * 0.7 * bSmearFace(fp, float2(-0.105, 0.760), 1.75, 0.070, 0.024, Q, 6.0, ps); // beside the left eye
        float n2 = 0.6 * bvnoise(Q * 7.0 + 11.0 + ps * 17.0) + 0.4 * bvnoise(Q * 16.0 + 3.0 + ps * 17.0);
        float faceMask = smoothstep(0.42, 0.55, fp.y) * (1.0 - smoothstep(0.98, 1.1, fp.y));
        field += 0.55 * smoothstep(0.1, 0.5, dirtK) * smoothstep(0.38, 0.78, n2) * faceMask;                      // uneven dusting
        field *= front;
        // the rest of the body: wipes all over, in the body's own tangent frame (front, sides, back, crown, arms, feet), appearing as he gets dirtier
        float bd = smoothstep(0.1, 0.5, dirtK) * smoothstep(0.35, 0.8, 0.6 * bvnoise(Q * 5.0 + 21.0 + ps * 17.0) + 0.4 * bvnoise(Q * 12.0 + 5.0 + ps * 17.0));
        field += 0.4 * bd;                                                                                            // uneven dusting, whole body
        field += smoothstep(0.40, 0.60, dirtK) * 0.9 * bSmearBody(sd, d, float3( 0.05, -0.40,  0.90), 0.32, 0.16, 0.045, Q, 7.0, ps);   // belly
        field += smoothstep(0.50, 0.70, dirtK) * 0.8 * bSmearBody(sd, d, float3(-0.30, -0.15,  0.94), -0.50, 0.14, 0.040, Q, 8.0, ps);
        field += smoothstep(0.65, 0.85, dirtK) * 0.7 * bSmearBody(sd, d, float3( 0.35, -0.55,  0.76), 1.35, 0.13, 0.030, Q, 9.0, ps);   // drip
        field += smoothstep(0.42, 0.62, dirtK) * 0.9 * bSmearBody(sd, d, float3( 1.00,  0.15,  0.10), 0.50, 0.18, 0.045, Q, 10.0, ps);  // right side
        field += smoothstep(0.62, 0.82, dirtK) * 0.7 * bSmearBody(sd, d, float3( 0.95, -0.35, -0.20), 1.50, 0.15, 0.035, Q, 11.0, ps);
        field += smoothstep(0.48, 0.68, dirtK) * 0.9 * bSmearBody(sd, d, float3(-1.00,  0.05,  0.15), -0.40, 0.18, 0.045, Q, 12.0, ps); // left side
        field += smoothstep(0.66, 0.86, dirtK) * 0.7 * bSmearBody(sd, d, float3(-0.95, -0.40, -0.10), 1.40, 0.15, 0.035, Q, 13.0, ps);
        field += smoothstep(0.45, 0.65, dirtK) * 0.9 * bSmearBody(sd, d, float3( 0.20,  0.15, -0.95), 0.35, 0.24, 0.058, Q, 14.0, ps);  // back
        field += smoothstep(0.58, 0.78, dirtK) * 0.8 * bSmearBody(sd, d, float3(-0.35, -0.25, -0.90), -0.60, 0.22, 0.052, Q, 15.0, ps);
        field += smoothstep(0.72, 0.90, dirtK) * 0.7 * bSmearBody(sd, d, float3( 0.10, -0.60, -0.80), 1.45, 0.14, 0.032, Q, 16.0, ps);
        field += smoothstep(0.50, 0.70, dirtK) * 0.8 * bSmearBody(sd, d, float3( 0.55, -0.05, -0.83), 0.55, 0.18, 0.045, Q, 22.0, ps);
        field += smoothstep(0.60, 0.80, dirtK) * 0.8 * bSmearBody(sd, d, float3(-0.50,  0.40, -0.77), -0.35, 0.18, 0.045, Q, 23.0, ps);
        field += smoothstep(0.55, 0.75, dirtK) * 0.8 * bSmearBody(sd, d, float3( 0.10,  1.00,  0.10), 0.40, 0.15, 0.040, Q, 17.0, ps);  // crown
        field += smoothstep(0.50, 0.70, dirtK) * 0.9 * bSmearBody(sd, d, float3( 1.00, -0.05,  0.15), 0.80, 0.09, 0.035, Q, 18.0, ps);  // arm nubs
        field += smoothstep(0.55, 0.75, dirtK) * 0.9 * bSmearBody(sd, d, float3(-1.00, -0.02,  0.12), -0.80, 0.09, 0.035, Q, 19.0, ps);
        field += smoothstep(0.60, 0.80, dirtK) * 0.9 * bSmearBody(sd, d, float3( 0.42, -0.92,  0.30), 0.60, 0.10, 0.035, Q, 20.0, ps);  // feet
        field += smoothstep(0.65, 0.85, dirtK) * 0.9 * bSmearBody(sd, d, float3(-0.42, -0.92,  0.30), -0.60, 0.10, 0.035, Q, 21.0, ps);
        float smudge = smoothstep(0.03, 0.95, field) * wash;
        float strength = 0.16 + 0.16 * smoothstep(0.2, 0.5, dirtK) + 0.16 * smoothstep(0.5, 0.85, dirtK);        // ~16 % -> 32 % -> 48 % toward charcoal
        col = mix(col, float3(lum * 0.16 + 0.010), smudge * strength);
        sootHere = clamp(dustAmt * 1.3, 0.0, 1.0);
    }

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
    }

    // ---- bath terms: each one is gated by its own control, so all-zero is the plain matte look ----
    float wet = clamp(bp.a.x, 0.0, 1.0), spk = clamp(bp.a.y, 0.0, 1.0);
    float3 V = normalize(u.camPos.xyz - i.wp);
    float NdV = max(dot(N, V), 1e-3);
    float time = u.camPos.w;
    float3 Nsurf = normalize(i.n);
    if (!ff) { Nsurf = -Nsurf; }

    if (wet > 0.001) {
        col *= 1.0 - 0.10 * wet;                                           // wet skin darkens a touch
        // droplet beads (rest space): small domes that catch the key light
        float3 bq = Q * 64.0;
        float3 bi = floor(bq), bf = fract(bq);
        float3 bj = bhash33(bi);
        float3 bc = 0.5 + (bj - 0.5) * 0.5;
        float bd = length(bf - bc);
        float present = step(1.0 - 0.34 * wet, bhash3(bi + 7.0));
        float br = 0.20 + 0.14 * bj.x;
        float dome = present * smoothstep(br, br * 0.35, bd);
        float3 tilt = (bf - bc) / br;
        tilt -= N * dot(tilt, N);
        float3 Nw = normalize(N - tilt * 0.55 * dome);
        float rough = mix(0.5, 0.12, wet);
        float3 H = normalize(L + V);
        float key = u.keyDir.w;
        float glossK = 1.0 - 0.5 * sootHere;                              // soot dulls the gloss
        float spec = bGGX(Nw, V, L, rough) * key * 0.35 * wet * glossK;
        spec += pow(max(dot(Nw, H), 0.0), 70.0) * dome * 0.55 * wet * glossK;
        float F = 0.03 + 0.97 * pow(1.0 - NdV, 5.0);
        float3 R = reflect(-V, N);
        float3 sky = mix(u.bg.rgb * 0.8, float3(0.78, 0.9, 1.0), smoothstep(-0.1, 0.8, R.y));
        col += float3(1.0, 0.98, 0.95) * spec;
        col += sky * F * 0.30 * wet * glossK;
        col = mix(col, col * 1.12 + 0.015, dome * wet);                    // bead body is slightly lighter
    }

    float foamOn = bp.a.z;
    if (foamOn > 0.5) {
        float f = bFoamAt(bp, Q - bp.centre.xyz);
        if (f > 0.012) {
            // soap suds: dense small bubbles (nearest of the 8 neighbouring jittered cells), bump normal from the dome
            float3 sp = Q * 21.0;
            float3 si = floor(sp);
            float3 sf = fract(sp);
            float3 st = step(0.5, sf) * 2.0 - 1.0;               // which neighbour to look toward on each axis
            float bestH = 0.0; float3 bestTilt = float3(0.0); float bestId = 0.0;
            for (int k = 0; k < 8; k++) {
                float3 off = float3(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1)) * st;
                float3 cid = si + off;
                float3 h3 = bhash33(cid);
                float3 cc = off + 0.5 + (h3 - 0.5) * 0.55;
                float rad = 0.46 + 0.42 * h3.x;
                float3 dv = sf - cc;
                float dl = length(dv) / rad;
                float hh = sqrt(max(1.0 - dl * dl, 0.0));
                if (hh > bestH) { bestH = hh; bestTilt = dv / rad; bestId = h3.y; }
            }
            float big = bvnoise(Q * 9.0 + 3.0);
            float lump = bvnoise(Q * 17.0 + 11.0);
            float cover = smoothstep(0.16, 0.46, f + (big - 0.5) * 0.42 + (lump - 0.5) * 0.16);
            float3 tl = bestTilt - N * dot(bestTilt, N);
            float3 Nf = normalize(N - tl * 1.0);
            float nd = dot(Nf, L);
            float lit = clamp(0.80 + 0.28 * nd, 0.0, 1.05);
            float crev = mix(0.84, 1.0, smoothstep(0.0, 0.5, bestH));    // dark crevice between bubbles
            float3 tint = mix(float3(0.97, 0.985, 1.0), float3(1.0, 0.96, 0.99), bestId);
            tint = mix(tint, u.flesh.rgb, 0.05);
            tint = mix(tint, float3(0.62, 0.625, 0.64), clamp(sootHere * 0.55, 0.0, 0.55));           // suds over soot go grey
            float3 foamC = tint * lit * crev;
            float3 Hh = normalize(L + V);
            foamC += float3(1.0) * pow(max(dot(Nf, Hh), 0.0), 90.0) * bestH * 0.30;   // pinpoint glints on the bubbles
            foamC += float3(0.85, 0.93, 1.0) * pow(1.0 - NdV, 3.0) * 0.10;            // soft cool rim
            col = mix(col, foamC, cover);                                              // thick foam hides the skin
        }
    }

    if (spk > 0.001) {
        // squeaky clean: a soft bright rim, a clean brightening, and many twinkling four-point stars with a soft halo
        col = mix(col, col * 1.10 + 0.02, spk);
        col += float3(0.80, 0.93, 1.0) * pow(1.0 - NdV, 2.2) * 0.18 * spk;
        float3 T = normalize(cross(abs(Nsurf.y) < 0.9 ? float3(0, 1, 0) : float3(1, 0, 0), Nsurf));
        float3 Bt = cross(Nsurf, T);
        float3 glint = float3(0.0);
        for (int layer = 0; layer < 2; layer++) {       // two cell sizes: about half the glints of the first pass
            float cs = layer == 0 ? 0.38 : (layer == 1 ? 0.24 : 0.15);
            float3 gq = (Q + float3(0.37, 0.11, 0.53) * float(layer)) / cs;
            float3 gi = floor(gq);
            float3 h3 = bhash33(gi + float(layer) * 31.7);
            float gate = bhash3(gi + 91.0 + float(layer));
            float dens = layer == 0 ? 0.8 : 0.6;
            if (gate < spk * dens) {
                float3 pc = 0.5 + (h3 - 0.5) * 0.40;
                float3 dv = (fract(gq) - pc) * cs;                      // rest-space offset to the speck centre
                float u1 = dot(dv, T), v1 = dot(dv, Bt);
                float r = length(dv);
                float reach = 0.245 * cs;
                float ph = fract(time * (0.18 + 0.5 * h3.z) + h3.x * 7.0);   // each star twinkles at its own rate
                float pop = pow(max(sin(ph * BATH_PI), 0.0), 2.5);
                float core = exp(-r * r / (reach * reach * 0.06));
                float halo = exp(-r * r / (reach * reach * 0.55)) * 0.20;
                float crs = exp(-abs(u1 * v1) / (reach * reach * 0.05)) * exp(-r / (reach * 0.6));
                float star = (1.0 * core + 1.1 * crs + halo) * smoothstep(reach, reach * 0.5, r);
                float3 gc = mix(float3(1.0, 0.98, 0.92), float3(0.82, 0.94, 1.0), h3.y);
                glint += gc * star * pop;
            }
        }
        col += glint * 1.5 * smoothstep(0.0, 0.2, NdV + 0.15);
    }
    return float4(col / max(u.misc.x, 1e-3), 0.0);
}

/// The same shader specialised with the function constants above (MelonRenderer.gfxOpt.bathVariants, -BathVariants 1): unused blocks are
/// compiled out. Kept as a separate function because any specialised build (even all-true) is folded a few ulps differently from the plain
/// function: BathSootSeedZeroTests hashes the plain one. Keep the two bodies identical.
fragment float4 fsSoftMatteBathSpec(BathJellyIn i [[stage_in]],
                                bool ff [[front_facing]],
                                constant BathBase& u [[buffer(0)]],
                                constant BathParams& bp [[buffer(3)]]) {
    float3 N = normalize(i.n);
    if (!ff) { N = -N; }
    float3 Q = i.rest;
    float e = 0.012;
    float c0 = bCrinkle(Q);
    float3 g = float3(bCrinkle(Q + float3(e, 0, 0)) - c0, bCrinkle(Q + float3(0, e, 0)) - c0, bCrinkle(Q + float3(0, 0, e)) - c0) / e;
    g -= N * dot(g, N);
    N = normalize(N - g * 0.0022);
    float fb = bFibre(Q);
    float ef = 0.0018;
    float3 gf = float3(bFibre(Q + float3(ef, 0, 0)) - fb, bFibre(Q + float3(0, ef, 0)) - fb, bFibre(Q + float3(0, 0, ef)) - fb) / ef;
    gf -= N * dot(gf, N);
    N = normalize(N - gf * 0.0003);

    float3 L = normalize(u.keyDir.xyz);
    float d = dot(N, L);
    float occ = clamp(i.mat / 0.4, 0.0, 1.0);
    float down = clamp(-N.y, 0.0, 1.0);
    float s = clamp(0.26 + 0.80 * d - 0.5 * max(-d - 0.04, 0.0) - 0.16 * down, 0.0, 1.0);
    s *= 1.0 - 0.62 * occ;
    float3 t = pow(float3(s), float3(0.55, 1.0, 1.25));
    float3 col = mix(u.fleshDeep.rgb, u.flesh.rgb, t);
    col += float3(0.02, 0.0, -0.004) * smoothstep(0.0, 0.2, s) * (1.0 - smoothstep(0.2, 0.55, s));
    col *= 1.0 + (bCrinkle(Q * 1.7 + 11.0) - 0.5) * 0.045;
    col *= 1.0 + 0.04 * fb;

    // ---- soot: mostly a light DUSTY film (matte, a touch desaturated, faint warm-grey, powdery grain), heavier on the lower half and
    // feet like settled dust, plus (when quite dirty) one or two very faint soft cheek / belly smudges. The 12 x 24 grid is ONLY the wash
    // mask (1 = still dusty), sampled bilinearly; nothing here has cells. His colour stays his colour: <= ~10 % darker, ~15 % desaturated at 1.0.
    float dirtK = clamp(bp.a.w, 0.0, 1.0);
    float ps = bp.centre.w;                                                                            // per-Jelly soot placement seed (Bob = 0)
    float sootHere = 0.0;
    float3 sd = Q - bp.centre.xyz;
    float wash = smoothstep(0.0, 0.7, bSootAt(bp, sd));
    if (bathHasSoot && wash > 0.003 && dirtK > 0.01) {
        float3 d = normalize(sd + float3(0.0, 1e-4, 0.0));
        float film = pow(dirtK, 0.75) * wash;
        float low = mix(1.0, 0.3, smoothstep(-0.25, 0.85, d.y));                              // dust settles low, thin on the crown
        float dustAmt = film * low;
        float grain = 1.0 + (bvnoise(Q * 44.0 + 2.0) - 0.5) * 0.09 * film;                  // faint powder, seen up close
        float lum = dot(col, float3(0.299, 0.587, 0.114));
        float3 dustTint = float3(lum) * float3(1.04, 1.0, 0.93);                                // faint warm grey
        col = mix(col, mix(col, dustTint, 0.24), dustAmt);                                      // up to ~15 % desaturated
        col *= (1.0 - 0.14 * dustAmt) * grain;                                                  // up to ~10 % darker
        // charcoal soot WIPES, mainly on the face (like a sooty hand smeared across it): sideways / diagonal streaks on the cheeks, one across the
        // brow, grime beside the eyes and nose, a chin smear and an uneven dusting of the whole face; a couple of fainter ones on the body.
        // Elongated feathered ellipses in the face plane (see bSmear), no round blobs. Eyes / brows are separate draws on top, so they stay crisp.
        float2 fp = Q.xy;
        float front = smoothstep(0.22, 0.6, d.z);
        float field = 0.0;
        field += smoothstep(0.05, 0.28, dirtK) * bSmearFace(fp, float2( 0.15, 0.655), -0.38, 0.150, 0.034, Q, 1.0, ps);       // right cheek wipe
        field += smoothstep(0.26, 0.50, dirtK) * bSmearFace(fp, float2(-0.16, 0.620), 0.20, 0.140, 0.032, Q, 2.0, ps);       // left cheek wipe
        field += smoothstep(0.30, 0.52, dirtK) * 0.9 * bSmearFace(fp, float2(0.04, 0.445), 0.45, 0.140, 0.030, Q, 3.0, ps);   // chin smear
        field += smoothstep(0.40, 0.62, dirtK) * 0.8 * bSmearFace(fp, float2(-0.03, 0.985), 0.08, 0.190, 0.032, Q, 4.0, ps);  // brow / forehead
        field += smoothstep(0.34, 0.58, dirtK) * 0.7 * bSmearFace(fp, float2( 0.115, 0.775), 1.25, 0.075, 0.024, Q, 5.0, ps); // beside the right eye / nose
        field += smoothstep(0.42, 0.66, dirtK) * 0.7 * bSmearFace(fp, float2(-0.105, 0.760), 1.75, 0.070, 0.024, Q, 6.0, ps); // beside the left eye
        float n2 = 0.6 * bvnoise(Q * 7.0 + 11.0 + ps * 17.0) + 0.4 * bvnoise(Q * 16.0 + 3.0 + ps * 17.0);
        float faceMask = smoothstep(0.42, 0.55, fp.y) * (1.0 - smoothstep(0.98, 1.1, fp.y));
        field += 0.55 * smoothstep(0.1, 0.5, dirtK) * smoothstep(0.38, 0.78, n2) * faceMask;                      // uneven dusting
        field *= front;
        // the rest of the body: wipes all over, in the body's own tangent frame (front, sides, back, crown, arms, feet), appearing as he gets dirtier
        float bd = smoothstep(0.1, 0.5, dirtK) * smoothstep(0.35, 0.8, 0.6 * bvnoise(Q * 5.0 + 21.0 + ps * 17.0) + 0.4 * bvnoise(Q * 12.0 + 5.0 + ps * 17.0));
        field += 0.4 * bd;                                                                                            // uneven dusting, whole body
        field += smoothstep(0.40, 0.60, dirtK) * 0.9 * bSmearBody(sd, d, float3( 0.05, -0.40,  0.90), 0.32, 0.16, 0.045, Q, 7.0, ps);   // belly
        field += smoothstep(0.50, 0.70, dirtK) * 0.8 * bSmearBody(sd, d, float3(-0.30, -0.15,  0.94), -0.50, 0.14, 0.040, Q, 8.0, ps);
        field += smoothstep(0.65, 0.85, dirtK) * 0.7 * bSmearBody(sd, d, float3( 0.35, -0.55,  0.76), 1.35, 0.13, 0.030, Q, 9.0, ps);   // drip
        field += smoothstep(0.42, 0.62, dirtK) * 0.9 * bSmearBody(sd, d, float3( 1.00,  0.15,  0.10), 0.50, 0.18, 0.045, Q, 10.0, ps);  // right side
        field += smoothstep(0.62, 0.82, dirtK) * 0.7 * bSmearBody(sd, d, float3( 0.95, -0.35, -0.20), 1.50, 0.15, 0.035, Q, 11.0, ps);
        field += smoothstep(0.48, 0.68, dirtK) * 0.9 * bSmearBody(sd, d, float3(-1.00,  0.05,  0.15), -0.40, 0.18, 0.045, Q, 12.0, ps); // left side
        field += smoothstep(0.66, 0.86, dirtK) * 0.7 * bSmearBody(sd, d, float3(-0.95, -0.40, -0.10), 1.40, 0.15, 0.035, Q, 13.0, ps);
        field += smoothstep(0.45, 0.65, dirtK) * 0.9 * bSmearBody(sd, d, float3( 0.20,  0.15, -0.95), 0.35, 0.24, 0.058, Q, 14.0, ps);  // back
        field += smoothstep(0.58, 0.78, dirtK) * 0.8 * bSmearBody(sd, d, float3(-0.35, -0.25, -0.90), -0.60, 0.22, 0.052, Q, 15.0, ps);
        field += smoothstep(0.72, 0.90, dirtK) * 0.7 * bSmearBody(sd, d, float3( 0.10, -0.60, -0.80), 1.45, 0.14, 0.032, Q, 16.0, ps);
        field += smoothstep(0.50, 0.70, dirtK) * 0.8 * bSmearBody(sd, d, float3( 0.55, -0.05, -0.83), 0.55, 0.18, 0.045, Q, 22.0, ps);
        field += smoothstep(0.60, 0.80, dirtK) * 0.8 * bSmearBody(sd, d, float3(-0.50,  0.40, -0.77), -0.35, 0.18, 0.045, Q, 23.0, ps);
        field += smoothstep(0.55, 0.75, dirtK) * 0.8 * bSmearBody(sd, d, float3( 0.10,  1.00,  0.10), 0.40, 0.15, 0.040, Q, 17.0, ps);  // crown
        field += smoothstep(0.50, 0.70, dirtK) * 0.9 * bSmearBody(sd, d, float3( 1.00, -0.05,  0.15), 0.80, 0.09, 0.035, Q, 18.0, ps);  // arm nubs
        field += smoothstep(0.55, 0.75, dirtK) * 0.9 * bSmearBody(sd, d, float3(-1.00, -0.02,  0.12), -0.80, 0.09, 0.035, Q, 19.0, ps);
        field += smoothstep(0.60, 0.80, dirtK) * 0.9 * bSmearBody(sd, d, float3( 0.42, -0.92,  0.30), 0.60, 0.10, 0.035, Q, 20.0, ps);  // feet
        field += smoothstep(0.65, 0.85, dirtK) * 0.9 * bSmearBody(sd, d, float3(-0.42, -0.92,  0.30), -0.60, 0.10, 0.035, Q, 21.0, ps);
        float smudge = smoothstep(0.03, 0.95, field) * wash;
        float strength = 0.16 + 0.16 * smoothstep(0.2, 0.5, dirtK) + 0.16 * smoothstep(0.5, 0.85, dirtK);        // ~16 % -> 32 % -> 48 % toward charcoal
        col = mix(col, float3(lum * 0.16 + 0.010), smudge * strength);
        sootHere = clamp(dustAmt * 1.3, 0.0, 1.0);
    }

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
    }

    // ---- bath terms: each one is gated by its own control, so all-zero is the plain matte look ----
    float wet = clamp(bp.a.x, 0.0, 1.0), spk = clamp(bp.a.y, 0.0, 1.0);
    float3 V = normalize(u.camPos.xyz - i.wp);
    float NdV = max(dot(N, V), 1e-3);
    float time = u.camPos.w;
    float3 Nsurf = normalize(i.n);
    if (!ff) { Nsurf = -Nsurf; }

    if (bathHasWet && wet > 0.001) {
        col *= 1.0 - 0.10 * wet;                                           // wet skin darkens a touch
        // droplet beads (rest space): small domes that catch the key light
        float3 bq = Q * 64.0;
        float3 bi = floor(bq), bf = fract(bq);
        float3 bj = bhash33(bi);
        float3 bc = 0.5 + (bj - 0.5) * 0.5;
        float bd = length(bf - bc);
        float present = step(1.0 - 0.34 * wet, bhash3(bi + 7.0));
        float br = 0.20 + 0.14 * bj.x;
        float dome = present * smoothstep(br, br * 0.35, bd);
        float3 tilt = (bf - bc) / br;
        tilt -= N * dot(tilt, N);
        float3 Nw = normalize(N - tilt * 0.55 * dome);
        float rough = mix(0.5, 0.12, wet);
        float3 H = normalize(L + V);
        float key = u.keyDir.w;
        float glossK = 1.0 - 0.5 * sootHere;                              // soot dulls the gloss
        float spec = bGGX(Nw, V, L, rough) * key * 0.35 * wet * glossK;
        spec += pow(max(dot(Nw, H), 0.0), 70.0) * dome * 0.55 * wet * glossK;
        float F = 0.03 + 0.97 * pow(1.0 - NdV, 5.0);
        float3 R = reflect(-V, N);
        float3 sky = mix(u.bg.rgb * 0.8, float3(0.78, 0.9, 1.0), smoothstep(-0.1, 0.8, R.y));
        col += float3(1.0, 0.98, 0.95) * spec;
        col += sky * F * 0.30 * wet * glossK;
        col = mix(col, col * 1.12 + 0.015, dome * wet);                    // bead body is slightly lighter
    }

    float foamOn = bp.a.z;
    if (bathHasFoam && foamOn > 0.5) {
        float f = bFoamAt(bp, Q - bp.centre.xyz);
        if (f > 0.012) {
            // soap suds: dense small bubbles (nearest of the 8 neighbouring jittered cells), bump normal from the dome
            float3 sp = Q * 21.0;
            float3 si = floor(sp);
            float3 sf = fract(sp);
            float3 st = step(0.5, sf) * 2.0 - 1.0;               // which neighbour to look toward on each axis
            float bestH = 0.0; float3 bestTilt = float3(0.0); float bestId = 0.0;
            for (int k = 0; k < 8; k++) {
                float3 off = float3(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1)) * st;
                float3 cid = si + off;
                float3 h3 = bhash33(cid);
                float3 cc = off + 0.5 + (h3 - 0.5) * 0.55;
                float rad = 0.46 + 0.42 * h3.x;
                float3 dv = sf - cc;
                float dl = length(dv) / rad;
                float hh = sqrt(max(1.0 - dl * dl, 0.0));
                if (hh > bestH) { bestH = hh; bestTilt = dv / rad; bestId = h3.y; }
            }
            float big = bvnoise(Q * 9.0 + 3.0);
            float lump = bvnoise(Q * 17.0 + 11.0);
            float cover = smoothstep(0.16, 0.46, f + (big - 0.5) * 0.42 + (lump - 0.5) * 0.16);
            float3 tl = bestTilt - N * dot(bestTilt, N);
            float3 Nf = normalize(N - tl * 1.0);
            float nd = dot(Nf, L);
            float lit = clamp(0.80 + 0.28 * nd, 0.0, 1.05);
            float crev = mix(0.84, 1.0, smoothstep(0.0, 0.5, bestH));    // dark crevice between bubbles
            float3 tint = mix(float3(0.97, 0.985, 1.0), float3(1.0, 0.96, 0.99), bestId);
            tint = mix(tint, u.flesh.rgb, 0.05);
            tint = mix(tint, float3(0.62, 0.625, 0.64), clamp(sootHere * 0.55, 0.0, 0.55));           // suds over soot go grey
            float3 foamC = tint * lit * crev;
            float3 Hh = normalize(L + V);
            foamC += float3(1.0) * pow(max(dot(Nf, Hh), 0.0), 90.0) * bestH * 0.30;   // pinpoint glints on the bubbles
            foamC += float3(0.85, 0.93, 1.0) * pow(1.0 - NdV, 3.0) * 0.10;            // soft cool rim
            col = mix(col, foamC, cover);                                              // thick foam hides the skin
        }
    }

    if (bathHasSparkle && spk > 0.001) {
        // squeaky clean: a soft bright rim, a clean brightening, and many twinkling four-point stars with a soft halo
        col = mix(col, col * 1.10 + 0.02, spk);
        col += float3(0.80, 0.93, 1.0) * pow(1.0 - NdV, 2.2) * 0.18 * spk;
        float3 T = normalize(cross(abs(Nsurf.y) < 0.9 ? float3(0, 1, 0) : float3(1, 0, 0), Nsurf));
        float3 Bt = cross(Nsurf, T);
        float3 glint = float3(0.0);
        for (int layer = 0; layer < 2; layer++) {       // two cell sizes: about half the glints of the first pass
            float cs = layer == 0 ? 0.38 : (layer == 1 ? 0.24 : 0.15);
            float3 gq = (Q + float3(0.37, 0.11, 0.53) * float(layer)) / cs;
            float3 gi = floor(gq);
            float3 h3 = bhash33(gi + float(layer) * 31.7);
            float gate = bhash3(gi + 91.0 + float(layer));
            float dens = layer == 0 ? 0.8 : 0.6;
            if (gate < spk * dens) {
                float3 pc = 0.5 + (h3 - 0.5) * 0.40;
                float3 dv = (fract(gq) - pc) * cs;                      // rest-space offset to the speck centre
                float u1 = dot(dv, T), v1 = dot(dv, Bt);
                float r = length(dv);
                float reach = 0.245 * cs;
                float ph = fract(time * (0.18 + 0.5 * h3.z) + h3.x * 7.0);   // each star twinkles at its own rate
                float pop = pow(max(sin(ph * BATH_PI), 0.0), 2.5);
                float core = exp(-r * r / (reach * reach * 0.06));
                float halo = exp(-r * r / (reach * reach * 0.55)) * 0.20;
                float crs = exp(-abs(u1 * v1) / (reach * reach * 0.05)) * exp(-r / (reach * 0.6));
                float star = (1.0 * core + 1.1 * crs + halo) * smoothstep(reach, reach * 0.5, r);
                float3 gc = mix(float3(1.0, 0.98, 0.92), float3(0.82, 0.94, 1.0), h3.y);
                glint += gc * star * pop;
            }
        }
        col += glint * 1.5 * smoothstep(0.0, 0.2, NdV + 0.15);
    }
    return float4(col / max(u.misc.x, 1e-3), 0.0);
}

// ───────────────────────── bathroom set + overlay props ─────────────────────────
// Vertex = RoomVertex: pos (w = material), normal (w = baked AO), colour (a = alpha). Materials:
//  0 matte  1 glossy ceramic  2 fabric  3 emissive (window, mirror halo)  4 jelly  5 water  6 sud bubble  7 water droplet
//  8 glitter fleck  9 star billboard  14 dust puff  10 marble slab  11 porcelain floor slab  12 oak / walnut  13 brushed metal

struct BathSetU {
    float4x4 viewProj;
    float4x4 lightVP;
    float4 camPos;     // xyz, w = 1 when the shadow map is valid
    float4 keyDir;     // xyz toward the light, w = intensity
    float4 misc;       // time, water height, ripple centre x, ripple centre z
    float4 sky;        // ambient from above
    float4 ground;     // ambient from below
    float4 fog;        // colour xyz, w = amount per unit past 12 (small)
};
static_assert(sizeof(BathSetU) == 2 * 64 + 6 * 16, "BathSetU layout (BathSetUniforms in BathSet.swift)");

struct BathVIn {
    float4 pos    [[attribute(0)]];
    float4 normal [[attribute(1)]];
    float4 color  [[attribute(2)]];
};
struct BathVOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 color;
    float ao;
    float alpha;
    float mat [[flat]];
};

vertex BathVOut bathVS(BathVIn v [[stage_in]], constant BathSetU& u [[buffer(0)]]) {
    BathVOut o;
    o.world = v.pos.xyz;
    o.position = u.viewProj * float4(v.pos.xyz, 1.0);
    o.normal = v.normal.xyz; o.ao = v.normal.w;
    o.color = v.color.rgb; o.alpha = v.color.a;
    o.mat = v.pos.w;
    return o;
}

constexpr sampler bathCmp(coord::normalized, address::clamp_to_edge, filter::linear, compare_func::less_equal);

static float bathShadow(constant BathSetU& u, depth2d<float> sm, float3 P, float3 N) {
    if (u.camPos.w < 0.5) { return 1.0; }
    float4 lp = u.lightVP * float4(P + N * 0.01, 1.0);
    float2 uv = float2(lp.x * 0.5 + 0.5, 0.5 - lp.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return 1.0; }
    float z = lp.z - 0.0015;
    float s = 0.0;
    float2 texel = float2(1.0 / float(sm.get_width()), 1.0 / float(sm.get_height()));
    for (int j = -1; j <= 1; j++) { for (int i = -1; i <= 1; i++) { s += sm.sample_compare(bathCmp, uv + float2(i, j) * texel * 5.0, z); } }
    return mix(1.0, s / 9.0, 0.6);
}

/// Soft studio-like environment for ceramic / tile reflections: cool sky, bright window panel, white ceiling light.
static float3 bathEnv(float3 d, constant BathSetU& u) {
    float3 col = mix(u.ground.rgb * 0.9, u.sky.rgb * 1.1, smoothstep(-0.3, 0.5, d.y));
    float3 wd = normalize(float3(-0.55, 0.28, -0.78));                 // the window
    col += float3(1.0, 0.99, 0.96) * 2.2 * smoothstep(0.93, 0.975, dot(d, wd));
    col += float3(0.98, 0.97, 0.95) * 1.1 * smoothstep(0.78, 0.98, d.y);
    return col;
}

static float bathRipple(constant BathSetU& u, float2 xz, thread float2& grad) {
    float t = u.misc.x;
    float2 c = xz - u.misc.zw;
    float r = length(c) + 1e-4;
    float ring = sin(r * 16.0 - t * 2.4) * exp(-r * 1.3) * 0.5;
    float dr = (cos(r * 16.0 - t * 2.4) * 16.0 * exp(-r * 1.3) * 0.5) - 1.3 * ring;
    float2 g = (c / r) * dr;
    float a1 = xz.x * 4.1 + t * 0.9, a2 = xz.y * 3.3 - t * 0.7;
    g += float2(cos(a1) * 4.1 * sin(a2), sin(a1) * cos(a2) * 3.3) * 0.28;
    g += float2(cos(xz.x * 9.0 - t * 1.7 + xz.y * 5.0) * 9.0, cos(xz.x * 9.0 - t * 1.7 + xz.y * 5.0) * 5.0) * 0.05;
    grad = g;
    return ring;
}

fragment float4 bathFS(BathVOut in [[stage_in]],
                       constant BathSetU& u [[buffer(0)]],
                       depth2d<float> shadowMap [[texture(0)]]) {
    float3 N = normalize(in.normal);
    float3 P = in.world;
    float3 camVec = u.camPos.xyz - P;
    float dist = length(camVec);
    float3 V = camVec / max(dist, 1e-4);
    int m = int(in.mat + 0.5);
    float3 albedo = in.color;
    float alpha = 1.0;
    float t = u.misc.x;

    if (m == 3) { return float4(albedo * 1.3, 1.0); }               // glowing window / mirror light

    if (m == 14) {
        // dust puff: a tiny soft grey disc with a ragged edge, camera-facing (normal.xy = quad coordinate, colour.a = fade)
        float2 q = in.normal.xy;
        float r = length(q);
        float ragged = 0.72 + 0.55 * bvnoise(float3(q * 2.6, t * 0.6 + P.x * 9.0));
        float s = exp(-r * r * 3.0) * smoothstep(1.0, 0.5, r) * ragged;
        return float4(albedo, clamp(s, 0.0, 1.0) * in.alpha);
    }

    if (m == 9) {
        // camera-facing sparkle: normal.xy carries the quad coordinate (-1...1), colour.a the fade
        float2 q = in.normal.xy;
        float r = length(q);
        float halo = exp(-r * r * 5.0) * 0.30;
        float crs = exp(-abs(q.x * q.y) * 26.0) * exp(-r * 2.2);
        float core = exp(-r * r * 38.0);
        float s = (core + crs * 1.05 + halo) * smoothstep(1.0, 0.7, r);
        return float4(albedo * (1.0 + 0.8 * core), clamp(s, 0.0, 1.0) * in.alpha);
    }

    if (m == 5) {
        // water: translucent, slightly blue, rippling; fresnel mixes in the bathroom reflection
        float2 gr; bathRipple(u, P.xz, gr);
        float3 Nw = normalize(float3(-gr.x * 0.05, 1.0, -gr.y * 0.05));
        float NdV = max(dot(Nw, V), 1e-3);
        float F = 0.02 + 0.98 * pow(1.0 - NdV, 4.0);
        float3 R = reflect(-V, Nw);
        float3 L = normalize(u.keyDir.xyz);
        float3 deep = float3(0.36, 0.64, 0.86), shallow = float3(0.58, 0.82, 0.95);
        float3 body = mix(shallow, deep, 0.45 + 0.25 * sin(P.x * 3.0 + t * 0.6) * sin(P.z * 2.6 - t * 0.5));
        float3 col = mix(body * (0.72 + 0.28 * Nw.y), bathEnv(R, u), F);
        col += float3(1.0) * pow(max(dot(Nw, normalize(L + V)), 0.0), 220.0) * 1.6;      // key glint
        alpha = clamp(mix(0.55, 0.92, F) + 0.1 * clamp(length(gr) * 0.05, 0.0, 1.0), 0.0, 0.92);
        // soft pale edge against the tub rim
        float rr = length(P.xz - u.misc.zw);
        col = mix(col, float3(0.92, 0.97, 1.0), smoothstep(0.80, 0.9, rr / max(in.ao, 0.1)) * 0.45);
        return float4(col, alpha);
    }

    float3 L = normalize(u.keyDir.xyz);
    float NdV = max(dot(N, V), 1e-3);
    float ao = in.ao;
    float sh = bathShadow(u, shadowMap, P, N);
    float wrapW = 0.5;
    float ndl = saturate((dot(N, L) + wrapW) / (1.0 + wrapW));
    ndl = ndl * ndl * (3.0 - 2.0 * ndl) * 0.35 + ndl * 0.65;
    float3 keyCol = float3(1.0, 0.985, 0.95) * u.keyDir.w;
    float3 amb = mix(u.ground.rgb, u.sky.rgb, N.y * 0.5 + 0.5);

    if (m == 6) {
        // soap bubble: clear body, bright iridescent rim and a window glint
        float rim = pow(1.0 - NdV, 2.2);
        float3 film = 0.55 + 0.45 * cos(6.2832 * (NdV * 1.3 + float3(0.0, 0.33, 0.67)) + t * 0.5);
        float3 R = reflect(-V, N);
        float3 col = film * rim * 0.9 + bathEnv(R, u) * (0.04 + 0.5 * rim) + float3(1.0) * pow(max(dot(N, normalize(L + V)), 0.0), 120.0) * 1.2;
        return float4(col, clamp(0.10 + 0.75 * rim + 0.5 * pow(max(dot(N, normalize(L + V)), 0.0), 120.0), 0.0, 0.92));
    }
    if (m == 7) {
        float3 R = reflect(-V, N);
        float F = 0.04 + 0.96 * pow(1.0 - NdV, 4.0);
        float3 col = mix(float3(0.62, 0.84, 0.98) * (0.6 + 0.4 * ndl), bathEnv(R, u), F);
        col += float3(1.0) * pow(max(dot(N, normalize(L + V)), 0.0), 150.0) * 1.0;
        return float4(col, 0.62);
    }
    if (m == 8) {
        // glitter fleck: sparkly foil, flips between bright and pastel as it turns
        float tw = 0.5 + 0.5 * sin(t * 7.0 + in.world.x * 40.0 + in.world.y * 31.0);
        float3 R = reflect(-V, N);
        float3 col = albedo * (0.5 + 0.7 * tw) + bathEnv(R, u) * 0.35 + float3(1.0) * pow(max(dot(N, normalize(L + V)), 0.0), 40.0) * 1.2;
        return float4(col, 1.0);
    }

    if (m == 10 || m == 11) {
        // large-format slabs: seams, per-slab tone and soft veining, in world space on the dominant plane
        float3 an = abs(N);
        float2 uv = an.y > 0.7 ? P.xz : (an.x > an.z ? P.zy : P.xy);
        float2 sz = m == 10 ? float2(1.5, 2.2) : float2(1.2, 1.2);
        float2 sc = uv / sz;
        float2 id = floor(sc), fr = fract(sc);
        float seam = min(min(fr.x, 1.0 - fr.x) * sz.x, min(fr.y, 1.0 - fr.y) * sz.y);
        float sk = smoothstep(0.0, 0.012, seam);
        albedo *= 0.93 + 0.12 * bhash3(float3(id, 3.0));
        float2 vp = uv * (m == 10 ? 1.4 : 0.9) + id * 7.3;
        float nz = 0.6 * bvnoise(float3(vp * 1.3, 1.0)) + 0.4 * bvnoise(float3(vp * 3.1, 8.0));
        float vv = abs(sin((vp.x * 0.8 + vp.y * 1.3 + nz * 4.5) * 2.6));
        float vein = (1.0 - smoothstep(0.0, 0.11, vv)) * smoothstep(0.35, 0.7, bvnoise(float3(vp * 0.7, 20.0)));
        float vein2 = (1.0 - smoothstep(0.0, 0.06, abs(sin((vp.x * 1.7 - vp.y * 0.9 + nz * 3.0) * 3.4)))) * smoothstep(0.55, 0.8, bvnoise(float3(vp * 0.5, 40.0)));
        albedo = mix(albedo, albedo * float3(1.38, 1.36, 1.33) + 0.03, clamp(vein * (m == 10 ? 0.6 : 0.3) + vein2 * 0.3, 0.0, 0.7));   // lighter grey veining
        albedo *= mix(0.78, 1.0, sk);
    }
    if (m == 12) {
        float g = bvnoise(float3(P.x * 3.0, P.y * 55.0, P.z * 3.0)) * 0.6 + bvnoise(float3(P.x * 9.0, P.y * 150.0, P.z * 9.0)) * 0.4;
        albedo *= 0.82 + 0.3 * g;
    }
    if (m == 13) {
        // brushed metal: tinted reflections, a stretched soft highlight
        float3 R = reflect(-V, N);
        float brush = 0.92 + 0.08 * bvnoise(float3(P.x * 90.0, P.y * 6.0, P.z * 90.0));
        float3 env = bathEnv(R, u) * albedo * 0.85 * brush;
        float3 base = albedo * (amb * ao * 0.35 + keyCol * ndl * sh * 0.25);
        float spec = bGGX(N, V, L, 0.32) * u.keyDir.w * sh * 0.8;
        return float4((base + env * ao + albedo * spec) * mix(1.0, 0.9, 1.0 - ao), 1.0);
    }
    float3 col = albedo * (amb * ao * 0.95 + keyCol * ndl * sh * mix(0.55, 1.0, ao) * 0.62);
    if (m == 10 || m == 11 || m == 12) {
        float3 R = reflect(-V, N);
        float F = 0.04 + 0.96 * pow(1.0 - NdV, 5.0);
        float gl = m == 10 ? 0.9 : (m == 11 ? 0.35 : 0.25);
        float rough = m == 10 ? 0.16 : (m == 11 ? 0.3 : 0.4);
        col += float3(1.0, 0.98, 0.94) * bGGX(N, V, L, rough) * u.keyDir.w * sh * 0.5 * gl * ao;
        col += bathEnv(R, u) * F * 0.55 * gl * ao;
    }
    if (m == 2) {
        float fz = bhash3(floor(P * 70.0)) - 0.5;
        col *= 1.0 + 0.10 * fz;
        col += albedo * pow(1.0 - NdV, 2.0) * 0.10;                  // fluffy edge sheen
    }
    if (m == 1 || m == 4) {
        float3 R = reflect(-V, N);
        float F = 0.04 + 0.96 * pow(1.0 - NdV, 5.0);
        float rough = m == 4 ? 0.18 : 0.12;
        float spec = bGGX(N, V, L, rough) * u.keyDir.w * sh * 0.9;
        col += float3(1.0, 0.99, 0.96) * spec * ao;
        col += bathEnv(R, u) * F * (m == 4 ? 0.6 : 0.5) * ao;
        if (m == 4) {
            col += albedo * 0.18;                                    // inner glow of the jelly
            alpha = in.alpha;
        }
    }
    // faint depth fog toward the room tone, only far away
    float f = saturate((dist - 12.0) * 0.08) * u.fog.w;
    col = mix(col, u.fog.rgb, f);
    return float4(col, alpha);
}
