//
//  GuestArrivalTests.swift
//  The arrival moment's timeline (Park/GuestArrival.swift): doorbell at 0, card at 0.6, the body built between 0.6 and 1.8, the run-in at 1.8, the hug at 2.6,
//  done by 3.5; a second invite while one is coming or here is ignored.
//

import XCTest
@testable import BobV1

@MainActor
final class GuestArrivalTests: XCTestCase {
    private func run(_ clock: inout ArrivalClock, seconds: Float) -> [(t: Float, e: ArrivalEvent)] {
        var out = [(Float, ArrivalEvent)]()
        let dt: Float = 1.0 / 60
        var t: Float = 0
        while t < seconds {
            t += dt
            for e in clock.advance(dt) { out.append((t, e)) }
        }
        return out
    }

    func testTimelineMatchesTheBoard() {
        var c = ArrivalClock()
        XCTAssertTrue(c.start())
        let ev = run(&c, seconds: 4)
        XCTAssertEqual(ev.map(\.e), [.doorbell, .showCard, .build, .hideCard, .runIn, .hug, .finished])
        func at(_ e: ArrivalEvent) -> Float { ev.first { $0.e == e }!.t }
        XCTAssertLessThan(at(.doorbell), 0.05)
        XCTAssertEqual(at(.showCard), 0.6, accuracy: 0.03)
        XCTAssertGreaterThanOrEqual(at(.build), 0.6); XCTAssertLessThanOrEqual(at(.build), 1.8)
        XCTAssertEqual(at(.runIn), 1.8, accuracy: 0.03)
        XCTAssertEqual(at(.hideCard), 1.8, accuracy: 0.03)
        XCTAssertEqual(at(.hug), 2.6, accuracy: 0.03)
        XCTAssertLessThanOrEqual(at(.finished), 3.5)
        XCTAssertFalse(c.active, "done: the clock is idle again")
    }

    func testASecondArrivalIsIgnoredWhileOneRuns() {
        var c = ArrivalClock()
        XCTAssertTrue(c.start())
        _ = run(&c, seconds: 1)
        XCTAssertFalse(c.start(), "a second start while one is running does nothing")
        let rest = run(&c, seconds: 4)
        XCTAssertEqual(rest.filter { $0.e == .doorbell }.count, 0, "no second doorbell")
        XCTAssertTrue(c.start(), "after it finished a new one can run")
    }

    func testCancelStopsEverything() {
        var c = ArrivalClock()
        c.start(); _ = run(&c, seconds: 0.8)
        c.cancel()
        XCTAssertTrue(run(&c, seconds: 4).isEmpty)
        XCTAssertFalse(c.active)
    }

    func testSecondInviteIgnoredByTheBook() {
        let suite = UserDefaults(suiteName: "GuestArrivalTests.\(UUID().uuidString)")!
        let book = GuestBook(defaults: suite)
        XCTAssertTrue(book.invite(visitor: 2, kind: .playDate, now: 100))
        XCTAssertFalse(book.invite(visitor: 5, kind: .sleepover, now: 101), "one guest at a time, whether coming or here")
        XCTAssertTrue(book.arrival.start())
        XCTAssertFalse(book.arrival.start())
        book.finish()
        XCTAssertFalse(book.arrival.active, "the end of the visit clears the arrival")
        XCTAssertEqual(book.arrivalCard, .hidden)
    }

    /// 2026-11-11: a friend comes in from, and goes out through, the screen's LEFT edge in every window: the point is left of the visible floor, and the body's RIGHT edge
    /// (x + 0.9, projected through the real camera) is left of pixel 0, in portrait and landscape, phone and tablet.
    func testEntryAndExitAreOffTheLeftEdgeInEveryWindow() {
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        for aspect: Float in [440.0 / 956.0, 0.75, 1.33, 2.17] {
            GameCamera.configureRoom(count: 1)
            _ = GameCamera.camera(aspect: aspect)
            let size = CGSize(width: CGFloat(1000 * aspect), height: 1000)
            for z: Float in [-1.0, 0.5, 2.4] {
                let p = GuestEdge.offLeft(z: z, aspect: aspect)
                XCTAssertLessThan(p.x, -GameCamera.visibleHalfWidthAtBody(z: z, aspect: aspect), "left of the visible floor at aspect \(aspect) z \(z)")
                if let s = ThoughtBubbleView.project(SIMD3(p.x + 0.9, 0.7, z), size: size, focus: 0) {
                    XCTAssertLessThan(s.x, 0, "the body's right edge is off the left of the screen at aspect \(aspect) z \(z): \(s.x)")
                } else { XCTFail("not projectable at aspect \(aspect)") }
            }
        }
    }
}
