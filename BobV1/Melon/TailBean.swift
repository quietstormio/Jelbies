//
//  TailBean.swift
//  Pip's tail: a short plump teardrop that is part of the BODY render mesh, like the foot beans (so it is drawn by the same body skin shader: the same
//  colour, fuzz and crinkle texture, no seam). Its wide base is buried in the lower back; it lifts to a round tip. The block sits after the foot beans in
//  the body index range and is skinned like any body vertex (embedded in the sim tets at its rest pose). Skinner collapses it onto its base pole (zero-area,
//  invisible) for every Jelly but Pip, and sways / wags it for Pip (Skinner.applyTail). The art layer's spikes along its top (PipSpikes) read `shape`.
//  Vertex layout: base pole, `rings` rings of `around` vertices (body rings, then tip-cap rings), tip pole.
//

import Foundation
import simd

nonisolated enum TailBean {
    static let around = 24, bodyRings = 12, capRings = 5
    static var rings: Int { bodyRings + capRings }
    static var vertexCount: Int { 2 + around * rings }

    static func triangles(firstVertex f: Int) -> [UInt32] {
        var t: [UInt32] = []
        func ring(_ r: Int, _ j: Int) -> UInt32 { UInt32(f + 1 + around * r + (j % around)) }
        let bottom = UInt32(f), top = UInt32(f + vertexCount - 1)
        for j in 0..<around { t += [bottom, ring(0, j), ring(0, j + 1)] }
        for r in 0..<(rings - 1) {
            for j in 0..<around {
                t += [ring(r, j), ring(r + 1, j), ring(r, j + 1)]
                t += [ring(r, j + 1), ring(r + 1, j), ring(r + 1, j + 1)]
            }
        }
        for j in 0..<around { t += [top, ring(rings - 1, j + 1), ring(rings - 1, j)] }
        return t
    }

    /// The tail's centre line (y-z plane, rest coordinates) and radius profile.
    struct Shape {
        var root: SIMD3<Double>          // where the centre line leaves the back surface
        var table: [SIMD3<Double>]       // centre line samples every `step`, from inside the body (t = 0) to the tip-cap start (t = length)
        var step: Double
        var length: Double, sink: Double, tipR: Double, baseR: Double, xs: Double
        func point(_ t: Double) -> SIMD3<Double> {
            let f = min(max(t, 0), length) / step, i = min(Int(f), table.count - 2), a = f - Double(i)
            return table[i] * (1 - a) + table[i + 1] * a
        }
        func tangent(_ t: Double) -> SIMD3<Double> {
            let e = step * 0.5
            return simd_normalize(point(min(t + e, length)) - point(max(t - e, 0)))
        }
        func radius(_ t: Double) -> Double {
            let u = min(max(t / length, 0), 1)
            return tipR + (baseR - tipR) * pow(1 - u, 1.25)
        }
        /// The point on the top ridge and the way up (perpendicular to the centre line) at `t`.
        func ridge(_ t: Double) -> (p: SIMD3<Double>, up: SIMD3<Double>, r: Double) {
            let tg = tangent(t)
            var up = SIMD3<Double>(0, 1, 0); up -= tg * simd_dot(up, tg)
            up = simd_normalize(up)
            return (point(t), up, radius(t))
        }
    }

    static let shape: Shape = {
        let y0 = 0.39 * 1.3458                                           // the lower back, 30% of his height
        var lo = -1.2, hi = 0.0
        for _ in 0..<50 { let m = (lo + hi) / 2; if BobForm.sdf(SIMD3(0, y0, m)) > 0 { lo = m } else { hi = m } }
        let root = SIMD3(0, y0, hi)
        var xlo = 0.0, xhi = 1.2
        for _ in 0..<50 { let m = (xlo + xhi) / 2; if BobForm.sdf(SIMD3(m, 0.55, 0)) > 0 { xhi = m } else { xlo = m } }
        let width = 2 * xlo
        let tipR = 0.075, sink = 0.17
        let vis = 0.34 * width - tipR                                    // surface -> start of the round tip cap
        let length = sink + vis
        let step = 0.004
        var table: [SIMD3<Double>] = []
        var cur = root + SIMD3(0, 0, sink)
        var t = 0.0
        while t <= length + step {
            table.append(cur)
            let u = max(0, (t - sink) / vis)
            let ang = (20 + 36 * pow(u, 1.1)) * Double.pi / 180           // nearly level at the base, lifting up to a ~42 degree tip
            cur += SIMD3(0, sin(ang), -cos(ang)) * step
            t += step
        }
        return Shape(root: root, table: table, step: step, length: length, sink: sink, tipR: tipR, baseR: 0.175, xs: 0.85)
    }()

    /// Rest-space vertices and outward normals.
    static let local: (pos: [SIMD3<Double>], nrm: [SIMD3<Double>]) = {
        let s = shape
        var pos: [SIMD3<Double>] = [], nrm: [SIMD3<Double>] = []
        let side = SIMD3<Double>(1, 0, 0)
        func ring(_ c: SIMD3<Double>, _ tg: SIMD3<Double>, _ rad: Double, along: Double, across: Double) {
            let v = simd_normalize(simd_cross(tg, side))
            for j in 0..<around {
                let ph = 2 * Double.pi * Double(j) / Double(around)
                let radial = side * (cos(ph) * s.xs) + v * sin(ph)
                let radialN = simd_normalize(side * (cos(ph) / s.xs) + v * sin(ph))
                pos.append(c + radial * rad); nrm.append(simd_normalize(radialN * across + tg * along))
            }
        }
        pos.append(s.point(0)); nrm.append(-s.tangent(0))
        for k in 1...bodyRings {
            let t = s.length * Double(k) / Double(bodyRings)
            let dr = (s.radius(min(t + 0.004, s.length)) - s.radius(max(t - 0.004, 0))) / (min(t + 0.004, s.length) - max(t - 0.004, 0))
            let a = atan(-dr)
            ring(s.point(t), s.tangent(t), s.radius(t), along: sin(a), across: cos(a))
        }
        let tc = s.point(s.length), tt = s.tangent(s.length)
        for j in 1...capRings {
            let phi = Double.pi / 2 * Double(j) / Double(capRings + 1)
            ring(tc + tt * (s.tipR * sin(phi)), tt, s.tipR * cos(phi), along: sin(phi), across: cos(phi))
        }
        pos.append(tc + tt * s.tipR); nrm.append(tt)
        return (pos, nrm)
    }()

    static let localF: [SIMD3<Float>] = local.pos.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }

    /// Three egg vertices (indices) around the tail's root on the lower back: the tail is carried rigidly by their skinned frame (Skinner.applyTail),
    /// not embedded in the sim tets (a block this far outside the egg shreds under the extrapolated weights).
    static func landmarks(rest: [Float], eggLimit: Int) -> [Int] {
        let y0 = Float(shape.root.y), zb = Float(shape.root.z)
        let targets = [SIMD3<Float>(0.28, y0, zb * 0.82), SIMD3<Float>(-0.28, y0, zb * 0.82), SIMD3<Float>(0, y0 + 0.30, zb * 0.9)]
        return targets.map { t in
            var best = 0, bd = Float.infinity
            for v in 0..<min(eggLimit, rest.count / 3) {
                let d = simd_distance_squared(SIMD3(rest[3 * v], rest[3 * v + 1], rest[3 * v + 2]), t)
                if d < bd { bd = d; best = v }
            }
            return best
        }
    }
}
