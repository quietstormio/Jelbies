//
//  MealWakeTimingTests.swift
//  The tray's SOFT wake (`BlobBrain.softMealWake`): how long from the call to the first step, per slot, and the invariant that a meal-woken sleeper never reads as idle
//  (`DiningGroup.isIdle`: .idle / .lookingAround / .steppingInPlace) between the call and the first step. Prints `MEALWAKE-TIMING` lines (MotionLog + stdout).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MealWakeTimingTests: XCTestCase {
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
        return lab
    }

    private func isIdleLike(_ a: BlobActivity) -> Bool { a == .idle || a == .lookingAround || a == .steppingInPlace }

    struct Row { var stir: Float?, roll: Float?, stretch: Float?, stretchEnd: Float?, step: Float?, lag: Float = 0; var idleTicks: [String] = [] }

    /// Call all brains in one tick, tick until everybody walks (or 14 s); returns per-brain rows.
    private func run(_ lab: SocialTests.Lab, label: String, seed: UInt64) -> [Row] {
        BlobBrain.softMealWake = true
        for r in lab.rigs { r.brain.idleNight = 0; r.brain.idleDeepNight = 0; r.brain.autonomy = false }
        SleepOrder.reset()
        let brains = lab.rigs.map(\.brain)
        for b in brains { b.callToMeal(.goTo(b.position + SIMD2(0, 1.5))) }
        var rows = [Row](repeating: Row(), count: brains.count)
        var t: Float = 0
        while t < 14, rows.contains(where: { $0.step == nil }) {
            lab.tick(watching: false); t += dt
            for (i, b) in brains.enumerated() where rows[i].step == nil {
                if b.idleState.kind == .sleep {
                    if b.sleep.stage == 3, b.sleep.stirT >= 0 { rows[i].lag = b.sleep.stirLag; if b.sleep.stirT - b.sleep.stirLag >= 0, rows[i].stir == nil { rows[i].stir = t } }
                    if b.sleep.stage == 4, rows[i].roll == nil { rows[i].roll = t }
                    if b.sleep.stage == 5, rows[i].stretch == nil { rows[i].stretch = t }
                } else if rows[i].stretch != nil, rows[i].stretchEnd == nil { rows[i].stretchEnd = t }
                if b.activity == .walking || b.activity == .coming { rows[i].step = t }
                else if isIdleLike(b.activity) { rows[i].idleTicks.append("t\(String(format: "%.2f", t)) stage\(b.sleep.stage) \(b.activity)") }
            }
        }
        BlobBrain.softMealWake = false
        func f(_ v: Float?) -> String { v.map { String(format: "%.2f", $0) } ?? "nil" }
        for (i, r) in rows.enumerated() {
            let line = "MEALWAKE-TIMING \(label) seed \(seed) slot \(i) lag \(f(r.lag)) | stir \(f(r.stir)) roll \(f(r.roll)) stretch \(f(r.stretch)) stretchEnd \(f(r.stretchEnd)) firstStep \(f(r.step))"
            MotionLog.write(line); print(line)
        }
        return rows
    }

    private func check(_ rows: [Row], _ what: String) {
        for (i, r) in rows.enumerated() {
            XCTAssertNotNil(r.step, "\(what) slot \(i): walks")
            if let s = r.step { XCTAssertLessThanOrEqual(s, 12, "\(what) slot \(i): walking within 12 s (\(s))") }
            XCTAssertTrue(r.idleTicks.isEmpty, "\(what) slot \(i): never idle-like before the first step: \(r.idleTicks.prefix(5))")
        }
    }

    func testThreeSleepersTimingSeeds() {
        var bySlot: [[Float]] = [[], [], []]
        for seed in UInt64(1)...6 {
            let lab = night(n: 3, seed: seed)
            let rows = run(lab, label: "three", seed: seed)
            check(rows, "seed \(seed)")
            for (i, r) in rows.enumerated() { if let s = r.step { bySlot[i].append(s) } }
        }
        for (i, v) in bySlot.enumerated() {
            let s = v.sorted()
            guard !s.isEmpty else { continue }
            let line = String(format: "MEALWAKE-TIMING summary slot %d firstStep min %.2f median %.2f max %.2f (n %d)", i, s.first!, s[s.count / 2], s.last!, s.count)
            MotionLog.write(line); print(line)
        }
    }

    func testSingleSleeperTiming() {
        var v: [Float] = []
        for seed in UInt64(1)...6 {
            let lab = night(n: 1, seed: seed)
            let rows = run(lab, label: "single", seed: seed)
            check(rows, "single seed \(seed)")
            if let s = rows[0].step { v.append(s) }
        }
        let s = v.sorted()
        if !s.isEmpty {
            let line = String(format: "MEALWAKE-TIMING summary single firstStep min %.2f median %.2f max %.2f (n %d)", s.first!, s[s.count / 2], s.last!, s.count)
            MotionLog.write(line); print(line)
        }
    }

    /// Task 2: stage 3 with `wakeAsked` already true joins the soft wake (no hard abort), and `mealWake` is cleared once the walk begins.
    func testStage3WithWakeAskedStaysSoftAndClearsMealWake() {
        let lab = night(n: 1, seed: 3)
        let b = lab.rigs[0].brain
        BlobBrain.softMealWake = true; defer { BlobBrain.softMealWake = false }
        for r in lab.rigs { r.brain.idleNight = 0; r.brain.idleDeepNight = 0; r.brain.autonomy = false }
        XCTAssertEqual(b.sleep.stage, 3)
        b.sleep.wakeAsked = true
        b.callToMeal(.goTo(b.position + SIMD2(0, 1.5)))
        XCTAssertFalse(b.interruptScript, "no hard abort")
        XCTAssertTrue(b.sleep.mealWake)
        var t: Float = 0, walked = false
        while t < 14, !walked {
            lab.tick(watching: false); t += dt
            if b.activity == .walking { walked = true } else { XCTAssertFalse(isIdleLike(b.activity), "stage \(b.sleep.stage) \(b.activity)") }
        }
        XCTAssertTrue(walked)
        XCTAssertFalse(b.sleep.mealWake, "cleared when the walk begins")
    }
}
