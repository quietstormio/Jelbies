//
//  WalkPolishLockTests.swift
//  walk-polish-r1. Records the walk (three speeds, 10 s each) and every run-like gait (run, zoomies, trot, hurry, two playChase gains, each from a stand) channel by channel
//  (root, heading, both planted feet, the pose channels, the arm phases, the attractor, the rendered feet and the folded rendered mesh). The golden was recorded on fdb1acd0
//  (= tag walk-lock-2026-11-23) by running this file with WALK_GOLDEN_OUT=<file>; WALK_GOLDEN_IN=<file> compares (level 0: the whole walk; any level: the run-like scenarios).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WalkPolishLockTests: XCTestCase {
    static var level: Int { BlobBrain.walkPolish }

    static var firstOn: [String: Int] = [:]

    private func record(_ name: String, seconds: Float, setup: (MotionRig) -> Void) -> [String] {
        let r = MotionRig(game: false)
        r.renderSamples = false
        r.brain.seed = 11
        setup(r)
        var out: [String] = [], n = 0
        r.run(seconds, each: {
            n += 1
            if r.brain.wp.w > 0, Self.firstOn[name] == nil { Self.firstOn[name] = out.count }
            guard n % 2 == 0 else { return }
            let b = r.brain, a = r.sim.attractor
            var f: [Double] = [Double(r.t), Double(b.px), Double(b.pz), Double(b.yaw),
                               Double(b.feet.pos[0].x), Double(b.feet.pos[0].y), Double(b.feet.pos[1].x), Double(b.feet.pos[1].y), Double(b.feet.stepU),
                               Double(b.roll), Double(b.pitch), Double(b.squash), Double(b.lift), Double(b.nubPhi[0]), Double(b.nubPhi[1]), Double(b.runW),
                               Double(a.anchor.x), Double(a.anchor.y), Double(a.anchor.z), Double(a.squash), Double(a.rotation.vector.x), Double(a.rotation.vector.y), Double(a.rotation.vector.z), Double(a.rotation.vector.w)]
            let c = r.sim.centroid(); f += [Double(c.x), Double(c.y), Double(c.z)]
            if n % 6 == 0 {
                r.render()
                for s in 0..<2 { let p = r.renderedFootXZ(s); f += [Double(p.x), Double(p.y), Double(r.renderedFootGap(s))] }
                var v: Double = 0
                for (i, x) in r.dyn.enumerated() where i % 5 == 0 { v += Double(x) * Double(1 + i % 7) }
                f.append(v)
            }
            out.append(name + " " + f.map { String(format: "%.7g", $0) }.joined(separator: " "))
        })
        return out
    }

    private func all() -> (walk: [String], runs: [String]) {
        Self.firstOn = [:]
        var walk: [String] = [], runs: [String] = []
        func go(_ r: MotionRig, _ d: Float = 16) { r.brain.request(.goTo(r.root + SIMD2(0, d))) }
        walk += record("walk_roam", seconds: 10) { go($0) }
        walk += record("walk_mid", seconds: 10) { r in r.brain.amplitude = 0.85; go(r) }          // (a middle-sized Jelmiko)
        walk += record("walk_small", seconds: 10) { r in r.brain.amplitude = 0.7; go(r) }          // (a small / calm Jelmiko: shorter stride)
        runs += record("run", seconds: 8) { r in r.brain.idleForced = true; _ = r.brain.idleStart(.run, r.sim) }
        runs += record("zoomies", seconds: 8) { r in r.brain.idleForced = true; _ = r.brain.idleStart(.zoomies, r.sim) }
        runs += record("trot", seconds: 8) { r in r.brain.idleForced = true; _ = r.brain.idleStart(.trot, r.sim) }
        runs += record("hurry", seconds: 8) { r in r.brain.hurry = true; go(r, 8) }
        runs += record("chase13", seconds: 8) { r in r.brain.playChase = 1.3; go(r, 8) }
        runs += record("chase16", seconds: 8) { r in r.brain.playChase = 1.6; go(r, 8) }
        return (walk, runs)
    }

    /// name -> lines
    private func parse(_ lines: [String]) -> [String: [[Double]]] {
        var d: [String: [[Double]]] = [:]
        for l in lines { let p = l.split(separator: " "); d[String(p[0]), default: []].append(p.dropFirst().compactMap { Double($0) }) }
        return d
    }

    private func compare(_ got: [String], _ goldPath: String, only: (String) -> Bool, tol: Double, label: String) {
        guard let txt = try? String(contentsOfFile: goldPath, encoding: .utf8) else { return XCTFail("no golden at \(goldPath)") }
        let gold = parse(txt.split(separator: "\n").map(String.init).filter { only(String($0.split(separator: " ")[0])) })
        let g = parse(got)
        for k in gold.keys.sorted() {
            guard let a = g[k], let b = gold[k] else { XCTFail("\(label) \(k) missing"); continue }
            XCTAssertEqual(a.count, b.count, "\(label) \(k) sample count")
            let cut = (label.hasPrefix("run-level") && Self.level > 0) ? (Self.firstOn[k] ?? a.count) : a.count          // (a run-like gait that has ended and gone back to a plain walk may polish from then on)
            if cut < a.count { MotionLog.write("LOCK \(label) \(k): polish first on at row \(cut) of \(a.count) (compared before it)") }
            let aa = Array(a.prefix(cut)), bb = Array(b.prefix(cut))
            var worst = 0.0, worstAt = ""
            for (i, (x, y)) in zip(aa, bb).enumerated() {
                XCTAssertEqual(x.count, y.count, "\(label) \(k) row \(i) width")
                for (j, (u, v)) in zip(x, y).enumerated() where abs(u - v) > worst { worst = abs(u - v); worstAt = "row \(i) col \(j)" }
            }
            MotionLog.write(String(format: "LOCK %@ %@ worst abs diff %.3g (%@) level %d", label, k, worst, worstAt, Self.level))
            XCTAssertLessThanOrEqual(worst, tol, "\(label) \(k): \(worstAt)")
        }
    }

    func testRecordOrCompareTheWalkAndTheRun() {
        let env = ProcessInfo.processInfo.environment
        let savedLevel = BlobBrain.walkPolish; defer { BlobBrain.walkPolish = savedLevel }
        if let out = env["WALK_GOLDEN_OUT"] {
            BlobBrain.walkPolish = 0
            let (walk, runs) = all()
            try? (walk + runs).joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            MotionLog.write("LOCK wrote \(walk.count + runs.count) rows to \(out)")
            return
        }
        guard let gin = env["WALK_GOLDEN_IN"] else { return }          // (nothing asked: the recording is only a tool)
        for level in (env["WALK_LEVELS"] ?? "0").split(separator: ",").compactMap({ Int($0) }) {
            BlobBrain.walkPolish = level
            let (walk, runs) = all()
            if level == 0 { compare(walk, gin, only: { $0.hasPrefix("walk") }, tol: 1e-5, label: "walk") }
            else {          // (the polished walk differs by design: how much, per channel, is logged)
                compare(walk, gin, only: { $0.hasPrefix("walk") }, tol: .infinity, label: "walk-diff-level\(level)")
            }
            compare(runs, gin, only: { !$0.hasPrefix("walk") }, tol: 1e-5, label: "run-level\(level)")
        }
    }
}
