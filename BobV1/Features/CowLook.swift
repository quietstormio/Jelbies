//
//  CowLook.swift
//  The cow family of the "Jelmiko Lineup" (2026-11-21): Moo 13 (white, near-black patches), Cocoa 14 (cream, brown patches), Blush 15 (pale pink, rose patches); feature `.none`, the plain body.
//  ONE patch layout (a few large irregular rounded patches: back, sides, one over an eye area, a small one on the head; face clear, no patch on the soles) in three palettes.
//  The shaders draw it (Melon/CowMarks.h, body modes 91 / 93 / 95 = tone 9, shape mode 1 / 3 / 5, in the matte, bath and jersey body shaders). THE TINTS ARE MIRRORED IN CowMarks.h.
//  The character is found by its body mode (BlueBelly.mode keyed on the palette's exact flesh value). Select in code: `JellyRoster.mooID / cocoaID / blushID` (13 / 14 / 15);
//  on the command line `-NewGame bob,moo`, `-SetRoster cocoa`, `-ForceSpecies blush`.
//

import simd
import Foundation

nonisolated enum CowLook {
    /// The patch tints are the drawing's (0.26 / 0.49,0.31,0.23 / 0.92,0.44,0.59) stretched toward the saturated end: the jelly shading lifts a dark patch toward grey (Moo read grey at 0.26).
    struct Look { let flesh: SIMD3<Float>, patch: SIMD3<Float>, mode: Float }
    static let looks: [Int: Look] = [
        JellyRoster.mooID: Look(flesh: SIMD3(0.957, 0.945, 0.925), patch: SIMD3(0.13, 0.13, 0.16), mode: 91),
        JellyRoster.cocoaID: Look(flesh: SIMD3(0.953, 0.902, 0.812), patch: SIMD3(0.40, 0.23, 0.16), mode: 93),
        JellyRoster.blushID: Look(flesh: SIMD3(0.976, 0.890, 0.910), patch: SIMD3(0.90, 0.36, 0.52), mode: 95),
    ]
    static var ids: [Int] { [JellyRoster.mooID, JellyRoster.cocoaID, JellyRoster.blushID] }
    static func palette(_ id: Int) -> Palette? {
        guard let l = looks[id], JellyRoster.baseNames.indices.contains(id) else { return nil }
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        let deep = l.flesh * 0.82
        return JellyPalettes.matte(Palette(name: JellyRoster.baseNames[id], flesh: l.flesh, fleshDeep: deep, pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                                           shadowTint: deep * 0.5 + l.flesh * 0.5, uiFlesh: l.flesh * 0.93))
    }
    /// sRGB 0...1 swatch (selection cards, portraits) = the flesh.
    static func swatch(_ id: Int) -> SIMD3<Float> { looks[id]?.flesh ?? SIMD3(0.70, 0.83, 0.945) }
    /// The body mode (91 / 93 / 95) of a body whose palette has this exact flesh value; nil for every other body.
    static func mode(forFlesh flesh: SIMD3<Float>) -> Float? {
        for (_, l) in looks where l.flesh == flesh { return l.mode }
        return nil
    }
}
