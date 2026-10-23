//
//  RoomSwitchTests.swift
//  GameCare.switchRoom: refusals, the fade and the single swap under it.
//

import XCTest
@testable import BobV1

@MainActor
final class RoomSwitchTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private func care(_ n: String) -> GameCare {
        let d = UserDefaults(suiteName: "RoomSwitchTests.\(n)")!
        d.removePersistentDomain(forName: "RoomSwitchTests.\(n)")
        let c = GameCare(jellyCount: 3, persistent: false, defaults: d)
        Self.keep.append(c)
        return c
    }
    override func tearDown() { RoomLayout.apply(RoomCatalog.home); GameCamera.configureRoom(count: 1) }

    func testBlockers() {
        let c = care("blockers")
        XCTAssertEqual(c.roomID, .home)
        XCTAssertEqual(c.roomSwitchBlocker(.loft), .notOwned)
        XCTAssertEqual(c.roomSwitchBlocker(.home), .same)
        c.store.grant("room-loft")
        XCTAssertNil(c.roomSwitchBlocker(.loft))
        c.arranging = true
        XCTAssertEqual(c.roomSwitchBlocker(.loft), .arranging)
        XCTAssertEqual(c.switchRoom(.loft), .arranging)
        XCTAssertFalse(c.roomSwitch.active)
        c.arranging = false
        XCTAssertNil(c.switchRoom(.loft))
        XCTAssertEqual(c.roomSwitchBlocker(.loft), .busy)
        XCTAssertEqual(c.switchRoom(.loft), .busy)
    }

    func testFadeSwapsExactlyOnce() {
        let c = care("flow")
        c.store.grant("room-loft")
        XCTAssertNil(c.switchRoom(.loft))
        XCTAssertEqual(c.roomSwitch.phase, .out)
        XCTAssertEqual(RoomLayout.current.id, .home, "nothing swaps before the veil is white")
        var swappedAt: Int?, steps = 0, maxWipe: Float = 0
        while c.roomSwitch.active && steps < 240 {
            c.tickRoomSwitch(dt: 1.0 / 60); steps += 1
            maxWipe = max(maxWipe, c.roomSwitch.wipe)
            if swappedAt == nil, RoomLayout.current.id == .loft { swappedAt = steps; XCTAssertGreaterThanOrEqual(c.roomSwitch.wipe, 1); XCTAssertEqual(c.store.currentRoom, .loft) }
        }
        XCTAssertNotNil(swappedAt)
        XCTAssertEqual(maxWipe, 1)
        XCTAssertLessThan(Double(steps) / 60, 1.3)
        XCTAssertEqual(c.roomSwitch.phase, .off); XCTAssertEqual(c.roomSwitch.wipe, 0)
        XCTAssertEqual(c.roomID, .loft)
        XCTAssertEqual(c.roomSwitchBlocker(.loft), .same)
        // and back
        XCTAssertNil(c.switchRoom(.home))
        while c.roomSwitch.active { c.tickRoomSwitch(dt: 1.0 / 60) }
        XCTAssertEqual(RoomLayout.current.id, .home); XCTAssertEqual(c.roomID, .home)
    }

    func testNewGameStartsAtHomeAfterLoft() {
        RoomLayout.apply(RoomCatalog.loft)
        let c = care("fresh")
        XCTAssertEqual(RoomLayout.current.id, .home, "a headless game applies its saved room (home)")
        XCTAssertEqual(c.roomID, .home)
    }
}
