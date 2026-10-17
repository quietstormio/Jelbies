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

/// The wave's timeline, measured from the reference video (docs: motion table, REF1 t = 7.58 ... 9.58 s). Seconds since the wave began ->
/// path parameter s of `ArmPath.wave` (0 = resting arm, 0.4 = arm out, 1 = arm up) plus the body's lean / foot-lift envelopes and the two
/// short eye closes. Only s drives the arm's shape; nothing is lerped in time. `duration` includes the retract.
struct WaveScript {
    static let raise: Float = 0.33                  // rest -> out
    static let firstPeak: Float = 0.68              // first up-swing peak
    static let period: Float = 0.495                // 2.02 Hz
    static let hz: Float = 1 / 0.495
    static let swings = 3
    static let endSwing: Float = 1.90               // last trough, then the arm retracts
    static let retract: Float = 0.10
    static var duration: Float { endSwing + retract }
    static let outS: Float = 0.4, upS: Float = 1.0

    static func s(at t: Float) -> Float {
        if t < raise { return outS * smooth01(t / raise) }
        if t < firstPeak {
            let u = (t - raise) / (firstPeak - raise)
            return outS + (upS - outS) * (1 - (1 - u) * (1 - u))
        }
        if t < endSwing { return 0.70 + 0.30 * cosf(2 * .pi * (t - firstPeak) / period) }
        return outS * (1 - smooth01((t - endSwing) / retract))
    }
    /// 0...1 how far the arm is out (kept for callers that want an arm-extension measure).
    static func extend(at t: Float) -> Float { min(1, s(at: t) / outS) }

    /// 0...1 roll envelope of the body leaning away from the arm: 0 -> 1 over 0.2 ... 0.9 s (ease-out), plateau to 1.25 s, release by 1.9 s.
    static func lean(at t: Float) -> Float {
        if t < 0.2 { return 0 }
        if t < 0.9 { let u = (t - 0.2) / 0.7; return 1 - (1 - u) * (1 - u) }
        if t < 1.25 { return 1 }
        return 1 - smooth01((t - 1.25) / 0.65)
    }
    /// 0...1 lift (and sideways swing) of the arm-side foot: rises 0.40 -> 0.85 s, held to 1.25 s, drops to 0.23 by 1.45 s, lands by 1.55 s.
    static func footLift(at t: Float) -> Float {
        if t < 0.40 { return 0 }
        if t < 0.85 { return smooth01((t - 0.40) / 0.45) }
        if t < 1.25 { return 1 }
        if t < 1.45 { return 1 - 0.77 * smooth01((t - 1.25) / 0.20) }
        if t < 1.55 { return 0.23 * (1 - smooth01((t - 1.45) / 0.10)) }
        return 0
    }
    /// The two short eye closes (fully shut, like a blink): 0.10 s at the first out-swing, 0.12 s near the end.
    static func eyesShut(at t: Float) -> Bool { (t >= 0.33 && t < 0.43) || (t >= 1.52 && t < 1.64) }
}

// MARK: - Feet

/// Rest-frame geometry of the two feet (index 0 = side -1 / image-left when he faces the camera, 1 = side +1), from the sim mesh.
struct FootGeom {
    var particles: [[Int]] = [[], []]
    var rest: [[SIMD3<Float>]] = [[], []]
    /// Mean of the lowest particles of each foot (rest coordinates, y = rest height of the sole).
    var contact: [SIMD3<Float>] = [.zero, .zero]
    /// Contact xz relative to the rest centroid (body frame).
    var off: [SIMD2<Float>] = [.zero, .zero]
    /// z of the rear of each sole (rest coordinates): the toe-up tilt pivots there.
    var heelZ: [Float] = [0, 0]
    var mid: SIMD3<Float> = .zero
    var midOff: SIMD2<Float> = .zero
    var valid = false

    init() {}
    init(sim: SoftBody) {
        let c0 = sim.restCentroid
        for a in sim.appendages where a.kind == .foot { particles[a.side < 0 ? 0 : 1] += a.particles }
        guard !particles[0].isEmpty, !particles[1].isEmpty else { return }
        for k in 0..<2 {
            rest[k] = particles[k].map { sim.restPosition($0) }
            let ymin = rest[k].map(\.y).min() ?? 0
            let low = rest[k].filter { $0.y < ymin + 0.02 }
            var c = SIMD3<Float>(0, ymin, 0)
            for p in low { c.x += p.x; c.z += p.z }
            c.x /= Float(low.count); c.z /= Float(low.count)
            contact[k] = c
            heelZ[k] = low.map(\.z).min() ?? c.z
            off[k] = SIMD2(c.x - c0.x, c.z - c0.z)
        }
        mid = (contact[0] + contact[1]) / 2
        midOff = (off[0] + off[1]) / 2
        valid = true
    }
}

