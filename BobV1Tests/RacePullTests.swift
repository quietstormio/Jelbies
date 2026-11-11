//
//  RacePullTests.swift
//  The pull-back-and-release hop control, headless (Race/RacePull.swift + the pull section of RaceModel.swift): the formulas, the hop, the releases,
//  the bars, the trips, the rivals' pace against the taps race, a beginner's chances, the old control unchanged. No bodies, no UI.
//
//  `PULLCAL=1` (pass `TEST_RUNNER_PULLCAL=1`) also runs the calibration sweep, which prints `[pullcal]` lines.
//

import XCTest
@testable import BobV1

// MARK: - helpers (file scope)

/// A bot that releases the pull. It has its own seeded generator, never the sim's.
struct PullBot {
    enum Kind { case perfect, steady, firstTimer, weakOnly, afk }
    var kind: Kind
    var rng: RaceRNG
    var due: Float?
    var started = false

    init(_ kind: Kind, seed: UInt64) { self.kind = kind; rng = RaceRNG(seed: seed &* 7919 &+ 17) }

    mutating func pull() -> Float {
        switch kind {
        case .perfect: return 0.81
        case .weakOnly: return 0.5
        case .afk: return 0
        case .steady: return mix(green: 0.60, weak: 0.30, weakLo: 0.45)
        case .firstTimer: return mix(green: 0.45, weak: 0.40, weakLo: 0.30, overHi: 1.10)
        }
    }
    private mutating func mix(green: Float, weak: Float, weakLo: Float, overHi: Float = 1.07) -> Float {
        let x = rng.next()
        if x < green { return rng.range(0.73, 0.89) }
        if x < green + weak { return rng.range(weakLo, 0.67) }
        return rng.range(0.95, overHi)
    }

    mutating func act(_ sim: inout RaceSim, _ evs: [RaceEvent]) {
        guard sim.phase == .running || sim.phase == .finishing else { return }
        switch kind {
        case .afk: return
        case .perfect, .weakOnly, .steady:
            if !sim.pullState(0).buffered { sim.playerRelease(pull: pull()) }
        case .firstTimer:
            for e in evs { if case .landed(let r) = e, r == 0 { due = sim.clock + rng.range(0, 0.35) } }
            if !started { started = true; due = sim.clock + rng.range(0.5, 1.0) }
            if let d = due, sim.clock >= d {
                if sim.playerRelease(pull: pull()) == .ignored { due = sim.clock + 0.1 } else { due = nil }
            }
        }
    }
}

struct PullRun {
    var sim: RaceSim
    var events: [RaceEvent] = []
    var ticks: [Int] = []
    var clocks: [Float] = []
    var place: Int? { sim.playerPlace }
    var rivalTimes: [Float] { sim.racers.dropFirst().compactMap(\.finishTime) }
    var rivalTrips: Int { sim.racers.dropFirst().reduce(0) { $0 + $1.tap.trips } }
}

@MainActor
final class RacePullTests: XCTestCase {
    /// A brand-new Jelbie: the stats the app gives a fresh one with default picker jars (JellyProfile.swift:40 -> StatTuning.seed(jars:), 50 each: waddle 0.475, focus 0.525).
    static let newJelbie: RacerStats = { let s = StatTuning.seed(jars: [50, 50, 50, 50, 50]); return RacerStats(waddle: s.waddle, focus: s.focus) }()
    static let halfTrained = RacerStats(waddle: 0.70, focus: 0.70)
    static let fullTrained = RacerStats(waddle: 1, focus: 1)
    static let untrained = RacerStats(waddle: 0, focus: 0.5)           // (pace 0.27 x 3.0 = 0.81 u/s: the brief's numbers)
    static let dt: Float = 1 / 60

    static func rivals(seed: UInt64, player: RacerStats, course: RaceCourse) -> [Rival] {
        LocalRivalSource().rivals(count: 2, player: player, playerTint: JellyRoster.tint(0), seed: seed, tier: course.tier)
    }

    /// One headless pull race.
    static func pullRun(seed: UInt64, player: RacerStats = newJelbie, bot: PullBot.Kind, course: RaceCourse = .puddle, rivals rs: [Rival]? = nil,
                        tuning: RacePullTuning = RacePullTuning(), autoJump: Bool = false, autoHop: Bool = false, boost: RaceBoost = .none,
                        keep: Bool = true, maxSeconds: Float = 200) -> PullRun {
        var sim = RaceSim(player: player, playerName: "P", rivals: rs ?? rivals(seed: seed, player: player, course: course), seed: seed, playerBoost: boost, course: course, control: .pull)
        sim.pullTuning = tuning
        sim.autoJumpPlayer = autoJump
        sim.autoHopPlayer = autoHop
        var b = PullBot(bot, seed: seed)
        var run = PullRun(sim: sim)
        var tick = 0
        while sim.phase != .results, tick < Int(maxSeconds * 60) {
            sim.tick(dt: dt)
            let evs = sim.takeEvents()
            if keep { for e in evs { run.events.append(e); run.ticks.append(tick); run.clocks.append(sim.clock) } }
            b.act(&sim, evs)
            tick += 1
        }
        run.sim = sim
        return run
    }

    /// One headless taps race, the player tapping at `rate` x his top step rate (0 = never), autoJump on.
    static func tapsRun(seed: UInt64, player: RacerStats = newJelbie, rate: Float, course: RaceCourse = .puddle, rivals rs: [Rival]? = nil, autoJump: Bool = true) -> RaceSim {
        var sim = RaceSim(player: player, playerName: "P", rivals: rs ?? rivals(seed: seed, player: player, course: course), seed: seed, course: course)
        sim.autoJumpPlayer = autoJump
        let taps = rate * RaceTuning.maxRate(waddle: player.waddle)
        var tapT: Float = 0, foot = 0, tick = 0
        while sim.phase != .results, tick < 60 * 200 {
            if rate > 0, sim.phase == .running || sim.phase == .finishing {
                tapT += dt
                while tapT >= 1 / taps { tapT -= 1 / taps; sim.playerTap(foot: foot); foot = 1 - foot }
            }
            sim.tick(dt: dt)
            _ = sim.takeEvents()
            tick += 1
        }
        return sim
    }

