//
//  AntennaBean.swift
//  The green Jelmiko's signature (JellyFeature.daisy keeps its raw value, it now means "two antennas"): two slim jelly stalks with a round ball on the tip, left and right on top
//  of the head, grown out of the BODY render mesh exactly like Teddy's ears and Pip's tail: one block of body vertices appended after Teddy's block (still in the body index range, so
//  the body skin shader draws it with the individual's own colour, fuzz, crinkle and look, mat = 0 everywhere: nothing here is a prop with a material of its own). The block is
//  collapsed onto each antenna's base pole (zero area, invisible) for every Jelmiko but green and while the hat rule tucks them (scale 0).
//
//  SHAPE (rest units; the crown is y ~1.35): a centre line that leaves the head about a quarter of the head width out from the middle and curves outward, a flared base (a trumpet that
//  melts into the head: a rolling-ball fillet pushes the egg's own vertices out around the root, TeddyBean's maths) tapering to a soft stalk, then a round ball tip.
//
//  MOTION (Skinner.applyAntennas): the root frame is carried on three landmark egg vertices (as Teddy's ears). Each antenna keeps its own two lean angles (outward / forward) as a damped
//  spring driven by the head's acceleration (lag, overshoot, settle), by gravity in the head frame (the stalks flop when he tips or lies down) and by a gentle idle sway of its own
//  phase. The lean is applied as a CUMULATIVE bend along the stalk (zero at the root, full at the ball, the ball rigid on the tip frame), so the length never changes: it bends, never stretches.
//

import Foundation
import simd

