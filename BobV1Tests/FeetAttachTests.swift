//
//  FeetAttachTests.swift
//  Short cute feet that stay under him (user, 2026-10-17: "cute short feet not balls ... lean into his short arms and feet and his body moves"):
//  over every scripted move, in every frame where the foot beans are out, in the fitted body frame (rest coordinates, sole = 0):
//    LOW     the lowest point of each foot (sole) never rises more than `maxSoleRise` and the foot centre never above 0.2 H (a lifted foot
//            never rides up onto or in front of the belly: it stays in the bottom band of the silhouette);
//    UNDER   the foot centre stays within `maxRadius` of the body axis (roughly under the body footprint);
//    ATTACHED  part of the foot is well inside the egg (overlap, no gap between foot and belly).
//  Also: the bean IS the rest foot when planted (same shape, no swap pop), it morphs smoothly to a ball when lifted, and the mesh-build winding fix
//  leaves the bean triangles intact.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FeetAttachTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let maxSoleRise: Float = 0.12                 // body-frame sole height (0.09 H); the hop / jacks tuck is the largest
    static let maxCentreHeight: Float = 0.2 * Float(BobForm.top)
    static let maxRadius: Float = 0.52                  // foot centre from the body axis (the underside radius is ~0.4 at the rim, the arm-free footprint ~0.5)
    static let minOverlap: Float = -0.02                // the deepest foot vertex is at least this far inside the egg

    struct FootFrame { var soleRise: Float, centreHeight: Float, radius: Float, overlap: Float
        /// Embedded foot only: its extent (largest vertex distance from the foot's mean) over the rest extent. Squash barely changes it; a foot left on the
        /// floor while the body moves on stretches the slab into a tongue (2026-10-21: 1.9 x). 0 for bean frames.
        var stretch: Float = 0 }
    /// Worst of both feet this frame; nil while the beans are not out.
    static func footFrame(_ r: MotionRig) -> FootFrame? {
        guard r.skinner.beansActive, r.skinner.beanBlend > 0.05 else { return nil }
        r.render()
        let pose = r.sim.bodyPose(iterations: 4), c0 = r.sim.restCentroid
        var f = FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity)
        for s in 0..<2 {
            var lo = Float.infinity, cx: Float = 0, cy: Float = 0, cz: Float = 0, deepest = Float.infinity
            for id in r.bean[s] {
                let o = 6 * Int(id)
                let q = c0 + pose.rotation.inverse.act(SIMD3(r.dyn[o], r.dyn[o + 1], r.dyn[o + 2]) - pose.centroid)
                lo = min(lo, q.y); cx += q.x; cy += q.y; cz += q.z
                deepest = min(deepest, Float(BobForm.bodySDF(SIMD3(Double(abs(q.x)), Double(q.y), Double(q.z)))))
            }
            let n = Float(r.bean[s].count)
            f.soleRise = max(f.soleRise, lo); f.centreHeight = max(f.centreHeight, cy / n)
            f.radius = max(f.radius, hypotf(cx / n, cz / n)); f.overlap = max(f.overlap, deepest)
        }
        return f
    }
    /// The foot that is actually DRAWN this frame (2026-10-21, "when he rolled randomly his feet came off again"): the beans while they are out, else the
    /// embedded foot's render vertices (`MotionRig.core`). `footFrame` is nil while the beans are in, so a move that never puts them out (the rolls, the
    /// flip, the flop) was never measured at all. Same body-frame metrics; `beans` says which foot was measured.
    static func drawnFootFrame(_ r: MotionRig) -> FootFrame {
        r.render()
        let beans = r.skinner.beansActive && r.skinner.beanBlend > 0.05
        let pose = r.sim.bodyPose(iterations: 4), c0 = r.sim.restCentroid
        var f = FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity)
        for s in 0..<2 {
            let ids = beans ? r.bean[s] : r.core[s]
            guard !ids.isEmpty else { continue }
            var lo = Float.infinity, cx: Float = 0, cy: Float = 0, cz: Float = 0, deepest = Float.infinity
            var wm = SIMD3<Float>.zero
            for id in ids {
                let o = 6 * Int(id)
                let p = SIMD3(r.dyn[o], r.dyn[o + 1], r.dyn[o + 2])
                wm += p
                let q = c0 + pose.rotation.inverse.act(p - pose.centroid)
                lo = min(lo, q.y); cx += q.x; cy += q.y; cz += q.z
                deepest = min(deepest, Float(BobForm.bodySDF(SIMD3(Double(abs(q.x)), Double(q.y), Double(q.z)))))
            }
            let n = Float(ids.count)
            f.soleRise = max(f.soleRise, lo); f.centreHeight = max(f.centreHeight, cy / n)
            f.radius = max(f.radius, hypotf(cx / n, cz / n)); f.overlap = max(f.overlap, deepest)
            if !beans {
                wm /= n
                var ext: Float = 0
                for id in ids { let o = 6 * Int(id); ext = max(ext, simd_distance(SIMD3(r.dyn[o], r.dyn[o + 1], r.dyn[o + 2]), wm)) }
                f.stretch = max(f.stretch, ext / coreRestExtent[s])
            }
        }
        return f
    }
    static func accumulate(_ w: inout FootFrame, _ f: FootFrame) {
        w.soleRise = max(w.soleRise, f.soleRise); w.centreHeight = max(w.centreHeight, f.centreHeight)
        w.radius = max(w.radius, f.radius); w.overlap = max(w.overlap, f.overlap); w.stretch = max(w.stretch, f.stretch)
    }
    static func check(_ name: String, _ w: FootFrame, frames: Int, throwing: Bool = false, core: Bool = false) {
        MotionLog.write(String(format: "FEETATTACH %@: %d %@ frames, max sole rise %.3f, max foot-centre height %.3f (limit %.3f), max radius %.3f, worst overlap %.3f, stretch %.2f", name, frames, core ? "embedded-foot" : "bean", w.soleRise, w.centreHeight, maxCentreHeight, w.radius, w.overlap, w.stretch))
        guard frames > 0 else { return }
        if core { XCTAssertLessThanOrEqual(w.stretch, maxCoreStretch, "\(name): the foot is stretched away from the body (a tongue)") }
        XCTAssertLessThanOrEqual(w.soleRise, maxSoleRise, "\(name): a foot is lifted too high")
        XCTAssertLessThanOrEqual(w.centreHeight, maxCentreHeight, "\(name): a foot rides up onto the belly")
        XCTAssertLessThanOrEqual(w.radius, throwing ? 0.7 : maxRadius, "\(name): a foot is not under the body")
        XCTAssertLessThanOrEqual(w.overlap, core ? minCoreOverlap : minOverlap, "\(name): a foot is not fused to the body (gap)")
    }

    struct Move {
        let name: String, game: Bool, seconds: Float, expectBeans: Bool
        let start: (MotionRig) -> Void
        /// Per frame, after the step (the Ears reactions are driven from outside the brain).
        var each: ((MotionRig) -> Void)? = nil
    }
    /// The Ears moves: a reactor per rig, ticked every frame (BlobBrain+Ears.swift).
    nonisolated(unsafe) static var earsReactors: [ObjectIdentifier: EarsReactor] = [:]
    static func ears(_ r: MotionRig, _ e: EarEvent) {
        let re = EarsReactor(); earsReactors[ObjectIdentifier(r)] = re
        re.handle(e, jellies: [EarsReactor.Jelly(id: 0, brain: r.brain, sim: r.sim)], now: Double(r.t))
    }
    static func earsTick(_ r: MotionRig) {
        earsReactors[ObjectIdentifier(r)]?.tick(jellies: [EarsReactor.Jelly(id: 0, brain: r.brain, sim: r.sim)], dt: r.sim.stepDt, now: Double(r.t))
    }
    /// The second decor batch and soccer: every interaction (name, piece, where, move, seconds, beans expected, forced soccer mode, a goal placed at).
    static let batch2Decor: [(String, DecorKind, SIMD2<Float>, IdleKind, Float, Bool, Int?, SIMD2<Float>?)] = [
        ("decor2: sit on the pouf", .pouf, SIMD2(1.3, 0.9), .decorSit, 26, true, nil, nil),
        ("decor2: sit in the armchair", .armchair, SIMD2(1.1, 0.9), .decorSit, 26, true, nil, nil),
        ("decor2: sit on the loveseat", .loveseat, SIMD2(1.1, 0.9), .decorSit, 26, true, nil, nil),
        ("decor2: sit on a dining stool", .diningset, SIMD2(1.1, 0.9), .decorSit, 26, true, nil, nil),
        ("decor2: rock in the rocking chair", .rockingchair, SIMD2(1.1, 0.9), .decorSit, 26, true, nil, nil),
        ("decor2: sway on the swing", .swing, SIMD2(1.1, 0.9), .decorSit, 28, true, nil, nil),
        ("decor2: peek at the bookshelf", .bookshelf, SIMD2(1.1, 0.9), .decorPeek, 14, false, nil, nil),
        ("decor2: peek in the wardrobe", .wardrobe, SIMD2(0.0, -0.8), .decorPeek, 14, false, nil, nil),
        ("decor2: boop the duck", .duck, SIMD2(1.1, 0.9), .decorBoop, 14, false, nil, nil),
        ("decor2: boop the drum", .drum, SIMD2(1.1, 0.9), .decorBoop, 14, false, nil, nil),
        ("decor2: boop the monstera", .monstera, SIMD2(1.1, 0.9), .decorBoop, 14, false, nil, nil),
        ("decor2: boop the spinning top", .spintop, SIMD2(1.1, 0.9), .decorBoop, 16, false, nil, nil),
        ("decor2: kick the block tower", .blocks, SIMD2(0.9, 0.9), .decorKick, 14, false, nil, nil),
        ("decor2: kick the toy car", .toycar, SIMD2(0.9, 0.9), .decorKick, 14, false, nil, nil),
        ("decor2: kick the yarn ball", .yarnball, SIMD2(0.9, 0.9), .decorKick, 14, false, nil, nil),
        ("decor2: climb the slide, sit, ride, exit", .slide, SIMD2(1.0, 1.2), .decorSlide, 30, true, nil, nil),
        // soccer (BlobBrain+Soccer.swift): the stomp kick, a dribble to the goal's kick spot and the shot, the shot and the celebration bounce, a stuck ball's rescue
        ("soccer: stomp-kick the ball", .soccerball, SIMD2(0.9, 0.9), .soccerKick, 16, true, 0, nil),
        ("soccer: dribble the ball to the goal and shoot", .soccerball, SIMD2(0.9, 1.4), .soccerKick, 34, true, 1, SIMD2(0.0, -1.6)),
        ("soccer: shoot at the goal and celebrate", .soccerball, SIMD2(0.5, 0.1), .soccerKick, 22, true, 2, SIMD2(0.0, -1.6)),
        ("soccer: dribble a stuck ball back to open floor", .soccerball, SIMD2(-1.4, -2.2), .soccerKick, 30, true, 3, nil),
    ]
    static let moves: [Move] = batch2Decor.map { d in
        Move(name: d.0, game: true, seconds: d.4, expectBeans: d.5, start: { $0.brain.soccerModeForce = d.6; decorStart($0, d.1, d.2, d.3, goal: d.7) })
    } + [
        Move(name: "walk", game: false, seconds: 7, expectBeans: true, start: { $0.brain.request(.goTo($0.root + SIMD2(0, 2.4))) }),
        Move(name: "walk (game)", game: true, seconds: 7, expectBeans: true, start: { $0.brain.request(.goTo(SIMD2(1.6, 0.4))) }),
        Move(name: "run", game: true, seconds: 6, expectBeans: true, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.run, $0.sim) }),
        Move(name: "zoomies", game: true, seconds: 8, expectBeans: true, start: { $0.brain.seed = 11; $0.brain.idleForced = true; _ = $0.brain.idleStart(.zoomies, $0.sim) }),
        Move(name: "belly slide", game: true, seconds: 9, expectBeans: true, start: { $0.brain.seed = 11; $0.brain.idleForced = true; _ = $0.brain.idleStart(.slide, $0.sim) }),
        Move(name: "hop-scoot", game: true, seconds: 5, expectBeans: true, start: { $0.brain.seed = 11; $0.brain.idleForced = true; _ = $0.brain.idleStart(.scoot, $0.sim) }),
        Move(name: "jumping jacks", game: true, seconds: 8, expectBeans: true, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.jacks, $0.sim) }),
        Move(name: "sit", game: true, seconds: 5, expectBeans: true, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.sit, $0.sim) }),
        Move(name: "sleep: roll onto the back and up again", game: true, seconds: 16, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.sleep, $0.sim); $0.brain.sleep.hold = 2 }),
        Move(name: "sleep: hand-hold", game: true, seconds: 18, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.sleep, $0.sim); $0.brain.sleep.hold = 5; $0.brain.sleep.holdForce = true }),
        Move(name: "sleep: hand-hold + cuddle lean", game: true, seconds: 18, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.sleep, $0.sim); $0.brain.sleep.hold = 5; $0.brain.sleep.holdForce = true; $0.brain.sleep.mode = .cuddle }),
        Move(name: "antic: spin after his tail", game: true, seconds: 6, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.tail, $0.sim) }),
        Move(name: "antic: flop", game: true, seconds: 4, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.flop, $0.sim) }),
        Move(name: "antic: happy bounce", game: true, seconds: 4, expectBeans: true, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.bounce, $0.sim) }),
        Move(name: "Lavender: flap-hop", game: true, seconds: 6, expectBeans: true, start: { $0.brain.feature = .wings; $0.brain.idleForced = true; _ = $0.brain.idleStart(.flapHop, $0.sim) }),
        Move(name: "antic: roll", game: true, seconds: 3, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.roll, $0.sim) }),
        Move(name: "antic: window", game: true, seconds: 9, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.window, $0.sim) }),
        Move(name: "antic: stretch", game: true, seconds: 5, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.stretch, $0.sim) }),
        // the "too bland" round (2026-10-20): mid-walk flourishes, the jump for joy and the reaction moves (standalone; the mid-walk versions are in LivelyLabTests)
        Move(name: "flourish: skip-hop", game: true, seconds: 4, expectBeans: true, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.skipHop, $0.sim) }),
        Move(name: "flourish: hopscotch", game: true, seconds: 5, expectBeans: true, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.hopscotch, $0.sim) }),
        Move(name: "flourish: mid-leg spin", game: true, seconds: 4, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.legSpin, $0.sim) }),
        Move(name: "flourish: bounce-trot", game: true, seconds: 6, expectBeans: true, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.trot, $0.sim) }),
        Move(name: "flourish: stop and look", game: true, seconds: 6, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.stopLook, $0.sim) }),
        Move(name: "jump for joy", game: true, seconds: 3, expectBeans: true, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.joy, $0.sim) }),
        Move(name: "reaction: giggle", game: true, seconds: 3, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.giggle, $0.sim) }),
        Move(name: "reaction: startle hop", game: true, seconds: 3, expectBeans: true, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.startle, $0.sim, goal: $0.root - SIMD2(0, 0.25)) }),
        Move(name: "flourish: roll along the leg", game: true, seconds: 5, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.rollTrip, $0.sim) }),
        Move(name: "big sigh", game: true, seconds: 6, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.sigh, $0.sim) }),
        Move(name: "grumpy hmph puff", game: true, seconds: 3, expectBeans: false, start: { $0.brain.idleForced = true; _ = $0.brain.idleStart(.hmph, $0.sim) }),
        Move(name: "march", game: false, seconds: 5, expectBeans: true, start: { $0.brain.startStepping(seconds: 3, sim: $0.sim) }),
        Move(name: "turn", game: false, seconds: 3.5, expectBeans: true, start: { $0.brain.startTurn(to: $0.poseYaw + 2.4, sim: $0.sim) }),
        Move(name: "wave", game: true, seconds: 4, expectBeans: true, start: { $0.brain.request(.wave) }),
        Move(name: "hop", game: false, seconds: 3, expectBeans: true, start: { $0.brain.startHopPlay(sim: $0.sim) }),
        Move(name: "call", game: true, seconds: 12, expectBeans: true, start: { $0.brain.requestNow(.come(to: SIMD2(0, 1.4))) }),
        Move(name: "flip", game: true, seconds: 3, expectBeans: false, start: { $0.brain.startFlip(sim: $0.sim) }),
        Move(name: "faceplant", game: true, seconds: 4, expectBeans: false, start: { $0.brain.startFlip(sim: $0.sim, fail: true) }),
        // decor (store part B): the walk to the piece and what he does with it; installed in the field for the run (the tests clear it afterwards)
        Move(name: "decor: hop onto the beanbag, sit on top, hop off", game: true, seconds: 26, expectBeans: true, start: { decorStart($0, .beanbag, SIMD2(1.1, 0.9), .decorSit) }),
        Move(name: "decor: sit on a cushion", game: true, seconds: 26, expectBeans: true, start: { decorStart($0, .cushion, SIMD2(-1.1, 0.9), .decorSit) }),
        Move(name: "decor: boop the plant", game: true, seconds: 14, expectBeans: false, start: { decorStart($0, .plant, SIMD2(1.1, 0.9), .decorBoop) }),
        Move(name: "decor: kick the ball", game: true, seconds: 14, expectBeans: false, start: { decorStart($0, .ball, SIMD2(0.9, 0.9), .decorKick) }),
        Move(name: "decor: hop on the mat", game: true, seconds: 16, expectBeans: true, start: { decorStart($0, .bouncymat, SIMD2(-1.1, 0.9), .decorHop) }),
        Move(name: "decor: peek in the toy box", game: true, seconds: 14, expectBeans: false, start: { decorStart($0, .toybox, SIMD2(1.1, 0.9), .decorPeek) }),
        // Ears (sound reactions): the beat dance with its hop (beat 8) and spin (beat 16), the startle flinch + hop + turn, the giggle
        Move(name: "ears dance", game: true, seconds: 12, expectBeans: true, start: { ears($0, .musicStarted(EarBeat(bpm: 120, anchor: Double($0.t), strength: 3))) }, each: earsTick),
        Move(name: "ears startle", game: true, seconds: 4, expectBeans: true, start: { ears($0, .bang(level: 0.8)) }, each: earsTick),
        Move(name: "ears giggle", game: true, seconds: 3, expectBeans: false, start: { ears($0, .heard(.laugh)) }, each: earsTick),
    ]
    /// Puts one piece in the field (and a mini goal at `goal`) and starts the Jelly's behaviour with it.
    static func decorStart(_ r: MotionRig, _ kind: DecorKind, _ at: SIMD2<Float>, _ move: IdleKind, goal: SIMD2<Float>? = nil) {
        var placed = [PlacedDecor(uid: 7, kind: kind, x: at.x, z: at.y)]
        if let goal { placed.append(PlacedDecor(uid: 8, kind: .minigoal, x: goal.x, z: goal.y)) }
        DecorField.shared.clear()          // (the last row's piece, uid 7 too, may still be rolling: `set` would keep its motion and the pick would skip a moving ball)
        DecorField.shared.set(placed)
        SoccerState.shared.reset()
        if move == .soccerKick, r.brain.soccerModeForce == 3 { DecorField.shared.tick(dt: 0); SoccerState.shared.setStuck(7, SoccerTuning.stuckAfter) }          // (a stuck ball: the 20 s have passed)
        r.brain.idleForced = true
        let ok = r.brain.idleStart(move, r.sim)
        if move == .soccerKick {
            MotionLog.write("DECORSTART soccer mode \(r.brain.soccerModeForce ?? -1) started \(ok) at (\(r.brain.px), \(r.brain.pz)) occupant \(String(describing: DecorField.shared.occupant[7])) ball \(DecorField.shared.anim[7]?.pos ?? .zero) stand \(String(describing: r.brain.soccerStand(DecorField.shared.foot(7)!, from: r.brain.position))) plan \(r.brain.soccerPlan.mode) kind \(String(describing: r.brain.idleState.kind)) openFloor \(String(describing: DecorField.shared.nearestOpenFloor(to: at)))")
            XCTAssertTrue(ok, "soccer mode \(r.brain.soccerModeForce ?? -1) starts")
        }
    }

    /// The embedded foot (beans in) is measured with the same limits; its overlap is the slab top against the egg: at rest ~-0.04, it may ride a hair
    /// out under a hard squash or a fast tip (the fitted frame lags the deformed body), never more than this. A foot left on the floor while the body
    /// rolls away (2026-10-21) reads +0.16.
    static let minCoreOverlap: Float = 0.06
    /// Embedded foot: extent over rest extent. The hop / jacks tuck and the sleep lie read up to ~1.15; the roll's tongue 1.9.
    static let maxCoreStretch: Float = 1.3
    /// Rest extent of each embedded foot (largest vertex distance from its mean, rest render mesh).
    static let coreRestExtent: [Float] = {
        let rm = MotionRig.renderMesh
        let r = MotionRig(game: true, settle: 0)
        return (0..<2).map { s in
            let ids = r.core[s]
            guard !ids.isEmpty else { return 1 }
            var m = SIMD3<Float>.zero
            for id in ids { let o = 3 * Int(id); m += SIMD3(rm.rest[o], rm.rest[o + 1], rm.rest[o + 2]) }
            m /= Float(ids.count)
            var ext: Float = 0
            for id in ids { let o = 3 * Int(id); ext = max(ext, simd_distance(SIMD3(rm.rest[o], rm.rest[o + 1], rm.rest[o + 2]), m)) }
            return ext > 0 ? ext : 1
        }
    }()

    func testFeetStayLowUnderAndAttachedInEveryScriptedMove() {
        defer { DecorField.shared.clear() }
        for m in Self.moves {
            let r = MotionRig(game: m.game)
            Self.keep.append(r)
            r.renderSamples = false
            m.start(r)
            var w = FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity), frames = 0
            var wc = FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity), coreFrames = 0
            var worstInfo = "", worstCore = "", clock: Float = 0
            r.run(m.seconds) {
                m.each?(r)
                clock += 1.0 / 60
                if m.name.hasPrefix("soccer") { DecorField.shared.tick(dt: 1.0 / 60) }          // (the ball rolls: the stage ticks the field each step)
                let f = Self.drawnFootFrame(r)
                let info = { String(format: "t=%.2f kind=%@ stage=%d script=%@ gait=%@ feetActive=%d stepU=%.2f yaw=%.2f boost=%.3f runW=%.2f pos=(%.2f,%.2f) amp=%.2f targets=%d", clock, "\(r.brain.idleState.kind.map { $0.rawValue } ?? "-")", r.brain.idleState.bagStage, "\(r.brain.script)", "\(r.brain.gait.phase)", r.brain.feet.active ? 1 : 0, r.brain.feet.stepU, r.brain.yaw, r.brain.walkBoostK, r.brain.runW, r.brain.px, r.brain.pz, r.brain.amplitude, r.sim.targets.count) }
                if r.skinner.beansActive && r.skinner.beanBlend > 0.05 {
                    if f.overlap > w.overlap { worstInfo = info() }
                    Self.accumulate(&w, f); frames += 1
                } else {
                    if f.overlap > wc.overlap || f.stretch > wc.stretch { worstCore = info() }
                    Self.accumulate(&wc, f); coreFrames += 1
                }
            }
            if w.overlap > Self.minOverlap { print("FEETWORST \(m.name): \(worstInfo)") }
            if wc.overlap > Self.minCoreOverlap || wc.stretch > Self.maxCoreStretch { print("FEETWORST \(m.name) (embedded foot): \(worstCore)") }
            if m.expectBeans { XCTAssertGreaterThan(frames, 20, "\(m.name): the beans were out") }
            XCTAssertGreaterThan(frames + coreFrames, 20, "\(m.name): a foot was measured in every frame")
            Self.check(m.name, w, frames: frames)
            Self.check(m.name + " (embedded foot)", wc, frames: coreFrames, core: true)
        }
    }

    /// Shoes (store, cosmetic) are grown from the rendered bean vertices: in every scripted move they stay on the bean (within their thickness) and
    /// obey the same low / under / attached limits as the bare foot. With shoes on the beans are out in EVERY move (`shoesWorn` keeps them live), so
    /// every row is measured, the rolls and the flip included (2026-10-21: the rolls were skipped as "no beans").
    func testShoesStayAttachedInEveryScriptedMove() {
        defer { DecorField.shared.clear() }
        for m in Self.moves {
            let r = MotionRig(game: m.game)
            Self.keep.append(r)
            r.renderSamples = false
            r.brain.shoesWorn = true
            m.start(r)
            var w = FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity), frames = 0
            var worstOff: Float = 0
            var k = 0
            r.run(m.seconds) {
                m.each?(r)
                k += 1
                if m.name.hasPrefix("soccer") { DecorField.shared.tick(dt: 1.0 / 60) }
                guard k % 3 == 0, r.skinner.beansActive, r.skinner.beanBlend > 0.05 else { return }
                r.render()
                let pose = r.sim.bodyPose(iterations: 4), c0 = r.sim.restCentroid
                var f = FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity)
                for s in 0..<2 {
                    let bean = r.bean[s].map { id -> SIMD3<Float> in let o = 6 * Int(id); return SIMD3(r.dyn[o], r.dyn[o + 1], r.dyn[o + 2]) }
                    guard bean.count == FootBean.vertexCount else { continue }
                    let b = RoomMeshBuilder(); b.material = .plain
                    ShoeModel.build(.rainBoots, bean: bean, floorY: r.sim.floorY, time: 0, side: s, into: b)
                    var lo = Float.infinity, cx: Float = 0, cy: Float = 0, cz: Float = 0, deepest = Float.infinity
                    for i in 0..<FootBean.vertexCount {
                        let v = b.mesh.vertices[i]
                        let p = SIMD3(v.pos.x, v.pos.y, v.pos.z)
                        worstOff = max(worstOff, simd_distance(p, bean[i]))
                        let q = c0 + pose.rotation.inverse.act(p - pose.centroid)
                        lo = min(lo, q.y); cx += q.x; cy += q.y; cz += q.z
                        deepest = min(deepest, Float(BobForm.bodySDF(SIMD3(Double(abs(q.x)), Double(q.y), Double(q.z)))))
                    }
                    let n = Float(FootBean.vertexCount)
                    f.soleRise = max(f.soleRise, lo); f.centreHeight = max(f.centreHeight, cy / n)
                    f.radius = max(f.radius, hypotf(cx / n, cz / n)); f.overlap = max(f.overlap, deepest)
                }
                Self.accumulate(&w, f); frames += 1
            }
            XCTAssertGreaterThan(frames, 10, "\(m.name): shoes were built")
            XCTAssertLessThanOrEqual(worstOff, ShoeModel.maxThickness + 1e-3, "\(m.name) + shoes: the shoe grows from the bean")
            // the shoe may sit a hair lower / wider than the bare foot by its own thickness: the limits get that much slack, never more
            let slack = ShoeModel.maxThickness
            MotionLog.write(String(format: "FEETATTACH shoes %@: %d frames, sole rise %.3f, centre height %.3f, radius %.3f, overlap %.3f", m.name, frames, w.soleRise, w.centreHeight, w.radius, w.overlap))
            XCTAssertLessThanOrEqual(w.soleRise, Self.maxSoleRise + slack, "\(m.name) + shoes: low")
            XCTAssertLessThanOrEqual(w.centreHeight, Self.maxCentreHeight + slack, "\(m.name) + shoes: not up on the belly")
            XCTAssertLessThanOrEqual(w.radius, Self.maxRadius + slack, "\(m.name) + shoes: under him")
        }
    }

    func testFeetStayAttachedWhileHeldDanglingAndThrown() {
        let r = TouchPlayTests.Rig()
        Self.keep.append(r)
        let sim = r.rig.sim
        r.step(touched: true)
        let hit = sim.centroid() + SIMD3(0, 0.1, 0.5)
        sim.beginGrab(hit: hit, radius: 0.4)
        var w = FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity), frames = 0
        func held(_ target: SIMD3<Float>, lift: Float) {
            r.step(touched: true) {
                sim.moveGrab(target: target, rot: nil)
                r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: true, liftHeight: lift, sim: sim, brain: r.rig.brain, skinner: r.rig.skinner)
            }
            if let f = Self.footFrame(r.rig) { Self.accumulate(&w, f); frames += 1 }
        }
        for _ in 0..<30 { held(hit, lift: 0) }
        for k in 0..<360 {
            let t = Float(k) / 60, e = min(1, t / 0.8)
            let lift = 0.4 * e * e * (3 - 2 * e)
            held(hit + SIMD3(0.6 * sinf(2.4 * t) * e, lift + 0.1 * sinf(3.1 * t) * e, 0.3 * sinf(1.7 * t) * e), lift: lift)
        }
        XCTAssertGreaterThan(frames, 20)
        // held in the air the feet dangle: allowed up to the dangle's own amplitude (a fraction of the body height), still under him
        Self.check("pick-up dangling", w, frames: frames)
        sim.endGrab()
        r.play.thrown = true
        sim.launch(velocity: SIMD3(2.5, 3.5, 0), spin: SIMD3(0, 0, -2.0))
        var wT = FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity), framesT = 0
        for _ in 0..<(60 * 4) {
            r.step(touched: true) { r.play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: false, liftHeight: 0, sim: sim, brain: r.rig.brain, skinner: r.rig.skinner) }
            if let f = Self.footFrame(r.rig) { Self.accumulate(&wT, f); framesT += 1 }
        }
        Self.check("thrown / landing", wT, frames: framesT, throwing: true)
    }

    /// A planted foot is the boot; a lifted one is a rounded ball; in between it morphs smoothly (no pop).
    func testPlantedBootLiftedBallMorph() {
        XCTAssertEqual(BlobBrain.beanMorph(clearance: 0), 0)
        XCTAssertEqual(BlobBrain.beanMorph(clearance: 0.05), 1)
        var prev: Float = 0
        for k in 0...100 { let m = BlobBrain.beanMorph(clearance: Float(k) * 0.0005); XCTAssertGreaterThanOrEqual(m, prev); XCTAssertLessThan(m - prev, 0.12); prev = m }
        // the ball sits on the sole plane and is smaller than the boot's footprint
        XCTAssertEqual(FootBean.ballF.map { $0.y }.min()!, 0, accuracy: 1e-5)
        XCTAssertLessThanOrEqual(FootBean.ballF.map { $0.x }.max()!, Float(BobForm.footRadii.x))
        // the morph is a plain vertex blend: same layout
        XCTAssertEqual(FootBean.ballF.count, FootBean.vertexCount)
    }

    /// The bean is the rest foot: its footprint equals the rest foot's (no size pop at the swap), sole flat on the floor, toe curled up.
    func testBeanIsTheRestFoot() {
        var minX = 9.0, maxX = -9.0, minZ = 9.0, maxZ = -9.0
        for p in FootBean.local.pos where p.y < 0.02 { minX = min(minX, p.x); maxX = max(maxX, p.x); minZ = min(minZ, p.z); maxZ = max(maxZ, p.z) }
        for p in FootBean.local.pos {
            let f = BobForm.footSDF(SIMD3(BobForm.footX + p.x, p.y, BobForm.footZ + p.z))
            XCTAssertEqual(f, 0, accuracy: 0.002, "every bean vertex lies on the rest foot surface")
        }
        XCTAssertLessThanOrEqual(FootBean.local.pos.map { $0.x }.max()!, BobForm.footRadii.x + 1e-6)
        XCTAssertLessThanOrEqual(FootBean.local.pos.map { $0.z }.max()!, BobForm.footToeLen + 1e-6)
        XCTAssertGreaterThanOrEqual(FootBean.local.pos.map { $0.z }.min()!, -BobForm.footRadii.z - 1e-6)
        // the toe slopes DOWN (no curled-up toe): the crown is lower at the toe tip than at the heel, the sole rise is a hair
        XCTAssertLessThan(BobForm.footSole(BobForm.footZ + BobForm.footToeLen), 0.012)
        XCTAssertLessThan(BobForm.footToeTop, BobForm.footHeelTop * 0.5)
    }

    /// The mesh-build winding fix (Geometry: flips a triangle whose normal disagrees with the hidden shape's vertex normals) must leave the
    /// bean triangles exactly as `FootBean.triangles` writes them: the hidden ball must not collapse.
    func testBeanTrianglesSurviveTheMeshBuild() {
        let rm = MotionRig.renderMesh
        guard let cap = rm.armCapsule else { return }
        for side in [-1, 1] {
            let want = FootBean.triangles(firstVertex: cap.beanFirst(side: side))
            var pos = -1
            var t = cap.indexFirst
            while t + want.count <= cap.indexFirst + cap.indexCount {
                if rm.index[t] == want[0] && rm.index[t + 1] == want[1] && rm.index[t + 2] == want[2] { pos = t; break }
                t += 3
            }
            XCTAssertGreaterThanOrEqual(pos, 0, "bean block found (side \(side))")
            if pos >= 0 { for k in 0..<want.count { XCTAssertEqual(rm.index[pos + k], want[k], "bean triangle entry \(k) flipped by the mesh build") } }
        }
    }
}
