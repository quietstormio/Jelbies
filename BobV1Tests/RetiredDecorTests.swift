//
//  RetiredDecorTests.swift
//  The sit-on furniture is retired: not sold, and a save that owns or placed any has it removed (current room and stashed rooms) and refunded exactly once.
//

import XCTest
@testable import BobV1

@MainActor
final class RetiredDecorTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    func testRetiredPiecesAreNotSold() {
        for k in DecorKind.retired { XCTAssertNil(StoreCatalog.item(k.storeID), "\(k) is no longer sold") }
        XCTAssertFalse(StoreCatalog.items(.decor).contains { $0.decor?.isRetired == true })
        XCTAssertEqual(Set(DecorKind.retiredPrices.keys), DecorKind.retired)
        // every home piece with a seat is retired (the park-only seesaw / spring rider / sandbox stay: they live in the Park)
        for k in DecorKind.allCases where k.hopSit && ![.seesaw, .sandbox].contains(k) { XCTAssertTrue(k.isRetired, "\(k) has a seat") }
    }

    func testMigrationRefundsOwnedAndPlacedOnceAndEmptiesEveryRoom() {
        let suite = "RetiredDecorTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let old = #"""
        {"counts":{"decor-loveseat":1,"decor-cushion":2,"decor-plant":1,"sushi":3},"pages":[],"wearables":[],"worn":{},"starterGiven":true,"newItems":0,"placed":[],
         "placedAt":[{"uid":1,"kind":"loveseat","x":1.0,"z":0.5},{"uid":2,"kind":"plant","x":-2.0,"z":1.0}],
         "stash":{"loft":[{"uid":3,"kind":"cushion","x":1.0,"z":0.5}]},"rooms":["loft"],"nextDecorUID":4}
        """#
        d.set(Data(old.utf8), forKey: "k")
        let w = DropsWallet(persists: false)
        let a = StoreBook(wallet: w, persists: true, defaults: d, key: "k")
        Self.keep.append(a)
        XCTAssertEqual(w.count, 120 + 2 * 25, "loveseat 120 + two cushions at 25")
        XCTAssertEqual(a.count("decor-loveseat"), 0); XCTAssertEqual(a.count("decor-cushion"), 0)
        XCTAssertEqual(a.count("decor-plant"), 1); XCTAssertEqual(a.count("sushi"), 3, "other goods are untouched")
        XCTAssertEqual(a.placedDecor.map(\.kind), [.plant])
        XCTAssertNil(a.saved.stash, "the stashed cushion is gone too")
        XCTAssertEqual(a.saved.retiredDecorRefunded, true)
        // loading again never pays twice
        let w2 = DropsWallet(persists: false)
        let b = StoreBook(wallet: w2, persists: true, defaults: d, key: "k")
        Self.keep.append(b)
        XCTAssertEqual(w2.count, 0)
        XCTAssertEqual(b.placedDecor.map(\.kind), [.plant])
    }

    func testAFreshSaveIsUntouched() {
        let (s, refund) = StoreBook.dropRetiredDecor(StoreBook.Saved())
        XCTAssertEqual(refund, 0); XCTAssertEqual(s.retiredDecorRefunded, true)
    }
}
