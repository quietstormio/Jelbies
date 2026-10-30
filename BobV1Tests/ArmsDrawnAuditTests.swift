//
//  ArmsDrawnAuditTests.swift
//  2026-10-30 (the cartwheel's "legs come off", seen on the phone and in the real-app recordings): in a cartwheel one of the two arm capsules was drawn FLOATING
//  in the air, a hand's breadth off the body, for ~0.4 s from mid-flight to well after the landing. The old audits missed it: ArmCapTests judges the arm in the
//  idealised body frame (is the root inside the analytic egg?), LegsDrawnAuditTests only measures the foot beans. This audit measures what is DRAWN: per arm and
//  frame, the closest approach of the skinned arm capsule to the skinned body (signed distance to the nearest drawn triangle, sign from the skinned normals).
//  <= 0 = a part of the capsule is inside the body = attached; the gap is how far the whole capsule floats off it.
//  Same stage-order driver and cadences as LegsDrawnAuditTests (60 / 120 fps, hitch frames).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ArmsDrawnAuditTests: XCTestCase {
    /// An arm whose nearest vertex is further than this from the drawn body is floating (the rest nub / thumb roots are buried: they measure well below 0).
    static let maxGap: Float = 0.02
    /// The wall scenarios squeeze the body against a 0.8 u wall: the drawn body is deformed there and the arm sits on the rigid fitted pose, so a few cm more are allowed (the old code: 0.44).
    static let maxGapWall: Float = 0.10

    struct ArmM { var gap: Float = -.infinity; var side = 0; var out = false }

    /// The worst (largest) gap over the two arm capsules of this frame; `out` = a capsule is drawn at all.
    static func measure(_ r: MotionRig) -> ArmM {
        var m = ArmM()
        guard r.brain.armG > 0.5, r.skinner.armBlend > 0.5, let cap = MotionRig.renderMesh.armCapsule else { return m }
        m.out = true
        let tri = LegsDrawnAuditTests.bodyTri
        r.dyn.withUnsafeBufferPointer { d in
            @inline(__always) func P(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]) }
            @inline(__always) func N(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v + 3], d[6 * v + 4], d[6 * v + 5]) }
            for (k, side) in [-1, 1].enumerated() {
                let first = cap.first(side: side)
                var c = SIMD3<Float>.zero
                var pts: [SIMD3<Float>] = []
                var i = 0
                while i < ArmCapsule.vertexCount { pts.append(P(first + i)); i += 6 }
                for p in pts { c += p }
                c /= Float(pts.count)
                var cand: [Int] = []
                var t = 0
                while t < tri.count {
                    if simd_distance_squared(P(Int(tri[t])), c) < 0.9 * 0.9 { cand.append(t) }
                    t += 3
                }
                var closest = Float.infinity
                for p in pts {
                    var bd = Float.infinity, sgn: Float = 1
                    for t in cand {
                        let ia = Int(tri[t]), ib = Int(tri[t + 1]), ic = Int(tri[t + 2])
                        let (q, w) = DrawnGeom.closest(p, P(ia), P(ib), P(ic))
                        let dd = simd_distance_squared(p, q)
                        if dd < bd { bd = dd; let n = N(ia) * w.x + N(ib) * w.y + N(ic) * w.z; sgn = simd_dot(p - q, n) >= 0 ? 1 : -1 }
                    }
                    closest = min(closest, bd.isFinite ? sgn * bd.squareRoot() : 9)
                }
                if closest > m.gap { m.gap = closest; m.side = k }
            }
        }
        return m
    }

    /// Cartwheels from every entry, every character, the real cadences; flips and faceplants (same flight code). Worst gap and how many frames float.
    func testArmsNeverFloatOffTheBodyInCartwheelsFlipsAndFaceplants() throws {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        var scs: [LegsDrawnAuditTests.Scenario] = ["stand", "walk", "run", "zoomies"].map { LegsDrawnAuditTests.cartwheel($0) }
        for n in ["flip", "faceplant"] { if let s = LegsDrawnAuditTests.fromMove(n) { scs.append(s) } }
        // the real-app case: the room's round arena wall stops the body mid-cartwheel while the brain's attractor goes on (landscape: the room's corners reach past the wall; the planner now
        // keeps cartwheels inside it, but a furniture piece or a peer stops a body the same way). The rig has no wall of its own: when the flight starts put one 0.8 u around where he is, so he
        // stops against it (anchor and body end up ~0.5 u apart; 0.4 u in the recordings).
        for entry in ["stand", "walk"] {
            scs.append(LegsDrawnAuditTests.Scenario(name: "cartwheel-wall-\(entry)", game: true, seconds: 14, setup: { r, seed in
                var q = seed &* 2654435761 &+ 17
                let px = (LegsDrawnAuditTests.lcg(&q) - 0.5) * 1.6, pz = 0.6 + LegsDrawnAuditTests.lcg(&q) * 0.8
                r.sim.teleport(toXZ: SIMD2(px, pz)); r.run(0.4)
                r.brain.currentPose(r.sim)
                r.brain.idleForced = true
                if entry == "stand" { return r.brain.idleStart(.cartwheel, r.sim) }
                let goal = SIMD2<Float>(px * 0.5, pz + 1.2)
                r.brain.requestNow(.goTo(goal)); r.run(0.6)
                return r.brain.flourishStart(.cartwheel, resume: goal, r.sim, r.skinner)
            }, each: { r in
                if r.brain.idleState.kind == .cartwheel, r.brain.idleState.phase >= 1, !r.sim.arenaRadius.isFinite { r.sim.arenaCenter = r.root; r.sim.arenaRadius = 0.8 }
            }, endKind: .cartwheel))
        }
        BlobBrain.armsOnFit = ProcessInfo.processInfo.environment["ARMS_FIT_OFF"] == nil          // (ARMS_FIT_OFF=1: the code before the fix, the test must then fail)
        defer { BlobBrain.armsOnFit = true }
        if let only = ProcessInfo.processInfo.environment["AUDIT_ONLY"], !only.isEmpty { let parts = only.components(separatedBy: ","); scs = scs.filter { s in parts.contains { s.name.contains($0) } } }
        // (the drawn-space measure is slow: plain cartwheels / flips at 120 fps with hitch frames, the wall cases at 60 and 120; every 2nd frame)
        var worst: Float = -.infinity, floatFrames = 0, armFrames = 0, runs = 0
        var worstDesc = ""
        for sc in scs {
            for fi in 0..<4 {
                for (ci, cad) in (sc.name.contains("wall") ? [0, 1] : [3]).enumerated() {
                    let seed = UInt64(1 + fi * 7 + ci * 3 + sc.name.count)
                    var rw: Float = -.infinity, rf = 0, ra = 0, frameAt = 0
                    let res = LegsDrawnAuditTests.run(sc, feature: LegsDrawnAuditTests.features[fi].1, shoes: false, cad: LegsDrawnAuditTests.cadences[cad], seed: seed) { frame, r, _ in
                        guard frame % 2 == 0 else { return }
                        let m = Self.measure(r)
                        guard m.out else { return }
                        ra += 1
                        if m.gap > rw { rw = m.gap; frameAt = frame }
                        if m.gap > (sc.name.contains("wall") ? Self.maxGapWall : Self.maxGap) { rf += 1 }
                    }
                    if !res.started { continue }
                    runs += 1; armFrames += ra; floatFrames += rf
                    MotionLog.write(String(format: "ARMAUDIT %@ | %@ cad=%@ seed=%d | armFrames=%d floating(>2cm)=%d worstGap=%.3f@%d", sc.name, LegsDrawnAuditTests.features[fi].0, LegsDrawnAuditTests.cadences[cad].name, Int(seed), ra, rf, rw, frameAt))
                    if rw > worst { worst = rw; worstDesc = "\(sc.name) \(LegsDrawnAuditTests.features[fi].0) cad \(LegsDrawnAuditTests.cadences[cad].name) frame \(frameAt)" }
                }
            }
        }
        MotionLog.write(String(format: "ARMAUDIT TOTAL runs=%d armFrames=%d floating=%d worstGap=%.3f (%@)", runs, armFrames, floatFrames, worst, worstDesc))
        XCTAssertGreaterThan(runs, 10)
        XCTAssertEqual(floatFrames, 0, "frames where an arm capsule floats more than 2 cm (10 cm in the wall scenarios) off the DRAWN body; worst \(worst) at \(worstDesc)")
    }
}