    static let allCourses: [RaceCourse] = CourseTier.allCases.map { RaceCourse.course($0) }

    // MARK: - A. the shot

    func testShotMatchesThePrototype() {
        let t = RacePullTuning()
        func proto(_ pull: Float, _ streak: Int) -> (perfect: Bool, over: Bool, eff: Float, v0: Float, vy: Float) {
            let zA: Float = 0.7, zB: Float = 0.92
            let perfect = pull >= zA && pull <= zB, over = pull > zB
            let eff = pull <= zB ? pull : max(0.35, zB - (pull - zB) * 2.4)
            let mult: Float = perfect ? 1.28 + Float(min(streak, 5)) * 0.025 : 1
            return (perfect, over, eff, (2.6 + 6.2 * eff) * mult, (3.3 + 3.4 * eff) * (perfect ? 1.08 : 1))
        }
        for pull in [Float(0.15), 0.5, 0.69, 0.70, 0.81, 0.92, 0.93, 1.0, 1.1] {
            for streak in [0, 3, 7] {
                let p = proto(pull, streak), s = t.shot(pull: pull, streak: streak, widen: 0)
                XCTAssertEqual(s.grade == .perfect, p.perfect, "pull \(pull)")
                XCTAssertEqual(s.grade == .over, p.over, "pull \(pull)")
                XCTAssertEqual(s.v0, p.v0, accuracy: 1e-4, "v0 at \(pull) / \(streak)")
                XCTAssertEqual(s.vy, p.vy, accuracy: 1e-4, "vy at \(pull) / \(streak)")
            }
        }
        // the borders
        XCTAssertEqual(t.shot(pull: 0.699, streak: 0, widen: 0).grade, .weak)
        XCTAssertEqual(t.shot(pull: 0.70, streak: 0, widen: 0).grade, .perfect)
        XCTAssertEqual(t.shot(pull: 0.92, streak: 0, widen: 0).grade, .perfect)
        XCTAssertEqual(t.shot(pull: 0.921, streak: 0, widen: 0).grade, .over)
        XCTAssertEqual(t.shot(pull: 2.0, streak: 0, widen: 0).grade, .over, "the pull is clamped to pullMax, never beyond")
        // a wider zone (the perk)
        XCTAssertEqual(t.shot(pull: 0.65, streak: 0, widen: 0.05).grade, .perfect)
        XCTAssertEqual(t.shot(pull: 0.945, streak: 0, widen: 0.05).grade, .perfect)
        XCTAssertEqual(t.shot(pull: 0.95, streak: 0, widen: 0.05).grade, .over)
        XCTAssertEqual(t.shot(pull: 0.64, streak: 0, widen: 0.05).grade, .weak)
        // the streak bonus stops at 5
        XCTAssertEqual(t.shot(pull: 0.8, streak: 5, widen: 0).v0, t.shot(pull: 0.8, streak: 9, widen: 0).v0)
        XCTAssertGreaterThan(t.shot(pull: 0.8, streak: 5, widen: 0).v0, t.shot(pull: 0.8, streak: 0, widen: 0).v0)
    }

    // MARK: - B. lengths, apex, air

    func testProtoLengthApexAndAirMatchTheBriefsNumbers() {
        var t = RacePullTuning(); t.hopScale = 0.096          // (the brief's world-unit numbers are for 0.096; the calibrated default is a little higher)
        // the first perfect hop from standing
        let s1 = t.shot(pull: 0.81, streak: 0, widen: 0)
        let vsL1 = min(t.vsMax, t.carry * 1.5 + s1.v0)
        XCTAssertEqual(vsL1, 10.28, accuracy: 0.01)
        XCTAssertEqual(t.protoLength(vs0: vsL1, flight: t.protoFlight(vy: s1.vy)), 5.00, accuracy: 0.02)
        // a chain at the cap
        let s2 = t.shot(pull: 0.81, streak: 5, widen: 0)
        XCTAssertEqual(t.protoLength(vs0: 14, flight: t.protoFlight(vy: s2.vy)), 6.78, accuracy: 0.02)
        // a weak 0.5 pull from standing
        let s3 = t.shot(pull: 0.5, streak: 0, widen: 0)
        let vsL3 = min(t.vsMax, t.carry * 1.5 + s3.v0)
        XCTAssertEqual(t.protoLength(vs0: vsL3, flight: t.protoFlight(vy: s3.vy)), 2.40, accuracy: 0.02)
        // apex and air
        XCTAssertEqual(t.apex(vy: t.shot(pull: 0.15, streak: 0, widen: 0).vy), 0.10, accuracy: 0.002)
        XCTAssertEqual(t.apex(vy: s1.vy), 0.20, accuracy: 0.003)
        XCTAssertEqual(t.apex(vy: t.shot(pull: 0.92, streak: 0, widen: 0).vy), 0.22, accuracy: 0.005)
        XCTAssertEqual(t.apex(vy: s3.vy), 0.137, accuracy: 0.003)
        XCTAssertEqual(t.air(apex: 0.20), 0.368, accuracy: 0.001)
        XCTAssertEqual(t.air(apex: 0.20), HurdleTuning.airTime, accuracy: 1e-4, "the same law as the race jump")
        // the preview, in world units, for an untrained Jelbie (pace 0.81)
        let p1 = t.preview(pull: 0.81, streak: 0, widen: 0, vs: 1.5, pace: 0.81, slow: false)
        XCTAssertEqual(p1.length, 0.39, accuracy: 0.01); XCTAssertEqual(p1.grade, .perfect)
        let p2 = t.preview(pull: 0.81, streak: 5, widen: 0, vs: 11, pace: 0.81, slow: false)
        XCTAssertEqual(p2.length, 0.53, accuracy: 0.01)
        let p3 = t.preview(pull: 0.5, streak: 0, widen: 0, vs: 1.5, pace: 0.81, slow: false)
        XCTAssertEqual(p3.length, 0.19, accuracy: 0.01); XCTAssertEqual(p3.apex, 0.137, accuracy: 0.003); XCTAssertEqual(p3.grade, .weak)
        XCTAssertEqual(t.preview(pull: 0.81, streak: 0, widen: 0, vs: 1.5, pace: 0.81, slow: true).length, p1.length * HurdleTuning.slowFactor, accuracy: 1e-4)
        XCTAssertLessThanOrEqual(t.preview(pull: 0.81, streak: 5, widen: 0, vs: 14, pace: 5, slow: false).length, t.hopCap)
    }

