//
//  RaceCourseTests.swift
//  Jelly Circuit course tiers: the Puddle golden (the straight race reproduces the pre-course race bit for bit), the course model
//  (traversable, continuous, lanes apart, 25-45 s), corner / bump trips by skill, rivals on curves, unlocks and prizes, the follow camera.
//

import XCTest
import simd
@testable import BobV1

// MARK: - the Puddle golden

/// Hashes of a few seeded Puddle races, recorded on the race BEFORE the course model existed (checkpoint 7c, 2026-10-20). The race on the Puddle must
/// reproduce them exactly: the same events in the same ticks, the same finish times to the bit, the same trips and stumbles.
@MainActor
final class PuddleGoldenTests: XCTestCase {
    struct Golden { let seed: UInt64; let player: RacerStats; let taps: Float; let hash: UInt64; let placings: [Int]; let times: [UInt32?]; let trips: [Int] }

    /// FNV-1a over the strings.
    static func fnv(_ parts: [String]) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for p in parts { for b in p.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 } }
        return h
    }

    /// One seeded headless race: LocalRivalSource rivals, the player tapping alternately at `taps`/s from GO. Returns the sim and a transcript
    /// (every event with its tick, then each racer's distance bits, trips, stumbles and steps).
    static func race(seed: UInt64, player: RacerStats = RacerStats(waddle: 0.5, focus: 0.5), taps: Float = 4, course: RaceCourse? = nil, rivals rs: [Rival]? = nil) -> (sim: RaceSim, parts: [String]) {
        let rivals = rs ?? LocalRivalSource().rivals(count: 2, player: player, playerTint: JellyRoster.tint(0), seed: seed)
        var sim = course.map { RaceSim(player: player, playerName: "P", rivals: rivals, seed: seed, course: $0) } ?? RaceSim(player: player, playerName: "P", rivals: rivals, seed: seed)
        var parts: [String] = []
        var tapT: Float = 0, foot = 0, tick = 0
        let dt: Float = 1 / 60
        while sim.phase != .results, tick < 60 * 180 {
            if sim.phase == .running || sim.phase == .finishing {
                tapT += dt
                while tapT >= 1 / taps { tapT -= 1 / taps; sim.playerTap(foot: foot); foot = 1 - foot }
            }
            sim.tick(dt: dt)
            for e in sim.takeEvents() { parts.append("\(tick):\(e)") }
            tick += 1
        }
        for r in sim.racers { parts.append("D\(r.dist.bitPattern)/\(r.tap.trips)/\(r.tap.stumbles)/\(r.tap.steps)/\(r.stepCount)") }
        return (sim, parts)
    }

    static let goldens: [Golden] = [
        Golden(seed: 1, player: RacerStats(waddle: 0.5, focus: 0.5), taps: 4, hash: 0xf72452cd1bf728a9, placings: [0, 1, 2], times: [0x4156eecc, 0x415f774c, 0x417d10c8], trips: [2, 0, 1]),
        Golden(seed: 2, player: RacerStats(waddle: 0.5, focus: 0.5), taps: 4, hash: 0x70188ad4b9752886, placings: [2, 1, 0], times: [0x41819972, 0x417bbb74, 0x415f3308], trips: [3, 2, 0]),
        Golden(seed: 3, player: RacerStats(waddle: 0.5, focus: 0.5), taps: 4, hash: 0xd941405a80156ed5, placings: [0, 1, 2], times: [0x4163bb8c, 0x41684410, 0x4171995c], trips: [1, 0, 2]),
        Golden(seed: 4, player: RacerStats(waddle: 0.35, focus: 0.3), taps: 5, hash: 0xafb6af411642691, placings: [0, 2, 1], times: [0x4174cc8c, 0x419ddd9a, 0x418d3300], trips: [1, 6, 2]),
        Golden(seed: 5, player: RacerStats(waddle: 0.9, focus: 0.8), taps: 9, hash: 0xb05b85526e586e7b, placings: [0, 2, 1], times: [0x4121ddf0, 0x41340000, 0x4125ddec], trips: [0, 0, 0]),
        Golden(seed: 6, player: RacerStats(waddle: 0.45, focus: 0.5), taps: 2.5, hash: 0xa693eb545932e652, placings: [1, 2, 0], times: [0x41accc7a, 0x415ccca4, 0x417a6620], trips: [1, 0, 1]),
    ]

    func testPuddleReproducesThePreCourseRaceBitForBit() {
        for g in Self.goldens {
            for course in [nil, RaceCourse.puddle] {                      // the default race, and the Puddle asked for by name
                let (sim, parts) = Self.race(seed: g.seed, player: g.player, taps: g.taps, course: course)
                XCTAssertEqual(Self.fnv(parts), g.hash, "seed \(g.seed): the event stream changed (course \(course?.tier.rawValue ?? "default"))")
                XCTAssertEqual(sim.placings.map(\.racer), g.placings, "seed \(g.seed): placings")
                XCTAssertEqual(sim.racers.map { $0.finishTime?.bitPattern }, g.times, "seed \(g.seed): finish times to the bit")
                XCTAssertEqual(sim.racers.map(\.tap.trips), g.trips, "seed \(g.seed): trips")
                XCTAssertEqual(sim.course.tier, .puddle)
            }
        }
        XCTAssertEqual(RaceTuning.drops(place: 1), 12); XCTAssertEqual(RaceTuning.drops(place: 2), 7); XCTAssertEqual(RaceTuning.drops(place: 3), 4)
        XCTAssertEqual(RaceCourse.puddle.timeout, RaceTuning.timeout)
    }

    /// The body-driven race on the straight (RaceBodyRig, the game's glue): progress and heading every 30 ticks, recorded before the course model.
    static let bodyGoldenHash: UInt64 = 0xea4ce5cabf84a496
    static let bodyGoldenLast = "S44/1/1097893964"

    static func bodyRun(course: RaceCourse? = nil) -> [String] {
        let r = RaceBodyRig(waddle: 0.5, tapsPerSecond: 5, focus: 0.3, seed: 7, course: course)
        r.rig.renderSamples = false
        var parts: [String] = []
        var n = 0
        r.run(22) { n += 1; if n % 30 == 0 { parts.append("\(n):\(r.rig.brain.pz.bitPattern):\(r.rig.brain.yaw.bitPattern)") } }
        parts.append("S\(r.sim.racers[0].stepCount)/\(r.sim.racers[0].tap.trips)/\(r.sim.racers[0].finishTime.map { String($0.bitPattern) } ?? "nil")")
        return parts
    }

    func testPuddleBodyRaceReproducesThePreCourseRunBitForBit() {
        let a = Self.bodyRun()
        XCTAssertEqual(Self.fnv(a), Self.bodyGoldenHash, "the body's progress / heading transcript changed")
        XCTAssertEqual(a.last, Self.bodyGoldenLast)
        // the same through the course model's straight, placed where the rig stands (the general path on a straight is exact)
        let r0 = RaceBodyRig(waddle: 0.5, tapsPerSecond: 5, focus: 0.3, seed: 7)
        let straight = RaceCourse.straight(from: SIMD2(r0.rig.root.x, r0.rig.brain.pz), heading: 0, length: RaceTuning.length)
        XCTAssertLessThan(simd_distance(straight.lanePoint(1, at: 0), SIMD2(r0.rig.brain.px, r0.rig.brain.pz)), 1e-3, "the straight starts where the rig stands")
        XCTAssertEqual(Self.bodyRun(course: straight), a, "the course path on a straight is the old path to the bit")
    }

    /// The straight's lookups have no trig in them: heading exactly 0, lane x exactly RaceTuning.laneX, progress exactly pz - startZ (what BlobBrain+Race and the
    /// glue fed the race before the course model).
    func testPuddleLookupsAreExact() {
        let c = RaceCourse.puddle
        XCTAssertEqual(c.length, RaceTuning.length)
        XCTAssertTrue(c.isStraight)
        for k in 0...50 {
            let s = Float(k) / 50 * RaceTuning.length
            let p = c.pose(at: s)
            XCTAssertEqual(p.heading, 0); XCTAssertEqual(p.curvature, 0)
            XCTAssertEqual(p.pos.x, 0); XCTAssertEqual(p.pos.y, RaceTuning.startZ + s)
            for lane in 0..<3 {
                let q = c.lanePoint(lane, at: s)
                XCTAssertEqual(q.x, RaceTuning.laneX(lane)); XCTAssertEqual(q.y, RaceTuning.startZ + s)
            }
            XCTAssertNil(c.turnRadius(at: s)); XCTAssertFalse(c.inBump(at: s))
        }
        for lane in 0..<3 { for z in [Float(-7.3), -7, -3.21, 0.5, 5.5, 6.7] { for dx in [Float(-0.3), 0, 0.17] {
            XCTAssertEqual(c.progress(of: SIMD2(RaceTuning.laneX(lane) + dx, z), lane: lane, near: nil), z - RaceTuning.startZ, "progress is pz - startZ exactly")
            XCTAssertEqual(c.progress(of: SIMD2(RaceTuning.laneX(lane) + dx, z), lane: lane, near: 3), z - RaceTuning.startZ)
        } } }
    }
}

