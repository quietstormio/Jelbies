//
//  FlipTests.swift
//  The voice backflip (BlobBrain+Flip.swift, GaitDriver `.flip`): timing, apex, one full backward turn, rest return, stability, no
//  horizontal drift, jelly wobble on landing, voice teaching from the trick book row, and an old stored "yawn" lesson loading cleanly.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FlipTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    struct Result {
        var duration: Float = 0, apex: Float = 0, turn: Float = 0, drift: Float = 0, maxSpeed: Float = 0
        var restDev: Float = 0, nonFinite = false, airStart: Float = 0, airEnd: Float = 0
        var feetOffOutsideAir = false, landingJelly: Float = 0
    }

    private func fly(game: Bool, compact: Bool) -> Result {
        let game = game
        let r = MotionRig(game: game, settle: 1.5)
        Self.keep.append(r)
        let rest = r.sim.x
        let c0 = r.sim.centroid()
        let yaw0 = r.sim.bodyPose(iterations: 8).yaw
        let fwd0 = SIMD3<Float>(sinf(yaw0), 0, cosf(yaw0))
        let root0 = SIMD2(r.brain.px, r.brain.pz)
        MotionLog.write(String(format: "FLIP start centroid (%.3f, %.3f, %.3f) brain root (%.3f, %.3f) yaw %.3f", c0.x, c0.y, c0.z, root0.x, root0.y, yaw0))
        r.brain.startFlip(sim: r.sim, compact: compact)
        var res = Result()
        var lastAng: Float? = nil
        var maxAirT: Float = 0
        var t: Float = 0
        var ended = false
        for _ in 0..<(60 * 4) {
            r.tick(); t += 1 / 60
            r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            let c = r.sim.centroid()
            res.apex = max(res.apex, c.y - c0.y)
            res.drift = max(res.drift, simd_length(SIMD2(c.x - c0.x, c.z - c0.z)))
            var sp: Float = 0, spI = 0
            for i in 0..<(r.sim.v.count / 3) { let q = simd_length(SIMD3(r.sim.v[3*i], r.sim.v[3*i+1], r.sim.v[3*i+2])); if q > sp { sp = q; spI = i } }
            if sp > res.maxSpeed { let ro = r.sim.restPosition(spI) - r.sim.restCentroid; MotionLog.write(String(format: "  fastest particle %d rest offset (%.2f, %.2f, %.2f) v (%.1f, %.1f, %.1f)", spI, ro.x, ro.y, ro.z, r.sim.v[3*spI], r.sim.v[3*spI+1], r.sim.v[3*spI+2])) }
            if sp > res.maxSpeed { res.maxSpeed = sp; MotionLog.write(String(format: "  speedmax %.2f at t=%.3f phase=%@ u=%.2f landT=%.3f", sp, t, String(describing: r.brain.gait.phase), r.brain.gait.flipU, r.brain.gait.flipLandT)) }
            // pitch of the body's up vector in the facing frame
            let q = r.sim.bodyPose(iterations: 4).rotation
            let up = q.act(SIMD3<Float>(0, 1, 0))
            let ang = atan2f(simd_dot(up, fwd0), up.y)
            if let la = lastAng { var d = ang - la; while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }; res.turn += d }
            lastAng = ang
            let off = min(r.groundGap, r.groundGap) > MotionScenario.tol
            if off { if res.airStart == 0 { res.airStart = t }; res.airEnd = t }
            res.landingJelly = max(res.landingJelly, abs(r.skinner.jelly.squash))
            if r.sim.hasNonFinite() { res.nonFinite = true }
            maxAirT = max(maxAirT, t)
            if Int(t * 60 + 0.5) % 12 == 0 { MotionLog.write(String(format: "  t=%.2f c=(%.3f, %.3f, %.3f) ang=%.2f act=%@", t, c.x, c.y, c.z, ang, String(describing: r.brain.activity))) }
            if !ended, r.brain.activity != .playing, case .none = r.brain.script { ended = true; res.duration = t }
        }
        if !ended { res.duration = 99 }
        // rest return: 1.5 s after the script ended (we ran 4 s total)
        var dev: Float = 0
        for i in 0..<rest.count { dev = max(dev, abs(r.sim.x[i] - rest[i])) }
        res.restDev = dev
        return res
    }

    func testFlipRoamingAndFocusNumbers() {
        for (game, compact, target) in [(false, false, Float(0.42)), (true, false, 0.42), (true, true, 0.28)] {
            let a = fly(game: game, compact: compact)
            MotionLog.write(String(format: "FLIP game=%d compact=%d: duration %.2f s, apex %.3f u (target %.2f), turn %.2f rad, drift %.3f u, max particle speed %.2f u/s, rest dev %.4f, both-feet-off %.2f..%.2f s, jelly squash max %.4f",
                                   game ? 1 : 0, compact ? 1 : 0, a.duration, a.apex, target, a.turn, a.drift, a.maxSpeed, a.restDev, a.airStart, a.airEnd, a.landingJelly))
            XCTAssertLessThan(a.duration, 1.4, "the flip completes within ~1.4 s")
            XCTAssertEqual(a.apex, target, accuracy: 0.10 * target, "apex within 10 %")
            XCTAssertEqual(abs(a.turn), 2 * .pi, accuracy: 0.1, "one full turn")
            XCTAssertLessThan(a.turn, 0, "backward")
            XCTAssertFalse(a.nonFinite)
            XCTAssertLessThan(a.drift, 0.05, "no travel")
            XCTAssertLessThan(a.maxSpeed, 12.3, "particle speed rides the soft-body 12 u/s clamp (+ its damping term) at most; v1 peaked at 13.0")
            XCTAssertLessThan(a.restDev, 0.05, "back at the rest pose")
            XCTAssertGreaterThan(a.landingJelly, 0.004, "the landing wobbles the jelly")
        }
    }

    func testFlipLeavesTheFloorOnlyInTheAirPhase() {
        let r = MotionRig(game: true, settle: 1.5)
        Self.keep.append(r)
        r.brain.startFlip(sim: r.sim)
        var offEarly = false, offLate = false
        var t: Float = 0
        for _ in 0..<(60 * 3) {
            r.tick(); t += 1 / 60
            let off = r.groundGap > MotionScenario.tol
            if off && t < 0.16 { offEarly = true }
            if off && t > 0.16 + GaitDriver.flipAir(apex: 0.42) + 0.25 { offLate = true }
        }
        XCTAssertFalse(offEarly, "the crouch stays on the floor")
        XCTAssertFalse(offLate, "after the landing he stays down")
    }

    func testFlipEndsInRestPoseAndHandsBack() {
        let r = MotionRig(game: true, settle: 1.5)
        Self.keep.append(r)
        r.brain.startFlip(sim: r.sim)
        r.run(2.5, until: { if case .none = r.brain.script { return true }; return false })
        if case .none = r.brain.script {} else { XCTFail("flip script ends") }
        XCTAssertEqual(r.brain.gait.flipPitch, 0)
        XCTAssertFalse(r.brain.gait.isBusy)
        XCTAssertEqual(r.brain.armDirW, 0)
        r.run(2)
        XCTAssertEqual(r.brain.activity, .idle)
    }

    // MARK: v2: arms, stretch, faceplant

    func testArmsSwingBackInTheCrouchAndForwardAtLaunchWithLessStretch() {
        let r = MotionRig(game: true, settle: 1.5)
        Self.keep.append(r)
        r.brain.startFlip(sim: r.sim)
        r.run(0.14)
        XCTAssertEqual(r.brain.gait.phase, .crouch, "he winds up first")
        XCTAssertLessThan(r.brain.armDirSa[0], -0.8, "arms swung BACK in the crouch: \(r.brain.armDirSa[0])")
        XCTAssertGreaterThan(r.brain.armDirW, 0.95)
        var maxSq: Float = 0, minSq: Float = 9
        var saLaunch: Float = -9, elLaunch: Float = -9, maxSa: Float = -9
        var t: Float = 0
        while t < 1.2 {
            r.tick(); t += 1 / 60
            if r.brain.gait.phase == .air, r.brain.gait.flipU > 0.04 { maxSq = max(maxSq, r.sim.attractor.squash) }
            if r.brain.gait.phase == .air, r.brain.gait.flipU > 0.30 { minSq = min(minSq, r.sim.attractor.squash) }
            if r.brain.gait.phase == .air && r.brain.gait.flipU > 0.08 && r.brain.gait.flipU < 0.16 { saLaunch = max(saLaunch, r.brain.armDirSa[0]); elLaunch = max(elLaunch, r.brain.armDirEl[0]) }
            maxSa = max(maxSa, r.brain.armDirSa[0])
        }
        MotionLog.write(String(format: "FLIP arms: crouch sa %.2f, launch sa %.2f el %.2f, stretch max %.3f tuck min %.3f", r.brain.flipSa, saLaunch, elLaunch, maxSq, minSq))
        XCTAssertGreaterThan(saLaunch, 0.3, "arms swing forward at launch")
        XCTAssertGreaterThan(elLaunch, 0.6, "... and up")
        XCTAssertLessThanOrEqual(maxSq, 1.0501, "take-off stretch at most +0.05")
        XCTAssertGreaterThanOrEqual(minSq, 0.9399, "the tuck stays subtle (-0.06)")
    }

    func testFaceplantNumbers() {
        for (game, compact) in [(false, false), (true, false), (true, true)] {
            let r = MotionRig(game: game, settle: 1.5)
            Self.keep.append(r)
            let rest = r.sim.x
            let yaw0 = r.sim.bodyPose(iterations: 8).yaw
            _ = yaw0
            r.brain.startFlip(sim: r.sim, compact: compact, fail: true)
            var t: Float = 0, dur: Float = 0, ended = false
            var turnAtLie: Float = 0, pitchAtLie: Float = 0, fwdY: Float = 9, maxSpeed: Float = 0, nonFinite = false
            var lowestEyes = false
            var armSaPeel: Float = 9
            var lastAng: Float? = nil, cum: Float = 0
            let fwd0 = SIMD3<Float>(sinf(yaw0), 0, cosf(yaw0))
            for _ in 0..<(60 * 4) {
                r.tick(); t += 1 / 60
                for i in 0..<(r.sim.v.count / 3) { let sp = simd_length(SIMD3(r.sim.v[3*i], r.sim.v[3*i+1], r.sim.v[3*i+2])); if sp > maxSpeed { maxSpeed = sp; MotionLog.write(String(format: "  fp speedmax %.2f at t=%.3f phase=%@ u=%.2f landT=%.3f", sp, t, String(describing: r.brain.gait.phase), r.brain.gait.flipU, r.brain.gait.flipLandT)) } }
                if r.sim.hasNonFinite() { nonFinite = true }
                let q = r.sim.bodyPose(iterations: 4).rotation
                let up = q.act(SIMD3<Float>(0, 1, 0))
                let ang = atan2f(simd_dot(up, fwd0), up.y)
                if let la = lastAng { var d = ang - la; while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }; cum += d }
                lastAng = ang
                if r.brain.gait.phase == .land, abs(r.brain.gait.flipLandT - 0.4) < 0.009 {
                    turnAtLie = cum; pitchAtLie = r.brain.gait.flipPitch
                    fwdY = q.act(SIMD3<Float>(0, 0, 1)).y
                }
                if r.brain.gait.phase == .land, r.brain.gait.flipLandT > GaitDriver.fpLieEnd + 0.1, r.brain.gait.flipLandT < GaitDriver.fpPeelEnd { armSaPeel = min(armSaPeel, r.brain.armDirSa[0]) }
                if !ended, case .none = r.brain.script { ended = true; dur = t }
                _ = lowestEyes; lowestEyes = false
            }
            r.run(1.0)
            var dev: Float = 0, devIdx = 0
            for i in 0..<rest.count { let d = abs(r.sim.x[i] - rest[i]); if d > dev { dev = d; devIdx = i } }
            MotionLog.write(String(format: "  devIdx %d (axis %d) rest %.3f now %.3f", devIdx / 3, devIdx % 3, rest[devIdx], r.sim.x[devIdx]))
            MotionLog.write(String(format: "FAILFLIP game=%d compact=%d: duration %.2f s, turn at lie %.2f rad (pitch %.2f), forward.y %.2f, max speed %.2f, rest dev %.4f, peel arm sa %.2f",
                                   game ? 1 : 0, compact ? 1 : 0, dur, turnAtLie, pitchAtLie, fwdY, maxSpeed, dev, armSaPeel))
            XCTAssertFalse(nonFinite)
            XCTAssertGreaterThanOrEqual(dur, 1.8); XCTAssertLessThanOrEqual(dur, 2.4)
            XCTAssertEqual(abs(pitchAtLie), 4.9, accuracy: 0.3); XCTAssertGreaterThan(abs(pitchAtLie), 4.7); XCTAssertLessThan(abs(pitchAtLie), 5.2)
            XCTAssertGreaterThan(abs(turnAtLie), 4.4, "the sim body is round about 280 degrees when he lies there: \(turnAtLie)")
            XCTAssertLessThan(fwdY, -0.6, "face first: the front of the body points at the floor: \(fwdY)")
            XCTAssertLessThan(maxSpeed, 12.3, "the faceplant rides the clamp at most")
            XCTAssertLessThan(dev, game ? 0.06 : 0.01, "back at the rest pose (the game rig's idle sway keeps a few cm of phase difference, as in the clean flip's 0.044)")
            XCTAssertEqual(r.brain.armDirW, 0)
            XCTAssertEqual(r.brain.gait.flipPitch, 0)
            XCTAssertEqual(r.skinner.openness.left, 1, accuracy: 1e-4, "the face is back exactly")
            XCTAssertEqual(r.brain.mouthOpen, 0)
            XCTAssertEqual(r.brain.flipFaceplants, 1)
        }
    }

    /// The stage asks the touch play for a "get up" every frame; the faceplant lies face-down on purpose and must never be taken over by it.
    func testTouchGetUpLeavesTheFaceplantAlone() {
        let r = MotionRig(game: true, settle: 1.5)
        Self.keep.append(r)
        let play = TouchPlay(haptics: HapticDriver(sinks: []))
        r.brain.startFlip(sim: r.sim, fail: true)
        var sawLying = false, held = false, t: Float = 0
        while t < 3.5 {
            let h = play.getUpFrame(dt: 1 / 60, now: Double(100 + t), held: false, focusSpot: nil, sim: r.sim, brain: r.brain)
            if h { held = true }
            r.tick(touched: h); t += 1 / 60
            if r.brain.gait.phase == .land, r.brain.gait.flipLandT > 0.3, r.brain.gait.flipLandT < 0.5 { sawLying = sawLying || r.sim.bodyPose(iterations: 4).tilt > 1.0 }
        }
        XCTAssertTrue(sawLying, "he does lie face down")
        XCTAssertFalse(held, "the touch get-up never took over")
        XCTAssertEqual(play.getUps, 0)
        if case .none = r.brain.script {} else { XCTFail("the flip script ran to its end") }
    }

    // MARK: voice

    func testOldYawnLessonLoadsCleanly() {
        let suite = "FlipTests.yawn"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let json = #"{"name":{"word":"bob","reps":4,"sessions":[1,2],"learned":true,"reliability":0.5},"tricks":{"yawn":{"word":"sleepy","reps":4,"sessions":[1,2],"learned":true,"reliability":0.8},"sit":{"word":"sit","reps":4,"sessions":[1,2],"learned":true,"reliability":0.9}},"sessionCounter":3}"#
        d.set(Data(json.utf8), forKey: VoiceTuning.defaultsKey)
        let t = VoiceTraining(defaults: d, persists: true)
        XCTAssertTrue(t.isLearned(.sit))
        XCTAssertNil(t.book.tricks["yawn"], "the retired trick is dropped")
        XCTAssertFalse(t.isLearned(.flip))
        XCTAssertEqual(VoiceTrick.flip.title, "Flip"); XCTAssertEqual(VoiceTrick.flip.suggestion, "flip")
        XCTAssertNil(VoiceTrick(rawValue: "yawn"))
        d.removePersistentDomain(forName: suite)
    }
}

