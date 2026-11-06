//
//  WearMeshes.swift
//  The Blender wardrobe, loaded from the bundled wear_<id>.bin files (tools/convert_wear_art.py) and prepared ONCE per look for the game:
//  one flat vertex list in the artist's anchor-relative rest space, plus per vertex how it is carried (WearRules.rule): a surface bind to the rest egg
//  (WearBody), a surface weight `w` (1 = pinned to the skin, 0 = carried rigidly by the body pose), a swing weight `h` (hanging parts) and a spin flag.
//  The Circuit bib is prepared per team colour and race number (the digit meshes placed on the plate).
//

import simd
import Foundation

nonisolated final class WearPrepared: @unchecked Sendable {
    let look: WearLook
    /// Rest-space positions (anchor + offset; for gloves the arm-local offsets), normals, linear colours, baked AO.
    var rest: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], col: [SIMD3<Float>] = [], ao: [Float] = []
    /// Per vertex RoomMaterial id for the jewellery shader (6 = gem, 7 = polished metal, 8 = pave); EMPTY (all plain) for every other piece.
    var mat: [Float] = []
    var idx: [UInt32] = []
    /// Surface binds (parallel to `rest`; `.zero` tri for vertices with w == 0), weights, swing weights, spin flags.
    var bind: [SurfaceBind] = [], w: [Float] = [], h: [Float] = [], spin: [Bool] = []
    var anyBound = false, anySwing = false
    /// Per vertex: may the limb push (WearLimbs) move it? False for the vertices the art itself puts inside a resting arm nub (a garment's own cover of the arm).
    var limbFree: [Bool] = []
    /// Small surface-bound parts (a pearl, a chain link, a button, a gem) that the limb push moves as ONE rigid piece so they stay round: per part the vertex nearest its
    /// centre (-1 = not such a part), its radius, and its first vertex (parts are contiguous).
    var clusterRep: [Int32] = [], clusterRadius: [Float] = [], partFirst: [Int] = []
    /// A cluster part is carried RIGIDLY: its centre (rest), the centre's surface bind and the rest frame of that bind (columns T, B, N). At runtime every vertex is
    /// centre + (current frame x rest frame^-1) x (rest - centre), so a pearl stays a pearl however hard the skin under it shears (a bump, a collar, a spin).
    var clusterCentre: [SIMD3<Float>] = [], clusterBind: [SurfaceBind] = [], clusterFrame0: [simd_float3x3] = []
    var hasClusters = false
    /// LEVELLED vertices (WearLevel): an encircling part (a band, string, wrap, collar ...) and everything of its piece that hangs on it keep their authored HEIGHT and their azimuth
    /// round the body axis in the body's own frame; only the radius follows the skin (`lvExcess` = how far outside the skin's foot point the authored vertex stands).
    var lvBind: [SurfaceBind] = [], clusterLvBind: [SurfaceBind] = []
    var level: [Bool] = [], lvY0: [Float] = [], lvDir: [SIMD2<Float>] = [], lvExcess: [Float] = []
    var levelPiece = false
    /// A necklace-class piece (WearLevel.tilts): its loop sits on the TILTED plane (front low, over the arm tops, higher on the back) instead of a level one; set before finalize.
    var tilted = false
    var tiltFrontY: Float = 0
    /// This piece's side loop height (WearLevel.sideY).
    var tiltSide: Float = 0.645
    /// The vertices of the thin encircling ring parts (a collar, hem, band, string): the limb bulge moves them even where a garment's authored cover would leave them on the skin.
    var lvRing: [Bool] = []
    /// Bandana string: the tube's vertices are lifted by their local CENTRELINE's tilt (the sag fade must not squash the tube's cross-section); set before finalize.
    var tubeKeep = false
    /// The nodes whose skin radius is read each frame (WearLevel): every levelled vertex that is not part of a rigid small part, and the centre of every levelled small part. Each node
    /// keeps the vertex (or part) it stands for, its skin point / height / azimuth, and the nodes within `WearLevel.neighbourhood` of it (the skin radius is dilated and averaged over
    /// them, so the loop does not follow the skin's ripple).
    var nodeVertex: [Int32] = [], nodeCluster: [Int32] = [], nodeBind: [SurfaceBind] = [], nodeY0: [Float] = [], nodeDir: [SIMD2<Float>] = [], nodeNbr: [[Int32]] = [], nodeRho0: [Float] = []
    var lvNode: [Int32] = [], clusterNode: [Int32] = []
    /// The same for the small rigid parts (pearl, link, knot, dot): per part, centre height / azimuth / excess (valid where `clusterLevel`).
    var clusterLevel: [Bool] = [], clusterY0: [Float] = [], clusterDir: [SIMD2<Float>] = [], clusterExcess: [Float] = []
    var partNames: [String] = [], partOfVertex: [UInt8] = []
    /// Vertices the jewellery twinkles on (the top vertex of every part named gem*): WornSet.emit pops 4-point star glints there.
    var sparkleSites: [Int] = []
    /// Where the piece scales about when it poofs on / off.
    var pivot = SIMD3<Float>.zero
    /// Head wear: the crown height map (CrownFit) and whether the piece encloses the head top (then it is fitted to the skin every frame).
    var crown: [Float] = []
    var crownEnclosing = false
    var crownMargin: Float = 0.02
    var triangles: Int { idx.count / 3 }
    init(_ l: WearLook) { look = l }
}

