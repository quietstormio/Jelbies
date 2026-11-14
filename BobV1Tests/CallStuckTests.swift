//
//  CallStuckTests.swift
//  "Come here" for everyone never sticks (2026-11-01: Bob wedged between two standing Jelbies, the HUD gone, no way out), and every group action shows a Cancel pill.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CallStuckTests: XCTestCase {
    static var keep: [AnyObject] = []

    /// Worst layout: the two side ones already stand on their row spots, Bob (the middle one) stands behind, between them.
    func testCallEveryoneWithTheMiddleOneBehindTwoStandingOnesStillCompletes() {
        let r = FocusAnyRun(count: 3, peers: true); Self.keep.append(r); r.run(1)
        let anchor = GameCamera.callSpot
        r.place(1, at: SIMD2(anchor.x - GameCamera.focusRowSpacing, anchor.y - GameCamera.focusRowBack))
        r.place(2, at: SIMD2(anchor.x + GameCamera.focusRowSpacing, anchor.y - GameCamera.focusRowBack))
        r.place(0, at: SIMD2(anchor.x, anchor.y - 1.6))
        r.care.comeHereEveryone()
        XCTAssertTrue(r.care.cancelPill || { r.run(0.5); return r.care.cancelPill }(), "the Cancel pill is up from the start")
        let done = r.run(8.5) { r.care.focus.isFocused }
        XCTAssertTrue(done, "all three arrive or are accepted within 8 s (phase \(r.care.focus.phase), arrived \(r.care.focusGroup.arrived))")
        XCTAssertEqual(r.care.focusGroup.arrived, [0, 1, 2])
        XCTAssertFalse(r.care.cancelPill, "the pill gives way to Let them go")
        r.care.release()
        XCTAssertTrue(r.run(10) { r.care.focus.phase == .roaming })
        r.run(2)
        XCTAssertFalse(r.care.focus.isActive, "the normal HUD is back")
        XCTAssertTrue(r.actors.allSatisfy { $0.brain!.autonomy })
    }

    /// A Jelbie pinned for good (held by a wall of bodies, never calm) is accepted where he stands after the grace time.
    func testSafetyNetAcceptsAJelbieThatNeverArrives() {
        let r = FocusAnyRun(count: 3, peers: true); Self.keep.append(r); r.run(1)
        r.care.comeHereEveryone()
        r.actors[2].brain!.interruptScript = true
        // pin Jelly 2 far from his spot by re-placing him every step
        let far = SIMD2<Float>(-2.0, -1.5)
        var ok = false
        for _ in 0..<Int(9.5 * 60) {
            if !r.care.focus.isFocused { r.actors[2].sim.teleport(toXZ: far) }
            r.tick()
            if r.care.focus.isFocused { ok = true; break }
        }
        XCTAssertTrue(ok, "the line-up completes even with one Jelmiko pinned (phase \(r.care.focus.phase))")
    }

    func testCancelPillAppearsAtOnceAndCancelRestoresRoamingAndHUD() {
        let r = FocusAnyRun(count: 3, peers: true); Self.keep.append(r); r.run(1)
        XCTAssertFalse(r.care.cancelPill)
        r.care.comeHereEveryone()
        r.run(0.5)
        XCTAssertTrue(r.care.cancelPill, "pill within 0.5 s of the call")
        XCTAssertFalse(r.care.focus.showsRelease)
        r.care.cancelGroupAction()
        r.run(2)
        XCTAssertEqual(r.care.focus.phase, .roaming)
        XCTAssertFalse(r.care.cancelPill)
        XCTAssertTrue(r.actors.allSatisfy { $0.brain!.autonomy }, "everyone roams again")
        XCTAssertEqual(r.care.focusedJellies, [])
        // one Jelbie's come here too
        r.care.comeHere(jelly: 1)
        r.run(0.5)
        XCTAssertTrue(r.care.cancelPill)
        r.care.cancelGroupAction()
        r.run(2)
        XCTAssertEqual(r.care.focus.phase, .roaming)
        XCTAssertTrue(r.actors.allSatisfy { $0.brain!.autonomy })
    }
}
