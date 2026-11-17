//
//  SellBackTests.swift
//  2026-11-17 (the owner: "a way to sell items back"): half the Shop price, only what is free to sell.
//

import XCTest
@testable import BobV1

@MainActor
final class SellBackTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private func book(coins: Int = 0) -> (StoreBook, DropsWallet) {
        let w = DropsWallet(persists: false); w.add(coins, silent: true)
        let b = StoreBook(wallet: w, persists: false); Self.keep.append(b); Self.keep.append(w)
        return (b, w)
    }

    func testFoodSellsOneForHalf() {
        let (b, w) = book()
        b.grant("sushi", 3)
        XCTAssertEqual(b.sellState(StoreCatalog.item("sushi")!), .sellable(9))
        XCTAssertEqual(b.sell("sushi"), 9)
        XCTAssertEqual(b.count("sushi"), 2); XCTAssertEqual(w.count, 9)
        b.sell("sushi"); b.sell("sushi")
        XCTAssertEqual(b.count("sushi"), 0); XCTAssertEqual(w.count, 27)
        XCTAssertNil(b.sell("sushi"), "none left"); XCTAssertEqual(w.count, 27)
    }

    func testDrinksAndSuppliesSell() {
        let (b, w) = book()
        b.grant("lavender", 1)
        XCTAssertEqual(b.sell("lavender"), 10); XCTAssertEqual(w.count, 10)
        if let d = StoreCatalog.items.first(where: { $0.kind == .drink }) { b.grant(d.id); XCTAssertEqual(b.sell(d.id), max(d.price / 2, 1)) }
    }

    func testFreeWearCopySellsWornOnlyDoesNot() {
        let (b, w) = book()
        let item = StoreCatalog.item(wearing: .sneakerMint)!
        b.grant(item.id, 2)
        b.wear(.sneakerMint, on: 0)
        XCTAssertEqual(b.sell(item.id), item.price / 2)
        XCTAssertEqual(b.copies(.sneakerMint), 1); XCTAssertEqual(b.worn(0, .feet), .sneakerMint, "the worn copy stays on")
        let coins = w.count
        XCTAssertEqual(b.sellState(item), .worn)
        XCTAssertNil(b.sell(item.id)); XCTAssertEqual(w.count, coins); XCTAssertEqual(b.copies(.sneakerMint), 1)
        b.takeOff(.feet, from: 0)
        XCTAssertNotNil(b.sell(item.id)); XCTAssertEqual(b.copies(.sneakerMint), 0)
    }

    func testStashedDecorSellsPlacedDoesNot() {
        let (b, w) = book()
        b.grant("decor-plant", 2)
        XCTAssertNotNil(b.place("decor-plant"))
        XCTAssertEqual(b.sell("decor-plant"), 17)          // the unplaced one
        XCTAssertEqual(b.count("decor-plant"), 1); XCTAssertEqual(w.count, 17)
        XCTAssertEqual(b.sellState(StoreCatalog.item("decor-plant")!), .inRoom)
        XCTAssertNil(b.sell("decor-plant")); XCTAssertEqual(b.count("decor-plant"), 1); XCTAssertEqual(w.count, 17)
    }

    func testTricksRoomsAndMedalCannotBeSold() {
        let (b, w) = book(coins: 5000)
        for item in StoreCatalog.items where item.kind == .trickPage || item.kind == .room || item.kind == .toy { b.grant(item.id); XCTAssertEqual(b.sellState(item), .no, item.id); XCTAssertNil(b.sell(item.id)) }
        XCTAssertEqual(w.count, 5000)
        XCTAssertNil(b.sell("nonsense"))
    }

    func testNeverMoreThanHalfAndNoLoopProfit() {
        for item in StoreCatalog.items where item.price >= 2 { XCTAssertLessThanOrEqual(StoreBook.sellPrice(item) * 2, item.price, item.id); XCTAssertGreaterThanOrEqual(StoreBook.sellPrice(item), 1) }
        let (b, w) = book(coins: 100)
        let before = w.count
        for _ in 0..<5 { XCTAssertEqual(b.buy("pizza"), .bought); XCTAssertNotNil(b.sell("pizza")) }
        XCTAssertLessThan(w.count, before, "buy then sell loses coins")
    }

    func testSellingTouchesOnlyThatCount() {
        let (b, _) = book()
        b.grant("pizza", 2); b.grant("sushi", 1); b.grant(StoreCatalog.item(wearing: .beret)!.id, 1)
        let before = b.saved.counts; let wear = b.saved.wearables
        b.sell("pizza")
        var want = before; want["pizza"] = 1
        XCTAssertEqual(b.saved.counts, want); XCTAssertEqual(b.saved.wearables, wear)
    }
}
