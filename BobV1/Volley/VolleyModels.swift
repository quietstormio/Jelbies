//
//  VolleyModels.swift
//  Jelly Volleyball (the third earning game): the data. Tiers (ranks), the court's numbers, per-Jelbie volleyball stats (Speed, Power, Hops, Timing)
//  with their training gain rules, the tier unlocks, and the Drops. Pure values: no bodies, no screen.
//
//  The court is a side view along x: the net at x = 0, the player's team on the left (x < 0), two Jelbies a side, everybody on (or a step off) the plane z = 0.
//

import Foundation
import simd
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
    static let pointsToWin = 3               // rally scoring: first to 3, no win-by-2, no cap
    static let maxTouches = 3                // bump, set, spike
    static let pointPause: Float = 2.1
    static let serveWaitAI: Float = 1.1
    static let introSeconds: Float = 1.6
    // players
    static let restYaw: Float = 0.95             // 3/4 toward the camera, facing the net
    /// Two bodies on one side never come closer than this (centre to centre): a body is ~1.1 wide, plus a margin. `partnerGap` is how far apart two teammates' wishes are
    /// kept (the one nearer the ball keeps his spot, the other steps aside); `brainGap` is the least a step, jump or dive may end from the partner's body.
    static let bodyDiameter: Float = 1.1
    static let minCentreGap: Float = bodyDiameter + 0.5          // (the margin: a body's centre sways a little as it walks, and two steps can be taken at once)
    static let partnerGap: Float = bodyDiameter + 0.5, brainGap: Float = bodyDiameter + 0.5
    static let minGap: Float = 1.3              // teammates keep this far apart (the old wish-to-wish gap)
    /// A hook for the before / after measurements and captures: `-VolleyKeepApart 0` plays with the old rules (only the wishes of two computer teammates are pushed apart,
    /// and the bodies walk, jump and dive straight through each other).
    nonisolated(unsafe) static var keepApart: Bool = UserDefaults.standard.object(forKey: "VolleyKeepApart") == nil ? true : UserDefaults.standard.bool(forKey: "VolleyKeepApart")
    /// `q` (where a body is heading, from `p`) moved out to the circle of radius `brainGap` round the partner `m` when it is inside it (or a little more than his distance now, when
    /// he is closer already): the partner's body is a wall to walk, jump and dive round. `lane` (an x direction, away from the net) picks the way when everything is dead centre.
    static func clearOfMate(_ q: SIMD2<Float>, from p: SIMD2<Float>, mate m: SIMD2<Float>, lane: Float = 1) -> SIMD2<Float> {
        let d0 = simd_distance(p, m)
        let dmin = d0 < brainGap ? min(brainGap, d0 + 0.15) : brainGap          // (already too close: the move must open the gap, not keep it)
        guard simd_distance(q, m) < dmin else { return q }
        var out = q - m
        if simd_length(out) < 1e-3 { out = p - m }
        if simd_length(out) < 1e-3 { out = SIMD2(lane, 0) }
        return m + simd_normalize(out) * dmin
    }
    static let startX: [Float] = [-2.5, -1.1, 2.5, 1.1]
    static let startZ: [Float] = [0.35, -0.35, -0.35, 0.35]
    /// Depth: the players roam this far either side of the centre line; a ball landing past `outZ` is out; a body must be within `zReach` of the ball's depth to touch it.
    static let zLimit: Float = 1.15, outZ: Float = 1.75, zReach: Float = 0.78
    /// Timing: the Perfect and Good half windows (seconds, around the ideal tap) from the Timing stat; the wide ones are for assists.
    static func perfectWindow(timing: Float, wide: Bool) -> Float { (0.075 + 0.10 * clamp01(timing)) * (wide ? 1.8 : 1) }
    static func goodWindow(timing: Float, wide: Bool) -> Float { perfectWindow(timing: timing, wide: wide) + 0.14 * (wide ? 1.5 : 1) }
    /// The body block jumps a little higher than a plain hop.
    static func blockApex(hops: Float) -> Float { apex(hops: hops) * 1.05 + 0.04 }
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

    // payout: a win pays 250 / 400 / 550 / 750 by tier (top = 3x the first), a loss 75 / 120 / 165 / 225 (a loss pays only if the player played, see VolleyFlow.settle)
    static func drops(win: Bool, tier: VolleyTier) -> Int {
        let w = [250, 400, 550, 750], l = [75, 120, 165, 225]
        return win ? w[tier.index] : l[tier.index]
    }
}

