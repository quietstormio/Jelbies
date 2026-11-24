//
//  ComeHereFreezeTests.swift
//  come-here-freeze-r1 (the owner, 2026-11-23: "Pink has not moved at all after I started them come here to cuddle then I cancelled it ... closing the app fixed it").
//  Every way out of a call gives the called Jelmiko his life back, and the safety net frees anyone the call forgot.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ComeHereFreezeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func rig(_ count: Int = 3) -> FocusAnyRun { let r = FocusAnyRun(count: count, peers: true); Self.keep.append(r); r.run(1); return r }

    /// Everybody asleep-free and roaming again: autonomy back on, nothing of the call left on any brain, the group forgotten.
    private func assertFree(_ r: FocusAnyRun, _ why: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.care.focus.phase, .roaming, why, file: file, line: line)
        for a in r.actors {
            let b = a.brain!
            XCTAssertTrue(b.autonomy, "\(why): Jelly \(a.id) has his autonomy back", file: file, line: line)
            XCTAssertFalse(b.commanded, "\(why): Jelly \(a.id) is not commanded", file: file, line: line)
            XCTAssertFalse(b.reserved, "\(why): Jelly \(a.id) is not reserved", file: file, line: line)
        }
        XCTAssertTrue(r.care.focusGroup.saved.isEmpty, "\(why): nothing saved", file: file, line: line)
        XCTAssertTrue(r.care.focusGroup.ids.isEmpty, "\(why): the group is forgotten", file: file, line: line)
    }

    /// THE HOLE: "Come here" for everyone, Jelly 0 already stands near his slot and is taken in (autonomy off, waiting for the others), Cancel is pressed before the last one arrives.
    func testCancelWhileJellyZeroHasArrivedAndOthersAreStillComing() {
        let r = rig()
        let a = GameCamera.callSpot
        r.place(1, at: SIMD2(-2.2, -1.8)); r.place(2, at: SIMD2(2.2, -1.8))
        r.place(0, at: SIMD2(a.x, a.y - 0.2))
        r.care.comeHereEveryone()
        XCTAssertTrue(r.run(4) { r.care.focusGroup.arrived.contains(0) && r.care.focus.phase == .approaching }, "Jelly 0 is taken in while the others come")
        XCTAssertFalse(r.actors[0].brain!.autonomy, "(he waits on the spot)")
        r.care.cancelGroupAction()
        r.run(3)
        assertFree(r, "cancel after Jelly 0 arrived")
        // and he really moves again
        let p0 = r.centroid(0)
        var moved: Float = 0
        r.run(20) { moved = max(moved, simd_distance(r.centroid(0), p0)); return moved > 0.5 }
        XCTAssertGreaterThan(moved, 0.5, "Jelly 0 roams again")
    }

    /// A later call must not snapshot the stuck "off" either: cancel, call again, let go: everyone is free.
    func testCancelThenCallAgainThenLetGoLeavesEveryoneFree() {
        let r = rig()
        let a = GameCamera.callSpot
        r.place(1, at: SIMD2(-2.2, -1.8)); r.place(2, at: SIMD2(2.2, -1.8)); r.place(0, at: SIMD2(a.x, a.y - 0.2))
        r.care.comeHereEveryone()
        r.run(4) { r.care.focusGroup.arrived.contains(0) && r.care.focus.phase == .approaching }
        r.care.cancelGroupAction(); r.run(1)
        r.care.comeHereEveryone()
        XCTAssertTrue(r.run(12) { r.care.focus.isFocused })
        r.care.release()
        XCTAssertTrue(r.run(10) { r.care.focus.phase == .roaming })
        r.run(3)
        assertFree(r, "cancel, call again, let go")
    }

    /// Cancel / release a single call at many moments (before the walk, mid-walk, as he arrives, in the close-up, while it leaves): everybody is free afterwards.
    func testSingleCallCancelledAtManyMoments() {
        for who in [0, 1, 2] {
            for delay in [0.0, 0.2, 0.6, 1.2, 2.0, 3.0, 4.5, 7.0] {
                let r = rig()
                r.care.comeHere(jelly: who)
                r.run(Float(delay))
                if r.care.focus.phase == .approaching { r.care.cancelGroupAction() } else { r.care.release() }
                XCTAssertTrue(r.run(12) { r.care.focus.phase == .roaming && r.actors.allSatisfy { $0.brain!.autonomy } }, "call \(who), cancel at \(delay): free again (phase \(r.care.focus.phase), auto \(r.actors.map { $0.brain!.autonomy }))")
                r.run(1)
                assertFree(r, "call \(who), cancel at \(delay)")
            }
        }
    }

    /// Two of three called (a row), cancelled at many moments.
    func testRowOfTwoCancelledAtManyMoments() {
        for delay in [0.0, 0.5, 1.0, 2.0, 3.0, 5.0, 8.0] {
            let r = rig()
            r.care.beginFocus(ids: [0, 2])
            r.run(Float(delay))
            if r.care.focus.phase == .approaching { r.care.cancelGroupAction() } else { r.care.release() }
            XCTAssertTrue(r.run(12) { r.care.focus.phase == .roaming && r.actors.allSatisfy { $0.brain!.autonomy } }, "row of two, cancel at \(delay) (phase \(r.care.focus.phase), auto \(r.actors.map { $0.brain!.autonomy }))")
            r.run(1)
            assertFree(r, "row of two, cancel at \(delay)")
        }
    }

    /// Call one, cancel, call a different one: the first one is free the whole time.
    func testCallOneCancelCallAnother() {
        let r = rig()
        r.care.comeHere(jelly: 1); r.run(1.0); r.care.cancelGroupAction(); r.run(0.3)
        r.care.comeHere(jelly: 2); r.run(1.0)
        XCTAssertTrue(r.actors[1].brain!.autonomy, "the first call's Jelmiko is free while the second is called")
        r.care.cancelGroupAction(); r.run(3)
        assertFree(r, "call one, cancel, call another, cancel")
    }

    // MARK: safety net

    /// A body the focus switched off and nobody gave back (any cause) is freed after a few seconds while no close-up is on, with one `[stuck]` line.
    func testSafetyNetFreesAnyoneTheCallForgot() {
        let r = rig()
        let b = r.actors[1].brain!
        r.care.focusTook(1)                  // (what `enterFocus` and the arrival do)
        b.autonomy = false                   // ... and the hand-back is lost
        XCTAssertEqual(r.care.focus.phase, .roaming)
        r.run(GameCare.focusNetAfter - 0.5)
        XCTAssertFalse(b.autonomy, "not before the grace time")
        r.run(1.5)
        XCTAssertTrue(b.autonomy, "released after the grace time")
        XCTAssertEqual(r.care.focusNetReleased, 1)
    }

    /// The net never cuts a real call short: not while approaching or focused, not for a body something else holds (bath / meal), not for a sleeper.
    func testSafetyNetLeavesARealCallAlone() {
        let r = rig()
        r.care.comeHere(jelly: 1)
        XCTAssertTrue(r.run(10) { r.care.focus.isFocused })
        r.run(GameCare.focusNetAfter + 3)          // a long cuddle
        XCTAssertTrue(r.care.focus.isFocused)
        XCTAssertEqual(r.care.focusNetReleased, 0)
        XCTAssertFalse(r.actors[1].brain!.autonomy, "he stays on his spot while the close-up is on")
        r.care.release(); XCTAssertTrue(r.run(10) { r.care.focus.phase == .roaming }); r.run(2)
        XCTAssertTrue(r.actors[1].brain!.autonomy)
        XCTAssertEqual(r.care.focusNetReleased, 0)
    }

    func testSafetyNetLeavesBodiesSomethingElseHoldsAlone() {
        let r = rig()
        r.care.focusTook(2)
        let b = r.actors[2].brain!
        b.sleepEnabled = true; b.sleepInstant(r.actors[2].sim, r.actors[2].skinner)          // (he sleeps: the night's, not ours)
        r.run(2)
        XCTAssertTrue(b.isNapping)
        b.autonomy = false
        r.run(GameCare.focusNetAfter + 2)
        XCTAssertEqual(r.care.focusNetReleased, 0, "a body another system holds is not ours to take")
        XCTAssertFalse(b.autonomy)
    }

    /// The old behaviour, kept as a record (hand-back and net off): this is the freeze the owner saw.
    func testTheFreezeBeforeTheFix() {
        let (fix, net) = (FocusGroup.handBackFix, FocusGroup.netEnabled)
        FocusGroup.handBackFix = false; FocusGroup.netEnabled = false
        defer { FocusGroup.handBackFix = fix; FocusGroup.netEnabled = net }
        let r = rig()
        let a = GameCamera.callSpot
        r.place(1, at: SIMD2(-2.2, -1.8)); r.place(2, at: SIMD2(2.2, -1.8)); r.place(0, at: SIMD2(a.x, a.y - 0.2))
        r.care.comeHereEveryone()
        XCTAssertTrue(r.run(4) { r.care.focusGroup.arrived.contains(0) && r.care.focus.phase == .approaching })
        r.care.cancelGroupAction()
        r.run(30)
        XCTAssertFalse(r.actors[0].brain!.autonomy, "before the fix: Jelly 0 stands there for good after the cancel")
    }
}
