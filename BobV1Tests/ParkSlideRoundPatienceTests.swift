//
//  ParkSlideRoundPatienceTests.swift
//  park-slide-r2: the patience of a requested walk for a STANDING friend on its leg (BlobBrain.steerTarget). Home / ordinary requested walks keep 6 s (no give-up, no advance before it);
//  only the park slide's way-round legs (stage < 0) give up after 2 s, and only behind a standing friend.
//

import XCTest
import simd
@testable import BobV1

extension ParkSlideRoundTests {
    /// A rig whose leg (0,0) -> (0,4) is closed by a wall of standing friends (huge ids), so no route and no side-step exists.
    func wallRig() -> (MotionRig, SIMD2<Float>) {
        _ = OnePieceInvariantTests.configured
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        DecorField.shared.clear()
        let r = MotionRig(game: true, settle: 0.5)
        Self.keep.append(r)
        r.sim.teleport(toXZ: SIMD2(0, -1.0)); for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.peerGap = MelonController.jellyGap
        var wall: [(id: Int, pos: SIMD2<Float>)] = []
        var x: Float = -4
        while x <= 4 { wall.append((id: Int.max / 2 + wall.count, pos: SIMD2(x, 0.6))); x += 0.4 }
        r.brain.peers = { wall }
        return (r, SIMD2(0, 2.5))
    }

    /// A home walk that is `requested` with a standing friend on the leg waits the same 6 s as before: nothing before 6 s, no give-up, then it goes on.
    func testRequestedHomeWalkStillWaitsSixSeconds() {
        let (r, target) = wallRig()
        let b = r.brain
        b.commanded = true
        b.steerGiveUp = false
        b.steerWait = 5.9
        let early = b.steerTarget(to: target)
        print("PSR PATIENCE home requested, steerWait 5.9 -> \(String(describing: early)) giveUp \(b.steerGiveUp)")
        XCTAssertNil(early, "still waiting at 5.9 s")
        XCTAssertFalse(b.steerGiveUp, "a requested home walk never gives up")
        b.steerWait = 6.1
        let late = b.steerTarget(to: target)
        print("PSR PATIENCE home requested, steerWait 6.1 -> \(String(describing: late)) giveUp \(b.steerGiveUp)")
        XCTAssertNotNil(late, "after 6 s it goes on")
        XCTAssertFalse(b.steerGiveUp)
        // the leg really is blocked (a 2.1 s wait is still a wait at home)
        b.steerWait = 2.1
        XCTAssertNil(b.steerTarget(to: target), "2.1 s: a home walk still waits")
        XCTAssertFalse(b.steerGiveUp)
    }

    /// The park slide's way-round leg (stage < 0): 2 s, then the leg is given up (and re-planned in BlobBrain+Decor.swift).
    func testSlideWayRoundLegGivesUpAfterTwoSeconds() {
        let (r, target) = wallRig()
        let b = r.brain
        b.commanded = true
        b.idleState.kind = .decorSlide; b.idleState.decorUID = ParkToys.slideUID; b.idleState.slideStage = -3
        b.steerGiveUp = false; b.steerWait = 1.9
        XCTAssertNil(b.steerTarget(to: target), "1.9 s: still waiting")
        XCTAssertFalse(b.steerGiveUp)
        b.steerWait = 2.1
        XCTAssertNil(b.steerTarget(to: target))
        XCTAssertTrue(b.steerGiveUp, "2.1 s behind a standing friend: the leg is given up")
        // the climb step (stage -2 is also < 0) and a stage >= 0 ride keep the old rule only when not a slide leg
        b.steerGiveUp = false; b.idleState.slideStage = 0; b.steerWait = 2.1
        XCTAssertNil(b.steerTarget(to: target), "stage 0: the old 6 s patience")
        XCTAssertFalse(b.steerGiveUp)
        b.idleState.kind = nil
    }
}
