//
//  BallSolidTests.swift
//  Balls are solid (DecorField+BallContact.swift): a body walked into a ball ends outside its contact circle and the ball rolled on; a body dragged into a ball
//  pinned against a wall never overlaps it; two balls pushed together separate; the contact step costs next to nothing.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BallSolidTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { room(); DecorField.shared.clear(); DecorField.shared.bodies = []; SoccerState.shared.reset() }
    override func tearDown() { DecorField.shared.clear(); DecorField.shared.bodies = []; RoomLayout.ballSpheres = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    private func room() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0); GameCamera.refreshRoam(aspect: 440.0 / 956.0) }
    func gap(_ kind: DecorKind) -> Float { kind.rollRadius + RoomLayout.ballBodyGap(0.7) }

    /// A body model: moves at `v` along +x through the one floor resolver, then the field steps with it as a bumper.
    func walk(into kind: DecorKind) {
        DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: 0, z: 1.0)])
        var p = SIMD2<Float>(-2.2, 1.0), minD: Float = 9
        for _ in 0..<(60 * 4) {
            let q = RoomLayout.resolve(position: SIMD3(p.x + 1.3 / 60, 0, p.y), radius: 0.7)
            p = SIMD2(q.x, q.z)
            DecorField.shared.bodies = [(1, p)]
            DecorField.shared.tick(dt: 1.0 / 60)
            minD = min(minD, simd_distance(p, DecorField.shared.anim[7]!.pos))
        }
        XCTAssertGreaterThanOrEqual(minD, gap(kind) - 0.02, "\(kind): never inside the ball")
        XCTAssertGreaterThan(DecorField.shared.anim[7]!.pos.x, 0.6, "\(kind): the ball was pushed on")
    }
    func testABodyWalkedIntoAnyBallStopsAtItsSurfaceAndPushesItOn() {
        for k in [DecorKind.beachball, .soccerball, .ball, .yarnball] { walk(into: k) }
    }

    func testAWalkingJelbieInTheRealRigMeetsTheBeachBallWithoutPassingThrough() {
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .beachball, x: 0, z: 1.0)])
        let r = MotionRig(game: true); Self.keep.append(r)
        r.renderSamples = false; r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: SIMD2(-2.0, 1.0))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.script = .walk(target: SIMD2(2.0, 1.0), then: .none); r.brain.activity = .walking
        var minD: Float = 9
        r.run(8) {
            DecorField.shared.bodies = [(r.brain.steerID, r.brain.position)]
            DecorField.shared.tick(dt: 1.0 / 60)
            minD = min(minD, simd_distance(r.brain.position, DecorField.shared.anim[7]!.pos))
        }
        XCTAssertGreaterThanOrEqual(minD, gap(.beachball) - 0.05, "his root never gets inside the ball's contact circle")
    }

    func testDraggedIntoABallPinnedAgainstTheWallItNeverOverlaps() {
        let wallX = DecorPlacement.visibleHalf(z: 1.0) - 0.34
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .beachball, x: wallX - 0.05, z: 1.0)])
        DecorField.shared.tick(dt: 1.0 / 60)
        var minD: Float = 9
        for i in 0..<(60 * 3) {
            let x = -1.5 + Float(i) / 60 * 2.0          // the finger drags +x through the ball
            let q = RoomLayout.resolve(position: SIMD3(x, 0, 1.0), radius: 0.35)          // (the roam polygon's side clamp is a screen-edge rule on top of this)
            let p = SIMD2(q.x, q.z)
            DecorField.shared.bodies = [(1, p)]
            DecorField.shared.tick(dt: 1.0 / 60)
            minD = min(minD, simd_distance(p, DecorField.shared.anim[7]!.pos))
        }
        print("BALLS drag minD \(minD) ball \(DecorField.shared.anim[7]!.pos) wallX \(wallX) hw \(GameCamera.roamFloor?.halfWidth(at: 1.0) ?? -1)")
        XCTAssertGreaterThanOrEqual(minD, 0.34 + RoomLayout.ballBodyGap(0.35) - 0.02, "the held patch stops at the ball; the ball stops at the wall")
    }

    func testTwoBallsPushedTogetherSeparateAndTheRestingOneRolls() {
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .beachball, x: -1.0, z: 1.0), PlacedDecor(uid: 8, kind: .beachball, x: 0.0, z: 1.0)])
        DecorField.shared.kickBall(7, direction: SIMD2(1, 0), speed: 2.5)
        var minD: Float = 9
        for _ in 0..<(60 * 3) { DecorField.shared.tick(dt: 1.0 / 60); minD = min(minD, simd_distance(DecorField.shared.anim[7]!.pos, DecorField.shared.anim[8]!.pos)) }
        XCTAssertGreaterThanOrEqual(minD, 0.68 - 0.04, "the balls never overlap")
        XCTAssertGreaterThan(DecorField.shared.anim[8]!.pos.x, 0.5, "the struck ball rolled on")
    }

    func testTheContactStepIsCheapForThreeBodiesAndThreeBalls() {
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .beachball, x: -1, z: 1), PlacedDecor(uid: 8, kind: .soccerball, x: 0, z: 1), PlacedDecor(uid: 9, kind: .ball, x: 1, z: 1)])
        DecorField.shared.bodies = [(1, SIMD2(-2, 0.2)), (2, SIMD2(2, 0.1)), (3, SIMD2(0, 2.2))]
        DecorField.shared.ballContactStep(dt: 1.0 / 60)
        let n = 20000
        let t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<n { DecorField.shared.ballContactStep(dt: 1.0 / 60) }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000 / Double(n)
        print(String(format: "BALLS contact step %.5f ms (3 bodies, 3 balls)", ms))
        XCTAssertLessThan(ms, 0.05)
        var p = SIMD3<Float>(0.1, 0, 1.0)
        let t1 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<n { p = RoomLayout.resolve(position: p, radius: 0.7) }
        print(String(format: "BALLS resolve %.5f ms per call (3 balls)", (CFAbsoluteTimeGetCurrent() - t1) * 1000 / Double(n)))
    }
}
