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

/// The restyle options for Pip's tail. T3 (0.86 radius, T2's tall pointed spikes) is the SHIPPED default. `current`, T1 and T2 are kept as comparison variants for tests and DEBUG builds.
/// Overridden once per process by the PIPTAIL environment variable (tests) or, in DEBUG builds only, the `-PipTail current|T1|T2|T3` launch argument.
nonisolated enum PipTailVariant: String {
    case current, T1, T2, T3
    static let active: PipTailVariant = {
        func parse(_ s: String) -> PipTailVariant? { PipTailVariant(rawValue: ["T1", "T2", "T3"].contains(s) ? s : s.lowercased()) }
        if let s = ProcessInfo.processInfo.environment["PIPTAIL"], let v = parse(s) { return v }
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "PipTail"), let v = parse(s) { return v }
        #endif
        return .T3
    }()
    /// Tail radius multiplier along the whole length (the body-width knots in TailBean.Shape.radius are scaled by it; tip radius too).
    var radiusScale: Double { switch self { case .current: return 1; case .T1: return 0.80; case .T2: return 0.72; case .T3: return 0.86 } }
    /// Spike height multiplier (PipSpikes), the base width multiplier, and the tip radius as a fraction of the base radius (smaller = pointier, still rounded).
    var spikeHeightScale: Float { switch self { case .current: return 1; case .T1: return 1.5; case .T2: return 1.8; case .T3: return 1.8 } }
    var spikeBaseScale: Float { switch self { case .current: return 1; case .T1: return 1.1; case .T2: return 1.2; case .T3: return 1.2 } }
    var spikeTipSoft: Float { switch self { case .current: return 0.38; case .T1: return 0.34; case .T2: return 0.30; case .T3: return 0.30 } }
    /// Variants that re-flow the back spikes under a crown-enclosing hat (instead of hiding them): every variant but the old `current` look.
    var reflowsUnderHat: Bool { self != .current }
}

/// TEST-ONLY comparison override for the shape of Pip's back where the tail grows out of it (PIPBACK environment variable, read once, no UserDefaults):
/// `now` (default, the Gaussian swell), `none` (no swell), `fillet:<k>` (a smooth-union fillet against the tail tube only, rolloff width k), each with an optional
/// `,len:<f>` suffix that replaces the 0.74 tail-length factor in TailBean.shape (`vis = f * width - tipR`).
nonisolated enum PipBack {
    enum Mode: Equatable { case now, none, fillet(Float) }
    static let parsed: (mode: Mode, len: Double, shift: Double) = {
        guard let raw = ProcessInfo.processInfo.environment["PIPBACK"], !raw.isEmpty else { return (.now, 0.74, 0) }
        var mode = Mode.now, len = 0.74, shift = 0.0
        for part in raw.split(separator: ",") {
            let kv = part.split(separator: ":", maxSplits: 1).map(String.init)
            switch kv[0] {
            case "now": mode = .now
            case "none": mode = .none
            case "fillet": if kv.count == 2, let k = Float(kv[1]), k > 0 { mode = .fillet(k) }
            case "len": if kv.count == 2, let f = Double(kv[1]), f > 0 { len = f }
            case "shift": if kv.count == 2, let f = Double(kv[1]), f >= 0 { shift = f }
            default: break
            }
        }
        return (mode, len, shift)
    }()
    static var mode: Mode { parsed.mode }
    static var lenFactor: Double { parsed.len }
    /// `shift:<d>`: the whole tail (centre line + tube) is translated d toward the body (+z), heights kept; the surface root (`shape.root`, landmarks, pivot) stays where the plain back is.
    static var shift: Double { parsed.shift }
    static var tag: String { ProcessInfo.processInfo.environment["PIPBACK"].flatMap { $0.isEmpty ? nil : $0 } ?? "now" }
}

