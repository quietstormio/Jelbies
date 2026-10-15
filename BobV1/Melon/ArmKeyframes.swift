//
//  ArmKeyframes.swift
//  Precomputed (background) per-keyframe displacements + AO for the render vertices that change while an `ArmPath` plays,
//  and the runtime that evaluates them: (path keyframes, s, side) -> additive world displacement + AO per vertex.
//
//  Vertex classes per keyframe and side (region = body skin with mat <= 0.4 and rest x * sigma > 0.25):
//    1 COVERED  inside the posed capsule: tucked onto the bare egg (and sunk), hidden under the capsule.
//    2 FILLET   rest arm skin or egg skin near the new arm: projected onto F_s = smin(egg, cone, k), sunk slightly where
//               the capsule surface is close (z-fight guard).
//    3 REST     untouched (only its AO is recomputed with F_s).
//  The capsule itself (appended to the render mesh) is moved from its hidden rest shape to the posed revolve.
//  Nothing is stored for s = 0: displacements are exactly 0 and AO is the baked value.
//

import Foundation
import simd

nonisolated struct ArmKeyframes: Sendable {
    struct Side: Sendable {
        var vertices: [Int32] = []         // render vertex ids: skin vertices first, then the capsule's
        var skinCount = 0
        var delta: [Float] = []            // (K+1) x n x 3, body frame
        var ao: [Float] = []               // (K+1) x n, value for the mat channel (0 ... 0.4)
        var cls: [UInt8] = []              // (K+1) x n: 1, 2, 3 (skin) / 0 (capsule)
        var restMat: [Float] = []          // n, the baked mat value
    }
    let name: String
    let intervals: Int                     // K; keyframes 0...K
    var sides: [Side]                      // [-1, +1]
    var seconds: Double = 0
    let scale: Double

    func side(_ s: Int) -> Side { s < 0 ? sides[0] : sides[1] }

    /// Evaluate keyframes at s (0...1): displacement rotated into the world by `rotation`, plus AO.
    func evaluate(side sd: Int, s: Float, rotation: simd_quatf, delta: inout [SIMD3<Float>], ao: inout [Float]) {
        let S = side(sd)
        let n = S.vertices.count
        if delta.count != n { delta = [SIMD3<Float>](repeating: .zero, count: n) }
        if ao.count != n { ao = [Float](repeating: 0, count: n) }
        let f = min(max(s, 0), 1) * Float(intervals)
        let k0 = min(Int(f), intervals - 1)
        let t = f - Float(k0), it = 1 - t
        let m = simd_float3x3(rotation)
        S.delta.withUnsafeBufferPointer { d in
            S.ao.withUnsafeBufferPointer { a in
                let o0 = k0 * n, o1 = (k0 + 1) * n
                for i in 0..<n {
                    let a0 = 3 * (o0 + i), a1 = 3 * (o1 + i)
                    let v = SIMD3(d[a0] * it + d[a1] * t, d[a0 + 1] * it + d[a1 + 1] * t, d[a0 + 2] * it + d[a1 + 2] * t)
                    delta[i] = m * v
                    ao[i] = a[o0 + i] * it + a[o1 + i] * t
                }
            }
        }
    }
}

/// Capture / debugging knobs (launch arguments). -ArmAOMode: 0 normal, 1 no AO writes (baked values kept, capsule 0),
/// 2 capsule uses the same AO strength as the skin, 3 colour debug (capsule bright, skin dark).
nonisolated enum ArmDebug {
    static let aoMode = UserDefaults.standard.integer(forKey: "ArmAOMode")
    static let coverOnField = UserDefaults.standard.object(forKey: "ArmCoverEgg") == nil || UserDefaults.standard.integer(forKey: "ArmCoverEgg") == 0
    static let relaxWebs = UserDefaults.standard.object(forKey: "ArmRelaxWebs") == nil || UserDefaults.standard.integer(forKey: "ArmRelaxWebs") != 0
    static let relaxPasses = 8
    /// Largest total inward pull of one skin vertex by the web relaxation (world units).
    static let relaxMax: Double = UserDefaults.standard.object(forKey: "ArmRelaxMax") != nil ? UserDefaults.standard.double(forKey: "ArmRelaxMax") : 0.012
    static let smoothPasses: Int = UserDefaults.standard.object(forKey: "ArmSmoothPasses") != nil ? UserDefaults.standard.integer(forKey: "ArmSmoothPasses") : 3
    /// Flared capsule base (off by default: it produced a long sliver fin along the arm's inner side, see the report).
    static let flare = UserDefaults.standard.integer(forKey: "ArmFlare") != 0
    static let flareRange: Double = UserDefaults.standard.object(forKey: "ArmFlareRange") != nil ? UserDefaults.standard.double(forKey: "ArmFlareRange") : 0.08
    static let sinkReach: Double = UserDefaults.standard.object(forKey: "ArmSinkReach") != nil ? UserDefaults.standard.double(forKey: "ArmSinkReach") : 0.04
}

