//
//  JellyRoster.swift
//  The Jelbies of the room (1...3): who they are, what colour, where they spawn, and the UserDefaults keys of their saved state.
//
//  CHARACTERS (fixed ids, 4 available): 0 Bob (baby blue), 1 Pip (yellow, spines), 2 Moss (green, daisy), 3 Lavender (pastel lavender, wings).
//  Every body is Bob's; a character differs only by colour and FEATURE (JellyFeature; Features/). Saved state is keyed by CHARACTER id (JellyKeys):
//  character 0's keys ARE the pre-multi-Jelly keys ("BlobNeeds.v1", "BlobGrime.v1", "BlobWords.v1"), so the phone's existing Bob state became
//  his data with no copy; the others get suffixed keys (".jelly1" ...). DropsWallet and the voice tutorial flag stay shared on purpose.
//
//  ROSTER (who is in the room, at most `maxCount` = 3): an ordered list of character ids saved under "BlobRoster.v1" (default Bob, Pip, Moss).
//  Everything that runs the room (GameCare.jellies, the stage's actors, the renderer's bodies, selection, bubbles, intents, the widget) is
//  indexed by SLOT = position in that list (0...2); slot 0 is the "primary" that the legacy Bob-only paths drive. `character(slot)` maps a
//  slot to its character for colour / feature / name / saved keys. With the default roster slot == character, so nothing moved.
//
//  Launch flags: -BlobCount 1|2|3 (how many of the roster, default all); -SetRoster pip,moss,lavender (REPLACES the saved roster with exactly
//  those, in that order; safe to leave in: applying it again is a no-op). Adoption (Bob only to start, Drops to adopt) is planned, not built: docs/Species.md.
//

import Foundation
import simd

enum JellyKeys {
    static func needs(_ id: Int) -> String { suffixed(NeedsTuning.defaultsKey, id) }
    static func grime(_ id: Int) -> String { suffixed(GrimeTuning.defaultsKey, id) }
    static func words(_ id: Int) -> String { suffixed(VoiceTuning.defaultsKey, id) }
    static func stats(_ id: Int) -> String { suffixed(StatTuning.defaultsKey, id) }
    static func perks(_ id: Int) -> String { suffixed(PerkTuning.defaultsKey, id) }
    private static func suffixed(_ legacy: String, _ id: Int) -> String { id == 0 ? legacy : "\(legacy).jelly\(id)" }
}

/// What grows on a Jelly besides Bob's body (BobV1/Features): mapped from his colour. Saved nowhere: it follows the character id.
nonisolated enum JellyFeature: String, Codable, CaseIterable, Sendable {
    case none, spines, daisy, wings
    /// The feature art of the bundle (feature_<id>.bin); "" for none.
    var art: String {
        switch self { case .none: return ""; case .spines: return "pip_c_final"; case .daisy: return "moss_a_final"; case .wings: return "lav_a_final" }
    }
}