nonisolated enum TailBean {
    /// Named tail size constants (rest units / fractions of the body width) so contact spheres can follow the tail: radius knots at 0 / 40% / 75% / 100% of the visible
    /// length (half-widths as fractions of the body width) BEFORE `radiusScale`, the scale itself, and the tip cap radius.
    static let radiusKnots: [(Double, Double)] = [(0, 0.21), (0.4, 0.13), (0.75, 0.08), (1, 0.03)]
    static var radiusScale: Double { PipTailVariant.active.radiusScale }
    static var tipRadius: Double { 0.04 * radiusScale }
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
            let knots = TailBean.radiusKnots
            var taper = knots[3].1 * width
            for k in 1..<knots.count where uu <= knots[k].0 {
                let a = knots[k - 1], b = knots[k], f = (uu - a.0) / (b.0 - a.0), sm = f * f * (3 - 2 * f)
                taper = (a.1 + (b.1 - a.1) * (0.5 * f + 0.5 * sm)) * width
                break
            }
            let flare = 1 + 0.55 * exp(-(t - sink) / 0.30) * (1 - u)
            return taper * flare * TailBean.radiusScale
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
        let y0 = 0.47                                                    // the lower back
        var lo = -1.2, hi = 0.0
        for _ in 0..<50 { let m = (lo + hi) / 2; if BobForm.sdf(SIMD3(0, y0, m)) > 0 { lo = m } else { hi = m } }
        let root = SIMD3(0, y0, hi)
        var xlo = 0.0, xhi = 1.2
        for _ in 0..<50 { let m = (xlo + xhi) / 2; if BobForm.sdf(SIMD3(m, 0.55, 0)) > 0 { xhi = m } else { xlo = m } }
        let width = 2 * xlo
        let tipR = TailBean.tipRadius, sink = 0.30, ys = 1.0
        let baseR = width * radiusKnots[0].1 * radiusScale                                             // about a third of the body width across
        let vis = PipBack.lenFactor * width - tipR                                      // surface -> start of the round tip cap
        let length = sink + vis
        let step = 0.004
        var shape = Shape(root: root, table: [], step: step, length: length, sink: sink, tipR: tipR, baseR: baseR, xs: 1.0, ys: ys, width: width)
        var table: [SIMD3<Double>] = []
        var cur = root + SIMD3(0, 0, sink)
        var t = 0.0
        while t <= length + step {
            table.append(cur + SIMD3(0, 0, PipBack.shift))
            let u = max(0, (t - sink) / vis)
            let psi = 140 * pow(u, 1.7) * Double.pi / 180                // heading: straight back, then curving sideways (+x, the Jelbie's left)
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
    static let restFloor: Float = 0.12
    /// The swell on the egg's lower back (Skinner.configureTail): how far (rest units) its vertices are pushed along the tail's start direction, and how widely.
    static let swellHeight: Float = { switch PipBack.mode { case .now: return 0.30; case .none: return 0; case .fillet(let k): return k / 4 } }()
    static let swellSigma: Float = 0.42
    /// The swell fades out over this rest height band (the root is at 0.47 and the tail tube's top meets the back below 0.9, which the swell must keep covering; the head cap the crown fit reads starts at about 1.19): it shapes the lower back
    /// where it becomes the tail, never the head. Unfaded, the Gaussian pushed the back of his head out under the hat, and the per-frame crown fit
    /// (CrownFit) lifted and dropped the hat by up to 0.45 every step: the bouncing head and the broken back of the hat.
    static let swellTopFade: ClosedRange<Float> = 0.9...1.19
    /// The swell's weight at rest point `q` (0...1): a Gaussian about the tail root, faded out above `swellTopFade`. The skin (Skinner.configureTail) and
    /// the spike ridge (PipOptions) share it, so the spikes stay seated on the swelled back.
    static func swellWeight(_ q: SIMD3<Float>) -> Float {
        switch PipBack.mode {
        case .none: return 0
        case .fillet(let k): return filletWeight(q, k: k) * (1 - simd_smoothstep(swellTopFade.lowerBound, swellTopFade.upperBound, q.y))
        case .now: break
        }
        return expf(-simd_length_squared(q - rootF) / (2 * swellSigma * swellSigma)) * (1 - simd_smoothstep(swellTopFade.lowerBound, swellTopFade.upperBound, q.y))
    }
    /// (test-only PIPBACK=fillet:k) Smooth-union fillet against the round tail tube: b = distance from the rest point to the tube surface (centre-line table, radius profile);
    /// the displacement is (k - b)^2 / 4k for 0 <= b < k and k/4 inside the tube, expressed as swellHeight (k/4) * ((k - b) / k)^2 clamped to 0...1.
    static func filletWeight(_ q: SIMD3<Float>, k: Float) -> Float {
        if simd_distance(q, rootF) > 1.3 { return 0 }                                   // cheap early-out: nothing within k of the tube this far from the root
        let s = shape, qd = SIMD3<Double>(Double(q.x), Double(q.y), Double(q.z))
        var b = Double.infinity
        var i = 0
        while i < s.table.count - 1 {                                                  // every 2nd sample (8 mm)
            let t = Double(i) * s.step
            if t > s.length { break }
            b = min(b, simd_distance(qd, s.table[i]) - s.radius(t))
            i += 2
        }
        let w = (Double(k) - b) / Double(k)
        return Float(min(max(w, 0), 1) * min(max(w, 0), 1))
    }
    static let startDir: SIMD3<Float> = { let d = shape.tangent(shape.sink + 0.05); return SIMD3(Float(d.x), Float(d.y), Float(d.z)) }()
    /// Per vertex: the rest height of its ring's centre (so a whole ring blends rigid -> floor-lying by the same weight and is never squashed).
    static let ringY: [Float] = {
        let s = shape
        var out: [Float] = [Float(s.point(0).y)]
        for k in 1...bodyRings { out += Array(repeating: Float(s.point(s.length * Double(k) / Double(bodyRings)).y), count: around) }
        for _ in 1...capRings { out += Array(repeating: Float(s.point(s.length).y), count: around) }
        out.append(Float(s.point(s.length).y))
        return out
    }()
    /// Where the tail block starts in the body mesh last built (Geometry), so a Skinner nobody configured (test rigs, previews) still collapses it instead of showing the rest tail.
    nonisolated(unsafe) static var builtFirst = -1
    /// Shading continuity at the junction: per tail vertex the egg's own outward normal at its rest position, and how strongly the tail's normal is pulled toward it
    /// (1 in the buried / root rings, easing to 0 a short way down the tail), applied after the normal pass (Skinner.blendTailNormals).
    static let bodyNormals: [SIMD3<Float>] = local.pos.map { let n = BobForm.normal($0); return SIMD3(Float(n.x), Float(n.y), Float(n.z)) }
    static let normalBlend: [Float] = {
        let s = shape
        func w(_ t: Double) -> Float { let u = min(max((t - s.sink - PipBack.shift) / 0.5, 0), 1); return 1 - Float(u * u * (3 - 2 * u)) }
        var out: [Float] = [1]
        for k in 1...bodyRings { out += Array(repeating: w(s.length * Double(k) / Double(bodyRings)), count: around) }
        for _ in 1...capRings { out += Array(repeating: 0, count: around) }
        out.append(0)
        return out
    }()
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
