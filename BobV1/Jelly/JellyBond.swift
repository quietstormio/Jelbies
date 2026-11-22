//
//  JellyBond.swift
//  The RELATIONSHIP between the player and ONE Jelmiko: a long-term bond that only ever grows, a little with everything the player does with them, over days and weeks.
//  Shown on the Profile only (hearts that fill partly + a level name); nothing else in the game reads it, and nothing outside the Profile announces it.
//
//  STORED per creature under `BlobBond.v1` (id 0) / `BlobBond.v1.jelly<id>` (the `JellyKeys` family; purged by `JellyCamp.instanceKeys`), as a small dictionary:
//    ["p": points, "d": the calendar day the "t" table belongs to (yyyymmdd), "t": [kind: points counted today]].
//  The store is STATELESS (every call reads and writes the defaults), so a rebuilt profile can never write back an older number. Points are whole numbers, never taken away.
//  No key = an old save: `seedIfNeeded` writes the key ONCE from what the save already records (even when that is 0, so a new pet is never seeded later).
//
//  TUNING (everything is in `BondTuning`; "ordinary day" = open the game, two strokes, two meals, two drinks, one toy, two tricks = 20 points):
//
//    event (per Jelmiko)                  points   per-day cap
//    first open of a new day                 2         2
//    a stroke session (4 s of hearts)        3         6
//    a meal eaten (favourite food)         3 (5)       9
//    a drink                                 1         3
//    a bath or a groom                       3         6
//    a toy the player starts                 2         6
//    a trick on voice / "come here"          1         5
//    park / race / show / volley             3 (+2 win) 5 each
//    ALL KINDS TOGETHER                                30
//
//    heart n is full at (points):   20, 60, 140, 350, 840
//    ordinary play (20 a day)  ->   heart 1 on day 1, heart 2 about day 3, heart 3 about day 7, heart 4 about day 18, heart 5 about day 42.
//    the fastest possible (30 a day) is 28 days to the fifth heart, never one sitting.
//

import Foundation

nonisolated enum BondKind: String, CaseIterable, Sendable {
    case dayOpen, stroke, meal, drink, care, toy, trick, park, race, show, volley
}

nonisolated enum BondTuning {
    /// Points per event.
    static func points(_ k: BondKind, favourite: Bool = false, win: Bool = false) -> Int {
        switch k {
        case .dayOpen: return 2
        case .stroke: return 3
        case .meal: return favourite ? 5 : 3
        case .drink: return 1
        case .care: return 3
        case .toy: return 2
        case .trick: return 1
        case .park: return 3
        case .race, .show, .volley: return 3 + (win ? 2 : 0)
        }
    }
    /// Per-day cap of one kind, per Jelmiko.
    static func dayCap(_ k: BondKind) -> Int {
        switch k {
        case .dayOpen: return 2
        case .stroke: return 6
        case .meal: return 9
        case .drink: return 3
        case .care: return 6
        case .toy: return 6
        case .trick: return 5
        case .park, .race, .show, .volley: return 5
        }
    }
    /// Per-day cap of everything together.
    static let totalDayCap = 30
    /// Seconds of stroking that give hearts (and are not refused) that make one stroke event.
    static let strokeSeconds: Float = 4
    /// The points at which heart 1...5 is full.
    static let heartFull = [20, 60, 140, 350, 840]
    static let hearts = 5
    static let levelNames = ["Just met", "Getting to know you", "Friends", "Good friends", "Close friends", "Best friends"]

    // MARK: the one-time seed for creatures that were already in the save
    static let seedMeal = 5, seedMealsMax = 8            // the diary keeps 8
    static let seedTrick = 8, seedTricksMax = 5
    static let seedRace = 6, seedWin = 6, seedRacesMax = 10
    static let seedTrophy = 10, seedTrophiesMax = 5
    /// A seed never goes past this (inside heart 4: about 3 full hearts and a bit).
    static let seedCap = 300
}

/// What the Profile draws: whole hearts, the share of the next one, and the level name.
nonisolated struct BondLevel: Equatable, Sendable {
    let points: Int
    /// Hearts that are full (0...5).
    let hearts: Int
    /// How full the next heart is (0..<1); 0 when all five are full.
    let partial: Double
    var name: String { BondTuning.levelNames[hearts] }
    /// "Relationship: Good friends, 3 of 5 hearts"
    var spoken: String { "Relationship: \(name), \(hearts) of \(BondTuning.hearts) hearts" }

    init(points: Int) {
        let p = max(points, 0)
        self.points = p
        let full = BondTuning.heartFull.filter { p >= $0 }.count
        hearts = full
        if full >= BondTuning.hearts { partial = 0 }
        else {
            let lo = full == 0 ? 0 : BondTuning.heartFull[full - 1], hi = BondTuning.heartFull[full]
            partial = Double(p - lo) / Double(hi - lo)
        }
    }
    /// 0...1 fill of heart `i` (0-based).
    func fill(_ i: Int) -> Double { i < hearts ? 1 : i == hearts ? partial : 0 }
}

