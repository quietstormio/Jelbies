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
    static let maxNormalBreakP90: Float = 8         // degrees: the shading-normal break across the crossing, 90th percentile (the old crease requirement of 25 degrees is gone: the join must not be a crease)
    static let maxShadowStep: Float = 0.03          // the baked-shadow (mat) step across the crossing

    struct Line { var saw: Float; var p10: Float; var points: Int; var breaks: [Float] = []; var matStep: Float = 0; var steps: [Float] = [] }


    /// Closest point on triangle (a, b, c) to p, with its barycentric weights (Ericson, Real-Time Collision Detection).
    static func closest(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return (a, SIMD3(1, 0, 0)) }
        let bp = p - b, d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return (b, SIMD3(0, 1, 0)) }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 { let v = d1 / (d1 - d3); return (a + ab * v, SIMD3(1 - v, v, 0)) }
        let cp = p - c, d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return (c, SIMD3(0, 0, 1)) }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 { let w = d2 / (d2 - d6); return (a + ac * w, SIMD3(1 - w, 0, w)) }
        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 { let w = (d4 - d3) / ((d4 - d3) + (d5 - d6)); return (b + (c - b) * w, SIMD3(0, 1 - w, w)) }
        let den = 1 / (va + vb + vc), v = vb * den, w = vc * den
        return (a + ab * v + ac * w, SIMD3(1 - v - w, v, w))
    }

    /// The shadow value each vertex is drawn with this frame: baked, or moved by the join writes of the frame just rendered (set by `shading`; empty elsewhere).
    static var joinMat: [Int32: Float] = [:]
    static var crossE: [Float] = []          // (diagnostic) the crossing points' height above the fitted egg, m
    static func effMat(_ v: Int) -> Float { joinMat[Int32(v)] ?? MotionRig.renderMesh.mat[v] }

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
        var breaksAll: [Float] = [], matStepMax: Float = 0, stepsAll: [Float] = []
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
                // shading-normal break: the skin edge's interpolated vertex normal against the piece triangle's interpolated vertex normal at the crossing point
                let ea = P(i0 ? v1 : v0), eb = P(i0 ? v0 : v1), tp = simd_length(eb - ea) > 1e-7 ? min(1, max(0, simd_dot(x - ea, eb - ea) / simd_length_squared(eb - ea))) : 0
                let ns = simd_normalize(N(i0 ? v1 : v0) * (1 - tp) + N(i0 ? v0 : v1) * tp)
                var bestTri = 0, bestQ = Float.infinity, bestW = SIMD3<Float>(1, 0, 0)
                var q = 0
                while q < bt.count {
                    let (cp, w) = Self.closest(x, P(Int(bt[q])), P(Int(bt[q + 1])), P(Int(bt[q + 2])))
                    let dq = simd_distance_squared(cp, x)
                    if dq < bestQ { bestQ = dq; bestTri = q; bestW = w }
                    q += 3
                }
                let nb = simd_normalize(N(Int(bt[bestTri])) * bestW.x + N(Int(bt[bestTri + 1])) * bestW.y + N(Int(bt[bestTri + 2])) * bestW.z)
                let brk = acosf(min(1, max(-1, simd_dot(ns, nb)))) * 180 / .pi
                let sm = Self.effMat(i0 ? v1 : v0) * (1 - tp) + Self.effMat(i0 ? v0 : v1) * tp
                let bm = Self.effMat(Int(bt[bestTri])) * bestW.x + Self.effMat(Int(bt[bestTri + 1])) * bestW.y + Self.effMat(Int(bt[bestTri + 2])) * bestW.z
                breaksAll.append(brk); matStepMax = max(matStepMax, abs(sm - bm)); stepsAll.append(abs(sm - bm))
                if let pose = r.skinner.joinPose { Self.crossE.append(-Skinner.fittedDepth(x, pose).0) }
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
        return Line(saw: saw, p10: angs.isEmpty ? 90 : angs[angs.count / 10], points: angs.count, breaks: breaksAll, matStep: matStepMax, steps: stepsAll)
    }

    func run(_ name: String, char: Int, start: (MotionRig) -> Void) -> (saw: Float, p10: Float, frames: Int) {
        let rm = MotionRig.renderMesh
        Self.joinMat = [:]
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

    func testJoinLineIsCleanWhilePiecesAreOut() {
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
            }
        }
        XCTAssertGreaterThanOrEqual(measured, 4, "too few moves put the foot pieces out")
    }

    /// The measure itself: the old tangent collar must fail it (else the test could not see the defect it guards).
    func testOldTangentCollarIsCaught() {
        Skinner.collarCrossing = false
        defer { Skinner.collarCrossing = true }
        let m = run("look (old collar)", char: 0) { r in r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim) }
        XCTAssertGreaterThan(m.frames, 0)
        XCTAssertTrue(m.saw > Self.maxSawtooth, "the old collar's sawtooth join was not detected (\(m.saw * 100) cm)")
    }
    // MARK: shading continuity (2026-11-11, the user's third complaint: "the legs are separate ... not ready for production")
    /// The moves that put the pieces out, per character, over EVERY frame the pieces are out (transitions and landings included, not only planted frames).
    static let moves: [(String, (MotionRig) -> Void)] = [
        ("look", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim) }),
        ("sway", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.sway, r.sim) }),
        ("hop", { r in r.brain.startHopPlay(sim: r.sim) }),
        ("flapHop", { r in r.brain.idleForced = true; _ = r.brain.idleStart(.flapHop, r.sim) }),
        ("turn", { r in r.brain.startTurn(to: r.brain.yaw + 2.0, sim: r.sim) }),
    ]

    /// (90th percentile normal break in degrees, largest shadow step, crossings measured, frames) over a move of a character.
    func shading(_ name: String, char: Int, start: (MotionRig) -> Void) -> (p90: Float, step: Float, n: Int, frames: Int) {
        let rm = MotionRig.renderMesh
        let r = MotionRig(game: true, settle: 0.5)
        r.skinner.autoBlink = false
        r.brain.seed = 11
        r.brain.feature = JellyRoster.feature(char)
        r.skinner.configureTail(rm); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        start(r)
        var breaks: [Float] = [], steps: [Float] = [], frames = 0
        for frame in 0..<(60 * 3) {
            r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            guard frame % 5 == 0, r.skinner.beansActive, r.skinner.beanBlend > 0.5 else { continue }
            r.render()
            frames += 1
            Self.joinMat = [:]
            if let w = r.skinner.takeJoinWrites() { for (k, v) in w.v.enumerated() { let b = rm.mat[Int(v)]; Self.joinMat[v] = b + (w.matT[k] - b) * w.matW[k] } }
            for s in 0..<2 { let l = Self.line(r, s); if l.points >= 10 { breaks += l.breaks; steps += l.steps } }
        }
        breaks.sort()
        Self.crossE.sort(); if !Self.crossE.isEmpty { print(String(format: "[footjoinshade] crossing height above the egg: p10 %.3f p50 %.3f p90 %.3f m", Self.crossE[Self.crossE.count / 10], Self.crossE[Self.crossE.count / 2], Self.crossE[Self.crossE.count * 9 / 10])) }; Self.crossE = []
        let p90 = breaks.isEmpty ? 0 : breaks[min(breaks.count - 1, breaks.count * 9 / 10)]
        steps.sort(); let step = steps.isEmpty ? 0 : steps[min(steps.count - 1, steps.count * 9 / 10)], stepMax = steps.last ?? 0
        print(String(format: "[footjoinshade] %@ char %d (blend %@): frames %d crossings %d | normal break p90 %.1f deg | shadow step p90 %.3f max %.3f", name, char, Skinner.joinBlend ? "on" : "off", frames, breaks.count, p90, step, stepMax))
        return (p90, step, breaks.count, frames)
    }

    func testShadingIsContinuousAcrossTheJoinWhileLegsAreOut() {
        var measured = 0
        for (name, start) in Self.moves {
            for char in 0..<7 {
                let m = shading(name, char: char, start: start)
                guard m.frames > 0, m.n >= 10 else { print("[footjoinshade] SKIPPED \(name) char \(char): frames \(m.frames) crossings \(m.n)"); continue }
                measured += 1
                XCTAssertLessThanOrEqual(m.p90, Self.maxNormalBreakP90, "\(name) char \(char): the shading normal breaks \(m.p90) deg across the skin / foot crossing (p90)")
                XCTAssertLessThanOrEqual(m.step, Self.maxShadowStep, "\(name) char \(char): the baked shadow steps \(m.step) (p90) across the crossing")
            }
        }
        XCTAssertGreaterThanOrEqual(measured, 20, "too few (move, character) pairs put the pieces out")
    }

    /// The measure itself: with the blend off the normal break must be caught (else the test could not see the defect it guards).
    func testNormalBreakIsCaughtWithTheBlendOff() {
        Skinner.joinBlend = false
        defer { Skinner.joinBlend = true }
        let m = shading("look (blend off)", char: 0) { r in r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim) }
        XCTAssertGreaterThan(m.n, 10)
        XCTAssertGreaterThan(m.p90, Self.maxNormalBreakP90, "the unblended join's normal break was not detected (\(m.p90) deg)")
    }
}