nonisolated enum ArmKeyframeBuilder {
    static let skinRegionMinX: Float = 0.25

    /// Region (skin) vertex ids of a side.
    static func region(rest: [Float], mat: [Float], sigma: Float, capsuleFirst: Int) -> [Int32] {
        var out: [Int32] = []
        for v in 0..<capsuleFirst where mat[v] <= 0.4 && rest[3 * v] * sigma > skinRegionMinX { out.append(Int32(v)) }
        return out
    }

    struct VertexResult { var p: SIMD3<Double>; var cls: UInt8; var ao: Double }

    /// Classify and pose one skin vertex (mirrored coordinates, arm on +x). Exposed for the tests.
    static func pose(vertex p: SIMD3<Double>, field F: PosedArmField, restArm: Double) -> (p: SIMD3<Double>, cls: UInt8) {
        let g = F.g
        let infl = g.capsuleInflate
        let cone0 = F.cone(p)
        // 1 covered
        if g.grow >= 1 && cone0 < infl - 0.003 {      // only once the capsule is fully there to hide them
            var q = ArmDebug.coverOnField ? F.project(p) : BobForm.projectEgg(p)
            let n = ArmDebug.coverOnField ? F.normal(q) : simd_normalize(BobForm.eggGradient(q))
            q -= n * (ArmDebug.coverOnField ? 0.01 : ArmGeom.capsuleLift)
            if F.cone(q) <= infl - 0.007 { return (q, 1) }
        }
        // 2 fillet
        var near = restArm < -1e-4
        if !near {
            let ab = g.B - g.A, t = min(max(simd_dot(p - g.A, ab) / simd_dot(ab, ab), 0), 1)
            let dist = simd_length(p - (g.A + ab * t))
            if dist < 0.22 + max(g.r1, g.r2) && F.value(p) < BobForm.bodySDF(p) - 1e-4 { near = true }
        }
        if near {
            var q = F.project(p)
            let c = F.cone(q)
            let sink = ArmGeom.capsuleLift * g.grow * min(max(1 - c / ArmDebug.sinkReach, 0), 1)
            if sink > 0 { q -= F.normal(q) * sink }
            return (q, 2)
        }
        return (p, 3)
    }

    /// Rest-arm test: how much the rest arm lowers the field below the egg at p (mirrored coordinates).
    static func restArmDelta(_ p: SIMD3<Double>) -> Double {
        let arm = BobForm.armSDF(SIMD3(abs(p.x), p.y, p.z))
        let u = 1 - min(max(arm.t / 0.55, 0), 1)
        let k = BobForm.armTipBlend + (BobForm.armBlend - BobForm.armTipBlend) * (u * u * (3 - 2 * u))
        let e = BobForm.bodySDF(p)
        return BobForm.smin(e, arm.d, k) - e
    }

    static func build(path: ArmPath, rest: [Float], mat: [Float], capsule: ArmCapsuleInfo, index: [UInt32], intervals K: Int = 32,
                      scale: Double = 1) -> ArmKeyframes {
        let t0 = CFAbsoluteTimeGetCurrent()
        let geoms = (0...K).map { path.geom(at: Double($0) / Double(K), scale: scale) }
        var out = ArmKeyframes(name: path.name, intervals: K, sides: [], scale: scale)
        let capFirst = min(capsule.firstVertex[0], capsule.firstVertex[1])
        for sigma in [-1.0, 1.0] {
            let reg = region(rest: rest, mat: mat, sigma: Float(sigma), capsuleFirst: capFirst)
            let first = capsule.first(side: Int(sigma))
            let nS = reg.count, nC = ArmCapsule.vertexCount, n = nS + nC
            var delta = [Float](repeating: 0, count: (K + 1) * n * 3)
            var ao = [Float](repeating: 0, count: (K + 1) * n)
            var cls = [UInt8](repeating: 3, count: (K + 1) * n)
            var restMat = [Float](repeating: 0, count: n)
            for i in 0..<nS { restMat[i] = mat[Int(reg[i])] }
            for i in 0..<nC { restMat[nS + i] = mat[first + i] }
            let restP: [SIMD3<Double>] = reg.map { v in
                SIMD3(Double(rest[3 * Int(v)]) * sigma, Double(rest[3 * Int(v) + 1]), Double(rest[3 * Int(v) + 2]))
            }
            let restArm = restP.map { restArmDelta($0) }
            let inactive = ArmCapsule.inactive(sigma: sigma)
            // skin triangles touching this side's region (for the web relaxation below)
            var local = [Int32](repeating: -1, count: capFirst)
            for (i, v) in reg.enumerated() { local[Int(v)] = Int32(i) }
            var triList: [(Int32, Int32, Int32)] = []
            var nbrs = [[Int32]](repeating: [], count: nS)
            var ti = 0
            while ti < capsule.indexFirst {
                let a = Int(index[ti]), b = Int(index[ti + 1]), c = Int(index[ti + 2])
                if a < capFirst && b < capFirst && c < capFirst && (local[a] >= 0 || local[b] >= 0 || local[c] >= 0) {
                    triList.append((Int32(a), Int32(b), Int32(c)))
                    for (x, y, z) in [(a, b, c), (b, c, a), (c, a, b)] where local[x] >= 0 {
                        nbrs[Int(local[x])] += [Int32(y), Int32(z)]
                    }
                }
                ti += 3
            }
            delta.withUnsafeMutableBufferPointer { dP in
                ao.withUnsafeMutableBufferPointer { aP in
                    cls.withUnsafeMutableBufferPointer { cP in
                        let dB = dP.baseAddress!, aB = aP.baseAddress!, cB = cP.baseAddress!
                        DispatchQueue.concurrentPerform(iterations: K + 1) { k in
                            let o = k * n
                            if k == 0 {
                                for i in 0..<n { aB[o + i] = restMat[i]; cB[o + i] = i < nS ? 3 : 0 }
                                return
                            }
                            let g = geoms[k], F = PosedArmField(g)
                            var posK = [SIMD3<Double>](repeating: .zero, count: nS)
                            var clsK = [UInt8](repeating: 3, count: nS)
                            for i in 0..<nS {
                                let r = pose(vertex: restP[i], field: F, restArm: restArm[i])
                                posK[i] = r.p; clsK[i] = r.cls
                            }
                            if ArmDebug.smoothPasses > 0 {
                                // tangential smoothing of the movable skin (class 2), re-projected onto F_s, so vertices that piled up
                                // where the rest bulb collapsed spread out again instead of forming crumpled folds
                                @inline(__always) func atS(_ v: Int32) -> SIMD3<Double> {
                                    let l = local[Int(v)]
                                    return l >= 0 ? posK[Int(l)] : SIMD3(Double(rest[3 * Int(v)]) * sigma, Double(rest[3 * Int(v) + 1]), Double(rest[3 * Int(v) + 2]))
                                }
                                for _ in 0..<ArmDebug.smoothPasses {
                                    var nxt = posK
                                    for i in 0..<nS where clsK[i] == 2 && !nbrs[i].isEmpty {
                                        var m = SIMD3<Double>.zero
                                        for n in nbrs[i] { m += atS(n) }
                                        m /= Double(nbrs[i].count)
                                        var q = F.project(posK[i] * 0.4 + m * 0.6, steps: 6)
                                        let sink = ArmGeom.capsuleLift * g.grow * min(max(1 - F.cone(q) / ArmDebug.sinkReach, 0), 1)
                                        if sink > 0 { q -= F.normal(q) * sink }
                                        nxt[i] = q
                                    }
                                    posK = nxt
                                }
                            }
                            if ArmDebug.relaxWebs {
                                // Valley chords: a triangle bridging a cone-side and an egg-side vertex can lie outside the field (a fin).
                                // Pull the movable (class 2) vertices of such triangles inward along -grad F until its centroid is back
                                // inside F + 0.004.
                                @inline(__always) func at(_ v: Int32) -> SIMD3<Double> {
                                    let l = local[Int(v)]
                                    return l >= 0 ? posK[Int(l)] : SIMD3(Double(rest[3 * Int(v)]) * sigma, Double(rest[3 * Int(v) + 1]), Double(rest[3 * Int(v) + 2]))
                                }
                                var pulled = [Double](repeating: 0, count: nS)
                                for _ in 0..<ArmDebug.relaxPasses {
                                    var any = false
                                    for (a, b, c) in triList {
                                        let la = Int(local[Int(a)]), lb = Int(local[Int(b)]), lc = Int(local[Int(c)])
                                        if !((la >= 0 && clsK[la] == 2) || (lb >= 0 && clsK[lb] == 2) || (lc >= 0 && clsK[lc] == 2)) { continue }
                                        let pa = at(a), pb = at(b), pc = at(c)
                                        let f = F.value((pa + pb + pc) / 3)
                                        if f <= 0.004 { continue }
                                        any = true
                                        let want = min(0.02, (f - 0.002) * 1.0)
                                        for (l, p) in [(la, pa), (lb, pb), (lc, pc)] where l >= 0 && clsK[l] == 2 {
                                            let push = min(want, ArmDebug.relaxMax - pulled[l])
                                            if push <= 0 { continue }
                                            pulled[l] += push
                                            posK[l] = p - F.normal(p) * push
                                        }
                                    }
                                    if !any { break }
                                }
                            }
                            for i in 0..<nS {
                                let r = (p: posK[i], cls: clsK[i])
                                let d = r.p - restP[i]
                                dB[3 * (o + i)] = Float(d.x * sigma); dB[3 * (o + i) + 1] = Float(d.y); dB[3 * (o + i) + 2] = Float(d.z)
                                cB[o + i] = r.cls
                                let nrm = F.normal(r.p)
                                switch ArmDebug.aoMode {
                                case 1: aB[o + i] = restMat[i]
                                case 3: aB[o + i] = 0.4
                                default: aB[o + i] = Float(0.4 * F.occlusion(r.p, nrm))
                                }
                            }
                            var cap = ArmCapsule.points(g, inflate: g.capsuleInflate, sigma: sigma)
                            if ArmDebug.flare {
                                // flared base: capsule vertices just outside the egg are pulled onto the fillet surface F_s (so the
                                // base melts into the egg with matching normals). Vertices still inside the egg are hidden and stay on the cone.
                                for i in 0..<nC {
                                    let c = SIMD3(cap.pos[i].x * sigma, cap.pos[i].y, cap.pos[i].z)
                                    let e = BobForm.bodySDF(c)
                                    if e > 0 {
                                        let w = g.grow
                                        let t = F.project(c, steps: 8) + F.normal(c) * (0.0007 * g.grow)
                                        let q = c + (t - c) * w
                                        cap.pos[i] = SIMD3(q.x * sigma, q.y, q.z)
                                    }
                                }
                            }
                            for i in 0..<nC {
                                let d = cap.pos[i] - inactive[i]
                                let a3 = 3 * (o + nS + i)
                                dB[a3] = Float(d.x); dB[a3 + 1] = Float(d.y); dB[a3 + 2] = Float(d.z)
                                cB[o + nS + i] = 0
                                let q = SIMD3(cap.pos[i].x * sigma, cap.pos[i].y, cap.pos[i].z)
                                let capAO = Float(0.2 * F.occlusion(q, SIMD3(cap.nrm[i].x * sigma, cap.nrm[i].y, cap.nrm[i].z)))
                                switch ArmDebug.aoMode {
                                case 1, 3: aB[o + nS + i] = 0
                                case 2: aB[o + nS + i] = capAO * 2
                                default: aB[o + nS + i] = capAO
                                }
                            }
                        }
                    }
                }
            }
            // prune skin vertices that never move and keep (nearly) their baked AO
            var keep: [Int] = []
            for i in 0..<nS {
                var moves = false
                for k in 1...K {
                    let o = k * n + i
                    if cls[o] != 3 || abs(ao[o] - restMat[i]) > 1e-3 { moves = true; break }
                }
                if moves { keep.append(i) }
            }
            let kept = keep + Array(nS..<n)
            var side = ArmKeyframes.Side()
            side.skinCount = keep.count
            side.vertices = kept.map { $0 < nS ? reg[$0] : Int32(first + $0 - nS) }
            side.restMat = kept.map { restMat[$0] }
            let m = kept.count
            side.delta = [Float](repeating: 0, count: (K + 1) * m * 3)
            side.ao = [Float](repeating: 0, count: (K + 1) * m)
            side.cls = [UInt8](repeating: 3, count: (K + 1) * m)
            for k in 0...K {
                for (j, i) in kept.enumerated() {
                    for c in 0..<3 { side.delta[3 * (k * m + j) + c] = delta[3 * (k * n + i) + c] }
                    side.ao[k * m + j] = ao[k * n + i]
                    side.cls[k * m + j] = cls[k * n + i]
                }
            }
            out.sides.append(side)
        }
        out.seconds = CFAbsoluteTimeGetCurrent() - t0
        return out
    }
}
