//
//  SolverBenchTests.swift
//  Micro-benchmark of the soft-body step and the skin, pass by pass (SoftBody.profileStep / Skinner.profileUpdate), idle and mid-walk.
//  Prints "BENCH ..." lines to the motion log; run in Release (ENABLE_TESTABILITY=YES) for the numbers that matter.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SolverBenchTests: XCTestCase {
    private func report(_ name: String, _ rows: [(String, Double)], steps: Int) {
        let total = rows.reduce(0) { $0 + $1.1 } / Double(steps)
        let parts = rows.map { String(format: "%@ %.0f", $0.0, $0.1 / Double(steps)) }.joined(separator: " | ")
        MotionLog.write(String(format: "BENCH %@: total %.0f us per step | %@", name, total, parts))
    }

    private func merge(_ into: inout [(String, Double)], _ rows: [(String, Double)]) {
        for (k, v) in rows {
            if let i = into.firstIndex(where: { $0.0 == k }) { into[i].1 += v } else { into.append((k, v)) }
        }
    }

    func testStepPasses() {
        let probe = MotionRig.simMesh
        let sb = SoftBody(mesh: probe)
        MotionLog.write(String(format: "BENCH schedule: %d tets in %d levels -> %d SIMD4 groups (%.1f %% lanes used)",
                               sb.nT, sb.tetLevels, sb.tetGroups, 100 * Double(sb.nT) / Double(4 * sb.tetGroups)))
        for mode in ["SIMD 8-lane", "SIMD 4-lane", "scalar reference"] {
        SoftBody.referenceSolver = mode == "scalar reference"; SoftBody.narrowTets = mode == "SIMD 4-lane"
        defer { SoftBody.referenceSolver = false; SoftBody.narrowTets = false }
        for (name0, game, start) in [("idle studio", false, { (_: MotionRig) in }),
                                    ("walk", false, { (r: MotionRig) in r.brain.request(.goTo(r.root + SIMD2(0, 3))) }),
                                    ("march game", true, { (r: MotionRig) in r.brain.startStepping(seconds: 6, sim: r.sim) })] {
            let name = name0 + " [" + mode + "]"
            let r = MotionRig(game: game)
            start(r)
            r.run(0.5)
            var rows: [(String, Double)] = []
            let steps = 240
            var plain = 0.0
            for i in 0..<steps {
                r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
                if i % 2 == 0 {
                    merge(&rows, r.sim.profileStep())
                } else {
                    let t0 = CACurrentMediaTime(); r.sim.step(); plain += CACurrentMediaTime() - t0
                }
            }
            report(name, rows, steps: steps / 2)
            MotionLog.write(String(format: "BENCH %@: plain sim.step %.0f us", name, plain / Double(steps / 2) * 1e6))
        }
        }
    }

    /// Before / after on one build: the THREEPERF measurement (step + skin: 1 body, 3 serial, 3 threaded) with the scalar reference sweeps and the
    /// scatter normals (= the code before this work) against the level-scheduled SIMD kernels and the gathered normals.
    func testThreeBodyBeforeAfter() {
        let sm = buildSimMesh(), rm = buildRenderMesh()
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let spots = JellyRoster.spawnSpots(count: 3)
        let actors = (0..<3).map {
            let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
            a.reset(drop: 0.35, shift: true)
            return a
        }
        let n = rm.vertexCount * 6
        let dyn = UnsafeMutablePointer<Float>.allocate(capacity: n * 3)
        defer { dyn.deallocate() }
        let sims = actors.map(\.sim)
        let jobs = (0..<3).map { JellyParallel.SkinJob(skinner: actors[$0].skinner, sim: actors[$0].sim, dst: dyn + $0 * n) }
        for _ in 0..<30 { JellyParallel.step(sims) }
        for pass in 0..<2 {
            let before = pass == 0
            SoftBody.referenceSolver = before; Skinner.scatterNormals = before
            defer { SoftBody.referenceSolver = false; Skinner.scatterNormals = false }
            let frames = 200
            var t0 = CACurrentMediaTime()
            for _ in 0..<frames { JellyParallel.step(sims); JellyParallel.skin(jobs, index: rm.index) }
            let par = (CACurrentMediaTime() - t0) / Double(frames) * 1000
            t0 = CACurrentMediaTime()
            for _ in 0..<frames { for s in sims { s.step() }; for j in jobs { j.skinner.update(x: j.sim.x, index: rm.index, into: j.dst) } }
            let ser = (CACurrentMediaTime() - t0) / Double(frames) * 1000
            t0 = CACurrentMediaTime()
            for _ in 0..<frames { for s in sims { s.step() } }
            let ser3step = (CACurrentMediaTime() - t0) / Double(frames) * 1000
            let one = actors[0]
            t0 = CACurrentMediaTime()
            for _ in 0..<frames { one.sim.step() }
            let oneStep = (CACurrentMediaTime() - t0) / Double(frames) * 1000
            t0 = CACurrentMediaTime()
            for _ in 0..<frames { one.skinner.update(x: one.sim.x, index: rm.index, into: dyn) }
            let oneSkin = (CACurrentMediaTime() - t0) / Double(frames) * 1000
            MotionLog.write(String(format: "THREEAB %@: 1 body step %.3f ms, skin %.3f ms | 3 bodies step serial %.3f ms | 3 bodies step+skin serial %.3f ms, threaded %.3f ms (%d cores)",
                                   before ? "BEFORE (scalar sweeps, scatter normals)" : "AFTER (SIMD level schedule, gathered normals)",
                                   oneStep, oneSkin, ser3step, ser, par, ProcessInfo.processInfo.activeProcessorCount))
        }
    }

    /// Why is the threaded step not faster than the serial one? Time each body INSIDE the concurrentPerform closure (per-thread wall time) against
    /// the outer wall time, and the same with explicit user-interactive threads.
    func testParallelStepAnatomy() {
        let sm = buildSimMesh()
        let sims = (0..<3).map { _ in SoftBody(mesh: sm, firmness: 0.95, damping: 0.45) }
        for s in sims { s.reset(drop: 0.35); for _ in 0..<30 { s.step() } }
        let frames = 60
        nonisolated(unsafe) var inner = [Double](repeating: 0, count: 3)
        nonisolated(unsafe) var qos = [Int](repeating: 0, count: 3)
        var t0 = CACurrentMediaTime()
        for _ in 0..<frames {
            sims.withUnsafeBufferPointer { b in
                DispatchQueue.concurrentPerform(iterations: 3) { i in
                    let a = CACurrentMediaTime(); b[i].step(); inner[i] += CACurrentMediaTime() - a
                    qos[i] = Int(qos_class_self().rawValue)
                }
            }
        }
        let wall = (CACurrentMediaTime() - t0) / Double(frames) * 1000
        MotionLog.write(String(format: "PARANATOMY concurrentPerform: wall %.2f ms | inside each body %.2f / %.2f / %.2f ms | qos %d %d %d (main qos %d, cores %d)",
                               wall, inner[0] / Double(frames) * 1000, inner[1] / Double(frames) * 1000, inner[2] / Double(frames) * 1000,
                               qos[0], qos[1], qos[2], Int(qos_class_main().rawValue), ProcessInfo.processInfo.activeProcessorCount))
        // serial, for the same bodies
        t0 = CACurrentMediaTime()
        for _ in 0..<frames { for s in sims { s.step() } }
        let ser = (CACurrentMediaTime() - t0) / Double(frames) * 1000
        // explicit user-interactive threads via a concurrent queue + group
        let q = DispatchQueue(label: "jelly.step", qos: .userInteractive, attributes: .concurrent)
        inner = [0, 0, 0]
        t0 = CACurrentMediaTime()
        for _ in 0..<frames {
            let g = DispatchGroup()
            sims.withUnsafeBufferPointer { b in
                for i in 0..<3 { q.async(group: g) { let a = CACurrentMediaTime(); b[i].step(); inner[i] += CACurrentMediaTime() - a; qos[i] = Int(qos_class_self().rawValue) } }
            }
            g.wait()
        }
        let wq = (CACurrentMediaTime() - t0) / Double(frames) * 1000
        MotionLog.write(String(format: "PARANATOMY serial %.2f ms | UI-qos queue: wall %.2f ms | inside %.2f / %.2f / %.2f ms | qos %d %d %d", ser, wq,
                               inner[0] / Double(frames) * 1000, inner[1] / Double(frames) * 1000, inner[2] / Double(frames) * 1000, qos[0], qos[1], qos[2]))
    }

    func testSkinPasses() {
        let r = MotionRig(game: false)
        r.brain.request(.goTo(r.root + SIMD2(0, 3)))
        r.run(0.8)
        for scatter in [false, true] {
        Skinner.scatterNormals = scatter
        defer { Skinner.scatterNormals = false }
        var rows: [(String, Double)] = []
        let n = 200
        var plain = 0.0
        r.dyn.withUnsafeMutableBufferPointer { d in
            r.sim.x.withUnsafeBufferPointer { xb in
                for _ in 0..<n {
                    merge(&rows, r.skinner.profileUpdate(x: xb.baseAddress!, index: MotionRig.renderMesh.index, into: d.baseAddress!))
                    let t0 = CACurrentMediaTime()
                    r.skinner.update(x: xb.baseAddress!, index: MotionRig.renderMesh.index, into: d.baseAddress!)
                    plain += CACurrentMediaTime() - t0
                }
            }
        }
        report("skin (walk)" + (scatter ? " [scatter normals]" : " [gather normals]"), rows, steps: n)
        MotionLog.write(String(format: "BENCH skin (walk) %@: plain Skinner.update %.0f us (%d verts, %d tris)", scatter ? "[scatter normals]" : "[gather normals]", plain / Double(n) * 1e6, r.skinner.vertexCount, MotionRig.renderMesh.index.count / 3))
        }
    }
}
