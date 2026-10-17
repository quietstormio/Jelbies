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
    /// The rest nub (root `armTop`, tip `armTip`, rest radii) swung about its shoulder so the tip moves `tiltDeg` toward +z, as a posed
    /// arm: the surface point S on the egg is solved so the root stays exactly at `armTop`.
    static func nubSwing(tiltDeg: Double) -> ArmPose {
        let A = BobForm.armTop, d0 = BobForm.armTip - BobForm.armTop
        let L = simd_length(d0), u0 = d0 / L
        let t = tiltDeg * .pi / 180
        let D = simd_normalize(SIMD3(u0.x, u0.y * cos(t), -u0.y * sin(t)))
        // S = A + D * inset must lie on the egg surface (A itself is inside the body)
        var lo = 0.0, hi = 0.8
        for _ in 0..<50 {
            let m = 0.5 * (lo + hi), S = A + D * m
            if eggX(y: S.y, z: S.z) - S.x > 0 { lo = m } else { hi = m }
        }
        let inset = 0.5 * (lo + hi), S = A + D * inset
        return ArmPose(yS: S.y, zS: S.z, axis: D, inset: inset, prot: BobForm.armTipR + L - inset, r1: BobForm.armTopR, r2: BobForm.armTipR,
                       flatten: BobForm.armFlatten, k: 0.03)
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
        var g = geomRaw(at: sIn, scale: scale)
        g.B = ArmCap.clampTip(a: g.A, b: g.B, r2: g.r2, scale: scale)        // the global arm cap (the wave itself is the reference, so it passes untouched)
        return g
    }

    /// `geom` before the global cap (the cap's own reference is measured on the wave with this).
    func geomRaw(at sIn: Double, scale: Double = 1) -> ArmGeom {
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

    /// The resting teardrop swung about its shoulder like a pendulum: `nubForward` (tip swings toward +z, the way he faces) and `nubBack`
    /// (toward -z) are each one knot away from the exact rest pose (s = 0), so a swing is s = |phase| on the path of its sign and the two
    /// meet exactly at rest. Built through the same keyframe builder as the wave, with the rest radii (a posed teardrop, not a thumb).
    static let nubForward = ArmPath(name: "nubForward", knots: [Knot(s: 0, pose: .rest), Knot(s: 1, pose: .nubSwing(tiltDeg: nubTiltDeg))])
    static let nubBack = ArmPath(name: "nubBack", knots: [Knot(s: 0, pose: .rest), Knot(s: 1, pose: .nubSwing(tiltDeg: -nubTiltDeg))])
    /// The stubby nub raised to the mouth (dining): the arm keeps its stub length but its root slides from the side of the belly around to the
    /// front, pointing forward-up-inward so the tip ends up beside the mouth (rest nub -> mid -> beside the mouth). The skin is built by the same
    /// keyframe builder as the wave; nothing is stretched (tip centre only ~0.18 from the root, the wave's own length).
    static let nubToMouth = ArmPath(name: "nubToMouth", knots: [
        Knot(s: 0, pose: .rest),
        Knot(s: Self.nubGrabS, pose: .nubSwing(tiltDeg: nubTiltDeg)),             // the grab: the nub swings forward (the nubForward pose)
        Knot(s: 0.65, pose: .posed(yS: 0.50, thetaDeg: 50, tiltDeg: 25, inset: 0.10, prot: 0.29, r1: 0.125, r2: 0.12, k: 0.20, zS: 0.08)),
        Knot(s: 1.0, pose: .posed(yS: 0.50, thetaDeg: -15, tiltDeg: 50, inset: 0.10, prot: 0.27, r1: 0.125, r2: 0.12, k: 0.32, zS: 0.30)),
    ])
    /// WALKING ARM (W1b): not a skin path. The brain poses the closed ArmCapsule directly (see BlobBrain.driveArms); these are its data.
    /// Sweep S (deg) about a near-vertical shoulder axis, -35 .. +85, hold-snap-hold from the stride phase; elevation el(S) as in REF2.
    static let armWalkRoot = (x: 0.48, y: 0.51, z: 0.15, length: 0.225, r1: 0.13, r2: 0.115)
    /// Phase shift of the forward-hold centre in the STRIDE gait (x gaitW); 0 = the waddle's phase in both gaits. Pending the arms analyst's measurement (W1c).
    static let armStridePhaseShift: Float = 0.18
    /// One step of the arms' gait-weight copy (`shiftW`, 0 waddle ... 1 stride): it only moves while BOTH arms are deep in a hold (|cos| > 0.95 of the right arm's phase), where
    /// the sweep is flat, so a waddle <-> stride blend can shift the hold centres without whipping an arm (<= 0.3 gaitW per second).
    static func armShiftStep(shiftW: Float, target: Float, phase ph: Float, dt: Float) -> Float {
        let c = cosf(2 * .pi * (ph - (0.79 + armStridePhaseShift * shiftW)))
        guard abs(c) > 0.95 else { return shiftW }
        return shiftW + max(-dt * 0.3, min(dt * 0.3, target - shiftW))
    }
    static func armWalkSweepDeg(phase ph: Float, side: Int, gaitW: Float = 0) -> Float {
        let fwd: Float = (side > 0 ? 0.79 : 0.29) + armStridePhaseShift * gaitW
        let x = 1.8 * cosf(2 * .pi * (ph - fwd))
        let d: Float = 0.4                                    // corner half width (REF2's crossing takes 2-2.5 frames)
        let ax = abs(x)
        var v = x
        if ax > 1 + d { v = x > 0 ? 1 : -1 }
        else if ax > 1 - d { let t = (ax - (1 - d)) / (2 * d); let m = (1 - d) + 2 * d * (t * t * (3 - 2 * t) * 0.5 + 0.5 * t); v = (x > 0 ? 1 : -1) * min(1, m) }
        return armWalkCentreDeg + 33 * v                      // W1d: 55 % of the W1c sweep (-35..85): -11..55
    }
    static let armWalkCentreDeg: Float = 22
    /// Elevation (rad) of the arm axis at sweep S (deg).
    static func armWalkElevation(_ S: Float) -> Float {
        (S >= 0 ? -8 + 18 * (S / 55) * (S / 55) : -8 + 4 * (S / 11) * (S / 11)) * .pi / 180
    }
    /// Path parameter of the grab pose (the nub swung forward) on `nubToMouth`.
    static let nubGrabS: Double = 0.30
    /// Peak pendulum angle of the nub (REF2: std 12.8 deg front / 20 deg profile; a sine of this peak has std peak / sqrt 2).
    static let nubTiltDeg: Double = 24
}

