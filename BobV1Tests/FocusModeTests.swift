//
//  FocusModeTests.swift
//  Focus mode == "Come here": enter only through comeHere(), leave only through release(); the camera spring; the close-up framing;
//  Feed / Drink from inside focus release first; the release hop; the care tick stays cheap.
//

import XCTest
import simd
@testable import BobV1

/// Game brain + care ticked like the stage does (brain, care with sim, sim step).
@MainActor
final class FocusRun {
    let rig = MotionRig(game: true, settle: 1.0)
    let care = GameCare()
    var brain: BlobBrain { rig.brain }
    var focus: BlobFocus { care.focus }
    init() { rig.brain.autonomy = true; rig.brain.seed = 7 }
    func tick() {
        brain.tick(sim: rig.sim, skinner: rig.skinner, dt: rig.sim.stepDt, touched: false)
        care.tick(brain: brain, renderer: nil, dt: rig.sim.stepDt, sim: rig.sim)
        rig.sim.step()
        rig.t += rig.sim.stepDt
    }
    @discardableResult
    func run(_ s: Float, until: (() -> Bool)? = nil) -> Bool {
        for _ in 0..<Int(s * 60) { tick(); if let until, until() { return true } }
        return until?() ?? false
    }
}

@MainActor
final class FocusModeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [FocusRun] = []     // the runtime aborts when a rig is released (see MelonModel)

    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = [] }     // a tray left out by a test must not block the next test's walk

    func testSpringSettlesWithoutOvershootAndLeavesAtExactlyZero() {
        let f = BlobFocus()
        f.beginApproach(); f.arrive()
        var peak: Float = 0, tSettle: Float?
        for i in 0..<120 {
            f.step(dt: 1.0 / 60); peak = max(peak, f.blend)
            if tSettle == nil, abs(f.blend - 1) < 0.02 { tSettle = Float(i + 1) / 60 }
        }
        XCTAssertLessThan(peak, 1.05, "barely any overshoot")
        XCTAssertNotNil(tSettle); XCTAssertLessThan(tSettle ?? 9, 0.85, "about 0.7 s")
        f.release()
        XCTAssertEqual(f.phase, .leaving)
        var ended = false
        for _ in 0..<180 where !ended { ended = f.step(dt: 1.0 / 60) }
        XCTAssertTrue(ended); XCTAssertEqual(f.phase, .roaming); XCTAssertEqual(f.blend, 0, "the home camera is exactly the old camera")
    }

    func testFocusEntersOnlyViaComeHereAndLeavesOnlyViaRelease() {
        let r = FocusRun(); Self.keep.append(r)
        XCTAssertEqual(r.focus.phase, .roaming)
        r.run(20)                                                  // roaming alone never enters focus
        XCTAssertEqual(r.focus.phase, .roaming)
        r.care.release(); XCTAssertEqual(r.focus.phase, .roaming, "release does nothing outside focus")
        r.care.comeHere()
        XCTAssertEqual(r.focus.phase, .approaching)
        XCTAssertFalse(r.focus.showsDock); XCTAssertFalse(r.focus.isFocused)
        XCTAssertTrue(r.run(40) { r.focus.phase == .focused }, "he walks to the front spot and focus starts")
        XCTAssertLessThan(simd_length(r.brain.position - GameCamera.callSpot), 0.5)
        XCTAssertFalse(r.brain.autonomy, "he stays put in focus")
        XCTAssertTrue(r.focus.showsDock); XCTAssertTrue(r.focus.showsRelease)
        // nothing but the release button leaves: 30 s of time, a wave and a second Come here change nothing
        let spot = r.brain.position
        r.run(30)
        r.care.wave(); r.care.comeHere(); r.run(3)
        XCTAssertEqual(r.focus.phase, .focused)
        XCTAssertLessThan(simd_length(r.brain.position - spot), 0.15, "he does not wander in focus")
        r.care.release()
        XCTAssertEqual(r.focus.phase, .leaving); XCTAssertFalse(r.focus.isFocused, "touch play is off from the press")
        XCTAssertTrue(r.run(3) { r.focus.phase == .roaming })
        XCTAssertEqual(r.focus.blend, 0)
        XCTAssertTrue(r.brain.autonomy, "he resumes roaming")
    }

    func testReleaseDoesAHappyHopAndRoamingResumes() {
        let r = FocusRun(); Self.keep.append(r)
        r.care.comeHere()
        XCTAssertTrue(r.run(40) { r.focus.phase == .focused })
        r.run(1)
        r.care.release()
        var hopped = false
        r.run(2) { if r.brain.activity == .playing { hopped = true }; return hopped }
        XCTAssertTrue(hopped, "a little hop on release")
        r.run(60) // seconds of roaming: he wanders again
        XCTAssertTrue(r.brain.autonomy)
    }

    func testFeedFromFocusReleasesFirstThenTheTrayFlow() {
        let r = FocusRun(); Self.keep.append(r)
        r.care.comeHere()
        XCTAssertTrue(r.run(40) { r.focus.phase == .focused })
        r.care.feed("berries")
        XCTAssertEqual(r.focus.phase, .leaving, "focus ends first")
        XCTAssertFalse(r.care.trayOut, "no tray while the camera is still easing out")
        XCTAssertTrue(r.run(3) { r.focus.phase == .roaming })
        r.run(0.1)
        XCTAssertTrue(r.care.trayOut, "then the tray flow starts")
    }

    func testComeHereMidMealDropsTheTrayThenFocuses() {
        let r = FocusRun(); Self.keep.append(r)
        r.care.feed("berries")
        XCTAssertTrue(r.run(20) { r.brain.activity == .eating })
        r.care.comeHere()
        XCTAssertTrue(r.run(60) { r.focus.phase == .focused })
        XCTAssertFalse(r.care.trayOut); XCTAssertEqual(r.care.dining.phase, .absent)
    }

    func testFocusCameraFramesBobBigAndHomeIsUnchanged() {
        let aspect: Float = 440 / 956
        let home = GameCamera.camera(aspect: aspect)
        let zero = GameCamera.camera(aspect: aspect, focus: 0)
        XCTAssertEqual(home.viewProj, zero.viewProj)
        let cam = GameCamera.camera(aspect: aspect, focus: 1)
        func scr(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let q = cam.viewProj * SIMD4(p, 1); return SIMD2(q.x / q.w, q.y / q.w)
        }
        let s = GameCamera.callSpot, R = BobShape.R, H = BobShape.H
        let left = scr(SIMD3(s.x - R, 0.45 * H, s.y)), right = scr(SIMD3(s.x + R, 0.45 * H, s.y))
        let top = scr(SIMD3(s.x, H, s.y)), bot = scr(SIMD3(s.x, 0, s.y))
        let wFrac = (right.x - left.x) / 2, hFrac = (top.y - bot.y) / 2
        XCTAssertEqual(wFrac, GameCamera.focusWidthFill, accuracy: 0.05, "fills the screen width")
        XCTAssertGreaterThan(hFrac, 0.33, "about a third or more of the height")
        let midY = 0.5 - (top.y + bot.y) / 4          // 0 = screen top
        XCTAssertEqual(midY, GameCamera.focusBodyScreenY, accuracy: 0.05)
        XCTAssertGreaterThan(top.y, -0.4)                // head well inside the screen
        XCTAssertLessThan(bot.y, 0.35 + 0)               // feet stay above the dock zone (dock top is ~ -0.7)
        XCTAssertGreaterThan(bot.y, -0.45)
        // halfway blend is between the two
        let mid = GameCamera.camera(aspect: aspect, focus: 0.5)
        XCTAssertLessThan(simd_length(mid.pos - home.pos), simd_length(cam.pos - home.pos))
    }

    func testFocusTickCostIsSmall() {
        let r = FocusRun(); Self.keep.append(r)
        r.care.comeHere()
        XCTAssertTrue(r.run(40) { r.focus.phase == .focused })
        var sum = 0.0, worst = 0.0
        let n = 600
        for _ in 0..<n {
            let a = CACurrentMediaTime()
            r.care.tick(brain: r.brain, renderer: nil, dt: r.rig.sim.stepDt, sim: r.rig.sim)
            let d = (CACurrentMediaTime() - a) * 1e6
            sum += d; worst = max(worst, d)
        }
        MotionLog.write(String(format: "FOCUS perf: care.tick in focus mean %.2f us, worst %.1f us", sum / Double(n), worst))
        XCTAssertLessThan(sum / Double(n), 100)
    }
}
