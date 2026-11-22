//
//  SmoothDrawTests.swift
//  smooth-motion-r1: the ball is drawn between two steps every frame (no repeated pose at 120 Hz), a steady 30 / 24 fps frame keeps real speed, a hitch is still guarded,
//  the physics does not know about the switch, and the impact taps (none for rolling, soft for a head / foot, firmer for the floor).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SmoothDrawTests: XCTestCase {
    let stepDt: Float = 1.0 / 60
    override func setUp() { super.setUp(); SmoothDraw.on = true; SmoothDraw.reset() }
    override func tearDown() { SmoothDraw.on = true; SmoothDraw.reset(); super.tearDown() }

    /// The stage's accumulator loop (MelonStage.draw) as a pure function over a frame timeline: returns the steps run per frame.
    func run(fps: Int, seconds: Double, cpuMs: Double, dtJitter: Bool = false, body: (Int, Float) -> Void = { _, _ in }) -> (steps: Int, perFrame: [Int]) {
        var acc: Float = 0, total = 0, per: [Int] = []
        let interval = 1.0 / Double(fps)
        for f in 0..<Int(seconds * Double(fps)) {
            let dt = MelonController.pacedDt(interval * (dtJitter && f % 2 == 0 ? 1.04 : 1), fps: fps)
            acc += dt
            let maxSteps = SmoothDraw.maxSteps(base: cpuMs > 12 ? 1 : 2, dt: dt, fps: fps, stepDt: stepDt, cpuMs: cpuMs)
            var steps = 0
            while acc >= stepDt - 1e-6 && steps < maxSteps { acc -= stepDt; steps += 1; total += 1 }
            if steps == maxSteps { acc = min(acc, stepDt) }
            per.append(steps); body(steps, max(acc, 0) / stepDt)
        }
        return (total, per)
    }

    func testGameRunsAtRealSpeedAtEveryRate() {
        for fps in [120, 60, 30, 24] {
            for cpu in [3.0, 14.0] {          // an idle frame and one over the old 12 ms rule (the old cap ran it at one step)
                let r = run(fps: fps, seconds: 10, cpuMs: cpu)
                let rate = Double(r.steps) * Double(stepDt) / 10
                XCTAssertEqual(rate, 1.0, accuracy: 0.03, "fps \(fps) cpu \(cpu): \(rate)")
            }
        }
    }

    func testOldRuleWasSlowAtLowRates() {          // documents the bug the switch fixes
        SmoothDraw.on = false
        XCTAssertEqual(Double(run(fps: 24, seconds: 10, cpuMs: 3).steps) * Double(stepDt) / 10, 0.8, accuracy: 0.03)
        XCTAssertEqual(Double(run(fps: 30, seconds: 10, cpuMs: 14).steps) * Double(stepDt) / 10, 0.5, accuracy: 0.03)
    }

    func testHitchAndHeavyFramesKeepTheOldCap() {
        XCTAssertEqual(SmoothDraw.maxSteps(base: 2, dt: 0.1, fps: 24, stepDt: stepDt, cpuMs: 3), 2)          // one long frame: still two steps at most
        XCTAssertEqual(SmoothDraw.maxSteps(base: 1, dt: 1.0 / 24, fps: 24, stepDt: stepDt, cpuMs: 30), 1)    // a frame that costs most of its interval cannot catch up
        XCTAssertEqual(SmoothDraw.maxSteps(base: 2, dt: 1.0 / 60, fps: 60, stepDt: stepDt, cpuMs: 3), 2)
        XCTAssertEqual(SmoothDraw.maxSteps(base: 1, dt: 1.0 / 120, fps: 120, stepDt: stepDt, cpuMs: 3), 1)
        SmoothDraw.on = false
        XCTAssertEqual(SmoothDraw.maxSteps(base: 2, dt: 1.0 / 24, fps: 24, stepDt: stepDt, cpuMs: 3), 2)
    }

    /// A ball thrown up and left to bounce, stepped by the real TossBall, drawn every frame at 120 Hz.
    func drawnTimeline(fps: Int, on: Bool, seconds: Double = 2.2) -> (drawn: [SIMD3<Float>], phys: [SIMD3<Float>]) {
        SmoothDraw.on = on; SmoothDraw.reset()
        var ball = TossBall(pos: SIMD3(-1, 0.8, 3), radius: 0.27); ball.vel = SIMD3(2.5, 5.0, -1.2)
        var w = TossWorld(); w.xHalf = { _ in 6 }
        var acc: Float = 0, drawn: [SIMD3<Float>] = [], phys: [SIMD3<Float>] = []
        for f in 0..<Int(seconds * Double(fps)) {
            acc += Float(1.0 / Double(fps))
            let maxSteps = SmoothDraw.maxSteps(base: 2, dt: Float(1.0 / Double(fps)), fps: fps, stepDt: stepDt, cpuMs: 3)
            var steps = 0
            while acc >= stepDt - 1e-6 && steps < maxSteps {
                ball.step(stepDt, in: w); phys.append(ball.pos)
                SmoothDraw.record(pos: ball.pos, rot: ball.rot, phase: .flying)
                acc -= stepDt; steps += 1
            }
            SmoothDraw.alpha = min(max(acc / stepDt, 0), 1)
            if f > 2 { drawn.append(SmoothDraw.drawn(pos: ball.pos, rot: ball.rot, jellies: []).pos) }
        }
        return (drawn, phys)
    }

    func testNoRepeatedBallPositionAt120WithTheSwitchOn() {
        let on = drawnTimeline(fps: 120, on: true).drawn
        let off = drawnTimeline(fps: 120, on: false).drawn
        func repeats(_ a: [SIMD3<Float>]) -> Int { zip(a, a.dropFirst()).filter { $0 == $1 }.count }
        XCTAssertEqual(repeats(on), 0)
        XCTAssertGreaterThan(repeats(off), on.count / 3)          // today: about every second frame is a repeat
    }

    func testPhysicsIdenticalWithTheSwitchOnOrOff() {
        for fps in [120, 60] {
            let a = drawnTimeline(fps: fps, on: true).phys, b = drawnTimeline(fps: fps, on: false).phys
            XCTAssertEqual(a.count, b.count)
            XCTAssertTrue(zip(a, b).allSatisfy { $0 == $1 }, "ball physics must be bit-identical (fps \(fps))")
        }
    }

    func testDrawnPositionStaysBetweenTheTwoSteps() {
        let t = drawnTimeline(fps: 120, on: true)
        XCTAssertFalse(t.drawn.isEmpty)
        // along the flight the drawn height never leaves the physics' own range, and consecutive frames never jump more than one step of travel
        let maxStep = zip(t.phys, t.phys.dropFirst()).map { simd_distance($0, $1) }.max() ?? 0
        XCTAssertTrue(zip(t.drawn, t.drawn.dropFirst()).allSatisfy { simd_distance($0, $1) <= maxStep + 1e-4 })
    }

    func testNearAJelmikoTheBallLeansToTheNewestStep() {
        SmoothDraw.on = true; SmoothDraw.reset()
        let q = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        SmoothDraw.record(pos: SIMD3(0, 1, 0), rot: q, phase: .flying)
        SmoothDraw.record(pos: SIMD3(1, 1, 0), rot: q, phase: .flying)
        SmoothDraw.alpha = 0
        XCTAssertEqual(SmoothDraw.drawn(pos: SIMD3(1, 1, 0), rot: q, jellies: []).pos.x, 0, accuracy: 1e-6)          // far from everyone: the older step
        XCTAssertEqual(SmoothDraw.drawn(pos: SIMD3(1, 1, 0), rot: q, jellies: [(pos: SIMD2(1, 0.5), top: 1.1)]).pos.x, 1, accuracy: 1e-6)          // in reach: the newest step, as the bodies are drawn
        let mid = SmoothDraw.drawn(pos: SIMD3(1, 1, 0), rot: q, jellies: [(pos: SIMD2(1.0 + 1.2, 0), top: 1.1)]).pos.x
        XCTAssertTrue(mid > 0 && mid < 1, "the lean is continuous: \(mid)")
    }

    func testATeleportAndAStaleStateAreNotInterpolated() {
        SmoothDraw.on = true; SmoothDraw.reset()
        let q = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        SmoothDraw.record(pos: SIMD3(0, 1, 0), rot: q, phase: .flying)
        SmoothDraw.record(pos: SIMD3(5, 1, 0), rot: q, phase: .flying)          // a jump of 5 u: a new throw, not a path
        SmoothDraw.alpha = 0.2
        XCTAssertEqual(SmoothDraw.drawn(pos: SIMD3(5, 1, 0), rot: q, jellies: []).pos.x, 5, accuracy: 1e-6)
        XCTAssertEqual(SmoothDraw.drawn(pos: SIMD3(9, 1, 0), rot: q, jellies: []).pos.x, 9, accuracy: 1e-6)          // the ball was moved after the last step (a flick)
    }

    func testTapsFollowTheImpactSpeed() {
        XCTAssertNil(PlayHaptics.tap(.floor, speed: 1.0))          // a small rolling bounce: nothing
        XCTAssertNil(PlayHaptics.tap(.floor, speed: 2.9))
        let f1 = PlayHaptics.tap(.floor, speed: 4)!, f2 = PlayHaptics.tap(.floor, speed: 9)!
        XCTAssertLessThan(f1.intensity, f2.intensity)
        let h = PlayHaptics.tap(.head, speed: 6)!, k = PlayHaptics.tap(.foot, speed: 6)!
        XCTAssertEqual(h.style, .soft); XCTAssertEqual(k.style, .soft); XCTAssertEqual(f2.style, .medium)          // head / foot: soft and round; floor: firmer
        XCTAssertLessThan(PlayHaptics.tap(.head, speed: 2)!.intensity, PlayHaptics.tap(.head, speed: 9)!.intensity)
        XCTAssertLessThanOrEqual(PlayHaptics.tap(.head, speed: 99)!.intensity, 0.8 + 1e-6)
    }

    func testSwitchOffMeansNoNewTap() {
        SmoothDraw.on = false
        XCTAssertFalse(PlayHaptics.play(.kick(id: 0), incoming: 1, outgoing: 5))          // the old fixed buzz stays
    }

    /// item 3 of the brief: what drawing every body between two steps would cost per frame (measured, printed as SMOOTHCOST lines). The two cheapest ways:
    /// (A) blend the particle positions before the skin, (B) blend the skinned vertex stream (pos + normal) after it. Both are timed on top of today's skin pass.
    func testBodyBlendCost() {
        let ap = BlobAppearance.berry
        let sm = buildSimMesh(appearance: ap), rm = buildRenderMesh(appearance: ap)
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        for bodies in [3, 5] {
            var jobs: [JellyParallel.SkinJob] = [], sims: [SoftBody] = []
            var prevX: [[Float]] = [], tmpX: [[Float]] = [], prevOut: [UnsafeMutablePointer<Float>] = [], curOut: [UnsafeMutablePointer<Float>] = []
            for i in 0..<bodies {
                let b = SoftBody(mesh: sm, firmness: 0.95, damping: 0.45); b.reset(drop: 0.35); for _ in 0..<30 { b.step() }
                let sk = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount, eyes: buildEyeRig(render: rm, sim: sm, appearance: ap), antennae: buildAntennaRig(render: rm, sim: sm))
                let dst = UnsafeMutablePointer<Float>.allocate(capacity: rm.vertexCount * 6)
                jobs.append(JellyParallel.SkinJob(skinner: sk, sim: b, dst: dst, id: i)); sims.append(b)
                prevX.append(b.x); tmpX.append(b.x)
                prevOut.append(.allocate(capacity: rm.vertexCount * 6)); curOut.append(.allocate(capacity: rm.vertexCount * 6))
                prevOut[i].initialize(repeating: 0, count: rm.vertexCount * 6); curOut[i].initialize(repeating: 0, count: rm.vertexCount * 6)
            }
            defer { for j in jobs { j.dst.deallocate() }; for p in prevOut + curOut { p.deallocate() } }
            let n = 300, nv = rm.vertexCount * 6
            func time(_ f: () -> Void) -> Double { let t0 = CACurrentMediaTime(); for _ in 0..<n { f() }; return (CACurrentMediaTime() - t0) / Double(n) * 1000 }
            let skinMs = time { JellyParallel.skin(jobs, index: rm.index) }
            let a: Float = 0.37
            let blendA = time {          // (A) x = prev + (cur - prev) * a, per body, before the skin
                for i in 0..<bodies { let cx = sims[i].x; prevX[i].withUnsafeBufferPointer { p in cx.withUnsafeBufferPointer { c in tmpX[i].withUnsafeMutableBufferPointer { o in for k in 0..<o.count { o[k] = p[k] + (c[k] - p[k]) * a } } } } }
            }
            let blendB = time {          // (B) out = prev + (cur - prev) * a over the vertex stream, after the skin
                for i in 0..<bodies { let p = prevOut[i], c = curOut[i], o = jobs[i].dst; for k in 0..<nv { o[k] = p[k] + (c[k] - p[k]) * a } }
            }
            let line = String(format: "SMOOTHCOST %d bodies, %d vertices each: skin pass %.3f ms | (A) blend particles %.3f ms | (B) blend skinned vertices %.3f ms | 120 Hz frame = 8.33 ms, governor CPU headroom 5 ms", bodies, rm.vertexCount, skinMs, blendA, blendB)
            print(line); NSLog("%@", line)
            if let h = FileHandle(forWritingAtPath: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/e0755ccf-aeea-4c40-b871-1f1d2b621362/scratchpad/smooth/cost.txt") ?? { FileManager.default.createFile(atPath: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/e0755ccf-aeea-4c40-b871-1f1d2b621362/scratchpad/smooth/cost.txt", contents: nil); return FileHandle(forWritingAtPath: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/e0755ccf-aeea-4c40-b871-1f1d2b621362/scratchpad/smooth/cost.txt") }() { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!) }
        }
    }

    // MARK: same-seed physics with real bodies (the switch must not change one bit of the ball or the bodies)
    nonisolated(unsafe) static var keep: [MotionRig] = []
    func tossTrace(on: Bool) -> [String] {
        SmoothDraw.on = on; SmoothDraw.reset()
        GameCamera.playBlend = 0; DecorField.shared.clear()
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 393.0 / 852.0)
        let r = MotionRig(game: true); Self.keep.append(r)
        r.renderSamples = false; r.brain.anticsEnabled = true; r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: SIMD2(0, 0.6)); for _ in 0..<120 { r.sim.step() }; r.brain.currentPose(r.sim)
        let p = PlayToss(); p.forceQuality = .good; p.seed(11); p.viewSize = CGSize(width: 393, height: 852)
        let jelly = { PlayJelly(id: 0, brain: r.brain, sim: r.sim, skinner: r.skinner) }
        var w = TossWorld(); w.xHalf = { DecorPlacement.visibleHalf(z: $0) + 0.3 }
        p.begin(ball: .ball, title: "Bouncy ball", jellies: [jelly()], snapCamera: true)
        p.onEvent = { e in PlayHaptics.play(e, incoming: SmoothDraw.incomingSpeed, outgoing: simd_length(p.ball.vel)) }          // (the stage's feel hook)
        var out: [String] = []
        for k in 0..<(60 * 14) {
            if k == 180 { p.flick(from: CGPoint(x: 393 * 0.5, y: 852 * 0.83), velocity: CGVector(dx: 0, dy: -852 * 1.8)) }
            r.tick(); p.tick(dt: r.sim.stepDt, world: w, jellies: [jelly()])
            if on { SmoothDraw.record(pos: p.ball.pos, rot: p.ball.rot, phase: p.phase); SmoothDraw.alpha = Float(k % 2) * 0.5; _ = SmoothDraw.ball(p) }
            var sum: UInt64 = 0; for v in r.sim.x { sum = sum &* 1099511628211 &+ UInt64(v.bitPattern) }
            out.append(String(format: "%a %a %a %016llx", Double(p.ball.pos.x), Double(p.ball.pos.y), Double(p.ball.pos.z), sum))
        }
        return out
    }

    func testBallAndBodyPhysicsAreBitIdenticalWithTheSwitchOnOrOff() {
        let a = tossTrace(on: false), b = tossTrace(on: false), c = tossTrace(on: true)
        XCTAssertEqual(a.count, 840)
        XCTAssertEqual(a, b, "the harness itself must be deterministic")
        XCTAssertEqual(a, c, "the ball and the body, every step: identical with SmoothDraw on")
        XCTAssertTrue(a.contains { $0.hasPrefix("0x") } && Set(a.map { String($0.prefix(30)) }).count > 50, "the ball really flew")
    }
}