// MARK: - Global arm protrusion cap

/// ONE cap on how far any arm may stand out of the body, for every move (walk, run, jacks, flip, hops, dining, wave ...).
/// "Exposed length" = the part of the capsule axis outside the egg plus the tip radius (what the eye reads as the arm's length,
/// body surface -> tip). The cap is the WAVE's maximum (the approved stubby thumb); `clamp` pulls a longer tip back along its own
/// axis (root stays buried, radii untouched), so a stub never grows into a tube whatever pose a move asks for. Body frame, +x arm.
nonisolated enum ArmCap {
    /// Test / comparison switch only (measuring the uncapped poses); always true in the app.
    nonisolated(unsafe) static var enabled = true
    /// Fillet collar switch (tests / cost measurement); always true in the app.
    nonisolated(unsafe) static var collar = true
    /// Fraction of the axis a->b that lies outside the egg, as a length, plus the tip radius.
    static func exposed(a: SIMD3<Double>, b: SIMD3<Double>, r2: Double, samples n: Int = 10) -> Double {
        let L = simd_length(b - a)
        var out = 0.0
        var prev = BobForm.bodySDF(a)
        for i in 1...n {
            let p = a + (b - a) * (Double(i) / Double(n))
            let d = BobForm.bodySDF(p)
            let seg = L / Double(n)
            if d > 0 && prev > 0 { out += seg }
            else if d > 0 || prev > 0 { out += seg * max(d, prev) / (abs(d) + abs(prev) + 1e-12) }
            prev = d
        }
        return out + (BobForm.bodySDF(b) > -r2 ? r2 : 0)
    }
    /// The wave's largest exposed length over its whole path (the approved reference), plus 2 % slack for the sampled metric.
    static let maximum: Double = {
        var m = 0.0
        for i in 0...100 {
            let g = ArmPath.wave.geomRaw(at: Double(i) / 100)
            m = max(m, exposed(a: g.A, b: g.B, r2: g.r2))
        }
        return m
    }()
    static let waveMax: Double = maximum
    /// The wave's shallowest root burial (centre depth below the egg surface, u) once it is posed: a closed capsule arm must be at least this
    /// deep, so its base is swallowed by the body like the wave's thumb instead of standing on the surface as a bare tube.
    static let minRootDepth: Double = {
        var m = 1.0
        for i in 40...100 { let g = ArmPath.wave.geomRaw(at: Double(i) / 100); m = min(m, -BobForm.bodySDF(g.A)) }
        return m
    }()
    /// The whole arm slid inward (along -x of the +x arm, length and radii unchanged) until its root is buried `minRootDepth` deep.
    static func fuse(a: SIMD3<Double>, b: SIMD3<Double>) -> (a: SIMD3<Double>, b: SIMD3<Double>) {
        if -BobForm.bodySDF(a) >= minRootDepth { return (a, b) }
        var lo = 0.0, hi = max(a.x, 0.05)
        for _ in 0..<14 {
            let m = 0.5 * (lo + hi)
            if -BobForm.bodySDF(a - SIMD3(m, 0, 0)) >= minRootDepth { hi = m } else { lo = m }
        }
        let d = SIMD3(hi, 0, 0)
        return (a - d, b - d)
    }
    /// `b` pulled toward `a` until the exposed length is within the cap (unchanged when already within it).
    /// The resting nub's exposed length (u): the limit for the body-led moves (jacks, flip, name hop ...): the arms stay at or below the rest nub,
    /// only the wave may raise an arm further.
    static let restNub: Double = exposed(a: BobForm.armTop, b: BobForm.armTip, r2: BobForm.armTipR)
    /// The cap `w` of the way (0...1) from the wave's maximum toward the rest nub's (`w` = the body-led override weight). Walk / run arms (w = 0) keep the wave cap.
    static func limit(bodyLed w: Double) -> Double { maximum + (min(restNub, maximum) - maximum) * smoothW(w) }
    private static func smoothW(_ w: Double) -> Double { let x = min(max(w, 0), 1); return x * x * (3 - 2 * x) }
    static func clampTip(a: SIMD3<Double>, b: SIMD3<Double>, r2: Double, scale: Double = 1, limit: Double? = nil) -> SIMD3<Double> {
        let cap = (limit ?? maximum) * scale
        if exposed(a: a, b: b, r2: r2, samples: 10) <= cap { return b }
        var lo = 0.0, hi = 1.0
        for _ in 0..<8 {
            let m = 0.5 * (lo + hi)
            if exposed(a: a, b: a + (b - a) * m, r2: r2, samples: 10) <= cap { lo = m } else { hi = m }
        }
        return a + (b - a) * lo
    }
}

