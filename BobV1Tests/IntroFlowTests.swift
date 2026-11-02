//
//  IntroFlowTests.swift
//  The launch intro: plays the whole clip with no tap, holds the last frame (paused), fades to the menu, tears the player down; a skip jumps to the held last frame
//  (and waits, at most 2.5 s, for the preloads); foregrounding never replays it; rotating swaps the variant at the same timestamp; the preloads run while it plays.
//

import XCTest
import AVFoundation
@testable import BobV1

@MainActor
final class IntroFlowTests: XCTestCase {
    private func make(hold: Double = 0.2, fade: Double = 0.3) -> IntroFlow {
        let f = IntroFlow(onFadeBegins: {})
        f.holdSeconds = hold; f.fadeSeconds = fade
        return f
    }
    private func expect(_ timeout: Double, _ msg: String, _ cond: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let ok = await wait(timeout, cond)
        XCTAssertTrue(ok, msg, file: file, line: line)
    }
    private func wait(_ timeout: Double, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(nanoseconds: 20_000_000) }
        return cond()
    }

    /// Whole clip, no interaction: loading -> playing -> holding -> fading -> gone; played exactly once; player released; warm-ups finished before the clip ended.
    func testFullPlayThenHoldFadeAndTeardownWithPreloadsDuringPlayback() async throws {
        IntroWarmup.begin(forTests: true)          // what IntroView.onAppear does
        var fades = 0
        let f = IntroFlow(onFadeBegins: { fades += 1 }); f.holdSeconds = 0.2; f.fadeSeconds = 0.3
        f.start(landscape: false)
        let ok = await wait(20) { f.stage == .gone }
        XCTAssertTrue(ok, "never reached gone: \(f.stageLog)")
        XCTAssertEqual(f.stageLog.map(\.rawValue), ["loading", "playing", "holding", "fading", "gone"])
        XCTAssertEqual(f.playCalls, 1)
        XCTAssertEqual(fades, 1)
        XCTAssertNil(f.player, "the AVPlayer is released after the fade")
        // the preloads ran during playback (marks are seconds since the first mark)
        let ready = try XCTUnwrap(LaunchTiming.time(of: "intro: clip ready")), end = try XCTUnwrap(LaunchTiming.time(of: "intro: clip end"))
        XCTAssertGreaterThan(end - ready, 6, "the whole ~7.9 s clip played")
        for m in ["warm-up starts", "warm-up: pipelines done", "warm-up: meshes done", "warm-up: sounds done", "warm-up: bodies done"] {
            let t = try XCTUnwrap(LaunchTiming.time(of: m), m)
            XCTAssertLessThan(t, end, "\(m) must finish while the clip is still playing")
            XCTAssertGreaterThan(t, ready - 0.5, m)
        }
        XCTAssertTrue(IntroWarmup.isFinished)
        XCTAssertGreaterThanOrEqual(ActorPrebuild.count, 1)
        // order of the end sequence
        let fb = try XCTUnwrap(LaunchTiming.time(of: "intro: fade begins")), td = try XCTUnwrap(LaunchTiming.time(of: "intro: torn down"))
        XCTAssertLessThan(end, fb); XCTAssertLessThan(fb, td)
        // foregrounding afterwards brings nothing back
        f.sceneActive()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(f.stage, .gone); XCTAssertNil(f.player); XCTAssertEqual(f.playCalls, 1)
    }

    /// During the hold and the fade the clip is paused on its last frame; foregrounding there does not move it.
    func testHoldIsPausedOnTheLastFrameAndForegroundingDoesNotReplay() async throws {
        let f = make(hold: 1.0, fade: 1.0)
        f.start(landscape: false)
        await expect(5, "timed out") { f.stage == .playing }
        f.tap()
        await expect(3, "timed out") { f.stage == .holding }
        let p = try XCTUnwrap(f.player), dur = try XCTUnwrap(p.currentItem).duration.seconds
        XCTAssertEqual(p.rate, 0)
        let t0 = p.currentTime().seconds
        XCTAssertGreaterThan(t0, dur - 0.1, "paused on the final frame")
        f.sceneActive(); f.sceneActive()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(p.rate, 0); XCTAssertEqual(p.currentTime().seconds, t0, accuracy: 0.001)
        await expect(3, "timed out") { f.stage == .fading }
        f.sceneActive()
        XCTAssertEqual(p.rate, 0)
        await expect(3, "timed out") { f.stage == .gone }
        XCTAssertNil(f.player); XCTAssertEqual(f.playCalls, 1)
    }

    /// A skip jumps to the last frame (no replay) and then holds -> fades -> tears down.
    func testSkipJumpsToFinalFrameThenFades() async throws {
        let f = make()
        f.start(landscape: false)
        await expect(5, "timed out") { f.stage == .playing }
        await expect(3, "the Skip pill shows ~1 s in") { f.skipVisible }
        f.tap()
        await expect(3, "timed out") { f.stage != .playing }
        XCTAssertFalse(f.skipVisible)
        await expect(5, "timed out") { f.stage == .gone }
        XCTAssertEqual(f.stageLog.map(\.rawValue), ["loading", "playing", "holding", "fading", "gone"])
        XCTAssertEqual(f.playCalls, 1); XCTAssertNil(f.player)
        f.tap()          // a late tap is ignored
        XCTAssertEqual(f.stage, .gone)
    }

    /// A skip before the preloads finish holds the last frame until they do (capped at 2.5 s).
    func testSkipWaitsForPreloadsWithACap() async throws {
        IntroWarmup._simulatePending(true)
        var released = false
        defer { if !released { IntroWarmup._simulatePending(false) } }
        let f = make(hold: 0.1, fade: 0.2)
        f.start(landscape: false)
        await expect(5, "timed out") { f.stage == .playing }
        f.tap()
        await expect(3, "timed out") { f.stage == .holding }
        let t0 = Date()
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(f.stage, .holding, "still holding the last frame while a preload runs")
        IntroWarmup._simulatePending(false); released = true
        await expect(2, "timed out") { f.stage == .fading || f.stage == .gone }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2.5, "released early: fades soon after the loads finish")
        await expect(3, "timed out") { f.stage == .gone }

        // never finishing: the cap (2.5 s) ends the wait
        IntroWarmup._simulatePending(true); released = false
        let g = make(hold: 0.1, fade: 0.2)
        g.start(landscape: false)
        await expect(5, "timed out") { g.stage == .playing }
        g.tap()
        await expect(3, "timed out") { g.stage == .holding }
        let t1 = Date()
        await expect(5, "timed out") { g.stage == .fading || g.stage == .gone }
        let waited = Date().timeIntervalSince(t1)
        XCTAssertGreaterThan(waited, 2.0); XCTAssertLessThan(waited, 3.6)
    }

    /// Rotating while it plays swaps the other variant in at the same timestamp and keeps playing.
    func testRotationSwapsVariantAtTheSameTimestamp() async throws {
        let f = make()
        f.start(landscape: false)
        await expect(5, "timed out") { f.stage == .playing }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let before = try XCTUnwrap(f.player).currentTime().seconds
        f.rotated(landscape: true)
        XCTAssertEqual(f.variantSwaps, 1)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let p = try XCTUnwrap(f.player)
        XCTAssertGreaterThan(p.currentTime().seconds, before, "continues from where it was")
        XCTAssertLessThan(p.currentTime().seconds, before + 2.5)
        XCTAssertGreaterThan(p.rate, 0)
        XCTAssertEqual(f.stage, .playing)
        f.teardown()
        XCTAssertNil(f.player)
    }
}
