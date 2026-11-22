//
//  TrophyCaseTests.swift
//  trophy-case-r1: the "show trophy case" switch is saved, the engraving dates are written at the win, and a save from before them still loads ("Won earlier").
//

import XCTest
@testable import BobV1

@MainActor
final class TrophyCaseTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "TrophyCaseTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testCaseSwitchIsOnByDefaultAndPersists() {
        let d = defaults()
        let a = TrophyBook(persists: true, defaults: d)
        XCTAssertTrue(a.caseVisible)
        a.setCaseVisible(false)
        XCTAssertFalse(TrophyBook(persists: true, defaults: d).caseVisible, "saved")
        a.setCaseVisible(true)
        XCTAssertTrue(TrophyBook(persists: true, defaults: d).caseVisible)
    }

    func testEngravingDateIsWrittenAtTheWinAndSaved() {
        let d = defaults()
        let day = Date(timeIntervalSince1970: 1_795_262_400)          // 21 Nov 2026, noon UTC
        let book = TrophyBook(persists: true, defaults: d)
        _ = book.recordRace(character: 3, tier: .puddle, place: 1, now: day)
        _ = book.recordRace(character: 3, tier: .puddle, place: 1, now: day + 86_400)          // a later win never rewrites the first date
        let back = TrophyBook(persists: true, defaults: d)
        XCTAssertEqual(back.shelf(character: 3).won?["race.puddle.1"], day)
        XCTAssertEqual(back.shelf(character: 3).won?["trophy.first.puddle"], day)
        let item = back.shelfItems(spec: back.roomShelf(contestBest: 0), contestWho: nil).first { $0.id == "cup.puddle" }
        XCTAssertEqual(item?.character, 3)
        XCTAssertEqual(item?.date, day)
        XCTAssertEqual(item?.event, "Jelly Race (Puddle) \u{2013} 1st")
        XCTAssertEqual(TrophyShelfItem.dateText(day), "21 Nov 2026")
    }

    func testOldSaveWithoutDatesLoadsAndReadsWonEarlier() throws {
        let d = defaults()
        d.set(Data(#"{"4":{"race":{"puddle":[1,0,0]},"earned":["first.puddle"]}}"#.utf8), forKey: TrophyBook.key)
        let book = TrophyBook(persists: true, defaults: d)
        XCTAssertEqual(book.shelf(character: 4).raceWins, 1)
        XCTAssertNil(book.shelf(character: 4).won)
        XCTAssertTrue(book.caseVisible, "no switch saved: on")
        let item = try XCTUnwrap(book.shelfItems(spec: book.roomShelf(contestBest: 0), contestWho: nil).first { $0.id == "cup.puddle" })
        XCTAssertNil(item.date)
        XCTAssertEqual(item.character, 4)
        XCTAssertEqual(TrophyShelfItem.dateText(item.date), "Won earlier")
    }

    func testEveryItemHasAShelfSlot() {
        let book = TrophyBook(persists: false)
        for t in CourseTier.allCases { _ = book.recordRace(character: 0, tier: t, place: 1) }
        let spec = book.roomShelf(contestBest: 2)
        let ids = Set(book.shelfItems(spec: spec, contestWho: 0).map(\.id))
        let slots = Set(TrophyShelfGeometry.slots(spec, def: RoomCatalog.def(.home)).map(\.id))
        XCTAssertEqual(ids, slots)
    }

    // MARK: two winners (trophy-pair-r1)

    private func items(_ b: TrophyBook) -> [TrophyShelfItem] { b.shelfItems(spec: b.roomShelf(contestBest: 0), contestWho: nil) }

    func testOwnPartnerWinNamesBothAndShowsForBoth() throws {
        let day = Date(timeIntervalSince1970: 1_795_262_400)
        let book = TrophyBook(persists: false)
        let a = book.recordVolleyWin(character: 1, tier: .sandcastle, name: "Shadow", partner: (2, "Berry"), now: day)
        XCTAssertTrue(a.newRibbon)
        XCTAssertEqual(book.shelf(character: 1).volleyWon(.sandcastle), 1)
        XCTAssertEqual(book.shelf(character: 2).volleyWon(.sandcastle), 1, "the trophy is on both Jelmiko's Profiles")
        XCTAssertTrue(book.shelf(character: 2).has(.volleyFirst(.sandcastle)))
        let item = try XCTUnwrap(items(book).first { $0.id == "volley.sandcastle" })
        XCTAssertEqual(item.pair, VolleyPair(asked: 1, askedName: "Shadow", mate: 2, mateName: "Berry"))
        XCTAssertEqual(item.character, 1, "the asked Jelmiko's face")
        XCTAssertEqual(item.date, day)
    }

    func testParkFriendWinNamesTheFriendAndOnlyOneShelf() throws {
        let book = TrophyBook(persists: false)
        _ = book.recordVolleyWin(character: 1, tier: .sandcastle, name: "Shadow", partner: (nil, "Pebble"))
        XCTAssertEqual(book.shelves.count, 1)
        let item = try XCTUnwrap(items(book).first { $0.id == "volley.sandcastle" })
        XCTAssertEqual(item.pair?.mateName, "Pebble")
        XCTAssertNil(item.pair?.mate)
    }

    func testRaceAndNoPartnerWinsKeepOneWinner() throws {
        let book = TrophyBook(persists: false)
        _ = book.recordRace(character: 3, tier: .puddle, place: 1)
        _ = book.recordVolleyWin(character: 1, tier: .sandcastle)
        XCTAssertNil(items(book).first { $0.id == "cup.puddle" }?.pair)
        XCTAssertNil(items(book).first { $0.id == "volley.sandcastle" }?.pair)
    }

    func testOldVolleyRecordDecodesWithOneWinnerAndStaysSo() throws {
        let d = defaults()
        d.set(Data(#"{"4":{"race":{},"earned":["vfirst.sandcastle"],"volleyWins":{"sandcastle":1},"won":{"volley.sandcastle":780000000}}}"#.utf8), forKey: TrophyBook.key)
        let book = TrophyBook(persists: true, defaults: d)
        XCTAssertNil(book.shelf(character: 4).volleyPairs)
        XCTAssertNil(items(book).first { $0.id == "volley.sandcastle" }?.pair)
        _ = book.recordVolleyWin(character: 4, tier: .sandcastle, name: "Shadow", partner: (5, "Berry"))          // a later pair win does not turn the old trophy into a pair one
        XCTAssertNil(items(book).first { $0.id == "volley.sandcastle" }?.pair)
        XCTAssertNotNil(book.shelf(character: 5).volleyPairs)
    }

    func testPairSurvivesASaveAndReload() throws {
        let d = defaults()
        _ = TrophyBook(persists: true, defaults: d).recordVolleyWin(character: 1, tier: .sandcastle, name: "Shadow", partner: (2, "Berry"))
        let back = TrophyBook(persists: true, defaults: d)
        XCTAssertEqual(back.shelf(character: 2).volleyPairs?["sandcastle"]?.askedName, "Shadow")
    }

    func testLeaveRuleTheTrophyStaysWhileOneWinnerIsStillTheirs() throws {
        let d = defaults()
        let book = TrophyBook(persists: true, defaults: d)
        _ = book.recordVolleyWin(character: 1, tier: .sandcastle, name: "Shadow", partner: (2, "Berry"))
        _ = book.recordVolleyWin(character: 1, tier: .shore, name: "Shadow", partner: (nil, "Pebble"))
        // Shadow (1) leaves: the purge removes his shelf (JellyCamp.purge, `Circuit.trophies.v1` root["1"])
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(d.data(forKey: TrophyBook.key))) as? [String: Any])
        root.removeValue(forKey: "1")
        d.set(try JSONSerialization.data(withJSONObject: root), forKey: TrophyBook.key)
        let back = TrophyBook(persists: true, defaults: d)
        let pair = try XCTUnwrap(items(back).first { $0.id == "volley.sandcastle" }, "Berry still has it").pair
        XCTAssertEqual(pair?.askedName, "Shadow", "the leaver's name is the saved one")
        XCTAssertNil(items(back).first { $0.id == "volley.shore" }, "a Park-friend pair with its Jelmiko gone is gone")
    }

    // MARK: the plaque line

    private func measure(_ s: String) -> CGFloat { CGFloat(s.count) * 10 }

    func testShortPairStaysOnOneLineAtFullSize() {
        let r = PlaqueFit.fit(names: ["Shadow", "Berry"], width: 300, measure: measure)
        XCTAssertEqual(r, PlaqueFit.Result(lines: ["Shadow & Berry"], scale: 1))
    }

    func testLongPairScalesDownToSeventyPercentThenStaysOnOneLine() {
        let r = PlaqueFit.fit(names: ["Marshmallow", "Strawberry Pie"], width: 300, measure: measure)          // 28 chars = 280 -> fits
        XCTAssertEqual(r.scale, 1)
        let tight = PlaqueFit.fit(names: ["Marshmallow Crumb", "Strawberry Pie"], width: 300, measure: measure)          // 34 chars = 340 -> 0.88
        XCTAssertEqual(tight.lines.count, 1); XCTAssertEqual(tight.scale, 300.0 / 340.0, accuracy: 0.001)
    }

    func testVeryLongPairBreaksAtTheAmpersandAndNeverDrops() {
        let r = PlaqueFit.fit(names: ["Marshmallow Crumblecake", "Strawberry Shortcake Pie"], width: 300, measure: measure)          // 50 chars: 0.6 < 0.7
        XCTAssertEqual(r.lines, ["Marshmallow Crumblecake &", "Strawberry Shortcake Pie"])
        XCTAssertEqual(r.scale, 1, "each line fits at full size")
        let huge = PlaqueFit.fit(names: ["A very very very long name indeed", "Another one that is just as long"], width: 200, measure: measure)
        XCTAssertEqual(huge.lines.count, 2)
        XCTAssertLessThan(huge.scale, 1, "scaled further, not cut")
    }
}
