import XCTest
@testable import BobV1

/// A press made while the previous command is still finishing (the 0.4 s post-roll, then the analyzer finalize) opens at once;
/// the previous command is still acted on, in order, and no engine is left running afterwards.
@MainActor
final class MicTailTests: XCTestCase {
    private final class Clock { var t = 100.0 }

    /// A speech input with a real post-roll and finalize delay, the same contract as `DictationSpeechInput`
    /// (`willStop` / `cutPostRoll`; a `start` during the teardown waits for it).
    @MainActor
    private final class TailInput: SpeechInput {
        var availability: VoiceAvailability = .ready
        var onLevel: ((Float) -> Void)?
        var postRoll = 0.4, finalizeDelay = 0.3
        var transcripts: [String] = []
        private(set) var running = false
        private(set) var events: [String] = []
        private var roll: Task<Void, Never>?
        private var settling = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func prepare(contextualWords: [String]) async {}
        func willStop() { settling = true }
        private var cut = false
        func cutPostRoll() { if settling { cut = true }; roll?.cancel() }
        private func endSettle() { settling = false; let w = waiters; waiters = []; for c in w { c.resume() } }
        func start(contextualWords: [String]) async throws {
            while settling { await withCheckedContinuation { waiters.append($0) } }
            guard !running else { events.append("start-REFUSED"); throw SpeechInputError.alreadyRunning }
            running = true; events.append("start")
        }
        func stop() async -> String {
            guard running else { endSettle(); return "" }
            if !cut {
                let t = Task<Void, Never> { _ = try? await Task.sleep(nanoseconds: UInt64(postRoll * 1e9)) }
                roll = t; await t.value; roll = nil
            }
            cut = false
            running = false; events.append("engineStopped"); endSettle()
            try? await Task.sleep(nanoseconds: UInt64(finalizeDelay * 1e9))
            return transcripts.isEmpty ? "" : transcripts.removeFirst()
        }
    }

