//
//  ShowProgress.swift
//  What the player has done at the Jelly Show: shows and placings per rank (the unlocks: a 1st at the rank below, or three top-two finishes), the
//  rank picked last, and each Jelbie's trophies (a cup per rank in bronze / silver / gold for the best placing, a rosette per theme stat for a 1st in
//  that theme, and a few stickers). Saved as JSON under NEW keys, so older saves are untouched; a missing save means nothing won yet.
//

import Foundation
import Observation

@MainActor
@Observable
final class ShowProgress {
    nonisolated struct Record: Codable, Equatable, Sendable {
        var shows = 0, wins = 0, topTwo = 0
        /// Best placing (0 = none yet).
        var best = 0
    }
    nonisolated struct Trophies: Codable, Equatable, Sendable {
        /// Rank -> best place (1 gold, 2 silver, 3 bronze).
        var cups: [String: Int] = [:]
        /// Theme stats (WearTag raw values) won with a 1st.
        var rosettes: [String] = []
        var stickers: [String] = []
        var shows = 0
        var cupCount: Int { cups.count }
        func cup(_ r: ShowRank) -> Int? { cups[r.rawValue] }
        func hasRosette(_ t: WearTag) -> Bool { rosettes.contains(t.rawValue) }
    }
    nonisolated struct Saved: Codable {
        var records: [String: Record] = [:]
        var chosen: String = ShowRank.puddle.rawValue
        /// Character id -> trophies.
        var trophies: [String: Trophies] = [:]
    }
    nonisolated enum Sticker: String, CaseIterable, Sendable {
        case firstShow, perfectDance, glowBurst, hatTrick
        var title: String {
            switch self { case .firstShow: return "First Show"; case .perfectDance: return "Perfect Dance"; case .glowBurst: return "Glow Burst"; case .hatTrick: return "Hat-trick" }
        }
    }

    private(set) var saved = Saved()
    /// The rank picked last (kept if it is open).
    var chosen: ShowRank {
        get { ShowRank(rawValue: saved.chosen).flatMap { unlocked($0) ? $0 : nil } ?? .puddle }
        set { if unlocked(newValue) { saved.chosen = newValue.rawValue; save() } }
    }
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storeKey: String
    static let key = "JellyShow.progress.v1"
    static let topTwoToUnlock = 3
    nonisolated deinit {}

    init(persists: Bool = false, defaults: UserDefaults = .standard, key: String = ShowProgress.key) {
        self.persists = persists; self.defaults = defaults; storeKey = key
        guard persists, let d = defaults.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: d) else { return }
        saved = s
    }

    func record(_ r: ShowRank) -> Record { saved.records[r.rawValue] ?? Record() }
    func trophies(character c: Int) -> Trophies { saved.trophies["\(c)"] ?? Trophies() }
    var totalShows: Int { saved.records.values.reduce(0) { $0 + $1.shows } }
    /// The player has never entered a show (the rivals go easy).
    var firstShowEver: Bool { totalShows == 0 }

    /// Open: the Puddle always; each other rank once the one below has a 1st, or three top-two finishes.
    func unlocked(_ r: ShowRank) -> Bool {
        guard let below = r.below else { return true }
        let rec = record(below)
        return rec.wins >= 1 || rec.topTwo >= Self.topTwoToUnlock
    }
    var unlockedRanks: [ShowRank] { ShowRank.allCases.filter { unlocked($0) } }
    /// In words, what opens `r` (nil when it is open).
    func requirement(_ r: ShowRank) -> String? {
        guard !unlocked(r), let below = r.below else { return nil }
        let left = Self.topTwoToUnlock - record(below).topTwo
        return "Win a 1st at \(below.title), or finish top two \(left) more time\(left == 1 ? "" : "s")"
    }

    /// What a finished show earned besides Drops.
    nonisolated struct Awards: Equatable, Sendable {
        /// A new (or better) cup for the rank: its place.
        var cup: Int?
        var rosette: WearTag?
        var stickers: [Sticker] = []
        var unlocked: ShowRank?
    }

    /// A show at `rank` ended with the player's Jelbie (`character`) in `place`. Returns what is new.
    @discardableResult
    func record(rank: ShowRank, place: Int, theme: ShowTheme, character: Int, burst: Bool, perfectDance: Bool, hatTrick: Bool) -> Awards {
        let open = unlockedRanks
        var a = Awards()
        var rec = record(rank)
        rec.shows += 1
        if place == 1 { rec.wins += 1 }
        if place <= 2 { rec.topTwo += 1 }
        if rec.best == 0 || place < rec.best { rec.best = place }
        saved.records[rank.rawValue] = rec
        var t = trophies(character: character)
        if t.shows == 0, totalShows >= 1 { a.stickers.append(.firstShow); t.stickers.append(Sticker.firstShow.rawValue) }
        t.shows += 1
        if place <= 3, (t.cups[rank.rawValue] ?? 9) > place { t.cups[rank.rawValue] = place; a.cup = place }
        if place == 1, !t.rosettes.contains(theme.main.rawValue) { t.rosettes.append(theme.main.rawValue); a.rosette = theme.main }
        for (on, s) in [(burst, Sticker.glowBurst), (perfectDance, .perfectDance), (hatTrick, .hatTrick)] where on && !t.stickers.contains(s.rawValue) {
            t.stickers.append(s.rawValue); a.stickers.append(s)
        }
        saved.trophies["\(character)"] = t
        a.unlocked = unlockedRanks.first { !open.contains($0) }
        save()
        return a
    }

    private func save() {
        guard persists, let d = try? JSONEncoder().encode(saved) else { return }
        defaults.set(d, forKey: storeKey)
    }
}
