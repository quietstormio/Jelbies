//
//  MealPartingTests.swift
//  A diner (`reserved`) keeps the 6 s parting flag of the close social session the meal call ended, but his turn steps must not slide him away from the ex-partner;
//  outside a meal the parting retreat still works (BlobSocial+Part.swift).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MealPartingTests: XCTestCase {
    private var savedHour: Double?          // (the day clock as this class found it: put back in tearDown)
    override func setUp() { savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 12; RoomLayout.dynamicBoxes = [] }
    override func tearDown() { DayClock.shared.forcedHour = savedHour; RoomLayout.dynamicBoxes = [] }

    func testReservedDinerGetsNoPartingRetreatButFreeOneDoes() {
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-0.3, 1.0), SIMD2(0.2, 1.0)])
        let a = lab.rigs[0].brain, b = lab.rigs[1].brain
        a.peerGap = 2.5          // (no contact profiles here: the skin gap falls back to root distance - peerGap * 0.74, so the pair counts as touching)
        a.startParting(from: b)
        a.reserved = true
        XCTAssertNil(a.partingRetreat(dyaw: 1.0), "a reserved (meal) brain takes a plain turn")
        XCTAssertNil(a.partingRetreat(dyaw: -1.0))
        a.reserved = false
        let r = a.partingRetreat(dyaw: 1.0)
        XCTAssertNotNil(r, "unreserved, the parting retreat still fires")
        if let r { XCTAssertGreaterThan(simd_dot(r, a.position - b.position), 0, "...and it backs away from the ex-partner") }
    }
}
