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

fragment float4 gfxCacheFS(GfxOut in [[stage_in]], texture2d<float> cache [[texture(0)]]) {
    uint2 px = min(uint2(in.position.xy), uint2(cache.get_width() - 1, cache.get_height() - 1));
    return cache.read(px);
}

fragment float4 gfxPresentFS(GfxOut in [[stage_in]], texture2d<float> src [[texture(0)]]) {
    uint2 px = min(uint2(in.position.xy), uint2(src.get_width() - 1, src.get_height() - 1));
    return src.read(px);
}
