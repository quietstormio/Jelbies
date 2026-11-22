//
//  MarbleLook.swift
//  Marble 9 and Midnight 18 of the "Jelmiko Lineup" (2026-11-21); feature `.none`, the plain body, no extras.
//  Marble: pale aqua with white marble veins baked from the drawings (Melon/MarbleMarks.h, tools/marble_bake.py), body mode 121 (tone 12, shape mode 1).
//  Midnight: near-black glossy body; the eyes and brows are pale lilac (fsEyesMatte), body mode 131 (tone 13, shape mode 1).
//  The flesh stays LineupLook's (the drawing's colour dot); the character is found by its body mode (BlueBelly.mode keyed on the exact flesh value).
//  Not offered anywhere: `-NewGame bob,marble`, `-SetRoster midnight`, `-ForceSpecies marble`. THE TINT IN MarbleMarks.h is mirrored here (vein 0.97, 1.0, 0.99).
//

import simd
import Foundation

nonisolated enum MarbleLook {
    static let veinTint = SIMD3<Float>(0.97, 1.0, 0.99)
    static let modes: [Int: Float] = [JellyRoster.marbleID: 121, JellyRoster.midnightID: 131]
    /// The body mode (121 / 131) of a body whose palette has this exact flesh value; nil for every other body.
    static func mode(forFlesh flesh: SIMD3<Float>) -> Float? {
        for (id, m) in modes where LineupLook.fleshByID[id] == flesh { return m }
        return nil
    }
}
