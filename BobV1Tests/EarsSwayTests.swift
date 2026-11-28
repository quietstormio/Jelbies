//
//  EarsSwayTests.swift
//  The sway clock (Audio/EarsSway.swift) on its own: tempo folding, locking onto a beat grid, no pop at a half-beat flip / a tempo change / a lost beat,
//  coasting without a beat.
//

import XCTest
@testable import BobV1

final class EarsSwayTests: XCTestCase {
    func testFastTempoSwaysOnEverySecondBeat() {
        XCTAssertEqual(EarsSway.swayBpm(140), 70, accuracy: 0.01)
        XCTAssertEqual(EarsSway.swayBpm(120), 60, accuracy: 0.01)
        XCTAssertEqual(EarsSway.swayBpm(100), 100, accuracy: 0.01)
        XCTAssertEqual(EarsSway.swayBpm(80), 80, accuracy: 0.01)
        XCTAssertEqual(EarsSway.swayBpm(160), 80, accuracy: 0.01)
    }

    /// Run `seconds` at 60 Hz, feeding `feed(t)` first each frame; returns (extremes of the roll as times, the largest step in roll and squash).
    private func run(_ s: inout EarsSway, from t0: Double, seconds: Double, feed: (inout EarsSway, Double) -> Void = { _, _ in }) -> (stepRoll: Float, stepSq: Float, landings: [Double]) {
        var stepRoll: Float = 0, stepSq: Float = 0, landings: [Double] = []
        var pr = s.roll(maxRoll: 0.09), pq = s.squash(depth: 0.05), pu = s.u
        var t = t0
        for _ in 0..<Int(seconds * 60) {
            t += 1.0 / 60
            feed(&s, t)
            s.tick(dt: 1.0 / 60)
            let r = s.roll(maxRoll: 0.09), q = s.squash(depth: 0.05)
            stepRoll = max(stepRoll, abs(r - pr)); stepSq = max(stepSq, abs(q - pq)); pr = r; pq = q
            if floor(s.u) > floor(pu) { landings.append(t) }
            pu = s.u
        }
        return (stepRoll, stepSq, landings)
    }

    func testLocksOntoTheBeatGridAndLandsOnIt() {
        var s = EarsSway()
        let bpm: Float = 100, period = 0.6, anchor = 0.17
        let r = run(&s, from: 0, seconds: 12) { sw, t in
            if abs((t * 4).rounded() / 4 - t) < 1.0 / 120, Int((t * 4).rounded()) % 1 == 0 { sw.hear(EarBeat(bpm: bpm, anchor: anchor, strength: 4), now: t) }          // every 0.25 s
        }
        let late = r.landings.filter { $0 > 6 }
        XCTAssertGreaterThanOrEqual(late.count, 8)
        for l in late { let d = ((l - anchor) / period); XCTAssertEqual(d, d.rounded(), accuracy: 0.04, "landing at \(l) is off the beat") }
        XCTAssertLessThan(r.stepRoll, 0.012); XCTAssertLessThan(r.stepSq, 0.008)
    }

    func testAHalfBeatFlipATempoChangeAndALostBeatDoNotPop() {
        var s = EarsSway()
        var anchor = 0.0
        var bpm: Float = 100
        func feed(_ sw: inout EarsSway, _ t: Double) {
            if Int((t * 60).rounded()) % 15 == 0 { sw.hear(EarBeat(bpm: bpm, anchor: anchor, strength: 4), now: t) }
        }
        var r = run(&s, from: 0, seconds: 6, feed: feed)
        anchor = 0.3                       // a half-beat shift that lasts one estimate only, then comes back (an outlier)
        var worst = r.stepRoll
        r = run(&s, from: 6, seconds: 0.25, feed: feed); worst = max(worst, r.stepRoll)
        anchor = 0
        r = run(&s, from: 6.25, seconds: 3, feed: feed); worst = max(worst, r.stepRoll)
        bpm = 200                          // the octave: folds to the same sway tempo
        r = run(&s, from: 9.25, seconds: 3, feed: feed); worst = max(worst, r.stepRoll)
        bpm = 130                          // a real new tempo (folds to 65)
        r = run(&s, from: 12.25, seconds: 4, feed: feed); worst = max(worst, r.stepRoll)
        r = run(&s, from: 16.25, seconds: 6); worst = max(worst, r.stepRoll)          // lost: it coasts
        XCTAssertLessThan(worst, 0.012, "roll step per frame")
        XCTAssertGreaterThan(r.landings.count, 4, "the clock keeps going with no beat")
        XCTAssertEqual(s.roll(maxRoll: 0.09).magnitude <= 0.09, true)
    }

    func testWithNoBeatEverItSwaysGentlyOnItsOwn() {
        var s = EarsSway()
        var mx: Float = 0
        for _ in 0..<600 { s.tick(dt: 1.0 / 60); mx = max(mx, abs(s.roll(maxRoll: 0.09))) }
        XCTAssertGreaterThan(mx, 0.04)
        XCTAssertLessThan(mx, 0.06)
    }
}
