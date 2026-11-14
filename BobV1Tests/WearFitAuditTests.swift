//
//  WearFitAuditTests.swift
//  Body wear fit: how far every neck / chest / back / waist piece sits inside or off the DRAWN skinned body, per frame, per motion, per Jelbie.
//  Not a pure regression test on its own: the audit (testAuditBodyWear) writes a table when WEARFIT_DIR is set (TEST_RUNNER_WEARFIT_DIR) and
//  asserts the shipped bounds always; testPickerSpin renders the Jelly Spring framing at every 15 degrees of the spin; testGrid renders every
//  piece x 4 Jelbies x 3 angles. WEARFIT_TAG names the output files (before / after); WEARFIT_ONLY=a,b limits the pieces.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

/// Signed distance to the DRAWN body: the union of the egg, the arm capsules, the foot beans and Pip's tail block (each closed component on its own,
/// min over components, so a point inside the egg but outside a capsule that hides inside it is still inside).
final class SkinField {
    struct Comp {
        var tris: [SIMD3<UInt32>] = []
        var cells: [[Int32]] = []
        var dim = SIMD3<Int>(1, 1, 1)
        var lo = SIMD3<Float>.zero, hi = SIMD3<Float>.zero
        var cell: Float = 0.035
        var stamp: [UInt32] = []
    }
    var comps: [Comp] = []
    var clock: UInt32 = 0
    var skipArms = false
    let pos: [SIMD3<Float>], nrm: [SIMD3<Float>]
    nonisolated(unsafe) static var compOf: [Int32] = []
    nonisolated(unsafe) static var compCount = 0
    nonisolated(unsafe) static var bodyTris: [SIMD3<UInt32>] = []
    nonisolated(unsafe) static var compName: [String] = []

    static func prepare(_ rm: RenderMesh) {
        guard compOf.isEmpty else { return }
        let end = rm.body.first + rm.body.count
        var parent = [Int32](0..<Int32(rm.vertexCount))
        func find(_ a: Int32) -> Int32 { var x = a; while parent[Int(x)] != x { parent[Int(x)] = parent[Int(parent[Int(x)])]; x = parent[Int(x)] }; return x }
        var i = rm.body.first
        var tris: [SIMD3<UInt32>] = []
        while i + 2 < end {
            let t = SIMD3(rm.index[i], rm.index[i + 1], rm.index[i + 2]); tris.append(t)
            let a = find(Int32(t.x)), b = find(Int32(t.y)), c = find(Int32(t.z))
            parent[Int(b)] = a; parent[Int(find(c))] = a
            i += 3
        }
        bodyTris = tris
        var ids: [Int32: Int32] = [:]
        compOf = [Int32](repeating: -1, count: rm.vertexCount)
        for t in tris { for v in [t.x, t.y, t.z] { let r = find(Int32(v)); if ids[r] == nil { ids[r] = Int32(ids.count) }; compOf[Int(v)] = ids[r]! } }
        compCount = ids.count
        var sum = [SIMD3<Float>](repeating: .zero, count: compCount), cnt = [Int](repeating: 0, count: compCount)
        for t in tris { let k = Int(compOf[Int(t.x)]); for v in [t.x, t.y, t.z] { sum[k] += SIMD3(rm.rest[3 * Int(v)], rm.rest[3 * Int(v) + 1], rm.rest[3 * Int(v) + 2]); cnt[k] += 1 } }
        compName = (0..<compCount).map { k in
            let m = sum[k] / Float(max(cnt[k], 1))
            if cnt[k] == cnt.max()! { return "egg" }
            if m.z < -0.3 { return "tail" }
            if abs(m.x) > 0.3 { return m.x > 0 ? "armR" : "armL" }
            return "foot\(m.x > 0 ? "R" : "L")"
        }
    }

    /// From 6 floats per vertex (position, smooth normal), as the skinner writes them.
    init(skin s: [Float]) {
        var p: [SIMD3<Float>] = [], n: [SIMD3<Float>] = []
        let vc = s.count / 6
        p.reserveCapacity(vc); n.reserveCapacity(vc)
        for v in 0..<vc { p.append(SIMD3(s[6 * v], s[6 * v + 1], s[6 * v + 2])); n.append(SIMD3(s[6 * v + 3], s[6 * v + 4], s[6 * v + 5])) }
        pos = p; nrm = n
        build()
    }
    /// From the rest mesh.
    init(rest rm: RenderMesh, skipArms: Bool = false) {
        self.skipArms = skipArms
        var p: [SIMD3<Float>] = [], n: [SIMD3<Float>] = []
        for v in 0..<rm.vertexCount {
            p.append(SIMD3(rm.rest[3 * v], rm.rest[3 * v + 1], rm.rest[3 * v + 2])); n.append(SIMD3(rm.restNormal[3 * v], rm.restNormal[3 * v + 1], rm.restNormal[3 * v + 2]))
        }
        pos = p; nrm = n
        build()
    }

    private func build() {
        comps = [Comp](repeating: Comp(), count: Self.compCount)
        for t in Self.bodyTris {
            let a = pos[Int(t.x)], b = pos[Int(t.y)], c = pos[Int(t.z)]
            if simd_length(simd_cross(b - a, c - a)) < 1e-9 { continue }          // collapsed (Pip's tail on another Jelbie)
            comps[Int(Self.compOf[Int(t.x)])].tris.append(t)
        }
        for k in comps.indices {
            var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
            for t in comps[k].tris { for v in [t.x, t.y, t.z] { lo = simd_min(lo, pos[Int(v)]); hi = simd_max(hi, pos[Int(v)]) } }
            guard !comps[k].tris.isEmpty else { continue }
            lo -= 0.01
            comps[k].lo = lo; comps[k].hi = hi
            let d = simd_max(SIMD3<Float>(repeating: 1), ((hi + 0.01 - lo) / comps[k].cell).rounded(.up))
            comps[k].dim = SIMD3(Int(d.x), Int(d.y), Int(d.z))
            comps[k].cells = [[Int32]](repeating: [], count: comps[k].dim.x * comps[k].dim.y * comps[k].dim.z)
            comps[k].stamp = [UInt32](repeating: 0, count: comps[k].tris.count)
            for (ti, t) in comps[k].tris.enumerated() {
                let a = pos[Int(t.x)], b = pos[Int(t.y)], c = pos[Int(t.z)]
                let i0 = cellOf(simd_min(a, simd_min(b, c)), comps[k]), i1 = cellOf(simd_max(a, simd_max(b, c)), comps[k])
                for z in i0.z...i1.z { for y in i0.y...i1.y { for x in i0.x...i1.x { comps[k].cells[(z * comps[k].dim.y + y) * comps[k].dim.x + x].append(Int32(ti)) } } }
            }
        }
    }
    private func cellOf(_ q: SIMD3<Float>, _ c: Comp) -> SIMD3<Int> {
        let f = ((q - c.lo) / c.cell).rounded(.down)
        return SIMD3(min(max(Int(f.x), 0), c.dim.x - 1), min(max(Int(f.y), 0), c.dim.y - 1), min(max(Int(f.z), 0), c.dim.z - 1))
    }

