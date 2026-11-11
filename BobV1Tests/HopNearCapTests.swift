//
//  HopNearCapTests.swift
//  The hop onto a seat is never longer than `hopFar` + 0.3: a Jelbie who stands farther from the seat when the hop would start drops the sit.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HopNearCapTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { DecorField.shared.clear(); room() }
    override func tearDown() { DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    private func room() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }

    /// Starts a loveseat sit; when he arrives (stage 0 ready) he is moved `away` m from the seat (0: left where he is). Returns (hop started, the distance at take-off, finished).
    private func run(away: Float) -> (hopped: Bool, takeOff: Float, finished: Bool, startDist: Float) {
        room()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .loveseat, x: 2.8, z: 0.6)])
        let r = MotionRig(game: true); Self.keep.append(r)
        r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: SIMD2(-1.0, 1.0))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.decorSit, r.sim), "the sit starts")
        let f = DecorField.shared.foot(7)!
        let seatP = r.brain.hopSeatXZ(f, seat: r.brain.idleState.seat)
        var moved = false, hopped = false, takeOff: Float = -1, startDist: Float = -1, finished = false
        var prev = r.brain.position, trace = 0
        for _ in 0..<(60 * 40) {
            r.tick(); DecorField.shared.tick(dt: 1.0 / 60)
            let s = r.brain.idleState
            if s.kind == .decorSit, s.bagStage == 0, !s.decorGo, !moved, away > 0 {
                moved = true
                let to = seatP + SIMD2(-away, 0)
                r.sim.teleport(toXZ: to)
                for _ in 0..<30 { r.sim.step() }
                r.brain.currentPose(r.sim)
                r.brain.px = to.x; r.brain.pz = to.y          // (the brain's floor spot follows the body only on the next tick)
                startDist = simd_distance(r.brain.position, seatP)
            }
            if moved, trace < 40 { trace += 1; let c = r.sim.centroid(); print(String(format: "HOPNEAR-CAPTRACE tick %d stage %d kind %@ pos (%.2f, %.2f) centroid (%.2f, %.2f) seat (%.2f, %.2f)", trace, s.bagStage, "\(String(describing: s.kind))", r.brain.px, r.brain.pz, c.x, c.z, seatP.x, seatP.y)) }
            if s.kind == .decorSit, s.bagStage >= 1, !hopped { hopped = true; takeOff = simd_distance(prev, seatP) }
            if s.kind == nil, hopped || moved { finished = true }
            prev = r.brain.position
            if finished || (hopped && s.bagStage == 3) { break }
        }
        print(String(format: "HOPNEAR-CAP away %.1f moved %d start-dist %.2f hopped %d take-off %.2f finished %d", away, moved ? 1 : 0, startDist, hopped ? 1 : 0, takeOff, finished ? 1 : 0))
        return (hopped, takeOff, finished, startDist)
    }

    func testAJelbieTooFarFromTheSeatDropsTheSitInsteadOfHopping() {
        let far = run(away: 2.6)
        XCTAssertGreaterThan(far.startDist, 2.3, "he really stands farther than the cap")
        XCTAssertFalse(far.hopped, "no hop across the room")
        XCTAssertTrue(far.finished, "the sit is dropped")
    }

    func testANormalApproachStillHopsOnWithinTheCap() {
        let ok = run(away: 0)
        XCTAssertTrue(ok.hopped, "the normal sit hops on")
        XCTAssertLessThanOrEqual(ok.takeOff, 2.3, "and never from farther than 2.3 m (\(ok.takeOff))")
    }
}
