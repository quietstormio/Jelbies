//
//  BlobMotion.swift
//  Pose / limb helpers for Bob's brain (BlobBrain.swift). Nothing here changes his rest shape: it only computes
//  temporary targets for existing sim particles (the SimAppendage arm / foot chains) and a scripted rigid pose for
//  the attractor. Everything is released again afterwards, so the soft body settles back to its rest form.
//

import Foundation
import simd

func yawQuat(_ y: Float) -> simd_quatf { simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0)) }
func wrapAngle(_ a: Float) -> Float {
    var d = a
    while d > .pi { d -= 2 * .pi }
    while d < -.pi { d += 2 * .pi }
    return d
}
@inline(__always) func smooth01(_ x: Float) -> Float { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }

/// One arm as a swingable tube. The 9 chain particles (3 stations x outer / front / back, root -> tip) get targets
/// computed from a handful of parameters; at the rest parameters the targets equal the built rest positions.
struct ArmRig {
    let side: Float
    let particles: [Int]
    private let shoulder: SIMD3<Float>       // armTop (rest frame)
    /// Rest parameters (angle from straight up, tube length, radii).
    static let restAngle: Float = {
        let d = BobForm.armTip - BobForm.armTop
        return Float(atan2(abs(d.x), d.y))
    }()
    static let restLength: Float = Float(simd_length(BobForm.armTip - BobForm.armTop))
    static let restRadii = SIMD2<Float>(Float(BobForm.armTopR), Float(BobForm.armTipR))

    init?(sim: SoftBody, side: Int) {
        guard let a = sim.appendages.first(where: { $0.kind == .arm && $0.side == side }), a.particles.count == 9 else { return nil }
        self.side = Float(side)
        particles = a.particles
        shoulder = SIMD3<Float>(Float(side) * Float(BobForm.armTop.x), Float(BobForm.armTop.y), Float(BobForm.armTop.z))
    }

    /// Body-frame (rest coordinates) target of every chain particle for: tube axis angle `a` from straight up toward
    /// outward (rest ~ 167 deg = hanging down), tube length `len`, root / tip radius.
    func targets(angle a: Float, length len: Float, rTop: Float, rTip: Float) -> [SIMD3<Float>] {
        let dir = SIMD3<Float>(side * sinf(a), cosf(a), 0)
        let da = a - Self.restAngle
        let perp = SIMD3<Float>(side * cosf(da), -sinf(da), 0)
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(9)
        for k in 0..<3 {
            let s = Float(k) * 0.5
            let c = shoulder + dir * (len * s)
            let r = rTop + (rTip - rTop) * s
            let rz = r / Float(BobForm.armFlatten)
            out.append(c + perp * (r * 1.2))
            out.append(c + perp * (r * 0.25) + SIMD3(0, 0, rz * 0.85))
            out.append(c + perp * (r * 0.25) - SIMD3(0, 0, rz * 0.85))
        }
        return out
    }
}

/// The wave's timeline: seconds since the wave began -> path parameter s of `ArmPath.wave` (0 = resting arm, 0.4 = arm out,
/// 1 = arm up). Only s drives the arm's shape; nothing is lerped in time. `duration` includes the retract.
struct WaveScript {
    static let raise: Float = 0.45
    static let swings = 3
    static let hz: Float = 1.5
    static var swingTime: Float { Float(swings) / hz }
    static let retract: Float = 0.5
    static var duration: Float { raise + swingTime + retract }
    static let outS: Float = 0.4, upS: Float = 1.0

    static func s(at t: Float) -> Float {
        if t < raise { return outS * smooth01(t / raise) }
        let ts = t - raise
        if ts < swingTime { return (outS + upS) / 2 - (upS - outS) / 2 * cosf(2 * .pi * hz * ts) }
        return outS * (1 - smooth01((ts - swingTime) / retract))
    }
    /// 0...1 how far the arm is out (drives the lean away from it and the bounce).
    static func extend(at t: Float) -> Float { min(1, s(at: t) / outS) }

    /// Happy squint: eyes narrow in the middle of the wave.
    static func eyeOpenness(at t: Float) -> Float {
        let c = raise + swingTime * 0.5
        let w = 1 - smooth01((abs(t - c) - 0.25) / 0.35)
        return 1 - 0.78 * w
    }
}

/// Alternating foot steps: while `stepping`, one foot sole lifts a little and moves forward, then the other
/// (~2 steps/s). Provides the sway and bob that go with it.
struct FootStepper {
    var clock: Float = 0               // integer part = step index, fraction = progress through the step
    var stepping = false
    var wantStep = false
    var rate: Float = 2.0              // steps per second
    var lift: Float = 0.07
    var forward: Float = 0.10
    var firstSide: Float = 1

    /// Advance; returns false once the last swing finished after `wantStep` went false.
    mutating func advance(_ dt: Float) {
        if !stepping {
            if wantStep { stepping = true; clock = 0 }
            else { return }
        }
        let before = floorf(clock)
        clock += dt * rate
        if floorf(clock) > before && !wantStep { stepping = false; clock = 0; firstSide = -firstSide }
    }

    var swingSide: Float { (Int(floorf(clock)) % 2 == 0) ? firstSide : -firstSide }
    var u: Float { clock - floorf(clock) }
    var swing: Float { stepping ? sinf(.pi * u) : 0 }
}