// MARK: - the course model

@MainActor
final class CourseModelTests: XCTestCase {
    static let tiers = CourseTier.allCases

    /// Every course: starts on the start line facing +z, ends facing +z (so the gantry is square), turns as much left as right (every lane the same
    /// length), lanes stay apart (no turn tighter than the lane spacing), position and heading are continuous along it, and the clay never crosses itself.
    func testEveryCourseIsTraversableContinuousAndTheLanesStayApart() {
        for t in Self.tiers {
            let c = RaceCourse.course(t)
            XCTAssertEqual(c.tier, t)
            XCTAssertEqual(c.pose(at: 0).pos, SIMD2(0, RaceTuning.startZ), "\(t): starts on the start line")
            XCTAssertEqual(c.pose(at: 0).heading, 0)
            XCTAssertEqual(wrapAngle(c.pose(at: c.length).heading), 0, accuracy: 1e-4, "\(t): finishes facing +z")
            XCTAssertEqual(c.netTurn, 0, accuracy: 1e-4, "\(t): turns as much left as right")
            for lane in 0..<3 { XCTAssertEqual(c.laneLength(lane), c.length, accuracy: 1e-3, "\(t): lane \(lane) is as long as the course") }
            for seg in c.segments { if case .turn(let r, _) = seg { XCTAssertGreaterThan(r - RaceTuning.laneSpacing, 2.0, "\(t): the inner lane's radius leaves room to turn") } }
            // continuity: small steps in s move the position a little and the heading a little
            var prev = c.pose(at: -1)
            var s: Float = -1 + 0.05
            while s < c.length + 3 {
                let p = c.pose(at: s)
                XCTAssertEqual(simd_distance(p.pos, prev.pos), 0.05, accuracy: 0.002, "\(t): the centreline moves by the arc step at s \(s)")
                XCTAssertLessThan(abs(wrapAngle(p.heading - prev.heading)), 0.05 / 2.0 + 1e-3, "\(t): heading continuous at s \(s)")
                for lane in 0..<3 {
                    let q = c.lanePoint(lane, at: s), q0 = c.lanePoint(lane, at: s - 0.05)
                    XCTAssertLessThan(simd_distance(q, q0), 0.08, "\(t): lane \(lane) continuous at s \(s)")
                }
                // lanes never cross: the three lane points are in order along the right vector, spacing kept
                let r = RaceCourse.right(p.heading)
                let xs = (0..<3).map { simd_dot(c.lanePoint($0, at: s) - p.pos, r) }
                XCTAssertEqual(xs[1] - xs[0], RaceTuning.laneSpacing, accuracy: 1e-3); XCTAssertEqual(xs[2] - xs[1], RaceTuning.laneSpacing, accuracy: 1e-3)
                prev = p; s += 0.05
            }
            // the clay never overlaps itself: centreline points far apart in s are far apart in space
            let pts = c.polyline(from: -RaceModels.before, to: c.length + RaceModels.after, step: 0.25)
            for i in pts.indices { for j in pts.indices where Float(j - i) * 0.25 > 2 * RaceModels.trackHalfW + 1 {
                XCTAssertGreaterThan(simd_distance(pts[i], pts[j]), 2 * RaceModels.trackHalfW + 0.3, "\(t): the track crosses itself (\(i), \(j))")
            } }
            // the inverse: progress recovers s on every lane, with and without a hint, including a little off the line
            for lane in 0..<3 {
                var s: Float = 0
                while s <= c.length {
                    let q = c.lanePoint(lane, at: s), r = RaceCourse.right(c.pose(at: s).heading)
                    XCTAssertEqual(c.progress(of: q, lane: lane, near: s - 0.4), s, accuracy: 0.03, "\(t): progress inverts lanePoint (lane \(lane), s \(s))")
                    XCTAssertEqual(c.progress(of: q + r * 0.3, lane: lane, near: nil), s, accuracy: 0.05, "\(t): a little off the line (lane \(lane), s \(s))")
                    XCTAssertEqual(c.lateral(of: q + r * 0.3, lane: lane, at: s), 0.3, accuracy: 0.02)
                    s += 0.5
                }
            }
            // the mini map has points and keeps proportion
            let pts2 = CourseMiniMap.points(c, in: CGSize(width: 92, height: 64))
            XCTAssertGreaterThan(pts2.count, 10)
            for p in pts2 { XCTAssertTrue(p.x >= 0 && p.x <= 92 && p.y >= 0 && p.y <= 64, "\(t): mini map inside its box") }
            // the mesh builds and fits the field
            let m = RaceModels.build(course: c)
            XCTAssertGreaterThan(m.indices.count, 1000, "\(t): the track mesh has triangles")
            let bb = c.bounds()
            XCTAssertGreaterThan(bb.min.x, -60); XCTAssertLessThan(bb.max.x, 60); XCTAssertGreaterThan(bb.min.y, -45, "\(t): in front of the far hills"); XCTAssertLessThan(bb.max.y, 40)
        }
        XCTAssertTrue(RaceCourse.puddle.isStraight); XCTAssertFalse(RaceCourse.ripple.isStraight)
        XCTAssertTrue(RaceCourse.splash.hasBumps); XCTAssertFalse(RaceCourse.wave.hasBumps)
        XCTAssertLessThan(RaceCourse.puddle.length, RaceCourse.ripple.length); XCTAssertLessThan(RaceCourse.ripple.length, RaceCourse.splash.length); XCTAssertLessThan(RaceCourse.splash.length, RaceCourse.wave.length)
    }

