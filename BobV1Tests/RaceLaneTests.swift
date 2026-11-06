//
//  RaceLaneTests.swift
//  littleRace is a PROXIMITY kind: two runners abreast must never overlap. The lanes used to start at the stand-apart (touch) distance: the runners' sway (+-12 cm) and arm swing overlapped them by
//  4 - 6.5 cm along the whole run on every cast. The lane spots now keep `Friends2Tuning.raceLaneClear` of clear water on top of the touch distance (BlobSocial+Friends2.swift, sideSpot(extra:)).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RaceLaneTests: XCTestCase {
    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        ContactField.reset(); ContactField.enabled = true
    }
    override func tearDown() {
        ContactField.reset(); ContactField.enabled = true
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    func testRaceLaneSpotKeepsTheClearWaterOnTopOfTheStandApartDistance() throws {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.none, .none], seed: 5)
        d.live = true
        for _ in 0..<5 { d.tick() }
        let a = d.lab.rigs[0].brain, b = d.lab.rigs[1].brain
        let plain = try XCTUnwrap(a.sideSpot(of: b, gap: a.peerGap * Friends2Tuning.raceLane))
        let lane = try XCTUnwrap(a.sideSpot(of: b, gap: a.peerGap * Friends2Tuning.raceLane, extra: Friends2Tuning.raceLaneClear))
        XCTAssertEqual(simd_distance(lane, b.position) - simd_distance(plain, b.position), Friends2Tuning.raceLaneClear, accuracy: 0.03, "the lane spot sits the clear water further from the partner than the plain side spot")
        XCTAssertGreaterThanOrEqual(Friends2Tuning.raceLaneClear, 0.3, "less than a running sway + the widest feature (0.30 left Lavender+Pip at -3.8 cm)")
    }
}
