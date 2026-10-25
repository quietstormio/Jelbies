//
//  TrophyBook.swift
//  What each Jelbie has won on the Circuit and at the Show, kept per CHARACTER (the same id the Show's cups use):
//
//    RIBBONS   one per race placing 1st / 2nd / 3rd, counted per course tier (Puddle ... Tsunami). A ribbon is NEW (the results card says "New ribbon!")
//              the first time that place is won on that tier. The Show keeps its own cups (gold / silver / bronze per rank, Show/ShowProgress.swift): those are
//              the contest ribbons, shown beside these on the Trophies sheet and on the wall shelf; nothing about the Show is stored twice.
//    TROPHIES  milestones of RACE wins (1st places) over all tiers: the first win on each tier, then 5, 10 and 25 wins, and "Champion" for a win on every tier.
//
//  Saved as JSON under its own key, so older saves are untouched; a missing save is an empty shelf. Shown in the Trophies sheet (Trophies/RaceTrophiesSection.swift)
//  and on the room's wall shelf (Trophies/TrophyShelfGeometry.swift), which fills itself from `roomShelf`.
//

import Foundation
import Observation

/// One trophy of the Circuit.
nonisolated struct Trophy: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var detail: String

    static func firstWin(_ t: CourseTier) -> Trophy { Trophy(id: "first.\(t.rawValue)", title: "\(t.title) winner", detail: "First win on \(t.title)") }
    static let wins5 = Trophy(id: "wins5", title: "5 wins", detail: "Won 5 races")
    static let wins10 = Trophy(id: "wins10", title: "10 wins", detail: "Won 10 races")
    static let wins25 = Trophy(id: "wins25", title: "25 wins", detail: "Won 25 races")
    static let champion = Trophy(id: "champion", title: "Champion", detail: "Won on every course")
    /// The win counts that earn a milestone trophy, in order.
    static let milestones: [(wins: Int, trophy: Trophy)] = [(5, wins5), (10, wins10), (25, wins25)]
    /// Every trophy, in the order the sheet shows them.
    static var all: [Trophy] { CourseTier.allCases.map(firstWin) + [wins5, wins10, wins25, champion] }
}

/// One Jelbie's ribbons and trophies.
nonisolated struct JelbieTrophies: Codable, Equatable, Sendable {
    /// Course tier raw value -> [1st, 2nd, 3rd] counts.
    var race: [String: [Int]] = [:]
    /// Trophy ids, in the order earned.
    var earned: [String] = []
    /// Beach volleyball match wins per tier (Volley/VolleyFlow.swift); optional so older saves decode.
    var volleyWins: [String: Int]? = nil
    var volleyTotal: Int { (volleyWins ?? [:]).values.reduce(0, +) }
    func volleyWon(_ t: VolleyTier) -> Int { volleyWins?[t.rawValue] ?? 0 }

    func raceRibbons(_ t: CourseTier) -> [Int] { padded(race[t.rawValue]) }
    private func padded(_ a: [Int]?) -> [Int] { var r = a ?? []; while r.count < 3 { r.append(0) }; return r }
    /// 1st places on the Circuit over every tier.
    var raceWins: Int { race.values.reduce(0) { $0 + ($1.first ?? 0) } }
    func has(_ t: Trophy) -> Bool { earned.contains(t.id) }
    /// The best place won on a tier (1...3), nil when none.
    func bestRace(_ t: CourseTier) -> Int? { raceRibbons(t).firstIndex { $0 > 0 }.map { $0 + 1 } }
    var raceRibbonCount: Int { race.values.reduce(0) { $0 + $1.reduce(0, +) } }
}

/// What one result earned: the ribbon (new, or one more of a kind he already has) and any trophies, for the results card.
nonisolated struct TrophyAwards: Equatable, Sendable {
    var place: Int?
    var newRibbon = false
    var trophies: [Trophy] = []
    var isEmpty: Bool { !newRibbon && trophies.isEmpty }
}

/// What the wall shelf shows (summed over every Jelbie): the best medal per course tier, the milestone trophies, the best contest ribbon.
nonisolated struct TrophyShelfSpec: Equatable, Sendable {
    /// Per CourseTier (in allCases order): 0 none, 1 gold, 2 silver, 3 bronze.
    var cups: [UInt8] = Array(repeating: 0, count: CourseTier.allCases.count)
    /// wins5, wins10, wins25, champion.
    var milestones: [Bool] = [false, false, false, false]
    /// The best Show placing (0 none).
    var contest: UInt8 = 0
    var isEmpty: Bool { cups.allSatisfy { $0 == 0 } && !milestones.contains(true) && contest == 0 }
}

@MainActor
@Observable
final class TrophyBook {
    private(set) var shelves: [String: JelbieTrophies] = [:]
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    static let key = "Circuit.trophies.v1"
    nonisolated deinit {}

    init(persists: Bool = false, defaults: UserDefaults = .standard) {
        self.persists = persists; self.defaults = defaults
        guard persists, let d = defaults.data(forKey: Self.key), let s = try? JSONDecoder().decode([String: JelbieTrophies].self, from: d) else { return }
        shelves = s
    }

    func shelf(character c: Int) -> JelbieTrophies { shelves["\(c)"] ?? JelbieTrophies() }
    func setShelf(_ s: JelbieTrophies, character c: Int) { shelves["\(c)"] = s; save() }

    /// A race on `tier` ended with Jelbie `character` in `place` (1...3 earn a ribbon; 1st also counts toward the trophies).
    @discardableResult
    func recordRace(character c: Int, tier: CourseTier, place: Int) -> TrophyAwards {
        var a = TrophyAwards(place: place <= 3 ? place : nil)
        guard place >= 1, place <= 3 else { return a }
        var s = shelf(character: c)
        var r = s.raceRibbons(tier)
        a.newRibbon = r[place - 1] == 0
        r[place - 1] += 1
        s.race[tier.rawValue] = r
        if place == 1 {
            func grant(_ t: Trophy) { if !s.has(t) { s.earned.append(t.id); a.trophies.append(t) } }
            grant(.firstWin(tier))
            for m in Trophy.milestones where s.raceWins >= m.wins { grant(m.trophy) }
            if CourseTier.allCases.allSatisfy({ s.raceRibbons($0)[0] > 0 }) { grant(.champion) }
        }
        shelves["\(c)"] = s
        save()
        return a
    }

    /// The wall shelf's contents over every Jelbie.
    func roomShelf(contestBest: Int) -> TrophyShelfSpec {
        var spec = TrophyShelfSpec()
        spec.contest = UInt8(min(max(contestBest, 0), 3))
        for s in shelves.values {
            for (k, t) in CourseTier.allCases.enumerated() {
                if let b = s.bestRace(t) { spec.cups[k] = spec.cups[k] == 0 ? UInt8(b) : min(spec.cups[k], UInt8(b)) }
            }
            for (k, t) in [Trophy.wins5, .wins10, .wins25, .champion].enumerated() where s.has(t) { spec.milestones[k] = true }
        }
        return spec
    }

    private func save() {
        guard persists, let d = try? JSONEncoder().encode(shelves) else { return }
        defaults.set(d, forKey: Self.key)
    }
}

extension ShowProgress {
    /// The best Show placing any Jelbie has a cup for (1 gold ... 3 bronze), 0 when none: the contest ribbon on the wall shelf.
    var bestCup: Int { saved.trophies.values.flatMap { $0.cups.values }.min() ?? 0 }
}
