//
//  FinishLookTests.swift
//  The finish family (Gold 10, Silver 11, Bronze 26, Ruby 17, Emerald 23, Sapphire 24, Amethyst 25; FinishLook.swift): own body modes 101...107, unique flesh, ids unchanged, the plain body, the earlier species untouched.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FinishLookTests: XCTestCase {
    func testModesAndIdentity() {
        let expect: [(Int, Float, String)] = [(10, 101, "Gold"), (11, 102, "Silver"), (26, 103, "Bronze"), (17, 104, "Ruby"), (23, 105, "Emerald"), (24, 106, "Sapphire"), (25, 107, "Amethyst")]
        XCTAssertEqual(FinishLook.ids, expect.map { $0.0 })
        for (id, mode, name) in expect {
            let p = JellyRoster.palette(id)!
            XCTAssertEqual(BlueBelly.mode(for: p), mode)
            XCTAssertEqual(JellyRoster.nameOf(id), name)
            XCTAssertEqual(JellyRoster.feature(id), JellyFeature.none)
            XCTAssertEqual(JellyRoster.tint(id), p.flesh)
            XCTAssertEqual(FinishLook.mode(forFlesh: p.flesh), mode)
            XCTAssertFalse(JellyVariants.takesVariant(id))
        }
        XCTAssertEqual(Set(FinishLook.looks.values.map { $0.flesh }).count, 7, "unique flesh")
        for id in 0...8 { XCTAssertNil(FinishLook.mode(forFlesh: (JellyRoster.palette(id) ?? PaletteKey.blue.palette).flesh), "species \(id) is no finish look") }
        for c in ParkColour.allCases { XCTAssertNil(FinishLook.mode(forFlesh: JellyPalettes.park(c).flesh)) }
        for id in [13, 14, 15, 16, 19, 20, 21, 22] { XCTAssertNil(FinishLook.mode(forFlesh: JellyRoster.palette(id)!.flesh)) }
    }
}
