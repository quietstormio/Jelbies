import XCTest
@testable import BobV1

/// The double-tap-hold must open on the FIRST try even when the speculative warm-up (first tap) failed.
@MainActor
final class VoiceFirstTryTests: XCTestCase {
    private var clock = 100.0
    private func make(failures: Int) -> (VoiceCoordinator, FakeSpeechInput) {
        let input = FakeSpeechInput()
        input.warmFailures = failures
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "VoiceFirstTryTests")!, persists: false)
        return (VoiceCoordinator(training: training, input: input, now: { [unowned self] in self.clock }), input)
    }

    func testOpensOnFirstTryAfterFailedWarmUp() async throws {
        let (v, input) = make(failures: 1)
        input.nextTranscript = "sit"
        v.warmUp()                                        // first tap
        try await Task.sleep(nanoseconds: 50_000_000)     // the failed warm-up settles
        XCTAssertTrue(v.begin())                          // second down
        await v._startTask?.value
        XCTAssertTrue(input.isStarted, "the retry brought the mic up inside the same press")
        XCTAssertTrue(v.isListening)
        XCTAssertEqual(v.openCount, 1)
        clock += 0.6
        v.release()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(input.isStarted)
    }

    func testTwoCleanGesturesBothOpen() async throws {
        let (v, input) = make(failures: 0)
        for n in 1...2 {
            v.warmUp()
            XCTAssertTrue(v.begin())
            await v._startTask?.value
            XCTAssertTrue(input.isStarted)
            clock += 0.6
            v.release()
            try await Task.sleep(nanoseconds: 800_000_000)
            XCTAssertEqual(v.openCount, n)
        }
    }
}