    /// Ripple, Splash and Wave take 25-45 s from GO with average taps (the Puddle stays its ~12 s sprint, as before courses), well inside their timeouts.
    func testTheNewCoursesTakeTwentyFiveToFortyFiveSeconds() {
        for t in [CourseTier.ripple, .splash, .wave] {
            var times: [Float] = []
            for seed in UInt64(1)...6 {
                let (sim, _) = PuddleGoldenTests.race(seed: seed, player: RacerStats(waddle: 0.5, focus: 0.5), taps: 4, course: RaceCourse.course(t))
                XCTAssertEqual(sim.phase, .results)
                guard let ft = sim.player.finishTime else { XCTFail("\(t) seed \(seed): the player did not finish"); continue }
                times.append(ft)
                XCTAssertLessThan(ft + RaceTuning.finishGrace, sim.course.timeout, "\(t): the timeout leaves room for the stragglers")
            }
            let mean = times.reduce(0, +) / Float(times.count)
            print("COURSE time \(t): mean \(mean) s, \(times)")
            XCTAssertGreaterThan(mean, 25, "\(t): about 25-45 s with average taps (\(mean))")
            XCTAssertLessThan(mean, 45, "\(t): about 25-45 s with average taps (\(mean))")
        }
        let (p, _) = PuddleGoldenTests.race(seed: 1, course: .puddle)
        XCTAssertLessThan(p.player.finishTime!, 20, "the Puddle is the sprint it was")
    }

