//
//  IdleBehaviourTests.swift
//  I1 room life: run, stumble, jumping jacks, sit / slump, look, yawn-stretch and their scheduler (BlobBrain+Idle.swift).
//  Gates: every behaviour ends at rest; the stumble keeps one foot down in every step (MotionGrounded's rule, untouched); the jacks use only the hop
//  exception; the run is the walk's stride / rate / lean / arm sweep at runW = 1 and exactly the locked walk at runW = 0; they yield to Come here / Feed /
//  focus / touch within 0.3 s; mood picks the right set; cadence and cooldown; the brain tick stays under budget.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class IdleBehaviourTests: XCTestCase {
    private struct Run {
        var rig: MotionRig
        var samples: [MotionSample] = []
        var kinds: [IdleKind?] = []
        var phases: [GaitDriver.Phase] = []
        var seen: Set<IdleKind> = []
        var armW: Float = 0
        var mouthMax: Float = 0
        var duration: Float = 0
    }

    /// Start `kind` in the game brain and record until it has ended (or `maxT`).
    private func play(_ kind: IdleKind, stumble: Bool = false, seed: UInt64 = 11, maxT: Float = 45, game: Bool = true) -> Run {
        let r = MotionRig(game: game)
        r.brain.seed = seed
        r.brain.idleForced = true
        r.brain.amplitude = 1
        if !game { r.brain.wanderCenter = .zero; r.brain.wanderRadius = 2.0 }
        XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(kind) starts")
        if stumble { r.brain.idleState.stumbleAt = 1.9 }
        var out = Run(rig: r)
        let t0 = r.t
        r.run(maxT, until: { r.brain.idleState.kind == nil }) {
            out.samples.append(r.sample())
            out.kinds.append(r.brain.idleState.kind)
            out.phases.append(r.brain.gait.phase)
            if let k = r.brain.idleState.kind { out.seen.insert(k) }
            out.armW = max(out.armW, r.brain.armDirW)
            out.mouthMax = max(out.mouthMax, r.brain.mouthOpen)
        }
        out.duration = r.t - t0
        return out
    }

    private func settleCheck(_ name: String, _ run: Run, startRoot: SIMD2<Float>?) {
        let r = run.rig
        XCTAssertNil(r.brain.idleState.kind, "\(name): the behaviour ended (took \(run.duration) s)")
        r.run(1.0)
        let c0 = r.sim.centroid()
        r.run(0.5)
        let c1 = r.sim.centroid()
        let speed = simd_length(c1 - c0) / 0.5
        let H = MotionRig.H
        MotionLog.write(String(format: "IDLE rest %@: lasted %.1f s, 1.5 s after the end: drift %.4f H over 0.5 s, speed %.4f u/s; eyes %.2f mouth %.2f armDirW %.2f runW %.2f targets %d",
                               name, run.duration, simd_length(c1 - c0) / H, speed, r.skinner.openness.left, r.brain.mouthOpen, r.brain.armDirW, r.brain.runW, r.sim.targets.count))
        XCTAssertLessThan(simd_length(c1 - c0), 0.02 * H, "\(name): centroid still at 1.5 s after the end")
        XCTAssertLessThan(speed, 0.05, "\(name): speed after 1 s")
        XCTAssertEqual(r.brain.mouthOpen, 0, "\(name): no mouth at rest")
        XCTAssertEqual(r.brain.armDirW, 0, "\(name): arm override released")
        XCTAssertEqual(r.brain.runW, 0, "\(name): run blend released")
        XCTAssertGreaterThan(r.skinner.openness.left, 0.99, "\(name): eyes open")
        XCTAssertFalse(r.sim.hasNonFinite())
        if let s0 = startRoot {
            let drift = simd_length(r.root - s0)
            MotionLog.write(String(format: "IDLE rest %@: ended %.3f H from where it started", name, drift / H))
        }
        // a behaviour that was in place stays in place (the sit may scoot a few cm while the feet step)
        if let s0 = startRoot, ["jacks", "sit", "slump", "look", "yawn"].contains(name) { XCTAssertLessThan(simd_length(r.root - s0), 0.12 * H, "\(name) stays where it is") }
    }

    // MARK: rest

    func testEveryBehaviourReturnsToRest() {
        for (name, kind, stumble) in [("run", IdleKind.run, false), ("stumble", .run, true), ("jacks", .jacks, false), ("sit", .sit, false),
                                      ("slump", .slump, false), ("look", .look, false), ("yawn", .yawn, false)] {
            let run = play(kind, stumble: stumble)
            settleCheck(name, run, startRoot: run.samples.first?.root)
            if name == "stumble" { XCTAssertTrue(run.seen.contains(.stumble), "the trip happened") }
        }
    }

    // MARK: stumble

    func testStumbleKeepsOneFootDownInEveryStep() {
        for seed: UInt64 in [3, 11, 29] {
            let run = play(.run, stumble: true, seed: seed)
            XCTAssertTrue(run.seen.contains(.stumble), "seed \(seed): the trip happened")
            let tol = MotionScenario.tol
            var worst: Float = 0, worstR: Float = 0
            for s in run.samples { worst = max(worst, min(s.gap[0], s.gap[1])); worstR = max(worstR, min(s.rgap[0], s.rgap[1])) }
            let lurch = run.samples.map { abs($0.roll) }.max() ?? 0
            MotionLog.write(String(format: "IDLE stumble seed %llu: %.1f s, worst planted-foot gap %.4f H (sim) %.4f H (drawn), arms out %.2f, max roll %.1f deg, %d samples",
                                   seed, run.duration, worst / MotionRig.H, worstR / MotionRig.H, run.armW, lurch * 57.3, run.samples.count))
            XCTAssertLessThanOrEqual(worst, tol, "seed \(seed): both feet off the floor in a stumble")
            XCTAssertLessThanOrEqual(worstR, tol, "seed \(seed): the drawn feet are both off the floor")
            XCTAssertGreaterThan(run.armW, 0.9, "the arms are flung out")
            XCTAssertFalse(run.rig.sim.hasNonFinite())
        }
    }

    func testStumbleStaysOnItsFeet() {
        let r = MotionRig(game: true)
        r.brain.idleForced = true; r.brain.seed = 5
        XCTAssertTrue(r.brain.idleStart(.run, r.sim)); r.brain.idleState.stumbleAt = 1.9
        var tiltMax: Float = 0, pitchMax: Float = 0
        r.run(30, until: { r.brain.idleState.kind == nil }) {
            let p = r.sim.bodyPose(iterations: 4)
            tiltMax = max(tiltMax, p.tilt)
            pitchMax = max(pitchMax, p.rotation.act(SIMD3<Float>(0, 1, 0)).z)
        }
        MotionLog.write(String(format: "IDLE stumble: max tilt %.1f deg, max forward lean %.1f deg", tiltMax * 57.3, asinf(pitchMax) * 57.3))
        XCTAssertLessThan(tiltMax * 57.3, 32, "a lurch, not a fall")
    }

    // MARK: jumping jacks

    func testJumpingJacksUseOnlyTheHopException() {
        for seed: UInt64 in [2, 13] {
            let run = play(.jacks, seed: seed)
            let tol = MotionScenario.tol
            // every sample with both feet off the floor is inside the hop machinery's air phase (or its tiny landing re-bounce)
            var offOutsideHop = 0, airRuns = 0, longest: Float = 0, apex: Float = 0
            var inRun = false, runStart: Float = 0
            for (i, s) in run.samples.enumerated() {
                let off = min(s.gap[0], s.gap[1]) > tol
                if off && run.phases[i] == .idle { offOutsideHop += 1 }       // only the hop machinery (crouch / air / its landing re-bounce) may have him off the floor
                if off && !inRun { inRun = true; runStart = s.t; airRuns += 1 }
                if off { apex = max(apex, min(s.gap[0], s.gap[1])) }
                if !off && inRun { inRun = false; longest = max(longest, s.t - runStart) }
            }
            let hops = run.rig.brain.idleState.hop
            MotionLog.write(String(format: "IDLE jacks seed %llu: %d reps, %d hops, both-feet-off runs %d, longest %.2f s, apex %.3f H, off outside the hop phases %d, arms %.2f, %.1f s",
                                   seed, run.rig.brain.idleState.reps, hops, airRuns, longest, apex / MotionRig.H, offOutsideHop, run.armW, run.duration))
            XCTAssertEqual(offOutsideHop, 0, "both feet leave the floor only in the hop")
            XCTAssertGreaterThanOrEqual(run.rig.brain.idleState.reps, 4); XCTAssertLessThanOrEqual(run.rig.brain.idleState.reps, 6)
            XCTAssertLessThan(longest, 0.40, "each hop is the small hop")
            XCTAssertLessThanOrEqual(apex, 0.20)
            XCTAssertGreaterThan(run.armW, 0.95, "the stub arms go up")
            XCTAssertGreaterThanOrEqual(airRuns, run.rig.brain.idleState.reps * 2, "a hop per half rep")
        }
    }

    // MARK: run

    /// The run is the walk at runW = 1: speed x1.35, stride x1.2, a 5-6 deg forward lean, a bigger arm sweep.
    func testRunIsTheWalkAtTheThirdGaitPoint() {
        func steady(run: Bool) -> (speed: Float, lean: Float, sweep: Float, stride: Float) {
            let r = MotionRig(game: false)
            r.renderSamples = false
            r.brain.runW = 0
            let target = r.root + SIMD2(0, 7)
            r.brain.request(.goTo(target))
            var phi: [Float] = []
            var tpos: [Float] = [], zs: [SIMD2<Float>] = []
            var lean: [Float] = []
            r.run(1.2)
            r.run(3.2) {
                if run { r.brain.runW = 1 }
                phi.append(r.brain.nubPhi[0]); tpos.append(r.t); zs.append(r.root)
                lean.append(r.sim.bodyPose(iterations: 4).rotation.act(SIMD3<Float>(0, 1, 0)).z)
            }
            let a = zs.count / 3
            let speed = simd_length(zs.last! - zs[a]) / (tpos.last! - tpos[a])
            let sw = (phi[a...].max() ?? 0) - (phi[a...].min() ?? 0)
            // stride = distance per step = speed / step rate
            let rate = r.brain.stepRate * (run ? r.brain.runRateMul : 1)
            return (speed, asinf(max(-1, min(1, lean[a...].reduce(0, +) / Float(lean.count - a)))), sw, speed / rate)
        }
        let w = steady(run: false), n = steady(run: true)
        MotionLog.write(String(format: "IDLE run vs walk: speed %.3f -> %.3f u/s (x%.3f), stride %.3f -> %.3f (x%.3f), lean %.2f -> %.2f deg (+%.2f), arm sweep %.2f -> %.2f (x%.2f)",
                               w.speed, n.speed, n.speed / w.speed, w.stride, n.stride, n.stride / w.stride, w.lean * 57.3, n.lean * 57.3, (n.lean - w.lean) * 57.3, w.sweep, n.sweep, n.sweep / w.sweep))
        // Build B (walk cadence 3.5 -> 3.75, ground speed in whole frames): run / walk speed 1.35 -> 1.25, stride ratio 1.2 -> 1.15 (the run is still +25 % over the walk)
        // (2026-10-18: the walk is x1.143 faster, the run unchanged: ratios 1.25 -> 1.09, 1.15 -> 1.0)
        XCTAssertEqual(n.speed / w.speed, 1.10, accuracy: 0.07)
        XCTAssertEqual(n.stride / w.stride, 1.0, accuracy: 0.07)
        XCTAssertEqual((n.lean - w.lean) * 57.3, 5.5, accuracy: 1.6)
        XCTAssertGreaterThan(n.sweep / w.sweep, 1.1)
    }

    /// With the run blend at exactly 0 the new factors are exactly 1: the arithmetic of the walk is unchanged (the channel log diff against the pre-I1 build
    /// is bit-identical, see READY_I1.md).
    func testRunBlendOffIsExactlyTheWalk() {
        let b = BlobBrain()
        XCTAssertEqual(b.runW, 0); XCTAssertEqual(b.runStrideMul, BlobBrain.walkBoost); XCTAssertEqual(b.runRateMul, 1)      // 2026-10-18: the roam walk's stride is x1.143 (cadence unchanged); the run itself is unchanged
        XCTAssertEqual(b.stepRate * b.runRateMul, b.stepRate); XCTAssertEqual(b.stride * b.runStrideMul, b.stride * BlobBrain.walkBoost)
        XCTAssertEqual(BlobBrain.runLean * b.runW, 0); XCTAssertEqual(1 + BlobBrain.runArmGain * b.runW, 1)
        // a walk with the idle machinery in the build never touches runW
        let r = MotionRig(game: true)
        r.brain.request(.goTo(SIMD2(1.4, 0.4)))
        r.run(5)
        XCTAssertEqual(r.brain.runW, 0); XCTAssertNil(r.brain.idleState.kind)
    }

    // MARK: yielding

    func testYieldsToComeFeedFocusAndTouchWithinPointThreeSeconds() {
        let kinds: [IdleKind] = [.run, .jacks, .sit, .slump, .look, .yawn]
        for kind in kinds {
            for mode in ["come", "feed", "focus", "touch", "blocked"] {
                if mode == "touch" {
                    // a finger lands: the touch path aborts at once
                    let r2 = MotionRig(game: true)
                    r2.brain.seed = 17; r2.brain.idleForced = true
                    XCTAssertTrue(r2.brain.idleStart(kind, r2.sim))
                    r2.run(kind == .jacks ? 2.2 : (kind == .run ? 1.5 : 3.0))
                    let t1 = r2.t
                    var y2: Float?
                    for _ in 0..<40 { r2.tick(touched: true); if r2.brain.idleState.kind == nil && y2 == nil { y2 = r2.t - t1 } }
                    XCTAssertNotNil(y2, "\(kind) / touch: ended"); XCTAssertLessThanOrEqual(y2 ?? 9, 0.3)
                    XCTAssertEqual(r2.brain.armDirW, 0); XCTAssertEqual(r2.brain.runW, 0)
                    continue
                }
                let r = MotionRig(game: true)
                r.brain.seed = 17; r.brain.idleForced = true
                XCTAssertTrue(r.brain.idleStart(kind, r.sim))
                r.run(kind == .jacks ? 2.2 : (kind == .run ? 1.5 : 3.0))
                if r.brain.idleState.kind == nil { continue }          // (a short behaviour that already ended)
                let t0 = r.t
                switch mode {
                case "come": r.brain.request(.come(to: SIMD2(0, 1.4)))
                case "feed": r.brain.requestNow(.eat(at: SIMD2(0.8, -0.2)))
                case "focus": r.brain.autonomy = false; r.brain.idleForced = false
                default: r.brain.idleBlocked = true
                }
                var yielded: Float?
                r.run(0.6, until: { yielded != nil }) {
                    if r.brain.idleState.kind == nil && yielded == nil { yielded = r.t - t0 }
                }
                MotionLog.write(String(format: "IDLE yield %@ / %@: out after %.3f s, activity %@", kind.rawValue, mode, yielded ?? -1, "\(r.brain.activity)"))
                XCTAssertNotNil(yielded, "\(kind) / \(mode): yields")
                XCTAssertLessThanOrEqual(yielded ?? 9, 0.3, "\(kind) / \(mode): yields within 0.3 s")
                if mode == "come" { r.run(0.2); XCTAssertEqual(r.brain.activity, .coming, "Come here starts at once") }
                if mode == "feed" { r.run(0.2); XCTAssertEqual(r.brain.activity, .walking, "Feed starts at once") }
                // and he is back at rest afterwards: nothing of the behaviour is left on him
                XCTAssertEqual(r.brain.armDirW, 0); XCTAssertEqual(r.brain.runW, 0, accuracy: 0.0001); XCTAssertEqual(r.brain.mouthOpen, 0)
            }
        }
    }

    // MARK: mood and scheduler

    func testMoodWeightsSelectTheRightSet() {
        XCTAssertEqual(IdleTable.set(.happy), [.run, .jacks, .look, .zoomies, .slide, .scoot])      // Build B: + the body-led running actions
        XCTAssertEqual(IdleTable.set(.okay), [.sit, .look, .yawn, .scoot, .zoomies, .run])      // 2026-10-20: + zoomies / run (the happy table alone almost never came up)
        XCTAssertEqual(IdleTable.set(.grumpy), [.slump])
        for m in [IdleMood.happy, .okay, .grumpy] {
            var seen: Set<IdleKind> = []
            var last: IdleKind?
            for i in 0..<4000 {
                let k = IdleTable.pick(m, last: last, r: Float(i) / 4000)
                seen.insert(k)
                if k != .wander { if IdleTable.set(m).count > 1 { XCTAssertNotEqual(k, last, "never the same special back to back") }; last = k }
            }
            XCTAssertEqual(seen.subtracting([.wander]), IdleTable.set(m), "\(m): every pick comes from the mood's set")
        }
        // the grumpy sit is the slump, the happy ones never sit
        XCTAssertFalse(IdleTable.set(.happy).contains(.sit)); XCTAssertFalse(IdleTable.set(.happy).contains(.slump))
        XCTAssertFalse(IdleTable.set(.grumpy).contains(.run)); XCTAssertFalse(IdleTable.set(.grumpy).contains(.jacks))
    }

    /// A long roam: the scheduler starts specials of the mood's set only, 15...30 s apart (start to start, plus the first 9 s), never the same one back to back.
    func testSchedulerCadenceAndCooldown() {
        for mood in [IdleMood.happy, .okay, .grumpy] {
            let r = MotionRig(game: true)
            r.renderSamples = false
            r.brain.autonomy = true
            r.brain.seed = 99
            r.brain.idleMood = mood
            var starts: [(Float, IdleKind)] = []
            var prev: IdleKind?
            var acts: Set<BlobActivity> = []
            r.run(200) {
                let k = r.brain.idleState.kind
                if k != nil && prev == nil { starts.append((r.t, k!)) }
                if let k, k == .stumble, starts.last?.1 == .run { }
                prev = k
                acts.insert(r.brain.activity)
            }
            let kinds = starts.map { $0.1 }
            let gaps = zip(starts.dropFirst(), starts).map { $0.0.0 - $0.1.0 }
            MotionLog.write("IDLE roam \(mood): starts \(starts.map { String(format: "%.0f:%@", $0.0, $0.1.rawValue) }) gaps \(gaps.map { String(format: "%.0f", $0) })")
            XCTAssertGreaterThanOrEqual(starts.count, 3, "\(mood): a special now and then")
            XCTAssertLessThanOrEqual(starts.count, 14, "\(mood): not constantly")
            let allowed = IdleTable.set(mood).union(mood == .happy ? [.stumble] : [])
            for k in kinds { XCTAssertTrue(allowed.contains(k), "\(mood): \(k) is not in its set") }
            for g in gaps { XCTAssertGreaterThanOrEqual(g, 10, "\(mood): cooldown between specials"); XCTAssertLessThanOrEqual(g, 75) }
            if IdleTable.set(mood).count > 1 { for (a, b) in zip(kinds, kinds.dropFirst()) where a != .stumble && b != .stumble { XCTAssertNotEqual(a, b, "\(mood): same behaviour back to back") } }
            XCTAssertFalse(r.sim.hasNonFinite())
        }
    }

    // MARK: perf

    func testBrainTickStaysUnderBudget() {
        for kind in [IdleKind.run, .jacks, .sit, .look, .yawn] {
            let r = MotionRig(game: true)
            r.renderSamples = false
            r.brain.seed = 4; r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(kind, r.sim))
            r.run(kind == .sit ? 2.5 : 1.2)
            var tick = 0.0, n = 0
            for _ in 0..<240 {
                let a = CACurrentMediaTime()
                r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
                tick += CACurrentMediaTime() - a; n += 1
                r.sim.step()
            }
            let us = tick / Double(n) * 1e6
            MotionLog.write(String(format: "IDLE perf %@: brain.tick %.1f us per step", kind.rawValue, us))
            XCTAssertLessThan(us, 1500, "\(kind): the brain stays under budget")
        }
    }
}
