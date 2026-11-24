//
//  ClipProbe.swift
//  no-clip-r1 capture aid (`-ClipProbe 1`, simulator only, reads state and logs: no behaviour change). Every frame, after the skin pass, for every drawn body: the DRAWN skin's
//  vertices (the egg, the arm capsules, the foot beans, from the skinned stream) against the solid volumes of the props around him:
//    - the park / home slide: the art mesh itself, as a voxel field (2 cm) built once by signed winding along the vertical, so the chute's walls, the posts and the platform
//      are solid and the open channel is not;
//    - every other solid placed piece: its footprint box (`DecorFoot.box`) up to its height, except for the body that is using it (`DecorField.occupant`);
//    - the Jelly Spa street: the shop front (the wall plane), the swinging door leaf, the planters, the sandwich board, the flower box, the bench.
//  `[clip] ep` one line per episode (a body's skin inside a prop by more than 3 mm; ends after 5 clear frames): who, prop, part (arm / body / foot), max depth (cm), frames, what he does.
//  `[clip] pair` two drawn skins sunk into each other by more than 2 cm while the Spa door is open (ContactField.gap).
//  `[clip] sum` every 20 s of wall clock: per prop and part the episodes, the frames, the max depth, and the frames with depth over 1 cm.
//

#if targetEnvironment(simulator)
import Foundation
import QuartzCore
import simd

enum ClipProbe {
    nonisolated(unsafe) static var on = UserDefaults.standard.integer(forKey: "ClipProbe") != 0
    typealias V3 = SIMD3<Float>

