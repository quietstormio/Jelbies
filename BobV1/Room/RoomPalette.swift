//
//  RoomPalette.swift
//  Monochrome palette derived from one tint via OKLCH (https://bottosson.github.io/posts/oklab/).
//

import simd
import Foundation

/// OKLab <-> linear sRGB (Bjorn Ottosson).
enum OKLab {
    static func fromLinear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = cbrtf(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z)
        let m = cbrtf(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z)
        let s = cbrtf(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z)
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func toLinear(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        let l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
        let m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
        let s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return SIMD3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                     -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                     -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    static func srgbToLinear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(f(c.x), f(c.y), f(c.z))
    }
    private static func f(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4) }

    /// Polar OKLCH (h in radians) to linear sRGB, reducing chroma until the colour is in gamut.
    static func lchToLinear(L: Float, C: Float, h: Float) -> SIMD3<Float> {
        var c = C
        for _ in 0..<24 {
            let rgb = toLinear(SIMD3(L, c * cosf(h), c * sinf(h)))
            if rgb.x >= 0 && rgb.y >= 0 && rgb.z >= 0 && rgb.x <= 1 && rgb.y <= 1 && rgb.z <= 1 { return rgb }
            c *= 0.9
        }
        return SIMD3(repeating: L * L * L)
    }
}

/// One base colour (sRGB 0...1) drives every surface in the room. Later a user setting.
struct RoomTheme: Equatable {
    var tint: SIMD3<Float>

    /// Warm soft cream / peach.
    static let defaultTint = SIMD3<Float>(0.96, 0.78, 0.66)

    init(tint: SIMD3<Float> = RoomTheme.defaultTint) { self.tint = tint }

    static let lightness: [Float] = [0.30, 0.45, 0.62, 0.78, 0.90]
    private static let chromaProfile: [Float] = [0.55, 0.85, 1.0, 0.85, 0.5]
    static let swatchCount = 5

    /// Hue (radians) and base chroma of the tint in OKLCH.
    var hueChroma: (h: Float, c: Float) {
        let lab = OKLab.fromLinear(OKLab.srgbToLinear(tint))
        return (atan2f(lab.z, lab.y), min(max(sqrtf(lab.y * lab.y + lab.z * lab.z), 0.04), 0.10))
    }

    /// Swatch i = 0 (darkest) ... 4 (lightest), linear sRGB. Highlights drift warm (+8 deg), shadows cool (-8 deg).
    func swatch(_ i: Int) -> SIMD3<Float> {
        let k = min(max(i, 0), 4)
        let (h, c) = hueChroma
        let nudge = Float(k - 2) / 2 * (8 * Float.pi / 180)
        return OKLab.lchToLinear(L: Self.lightness[k], C: c * Self.chromaProfile[k] * 1.0, h: h + nudge)
    }

    var swatches: [SIMD3<Float>] { (0..<Self.swatchCount).map(swatch) }
}

/// Named surface -> swatch assignments.
enum RoomSwatch {
    static let soil = 0
    static let sofa = 1, pot = 1, leaf = 1, tableLeg = 1
    static let floor = 2, cushion = 2, tableTop = 2, leafLight = 2
    static let wall = 3, rugBand = 3
    static let rug = 4, frame = 4, pane = 4
}
