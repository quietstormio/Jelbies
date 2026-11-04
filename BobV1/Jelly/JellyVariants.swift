//
//  JellyVariants.swift
//  Jelly Spring colour variants. The SPECIES stay fixed (blue none, yellow tail + spikes, green daisy, purple wings: JellyRoster.feature is by
//  character id, never by colour); only the body colour of a species on offer changes from day to day.
//
//  - The Spring shows ONE seeded-daily colour variant per species (same on every device that day). It is built from the Park visitor palette table
//    (`ParkColour.flesh` -> `JellyPalettes` matte treatment) with a small seeded tone jitter, or it is the species' classic colour.
//  - Rare mutations (`VariantTuning.rareRate`, ~4% of species-days) are one of a small fixed set of EXCLUSIVE off-palette colours. Exclusives never
//    appear in the Park (`ParkPool.generate` filters them; none is a `ParkColour`), and the Spring card shows a "Rare" tag.
//  - An adopted variant is saved per CHARACTER id ("JellyVariants.v1"); `JellyRoster.palette/tint` read it, so the roster, profile, widget and
//    selection all follow. A character with no saved variant (Bob, Pearl, Teddy, Panda, every old save) is untouched. Only ids 0...3 take variants.
//

import Foundation
import simd

nonisolated enum VariantTuning {
    /// Chance that a species-day offers a rare mutation (one constant).
    static let rareRate: Double = 0.04
    /// Chance that a normal day shows the species' classic colour.
    static let classicShare: Double = 0.30
    /// Seeded tone jitter (towards white / black) applied to a Park-table colour.
    static let toneJitter: Float = 0.05
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
    init(title: String, flesh: SIMD3<Float>, deep: SIMD3<Float>, rare: Bool) {
        self.title = title; self.flesh = [flesh.x, flesh.y, flesh.z]; self.deep = [deep.x, deep.y, deep.z]; self.rare = rare
    }
    /// Whether this colour is one of the Park-excluded exclusives.
    var isExclusive: Bool { JellyVariantBook.exclusives.contains { $0.title == title } }
}

nonisolated enum JellyVariantBook {
    /// The fixed exclusive set: off-palette colours that never show in the Park. The rare mutation draws from these.
    static let exclusives: [JellyVariant] = [
        JellyVariant(title: "Sunbeam gold", flesh: [1.000, 0.835, 0.330], deep: [0.900, 0.620, 0.090], rare: true),
        JellyVariant(title: "Midnight", flesh: [0.300, 0.340, 0.620], deep: [0.140, 0.160, 0.400], rare: true),
        JellyVariant(title: "Moonstone", flesh: [0.880, 0.930, 1.000], deep: [0.620, 0.700, 0.900], rare: true),
        JellyVariant(title: "Rose quartz", flesh: [1.000, 0.740, 0.860], deep: [0.860, 0.440, 0.640], rare: true),
        JellyVariant(title: "Aurora", flesh: [0.560, 0.960, 0.800], deep: [0.250, 0.700, 0.760], rare: true),
    ]

    /// Park colours a visitor may have: everything except an exclusive (today none collides, so the pool is unchanged).
    static func parkEligible(_ c: ParkColour) -> Bool { !exclusives.contains { $0.title.lowercased() == c.rawValue } }

    /// Tasteful Park-table colours per species (character 0 blue, 1 yellow, 2 green, 3 purple).
    static func colours(for species: Int) -> [ParkColour] {
        switch species {
        case 0: return [.teal, .grey, .cream, .mint]
        case 1: return [.orange, .peach, .cream, .lime]
        case 2: return [.mint, .lime, .teal, .cream]
        default: return [.plum, .pink, .coral, .grey]
        }
    }

    /// Days since the epoch in the local calendar (what the daily seed is keyed by).
    static func dayKey(_ date: Date = Date(), calendar: Calendar = .current) -> Int { calendar.ordinality(of: .day, in: .era, for: date) ?? 0 }

    /// The Spring's offer for `species` on `dayKey`: nil = the classic colour. Deterministic.
    static func offer(species: Int, dayKey: Int) -> JellyVariant? {
        guard (0...3).contains(species) else { return nil }
        var r = ParkRandom(VariantTuning.seed &+ UInt64(bitPattern: Int64(dayKey)) &* 0x9E37_79B9 &+ UInt64(species) &* 0x1F3D)
        _ = r.next()
        if Double(r.unit()) < VariantTuning.rareRate { return r.pick(exclusives) }
        if Double(r.unit()) < VariantTuning.classicShare { return nil }
        let c = r.pick(colours(for: species))
        let t = (r.unit() * 2 - 1) * VariantTuning.toneJitter
        func tone(_ v: SIMD3<Float>) -> SIMD3<Float> {
            let target: Float = t >= 0 ? 1 : 0
            return simd_clamp(v + (SIMD3<Float>(repeating: target) - v) * abs(t), SIMD3(repeating: 0.02), SIMD3(repeating: 0.99))
        }
        let (f, d) = c.flesh
        return JellyVariant(title: c.title, flesh: tone(f), deep: tone(d), rare: false)
    }
}

/// The adopted variants (saved per character id) plus the picker's in-memory previews.
nonisolated enum JellyVariants {
    static let key = "JellyVariants.v1"
    nonisolated(unsafe) private static var saved: [Int: JellyVariant] = load()
    nonisolated(unsafe) private static var previews: [Int: JellyVariant] = [:]
    nonisolated(unsafe) private static var classicPreviews: Set<Int> = []

    static func load(_ d: UserDefaults = .standard) -> [Int: JellyVariant] {
        guard let data = d.data(forKey: key), let raw = try? JSONDecoder().decode([String: JellyVariant].self, from: data) else { return [:] }
        var out: [Int: JellyVariant] = [:]
        for (k, v) in raw { if let i = Int(k), (0...3).contains(i), v.flesh.count == 3, v.deep.count == 3 { out[i] = v } }
        return out
    }
    /// Re-reads the save (after a wipe, or in tests).
    static func reload(_ d: UserDefaults = .standard) { saved = load(d) }

    /// The variant a character wears now (preview first, then the save); nil = his own classic colour.
    static func active(_ id: Int) -> JellyVariant? {
        guard (0...3).contains(id) else { return nil }
        if classicPreviews.contains(id) { return nil }
        return previews[id] ?? saved[id]
    }
    /// The saved (adopted) variant only.
    static func adopted(_ id: Int) -> JellyVariant? { saved[id] }

    /// Adopting character `id` with `variant` (nil = classic clears any old one). Saved to `d`.
    static func adopt(_ id: Int, _ variant: JellyVariant?, _ d: UserDefaults = .standard) {
        guard (0...3).contains(id) else { return }
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
