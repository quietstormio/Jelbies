//
//  LegWeld.swift
//  2026-11-11 (prototype, branch legs-weld-r1; the user: "their legs cannot look like this we need to unify the body somehow the legs are seperate"):
//  each leg is WELDED to the body. The body triangles around each foot root (a fixed loop of egg vertices chosen once from the rest mesh, about
//  `margin` outside the foot outline) are not drawn; the foot piece (FootBean) is drawn only from the sole up to the seam ring (an open cup); a band of
//  quads, rebuilt every frame by Skinner.applyWeldBand, joins the seam ring to the loop. Along each of the 32 meridians the band is a cubic Hermite
//  curve that leaves the leg along the leg's own slope and arrives at the loop along the body's slope (a tangent-continuous fillet). The band shares
//  its vertices with the cup (the seam ring IS the cup's top ring) and is stitched straight onto the loop's egg vertices, so normals, the baked crease
//  shadow (`mat`) and the crinkle-texture coordinates (`rest`) are continuous by construction.
//
//  Always on (rest included): the welded leg at rest is the old embedded foot's place, sim-skinned through "ghost" copies of the foot piece's vertices
//  at the rest foot (appended after the decals, referenced by no triangle); while the feet act, the piece blends from the ghost to the brain's pose.
//  `-LegsWeld 0` builds the old mesh (closed piece in the belly, collar) for before / after captures from one build.
//
//  Vertex layout (appended after the decals, existing vertex numbers unchanged): per side [ghost (FootBean.vertexCount)], then per side
//  [band rows 1...K, `FootBean.around` each]. Index layout: the band + stitch triangles sit at the head of the capsule index block
//  (ArmCapsuleInfo.indexFirst ..< + bandIndexCount), so the egg-only passes (bean guard, wear, bath) never see them and Panda's egg pass
//  (mode 51, rest-space foot mask) paints them, not the all-charcoal limb pass.
//

import Foundation
import simd

nonisolated struct LegWeldSide: Sendable {
    /// Egg vertices of the loop, in increasing angle about the foot centre (xz plane).
    var loop: [Int32]
    /// Per loop vertex, an egg vertex a few cm further out (diagnostic; the first version took the body's slope from it: noisy, it flipped stitch triangles).
    var outer: [Int32]
    /// Per loop vertex, its egg triangles (outward-wound vertex triples, flat): the body's own normal at the loop, from this frame's drawn egg.
    var nTriStart: [Int32] = [], nTris: [Int32] = []
    /// The egg round the loop that follows the leg (vertex, weight 1 at the loop ... 0 `followReach` further out): the loop slides with the foot, so a stepping
    /// leg never strides out past its own loop (the first version folded the band inside out on every step: the stride is longer than the margin).
    var followV: [Int32] = [], followW: [Float] = []
    /// Per meridian j of the seam ring: the loop point at the meridian's angle = loop[mA] + (loop[mB] - loop[mA]) * mW (indices into `loop`).
    var mA: [Int32], mB: [Int32], mW: [Float]
    /// Egg vertices inside the loop (not drawn while welded).
    var hidden: [Int32]
    var beanFirst: Int = 0, ghostFirst: Int = 0, bandFirst: Int = 0
}

nonisolated struct LegWeldInfo: Sendable {
    var sides: [LegWeldSide]
    /// The seam ring of the foot piece (the cup is drawn from the sole up to this ring).
    var ring: Int
    /// Band rows between the seam ring and the loop.
    var rows: Int
    /// Band + stitch triangles at the head of the capsule index block (indices, not triangles).
    var bandIndexCount: Int
    /// The band's two paint / crinkle streams (xyz per band vertex, side -1 then +1, in band-vertex order): `restDefault` (in the mesh's rest stream) = the old rest
    /// body's own surface at that place (the band point projected onto the rest form with the tight foot fillet, so Teddy's patch, the blue belly, Panda's
    /// marks all end exactly where they ended on the rest body); `restPanda` = the leg's own coordinates up most of the band, fading to the egg's in its
    /// outer rows (Panda's charcoal covers the band up to near the loop: no white smear on the leg top). The renderer writes the Panda one into a Panda slot.
    var restDefault: [Float] = [], restPanda: [Float] = []
}

