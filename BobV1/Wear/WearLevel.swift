//
//  WearLevel.swift
//  Encircling wearables (a bandana string, a sweatband, a bow-tie band, a scarf wrap, a necklace string, a waistband, a collar ...) must read as a straight, level
//  loop round the body, whatever the skin underneath does. Bound to a single skin triangle they rode its jiggle (a wavy string), the neck lift raised the sides
//  into a U, and the limb push slid a vertex up or down the wall around an arm (a dip).
//
//  Here such a part is LEVELLED: every vertex keeps its authored height and its azimuth round the body's own vertical axis (x = 0, z = WearBody.axisZ, in the rest
//  frame the carry maps to the world), and only its RADIUS follows the current skin (the skin's radius under it, plus the authored stand-off). The loop therefore
//  tilts with the body as a whole and never waves. Where a limb is out at the loop's height, the loop clears it by a smooth, symmetric RADIAL bulge (the same
//  outward amount over a window of azimuth, falling off C1-smoothly), never vertically.
//
//  What is levelled: the vertices of every thin, bound, non-hanging ring part (azimuth coverage >= 24/36 bins, height span <= 0.21) and, for the rest of that piece,
//  every bound vertex (a bandana's cloth and knot, a scarf's tails, a necklace's pearls and pendant), so the hanging bits stay attached to their loop. Small
//  rigid parts (pearl, link, knot, dot) are levelled by their centre and stay rigid. A future item with such a part inherits all of this through `classify`.
//

import simd
import Foundation

