//
//  BlobDine.swift
//  Pure value-type helpers of the dining motion (the brain owns the state): where a piece sits on the nub, the body-led reach solver
//  (turn / pitch / roll / crouch about the planted feet until the nub tip meets the piece: no arm IK, the arm path only has ONE parameter),
//  and the one shared timeline of a bite (grab beat + chew beat = DiningTiming.biteDuration) with the shared spring, squash pulse and
//  mouth chomp. Nothing here touches the soft body.
//

import Foundation
import simd

/// The shared "spring" ease (overshoots ~6 % and settles), used by every dining beat (same family as the pop curve of the props).
nonisolated enum MotionCurve {
    /// 0 -> 1 with a slight overshoot (critically-ish damped): u in 0...1.
    static func spring(_ u: Float) -> Float {
        let x = min(max(u, 0), 1) - 1
        return 1 + 2.2 * x * x * x + 1.2 * x * x
    }
    /// The shared squash pulse: a quick dip of `amplitude` with one soft rebound, u in 0...1 (0 at both ends).
    static func pulse(_ u: Float) -> Float {
        let x = min(max(u, 0), 1)
        return sinf(.pi * x) * (1 - 0.35 * x) * (x < 0.5 ? 1 : 1 - 0.3 * sinf(.pi * (x - 0.5) * 2))
    }
    /// Squash pulse depth shared by bites, gulps and the happy bounce (landings use it too).
    static let pulseDepth: Float = 0.055
}

nonisolated struct ReachPose: Equatable {
    var twist: Float = 0        // extra heading about the vertical (rad), the body turns toward the arm
    var pitch: Float = 0        // extra pitch on top of the idle tip-back (+ = forward)
    var roll: Float = 0
    var squash: Float = 1       // < 1 = crouch
}