// MARK: - Fillet collar (capsule arms)

/// The wave's join is a smooth union of the egg and the arm (`PosedArmField`, smin with k about 0.12). The capsule arms get the same join at run time:
/// a skin vertex on the egg at cone distance c from the arm is raised along the egg normal by the smin bump h^2 k / 4, h = max(k - |c|, 0) / k.
nonisolated enum ArmCollar {
    static let k = 0.12
    /// Bump height for a skin vertex at cone distance `c` (the first-order smooth-union fillet).
    @inline(__always) static func bump(_ c: Float) -> Float {
        let kk = Float(k), h = max(kk - abs(c), 0) / kk
        return h * h * kk * 0.25
    }
    /// Rest-space data of the collar: vertex ids, side (0 / 1), mirrored (+x arm convention) rest positions and outward egg normals.
    struct Set { var ids: [Int32] = [], side: [Int8] = [], pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = []; var ranges: [Range<Int>] = [0..<0, 0..<0] }
    /// Skin vertices within `reach` of the shoulder (both sides) that are not capsule / bean vertices (`skip`).
    static func build(rest: [Float], skip: [Range<Int>], reach: Double = 0.36) -> Set {
        var out = Set()
        let W = ArmPath.armWalkRoot, sh = SIMD3<Double>(W.x, W.y, W.z)
        for side in 0..<2 {
            let first = out.ids.count
            for v in 0..<(rest.count / 3) where !skip.contains(where: { $0.contains(v) }) {
                let x = Double(rest[3 * v]), y = Double(rest[3 * v + 1]), z = Double(rest[3 * v + 2])
                if abs(x) < 0.25 || y < 0.15 || y > 1.0 || (x < 0 ? 0 : 1) != side { continue }
                let p = SIMD3(abs(x), y, z)
                if simd_length(p - sh) > reach { continue }
                let n = simd_normalize(BobForm.eggGradient(p))
                out.ids.append(Int32(v)); out.side.append(Int8(side))
                out.pos.append(SIMD3<Float>(p)); out.nrm.append(SIMD3<Float>(n))
            }
            out.ranges[side] = first..<out.ids.count
        }
        return out
    }
    /// Fill `delta` (world, before the armBlend scale) for the two sides' capsules `g` (body frame, +x convention); `M` carries rest space into the world.
    static func fill(_ set: Set, geoms g: [(a: SIMD3<Float>, b: SIMD3<Float>, r1: Float, r2: Float, f: Float)], M: simd_float3x3, side only: Int, into delta: inout [SIMD3<Float>]) {
        if delta.count != set.ids.count { delta = [SIMD3<Float>](repeating: .zero, count: set.ids.count) }
        var mid = [SIMD3<Float>](repeating: .zero, count: 2), rad2 = [Float](repeating: 0, count: 2)
        for s in 0..<2 {
            let gg = g[s], F = gg.f
            let a = SIMD3(gg.a.x, gg.a.y, gg.a.z * F), b = SIMD3(gg.b.x, gg.b.y, gg.b.z * F)
            mid[s] = (a + b) * 0.5
            let r = simd_length(b - a) * 0.5 + max(gg.r1, gg.r2) + Float(k) + 0.02
            rad2[s] = r * r * F       // flatten stretches z at most by F
        }
        for i in set.ranges[only] {
            let s = only, gg = g[s]
            let F = gg.f
            let p = set.pos[i], q = SIMD3(p.x, p.y, p.z * F)
            let dm = q - mid[s]
            if simd_dot(dm, dm) > rad2[s] { delta[i] = .zero; continue }
            let a = SIMD3(gg.a.x, gg.a.y, gg.a.z * F), b = SIMD3(gg.b.x, gg.b.y, gg.b.z * F)
            let c = roundConeF(q, a, b, gg.r1, gg.r2) / F.squareRoot()
            let d = bump(c)
            if d < 1e-5 { delta[i] = .zero; continue }
            let sg: Float = s == 0 ? -1 : 1
            let n = set.nrm[i]
            delta[i] = M * (SIMD3(n.x * sg, n.y, n.z) * d)
        }
    }
    @inline(__always) static func roundConeF(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ r1: Float, _ r2: Float) -> Float {
        let ba = b - a, l2 = simd_dot(ba, ba), rr = r1 - r2, a2 = l2 - rr * rr, il2 = 1 / max(l2, 1e-9)
        let pa = p - a, y = simd_dot(pa, ba), z = y - l2
        let w = pa * l2 - ba * y
        let x2 = simd_dot(w, w), y2 = y * y * l2, z2 = z * z * l2
        let k = (rr < 0 ? -1 : 1) * rr * rr * x2
        if (z < 0 ? -1 : 1) * a2 * z2 > k { return (x2 + z2).squareRoot() * il2 - r2 }
        if (y < 0 ? -1 : 1) * a2 * y2 < k { return (x2 + y2).squareRoot() * il2 - r1 }
        return ((x2 * a2 * il2).squareRoot() + y * rr) * il2 - r1
    }
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
    /// First vertex of the foot bean of a side: it follows the arm capsule inside the same block.
    func beanFirst(side: Int) -> Int { first(side: side) + ArmCapsule.vertexCount }
}