    /// Signed distance of component `k` at `p` (positive outside); `limit` when nothing is that close.
    private func sd(_ k: Int, _ p: SIMD3<Float>, limit: Float) -> Float {
        clock &+= 1
        let stampNow = clock
        let cellSize = comps[k].cell, dim = comps[k].dim
        let c0 = cellOf(p, comps[k])
        var best = Float.infinity, bestSign: Float = 1
        var r = 0
        let maxR = Int((limit / cellSize).rounded(.up)) + 1
        while r <= maxR {
            for z in max(c0.z - r, 0)...min(c0.z + r, dim.z - 1) { for y in max(c0.y - r, 0)...min(c0.y + r, dim.y - 1) { for x in max(c0.x - r, 0)...min(c0.x + r, dim.x - 1) {
                if r > 0, abs(x - c0.x) != r, abs(y - c0.y) != r, abs(z - c0.z) != r { continue }
                let ci = (z * dim.y + y) * dim.x + x
                for ti in comps[k].cells[ci] {
                    if comps[k].stamp[Int(ti)] == stampNow { continue }
                    comps[k].stamp[Int(ti)] = stampNow
                    let t = comps[k].tris[Int(ti)]
                    let a = pos[Int(t.x)], b = pos[Int(t.y)], d = pos[Int(t.z)]
                    let w = WearBody.closest(p, a, b, d)
                    let q = a * w.x + b * w.y + d * w.z
                    let dd = simd_distance_squared(p, q)
                    if dd < best {
                        best = dd
                        var n = nrm[Int(t.x)] * w.x + nrm[Int(t.y)] * w.y + nrm[Int(t.z)] * w.z
                        let fn = simd_cross(b - a, d - a)
                        if simd_length(n) < 1e-6 || (min(w.x, min(w.y, w.z)) > 0.002 && simd_dot(fn, n) > 0) { n = fn }          // inside a face: the face's own side (smooth normals are blended near the tail root)
                        bestSign = simd_dot(p - q, n) < 0 ? -1 : 1
                    }
                }
            } } }
            if best.isFinite, best.squareRoot() <= Float(r) * cellSize { break }
            r += 1
        }
        guard best.isFinite else { return limit }
        if bestSign < 0, Self.compName[k] != "egg", !parityInside(k, p) { bestSign = 1 }               // the nearest-face sign can be wrong on a thin or blended block: a closed mesh is inside only when a ray from there crosses it an odd number of times
        return bestSign * best.squareRoot()
    }

    private func parityInside(_ k: Int, _ p: SIMD3<Float>) -> Bool {
        let dir = simd_normalize(SIMD3<Float>(0.123, 0.987, 0.101))
        var crossings = 0
        for t in comps[k].tris {
            let a = pos[Int(t.x)], b = pos[Int(t.y)], c = pos[Int(t.z)]
            let e1 = b - a, e2 = c - a, h = simd_cross(dir, e2), det = simd_dot(e1, h)
            if abs(det) < 1e-12 { continue }
            let f = 1 / det, sv = p - a, u = f * simd_dot(sv, h)
            if u < 0 || u > 1 { continue }
            let q = simd_cross(sv, e1), v = f * simd_dot(dir, q)
            if v < 0 || u + v > 1 { continue }
            if f * simd_dot(e2, q) > 1e-6 { crossings += 1 }
        }
        return crossings % 2 == 1
    }
    func sd(_ p: SIMD3<Float>, limit: Float = 0.5) -> Float { sdOwner(p, limit: limit).d }
    /// The distance and the component that gives it ("egg", "armL/R", "foot", "tail").
    func sdOwner(_ p: SIMD3<Float>, limit: Float = 0.5) -> (d: Float, owner: String) {
        var m = limit, who = -1
        for k in comps.indices {
            let c = comps[k]
            guard !c.tris.isEmpty, !(skipArms && Self.compName[k].hasPrefix("arm")) else { continue }
            let dq = simd_max(c.lo - p, p - c.hi)
            let out = simd_length(simd_max(dq, SIMD3<Float>(repeating: 0)))
            if out >= m { continue }                                  // can't beat the best so far
            let v = sd(k, p, limit: m); if v < m { m = v; who = k }
        }
        guard who >= 0 else { return (m, "-") }
        return (m, name(who))
    }
    private func name(_ k: Int) -> String { Self.compName[k] }
}

