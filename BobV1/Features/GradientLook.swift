//
//  GradientLook.swift
//  The gradient family of the "Jelmiko Lineup" (look phase, 2026-11-18): Sunset 16, Cotton Candy 19, Ocean 20, Lemon-Lime 21, Lagoon 22 (feature `.none`, the plain body).
//  The body is painted in three stops by its height: below `tLo` the bottom colour, above `tHi` the top colour, the MIDDLE stop (= the palette's flesh) at `tMid`.
//  t = height on the body: 0 = the feet, 1 = the crown. The shaders draw it (Melon/GradientMarks.h, body modes 81...85 in the matte, bath and jersey body shaders);
//  THE NUMBERS BELOW ARE MIRRORED IN GradientMarks.h: the two must match.
//  The shader finds the character by its body mode (BlueBelly.mode, keyed on the palette's exact flesh value: never equal to another species' colour, a variant's or a park visitor's).
//  Not offered anywhere: reachable through `-NewGame` / `-SetRoster` / `-ForceSpecies` only.
//

import simd
import Foundation

nonisolated enum GradientLook {
    struct Stops {
        let bottom: SIMD3<Float>, middle: SIMD3<Float>, top: SIMD3<Float>
        let tLo: Float, tMid: Float, tHi: Float
        let mode: Float          // the body mode 81...85
    }
    /// Stops by character id (sRGB 0...1, from the lineup's colour dots).
    static let stops: [Int: Stops] = [
        JellyRoster.sunsetID: Stops(bottom: SIMD3(0.988, 0.847, 0.353), middle: SIMD3(0.976, 0.545, 0.227), top: SIMD3(0.933, 0.231, 0.231), tLo: 0.28, tMid: 0.52, tHi: 0.84, mode: 81),
        JellyRoster.cottonCandyID: Stops(bottom: SIMD3(0.561, 0.784, 0.973), middle: SIMD3(0.804, 0.659, 0.941), top: SIMD3(0.969, 0.612, 0.753), tLo: 0.30, tMid: 0.55, tHi: 0.86, mode: 82),
        JellyRoster.oceanID: Stops(bottom: SIMD3(0.153, 0.224, 0.604), middle: SIMD3(0.310, 0.663, 0.910), top: SIMD3(0.616, 0.922, 0.851), tLo: 0.32, tMid: 0.56, tHi: 0.86, mode: 83),
        JellyRoster.lemonLimeID: Stops(bottom: SIMD3(0.659, 0.886, 0.298), middle: SIMD3(0.821, 0.886, 0.325), top: SIMD3(0.984, 0.886, 0.353), tLo: 0.36, tMid: 0.58, tHi: 0.80, mode: 84),
        JellyRoster.lagoonID: Stops(bottom: SIMD3(0.949, 0.420, 0.710), middle: SIMD3(0.627, 0.439, 0.910), top: SIMD3(0.373, 0.878, 0.839), tLo: 0.34, tMid: 0.58, tHi: 0.86, mode: 85),
    ]
    /// Opal 12 (body mode 86): not a height gradient but ONE cyclic plane wave of colour through the rest body (fitted to the lineup drawing; the same 3D wave from every side).
    /// THE NUMBERS BELOW ARE MIRRORED IN GradientMarks.h (the bm 6 branch): the two must match.
    /// phase = opalWaveScale * dot(Q, opalWaveDir) + opalWavePhase; u = fract(phase) * 5; the stops blend with smoothstep, the fifth back into the first.
    enum Opal {
        static let mode: Float = 86
        static let stops: [SIMD3<Float>] = [SIMD3(0.976, 0.761, 0.824), SIMD3(0.969, 0.839, 0.753), SIMD3(0.784, 0.902, 0.839), SIMD3(0.769, 0.855, 0.965), SIMD3(0.839, 0.796, 0.957)]   // pink, peach, mint, sky, lilac
        static let waveDir = SIMD3<Float>(0.640, 0.583, 0.502)
        static let waveScale: Float = 1.40, wavePhase: Float = 0.025
        static let flesh = SIMD3<Float>(0.871, 0.829, 0.869)
        static let swatch = SIMD3<Float>(0.937, 0.820, 0.902)
    }
    /// The palette of gradient character `id` (nil when `id` is not one of the five or Opal); the flesh is the middle stop (Opal: its own flesh).
    static func palette(_ id: Int) -> Palette? {
        guard JellyRoster.baseNames.indices.contains(id) else { return nil }
        let flesh: SIMD3<Float>
        if id == JellyRoster.opalID { flesh = Opal.flesh } else if let s = stops[id] { flesh = s.middle } else { return nil }
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        let deep = flesh * 0.82
        return JellyPalettes.matte(Palette(name: JellyRoster.baseNames[id], flesh: flesh, fleshDeep: deep, pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                                           shadowTint: deep * 0.5 + flesh * 0.5, uiFlesh: flesh * 0.93))
    }
    /// sRGB 0...1 swatch (selection cards, portraits) = the middle stop.
    static func swatch(_ id: Int) -> SIMD3<Float> { id == JellyRoster.opalID ? Opal.swatch : (stops[id]?.middle ?? SIMD3(0.70, 0.83, 0.945)) }
    /// The body mode (81...86) of a body whose palette has this exact flesh value; nil for every other body.
    static func mode(forFlesh flesh: SIMD3<Float>) -> Float? {
        if flesh == Opal.flesh { return Opal.mode }
        for (_, s) in stops where s.middle == flesh { return s.mode }
        return nil
    }
}