    // MARK: - C. the magnet

    func testMagnetLeavesNoHoleOnTheGrid() {
        let t = RacePullTuning()
        var holes = 0, cases = 0, over = 0, short = 0, same = 0
        var firstHole = ""
        var l: Float = 0.10
        while l <= 0.9001 {
            var d: Float = 0.12
            while d <= 1.6001 {
                var a: Float = 0.10
                while a <= 0.2201 {
                    cases += 1
                    let m = t.magnet(length: l, apex: a, toBar: d, toNext: nil)
                    let lo = t.stretchLo * l, hi = max(min(t.stretchHi * l, t.stretchMax), t.stretchFloor)
                    var ok: Bool
                    if m.length <= d - t.landShort + 1e-5 {
                        ok = m.length == l || (m.length >= lo - 1e-5 && m.length <= hi + 1e-5)
                        if m.length == l { same += 1 } else { short += 1 }
                    } else {
                        let u = d / m.length
                        ok = u >= t.uMin - 1e-5 && u <= 0.8 + 1e-5 && m.apex * 4 * u * (1 - u) >= t.barTop - 1e-5 && m.length >= d + t.landBeyond - 1e-5
                            && m.length >= lo - 1e-5 && m.length <= hi + 1e-5
                        over += 1
                    }
                    if !ok { holes += 1; if firstHole.isEmpty { firstHole = "L \(l) D \(d) apex \(a) -> \(m)" } }
                    a += 0.01
                }
                d += 0.01
            }
            l += 0.01
        }
        print("[pullcal] magnet grid: \(cases) cases, same \(same), short \(short), over \(over), holes \(holes)")
        XCTAssertEqual(holes, 0, "the magnet leaves a hole: \(firstHole)")
        // a bar right under his feet: the hop still goes over it, at the cap
        let m0 = t.magnet(length: 0.4, apex: 0.15, toBar: 0.05, toNext: nil)
        XCTAssertGreaterThanOrEqual(m0.length, 0.05 + t.landBeyond - 1e-5)
    }

    // MARK: - D. a perfect chain

    func testPerfectChainSpeedAndRhythm() {
        for stats in [Self.newJelbie, Self.halfTrained, Self.fullTrained] {
            var speeds: [Float] = [], gaps: [Float] = [], bestStreak = 0
            for seed in UInt64(1)...6 {
                let run = Self.pullRun(seed: seed, player: stats, bot: .perfect)
                var landed = 0, d6: Float = 0, t6: Float = 0, lens: [Float] = [], hopClocks: [Float] = []
                for (k, e) in run.events.enumerated() {
                    if case .hop(let r, let len, _, _, _, _, let st) = e, r == 0 { lens.append(len); hopClocks.append(run.clocks[k]); bestStreak = max(bestStreak, st) }
                    if case .landed(let r) = e, r == 0 { landed += 1; if landed == 6 { d6 = lens.prefix(6).reduce(0, +); t6 = run.clocks[k] } }
                }
                guard let ft = run.sim.player.finishTime, landed >= 6 else { XCTFail("seed \(seed): did not finish"); continue }
                speeds.append((run.sim.course.length - d6) / (ft - t6))
                for k in 3..<max(3, hopClocks.count - 1) { gaps.append(hopClocks[k] - hopClocks[k - 1]) }
            }
            let pace = RaceTuning.stride(waddle: stats.waddle) * RaceTuning.maxRate(waddle: stats.waddle)
            let mean = speeds.reduce(0, +) / Float(speeds.count), gap = gaps.reduce(0, +) / Float(gaps.count)
            print("[pullcal] chain speed waddle \(stats.waddle): \(mean) u/s = \(mean / pace) x pace; hop every \(gap) s; best streak \(bestStreak)")
            XCTAssertEqual(mean / pace, 1.25, accuracy: 1.25 * 0.03, "waddle \(stats.waddle): chain speed")
            XCTAssertEqual(gap, 0.52, accuracy: 0.02, "waddle \(stats.waddle): one hop every 0.52 s")
            XCTAssertGreaterThanOrEqual(bestStreak, 5)
        }
    }

    /// The first hop and a settled chain, in world units (untrained, pace 0.81): L 0.39 then 0.53.
    func testFirstHopAndChainLengths() {
        let run = Self.pullRun(seed: 3, player: Self.untrained, bot: .perfect)
        var lens: [Float] = [], first: RaceEvent?
        for e in run.events { if case .hop(let r, let len, _, _, _, _, _) = e, r == 0 { lens.append(len); if first == nil { first = e } } }
        XCTAssertEqual(lens[0], 0.40, accuracy: 0.02)
        XCTAssertEqual(lens[8], 0.545, accuracy: 0.025)
        if case .hop(_, _, let apex, let air, let crouch, let grade, let streak)? = first {
            XCTAssertEqual(crouch, 0.13, accuracy: 1e-5); XCTAssertEqual(grade, .perfect); XCTAssertEqual(streak, 1)
            XCTAssertEqual(apex, 0.20, accuracy: 0.003); XCTAssertEqual(air, 0.368, accuracy: 0.003)
        } else { XCTFail("no hop") }
    }

    // MARK: - E. releases

