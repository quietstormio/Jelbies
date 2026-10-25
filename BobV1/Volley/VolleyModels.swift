//
//  VolleyModels.swift
//  Jelly Volleyball (the third earning game): the data. Tiers (ranks), the court's numbers, per-Jelbie volleyball stats (Speed, Power, Hops, Timing)
//  with their training gain rules, the tier unlocks, and the Drops. Pure values: no bodies, no screen.
//
//  The court is a side view along x: the net at x = 0, the player's team on the left (x < 0), two Jelbies a side, everybody on the plane z = 0.
//

import Foundation
import Observation

nonisolated enum VolleyTier: String, CaseIterable, Codable, Sendable {
    case sandcastle, shore, reef, tidal
    var title: String { switch self { case .sandcastle: return "Sandcastle"; case .shore: return "Shore"; case .reef: return "Reef"; case .tidal: return "Tidal" } }
    var className: String { switch self { case .sandcastle: return "Starter"; case .shore: return "Rookie"; case .reef: return "Pro"; case .tidal: return "Champion" } }
    var blurb: String {
        switch self {
        case .sandcastle: return "Easygoing visitors. Learn the bonk."
        case .shore: return "Quicker feet, sneakier hits."
        case .reef: return "They dig everything. Spike it down."
        case .tidal: return "The big wave. They almost never miss."
        }
    }
    var index: Int { VolleyTier.allCases.firstIndex(of: self) ?? 0 }
    var below: VolleyTier? { index > 0 ? VolleyTier.allCases[index - 1] : nil }
    /// How good the computer team is (0...1): feeds their stats and their mistakes.
    var skill: Float { [0.20, 0.45, 0.70, 0.92][index] }
}

nonisolated enum VolleyTuning {
    // court (world units; a Jelbie is ~1.35 tall and ~1.1 wide)
    static let halfCourt: Float = 2.7            // the side lines / back lines
    static let outLine: Float = 3.15             // a ball landing past this is out
    static let netTop: Float = 1.45
    /// The nearest a body's centre may come to the net plane (the half width of the body plus a margin), and the two zones: back and front.
    static let netMargin: Float = 0.9
    static let backX: Float = 2.5, frontX: Float = 1.1
    static let netDepth: Float = 1.5             // the net runs from z = -netDepth to +netDepth
    static let ballR: Float = 0.34
    static let gravity: Float = 2.7              // floaty
    static let drag: Float = 0.10
    static let ballZ: Float = 0.06
    static let bodyTop: Float = 1.35             // a resting Jelbie's crown
    // match
    static let pointsToWin = 7
    static let pointPause: Float = 2.1
    static let serveWaitAI: Float = 1.1
    static let introSeconds: Float = 1.6
    // players
    static let restYaw: Float = 0.95             // 3/4 toward the camera, facing the net
    static let minGap: Float = 1.3              // teammates keep this far apart
    static let startX: [Float] = [-2.5, -1.1, 2.5, 1.1]
    // movement: speed comes from step rate and stride, like racing (RaceTuning)
    static func stride(speed: Float) -> Float { 0.27 + 0.05 * clamp01(speed) }
    static func rate(speed: Float) -> Float { 3.0 + 1.2 * clamp01(speed) }
    static func walkSpeed(speed: Float) -> Float { stride(speed: speed) * rate(speed: speed) }
    // jumps
    static func apex(hops: Float) -> Float { 0.46 + 0.34 * clamp01(hops) }
    static let jumpGravity: Float = 7.0
    static func airTime(apex: Float) -> Float { 2 * (2 * apex / jumpGravity).squareRoot() }
    static let crouch: Float = 0.13
    static let diveReach: Float = 1.25
    // hits
    static func flightTime(power: Float, over: Bool) -> Float { over ? 1.75 - 0.5 * clamp01(power) : 1.8 }
    static func spikeTime(power: Float) -> Float { 0.95 - 0.40 * clamp01(power) }
    /// Aim error (u) of a hit: the timing stat tightens the human's; computer teams use the tier skill.
    static func aimError(timing: Float) -> Float { 0.55 * (1 - clamp01(timing)) + 0.06 }
    static func contactPad(timing: Float) -> Float { 0.02 + 0.10 * clamp01(timing) }

    static func clamp01(_ v: Float) -> Float { min(max(v, 0), 1) }

    // payout: a win pays like a race 1st, a loss like 3rd (RaceTuning.drops); tiers pay more
    static func drops(win: Bool, tier: VolleyTier) -> Int {
        let w = [12, 15, 19, 24], l = [3, 4, 5, 6]
        return win ? w[tier.index] : l[tier.index]
    }
}