    /// The corner rule: the safe speed grows with radius and with skill; the trip chance is zero at or under it and grows above it; bumps bite the unfocused.
    func testCornerRuleShape() {
        XCTAssertGreaterThan(CourseTuning.cornerSpeed(radius: 10), CourseTuning.cornerSpeed(radius: 4))
        let starter = RacerStats(waddle: 0.4, focus: 0.4), trained = RacerStats(waddle: 0.85, focus: 0.75), full = RacerStats(waddle: 1, focus: 1)
        for r in [Float(4), 5, 7, 10] {
            XCTAssertGreaterThan(CourseTuning.safeSpeed(radius: r, stats: trained), CourseTuning.safeSpeed(radius: r, stats: starter), "skill raises the safe speed")
            XCTAssertEqual(CourseTuning.cornerTrip(pace: CourseTuning.safeSpeed(radius: r, stats: starter) * 0.99, radius: r, stats: starter), 0, "under the safe speed: no corner trip")
            XCTAssertGreaterThan(CourseTuning.cornerTrip(pace: 1.3, radius: r, stats: starter), CourseTuning.cornerTrip(pace: 1.3, radius: r, stats: trained), "skill lowers the chance")
            XCTAssertEqual(CourseTuning.cornerTrip(pace: 2, radius: r, stats: full), 0, "fully trained: never")
            XCTAssertGreaterThan(CourseTuning.cornerTrip(pace: 1.3, radius: r, stats: starter), CourseTuning.cornerTrip(pace: 1.1, radius: r, stats: starter), "faster is riskier")
        }
        // waddle and focus each count
        XCTAssertGreaterThan(CourseTuning.safeSpeed(radius: 5, stats: RacerStats(waddle: 0.8, focus: 0.4)), CourseTuning.safeSpeed(radius: 5, stats: starter))
        XCTAssertGreaterThan(CourseTuning.safeSpeed(radius: 5, stats: RacerStats(waddle: 0.4, focus: 0.8)), CourseTuning.safeSpeed(radius: 5, stats: starter))
        XCTAssertGreaterThan(CourseTuning.bumpTrip(stats: RacerStats(waddle: 0.5, focus: 0.2)), CourseTuning.bumpTrip(stats: RacerStats(waddle: 0.5, focus: 0.6)))
        XCTAssertLessThan(CourseTuning.bumpTrip(stats: RacerStats(waddle: 0.5, focus: 0.9)), 0.001, "a focused Jelly hardly notices a bump")
        XCTAssertEqual(CourseTuning.hazard(course: .puddle, at: 5, pace: 2, stats: starter), 0, "no hazard on the straight")
        XCTAssertGreaterThan(CourseTuning.hazard(course: .wave, at: 6, pace: 1.1, stats: starter), 0, "a hairpin at speed")
        XCTAssertGreaterThan(CourseTuning.hazard(course: .splash, at: 2.5 + 7 * .pi / 3 + 0.5, pace: 0.5, stats: RacerStats(waddle: 0.5, focus: 0.3)), 0, "a bump")
        // rivals: a focused rival eases off for a bend (longer step period), an unfocused one does not; nobody brakes on a straight
        XCTAssertEqual(CourseTuning.rivalBrake(course: .puddle, at: 5, stats: starter, nominal: 1.2), 1)
        XCTAssertGreaterThan(CourseTuning.rivalBrake(course: .wave, at: 6, stats: RacerStats(waddle: 0.6, focus: 0.9), nominal: 1.2), 1.05)
        XCTAssertEqual(CourseTuning.rivalBrake(course: .wave, at: 6, stats: RacerStats(waddle: 0.6, focus: 0), nominal: 1.2), 1)
    }

