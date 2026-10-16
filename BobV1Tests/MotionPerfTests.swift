//
//  MotionPerfTests.swift
//  CPU cost of the motion layer: brain.tick (pose pivot, foot / nub targets, arm override) vs sim.step, per fixed step, while walking,
//  waving, marching and idling in the game. Run in Release (-configuration Release ENABLE_TESTABILITY=YES) for the numbers that matter.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionPerfTests: XCTestCase {
    private func measure(_ name: String, game: Bool = false, steps: Int = 240, start: (MotionRig) -> Void) {
        let r = MotionRig(game: game)
        start(r)
        r.run(0.5)                              // let the action get going
        var tick = 0.0, step = 0.0
        for _ in 0..<steps {
            let a = CACurrentMediaTime()
            r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
            let b = CACurrentMediaTime()
            r.sim.step()
            let c = CACurrentMediaTime()
            tick += b - a; step += c - b
        }
        let t = tick / Double(steps) * 1e6, st = step / Double(steps) * 1e6
        MotionLog.write(String(format: "MOTIONPERF %@: brain.tick %.1f us, sim.step %.1f us per fixed step (tick = %.1f %% of the step)", name, t, st, 100 * t / st))
        XCTAssertLessThan(t, 1500, "the brain stays well under a millisecond-and-a-half per step")
    }

    func testBrainTickCost() {
        measure("idle studio") { _ in }
        measure("idle game (pivot + planted feet)", game: true) { _ in }
        measure("walk") { $0.brain.request(.goTo($0.root + SIMD2(0, 3))) }
        measure("march") { $0.brain.startStepping(seconds: 6, sim: $0.sim) }
        measure("wave", steps: 120) { $0.brain.request(.wave) }
        measure("Call (game)", game: true) { $0.brain.requestNow(.come(to: SIMD2(0, 1.4))) }
    }

    /// The bean override costs: brain.tick (targets + bean vertices) plus the extra work inside Skinner.update, per fixed step.
    func testBeanOverrideCost() {
        let r = MotionRig(game: false)
        r.renderSamples = false
        r.brain.request(.goTo(r.root + SIMD2(0, 4)))
        r.run(1.2)
        var tick = 0.0, withO = 0.0, withoutO = 0.0
        var n = 0
        for _ in 0..<240 {
            let a = CACurrentMediaTime()
            r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
            let b = CACurrentMediaTime()
            r.sim.step()
            guard r.skinner.beansActive else { continue }
            r.render()
            let c = CACurrentMediaTime()
            r.render()
            let d = CACurrentMediaTime()
            let keep = r.skinner.beanBlend
            r.skinner.beanBlend = 0
            let e = CACurrentMediaTime()
            r.render()
            let f = CACurrentMediaTime()
            r.skinner.beanBlend = keep
            tick += b - a; withO += d - c; withoutO += f - e; n += 1
        }
        XCTAssertGreaterThan(n, 100)
        let t = tick / Double(n) * 1e6, extra = (withO - withoutO) / Double(n) * 1e6
        MotionLog.write(String(format: "MOTIONPERF beans: brain.tick %.1f us + override in Skinner.update %.1f us = %.1f us per step (budget 100 us)", t, extra, t + extra))
        XCTAssertLessThan(t + extra, 100)
    }
}