    /// A voxel field of "how deep inside" a piece of art, piece-local (the piece origin at the footprint centre on the floor).
    final class Field {
        let lo: V3, n: SIMD3<Int>, h: Float, depth: [Float], solidFraction: Float
        init(art: DecorMeshes.Art, h: Float = 0.02) {
            let b = art.bounds
            let lo = b.lo - V3(repeating: 2 * h)
            let ext = b.hi + V3(repeating: 2 * h) - lo
            let n = SIMD3(Int(ext.x / h) + 1, Int(ext.y / h) + 1, Int(ext.z / h) + 1)
            var solid = [Bool](repeating: false, count: n.x * n.y * n.z)
            func idx(_ x: Int, _ y: Int, _ z: Int) -> Int { (z * n.y + y) * n.x + x }
            // signed crossings along +y per (x, z) column
            var cols = [[(y: Float, s: Int)]](repeating: [], count: n.x * n.z)
            for p in art.parts {
                var t = 0
                while t + 2 < p.indices.count {
                    let a = p.positions[Int(p.indices[t])], bb = p.positions[Int(p.indices[t + 1])], c = p.positions[Int(p.indices[t + 2])]
                    let nrm = p.normals[Int(p.indices[t])] + p.normals[Int(p.indices[t + 1])] + p.normals[Int(p.indices[t + 2])]
                    t += 3
                    if abs(nrm.y) < 1e-4 { continue }
                    let gn = simd_cross(bb - a, c - a)
                    if abs(gn.y) < 1e-9 { continue }          // (vertical face: the ray runs along it)
                    let s = nrm.y < 0 ? 1 : -1                 // entering the solid when the outward normal points down
                    let x0 = max(0, Int((min(a.x, bb.x, c.x) - lo.x) / h)), x1 = min(n.x - 1, Int((max(a.x, bb.x, c.x) - lo.x) / h) + 1)
                    let z0 = max(0, Int((min(a.z, bb.z, c.z) - lo.z) / h)), z1 = min(n.z - 1, Int((max(a.z, bb.z, c.z) - lo.z) / h) + 1)
                    if x0 > x1 || z0 > z1 { continue }
                    for zi in z0...z1 { for xi in x0...x1 {
                        let px = lo.x + (Float(xi) + 0.5) * h, pz = lo.z + (Float(zi) + 0.5) * h
                        let d = (bb.z - c.z) * (a.x - c.x) + (c.x - bb.x) * (a.z - c.z)
                        if abs(d) < 1e-12 { continue }
                        let l1 = ((bb.z - c.z) * (px - c.x) + (c.x - bb.x) * (pz - c.z)) / d
                        let l2 = ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / d
                        let l3 = 1 - l1 - l2
                        if l1 < 0 || l2 < 0 || l3 < 0 { continue }
                        cols[zi * n.x + xi].append((l1 * a.y + l2 * bb.y + l3 * c.y, s))
                    } }
                }
            }
            for zi in 0..<n.z { for xi in 0..<n.x {
                let c = cols[zi * n.x + xi].sorted { $0.y < $1.y }
                var w = 0, k = 0
                for yi in 0..<n.y {
                    let y = lo.y + (Float(yi) + 0.5) * h
                    while k < c.count, c[k].y <= y { w += c[k].s; k += 1 }
                    if w > 0 { solid[idx(xi, yi, zi)] = true }
                }
            } }
            var d = [Float](repeating: 0, count: solid.count)
            let big: Float = 1e3
            var nSolid = 0
            for i in solid.indices { d[i] = solid[i] ? big : 0; if solid[i] { nSolid += 1 } }
            let w1 = h, w2 = h * 1.4142, w3 = h * 1.7321
            func relax(_ x: Int, _ y: Int, _ z: Int, _ dx: Int, _ dy: Int, _ dz: Int, _ w: Float) {
                let xx = x + dx, yy = y + dy, zz = z + dz
                guard xx >= 0, yy >= 0, zz >= 0, xx < n.x, yy < n.y, zz < n.z else { return }
                let v = d[idx(xx, yy, zz)] + w
                if v < d[idx(x, y, z)] { d[idx(x, y, z)] = v }
            }
            for z in 0..<n.z { for y in 0..<n.y { for x in 0..<n.x {
                for dz in -1...0 { for dy in -1...1 { for dx in -1...1 {
                    if dz == 0, dy > 0 || (dy == 0 && dx >= 0) { continue }
                    let m = abs(dx) + abs(dy) + abs(dz); if m == 0 { continue }
                    relax(x, y, z, dx, dy, dz, m == 1 ? w1 : (m == 2 ? w2 : w3))
                } } }
            } } }
            for z in stride(from: n.z - 1, through: 0, by: -1) { for y in stride(from: n.y - 1, through: 0, by: -1) { for x in stride(from: n.x - 1, through: 0, by: -1) {
                for dz in 0...1 { for dy in -1...1 { for dx in -1...1 {
                    if dz == 0, dy < 0 || (dy == 0 && dx <= 0) { continue }
                    let m = abs(dx) + abs(dy) + abs(dz); if m == 0 { continue }
                    relax(x, y, z, dx, dy, dz, m == 1 ? w1 : (m == 2 ? w2 : w3))
                } } }
            } } }
            self.lo = lo; self.n = n; self.h = h
            self.depth = d.map { $0 >= big ? 0 : max(0, $0 - 0.5 * h) + ($0 > 0 ? 0.001 : 0) }
            self.solidFraction = Float(nSolid) / Float(solid.count)
        }
        /// Depth inside (m) at a piece-local point, 0 outside.
        @inline(__always) func at(_ p: V3) -> Float {
            let q = (p - lo) / h
            let x = Int(q.x), y = Int(q.y), z = Int(q.z)
            guard q.x >= 0, q.y >= 0, q.z >= 0, x < n.x, y < n.y, z < n.z else { return 0 }
            return depth[(z * n.y + y) * n.x + x]
        }
    }
    nonisolated(unsafe) static var fields: [DecorKind: Field] = [:]
    nonisolated(unsafe) static var slideLogged = Set<Int>()
    static func field(_ k: DecorKind) -> Field? {
        if let f = fields[k] { return f }
        guard let a = DecorMeshes.loaded[k] else { return nil }
        let t0 = CACurrentMediaTime()
        let f = Field(art: k == .slide ? (ParkSlideSkin.art ?? a) : a)
        fields[k] = f
        NSLog("[clip] field %@ built %.2fs voxels %d x %d x %d solidFraction %.3f", k.rawValue, CACurrentMediaTime() - t0, f.n.x, f.n.y, f.n.z, f.solidFraction)
        return f
    }