    /// Headless, same taps: the trained Jelly beats the untrained one and trips fewer times on every course across seeds; an untrained Jelly trips
    /// more per step on the Wave than on the Puddle, and a trained one hardly ever in a corner.
    func testTrainedBeatsUntrainedAndTripsLessOnEveryCourse() {
        let starter = RacerStats(waddle: 0.40, focus: 0.40), trained = RacerStats(waddle: 0.85, focus: 0.75)
        let rivals = [Rival(name: "A", tint: .one, stats: RacerStats(waddle: 0.5, focus: 0.5)), Rival(name: "B", tint: .one, stats: RacerStats(waddle: 0.6, focus: 0.6))]
        var perStep: [CourseTier: Double] = [:], perRace: [CourseTier: (Double, Double)] = [:]
        for t in Self.tiers {
            let c = RaceCourse.course(t)
            var faster = 0, tripsU = 0, tripsT = 0, stepsU = 0, cornerU = 0, cornerT = 0
            let seeds = UInt64(1)...30
            for seed in seeds {
                let u = PuddleGoldenTests.race(seed: seed, player: starter, taps: 5, course: c, rivals: rivals).sim
                let tr = PuddleGoldenTests.race(seed: seed, player: trained, taps: 5, course: c, rivals: rivals).sim
                XCTAssertNotNil(u.player.finishTime, "\(t) seed \(seed): the starter finishes"); XCTAssertNotNil(tr.player.finishTime)
                if (tr.player.finishTime ?? 99) < (u.player.finishTime ?? 99) { faster += 1 }
                tripsU += u.player.tap.trips; tripsT += tr.player.tap.trips; stepsU += u.player.stepCount
                cornerU += u.player.cornerTrips; cornerT += tr.player.cornerTrips
                for r in u.racers.dropFirst() { XCTAssertGreaterThan(r.dist, 0, "\(t): rivals run") }
            }
            XCTAssertEqual(faster, seeds.count, "\(t): the trained Jelly wins the same-taps race on every seed")
            XCTAssertGreaterThan(tripsU, tripsT * 3, "\(t): untrained trips \(tripsU) vs trained \(tripsT) over 30 races")
            perStep[t] = Double(tripsU) / Double(stepsU)
            perRace[t] = (Double(tripsU) / 30, Double(tripsT) / 30)
            print("COURSE trips \(t): starter \(Double(tripsU) / 30)/race (\(cornerU) in corners), trained \(Double(tripsT) / 30)/race (\(cornerT) in corners)")
            if !c.isStraight { XCTAssertGreaterThan(cornerU, cornerT * 2, "\(t): corners catch the untrained far more") }
            if t == .wave { XCTAssertLessThan(Double(tripsT) / 30, 1.0, "a trained Jelly rarely trips on the Wave (\(Double(tripsT) / 30) a race)") }
        }
        XCTAssertGreaterThan(perStep[.wave]!, perStep[.puddle]! * 1.25, "an untrained Jelly trips more per step on the Wave (\(perStep[.wave]!)) than on the Puddle (\(perStep[.puddle]!))")
        XCTAssertGreaterThan(perRace[.wave]!.0, perRace[.puddle]!.0 * 2, "and far more per race")
        XCTAssertGreaterThan(perRace[.ripple]!.0, perRace[.puddle]!.0, "gentle curves already catch a starter a little more")
    }

    /// Rivals keep the same rules: on the Wave, higher-ranked (trained) rivals trip less than a starter field, and tapping slower in a bend keeps the player safer.
    func testRivalsObeyTheCornerRuleAndSlowTapsAreSafer() {
        func fieldTrips(_ stats: RacerStats) -> Int {
            var n = 0
            for seed in UInt64(1)...20 {
                let rivals = [Rival(name: "A", tint: .one, stats: stats), Rival(name: "B", tint: .one, stats: stats)]
                let s = PuddleGoldenTests.race(seed: seed, player: RacerStats(waddle: 0.7, focus: 0.7), taps: 5, course: .wave, rivals: rivals).sim
                n += s.racers.dropFirst().reduce(0) { $0 + $1.tap.trips }
            }
            return n
        }
        let weak = fieldTrips(RacerStats(waddle: 0.4, focus: 0.3)), strong = fieldTrips(RacerStats(waddle: 0.85, focus: 0.8))
        XCTAssertGreaterThan(weak, strong * 3, "untrained rivals trip \(weak), trained \(strong)")
        // the Wave fields rank-scaled rivals: at least the floor
        for seed in UInt64(1)...10 {
            for r in LocalRivalSource().rivals(count: 2, player: RacerStats(waddle: 0.3, focus: 0.3), playerTint: JellyRoster.tint(0), seed: seed, tier: .wave) {
                XCTAssertGreaterThanOrEqual(r.stats.waddle, LocalRivalSource.floor(.wave).waddle); XCTAssertGreaterThanOrEqual(r.stats.focus, LocalRivalSource.floor(.wave).focus)
            }
            XCTAssertEqual(LocalRivalSource().rivals(count: 2, player: RacerStats(waddle: 0.5, focus: 0.5), playerTint: JellyRoster.tint(0), seed: seed, tier: .puddle),
                           LocalRivalSource().rivals(count: 2, player: RacerStats(waddle: 0.5, focus: 0.5), playerTint: JellyRoster.tint(0), seed: seed), "the Puddle's rivals are unchanged")
        }
        // tapping slower through the Wave (a pace under the hairpins' safe speed) trips less than flat out, for the same starter
        func trips(taps: Float) -> Int { (1...20).reduce(0) { $0 + PuddleGoldenTests.race(seed: UInt64($1), player: RacerStats(waddle: 0.4, focus: 0.4), taps: taps, course: .wave, rivals: []).sim.player.tap.trips } }
        let flat = trips(taps: 5), eased = trips(taps: 2.2)
        XCTAssertGreaterThan(flat, eased, "flat out \(flat) trips vs eased \(eased)")
    }