nonisolated enum LegWeld {
    static var A: Int { FootBean.around }
    // build-time tunables (launch arguments; a relaunch, not a rebuild)
    static var buildRing: Int { UserDefaults.standard.object(forKey: "LegsWeldRing") != nil ? max(3, min(10, UserDefaults.standard.integer(forKey: "LegsWeldRing"))) : 6 }
    static var buildRows: Int { UserDefaults.standard.object(forKey: "LegsWeldRows") != nil ? max(2, min(16, UserDefaults.standard.integer(forKey: "LegsWeldRows"))) : 12 }
    static var buildMargin: Double { UserDefaults.standard.object(forKey: "LegsWeldMargin") != nil ? UserDefaults.standard.double(forKey: "LegsWeldMargin") : 0.08 }
    /// Front (toe side) margin: the toe stands out in front of the egg, a full margin there climbs the front wall.
    static var buildFront: Double { UserDefaults.standard.object(forKey: "LegsWeldFront") != nil ? UserDefaults.standard.double(forKey: "LegsWeldFront") : 0.12 }
    /// The loops stay this far from the midline (the inner foot walls are only 12 cm apart).
    static var buildInnerX: Double { UserDefaults.standard.object(forKey: "LegsWeldInnerX") != nil ? UserDefaults.standard.double(forKey: "LegsWeldInnerX") : 0.025 }
    static let yMax = 0.40
    static var paintMode: Int { UserDefaults.standard.object(forKey: "LegsWeldPaint") != nil ? UserDefaults.standard.integer(forKey: "LegsWeldPaint") : 0 }
    /// Panda's band paint: the leg's own coordinates up to this fraction of the band, then into the egg's (launch argument -LegsWeldPandaCut).
    static var pandaCut: Double { UserDefaults.standard.object(forKey: "LegsWeldPandaCut") != nil ? UserDefaults.standard.double(forKey: "LegsWeldPandaCut") : 0.85 }
    static var followReach: Double { UserDefaults.standard.object(forKey: "LegsWeldFollowReach") != nil ? UserDefaults.standard.double(forKey: "LegsWeldFollowReach") : 0.20 }
    static var restPow: Double { UserDefaults.standard.object(forKey: "LegsWeldRestPow") != nil ? UserDefaults.standard.double(forKey: "LegsWeldRestPow") : 3.0 }

    /// The mesh last built with the weld (vertex count, info): a Skinner built for that mesh picks the weld up even where nobody calls configureTail (lock tests, portraits).
    nonisolated(unsafe) static var lastBuilt: (vertexCount: Int, info: LegWeldInfo)? = nil

    /// Footprint radius (xz) of the rest foot in direction (cx, cz) from the foot centre (the superellipse of BobForm.footSDF at the sole).
    static func footRadius(_ cx: Double, _ cz: Double) -> Double {
        let rz = cz >= 0 ? BobForm.footToeLen : BobForm.footRadii.z, rx = BobForm.footRadii.x, p = BobForm.footExpXZ
        let a = pow(abs(cx) / rx, p) + pow(abs(cz) / rz, p)
        return 1 / pow(max(a, 1e-12), 1 / p)
    }

    // MARK: the weld's baked crease shadow
    // The body's `mat` was baked against the tight rest fillet (footBlend 4.5 cm): around the foot root the egg is crease-dark right up to where the old foot met it, the
    // foot piece's top 85% lighter. Across the plush band that read as a ragged light patch (first captures). Near the feet everything (egg, cup, band, ghost) is baked
    // again against the welded shape: the same egg and arms, the feet joined with a wide blend (`blendW`).
    static var blendW: Double { UserDefaults.standard.object(forKey: "LegsWeldAOBlend") != nil ? UserDefaults.standard.double(forKey: "LegsWeldAOBlend") : 0.14 }
    static func sdfW(_ p: SIMD3<Double>) -> Double {
        let q = SIMD3(abs(p.x), p.y, p.z)
        let arm = BobForm.armSDF(q)
        let u = 1 - min(max(arm.t / 0.55, 0), 1)
        let k = BobForm.armTipBlend + (BobForm.armBlend - BobForm.armTipBlend) * (u * u * (3 - 2 * u))
        return BobForm.smin(BobForm.smin(BobForm.bodySDF(p), arm.d, k), BobForm.footSDF(q), blendW)
    }
    static func normalW(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let e = 0.0015
        let g = SIMD3(sdfW(p + SIMD3(e, 0, 0)) - sdfW(p - SIMD3(e, 0, 0)), sdfW(p + SIMD3(0, e, 0)) - sdfW(p - SIMD3(0, e, 0)), sdfW(p + SIMD3(0, 0, e)) - sdfW(p - SIMD3(0, 0, e)))
        return simd_length(g) > 1e-12 ? simd_normalize(g) : SIMD3(0, 1, 0)
    }
    /// Baked `mat` (0...0.4) of rest point `p` against the welded shape (projected onto it first).
    static func matW(_ p0: SIMD3<Double>) -> Float {
        var p = p0
        for _ in 0..<4 { let f = sdfW(p), n = normalW(p); p -= n * f }
        let n = normalW(p)
        var occ = 0.0, w = 1.0
        for k in 1...5 { let h = 0.05 * Double(k); occ += max(h - sdfW(p + n * h), 0) / h * w; w *= 0.7 }
        return Float(0.4 * min(max(occ * 1.1, 0), 1))
    }
    /// The welded `mat` of the foot piece's vertices at the rest foot (cup + ghost), side `sigma`.
    static func pieceMat(sigma: Double) -> [Float] { FootBean.restStream(sigma: sigma).map { matW($0) } }

    struct Plan {
        var eggTri: [UInt32]
        var sides: [LegWeldSide]
        var ring: Int, rows: Int
        /// Per side: the band's rest positions / normals / mat, rows 1...K x around.
        var bandPos: [[SIMD3<Double>]], bandNrm: [[SIMD3<Double>]], bandMat: [[Float]]
        /// The band's rest SHAPE (bandPos is the rest stream, its parameter pulled toward the leg): what the triangles are wound against.
        var bandShape: [[SIMD3<Double>]] = []
        var bandPanda: [[SIMD3<Double>]] = []
        /// Egg vertices near the feet re-baked against the welded shape (vertex, mat).
        var bodyMat: [(Int, Float)] = []
    }

    /// Cubic Hermite.
    @inline(__always) static func hermite(_ p0: SIMD3<Double>, _ m0: SIMD3<Double>, _ p1: SIMD3<Double>, _ m1: SIMD3<Double>, _ s: Double) -> SIMD3<Double> {
        let s2 = s * s, s3 = s2 * s
        return p0 * (2 * s3 - 3 * s2 + 1) + m0 * (s3 - 2 * s2 + s) + p1 * (-2 * s3 + 3 * s2) + m1 * (s3 - s2)
    }
    @inline(__always) static func hermiteF(_ p0: SIMD3<Float>, _ m0: SIMD3<Float>, _ p1: SIMD3<Float>, _ m1: SIMD3<Float>, _ s: Float) -> SIMD3<Float> {
        let s2 = s * s, s3 = s2 * s
        return p0 * (2 * s3 - 3 * s2 + 1) + m0 * (s3 - 2 * s2 + s) + p1 * (-2 * s3 + 3 * s2) + m1 * (s3 - s2)
    }
    /// Band row parameter (row 1...K): even steps from the seam ring (0) to the loop (1).
    /// Band row parameter (row 1...K) from the seam ring (0) to the loop (1): cosine spacing, rows closer together at both seams (the curve turns fastest there).
    @inline(__always) static func rowS(_ k: Int, _ K: Int) -> Double { rowCosine ? (1 - cos(Double.pi * Double(k) / Double(K + 1))) / 2 : Double(k) / Double(K + 1) }
    static var rowCosine: Bool { UserDefaults.standard.object(forKey: "LegsWeldRowCos") != nil ? UserDefaults.standard.integer(forKey: "LegsWeldRowCos") != 0 : true }

    /// Choose the loops, drop the egg triangles inside them, and lay out the band at rest. nil = the loops could not be made simple (the caller builds the old mesh).
    static func plan(P: [SIMD3<Double>], N: [SIMD3<Double>], M: [Float], tri: [UInt32]) -> Plan? {
        let nV = P.count, R = buildRing, K = buildRows
        // vertex -> triangles
        var vt = [[Int]](repeating: [], count: nV)
        for t in 0..<(tri.count / 3) { for k in 0..<3 { vt[Int(tri[3 * t + k])].append(t) } }
        var removed = [Bool](repeating: false, count: tri.count / 3)
        var sides: [LegWeldSide] = []
        var bandShape: [[SIMD3<Double>]] = [], bandPanda: [[SIMD3<Double>]] = []
        var bandPos: [[SIMD3<Double>]] = [], bandNrm: [[SIMD3<Double>]] = [], bandMat: [[Float]] = []
        let footMat = FootBean.matValues()
        for sigma in [-1.0, 1.0] {
            let cx = sigma * BobForm.footX, cz = BobForm.footZ
            var inside = [Bool](repeating: false, count: nV)
            // the drawn cup at rest (sole up to the seam ring): the loop is `margin` from it in 3D (the egg's lower walls stand within a footprint-plus-margin
            // disc almost all the way round, so an xz distance took the whole lower body: first try)
            let rsC = FootBean.restStream(sigma: sigma)
            let cup = Array(rsC[0..<(1 + A * (R + 1))])
            for v in 0..<nV {
                let p = P[v]
                guard p.y < yMax, sigma * p.x > buildInnerX else { continue }
                let q = SIMD3(abs(p.x), p.y, p.z)
                if BobForm.armSDF(q).d < 0.04 { continue }
                let dx = p.x - cx, dz = p.z - cz, r = (dx * dx + dz * dz).squareRoot()
                // margin: full at the sides and the heel, `buildFront` toward the toe
                let front = max(0, dz / max(r, 1e-9))
                let mg = buildMargin + (buildFront - buildMargin) * front * front
                var d2 = Double.infinity
                for b in cup { d2 = min(d2, simd_distance_squared(b, p)) }
                if d2 < mg * mg { inside[v] = true }
            }
            var loop: [Int] = []
            var ok = false
            for _ in 0..<30 {
                // removed triangles = any vertex inside; an outside vertex all of whose triangles are removed is inside too
                var changed = true
                while changed {
                    changed = false
                    for v in 0..<nV where !inside[v] && !vt[v].isEmpty {
                        if vt[v].allSatisfy({ t in (0..<3).contains { inside[Int(tri[3 * t + $0])] } }) { inside[v] = true; changed = true }
                    }
                }
                // boundary edges: an edge of exactly one removed triangle
                var cnt: [UInt64: Int] = [:]
                func key(_ a: Int, _ b: Int) -> UInt64 { UInt64(min(a, b)) << 32 | UInt64(max(a, b)) }
                for t in 0..<(tri.count / 3) {
                    let a = Int(tri[3 * t]), b = Int(tri[3 * t + 1]), c = Int(tri[3 * t + 2])
                    guard inside[a] || inside[b] || inside[c] else { continue }
                    for (x, y) in [(a, b), (b, c), (c, a)] { cnt[key(x, y), default: 0] += 1 }
                }
                var adj: [Int: [Int]] = [:]
                for (k, n) in cnt where n == 1 {
                    let a = Int(k >> 32), b = Int(k & 0xffffffff)
                    if inside[a] || inside[b] { continue }          // (cannot happen on a closed manifold: every edge with an inside end has both triangles removed)
                    adj[a, default: []].append(b); adj[b, default: []].append(a)
                }
                // pinches (a loop vertex with != 2 boundary edges) go inside
                let pinch = adj.filter { $0.value.count != 2 }.map(\.key)
                if !pinch.isEmpty { for v in pinch { inside[v] = true }; continue }
                // cycles: keep the longest, the others are islands of outside vertices -> inside
                var seen = Set<Int>(), cycles: [[Int]] = []
                for start in adj.keys.sorted() where !seen.contains(start) {
                    var cyc = [start], prev = -1, cur = start
                    seen.insert(start)
                    while true {
                        let nb = adj[cur]!
                        let nx = nb[0] != prev ? nb[0] : nb[1]
                        if nx == start { break }
                        if seen.contains(nx) { break }
                        cyc.append(nx); seen.insert(nx); prev = cur; cur = nx
                    }
                    cycles.append(cyc)
                }
                cycles.sort { $0.count > $1.count }
                if cycles.count > 1 { for c in cycles.dropFirst() { for v in c { inside[v] = true } }; continue }
                guard let c = cycles.first, c.count >= 8 else { return nil }
                loop = c; ok = true; break
            }
            guard ok else { return nil }
            // increasing angle about the foot centre
            func ang(_ v: Int) -> Double { atan2(P[v].z - cz, P[v].x - cx) }
            var turn = 0.0
            for i in 0..<loop.count { var d = ang(loop[(i + 1) % loop.count]) - ang(loop[i]); while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }; turn += d }
            if turn < 0 { loop.reverse() }
            guard abs(abs(turn) - 2 * .pi) < 0.5 else { return nil }          // the loop must go round the foot once
            // unwrapped angles starting at the smallest in [0, 2pi)
            var a0 = loop.map { a -> Double in var x = ang(a); while x < 0 { x += 2 * .pi }; return x }
            let iMin = a0.indices.min { a0[$0] < a0[$1] }!
            loop = Array(loop[iMin...] + loop[..<iMin]); a0 = Array(a0[iMin...] + a0[..<iMin])
            // unwrapped by the smallest step (a loop that turns back locally is clamped to monotone; its stitch stays valid)
            var raw = [a0[0]], un = [a0[0]]
            for i in 1..<a0.count {
                var d = a0[i] - a0[i - 1]; while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
                raw.append(raw[i - 1] + d); un.append(max(raw[i], un[i - 1] + 1e-6))
            }
            if un[un.count - 1] >= un[0] + 2 * .pi { return nil }
            for t in 0..<(tri.count / 3) where (0..<3).contains(where: { inside[Int(tri[3 * t + $0])] }) { removed[t] = true }
            // outer partner: the outside egg vertex nearest to 4 cm further out along the body (radial direction projected onto the tangent plane)
            let loopSet = Set(loop)
            var outer: [Int32] = []
            for v in loop {
                let n = N[v], rad = SIMD3(P[v].x - cx, 0, P[v].z - cz)
                var t = rad - n * simd_dot(rad, n)
                if simd_length(t) < 1e-6 { t = SIMD3(0, 1, 0) - n * n.y }
                t = simd_normalize(t)
                let target = P[v] + t * 0.04
                var best = -1, bd = Double.infinity
                for u in 0..<nV where !inside[u] && !loopSet.contains(u) && !vt[u].isEmpty {
                    let d = simd_distance_squared(P[u], target)
                    if d < bd && simd_dot(P[u] - P[v], t) > 0.01 { bd = d; best = u }
                }
                outer.append(Int32(best >= 0 ? best : v))
            }
            // meridian -> loop segment
            var mA: [Int32] = [], mB: [Int32] = [], mW: [Float] = []
            let nL = loop.count
            for j in 0..<A {
                var th = 2 * Double.pi * Double(j) / Double(A)
                while th < un[0] { th += 2 * .pi }
                var ia = nL - 1, w = 0.0
                for i in 0..<nL {
                    let lo = un[i], hi = i + 1 < nL ? un[i + 1] : un[0] + 2 * .pi
                    if th >= lo && th < hi { ia = i; w = (th - lo) / max(hi - lo, 1e-9); break }
                }
                if ia == nL - 1 && w == 0 { let lo = un[nL - 1], hi = un[0] + 2 * .pi; w = min(1, max(0, (th - lo) / max(hi - lo, 1e-9))) }
                mA.append(Int32(ia)); mB.append(Int32((ia + 1) % nL)); mW.append(Float(w))
            }
            var side = LegWeldSide(loop: loop.map { Int32($0) }, outer: outer, mA: mA, mB: mB, mW: mW,
                                   hidden: (0..<nV).filter { inside[$0] }.map { Int32($0) })
            for v in loop {
                side.nTriStart.append(Int32(side.nTris.count))
                for t in vt[v] {
                    let a = Int(tri[3 * t]), b = Int(tri[3 * t + 1]), c = Int(tri[3 * t + 2])
                    if inside[a] || inside[b] || inside[c] { continue }          // (dropped: inside the loop)
                    let fn = simd_cross(P[b] - P[a], P[c] - P[a])
                    if simd_dot(fn, N[a] + N[b] + N[c]) < 0 { side.nTris += [Int32(a), Int32(c), Int32(b)] } else { side.nTris += [Int32(a), Int32(b), Int32(c)] }
                }
            }
            side.nTriStart.append(Int32(side.nTris.count))
            for v in 0..<nV where !inside[v] && !vt[v].isEmpty && P[v].y < 0.7 {
                var d2 = Double.infinity
                for b in cup { d2 = min(d2, simd_distance_squared(b, P[v])) }
                let d = d2.squareRoot()
                let t = min(1, max(0, (d - buildMargin) / followReach))
                if t >= 1 { continue }
                side.followV.append(Int32(v)); side.followW.append(Float(1 - t * t * (3 - 2 * t)))
            }
            // the band at rest
            let rs = FootBean.restStream(sigma: sigma)
            var bp: [SIMD3<Double>] = [], bn: [SIMD3<Double>] = [], bm: [Float] = [], bsh: [SIMD3<Double>] = [], bpP: [SIMD3<Double>] = []
            var ringC = SIMD3<Double>.zero
            for j in 0..<A { ringC += rs[1 + A * R + j] }
            ringC /= Double(A)
            let legAxis = simd_normalize(ringC - rs[0])
            for k in 1...K {
                let s = rowS(k, K)
                for j in 0..<A {
                    let i0 = 1 + A * R + j, im = 1 + A * (R - 1) + j
                    let p0 = rs[i0], t0 = simd_normalize(rs[i0] - rs[im])
                    let la = loop[Int(mA[j])], lb = loop[Int(mB[j])], w = Double(mW[j])
                    let p1 = P[la] + (P[lb] - P[la]) * w
                    let n1r = simd_normalize(N[la] + (N[lb] - N[la]) * w)
                    var rad = p1 - ringC; rad -= legAxis * simd_dot(rad, legAxis)
                    var t1 = rad - n1r * simd_dot(rad, n1r); t1 = simd_length(t1) > 1e-9 ? simd_normalize(t1) : SIMD3(0, 1, 0)
                    let c = simd_distance(p0, p1)
                    // the rest stream (crinkle texture + the rest-space paint: Panda's foot mask, Teddy's patch) runs along the band's rest shape, with its parameter
                    // pulled toward the leg (`restPow`): the leg's paint carries up most of the band and fades in its outer part (a linear map faded Panda's charcoal across
                    // the whole band, a white smudge on the inner top of each leg)
                    let m0v = t0 * c * Double(Skinner.weldK0), m1v = t1 * c * Double(Skinner.weldK1)
                    let shapeP = hermite(p0, m0v, p1, m1v, s)
                    bsh.append(shapeP)
                    // default paint / crinkle stream: the rest body's own surface there (the old egg + tight foot fillet that this band replaces)
                    let proj0 = BobForm.project(shapeP, steps: 6)
                    let proj = simd_length(proj0 - shapeP) < 0.12 ? proj0 : shapeP
                    // (launch argument -LegsWeldPaint: 0 = projected onto the rest body, 1 = straight blend seam ring -> loop (smoothstep), 2 = half of each)
                    let sm = s * s * (3 - 2 * s), lin = p0 + (p1 - p0) * sm
                    // 3 = cast along the band's own normal onto the rest body (continuous, unlike the nearest point, which jumps from the egg to the foot wall)
                    func cast() -> SIMD3<Double> {
                        let nn = simd_normalize(FootBean.local.nrm[i0] + (simd_normalize(N[la] + (N[lb] - N[la]) * w) - FootBean.local.nrm[i0]) * s)
                        func f(_ t: Double) -> Double { BobForm.sdf(shapeP - nn * t) }
                        var best: Double? = nil, prevT = -0.08, prevF = f(-0.08)
                        var t = -0.08 + 0.004
                        while t <= 0.16 {
                            let ft = f(t)
                            if (prevF > 0) != (ft > 0) {
                                var lo = prevT, hi = t, flo = prevF
                                for _ in 0..<30 { let m = (lo + hi) / 2, fm = f(m); if (fm > 0) == (flo > 0) { lo = m; flo = fm } else { hi = m } }
                                let r = (lo + hi) / 2
                                if best == nil || abs(r) < abs(best!) { best = r }
                            }
                            prevT = t; prevF = ft; t += 0.004
                        }
                        return best.map { shapeP - nn * $0 } ?? proj
                    }
                    switch paintMode { case 1: bp.append(lin); case 2: bp.append((proj + lin) * 0.5); case 3: bp.append(cast()); default: bp.append(proj) }
                    // Panda: the leg's own coordinates (straight up the leg from the seam ring) up to 70 % of the band, then into the egg's
                    let up = p0 + t0 * (simd_distance(p0, p1) * s * 0.3)
                    let tP = max(0, min(1, (s - pandaCut) / (1 - pandaCut))), wP = tP * tP * (3 - 2 * tP)
                    bpP.append(up + (bp[bp.count - 1] - up) * wP)
                    let n1 = simd_normalize(N[la] + (N[lb] - N[la]) * w), n0 = FootBean.local.nrm[i0]
                    bn.append(simd_normalize(n0 + (n1 - n0) * s))
                    _ = footMat
                    bm.append(matW(shapeP))
                }
            }
            sides.append(side); bandPos.append(bp); bandNrm.append(bn); bandMat.append(bm); bandShape.append(bsh); bandPanda.append(bpP)
        }
        // the two regions must not touch
        if !Set(sides[0].hidden + sides[0].loop).isDisjoint(with: sides[1].hidden + sides[1].loop) { return nil }
        // the egg near the feet: re-baked against the welded shape, fading back to the old bake 18...30 cm from the cups
        var bodyMat: [(Int, Float)] = []
        let cups = [-1.0, 1.0].map { sg in Array(FootBean.restStream(sigma: sg)[0..<(1 + A * (R + 1))]) }
        for v in 0..<nV where P[v].y < 0.6 {
            var d2 = Double.infinity
            for c in cups { for b in c { d2 = min(d2, simd_distance_squared(b, P[v])) } }
            let d = d2.squareRoot()
            if d > 0.30 { continue }
            let t = min(1, max(0, (d - 0.18) / 0.12)), wgt = Float(1 - t * t * (3 - 2 * t))
            bodyMat.append((v, M[v] + (matW(P[v]) - M[v]) * wgt))
        }
        var egg: [UInt32] = []
        egg.reserveCapacity(tri.count)
        for t in 0..<(tri.count / 3) where !removed[t] { egg += [tri[3 * t], tri[3 * t + 1], tri[3 * t + 2]] }
        return Plan(eggTri: egg, sides: sides, ring: R, rows: K, bandPos: bandPos, bandNrm: bandNrm, bandMat: bandMat, bandShape: bandShape, bandPanda: bandPanda, bodyMat: bodyMat)
    }

    /// The band quads (seam ring -> row K) and the stitch (row K -> loop) of one side, wound outward against the rest positions `pos` (flat xyz) and rest normals `nrm`.
    /// `seamRest` = rest positions of the seam ring (the piece's own rest stream: its `pos` entries are the hidden ball).
    static func bandTriangles(side sd: LegWeldSide, ring R: Int, rows K: Int, seamRest: [SIMD3<Double>], seamNrm: [SIMD3<Double>],
                              pos: [Double], nrm: [Double], bandShape: [SIMD3<Double>] = []) -> [UInt32] {
        func seam(_ j: Int) -> Int { sd.beanFirst + 1 + A * R + (j % A) }
        func band(_ k: Int, _ j: Int) -> Int { k == 0 ? seam(j) : sd.bandFirst + (k - 1) * A + (j % A) }
        func P(_ v: Int) -> SIMD3<Double> {
            let r = v - (sd.beanFirst + 1 + A * R)
            if r >= 0 && r < A { return seamRest[r] }
            let b = v - sd.bandFirst
            if b >= 0 && b < bandShape.count { return bandShape[b] }
            return SIMD3(pos[3 * v], pos[3 * v + 1], pos[3 * v + 2])
        }
        func Nn(_ v: Int) -> SIMD3<Double> {
            let r = v - (sd.beanFirst + 1 + A * R)
            if r >= 0 && r < A { return seamNrm[r] }
            return SIMD3(nrm[3 * v], nrm[3 * v + 1], nrm[3 * v + 2])
        }
        var out: [UInt32] = []
        func tri(_ a: Int, _ b: Int, _ c: Int) {
            let fn = simd_cross(P(b) - P(a), P(c) - P(a))
            if simd_dot(fn, Nn(a) + Nn(b) + Nn(c)) < 0 { out += [UInt32(a), UInt32(c), UInt32(b)] } else { out += [UInt32(a), UInt32(b), UInt32(c)] }
        }
        for k in 0..<K {
            for j in 0..<A { tri(band(k, j), band(k + 1, j), band(k, j + 1)); tri(band(k, j + 1), band(k + 1, j), band(k + 1, j + 1)) }
        }
        // stitch row K (A vertices at the meridian angles) to the loop (in increasing angle); the meridian j lies on loop segment mA[j] -> mB[j]
        let nL = sd.loop.count
        // position of meridian j along the loop, in loop-index units (0 ..< nL), and of loop vertex i = i
        let raw0 = Double(sd.mA[0]) + Double(sd.mW[0])
        func mpos(_ j: Int) -> Double {
            var r = Double(sd.mA[j % A]) + Double(sd.mW[j % A])
            if r < raw0 - 1e-9 { r += Double(nL) }
            return r + (j >= A ? Double(nL) : 0)
        }
        // start where meridian 0 sits; walk both rings once
        var j = 0
        var i = Int(sd.mA[0]) + 1          // the first loop vertex after meridian 0
        let iEnd = i + nL, jEnd = A
        while j < jEnd || i < iEnd {
            let nextJ = j < jEnd ? mpos(j + 1) : Double.infinity
            let nextI = i < iEnd ? Double(i) : Double.infinity
            if nextJ <= nextI {
                tri(band(K, j), band(K, j + 1), Int(sd.loop[((i - 1) % nL + nL) % nL]))
                j += 1
            } else {
                tri(band(K, j), Int(sd.loop[i % nL]), Int(sd.loop[((i - 1) % nL + nL) % nL]))
                i += 1
            }
        }
        return out
    }
}