    private func make() -> (VoiceCoordinator, TailInput, Clock) {
        let c = Clock(); let input = TailInput()
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "MicTailTests")!, persists: false)
        training.debugLearn(.sit, word: "sit"); training.debugLearn(.spin, word: "spin")
        let care = GameCare(voice: VoiceCoordinator(training: training, input: input, now: { c.t }))
        _keep.append(care)
        return (care.voice, input, c)
    }
    nonisolated(unsafe) private var _keep: [AnyObject] = []

    private func hold(_ v: VoiceCoordinator, _ c: Clock) async throws {
        XCTAssertTrue(v.begin(), "the press opens")
        await v._startTask?.value
        c.t += 0.5
    }

    func testPressDuringPostRollOpensAtOnceAndBothCommandsAreActedOn() async throws {
        let (v, input, c) = make()
        input.transcripts = ["sit", "spin"]
        try await hold(v, c)
        v.release()
        XCTAssertFalse(v.isListening, "the listen ended at the release")
        let t0 = CACurrentMediaTime()
        XCTAssertTrue(v.begin(), "a press during the post-roll is NOT dropped")
        XCTAssertTrue(v.isListening)
        await v._startTask?.value
        XCTAssertLessThan(CACurrentMediaTime() - t0, 0.3, "the post-roll was cut short, the new engine did not wait the whole 0.4 s")
        XCTAssertEqual(input.events, ["start", "engineStopped", "start"], "the old engine was stopped before the new one started")
        XCTAssertTrue(input.running)
        c.t += 0.5
        v.release()
        await v._settleTail()
        XCTAssertEqual(v.heard?.text, "\u{201C}spin\u{201D}", "the second command is acted on last")
        XCTAssertFalse(input.running, "no engine left running after release + post-roll")
        XCTAssertFalse(input.events.contains("start-REFUSED"))
    }

    func testPressDuringFinalizeOpensAndThePreviousResultIsStillActedOn() async throws {
        let (v, input, c) = make()
        input.transcripts = ["sit", "spin"]
        try await hold(v, c)
        v.release()
        while !input.events.contains("engineStopped") { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(v.begin(), "a press while the analyzer finalizes the previous command is NOT dropped")
        await v._startTask?.value
        XCTAssertTrue(input.running)
        XCTAssertTrue(v.isListening)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(v.heard?.text, "\u{201C}sit\u{201D}", "the previous command's result arrived while the new listen is open")
        XCTAssertTrue(v.isListening, "and did not end the new listen")
        c.t += 0.5
        v.release()
        await v._settleTail()
        XCTAssertEqual(v.heard?.text, "\u{201C}spin\u{201D}")
        XCTAssertFalse(input.running)
    }

    override func tearDown() async throws { MicTuning.overlapOverride = nil }

    // MARK: the off switch (MicTuning.overlapTail = false: exactly the behaviour before the overlapping tail)

    func testSwitchOffRefusesAPressDuringThePostRollAndStillDeliversTheFirstResult() async throws {
        MicTuning.overlapOverride = false
        let (v, input, c) = make()
        input.transcripts = ["sit"]
        try await hold(v, c)
        v.release()
        XCTAssertFalse(v.isListening)
        XCTAssertFalse(v.begin(), "a press during the post-roll is refused, as before the overlapping tail")
        XCTAssertTrue(v.traceDropReason.contains("stopping"), v.traceDropReason)
        await v._startTask?.value
        for _ in 0..<100 where v.heard == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(v.heard?.text, "\u{201C}sit\u{201D}", "the first command's result still arrives")
        XCTAssertFalse(input.running, "engine stopped")
        XCTAssertEqual(input.events, ["start", "engineStopped"], "the post-roll was NOT cut and no second listen started")
        XCTAssertTrue(v.begin(), "once the tail is done a press opens")
        v.cancel()
    }

    func testSwitchOffRefusesAPressDuringTheFinalize() async throws {
        MicTuning.overlapOverride = false
        let (v, input, c) = make()
        input.transcripts = ["sit"]
        try await hold(v, c)
        v.release()
        while !input.events.contains("engineStopped") { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(v.begin(), "still refused while the analyzer finalizes")
        for _ in 0..<100 where v.heard == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(v.heard?.text, "\u{201C}sit\u{201D}")
        XCTAssertFalse(input.running)
    }

    func testSwitchStorageAndDevGate() {
        let n = "MicTailTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!; defer { d.removePersistentDomain(forName: n) }
        XCTAssertTrue(MicTuning.storedOverlap(devArgs: true, defaults: d), "no stored value: on")
        XCTAssertTrue(MicTuning.storedOverlap(devArgs: false, defaults: d, domain: n))
        d.set(false, forKey: MicTuning.overlapKey)          // what the launch argument (or an earlier dev launch) leaves behind
        XCTAssertFalse(MicTuning.storedOverlap(devArgs: true, defaults: d))
        XCTAssertFalse(MicTuning.storedOverlap(devArgs: false, defaults: d, domain: n), "a STORED value is honoured outside the dev gate")
        d.set(true, forKey: MicTuning.overlapKey)
        XCTAssertTrue(MicTuning.storedOverlap(devArgs: true, defaults: d))
        // the argument itself: only a dev build writes it
        let n2 = n + ".b"; let e = UserDefaults(suiteName: n2)!; defer { e.removePersistentDomain(forName: n2) }
        e.setVolatileDomain(["MicOverlapTail": false], forName: UserDefaults.argumentDomain)
        MicTuning.applyLaunchArguments(devArgs: false, defaults: e)
        XCTAssertNil(e.persistentDomain(forName: n2)?[MicTuning.overlapKey], "outside the dev gate the argument writes nothing")
        MicTuning.applyLaunchArguments(devArgs: true, defaults: e)
        XCTAssertEqual(e.persistentDomain(forName: n2)?[MicTuning.overlapKey] as? Bool, false, "in a dev build it is stored")
    }
}
