//
//  SetRosterTests.swift
//  The roster as a list of characters by slot (JellyRoster.current), the `-SetRoster pip,moss,lavender` launch argument, and what follows
//  from a slot being a different character: saved data stays with the character, colours / features / names / voice names follow him.
//

import XCTest
@testable import BobV1

@MainActor
final class SetRosterTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []         // the runtime aborts when a GameCare is released (see MelonModel)

    private func suite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "SetRoster.\(name)")!
        d.removePersistentDomain(forName: "SetRoster.\(name)")
        return d
    }

    func testParseRosterNamesIdsDuplicatesAndCap() {
        XCTAssertEqual(JellyRoster.parseRoster("pip,moss,lavender"), [1, 2, 3])
        XCTAssertEqual(JellyRoster.parseRoster("Pip, Bob"), [1, 0], "case-insensitive, spaces allowed, order kept")
        XCTAssertEqual(JellyRoster.parseRoster("3,0"), [3, 0], "ids work too")
        XCTAssertEqual(JellyRoster.parseRoster("bob,bob,pip,moss,lavender"), [0, 1, 2], "repeats dropped, capped at three")
        XCTAssertEqual(JellyRoster.parseRoster("pip,nobody,moss"), [1, 2], "unknown names dropped")
        XCTAssertNil(JellyRoster.parseRoster("nobody"))
        XCTAssertNil(JellyRoster.parseRoster(""))
        XCTAssertEqual(JellyRoster.sanitised([]), [0, 1, 2])
        XCTAssertEqual(JellyRoster.sanitised([2, 2, 9, 1]), [2, 1])
    }

    func testSetRosterArgumentReplacesTheSavedRosterOnceAndIsIdempotent() {
        let d = suite("apply")
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 1, 2], "a fresh install: Bob, Pip, Moss")
        XCTAssertEqual(JellyRoster.launchIDs(d), [0, 1, 2])
        XCTAssertNil(d.array(forKey: JellyRoster.rosterKey), "nothing written without the argument")

        d.set("pip,moss,lavender", forKey: JellyRoster.setRosterKey)              // the launch argument
        XCTAssertEqual(JellyRoster.applySetRoster(d), [1, 2, 3])
        XCTAssertEqual(d.array(forKey: JellyRoster.rosterKey) as? [Int], [1, 2, 3], "persisted")
        XCTAssertEqual(JellyRoster.applySetRoster(d), [1, 2, 3], "again: the same")
        XCTAssertEqual(JellyRoster.launchIDs(d), [1, 2, 3])
        XCTAssertEqual(JellyRoster.launchCount(d), 3)

        d.removeObject(forKey: JellyRoster.setRosterKey)                            // the next launch without it
        XCTAssertEqual(JellyRoster.launchIDs(d), [1, 2, 3], "the saved roster stays")
        d.set(2, forKey: "BlobCount")
        XCTAssertEqual(JellyRoster.launchIDs(d), [1, 2], "-BlobCount cuts the roster")
        d.removeObject(forKey: "BlobCount")

        d.set("nobody", forKey: JellyRoster.setRosterKey)
        XCTAssertEqual(JellyRoster.launchIDs(d), [1, 2, 3], "garbage leaves the roster alone")
    }

    func testCurrentRosterMapsSlotsToCharacters() {
        let saved = JellyRoster.current
        defer { JellyRoster.current = saved }
        XCTAssertEqual(saved, [0, 1, 2], "the test host runs the default roster")
        JellyRoster.current = [1, 2, 3]
        XCTAssertEqual(JellyRoster.character(0), 1)
        XCTAssertEqual(JellyRoster.name(slot: 2), "Lavender")
        XCTAssertEqual(JellyRoster.feature(slot: 0), .spines)
        XCTAssertEqual(JellyRoster.palette(slot: 0)?.flesh, PaletteKey.yellow.palette.flesh)
        XCTAssertEqual(JellyRoster.tint(slot: 2), JellyRoster.tint(3))
        XCTAssertNil(JellyRoster.slot(ofCharacter: 0), "Bob is not in the room")
        XCTAssertEqual(JellyRoster.slot(ofCharacter: 3), 2)
    }

    func testGameCareKeepsEachCharactersDataAndStartsLavenderFresh() {
        let d = suite("care")
        // what the phone already has: Bob's legacy keys and Pip's own keys
        let bob = BlobNeeds(defaults: d, key: JellyKeys.needs(0)); bob.set(.hunger, 0.11); bob.save()
        let pip = BlobNeeds(defaults: d, key: JellyKeys.needs(1)); pip.set(.hunger, 0.33); pip.save()
        JellyStats(defaults: d, key: JellyKeys.stats(1)).set(waddle: 0.9)
        XCTAssertNil(d.object(forKey: JellyKeys.needs(3)), "Lavender has never been in the room")

        let care = GameCare(roster: [1, 2, 3], persistent: true, defaults: d)
        Self.keep.append(care)
        XCTAssertEqual(care.roster, [1, 2, 3])
        XCTAssertEqual(care.jellies.map(\.name), ["Pip", "Moss", "Lavender"])
        XCTAssertEqual(care.jellies.map(\.id), [0, 1, 2], "ids are slots")
        XCTAssertEqual(care.jellies.map(\.character), [1, 2, 3])
        // slot 0 (the legacy objects) is Pip, reading Pip's saved data
        XCTAssertEqual(care.jelly(0)?.needs.level(.hunger) ?? -1, 0.33, accuracy: 0.02, "slot 0 reads Pip's needs")
        XCTAssertTrue(care.needs === care.jelly(0)?.needs)
        XCTAssertEqual(care.jelly(0)?.stats.waddle ?? -1, 0.9, accuracy: 1e-5, "Pip keeps his stats")
        XCTAssertEqual(care.jelly(0)?.feature, .spines)
        XCTAssertEqual(care.jelly(2)?.feature, .wings)
        // Bob's data is untouched (nothing copied, nothing cleared)
        XCTAssertEqual(BlobNeeds(defaults: d, key: JellyKeys.needs(0)).level(.hunger), 0.11, accuracy: 0.02)
        // Lavender was initialised fresh and saved under her own keys
        XCTAssertNotNil(d.object(forKey: JellyKeys.needs(3)))
        // the widget sees colours and features by character, ids by slot
        let ins = care.widgetInputs()
        XCTAssertEqual(ins.map(\.id), [0, 1, 2])
        XCTAssertEqual(ins.map(\.color), ["yellow", "green", "lavender"])
        XCTAssertEqual(WidgetBridge.record(ins[2], look: "").feature, "wings")
        XCTAssertEqual(WidgetBridge.record(ins[0], look: "").feature, "spines")
        XCTAssertEqual(WidgetBridge.palette(color: "green").flesh, JellyPalettes.green.flesh)
    }

    func testVoiceNamesResolveToSlotsAndNicknamesFollowTheCharacter() {
        let n = JellyNames(defaults: suite("names"), persists: false)
        n.roster = [1, 2, 3]
        XCTAssertEqual(n.match(token: "pip")?.id, 0, "Pip is in slot 0")
        XCTAssertEqual(n.match(token: "lavender")?.id, 2)
        XCTAssertEqual(n.match(token: "bob")?.id, JellyNames.absentID(0), "Bob is not here: never a slot")
        XCTAssertGreaterThanOrEqual(n.match(token: "bob")!.id, JellyRoster.maxCount)
        XCTAssertEqual(n.displayName(0), "Pip")
        XCTAssertEqual(n.displayName(JellyNames.absentID(0)), "Bob")
        XCTAssertTrue(n.addNickname("squeaky", for: 0))
        XCTAssertEqual(n.nicknames(for: 0), ["squeaky"])
        XCTAssertEqual(n.match(token: "squeaky")?.id, 0)
        n.roster = [0, 1, 2]                                                         // Pip moves to slot 1: the nickname is still his
        XCTAssertEqual(n.nicknames(for: 1), ["squeaky"])
        XCTAssertEqual(n.match(token: "squeaky")?.id, 1)
        XCTAssertEqual(n.match(token: "pip")?.id, 1)
        XCTAssertEqual(n.match(token: "bob")?.id, 0)
        XCTAssertEqual(n.match(token: "lavender")?.id, JellyNames.absentID(3))
    }
}
