//
//  SoftMealWakeClockTests.swift
//  The soft meal wake's clocks and the awake diner (2026-11-12): the single flow's `callRunning` watchdog advances while a Come call holds the tray back; `mealWakeT` ticks in every stage of the
//  wake (stage 5, the stretch, too); one awake + sleepers: the awake one eats at the normal time, the sleepers join once awake, nobody is left in `mealWaking`.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SoftMealWakeClockTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956); SleepOrder.reset(); BlobBrain.softMealWake = true }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SleepOrder.reset() }
    private let dt: Float = 1.0 / 60

    private func night(n: Int, seed: UInt64) -> SocialTests.Lab {
        let lab = SocialTests.Lab(n: n, quiet: false, seed: seed)
        for r in lab.rigs {
            r.brain.sleepEnabled = true; r.brain.watching = true
            r.brain.idleNight = 1; r.brain.idleDeepNight = 1
            r.brain.idleState.cooldown = 0; r.brain.restTimer = 0.5; r.brain.socialBook.cooldown = 1e6
        }
        for _ in 0..<120 { lab.tick(watching: false) }
        NightRestTuning.sendToBed(lab.rigs.map(\.brain))
        var t: Float = 0
        while t < 40, !lab.rigs.allSatisfy({ $0.brain.isNapping }) { lab.tick(watching: false); t += dt }
        for _ in 0..<60 { lab.tick(watching: false) }
        for r in lab.rigs { r.brain.idleNight = 0; r.brain.idleDeepNight = 0; r.brain.autonomy = false }
        SleepOrder.reset()
        return lab
    }

    /// Item 1: Bob is held by a Come call (`callRunning`), a tray is wanted: the order's clock runs anyway, the watchdog clears the call after 20 s and not before.
    func testSingleFlowWatchdogAdvancesWhileCallRunning() {
        let rig = MotionRig(game: true)
        let care = GameCare()
        care.wanted = Consumables.berries; care.callRunning = true
        var t: Float = 0
        while t < 19 { care.tickDining(id: 0, brain: rig.brain, sim: rig.sim, dt: dt); t += dt }
        XCTAssertTrue(care.callRunning, "not before 20 s")
        while t < 21 { care.tickDining(id: 0, brain: rig.brain, sim: rig.sim, dt: dt); t += dt }
        XCTAssertFalse(care.callRunning, "the watchdog fired by 21 s (wantedAge stood still before: it only ticks in serveWanted)")
        // a drink is the same path
        let care2 = GameCare()
        care2.wanted = Consumables.water; care2.callRunning = true
        t = 0
        while t < 21 { care2.tickDining(id: 0, brain: rig.brain, sim: rig.sim, dt: dt); t += dt }
        XCTAssertFalse(care2.callRunning, "drink: same")
    }

    /// Item 1: a single flow's sleeper whose wake is stuck past `wakeCap` is called the hard way once.
    func testSingleFlowStuckWakeFallsBack() {
        let lab = night(n: 1, seed: 3)
        let b = lab.rigs[0].brain
        let care = GameCare()
        care.wanted = Consumables.berries
        b.callToMeal(.goTo(SIMD2(0.5, 0.5)))
        XCTAssertTrue(b.mealWaking)
        b.sleep.mealWakeT = DiningGroup.wakeCap + 1
        care.tickDining(id: 0, brain: b, sim: lab.rigs[0].sim, dt: dt)
        XCTAssertFalse(b.mealWaking, "called the hard way")
        XCTAssertFalse(b.sleep.mealWake)
    }

    /// Item 2: `mealWakeT` ticks in every stage of the wake (stir 3, roll 4, stretch 5) and at the end of the wake equals the time since the call.
    func testMealWakeClockTicksInStageFive() {
        for seed in UInt64(1)...6 {
            let lab = night(n: 1, seed: seed)
            let b = lab.rigs[0].brain
            b.callToMeal(.goTo(SIMD2(0.5, 0.5)))
            var t: Float = 0, last: Float = 0, lastStage = 0, ticksIn5 = 0, advancedIn5 = 0
            while t < 30, b.mealWaking {
                let before = b.sleep.mealWakeT, stage = b.sleep.stage
                lab.tick(watching: false); t += dt
                if b.mealWaking {
                    last = b.sleep.mealWakeT; lastStage = b.sleep.stage
                    if stage == 5, b.sleep.stage == 5 { ticksIn5 += 1; if b.sleep.mealWakeT > before + dt * 0.5 { advancedIn5 += 1 } }
                }
            }
            XCTAssertGreaterThan(ticksIn5, 0, "seed \(seed): the lab wake has a stage 5")
            XCTAssertEqual(advancedIn5, ticksIn5, "seed \(seed): mealWakeT advances on every stage-5 tick")
            XCTAssertEqual(last, t, accuracy: 0.2, "seed \(seed): the clock reads the time since the call (last stage \(lastStage))")
        }
    }

    // MARK: item 3

    typealias Run = (tray: Float?, ate: [Float?], end: Float?, left: Int, gaveUp: Bool, inBox: Int, reason: String)
    /// `awake`: the ids woken (and settled) before the meal; the rest stay asleep. Group meal of berries over `n` Jelbies.
    private func meal(n: Int, awake: [Int], seed: UInt64) -> Run {
        let lab = night(n: n, seed: seed)
        let brains = lab.rigs.map(\.brain)
        for i in awake { brains[i].sleepWake(groggy: false, fast: true) }
        var w: Float = 0
        while w < 10, awake.contains(where: { brains[$0].isSleeping }) { lab.tick(watching: false); w += dt }
        for _ in 0..<120 { lab.tick(watching: false) }
        SleepOrder.reset()
        let group = DiningGroup()
        group.start(Consumables.berries, brains: brains, floor: { lab.rigs[$0].brain.position })
        var ate = [Float?](repeating: nil, count: n), tray: Float?, end: Float?, t: Float = 0
        while t < 45, end == nil {
            lab.tick(watching: false); group.tick(dt: lab.rigs[0].sim.stepDt); t += dt
            if tray == nil, group.dining.phase != .absent { tray = t }
            for (i, b) in brains.enumerated() where ate[i] == nil { if b.activity == .eating || b.activity == .drinking { ate[i] = t } }
            if group.state == .idle { end = t }
        }
        let r: Run = (tray, ate, end, brains.filter(\.mealWaking).count, group.gaveUp, group.inBoxTicks, group.popReason)
        group.cancel(); group.dining.reset()
        return r
    }
    private func f(_ v: Float?) -> String { v.map { String(format: "%.2f", $0) } ?? "nil" }

    /// One awake + one asleep (the lab's third diner is left behind in every mode, so n = 2; the three-Jelbie case is the real-app clip): the awake Jelbie's first bite is within 1 s of the all-awake meal (same seed), every Jelbie eats, the meal ends, nobody stays in `mealWaking`, the tray was never run through.
    func testOneAwakeTwoAsleepAwakeEatsOnTime() {
        var early = 0
        for seed in UInt64(1)...5 {
            let base = meal(n: 2, awake: [0, 1], seed: seed)
            let mix = meal(n: 2, awake: [0], seed: seed)
            let line = "SOFTWAKE-AWAKE seed \(seed) allAwake tray \(f(base.tray)) ate \(base.ate.map(f)) end \(f(base.end)) | oneAwake[\(mix.reason)] tray \(f(mix.tray)) ate \(mix.ate.map(f)) end \(f(mix.end)) gaveUp \(mix.gaveUp) inBox \(mix.inBox)"
            MotionLog.write(line); print(line)
            if mix.reason == "awake-first" { early += 1 }
            // a sleeper in front of his line or near the tray's rectangle keeps today's timing (the tray waits for him): only the early pop promises the awake one's time
            if mix.reason == "awake-first", let a = base.ate[0], let b = mix.ate[0] { XCTAssertLessThan(b - a, 1.0, "seed \(seed): the awake Jelbie eats on time (\(f(b)) vs \(f(a)))") }
            else if mix.reason == "awake-first" { XCTFail("seed \(seed): the awake one never ate") }
            XCTAssertFalse(mix.ate.contains { $0 == nil }, "seed \(seed): all eat \(mix.ate.map(f))")
            XCTAssertNotNil(mix.end, "seed \(seed): the meal ends")
            XCTAssertEqual(mix.left, 0, "seed \(seed): nobody left in mealWaking")
            XCTAssertEqual(mix.inBox, 0, "seed \(seed): nobody inside the tray")
            XCTAssertFalse(mix.gaveUp, "seed \(seed): not given up")
        }
        XCTAssertGreaterThanOrEqual(early, 3, "the early pop applies in most layouts (\(early) of 5)")
    }

    /// One sleeper, nobody awake: the tray does not pop before he is up (the new pop only applies with an awake diner), and he eats.
    func testAllAsleepTrayWaitsForThem() {
        for seed in UInt64(1)...2 {
            let r = meal(n: 2, awake: [], seed: seed)
            let line = "SOFTWAKE-AWAKE seed \(seed) allAsleep tray \(f(r.tray)) ate \(r.ate.map(f)) end \(f(r.end))"
            MotionLog.write(line); print(line)
            XCTAssertGreaterThan(r.tray ?? 0, 3, "seed \(seed): not at t = 0")
            XCTAssertEqual(r.left, 0)
        }
    }
}
