//
//  SleepBackTests.swift
//  Sleeping on his back (BlobBrain+Sleep.swift): a Jelly yawns, rolls onto his back where he is, sleeps with his eyes shut, and rolls back over the
//  way he went down; a tap wakes him gently; sleepers snuggle into one row; deep night puts everybody to sleep; the sim sleeps with him. The feet
//  stay attached and the arms stubby through the roll over and back (FeetAttach / ArmCap, every frame).
//

import XCTest
import simd
@testable import BobV1

/// The face normal's height: +1 = face to the ceiling (on his back), 0 = upright, -1 = face down.
@MainActor private func faceUp(_ r: MotionRig) -> Float { r.sim.bodyPose(iterations: 4).rotation.act(SIMD3<Float>(0, 0, 1)).y }

@MainActor
final class SleepBackTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }          // the room as the game runs it
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    /// The face normal's height: +1 = face to the ceiling (on his back), 0 = upright, -1 = face down.

    private func sleeper(hold: Float = 3, at p: SIMD2<Float> = SIMD2(0, 0.2)) -> MotionRig {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.skinner.autoBlink = false
        r.sim.teleport(toXZ: p)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.seed = 11
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim))
        r.brain.sleep.hold = hold
        return r
    }

    func testRollsOntoHisBackSleepsAndRollsBackWithFeetAndArmsAttached() {
        let r = sleeper()
        var w = SocialTests.Watch()
        var maxUp: Float = -1, napFrames = 0, eyesClosedAtNap = false
        var stages: [Int] = []
        r.run(24, until: { r.brain.idleState.kind == nil && r.t > 4 }) {
            w.sample(r)
            if r.brain.idleState.kind == .sleep, stages.last != r.brain.sleep.stage { stages.append(r.brain.sleep.stage) }
            maxUp = max(maxUp, faceUp(r))
            if r.brain.isNapping { napFrames += 1; eyesClosedAtNap = r.skinner.openness.left < 0.15 }
        }
        MotionLog.write("SLEEPBACK stages \(stages), max face-up \(maxUp), nap frames \(napFrames), ended at t=\(r.t)")
        XCTAssertEqual(stages, [1, 2, 3, 4, 5], "yawn, lie down, asleep, roll back, stretch")
        XCTAssertGreaterThan(maxUp, 0.8, "on his back, tipped up about 60 degrees: the face looks up")
        XCTAssertGreaterThan(napFrames, 60, "he sleeps")
        XCTAssertTrue(eyesClosedAtNap, "eyes shut while he sleeps")
        XCTAssertNil(r.brain.idleState.kind, "awake again")
        XCTAssertLessThan(abs(faceUp(r)), 0.35, "back on his feet")
        XCTAssertLessThan(r.sim.bodyPose(iterations: 6).tilt, 0.4)
        XCTAssertEqual(r.skinner.openness.left, 1, accuracy: 0.01)
        w.check("sleep roll over and back")
    }

    func testSleepsWhereHeStandsNotInFrontOfTheTableOrBowls() {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        // in front of the water bowl / on the call spot: he walks to a clear rug spot first
        for p in [GameCamera.waterBowlSpot, GameCamera.callSpot, GameCamera.foodBowlSpot] {
            r.sim.teleport(toXZ: p)
            for _ in 0..<90 { r.sim.step() }
            r.brain.currentPose(r.sim)
            let c = r.brain.chooseSleepSpot()
            XCTAssertTrue(r.brain.sleepFloorOK(c.spot), "a clear rug spot for \(p): got \(c.spot)")
            XCTAssertFalse(r.brain.sleepFloorOK(p), "the \(p) spot itself is no place to lie")
        }
        r.sim.teleport(toXZ: SIMD2(0.3, 0.1))
        for _ in 0..<90 { r.sim.step() }
        r.brain.currentPose(r.sim)
        XCTAssertLessThan(simd_distance(r.brain.chooseSleepSpot().spot, r.brain.position), 0.01, "a good spot: he lies down right where he is")
    }

    func testTapWakesHimGentlyAndHeRollsBack() {
        let r = sleeper(hold: 500)
        r.run(12, until: { r.brain.isNapping })
        XCTAssertTrue(r.brain.isNapping)
        for _ in 0..<120 { r.tick() }
        XCTAssertGreaterThan(faceUp(r), 0.8)
        // a quick tap: 8 ticks of a finger on him
        for _ in 0..<8 { r.tick(touched: true) }
        XCTAssertNotEqual(r.brain.activity, .touched, "a tap is not a pick up")
        XCTAssertEqual(r.brain.sleep.stage, 4, "he starts rolling back")
        XCTAssertTrue(r.brain.sleep.groggy)
        r.run(8, until: { r.brain.idleState.kind == nil })
        XCTAssertNil(r.brain.idleState.kind)
        XCTAssertLessThan(abs(faceUp(r)), 0.35, "on his feet again")
    }

    func testAHeldFingerStillPicksHimUpAndHeRightsHimself() {
        let r = sleeper(hold: 500)
        r.run(12, until: { r.brain.isNapping })
        XCTAssertTrue(r.brain.isNapping)
        for _ in 0..<90 { r.tick(touched: true) }                 // 1.5 s of a finger: a real touch
        XCTAssertEqual(r.brain.activity, .touched)
        XCTAssertNil(r.brain.idleState.kind)
        r.run(12) { }
        XCTAssertLessThan(r.sim.bodyPose(iterations: 6).tilt, 0.4, "released on his back: the recover path rolls him up onto his feet")
    }

    func testAskedToWakeByARequestHeRollsBackFirst() {
        let r = sleeper(hold: 500)
        r.run(12, until: { r.brain.isNapping })
        r.brain.request(.goTo(SIMD2(1.0, 1.2)))
        r.run(10, until: { r.brain.idleState.kind == nil })
        XCTAssertNil(r.brain.idleState.kind)
        r.run(6) { }
        XCTAssertLessThan(abs(faceUp(r)), 0.35)
    }

    func testNappingJelliesJoinNoSocials() {
        let lab = SocialTests.Lab(quiet: true, seed: 5)
        let a = lab.rigs[0], b = lab.rigs[1]
        a.brain.idleForced = true
        XCTAssertTrue(a.brain.idleStart(.sleep, a.sim))
        a.brain.sleep.hold = 500
        for _ in 0..<(60 * 12) { lab.tick(watching: false) }
        XCTAssertTrue(a.brain.isNapping)
        for kind in [SocialKind.boop, .follow, .greet, .look, .squabble, .zoomies] {
            XCTAssertFalse(b.brain.socialStart(kind, with: a.brain, b.sim), "\(kind): not with a sleeper")
            XCTAssertFalse(a.brain.socialStart(kind, with: b.brain, a.sim), "\(kind): a sleeper starts none")
        }
        XCTAssertFalse(a.brain.socialFree)
    }

    func testSleepersSnuggleIntoOneRowTouchingNeverInsideEachOther() {
        let lab = SocialTests.Lab(positions: [SIMD2(-1.0, 0.6), SIMD2(0.7, 0.9), SIMD2(1.6, -1.2)], quiet: true, seed: 8)
        for r in lab.rigs { r.brain.sleepEnabled = true; r.brain.idleForced = true }
        XCTAssertTrue(lab.rigs[0].brain.idleStart(.sleep, lab.rigs[0].sim))
        for r in lab.rigs { r.brain.sleep.hold = 500 }
        lab.rigs[0].brain.sleep.hold = 500
        for _ in 0..<(60 * 6) { lab.tick(watching: false) }
        // the others get sleepy a few seconds after the first
        for i in 1..<3 { XCTAssertTrue(lab.rigs[i].brain.idleStart(.sleep, lab.rigs[i].sim), "rig \(i) goes to sleep"); lab.rigs[i].brain.sleep.hold = 500 }
        XCTAssertTrue(lab.rigs[1].brain.sleep.joined, "he heads for the pile")
        MotionLog.write("SLEEPBACK starts: \(lab.rigs.map { "stage \($0.brain.sleep.stage) spot \($0.brain.sleep.spot) joined \($0.brain.sleep.joined) pos \($0.brain.position)" })")
        for _ in 0..<(60 * 8) { lab.tick(watching: false) }
        MotionLog.write("SLEEPBACK after 8 s: \(lab.rigs.map { "stage \($0.brain.sleep.stage) tries \($0.brain.sleep.walkTries) pos \($0.brain.position) act \($0.brain.activity) script \($0.brain.script)" })")
        var minGap: Float = .infinity
        for f in 0..<(60 * 40) {
            lab.tick(watching: false)
            if f > 60 * 30 { minGap = min(minGap, min(lab.centreGap(0, 1), lab.centreGap(0, 2), lab.centreGap(1, 2))) }
        }
        XCTAssertTrue(lab.rigs.allSatisfy { $0.brain.isNapping }, "all three asleep: \(lab.rigs.map { $0.brain.sleep.stage })")
        let ps = lab.rigs.map { $0.brain.position }
        MotionLog.write("SLEEPBACK pile spots \(ps), min centre gap \(minGap)")
        for i in 0..<3 {
            let others = (0..<3).filter { $0 != i }.map { simd_distance(ps[i], ps[$0]) }
            XCTAssertGreaterThan(others.min()!, 1.5, "touching but not inside each other")
            XCTAssertLessThan(others.min()!, 2.0, "snuggled: against a neighbour")
            XCTAssertLessThan(others.max()!, 3.6, "one cluster")
        }
        XCTAssertGreaterThan(minGap, 1.45)
        // no jitter: every sleeper's sim is settled (so a real stage skips his step) and nobody drifts
        let p0 = lab.rigs.map { $0.root }
        for _ in 0..<120 { lab.tick(watching: false) }
        for (i, r) in lab.rigs.enumerated() {
            XCTAssertTrue(r.sim.isSettled, "rig \(i) is settled: his sim can sleep")
            XCTAssertLessThan(simd_distance(r.root, p0[i]), 0.01, "rig \(i) does not jitter or drift")
        }
    }

    /// Round 1022: deep night alone puts nobody to bed; "goodnight" does (asleep until morning); the morning wakes them.
    func testDeepNightAloneSleepsNobodyGoodnightDoesAndMorningWakesThem() {
        let lab = SocialTests.Lab(quiet: false, seed: 21)
        for r in lab.rigs {
            r.brain.sleepEnabled = true; r.brain.watching = true
            r.brain.idleNight = 1; r.brain.idleDeepNight = 1
            r.brain.idleState.cooldown = 0; r.brain.restTimer = 0.5; r.brain.socialBook.cooldown = 1e6
        }
        for _ in 0..<(60 * 70) { lab.tick(watching: false) }
        XCTAssertFalse(lab.rigs.contains { $0.brain.isSleeping }, "nobody chose bed by himself: \(lab.rigs.map { $0.brain.sleep.stage })")
        for r in lab.rigs { r.brain.commandedGoodnight = true }
        for _ in 0..<(60 * 70) { lab.tick(watching: false) }
        XCTAssertTrue(lab.rigs.allSatisfy { $0.brain.isNapping }, "all asleep after goodnight: \(lab.rigs.map { $0.brain.sleep.stage })")
        XCTAssertTrue(lab.rigs.allSatisfy { $0.brain.sleep.hold == NightRestTuning.untilMorning }, "until morning")
        // morning
        for r in lab.rigs { r.brain.idleNight = 0; r.brain.idleDeepNight = 0 }
        for _ in 0..<(60 * 40) { lab.tick(watching: false) }
        XCTAssertTrue(lab.rigs.allSatisfy { $0.brain.idleState.kind != .sleep }, "up in the morning: \(lab.rigs.map { String(describing: $0.brain.idleState.kind) })")
    }

    func testNappingMeansTheNeedsDrainScaleAndMusicRule() {
        let r = sleeper(hold: 500)
        XCTAssertFalse(r.brain.isNapping)
        XCTAssertEqual(r.brain.napDrainScale, 1)
        r.run(12, until: { r.brain.isNapping })
        XCTAssertTrue(r.brain.isNapping)
        XCTAssertEqual(r.brain.napDrainScale, NeedsTuning.napDrain)
    }

    // MARK: the sim sleeps with him

    func testBackSleeperSimSleepsAndWakesWithHim() {
        let sm = buildSimMesh(), rm = buildRenderMesh()
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let a = JellyActor(id: 0, name: "Bob", simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: SIMD2(0, 0.2))
        a.reset(drop: 0.35, shift: false)
        let b = BlobBrain.forGame()
        b.attach(renderMesh: rm, synchronous: true)
        b.autonomy = false; b.idleForced = true
        a.brain = b
        Self.keep.append(a)
        for _ in 0..<150 { a.sim.step() }
        b.currentPose(a.sim)
        func tick() -> Bool {
            b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false)
            a.skinner.jelly.tick(brain: b, sim: a.sim, dt: a.sim.stepDt)
            let stepped = a.updateSleep(forceAwake: false)
            if stepped { a.sim.step() }
            return stepped
        }
        XCTAssertTrue(b.idleStart(.sleep, a.sim)); b.sleep.hold = 500
        var n = 0
        while !b.isNapping && n < 60 * 20 { _ = tick(); n += 1 }
        XCTAssertTrue(b.isNapping)
        var steps = 0
        while !a.asleep && steps < 60 * 10 { _ = tick(); steps += 1 }
        XCTAssertTrue(a.asleep, "a Jelly lying on his back falls asleep too (took \(steps) steps)")
        let x0 = a.sim.x
        for _ in 0..<300 { XCTAssertFalse(tick(), "no sim step while he sleeps"); XCTAssertTrue(b.isNapping) }
        XCTAssertEqual(a.sim.x, x0, "his body does not move while he sleeps")
        // waking
        b.sleepWake(groggy: false)
        XCTAssertTrue(tick(), "woken the very step it happens")
        var awake = 0
        while b.idleState.kind == .sleep && awake < 60 * 20 { _ = tick(); awake += 1 }
        XCTAssertNil(b.idleState.kind)
    }

    // MARK: audio: quieter slurp and snore, sparser snoring

    func testSlurpAndSnoreGains() {
        XCTAssertEqual(SFX.slurp.gain, 0.85 * 0.6, accuracy: 0.001, "slurp is 0.6x its old gain")
        XCTAssertEqual(SFX.snore.gain, 0.5 * 0.35, accuracy: 0.001, "snore is 0.35x its old gain")
    }

    func testSnoresAreSparseAndNeverTwoAtOnce() {
        var s = SnoreScheduler()
        var rng = SystemRandomNumberGenerator()
        var times: [[Double]] = [[], [], []]
        var now = 1000.0
        while now < 1000 + 600 {
            for i in s.due(napping: [true, true, true], now: now, random: { Double.random(in: $0, using: &rng) }) { times[i].append(now) }
            now += 0.1
        }
        var all: [Double] = []
        for (i, t) in times.enumerated() {
            XCTAssertGreaterThan(t.count, 20, "jelly \(i) does snore")
            for k in 1..<t.count { XCTAssertGreaterThanOrEqual(t[k] - t[k - 1], 6 - 0.11, "at most one snore every 6 s per Jelly") }
            all += t
        }
        all.sort()
        for k in 1..<all.count { XCTAssertGreaterThanOrEqual(all[k] - all[k - 1], SnoreScheduler.hubGap - 0.11, "never two Jellies snoring at the same instant") }
        // a Jelly that wakes forgets his schedule
        var s2 = SnoreScheduler()
        _ = s2.due(napping: [true, false, false], now: 5, random: { $0.lowerBound })
        _ = s2.due(napping: [false, false, false], now: 6, random: { $0.lowerBound })
        XCTAssertEqual(s2.next[0], 0)
    }
}
