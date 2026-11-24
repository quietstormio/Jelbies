//
//  JellyCamp.swift
//  Jelmiko Camp: where the creatures bought beyond the three at home stay. NO UI here: the model, the rules and the save.
//
//  DATA: one key, "JellyCamp.v1" = [Int], the INSTANCE ids staying at Camp, in arrival order. Everything a creature owns (needs, name, colour, traits, wardrobe, tricks,
//  trophies ...) stays under its instance id exactly as before: moving between home and Camp changes only which of the two lists holds the id. An old save has
//  no key: its Camp is empty and nothing is migrated. Home is still "BlobRoster.v1" (1...3 ids, the order is the room's slots).
//
//  API (what the UI steps call):
//   JellyCamp.cap                                  6 places at Camp (every Camp creature is on screen at once in the yard)
//   JellyCamp.saved(d)                             the Camp ids as loaded now (home wins an overlap; never invents anyone)
//   JellyCamp.load(home:, d)                       the same for a given home list
//   JellyCamp.owned(home:camp:)                    everyone the player has (home then Camp)
//   JellyCamp.destination(home:camp:)              .home / .camp / .full for a NEW creature, from the two COUNTS
//   JellyCamp.canBringHome(id, home:camp:)         id is at Camp and home has fewer than 3
//   JellyCamp.canSendToCamp(id, home:camp:)        id is at home, at least one OTHER stays home, Camp has room
//   JellyCamp.bringHome / sendToCamp / swap        pure rules: return the new (home, camp) or nil when refused. bringHome appends to the END of home;
//                                                   swap(in: campID, out: homeID) puts campID in homeID's slot and homeID where campID was in the camp list
//   JellyCamp.commit(from:to:d)                    writes a rule's result in the crash-safe order; returns false (writes nothing) when `to` breaks an invariant
//   JellyCamp.restamp(id, now:, d)                 frozen at Camp: needs / dirt / condition clocks set to now (commit callers do this for the one coming home)
//   JellyCamp.settleCondition(id, now:, d)         on the way TO Camp: the condition decay since its last meal is applied once, so the stamp reset on the way home cannot hand it back
//   StartFlow.campMove(.bringHome / .sendToCamp / .swap, d)   rule + restamp + commit in one call (StartFlow.campBringHome / campSendToCamp / campSwap on the live flow)
//   StartFlow.shared.openCamp() / leaveCamp()      the Camp phase (`.camp(newID)`); leaving rebuilds the room once
//   JellyCamp.members(d)                           the yard's data per Camp creature (id, species, name, palette, variant, traits, worn), camp-list order
//   JellyCamp.profiles(d)                          the Camp creatures as JellyProfile (the room's type), in-memory only; see the note on the function for what is position-bound
//   (every rule and campMove only reads / writes the two lists and the one creature's clocks: they stay callable while a Camp stage is on screen)
//   AdoptionPrice.next(home:camp:rare:special:)    price of the next creature; at home 3 it is what a third costs, nil when home and Camp are both full
//
//  WRITE ORDER (two keys, no transaction): the list that GAINS the id is written first. A kill after any single write leaves the id in both lists, which `load` reads
//  as "at home", never in neither. The Camp key is written RAW by `commit` (a filtered write would drop an id that is still at home) and only `load` filters.
//  `load` NEVER goes through JellyRoster.sanitised (it cuts to 3 and turns an empty list into the three starters).
//

import Foundation

