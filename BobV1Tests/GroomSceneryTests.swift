//
//  GroomSceneryTests.swift
//  The Jelly Spa street: the static mesh stays light, and the walk area stops inside the curb.
//

import XCTest
@testable import BobV1

final class GroomSceneryTests: XCTestCase {
    func testStaticMeshCountsAndCurb() {
        let m = GroomScenery.build(theme: RoomCatalog.groom.theme)
        print("GROOMMESH vertices=\(m.vertices.count) triangles=\(m.indices.count / 3)")
        XCTAssertFalse(m.vertices.isEmpty)
        XCTAssertTrue(m.indices.allSatisfy { Int($0) < m.vertices.count })
        XCTAssertLessThan(m.vertices.count, 60_000)
        GameCamera.configureGroom()
        defer { GameCamera.groomOn = false }
        XCTAssertLessThanOrEqual(GameCamera.roamRect.1.y, GroomScenery.curbZ - 0.6)
    }
}
