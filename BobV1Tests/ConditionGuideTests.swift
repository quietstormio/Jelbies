//
//  ConditionGuideTests.swift
//  The Condition screen's words and lists (Show/ConditionGuide.swift): the foods that fill a jar (owned first, never empty for any of the five styles,
//  nothing Feed cannot serve), the Glow wording, the "Today" tags and the meals that filled a jar. Display only.
//

import XCTest
@testable import BobV1

@MainActor
final class ConditionGuideTests: XCTestCase {
    func testEveryStyleHasFoodsToListWithAnEmptyBag() {
        for k in ConditionKey.allCases {
            let l = ConditionGuide.fillers(raising: k, count: { _ in 0 })
            XCTAssertFalse(l.isEmpty, "\(k.title) lists foods")
            XCTAssertLessThanOrEqual(l.count, 3, "an empty bag lists at most three Shop foods")
            for f in l {
                XCTAssertFalse(f.owned); XCTAssertNotEqual(f.item.kind, .drink)
                XCTAssertGreaterThan(Consumables.with(id: f.item.food ?? "")?.condition[k] ?? 0, 0, "\(f.item.name) raises \(k.title)")
            }
        }
    }

    func testOwnedFoodsComeFirstThenAtMostThreeShopFoods() {
        for k in ConditionKey.allCases {
            let all = ConditionGuide.allFoods(raising: k)
            guard let own = all.last else { return XCTFail("\(k.title) has no food") }
            let l = ConditionGuide.fillers(raising: k, count: { $0 == own.item.id ? 2 : 0 })
            XCTAssertEqual(l.first?.item.id, own.item.id, "\(k.title): the owned food is first even when it gives the least")
            XCTAssertEqual(l.first?.count, 2)
            XCTAssertTrue(l.dropFirst().allSatisfy { !$0.owned })
            XCTAssertEqual(l.count, 1 + min(3, all.count - 1))
        }
        let everything = ConditionGuide.fillers(raising: .sweet, count: { _ in 1 })
        XCTAssertEqual(everything.count, ConditionGuide.allFoods(raising: .sweet).count, "every owned food is listed")
        XCTAssertTrue(everything.allSatisfy(\.owned))
    }

    func testGlowWordsMapZeroToFive() {
        XCTAssertEqual((0...5).map { ConditionGuide.glowWord(of5: $0) }, ["none", "a little", "a little", "a little", "full", "full"])
        XCTAssertEqual(ConditionGuide.glowWord(0), "none")
        XCTAssertEqual(ConditionGuide.glowWord(1), "full")
        XCTAssertEqual(ConditionGuide.glowWord(0.5), "a little")
    }

    func testTodayTagsMarkTheMainAndFriendStyleOnly() {
        for ord in 0..<5 {
            let th = ShowSchedule.theme(ordinal: ord)
            let tags = WearTag.jarOrder.map { ConditionGuide.todayTag($0, theme: th) }
            XCTAssertEqual(tags.compactMap { $0 }.sorted(), ["Helps today", "Today"])
            XCTAssertEqual(ConditionGuide.todayTag(th.main, theme: th), "Today"); XCTAssertEqual(ConditionGuide.todayTag(th.friend, theme: th), "Helps today")
        }
        XCTAssertNil(ConditionGuide.todayTag(.cute, theme: nil))
    }

    func testMealsThatFilledAJar() {
        let ms = [MealEntry(food: "Sushi", at: 3, gains: [ConditionKey.cute.rawValue: 0.1, ConditionKey.sparkle.rawValue: 0.1]),
                  MealEntry(food: "Donut", at: 2, gains: [ConditionKey.sweet.rawValue: 0.14]),
                  MealEntry(food: "Taco", at: 1, gains: [:])]
        XCTAssertEqual(ConditionGuide.meals(filling: .sweet, in: ms).map(\.food), ["Donut"])
        XCTAssertEqual(ConditionGuide.meals(filling: .cute, in: ms).map(\.food), ["Sushi"])
        XCTAssertTrue(ConditionGuide.meals(filling: .sporty, in: ms).isEmpty)
        XCTAssertEqual(ConditionGuide.styleLine(.sweet), "Sweet: filled by sweet foods")
        XCTAssertEqual(ConditionGuide.rivalsLine(.lagoon), "Rivals in Lagoon are about here.")
    }
}
