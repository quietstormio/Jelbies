//
//  LivelyMovesTests.swift
//  The liveliness round's new moves (W2): shake, lie down, chirp and the window walk: each returns to rest,
//  the window antic walks there and faces the wall, and the scheduler's "recent" filter keeps his own last picks out.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class LivelyMovesTests: XCTestCase {
    nonisolated(unsafe) static var keep: [MotionRig] = []
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    override func tearDown() { BlobBrain.windowXs = { RoomGeometry.windowXs } }

    private func rig() -> MotionRig {
        let r = MotionRig(game: true); Self.keep.append(r)
        r.brain.seed = 5; r.brain.amplitude = 1; r.brain.idleForced = true; r.brain.anticsEnabled = true
        return r
    }

    func testEachNewMoveReturnsToRest() {
        for k in [IdleKind.shake, .lieDown, .chirp, .window] {
            let r = rig()
            let rest = r.sim.bodyPose(iterations: 6).tilt
            XCTAssertTrue(r.brain.idleStart(k, r.sim), "\(k) starts")
            var done = false
            r.run(16, until: { done = r.brain.idleState.kind == nil && r.t > 0.5; return done })
            XCTAssertTrue(done, "\(k) ends within 16 s")
            r.run(1.5)
            let p = r.sim.bodyPose(iterations: 6)
            XCTAssertLessThan(abs(p.tilt - rest), 0.12, "\(k): upright again (rest \(rest), now \(p.tilt))")
            XCTAssertFalse(r.root.x.isNaN || r.root.y.isNaN, "\(k): no NaN")
        }
    }

    func testWindowWalksThereAndFacesTheWall() {
        let r = rig()
        r.sim.teleport(toXZ: SIMD2(1.0, 1.4)); r.run(1)
        r.brain.currentPose(r.sim)
        let here = r.brain.position
        guard let w = r.brain.windowSpot(from: here) else { return XCTFail("a window spot") }
        XCTAssertTrue(r.brain.idleStart(.window, r.sim))
        XCTAssertTrue(r.brain.idleState.windowGo, "walks first")
        var sawHold = false
        r.run(20, until: { r.brain.idleState.kind == nil && r.t > 1 }, each: {
            if r.brain.idleState.kind == .window, r.brain.idleState.phase == 1, !sawHold {
                sawHold = true
                XCTAssertLessThan(simd_distance(r.brain.position, w.spot), 1.2, "at the window")
                XCTAssertLessThan(abs(wrapAngleT(r.brain.yaw - r.brain.idleState.goalYaw)), 0.3, "faces the wall")
            }
        })
        XCTAssertTrue(sawHold, "the look was held")
    }

    func testWindowFallsBackWithoutWindows() {
        BlobBrain.windowXs = { [] }
        let r = rig()
        XCTAssertTrue(r.brain.idleStart(.window, r.sim))
        XCTAssertFalse(r.brain.idleState.windowGo, "no spot: the in-place look")
    }

    func testPickAvoidsRecent() {
        var seen = Set<IdleKind>()
        for i in 0..<400 {
            let k = IdleTable.pick(.okay, last: nil, r: Float(i) / 400, antics: true, recent: [.zoomies, .run, .window])
            seen.insert(k)
        }
        XCTAssertFalse(seen.contains(.zoomies) || seen.contains(.run) || seen.contains(.window), "recent kinds stay out: \(seen)")
    }

    func testFamiliesAndEchoBlockCopycats() {
        XCTAssertTrue(BlobBrain.family(.bounce).contains(.scoot))
        XCTAssertTrue(BlobBrain.family(.slide).contains(.zoomies))
    }
}

func wrapAngleT(_ a: Float) -> Float { var d = a; while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }; return d }
