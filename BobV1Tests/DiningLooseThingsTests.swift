//
//  DiningLooseThingsTests.swift
//  The meal tray is never put where a toy lies on the floor, a ball rolls, or another tray / table already stands.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class DiningLooseThingsTests: XCTestCase {
    private var feet: [DecorFoot] = [], balls: [BallSphere] = [], boxes: [RoomLayout.FlatBox] = [], tables: [Int: RoomLayout.FlatBox] = [:]
    override func setUp() { feet = RoomLayout.decorFeet; balls = RoomLayout.ballSpheres; boxes = RoomLayout.dynamicBoxes; tables = RoomLayout.tableBoxes
        RoomLayout.decorFeet = []; RoomLayout.ballSpheres = []; RoomLayout.dynamicBoxes = []; RoomLayout.tableBoxes = [:] }
    override func tearDown() { RoomLayout.decorFeet = feet; RoomLayout.ballSpheres = balls; RoomLayout.dynamicBoxes = boxes; RoomLayout.tableBoxes = tables }

    private let spot = SIMD2<Float>(0.6, 1.4)

    func testALooseToyBlocksTheSpotItLiesOn() {
        let L = DiningLayout.make(n: 2)
        XCTAssertFalse(DiningSpot.blockedByLooseThings(origin: spot, layout: L))
        RoomLayout.decorFeet = [DecorFoot(uid: 1, kind: .ball, centre: spot)]
        XCTAssertTrue(DiningSpot.blockedByLooseThings(origin: spot, layout: L), "a toy under the tray")
        XCTAssertFalse(DiningSpot.blockedByLooseThings(origin: spot + SIMD2(2.5, 0), layout: L), "a toy far away does not matter")
    }
    func testABallAnotherTrayAndATableBlockToo() {
        let L = DiningLayout.make(n: 1)
        RoomLayout.ballSpheres = [BallSphere(c: spot + SIMD2(0.05, 0), r: 0.2, uid: 2)]
        XCTAssertTrue(DiningSpot.blockedByLooseThings(origin: spot, layout: L)); RoomLayout.ballSpheres = []
        RoomLayout.dynamicBoxes = [.init(centre: spot, half: SIMD2(0.4, 0.3), height: 0.3)]
        XCTAssertTrue(DiningSpot.blockedByLooseThings(origin: spot, layout: L), "another tray"); RoomLayout.dynamicBoxes = []
        RoomLayout.tableBoxes = [5: .init(centre: spot + SIMD2(0.1, 0.1), half: SIMD2(0.5, 0.4), height: 0.6)]
        XCTAssertTrue(DiningSpot.blockedByLooseThings(origin: spot, layout: L), "a café table")
    }
    func testTheChosenSpotAvoidsAToyWhereTheTrayWouldHaveLanded() {
        let L = DiningLayout.make(n: 2)
        let was = DiningSpot.pickOpen; defer { DiningSpot.pickOpen = was }
        DiningSpot.pickOpen = { open in open.first { simd_distance($0, SIMD2(0.6, 1.4)) < 0.01 } ?? open.first }          // "where the tray lands on the base": a fixed pick
        let base = DiningSpot.choose(bob: SIMD2(99, 99), layout: L, jellies: [])
        RoomLayout.decorFeet = [DecorFoot(uid: 1, kind: .ball, centre: base)]
        let after = DiningSpot.choose(bob: SIMD2(99, 99), layout: L, jellies: [])
        XCTAssertGreaterThan(simd_distance(base, after), 0.2, "the tray lands elsewhere")
        XCTAssertFalse(DiningSpot.blockedByLooseThings(origin: after, layout: L))
    }
}
