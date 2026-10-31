//
//  WhiteWing.swift
//  LOOK-ONLY candidate species (placeholder name "whitewing"): Bob's body in a clean soft white, plus Lavender's wing feature in a pale tint.
//  It is also the real character Pearl (id 5, JellyRoster.pearlID, added for the phone's new game); the forced look still works for captures. Wired into no player-facing surface (intro, Jelly Spring, starters); it only exists when the launch argument
//  `-ForceSpecies whitewing` (or `whitewing:<character id>`, default character 0) makes one roster character LOOK like it, for captures. Saved data
//  stays keyed by the real character, so an existing save loads unchanged. The wings are `JellyFeature.wings` untouched (same art, hinges, clamps,
//  clearance tables); only their vertex colours are re-mapped (FeatureMeshes.prepare, `WingTint`).
//

import Foundation
import simd

/// A wing colour ramp: the art's vertex colours run from a deep tone (the wing's rim / veins) to a light one (the membrane); each vertex is re-coloured
/// along deep -> mid -> light by where its luminance sits between the art's own darkest and lightest.
nonisolated struct WingTint: Hashable, Sendable {
    var name: String
    /// A pale wing seen from behind (away from the key light, over the room's warm ambient) would go brown-grey, so it gets a little self-light: the room
    /// shader adds `albedo * 1.7 * (ao - 1)` for any baked ao above 1 (the light-up sneakers' glow). The art's own AO still scales it, so the feather
    /// hollows stay a touch darker than the ridges.
    var glow: Float = 0.28
    var deep: SIMD3<Float>, mid: SIMD3<Float>, light: SIMD3<Float>
    var key: String { String(format: "%@%.2f|%.3f,%.3f,%.3f/%.3f,%.3f,%.3f/%.3f,%.3f,%.3f", name, glow, deep.x, deep.y, deep.z, mid.x, mid.y, mid.z, light.x, light.y, light.z) }
    /// The art's own ramp (Lavender's purples): darkest and lightest luminance.
    static let artLo: Float = 0.48, artHi: Float = 0.87
    func recolour(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = 0.299 * c.x + 0.587 * c.y + 0.114 * c.z
        let t = simd_clamp((l - Self.artLo) / (Self.artHi - Self.artLo), 0, 1)
        return t < 0.5 ? deep + (mid - deep) * (t * 2) : mid + (light - mid) * (t * 2 - 1)
    }
}

nonisolated enum WhiteWing {
    static let forceKey = "ForceSpecies"
    static let name = "whitewing"

    /// The three wing tints on the options board (pearl is the working default).
    /// (Albedo targets for the room shader, which tone-maps: values above 1 are fine and keep a pale wing white in the shade.)
    static let tintPearl = WingTint(name: "pearl", deep: [1.00, 0.85, 0.70], mid: [1.10, 1.00, 0.88], light: [1.15, 1.12, 1.05])
    static let tintSilver = WingTint(name: "silver", deep: [0.72, 0.88, 1.10], mid: [0.88, 1.02, 1.20], light: [1.05, 1.12, 1.25])
    static let tintIris = WingTint(name: "iris", deep: [0.98, 0.84, 1.12], mid: [1.10, 0.96, 1.10], light: [1.18, 1.10, 1.15])
    static let tints = [tintPearl, tintSilver, tintIris]
    static let wingTint = tintPearl

    /// Clean soft white: flesh (the lit tone) stays under 0.95 so the key light's highlights and the crinkle never clip flat; fleshDeep is a cool light grey
    /// so the shaded side, the squish creases and the belly read.
    static let palette: Palette = {
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        return JellyPalettes.matte(Palette(name: "Whitewing", flesh: [0.925, 0.920, 0.935], fleshDeep: [0.655, 0.670, 0.745],
                                           pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                                           shadowTint: [0.760, 0.770, 0.820], uiFlesh: [0.900, 0.900, 0.930]))
    }()
    /// sRGB 0...1 swatch (selection cards).
    static let swatch = SIMD3<Float>(0.96, 0.95, 0.97)

    /// The character a launch argument turns into this look; nil = none (the normal game).
    nonisolated(unsafe) static var forcedCharacter: Int? = parse(UserDefaults.standard.string(forKey: forceKey))
    static func parse(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let parts = raw.lowercased().split(separator: ":").map(String.init)
        guard parts.first == name else { return nil }
        if parts.count > 1, let c = Int(parts[1]), (0..<JellyRoster.characterCount).contains(c) { return c }
        return 0
    }
    static func isForced(_ character: Int) -> Bool { forcedCharacter == character }
    /// The white look (palette, swatch, pearl wing tint) applies to the real character Pearl (id 5) and to any character `-ForceSpecies whitewing` forces.
    static func hasLook(_ character: Int) -> Bool { character == JellyRoster.pearlID || isForced(character) }
}
