import XCTest
@testable import BobV1

/// Mic-lag fix: the listening state, the open tick and the live-level feedback are synchronous with the press.
@MainActor
final class VoiceLatencyTests: XCTestCase {
    private func make() -> (VoiceCoordinator, FakeSpeechInput) {
        let input = FakeSpeechInput()
        return (VoiceCoordinator(training: VoiceTraining(defaults: UserDefaults(suiteName: "VoiceLatencyTests")!, persists: false), input: input), input)
    }

    func testBeginIsSynchronousAndTicksOnTheSameFrame() {
        let (v, input) = make()
        var ticks = 0
        v.mode.onOpen = { ticks += 1 }
        let t0 = CACurrentMediaTime()
        XCTAssertTrue(v.begin())
        let dt = (CACurrentMediaTime() - t0) * 1000
        XCTAssertTrue(v.isListening, "listening state is set before begin() returns")
        XCTAssertEqual(ticks, 1, "the open haptic fires inside the press")
        XCTAssertLessThan(dt, 50, "begin() returns within the one-frame budget (\(dt) ms)")
        XCTAssertFalse(input.isStarted, "the real start runs behind the UI, not inside the press")
        v.cancel()
    }

    func testAudioStartsBehindAndLevelDrivesVisuals() async throws {
        let (v, input) = make()
        XCTAssertTrue(v.begin())
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(input.isStarted, "audio running shortly after")
        XCTAssertNotNil(v.audioLatencyMs)
        XCTAssertGreaterThan(v.level, 0, "the fake mic's synthetic level reaches the glow / bars / halo")
        v.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testFailedStartKeepsListeningUI() async throws {
        let (v, _) = make()
        XCTAssertTrue(v.begin())
        XCTAssertTrue(v.isListening)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(v.isListening, "no flicker while the start is in flight")
        v.cancel()
    }
}
