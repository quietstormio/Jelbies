//
//  FinishLook.swift
//  The "finish" family of the "Jelmiko Lineup" (2026-11-21): the metals Gold 10, Silver 11, Bronze 26 (polished, mirror-ish sheen) and the jewels Ruby 17, Emerald 23, Sapphire 24,
//  Amethyst 25 (deep saturated glossy jelly); every one wears tiny white sparkle stars. Feature `.none`, the plain body (no wings / antennas / extras: the drawings have none).
//  The shaders draw it (Melon/FinishMarks.h, body modes 101...107 = tone 10, shape mode 1...7, in the matte, bath and jersey body shaders). THE TINTS ARE MIRRORED IN FinishMarks.h.
//  The character is found by its body mode (BlueBelly.mode keyed on the palette's exact flesh value). Not offered anywhere: `-NewGame bob,gold`, `-SetRoster ruby`, `-ForceSpecies amethyst`.
//

import simd
import Foundation

nonisolated enum FinishLook {
    struct Look { let flesh: SIMD3<Float>, mode: Float, metal: Bool }
    static let looks: [Int: Look] = [
        JellyRoster.goldID: Look(flesh: SIMD3(0.941, 0.761, 0.235), mode: 101, metal: true),
        JellyRoster.silverID: Look(flesh: SIMD3(0.788, 0.808, 0.839), mode: 102, metal: true),
        JellyRoster.bronzeID: Look(flesh: SIMD3(0.722, 0.412, 0.180), mode: 103, metal: true),
        JellyRoster.rubyID: Look(flesh: SIMD3(0.784, 0.137, 0.310), mode: 104, metal: false),
        JellyRoster.emeraldID: Look(flesh: SIMD3(0.122, 0.710, 0.478), mode: 105, metal: false),
        JellyRoster.sapphireID: Look(flesh: SIMD3(0.141, 0.286, 0.784), mode: 106, metal: false),
        JellyRoster.amethystID: Look(flesh: SIMD3(0.604, 0.271, 0.839), mode: 107, metal: false),
    ]
    static var ids: [Int] { [JellyRoster.goldID, JellyRoster.silverID, JellyRoster.bronzeID, JellyRoster.rubyID, JellyRoster.emeraldID, JellyRoster.sapphireID, JellyRoster.amethystID] }
    static func palette(_ id: Int) -> Palette? {
        guard let l = looks[id], JellyRoster.baseNames.indices.contains(id) else { return nil }
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        let deep = l.flesh * 0.82
        return JellyPalettes.matte(Palette(name: JellyRoster.baseNames[id], flesh: l.flesh, fleshDeep: deep, pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                                           shadowTint: deep * 0.5 + l.flesh * 0.5, uiFlesh: l.flesh * 0.93))
    }
    /// sRGB 0...1 swatch (selection cards, portraits) = the flesh.
    static func swatch(_ id: Int) -> SIMD3<Float> { looks[id]?.flesh ?? SIMD3(0.70, 0.83, 0.945) }
    /// The body mode (101...107) of a body whose palette has this exact flesh value; nil for every other body.
    static func mode(forFlesh flesh: SIMD3<Float>) -> Float? {
        for (_, l) in looks where l.flesh == flesh { return l.mode }
        return nil
    }
}
