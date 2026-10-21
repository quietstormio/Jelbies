//
//  RaceCourse.swift
//  Jelly Circuit courses: a course is a list of segments (a straight, a turn of some radius and angle, a bump) laid end to end from the start
//  line. A racer's place on it is an ARC LENGTH along the centreline; the course turns that into a world position and a heading for each of
//  the three lanes (the lanes are offsets to the right of the centreline; the player's lane 1 IS the centreline). Every course turns as much
//  left as right, so all three lanes are the same length and the finish faces the way the start does.
//
//    CourseTier       Puddle (the straight), Ripple (gentle curves), Splash (S-bends and soft bumps), Wave (tight turns and hairpins).
//    RaceCourse       the geometry: pose(at:), lanePoint, progress (the inverse: world -> arc length), the turn / bump at an arc length.
//    CourseTuning     the corner rule: a safe speed per turn (by radius and skill); above it the trip chance rises; bumps add a small one.
//    CourseProgress   what the player has won on each tier: the unlocks (1st on the tier below, or three top-two finishes).
//
//  Puddle is exactly the race before courses existed: one straight along +z from RaceTuning.startZ, no trig in its lookups, no corner draws.
//

import Foundation
import simd

// MARK: - segments and geometry

nonisolated enum CourseSegment: Equatable, Sendable {
    case straight(Float)
    /// `angle` in radians; positive turns RIGHT (toward +x when heading +z).
    case turn(radius: Float, angle: Float)
    /// A straight with a soft hump in it: a small trip chance unless Focus is high.
    case bump(Float)

    var length: Float {
        switch self {
        case .straight(let l), .bump(let l): return l
        case .turn(let r, let a): return r * abs(a)
        }
    }
    var isTurn: Bool { if case .turn = self { return true }; return false }
    var isBump: Bool { if case .bump = self { return true }; return false }
}

nonisolated struct CoursePose: Equatable, Sendable {
    var pos: SIMD2<Float>
    /// World yaw: 0 = toward +z (the Puddle's camera), growing toward +x.
    var heading: Float
    /// Signed 1 / radius, positive in a right turn; 0 on a straight.
    var curvature: Float
}

