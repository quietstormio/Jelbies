//
//  ArmPath.swift
//  Data-driven arm poses. An `ArmPath` is a 1-D path (parameter s in 0...1) through arm poses, starting at the resting teardrop.
//  Each pose is described by where the arm leaves the egg (surface point at height `yS`), its axis direction (a 3-D unit
//  vector, outward = +x for the +x arm; mirrored for the other side), how far the root is buried (`inset`), how far it
//  protrudes (`prot`), root / tip radii, z flatten and fillet size `k`. The wave is one path; other paths (reach to a
//  plate, nub to the mouth, ...) are more data of the same kind.
//
//  `PosedArmField` is the posed signed distance field F_s = smin(egg, round cone, k) (+ feet) the keyframe builder
//  (ArmKeyframes.swift) projects the skin onto; at the rest pose it equals `BobForm.sdf` exactly.
//
//  Everything here is value-type math with no UI / actor state, so it runs on any thread.
//

import Foundation
import simd

nonisolated struct ArmGeom: Sendable {
    var A: SIMD3<Double>            // root centre (+x arm convention)
    var B: SIMD3<Double>            // tip centre
    var r1: Double, r2: Double
    var flatten: Double
    var k: Double                   // fillet size once fully posed
    /// 0 = still the rest rule for the fillet size (varies along the arm), 1 = constant `k`.
    var restW: Double

    static let rest = ArmGeom(A: BobForm.armTop, B: BobForm.armTip, r1: BobForm.armTopR, r2: BobForm.armTipR,
                              flatten: BobForm.armFlatten, k: 0.03, restW: 0)

    /// 0 while the arm is at rest -> 1 once posed: grows the capsule from hidden inside the skin to its working size.
    var grow: Double { let x = min(max(restW / 0.5, 0), 1); return x * x * (3 - 2 * x) }
    /// Capsule offset over the cone surface (world units): -0.02 (hidden inside the rest skin) ... +capsuleLift.
    var capsuleInflate: Double { -0.02 + (0.02 + Self.capsuleLift) * grow }
    /// How far the working capsule stands proud of the cone surface (the skin sinks by the same amount near it).
    static let capsuleLift = 0.0015
}

nonisolated struct ArmPose: Sendable {
    var yS = 0.7, zS = 0.06
    var axis = SIMD3<Double>(1, 0, 0)       // unit, root -> tip
    var inset = 0.1, prot = 0.28
    var r1 = 0.125, r2 = 0.12
    var flatten = 1.0, k = 0.06
    /// Explicit root / tip centres (the resting pose); nil = derived from the egg surface point.
    var explicitRoot: SIMD3<Double>?, explicitTip: SIMD3<Double>?

    static let rest = ArmPose(r1: BobForm.armTopR, r2: BobForm.armTipR, flatten: BobForm.armFlatten, k: 0.03,
                              explicitRoot: BobForm.armTop, explicitTip: BobForm.armTip)

    /// Axis from the vertical: `theta` toward outward (+x), `tilt` toward +z (forward).
    static func axis(thetaDeg: Double, tiltDeg: Double = 0) -> SIMD3<Double> {
        let th = thetaDeg * .pi / 180, ti = tiltDeg * .pi / 180
        return simd_normalize(SIMD3(sin(th) * cos(ti), cos(th) * cos(ti), sin(ti)))
    }
    static func posed(yS: Double, thetaDeg: Double, tiltDeg: Double = 0, inset: Double, prot: Double, r1: Double, r2: Double,
                      flatten: Double = 1, k: Double, zS: Double = 0.06) -> ArmPose {
        ArmPose(yS: yS, zS: zS, axis: axis(thetaDeg: thetaDeg, tiltDeg: tiltDeg), inset: inset, prot: prot, r1: r1, r2: r2,
                flatten: flatten, k: k)
    }

    var isExplicit: Bool { explicitRoot != nil && explicitTip != nil }

    /// x of the egg's surface at (yS, zS) on the +x side.
    static func eggX(y: Double, z: Double) -> Double {
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let m = 0.5 * (lo + hi)
            if BobForm.bodySDF(SIMD3(m, y, z)) < 0 { lo = m } else { hi = m }
        }
        return 0.5 * (lo + hi)
    }

    func resolve(scale: Double) -> ArmGeom {
        if let a = explicitRoot, let b = explicitTip {
            return ArmGeom(A: a, B: b, r1: r1, r2: r2, flatten: flatten, k: k, restW: 0)
        }
        let S = SIMD3(Self.eggX(y: yS, z: zS), yS, zS)
        let D = simd_normalize(axis)
        let R1 = r1 * scale, R2 = r2 * scale
        return ArmGeom(A: S - D * inset, B: S + D * (prot * scale - R2), r1: R1, r2: R2, flatten: flatten, k: k, restW: 1)
    }

    fileprivate var vector: [Double] { [yS, zS, axis.x, axis.y, axis.z, inset, prot, r1, r2, flatten, k] }
    fileprivate init(vector v: [Double]) {
        yS = v[0]; zS = v[1]; axis = simd_normalize(SIMD3(v[2], v[3], v[4])); inset = v[5]; prot = v[6]
        r1 = v[7]; r2 = v[8]; flatten = v[9]; k = v[10]
    }
    init(yS: Double = 0.7, zS: Double = 0.06, axis: SIMD3<Double> = SIMD3(1, 0, 0), inset: Double = 0.1, prot: Double = 0.28,
         r1: Double = 0.125, r2: Double = 0.12, flatten: Double = 1, k: Double = 0.06,
         explicitRoot: SIMD3<Double>? = nil, explicitTip: SIMD3<Double>? = nil) {
        self.yS = yS; self.zS = zS; self.axis = axis; self.inset = inset; self.prot = prot; self.r1 = r1; self.r2 = r2
        self.flatten = flatten; self.k = k; self.explicitRoot = explicitRoot; self.explicitTip = explicitTip
    }
}