    /// The final-stretch music still comes in near the line on every course.
    func testFinalStretchMusicNearTheFinishOnEveryCourse() {
        for t in Self.tiers {
            let f = RaceFlow()
            f.cue = { _ in }; f.drillCue = { _ in }; f.autoRate = 6
            f.progress.records[.puddle] = CourseProgress.Record(races: 9, wins: 9, topTwo: 9); f.progress.records[.ripple] = f.progress.records[.puddle]; f.progress.records[.splash] = f.progress.records[.puddle]
            f.begin(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.9, focus: 1), playerTint: JellyRoster.tint(0), rivalCount: 2, seed: 3, course: t)
            var sawRace = false, sawFinal = false, finalAt: Float?
            for _ in 0..<(60 * 120) {
                _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true })
                if f.musicScene == .race { sawRace = true }
                if f.musicScene == .raceFinal, finalAt == nil { finalAt = f.sim!.racers.map(\.dist).max(); sawFinal = true }
                if f.hasResults { break }
            }
            XCTAssertTrue(sawRace && sawFinal, "\(t): race music, then the final stretch")
            XCTAssertEqual(finalAt ?? 0, f.course.length - RaceTuning.finalStretch, accuracy: 0.6, "\(t): the cue comes in \(RaceTuning.finalStretch) u from the line")
            XCTAssertEqual(f.musicScene, .results)
            XCTAssertEqual(f.sim?.course.tier, t)
        }
    }
}

// MARK: - progression

@MainActor
final class CourseProgressionTests: XCTestCase {
    func testPrizesRisePerTier() {
        XCTAssertEqual([1, 2, 3].map { RaceTuning.drops(place: $0, tier: .puddle) }, [12, 7, 4])
        XCTAssertEqual([1, 2, 3].map { RaceTuning.drops(place: $0, tier: .ripple) }, [15, 9, 5])
        XCTAssertEqual([1, 2, 3].map { RaceTuning.drops(place: $0, tier: .splash) }, [18, 11, 7])
        XCTAssertEqual([1, 2, 3].map { RaceTuning.drops(place: $0, tier: .wave) }, [22, 13, 8])
        for p in 1...3 { for t in CourseTier.allCases.dropFirst() { XCTAssertGreaterThan(RaceTuning.drops(place: p, tier: t), RaceTuning.drops(place: p, tier: t.below!)) } }
        XCTAssertEqual(RaceTuning.drops(place: 7, tier: .wave), 8)
        XCTAssertEqual(CourseTier.allCases.map(\.className), ["Starter", "Rookie", "Pro", "Champion"])
        XCTAssertEqual(CourseTier.wave.below, .splash); XCTAssertNil(CourseTier.puddle.below); XCTAssertNil(CourseTier.wave.above)
    }

    func testUnlocksByAWinOrThreeTopTwos() {
        let p = CourseProgress()
        XCTAssertEqual(p.unlockedTiers, [.puddle])
        XCTAssertNotNil(p.requirement(.ripple)); XCTAssertNil(p.requirement(.puddle))
        p.record(tier: .puddle, place: 3)
        XCTAssertEqual(p.unlockedTiers, [.puddle], "a 3rd opens nothing")
        p.record(tier: .puddle, place: 2); p.record(tier: .puddle, place: 2)
        XCTAssertEqual(p.unlockedTiers, [.puddle]); XCTAssertTrue(p.requirement(.ripple)!.contains("1 more time"))
        p.record(tier: .puddle, place: 2)
        XCTAssertEqual(p.unlockedTiers, [.puddle, .ripple], "three top-two finishes open the next course")
        XCTAssertFalse(p.unlocked(.splash), "only the next one")
        p.record(tier: .ripple, place: 1)
        XCTAssertEqual(p.unlockedTiers, [.puddle, .ripple, .splash], "a win opens the next course at once")
        XCTAssertEqual(p.record(.ripple).wins, 1); XCTAssertEqual(p.record(.ripple).topTwo, 1); XCTAssertEqual(p.record(.puddle).races, 4)
        p.record(tier: .splash, place: 1)
        XCTAssertEqual(p.unlockedTiers, CourseTier.allCases)
    }

