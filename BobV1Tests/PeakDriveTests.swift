//
//  PeakDriveTests.swift
//  Motion warping of the touching emotes (BlobSocial+Peak.swift, +Part.swift pressTurnWarp, ringAround radius): the math that keeps a lunge's peak at skin contact.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PeakDriveTests: XCTestCase {
    /// At the hold gap the lean-in room is zero: whatever the drive asks for, a body that leans `now` may lean no further in (minus the engine's own trim, added after).
    func testNoRoomAtContact() {
        let b = PeakTuning.leanBounds(now: 0.05, trim: 0.02, gap: ContactStance.hold)
        XCTAssertEqual(b.maxIn, 0.03, accuracy: 1e-5)
    }

    /// The room grows with the gap and is shared by the two leaners: a 4 cm wind-up gap allows gain * 4 cm / (2 * reach) rad of extra lean each, and that lean closes at most that gap.
    func testRoomSharedAndBounded() {
        let gap: Float = 0.04
        let b = PeakTuning.leanBounds(now: 0, trim: 0, gap: gap)
        let travel = (b.maxIn) * PeakTuning.reachPerRad * 2          // the skin travel of both bodies at the cap
        XCTAssertLessThanOrEqual(travel, gap - PeakTuning.rest + 1e-5, "the strike never travels past contact")
        XCTAssertGreaterThan(travel, 0.5 * (gap - PeakTuning.rest), "but it is a visible lean, not nothing")
    }

    /// A wind-up (lean away) may open the gap only up to `openCap`: with the pair at the cap it may not lean further away.
    func testWindUpCapped() {
        let atCap = PeakTuning.leanBounds(now: -0.02, trim: 0, gap: PeakTuning.openCap)
        XCTAssertEqual(atCap.maxOut, -0.02, accuracy: 1e-6)
        let closer = PeakTuning.leanBounds(now: 0, trim: 0, gap: 0)
        XCTAssertLessThan(closer.maxOut, 0)
        XCTAssertGreaterThan(closer.maxOut, -0.05)
    }

    /// The engine's lean trim is added AFTER the drive: it is taken out of the drive's bounds, so drive + trim stays inside the room.
    func testTrimIsAccountedFor() {
        let a = PeakTuning.leanBounds(now: 0.1, trim: 0, gap: 0.02)
        let b = PeakTuning.leanBounds(now: 0.1, trim: 0.06, gap: 0.02)
        XCTAssertEqual(a.maxIn - b.maxIn, 0.06, accuracy: 1e-6)
        XCTAssertEqual(a.maxOut - b.maxOut, 0.06, accuracy: 1e-6)
    }

    /// The ring hop moves along a chord: mid-hop the pair is closer by cos(hop / 2). The ring radius for the widest touch keeps even that moment clear.
    func testRingRadiusClearsTheChord() {
        let touch: Float = 1.445
        let r = (touch + 0.06) / (2 * cosf(Friends2Tuning.ringHop / 2))
        XCTAssertGreaterThanOrEqual(2 * r * cosf(Friends2Tuning.ringHop / 2), touch)
        XCTAssertEqual(Int((1.5 * 2 * Float.pi / Friends2Tuning.ringHop).rounded()), 15, "1.5 turns of 36 degree hops")
    }

    /// The turn-in-place warp: the reach after a turn of `dyaw` is the profile's reach in the direction the turn brings round (what pressTurnWarp reads).
    func testTurnReachDirection() {
        // a body that is 0.7 wide to its +x and 0.4 deep to its +z, yaw 0; it turns 90 degrees so that its +x side faces +z: the reach toward +z becomes 0.7
        func reach(_ d: SIMD2<Float>) -> Float { abs(d.x) > abs(d.y) ? 0.7 : 0.4 }
        let u = SIMD2<Float>(0, 1)
        let dyaw: Float = .pi / 2
        let back = rotXZ(u, -dyaw)
        XCTAssertEqual(reach(u), 0.4)
        XCTAssertEqual(reach(back), 0.7, "after a +90 degree turn the body's +x side points where +z was: the old reach toward +x is the new reach toward +z")
    }
}