/// Rotate a body-frame xz vector (x = his right = +x, z = forward) by heading `yaw` (0 faces +z, pi/2 faces +x) into world xz.
@inline(__always) func rotXZ(_ v: SIMD2<Float>, _ yaw: Float) -> SIMD2<Float> {
    let c = cosf(yaw), s = sinf(yaw)
    return SIMD2(v.x * c + v.y * s, -v.x * s + v.y * c)
}

/// World-space feet. Each foot is either planted (xz fixed) or in a swing (xz eases from `from` to `to`, height = a lift arc). Steps are
/// started by the brain; the cadence is fixed (`rate` steps/s), a step lasts 1/rate seconds, the swing takes `swingFrac` of it and the
/// foot is planted for the rest, so consecutive steps always have a short double support and he can never stop mid-swing.
struct FootGait {
    var pos: [SIMD2<Float>] = [.zero, .zero]
    var yaw: [Float] = [0, 0]
    private(set) var active = false
    private(set) var side = 0
    private(set) var t: Float = 0
    private(set) var rate: Float = 3.5
    private(set) var swingFrac: Float = 0.85
    private var from = SIMD2<Float>.zero, to = SIMD2<Float>.zero
    private var fromYaw: Float = 0, toYaw: Float = 0
    private var peak: Float = 0
    private var outAmp: Float = 0, tiltPeak: Float = 0, fwdAmp: Float = 0

    var stepTime: Float { 1 / rate }
    var swingTime: Float { swingFrac / rate }
    var swinging: Bool { active && t < swingTime }
    /// Progress of the whole step 0...1 (stays 1 after the step ends until the next begins).
    var stepU: Float { min(1, t / stepTime) }
    /// Progress of the swing 0...1.
    var swingU: Float { active ? min(1, t / swingTime) : 0 }

    mutating func reset() { active = false; t = 0 }

    /// `out`: how far (world units) the swing foot swings sideways away from the body at mid swing; `tilt`: toe-up angle (rad) at mid swing
    /// so the sole shows from the front.
    mutating func begin(side s: Int, to target: SIMD2<Float>, toYaw ty: Float, peak h: Float, rate r: Float, swingFrac f: Float = 0.85,
                        out: Float = 0, tilt: Float = 0, fwd: Float = 0) {
        active = true; t = 0; side = s; rate = r; swingFrac = f
        from = pos[s]; to = target; fromYaw = yaw[s]; toYaw = ty; peak = h; outAmp = out; tiltPeak = tilt; fwdAmp = fwd
    }

    mutating func advance(_ dt: Float) {
        guard active else { return }
        t += dt
        if t >= swingTime { pos[side] = to; yaw[side] = toYaw }
        if t >= stepTime { active = false; t = stepTime }
    }

    /// Current xz / yaw / lift / sideways swing / toe-up tilt of `s` (planted feet report their fixed values and zeros).
    func state(_ s: Int) -> (xz: SIMD2<Float>, yaw: Float, h: Float, out: Float, tilt: Float, fwd: Float) {
        guard swinging, s == side else { return (pos[s], yaw[s], 0, 0, 0, 0) }
        let u = swingU
        let e = u * u * (3 - 2 * u)
        let arc = max(0, sinf(.pi * u))
        return (from + (to - from) * e, fromYaw + wrapAngle(toYaw - fromYaw) * e, peak * powf(arc, 0.8), outAmp * arc * arc, tiltPeak * arc, fwdAmp * arc * arc)
    }
}

// MARK: - Rigid foot render

/// Which render vertices belong to each foot's rigid "bean": those embedded in the slab prisms under the foot (core, weight 1) plus a
/// junction band of the belly underside around it whose weight fades to 0, so the skin stretches a little instead of folding. The sim
/// foot is only a thin slab (`BobForm.lift` tall) driven by its sole particles, so when a foot leaves the floor the render draws the bean
/// as a rigid body through `Skinner.feetVertices` instead of letting the slab shear and invert.
struct FootSkin {
    var verts: [[Int32]] = [[], []]
    var rest: [[SIMD3<Float>]] = [[], []]
    var dist: [[Float]] = [[], []]       // rest distance to the nearest core vertex (0 for the core)
    var sdf: [[Float]] = [[], []]        // rest-space signed distance to the foot ellipsoid (BobForm.footSDF, mirrored): the smooth weight coordinate
    var coreCount: [Int] = [0, 0]
    var valid = false
    static let plateau: Float = 0.0     // belly vertices this close to the bean ring move WITH it (a thin gradient there would fold into a flap)
    static let band: Float = 0.025         // fade length for a small foot motion
    static let bandMax: Float = 0.26      // ... widening with the foot's displacement so the skin tents smoothly instead of creasing
    static var bandGain: Float = 0
    static func bandWidth(displacement d: Float) -> Float { min(bandMax, plateau + band + bandGain * d) }
    /// Weight of a vertex at rest distance `dist` from the bean: 1 on the bean and on the plateau, then smooth to 0 at the band width.
    static func weight(dist: Float, width: Float) -> Float {
        if dist <= plateau { return 1 }
        let t = min(1, (dist - plateau) / max(1e-4, width - plateau))
        return 1 - t * t * (3 - 2 * t)
    }

