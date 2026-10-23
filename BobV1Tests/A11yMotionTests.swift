//
//  A11yMotionTests.swift
//  Reduce Motion for the camera (a crossfade, never a swoop; the jelly physics is untouched) and the sound captions.
//

import XCTest
@testable import BobV1

@MainActor
final class A11yMotionTests: XCTestCase {
    override func setUp() {
        A11ySettings.shared.reduceMotionInApp = false; A11ySettings.shared.systemReduceMotion = false
        A11ySettings.shared.captions = false; CaptionCenter.shared.clear(); MotionVeil.shared.reset()
    }
    override func tearDown() {
        A11ySettings.shared.reduceMotionInApp = false; A11ySettings.shared.systemReduceMotion = false
        A11ySettings.shared.captions = false; CaptionCenter.shared.clear(); MotionVeil.shared.reset()
    }

    // MARK: the camera

    func testReduceMotionSnapsTheCloseUpUnderAVeil() {
        A11ySettings.shared.reduceMotionInApp = true
        let f = BlobFocus()
        f.beginApproach(); f.arrive()
        var peak = 0.0, t: Float = 0
        while f.blend < 0.999, t < 1 { f.step(dt: 1 / 60); t += 1 / 60; peak = max(peak, MotionVeil.shared.opacity) }
        XCTAssertEqual(f.blend, 1, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(t, 0.3, "the camera is there within one veil period")
        XCTAssertEqual(peak, 1, accuracy: 1e-6, "the screen was fully veiled while it snapped")
        XCTAssertTrue(f.assistPeaked)
        for _ in 0..<30 { f.step(dt: 1 / 60) }
        XCTAssertEqual(MotionVeil.shared.opacity, 0, accuracy: 1e-6, "and the veil fades back out")
        // and back out
        f.release()
        var done = false, n = 0
        while !done, n < 60 { done = f.step(dt: 1 / 60); n += 1 }
        XCTAssertTrue(done, "leaving ends too"); XCTAssertEqual(f.phase, .roaming); XCTAssertEqual(f.blend, 0, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(Float(n) / 60, 0.3)
    }

    func testTheSystemSettingAloneAlsoReducesMotion() {
        A11ySettings.shared.systemReduceMotion = true
        XCTAssertTrue(A11ySettings.shared.reduceMotion)
        let f = BlobFocus(); f.beginApproach(); f.arrive()
        for _ in 0..<20 { f.step(dt: 1 / 60) }
        XCTAssertEqual(f.blend, 1, accuracy: 1e-6)
    }

    func testWithoutReduceMotionTheSpringIsUnchanged() {
        let f = BlobFocus(); f.beginApproach(); f.arrive()
        f.step(dt: 1 / 60)
        XCTAssertLessThan(f.blend, 0.2, "the spring starts gently")
        XCTAssertEqual(MotionVeil.shared.opacity, 0)
        // the same numbers as the original spring (semi-implicit Euler, omega 9, zeta 0.9)
        var x: Float = 0, v: Float = 0
        let w = BlobFocus.omega, z = BlobFocus.zeta
        let g = BlobFocus(); g.beginApproach(); g.arrive()
        for _ in 0..<45 {
            let h: Float = 1 / 60
            v += (w * w * (1 - x) - 2 * z * w * v) * h; x += v * h
            g.step(dt: h)
        }
        XCTAssertEqual(g.blend, x, accuracy: 1e-5)
        XCTAssertFalse(g.assistPeaked)
    }

    func testBlendAssistStateMachine() {
        var a = CameraBlendAssist()
        var blend: Float = 0, vel: Float = 0
        XCTAssertFalse(a.step(blend: &blend, vel: &vel, goal: 1, dt: 1 / 60, reduce: false), "off: the caller's spring runs")
        var steps = 0
        while a.step(blend: &blend, vel: &vel, goal: 1, dt: 1 / 60, reduce: true), a.stage != .idle || steps == 0 { steps += 1; if steps > 100 { break } }
        XCTAssertEqual(blend, 1); XCTAssertEqual(a.veil, 0, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(Float(steps) / 60, 0.3)
        // a mid-fade switch to "off" clears the veil
        var b = CameraBlendAssist(); var bl: Float = 0, v: Float = 0
        _ = b.step(blend: &bl, vel: &v, goal: 1, dt: 1 / 60, reduce: true)
        XCTAssertFalse(b.step(blend: &bl, vel: &v, goal: 1, dt: 1 / 60, reduce: false))
        XCTAssertEqual(b.veil, 0)
    }

    // MARK: captions

    func testEverySoundHasACaptionOrIsDeliberatelySilent() {
        for s in SFX.allCases {
            let t = SoundCaptions.text(s)
            switch s {
            case .uitap, .uiconfirm, .select, .footstep, .tick, .goodStep, .pageTurn, .shoeOn, .wobble, .zoomies, .setdown, .bubblepop:
                XCTAssertNil(t, "\(s) is not captioned")
            default: XCTAssertNotNil(t, "\(s) has a caption")
            }
        }
        XCTAssertEqual(SoundCaptions.text(.squish), "Squish")
        XCTAssertEqual(SoundCaptions.text(.letgo), "Boing")
        XCTAssertEqual(SoundCaptions.text(.lintroller), "Roll roll")
        XCTAssertEqual(SoundCaptions.voice(.happy, name: "Pip"), "Pip chirps")
        XCTAssertEqual(SoundCaptions.voice(.sad, name: "Moss"), "Moss whimpers")
    }

    func testChirpReachesTheCaptionCenterOnlyWhenCaptionsAreOn() {
        AudioHub.shared.chirp(jelly: 0, .happy)
        XCTAssertTrue(CaptionCenter.shared.items.isEmpty, "captions off: nothing")
        A11ySettings.shared.captions = true
        AudioHub.shared.chirp(jelly: 0, .happy)
        XCTAssertEqual(CaptionCenter.shared.items.map(\.text), ["Bob chirps"], "even though the test host has no audio running")
        AudioHub.shared.play(.squish)
        AudioHub.shared.play(.uitap)
        XCTAssertEqual(CaptionCenter.shared.items.map(\.text), ["Bob chirps", "Squish"], "UI taps are never captioned")
    }

    func testTheSameSoundRefreshesInsteadOfStacking() {
        A11ySettings.shared.captions = true
        let c = CaptionCenter.shared
        c.post("Squish"); c.post("Boing"); c.post("Squish")
        XCTAssertEqual(c.items.map(\.text), ["Boing", "Squish"])
        c.post("a"); c.post("b")
        XCTAssertEqual(c.items.count, CaptionCenter.maxShown)
    }
}
