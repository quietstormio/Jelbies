//
//  MotionGroundedTests.swift
//  GROUNDED: in every sim step of wave / walk / step / turn / Call / spin / eat / idle, min(footBottomL, footBottomR) stays within
//  0.02 H of the floor (only the hop may have both feet off; see MotionHopTests), and the contact shadow stays under the planted foot.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionGroundedTests: XCTestCase {
    private func check(_ name: String, _ r: MotionRig, _ s: [MotionSample], skip: Float = 0) {
        let tol = MotionScenario.tol
        var worst: Float = 0, worstT: Float = 0, shadowWorst: Float = 0
        for x in s where x.t > skip {
            let g = min(x.gap[0], x.gap[1])
            if g > worst { worst = g; worstT = x.t }
            // the contact shadow sits under the body: the planted (lower) foot must lie under it (within the body's footprint)
            let k = x.gap[0] <= x.gap[1] ? 0 : 1
            shadowWorst = max(shadowWorst, simd_length(x.xz[k] - x.root))
        }
        MotionLog.write(String(format: "GROUNDED %@: worst gap %.4f H (t=%.2f)  planted-foot to root %.3f u  samples %d",
                               name, worst / MotionRig.H, worstT, shadowWorst, s.count))
        XCTAssertLessThanOrEqual(worst, tol, "\(name): both feet off the floor by \(worst / MotionRig.H) H at t=\(worstT)")
        // and what is DRAWN: the lowest rendered bean vertex of the planted foot is on the floor too
        let rWorst = s.filter { $0.t > skip }.map { min($0.rgap[0], $0.rgap[1]) }.max() ?? 0
        MotionLog.write(String(format: "GROUNDED %@: rendered worst gap %.4f H", name, rWorst / MotionRig.H))
        XCTAssertLessThanOrEqual(rWorst, tol, "\(name): the drawn feet are both off the floor")
        XCTAssertLessThanOrEqual(shadowWorst, 0.45, "\(name): planted foot left the body's shadow footprint")
        XCTAssertFalse(r.sim.hasNonFinite())
    }

    func testWaveGrounded() {
        for game in [false, true] { for side in [-1, 1] {
            let (r, s) = MotionScenario.wave(side: side, game: game)
            check("wave \(game ? "game" : "studio") side \(side)", r, s)
        } }
    }
    func testWalkGrounded() {
        for game in [false, true] { let (r, s) = MotionScenario.walk(game: game); check("walk \(game ? "game" : "studio")", r, s) }
    }
    func testStepTurnSpinGrounded() {
        var (r, s) = MotionScenario.step(); check("step", r, s)
        (r, s) = MotionScenario.turn(); check("turn", r, s)
        (r, s) = MotionScenario.turn(game: true, by: -2.4); check("turn game", r, s)
        (r, s) = MotionScenario.spin(); check("spin", r, s, skip: 0.4)
    }
    func testCallEatIdleGrounded() {
        var (r, s) = MotionScenario.call(); check("call", r, s)
        (r, s) = MotionScenario.eat(); check("eat", r, s)
        (r, s) = MotionScenario.idle(game: true); check("idle game", r, s)
        // the game's tip-back pivots on his feet: the back of his belly must not squash into the floor, and he is still on both feet
        let belly = r.sim.minY()
        MotionLog.write(String(format: "GROUNDED idle game: lowest body particle %.4f u above the floor (belly not squashed into it), pitch %.1f deg", belly, r.sim.bodyPose(iterations: 6).rotation.act(SIMD3<Float>(0, 1, 0)).z * -57.3))
        XCTAssertGreaterThanOrEqual(belly, -0.02, "game idle: nothing squashes into the floor")
        XCTAssertLessThanOrEqual(max(s.last!.gap[0], s.last!.gap[1]), 0.03 * MotionRig.H, "both feet down at idle")
        (r, s) = MotionScenario.idle(game: false); check("idle studio", r, s)
    }
}
