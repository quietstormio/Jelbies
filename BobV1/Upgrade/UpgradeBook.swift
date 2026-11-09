//
//  UpgradeBook.swift
//  The Upgrade menu's model (Upgrade/UpgradeSheet.swift is the view): per game and per Jelbie CHARACTER, a balance of points to spend on skills and the one race-boost food
//  chosen as the power-up for the next race. Points come from placing in a game (Race: 3 / 2 / 1) and buy skill levels. A skill's level is DERIVED from the stored 0...1 stat
//  (JellyStats.waddle / .focus): level = floor(stat x 5) clamped to 1...5, and buying the next level lifts the stat to level/5 (never lowers it). Pure model, persisted
//  under its own key like the other per-Jelbie stores.
//

import Foundation
import Observation

nonisolated enum UpgradeGame: String, Codable, CaseIterable, Sendable {
    case race, volley
    /// "Race" / "Volleyball": the game word of the sheet.
    var word: String { self == .race ? "Race" : "Volleyball" }
}

nonisolated enum UpgradeTuning {
    static let defaultsKey = "UpgradeBook.v1"
    static let maxLevel = 5
    /// 1...5 from a 0...1 stat (a small epsilon so 0.4 / 0.6 / 0.8 land on their level in Float).
    static func level(stat: Float) -> Int { min(max(Int((min(max(stat, 0), 1) * Float(maxLevel) + 1e-4).rounded(.down)), 1), maxLevel) }
    /// Points for the NEXT level from `level` (nil at the top).
    static func cost(level: Int) -> Int? { level >= maxLevel ? nil : level + 1 }
    /// The stat a level stands for.
    static func stat(level: Int) -> Float { Float(min(max(level, 1), maxLevel)) / Float(maxLevel) }
    /// Race points by finishing place (1-based); 0 = no result (aborted) = nothing.
    static func racePoints(place: Int) -> Int { place <= 0 ? 0 : place == 1 ? 3 : place == 2 ? 2 : 1 }
    /// Volleyball points by result: a win 3, a close loss 2 (VolleySim.closeLoss), any other loss 1; nil = no result (abandoned) = nothing.
    static func volleyPoints(win: Bool?, closeLoss: Bool = false) -> Int {
        guard let win else { return 0 }
        return win ? 3 : (closeLoss ? 2 : 1)
    }
    /// The one-match bump a chosen volleyball power-up food gives to its stat (never saved; the stat stays clamped to 1).
    static let volleyBump: Float = 0.15
}

/// The four volleyball skills are the VolleyStatKind stats.
extension VolleyStatKind {
    var blurb: String {
        switch self {
        case .speed: return "Gets to the ball faster."
        case .power: return "Harder spikes and serves."
        case .hops: return "Jumps higher at the net."
        case .timing: return "Bigger Perfect window."
        }
    }
}

extension VolleyStats {
    func value(_ k: VolleyStatKind) -> Float {
        switch k { case .speed: return speed; case .power: return power; case .hops: return hops; case .timing: return timing }
    }
    mutating func setValue(_ k: VolleyStatKind, _ v: Float) {
        let c = min(max(v, 0), 1)
        switch k { case .speed: speed = c; case .power: power = c; case .hops: hops = c; case .timing: timing = c }
    }
    /// The stats for ONE match with a power-up food's perk on: zoomies = Speed, focus = Timing, +volleyBump, clamped to 1. A copy: nothing is saved.
    func boosted(by perk: PerkKind?) -> VolleyStats {
        var s = self
        switch perk {
        case .zoomies?: s.setValue(.speed, speed + UpgradeTuning.volleyBump)
        case .focus?: s.setValue(.timing, timing + UpgradeTuning.volleyBump)
        default: break
        }
        return s
    }
}

/// The two race skills.
nonisolated enum RaceSkill: String, CaseIterable, Sendable {
    case speed, focus
    var title: String { self == .speed ? "Speed" : "Focus" }
    var blurb: String { self == .speed ? "Longer, faster steps." : "Fewer stumbles on a double tap." }
}