    func testReleases() {
        var sim = RaceSim(player: Self.newJelbie, playerName: "P", rivals: Self.rivals(seed: 5, player: Self.newJelbie, course: .puddle), seed: 5, control: .pull)
        XCTAssertEqual(sim.playerRelease(pull: 0.8), .ignored, "before go")
        var n = 0
        while sim.phase == .countdown, n < 600 { sim.tick(dt: Self.dt); _ = sim.takeEvents(); n += 1 }
        XCTAssertEqual(sim.phase, .running)
        XCTAssertEqual(sim.playerRelease(pull: 0.10), .ignored, "below minPull")
        XCTAssertFalse(sim.pullState(0).buffered)
        XCTAssertEqual(sim.playerRelease(pull: 0.81), .hopped(.perfect), "standing: the hop leaves at the next tick")
        XCTAssertTrue(sim.pullState(0).buffered)
        sim.tick(dt: Self.dt)
        XCTAssertTrue(sim.takeEvents().contains { if case .hop(0, _, _, _, _, _, _) = $0 { return true }; return false }, "the hop starts inside the tick")
        XCTAssertFalse(sim.pullState(0).buffered); XCTAssertTrue(sim.pullState(0).inHop)
        XCTAssertEqual(sim.playerRelease(pull: 0.81), .buffered, "in the air")
        XCTAssertEqual(sim.playerRelease(pull: 0.60), .buffered, "the latest wins")
        // run to the landing, then count the ticks to the next hop
        var landTick: Int?, hopTick: Int?, grade: RaceHopGrade?
        var k = 0
        while hopTick == nil, k < 300 {
            sim.tick(dt: Self.dt); k += 1
            for e in sim.takeEvents() {
                if case .landed(0) = e, landTick == nil { landTick = k }
                if case .hop(0, _, _, _, _, let g, _) = e, landTick != nil { hopTick = k; grade = g }
            }
        }
        XCTAssertEqual(grade, RaceHopGrade.weak, "the 0.60 release won (not the 0.81 one)")
        if let l = landTick, let h = hopTick { XCTAssertTrue((5...7).contains(h - l), "a buffered release fires landHold after the landing: \(h - l) ticks") } else { XCTFail("no landing / hop") }
        // after the finish: ignored
        let run = Self.pullRun(seed: 5, bot: .perfect)
        var sim2 = run.sim
        XCTAssertTrue(sim2.player.finished)
        XCTAssertEqual(sim2.playerRelease(pull: 0.8), .ignored)
        // while stumbling, and a bar hit clears the buffer
        var seen = 0
        for seed in UInt64(1)...10 where seen < 3 {
            var s = RaceSim(player: Self.newJelbie, playerName: "P", rivals: Self.rivals(seed: seed, player: Self.newJelbie, course: .wave), seed: seed, course: .wave, control: .pull)
            var bot = PullBot(.weakOnly, seed: seed)
            var t = 0
            while s.phase != .results, t < 60 * 120, seen < 3 {
                s.tick(dt: Self.dt)
                let evs = s.takeEvents()
                if evs.contains(where: { if case .trip(0) = $0 { return true }; return false }) {
                    seen += 1
                    XCTAssertFalse(s.pullState(0).buffered, "a trip clears the buffer")
                    XCTAssertEqual(s.pullState(0).streak, 0)
                    XCTAssertEqual(s.playerRelease(pull: 0.8), .ignored, "while stumbling")
                    XCTAssertEqual(s.pullState(0).vs, s.pullTuning.base, accuracy: 1e-4)
                }
                bot.act(&s, evs)
                t += 1
            }
        }
        XCTAssertGreaterThan(seen, 0, "a weak-only player trips on the Wave")
    }

    // MARK: - F. momentum

    func testMomentumCarriesAndBleedsAway() {
        func secondHop(delayAfterLanding: Float?) -> Float {
            var sim = RaceSim(player: Self.untrained, playerName: "P", rivals: Self.rivals(seed: 9, player: Self.untrained, course: .puddle), seed: 9, control: .pull)
            var n = 0
            while sim.phase == .countdown, n < 600 { sim.tick(dt: Self.dt); _ = sim.takeEvents(); n += 1 }
            sim.playerRelease(pull: 0.81)
            var landedAt: Float?, lens: [Float] = [], released = false
            var k = 0
            while lens.count < 2, k < 600 {
                sim.tick(dt: Self.dt); k += 1
                for e in sim.takeEvents() {
                    if case .hop(0, let len, _, _, _, _, _) = e { lens.append(len); if lens.count == 1, delayAfterLanding == nil { sim.playerRelease(pull: 0.81); released = true } }
                    if case .landed(0) = e { landedAt = sim.clock }
                }
                if !released, let la = landedAt, let dly = delayAfterLanding, sim.clock - la >= dly - 1e-4 { sim.playerRelease(pull: 0.81); released = true }
            }
            return lens.count == 2 ? lens[1] : -1
        }
        let buffered = secondHop(delayAfterLanding: nil), late = secondHop(delayAfterLanding: 0.3)
        let standing = RacePullTuning().preview(pull: 0.81, streak: 1, widen: 0, vs: 1.5, pace: 0.81, slow: false).length
        print("[pullcal] momentum: buffered \(buffered), 0.3 s late \(late), from standing \(standing)")
        XCTAssertGreaterThan(buffered, late); XCTAssertGreaterThan(late, standing)
        // standing still: after a weak hop and 2 s the momentum is back at base
        var sim = RaceSim(player: Self.untrained, playerName: "P", rivals: Self.rivals(seed: 9, player: Self.untrained, course: .puddle), seed: 9, control: .pull)
        var n = 0
        while sim.phase == .countdown, n < 600 { sim.tick(dt: Self.dt); _ = sim.takeEvents(); n += 1 }
        sim.playerRelease(pull: 0.5)
        var landed = false, k = 0, landClock: Float = 0
        while k < 600 {
            sim.tick(dt: Self.dt); k += 1
            for e in sim.takeEvents() { if case .landed(0) = e { landed = true; landClock = sim.clock } }
            if landed, sim.clock - landClock >= 2.0 { break }
        }
        XCTAssertTrue(landed)
        XCTAssertEqual(sim.pullState(0).vs, sim.pullTuning.base, accuracy: 0.05)
        XCTAssertFalse(sim.pullState(0).inHop)
    }

    // MARK: - G. bars