// MARK: - Fast capsule fill (walking arm, per tick)

extension ArmCapsule {
    private static let thCos: [Float] = (0..<around).map { cosf(2 * .pi * Float($0) / Float(around)) }
    private static let thSin: [Float] = (0..<around).map { sinf(2 * .pi * Float($0) / Float(around)) }

    /// Same revolve as `points` in Float with cached angle tables (no trig per vertex): body-frame (+x arm convention) cone `a` (root) -> `b` (tip), radii
    /// `r1` / `r2`, z-flatten `F`, mirrored by `sigma`, grown by `inflate`.
    static func fill(a a0: SIMD3<Float>, b b0: SIMD3<Float>, r1: Float, r2: Float, flatten F: Float, sigma: Float, inflate: Float = 0, into out: inout [SIMD3<Float>]) {
        if out.count != vertexCount { out = [SIMD3<Float>](repeating: .zero, count: vertexCount) }
        let sF = F.squareRoot()
        let a = SIMD3(a0.x, a0.y, a0.z * F), b = SIMD3(b0.x, b0.y, b0.z * F)
        let ba = b - a, L = simd_length(ba), u = ba / max(L, 1e-6)
        let R1 = r1 + inflate * sF, R2 = r2 + inflate * sF
        let alpha = acosf(min(max((R1 - R2) / max(L, 1e-6), -1), 1))
        var e1 = SIMD3<Float>(0, 0, 1) - u * u.z
        if simd_length(e1) < 1e-4 { e1 = SIMD3(1, 0, 0) - u * u.x }
        e1 = simd_normalize(e1)
        let e2 = simd_cross(u, e1)
        var k = 0
        @inline(__always) func put(_ p: SIMD3<Float>) { out[k] = SIMD3(p.x * sigma, p.y, p.z / F); k += 1 }
        put(b + u * R2)
        for i in 1...tipRings {
            let phi = alpha * Float(i) / Float(tipRings), c = cosf(phi), s = sinf(phi)
            for j in 0..<around { put(b + (u * c + (e1 * thCos[j] + e2 * thSin[j]) * s) * R2) }
        }
        for i in 0..<rootRings {
            let phi = alpha + (.pi - alpha) * Float(i) / Float(rootRings), c = cosf(phi), s = sinf(phi)
            for j in 0..<around { put(a + (u * c + (e1 * thCos[j] + e2 * thSin[j]) * s) * R1) }
        }
        put(a - u * R1)
    }

    /// Baked crease occlusion (0...0.38) of the walking capsule's vertices: darker toward the buried root, so the junction reads as a soft clay crease.
    static let creaseAO: [Float] = {
        var m = [Float](repeating: 0, count: vertexCount)
        // W1c: the capsule reads pale and flat without occlusion at its base. The shaft is one long strip between ring `tipRings - 1` (tip equator)
        // and ring `tipRings` (root, buried), so the AO runs along it: ~0.30 at the buried root ring (about 0.16 where the shaft leaves the skin) and 0 at
        // the tip, plus the egg's occlusion on the shaft's UNDERSIDE (ring angle 90 deg = down), strongest near the root.
        for r in 0..<ringCount {
            for j in 0..<around {
                let th = 2 * Float.pi * Float(j) / Float(around)
                var v: Float = 0
                if r >= tipRings {                                  // root rings: 0.28 at the strip's buried end rising to 0.38 at the pole
                    v = 0.28 + 0.10 * Float(r - tipRings) / Float(rootRings - 1)
                    v += 0.10 * max(0, sinf(th))                    // underside (ring angle 90 deg = down)
                }
                m[1 + around * r + j] = min(0.4, v)
            }
        }
        m[vertexCount - 1] = 0.38
        return m
    }()
}
