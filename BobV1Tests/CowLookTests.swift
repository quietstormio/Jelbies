//
//  CowLookTests.swift
//  The cow family (Moo 13, Cocoa 14, Blush 15; CowLook.swift): own body modes 91 / 93 / 95, unique flesh, ids unchanged, the plain body, the earlier species untouched.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CowLookTests: XCTestCase {
    func testModesAndIdentity() {
        XCTAssertEqual([JellyRoster.mooID, JellyRoster.cocoaID, JellyRoster.blushID], [13, 14, 15])
        for (id, mode, name) in [(13, Float(91), "Moo"), (14, 93, "Cocoa"), (15, 95, "Blush")] {
            let p = JellyRoster.palette(id)!
            XCTAssertEqual(BlueBelly.mode(for: p), mode)
            XCTAssertEqual(JellyRoster.nameOf(id), name)
            XCTAssertEqual(JellyRoster.feature(id), JellyFeature.none)
            XCTAssertEqual(p.flesh, LineupLook.fleshByID[id]!, "the flesh stays the drawing's base colour")
            XCTAssertEqual(JellyRoster.tint(id), p.flesh)
            XCTAssertEqual(CowLook.mode(forFlesh: p.flesh), mode)
        }
        for id in 0...8 { XCTAssertNil(CowLook.mode(forFlesh: (JellyRoster.palette(id) ?? PaletteKey.blue.palette).flesh), "species \(id) is no cow") }
        for c in ParkColour.allCases { XCTAssertNil(CowLook.mode(forFlesh: JellyPalettes.park(c).flesh)) }
    }
}
