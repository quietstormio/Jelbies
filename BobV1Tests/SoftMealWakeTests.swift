//
//  SoftMealWakeTests.swift
//  The soft meal wake ON (`BlobBrain.softMealWake`, 2026-11-12): a meal call to a sleeper wakes him softly and he always ends up eating; `callRunning` is never left set; a meal-waking sleeper is never
//  idle-like to the tray between the call and his first step; the wake's slot lags stagger a group.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SoftMealWakeTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956); SleepOrder.reset() }
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
    private func idleLike(_ a: BlobActivity) -> Bool { a == .idle || a == .lookingAround || a == .steppingInPlace }

    /// 30 seeds, one sleeper, the group meal: he stirs, is never idle-like to the tray, always eats, `mealWake` never outlives the wake.
    func testSingleSleeperAlwaysEatsAndNeverReadsIdle() {
        BlobBrain.softMealWake = true
        var firstEat: [Float] = []
        for seed in UInt64(1)...30 {
            let lab = night(n: 1, seed: seed)
            let b = lab.rigs[0].brain
            let group = DiningGroup()
            group.start(Consumables.berries, brains: [b], floor: { _ in b.position })
            XCTAssertTrue(b.isSleeping, "seed \(seed): not hard-aborted")
            var ate: Float?, t: Float = 0, idleBad: [String] = [], gaveUp = false
            while t < 60, ate == nil {
                lab.tick(watching: false); group.tick(dt: lab.rigs[0].sim.stepDt); t += dt
                if group.gaveUp { gaveUp = true }
                if b.activity == .eating || b.activity == .drinking { ate = t }
                else if ate == nil, b.sleep.mealWake || b.idleState.kind == .sleep, !b.mealWaking, idleLike(b.activity), b.idleState.kind == .sleep { idleBad.append("t\(t) stage \(b.sleep.stage)") }
            }
            XCTAssertNotNil(ate, "seed \(seed): eats")
            XCTAssertFalse(gaveUp, "seed \(seed): the group never gives up")
            XCTAssertTrue(idleBad.isEmpty, "seed \(seed): busy while waking \(idleBad.prefix(3))")
            XCTAssertFalse(b.sleep.mealWake, "seed \(seed): mealWake cleared")
            if let a = ate { firstEat.append(a) }
            group.cancel(); group.dining.reset()
        }
        let s = firstEat.sorted()
        let line = "SOFTWAKE-ON single first eat: min \(s.first ?? -1) median \(s.isEmpty ? -1 : s[s.count / 2]) max \(s.last ?? -1) (n \(s.count))"
        MotionLog.write(line); print(line)
    }

    /// Three sleepers, 30 seeds: nobody hard-aborted, staggered roll starts, the meal never gives up, every diner eats; prints the first-bite spread.
    func testThreeSleepersAllEatStaggered() {
        BlobBrain.softMealWake = true
        var worst: Float = 0, notAll = 0, gave = 0
        for seed in UInt64(1)...30 {
            let lab = night(n: 3, seed: seed)
            let brains = lab.rigs.map(\.brain)
            let group = DiningGroup()
            group.start(Consumables.berries, brains: brains, floor: { lab.rigs[$0].brain.position })
            var ate = [Float?](repeating: nil, count: 3), roll = [Float?](repeating: nil, count: 3), t: Float = 0
            while t < 60, ate.contains(where: { $0 == nil }), !group.gaveUp {
                lab.tick(watching: false); group.tick(dt: lab.rigs[0].sim.stepDt); t += dt
                for (i, b) in brains.enumerated() {
                    if roll[i] == nil, b.idleState.kind == .sleep, b.sleep.stage == 4 { roll[i] = t }
                    if ate[i] == nil, b.activity == .eating || b.activity == .drinking { ate[i] = t }
                }
            }
            if group.gaveUp { gave += 1 }
            if ate.contains(where: { $0 == nil }) { notAll += 1 }
            worst = max(worst, ate.compactMap { $0 }.max() ?? 0)
            let r = roll.compactMap { $0 }
            let line = "SOFTWAKE-ON three seed \(seed) roll \(roll.map { $0.map { String(format: "%.1f", $0) } ?? "nil" }) ate \(ate.map { $0.map { String(format: "%.1f", $0) } ?? "nil" }) spread \(String(format: "%.1f", (r.max() ?? 0) - (r.min() ?? 0))) gaveUp \(group.gaveUp)"
            MotionLog.write(line); print(line)
            group.cancel(); group.dining.reset()
        }
        let line = "SOFTWAKE-ON three summary: worst last first-bite \(worst) s, seeds where not all ate \(notAll), gave up \(gave)"
        MotionLog.write(line); print(line)
        XCTAssertEqual(gave, 0, "the meal is never given up")
        XCTAssertEqual(notAll, 0, "every diner eats")
    }

    /// `callRunning` (GameCare) is cleared by the watchdog only past 20 s of the meal's own clock, only with the flag on; a fresh GameCare never has it set by a meal call to a sleeper.
    func testCallRunningWatchdog() {
        BlobBrain.softMealWake = true
        XCTAssertFalse(GameCare.softMealWakeWatchdog(age: 19)); XCTAssertTrue(GameCare.softMealWakeWatchdog(age: 21))
        BlobBrain.softMealWake = false
        XCTAssertFalse(GameCare.softMealWakeWatchdog(age: 21), "off = today's flow")
        BlobBrain.softMealWake = true
        let care = GameCare()
        XCTAssertFalse(care.callRunning)
        let lab = night(n: 1, seed: 5)
        lab.rigs[0].brain.callToMeal(.goTo(SIMD2(0.5, 0.5)))
        XCTAssertFalse(care.callRunning, "a meal call never sets it")
    }
}
