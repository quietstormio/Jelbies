//
//  ClearGuestTests.swift
//  `-ClearGuest 1` (StartFlow.applyClearGuest): only the guest visit key goes; the save is otherwise byte-identical; one-shot; `-ClearGuest 0` re-arms.
//

import XCTest
@testable import BobV1

@MainActor
final class ClearGuestTests: XCTestCase {
    func testClearsOnlyTheGuestVisit() throws {
        let name = "ClearGuestTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let guest = Data(#"{"invitedAt":1000,"visitor":2,"kind":"sleepover","arrivedAt":0,"endsAt":0}"#.utf8)
        let oldPlayDate = Data(#"{"invitedAt":1000,"visitor":2,"kind":"playDate","arrivedAt":0,"endsAt":0}"#.utf8)          // (a save from before the evening visits still decodes)
        XCTAssertEqual(try JSONDecoder().decode(GuestVisit.self, from: oldPlayDate).visitor, 2)
        let rest: [String: Data] = [
            JellyRoster.rosterKey: Data("[0,5,4]".utf8),
            DropsWallet.key: Data([1, 2, 3, 4]),
            StoreBook.key: Data(#"{"starterGiven":true,"x":[1,2,3]}"#.utf8),
            ParkBook.key: Data("[{\"id\":2}]".utf8),
            ParkBook.ledgerKey: Data("{}".utf8),
        ]
        d.set(guest, forKey: GuestBook.key)
        for (k, v) in rest { d.set(v, forKey: k) }

        XCTAssertTrue(StartFlow.applyClearGuest(arg: 1, defaults: d))
        XCTAssertNil(d.object(forKey: GuestBook.key))
        for (k, v) in rest { XCTAssertEqual(d.data(forKey: k), v, k) }
        XCTAssertEqual(GuestBook(defaults: d).visit, nil)

        // one-shot: a new stuck visit survives a relaunch with the same argument
        d.set(guest, forKey: GuestBook.key)
        XCTAssertFalse(StartFlow.applyClearGuest(arg: 1, defaults: d))
        XCTAssertNotNil(d.data(forKey: GuestBook.key))
        // no argument: nothing; 0 re-arms
        XCTAssertFalse(StartFlow.applyClearGuest(arg: nil, defaults: d))
        XCTAssertFalse(StartFlow.applyClearGuest(arg: 0, defaults: d))
        XCTAssertNil(d.object(forKey: StartFlow.clearGuestAppliedKey))
        XCTAssertTrue(StartFlow.applyClearGuest(arg: 1, defaults: d))
        XCTAssertNil(d.object(forKey: GuestBook.key))
    }

    /// 2026-10-31 crash: a guest makes 4 bodies; the 3-long cooldown / brains arrays must not trap makeRoom / clearWay.
    func testMakeRoomWithAFourthBodyDoesNotTrap() {
        let snap: [(pos: SIMD2<Float>, walking: Bool)] = [(SIMD2(0, 0), false), (SIMD2(0.1, 0), false), (SIMD2(2, 0), false), (SIMD2(0.05, 0.05), false)]
        var cooldown = [Float](repeating: 0, count: JellyRoster.maxCount)
        MelonController.makeRoom(snapshot: snap, brains: [nil, nil, nil], cooldown: &cooldown, dt: 0.25)
        XCTAssertEqual(cooldown.count, 4)
        XCTAssertEqual(cooldown, [0, 0, 0, 0])
        var c2 = [Float](repeating: 0, count: 3)
        MelonController.clearWay(snapshot: snap, brains: [nil, nil, nil], cooldown: &c2, free: { _ in true })
        XCTAssertEqual(c2.count, 4)
    }
}
