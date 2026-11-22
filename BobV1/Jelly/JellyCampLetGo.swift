//
//  JellyCampLetGo.swift
//  "Say goodbye": a creature AT CAMP can be let go for good (it goes back to the Jelly Spring). No UI here.
//
//  API:
//   JellyCamp.thankYouCoins                      the thank-you the wallet gains, once (100 JellyCoins)
//   JellyCamp.canLetGo(id, home:camp:)           only a creature at Camp (a home one must be sent to Camp first); never leaves the player with nobody
//   JellyCamp.letGo(id, home:camp:)              pure rule: the lists after it (the id is in neither); nil when refused
//   JellyCamp.letGo(_ id:, _ d:)                 the real thing (see the order below); false when refused (nothing written, nothing paid)
//   JellyCamp.resumeRelease(d)                   finishes a release a kill interrupted; StartFlow.applyLaunchArguments calls it at every launch
//   JellyCamp.instanceKeys(id)                   THE list of every plain per-instance defaults key
//   JellyCamp.purge(id, d)                       removes everything stored for that instance (plain keys + its entries inside the shared books) and nothing else
//   JellyCamp.onPurge                            hooks run by the purge (the saved head picture registers `CampHeads.remove` here)
//
//  WRITE ORDER (reasoning): the creature, the coins and the purge live under different keys with no transaction, so one MARKER key ("JellyCamp.release.v1" =
//  {id, target wallet}) is written FIRST and means "this release is going through". Before the marker nothing has happened (the creature is fully there, unpaid).
//  From the marker on, the rest is a roll-forward made only of idempotent writes, in this order: (1) the wallet is set to the ABSOLUTE target (old balance + 100; set again
//  only if it is still below it, so a repeat can never pay twice), (2) the id leaves the Camp list, (3) the purge, (4) the marker is removed. `load` hides the marked
//  id from the moment the marker exists, so a kill anywhere after it shows nobody half-there; the next launch finishes the job (resumeRelease). A kill can never pay twice
//  and never lose the creature without paying: the creature leaves the Camp list only AFTER the wallet holds the target. The id is free for a later purchase only once
//  the marker is gone (allocateInstance sees the id in nobody's list, and the purge has run).
//

import Foundation

