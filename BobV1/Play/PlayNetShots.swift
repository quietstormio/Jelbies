//
//  PlayNetShots.swift
//  Capture / test aid for the play net (`-PlayNetShots <runs>`, dev builds in the simulator only): once Play is up with the net, the play ball is launched from fixed points on a fixed
//  list of paths, one line per shot: `[playnet] shot=<name> result=goal|post|bar|over|wide expect=<...> ok=<0|1>`. The path list is shared with PlayNetTests (the same names and numbers).
//

import Foundation
import simd

/// One fixed shot: where it starts (relative to the net: x in the mouth's half widths, z in front of the mouth plane, y height), what it aims at on the mouth plane and how long it flies.
struct PlayNetShot {
    var name: String
    var start: SIMD3<Float>          // x in world offsets from the net's centre x; y height; z in front of the mouth plane
    var aim: SIMD3<Float>            // the same, on the mouth plane (z ignored)
    var flight: Float
    var expect: String
    /// A slow roll: the ball starts on the floor with this speed toward the mouth instead (the path above is ignored).
    var roll: Float = 0

    /// The launch (world position, velocity) for a net.
    func launch(_ n: TossNet) -> (from: SIMD3<Float>, v: SIMD3<Float>) {
        let from = SIMD3(n.centre.x + start.x, start.y, n.mouthZ + start.z)
        if roll > 0 { return (from, SIMD3(0, 0, -roll)) }
        let to = SIMD3(n.centre.x + aim.x, aim.y, n.mouthZ)
        return (from, TossAim.ballistic(from: from, to: to, flight: flight * TossTuning.slow))
    }

    /// The list: into the middle of the mouth, low into each corner, high into each corner under the bar, onto each post, onto the bar, over the bar, wide on each side, a slow roll in.
    static func list(innerHalf w: Float, radius r: Float) -> [PlayNetShot] {
        let barY: Float = PlayNetTuning.barTop * PlayNetTuning.scale - PlayNetTuning.barRadius * PlayNetTuning.scale          // the tube's centre
        let corner = w - r - 0.12
        return [
            .init(name: "middle", start: SIMD3(0, 0.5, 0.6), aim: SIMD3(0, 0.55, 0), flight: 0.22, expect: "goal"),
            .init(name: "low-left", start: SIMD3(-0.4, 0.4, 0.6), aim: SIMD3(-corner, r + 0.03, 0), flight: 0.22, expect: "goal"),
            .init(name: "low-right", start: SIMD3(0.4, 0.4, 0.6), aim: SIMD3(corner, r + 0.03, 0), flight: 0.22, expect: "goal"),
            .init(name: "high-left", start: SIMD3(-0.4, 0.5, 0.6), aim: SIMD3(-corner, PlayNetTuning.barUnder * PlayNetTuning.scale - r - 0.14, 0), flight: 0.22, expect: "goal"),
            .init(name: "high-right", start: SIMD3(0.4, 0.5, 0.6), aim: SIMD3(corner, PlayNetTuning.barUnder * PlayNetTuning.scale - r - 0.14, 0), flight: 0.22, expect: "goal"),
            .init(name: "post-left", start: SIMD3(-0.6, 0.5, 0.6), aim: SIMD3(-(w + 0.5 * (PlayNetTuning.scale * GoalGeometry.outerHalfX - w)), 0.55, 0), flight: 0.22, expect: "post"),
            .init(name: "post-right", start: SIMD3(0.6, 0.5, 0.6), aim: SIMD3(w + 0.5 * (PlayNetTuning.scale * GoalGeometry.outerHalfX - w), 0.55, 0), flight: 0.22, expect: "post"),
            .init(name: "bar", start: SIMD3(0, 0.6, 0.6), aim: SIMD3(0, barY, 0), flight: 0.22, expect: "bar"),
            .init(name: "over", start: SIMD3(0, 1.9, 2.2), aim: SIMD3(0, 2.1, 0), flight: 0.5, expect: "over"),
            .init(name: "wide-left", start: SIMD3(-2.0, 0.5, 0.6), aim: SIMD3(-2.1, 0.55, 0), flight: 0.25, expect: "wide"),
            .init(name: "wide-right", start: SIMD3(2.0, 0.5, 0.6), aim: SIMD3(2.1, 0.55, 0), flight: 0.25, expect: "wide"),
            .init(name: "slow-roll", start: SIMD3(0.3, r, 0.6), aim: .zero, flight: 0, expect: "goal", roll: 2.0),
        ]
    }
}

#if targetEnvironment(simulator)
extension PlayToss {
    /// Runs the list `runs` times (waiting for each ball to come back to the hand). Logs `[playnet] shot=... result=...`.
    @MainActor
    func runNetShots(runs: Int, only: String? = nil) async {
        func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
        guard netUp, let n = net.spec else { NSLog("[playnet] shots: no net"); return }
        for run in 0..<max(runs, 1) {
            for s in PlayNetShot.list(innerHalf: n.innerHalf, radius: ball.radius) where only == nil || s.name == only {
                var waited = 0.0
                while phase != .inHand, active, waited < 30 { await sleep(0.1); waited += 0.1 }
                guard active, let spec = net.spec else { return }
                await sleep(only == nil ? 2.5 : 1.0)          // (the Jelmiko walk back to their places first)
                let (from, v) = s.launch(spec)
                NSLog("[playnet] launch shot=%@", s.name)
                let launchClock = clock
                launch(from: from, velocity: v)
                var t = 0.0, overSeen = false
                while net.first == nil, t < 6, active {
                    await sleep(0.03); t += 0.03
                    if let sp = net.spec, sp.contains(SIMD2(ball.pos.x, ball.pos.z)), ball.pos.y - ball.radius > sp.barTop { overSeen = true }
                }
                let result = net.first ?? (overSeen ? "over" : "wide")
                NSLog("[playnet] shot=%@ result=%@ expect=%@ ok=%d run=%d t=%.2f", s.name, result, s.expect, result == s.expect ? 1 : 0, run, t)
                var w2 = 0.0
                while phase != .inHand, active, w2 < 30 { await sleep(0.1); w2 += 0.1 }          // (keep-out round: seconds from the launch to the ball back in the hand, scoring or not)
                NSLog("[playnet] shot-back shot=%@ launch-to-hand=%.1f s hand=%d", s.name, clock - launchClock, phase == .inHand ? 1 : 0)
            }
        }
        NSLog("[playnet] shots done closest-body-to-footprint=%.2f dead-returns=%d keepout-body-samples=%d", net.minBodyDist, net.deadReturns, net.keepOutSamples)
    }
}
#endif
