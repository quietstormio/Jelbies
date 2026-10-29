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
        if let body, !isArm { CrownFit.prepare(p, body: body); if let lift = WearRules.neckLift(l) { raise(p, body: body, by: lift) } }
        return p
    }

    /// A chain-type neck piece raised clear of the arms (the arm roots sit at the sides, top ~0.66): every bound vertex slides up the egg wall by `lift` times
    /// a weight that is 0 over the mouth (front) and full from the arms round the back, then is re-seated on the wall there keeping its own offset (the
    /// tangent part turned with the wall's normal, the normal part unchanged), so the links stay on the skin and the pendant keeps hanging at the front.
    static func raise(_ p: WearPrepared, body: WearBody, by lift: WearRules.NeckLift) {
        for i in p.rest.indices where p.w[i] > 0.001 {
            let r = p.rest[i]
            let az = abs(atan2(r.x, r.z))                                  // 0 at the front, pi at the back
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
        lock.lock(); bibs[key] = p; lock.unlock()
        return p
    }
}
