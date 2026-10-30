//
//  WakeUpTests.swift
//  Wake-ups that vary (BlobBrain+WakeUps.swift): five get-ups and five flourishes, every one ending on his feet with the feet attached and the arms stubby; a
//  group wake gives each Jelbie a different pair and one shared landing frame and finish; Reduce Motion and fast wakes keep the plain pop + stretch; no
//  immediate repeat; the mask / hats poof by real roll progress (k), whatever the style.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WakeUpTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        WakeTuning.forceUp = nil; WakeTuning.forceFlo = nil; WakeTuning.debugLoaded = true
        A11ySettings.shared.reduceMotionInApp = false; A11ySettings.shared.systemReduceMotion = false
    }
    override func tearDown() {
        WakeTuning.forceUp = nil; WakeTuning.forceFlo = nil
        A11ySettings.shared.reduceMotionInApp = false; A11ySettings.shared.systemReduceMotion = false
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    private func faceUp(_ r: MotionRig) -> Float { r.sim.bodyPose(iterations: 4).rotation.act(SIMD3<Float>(0, 0, 1)).y }

    /// One napping rig (daytime, alone).
    private func napper(_ feature: JellyFeature = .none) -> MotionRig {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.skinner.autoBlink = false
        r.sim.teleport(toXZ: SIMD2(0, 0.2))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.seed = 11
        r.brain.feature = feature
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim))
        r.brain.sleep.hold = 600
        var f = 0
        while !r.brain.isNapping && f < 60 * 20 { r.tick(); f += 1 }
        XCTAssertTrue(r.brain.isNapping)
        for _ in 0..<60 { r.tick() }
        return r
    }

    /// Wakes him with this pair and measures the two stages, every frame watched for feet and arms.
    private func wakeMeasured(_ r: MotionRig, up: GetUp, flo: WakeFlourish, groggy: Bool, name: String) -> (upSec: Float, floSec: Float) {
        var w = SocialTests.Watch()
        var plan = WakePlan(); plan.up = up; plan.flo = flo; plan.chosen = true
        r.brain.sleepWake(groggy: groggy, plan: plan)
        var tUp: Float?, tFlo: Float?
        let t0 = r.t
        var f = 0
        var minK: Float = 9
        while r.brain.idleState.kind == .sleep, f < 60 * 8 {
            r.tick(); f += 1
            w.sample(r)
            if r.brain.idleState.kind == .sleep, r.brain.sleep.stage == 5, tUp == nil { tUp = r.t - t0; XCTAssertEqual(r.brain.sleep.k, 0, accuracy: 1e-4, "\(name): lands at k = 0") }
            if r.brain.idleState.kind == .sleep, r.brain.sleep.stage == 4 { minK = min(minK, r.brain.sleep.k) }
        }
        tFlo = r.t - t0
        XCTAssertNil(r.brain.idleState.kind, "\(name): the wake ends")
        XCTAssertNotNil(tUp, "\(name): reached the flourish")
        for _ in 0..<150 { r.tick(); w.sample(r) }          // (a smile may hold a moment past the finish)
        XCTAssertLessThan(abs(faceUp(r)), 0.35, "\(name): back on his feet")
        XCTAssertLessThan(r.sim.bodyPose(iterations: 6).tilt, 0.4, "\(name): upright")
        if flo == .stretch { XCTAssertEqual(r.skinner.openness.left, 1, accuracy: 0.02, "\(name): eyes open again") }          // (the others hand the face to the expression layer, which may smile on for a while)
        w.check(name)
        return (tUp ?? 0, (tFlo ?? 0) - (tUp ?? 0))
    }

    // MARK: every style

    func testEveryGetUpEndsUprightOnItsFeetAtItsLength() {
        for up in GetUp.allCases {
            let r = napper()
            let (u, _) = wakeMeasured(r, up: up, flo: .stretch, groggy: up == .sit, name: "get-up \(up)")
            XCTAssertEqual(u, WakeTuning.upLen(up), accuracy: 0.05, "get-up \(up): its own length")
            MotionLog.write("WAKEUP get-up \(up) took \(u) s")
        }
    }

    func testEveryFlourishFinishesStanding() {
        for flo in WakeFlourish.allCases {
            let feats: [JellyFeature] = flo == .signature ? [.spines, .daisy, .wings] : [.none]
            for ft in feats {
                let r = napper(ft)
                let groggy = flo == .look
                let (_, f) = wakeMeasured(r, up: .pop, flo: flo, groggy: groggy, name: "flourish \(flo) \(ft)")
                let nat = WakeTuning.floLen(flo, groggy: groggy, feature: ft)
                XCTAssertEqual(f, nat, accuracy: 0.08, "flourish \(flo) \(ft): its own length")
                MotionLog.write("WAKEUP flourish \(flo) \(ft) took \(f) s")
            }
        }
    }

    func testSideRollGoesAwayFromANeighbourNeverTowardHim() {
        let l = SocialTests.Lab(n: 2, positions: [SIMD2(-0.5, 0.3), SIMD2(1.2, 0.3)], quiet: true, seed: 5)
        for r in l.rigs { r.skinner.autoBlink = false; r.brain.sleepEnabled = true; r.brain.idleNight = 0 }
        for r in l.rigs { r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 600 }
        var f = 0
        while !l.rigs.allSatisfy({ $0.brain.isNapping }) && f < 60 * 40 { tick(l); f += 1 }
        XCTAssertTrue(l.rigs.allSatisfy { $0.brain.isNapping })
        for (me, other) in [(0, 1), (1, 0)] {
            let b = l.rigs[me].brain, o = l.rigs[other].brain
            let right = SIMD2(cosf(b.yaw), -sinf(b.yaw))
            let towardHim = simd_dot(o.position - b.position, right)          // + = he lies on my right
            XCTAssertLessThan(b.wakeRollSide() * towardHim, 0, "Jelbie \(me) rolls away from Jelbie \(other)")
        }
    }

    // MARK: group

    private func lab() -> SocialTests.Lab {
        let l = SocialTests.Lab(positions: [SIMD2(-0.5, 0.3), SIMD2(1.2, 0.9), SIMD2(2.2, -1.2)], quiet: true, seed: 5)
        for r in l.rigs { r.skinner.autoBlink = false; r.brain.sleepEnabled = true; r.brain.idleNight = 0 }
        l.rigs[0].brain.feature = .spines; l.rigs[1].brain.feature = .daisy; l.rigs[2].brain.feature = .wings
        return l
    }
    private func tick(_ l: SocialTests.Lab) {
        l.tick(watching: false)
        for r in l.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
    }
    private func sleepAll(_ l: SocialTests.Lab) {
        for r in l.rigs {
            r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 600
        }
        var f = 0
        while !l.rigs.allSatisfy({ $0.brain.isNapping }) && f < 60 * 40 { tick(l); f += 1 }
        XCTAssertTrue(l.rigs.allSatisfy { $0.brain.isNapping }, "all three down")
        for _ in 0..<60 { tick(l) }
    }

    func testGroupPlansAreDifferentWithSharedLengthsForEveryDraw() {
        let l = lab()
        let bs = l.rigs.map(\.brain)
        for groggy in [false, true] {
            for seed in 1...60 {
                bs[0].seed = UInt64(seed) * 977
                let plans = BlobBrain.groupWakePlans(bs, groggy: groggy)
                XCTAssertEqual(plans.count, 3)
                XCTAssertEqual(Set(plans.map(\.up)).count, 3, "different get-ups (groggy \(groggy), draw \(seed)): \(plans.map(\.up))")
                XCTAssertEqual(Set(plans.map(\.flo)).count, 3, "different flourishes (groggy \(groggy), draw \(seed)): \(plans.map(\.flo))")
                XCTAssertEqual(Set(plans.map(\.upLen)).count, 1, "one shared landing")
                XCTAssertEqual(Set(plans.map(\.floLen)).count, 1, "one shared finish")
                for (b, p) in zip(bs, plans) {
                    XCTAssertTrue(b.wakeUpChoices(groggy: groggy).contains(p.up), "get-up \(p.up) belongs to the \(groggy ? "groggy" : "lively") set")
                    XCTAssertTrue(b.wakeFlourishChoices(groggy: groggy).contains(p.flo), "flourish \(p.flo) belongs to the set")
                    if p.flo == .signature { XCTAssertTrue(b.wakeSignatureOK) }
                    let t = WakeTuning.upTiming(p)
                    XCTAssertEqual(t.end, p.upLen, accuracy: 1e-5)
                    XCTAssertGreaterThanOrEqual(t.lead, 0)
                }
                if groggy { XCTAssertFalse(plans.contains { $0.up == .rock || $0.up == .spring }, "groggy wakes never spring or rock") }
                else { XCTAssertFalse(plans.contains { $0.up == .sit || $0.flo == .look }, "lively wakes never sit up slowly or look around sleepily") }
            }
        }
    }

    func testGroupWakeStartsTogetherLandsOnOneFrameAndFinishesTogether() {
        let l = lab()
        let bs = l.rigs.map(\.brain)
        for (round, groggy) in [(0, false), (1, true), (2, false)] {
            sleepAll(l)
            bs[0].seed = UInt64(round + 3) * 7919
            let plans = BlobBrain.groupWakePlans(bs, groggy: groggy)
            for (b, p) in zip(bs, plans) { b.sleepWake(groggy: groggy, plan: p) }
            var landed = [Int](repeating: -1, count: 3), done = [Int](repeating: -1, count: 3)
            var minPair = Float.infinity
            var frame = 0
            XCTAssertTrue(bs.allSatisfy { $0.sleep.stage == 4 && $0.sleep.t == 0 }, "all begin on the same tick")
            while done.contains(-1), frame < 60 * 10 {
                tick(l); frame += 1
                for i in 0..<3 {
                    let b = bs[i]
                    if landed[i] < 0, b.idleState.kind == .sleep, b.sleep.stage == 5 { landed[i] = frame }
                    if done[i] < 0, b.idleState.kind == nil { done[i] = frame }
                }
                for i in 0..<3 { for j in (i + 1)..<3 { minPair = min(minPair, simd_distance(bs[i].position, bs[j].position)) } }
            }
            let what = "round \(round) \(plans.map { "\($0.up)/\($0.flo)" })"
            MotionLog.write("WAKEUP group \(what): landed \(landed), done \(done), min pair \(minPair)")
            XCTAssertEqual(Set(landed).count, 1, "\(what): the same landing frame \(landed)")
            XCTAssertEqual(Set(done).count, 1, "\(what): the same finish frame \(done)")
            XCTAssertGreaterThan(minPair, 1.0, "\(what): nobody passes into another")
            for r in l.rigs { XCTAssertLessThan(abs(faceUp(r)), 0.35, "\(what): on his feet") }
            for _ in 0..<10 { tick(l) }
            // the pair he did is remembered (memory only)
            for (b, p) in zip(bs, plans) { XCTAssertEqual(b.wakeLast, WakePair(up: p.up, flo: p.flo)) }
        }
    }

    // MARK: Reduce Motion, fast, repeats

    func testReduceMotionKeepsOnlyThePopAndTheStretch() {
        A11ySettings.shared.reduceMotionInApp = true
        let l = lab()
        let bs = l.rigs.map(\.brain)
        for b in bs { for g in [false, true] { for _ in 0..<40 { let p = b.chooseWakePlan(groggy: g); XCTAssertEqual(p.up, .pop); XCTAssertEqual(p.flo, .stretch) } } }
        for seed in 1...20 {
            bs[0].seed = UInt64(seed) * 31
            for p in BlobBrain.groupWakePlans(bs, groggy: seed % 2 == 0) { XCTAssertEqual(p.up, .pop); XCTAssertEqual(p.flo, .stretch) }
        }
    }

    func testFastWakesAreTheOldPopAndStretch() {
        for groggy in [false, true] {
            let r = napper(.wings)
            r.brain.sleepWake(groggy: groggy, fast: true)
            XCTAssertEqual(r.brain.sleep.plan.up, .pop); XCTAssertEqual(r.brain.sleep.plan.flo, .stretch)
            var up: Float?, f = 0
            let t0 = r.t
            while r.brain.idleState.kind == .sleep, f < 60 * 8 {
                r.tick(); f += 1
                if up == nil, r.brain.sleep.stage == 5 { up = r.t - t0 }
            }
            let total = r.t - t0
            XCTAssertEqual(up ?? 0, SleepTuning.rollBackTime, accuracy: 0.03, "the 0.5 s roll-up")
            XCTAssertEqual(total - (up ?? 0), SleepTuning.stretchTime * (groggy ? 1.5 : 1), accuracy: 0.05, "the stretch (groggy half again as long)")
        }
    }

    func testAJelbieNeverRepeatsHisLastPair() {
        let r = MotionRig(game: true); Self.keep.append(r)
        for ft in [JellyFeature.none, .spines, .daisy, .wings] {
            for g in [false, true] {
                r.brain.feature = ft
                r.brain.wakeLast = nil
                r.brain.seed = 99
                var last: WakePair?
                for _ in 0..<300 {
                    let p = r.brain.chooseWakePlan(groggy: g)
                    let pair = WakePair(up: p.up, flo: p.flo)
                    XCTAssertNotEqual(pair, last, "no immediate repeat (\(ft), groggy \(g))")
                    last = pair; r.brain.wakeLast = pair
                }
            }
        }
    }

    func testSignatureFollowsTheBodyNotTheName() {
        let r = MotionRig(game: true); Self.keep.append(r)
        let seen: [JellyFeature: Bool] = Dictionary(uniqueKeysWithValues: [JellyFeature.none, .spines, .daisy, .wings].map { ft in
            r.brain.feature = ft
            var any = false
            for g in [false, true] { for _ in 0..<200 { if r.brain.chooseWakePlan(groggy: g).flo == .signature { any = true } } }
            return (ft, any)
        })
        XCTAssertEqual(seen[.none], false, "a body with no feature never gets a signature")
        for ft in [JellyFeature.spines, .daisy, .wings] { XCTAssertEqual(seen[ft], true, "\(ft) gets one") }
        r.brain.feature = .wings; r.brain.wingsFolded = true
        for _ in 0..<200 { XCTAssertNotEqual(r.brain.chooseWakePlan(groggy: false).flo, .signature, "folded wings: no wing stretch") }
    }

    func testPetBedGetsInPlaceStylesOnly() {
        let r = MotionRig(game: true); Self.keep.append(r)
        r.brain.sleep.bed = 3
        for g in [false, true] {
            for _ in 0..<100 {
                let p = r.brain.chooseWakePlan(groggy: g)
                XCTAssertTrue([GetUp.pop, .rock, .sit].contains(p.up), "in a bed: \(p.up)")
                XCTAssertNotEqual(p.flo, .bounce)
            }
        }
    }

    // MARK: the mask and the hats

    func testMaskAndHatsGoByRealRollProgressForEveryStyle() {
        for up in GetUp.allCases {
            let r = napper()
            var plan = WakePlan(); plan.up = up; plan.chosen = true
            r.brain.sleepWake(groggy: up == .sit, plan: plan)
            var gone = false, f = 0, firstGoneK: Float = -1
            while r.brain.idleState.kind == .sleep, r.brain.sleep.stage == 4, f < 60 * 6 {
                r.tick(); f += 1
                guard r.brain.sleep.stage == 4 else { break }
                let on = SleepMaskSet.lingers(r.brain)
                XCTAssertEqual(on, !r.brain.sleep.maskOff, "\(up): the mask follows the latch")
                XCTAssertEqual(WornSet.sleepHides(r.brain), !r.brain.sleep.maskOff, "\(up): the hats follow it")
                if !on { XCTAssertLessThanOrEqual(r.brain.sleep.k, 0.8 + 0.2, "\(up): gone while still low") }
                if !on { if !gone { firstGoneK = r.brain.sleep.k }; gone = true } else { XCTAssertFalse(gone, "\(up): once off it stays off") }
            }
            XCTAssertTrue(gone, "\(up): the mask poofs during the get-up")
            if up == .spring { XCTAssertEqual(firstGoneK, 1, accuracy: 1e-4, "spring: it lets go in the crouch, while he still lies") }
            else { XCTAssertLessThanOrEqual(firstGoneK, r.brain.sleep.maskK + 0.1, "\(up): it goes at the mask's k, over his eyes, before he is upright") }
        }
    }

    func testCurvesAreContinuousAndEndAtZero() {
        for up in GetUp.allCases {
            var prev = WakeTuning.getUp(up, lt: 0, side: 1)
            XCTAssertEqual(prev.k, 1, accuracy: 1e-5, "\(up) starts lying")
            XCTAssertEqual(prev.lift, 0, accuracy: 1e-5)
            let n = 600, len = WakeTuning.upLen(up)
            for i in 1...n {
                let w = WakeTuning.getUp(up, lt: len * Float(i) / Float(n), side: 1)
                XCTAssertLessThan(abs(w.k - prev.k), 0.06, "\(up): no jump in k at \(i)")
                XCTAssertLessThan(abs(w.yRoll - prev.yRoll), 0.04, "\(up): no jump in the roll at \(i)")
                XCTAssertLessThan(abs(w.sq - prev.sq), 0.05, "\(up): no jump in the squash at \(i)")
                XCTAssertLessThan(abs(w.lift - prev.lift), 0.03, "\(up): no jump in the lift at \(i)")
                prev = w
            }
            XCTAssertEqual(prev.k, 0, accuracy: 1e-5, "\(up) lands standing")
            XCTAssertEqual(prev.yRoll, 0, accuracy: 1e-4, "\(up) ends level")
            XCTAssertEqual(prev.lift, 0, accuracy: 1e-5, "\(up) ends on the floor")
            XCTAssertEqual(prev.sq, 1, accuracy: 1e-4, "\(up) ends unsquashed")
        }
    }
}

