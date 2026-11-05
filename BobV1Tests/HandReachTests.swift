//
//  HandReachTests.swift
//  The hand emotes (user rule 2, BlobSocial+Hands.swift): the geometry the stances stand on, the table rows (side by side, the hand's reach, no default stance), the drives' arm requests.
//  The end-to-end numbers (hand tip to the partner's skin 0 +- 0.5 cm, hands tip to tip, bodies at hand reach) are ContactPolishTests.handFails on all five casts.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HandReachTests: XCTestCase {
    /// The resting body's widest point is the arm nub (0.70 from the centre, at hand height), not the egg (0.58): what a raised hand meets, and what the footprint of a body with its arms down measures.
    func testRestExtremeIsTheNubAtHandHeight() {
        let e = HandReach.restExtreme
        XCTAssertEqual(e.x, 0.70, accuracy: 0.01, "the nub is the widest part of the resting body")
        XCTAssertGreaterThan(e.x, Float(BobForm.halfW) + 0.08, "wider than the egg")
        XCTAssertEqual(e.y, 0.465, accuracy: 0.05, "at about the height of the shoulder")
        XCTAssertEqual(HandReach.restSDF(SIMD3(Double(e.x) - 0.004, Double(e.y), Double(e.z))), -0.004, accuracy: 0.003, "inside, on the skin")
        XCTAssertGreaterThan(HandReach.restSDF(SIMD3(Double(e.x) + 0.01, Double(e.y), Double(e.z))), 0.005, "outside beyond")
        XCTAssertEqual(HandReach.restSDF(SIMD3(.nan, 0, 0)), 9, "a non-finite point is far away (never a crash)")
    }

    /// The hand at the nub's height reaches 11-13 cm past it (the stub arm): that is the only slack between "arms down" and "hand on the partner".
    func testReachBeyondTheNubIsTheStubArm() {
        let r = HandReach.reachBeyondNub(el: HandReach.elBoop)
        XCTAssertEqual(r, 0.115, accuracy: 0.02, "boop: the pole stands ~11.5 cm past the partner's resting arm")
        XCTAssertEqual(HandReach.pole(el: 0, sa: 0).x, 0.48 + 0.34, accuracy: 0.002, "shoulder 0.48 + length 0.225 + tip radius 0.115")
        XCTAssertLessThan(HandReach.pole(el: 0, sa: 0).x - 0.48, Float(ArmCap.maximum) + 0.1, "a stub (the wave's own thumb), never a noodle")
        // the arm cap does not shorten the pose the hand emotes use
        let brain = MotionRig(game: true); Self.keep.append(brain)
        let g = brain.brain.armGeometry(el: HandReach.elBoop, sa: 0, lift: 1, xShift: 0, bodyLed: 0)
        XCTAssertEqual(simd_length(g.b - g.a), Float(ArmPath.armWalkRoot.length), accuracy: 0.002, "capped arm = the full stub")
        XCTAssertLessThanOrEqual(ArmCap.exposed(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), r2: Double(g.r2)), ArmCap.maximum + 1e-6)
    }
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// Every hand emote stands side by side and reaches across (rows), and its walk-up stands the hand's own stand-off (a hair above the touch window, under the arrival bar).
    func testHandRowsStandSideBySideAtHandReach() {
        for k in [SocialKind.boop, .highFive] {
            let row = ContactStance.entry(k)
            XCTAssertEqual(row?.facing, .camera, "\(k): side by side (a hand cannot get past the belly of a partner it faces)")
            XCTAssertEqual(row?.cls, .touching)
            XCTAssertEqual(row?.steps.first?.target, HandReach.stand, "\(k): the walk-up lands the HAND, no extra stand-off")
            XCTAssertGreaterThan(HandReach.stand, 0.005, "above the 0.5 cm touch window: the touch is the press")
            XCTAssertLessThan(HandReach.stand, 0.015, "under the 1.5 cm arrival bar")
        }
        XCTAssertEqual(ContactStance.entry(.boop)?.anchor, .b, "the booped one stands")
    }

    /// The drives ask for the arm every tick (and only the walker's side for cheek / whisper): a request is `socialBook.handWant`, reset by socialTick, never left over.
    func testHandRequestIsPerTickAndEasesOut() {
        let r = MotionRig(game: true); Self.keep.append(r)
        r.run(0.5)
        let b = r.brain
        b.socialBook.handWant = HandReach(side: 1, w: 1, el: HandReach.elBoop, seek: false, partner: -1)
        b.socialHandsTick(r.sim, 1.0 / 60)
        XCTAssertGreaterThan(b.socialBook.handW, 0, "the override eases in")
        XCTAssertEqual(b.armReachW, 1, "and releases the rest-nub cap (the wave's thumb is the limit)")
        XCTAssertEqual(b.armDirEl[0], -0.25, accuracy: 1e-6, "the free arm hangs relaxed")
        b.socialBook.handWant = nil
        for _ in 0..<40 { b.socialHandsTick(r.sim, 1.0 / 60) }
        XCTAssertEqual(b.socialBook.handW, 0, accuracy: 1e-6, "no request: the arm goes back down within 0.3 s")
        XCTAssertEqual(b.armReachW, 0)
        XCTAssertEqual(b.armDirW, 0, "nothing of the hand reach is left on him")
    }
}