/// One Jelbie's volleyball stats, 0...1.
nonisolated struct VolleyStats: Codable, Equatable, Sendable {
    var speed: Float = 0.35, power: Float = 0.35, hops: Float = 0.35, timing: Float = 0.30
    var sessions = 0, day = 0, daySessions = 0
    var matches = 0, wins = 0
    static func avg(_ a: VolleyStats, _ b: VolleyStats) -> VolleyStats {
        VolleyStats(speed: (a.speed + b.speed) / 2, power: (a.power + b.power) / 2, hops: (a.hops + b.hops) / 2, timing: (a.timing + b.timing) / 2)
    }
    /// The computer team of a tier.
    static func team(_ t: VolleyTier) -> VolleyStats {
        let s = t.skill
        return VolleyStats(speed: 0.15 + 0.7 * s, power: 0.2 + 0.6 * s, hops: 0.2 + 0.6 * s, timing: 0.2 + 0.7 * s)
    }
}

nonisolated enum VolleyTraining {
    static let baseGain: Float = 0.12
    static let fullSessions = 3
    static let spentFactor: Float = 0.25
    static func diminishing(_ stat: Float) -> Float { powf(max(0, 1 - min(max(stat, 0), 1)), 1.5) }
    static func fatigue(sessionsToday: Int) -> Float { sessionsToday < fullSessions ? 1 : spentFactor }
    static func gain(stat: Float, accuracy: Float, sessionsToday: Int, share: Float = 1) -> Float {
        baseGain * share * min(max(accuracy, 0), 1) * diminishing(stat) * fatigue(sessionsToday: sessionsToday)
    }
    /// A match nudges every stat a little (a win more).
    static func matchGain(win: Bool) -> Float { win ? 0.02 : 0.01 }
}

nonisolated enum VolleyDrillKind: String, CaseIterable, Sendable {
    case bonk, spike, sprint
    var title: String { switch self { case .bonk: return "Bonk practice"; case .spike: return "Spike targets"; case .sprint: return "Sand sprints" } }
    var blurb: String {
        switch self {
        case .bonk: return "Keep the ball up. Raises Hops and Timing."
        case .spike: return "Spike the ball onto the cushions. Raises Power."
        case .sprint: return "Dash to the flags. Raises Speed."
        }
    }
    var symbol: String { switch self { case .bonk: return "circle.dotted"; case .spike: return "arrow.down.right.circle.fill"; case .sprint: return "figure.run" } }
}

/// Wins, close losses and unlocks per tier (a win, or three close losses, opens the next tier; saved).
nonisolated struct VolleyRecord: Codable, Equatable, Sendable { var matches = 0, wins = 0, close = 0 }

@MainActor
@Observable
final class VolleyBook {
    private(set) var stats: [String: VolleyStats] = [:]
    private(set) var records: [String: VolleyRecord] = [:]
    var chosen: VolleyTier = .sandcastle
    var slowBall = false { didSet { if persists { defaults.set(slowBall, forKey: "volley.slowBall") } } }
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let dayKey: () -> Int
    static let key = "Volley.book.v1"
    nonisolated deinit {}

