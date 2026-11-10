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

/// Gate for every developer launch argument (`-UpgradePoints`, `-SleepNow`, `-ClockHour`, `-SetRoster`, `-ForceSpecies`, `-BlobCount`, ...).
/// True in Debug, on the simulator, and in Release builds made with the JELBIES_DEV_ARGS compilation condition (the project's Release
/// configuration sets it through the JELBIES_DEV_ARGS_COND build setting so local device installs keep diagnostics). The App Store archive
/// must clear it: `JELBIES_DEV_ARGS_COND=` on the archive command (see docs/RELEASE-1.0.md).
/// `-AudioLog` (AudioHub) is intentionally NOT gated: it is a silent, read-only diagnostic that grants nothing.
/// Capture-aid blocks in GameScreen (runDebugScript, runStoreDemo, launchTown) are gated at their entry; Park/Volley/Groom Start* hooks are simulator-only.
nonisolated enum DevArgs {
    static var enabled: Bool {
        #if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

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
    /// Teddy: round bear ears + a small puffy pom tail (built in code, Features/TeddyFeature.swift; there is no .bin).
    case ears
    /// The feature art of the bundle (feature_<id>.bin); "" for none (and for the ears: they are built in code).
    var art: String {
        switch self { case .none, .ears: return ""; case .spines: return "pip_c_final"; case .daisy: return "moss_a_final"; case .wings: return "lav_a_final" }
    }
}

nonisolated enum JellyRoster {
    /// Jelbies in the room at once (the roster cap).
    static let maxCount = 3
    /// The four starter characters (Bob, Pip, Moss, Lavender); Teddy, Pearl and Panda are the specials (`knownCount`).
    static let characterCount = 4
    /// The species' own names (what the Adoption Center offers as the default).
    static let baseNames = ["Bob", "Pip", "Moss", "Lavender", "Teddy", "Pearl", "Panda"]
    /// Teddy (character 4): a special species bought in the Jelly Spring with JellyCoins (AdoptionPrice.special); NOT in the intro, the free first gift or the
    /// starter roster, and never padded into a short roster or any default. Existing saves that hold him keep him; `-ForceSpecies teddy` / `-SetRoster teddy` still work.
    static let teddyID = 4
    /// Panda (character 6): Teddy's round bear ears + pom on a white body with black eye patches, ears, arms, feet, shoulder band and pom (PandaLook.swift).
    /// Like Teddy and Pearl it is a special species bought in the Jelly Spring (not in the intro, the starter roster or any generator).
    static let pandaID = 6
    /// Every character id that exists (the four on offer + Teddy, Pearl, Panda).
    static let knownCount = 7
    /// Pearl (character 5): the white winged Jelbie (WhiteWing.swift): Lavender's wings re-tinted pearl, a soft white body. Like Teddy it is a special species
    /// bought in the Jelly Spring (not in the intro, the starter roster or any generator); a roster also gets him by `-SetRoster` / `-NewGame` / a save.
    static let pearlID = 5
    static let namesKey = "JellyNames.v1"

    // MARK: instances (duplicates)
    //
    // An INSTANCE id names one Jelbie (the roster holds instance ids; every save key, name, stat and book is keyed by it). A SPECIES id (0...6) says what it
    // looks like and sounds like. The first Jelbie of a species has instance id == species id (so every v1 save is already valid); a second Bob (or Pip...)
    // gets a fresh id from the saved counter (>= firstInstanceID, never reused) whose species is recorded in `speciesKey` BEFORE the roster is saved.
    // Picker previews use scratch ids previewBase + species so a preview never touches an owned Jelbie's keys.
    static let firstInstanceID = 100
    static let previewBase = 1000
    static let speciesKey = "JellySpeciesOf.v1"
    static let nextInstanceKey = "JellyNextInstance.v1"
    static let extraNamesKey = "JellyNamesExtra.v1"
    /// instance id (>= firstInstanceID) -> species id. Loaded lazily from the save, so it is ready before `current = launchIDs()` runs (sanitised reads it).
    nonisolated(unsafe) static var speciesMap: [Int: Int] = loadSpeciesMap()
    /// Names of instances >= firstInstanceID (ids 0...6 keep using the v1 `names` array).
    nonisolated(unsafe) static var extraNames: [Int: String] = loadExtraNames()
    static func loadSpeciesMap(_ d: UserDefaults = .standard) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for (k, v) in (d.dictionary(forKey: speciesKey) ?? [:]) {
            if let i = Int(k), let sp = v as? Int, i >= firstInstanceID, i < previewBase, (0..<knownCount).contains(sp) { out[i] = sp }
        }
        return out
    }
    static func loadExtraNames(_ d: UserDefaults = .standard) -> [Int: String] {
        var out: [Int: String] = [:]
        for (k, v) in (d.dictionary(forKey: extraNamesKey) ?? [:]) {
            if let i = Int(k), i >= firstInstanceID, let n = v as? String { out[i] = n }
        }
        return out
    }
    /// Re-reads the species map and the extra names (after a wipe, or in tests).
    static func reloadSpecies(_ d: UserDefaults = .standard) { speciesMap = loadSpeciesMap(d); extraNames = loadExtraNames(d) }
    /// Preview slots: the pick-one-of-three page stands three Jelbies of one species side by side, so a species has `previewSlots` scratch ids.
    static let previewSlots = 3
    /// The scratch instance id the Adoption Center's preview stage uses for `species` (slot 0).
    static func previewID(_ species: Int) -> Int { previewID(species: species, slot: 0) }
    /// Scratch id of preview `slot` (0...2) of `species`: 1000 + slot * 10 + species. Slot 0 is the single-Jelbie page's id.
    static func previewID(species: Int, slot: Int) -> Int { previewBase + min(max(slot, 0), previewSlots - 1) * 10 + min(max(species, 0), knownCount - 1) }
    /// Whether `id` is a picker scratch id (never saved anywhere).
    static func isPreview(_ id: Int) -> Bool { id >= previewBase }
    /// The slot (0...2) a preview scratch id stands for.
    static func previewSlot(_ id: Int) -> Int { max(id - previewBase, 0) / 10 }
    /// The species (look, voice, feature) of instance `id`: identity below 100, the saved map from 100, a preview scratch id resolves to its species.
    static func species(_ id: Int) -> Int {
        if (0..<knownCount).contains(id) { return id }
        if id >= previewBase { return min((id - previewBase) % 10, knownCount - 1) }
        if let s = speciesMap[id] { return s }
        return min(max(id, 0), knownCount - 1)
    }
    /// Whether `id` is a Jelbie that can exist: a species-id instance, a recorded duplicate, or a picker preview scratch id.
    static func isValid(_ id: Int) -> Bool {
        if (0..<knownCount).contains(id) { return true }
        if id >= previewBase { return (id - previewBase) / 10 < previewSlots && (id - previewBase) % 10 < knownCount }
        return speciesMap[id] != nil
    }
    /// A new Jelbie of `species` joining `roster` (instance ids): the species id itself when nobody of that species is in the room, else a fresh instance id
    /// from the saved counter (never reused), recorded in the species map and saved to `d` right away (before the caller saves the roster).
    static func allocateInstance(species s: Int, roster: [Int], _ d: UserDefaults = .standard) -> Int {
        let sp = min(max(s, 0), knownCount - 1)
        if !roster.contains(where: { species($0) == sp }) { return sp }
        var id = max(d.integer(forKey: nextInstanceKey), firstInstanceID)
        while speciesMap[id] != nil || roster.contains(id) { id += 1 }
        d.set(id + 1, forKey: nextInstanceKey)
        speciesMap[id] = sp
        var raw: [String: Int] = [:]
        for (k, v) in speciesMap { raw[String(k)] = v }
        d.set(raw, forKey: speciesKey)
        return id
    }
    /// The name a new `species` gets given the names already at home: the base name, else "Teddy 2", "Teddy 3" ...
    static func suggestedName(species s: Int, taken: [String]) -> String {
        let base = baseNames[min(max(s, 0), knownCount - 1)]
        let used = Set(taken.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if !used.contains(base.lowercased()) { return base }
        var n = 2
        while used.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
    /// A name chosen by the player, made different from the names already at home (case-insensitive): "Rex" taken -> "Rex 2".
    static func uniqueName(_ raw: String, taken: [String]) -> String {
        let t = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
        let used = Set(taken.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if !used.contains(t.lowercased()) { return t }
        var n = 2
        while used.contains("\(t) \(n)".lowercased()) { n += 1 }
        return "\(t) \(n)"
    }
    /// The name of Jelbie `id` (instance id): the v1 names array below 7, the extra names from 100, a preview scratch id its species' base name.
    static func nameOf(_ id: Int) -> String {
        if names.indices.contains(id) { return names[id] }
        if let n = extraNames[id], !n.isEmpty { return n }
        return baseNames[species(id)]
    }

    /// Names by CHARACTER: the base name, or the one the player typed when adopting (saved under `namesKey`; Start/StartFlow.swift).
    /// Only ids 0...6: anything that may hold an instance id >= 100 goes through `nameOf`.
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
        if id >= firstInstanceID && id < previewBase {
            guard speciesMap[id] != nil else { return }
            let t = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(14))
            extraNames[id] = t.isEmpty ? nil : t
            var out: [String: String] = [:]
            for (k, v) in extraNames { out[String(k)] = v }
            d.set(out, forKey: extraNamesKey)
            return
        }
        guard (0..<knownCount).contains(id) else { return }
        var saved = d.stringArray(forKey: namesKey) ?? []
        while saved.count < baseNames.count { saved.append("") }
        saved[id] = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(14))
        d.set(saved, forKey: namesKey)
        names = loadNames(d)
    }
    /// A fresh install: Bob, Pip and Moss (the roster before the characters round; Lavender stays available).
    static let defaultIDs = [0, 1, 2]
    static let rosterKey = "BlobRoster.v1"
    static let setRosterKey = "SetRoster"
    static let forceSpeciesKey = "ForceSpecies"

    /// Colour -> feature: blue none, yellow spines, green daisy, lavender wings. (By CHARACTER id.)
    static func feature(_ instance: Int) -> JellyFeature {
        let id = species(instance)
        if WhiteWing.isForced(id) { return .wings }          // -ForceSpecies whitewing (look-only candidate, captures)
        switch id { case 1: return .spines; case 2: return .daisy; case 3, pearlID: return .wings; case teddyID, pandaID: return .ears; default: return .none }
    }

    // MARK: the roster (characters by slot)

    /// Character name or id, case-insensitive ("pip", "Lavender", "2"); nil when unknown.
    static func characterID(named raw: String) -> Int? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let i = baseNames.firstIndex(where: { $0.lowercased() == t }) ?? names.firstIndex(where: { $0.lowercased() == t }) { return i }
        if let n = Int(t), (0..<knownCount).contains(n) { return n }
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
    /// Picker scratch ids (>= 1000) are dropped unless `allowPreview`: only a preview GameCare asks for them, so no save or roster ever holds one.
    static func sanitised(_ ids: [Int], allowPreview: Bool = false) -> [Int] {
        var out: [Int] = []
        for c in ids where isValid(c) && (allowPreview || !isPreview(c)) && !out.contains(c) { out.append(c) }
        return out.isEmpty ? defaultIDs : Array(out.prefix(maxCount))
    }
    /// The roster saved in `d` (the default roster when none was saved).
    static func savedIDs(_ d: UserDefaults = .standard) -> [Int] {
        guard let a = d.array(forKey: rosterKey) as? [Int] else { return defaultIDs }
        return sanitised(a)
    }
    /// Saves `ids` (sanitised) as the roster.
    static func save(_ ids: [Int], to d: UserDefaults = .standard) { d.set(sanitised(ids), forKey: rosterKey) }

    /// Set by the development `-AdoptNow` argument once its Jelbie is bought: `-SetRoster` then no longer re-applies on rebuilding the room (it would drop him again).
    nonisolated(unsafe) static var setRosterSuspended = false
    /// Applies `-SetRoster a,b,c` when the launch argument is present: the saved roster becomes exactly that list. Returns the roster now in force.
    /// Each character keeps whatever is saved under his own keys (nothing is copied or cleared); a character with no saved data starts fresh
    /// the first time his profile loads. Idempotent: the same argument again writes the same list; no argument leaves the saved roster alone.
    @discardableResult
    static func applySetRoster(_ d: UserDefaults = .standard) -> [Int] {
        if DevArgs.enabled, !setRosterSuspended, let text = d.string(forKey: setRosterKey), let ids = parseRoster(text) {
            if savedIDs(d) != ids { save(ids, to: d) }
            return ids
        }
        return savedIDs(d)
    }
    /// The characters in the room at launch, by slot: `-SetRoster` applied, then the saved roster, cut to `-BlobCount` when given.
    static func launchIDs(_ d: UserDefaults = .standard) -> [Int] {
        var ids = applySetRoster(d)
        // `-ForceSpecies teddy`: that species takes slot 0 for this launch only (never saved), so a capture can spawn one without touching the saved roster
        if DevArgs.enabled, let f = d.string(forKey: forceSpeciesKey), let c = characterID(named: f) { ids = Array(([c] + ids.filter { $0 != c }).prefix(maxCount)) }
        guard DevArgs.enabled, d.object(forKey: "BlobCount") != nil else { return ids }
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
    /// The species (look / voice) of the Jelbie in `slot`.
    @MainActor static func speciesOf(slot: Int) -> Int { species(character(slot)) }
    /// The slots holding a Jelbie of `species` (a duplicate means more than one).
    @MainActor static func slots(ofSpecies s: Int) -> [Int] { current.indices.filter { species(current[$0]) == s } }
    @MainActor static func name(slot: Int) -> String { nameOf(character(slot)) }
    /// The names of the Jelbies in the room right now, by slot (duplicates included).
    @MainActor static var currentNames: [String] { current.map { nameOf($0) } }
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
    static func palette(_ instance: Int) -> Palette? {
        if WhiteWing.hasLook(instance) { return WhiteWing.palette }
        if let v = JellyVariants.active(instance) { return v.palette }    // an adopted / previewed Jelly Spring colour variant (belongs to the INSTANCE; species + feature unchanged)
        switch species(instance) {
        case 1: return PaletteKey.yellow.palette
        case 2: return JellyPalettes.green
        case 3: return JellyPalettes.lavender
        case teddyID: return TeddyLook.current.palette
        case pandaID: return PandaLook.palette
        default: return nil
        }
    }

    /// sRGB 0...1 swatch for the roster card / selection preview (by CHARACTER).
    static func tint(_ instance: Int) -> SIMD3<Float> {
        if WhiteWing.hasLook(instance) { return WhiteWing.swatch }
        if let v = JellyVariants.active(instance) { return v.swatch }
        switch species(instance) {
        case 1: return SIMD3(0.99, 0.90, 0.62)
        case 2: return SIMD3(0.70, 0.90, 0.66)
        case 3: return SIMD3(0.80, 0.72, 0.93)
        case teddyID: return TeddyLook.current.flesh
        case pandaID: return PandaLook.swatch
        default: return SIMD3(0.70, 0.83, 0.945)
        }
    }

    /// Selection cards for a roster (slot ids, character names and tints).
    static func selectBlobs(roster: [Int]) -> [SelectBlob] {
        sanitised(roster, allowPreview: true).enumerated().map { SelectBlob(id: $0.offset, name: nameOf($0.element), tint: tint($0.element)) }
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