nonisolated struct ArmPath: Sendable {
    struct Knot: Sendable { var s: Double; var pose: ArmPose }
    let name: String
    let knots: [Knot]

    /// Arm geometry (+x convention) at path parameter s. An explicit (resting) pose swings to the next pose in polar form
    /// (root and length interpolate, the axis slerps, so the arm sweeps up the outside without shrinking); between posed
    /// knots all pose parameters follow a Catmull-Rom Hermite curve.
    func geom(at sIn: Double, scale: Double = 1) -> ArmGeom {
        let s = min(max(sIn, 0), 1)
        var i = 0
        while i < knots.count - 2 && s > knots[i + 1].s { i += 1 }
        let k0 = knots[i], k1 = knots[i + 1]
        let u = min(max((s - k0.s) / max(k1.s - k0.s, 1e-9), 0), 1)
        if k0.pose.isExplicit {
            let g0 = k0.pose.resolve(scale: scale), g1 = k1.pose.resolve(scale: scale)
            let d0 = g0.B - g0.A, d1 = g1.B - g1.A
            let l0 = simd_length(d0), l1 = simd_length(d1)
            let q = simd_slerp(simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), simd_quatd(from: d0 / l0, to: d1 / l1), u)
            let axis = q.act(d0 / l0)
            let A = g0.A + (g1.A - g0.A) * u
            let L = l0 + (l1 - l0) * u
            func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * u }
            return ArmGeom(A: A, B: A + axis * L, r1: mix(g0.r1, g1.r1), r2: mix(g0.r2, g1.r2), flatten: mix(g0.flatten, g1.flatten),
                           k: mix(g0.k, g1.k), restW: mix(g0.restW, g1.restW))
        }
        // Hermite through the posed knots
        func tangent(_ j: Int) -> [Double] {
            let a = max(j - 1, 0), b = min(j + 1, knots.count - 1)
            let lo = knots[a].pose.isExplicit ? j : a      // never differentiate against the explicit rest pose
            let va = knots[lo].pose.vector, vb = knots[b].pose.vector
            let ds = max(knots[b].s - knots[lo].s, 1e-9)
            return zip(va, vb).map { ($1 - $0) / ds }
        }
        let p0 = k0.pose.vector, p1 = k1.pose.vector, m0 = tangent(i), m1 = tangent(i + 1)
        let h = k1.s - k0.s
        let u2 = u * u, u3 = u2 * u
        let h00 = 2 * u3 - 3 * u2 + 1, h10 = u3 - 2 * u2 + u, h01 = -2 * u3 + 3 * u2, h11 = u3 - u2
        var v = [Double](repeating: 0, count: p0.count)
        for c in 0..<v.count { v[c] = h00 * p0[c] + h10 * h * m0[c] + h01 * p1[c] + h11 * h * m1[c] }
        return ArmPose(vector: v).resolve(scale: scale)
    }

    /// The friendly wave: rest -> OUT (arm swung out sideways) -> MID -> UP (thick stubby thumb rising from high on the side, tip about head-top level; the spec's yS 0.82 only reached eye level).
    static let wave = ArmPath(name: "wave", knots: [
        Knot(s: 0, pose: .rest),
        Knot(s: 0.4, pose: .posed(yS: 0.72, thetaDeg: 75, inset: 0.10, prot: 0.28, r1: 0.125, r2: 0.12, k: 0.12)),
        Knot(s: 0.7, pose: .posed(yS: 0.80, thetaDeg: 52, inset: 0.10, prot: 0.28, r1: 0.125, r2: 0.12, k: 0.12)),
        Knot(s: 1.0, pose: .posed(yS: 0.88, thetaDeg: 30, inset: 0.08, prot: 0.31, r1: 0.125, r2: 0.115, k: 0.13)),
    ])
}

