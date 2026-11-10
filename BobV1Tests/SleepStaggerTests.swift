//
//  SleepStaggerTests.swift
//  Bedtime and waking are staggered per Jelbie (user 2026-11-09: "they walk and yawn at the exact same time then lay down and sleep the same time in sync ... they wake right up fast
//  and just start moving. It should be a slightly slow wake up that's slightly staggered"). BlobBrain+Sleep.swift: `SleepOrder` hands out an order index to calls in the same moment;
//  bedtime = linger + pauses; the soft wake = stir, slow roll, groggy stretch, look round. A single wake / `fast` stay as quick as before.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SleepStaggerTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956); SleepOrder.reset() }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SleepOrder.reset() }

    private let dt: Float = 1.0 / 60

    /// Three Jelbies at night (the same set-up as the -SleepNow budget test).
    private func night(seed: UInt64 = 21) -> SocialTests.Lab {
        let lab = SocialTests.Lab(quiet: false, seed: seed)
        for r in lab.rigs {
            r.brain.sleepEnabled = true; r.brain.watching = true
            r.brain.idleNight = 1; r.brain.idleDeepNight = 1
            r.brain.idleState.cooldown = 0; r.brain.restTimer = 0.5; r.brain.socialBook.cooldown = 1e6
        }
        for _ in 0..<120 { lab.tick(watching: false) }
        return lab
    }
    /// Bedtime, then run until all three are settled asleep (up to `limit` sim-s).
    private func allToBed(_ lab: SocialTests.Lab, limit: Float = 40) {
        NightRestTuning.sendToBed(lab.rigs.map(\.brain))
        var t: Float = 0
        while t < limit, !lab.rigs.allSatisfy({ $0.brain.isNapping }) { lab.tick(watching: false); t += dt }
        for _ in 0..<60 { lab.tick(watching: false) }          // (the last flop settles)
    }
    private func morning(_ lab: SocialTests.Lab) { for r in lab.rigs { r.brain.idleNight = 0; r.brain.idleDeepNight = 0 } }

    func testBedtimeForThreeIsStaggered() {
        let lab = night()
        let brains = lab.rigs.map(\.brain)
        NightRestTuning.sendToBed(brains)
        var yawn = [Float?](repeating: nil, count: 3), lie = [Float?](repeating: nil, count: 3), asleep = [Float?](repeating: nil, count: 3)
        var t: Float = 0
        var sleepingEarly = false
        while t < 40, asleep.contains(where: { $0 == nil }) {
            lab.tick(watching: false); t += dt
            if t < 3 * dt { sleepingEarly = brains.allSatisfy { $0.isSleeping } }          // (lingering Jelbies already count as sleeping: the Cancel pill and the retry loop see them)
            for (i, b) in brains.enumerated() {
                if yawn[i] == nil, b.idleState.kind == .sleep, b.sleep.stage == 1, b.sleep.turned, b.sleep.staggerSet, b.sleep.t >= b.sleep.pre1 { yawn[i] = t }
                if lie[i] == nil, b.idleState.kind == .sleep, b.sleep.stage >= 2 { lie[i] = t }
                if asleep[i] == nil, b.isNapping { asleep[i] = t }
            }
        }
        MotionLog.write("SLEEPSTAGGER bed yawn \(yawn) lie \(lie) asleep \(asleep)")
        XCTAssertTrue(sleepingEarly, "everybody is `isSleeping` from the first ticks (the linger counts)")
        XCTAssertFalse(yawn.contains { $0 == nil } || lie.contains { $0 == nil } || asleep.contains { $0 == nil }, "all three yawn, lie down and fall asleep")
        for (a, b) in [(0, 1), (0, 2), (1, 2)] {
            XCTAssertGreaterThanOrEqual(abs((yawn[a] ?? 0) - (yawn[b] ?? 0)), 0.5, "yawn starts \(a)/\(b) at least 0.5 s apart")
            XCTAssertGreaterThanOrEqual(abs((lie[a] ?? 0) - (lie[b] ?? 0)), 0.4, "lie-down starts \(a)/\(b) at least 0.4 s apart")
        }
        XCTAssertLessThanOrEqual(asleep.compactMap { $0 }.max() ?? 999, 14, "all asleep within the budget")
    }

    func testNoLingerForAPlainNapOrAnInstantSleep() {
        let lab = night()
        let a = lab.rigs[0].brain, b = lab.rigs[1].brain
        a.idleForced = true
        XCTAssertTrue(a.idleStart(.sleep, lab.rigs[0].sim))
        XCTAssertFalse(a.sleep.stagger); XCTAssertEqual(a.sleep.linger, 0); XCTAssertFalse(a.sleep.lingering)
        b.sleepInstant(lab.rigs[1].sim, lab.rigs[1].skinner)
        XCTAssertFalse(b.sleep.stagger); XCTAssertFalse(b.sleep.lingering)
    }

    func testMorningThreeSleepersRollStaggeredAndSlowly() {
        let lab = night()
        allToBed(lab)
        XCTAssertTrue(lab.rigs.allSatisfy { $0.brain.isNapping })
        let brains = lab.rigs.map(\.brain)
        morning(lab)
        var stir = [Float?](repeating: nil, count: 3), roll = [Float?](repeating: nil, count: 3), free = [Float?](repeating: nil, count: 3)
        var rollStep = [Int?](repeating: nil, count: 3)
        var napDuringStir = true, drift: Float = 0
        var home = brains.map { $0.position }
        var t: Float = 0, step = 0
        while t < 40, free.contains(where: { $0 == nil }) {
            lab.tick(watching: false); t += dt; step += 1
            for (i, b) in brains.enumerated() {
                if stir[i] == nil, b.idleState.kind == .sleep, b.sleep.stirT >= 0 { stir[i] = t }
                if b.idleState.kind == .sleep, b.sleep.stage == 3, b.sleep.stirT >= 0, !b.sleep.wakeAsked {
                    if !b.isNapping { napDuringStir = false }
                    drift = max(drift, simd_distance(b.position, home[i]))
                } else if b.idleState.kind == .sleep, b.sleep.stage == 3 { home[i] = b.position }
                if roll[i] == nil, b.idleState.kind == .sleep, b.sleep.stage == 4 { roll[i] = t; rollStep[i] = step }
                if free[i] == nil, stir[i] != nil, b.idleState.kind == nil { free[i] = t }
            }
        }
        MotionLog.write("SLEEPSTAGGER morning stir \(stir) roll \(roll) free \(free)")
        XCTAssertFalse(free.contains { $0 == nil }, "all up within 40 s")
        XCTAssertEqual(Set(rollStep.compactMap { $0 }).count, 3, "no two enter the roll on the same step")
        let spread = (roll.compactMap { $0 }.max() ?? 0) - (roll.compactMap { $0 }.min() ?? 0)
        XCTAssertGreaterThanOrEqual(spread, 0.6, "first-to-last roll start spread \(spread)")
        XCTAssertLessThanOrEqual(spread, 4, "first-to-last roll start spread \(spread)")
        for i in 0..<3 { XCTAssertGreaterThanOrEqual((free[i] ?? 0) - (stir[i] ?? 0), 2.5, "rig \(i): first stir to free takes at least 2.5 s") }
        XCTAssertTrue(napDuringStir, "mask + snores stay on (isNapping) through the stir")
        XCTAssertLessThan(drift, 0.001, "a lying sleeper never slides during the stir")
    }

    func testThreeWakeCallsOnOneTickAllStirFirstWithZeroLagOthersStaggered() {
        let lab = night()
        allToBed(lab)
        SleepOrder.reset()
        let brains = lab.rigs.map(\.brain)
        for b in brains { b.sleepWake(groggy: true) }
        for i in 0..<3 {
            XCTAssertEqual(brains[i].sleep.stage, 3, "rig \(i) is still lying (the first caller was put back into a stir)")
            XCTAssertTrue(brains[i].sleep.softWake); XCTAssertGreaterThanOrEqual(brains[i].sleep.stirT, 0)
            XCTAssertFalse(brains[i].sleep.wakeAsked, "wakeAsked waits for the roll (the mask and snores stay on)")
            XCTAssertTrue(brains[i].isNapping)
        }
        XCTAssertEqual(brains[0].sleep.stirLag, 0, accuracy: 0.001, "the first has no lag")
        lab.tick(watching: false)
        XCTAssertTrue(brains.allSatisfy { $0.sleep.stage != 4 && $0.isNapping }, "none is at stage 4 on the next tick")
        var roll = [Float?](repeating: nil, count: 3), rollEnd = [Float?](repeating: nil, count: 3)
        var t: Float = 0
        var napDuringStir = true
        while t < 30, rollEnd.contains(where: { $0 == nil }) {
            lab.tick(watching: false); t += dt
            for (i, b) in brains.enumerated() {
                if b.idleState.kind == .sleep, b.sleep.stage == 3, !b.sleep.wakeAsked, !b.isNapping { napDuringStir = false }
                if roll[i] == nil, b.sleep.stage == 4, b.idleState.kind == .sleep { roll[i] = t }
                if roll[i] != nil, rollEnd[i] == nil, b.sleep.stage >= 5 || b.idleState.kind == nil { rollEnd[i] = t }
            }
        }
        MotionLog.write("SLEEPSTAGGER wake3 roll \(roll) end \(rollEnd)")
        XCTAssertTrue(napDuringStir)
        XCTAssertGreaterThanOrEqual(roll[0] ?? 0, 0.75, "even the first stirs before he rolls")
        XCTAssertGreaterThanOrEqual(roll[1] ?? 0, 1.4, "the second stirs ~0.7-1.5 s after, then rolls")
        XCTAssertGreaterThanOrEqual(roll[2] ?? 0, 2.3, "the third ~1.6-2.8 s after")
        for i in 0..<3 { XCTAssertGreaterThanOrEqual((rollEnd[i] ?? 0) - (roll[i] ?? 0), 0.75, "rig \(i): the soft roll-up is slow") }
    }

    /// Per-tick order: A is woken, ticks once (his roll has begun by a tick), then B joins later in the same moment: A is softened too.
    func testFirstWakerIsSoftenedWhenASecondJoinsAfterOneTick() {
        let lab = night()
        allToBed(lab)
        SleepOrder.reset()
        let a = lab.rigs[0].brain, b = lab.rigs[1].brain
        a.sleepWake(groggy: true)
        XCTAssertEqual(a.sleep.stage, 4, "alone so far: today's quick path")
        lab.tick(watching: false)
        b.sleepWake(groggy: true)
        XCTAssertEqual(a.sleep.stage, 3, "A is put back into a stir")
        XCTAssertTrue(a.sleep.softWake); XCTAssertFalse(a.sleep.wakeAsked); XCTAssertTrue(a.isNapping)
        XCTAssertTrue(b.sleep.softWake); XCTAssertTrue(b.isNapping)
        // a wake that stays single, much later (a new moment), is the quick one
        for _ in 0..<(60 * 20) { lab.tick(watching: false) }
        SleepOrder.reset()
        let c = lab.rigs[2].brain
        if c.isNapping { c.sleepWake(groggy: true); XCTAssertEqual(c.sleep.stage, 4); XCTAssertFalse(c.sleep.softWake) }
    }

    func testOneWakeAloneIsTodaysQuickWake() {
        let lab = night()
        allToBed(lab)
        SleepOrder.reset()
        let b = lab.rigs[1].brain
        b.sleepWake(groggy: true)
        XCTAssertEqual(b.sleep.stage, 4); XCTAssertTrue(b.sleep.wakeAsked); XCTAssertTrue(b.sleep.groggy)
        XCTAssertFalse(b.sleep.softWake); XCTAssertEqual(b.sleep.stirT, -1); XCTAssertEqual(b.sleep.rollDur, SleepTuning.rollBackTime)
        var t: Float = 0
        var rollEnd: Float?
        while t < 10, rollEnd == nil { lab.tick(watching: false); t += dt; if b.sleep.stage >= 5 || b.idleState.kind == nil { rollEnd = t } }
        XCTAssertEqual(rollEnd ?? 0, SleepTuning.rollBackTime, accuracy: 0.08, "the roll is today's 0.5 s")
        XCTAssertTrue(lab.rigs[0].brain.isNapping && lab.rigs[2].brain.isNapping, "the others sleep on")
    }

    func testFastWakeIsTodaysTimingWithNoStagger() {
        let lab = night()
        allToBed(lab)
        SleepOrder.reset()
        let brains = lab.rigs.map(\.brain)
        for b in brains { b.sleepWake(groggy: false, fast: true) }
        for (i, b) in brains.enumerated() {
            XCTAssertEqual(b.sleep.stage, 4, "rig \(i): fast = at once, even as the 2nd / 3rd caller")
            XCTAssertFalse(b.sleep.softWake); XCTAssertEqual(b.sleep.stirT, -1); XCTAssertEqual(b.sleep.rollDur, SleepTuning.rollBackTime)
        }
        var t: Float = 0
        while t < 10, brains.contains(where: { $0.sleep.stage == 4 && $0.idleState.kind == .sleep }) { lab.tick(watching: false); t += dt }
        XCTAssertEqual(t, SleepTuning.rollBackTime, accuracy: 0.08, "all three are up off their backs after 0.5 s")
    }

    /// The tray with three sleepers: nobody is hard-aborted (each rolls up and stretches), they reach the tray one after another.
    func testTrayWakesThreeSleepersSoftlyAndTheyAllEatStaggered() {
        let lab = night()
        allToBed(lab)
        SleepOrder.reset()
        for r in lab.rigs { r.brain.idleNight = 0; r.brain.idleDeepNight = 0; r.brain.autonomy = false }
        let brains = lab.rigs.map(\.brain)
        let group = DiningGroup()
        group.start(Consumables.berries, brains: brains, floor: { lab.rigs[$0].brain.position })
        XCTAssertTrue(brains.allSatisfy { $0.isSleeping }, "nobody was hard-aborted by the call")
        var saw4 = [Bool](repeating: false, count: 3), saw5 = [Bool](repeating: false, count: 3), ate = [Float?](repeating: nil, count: 3)
        var t: Float = 0
        while t < 70, ate.contains(where: { $0 == nil }) {
            lab.tick(watching: false); group.tick(dt: lab.rigs[0].sim.stepDt); t += dt
            for (i, b) in brains.enumerated() {
                if b.idleState.kind == .sleep { if b.sleep.stage == 4 { saw4[i] = true }; if b.sleep.stage == 5 { saw5[i] = true } }
                if ate[i] == nil, b.activity == .eating || b.activity == .drinking { ate[i] = t }
            }
        }
        MotionLog.write("SLEEPSTAGGER tray saw4 \(saw4) saw5 \(saw5) ate \(ate)")
        XCTAssertTrue(saw4.allSatisfy { $0 } && saw5.allSatisfy { $0 }, "each passes through the roll and the stretch")
        XCTAssertFalse(ate.contains { $0 == nil }, "everybody reaches the tray and eats")
        let times = ate.compactMap { $0 }
        XCTAssertGreaterThan((times.max() ?? 0) - (times.min() ?? 0), 0.5, "they get there staggered")
        group.cancel(); group.dining.reset()
    }

    /// An awake Jelbie is still called with `requestNow` (`callToMeal`'s soft path is only for a lying one).
    func testCallToMealOnAnAwakeBrainIsRequestNow() {
        let lab = night()
        let b = lab.rigs[0].brain
        XCTAssertNotEqual(b.idleState.kind, .sleep)
        b.callToMeal(.goTo(SIMD2(0.5, 0.5)))
        XCTAssertTrue(b.interruptScript); XCTAssertFalse(b.sleep.mealWake)
    }
}