nonisolated struct RaceCourse: Equatable, Sendable {
    let tier: CourseTier
    let segments: [CourseSegment]
    let start: SIMD2<Float>
    let startHeading: Float
    /// Pose at the start of each segment, and the arc length there.
    private let heads: [CoursePose]
    private let cum: [Float]
    let length: Float

    init(tier: CourseTier, segments: [CourseSegment], start: SIMD2<Float> = SIMD2(0, RaceTuning.startZ), heading: Float = 0) {
        self.tier = tier; self.segments = segments; self.start = start; self.startHeading = heading
        var hs: [CoursePose] = [], cs: [Float] = []
        var p = CoursePose(pos: start, heading: heading, curvature: 0), s: Float = 0
        for seg in segments {
            hs.append(p); cs.append(s)
            p = Self.advance(p, seg, by: seg.length)
            s += seg.length
        }
        heads = hs; cum = cs; length = s
    }

    /// The forward and right unit vectors of a heading.
    static func forward(_ h: Float) -> SIMD2<Float> { SIMD2(sinf(h), cosf(h)) }
    static func right(_ h: Float) -> SIMD2<Float> { SIMD2(cosf(h), -sinf(h)) }

    /// The pose `d` along `seg` from its head `p0` (d may run past either end: straights extrapolate, turns keep turning).
    private static func advance(_ p0: CoursePose, _ seg: CourseSegment, by d: Float) -> CoursePose {
        switch seg {
        case .straight, .bump:
            return CoursePose(pos: p0.pos + forward(p0.heading) * d, heading: p0.heading, curvature: 0)
        case .turn(let r, let a):
            let sgn: Float = a >= 0 ? 1 : -1
            let c = p0.pos + right(p0.heading) * (r * sgn)
            let h = p0.heading + sgn * (d / r)
            return CoursePose(pos: c - right(h) * (r * sgn), heading: h, curvature: sgn / r)
        }
    }

    /// The segment index holding arc length `s` (the first before 0, the last past the end).
    func segmentIndex(at s: Float) -> Int {
        var i = 0
        while i + 1 < segments.count, s >= cum[i + 1] { i += 1 }
        return i
    }

    /// Centreline pose at arc length `s`. Before the start line / past the finish the end straights continue (the body stands behind the line, coasts past it).
    func pose(at s: Float) -> CoursePose {
        guard !segments.isEmpty else { return CoursePose(pos: start, heading: startHeading, curvature: 0) }
        let i = segmentIndex(at: s)
        var seg = segments[i]
        if case .turn = seg, s < cum[i] || s > cum[i] + seg.length { seg = .straight(0) }      // a turn does not continue past its ends
        let p = Self.advance(heads[i], seg, by: s - cum[i])
        return i == segments.count - 1 && s > length ? CoursePose(pos: p.pos, heading: p.heading, curvature: 0) : p
    }

    /// Offset of lane `i` to the right of the centreline (lane 1 is the centreline, as the Puddle's laneX).
    static func laneOffset(_ lane: Int) -> Float { RaceTuning.laneX(lane) }

    /// World point of lane `lane` at arc length `s`.
    func lanePoint(_ lane: Int, at s: Float) -> SIMD2<Float> {
        let p = pose(at: s)
        return p.pos + Self.right(p.heading) * Self.laneOffset(lane)
    }

    /// The inverse: the arc length whose lane point is nearest `p` on lane `lane`. `near` (the last known arc length) breaks ties where a course
    /// folds back on itself. On a single straight this is exactly the dot product along it (no clamp), as the Puddle's pz - startZ was.
    func progress(of p: SIMD2<Float>, lane: Int, near: Float?) -> Float {
        guard segments.count > 1 else {
            let h = heads.first ?? CoursePose(pos: start, heading: startHeading, curvature: 0)
            return simd_dot(p - (h.pos + Self.right(h.heading) * Self.laneOffset(lane)), Self.forward(h.heading))
        }
        let off = Self.laneOffset(lane)
        var best: Float = 0, bestScore = Float.infinity
        for (i, seg) in segments.enumerated() {
            let h = heads[i]
            var sLocal: Float, d: Float
            switch seg {
            case .straight, .bump:
                let a = h.pos + Self.right(h.heading) * off, u = Self.forward(h.heading)
                var t = simd_dot(p - a, u)
                if i > 0 { t = max(t, 0) }
                if i < segments.count - 1 { t = min(t, seg.length) }
                sLocal = t
                d = simd_length(p - (a + u * t))
            case .turn(let r, let ang):
                let sgn: Float = ang >= 0 ? 1 : -1
                let c = h.pos + Self.right(h.heading) * (r * sgn)
                let rl = r - sgn * off                                      // the lane's own radius
                let v = p - c
                // the angle turned from the segment head: the lane point at angle t is c - right(h0 + sgn t) * (r sgn)
                let v0 = -Self.right(h.heading) * sgn
                let ang0 = atan2f(v0.x, v0.y)                                  // (x, z) -> yaw-style angle
                var t = (atan2f(v.x, v.y) - ang0) * sgn
                t = t - (2 * .pi) * floorf((t + .pi) / (2 * .pi))              // wrap to (-pi, pi]
                t = min(max(t, 0), abs(ang))
                sLocal = t * r
                let hh = h.heading + sgn * t
                d = simd_length(p - (c - Self.right(hh) * (r * sgn) + Self.right(hh) * off))
                _ = rl
            }
            var score = d
            if let n = near { score += max(0, abs(cum[i] + sLocal - n) - 3) * 0.5 }      // far from where he was: only if nothing else is near
            if score < bestScore { bestScore = score; best = cum[i] + sLocal }
        }
        return best
    }

    /// Lateral offset of `p` from lane `lane` at arc length `s` (positive = to the right of the lane's line).
    func lateral(of p: SIMD2<Float>, lane: Int, at s: Float) -> Float {
        let q = pose(at: s)
        return simd_dot(p - (q.pos + Self.right(q.heading) * Self.laneOffset(lane)), Self.right(q.heading))
    }

    /// The turn at arc length `s`: its radius, or nil on a straight / bump.
    func turnRadius(at s: Float) -> Float? {
        guard s >= 0, s <= length, !segments.isEmpty else { return nil }
        if case .turn(let r, _) = segments[segmentIndex(at: s)] { return r }
        return nil
    }
    /// Signed curvature at `s` (+ right).
    func curvature(at s: Float) -> Float { pose(at: s).curvature }
    func inBump(at s: Float) -> Bool {
        guard s >= 0, s <= length, !segments.isEmpty else { return false }
        return segments[segmentIndex(at: s)].isBump
    }
    /// The nearest turn ahead of `s` (within `ahead`): its radius and how far to it (0 = in it).
    func turnAhead(of s: Float, within ahead: Float) -> (radius: Float, distance: Float)? {
        guard !segments.isEmpty else { return nil }
        var i = segmentIndex(at: max(s, 0))
        while i < segments.count, cum[i] <= s + ahead {
            if case .turn(let r, _) = segments[i], cum[i] + segments[i].length > s { return (r, max(0, cum[i] - s)) }
            i += 1
        }
        return nil
    }

    var isStraight: Bool { !segments.contains { $0.isTurn } }
    var hasBumps: Bool { segments.contains { $0.isBump } }
    /// The total signed turn (rad, + right) over the course: 0 when it turns as much left as right.
    var netTurn: Float {
        var t: Float = 0
        for seg in segments { if case .turn(_, let a) = seg { t += a } }
        return t
    }
    /// The lane's length (equal to the centreline's when the course turns as much left as right: a right lane is shorter through right turns).
    func laneLength(_ lane: Int) -> Float { length - Self.laneOffset(lane) * netTurn }

    /// Points along a lane (or the centreline) from `from` to `to`, every `step`.
    func polyline(lane: Int = 1, from: Float = 0, to: Float? = nil, step: Float = 0.25) -> [SIMD2<Float>] {
        let end = to ?? length
        var out: [SIMD2<Float>] = [], s = from
        while s < end { out.append(lanePoint(lane, at: s)); s += step }
        out.append(lanePoint(lane, at: end))
        return out
    }
    /// Bounding box of the track (the centreline widened by the clay strip).
    func bounds(margin: Float = RaceModels.trackHalfW) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        var lo = SIMD2<Float>(.infinity, .infinity), hi = -lo
        for p in polyline(step: 0.5) { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return (lo - SIMD2(repeating: margin), hi + SIMD2(repeating: margin))
    }

    /// The race is called off this long after GO (RaceTuning.timeout on the Puddle; longer courses get longer).
    var timeout: Float { tier == .puddle ? RaceTuning.timeout : max(RaceTuning.timeout, length / 0.55 + 12) }

    // MARK: the courses

    /// A straight of `length` from `from` facing `heading` (the Puddle, and a body's own lane in tests).
    static func straight(from: SIMD2<Float>, heading: Float, length: Float) -> RaceCourse {
        RaceCourse(tier: .puddle, segments: [.straight(length)], start: from, heading: heading)
    }

    /// The Puddle: the race before courses existed, one straight along +z from the start line to the finish.
    static let puddle = RaceCourse(tier: .puddle, segments: [.straight(RaceTuning.length)])

    static func deg(_ d: Float) -> Float { d * .pi / 180 }

    /// Ripple: two gentle curves, one each way (about 24 u: ~25 s at an average waddle).
    static let ripple = RaceCourse(tier: .ripple, segments: [.straight(4), .turn(radius: 10, angle: deg(40)), .straight(2), .turn(radius: 10, angle: deg(-40)), .straight(4)])

    /// Splash: an S-bend with a bump in its middle, then a softer S with a bump (about 29 u).
    static let splash = RaceCourse(tier: .splash, segments: [.straight(2.5), .turn(radius: 7, angle: deg(60)), .bump(1.5), .turn(radius: 7, angle: deg(-60)), .straight(1),
                                                          .turn(radius: 8, angle: deg(-30)), .bump(1.5), .turn(radius: 8, angle: deg(30)), .straight(2.5)])

    /// Wave: a hairpin right, a short straight, a hairpin left (about 35 u).
    static let wave = RaceCourse(tier: .wave, segments: [.straight(2.5), .turn(radius: 4, angle: deg(180)), .straight(2), .turn(radius: 5, angle: deg(-180)), .straight(2)])

    static func course(_ tier: CourseTier) -> RaceCourse {
        switch tier {
        case .puddle: return puddle
        case .ripple: return ripple
        case .splash: return splash
        case .wave: return wave
        }
    }
}

