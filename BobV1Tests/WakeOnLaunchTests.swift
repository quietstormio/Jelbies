//
//  WakeOnLaunchTests.swift
//  A COLD launch wakes whoever is asleep (the slow, staggered wake); at night the clock first moves to the morning. A return from the background changes nothing.
//  Built on the real GameCare + three bodies (RaceTripTests.Room), as NightRestTests.
//

import XCTest
@testable import BobV1

@MainActor
final class WakeOnLaunchTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var room: RaceTripTests.Room!
    private var care: GameCare { room.care }

    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        SleepOrder.reset()
    }
    override func tearDown() {
        DayClock.shared.forcedHour = 12
        NightRestTuning.idleBedtime = 180
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }
    private func make(hour: Double) {
        DayClock.shared.forcedHour = hour
        let r = RaceTripTests.Room(); Self.keep.append(r); room = r
        for a in r.actors {
            guard let b = a.brain else { continue }
            b.sleepEnabled = true; b.autonomy = true; b.seed = 5 &+ UInt64(a.id)
            b.socialOthers = { [unowned r] in r.actors.compactMap(\.brain) }
        }
    }
    private var brains: [BlobBrain] { room.actors.compactMap(\.brain) }
    private func step() {
        for b in brains { b.idleNight = DayClock.shared.nightFactor; b.idleMorning = DayClock.shared.morningFactor; b.idleDeepNight = DayClock.shared.deepNightFactor }
        room.step()
    }
    private func go(_ s: Float, until: (() -> Bool)? = nil) { for _ in 0..<Int(s * 60) { step(); if until?() == true { return } } }
    /// Runs a cold launch and records, per Jelmiko, the first sim second the slow roll-up (stage 4 of a soft wake, after the lag and stir) began.
    private func coldRun(seconds: Float) -> [Float?] {
        var first = [Float?](repeating: nil, count: brains.count)
        for i in 0..<Int(seconds * 60) {
            step()
            for (k, b) in brains.enumerated() where first[k] == nil && b.idleState.kind == .sleep && b.sleep.stage == 4 && b.sleep.softWake { first[k] = Float(i) / 60 }
        }
        return first
    }
    private func putToBed() {
        NightRestTuning.sendToBed(brains)
        go(60, until: { self.brains.allSatisfy { $0.isNapping } })
        go(1)
    }

    func testColdLaunchAtNightGivesMorningClockAndStaggeredSlowWake() {
        make(hour: 23)
        putToBed()
        XCTAssertTrue(brains.allSatisfy { $0.isNapping }, "control: all asleep \(brains.map { $0.sleep.stage })")
        care.launched(away: 0)
        XCTAssertEqual(DayClock.shared.realHour, GameClockTuning.wakeHour, accuracy: 0.01, "the clock moved to the morning")
        let first = coldRun(seconds: 14)
        XCTAssertTrue(first.allSatisfy { $0 != nil }, "everybody got the slow wake: \(first)")
        let times = first.compactMap { $0 }.sorted()
        XCTAssertGreaterThan(times.last! - times.first!, 0.3, "staggered, not on one frame: \(times)")
        go(14)
        XCTAssertTrue(brains.allSatisfy { !$0.isSleeping }, "all up and nobody back in bed: \(brains.map { $0.sleep.stage })")
    }

    func testColdLaunchByDayWakesTheSleeperAndLeavesTheClock() {
        make(hour: 13)
        putToBed()
        XCTAssertTrue(brains.allSatisfy { $0.isNapping }, "control: asleep by day")
        care.launched(away: 0)
        XCTAssertEqual(DayClock.shared.realHour, 13, accuracy: 0.001, "daytime: clock unchanged")
        let first = coldRun(seconds: 14)
        XCTAssertTrue(first.allSatisfy { $0 != nil }, "slow wake for each: \(first)")
        go(14)
        XCTAssertTrue(brains.allSatisfy { !$0.isSleeping }, "all up")
    }

    func testBackgroundReturnChangesNothing() {
        make(hour: 23)
        putToBed()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        care.leftActive(at: t0)
        care.returnedActive(at: t0.addingTimeInterval(2 * 3600))
        XCTAssertFalse(care.nightRest.coldWakePending, "a return is not a launch")
        XCTAssertEqual(DayClock.shared.realHour, 23, accuracy: 0.001)
        go(20)
        XCTAssertTrue(brains.allSatisfy { $0.isNapping }, "still asleep: \(brains.map { $0.sleep.stage })")
    }

    func testTheClockRuleOnItsOwn() {
        let d = UserDefaults(suiteName: "wakelaunch.\(UUID().uuidString)")!
        let c = DayClock(defaults: d, now: { Date(timeIntervalSince1970: 1_800_000_000) }, uptime: { 0 })
        c.forcedHour = nil
        for (h, moves) in [(23.0, true), (3.0, true), (21.0, true), (18.0, false), (7.05, false), (9.0, false), (13.0, false)] {
            let t = (c.gameTime / 24).rounded(.down) * 24 + h
            c.forcedHour = h
            XCTAssertEqual(c.coldLaunchToMorning(), moves, "hour \(h)")
            if moves { XCTAssertEqual(c.realHour, GameClockTuning.wakeHour, accuracy: 0.001); _ = t }
            else { XCTAssertEqual(c.realHour, h, accuracy: 0.001) }
        }
        // the real game clock (no forced hour): 23:00 -> next day 07:00, no lapse; 03:00 -> the same day's 07:00; daytime untouched
        c.forcedHour = nil
        let e = DayClock(defaults: UserDefaults(suiteName: "wakelaunch.\(UUID().uuidString)")!, now: { Date(timeIntervalSince1970: 1_800_000_000) }, uptime: { 0 })
        e.resetForNewGame()                                   // Day 1, 08:00
        XCTAssertFalse(e.coldLaunchToMorning()); XCTAssertEqual(e.gameTime, 8, accuracy: 0.001)
    }
}
