//
//  DiningPlaceToyTests.swift
//  2026-11-16 feeding survey (the owner: "flawless tray and eating and drinking"; "smooth motion no glitchy movement they just lineup properly"): the tray spot is never
//  one where a diner's place (his stand, or the approach point behind it where he waits for the tray) lies on a loose toy or a ball. Install 3 only kept the TRAY
//  off them, so with blocks at (0.4, 1.1) and the tray at (1.6, 2.2), place 1's stand was 0.09 from the blocks: its diner froze mid-walk, was re-sent twice
//  and the tray popped by the 12 s cap with him out of his place.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class DiningPlaceToyTests: XCTestCase {
    private var feet: [DecorFoot] = [], balls: [BallSphere] = [], boxes: [RoomLayout.FlatBox] = [], tables: [Int: RoomLayout.FlatBox] = [:]
    override func setUp() { feet = RoomLayout.decorFeet; balls = RoomLayout.ballSpheres; boxes = RoomLayout.dynamicBoxes; tables = RoomLayout.tableBoxes
        RoomLayout.decorFeet = []; RoomLayout.ballSpheres = []; RoomLayout.dynamicBoxes = []; RoomLayout.tableBoxes = [:] }
    override func tearDown() { RoomLayout.decorFeet = feet; RoomLayout.ballSpheres = balls; RoomLayout.dynamicBoxes = boxes; RoomLayout.tableBoxes = tables }

    private let surveyToy = SIMD2<Float>(0.4, 1.1), surveySpot = SIMD2<Float>(1.6, 2.2)

    func testTheApproachOffsetMatchesTheMeal() {
        XCTAssertEqual(DiningSpot.placeApproachBack, GameCare.approachBack)
    }

    func testAToyOnAStandOrJustBehindItBlocksThatPlace() {
        let L = DiningLayout.make(n: 3)
        for p in L.places { XCTAssertFalse(DiningSpot.placeBlockedByLooseThings(surveySpot + p.rel), "nothing on the floor yet") }
        RoomLayout.decorFeet = [DecorFoot(uid: 1, kind: .blocks, centre: surveyToy)]
        XCTAssertTrue(DiningSpot.placeBlockedByLooseThings(surveySpot + L.places[1].rel), "the survey's meal: blocks on place 1's stand")
        XCTAssertFalse(DiningSpot.blockedByLooseThings(origin: surveySpot, layout: L), "the tray-only check let that spot through")
        let stand = SIMD2<Float>(-1.0, 0.4)
        RoomLayout.decorFeet = [DecorFoot(uid: 2, kind: .blocks, centre: stand + SIMD2(0, -0.25 - 0.3))]
        XCTAssertTrue(DiningSpot.placeBlockedByLooseThings(stand), "a toy right behind the approach point")
        RoomLayout.decorFeet = [DecorFoot(uid: 3, kind: .blocks, centre: stand + SIMD2(1.5, 0))]
        XCTAssertFalse(DiningSpot.placeBlockedByLooseThings(stand), "a toy beside the neighbouring place is not on this one")
        RoomLayout.decorFeet = []
        RoomLayout.ballSpheres = [BallSphere(c: stand + SIMD2(0.2, 0), r: 0.2, uid: 4)]
        XCTAssertTrue(DiningSpot.placeBlockedByLooseThings(stand), "a ball on the stand")
    }

    func testNoOfferedSpotPutsAPlaceOnTheToy() {
        let L = DiningLayout.make(n: 3)
        RoomLayout.decorFeet = [DecorFoot(uid: 1, kind: .blocks, centre: surveyToy)]
        let was = DiningSpot.pickOpen; defer { DiningSpot.pickOpen = was }
        var offered: [SIMD2<Float>] = []
        DiningSpot.pickOpen = { offered = $0; return $0.first }
        _ = DiningSpot.choose(bob: SIMD2(99, 99), layout: L, jellies: [])
        XCTAssertFalse(offered.isEmpty, "the room still has open spots")
        XCTAssertFalse(offered.contains { simd_distance($0, surveySpot) < 0.01 }, "the survey's spot is no longer offered")
        let r = RoomLayout.decorFeet[0].radius
        for o in offered {
            for p in L.places {
                let stand = o + p.rel, approach = stand - SIMD2(0, GameCare.approachBack)
                XCTAssertGreaterThanOrEqual(simd_distance(stand, surveyToy), r + DiningSpot.placeLooseClear, "stand of spot \(o)")
                XCTAssertGreaterThanOrEqual(simd_distance(approach, surveyToy), r + DiningSpot.placeLooseClear, "approach of spot \(o)")
            }
        }
    }
}
