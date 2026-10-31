//
//  StapleFoodTests.swift
//  Berries and pizza are store foods: bought like the rest, stocked once for every save, and the player is never left unable to feed.
//

import XCTest
@testable import BobV1

@MainActor
final class StapleFoodTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private func book(_ drops: Int = 0, defaults: UserDefaults? = nil, key: String = "StapleFoodTests.book") -> (StoreBook, DropsWallet) {
        let w = DropsWallet(persists: false); w.add(drops, silent: true)
        let b = StoreBook(wallet: w, persists: defaults != nil, defaults: defaults ?? .standard, key: key)
        Self.keep.append(b); return (b, w)
    }

    func testBerriesAndPizzaAreSoldFoodsWithCheapPrices() {
        for id in ["berries", "pizza"] {
            let it = StoreCatalog.item(id)
            XCTAssertEqual(it?.kind, .food); XCTAssertEqual(it?.food, id); XCTAssertEqual(StoreCatalog.item(forFood: id)?.id, id)
            XCTAssertTrue(ShopTab.food.items.contains { $0.id == id })
        }
        XCTAssertLessThan(StoreCatalog.item("berries")!.price, StoreCatalog.item("pizza")!.price)
        XCTAssertLessThanOrEqual(StoreCatalog.item("pizza")!.price, 10)
        XCTAssertTrue(Consumables.berries.stored && Consumables.pizza.stored)
        XCTAssertEqual(ShopTab.food.rawValue, "Food")
    }

    func testBerriesAndPizzaGetTheSamePictureAsEveryOtherFood() {
        for id in ["berries", "pizza"] {
            guard let it = StoreCatalog.item(id) else { return XCTFail(id) }
            XCTAssertFalse(StoreThumb.mesh(for: it)?.vertices.isEmpty ?? true, "\(id) has a 3D thumbnail mesh")
            XCTAssertNotNil(StoreThumb.image(for: it), "\(id) renders through the same thumbnail pipeline")
        }
        for c in [Consumables.water, Consumables.soda] { XCTAssertNotNil(StoreThumb.image(for: c), c.id) }
    }

    func testStarterStockIsGivenOnceAndKeepsMoney() {
        let (b, w) = book(7)
        XCTAssertEqual(b.count("berries"), 0)
        XCTAssertTrue(b.grantStaplesIfNeeded())
        XCTAssertEqual(b.count("berries"), StoreBook.starterBerries); XCTAssertEqual(b.count("pizza"), StoreBook.starterPizza)
        XCTAssertFalse(b.grantStaplesIfNeeded(), "never twice")
        XCTAssertEqual(w.count, 7, "currency is untouched")
    }

    func testAnOlderSaveLoadsUnchangedAndGetsTheStockOnce() throws {
        let d = UserDefaults(suiteName: "StapleFoodTests.old")!; d.removePersistentDomain(forName: "StapleFoodTests.old")
        // a save from before staples existed: no staplesGiven key, other goods present
        let old = #"{"counts":{"sushi":2,"berries":1},"pages":["spin"],"wearables":[],"worn":{},"starterGiven":true,"newItems":0,"placed":[]}"#
        d.set(Data(old.utf8), forKey: "k")
        let (b, _) = book(0, defaults: d, key: "k")
        XCTAssertEqual(b.count("sushi"), 2); XCTAssertTrue(b.saved.pages.contains("spin"))
        b.grantStaplesIfNeeded()
        XCTAssertEqual(b.count("berries"), 1 + StoreBook.starterBerries, "added to what was there")
        XCTAssertEqual(b.count("sushi"), 2)
        let (b2, _) = book(0, defaults: d, key: "k")
        XCTAssertFalse(b2.grantStaplesIfNeeded(), "the flag is saved")
    }

    func testNeverStuckWithNoFoodAndNoDrops() {
        let (b, _) = book(0)
        XCTAssertTrue(b.ensureFeedable()); XCTAssertEqual(b.count("berries"), 1)
        XCTAssertFalse(b.ensureFeedable(), "only while nothing is left")
        let (b2, _) = book(50)
        XCTAssertFalse(b2.ensureFeedable(), "with Drops to spend there is no hand-out")
    }

    func testANewPlayerCanFeedAtOnce() {
        let c = GameCare(jellyCount: 1, persistent: false, defaults: UserDefaults(suiteName: "StapleFoodTests.care")!)
        Self.keep.append(c)
        XCTAssertEqual(c.store.count(food: "berries"), StoreBook.starterBerries)
        XCTAssertEqual(c.store.count(food: "pizza"), StoreBook.starterPizza)
    }

    // MARK: Siri / widget feed with an empty or partial bag

    private func router(_ name: String) -> (GameRouter, GameCare) {
        let d = UserDefaults(suiteName: "StapleFoodTests.\(name)")!; d.removePersistentDomain(forName: "StapleFoodTests.\(name)")
        let care = GameCare(jellyCount: 1, persistent: false, defaults: d)
        let r = GameRouter(directory: nil)
        Self.keep.append(care); Self.keep.append(r)
        return (r, care)
    }
    /// Empties the bag of every food (the starter stock included).
    private func emptyBag(_ care: GameCare) {
        for it in StoreCatalog.items where it.food != nil && it.kind != .drink { while care.store.count(it.id) > 0 { care.store.use(it.id) } }
    }

    func testSiriFeedFallsBackToAnyOwnedFood() {
        let (r, care) = router("fallback")
        emptyBag(care)
        care.store.grant("fries", 2)
        var said = 0; r.onNoFood = { said += 1 }
        r.request(.feed(0)); r.apply(care: care)
        XCTAssertEqual(said, 0, "there was food to serve")
        XCTAssertTrue(care.foodOut, "the berries were gone, so the fries came out")
        XCTAssertEqual(care.selectedFoodID, "fries")
    }

    func testSiriFeedWithNoFoodSaysSoInsteadOfDoingNothing() {
        let (r, care) = router("none")
        emptyBag(care)
        var said = 0; r.onNoFood = { said += 1 }
        r.request(.feed(0)); r.apply(care: care)
        XCTAssertEqual(said, 1); XCTAssertEqual(r.noFoodCount, 1)
        XCTAssertFalse(care.trayOut, "no tray with nothing to serve")
        XCTAssertTrue(r.pending.isEmpty, "handled, not left waiting forever")
        XCTAssertFalse(GameRouter.noFoodLine.isEmpty)
    }
}
