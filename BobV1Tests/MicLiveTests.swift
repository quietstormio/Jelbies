import XCTest
import AVFoundation
@testable import BobV1

/// Mic-live signal: the pressed state and the duck are instant, the edge glow and the open tick wait for the first real input buffer.
@MainActor
final class MicLiveTests: XCTestCase {
    private var clock = 100.0
    private func make(failures: Int = 0, autoLive: Bool = true) -> (VoiceCoordinator, FakeSpeechInput) {
        let input = FakeSpeechInput()
        input.warmFailures = failures
        input.autoLive = autoLive
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "MicLiveTests")!, persists: false)
        return (VoiceCoordinator(training: training, input: input, now: { [unowned self] in self.clock }), input)
    }

    func testBeginIsSynchronousPressedAndDuckNowGlowAndTickWait() {
        let (v, _) = make(autoLive: false)
        var opens = 0, lives = 0
        v.mode.onOpen = { opens += 1 }          // the duck (micListening(true)) hangs off onOpen
        v.onLive = { lives += 1 }
        XCTAssertTrue(v.begin())
        XCTAssertTrue(v.isListening, "pressed state is set before begin() returns")
        XCTAssertEqual(opens, 1, "the duck fires inside the press")
        XCTAssertEqual(lives, 0, "no tick yet")
        XCTAssertFalse(v.micLive, "the glow reads micLive: it is not up before the mic is")
        v.cancel()
    }

    func testFirstBufferGoesLiveOnceAndTicksOnce() async throws {
        let (v, input) = make(autoLive: false)
        var lives = 0
        v.onLive = { lives += 1 }
        XCTAssertTrue(v.begin())
        let handler = try XCTUnwrap(input.liveHandler, "begin() armed the first-buffer signal")
        await v._startTask?.value
        XCTAssertFalse(v.micLive, "engine started but no buffer yet")
        handler(); handler()                    // two buffers' worth of signals
        XCTAssertTrue(v.micLive)
        XCTAssertEqual(lives, 1)
        XCTAssertNotNil(v.micLiveMs)
        XCTAssertTrue(v.isListening)
        v.cancel()
        XCTAssertFalse(v.micLive, "cancel clears it")
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    func testAutoLiveFakeGoesLiveRightAfterStart() async throws {
        let (v, _) = make()
        var lives = 0
        v.onLive = { lives += 1 }
        XCTAssertTrue(v.begin())
        await v._startTask?.value
        XCTAssertTrue(v.micLive)
        XCTAssertEqual(lives, 1)
        v.cancel()
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    func testReleaseBeforeFirstBufferNeverGoesLive() async throws {
        let (v, input) = make(autoLive: false)
        var lives = 0
        v.onLive = { lives += 1 }
        XCTAssertTrue(v.begin())
        let handler = try XCTUnwrap(input.liveHandler)
        clock += 0.1
        v.release()
        XCTAssertFalse(v.isListening)
        XCTAssertFalse(v.micLive)
        handler()                                // a late buffer from the abandoned press
        XCTAssertFalse(v.micLive, "no stuck glow")
        XCTAssertEqual(lives, 0, "no tick")
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertFalse(v.micLive, "the watchdog of the dead press does not fire either")
        XCTAssertEqual(lives, 0)
    }

    func testOldPressSignalDoesNotLeakIntoTheNextPress() async throws {
        let (v, input) = make(autoLive: false)
        var lives = 0
        v.onLive = { lives += 1 }
        XCTAssertTrue(v.begin())
        let old = try XCTUnwrap(input.liveHandler)
        await v._startTask?.value
        v.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        clock += 1
        XCTAssertTrue(v.begin())
        old()
        XCTAssertFalse(v.micLive, "a signal armed for the previous press is ignored")
        XCTAssertEqual(lives, 0)
        v.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testNoBufferFor1_2sFallsBackOnceTheEngineIsRunning() async throws {
        let (v, _) = make(autoLive: false)
        var lives = 0
        v.onLive = { lives += 1 }
        XCTAssertTrue(v.begin())
        await v._startTask?.value
        XCTAssertFalse(v.micLive)
        try await Task.sleep(nanoseconds: UInt64((VoiceCoordinator.liveWatchSeconds + 0.3) * 1e9))
        XCTAssertTrue(v.micLive, "a running engine is never left without its glow")
        XCTAssertEqual(lives, 1)
        v.cancel()
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    func testFailedStartKeepsTodaysRecoveryAndNeverGoesLive() async throws {
        let (v, _) = make(failures: 2, autoLive: false)
        var lives = 0
        v.onLive = { lives += 1 }
        XCTAssertTrue(v.begin())
        await v._startTask?.value
        XCTAssertFalse(v.isListening, "both attempts failed: today's cancel path ran")
        XCTAssertFalse(v.micLive)
        try await Task.sleep(nanoseconds: UInt64((VoiceCoordinator.liveWatchSeconds + 0.3) * 1e9))
        XCTAssertFalse(v.micLive)
        XCTAssertEqual(lives, 0)
    }

    // MARK: put-back (quick re-press)

    func testQueuedPutBackIsSkippedByANewPress() {
        let g = PutBackGate()
        let gen = g.enqueue()
        XCTAssertEqual(g.voidQueued(), 1, "one put-back was still queued")
        XCTAssertFalse(g.shouldRun(gen), "it is skipped: the session is not bounced to .ambient")
        XCTAssertEqual(g.skippedTotal, 1)
        XCTAssertEqual(g.pendingCount, 0)
    }

    func testPutBackThatAlreadyRanOrIsNewerStillRuns() {
        let g = PutBackGate()
        XCTAssertEqual(g.voidQueued(), 0, "nothing queued: nothing to void")
        let a = g.enqueue()
        XCTAssertTrue(g.shouldRun(a), "a put-back with no press in front of it runs")
        let b = g.enqueue()
        _ = g.voidQueued()
        let c = g.enqueue()                         // the release of that next press
        XCTAssertFalse(g.shouldRun(b))
        XCTAssertTrue(g.shouldRun(c), "the release after the re-press still puts the session back")
        XCTAssertEqual(g.skippedTotal, 1)
    }

    // MARK: warm path

    func testWarmDecision() {
        XCTAssertTrue(DictationSpeechInput.shouldWarm(availability: .ready, permissionGranted: { false }))
        XCTAssertTrue(DictationSpeechInput.shouldWarm(availability: .unknown, permissionGranted: { true }), "unknown + granted: warm")
        var asked = 0
        XCTAssertFalse(DictationSpeechInput.shouldWarm(availability: .unknown, permissionGranted: { asked += 1; return false }))
        XCTAssertEqual(asked, 1, "the permission is only READ")
        XCTAssertFalse(DictationSpeechInput.shouldWarm(availability: .denied, permissionGranted: { true }))
        XCTAssertFalse(DictationSpeechInput.shouldWarm(availability: .unavailable(reason: "x"), permissionGranted: { true }))
        XCTAssertFalse(DictationSpeechInput.shouldWarm(availability: .needsDownload(progress: 0.2), permissionGranted: { true }))
    }

    func testUndeterminedPermissionWarmDoesNotStartAnything() {
        let saved = DictationSpeechInput.recordPermissionGranted
        defer { DictationSpeechInput.recordPermissionGranted = saved }
        DictationSpeechInput.recordPermissionGranted = { false }
        let d = DictationSpeechInput()
        d.warmUp()
        XCTAssertEqual(d.warmMakes, 0, "no warm-up, no permission prompt: the press flow is unchanged")
        XCTAssertEqual(d.availability, .unknown)
    }

    func testPipeFirstBufferSignalFiresOncePerArm() {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        final class Counter: @unchecked Sendable { let lock = NSLock(); private var n = 0
            func bump() { lock.lock(); n += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return n } }
        let counter = Counter()
        let pipe = AudioPipe(format: fmt, onFirstBuffer: { counter.bump() })
        func buf() -> AVAudioPCMBuffer { let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1600)!; b.frameLength = 1600; return b }
        pipe.handle(buf())
        XCTAssertEqual(counter.value, 0, "not armed: a pre-warm buffer is not a press's proof")
        pipe.arm()
        pipe.handle(buf()); pipe.handle(buf())
        XCTAssertEqual(counter.value, 1)
        pipe.arm()
        pipe.handle(buf())
        XCTAssertEqual(counter.value, 2)
    }
}
