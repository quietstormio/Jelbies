//
//  MotionWaveShapeTests.swift
//  The wave against the motion table (REF1, t = 7.58 s): arm s(t) swings at 2.0 Hz three times, he leans 14-24 deg away from the arm,
//  the arm-side foot lifts 0.12-0.20 H and is held, the far foot stays down, the eyes shut fully twice (0.10 / 0.12 s), 2.0 s in all.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionWaveShapeTests: XCTestCase {
    func testWaveScriptTiming() {
        XCTAssertEqual(WaveScript.duration, 2.0, accuracy: 0.001)
        var peaks: [Float] = []
        var prev: [Float] = [0, 0]
        var t: Float = 0
        while t < WaveScript.duration {
            let s0 = WaveScript.s(at: t)
            if prev[0] > prev[1] && prev[0] >= s0 && prev[0] > 0.95 { peaks.append(t - 0.001) }
            prev = [s0, prev[0]]
            t += 0.001
        }
        // up-peaks of the arm (s ~ 1) every 0.495 s: 0.68, 1.17, 1.67
        MotionLog.write("WAVESHAPE s(t) up-peaks at \(peaks.map { String(format: "%.2f", $0) })")
        XCTAssertGreaterThanOrEqual(peaks.count, 3)
        let p = Array(peaks.prefix(3))
        XCTAssertEqual(p[0], 0.68, accuracy: 0.03)
        XCTAssertEqual(p[1] - p[0], 0.495, accuracy: 0.495 * 0.05)
        XCTAssertEqual(p[2] - p[1], 0.495, accuracy: 0.495 * 0.05)
        XCTAssertEqual(WaveScript.s(at: 0), 0, accuracy: 1e-4)
        XCTAssertEqual(WaveScript.s(at: WaveScript.duration), 0, accuracy: 1e-3)
        // monotone raise from rest to the first peak
        var last: Float = -1
        for i in 0...68 { let v = WaveScript.s(at: Float(i) * 0.01); XCTAssertGreaterThanOrEqual(v + 1e-5, last); last = v }
    }

    func testWaveBodyAgainstMotionTable() {
        for side in [-1, 1] {
            let (r, s) = MotionScenario.wave(side: side, game: true)
            guard let i0 = s.firstIndex(where: { $0.activity == .waving }) else { return XCTFail("no wave") }
            let w = s.filter { $0.activity == .waving }
            let t0 = s[i0].t
            let armFoot = side > 0 ? 1 : 0, farFoot = 1 - armFoot
            let H = MotionRig.H
            let lift = w.map { $0.rgap[armFoot] / H }              // the RENDERED rigid foot (the sim sole only lifts a few cm)
            let holdN = lift.filter { $0 >= 0.12 }.count
            let far = w.map { $0.rgap[farFoot] / H }.max() ?? 0
            let rollAway = w.map { -Float(side) * $0.roll * 180 / .pi }.max() ?? 0
            let dur = (w.last?.t ?? 0) - t0
            let shut = w.filter { $0.openness < 0.01 }
            // two separate closes
            var closes: [Float] = []
            var a: Float?
            for x in w { if x.openness < 0.01 { if a == nil { a = x.t } } else if let a0 = a { closes.append(x.t - a0); a = nil } }
            MotionLog.write(String(format: "WAVESHAPE side %d: arm-side foot lift max %.3f H, held >=0.12 H for %.2f s, far foot max gap %.3f H, lean away max %.1f deg, duration %.2f s, closes %@",
                                   side, lift.max() ?? 0, Float(holdN) / 60, far, rollAway, dur, "\(closes.map { String(format: "%.2f", $0) })"))
            XCTAssertGreaterThanOrEqual(lift.max() ?? 0, 0.12)
            XCTAssertLessThanOrEqual(lift.max() ?? 0, 0.20)
            XCTAssertGreaterThanOrEqual(Float(holdN) / 60, 0.3, "the arm-side foot is held up")
            XCTAssertLessThanOrEqual(far, 0.02, "far foot stays planted")
            XCTAssertGreaterThanOrEqual(rollAway, 20, "REF1 leans 20-22 deg away from the arm (eye line 28)"); XCTAssertLessThanOrEqual(rollAway, 23)
            XCTAssertEqual(dur, 2.0, accuracy: 0.1)
            XCTAssertEqual(closes.count, 2, "two eye closes")
            if closes.count == 2 { XCTAssertEqual(closes[0], 0.10, accuracy: 0.04); XCTAssertEqual(closes[1], 0.12, accuracy: 0.04) }
            XCTAssertFalse(shut.isEmpty)
            _ = r
        }
    }
}