nonisolated enum DineGeometry {
    /// Where a held piece sits on the nub (rest coordinates, +x arm convention) when the arm is at path parameter `s`: at the end of the tip ball (the piece sits on the nub's tip).
    static func holdPoint(path: ArmPath, s: Double) -> SIMD3<Float> {
        let g = path.geom(at: s)
        let d = simd_normalize(g.B - g.A)
        let p = g.B + d * (g.r2 * 1.0)
        return SIMD3(Float(p.x), Float(p.y), Float(p.z))
    }
    static func mirrored(_ p: SIMD3<Float>, side: Int) -> SIMD3<Float> { SIMD3(Float(side) * p.x, p.y, p.z) }

    /// The mouth's centre on the front of the body in rest coordinates: the shader draws it at x = 0, y = 0.665 (Shaders.metal), z = the surface there.
    static let mouthRest: SIMD3<Float> = {
        var lo = 0.0, hi = 1.5
        for _ in 0..<40 {
            let mid = 0.5 * (lo + hi)
            if BobForm.bodySDF(SIMD3(0, 0.665, mid)) < 0 { lo = mid } else { hi = mid }
        }
        return SIMD3(0, 0.665, Float(0.5 * (lo + hi)))
    }()

    /// Grip-to-bite length of the fork (DiningModels.forkTip.z) and the bite's lift above the tine line (forkTip.y).
    static let forkLength: Float = 0.27
    static let forkBiteLift: Float = 0.04
    /// Direction the tines point in the BODY frame at arm parameter `s`: tines UP when the fork pops into his hand (s = 0); the wrist turns it forward
    /// and down to stab as the arm swings to the grab (s = grabS); as the arm rises the tines turn toward his mouth (s = 1).
    static func forkDir(s: Float, side: Int, grabS: Float) -> SIMD3<Float> {
        let up = simd_normalize(SIMD3<Float>(-Float(side) * 0.15, 1, 0.35))
        let reach = simd_normalize(SIMD3<Float>(-Float(side) * 0.25, -0.35, 1))
        let eat = simd_normalize(mouthRest - mirrored(holdPoint(path: .nubToMouth, s: 1), side: side))
        let u0 = smooth01(s / max(grabS, 1e-3))
        let u1 = smooth01((s - grabS) / max(1 - grabS, 1e-3))
        let d0 = simd_normalize(up + (reach - up) * u0)
        return simd_normalize(d0 + (eat - d0) * u1)
    }

    /// Rigid world position of rest point `r` under pose (rotation `q`, crouch `sy`) with rest point `m` pinned at world `w`.
    static func world(_ r: SIMD3<Float>, q: simd_quatf, sy: Float, m: SIMD3<Float>, w: SIMD3<Float>, c0: SIMD3<Float>) -> SIMD3<Float> {
        let R = simd_float3x3(q), sxz = 1 / sy.squareRoot()
        let a = w - R * SIMD3((m.x - c0.x) * sxz, (m.y - c0.y) * sy, (m.z - c0.z) * sxz)
        return a + R * SIMD3((r.x - c0.x) * sxz, (r.y - c0.y) * sy, (r.z - c0.z) * sxz)
    }

    /// World position of rest point `hold` under pose `p` (the same model `solveReach` fits).
    static func reachTip(hold: SIMD3<Float>, pose p: ReachPose, m: SIMD3<Float>, w: SIMD3<Float>, c0: SIMD3<Float>, yaw: Float, pitchBase: Float) -> SIMD3<Float> {
        let q = yawQuat(yaw + p.twist) * simd_quatf(angle: p.pitch + pitchBase, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: p.roll, axis: SIMD3(0, 0, 1))
        return world(hold, q: q, sy: p.squash, m: m, w: w, c0: c0)
    }

    /// Body-led reach: finds turn / pitch / roll (crouch fixed) so `hold` (the piece point on the nub, rest coordinates) meets `target`
    /// (world), pivoting on `m` (rest) pinned at `w` (world). Coarse grid + shrinking coordinate descent; returns the pose and the miss (u).
    static func solveReach(hold: SIMD3<Float>, target: SIMD3<Float>, m: SIMD3<Float>, w: SIMD3<Float>, c0: SIMD3<Float>,
                           yaw: Float, pitchBase: Float, crouch: Float, side: Int, fast: Bool = false, start: ReachPose? = nil, pitchMax: Float = 0.5, rollMax: Float = 0.6) -> (pose: ReachPose, miss: Float) {
        func tip(_ p: ReachPose) -> SIMD3<Float> {
            let q = yawQuat(yaw + p.twist) * simd_quatf(angle: p.pitch + pitchBase, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: p.roll, axis: SIMD3(0, 0, 1))
            return world(hold, q: q, sy: p.squash, m: m, w: w, c0: c0)
        }
        func cost(_ p: ReachPose) -> Float {
            let d = tip(p) - target
            return simd_length_squared(d) + 0.004 * (p.twist * p.twist + p.roll * p.roll) + 0.002 * p.pitch * p.pitch
        }
        var best = start ?? ReachPose(twist: 0, pitch: 0, roll: 0, squash: crouch), bc = cost(best)
        if start != nil { best.squash = crouch; bc = cost(best) }
        var tw: Float = start != nil ? 9 : -1.6          // (a warm start skips the coarse grid)
        let gT: Float = fast ? 0.2 : 0.1, gP: Float = fast ? 0.2 : 0.1, gR: Float = fast ? 0.3 : 0.1
        // the roll samples are symmetric about 0 (a grid that started at -rollMax with a step that does not divide it favoured one sign: the left end diner missed where the right end did not)
        let rn = Int((rollMax / gR + 1e-4).rounded(.down))
        let rolls: [Float] = rn >= 1 ? (-rn...rn).map { Float($0) * gR } : [-rollMax, 0, rollMax]
        while tw <= 1.6 {
            var pt: Float = -0.3
            while pt <= pitchMax {
                for rl in rolls {
                    let p = ReachPose(twist: tw, pitch: pt, roll: rl, squash: crouch)
                    let c = cost(p)
                    if c < bc { bc = c; best = p }
                }
                pt += gP
            }
            tw += gT
        }
        let pCap: Float = pitchMax == 0.5 ? 0.6 : pitchMax, rCap: Float = rollMax == 0.6 ? 0.65 : rollMax          // (the defaults keep the old limits exactly)
        var step: Float = start != nil ? 0.03 : 0.05
        for _ in 0..<(start != nil ? 8 : 14) {
            var improved = false
            for k in 0..<3 {
                for dir in [Float(-1), 1] {
                    var p = best
                    switch k { case 0: p.twist += dir * step; case 1: p.pitch = min(pCap, max(-0.35, p.pitch + dir * step)); default: p.roll = min(rCap, max(-rCap, p.roll + dir * step)) }
                    let c = cost(p)
                    if c < bc { bc = c; best = p; improved = true }
                }
            }
            if !improved { step *= 0.5 }
        }
        return (best, simd_length(tip(best) - target))
    }
}
