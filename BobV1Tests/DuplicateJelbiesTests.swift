//
//  DuplicateJelbiesTests.swift
//  A second Bob (or Pip, Teddy ...) is allowed. Roster entries are INSTANCE ids (the first of a species keeps instance id == species id, a duplicate gets an id >= 100
//  from a counter whose species is recorded in the species map); look / voice / feature follow the SPECIES, saved state / names / colours the INSTANCE.
//  Fast and pure: own UserDefaults suites; the process-wide maps and roster are put back in tearDown.
//

import XCTest
@testable import BobV1

@MainActor
final class DuplicateJelbiesTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []         // the runtime aborts when a GameCare is released (see MelonModel)

    private var savedCurrent: [Int] = []
    private var savedMap: [Int: Int] = [:]
    private var savedNames: [Int: String] = [:]
    private var savedBaseNames: [String] = []
    private var suites: [String] = []

    override func setUp() {
        savedCurrent = JellyRoster.current
        savedMap = JellyRoster.speciesMap
        savedNames = JellyRoster.extraNames
        savedBaseNames = JellyRoster.names
        JellyRoster.speciesMap = [:]
        JellyRoster.extraNames = [:]
    }
    override func tearDown() {
        JellyRoster.current = savedCurrent
        JellyRoster.speciesMap = savedMap
        JellyRoster.extraNames = savedNames
        JellyRoster.names = savedBaseNames
        JellyVariants.reload()
        JellyVariants.clearPreviews()
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
    }

    private func suite(_ name: String = "x") -> UserDefaults {
        let s = "DuplicateJelbiesTests.\(name).\(UUID().uuidString)"
        suites.append(s)
        return UserDefaults(suiteName: s)!
    }

    // MARK: ids

    func testAllocateInstanceKeepsTheSpeciesIdForTheFirstAndCountsUpForDuplicates() {
        let d = suite()
        XCTAssertEqual(JellyRoster.allocateInstance(species: 0, roster: [], d), 0, "the first Bob is instance 0")
        XCTAssertNil(d.object(forKey: JellyRoster.nextInstanceKey), "no counter used for a first of a species")
        XCTAssertEqual(JellyRoster.allocateInstance(species: 0, roster: [0], d), 100, "a second Bob")
        XCTAssertEqual(d.integer(forKey: JellyRoster.nextInstanceKey), 101, "the counter is persisted")
        XCTAssertEqual(JellyRoster.species(100), 0)
        XCTAssertEqual(JellyRoster.loadSpeciesMap(d), [100: 0], "the species map is saved before the roster is")
        XCTAssertEqual(JellyRoster.allocateInstance(species: 0, roster: [0, 100], d), 101, "a third Bob")
        XCTAssertEqual(JellyRoster.loadSpeciesMap(d), [100: 0, 101: 0])
        // ids are never reused: even with the roster emptied the counter moves on
        XCTAssertEqual(JellyRoster.allocateInstance(species: 0, roster: [0], d), 102)
    }

    func testANewSpeciesTakesItsOwnIdAndADuplicateOfItGetsAnInstance() {
        let d = suite()
        XCTAssertEqual(JellyRoster.allocateInstance(species: 1, roster: [0, 1], d), 100, "a second Pip while Bob is also home")
        XCTAssertEqual(JellyRoster.species(100), 1)
        XCTAssertEqual(JellyRoster.allocateInstance(species: 4, roster: [0], d), 4, "Teddy, first of his kind")
    }

    func testSpeciesIsIdentityBelow100AndResolvesPreviewScratchIds() {
        for s in 0..<JellyRoster.knownCount { XCTAssertEqual(JellyRoster.species(s), s) }
        XCTAssertEqual(JellyRoster.previewID(4), 1004)
        XCTAssertEqual(JellyRoster.species(1004), 4)
        XCTAssertTrue(JellyRoster.isValid(1004))
        XCTAssertFalse(JellyRoster.isValid(1007))
        XCTAssertFalse(JellyRoster.isValid(100), "not in the map")
        JellyRoster.speciesMap = [100: 3]
        XCTAssertTrue(JellyRoster.isValid(100))
        XCTAssertEqual(JellyRoster.species(100), 3)
    }

    func testSanitisedKeepsRecordedDuplicatesAndDropsUnknownIds() {
        JellyRoster.speciesMap = [100: 0, 101: 0]
        XCTAssertEqual(JellyRoster.sanitised([0, 100, 101]), [0, 100, 101])
        XCTAssertEqual(JellyRoster.sanitised([0, 9, 50, 100, 100]), [0, 100], "unknown ids dropped, repeats of one id dropped")
        XCTAssertEqual(JellyRoster.sanitised([2, 2, 9, 1]), [2, 1], "unchanged")
        XCTAssertEqual(JellyRoster.sanitised([0, 100, 101, 1]), [0, 100, 101], "capped at three")
    }

    func testSaveRoundTripKeepsADuplicate() {
        let d = suite()
        let id = JellyRoster.allocateInstance(species: 0, roster: [0], d)
        JellyRoster.save([0, id], to: d)
        XCTAssertEqual(d.array(forKey: JellyRoster.rosterKey) as? [Int], [0, 100])
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 100])
        // a relaunch: the maps come back from the save before the roster is read
        JellyRoster.speciesMap = [:]
        JellyRoster.reloadSpecies(d)
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 100])
    }

    // MARK: names

    func testNamesOfDuplicatesAreSavedPerInstance() {
        let d = suite()
        _ = JellyRoster.allocateInstance(species: 0, roster: [0], d)
        XCTAssertEqual(JellyRoster.nameOf(100), "Bob", "no name yet: the species name")
        JellyRoster.setName(100, "Rex", d)
        XCTAssertEqual(JellyRoster.nameOf(100), "Rex")
        XCTAssertEqual(JellyRoster.nameOf(0), JellyRoster.names[0], "the first Bob is untouched")
        JellyRoster.setName(150, "Ghost", d)
        XCTAssertEqual(JellyRoster.nameOf(150), "Bob", "an id that was never allocated is ignored")
        JellyRoster.extraNames = [:]
        JellyRoster.reloadSpecies(d)
        XCTAssertEqual(JellyRoster.nameOf(100), "Rex", "survives a reload")
        JellyRoster.setName(100, "  ", d)
        XCTAssertEqual(JellyRoster.nameOf(100), "Bob", "empty = back to the species name")
        XCTAssertEqual(JellyRoster.nameOf(1004), "Teddy", "a preview scratch id shows its species name")
    }

    func testSuggestedAndUniqueNames() {
        XCTAssertEqual(JellyRoster.suggestedName(species: 4, taken: []), "Teddy")
        XCTAssertEqual(JellyRoster.suggestedName(species: 4, taken: ["Teddy"]), "Teddy 2")
        XCTAssertEqual(JellyRoster.suggestedName(species: 4, taken: ["teddy", "Teddy 2"]), "Teddy 3")
        XCTAssertEqual(JellyRoster.suggestedName(species: 0, taken: ["Rex", "Pip"]), "Bob")
        XCTAssertEqual(JellyRoster.suggestedName(species: 3, taken: ["Lavender", "Lavender 2"]), "Lavender 3")
        XCTAssertLessThanOrEqual(JellyRoster.suggestedName(species: 3, taken: ["Lavender", "Lavender 2"]).count, 12)
        XCTAssertEqual(JellyRoster.uniqueName("Rex", taken: ["Bob", "rex"]), "Rex 2")
        XCTAssertEqual(JellyRoster.uniqueName("Sam", taken: ["Bob"]), "Sam")
    }

    // MARK: look follows the species, state follows the instance

    func testPaletteFeatureAndTintOfADuplicateAreTheSpeciesLook() {
        JellyRoster.speciesMap = [100: 1, 101: 0, 102: 5, 103: 4]
        JellyVariants.reload(suite())          // no adopted colours
        XCTAssertEqual(JellyRoster.feature(100), .spines, "a second Pip keeps his spines")
        XCTAssertEqual(JellyRoster.palette(100)?.flesh, PaletteKey.yellow.palette.flesh)
        XCTAssertEqual(JellyRoster.tint(100), JellyRoster.tint(1))
        XCTAssertEqual(JellyRoster.feature(101), .none)
        XCTAssertNil(JellyRoster.palette(101), "Bob blue is the model's own palette")
        XCTAssertEqual(JellyRoster.feature(102), .wings)
        XCTAssertEqual(JellyRoster.palette(102)?.flesh, JellyRoster.palette(5)?.flesh, "a second Pearl is white")
        XCTAssertTrue(WhiteWing.hasLook(102))
        XCTAssertEqual(JellyRoster.feature(103), .ears)
        XCTAssertEqual(JellyRoster.tint(103), JellyRoster.tint(JellyRoster.teddyID))
        XCTAssertEqual(JelbieA11yText.description(character: 103), JelbieA11yText.description(character: JellyRoster.teddyID))
        XCTAssertEqual(JelbieA11yText.description(character: 102), JelbieA11yText.description(character: JellyRoster.pearlID))
    }

    func testAdoptedColourBelongsToTheInstance() {
        let d = suite()
        JellyRoster.speciesMap = [100: 0, 102: 4]
        JellyVariants.reload(d)
        let v = JellyVariantBook.exclusives[1]
        JellyVariants.adopt(100, v, d)
        XCTAssertEqual(JellyVariants.active(100), v)
        XCTAssertNil(JellyVariants.active(0), "the first Bob keeps his own colour")
        XCTAssertNil(JellyRoster.palette(0))
        XCTAssertEqual(JellyRoster.palette(100)?.flesh, v.palette.flesh)
        XCTAssertEqual(JellyRoster.tint(100), v.swatch)
        XCTAssertEqual(JellyVariants.load(d).keys.sorted(), [100], "saved under the instance id")
        JellyVariants.adopt(102, v, d)          // Teddy-species duplicates never take a variant
        XCTAssertNil(JellyVariants.active(102))
        JellyVariants.adopt(150, v, d)          // an unrecorded id neither
        XCTAssertNil(JellyVariants.active(150))
        // a picker preview uses the scratch id and does not recolour an owned Bob
        JellyVariants.setPreview(JellyRoster.previewID(0), JellyVariantBook.exclusives[2])
        XCTAssertNil(JellyVariants.active(0))
        XCTAssertEqual(JellyVariants.active(JellyRoster.previewID(0)), JellyVariantBook.exclusives[2])
        XCTAssertEqual(JellyVariants.active(100), v)
    }

    func testGameCareBuildsARoomWithADuplicateAndKeepsItsStateApart() {
        let d = suite("care")
        JellyRoster.speciesMap = [100: 0]
        JellyRoster.setName(100, "Rex", d)
        let care = GameCare(roster: [0, 100], persistent: true, defaults: d)
        Self.keep.append(care)
        XCTAssertEqual(care.roster, [0, 100])
        XCTAssertEqual(care.jellies.map(\.character), [0, 100])
        XCTAssertEqual(care.jellies.map(\.species), [0, 0])
        XCTAssertEqual(care.jellies.map(\.name), [JellyRoster.names[0], "Rex"])
        XCTAssertNotNil(d.object(forKey: JellyKeys.needs(100)), "the duplicate has his own needs key")
        XCTAssertEqual(care.jelly(1)?.feature, JellyFeature.none)
        // widget: colour by species, the instance for the portrait palette
        let ins = care.widgetInputs()
        XCTAssertEqual(ins.map(\.color), ["blue", "blue"])
        XCTAssertEqual(ins.map(\.character), [0, 100])
        XCTAssertNotEqual(WidgetBridge.lookKey(ins[0]), WidgetBridge.lookKey(ins[1]), "two Bobs are two portraits")
        // outfits are saved by instance
        XCTAssertEqual(care.store.characterOf(1), 100)
        XCTAssertTrue(care.store.awardMedal())
        let look = WearLook.medalGold
        XCTAssertTrue(care.store.wear(look, on: 1))
        XCTAssertEqual(care.store.worn(1, look.slot), look)
        XCTAssertNil(care.store.worn(0, look.slot), "the other Bob wears nothing")
        XCTAssertEqual(care.store.saved.worn.keys.sorted(), ["100"])
        // the selection cards read names through nameOf
        XCTAssertEqual(JellyRoster.selectBlobs(roster: [0, 100]).map(\.name), [JellyRoster.names[0], "Rex"])
    }

    // MARK: widget

    func testWidgetColourNameUsesTheSpeciesAndThePortraitPaletteTheInstance() {
        JellyRoster.speciesMap = [100: 1]
        JellyVariants.reload(suite())
        XCTAssertEqual(WidgetBridge.colorName(JellyRoster.species(100)), "yellow")
        XCTAssertEqual(JelbieRoster.colorName(JellyRoster.species(100)), "yellow")
        XCTAssertEqual(WidgetBridge.palette(100).flesh, PaletteKey.yellow.palette.flesh)
        XCTAssertTrue(JelbieRoster.current(directory: nil, roster: [0, 100]).isEmpty, "no snapshot: no Jelmiko are offered (apple-fixes-r1 H)")
    }

    // MARK: voice

    func testVoiceNamesFindADuplicateByItsOwnNameAndTheBaseNameFindsTheFirst() {
        JellyRoster.speciesMap = [100: 0, 103: 2]
        JellyRoster.extraNames = [100: "Rex"]
        let n = JellyNames(defaults: suite(), key: "nick", persists: false)
        n.roster = [0, 100]
        XCTAssertEqual(n.resolve(tokens: ["rex"]).first?.id, 1, "his own name goes to the duplicate's slot")
        XCTAssertEqual(n.resolve(tokens: ["bob"]).first?.id, 0, "the base name goes to the first Bob")
        XCTAssertEqual(n.displayName(1), "Rex")
        XCTAssertTrue(n.addNickname("sunny", for: 1))
        XCTAssertEqual(n.nicknames(for: 1), ["sunny"])
        XCTAssertEqual(n.nicknames[100], ["sunny"], "nicknames are keyed by instance")
        XCTAssertEqual(n.resolve(tokens: ["sunny"]).first?.id, 1)
        XCTAssertTrue(n.nicknames(for: 0).isEmpty)
        // an instance that is not in the room round-trips through its absent id
        let absent = JellyNames.absentID(103)
        XCTAssertEqual(n.id(ofCharacter: 103), absent)
        XCTAssertEqual(n.character(absent), 103)
        XCTAssertGreaterThanOrEqual(absent, JellyRoster.maxCount, "never a slot")
    }

    func testTheBaseNameFindsTheDuplicateThatStillHasTheBaseName() {
        JellyRoster.speciesMap = [100: 0]
        JellyRoster.extraNames = [100: "Bob"]
        let n = JellyNames(defaults: suite(), key: "nick", persists: false)
        JellyRoster.setName(0, "Sunny", suite())          // the first Bob was renamed, the second kept "Bob"
        n.roster = [0, 100]
        XCTAssertEqual(n.resolve(tokens: ["bob"]).first?.id, 1)
    }

    // MARK: audio

    func testADuplicateTeddySpeaksWithTeddysVoice() {
        JellyRoster.speciesMap = [100: JellyRoster.teddyID]
        JellyRoster.current = [JellyRoster.teddyID, 100]
        XCTAssertEqual(JellyRoster.speciesOf(slot: 1), JellyRoster.teddyID)
        XCTAssertEqual(AudioHub.voiceFile(slot: 1, .happy), AudioHub.voiceFile(slot: 0, .happy))
        XCTAssertEqual(JellyRoster.slots(ofSpecies: JellyRoster.teddyID), [0, 1])
        XCTAssertEqual(JellyRoster.name(slot: 1), "Teddy")
    }

    // MARK: adoption rules

    func testAdoptionAllowsDuplicatesUntilTheRoomIsFull() {
        // the picker flow, by ids: Bob, a second Bob, a Pip; then no price at all
        let d = suite()
        var roster: [Int] = []
        for s in [0, 0, 1] {
            XCTAssertNotNil(AdoptionPrice.next(home: roster.count), "room for one more at \(roster.count)")
            roster.append(JellyRoster.allocateInstance(species: s, roster: roster, d))
        }
        XCTAssertEqual(roster, [0, 100, 1])
        XCTAssertEqual(roster.map(JellyRoster.species), [0, 0, 1])
        XCTAssertNil(AdoptionPrice.next(home: roster.count), "the 4th is refused")
        XCTAssertEqual(AdoptionPrice.next(home: 2), 800)
        XCTAssertEqual(AdoptionPrice.next(home: 1), 500)
        // the Spring's offer (own colour, or the rare mutation) is one of the pick page's three shades for every species, the ones at home included; the free first gift is classic for all three
        let day = JellyVariantBook.dayKey()
        for s in 0...3 {
            let shades = JellyVariantBook.shades(species: s, dayKey: day, owned: 1)
            XCTAssertEqual(shades.count, 3)
            if let o = JellyVariantBook.offer(species: s, dayKey: day) { XCTAssertTrue(shades.contains { $0 == o }) }
        }
        XCTAssertTrue(AdoptionCenter.makeCandidates(mode: .first, species: 0, dayKey: day, home: []).allSatisfy { $0.variant == nil })
    }

    func testResetCharacterStateClearsAPreviewScratchId() {
        let d = suite()
        let scratch = JellyRoster.previewID(0)
        d.set(Data([1]), forKey: JellyKeys.needs(scratch))
        d.set(Data([1]), forKey: JellyKeys.needs(100))
        StartFlow.resetCharacterState(scratch, d)
        XCTAssertNil(d.object(forKey: JellyKeys.needs(scratch)))
        XCTAssertNotNil(d.object(forKey: JellyKeys.needs(100)), "another Jelmiko's keys stay")
    }
}
