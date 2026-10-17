//
//  TouchPinchGuardTests.swift
//  The two-finger cheek pinch must never stretch his skin off the body (the phone showed long streaks to the camera). Extreme and degenerate
//  inputs: zero / huge / NaN gaps, fingers off the body, rapid start / stop, hitched frames (dt up to the stage's 0.1 s clamp).
//  Every drawn vertex stays finite and within 1.2x the body bounds.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TouchPinchGuardTests: XCTestCase {
    private func bounds(_ d: [Float]) -> (lo: SIMD3<Float>, hi: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for v in 0..<(d.count / 6) { let p = SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return (lo, hi)
    }

    func testPinchNeverTearsTheSkin() {
        let r = TouchPlayTests.Rig()
        r.rig.render()
        let b0 = bounds(r.rig.dyn)
        let c = (b0.lo + b0.hi) / 2, h = (b0.hi - b0.lo) / 2 * 1.2
        let lo = c - h, hi = c + h
        var worst: Float = 0
        func check(_ what: String) {
            r.rig.render()
            for v in 0..<(r.rig.dyn.count / 6) {
                let p = SIMD3(r.rig.dyn[6 * v], r.rig.dyn[6 * v + 1], r.rig.dyn[6 * v + 2])
                XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite, "\(what): non-finite vertex")
                if !(p.x.isFinite && p.y.isFinite && p.z.isFinite) { return }
                worst = max(worst, simd_reduce_max(simd_max(lo - p, p - hi)))
                if p.x < lo.x || p.y < lo.y || p.z < lo.z || p.x > hi.x || p.y > hi.y || p.z > hi.z {
                    XCTFail("\(what): vertex \(v) at \(p) is outside 1.2x the body bounds"); return
                }
            }
            XCTAssertLessThan(r.rig.sim.kineticEnergy() / r.rig.sim.totalMass, 5, "\(what): the sim stays calm")
        }
        let on = [r.ray(-0.2, 0.25), r.ray(0.2, 0.25)]
        let off = [(o: SIMD3<Float>(0, 0.9, 6), d: SIMD3<Float>(0, 1, 0)), (o: SIMD3<Float>(0, 0.9, 6), d: SIMD3<Float>(1, 0, 0))]
        func run(_ what: String, frames: Int, dt: Float = 1.0 / 60, rays: [(o: SIMD3<Float>, d: SIMD3<Float>)]?, gap: (Int) -> Float) {
            for k in 0..<frames {
                r.play.cheeksFrame(dt: dt, now: r.clock, rays: rays, gap: gap(k), sim: r.rig.sim, brain: r.rig.brain, skinner: r.rig.skinner, surface: r.surface)
                r.rig.tick(); r.clock += Double(dt)
                check("\(what) frame \(k)")
            }
        }
        run("zero gap", frames: 40, rays: on) { _ in 0 }
        run("release", frames: 20, rays: nil) { _ in 0 }
        run("huge gap", frames: 40, rays: on) { _ in 1e9 }
        run("release", frames: 20, rays: nil) { _ in 0 }
        run("nan gap", frames: 40, rays: on) { _ in .nan }
        run("inf gap", frames: 10, rays: on) { _ in .infinity }
        run("negative gap", frames: 10, rays: on) { _ in -50 }
        run("release", frames: 20, rays: nil) { _ in 0 }
        run("fingers off the body", frames: 40, rays: off) { Float(400 - $0 * 8) }
        run("rapid start / stop", frames: 60, rays: on) { _ in 400 }
        for k in 0..<60 { run("flip \(k)", frames: 1, rays: k % 2 == 0 ? on : nil) { _ in max(0, 400 - Float(k) * 12) } }
        // hitched frames: the stage clamps dt to 0.1 s, which used to destabilise the squeeze spring
        run("pinch in", frames: 30, rays: on) { 400 - Float($0) * 13 }
        run("hitching pinch", frames: 30, dt: 0.1, rays: on) { _ in 5 }
        run("hitching release", frames: 30, dt: 0.1, rays: nil) { _ in 0 }
        run("hitch then fine", frames: 30, rays: on) { _ in 5 }
        print("PINCHGUARD worst overshoot beyond 1.2x bounds: \(worst) (<= 0 is inside)")
        XCTAssertLessThanOrEqual(r.play.visPinch, 1.3)
        XCTAssertGreaterThanOrEqual(r.play.visPinch, -0.4)
    }

    func testCheekOffsetIsCapped() {
        let r = TouchPlayTests.Rig()
        for k in 0..<60 { r.play.cheeksFrame(dt: 1.0 / 60, now: r.clock, rays: [r.ray(-0.2, 0.25), r.ray(0.2, 0.25)], gap: k < 5 ? 400 : 1, sim: r.rig.sim, brain: r.rig.brain, skinner: r.rig.skinner, surface: r.surface); r.clock += 1.0 / 60 }
        XCTAssertFalse(r.rig.skinner.extraDelta.isEmpty)
        for d in r.rig.skinner.extraDelta { XCTAssertLessThanOrEqual(simd_length(d), TouchPlay.maxCheekOffset + 1e-5) }
    }
}
