import XCTest
@testable import BobV1

/// The warm-up cache: a failed warm-up is never handed to the next press (the "twice before the mic works" bug).
@MainActor
final class MicWarmGateTests: XCTestCase {
    private func ok() async -> Bool { true }
    private func bad() async -> Bool { false }

    func testFailedWarmIsNotReused() async {
        let g = MicWarmGate()
        g.warm { false }
        _ = await g.value()
        g.warm { true }
        XCTAssertEqual(g.makes, 2)
    }

    func testSuccessfulWarmIsReused() async {
        let g = MicWarmGate()
        g.warm { true }
        g.warm { true }
        XCTAssertEqual(g.makes, 1)
    }

    func testReadyRetriesAfterFailure() async {
        let g = MicWarmGate()
        var calls = 0, before = 0
        let make: MicWarmGate.Make = { calls += 1; return calls > 1 }
        g.warm(make)
        let r = await g.ready(stillRunning: { true }, make, beforeRetry: { before += 1 })
        XCTAssertTrue(r)
        XCTAssertEqual(before, 1)
        XCTAssertEqual(calls, 2)
    }

    func testReadyRetriesWhenEngineNotRunning() async {
        let g = MicWarmGate()
        var running = false, before = 0
        let make: MicWarmGate.Make = { running = true; return true }
        g.warm { true }
        let r = await g.ready(stillRunning: { running }, make, beforeRetry: { before += 1 })
        XCTAssertTrue(r)
        XCTAssertEqual(before, 1)
    }

    func testTwoFailuresGiveUp() async {
        let g = MicWarmGate()
        let r = await g.ready(stillRunning: { true }, { false }, beforeRetry: {})
        XCTAssertFalse(r)
    }
}
