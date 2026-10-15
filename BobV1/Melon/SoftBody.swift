//
//  SoftBody.swift
//  XPBD tetrahedral soft body (port of physics.js)
//   - co-rotational tet constraints: each tet is pulled toward its best-fit rotated rest shape
//     (recovers inversions)
//   - tet volume constraints: near-incompressibility
//   - soft grab attachment, ground contact with friction
//   - relative-velocity damping along edges (internal viscosity)
//   - a soft rigid-pose attractor (shape-matching fit of the whole body + a spring toward a scripted pose),
//     used by the gaits in Locomotion.swift; strength 0 = plain free physics
//  Fixed step, fixed substeps, "small steps" XPBD (1 iteration / substep).
//  Hot loops run on raw pointers (no bounds checks, no copy-on-write).
//

import Foundation
import simd

/// Soft pull of every particle toward `anchor + rotation * (squash * restOffset)`. `strength` is a stiffness in
/// 1/s^2 (0 = off, ~300 loose, ~1500 firm); `squash` scales the target about its centroid along its own up axis
/// (volume preserving), so a gait can script squash and stretch. `damping` is the damping ratio of the spring.
/// `anchor` is where the body's mass centroid should be. The values you set are the state at the END of the
/// next fixed step; the body interpolates from the previous step's values across the substeps.
struct Attractor {
    var strength: Float = 0
    var anchor = SIMD3<Float>(0, 0, 0)
    var rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var squash: Float = 1
    var damping: Float = 0.55
}

/// Soft pull of one particle toward a world position (animation hook: wave arm, lifted foot). `stiffness` is in 1/s^2
/// like `Attractor.strength`. Solved after the attractor so it wins over the rigid pose; empty list = no effect.
struct ParticleTarget {
    var index: Int
    var pos: SIMD3<Float>
    var stiffness: Float
}

/// Whole-body rigid fit (mass-weighted shape matching).
struct BodyPose {
    var centroid: SIMD3<Float>
    var rotation: simd_quatf
    /// Angle in radians between the body's up axis and world up (0 = upright, pi = upside down).
    var tilt: Float { acosf(max(-1, min(1, rotation.act(SIMD3<Float>(0, 1, 0)).y))) }
    /// Heading of the body's face (+z) about world y: 0 faces +z, pi/2 faces +x.
    var yaw: Float { let f = rotation.act(SIMD3<Float>(0, 0, 1)); return atan2f(f.x, f.z) }
}

final class SoftBody {
    let n: Int
    let nT: Int
    let nE: Int
    var x: [Float]
    var v: [Float]
    let tets: [UInt32]
    let edges: [UInt32]
    let totalRestVolume: Float
    let totalMass: Float

    // parameters (tuned in sim units: metres-ish, seconds)
    var firmness: Float
    var damping: Float
    var stepDt: Float = 1.0 / 60
    var substeps: Int = 10
    var gravity: Float = -9.81
    var friction: Float = 0.55
    var floorY: Float = 0
    var maxSpeed: Float = 12
    private(set) var grabbing = false
    private(set) var time: Float = 0
    private var restSteps = 0

    // static data (raw storage, freed in deinit)
    private let rest: UnsafeMutablePointer<Float>
    private let prev: UnsafeMutablePointer<Float>
    private let invMass: UnsafeMutablePointer<Float>
    private let mass: UnsafeMutablePointer<Float>
    private let restVol: UnsafeMutablePointer<Float>
    private let restLen: UnsafeMutablePointer<Float>
    private let tetIdx: UnsafeMutablePointer<Int32>
    private let edgeIdx: UnsafeMutablePointer<Int32>
    private let tetQ: UnsafeMutablePointer<Float>      // rest positions relative to tet centroid (4 x xyz)
    private let tetRot: UnsafeMutablePointer<Float>    // warm-started quaternion (x, y, z, w)
    private let tetFirm: UnsafeMutablePointer<Float>
    private let tetVolScale: UnsafeMutablePointer<Float>   // per-tet volume-compliance multiplier (1 = normal)
    private let tetFirm0: [Float]                          // tetFirm as built (restored by restoreStiffness)

    /// Arm / foot particle chains from the sim mesh (empty for legacy meshes). Read-only animation handles.
    let appendages: [SimAppendage]
    /// Per-particle animation targets (see `ParticleTarget`); the caller refreshes them every fixed step.
    var targets: [ParticleTarget] = []

    // rigid-pose attractor
    var attractor = Attractor()
    private var attPrev = Attractor()
    private var attFresh = true
    private let restOff: UnsafeMutablePointer<Float>   // rest minus mass-weighted rest centroid (n x xyz)
    private let attT: UnsafeMutablePointer<Float>      // previous target positions
    private let attV: UnsafeMutablePointer<Float>      // target velocities
    private var fitQ = SIMD4<Float>(0, 0, 0, 1)        // warm-started best-fit rotation (x, y, z, w)
    let restCentroid: SIMD3<Float>
    /// Invisible round wall: particles are kept within `arenaRadius` of `arenaCenter` (xz). Infinite = off.
    var arenaCenter = SIMD2<Float>(0, 0)
    var arenaRadius: Float = .infinity

