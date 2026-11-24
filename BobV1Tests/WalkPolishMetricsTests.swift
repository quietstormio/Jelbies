//
//  WalkPolishMetricsTests.swift
//  walk-polish-r1. Numbers for how a gait looks, so the walk can be compared with the run: speed, cadence, planted-foot drift per step (rendered sole), sway (body roll p2p),
//  bob (centroid height p2p), forward lean, arm swing. One line per scenario in the MOTION_LOG ("WPM ..."). Informational: no asserts except that a walk was seen.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WalkPolishMetricsTests: XCTestCase {
    struct Result { var line: String }

    static func measure(_ name: String, _ setup: (MotionRig) -> Void, runOnly: Bool = false, seconds: Float = 10) -> String {
        let r = MotionRig(game: false)
        r.brain.seed = 11
        r.run(0.5)
        var tip0: Float = 0
        do { let q = r.sim.bodyPose(iterations: 4).rotation.act(SIMD3<Float>(0, 0, 1)); tip0 = asinf(max(-1, min(1, q.y))) }
        setup(r)
        var s: [MotionSample] = [], cy: [Float] = [], pitchB: [Float] = [], phi: [[Float]] = [[], []], rootP: [SIMD2<Float>] = [], tilt: [Float] = [], swingFlag: [Bool] = [], stepsStarted = 0
        var lastSide = r.brain.feet.side, lastActive = false
        r.run(seconds, each: {
            let m = r.sample()
            if runOnly ? r.brain.runW > 0.999 : r.brain.activity == .walking {
                s.append(m); cy.append(r.sim.centroid().y); pitchB.append(r.brain.pitch); phi[0].append(r.brain.nubPhi[0]); phi[1].append(r.brain.nubPhi[1])
                rootP.append(SIMD2(r.brain.px, r.brain.pz)); tilt.append(m.tipBack)
            }
            if r.brain.feet.active && (!lastActive || r.brain.feet.side != lastSide) { stepsStarted += 1 }
            lastActive = r.brain.feet.active; lastSide = r.brain.feet.side
        })
        guard s.count > 80 else { return "WPM \(name): no steady gait (\(s.count) samples)" }
        // use the middle 60 % of the samples
        let a = s.count / 5, b = s.count - s.count / 5
        let mid = Array(s[a..<b])
        let H = MotionRig.H
        let dur = mid.last!.t - mid.first!.t
        let speed = simd_length(rootP[b - 1] - rootP[a]) / dur
        // swings (rendered foot more than 0.01 H up) and planted-foot drift
        let th = 0.01 * H
        var drifts: [Float] = [], swings = 0
        for f in 0..<2 {
            var stanceStart: Int?
            for i in 0..<mid.count {
                let down = mid[i].rgap[f] <= th
                if down { if stanceStart == nil { stanceStart = i } }
                else { if let i0 = stanceStart, i - i0 > 6 { drifts.append(simd_length(mid[i - 2].xz[f] - mid[i0 + 2].xz[f])) }; stanceStart = nil; if i > 0 && mid[i - 1].rgap[f] <= th { swings += 1 } }
            }
        }
        let cadence = Float(swings) / dur
        func p2p(_ v: ArraySlice<Float>) -> Float { (v.max() ?? 0) - (v.min() ?? 0) }
        func std(_ v: ArraySlice<Float>) -> Float { let m = v.reduce(0, +) / Float(v.count); return (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Float(v.count)).squareRoot() }
        let roll = mid.map { $0.roll * 57.2958 }
        let rollP2P = roll.max()! - roll.min()!
        let bob = p2p(cy[a..<b])
        let lean = (tilt[a..<b].reduce(0, +) / Float(b - a) - tip0) * 57.2958
        let pit = pitchB[a..<b].reduce(0, +) / Float(b - a) * 57.2958
        let armDeg = (std(phi[0][a..<b]) + std(phi[1][a..<b])) * 0.5 * Float(ArmPath.nubTiltDeg)
        let dm = drifts.isEmpty ? 0 : drifts.reduce(0, +) / Float(drifts.count), dx = drifts.max() ?? 0
        return String(format: "WPM %@: speed %.3f u/s, cadence %.2f swings/s, stride %.3f u/step, planted-foot drift mean %.3f max %.3f u (%.1f / %.1f %% of H) over %d stances, roll p2p %.1f deg, bob p2p %.3f u (%.1f %% H), body tip %+.1f deg vs standing (brain.pitch mean %+.1f deg), arm swing std %.1f deg, steps started %d, polish level %d",
                      name, speed, cadence, speed / max(cadence, 0.01), dm, dx, 100 * dm / H, 100 * dx / H, drifts.count, rollP2P, bob, 100 * bob / H, lean, pit, armDeg, stepsStarted, WalkPolishMetricsTests.level)
    }
    static var level: Int { Int(ProcessInfo.processInfo.environment["WALK_LEVEL"] ?? "0") ?? 0 }

    func testGaitNumbers() {
        func go(_ r: MotionRig) { r.brain.request(.goTo(r.root + SIMD2(0, 16))) }
        MotionLog.write(Self.measure("walk_roam", go))
        MotionLog.write(Self.measure("walk_plain", { r in r.brain.walkBoostK = 1.0; go(r) }))
        MotionLog.write(Self.measure("walk_small", { r in r.brain.amplitude = 0.7; go(r) }))
        MotionLog.write(Self.measure("run", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.run, r.sim) }, runOnly: true, seconds: 8))
    }
}
