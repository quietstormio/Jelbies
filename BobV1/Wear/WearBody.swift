//
//  WearBody.swift
//  The rest body's egg surface as a bind target for wearables. Every Jelly shares one render mesh, so the surface is built ONCE from `RenderMesh.rest`:
//  the egg triangles only (the arm capsules and foot beans sit hidden inside it at rest and would steal the bindings), with a uniform grid for
//  the nearest-triangle query.
//
//  A "bind" pins a rest-space point to the surface: the triangle, the barycentric foot point, and the point's offset in the triangle's smooth frame
//  (T = first edge projected into the tangent plane of the interpolated vertex normal, N = that normal, B = N x T). At runtime the same frame is built
//  from the SKINNED triangle (positions + the smoothed skin normals the CPU already wrote to the shared vertex buffer), so a bound point follows the
//  local jiggle of the skin it sits on, and at rest it lands exactly on its authored position.
//

import simd
import Foundation

nonisolated struct SurfaceBind: Sendable {
    var tri: SIMD3<UInt32> = .zero
    var bary: SIMD3<Float> = .zero
    /// Offset in the (T, B, N) frame.
    var off: SIMD3<Float> = .zero
}

/// The limbs that stand out of the egg, as the renderer draws them: the two arm capsules, the two foot beans and Pip's tail block. Each is a pole + `rings`
/// rings of `around` vertices + pole, so the drawn surface is read straight back as a generalized cylinder (the centre of every ring, the ring's mean radius,
/// the poles as zero-radius ends). A wearable bound to the EGG skin passes straight through whichever limb is out at its height (the walking arm's root is
/// 0.13 thick and swings up through the necklace line); `push` slides such a vertex along the wall until it is outside the limb. Built once per body per
/// frame from the skin the wear is already reading (WornSet.frame), or once from the rest mesh to find which authored vertices start clear of the limbs.
nonisolated struct WearLimbs: Sendable {
    struct Chain: Sendable {
        var c: [SIMD3<Float>] = [], rho: [Float] = []
        var lo = SIMD3<Float>.zero, hi = SIMD3<Float>.zero, reach: Float = 0
    }
    var chains: [Chain] = []
    var isEmpty: Bool { chains.isEmpty }
    /// The push can be switched off for before / after comparisons (tests only).
    /// (test / capture aid: the environment variable WEARFIT_LIMBS=off turns it off for the whole process, for before / after comparisons.)
    nonisolated(unsafe) static var enabled = ProcessInfo.processInfo.environment["WEARFIT_LIMBS"] != "off"
    /// How far past the drawn surface a pushed vertex ends up (the skin's own relief and the strand's thickness).
    static let margin: Float = 0.006
    /// The most a limb may move a vertex off the skin it is bound to: past this the piece would hang in the air (the skin dips and bulges round a swung arm), so it stays and the limb pokes through.
    nonisolated(unsafe) static var maxPush: Float = Float(ProcessInfo.processInfo.environment["WEARFIT_PUSHMAX"] ?? "") ?? 0.14
    /// 0...1: how much of the way back DOWN onto the skin a pushed point goes after it has slid round a limb (it slides along the wall's tangent plane, which leaves the curved wall).
    nonisolated(unsafe) static var rehugBlend: Float = Float(ProcessInfo.processInfo.environment["WEARFIT_REHUGBLEND"] ?? "") ?? 0.5
    static let rehugVertexBudget = 10
    nonisolated(unsafe) static var alwaysSlide = ProcessInfo.processInfo.environment["WEARFIT_RADIAL"] == nil
    nonisolated(unsafe) static var maxPushVertex: Float = Float(ProcessInfo.processInfo.environment["WEARFIT_PUSHMAXV"] ?? "") ?? 0.14
    /// How far along a strand a push is shared with its neighbours (falling quadratically): the string leaves and rejoins the wall in a curve, not a V.
    nonisolated(unsafe) static var spread: Float = Float(ProcessInfo.processInfo.environment["WEARFIT_SPREAD"] ?? "") ?? 0.09
    nonisolated(unsafe) static var spreadMax: Float = Float(ProcessInfo.processInfo.environment["WEARFIT_SPREADMAX"] ?? "") ?? 0.03

    /// `P(i)` = the position of render vertex i. `blocks` = (first vertex, around, rings).
    static func build(blocks: [(first: Int, around: Int, rings: Int)], P: (Int) -> SIMD3<Float>) -> WearLimbs {
        var out = WearLimbs()
        for b in blocks {
            var ch = Chain()
            ch.c.append(P(b.first)); ch.rho.append(0)
            var mx: Float = 0
            for r in 0..<b.rings {
                var sum = SIMD3<Float>.zero
                let o = b.first + 1 + b.around * r
                for j in 0..<b.around { sum += P(o + j) }
                let ctr = sum / Float(b.around)
                var rad: Float = 0
                for j in 0..<b.around { rad += simd_distance(P(o + j), ctr) }
                rad /= Float(b.around)
                ch.c.append(ctr); ch.rho.append(rad); mx = max(mx, rad)
            }
            ch.c.append(P(b.first + 1 + b.around * b.rings)); ch.rho.append(0)
            guard mx > 0.02 else { continue }                                  // a collapsed block (Pip's tail on the others) is nothing
            var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
            for q in ch.c { lo = simd_min(lo, q); hi = simd_max(hi, q) }
            ch.lo = lo - mx - margin; ch.hi = hi + mx + margin; ch.reach = mx
            out.chains.append(ch)
        }
        return out
    }

    /// The two resting arm nubs (the rest round cone, the hidden shape shrunk 2 cm as the skinner draws it) in the rest frame: the only limbs that are out of
    /// the egg while he stands still. (The rest mesh's arm vertices are texture coordinates, not this shape, so they cannot be read back.)
    static func restArms() -> WearLimbs {
        var out = WearLimbs()
        let a = ArmGeom.rest, infl: Double = -0.02
        for sg in [-1.0, 1.0] {
            let A = SIMD3<Float>(Float(a.A.x * sg), Float(a.A.y), Float(a.A.z)), B = SIMD3<Float>(Float(a.B.x * sg), Float(a.B.y), Float(a.B.z))
            let R1 = Float(a.r1 + infl), R2 = Float(a.r2 + infl)
            let u = simd_normalize(B - A)
            var ch = Chain()
            ch.c = [B + u * R2, B, A, A - u * R1]; ch.rho = [0, R2, R1, 0]
            var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
            for q in ch.c { lo = simd_min(lo, q); hi = simd_max(hi, q) }
            let mx = max(R1, R2)
            ch.lo = lo - mx - margin; ch.hi = hi + mx + margin; ch.reach = mx
            out.chains.append(ch)
        }
        return out
    }

    /// The blocks of a render mesh: [arm -x, arm +x, bean -x, bean +x, tail].
    static func blocks(_ rm: RenderMesh) -> [(first: Int, around: Int, rings: Int)] {
        guard let cap = rm.armCapsule, cap.firstVertex.count == 2 else { return [] }
        var b: [(first: Int, around: Int, rings: Int)] = []
        for f in cap.firstVertex { b.append((f, ArmCapsule.around, ArmCapsule.ringCount)) }
        for f in cap.firstVertex { b.append((f + ArmCapsule.vertexCount, FootBean.around, FootBean.rings)) }
        if cap.tailFirst >= 0 { b.append((cap.tailFirst, TailBean.around, TailBean.rings)) }
        return b
    }

    /// Depth of `p` inside the limb of chain `k` (> 0 inside), the nearest axis point and its radius.
    @inline(__always)
    private func depth(_ ch: Chain, _ p: SIMD3<Float>) -> (depth: Float, axis: SIMD3<Float>) {
        var best = Float.infinity, bestAxis = SIMD3<Float>.zero, bestRho: Float = 0
        for i in 0..<(ch.c.count - 1) {
            let a = ch.c[i], b = ch.c[i + 1], ab = b - a
            let l2 = simd_length_squared(ab)
            let t = l2 > 1e-12 ? min(max(simd_dot(p - a, ab) / l2, 0), 1) : 0
            let q = a + ab * t
            let rho = ch.rho[i] + (ch.rho[i + 1] - ch.rho[i]) * t
            let d = simd_distance(p, q) - rho                         // < 0 inside
            if d < best { best = d; bestAxis = q; bestRho = rho }
        }
        _ = bestRho
        return (-best, bestAxis)
    }

    /// How deep `p` is inside the deepest limb (negative = outside all of them, -1 when none is near).
    func penetration(_ p: SIMD3<Float>) -> Float {
        var m: Float = -1
        for ch in chains where all(p .>= ch.lo) && all(p .<= ch.hi) { m = max(m, depth(ch, p).depth) }
        return m
    }

    /// Is `p` inside any limb (by more than `tol`)?
    func inside(_ p: SIMD3<Float>, tol: Float = 0) -> Bool {
        for ch in chains where all(p .>= ch.lo) && all(p .<= ch.hi) { if depth(ch, p).depth > tol { return true } }
        return false
    }

    /// `p` moved along the wall (normal `n`) away from the limb axis until it is outside the limb by the margin; unchanged when it is clear.
    func push(_ p0: SIMD3<Float>, wallNormal n: SIMD3<Float>, margin: Float = WearLimbs.margin, cap: Float = WearLimbs.maxPush) -> SIMD3<Float> {
        var p = p0
        for ch in chains where all(p .>= ch.lo) && all(p .<= ch.hi) {
            var (d, axis) = depth(ch, p)
            guard d > -margin else { continue }
            var away = p - axis
            if Self.alwaysSlide || simd_dot(away, n) < 0 { away -= n * simd_dot(away, n) }        // out of the limb by the shortest way (over its surface, so the piece rests ON the limb, never hangs off the body); if that is into the wall, along the wall instead
            var l = simd_length(away)
            if l < 1e-4 { away = SIMD3(0, 1, 0) - n * n.y; l = simd_length(away) }
            if l < 1e-4 { away = SIMD3(1, 0, 0) - n * n.x; l = simd_length(away) }
            away /= max(l, 1e-6)
            for _ in 0..<4 {
                p += away * (d + margin)
                (d, axis) = depth(ch, p)
                if d <= -margin * 0.5 { break }
            }
        }
        let d = p - p0, l = simd_length(d)
        if l > cap { p = p0 + d * (cap / l) }
        return p
    }
}