    // MARK: the sample points of a body

    struct Sample { var p: V3; var part: UInt8 }          // 0 body, 1 arm, 2 foot
    /// The arms' axes (root pole to tip pole, world) and the egg's centre, for the pass-through (chord) measure.
    struct Body { var s: [Sample]; var axes: [(V3, V3)]; var centre: V3 }
    static func samples(_ j: JellyParallel.SkinJob) -> Body {
        var out: [Sample] = []
        var axes: [(V3, V3)] = []
        let s = j.skinner, d = UnsafePointer(j.dst)
        func pt(_ i: Int) -> V3 { V3(d[6 * i], d[6 * i + 1], d[6 * i + 2]) }
        let egg = s.bodyVertexLimit > 0 ? min(s.bodyVertexLimit, s.vertexCount) : min(ContactField.eggLimit, s.vertexCount)
        var i = 0
        while i < egg { let p = pt(i); if p.x.isFinite { out.append(Sample(p: p, part: 0)) }; i += 3 }
        if s.armCapsulesActive { for k in 0..<2 { axes.append((pt(s.armFirst[k] + ArmCapsule.vertexCount - 1), pt(s.armFirst[k]))) } }
        if s.armCapsulesActive { for k in 0..<2 { for v in s.armFirst[k]..<(s.armFirst[k] + ArmCapsule.vertexCount) { let p = pt(v); if p.x.isFinite { out.append(Sample(p: p, part: 1)) } } } }
        if s.beansActive { for k in 0..<2 { for v in stride(from: s.beanFirst[k], to: s.beanFirst[k] + FootBean.vertexCount, by: 2) { let p = pt(v); if p.x.isFinite { out.append(Sample(p: p, part: 2)) } } } }
        var c = V3.zero, cn: Float = 0
        for q in out where q.part == 0 { c += q.p; cn += 1 }
        return Body(s: out, axes: axes, centre: cn > 0 ? c / cn : .zero)
    }

    // MARK: the props

    struct Prop { var name: String; var uid: Int; var depth: (V3) -> Float; var lo: V3; var hi: V3; var thin = false }

    static func boxProp(_ name: String, uid: Int = -1, lo: V3, hi: V3) -> Prop {
        Prop(name: name, uid: uid, depth: { p in
            guard p.x > lo.x, p.x < hi.x, p.y > lo.y, p.y < hi.y, p.z > lo.z, p.z < hi.z else { return 0 }
            return min(p.x - lo.x, hi.x - p.x, p.y - lo.y, hi.y - p.y, p.z - lo.z, hi.z - p.z)
        }, lo: lo, hi: hi)
    }

