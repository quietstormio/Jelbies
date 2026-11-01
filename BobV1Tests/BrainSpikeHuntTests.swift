import XCTest
import simd
@testable import BobV1

/// Hunts for brain.tick calls that take milliseconds (the phone showed single 30-50 ms calls in the first minute): a roaming game brain runs for 4 simulated minutes and
/// every tick over 2 ms is printed with what the brain was doing. Prints only (the numbers are machine dependent); asserts nothing slower than 25 ms on the Mac.
@MainActor
final class BrainSpikeHuntTests: XCTestCase {
    func testRoamingBrainHasNoMillisecondSpikes() {
        let r = MotionRig(game: true)
        r.brain.warmFeet(r.sim, r.skinner)          // the one-time foot set-up the app now does before the first walk
        r.brain.autonomy = true
        r.brain.wanderRect = (min: SIMD2(-3, -1), max: SIMD2(3, 4))
        var worst = 0.0
        _ = HopDiag.take(steps: 1)
        var lines: [String] = []
        for step in 0..<(60 * 240) {
            let a = CACurrentMediaTime()
            r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
            let ms = (CACurrentMediaTime() - a) * 1000
            r.sim.step()
            if ms > 2 { lines.append(String(format: "SPIKE step %d (%.1f s): %.1f ms, activity %@, script %@, idle %@", step, Double(step) / 60, ms, "\(r.brain.activity)", "\(r.brain.script)".prefix(60) as CVarArg, "\(String(describing: r.brain.idleState.kind))")) }
            worst = max(worst, ms)
        }
        for l in lines { print(l) }
        print("SPIKEHUNT sections (mean ms per step / longest call): " + HopDiag.take(steps: 60 * 240))
        print(String(format: "SPIKEHUNT worst tick %.1f ms, %d ticks over 2 ms", worst, lines.count))
        XCTAssertLessThan(worst, 25)
    }
}