nonisolated enum AntennaBean {
    // MARK: the design numbers (rest units)

    /// The right antenna's root on the egg: polar angle from straight up (deg), azimuth from the front (deg; 90 = straight out to the side).
    nonisolated(unsafe) static var rootPolar = 17.0, rootAzimuth = 80.0
    /// Visible length of the stalk from the head surface to the ball's centre, the ball radius, how far the stalk leans outward at the root and at the ball (deg from the surface normal).
    nonisolated(unsafe) static var length = 0.30, ballR = 0.082, leanRoot = 6.0, leanTip = 36.0
    /// Stalk half width at the tip end and the flare at the root (extra half width at the surface, its fall-off length), buried depth below the surface.
    nonisolated(unsafe) static var stalkR = 0.030, flareR = 0.040, flareLen = 0.050, buried = 0.10
    nonisolated(unsafe) static var filletR = 0.035
    static let around = 14

    // MARK: motion tuning (see Skinner.applyAntennas)
    /// Spring frequency (Hz) per antenna (different so the two never move in lockstep), damping ratio (0.16 = a few soft overshoots), acceleration -> lean (rad per u/s^2), gravity -> lean (rad per g),
    /// vertical acceleration -> outward splay (rad per u/s^2), idle sway (rad, Hz), hard lean limits (rad).
    nonisolated(unsafe) static var hz: [Float] = [2.6, 3.0], zeta: Float = 0.16
    nonisolated(unsafe) static var accelGain: Float = 0.045, gravityGain: Float = 0.9, splayGain: Float = 0.012
    nonisolated(unsafe) static var idleAmp: Float = 0.07, idleHz: [Float] = [0.37, 0.43]
    /// How fast the roots glide when a tall hat goes on / off (rest units per second).
    nonisolated(unsafe) static var liftSpeed: Float = 2.0
    nonisolated(unsafe) static var outMax: Float = 0.95, inMax: Float = 0.50, fwdMax: Float = 0.50, backMax: Float = 0.80

    // MARK: parts

    struct Part {
        var name: String
        var sgn: Double                              // +1 right (+x), -1 left
        var centre: [SIMD3<Double>]                  // centre line sample per ring (rest)
        var s: [Double]                              // arc length per ring (0 = the head surface)
        var radius: [Double]                         // half width per ring
        var o: SIMD3<Double>                         // base pole (inside the head): the anchor everything scales about
        var landmarkTargets: [SIMD3<Float>]
        var first = 0, count = 0
        var ringFirst = 0, rings = 0                 // local index of ring 0 / ring count (vertices: ring r vertex j = ringFirst + r * around + j)
        var tipPole = 0
        var rootIndex = 0                            // ring index of s = 0 (the head surface)
        var liftDir = SIMD3<Double>(0, 1, 0)         // the antenna's own direction at its root (raising a root moves it along this)
    }

    /// Arc-length stations of the rings: buried, flare + stalk, then the ball by angle.
    static func stations() -> [Double] {
        var out: [Double] = [-buried, -buried * 0.5]
        var s = 0.0
        while s < length - ballR - 1e-9 { out.append(s); s += s < 0.06 ? 0.02 : 0.035 }
        let a0 = -80.0
        var a = a0
        while a < 89 { out.append(length + ballR * sin(a * .pi / 180)); a += 14 }
        return out
    }

    /// Half width along the stalk (before the ball).
    static func stalkRadius(_ s: Double) -> Double {
        if s > length { return 0 }
        let sc = max(s, 0)
        return stalkR + flareR * exp(-sc / flareLen) * 1.0
    }
    static func ballRadius(_ s: Double) -> Double {
        let d = s - length
        return abs(d) < ballR ? sqrt(max(ballR * ballR - d * d, 0)) : 0
    }
    static func radius(_ s: Double) -> Double {
        let a = stalkRadius(s), b = ballRadius(s), k = 0.035
        let h = min(max(0.5 + 0.5 * (a - b) / k, 0), 1)
        return b + (a - b) * h + k * h * (1 - h)
    }

    /// The bend weight at arc length s: 0 at the root, 1 over the ball (a rigid tip), concentrated toward the root so the whole stalk curves.
    static func bendWeight(_ s: Double) -> Float {
        let u = min(max((s - 0.015) / (length - 0.05 - 0.015), 0), 1)
        return Float(1 - (1 - u) * (1 - u))
    }

    static func buildParts() -> [Part] {
        var parts: [Part] = []
        let pol = rootPolar * .pi / 180, az = rootAzimuth * .pi / 180
        let dir = simd_normalize(SIMD3<Float>(Float(sin(pol) * sin(az)), Float(cos(pol)), Float(sin(pol) * cos(az))))
        let (sp, sn) = TeddyMesh.surface(from: TeddyMesh.earCentreFrom, dir: dir)
        let p = SIMD3<Double>(Double(sp.x), Double(sp.y), Double(sp.z)), n = SIMD3<Double>(Double(sn.x), Double(sn.y), Double(sn.z))
        // the stalk grows along a blend of the surface normal and straight up, then curves outward
        let st = stations()
        for sgn in [1.0, -1.0] {
            func mir(_ q: SIMD3<Double>) -> SIMD3<Double> { sgn > 0 ? q : SIMD3(-q.x, q.y, q.z) }
            // integrate the centre line (in the right-hand frame, mirrored after)
            let n0 = simd_normalize(SIMD3(n.x * 0.5, n.y * 0.5 + 0.5, n.z * 0.5))
            func dirAt(_ s: Double) -> SIMD3<Double> {
                let t = min(max(s / length, 0), 1)
                let ang = (leanRoot + (leanTip - leanRoot) * t * t) * .pi / 180
                return simd_normalize(n0 * cos(ang) + SIMD3(1, 0, 0) * sin(ang))
            }
            var pos = p
            var prevS = 0.0
            // the visible part: integrate from 0
            var visible: [SIMD3<Double>] = []
            for s in st where s > 0 {
                let steps = 4
                let ds = (s - prevS) / Double(steps)
                for k in 0..<steps { pos += dirAt(prevS + ds * (Double(k) + 0.5)) * ds }
                prevS = s
                visible.append(pos)
            }
            var centre: [SIMD3<Double>] = []
            var vi = 0
            for s in st { if s <= 0 { centre.append(p + dirAt(0) * s) } else { centre.append(visible[vi]); vi += 1 } }
            centre = centre.map(mir)
            let rad = st.map { radius($0) }
            func f(_ q: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(q.x), Float(q.y), Float(q.z)) }
            let root = mir(p)
            var part = Part(name: sgn > 0 ? "ant_r" : "ant_l", sgn: sgn, centre: centre, s: st, radius: rad, o: centre[0],
                            landmarkTargets: [f(root + SIMD3(0.16, 0, 0)), f(root - SIMD3(0.16, 0, 0)), f(root + SIMD3(0, 0, 0.16))])
            if sgn < 0 { part.landmarkTargets = [f(root - SIMD3(0.16, 0, 0)), f(root + SIMD3(0.16, 0, 0)), f(root + SIMD3(0, 0, 0.16))] }
            part.rootIndex = st.firstIndex(where: { $0 >= 0 }) ?? 0
            let ri = part.rootIndex
            part.liftDir = simd_normalize(centre[min(ri + 2, centre.count - 1)] - centre[ri])
            parts.append(part)
        }
        return parts
    }

    // MARK: the mesh

    struct Block { var pos: [SIMD3<Double>] = [], nrm: [SIMD3<Double>] = [], tri: [UInt32] = [] }

    static let built: (parts: [Part], block: Block) = {
        var parts = buildParts()
        var blk = Block()
        for pi in 0..<parts.count {
            var part = parts[pi]
            part.first = blk.pos.count
            let base = blk.pos.count
            blk.pos.append(part.o); blk.nrm.append(SIMD3(0, 1, 0))             // the base pole: unreferenced, the collapse target
            part.ringFirst = 1
            part.rings = part.s.count
            let nR = part.s.count
            for r in 0..<nR {
                let c = part.centre[r]
                let tg: SIMD3<Double> = {
                    let a = part.centre[max(r - 1, 0)], b = part.centre[min(r + 1, nR - 1)]
                    return simd_normalize(b - a)
                }()
                // cross-section frame without twist: the side axis is z, the other is across the plane the stalk lies in
                let zAxis = SIMD3<Double>(0, 0, 1)
                let e1 = simd_normalize(simd_cross(tg, zAxis)), e2 = zAxis
                let rr = part.radius[r]
                // radial slope for the normal (dr/ds)
                let sA = part.s[max(r - 1, 0)], sB = part.s[min(r + 1, nR - 1)]
                let slope = (radius(sB) - radius(sA)) / max(sB - sA, 1e-6)
                for j in 0..<around {
                    let ph = 2 * Double.pi * Double(j) / Double(around)
                    let e = e1 * cos(ph) + e2 * sin(ph)
                    blk.pos.append(c + e * rr)
                    blk.nrm.append(simd_normalize(e - tg * slope))
                }
            }
            let tipC = part.centre[nR - 1]
            let tg = simd_normalize(part.centre[nR - 1] - part.centre[nR - 2])
            part.tipPole = blk.pos.count - base
            blk.pos.append(tipC + tg * 0.001); blk.nrm.append(tg)
            let ring0 = base + 1
            func ring(_ r: Int, _ j: Int) -> UInt32 { UInt32(ring0 + r * around + (j % around)) }
            for j in 0..<around { blk.tri += [UInt32(base), ring(0, j), ring(0, j + 1)] }
            for r in 0..<(nR - 1) { for j in 0..<around {
                blk.tri += [ring(r, j), ring(r + 1, j), ring(r, j + 1), ring(r, j + 1), ring(r + 1, j), ring(r + 1, j + 1)]
            } }
            for j in 0..<around { blk.tri += [UInt32(blk.pos.count - 1), ring(nR - 1, j + 1), ring(nR - 1, j)] }
            part.count = blk.pos.count - base
            parts[pi] = part
        }
        return (parts, blk)
    }()

    static var parts: [Part] { built.parts }
    static var vertexCount: Int { built.block.pos.count }
    nonisolated(unsafe) static var builtFirst = -1
    static func triangles(firstVertex f: Int) -> [UInt32] { built.block.tri.map { $0 + UInt32(f) } }
    static let localF: [SIMD3<Float>] = built.block.pos.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }
    /// Per vertex: its ring (-1 for the poles), and the vertex relative to its ring centre (rest).
    static let ringOf: [Int] = {
        var out = [Int](repeating: -1, count: vertexCount)
        for part in parts { for r in 0..<part.rings { for j in 0..<around { out[part.first + part.ringFirst + r * around + j] = r } } }
        return out
    }()

    /// Rest-space points of the antennas' visible part (above the head surface).
    static func visiblePoints(minHeight: Double = 0.02) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        for part in parts { for i in 1..<part.count where BobForm.sdf(built.block.pos[part.first + i]) > minHeight { out.append(localF[part.first + i]) } }
        return out
    }

    // MARK: the fillet

    /// Signed distance to the stalk's solid (rest): the distance to its centre line minus the radius there (rest, the flare included).
    static func sdf(_ q: SIMD3<Double>, part: Part) -> Double {
        var best = Double.infinity
        let nR = min(part.s.count, part.s.firstIndex(where: { $0 >= length - ballR }) ?? part.s.count)
        guard nR >= 2 else { return best }
        for i in 0..<(nR - 1) {
            let a = part.centre[i], b = part.centre[i + 1], ab = b - a
            let t = min(max(simd_dot(q - a, ab) / max(simd_dot(ab, ab), 1e-12), 0), 1)
            let d = simd_length(q - (a + ab * t)) - (part.radius[i] + (part.radius[i + 1] - part.radius[i]) * t)
            best = min(best, d)
        }
        return best
    }

    static func swell(_ q: SIMD3<Float>, part: Part) -> SIMD3<Float> {
        let p = SIMD3<Double>(Double(q.x), Double(q.y), Double(q.z))
        if simd_distance(p, part.o) > 0.55 { return .zero }
        let R = filletR, kk = R / (1 - 0.5.squareRoot())
        if sdf(p, part: part) >= kk { return .zero }
        let n = BobForm.normal(p)
        func smin(_ a: Double, _ b: Double) -> Double {
            let h = max(kk - abs(a - b), 0) / kk
            return min(a, b) - kk * 0.5 * (1 + h - (1 - h * (h - 2)).squareRoot())
        }
        func f(_ s: Double) -> Double { let x = p + n * s; return smin(BobForm.sdf(x), sdf(x, part: part)) }
        let cap = 0.5 * R
        var root = 0.0
        if f(0) < 0 {
            let top = 3 * cap
            if f(top) < 0 { root = top } else {
                var lo = 0.0, hi = top
                for _ in 0..<18 { let m = (lo + hi) / 2; if f(m) < 0 { lo = m } else { hi = m } }
                root = (lo + hi) / 2
            }
        }
        let s = cap * tanh(root / cap)
        let d = n * s
        return SIMD3(Float(d.x), Float(d.y), Float(d.z))
    }

    struct Rig {
        var landmarks: [[Int]]
        var landmarkRest: [[SIMD3<Float>]]
        var bumps: [[(Int, SIMD3<Float>)]]
    }
    private static let rigLock = NSLock()
    nonisolated(unsafe) private static var rigCache: [Int: Rig] = [:]
    static func rig(rest: [Float], eggLimit: Int) -> Rig {
        let key = rest.count &* 31 &+ eggLimit
        rigLock.lock(); let c = rigCache[key]; rigLock.unlock()
        if let c { return c }
        var r = Rig(landmarks: [], landmarkRest: [], bumps: [])
        let limit = min(eggLimit, rest.count / 3)
        for part in parts {
            let lm = part.landmarkTargets.map { t -> Int in
                var best = 0, bd = Float.infinity
                for v in 0..<limit {
                    let dd = simd_distance_squared(SIMD3(rest[3 * v], rest[3 * v + 1], rest[3 * v + 2]), t)
                    if dd < bd { bd = dd; best = v }
                }
                return best
            }
            r.landmarks.append(lm)
            r.landmarkRest.append(lm.map { SIMD3(rest[3 * $0], rest[3 * $0 + 1], rest[3 * $0 + 2]) })
            var bumps: [(Int, SIMD3<Float>)] = []
            for v in 0..<limit {
                let d = swell(SIMD3(rest[3 * v], rest[3 * v + 1], rest[3 * v + 2]), part: part)
                if simd_length(d) > 0.002 { bumps.append((v, d)) }
            }
            r.bumps.append(bumps)
        }
        rigLock.lock(); rigCache[key] = r; rigLock.unlock()
        return r
    }
}