// MARK: - Posed field

extension BobForm {
    /// Egg only: Newton onto bodySDF = 0 using its own gradient (`project` uses the full sdf with arms and feet).
    static func eggGradient(_ p: SIMD3<Double>, e: Double = 0.0015) -> SIMD3<Double> {
        SIMD3(bodySDF(p + SIMD3(e, 0, 0)) - bodySDF(p - SIMD3(e, 0, 0)),
              bodySDF(p + SIMD3(0, e, 0)) - bodySDF(p - SIMD3(0, e, 0)),
              bodySDF(p + SIMD3(0, 0, e)) - bodySDF(p - SIMD3(0, 0, e))) / (2 * e)
    }
    static func projectEgg(_ p0: SIMD3<Double>, steps: Int = 8) -> SIMD3<Double> {
        var p = p0
        for _ in 0..<steps {
            let f = bodySDF(p), g = eggGradient(p), l2 = simd_dot(g, g)
            if l2 < 1e-12 || abs(f) < 1e-7 { break }
            p -= g * (f / l2)
        }
        return p
    }
}

/// F_s for the +x arm; callers mirror x for the other side.
nonisolated struct PosedArmField: Sendable {
    let g: ArmGeom
    private let a: SIMD3<Double>, b: SIMD3<Double>, ba2: Double

    init(_ g: ArmGeom) {
        self.g = g
        a = SIMD3(g.A.x, g.A.y, g.A.z * g.flatten)
        b = SIMD3(g.B.x, g.B.y, g.B.z * g.flatten)
        ba2 = simd_dot(b - a, b - a)
    }

    @inline(__always) func coneT(_ q: SIMD3<Double>) -> (d: Double, t: Double) {
        let qq = SIMD3(q.x, q.y, q.z * g.flatten)
        let t = min(max(simd_dot(qq - a, b - a) / ba2, 0), 1)
        return (BobForm.roundCone(qq, a, b, g.r1, g.r2) / g.flatten.squareRoot(), t)
    }
    @inline(__always) func cone(_ q: SIMD3<Double>) -> Double { coneT(q).d }

    func value(_ q: SIMD3<Double>) -> Double {
        let c = coneT(q)
        let u = 1 - min(max(c.t / 0.55, 0), 1)
        let rule = BobForm.armTipBlend + (BobForm.armBlend - BobForm.armTipBlend) * (u * u * (3 - 2 * u))
        let k = rule + (g.k - rule) * g.restW
        var d = BobForm.smin(BobForm.bodySDF(q), c.d, k)
        d = BobForm.smin(d, BobForm.footSDF(SIMD3(abs(q.x), q.y, q.z)), BobForm.footBlend)
        return d
    }
    func gradient(_ q: SIMD3<Double>, e: Double = 0.0015) -> SIMD3<Double> {
        SIMD3(value(q + SIMD3(e, 0, 0)) - value(q - SIMD3(e, 0, 0)),
              value(q + SIMD3(0, e, 0)) - value(q - SIMD3(0, e, 0)),
              value(q + SIMD3(0, 0, e)) - value(q - SIMD3(0, 0, e))) / (2 * e)
    }
    func normal(_ q: SIMD3<Double>) -> SIMD3<Double> {
        let gr = gradient(q)
        return simd_length(gr) > 1e-12 ? simd_normalize(gr) : SIMD3(0, 0, 1)
    }
    /// Same formula as BobForm.occlusion, with this field.
    func occlusion(_ p: SIMD3<Double>, _ n: SIMD3<Double>) -> Double {
        var occ = 0.0, w = 1.0
        for k in 1...5 {
            let h = 0.05 * Double(k)
            occ += max(h - value(p + n * h), 0) / h * w
            w *= 0.7
        }
        return min(max(occ * 1.1, 0), 1)
    }
    /// Newton onto F = 0, each step capped at `cap`.
    func project(_ p0: SIMD3<Double>, steps: Int = 16, cap: Double = 0.02) -> SIMD3<Double> {
        var p = p0
        for _ in 0..<steps {
            let f = value(p)
            if abs(f) < 2e-5 { break }
            let gr = gradient(p), l2 = simd_dot(gr, gr)
            if l2 < 1e-12 { break }
            var st = gr * (f / l2)
            let l = simd_length(st)
            if l > cap { st *= cap / l }
            p -= st
        }
        return p
    }
}

// MARK: - Capsule (the arm itself)

