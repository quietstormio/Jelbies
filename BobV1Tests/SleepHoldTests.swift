//
//  SleepHoldTests.swift
//  A bedtime must HOLD, not just start: with three Jelbies and a group bedtime, every one of them (the last to lie down too) stays asleep, with no
//  sleep -> awake transition, for the whole window. Sweeps seeds, day and night, with a selection and a recent interaction.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SleepHoldTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let seeds: ClosedRange<UInt64> = 1...2
    private var room: RaceTripTests.Room!
    private var care: GameCare { room.care }
    private var brains: [BlobBrain] { room.actors.compactMap(\.brain) }

    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
    }
    override func tearDown() {
        DayClock.shared.forcedHour = 12
        NightRestTuning.idleBedtime = 180
        DecorField.shared.clear()
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    private func make(seed: UInt64, hour: Double) {
        DayClock.shared.forcedHour = hour
        let r = RaceTripTests.Room()
        Self.keep.append(r)
        room = r
        for a in r.actors {
            guard let b = a.brain else { continue }
            b.sleepEnabled = true; b.autonomy = true
            b.seed = seed &+ UInt64(a.id) &* 7919
            b.socialOthers = { [unowned r] in r.actors.compactMap(\.brain) }
        }
    }
    private func step() {
        for b in brains { b.idleNight = DayClock.shared.nightFactor; b.idleMorning = DayClock.shared.morningFactor; b.idleDeepNight = DayClock.shared.deepNightFactor }
        room.step()
    }

    /// Bedtime for all; wait until all three are napping; then `window` seconds in which nobody may leave the sleep. Returns a failure text or nil.
    private func holdRun(seed: UInt64, hour: Double, window: Float, select: Int?, interact: Int?, label: String) -> String? {
        make(seed: seed, hour: hour)
        if let s = select { care.select.doubleTap(s) }
        if let i = interact { care.noteInteraction(jelly: i) }
        care.bedtimeAll()
        var reached = Set<Int>()
        var log: [String] = []
        let total = Int((90 + window) * 60)
        var allAt = -1
        for n in 0..<total {
            step()
            if n % 600 == 0 { NSLog("SLEEPHOLD %@ t=%d stages=%@ kinds=%@", label, n / 60, brains.map { String($0.sleep.stage) }.joined(separator: ","), brains.map { String(describing: $0.idleState.kind) }.joined(separator: ",")) }
            for (i, b) in brains.enumerated() {
                if b.isNapping { reached.insert(i) }
                else if reached.contains(i), !b.isNapping, allAt >= 0 || true {
                    // left the settled sleep (after having been asleep): record once
                    if !log.contains(where: { $0.hasPrefix("j\(i) ") }) { log.append("j\(i) woke at \(Float(n) / 60)s stage=\(b.sleep.stage) wakeAsked=\(b.sleep.wakeAsked) kind=\(String(describing: b.idleState.kind))") }
                }
            }
            if allAt < 0, brains.allSatisfy({ $0.isNapping }) { allAt = n }
            if allAt >= 0, n - allAt > Int(window * 60) { break }
        }
        if allAt < 0 { return "\(label): never all asleep, stages \(brains.map { $0.sleep.stage })" }
        if !log.isEmpty { return "\(label): " + log.joined(separator: "; ") }
        if !brains.allSatisfy({ $0.isNapping }) { return "\(label): not all napping at the end" }
        return nil
    }

    func testBedtimeHoldsAtNightAcrossSeeds() {
        var fails: [String] = []
        for seed in Self.seeds {
            if let f = holdRun(seed: seed, hour: 23, window: 120, select: seed % 3 == 0 ? 2 : nil, interact: seed % 2 == 0 ? 2 : nil, label: "night seed \(seed)") { fails.append(f) }
        }
        XCTAssertTrue(fails.isEmpty, "\n" + fails.joined(separator: "\n"))
    }

    func testBedtimeHoldsInTheEveningAcrossSeeds() {
        var fails: [String] = []
        for hour in [20.7, 21.5] { for seed in Self.seeds {
            if let f = holdRun(seed: seed, hour: hour, window: 150, select: seed % 2 == 0 ? 2 : nil, interact: nil, label: "evening \(hour) seed \(seed)") { fails.append(f) }
        } }
        XCTAssertTrue(fails.isEmpty, "\n" + fails.joined(separator: "\n"))
    }

    func testBedtimeHoldsByDayAcrossSeeds() {
        var fails: [String] = []
        for seed in Self.seeds {
            if let f = holdRun(seed: seed, hour: 13, window: 120, select: seed % 3 == 0 ? 1 : nil, interact: seed % 2 == 0 ? 0 : nil, label: "day seed \(seed)") { fails.append(f) }
        }
        XCTAssertTrue(fails.isEmpty, "\n" + fails.joined(separator: "\n"))
    }

    /// THE BUG (phone, 3 Jelbies): the stage asks the touch play of the TOUCH TARGET (the last touched / selected / close-up Jelbie, Pip by default) for a
    /// "get up" every frame, and a body tilted past 1.0 rad counts as "left lying". The sleep pose (lieAngle 1.05 + the flop overshoot) is such a body, so
    /// the target Jelbie was righted ("touched": sleepWake) as soon as he settled, again and again. Every one of the three may be the target.
    func testTheTouchGetUpNeverWakesASleeper() {
        var fails: [String] = []
        for target in 0..<3 { for seed in Self.seeds {
            make(seed: seed, hour: 23)
            let play = TouchPlay(haptics: HapticDriver(sinks: []))
            care.bedtimeAll()
            var asleepAt: Int?
            var woke: String?
            for n in 0..<(100 * 60) {
                for b in brains { b.idleNight = DayClock.shared.nightFactor; b.idleDeepNight = DayClock.shared.deepNightFactor }
                let dt = room.actors[0].sim.stepDt
                for a in room.actors {
                    let hold = a.id == target ? play.getUpFrame(dt: dt, now: Double(n) * Double(dt), held: false, focusSpot: nil, sim: a.sim, brain: a.brain) : false
                    a.brain?.tick(sim: a.sim, skinner: a.skinner, dt: dt, touched: hold)
                    a.skinner.jelly.tick(brain: a.brain!, sim: a.sim, dt: dt)
                }
                care.tick(brain: room.actors[0].brain!, renderer: nil, dt: dt, sim: room.actors[0].sim)
                care.tickOthers(room.actors, dt: dt); care.tickRace(room.actors, dt: dt)
                for a in room.actors { a.sim.step() }
                if asleepAt == nil, brains.allSatisfy({ $0.isNapping }) { asleepAt = n }
                if asleepAt != nil, woke == nil, !brains.allSatisfy({ $0.isNapping }) { woke = "left the sleep at \(Float(n) / 60) s, stages \(brains.map { $0.sleep.stage }), getUps \(play.getUps)" }
            }
            if asleepAt == nil { fails.append("target \(target) seed \(seed): never all asleep (getUps \(play.getUps), stages \(brains.map { $0.sleep.stage }))") }
            else if let w = woke { fails.append("target \(target) seed \(seed): \(w)") }
        } }
        XCTAssertTrue(fails.isEmpty, "\n" + fails.joined(separator: "\n"))
    }
}
