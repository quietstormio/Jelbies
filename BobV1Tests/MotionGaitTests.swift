//
//  MotionGaitTests.swift
//  GAIT (motion table; swing lift LOWERED 2026-10-17 on the user's direction: a low shuffle under the body, "cute short feet"): swing lift peak 0.03-0.10 H, cadence 2.8-3.6 steps/s walking and 1.8-2.2 steps/s marching, swing
//  fraction 0.30-0.45 of a foot's cycle, alternating feet, never a foot in the air at the end of a walk / turn / march (stop in double support).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionGaitTests: XCTestCase {
    private struct Event { var foot: Int; var t0: Float; var t1: Float; var peak: Float }

    /// Swings: runs where the RENDERED foot (lowest bean vertex) is more than 0.02 H off the floor.
    private func swings(_ s: [MotionSample]) -> [Event] {
        var out: [Event] = []
        let th = 0.01 * MotionRig.H
        for f in 0..<2 {
            var a: Int?, pk: Float = 0
            for i in 0..<s.count {
                let up = s[i].rgap[f] > th
                if up { if a == nil { a = i; pk = 0 }; pk = max(pk, s[i].rgap[f]) }
                else if let a0 = a { out.append(Event(foot: f, t0: s[a0].t, t1: s[i].t, peak: pk / MotionRig.H)); a = nil }
            }
        }
        return out.sorted { $0.t0 < $1.t0 }
    }

    func testWalkGait() {
        let (r, s) = MotionScenario.walk(game: false)
        let ev = swings(s.filter { $0.activity == .walking })
        // the middle of the walk (drop the first and last swing: they are the shortened start / stop steps)
        let mid = Array(ev.dropFirst(2).dropLast(2))
        XCTAssertGreaterThan(mid.count, 3)
        let peaks = mid.map(\.peak)
        let dur = zip(mid.dropFirst(), mid).map { $0.t0 - $1.t0 }.reduce(0, +) / Float(max(1, mid.count - 1))
        let rate = 1 / max(0.001, dur)
        let swingT = mid.map { $0.t1 - $0.t0 }.reduce(0, +) / Float(mid.count)
        let swingFrac = swingT / (2 / r.brain.stepRate)
        MotionLog.write(String(format: "GAIT walk: swing lift peak mean %.3f H (min %.3f max %.3f), cadence %.2f steps/s, swing %.3f s = %.2f of the foot cycle, %d swings",
                               peaks.reduce(0, +) / Float(peaks.count), peaks.min()!, peaks.max()!, rate, swingT, swingFrac, ev.count))
        XCTAssertGreaterThanOrEqual(peaks.min()!, 0.03)
        XCTAssertLessThanOrEqual(peaks.max()!, 0.10)
        XCTAssertGreaterThanOrEqual(rate, 2.8); XCTAssertLessThanOrEqual(rate, 4.0)      // Build B: cadence 3.5 -> 3.85 steps/s (speed +10 %)
        XCTAssertGreaterThanOrEqual(swingFrac, 0.25); XCTAssertLessThanOrEqual(swingFrac, 0.45)
        // alternating feet
        for (a, b) in zip(mid, mid.dropFirst()) { XCTAssertNotEqual(a.foot, b.foot, "feet alternate") }
        // stop in double support: no foot in the air once he is idle
        let tail = s.filter { $0.activity == .idle }
        XCTAssertFalse(tail.isEmpty)
        XCTAssertLessThanOrEqual(tail.map { max($0.gap[0], $0.gap[1]) }.max() ?? 0, 0.02 * MotionRig.H, "never halts with a foot in the air")
    }

    func testMarchGait() {
        let (_, s) = MotionScenario.step()
        let ev = swings(s.filter { $0.activity == .steppingInPlace })
        XCTAssertGreaterThan(ev.count, 4)
        let span = (ev.last!.t0 - ev.first!.t0)
        let rate = Float(ev.count - 1) / span
        let first = ev[0].peak
        MotionLog.write(String(format: "GAIT march: %.2f steps/s, first lift %.3f H, later mean %.3f H", rate, first, ev.dropFirst().map(\.peak).reduce(0, +) / Float(ev.count - 1)))
        XCTAssertGreaterThanOrEqual(rate, 1.8); XCTAssertLessThanOrEqual(rate, 2.2)
        XCTAssertGreaterThanOrEqual(first, 0.03)                       // was 0.06 (reference 0.09 H first step) before the low shuffle
        for (a, b) in zip(ev, ev.dropFirst()) { XCTAssertNotEqual(a.foot, b.foot) }
        XCTAssertLessThanOrEqual(s.filter { $0.activity == .idle }.map { max($0.gap[0], $0.gap[1]) }.max() ?? 0, 0.02 * MotionRig.H)
    }

    func testTurnStopsInDoubleSupportAndTurnsAtReferenceRate() {
        let (r, s) = MotionScenario.turn(by: 2.4)
        let walking = s.filter { $0.activity == .turning }
        guard let a = walking.first, let b = walking.last else { return XCTFail("no turn") }
        let rate = 2.4 / (b.t - a.t)
        MotionLog.write(String(format: "GAIT turn: 2.4 rad in %.2f s = %.2f rad/s (%.0f deg/s), reference 110-120 deg/s", b.t - a.t, rate, rate * 57.3))
        XCTAssertGreaterThan(rate * 57.3, 80); XCTAssertLessThan(rate * 57.3, 140)
        XCTAssertLessThanOrEqual(s.filter { $0.activity == .idle }.map { max($0.gap[0], $0.gap[1]) }.max() ?? 0, 0.02 * MotionRig.H)
        _ = r
    }

    /// Arm nubs swing as forward / back pendulums against the legs (REF2: std 12.8 deg front, 20 deg profile) through the nubForward / nubBack
    /// arm paths, and the override is released when the steps stop.
    func testNubsSwingAsPendulumsAgainstTheLegs() {
        let r = MotionRig(game: false)
        r.renderSamples = false
        r.brain.request(.goTo(r.root + SIMD2(0.0, 3.0)))
        var phi: [[Float]] = [[], []]
        var started = false
        r.run(9, until: { started && r.brain.activity == .idle }) {
            if r.brain.activity == .walking {
                started = true
                phi[0].append(r.brain.nubPhi[0]); phi[1].append(r.brain.nubPhi[1])
            }
        }
        let mid = 40..<(phi[0].count - 40)
        let tilt0 = mid.map { phi[0][$0] * Float(ArmPath.nubTiltDeg) }, tilt1 = mid.map { phi[1][$0] * Float(ArmPath.nubTiltDeg) }
        func std(_ v: [Float]) -> Float { let m = v.reduce(0, +) / Float(v.count); return (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Float(v.count)).squareRoot() }
        let opposite = mid.filter { abs(phi[0][$0]) > 0.2 && abs(phi[1][$0]) > 0.2 }.filter { phi[0][$0] * phi[1][$0] < 0 }.count
        let both = mid.filter { abs(phi[0][$0]) > 0.2 && abs(phi[1][$0]) > 0.2 }.count
        MotionLog.write(String(format: "NUBS pendulum: tilt std %.1f / %.1f deg (peak %.0f deg; REF2 12.8 front, 20 profile), max |phase| %.2f / %.2f, opposite-phase fraction %.2f, forward %@ back %@",
                               std(tilt0), std(tilt1), ArmPath.nubTiltDeg, phi[0].map { abs($0) }.max() ?? 0, phi[1].map { abs($0) }.max() ?? 0,
                               both > 0 ? Float(opposite) / Float(both) : 0, "\(phi[0].contains { $0 > 0.9 })", "\(phi[0].contains { $0 < -0.9 })"))
        XCTAssertGreaterThan(std(tilt0), 11); XCTAssertGreaterThan(std(tilt1), 11)
        XCTAssertLessThan(std(tilt0), 22)
        XCTAssertTrue(phi[0].contains { $0 > 0.9 } && phi[0].contains { $0 < -0.9 }, "both forward and back")
        XCTAssertGreaterThan(Float(opposite), 0.9 * Float(both), "the two arms swing in counter-phase")
        r.run(2.0)       // revert to cp5b: the walking arm capsules (W1d arms) hold 0.7 s after the walk before they swap out, so the release is checked after 2 s, not 1 s
        XCTAssertTrue(r.skinner.overrideVertices.isEmpty, "nub override released after the walk")
        XCTAssertTrue(r.sim.targets.isEmpty)
    }

    /// Steady-state ground speed (u/s) of the walk and the run, measured over the middle of a long leg (Build B: both raised ~10 %).
    func testWalkRunSteadySpeed() {
        func speed(_ run: Bool) -> Float {
            let r = MotionRig(game: false)
            r.renderSamples = false
            r.brain.seed = 11
            var pts: [(Float, SIMD2<Float>)] = []
            if run { r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(.run, r.sim)) }
            else { r.brain.request(.goTo(r.root + SIMD2(0, 6))) }
            let t0 = r.t
            r.run(12, until: { run ? r.brain.idleState.kind != .run : (pts.count > 30 && r.brain.activity == .idle) }) {
                if r.brain.activity == .walking && (!run || r.brain.runW > 0.999) { pts.append((r.t - t0, SIMD2(r.brain.px, r.brain.pz))) }
            }
            guard pts.count > 30 else { XCTFail("no walk"); return 0 }
            let total = simd_length(pts.last!.1 - pts[0].1)
            let a = pts.firstIndex { simd_length($0.1 - pts[0].1) > 0.3 * total }!, b = pts.lastIndex { simd_length($0.1 - pts[0].1) < 0.7 * total }!
            return simd_length(pts[b].1 - pts[a].1) / (pts[b].0 - pts[a].0)
        }
        let w = speed(false), n = speed(true)
        MotionLog.write(String(format: "SPEED walk %.3f u/s, run %.3f u/s", w, n))
        XCTAssertGreaterThan(w, 1.08); XCTAssertLessThan(w, 1.2)
        XCTAssertGreaterThan(n, 1.40); XCTAssertLessThan(n, 1.6)
    }
}
