//
//  Geometry.swift
//  Blob: an egg-shaped soft pet (flat-ish base, widest below middle, narrower dome). Tetrahedral sim mesh (circle Delaunay extruded
//  into layers following the profile, plus apex tets for arms/feet), smooth surface-of-revolution render body with nub arms/feet, oval eyes, brows,
//  and the barycentric embedding that ties every render vertex to a tetrahedron.
//  Construction runs in Double, results are stored as Float.
//
//  LOCKED BASE BODY — do not change; see docs/BaseBody.md; guarded by BaseBodyLockTests
//  (the rest sim mesh, the rest render mesh and the eye rig built for the base Blob; appendages added for animation must stay
//  hidden inside the rest body.)
//

import Foundation
import simd

// MARK: - Shape (legacy names, kept so other files keep compiling)

enum Shape {
    static let T: Float = BlobShape.H       // height
    static let Ro: Float = BlobShape.R      // widest radius
    static let skin: Float = 0.04
    static let pale: Float = 0.08
    static let baseR: Float = BlobShape.baseR
}

// MARK: - Seeded PRNG (mulberry32, identical to the JS rng)

struct Mulberry {
    private var s: UInt32
    init(seed: UInt32) { s = seed }
    mutating func next() -> Double {
        s = s &+ 0x6D2B79F5
        var t = s
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}
// MARK: - Bowyer-Watson Delaunay (convex point sets, a few thousand points)

private struct DTri {
    var a: Int32, b: Int32, c: Int32
    var x: Double, y: Double, r2: Double
}

/// Returns CCW triangles (index triples into `pts`, which holds xy pairs).
private func delaunay(_ pts: [Double]) -> [Int] {
    let n = pts.count / 2
    var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
    for i in 0..<n {
        minX = min(minX, pts[2 * i]); maxX = max(maxX, pts[2 * i])
        minY = min(minY, pts[2 * i + 1]); maxY = max(maxY, pts[2 * i + 1])
    }
    let d = max(maxX - minX, maxY - minY) * 20
    let mx = (minX + maxX) / 2, my = (minY + maxY) / 2
    var P = pts
    P.append(contentsOf: [mx - d, my - d, mx + d, my - d, mx, my + d])

    func mk(_ a: Int, _ b: Int, _ c: Int) -> DTri {
        let ax = P[2 * a], ay = P[2 * a + 1], bx = P[2 * b], by = P[2 * b + 1], cx = P[2 * c], cy = P[2 * c + 1]
        let D = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
        let a2 = ax * ax + ay * ay, b2 = bx * bx + by * by, c2 = cx * cx + cy * cy
        let ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / D
        let uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / D
        return DTri(a: Int32(a), b: Int32(b), c: Int32(c), x: ux, y: uy,
                    r2: (ax - ux) * (ax - ux) + (ay - uy) * (ay - uy))
    }

    var tris: [DTri] = [mk(n, n + 1, n + 2)]
    tris.reserveCapacity(2 * n + 8)
    var edges: [SIMD2<Int32>] = []   // boundary candidates of the bad region, reused across points
    edges.reserveCapacity(64)
    for i in 0..<n {
        let px = P[2 * i], py = P[2 * i + 1]
        edges.removeAll(keepingCapacity: true)
        // partition in place: keep triangles whose circumcircle does not contain the point
        var w = 0
        for r in 0..<tris.count {
            let t = tris[r]
            let dx = px - t.x, dy = py - t.y
            if dx * dx + dy * dy < t.r2 * (1 + 1e-9) {
                edges.append(SIMD2(min(t.a, t.b), max(t.a, t.b)))
                edges.append(SIMD2(min(t.b, t.c), max(t.b, t.c)))
                edges.append(SIMD2(min(t.c, t.a), max(t.c, t.a)))
            } else {
                tris[w] = t; w += 1
            }
        }
        tris.removeSubrange(w..<tris.count)
        // edges that occur exactly once bound the cavity
        edges.sort { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        var k = 0
        while k < edges.count {
            var m = k + 1
            while m < edges.count && edges[m] == edges[k] { m += 1 }
            if m - k == 1 { tris.append(mk(Int(edges[k].x), Int(edges[k].y), i)) }
            k = m
        }
    }
    var res: [Int] = []
    res.reserveCapacity(tris.count * 3)
    for t in tris {
        let a = Int(t.a), b = Int(t.b), c = Int(t.c)
        if a >= n || b >= n || c >= n { continue }
        let ax = P[2 * a], ay = P[2 * a + 1]
        let cr = (P[2 * b] - ax) * (P[2 * c + 1] - ay) - (P[2 * b + 1] - ay) * (P[2 * c] - ax)
        if cr > 0 { res.append(contentsOf: [a, b, c]) } else { res.append(contentsOf: [a, c, b]) }
    }
    return res
}

// MARK: - Profile helpers

private func hexLattice(_ spacing: Double, radius: Double, keep: (Double, Double) -> Bool) -> [Double] {
    var pts: [Double] = []
    let dy = spacing * 3.0.squareRoot() / 2
    var row = 0
    var w = -radius - spacing
    while w < radius + spacing {
        let off = Double(row % 2) * spacing / 2
        var u = -radius - spacing + off
        while u < radius + spacing {
            if keep(u, w) { pts.append(u); pts.append(w) }
            u += spacing
        }
        w += dy; row += 1
    }
    return pts
}

// MARK: - Simulation mesh

/// Heights of the sim layer levels (levels = layers + 1): flat base at 0, ending exactly at H.
private func simLevels(_ layers: Int, H: Double) -> [Double] {
    if layers == 7 { return [0, 0.085, 0.22, 0.38, 0.55, 0.72, 0.88, 1.0].map { $0 * H } }
    return (0...layers).map { H * (1 - pow(1 - Double($0) / Double(layers), 1.35)) }
}

/// Radius of each sim level. Starts on the profile, then grows just enough that the faceted sim hull
/// (polygon ring, straight chords between levels) contains the smooth render surface (up to `slack`).
private func simRadii(_ ys: [Double], azimuthSegments n: Int, prof: BlobProfile) -> [Double] {
    let az = 1 / cos(Double.pi / Double(n))
    var r = ys.map { prof.radius(atHeight: $0) * az }
    r[r.count - 1] = max(r[r.count - 1], 0.2)      // the dome closes to a point: keep a small flat top layer on the sim hull
    let nL = ys.count
    let margin = 0.004 * prof.R
    for _ in 0..<80 {
        for l in 0..<(nL - 1) {
            var d = 0.0
            for k in 0...48 {
                let f = Double(k) / 48
                let y = ys[l] + (ys[l + 1] - ys[l]) * f
                let chord = r[l] + (r[l + 1] - r[l]) * f
                d = max(d, prof.radius(atHeight: y) * az + margin - chord)
            }
            if d > 0 { r[l] += d; r[l + 1] += d }
        }
    }
    return r
}

/// 2D Delaunay of a unit disc, extruded into layers following the Blob profile (the top sim layer is a small flat disc
/// under the dome apex). Arms and feet are extra particles: each nub is one apex particle joined by tets to a patch of
/// wall triangles, so the appendages are part of the soft body (they hang, squash and jiggle with it).
private func buildSimMeshLegacy(h: Float, layers: Int, appearance: BlobAppearance) -> SimMesh {
    let prof = BlobProfile(appearance.effective)
    let h = Double(h)
    // boundary ring + hex lattice inside the unit disc
    let nRing = max(8, Int((2 * Double.pi / h).rounded()))
    var all: [Double] = []
    for i in 0..<nRing {
        let a = 2 * Double.pi * Double(i) / Double(nRing)
        all.append(cos(a)); all.append(sin(a))
    }
    let inner = hexLattice(h, radius: 1) { u, w in hypot(u, w) < 1 - h * 0.55 }
    all += inner
    let tri2 = delaunay(all)
    var t2: [Int] = []
    var q = 0
    while q < tri2.count {
        let a = tri2[q], b = tri2[q + 1], c = tri2[q + 2]
        q += 3
        let ax = all[2 * a], ay = all[2 * a + 1], bx = all[2 * b], by = all[2 * b + 1], cx = all[2 * c], cy = all[2 * c + 1]
        let area = abs((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)) / 2
        let l2 = max((bx - ax) * (bx - ax) + (by - ay) * (by - ay),
                     (cx - bx) * (cx - bx) + (cy - by) * (cy - by),
                     (ax - cx) * (ax - cx) + (ay - cy) * (ay - cy))
        if area / l2 > 0.12 { t2.append(contentsOf: [a, b, c]) }
    }
    var used = [Int](repeating: -1, count: all.count / 2)
    var verts2: [Double] = []
    for v in t2 where used[v] < 0 {
        used[v] = verts2.count / 2
        verts2.append(all[2 * v]); verts2.append(all[2 * v + 1])
    }
    let tris = t2.map { used[$0] }
    let n2 = verts2.count / 2
    let ys = simLevels(layers, H: prof.H)
    let nL = ys.count
    var rest = [Float](repeating: 0, count: n2 * nL * 3)
    let rads = simRadii(ys, azimuthSegments: nRing, prof: prof)
    for l in 0..<nL {
        let rl = rads[l]
        for i in 0..<n2 {
            let k = (l * n2 + i) * 3
            rest[k] = Float(verts2[2 * i] * rl)
            rest[k + 1] = Float(ys[l])
            rest[k + 2] = Float(verts2[2 * i + 1] * rl)
        }
    }
    var tets: [UInt32] = []
    tets.reserveCapacity(layers * (tris.count / 3) * 12)
    for l in 0..<(nL - 1) {
        var i = 0
        while i < tris.count {
            let s = [tris[i], tris[i + 1], tris[i + 2]].sorted()
            let a = l * n2 + s[0], b = l * n2 + s[1], c = l * n2 + s[2]
            let A = a + n2, B = b + n2, C = c + n2
            for v in [a, b, c, A, b, c, A, B, c, A, B, C] { tets.append(UInt32(v)) }
            i += 3
        }
    }
    // region 2 (firmer skin): boundary ring of any layer, the whole bottom and top layers. Everything else 0.
    var region = [UInt8](repeating: 0, count: n2 * nL)
    for l in 0..<nL {
        for i in 0..<n2 {
            let onRing = hypot(verts2[2 * i], verts2[2 * i + 1]) > 1 - 1e-6
            if onRing || l == 0 || l == nL - 1 { region[l * n2 + i] = 2 }
        }
    }

    // ── appendages: wall triangles (boundary ring x consecutive layers) joined to one apex particle per nub ──
    var wall: [(Int, Int, Int)] = []
    for l in 0..<(nL - 1) {
        for i in 0..<nRing {
            let j = (i + 1) % nRing
            guard used[i] >= 0, used[j] >= 0 else { continue }
            let p00 = l * n2 + used[i], p01 = l * n2 + used[j], p11 = (l + 1) * n2 + used[j], p10 = (l + 1) * n2 + used[i]
            wall.append((p00, p01, p11)); wall.append((p00, p11, p10))
        }
    }
    func P(_ i: Int) -> SIMD3<Double> { SIMD3(Double(rest[3 * i]), Double(rest[3 * i + 1]), Double(rest[3 * i + 2])) }
    func wallNormal(_ t: (Int, Int, Int)) -> SIMD3<Double> {
        // listed order winds so that cross(e1, e2) points inward (see ring orientation); outward is its negative
        let n = simd_cross(P(t.1) - P(t.0), P(t.2) - P(t.0))
        let l = simd_length(n)
        return l > 1e-12 ? -n / l : SIMD3(0, 1, 0)
    }
    for nub in prof.nubs(appearance) {
        // patch triangles near the anchor whose outward normal faces the nub direction; widen if none qualify
        var patch: [(Int, Int, Int)] = []
        var cen = SIMD3<Double>(repeating: 0)
        var radius = nub.patchRadius
        for _ in 0..<5 where patch.isEmpty {
            cen = SIMD3<Double>(repeating: 0)
            for t in wall {
                let c = (P(t.0) + P(t.1) + P(t.2)) / 3
                if simd_distance(c, nub.surfaceAnchor) < radius && simd_dot(wallNormal(t), nub.d) > 0.35 {
                    patch.append(t); cen += c
                }
            }
            radius *= 1.4
        }
        guard !patch.isEmpty else { continue }
        cen /= Double(patch.count)
        var apex = cen + nub.d * nub.apexDist
        if nub.isFoot { apex.y = max(apex.y, nub.center.y) }
        let ai = rest.count / 3
        rest.append(Float(apex.x)); rest.append(Float(apex.y)); rest.append(Float(apex.z))
        region.append(0)
        for t in patch { tets.append(contentsOf: [UInt32(t.0), UInt32(t.1), UInt32(t.2), UInt32(ai)]) }
    }

    // orient every tet to positive volume
    var t = 0
    while t < tets.count {
        if tetVolume(rest, Int(tets[t]), Int(tets[t + 1]), Int(tets[t + 2]), Int(tets[t + 3])) < 0 {
            tets.swapAt(t + 2, t + 3)
        }
        t += 4
    }
    return SimMesh(rest: rest, tets: tets, region: region, n2: n2, layers: nL - 1)
}

private func tetVolume(_ p: [Float], _ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Float {
    let ax = p[3 * a], ay = p[3 * a + 1], az = p[3 * a + 2]
    let b0 = p[3 * b] - ax, b1 = p[3 * b + 1] - ay, b2 = p[3 * b + 2] - az
    let c0 = p[3 * c] - ax, c1 = p[3 * c + 1] - ay, c2 = p[3 * c + 2] - az
    let d0 = p[3 * d] - ax, d1 = p[3 * d + 1] - ay, d2 = p[3 * d + 2] - az
    return (b0 * (c1 * d2 - c2 * d1) - b1 * (c0 * d2 - c2 * d0) + b2 * (c0 * d1 - c1 * d0)) / 6
}


// MARK: - Render mesh

/// Body (surface of revolution from the Blob profile, poles at bottom and top centre) plus arm / foot nubs (also material 0),
/// then the face decals in the "seeds" range: oval eyes (material 1), eye glints (3) and brow lines (4).
/// Decals are thin beads that follow the body surface and sit a hair above it. No bubbles.
private func buildRenderMeshLegacy(appearance: BlobAppearance) -> RenderMesh {
    let proportions = appearance.effective
    let prof = BlobProfile(proportions)
    let bH = prof.H
    var pos: [Double] = [], nrm: [Double] = [], mat: [Float] = []
    var idx: [UInt32] = []
    @discardableResult
    func add(_ x: Double, _ y: Double, _ z: Double, _ m: Float, _ nx: Double = 0, _ ny: Double = 1, _ nz: Double = 0) -> Int {
        pos.append(x); pos.append(y); pos.append(z)
        nrm.append(nx); nrm.append(ny); nrm.append(nz)
        mat.append(m)
        return pos.count / 3 - 1
    }
    func tri(_ a: Int, _ b: Int, _ c: Int) { idx.append(UInt32(a)); idx.append(UInt32(b)); idx.append(UInt32(c)) }

    // ── body: rings from the closed profile; first and last samples (r = 0) become single pole vertices ──
    let seg = 96
    let prf = prof.profile(spacing: 0.03)
    precondition(prf.count > 4 && prf[0].r == 0 && prf[prf.count - 1].r == 0)
    let bottomPole = add(0, 0, 0, 0, 0, -1, 0)
    var ringStart: [Int] = []
    for k in 1..<(prf.count - 1) {
        let p = prf[k]
        ringStart.append(pos.count / 3)
        for s in 0..<seg {
            let a = 2 * Double.pi * Double(s) / Double(seg)
            let c = cos(a), sn = sin(a)
            add(Double(p.r) * c, Double(p.y), Double(p.r) * sn,
                0, Double(p.nr) * c, Double(p.ny), Double(p.nr) * sn)
        }
    }
    let topPole = add(0, bH, 0, 0, 0, 1, 0)
    let nRings = ringStart.count
    for s in 0..<seg { tri(bottomPole, ringStart[0] + (s + 1) % seg, ringStart[0] + s) }
    for k in 0..<(nRings - 1) {
        for s in 0..<seg {
            let a = ringStart[k] + s, b = ringStart[k] + (s + 1) % seg
            let c = ringStart[k + 1] + s, d = ringStart[k + 1] + (s + 1) % seg
            tri(a, c, b); tri(b, c, d)
        }
    }
    for s in 0..<seg { tri(ringStart[nRings - 1] + s, topPole, ringStart[nRings - 1] + (s + 1) % seg) }

    // ── arm / foot nubs (material 0): ellipsoids growing out of the wall ──
    for nub in prof.nubs(appearance) {
        let nLat = 16, nLon = 28
        let base = pos.count / 3
        for i in 0...nLat {
            let th = Double.pi * Double(i) / Double(nLat)
            for j in 0..<nLon {
                let ph = 2 * Double.pi * Double(j) / Double(nLon)
                let lx = cos(th), ly = sin(th) * cos(ph), lz = sin(th) * sin(ph)     // d, w, up
                let p = nub.center + nub.d * (lx * nub.semi.x) + nub.w * (ly * nub.semi.y) + nub.up * (lz * nub.semi.z)
                let g = nub.d * (lx / nub.semi.x) + nub.w * (ly / nub.semi.y) + nub.up * (lz / nub.semi.z)
                let n = simd_normalize(g)
                add(p.x, max(p.y, 0), p.z, 0, n.x, n.y, n.z)
            }
        }
        for i in 0..<nLat {
            for j in 0..<nLon {
                let a = base + i * nLon + j, b = base + i * nLon + (j + 1) % nLon, c = a + nLon, d = b + nLon
                tri(a, b, c); tri(b, d, c)
            }
        }
    }
    // ── Honey: curly antenna(s) out of the crown (stalk = material 0, bobble = material 5) ──
    var antennae: [AntennaInfo] = []
    if appearance.breed == .honey {
        var rng = Mulberry(seed: appearance.featureSeed &* 2246822519 &+ 11)
        let na = appearance.resolvedFeatureCount
        let fs = Double(appearance.featureScale) * Double(appearance.sizeScale)
        for ai in 0..<na {
            let pairSign = na == 2 ? (ai == 0 ? -1.0 : 1.0) : 0.0
            let curlDir = rng.next() < 0.5 ? -1.0 : 1.0
            let turns = 1.0 + 0.5 * rng.next()
            let length = (na == 2 ? 0.34 : 0.44) * fs
            let rc = (na == 2 ? 0.075 : 0.10) * fs * (0.85 + 0.3 * rng.next())
            let base = SIMD3<Double>(pairSign * 0.11 * prof.R / 0.7, bH * 0.985 - 0.02 * bH / 1.35, 0.0)
            let tilt = pairSign * 0.38
            let axis = simd_normalize(SIMD3(sin(tilt), cos(tilt), -0.08))
            let sideV = simd_normalize(simd_cross(axis, SIMD3(0, 0, 1)))
            let sideW = simd_cross(axis, sideV)
            let nSeg = 64, nAround = 12
            func centre(_ t: Double) -> SIMD3<Double> {
                let r = rc * min(1, t / 0.22) * (1 - 0.3 * t)
                let phi = curlDir * 2 * Double.pi * turns * t
                return base + axis * (length * t) + sideV * (r * cos(phi) - r) + sideW * (r * sin(phi))
            }
            let first = pos.count / 3
            var weights: [Float] = []
            var prevN = sideV
            var rings: [Int] = []
            let rStalk0 = 0.026 * sqrt(fs), rStalk1 = 0.016 * sqrt(fs)
            for i in 0...nSeg {
                let t = Double(i) / Double(nSeg)
                let c = centre(t)
                let tan = simd_normalize(centre(min(1, t + 0.01)) - centre(max(0, t - 0.01)))
                var nn = prevN - tan * simd_dot(prevN, tan)
                nn = simd_length(nn) < 1e-6 ? sideW : simd_normalize(nn)
                prevN = nn
                let bb = simd_cross(tan, nn)
                let rad = rStalk0 + (rStalk1 - rStalk0) * t
                rings.append(pos.count / 3)
                for j in 0..<nAround {
                    let a = 2 * Double.pi * Double(j) / Double(nAround)
                    let dir = nn * cos(a) + bb * sin(a)
                    let p = c + dir * rad
                    add(p.x, p.y, p.z, 0, dir.x, dir.y, dir.z)
                    weights.append(Float(pow(t, 1.4)))
                }
            }
            for i in 0..<nSeg {
                for j in 0..<nAround {
                    let a = rings[i] + j, b = rings[i] + (j + 1) % nAround, c = rings[i + 1] + j, d = rings[i + 1] + (j + 1) % nAround
                    tri(a, c, b); tri(b, c, d)
                }
            }
            // bobble
            let tipC = centre(1) + simd_normalize(centre(1) - centre(0.97)) * 0.0
            let br = 0.058 * fs
            let bc = tipC + simd_normalize(centre(1) - centre(0.97)) * br * 0.55
            let bLat = 14, bLon = 24
            let bBase = pos.count / 3
            for i in 0...bLat {
                let th = Double.pi * Double(i) / Double(bLat)
                for j in 0..<bLon {
                    let ph = 2 * Double.pi * Double(j) / Double(bLon)
                    let n = SIMD3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
                    let p = bc + n * br
                    add(p.x, p.y, p.z, 5, n.x, n.y, n.z)
                    weights.append(1)
                }
            }
            for i in 0..<bLat {
                for j in 0..<bLon {
                    let a = bBase + i * bLon + j, b = bBase + i * bLon + (j + 1) % bLon, c = a + bLon, d = b + bLon
                    tri(a, c, b); tri(b, c, d)
                }
            }
            let up0 = base + SIMD3(0, 0.1, 0), sd0 = base + SIMD3(0.1, 0, 0)
            antennae.append(AntennaInfo(
                firstVertex: first, vertexCount: pos.count / 3 - first,
                basePoints: [base, up0, sd0].flatMap { [Float($0.x), Float($0.y), Float($0.z)] },
                tip: SIMD3(Float(bc.x), Float(bc.y), Float(bc.z)), weights: weights))
        }
    }
    let bodyIndexCount = idx.count

    // ── decals: shapes on the surface of revolution, parameterised by (u along the azimuth arc, v up the height) ──
    /// Superellipse footprint of half sizes (a, b), exponent pw, centred at (yc, thc) (+ optional (du, dv) offset), raised by
    /// `lift + bump * sqrt(1 - rho^2)`; a skirt ring sinks under the surface so there is never a visible gap.
    func decal(yc: Double, thc: Double, a: Double, b: Double, pw: Double, du: Double = 0, dv: Double = 0,
               lift: Double, bump: Double, m: Float) {
        let rc = prof.radius(atHeight: yc)
        let nR = 6, nA = 40
        func point(_ rho: Double, _ ang: Double, _ h: Double) -> SIMD3<Double> {
            let c = cos(ang), s = sin(ang)
            let e = 2 / pw
            let u = du + a * rho * (c < 0 ? -1 : 1) * pow(abs(c), e)
            let v = dv + b * rho * (s < 0 ? -1 : 1) * pow(abs(s), e)
            let y = yc + v
            let th = thc + u / max(prof.radius(atHeight: y), rc * 0.5)
            let sf = prof.surface(y: y, th: th)
            return sf.p + sf.n * h
        }
        func height(_ rho: Double) -> Double { lift + bump * sqrt(max(0, 1 - rho * rho)) }
        func normalAt(_ rho: Double, _ ang: Double, _ h: Double) -> SIMD3<Double> {
            // numeric normal of the bead surface; poles of the polar grid use a small ring offset
            let r0 = max(rho, 0.02), e = 0.02
            let pa = point(min(r0 + e, 1), ang, height(min(r0 + e, 1))) - point(max(r0 - e, 0), ang, height(max(r0 - e, 0)))
            let pb = point(r0, ang + e, height(r0)) - point(r0, ang - e, height(r0))
            var n = simd_cross(pa, pb)
            let outward = prof.surface(y: yc, th: thc).n
            if simd_dot(n, outward) < 0 { n = -n }
            return simd_normalize(n)
        }
        let c0 = point(0, 0, height(0))
        let centre = add(c0.x, c0.y, c0.z, m, normalAt(0, 0, 0).x, normalAt(0, 0, 0).y, normalAt(0, 0, 0).z)
        var rings: [Int] = []
        for i in 1...nR {
            let rho = Double(i) / Double(nR)
            rings.append(pos.count / 3)
            for j in 0..<nA {
                let ang = 2 * Double.pi * Double(j) / Double(nA)
                let p = point(rho, ang, height(rho)), n = normalAt(rho, ang, 0)
                add(p.x, p.y, p.z, m, n.x, n.y, n.z)
            }
        }
        let skirt = pos.count / 3
        for j in 0..<nA {
            let ang = 2 * Double.pi * Double(j) / Double(nA)
            let p = point(1, ang, -0.012), n = normalAt(1, ang, 0)
            add(p.x, p.y, p.z, m, n.x, n.y, n.z)
        }
        for j in 0..<nA { tri(centre, rings[0] + j, rings[0] + (j + 1) % nA) }
        for i in 0..<(nR - 1) {
            for j in 0..<nA {
                let a0 = rings[i] + j, b0 = rings[i] + (j + 1) % nA, c0 = rings[i + 1] + j, d0 = rings[i + 1] + (j + 1) % nA
                tri(a0, c0, b0); tri(b0, c0, d0)
            }
        }
        for j in 0..<nA {
            let a0 = rings[nR - 1] + j, b0 = rings[nR - 1] + (j + 1) % nA, c0 = skirt + j, d0 = skirt + (j + 1) % nA
            tri(a0, c0, b0); tri(b0, c0, d0)
        }
    }

    let seedStart = idx.count
    let eyeY = Double(proportions.eyeT) * bH
    let eyeX = Double(proportions.eyeSpacingFrac) * 2 * prof.R
    let eyeRX = Double(proportions.eyeRX), eyeRY = Double(proportions.eyeRY)
    let eyeBump = Double(proportions.eyeBump)
    let sides = [-1.0, 1.0]
    func azimuth(_ x: Double, _ y: Double) -> Double { asin(min(1, max(-1, x / prof.radius(atHeight: y)))) }
    // eyes (material 1)
    for sgn in sides {
        decal(yc: eyeY, thc: azimuth(sgn * eyeX, eyeY), a: eyeRX, b: eyeRY, pw: 2, lift: 0.003, bump: eyeBump, m: 1)
    }
    // glints (material 3): small sparkle up-left on each eye bead
    for sgn in sides {
        let gu = -0.36 * eyeRX, gv = 0.40 * eyeRY
        let rho = hypot(-0.36, 0.40)
        let hEye = 0.003 + eyeBump * sqrt(max(0, 1 - rho * rho))
        decal(yc: eyeY, thc: azimuth(sgn * eyeX, eyeY), a: eyeRX * 0.26, b: eyeRX * 0.26, pw: 2, du: gu, dv: gv,
              lift: hEye + 0.0005, bump: 0.004, m: 3)
    }
    // brows (material 4): flat superellipse lines
    for sgn in sides {
        for k in 0..<max(1, proportions.browLines) {
            let by = Double(proportions.browT) * bH + Double(k) * Double(proportions.browGap)
            decal(yc: by, thc: azimuth(sgn * eyeX, by), a: Double(proportions.browHalfLen), b: Double(proportions.browHalfThick),
                  pw: 3.2, lift: 0.002, bump: 0.011, m: 4)
        }
    }
    let seedCount = idx.count - seedStart

    // make every triangle's winding agree with its analytic outward normal (CCW = front)
    var i = 0
    while i < idx.count {
        let a = Int(idx[i]), b1 = Int(idx[i + 1]), c = Int(idx[i + 2])
        let e1x = pos[3 * b1] - pos[3 * a], e1y = pos[3 * b1 + 1] - pos[3 * a + 1], e1z = pos[3 * b1 + 2] - pos[3 * a + 2]
        let e2x = pos[3 * c] - pos[3 * a], e2y = pos[3 * c + 1] - pos[3 * a + 1], e2z = pos[3 * c + 2] - pos[3 * a + 2]
        let fx = e1y * e2z - e1z * e2y, fy = e1z * e2x - e1x * e2z, fz = e1x * e2y - e1y * e2x
        var d = 0.0
        for v in [a, b1, c] { d += fx * nrm[3 * v] + fy * nrm[3 * v + 1] + fz * nrm[3 * v + 2] }
        if d < 0 { idx[i + 1] = UInt32(c); idx[i + 2] = UInt32(b1) }
        i += 3
    }

    return RenderMesh(
        rest: pos.map { Float($0) }, restNormal: nrm.map { Float($0) }, mat: mat, index: idx,
        body: (0, bodyIndexCount), seeds: (seedStart, seedCount), bubbles: (idx.count, 0),
        seedCount: 2, antennae: antennae)
}

// MARK: - Barycentric embedding

/// Embeds each render vertex in the sim tet (rest pose) with the best (largest min) barycentric coordinates.
func embed(simRest: [Float], tets: [UInt32], verts: [Float]) -> (tetOf: [UInt32], w: [Float]) {
    let nT = tets.count / 4, nV = verts.count / 3
    let cell = 0.2
    @inline(__always) func key(_ i: Int, _ j: Int, _ k: Int) -> Int { (i + 512) * 1048576 + (j + 512) * 1024 + (k + 512) }
    var grid: [Int: [Int32]] = [:]
    var inv = [Double](repeating: 0, count: nT * 9)
    @inline(__always) func R(_ v: Int, _ c: Int) -> Double { Double(simRest[3 * v + c]) }
    for t in 0..<nT {
        let id = [Int(tets[4 * t]), Int(tets[4 * t + 1]), Int(tets[4 * t + 2]), Int(tets[4 * t + 3])]
        var mn = SIMD3<Double>(repeating: .infinity), mxv = SIMD3<Double>(repeating: -.infinity)
        for v in id { for c in 0..<3 { mn[c] = min(mn[c], R(v, c)); mxv[c] = max(mxv[c], R(v, c)) } }
        let i0 = Int((mn[0] / cell).rounded(.down)), i1 = Int((mxv[0] / cell).rounded(.down))
        let j0 = Int((mn[1] / cell).rounded(.down)), j1 = Int((mxv[1] / cell).rounded(.down))
        let k0 = Int((mn[2] / cell).rounded(.down)), k1 = Int((mxv[2] / cell).rounded(.down))
        for i in i0...i1 { for j in j0...j1 { for k in k0...k1 { grid[key(i, j, k), default: []].append(Int32(t)) } } }
        // inverse of [b-a, c-a, d-a]
        let a = id[0]
        var m: [Double] = []
        for c in 1..<4 { for r in 0..<3 { m.append(R(id[c], r) - R(a, r)) } }
        let M = [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]
        let det = M[0] * (M[4] * M[8] - M[5] * M[7]) - M[1] * (M[3] * M[8] - M[5] * M[6]) + M[2] * (M[3] * M[7] - M[4] * M[6])
        let id2 = 1 / det
        inv[9 * t + 0] = (M[4] * M[8] - M[5] * M[7]) * id2; inv[9 * t + 1] = (M[2] * M[7] - M[1] * M[8]) * id2; inv[9 * t + 2] = (M[1] * M[5] - M[2] * M[4]) * id2
        inv[9 * t + 3] = (M[5] * M[6] - M[3] * M[8]) * id2; inv[9 * t + 4] = (M[0] * M[8] - M[2] * M[6]) * id2; inv[9 * t + 5] = (M[2] * M[3] - M[0] * M[5]) * id2
        inv[9 * t + 6] = (M[3] * M[7] - M[4] * M[6]) * id2; inv[9 * t + 7] = (M[1] * M[6] - M[0] * M[7]) * id2; inv[9 * t + 8] = (M[0] * M[4] - M[1] * M[3]) * id2
    }
    func bary(_ t: Int, _ x: Double, _ y: Double, _ z: Double) -> SIMD4<Double> {
        let a = Int(tets[4 * t])
        let dx = x - R(a, 0), dy = y - R(a, 1), dz = z - R(a, 2)
        let I = 9 * t
        let b1 = inv[I] * dx + inv[I + 1] * dy + inv[I + 2] * dz
        let b2 = inv[I + 3] * dx + inv[I + 4] * dy + inv[I + 5] * dz
        let b3 = inv[I + 6] * dx + inv[I + 7] * dy + inv[I + 8] * dz
        return SIMD4(1 - b1 - b2 - b3, b1, b2, b3)
    }
    var tetOf = [UInt32](repeating: 0, count: nV)
    var w = [Float](repeating: 0, count: nV * 4)
    for v in 0..<nV {
        let x = Double(verts[3 * v]), y = Double(verts[3 * v + 1]), z = Double(verts[3 * v + 2])
        var best = -1, bestScore = -Double.infinity
        var bestB = SIMD4<Double>(repeating: 0)
        func tryT(_ t: Int) {
            let bb = bary(t, x, y, z)
            let s = min(min(bb[0], bb[1]), min(bb[2], bb[3]))
            if s > bestScore { bestScore = s; best = t; bestB = bb }
        }
        let ci = Int((x / cell).rounded(.down)), cj = Int((y / cell).rounded(.down)), ck = Int((z / cell).rounded(.down))
        var r = 0
        while r <= 2 && bestScore < -1e-4 {
            for i in (ci - r)...(ci + r) { for j in (cj - r)...(cj + r) { for k in (ck - r)...(ck + r) {
                if max(abs(i - ci), abs(j - cj), abs(k - ck)) != r { continue }
                if let l = grid[key(i, j, k)] { for t in l { tryT(Int(t)) } }
            } } }
            r += 1
        }
        if best < 0 { for t in 0..<nT { tryT(t) } }
        tetOf[v] = UInt32(best)
        for k in 0..<4 { w[4 * v + k] = Float(bestB[k]) }
    }
    return (tetOf, w)
}

// MARK: - Eye rig (blinking)

/// Which render vertices belong to which eye, plus two virtual points per eye (centre, centre + local up) embedded in
/// the sim mesh so the skinner can recover each eye's skinned centre and current local up axis.
struct EyeRig {
    var eye: [[Int32]]       // per eye (0 = -x side, 1 = +x side): eyeball vertices (material 1)
    var glint: [[Int32]]     // per eye: glint vertices (material 3)
    var anchorTet: [UInt32]  // 4 virtual points: [centre0, up0, centre1, up1]
    var anchorW: [Float]     // 4 barycentric weights per virtual point
    var brow: [[Int32]] = [[], []]   // per side (0 = -x): brow vertices (material 4), for future tilt / gaze
}

private func buildEyeRigLegacy(render rm: RenderMesh, sim: SimMesh, appearance: BlobAppearance) -> EyeRig {
    let prof = BlobProfile(appearance.effective)
    var eye: [[Int32]] = [[], []], glint: [[Int32]] = [[], []]
    var sum = [SIMD3<Double>](repeating: .zero, count: 2), cnt = [0, 0]
    for v in 0..<rm.vertexCount where rm.mat[v] == 1 || rm.mat[v] == 3 {
        let s = rm.rest[3 * v] < 0 ? 0 : 1
        if rm.mat[v] == 1 {
            eye[s].append(Int32(v)); cnt[s] += 1
            sum[s] += SIMD3(Double(rm.rest[3 * v]), Double(rm.rest[3 * v + 1]), Double(rm.rest[3 * v + 2]))
        } else { glint[s].append(Int32(v)) }
    }
    var pts: [Float] = []
    for s in 0..<2 {
        let c = sum[s] / Double(max(cnt[s], 1))
        let r = hypot(c.x, c.z)
        let nn = prof.sample(atHeight: c.y)
        let n = simd_normalize(SIMD3(nn.nr * c.x / r, nn.ny, nn.nr * c.z / r))
        let y = SIMD3<Double>(0, 1, 0)
        let up = simd_normalize(y - n * simd_dot(y, n))
        let u = c + up * 0.1
        pts += [Float(c.x), Float(c.y), Float(c.z), Float(u.x), Float(u.y), Float(u.z)]
    }
    let e = embed(simRest: sim.rest, tets: sim.tets, verts: pts)
    return EyeRig(eye: eye, glint: glint, anchorTet: e.tetOf, anchorW: e.w)
}

// MARK: - Antenna rig (Honey)

/// Three virtual points per antenna (centre, centre + up, centre + side) embedded in the sim mesh: the skinner rebuilds the
/// crown frame from them every frame and carries the whole curl rigidly with it (plus the spring wobble).
struct AntennaRig {
    var info: [AntennaInfo]
    var anchorTet: [UInt32]     // 3 per antenna
    var anchorW: [Float]        // 4 per point
    var restVerts: [Float]      // rest xyz of every render vertex (for local coordinates)
}

func buildAntennaRig(render rm: RenderMesh, sim: SimMesh) -> AntennaRig? {
    guard !rm.antennae.isEmpty else { return nil }
    var pts: [Float] = []
    for a in rm.antennae { pts += a.basePoints }
    let e = embed(simRest: sim.rest, tets: sim.tets, verts: pts)
    return AntennaRig(info: rm.antennae, anchorTet: e.tetOf, anchorW: e.w, restVerts: rm.rest)
}


// MARK: - Bob (reference form): public builders

/// Simulation mesh. Berry (Bob) uses the reference egg; Mint / Honey keep the legacy surface-of-revolution mesh.
func buildSimMesh(h: Float = 0.2, layers: Int = 7, appearance: BlobAppearance = .berry) -> SimMesh {
    appearance.breed == .berry ? buildSimMeshBob(h: h, layers: layers) : buildSimMeshLegacy(h: h, layers: layers, appearance: appearance)
}
func buildRenderMesh(appearance: BlobAppearance = .berry) -> RenderMesh {
    appearance.breed == .berry ? buildRenderMeshBob() : buildRenderMeshLegacy(appearance: appearance)
}
func buildEyeRig(render rm: RenderMesh, sim: SimMesh, appearance: BlobAppearance = .berry) -> EyeRig {
    appearance.breed == .berry ? buildEyeRigBob(render: rm, sim: sim) : buildEyeRigLegacy(render: rm, sim: sim, appearance: appearance)
}

/// Heights fractions of the sim layer levels, bottom (underside) to crown.
private func bobLevels(_ layers: Int) -> [Double] {
    if layers == 7 { return [0, 0.085, 0.22, 0.38, 0.55, 0.72, 0.88, 1.0] }
    return (0...layers).map { 1 - pow(1 - Double($0) / Double(layers), 1.35) }
}

/// Per-level hull radius for one axis: the faceted drum (polygon ring, straight chords between levels) must contain the
/// smooth egg profile `f(t)`.
private func bobHullRadii(_ ts: [Double], azimuthSegments n: Int, f: (Double) -> Double) -> [Double] {
    let az = 1 / cos(Double.pi / Double(n))
    var r = ts.map { f($0) * az }
    r[r.count - 1] = max(r[r.count - 1], 0.2)
    let margin = 0.004
    for _ in 0..<80 {
        for l in 0..<(ts.count - 1) {
            var d = 0.0
            for k in 0...48 {
                let u = Double(k) / 48
                let t = ts[l] + (ts[l + 1] - ts[l]) * u
                let chord = r[l] + (r[l + 1] - r[l]) * u
                d = max(d, f(t) * az + margin - chord)
            }
            if d > 0 { r[l] += d; r[l + 1] += d }
        }
    }
    return r
}

private func buildSimMeshBob(h hIn: Float, layers: Int) -> SimMesh {
    let h = Double(hIn)
    let nRing = max(8, 4 * Int((2 * Double.pi / h / 4).rounded()))     // multiple of 4: the lattice is mirror symmetric in x and z
    var all: [Double] = []
    for i in 0..<nRing {
        let a = 2 * Double.pi * Double(i) / Double(nRing)
        all.append(cos(a)); all.append(sin(a))
    }
    all += hexLattice(h, radius: 1) { u, w in hypot(u, w) < 1 - h * 0.55 }
    let tri2 = delaunay(all)
    var t2: [Int] = []
    var q = 0
    while q < tri2.count {
        let a = tri2[q], b = tri2[q + 1], c = tri2[q + 2]
        q += 3
        let ax = all[2 * a], ay = all[2 * a + 1], bx = all[2 * b], by = all[2 * b + 1], cx = all[2 * c], cy = all[2 * c + 1]
        let area = abs((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)) / 2
        let l2 = max((bx - ax) * (bx - ax) + (by - ay) * (by - ay), (cx - bx) * (cx - bx) + (cy - by) * (cy - by),
                     (ax - cx) * (ax - cx) + (ay - cy) * (ay - cy))
        if area / l2 > 0.12 { t2.append(contentsOf: [a, b, c]) }
    }
    var used = [Int](repeating: -1, count: all.count / 2)
    var verts2: [Double] = []
    for v in t2 where used[v] < 0 {
        used[v] = verts2.count / 2
        verts2.append(all[2 * v]); verts2.append(all[2 * v + 1])
    }
    let tris = t2.map { used[$0] }
    let n2 = verts2.count / 2
    // prism-to-tet splitting depends on a vertex order; use one that is invariant under x -> -x so the lattice stays mirror symmetric
    let order: [Int] = {
        let idx = (0..<n2).sorted { a, b in
            let ka = (abs(verts2[2 * a]).rounded(toPlaces: 5), verts2[2 * a + 1].rounded(toPlaces: 5), verts2[2 * a])
            let kb = (abs(verts2[2 * b]).rounded(toPlaces: 5), verts2[2 * b + 1].rounded(toPlaces: 5), verts2[2 * b])
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            if ka.1 != kb.1 { return ka.1 < kb.1 }
            return ka.2 < kb.2
        }
        var rank = [Int](repeating: 0, count: n2)
        for (r, v) in idx.enumerated() { rank[v] = r }
        return rank
    }()
    let ts = bobLevels(layers)
    let nL = ts.count
    let ys = ts.map { BobForm.lift + $0 * BobForm.bodyH }
    // The sim hull is a little wider than the egg right at the underside, so the feet have lattice to grow from.
    let rx = bobHullRadii(ts, azimuthSegments: nRing) { max(BobForm.halfWidth(t: $0), 0.47 * max(0, 1 - $0 / 0.1)) }
    let rz = bobHullRadii(ts, azimuthSegments: nRing) { max(BobForm.halfDepth(t: $0), 0.40 * max(0, 1 - $0 / 0.1)) }
    var rest = [Float](repeating: 0, count: n2 * nL * 3)
    for l in 0..<nL {
        for i in 0..<n2 {
            let k = (l * n2 + i) * 3
            rest[k] = Float(verts2[2 * i] * rx[l])
            rest[k + 1] = Float(ys[l])
            rest[k + 2] = Float(verts2[2 * i + 1] * rz[l])
        }
    }
    var tets: [UInt32] = []
    for l in 0..<(nL - 1) {
        var i = 0
        while i < tris.count {
            let s = [tris[i], tris[i + 1], tris[i + 2]].sorted { order[$0] < order[$1] }
            let a = l * n2 + s[0], b = l * n2 + s[1], c = l * n2 + s[2]
            let A = a + n2, B = b + n2, C = c + n2
            for v in [a, b, c, A, b, c, A, B, c, A, B, C] { tets.append(UInt32(v)) }
            i += 3
        }
    }
    var region = [UInt8](repeating: 0, count: n2 * nL)
    for l in 0..<nL {
        for i in 0..<n2 {
            let onRing = hypot(verts2[2 * i], verts2[2 * i + 1]) > 1 - 1e-6
            if onRing || l == 0 || l == nL - 1 { region[l * n2 + i] = 2 }
        }
    }
    func P(_ i: Int) -> SIMD3<Double> { SIMD3(Double(rest[3 * i]), Double(rest[3 * i + 1]), Double(rest[3 * i + 2])) }
    func addParticle(_ p: SIMD3<Double>) -> Int {
        let i = rest.count / 3
        rest.append(Float(p.x)); rest.append(Float(p.y)); rest.append(Float(p.z))
        region.append(0)
        return i
    }
    var appendages: [SimAppendage] = []

    // ── feet: four sole particles on the floor under each foot, tied to the nearest underside triangles ──
    var bottom: [(Int, Int, Int)] = []
    var bi = 0
    while bi < tris.count { bottom.append((tris[bi], tris[bi + 1], tris[bi + 2])); bi += 3 }
    func cen(_ t: (Int, Int, Int)) -> SIMD3<Double> { (P(t.0) + P(t.1) + P(t.2)) / 3 }
    // The whole underside is extruded down to the floor as one stiff slab (the same lattice extrusion as the body layers), so the
    // body stands as stably as a flat-based jelly. Only the two foot ellipses are visible: render vertices of the feet embed in
    // the slab prisms below them, the belly between the feet embeds in the body above and hangs clear of the floor.
    var soleOf: [Int: Int] = [:]
    func sole(_ v: Int) -> Int {
        if let s = soleOf[v] { return s }
        let p = P(v)
        let s = addParticle(SIMD3(p.x, 0, p.z))
        soleOf[v] = s
        return s
    }
    for t in bottom {
        let s3 = [t.0, t.1, t.2].sorted { order[$0] < order[$1] }
        let a = s3[0], b = s3[1], c = s3[2]
        let A = sole(a), B = sole(b), C = sole(c)
        for v in [a, b, c, A, b, c, A, B, c, A, B, C] { tets.append(UInt32(v)) }
    }
    for side in [-1.0, 1.0] {
        let cx = side * BobForm.footX, cz = BobForm.footZ
        var ids = Set<Int>()
        for t in bottom {
            let c = cen(t)
            let dx = (c.x - cx) / BobForm.footRadii.x, dz = (c.z - cz) / BobForm.footRadii.z
            if dx * dx + dz * dz < 1.2 { for v in [t.0, t.1, t.2] { ids.insert(soleOf[v]!) } }
        }
        appendages.append(SimAppendage(kind: .foot, side: Int(side), particles: ids.sorted()))
    }

    // ── arms: three chain particles along each teardrop, tied to the wall triangles beside them ──
    var wall: [(Int, Int, Int)] = []
    for l in 0..<(nL - 1) {
        for i in 0..<nRing {
            let j = (i + 1) % nRing
            guard used[i] >= 0, used[j] >= 0 else { continue }
            let p00 = l * n2 + used[i], p01 = l * n2 + used[j], p11 = (l + 1) * n2 + used[j], p10 = (l + 1) * n2 + used[i]
            wall.append((p00, p01, p11)); wall.append((p00, p11, p10))
        }
    }
    for side in [-1.0, 1.0] {
        let stations: [Double] = [0.0, 0.5, 1.0]
        var centres: [SIMD3<Double>] = [], apexes: [Int] = []
        for s in stations {
            var c = BobForm.armTop + (BobForm.armTip - BobForm.armTop) * s
            let r = (BobForm.armTopR + (BobForm.armTipR - BobForm.armTopR) * s)     // a little fuller than the surface so the fillet embeds
            c.x *= side
            centres.append(c)
            // three particles per station (outer, front, back) so the whole tube cross-section is covered by tets
            let rz = r / BobForm.armFlatten
            apexes.append(addParticle(c + SIMD3(side * r * 1.2, 0, 0)))
            apexes.append(addParticle(c + SIMD3(side * r * 0.25, 0, rz * 0.85)))
            apexes.append(addParticle(c + SIMD3(side * r * 0.25, 0, -rz * 0.85)))
        }
        var owned = [[(Int, Int, Int)]](repeating: [], count: 3)
        var radius = 0.22
        for _ in 0..<7 where owned.contains(where: { $0.isEmpty }) {
            owned = [[(Int, Int, Int)]](repeating: [], count: 3)
            for t in wall {
                let c = cen(t)
                guard c.x * side > 0.1 else { continue }
                var best = -1, bd = Double.infinity
                for (k, sc) in centres.enumerated() { let d = simd_distance(c, sc); if d < bd { bd = d; best = k } }
                if bd < radius { owned[best].append(t) }
            }
            radius *= 1.4
        }
        for k in 0..<3 { for t in owned[k] { for j in 0..<3 { tets.append(contentsOf: [UInt32(t.0), UInt32(t.1), UInt32(t.2), UInt32(apexes[3 * k + j])]) } } }
        appendages.append(SimAppendage(kind: .arm, side: Int(side), particles: apexes))
    }

    var t = 0
    while t < tets.count {
        if tetVolume(rest, Int(tets[t]), Int(tets[t + 1]), Int(tets[t + 2]), Int(tets[t + 3])) < 0 { tets.swapAt(t + 2, t + 3) }
        t += 4
    }
    return SimMesh(rest: rest, tets: tets, region: region, n2: n2, layers: nL - 1, appendages: appendages)
}

// MARK: Surface nets

/// Isosurface (f = 0) of `f` on a regular grid: one vertex per sign-changing cell, one quad per sign-changing edge.
/// Blocks far from the surface are skipped (filled with the sign of their centre value).
private func surfaceNets(cell h: Double, lo: SIMD3<Double>, hi: SIMD3<Double>, f: (SIMD3<Double>) -> Double)
    -> (pos: [SIMD3<Double>], tri: [UInt32]) {
    let nx = Int(ceil((hi.x - lo.x) / h)) + 1, ny = Int(ceil((hi.y - lo.y) / h)) + 1, nz = Int(ceil((hi.z - lo.z) / h)) + 1
    var val = [Double](repeating: 0, count: nx * ny * nz)
    @inline(__always) func gi(_ i: Int, _ j: Int, _ k: Int) -> Int { i + nx * (j + ny * k) }
    func at(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Double> { lo + SIMD3(Double(i), Double(j), Double(k)) * h }
    let B = 4
    var bk = 0
    while bk < nz { var bj = 0
        while bj < ny { var bi = 0
            while bi < nx {
                let ei = min(bi + B, nx), ej = min(bj + B, ny), ek = min(bk + B, nz)
                let c = f(at(bi, bj, bk) + SIMD3(repeating: Double(B) * h * 0.5))
                if abs(c) > 0.24 {
                    for k in bk..<ek { for j in bj..<ej { for i in bi..<ei { val[gi(i, j, k)] = c } } }
                } else {
                    for k in bk..<ek { for j in bj..<ej { for i in bi..<ei { val[gi(i, j, k)] = f(at(i, j, k)) } } }
                }
                bi += B }
            bj += B }
        bk += B }
    var cellV = [Int32](repeating: -1, count: nx * ny * nz)
    var pos: [SIMD3<Double>] = []
    let corner: [(Int, Int, Int)] = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0), (0, 0, 1), (1, 0, 1), (0, 1, 1), (1, 1, 1)]
    let edges: [(Int, Int)] = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]
    for k in 0..<(nz - 1) { for j in 0..<(ny - 1) { for i in 0..<(nx - 1) {
        var v = [Double](repeating: 0, count: 8)
        var neg = 0
        for c in 0..<8 { v[c] = val[gi(i + corner[c].0, j + corner[c].1, k + corner[c].2)]; if v[c] < 0 { neg += 1 } }
        if neg == 0 || neg == 8 { continue }
        var sum = SIMD3<Double>(repeating: 0); var cnt = 0.0
        for (a, b) in edges where (v[a] < 0) != (v[b] < 0) {
            let tt = v[a] / (v[a] - v[b])
            let pa = at(i + corner[a].0, j + corner[a].1, k + corner[a].2), pb = at(i + corner[b].0, j + corner[b].1, k + corner[b].2)
            sum += pa + (pb - pa) * tt; cnt += 1
        }
        cellV[gi(i, j, k)] = Int32(pos.count)
        pos.append(sum / cnt)
    } } }
    var tri: [UInt32] = []
    for k in 0..<nz { for j in 0..<ny { for i in 0..<nx {
        let v0 = val[gi(i, j, k)] < 0
        for axis in 0..<3 {
            let ni = i + (axis == 0 ? 1 : 0), nj = j + (axis == 1 ? 1 : 0), nk = k + (axis == 2 ? 1 : 0)
            guard ni < nx, nj < ny, nk < nz, (val[gi(ni, nj, nk)] < 0) != v0 else { continue }
            let bA = (axis + 1) % 3, cA = (axis + 2) % 3
            let p = [i, j, k]
            var quad: [Int32] = []
            for (db, dc) in [(-1, -1), (0, -1), (0, 0), (-1, 0)] {
                var c = p
                c[bA] += db; c[cA] += dc
                guard c[0] >= 0, c[1] >= 0, c[2] >= 0, c[0] < nx - 1, c[1] < ny - 1, c[2] < nz - 1 else { break }
                quad.append(cellV[gi(c[0], c[1], c[2])])
            }
            guard quad.count == 4, !quad.contains(-1) else { continue }
            tri += [UInt32(quad[0]), UInt32(quad[1]), UInt32(quad[2]), UInt32(quad[0]), UInt32(quad[2]), UInt32(quad[3])]
        }
    } } }
    return (pos, tri)
}

// MARK: Render mesh

private func buildRenderMeshBob() -> RenderMesh {
    var pos: [Double] = [], nrm: [Double] = [], mat: [Float] = []
    var idx: [UInt32] = []
    @discardableResult
    func add(_ p: SIMD3<Double>, _ n: SIMD3<Double>, _ m: Float) -> Int {
        pos += [p.x, p.y, p.z]; nrm += [n.x, n.y, n.z]; mat.append(m)
        return pos.count / 3 - 1
    }
    func tri(_ a: Int, _ b: Int, _ c: Int) { idx.append(UInt32(a)); idx.append(UInt32(b)); idx.append(UInt32(c)) }

    // body: surface nets of the SDF, relaxed and reprojected onto the surface
    let net = surfaceNets(cell: 0.02, lo: SIMD3(-0.95, -0.06, -0.70), hi: SIMD3(0.95, 1.42, 0.70), f: BobForm.sdf)
    var P = net.pos
    var nbr = [[Int32]](repeating: [], count: P.count)
    var ti = 0
    while ti < net.tri.count {
        let a = Int(net.tri[ti]), b = Int(net.tri[ti + 1]), c = Int(net.tri[ti + 2])
        nbr[a] += [Int32(b), Int32(c)]; nbr[b] += [Int32(a), Int32(c)]; nbr[c] += [Int32(a), Int32(b)]
        ti += 3
    }
    for _ in 0..<3 {
        var Q = P
        for v in 0..<P.count where !nbr[v].isEmpty {
            var s = SIMD3<Double>(repeating: 0)
            for n in nbr[v] { s += P[Int(n)] }
            Q[v] = P[v] * 0.4 + (s / Double(nbr[v].count)) * 0.6
        }
        for v in 0..<Q.count { Q[v] = BobForm.project(Q[v], steps: 3) }
        P = Q
    }
    for v in 0..<P.count {
        P[v].y = max(P[v].y, 0)
        let n = BobForm.normal(P[v])
        add(P[v], n, Float(0.4 * BobForm.occlusion(P[v], n)))      // body: baked crease occlusion in `mat` (0...0.4)
    }
    idx = net.tri

    // wave arm capsules (one per side, appended to the body range): hidden inside the rest skin until a wave runs
    // (see ArmPath.swift / ArmKeyframes.swift). `rest` holds the hidden position (used for the sim embedding); the renderer's
    // static `rest` stream (crinkle texture) is replaced by the matching point on the REST cone (ArmCapsule.restStream).
    var capFirst: [Int] = []
    let capIndexFirst = idx.count
    for sigma in [-1.0, 1.0] {
        let first = pos.count / 3
        capFirst.append(first)
        let inactive = ArmCapsule.inactive(sigma: sigma)
        let restPts = ArmCapsule.points(.rest, inflate: 0, sigma: sigma)
        for i in 0..<ArmCapsule.vertexCount { add(inactive[i], restPts.nrm[i], 0) }
        idx += ArmCapsule.triangles(firstVertex: first)
        // the foot bean of the same side, in the same block: [arm capsule, bean] (hidden deep inside the belly until he moves his feet)
        let beanFirst = pos.count / 3
        let hidden = FootBean.inactive(sigma: sigma)
        for i in 0..<FootBean.vertexCount { add(hidden[i], FootBean.local.nrm[i], FootBean.mat[i]) }
        idx += FootBean.triangles(firstVertex: beanFirst)
    }
    // Pip's tail (TailBean): after the foot beans, still in the body index range; skinned like the body, collapsed for every Jelly but Pip (Skinner)
    let tailFirst = pos.count / 3
    for i in 0..<TailBean.vertexCount { add(TailBean.local.pos[i], TailBean.local.nrm[i], 0) }
    idx += TailBean.triangles(firstVertex: tailFirst)
    let bodyIndexCount = idx.count

    // decals: footprints in the x-y plane, projected onto the front surface
    func decal(cx: Double, cy: Double, a: Double, b: Double, pw: Double, du: Double = 0, dv: Double = 0,
               lift: Double, bump: Double, m: Float, capsule: Bool = false, tilt: Double = 0) {
        let nR = 6, nA = 40
        func height(_ rho: Double) -> Double { lift + bump * sqrt(max(0, 1 - rho * rho)) }
        func point(_ rho: Double, _ ang: Double, _ hh: Double) -> (SIMD3<Double>, SIMD3<Double>) {
            let c = cos(ang), s = sin(ang), e = 2 / pw
            var u = du + a * rho * (c < 0 ? -1 : 1) * pow(abs(c), e)
            var v = dv + b * rho * (s < 0 ? -1 : 1) * pow(abs(s), e)
            var hh = hh
            var rr = rho
            var gu = u / (a * a), gv = v / (b * b)
            if capsule {
                // stadium footprint (half length a, half thickness b): flat sides, round caps; rod-like height profile
                let L = max(a - b, 0)
                // boundary point by perimeter parameter (even sampling around the round caps): right cap, top, left cap, bottom
                let per = 4 * L + 2 * Double.pi * b
                let sp = (ang / (2 * Double.pi)) * per
                var bx = 0.0, by = 0.0
                let cap = Double.pi * b
                if sp < cap { let th = -Double.pi / 2 + sp / b; bx = L + b * cos(th); by = b * sin(th) }
                else if sp < cap + 2 * L { bx = L - (sp - cap); by = b }
                else if sp < 2 * cap + 2 * L { let th = Double.pi / 2 + (sp - cap - 2 * L) / b; bx = -L + b * cos(th); by = b * sin(th) }
                else { bx = -L + (sp - 2 * cap - 2 * L); by = -b }
                u = du + rho * bx; v = dv + rho * by
                let sx = min(max(u - du, -L), L)
                let ex = u - du - sx, ey = v - dv
                let dist = hypot(ex, ey)
                rr = min(dist / b, 1)
                if hh > 0 { hh = lift + bump * sqrt(max(0, 1 - rr * rr)) }      // (hh < 0 marks the skirt ring)
                gu = dist > 1e-9 ? ex / dist * dist / (b * b) : 0; gv = dist > 1e-9 ? ey / dist * dist / (b * b) : 0
            }
            if tilt != 0 { v += tilt * (cx > 0 ? -(u - du) : (u - du)) }          // inner end up by atan(tilt)
            let sp = BobForm.frontSurface(x: cx + u, y: cy + v)
            let ns = BobForm.normal(sp)
            // dome normal of the raised bead: tilt the surface normal away from the footprint centre
            let q = sqrt(max(1 - rr * rr, 0.05))
            let hu = -4.5 * bump * gu / q, hv = -4.5 * bump * gv / q      // exaggerated bead shading slope
            let tu = simd_normalize(SIMD3(1, 0, 0) - ns * ns.x), tv = simd_normalize(SIMD3(0, 1, 0) - ns * ns.y)
            let n = bump > 0.0045 ? simd_normalize(ns - tu * hu - tv * hv) : ns
            return (sp + ns * hh, n)
        }
        let c0 = point(0, 0, height(0))
        let centre = add(c0.0, c0.1, m)
        var rings: [Int] = []
        for i in 1...nR {
            let rho = Double(i) / Double(nR)
            rings.append(pos.count / 3)
            for j in 0..<nA { let q = point(rho, 2 * Double.pi * Double(j) / Double(nA), height(rho)); add(q.0, q.1, m) }
        }
        let skirt = pos.count / 3
        for j in 0..<nA { let q = point(1, 2 * Double.pi * Double(j) / Double(nA), -0.012); add(q.0, q.1, m) }
        for j in 0..<nA { tri(centre, rings[0] + j, rings[0] + (j + 1) % nA) }
        for i in 0..<(nR - 1) {
            for j in 0..<nA {
                let a0 = rings[i] + j, b0 = rings[i] + (j + 1) % nA, c1 = rings[i + 1] + j, d0 = rings[i + 1] + (j + 1) % nA
                tri(a0, c1, b0); tri(b0, c1, d0)
            }
        }
        for j in 0..<nA {
            let a0 = rings[nR - 1] + j, b0 = rings[nR - 1] + (j + 1) % nA, c1 = skirt + j, d0 = skirt + (j + 1) % nA
            tri(a0, c1, b0); tri(b0, c1, d0)
        }
    }
    let seedStart = idx.count
    for sgn in [-1.0, 1.0] {
        decal(cx: sgn * BobForm.eyeX, cy: BobForm.eyeY, a: BobForm.eyeHalfW, b: BobForm.eyeHalfH, pw: 2, lift: 0.003, bump: 0.022, m: 1)
    }
    for sgn in [-1.0, 1.0] {
        let gu = -0.36 * BobForm.eyeHalfW, gv = 0.40 * BobForm.eyeHalfH
        let rho = hypot(-0.36, 0.40)
        let hEye = 0.003 + 0.012 * sqrt(max(0, 1 - rho * rho))
        decal(cx: sgn * BobForm.eyeX, cy: BobForm.eyeY, a: 0.005, b: 0.005, pw: 2, du: gu, dv: gv, lift: hEye + 0.0005, bump: 0.003, m: 3)
    }
    for sgn in [-1.0, 1.0] {
        decal(cx: sgn * BobForm.eyeX, cy: BobForm.browY, a: BobForm.browHalfLen, b: BobForm.browHalfThick, pw: 4.5,
              lift: 0.002, bump: 0.011, m: 4, capsule: true, tilt: BobForm.browTilt)
    }
    let seedCount = idx.count - seedStart

    var i = 0
    while i < idx.count {
        let a = Int(idx[i]), b1 = Int(idx[i + 1]), c = Int(idx[i + 2])
        let e1 = SIMD3(pos[3 * b1] - pos[3 * a], pos[3 * b1 + 1] - pos[3 * a + 1], pos[3 * b1 + 2] - pos[3 * a + 2])
        let e2 = SIMD3(pos[3 * c] - pos[3 * a], pos[3 * c + 1] - pos[3 * a + 1], pos[3 * c + 2] - pos[3 * a + 2])
        let fn = simd_cross(e1, e2)
        var d = 0.0
        for v in [a, b1, c] { d += simd_dot(fn, SIMD3(nrm[3 * v], nrm[3 * v + 1], nrm[3 * v + 2])) }
        if d < 0 { idx[i + 1] = UInt32(c); idx[i + 2] = UInt32(b1) }
        i += 3
    }
    return RenderMesh(
        rest: pos.map { Float($0) }, restNormal: nrm.map { Float($0) }, mat: mat, index: idx,
        body: (0, bodyIndexCount), seeds: (seedStart, seedCount), bubbles: (idx.count, 0), seedCount: 2, antennae: [],
        armCapsule: ArmCapsuleInfo(firstVertex: capFirst, indexFirst: capIndexFirst, indexCount: bodyIndexCount - capIndexFirst, tailFirst: tailFirst))
}

private func buildEyeRigBob(render rm: RenderMesh, sim: SimMesh) -> EyeRig {
    var eye: [[Int32]] = [[], []], glint: [[Int32]] = [[], []], brow: [[Int32]] = [[], []]
    var sum = [SIMD3<Double>](repeating: .zero, count: 2), cnt = [0, 0]
    for v in 0..<rm.vertexCount where rm.mat[v] == 1 || rm.mat[v] == 3 || rm.mat[v] == 4 {
        let s = rm.rest[3 * v] < 0 ? 0 : 1
        switch rm.mat[v] {
        case 1:
            eye[s].append(Int32(v)); cnt[s] += 1
            sum[s] += SIMD3(Double(rm.rest[3 * v]), Double(rm.rest[3 * v + 1]), Double(rm.rest[3 * v + 2]))
        case 3: glint[s].append(Int32(v))
        default: brow[s].append(Int32(v))
        }
    }
    var pts: [Float] = []
    for s in 0..<2 {
        let c = sum[s] / Double(max(cnt[s], 1))
        let n = BobForm.normal(c)
        let y = SIMD3<Double>(0, 1, 0)
        let up = simd_normalize(y - n * simd_dot(y, n))
        let u = c + up * 0.1
        pts += [Float(c.x), Float(c.y), Float(c.z), Float(u.x), Float(u.y), Float(u.z)]
    }
    let e = embed(simRest: sim.rest, tets: sim.tets, verts: pts)
    return EyeRig(eye: eye, glint: glint, anchorTet: e.tetOf, anchorW: e.w, brow: brow)
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double { let m = pow(10.0, Double(p)); return (self * m).rounded() / m }
}