nonisolated enum WearLevel {
    nonisolated(unsafe) static var enabled = ProcessInfo.processInfo.environment["WEARBAND_LEVEL"] != "off"
    /// Bulge mode: true = the loop leaves an arm by a radial bulge; false = it passes the arm (the arm is drawn over it).
    nonisolated(unsafe) static var bulge = ProcessInfo.processInfo.environment["WEARBAND_MODE"] != "pass"
    /// Half-width of the bulge (rad of azimuth) and its vertical reach (m): the smooth window every limb clearance is spread over.
    static let window: Float = 0.62, reachY: Float = 0.16
    /// Radius (m) over which the skin radius is dilated and averaged; a clearance up to `bulgeFull` is bulged around fully, beyond `bulgeNone` the limb is left to pass (an arm
    /// pointing straight out would need a tent as long as the arm): the amount fades smoothly between them.
    static let neighbourhood: Float = 0.06, bulgeFull: Float = 0.07, bulgeNone: Float = 0.15

    // MARK: the necklace tilt
    /// Necklace-class pieces (chains, pearl strings, the Diamond J) are kept on a TILTED loop in the body frame instead of a level one. The front centre keeps its authored height
    /// (`WearPrepared.tiltFrontY`: the pendant does not move on the chest); from `tiltFrom` rad of azimuth off the front (just past the mouth keep-out) the loop rises smoothly (C1,
    /// smoothstep) to `tiltSideY` over the arm tops (complete at `tiltSideAt`, the arm roots), and on to `tiltBackY` at the very back (slightly higher than at the sides). Over the
    /// rising part the authored height variation fades out (the art was drawn with its own sag) so every body sees the same clean curve. Bands, scarves, collars and waistbands stay level.
    nonisolated(unsafe) static var tiltOn = ProcessInfo.processInfo.environment["WEARBAND_TILT"] != "off"
    /// Absolute loop heights (m, body frame) at the sides (the arm tops reach ~0.605; a link's radius is ~1.5 cm) and at the back.
    nonisolated(unsafe) static var tiltSideY: Float = 0.645, tiltBackY: Float = 0.665
    static let tiltFrom: Float = 0.44, tiltSideAt: Float = 1.48
    /// The inner edge of a rigid link / gem / pearl is brought to this distance (m) from the skin at rest (the chain hugs the body).
    static let hugGap: Float = 0.002
    static func tilts(_ l: WearLook) -> Bool { tiltOn && (l == .chainGold || l == .diamondJ || l == .pearls) }
    @inline(__always) private static func smooth(_ x: Float) -> Float { let u = min(max(x, 0), 1); return u * u * (3 - 2 * u) }
    /// 0 at the front (up to `tiltFrom`), 1 from the arm roots round the back.
    static func tiltWeight(az: Float) -> Float { smooth((abs(az) - tiltFrom) / (tiltSideAt - tiltFrom)) }
    /// The height of the tilted loop at azimuth `az` (0 = front centre, +-pi = back centre) for a loop whose front centre is at `yFront`.
    static func loopY(az: Float, yFront: Float) -> Float {
        let w1 = tiltWeight(az: az), w2 = smooth((abs(az) - tiltSideAt) / (Float.pi - tiltSideAt))
        return yFront + (tiltSideY - yFront) * w1 + (tiltBackY - tiltSideY) * w2
    }
    /// Where a point authored at height `y0` and azimuth `az` goes: a hanging part (a pendant) keeps its authored offset below the loop point; the loop itself fades its authored sag out.
    static func targetY(y0: Float, az: Float, yFront: Float, hanging: Bool) -> Float {
        let rise = loopY(az: az, yFront: yFront) - yFront
        return hanging ? y0 + rise : yFront + rise + (y0 - yFront) * (1 - tiltWeight(az: az))
    }

    /// Tests: when set, `emit` records per vertex of the last piece how far the bulge moved it (`recBulge`) and how far the limb would have had to be cleared (`recRaw`; >= `bulgeFull` = an arm swallows it and is drawn over it).
    nonisolated(unsafe) static var record = false
    nonisolated(unsafe) static var recBulge: [Float] = [], recRaw: [Float] = []
    static let bins = 36, minBins = 24, maxSpan: Float = 0.21

    /// Finds the encircling parts of a prepared piece (before any lift) and flags the vertices to level. Sets `levelPiece`, `level`, `lvY0`.
    static func classify(_ p: WearPrepared, body: WearBody) {
        let n = p.rest.count
        p.level = [Bool](repeating: false, count: n); p.lvY0 = p.rest.map(\.y)
        p.lvDir = [SIMD2<Float>](repeating: .zero, count: n); p.lvExcess = [Float](repeating: 0, count: n)
        p.clusterLevel = [Bool](repeating: false, count: p.partNames.count)
        p.clusterY0 = [Float](repeating: 0, count: p.partNames.count); p.clusterDir = [SIMD2<Float>](repeating: .zero, count: p.partNames.count); p.clusterExcess = [Float](repeating: 0, count: p.partNames.count)
        p.levelPiece = false
        guard enabled, p.anyBound else { return }
        let zc = body.axisZ
        func bin(_ q: SIMD3<Float>) -> Int { min(bins - 1, Int((atan2(q.x, q.z - zc) + .pi) / (2 * .pi) * Float(bins))) }
        var byPart = [[Int]](repeating: [], count: p.partNames.count)
        for i in 0..<n where Int(p.partOfVertex[i]) < byPart.count { byPart[Int(p.partOfVertex[i])].append(i) }
        var ring = false
        var smallBins = Set<Int>(), smallCount = 0
        p.lvRing = [Bool](repeating: false, count: n)
        for vs in byPart where vs.count >= 8 {
            guard vs.allSatisfy({ p.w[$0] > 0.99 && p.h[$0] == 0 }) else { continue }
            var c = SIMD3<Float>.zero, lo = Float.infinity, hi = -Float.infinity
            for v in vs { c += p.rest[v]; lo = min(lo, p.rest[v].y); hi = max(hi, p.rest[v].y) }
            c /= Float(vs.count)
            if vs.allSatisfy({ simd_distance(p.rest[$0], c) <= 0.07 }) { smallBins.insert(bin(c)); smallCount += 1; continue }
            if vs.allSatisfy({ simd_distance(p.rest[$0], c) <= 0.12 }) { smallBins.insert(bin(c)); smallCount += 1 }                  // (a chain link: counts for the chain, is levelled per vertex)
            var b = Set<Int>()
            for v in vs { b.insert(bin(p.rest[v])) }
            if b.count >= minBins, hi - lo <= maxSpan { ring = true; for v in vs { p.lvRing[v] = true } }
        }
        let chain = smallCount >= 8 && smallBins.count >= minBins
        guard ring || chain else { return }
        p.levelPiece = true
        for i in 0..<n where p.w[i] > 0.001 { p.level[i] = true }
    }

    /// After the clusters are found: each levelled vertex's azimuth direction, its authored height and its stand-off outside the REST skin at that same height and azimuth
    /// (the skin point is found by a radial ray, so the loop never rides a lift up the wall); `lvBind` is that skin point, bound for the runtime.
    static func finalize(_ p: WearPrepared, body: WearBody) {
        guard p.levelPiece else { return }
        let zc = body.axisZ
        let floorOff: Float = -0.004                                            // (as the old seat: a string may sit 4 mm into the skin)
        /// The stand-off is read at the AUTHORED height (it is the piece's own thickness), the skin point it is bound to at the loop's (tilted) height.
        func dirExcess(_ r: SIMD3<Float>, hang: Bool, fallback: SurfaceBind) -> (dir: SIMD2<Float>, excess: Float, bind: SurfaceBind) {
            let o = SIMD2(r.x, r.z - zc), l = max(simd_length(o), 1e-5), d = o / l
            let lift = lifted(r, hang: hang)
            if let h = body.radialHit(dir: d, y: r.y) {
                if lift != 0, let h2 = body.radialHit(dir: d, y: r.y + lift) { return (d, max(l - h.rho, floorOff), h2.bind) }
                return (d, max(l - h.rho, floorOff), h.bind)
            }
            let f = body.restFoot(fallback)
            return (d, l - simd_length(SIMD2(f.x, f.z - zc)), fallback)
        }
        // the tilted loop: where its front centre is (the mean authored height of the loop's own, non-hanging vertices within 0.3 rad of the front)
        if p.tilted {
            var sum: Float = 0, cnt: Float = 0
            for i in 0..<p.rest.count where p.level[i] && p.h[i] == 0 && abs(atan2(p.rest[i].x, p.rest[i].z - zc)) < 0.3 { sum += p.rest[i].y; cnt += 1 }
            p.tiltFrontY = cnt > 0 ? sum / cnt : p.pivot.y
        }
        /// How far the tilt moves a point authored at `q` (0 for a level piece).
        func lifted(_ q: SIMD3<Float>, hang: Bool) -> Float { p.tilted ? targetY(y0: q.y, az: atan2(q.x, q.z - zc), yFront: p.tiltFrontY, hanging: hang) - q.y : 0 }
        p.lvBind = [SurfaceBind](repeating: SurfaceBind(), count: p.rest.count)
        p.clusterLvBind = [SurfaceBind](repeating: SurfaceBind(), count: p.partNames.count)
        for i in 0..<p.rest.count where p.level[i] {
            let hang = p.h[i] > 0
            let r = dirExcess(p.rest[i], hang: hang, fallback: p.bind[i]); p.lvDir[i] = r.dir; p.lvExcess[i] = r.excess; p.lvBind[i] = r.bind; p.lvY0[i] = p.rest[i].y + lifted(p.rest[i], hang: hang)
        }
        if p.tilted {
            // a chain link that is levelled per vertex (too big to be a rigid cluster) hugs too: its whole vertex set moves in by what its innermost vertex stands off the skin
            for k in p.partNames.indices where p.partNames[k].hasPrefix("link") && !(p.clusterRep.indices.contains(k) && p.clusterRep[k] >= 0) {
                let vs = (0..<p.rest.count).filter { Int(p.partOfVertex[$0]) == k && p.level[$0] && p.h[$0] == 0 }
                guard vs.count >= 8, let lo = vs.map({ p.lvExcess[$0] }).min(), lo > hugGap else { continue }
                for v in vs { p.lvExcess[v] = max(p.lvExcess[v] - (lo - hugGap), floorOff) }
            }
        }
        for k in p.partNames.indices where p.clusterRep.indices.contains(k) && p.clusterRep[k] >= 0 && p.level[Int(p.clusterRep[k])] {
            let c = p.clusterCentre[k]
            let hang = p.h[Int(p.clusterRep[k])] > 0
            let r = dirExcess(c, hang: hang, fallback: p.clusterBind[k])
            var excess = r.excess
            if p.tilted {
                // hug: the rigid part's inner edge (its lowest vertex above the rest skin, radially) is brought to `hugGap` from the skin; it is never pushed further out than authored
                // (measured where the part ends up: raised by the tilt, the part rides the rest skin at its new height - on the sloping shoulder too)
                let lift = lifted(c, hang: hang)
                let lc = simd_length(SIMD2(c.x, c.z - zc))
                if !hang, let hc = body.radialHit(dir: r.dir, y: c.y + lift) {
                    var low = Float.infinity                                          // (how far the lowest vertex of the part sits outside the skin when the centre stands ON the skin)
                    for v in 0..<p.rest.count where Int(p.partOfVertex[v]) == k {
                        let o = SIMD2(p.rest[v].x, p.rest[v].z - zc), l = simd_length(o)
                        guard l > 1e-4, let h = body.radialHit(dir: o / l, y: p.rest[v].y + lift) else { continue }
                        low = min(low, hc.rho + (l - lc) - h.rho)
                    }
                    if low.isFinite { excess = min(excess, max(hugGap - low, floorOff)) }
                }
            }
            p.clusterLevel[k] = true; p.clusterDir[k] = r.dir; p.clusterExcess[k] = excess; p.clusterLvBind[k] = r.bind; p.clusterY0[k] = c.y + lifted(c, hang: hang)
        }
        // the nodes: levelled vertices outside the rigid small parts, plus each rigid small part's centre
        p.nodeVertex = []; p.nodeCluster = []; p.nodeBind = []; p.nodeY0 = []; p.nodeDir = []; p.nodeRho0 = []
        p.lvNode = [Int32](repeating: -1, count: p.rest.count); p.clusterNode = [Int32](repeating: -1, count: p.partNames.count)
        var pos: [SIMD3<Float>] = []
        for k in p.partNames.indices where p.clusterLevel[k] {
            p.clusterNode[k] = Int32(p.nodeBind.count)
            p.nodeVertex.append(-1); p.nodeCluster.append(Int32(k)); p.nodeBind.append(p.clusterLvBind[k]); p.nodeY0.append(p.clusterY0[k]); p.nodeDir.append(p.clusterDir[k]); pos.append(p.clusterCentre[k] + SIMD3(0, lifted(p.clusterCentre[k], hang: p.h[Int(p.clusterRep[k])] > 0), 0))
        }
        for i in 0..<p.rest.count where p.level[i] {
            let k = Int(p.partOfVertex[i])
            if p.clusterLevel.indices.contains(k), p.clusterLevel[k] { continue }
            p.lvNode[i] = Int32(p.nodeBind.count)
            p.nodeVertex.append(Int32(i)); p.nodeCluster.append(-1); p.nodeBind.append(p.lvBind[i]); p.nodeY0.append(p.lvY0[i]); p.nodeDir.append(p.lvDir[i]); pos.append(p.rest[i] + SIMD3(0, lifted(p.rest[i], hang: p.h[i] > 0), 0))
        }
        for b in p.nodeBind { let f = body.restFoot(b); p.nodeRho0.append(simd_length(SIMD2(f.x, f.z - zc))) }          // (the rest skin radius under each node)
        // neighbours (a uniform grid on the authored positions)
        let R = neighbourhood
        p.nodeNbr = [[Int32]](repeating: [], count: pos.count)
        var grid: [SIMD3<Int32>: [Int32]] = [:]
        func cell(_ q: SIMD3<Float>) -> SIMD3<Int32> { SIMD3(Int32((q.x / R).rounded(.down)), Int32((q.y / R).rounded(.down)), Int32((q.z / R).rounded(.down))) }
        for (j, q) in pos.enumerated() { grid[cell(q), default: []].append(Int32(j)) }
        for (j, q) in pos.enumerated() {
            let c0 = cell(q)
            var out: [(Float, Int32)] = []
            for dz in -1...1 { for dy in -1...1 { for dx in -1...1 {
                for m in grid[SIMD3(c0.x + Int32(dx), c0.y + Int32(dy), c0.z + Int32(dz))] ?? [] {
                    let d = simd_distance(q, pos[Int(m)])
                    if d < R { out.append((d, m)) }
                }
            } } }
            out.sort { $0.0 < $1.0 }
            p.nodeNbr[j] = out.prefix(64).map { $0.1 }
            if !p.nodeNbr[j].contains(Int32(j)) { p.nodeNbr[j].append(Int32(j)) }
        }
    }

    /// The skin's radius (about the body axis, in the body frame) at the node's height, from its current skin point carried along the skin's slope; dilated then averaged over the
    /// node's neighbours, so the loop is a clean curve above the skin's ripple and never dips under it.
    static func skinRadii(_ p: WearPrepared, skin: UnsafePointer<Float>, zc: Float, carry c: EyeMaskModel.Carry, M: simd_float3x3, Minv: simd_float3x3) -> [Float] {
        let n = p.nodeBind.count
        var raw = [Float](repeating: 0, count: n)
        for j in 0..<n {
            let (foot, nW) = WearBody.worldWithNormal(p.nodeBind[j], skin: skin)
            let b = Minv * (foot - c.centroid) + c.restCentroid
            var rho = simd_length(SIMD2(b.x, b.z - zc))
            // the radius at the node's own height and azimuth: where the skin's tangent plane at the foot meets the horizontal line there (carries the foot back
            // along a ripple, up or down the wall AND sideways round it)
            let nb = M.transpose * nW, d = p.nodeDir[j]
            let nd = nb.x * d.x + nb.z * d.y
            let t = min(max((abs(nd) - 0.15) / 0.25, 0), 1)                          // (blended in smoothly: a plane that is nearly vertical is no use)
            if t > 0 {
                let num = nb.x * b.x + nb.z * (b.z - zc) - nb.y * (p.nodeY0[j] - b.y)
                let plane = max(-0.07, min(0.07, num / (abs(nd) > 1e-3 ? nd : 1e-3) - rho))
                rho += t * t * (3 - 2 * t) * plane
            }
            raw[j] = max(p.nodeRho0[j] - 0.06, min(p.nodeRho0[j] + 0.06, rho))          // (a ring never strays more than 6 cm from the rest skin radius: a hem on the steep underside cannot sink)
        }
        // what is smoothed is the CHANGE of the skin's radius from its rest value (so the rest shape is exact and a steep wall - the head - is not flared): dilated (never under any
        // neighbour's skin) then averaged over the neighbours
        var delta = raw
        for j in 0..<n { delta[j] = raw[j] - p.nodeRho0[j] }
        var dil = delta
        // (a necklace HUGS the skin: it is only averaged, not dilated to the highest skin bump within reach - the dilation would hold it up to 2 cm off the chest while the belly squashes)
        if !p.tilted { for j in 0..<n { var m = delta[j]; for k in p.nodeNbr[j] { m = max(m, delta[Int(k)]) }; dil[j] = m } }
        var out = dil
        for j in 0..<n { var s: Float = 0; for k in p.nodeNbr[j] { s += dil[Int(k)] }; out[j] = p.nodeRho0[j] + s / Float(max(p.nodeNbr[j].count, 1)) }
        return out
    }

    /// The levelled world position: authored height `y`, azimuth `dir`, radius `rho` (the skin's radius there + the stand-off), through the carry.
    @inline(__always)
    static func position(rho: Float, y: Float, dir: SIMD2<Float>, zc: Float, carry c: EyeMaskModel.Carry, M: simd_float3x3) -> SIMD3<Float> {
        let r = max(rho, 0.01)
        return c.centroid + M * (SIMD3<Float>(dir.x * r, y, zc + dir.y * r) - c.restCentroid)
    }
    /// Fade of a limb clearance: 1 up to `bulgeFull`, 0 from `bulgeNone` (smoothstep).
    @inline(__always) static func fade(_ e: Float) -> Float { let u = min(max((e - bulgeFull) / (bulgeNone - bulgeFull), 0), 1); return 1 - u * u * (3 - 2 * u) }

    /// C1-smooth window: 1 at 0, 0 at and beyond `w`.
    @inline(__always) static func bump(_ d: Float, _ w: Float) -> Float { let u = min(abs(d) / w, 1); let v = 1 - u * u; return v * v }
}