    func testPerfectClearsEveryBarAndAWeakPlayerHitsMost() {
        for tier in [CourseTier.splash, .wave, .tsunami] {
            let c = RaceCourse.course(tier)
            var weakHits = 0, weakBars = 0, weakSeen = 0
            for seed in UInt64(1)...50 {
                let run = Self.pullRun(seed: seed, bot: .perfect, course: c)
                let p = run.sim.player
                XCTAssertTrue(p.finished, "\(tier) seed \(seed): perfect finishes")
                XCTAssertEqual(p.hurdlesHit, 0, "\(tier) seed \(seed)")
                XCTAssertEqual(p.hurdlesCleared, c.hurdles.count, "\(tier) seed \(seed): every bar cleared")
                XCTAssertEqual(p.tap.trips, 0, "\(tier) seed \(seed): no trip")
                XCTAssertFalse(run.events.contains { if case .trip(0) = $0 { return true }; return false })
                // weak only
                let w = Self.pullRun(seed: seed, bot: .weakOnly, course: c)
                weakHits += w.sim.player.hurdlesHit; weakBars += w.sim.player.hurdlesHit + w.sim.player.hurdlesCleared
                // a hit: .hurdleHit in the flight, then .trip at that landing, streak 0, slow set
                var inFlight = false, hitInFlight = false, checked = false
                var s = RaceSim(player: Self.newJelbie, playerName: "P", rivals: Self.rivals(seed: seed, player: Self.newJelbie, course: c), seed: seed, course: c, control: .pull)
                var bot = PullBot(.weakOnly, seed: seed)
                var t = 0
                while s.phase != .results, t < 60 * 120, !checked {
                    s.tick(dt: Self.dt)
                    let evs = s.takeEvents()
                    for e in evs {
                        switch e {
                        case .hop(0, _, _, _, _, _, _): inFlight = true; hitInFlight = false
                        case .hurdleHit(0): XCTAssertTrue(inFlight, "a hit is announced in the flight"); hitInFlight = true
                        case .landed(0): inFlight = false
                        case .trip(0):
                            guard hitInFlight else { break }          // (a rolled trip, not a bar hit)
                            XCTAssertGreaterThan(s.player.slow, 0); XCTAssertEqual(s.player.streak, 0)
                            checked = true; weakSeen += 1
                        default: break
                        }
                    }
                    bot.act(&s, evs)
                    t += 1
                }
            }
            let rate = Double(weakHits) / Double(max(weakBars, 1))
            print("[pullcal] weakOnly \(tier): hits \(weakHits) of \(weakBars) bars = \(rate)")
            XCTAssertGreaterThan(rate, 0.5, "\(tier): a weak-only player hits more than half the bars")
            XCTAssertGreaterThan(weakSeen, 0)
        }
    }

    // MARK: - H. trips, I. rivals' pace

    func testPerfectNeverTripsAndRivalTripsMatchTheTapsRace() {
        for c in Self.allCourses {
            for seed in UInt64(1)...50 {
                let r = Self.pullRun(seed: seed, bot: .perfect, course: c, keep: false)
                XCTAssertEqual(r.sim.player.tap.trips, 0, "\(c.tier) seed \(seed): perfect hops never trip")
            }
            var pullTrips = 0, tapsTrips = 0, fullPull = 0, fullTaps = 0
            for seed in UInt64(1)...200 {
                let stats = seed % 2 == 0 ? Self.newJelbie : Self.halfTrained
                let rs = Self.rivals(seed: seed, player: stats, course: c)
                pullTrips += Self.pullRun(seed: seed, player: stats, bot: .afk, course: c, rivals: rs, keep: false).rivalTrips
                tapsTrips += Self.tapsRun(seed: seed, player: stats, rate: 0, course: c, rivals: rs, autoJump: false).racers.dropFirst().reduce(0) { $0 + $1.tap.trips }
                guard seed <= 50 else { continue }
                let full = [Rival(name: "A", tint: .one, stats: Self.fullTrained), Rival(name: "B", tint: .one, stats: Self.fullTrained)]
                // (a bar a rival fails to jump is a trip by design, even for a fully trained one: only trips on the open track count here)
                fullPull += Self.pullRun(seed: seed, player: stats, bot: .afk, course: c, rivals: full, keep: false).sim.racers.dropFirst().reduce(0) { $0 + $1.tap.trips - $1.hurdlesHit }
                fullTaps += Self.tapsRun(seed: seed, player: stats, rate: 0, course: c, rivals: full, autoJump: false).racers.dropFirst().reduce(0) { $0 + $1.tap.trips - $1.hurdlesHit }
            }
            let ratio = Double(pullTrips) / Double(max(tapsTrips, 1))
            print("[pullcal] rival trips \(c.tier): pull \(Double(pullTrips) / 200) taps \(Double(tapsTrips) / 200) per race, ratio \(ratio)")
            XCTAssertEqual(ratio, 1, accuracy: 0.25, "\(c.tier): rivals trip about as often as in the taps race")
            XCTAssertEqual(fullPull, 0, "\(c.tier): fully trained rivals never trip (pull)")
            XCTAssertEqual(fullTaps, 0, "\(c.tier): fully trained rivals never trip (taps)")
        }
    }

    func testRivalPaceMatchesTheTapsRace() {
        for c in Self.allCourses {
            var pullT: [Float] = [], tapsT: [Float] = []
            for seed in UInt64(1)...200 {
                let stats = seed % 2 == 0 ? Self.newJelbie : Self.halfTrained
                let rs = Self.rivals(seed: seed, player: stats, course: c)
                pullT += Self.pullRun(seed: seed, player: stats, bot: .afk, course: c, rivals: rs, keep: false).rivalTimes
                tapsT += Self.tapsRun(seed: seed, player: stats, rate: 0, course: c, rivals: rs, autoJump: false).racers.dropFirst().compactMap(\.finishTime)
            }
            let mp = pullT.reduce(0, +) / Float(max(pullT.count, 1)), mt = tapsT.reduce(0, +) / Float(max(tapsT.count, 1))
            print("[pullcal] rival time \(c.tier): pull \(mp) s (\(pullT.count) finishers) taps \(mt) s (\(tapsT.count)), ratio \(mp / mt)")
            XCTAssertEqual(mp / mt, 1, accuracy: 0.05, "\(c.tier): rivals run about as fast as in the taps race")
        }
    }

