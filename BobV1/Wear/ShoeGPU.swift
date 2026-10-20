//
//  ShoeGPU.swift
//  The shoe paint specs (ShoePaint) baked into a constant table the room fragment shader reads (roomShoe in RoomShaders.metal), so every band, stripe,
//  cap, collar, lace, dot and glow window is evaluated PER PIXEL from the interpolated (u, v, sx) with a one-pixel anti-aliased edge, instead of
//  per vertex colours that smear across the triangles.
//
//  Table (float4 units). Per look (index = WearLook.shoes order): [header] + maxLayers x 9:
//    header      base.rgb, layerCount
//    layer + 0   colour.rgb (linear), alpha
//    layer + 1   glow, isBody ("$body": the Jelly's colour), soft (a gradient by design: shine / sheen / ombre), speckle density (0 = none)
//    layer + 2/3/4  windows of u / v / sx: a, b, edge, unused (a = -1000 / b = 1000: open). Edges are the narrowed (x0.5) ones the vertex painter used.
//    layer + 5   ellipse centre (v, sx), radius (v, sx)
//    layer + 6   ellipse edge, hasEllipse, bar count, bar half-width
//    layer + 7   bar centres v0...v3
//    layer + 8   bar centres v4, v5, bar edge, unused
//  A shoe vertex carries: pos.w = material 16 + look index, colour = (u, v, sx, glow phase), normal.w = the body colour packed as 3 sRGB bytes.
//

import simd
import Foundation

nonisolated enum ShoeGPU {
    static let firstMaterial: Float = 16
    static let maxLayers = 12, layerFloats = 9
    static var lookStride: Int { 1 + maxLayers * layerFloats }

    static func index(_ look: WearLook) -> Int { WearLook.shoes.firstIndex(of: look) ?? 0 }
    static func material(_ look: WearLook) -> Float { firstMaterial + Float(index(look)) }

    /// The body colour (linear) as three sRGB bytes in one float (24 bits, exact in a Float32).
    static func packBody(_ lin: SIMD3<Float>) -> Float {
        func enc(_ x: Float) -> Float { let c = min(max(x, 0), 1); return c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055 }
        func byte(_ x: Float) -> Int { Int((enc(x) * 255).rounded()) }
        return Float(byte(lin.x) << 16 | byte(lin.y) << 8 | byte(lin.z))
    }

    static let table: [SIMD4<Float>] = {
        var t = [SIMD4<Float>](repeating: .zero, count: WearLook.shoes.count * lookStride)
        for (li, look) in WearLook.shoes.enumerated() {
            guard let st = ShoePaint.style(look) else { continue }
            let o = li * lookStride
            let layers = Array(st.layers.prefix(maxLayers))
            t[o] = SIMD4(st.base, Float(layers.count))
            func win(_ w: ShoePaint.Window?, narrow: Float = 0.5) -> SIMD4<Float> {
                guard let w else { return SIMD4(-1000, 1000, 0.01, 0) }
                return SIMD4(w.a ?? -1000, w.b ?? 1000, w.e * narrow, 0)
            }
            for (k, var L) in layers.enumerated() {
                // the body hides most of the foot, so the toe is what shows: keep the toe cap a cap (same rule as ShoePaint.paintVertices)
                if L.name.hasPrefix("toe_cap"), !L.name.contains("stitch"), let a = L.v?.a, a < 0.9 { L.v?.a = a + 0.07 }
                let b = o + 1 + k * layerFloats
                t[b] = SIMD4(L.colour ?? .zero, L.alpha)
                let soft = L.name.contains("shine") || L.name.contains("sheen") || L.name.contains("ombre")
                t[b + 1] = SIMD4(L.glow ? 1 : 0, L.colour == nil ? 1 : 0, soft ? 1 : 0, L.speckle.map { $0.density } ?? 0)
                t[b + 2] = win(L.u); t[b + 3] = win(L.v); t[b + 4] = win(L.sx)
                if let e = L.ellipse {
                    t[b + 5] = SIMD4(e.c.x, e.c.y, e.r.x, e.r.y)
                    t[b + 6].x = e.e; t[b + 6].y = 1
                }
                if let br = L.bars {
                    let v = Array(br.v.prefix(6)) + [Float](repeating: 0, count: max(0, 6 - br.v.count))
                    t[b + 6].z = Float(min(br.v.count, 6)); t[b + 6].w = br.hw
                    t[b + 7] = SIMD4(v[0], v[1], v[2], v[3])
                    t[b + 8] = SIMD4(v[4], v[5], br.e, 0)
                }
            }
        }
        return t
    }()
}