    func testProgressSavesAndDecodesAndAnEmptySaveIsThePuddle() {
        let d = UserDefaults(suiteName: "CourseProgress.\(UUID().uuidString)")!
        let p = CourseProgress(persists: true, defaults: d)
        XCTAssertEqual(p.unlockedTiers, [.puddle], "a fresh install: nothing saved, the Puddle only")
        p.record(tier: .puddle, place: 1); p.record(tier: .ripple, place: 2)
        p.chosen = .ripple
        let q = CourseProgress(persists: true, defaults: d)
        XCTAssertEqual(q.record(.puddle), CourseProgress.Record(races: 1, wins: 1, topTwo: 1))
        XCTAssertEqual(q.record(.ripple), CourseProgress.Record(races: 1, wins: 0, topTwo: 1))
        XCTAssertEqual(q.chosen, .ripple, "the picked course comes back")
        // garbage / older saves decode to nothing won
        d.set(Data([1, 2, 3]), forKey: CourseProgress.key); d.set("lagoon", forKey: CourseProgress.chosenKey)
        let r = CourseProgress(persists: true, defaults: d)
        XCTAssertEqual(r.unlockedTiers, [.puddle]); XCTAssertEqual(r.chosen, .puddle)
        // a chosen course that is not open is not restored
        d.removeObject(forKey: CourseProgress.key); d.set("wave", forKey: CourseProgress.chosenKey)
        XCTAssertEqual(CourseProgress(persists: true, defaults: d).chosen, .puddle)
        // tests' flows do not persist
        XCTAssertEqual(RaceFlow().courseTier, .puddle)
    }

    /// The flow: a race settles its result into the progress, pays the course's prize, and says what it unlocked; a locked pick falls back to the Puddle.
    func testTheFlowRecordsProgressPaysTheTierAndRefusesLockedCourses() {
        struct Slow: RivalSource { func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64) -> [Rival] { (0..<count).map { Rival(name: "R\($0)", tint: .one, stats: RacerStats(waddle: 0.15, focus: 1)) } } }
        func run(_ f: RaceFlow, course: CourseTier? = nil) {
            f.begin(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.9, focus: 1), playerTint: JellyRoster.tint(0), rivalCount: 2, seed: 5, course: course)
            for _ in 0..<(60 * 120) { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); if f.hasResults { break } }
            XCTAssertTrue(f.hasResults)
            f.goHome()
            for _ in 0..<400 { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
            XCTAssertFalse(f.active)
        }
        let w = DropsWallet(persists: false)
        let f = RaceFlow(); f.rivalSource = Slow(); f.cue = { _ in }; f.drillCue = { _ in }; f.autoRate = 6; f.wallet = w
        f.courseTier = .wave
        run(f)
        XCTAssertEqual(f.progress.record(.puddle).wins, 1, "Wave was locked: the race ran on the Puddle")
        XCTAssertEqual(w.count, 12, "paid the Puddle's prize")
        XCTAssertEqual(f.unlockedNow, .ripple, "and opened the Ripple")
        f.courseTier = .ripple
        run(f)
        XCTAssertEqual(f.progress.record(.ripple).wins, 1); XCTAssertEqual(w.count, 12 + 15, "the Ripple pays 15 for a win")
        XCTAssertEqual(f.unlockedNow, .splash)
        run(f, course: .splash)
        XCTAssertEqual(w.count, 12 + 15 + 18); XCTAssertEqual(f.unlockedNow, .wave)
        run(f, course: .wave)
        XCTAssertEqual(w.count, 12 + 15 + 18 + 22); XCTAssertNil(f.unlockedNow, "nothing left to open")
        XCTAssertEqual(f.progress.unlockedTiers, CourseTier.allCases)
        // GameCare's pick refuses a locked course and takes an open one
        let care = GameCare(jellyCount: 1, persistent: false)
        XCTAssertFalse(care.chooseCourse(.wave)); XCTAssertEqual(care.race.courseTier, .puddle)
        care.race.progress.record(tier: .puddle, place: 1)
        XCTAssertTrue(care.chooseCourse(.ripple)); XCTAssertEqual(care.race.courseTier, .ripple)
    }
}

// MARK: - the follow camera

@MainActor
final class RaceFollowCameraTests: XCTestCase {
    private func ndc(_ cam: CameraState, _ p: SIMD3<Float>) -> SIMD3<Float>? {
        let c = cam.viewProj * SIMD4<Float>(p.x, p.y, p.z, 1)
        guard c.w > 1e-4 else { return nil }
        return SIMD3(c.x / c.w, c.y / c.w, c.z / c.w)
    }

