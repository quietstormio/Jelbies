//
//  MealTwoSeatsTests.swift
//  2026-11-17 feeding survey, fix C6: the home tray seats two per sitting (the hungriest first, the nearer on a tie); the third waits calmly, clear of both
//  eaters, facing the tray, and eats at the next sitting.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MealTwoSeatsTests: XCTestCase {
    override func setUp() { DiningGroup.homeSeats = 2 }
    override func tearDown() { DiningGroup.homeSeats = 2 }

    private func room() -> DiningJellyTests.Room {
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        return r
    }
    private func hungry(_ r: DiningJellyTests.Room) {
        r.care.store.grant("berries", 3)
        for i in 0..<3 { r.care.needs(for: i).set(.hunger, 0.1) }
        r.run(1)
    }

    /// Guards C6: the hungriest two sit first (a tie within 0.1 goes to the nearer), the rest later; with three seats everybody sits now.
    func testSeatingIsHungriestFirstThenNearest() {
        let two = GameCare.seating([0, 1, 2], level: { [0.5, 0.1, 0.55][$0] }, seats: 2, distance: { [3, 1, 1][$0] })
        XCTAssertEqual(two.now, [1, 2]); XCTAssertEqual(two.later, [0])
        let three = GameCare.seating([0, 1, 2], level: { [0.5, 0.1, 0.55][$0] }, seats: 3, distance: { [3, 1, 1][$0] })
        XCTAssertEqual(three.now, [0, 1, 2]); XCTAssertEqual(three.later, [])
    }

    /// Guards C6: three hungry Jellies at home eat as two then one: two diners in the first sitting, the third queued, all three eat in the end.
    func testThreeAtHomeEatTwoThenOne() {
        let r = room()
        hungry(r)
        r.care.feed()
        var sawTwo = false, sawQueued = false, firstSittingSeen = false
        r.run(70) {
            if r.care.group.isActive, !firstSittingSeen {
                firstSittingSeen = true
                sawTwo = r.care.group.memberIDs.count == 2
                sawQueued = r.care.groupQueue.count == 1 && !r.care.group.memberIDs.contains(r.care.groupQueue[0])
            }
            return r.t > 2 && !r.care.trayOut && !r.care.groupActive
        }
        XCTAssertTrue(firstSittingSeen, "a sitting started")
        XCTAssertTrue(sawTwo, "the first sitting has two diners")
        XCTAssertTrue(sawQueued, "the third waits in the queue")
        XCTAssertFalse(r.care.trayOut, "the trays are gone")
        XCTAssertTrue(r.sawEating.allSatisfy { $0 }, "all three ate \(r.sawEating)")
    }

    /// Guards C6: the waiter keeps clear of both eaters and ends up facing the tray.
    func testTheWaiterWaitsClearOfBothEatersFacingTheTray() {
        let r = room()
        hungry(r)
        r.care.feed()
        var waiter: Int?, minClear: Float = .infinity, atBothEating = false
        r.run(40) {
            let ids = r.care.group.memberIDs
            guard r.care.group.isActive, ids.count == 2, let w = r.care.groupQueue.first else { return false }
            if ids.allSatisfy({ r.actors[$0].brain?.activity == .eating }) {
                waiter = w; atBothEating = true
                let p = r.actors[w].floor
                minClear = r.care.group.standsNow.map { simd_distance(p, $0) }.min() ?? .infinity
                return true
            }
            return false
        }
        guard atBothEating, let w = waiter else {
            XCTFail("the harness never saw both diners of the first sitting eating within 40 s (t=\(r.t), active=\(r.care.group.isActive), members=\(r.care.group.memberIDs), queue=\(r.care.groupQueue), activities=\(r.actors.map { String(describing: $0.brain?.activity) }))")
            return
        }
        XCTAssertGreaterThanOrEqual(minClear, DiningGroup.waiterClear - 0.15, "the waiter \(w) is \(minClear) from the nearest eater")
        var idle = false
        r.run(10) {
            if r.actors[w].brain?.activity == .idle, r.care.groupQueue.contains(w) { idle = true; return true }
            return !r.care.group.isActive
        }
        guard idle, let o = r.care.group.originNow, let b = r.actors[w].brain else {
            XCTFail("the waiter never stood idle in the queue (t=\(r.t), activity=\(String(describing: r.actors[w].brain?.activity)), queue=\(r.care.groupQueue))")
            return
        }
        let p = r.actors[w].floor
        let want = atan2f(o.x - p.x, o.y - p.y)
        var d = b.yaw - want
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        XCTAssertLessThan(abs(d), 0.25, "the waiter faces the tray: yaw \(b.yaw) vs \(want)")
    }
}