/// Fixed-topology revolve of the round cone: pole at the tip, `tipRings` rings on the tip sphere, `rootRings` rings on the
/// root sphere (the first of them joins the tangent cone), pole at the root. One per side, appended to the render mesh.
nonisolated enum ArmCapsule {
    static let around = 40, tipRings = 8, rootRings = 10
    static var ringCount: Int { tipRings + rootRings }
    static var vertexCount: Int { 2 + around * ringCount }

    static func triangles(firstVertex f: Int) -> [UInt32] {
        var t: [UInt32] = []
        func ring(_ r: Int, _ j: Int) -> UInt32 { UInt32(f + 1 + around * r + (j % around)) }
        let tipPole = UInt32(f), rootPole = UInt32(f + vertexCount - 1)
        for j in 0..<around { t += [tipPole, ring(0, j), ring(0, j + 1)] }
        for r in 0..<(ringCount - 1) {
            for j in 0..<around {
                t += [ring(r, j), ring(r + 1, j), ring(r, j + 1)]
                t += [ring(r, j + 1), ring(r + 1, j), ring(r + 1, j + 1)]
            }
        }
        for j in 0..<around { t += [rootPole, ring(ringCount - 1, j + 1), ring(ringCount - 1, j)] }
        return t
    }

    /// World-frame points and unit normals of the revolve of the round cone of `g` grown by `inflate` (world units),
    /// for side `sigma` (+1 = +x arm, -1 = mirrored).
    static func points(_ g: ArmGeom, inflate: Double, sigma: Double) -> (pos: [SIMD3<Double>], nrm: [SIMD3<Double>]) {
        let F = g.flatten, sF = F.squareRoot()
        let a = SIMD3(g.A.x, g.A.y, g.A.z * F), b = SIMD3(g.B.x, g.B.y, g.B.z * F)
        let ba = b - a, L = simd_length(ba), u = ba / L
        let R1 = g.r1 + inflate * sF, R2 = g.r2 + inflate * sF
        let alpha = acos(min(max((R1 - R2) / L, -1), 1))
        let zAxis = SIMD3<Double>(0, 0, 1)
        var e1 = zAxis - u * simd_dot(zAxis, u)
        if simd_length(e1) < 1e-4 { e1 = SIMD3(1, 0, 0) - u * u.x }
        e1 = simd_normalize(e1)
        let e2 = simd_cross(u, e1)
        var pos: [SIMD3<Double>] = [], nrm: [SIMD3<Double>] = []
        pos.reserveCapacity(vertexCount); nrm.reserveCapacity(vertexCount)
        func emit(_ centre: SIMD3<Double>, _ R: Double, _ n: SIMD3<Double>) {
            let p = centre + n * R
            pos.append(SIMD3(p.x * sigma, p.y, p.z / F))
            let nn = simd_normalize(SIMD3(n.x * sigma, n.y, n.z * F))
            nrm.append(nn)
        }
        emit(b, R2, u)
        for i in 1...tipRings {
            let phi = alpha * Double(i) / Double(tipRings)
            for j in 0..<around {
                let th = 2 * Double.pi * Double(j) / Double(around)
                emit(b, R2, cos(phi) * u + sin(phi) * (cos(th) * e1 + sin(th) * e2))
            }
        }
        for i in 0..<rootRings {
            let phi = alpha + (Double.pi - alpha) * Double(i) / Double(rootRings)
            for j in 0..<around {
                let th = 2 * Double.pi * Double(j) / Double(around)
                emit(a, R1, cos(phi) * u + sin(phi) * (cos(th) * e1 + sin(th) * e2))
            }
        }
        emit(a, R1, -u)
        return (pos, nrm)
    }

    /// The static `rest` stream (crinkle texture coordinates) of a capsule: the matching point (same ring / angle) on a texture cone.
    /// The cone it is taken from has the size of a typical posed arm (the wave's OUT pose) so the crinkle noise has the same
    /// density as on the body skin instead of being stretched from the small resting arm.
    static func restStream(sigma: Double) -> [SIMD3<Double>] { points(ArmPath.wave.geom(at: 0.4), inflate: 0, sigma: sigma).pos }

    /// The hidden resting shape: the rest cone shrunk by 0.02.
    static func inactive(sigma: Double) -> [SIMD3<Double>] { points(.rest, inflate: -0.02, sigma: sigma).pos }
}

/// Where the capsules live in the render mesh.
nonisolated struct ArmCapsuleInfo: Sendable {
    /// First vertex of the side -1 / +1 capsule.
    var firstVertex: [Int]
    var indexFirst: Int, indexCount: Int
    func first(side: Int) -> Int { side < 0 ? firstVertex[0] : firstVertex[1] }
}
