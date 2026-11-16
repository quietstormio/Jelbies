//
//  FavouriteFoodTests.swift
//  The favourite food rule (Store/FavouriteFood.swift): a Jelmiko who eats the food it loves gets that food's power-up for twice as long. Any other food
//  gives the usual time, a favourite food without a power-up gives none (only the heart it always gave), and no serving cuts a longer time short.
//  Fast: in-memory homes (characters 1, 2, 3 with persistent: false, so no slot's power-ups, stats or needs reach the save), own UserDefaults suites for
//  the favourite records, and the process-wide book is put back. The last test runs one real shared meal at the tray (DiningJellyTests.Room).
//

import XCTest
@testable import BobV1

@MainActor
final class FavouriteFoodTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []         // the runtime aborts when a GameCare is released (see MelonModel)

    private var suites: [String] = []

    override func tearDown() {
        JellyTraitsBook.reload()
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
    }
    private func suite() -> UserDefaults {
        let n = "FavouriteFoodTests.\(UUID().uuidString)"
        suites.append(n)
        return UserDefaults(suiteName: n)!
    }
    /// Where this test writes its favourite records (never the real save).
    private lazy var book: UserDefaults = suite()

    // MARK: helpers

    /// An in-memory home of three with no favourite on record. Characters 1, 2, 3: with no Bob in slot 0, every slot keeps its power-ups out of the save.
    private func home() throws -> GameCare {
        let care = GameCare(roster: [1, 2, 3], persistent: false, defaults: suite())
        Self.keep.append(care)
        XCTAssertEqual(care.jellyCount, 3)
        for slot in 0..<3 { try love(care, slot, nil) }
        return care
    }
    /// The Jelmiko in `slot` now loves `snack` (nil = no record at all: a Jelmiko with no favourite).
    private func love(_ care: GameCare, _ slot: Int, _ snack: String?) throws {
        let prof = try XCTUnwrap(care.jelly(slot))
        let record = snack.map { JellyTraits(personality: .brave, jars: [50, 50, 50, 50, 50], snack: $0) }
        JellyTraitsBook.adopt(prof.character, record, book)
    }
    /// `slot` eats one whole serving of `c`, bite by bite, the way a meal pays it (GameCare.payPieces, the group's `pay`). `newServing: false` = another
    /// diner at the SAME serving: a shared meal uses up one serving from the bag for the whole table.
    private func eat(_ care: GameCare, _ slot: Int, _ c: Consumable, newServing: Bool = true) throws {
        if newServing {
            let item = try XCTUnwrap(c.storeID)
            care.store.grant(item, 1)
            care.servingCharged = false
        }
        for _ in 0..<DiningTiming.bitesPerServing { care.ate(jelly: slot, c, pieces: 1) }
    }
    /// Seconds of `perk` the Jelmiko in `slot` has left (-1: there is no such Jelmiko).
    private func left(_ care: GameCare, _ slot: Int, _ perk: PerkKind) -> TimeInterval { care.jelly(slot)?.perks.remaining(perk) ?? -1 }
    /// The power-ups the Jelmiko in `slot` has now.
    private func active(_ care: GameCare, _ slot: Int) -> [PerkKind] { care.jelly(slot)?.perks.active ?? [] }
    /// Hearts in the air over the Jelmiko in `slot`.
    private func hearts(_ care: GameCare, _ slot: Int) -> Int { care.bubbleHub.hearts.filter { $0.id == slot }.count }

    // MARK: the numbers

    func testAFavouriteServingLastsTwiceAsLongAndNoServingCutsALongerTimeShort() {
        XCTAssertEqual(FavouriteFood.perkTimeMul, 2)
        for p in PerkKind.allCases {
            let d = p.duration
            XCTAssertGreaterThan(d, 0, "\(p)")
            XCTAssertEqual(FavouriteFood.perkDuration(p, favourite: false), d, "\(p): a plain serving")
            XCTAssertEqual(FavouriteFood.perkDuration(p, favourite: true), 2 * d, "\(p): a favourite serving")
            XCTAssertEqual(FavouriteFood.grantSeconds(p, favourite: false, left: 0), d, "\(p): plain, nothing running")
            XCTAssertEqual(FavouriteFood.grantSeconds(p, favourite: true, left: 0), 2 * d, "\(p): favourite, nothing running")
            XCTAssertEqual(FavouriteFood.grantSeconds(p, favourite: false, left: 0.5 * d), d, "\(p): a plain serving tops a shorter time up")
            XCTAssertEqual(FavouriteFood.grantSeconds(p, favourite: true, left: 1.5 * d), 2 * d, "\(p): a favourite serving tops a shorter time up")
            XCTAssertEqual(FavouriteFood.grantSeconds(p, favourite: false, left: 1.75 * d), 1.75 * d, "\(p): a plain serving keeps a longer time")
            XCTAssertEqual(FavouriteFood.grantSeconds(p, favourite: true, left: 3 * d), 3 * d, "\(p): so does a favourite one")
        }
    }

    // MARK: eating at home

    func testEatingTheFavouriteFoodDoublesItsPowerUp() throws {
        for (food, perk) in [(Consumables.taco, PerkKind.zoomies), (Consumables.sushi, PerkKind.cozy)] {
            XCTAssertEqual(food.perk, perk, "\(food.id) gives \(perk)")
            let care = try home()
            let item = try XCTUnwrap(food.storeID)
            let bag = care.store.count(item)
            try love(care, 1, food.id)
            try eat(care, 1, food)
            XCTAssertEqual(left(care, 1, perk), 2 * perk.duration, accuracy: 5, "\(food.id): the favourite's power-up lasts twice as long")
            XCTAssertEqual(active(care, 1), [perk], "\(food.id): the food's own power-up and no other")
            XCTAssertEqual(care.store.count(item), bag, "\(food.id): the one serving was used up")
            XCTAssertEqual(hearts(care, 1), 1, "\(food.id): the favourite's heart on the first bite, as before")
            XCTAssertTrue(active(care, 2).isEmpty, "a Jelmiko who did not eat gets nothing")
        }
    }

    func testAnyOtherFoodGivesTheUsualTime() throws {
        let care = try home()
        try love(care, 1, "taco")
        try eat(care, 1, Consumables.sushi)
        XCTAssertEqual(left(care, 1, .cozy), PerkKind.cozy.duration, accuracy: 5, "not the favourite: the usual time")
        XCTAssertEqual(active(care, 1), [PerkKind.cozy])
        XCTAssertEqual(hearts(care, 1), 0, "and no heart")
    }

    func testAJelmikoWithNoFavouriteOnRecordGetsTheUsualTime() throws {
        let care = try home()
        let prof = try XCTUnwrap(care.jelly(1))
        XCTAssertNil(prof.traits, "no record: nothing is loved")
        try eat(care, 1, Consumables.sushi)
        XCTAssertEqual(left(care, 1, .cozy), PerkKind.cozy.duration, accuracy: 5)
        XCTAssertEqual(hearts(care, 1), 0)
    }

    func testAPlainServingAfterTheFavouriteKeepsTheLongerTime() throws {
        XCTAssertEqual(Consumables.taco.perk, PerkKind.zoomies)
        XCTAssertEqual(Consumables.donut.perk, PerkKind.zoomies, "two foods with the same power-up")
        let care = try home()
        try love(care, 1, "taco")
        try eat(care, 1, Consumables.taco)
        try eat(care, 1, Consumables.donut)
        XCTAssertEqual(left(care, 1, .zoomies), 2 * PerkKind.zoomies.duration, accuracy: 5, "another food with the same power-up does not cut the favourite's time short")
    }

    func testAServingTopsAShorterTimeUpAndKeepsALongerOne() throws {
        let care = try home()
        let prof = try XCTUnwrap(care.jelly(1))
        let d = PerkKind.cozy.duration
        prof.perks.grant(.cozy, duration: 60)
        try eat(care, 1, Consumables.sushi)
        XCTAssertEqual(prof.perks.remaining(.cozy), d, accuracy: 5, "a plain serving tops a minute up to the usual time")
        try love(care, 1, "sushi")
        try eat(care, 1, Consumables.sushi)
        XCTAssertEqual(prof.perks.remaining(.cozy), 2 * d, accuracy: 5, "the favourite tops it up to twice that")
        try love(care, 1, "taco")
        try eat(care, 1, Consumables.sushi)
        XCTAssertEqual(prof.perks.remaining(.cozy), 2 * d, accuracy: 5, "no longer the favourite: the longer time stays")
        prof.perks.grant(.cozy, duration: 3 * d)
        try love(care, 1, "sushi")
        try eat(care, 1, Consumables.sushi)
        XCTAssertEqual(prof.perks.remaining(.cozy), 3 * d, accuracy: 5, "a longer time from elsewhere is never cut, by the favourite either")
    }

    func testAtASharedMealEachDinerIsJudgedOnItsOwnFavourite() throws {
        let d = PerkKind.zoomies.duration
        // the one who loves it bites first
        let first = try home()
        let bag = first.store.count("taco")
        try love(first, 0, "taco")
        try love(first, 1, "sushi")          // (slot 2 has no favourite on record)
        try eat(first, 0, Consumables.taco)
        try eat(first, 1, Consumables.taco, newServing: false)
        try eat(first, 2, Consumables.taco, newServing: false)
        XCTAssertEqual(first.store.count("taco"), bag, "one serving for the whole table")
        XCTAssertEqual(left(first, 0, .zoomies), 2 * d, accuracy: 5, "loves Taco: twice as long")
        XCTAssertEqual(left(first, 1, .zoomies), d, accuracy: 5, "loves something else: the usual time")
        XCTAssertEqual(left(first, 2, .zoomies), d, accuracy: 5, "no favourite: the usual time")
        XCTAssertEqual(first.bubbleHub.hearts.map { $0.id }, [0], "the heart of the serving's first bite, as before")
        // the one who loves it bites last: the double time does not depend on the order
        let last = try home()
        try love(last, 2, "taco")
        try eat(last, 0, Consumables.taco)
        try eat(last, 1, Consumables.taco, newServing: false)
        try eat(last, 2, Consumables.taco, newServing: false)
        XCTAssertEqual(left(last, 0, .zoomies), d, accuracy: 5)
        XCTAssertEqual(left(last, 1, .zoomies), d, accuracy: 5)
        XCTAssertEqual(left(last, 2, .zoomies), 2 * d, accuracy: 5, "the last one to bite still gets the double time")
    }

    func testAFavouriteFoodWithoutAPowerUpGivesNoPowerUp() throws {
        let c = Consumables.berries
        XCTAssertNil(c.perk, "Berries have no power-up")
        XCTAssertTrue(c.stored)
        let care = try home()
        let item = try XCTUnwrap(c.storeID)
        let bag = care.store.count(item)
        try love(care, 1, c.id)
        try eat(care, 1, c)
        XCTAssertTrue(active(care, 1).isEmpty, "a favourite food without a power-up gives none")
        for p in PerkKind.allCases { XCTAssertEqual(left(care, 1, p), 0, "\(p)") }
        XCTAssertEqual(hearts(care, 1), 1, "only the heart it always gave")
        XCTAssertEqual(care.store.count(item), bag, "the serving was used up")
    }

    /// Every food an adopted Jelmiko can love (its personality's snacks or its species' own) is a store food with a power-up, and the Shop's chip names that same power-up.
    func testEveryFavouriteAPlayerCanMeetHasAPowerUpToDouble() {
        var ids = Set<String>()
        for p in JellyPersonality.allCases { ids.formUnion(p.snacks) }
        for s in 0..<JellyRoster.knownCount { if let loved = JellyCandidates.lovedSnack(s) { ids.insert(loved) } }
        XCTAssertGreaterThanOrEqual(ids.count, 4, "\(ids.sorted())")
        for id in ids.sorted() {
            guard let c = Consumables.with(id: id) else { XCTFail("\(id) is not a food"); continue }
            XCTAssertTrue(c.stored, "\(id) is fed from the bag")
            XCTAssertNotNil(c.perk, "\(id) gives a power-up")
            XCTAssertEqual(StoreCatalog.item(forFood: id)?.perk, c.perk, "\(id): the Shop's chip names the power-up the food gives")
        }
    }

    // MARK: what the player reads

    func testTheShopLineAndTheHelpPageSayWhatTheGameDoes() {
        XCTAssertEqual(FavouriteFood.perkTimeMul, 2, "every text below says 'twice as long'")
        XCTAssertTrue(FavouriteFood.shopLine.contains("power-up"), FavouriteFood.shopLine)
        XCTAssertTrue(FavouriteFood.shopLine.contains("twice as long"), FavouriteFood.shopLine)
        var help: [String] = []
        for s in SupportText.sections { help.append(contentsOf: s.paragraphs) }
        XCTAssertEqual(help.filter { $0.hasPrefix("Power-ups: ") }.count, 1, "one Help line on power-ups")
        let favourite = help.filter { $0.hasPrefix("Favourite food: ") }
        XCTAssertEqual(favourite.count, 1, "one Help line on the favourite food")
        XCTAssertTrue(favourite.first?.contains("twice as long") ?? false, "\(favourite)")
    }

    // MARK: a real meal

    /// One real shared meal at the tray (the dining tests' room): three famished Jelmiko eat one Sushi roll serving. Only the one who loves it gets the double time.
    func testARealSharedMealDoublesThePowerUpOnlyForTheOneWhoLovesIt() throws {
        XCTAssertEqual(Consumables.sushi.perk, PerkKind.cozy)
        let r = DiningJellyTests.Room(count: 3)
        Self.keep.append(r.care); Self.keep.append(contentsOf: r.actors)
        let c = r.care
        XCTAssertEqual(c.jellyCount, 3)
        // (this room's slot 0 keeps its power-ups in the save: start clean and leave nothing behind)
        defer { for i in 0..<3 { c.jelly(i)?.perks.clear(.cozy) } }
        for i in 0..<3 {
            c.jelly(i)?.perks.clear(.cozy)
            try love(c, i, i == 1 ? "sushi" : nil)
        }
        r.run(1)
        c.feedSnack("sushi")
        XCTAssertTrue(c.groupActive, "one serving for the three of them")
        r.run(120) { r.t > 2 && !c.trayOut }
        XCTAssertFalse(c.trayOut, "the meal ended")
        let d = PerkKind.cozy.duration
        for i in 0..<3 {
            let t = left(c, i, .cozy)
            if i == 1 {
                XCTAssertGreaterThan(t, 1.9 * d, "slot 1 loves Sushi roll: twice as long")
                XCTAssertLessThanOrEqual(t, 2 * d)
            } else {
                XCTAssertGreaterThan(t, 0.9 * d, "slot \(i) ate too: the usual time")
                XCTAssertLessThanOrEqual(t, d, "slot \(i) does not love it: not a second more")
            }
        }
    }
}
