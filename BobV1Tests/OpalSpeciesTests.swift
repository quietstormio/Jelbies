//
//  OpalSpeciesTests.swift
//  Opal (character 12): its real look (the iridescent wave, body mode 86), its Spring content (page, jars, loved food), its own sleep mask. a Jelly Spring special (OpalSpringTests). (Its voice is a separate commit.) Modelled on LineupLooksSpeciesTests / TigerBerrySpeciesTests.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class OpalSpeciesTests: XCTestCase {
    let opal = JellyRoster.opalID

    func testBodyModeIs86AndFleshIsUnique() {
        XCTAssertEqual(opal, 12)
        let p = JellyRoster.palette(opal)!
        XCTAssertEqual(BlueBelly.mode(for: p), 86)
        XCTAssertEqual(p.flesh, GradientLook.Opal.flesh)
        XCTAssertEqual(JellyRoster.tint(opal), GradientLook.Opal.swatch)
        XCTAssertEqual(p.jellySpecies, opal)
        for id in 0..<JellyRoster.knownCount where id != opal {
            let f = (JellyRoster.palette(id) ?? PaletteKey.blue.palette).flesh
            XCTAssertNotEqual(f, p.flesh, "species \(id) shares Opal's flesh value")
        }
        for c in ParkColour.allCases { XCTAssertNotEqual(JellyPalettes.park(c).flesh, p.flesh) }
        for v in JellyVariantBook.exclusives { XCTAssertNotEqual(v.palette.flesh, p.flesh) }
        XCTAssertEqual(GradientLook.Opal.stops.count, 5)
        // every other species keeps the mode it had
        for id in 0..<JellyRoster.knownCount where id != opal {
            XCTAssertNotEqual(BlueBelly.mode(for: JellyRoster.palette(id) ?? PaletteKey.blue.palette), 86, "species \(id)")
        }
    }

    func testSpringSpecialButNeverAStarter() {
        XCTAssertTrue(SpeciesInfo.special.contains(opal))
        XCTAssertFalse(SpeciesInfo.order.contains(opal))
        XCTAssertTrue(SpeciesInfo.pages(includingSpecial: true).contains(opal))
        XCTAssertFalse(SpeciesInfo.pages(includingSpecial: false).contains(opal))
        XCTAssertTrue(SpeciesInfo.of(opal).isSpecial)
        XCTAssertFalse(JellyRoster.defaultIDs.contains(opal))
        for n in 1...3 { XCTAssertFalse(JellyRoster.sanitised(Array(0..<n)).contains(opal)) }
        XCTAssertFalse(JellyVariants.takesVariant(opal))
        XCTAssertEqual(JellyRoster.characterCount, 4)
        let d = UserDefaults(suiteName: "OpalSpeciesTests.launch")!
        d.removePersistentDomain(forName: "OpalSpeciesTests.launch")
        XCTAssertTrue(JellyRoster.launchIDs(d).allSatisfy { $0 < 9 })
        d.removePersistentDomain(forName: "OpalSpeciesTests.launch")
    }

    func testContent() {
        let info = SpeciesInfo.of(opal)
        XCTAssertEqual(info.character, opal)
        XCTAssertEqual(info.name, "Opal")
        XCTAssertEqual(info.traits, JellyCandidates.baseJars(opal))
        XCTAssertEqual(JellyCandidates.baseJars(opal), [72, 68, 90, 50, 38])
        XCTAssertEqual(JellyCandidates.lovedSnack(opal), "popsicle")
        XCTAssertNotNil(Consumables.with(id: "popsicle"), "the loved snack is a store food (Ice pop)")
        XCTAssertEqual(Consumables.with(id: "popsicle")?.name, "Ice pop")
        XCTAssertEqual(info.loves, "Ice pop")
        XCTAssertEqual(info.emotes.count, 5)
        // earlier species keep their jars / snacks
        XCTAssertEqual(JellyCandidates.baseJars(JellyRoster.pandaID), [70, 80, 35, 40, 55])
        XCTAssertEqual(JellyCandidates.lovedSnack(JellyRoster.pearlID), "onigiri")
        XCTAssertNil(JellyCandidates.lovedSnack(JellyRoster.mooID))
    }

    func testSleepMask() {
        XCTAssertEqual(EyeMaskModel.paletteCount, 10)
        XCTAssertEqual(EyeMaskModel.rests.count, EyeMaskModel.paletteCount)
        XCTAssertEqual(EyeMaskModel.maskIndex(opal), 9)
        for id in 0...8 { XCTAssertEqual(EyeMaskModel.maskIndex(id), id) }
        for id in [9, 10, 11, 13, 17, 26, 100, -1] { XCTAssertEqual(EyeMaskModel.maskIndex(id), ((id % 9) + 9) % 9, "id \(id) wraps as before") }
        XCTAssertEqual(EyeMaskModel.palette(opal).band, Consumables.srgb(0.62, 0.52, 0.86))
        XCTAssertEqual(EyeMaskModel.palette(opal).piping, Consumables.srgb(0.96, 0.90, 1.0))
        XCTAssertEqual(EyeMaskModel.palette(0).band, Consumables.srgb(0.15, 0.19, 0.46), "Bob's navy is unchanged")
        XCTAssertEqual(EyeMaskModel.palette(JellyRoster.pandaID).band, Consumables.srgb(0.90, 0.45, 0.55))
        XCTAssertEqual(EyeMaskModel.palette(JellyRoster.berryID).band, Consumables.srgb(0.30, 0.62, 0.42))
        for id in 0..<JellyRoster.knownCount where id != opal { XCTAssertNotEqual(EyeMaskModel.palette(id).band, EyeMaskModel.palette(opal).band) }
    }

    func testHooksParse() {
        XCTAssertEqual(JellyRoster.parseRoster("opal"), [12])
        XCTAssertEqual(JellyRoster.parseRoster("bob,opal"), [0, 12])
    }
}