nonisolated enum WearMeshes {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var arts: [String: DecorMeshes.Art?] = [:]
    nonisolated(unsafe) private static var prepared: [WearLook: WearPrepared] = [:]
    nonisolated(unsafe) private static var bibs: [String: WearPrepared] = [:]
    nonisolated(unsafe) private static var variants: [String: WearPrepared] = [:]

    /// The raw art of a piece ("bandana_coral", "digit_3").
    static func art(_ id: String) -> DecorMeshes.Art? {
        lock.lock(); defer { lock.unlock() }
        if let a = arts[id] { return a }
        let a = DecorMeshes.load(id.hasPrefix("digit_") ? id : id, prefix: "wear_")
        arts[id] = .some(a)
        return a
    }
    static func art(_ l: WearLook) -> DecorMeshes.Art? { l.art.isEmpty ? nil : art(l.art) }

    /// Budget: every piece must stay under this many vertices / triangles (the whole outfit of three Jellies is rebuilt every frame).
    static let vertexBudget = 1000, triangleBudget = 1300

    /// The prepared piece (cached). `body` binds the surface-carried parts.
    static func prepare(_ l: WearLook, body: WearBody) -> WearPrepared? {
        lock.lock(); let c = prepared[l]; lock.unlock()
        if let c { return c }
        guard let a = art(l) else { return nil }
        let p = build(l, art: a, body: body, recolour: nil)
        lock.lock(); prepared[l] = p; lock.unlock()
        return p
    }

    static func clearCache() { lock.lock(); prepared = [:]; bibs = [:]; variants = [:]; lock.unlock() }

    /// The look drawn from a VARIANT of its art (the hats Moss's daisy sits on: beanie_honey_nopom, party_hat_short ...; Features/Resources): the
    /// look's own rules and anchor, the variant's mesh. Cached per look + art.
    static func prepare(_ l: WearLook, body: WearBody, art variant: String?) -> WearPrepared? {
        guard let variant, variant != l.art else { return prepare(l, body: body) }
        let key = "\(l.rawValue)|\(variant)"
        lock.lock(); let c = variants[key]; lock.unlock()
        if let c { return c }
        guard let a = art(variant) else { return prepare(l, body: body) }
        let p = build(l, art: a, body: body, recolour: nil)
        lock.lock(); variants[key] = p; lock.unlock()
        return p
    }

    static func build(_ l: WearLook, art a: DecorMeshes.Art, body: WearBody?, recolour: [(from: SIMD3<Float>, to: SIMD3<Float>)]?) -> WearPrepared {
        let p = WearPrepared(l)
        let anchor = l.row.anchorRest
        let isArm = WearRules.isArm(l)
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for (pi, part) in a.parts.enumerated() {
            let rule = WearRules.rule(l, part: part.name)
            let material = WearRules.material(l, part: part.name)
            let base = UInt32(p.rest.count)
            p.partNames.append(part.name)
            var ylo = Float.infinity, yhi = -Float.infinity
            for q in part.positions { ylo = min(ylo, q.y); yhi = max(yhi, q.y) }
            for k in 0..<part.positions.count {
                let v = part.positions[k]
                let r = isArm ? v : anchor + v
                p.rest.append(r); p.nrm.append(part.normals[k]); p.ao.append(part.ao[k])
                if material != 0 { if p.mat.isEmpty { p.mat = [Float](repeating: 0, count: p.rest.count - 1) }; p.mat.append(material) } else if !p.mat.isEmpty { p.mat.append(0) }
                var c = part.colors[k]
                if let recolour { for m in recolour where simd_distance(m.from, c) < 0.04 { c = m.to; break } }
                p.col.append(c)
                let t = yhi > ylo ? (yhi - v.y) / (yhi - ylo) : 0           // 0 at the part's top, 1 at its bottom
                let w = rule.w0 + (rule.w1 - rule.w0) * t, h = rule.h0 + (rule.h1 - rule.h0) * t
                p.w.append(w); p.h.append(h); p.spin.append(rule.spin); p.partOfVertex.append(UInt8(min(pi, 255)))
                lo = simd_min(lo, r); hi = simd_max(hi, r)
                if h > 0 { p.anySwing = true }
            }
            // trust the vertex normals over the file's winding: every triangle faces the way its normals say (the renderer culls back faces)
            var t = 0
            while t + 2 < part.indices.count {
                let i0 = part.indices[t], i1 = part.indices[t + 1], i2 = part.indices[t + 2]
                let g = simd_cross(part.positions[Int(i1)] - part.positions[Int(i0)], part.positions[Int(i2)] - part.positions[Int(i0)])
                let nn = part.normals[Int(i0)] + part.normals[Int(i1)] + part.normals[Int(i2)]
                if simd_dot(g, nn) >= 0 { p.idx += [base + i0, base + i1, base + i2] } else { p.idx += [base + i0, base + i2, base + i1] }
                t += 3
            }
        }
        if l == .diamondJ {
            // twinkle sites: every third stone's own vertex facing the way the stone does, and a spread of vertices on the pave face of the J and its bar
            for (pi, name) in p.partNames.enumerated() {
                let vs = p.partOfVertex.indices.filter { Int(p.partOfVertex[$0]) == pi }
                guard !vs.isEmpty else { continue }
                if name.hasPrefix("gem") {
                    if pi % 4 == 0 { var m = SIMD3<Float>.zero; for v in vs { m += p.nrm[v] }; m = simd_normalize(m); p.sparkleSites.append(vs.max { simd_dot(p.nrm[$0], m) < simd_dot(p.nrm[$1], m) }!) }
                } else if name == "jbody" || name == "jbar" {
                    let top = vs.filter { p.col[$0].z > 1.5 }                     // the pave face's rim vertices, in ring order
                    let want = name == "jbar" ? 1 : 3
                    for i in 0..<want where !top.isEmpty { p.sparkleSites.append(top[(top.count * (2 * i + 1)) / (2 * want)]) }
                }
            }
        }
        p.pivot = isArm ? .zero : anchor
        p.bind = [SurfaceBind](repeating: SurfaceBind(), count: p.rest.count)
        if let body, !isArm {
            for i in p.rest.indices where p.w[i] > 0.001 {
                if let b = body.bind(p.rest[i]) { p.bind[i] = b; p.anyBound = true } else { p.w[i] = 0 }
            }
        } else { for i in p.w.indices { p.w[i] = 0 } }
        if let body, !isArm { WearLevel.classify(p, body: body) }
        if let body, !isArm { CrownFit.prepare(p, body: body); if let lift = WearRules.neckLift(l), !p.levelPiece { raise(p, body: body, by: lift) } }
        if let body, !isArm, l.slot == .neck, WearLimbs.enabled, !p.levelPiece { seat(p, body: body) }          // (a levelled loop is not lifted up the wall: it takes its radius from the skin at its own height, WearLevel.finalize)
        markLimbFree(p, body: body, authoredCover: l.slot != .neck, clusters: WearLimbs.enabled && (l.slot == .neck || l.slot == .body))
        p.tilted = WearLevel.tilts(l); p.tiltSide = WearLevel.sideY(l); p.tubeKeep = WearLevel.tilts(l) && (l == .bandanaCoral || l == .bandanaMint || l == .bandanaSun)
        if let body, !isArm { WearLevel.finalize(p, body: body) }
        return p
    }

    /// The neck pieces were drawn round a plain egg, but the real rest egg stands out around the arm roots (the resting arm nub and its shoulder): where a strand, band or
    /// knot crosses that bump its vertices start 4-11 cm INSIDE the skin (a pearl necklace reads as two arcs with the middle under the shoulder). Each bound vertex that is
    /// sunk deeper than `floor` below the skin it is bound to is lifted along that skin's normal to just under the surface, and the lift is spread to everything within
    /// `plateau` of it (falling to nothing by `reach`), so a pearl or link rises as one round piece and a band keeps its thickness over the bump. Nothing else moves.
    static func seat(_ p: WearPrepared, body: WearBody, floor: Float = -0.004, plateau: Float = 0.10, reach: Float = 0.17) {
        let n = p.rest.count
        func wallNormal(_ i: Int) -> SIMD3<Float> {
            let b = p.bind[i]
            return WearBody.frame(body.pos[Int(b.tri.x)], body.pos[Int(b.tri.y)], body.nrm[Int(b.tri.x)], body.nrm[Int(b.tri.y)], body.nrm[Int(b.tri.z)], b.bary).n
        }
        // small parts (a pearl, a link, a gem) are lifted as ONE rigid piece; everything else (string, band, wrap) by a smooth lift field
        var partOf = [[Int]](repeating: [], count: p.partNames.count)
        for i in 0..<n where p.w[i] > 0.001 && Int(p.partOfVertex[i]) < partOf.count { partOf[Int(p.partOfVertex[i])].append(i) }
        var small = [Bool](repeating: false, count: n)
        var smallParts: [[Int]] = []
        for vs in partOf where vs.count >= 8 {
            var c = SIMD3<Float>.zero
            for v in vs { c += p.rest[v] }
            c /= Float(vs.count)
            if vs.allSatisfy({ simd_distance(p.rest[$0], c) <= 0.07 }) { smallParts.append(vs); for v in vs { small[v] = true } }
        }
        for _ in 0..<3 {
            var need = [Float](repeating: 0, count: n)
            var anyNeed = false
            for i in 0..<n where p.w[i] > 0.001 {
                let z = p.bind[i].off.z
                if z < floor - 0.002 { need[i] = floor - z; anyNeed = true }
            }
            guard anyNeed else { return }
            for vs in smallParts {
                let m = vs.map { need[$0] }.max() ?? 0
                guard m > 0 else { continue }
                var c = SIMD3<Float>.zero
                for v in vs { c += p.rest[v] }
                c /= Float(vs.count)
                let rep = vs.min { simd_distance(p.rest[$0], c) < simd_distance(p.rest[$1], c) }!
                let delta = wallNormal(rep) * m
                for v in vs { if let nb = body.bind(p.rest[v] + delta) { p.bind[v] = nb; p.rest[v] = body.restPoint(nb) } }
            }
            let src = (0..<n).filter { need[$0] > 0 && !small[$0] }
            guard !src.isEmpty else { continue }
            var nrm = [SIMD3<Float>](repeating: .zero, count: n)
            for i in 0..<n where p.w[i] > 0.001 && !small[i] { nrm[i] = wallNormal(i) }
            for i in 0..<n where p.w[i] > 0.001 && !small[i] {
                var lift: Float = 0
                for j in src {
                    let d = simd_distance(p.rest[i], p.rest[j])
                    if d >= reach { continue }
                    lift = max(lift, need[j] * (d <= plateau ? 1 : (reach - d) / (reach - plateau)))
                }
                guard lift > 0 else { continue }
                // one common direction for the neighbourhood (the skin's normals fan out over a bump)
                var dir = SIMD3<Float>.zero
                for j in 0..<n where p.w[j] > 0.001 && !small[j] && simd_distance(p.rest[i], p.rest[j]) < 0.07 { dir += nrm[j] }
                dir = simd_length(dir) > 1e-4 ? simd_normalize(dir) : nrm[i]
                if let nb = body.bind(p.rest[i] + dir * lift) { p.bind[i] = nb; p.rest[i] = body.restPoint(nb) }
            }
        }
    }

    /// Which bound vertices the limb push may move: the ones that are NOT inside a resting arm nub as authored.
    static func markLimbFree(_ p: WearPrepared, body: WearBody?, authoredCover: Bool = true, clusters: Bool = true) {
        p.limbFree = [Bool](repeating: false, count: p.rest.count)
        p.clusterRep = [Int32](repeating: -1, count: p.partNames.count); p.clusterRadius = [Float](repeating: 0, count: p.partNames.count)
        p.partFirst = [Int](repeating: p.rest.count, count: p.partNames.count)
        p.clusterCentre = [SIMD3<Float>](repeating: .zero, count: p.partNames.count); p.clusterBind = [SurfaceBind](repeating: SurfaceBind(), count: p.partNames.count)
        p.clusterFrame0 = [simd_float3x3](repeating: matrix_identity_float3x3, count: p.partNames.count); p.hasClusters = false
        guard let body else { return }
        for i in p.rest.indices where p.w[i] > 0.001 { p.limbFree[i] = !authoredCover || !body.restLimbs.inside(p.rest[i], tol: 0.02) }          // (a neck piece has no authored cover: seat() has lifted it clear)
        for i in p.rest.indices.reversed() where Int(p.partOfVertex[i]) < p.partFirst.count { p.partFirst[Int(p.partOfVertex[i])] = i }
        for k in p.partNames.indices {
            let vs = p.rest.indices.filter { Int(p.partOfVertex[$0]) == k }
            guard vs.count >= 8, vs.allSatisfy({ p.w[$0] > 0.99 && p.h[$0] == 0 }) else { continue }
            var ctr = SIMD3<Float>.zero
            for v in vs { ctr += p.rest[v] }
            ctr /= Float(vs.count)
            var rad: Float = 0
            var rep = vs[0], best = Float.infinity
            for v in vs { let d = simd_distance(p.rest[v], ctr); rad = max(rad, d); if d < best { best = d; rep = v } }
            if clusters, rad <= 0.07, p.limbFree[rep], let cb = body.bind(ctr) {
                p.clusterRep[k] = Int32(rep); p.clusterRadius[k] = rad
                p.clusterCentre[k] = ctr; p.clusterBind[k] = cb
                let f = WearBody.frame(body.pos[Int(cb.tri.x)], body.pos[Int(cb.tri.y)], body.nrm[Int(cb.tri.x)], body.nrm[Int(cb.tri.y)], body.nrm[Int(cb.tri.z)], cb.bary)
                p.clusterFrame0[k] = simd_float3x3(columns: (f.t, f.b, f.n)); p.hasClusters = true
            }
        }
    }

    /// A chain-type neck piece raised clear of the arms (the arm roots sit at the sides, top ~0.66): every bound vertex slides up the egg wall by `lift` times
    /// a weight that is 0 over the mouth (front) and full from the arms round the back, then is re-seated on the wall there keeping its own offset (the
    /// tangent part turned with the wall's normal, the normal part unchanged), so the links stay on the skin and the pendant keeps hanging at the front.
    static func raise(_ p: WearPrepared, body: WearBody, by lift: WearRules.NeckLift) {
        // a small part (a pearl, a link, a gem) is lifted by the weight at ITS centre, so the lift cannot differ across it and shear it into a rock
        var centre = [SIMD3<Float>?](repeating: nil, count: p.rest.count)
        var byPart = [[Int]](repeating: [], count: p.partNames.count)
        for i in p.rest.indices where p.w[i] > 0.001 && Int(p.partOfVertex[i]) < byPart.count { byPart[Int(p.partOfVertex[i])].append(i) }
        for vs in byPart where vs.count >= 8 && WearLimbs.enabled {
            var c = SIMD3<Float>.zero
            for v in vs { c += p.rest[v] }
            c /= Float(vs.count)
            if vs.allSatisfy({ simd_distance(p.rest[$0], c) <= 0.07 }) { for v in vs { centre[v] = c } }
        }
        // small parts move as one piece: the lift of their centre, applied to every vertex as the same translation
        for vs in byPart where vs.count >= 8 {
            guard let c = centre[vs[0]], let b0 = body.bind(c) else { continue }
            let az = abs(atan2(c.x, c.z))
            let u = min(max((az - lift.from) / (lift.full - lift.from), 0), 1)
            let k = u * u * (3 - 2 * u)
            guard k > 0.001 else { continue }
            let a0 = body.pos[Int(b0.tri.x)], c0 = body.pos[Int(b0.tri.y)], d0 = body.pos[Int(b0.tri.z)]
            let f0 = WearBody.frame(a0, c0, body.nrm[Int(b0.tri.x)], body.nrm[Int(b0.tri.y)], body.nrm[Int(b0.tri.z)], b0.bary)
            let q0 = a0 * b0.bary.x + c0 * b0.bary.y + d0 * b0.bary.z
            guard let b1 = body.bind(q0 + SIMD3(0, lift.up * k, 0)) else { continue }
            let f1 = WearBody.frame(body.pos[Int(b1.tri.x)], body.pos[Int(b1.tri.y)], body.nrm[Int(b1.tri.x)], body.nrm[Int(b1.tri.y)], body.nrm[Int(b1.tri.z)], b1.bary)
            let tang = f0.t * b0.off.x + f0.b * b0.off.y
            let ax = simd_cross(f0.n, f1.n), sn = simd_length(ax), cs = simd_dot(f0.n, f1.n)
            var t1 = tang
            if sn > 1e-6 { let kk = ax / sn; t1 = tang * cs + simd_cross(kk, tang) * sn + kk * simd_dot(kk, tang) * (1 - cs) }
            let cNew = body.restPoint(SurfaceBind(tri: b1.tri, bary: b1.bary, off: SIMD3(simd_dot(t1, f1.t), simd_dot(t1, f1.b), b0.off.z)))
            let delta = cNew - c
            for v in vs { let r2 = p.rest[v] + delta; if let nb = body.bind(r2) { p.bind[v] = nb; p.rest[v] = body.restPoint(nb) } }
        }
        for i in p.rest.indices where p.w[i] > 0.001 {
            if centre[i] != nil { continue }                               // (done above)
            let r = p.rest[i]
            let rc = r
            let az = abs(atan2(rc.x, rc.z))                                // 0 at the front, pi at the back
            let u = min(max((az - lift.from) / (lift.full - lift.from), 0), 1)
            let k = u * u * (3 - 2 * u)
            guard k > 0.001 else { continue }
            let b0 = p.bind[i]
            let a0 = body.pos[Int(b0.tri.x)], c0 = body.pos[Int(b0.tri.y)], d0 = body.pos[Int(b0.tri.z)]
            let f0 = WearBody.frame(a0, c0, body.nrm[Int(b0.tri.x)], body.nrm[Int(b0.tri.y)], body.nrm[Int(b0.tri.z)], b0.bary)
            let q0 = a0 * b0.bary.x + c0 * b0.bary.y + d0 * b0.bary.z
            let tang = f0.t * b0.off.x + f0.b * b0.off.y                     // the offset's part along the wall
            guard let b1 = body.bind(q0 + SIMD3(0, lift.up * k, 0)) else { continue }
            let a1 = body.pos[Int(b1.tri.x)], c1 = body.pos[Int(b1.tri.y)], d1 = body.pos[Int(b1.tri.z)]
            let f1 = WearBody.frame(a1, c1, body.nrm[Int(b1.tri.x)], body.nrm[Int(b1.tri.y)], body.nrm[Int(b1.tri.z)], b1.bary)
            // turn the wall-tangent offset from the old normal to the new one (smallest rotation)
            let ax = simd_cross(f0.n, f1.n), s = simd_length(ax), c = simd_dot(f0.n, f1.n)
            var t1 = tang, n1 = p.nrm[i]
            if s > 1e-6 {
                let kk = ax / s
                func turn(_ v: SIMD3<Float>) -> SIMD3<Float> { v * c + simd_cross(kk, v) * s + kk * simd_dot(kk, v) * (1 - c) }
                t1 = turn(tang); n1 = turn(n1)
            }
            p.bind[i] = SurfaceBind(tri: b1.tri, bary: b1.bary, off: SIMD3(simd_dot(t1, f1.t), simd_dot(t1, f1.b), b0.off.z))
            p.rest[i] = body.restPoint(p.bind[i]); p.nrm[i] = n1          // (the rest point is where the bind lands)
        }
    }

    /// The piece alone, at rest, for the shop's 3D thumbnails (no body needed).
    static func restMesh(_ l: WearLook) -> RoomMesh? {
        guard let a = art(l) else { return nil }
        let p = build(l, art: a, body: nil, recolour: nil)
        var m = RoomMesh()
        // (the shop picture is a SceneKit render with no jewellery shader: the J's pave face carries grid coordinates in its colour, so show it as plain bright platinum there)
        m.vertices = (0..<p.rest.count).map { i in
            let mt: Float = p.mat.isEmpty ? 0 : p.mat[i]
            let c: SIMD3<Float> = mt == 8 ? (p.col[i].z > 1.5 ? SIMD3(2.0, 2.1, 2.4) : SIMD3(1.3, 1.4, 1.7)) : p.col[i]
            return RoomVertex(pos: SIMD4(p.rest[i], mt), normal: SIMD4(p.nrm[i], p.ao[i]), color: SIMD4(c, 1))
        }
        m.indices = p.idx
        return m
    }

    // MARK: the Circuit bib

    /// A bib (`.bibSky` / `.bibPink` plate recoloured to `team`) with `number` (1 or 2 digits from the digit meshes) on it.
    static func bib(team: WearTeam, number: Int, body: WearBody) -> WearPrepared? {
        let key = "\(team.rawValue)-\(number)"
        lock.lock(); let c = bibs[key]; lock.unlock()
        if let c { return c }
        let src: WearLook = .bibSky
        guard let plate = art(src) else { return nil }
        let swap = [(from: WearTeam.sky.linear, to: team.linear), (from: WearTeam.pink.linear, to: team.linear)]
        let p = build(src, art: plate, body: body, recolour: swap)
        // the digits, placed on the plate face along the plate normal, tinted team colour 25 % toward ink
        let tint = team.linear * 0.75 + WearTeam.inkLinear * 0.25
        let N = simd_normalize(WearGenerated.bibNumberNormal)
        let T = simd_normalize(SIMD3<Float>(1, 0, 0) - N * N.x)
        let U = simd_cross(N, T)
        let hgt = WearGenerated.bibNumberHeight
        let digits = String(max(0, min(number, 99))).compactMap { $0.wholeNumberValue }
        var arts: [DecorMeshes.Art] = []
        for d in digits { if let a = art("digit_\(d)") { arts.append(a) } }
        func bounds(_ a: DecorMeshes.Art) -> (lo: Float, hi: Float) { let b = a.bounds; return (b.lo.x, b.hi.x) }
        let gap: Float = 0.07
        let total = arts.reduce(Float(0)) { $0 + (bounds($1).hi - bounds($1).lo) } + gap * Float(max(arts.count - 1, 0))
        var x0 = -total / 2
        for a in arts {
            let (bl, bh) = bounds(a)
            let base = UInt32(p.rest.count)
            for part in a.parts {
                let pb = UInt32(p.rest.count) - base
                _ = pb
                let off = UInt32(p.rest.count)
                for k in 0..<part.positions.count {
                    let v = part.positions[k]
                    let lx = x0 - bl + v.x
                    let r = WearGenerated.bibNumberAnchor + (T * lx + U * v.y + N * v.z) * hgt
                    p.rest.append(r)
                    let n = part.normals[k]
                    p.nrm.append(simd_normalize(T * n.x + U * n.y + N * n.z))
                    p.col.append(tint); p.ao.append(part.ao[k]); p.w.append(1); p.h.append(0); p.spin.append(false); p.partOfVertex.append(250)
                    p.bind.append(body.bind(r) ?? SurfaceBind())
                }
                var t = 0
                while t + 2 < part.indices.count {
                    let i0 = part.indices[t], i1 = part.indices[t + 1], i2 = part.indices[t + 2]
                    let g = simd_cross(part.positions[Int(i1)] - part.positions[Int(i0)], part.positions[Int(i2)] - part.positions[Int(i0)])
                    let nn = part.normals[Int(i0)] + part.normals[Int(i1)] + part.normals[Int(i2)]
                    if simd_dot(g, nn) >= 0 { p.idx += [off + i0, off + i1, off + i2] } else { p.idx += [off + i0, off + i2, off + i1] }
                    t += 3
                }
            }
            x0 += (bh - bl) + gap
        }
        markLimbFree(p, body: body)
        lock.lock(); bibs[key] = p; lock.unlock()
        return p
    }
}
