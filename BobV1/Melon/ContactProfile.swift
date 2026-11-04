//
//  ContactProfile.swift
//  TOUCHING WITHOUT OVERLAPPING: the contact profile (2026-11-02, the user: "all touching emotes must look polished: touching, but never overlapping like a buggy game").
//
//  One profile per body per skin pass, built from the DRAWN skin (so a lying body that is 1.27 x wider, a lean, a squash, a breath, an arm out, Teddy's ears, Pip's tail are all in it):
//    polygon  the farthest skinned vertex of each of K = 128 direction bins around the body's ROOT (the floor position the room steers: `JellyActor.floor`), horizontal, relative to the root:
//             body skin + arms + feet + the blocks that ride the skin (Teddy's ears + pom, Pip's tail). Built inside `JellyParallel.skin` (parallel, one slice of `ContactField.store`
//             per body) from a sample of the vertices (every 3rd of the egg, every 2nd of the limb blocks: 24 k vertices, ~0.02 ms a body).
//    rho[k]   the RADIAL table: the ray cast of that polygon from the root along each bin centre: "how far does he reach along this direction" (`ext`), a 0.2 us lookup.
//    feature  the same polygon / table for FEATURE-only vertices (wings at their CURRENT fold, Moss's daisy, Pip's spikes): `FeatureSet.frame` fills it from the emitted meshes.
//  The pair metric (THE metric): the SKIN GAP = the distance the two bodies could still translate toward each other along their root axis before the drawn footprints touch
//  (the exact translation gap of the two polygons: lateral offsets, lying, leaning, arms, ears all in), + apart, - sunk in. `ContactField.gap`. An estimate for hot paths
//  (the keepApart wall, called hundreds of times a step) is `touch` = ext(a, dir) + ext(b, -dir) (the roots' rays only).
//  Everything that decides "are they touching" asks `ContactField`: the keepApart wall, the contact boop + haptic, the settle controller, the wing fold.
//  See docs/HANDOFF.md ("Touching without overlapping: the contact profile").
//

import Foundation
import simd

