//
//  ParkSlideSkin.swift
//  The park's slide look (2026-11-09): the room's `decor_slide.bin` is one part with the toy palette baked per vertex (cream posts, honey tower, mint chute, pink trim). The park
//  draws the SAME geometry with a natural skin: stained timber platform and step, a signal-red chute with a lighter centre streak, galvanised steel side walls, forest-green posts. Built once by
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
        // round 5: from the park camera the old skin read as a grey box. Now: a muted terracotta chute (round 8: was signal red), galvanised steel side walls and top bars, stained timber platform and step block,
        // dark forest-green posts and caps. Same geometry, same anchors.
        let red = srgb(0.72, 0.41, 0.28), steel = srgb(0.60, 0.64, 0.67), timber = srgb(0.52, 0.35, 0.20), step = srgb(0.64, 0.46, 0.27), green = srgb(0.10, 0.27, 0.18)
        let refCream = lum(srgb(0.97, 0.94, 0.88)), refHoney = lum(srgb(0.97, 0.80, 0.35)), refMint = lum(srgb(0.62, 0.85, 0.69)), refCoral = lum(srgb(0.96, 0.55, 0.43)), refPink = lum(srgb(0.91, 0.54, 0.64))
        // centre and half width of the chute (the mint vertices facing up)
        var sx: Float = 0, n: Float = 0
        for p in a.parts { for i in 0..<p.colors.count where isMint(p.colors[i]) && p.normals[i].y > 0.45 { sx += p.positions[i].x; n += 1 } }
        let cx = n > 0 ? sx / n : 0
        var half: Float = 0.01
        for p in a.parts { for i in 0..<p.colors.count where isMint(p.colors[i]) && p.normals[i].y > 0.45 { half = max(half, fabsf(p.positions[i].x - cx)) } }
        func scaled(_ c: SIMD3<Float>, _ l: Float, _ ref: Float) -> SIMD3<Float> { c * min(1.3, max(0.55, l / ref)) }
        for pi in a.parts.indices {
            for i in 0..<a.parts[pi].colors.count {
                let c = a.parts[pi].colors[i], l = lum(c), s = toSrgb(c), nrm = a.parts[pi].normals[i]
                var out: SIMD3<Float>
                if isMint(c) {
                    if nrm.y > 0.45 {
                        out = scaled(red, l, refMint)
                        let off = fabsf(a.parts[pi].positions[i].x - cx) / half
                        if off < 0.3 { out = simd_min(out * 1.18, SIMD3(repeating: 1)) } else if off > 0.85 { out *= 0.78 }          // lighter centre streak, darker edges
                    } else { out = scaled(green, l, refMint) }          // the posts
                } else if s.x > 0.85, s.y > 0.82, s.z > 0.75 { out = scaled(steel, l, refCream)
                } else if s.x > 0.8, s.y > 0.62, s.z < 0.55, s.x - s.z > 0.4, s.y > s.x * 0.74 { out = scaled(timber, l, refHoney)
                } else if s.y > s.z { out = scaled(step, l, refCoral)
                } else { out = scaled(green, l, refPink) }
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
