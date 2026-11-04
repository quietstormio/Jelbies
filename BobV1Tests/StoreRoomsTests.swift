//
//  StoreRoomsTests.swift
//  Rooms in the Shop: bought once with Drops, the home room is free, and the decor placement is saved per room.
//

import XCTest
@testable import BobV1

@MainActor
final class StoreRoomsTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private func suite(_ n: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "StoreRoomsTests.\(n)")!
        d.removePersistentDomain(forName: "StoreRoomsTests.\(n)")
        return d
    }
    private func book(_ drops: Int, d: UserDefaults, persists: Bool = true) -> (StoreBook, DropsWallet) {
        let w = DropsWallet(persists: false); w.add(drops, silent: true)
        let b = StoreBook(wallet: w, persists: persists, defaults: d, key: "book")
        Self.keep.append(b)
        return (b, w)
    }
    override func tearDown() { RoomLayout.apply(RoomCatalog.home) }

    func testBuy() {
        let (b, w) = book(299, d: suite("buy"))
        XCTAssertEqual(b.buy("room-loft"), .notEnough)
        w.add(1, silent: true)
        XCTAssertEqual(b.buy("room-loft"), .bought)
        XCTAssertEqual(w.count, 0)
        XCTAssertEqual(StoreTuning.roomPrices[.loft], 300)
        XCTAssertEqual(b.buy("room-loft"), .alreadyOwned)
        XCTAssertTrue(b.ownsRoom(.loft)); XCTAssertFalse(b.ownsRoom(.cabin)); XCTAssertTrue(b.ownsRoom(.home))
        XCTAssertEqual(b.ownedRooms, [.home, .loft])
        XCTAssertFalse(b.moveIn(.cabin), "not owned")
        XCTAssertNil(StoreCatalog.item("room-home")); XCTAssertEqual(StoreCatalog.items(.room).count, 2)
        XCTAssertEqual(ShopTab.rooms.items.count, 2)
    }

    func testDecorIsPerRoom() {
        let d = suite("decor")
        let (b, _) = book(0, d: d)
        b.grant("room-loft"); b.grant("decor-plant", 2)
        XCTAssertNotNil(b.place("decor-plant"))
        XCTAssertEqual(b.placedDecor.count, 1)
        XCTAssertTrue(b.moveIn(.loft))
        RoomLayout.apply(RoomCatalog.loft)
        XCTAssertEqual(b.currentRoom, .loft)
        XCTAssertTrue(b.placedDecor.isEmpty)
        XCTAssertEqual(b.unplaced("decor-plant"), 1)
        XCTAssertNotNil(b.place("decor-plant"))
        XCTAssertNil(b.place("decor-plant"), "only two plants are owned")
        XCTAssertEqual(b.placedCount("decor-plant"), 2)
        // a new book on the same defaults keeps both lists and the current room
        let b2 = StoreBook(wallet: DropsWallet(persists: false), persists: true, defaults: d, key: "book")
        Self.keep.append(b2)
        XCTAssertEqual(b2.currentRoom, .loft); XCTAssertEqual(b2.placedDecor.count, 1)
        XCTAssertTrue(b2.moveIn(.home))
        XCTAssertEqual(b2.placedDecor.count, 1)
        XCTAssertTrue(b.moveIn(.home))
        XCTAssertEqual(b.currentRoom, .home); XCTAssertEqual(b.placedDecor.count, 1)
        b.putAwayAll()
        XCTAssertEqual(b.placedCount("decor-plant"), 1, "put away clears only this room")
        XCTAssertTrue(b.moveIn(.loft)); XCTAssertEqual(b.placedDecor.count, 1)
    }

    func testCapacityPerRoom() {
        let (b, _) = book(0, d: suite("cap"), persists: false)
        b.grant("room-loft"); b.grant("decor-plant", 12)
        var n = 0
        while b.place("decor-plant") != nil { n += 1 }
        XCTAssertGreaterThan(n, 0)
        XCTAssertGreaterThan(b.unplaced("decor-plant"), 0)
        RoomLayout.apply(RoomCatalog.home)
        b.moveIn(.loft); RoomLayout.apply(RoomCatalog.loft)
        XCTAssertEqual(b.roomUnitsUsed, 0)
        XCTAssertTrue(b.canPlace(StoreCatalog.item("decor-plant")!))
        XCTAssertNotNil(b.place("decor-plant"))
        XCTAssertEqual(b.roomUnitsUsed, 1)
    }

    func testOldSaveDecodes() throws {
        let d = suite("old")
        let old = #"{"counts":{"decor-plant":1},"pages":[],"wearables":[],"worn":{},"starterGiven":true,"newItems":0,"placed":[],"placedAt":[{"uid":1,"kind":"plant","x":1.0,"z":0.5}],"nextDecorUID":2}"#
        d.set(Data(old.utf8), forKey: "book")
        let (b, _) = book(0, d: d)
        XCTAssertEqual(b.currentRoom, .home)
        XCTAssertEqual(b.placedDecor.count, 1)
        XCTAssertEqual(b.ownedRooms, [.home])
    }
}
