//
//  JellyTraits.swift
//  "Pick one of three": the three Jelbies of a species the Adoption Center shows side by side. They differ by a personality word, the five trait jars,
//  a favourite snack and (ordinary species, Jelly Spring only) a slight colour shade. Everything here is a pure function of
//  (species, dayKey, classic, owned), so leaving the page and coming back the same day shows the same three.
//
//  The adopted one keeps a JellyTraits record per INSTANCE id ("JellyTraits.v1"). Its jars seed the Jelbie's starting condition stats the first time his
//  JellyStats is built (StatTuning.seed(jars:)), and half of that seed is an innate floor the condition never decays below.
//

import Foundation

nonisolated enum Personality: String, CaseIterable, Codable, Sendable {
    case bouncy, cuddly, curious, sleepy, giggly, brave, gentle, cheeky

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// One kid line (at most 34 characters).
    var blurb: String {
        switch self {
        case .bouncy: return "Always up for a hop."
        case .cuddly: return "Loves a big squishy hug."
        case .curious: return "Pokes at everything."
        case .sleepy: return "Never far from a nap."
        case .giggly: return "Giggles at nothing at all."
        case .brave: return "Not scared of anything."
        case .gentle: return "Soft, calm and kind."
        case .cheeky: return "A little rascal."
        }
    }
    /// SF Symbol for the chip.
    var symbol: String {
        switch self {
        case .bouncy: return "bolt.fill"
        case .cuddly: return "heart.fill"
        case .curious: return "magnifyingglass"
        case .sleepy: return "moon.zzz.fill"
        case .giggly: return "face.smiling.fill"
        case .brave: return "shield.fill"
        case .gentle: return "leaf.fill"
        case .cheeky: return "sparkles"
        }
    }
    /// Jar tilt in the order Cute, Sweet, Sparkly, Cool, Sporty (SpeciesInfo.jarNames).
    var tilt: [Int] {
        switch self {
        case .bouncy: return [0, -4, 0, -8, 14]
        case .cuddly: return [10, 8, 0, -8, -8]
        case .curious: return [0, -4, 10, 6, -8]
        case .sleepy: return [2, 12, -4, 2, -14]
        case .giggly: return [8, 2, 10, -10, 0]
        case .brave: return [-8, -8, -2, 12, 12]
        case .gentle: return [4, 12, 2, -2, -14]
        case .cheeky: return [-4, -10, 8, 10, 4]
        }
    }
    /// Three store-food ids this personality likes.
    var snacks: [String] {
        switch self {
        case .bouncy: return ["donut", "fries", "taco"]
        case .cuddly: return ["cookie", "cupcake", "macncheese"]
        case .curious: return ["dumplings", "sushi", "sandwich"]
        case .sleepy: return ["cookie", "popsicle", "onigiri"]
        case .giggly: return ["cupcake", "pancakestack", "minipizza"]
        case .brave: return ["cheeseburger", "taco", "ramen"]
        case .gentle: return ["onigiri", "fruitcup", "popsicle"]
        case .cheeky: return ["nuggets", "fries", "cakeslice"]
        }
    }
}

nonisolated struct JellyTraits: Codable, Equatable, Sendable {
    var personality: Personality
    /// Five jars 15...98 in the order Cute, Sweet, Sparkly, Cool, Sporty.
    var jars: [Int]
    /// A store food id.
    var snack: String
}

nonisolated struct JellyCandidate: Equatable, Sendable {
    /// Left-to-right position on the pick page (0...2).
    let index: Int
    let species: Int
    let traits: JellyTraits
    /// The slight shade (or today's colour); nil = the classic colour.
    let variant: JellyVariant?
    /// The scratch id its stage actor wears (JellyRoster.previewID(species:slot:)).
    let previewID: Int
}

nonisolated enum JellyTraitsTuning {
    static let seed: UInt64 = 0x4A_E1_B1_E5
    static let jarRange = 15...98
}

/// Where the three candidates stand on the stage. Candidates are shown left to right as 0, 1, 2; the middle stage slot (0) is the front one, slot 1 stands left, slot 2 right.
nonisolated enum PickerRow {
    /// candidate index -> stage slot
    static let slotOfCandidate = [1, 0, 2]
    static func slot(ofCandidate i: Int) -> Int { slotOfCandidate[min(max(i, 0), 2)] }
    static func candidate(ofSlot s: Int) -> Int { slotOfCandidate.firstIndex(of: s) ?? 0 }
}