    // grab state
    private let grabIdx: UnsafeMutablePointer<Int32>
    private let grabW: UnsafeMutablePointer<Float>
    private let grabOff: UnsafeMutablePointer<Float>
    private var grabN = 0
    private var grabTarget = SIMD3<Float>(0, 0, 0)
    private var grabStart = SIMD3<Float>(0, 0, 0)
    private var grabRot: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]

    init(mesh: SimMesh, firmness: Float = 0.95, damping: Float = 0.45) {
        let rest0 = mesh.rest, tets = mesh.tets, region = mesh.region
        let n = rest0.count / 3, nT = tets.count / 4
        self.n = n; self.nT = nT
        self.tets = tets
        self.firmness = firmness
        self.damping = damping
        x = [Float](repeating: 0, count: rest0.count)
        v = [Float](repeating: 0, count: rest0.count)

        func alloc<T>(_ c: Int, _ z: T) -> UnsafeMutablePointer<T> {
            let p = UnsafeMutablePointer<T>.allocate(capacity: max(c, 1)); p.initialize(repeating: z, count: max(c, 1)); return p
        }
        rest = alloc(rest0.count, 0); prev = alloc(rest0.count, 0)
        invMass = alloc(n, 0); mass = alloc(n, 0); restVol = alloc(nT, 0)
        tetIdx = alloc(nT * 4, 0); tetQ = alloc(nT * 12, 0); tetRot = alloc(nT * 4, 0); tetFirm = alloc(nT, 0)
        tetVolScale = alloc(nT, 1)
        appendages = mesh.appendages
        grabIdx = alloc(n, 0); grabW = alloc(n, 0); grabOff = alloc(n * 3, 0)
        restOff = alloc(n * 3, 0); attT = alloc(n * 3, 0); attV = alloc(n * 3, 0)
        for i in 0..<rest0.count { rest[i] = rest0[i] }
        for i in 0..<(nT * 4) { tetIdx[i] = Int32(tets[i]) }

        // masses from rest volumes (density 1)
        func vol(_ t: Int) -> Float {
            let a = Int(tets[4 * t]), b = Int(tets[4 * t + 1]), c = Int(tets[4 * t + 2]), d = Int(tets[4 * t + 3])
            let ax = rest0[3 * a], ay = rest0[3 * a + 1], az = rest0[3 * a + 2]
            let b0 = rest0[3 * b] - ax, b1 = rest0[3 * b + 1] - ay, b2 = rest0[3 * b + 2] - az
            let c0 = rest0[3 * c] - ax, c1 = rest0[3 * c + 1] - ay, c2 = rest0[3 * c + 2] - az
            let d0 = rest0[3 * d] - ax, d1 = rest0[3 * d + 1] - ay, d2 = rest0[3 * d + 2] - az
            return (b0 * (c1 * d2 - c2 * d1) - b1 * (c0 * d2 - c2 * d0) + b2 * (c0 * d1 - c1 * d0)) / 6
        }
        var tv: Float = 0
        for t in 0..<nT {
            let vv = vol(t)
            restVol[t] = vv; tv += vv
            for k in 0..<4 { mass[Int(tets[4 * t + k])] += vv / 4 }
        }
        totalRestVolume = tv
        var tm: Float = 0
        for i in 0..<n { invMass[i] = 1 / mass[i]; tm += mass[i] }
        totalMass = tm
        var rc = SIMD3<Float>(0, 0, 0)
        for i in 0..<n { rc += SIMD3(rest0[3 * i], rest0[3 * i + 1], rest0[3 * i + 2]) * mass[i] }
        rc /= tm
        restCentroid = rc
        for i in 0..<n {
            restOff[3 * i] = rest0[3 * i] - rc.x; restOff[3 * i + 1] = rest0[3 * i + 1] - rc.y; restOff[3 * i + 2] = rest0[3 * i + 2] - rc.z
        }

        // unique edges, in first-seen order (like the JS Map)
        var seen = Set<UInt64>()
        var list: [(UInt32, UInt32)] = []
        let pairs = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)]
        for t in 0..<nT {
            for (pa, pb) in pairs {
                var i = tets[4 * t + pa], j = tets[4 * t + pb]
                if i > j { swap(&i, &j) }
                if seen.insert(UInt64(i) << 32 | UInt64(j)).inserted { list.append((i, j)) }
            }
        }
        nE = list.count
        restLen = alloc(nE, 0)
        edgeIdx = alloc(nE * 2, 0)
        for (e, p) in list.enumerated() {
            edgeIdx[2 * e] = Int32(p.0); edgeIdx[2 * e + 1] = Int32(p.1)
            let i = Int(p.0), j = Int(p.1)
            let dx = rest0[3 * i] - rest0[3 * j], dy = rest0[3 * i + 1] - rest0[3 * j + 1], dz = rest0[3 * i + 2] - rest0[3 * j + 2]
            restLen[e] = (dx * dx + dy * dy + dz * dz).squareRoot()
        }
        // shuffle edge order a little (reduces Gauss-Seidel directional bias)
        if nE > 1 {
            for k in stride(from: nE - 1, to: 0, by: -1) {
                let r = Int((UInt64(k) &* 2654435761) % UInt64(k + 1))
                let a0 = edgeIdx[2 * k], a1 = edgeIdx[2 * k + 1]
                edgeIdx[2 * k] = edgeIdx[2 * r]; edgeIdx[2 * k + 1] = edgeIdx[2 * r + 1]
                edgeIdx[2 * r] = a0; edgeIdx[2 * r + 1] = a1
                let tmp = restLen[k]; restLen[k] = restLen[r]; restLen[r] = tmp
            }
        }
        var ev = [UInt32](repeating: 0, count: nE * 2)
        for i in 0..<(nE * 2) { ev[i] = UInt32(edgeIdx[i]) }
        edges = ev

        // co-rotational tet elasticity: rest shape about the mass centroid, warm-started rotation
        for t in 0..<nT {
            let id = (0..<4).map { Int(tets[4 * t + $0]) }
            var cx: Float = 0, cy: Float = 0, cz: Float = 0, M: Float = 0
            for vtx in id {
                let mv = mass[vtx]; M += mv
                cx += rest0[3 * vtx] * mv; cy += rest0[3 * vtx + 1] * mv; cz += rest0[3 * vtx + 2] * mv
            }
            cx /= M; cy /= M; cz /= M
            for k in 0..<4 {
                tetQ[12 * t + 3 * k] = rest0[3 * id[k]] - cx
                tetQ[12 * t + 3 * k + 1] = rest0[3 * id[k] + 1] - cy
                tetQ[12 * t + 3 * k + 2] = rest0[3 * id[k] + 2] - cz
            }
            tetRot[4 * t + 3] = 1
            var rg = 0
            for vtx in id { rg += Int(region[vtx]) }
            tetFirm[t] = rg >= 6 ? 0.3 : rg >= 3 ? 0.5 : rg >= 1 ? 0.75 : 1.0
        }
        let tf0 = tetFirm
        tetFirm0 = (0..<nT).map { tf0[$0] }
        targets = []
        reset(drop: 0)
    }

    deinit {
        rest.deallocate(); prev.deallocate(); invMass.deallocate(); mass.deallocate(); restVol.deallocate()
        restLen.deallocate(); tetIdx.deallocate(); edgeIdx.deallocate(); tetQ.deallocate(); tetRot.deallocate()
        tetFirm.deallocate(); tetVolScale.deallocate(); grabIdx.deallocate(); grabW.deallocate(); grabOff.deallocate()
        restOff.deallocate(); attT.deallocate(); attV.deallocate()
    }

    func reset(drop: Float = 0.35) {
        for i in 0..<n {
            x[3 * i] = rest[3 * i]
            x[3 * i + 1] = rest[3 * i + 1] + drop
            x[3 * i + 2] = rest[3 * i + 2]
        }
        for i in 0..<(3 * n) { prev[i] = x[i]; v[i] = 0 }
        for t in 0..<nT { tetRot[4 * t] = 0; tetRot[4 * t + 1] = 0; tetRot[4 * t + 2] = 0; tetRot[4 * t + 3] = 1 }
        fitQ = SIMD4<Float>(0, 0, 0, 1)
        attractor = Attractor(); attPrev = Attractor(); attFresh = true
        endGrab()
    }

    // stiffness mapping: firmness 0..1 -> edge compliance (log scale)
    private func shapeCompliance() -> Float { expf(logf(3.0) + (logf(0.05) - logf(3.0)) * firmness) }
    private func volCompliance() -> Float { 1e-4 * (1 - 0.7 * firmness) }
    // damping 0..1 -> rate (1/s) of relative-velocity decay along edges
    private func dampRate() -> Float { 3 + 55 * damping * damping }

    // free-flight drag (1/s): the base air drag plus a damping-scaled share, so the whole slice calms down too
    private func airDrag() -> Float { 0.08 + 0.2 + 2 * damping * damping }

    /// Small hop with a twist: every particle gets v += v_lin + w x (x - c).
    func nudge(strength: Float = 1) {
        let c = centroid()
        let vy = 2.2 * strength, wx = 2.4 * strength, wz = -1.5 * strength, wy = 1.2 * strength
        for i in 0..<n {
            let rx = x[3 * i] - c.x, ry = x[3 * i + 1] - c.y, rz = x[3 * i + 2] - c.z
            v[3 * i] += wy * rz - wz * ry
            v[3 * i + 1] += vy + wz * rx - wx * rz
            v[3 * i + 2] += wx * ry - wy * rx
        }
    }

    /// Current heading of the body about +y (radians; rest +z maps to (sin t, cos t) in x,z).
    func yaw() -> Float {
        let c = centroid()
        var a: Float = 0, b: Float = 0
        for i in 0..<n {
            let rx = rest[3 * i], rz = rest[3 * i + 2]
            let cx = x[3 * i] - c.x, cz = x[3 * i + 2] - c.z
            a += rx * cx + rz * cz          // cos component
            b += rz * cx - rx * cz          // sin component
        }
        return atan2f(b, a)
    }

    func centroid() -> SIMD3<Float> {
        var sx: Float = 0, sy: Float = 0, sz: Float = 0, m: Float = 0
        x.withUnsafeBufferPointer { p in
            for i in 0..<n {
                let w = mass[i]; m += w
                sx += p[3 * i] * w; sy += p[3 * i + 1] * w; sz += p[3 * i + 2] * w
            }
        }
        return SIMD3(sx / m, sy / m, sz / m)
    }

    // MARK: animation hooks (temporary per-region softness)

    /// Rest position of particle `i` (body frame, floor at y = 0).
    func restPosition(_ i: Int) -> SIMD3<Float> { SIMD3(rest[3 * i], rest[3 * i + 1], rest[3 * i + 2]) }

    /// Temporarily loosen every tet that touches one of `particles` (shape compliance x `shapeScale`, volume compliance
    /// x `volScale`) so an animation can stretch that region (the wave arm). Replaces any previous setting.
    func setSoftRegion(particles: [Int], shapeScale: Float, volScale: Float) {
        restoreStiffness()
        let set = Set(particles)
        for t in 0..<nT {
            var touches = false
            for k in 0..<4 where set.contains(Int(tetIdx[4 * t + k])) { touches = true }
            if touches { tetFirm[t] = tetFirm0[t] * shapeScale; tetVolScale[t] = volScale }
        }
    }

    /// Put every tet back to its built stiffness (firmness itself is never touched).
    func restoreStiffness() {
        for t in 0..<nT { tetFirm[t] = tetFirm0[t]; tetVolScale[t] = 1 }
    }

    // MARK: grabbing

    func beginGrab(hit: SIMD3<Float>, radius: Float = 0.4) {
        grabN = 0
        var nearest = -1
        var nd = Float.infinity
        for i in 0..<n {
            let dx = x[3 * i] - hit.x, dy = x[3 * i + 1] - hit.y, dz = x[3 * i + 2] - hit.z
            let d = (dx * dx + dy * dy + dz * dz).squareRoot()
            if d < nd { nd = d; nearest = i }
            if d < radius {
                let f = 1 - d / radius
                let k = grabN; grabN += 1
                grabIdx[k] = Int32(i); grabW[k] = f * f * (3 - 2 * f)
                grabOff[3 * k] = dx; grabOff[3 * k + 1] = dy; grabOff[3 * k + 2] = dz
            }
        }
        if grabN == 0 && nearest >= 0 {
            grabIdx[0] = Int32(nearest); grabW[0] = 1
            grabOff[0] = x[3 * nearest] - hit.x; grabOff[1] = x[3 * nearest + 1] - hit.y; grabOff[2] = x[3 * nearest + 2] - hit.z
            grabN = 1
        }
        grabTarget = hit
        grabStart = hit
        grabRot = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        grabbing = true
    }

    /// `rot` is a row-major 3x3 rotation applied to the grab offsets (nil keeps the previous one).
    func moveGrab(target: SIMD3<Float>, rot: [Float]?) {
        grabTarget = target
        // bounded reach: a strong stretch, never an unbounded one
        let dv = target - grabStart
        let d = (dv.x * dv.x + dv.y * dv.y + dv.z * dv.z).squareRoot(), maxReach: Float = 2.2
        if d > maxReach { grabTarget = grabStart + dv * (maxReach / d) }
        if let rot, rot.count >= 9 { grabRot = rot }
        // never drive the held patch into the floor: lift the whole patch instead of crushing it
        let R = grabRot
        var lowest = Float.infinity
        for k in 0..<grabN {
            lowest = min(lowest, R[3] * grabOff[3 * k] + R[4] * grabOff[3 * k + 1] + R[5] * grabOff[3 * k + 2])
        }
        if lowest.isFinite { grabTarget.y = max(grabTarget.y, floorY + 0.004 - lowest) }
    }

    func endGrab() { grabbing = false; grabN = 0 }

    // MARK: simulation

    func step() {
        let sub = substeps
        let dt = stepDt / Float(sub)
        let totalM = totalMass
        let isGrabbing = grabbing
        var bad = false
        // attractor state for this step (off while held); interpolated across the substeps
        var a1 = attractor
        if isGrabbing { a1.strength = 0 }
        var a0 = attPrev
        if a0.strength <= 0 { a0.anchor = a1.anchor; a0.rotation = a1.rotation; a0.squash = a1.squash }
        if a1.strength <= 0 { attFresh = true }
        x.withUnsafeMutableBufferPointer { xb in
            v.withUnsafeMutableBufferPointer { vb in
                let px = xb.baseAddress!, pv = vb.baseAddress!
                for k in 0..<sub {
                    var a = a1
                    if a1.strength > 0 {
                        let t = Float(k + 1) / Float(sub)
                        a.strength = a0.strength + (a1.strength - a0.strength) * t
                        a.anchor = a0.anchor + (a1.anchor - a0.anchor) * t
                        a.squash = a0.squash + (a1.squash - a0.squash) * t
                        a.rotation = simd_slerp(a0.rotation, a1.rotation, t)
                    }
                    substep(dt, px, pv, a)
                }
                time += stepDt
                // settling: once the jelly is nearly still, bleed off the last residual jitter
                if !isGrabbing {
                    let ke = kineticEnergy(pv) / totalM        // ~ 1/2 v^2
                    if ke < 2e-2 {
                        // smooth ramp: barely there at 2e-2, up to 14% per step near stillness
                        let u = 1 - ke / 2e-2
                        let f = 1 - 0.14 * u * u
                        for i in 0..<(3 * n) { pv[i] *= f }
                    }
                    // rest snap: nearly still for ~0.25 s -> zero velocities (no residual buzz)
                    if ke < 2e-5 { restSteps += 1 } else { restSteps = 0 }
                    if restSteps > 15 { for i in 0..<(3 * n) { pv[i] = 0 } }
                } else { restSteps = 0 }
                // safety: any non-finite value -> reset gently
                var i = 0
                while i < 3 * n { if !px[i].isFinite { bad = true; break }; i += 97 }
            }
        }
        attPrev = a1
        if bad { reset(drop: 0.2) }
    }

    private func substep(_ dt: Float, _ x: UnsafeMutablePointer<Float>, _ v: UnsafeMutablePointer<Float>, _ att: Attractor) {
        let g = gravity * dt
        // light air drag; while held, the hand steadies the slice a little more
        let air = expf(-(grabbing ? 2.5 : airDrag()) * dt)
        let prev = self.prev
        for i in 0..<n {
            let k = 3 * i
            v[k + 1] += g
            v[k] *= air; v[k + 1] *= air; v[k + 2] *= air
            prev[k] = x[k]; prev[k + 1] = x[k + 1]; prev[k + 2] = x[k + 2]
            x[k] += v[k] * dt; x[k + 1] += v[k + 1] * dt; x[k + 2] += v[k + 2] * dt
        }
        if grabbing { solveGrab(dt, x) }
        solveTets(dt, x)
        solveVolumes(dt, x)
        let attOn = att.strength > 0
        if attOn { solveAttractor(dt, x, att) }
        if !targets.isEmpty { solveTargets(dt, x) }
        solveFloor(x)
        if arenaRadius.isFinite { solveArena(x) }
        let inv = 1 / dt, vmax = maxSpeed
        var i = 0
        while i < 3 * n {
            var vx = (x[i] - prev[i]) * inv, vy = (x[i + 1] - prev[i + 1]) * inv, vz = (x[i + 2] - prev[i + 2]) * inv
            let sp = (vx * vx + vy * vy + vz * vz).squareRoot()
            if sp > vmax { let f = vmax / sp; vx *= f; vy *= f; vz *= f }
            v[i] = vx; v[i + 1] = vy; v[i + 2] = vz
            i += 3
        }
        if attOn {
            // spring damping toward the target's own velocity (critically damped at damping = 1)
            let kd = 1 - expf(-2 * att.damping * att.strength.squareRoot() * dt)
            for i in 0..<(3 * n) { v[i] += (attV[i] - v[i]) * kd }
        }
        dampEdges(dt, x, v)
    }

    // MARK: rigid-pose attractor

    /// Pull toward the scripted rigid pose. Uniform fraction per particle (mass independent), XPBD-like: f = k dt^2 / (1 + k dt^2).
    private func solveAttractor(_ dt: Float, _ x: UnsafeMutablePointer<Float>, _ a: Attractor) {
        fitPose(x, iterations: 2)          // keeps the warm-started best-fit rotation tracking the body
        let kdt = a.strength * dt * dt, f = kdt / (1 + kdt)
        let R = simd_float3x3(a.rotation)
        let sy = a.squash, sxz = 1 / sy.squareRoot()
        let fresh = attFresh
        attFresh = false
        let inv = 1 / dt
        for i in 0..<n {
            let k = 3 * i
            let o = SIMD3<Float>(restOff[k] * sxz, restOff[k + 1] * sy, restOff[k + 2] * sxz)
            let T = a.anchor + R * o
            if fresh {
                // first substep after switching on: no target velocity yet, so aim for the body's own (no drag toward zero)
                attT[k] = T.x; attT[k + 1] = T.y; attT[k + 2] = T.z
                attV[k] = (x[k] - prev[k]) * inv; attV[k + 1] = (x[k + 1] - prev[k + 1]) * inv; attV[k + 2] = (x[k + 2] - prev[k + 2]) * inv
            } else {
                attV[k] = (T.x - attT[k]) * inv; attV[k + 1] = (T.y - attT[k + 1]) * inv; attV[k + 2] = (T.z - attT[k + 2]) * inv
                attT[k] = T.x; attT[k + 1] = T.y; attT[k + 2] = T.z
            }
            x[k] += (T.x - x[k]) * f; x[k + 1] += (T.y - x[k + 1]) * f; x[k + 2] += (T.z - x[k + 2]) * f
        }
    }

    private func solveTargets(_ dt: Float, _ x: UnsafeMutablePointer<Float>) {
        for tg in targets {
            let kdt = tg.stiffness * dt * dt, f = kdt / (1 + kdt), k = 3 * tg.index
            x[k] += (tg.pos.x - x[k]) * f; x[k + 1] += (tg.pos.y - x[k + 1]) * f; x[k + 2] += (tg.pos.z - x[k + 2]) * f
        }
    }

    /// Mass-weighted best-fit rigid pose of `x` against the rest shape (warm-started quaternion, same iteration as solveTets).
    @discardableResult
    private func fitPose(_ x: UnsafePointer<Float>, iterations: Int) -> BodyPose {
        var c = SIMD3<Float>(0, 0, 0)
        var f00: Float = 0, f01: Float = 0, f02: Float = 0, f10: Float = 0, f11: Float = 0, f12: Float = 0, f20: Float = 0, f21: Float = 0, f22: Float = 0
        for i in 0..<n {
            let k = 3 * i, m = mass[i]
            let px = x[k] * m, py = x[k + 1] * m, pz = x[k + 2] * m
            c.x += px; c.y += py; c.z += pz
            // sum m p q^T; the centroid term vanishes because the mass-weighted rest offsets sum to zero
            let q0 = restOff[k], q1 = restOff[k + 1], q2 = restOff[k + 2]
            f00 += px * q0; f01 += px * q1; f02 += px * q2
            f10 += py * q0; f11 += py * q1; f12 += py * q2
            f20 += pz * q0; f21 += pz * q1; f22 += pz * q2
        }
        c /= totalMass
        var qx = fitQ.x, qy = fitQ.y, qz = fitQ.z, qw = fitQ.w
        for _ in 0..<iterations {
            let r00 = 1 - 2 * (qy * qy + qz * qz), r01 = 2 * (qx * qy - qw * qz), r02 = 2 * (qx * qz + qw * qy)
            let r10 = 2 * (qx * qy + qw * qz), r11 = 1 - 2 * (qx * qx + qz * qz), r12 = 2 * (qy * qz - qw * qx)
            let r20 = 2 * (qx * qz - qw * qy), r21 = 2 * (qy * qz + qw * qx), r22 = 1 - 2 * (qx * qx + qy * qy)
            let ox = (r10 * f20 - r20 * f10) + (r11 * f21 - r21 * f11) + (r12 * f22 - r22 * f12)
            let oy = (r20 * f00 - r00 * f20) + (r21 * f01 - r01 * f21) + (r22 * f02 - r02 * f22)
            let oz = (r00 * f10 - r10 * f00) + (r01 * f11 - r11 * f01) + (r02 * f12 - r12 * f02)
            let den = abs(r00 * f00 + r10 * f10 + r20 * f20 + r01 * f01 + r11 * f11 + r21 * f21 + r02 * f02 + r12 * f12 + r22 * f22) + 1e-12
            let wx = ox / den, wy = oy / den, wz = oz / den
            let w = (wx * wx + wy * wy + wz * wz).squareRoot()
            if w < 1e-6 { break }
            let sc: Float = w > 1 ? 0.5 / w : 0.5
            let ax = wx * sc, ay = wy * sc, az = wz * sc
            let nx = qx + ax * qw + ay * qz - az * qy
            let ny = qy - ax * qz + ay * qw + az * qx
            let nz = qz + ax * qy - ay * qx + az * qw
            let nw = qw - ax * qx - ay * qy - az * qz
            let nl = 1 / (nx * nx + ny * ny + nz * nz + nw * nw).squareRoot()
            qx = nx * nl; qy = ny * nl; qz = nz * nl; qw = nw * nl
        }
        fitQ = SIMD4(qx, qy, qz, qw)
        return BodyPose(centroid: c, rotation: simd_quatf(ix: qx, iy: qy, iz: qz, r: qw))
    }

    /// Current whole-body rigid pose (centroid + best-fit rotation). Cheap enough to call every frame.
    func bodyPose(iterations: Int = 8) -> BodyPose {
        x.withUnsafeBufferPointer { fitPose($0.baseAddress!, iterations: iterations) }
    }

    /// Anchor height that puts the lowest point of the target pose (rotation q, squash s) exactly on the floor.
    func groundedAnchorY(rotation q: simd_quatf, squash sy: Float = 1) -> Float {
        let R = simd_float3x3(q), sxz = 1 / sy.squareRoot()
        var lo = Float.infinity
        for i in 0..<n {
            let o = SIMD3<Float>(restOff[3 * i] * sxz, restOff[3 * i + 1] * sy, restOff[3 * i + 2] * sxz)
            lo = min(lo, (R * o).y)
        }
        return floorY - lo
    }

    /// Mean velocity of the body (mass weighted).
    func meanVelocity() -> SIMD3<Float> {
        var s = SIMD3<Float>(0, 0, 0)
        for i in 0..<n { s += SIMD3(v[3 * i], v[3 * i + 1], v[3 * i + 2]) * mass[i] }
        return s / totalMass
    }

    /// Throw: replace the body's mean velocity with `velocity` and add a rigid spin `omega` (rad/s) about the centroid.
    func launch(velocity: SIMD3<Float>, spin omega: SIMD3<Float> = .zero) {
        let c = centroid(), dv = velocity - meanVelocity()
        for i in 0..<n {
            let r = SIMD3(x[3 * i] - c.x, x[3 * i + 1] - c.y, x[3 * i + 2] - c.z)
            let w = simd_cross(omega, r)
            v[3 * i] += dv.x + w.x; v[3 * i + 1] += dv.y + w.y; v[3 * i + 2] += dv.z + w.z
        }
        restSteps = 0
    }

    private func solveArena(_ x: UnsafeMutablePointer<Float>) {
        let r2 = arenaRadius * arenaRadius, cx = arenaCenter.x, cz = arenaCenter.y
        for i in 0..<n {
            let k = 3 * i
            let dx = x[k] - cx, dz = x[k + 2] - cz, d2 = dx * dx + dz * dz
            if d2 > r2 { let s = arenaRadius / d2.squareRoot(); x[k] = cx + dx * s; x[k + 2] = cz + dz * s }
        }
    }

    private func solveGrab(_ dt: Float, _ x: UnsafeMutablePointer<Float>) {
        let a = 2e-6 / (dt * dt)
        let R = grabRot, T = grabTarget
        for k in 0..<grabN {
            let i = Int(grabIdx[k]), w = invMass[i]
            let ox = grabOff[3 * k], oy = grabOff[3 * k + 1], oz = grabOff[3 * k + 2]
            let tx = T.x + R[0] * ox + R[1] * oy + R[2] * oz
            let ty = max(T.y + R[3] * ox + R[4] * oy + R[5] * oz, floorY + 0.005)
            let tz = T.z + R[6] * ox + R[7] * oy + R[8] * oz
            var f = grabW[k] * w / (w + a)
            // pressing down near the table: yield instead of crushing the jelly underneath
            if ty < x[3 * i + 1] && ty < 0.45 { f *= max(0.12, ty / 0.45) }
            x[3 * i] += (tx - x[3 * i]) * f
            x[3 * i + 1] += (ty - x[3 * i + 1]) * f
            x[3 * i + 2] += (tz - x[3 * i + 2]) * f
        }
    }

    /// Per-tet co-rotational shape matching: find the rotation that best maps the rest tet onto the current
    /// one (Mueller et al. 2016, warm-started quaternion), then pull the four corners toward the rotated rest
    /// shape with XPBD compliance. Inverted tets are always pushed back to a proper shape.
    private func solveTets(_ dt: Float, _ x: UnsafeMutablePointer<Float>) {
        let base = shapeCompliance() / (dt * dt)
        let Q = tetRot, tq = tetQ
        for t in 0..<nT {
            let ia = 3 * Int(tetIdx[4 * t]), ib = 3 * Int(tetIdx[4 * t + 1]), ic = 3 * Int(tetIdx[4 * t + 2]), id = 3 * Int(tetIdx[4 * t + 3])
            let idx = (ia, ib, ic, id)
            let ma = mass[ia / 3], mb = mass[ib / 3], mc = mass[ic / 3], md = mass[id / 3]
            let M = ma + mb + mc + md
            let cx = (x[ia] * ma + x[ib] * mb + x[ic] * mc + x[id] * md) / M
            let cy = (x[ia + 1] * ma + x[ib + 1] * mb + x[ic + 1] * mc + x[id + 1] * md) / M
            let cz = (x[ia + 2] * ma + x[ib + 2] * mb + x[ic + 2] * mc + x[id + 2] * md) / M
            let T = 12 * t
            // A = sum m p q^T (mass-weighted covariance of current vs rest, both about their centroids)
            var f00: Float = 0, f01: Float = 0, f02: Float = 0, f10: Float = 0, f11: Float = 0, f12: Float = 0, f20: Float = 0, f21: Float = 0, f22: Float = 0
            @inline(__always) func acc(_ i: Int, _ m: Float, _ o: Int) {
                let px = (x[i] - cx) * m, py = (x[i + 1] - cy) * m, pz = (x[i + 2] - cz) * m
                let q0 = tq[T + o], q1 = tq[T + o + 1], q2 = tq[T + o + 2]
                f00 += px * q0; f01 += px * q1; f02 += px * q2
                f10 += py * q0; f11 += py * q1; f12 += py * q2
                f20 += pz * q0; f21 += pz * q1; f22 += pz * q2
            }
            acc(idx.0, ma, 0); acc(idx.1, mb, 3); acc(idx.2, mc, 6); acc(idx.3, md, 9)
            var qx = Q[4 * t], qy = Q[4 * t + 1], qz = Q[4 * t + 2], qw = Q[4 * t + 3]
            var r00: Float = 1, r01: Float = 0, r02: Float = 0, r10: Float = 0, r11: Float = 1, r12: Float = 0, r20: Float = 0, r21: Float = 0, r22: Float = 1
            for _ in 0..<2 {
                r00 = 1 - 2 * (qy * qy + qz * qz); r01 = 2 * (qx * qy - qw * qz); r02 = 2 * (qx * qz + qw * qy)
                r10 = 2 * (qx * qy + qw * qz); r11 = 1 - 2 * (qx * qx + qz * qz); r12 = 2 * (qy * qz - qw * qx)
                r20 = 2 * (qx * qz - qw * qy); r21 = 2 * (qy * qz + qw * qx); r22 = 1 - 2 * (qx * qx + qy * qy)
                let ox = (r10 * f20 - r20 * f10) + (r11 * f21 - r21 * f11) + (r12 * f22 - r22 * f12)
                let oy = (r20 * f00 - r00 * f20) + (r21 * f01 - r01 * f21) + (r22 * f02 - r02 * f22)
                let oz = (r00 * f10 - r10 * f00) + (r01 * f11 - r11 * f01) + (r02 * f12 - r12 * f02)
                let den = abs(r00 * f00 + r10 * f10 + r20 * f20 + r01 * f01 + r11 * f11 + r21 * f21 + r02 * f02 + r12 * f12 + r22 * f22) + 1e-12
                let wx = ox / den, wy = oy / den, wz = oz / den
                let w = (wx * wx + wy * wy + wz * wz).squareRoot()
                if w < 1e-6 { break }
                // small-angle quaternion step (renormalised below); large jumps are clamped
                let sc: Float = w > 1 ? 0.5 / w : 0.5
                let ax = wx * sc, ay = wy * sc, az = wz * sc
                let nx = qx + ax * qw + ay * qz - az * qy
                let ny = qy - ax * qz + ay * qw + az * qx
                let nz = qz + ax * qy - ay * qx + az * qw
                let nw = qw - ax * qx - ay * qy - az * qz
                let nl = 1 / (nx * nx + ny * ny + nz * nz + nw * nw).squareRoot()
                qx = nx * nl; qy = ny * nl; qz = nz * nl; qw = nw * nl
            }
            r00 = 1 - 2 * (qy * qy + qz * qz); r01 = 2 * (qx * qy - qw * qz); r02 = 2 * (qx * qz + qw * qy)
            r10 = 2 * (qx * qy + qw * qz); r11 = 1 - 2 * (qx * qx + qz * qz); r12 = 2 * (qy * qz - qw * qx)
            r20 = 2 * (qx * qz - qw * qy); r21 = 2 * (qy * qz + qw * qx); r22 = 1 - 2 * (qx * qx + qy * qy)
            Q[4 * t] = qx; Q[4 * t + 1] = qy; Q[4 * t + 2] = qz; Q[4 * t + 3] = qw
            // the same fraction for all four corners keeps linear and angular momentum intact
            let f = 1 / (1 + base * tetFirm[t] * M * 0.25)
            @inline(__always) func pull(_ i: Int, _ o: Int) {
                let q0 = tq[T + o], q1 = tq[T + o + 1], q2 = tq[T + o + 2]
                x[i] += (cx + r00 * q0 + r01 * q1 + r02 * q2 - x[i]) * f
                x[i + 1] += (cy + r10 * q0 + r11 * q1 + r12 * q2 - x[i + 1]) * f
                x[i + 2] += (cz + r20 * q0 + r21 * q1 + r22 * q2 - x[i + 2]) * f
            }
            pull(idx.0, 0); pull(idx.1, 3); pull(idx.2, 6); pull(idx.3, 9)
        }
    }

    private func solveVolumes(_ dt: Float, _ x: UnsafeMutablePointer<Float>) {
        let alpha0 = volCompliance() / (dt * dt)
        for t in 0..<nT {
            let a = Int(tetIdx[4 * t]), b = Int(tetIdx[4 * t + 1]), c = Int(tetIdx[4 * t + 2]), d = Int(tetIdx[4 * t + 3])
            let A = 3 * a, B = 3 * b, Cc = 3 * c, D = 3 * d
            // gradients (Mueller): g_a = (d-b)x(c-b), g_b = (c-a)x(d-a), g_c = (d-a)x(b-a), g_d = (b-a)x(c-a)
            let bax = x[B] - x[A], bay = x[B + 1] - x[A + 1], baz = x[B + 2] - x[A + 2]
            let cax = x[Cc] - x[A], cay = x[Cc + 1] - x[A + 1], caz = x[Cc + 2] - x[A + 2]
            let dax = x[D] - x[A], day = x[D + 1] - x[A + 1], daz = x[D + 2] - x[A + 2]
            let dbx = x[D] - x[B], dby = x[D + 1] - x[B + 1], dbz = x[D + 2] - x[B + 2]
            let cbx = x[Cc] - x[B], cby = x[Cc + 1] - x[B + 1], cbz = x[Cc + 2] - x[B + 2]
            let gax = dby * cbz - dbz * cby, gay = dbz * cbx - dbx * cbz, gaz = dbx * cby - dby * cbx
            let gbx = cay * daz - caz * day, gby = caz * dax - cax * daz, gbz = cax * day - cay * dax
            let gcx = day * baz - daz * bay, gcy = daz * bax - dax * baz, gcz = dax * bay - day * bax
            let gdx = bay * caz - baz * cay, gdy = baz * cax - bax * caz, gdz = bax * cay - bay * cax
            let V = (dax * gdx + day * gdy + daz * gdz) / 6
            let wa = invMass[a], wb = invMass[b], wc = invMass[c], wd = invMass[d]
            let wsum = wa * (gax * gax + gay * gay + gaz * gaz) + wb * (gbx * gbx + gby * gby + gbz * gbz)
                     + wc * (gcx * gcx + gcy * gcy + gcz * gcz) + wd * (gdx * gdx + gdy * gdy + gdz * gdz)
            if wsum < 1e-12 { continue }
            let r0 = restVol[t]
            // anti-inversion: elements far below rest volume get a rigid (compliance-free) correction
            let alpha: Float = V < 0.25 * r0 ? 0 : alpha0 * tetVolScale[t]
            let C = 6 * (V - r0)
            let s = -C / (wsum + alpha)
            x[A] += gax * s * wa; x[A + 1] += gay * s * wa; x[A + 2] += gaz * s * wa
            x[B] += gbx * s * wb; x[B + 1] += gby * s * wb; x[B + 2] += gbz * s * wb
            x[Cc] += gcx * s * wc; x[Cc + 1] += gcy * s * wc; x[Cc + 2] += gcz * s * wc
            x[D] += gdx * s * wd; x[D + 1] += gdy * s * wd; x[D + 2] += gdz * s * wd
        }
    }

    private func solveFloor(_ x: UnsafeMutablePointer<Float>) {
        let fy = floorY, mu = friction
        for i in 0..<n {
            let k = 3 * i
            let pen = fy - x[k + 1]
            if pen <= 0 { continue }
            x[k + 1] = fy
            // Coulomb-style positional friction
            let dx = x[k] - prev[k], dz = x[k + 2] - prev[k + 2]
            let dl = (dx * dx + dz * dz).squareRoot()
            if dl < 1e-12 { continue }
            // static friction for micro-slip, kinetic friction otherwise (never locks in large strain)
            let f: Float = dl < mu * pen ? 1 : mu * pen / dl
            x[k] -= dx * f; x[k + 2] -= dz * f
        }
    }

    private func dampEdges(_ dt: Float, _ x: UnsafeMutablePointer<Float>, _ v: UnsafeMutablePointer<Float>) {
        let k = 1 - expf(-dampRate() * dt)
        for e in 0..<nE {
            let i = Int(edgeIdx[2 * e]), j = Int(edgeIdx[2 * e + 1])
            let I = 3 * i, J = 3 * j
            var nx = x[J] - x[I], ny = x[J + 1] - x[I + 1], nz = x[J + 2] - x[I + 2]
            let l = (nx * nx + ny * ny + nz * nz).squareRoot()
            if l < 1e-9 { continue }
            nx /= l; ny /= l; nz /= l
            let rv = (v[J] - v[I]) * nx + (v[J + 1] - v[I + 1]) * ny + (v[J + 2] - v[I + 2]) * nz
            let wi = invMass[i], wj = invMass[j], ws = wi + wj
            let imp = rv * k / ws
            v[I] += nx * imp * wi; v[I + 1] += ny * imp * wi; v[I + 2] += nz * imp * wi
            v[J] -= nx * imp * wj; v[J + 1] -= ny * imp * wj; v[J + 2] -= nz * imp * wj
        }
    }

    // MARK: diagnostics

    private func tetVol(_ p: UnsafePointer<Float>, _ t: Int) -> Float {
        let a = 3 * Int(tetIdx[4 * t]), b = 3 * Int(tetIdx[4 * t + 1]), c = 3 * Int(tetIdx[4 * t + 2]), d = 3 * Int(tetIdx[4 * t + 3])
        let ax = p[a], ay = p[a + 1], az = p[a + 2]
        let b0 = p[b] - ax, b1 = p[b + 1] - ay, b2 = p[b + 2] - az
        let c0 = p[c] - ax, c1 = p[c + 1] - ay, c2 = p[c + 2] - az
        let d0 = p[d] - ax, d1 = p[d + 1] - ay, d2 = p[d + 2] - az
        return (b0 * (c1 * d2 - c2 * d1) - b1 * (c0 * d2 - c2 * d0) + b2 * (c0 * d1 - c1 * d0)) / 6
    }

    func volumeRatio() -> Float {
        var s: Float = 0
        x.withUnsafeBufferPointer { p in for t in 0..<nT { s += tetVol(p.baseAddress!, t) } }
        return s / totalRestVolume
    }

    func minVolumeRatio() -> Float {
        var m = Float.infinity
        x.withUnsafeBufferPointer { p in for t in 0..<nT { m = min(m, tetVol(p.baseAddress!, t) / restVol[t]) } }
        return m
    }

    private func kineticEnergy(_ pv: UnsafePointer<Float>) -> Float {
        var e: Float = 0
        for i in 0..<n {
            let k = 3 * i
            e += 0.5 * mass[i] * (pv[k] * pv[k] + pv[k + 1] * pv[k + 1] + pv[k + 2] * pv[k + 2])
        }
        return e
    }

    func kineticEnergy() -> Float { v.withUnsafeBufferPointer { kineticEnergy($0.baseAddress!) } }

    /// Mean absolute edge strain (diagnostic).
    func meanStrain() -> Float {
        var s: Float = 0
        x.withUnsafeBufferPointer { p in
            for e in 0..<nE {
                let i = 3 * Int(edgeIdx[2 * e]), j = 3 * Int(edgeIdx[2 * e + 1])
                let dx = p[i] - p[j], dy = p[i + 1] - p[j + 1], dz = p[i + 2] - p[j + 2]
                s += abs((dx * dx + dy * dy + dz * dz).squareRoot() / restLen[e] - 1)
            }
        }
        return s / Float(nE)
    }

    func minY() -> Float {
        var m = Float.infinity
        for i in stride(from: 1, to: x.count, by: 3) { m = min(m, x[i]) }
        return m
    }

    func hasNonFinite() -> Bool {
        for f in x where !f.isFinite { return true }
        for f in v where !f.isFinite { return true }
        return false
    }
}