// MARK: - the corner rule

nonisolated enum CourseTuning {
    /// Safe corner speed (u/s) for a middling Jelly (skill 0.5), by the turn's radius: 0.78 at 4 u, 0.98 at 10 u.
    static let cornerBase: Float = 0.78, cornerPerRadius: Float = 0.033
    static func cornerSpeed(radius: Float) -> Float { cornerBase + cornerPerRadius * (radius - 4) }
    /// Cornering skill: half waddle (sure feet), half focus (looks where he is going).
    static func skill(_ s: RacerStats) -> Float { 0.5 * RaceTuning.clamp01(s.waddle) + 0.5 * RaceTuning.clamp01(s.focus) }
    /// The safe speed of a racer in a turn: x0.72 at no skill ... x1.28 fully trained.
    static func safeSpeed(radius: Float, stats: RacerStats) -> Float { cornerSpeed(radius: radius) * (0.72 + 0.56 * skill(stats)) }
    /// Trip chance per step above the safe speed: grows with how far over he is, shrinks steeply with skill (zero fully trained).
    static let cornerTripGain: Float = 0.12
    static func cornerTrip(pace: Float, radius: Float, stats: RacerStats) -> Float {
        let excess = max(0, pace / safeSpeed(radius: radius, stats: stats) - 1)
        return cornerTripGain * excess * powf(1 - skill(stats), 1.5)
    }
    /// Trip chance per step on a bump: 0.06 at no focus, squared toward zero.
    static let bumpTripBase: Float = 0.06
    static func bumpTrip(stats: RacerStats) -> Float { let u = 1 - RaceTuning.clamp01(stats.focus); return bumpTripBase * u * u }

    /// The extra trip chance of a step taken at arc length `s` at `pace` u/s (0 on a straight: the Puddle draws exactly as before).
    static func hazard(course: RaceCourse, at s: Float, pace: Float, stats: RacerStats) -> Float {
        var h: Float = 0
        if let r = course.turnRadius(at: s) { h += cornerTrip(pace: pace, radius: r, stats: stats) }
        if course.inBump(at: s) { h += bumpTrip(stats: stats) }
        return h
    }

    /// How much a rival eases off for the turn he is in or about to enter (a step-period multiplier >= 1): a focused rival slows to his safe
    /// speed, an unfocused one does not brake at all. 1 on a straight.
    static let rivalLookAhead: Float = 1.2
    static func rivalBrake(course: RaceCourse, at s: Float, stats: RacerStats, nominal: Float) -> Float {
        guard let t = course.turnAhead(of: s, within: rivalLookAhead) else { return 1 }
        let safe = safeSpeed(radius: t.radius, stats: stats)
        guard nominal > safe else { return 1 }
        let f = RaceTuning.clamp01(stats.focus)
        return 1 / (1 - f * (1 - safe / nominal))
    }
}