/// The boost a race-boost food gives as a power-up (the same numbers the eaten perk gives): zoomies = stride / rate, focus = grace.
extension RaceBoost {
    static func powerUp(_ perk: PerkKind?) -> RaceBoost {
        switch perk {
        case .zoomies?: return RaceBoost(strideMul: 1 + PerkTuning.raceStride, rateMul: 1 + PerkTuning.raceRate, grace: 0)
        case .focus?: return RaceBoost(strideMul: 1, rateMul: 1, grace: PerkTuning.focusGrace)
        default: return .none
        }
    }
    /// Both at once without stacking: the larger of each part (the same perk twice is one boost).
    func merged(with o: RaceBoost) -> RaceBoost {
        RaceBoost(strideMul: max(strideMul, o.strideMul), rateMul: max(rateMul, o.rateMul), grace: max(grace, o.grace))
    }
}

@MainActor
@Observable
final class UpgradeBook {
    private struct Saved: Codable, Equatable {
        /// "<game>.<character>" -> points.
        var points: [String: Int] = [:]
        /// "<game>.<character>" -> chosen power-up item id.
        var chosen: [String: String] = [:]
    }
    private var saved = Saved()
    /// Bumped on every change (views read it).
    private(set) var revision = 0
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    nonisolated deinit {}

    init(persists: Bool = true, defaults: UserDefaults = .standard, key: String = UpgradeTuning.defaultsKey) {
        self.persists = persists; self.defaults = defaults; self.key = key
        if persists, let d = defaults.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: d) { saved = s }
        // Dev launch arg `-UpgradePoints N`: tops every game x character balance up to at least N (saved).
        if persists, DevArgs.enabled, let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-UpgradePoints"),
           i + 1 < ProcessInfo.processInfo.arguments.count, let n = Int(ProcessInfo.processInfo.arguments[i + 1]), n > 0 {
            for g in UpgradeGame.allCases { for c in 0..<32 { let key = k(g, c); saved.points[key] = max(saved.points[key] ?? 0, n) } }
            save()
        }
    }

    private func k(_ g: UpgradeGame, _ c: Int) -> String { "\(g.rawValue).\(c)" }
    private func save() {
        revision += 1
        guard persists, let d = try? JSONEncoder().encode(saved) else { return }
        defaults.set(d, forKey: key)
    }

    // MARK: points

    func points(_ g: UpgradeGame, character c: Int) -> Int { saved.points[k(g, c)] ?? 0 }
    func add(_ n: Int, _ g: UpgradeGame, character c: Int) {
        guard n > 0 else { return }
        saved.points[k(g, c), default: 0] += n; save()
    }
    @discardableResult
    func spend(_ n: Int, _ g: UpgradeGame, character c: Int) -> Bool {
        guard n >= 0, points(g, character: c) >= n else { return false }
        saved.points[k(g, c), default: 0] -= n; save()
        return true
    }

    // MARK: race skills

    /// The skill's current level, from the stat.
    func level(_ s: RaceSkill, stats: JellyStats) -> Int { UpgradeTuning.level(stat: s == .speed ? stats.waddle : stats.focus) }
    /// Buys the next level (cost = level + 1 points): the stat rises to that level's value (never lower); false when short or at the top.
    @discardableResult
    func buy(_ s: RaceSkill, stats: JellyStats, character c: Int) -> Bool {
        let lv = level(s, stats: stats)
        guard let cost = UpgradeTuning.cost(level: lv), spend(cost, .race, character: c) else { return false }
        let target = UpgradeTuning.stat(level: lv + 1)
        if s == .speed { stats.set(waddle: max(stats.waddle, target)) } else { stats.set(focus: max(stats.focus, target)) }
        return true
    }

    // MARK: volleyball skills

    func level(_ k: VolleyStatKind, stats: VolleyStats) -> Int { UpgradeTuning.level(stat: stats.value(k)) }
    /// Buys the next level of a volleyball skill for `character` (cost = level + 1 points): the saved stat rises to that level's value (never lower); false when short or at the top.
    @discardableResult
    func buy(_ k: VolleyStatKind, volley: VolleyBook, character c: Int) -> Bool {
        let lv = level(k, stats: volley.stats(character: c))
        guard let cost = UpgradeTuning.cost(level: lv), spend(cost, .volley, character: c) else { return false }
        volley.raise(k, to: UpgradeTuning.stat(level: lv + 1), character: c)
        return true
    }

    // MARK: power-up

    func chosen(_ g: UpgradeGame, character c: Int) -> String? { saved.chosen[k(g, c)] }
    func choose(_ item: String?, _ g: UpgradeGame, character c: Int) {
        if saved.chosen[k(g, c)] == item { return }
        saved.chosen[k(g, c)] = item; save()
    }
}