    init() {}
    init(renderRest: [Float], skinner: Skinner, footParticles: [[Int]]) {
        let n = renderRest.count / 3
        func p(_ v: Int) -> SIMD3<Float> { SIMD3(renderRest[3 * v], renderRest[3 * v + 1], renderRest[3 * v + 2]) }
        var isCore = [Bool](repeating: false, count: n)
        var core: [[Int32]] = [[], []]
        for s in 0..<2 {
            core[s] = skinner.vertices(touching: Set(footParticles[s].map { Int32($0) }))
            for v in core[s] { isCore[Int(v)] = true }
        }
        // spatial hash of the core vertices
        let cell = Self.bandMax
        func key(_ q: SIMD3<Float>) -> SIMD3<Int> { SIMD3(Int((q.x / cell).rounded(.down)), Int((q.y / cell).rounded(.down)), Int((q.z / cell).rounded(.down))) }
        var grid: [SIMD3<Int>: [(Int, Int32)]] = [:]
        for s in 0..<2 { for v in core[s] { grid[key(p(Int(v))), default: []].append((s, v)) } }
        var band: [[(Int32, Float)]] = [[], []]       // (vertex, rest distance)
        for v in 0..<n where !isCore[v] {
            let q = p(v)
            if q.y > 0.5 { continue }
            let k = key(q)
            var best: Float = .infinity, bs = 0
            for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                guard let list = grid[SIMD3(k.x + dx, k.y + dy, k.z + dz)] else { continue }
                for (s, c) in list { let d = simd_distance(q, p(Int(c))); if d < best { best = d; bs = s } }
            } } }
            if best < Self.bandMax { band[bs].append((Int32(v), best)) }
        }
        for s in 0..<2 {
            verts[s] = core[s] + band[s].map(\.0)
            rest[s] = verts[s].map { p(Int($0)) }
            dist[s] = [Float](repeating: 0, count: core[s].count) + band[s].map(\.1)
            coreCount[s] = core[s].count
            sdf[s] = rest[s].map { q in Float(BobForm.footSDF(SIMD3(Double(abs(q.x)), Double(q.y), Double(q.z)))) }
        }
        valid = !verts[0].isEmpty && !verts[1].isEmpty
    }
}

/// The nubForward / nubBack paths touch slightly different render vertices; the nub override always lists the UNION per side (zero delta and
/// the baked AO for vertices the current path does not move), so the vertex list never changes and the AO restore is exact.
struct NubUnion {
    var verts: [Int32] = []
    var delta: [SIMD3<Float>] = []
    var ao: [Float] = []
    private var idxF: [Int] = [], idxB: [Int] = []
    private var restMat: [Float] = []

    var isEmpty: Bool { verts.isEmpty }

    init(_ f: ArmKeyframes, _ b: ArmKeyframes, side: Int) {
        let F = f.side(side), B = b.side(side)
        var pos: [Int32: Int] = [:]
        for (i, v) in F.vertices.enumerated() { pos[v] = i; verts.append(v); restMat.append(F.restMat[i]) }
        idxF = Array(0..<F.vertices.count)
        for (i, v) in B.vertices.enumerated() {
            if let p = pos[v] { idxB.append(p) } else { pos[v] = verts.count; idxB.append(verts.count); verts.append(v); restMat.append(B.restMat[i]) }
        }
        delta = [SIMD3<Float>](repeating: .zero, count: verts.count)
        ao = restMat
    }

    mutating func fill(forward: Bool, delta d: [SIMD3<Float>], ao a: [Float]) {
        for i in 0..<delta.count { delta[i] = .zero; ao[i] = restMat[i] }
        let map = forward ? idxF : idxB
        for (i, u) in map.enumerated() { delta[u] = d[i]; ao[u] = a[i] }
    }
}
