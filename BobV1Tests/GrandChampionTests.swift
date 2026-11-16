//
//  GrandChampionTests.swift
//  "Won every course" (the Grand Champion badge) and "this win completes the set" (the confetti finish).
//

import XCTest
@testable import BobV1

@MainActor
final class GrandChampionTests: XCTestCase {
    func testWonEveryCourseNeedsAFirstPlaceOnEveryTier() {
        let book = TrophyBook(persists: false)
        let tiers = CourseTier.allCases
        for (i, t) in tiers.enumerated() {
            XCTAssertFalse(book.shelf(character: 0).wonEveryCourse, "before the \(i + 1)th course")
            _ = book.recordRace(character: 0, tier: t, place: i == tiers.count - 1 ? 2 : 1)          // the last one only second: not won
        }
        XCTAssertFalse(book.shelf(character: 0).wonEveryCourse, "second place on the last course is not a win")
        _ = book.recordRace(character: 0, tier: tiers.last!, place: 1)
        XCTAssertTrue(book.shelf(character: 0).wonEveryCourse)
        XCTAssertFalse(book.shelf(character: 1).wonEveryCourse, "per Jelmiko")
    }

    func testOnlyTheWinThatCompletesTheSetGetsTheConfetti() {
        let book = TrophyBook(persists: false)
        let tiers = CourseTier.allCases
        var completing: [Bool] = []
        for t in tiers { completing.append(book.recordRace(character: 0, tier: t, place: 1).completesSet) }
        XCTAssertEqual(completing, tiers.indices.map { $0 == tiers.count - 1 }, "only the last unwon course")
        XCTAssertFalse(book.recordRace(character: 0, tier: tiers[0], place: 1).completesSet, "winning again afterwards is not the completing win")
        XCTAssertFalse(book.recordRace(character: 0, tier: tiers[0], place: 3).completesSet)
    }

    func testAMissedWinInTheMiddleDelaysTheCompletion() {
        let book = TrophyBook(persists: false)
        let tiers = CourseTier.allCases
        for t in tiers.dropFirst() { XCTAssertFalse(book.recordRace(character: 2, tier: t, place: 1).completesSet) }
        XCTAssertTrue(book.recordRace(character: 2, tier: tiers[0], place: 1).completesSet, "the one that was left")
    }
}
