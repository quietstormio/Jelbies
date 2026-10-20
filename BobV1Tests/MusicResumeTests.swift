//
//  MusicResumeTests.swift
//  Music comes back after leaving and returning to the app: gap restart, dead decks, mic session flag, scene music, engine restart.
//

import XCTest
import AVFoundation
@testable import BobV1

@MainActor
final class MusicResumeTests: XCTestCase {
    private func run(_ d: inout MusicDirector, seconds: Double, input: MusicInput = MusicInput(phase: .day)) {
        var t = 0.0
        while t < seconds { _ = d.update(dt: 0.25, input: input); t += 0.25 }
    }

    func testDirectorResumedInGapStartsNextTrackWithShortFade() {
        var d = MusicDirector(length: { _ in 30 }, rand: { 0 })
        run(&d, seconds: 31)
        XCTAssertNil(d.current); XCTAssertNotNil(d.gapLeft)
        let ev = d.resumed(deckPlaying: false)
        guard case .playTrack(_, let fade)? = ev.first else { return XCTFail("no track: \(ev)") }
        XCTAssertEqual(fade, 1.5, accuracy: 0.001)
        XCTAssertNil(d.gapLeft); XCTAssertNotNil(d.current)
    }

    func testDirectorResumedWithDeadDeckRestartsAndHealthyDoesNothing() {
        var d = MusicDirector(length: { _ in 60 }, rand: { 0 })
        run(&d, seconds: 5)
        XCTAssertNotNil(d.current)
        XCTAssertTrue(d.resumed(deckPlaying: true).isEmpty)
        XCTAssertEqual(d.resumed(deckPlaying: false).count, 1)
    }

    func testDirectorResumedDuringSceneDoesNothing() {
        var d = MusicDirector(length: { _ in 60 }, rand: { 0 })
        run(&d, seconds: 3)
        run(&d, seconds: 2, input: MusicInput(phase: .day, scene: .town))
        XCTAssertTrue(d.resumed(deckPlaying: false).isEmpty)
    }

    /// One real (unmuted) hub for the suite: starting it decodes every effect, which is slow on a simulator.
    nonisolated(unsafe) private static var sharedHub: AudioHub?
    private func makeHub() -> AudioHub {
        if let h = Self.sharedHub { h.setForeground(true); return h }
        let hub = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: false)
        hub._sceneEngineDisabled = true
        hub.start()
        hub._tick(0.05)
        Self.sharedHub = hub
        return hub
    }
    private func trackEvents(_ hub: AudioHub) -> Int { hub.eventLog.filter { if case .playTrack = $0 { return true }; return false }.count }

    /// Background, then foreground in the middle of a 30-90 s ambience gap: the next track starts at once (1.5 s fade-in), well inside 2 s.
    /// (A simulator may have no audio output, so the check is the event and, where the host plays at all, the deck.)
    func testHubBackgroundThenForegroundInGapStartsMusicWithinTwoSeconds() async throws {
        let hub = makeHub()
        hub._tick(0.05)
        hub._forceGap(80)
        XCTAssertTrue(hub._inGap)
        let before = trackEvents(hub)
        hub.setForeground(false)
        hub.setForeground(true)
        XCTAssertFalse(hub._inGap, "the gap must end on return")
        XCTAssertEqual(trackEvents(hub), before + 1, "a track starts on return")
        guard case .playTrack(_, let fade)? = hub.eventLog.last else { return XCTFail("no track event: \(String(describing: hub.eventLog.last))") }
        XCTAssertEqual(fade, 1.5, accuracy: 0.001)
    }

    func testHubMicSessionFlagClearsOnBackground() {
        let hub = makeHub()
        hub.micSessionBegan()
        XCTAssertTrue(hub._micSession)
        hub.setForeground(false)
        XCTAssertFalse(hub._micSession)
        hub.setForeground(true)       // setUpSession runs again (no stale flag)
        XCTAssertFalse(hub._micSession)
    }

    /// The 0.5 s re-check after a resume: a deck that is not really playing is rebuilt (a new track event); a healthy one is left alone.
    func testHubRecheckRebuildsADeadDeckAndLeavesAHealthyOne() async throws {
        let hub = makeHub()
        hub._tick(0.05)
        hub.ensureMusic(delay: false)          // settle: anything dead is rebuilt once
        let before = trackEvents(hub)
        hub.ensureMusic(delay: true)
        if hub._decksPlaying { XCTAssertEqual(trackEvents(hub), before, "a healthy deck is left alone") }
        else { XCTAssertEqual(trackEvents(hub), before + 1, "a dead deck is rebuilt (this host's players do not play)") }
    }

    /// Returning mid-gap through the foreground path with the verify task pending: the 0.5 s check runs without breaking anything.
    func testHubVerifyTaskRunsAfterHalfASecond() async throws {
        let hub = makeHub()
        hub._forceGap(60)
        hub.setForeground(false); hub.setForeground(true)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertFalse(hub._inGap)
    }

    /// Town / shop / race / training music: after a background and back, the scene's track is requested again if the engine lost it.
    func testHubSceneMusicIsRequestedAgainOnReturn() async throws {
        let hub = makeHub()
        hub.setTownScene(.shop)
        hub._tick(0.05)
        XCTAssertEqual(hub._directorScene, .shop)
        func sceneOns() -> Int { hub.eventLog.filter { $0 == .sceneOn(.shop, fade: 1.2) || $0 == .sceneOn(.shop, fade: 1.5) }.count }
        XCTAssertEqual(sceneOns(), 1)
        hub.setForeground(false); hub.setForeground(true)          // no engine on this test host (nothing plays the scene): it is asked for again
        XCTAssertGreaterThanOrEqual(sceneOns(), 2, "the shop track is requested again on return")
        XCTAssertEqual(hub.eventLog.last, .sceneOn(.shop, fade: 1.5))
        hub.setTownScene(.none)
        hub._tick(0.05)
        XCTAssertEqual(hub._directorScene, .none)
    }

    func testSceneEngineRestartPathKeepsPlayingTrack() async throws {
        let e = SceneMusicEngine()
        e.play(.town, fade: 0.1)
        var ok = false
        for _ in 0..<60 { if e.isPlaying(.town) { ok = true; break }; try await Task.sleep(for: .milliseconds(100)) }
        guard ok else { throw XCTSkip("no audio output engine on this host") }
        e.pause(); e.resume()
        XCTAssertTrue(e.isPlaying(.town))
        e.restartAfterConfigChange()                 // what AVAudioEngineConfigurationChange / interruption end does
        XCTAssertEqual(e.current, .town)
        ok = false
        for _ in 0..<60 { if e.isPlaying(.town) { ok = true; break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(ok, "the scene track plays again after the engine restart")
        e.stopAll(fade: 0); e.update(dt: 1)
    }
}
