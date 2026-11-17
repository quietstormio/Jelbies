//
//  WakeOnLaunchTests.swift
//  A COLD launch: the game clock is never touched, the back-at-night arrival does not put anyone to bed, whoever is asleep AT launch gets the slow staggered wake, and at night the bedtime
//  logic keeps off for `NightRestTuning.coldLaunchGrace` (Goodnight still works). A return from the background behaves as before. Built on the real GameCare + three bodies (RaceTripTests.Room).
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
        NightRestTuning.idleBedtime = 180; NightRestTuning.coldLaunchGrace = 180
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
    @discardableResult
    private func go(_ s: Float, until: (() -> Bool)? = nil) -> Bool { for _ in 0..<Int(s * 60) { step(); if until?() == true { return true } }; return until?() ?? false }
    private func putToBed() {
        NightRestTuning.sendToBed(brains)
        go(60, until: { self.brains.allSatisfy { $0.isNapping } })
        go(1)
    }
    /// Per Jelmiko, the first sim second the slow roll-up (stage 4 of a soft wake, after the lag and stir) began.
    private func coldRun(seconds: Float) -> [Float?] {
        var first = [Float?](repeating: nil, count: brains.count)
        for i in 0..<Int(seconds * 60) {
            step()
            for (k, b) in brains.enumerated() where first[k] == nil && b.idleState.kind == .sleep && b.sleep.stage == 4 && b.sleep.softWake { first[k] = Float(i) / 60 }
        }
        return first
    }
    private var anyAsleep: Bool { brains.contains { $0.isSleeping } }

    /// Cold launch at 23:00 after 10 min away: the clock stays, nobody arrives asleep, no curtain hold.
    func testColdLaunchAtNightKeepsTheClockAndNobodyArrivesAsleep() {
        make(hour: 23)
        care.launched(away: 600)
        XCTAssertFalse(care.nightRest.arrivalAsleep)
        XCTAssertEqual(DayClock.shared.realHour, 23, accuracy: 0.001)
        go(12)
        XCTAssertEqual(DayClock.shared.realHour, 23, accuracy: 0.001)
        XCTAssertFalse(anyAsleep, "they arrive awake: \(brains.map { $0.sleep.stage })")
        XCTAssertGreaterThan(care.nightRest.coldGraceLeft, 0, "the night grace runs")
    }

    /// Somebody asleep at launch for another reason: the slow, staggered wake, one after another; the clock stays.
    func testASleeperAtLaunchGetsTheSlowStaggeredWake() {
        make(hour: 23)
        putToBed()
        XCTAssertTrue(brains.allSatisfy { $0.isNapping }, "control: asleep")
        care.launched(away: 600)
        XCTAssertEqual(DayClock.shared.realHour, 23, accuracy: 0.001)
        let first = coldRun(seconds: 14)
        XCTAssertTrue(first.allSatisfy { $0 != nil }, "everybody got the slow wake: \(first)")
        let t = first.compactMap { $0 }.sorted()
        XCTAssertGreaterThan(t.last! - t.first!, 0.3, "staggered: \(t)")
        go(14)
        XCTAssertFalse(anyAsleep, "all up: \(brains.map { $0.sleep.stage })")
        XCTAssertEqual(DayClock.shared.realHour, 23, accuracy: 0.001)
    }

    /// No bedtime during the grace (the idle rule would otherwise fire at 5 s), then the normal bedtime.
    func testNoBedtimeDuringTheGraceThenANormalBedtime() {
        NightRestTuning.idleBedtime = 5; NightRestTuning.coldLaunchGrace = 40
        make(hour: 23)
        care.launched(away: 600)
        go(35)
        XCTAssertFalse(anyAsleep, "inside the grace nobody goes to bed")
        XCTAssertTrue(go(60, until: { self.brains.allSatisfy { $0.isNapping } }), "after it the normal bedtime puts all three down: \(brains.map { $0.sleep.stage })")
    }

    /// Goodnight during the grace works at once.
    func testGoodnightDuringTheGraceWorks() {
        NightRestTuning.idleBedtime = 5; NightRestTuning.coldLaunchGrace = 1000
        make(hour: 23)
        care.launched(away: 600)
        go(3)
        XCTAssertTrue(care.bedtimeAll())
        XCTAssertTrue(go(60, until: { self.brains.allSatisfy { $0.isNapping } }), "asleep: \(brains.map { $0.sleep.stage })")
        go(15)
        XCTAssertTrue(brains.allSatisfy { $0.isSleeping && !$0.sleep.wakeAsked && $0.sleep.stirT < 0 }, "and the cold wake did not touch them")
    }

    /// Put to bed after launch (before the cold wake has run): never woken by it.
    func testBedAfterLaunchIsNotWokenByTheColdWake() {
        make(hour: 13)
        care.launched(away: 0)
        XCTAssertTrue(care.nightRest.coldWakeIDs.isEmpty)
        NightRestTuning.sendToBed(brains)
        go(20)
        XCTAssertFalse(care.nightRest.coldWakePending)
        XCTAssertTrue(brains.allSatisfy { $0.isSleeping && !$0.sleep.wakeAsked && $0.sleep.stirT < 0 }, "still asleep: \(brains.map { $0.sleep.stage })")
    }

    /// A return from the background at night after 10 min: arrives asleep, as before; no cold wake, no grace.
    func testBackgroundReturnAtNightStillArrivesAsleep() {
        make(hour: 23)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        care.leftActive(at: t0)
        care.returnedActive(at: t0.addingTimeInterval(600))
        XCTAssertTrue(care.nightRest.arrivalAsleep)
        XCTAssertFalse(care.nightRest.coldWakePending)
        XCTAssertEqual(care.nightRest.coldGraceLeft, 0)
        go(4)
        XCTAssertTrue(brains.allSatisfy { $0.isNapping }, "asleep within 4 s: \(brains.map { $0.sleep.stage })")
        go(20)
        XCTAssertTrue(brains.allSatisfy { $0.isNapping }, "and they stay down")
        XCTAssertEqual(DayClock.shared.realHour, 23, accuracy: 0.001)
    }

    /// Day cold launch: no grace, clock unchanged; a sleeper gets the slow wake.
    func testDayColdLaunchOnlyWakesTheSleeper() {
        make(hour: 13)
        putToBed()
        care.launched(away: 600)
        XCTAssertEqual(care.nightRest.coldGraceLeft, 0)
        XCTAssertEqual(DayClock.shared.realHour, 13, accuracy: 0.001)
        let first = coldRun(seconds: 14)
        XCTAssertTrue(first.allSatisfy { $0 != nil }, "slow wake for each: \(first)")
        go(14)
        XCTAssertFalse(anyAsleep)
    }
}
