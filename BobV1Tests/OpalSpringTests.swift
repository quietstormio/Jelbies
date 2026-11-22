//
//  OpalSpringTests.swift
//  Opal (character 12) is a Jelly Spring special like Teddy / Pearl / Panda: its own page, the specials' price (2,000 JellyCoins), never a starter, only ever met in the park by a
//  player who owns one, and every table keyed by species has an entry for it. Tiger, Berry and the other lineup ids stay offered nowhere.
//

import XCTest
@testable import BobV1

@MainActor
final class OpalSpringTests: XCTestCase {
    let opal = JellyRoster.opalID
    private var suites: [String] = []
    private var savedMap: [Int: Int] = [:], savedNames: [Int: String] = [:], savedCurrent: [Int] = []

    override func setUp() {
        super.setUp()
        savedMap = JellyRoster.speciesMap; savedNames = JellyRoster.extraNames; savedCurrent = JellyRoster.current
    }
    override func tearDown() {
        JellyRoster.speciesMap = savedMap; JellyRoster.extraNames = savedNames; JellyRoster.current = savedCurrent
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
        super.tearDown()
    }
    private func suite() -> UserDefaults { let s = "OpalSpringTests.\(UUID().uuidString)"; suites.append(s); return UserDefaults(suiteName: s)! }

    /// Moo, Cocoa, Blush (cows; listed only while `SpeciesInfo.cowsInStore`) and Sunset, Cotton Candy, Ocean, Lagoon.
    static let springSeven = [13, 14, 15, 16, 19, 20, 22]

    // MARK: the Spring

    func testTheSevenNewSpringLooksAreSpecialsAtOpalsPriceAndRules() {
        let gradients = [16, 19, 20, 22]
        XCTAssertEqual(SpeciesInfo.gradientIDs, gradients)
        XCTAssertEqual(SpeciesInfo.cowIDs, [13, 14, 15])
        for id in Self.springSeven {
            XCTAssertEqual(SpeciesInfo.of(id).character, id, "an info entry for \(id)")
            XCTAssertEqual(SpeciesInfo.of(id).name, JellyRoster.baseNames[id])
            XCTAssertEqual(SpeciesInfo.of(id).traits, JellyCandidates.baseJars(id))
            XCTAssertFalse(SpeciesInfo.order.contains(id))
            XCTAssertFalse(SpeciesInfo.pages(includingSpecial: false).contains(id))
            XCTAssertFalse(JellyRoster.defaultIDs.contains(id))
            XCTAssertFalse(JellyVariants.takesVariant(id))
            XCTAssertNotNil(NameIdeas.pool[id])
            XCTAssertTrue(ParkPool.all().allSatisfy { $0.species != id }, "no park visitor of \(id)")
            let listed = gradients.contains(id) || SpeciesInfo.cowsInStore
            XCTAssertEqual(SpeciesInfo.special.contains(id), listed, "\(id)")
            XCTAssertEqual(SpeciesInfo.pages(includingSpecial: true).contains(id), listed, "\(id)")
            XCTAssertEqual(SpeciesInfo.of(id).isSpecial, listed, "\(id)")
            if listed {
                XCTAssertEqual(AdoptionPrice.next(home: 1, special: true), 2000)
                let c = AdoptionCenter.makeCandidates(mode: .more, species: id, dayKey: 800_001, home: [0])
                XCTAssertTrue(c.allSatisfy { $0.variant == nil })
            }
        }
    }

