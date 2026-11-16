//
//  BerryLook.swift
//  Berry (character 8, JellyRoster.berryID): the plain body (feature `.none`) in soft pink, with cream seeds dotted over the body (none on the face)
//  and a leafy green top. The tiny stem nub of the design is a 3D piece for a later round: it is NOT here.
//  Not offered anywhere (not in the intro, the Jelly Spring picker, the starter roster or any generator): reachable through `-NewGame bob,berry` /
//  `-SetRoster` / `-ForceSpecies berry` only, until the adoption round adds it.
//
//  The seeds and the leaf are drawn by the matte, bath and jersey body shaders (BerryMarks.h). The shader finds a Berry by its body mode (BlueBelly.mode 71 / 72),
//  which is keyed on this palette's exact flesh value (never equal to another species' colour, a Jelly Spring colour variant's, nor any park visitor's).
//  MelonRenderer draws the walking arm capsules and the foot beans again in the plain mode 72, so a limb piece never carries a seed.
//

import simd
import Foundation

nonisolated enum BerryLook {
    /// The lit body tone (palette.flesh): a soft strawberry pink, fitted to the "Jelmiko Lineup" picture of the Berry.
    static let flesh = SIMD3<Float>(0.934, 0.624, 0.718)
    static let deep = SIMD3<Float>(0.732, 0.324, 0.431)
    /// sRGB 0...1 swatch (selection cards, portraits).
    static let swatch = SIMD3<Float>(0.976, 0.655, 0.733)
    static var palette: Palette {
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        return JellyPalettes.matte(Palette(name: "Berry", flesh: flesh, fleshDeep: deep, pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                                           shadowTint: deep * 0.5 + flesh * 0.5, uiFlesh: flesh * 0.93))
    }
}
