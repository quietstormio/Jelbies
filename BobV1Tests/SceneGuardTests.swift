//
//  SceneGuardTests.swift
//  show-perfect-r1: the scene music guard (AudioHub.sceneGuardTick) and the on-device ring log (JLog).
//  Fault injection on a REAL scene engine (the Jelly Show's stage music): the engine is stopped under the voice, a route change is posted, an interruption begins and ends (shouldResume or not);
//  each time the music must be playing again within 2 s, with exactly one voice (never stacked). A host with no audio output skips the engine tests.
//

import XCTest
import AVFoundation
@testable import BobV1

@MainActor
final class SceneGuardTests: XCTestCase {
    nonisolated(unsafe) private static var hub: AudioHub?
    private func makeHub() async throws -> AudioHub {
        if let h = Self.hub { return h }
        let h = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: false)
        h.start()
        Self.hub = h
        h.situation(napping: [], playing: false, xs: [], moods: [], scene: .show)
        let ok = await waitHealthy(h, within: 12)
        try XCTSkipUnless(ok != nil, "this host cannot run the scene engine (no audio output)")
        return h
    }
    /// Seconds until the stage voice is healthy (nil = never within `within`). Real time: the hub's own 30 Hz timer runs the guard.
    private func waitHealthy(_ h: AudioHub, within: Double) async -> Double? {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < within {
            if h._guardHealth(.contestStage) == .healthy { return Date().timeIntervalSince(t0) }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return nil
    }
    private func healthyAgain(_ h: AudioHub, _ what: String, within: Double = 2.0, file: StaticString = #filePath, line: UInt = #line) async {
        // let the fault be seen first (a stopped engine reads stalled at once; a route change alone reads healthy)
        let t = await waitHealthy(h, within: within)
        XCTAssertNotNil(t, "\(what): the music is not back within \(within) s (health \(String(describing: h._guardHealth(.contestStage))), guard: \(h.guardLast))", file: file, line: line)
        XCTAssertEqual(h._sceneVoiceCount, 1, "\(what): exactly one scene voice (never stacked)", file: file, line: line)
        try? await Task.sleep(for: .milliseconds(700))          // (the fade-in)
        let peak = await h._scenePeak(0.6)
        XCTAssertGreaterThan(peak, 0.001, "\(what): the recovered music is really AUDIBLE on the mixer (peak \(peak)), not just flagged as playing", file: file, line: line)
    }

    func testEngineStoppedUnderTheVoiceIsRebuilt() async throws {
        let h = try await makeHub()
        let before = h.guardRestarts
        h._injectEngineStop()
        XCTAssertNotEqual(h._guardHealth(.contestStage), .healthy)
        await healthyAgain(h, "engine stop")
        XCTAssertGreaterThan(h.guardRestarts, before, "the guard did it")
    }
    func testRouteChangeAfterTheEngineStoppedIsRebuilt() async throws {
        let h = try await makeHub()
        h._injectEngineStop()
        h._simulateRouteChange(reason: .oldDeviceUnavailable)          // headphones out
        await healthyAgain(h, "route change (old device unavailable)")
        h._injectEngineStop()
        h._simulateRouteChange(reason: .newDeviceAvailable)            // headphones / Bluetooth in
        await healthyAgain(h, "route change (new device available)")
    }
    func testRouteChangeAloneKeepsOneHealthyVoice() async throws {
        let h = try await makeHub()
        h._simulateRouteChange(reason: .categoryChange)
        try? await Task.sleep(for: .milliseconds(1800))
        await healthyAgain(h, "route change alone")
    }
    func testInterruptionBeganAndEndedShouldResumeOrNot() async throws {
        let h = try await makeHub()
        for shouldResume in [true, false] {
            h._simulateInterruption(began: true, shouldResume: false)
            h._injectEngineStop()                                    // (what a real interruption does to the engine)
            try? await Task.sleep(for: .milliseconds(300))
            h._simulateInterruption(began: false, shouldResume: shouldResume)
            await healthyAgain(h, "interruption ended shouldResume=\(shouldResume)")
        }
    }
    func testMediaServicesResetBuildsANewEngine() async throws {
        let h = try await makeHub()
        h._injectMediaServicesReset()
        await healthyAgain(h, "media services reset", within: 3)
    }
    func testVoiceCategoryChangedAndNotRestoredIsPutBack() async throws {
        let h = try await makeHub()
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])          // (the voice input changed it and never put it back)
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 3, s.category != .ambient { try? await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(s.category, .ambient, "the guard put the category back")
        await healthyAgain(h, "category put back", within: 4)
    }

    // MARK: the ring log

    func testRingLogKeepsTheLastTwoThousandLines() throws {
        let path = NSTemporaryDirectory() + "jlog-test-\(UUID().uuidString).txt"
        JLog.redirect(to: path)
        defer { JLog.redirect(to: nil); try? FileManager.default.removeItem(atPath: path) }
        for i in 0..<(JLog.keep + 900) { JLog.show("line \(i)") }
        JLog.flush()
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertLessThanOrEqual(lines.count, JLog.keep + 400, "never grows without a bound")
        XCTAssertGreaterThanOrEqual(lines.count, JLog.keep, "the last 2000 are kept")
        XCTAssertTrue(lines.last!.hasSuffix("[show] line \(JLog.keep + 899)"), "the newest line is last: \(lines.last!)")
        XCTAssertFalse(text.contains("[show] line 0\n"), "the oldest are dropped")
    }
}
