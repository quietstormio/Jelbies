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

    /// The boop is a repeated tap: the lift is a wind-up that returns to ZERO (= the solved elevation = the skin) at every strike, the hand is on the skin for at least half of every cycle (the hold median stays 0 +- 0.5),
    /// and the cycle fits the session (3 taps, then the finish).
    func testBoopTapsStrikeAtTheSkinAndRestOnIt() {
        typealias T = BlobBrain.TapTuning
        var onSkin = 0, total = 0, peak: Float = 0, atStrike: Float = 1
        let dt: Float = 0.01
        var u: Float = 0
        while u < T.period {
            let w = smooth(u / T.windup) * (1 - smooth((u - T.strike) / T.fall))
            peak = max(peak, T.height * w)
            if abs(u - (T.strike + T.fall)) < dt / 2 { atStrike = T.height * w }
            if T.height * w < 0.02 { onSkin += 1 }
            total += 1; u += dt
        }
        XCTAssertEqual(peak, T.height, accuracy: 0.01, "the wind-up reaches its height before the strike")
        XCTAssertEqual(atStrike, 0, accuracy: 1e-4, "the strike ends EXACTLY on the solved elevation: the skin, never past it")
        XCTAssertGreaterThanOrEqual(Float(onSkin) / Float(total), 0.5, "the hand rests on the skin for at least half of each cycle")
        XCTAssertGreaterThan(T.period, T.strike + T.fall + 0.2, "a rest on the skin follows every strike")
        XCTAssertGreaterThanOrEqual(T.count, 3)
    }
    private func smooth(_ x: Float) -> Float { let t = max(0, min(1, x)); return t * t * (3 - 2 * t) }

    /// WHY a cheek / an ear cannot be reached (numbers, round 4): the contact footprint is height-blind, so the walls stop two bodies at ARM-NUB contact (0.70 each, at hand height); at the face's height the egg is
    /// narrower, so the partner's cheek is further than the stub arm can reach from there, and a head-to-head press (cheek to cheek) leaves the heads apart by twice the difference.
    func testCheekIsOutOfReachAtTheNubWall() {
        func eggHalfWidth(_ y: Double) -> Float {
            var lo = 0.1, hi = 1.0
            for _ in 0..<40 { let m = 0.5 * (lo + hi); if BobForm.bodySDF(SIMD3(m, y, 0)) < 0 { lo = m } else { hi = m } }
            return Float(lo)
        }
        let yFace: Double = 0.65, yHead: Double = 0.85
        let L = HandReach.armLength, sh = HandReach.shoulder
        // the stance distance (centre to centre): the partner's nub + the hand's reach at the nub's height + the stand-off
        let wall = HandReach.restHalfWidth + HandReach.pole(el: HandReach.elBoop, sa: HandReach.saNub).x + HandReach.stand
        // the distance at which the hand's pole would stand on the cheek (arm raised to the face's height, straight across)
        let elFace = asinf(max(-1, min(1, (Float(yFace) - sh.y) / L)))
        let cheek = eggHalfWidth(yFace) + HandReach.pole(el: elFace, sa: 0).x
        let headGap = 2 * (HandReach.restHalfWidth - eggHalfWidth(yHead))
        print("HANDREACH wall=\(wall) cheekDistance=\(cheek) handShortOfCheek=\(wall - cheek) headGapAtNubWall=\(headGap) eggHalfWidthFace=\(eggHalfWidth(yFace)) head=\(eggHalfWidth(yHead))")
        XCTAssertGreaterThan(wall - cheek, 0.05, "the bodies stand 5+ cm FURTHER apart (nub wall) than a hand on the cheek needs: the cheek is out of reach from the wall")
        XCTAssertGreaterThan(headGap, 0.05, "and the heads of a pair at the nub wall are apart: cheek to cheek needs a head-height wall")
    }
}
