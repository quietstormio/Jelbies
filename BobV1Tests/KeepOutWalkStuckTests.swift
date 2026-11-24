//
//  KeepOutWalkStuckTests.swift
//  no-stuck-r1: the soak's "motionless" case (iter0 seed 21: Jelly 2 "walking" with a job, 75 s without moving at the front of the room during Jelly 1's close-up).
//  Mechanism under test: a requested walk (a job) whose target lies inside the close-up's keep-out wedge while the walker is outside it: the floor rules push every step
//  out of the wedge, the job walk only re-plans (it never gives up), and the walker marks time at the wedge's edge until the close-up ends.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class KeepOutWalkStuckTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// Returns (seconds the walker was within 0.05 of one spot while walking, whether the job ended, the walker's final distance to the target).
    private func walkIntoWedge(dx: Float, dz: Float) -> (still: Float, ended: Bool, d: Float, log: String) {
        let r = FocusAnyRun(count: 3, peers: true); Self.keep.append(r); r.run(1)
        let a = GameCamera.callSpot
        r.place(1, at: SIMD2(a.x, a.y - 0.3)); r.place(2, at: SIMD2(a.x - 2.4, a.y + 1.2)); r.place(0, at: SIMD2(a.x + 2.4, a.y - 1.5))
        r.care.comeHere(jelly: 1)
        XCTAssertTrue(r.run(12) { r.care.focus.phase == .focused }, "Jelly 1's close-up")
        let b2 = r.actors[2].brain!
        let target = SIMD2(a.x + dx, a.y + dz)
        b2.requestNow(.goTo(target))
        r.run(0.5)
        var still: Float = 0, maxStill: Float = 0, last = b2.position, ended = false
        r.run(60) {
            if simd_distance(b2.position, last) < 0.05 { still += 1 / 60 } else { still = 0; last = b2.position }
            maxStill = max(maxStill, still)
            if b2.job == nil { ended = true }
            return false
        }
        let inWedge = r.care.focusKeepOutFor(2)?.contains(target, radius: b2.footprint) ?? false
        return (maxStill, ended, simd_distance(b2.position, target), "target in wedge=\(inWedge) pos=\(b2.position) script=\(b2.scriptKindName) job=\(String(describing: b2.job)) repicks=\(b2.stuckRepicks)")
    }

    /// A walk asked of a Jelmiko into the close-up's wedge must not leave him marking time: he arrives, or the walk is dropped, within ~10 s.
    func testJobWalkIntoTheWedgeDoesNotMarkTime() {
        for (dx, dz) in [(Float(0), Float(1.2)), (0.3, 1.8), (-0.3, 0.8)] {
            let res = walkIntoWedge(dx: dx, dz: dz)
            print("KEEPOUT-WALK dx=\(dx) dz=\(dz) still=\(res.still) ended=\(res.ended) d=\(res.d) \(res.log)")
            XCTAssertTrue(res.d < 0.4 || res.ended, "dx \(dx) dz \(dz): neither arrived nor gave up: \(res.log)")
            XCTAssertLessThan(res.still, 15, "dx \(dx) dz \(dz): stood \(res.still) s while walking: \(res.log)")
        }
    }
}