nonisolated enum JellyCandidates {
    /// `classic` = the free first gift and the special species: no colour shades. `owned` = how many Jelbies of this species are already home.
    static func make(species: Int, dayKey: Int, classic: Bool, owned: Int) -> [JellyCandidate] {
        var r = ParkRandom(JellyTraitsTuning.seed &+ UInt64(bitPattern: Int64(dayKey)) &* 0x9E37_79B9 &+ UInt64(max(species, 0)) &* 0x1F3D
                           &+ UInt64(classic ? 0x51 : 0xA7) &* 0xC2B2 &+ UInt64(max(owned, 0)) &* 0x7B1)
        _ = r.next()
        var words = Personality.allCases
        for i in stride(from: words.count - 1, to: 0, by: -1) { words.swapAt(i, Int(r.next() % UInt64(i + 1))) }
        let base = Self.baseJars(species)
        let shades: [JellyVariant?] = classic ? [nil, nil, nil] : JellyVariantBook.shades(species: species, dayKey: dayKey, owned: owned)
        var used: [String] = []
        var out: [JellyCandidate] = []
        for i in 0..<3 {
            let p = words[i]
            let jars = (0..<5).map { k in min(max(base[k] + p.tilt[k] + Int(r.next() % 7) - 3, JellyTraitsTuning.jarRange.lowerBound), JellyTraitsTuning.jarRange.upperBound) }
            var pool = p.snacks
            if let loved = lovedSnack(species) { pool.append(loved) }
            var k = Int(r.next() % UInt64(pool.count))
            var guardCount = 0
            while used.contains(pool[k]) && guardCount < pool.count { k = (k + 1) % pool.count; guardCount += 1 }
            used.append(pool[k])
            out.append(JellyCandidate(index: i, species: species, traits: JellyTraits(personality: p, jars: jars, snack: pool[k]),
                                      variant: shades[i], previewID: JellyRoster.previewID(species: species, slot: PickerRow.slot(ofCandidate: i))))
        }
        return out
    }

    /// The species' own jar profile (SpeciesInfo.traits, kept here so this file stays free of the UI types).
    static func baseJars(_ species: Int) -> [Int] {
        switch species {
        case 0: return [50, 45, 30, 85, 55]
        case 1: return [58, 60, 46, 28, 85]
        case 3: return [70, 55, 84, 40, 45]
        case 2: return [62, 82, 40, 50, 30]
        case JellyRoster.teddyID: return [88, 75, 40, 35, 40]
        case JellyRoster.pearlID: return [65, 60, 90, 45, 35]
        case JellyRoster.pandaID: return [70, 80, 35, 40, 55]
        default: return [50, 50, 50, 50, 50]
        }
    }
    /// The species' "Loves" food as a store food id.
    static func lovedSnack(_ species: Int) -> String? {
        switch species {
        case 0: return "sushi"
        case 1, JellyRoster.pandaID: return "donut"
        case 3, JellyRoster.teddyID: return "cookie"
        case 2, JellyRoster.pearlID: return "onigiri"
        default: return nil
        }
    }
}

/// The adopted Jelbies' traits, saved per INSTANCE id. No record = an old / default Jelbie, who behaves exactly as before.
nonisolated enum JellyTraitsBook {
    static let key = "JellyTraits.v1"
    nonisolated(unsafe) private(set) static var saved: [Int: JellyTraits] = load()

    static func load(_ d: UserDefaults = .standard) -> [Int: JellyTraits] {
        guard let raw = SaveRecovery.decode([String: JellyTraits].self, key: key, defaults: d) else { return [:] }
        var out: [Int: JellyTraits] = [:]
        for (k, v) in raw where v.jars.count == 5 { if let i = Int(k), i >= 0, !JellyRoster.isPreview(i) { out[i] = v } }
        return out
    }
    /// Re-reads the save (after a wipe, or in tests).
    static func reload(_ d: UserDefaults = .standard) { saved = load(d) }
    static func record(_ id: Int) -> JellyTraits? { saved[id] }
    /// Adopting Jelbie `id` with `t` (nil clears any old record). Saved to `d`. A preview scratch id is never recorded.
    static func adopt(_ id: Int, _ t: JellyTraits?, _ d: UserDefaults = .standard) {
        guard !JellyRoster.isPreview(id) else { return }
        saved[id] = t
        var raw: [String: JellyTraits] = [:]
        for (k, v) in saved { raw[String(k)] = v }
        if let data = try? JSONEncoder().encode(raw) { d.set(data, forKey: key) }
    }
}
