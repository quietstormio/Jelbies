//
//  RunMoveTests.swift
//  Build B running actions (2026-10-17): ZOOMIES (fast dash + dead stop + big wobble), BELLY SLIDE (run, dive, slide, pop up), HOP-SCOOT (a few bunny hops).
//  They must start, finish on their own, leave him upright and at rest, move him the right way, and keep the scheduler from spamming them.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RunMoveTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func rig(_ kind: IdleKind) -> MotionRig {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.brain.seed = 11
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(kind) starts")
        return r
    }

    func testEachMoveRunsToTheEndAndLeavesHimAtRest() {
        for kind in [IdleKind.zoomies, .slide, .scoot] {
            let r = rig(kind)
            let p0 = r.root, tilt0 = r.sim.bodyPose(iterations: 6).tilt
            var maxSpeed: Float = 0, last = p0, maxTilt: Float = 0, t: Float = 0
            r.run(14, until: { r.brain.idleState.kind == nil }) {
                maxSpeed = max(maxSpeed, simd_length(r.root - last) * 60); last = r.root
                maxTilt = max(maxTilt, r.sim.bodyPose(iterations: 3).tilt - tilt0)
                t = r.t
            }
            XCTAssertNil(r.brain.idleState.kind, "\(kind) finished")
            r.run(1.5)
            let pose = r.sim.bodyPose(iterations: 6)
            MotionLog.write(String(format: "RUNMOVE %@: moved %.2f u, peak root speed %.2f u/s, max tilt %.2f rad, ended after %.1f s, final tilt %.3f", "\(kind)", simd_length(r.root - p0), maxSpeed, maxTilt, t, pose.tilt))
            XCTAssertGreaterThan(simd_length(r.root - p0), kind == .scoot ? 0.8 : 1.5, "\(kind) travels")
            XCTAssertEqual(pose.tilt, tilt0, accuracy: 0.08, "\(kind): upright again")
            XCTAssertEqual(r.brain.zoomW, 0); XCTAssertEqual(r.brain.armDirW, 0)
            if kind == .slide { XCTAssertGreaterThan(maxTilt, 0.35, "he really goes down on his belly") }
        }
    }

    func testZoomiesAreFasterThanTheRun() {
        func peak(_ kind: IdleKind) -> Float {
            let r = rig(kind)
            var last = r.root, m: Float = 0
            r.run(14, until: { r.brain.idleState.kind == nil }) {
                if r.brain.runW > 0.99 { m = max(m, simd_length(r.root - last) * 60) }
                last = r.root
            }
            return m
        }
        let z = peak(.zoomies), n = peak(.run)
        MotionLog.write(String(format: "RUNMOVE zoomies peak %.2f u/s vs run %.2f u/s", z, n))
        XCTAssertGreaterThan(z, n * 1.1)
    }

    func testSchedulerPicksThemSparinglyAndNeverTwiceInARow() {
        var counts: [IdleKind: Int] = [:]
        var last: IdleKind?
        var x: UInt64 = 88172645463325252
        for _ in 0..<4000 {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17
            let k = IdleTable.pick(.happy, last: last, r: Float(x >> 40) / Float(1 << 24))
            counts[k, default: 0] += 1
            if k != .wander { XCTAssertNotEqual(k, last); last = k }
        }
        let specials = counts.filter { $0.key != .wander }.map(\.value).reduce(0, +)
        let new = [IdleKind.zoomies, .slide, .scoot].map { counts[$0] ?? 0 }
        MotionLog.write("RUNMOVE happy picks \(counts) new-move share \(Double(new.reduce(0, +)) / Double(specials))")
        for n in new { XCTAssertGreaterThan(n, 0) }
        XCTAssertLessThan(Double(new.reduce(0, +)) / Double(specials), 0.45, "run + jacks still dominate")
    }
}