/// The antennas' soft state (one per Skinner): per antenna the outward / forward lean (rad) and their rates, plus what the acceleration is made from.
nonisolated struct AntennaMotion {
    var lean = [SIMD2<Float>](repeating: .zero, count: 2)       // (outward, forward)
    var rate = [SIMD2<Float>](repeating: .zero, count: 2)
    var prevC = SIMD3<Float>.zero, prevV = SIMD3<Float>.zero, accel = SIMD3<Float>.zero
    var primed = false
    var clock: Float = 0
    /// Last-frame read-outs for tests.
    var lastTip = [SIMD3<Float>](repeating: .zero, count: 2)
}

// MARK: - the Skinner side

extension Skinner {
    func configureAntennas(_ rm: RenderMesh) {
        guard let cap = rm.armCapsule, cap.antennaFirst >= 0 else { return }
        antennaFirst = cap.antennaFirst
        antennaRig = AntennaBean.rig(rest: rm.rest, eggLimit: cap.firstVertex.min() ?? rm.vertexCount)
    }

    /// One soft step of antenna `k`'s lean springs (exposed for tests): target lean from the acceleration, gravity (head frame) and the idle sway.
    static func antennaStep(_ m: inout AntennaMotion, k: Int, aLocal: SIMD3<Float>, gLocal: SIMD3<Float>, dt: Float) {
        let sgn: Float = k == 0 ? 1 : -1
        let w = 2 * Float.pi * AntennaBean.hz[k], z = AntennaBean.zeta
        // outward lean: the lag against sideways acceleration (in outward terms), gravity pulling sideways, vertical acceleration splaying
        let outA = sgn * (-AntennaBean.accelGain * aLocal.x) + sgn * AntennaBean.gravityGain * gLocal.x + AntennaBean.splayGain * aLocal.y
        let fwdA = -AntennaBean.accelGain * aLocal.z + AntennaBean.gravityGain * gLocal.z
        let idle = AntennaBean.idleAmp
        let ph = 2 * Float.pi * AntennaBean.idleHz[k] * m.clock
        let target = SIMD2<Float>(outA + idle * sinf(ph + Float(k) * 2.1), fwdA + idle * 0.8 * sinf(ph * 1.31 + 1.0 + Float(k) * 1.3))
        let sub = 4, h = dt / Float(sub)
        var L = m.lean[k], V = m.rate[k]
        for _ in 0..<sub {
            V += (-w * w * (L - target) - 2 * z * w * V) * h
            L += V * h
        }
        L.x = min(max(L.x, -AntennaBean.inMax), AntennaBean.outMax)
        L.y = min(max(L.y, -AntennaBean.backMax), AntennaBean.fwdMax)
        if !(L.x.isFinite && L.y.isFinite && V.x.isFinite && V.y.isFinite) { L = .zero; V = .zero }
        m.lean[k] = L; m.rate[k] = V
    }

