//
//  JellyJiggleTests.swift
//  The jelly follow-through layer (BobV1/Melon/JellyJiggle.swift): zero at rest, bounded, feet untouched, the footfall ripple and the
//  start / stop sway have the intended size, and the per-frame cost. The gait tests (Motion*Tests) never tick the jelly, so they prove the
//  brain / sim are unchanged; here the jelly is ticked exactly like MelonStage does (after each brain tick).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class JellyJiggleTests: XCTestCase {
    private let H = Float(BobForm.top)

    private func step(_ r: MotionRig) {
        r.tick()
        r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
    }

    /// Skin with and without the jelly and return (max displacement / H, max displacement of any vertex below 0.1 H, with-jelly dyn).
    private func displacement(_ r: MotionRig) -> (all: Float, feet: Float) {
        r.render()
        let a = r.dyn
        r.skinner.jelly.enabled = false
        r.render()
        r.skinner.jelly.enabled = true
        let b = r.dyn
        var m: Float = 0, f: Float = 0
        for v in 0..<(a.count / 6) {
            let o = 6 * v
            let d = simd_length(SIMD3(a[o] - b[o], a[o + 1] - b[o + 1], a[o + 2] - b[o + 2]))
            m = max(m, d)
            if b[o + 1] - r.sim.floorY < 0.1 * H { f = max(f, d) }
        }
        return (m / H, f)
    }

    func testZeroAtRest() {
        let r = MotionRig(game: true)
        r.run(1.0) { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
        XCTAssertFalse(r.skinner.jelly.active)
        XCTAssertEqual(r.skinner.jelly.squash, 0)
        r.render(); let a = r.dyn
        r.skinner.jelly.enabled = false; r.render(); let b = r.dyn
        XCTAssertEqual(a, b, "at rest the drawn skin is bit-identical with and without the jelly")
    }

    func testSettlesToExactlyZeroHalfASecondAfterStopping() {
        let r = MotionRig(game: true)
        r.brain.request(.goTo(r.root + SIMD2(0, 1.5)))
        r.run(1.0) { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
        r.run(6.0, until: { !r.brain.feet.active && !r.brain.stepLive }) { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
        XCTAssertFalse(r.brain.feet.active)
        r.run(0.5) { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
        let j = r.skinner.jelly
        XCTAssertFalse(j.active)
        XCTAssertEqual(j.squash, 0); XCTAssertEqual(j.sway, .zero); XCTAssertEqual(j.tw, 0)
        r.render(); let a = r.dyn
        j.enabled = false; r.render()
        XCTAssertEqual(a, r.dyn)
    }

    func testWalkIsSlightBoundedAndFeetUntouched() {
        let r = MotionRig(game: true)
        var peak: Float = 0, feet: Float = 0, sqPeak: Float = 0, swayPeak: Float = 0, frames = 0
        for leg in 0..<3 {
            r.brain.request(.goTo(r.root + SIMD2(leg % 2 == 0 ? 1.6 : -1.6, 1.0)))
            for _ in 0..<(60 * 4) {
                step(r)
                frames += 1
                if frames % 3 == 0 {
                    let d = displacement(r); peak = max(peak, d.all); feet = max(feet, d.feet)
                    sqPeak = max(sqPeak, abs(r.skinner.jelly.squash)); swayPeak = max(swayPeak, simd_length(r.skinner.jelly.sway) / H)
                }
            }
        }
        MotionLog.write(String(format: "JELLY walk: max surface displacement %.2f %% H, squash %.2f %%, sway %.2f %%, feet %.6f", peak * 100, sqPeak * 100, swayPeak * 100, feet))
        XCTAssertGreaterThan(peak, 0.006, "the jiggle is visible")
        XCTAssertLessThanOrEqual(peak, 0.055, "walking: <= 5.5 % H (Build B: more jiggle, was 3 %)")
        XCTAssertEqual(feet, 0, "the feet (lowest 10 % of the body) never move")
        XCTAssertGreaterThanOrEqual(sqPeak, 0.02); XCTAssertLessThanOrEqual(sqPeak, 0.05)      // Build B: was 0.012...0.03
    }

    func testRunAndJacksBoundedAndFeetUntouched() {
        for kind in [IdleKind.run, .jacks] {
            let r = MotionRig(game: true)
            r.brain.seed = 11; r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(kind, r.sim))
            var peak: Float = 0, feet: Float = 0, n = 0
            r.run(30, until: { r.brain.idleState.kind == nil }) {
                r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
                n += 1
                if n % 3 == 0 { let d = self.displacement(r); peak = max(peak, d.all); feet = max(feet, d.feet) }
            }
            MotionLog.write(String(format: "JELLY %@: max surface displacement %.2f %% H (%d steps)", "\(kind)", peak * 100, n))
            XCTAssertGreaterThan(n, 120, "\(kind) really ran"); XCTAssertGreaterThan(peak, 0.006)
            XCTAssertLessThanOrEqual(peak, 0.085, "\(kind): <= 8.5 % H (Build B, was 5 %)")
            XCTAssertEqual(feet, 0)
        }
    }

    func testHopLandingBoundedAndFeetUntouched() {
        let r = MotionRig(game: true)
        var peak: Float = 0, feet: Float = 0, n = 0
        for _ in 0..<3 {
            r.brain.startHopPlay(sim: r.sim, distance: 0.45)
            r.run(2.0) {
                r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
                n += 1
                if n % 2 == 0 { let d = self.displacement(r); peak = max(peak, d.all); feet = max(feet, d.feet) }
            }
        }
        MotionLog.write(String(format: "JELLY hop: max surface displacement %.2f %% H", peak * 100))
        XCTAssertGreaterThan(peak, 0.006); XCTAssertLessThanOrEqual(peak, 0.085); XCTAssertEqual(feet, 0)
    }

    func testFootfallRippleSizeAndSettling() {
        let j = JellyJiggle()
        let dt: Float = 1.0 / 60
        j.advance(dt: dt, root: .zero, yaw: 0, landing: JellyJiggle.footImpulse, run: 0)
        var peak: Float = 0, t: Float = 0, lastBig: Float = 0
        for _ in 0..<60 {
            t += dt
            j.advance(dt: dt, root: .zero, yaw: 0, landing: 0, run: 0)
            peak = max(peak, abs(j.squash))
            if abs(j.squash) > 0.002 { lastBig = t }
        }
        MotionLog.write(String(format: "JELLY footfall: peak %.2f %% H, below 0.2 %% after %.2f s", peak * 100, lastBig))
        XCTAssertGreaterThanOrEqual(peak, 0.025); XCTAssertLessThanOrEqual(peak, 0.05)      // Build B: was 0.015...0.03
        XCTAssertLessThanOrEqual(lastBig, 0.3, "settles in about a quarter second")
    }

    func testStartStopSwayTrailsThenReturns() {
        let r = MotionRig(game: true)
        r.brain.request(.goTo(r.root + SIMD2(0, 2.0)))
        var lagAlong: Float = 0, over: Float = 0, started = false
        var dir = SIMD2<Float>(0, 1)
        for i in 0..<(60 * 6) {
            step(r)
            let j = r.skinner.jelly
            if i < 40 { lagAlong = min(lagAlong, simd_dot(j.sway, dir)) }                 // crown trails (negative along travel)
            if i > 60, simd_length(r.skinner.jelly.sway) > 0 { started = true }
            if !r.brain.feet.active && i > 100 { over = max(over, simd_dot(j.sway, dir)) }   // leans on past on the stop
        }
        MotionLog.write(String(format: "JELLY start trail %.2f %% H, stop overshoot %.2f %% H", -lagAlong / H * 100, over / H * 100))
        XCTAssertGreaterThan(-lagAlong / H, 0.005, "the crown trails the base on the start")
        XCTAssertLessThan(-lagAlong / H, 0.05)
        XCTAssertGreaterThan(over / H, 0.003, "and carries on forward when he stops")
        _ = started
    }

    /// Build B: stopping dead from a walk gives a settle wobble (a squash ripple) that then dies to exactly zero.
    func testStopFromAWalkWobblesThenSettles() {
        let j = JellyJiggle()
        let dt: Float = 1.0 / 60
        var x: Float = 0
        for _ in 0..<90 { x += 1.1 * dt; j.advance(dt: dt, root: SIMD2(0, x), yaw: 0, landing: 0, run: 0) }
        var peak: Float = 0, settled: Float = 0, t: Float = 0
        for _ in 0..<90 {
            t += dt
            j.advance(dt: dt, root: SIMD2(0, x), yaw: 0, landing: 0, run: 0)
            if t > 0.1 { peak = max(peak, abs(j.squash)) }
            if j.active { settled = t }
        }
        MotionLog.write(String(format: "JELLY stop wobble: squash peak %.2f %% H after the stop, inactive after %.2f s", peak * 100, settled))
        XCTAssertGreaterThan(peak, 0.01, "he wobbles when he stops")
        XCTAssertFalse(j.active); XCTAssertEqual(j.squash, 0)
    }

    /// Build B: the walk / run jiggle is about 1.5-2x the first slight one (same scenario, `legacy` = the first tuning).
    func testBuildBJiggleIsStrongerThanTheFirstOne() {
        func measure(legacy: Bool, run: Bool) -> (disp: Float, sq: Float, sway: Float) {
            let r = MotionRig(game: true)
            r.skinner.jelly.legacy = legacy
            r.brain.seed = 11
            if run { r.brain.idleForced = true; _ = r.brain.idleStart(.run, r.sim) } else { r.brain.request(.goTo(r.root + SIMD2(1.6, 1.0))) }
            var disp: Float = 0, sq: Float = 0, sway: Float = 0, n = 0
            for _ in 0..<(60 * (run ? 5 : 4)) {
                step(r)
                n += 1
                sq = max(sq, abs(r.skinner.jelly.squash)); sway = max(sway, simd_length(r.skinner.jelly.sway) / H)
                if n % 3 == 0 { disp = max(disp, displacement(r).all) }
            }
            return (disp, sq, sway)
        }
        for run in [false, true] {
            let a = measure(legacy: true, run: run), b = measure(legacy: false, run: run)
            MotionLog.write(String(format: "JELLY build B %@: surface displacement %.2f -> %.2f %% H (x%.2f), squash %.2f -> %.2f %% (x%.2f), sway %.2f -> %.2f %% (x%.2f)", run ? "run" : "walk",
                                   a.disp * 100, b.disp * 100, b.disp / a.disp, a.sq * 100, b.sq * 100, b.sq / a.sq, a.sway * 100, b.sway * 100, b.sway / a.sway))
            XCTAssertGreaterThan(b.sq / a.sq, 1.3); XCTAssertGreaterThan(b.disp / a.disp, 1.2)
            XCTAssertLessThan(b.sq / a.sq, 2.6); XCTAssertLessThan(b.disp / a.disp, 2.6)
        }
    }

    func testCostPerFrame() {
        let r = MotionRig(game: true)
        r.brain.request(.goTo(r.root + SIMD2(0, 4)))
        r.run(1.0) { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
        XCTAssertTrue(r.skinner.jelly.active)
        let n = 300
        var tickT = 0.0, applyT = 0.0
        r.render()
        var buf = r.dyn
        for _ in 0..<n {
            r.tick()
            let a = CACurrentMediaTime()
            r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            let b = CACurrentMediaTime()
            let vc = buf.count / 6
            buf.withUnsafeMutableBufferPointer { r.skinner.jelly.apply($0.baseAddress!, count: vc) }
            let c = CACurrentMediaTime()
            tickT += b - a; applyT += c - b
        }
        MotionLog.write(String(format: "JELLY perf: tick %.1f us, apply %.1f us per frame (%d vertices)", tickT / Double(n) * 1e6, applyT / Double(n) * 1e6, buf.count / 6))
        XCTAssertLessThan(applyT / Double(n) * 1e6, 400)
    }
}
