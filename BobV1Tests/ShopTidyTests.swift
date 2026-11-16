//
//  ShopTidyTests.swift
//  2026-11-15 (the user's ask: "Remove Furniture section. Remove rc car, scooter, frisbee, and bubble machine. Ensure remaining toys all work and have
//  interactions."): the Shop has no Furniture tab (owned furniture stays in the bag and in the rooms), the toy car, kick scooter, frisbee and bubble machine
//  are retired (not sold; a save that owns one has it removed and refunded exactly once), and every toy still sold has something a Jelmiko does with it.
//

import XCTest
@testable import BobV1

@MainActor
final class ShopTidyTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// The sixteen toys the Shop still sells.
    private static let soldToys: Set<DecorKind> = [.ball, .bouncymat, .blocks, .spintop, .yarnball, .drum, .soccerball, .minigoal, .plushbear, .pinwheel,
                                                   .beachball, .playtunnel, .plushdino, .footbag, .skateboard, .hoop]

    // the game's room and camera (the placement rules read them), as DecorTests sets them
    override func setUp() { DecorField.shared.clear(); GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    override func tearDown() { DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    private func book(_ d: UserDefaults) -> (StoreBook, DropsWallet) {
        let w = DropsWallet(persists: false)
        let b = StoreBook(wallet: w, persists: true, defaults: d, key: "k")
        Self.keep.append(b)
        return (b, w)
    }

    func testTheFourToysAreRetiredAtTheirShopPrices() {
        XCTAssertEqual(StoreBook.retiredToys, [.toycar, .kickscooter, .frisbee, .bubblemachine])
        let prices: [DecorKind: Int] = [.toycar: 50, .kickscooter: 55, .frisbee: 35, .bubblemachine: 60]
        for (k, price) in prices {
            XCTAssertTrue(k.isRetired, "\(k) is retired")
            XCTAssertNil(StoreCatalog.item(k.storeID), "\(k) is no longer sold")
            XCTAssertEqual(DecorKind.retiredPrices[k], price, "\(k) refund = the price it was sold at")
        }
        XCTAssertFalse(BallToy.kinds.contains(.frisbee), "the Play picker no longer offers the frisbee")
        XCTAssertFalse(ShopTab.toys.items.contains { $0.decor.map { StoreBook.retiredToys.contains($0) } ?? false })
    }

    /// A save that already went through the 2026-11-04 pass (`retiredDecorRefunded` true): only the flag-free pass can clear it.
    func testAnOlderSaveLosesTheFourToysEverywhereAndIsRefundedOnce() {
        let suite = "ShopTidyTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let old = #"""
        {"counts":{"decor-toycar":1,"decor-kickscooter":1,"decor-frisbee":2,"decor-bubblemachine":1,"decor-plant":1,"decor-yarnball":1,"sushi":3},
         "pages":[],"wearables":[],"worn":{},"starterGiven":true,"newItems":0,"placed":[],
         "placedAt":[{"uid":1,"kind":"toycar","x":1.0,"z":0.5},{"uid":2,"kind":"plant","x":-2.0,"z":1.0},{"uid":3,"kind":"frisbee","x":0.5,"z":1.5}],
         "stash":{"loft":[{"uid":4,"kind":"kickscooter","x":1.0,"z":0.5}]},"rooms":["loft"],"nextDecorUID":5,"retiredDecorRefunded":true}
        """#
        d.set(Data(old.utf8), forKey: "k")
        let (a, w) = book(d)
        XCTAssertEqual(w.count, 50 + 55 + 2 * 35 + 60, "toy car 50 + scooter 55 + two frisbees at 35 + bubble machine 60")
        for k in StoreBook.retiredToys { XCTAssertEqual(a.count(k.storeID), 0, "\(k) left the bag") }
        XCTAssertEqual(a.count("decor-plant"), 1); XCTAssertEqual(a.count("decor-yarnball"), 1); XCTAssertEqual(a.count("sushi"), 3, "other goods are untouched")
        XCTAssertEqual(a.placedDecor.map(\.kind), [.plant], "the placed toy car and frisbee are gone, the plant stays where it was")
        XCTAssertNil(a.saved.stash, "the stashed scooter is gone too")
        // loading again never pays twice
        let (b, w2) = book(d)
        XCTAssertEqual(w2.count, 0)
        XCTAssertEqual(b.placedDecor.map(\.kind), [.plant])
        XCTAssertEqual(b.count("decor-plant"), 1)
    }

    /// A save from before 2026-11-04: the older pass refunds every retired piece (the four toys included); the new pass then finds nothing.
    func testAVeryOldSaveIsRefundedOnceByTheOlderPass() {
        let suite = "ShopTidyTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let old = #"""
        {"counts":{"decor-toycar":1,"decor-loveseat":1,"decor-plant":1},"pages":[],"wearables":[],"worn":{},"starterGiven":true,"newItems":0,"placed":[],
         "placedAt":[{"uid":1,"kind":"toycar","x":1.0,"z":0.5},{"uid":2,"kind":"plant","x":-2.0,"z":1.0}],"nextDecorUID":3}
        """#
        d.set(Data(old.utf8), forKey: "k")
        let (a, w) = book(d)
        XCTAssertEqual(w.count, 50 + 120, "toy car 50 + loveseat 120, each paid once")
        XCTAssertEqual(a.placedDecor.map(\.kind), [.plant])
        let (_, w2) = book(d)
        XCTAssertEqual(w2.count, 0)
    }

    func testASaveWithoutTheFourToysIsUntouched() {
        let (s, refund, changed) = StoreBook.dropRetiredToys(StoreBook.Saved())
        XCTAssertEqual(refund, 0); XCTAssertFalse(changed)
        XCTAssertTrue(s.counts.isEmpty); XCTAssertNil(s.placedAt); XCTAssertNil(s.stash)
        var owner = StoreBook.Saved()
        owner.counts = ["decor-plant": 1, "decor-ball": 2]
        owner.placedAt = [PlacedDecor(uid: 1, kind: .plant, x: 1, z: 1)]
        let (kept, refund2, changed2) = StoreBook.dropRetiredToys(owner)
        XCTAssertEqual(refund2, 0); XCTAssertFalse(changed2)
        XCTAssertEqual(kept.counts, owner.counts); XCTAssertEqual(kept.placedAt, owner.placedAt)
    }

    func testTheShopHasNoFurnitureTabAndOwnedFurnitureStillWorks() {
        XCTAssertFalse(ShopTab.shown.contains(.furniture), "the Furniture section is gone from the Shop")
        XCTAssertTrue(ShopTab.shown.contains(.toys))
        XCTAssertNil(ShopTab.named("furniture")); XCTAssertNil(ShopTab.named("decor"), "the capture aid cannot open the hidden tab")
        XCTAssertEqual(ShopTab.named("toys"), .toys); XCTAssertEqual(ShopTab.named("food"), .food)
        // the catalogue still knows the furniture, so a player who owns a piece can still place it and arrange it
        let furniture = StoreCatalog.decorItems(.furniture)
        XCTAssertFalse(furniture.isEmpty)
        let b = StoreBook(wallet: DropsWallet(persists: false), persists: false)
        b.grant("decor-plant")
        XCTAssertEqual(b.count("decor-plant"), 1)
        XCTAssertNotNil(b.place("decor-plant"), "an owned plant can still be placed")
        XCTAssertEqual(b.placedDecor.map(\.kind), [.plant])
    }

    func testEveryToyStillSoldHasSomethingAJelmikoDoesWithIt() {
        let toys = Set(StoreCatalog.decorItems(.toys).compactMap(\.decor))
        XCTAssertEqual(toys, Self.soldToys, "the sixteen toys left in the Shop")
        // the goal has no behaviour of its own: it is shot at through the soccer ball, which is sold with it
        for k in toys where k != .minigoal { XCTAssertNotNil(k.activeInteraction, "\(k) is a toy nobody plays with") }
        XCTAssertEqual(DecorKind.soccerball.activeInteraction, .soccerKick)
        XCTAssertTrue(DecorKind.minigoal.use.contains("soccer ball"), "the Shop tells the player the goal needs a soccer ball")
        for k in toys { XCTAssertFalse(k.isRetired, "\(k)"); XCTAssertNotNil(StoreCatalog.item(k.storeID), "\(k) is sold") }
        // every ball the Play picker can throw is a toy the Shop sells; the bubble wand stays
        for k in BallToy.kinds { XCTAssertTrue(toys.contains(k), "\(k) is thrown in Play but not sold") }
        XCTAssertNotNil(StoreCatalog.item("toy-bubbleWand"))
        XCTAssertTrue(ShopTab.toys.items.contains { $0.id == "toy-bubbleWand" })
    }
}