@MainActor
final class WearFitAuditTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    nonisolated(unsafe) static var smallParts: [WearLook: [Bool]] = [:]
    typealias Outfit = [WearSlot: WearLook]
    static let charNames = ["Bob", "Pip", "Moss", "Lavender"]

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0); DayClock.shared.forcedHour = 12; WearLimbs.enabled = ProcessInfo.processInfo.environment["WEARFIT_LIMBS"] != "off"; ArmCap.collar = ProcessInfo.processInfo.environment["WEARFIT_NOCOLLAR"] == nil }
    override func tearDown() { WearLimbs.enabled = true; ArmCap.collar = true;  GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DayClock.shared.forcedHour = 12 }

    // MARK: plumbing

    private func env(_ k: String) -> String? { ProcessInfo.processInfo.environment[k].flatMap { $0.isEmpty ? nil : $0 } }
    private func dir() throws -> String {
        guard let d = env("WEARFIT_DIR") else { throw XCTSkip("WEARFIT_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    private var tag: String { env("WEARFIT_TAG") ?? "run" }

    /// The pieces of the neck, chest, back and waist slots.
    static var bodyPieces: [WearLook] { WearLook.pieces.filter { ($0.slot == .neck || $0.slot == .body) } }
    private func pieces() -> [WearLook] {
        var all = Self.bodyPieces
        if let only = env("WEARFIT_ONLY")?.split(separator: ",").map(String.init) { all = all.filter { only.contains($0.rawValue) } }
        return all
    }

    final class Ctx { let ren: MelonRenderer; let target: MTLTexture; let W: Int, H: Int
        init(ren: MelonRenderer, target: MTLTexture, W: Int, H: Int) { self.ren = ren; self.target = target; self.W = W; self.H = H } }

    private func makeCtx(sim: SoftBody, W: Int, H: Int) throws -> Ctx {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: sim.edges, particleCount: sim.n, game: true, bodyCount: 1), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        let c = Ctx(ren: ren, target: device.makeTexture(descriptor: td)!, W: W, H: H)
        Self.keep.append(ren)
        return c
    }

    struct Char { var id: Int; var outfit: Outfit = [:] }

    private func makeLab(_ id: Int, at: SIMD2<Float> = SIMD2(0.2, 0.6), quiet: Bool = true) -> SocialTests.Lab {
        let lab = SocialTests.Lab(n: 1, positions: [at], quiet: quiet, seed: 3)
        SocialTests.keep.append(lab)
        let r = lab.rigs[0]
        r.skinner.autoBlink = false
        r.brain.feature = JellyRoster.feature(id); r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        WearBody.install(MotionRig.renderMesh)
        SkinField.prepare(MotionRig.renderMesh)
        return lab
    }

    /// One WornSet per outfit entry (each wears exactly one piece) on the same body, plus the feature set.
    @MainActor final class Wardrobe { var sets: [(look: WearLook, set: WornSet)] = []; let feats = FeatureSet() }
    private func wardrobe(_ lab: SocialTests.Lab, id: Int, looks: [[WearSlot: WearLook]]) -> Wardrobe {
        let w = Wardrobe()
        w.feats.body = WearBody.shared; Self.keep.append(w.feats)
        for o in looks {
            let s = WornSet(); s.body = WearBody.shared; s.soundOn = false; Self.keep.append(s)
            w.sets.append((o.values.first!, s))
        }
        for (k, o) in looks.enumerated() { for _ in 0..<3 { tick(w.sets[k].set, lab, id, o, feats: nil) } }
        return w
    }
    private func tick(_ w: WornSet, _ lab: SocialTests.Lab, _ id: Int, _ outfit: Outfit, feats: FeatureSet?) {
        let r = lab.rigs[0]
        w.tick(id: 0, brain: r.brain, sim: r.sim, outfit: outfit, role: .none, hideAll: false, dt: 1.0 / 60)
        if let f = feats {
            var art: [String] = []
            for s in WearSlot.allCases where s != .feet { if let l = w.shown(0, s), !l.art.isEmpty { art.append(l.art) } }
            f.tick(id: 0, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(id), worn: art, hideAll: false, dt: 1.0 / 60)
            if let s = f.slot(0) { w.setArtOverride(0, s.fit.hatVariant); r.brain.wingsFolded = s.fit.folded; r.brain.wingFlapLimit = s.fit.flapMax }
        }
    }
    private func step(_ lab: SocialTests.Lab, _ wd: Wardrobe, _ id: Int, outfits: [Outfit]) {
        lab.tick(watching: false)
        let r = lab.rigs[0]
        r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
        for (k, s) in wd.sets.enumerated() { tick(s.set, lab, id, outfits[k], feats: k == 0 ? wd.feats : nil) }
    }
    private func skin(_ lab: SocialTests.Lab) -> [Float] {
        let r = lab.rigs[0]
        var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &d)
        return d
    }
    private func worldVerts(_ s: WornSet, skin sk: [Float]) -> [SIMD3<Float>] {
        let f = sk.withUnsafeBufferPointer { p in s.frame(theme: RoomTheme(), time: 0.4) { _ in p.baseAddress } }
        return f.opaque.vertices.map { SIMD3($0.pos.x, $0.pos.y, $0.pos.z) }
    }

    // MARK: motions

    struct Motion { var name: String; var start: (SocialTests.Lab) -> Void; var seconds: Float = 3; var wait: ((SocialTests.Lab) -> Bool)? }
    private func motions() -> [Motion] {
        func idle(_ k: IdleKind) -> (SocialTests.Lab) -> Void { { lab in let b = lab.rigs[0].brain; b.idleForced = true; _ = b.idleStart(k, lab.rigs[0].sim) } }
        func walk(_ dx: Float, _ dz: Float, hurry: Bool) -> (SocialTests.Lab) -> Void { { lab in
            let r = lab.rigs[0], p = r.sim.bodyPose(iterations: 3).centroid
            r.brain.hurry = hurry
            r.brain.script = .walk(target: SIMD2(p.x + dx, p.z + dz), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 } }
        return [
            Motion(name: "idle", start: { _ in }, seconds: 2),
            Motion(name: "walk", start: walk(-3, 0.2, hurry: false)),
            Motion(name: "run", start: walk(-3.5, 0.2, hurry: true)),
            Motion(name: "turn", start: walk(0, -2.5, hurry: false), seconds: 2),
            Motion(name: "sit", start: idle(.sit)),
            Motion(name: "sleep", start: { lab in let b = lab.rigs[0].brain; b.idleForced = true; _ = b.idleStart(.sleep, lab.rigs[0].sim); b.sleep.hold = 500 }, seconds: 5, wait: { $0.rigs[0].brain.isNapping }),
            Motion(name: "hop", start: idle(.bounce)),
            Motion(name: "joy", start: idle(.joy)),
            Motion(name: "yawn", start: idle(.yawn)),
            Motion(name: "jacks", start: idle(.jacks)),
            Motion(name: "flop", start: idle(.flop)),
            Motion(name: "stretch", start: idle(.stretch)),
            Motion(name: "sway", start: idle(.sway)),
            Motion(name: "backflip", start: { lab in lab.rigs[0].brain.startFlip(sim: lab.rigs[0].sim) }, seconds: 3),
        ]
    }

    // MARK: the audit

    struct Stat {
        var worstIn: Float = 0, whereIn = "", worstNew: Float = 0, whereNew = "", worstFloat: Float = 0, whereFloat = "", bufFrac: Float = 0, whereBuf = "", frames = 0
        var restIn: Float = 0
        var rigidNew: Float = 0, whereRigid = ""
        /// worst newly-buried depth that an arm, foot or tail (not the egg) is responsible for
        var worstLimb: Float = 0, whereLimb = ""
    }

    /// Measures one posed frame of one piece: updates `st`.
    private func measure(_ look: WearLook, stride: Int = 2, verts: [SIMD3<Float>], field: SkinField, rest: [Float], tag: String, st: inout Stat) {
        guard let p = WearMeshes.prepare(look, body: WearBody.shared), verts.count >= p.rest.count else { return }
        var n = 0, buried = 0
        var small: [Bool] = Self.smallParts[look] ?? {
            var r = [Bool](repeating: false, count: p.partNames.count)
            for k in p.partNames.indices {
                let vs = p.rest.indices.filter { Int(p.partOfVertex[$0]) == k }
                guard vs.count >= 8 else { continue }
                var c = SIMD3<Float>.zero
                for v in vs { c += p.rest[v] }
                c /= Float(vs.count)
                r[k] = vs.allSatisfy { simd_distance(p.rest[$0], c) <= 0.07 }
            }
            Self.smallParts[look] = r
            return r
        }()
        if small.count != p.partNames.count { small = [Bool](repeating: false, count: p.partNames.count) }
        var partFloat: [Int: (d: Float, off: Float)] = [:]
        for i in p.rest.indices where p.w[i] <= 0.001 && (i % stride == 0) {
            let (d, owner) = field.sdOwner(verts[i])
            let newly = max(0, -d - max(0, -rest[i]))
            if newly > st.rigidNew { st.rigidNew = newly; st.whereRigid = "\(tag) \(p.partNames[Int(p.partOfVertex[i])]) v\(i) by \(owner)" }
        }
        for i in p.rest.indices where p.w[i] > 0.001 && (i % stride == 0) {
            let (d, owner) = field.sdOwner(verts[i])
            let r0 = rest[i]
            let inside = max(0, -d), restInside = max(0, -r0)
            let newly = max(0, inside - restInside)
            n += 1
            let part = p.partNames[Int(p.partOfVertex[i])]
            if inside > st.worstIn { st.worstIn = inside; st.whereIn = "\(tag) \(part) v\(i) by \(owner)" }
            if newly > st.worstNew { st.worstNew = newly; st.whereNew = "\(tag) \(part) v\(i) by \(owner)" }
            let sinkEx = WearLevel.record && i < WearLevel.recRaw.count && WearLevel.recRaw[i] >= WearLevel.bulgeFull, floatEx = WearLevel.record && i < WearLevel.recBulge.count && WearLevel.recBulge[i] > 0.0005
            if newly > st.worstLimb, !sinkEx, owner.hasPrefix("arm") || owner.hasPrefix("foot") || owner.hasPrefix("tail") { st.worstLimb = newly; st.whereLimb = "\(tag) \(part) v\(i) by \(owner)" }
            if newly > 0.01 { buried += 1 }
            // float: how much further OUT of the drawn body than it was authored to stand (its offset above the skin it is bound to). A small part (a pearl, a gem) counts as a whole:
            // its NEAREST vertex against its authored nearest, so a big round gem is not "floating" by its own size; strings and bands count per vertex.
            if p.h[i] == 0, p.w[i] > 0.99, !floatEx {
                let k = Int(p.partOfVertex[i]), off = max(0, p.bind[i].off.z)
                if k < small.count, small[k] {
                    let e = partFloat[k] ?? (.infinity, .infinity)
                    partFloat[k] = (min(e.d, max(0, d)), min(e.off, off))
                } else {
                    let fl = max(0, d) - off
                    if fl > st.worstFloat { st.worstFloat = fl; st.whereFloat = "\(tag) \(part) v\(i)" }
                }
            }
        }
        for (k, e) in partFloat {
            let fl = e.d - e.off
            if fl > st.worstFloat { st.worstFloat = fl; st.whereFloat = "\(tag) \(p.partNames[k]) (whole part)" }
        }
        if n > 0 {
            let f = Float(buried) / Float(n)
            if f > st.bufFrac { st.bufFrac = f; st.whereBuf = tag }
        }
        st.frames += 1
    }

    /// rest signed distance of every vertex of a piece (the rest pose, authored position).
    private func restSD(_ look: WearLook, restField: SkinField) -> [Float] {
        guard let p = WearMeshes.prepare(look, body: WearBody.shared) else { return [] }
        let arms = WearBody.shared.restLimbs
        return p.rest.indices.map { min(restField.sd(p.rest[$0]), -arms.penetration(p.rest[$0])) }
    }

    func testAuditBodyWear() throws {
        let d = try dir()
        let list = pieces()
        WearBody.install(MotionRig.renderMesh); SkinField.prepare(MotionRig.renderMesh)
        let restField = SkinField(rest: MotionRig.renderMesh, skipArms: true)
        var rest: [WearLook: [Float]] = [:]
        for l in list { rest[l] = restSD(l, restField: restField) }
        var stats: [WearLook: [Stat]] = [:]
        var byMotion: [WearLook: [String: Float]] = [:]
        for l in list { byMotion[l] = [:] }
        for l in list { stats[l] = Array(repeating: Stat(), count: 4) }
        let outfits = list.map { [$0.slot: $0] as Outfit }
        var onlyMotions = env("WEARFIT_MOTIONS")?.split(separator: ",").map(String.init)
        if onlyMotions?.isEmpty == true { onlyMotions = nil }
        for id in 0..<4 {
            for m in motions() where onlyMotions?.contains(m.name) ?? true {
                let lab = makeLab(id)
                let wd = wardrobe(lab, id: id, looks: outfits)
                for r in lab.rigs { r.brain.autonomy = false; r.brain.expr.enabled = false }
                for _ in 0..<40 { step(lab, wd, id, outfits: outfits) }
                for _ in 0..<30 { _ = skin(lab) }
                m.start(lab)
                var t: Float = 0, wt: Float = 0
                while let w = m.wait, !w(lab), wt < 25 { step(lab, wd, id, outfits: outfits); wt += 1.0 / 60 }
                var frame = 0
                while t < m.seconds {
                    step(lab, wd, id, outfits: outfits); t += 1.0 / 60; frame += 1
                    guard frame % 4 == 0 else { continue }
                    let sk = skin(lab)
                    let field = SkinField(skin: sk)
                    for (k, l) in list.enumerated() {
                        guard wd.sets[k].set.item(0, l.slot)?.scale == 1 else { continue }          // (poofing on / off: scaled about its pivot, not a fit question)
                        let v = worldVerts(wd.sets[k].set, skin: sk)
                        var one = Stat()
                        measure(l, verts: v, field: field, rest: rest[l]!, tag: "\(Self.charNames[id]) \(m.name) t=\(String(format: "%.2f", t))", st: &one)
                        if one.worstNew > byMotion[l]![m.name, default: 0] { byMotion[l]![m.name] = one.worstNew }
                        var acc = stats[l]![id]
                        if one.worstIn > acc.worstIn { acc.worstIn = one.worstIn; acc.whereIn = one.whereIn }
                        if one.worstNew > acc.worstNew { acc.worstNew = one.worstNew; acc.whereNew = one.whereNew }
                        if one.worstFloat > acc.worstFloat { acc.worstFloat = one.worstFloat; acc.whereFloat = one.whereFloat }
                        if one.bufFrac > acc.bufFrac { acc.bufFrac = one.bufFrac; acc.whereBuf = one.whereBuf }
                        if one.worstLimb > acc.worstLimb { acc.worstLimb = one.worstLimb; acc.whereLimb = one.whereLimb }
                        if one.rigidNew > acc.rigidNew { acc.rigidNew = one.rigidNew; acc.whereRigid = one.whereRigid }
                        acc.frames += one.frames
                        stats[l]![id] = acc
                    }
                }
            }
        }
        var out = "piece, char: worst inside (m) | worst newly buried | max buried fraction | worst float vs rest | frames\n"
        var worstAll: [String] = []
        for l in list {
            for id in 0..<4 {
                let s = stats[l]![id]
                out += String(format: "%@ %@: in %.3f [%@] | new %.3f [%@] | buried %.0f%% [%@] | float %.3f [%@] | rigid new %.3f [%@] | limb-only new %.3f [%@] | n %d\n", l.rawValue, Self.charNames[id], s.worstIn, s.whereIn, s.worstNew, s.whereNew, s.bufFrac * 100, s.whereBuf, s.worstFloat, s.whereFloat, s.rigidNew, s.whereRigid, s.worstLimb, s.whereLimb, s.frames)
            }
            let w = stats[l]!
            worstAll.append(String(format: "%@ | %.3f | %.3f | %.0f%% | %.3f | %.3f | %@", l.rawValue, w.map(\.worstIn).max()!, w.map(\.worstNew).max()!, (w.map(\.bufFrac).max()!) * 100, w.map(\.worstFloat).max()!, w.map(\.rigidNew).max()!, w.max { $0.worstNew < $1.worstNew }!.whereNew + String(format: " | limb-only %.3f", w.map(\.worstLimb).max()!)))
        }
        out += "\nBY MOTION (worst newly buried over the four Jelmiko)\n"
        for l in list { out += "\(l.rawValue): " + byMotion[l]!.sorted { $0.value > $1.value }.map { String(format: "%@ %.3f", $0.key, $0.value) }.joined(separator: ", ") + "\n" }
        out += "\nSUMMARY piece | worst inside | worst newly buried | max buried fraction | worst float | rigid-part worst newly inside | where (newly buried)\n" + worstAll.joined(separator: "\n") + "\n"
        try out.write(toFile: "\(d)/numbers_\(tag).txt", atomically: true, encoding: .utf8)
        print(out)
        // shipped bound (with the limb push on): no arm, foot or tail swallows a bound piece by more than 4 cm. (What is left is the egg's own pinch under loosely carried hems and tails.)
        if WearLimbs.enabled { for l in list { for id in 0..<4 { let s = stats[l]![id]; XCTAssertLessThan(s.worstLimb, 0.04, "\(l) \(Self.charNames[id]) is \(s.worstLimb) inside a limb: \(s.whereLimb)") } } }
    }

    /// (WearLevel: vertices an arm swallows deeper than `WearLevel.bulgeFull` pass behind the arm (it is drawn over them) and vertices the limb bulge moved are exempt from the sink / float bounds; everything else keeps them.)
    /// REGRESSION: a wearable bound to the egg never ends up inside an arm, foot or tail that is out (WearLimbs): Bob, Pip (tail) and Lavender through a walk, a run, a
    /// turn, a joy jump and the jumping-jacks, every neck / chest / back / waist piece, deeper than 7 cm than it was authored; and the pearls / lei / diamond J never stand more than 3 cm farther off the body than they were authored. (The wider audit is testAuditBodyWear.)
    func testBodyWearNeverSinksIntoALimb() throws {
        WearLevel.record = true; defer { WearLevel.record = false }
        WearBody.install(MotionRig.renderMesh); SkinField.prepare(MotionRig.renderMesh)
        let list = Self.bodyPieces
        let restField = SkinField(rest: MotionRig.renderMesh, skipArms: true)
        var rest: [WearLook: [Float]] = [:]
        for l in list { rest[l] = restSD(l, restField: restField) }
        let outfits = list.map { [$0.slot: $0] as Outfit }
        var worst: Float = 0, where_ = "", frames = 0
        var floatWorst: Float = 0, floatWhere = ""
        for id in [0, 1, 3] {
            for m in motions() where ["walk", "run", "turn", "joy", "jacks"].contains(m.name) {
                let lab = makeLab(id)
                let wd = wardrobe(lab, id: id, looks: outfits)
                for r in lab.rigs { r.brain.autonomy = false; r.brain.expr.enabled = false }
                for _ in 0..<40 { step(lab, wd, id, outfits: outfits) }
                for _ in 0..<30 { _ = skin(lab) }
                m.start(lab)
                var t: Float = 0, frame = 0
                while t < min(m.seconds, 2.2) {
                    step(lab, wd, id, outfits: outfits); t += 1.0 / 60; frame += 1
                    guard frame % 8 == 0 else { continue }
                    let sk = skin(lab), field = SkinField(skin: sk)
                    for (k, l) in list.enumerated() {
                        guard wd.sets[k].set.item(0, l.slot)?.scale == 1 else { continue }
                        var one = Stat()
                        measure(l, stride: 3, verts: worldVerts(wd.sets[k].set, skin: sk), field: field, rest: rest[l]!, tag: "\(Self.charNames[id]) \(m.name) \(l.rawValue) t=\(String(format: "%.2f", t))", st: &one)
                        if one.worstLimb > worst { worst = one.worstLimb; where_ = one.whereLimb }
                        if [.pearls, .lei, .diamondJ].contains(l), one.worstFloat > floatWorst { floatWorst = one.worstFloat; floatWhere = one.whereFloat }
                        frames += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(frames, 500)
        XCTAssertLessThan(worst, 0.07, "a body wearable is \(worst) inside a limb: \(where_)")
        XCTAssertLessThan(floatWorst, 0.03, "a necklace part floats \(floatWorst) off the body: \(floatWhere)")
    }

    /// What the limb push costs: WornSet.frame for three Jelbies each in a full neck + body outfit, walking (arms out), push on vs off (printed; asserted to stay small).
    func testLimbPushCost() throws {
        WearBody.install(MotionRig.renderMesh); SkinField.prepare(MotionRig.renderMesh)
        let lab = makeLab(0)
        let outfits: [(String, Outfit)] = [("chain", [.neck: .pearls]), ("pearls", [.neck: .pearls]), ("diamondJ", [.neck: .diamondJ]), ("vest", [.body: .vestPuffer]), ("hoodie", [.body: .hoodie]), ("chain + vest", [.neck: .chainGold, .body: .vestPuffer])]
        let sets = outfits.map { _ in WornSet() }
        for (k, s) in sets.enumerated() { s.body = WearBody.shared; s.soundOn = false; for _ in 0..<3 { tick(s, lab, 0, outfits[k].1, feats: nil) } }
        let r0 = lab.rigs[0], p0 = r0.sim.bodyPose(iterations: 3).centroid
        r0.brain.script = .walk(target: SIMD2(p0.x - 3, p0.z + 0.2), then: .none); r0.brain.activity = .walking; r0.brain.scriptT = 0
        for _ in 0..<80 { lab.tick(watching: false); for (k, s) in sets.enumerated() { tick(s, lab, 0, outfits[k].1, feats: nil) } }
        let sk = skin(lab)
        var worstExtra = 0.0
        for (k, set) in sets.enumerated() {
            func time(_ on: Bool) -> Double {
                WearLimbs.enabled = on
                let n = 200
                let t0 = CFAbsoluteTimeGetCurrent()
                var verts = 0
                for _ in 0..<n { verts &+= sk.withUnsafeBufferPointer { p in set.frame(theme: RoomTheme(), time: 0.4) { _ in p.baseAddress } }.opaque.vertices.count }
                XCTAssertGreaterThan(verts, 0)
                return (CFAbsoluteTimeGetCurrent() - t0) / Double(n) * 1000
            }
            _ = time(true)
            let off = time(false), on = time(true)
            print(String(format: "LIMBCOST %@ (arms out): push off %.3f ms, on %.3f ms, extra %.3f ms", outfits[k].0, off, on, on - off))
            worstExtra = max(worstExtra, on - off)
        }
        XCTAssertLessThan(worstExtra, 1.0, "the limb push must stay under a millisecond per Jelmiko per frame")
    }

    // MARK: render

    private func camera(eye: SIMD3<Float>, target: SIMD3<Float>, aspect: Float = 1) -> CameraState {
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        return cam
    }
    private func pose(_ sim: SoftBody, memo: inout SIMD3<Float>) -> (c: SIMD3<Float>, fwd: SIMD3<Float>) {
        let p = sim.bodyPose(iterations: 3)
        var f = p.rotation.act(SIMD3<Float>(0, 0, 1)); f.y = 0
        if simd_length(f) > 0.3 { memo = simd_normalize(f) }
        return (p.centroid, memo)
    }
    /// Room-style orbit round the body: yaw measured from its facing.
    private func orbit(_ sim: SoftBody, memo: inout SIMD3<Float>, yaw: Float, dist: Float = 3.6, lookY: Float = 0.2, lookBack: Float = 0.35, lift: Float = 0.12) -> CameraState {
        let (c, fwd) = pose(sim, memo: &memo)
        let t = SIMD3(c.x - fwd.x * lookBack, c.y + lookY, c.z - fwd.z * lookBack)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        return camera(eye: t + dir * dist + SIMD3(0, dist * lift, 0), target: t)
    }
    /// The species picker's framing at `yaw` (PhotoCam orbit over the focus close-up), from the jelly's facing at the moment the spot was set.
    struct PickerRig { var fp: (eye: SIMD3<Float>, target: SIMD3<Float>); var v0: SIMD3<Float> }
    private func pickerRig(_ lab: SocialTests.Lab, memo: inout SIMD3<Float>) -> PickerRig {
        let r = lab.rigs[0]
        let (_, fwd) = pose(r.sim, memo: &memo)
        let spot = GameCare.floorPos(r.brain, r.sim)
        let fp = GameCamera.focusPose(aspect: 1, spot: spot)
        var v0 = fp.eye - fp.target
        let hl: Float = simd_length(SIMD2<Float>(v0.x, v0.z))
        v0.x = fwd.x * hl; v0.z = fwd.z * hl
        return PickerRig(fp: (fp.eye, fp.target), v0: v0)
    }
    private func pickerCam(_ pr: PickerRig, yaw: Float, pitch: Float = 0) -> CameraState {
        let (sy, sp, sz, spn) = (PhotoCam.yaw, PhotoCam.pitch, PhotoCam.zoom, PhotoCam.pan)
        defer { PhotoCam.yaw = sy; PhotoCam.pitch = sp; PhotoCam.zoom = sz; PhotoCam.pan = spn }
        PhotoCam.yaw = yaw; PhotoCam.pitch = pitch; PhotoCam.zoom = PickerCamera.startZoom; PhotoCam.pan = .zero
        let e = PhotoCam.apply(eye: pr.fp.target + pr.v0, target: pr.fp.target)
        return camera(eye: e.eye, target: e.target)
    }

    /// Renders the Jelbie with `worn` (and his features), others nothing; neutral = cut out on a light backdrop.
    private func render(_ c: Ctx, _ lab: SocialTests.Lab, id: Int, worn: WornSet, feats: FeatureSet, cam: CameraState) -> LockImage {
        let ren = c.ren, W = c.W, H = c.H
        let r = lab.rigs[0]
        let vc = MotionRig.renderMesh.vertexCount
        func shot(visible: Bool) -> LockImage {
            ren.beginFrame()
            ren.setHidden(!visible, body: 0)
            let p = ren.dynPointer(body: 0)
            if visible { r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: p) }
            else { for v in 0..<vc { p[6 * v] = 0; p[6 * v + 1] = -60; p[6 * v + 2] = 0; p[6 * v + 3] = 0; p[6 * v + 4] = 1; p[6 * v + 5] = 0 } }
            if visible {
                let sk = skin(lab)
                var f = sk.withUnsafeBufferPointer { q in worn.frame(theme: ren.room!.theme, time: 0.4) { _ in q.baseAddress } }
                let ff = sk.withUnsafeBufferPointer { q in feats.frame { _ in q.baseAddress } }
                let base = UInt32(f.opaque.vertices.count)
                f.opaque.vertices += ff.vertices; f.opaque.indices += ff.indices.map { $0 + base }
                ren.room!.setWear(opaque: f.opaque, translucent: f.translucent, bounds: [])
                ren.room!.setShoes(RoomMesh())
                ren.setJersey(worn.jersey(0), body: 0)
                ren.setMouth(r.brain.mouthOpen, body: 0)
            } else {
                ren.room!.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []); ren.room!.setShoes(RoomMesh()); ren.setJersey(nil, body: 0)
            }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = JellyRoster.palette(id) ?? PaletteKey.blue.palette
            ren.setPalette(pal, body: 0)
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: GameCamera.light(centroids: [r.sim.centroid()]), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: c.target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { c.target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            return LockImage(w: W, h: H, bgra: px)
        }
        ren.dayHourOverride = 12
        _ = shot(visible: false)
        let b = shot(visible: true)
        let empty = shot(visible: false)
        var out = b
        for p in 0..<(W * H) {
            var dd = 0
            for k in 0..<3 { dd = max(dd, abs(Int(b.bgra[4 * p + k]) - Int(empty.bgra[4 * p + k]))) }
            if dd <= 3 { out.bgra[4 * p] = 236; out.bgra[4 * p + 1] = 232; out.bgra[4 * p + 2] = 228; out.bgra[4 * p + 3] = 255 }
        }
        return out
    }

    private func label(_ img: UIImage, _ text: String, bar: CGFloat = 30) -> UIImage {
        let w = img.size.width, h = img.size.height
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + bar), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + bar))
            (text as NSString).draw(at: CGPoint(x: 6, y: 6), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white])
            img.draw(in: CGRect(x: 0, y: bar, width: w, height: h))
        }
    }
    private func sheet(_ imgs: [UIImage], cols: Int) -> UIImage {
        let cw = imgs.map { $0.size.width }.max() ?? 0, ch = imgs.map { $0.size.height }.max() ?? 0
        let rows = (imgs.count + cols - 1) / cols
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: cw * CGFloat(cols), height: ch * CGFloat(rows)), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: cw * CGFloat(cols), height: ch * CGFloat(rows)))
            for (i, im) in imgs.enumerated() { im.draw(at: CGPoint(x: CGFloat(i % cols) * cw, y: CGFloat(i / cols) * ch)) }
        }
    }
    private func write(_ img: UIImage, _ path: String) throws { try img.pngData()!.write(to: URL(fileURLWithPath: path)) }

    // MARK: the Jelly Spring spin

    /// Lavender (roster 3) in pearls with her wings, in the Jelly Spring framing, spun through every 15 degrees over ~3 s of her own idle (autonomy on).
    /// Each cell carries the buried numbers of that frame. WEARFIT_LOOK names another piece, WEARFIT_CHAR another Jelbie.
    func testPickerSpin() throws {
        let d = try dir()
        let id = Int(env("WEARFIT_CHAR") ?? "3") ?? 3
        let look = WearLook(rawValue: env("WEARFIT_LOOK") ?? "pearls") ?? .pearls
        let outfit: Outfit = [look.slot: look]
        let lab = makeLab(id, at: GameCamera.callSpot, quiet: env("WEARFIT_BUSY") == nil)
        let wd = wardrobe(lab, id: id, looks: [outfit])
        for r in lab.rigs { r.brain.expr.enabled = false }
        for _ in 0..<40 { step(lab, wd, id, outfits: [outfit]) }
        for _ in 0..<30 { _ = skin(lab) }
        let c = try makeCtx(sim: lab.rigs[0].sim, W: 420, H: 420)
        var memo = SIMD3<Float>(0, 0, 1)
        let pr = pickerRig(lab, memo: &memo)
        let restField = SkinField(rest: MotionRig.renderMesh, skipArms: true)
        let rest = restSD(look, restField: restField)
        if let pp = WearMeshes.prepare(look, body: WearBody.shared) {
            print("CLUSTERS tris \(WearBody.shared.tris.count) \(look): parts \(pp.partNames.count) clusters \(pp.clusterRep.filter { $0 >= 0 }.count) free \(pp.limbFree.filter { $0 }.count)/\(pp.rest.count) names \(pp.partNames)")
        }
        var cells: [UIImage] = [], report = ""
        print("COLLAR ids \(lab.rigs[0].brain.armCollar.ids.count) delta \(lab.rigs[0].skinner.armCollarDelta.count) enabled \(ArmCap.enabled) collar \(ArmCap.collar)")
        let n = 24, fixedYaw = Float(env("WEARFIT_YAW") ?? "")
        var frame = 0
        let freeze = Int(env("WEARFIT_FREEZE") ?? "")
        if let freeze { for _ in 0..<freeze { step(lab, wd, id, outfits: [outfit]); frame += 1 } }
        for k in 0..<n {
            if freeze == nil { for _ in 0..<(fixedYaw == nil ? 7 : 5) { step(lab, wd, id, outfits: [outfit]); frame += 1 } }
            let yaw = fixedYaw.map { $0 * .pi / 180 } ?? Float(k) * .pi / 12
            let sk = skin(lab)
            let field = SkinField(skin: sk)
            var stOn = Stat(), stOff = Stat()
            let br = lab.rigs[0].brain
            var txt = ""
            var pair: [UIImage] = []
            for on in [WearLimbs.enabled] {
                var st = Stat()
                measure(look, verts: worldVerts(wd.sets[0].set, skin: sk), field: field, rest: rest, tag: "f\(frame)", st: &st)
                if on { stOn = st } else { stOff = st }
                let img = render(c, lab, id: id, worn: wd.sets[0].set, feats: wd.feats, cam: pickerCam(env("WEARFIT_FOLLOW") != nil ? pickerRig(lab, memo: &memo) : pr, yaw: yaw, pitch: 0.1))
                txt = String(format: "%@ yaw %d f%d armG %.2f new %.3f buried %.0f%%", on ? "AFTER" : "BEFORE", k * 15, frame, br.armG, st.worstNew, st.bufFrac * 100)
                let ui = label(img.uiImage()!, txt)
                pair.append(ui)
                try write(ui, "\(d)/spin_\(on ? "after" : "before")_\(Self.charNames[id])_\(look.rawValue)_\(String(format: "%03d", fixedYaw == nil ? k * 15 : k)).png")
            }
            _ = stOn
            report += String(format: "yaw %d f%d armG %.2f blend %.2f | before new %.3f [%@] | after new %.3f [%@] | after ABSOLUTE in %.3f [%@]\n", k * 15, frame, br.armG, br.armBlendNow, stOff.worstNew, stOff.whereNew, stOn.worstNew, stOn.whereNew, stOn.worstIn, stOn.whereIn)
            cells += pair
        }
        try write(sheet(cells, cols: 4), "\(d)/spin_\(tag)_\(Self.charNames[id])_\(look.rawValue).png")
        try report.write(toFile: "\(d)/spin_\(tag)_\(Self.charNames[id])_\(look.rawValue).txt", atomically: true, encoding: .utf8)
        print(report)
    }

    // MARK: the grid

    /// Every body piece x 4 Jelbies x 3 angles (side, back 3/4, picker): individual cells to WEARFIT_DIR/cells_<tag>/<piece>_<char>_<angle>.png.
    func testGrid() throws {
        let d = try dir()
        let list = pieces()
        let outfits = list.map { [$0.slot: $0] as Outfit }
        let pickYaw = (Float(env("WEARFIT_PICKYAW") ?? "") ?? 300) * .pi / 180
        for t in ["before", "after"] { try FileManager.default.createDirectory(atPath: "\(d)/cells_\(t)", withIntermediateDirectories: true) }
        for id in 0..<4 {
            let lab = makeLab(id, at: GameCamera.callSpot)
            let wd = wardrobe(lab, id: id, looks: outfits)
            for r in lab.rigs { r.brain.autonomy = false; r.brain.expr.enabled = false }
            for _ in 0..<40 { step(lab, wd, id, outfits: outfits) }
            for _ in 0..<30 { _ = skin(lab) }
            // the grid is shot while he walks, so the arms are out (at rest nothing differs): a walk 1.3 s in
            let r0 = lab.rigs[0], p0 = r0.sim.bodyPose(iterations: 3).centroid
            r0.brain.hurry = false
            r0.brain.script = .walk(target: SIMD2(p0.x - 3, p0.z + 0.2), then: .none); r0.brain.activity = .walking; r0.brain.scriptT = 0
            for _ in 0..<80 { step(lab, wd, id, outfits: outfits) }
            let c = try makeCtx(sim: lab.rigs[0].sim, W: 300, H: 300)
            var memo = SIMD3<Float>(0, 0, 1)
            let pr = pickerRig(lab, memo: &memo)
            for (k, l) in list.enumerated() {
                let cams: [(String, CameraState)] = [("side", orbit(lab.rigs[0].sim, memo: &memo, yaw: .pi / 2)), ("back34", orbit(lab.rigs[0].sim, memo: &memo, yaw: 2.5)), ("picker", pickerCam(pr, yaw: pickYaw, pitch: 0.1))]
                for on in [WearLimbs.enabled] {
                    for (n, cam) in cams {
                        try write(render(c, lab, id: id, worn: wd.sets[k].set, feats: wd.feats, cam: cam).uiImage()!, "\(d)/cells_\(on ? "after" : "before")/\(l.rawValue)_\(Self.charNames[id])_\(n).png")
                    }
                }
            }
        }
    }

    // MARK: one frame, looked at

    /// WEARFIT_SNAP=<char id>:<motion>:<piece>:<t,t,..> renders that motion's frames from the side, 3/4 back and front, and prints the worst vertex of the frame.
    func testSnap() throws {
        let d = try dir()
        guard let spec = env("WEARFIT_SNAP")?.split(separator: ":").map(String.init), spec.count == 4, let id = Int(spec[0]), let look = WearLook(rawValue: spec[2]) else { throw XCTSkip("WEARFIT_SNAP not set") }
        let times = spec[3].split(separator: ",").compactMap { Float($0) }
        guard let m = motions().first(where: { $0.name == spec[1] }) else { return XCTFail("no motion \(spec[1])") }
        let outfit: Outfit = [look.slot: look]
        let lab = makeLab(id)
        let wd = wardrobe(lab, id: id, looks: [outfit])
        for r in lab.rigs { r.brain.autonomy = false; r.brain.expr.enabled = false }
        for _ in 0..<40 { step(lab, wd, id, outfits: [outfit]) }
        for _ in 0..<30 { _ = skin(lab) }
        m.start(lab)
        var wt: Float = 0
        while let w = m.wait, !w(lab), wt < 25 { step(lab, wd, id, outfits: [outfit]); wt += 1.0 / 60 }
        let c = try makeCtx(sim: lab.rigs[0].sim, W: 420, H: 420)
        let restField = SkinField(rest: MotionRig.renderMesh, skipArms: true)
        let rest = restSD(look, restField: restField)
        var t: Float = 0, idx = 0, memo = SIMD3<Float>(0, 0, 1)
        var cells: [UIImage] = []
        while idx < times.count, t < 8 {
            step(lab, wd, id, outfits: [outfit]); t += 1.0 / 60
            guard t >= times[idx] else { continue }
            idx += 1
            let sk = skin(lab)
            var st = Stat()
            measure(look, stride: 1, verts: worldVerts(wd.sets[0].set, skin: sk), field: SkinField(skin: sk), rest: rest, tag: "t=\(t)", st: &st)
            print("SNAPFLOAT t=\(t) float \(st.worstFloat) [\(st.whereFloat)]"); print("SNAP \(spec[1]) t=\(t): in \(st.worstIn) new \(st.worstNew) [\(st.whereNew)] buried \(st.bufFrac)")
            for (n, yaw) in [("side", Float.pi / 2), ("back34", 2.5), ("front", 0), ("front34", 0.7), ("front34r", -0.7)] {
                cells.append(label(render(c, lab, id: id, worn: wd.sets[0].set, feats: wd.feats, cam: orbit(lab.rigs[0].sim, memo: &memo, yaw: yaw, dist: Float(env("WEARFIT_SNAPDIST") ?? "") ?? 3.4, lookY: Float(env("WEARFIT_SNAPY") ?? "") ?? 0.2, lookBack: Float(env("WEARFIT_SNAPBACK") ?? "") ?? 0.35)).uiImage()!, "\(Self.charNames[id]) \(spec[1]) t=\(String(format: "%.2f", t)) \(n) new \(String(format: "%.3f", st.worstNew))"))
            }
        }
        try write(sheet(cells, cols: 5), "\(d)/snap_\(tag)_\(Self.charNames[id])_\(spec[1])_\(look.rawValue).png")
    }
}