@MainActor
final class FlipVoiceTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = [] }

    @MainActor final class Clock { var t: Double = 100 }
    @MainActor final class Run {
        let rig = MotionRig(game: true, settle: 1.0)
        let clock = Clock()
        let care: GameCare
        var brain: BlobBrain { rig.brain }
        init() {
            let c = clock
            let training = VoiceTraining(defaults: UserDefaults(suiteName: "FlipVoiceTests")!, persists: false, random: { 0 })
            care = GameCare(voice: VoiceCoordinator(training: training, input: FakeSpeechInput(), now: { c.t }))
            for k in NeedKind.allCases { care.needs.set(k, 1) }
            brain.autonomy = false; brain.seed = 7
        }
        func tick() {
            brain.idleMood = care.mood
            brain.idleBlocked = ((care.focus.isActive && care.focusGroup.includes(0)) || care.trayOut) && !brain.commanded
            brain.tick(sim: rig.sim, skinner: rig.skinner, dt: rig.sim.stepDt, touched: false)
            care.tick(brain: brain, renderer: nil, dt: rig.sim.stepDt, sim: rig.sim)
            rig.sim.step(); rig.t += rig.sim.stepDt; clock.t += Double(rig.sim.stepDt)
        }
        @discardableResult func run(_ s: Float, until: (() -> Bool)? = nil) -> Bool {
            for _ in 0..<Int(s * 60) { tick(); if let until, until() { return true } }
            return until?() ?? false
        }
        var flipping: Bool { if case .flipPlay = brain.script { return true }; return false }
    }

    func testTeachFlipFromTheBookRowThenCommandIt() {
        let r = Run(); Self.keep.append(r)
        let v = r.care.voice
        v.flipRoll = { 0.99 }                                    // never a faceplant here
        for i in 0..<VoiceTuning.repsToLearn {
            r.run(2.0, until: { !r.flipping })
            r.run(0.5)
            v.show(.flip)                                        // the trick book row
            XCTAssertTrue(r.run(1.0, until: { r.flipping }), "the row starts the flip")
            r.run(0.1)
            XCTAssertTrue(v.begin())
            r.run(0.3)
            XCTAssertTrue(r.flipping, "still flipping while the word is said")
            v.hear("flip")
            r.run(0.2)
            XCTAssertEqual(v.training.lesson(.flip).reps, i + 1, "rep \(i + 1)")
        }
        XCTAssertTrue(v.training.isLearned(.flip), "\(VoiceTuning.repsToLearn) reps over \(VoiceTuning.repsToLearn) listens")
        XCTAssertEqual(v.training.word(for: .flip), "flip")
        r.run(2.5, until: { !r.flipping }); r.run(2.0)
        XCTAssertFalse(r.flipping)
        XCTAssertTrue(v.begin()); r.run(0.3)
        v.hear("flip")
        XCTAssertTrue(r.run(1.0, until: { r.flipping }), "the learned word runs the flip script")
        XCTAssertTrue(r.run(4.0, until: { !r.flipping }), "and it ends with no input")
        XCTAssertEqual(r.brain.flipFaceplants, 0)
        XCTAssertEqual(r.brain.flipTakeoffs, VoiceTuning.repsToLearn + 1)
    }

    private func settle(_ r: Run) { r.run(2.0, until: { !r.flipping }); r.run(0.5) }

    /// Untrained: never on the first try, never twice in a row (roll forced to 0 = "always fail" otherwise), and a faceplant still counts as a rep.
    func testBookRowFaceplantNeverFirstNeverTwiceAndCountsARep() {
        let r = Run(); Self.keep.append(r)
        let v = r.care.voice
        v.flipRoll = { 0.0 }
        var plants: [Bool] = []
        for _ in 0..<3 {
            settle(r)
            let before = r.brain.flipFaceplants
            v.show(.flip)
            XCTAssertTrue(r.run(1.0, until: { r.flipping }))
            if plants.count == 1 {
                XCTAssertTrue(v.begin()); r.run(0.3)
                v.hear("flip")
                r.run(0.1)
                XCTAssertEqual(v.training.lesson(.flip).reps, 1, "a rep counts on a faceplant")
            }
            XCTAssertTrue(r.run(4.0, until: { !r.flipping }))
            plants.append(r.brain.flipFaceplants > before)
        }
        XCTAssertEqual(plants, [false, true, false])
    }

    /// Flip never shows a meter or waits for input: the row alone flips him.
    func testBookRowFlipsWithNoInput() {
        let r = Run(); Self.keep.append(r)
        let v = r.care.voice
        v.flipRoll = { 0.99 }
        settle(r)
        v.show(.flip)
        XCTAssertTrue(r.run(1.5, until: { r.brain.flipTakeoffs == 1 }), "crouch then take-off by itself")
        XCTAssertTrue(r.run(3.0, until: { !r.flipping }))
        XCTAssertEqual(r.brain.flipFaceplants, 0)
    }
}
