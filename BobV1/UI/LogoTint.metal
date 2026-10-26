//  LogoTint.metal
//  Recolours the Jelbies logo: each pixel is projected onto the white-to-blue line (t = 0 white, 1 the logo's #8DB8E0-ish outline blue)
//  and re-mixed as white-to-`outline`. Alpha is kept. With the Sky Blue outline this is the identity.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]] half4 logoTint(float2 position, half4 color, half4 outline) {
    if (color.a <= 0.001h) return color;
    float3 c = float3(color.rgb) / float(color.a);                 // SwiftUI hands us premultiplied colour
    const float3 blue = float3(141.0, 184.0, 223.0) / 255.0;
    float3 v = float3(1.0) - blue;
    float t = clamp(dot(float3(1.0) - c, v) / dot(v, v), 0.0, 1.0);
    float3 o = mix(float3(1.0), float3(outline.rgb), t);
    return half4(half3(o) * color.a, color.a);
}
