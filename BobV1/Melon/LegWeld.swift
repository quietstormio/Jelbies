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
    /// Per loop vertex, an egg vertex a few cm further out (the body's slope at the loop: loop -> outer).
    var outer: [Int32]
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
}

nonisolated enum LegWeld {
    static var A: Int { FootBean.around }
    // build-time tunables (launch arguments; a relaunch, not a rebuild)
    static var buildRing: Int { UserDefaults.standard.object(forKey: "LegsWeldRing") != nil ? max(3, min(10, UserDefaults.standard.integer(forKey: "LegsWeldRing"))) : 6 }
    static var buildRows: Int { UserDefaults.standard.object(forKey: "LegsWeldRows") != nil ? max(2, min(12, UserDefaults.standard.integer(forKey: "LegsWeldRows"))) : 6 }
    static var buildMargin: Double { UserDefaults.standard.object(forKey: "LegsWeldMargin") != nil ? UserDefaults.standard.double(forKey: "LegsWeldMargin") : 0.08 }
    /// Front (toe side) margin: the toe stands out in front of the egg, a full margin there climbs the front wall.
    static var buildFront: Double { UserDefaults.standard.object(forKey: "LegsWeldFront") != nil ? UserDefaults.standard.double(forKey: "LegsWeldFront") : 0.06 }
    /// The loops stay this far from the midline (the inner foot walls are only 12 cm apart).
    static var buildInnerX: Double { UserDefaults.standard.object(forKey: "LegsWeldInnerX") != nil ? UserDefaults.standard.double(forKey: "LegsWeldInnerX") : 0.025 }
    static let yMax = 0.40

    /// The mesh last built with the weld (vertex count, info): a Skinner built for that mesh picks the weld up even where nobody calls configureTail (lock tests, portraits).
    nonisolated(unsafe) static var lastBuilt: (vertexCount: Int, info: LegWeldInfo)? = nil

    /// Footprint radius (xz) of the rest foot in direction (cx, cz) from the foot centre (the superellipse of BobForm.footSDF at the sole).
    static func footRadius(_ cx: Double, _ cz: Double) -> Double {
        let rz = cz >= 0 ? BobForm.footToeLen : BobForm.footRadii.z, rx = BobForm.footRadii.x, p = BobForm.footExpXZ
        let a = pow(abs(cx) / rx, p) + pow(abs(cz) / rz, p)
        return 1 / pow(max(a, 1e-12), 1 / p)
    }

    struct Plan {
        var eggTri: [UInt32]
        var sides: [LegWeldSide]
        var ring: Int, rows: Int
        /// Per side: the band's rest positions / normals / mat, rows 1...K x around.
        var bandPos: [[SIMD3<Double>]], bandNrm: [[SIMD3<Double>]], bandMat: [[Float]]
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
    @inline(__always) static func rowS(_ k: Int, _ K: Int) -> Double { Double(k) / Double(K + 1) }

    /// Choose the loops, drop the egg triangles inside them, and lay out the band at rest. nil = the loops could not be made simple (the caller builds the old mesh).
    static func plan(P: [SIMD3<Double>], N: [SIMD3<Double>], M: [Float], tri: [UInt32]) -> Plan? {
        let nV = P.count, R = buildRing, K = buildRows
        // vertex -> triangles
        var vt = [[Int]](repeating: [], count: nV)
        for t in 0..<(tri.count / 3) { for k in 0..<3 { vt[Int(tri[3 * t + k])].append(t) } }
        var removed = [Bool](repeating: false, count: tri.count / 3)
        var sides: [LegWeldSide] = []
        var bandPos: [[SIMD3<Double>]] = [], bandNrm: [[SIMD3<Double>]] = [], bandMat: [[Float]] = []
        let footMat = FootBean.matValues()
        for sigma in [-1.0, 1.0] {
            let cx = sigma * BobForm.footX, cz = BobForm.footZ
            var inside = [Bool](repeating: false, count: nV)
            for v in 0..<nV {
                let p = P[v]
                guard p.y < yMax, sigma * p.x > buildInnerX else { continue }
                let dx = p.x - cx, dz = p.z - cz, r = (dx * dx + dz * dz).squareRoot()
                let fr = footRadius(dx, dz)
                // margin: full at the sides and the heel, `buildFront` toward the toe
                let front = max(0, dz / max(r, 1e-9))
                let mg = buildMargin + (buildFront - buildMargin) * front * front
                if r - fr < mg { inside[v] = true }
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
            var un = [a0[0]]
            for i in 1..<a0.count { var x = a0[i]; while x < un[i - 1] { x += 2 * .pi }; while x - un[i - 1] > 2 * .pi { x -= 2 * .pi }; un.append(x) }
            // (monotone: a loop that turns back locally is clamped; its stitch stays valid)
            for i in 1..<un.count { un[i] = max(un[i], un[i - 1] + 1e-6) }
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
            let side = LegWeldSide(loop: loop.map { Int32($0) }, outer: outer, mA: mA, mB: mB, mW: mW,
                                   hidden: (0..<nV).filter { inside[$0] }.map { Int32($0) })
            // the band at rest
            let rs = FootBean.restStream(sigma: sigma)
            var bp: [SIMD3<Double>] = [], bn: [SIMD3<Double>] = [], bm: [Float] = []
            for k in 1...K {
                let s = rowS(k, K)
                for j in 0..<A {
                    let i0 = 1 + A * R + j, im = 1 + A * (R - 1) + j
                    let p0 = rs[i0], t0 = simd_normalize(rs[i0] - rs[im])
                    let la = loop[Int(mA[j])], lb = loop[Int(mB[j])], w = Double(mW[j])
                    let p1 = P[la] + (P[lb] - P[la]) * w
                    let o1 = P[Int(outer[Int(mA[j])])] + (P[Int(outer[Int(mB[j])])] - P[Int(outer[Int(mA[j])])]) * w
                    let t1 = simd_normalize(o1 - p1)
                    let c = simd_distance(p0, p1)
                    bp.append(hermite(p0, t0 * c * Double(Skinner.weldK0), p1, t1 * c * Double(Skinner.weldK1), s))
                    let n1 = simd_normalize(N[la] + (N[lb] - N[la]) * w), n0 = FootBean.local.nrm[i0]
                    bn.append(simd_normalize(n0 + (n1 - n0) * s))
                    let m1 = M[la] + (M[lb] - M[la]) * Float(w), m0 = footMat[i0]
                    let ss = Float(s * s * (3 - 2 * s))
                    bm.append(m0 + (m1 - m0) * ss)
                }
            }
            sides.append(side); bandPos.append(bp); bandNrm.append(bn); bandMat.append(bm)
        }
        // the two regions must not touch
        if !Set(sides[0].hidden + sides[0].loop).isDisjoint(with: sides[1].hidden + sides[1].loop) { return nil }
        var egg: [UInt32] = []
        egg.reserveCapacity(tri.count)
        for t in 0..<(tri.count / 3) where !removed[t] { egg += [tri[3 * t], tri[3 * t + 1], tri[3 * t + 2]] }
        return Plan(eggTri: egg, sides: sides, ring: R, rows: K, bandPos: bandPos, bandNrm: bandNrm, bandMat: bandMat)
    }

    /// The band quads (seam ring -> row K) and the stitch (row K -> loop) of one side, wound outward against the rest positions `pos` (flat xyz) and rest normals `nrm`.
    /// `seamRest` = rest positions of the seam ring (the piece's own rest stream: its `pos` entries are the hidden ball).
    static func bandTriangles(side sd: LegWeldSide, ring R: Int, rows K: Int, seamRest: [SIMD3<Double>], seamNrm: [SIMD3<Double>],
                              pos: [Double], nrm: [Double]) -> [UInt32] {
        func seam(_ j: Int) -> Int { sd.beanFirst + 1 + A * R + (j % A) }
        func band(_ k: Int, _ j: Int) -> Int { k == 0 ? seam(j) : sd.bandFirst + (k - 1) * A + (j % A) }
        func P(_ v: Int) -> SIMD3<Double> {
            let r = v - (sd.beanFirst + 1 + A * R)
            if r >= 0 && r < A { return seamRest[r] }
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
