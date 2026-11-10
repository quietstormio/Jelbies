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
                XCTAssertGreaterThanOrEqual(m.p10, Self.minCrossingAngle, "\(name) char \(char): the skin meets the foot piece nearly tangentially (\(m.p10) deg): a ragged join")
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
        XCTAssertTrue(m.saw > Self.maxSawtooth || m.p10 < Self.minCrossingAngle, "the old collar's sawtooth join was not detected (\(m.saw * 100) cm, \(m.p10) deg)")
    }
}
