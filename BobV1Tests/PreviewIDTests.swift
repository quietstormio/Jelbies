//
//  PreviewIDTests.swift
//  The picker's scratch preview ids encode the species in TWO decimal digits (previewBase + slot * 100 + species), so species 10...26 have previews too.
//

import XCTest
@testable import BobV1

@MainActor
final class PreviewIDTests: XCTestCase {
    func testEverySpeciesAndSlotRoundTrips() {
        var seen = Set<Int>()
        for s in 0..<JellyRoster.knownCount {
            for k in 0..<JellyRoster.previewSlots {
                let id = JellyRoster.previewID(species: s, slot: k)
                XCTAssertEqual(id, JellyRoster.previewBase + k * 100 + s)
                XCTAssertTrue(seen.insert(id).inserted, "unique")
                XCTAssertEqual(JellyRoster.species(id), s)
                XCTAssertEqual(JellyRoster.previewSlot(id), k)
                XCTAssertTrue(JellyRoster.isValid(id))
                XCTAssertTrue(JellyRoster.isPreview(id))
                XCTAssertEqual(JellyRoster.nameOf(id), JellyRoster.baseNames[s], "a preview shows its species' base name")
            }
            XCTAssertEqual(JellyRoster.previewID(s), JellyRoster.previewID(species: s, slot: 0))
        }
        XCTAssertEqual(JellyRoster.species(JellyRoster.previewID(species: JellyRoster.opalID, slot: 2)), JellyRoster.opalID)
    }

    func testInvalidIDs() {
        let b = JellyRoster.previewBase
        XCTAssertFalse(JellyRoster.isValid(b + JellyRoster.knownCount), "species 27 does not exist")
        XCTAssertFalse(JellyRoster.isValid(b + 99))
        XCTAssertFalse(JellyRoster.isValid(b + JellyRoster.previewSlots * 100), "slot 3 does not exist")
        XCTAssertFalse(JellyRoster.isValid(b + 500))
    }

    func testNoCollisionWithOtherIDs() {
        let top = JellyRoster.previewBase + JellyRoster.previewSlots * 100
        XCTAssertGreaterThan(JellyRoster.previewBase, JellyRoster.firstInstanceID, "instance ids start below the previews")
        let ids = (0..<JellyRoster.knownCount).flatMap { s in (0..<JellyRoster.previewSlots).map { JellyRoster.previewID(species: s, slot: $0) } }
        for id in ids {
            XCTAssertGreaterThanOrEqual(id, JellyRoster.previewBase)
            XCTAssertLessThan(id, top)
            XCTAssertFalse((0..<JellyRoster.knownCount).contains(id), "not a species id")
            XCTAssertFalse(id >= JellyRoster.firstInstanceID && id < JellyRoster.previewBase, "not an instance id")
        }
        // a recorded instance id is always below the preview range
        XCTAssertFalse(JellyRoster.isPreview(JellyRoster.previewBase - 1))
        XCTAssertTrue(JellyRoster.sanitised(ids).isEmpty || !JellyRoster.sanitised(ids).contains(where: JellyRoster.isPreview), "no roster ever keeps a preview id")
    }
}