nonisolated enum ContactField {
    static let K = 128
    static let capacity = 16
    /// Per body (floats): rho[K], frho[K], bx[K], bz[K], br2[K] (body polygon; br2 <= 0 = empty bin), fx[K], fz[K], fr2[K] (feature polygon), then rootX, rootZ, valid, featValid, stamp.
    static let stride = 8 * K + 5
    private static let oRho = 0, oFRho = K, oBX = 2 * K, oBZ = 3 * K, oBR = 4 * K, oFX = 5 * K, oFZ = 6 * K, oFR = 7 * K, oMeta = 8 * K
    nonisolated(unsafe) static let store: UnsafeMutablePointer<Float> = {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: capacity * stride)
        p.initialize(repeating: 0, count: capacity * stride)
        return p
    }()
    /// Pip's tail as a FEATURE (2026-11-03): its farthest vertex per bin (r2, x, z) kept apart from the body profile and merged into the feature bins, so `gap(features: true)` and the keepApart wall see it.
    nonisolated(unsafe) static let tailBuf: UnsafeMutablePointer<Float> = {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: capacity * 3 * K); p.initialize(repeating: -1, count: capacity * 3 * K); return p
    }()
    nonisolated(unsafe) static let tailState: UnsafeMutablePointer<Float> = {          // per body: 1 = the tail is drawn and in tailBuf, 2 = a feature mesh owns the feature bins (the tail is merged after it)
        let p = UnsafeMutablePointer<Float>.allocate(capacity: capacity); p.initialize(repeating: 0, count: capacity); return p
    }()
    nonisolated(unsafe) static let tailDrawn: UnsafeMutablePointer<Float> = {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: capacity); p.initialize(repeating: 0, count: capacity); return p
    }()
    /// false = no profile is ever read (the legacy centre-distance rules).
    nonisolated(unsafe) static var enabled = true
    /// Vertex count of the egg proper (the limb / ear / tail blocks come after it): the egg is sampled more sparsely than the limbs.
    nonisolated(unsafe) static var eggLimit = Int.max
    /// Pip's tail block: NOT part of the body profile (a tail that holds two bodies a hand apart is not what "touching" means; it is a feature: FeatureClip pushes it out of the neighbour).
    nonisolated(unsafe) static var tailLo = Int.max, tailHi = Int.max
    static func configure(eggLimit n: Int, tail: Range<Int>? = nil, index: [UInt32]? = nil) {
        eggLimit = n; tailLo = tail?.lowerBound ?? Int.max; tailHi = tail?.upperBound ?? Int.max
        if let index { buildNeighbours(index) }
    }
    nonisolated(unsafe) static var eggStride = 6, limbStride = 3
    /// REFINE (2026-11-03): after the strided pass, each bin's winning vertex and its mesh neighbours (1-ring, then again around the bins that moved) are tested too, so a thin lobe whose tip
    /// vertex fell between the samples is still found (the stride-3 pass alone missed vertices by up to 5.6 mm in a lean). 0 = off.
    nonisolated(unsafe) static var refinePasses = 2
    /// Vertex adjacency (CSR over the triangles of the render mesh): neighbours of v are nbr[nbrStart[v] ..< nbrStart[v + 1]].
    nonisolated(unsafe) private static var nbrStart: UnsafeMutablePointer<Int32>? = nil
    nonisolated(unsafe) private static var nbr: UnsafeMutablePointer<Int32>? = nil
    nonisolated(unsafe) private static var nbrCount = 0
    nonisolated(unsafe) private static var nbrKey = -1
    private static func buildNeighbours(_ index: [UInt32]) {
        guard index.count != nbrKey else { return }
        var n = 0
        for v in index { n = max(n, Int(v) + 1) }
        var lists = [[Int32]](repeating: [], count: n)
        var t = 0
        while t + 2 < index.count {
            let a = Int(index[t]), b = Int(index[t + 1]), c = Int(index[t + 2]); t += 3
            for (x, y) in [(a, b), (b, c), (c, a)] {
                if !lists[x].contains(Int32(y)) { lists[x].append(Int32(y)) }
                if !lists[y].contains(Int32(x)) { lists[y].append(Int32(x)) }
            }
        }
        let total = lists.reduce(0) { $0 + $1.count }
        let st = UnsafeMutablePointer<Int32>.allocate(capacity: n + 1), nb = UnsafeMutablePointer<Int32>.allocate(capacity: max(total, 1))
        var o = 0
        for v in 0..<n { st[v] = Int32(o); for w in lists[v] { nb[o] = w; o += 1 } }
        st[n] = Int32(o)
        nbrStart?.deallocate(); nbr?.deallocate()
        nbrStart = st; nbr = nb; nbrCount = n; nbrKey = index.count
    }

    // MARK: layout
    @inline(__always) private static func base(_ id: Int) -> UnsafeMutablePointer<Float> { store + id * stride }

    /// Forget every profile (tests, a scene change).
    static func reset() { store.initialize(repeating: 0, count: capacity * stride); tailBuf.initialize(repeating: -1, count: capacity * 3 * K); tailState.initialize(repeating: 0, count: capacity); tailDrawn.initialize(repeating: 0, count: capacity); gapStamp = [Int](repeating: -1, count: capacity * capacity) }
    static func invalidate(_ id: Int) { if id >= 0, id < capacity { base(id)[oMeta + 2] = 0; base(id)[oMeta + 3] = 0 } }
    static func isValid(_ id: Int) -> Bool { id >= 0 && id < capacity && base(id)[oMeta + 2] > 0.5 }
    /// How many times body `id`'s profile was built (a controller acts once per fresh profile).
    static func stamp(_ id: Int) -> Int { id >= 0 && id < capacity ? Int(base(id)[oMeta + 4]) : 0 }
    static func root(_ id: Int) -> SIMD2<Float> { let b = base(id); return SIMD2(b[oMeta], b[oMeta + 1]) }

    // MARK: angles
    /// pseudo-angle 0..4 of (x, z): monotonic in the true angle, no trig.
    @inline(__always) private static func pseudo(_ x: Float, _ z: Float) -> Float {
        let p = x / (abs(x) + abs(z))
        return z < 0 ? 3 + p : 1 - p
    }
    private static let tableN = 4096
    /// pseudo-angle slot -> bin (a slot is 4/4096 of pseudo-angle: <= 0.1 degree).
    private static let binOfSlot: [UInt8] = {
        var t = [UInt8](repeating: 0, count: tableN + 1)
        for s in 0...tableN {
            let pa = (Float(s) + 0.5) * 4 / Float(tableN)
            // invert pseudo(): z >= 0: pa = 1 - p, p = x / (|x| + |z|) -> x = p, z = 1 - |p|;  z < 0: pa = 3 + p -> x = p, z = -(1 - |p|)
            let p: Float, z: Float
            if pa < 2 { p = 1 - pa; z = 1 - abs(p) } else { p = pa - 3; z = -(1 - abs(p)) }
            let ang = atan2f(z, p)
            t[s] = UInt8(min(max(Int((ang + .pi) * (Float(K) / (2 * .pi))), 0), K - 1))          // (K = 128 fits a byte)
        }
        return t
    }()
    @inline(__always) static func angle(_ z: Float, _ x: Float) -> Float {
        let ax = abs(x), az = abs(z)
        let mx = max(ax, az), mn = min(ax, az)
        guard mx > 0 else { return 0 }
        let a = mn / mx, s = a * a
        var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a
        if az > ax { r = .pi / 2 - r }
        if x < 0 { r = .pi - r }
        return z < 0 ? -r : r
    }
    private static let cosT: [Float] = (0..<K).map { cosf((Float($0) + 0.5) * 2 * .pi / Float(K) - .pi) }
    private static let sinT: [Float] = (0..<K).map { sinf((Float($0) + 0.5) * 2 * .pi / Float(K) - .pi) }

    // MARK: build
    /// The body's profile from its skinned stream (`dyn`: 6 floats a vertex, `count` vertices), relative to `root`. Runs on a worker thread: touches only body `id`'s slice.
    static func build(id: Int, dyn: UnsafePointer<Float>, count: Int, root: SIMD2<Float>, blocks: [Range<Int>]? = nil) {
        guard id >= 0, id < capacity else { return }
        let b = base(id)
        let r2 = b + oBR, px = b + oBX, pz = b + oBZ
        for k in 0..<K { r2[k] = -1 }
        let lim = min(eggLimit, count)
        let passes = nbr != nil ? refinePasses : 0
        withUnsafeTemporaryAllocation(of: Int32.self, capacity: 3 * K) { wbuf in
        let win = wbuf.baseAddress!, cur = win + K, nxt = win + 2 * K
        binOfSlot.withUnsafeBufferPointer { tb in
            @inline(__always) func add(_ i: Int) {
                let o = 6 * i
                let x = dyn[o] - root.x, z = dyn[o + 2] - root.y
                let q = x * x + z * z
                guard q > 1e-6, q < 25 else { return }          // (a NaN fails both)
                let slot = Int(pseudo(x, z) * (Float(tableN) / 4))
                let k = Int(tb[min(max(slot, 0), tableN)])
                if q > r2[k] { r2[k] = q; px[k] = x; pz[k] = z; win[k] = Int32(i) }
            }
            var i = 0
            while i < lim { add(i); i += eggStride }
            // the limb / ear blocks that are DRAWN (an inactive block is parked out of sight: it must not count; `blocks` nil = everything after the egg)
            for r in blocks ?? [lim..<count] {
                i = max(r.lowerBound, lim)
                let hi = min(r.upperBound, count)
                while i < hi {
                    if i >= tailLo, i < tailHi { i = tailHi; continue }          // (the tail is a feature)
                    add(i); i += limbStride
                }
            }
            if passes > 0, let ns = nbrStart, let nb = nbr {
                for k in 0..<K { cur[k] = r2[k] > 0 ? 1 : 0 }          // round 1: every filled bin; later rounds: only the bins a neighbour improved
                for _ in 0..<passes {
                    for k in 0..<K { nxt[k] = 0 }
                    for k in 0..<K where cur[k] != 0 {
                        let v = Int(win[k])
                        guard v < nbrCount else { continue }
                        for e in Int(ns[v])..<Int(ns[v + 1]) {
                            let w = Int(nb[e])
                            if w >= count || (w >= tailLo && w < tailHi) { continue }
                            let o = 6 * w
                            let x = dyn[o] - root.x, z = dyn[o + 2] - root.y
                            let q = x * x + z * z
                            guard q > 1e-6, q < 25 else { continue }
                            let slot = Int(pseudo(x, z) * (Float(tableN) / 4))
                            let kk = Int(tb[min(max(slot, 0), tableN)])
                            if q > r2[kk] { r2[kk] = q; px[kk] = x; pz[kk] = z; win[kk] = Int32(w); nxt[kk] = 1 }
                        }
                    }
                    for k in 0..<K { cur[k] = nxt[k] }
                }
            }
        }
        }
        // the tail (a feature): its farthest vertex per bin, when the tail block is drawn
        let tb = tailBuf + id * 3 * K
        var drawn = false
        if tailLo < tailHi {
            for r in blocks ?? [lim..<count] where r.lowerBound < tailHi && r.upperBound > tailLo { drawn = true }
        }
        tailDrawn[id] = drawn ? 1 : 0
        if drawn {
            for k in 0..<K { tb[k] = -1 }
            binOfSlot.withUnsafeBufferPointer { tbl in
                var i = max(tailLo, 0)
                let hi = min(tailHi, count)
                while i < hi {
                    let o = 6 * i
                    let x = dyn[o] - root.x, z = dyn[o + 2] - root.y
                    let q = x * x + z * z
                    if q > 1e-6, q < 25 {
                        let slot = Int(pseudo(x, z) * (Float(tableN) / 4))
                        let k = Int(tbl[min(max(slot, 0), tableN)])
                        if q > tb[k] { tb[k] = q; tb[K + k] = x; tb[2 * K + k] = z }
                    }
                    i += 2
                }
            }
        }
        castTable(r2, px, pz, into: b + oRho, fallback: true)
        if drawn {
            if tailState[id] < 1.5 { mergeTail(id) }          // (a body with no feature mesh: the tail is its whole feature polygon)
            else { tailState[id] = 2 }
        } else if tailState[id] > 0.5 && tailState[id] < 1.5 { clearFeature(id: id); tailState[id] = 0 }
        b[oMeta] = root.x; b[oMeta + 1] = root.y
        b[oMeta + 2] = 1
        b[oMeta + 4] += 1
    }

    /// Merges the stored tail points into the feature bins of body `id` (max per bin). The tail counts as a feature from then on.
    static func mergeTail(_ id: Int) {
        let b = base(id), tb = tailBuf + id * 3 * K
        let r2 = b + oFR, px = b + oFX, pz = b + oFZ
        if tailState[id] < 1.5 { for k in 0..<K { r2[k] = -1 }; tailState[id] = 1 }
        for k in 0..<K where tb[k] > r2[k] { r2[k] = tb[k]; px[k] = tb[K + k]; pz[k] = tb[2 * K + k] }
        b[oMeta + 3] = 1
    }

    /// A feature's profile (wings, spikes, daisy) from its emitted world vertices: `position` yields the world position of each. Main thread, after the skin.
    static func buildFeature(id: Int, count: Int, position: (Int) -> SIMD3<Float>) {
        guard id >= 0, id < capacity, isValid(id) else { return }
        let b = base(id)
        let root = SIMD2(b[oMeta], b[oMeta + 1])
        let r2 = b + oFR, px = b + oFX, pz = b + oFZ
        for k in 0..<K { r2[k] = -1 }
        for i in 0..<count {
            let p = position(i)
            let x = p.x - root.x, z = p.z - root.y
            let q = x * x + z * z
            guard q > 1e-6, q < 25 else { continue }
            let slot = Int(pseudo(x, z) * (Float(tableN) / 4))
            let k = Int(binOfSlot[min(max(slot, 0), tableN)])
            if q > r2[k] { r2[k] = q; px[k] = x; pz[k] = z }
        }
        b[oMeta + 3] = 1
        tailState[id] = 2          // (a feature mesh owns the bins)
        if tailDrawn[id] > 0.5 {          // ... and the drawn tail joins it
            let tb = tailBuf + id * 3 * K
            for k in 0..<K where tb[k] > r2[k] { r2[k] = tb[k]; px[k] = tb[K + k]; pz[k] = tb[2 * K + k] }
        }
    }
    static func clearFeature(id: Int) {
        guard id >= 0, id < capacity else { return }
        let b = base(id)
        for k in 0..<K { b[oFRho + k] = 0; b[oFR + k] = -1 }
        b[oMeta + 3] = 0
    }

    /// The ray cast of the polygon through the per-bin farthest vertices, from the origin, along each bin centre.
    private static func castTable(_ r2: UnsafeMutablePointer<Float>, _ px: UnsafeMutablePointer<Float>, _ pz: UnsafeMutablePointer<Float>, into out: UnsafeMutablePointer<Float>, fallback: Bool) {
        for k in 0..<K {
            let dx = cosT[k], dz = sinT[k]
            var best: Float = 0
            // edges between the points of the bins around this one (the ray lies between the two points whose directions straddle it)
            for j in (k - 3)...(k + 2) {
                let a = (j + K) % K, c = (j + 1 + K) % K
                guard r2[a] > 0, r2[c] > 0 else { continue }
                let ax = px[a], az = pz[a], ex = px[c] - ax, ez = pz[c] - az
                let denom = dx * ez - dz * ex
                if abs(denom) < 1e-9 { continue }
                let t = (ax * ez - az * ex) / denom
                let u = (ax * dz - az * dx) / denom
                if t > 0, u >= -1e-4, u <= 1 + 1e-4, t > best { best = t }
            }
            if best <= 0, fallback {          // (a sparse ring: the nearest filled bin's own radius; a feature has no reach where it has no vertices)
                var d = 1
                while d < K / 2, best <= 0 {
                    for s in [k - d, k + d] { let q = (s + K) % K; if r2[q] > 0 { best = max(best, r2[q].squareRoot()) } }
                    d += 1
                }
            }
            out[k] = best
        }
    }

    // MARK: queries (radial)
    @inline(__always) private static func sample(_ t: UnsafeMutablePointer<Float>, _ dir: SIMD2<Float>) -> Float {
        let theta = angle(dir.y, dir.x)
        let u = (theta + .pi) * (Float(K) / (2 * .pi)) - 0.5
        let f = floorf(u)
        let i0 = ((Int(f) % K) + K) % K, i1 = (i0 + 1) % K, w = u - f
        return t[i0] * (1 - w) + t[i1] * w
    }
    /// How far body `id` reaches from its root along the unit horizontal `dir` (body skin, limbs, ears, tail; + the features when asked). nil = no profile.
    static func ext(_ id: Int, _ dir: SIMD2<Float>, features: Bool = false) -> Float? {
        guard enabled, isValid(id) else { return nil }
        let b = base(id)
        let e = sample(b + oRho, dir)
        guard features, b[oMeta + 3] > 0.5 else { return e }
        return max(e, featureExt(id, dir))
    }
    /// How far the FEATURES (wings, spikes, daisy) reach from the root along the unit `dir`: the farthest feature point within a corridor of +-10 cm of the ray (a wing is thin: the radial
    /// ray cast would miss it). 0 where there is none.
    static func featureExt(_ id: Int, _ dir: SIMD2<Float>) -> Float {
        guard enabled, isValid(id), base(id)[oMeta + 3] > 0.5 else { return 0 }
        let b = base(id)
        var best: Float = 0
        for k in 0..<K where b[oFR + k] > 0 {
            let x = b[oFX + k], z = b[oFZ + k]
            let along = x * dir.x + z * dir.y
            if along > best, abs(x * dir.y - z * dir.x) <= 0.10 { best = along }
        }
        return best
    }
    /// The feature points (wings, spikes, daisy: the farthest vertex of each direction bin) relative to the owner's root.
    static func featurePoints(_ id: Int) -> [SIMD2<Float>] {
        guard enabled, isValid(id), base(id)[oMeta + 3] > 0.5 else { return [] }
        let b = base(id)
        var r: [SIMD2<Float>] = []
        for k in 0..<K where b[oFR + k] > 0 { r.append(SIMD2(b[oFX + k], b[oFZ + k])) }
        return r
    }
    /// How far (u, + clear, - inside) the nearest of `points` (relative to `ownerRoot`) is from body `j`'s skin footprint (the radial table: a few mm). nil = no profile.
    static func clearance(of points: [SIMD2<Float>], ownerRoot: SIMD2<Float>, against j: Int) -> Float? {
        guard enabled, isValid(j) else { return nil }
        let rj = root(j)
        var best = Float.infinity
        for p in points {
            let q = ownerRoot + p - rj, L = simd_length(q)
            if L < 1e-4 { return -1 }
            guard let e = ext(j, q / L) else { return nil }
            best = min(best, L - e)
        }
        return best.isFinite ? best : nil
    }

    /// The estimate for hot paths: the roots' rays only, ext(a, dir) + ext(b, -dir) (`dir` unit, from a to b).
    static func touch(_ a: Int, _ b: Int, dir: SIMD2<Float>, features: Bool = false) -> Float? {
        guard let ea = ext(a, dir, features: features), let eb = ext(b, -dir, features: features) else { return nil }
        return ea + eb
    }

    // MARK: the support metric (the catalogue's definition: BruteForceContactMetric.skinGap)
    /// How far body `id`'s drawn skin reaches along the unit horizontal `dir`, measured as the SUPPORT (the largest projection on `dir` of any skin point, relative to the root):
    /// the per-bin farthest vertices are the footprint's hull to 2.8 degrees, so this is the brute-force support to a mm. nil = no profile.
    static func supportExt(_ id: Int, _ dir: SIMD2<Float>) -> Float? {
        guard enabled, isValid(id) else { return nil }
        let b = base(id)
        var best = -Float.infinity
        for k in 0..<K where b[oBR + k] > 0 { best = max(best, b[oBX + k] * dir.x + b[oBZ + k] * dir.y) }
        return best.isFinite ? best : nil
    }
    /// The catalogue's touch distance: extA(u) + extB(-u) along the root axis u (support reaches), metres: the root distance at which the two skins' supports meet.
    static func touchDistance(_ a: Int, _ b: Int) -> Float? {
        guard enabled, isValid(a), isValid(b), a != b else { return nil }
        let d = root(b) - root(a), L = simd_length(d)
        let u = L > 1e-4 ? d / L : SIMD2<Float>(1, 0)
        guard let ea = supportExt(a, u), let eb = supportExt(b, -u) else { return nil }
        return ea + eb
    }
    /// The support touch distance along an EXPLICIT axis `u` (unit, from `a` toward `b`): extA(u) + extB(-u). Use it at a STANDING moment (both planted) for a distance that does not swing with the steps
    /// (the live profile includes a swinging leg / arm: 0.39 ... 1.6 m on the same axis during a walk). nil = no profile for one of them.
    static func touchDistance(_ a: Int, _ b: Int, dir u: SIMD2<Float>) -> Float? {
        guard enabled, isValid(a), isValid(b), a != b, let ea = supportExt(a, u), let eb = supportExt(b, -u) else { return nil }
        return ea + eb
    }
    /// The catalogue's skin gap: root distance - touchDistance (metres; + apart, - the supports overlap). Agrees with `BruteForceContactMetric.skinGap` to a few mm (ContactProfileTests).
    /// It is a lower bound of `gap` (the supports can overlap where the footprints do not: two lying bodies whose farthest points sit side by side); decisions use `gap`.
    static func skinGap(_ a: Int, _ b: Int) -> Float? {
        guard let t = touchDistance(a, b) else { return nil }
        return simd_distance(root(a), root(b)) - t
    }

    // MARK: the pair gap (exact translation gap of the two footprints)
    nonisolated(unsafe) private static var gapStamp = [Int](repeating: -1, count: capacity * capacity)
    nonisolated(unsafe) private static var gapValue = [Float](repeating: 0, count: capacity * capacity)

    /// THE pair metric: the distance the two bodies could still slide toward each other along their root axis before the drawn footprints touch. + apart, - sunk into each other,
    /// on the roots the profiles were built at. nil = no profile for one of them (or the footprints do not face each other). Main thread; cached per pair of profile stamps.
    static func gap(_ a: Int, _ b: Int, features: Bool = false) -> Float? {
        guard enabled, isValid(a), isValid(b), a != b else { return nil }
        let lo = min(a, b), hi = max(a, b)
        let key = lo * capacity + hi
        let st = stamp(lo) &* 100_003 &+ stamp(hi) &+ (features ? 1 : 0) &* 7
        if gapStamp[key] == st { let v = gapValue[key]; return v.isNaN ? nil : v }
        let d = root(hi) - root(lo), L = simd_length(d)
        var best = Float.infinity
        if L > 1e-4 {
            let u = d / L
            best = polyGap(lo, hi, L, u, bodyA: true, bodyB: true)
            if features {
                if base(lo)[oMeta + 3] > 0.5 { best = min(best, polyGap(lo, hi, L, u, bodyA: false, bodyB: true)) }
                if base(hi)[oMeta + 3] > 0.5 { best = min(best, polyGap(lo, hi, L, u, bodyA: true, bodyB: false)) }
                if base(lo)[oMeta + 3] > 0.5, base(hi)[oMeta + 3] > 0.5 { best = min(best, polyGap(lo, hi, L, u, bodyA: false, bodyB: false)) }
            }
        }
        let v: Float = best.isFinite ? best : .nan
        gapStamp[key] = st; gapValue[key] = v
        return best.isFinite ? best : nil
    }

    /// The pair gap for hypothetical roots (a candidate position, a steering probe): body `a` with its root at `pa`, body `b` at `pb`. Not cached (~3 us): call it only for a pair that is near.
    static func gap(_ a: Int, at pa: SIMD2<Float>, _ b: Int, at pb: SIMD2<Float>, features: Bool = false, support: Bool = false) -> Float? {
        guard enabled, isValid(a), isValid(b), a != b else { return nil }
        let d = pb - pa, L = simd_length(d)
        guard L > 1e-4 else { return nil }
        let u = d / L
        var g = polyGap(a, b, L, u, bodyA: true, bodyB: true)
        if features {          // a drawn wing / spike / daisy / tail is a surface too
            let fa = base(a)[oMeta + 3] > 0.5, fb = base(b)[oMeta + 3] > 0.5
            if fa { g = min(g, polyGap(a, b, L, u, bodyA: false, bodyB: true)) }
            if fb { g = min(g, polyGap(a, b, L, u, bodyA: true, bodyB: false)) }
            if fa, fb { g = min(g, polyGap(a, b, L, u, bodyA: false, bodyB: false)) }
        }
        if support, let ea = supportExt(a, u), let eb = supportExt(b, -u) { g = min(g, L - (ea + eb)) }          // (the catalogue's support gap, the stricter one when the bodies stand staggered: the harness's ground truth)
        return g.isFinite ? g : nil
    }

    /// The translation gap of polygon A (body `a`, at the origin) and polygon B (body `b`, `L` along `u`) along `u`: the smallest, over the lateral positions where both exist, of
    /// (B's nearest axial coordinate - A's farthest axial coordinate). The envelopes are piecewise linear: it is enough to look at the facing vertices of both.
    private static func polyGap(_ a: Int, _ b: Int, _ L: Float, _ u: SIMD2<Float>, bodyA: Bool, bodyB: Bool) -> Float {
        let g = polyGapEdges(a, b, L, u, bodyA: bodyA, bodyB: bodyB)
        // a feature (tail, wing, spike, daisy) against the other's BODY: its own vertices tested against the whole footprint, so a tip INSIDE the body always reads negative (2026-11-04: the edge
        // caps above need two neighbouring bins facing each other and a lateral overlap of the caps; a lone tail tip deep inside the body had neither and read +infinity).
        if bodyA != bodyB { return min(g, featurePointsGap(a, b, L, u, featureIsA: !bodyA)) }
        return g
    }

    /// The translation gap of body A's and body B's footprints along `u` where one of the two is a FEATURE polygon: per feature vertex, the body footprint's nearest (feature on A's side: it moves toward B)
    /// or farthest (feature on B's side) crossing at the vertex's lateral position, minus the vertex's axial coordinate. Negative = the vertex is inside / past the body. Only vertices that reach within
    /// 0.4 m of the body's near edge are tested (the edge pass covers the rest), so a clear pair costs one pass over the bins.
    private static func featurePointsGap(_ a: Int, _ b: Int, _ L: Float, _ u: SIMD2<Float>, featureIsA: Bool) -> Float {
        let v = SIMD2(-u.y, u.x)
        let pa = base(a), pb = base(b)
        let fo = featureIsA ? pa : pb, bo = featureIsA ? pb : pa
        let fOff: Float = featureIsA ? 0 : L, bOff: Float = featureIsA ? L : 0
        let fr = fo + oFR, fx = fo + oFX, fz = fo + oFZ
        let br = bo + oBR, bx = bo + oBX, bz = bo + oBZ
        var best = Float.infinity
        withUnsafeTemporaryAllocation(of: Float.self, capacity: 2 * K) { buf in
            let ax = buf.baseAddress!, lw = ax + K          // the body's axial / lateral per bin
            var near = Float.infinity, far = -Float.infinity
            for k in 0..<K where br[k] > 0 {
                ax[k] = bOff + bx[k] * u.x + bz[k] * u.y; lw[k] = bx[k] * v.x + bz[k] * v.y
                near = min(near, ax[k]); far = max(far, ax[k])
            }
            guard near.isFinite else { return }
            for k in 0..<K where fr[k] > 0 {
                let p = fOff + fx[k] * u.x + fz[k] * u.y, w = fx[k] * v.x + fz[k] * v.y
                if featureIsA ? (p < near - 0.4) : (p > far + 0.4) { continue }
                var cross: Float? = nil          // the body's nearest (feature on A) / farthest (feature on B) axial coordinate at lateral w
                for j in 0..<K {
                    let j2 = (j + 1) % K
                    guard br[j] > 0, br[j2] > 0 else { continue }
                    let w0 = lw[j], w1 = lw[j2]
                    if w < min(w0, w1) - 1e-5 || w > max(w0, w1) + 1e-5 { continue }
                    let dw = w1 - w0
                    let t: Float = abs(dw) < 1e-7 ? (featureIsA ? min(ax[j], ax[j2]) : max(ax[j], ax[j2])) : ax[j] + (ax[j2] - ax[j]) * ((w - w0) / dw)
                    if let c = cross { cross = featureIsA ? min(c, t) : max(c, t) } else { cross = t }
                }
                if let c = cross { best = min(best, featureIsA ? c - p : p - c) }
            }
        }
        return best
    }

    private static func polyGapEdges(_ a: Int, _ b: Int, _ L: Float, _ u: SIMD2<Float>, bodyA: Bool, bodyB: Bool) -> Float {
        let g = polyGapCap(a, b, L, u, bodyA: bodyA, bodyB: bodyB, reach: 0.4)
        if g.isFinite { return g }
        // (a deep overlap: the facing caps no longer pair up - widen them to the whole footprint so the gap stays a finite, signed number: 2026-11-04, the settle and the wall need it most when the overlap is deepest)
        guard bodyA && bodyB else { return g }          // (a feature that faces nothing - laterally disjoint from the other's skin - can never touch it: infinity is right)
        let g2 = polyGapCap(a, b, L, u, bodyA: bodyA, bodyB: bodyB, reach: 4)
        if g2.isFinite { return g2 }
        if let ea = supportExt(a, u), let eb = supportExt(b, -u) { return L - (ea + eb) }          // (last resort for the two bodies: the support gap, a lower bound)
        return g2
    }

    private static func polyGapCap(_ a: Int, _ b: Int, _ L: Float, _ u: SIMD2<Float>, bodyA: Bool, bodyB: Bool, reach: Float) -> Float {
        let v = SIMD2(-u.y, u.x)
        let pa = base(a), pb = base(b)
        let ar = bodyA ? pa + oBR : pa + oFR, ax = bodyA ? pa + oBX : pa + oFX, az = bodyA ? pa + oBZ : pa + oFZ
        let br = bodyB ? pb + oBR : pb + oFR, bx = bodyB ? pb + oBX : pb + oFX, bz = bodyB ? pb + oBZ : pb + oFZ
        var best = Float.infinity
        withUnsafeTemporaryAllocation(of: Float.self, capacity: 4 * K) { buf in
            let aA = buf.baseAddress!, wA = aA + K, aB = aA + 2 * K, wB = aA + 3 * K
            var maxA = -Float.infinity, minB = Float.infinity
            for k in 0..<K {
                if ar[k] > 0 { aA[k] = ax[k] * u.x + az[k] * u.y; wA[k] = ax[k] * v.x + az[k] * v.y; maxA = max(maxA, aA[k]) } else { aA[k] = -Float.infinity }
                if br[k] > 0 { aB[k] = L + bx[k] * u.x + bz[k] * u.y; wB[k] = bx[k] * v.x + bz[k] * v.y; minB = min(minB, aB[k]) } else { aB[k] = Float.infinity }
            }
            guard maxA.isFinite, minB.isFinite else { return }
            // (reach: only the cap of each footprint that faces the other can touch)
            // the facing edges (between neighbouring bins that are both facing), collected once
            var ea = [Int](), eb = [Int]()
            ea.reserveCapacity(48); eb.reserveCapacity(48)
            for k in 0..<K {
                let k2 = (k + 1) % K
                if ar[k] > 0, ar[k2] > 0, aA[k] >= maxA - reach, aA[k2] >= maxA - reach { ea.append(k) }
                if br[k] > 0, br[k2] > 0, aB[k] <= minB + reach, aB[k2] <= minB + reach { eb.append(k) }
            }
            // the envelope of A (farthest axial at lateral w) and of B (nearest axial at lateral w)
            func envA(_ w: Float) -> Float? {
                var r: Float?
                for k in ea {
                    let k2 = (k + 1) % K
                    let w0 = wA[k], w1 = wA[k2]
                    if w < min(w0, w1) - 1e-5 || w > max(w0, w1) + 1e-5 { continue }
                    let dw = w1 - w0
                    let t: Float = abs(dw) < 1e-7 ? max(aA[k], aA[k2]) : aA[k] + (aA[k2] - aA[k]) * ((w - w0) / dw)
                    if r == nil || t > r! { r = t }
                }
                return r
            }
            func envB(_ w: Float) -> Float? {
                var r: Float?
                for k in eb {
                    let k2 = (k + 1) % K
                    let w0 = wB[k], w1 = wB[k2]
                    if w < min(w0, w1) - 1e-5 || w > max(w0, w1) + 1e-5 { continue }
                    let dw = w1 - w0
                    let t: Float = abs(dw) < 1e-7 ? min(aB[k], aB[k2]) : aB[k] + (aB[k2] - aB[k]) * ((w - w0) / dw)
                    if r == nil || t < r! { r = t }
                }
                return r
            }
            for k in ea { for q in [k, (k + 1) % K] { if let e = envB(wA[q]) { best = min(best, e - aA[q]) } } }
            for k in eb { for q in [k, (k + 1) % K] { if let e = envA(wB[q]) { best = min(best, aB[q] - e) } } }
        }
        return best
    }
}


extension Skinner {
    /// The vertex blocks after the egg that are drawn right now (the arm capsules, the foot beans, Teddy's ears; not Pip's tail, a feature): what the contact profile samples.
    var contactBlocks: [Range<Int>] {
        var r: [Range<Int>] = []
        if armCapsulesActive { for s in 0..<2 { r.append(armFirst[s]..<(armFirst[s] + ArmCapsule.vertexCount)) } }
        if teddyOn, teddyFirst >= 0 { r.append(teddyFirst..<(teddyFirst + TeddyBean.vertexCount)) }
        if beansActive { for s in 0..<2 { r.append(beanFirst[s]..<(beanFirst[s] + FootBean.vertexCount)) } }
        return r
    }
}
