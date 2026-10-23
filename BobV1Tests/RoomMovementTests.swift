//
//  RoomMovementTests.swift
//  2026-10-21, the phone report (roster Pip, Moss, Lavender): "I called over Moss but the other ones are stuck blocking him, they just stopped. I had just
//  interacted with Lavender." Two mechanisms:
//    1. the Jellies not in a close-up were PAUSED from the moment one was called, and `makeRoom` never moved a held Jelly, so whoever stood in the called one's lane
//       stayed there while he waited (6 s), walked into them, gave up and the call was cancelled. (W2, 2026-10-22: they are no longer paused or hidden at all:
//       they keep roaming outside the camera's keep-out wedge, GameCare+FocusKeepOut.swift; this suite now guards that nobody is ever frozen and the lane stays clear.)
//    2. a call landing in the one or two steps between a release and the hand-back of the paused Jellies' autonomy (`driveFocus`, one brain per step) wiped
//       `FocusGroup.saved` in `begin`, leaving them with autonomy off for good.
//  The fixes: `focusPaused` (a paused Jelly may step aside), `makeRoom.clearWay` (whoever stands in a requested walk's lane steps out of it), and `beginFocus`
//  hands any saved autonomy back first. The mini stage `FocusAnyRun(peers: true)` is wired like the room (peer snapshot, keepApart, makeRoom).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RoomMovementTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// The room as the game runs it with three Jellies: the room camera and its roaming polygon (portrait).
    override func setUp() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0); GameCamera.refreshRoam(aspect: 440.0 / 956.0)
    }
    override func tearDown() { GameCamera.clearRoam(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    private func run3() -> FocusAnyRun {
        let r = FocusAnyRun(peers: true)
        Self.keep.append(r)
        r.run(1.0)
        return r
    }
    /// Moss (1) at the back, Pip (0) and Lavender (2) standing either side of his straight line to the call spot (closer than the gap to it: he cannot pass
    /// between them, and the floor beside them is narrow).
    private func blockedLane(_ r: FocusAnyRun) {
        r.place(1, at: SIMD2(0, -2.0))
        r.place(0, at: SIMD2(-0.75, 0.5))
        r.place(2, at: SIMD2(0.75, 0.5))
        r.run(0.5)
    }
    private func allFree(_ r: FocusAnyRun) -> Bool {
        r.actors.allSatisfy { a in let b = a.brain!; return b.autonomy && !b.held && !b.focusPaused }          // (autonomy is the ones not focused; the focused one's is held on his spot)
    }

    // MARK: 1. the called Jelly gets through standing Jellies

    func testCalledJellyReachesTheCallSpotThroughTwoStandingBlockers() {
        let r = run3()
        blockedLane(r)
        let moss = r.actors[1].brain!
        r.care.comeHere(jelly: 1)
        XCTAssertEqual(r.care.focus.phase, .approaching)
        let arrived = r.run(15) { r.care.focus.phase == .focused }
        let d = simd_length(moss.position - GameCamera.callSpot)
        XCTAssertTrue(arrived, "Moss reached the call spot and the close-up started within 15 s (phase \(r.care.focus.phase), \(d) from the spot)")
        XCTAssertLessThan(d, 0.6, "Moss stands on the call spot")
        // the blockers moved out of his lane (or he routed around them): nobody stands inside the gap of the spot
        for id in [0, 2] { XCTAssertGreaterThan(simd_distance(r.actors[id].floor, GameCamera.callSpot), MelonController.jellyGap * 0.95, "Jelly \(id) is clear of the spot") }
    }

    /// The paused Jellies step aside PROMPTLY: within 3 s of the call a blocker in the lane is walking (not after the walker's 6 s patience).
    func testBlockersStepAsideWithinThreeSeconds() {
        let r = run3()
        blockedLane(r)
        r.care.comeHere(jelly: 1)
        var moved = Set<Int>()
        r.run(3) {
            for id in [0, 2] where r.actors[id].isWalking || simd_distance(r.actors[id].floor, id == 0 ? SIMD2(-0.75, 0.5) : SIMD2(0.75, 0.5)) > 0.3 { moved.insert(id) }
            return moved.count == 2
        }
        XCTAssertFalse(moved.isEmpty, "at least one blocker left the lane within 3 s (moved \(moved))")
    }

    // MARK: 2. everybody resumes after a close-up ends

    func testEverybodyResumesAutonomyAfterAFocusEnds() {
        let r = run3()
        r.care.comeHere(jelly: 2)
        XCTAssertTrue(r.run(20) { r.care.focus.phase == .focused }, "Lavender's close-up started")
        for a in r.actors where a.id != 2 { XCTAssertTrue(a.brain!.autonomy, "Jelly \(a.id) keeps roaming during the close-up"); XCTAssertFalse(a.brain!.idleBlocked) }
        r.run(1.0)
        r.care.release()
        XCTAssertTrue(r.run(6) { r.care.focus.phase == .roaming }, "the camera came home")
        XCTAssertTrue(r.run(2) { self.allFree(r) }, "everybody has his wandering back within 2 s: \(r.actors.map { ($0.id, $0.brain!.autonomy, $0.brain!.held, $0.brain!.focusPaused) })")
        // flag != motion: each of them starts a new leg or a look within the next 12 s
        var moved = Set<Int>()
        r.run(12) {
            for a in r.actors where a.isWalking || a.brain!.activity == .lookingAround || a.brain!.activity == .steppingInPlace || a.brain!.activity == .playing { moved.insert(a.id) }
            return moved.count == 3
        }
        XCTAssertEqual(moved.count, 3, "all three do something again (\(moved))")
    }

    /// A release while still approaching flips the phase at once; a call in the same step must not freeze the Jellies the first call had paused.
    func testCallRightAfterAnApproachReleaseLeavesNobodyFrozen() {
        let r = run3()
        r.care.comeHere(jelly: 2)
        r.run(0.5)
        XCTAssertEqual(r.care.focus.phase, .approaching)
        for a in r.actors where a.id != 2 { XCTAssertTrue(a.brain!.autonomy, "Jelly \(a.id) is not paused by the first call") }
        r.care.release()                                 // approaching -> roaming at once
        XCTAssertEqual(r.care.focus.phase, .roaming)
        r.care.comeHere(jelly: 1)                        // the same step: nobody has had his autonomy handed back yet
        XCTAssertTrue(r.run(20) { r.care.focus.phase == .focused }, "Moss's close-up started")
        r.run(0.5)
        r.care.release()
        XCTAssertTrue(r.run(6) { r.care.focus.phase == .roaming })
        XCTAssertTrue(r.run(2) { self.allFree(r) }, "nobody is left frozen: \(r.actors.map { ($0.id, $0.brain!.autonomy, $0.brain!.held) })")
    }

    /// The same, with the second call at every step of the hand-back window after a full close-up (0...3 steps after the phase came home).
    func testCallInTheHandBackWindowLeavesNobodyFrozen() {
        for delay in 0...3 {
            let r = run3()
            r.care.comeHere(jelly: 2)
            XCTAssertTrue(r.run(20) { r.care.focus.phase == .focused }, "delay \(delay): first close-up started")
            r.run(0.3)
            r.care.release()
            XCTAssertTrue(r.run(6) { r.care.focus.phase == .roaming }, "delay \(delay): the camera came home")
            for _ in 0..<delay { r.tick() }
            r.care.comeHere(jelly: 1)
            XCTAssertTrue(r.run(20) { r.care.focus.phase == .focused }, "delay \(delay): second close-up started")
            r.run(0.3)
            r.care.release()
            XCTAssertTrue(r.run(6) { r.care.focus.phase == .roaming })
            XCTAssertTrue(r.run(2) { self.allFree(r) }, "delay \(delay): nobody is left frozen: \(r.actors.map { ($0.id, $0.brain!.autonomy, $0.brain!.held) })")
        }
    }

    /// A pick ("Play with Lavender?") and its cancel leave everybody autonomous.
    func testSelectionAndCancelLeaveEverybodyFree() {
        let r = run3()
        r.care.select.setBlobs([SelectBlob(id: 0, name: "Pip"), SelectBlob(id: 1, name: "Moss"), SelectBlob(id: 2, name: "Lavender")])
        r.care.select.highlight(2)
        r.run(1.0)
        r.care.select.cancel()
        XCTAssertTrue(r.run(2) { self.allFree(r) && !r.care.select.isSelecting }, "free after a cancelled pick")
        r.care.select.highlight(2)
        r.run(0.5)
        r.care.select.confirm()
        r.run(1.0)
        r.care.comeHere(jelly: 1)
        XCTAssertTrue(r.run(20) { r.care.focus.phase == .focused }, "Moss comes after a pick of Lavender")
        r.care.release()
        XCTAssertTrue(r.run(6) { r.care.focus.phase == .roaming })
        XCTAssertTrue(r.run(2) { self.allFree(r) }, "free after the close-up: \(r.actors.map { ($0.id, $0.brain!.autonomy, $0.brain!.held) })")
    }

    // MARK: 3. the stage rule on its own

    /// `makeRoom.clearWay`: the paused Pip stands in Moss's lane and is sent out of it (a `goTo` sideways, over the gap from the lane), while the reserved
    /// Lavender (her meal is coming) is never moved, whatever stands in whose way.
    func testClearWayMovesAPausedStanderButNeverAReservedOne() {
        let r = run3()
        blockedLane(r)
        let pip = r.actors[0].brain!, lav = r.actors[2].brain!
        lav.reserved = true
        r.care.comeHere(jelly: 1)
        var pipAsked = false, lavMoved = false
        for _ in 0..<(60 * 4) {
            lav.reserved = true                      // (the care's meal bookkeeping rewrites `reserved` every step: keep her reserved as a coming meal would)
            r.tick()
            if pip.job != nil || pip.activity == .walking { pipAsked = true }
            if lav.job != nil || lav.activity == .walking || lav.activity == .coming { lavMoved = true }          // (her wait pose steps in place, and the passing walker's gap may nudge her: no WALK is asked of her)
        }
        XCTAssertTrue(pipAsked, "the paused Pip was asked to step out of Moss's lane")
        XCTAssertFalse(lavMoved, "the reserved Lavender stays where she waits (job \(String(describing: lav.job)) activity \(lav.activity) at \(lav.position) script \(lav.script))")
        XCTAssertGreaterThan(abs(pip.position.x), 0.75 + 0.3, "Pip went sideways, out of the lane (x \(pip.position.x))")
    }

    /// The user's exact sequence: a close-up on Lavender ends with her standing on the call spot; Moss is called next. Her body displaced his target (the
    /// floor rules keep the gap), so he used to stop 1.4 u short, wave there, and the call was cancelled. Now she steps aside and he arrives, quickly.
    func testCallAfterACloseUpLeftSomeoneOnTheSpotArrivesQuickly() {
        let r = run3()
        r.care.comeHere(jelly: 2)
        XCTAssertTrue(r.run(20) { r.care.focus.phase == .focused }, "Lavender's close-up started")
        r.run(0.3)
        r.care.release()
        XCTAssertTrue(r.run(6) { r.care.focus.phase == .roaming })
        // (W2: once released she is free to wander off the spot, as the others are: put her back on it, as the close-up left her, so the stand-on-the-spot case is what is tested)
        r.actors[2].brain!.requestNow(.goTo(GameCamera.callSpot))
        XCTAssertTrue(r.run(8) { simd_distance(r.actors[2].floor, GameCamera.callSpot) < 0.5 && r.actors[2].brain!.activity != .walking }, "Lavender stands on the call spot (\(simd_distance(r.actors[2].floor, GameCamera.callSpot)))")
        var t: Float = 0
        r.care.comeHere(jelly: 1)
        let arrived = r.run(20) { t += 1.0 / 60; return r.care.focus.phase == .focused }
        print("ROOMMOVE arrival \(t) s")
        XCTAssertTrue(arrived, "Moss's close-up started")
        XCTAssertLessThan(t, 12, "and within 12 s of the call (\(t) s)")
        XCTAssertLessThan(simd_distance(r.actors[1].floor, GameCamera.callSpot), 0.6, "Moss stands on the spot")
    }
}
