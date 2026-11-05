//
//  PeakDriveTests.swift
//  Motion warping of the touching emotes (BlobSocial+Peak.swift, ringAround radius): the math that keeps a lunge's peak at skin contact.
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

    /// A lean that is IN while the gap is open may always relax back to neutral (a guard that froze the lean held the high five 30 cm apart for 5 s).
    func testRelaxingIsNeverBlocked() {
        let b = PeakTuning.leanBounds(now: 0.055, trim: 0, gap: 0.33)
        XCTAssertLessThanOrEqual(b.maxOut, 0)
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
        XCTAssertLessThanOrEqual(a.maxOut, 0)          // (the away bound never forbids relaxing to neutral)
        XCTAssertLessThanOrEqual(b.maxOut, 0)
    }

    /// The ring hop moves along a chord: mid-hop the pair is closer by cos(hop / 2). The ring is the FACE-TO-FACE touch (~0.8 m, the pair faces each other all the way round) + a margin, and the hop is small enough that the chord
    /// pulls the pair in by under 2 cm (a 36 degree hop pulled 4 cm: the ring clears the chord only when the hop is short, not by a wide ring).
    func testRingHopChordDipIsUnderTwoCentimetres() {
        let touch: Float = 0.80
        let dip = (touch + Friends2Tuning.ringFaceMargin) * (1 - cosf(Friends2Tuning.ringHop / 2))
        XCTAssertLessThan(dip, 0.02)
        XCTAssertEqual(Int((1.5 * 2 * Float.pi / Friends2Tuning.ringHop).rounded()), 24, "1.5 turns of 22.5 degree hops")
    }

    /// The hop / lunge kinds (bump, chestBump, highFive, bellyBounce, sneak) may open the gap by a wind-up only 1.5 cm; the squabble keeps the 4.5 cm.
    func testPressKindsHaveATightWindUp() {
        XCTAssertEqual(PeakTuning.openCap(for: .bump), 0.015, accuracy: 1e-6)
        XCTAssertEqual(PeakTuning.openCap(for: .highFive), 0.015, accuracy: 1e-6)
        XCTAssertEqual(PeakTuning.openCap(for: .squabble), PeakTuning.openCap, accuracy: 1e-6)
        let tight = PeakTuning.leanBounds(now: 0, trim: 0, gap: 0.0, openCap: PeakTuning.openCap(for: .bump)).maxOut
        let wide = PeakTuning.leanBounds(now: 0, trim: 0, gap: 0.0, openCap: PeakTuning.openCap(for: .squabble)).maxOut
        XCTAssertGreaterThan(tight, wide, "the press kinds' lean-away room is smaller (less negative)")
    }

    /// The impact kick (a skin displacement into the partner) is capped for the touching drives.
    func testImpactKickIsCapped() {
        let b = BlobBrain()
        XCTAssertEqual(b.impactKick(3.0), PeakTuning.kickMax, accuracy: 1e-6)
        XCTAssertEqual(b.impactKick(0.2), 0.2, accuracy: 1e-6)
    }
}
