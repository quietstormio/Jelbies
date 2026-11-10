//
//  JellyVariants.swift
//  Jelly Spring colour variants. The SPECIES stay fixed (blue none, yellow tail + spikes, green daisy, purple wings: JellyRoster.feature is by
//  character id, never by colour); only the rare mutation days change the body colour of a species on offer.
//
//  - The Spring shows every species in its own classic colour. On about 4% of species-days (seeded daily, the same on every device that day) it offers
//    its one rare jewel tone instead (below); there is no other daily colour.
//  - Rare mutations (`VariantTuning.rareRate`, ~4% of species-days) are ONE jewel tone per species in its own colour family (Sapphire, Amber, Emerald, Amethyst). Exclusives never
//    appear in the Park (`ParkPool.generate` filters them; none is a `ParkColour`), and the Spring card shows a "Rare" tag.
//  - An adopted variant is saved per CHARACTER id ("JellyVariants.v1"); `JellyRoster.palette/tint` read it, so the roster, profile, widget and
//    selection all follow. A character with no saved variant (Bob, Pearl, Teddy, Panda, every old save) is untouched. Only ids 0...3 take variants.
//

import Foundation
import simd

nonisolated enum VariantTuning {
    /// Chance that a species-day offers a rare mutation (one constant).
    static let rareRate: Double = 0.04
    static let seed: UInt64 = 0x57_12_91_AB_E3
}

nonisolated struct JellyVariant: Codable, Equatable, Sendable {
    var title: String
    var flesh: [Float]
    var deep: [Float]
    var rare: Bool

    var fleshV: SIMD3<Float> { SIMD3(flesh[0], flesh[1], flesh[2]) }
    var deepV: SIMD3<Float> { SIMD3(deep[0], deep[1], deep[2]) }
    var swatch: SIMD3<Float> { fleshV }
    var palette: Palette {
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        return JellyPalettes.matte(Palette(name: title, flesh: fleshV, fleshDeep: deepV, pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                                           shadowTint: deepV * 0.5 + fleshV * 0.5, uiFlesh: fleshV * 0.93))
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title); flesh = try c.decode([Float].self, forKey: .flesh); deep = try c.decode([Float].self, forKey: .deep)
        rare = c.value(.rare, false)
    }
    init(title: String, flesh: SIMD3<Float>, deep: SIMD3<Float>, rare: Bool) {
        self.title = title; self.flesh = [flesh.x, flesh.y, flesh.z]; self.deep = [deep.x, deep.y, deep.z]; self.rare = rare
    }
    /// Whether this colour is one of the Park-excluded exclusives.
    var isExclusive: Bool { JellyVariantBook.isExclusiveTitle(title) }
}