/// One Jelbie's volleyball stats, 0...1.
nonisolated struct VolleyStats: Codable, Equatable, Sendable {
    var speed: Float = 0.35, power: Float = 0.35, hops: Float = 0.35, timing: Float = 0.30
    var sessions = 0, day = 0, daySessions = 0
    var matches = 0, wins = 0
    init(speed: Float = 0.35, power: Float = 0.35, hops: Float = 0.35, timing: Float = 0.30) { self.speed = speed; self.power = power; self.hops = hops; self.timing = timing }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speed = c.value(.speed, speed); power = c.value(.power, power); hops = c.value(.hops, hops); timing = c.value(.timing, timing)
        sessions = c.value(.sessions, 0); day = c.value(.day, 0); daySessions = c.value(.daySessions, 0); matches = c.value(.matches, 0); wins = c.value(.wins, 0)
    }
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
    static func diminishing(_ stat: Float) -> Float { powf(max(0, 1 - min(max(stat, 0), 1)), 1.5) }
}

nonisolated enum VolleyStatKind: String, CaseIterable, Sendable {
    case speed, power, hops, timing
    var title: String { rawValue.capitalized }
}

/// Wins, close losses and unlocks per tier (a win, or three close losses, opens the next tier; saved).
nonisolated struct VolleyRecord: Codable, Equatable, Sendable {
    var matches = 0, wins = 0, close = 0
    init(matches: Int = 0, wins: Int = 0, close: Int = 0) { self.matches = matches; self.wins = wins; self.close = close }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matches = c.value(.matches, 0); wins = c.value(.wins, 0); close = c.value(.close, 0)
    }
}

@MainActor
@Observable
final class VolleyBook {
    private(set) var stats: [String: VolleyStats] = [:]
    private(set) var records: [String: VolleyRecord] = [:]
    var chosen: VolleyTier = .sandcastle
    var slowBall = false { didSet { if persists { defaults.set(slowBall, forKey: "volley.slowBall") } } }
    /// When the ball crosses to your side, control jumps to the teammate nearer the landing spot (a double-tap always wins for 2 s). On by default.
    var autoSwitch = true { didSet { if persists { defaults.set(autoSwitch, forKey: "volley.autoSwitch") } } }
    /// The teammate chosen in the lobby, by CHARACTER (nil = the first other Jelbie). Used only while it still names a Jelbie in the room other than the player.
    var partner: Int? { didSet { if persists { if let p = partner { defaults.set(p, forKey: "volley.partner") } else { defaults.removeObject(forKey: "volley.partner") } } } }
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let dayKey: () -> Int
    static let key = "Volley.book.v1"
    nonisolated deinit {}

    private struct Saved: Codable {
        var stats: [String: VolleyStats]; var records: [String: VolleyRecord]; var chosen: VolleyTier
        init(stats: [String: VolleyStats], records: [String: VolleyRecord], chosen: VolleyTier) { self.stats = stats; self.records = records; self.chosen = chosen }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            stats = c.value(.stats, [:]); records = c.value(.records, [:]); chosen = c.value(.chosen, .sandcastle)
        }
    }

    init(persists: Bool = false, defaults: UserDefaults = .standard, dayKey: @escaping () -> Int = { MainActor.assumeIsolated { DayClock.shared.dayKey } }) {
        self.persists = persists; self.defaults = defaults; self.dayKey = dayKey
        guard persists else { return }
        slowBall = defaults.bool(forKey: "volley.slowBall")
        autoSwitch = defaults.object(forKey: "volley.autoSwitch") == nil ? true : defaults.bool(forKey: "volley.autoSwitch")
        partner = defaults.object(forKey: "volley.partner") == nil ? nil : defaults.integer(forKey: "volley.partner")
        if let s = SaveRecovery.decode(Saved.self, key: Self.key, defaults: defaults) { stats = s.stats; records = s.records; chosen = s.chosen }
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

    /// A match is over. Returns whether a new tier opened.
    @discardableResult
    func finishMatch(character c: Int, tier: VolleyTier, win: Bool, closeLoss: Bool) -> VolleyTier? {
        let before = Set(unlockedTiers)
        var r = record(tier)
        r.matches += 1
        if win { r.wins += 1 } else if closeLoss { r.close += 1 }
        records[tier.rawValue] = r
        var s = stats(character: c)          // (no stat creep: skills rise by spending Upgrade points, Upgrade/UpgradeBook.swift)
        s.matches += 1; if win { s.wins += 1 }
        stats["\(c)"] = s
        save()
        return unlockedTiers.first { !before.contains($0) }
    }

    /// Lifts one saved stat to `value` (never lowers it): the Upgrade menu's purchase.
    func raise(_ k: VolleyStatKind, to value: Float, character c: Int) {
        var s = stats(character: c)
        s.setValue(k, max(s.value(k), value))
        stats["\(c)"] = s
        save()
    }

    func save() {
        guard persists, let d = try? JSONEncoder().encode(Saved(stats: stats, records: records, chosen: chosen)) else { return }
        defaults.set(d, forKey: Self.key)
    }
}
