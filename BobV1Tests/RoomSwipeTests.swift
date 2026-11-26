//
//  RoomSwipeTests.swift
//  The room swipe's maths (Room/RoomSwipe.swift): the rubber band, the 4 s idle + 0.8 s ease home, the fast snap-in when a close-up turns it off.
//

import XCTest
@testable import BobV1

final class RoomSwipeTests: XCTestCase {
    override func setUp() { RoomSwipe.yaw = 0; RoomSwipe.end(now: 0) }

    private func run(_ seconds: Double, from t0: Double, allowed: Bool = true) -> Double {
        var t = t0
        for _ in 0..<Int(seconds * 60) { t += 1.0 / 60; RoomSwipe.tick(dt: 1.0 / 60, now: t, allowed: allowed) }
        return t
    }

    func testBandStaysNearTheLimit() {
        XCTAssertEqual(RoomSwipe.band(0.3), 0.3, accuracy: 1e-6)
        XCTAssertLessThan(RoomSwipe.band(5), RoomSwipe.limit + RoomSwipe.stretch + 1e-4)
        XCTAssertGreaterThan(RoomSwipe.band(0.6), RoomSwipe.limit)
        XCTAssertEqual(RoomSwipe.band(-0.6), -RoomSwipe.band(0.6), accuracy: 1e-6)
    }

    func testDragThenIdleEasesHomeInAboutFourPointEightSeconds() {
        var t = 100.0
        RoomSwipe.begin(now: t)
        for _ in 0..<40 { t += 1.0 / 60; RoomSwipe.drag(dx: -12, dt: 1.0 / 60, now: t) }          // a long swipe left
        RoomSwipe.end(now: t + 0.2)
        XCTAssertGreaterThan(abs(RoomSwipe.yaw), 0.15)
        XCTAssertLessThanOrEqual(abs(RoomSwipe.yaw), RoomSwipe.limit + RoomSwipe.stretch + 1e-4)
        t = run(3.0, from: t + 0.2)
        XCTAssertNotEqual(RoomSwipe.yaw, 0, "still turned before the 4 s are up")
        t = run(2.5, from: t)
        XCTAssertEqual(RoomSwipe.yaw, 0, accuracy: 1e-5, "home after 4 s + 0.8 s")
    }

    func testTurnedOffSnapsBackFast() {
        var t = 200.0
        RoomSwipe.begin(now: t)
        for _ in 0..<20 { t += 1.0 / 60; RoomSwipe.drag(dx: 12, dt: 1.0 / 60, now: t) }
        RoomSwipe.end(now: t)
        XCTAssertNotEqual(RoomSwipe.yaw, 0)
        _ = run(0.6, from: t, allowed: false)
        XCTAssertEqual(RoomSwipe.yaw, 0, accuracy: 0.003)
    }
}