nonisolated enum JellyBond {
    static let legacyKey = "BlobBond.v1"
    /// The key of a creature's bond (id 0 owns the bare key, like needs / stats).
    static func key(_ id: Int) -> String { id == 0 ? legacyKey : "\(legacyKey).jelly\(id)" }

    /// The calendar day as yyyymmdd (real date; never the game clock).
    static func dayKey(_ date: Date, calendar cal: Calendar = .current) -> Int {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    // MARK: read

    /// The points now (seeds first when there is no key).
    static func points(_ id: Int, _ d: UserDefaults = .standard) -> Int {
        seedIfNeeded(id, d)
        return (d.dictionary(forKey: key(id))?["p"] as? Int) ?? 0
    }
    static func level(_ id: Int, _ d: UserDefaults = .standard) -> BondLevel { BondLevel(points: points(id, d)) }
    /// What was counted today per kind (for tests and the dev log).
    static func today(_ id: Int, _ d: UserDefaults = .standard, now: Date = Date()) -> [String: Int] {
        guard let m = d.dictionary(forKey: key(id)), (m["d"] as? Int) == dayKey(now), let t = m["t"] as? [String: Int] else { return [:] }
        return t
    }

    // MARK: write

    /// Counts one event for creature `id`. Returns the points actually added (0 when a cap was reached). Only ever adds.
    @discardableResult
    static func earn(_ kind: BondKind, _ id: Int, favourite: Bool = false, win: Bool = false, _ d: UserDefaults = .standard, now: Date = Date()) -> Int {
        seedIfNeeded(id, d)
        var m = d.dictionary(forKey: key(id)) ?? [:]
        let day = dayKey(now)
        var t = (m["d"] as? Int) == day ? (m["t"] as? [String: Int] ?? [:]) : [:]
        let kindLeft = BondTuning.dayCap(kind) - (t[kind.rawValue] ?? 0)
        let totalLeft = BondTuning.totalDayCap - t.values.reduce(0, +)
        let add = max(0, min(BondTuning.points(kind, favourite: favourite, win: win), kindLeft, totalLeft))
        guard add > 0 else {
            if (m["d"] as? Int) != day { m["d"] = day; m["t"] = t; d.set(m, forKey: key(id)) }
            return 0
        }
        t[kind.rawValue, default: 0] += add
        m["p"] = ((m["p"] as? Int) ?? 0) + add
        m["d"] = day; m["t"] = t
        d.set(m, forKey: key(id))
        return add
    }

    /// Writes the key once for a creature that has none, from what its save already records. Does nothing when the key exists.
    static func seedIfNeeded(_ id: Int, _ d: UserDefaults = .standard) {
        guard d.object(forKey: key(id)) == nil else { return }
        d.set(["p": seed(id, d), "d": 0, "t": [String: Int]()] as [String: Any], forKey: key(id))
    }

    /// The seed: a pure function of the raw defaults (meals in the diary, tricks learned, races and wins, trophies). Capped.
    static func seed(_ id: Int, _ d: UserDefaults = .standard) -> Int {
        let stats = id == 0 ? "BlobStats.v1" : "BlobStats.v1.jelly\(id)"
        let words = id == 0 ? "BlobWords.v1" : "BlobWords.v1.jelly\(id)"
        var total = 0
        if let md = d.data(forKey: stats + ".meals"), let arr = (try? JSONSerialization.jsonObject(with: md)) as? [Any] { total += min(arr.count, BondTuning.seedMealsMax) * BondTuning.seedMeal }
        if let a = d.array(forKey: stats) as? [Double], a.count >= 4 {
            total += min(Int(a[2]), BondTuning.seedRacesMax) * BondTuning.seedRace + min(Int(a[3]), BondTuning.seedRacesMax) * BondTuning.seedWin
        }
        if let wd = d.data(forKey: words), let root = (try? JSONSerialization.jsonObject(with: wd)) as? [String: Any], let tr = root["tricks"] as? [String: Any] {
            let learned = tr.values.filter { ($0 as? [String: Any])?["learned"] as? Bool == true }.count
            total += min(learned, BondTuning.seedTricksMax) * BondTuning.seedTrick
        }
        if let td = d.data(forKey: "Circuit.trophies.v1"), let root = (try? JSONSerialization.jsonObject(with: td)) as? [String: Any], let me = root[String(id)] as? [String: Any] {
            let earned = (me["earned"] as? [Any])?.count ?? 0
            total += min(earned, BondTuning.seedTrophiesMax) * BondTuning.seedTrophy
        }
        return min(total, BondTuning.seedCap)
    }

    static func remove(_ id: Int, _ d: UserDefaults = .standard) { d.removeObject(forKey: key(id)) }
}
