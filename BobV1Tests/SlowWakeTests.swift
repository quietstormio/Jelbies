//
//  SlowWakeTests.swift
//  Slow wake everywhere (`BlobBrain.slowWakeEverywhere`, 2026-11-12, user: "Whenever they wake up it should be slow with a yawn and stretch"): a tap, a call (`requestNow`), a bang, a natural wake all give
//  the staged wake (stir, roll up, YAWN, stretch) and the action that woke him starts when it ends; the immediate causes (`fast`: race / volley / show / newcomer) and the switch off keep today's numbers.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SlowWakeTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956); SleepOrder.reset(); BlobBrain.slowWakeEverywhere = true; BlobBrain.softMealWake = true }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SleepOrder.reset(); BlobBrain.slowWakeEverywhere = true; AudioHub.requestTap = nil }
    private let dt: Float = 1.0 / 60

    private func night(n: Int = 1, seed: UInt64) -> SocialTests.Lab {
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

    struct Timeline { var stir: Float?, roll: Float?, yawn: Float?, stretch: Float?, up: Float?, step: Float?, maxMouth: Float = 0, snoreAfterCall = false, lastStage = 0 }

    /// Runs the lab after the cause until he has taken his first step (or `limit`), logging when each stage first shows.
    private func run(_ lab: SocialTests.Lab, _ b: BlobBrain, limit: Float = 25, until: (BlobBrain, Timeline) -> Bool = { _, tl in tl.step != nil }) -> Timeline {
        var tl = Timeline(); var t: Float = 0
        let from = b.position
        while t < limit, !until(b, tl) {
            lab.tick(watching: false); t += dt
            if b.idleState.kind == .sleep {
                if b.sleep.stage == 3, b.sleep.stirT >= 0, tl.stir == nil { tl.stir = t }
                if b.sleep.stage == 4, tl.roll == nil { tl.roll = t }
                if b.sleep.stage == 5 {
                    if tl.stretch == nil { tl.stretch = t }
                    if b.sleep.t < SlowWakeTuning.yawnTime, tl.yawn == nil, b.mouthOpen > 0.3 { tl.yawn = t }
                    tl.maxMouth = max(tl.maxMouth, b.mouthOpen)
                }
                tl.lastStage = b.sleep.stage
                if tl.stir != nil, b.isSnoring { tl.snoreAfterCall = true }
            } else if tl.up == nil, tl.roll != nil || tl.stir != nil { tl.up = t }
            if tl.step == nil, tl.up != nil, simd_distance(b.position, from) > 0.08 { tl.step = t }
        }
        return tl
    }
    private func f(_ v: Float?) -> String { v.map { String(format: "%.2f", $0) } ?? "nil" }
    private func log(_ s: String) { MotionLog.write(s); print(s) }

    /// A tap (what `tick` does for a finger that touches a sleeper: `sleepWake(groggy: true)`): stir, roll up, YAWN, stretch, up. Nothing is dropped; he is up well inside the cap.
    func testTapIsTheStagedWakeWithAYawn() {
        for seed in UInt64(1)...6 {
            let lab = night(seed: seed); let b = lab.rigs[0].brain
            var yawnReq = 0; AudioHub.requestTap = { if $0 == "voice:yawn" { yawnReq += 1 } }
            XCTAssertTrue(b.isNapping)
            b.sleepWake(groggy: true)
            XCTAssertTrue(b.sleep.stirT >= 0 || b.sleep.wakeWhenDown, "seed \(seed): a tap stirs, no quick roll (stage \(b.sleep.stage))")
            XCTAssertFalse(b.sleep.wakeAsked)
            let tl = run(lab, b, until: { b, _ in b.idleState.kind != .sleep })
            log("SLOWWAKE tap seed \(seed): stir \(f(tl.stir)) roll \(f(tl.roll)) yawn \(f(tl.yawn)) stretch \(f(tl.stretch)) up \(f(tl.up)) maxMouth \(tl.maxMouth) yawnVoiceRequests \(yawnReq)")
            XCTAssertNotNil(tl.stir); XCTAssertNotNil(tl.roll); XCTAssertNotNil(tl.yawn, "seed \(seed): the yawn shows (mouth wide)"); XCTAssertNotNil(tl.stretch)
            XCTAssertGreaterThan(tl.maxMouth, 0.8, "seed \(seed): wide, round mouth")
            XCTAssertLessThan(tl.stir ?? 9, tl.roll ?? 0); XCTAssertLessThan(tl.roll ?? 9, tl.yawn ?? 0); XCTAssertLessThan(tl.yawn ?? 9, tl.up ?? 0)
            XCTAssertLessThan(tl.up ?? 99, 9.0, "seed \(seed): up inside 9 s")
            XCTAssertFalse(tl.snoreAfterCall, "seed \(seed): snores stop when the wake starts")
            XCTAssertEqual(yawnReq, 1, "seed \(seed): one yawn voice per wake (requested)")
            XCTAssertFalse(b.sleep.slowWake); XCTAssertEqual(b.mouthOpen, 0, accuracy: 1e-4)
        }
    }

    /// A repeat tap during the stir does not cut it short.
    func testSecondTapDuringTheWakeKeepsTheStagedWake() {
        let lab = night(seed: 3); let b = lab.rigs[0].brain
        b.sleepWake(groggy: true)
        for _ in 0..<30 { lab.tick(watching: false) }
        b.sleepWake(groggy: true)          // another tap
        XCTAssertFalse(b.sleep.wakeAsked && b.sleep.stirT < 0, "still the soft wake")
        XCTAssertTrue(b.sleep.softWake)
        let tl = run(lab, b, until: { b, _ in b.idleState.kind != .sleep })
        XCTAssertNotNil(tl.yawn)
    }

    /// Every `requestNow` (drink, wash, play, toy, bubble wand, guest, trick walks ...) on a sleeper waits for the staged wake and then walks; the time to the first step is printed.
    func testRequestNowWaitsForTheStagedWakeThenWalks() {
        for seed in UInt64(1)...6 {
            let lab = night(seed: seed); let b = lab.rigs[0].brain
            let goal = b.position + SIMD2(1.4, 0.8)
            b.requestNow(.goTo(goal))
            XCTAssertTrue(b.isSleeping, "seed \(seed): not hard-aborted")
            lab.tick(watching: false)
            XCTAssertTrue(b.isSleeping)
            let tl = run(lab, b)
            log("SLOWWAKE call seed \(seed): stir \(f(tl.stir)) roll \(f(tl.roll)) yawn \(f(tl.yawn)) stretch \(f(tl.stretch)) up \(f(tl.up)) first step \(f(tl.step))")
            XCTAssertNotNil(tl.yawn, "seed \(seed): staged incl. the yawn"); XCTAssertNotNil(tl.step, "seed \(seed): he walks")
            XCTAssertLessThan(tl.step ?? 99, 10.0, "seed \(seed): first step inside 10 s")
            // keeps walking to the goal
            for _ in 0..<(60 * 12) { lab.tick(watching: false) }
            XCTAssertLessThan(simd_distance(b.position, goal), 0.6, "seed \(seed): arrives (\(b.position) vs \(goal))")
        }
    }

    /// A second call during the wake is kept (the later one wins, as for an awake Jelbie): asked during the roll AND during the stretch.
    func testSecondCallDuringTheWakeIsHonoured() {
        for (label, atStage) in [("roll", 4), ("stretch", 5)] {
            let lab = night(seed: 9); let b = lab.rigs[0].brain
            let p1 = b.position + SIMD2(1.5, 0), p2 = b.position + SIMD2(-1.5, 0.5)
            b.requestNow(.goTo(p1))
            var t: Float = 0
            while t < 15, !(b.idleState.kind == .sleep && b.sleep.stage == atStage) { lab.tick(watching: false); t += dt }
            XCTAssertEqual(b.sleep.stage, atStage)
            b.requestNow(.goTo(p2))
            XCTAssertTrue(b.isSleeping, "\(label): the second call does not abort the wake")
            for _ in 0..<(60 * 14) { lab.tick(watching: false) }
            XCTAssertLessThan(simd_distance(b.position, p2), 0.6, "\(label): he went to the later call (\(b.position) vs \(p2))")
        }
    }

    /// A natural wake (slept enough): stir, roll, yawn, stretch; never the quick roll.
    func testNaturalWakeIsStagedAndOffIsQuick() {
        for on in [true, false] {
            BlobBrain.slowWakeEverywhere = on
            let lab = night(seed: 4); let b = lab.rigs[0].brain
            b.sleep.hold = b.sleep.t + 0.3          // slept enough, in the daytime (no morning rule)
            let tl = run(lab, b, limit: 15, until: { b, _ in b.idleState.kind != .sleep })
            log("SLOWWAKE natural on=\(on): stir \(f(tl.stir)) roll \(f(tl.roll)) yawn \(f(tl.yawn)) stretch \(f(tl.stretch)) up \(f(tl.up))")
            if on { XCTAssertNotNil(tl.stir); XCTAssertNotNil(tl.yawn, "the yawn shows"); XCTAssertGreaterThan(tl.roll ?? 0, 0.8, "he stirs first") }
            else { XCTAssertNil(tl.stir); XCTAssertLessThan(tl.roll ?? 9, 0.6, "off: the quick roll at once"); XCTAssertNil(tl.yawn) }
            XCTAssertNotNil(tl.up)
        }
    }

    /// The immediate causes stay immediate: `fast` (race / volley / show / newcomer) rolls at once, no stir, then the hard `requestNow` aborts as today.
    func testImmediateCauseStaysImmediate() {
        let lab = night(seed: 5); let b = lab.rigs[0].brain
        b.sleepWake(groggy: false, fast: true)
        XCTAssertEqual(b.sleep.stage, 4); XCTAssertFalse(b.sleep.softWake); XCTAssertEqual(b.sleep.stirT, -1); XCTAssertEqual(b.sleep.rollDur, SleepTuning.rollBackTime)
        XCTAssertTrue(b.sleep.quick)
        b.requestNow(.goTo(b.position + SIMD2(1, 0)))
        XCTAssertTrue(b.interruptScript, "the hard path: aborted on the next tick")
        lab.tick(watching: false)
        XCTAssertFalse(b.isSleeping)
        let t0 = lab.rigs[0].brain.position
        for _ in 0..<120 { lab.tick(watching: false) }
        log("SLOWWAKE immediate: up after one tick, moved \(simd_distance(b.position, t0))")
    }

    /// Switch off = today: a tap rolls at once (no stir), a request is a hard abort.
    func testSwitchOffIsToday() {
        BlobBrain.slowWakeEverywhere = false
        let lab = night(seed: 6); let b = lab.rigs[0].brain
        b.sleepWake(groggy: true)
        XCTAssertEqual(b.sleep.stage, 4); XCTAssertFalse(b.sleep.softWake); XCTAssertTrue(b.sleep.wakeAsked); XCTAssertFalse(b.sleep.slowWake)
        var t: Float = 0
        while t < 6, b.idleState.kind == .sleep { lab.tick(watching: false); t += dt }
        log("SLOWWAKE off tap: up at \(t) s")
        XCTAssertLessThan(t, 3.6, "today's wake: 0.5 roll + 1.5*1.5/2.7 stretch")
        let lab2 = night(seed: 6); let b2 = lab2.rigs[0].brain
        b2.requestNow(.goTo(b2.position + SIMD2(1, 0)))
        XCTAssertTrue(b2.interruptScript); XCTAssertNotNil(b2.pending)
        lab2.tick(watching: false)
        XCTAssertFalse(b2.isSleeping, "off: the call hard-aborts the sleep, as today")
    }

    /// A stuck slow wake ends hard past its cap, and the call is not lost.
    func testStuckWakeEndsHardAtTheCap() {
        let lab = night(seed: 7); let b = lab.rigs[0].brain
        b.requestNow(.goTo(b.position + SIMD2(1.2, 0)))
        lab.tick(watching: false)
        XCTAssertTrue(b.sleep.slowWake)
        b.sleep.mealWakeT = SlowWakeTuning.cap + 0.5
        lab.tick(watching: false)
        XCTAssertFalse(b.isSleeping, "the cap ends the sleep hard")
        XCTAssertTrue(b.pending != nil || b.job != nil || b.activity == .walking, "the kept call was handed back (pending \(String(describing: b.pending)), job \(String(describing: b.job)), \(b.activity))")
        let p0 = b.position
        for _ in 0..<(60 * 6) { lab.tick(watching: false) }
        XCTAssertGreaterThan(simd_distance(b.position, p0), 0.5, "and he walked it")
    }

    /// A voice / trick command during the sleep is held until the wake ends.
    func testCommandIsHeldUntilTheWakeEnds() {
        let lab = night(seed: 8); let b = lab.rigs[0].brain
        b.commandedFlip = true
        lab.tick(watching: false)
        XCTAssertTrue(b.isSleeping, "not aborted by the command"); XCTAssertFalse(b.commandedFlip, "held")
        var t: Float = 0
        while t < 15, b.idleState.kind == .sleep { lab.tick(watching: false); t += dt }
        XCTAssertFalse(b.isSleeping)
        XCTAssertGreaterThan(t, 3.0, "he went through the staged wake first (\(t) s)")
        log("SLOWWAKE command held: slept on for \(t) s")
    }
}
