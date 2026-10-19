//
//  SolverParityTests.swift
//  Guards the soft-body solver and the skinner against behaviour changes while they are optimised: scripted runs (walk, run, throw, squish,
//  jiggle, three Jellies roaming) record every 5th step's particle positions (and the final skinned vertices) to a golden directory, and a later
//  run compares against them. Bit-identical is the target; the hard bound is 1e-4 H on any particle.
//
//  Modes (TEST_RUNNER_ env of the test host): PARITY_MODE=record writes the goldens into PARITY_DIR; PARITY_MODE=compare (default) reads them.
//  Without a PARITY_DIR the compare is skipped (the goldens are machine-local scratch, not checked in).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SolverParityTests: XCTestCase {
    static let H = Float(BobForm.top)
    static let bound: Float = 1e-4 * Float(BobForm.top)
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private var dir: URL? {
        guard let p = ProcessInfo.processInfo.environment["PARITY_DIR"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p)
    }
    private var recording: Bool { ProcessInfo.processInfo.environment["PARITY_MODE"] == "record" }

    /// A recorded run: samples of the particle array every `every` steps + the final skin.
    private struct Trace {
        var samples: [Float] = []
        var skin: [Float] = []
        mutating func sample(_ sims: [SoftBody]) { for s in sims { samples.append(contentsOf: s.x) } }
    }

    private func finish(_ name: String, _ t: Trace, steps: Int) throws {
        guard let dir else { MotionLog.write("PARITY \(name): no PARITY_DIR, skipped"); return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fs = dir.appendingPathComponent("\(name).samples.f32"), fk = dir.appendingPathComponent("\(name).skin.f32")
        if recording {
            try t.samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: fs)
            try t.skin.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: fk)
            MotionLog.write(String(format: "PARITY %@: recorded %d samples (%d steps), %d skin floats", name, t.samples.count, steps, t.skin.count))
            return
        }
        func load(_ u: URL) throws -> [Float] {
            let d = try Data(contentsOf: u)
            return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        let gs = try load(fs), gk = try load(fk)
        XCTAssertEqual(gs.count, t.samples.count, "\(name): same number of particle samples")
        XCTAssertEqual(gk.count, t.skin.count, "\(name): same number of skin floats")
        var maxDev: Float = 0, firstDiff = -1, nDiff = 0
        for i in 0..<min(gs.count, t.samples.count) {
            let d = abs(gs[i] - t.samples[i])
            if d > 0 { nDiff += 1; if firstDiff < 0 { firstDiff = i } }
            maxDev = max(maxDev, d)
        }
        var skinDev: Float = 0
        for i in 0..<min(gk.count, t.skin.count) { skinDev = max(skinDev, abs(gk[i] - t.skin[i])) }
        let identical = nDiff == 0 && skinDev == 0
        MotionLog.write(String(format: "PARITY %@: %@ | particles max dev %.3e (%.2e H, %d of %d floats differ, first at sample float %d) | skin max dev %.3e",
                               name, identical ? "BIT-IDENTICAL" : "differs", maxDev, maxDev / Self.H, nDiff, gs.count, firstDiff, skinDev))
        XCTAssertLessThan(maxDev, Self.bound, "\(name): particles within 1e-4 H of the original solver")
        XCTAssertLessThan(skinDev, Self.bound, "\(name): skinned vertices within 1e-4 H of the original")
    }

    private func skin(_ r: MotionRig) -> [Float] { r.render(); return r.dyn }

    private func scripted(_ name: String, game: Bool, steps: Int, every: Int = 5, start: (MotionRig) -> Void, each: ((MotionRig, Int) -> Void)? = nil) throws {
        let r = MotionRig(game: game)
        Self.keep.append(r)
        r.brain.seed = 7
        start(r)
        var t = Trace()
        for i in 0..<steps {
            each?(r, i)
            r.tick()
            if i % every == 0 { t.sample([r.sim]) }
        }
        t.skin = skin(r)
        try finish(name, t, steps: steps)
    }

    func testWalkParity() throws {
        try scripted("walk", game: false, steps: 420) { $0.brain.request(.goTo($0.root + SIMD2(1.4, 0.6))) }
    }

    func testRunParity() throws {
        try scripted("run", game: true, steps: 600) { r in
            r.brain.seed = 11; r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(.run, r.sim), "run starts")
        }
    }

    func testMarchAndWaveParity() throws {
        try scripted("march", game: false, steps: 300) { $0.brain.startStepping(seconds: 4, sim: $0.sim) }
        try scripted("wave", game: false, steps: 240) { $0.brain.request(.wave) }
    }

    /// Grab, drag, release with a fling (free flight, floor bounce, spin), then the settle.
    func testThrowParity() throws {
        let r = MotionRig(game: false)
        Self.keep.append(r)
        var t = Trace()
        let c = r.sim.centroid()
        r.sim.beginGrab(hit: c + SIMD3(0.1, 0.3, 0.2), radius: 0.4)
        for i in 0..<40 {
            let s = Float(i) / 40
            r.sim.moveGrab(target: c + SIMD3(0.1 + 0.8 * s, 0.3 + 0.9 * s, 0.2 - 0.3 * s), rot: nil)
            r.sim.step(); if i % 5 == 0 { t.sample([r.sim]) }
        }
        r.sim.endGrab()
        r.sim.launch(velocity: SIMD3(3.5, 4.2, -1.3), spin: SIMD3(0.6, 0.2, -2.5))
        for i in 0..<300 { r.sim.step(); if i % 5 == 0 { t.sample([r.sim]) } }
        t.skin = skin(r)
        try finish("throw", t, steps: 340)
    }

    /// A fingertip sphere pressed into the belly and slid sideways (the squish / pet contact), then let go.
    func testSquishParity() throws {
        try scripted("squish", game: true, steps: 240) { _ in } each: { r, i in
            if i < 150 {
                let s = Float(i) / 150
                let c = r.sim.centroid()
                r.sim.setPress(center: c + SIMD3(-0.35 + 0.7 * s, 0.1, 0.55 - 0.25 * sinf(s * 3)), radius: 0.22)
            } else if i == 150 { r.sim.endPress() }
        }
    }

    /// The nudge hop (a twisting jump: every particle gets a velocity kick) and the landing jiggle.
    func testJiggleParity() throws {
        try scripted("jiggle", game: false, steps: 240) { _ in } each: { r, i in if i == 10 { r.sim.nudge(strength: 1) } }
    }

    /// Three game brains roaming for 20 s on the parallel step (the stage's path).
    func testThreeJellyRoamParity() throws {
        let spots = JellyRoster.spawnSpots(count: 3)
        let rigs = (0..<3).map { _ in MotionRig(game: true) }
        Self.keep += rigs
        for (i, r) in rigs.enumerated() {
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: spots[i])
            for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim)
            r.brain.autonomy = true
            r.brain.steerID = i; r.brain.peerGap = MelonController.jellyGap
            r.brain.seed = UInt64(11 + i * 7)
        }
        let sims = rigs.map(\.sim)
        var t = Trace()
        let steps = 60 * 20
        for f in 0..<steps {
            for r in rigs { r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false) }
            JellyParallel.step(sims)
            if f % 5 == 0 { t.sample(sims) }
        }
        for r in rigs { t.skin += skin(r) }
        try finish("roam3", t, steps: steps)
    }
}
