//
//  LineupLooksSpeciesTests.swift
//  The 18 "Jelmiko Lineup" characters (ids 9...26, look phase 2026-11-18): they exist, are reachable through the test hooks, are offered nowhere, and the five gradient
//  characters (Sunset, Cotton Candy, Ocean, Lemon-Lime, Lagoon) get their own shader modes 81...85; Opal 12 has mode 86 (its real look); the 12 placeholders keep mode 0.
//  Modelled on TigerBerrySpeciesTests.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class LineupLooksSpeciesTests: XCTestCase {
    static let names = ["Marble", "Gold", "Silver", "Opal", "Moo", "Cocoa", "Blush", "Sunset", "Ruby", "Midnight", "Cotton Candy", "Ocean", "Lemon-Lime", "Lagoon", "Emerald", "Sapphire", "Amethyst", "Bronze"]
    static let ids = Array(9...26)
    static let gradients: [Int: Float] = [16: 81, 19: 82, 20: 83, 21: 84, 22: 85, 13: 91, 14: 93, 15: 95]          // (13 / 14 / 15 = the cow family, CowLook.swift)

    func testIdentity() {
        XCTAssertEqual(JellyRoster.knownCount, 27)
        XCTAssertEqual(JellyRoster.baseNames.count, 27)
        XCTAssertEqual(Array(JellyRoster.baseNames[9...26]), Self.names)
        let constants = [JellyRoster.marbleID, JellyRoster.goldID, JellyRoster.silverID, JellyRoster.opalID, JellyRoster.mooID, JellyRoster.cocoaID, JellyRoster.blushID,
                         JellyRoster.sunsetID, JellyRoster.rubyID, JellyRoster.midnightID, JellyRoster.cottonCandyID, JellyRoster.oceanID, JellyRoster.lemonLimeID,
                         JellyRoster.lagoonID, JellyRoster.emeraldID, JellyRoster.sapphireID, JellyRoster.amethystID, JellyRoster.bronzeID]
        XCTAssertEqual(constants, Self.ids)
        XCTAssertEqual(JellyRoster.characterCount, 4, "not offered: the intro / Jelly Spring pickers still show four")
        for id in Self.ids {
            XCTAssertTrue(JellyRoster.isValid(id))
            XCTAssertEqual(JellyRoster.species(id), id)
            XCTAssertEqual(JellyRoster.feature(id), JellyFeature.none, "the plain body: no ears, no tail, no wings")
            XCTAssertEqual(JellyRoster.palette(id)?.jellySpecies, id)
            XCTAssertEqual(JellyRoster.nameOf(id), Self.names[id - 9])
            XCTAssertEqual(JelbieA11yText.description(character: id).isEmpty, false)
        }
    }

    func testFleshIsUnique() {
        var seen: [(String, SIMD3<Float>)] = []
        for id in 0..<JellyRoster.knownCount {
            let f = (JellyRoster.palette(id) ?? PaletteKey.blue.palette).flesh
            for (n, o) in seen { XCTAssertNotEqual(f, o, "species \(id) shares its flesh value with \(n)") }
            seen.append(("species \(id)", f))
        }
        // never equal to a Jelly Spring colour variant (rare exclusives and the daily shades) or a park visitor's colour
        var others: [(String, SIMD3<Float>)] = []
        for v in JellyVariantBook.exclusives { others.append(("variant " + v.title, v.palette.flesh)) }
        for sp in 0...3 {
            others.append(("classic \(sp)", JellyVariantBook.classicPalette(sp).flesh))
            for day in [1, 100, 20000] { for v in JellyVariantBook.shades(species: sp, dayKey: day, owned: 0) { if let v { others.append(("shade \(sp)/\(day) " + v.title, v.palette.flesh)) } } }
        }
        for c in ParkColour.allCases { others.append(("park " + c.rawValue, JellyPalettes.park(c).flesh)) }
        for id in Self.ids {
            let f = JellyRoster.palette(id)!.flesh
            for (n, o) in others { XCTAssertNotEqual(f, o, "species \(id) shares its flesh value with \(n)") }
        }
    }

    func testOfferedNowhere() {
        for id in Self.ids where id != JellyRoster.opalID && !OpalSpringTests.springSeven.contains(id) {          // (Opal 12 and the seven new Spring looks are Jelly Spring specials: OpalSpringTests)
            XCTAssertFalse(SpeciesInfo.order.contains(id))
            XCTAssertFalse(SpeciesInfo.special.contains(id))
            XCTAssertFalse(SpeciesInfo.pages(includingSpecial: true).contains(id))
            XCTAssertFalse(SpeciesInfo.pages(includingSpecial: false).contains(id))
            XCTAssertFalse(JellyRoster.defaultIDs.contains(id))
            for n in 1...3 { XCTAssertFalse(JellyRoster.sanitised(Array(0..<n)).contains(id)) }
            XCTAssertFalse(JellyVariants.takesVariant(id), "no rare / mutation variant for a lineup character")
        }
        // no rare / mutation is ever offered for any species that can take one, and none of those is a lineup character
        for sp in 0...3 { for day in [1, 100, 20000] { _ = JellyVariantBook.offer(species: sp, dayKey: day) } }
        let d = UserDefaults(suiteName: "LineupLooksSpeciesTests.launch")!
        d.removePersistentDomain(forName: "LineupLooksSpeciesTests.launch")
        XCTAssertTrue(JellyRoster.launchIDs(d).allSatisfy { $0 < 9 }, "a fresh launch roster holds no lineup character")
        d.removePersistentDomain(forName: "LineupLooksSpeciesTests.launch")
    }

    func testBodyModes() {
        for id in Self.ids {
            let mode = BlueBelly.mode(for: JellyRoster.palette(id)!)
            XCTAssertEqual(mode, Self.gradients[id] ?? (id == JellyRoster.opalID ? 86 : 0), "species \(id) (\(Self.names[id - 9]))")          // (Opal 12 is no placeholder any more: mode 86, OpalSpeciesTests)
        }
        // every earlier species keeps the mode it had
        XCTAssertEqual(BlueBelly.mode(for: JellyRoster.palette(JellyRoster.pandaID)!), 51)
        XCTAssertEqual(BlueBelly.mode(for: JellyRoster.palette(JellyRoster.tigerID)!), 61)
        XCTAssertEqual(BlueBelly.mode(for: JellyRoster.palette(JellyRoster.berryID)!), 71)
        XCTAssertEqual(BlueBelly.mode(for: WhiteWing.palette), 0)
        XCTAssertEqual(BlueBelly.mode(for: JellyRoster.palette(JellyRoster.teddyID)!), TeddyEarsVariant.active == .cream ? 43 : 33)
        for id in 1...3 { XCTAssertFalse([81, 82, 83, 84, 85, 86].contains(BlueBelly.mode(for: JellyRoster.palette(id)!))) }
        for c in ParkColour.allCases { XCTAssertFalse((81...86).contains(Int(BlueBelly.mode(for: JellyPalettes.park(c)))), "park visitor \(c.rawValue) must not look like a gradient character") }
        // the middle stop is the flesh and the swatch
        for (id, _) in Self.gradients where GradientLook.stops[id] != nil {
            let s = GradientLook.stops[id]!
            XCTAssertEqual(JellyRoster.palette(id)!.flesh, s.middle)
            XCTAssertEqual(JellyRoster.tint(id), s.middle)
            XCTAssertTrue(s.tLo < s.tMid && s.tMid < s.tHi)
        }
    }

    func testHooksParse() {
        XCTAssertEqual(JellyRoster.parseRoster("bob,sunset,lemon-lime"), [0, 16, 21])
        XCTAssertEqual(JellyRoster.parseRoster("cotton candy"), [19])
        XCTAssertEqual(JellyRoster.parseRoster("Ocean, cotton candy, lagoon"), [20, 19, 22])
        XCTAssertEqual(JellyRoster.parseRoster("bob pip moss"), [0, 1, 2], "spaces still separate single-word names")
        XCTAssertEqual(JellyRoster.characterID(named: "26"), 26)
        let d = UserDefaults(suiteName: "LineupLooksSpeciesTests")!
        d.removePersistentDomain(forName: "LineupLooksSpeciesTests")
        d.set("lagoon", forKey: JellyRoster.forceSpeciesKey)
        XCTAssertEqual(JellyRoster.launchIDs(d).first, 22)
        d.removePersistentDomain(forName: "LineupLooksSpeciesTests")
    }
}