    func applyAntennas(_ dyn: UnsafeMutablePointer<Float>) {
        let f = antennaFirst >= 0 ? antennaFirst : AntennaBean.builtFirst, n = AntennaBean.vertexCount
        guard f >= 0, f + n <= vertexCount else { return }
        let parts = AntennaBean.parts
        func collapse(_ part: AntennaBean.Part) {
            let o0 = 6 * (f + part.first)
            let B = SIMD3<Float>(dyn[o0], dyn[o0 + 1], dyn[o0 + 2])
            for i in 1..<part.count { let o = 6 * (f + part.first + i); dyn[o] = B.x; dyn[o + 1] = B.y; dyn[o + 2] = B.z }
        }
        let lift = antennaLift
        guard let rig = antennaRig, antennaOn, antennaScale > 0.002 else { antennaMotion.primed = false; for part in parts { collapse(part) }; return }
        func frame(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> simd_float3x3 {
            let x = simd_normalize(b - a), z = simd_normalize(simd_cross(x, c - a)), y = simd_cross(z, x)
            return simd_float3x3(columns: (x, y, z))
        }
        let dt = frameDt
        var rots = [simd_float3x3](repeating: matrix_identity_float3x3, count: 2)
        var anchors = [SIMD3<Float>](repeating: .zero, count: 2)
        var Rot0 = matrix_identity_float3x3
        for (pi, part) in parts.enumerated() {
            let lm = rig.landmarks[pi]
            func at(_ k: Int) -> SIMD3<Float> { let o = 6 * lm[k]; return SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]) }
            let rr = rig.landmarkRest[pi], ss = [at(0), at(1), at(2)]
            rots[pi] = frame(ss[0], ss[1], ss[2]) * frame(rr[0], rr[1], rr[2]).transpose
            let Cr = (rr[0] + rr[1] + rr[2]) / 3, Cs = (ss[0] + ss[1] + ss[2]) / 3
            let O = SIMD3<Float>(Float(part.o.x), Float(part.o.y), Float(part.o.z))
            anchors[pi] = Cs + rots[pi] * (O - Cr)
            if pi == 0 { Rot0 = rots[pi] }
        }
        // the head's acceleration (a short lag filter on the second difference of the carried root) and gravity, both in the head frame
        var m = antennaMotion
        m.clock += dt
        let Cc = anchors[0] * 0.5 + anchors[1] * 0.5
        if m.primed, simd_distance(Cc, m.prevC) < 1.0 {
            let v = (Cc - m.prevC) / dt
            var a = (v - m.prevV) / dt
            let am = simd_length(a); if am > 90 { a *= 90 / am }
            m.accel += (a - m.accel) * min(1, dt / 0.03)
            m.prevV = v
        } else { m.accel = .zero; m.prevV = .zero; m.lean = [.zero, .zero]; m.rate = [.zero, .zero] }
        m.prevC = Cc; m.primed = true
        let Rh = Rot0.transpose
        let aL = Rh * m.accel, gL = Rh * SIMD3<Float>(0, -1, 0)
        for k in 0..<2 { Skinner.antennaStep(&m, k: k, aLocal: aL, gLocal: gL, dt: dt) }
        let scale = antennaScale
        for (pi, part) in parts.enumerated() {
            let Rot = rots[pi], A = anchors[pi]
            let O = SIMD3<Float>(Float(part.o.x), Float(part.o.y), Float(part.o.z))
            // the bend per ring: a rotation (rest frame) about the root, growing with the bend weight; the ring centres are chained so the length is kept
            let lean = m.lean[pi]
            let liftVec = SIMD3<Float>(Float(part.liftDir.x), Float(part.liftDir.y), Float(part.liftDir.z)) * lift
            let sgn: Float = pi == 0 ? 1 : -1
            var ringC = [SIMD3<Float>](repeating: .zero, count: part.rings)
            var ringQ = [simd_quatf](repeating: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), count: part.rings)
            for r in 0..<part.rings {
                let w = AntennaBean.bendWeight(part.s[r])
                let rv = SIMD3<Float>(lean.y * w, 0, -sgn * lean.x * w)
                let ang = simd_length(rv)
                ringQ[r] = ang > 1e-6 ? simd_quatf(angle: ang, axis: rv / ang) : simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
                let c0 = SIMD3<Float>(Float(part.centre[r].x), Float(part.centre[r].y), Float(part.centre[r].z))
                if r == 0 { ringC[r] = c0 } else {
                    let cPrev = SIMD3<Float>(Float(part.centre[r - 1].x), Float(part.centre[r - 1].y), Float(part.centre[r - 1].z))
                    ringC[r] = ringC[r - 1] + ringQ[r].act(c0 - cPrev)
                }
            }
            for i in 0..<part.count {
                let L = AntennaBean.localF[part.first + i]
                let rg = AntennaBean.ringOf[part.first + i]
                var rel: SIMD3<Float>
                if rg >= 0 {
                    let c0 = SIMD3<Float>(Float(part.centre[rg].x), Float(part.centre[rg].y), Float(part.centre[rg].z))
                    rel = ringC[rg] + ringQ[rg].act(L - c0) - O
                } else if i == 0 { rel = .zero } else {
                    let r = part.rings - 1
                    let c0 = SIMD3<Float>(Float(part.centre[r].x), Float(part.centre[r].y), Float(part.centre[r].z))
                    rel = ringC[r] + ringQ[r].act(L - c0) - O
                }
                let p = A + Rot * (rel + liftVec) * scale
                let o = 6 * (f + part.first + i); dyn[o] = p.x; dyn[o + 1] = p.y; dyn[o + 2] = p.z
            }
            let c = ringC[part.rings - 1]
            m.lastTip[pi] = A + Rot * (c - O + liftVec) * scale
        }
        for pi in 0..<2 {
            for (v, w) in rig.bumps[pi] {
                let o = 6 * v, d = rots[pi] * (w * scale * max(0, 1 - lift / 0.06))          // (a raised root no longer grows from the head: its fillet fades)
                dyn[o] += d.x; dyn[o + 1] += d.y; dyn[o + 2] += d.z
            }
        }
        antennaMotion = m
    }
}