    func testOpalIsOnTheSpringListWithTheSpecialsPriceAndRules() {
        XCTAssertEqual(opal, 12)
        XCTAssertEqual(SpeciesInfo.special, [4, 5, 6, 12] + (SpeciesInfo.cowsInStore ? [13, 14, 15] : []) + [16, 19, 20, 22] + (SpeciesInfo.lineupRestInStore ? SpeciesInfo.lineupRestIDs : []))
        XCTAssertEqual(SpeciesInfo.pages(includingSpecial: true), [0, 1, 3, 2] + SpeciesInfo.special, "its own page after Panda")
        XCTAssertTrue(SpeciesInfo.of(opal).isSpecial)
        XCTAssertEqual(SpeciesInfo.of(opal).name, "Opal")
        // never a starter / free first gift
        XCTAssertFalse(SpeciesInfo.order.contains(opal))
        XCTAssertFalse(SpeciesInfo.pages(includingSpecial: false).contains(opal))
        XCTAssertFalse(JellyRoster.defaultIDs.contains(opal))
        XCTAssertEqual(JellyRoster.characterCount, 4)
        // the same price and rules as Teddy / Pearl / Panda: 2,000 whichever slot, at Camp too, nothing when both are full, never a rare colour
        XCTAssertEqual(AdoptionPrice.special, 2000)
        let sp = SpeciesInfo.of(opal).isSpecial
        XCTAssertEqual(AdoptionPrice.next(home: 1, special: sp), 2000)
        XCTAssertEqual(AdoptionPrice.next(home: 2, special: sp), 2000)
        XCTAssertEqual(AdoptionPrice.next(home: 3, camp: 0, special: sp), 2000)
        XCTAssertNil(AdoptionPrice.next(home: 3, camp: JellyCamp.cap, special: sp))
        for d in 800_000..<800_100 {
            let c = AdoptionCenter.makeCandidates(mode: .more, species: opal, dayKey: d, home: [0])
            XCTAssertEqual(c.count, 3)
            XCTAssertTrue(c.allSatisfy { $0.variant == nil }, "classic for all three, never a rare colour")
        }
        XCTAssertFalse(JellyVariants.takesVariant(opal))
    }

    func testOtherLineupIdsAreStillOfferedNowhere() {
        let pool = ParkPool.all()
        for id in 7...26 where id != opal && !Self.springSeven.contains(id) {
            XCTAssertFalse(SpeciesInfo.order.contains(id), "\(id)")
            XCTAssertFalse(SpeciesInfo.special.contains(id), "\(id)")
            XCTAssertFalse(SpeciesInfo.pages(includingSpecial: true).contains(id), "\(id)")
            XCTAssertFalse(SpeciesInfo.pages(includingSpecial: false).contains(id), "\(id)")
            XCTAssertFalse(SpeciesInfo.of(id).isSpecial, "\(id)")
            XCTAssertFalse(JellyRoster.defaultIDs.contains(id), "\(id)")
            XCTAssertTrue(pool.allSatisfy { $0.species != id }, "no park visitor of \(id)")
        }
        XCTAssertEqual(JellyRoster.tigerID, 7); XCTAssertEqual(JellyRoster.berryID, 8)
    }

    // MARK: new game, adoption, save

    func testANewGameNeverStartsWithOpal() {
        let d = suite()
        XCTAssertFalse(JellyRoster.launchIDs(d).contains(opal))
        XCTAssertFalse(JellyRoster.savedIDs(d).contains(opal))
        for n in 1...3 { XCTAssertFalse(JellyRoster.sanitised(Array(0..<n)).contains(opal)) }
        XCTAssertFalse(JellyRoster.sanitised([]).contains(opal))
    }

