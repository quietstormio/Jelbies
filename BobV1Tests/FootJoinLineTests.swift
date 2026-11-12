//
//  FootJoinLineTests.swift
//  2026-11-10 (the user, on the Jelly Spring close-up: "his feet look like separate pieces of his body"). While the foot pieces are out (any foot motion: look, sway, hop,
//  the walk ...) the line where the body skin meets a piece must be a clean curve, not a sawtooth. The old collar fillet stood vertical at the piece's outline, tangent to its
//  wall, so the crossing of the two meshes wandered with the 2 cm skin triangles: teeth of 3-5 cm at a 12-15 degree crossing.
//
//  Measured on the drawn skin (MotionRig, the game brain), per foot, per sampled frame with both pieces planted:
//   - the crossing line: every body-skin edge near the piece with one end inside the piece and one outside is bisected to the crossing point, expressed in the piece's polar
//     frame (axis sole - crown); per 6 degree bin the outermost crossing is the visible join;
//   - sawtooth = the largest tooth: a bin whose crossing height is a peak or pit against both neighbours, by the smaller of the two steps;
//   - crossing angle = the angle between the skin face and the piece surface at the crossing (10th percentile): near 0 = the two surfaces are tangent (an unstable, ragged line).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FootJoinLineTests: XCTestCase {
    static let maxSawtooth: Float = 0.008          // m
    static let minCrossingAngle: Float = 25         // degrees, 10th percentile

    struct Line { var saw: Float; var p10: Float; var points: Int }

    static func line(_ r: MotionRig, _ s: Int) -> Line {
        let rm = MotionRig.renderMesh
        let d = r.dyn
        @inline(__always) func P(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]) }
        @inline(__always) func N(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v + 3], d[6 * v + 4], d[6 * v + 5]) }
        let f = Int(r.bean[s][0]), nB = FootBean.vertexCount, A = FootBean.around
        let a = simd_normalize(P(f) - P(f + nB - 1))
        let tmp: SIMD3<Float> = abs(a.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let e1 = simd_normalize(simd_cross(a, tmp)), e2 = simd_cross(a, e1)
        var c = SIMD3<Float>.zero
        for j in 0..<A { c += P(f + 1 + A * Skinner.collarRing + j) }
        c /= Float(A)
        let bt = FootBean.triangles(firstVertex: f)
        let ray = simd_normalize(SIMD3<Float>(0.31, 0.17, 0.93))
        func inside(_ p: SIMD3<Float>) -> Bool {
            var hits = 0, t = 0
            while t < bt.count {
                let p0 = P(Int(bt[t])), q1 = P(Int(bt[t + 1]) ) - p0, q2 = P(Int(bt[t + 2])) - p0; t += 3
                let pv = simd_cross(ray, q2), det = simd_dot(q1, pv)
                if abs(det) < 1e-12 { continue }
                let inv = 1 / det, tv = p - p0, u = simd_dot(tv, pv) * inv
                if u < 0 || u > 1 { continue }
                let qv = simd_cross(tv, q1), v = simd_dot(ray, qv) * inv
                if v < 0 || u + v > 1 { continue }
                if simd_dot(q2, qv) * inv > 0 { hits += 1 }
            }
            return hits % 2 == 1
        }
        // the embedded foot's own cup is retracted inside the piece: not part of the visible skin
        var cup = Set<Int32>()
        for (k, v) in r.skinner.retractVertices.enumerated() where r.skinner.retractSide[k] >= 0 && r.skinner.retractWeight[k] > 0.5 { cup.insert(v) }
        let bodyEnd = rm.armCapsule?.firstVertex[0] ?? rm.vertexCount
        var near = [Bool](repeating: false, count: bodyEnd), ins = [Int8](repeating: -1, count: bodyEnd)
        for v in 0..<bodyEnd where !cup.contains(Int32(v)) && simd_distance(P(v), c) < 0.32 { near[v] = true }
        func isIn(_ v: Int) -> Bool { if ins[v] < 0 { ins[v] = inside(P(v)) ? 1 : 0 }; return ins[v] == 1 }
        let bins = 60
        var binH = [Float](repeating: -.infinity, count: bins), binA = [Float](repeating: 0, count: bins)
        var seen = Set<Int>(), t = 0
        let limit = rm.armCapsule?.indexFirst ?? rm.index.count
        while t < limit {
            let tri = [Int(rm.index[t]), Int(rm.index[t + 1]), Int(rm.index[t + 2])]; t += 3
            guard tri.allSatisfy({ $0 < bodyEnd && near[$0] }) else { continue }
            let fn = simd_normalize(simd_cross(P(tri[1]) - P(tri[0]), P(tri[2]) - P(tri[0])))
            for k in 0..<3 {
                let v0 = tri[k], v1 = tri[(k + 1) % 3]
                let key = min(v0, v1) * 1_000_000 + max(v0, v1)
                guard !seen.contains(key) else { continue }
                let i0 = isIn(v0), i1 = isIn(v1)
                guard i0 != i1 else { continue }
                seen.insert(key)
                var lo = P(i0 ? v1 : v0), hi = P(i0 ? v0 : v1)
                for _ in 0..<10 { let m = (lo + hi) / 2; if inside(m) { hi = m } else { lo = m } }
                let x = (lo + hi) / 2, u = x - c
                var bestD = Float.infinity, bn = SIMD3<Float>(0, 1, 0)
                for i in 0..<nB { let dd = simd_distance_squared(P(f + i), x); if dd < bestD { bestD = dd; bn = N(f + i) } }
                let ang = acosf(min(1, abs(simd_dot(simd_normalize(bn), fn)))) * 180 / .pi
                let th = atan2f(simd_dot(u, e2), simd_dot(u, e1)), h = simd_dot(u, a)
                let b = min(bins - 1, Int((th + .pi) / (2 * .pi) * Float(bins)))
                if h > binH[b] { binH[b] = h; binA[b] = ang }
            }
        }
        var saw: Float = 0, angs: [Float] = []
        for b in 0..<bins where binH[b].isFinite {
            angs.append(binA[b])
            // a tooth: the bin's crossing height is a local peak or pit against BOTH neighbours (a steep but monotone run of the line, e.g. where the underside turns into the
            // side wall next to the foot, is not a tooth); its size is the smaller of the two steps
            let l = binH[(b - 1 + bins) % bins], r = binH[(b + 1) % bins]
            guard l.isFinite, r.isFinite, (binH[b] - l) * (binH[b] - r) > 0 else { continue }
            saw = max(saw, min(abs(binH[b] - l), abs(binH[b] - r)))
        }
        angs.sort()
        return Line(saw: saw, p10: angs.isEmpty ? 90 : angs[angs.count / 10], points: angs.count)
    }

    func run(_ name: String, char: Int, start: (MotionRig) -> Void) -> (saw: Float, p10: Float, frames: Int) {
        let rm = MotionRig.renderMesh
        let r = MotionRig(game: true, settle: 0.5)
        r.skinner.autoBlink = false
        r.brain.seed = 11          // (deterministic: the look's direction and the idles' choices)
        r.brain.feature = JellyRoster.feature(char)
        r.skinner.configureTail(rm); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        start(r)
        var saw: Float = 0, p10: Float = 180, frames = 0
        for frame in 0..<(60 * 4) {
            r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            guard frame % 6 == 0, r.skinner.beansActive, r.skinner.beanBlend > 0.95 else { continue }
            guard (0..<2).allSatisfy({ k in (r.skinner.beanPos[k].map(\.y).min() ?? 0) - r.sim.floorY < 0.01 }) else { continue }
            r.render()
            frames += 1
            for s in 0..<2 { let l = Self.line(r, s); if l.points >= 10 { saw = max(saw, l.saw); p10 = min(p10, l.p10) } }
        }
        print(String(format: "[footjoinline] %@ char %d: planted piece frames %d | sawtooth %.2f cm | crossing angle p10 %.1f deg", name, char, frames, saw * 100, p10))
        return (saw, p10, frames)
    }

    // MARK: welded legs (LegWeld.swift, 2026-11-11): no crease at all

    /// The weld's continuity measure, at 90th percentile, across both seams (cup top ring | band, band | egg loop): the angle between the two faces on either side of every seam edge.
    /// (Vertex normals are shared there by construction, so comparing them would be 0 deg vacuously; the face angle is what the shading interpolates across.)
    static let maxSeamBreakP90: Float = 8

    struct Seams { var p90: Float; var max: Float; var folds: Int; var edges: Int }

    /// Seam edges and their two faces, from the index buffer (built once).
    struct SeamTopo { var edges: [(Int, Int, Int, Int)] = []; var band: [Int] = [] }          // (v0, v1, face a, face b) ; face = first index of the triangle
    static var topoCache: SeamTopo?
    static func topo() -> SeamTopo {
        if let t = topoCache { return t }
        let rm = MotionRig.renderMesh
        guard let cap = rm.armCapsule, let w = cap.weld else { return SeamTopo() }
        var faces: [UInt64: [Int]] = [:]
        func key(_ a: Int, _ b: Int) -> UInt64 { UInt64(min(a, b)) << 32 | UInt64(max(a, b)) }
        var t = 0
        let end = rm.body.first + rm.body.count
        while t < end { for k in 0..<3 { faces[key(Int(rm.index[t + k]), Int(rm.index[t + (k + 1) % 3])), default: []].append(t) }; t += 3 }
        var out = SeamTopo()
        let A = FootBean.around
        for sd in w.sides {
            var pairs: [(Int, Int)] = []
            for j in 0..<A { pairs.append((sd.beanFirst + 1 + A * w.ring + j, sd.beanFirst + 1 + A * w.ring + (j + 1) % A)) }
            for i in 0..<sd.loop.count { pairs.append((Int(sd.loop[i]), Int(sd.loop[(i + 1) % sd.loop.count]))) }
            for (a, b) in pairs { if let f = faces[key(a, b)], f.count == 2 { out.edges.append((a, b, f[0], f[1])) } }
        }
        out.band = Array(stride(from: cap.indexFirst, to: cap.indexFirst + w.bandIndexCount, by: 3))
        topoCache = out
        return out
    }

    static func seams(_ r: MotionRig) -> Seams {
        let rm = MotionRig.renderMesh, d = r.dyn, tp = topo()
        @inline(__always) func P(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]) }
        @inline(__always) func N(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v + 3], d[6 * v + 4], d[6 * v + 5]) }
        func fn(_ t: Int) -> SIMD3<Float> {
            let a = Int(rm.index[t]), b = Int(rm.index[t + 1]), c = Int(rm.index[t + 2])
            let n = simd_cross(P(b) - P(a), P(c) - P(a)); let l = simd_length(n)
            return l > 1e-12 ? n / l : SIMD3(0, 0, 0)
        }
        var angs: [Float] = []
        for (_, _, fa, fb) in tp.edges { angs.append(acosf(max(-1, min(1, simd_dot(fn(fa), fn(fb))))) * 180 / .pi) }
        var folds = 0
        for t in tp.band {
            let a = Int(rm.index[t]), b = Int(rm.index[t + 1]), c = Int(rm.index[t + 2])
            if simd_dot(fn(t), N(a) + N(b) + N(c)) < 0 { folds += 1 }
        }
        angs.sort()
        return Seams(p90: angs.isEmpty ? 180 : angs[angs.count * 9 / 10], max: angs.last ?? 180, folds: folds, edges: angs.count)
    }

    static let weldMoves: [(String, (MotionRig) -> Void)] = [
        ("rest", { _ in }),
        ("look", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim) }),
        ("sway", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.sway, r.sim) }),
        ("stretch", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.stretch, r.sim) }),
        ("hop", { r in r.brain.startHopPlay(sim: r.sim) }),
        ("walk", { r in r.brain.request(.goTo(SIMD2(1.6, 0.4))) }),
        ("turn", { r in r.brain.startTurn(to: r.poseYaw + 2.4, sim: r.sim) }),
        ("sit", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.sit, r.sim) }),
        ("flapHop", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.flapHop, r.sim) }),
    ]

    /// Every frame (transition, airborne and landing frames too), every sampled move.
    func weldRun(_ name: String, char: Int, seconds: Float = 4, start: (MotionRig) -> Void) -> (p90: Float, max: Float, folds: Int, frames: Int, out: Int) {
        let rm = MotionRig.renderMesh
        let r = MotionRig(game: true, settle: 0.5)
        r.skinner.autoBlink = false
        r.brain.seed = 11
        r.brain.feature = JellyRoster.feature(char)
        r.skinner.configureTail(rm); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        start(r)
        var p90: Float = 0, mx: Float = 0, folds = 0, frames = 0, out = 0
        for frame in 0..<Int(60 * seconds) {
            r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            guard frame % 3 == 0 else { continue }
            r.render()
            frames += 1
            if r.skinner.beansActive { out += 1 }
            let m = Self.seams(r)
            p90 = max(p90, m.p90); mx = max(mx, m.max); folds = max(folds, m.folds)
        }
        print(String(format: "[legweld] %@ char %d: frames %d (legs out %d) | seam break p90 %.1f deg, max %.1f deg | folded band triangles %d", name, char, frames, out, p90, mx, folds))
        return (p90, mx, folds, frames, out)
    }

    func testWeldSeamsAreContinuous() throws {
        guard MotionRig.renderMesh.armCapsule?.weld != nil else { throw XCTSkip("legs not welded in this process (-LegsWeld 0)") }
        var worst: Float = 0
        for (name, start) in Self.weldMoves {
            for char in [0, 4] {
                let m = weldRun(name, char: char, start: start)
                worst = max(worst, m.p90)
                XCTAssertLessThanOrEqual(m.p90, Self.maxSeamBreakP90, "\(name) char \(char): the welded leg's seams break the surface (p90 \(m.p90) deg)")
                XCTAssertEqual(m.folds, 0, "\(name) char \(char): the weld band folds over")
            }
        }
        print(String(format: "[legweld] worst p90 %.1f deg", worst))
    }

    /// The measure itself: a band with no tangent matching (straight chords) must fail it.
    func testWeldSeamMeasureCatchesACrease() throws {
        guard MotionRig.renderMesh.armCapsule?.weld != nil else { throw XCTSkip("legs not welded in this process (-LegsWeld 0)") }
        let k0 = Skinner.weldK0, k1 = Skinner.weldK1
        Skinner.weldK0 = 0; Skinner.weldK1 = 0
        defer { Skinner.weldK0 = k0; Skinner.weldK1 = k1 }
        let m = weldRun("rest (straight band)", char: 0, seconds: 1) { _ in }
        XCTAssertGreaterThan(m.p90, Self.maxSeamBreakP90, "a straight (creased) band was not detected")
    }

    /// Diagnostic: the drawn body (egg + band + limbs) at rest and in a few walk frames as OBJ files (env LEGWELD_OBJ_DIR), for inspection off the device.
    func testWeldDumpObj() throws {
        guard let dir = ProcessInfo.processInfo.environment["LEGWELD_OBJ_DIR"] ?? Optional("/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/49d32754-b08a-4bfd-999b-3f9f0cada45f/scratchpad/legs/weld/obj") else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let rm = MotionRig.renderMesh
        let r = MotionRig(game: true, settle: 0.5)
        r.skinner.autoBlink = false
        r.brain.seed = 11
        do {          // Lemon Drop (the tail's swell moves the lower back): its rest dump, and where the band folds
            let y = MotionRig(game: true, settle: 0.5)
            y.brain.feature = JellyRoster.feature(1)
            y.skinner.configureTail(rm); y.skinner.tailOn = true; y.brain.skinnerRef = y.skinner
            y.run(0.5); y.render()
            var o = ""
            for v in 0..<rm.vertexCount { o += String(format: "v %.5f %.5f %.5f\n", y.dyn[6 * v], y.dyn[6 * v + 1], y.dyn[6 * v + 2]) }
            var t = rm.body.first
            while t < rm.body.first + rm.body.count { o += "f \(rm.index[t] + 1) \(rm.index[t + 1] + 1) \(rm.index[t + 2] + 1)\n"; t += 3 }
            try? o.write(toFile: dir + "/yellow_rest.obj", atomically: true, encoding: .utf8)
            let m = Self.seams(y)
            print(String(format: "[legweld] dump yellow rest: seam p90 %.1f max %.1f folds %d", m.p90, m.max, m.folds))
        }
        func dump(_ name: String) {
            r.render()
            var o = ""
            for v in 0..<rm.vertexCount { o += String(format: "v %.5f %.5f %.5f\n", r.dyn[6 * v], r.dyn[6 * v + 1], r.dyn[6 * v + 2]) }
            var t = rm.body.first
            while t < rm.body.first + rm.body.count { o += "f \(rm.index[t] + 1) \(rm.index[t + 1] + 1) \(rm.index[t + 2] + 1)\n"; t += 3 }
            try? o.write(toFile: dir + "/\(name).obj", atomically: true, encoding: .utf8)
            let m = Self.seams(r)
            print(String(format: "[legweld] dump %@: seam p90 %.1f max %.1f folds %d edges %d", name, m.p90, m.max, m.folds, m.edges))
        }
        // closure: every edge of the drawn body (egg, band, limbs, tail, ears) is shared by exactly two triangles
        var ec: [UInt64: Int] = [:]
        var t = rm.body.first
        while t < rm.body.first + rm.body.count {
            for k in 0..<3 { let a = UInt64(rm.index[t + k]), b = UInt64(rm.index[t + (k + 1) % 3]); ec[min(a, b) << 32 | max(a, b), default: 0] += 1 }
            t += 3
        }
        let open = ec.filter { $0.value != 2 }
        print("[legweld] open edges \(open.count): \(open.prefix(12).map { "(\($0.key >> 32),\($0.key & 0xffffffff))x\($0.value)" })")
        dump("rest")
        r.brain.request(.goTo(SIMD2(1.6, 0.4)))
        for k in 0..<4 { r.run(0.5); dump("walk\(k)") }
        // skinner cost (this process's mesh: welded, or -LegsWeld 0 / defaults LegsWeld 0 for the old one), legs out mid-walk
        do {
            let n = 300
            let t0 = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<n { r.render() }
            let us = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1000 / Double(n)
            print(String(format: "[legweld] skinner cost %.1f us per update (welded %@, legs out %@)", us, rm.armCapsule?.weld != nil ? "yes" : "no", r.skinner.beansActive ? "yes" : "no"))
        }
        if let w = rm.armCapsule?.weld { print("[legweld] band first \(w.sides.map(\.bandFirst)) ghost \(w.sides.map(\.ghostFirst)) bean \(w.sides.map(\.beanFirst)) bandIdx \(w.bandIndexCount) capIdx \(rm.armCapsule!.indexFirst)") }
    }

    /// Where the weld sits, and the pieces' poses are the brain's (the band changes no foot vertex below the seam).
    func testWeldPlanIsSimple() throws {
        let rm = MotionRig.renderMesh
        guard let w = rm.armCapsule?.weld else { throw XCTSkip("legs not welded in this process") }
        for (k, sd) in w.sides.enumerated() {
            print("[legweld] side \(k): loop \(sd.loop.count) vertices, hidden \(sd.hidden.count), ring \(w.ring), rows \(w.rows), band indices \(w.bandIndexCount)")
            XCTAssertGreaterThan(sd.loop.count, 16)
            XCTAssertEqual(Set(sd.loop).count, sd.loop.count)
        }
        XCTAssertTrue(Set(w.sides[0].loop + w.sides[0].hidden).isDisjoint(with: w.sides[1].loop + w.sides[1].hidden))
    }

    func testJoinLineIsCleanWhilePiecesAreOut() throws {
        if MotionRig.renderMesh.armCapsule?.weld != nil { throw XCTSkip("welded legs: no crossing line (testWeldSeamsAreContinuous)") }
        let moves: [(String, (MotionRig) -> Void)] = [
            ("look", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim) }),
            ("sway", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.sway, r.sim) }),
            ("stretch", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.stretch, r.sim) }),
            ("hop", { r in r.brain.startHopPlay(sim: r.sim) }),
        ]
        var measured = 0
        for (name, start) in moves {
            for char in [0, 4] {          // Bob and Teddy
                let m = run(name, char: char, start: start)
                guard m.frames > 0 else { continue }
                measured += 1
                XCTAssertLessThanOrEqual(m.saw, Self.maxSawtooth, "\(name) char \(char): the body / foot join is a sawtooth (\(m.saw * 100) cm)")
                XCTAssertGreaterThanOrEqual(m.p10, Self.minCrossingAngle, "\(name) char \(char): the skin meets the foot piece nearly tangentially (\(m.p10) deg): a ragged join")
            }
        }
        XCTAssertGreaterThanOrEqual(measured, 4, "too few moves put the foot pieces out")
    }

    /// The measure itself: the old tangent collar must fail it (else the test could not see the defect it guards).
    func testOldTangentCollarIsCaught() throws {
        if MotionRig.renderMesh.armCapsule?.weld != nil { throw XCTSkip("welded legs: no collar") }
        Skinner.collarCrossing = false
        defer { Skinner.collarCrossing = true }
        let m = run("look (old collar)", char: 0) { r in r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim) }
        XCTAssertGreaterThan(m.frames, 0)
        XCTAssertTrue(m.saw > Self.maxSawtooth || m.p10 < Self.minCrossingAngle, "the old collar's sawtooth join was not detected (\(m.saw * 100) cm, \(m.p10) deg)")
    }
}
