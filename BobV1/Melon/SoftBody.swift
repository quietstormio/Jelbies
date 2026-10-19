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

nonisolated final class SoftBody {
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
    /// Bumped by every outside edit of the body (reset, shift, nudge, launch, grab, press): a sleeping Jelly (JellyActor.updateSleep) wakes when it changes.
    private(set) var epoch = 0

    /// The body is at a fixed point: not held or pressed, perfectly still for the rest-snap time, and whatever pulls on it (pose attractor, foot / hand
    /// targets) is exactly what pulled on it in its last step. Stepping it again would change nothing, so a sleeping Jelly may skip the step.
    var isSettled: Bool {
        guard !grabbing, !pressing, restSteps > 15, kineticEnergy() < 1e-9 else { return false }
        let a = attractor, p = attPrev
        guard a.strength == p.strength else { return false }
        if a.strength > 0 {
            guard simd_length_squared(a.anchor - p.anchor) < 1e-10, abs(a.squash - p.squash) < 1e-5, a.damping == p.damping,
                  simd_length_squared(a.rotation.vector - p.rotation.vector) < 1e-10 else { return false }
        }
        guard targets.count == targetsPrev.count else { return false }
        for i in 0..<targets.count {
            let t = targets[i], q = targetsPrev[i]
            if t.index != q.index || t.stiffness != q.stiffness || simd_length_squared(t.pos - q.pos) > 1e-10 { return false }
        }
        return true
    }
    private var targetsPrev: [ParticleTarget] = []

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

    // Level schedule (see `levelSchedule`): the tets in an order that gives BIT-IDENTICAL results to the plain 0..<nT Gauss-Seidel sweep,
    // bucketed into groups of 4 mutually independent tets that are solved together in the lanes of a SIMD4<Float> (solveTets takes two groups of
    // one level at a time as a SIMD8). Group data is stored
    // lane-transposed: `gIdx[16 g + 4 k + l]` = 3 x particle index of corner k of lane l; `gQ[12 g + 3 k + c]` = rest offset component c of corner k
    // across the lanes; `gMass[4 g + k]`, `gInvMass[4 g + k]` per corner; `gM`, `gRestVol` per tet; `gTet[4 g + l]` = the tet of each lane (for the
    // per-tet gathers of tetFirm / tetVolScale); `gRot[4 g + c]` = the warm-started quaternion (x, y, z, w) across the lanes. A group whose level
    // has fewer than 4 tets left repeats its last tet in the spare lanes (identical maths, identical writes: harmless).
    let tetGroups: Int
    let tetLevels: Int
    private let gLevelStart: UnsafeMutablePointer<Int32>     // first group of each level (tetLevels + 1 entries)
    private let gIdx: UnsafeMutablePointer<Int32>
    private let gTet: UnsafeMutablePointer<Int32>
    private let gMass: UnsafeMutablePointer<SIMD4<Float>>
    private let gInvMass: UnsafeMutablePointer<SIMD4<Float>>
    private let gM: UnsafeMutablePointer<SIMD4<Float>>
    private let gRestVol: UnsafeMutablePointer<SIMD4<Float>>
    private let gQ: UnsafeMutablePointer<SIMD4<Float>>
    private let gRot: UnsafeMutablePointer<SIMD4<Float>>
    /// Scratch the SIMD kernels gather / scatter through (see `scatter`, `gatherOpaque`): 12 gather slots + 1 scatter slot of 16 bytes.
    private let laneTmp: UnsafeMutableRawPointer
    /// Perf A/B (SolverBenchTests): run the plain scalar sweeps instead of the level-scheduled SIMD kernels. Same results either way.
    nonisolated(unsafe) static var referenceSolver = false

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

        // level schedules (bit-exact reorderings of the Gauss-Seidel sweeps, 4 independent elements per SIMD group)
        let ts = Self.levelSchedule(count: nT, arity: 4, particles: n) { Int(tets[$0]) }
        tetLevels = ts.levels; tetGroups = ts.groups.count / 4
        gLevelStart = alloc(tetLevels + 1, 0)
        for (i, g) in ts.levelStart.enumerated() { gLevelStart[i] = Int32(g) }
        gIdx = alloc(tetGroups * 16, 0); gTet = alloc(tetGroups * 4, 0)
        gMass = alloc(tetGroups * 4, SIMD4<Float>(repeating: 0)); gInvMass = alloc(tetGroups * 4, SIMD4<Float>(repeating: 0))
        gM = alloc(tetGroups, SIMD4<Float>(repeating: 0)); gRestVol = alloc(tetGroups, SIMD4<Float>(repeating: 0))
        gQ = alloc(tetGroups * 12, SIMD4<Float>(repeating: 0)); gRot = alloc(tetGroups * 4, SIMD4<Float>(repeating: 0))
        for g in 0..<tetGroups {
            for l in 0..<4 {
                let t = ts.groups[4 * g + l]
                gTet[4 * g + l] = Int32(t)
                let pa = Int(tets[4 * t]), pb = Int(tets[4 * t + 1]), pc = Int(tets[4 * t + 2]), pd = Int(tets[4 * t + 3])
                let ma = mass[pa], mb = mass[pb], mc = mass[pc], md = mass[pd]
                gM[g][l] = ma + mb + mc + md                       // the same left-to-right sum as the scalar sweep
                gRestVol[g][l] = restVol[t]
                for k in 0..<4 {
                    let pk = Int(tets[4 * t + k])
                    gIdx[16 * g + 4 * k + l] = Int32(3 * pk)
                    gMass[4 * g + k][l] = mass[pk]; gInvMass[4 * g + k][l] = invMass[pk]
                    for c in 0..<3 { gQ[12 * g + 3 * k + c][l] = tetQ[12 * t + 3 * k + c] }
                }
            }
        }
        laneTmp = UnsafeMutableRawPointer.allocate(byteCount: 208, alignment: 16)
        targets = []
        reset(drop: 0)
    }

    /// Dependency-level schedule of a Gauss-Seidel sweep over `count` elements of `arity` particles each (`particle(arity * e + k)`). Two elements
    /// that share a particle keep their original relative order (level(e) = 1 + the level of the latest earlier element on any of its particles);
    /// elements of one level share no particle, so solving them together, in any order, gives exactly the sweep's result. Returns the elements
    /// level by level (ascending index within a level) in groups of 4, the last element of a level repeated to fill its final group.
    static func levelSchedule(count: Int, arity: Int, particles: Int, particle: (Int) -> Int) -> (levels: Int, groups: [Int], levelStart: [Int]) {
        var last = [Int](repeating: -1, count: particles)
        var level = [Int](repeating: 0, count: count)
        var maxLevel = -1
        for e in 0..<count {
            var L = 0
            for k in 0..<arity { L = max(L, last[particle(arity * e + k)] + 1) }
            level[e] = L
            for k in 0..<arity { last[particle(arity * e + k)] = L }
            maxLevel = max(maxLevel, L)
        }
        let levels = maxLevel + 1
        var buckets = [[Int]](repeating: [], count: levels)
        for e in 0..<count { buckets[level[e]].append(e) }
        var groups: [Int] = [], levelStart: [Int] = []
        groups.reserveCapacity(count + 3 * levels)
        for b in buckets {
            levelStart.append(groups.count / 4)
            var i = 0
            while i < b.count {
                for l in 0..<4 { groups.append(b[min(i + l, b.count - 1)]) }
                i += 4
            }
        }
        levelStart.append(groups.count / 4)
        return (levels, groups, levelStart)
    }

    deinit {
        rest.deallocate(); prev.deallocate(); invMass.deallocate(); mass.deallocate(); restVol.deallocate()
        restLen.deallocate(); tetIdx.deallocate(); edgeIdx.deallocate(); tetQ.deallocate(); tetRot.deallocate()
        tetFirm.deallocate(); tetVolScale.deallocate(); grabIdx.deallocate(); grabW.deallocate(); grabOff.deallocate()
        restOff.deallocate(); attT.deallocate(); attV.deallocate()
        gIdx.deallocate(); gTet.deallocate(); gMass.deallocate(); gInvMass.deallocate(); gM.deallocate(); gRestVol.deallocate(); gQ.deallocate(); gRot.deallocate()
        laneTmp.deallocate(); gLevelStart.deallocate()
    }

    func reset(drop: Float = 0.35) {
        epoch &+= 1
        for i in 0..<n {
            x[3 * i] = rest[3 * i]
            x[3 * i + 1] = rest[3 * i + 1] + drop
            x[3 * i + 2] = rest[3 * i + 2]
        }
        for i in 0..<(3 * n) { prev[i] = x[i]; v[i] = 0 }
        for t in 0..<nT { tetRot[4 * t] = 0; tetRot[4 * t + 1] = 0; tetRot[4 * t + 2] = 0; tetRot[4 * t + 3] = 1 }
        for g in 0..<tetGroups { gRot[4 * g] = .zero; gRot[4 * g + 1] = .zero; gRot[4 * g + 2] = .zero; gRot[4 * g + 3] = SIMD4(repeating: 1) }
        fitQ = SIMD4<Float>(0, 0, 0, 1)
        attractor = Attractor(); attPrev = Attractor(); attFresh = true
        endGrab(); endPress()
    }

    /// Slides the whole body (and its previous positions, so there is no velocity) by (dx, dz) on the floor.
    func shift(byXZ d: SIMD2<Float>) {
        epoch &+= 1
        for i in 0..<n {
            x[3 * i] += d.x; x[3 * i + 2] += d.y
            prev[3 * i] += d.x; prev[3 * i + 2] += d.y
        }
    }

    /// Clean-up flow: puts the whole body, at rest on the floor, over floor spot `p` (centroid x, z). No velocity, no foot / arm targets, so the
    /// first step after the move has nothing to catch up on.
    func teleport(toXZ p: SIMD2<Float>) {
        reset(drop: 0)
        targets = []
        restoreStiffness()
        let c = centroid()
        let dx = p.x - c.x, dz = p.y - c.z
        for i in 0..<n {
            x[3 * i] += dx; x[3 * i + 2] += dz
            prev[3 * i] += dx; prev[3 * i + 2] += dz
        }
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
        epoch &+= 1
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
        epoch &+= 1
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

    // MARK: press contact (fingertip spheres that dent him and slide; unlike the grab they never hold on, so they never pull)

    /// True while a fingertip sphere is set. With none set the step is exactly the plain step.
    private(set) var pressing = false
    private var pressC = [SIMD3<Float>](repeating: .zero, count: 2)
    private var pressR = [Float](repeating: 0, count: 2)
    private var pressOn = [false, false]
    private var pressList: [Int32] = []
    private var pressDeepest: Float = 0
    /// Deepest push of the spheres during the last step (sim units): how hard the fingertip works on him.
    private(set) var pressDepth: Float = 0

    /// Fingertip sphere (slot 0 = the pet finger, slots 0 and 1 = the two cheek fingers) at `center` with `radius`:
    /// every particle inside is moved out to its surface (collision only, no attachment).
    func setPress(center: SIMD3<Float>, radius: Float, slot: Int = 0) {
        pressC[slot] = center; pressR[slot] = radius; pressOn[slot] = true; pressing = true; epoch &+= 1
    }

    func endPress(slot: Int) {
        pressOn[slot] = false
        if !pressOn[0] && !pressOn[1] { endPress() }
    }

    func endPress() {
        pressing = false; pressDepth = 0; pressDeepest = 0
        pressOn[0] = false; pressOn[1] = false
        pressList.removeAll(keepingCapacity: true)
    }

    private func buildPressList() {
        pressList.removeAll(keepingCapacity: true)
        for i in 0..<n {
            var near = false
            for s in 0..<2 where pressOn[s] {
                let r = pressR[s] + 0.12
                let dx = x[3 * i] - pressC[s].x, dy = x[3 * i + 1] - pressC[s].y, dz = x[3 * i + 2] - pressC[s].z
                if dx * dx + dy * dy + dz * dz < r * r { near = true }
            }
            if near { pressList.append(Int32(i)) }
        }
    }

    private func solvePress(_ x: UnsafeMutablePointer<Float>) {
        var deepest: Float = 0
        var sx: Float = 0, sy: Float = 0, sz: Float = 0
        for s in 0..<2 where pressOn[s] {
            let c = pressC[s], R = pressR[s], R2 = R * R
            for k in pressList {
                let i = 3 * Int(k)
                let dx = x[i] - c.x, dy = x[i + 1] - c.y, dz = x[i + 2] - c.z
                let d2 = dx * dx + dy * dy + dz * dz
                if d2 >= R2 { continue }
                let ox = x[i], oy = x[i + 1], oz = x[i + 2]
                let d = d2.squareRoot()
                let push = min(R - d, 0.04)
                if d > 1e-6 { let f = push / d; x[i] += dx * f; x[i + 1] += dy * f; x[i + 2] += dz * f } else { x[i + 2] += push }
                deepest = max(deepest, R - d)
                let m = mass[Int(k)]
                sx += m * (x[i] - ox); sy += m * (x[i + 1] - oy); sz += m * (x[i + 2] - oz)
            }
        }
        pressDeepest = max(pressDeepest, deepest)
        // zero net pull: the contact is an internal exchange, so the whole body gives back the mass-weighted mean of what it pushed
        // (the centroid is not shoved; only the dent moves)
        let inv = 1 / totalMass
        let gx = sx * inv, gy = sy * inv, gz = sz * inv
        if abs(gx) + abs(gy) + abs(gz) > 0 {
            for j in 0..<n { x[3 * j] -= gx; x[3 * j + 1] -= gy; x[3 * j + 2] -= gz }
        }
    }

    // MARK: simulation

    func step() {
        let sub = substeps
        let dt = stepDt / Float(sub)
        let totalM = totalMass
        let isGrabbing = grabbing
        var bad = false
        // attractor state for this step (off while held); interpolated across the substeps
        if pressing { buildPressList(); pressDeepest = 0 }
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
        targetsPrev = targets
        if pressing { pressDepth = pressDeepest }
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
        if pressing { solvePress(x) }
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

    /// Anchor for a pose (rotation q, squash sy) that keeps the rest-frame point `m` (e.g. a foot's sole) exactly at world point `world`.
    /// Rolling / pitching / yawing the target about that point makes him pivot on his feet instead of his centre.
    func pivotAnchor(rotation q: simd_quatf, squash sy: Float = 1, pivot m: SIMD3<Float>, world: SIMD3<Float>) -> SIMD3<Float> {
        let R = simd_float3x3(q), sxz = 1 / sy.squareRoot()
        let o = m - restCentroid
        return world - R * SIMD3<Float>(o.x * sxz, o.y * sy, o.z * sxz)
    }

    /// Mean velocity of the body (mass weighted).
    func meanVelocity() -> SIMD3<Float> {
        var s = SIMD3<Float>(0, 0, 0)
        for i in 0..<n { s += SIMD3(v[3 * i], v[3 * i + 1], v[3 * i + 2]) * mass[i] }
        return s / totalMass
    }

    /// Throw: replace the body's mean velocity with `velocity` and add a rigid spin `omega` (rad/s) about the centroid.
    func launch(velocity: SIMD3<Float>, spin omega: SIMD3<Float> = .zero) {
        epoch &+= 1
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

    // MARK: level-scheduled SIMD kernels
    // Each kernel below is the scalar sweep that follows it, written for 4 independent elements at once (one per SIMD lane) in the level order
    // built by `levelSchedule`. Every lane performs the scalar code's operations in the scalar code's order (NEON's lane-wise fmul / fadd /
    // fdiv / fsqrt are correctly rounded like the scalar ones, and Swift never fuses a * b + c), so the results are bit-identical to the sweep.
    // Early exits (`break`, `continue`) become lane masks: the lane keeps its old value. SolverParityTests holds the proof.

    private typealias V4 = SIMD4<Float>

    @inline(__always) private func gather(_ x: UnsafePointer<Float>, _ I: UnsafePointer<Int32>, _ c: Int) -> V4 {
        V4(x[Int(I[0]) + c], x[Int(I[1]) + c], x[Int(I[2]) + c], x[Int(I[3]) + c])
    }
    /// The same through a 16-byte scratch slot (four scalar stores, one vector load), for a kernel whose first operations subtract two gathered
    /// vectors: built from lane inserts, LLVM scalarises those differences and everything downstream (seen in solveVolumes: 4x the instructions);
    /// a vector that comes from a load stays a vector.
    @inline(__always) private func gatherOpaque(_ x: UnsafePointer<Float>, _ I: UnsafePointer<Int32>, _ c: Int, _ tmp: UnsafeMutableRawPointer) -> V4 {
        tmp.storeBytes(of: x[Int(I[0]) + c], as: Float.self); tmp.storeBytes(of: x[Int(I[1]) + c], toByteOffset: 4, as: Float.self)
        tmp.storeBytes(of: x[Int(I[2]) + c], toByteOffset: 8, as: Float.self); tmp.storeBytes(of: x[Int(I[3]) + c], toByteOffset: 12, as: Float.self)
        return tmp.load(as: V4.self)
    }
    /// Lane scatter through a 16-byte scratch (one vector store, four scalar loads). Extracting the lanes directly (`v[0]`...) makes LLVM
    /// scalarise the whole vector dataflow that feeds them (InstCombine's "cheap to scalarise" rule for values built from lane inserts), which
    /// turned this kernel into scalar code with 4x the instructions; the opaque store keeps it in 4-lane registers.
    @inline(__always) private func scatter(_ x: UnsafeMutablePointer<Float>, _ I: UnsafePointer<Int32>, _ c: Int, _ v: V4, _ tmp: UnsafeMutableRawPointer) {
        tmp.storeBytes(of: v, as: V4.self)
        x[Int(I[0]) + c] = tmp.load(as: Float.self); x[Int(I[1]) + c] = tmp.load(fromByteOffset: 4, as: Float.self)
        x[Int(I[2]) + c] = tmp.load(fromByteOffset: 8, as: Float.self); x[Int(I[3]) + c] = tmp.load(fromByteOffset: 12, as: Float.self)
    }

    private func solveTets(_ dt: Float, _ x: UnsafeMutablePointer<Float>) {
        if Self.referenceSolver { solveTetsScalar(dt, x); return }
        if !Self.narrowTets { solveTetsWide(dt, x); return }
        let base: V4 = V4(repeating: shapeCompliance() / (dt * dt))
        let G = tetGroups, gi = gIdx, gt = gTet, gm = gMass, gMM = gM, gq = gQ, gr = gRot, tf = tetFirm, tmp = laneTmp
        let quarter: V4 = V4(repeating: 0.25), one: V4 = V4(repeating: 1), two: V4 = V4(repeating: 2), half: V4 = V4(repeating: 0.5)
        let eps: V4 = V4(repeating: 1e-12), small: V4 = V4(repeating: 1e-6)
        for g in 0..<G {
            let I = gi + 16 * g, q = gq + 12 * g
            let xa: V4 = gather(x, I, 0), ya: V4 = gather(x, I, 1), za: V4 = gather(x, I, 2)
            let xb: V4 = gather(x, I + 4, 0), yb: V4 = gather(x, I + 4, 1), zb: V4 = gather(x, I + 4, 2)
            let xc: V4 = gather(x, I + 8, 0), yc: V4 = gather(x, I + 8, 1), zc: V4 = gather(x, I + 8, 2)
            let xd: V4 = gather(x, I + 12, 0), yd: V4 = gather(x, I + 12, 1), zd: V4 = gather(x, I + 12, 2)
            let ma: V4 = gm[4 * g], mb: V4 = gm[4 * g + 1], mc: V4 = gm[4 * g + 2], md: V4 = gm[4 * g + 3]
            let M: V4 = gMM[g]
            let cx: V4 = (xa * ma + xb * mb + xc * mc + xd * md) / M
            let cy: V4 = (ya * ma + yb * mb + yc * mc + yd * md) / M
            let cz: V4 = (za * ma + zb * mb + zc * mc + zd * md) / M
            // A = sum m p q^T, accumulated corner by corner from zero like the scalar sweep (no nested closures: a captured, mutated var is boxed
            // and dynamically exclusivity-checked, which costs a runtime call per access and scalarises the kernel)
            let pax: V4 = (xa - cx) * ma, pay: V4 = (ya - cy) * ma, paz: V4 = (za - cz) * ma
            let pbx: V4 = (xb - cx) * mb, pby: V4 = (yb - cy) * mb, pbz: V4 = (zb - cz) * mb
            let pcx: V4 = (xc - cx) * mc, pcy: V4 = (yc - cy) * mc, pcz: V4 = (zc - cz) * mc
            let pdx: V4 = (xd - cx) * md, pdy: V4 = (yd - cy) * md, pdz: V4 = (zd - cz) * md
            let qa0: V4 = q[0], qa1: V4 = q[1], qa2: V4 = q[2], qb0: V4 = q[3], qb1: V4 = q[4], qb2: V4 = q[5]
            let qc0: V4 = q[6], qc1: V4 = q[7], qc2: V4 = q[8], qd0: V4 = q[9], qd1: V4 = q[10], qd2: V4 = q[11]
            let zero: V4 = V4.zero
            let f00: V4 = zero + pax * qa0 + pbx * qb0 + pcx * qc0 + pdx * qd0
            let f01: V4 = zero + pax * qa1 + pbx * qb1 + pcx * qc1 + pdx * qd1
            let f02: V4 = zero + pax * qa2 + pbx * qb2 + pcx * qc2 + pdx * qd2
            let f10: V4 = zero + pay * qa0 + pby * qb0 + pcy * qc0 + pdy * qd0
            let f11: V4 = zero + pay * qa1 + pby * qb1 + pcy * qc1 + pdy * qd1
            let f12: V4 = zero + pay * qa2 + pby * qb2 + pcy * qc2 + pdy * qd2
            let f20: V4 = zero + paz * qa0 + pbz * qb0 + pcz * qc0 + pdz * qd0
            let f21: V4 = zero + paz * qa1 + pbz * qb1 + pcz * qc1 + pdz * qd1
            let f22: V4 = zero + paz * qa2 + pbz * qb2 + pcz * qc2 + pdz * qd2
            var qx: V4 = gr[4 * g], qy: V4 = gr[4 * g + 1], qz: V4 = gr[4 * g + 2], qw: V4 = gr[4 * g + 3]
            var done = SIMDMask<SIMD4<Float.SIMDMaskScalar>>(repeating: false)
            for _ in 0..<2 {
                let r00: V4 = one - two * (qy * qy + qz * qz), r01: V4 = two * (qx * qy - qw * qz), r02: V4 = two * (qx * qz + qw * qy)
                let r10: V4 = two * (qx * qy + qw * qz), r11: V4 = one - two * (qx * qx + qz * qz), r12: V4 = two * (qy * qz - qw * qx)
                let r20: V4 = two * (qx * qz - qw * qy), r21: V4 = two * (qy * qz + qw * qx), r22: V4 = one - two * (qx * qx + qy * qy)
                // (split into sub-expressions for the type checker; the left-to-right order of the scalar code is kept)
                let oxa: V4 = r10 * f20 - r20 * f10, oxb: V4 = r11 * f21 - r21 * f11, oxc: V4 = r12 * f22 - r22 * f12
                let oya: V4 = r20 * f00 - r00 * f20, oyb: V4 = r21 * f01 - r01 * f21, oyc: V4 = r22 * f02 - r02 * f22
                let oza: V4 = r00 * f10 - r10 * f00, ozb: V4 = r01 * f11 - r11 * f01, ozc: V4 = r02 * f12 - r12 * f02
                let ox: V4 = oxa + oxb + oxc, oy: V4 = oya + oyb + oyc, oz: V4 = oza + ozb + ozc
                let d1: V4 = r00 * f00 + r10 * f10 + r20 * f20
                let d2: V4 = d1 + r01 * f01 + r11 * f11 + r21 * f21
                let d3: V4 = d2 + r02 * f02 + r12 * f12 + r22 * f22
                let den: V4 = simd_abs(d3) + eps
                let wx: V4 = ox / den, wy: V4 = oy / den, wz: V4 = oz / den
                let w: V4 = (wx * wx + wy * wy + wz * wz).squareRoot()
                done = done .| (w .< small)
                let sc: V4 = half.replacing(with: half / w, where: w .> one)
                let ax: V4 = wx * sc, ay: V4 = wy * sc, az: V4 = wz * sc
                let nx: V4 = qx + ax * qw + ay * qz - az * qy
                let ny: V4 = qy - ax * qz + ay * qw + az * qx
                let nz: V4 = qz + ax * qy - ay * qx + az * qw
                let nw: V4 = qw - ax * qx - ay * qy - az * qz
                let nn0: V4 = nx * nx + ny * ny
                let nn: V4 = nn0 + nz * nz + nw * nw
                let nl: V4 = one / nn.squareRoot()
                qx = (nx * nl).replacing(with: qx, where: done); qy = (ny * nl).replacing(with: qy, where: done)
                qz = (nz * nl).replacing(with: qz, where: done); qw = (nw * nl).replacing(with: qw, where: done)
            }
            let r00: V4 = one - two * (qy * qy + qz * qz), r01: V4 = two * (qx * qy - qw * qz), r02: V4 = two * (qx * qz + qw * qy)
            let r10: V4 = two * (qx * qy + qw * qz), r11: V4 = one - two * (qx * qx + qz * qz), r12: V4 = two * (qy * qz - qw * qx)
            let r20: V4 = two * (qx * qz - qw * qy), r21: V4 = two * (qy * qz + qw * qx), r22: V4 = one - two * (qx * qx + qy * qy)
            gr[4 * g] = qx; gr[4 * g + 1] = qy; gr[4 * g + 2] = qz; gr[4 * g + 3] = qw
            let T = gt + 4 * g
            let firm: V4 = V4(tf[Int(T[0])], tf[Int(T[1])], tf[Int(T[2])], tf[Int(T[3])])
            let f: V4 = one / (one + base * firm * M * quarter)
            let tax: V4 = cx + r00 * qa0 + r01 * qa1 + r02 * qa2, tay: V4 = cy + r10 * qa0 + r11 * qa1 + r12 * qa2, taz: V4 = cz + r20 * qa0 + r21 * qa1 + r22 * qa2
            scatter(x, I, 0, xa + (tax - xa) * f, tmp); scatter(x, I, 1, ya + (tay - ya) * f, tmp); scatter(x, I, 2, za + (taz - za) * f, tmp)
            let tbx: V4 = cx + r00 * qb0 + r01 * qb1 + r02 * qb2, tby: V4 = cy + r10 * qb0 + r11 * qb1 + r12 * qb2, tbz: V4 = cz + r20 * qb0 + r21 * qb1 + r22 * qb2
            scatter(x, I + 4, 0, xb + (tbx - xb) * f, tmp); scatter(x, I + 4, 1, yb + (tby - yb) * f, tmp); scatter(x, I + 4, 2, zb + (tbz - zb) * f, tmp)
            let tcx: V4 = cx + r00 * qc0 + r01 * qc1 + r02 * qc2, tcy: V4 = cy + r10 * qc0 + r11 * qc1 + r12 * qc2, tcz: V4 = cz + r20 * qc0 + r21 * qc1 + r22 * qc2
            scatter(x, I + 8, 0, xc + (tcx - xc) * f, tmp); scatter(x, I + 8, 1, yc + (tcy - yc) * f, tmp); scatter(x, I + 8, 2, zc + (tcz - zc) * f, tmp)
            let tdx: V4 = cx + r00 * qd0 + r01 * qd1 + r02 * qd2, tdy: V4 = cy + r10 * qd0 + r11 * qd1 + r12 * qd2, tdz: V4 = cz + r20 * qd0 + r21 * qd1 + r22 * qd2
            scatter(x, I + 12, 0, xd + (tdx - xd) * f, tmp); scatter(x, I + 12, 1, yd + (tdy - yd) * f, tmp); scatter(x, I + 12, 2, zd + (tdz - zd) * f, tmp)
        }
    }

    private typealias V8 = SIMD8<Float>

    @inline(__always) private func gather8(_ x: UnsafePointer<Float>, _ I: UnsafePointer<Int32>, _ I2: UnsafePointer<Int32>, _ c: Int) -> V8 {
        V8(x[Int(I[0]) + c], x[Int(I[1]) + c], x[Int(I[2]) + c], x[Int(I[3]) + c], x[Int(I2[0]) + c], x[Int(I2[1]) + c], x[Int(I2[2]) + c], x[Int(I2[3]) + c])
    }
    @inline(__always) private func scatter8(_ x: UnsafeMutablePointer<Float>, _ I: UnsafePointer<Int32>, _ I2: UnsafePointer<Int32>, _ c: Int, _ v: V8, _ tmp: UnsafeMutableRawPointer) {
        tmp.storeBytes(of: v, as: V8.self)
        x[Int(I[0]) + c] = tmp.load(as: Float.self); x[Int(I[1]) + c] = tmp.load(fromByteOffset: 4, as: Float.self)
        x[Int(I[2]) + c] = tmp.load(fromByteOffset: 8, as: Float.self); x[Int(I[3]) + c] = tmp.load(fromByteOffset: 12, as: Float.self)
        x[Int(I2[0]) + c] = tmp.load(fromByteOffset: 16, as: Float.self); x[Int(I2[1]) + c] = tmp.load(fromByteOffset: 20, as: Float.self)
        x[Int(I2[2]) + c] = tmp.load(fromByteOffset: 24, as: Float.self); x[Int(I2[3]) + c] = tmp.load(fromByteOffset: 28, as: Float.self)
    }

    /// Perf A/B (SolverBenchTests): the 4-lane tets kernel instead of the 8-lane one (two groups of a level interleaved).
    nonisolated(unsafe) static var narrowTets = false

    private func solveTetsWide(_ dt: Float, _ x: UnsafeMutablePointer<Float>) {
        let base: V8 = V8(repeating: shapeCompliance() / (dt * dt))
        let L = tetLevels, ls = gLevelStart, gi = gIdx, gt = gTet, gm = gMass, gMM = gM, gq = gQ, gr = gRot, tf = tetFirm, tmp = laneTmp
        let quarter: V8 = V8(repeating: 0.25), one: V8 = V8(repeating: 1), two: V8 = V8(repeating: 2), half: V8 = V8(repeating: 0.5)
        let eps: V8 = V8(repeating: 1e-12), small: V8 = V8(repeating: 1e-6)
        for lv in 0..<L {
          var g = Int(ls[lv]); let end = Int(ls[lv + 1])
          while g < end {
            let g2 = min(g + 1, end - 1)        // two groups of one level at once (the level's last group twice when it has an odd count)
            let I = gi + 16 * g, q = gq + 12 * g, I2 = gi + 16 * g2, q2 = gq + 12 * g2
            let xa: V8 = gather8(x, I, I2, 0), ya: V8 = gather8(x, I, I2, 1), za: V8 = gather8(x, I, I2, 2)
            let xb: V8 = gather8(x, I + 4, I2 + 4, 0), yb: V8 = gather8(x, I + 4, I2 + 4, 1), zb: V8 = gather8(x, I + 4, I2 + 4, 2)
            let xc: V8 = gather8(x, I + 8, I2 + 8, 0), yc: V8 = gather8(x, I + 8, I2 + 8, 1), zc: V8 = gather8(x, I + 8, I2 + 8, 2)
            let xd: V8 = gather8(x, I + 12, I2 + 12, 0), yd: V8 = gather8(x, I + 12, I2 + 12, 1), zd: V8 = gather8(x, I + 12, I2 + 12, 2)
            let ma: V8 = V8(lowHalf: gm[4 * g], highHalf: gm[4 * g2]), mb: V8 = V8(lowHalf: gm[4 * g + 1], highHalf: gm[4 * g2 + 1]), mc: V8 = V8(lowHalf: gm[4 * g + 2], highHalf: gm[4 * g2 + 2]), md: V8 = V8(lowHalf: gm[4 * g + 3], highHalf: gm[4 * g2 + 3])
            let M: V8 = V8(lowHalf: gMM[g], highHalf: gMM[g2])
            let cx: V8 = (xa * ma + xb * mb + xc * mc + xd * md) / M
            let cy: V8 = (ya * ma + yb * mb + yc * mc + yd * md) / M
            let cz: V8 = (za * ma + zb * mb + zc * mc + zd * md) / M
            // A = sum m p q^T, accumulated corner by corner from zero like the scalar sweep (no nested closures: a captured, mutated var is boxed
            // and dynamically exclusivity-checked, which costs a runtime call per access and scalarises the kernel)
            let pax: V8 = (xa - cx) * ma, pay: V8 = (ya - cy) * ma, paz: V8 = (za - cz) * ma
            let pbx: V8 = (xb - cx) * mb, pby: V8 = (yb - cy) * mb, pbz: V8 = (zb - cz) * mb
            let pcx: V8 = (xc - cx) * mc, pcy: V8 = (yc - cy) * mc, pcz: V8 = (zc - cz) * mc
            let pdx: V8 = (xd - cx) * md, pdy: V8 = (yd - cy) * md, pdz: V8 = (zd - cz) * md
            let qa0: V8 = V8(lowHalf: q[0], highHalf: q2[0]), qa1: V8 = V8(lowHalf: q[1], highHalf: q2[1]), qa2: V8 = V8(lowHalf: q[2], highHalf: q2[2]), qb0: V8 = V8(lowHalf: q[3], highHalf: q2[3]), qb1: V8 = V8(lowHalf: q[4], highHalf: q2[4]), qb2: V8 = V8(lowHalf: q[5], highHalf: q2[5])
            let qc0: V8 = V8(lowHalf: q[6], highHalf: q2[6]), qc1: V8 = V8(lowHalf: q[7], highHalf: q2[7]), qc2: V8 = V8(lowHalf: q[8], highHalf: q2[8]), qd0: V8 = V8(lowHalf: q[9], highHalf: q2[9]), qd1: V8 = V8(lowHalf: q[10], highHalf: q2[10]), qd2: V8 = V8(lowHalf: q[11], highHalf: q2[11])
            let zero: V8 = V8.zero
            let f00: V8 = zero + pax * qa0 + pbx * qb0 + pcx * qc0 + pdx * qd0
            let f01: V8 = zero + pax * qa1 + pbx * qb1 + pcx * qc1 + pdx * qd1
            let f02: V8 = zero + pax * qa2 + pbx * qb2 + pcx * qc2 + pdx * qd2
            let f10: V8 = zero + pay * qa0 + pby * qb0 + pcy * qc0 + pdy * qd0
            let f11: V8 = zero + pay * qa1 + pby * qb1 + pcy * qc1 + pdy * qd1
            let f12: V8 = zero + pay * qa2 + pby * qb2 + pcy * qc2 + pdy * qd2
            let f20: V8 = zero + paz * qa0 + pbz * qb0 + pcz * qc0 + pdz * qd0
            let f21: V8 = zero + paz * qa1 + pbz * qb1 + pcz * qc1 + pdz * qd1
            let f22: V8 = zero + paz * qa2 + pbz * qb2 + pcz * qc2 + pdz * qd2
            var qx: V8 = V8(lowHalf: gr[4 * g], highHalf: gr[4 * g2]), qy: V8 = V8(lowHalf: gr[4 * g + 1], highHalf: gr[4 * g2 + 1])
            var qz: V8 = V8(lowHalf: gr[4 * g + 2], highHalf: gr[4 * g2 + 2]), qw: V8 = V8(lowHalf: gr[4 * g + 3], highHalf: gr[4 * g2 + 3])
            var done = SIMDMask<SIMD8<Float.SIMDMaskScalar>>(repeating: false)
            for _ in 0..<2 {
                let r00: V8 = one - two * (qy * qy + qz * qz), r01: V8 = two * (qx * qy - qw * qz), r02: V8 = two * (qx * qz + qw * qy)
                let r10: V8 = two * (qx * qy + qw * qz), r11: V8 = one - two * (qx * qx + qz * qz), r12: V8 = two * (qy * qz - qw * qx)
                let r20: V8 = two * (qx * qz - qw * qy), r21: V8 = two * (qy * qz + qw * qx), r22: V8 = one - two * (qx * qx + qy * qy)
                // (split into sub-expressions for the type checker; the left-to-right order of the scalar code is kept)
                let oxa: V8 = r10 * f20 - r20 * f10, oxb: V8 = r11 * f21 - r21 * f11, oxc: V8 = r12 * f22 - r22 * f12
                let oya: V8 = r20 * f00 - r00 * f20, oyb: V8 = r21 * f01 - r01 * f21, oyc: V8 = r22 * f02 - r02 * f22
                let oza: V8 = r00 * f10 - r10 * f00, ozb: V8 = r01 * f11 - r11 * f01, ozc: V8 = r02 * f12 - r12 * f02
                let ox: V8 = oxa + oxb + oxc, oy: V8 = oya + oyb + oyc, oz: V8 = oza + ozb + ozc
                let d1: V8 = r00 * f00 + r10 * f10 + r20 * f20
                let d2: V8 = d1 + r01 * f01 + r11 * f11 + r21 * f21
                let d3: V8 = d2 + r02 * f02 + r12 * f12 + r22 * f22
                let den: V8 = simd_abs(d3) + eps
                let wx: V8 = ox / den, wy: V8 = oy / den, wz: V8 = oz / den
                let w: V8 = (wx * wx + wy * wy + wz * wz).squareRoot()
                done = done .| (w .< small)
                let sc: V8 = half.replacing(with: half / w, where: w .> one)
                let ax: V8 = wx * sc, ay: V8 = wy * sc, az: V8 = wz * sc
                let nx: V8 = qx + ax * qw + ay * qz - az * qy
                let ny: V8 = qy - ax * qz + ay * qw + az * qx
                let nz: V8 = qz + ax * qy - ay * qx + az * qw
                let nw: V8 = qw - ax * qx - ay * qy - az * qz
                let nn0: V8 = nx * nx + ny * ny
                let nn: V8 = nn0 + nz * nz + nw * nw
                let nl: V8 = one / nn.squareRoot()
                qx = (nx * nl).replacing(with: qx, where: done); qy = (ny * nl).replacing(with: qy, where: done)
                qz = (nz * nl).replacing(with: qz, where: done); qw = (nw * nl).replacing(with: qw, where: done)
            }
            let r00: V8 = one - two * (qy * qy + qz * qz), r01: V8 = two * (qx * qy - qw * qz), r02: V8 = two * (qx * qz + qw * qy)
            let r10: V8 = two * (qx * qy + qw * qz), r11: V8 = one - two * (qx * qx + qz * qz), r12: V8 = two * (qy * qz - qw * qx)
            let r20: V8 = two * (qx * qz - qw * qy), r21: V8 = two * (qy * qz + qw * qx), r22: V8 = one - two * (qx * qx + qy * qy)
            gr[4 * g] = qx.lowHalf; gr[4 * g + 1] = qy.lowHalf; gr[4 * g + 2] = qz.lowHalf; gr[4 * g + 3] = qw.lowHalf
            gr[4 * g2] = qx.highHalf; gr[4 * g2 + 1] = qy.highHalf; gr[4 * g2 + 2] = qz.highHalf; gr[4 * g2 + 3] = qw.highHalf
            let T = gt + 4 * g, T2 = gt + 4 * g2
            let firm: V8 = V8(tf[Int(T[0])], tf[Int(T[1])], tf[Int(T[2])], tf[Int(T[3])], tf[Int(T2[0])], tf[Int(T2[1])], tf[Int(T2[2])], tf[Int(T2[3])])
            let f: V8 = one / (one + base * firm * M * quarter)
            let tax: V8 = cx + r00 * qa0 + r01 * qa1 + r02 * qa2, tay: V8 = cy + r10 * qa0 + r11 * qa1 + r12 * qa2, taz: V8 = cz + r20 * qa0 + r21 * qa1 + r22 * qa2
            scatter8(x, I, I2, 0, xa + (tax - xa) * f, tmp); scatter8(x, I, I2, 1, ya + (tay - ya) * f, tmp); scatter8(x, I, I2, 2, za + (taz - za) * f, tmp)
            let tbx: V8 = cx + r00 * qb0 + r01 * qb1 + r02 * qb2, tby: V8 = cy + r10 * qb0 + r11 * qb1 + r12 * qb2, tbz: V8 = cz + r20 * qb0 + r21 * qb1 + r22 * qb2
            scatter8(x, I + 4, I2 + 4, 0, xb + (tbx - xb) * f, tmp); scatter8(x, I + 4, I2 + 4, 1, yb + (tby - yb) * f, tmp); scatter8(x, I + 4, I2 + 4, 2, zb + (tbz - zb) * f, tmp)
            let tcx: V8 = cx + r00 * qc0 + r01 * qc1 + r02 * qc2, tcy: V8 = cy + r10 * qc0 + r11 * qc1 + r12 * qc2, tcz: V8 = cz + r20 * qc0 + r21 * qc1 + r22 * qc2
            scatter8(x, I + 8, I2 + 8, 0, xc + (tcx - xc) * f, tmp); scatter8(x, I + 8, I2 + 8, 1, yc + (tcy - yc) * f, tmp); scatter8(x, I + 8, I2 + 8, 2, zc + (tcz - zc) * f, tmp)
            let tdx: V8 = cx + r00 * qd0 + r01 * qd1 + r02 * qd2, tdy: V8 = cy + r10 * qd0 + r11 * qd1 + r12 * qd2, tdz: V8 = cz + r20 * qd0 + r21 * qd1 + r22 * qd2
            scatter8(x, I + 12, I2 + 12, 0, xd + (tdx - xd) * f, tmp); scatter8(x, I + 12, I2 + 12, 1, yd + (tdy - yd) * f, tmp); scatter8(x, I + 12, I2 + 12, 2, zd + (tdz - zd) * f, tmp)
            g += 2
          }
        }
    }

    private func solveVolumes(_ dt: Float, _ x: UnsafeMutablePointer<Float>) {
        if Self.referenceSolver { solveVolumesScalar(dt, x); return }
        let alpha0s = volCompliance() / (dt * dt)
        let alpha0: V4 = V4(repeating: alpha0s)
        let G = tetGroups, gi = gIdx, gt = gTet, gw = gInvMass, grv = gRestVol, tvs = tetVolScale, tmp = laneTmp
        let six: V4 = V4(repeating: 6), quarter: V4 = V4(repeating: 0.25), eps: V4 = V4(repeating: 1e-12)
        for g in 0..<G {
            let I = gi + 16 * g
            let xa: V4 = gatherOpaque(x, I, 0, tmp + 16), ya: V4 = gatherOpaque(x, I, 1, tmp + 32), za: V4 = gatherOpaque(x, I, 2, tmp + 48)
            let xb: V4 = gatherOpaque(x, I + 4, 0, tmp + 64), yb: V4 = gatherOpaque(x, I + 4, 1, tmp + 80), zb: V4 = gatherOpaque(x, I + 4, 2, tmp + 96)
            let xc: V4 = gatherOpaque(x, I + 8, 0, tmp + 112), yc: V4 = gatherOpaque(x, I + 8, 1, tmp + 128), zc: V4 = gatherOpaque(x, I + 8, 2, tmp + 144)
            let xd: V4 = gatherOpaque(x, I + 12, 0, tmp + 160), yd: V4 = gatherOpaque(x, I + 12, 1, tmp + 176), zd: V4 = gatherOpaque(x, I + 12, 2, tmp + 192)
            let bax: V4 = xb - xa, bay: V4 = yb - ya, baz: V4 = zb - za
            let cax: V4 = xc - xa, cay: V4 = yc - ya, caz: V4 = zc - za
            let dax: V4 = xd - xa, day: V4 = yd - ya, daz: V4 = zd - za
            let dbx: V4 = xd - xb, dby: V4 = yd - yb, dbz: V4 = zd - zb
            let cbx: V4 = xc - xb, cby: V4 = yc - yb, cbz: V4 = zc - zb
            let gax: V4 = dby * cbz - dbz * cby, gay: V4 = dbz * cbx - dbx * cbz, gaz: V4 = dbx * cby - dby * cbx
            let gbx: V4 = cay * daz - caz * day, gby: V4 = caz * dax - cax * daz, gbz: V4 = cax * day - cay * dax
            let gcx: V4 = day * baz - daz * bay, gcy: V4 = daz * bax - dax * baz, gcz: V4 = dax * bay - day * bax
            let gdx: V4 = bay * caz - baz * cay, gdy: V4 = baz * cax - bax * caz, gdz: V4 = bax * cay - bay * cax
            let V: V4 = (dax * gdx + day * gdy + daz * gdz) / six
            let wa: V4 = gw[4 * g], wb: V4 = gw[4 * g + 1], wc: V4 = gw[4 * g + 2], wd: V4 = gw[4 * g + 3]
            let sa: V4 = gax * gax + gay * gay + gaz * gaz, sb: V4 = gbx * gbx + gby * gby + gbz * gbz
            let sc: V4 = gcx * gcx + gcy * gcy + gcz * gcz, sd: V4 = gdx * gdx + gdy * gdy + gdz * gdz
            let wsum: V4 = wa * sa + wb * sb + wc * sc + wd * sd
            let T = gt + 4 * g
            if any(wsum .< eps) {
                // a flattened tet in one lane (the scalar sweep skips it): the rare exact path, the group's distinct tets one by one
                var last = -1
                for l in 0..<4 { let t = Int(T[l]); if t != last { solveVolumeTet(t, alpha0: alpha0s, x) }; last = t }
                continue
            }
            let r0: V4 = grv[g]
            let vs: V4 = V4(tvs[Int(T[0])], tvs[Int(T[1])], tvs[Int(T[2])], tvs[Int(T[3])])
            let alpha: V4 = (alpha0 * vs).replacing(with: V4.zero, where: V .< quarter * r0)
            let C: V4 = six * (V - r0)
            let s: V4 = (-C) / (wsum + alpha)
            scatter(x, I, 0, xa + gax * s * wa, tmp); scatter(x, I, 1, ya + gay * s * wa, tmp); scatter(x, I, 2, za + gaz * s * wa, tmp)
            scatter(x, I + 4, 0, xb + gbx * s * wb, tmp); scatter(x, I + 4, 1, yb + gby * s * wb, tmp); scatter(x, I + 4, 2, zb + gbz * s * wb, tmp)
            scatter(x, I + 8, 0, xc + gcx * s * wc, tmp); scatter(x, I + 8, 1, yc + gcy * s * wc, tmp); scatter(x, I + 8, 2, zc + gcz * s * wc, tmp)
            scatter(x, I + 12, 0, xd + gdx * s * wd, tmp); scatter(x, I + 12, 1, yd + gdy * s * wd, tmp); scatter(x, I + 12, 2, zd + gdz * s * wd, tmp)
        }
    }

    // MARK: scalar reference sweeps (the semantics; SoftBody.referenceSolver = true runs these)

    /// Per-tet co-rotational shape matching: find the rotation that best maps the rest tet onto the current
    /// one (Mueller et al. 2016, warm-started quaternion), then pull the four corners toward the rotated rest
    /// shape with XPBD compliance. Inverted tets are always pushed back to a proper shape.
    private func solveTetsScalar(_ dt: Float, _ x: UnsafeMutablePointer<Float>) {
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

    private func solveVolumesScalar(_ dt: Float, _ x: UnsafeMutablePointer<Float>) {
        let alpha0 = volCompliance() / (dt * dt)
        for t in 0..<nT { solveVolumeTet(t, alpha0: alpha0, x) }
    }

    @inline(__always) private func solveVolumeTet(_ t: Int, alpha0: Float, _ x: UnsafeMutablePointer<Float>) {
        do {
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
            if wsum < 1e-12 { return }
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

    /// Relative-velocity damping along the edges. Stays a scalar sweep: the 4-lane version was slower (two particles per edge, a dozen flops;
    /// the lane loads and stores dominate).
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

    /// Perf diagnostic (SolverBenchTests): one fixed step with a wall-clock timer around every pass, summed over the substeps. The state
    /// evolves exactly like `step()` (same passes, same order); only the bookkeeping differs. Returns (pass name, microseconds).
    func profileStep() -> [(String, Double)] {
        var acc: [String: Double] = [:], order: [String] = []
        @inline(never) func lap(_ name: String, _ t0: UInt64) {
            let us = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1000
            if acc[name] == nil { order.append(name) }
            acc[name, default: 0] += us
        }
        let sub = substeps
        let dt = stepDt / Float(sub)
        if pressing { buildPressList(); pressDeepest = 0 }
        var a1 = attractor
        if grabbing { a1.strength = 0 }
        var a0 = attPrev
        if a0.strength <= 0 { a0.anchor = a1.anchor; a0.rotation = a1.rotation; a0.squash = a1.squash }
        if a1.strength <= 0 { attFresh = true }
        x.withUnsafeMutableBufferPointer { xb in
            v.withUnsafeMutableBufferPointer { vb in
                let x = xb.baseAddress!, v = vb.baseAddress!
                for k in 0..<sub {
                    var att = a1
                    if a1.strength > 0 {
                        let t = Float(k + 1) / Float(sub)
                        att.strength = a0.strength + (a1.strength - a0.strength) * t
                        att.anchor = a0.anchor + (a1.anchor - a0.anchor) * t
                        att.squash = a0.squash + (a1.squash - a0.squash) * t
                        att.rotation = simd_slerp(a0.rotation, a1.rotation, t)
                    }
                    var t0 = DispatchTime.now().uptimeNanoseconds
                    let g = gravity * dt
                    let air = expf(-(grabbing ? 2.5 : airDrag()) * dt)
                    let prev = self.prev
                    for i in 0..<n {
                        let k = 3 * i
                        v[k + 1] += g
                        v[k] *= air; v[k + 1] *= air; v[k + 2] *= air
                        prev[k] = x[k]; prev[k + 1] = x[k + 1]; prev[k + 2] = x[k + 2]
                        x[k] += v[k] * dt; x[k + 1] += v[k + 1] * dt; x[k + 2] += v[k + 2] * dt
                    }
                    lap("integrate", t0)
                    if grabbing { t0 = DispatchTime.now().uptimeNanoseconds; solveGrab(dt, x); lap("grab", t0) }
                    t0 = DispatchTime.now().uptimeNanoseconds; solveTets(dt, x); lap("tets", t0)
                    t0 = DispatchTime.now().uptimeNanoseconds; solveVolumes(dt, x); lap("volumes", t0)
                    let attOn = att.strength > 0
                    if attOn { t0 = DispatchTime.now().uptimeNanoseconds; solveAttractor(dt, x, att); lap("attractor", t0) }
                    if !targets.isEmpty { t0 = DispatchTime.now().uptimeNanoseconds; solveTargets(dt, x); lap("targets", t0) }
                    if pressing { t0 = DispatchTime.now().uptimeNanoseconds; solvePress(x); lap("press", t0) }
                    t0 = DispatchTime.now().uptimeNanoseconds; solveFloor(x); lap("floor", t0)
                    if arenaRadius.isFinite { t0 = DispatchTime.now().uptimeNanoseconds; solveArena(x); lap("arena", t0) }
                    t0 = DispatchTime.now().uptimeNanoseconds
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
                        let kd = 1 - expf(-2 * att.damping * att.strength.squareRoot() * dt)
                        for i in 0..<(3 * n) { v[i] += (attV[i] - v[i]) * kd }
                    }
                    lap("velocities", t0)
                    t0 = DispatchTime.now().uptimeNanoseconds; dampEdges(dt, x, v); lap("dampEdges", t0)
                }
                time += stepDt
                let t0 = DispatchTime.now().uptimeNanoseconds
                if !grabbing {
                    let ke = kineticEnergy(v) / totalMass
                    if ke < 2e-2 { let u = 1 - ke / 2e-2; let f = 1 - 0.14 * u * u; for i in 0..<(3 * n) { v[i] *= f } }
                    if ke < 2e-5 { restSteps += 1 } else { restSteps = 0 }
                    if restSteps > 15 { for i in 0..<(3 * n) { v[i] = 0 } }
                } else { restSteps = 0 }
                lap("settle", t0)
            }
        }
        attPrev = a1
        if pressing { pressDepth = pressDeepest }
        return order.map { ($0, acc[$0]!) }
    }

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