    // MARK: - J. a beginner

    func testABeginnerWinsOftenOnThePuddle() {
        var wins = 0, top2 = 0, n = 0
        for seed in UInt64(1)...200 {
            let r = Self.pullRun(seed: seed, bot: .firstTimer, keep: false)
            n += 1
            if let p = r.place, r.sim.playerFinished { if p == 1 { wins += 1 }; if p <= 2 { top2 += 1 } }
        }
        print("[pullcal] firstTimer, new Jelbie, Puddle: wins \(wins)/\(n), top two \(top2)/\(n)")
        XCTAssertGreaterThanOrEqual(wins, n / 2, "a first-timer wins at least half")
        XCTAssertGreaterThanOrEqual(Double(top2) / Double(n), 0.85, "and is in the top two at least 85 %")
    }

    // MARK: - K. afk

    func testAnIdlePlayerNeverFinishesAndEarnsNothing() {
        for seed in UInt64(1)...5 {
            let r = Self.pullRun(seed: seed, bot: .afk, keep: false)
            XCTAssertFalse(r.sim.playerFinished); XCTAssertEqual(r.sim.playerDrops, 0)
            XCTAssertEqual(r.sim.phase, .results)
            if let f = r.sim.firstFinishAt {
                XCTAssertEqual(r.sim.clock, f + 2 * RaceTuning.finishGrace, accuracy: 0.05, "the race ends 10 s after the first finisher, as a taps race with an idle player does")
                let t = Self.tapsRun(seed: seed, rate: 0, autoJump: false)
                if let tf = t.firstFinishAt { XCTAssertEqual(t.clock, tf + 2 * RaceTuning.finishGrace, accuracy: 0.05) }
                XCTAssertEqual(t.playerDrops, 0)
            }
        }
    }

    // MARK: - L. a finish in the air

    func testAFinishInTheAirCompletesTheFlightThenCoasts() {
        var found = 0
        for seed in UInt64(1)...30 {
            let r = Self.pullRun(seed: seed, bot: .perfect)
            let ev = r.events
            guard let fin = ev.firstIndex(where: { if case .finished(0, _) = $0 { return true }; return false }) else { XCTFail("seed \(seed): no finish"); continue }
            // the finish in the air: a hop was running when he finished
            var inHop = false
            for e in ev[..<fin] { if case .hop(0, _, _, _, _, _, _) = e { inHop = true }; if case .landed(0) = e { inHop = false } }
            guard inHop else { continue }
            found += 1
            let after = ev[(fin + 1)...]
            let landed = after.firstIndex { if case .landed(0) = $0 { return true }; return false }
            let step = after.firstIndex { if case .step(0, _, _, _, _) = $0 { return true }; return false }
            XCTAssertNotNil(landed, "seed \(seed): the flight is completed")
            XCTAssertNotNil(step, "seed \(seed): then he coasts")
            if let l = landed, let s = step { XCTAssertLessThan(l, s, "seed \(seed): .landed before the coast steps") }
            XCTAssertFalse(after.contains { if case .hop(0, _, _, _, _, _, _) = $0 { return true }; return false }, "no hop after the finish")
            XCTAssertEqual(after.filter { if case .step(0, _, _, _, _) = $0 { return true }; return false }.count, RaceTuning.coastSteps)
            XCTAssertFalse(ev.contains { if case .stumble = $0 { return true }; if case .jump = $0 { return true }; return false }, "a pull race never emits .stumble or .jump")
        }
        XCTAssertGreaterThan(found, 0, "some seed finishes in the air")
    }

    // MARK: - M. determinism and the old control

    func testSameSeedSameBotSameEvents() {
        for c in [RaceCourse.puddle, .wave] {
            let a = Self.pullRun(seed: 7, bot: .steady, course: c), b = Self.pullRun(seed: 7, bot: .steady, course: c)
            XCTAssertEqual(a.events, b.events)
            XCTAssertEqual(a.sim.racers.map { $0.dist.bitPattern }, b.sim.racers.map { $0.dist.bitPattern })
        }
    }

    func testTheTapsControlIsUnchanged() {
        func events(_ course: RaceCourse, seed: UInt64, control: RaceControl?) -> ([RaceEvent], [UInt32]) {
            let stats = Self.newJelbie
            let rs = Self.rivals(seed: seed, player: stats, course: course)
            var sim = control.map { RaceSim(player: stats, playerName: "P", rivals: rs, seed: seed, course: course, control: $0) } ?? RaceSim(player: stats, playerName: "P", rivals: rs, seed: seed, course: course)
            sim.autoJumpPlayer = true
            var out: [RaceEvent] = []
            var tapT: Float = 0, foot = 0, tick = 0
            while sim.phase != .results, tick < 60 * 150 {
                if sim.phase == .running || sim.phase == .finishing { tapT += Self.dt; while tapT >= 1 / 4 { tapT -= 1 / 4; sim.playerTap(foot: foot); foot = 1 - foot } }
                sim.tick(dt: Self.dt)
                out += sim.takeEvents()
                tick += 1
            }
            return (out, sim.racers.map { $0.dist.bitPattern })
        }
        for c in [RaceCourse.puddle, .splash, .wave] {
            for seed in UInt64(1)...4 {
                let a = events(c, seed: seed, control: nil), b = events(c, seed: seed, control: .taps)
                XCTAssertEqual(a.0, b.0, "\(c.tier) seed \(seed)"); XCTAssertEqual(a.1, b.1)
                XCTAssertFalse(a.0.isEmpty)
                XCTAssertFalse(a.0.contains { if case .hop = $0 { return true }; if case .landed = $0 { return true }; return false }, "no pull event in a taps race")
            }
        }
        // the two controls ignore each other's buttons
        var taps = RaceSim(player: Self.newJelbie, playerName: "P", rivals: Self.rivals(seed: 1, player: Self.newJelbie, course: .puddle), seed: 1)
        var pull = RaceSim(player: Self.newJelbie, playerName: "P", rivals: Self.rivals(seed: 1, player: Self.newJelbie, course: .wave), seed: 1, course: .wave, control: .pull)
        for _ in 0..<(60 * 4) { taps.tick(dt: Self.dt); pull.tick(dt: Self.dt) }
        XCTAssertEqual(taps.phase, .running); XCTAssertEqual(pull.phase, .running)
        XCTAssertEqual(taps.playerRelease(pull: 0.8), .ignored)
        XCTAssertFalse(taps.pullState(0).buffered)
        XCTAssertEqual(pull.playerTap(foot: 0), .ignored); XCTAssertFalse(pull.playerJump())
        XCTAssertEqual(pull.player.tap.pending, nil)
    }

