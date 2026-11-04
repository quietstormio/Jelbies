//
//  PandaLook.swift
//  Panda (character 6, JellyRoster.pandaID): Teddy's body-mesh bear ears + pom (feature `.ears`, TeddyBean) on a soft warm-white body with charcoal markings.
//  Not offered anywhere (not in the intro, the Jelly Spring picker, the starter roster or any generator): reachable through `-NewGame bob,panda` /
//  `-SetRoster` / `-ForceSpecies panda`, exactly like Teddy and Pearl.
//
//  The markings are drawn by the matte body shader (PandaMarks.h: eye patches, shoulder band, arms, feet) and by the renderer drawing the ears + pom
//  + the walking arm / foot pieces in the charcoal too (MelonRenderer: the Panda limb draw). The shader finds a Panda by its body mode (BlueBelly.mode 51 / 52),
//  which is keyed on this palette's exact flesh value (never equal to Pearl's white, nor to any park visitor's colour).
//

import simd
import Foundation

nonisolated enum PandaLook {
    /// The lit body tone (palette.flesh): a soft warm white, a hair warmer than Pearl's cool white so the two read as different animals side by side.
    static let flesh = SIMD3<Float>(0.950, 0.935, 0.905)
    static let deep = SIMD3<Float>(0.700, 0.680, 0.690)
    /// sRGB 0...1 swatch (selection cards, portraits).
    static let swatch = SIMD3<Float>(0.97, 0.96, 0.94)
    static var palette: Palette {
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        return JellyPalettes.matte(Palette(name: "Panda", flesh: flesh, fleshDeep: deep, pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                                           shadowTint: SIMD3(0.780, 0.765, 0.790), uiFlesh: SIMD3(0.930, 0.915, 0.890)))
    }
}
