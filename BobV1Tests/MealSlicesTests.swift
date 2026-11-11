//
//  MealSlicesTests.swift
//  Group-meal slices (branch dining-slices-r1). S1: a diner who has finished his share is released while another diner is still on his way.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MealSlicesTests: XCTestCase {
    struct Out { var ateAt: Float?; var releasedAt: Float?; var heldAtTrigger: Bool?; var trigger: Float? }

    /// Two diners, tray already out (`forcedOrigin`): diner 0 stands at his approach point and takes one piece; diner 1 is walking in and stays "not arrived" as far as the
    /// group can tell (the floor the group reads for him is a far point) until 2.5 s after diner 0's last bite, then he is let arrive. The group stays in `.approaching` until then.
    private func run(flag: Bool) -> Out {
        let saved = DiningGroup.releaseWhileComing
        DiningGroup.releaseWhileComing = flag
        defer { DiningGroup.releaseWhileComing = saved }
        let origin = SIMD2<Float>(0, 1.8)
        let L = DiningLayout.make(n: 2)
        let ap0 = SIMD2<Float>(origin.x + L.places[0].rel.x, origin.y + L.places[0].rel.y + GameCare.eatCloser - GameCare.approachBack)
        let lab = SocialTests.Lab(n: 2, positions: [ap0, SIMD2(1.5, -2.0)], quiet: true, seed: 5)
        for r in lab.rigs { r.brain.autonomy = false }
        let brains = lab.rigs.map(\.brain)
        var farFake = true
        let group = DiningGroup()
        group.tierOf = { _ in .normal }          // 1 piece each
        group.pay = { _, _ in }
        group.forcedOrigin = origin
        group.start(Consumables.berries, brains: brains, floor: { i in (i == 1 && farFake) ? SIMD2(1.5, -2.0) : lab.rigs[i].brain.position }, ids: [0, 1])
        var t: Float = 0
        var out = Out()
        var leg = 0
        let dt = lab.rigs[0].sim.stepDt
        while t < 30, group.isActive {
            // diner 1 keeps walking about far away (never idle for long, so the group does not give up on him)
            let b1 = brains[1]
            if farFake, b1.activity == .idle || b1.activity == .lookingAround || b1.activity == .steppingInPlace { leg += 1; b1.requestNow(.goTo(leg % 2 == 0 ? SIMD2(1.5, -2.0) : SIMD2(-1.5, -2.0))) }
            lab.tick(watching: false); group.tick(dt: dt); t += dt
            if out.ateAt == nil, group.dining.phase != .absent, group.dining.bitesLeft[group.placeOf[0]] <= DiningTiming.bitesPerServing - 1 { out.ateAt = t }
            if out.releasedAt == nil, group.isActive, !group.isHolding(0) { out.releasedAt = t }
            if let a = out.ateAt, out.trigger == nil, t >= a + 2.5 { out.trigger = t; out.heldAtTrigger = group.isHolding(0); farFake = false; break }
        }
        group.cancel(); group.dining.reset()
        return out
    }

    /// With the flag on, diner 0 is released within 1.5 s of his last bite, while diner 1 has not arrived.
    func testFinishedDinerIsReleasedWhileAnotherIsStillComing() {
        let off = ProcessInfo.processInfo.environment["MEALSLICES_FLAG_OFF"] != nil          // (to show the test fails with the flag off)
        let o = run(flag: !off)
        print("S1 flag=\(!off) \(o)")
        XCTAssertNotNil(o.ateAt, "diner 0 ate his share")
        XCTAssertNotNil(o.trigger, "the scenario reached its trigger (group still running 2.5 s after the last bite)")
        if let a = o.ateAt { XCTAssertNotNil(o.releasedAt, "released before the other diner arrived: \(o)"); if let r = o.releasedAt { XCTAssertLessThan(r - a, 1.5, "released within 1.5 s of the last bite (measured 1.03; the old flow holds him 2.5 s+): \(o)") } }
    }

    /// With the flag off nothing changes: diner 0 is still held 2.5 s after his last bite while diner 1 has not arrived.
    func testFlagOffKeepsHimHeld() {
        let o = run(flag: false)
        print("S1 flag=false \(o)")
        XCTAssertNotNil(o.ateAt, "diner 0 ate his share")
        XCTAssertNotNil(o.trigger, "the scenario reached its trigger")
        XCTAssertEqual(o.heldAtTrigger, true, "old behaviour: still held: \(o)")
        XCTAssertNil(o.releasedAt, "old behaviour: not released early: \(o)")
    }
}