    static func props(_ care: GameCare) -> [Prop] {
        var out: [Prop] = []
        let df = DecorField.shared
        for f in df.feet {
            if f.kind == .slide, f.uid != ParkToys.slideUID, !slideLogged.contains(f.uid) { slideLogged.insert(f.uid); NSLog("[clip] home slide uid %d at (%.2f,%.2f) q%d zonesClear=%d", f.uid, f.centre.x, f.centre.y, f.quarter, SlideZones.clear(f, among: df.feet) ? 1 : 0) }
            if f.kind == .slide, f.uid != ParkToys.slideUID, slideLogged.contains(f.uid), slideLogged.count == 1, frame % 600 == 1 { for g in df.feet where g.uid != f.uid { let b = df.position(g), h = g.spec.half; NSLog("[clip] slide neighbour %@ at (%.2f,%.2f) half (%.2f,%.2f) solid=%d zones %@", g.kind.rawValue, b.x, b.y, h.x, h.y, g.spec.solid ? 1 : 0, SlideZones.zones(f).map { "[\($0.lo.x),\($0.lo.y)..\($0.hi.x),\($0.hi.y)]" }.joined(separator: " ")) } }
            if f.kind == .slide, let fld = field(.slide) {
                let c = f.centre, q = f.quarter, lift = f.lift
                let lo = V3(c.x - 1.4, lift, c.y - 2.0), hi = V3(c.x + 1.4, lift + 1.6, c.y + 2.0)
                out.append(Prop(name: "slide", uid: f.uid, depth: { p in
                    let l = DecorPlacement.turn(SIMD2(p.x - c.x, p.z - c.y), (4 - q) & 3)
                    return fld.at(V3(l.x, p.y - lift, l.y))
                }, lo: lo, hi: hi, thin: true))
            } else if f.spec.solid {
                let bx = f.box
                out.append(boxProp("decor:\(f.kind.rawValue)", uid: f.uid, lo: V3(bx.centre.x - bx.half.x, 0, bx.centre.y - bx.half.y), hi: V3(bx.centre.x + bx.half.x, bx.height, bx.centre.y + bx.half.y)))
            }
        }
        if !care.groom.inScene {
            // the room's own fixed pieces, from the tables the walk resolver reads
            let c = RoomLayout.sofa
            out.append(boxProp("room:sofa", lo: c.centre - c.halfExtents, hi: c.centre + c.halfExtents))
            for (i, b) in RoomLayout.current.boxes.enumerated() { out.append(boxProp("room:box\(i)", lo: b.centre - b.halfExtents, hi: b.centre + b.halfExtents)) }
            var cyls = RoomLayout.cylinders; cyls.append(RoomLayout.table)
            for (i, cy) in cyls.enumerated() { out.append(Prop(name: "room:cyl\(i)", uid: -1, depth: { p in p.y > 0 && p.y < cy.height ? max(0, min(cy.radius - hypotf(p.x - cy.centre.x, p.z - cy.centre.y), cy.height - p.y)) : 0 }, lo: V3(cy.centre.x - cy.radius, 0, cy.centre.y - cy.radius), hi: V3(cy.centre.x + cy.radius, cy.height, cy.centre.y + cy.radius))) }
            for b in RoomLayout.dynamicBoxes { out.append(boxProp("room:tray", lo: V3(b.centre.x - b.half.x, 0, b.centre.y - b.half.y), hi: V3(b.centre.x + b.half.x, b.height, b.centre.y + b.half.y))) }
            for (_, b) in RoomLayout.tableBoxes { out.append(boxProp("room:cafetable", lo: V3(b.centre.x - b.half.x, 0, b.centre.y - b.half.y), hi: V3(b.centre.x + b.half.x, b.height, b.centre.y + b.half.y))) }
        }
        if care.groom.inScene {
            let Z = GroomScenery.frontZ, dx = GroomScenery.doorX, dw = GroomScenery.doorW
            out.append(boxProp("groom:shopfront", lo: V3(-12, 0, -12), hi: V3(12, 6, Z)))
            let open = care.groom.doorOpen
            let ang = open * open * (3 - 2 * open) * 1.75
            let hinge = SIMD2<Float>(dx - dw, Z + 0.07)
            // the leaf: half 0.6 x 0.03 around its centre, turned by -ang about the hinge (RoomMeshBuilder rotation about +y, see GroomRoom.animated)
            let ca = cosf(ang), sa = sinf(ang)
            out.append(Prop(name: "groom:doorleaf", uid: -1, depth: { p in
                guard p.y > 0.1, p.y < 2.3 else { return 0 }
                let r = SIMD2<Float>(p.x - hinge.x, p.z - hinge.y)
                // inverse rotation: bring the point back to the closed leaf
                let l = SIMD2<Float>(ca * r.x + sa * r.y, -sa * r.x + ca * r.y)          // (the mesh turns by -ang about +y: x' = x ca - z sa, z' = x sa + z ca)
                let cx = l.x - dw, cz = l.y
                if abs(cx) < 0.6, abs(cz) < 0.06 { return min(0.6 - abs(cx), 0.06 - abs(cz)) }
                return 0
            }, lo: V3(hinge.x - 1.4, 0, Z - 0.2), hi: V3(hinge.x + 1.4, 2.4, Z + 1.5), thin: true))
            out.append(Prop(name: "groom:planter", uid: -1, depth: { p in
                guard p.y > 0.1, p.y < 0.8 else { return 0 }
                var m: Float = 0
                for x in [Float(-3.3), 3.5] { m = max(m, 0.42 - hypotf(p.x - x, p.z - (Z + 0.8))) }
                return m
            }, lo: V3(-4, 0, Z), hi: V3(4, 1, Z + 1.5)))
            out.append(boxProp("groom:step", lo: V3(dx - 0.95, 0.1, Z), hi: V3(dx + 0.95, 0.26, Z + 0.9)))
            out.append(boxProp("groom:sandwichboard", lo: V3(0.0, 0.16, Z + 0.55), hi: V3(0.6, 1.0, Z + 0.78)))
            out.append(boxProp("groom:flowerbox", lo: V3(-2.4, 0.1, Z + 0.36), hi: V3(-0.7, 0.42, Z + 0.64)))
            out.append(boxProp("groom:bench", lo: V3(-5.2, 0.2, Z + 0.1), hi: V3(-3.9, 1.0, Z + 0.55)))
        }
        return out
    }

