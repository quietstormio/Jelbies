//
//  MotionHopTests.swift
//  HOP (small and cute): crouch 0.13 s, short air time with the feet tucked, landing squash then a jiggle. It is the only action that
//  may have both feet off the floor (everything else is held to the grounded tolerance in MotionGroundedTests).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionHopTests: XCTestCase {
    func testHopIsSmallAndOnlyItsAirPhaseLeavesTheFloor() {
        let r = MotionRig(game: false)
        r.brain.startHopPlay(sim: r.sim)
        let s = r.record(2.5)
        let tol = MotionScenario.tol
        let c0 = s.first!.root
        _ = c0
        let off = s.indices.filter { min(s[$0].gap[0], s[$0].gap[1]) > tol }
        XCTAssertFalse(off.isEmpty, "the hop leaves the floor")
        let t0 = s[off.first!].t
        // runs of both-feet-off steps: the first is the air phase, anything after landing is a small re-bounce of the jiggle
        var runs: [(Float, Float)] = []
        var rs = off.first!
        for k in 1..<off.count where off[k] != off[k - 1] + 1 { runs.append((s[rs].t, s[off[k - 1]].t)); rs = off[k] }
        runs.append((s[rs].t, s[off.last!].t))
        MotionLog.write("HOP both-feet-off runs (t0,t1): \(runs.map { String(format: "(%.2f, %.2f)", $0.0, $0.1) })")
        for rb in runs.dropFirst() { XCTAssertLessThan(rb.1 - rb.0, 0.10, "a re-bounce after landing is tiny"); XCTAssertLessThan(rb.0, runs[0].1 + 0.5) }
        let t1 = runs[0].1
        let air = t1 - t0
        let apex = (off.map { min(s[$0].gap[0], s[$0].gap[1]) }.max() ?? 0)
        MotionLog.write(String(format: "HOP: air %.3f s (both feet off), apex of the lower foot %.3f u = %.3f H, total %.2f s", air, apex, apex / MotionRig.H, s.last!.t))
        let late0 = s.filter { $0.t > t1 + 0.6 }
        MotionLog.write("HOP late0 \(late0.count) gap max \(late0.map { min($0.gap[0], $0.gap[1]) }.max() ?? -1) targets \(r.sim.targets.count)")
        XCTAssertGreaterThan(air, 0.15); XCTAssertLessThan(air, 0.40)
        XCTAssertLessThanOrEqual(apex, 0.20, "small hop")
        XCTAssertGreaterThanOrEqual(apex, 0.06)
        // after landing he is on the floor again (settled within 0.6 s)
        let late = s.filter { $0.t > t1 + 0.6 }
        XCTAssertFalse(late.isEmpty)
        XCTAssertLessThanOrEqual(late.map { min($0.gap[0], $0.gap[1]) }.max() ?? 0, tol)
        XCTAssertFalse(r.sim.hasNonFinite())
        XCTAssertTrue(r.sim.targets.isEmpty, "hop foot targets released")
    }

    /// The hop stays UPRIGHT (crouch = squash only, then a straight small hop and landing): the body tilt from vertical stays under 12 deg
    /// (no face-plant) and he keeps facing the way he started within 10 deg.
    func testHopStaysUprightAndFacingForward() {
        for game in [false, true] {
            for hops in 0..<3 {
                let r = MotionRig(game: game)
                r.renderSamples = false
                let yaw0 = r.poseYaw
                var tiltMax: Float = 0, yawDev: Float = 0, pitchFwd: Float = 0
                if hops == 2 { r.brain.request(.goTo(r.root + SIMD2(0, 0.7))); r.run(3.0, until: { r.brain.activity == .idle && r.t > 1.5 }) }     // right after a walk (feet were pinned)
                for _ in 0...hops { r.brain.startHopPlay(sim: r.sim, distance: hops == 0 ? 0 : 0.45); var n = 0; r.run(2.0, each: {
                    n += 1
                    let pose = r.sim.bodyPose(iterations: 4)
                    if n > 9 && r.brain.activity == .playing { tiltMax = max(tiltMax, pose.tilt) }       // the first 0.15 s is the game's idle tip-back relaxing to upright
                    yawDev = max(yawDev, abs(wrapPi(pose.yaw - yaw0)))
                    pitchFwd = max(pitchFwd, pose.rotation.act(SIMD3<Float>(0, 1, 0)).z)       // top leaning forward over the camera = face-plant
                }) }
                MotionLog.write(String(format: "HOP upright (%@ run %d): max tilt %.1f deg, max heading change %.1f deg, max forward lean %.1f deg", game ? "game" : "studio", hops, tiltMax * 57.3, yawDev * 57.3, asinf(pitchFwd) * 57.3))
                XCTAssertLessThan(tiltMax * 57.3, 12, "the hop never tips him over")
                XCTAssertLessThan(yawDev * 57.3, 10, "the hop keeps the heading")
                XCTAssertLessThan(asinf(pitchFwd) * 57.3, 8, "no forward nod / face-plant at any point of the hop or the hand-over back to idle")
            }
        }
    }
}
