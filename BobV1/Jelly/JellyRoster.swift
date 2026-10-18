//
//  JellyRoster.swift
//  The Jellies of the room (1...3): who they are, what colour, where they spawn, and the UserDefaults keys of their saved state.
//
//  Launch flag: -BlobCount 1|2|3 (default 3). Jelly 0 is Bob (baby blue), 1 is Pip (yellow), 2 is Moss (green).
//  Persistence is keyed by id. Jelly 0's keys ARE the pre-multi-Jelly keys ("BlobNeeds.v1", "BlobGrime.v1", "BlobWords.v1"), so the phone's
//  existing Bob state (needs, dirt, his learned "come here") becomes Jelly 0's data with no copy and nothing lost; Jellies 1 and 2 get suffixed keys.
//  DropsWallet ("BlobDrops.v1") and the voice tutorial flag ("VoiceTutorial.v1") stay shared on purpose.
//

import Foundation
import simd

enum JellyKeys {
    static func needs(_ id: Int) -> String { suffixed(NeedsTuning.defaultsKey, id) }
    static func grime(_ id: Int) -> String { suffixed(GrimeTuning.defaultsKey, id) }
    static func words(_ id: Int) -> String { suffixed(VoiceTuning.defaultsKey, id) }
    private static func suffixed(_ legacy: String, _ id: Int) -> String { id == 0 ? legacy : "\(legacy).jelly\(id)" }
}

nonisolated enum JellyRoster {
    static let maxCount = 3
    static let names = ["Bob", "Pip", "Moss"]

    /// `-BlobCount 1|2|3`; default 3 in this build.
    static func launchCount(_ d: UserDefaults = .standard) -> Int {
        guard d.object(forKey: "BlobCount") != nil else { return maxCount }
        return min(max(d.integer(forKey: "BlobCount"), 1), maxCount)
    }

    /// Floor spots (x, z) the Jellies start on, spread over the visible floor so nobody overlaps (the floor is only ~2.2 wide at the body's height on a
    /// portrait phone, so they zig-zag in depth). One Jelly stays at the origin like before.
    static func spawnSpots(count: Int) -> [SIMD2<Float>] {
        switch count {
        case 1: return [SIMD2(0, 0)]
        case 2: return [SIMD2(0.1, 1.5), SIMD2(-0.2, -1.4)]
        default: return [SIMD2(-0.15, 1.6), SIMD2(-0.85, -1.7), SIMD2(0.85, -0.1)]
        }
    }

    /// Body colours: Bob is the model's palette (baby blue in the game); Pip is the existing yellow; Moss a green made the same way.
    static func palette(_ id: Int) -> Palette? {
        switch id {
        case 1: return PaletteKey.yellow.palette
        case 2: return JellyPalettes.green
        default: return nil
        }
    }

    /// sRGB 0...1 swatch for the roster card / selection preview.
    static func tint(_ id: Int) -> SIMD3<Float> {
        switch id {
        case 1: return SIMD3(0.99, 0.90, 0.62)
        case 2: return SIMD3(0.70, 0.90, 0.66)
        default: return SIMD3(0.70, 0.83, 0.945)
        }
    }

    static func selectBlobs(count: Int) -> [SelectBlob] {
        (0..<min(max(count, 1), maxCount)).map { SelectBlob(id: $0, name: names[$0], tint: tint($0)) }
    }
}

/// Colours that are not part of `PaletteKey` (that enum is hashed by the base-body lock, so it gets no new case).
nonisolated enum JellyPalettes {
    /// The same soft matte treatment `PaletteKey.palette` applies to its base colours.
    static func matte(_ base: Palette) -> Palette {
        var p = base
        func clampT(_ c: SIMD3<Float>) -> SIMD3<Float> { simd_clamp(c, SIMD3(repeating: 0.01), SIMD3(repeating: 0.985)) }
        let f = p.flesh, d = p.fleshDeep
        p.pale = clampT(f * 0.985)
        p.skin = d * 0.985
        p.stripe = clampT(f + (SIMD3<Float>(repeating: 1) - f) * 0.35)
        p.extra = d + (SIMD3<Float>(repeating: 1) - d) * 0.30
        p.matte = true
        return p
    }

    /// Moss: a soft pastel green in the same family as baby blue / butter.
    static let green: Palette = {
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        return matte(Palette(name: "Mint green", flesh: [0.560, 0.870, 0.585], fleshDeep: [0.290, 0.650, 0.350],
                             pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                             shadowTint: [0.500, 0.745, 0.530], uiFlesh: [0.470, 0.800, 0.505]))
    }()
}
