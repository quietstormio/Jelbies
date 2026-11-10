//
//  ParkSlideSkin.swift
//  The park's slide look (2026-11-09): the room's `decor_slide.bin` is one part with the toy palette baked per vertex (cream posts, honey tower, mint chute, pink trim). The park
//  draws the SAME geometry with a natural skin: stained timber tower, galvanised steel chute with a brighter centre streak, forest-green posts and rails. Built once by
//  recolouring the loaded art by colour class; positions and normals are untouched (the ride code depends on the geometry), and the home slide never sees it.
//

import simd
import Foundation

nonisolated enum ParkSlideSkin {
    /// The slide art in its park colours (nil when the resource is missing).
    static let art: DecorMeshes.Art? = {
        guard var a = DecorMeshes.loaded[.slide] else { return nil }
        func srgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { OKLab.srgbToLinear(SIMD3(r, g, b)) }
        func lum(_ c: SIMD3<Float>) -> Float { simd_dot(c, SIMD3(0.2126, 0.7152, 0.0722)) }
        let timber = srgb(0.50, 0.34, 0.20), steel = srgb(0.70, 0.74, 0.78), green = srgb(0.12, 0.30, 0.20), darkSteel = srgb(0.46, 0.50, 0.54)
        let refCream = lum(srgb(0.97, 0.94, 0.88)), refHoney = lum(srgb(0.97, 0.80, 0.35)), refMint = lum(srgb(0.62, 0.85, 0.69)), refPink = lum(srgb(0.91, 0.54, 0.64))
        // centre of the chute (the mint vertices)
        var sx: Float = 0, n: Float = 0
        for p in a.parts { for i in 0..<p.colors.count where isMint(p.colors[i]) { sx += p.positions[i].x; n += 1 } }
        let cx = n > 0 ? sx / n : 0
        for pi in a.parts.indices {
            for i in 0..<a.parts[pi].colors.count {
                let c = a.parts[pi].colors[i], l = lum(c)
                let s = toSrgb(c)
                var out: SIMD3<Float>
                if isMint(c) {
                    out = steel * min(1.15, max(0.6, l / refMint))
                    if fabsf(a.parts[pi].positions[i].x - cx) < 0.13 { out = simd_min(out * 1.12, SIMD3(repeating: 1)) }
                } else if s.x > 0.85, s.y > 0.82, s.z > 0.75 { out = green * min(1.3, max(0.5, l / refCream))
                } else if s.x > 0.8, s.y > 0.62, s.z < 0.55, s.x - s.z > 0.4, s.y > s.x * 0.74 { out = timber * min(1.3, max(0.5, l / refHoney))
                } else { out = darkSteel * min(1.3, max(0.5, l / refPink)) }
                a.parts[pi].colors[i] = out
            }
        }
        return a
    }()
    private static func toSrgb(_ c: SIMD3<Float>) -> SIMD3<Float> {
        func f(_ v: Float) -> Float { v <= 0.0031308 ? v * 12.92 : 1.055 * powf(v, 1 / 2.4) - 0.055 }
        return SIMD3(f(c.x), f(c.y), f(c.z))
    }
    private static func isMint(_ c: SIMD3<Float>) -> Bool {
        let s = toSrgb(c)
        return s.y > s.x + 0.12 && s.y >= s.z - 0.02
    }
}