    func testAdoptingOpalPutsSpecies12InTheRosterAndSurvivesASaveRoundTripAndAnImport() throws {
        let d = suite()
        JellyRoster.save([0], to: d)
        let p = try XCTUnwrap(StartFlow.placeNew(species: opal, name: "Opal", variant: nil, traits: nil, first: false, d))
        XCTAssertEqual(p.destination, .home)
        XCTAssertEqual(p.id, opal, "the first Opal is its own instance id")
        XCTAssertEqual(JellyRoster.species(p.id), opal)
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, opal])
        // a relaunch
        JellyRoster.speciesMap = [:]; JellyRoster.reloadSpecies(d)
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, opal])
        XCTAssertEqual(JellyRoster.species(JellyRoster.savedIDs(d)[1]), opal)
        // a second Opal is an instance whose species is remembered (home holds three: it goes to the Camp)
        JellyRoster.save([0, 1, opal], to: d)
        let p2 = try XCTUnwrap(StartFlow.placeNew(species: opal, name: "Opal 2", variant: nil, traits: nil, first: false, d))
        XCTAssertEqual(p2.destination, .camp)
        XCTAssertGreaterThanOrEqual(p2.id, JellyRoster.firstInstanceID)
        JellyRoster.speciesMap = [:]; JellyRoster.reloadSpecies(d)
        XCTAssertEqual(JellyRoster.species(p2.id), opal)
        // an import (an old save's room) leaves the roster, and so the Opal, alone
        let report = ImportSave.merge(old: [:], into: d)
        XCTAssertTrue(report.applied)
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 1, opal])
    }

    // MARK: the park, rivals, guests: never without one owned

    func testParkCastNeverHasOpalWithoutOneOwned() {
        let pool = ParkPool.all(reserved: ParkBook.reservedNames())
        XCTAssertTrue(pool.allSatisfy { $0.species != opal }, "no Opal visitor exists: the park shows only the player's own Opal (Teddy / Pearl / Panda keep their six)")
        XCTAssertEqual(pool.count, ParkTuning.fullPoolSize)
        XCTAssertTrue(pool.filter { $0.species == nil }.allSatisfy { [0, 1, 2, 3].contains($0.kind) })
        for unlocked: Set<Int> in [[], [4, 5, 6], [7, 8, 9, 11, 13]] {
            for seed in 0..<600 {
                var rng = SplitMix(s: UInt64(seed) &* 0x9E37_79B9 &+ 7)
                let cast = ParkPool.pickCast(from: pool, count: 1 + seed % 4, characters: [0, 1], now: 1_000_000, household: [0], unlocked: unlocked, using: &rng)
                XCTAssertFalse(cast.contains { $0.species == opal }, "Opal came without being owned")
            }
        }
        // what the park counts as unlocked
        let d = suite()
        XCTAssertFalse(GameCare.parkUnlockedSpecials(owned: [0, 1, 4], defaults: d).contains(opal))
        XCTAssertTrue(GameCare.parkUnlockedSpecials(owned: [opal], defaults: d).contains(opal))
    }

    func testGuestCafeVolleyPoolsHoldNoOpal() {
        // the guest / café-regular / volley friend pools all filter on `species == nil` (the special visitors are park-only): none of them can be Opal
        let classic = ParkPool.all().filter { $0.species == nil }
        XCTAssertFalse(classic.isEmpty)
        XCTAssertTrue(classic.allSatisfy { $0.kind <= 3 })
        XCTAssertFalse(LocalRivalSource.hues.isEmpty, "a race rival is a pastel tint on a borrowed body, never a species")
    }

    // MARK: tables

    func testEverySpeciesIndexedTableHasAnEntryForOpal() {
        XCTAssertEqual(JellyRoster.baseNames.count, JellyRoster.knownCount)
        XCTAssertEqual(JellyRoster.baseNames[opal], "Opal")
        XCTAssertEqual(JellyRoster.names.count, JellyRoster.knownCount)
        XCTAssertNotNil(JellyRoster.palette(opal)); XCTAssertEqual(JellyRoster.feature(opal), .none)
        XCTAssertEqual(JellyRoster.tint(opal), GradientLook.Opal.swatch)
        XCTAssertEqual(SpeciesInfo.all.filter { $0.character == opal }.count, 1)
        XCTAssertEqual(SpeciesInfo.of(opal).defaultName, "Opal")
        XCTAssertEqual(JellyCandidates.baseJars(opal), SpeciesInfo.of(opal).traits)
        XCTAssertEqual(JellyCandidates.lovedSnack(opal), "popsicle")
        // widget, Shortcuts / Siri, accessibility
        XCTAssertEqual(WidgetBridge.colorName(opal), "opal"); XCTAssertEqual(WidgetBridge.character(ofColor: "opal"), opal)
        XCTAssertEqual(JelbieRoster.colorName(opal), "opal")
        XCTAssertTrue(JelbieA11yText.label(name: "Glim", character: opal).hasPrefix("Glim, pearly pastel"))
        // voice name, the voice set, the sleep mask, the naming chips
        XCTAssertEqual(JellyNameRoster.name(opal)?.base, "opal")
        XCTAssertFalse(JellyVoiceSet.file(character: opal, .happy).isEmpty)
        XCTAssertFalse(JellyVoiceSet.snoreFile(character: opal, roll: 0.5).isEmpty)
        XCTAssertEqual(EyeMaskModel.maskIndex(opal), 9)
        XCTAssertEqual(NameIdeas.ideas(species: opal, index: 1, taken: []).count, 3)
        XCTAssertEqual(NameIdeas.ideas(species: opal, index: 0, taken: ["Opal"]).count, 3)
        XCTAssertTrue(NameIdeas.pool[opal]!.allSatisfy { $0.count <= 12 })
        // preview scratch ids
        XCTAssertEqual(JellyRoster.species(JellyRoster.previewID(species: opal, slot: 1)), opal)
        // every id resolves in the widget tables and has an accessibility line, so nothing falls back to a wrong species
        for id in 0..<JellyRoster.knownCount {
            XCTAssertFalse(JelbieA11yText.description(character: id).isEmpty, "\(id)")
            XCTAssertEqual(WidgetBridge.character(ofColor: WidgetBridge.colorName(id)), id, "\(id)")
            XCTAssertEqual(JelbieRoster.colorName(id), WidgetBridge.colorName(id), "\(id)")
        }
    }
}
