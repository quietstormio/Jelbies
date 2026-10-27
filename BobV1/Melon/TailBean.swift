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
    static let around = 24, bodyRings = 30, capRings = 5
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

    /// The tail's centre line (rest coordinates, 3D: it sweeps down and back, then curves sideways along the floor) and radius profile.
    struct Shape {
        var root: SIMD3<Double>          // where the centre line leaves the back surface
        var table: [SIMD3<Double>]       // centre line samples every `step`, from inside the body (t = 0) to the tip-cap start (t = length)
        var step: Double
        var length: Double, sink: Double, tipR: Double, baseR: Double, xs: Double, ys: Double, width: Double
        func point(_ t: Double) -> SIMD3<Double> {
            let f = min(max(t, 0), length) / step, i = min(Int(f), table.count - 2), a = f - Double(i)
            return table[i] * (1 - a) + table[i + 1] * a
        }
        func tangent(_ t: Double) -> SIMD3<Double> {
            let e = step * 0.5
            return simd_normalize(point(min(t + e, length)) - point(max(t - e, 0)))
        }
        /// Half-width at `t` (the vertical half-height is `ys` of it): a smooth taper to a soft point, with a fillet flare where it grows out of the back.
        func radius(_ t: Double) -> Double {
            if t < sink { let a = max(t, 0) / sink; return radius(sink) * (0.45 + 0.55 * a * a) }     // buried: narrows so it never pokes out of the sides
            let u = min(t / length, 1)
            let uu = min(max((t - sink) / (length - sink), 0), 1)
            // chunky plush profile (half-widths as fractions of the body width at 0 / 40% / 75% / 100% of the visible length), smooth between the knots
            let knots: [(Double, Double)] = [(0, 0.21), (0.4, 0.13), (0.75, 0.08), (1, 0.03)]
            var taper = knots[3].1 * width
            for k in 1..<knots.count where uu <= knots[k].0 {
                let a = knots[k - 1], b = knots[k], f = (uu - a.0) / (b.0 - a.0), sm = f * f * (3 - 2 * f)
                taper = (a.1 + (b.1 - a.1) * (0.5 * f + 0.5 * sm)) * width
                break
            }
            let flare = 1 + 0.10 * exp(-(t - sink) / 0.2) * (1 - u)
            return taper * flare
        }
        /// Cross-section frame at `t`: sideways (+x side) and the way up, both perpendicular to the centre line.
        func frame(_ t: Double) -> (side: SIMD3<Double>, up: SIMD3<Double>) {
            let tg = tangent(t)
            let side = simd_normalize(simd_cross(tg, SIMD3(0, 1, 0)))
            return (side, simd_normalize(simd_cross(side, tg)))
        }
        /// The point on the top ridge and the way up at `t`.
        func ridge(_ t: Double) -> (p: SIMD3<Double>, up: SIMD3<Double>, r: Double) {
            let f = frame(t), r = radius(t) * ys
            return (point(t), f.up, r)
        }
    }

    static let shape: Shape = {
        let y0 = 0.66                                                    // the lower back
        var lo = -1.2, hi = 0.0
        for _ in 0..<50 { let m = (lo + hi) / 2; if BobForm.sdf(SIMD3(0, y0, m)) > 0 { lo = m } else { hi = m } }
        let root = SIMD3(0, y0, hi)
        var xlo = 0.0, xhi = 1.2
        for _ in 0..<50 { let m = (xlo + xhi) / 2; if BobForm.sdf(SIMD3(m, 0.55, 0)) > 0 { xhi = m } else { xlo = m } }
        let width = 2 * xlo
        let tipR = 0.04, sink = 0.26, ys = 1.0
        let baseR = width * 0.21                                             // about a third of the body width across
        let vis = 0.92 * width - tipR                                      // surface -> start of the round tip cap
        let length = sink + vis
        let step = 0.004
        var shape = Shape(root: root, table: [], step: step, length: length, sink: sink, tipR: tipR, baseR: baseR, xs: 1.0, ys: ys, width: width)
        var table: [SIMD3<Double>] = []
        var cur = root + SIMD3(0, 0, sink)
        var t = 0.0
        while t <= length + step {
            table.append(cur)
            let u = max(0, (t - sink) / vis)
            let psi = 140 * pow(u, 1.1) * Double.pi / 180                // heading: straight back, then curving sideways (+x, the Jelbie's left)
            let floorY = shape.radius(t) * ys + Double(restFloor) + 0.02 + 0.07 * pow(max(0, (u - 0.8) / 0.2), 2)                     // rest on the floor
            let th = -min(0.95, atan2(max(cur.y - floorY, 0), 0.12))      // sweeps down, easing onto the floor
            cur += SIMD3(sin(psi) * cos(th), sin(th), -cos(psi) * cos(th)) * step
            cur.y = max(cur.y, floorY)
            t += step
        }
        shape.table = table
        return shape
    }()

    /// Rest-space vertices and outward normals.
    static let local: (pos: [SIMD3<Double>], nrm: [SIMD3<Double>]) = {
        let s = shape
        var pos: [SIMD3<Double>] = [], nrm: [SIMD3<Double>] = []
        func ringAt(_ t: Double, _ c: SIMD3<Double>, _ tg: SIMD3<Double>, _ rad: Double, along: Double, across: Double) {
            let f = s.frame(min(t, s.length))
            let side = f.side
            let v = simd_normalize(simd_cross(tg, side))
            for j in 0..<around {
                let ph = 2 * Double.pi * Double(j) / Double(around)
                let radial = side * (cos(ph) * s.xs) + v * (sin(ph) * s.ys)
                let radialN = simd_normalize(side * (cos(ph) / s.xs) + v * (sin(ph) / s.ys))
                pos.append(c + radial * rad); nrm.append(simd_normalize(radialN * across + tg * along))
            }
        }
        pos.append(s.point(0)); nrm.append(-s.tangent(0))
        for k in 1...bodyRings {
            let t = s.length * Double(k) / Double(bodyRings)
            let dr = (s.radius(min(t + 0.004, s.length)) - s.radius(max(t - 0.004, 0))) / (min(t + 0.004, s.length) - max(t - 0.004, 0))
            let a = atan(-dr)
            ringAt(t, s.point(t), s.tangent(t), s.radius(t), along: sin(a), across: cos(a))
        }
        let tc = s.point(s.length), tt = s.tangent(s.length)
        for j in 1...capRings {
            let phi = Double.pi / 2 * Double(j) / Double(capRings + 1)
            ringAt(s.length, tc + tt * (s.tipR * sin(phi)), tt, s.tipR * cos(phi), along: sin(phi), across: cos(phi))
        }
        pos.append(tc + tt * s.tipR); nrm.append(tt)
        return (pos, nrm)
    }()

    /// The rest-space height of the floor under the tail (the egg sits about this much below its rest y once settled).
    static let restFloor: Float = 0.14
    static let rootF = SIMD3<Float>(Float(shape.root.x), Float(shape.root.y), Float(shape.root.z))
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