nonisolated enum JellyRoster {
    /// Jelbies in the room at once (the roster cap).
    static let maxCount = 3
    /// Characters available (Bob, Pip, Moss, Lavender).
    static let characterCount = 4
    /// The species' own names (what the Adoption Center offers as the default).
    static let baseNames = ["Bob", "Pip", "Moss", "Lavender"]
    static let namesKey = "JellyNames.v1"
    /// Names by CHARACTER: the base name, or the one the player typed when adopting (saved under `namesKey`; Start/StartFlow.swift).
    nonisolated(unsafe) static var names: [String] = loadNames()
    static func loadNames(_ d: UserDefaults = .standard) -> [String] {
        let saved = d.stringArray(forKey: namesKey) ?? []
        return baseNames.enumerated().map { i, b in
            guard saved.indices.contains(i) else { return b }
            let t = saved[i].trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? b : t
        }
    }
    /// Gives character `id` a name (empty = back to the base name) and saves it.
    static func setName(_ id: Int, _ raw: String, _ d: UserDefaults = .standard) {
        guard (0..<characterCount).contains(id) else { return }
        var saved = d.stringArray(forKey: namesKey) ?? []
        while saved.count < characterCount { saved.append("") }
        saved[id] = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(14))
        d.set(saved, forKey: namesKey)
        names = loadNames(d)
    }
    /// A fresh install: Bob, Pip and Moss (the roster before the characters round; Lavender stays available).
    static let defaultIDs = [0, 1, 2]
    static let rosterKey = "BlobRoster.v1"
    static let setRosterKey = "SetRoster"

    /// Colour -> feature: blue none, yellow spines, green daisy, lavender wings. (By CHARACTER id.)
    static func feature(_ id: Int) -> JellyFeature {
        switch id { case 1: return .spines; case 2: return .daisy; case 3: return .wings; default: return .none }
    }

    // MARK: the roster (characters by slot)

    /// Character name or id, case-insensitive ("pip", "Lavender", "2"); nil when unknown.
    static func characterID(named raw: String) -> Int? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let i = baseNames.firstIndex(where: { $0.lowercased() == t }) ?? names.firstIndex(where: { $0.lowercased() == t }) { return i }
        if let n = Int(t), (0..<characterCount).contains(n) { return n }
        return nil
    }
    /// `-SetRoster pip,moss,lavender` -> [1, 2, 3]: unknown names dropped, repeats dropped, capped at `maxCount`; nil when nothing usable is left.
    static func parseRoster(_ text: String) -> [Int]? {
        var out: [Int] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }) {
            if let c = characterID(named: String(part)), !out.contains(c) { out.append(c) }
        }
        guard !out.isEmpty else { return nil }
        return Array(out.prefix(maxCount))
    }
    /// A saved / given list made valid: known characters, no repeats, 1...maxCount (empty -> the default roster).
    static func sanitised(_ ids: [Int]) -> [Int] {
        var out: [Int] = []
        for c in ids where (0..<characterCount).contains(c) && !out.contains(c) { out.append(c) }
        return out.isEmpty ? defaultIDs : Array(out.prefix(maxCount))
    }
    /// The roster saved in `d` (the default roster when none was saved).
    static func savedIDs(_ d: UserDefaults = .standard) -> [Int] {
        guard let a = d.array(forKey: rosterKey) as? [Int] else { return defaultIDs }
        return sanitised(a)
    }
    /// Saves `ids` (sanitised) as the roster.
    static func save(_ ids: [Int], to d: UserDefaults = .standard) { d.set(sanitised(ids), forKey: rosterKey) }

    /// Applies `-SetRoster a,b,c` when the launch argument is present: the saved roster becomes exactly that list. Returns the roster now in force.
    /// Each character keeps whatever is saved under his own keys (nothing is copied or cleared); a character with no saved data starts fresh
    /// the first time his profile loads. Idempotent: the same argument again writes the same list; no argument leaves the saved roster alone.
    @discardableResult
    static func applySetRoster(_ d: UserDefaults = .standard) -> [Int] {
        if let text = d.string(forKey: setRosterKey), let ids = parseRoster(text) {
            if savedIDs(d) != ids { save(ids, to: d) }
            return ids
        }
        return savedIDs(d)
    }
    /// The characters in the room at launch, by slot: `-SetRoster` applied, then the saved roster, cut to `-BlobCount` when given.
    static func launchIDs(_ d: UserDefaults = .standard) -> [Int] {
        let ids = applySetRoster(d)
        guard d.object(forKey: "BlobCount") != nil else { return ids }
        return Array(ids.prefix(min(max(d.integer(forKey: "BlobCount"), 1), ids.count)))
    }
    /// How many Jelbies the room starts with (`launchIDs().count`).
    static func launchCount(_ d: UserDefaults = .standard) -> Int { launchIDs(d).count }

    /// The roster of this process (slot -> character), fixed at launch from `launchIDs()`. Tests may set it and must put it back.
    @MainActor static var current: [Int] = launchIDs()
    /// The character in `slot` (a slot past the roster falls back to the same-numbered character, as before the roster existed).
    @MainActor static func character(_ slot: Int) -> Int {
        current.indices.contains(slot) ? current[slot] : min(max(slot, 0), characterCount - 1)
    }
    /// The slot a character is in; nil when he is not in the room.
    @MainActor static func slot(ofCharacter c: Int) -> Int? { current.firstIndex(of: c) }
    @MainActor static func name(slot: Int) -> String { names[character(slot)] }
    @MainActor static func feature(slot: Int) -> JellyFeature { feature(character(slot)) }
    @MainActor static func palette(slot: Int) -> Palette? { palette(character(slot)) }
    @MainActor static func tint(slot: Int) -> SIMD3<Float> { tint(character(slot)) }

    /// Floor spots (x, z) the Jellies start on, spread over the visible floor so nobody overlaps (the floor is only ~2.2 wide at the body's height on a
    /// portrait phone, so they zig-zag in depth). One Jelly stays at the origin like before.
    static func spawnSpots(count: Int) -> [SIMD2<Float>] {
        switch count {
        case 1: return [SIMD2(0, 0)]
        case 2: return [SIMD2(0.1, 1.5), SIMD2(-0.2, -1.4)]
        case 3: return [SIMD2(-0.15, 1.6), SIMD2(-0.85, -1.7), SIMD2(0.85, -0.1)]
        default: return [SIMD2(-0.15, 1.6), SIMD2(-1.1, -1.7), SIMD2(1.2, -0.3), SIMD2(1.15, 1.7)]       // 4: test rooms only (the roster cap is 3)
        }
    }

    /// Body colours by CHARACTER: Bob is the model's palette (baby blue in the game; nil); Pip is the existing yellow; Moss a green and Lavender a pastel lavender made the same way.
    static func palette(_ id: Int) -> Palette? {
        switch id {
        case 1: return PaletteKey.yellow.palette
        case 2: return JellyPalettes.green
        case 3: return JellyPalettes.lavender
        default: return nil
        }
    }

    /// sRGB 0...1 swatch for the roster card / selection preview (by CHARACTER).
    static func tint(_ id: Int) -> SIMD3<Float> {
        switch id {
        case 1: return SIMD3(0.99, 0.90, 0.62)
        case 2: return SIMD3(0.70, 0.90, 0.66)
        case 3: return SIMD3(0.80, 0.72, 0.93)
        default: return SIMD3(0.70, 0.83, 0.945)
        }
    }

    /// Selection cards for a roster (slot ids, character names and tints).
    static func selectBlobs(roster: [Int]) -> [SelectBlob] {
        sanitised(roster).enumerated().map { SelectBlob(id: $0.offset, name: names[$0.element], tint: tint($0.element)) }
    }
    /// The first `count` of the default roster.
    static func selectBlobs(count: Int) -> [SelectBlob] { selectBlobs(roster: Array(defaultIDs.prefix(min(max(count, 1), maxCount)))) }
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

    /// Lavender: the approved pastel lavender (#CDB8EC), the same treatment as Moss's green.
    static let lavender: Palette = {
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        return matte(Palette(name: "Lavender", flesh: [0.760, 0.665, 0.930], fleshDeep: [0.520, 0.410, 0.780],
                             pale: unused, skin: unused, stripe: unused, seed: PaletteKey.blue.palette.seed,
                             shadowTint: [0.640, 0.560, 0.800], uiFlesh: [0.780, 0.700, 0.920]))
    }()
}
