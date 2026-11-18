//
//  TigerBerrySpeciesTests.swift
//  Tiger (character 7, TigerLook.swift) and Berry (character 8, BerryLook.swift), the look phase: the two species exist, are reachable through the test hooks,
//  are offered nowhere, and are told apart from every other body by their own shader modes only (every other species keeps the mode it had).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TigerBerrySpeciesTests: XCTestCase {
    static let both = [JellyRoster.tigerID, JellyRoster.berryID]

    func testIdentity() {
        XCTAssertEqual(JellyRoster.tigerID, 7)
        XCTAssertEqual(JellyRoster.berryID, 8)
        XCTAssertEqual(JellyRoster.baseNames[7], "Tiger")
        XCTAssertEqual(JellyRoster.baseNames[8], "Berry")
        XCTAssertEqual(JellyRoster.knownCount, 27)
        XCTAssertEqual(JellyRoster.baseNames.count, JellyRoster.knownCount)
        XCTAssertEqual(JellyRoster.characterCount, 4, "not offered: the intro / Jelly Spring pickers still show four")
        for id in Self.both {
            XCTAssertTrue(JellyRoster.isValid(id))
            XCTAssertEqual(JellyRoster.species(id), id)
            XCTAssertEqual(JellyRoster.feature(id), JellyFeature.none, "the plain body: no ears, no tail, no wings")
            XCTAssertEqual(JellyRoster.palette(id)?.jellySpecies, id)
            XCTAssertFalse(JellyRoster.defaultIDs.contains(id))
            XCTAssertFalse(SpeciesInfo.order.contains(id), "not in the starter picker (the free first gift)")
            XCTAssertFalse(SpeciesInfo.pages(includingSpecial: true).contains(id), "not sold in the Jelly Spring in the look phase")
            for n in 1...3 { XCTAssertFalse(JellyRoster.sanitised(Array(0..<n)).contains(id)) }
        }
    }

    func testHooksParse() {
        XCTAssertEqual(JellyRoster.parseRoster("bob,tiger"), [0, 7])
        XCTAssertEqual(JellyRoster.parseRoster("Berry, tiger, panda"), [8, 7, 6])
        XCTAssertEqual(JellyRoster.characterID(named: "7"), 7)
        XCTAssertEqual(JellyRoster.characterID(named: "8"), 8)
        let d = UserDefaults(suiteName: "TigerBerrySpeciesTests")!
        d.removePersistentDomain(forName: "TigerBerrySpeciesTests")
        d.set("tiger", forKey: JellyRoster.forceSpeciesKey)
        XCTAssertEqual(JellyRoster.launchIDs(d).first, 7)
        d.set("berry", forKey: JellyRoster.forceSpeciesKey)
        XCTAssertEqual(JellyRoster.launchIDs(d).first, 8)
        d.removePersistentDomain(forName: "TigerBerrySpeciesTests")
    }

    func testModesAreDistinct() {
        let tiger = JellyRoster.palette(JellyRoster.tigerID)!, berry = JellyRoster.palette(JellyRoster.berryID)!
        XCTAssertEqual(tiger.flesh, TigerLook.flesh, "the mode is keyed on the exact flesh value")
        XCTAssertEqual(berry.flesh, BerryLook.flesh, "the mode is keyed on the exact flesh value")
        XCTAssertEqual(BlueBelly.mode(for: tiger), 61)
        XCTAssertEqual(BlueBelly.mode(for: berry), 71)
        // every other body keeps the mode it had
        XCTAssertEqual(BlueBelly.mode(for: JellyRoster.palette(JellyRoster.pandaID)!), 51, "Panda is untouched")
        XCTAssertEqual(BlueBelly.mode(for: WhiteWing.palette), 0, "Pearl is untouched")
        XCTAssertEqual(BlueBelly.mode(for: JellyRoster.palette(JellyRoster.teddyID)!), TeddyEarsVariant.active == .cream ? 43 : 33, "Teddy is untouched")
        // a park visitor keeps whatever mode it had (the blue one keeps its own belly mode, not 0): it is never given a Tiger or a Berry mode
        for c in ParkColour.allCases { XCTAssertFalse([61, 62, 71, 72].contains(BlueBelly.mode(for: JellyPalettes.park(c))), "park visitor \(c.rawValue) must not look like a Tiger or a Berry") }
        for id in 0..<4 { if let p = JellyRoster.palette(id) { XCTAssertEqual(BlueBelly.mode(for: p) >= 50, false) } }
    }

    func testJellyLookGroup() {
        // neither colour is mistaken for a starter's (Pip's yellow is the nearest to the Tiger's orange): both take the look every special species has
        for id in Self.both {
            let p = JellyRoster.palette(id)!
            XCTAssertEqual(JellyLook.species(id: id), JellyLook.Species.other)
            XCTAssertEqual(JellyLook.classify(flesh: SIMD4<Float>(p.flesh.x, p.flesh.y, p.flesh.z, 1)), JellyLook.Species.other)
        }
        XCTAssertGreaterThan(simd_length(TigerLook.flesh - PaletteKey.yellow.palette.flesh), 0.18, "well outside the colour tolerance of Pip's yellow")
    }

    func testAccessibilityMasksAndColourNames() {
        XCTAssertTrue(JelbieA11yText.description(character: 7).contains("stripes"))
        XCTAssertTrue(JelbieA11yText.description(character: 8).contains("seeds"))
        XCTAssertEqual(JelbieA11yText.description(character: 0), "blue and plain", "Bob's text is untouched")
        XCTAssertEqual(EyeMaskModel.paletteCount, 9, "the sleep masks cover ids 0...8; the lineup characters (9...26) wrap onto them until phase B")
        XCTAssertEqual(EyeMaskModel.rests.count, EyeMaskModel.paletteCount)
        XCTAssertEqual(EyeMaskModel.palette(JellyRoster.pandaID).band, Consumables.srgb(0.90, 0.45, 0.55), "Panda's sleep mask keeps its rose")
        XCTAssertEqual(EyeMaskModel.palette(0).band, Consumables.srgb(0.15, 0.19, 0.46), "Bob's sleep mask keeps its navy")
        XCTAssertNotEqual(EyeMaskModel.palette(7).band, EyeMaskModel.palette(JellyRoster.pandaID).band)
        XCTAssertNotEqual(EyeMaskModel.palette(8).band, EyeMaskModel.palette(JellyRoster.pandaID).band)
        XCTAssertNotEqual(EyeMaskModel.palette(7).band, EyeMaskModel.palette(8).band)
        // the widget / Shortcuts colour names: one per species, each back to its own id
        for id in 0..<JellyRoster.knownCount {
            let name = WidgetBridge.colorName(id)
            XCTAssertEqual(WidgetBridge.character(ofColor: name), id, "\(name) round-trips")
            XCTAssertEqual(JelbieRoster.colorName(id), name, "the Shortcuts list uses the widget's names")
        }
        XCTAssertEqual(WidgetBridge.colorName(6), "panda", "Panda is not clamped away")
        XCTAssertEqual(WidgetBridge.colorName(7), "tiger")
        XCTAssertEqual(WidgetBridge.colorName(8), "berry")
        XCTAssertEqual(JelbieEntity.colorWord("tiger"), "Orange")
        XCTAssertEqual(JelbieEntity.colorWord("berry"), "Pink")
    }
}
