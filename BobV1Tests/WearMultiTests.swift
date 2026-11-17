//
//  WearMultiTests.swift
//  2026-11-16 (the owner: "a way to buy multiple pieces of clothing ... matching shoes and clothes"): a wearable can be bought again; each copy is worn by one
//  Jelmiko at a time. With no free copy, Wear moves the copy worn longest. The Puffer vest and Cable cardigan are retired (refunded per copy, once).
//

import XCTest
@testable import BobV1

@MainActor
final class WearMultiTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func book(coins: Int = 500) -> (StoreBook, DropsWallet) {
        let w = DropsWallet(persists: false); w.add(coins, silent: true)
        let b = StoreBook(wallet: w, persists: false); Self.keep.append(b)
        return (b, w)
    }

    func testTwoCopiesTwoWearers() {
        let (b, w) = book()
        let item = StoreCatalog.item(wearing: .sneakerMint)!
        XCTAssertEqual(b.buy(item.id), .bought)
        XCTAssertEqual(b.owned(item), 1)
        let after1 = w.count
        XCTAssertEqual(b.buy(item.id), .bought, "Buy another")
        XCTAssertEqual(after1 - w.count, item.price, "the same price")
        XCTAssertEqual(b.owned(item), 2); XCTAssertEqual(b.copies(.sneakerMint), 2)
        XCTAssertTrue(b.wear(.sneakerMint, on: 0)); XCTAssertTrue(b.wear(.sneakerMint, on: 1))
        XCTAssertEqual(b.worn(0, .feet), .sneakerMint); XCTAssertEqual(b.worn(1, .feet), .sneakerMint)
        XCTAssertEqual(b.wearers(.sneakerMint, among: 3), [0, 1]); XCTAssertEqual(b.freeCopies(.sneakerMint), 0)
        XCTAssertNil(b.wearVictim(.sneakerMint, for: 0), "already wearing it")
    }

    func testThirdWearerMovesTheLongestWornCopy() {
        let (b, _) = book()
        b.grant("wear-" + WearLook.beret.art, 2)
        b.wear(.beret, on: 1); b.wear(.beret, on: 0)          // Pip (1) has worn it longest
        XCTAssertEqual(b.copies(.beret), 2)
        XCTAssertEqual(b.wearVictim(.beret, for: 2), 1)
        XCTAssertTrue(b.wear(.beret, on: 2))
        XCTAssertNil(b.worn(1, .head)); XCTAssertEqual(b.worn(0, .head), .beret); XCTAssertEqual(b.worn(2, .head), .beret)
        XCTAssertEqual(b.wearers(.beret, among: 3), [0, 2])
        // a third copy makes it free
        b.grant("wear-" + WearLook.beret.art, 3)
        XCTAssertEqual(b.freeCopies(.beret), 1); XCTAssertNil(b.wearVictim(.beret, for: 1))
        b.wear(.beret, on: 1)
        XCTAssertEqual(b.wearers(.beret, among: 3).count, 3)
        b.takeOff(.head, from: 0); XCTAssertEqual(b.freeCopies(.beret), 1)
    }

    /// A copy held by someone away at the Camp (a character outside the room) is still taken: no free copy, and he is the one named / moved.
    func testWearerOutsideTheRoomHoldsACopy() {
        let (b, _) = book()
        b.grant("wear-" + WearLook.beret.art, 1)
        b.characterOf = { $0 == 0 ? 0 : 9 }
        b.wear(.beret, on: 1)          // character 9, not in the room of three characters 0...2
        XCTAssertEqual(b.freeCopies(.beret), 0)
        XCTAssertEqual(b.wearerCharacters(.beret), [9])
        XCTAssertEqual(b.wearVictim(.beret, for: 0), 9)
        b.wear(.beret, on: 0)
        XCTAssertEqual(b.wearerCharacters(.beret), [0])
    }

    func testOldSaveLoadsAsOneCopy() throws {
        let suite = "WearMultiTests.old.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        // a save written before copies: no wornAt / bodiesRefunded keys at all
        let json = #"{"wearables":["beret","sneakerMint"],"worn":{"0":{"head":"beret","feet":"sneakerMint"},"1":{"head":"beret"}}}"#
        d.set(Data(json.utf8), forKey: StoreBook.key)
        let w = DropsWallet(persists: false)
        let b = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b)
        XCTAssertEqual(b.copies(.beret), 1); XCTAssertEqual(b.copies(.sneakerMint), 1)
        XCTAssertEqual(b.worn(0, .head), .beret); XCTAssertNil(b.worn(1, .head), "one copy, one wearer")
        XCTAssertEqual(b.worn(0, .feet), .sneakerMint)
        XCTAssertEqual(b.owned(StoreCatalog.item(wearing: .beret)!), 1)
    }

    func testRetiredVestAndCardiganAreGoneTakenOffAndRefundedOnce() throws {
        XCTAssertNil(StoreCatalog.item(wearing: .vestPuffer)); XCTAssertNil(StoreCatalog.item(wearing: .cardiganCable))
        XCTAssertFalse(WearLook.pieces.contains(.vestPuffer)); XCTAssertFalse(WearLook.pieces.contains(.cardiganCable))
        let suite = "WearMultiTests.retired.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        var saved = StoreBook.Saved()
        saved.wearables = [WearLook.vestPuffer.rawValue, WearLook.vestPuffer.rawValue, WearLook.cardiganCable.rawValue, WearLook.beret.rawValue]
        saved.worn = ["0": ["body": WearLook.vestPuffer.rawValue, "head": WearLook.beret.rawValue], "1": ["body": WearLook.vestPuffer.rawValue], "2": ["body": WearLook.cardiganCable.rawValue]]
        d.set(try JSONEncoder().encode(saved), forKey: StoreBook.key)
        let w = DropsWallet(persists: false); let before = w.count
        let b = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b)
        XCTAssertEqual(w.count - before, 65 * 2 + 60, "two vests and a cardigan at their prices")
        XCTAssertEqual(b.saved.wearables, [WearLook.beret.rawValue])
        for k in 0...2 { XCTAssertNil(b.saved.worn["\(k)"]?["body"]) }
        XCTAssertEqual(b.worn(0, .head), .beret, "other clothes are untouched")
        let b2 = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b2)
        XCTAssertEqual(w.count - before, 65 * 2 + 60, "a second load never pays twice")
        XCTAssertEqual(StoreBook.dropRetiredBodies(StoreBook.Saved()).refund, 0)
    }

    func testMultiCopiesSurviveSaveAndReload() throws {
        let suite = "WearMultiTests.reload.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        let w = DropsWallet(persists: false); w.add(300, silent: true)
        let a = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(a)
        let id = StoreCatalog.item(wearing: .beret)!.id
        a.buy(id); a.buy(id); a.wear(.beret, on: 0); a.wear(.beret, on: 1)
        let b = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b)
        XCTAssertEqual(b.copies(.beret), 2); XCTAssertEqual(b.worn(0, .head), .beret); XCTAssertEqual(b.worn(1, .head), .beret)
    }
}