nonisolated extension JellyCamp {
    /// The thank-you for a creature let go: 100 JellyCoins, once.
    static let thankYouCoins = 100
    static let releaseKey = "JellyCamp.release.v1"
    /// Run by `purge` for the id being let go (pictures that live outside the defaults register here).
    nonisolated(unsafe) static var onPurge: [(Int) -> Void] = []

    // MARK: rule

    static func canLetGo(_ id: Int, home: [Int], camp: [Int]) -> Bool { camp.contains(id) && !home.contains(id) && !home.isEmpty }
    static func letGo(_ id: Int, home: [Int], camp: [Int]) -> Lists? {
        guard canLetGo(id, home: home, camp: camp) else { return nil }
        return (home, camp.filter { $0 != id })
    }

    // MARK: the marker

    /// The release in progress, if a kill left one.
    static func pendingRelease(_ d: UserDefaults = .standard) -> (id: Int, target: Int)? {
        guard let m = d.dictionary(forKey: releaseKey), let id = m["id"] as? Int, let t = m["target"] as? Int else { return nil }
        return (id, t)
    }

    /// Lets `id` go: the marker, then the roll-forward. False (nothing written, nothing paid) when it is refused. `stopAfter`: test hook, a kill after that many writes.
    @MainActor @discardableResult
    static func letGo(_ id: Int, _ d: UserDefaults = .standard, stopAfter: Int? = nil) -> Bool {
        if let p = pendingRelease(d) {          // an interrupted release (this id or another): finish it first; it never pays twice
            resumeRelease(d)
            if p.id == id { return false }
        }
        let l = savedLists(d)
        guard canLetGo(id, home: l.home, camp: l.camp) else { return false }
        if stopAfter == 0 { return true }          // test hook: killed before the first write
        d.set(["id": id, "target": d.integer(forKey: DropsWallet.key) + thankYouCoins], forKey: releaseKey)          // write 1
        resumeRelease(d, stopAfter: stopAfter.map { max($0 - 1, 0) })
        return true
    }

    /// Finishes the release the marker names (nothing when there is none). Every write is safe to repeat.
    @MainActor
    static func resumeRelease(_ d: UserDefaults = .standard, stopAfter: Int? = nil) {
        guard let p = pendingRelease(d) else { return }
        var n = 0
        func go(_ write: () -> Void) -> Bool { if let s = stopAfter, n >= s { return false }; write(); n += 1; return true }
        guard go({ if d.integer(forKey: DropsWallet.key) < p.target { d.set(p.target, forKey: DropsWallet.key) } }) else { return }          // write 2: absolute, never +100 twice
        guard go({ if let raw = d.array(forKey: key) as? [Int] { d.set(raw.filter { $0 != p.id }, forKey: key) } }) else { return }          // write 3: raw, like commit
        guard go({ purge(p.id, d) }) else { return }                                                                                    // write 4
        _ = go({ d.removeObject(forKey: releaseKey) })                                                                                  // write 5
    }

    // MARK: the purge

    /// Every plain per-instance defaults key of `id`: needs, dirt, words, stats (+ condition, meals, dances), boosts, relationship (BlobBond). Exact keys only (id 0 owns the bare legacy keys, which
    /// are also the prefix of every other id's keys). Anything per-instance that lives INSIDE a shared book is handled in `purge`; both lists are the one place to add to.
    @MainActor static func instanceKeys(_ id: Int) -> [String] {
        let stats = JellyKeys.stats(id)
        return [JellyKeys.needs(id), JellyKeys.grime(id), JellyKeys.words(id), stats, stats + ".cond", stats + ".meals", stats + ".dances", stats + ".story", stats + ".events", JellyKeys.perks(id), JellyKeys.bond(id)]
    }

    /// The shared books that hold an entry per instance, and where the entry is. (Documentation for `purge`; the test that scans a played creature checks each one.)
    ///   JellyTraits.v1, JellyVariants.v1, JellyNicknames.v1, Circuit.trophies.v1       root["<id>"]
    ///   StoreBook.v1                                                                   worn["<id>"] (clothes stay owned: only who wears them goes), ownedTricks["<id>"]
    ///   JellyShow.progress.v1                                                          trophies["<id>"]
    ///   Volley.book.v1                                                                 stats["<id>"]; "volley.partner" when it is this id
    ///   UpgradeBook.v1                                                                 points / chosen keys "<game>.<id>"
    ///   ParkVisitors.v1                                                                every visitor's friendship["<id>"];  ParkLedger.v1 love["<id>"]
    ///   JellyNames.v1 (ids 0...6), JellyNamesExtra.v1 / JellySpeciesOf.v1 (ids 100+)    the name, the species record
    @MainActor
    static func purge(_ id: Int, _ d: UserDefaults = .standard) {
        let sid = String(id)
        for k in instanceKeys(id) { d.removeObject(forKey: k) }
        scrub(JellyTraitsBook.key, d) { $0.removeValue(forKey: sid) }
        scrub(JellyVariants.key, d) { $0.removeValue(forKey: sid) }
        scrub(JellyNames.defaultsKey, d) { $0.removeValue(forKey: sid) }
        scrub("Circuit.trophies.v1", d) { $0.removeValue(forKey: sid) }
        scrub(StoreBook.key, d) { root in
            if var w = root["worn"] as? [String: Any] { w.removeValue(forKey: sid); root["worn"] = w }
            if var t = root["ownedTricks"] as? [String: Any] { t.removeValue(forKey: sid); root["ownedTricks"] = t }
        }
        scrub(ShowProgress.key, d) { root in if var t = root["trophies"] as? [String: Any] { t.removeValue(forKey: sid); root["trophies"] = t } }
        scrub("Volley.book.v1", d) { root in if var t = root["stats"] as? [String: Any] { t.removeValue(forKey: sid); root["stats"] = t } }
        if d.object(forKey: "volley.partner") != nil, d.integer(forKey: "volley.partner") == id { d.removeObject(forKey: "volley.partner") }
        scrub(UpgradeTuning.defaultsKey, d) { root in
            for field in ["points", "chosen"] { if var m = root[field] as? [String: Any] { for k in m.keys where k.hasSuffix(".\(sid)") { m.removeValue(forKey: k) }; root[field] = m } }
        }
        scrub(ParkBook.ledgerKey, d) { root in if var l = root["love"] as? [String: Any] { l.removeValue(forKey: sid); root["love"] = l } }
        if let data = d.data(forKey: ParkBook.key), var vs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for i in vs.indices { if var f = vs[i]["friendship"] as? [String: Any] { f.removeValue(forKey: sid); vs[i]["friendship"] = f } }
            if let out = try? JSONSerialization.data(withJSONObject: vs) { d.set(out, forKey: ParkBook.key) }
        }
        if id < JellyRoster.knownCount {
            if var names = d.stringArray(forKey: JellyRoster.namesKey), names.indices.contains(id) { names[id] = ""; d.set(names, forKey: JellyRoster.namesKey) }
        } else {
            for k in [JellyRoster.extraNamesKey, JellyRoster.speciesKey] { if var m = d.dictionary(forKey: k) { m.removeValue(forKey: sid); d.set(m, forKey: k) } }
        }
        StoryBook.purge(id, d); StoryHabitStore.shared.forget(id)          // (Story/: the blurb, the notes naming this one, and the habit counters)
        if d === UserDefaults.standard { StoryBook.shared.reload() }
        for hook in onPurge { hook(id) }
        JellyRoster.reloadSpecies(d); JellyRoster.names = JellyRoster.loadNames(d)          // the in-memory copies follow the save
        JellyVariants.reload(d); JellyTraitsBook.reload(d)
    }

    /// Edits a JSON-object book in place; a missing or unreadable key is left alone.
    private static func scrub(_ key: String, _ d: UserDefaults, _ edit: (inout [String: Any]) -> Void) {
        guard let data = d.data(forKey: key), var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        edit(&root)
        if let out = try? JSONSerialization.data(withJSONObject: root) { d.set(out, forKey: key) }
    }
}