    // MARK: the run

    struct Key: Hashable { var id: Int; var prop: String; var part: UInt8 }
    struct Ep { var t0: Double; var maxD: Float; var frames: Int; var clear: Int; var doing: String; var at: SIMD2<Float>; var stage: Int; var pt = V3.zero, cen = V3.zero }
    nonisolated(unsafe) static var eps: [Key: Ep] = [:]
    struct Agg { var episodes = 0, frames = 0, over1 = 0, maxD: Float = 0 }
    nonisolated(unsafe) static var agg: [String: Agg] = [:]
    nonisolated(unsafe) static var t = 0.0, lastSum = 0.0, frame = 0
    nonisolated(unsafe) static var pairNow: [Int: Bool] = [:]
    nonisolated(unsafe) static var pairAgg = Agg()
    static let partName = ["body", "arm", "foot"]

    static func doing(_ b: BlobBrain?) -> String {
        guard let b else { return "-" }
        var s: [String] = []
        if let k = b.idleState.kind { s.append("idle:\(k)/st\(b.idleState.slideStage)") }
        s.append("scr:\(b.scriptKindName)")
        s.append("act:\(b.activity)")
        if b.poseW > 0 { s.append("pose") }
        return s.joined(separator: " ")
    }

    @MainActor static func run(_ jobs: [JellyParallel.SkinJob], bodies: [JellyActor], care: GameCare, dt: Float) {
        guard on else { return }
        frame += 1; t += Double(dt)
        let plist = props(care)
        let byID = Dictionary(bodies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<Key>()
        for j in jobs {
            let body = samples(j), sm = body.s
            guard !sm.isEmpty else { continue }
            var lo = V3(repeating: .infinity), hi = V3(repeating: -.infinity)
            for s in sm { lo = simd_min(lo, s.p); hi = simd_max(hi, s.p) }
            let brain = byID[j.id]?.brain
            for pr in plist {
                if hi.x < pr.lo.x || lo.x > pr.hi.x || hi.y < pr.lo.y || lo.y > pr.hi.y || hi.z < pr.lo.z || lo.z > pr.hi.z { continue }
                if pr.uid >= 0, pr.name != "slide", let b = brain, DecorField.shared.occupant[pr.uid] == b.steerID { continue }          // (he is using it: sitting on it, in it, at it)
                var m: [Float] = [0, 0, 0], at = [V3](repeating: .zero, count: 3)
                for s in sm { let d = pr.depth(s.p); if d > m[Int(s.part)] { m[Int(s.part)] = d; at[Int(s.part)] = s.p } }
                // the pass-through: how much of an arm's axis (root to tip) lies inside the prop, and of a line from the egg's centre to each egg vertex (a thin wall reads only half its thickness by vertex depth)
                for (a0, a1) in body.axes {
                    var inside: Float = 0
                    for i in 0...16 { if pr.depth(a0 + (a1 - a0) * (Float(i) / 16)) > 0 { inside += simd_length(a1 - a0) / 16 } }
                    if inside > m[1] { m[1] = inside }
                }
                if pr.thin {
                    var k = 0
                    for s in sm where s.part == 0 {
                        k += 1; if k % 3 != 0 { continue }
                        let d = s.p - body.centre, L = simd_length(d); if L < 0.01 { continue }
                        var inside: Float = 0, step = L / 12
                        for i in 1...12 where pr.depth(body.centre + d * (Float(i) / 12)) > 0 { inside += step }
                        step = 0
                        if inside > m[0] { m[0] = inside }
                    }
                }
                for part in 0..<3 where m[part] > 0.003 {
                    let k = Key(id: j.id, prop: pr.name, part: UInt8(part)); seen.insert(k)
                    let stg = brain.map { $0.idleState.kind == .decorSlide ? $0.idleState.slideStage : -9 } ?? -9
                    var e = eps[k] ?? Ep(t0: t, maxD: 0, frames: 0, clear: 0, doing: doing(brain), at: brain?.position ?? .zero, stage: stg)
                    if eps[k] == nil { agg[pr.name + "/" + partName[part], default: Agg()].episodes += 1 }
                    if m[part] > e.maxD { e.maxD = m[part]; e.stage = stg; e.pt = at[part]; e.cen = body.centre }
                    e.frames += 1; e.clear = 0
                    eps[k] = e
                    var a = agg[pr.name + "/" + partName[part]] ?? Agg()
                    a.frames += 1; if m[part] > 0.01 { a.over1 += 1 }; a.maxD = max(a.maxD, m[part])
                    agg[pr.name + "/" + partName[part]] = a
                }
            }
        }
        for (k, var e) in eps where !seen.contains(k) {
            e.clear += 1
            if e.clear >= 5 {
                eps[k] = nil
                NSLog("[clip] ep t=%.1f body=%d prop=%@ part=%@ maxDepth=%.1fcm frames=%d slideStage@max=%d deepestPt=(%.2f,%.2f,%.2f) bodyCentre=(%.2f,%.2f,%.2f) doing [%@] at (%.2f,%.2f)", e.t0, k.id, k.prop, partName[Int(k.part)], e.maxD * 100, e.frames, e.stage, e.pt.x, e.pt.y, e.pt.z, e.cen.x, e.cen.y, e.cen.z, e.doing, e.at.x, e.at.y)
            } else { eps[k] = e }
        }
        // two drawn skins sunk into each other while the Spa door is open
        if care.groom.inScene, care.groom.phase == .reveal {
            let ids = jobs.map(\.id)
            for (i, a) in ids.enumerated() { for c in ids[(i + 1)...] {
                guard let g = ContactField.gap(a, c, features: false) else { continue }
                let key = a * 64 + c, sunk = g < -0.02
                if sunk { pairAgg.frames += 1; pairAgg.maxD = max(pairAgg.maxD, -g); if pairNow[key] != true { pairNow[key] = true; pairAgg.episodes += 1
                    let pa = byID[a]?.sim.centroid() ?? .zero, pc = byID[c]?.sim.centroid() ?? .zero
                    NSLog("[clip] pair start t=%.1f %d/%d sunk=%.1fcm at (%.2f,%.2f) / (%.2f,%.2f) doing [%@] / [%@]", t, a, c, -g * 100, pa.x, pa.z, pc.x, pc.z, doing(byID[a]?.brain), doing(byID[c]?.brain)) } }
                else if pairNow[key] == true { pairNow[key] = false }
            } }
        }
        let now = CACurrentMediaTime()
        if lastSum == 0 { lastSum = now }
        if now - lastSum >= 20 {
            lastSum = now
            for (k, a) in agg.sorted(by: { $0.key < $1.key }) { NSLog("[clip] sum %@ episodes=%d frames=%d over1cm=%d maxDepth=%.1fcm", k, a.episodes, a.frames, a.over1, a.maxD * 100) }
            NSLog("[clip] sum pairs(door) episodes=%d frames=%d maxSunk=%.1fcm frames-total=%d", pairAgg.episodes, pairAgg.frames, pairAgg.maxD * 100, frame)
        }
    }
}
#endif
