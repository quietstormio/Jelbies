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
}
