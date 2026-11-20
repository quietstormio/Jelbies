import XCTest
@testable import BobV1

/// The mic press trace and the `-MicBench` bench: inert when off, gated by the dev switch, and the numbers it prints are the ones it measured.
@MainActor
final class MicTraceTests: XCTestCase {
    private func make() -> (VoiceCoordinator, FakeSpeechInput) {
        let input = FakeSpeechInput()
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "MicTraceTests")!, persists: false)
        return (VoiceCoordinator(training: training, input: input), input)
    }
    private func suite() -> (UserDefaults, () -> Void) {
        let n = "MicTraceTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!
        return (d, { d.removePersistentDomain(forName: n) })
    }
    private var tmpLog: URL { FileManager.default.temporaryDirectory.appendingPathComponent("micbench-test-\(UUID().uuidString).log") }

    override func tearDown() async throws {
        MicTrace.override = nil
        MicTrace.stopRecording()
        MicTrace.resetForTest()
    }

    func testTraceIsInertWhenOff() async throws {
        MicTrace.override = false
        MicTrace.resetForTest()
        let url = tmpLog
        MicTrace.logURL = url
        let (v, _) = make()
        XCTAssertTrue(v.begin())
        XCTAssertNil(v.trace, "no trace object is made when the trace is off")
        XCTAssertNil(MicTrace.latest)
        XCTAssertFalse(MicTrace.recording, "no frame / main-thread / playback recorder runs")
        MicTrace.frame(CACurrentMediaTime())          // the stage's hook is guarded by `recording`; calling it anyway must not matter
        await v._startTask?.value
        v.release()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(MicTrace.latest)
        XCTAssertFalse(MicTrace.recording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "nothing is written")
        v.cancel()
    }

    func testTraceNeedsTheDevSwitchEvenWithVoiceLog() {
        let (d, done) = suite(); defer { done() }
        d.set(true, forKey: "VoiceLog"); d.set(3, forKey: "MicBench")
        XCTAssertFalse(MicTrace.isEnabled(devArgs: false, defaults: d), "a store build never traces, whatever the saved flags say")
        XCTAssertTrue(MicTrace.isEnabled(devArgs: true, defaults: d))
        d.removeObject(forKey: "MicBench")
        XCTAssertTrue(MicTrace.isEnabled(devArgs: true, defaults: d), "-VoiceLog 1 still works in developer builds")
        d.set(false, forKey: "VoiceLog")
        XCTAssertFalse(MicTrace.isEnabled(devArgs: true, defaults: d))
    }

    func testBenchArgumentNeedsTheDevSwitch() {
        let (d, done) = suite(); defer { done() }
        d.set(5, forKey: "MicBench"); d.set("warm", forKey: "MicVariant")
        XCTAssertEqual(MicBench.count(devArgs: false, defaults: d), 0, "a store build never runs the bench")
        XCTAssertEqual(MicBench.variant(devArgs: false, defaults: d), "base")
        XCTAssertEqual(MicBench.count(devArgs: true, defaults: d), 5)
        XCTAssertEqual(MicBench.variant(devArgs: true, defaults: d), "warm")
        d.removeObject(forKey: "MicBench"); d.removeObject(forKey: "MicVariant")
        XCTAssertEqual(MicBench.count(devArgs: true, defaults: d), 0)
        XCTAssertEqual(MicBench.variant(devArgs: true, defaults: d), "base")
        d.set(-3, forKey: "MicBench")
        XCTAssertEqual(MicBench.count(devArgs: true, defaults: d), 0)
    }

    func testTraceCollectsOnAPressAndPrintsTheLine() async throws {
        MicTrace.override = true
        MicTrace.resetForTest()
        MicTrace.printFinished = false
        defer { MicTrace.printFinished = true }
        let (v, _) = make()
        XCTAssertTrue(v.begin())
        let tr = try XCTUnwrap(v.trace)
        XCTAssertEqual(tr.number, 1); XCTAssertTrue(tr.cold)
        XCTAssertNotNil(tr.abs(.begin), "begin() stamped")
        XCTAssertTrue(MicTrace.recording)
        await v._startTask?.value
        XCTAssertNotNil(tr.abs(.live), "the fake's first buffer stamps live")
        let live1 = tr.abs(.live)
        tr.mark(.live, at: tr.t0 + 10)
        XCTAssertEqual(tr.abs(.live), live1, "first write wins")
        v.release()
        XCTAssertNotNil(tr.abs(.release)); XCTAssertNotNil(tr.abs(.listenOff))
        MicTrace.abandon(tr, reason: "test")
        let done = expectation(description: "finished")
        tr.whenFinished { done.fulfill() }
        await fulfillment(of: [done], timeout: 3)
        let s = try XCTUnwrap(tr.summary)
        let line = s.line(number: tr.number, cold: tr.cold, variant: tr.variant)
        XCTAssertTrue(line.hasPrefix("[micbench] press 1 variant=base cold=1"), line)
        XCTAssertTrue(line.contains(" live="), line)
        XCTAssertTrue(line.contains(" r_listenOff="), line)
        XCTAssertTrue(line.contains(" ctl_main=-"), "a control window with no 2 s of recording is not claimed: \(line)")
        tr.mark(.engineStopped)
        XCTAssertNil(tr.abs(.engineStopped), "a finished trace ignores later marks")
    }

    func testDroppedPressReasonNamesTheGuard() async throws {
        MicTrace.override = false
        let (v, _) = make()
        XCTAssertEqual(v.traceDropReason, "none")
        v.stopping = true
        XCTAssertEqual(v.traceDropReason, "stopping")
        XCTAssertFalse(v.begin(), "begin() refuses while the tail of the last command runs")
        v.stopping = false
    }

    func testMediansAndDoneLine() {
        func sum(_ a: Double?, _ b: Double?) -> PressSummary { var s = PressSummary(); s.fields = [("live", a), ("engine", b)]; return s }
        let m = MicBench.medians([sum(100, 10), sum(300, nil), sum(200, 30)])
        XCTAssertEqual(m.first { $0.0 == "live" }?.1, 200)
        XCTAssertEqual(m.first { $0.0 == "engine" }?.1, 20, "the median ignores presses that did not measure the field")
        let line = MicBench.doneLine(variant: "base", presses: 3, dropped: 1, sums: [sum(100, 10), sum(300, nil), sum(200, 30)])
        XCTAssertEqual(line, "[micbench] done variant=base presses=3 dropped=1 median: live=200 engine=20")
    }

    /// Simulator, fake input: shows the lines come out (the numbers are NOT evidence of anything about audio).
    func testBenchPrintsOneLinePerPressAndADoneLine() async throws {
        MicTrace.override = true
        MicTrace.resetForTest()
        let box = LineBox()
        let (v, _) = make()
        await MicBench.run(voice: v, count: 2, hold: 0.4, settle: 0.5, quickGap: 0.6, afterPutBack: 0.1, emit: { box.add($0) })
        let lines = box.all
        for l in lines { print("SIMBENCH \(l)") }
        XCTAssertEqual(lines.filter { $0.hasPrefix("[micbench] press") }.count, 4, "2 presses + 2 quick re-presses")
        XCTAssertEqual(lines.last?.hasPrefix("[micbench] done variant=base presses=4"), true, lines.last ?? "")
        XCTAssertTrue(lines.contains { $0.contains("quick=1") })
    }
}

private final class LineBox: @unchecked Sendable {
    private let l = NSLock(); private var a: [String] = []
    func add(_ s: String) { l.lock(); a.append(s); l.unlock() }
    var all: [String] { l.lock(); defer { l.unlock() }; return a }
}