    // MARK: - N. focus pauses

    func testLowFocusPausesNeverInTheAir() {
        var pauses = 0
        for seed in UInt64(1)...50 {
            let rs = [Rival(name: "A", tint: .one, stats: RacerStats(waddle: 0.5, focus: 0)), Rival(name: "B", tint: .one, stats: RacerStats(waddle: 0.5, focus: 0.1))]
            let r = Self.pullRun(seed: seed, bot: .steady, rivals: rs)
            var inHop = [false, false, false]
            for e in r.events {
                switch e {
                case .hop(let i, _, _, _, _, _, _): inHop[i] = true
                case .landed(let i): inHop[i] = false
                case .pauseBegan(let i): pauses += 1; XCTAssertFalse(inHop[i], "seed \(seed): a pause began between a hop and its landing")
                default: break
                }
            }
        }
        XCTAssertGreaterThan(pauses, 0, "a low-focus racer pauses at least once in 50 races")
    }

    // MARK: - O. the assists

    func testAutoHopAndAutoJump() {
        for c in [RaceCourse.splash, .wave, .tsunami] {
            for seed in UInt64(1)...10 {
                let a = Self.pullRun(seed: seed, bot: .afk, course: c, autoHop: true)
                XCTAssertTrue(a.sim.player.finished, "\(c.tier) seed \(seed): the auto player finishes with no release")
                XCTAssertEqual(a.sim.player.hurdlesHit, 0); XCTAssertEqual(a.sim.player.hurdlesCleared, c.hurdles.count)
                XCTAssertEqual(a.sim.player.tap.trips, 0, "green treatment: no trips")
                let w = Self.pullRun(seed: seed, bot: .weakOnly, course: c, autoJump: true)
                XCTAssertEqual(w.sim.player.hurdlesHit, 0, "\(c.tier) seed \(seed): autoJump clears every bar even with weak pulls")
                XCTAssertTrue(w.sim.player.finished)
                XCTAssertEqual(w.sim.player.hurdlesCleared, c.hurdles.count)
            }
        }
    }

    // MARK: - calibration (PULLCAL=1)

    func testCalibrationSweep() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PULLCAL"] == "1", "calibration only: PULLCAL=1")
        var tune = RacePullTuning()
        let seeds = UInt64(1)...200
        // 1. hopScale from the chain speed
        func chain(_ t: RacePullTuning, _ stats: RacerStats) -> Float {
            var sp: [Float] = []
            for seed in UInt64(1)...12 {
                let run = Self.pullRun(seed: seed, player: stats, bot: .perfect, tuning: t)
                var landed = 0, d6: Float = 0, t6: Float = 0, lens: [Float] = []
                for (k, e) in run.events.enumerated() {
                    if case .hop(0, let len, _, _, _, _, _) = e { lens.append(len) }
                    if case .landed(0) = e { landed += 1; if landed == 6 { d6 = lens.prefix(6).reduce(0, +); t6 = run.clocks[k] } }
                }
                if let ft = run.sim.player.finishTime, landed >= 6 { sp.append((run.sim.course.length - d6) / (ft - t6)) }
            }
            return sp.reduce(0, +) / Float(max(sp.count, 1)) / (RaceTuning.stride(waddle: stats.waddle) * RaceTuning.maxRate(waddle: stats.waddle))
        }
        let ratio0 = chain(tune, Self.newJelbie)
        print("[pullcal] hopScale \(tune.hopScale): chain speed = \(ratio0) x pace (target 1.25); half \(chain(tune, Self.halfTrained)), full \(chain(tune, Self.fullTrained))")
        tune.hopScale *= 1.25 / ratio0
        print("[pullcal] hopScale -> \(tune.hopScale): new \(chain(tune, Self.newJelbie)), half \(chain(tune, Self.halfTrained)), full \(chain(tune, Self.fullTrained))")

        // 2. rivalLength against the taps race
        func statsFor(_ seed: UInt64) -> RacerStats { seed % 2 == 0 ? Self.newJelbie : Self.halfTrained }
        var tapsTime: [CourseTier: Float] = [:], tapsTrips: [CourseTier: Double] = [:]
        for c in Self.allCourses {
            var ts: [Float] = [], trips = 0
            for seed in seeds {
                let rs = Self.rivals(seed: seed, player: statsFor(seed), course: c)
                let s = Self.tapsRun(seed: seed, player: statsFor(seed), rate: 0, course: c, rivals: rs, autoJump: false)
                ts += s.racers.dropFirst().compactMap(\.finishTime); trips += s.racers.dropFirst().reduce(0) { $0 + $1.tap.trips }
            }
            tapsTime[c.tier] = ts.reduce(0, +) / Float(ts.count); tapsTrips[c.tier] = Double(trips) / 200
            print("[pullcal] taps rivals \(c.tier): mean finish \(tapsTime[c.tier]!) s (\(ts.count) finishers), trips \(tapsTrips[c.tier]!) per race")
        }
        func pullRivals(_ t: RacePullTuning, _ c: RaceCourse) -> (time: Float, trips: Double) {
            var ts: [Float] = [], trips = 0
            for seed in seeds {
                let rs = Self.rivals(seed: seed, player: statsFor(seed), course: c)
                let r = Self.pullRun(seed: seed, player: statsFor(seed), bot: .afk, course: c, rivals: rs, tuning: t, keep: false)
                ts += r.rivalTimes; trips += r.rivalTrips
            }
            return (ts.reduce(0, +) / Float(max(ts.count, 1)), Double(trips) / 200)
        }
        var matches: [CourseTier: Float] = [:]
        var prev: [CourseTier: (Float, Float)] = [:]
        var rl: Float = 0.80
        while rl <= 1.4001 {
            tune.rivalLength = rl; tune.rivalLengthPuddle = rl
            var line = "[pullcal] rivalLength \(rl):"
            for c in Self.allCourses {
                let m = pullRivals(tune, c).time
                line += " \(c.tier) \(m / tapsTime[c.tier]!)"
                if let p = prev[c.tier], matches[c.tier] == nil, (p.1 - tapsTime[c.tier]!) * (m - tapsTime[c.tier]!) <= 0 {
                    let f = (p.1 - tapsTime[c.tier]!) / (p.1 - m)
                    matches[c.tier] = p.0 + f * (rl - p.0)
                }
                prev[c.tier] = (rl, m)
            }
            print(line)
            rl += 0.05
        }
        print("[pullcal] rivalLength matches per course: \(matches)")
        let chosen = matches.isEmpty ? 1.0 : matches.values.reduce(0, +) / Float(matches.count)
        tune.rivalLength = chosen; tune.rivalLengthPuddle = chosen
        print("[pullcal] rivalLength chosen (mean of the matches) = \(chosen)")
        for c in Self.allCourses { print("[pullcal]   at \(chosen): \(c.tier) \(pullRivals(tune, c).time / tapsTime[c.tier]!)") }

