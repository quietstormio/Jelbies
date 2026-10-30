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
                XCTAssertEqual(on, r.brain.sleep.k > r.brain.sleep.maskK, "\(up): the mask follows k")
                XCTAssertEqual(WornSet.sleepHides(r.brain), r.brain.sleep.k > r.brain.sleep.maskK, "\(up): the hats follow k")
                if !on { if !gone { firstGoneK = r.brain.sleep.k }; gone = true } else { XCTAssertFalse(gone, "\(up): once off it stays off") }
            }
            XCTAssertTrue(gone, "\(up): the mask poofs during the get-up")
            XCTAssertLessThanOrEqual(firstGoneK, r.brain.sleep.maskK + 0.02)
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
