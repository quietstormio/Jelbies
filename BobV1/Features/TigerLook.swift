//
//  TigerLook.swift
//  Tiger (character 7, JellyRoster.tigerID): the plain body (no ears, no tail: feature `.none`) in orange, with rust stripes: three on the crown, two on each cheek
//  and three bands across the back.
//  Not offered anywhere (not in the intro, the Jelly Spring picker, the starter roster or any generator): reachable through `-NewGame bob,tiger` /
//  `-SetRoster` / `-ForceSpecies tiger` only, until the adoption round adds it.
//
//  The stripes are drawn by the matte, bath and jersey body shaders (TigerMarks.h). The shader finds a Tiger by its body mode (BlueBelly.mode 61 / 62),
//  which is keyed on this palette's exact flesh value (never equal to another species' colour, a Jelly Spring colour variant's, nor any park visitor's).
//  MelonRenderer draws the walking arm capsules and the foot beans again in the plain mode 62, so a limb piece never carries a stripe.
//

import simd
import Foundation

nonisolated enum TigerLook {
    /// The lit body tone (palette.flesh): a warm orange, fitted to the "Jelmiko Lineup" picture of the Tiger (redder and deeper than Pip's yellow, so the two never read as one animal).
    static let flesh = SIMD3<Float>(0.985, 0.593, 0.343)
    static let deep = SIMD3<Float>(0.886, 0.296, 0.130)
    /// sRGB 0...1 swatch (selection cards, portraits).
    static let swatch = SIMD3<Float>(0.965, 0.627, 0.353)
    static var palette: Palette {
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        return JellyPalettes.matte(Palette(name: "Tiger", flesh: flesh, fleshDeep: deep, pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                                           shadowTint: deep * 0.5 + flesh * 0.5, uiFlesh: flesh * 0.93))
    }
}
