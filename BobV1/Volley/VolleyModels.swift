//
//  VolleyModels.swift
//  Jelly Volleyball (the third earning game): the data. Tiers (ranks), the court's numbers, per-Jelbie volleyball stats (Speed, Power, Hops, Timing)
//  with their training gain rules, the tier unlocks, and the Drops. Pure values: no bodies, no screen.
//
//  The court runs along x: the net at x = 0, the player's team at x < 0, two Jelbies a side. The camera stands behind the player's baseline looking down the court,
//  so on the screen up = +x (toward the net and the opponents) and right = +z.
//

import Foundation
import simd
import CoreGraphics
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
    static let pointsToWin = 11              // rally scoring to 11, win by 2, capped at 15
    static let winBy = 2, scoreCap = 15
    static let maxTouches = 3                // bump, set, spike
    static let pointPause: Float = 2.1
    static let serveWaitAI: Float = 1.1
    static let introSeconds: Float = 1.6
    // players
    static let restYaw: Float = .pi / 2          // facing the net (your team: backs to the camera; the opponents: facing it)
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
    /// he is closer already): the partner's body is a wall to walk, jump and dive round. `lane` picks the side when everything is dead centre.
    static func clearOfMate(_ q: SIMD2<Float>, from p: SIMD2<Float>, mate m: SIMD2<Float>, lane: Float = 1) -> SIMD2<Float> {
        let d0 = simd_distance(p, m)
        let dmin = d0 < brainGap ? min(brainGap, d0 + 0.15) : brainGap          // (already too close: the move must open the gap, not keep it)
        guard simd_distance(q, m) < dmin else { return q }
        var out = q - m
        if simd_length(out) < 1e-3 { out = p - m }
        if simd_length(out) < 1e-3 { out = SIMD2(0, lane) }
        return m + simd_normalize(out) * dmin
    }
    static let startX: [Float] = [-2.5, -1.1, 2.5, 1.1]
    static let startZ: [Float] = [0.9, -0.9, -0.9, 0.9]          // (staggered across the court so the partner does not hide behind him from behind)
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

    // payout: a win pays like a race 1st, a loss like 3rd (RaceTuning.drops); tiers pay more
    static func drops(win: Bool, tier: VolleyTier) -> Int {
        let w = [16, 20, 25, 31], l = [4, 5, 6, 8]          // (v2: about 30% more for the longer match)
        return win ? w[tier.index] : l[tier.index]
    }
}

/// The screen <-> court mapping of the behind-the-team camera: up is +x (toward the net), right is +z. A thumb's offset (right, down; points or unit values) becomes the
/// sim's stick (x along the court, z across it) and the Hit-button swipe becomes the sim's aim (x: -1 short ... +1 deep, z across).
nonisolated enum VolleyView {
    static func stick(right: Float, down: Float) -> SIMD2<Float> { SIMD2(-down, right) }
    static func aim(right: Float, down: Float) -> SIMD2<Float> { SIMD2(-down, right) }

    /// How much of the smaller of two Jelbies' screen boxes the other one covers (0...1), through the beach camera of a view of `size`; nil when one is off the screen.
    /// A box wraps the body's footprint (a disc of radius 0.55 on the sand) and its crown (the height `p.y`): from this high up the body's depth shows as screen height.
    static func overlap(_ a: SIMD3<Float>, _ b: SIMD3<Float>, size: CGSize) -> Float? {
        func box(_ p: SIMD3<Float>) -> CGRect? {
            var pts: [CGPoint] = []
            for (dx, dz, y) in [(-0.55 as Float, 0 as Float, 0 as Float), (0.55, 0, 0), (0, -0.55, 0), (0, 0.55, 0), (0, 0, max(p.y, 0.5))] {
                guard let q = GameCamera.screenPoint(floor: SIMD2(p.x + dx, p.z + dz), y: y, size: size) else { return nil }
                pts.append(q)
            }
            let xs = pts.map(\.x), ys = pts.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        guard let ra = box(a), let rb = box(b) else { return nil }
        let i = ra.intersection(rb)
        guard !i.isNull else { return 0 }
        return Float(i.width * i.height / max(1, min(ra.width * ra.height, rb.width * rb.height)))
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

nonisolated enum VolleyStatKind: String, CaseIterable, Sendable {
    case speed, power, hops, timing
    var title: String { rawValue.capitalized }
}

nonisolated enum VolleyDrillKind: String, CaseIterable, Sendable {
    case bonk, spike, block, sprint
    var title: String { switch self { case .bonk: return "Bump & Set"; case .spike: return "Spike targets"; case .block: return "Block wall"; case .sprint: return "Sand sprints" } }
    var blurb: String {
        switch self {
        case .bonk: return "Bump, set, bump... keep it up with Perfect timing. Raises Timing and Hops."
        case .spike: return "Swipe the Hit button to aim the spike at the pink cushion. Raises Power."
        case .block: return "Jump at the net to block their spikes. Raises Hops."
        case .sprint: return "Dash to the flags with the stick. Raises Speed."
        }
    }
    /// The stats a drill raises (see `VolleyBook.finishDrill`), for the tags on the Training sheet.
    var raises: [VolleyStatKind] { switch self { case .bonk: return [.timing, .hops]; case .spike: return [.power]; case .block: return [.hops]; case .sprint: return [.speed] } }
    var symbol: String { switch self { case .bonk: return "circle.dotted"; case .spike: return "arrow.down.right.circle.fill"; case .block: return "rectangle.portrait.arrowtriangle.2.outward"; case .sprint: return "figure.run" } }
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
    /// When the ball crosses to your side, control jumps to the teammate nearer the landing spot (a double-tap always wins for 2 s). On by default.
    var autoSwitch = true { didSet { if persists { defaults.set(autoSwitch, forKey: "volley.autoSwitch") } } }
    /// The teammate chosen in the lobby, by CHARACTER (nil = the first other Jelbie). Used only while it still names a Jelbie in the room other than the player.
    var partner: Int? { didSet { if persists { if let p = partner { defaults.set(p, forKey: "volley.partner") } else { defaults.removeObject(forKey: "volley.partner") } } } }
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
        autoSwitch = defaults.object(forKey: "volley.autoSwitch") == nil ? true : defaults.bool(forKey: "volley.autoSwitch")
        partner = defaults.object(forKey: "volley.partner") as? Int
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
        case .block: d.hops = VolleyTraining.gain(stat: s.hops, accuracy: accuracy, sessionsToday: n) * factor
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
