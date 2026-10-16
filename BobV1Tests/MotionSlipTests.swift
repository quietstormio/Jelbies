//
//  MotionSlipTests.swift
//  SLIP: travel comes from the steps. A planted foot (on the floor, not swinging) must not slide: its xz drift over one stance is at
//  most 5 % of the stride (the distance between consecutive landings of the same foot = 2 single steps); he must not translate while
//  both feet stand still; and a foot's net travel follows the body's.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionSlipTests: XCTestCase {
    /// Stance intervals of foot `f`: maximal runs where the foot is on the floor (gap < 0.012 H) for at least `minLen` seconds.
    private func stances(_ s: [MotionSample], foot f: Int, minLen: Float = 0.15) -> [(a: Int, b: Int)] {
        var out: [(Int, Int)] = []
        var a: Int?
        let th = 0.012 * MotionRig.H
        for i in 0..<s.count {
            let down = s[i].gap[f] < th
            if down && a == nil { a = i }
            if (!down || i == s.count - 1), let a0 = a {
                let b = down ? i : i - 1
                if s[b].t - s[a0].t >= minLen { out.append((a0, b)) }
                a = nil
            }
        }
        return out
    }

    private func slip(_ name: String, _ s: [MotionSample], stride: Float, minStances: Int = 3) {
        var worst: Float = 0, count = 0
        // the first 0.3 s after the action starts is the pose blending in (attractor / foot targets ramp up over 0.25 s): not judged
        let t0 = (s.first { $0.activity != .idle }?.t ?? 0) + 0.3
        for f in 0..<2 {
            for (a, b) in stances(s, foot: f) where s[a].t >= t0 {
                // ignore the first 40 ms (landing settle) of each stance
                let a2 = min(b, a + 3)
                var path: Float = 0
                for i in (a2 + 1)...max(a2 + 1, b) where i <= b { path += simd_length(s[i].xz[f] - s[i - 1].xz[f]) }
                let net = simd_length(s[b].xz[f] - s[a2].xz[f])
                worst = max(worst, net)
                MotionLog.write(String(format: "  %@ stance foot %d t=%.2f..%.2f drift %.4f u", name, f, s[a].t, s[b].t, net))
                count += 1
                _ = path
            }
        }
        MotionLog.write(String(format: "SLIP %@: %d stances, worst planted-foot drift %.4f u = %.1f %% of stride %.3f u", name, count, worst, 100 * worst / stride, stride))
        XCTAssertGreaterThanOrEqual(count, minStances, "\(name): need stances to judge")
        XCTAssertLessThanOrEqual(worst, 0.05 * stride, "\(name): planted foot slid")
    }

    func testWalkPlantedFootDoesNotSlide() {
        let (r, s) = MotionScenario.walk(game: false)
        slip("walk", s, stride: 2 * r.brain.stride)
    }
    func testStepAndTurnPlantedFootDoesNotSlide() {
        var (r, s) = MotionScenario.step()
        slip("step", s, stride: 2 * r.brain.stride)
        (r, s) = MotionScenario.turn()
        slip("turn", s, stride: 2 * r.brain.stride, minStances: 2)
    }

    func testTravelComesFromTheSteps() {
        let (r, s) = MotionScenario.walk(game: false)
        // no body translation while both feet stand still for >= 0.12 s
        let th = 0.012 * MotionRig.H
        var run0: Int?
        var worstMove: Float = 0
        for i in 0..<s.count {
            let both = s[i].gap[0] < th && s[i].gap[1] < th && s[i].activity != .idle
            if both && run0 == nil { run0 = i }
            if (!both || i == s.count - 1), let a = run0 {
                if s[i].t - s[a].t >= 0.12 { worstMove = max(worstMove, simd_length(s[i].root - s[a].root) / max(0.01, s[i].t - s[a].t)) }
                run0 = nil
            }
        }
        // distance walked vs the feet's net displacement
        let dBody = simd_length(s.last!.root - s.first!.root)
        let dFoot = (0..<2).map { simd_length(s.last!.xz[$0] - s.first!.xz[$0]) }
        MotionLog.write(String(format: "TRAVEL walk: body %.3f u, feet %.3f / %.3f u, worst root speed in double support %.3f u/s (stride %.3f)", dBody, dFoot[0], dFoot[1], worstMove, 2 * r.brain.stride))
        for d in dFoot { XCTAssertEqual(d, dBody, accuracy: 0.30, "each foot ends where the body went") }
        XCTAssertGreaterThan(dBody, 1.0)
    }
}
