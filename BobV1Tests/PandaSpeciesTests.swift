//
//  PandaSpeciesTests.swift
//  Panda (character 6, PandaLook.swift): the species exists, is reachable through the test hooks, is not offered anywhere, and is told apart from every other white / light body
//  by its own shader mode only (Pearl and Teddy keep the modes they had).
//

import XCTest
@testable import BobV1

@MainActor
final class PandaSpeciesTests: XCTestCase {
    func testIdentity() {
        XCTAssertEqual(JellyRoster.pandaID, 6)
        XCTAssertEqual(JellyRoster.baseNames[6], "Panda")
        XCTAssertEqual(JellyRoster.knownCount, 7)
        XCTAssertEqual(JellyRoster.baseNames.count, JellyRoster.knownCount)
        XCTAssertEqual(JellyRoster.feature(JellyRoster.pandaID), .ears, "Teddy's in-body ears path")
        XCTAssertNotNil(JellyRoster.palette(JellyRoster.pandaID))
        XCTAssertEqual(JellyRoster.characterCount, 4, "not offered: the intro / Jelly Spring pickers still show four")
        XCTAssertFalse(JellyRoster.defaultIDs.contains(6))
        XCTAssertFalse(SpeciesInfo.order.contains(6), "not in the Jelly Spring picker")
        XCTAssertFalse(SpeciesInfo.all.contains { $0.character == 6 }, "no species card")
        for n in 1...3 { XCTAssertFalse(JellyRoster.sanitised(Array(0..<n)).contains(6)) }
    }

    func testHooksParse() {
        XCTAssertEqual(JellyRoster.parseRoster("bob,panda"), [0, 6])
        XCTAssertEqual(JellyRoster.parseRoster("Panda, teddy, pearl"), [6, 4, 5])
        XCTAssertEqual(JellyRoster.characterID(named: "6"), 6)
        let d = UserDefaults(suiteName: "PandaSpeciesTests")!
        d.removePersistentDomain(forName: "PandaSpeciesTests")
        d.set("panda", forKey: JellyRoster.forceSpeciesKey)
        XCTAssertEqual(JellyRoster.launchIDs(d).first, 6)
        d.removePersistentDomain(forName: "PandaSpeciesTests")
    }

    func testModesAreDistinct() {
        let panda = JellyRoster.palette(JellyRoster.pandaID)!
        XCTAssertEqual(BlueBelly.mode(for: panda), 51)
        XCTAssertEqual(BlueBelly.mode(for: WhiteWing.palette), 0, "Pearl is untouched")
        XCTAssertEqual(BlueBelly.mode(for: JellyRoster.palette(JellyRoster.teddyID)!), TeddyEarsVariant.active == .cream ? 43 : 33, "Teddy is untouched")
        XCTAssertNotEqual(panda.flesh, WhiteWing.palette.flesh)
        for c in ParkColour.allCases { XCTAssertEqual(BlueBelly.mode(for: JellyPalettes.park(c)), 0, "park visitor \(c.rawValue) must not look like a Panda") }
        for id in 0..<4 { if let p = JellyRoster.palette(id) { XCTAssertEqual(BlueBelly.mode(for: p) >= 50, false) } }
    }

    func testAccessibilityAndMasks() {
        XCTAssertTrue(JelbieA11yText.description(character: 6).contains("black"))
        XCTAssertEqual(EyeMaskModel.paletteCount, JellyRoster.knownCount)
    }
}
