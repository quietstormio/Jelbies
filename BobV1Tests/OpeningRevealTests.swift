//
//  OpeningRevealTests.swift
//  The opening's reveal: four Jelbies come out of their drops strictly one at a time, in the picker's order, with no rendering involved.
//

import XCTest
@testable import BobV1

@MainActor
final class OpeningRevealTests: XCTestCase {
    struct Log { var swells: [(Int, Double)] = []; var pops: [(Int, Double)] = []; var doneAt: Double? }

    /// Runs the sequencer on a fake clock. `readyAt[k]` is when Jelbie k is standing; `tapAt` hurries it.
    private func run(readyAt: [Double], step: Double = 1.0 / 30, tapAt: Double? = nil, stallAt: (Double, Double)? = nil, until: Double = 120) -> Log {
        var seq = RevealSequencer()
        var log = Log()
        var t = 0.0
        while t < until && log.doneAt == nil {
            var dt = step
            if let s = stallAt, t >= s.0, t - step < s.0 { dt = s.1 }          // one huge step: a hitch the clock should have clamped (the sequencer just sees the time)
            t += dt
            if let tap = tapAt, t >= tap { seq.hurry = true }
            for e in seq.update(now: t, ready: readyAt.map { $0 <= t }) {
                switch e {
                case .swell(let k): log.swells.append((k, t))
                case .pop(let k): log.pops.append((k, t))
                case .done: log.doneAt = t
                }
            }
        }
        return log
    }

    func testPopsInPickerOrderOneAtATime() {
        let log = run(readyAt: [0, 0, 0, 0])
        XCTAssertEqual(log.pops.map(\.0), [0, 1, 2, 3])
        XCTAssertEqual(log.swells.map(\.0), [0, 1, 2, 3])
        XCTAssertNotNil(log.doneAt)
        for i in 1..<4 { XCTAssertGreaterThanOrEqual(log.pops[i].1 - log.pops[i - 1].1, 0.9) }
        // the next drop swells only after the last one has settled
        for i in 1..<4 { XCTAssertGreaterThanOrEqual(log.swells[i].1 - log.pops[i - 1].1, RevealSequencer.Timing().settle - 0.001) }
        XCTAssertEqual(OpeningScript.characters, [0, 1, 3, 2], "blue, yellow, purple, green")
    }

    func testNoPopBeforeItsJelbieIsReady() {
        let ready = [0.0, 3.0, 20.0, 21.0]
        let log = run(readyAt: ready)
        XCTAssertEqual(log.pops.map(\.0), [0, 1, 2, 3])
        for (k, t) in log.pops { XCTAssertGreaterThanOrEqual(t, ready[k], "drop \(k) popped before its Jelbie stood") }
        for i in 1..<4 { XCTAssertGreaterThanOrEqual(log.pops[i].1 - log.pops[i - 1].1, 0.9) }
    }

    func testAJelbieThatIsLateHoldsOnlyItsOwnDropAndKeepsTheOrder() {
        // Jelbie 0 is the slow one: nothing else pops ahead of it
        let log = run(readyAt: [30, 0, 0, 0])
        XCTAssertEqual(log.pops.map(\.0), [0, 1, 2, 3])
        XCTAssertGreaterThanOrEqual(log.pops[0].1, 30)
    }

    func testHurryIsStillOneAtATime() {
        let slow = run(readyAt: [0, 0, 0, 0])
        let fast = run(readyAt: [0, 0, 0, 0], tapAt: 0.2)
        XCTAssertEqual(fast.pops.map(\.0), [0, 1, 2, 3])
        XCTAssertLessThan(fast.doneAt!, slow.doneAt!)
        for i in 1..<4 { XCTAssertGreaterThanOrEqual(fast.pops[i].1 - fast.pops[i - 1].1, 0.9) }
    }

    func testAStallDelaysAndNeverBunches() {
        let log = run(readyAt: [0, 0, 0, 0], stallAt: (3.0, 0.066))
        XCTAssertEqual(log.pops.count, 4)
        for i in 1..<4 { XCTAssertGreaterThanOrEqual(log.pops[i].1 - log.pops[i - 1].1, 0.9) }
    }

    func testNothingLeftoverWhenDone() {
        var seq = RevealSequencer()
        var t = 0.0
        var pops = 0
        for _ in 0..<2000 { t += 0.05; for e in seq.update(now: t, ready: [true, true, true, true]) { if case .pop = e { pops += 1 } } }
        XCTAssertEqual(pops, 4)
        XCTAssertTrue(seq.done)
        XCTAssertEqual(seq.update(now: t + 100, ready: [true, true, true, true]), [], "after the last one, no more pops")
    }

    func testCaptureAidFinishesWithoutPopping() {
        var seq = RevealSequencer()
        seq.finishAll(at: 0)
        XCTAssertTrue(seq.done)
        XCTAssertEqual(seq.update(now: 5, ready: [true, true, true, true]), [])
    }

    func testClockNeverJumpsMoreThanAFewFrames() {
        let c = OpeningClock()
        let t0 = Date()
        c.advance(t0)
        c.advance(t0.addingTimeInterval(0.03))
        c.advance(t0.addingTimeInterval(26))          // a 26 s render stall
        XCTAssertLessThanOrEqual(c.t, 0.03 + OpeningClock.maxStep + 0.0001)
        c.advance(t0.addingTimeInterval(26.03))
        XCTAssertLessThanOrEqual(c.t, 0.03 + OpeningClock.maxStep + 0.03 + 0.0001)
    }
}
