import XCTest
import simd
@testable import BobV1

/// The phone showed brain-stage p95 of 21-23 ms against a mean of a few ms. This rig runs 3 roaming game brains (makeRoom every 0.25 s as the stage does) for
/// 120 simulated seconds, times each fixed step's brain work (makeRoom + the three ticks, not the XPBD step) and prints p50 / p95 / max and the top sub-stages.
@MainActor
final class BrainStallRigTests: XCTestCase {
    func testThreeBodiesRoamingBrainTime() {
        let lab = SocialTests.Lab(n: 3, quiet: false, seed: 77)
        for r in lab.rigs { r.brain.warmFeet(r.sim, r.skinner) }          // the one-time foot set-up the stage does before the first walk
        for _ in 0..<120 { lab.tick(watching: false) }
        PerfProbe.reset(); PerfProbe.on = true
        defer { PerfProbe.on = false }
        _ = HopDiag.take(steps: 1)
        var samples: [Double] = []
        var rigWorst = [Double](repeating: 0, count: 3)
        var makeRoomWorst = 0.0
        let steps = 60 * 120
        var spikes: [String] = []
        for step in 0..<steps {
            let t0 = CACurrentMediaTime()
            lab.snapshot = lab.rigs.map { (pos: GameCare.floorPos($0.brain, $0.sim), walking: $0.brain.activity == .walking || $0.brain.activity == .coming) }
            lab.asideClock += 1.0 / 60
            if lab.asideClock >= 0.25 {
                let m0 = CACurrentMediaTime()
                let p = PerfProbe.begin()
                MelonController.makeRoom(snapshot: lab.snapshot, brains: lab.rigs.map { $0.brain }, cooldown: &lab.aside, dt: lab.asideClock)
                PerfProbe.end("makeRoom", p)
                makeRoomWorst = max(makeRoomWorst, (CACurrentMediaTime() - m0) * 1000)
                lab.asideClock = 0
            }
            for (i, r) in lab.rigs.enumerated() {
                let a = CACurrentMediaTime()
                let p = PerfProbe.begin()
                r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
                PerfProbe.end("brain.tick", p)
                let ms = (CACurrentMediaTime() - a) * 1000
                rigWorst[i] = max(rigWorst[i], ms)
                if ms > 2 { spikes.append(String(format: "SPIKE step %d rig %d: %.1f ms act %@ idle %@ script %@", step, i, ms, "\(r.brain.activity)", "\(String(describing: r.brain.idleState.kind))", String("\(r.brain.script)".prefix(40)))) }
            }
            samples.append((CACurrentMediaTime() - t0) * 1000)
            for r in lab.rigs { r.sim.step(); r.brain.refitBeans(r.sim, r.skinner); r.t += r.sim.stepDt }
        }
        let s = samples.sorted()
        let p50 = s[s.count / 2], p95 = s[Int(Double(s.count) * 0.95)], p99 = s[Int(Double(s.count) * 0.99)]
        print(String(format: "BRAINSTALL step brain time: mean %.3f p50 %.3f p95 %.3f p99 %.3f max %.2f ms | makeRoom worst %.2f | per-rig worst %@", samples.reduce(0, +) / Double(s.count), p50, p95, p99, s.last!, makeRoomWorst, rigWorst.map { String(format: "%.2f", $0) }.joined(separator: "/")))
        for l in spikes.prefix(40) { print("BRAINSTALL " + l) }
        print("BRAINSTALL probes (sorted by total):\n" + PerfProbe.report)
        print("BRAINSTALL hop parts: " + HopDiag.take(steps: steps))
        XCTAssertLessThan(p95, 6, "brain p95 per fixed step")
    }
}