nonisolated enum JellyVariantBook {
    /// The rare jewel tones, index = species (0 Bob blue, 1 Pip yellow, 2 Moss green, 3 Lavender purple): each species keeps to its own colour family.
    /// They never show in the Park (no title is a `ParkColour` raw value).
    static let exclusives: [JellyVariant] = [
        JellyVariant(title: "Sapphire", flesh: [0.240, 0.430, 0.860], deep: [0.090, 0.200, 0.600], rare: true),
        JellyVariant(title: "Amber", flesh: [0.900, 0.560, 0.140], deep: [0.640, 0.320, 0.030], rare: true),
        JellyVariant(title: "Emerald", flesh: [0.160, 0.640, 0.420], deep: [0.040, 0.400, 0.250], rare: true),
        JellyVariant(title: "Amethyst", flesh: [0.500, 0.300, 0.800], deep: [0.280, 0.130, 0.540], rare: true),
    ]
    /// The five off-palette exclusives of the first release line. No longer offered, but a Jelbie that already wears one (saved by value) keeps its colour and still counts as exclusive.
    static let legacyExclusiveTitles: [String] = ["Sunbeam gold", "Midnight", "Moonstone", "Rose quartz", "Aurora"]
    static func isExclusiveTitle(_ t: String) -> Bool { exclusives.contains { $0.title == t } || legacyExclusiveTitles.contains(t) }

    /// The spike colour (linear) for a Pip wearing this variant: only the Amber rare, whose body is the same orange as the spike art (a deep, brown russet so they read in daylight as well as at night);
    /// nil for every other colour (classic Pip and all others keep the art as drawn). Derived from the title, nothing saved.
    static let amberSpikeTint = SIMD3<Float>(0.52, 0.16, 0.03)
    static func spikeTint(for v: JellyVariant?) -> SIMD3<Float>? { v?.title == "Amber" ? amberSpikeTint : nil }

    /// Park colours a visitor may have: everything except an exclusive (today none collides, so the pool is unchanged).
    static func parkEligible(_ c: ParkColour) -> Bool { !(exclusives.map(\.title) + legacyExclusiveTitles).contains { $0.lowercased() == c.rawValue } }

    /// Days since the epoch in the local calendar (what the daily seed is keyed by).
    static func dayKey(_ date: Date = Date(), calendar: Calendar = .current) -> Int { calendar.ordinality(of: .day, in: .era, for: date) ?? 0 }

    /// The Spring's offer for `species` on `dayKey`: nil = the species' own classic colour (almost always); about 4% of days that species' own rare jewel tone (`exclusives[species]`). Deterministic. `-RareDay 1` (dev builds only) makes every day rare.
    static func offer(species: Int, dayKey: Int) -> JellyVariant? {
        guard (0...3).contains(species) else { return nil }
        var r = ParkRandom(VariantTuning.seed &+ UInt64(bitPattern: Int64(dayKey)) &* 0x9E37_79B9 &+ UInt64(species) &* 0x1F3D)
        _ = r.next()
        #if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
        if DevArgs.enabled, UserDefaults.standard.integer(forKey: "RareDay") == 1 { return exclusives[species] }          // capture aid: every day is a rare day
        #endif
        if Double(r.unit()) < VariantTuning.rareRate { return exclusives[species] }
        return nil
    }

    /// `v` moved `t` of the way toward white (t > 0) or black (t < 0).
    private static func tone(_ v: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let target: Float = t >= 0 ? 1 : 0
        return simd_clamp(v + (SIMD3<Float>(repeating: target) - v) * abs(t), SIMD3(repeating: 0.02), SIMD3(repeating: 0.99))
    }

    /// How far the pick page's "Soft" / "Deep" shades move the classic colour toward white / black.
    static let softShade: Float = 0.13, deepShade: Float = 0.14

    /// The classic colour of a starter species (the same sources as `JellyRoster.palette`, bypassing variants).
    static func classicPalette(_ species: Int) -> Palette {
        switch species {
        case 1: return PaletteKey.yellow.palette
        case 2: return JellyPalettes.green
        case 3: return JellyPalettes.lavender
        default: return PaletteKey.blue.palette
        }
    }

    /// Three slots for the pick page, left to right: the classic colour, a slight tone of it (Soft or Deep) and a third slot that is the rare mutation only on a rare day
    /// (`offer`); otherwise the three are classic / Soft / Deep, all the species' own colour, so no two slots match. Species 0...3 only; anything else is [nil, nil, nil].
    static func shades(species: Int, dayKey: Int, owned: Int) -> [JellyVariant?] {
        guard (0...3).contains(species) else { return [nil, nil, nil] }
        var r = ParkRandom(VariantTuning.seed ^ 0x5AD3 &+ UInt64(bitPattern: Int64(dayKey)) &* 0x9E37_79B9 &+ UInt64(species) &* 0x1F3D &+ UInt64(max(owned, 0)) &* 0x7B1)
        _ = r.next()
        let p = classicPalette(species)
        func shade(_ soft: Bool) -> JellyVariant {
            let t = soft ? softShade : -deepShade
            return JellyVariant(title: soft ? "Soft" : "Deep", flesh: tone(p.flesh, t), deep: tone(p.fleshDeep, t), rare: false)
        }
        let first = r.next() % 2 == 0
        if let d = offer(species: species, dayKey: dayKey) { return [nil, shade(first), d] }
        return [nil, shade(true), shade(false)]
    }
}

/// The adopted variants (saved per character id) plus the picker's in-memory previews.
nonisolated enum JellyVariants {
    static let key = "JellyVariants.v1"
    nonisolated(unsafe) private static var saved: [Int: JellyVariant] = load()
    nonisolated(unsafe) private static var previews: [Int: JellyVariant] = [:]
    nonisolated(unsafe) private static var classicPreviews: Set<Int> = []

    /// Only the four starter species take a colour variant; the key is the INSTANCE id (a second Bob has his own colour).
    static func takesVariant(_ id: Int) -> Bool { JellyRoster.isValid(id) && JellyRoster.species(id) <= 3 }

    static func load(_ d: UserDefaults = .standard) -> [Int: JellyVariant] {
        guard let raw = SaveRecovery.decode([String: JellyVariant].self, key: key, defaults: d) else { return [:] }
        var out: [Int: JellyVariant] = [:]
        for (k, v) in raw { if let i = Int(k), takesVariant(i), v.flesh.count == 3, v.deep.count == 3 { out[i] = v } }
        return out
    }
    /// Re-reads the save (after a wipe, or in tests).
    static func reload(_ d: UserDefaults = .standard) { saved = load(d) }

    /// The variant a character wears now (preview first, then the save); nil = his own classic colour.
    static func active(_ id: Int) -> JellyVariant? {
        guard takesVariant(id) else { return nil }
        if classicPreviews.contains(id) { return nil }
        return previews[id] ?? saved[id]
    }
    /// The saved (adopted) variant only.
    static func adopted(_ id: Int) -> JellyVariant? { saved[id] }

    /// Adopting character `id` with `variant` (nil = classic clears any old one). Saved to `d`.
    static func adopt(_ id: Int, _ variant: JellyVariant?, _ d: UserDefaults = .standard) {
        guard takesVariant(id) else { return }
        saved[id] = variant
        var raw: [String: JellyVariant] = [:]
        for (k, v) in saved { raw[String(k)] = v }
        if let data = try? JSONEncoder().encode(raw) { d.set(data, forKey: key) }
        clearPreviews()
    }
    static func setPreview(_ id: Int, _ variant: JellyVariant?) {
        if let v = variant { previews[id] = v; classicPreviews.remove(id) } else { previews[id] = nil; classicPreviews.insert(id) }
    }
    static func clearPreviews() { previews = [:]; classicPreviews = [] }
}
