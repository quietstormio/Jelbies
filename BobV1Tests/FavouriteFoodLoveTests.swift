//
//  FavouriteFoodLoveTests.swift
//  A Jelmiko who eats his favourite food gets a heart (the bubble over his head, then a short burst) and a step of love (the attention need,
//  FavouriteFood.loveGain), once per serving, on HIS OWN first bite. At a shared meal that is every diner who loves it, not only the serving's first biter.
//  In-memory homes (characters 1, 2, 3, persistent: false); DayClock pinned to noon.
//

import XCTest
@testable import BobV1

@MainActor
final class FavouriteFoodLoveTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var suites: [String] = []
    private var savedHour: Double?

    override func setUp() { super.setUp(); savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 12.0 }
    override func tearDown() {
        DayClock.shared.forcedHour = savedHour
        JellyTraitsBook.reload()
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
        super.tearDown()
    }
    private func suite() -> UserDefaults {
        let n = "FavouriteFoodLoveTests.\(UUID().uuidString)"
        suites.append(n)
        return UserDefaults(suiteName: n)!
    }
    private lazy var book: UserDefaults = suite()

    private func home(love start: Float = 0.3) throws -> GameCare {
        let care = GameCare(roster: [1, 2, 3], persistent: false, defaults: suite())
        Self.keep.append(care)
        for slot in 0..<3 {
            try loves(care, slot, nil)
            care.needs(for: slot).set(.attention, start)
        }
        return care
    }
    private func loves(_ care: GameCare, _ slot: Int, _ snack: String?) throws {
        let prof = try XCTUnwrap(care.jelly(slot))
        JellyTraitsBook.adopt(prof.character, snack.map { JellyTraits(personality: .brave, jars: [50, 50, 50, 50, 50], snack: $0) }, book)
    }
    private func eat(_ care: GameCare, _ slot: Int, _ c: Consumable, newServing: Bool = true) throws {
        if newServing { care.store.grant(try XCTUnwrap(c.storeID), 1); care.servingCharged = false }
        for _ in 0..<DiningTiming.bitesPerServing { care.ate(jelly: slot, c, pieces: 1) }
    }
    private func love(_ care: GameCare, _ slot: Int) -> Float { care.needs(for: slot).level(.attention) }
    private func hearts(_ care: GameCare, _ slot: Int) -> Int { care.bubbleHub.hearts.filter { $0.id == slot }.count }

    func testAtAGroupMealEveryDinerWhoLovesItIsCheeredOnceNotOnlyTheFirstBiter() throws {
        let care = try home()
        try loves(care, 1, "taco"); try loves(care, 2, "taco")        // diner 0 loves something else
        try loves(care, 0, "sushi")
        try eat(care, 0, Consumables.taco)
        try eat(care, 1, Consumables.taco, newServing: false)
        try eat(care, 2, Consumables.taco, newServing: false)
        XCTAssertEqual(love(care, 0), 0.3, accuracy: 0.001, "diner 0: not his favourite, no love")
        XCTAssertEqual(love(care, 1), 0.3 + FavouriteFood.loveGain, accuracy: 0.001, "diner 1: love once, not once per bite")
        XCTAssertEqual(love(care, 2), 0.3 + FavouriteFood.loveGain, accuracy: 0.001, "diner 2: the same")
        XCTAssertEqual(hearts(care, 0), 0)
        XCTAssertEqual(hearts(care, 1), 1, "one heart at once (the burst follows)")
        XCTAssertEqual(hearts(care, 2), 1)
        XCTAssertEqual(care.favouriteHearts[1]?.left, FavouriteFood.extraHearts, "the burst is queued")
        care.tickFavouriteHearts(dt: 1)
        XCTAssertEqual(hearts(care, 1), 2, "then more hearts float up")
        for _ in 0..<5 { care.tickFavouriteHearts(dt: 1) }
        XCTAssertEqual(hearts(care, 1), 1 + FavouriteFood.extraHearts)
        XCTAssertTrue(care.favouriteHearts.isEmpty)
        XCTAssertEqual(love(care, 1), 0.3 + FavouriteFood.loveGain, accuracy: 0.001, "the burst gives no more love")
    }

    func testASingleMealOfTheFavouriteGivesHeartAndLoveAndAnyOtherFoodGivesNone() throws {
        let care = try home()
        try loves(care, 1, "taco")
        try eat(care, 1, Consumables.sushi)
        XCTAssertEqual(love(care, 1), 0.3, accuracy: 0.001)
        XCTAssertEqual(hearts(care, 1), 0)
        try eat(care, 1, Consumables.taco)
        XCTAssertEqual(love(care, 1), 0.3 + FavouriteFood.loveGain, accuracy: 0.001)
        XCTAssertEqual(hearts(care, 1), 1)
        try eat(care, 1, Consumables.taco)          // the next serving cheers him again
        XCTAssertEqual(love(care, 1), 0.3 + 2 * FavouriteFood.loveGain, accuracy: 0.001)
        let none = try home()
        try eat(none, 1, Consumables.taco)
        XCTAssertEqual(love(none, 1), 0.3, accuracy: 0.001, "no favourite on record: nothing")
    }

    func testLoveIsCappedAtOne() throws {
        let care = try home(love: 0.95)
        try loves(care, 1, "taco")
        try eat(care, 1, Consumables.taco)
        XCTAssertEqual(love(care, 1), 1, accuracy: 0.0001)
    }
}
