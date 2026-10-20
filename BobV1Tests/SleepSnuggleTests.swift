//
//  SleepSnuggleTests.swift
//  Snuggling (BlobBrain+Sleep.swift): an awake Jelly sometimes comes to lie beside one who is already asleep (any time of day, with a cooldown),
//  never inside him, sometimes with a sleepy hand-hold (the nearest arm nubs reach out a little and touch, capped and attached, released when either
//  wakes) or turned toward him (cuddle), breathing together; never in a race.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SleepSnuggleTests: XCTestCase {
    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
    }
    override func tearDown() {
        SleepTuning.holdChance = 0.4; SleepTuning.cuddleChance = 0.3
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    private func lab(_ seed: UInt64 = 5) -> SocialTests.Lab {
        let l = SocialTests.Lab(positions: [SIMD2(-0.5, 0.3), SIMD2(1.2, 0.9), SIMD2(2.2, -1.2)], quiet: true, seed: seed)
        for r in l.rigs { r.skinner.autoBlink = false; r.brain.sleepEnabled = true }
        return l
    }
    private func tick(_ l: SocialTests.Lab) {
        l.tick(watching: false)
        for r in l.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
    }
    /// Rig 0 asleep on his back (daytime), the others awake and quiet.
    private func sleeperLab(_ seed: UInt64 = 5) -> SocialTests.Lab {
        let l = lab(seed)
        let s = l.rigs[0]
        s.brain.idleForced = true
        XCTAssertTrue(s.brain.idleStart(.sleep, s.sim)); s.brain.sleep.hold = 600
        var f = 0
        while !s.brain.isNapping && f < 60 * 25 { tick(l); f += 1 }
        XCTAssertTrue(s.brain.isNapping)
        return l
    }
    private func tipWorld(_ r: MotionRig, side: Int) -> SIMD3<Float> {
        let att = r.sim.attractor, sy = att.squash, sxz = 1 / sy.squareRoot()
        let RS = simd_float3x3(att.rotation) * simd_float3x3(diagonal: SIMD3(sxz, sy, sxz))
        var b = r.brain.armLastGeom[side].b
        if side == 0 { b.x = -b.x }                              // (the geometry is the +x arm's; the -x arm is its mirror)
        return att.anchor - RS * r.sim.restCentroid + RS * (b + SIMD3(side == 0 ? -r.brain.armLastGeom[side].r2 : r.brain.armLastGeom[side].r2, 0, 0))
    }

    func testHandSpacingIsAtLeastTheBodyGap() {
        let r = MotionRig(game: true); SleepBackTests.keep.append(r)
        let s = r.brain.handSpacing()
        MotionLog.write("SNUGGLE hand spacing \(s)")
        XCTAssertGreaterThanOrEqual(s, SleepTuning.minGap)
        XCTAssertLessThanOrEqual(s, 2.2)
    }

    func testJoiningASleeperHappensSometimesWithACooldown() {
        let l = sleeperLab()
        l.rigs[0].brain.idleState.t = 100                         // (not freshly down: the older "join while he has just lain down" rule is out of the way)
        let b = l.rigs[1].brain
        b.idleNight = 0.1
        var yes = 0, followUp = 0
        for _ in 0..<600 {
            b.snuggleCool = 0
            if b.sleepWanted() { yes += 1 }
            if b.sleepWanted() { followUp += 1 }                 // asked again at once: the cooldown holds
        }
        XCTAssertEqual(followUp, 0, "a roll starts a cooldown")
        XCTAssertGreaterThan(b.snuggleCool, 70)
        XCTAssertGreaterThan(yes, 10, "sometimes"); XCTAssertLessThan(yes, 120, "rarely by day (~6 %)")
        b.idleNight = 0.25                                       // evening: mildly tired
        var tired = 0
        for _ in 0..<600 { b.snuggleCool = 0; if b.sleepWanted() { tired += 1 } }
        XCTAssertGreaterThan(tired, 120); XCTAssertLessThan(tired, 260)
        // nobody asleep: no snuggling
        let c = l.rigs[2].brain
        l.rigs[0].brain.sleepWake(groggy: false)
        for _ in 0..<200 { tick(l) }
        c.idleNight = 0; c.snuggleCool = 0
        XCTAssertFalse((0..<100).contains { _ in c.snuggleCool = 0; return c.sleepWanted() }, "nobody asleep: nothing to join")
    }

    func testNotInARaceOrWhileLocked() {
        let l = sleeperLab()
        l.rigs[0].brain.idleState.t = 100
        let b = l.rigs[1].brain
        b.idleNight = 0.25
        b.race.active = true
        for _ in 0..<300 { b.snuggleCool = 0; XCTAssertFalse(b.sleepWanted()) }
        b.race.active = false; b.sleepLocked = true
        for _ in 0..<300 { b.snuggleCool = 0; XCTAssertFalse(b.sleepWanted()) }
    }

    func testJoinerWalksOverLiesBesideNeverOverlapsAndHoldsHands() {
        SleepTuning.holdChance = 1
        let l = sleeperLab()
        let s = l.rigs[0], j = l.rigs[1]
        j.brain.idleForced = true
        XCTAssertTrue(j.brain.idleStart(.sleep, j.sim))
        XCTAssertEqual(j.brain.sleep.mode, .hold)
        XCTAssertTrue(j.brain.sleep.partner === s.brain)
        XCTAssertTrue(s.brain.sleep.partner === j.brain)
        var minGap = Float.infinity, maxHold: Float = 0, armsDrawn = 0, minTip = Float.infinity
        var capMax = 0.0
        var w = SocialTests.Watch(), w2 = SocialTests.Watch()
        for _ in 0..<(60 * 40) {
            tick(l)
            w.sample(j); w2.sample(s)
            if j.brain.sleep.stage >= 2 { minGap = min(minGap, simd_distance(j.brain.position, s.brain.position)) }
            maxHold = max(maxHold, j.brain.sleep.holdW)
            if j.brain.sleep.holdW > 0.99 && s.brain.sleep.holdW > 0.99 && j.brain.armG > 0.5 && s.brain.armG > 0.5 {
                armsDrawn += 1
                for (r, side) in [(j, j.brain.sleep.holdSide), (s, s.brain.sleep.holdSide)] {
                    let g = r.brain.armLastGeom[side]
                    capMax = max(capMax, ArmCap.exposed(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), r2: Double(g.r2)))
                }
                minTip = min(minTip, simd_distance(tipWorld(j, side: j.brain.sleep.holdSide), tipWorld(s, side: s.brain.sleep.holdSide)))
            }
            if armsDrawn > 120 { break }
        }
        MotionLog.write("SNUGGLE hold: min centre gap \(minGap), arms drawn \(armsDrawn), tip distance \(minTip), exposed max \(capMax), cap \(ArmCap.maximum)")
        XCTAssertGreaterThanOrEqual(minGap, SleepTuning.minGap - 0.02, "never inside each other")
        XCTAssertGreaterThan(armsDrawn, 100, "both sleepers reach out")
        XCTAssertLessThanOrEqual(capMax, ArmCap.maximum * 1.02, "stubby: the global arm cap holds")
        XCTAssertLessThan(minTip, 0.12, "the hands meet (outer tip edges touch)")
        XCTAssertNotEqual(j.brain.sleep.holdSide, s.brain.sleep.holdSide, "the near arms: opposite sides")
        // he wakes: the hold lets go at once, arms retract
        s.brain.sleepWake(groggy: false)
        for _ in 0..<(60 * 2) { tick(l) }
        XCTAssertLessThan(j.brain.sleep.holdW, 0.01, "released when the other wakes")
        XCTAssertLessThan(s.brain.sleep.holdW, 0.01)
        for _ in 0..<(60 * 8) { tick(l) }
        XCTAssertEqual(j.brain.armDirW, 0, accuracy: 0.001)
        w.check("joiner snuggling"); w2.check("first sleeper holding hands")
    }

    func testCuddleTurnsTowardTheOtherAndTheyBreatheTogether() {
        SleepTuning.holdChance = 0; SleepTuning.cuddleChance = 1
        let l = sleeperLab()
        let s = l.rigs[0], j = l.rigs[1]
        j.brain.idleForced = true
        XCTAssertTrue(j.brain.idleStart(.sleep, j.sim))
        XCTAssertEqual(j.brain.sleep.mode, .cuddle)
        var maxLean: Float = 0, syncDiff: Float = 0, n = 0
        for _ in 0..<(60 * 40) {
            tick(l)
            maxLean = max(maxLean, j.brain.sleep.leanW)
            if j.brain.isNapping && s.brain.isNapping && j.brain.sleep.t > 3 {
                syncDiff = max(syncDiff, abs(j.brain.sleep.breath - s.brain.sleep.breath)); n += 1
            }
            if n > 300 { break }
        }
        XCTAssertGreaterThan(maxLean, 0.99, "leans in")
        XCTAssertLessThan(syncDiff, 0.05, "they breathe together")
        XCTAssertEqual(j.brain.sleep.holdW, 0, accuracy: 0.001, "a cuddle is not a hold")
        XCTAssertGreaterThan(simd_distance(j.brain.position, s.brain.position), SleepTuning.minGap - 0.02)
    }

    func testNoHoldWithoutBothAsleepAndNeverInARace() {
        let r = MotionRig(game: true); SleepBackTests.keep.append(r)
        r.skinner.autoBlink = false
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 500
        r.brain.sleep.mode = .hold                               // a hold wanted, but no partner
        for _ in 0..<(60 * 15) { r.tick(); XCTAssertEqual(r.brain.sleep.holdW, 0, accuracy: 0.0001) }
        // forced hold shows, then not while a race is on
        let r2 = MotionRig(game: true); SleepBackTests.keep.append(r2)
        r2.brain.idleForced = true
        XCTAssertTrue(r2.brain.idleStart(.sleep, r2.sim)); r2.brain.sleep.hold = 500; r2.brain.sleep.holdForce = true
        r2.run(25, until: { r2.brain.sleep.holdW > 0.99 })
        XCTAssertGreaterThan(r2.brain.sleep.holdW, 0.99)
        r2.brain.race.active = true
        for _ in 0..<150 { r2.tick() }
        XCTAssertLessThan(r2.brain.sleep.holdW, 0.01, "off in a race")
    }
}
