//
//  GfxShaders.metal
//  Render-cost savers (new file: the locked body shader functions stay untouched in Shaders.metal).
//    gfxFullVS     full-screen triangle
//    gfxCacheFS    copies the cached, already resolved room colour 1:1 (read by pixel, so no filtering) into every MSAA sample
//    gfxPresentFS  copies the MetalFX output into the drawable 1:1
//

#include <metal_stdlib>
using namespace metal;

struct GfxOut { float4 position [[position]]; };

vertex GfxOut gfxFullVS(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    GfxOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

static float gfxHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// Storm weather on the window glass (the same function as roomWeatherPane in RoomShaders.metal; keep them identical). w = rain, flash, time, gloom; w2 = flash spot, -, render size.
static float3 gfxWeatherPane(float3 pane, float2 px, float4 w, float4 w2) {
    float lum = dot(pane, float3(0.3, 0.59, 0.11));
    float3 c = pane;
    if (w.w > 0.001) {
        float3 storm = float3(0.44, 0.50, 0.62) * (0.10 + 0.46 * lum);
        c = mix(c, storm, w.w * 0.88);
    }
    float unit = min(w2.z, w2.w);
    float2 s = px / unit;
    float flash = w.y;
    if (w.x > 0.001) {
        float sl = s.x * 92.0 + s.y * 14.0;
        float cell = floor(sl);
        float h = gfxHash(float2(cell, 3.0));
        float on = step(1.0 - 0.5 * w.x, gfxHash(float2(cell, 9.0)));
        float y = fract(s.y * (0.9 + h) - w.z * (0.55 + h * 0.6) + h * 7.0);
        float across = abs(fract(sl) - 0.5);
        float streak = smoothstep(0.17, 0.02, across) * smoothstep(0.0, 0.05, y) * smoothstep(0.30, 0.05, y) * on;
        float2 g = s * float2(30.0, 24.0);
        float2 id = floor(g);
        float2 jit = float2(gfxHash(id + 1.3), gfxHash(id + 5.1)) - 0.5;
        float drop = smoothstep(0.20, 0.04, length(fract(g) - 0.5 - jit * 0.5)) * step(0.80 - 0.1 * w.x, gfxHash(id + 9.7));
        float glint = (streak * 0.20 + drop * 0.13) * w.x;
        c += float3(0.70, 0.82, 1.0) * glint * (0.35 + lum) * (1.0 + 2.5 * flash);
    }
    if (flash > 0.001) {
        float gx = (px.x / w2.z - (0.1 + 0.8 * w2.x)) * 2.6;
        float glow = 0.6 + 0.4 * exp(-gx * gx);
        c += float3(0.74, 0.82, 1.0) * flash * 0.95 * glow;
    }
    return c;
}

struct GfxWeather { float4 w; float4 w2; };

/// The room-cache blit. The cache build marks window glass with alpha 2 (a resolved edge pixel keeps its glass coverage in alpha - 1); the storm is added there, per frame, so
/// the rain never invalidates the cache. Alpha out is always 1.
fragment float4 gfxCacheFS(GfxOut in [[stage_in]], texture2d<float> cache [[texture(0)]], constant GfxWeather& wx [[buffer(0)]]) {
    uint2 px = min(uint2(in.position.xy), uint2(cache.get_width() - 1, cache.get_height() - 1));
    float4 c = cache.read(px);
    if (c.a > 1.001) {
        if (wx.w.x + wx.w.y + wx.w.w > 0.001) { c.rgb = mix(c.rgb, gfxWeatherPane(c.rgb, in.position.xy, wx.w, wx.w2), min(c.a - 1.0, 1.0)); }
        c.a = 1.0;
    }
    return c;
}

fragment float4 gfxPresentFS(GfxOut in [[stage_in]], texture2d<float> src [[texture(0)]]) {
    uint2 px = min(uint2(in.position.xy), uint2(src.get_width() - 1, src.get_height() - 1));
    return src.read(px);
}