// MARK: - progression

/// What the player has won on each course, and which courses are open. Saved as JSON under one key; a missing or unreadable save means nothing
/// won yet (only the Puddle open), so older installs decode fine.
@MainActor
@Observable
final class CourseProgress {
    nonisolated struct Record: Codable, Equatable, Sendable { var races = 0; var wins = 0; var topTwo = 0 }
    var records: [CourseTier: Record] = [:]
    /// The course the player picked last (kept if it is open).
    var chosen: CourseTier = .puddle { didSet { save() } }
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    static let key = "Circuit.progress.v1", chosenKey = "Circuit.course.v1"
    /// Top-two finishes that open the next course without a win.
    static let topTwoToUnlock = 3
    nonisolated deinit {}

    init(persists: Bool = false, defaults: UserDefaults = .standard) {
        self.persists = persists; self.defaults = defaults
        guard persists else { return }
        if let d = defaults.data(forKey: Self.key), let r = try? JSONDecoder().decode([String: Record].self, from: d) {
            for (k, v) in r { if let t = CourseTier(rawValue: k) { records[t] = v } }
        }
        if let c = defaults.string(forKey: Self.chosenKey), let t = CourseTier(rawValue: c), unlocked(t) { chosen = t }
    }

    func record(_ tier: CourseTier) -> Record { records[tier] ?? Record() }

    /// A race on `tier` ended with the player in `place`.
    func record(tier: CourseTier, place: Int) {
        var r = record(tier)
        r.races += 1
        if place == 1 { r.wins += 1 }
        if place <= 2 { r.topTwo += 1 }
        records[tier] = r
        save()
    }

    /// Open: the Puddle always; each other course once the one below has a win, or three top-two finishes.
    func unlocked(_ tier: CourseTier) -> Bool {
        guard let below = tier.below else { return true }
        let r = record(below)
        return r.wins >= 1 || r.topTwo >= Self.topTwoToUnlock
    }
    var unlockedTiers: [CourseTier] { CourseTier.allCases.filter { unlocked($0) } }
    /// In words, what opens `tier` (nil when it is open).
    func requirement(_ tier: CourseTier) -> String? {
        guard !unlocked(tier), let below = tier.below else { return nil }
        let r = record(below)
        return "Win on \(below.title), or finish top two \(Self.topTwoToUnlock - r.topTwo) more time\(Self.topTwoToUnlock - r.topTwo == 1 ? "" : "s")"
    }

    private func save() {
        guard persists else { return }
        if let d = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: records.map { ($0.key.rawValue, $0.value) })) { defaults.set(d, forKey: Self.key) }
        defaults.set(chosen.rawValue, forKey: Self.chosenKey)
    }
}