        // 3. tripScale
        var best: Float = 1
        var prevTrips: (Float, Double)?
        var ts: Float = 0.5
        while ts <= 4.0001 {
            tune.tripScale = ts
            var line = "[pullcal] tripScale \(ts):", sumP = 0.0
            for c in Self.allCourses { let r = pullRivals(tune, c).trips; sumP += r; line += " \(c.tier) \(r)/\(tapsTrips[c.tier]!)" }
            let sumT = tapsTrips.values.reduce(0, +)
            line += " | total \(sumP) vs taps \(sumT)"
            print(line)
            if let p = prevTrips, (p.1 - sumT) * (sumP - sumT) <= 0, p.1 != sumP { best = p.0 + Float((p.1 - sumT) / (p.1 - sumP)) * (ts - p.0) }
            prevTrips = (ts, sumP)
            ts += 0.5
        }
        tune.tripScale = best
        print("[pullcal] tripScale chosen = \(best)")
        for c in Self.allCourses { print("[pullcal]   at \(best): \(c.tier) trips \(pullRivals(tune, c).trips) vs taps \(tapsTrips[c.tier]!), time ratio \(pullRivals(tune, c).time / tapsTime[c.tier]!)") }

        // 4. the Puddle's own rival length, from the beginner test
        func beginner(_ t: RacePullTuning) -> (Int, Int) {
            var wins = 0, top2 = 0
            for seed in seeds { let r = Self.pullRun(seed: seed, bot: .firstTimer, tuning: t, keep: false); if let p = r.place, r.sim.playerFinished { if p == 1 { wins += 1 }; if p <= 2 { top2 += 1 } } }
            return (wins, top2)
        }
        let floorMul: Float = 0.80
        var mul: Float = 1.0
        while mul >= floorMul - 0.0001 {
            tune.rivalLengthPuddle = tune.rivalLength * mul
            let b = beginner(tune)
            print("[pullcal] rivalLengthPuddle \(tune.rivalLengthPuddle) (x\(mul) of rivalLength): firstTimer wins \(b.0)/200, top two \(b.1)/200")
            if b.0 >= 100, Double(b.1) / 200 >= 0.85 { break }
            mul -= 0.025
        }
        print("[pullcal] FINAL hopScale \(tune.hopScale) rivalLength \(tune.rivalLength) rivalLengthPuddle \(tune.rivalLengthPuddle) tripScale \(tune.tripScale)")

        // 5. the tables
        let boards: [(String, RacerStats)] = [("new", Self.newJelbie), ("half", Self.halfTrained)]
        for c in Self.allCourses {
            for (name, stats) in boards {
                func row(_ label: String, _ f: (UInt64) -> (place: Int?, time: Float?, hits: Int, trips: Int, closeGreens: Int, hops: Int)) {
                    var wins = 0, top2 = 0, dnf = 0, hits = 0, trips = 0, cg = 0, hops = 0
                    var times: [Float] = []
                    for seed in seeds {
                        let r = f(seed)
                        if let p = r.place { if p == 1 { wins += 1 }; if p <= 2 { top2 += 1 } }
                        if let t = r.time { times.append(t) } else { dnf += 1 }
                        hits += r.hits; trips += r.trips; cg += r.closeGreens; hops += r.hops
                    }
                    print("[pullcal] table \(c.tier) \(name) \(label): win \(wins / 2)%, top2 \(top2 / 2)%, mean time \(times.reduce(0, +) / Float(max(times.count, 1))) s, dnf \(dnf), bar hits/race \(Double(hits) / 200), trips/race \(Double(trips) / 200), green hops <0.12 from a bar \(cg) of \(hops)")
                }
                for (label, kind) in [("pull perfect", PullBot.Kind.perfect), ("pull steady", .steady), ("pull firstTimer", .firstTimer)] {
                    row(label) { seed in
                        let r = Self.pullRun(seed: seed, player: stats, bot: kind, course: c, tuning: tune, keep: false)
                        let p = r.sim.player
                        return (r.sim.playerFinished ? r.place : nil, p.finishTime, p.hurdlesHit, p.tap.trips, p.closeGreens, p.hopCount)
                    }
                }
                for frac in [Float(1.0), 0.85, 0.65] {
                    row("taps \(Int(frac * 100))%") { seed in
                        let s = Self.tapsRun(seed: seed, player: stats, rate: frac, course: c)
                        let p = s.player
                        return (s.playerFinished ? s.playerPlace : nil, p.finishTime, p.hurdlesHit, p.tap.trips, 0, p.stepCount)
                    }
                }
            }
        }
    }
}