nonisolated final class WearBody: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _shared: WearBody?
    /// Every Jelly shares one rest render mesh, so one body serves all of them. The stage installs its mesh; anything else (tests) builds the base mesh.
    static func install(_ rm: RenderMesh) { lock.lock(); if _shared == nil { _shared = WearBody(rm) }; lock.unlock() }
    static var shared: WearBody {
        lock.lock(); defer { lock.unlock() }
        if let s = _shared { return s }
        let b = WearBody(buildRenderMesh())
        _shared = b
        return b
    }

    let pos: [SIMD3<Float>]
    let nrm: [SIMD3<Float>]
    let tris: [SIMD3<UInt32>]
    let eggVertexLimit: Int
    /// The limbs in the rest pose (arms hidden in the egg, feet beans sunk in, Pip's tail collapsed): which authored vertices start inside one (they are the garment's own cover and are never pushed).
    let restLimbs: WearLimbs
    let limbBlocks: [(first: Int, around: Int, rings: Int)]
    /// The egg vertices of the head cap (the highest ones): what a hat's crown must always enclose (CrownFit).
    let capIndices: [Int]
    /// The vertical axis (x = 0, z = axisZ, rest space) the encircling parts are levelled about (WearLevel): the mean z of the rest egg.
    let axisZ: Float
    private let cell: Float = 0.08
    private let lo: SIMD3<Float>
    private let dim: SIMD3<Int>
    private var grid: [[Int32]]
    /// `bind` marks the triangles it has already tested with a generation stamp (no Set per call); the lock keeps it safe for any caller.
    private let bindLock = NSLock()
    private var stamp: [UInt32]
    private var stampGen: UInt32 = 0

    init(_ rm: RenderMesh) {
        var p: [SIMD3<Float>] = [], n: [SIMD3<Float>] = []
        p.reserveCapacity(rm.vertexCount)
        for i in 0..<rm.vertexCount {
            p.append(SIMD3(rm.rest[3 * i], rm.rest[3 * i + 1], rm.rest[3 * i + 2]))
            n.append(SIMD3(rm.restNormal[3 * i], rm.restNormal[3 * i + 1], rm.restNormal[3 * i + 2]))
        }
        pos = p; nrm = n
        let end = min(rm.armCapsule?.indexFirst ?? rm.body.count, rm.body.first + rm.body.count)
        var t: [SIMD3<UInt32>] = []
        var i = rm.body.first
        while i + 2 < end { t.append(SIMD3(rm.index[i], rm.index[i + 1], rm.index[i + 2])); i += 3 }
        tris = t
        stamp = [UInt32](repeating: 0, count: t.count)
        eggVertexLimit = rm.armCapsule?.firstVertex.min() ?? rm.vertexCount
        limbBlocks = WearLimbs.blocks(rm)
        restLimbs = WearLimbs.restArms()
        let eggN = max(1, min(rm.armCapsule?.firstVertex.min() ?? rm.vertexCount, p.count))
        axisZ = (0..<eggN).reduce(Float(0)) { $0 + p[$1].z } / Float(eggN)
        let eggTop = (0..<min(eggVertexLimit, p.count)).map { p[$0].y }.max() ?? 0
        capIndices = (0..<min(eggVertexLimit, p.count)).filter { p[$0].y > eggTop - 0.16 }
        var mn = SIMD3<Float>(repeating: .infinity), mx = SIMD3<Float>(repeating: -.infinity)
        for tr in t { for k in 0..<3 { let q = p[Int(tr[k])]; mn = simd_min(mn, q); mx = simd_max(mx, q) } }
        lo = mn - 0.05
        let d = simd_max(SIMD3<Float>(repeating: 1), ((mx + 0.05 - lo) / cell).rounded(.up))
        dim = SIMD3(Int(d.x), Int(d.y), Int(d.z))
        grid = [[Int32]](repeating: [], count: dim.x * dim.y * dim.z)
        for (ti, tr) in t.enumerated() {
            let a = p[Int(tr.x)], b = p[Int(tr.y)], c = p[Int(tr.z)]
            let tlo = simd_min(a, simd_min(b, c)), thi = simd_max(a, simd_max(b, c))
            let i0 = cellIndex(tlo), i1 = cellIndex(thi)
            for z in i0.z...i1.z { for y in i0.y...i1.y { for x in i0.x...i1.x { grid[(z * dim.y + y) * dim.x + x].append(Int32(ti)) } } }
        }
    }

    private func cellIndex(_ q: SIMD3<Float>) -> SIMD3<Int> {
        let f = ((q - lo) / cell).rounded(.down)
        return SIMD3(min(max(Int(f.x), 0), dim.x - 1), min(max(Int(f.y), 0), dim.y - 1), min(max(Int(f.z), 0), dim.z - 1))
    }

    /// Closest point of triangle (a, b, c) to p: barycentric (Ericson, Real-Time Collision Detection).
    static func closest(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return SIMD3(1, 0, 0) }
        let bp = p - b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return SIMD3(0, 1, 0) }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 { let v = d1 / (d1 - d3); return SIMD3(1 - v, v, 0) }
        let cp = p - c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return SIMD3(0, 0, 1) }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 { let w = d2 / (d2 - d6); return SIMD3(1 - w, 0, w) }
        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 { let w = (d4 - d3) / ((d4 - d3) + (d5 - d6)); return SIMD3(0, 1 - w, w) }
        let den = 1 / (va + vb + vc)
        let v = vb * den, w = vc * den
        return SIMD3(1 - v - w, v, w)
    }

    /// The smooth frame of a triangle given its three (current or rest) positions and the three vertex normals and barycentrics.
    @inline(__always)
    static func frame(_ pa: SIMD3<Float>, _ pb: SIMD3<Float>, _ na: SIMD3<Float>, _ nb: SIMD3<Float>, _ nc: SIMD3<Float>, _ w: SIMD3<Float>)
        -> (t: SIMD3<Float>, b: SIMD3<Float>, n: SIMD3<Float>) {
        var n = na * w.x + nb * w.y + nc * w.z
        let l = simd_length(n)
        n = l > 1e-9 ? n / l : SIMD3(0, 1, 0)
        var t = pb - pa
        t -= n * simd_dot(t, n)
        let tl = simd_length(t)
        t = tl > 1e-9 ? t / tl : simd_normalize(simd_cross(n, SIMD3(0, 1, 0.001)))
        return (t, simd_cross(n, t), n)
    }

    /// Binds a rest-space point to the egg surface (nil only if the mesh has no triangles).
    func bind(_ p: SIMD3<Float>) -> SurfaceBind? {
        guard !tris.isEmpty else { return nil }
        let c0 = cellIndex(p)
        var best = Float.infinity, bestT = -1, bestW = SIMD3<Float>.zero
        bindLock.lock(); defer { bindLock.unlock() }
        stampGen &+= 1
        if stampGen == 0 { for i in stamp.indices { stamp[i] = 0 }; stampGen = 1 }
        let gen = stampGen
        var r = 0
        while r <= 14 {
            for z in max(c0.z - r, 0)...min(c0.z + r, dim.z - 1) {
                for y in max(c0.y - r, 0)...min(c0.y + r, dim.y - 1) {
                    for x in max(c0.x - r, 0)...min(c0.x + r, dim.x - 1) {
                        if r > 0, abs(x - c0.x) != r, abs(y - c0.y) != r, abs(z - c0.z) != r { continue }       // the shell of cells only
                        for ti in grid[(z * dim.y + y) * dim.x + x] where stamp[Int(ti)] != gen {
                            stamp[Int(ti)] = gen
                            let tr = tris[Int(ti)]
                            let a = pos[Int(tr.x)], b = pos[Int(tr.y)], c = pos[Int(tr.z)]
                            let w = Self.closest(p, a, b, c)
                            let q = a * w.x + b * w.y + c * w.z
                            let d = simd_distance_squared(p, q)
                            if d < best { best = d; bestT = Int(ti); bestW = w }
                        }
                    }
                }
            }
            if bestT >= 0, best.squareRoot() <= Float(r) * cell { break }
            r += 1
        }
        guard bestT >= 0 else { return nil }
        let tr = tris[bestT]
        let a = pos[Int(tr.x)], b = pos[Int(tr.y)], c = pos[Int(tr.z)]
        let q = a * bestW.x + b * bestW.y + c * bestW.z
        let f = Self.frame(a, b, nrm[Int(tr.x)], nrm[Int(tr.y)], nrm[Int(tr.z)], bestW)
        let d = p - q
        return SurfaceBind(tri: tr, bary: bestW, off: SIMD3(simd_dot(d, f.t), simd_dot(d, f.b), simd_dot(d, f.n)))
    }

    /// The original `bind` (a fresh Set per call): kept for the bit-identical comparison test.
    func bindLegacy(_ p: SIMD3<Float>) -> SurfaceBind? {
        guard !tris.isEmpty else { return nil }
        let c0 = cellIndex(p)
        var best = Float.infinity, bestT = -1, bestW = SIMD3<Float>.zero
        var seen = Set<Int32>()
        var r = 0
        while r <= 14 {
            for z in max(c0.z - r, 0)...min(c0.z + r, dim.z - 1) {
                for y in max(c0.y - r, 0)...min(c0.y + r, dim.y - 1) {
                    for x in max(c0.x - r, 0)...min(c0.x + r, dim.x - 1) {
                        if r > 0, abs(x - c0.x) != r, abs(y - c0.y) != r, abs(z - c0.z) != r { continue }       // the shell of cells only
                        for ti in grid[(z * dim.y + y) * dim.x + x] where seen.insert(ti).inserted {
                            let tr = tris[Int(ti)]
                            let a = pos[Int(tr.x)], b = pos[Int(tr.y)], c = pos[Int(tr.z)]
                            let w = Self.closest(p, a, b, c)
                            let q = a * w.x + b * w.y + c * w.z
                            let d = simd_distance_squared(p, q)
                            if d < best { best = d; bestT = Int(ti); bestW = w }
                        }
                    }
                }
            }
            if bestT >= 0, best.squareRoot() <= Float(r) * cell { break }
            r += 1
        }
        guard bestT >= 0 else { return nil }
        let tr = tris[bestT]
        let a = pos[Int(tr.x)], b = pos[Int(tr.y)], c = pos[Int(tr.z)]
        let q = a * bestW.x + b * bestW.y + c * bestW.z
        let f = Self.frame(a, b, nrm[Int(tr.x)], nrm[Int(tr.y)], nrm[Int(tr.z)], bestW)
        let d = p - q
        return SurfaceBind(tri: tr, bary: bestW, off: SIMD3(simd_dot(d, f.t), simd_dot(d, f.b), simd_dot(d, f.n)))
    }

    /// The bound point in the REST pose (a check: it must land on the authored position).
    func restPoint(_ s: SurfaceBind) -> SIMD3<Float> {
        let a = pos[Int(s.tri.x)], b = pos[Int(s.tri.y)], c = pos[Int(s.tri.z)]
        let q = a * s.bary.x + b * s.bary.y + c * s.bary.z
        let f = Self.frame(a, b, nrm[Int(s.tri.x)], nrm[Int(s.tri.y)], nrm[Int(s.tri.z)], s.bary)
        return q + f.t * s.off.x + f.b * s.off.y + f.n * s.off.z
    }

    /// The bound point on a skinned body: `skin` = 6 floats per render vertex (position, smooth normal), as the CPU skinner writes them.
    @inline(__always)
    static func world(_ s: SurfaceBind, skin: UnsafePointer<Float>) -> SIMD3<Float> {
        @inline(__always) func P(_ i: UInt32) -> SIMD3<Float> { let o = 6 * Int(i); return SIMD3(skin[o], skin[o + 1], skin[o + 2]) }
        @inline(__always) func N(_ i: UInt32) -> SIMD3<Float> { let o = 6 * Int(i); return SIMD3(skin[o + 3], skin[o + 4], skin[o + 5]) }
        let a = P(s.tri.x), b = P(s.tri.y), c = P(s.tri.z)
        let q = a * s.bary.x + b * s.bary.y + c * s.bary.z
        let f = frame(a, b, N(s.tri.x), N(s.tri.y), N(s.tri.z), s.bary)
        return q + f.t * s.off.x + f.b * s.off.y + f.n * s.off.z
    }
    /// The bound point and the wall's normal there (the skin's smooth normal at the foot point).
    @inline(__always)
    static func worldWithNormal(_ s: SurfaceBind, skin: UnsafePointer<Float>) -> (p: SIMD3<Float>, n: SIMD3<Float>) {
        @inline(__always) func P(_ i: UInt32) -> SIMD3<Float> { let o = 6 * Int(i); return SIMD3(skin[o], skin[o + 1], skin[o + 2]) }
        @inline(__always) func N(_ i: UInt32) -> SIMD3<Float> { let o = 6 * Int(i); return SIMD3(skin[o + 3], skin[o + 4], skin[o + 5]) }
        let a = P(s.tri.x), b = P(s.tri.y), c = P(s.tri.z)
        let q = a * s.bary.x + b * s.bary.y + c * s.bary.z
        let f = frame(a, b, N(s.tri.x), N(s.tri.y), N(s.tri.z), s.bary)
        return (q + f.t * s.off.x + f.b * s.off.y + f.n * s.off.z, f.n)
    }
    /// Where the radial line at height `y` and azimuth direction `dir` (x, z about the body axis) meets the REST egg: the bind of that surface point and its radius. nil if the line misses the egg.
    /// FAST: the line is intersected directly with the egg's triangles (bucketed by azimuth and height, built on first use); when it crosses the egg exactly once between the old bracket
    /// (0.02 ... 1.2) that crossing is the answer. Anything else (a miss, a line that grazes or crosses more than once, a degenerate hit) takes the old bisection (`radialHitBisect`).
    func radialHit(dir: SIMD2<Float>, y: Float) -> (bind: SurfaceBind, rho: Float)? {
        if !Self.useBisection, let t = singleCrossing(dir: dir, y: y), var out = bind(SIMD3(dir.x * t, y, axisZ + dir.y * t)) {
            out.off = .zero
            Self.radialFast += 1
            return (out, t)
        }
        Self.radialFallback += 1
        return radialHitBisect(dir: dir, y: y)
    }
    /// Counters (tests / the report): how many queries took the direct path and how many fell back to the bisection.
    nonisolated(unsafe) static var radialFast = 0, radialFallback = 0
    /// Test / before-after aid: `-WearRadialOld 1` (or setting this) switches the direct intersection off, so every query takes the old bisection.
    nonisolated(unsafe) static var useBisection = UserDefaults.standard.object(forKey: "WearRadialOld") != nil
    /// The original: brackets [0.02, 1.2] along the line and bisects 16 times on the sign of the surface offset (19 nearest-triangle searches).
    func radialHitBisect(dir: SIMD2<Float>, y: Float) -> (bind: SurfaceBind, rho: Float)? {
        func at(_ r: Float) -> SurfaceBind? { bind(SIMD3(dir.x * r, y, axisZ + dir.y * r)) }
        var lo: Float = 0.02, hi: Float = 1.2
        guard let a = at(lo), a.off.z < 0, let b = at(hi), b.off.z > 0 else { return nil }
        for _ in 0..<16 { let m = (lo + hi) / 2; if let t = at(m), t.off.z < 0 { lo = m } else { hi = m } }
        let r = (lo + hi) / 2
        guard var out = at(r) else { return nil }
        out.off = .zero
        return (out, r)
    }

    // MARK: ray buckets

    /// The egg's triangles bucketed by azimuth (about the body axis) and height, for the radial-line queries.
    private struct RayBuckets {
        static let azBins = 90, yBins = 120
        var y0: Float = 0, dy: Float = 1
        var cells: [[Int32]] = []
        var a: [SIMD3<Float>] = [], e1: [SIMD3<Float>] = [], e2: [SIMD3<Float>] = []
    }
    private let rayLock = NSLock()
    private var rayBuckets: RayBuckets?

    private func buckets() -> RayBuckets {
        rayLock.lock(); defer { rayLock.unlock() }
        if let r = rayBuckets { return r }
        var rb = RayBuckets()
        let nA = RayBuckets.azBins, nY = RayBuckets.yBins
        var ylo = Float.infinity, yhi = -Float.infinity
        for t in tris { for k in 0..<3 { let q = pos[Int(t[k])]; ylo = min(ylo, q.y); yhi = max(yhi, q.y) } }
        rb.y0 = ylo - 0.001; rb.dy = max((yhi - ylo + 0.002) / Float(nY), 1e-6)
        rb.cells = [[Int32]](repeating: [], count: nA * nY)
        rb.a.reserveCapacity(tris.count); rb.e1.reserveCapacity(tris.count); rb.e2.reserveCapacity(tris.count)
        let twoPi = 2 * Float.pi
        for (ti, t) in tris.enumerated() {
            let p0 = pos[Int(t.x)], p1 = pos[Int(t.y)], p2 = pos[Int(t.z)]
            rb.a.append(p0); rb.e1.append(p1 - p0); rb.e2.append(p2 - p0)
            // height range
            let b0 = max(Int(((min(p0.y, p1.y, p2.y) - rb.y0) / rb.dy).rounded(.down)) - 0, 0), b1 = min(Int(((max(p0.y, p1.y, p2.y) - rb.y0) / rb.dy).rounded(.down)) + 0, nY - 1)
            // azimuth range of the triangle's projection on the horizontal plane; all of it when the projection holds (or nearly holds) the axis
            let q0 = SIMD2(p0.x, p0.z - axisZ), q1 = SIMD2(p1.x, p1.z - axisZ), q2 = SIMD2(p2.x, p2.z - axisZ)
            func cross2(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
            let s0 = cross2(q1 - q0, -q0), s1 = cross2(q2 - q1, -q1), s2 = cross2(q0 - q2, -q2)
            let eps: Float = 1e-4
            let holdsAxis = (s0 >= -eps && s1 >= -eps && s2 >= -eps) || (s0 <= eps && s1 <= eps && s2 <= eps)
            let near = min(simd_length(q0), simd_length(q1), simd_length(q2)) < 1e-3
            var bins: [Int] = []
            if holdsAxis || near { bins = Array(0..<nA) } else {
                let a0 = atan2(q0.y, q0.x)
                func wrap(_ d: Float) -> Float { var x = d; while x > .pi { x -= twoPi }; while x < -.pi { x += twoPi }; return x }
                let d1 = wrap(atan2(q1.y, q1.x) - a0), d2 = wrap(atan2(q2.y, q2.x) - a0)
                let lo = a0 + min(0, d1, d2) - 0.002, hi = a0 + max(0, d1, d2) + 0.002
                let first = Int(((lo / twoPi) * Float(nA)).rounded(.down)), last = Int(((hi / twoPi) * Float(nA)).rounded(.down))
                for k in first...max(first, last) { bins.append(((k % nA) + nA) % nA) }
            }
            for b in Set(bins) { for yb in b0...max(b0, b1) { rb.cells[b * nY + yb].append(Int32(ti)) } }
        }
        rayBuckets = rb
        return rb
    }

    /// The one crossing of the radial line (origin on the body axis at height `y`, direction `dir`) with the rest egg between t = 0.02 and t = 1.2, or nil when the line crosses it
    /// any other number of times (or touches an edge ambiguously): the caller then takes the bisection.
    private func singleCrossing(dir: SIMD2<Float>, y: Float) -> Float? {
        guard !tris.isEmpty else { return nil }
        let rb = buckets()
        let nA = RayBuckets.azBins, nY = RayBuckets.yBins
        let yb = Int(((y - rb.y0) / rb.dy).rounded(.down))
        guard yb >= 0, yb < nY else { return nil }
        var u = atan2(dir.y, dir.x) / (2 * Float.pi); u -= u.rounded(.down)
        let ab = min(Int(u * Float(nA)), nA - 1)
        let D = SIMD3<Float>(dir.x, 0, dir.y), O = SIMD3<Float>(0, y, axisZ)
        var ts: [Float] = []
        for ti in rb.cells[ab * nY + yb] {
            let i = Int(ti)
            // Moller-Trumbore, two-sided, edges inclusive
            let e1 = rb.e1[i], e2 = rb.e2[i]
            let pv = simd_cross(D, e2)
            let det = simd_dot(e1, pv)
            guard abs(det) > 1e-12 else { continue }
            let inv = 1 / det
            let tv = O - rb.a[i]
            let uu = simd_dot(tv, pv) * inv
            guard uu >= -1e-5, uu <= 1 + 1e-5 else { continue }
            let qv = simd_cross(tv, e1)
            let vv = simd_dot(D, qv) * inv
            guard vv >= -1e-5, uu + vv <= 1 + 1e-5 else { continue }
            let t = simd_dot(e2, qv) * inv
            if t > 1e-4 { ts.append(t) }
        }
        ts.sort()
        var merged: [Float] = []                                          // (a line through a shared edge or vertex meets two triangles at one point)
        for t in ts { if let l = merged.last, t - l < 2e-4 { continue }; merged.append(t) }
        guard merged.count == 1, merged[0] > 0.02, merged[0] < 1.2 else { return nil }
        return merged[0]
    }
    /// The foot point of a bind on the REST egg (the surface point under a bound vertex, without its offset).
    func restFoot(_ s: SurfaceBind) -> SIMD3<Float> { pos[Int(s.tri.x)] * s.bary.x + pos[Int(s.tri.y)] * s.bary.y + pos[Int(s.tri.z)] * s.bary.z }
    /// The foot point of a bind on the skinned body (no frame, no offset).
    @inline(__always)
    static func footPoint(_ s: SurfaceBind, skin: UnsafePointer<Float>) -> SIMD3<Float> {
        @inline(__always) func P(_ i: UInt32) -> SIMD3<Float> { let o = 6 * Int(i); return SIMD3(skin[o], skin[o + 1], skin[o + 2]) }
        return P(s.tri.x) * s.bary.x + P(s.tri.y) * s.bary.y + P(s.tri.z) * s.bary.z
    }
    /// The bound point plus the skin's frame there (columns T, B, N) at the foot point.
    @inline(__always)
    static func worldFrame(_ s: SurfaceBind, skin: UnsafePointer<Float>) -> (p: SIMD3<Float>, frame: simd_float3x3) {
        @inline(__always) func P(_ i: UInt32) -> SIMD3<Float> { let o = 6 * Int(i); return SIMD3(skin[o], skin[o + 1], skin[o + 2]) }
        @inline(__always) func N(_ i: UInt32) -> SIMD3<Float> { let o = 6 * Int(i); return SIMD3(skin[o + 3], skin[o + 4], skin[o + 5]) }
        let a = P(s.tri.x), b = P(s.tri.y), c = P(s.tri.z)
        let q = a * s.bary.x + b * s.bary.y + c * s.bary.z
        let f = frame(a, b, N(s.tri.x), N(s.tri.y), N(s.tri.z), s.bary)
        return (q + f.t * s.off.x + f.b * s.off.y + f.n * s.off.z, simd_float3x3(columns: (f.t, f.b, f.n)))
    }
    /// The same on an array of posed positions and normals (tests).
    static func world(_ s: SurfaceBind, positions: [SIMD3<Float>], normals: [SIMD3<Float>]) -> SIMD3<Float> {
        let a = positions[Int(s.tri.x)], b = positions[Int(s.tri.y)], c = positions[Int(s.tri.z)]
        let q = a * s.bary.x + b * s.bary.y + c * s.bary.z
        let f = frame(a, b, normals[Int(s.tri.x)], normals[Int(s.tri.y)], normals[Int(s.tri.z)], s.bary)
        return q + f.t * s.off.x + f.b * s.off.y + f.n * s.off.z
    }
}
