//
//  WearBandTests.swift
//  Every wearable part that ENCIRCLES the body (a bandana string, a sweatband, a bow-tie band, a waistband, a necklace string ...) must read as a straight, level loop
//  in the body's own frame while he walks, hops, leans and squashes: each vertex keeps its authored height (+-3 mm), the loop never crosses the drawn skin, and it never
//  breaks (adjacent vertices stay within 1.5x their rest spacing). Loops are found GEOMETRICALLY from the authored art (a bound, non-hanging, thin part whose
//  vertices cover the azimuth round the body axis), so a future item inherits the check.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WearBandTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    typealias Outfit = [WearSlot: WearLook]

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0); DayClock.shared.forcedHour = 12 }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    struct Loop { var look: WearLook; var part: String; var verts: [Int]; var y0: [Float]; var edges: [(Int, Int, Float)]; var coverage: Float }

    static func axisZ() -> Float {
        let b = WearBody.shared
        var s: Float = 0, n: Float = 0
        for i in 0..<min(b.eggVertexLimit, b.pos.count) { s += b.pos[i].z; n += 1 }
        return s / max(n, 1)
    }

    /// Loops of a piece from the AUTHORED art (before any lift): vertex index in the prepared piece, authored height, authored edges.
    static func loops(_ l: WearLook) -> [Loop] {
        guard l.slot != .hands, l.slot != .feet, let a = WearMeshes.art(l) else { return [] }
        let zc = axisZ()
        var out: [Loop] = []
        var base = 0
        for part in a.parts {
            defer { base += part.positions.count }
            let rule = WearRules.rule(l, part: part.name)
            guard rule.w0 > 0.99, rule.w1 > 0.99, rule.h0 == 0, rule.h1 == 0, part.positions.count >= 8 else { continue }
            let pts = part.positions.map { l.row.anchorRest + $0 }
            let ys = pts.map(\.y)
            guard let lo = ys.min(), let hi = ys.max(), hi - lo <= 0.21 else { continue }
            var c = SIMD3<Float>.zero
            for p in pts { c += p }
            c /= Float(pts.count)
            if pts.allSatisfy({ simd_distance($0, c) <= 0.07 }) { continue }                    // a pearl / gem: a small rigid part, not the loop
            let isLink = pts.allSatisfy { simd_distance($0, c) <= 0.12 } && isChain(l)
            var bins = Set<Int>()
            for p in pts { bins.insert(Int(((atan2(p.x, p.z - zc) + .pi) / (2 * .pi) * 36).rounded(.down)) % 36) }
            let cov = Float(bins.count) / 36
            guard cov >= 24.0 / 36 - 0.001 || isLink else { continue }
            var edges: [(Int, Int, Float)] = []
            var t = 0
            while t + 2 < part.indices.count {
                for (u, v) in [(0, 1), (1, 2), (2, 0)] {
                    let i = Int(part.indices[t + u]), j = Int(part.indices[t + v])
                    edges.append((base + i, base + j, simd_distance(pts[i], pts[j])))
                }
                t += 3
            }
            out.append(Loop(look: l, part: part.name, verts: Array(base..<(base + pts.count)), y0: ys, edges: edges, coverage: cov))
        }
        return out
    }

    /// The small rigid parts of a piece with an encircling loop or a chain of them (pearls, links, gems, flowers, dots, a knot): (first vertex, count, authored mean height).
    static func smallParts(_ l: WearLook) -> [(first: Int, count: Int, y: Float)] {
        guard l.slot != .hands, l.slot != .feet, let a = WearMeshes.art(l) else { return [] }
        var out: [(Int, Int, Float)] = []
        var base = 0
        for part in a.parts {
            defer { base += part.positions.count }
            let r = WearRules.rule(l, part: part.name)
            guard r.w0 > 0.99, r.w1 > 0.99, r.h0 == 0, r.h1 == 0, part.positions.count >= 8 else { continue }
            let pts = part.positions.map { l.row.anchorRest + $0 }
            var c = SIMD3<Float>.zero
            for q in pts { c += q }
            c /= Float(pts.count)
            if pts.allSatisfy({ simd_distance($0, c) <= 0.07 }) { out.append((base, pts.count, c.y)) }
        }
        return out
    }
    /// A chain of small parts round the body (pearls, links, gems, lei flowers) counts as a loop even with no string part.
    static func isChain(_ l: WearLook) -> Bool {
        let zc = axisZ()
        guard let a = WearMeshes.art(l), l.slot != .hands, l.slot != .feet else { return false }
        var bins = Set<Int>(), n = 0
        for part in a.parts {
            let r = WearRules.rule(l, part: part.name)
            guard r.w0 > 0.99, r.w1 > 0.99, r.h0 == 0, r.h1 == 0, part.positions.count >= 8 else { continue }
            let pts = part.positions.map { l.row.anchorRest + $0 }
            var c = SIMD3<Float>.zero
            for q in pts { c += q }
            c /= Float(pts.count)
            if pts.allSatisfy({ simd_distance($0, c) <= 0.12 }) { n += 1; bins.insert(Int(((atan2(c.x, c.z - zc) + .pi) / (2 * .pi) * 36).rounded(.down)) % 36) }
        }
        return n >= 8 && bins.count >= 24
    }
    static var candidates: [WearLook] { WearLook.pieces.filter { ($0.slot == .neck || $0.slot == .head || $0.slot == .body) && (!loops($0).isEmpty || isChain($0)) } }

    func testInventory() throws {
        WearBody.install(MotionRig.renderMesh)
        var s = ""
        for l in Self.candidates {
            let ls = Self.loops(l)
            guard let a = WearMeshes.art(l) else { continue }
            let names = a.parts.map { p -> String in let r = WearRules.rule(l, part: p.name); return "\(p.name)[n\(p.positions.count) w\(r.w0)/\(r.w1) h\(r.h0)/\(r.h1)]" }
            let zc = Self.axisZ()
            for part in a.parts where part.positions.count >= 30 {
                let r = WearRules.rule(l, part: part.name); guard r.w0 > 0.99, r.h1 == 0 else { continue }
                let pts = part.positions.map { l.row.anchorRest + $0 }
                var bins = Set<Int>(); for q in pts { bins.insert(Int(((atan2(q.x, q.z - zc) + .pi) / (2 * .pi) * 36).rounded(.down)) % 36) }
                var sec = [Float](repeating: 0, count: 12), cnt = [Float](repeating: 0, count: 12)
                for q in pts { let k = Int(((atan2(q.x, q.z - zc) + .pi) / (2 * .pi) * 12).rounded(.down)) % 12; sec[k] += q.y; cnt[k] += 1 }
                if bins.count >= 24 { s += "   SECT \(l.rawValue).\(part.name) mean y by azimuth sector (from -180deg, 30deg each): " + (0..<12).map { cnt[$0] > 0 ? String(format: "%.3f", sec[$0] / cnt[$0]) : "-" }.joined(separator: " ") + "\n" }
                s += "   \(l.rawValue).\(part.name): y \(String(format: "%.3f", pts.map(\.y).min()!))..\(String(format: "%.3f", pts.map(\.y).max()!)) cov \(bins.count)/36 n\(pts.count)\n"
            }
            s += "\(l.rawValue) (\(l.slot)) LOOPS: \(ls.map { "\($0.part) y\(String(format: "%.3f", $0.y0.min()!))..\(String(format: "%.3f", $0.y0.max()!)) cov\(String(format: "%.2f", $0.coverage))" }) | parts: \(names.joined(separator: " "))\n"
        }
        print("BANDINV\n" + s)
        if let d = ProcessInfo.processInfo.environment["BAND_DIR"] { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true); try s.write(toFile: d + "/inventory.txt", atomically: true, encoding: .utf8) }
    }

    // MARK: rig

    private func makeLab(_ id: Int) -> SocialTests.Lab {
        let lab = SocialTests.Lab(n: 1, positions: [SIMD2(0.2, 0.6)], quiet: true, seed: 3)
        SocialTests.keep.append(lab)
        let r = lab.rigs[0]
        r.skinner.autoBlink = false
        r.brain.feature = JellyRoster.feature(id); r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        r.brain.autonomy = false; r.brain.expr.enabled = false
        WearBody.install(MotionRig.renderMesh); SkinField.prepare(MotionRig.renderMesh)
        return lab
    }
    private func skin(_ lab: SocialTests.Lab) -> [Float] {
        let r = lab.rigs[0]
        var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &d)
        return d
    }

    struct Motion { var name: String; var start: (SocialTests.Lab) -> Void; var seconds: Float }
    private func motions() -> [Motion] {
        func idle(_ k: IdleKind) -> (SocialTests.Lab) -> Void { { lab in let b = lab.rigs[0].brain; b.idleForced = true; _ = b.idleStart(k, lab.rigs[0].sim) } }
        func walk(_ dx: Float, _ dz: Float, hurry: Bool) -> (SocialTests.Lab) -> Void { { lab in
            let r = lab.rigs[0], p = r.sim.bodyPose(iterations: 3).centroid
            r.brain.hurry = hurry
            r.brain.script = .walk(target: SIMD2(p.x + dx, p.z + dz), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 } }
        return [Motion(name: "walk", start: walk(-3, 0.2, hurry: false), seconds: 2.5),
                Motion(name: "run", start: walk(-3.5, 0.2, hurry: true), seconds: 2.2),
                Motion(name: "hop", start: idle(.bounce), seconds: 2.5),
                Motion(name: "lean", start: idle(.sway), seconds: 2.5),
                Motion(name: "squish", start: idle(.joy), seconds: 2.5),
                Motion(name: "jacks", start: idle(.jacks), seconds: 2.5)]
    }

    struct Worst { var dyPart: Float = 0, dyPartWhere = ""; var dy: Float = 0, dyWhere = ""; var inside: Float = 0, insideWhere = ""; var insideLimb: Float = 0, insideLimbWhere = ""; var stretch: Float = 0, stretchWhere = ""; var frames = 0 }

    func runBands(ids: [Int], only: [String]? = nil) -> [WearLook: Worst] {
        var res: [WearLook: Worst] = [:]
        let looks = Self.candidates.filter { (only == nil || only!.contains($0.rawValue)) }
        let restField = SkinField(rest: MotionRig.renderMesh, skipArms: true)
        _ = restField
        for id in ids {
            for m in motions() {
                let lab = makeLab(id)
                let r = lab.rigs[0]
                var sets: [(WearLook, WornSet)] = []
                for l in looks { let s = WornSet(); s.body = WearBody.shared; s.soundOn = false; Self.keep.append(s); sets.append((l, s)) }
                func tick() {
                    lab.tick(watching: false)
                    r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
                    for (l, s) in sets { s.tick(id: 0, brain: r.brain, sim: r.sim, outfit: [l.slot: l], role: .none, hideAll: false, dt: 1.0 / 60) }
                }
                for _ in 0..<40 { tick() }
                for _ in 0..<30 { _ = skin(lab) }
                // the DRAWN rest spacing: the settled idle frame before the motion starts
                var restEdges: [WearLook: [Float]] = [:]
                do {
                    let sk0 = skin(lab)
                    for (l, s) in sets {
                        s.syncCarry(0, sim: r.sim)
                        let f = sk0.withUnsafeBufferPointer { q in s.frame(theme: RoomTheme(), time: 0.4) { _ in q.baseAddress } }
                        let v = f.opaque.vertices.map { SIMD3($0.pos.x, $0.pos.y, $0.pos.z) }
                        restEdges[l] = Self.loops(l).flatMap { lp in lp.edges.map { e in e.0 < v.count && e.1 < v.count ? simd_distance(v[e.0], v[e.1]) : 0 } }
                    }
                }
                m.start(lab)
                var t: Float = 0, frame = 0
                while t < m.seconds {
                    tick(); t += 1.0 / 60; frame += 1
                    guard frame % 5 == 0 else { continue }
                    let sk = skin(lab), field = SkinField(skin: sk)
                    for (l, s) in sets {
                        guard s.item(0, l.slot)?.scale == 1, let p = WearMeshes.prepare(l, body: WearBody.shared) else { continue }
                        s.syncCarry(0, sim: r.sim)
                        let f = sk.withUnsafeBufferPointer { q in s.frame(theme: RoomTheme(), time: 0.4) { _ in q.baseAddress } }
                        let verts = f.opaque.vertices.map { SIMD3($0.pos.x, $0.pos.y, $0.pos.z) }
                        guard verts.count >= p.rest.count, let c = s.slot(0)?.carry else { continue }
                        let sxz = 1 / c.squash.squareRoot()
                        let Minv = simd_float3x3(diagonal: SIMD3(1 / sxz, 1 / c.squash, 1 / sxz)) * simd_float3x3(c.rotation).transpose
                        var w = res[l] ?? Worst()
                        let tag = "\(["Bob", "Pip", "Moss", "Lavender"][id]) \(m.name) t=\(String(format: "%.2f", t))"
                        var loopEdgeBase = 0
                        for lp in Self.loops(l) {
                            defer { loopEdgeBase += lp.edges.count }
                            for (k, vi) in lp.verts.enumerated() {
                                let b = Minv * (verts[vi] - c.centroid) + c.restCentroid
                                let dy = abs(b.y - lp.y0[k])
                                if dy > w.dy { w.dy = dy; w.dyWhere = "\(tag) \(lp.part) v\(vi)" }
                                let (d, owner) = field.sdOwner(verts[vi])
                                if owner.hasPrefix("egg") { if -d > w.inside { w.inside = -d; w.insideWhere = "\(tag) \(lp.part) v\(vi)" } }
                                else if -d > w.insideLimb { w.insideLimb = -d; w.insideLimbWhere = "\(tag) \(lp.part) v\(vi) by \(owner)" }
                            }
                            for (ei, (i, j, _)) in lp.edges.enumerated() {
                                let e0 = restEdges[l]?[loopEdgeBase + ei] ?? 0
                                guard e0 > 1e-4 else { continue }
                                let e = simd_distance(verts[i], verts[j]) / max(e0, 0.016)                 // (spacing vs the drawn rest, edges shorter than 16 mm measured against 16 mm: 1.5x of that = +8 mm)
                                if e > w.stretch {
                                    func bf(_ v: SIMD3<Float>) -> String { let b = Minv * (v - c.centroid) + c.restCentroid; return String(format: "rho %.3f y %.3f az %.3f", simd_length(SIMD2(b.x, b.z - WearBody.shared.axisZ)), b.y, atan2(b.x, b.z - WearBody.shared.axisZ)) }
                                    w.stretch = e; w.stretchWhere = "\(tag) \(lp.part) \(i)-\(j) rest \(e0) now \(simd_distance(verts[i], verts[j])): [\(bf(verts[i]))] [\(bf(verts[j]))] "
                                }
                            }
                        }
                        for sp in Self.smallParts(l) {
                            var mean: Float = 0
                            for i in sp.first..<(sp.first + sp.count) { mean += (Minv * (verts[i] - c.centroid) + c.restCentroid).y }
                            mean /= Float(sp.count)
                            let dyp = abs(mean - sp.y)
                            if dyp > w.dyPart { w.dyPart = dyp; w.dyPartWhere = "\(tag) part@v\(sp.first)" }
                        }
                        w.frames += 1
                        res[l] = w
                    }
                }
            }
        }
        return res
    }

    /// Straight, level, on the skin, unbroken: every encircling part, Bob and Pip, through a walk, a run, a hop, a lean, a squish and the jumping-jacks.
    func testBandsStayLevelAndUnbroken() throws {
        let only = ProcessInfo.processInfo.environment["BAND_ONLY"]?.split(separator: ",").map(String.init)
        let res = runBands(ids: [0, 1], only: only)
        var out = ""
        for (l, w) in res.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            out += String(format: "%@: frames %d | small-part height dev %.4f (%@) | height dev %.4f (%@) | inside egg skin %.4f (%@) | inside limb %.4f (%@) | stretch %.2fx (%@)\n", l.rawValue, w.frames, w.dyPart, w.dyPartWhere, w.dy, w.dyWhere, w.inside, w.insideWhere, w.insideLimb, w.insideLimbWhere, w.stretch, w.stretchWhere)
        }
        print("BANDRESULT\n" + out)
        if let d = ProcessInfo.processInfo.environment["BAND_DIR"] { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true); try? out.write(toFile: d + "/result_\(ProcessInfo.processInfo.environment["BAND_TAG"] ?? "run").txt", atomically: true, encoding: .utf8) }
        XCTAssertGreaterThan(res.count, 0)
        for (l, w) in res {
            XCTAssertLessThanOrEqual(w.dyPart, 0.003, "\(l) a small part on the loop drifts \(w.dyPart) m from its rest height: \(w.dyPartWhere)")
            XCTAssertLessThanOrEqual(w.dy, 0.003, "\(l) loop height drifts \(w.dy) m from its rest height in the body frame: \(w.dyWhere)")
            XCTAssertLessThanOrEqual(w.inside, 0.012, "\(l) loop crosses the skin by \(w.inside): \(w.insideWhere)")
            XCTAssertLessThanOrEqual(w.insideLimb, 0.14, "\(l) loop is \(w.insideLimb) inside a limb: \(w.insideLimbWhere)")
            XCTAssertLessThanOrEqual(w.stretch, 1.6, "\(l) loop breaks (spacing \(w.stretch)x): \(w.stretchWhere)")
        }
    }

    /// No popping: band vertices, sampled every 0.1 s (6 sim steps) through a walk and the jumping-jacks, never move more than 1 cm per sample IN THE BODY FRAME (the body's own
    /// motion is taken out), near the arms or anywhere else. Prints the worst numbers.
    func testBandsDoNotPop() throws {
        WearLevel.record = true; defer { WearLevel.record = false }
        var report = ""
        var walkNear: Float = 0, walkAll: Float = 0
        for look in [WearLook.bandanaCoral, .scarfCosy, .pearls, .sweatband] {
            let loopsL = Self.loops(look)
            guard !loopsL.isEmpty else { continue }
            for m in motions() where ["walk", "jacks", "hop"].contains(m.name) {
                let lab = makeLab(0); let r = lab.rigs[0]
                let s = WornSet(); s.body = WearBody.shared; s.soundOn = false; Self.keep.append(s)
                func tick() { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); s.tick(id: 0, brain: r.brain, sim: r.sim, outfit: [look.slot: look], role: .none, hideAll: false, dt: 1.0 / 60) }
                for _ in 0..<40 { tick() }
                m.start(lab)
                var prev6: [SIMD3<Float>]? = nil, prevNear6: [Bool] = [], prev1: [SIMD3<Float>]? = nil, prevNear1: [Bool] = []
                var all6: Float = 0, near6: Float = 0, all1: Float = 0, near1: Float = 0, far1: Float = 0, bul1: Float = 0, bul6: Float = 0
                var prevB1: [Float] = [], prevB6: [Float] = []
                for step in 0..<Int(m.seconds * 60) {
                    tick()
                    s.syncCarry(0, sim: r.sim)
                    let sk = skin(lab)
                    let f = sk.withUnsafeBufferPointer { q in s.frame(theme: RoomTheme(), time: 0.4) { _ in q.baseAddress } }
                    guard let c = s.slot(0)?.carry else { continue }
                    let sxz = 1 / c.squash.squareRoot()
                    let Minv = simd_float3x3(diagonal: SIMD3(1 / sxz, 1 / c.squash, 1 / sxz)) * simd_float3x3(c.rotation).transpose
                    var cur: [SIMD3<Float>] = [], near: [Bool] = []
                    for lp in loopsL { for vi in lp.verts {
                        let v = f.opaque.vertices[vi]
                        cur.append(Minv * (SIMD3(v.pos.x, v.pos.y, v.pos.z) - c.centroid) + c.restCentroid)
                        near.append(vi < WearLevel.recRaw.count && WearLevel.recRaw[vi] > 0.0005)
                    } }
                    if let p0 = prev1, p0.count == cur.count { for i in cur.indices { let d = simd_distance(cur[i], p0[i]); all1 = max(all1, d); if near[i] || prevNear1[i] { near1 = max(near1, d) } } }
                    if let p0 = prev1, p0.count == cur.count { for i in cur.indices where !near[i] && !prevNear1[i] { far1 = max(far1, simd_distance(cur[i], p0[i])) } }
                    var bnow: [Float] = []
                    for lp in loopsL { for vi in lp.verts { bnow.append(vi < WearLevel.recBulge.count ? WearLevel.recBulge[vi] : 0) } }
                    if prevB1.count == bnow.count { for i in bnow.indices { bul1 = max(bul1, abs(bnow[i] - prevB1[i])) } }
                    prevB1 = bnow
                    if step % 6 == 0 { if prevB6.count == bnow.count { for i in bnow.indices { bul6 = max(bul6, abs(bnow[i] - prevB6[i])) } }; prevB6 = bnow }
                    prev1 = cur; prevNear1 = near
                    if step % 6 == 0 {
                        if let p0 = prev6, p0.count == cur.count { for i in cur.indices { let d = simd_distance(cur[i], p0[i]); all6 = max(all6, d); if near[i] || prevNear6[i] { near6 = max(near6, d) } } }
                        prev6 = cur; prevNear6 = near
                    }
                }
                report += String(format: "%@ %@: body-frame move per 0.1 s: all %.4f near-arm %.4f | per frame (1/60 s): all %.4f near-arm %.4f, band vertices NOT near an arm %.4f | the arm-clearance bulge alone changes by at most %.4f per frame, %.4f per 0.1 s\n", look.rawValue, m.name, all6, near6, all1, near1, far1, bul1, bul6)
                if m.name == "walk" { walkNear = max(walkNear, bul1); walkAll = max(walkAll, bul6) }
            }
        }
        print("BANDPOP\n" + report)
        if let d = ProcessInfo.processInfo.environment["BAND_DIR"] { try? report.write(toFile: d + "/pop.txt", atomically: true, encoding: .utf8) }
        XCTAssertLessThanOrEqual(walkNear, 0.01, "the arm-clearance bulge changes by \(walkNear) m in one frame of a walk")
        XCTAssertLessThanOrEqual(walkAll, 0.01, "the arm-clearance bulge changes by \(walkAll) m in 0.1 s of a walk")
    }

    /// Chains stay in one piece (the "split chain" report): neighbouring links / gems / pearls stay within 1.5x of their drawn rest spacing in every frame, and a run of links near an arm
    /// takes ONE mode (a link never goes pass-behind while its neighbour bulges). WEARBAND_LEVEL=off runs the same check on the old code.
    func testChainsStayConnected() throws {
        WearLevel.record = true; defer { WearLevel.record = false }
        var report = ""
        var worst: Float = 0, worstMode = 0
        for (look, prefix) in [(WearLook.chainGold, "link"), (.diamondJ, "gem"), (.pearls, "pearl")] {
            guard let a = WearMeshes.art(look) else { continue }
            var parts: [(first: Int, count: Int)] = []
            var base = 0
            for part in a.parts { if part.name.hasPrefix(prefix) { parts.append((base, part.positions.count)) }; base += part.positions.count }
            for m in motions() where ["walk", "run", "hop", "jacks", "lean", "squish"].contains(m.name) {
                for id in [0, 1] {
                    let lab = makeLab(id); let r = lab.rigs[0]
                    let s = WornSet(); s.body = WearBody.shared; s.soundOn = false; Self.keep.append(s)
                    func tick() { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); s.tick(id: 0, brain: r.brain, sim: r.sim, outfit: [look.slot: look], role: .none, hideAll: false, dt: 1.0 / 60) }
                    for _ in 0..<70 { tick() }
                    func centres() -> [SIMD3<Float>]? {
                        s.syncCarry(0, sim: r.sim)
                        let sk = skin(lab)
                        let f = sk.withUnsafeBufferPointer { q in s.frame(theme: RoomTheme(), time: 0.4) { _ in q.baseAddress } }
                        guard let last = parts.last, f.opaque.vertices.count >= last.first + last.count else { return nil }
                        return parts.map { p in var c = SIMD3<Float>.zero; for v in p.first..<(p.first + p.count) { let q = f.opaque.vertices[v]; c += SIMD3(q.pos.x, q.pos.y, q.pos.z) }; return c / Float(p.count) }
                    }
                    guard let rest = centres() else { continue }
                    m.start(lab)
                    var wm: Float = 0, modeBad = 0
                    for step in 0..<Int(m.seconds * 60) {
                        tick()
                        guard step % 3 == 0, let c = centres() else { continue }
                        for k in 0..<(c.count - 1) {
                            let e0 = simd_distance(rest[k], rest[k + 1])
                            guard e0 > 0.005 else { continue }
                            wm = max(wm, simd_distance(c[k], c[k + 1]) / e0)
                            if WearLevel.record, parts[k].first < WearLevel.recBulge.count, parts[k + 1].first < WearLevel.recBulge.count {
                                let b0 = WearLevel.recBulge[parts[k].first], b1 = WearLevel.recBulge[parts[k + 1].first]
                                let r0 = WearLevel.recRaw[parts[k].first], r1 = WearLevel.recRaw[parts[k + 1].first]
                                if (b0 < 0.001 && r0 >= WearLevel.bulgeNone && b1 > 0.01) || (b1 < 0.001 && r1 >= WearLevel.bulgeNone && b0 > 0.01) { modeBad += 1 }
                            }
                        }
                    }
                    worst = max(worst, wm); worstMode += modeBad
                    report += String(format: "%@ %@ %@: worst neighbour spacing %.2fx rest, pass-behind/bulge mixed pairs %d\n", look.rawValue, ["Bob", "Pip"][id], m.name, wm, modeBad)
                }
            }
        }
        print("BANDCHAIN\n" + report)
        if let d = ProcessInfo.processInfo.environment["BAND_DIR"] { try? report.write(toFile: d + "/chain_\(ProcessInfo.processInfo.environment["BAND_TAG"] ?? "run").txt", atomically: true, encoding: .utf8) }
        XCTAssertLessThanOrEqual(worst, 1.5, "a neighbouring pair of chain links is \(worst)x its rest spacing apart")
        XCTAssertEqual(worstMode, 0, "a link goes pass-behind while its neighbour bulges")
    }
}
