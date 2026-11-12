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

    /// Seesaw <-> hopscotch room (2026-11-12): the seesaw's stand spots and footprint against the court's queue fan and slab; every spot on the roam floor and clear of the solids.
    func testSeesawHasRoomFromTheHopscotchCourt() {
        RoomLayout.apply(RoomCatalog.park)
        DecorField.shared.set(ParkToys.placed)
        defer { DecorField.shared.set([]) }
        guard let sf = DecorField.shared.foot(ParkToys.seesawUID), let cf = DecorField.shared.foot(ParkToys.hopscotchUID) else { return XCTFail("pieces") }
        let sh = DecorKind.seesaw.spec(quarter: sf.quarter).half
        let stands = [SIMD2<Float>(-0.66, SeesawTuning.standDz), SIMD2(0.66, SeesawTuning.standDz)].map { sf.centre + $0 }
        let queue = (0..<4).map { cf.centre + HopscotchCourt.queueSpot(slot: $0) }
        let slabBack = cf.centre.y - HopscotchCourt.slabHalf.y, seesawFront = sf.centre.y + sh.y
        var minSpot = Float.infinity
        for s in stands { for q in queue { minSpot = min(minSpot, simd_distance(s, q)) } }
        print("[parkroom] seesaw centre \(sf.centre) half \(sh) front z \(seesawFront); court centre \(cf.centre) slab back z \(slabBack); footprint gap \(slabBack - seesawFront); stands \(stands); queue \(queue); closest stand<->queue centre distance \(minSpot)")
        XCTAssertGreaterThanOrEqual(minSpot, 0.9, "a stand spot is at least a body width from every queue spot")
        for (label, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(852.0 / 393.0))] {
            GameCamera.configurePark()
            guard let rf = GameCamera.refreshRoam(aspect: aspect) else { return XCTFail("\(label): no roam floor") }
            for (name, p) in zip(["stand L", "stand R"] + (0..<4).map { "queue \($0)" }, stands + queue) {
                let row = rf.zs.lastIndex { $0 <= p.y } ?? 0
                XCTAssertTrue(rf.contains(p), "\(label): \(name) \(p) is on the roam floor")
                XCTAssertTrue(rf.free[row].contains { $0.contains(p.x) }, "\(label): \(name) \(p) is in a free span")
                XCTAssertGreaterThan(RoomLayout.sofaDistanceXZ(p), 0.5, "\(label): \(name) is clear of the bench")
            }
        }
    }
}