// MARK: - sleeping life (2026-10-30: "they're too still")

extension WakeUpTests {
    /// Three naps at once, each reading the render-side breath; the breathing is not in unison, it is render-only (the sim still settles), the small stirs happen, and NOTHING moves
    /// him: the root never leaves its spot and no jolt (jellyKick) is ever raised while he sleeps (the user: "they just jump randomly").
    func testSleepersBreatheOutOfStepStirSmallAndNeverMoveOrJolt() {
        let l = SocialTests.Lab(positions: [SIMD2(-0.5, 0.3), SIMD2(1.2, 0.9), SIMD2(2.2, -1.2)], quiet: true, seed: 5)
        for r in l.rigs { r.skinner.autoBlink = false; r.brain.sleepEnabled = true; r.brain.idleNight = 0.6 }          // (night: no morning wake mid-test)
        for r in l.rigs { r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 5000 }
        var f = 0
        while !l.rigs.allSatisfy({ $0.brain.isNapping }) && f < 60 * 40 { l.tick(watching: false); f += 1 }
        XCTAssertTrue(l.rigs.allSatisfy { $0.brain.isNapping })
        for _ in 0..<60 { l.tick(watching: false) }
        for r in l.rigs { r.brain.jellyKick = 0 }          // (the lie-down's own impact is not consumed in this lab: clear it, nothing may raise another)
        let home = l.rigs.map { $0.brain.position }
        var lo = [Float](repeating: 0, count: 3), hi = [Float](repeating: 0, count: 3)
        var differ = 0, settledWhileBreathing = 0
        var chew = Set<Int>(), sigh = Set<Int>(), nestle = Set<Int>(), flex = Set<Int>()
        var minPair = Float.infinity, maxMove: Float = 0, maxYaw: Float = 0, maxKick: Float = 0
        for i in 0..<(60 * 90) {
            l.tick(watching: false)
            let b = l.rigs.map { $0.brain.sleep.breathSq }
            for k in 0..<3 { lo[k] = min(lo[k], b[k]); hi[k] = max(hi[k], b[k]) }
            if i > 120, abs(b[0] - b[1]) > 0.004 || abs(b[1] - b[2]) > 0.004 { differ += 1 }
            for (k, r) in l.rigs.enumerated() {
                let fd = r.brain.sleep.fid
                if fd.chewU >= 0 { chew.insert(k) }; if fd.sighU >= 0 { sigh.insert(k) }; if fd.yawU >= 0 { nestle.insert(k) }; if fd.flexU >= 0 { flex.insert(k) }
                if !fd.active, r.sim.isSettled, r.brain.sleep.breathSq != 0 { settledWhileBreathing += 1 }
                maxMove = max(maxMove, simd_distance(r.brain.position, home[k]))
                maxYaw = max(maxYaw, abs(fd.yawOff)); maxKick = max(maxKick, r.brain.jellyKick)
                XCTAssertEqual(r.brain.sleep.breathDisp, -r.brain.sleep.breathSq * Float(BobForm.top) * 0.85, accuracy: 1e-5)
                XCTAssertTrue(r.brain.isNapping, "he sleeps on")
            }
            for a in 0..<3 { for c in (a + 1)..<3 { minPair = min(minPair, simd_distance(l.rigs[a].brain.position, l.rigs[c].brain.position)) } }
        }
        for k in 0..<3 { XCTAssertLessThan(lo[k], -0.02, "sleeper \(k) breathes in visibly: \(lo[k])"); XCTAssertEqual(hi[k], 0, accuracy: 1e-6, "it only ever rises") }
        XCTAssertGreaterThan(differ, 600, "they do not breathe in unison")
        XCTAssertGreaterThan(settledWhileBreathing, 300, "the sim settles (and skips) while he breathes: the breath is render-only")
        XCTAssertGreaterThanOrEqual(chew.count + sigh.count + nestle.count + flex.count, 8, "stirs: chews \(chew) sighs \(sigh) nestles \(nestle) flexes \(flex)")
        XCTAssertLessThan(maxMove, 0.01, "no drift, no scoot, no roll-over: the root stays put")
        XCTAssertEqual(maxKick, 0, "no jolt of any kind while he sleeps")
        XCTAssertLessThanOrEqual(maxYaw, SleepTuning.maxNestle + 1e-4, "the nestle is a few degrees")
        XCTAssertGreaterThan(minPair, 1.3, "no sinking into a neighbour")
    }

    /// Reduce Motion: the breathing only.
    func testReduceMotionSleepersOnlyBreathe() {
        A11ySettings.shared.reduceMotionInApp = true
        let r = napper()
        r.brain.amplitude = 0.55
        var minBreath: Float = 0, fidgets = 0
        for _ in 0..<(60 * 45) {
            r.tick()
            minBreath = min(minBreath, r.brain.sleep.breathSq)
            if r.brain.sleep.fid.active { fidgets += 1 }
        }
        XCTAssertEqual(fidgets, 0, "no stirs under Reduce Motion")
        XCTAssertLessThan(minBreath, -0.02, "but he breathes")
    }

    /// In a pet bed too.
    func testBreathAndStirsFadeOutBeforeTheGetUp() {
        let r = napper()
        for _ in 0..<(60 * 5) { r.tick() }
        XCTAssertLessThan(r.brain.sleep.breathSq, 0.0001)
        var plan = WakePlan(); plan.up = .pop; plan.chosen = true
        r.brain.sleepWake(groggy: false, plan: plan)
        for _ in 0..<30 { r.tick() }
        XCTAssertEqual(r.brain.sleep.breathSq, 0, accuracy: 1e-6, "no breath once he is up")
    }
}
