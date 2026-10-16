//
//  MotionFootRenderTests.swift
//  The moving feet are drawn as closed rigid beans (FootBean, via Skinner.beanPos; the sim foot is only a 0.1 u slab and folds into a fin when lifted).
//  RIGID: while the beans are out their vertices keep their mutual distances (no shear); SLAB: no slab tet under a foot ever inverts;
//  POP: the swap blends in / out (< 2 mm at the first and last active frame); REST: nothing is overridden at rest; HYSTERESIS: one swap per action.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionFootRenderTests: XCTestCase {
    private struct Slab {
        let tets: [Int]            // tet indices touching a foot sole particle
        let rest: [Float]
        init(_ sim: SoftBody) {
            var foot = Set<Int>()
            for a in sim.appendages where a.kind == .foot { for p in a.particles { foot.insert(p) } }
            var t: [Int] = [], r: [Float] = []
            for k in 0..<(sim.tets.count / 4) {
                let i = (0..<4).map { Int(sim.tets[4 * k + $0]) }
                guard i.contains(where: { foot.contains($0) }) else { continue }
                t.append(k); r.append(Slab.vol({ sim.restPosition($0) }, i))
            }
            tets = t; rest = r
        }
        static func vol(_ f: (Int) -> SIMD3<Float>, _ i: [Int]) -> Float {
            let a = f(i[0]), b = f(i[1]), c = f(i[2]), d = f(i[3])
            return simd_dot(b - a, simd_cross(c - a, d - a)) / 6
        }
        /// min current / rest volume over the slab tets
        func minRatio(_ sim: SoftBody) -> Float {
            var m = Float.infinity
            for (n, k) in tets.enumerated() {
                let i = (0..<4).map { Int(sim.tets[4 * k + $0]) }
                let v = Slab.vol({ SIMD3(sim.x[3 * $0], sim.x[3 * $0 + 1], sim.x[3 * $0 + 2]) }, i)
                m = min(m, v / rest[n])
            }
            return m
        }
    }

    func testNoOverrideAtRest() {
        for game in [false, true] {
            let r = MotionRig(game: game)
            r.run(1.0)
            r.render()
            XCTAssertFalse(r.skinner.beansActive, "no bean override at rest (game \(game))")
            XCTAssertEqual(r.skinner.beanBlend, 0)
            XCTAssertTrue(r.skinner.overrideVertices.isEmpty)
            // an idle render is the plain skinning: re-skinning with the (empty) override gives identical positions
            var a = r.dyn; r.render()
            XCTAssertEqual(a, r.dyn)
            a = []
        }
    }

    /// Run a scenario, calling `each` after every step with the rig; returns the rig.
    private func drive(_ r: MotionRig, seconds: Float, until: (() -> Bool)? = nil, each: @escaping () -> Void) {
        r.run(seconds, until: until) { r.render(); each() }
    }

    /// Bean vertex ids of side s and their local (foot-frame) positions.
    private func beanPairs(_ r: MotionRig, _ s: Int) -> [(Int, Int, Float)] {
        var out: [(Int, Int, Float)] = []
        let n = FootBean.vertexCount
        for k in 0..<80 {
            let a = (k * 37 + 3) % n, b = (k * 59 + 11) % n
            if a == b { continue }
            let d = FootBean.localF[a] - FootBean.localF[b]
            out.append((Int(r.bean[s][a]), Int(r.bean[s][b]), simd_length(d)))
        }
        return out
    }

    func testBeanIsRigidWhileOut() {
        // distances between bean vertices equal their local distances (1e-3 u) at every fully blended frame, in every action that moves the feet
        let cases: [(String, Bool, (MotionRig) -> Void)] = [
            ("walk", false, { $0.brain.request(.goTo($0.root + SIMD2(0, 2.2))) }),
            ("march", false, { $0.brain.startStepping(seconds: 3, sim: $0.sim) }),
            ("turn", false, { $0.brain.startTurn(to: $0.poseYaw + 2.4, sim: $0.sim) }),
            ("wave", true, { $0.brain.request(.wave) }),
            ("walk game", true, { $0.brain.request(.goTo(SIMD2(1.6, 0.4))) })]
        for (name, game, start) in cases {
            let r = MotionRig(game: game)
            r.renderSamples = false
            start(r)
            let pairs = [beanPairs(r, 0), beanPairs(r, 1)]
            var worst: Float = 0, frames = 0, lifted = 0
            r.run(7) {
                guard r.skinner.beansActive, r.skinner.beanBlend > 0.999 else { return }
                r.render()
                for s in 0..<2 {
                    for p in pairs[s] {
                        let a = SIMD3(r.dyn[6 * p.0], r.dyn[6 * p.0 + 1], r.dyn[6 * p.0 + 2]), b = SIMD3(r.dyn[6 * p.1], r.dyn[6 * p.1 + 1], r.dyn[6 * p.1 + 2])
                        worst = max(worst, abs(simd_distance(a, b) - p.2))
                    }
                }
                frames += 1
                if r.renderedFootGap(0) > 0.07 || r.renderedFootGap(1) > 0.07 { lifted += 1 }
            }
            MotionLog.write(String(format: "FOOTRENDER rigid %@: worst bean distance drift %.5f u over %d fully blended frames (%d with a foot lifted)", name, worst, frames, lifted))
            XCTAssertGreaterThan(frames, 30, "\(name): the beans were out")
            XCTAssertLessThan(worst, 1e-3, "\(name): the bean stays a rigid bean")
        }
    }

    /// While the beans are out the planted foot sits on the floor (sole gap within a few mm) and the bean is never below it.
    func testPlantedBeanSitsOnTheFloor() {
        for (name, game) in [("walk studio", false), ("walk game", true)] {
            let r = MotionRig(game: game)
            r.renderSamples = false
            r.brain.request(.goTo(game ? SIMD2(1.6, 0.4) : r.root + SIMD2(1.4, 0.6)))
            var worstLow: Float = 0, frames = 0
            var started = false
            r.run(8, until: { started && r.brain.activity == .idle }) {
                if r.brain.activity == .walking { started = true }
                guard r.skinner.beansActive, r.skinner.beanBlend > 0.999 else { return }
                r.render()
                var gap = Float.infinity
                for s in 0..<2 { gap = min(gap, r.renderedFootGap(s)) }
                worstLow = min(worstLow, gap)
                if gap < 0.01 { frames += 1 }
            }
            MotionLog.write(String(format: "FOOTRENDER planted %@: lowest bean vertex %.4f u relative to the floor, %d stance frames", name, worstLow, frames))
            XCTAssertGreaterThan(frames, 50, "\(name): a bean was planted on the floor for most of the walk")
            XCTAssertGreaterThan(worstLow, -0.004, "\(name): the bean sinks through the floor")
        }
    }

    func testSlabTetsNeverInvert() {
        let cases: [(String, Bool, (MotionRig) -> Void, Float)] = [
            ("walk", false, { $0.brain.request(.goTo($0.root + SIMD2(0, 2.4))) }, 7),
            ("march", false, { $0.brain.startStepping(seconds: 3, sim: $0.sim) }, 5),
            ("turn", false, { $0.brain.startTurn(to: $0.poseYaw + 2.4, sim: $0.sim) }, 3),
            ("wave", true, { $0.brain.request(.wave) }, 4),
            ("hop", false, { $0.brain.startHopPlay(sim: $0.sim) }, 3),
            ("Call", true, { $0.brain.requestNow(.come(to: SIMD2(0, 1.4))) }, 12)]
        for (name, game, start, secs) in cases {
            let r = MotionRig(game: game)
            r.renderSamples = false
            let slab = Slab(r.sim)
            start(r)
            var worst = Float.infinity
            r.run(secs) { worst = min(worst, slab.minRatio(r.sim)) }
            MotionLog.write(String(format: "FOOTRENDER slab %@: min tet volume ratio %.3f over %d slab tets", name, worst, slab.tets.count))
            XCTAssertGreaterThan(worst, 0.05, "\(name): a slab tet under a foot inverted or collapsed")
        }
    }

    /// The swap is a blend: its first and last active frame move no vertex by 2 mm or more (no pop), and the beans swap in once per action.
    func testSwapFadesInAndOut() {
        let cases: [(String, (MotionRig) -> Void)] = [
            ("walk", { $0.brain.request(.goTo($0.root + SIMD2(0, 2.0))) }),
            ("march", { $0.brain.startStepping(seconds: 3, sim: $0.sim) }),
            ("hop", { $0.brain.startHopPlay(sim: $0.sim) })]
        for (name, start) in cases {
            let r = MotionRig(game: false)
            r.renderSamples = false
            start(r)
            var disp: [Float] = [], onFlags: [Bool] = []
            r.run(6) {
                r.render()
                let on = r.skinner.beansActive
                var m: Float = 0
                if on {
                    // displacement the swap adds to the plain skinning, over every non-bean vertex (the retracting embedded foot / belly skin);
                    // the bean vertices themselves jump between two hidden states (a ball inside the belly / the inset bean inside the embedded
                    // foot, both strictly inside the body: FootBeanTests) when they switch on and off
                    let with = r.dyn
                    let keep = r.skinner.beanBlend
                    r.skinner.beanBlend = 0
                    r.render()
                    let plain = r.dyn
                    r.skinner.beanBlend = keep
                    let beanLo = Int(r.bean[0][0]), beanHi = Int(r.bean[1].last!)
                    for v in 0..<(with.count / 6) where v < beanLo || v > beanHi {
                        let o = 6 * v
                        m = max(m, simd_distance(SIMD3(with[o], with[o + 1], with[o + 2]), SIMD3(plain[o], plain[o + 1], plain[o + 2])))
                    }
                }
                disp.append(m); onFlags.append(on)
            }
            var firstFrame: Float = 0, lastFrame: Float = 0, runs = 0, maxFrame: Float = 0
            var i = 0
            while i < onFlags.count {
                if onFlags[i] {
                    var j = i
                    while j + 1 < onFlags.count && onFlags[j + 1] { j += 1 }
                    firstFrame = max(firstFrame, disp[i]); lastFrame = max(lastFrame, disp[j])
                    maxFrame = max(maxFrame, disp[i...j].max() ?? 0)
                    runs += 1; i = j + 1
                } else { i += 1 }
            }
            MotionLog.write(String(format: "FOOTRENDER pop %@: %d bean runs, displacement the swap adds at the first active frame %.4f u, at the last %.4f u, max over the run %.4f u", name, runs, firstFrame, lastFrame, maxFrame))
            XCTAssertGreaterThanOrEqual(runs, 1)
            XCTAssertLessThan(firstFrame, 0.002, "\(name): the swap pops in")
            XCTAssertLessThan(lastFrame, 0.002, "\(name): the swap pops out")
            XCTAssertEqual(runs, 1, "\(name): one swap per action")
        }
    }

    /// A step in place is ONE action: the beans swap in once at its start and out once after the last step (never per step), and they stay out
    /// through every pause between steps.
    func testBeansSwapOncePerStepInPlaceSequence() {
        for game in [false, true] {
            let r = MotionRig(game: game)
            r.renderSamples = false
            r.run(1.0)
            XCTAssertFalse(r.skinner.beansActive)
            r.brain.startStepping(seconds: 4, sim: r.sim)
            var transitions = 0, was = false, outFrames = 0, firstOn: Float = -1, lastOn: Float = -1
            r.run(10) {
                let on = r.skinner.beansActive
                if on != was { transitions += 1; was = on }
                if on { outFrames += 1; if firstOn < 0 { firstOn = r.t }; lastOn = r.t }
            }
            MotionLog.write(String(format: "FOOTRENDER hysteresis (game %d): %d on/off transitions during a 4 s step-in-place, beans out %.2f s ... %.2f s, swaps counted by the brain %d", game ? 1 : 0, transitions, firstOn, lastOn, r.brain.beanSwapCount))
            XCTAssertEqual(transitions, 2, "game \(game): the beans swap in once and out once")
            XCTAssertEqual(r.brain.beanSwapCount, 1)
            XCTAssertFalse(r.skinner.beansActive, "game \(game): beans back in after the action")
        }
    }

    /// Root cause of the hop "face-plant": the stiff world targets that pin the stepping feet were still active when the hop took over the
    /// body (the hop branch returns before `driveLimbs`), so the soles stayed pinned at the old spot while he squashed and travelled and the body
    /// pitched over them. The brain now releases them when the hop starts; this test keeps the old pins alive to show what they would do.
    func testStalePinnedFeetWouldTipTheHop() {
        func run(pinned: Bool) -> (tilt: Float, fwd: Float, targetsAtStart: Int) {
            let r = MotionRig(game: false)
            r.renderSamples = false
            r.brain.request(.goTo(r.root + SIMD2(0, 0.7)))
            r.run(3.0, until: { r.brain.activity == .idle && r.t > 1.5 })
            r.brain.startStepping(seconds: 0.6, sim: r.sim)
            r.run(0.5)
            let stale = r.sim.targets
            r.brain.startHopPlay(sim: r.sim, distance: 0.45)
            var tilt: Float = 0, fwd: Float = 0
            var started = -1
            for i in 0..<150 {
                r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
                if i == 0 { started = r.sim.targets.count }
                if pinned && i < 40 { r.sim.targets = stale }
                r.sim.step()
                let p = r.sim.bodyPose(iterations: 4)
                tilt = max(tilt, p.tilt); fwd = max(fwd, p.rotation.act(SIMD3<Float>(0, 1, 0)).z)
            }
            return (tilt, fwd, started)
        }
        let ok = run(pinned: false), bad = run(pinned: true)
        MotionLog.write(String(format: "FOOTRENDER hop with released feet: max tilt %.1f deg, forward lean %.1f deg (targets at hop start %d); with the old pins kept: tilt %.1f deg, forward lean %.1f deg",
                               ok.tilt * 57.3, asinf(ok.fwd) * 57.3, ok.targetsAtStart, bad.tilt * 57.3, asinf(bad.fwd) * 57.3))
        XCTAssertEqual(ok.targetsAtStart, 0, "the hop starts with no pinned foot targets")
        XCTAssertLessThan(ok.tilt * 57.3, 12)
        XCTAssertGreaterThan(bad.tilt, ok.tilt, "pinned soles drag the body over")
    }
}
