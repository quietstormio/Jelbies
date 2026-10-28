//
//  BlobBrain+Turn.swift
//  Responsive turning (user: "it takes a while for them to spin"). Turns stay step-driven (feet attached, no pivoting): what changes is how
//  much heading one step may carry and how fast the step is.
//   - Big turns (> 100 deg) are two quick steps (~0.3 s for 180 deg), with a tiny hop-turn when idle (Pip most often).
//   - Medium turns carry more heading per step; a walk starts while still turning (an arc) instead of rotating on the spot first.
//   - Follow-through: the body leans into the turn, the arms swing out a little.
//   - Personality: Pip quick, Moss smooth (slower, no hop), Lavender floaty with a small overshoot.
//

import Foundation
import simd

extension BlobBrain {
    static let bigTurn: Float = 1.75                     // 100 deg

    /// (rate multiplier on the per-step heading, hop-turn chance, overshoot fraction)
    var turnChar: (rate: Float, hop: Float, over: Float) {
        switch personalityKey {
        case .spines: return (1.25, 0.35, 0)
        case .daisy: return (0.9, 0.0, 0)
        case .wings: return (1.05, 0.35, 0.12)
        default: return (1, 0.3, 0)
        }
    }

    /// Heading carried by the next turning step, plus its step-rate multiplier. `idle`: standing, so a big turn may be a hop-turn.
    func turnPlan(err: Float, idle: Bool) -> (dyaw: Float, rate: Float) {
        let ch = turnChar, base = turnRate * min(max(amplitude, 0.5), 1) * feet.stepTime
        let a = abs(err), sgn: Float = err < 0 ? -1 : 1
        turnHopW = 0
        if a > Self.bigTurn {
            // two quick steps: the first takes about half the turn (never less than the base), the second finishes it
            if idle, (abs(sinf(yaw * 91.7 + Float(hopCount) * 3.1))) < ch.hop { turnHopW = 1; hopCount += 1 }
            let cap = max(a * 0.55, base)
            return (sgn * min(a, cap), 1.5 * (ch.rate > 1 ? 1.1 : (ch.rate < 1 ? 0.9 : 1)))
        }
        let m = base * (a > 0.8 ? 1.6 : 1.25) * ch.rate
        var d = min(a, m)
        if d == a, ch.over > 0, a > 0.4 { d = min(a * (1 + ch.over), a + 0.1) }       // Lavender: a little past, the next step eases back
        return (sgn * d, a > 0.8 ? 1.2 : 1)
    }

    /// Follow-through while a step turns the body: lean into the turn (opposite sway side kept), arms out a touch, a small hop-turn lift.
    func turnFollowThrough() {
        guard feet.active, stepLive, abs(stepYawD) > 0.15 else { return }
        let frac = min(1, abs(stepYawD) / 1.2) * sinf(.pi * feet.stepU)
        let sgn: Float = stepYawD < 0 ? -1 : 1
        roll += sgn * 0.07 * frac
        pitch += 0.03 * frac
        nubTarget = max(nubTarget, amplitude * (1 + 0.25 * frac))
        if turnHopW > 0 {
            let w = sinf(.pi * feet.stepU)
            lift += 0.025 * w
            squash += 0.05 * w - 0.07 * max(0, (feet.stepU - 0.85) / 0.15)
        }
    }
}
