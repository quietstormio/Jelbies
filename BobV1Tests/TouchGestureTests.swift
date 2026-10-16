//
//  TouchGestureTests.swift
//  The gesture classifier: the gesture decides the action, from movement and hold time, never switching mid-gesture.
//

import XCTest
@testable import BobV1

final class TouchGestureTests: XCTestCase {
    private func g(_ t: Double = 0, _ p: CGPoint = CGPoint(x: 200, y: 400)) -> TouchGesture { var x = TouchGesture(); x.down(t: t, p: p); return x }

    func testQuickSlideIsPet() {
        var x = g()
        x.move(t: 0.05, p: CGPoint(x: 215, y: 400))
        XCTAssertEqual(x.kind, .pet)
        // never switches: holding still, then dragging up, stays a pet
        x.tick(t: 0.6); x.move(t: 0.7, p: CGPoint(x: 215, y: 300))
        XCTAssertEqual(x.kind, .pet)
        XCTAssertEqual(x.up(t: 0.8), .none)
    }

    func testTapIsATapAndALongStillPressIsAHoldThenTap() {
        var x = g()
        x.move(t: 0.05, p: CGPoint(x: 203, y: 401))        // jitter under the slop
        XCTAssertEqual(x.kind, .undecided)
        XCTAssertEqual(x.up(t: 0.15), .tap)
        var h = g()
        h.tick(t: 0.3)
        XCTAssertEqual(h.kind, .hold)
        XCTAssertEqual(h.up(t: 0.9), .tap)
    }

    func testHoldThenDragUpIsPickUp() {
        var x = g()
        x.tick(t: 0.26)
        XCTAssertEqual(x.kind, .hold)
        x.move(t: 0.3, p: CGPoint(x: 202, y: 380))
        XCTAssertEqual(x.kind, .pickUp)
        // and stays one
        x.move(t: 0.5, p: CGPoint(x: 400, y: 380))
        XCTAssertEqual(x.kind, .pickUp)
    }

    func testHoldThenSidewaysOrDownIsAStroke() {
        var a = g(); a.tick(t: 0.3); a.move(t: 0.4, p: CGPoint(x: 260, y: 402))
        XCTAssertEqual(a.kind, .pet)
        var b = g(); b.tick(t: 0.3); b.move(t: 0.4, p: CGPoint(x: 200, y: 450))
        XCTAssertEqual(b.kind, .pet)
    }

    func testTwoFingersTogetherIsCheeksButALateSecondFingerIsIgnored() {
        var x = g()
        XCTAssertTrue(x.secondDown(t: 0.08))
        XCTAssertEqual(x.kind, .cheeks)
        var late = g()
        late.tick(t: 0.3)
        XCTAssertFalse(late.secondDown(t: 0.3), "a late second finger never starts a pinch")
        XCTAssertEqual(late.kind, .hold)
        var moved = g()
        moved.move(t: 0.05, p: CGPoint(x: 230, y: 400))
        XCTAssertFalse(moved.secondDown(t: 0.1), "the first finger had already moved on: it is a stroke")
        XCTAssertEqual(moved.kind, .pet)
    }

    func testFastFlickOnReleaseIsAThrowASlowReleaseIsNot() {
        var x = g(); x.tick(t: 0.3)
        x.move(t: 0.35, p: CGPoint(x: 200, y: 380))
        var t = 0.4
        for k in 1...6 { x.move(t: t, p: CGPoint(x: 205, y: 380 - CGFloat(k) * 40)); t += 0.016 }     // 2500 pt/s up
        if case .throwIt(let v) = x.up(t: t + 0.01) { XCTAssertLessThan(v.dy, -1500) } else { XCTFail("throw") }
        var slow = g(); slow.tick(t: 0.3)
        slow.move(t: 0.35, p: CGPoint(x: 200, y: 380))
        for k in 1...10 { slow.move(t: 0.4 + Double(k) * 0.05, p: CGPoint(x: 200, y: 380 - CGFloat(k) * 4)); }
        XCTAssertEqual(slow.up(t: 1.0), .none)
    }
}