    /// Portrait and landscape: along every curved course the player and the leader (a body high) stay on screen, the eye rides above the gantry and
    /// the trees, the bank is small and into the turn, and the Puddle keeps its fixed frame.
    func testFollowFramesTheRacersInPortraitAndLandscapeAndClearsTheScenery() {
        let aspects: [(String, Float)] = [("portrait", 440.0 / 956.0), ("landscape", 956.0 / 440.0), ("ipad", 1194.0 / 834.0)]
        for t in [CourseTier.ripple, .splash, .wave] {
            let c = RaceCourse.course(t)
            var follow: RaceFollowPose?
            var maxBank: Float = 0, bankSigns = 0
            var s: Float = 0
            while s < c.length {
                let player = RaceFollowPose.Racer(pos: c.lanePoint(1, at: s), s: s, isPlayer: true)
                let lead = RaceFollowPose.Racer(pos: c.lanePoint(0, at: min(s + 2.5, c.length)), s: min(s + 2.5, c.length), isPlayer: false)
                let want = RaceFollowPose.aim(course: c, racers: [player, lead])
                follow = follow.map { $0.smoothed(toward: want, dt: 1 / 60) } ?? want
                let f = follow!
                XCTAssertLessThanOrEqual(abs(f.bank), RaceFollowPose.bankMax + 1e-4)
                maxBank = max(maxBank, abs(f.bank))
                let curv = c.curvature(at: s)
                if abs(curv) > 0.1, abs(f.bank) > 0.01 { if (f.bank > 0) == (curv > 0) { bankSigns += 1 } else { bankSigns -= 1 } }
                for (name, a) in aspects {
                    let cam = GameCamera.camera(aspect: a, race: 1, raceFollow: f)
                    XCTAssertGreaterThan(cam.pos.y, RaceModels.gantryHeight + 0.6, "\(t) \(name): the eye clears the gantry and the trees (s \(s))")
                    for who in [player.pos, lead.pos] { for y in [Float(0), 1.4] {
                        guard let n = ndc(cam, SIMD3(who.x, y, who.y)) else { XCTFail("\(t) \(name): a racer behind the camera at s \(s)"); continue }
                        XCTAssertLessThanOrEqual(abs(n.x), 0.95, "\(t) \(name): racer on screen x (s \(s))"); XCTAssertLessThanOrEqual(abs(n.y), 0.95, "\(t) \(name): racer on screen y (s \(s))")
                    } }
                    XCTAssertGreaterThan(cam.pos.y, 5, "the eye is above every bush and tree")
                }
                s += 0.1
            }
            XCTAssertGreaterThan(maxBank, 0.01, "\(t): it banks in the bends")
            XCTAssertGreaterThan(bankSigns, 0, "\(t): into the turn")
        }
        // the Puddle: no follow pose, the fixed frame is exactly racePose
        let a: Float = 440.0 / 956.0
        let fixed = GameCamera.camera(aspect: a, race: 1), p = GameCamera.racePose(aspect: a)
        XCTAssertEqual(fixed.pos, p.eye)
        XCTAssertEqual(RaceFollowPose.distance(aspect: 956.0 / 440.0), RaceFollowPose.distance(aspect: GameCamera.landscapeFramingAspect), "landscape keeps the framing height")
        // smoothing converges and keeps the direction unit length
        var f = RaceFollowPose(target: SIMD3(0, 0.45, 0), toEye: SIMD2(0, 1), bank: 0)
        let want = RaceFollowPose(target: SIMD3(3, 0.45, 2), toEye: SIMD2(1, 0), bank: 0.05)
        for _ in 0..<300 { f = f.smoothed(toward: want, dt: 1 / 60); XCTAssertEqual(simd_length(f.toEye), 1, accuracy: 1e-3) }
        XCTAssertEqual(f.target, want.target); XCTAssertEqual(f.bank, want.bank, accuracy: 1e-4); XCTAssertEqual(f.toEye.x, 1, accuracy: 1e-3)
    }

    /// GameCare hands the stage a follow pose only on a curved course while the track is up.
    func testTheGlueFollowsOnlyCurvedCourses() {
        let care = GameCare(jellyCount: 1, persistent: false)
        XCTAssertNil(care.raceFollow([], dt: 1 / 60), "no race")
        care.race.cue = { _ in }
        care.race.begin(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.5, focus: 0.5), playerTint: JellyRoster.tint(0), rivalCount: 0, seed: 1)
        for _ in 0..<120 { _ = care.race.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
        XCTAssertTrue(care.race.trackVisible)
        XCTAssertNil(care.raceFollow([], dt: 1 / 60), "the Puddle keeps its fixed frame")
        care.race.abort()
        care.race.progress.records[.puddle] = CourseProgress.Record(races: 1, wins: 1, topTwo: 1)
        care.race.begin(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.5, focus: 0.5), playerTint: JellyRoster.tint(0), rivalCount: 0, seed: 1, course: .ripple)
        for _ in 0..<120 { _ = care.race.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
        XCTAssertEqual(care.race.sim?.course.tier, .ripple)
        XCTAssertNil(care.raceFollow([], dt: 1 / 60), "no bodies listed yet: nothing to aim at")
        care.race.abort()
    }
}
