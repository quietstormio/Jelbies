//
//  ParkRoomFloorTests.swift
//  The park's roam polygon (the walkable lawn) per aspect: prints its area and the free spans of the back rows, and pins that the pond and the flower bed no longer block the back flanks.
//

import XCTest
import simd
@testable import BobV1

final class ParkRoomFloorTests: XCTestCase {
    override func tearDown() { GameCamera.endPark(count: 1); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); super.tearDown() }

    private func spans(_ rf: GameCamera.RoamFloor, _ i: Int) -> String {
        rf.free[i].map { String(format: "%.2f...%.2f", $0.lowerBound, $0.upperBound) }.joined(separator: " ")
    }

    func testParkRoamFloorNumbers() {
        RoomLayout.apply(RoomCatalog.park)
        print("[parkroom] cylinders \(RoomLayout.cylinders.count) roamRect \(GameCamera.roamRect) (set by configurePark below)")
        for (label, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(852.0 / 393.0))] {
            GameCamera.configurePark()
            guard let rf = GameCamera.refreshRoam(aspect: aspect) else { return XCTFail("\(label): no roam floor") }
            print("[parkroom] \(label) roamRect \(GameCamera.roamRect) wide \(GameCamera.roamRectWide) polygon minZ \(rf.minZ) maxZ \(rf.maxZ) area \(rf.area) m2")
            for (i, z) in rf.zs.enumerated() where z <= -2.0 { print("[parkroom] \(label) z \(z) hw \(rf.hw[i]) free \(spans(rf, i))") }
            // the old pond and flower-bed spots are walkable now (a body centre 0.8 clear of the bench front sits in a free span)
            let row = rf.zs.firstIndex { $0 >= -3.5 } ?? 0
            let z = rf.zs[row]
            for x: Float in [3.5, -3.5] where abs(x) <= rf.hw[row] {
                XCTAssertTrue(rf.free[row].contains { $0.contains(x) }, "\(label): (\(x), \(z)) is free floor")
            }
            XCTAssertTrue(RoomLayout.cylinders.isEmpty, "the park has no cylinder collider")
            XCTAssertGreaterThan(RoomLayout.sofaDistanceXZ(SIMD2(-3.5, -4.35)), 0.5, "the flower bed's box is gone")
        }
    }
}
