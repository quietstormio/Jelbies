//
//  LineupLook.swift
//  The 12 plain placeholders of the "Jelmiko Lineup" characters (look phase, 2026-11-18; Opal 12 now has its real look in GradientLook.swift): Marble 9, Gold 10, Silver 11, Moo 13, Cocoa 14, Blush 15, Ruby 17,
//  Midnight 18, Emerald 23, Sapphire 24, Amethyst 25 and Bronze 26 (JellyRoster.marbleID ... bronzeID). PLACEHOLDERS ONLY: the plain body (feature `.none`) in the drawing's
//  base colour, no marks. Each family replaces its entries with its real look in a later commit (the gradient family already has it: GradientLook.swift).
//  Not offered anywhere (not in the intro, the Jelly Spring picker, the starter roster, the park or any generator): reachable through `-NewGame` / `-SetRoster` / `-ForceSpecies` only.
//  The body mode stays 0 (BlueBelly.mode): the flesh values are unique, so no shader branch ever mistakes one for another species.
//

import simd
import Foundation

nonisolated enum LineupLook {
    /// The lit body tone (palette.flesh) by character id: the colour dot of the drawing in the lineup (sRGB 0...1).
    static let fleshByID: [Int: SIMD3<Float>] = [
        JellyRoster.marbleID: SIMD3(0.525, 0.863, 0.812),
        JellyRoster.goldID: SIMD3(0.941, 0.761, 0.235),
        JellyRoster.silverID: SIMD3(0.788, 0.808, 0.839),
        JellyRoster.mooID: SIMD3(0.957, 0.945, 0.925),
        JellyRoster.cocoaID: SIMD3(0.953, 0.902, 0.812),
        JellyRoster.blushID: SIMD3(0.976, 0.890, 0.910),
        JellyRoster.rubyID: SIMD3(0.784, 0.137, 0.310),
        JellyRoster.midnightID: SIMD3(0.165, 0.157, 0.188),
        JellyRoster.emeraldID: SIMD3(0.122, 0.710, 0.478),
        JellyRoster.sapphireID: SIMD3(0.141, 0.286, 0.784),
        JellyRoster.amethystID: SIMD3(0.604, 0.271, 0.839),
        JellyRoster.bronzeID: SIMD3(0.722, 0.412, 0.180),
    ]
    /// The palette of placeholder `id` (nil when `id` is not one of the 13).
    static func palette(_ id: Int) -> Palette? {
        guard let flesh = fleshByID[id], JellyRoster.baseNames.indices.contains(id) else { return nil }
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        let deep = flesh * 0.82
        return JellyPalettes.matte(Palette(name: JellyRoster.baseNames[id], flesh: flesh, fleshDeep: deep, pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                                           shadowTint: deep * 0.5 + flesh * 0.5, uiFlesh: flesh * 0.93))
    }
    /// sRGB 0...1 swatch (selection cards, portraits) = the flesh.
    static func swatch(_ id: Int) -> SIMD3<Float> { fleshByID[id] ?? SIMD3(0.70, 0.83, 0.945) }
}