nonisolated enum JellyCamp {
    static let key = "JellyCamp.v1"
    /// Six: every Camp creature is on screen at once in the 3D yard and six bodies is the safe limit. THE one constant: rules, prices, tests and texts read it.
    static let cap = 6
    /// Creatures at home at most (the room's cap).
    static var homeCap: Int { JellyRoster.maxCount }

    /// A home list and a Camp list.
    typealias Lists = (home: [Int], camp: [Int])

    // MARK: load

    /// The Camp ids in `d`: valid instance ids, never a picker preview, no repeats, anyone who is at `home` removed (HOME WINS an overlap), at most `cap`.
    /// Empty when nothing was saved. Never touches JellyRoster.sanitised.
    static func load(home: [Int], _ d: UserDefaults = .standard) -> [Int] {
        guard let raw = d.array(forKey: key) as? [Int] else { return [] }
        var out: [Int] = []
        let releasing = (d.dictionary(forKey: "JellyCamp.release.v1")?["id"] as? Int) ?? -1          // a creature being let go is already gone for every reader
        for id in raw where id != releasing && JellyRoster.isValid(id) && !JellyRoster.isPreview(id) && !home.contains(id) && !out.contains(id) { out.append(id) }
        return Array(out.prefix(cap))
    }
    /// The Camp ids against the saved home list.
    static func saved(_ d: UserDefaults = .standard) -> [Int] { load(home: JellyRoster.savedIDs(d), d) }
    /// Both lists as the save holds them now.
    static func savedLists(_ d: UserDefaults = .standard) -> Lists { let h = JellyRoster.savedIDs(d); return (h, load(home: h, d)) }
    /// Every creature the player has: home, then Camp.
    static func owned(home: [Int], camp: [Int]) -> [Int] { home + camp.filter { !home.contains($0) } }

    // MARK: rules (pure)

    enum Destination: Equatable { case home, camp, full }
    /// Where a NEW creature goes, from the counts: home while it has fewer than 3, else Camp while it has room, else nowhere (nothing is bought).
    static func destination(home: Int, camp: Int) -> Destination {
        if home < homeCap { return .home }
        return camp < cap ? .camp : .full
    }
    static func canSendToCamp(_ id: Int, home: [Int], camp: [Int]) -> Bool { home.contains(id) && home.count >= 2 && camp.count < cap }
    static func canBringHome(_ id: Int, home: [Int], camp: [Int]) -> Bool { camp.contains(id) && !home.contains(id) && home.count < homeCap }

    /// `id` leaves Camp and joins the END of home; nil when refused (not at Camp, home full).
    static func bringHome(_ id: Int, home: [Int], camp: [Int]) -> Lists? {
        guard canBringHome(id, home: home, camp: camp) else { return nil }
        return (home + [id], camp.filter { $0 != id })
    }
    /// `id` leaves home and joins the END of the camp list; nil when refused (not at home, only one at home, Camp full).
    static func sendToCamp(_ id: Int, home: [Int], camp: [Int]) -> Lists? {
        guard canSendToCamp(id, home: home, camp: camp) else { return nil }
        return (home.filter { $0 != id }, camp + [id])
    }
    /// `campID` takes `homeID`'s slot at home, `homeID` takes `campID`'s place in the camp list; nobody else moves. nil when either is not where it should be.
    static func swap(in campID: Int, out homeID: Int, home: [Int], camp: [Int]) -> Lists? {
        guard let h = home.firstIndex(of: homeID), let c = camp.firstIndex(of: campID), !home.contains(campID), !camp.contains(homeID) else { return nil }
        var nh = home, nc = camp
        nh[h] = campID; nc[c] = homeID
        return (nh, nc)
    }

    /// The two lists describe every creature once: disjoint, no repeats, 1...3 at home, at most `cap` at Camp.
    static func isConsistent(_ l: Lists) -> Bool {
        Set(l.home).count == l.home.count && Set(l.camp).count == l.camp.count && Set(l.home).isDisjoint(with: l.camp)
            && (1...homeCap).contains(l.home.count) && l.camp.count <= cap
    }

    // MARK: commit (crash-safe order)

    /// The writes `commit` does for a move from `old` to `new`, in order: (1) the Camp list widened to old + the newcomers (the id that is leaving home is now in BOTH
    /// lists = still home), (2) the home list, (3) the Camp list tidied to `new`. A step that would change nothing is left out. After ANY prefix of these, `load` reads
    /// every creature exactly once. (The widened list may hold up to cap + 1 raw ids in a swap: `load` removes the ones at home BEFORE it cuts to `cap`.)
    enum Write: Equatable { case camp([Int]), home([Int]) }
    static func writes(from old: Lists, to new: Lists) -> [Write] {
        var out: [Write] = []
        let wide = old.camp + new.camp.filter { !old.camp.contains($0) }
        var campNow = old.camp
        if wide != campNow { out.append(.camp(wide)); campNow = wide }
        if new.home != old.home { out.append(.home(new.home)) }
        if new.camp != campNow { out.append(.camp(new.camp)) }
        return out
    }
    /// Writes one step (the Camp list RAW, the home list the way the roster always is).
    static func apply(_ w: Write, _ d: UserDefaults) {
        switch w {
        case .camp(let ids): d.set(ids, forKey: key)
        case .home(let ids): JellyRoster.save(ids, to: d)
        }
    }
    /// Writes a move in the crash-safe order. False (nothing written) when `new` is not a consistent state or is not the same set of creatures as `old`.
    /// `stopAfter`: test hook that simulates the app being killed after that many writes.
    @discardableResult
    static func commit(from old: Lists, to new: Lists, _ d: UserDefaults = .standard, stopAfter: Int? = nil) -> Bool {
        guard isConsistent(old), isConsistent(new), Set(owned(home: old.home, camp: old.camp)) == Set(owned(home: new.home, camp: new.camp)) else { return false }
        for (i, w) in writes(from: old, to: new).enumerated() {
            if let s = stopAfter, i >= s { break }
            apply(w, d)
        }
        return true
    }
    /// Adds a NEW creature to the Camp list (its id was in neither list: a single write, nothing to order).
    static func addNew(_ id: Int, camp: [Int], _ d: UserDefaults = .standard) { d.set(camp + [id], forKey: key) }

    // MARK: frozen at Camp

    /// Nothing ticks at Camp (no profile exists for a Camp creature), but the saved clocks keep their old time: coming home would apply the whole stay as time away.
    /// So the one coming home gets its clocks set to `now`: needs "time" (and "asleep" false), dirt's "at", and the condition stamp. Levels, dirt, sparkle and condition
    /// are untouched. A key that is not there stays missing (a never-home newcomer starts fresh as always). Boosts (perks) are NOT touched: they run out on the clock.
    @MainActor static func restamp(_ id: Int, now: Date, _ d: UserDefaults = .standard) {
        let t = now.timeIntervalSince1970
        let needsKey = JellyKeys.needs(id)
        // Coming home from Camp: it was looked after there, so it arrives with every need full (the stay is not time away either: the clock restarts now).
        if var n = d.dictionary(forKey: needsKey) { n["time"] = t; n["asleep"] = false; n["levels"] = [Double](repeating: Double(NeedsTuning.seedArrival), count: 3); d.set(n, forKey: needsKey) }
        let grimeKey = JellyKeys.grime(id)
        if let data = d.data(forKey: grimeKey), var g = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            g["at"] = t
            if let out = try? JSONSerialization.data(withJSONObject: g) { d.set(out, forKey: grimeKey) }
        }
        let condKey = JellyKeys.stats(id) + ".cond"
        if var c = d.array(forKey: condKey) as? [Double], c.count > 1 { c[c.count - 1] = t; d.set(c, forKey: condKey) }
    }

    /// Going to Camp: the condition stat decays slowly from its stamp (the last meal / outfit), so before the clocks stop the decay so far is written in and the stamp moves to
    /// `now`. Without this the restamp on the way home would give back everything lost since the last meal. A creature with no saved stats is left alone.
    @MainActor static func settleCondition(_ id: Int, now: Date, _ d: UserDefaults = .standard) {
        let key = JellyKeys.stats(id)
        guard d.object(forKey: key + ".cond") != nil else { return }
        let stats = JellyStats(persists: true, defaults: d, key: key, traitSeed: JellyTraitsBook.record(id).map { StatTuning.seed(jars: $0.jars) }, now: { now })
        stats.nudge([:])          // every stat takes its decay, the stamp moves to now, and it is saved
    }

    // MARK: the yard (3D stage of the Camp creatures)

    /// Everything needed to put a Camp creature's body on a stage as it looks at home. Built from the save; nothing in it is position-bound.
    @MainActor struct Member {
        let id: Int                 // INSTANCE id (every save key)
        let species: Int            // look / voice / feature
        let name: String
        let palette: Palette?       // JellyRoster.palette(id): the species colour or its adopted Jelly Spring variant (nil = Bob's model colour)
        let variant: JellyVariant?
        let traits: JellyTraits?    // personality, jars, favourite snack
        let worn: [WearSlot: WearLook]   // what it left home wearing (the saved wardrobe under its instance id)
    }
    /// The Camp creatures in camp-list order (arrival order; a stable order), read against the saved home list.
    @MainActor static func members(_ d: UserDefaults = .standard) -> [Member] {
        let l = savedLists(d)
        let store = SaveRecovery.decode(StoreBook.Saved.self, key: StoreBook.key, defaults: d)
        return l.camp.map { id in
            var worn: [WearSlot: WearLook] = [:]
            for (slot, raw) in store?.worn[String(id)] ?? [:] { if let sl = WearSlot(rawValue: slot), let look = WearLook(rawValue: raw) { worn[sl] = look } }
            return Member(id: id, species: JellyRoster.species(id), name: JellyRoster.nameOf(id), palette: JellyRoster.palette(id), variant: JellyVariants.adopted(id), traits: JellyTraitsBook.record(id), worn: worn)
        }
    }
    /// The Camp creatures as the room's own profile type, in camp-list order: profile.id = the yard's slot (0...n-1), profile.character = the instance id. IN MEMORY ONLY
    /// (`persists: false`): building one reads and writes nothing in the save, so no time away is applied and the frozen needs / dirt / condition stay as they were left.
    /// The needs inside are fresh stand-ins, not the saved ones. Wardrobe is NOT in the profile: it lives in StoreBook, which finds outfits through the room's slot ->
    /// character closure (`store.characterOf`), so a yard stage must read `members()[slot].worn` or set that closure itself.
    @MainActor static func profiles(_ d: UserDefaults = .standard) -> [JellyProfile] {
        savedLists(d).camp.enumerated().map { JellyProfile(id: $0.offset, character: $0.element, name: JellyRoster.nameOf($0.element), persists: false, defaults: d) }
    }
}
