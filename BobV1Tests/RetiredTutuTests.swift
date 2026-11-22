//
//  RetiredTutuTests.swift
//  2026-11-22 (the owner: "Remove the tutu it looks stupid"): the Ballet tutu is out of the game. Not sold, not in the Dress up list, not worn by anyone generated;
//  a save that owns / wears it loads without it and is refunded at its price exactly once (StoreBook+RetiredTutu.swift).
//

import XCTest
@testable import BobV1

@MainActor
final class RetiredTutuTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    func testTheCatalogueNoLongerListsTheTutu() {
        XCTAssertTrue(WearLook.retired.contains(.tutuPink))
        XCTAssertNil(StoreCatalog.item(wearing: .tutuPink))
        XCTAssertFalse(StoreCatalog.items.contains { $0.wear == .tutuPink || $0.id.contains("tutu") })
        XCTAssertFalse(StoreCatalog.items(.wear).contains { $0.id.contains("tutu") })
        XCTAssertFalse(WearLook.pieces.contains(.tutuPink))
    }

    func testNobodyGeneratedWearsTheTutu() {
        XCTAssertFalse(ParkPool.wearables.contains(.tutuPink))
        // the park's generated visitors (the pool, the extras, the species ones) over several seeds: nobody wears a retired look (the Show rivals and the café guests wear no WearLook at all)
        for seed in [UInt64(1), 7, 42, 2026] {
            for v in ParkPool.generate(seed: seed) + ParkPool.extras(seed: seed) { XCTAssertFalse(WearLook.retired.contains { $0 == v.wear }, "\(v.name) seed \(seed)") }
        }
        for v in ParkPool.all() + ParkPool.speciesVisitors() { XCTAssertNotEqual(v.wear, .tutuPink, v.name) }
        // every piece a generator can reach (the shop catalogue and the pieces list) is free of it
        XCTAssertFalse(StoreCatalog.items.compactMap(\.wear).contains(.tutuPink))
        XCTAssertNil(WearLook.pieces.first { $0.art == "tutu_pink" })
    }

    func testASaveThatOwnsAndWearsTheTutuLosesItAndIsRefundedOnce() throws {
        let suite = "RetiredTutuTests.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        var saved = StoreBook.Saved()
        let tutu = WearLook.tutuPink.rawValue
        saved.wearables = [tutu, WearLook.tutuPink.row.storeID, WearLook.beret.rawValue]
        saved.worn = ["0": ["body": tutu, "head": WearLook.beret.rawValue], "1": ["body": tutu]]
        saved.showHome = ["0": ["body": tutu, "head": WearLook.beret.rawValue], "2": [:]]
        d.set(try JSONEncoder().encode(saved), forKey: StoreBook.key)
        let w = DropsWallet(persists: false)
        let before = w.count
        let b = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b)
        XCTAssertEqual(w.count - before, 2 * WearLook.tutuPink.row.price, "each copy is paid at its price")
        XCTAssertEqual(WearLook.tutuPink.row.price, 60)
        XCTAssertFalse(b.ownsLook(.tutuPink))
        XCTAssertEqual(b.saved.wearables, [WearLook.beret.rawValue])
        XCTAssertNil(b.worn(0, .body)); XCTAssertNil(b.worn(1, .body))
        XCTAssertEqual(b.worn(0, .head), .beret, "other clothes stay")
        XCTAssertFalse((b.saved.showHome ?? [:]).values.contains { $0.values.contains(tutu) }, "no remembered outfit holds it")
        XCTAssertFalse(b.saved.worn.values.contains { $0.values.contains(tutu) })
        // loading again pays nothing more
        let b2 = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b2)
        XCTAssertEqual(w.count - before, 120, "a second load never pays twice")
        let b3 = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b3)
        XCTAssertEqual(w.count - before, 120)
        XCTAssertFalse(StoreBook.dropRetiredTutu(b3.saved).changed)
        XCTAssertEqual(StoreBook.dropRetiredTutu(StoreBook.Saved()).refund, 0)
    }

    func testAShowWardrobeThatRemembersTheTutuComesBackWithoutIt() throws {
        let suite = "RetiredTutuTests.home.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        var saved = StoreBook.Saved()
        saved.showHome = ["0": ["body": WearLook.tutuPink.rawValue, "neck": WearLook.pearls.rawValue]]
        saved.worn = ["0": ["body": WearLook.capeHero.rawValue]]
        d.set(try JSONEncoder().encode(saved), forKey: StoreBook.key)
        let w = DropsWallet(persists: false); let before = w.count
        let b = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b)
        XCTAssertEqual(w.count, before, "never owned: nothing to refund")
        XCTAssertNil(b.saved.showHome, "restored on load")
        XCTAssertNil(b.worn(0, .body), "the remembered tutu is not put back")
        XCTAssertFalse(b.hasEveryday)
    }
}