    private struct Saved: Codable { var stats: [String: VolleyStats]; var records: [String: VolleyRecord]; var chosen: VolleyTier }

    init(persists: Bool = false, defaults: UserDefaults = .standard, dayKey: @escaping () -> Int = { MainActor.assumeIsolated { DayClock.shared.dayKey } }) {
        self.persists = persists; self.defaults = defaults; self.dayKey = dayKey
        guard persists else { return }
        slowBall = defaults.bool(forKey: "volley.slowBall")
        if let d = defaults.data(forKey: Self.key), let s = try? JSONDecoder().decode(Saved.self, from: d) { stats = s.stats; records = s.records; chosen = s.chosen }
    }

    func stats(character c: Int) -> VolleyStats {
        var s = stats["\(c)"] ?? VolleyStats()
        if s.day != dayKey() { s.day = dayKey(); s.daySessions = 0 }
        return s
    }
    func record(_ t: VolleyTier) -> VolleyRecord { records[t.rawValue] ?? VolleyRecord() }
    func unlocked(_ t: VolleyTier) -> Bool {
        guard let b = t.below else { return true }
        let r = record(b)
        return r.wins >= 1 || r.close >= 3
    }
    var unlockedTiers: [VolleyTier] { VolleyTier.allCases.filter(unlocked) }
    func sessionsLeft(_ c: Int) -> Int { max(0, VolleyTraining.fullSessions - stats(character: c).daySessions) }

    /// A drill is over: the gains by accuracy (returns what was added: speed, power, hops, timing).
    @discardableResult
    func finishDrill(character c: Int, kind: VolleyDrillKind, accuracy: Float, factor: Float = 1) -> VolleyStats {
        var s = stats(character: c)
        let n = s.daySessions
        var d = VolleyStats(speed: 0, power: 0, hops: 0, timing: 0)
        switch kind {
        case .bonk:
            d.hops = VolleyTraining.gain(stat: s.hops, accuracy: accuracy, sessionsToday: n, share: 0.7) * factor
            d.timing = VolleyTraining.gain(stat: s.timing, accuracy: accuracy, sessionsToday: n, share: 1.0) * factor
        case .spike: d.power = VolleyTraining.gain(stat: s.power, accuracy: accuracy, sessionsToday: n) * factor
        case .sprint: d.speed = VolleyTraining.gain(stat: s.speed, accuracy: accuracy, sessionsToday: n) * factor
        }
        s.speed = min(1, s.speed + d.speed); s.power = min(1, s.power + d.power); s.hops = min(1, s.hops + d.hops); s.timing = min(1, s.timing + d.timing)
        s.daySessions += 1; s.sessions += 1
        stats["\(c)"] = s
        save()
        return d
    }

    /// A match is over. Returns whether a new tier opened.
    @discardableResult
    func finishMatch(character c: Int, tier: VolleyTier, win: Bool, closeLoss: Bool) -> VolleyTier? {
        let before = Set(unlockedTiers)
        var r = record(tier)
        r.matches += 1
        if win { r.wins += 1 } else if closeLoss { r.close += 1 }
        records[tier.rawValue] = r
        var s = stats(character: c)
        let g = VolleyTraining.matchGain(win: win)
        s.speed = min(1, s.speed + g * VolleyTraining.diminishing(s.speed)); s.power = min(1, s.power + g * VolleyTraining.diminishing(s.power))
        s.hops = min(1, s.hops + g * VolleyTraining.diminishing(s.hops)); s.timing = min(1, s.timing + g * VolleyTraining.diminishing(s.timing))
        s.matches += 1; if win { s.wins += 1 }
        stats["\(c)"] = s
        save()
        return unlockedTiers.first { !before.contains($0) }
    }

    func save() {
        guard persists, let d = try? JSONEncoder().encode(Saved(stats: stats, records: records, chosen: chosen)) else { return }
        defaults.set(d, forKey: Self.key)
    }
}
