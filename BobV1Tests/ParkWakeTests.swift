//
//  ParkWakeTests.swift
//  park-wake-r1: by day a trip (park, café, Jelly Spa) is never refused because somebody sleeps: the sleepers get the SHORT wake, then everybody runs out together. At night the park says plainly
//  that it is bedtime. The player's own Naptime does not block a later trip. Built on RaceThreeTests.Room (the real GameCare + bodies); the hour is pinned (this runs on the real clock otherwise).
//

import XCTest
@testable import BobV1

@MainActor
final class ParkWakeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private typealias Room = RaceThreeTests.Room

    override func setUp() {
        DayClock.shared.forcedHour = 14
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        SleepOrder.reset(); GameMessageCenter.shared.clear()
    }
    override func tearDown() {
        DayClock.shared.forcedHour = 12
        GameMessageCenter.shared.clear()
        GameCamera.endPark(count: 3); GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); _ = GameCamera.camera(aspect: 440.0 / 956.0); RoomLayout.apply(RoomCatalog.home)
    }

    private func room(_ n: Int) -> Room {
        let r = Room(count: n); r.withPark = true; Self.keep.append(r)
        for a in r.actors { a.brain?.sleepEnabled = true; a.brain?.seed = 5 &+ UInt64(a.id) }
        return r
    }
    private func step(_ r: Room, _ n: Int = 1) {
        for _ in 0..<n {
            for a in r.actors { a.brain.map { $0.idleNight = DayClock.shared.nightFactor; $0.idleMorning = DayClock.shared.morningFactor; $0.idleDeepNight = DayClock.shared.deepNightFactor } }
            r.step(); r.care.tickCafe(r.actors, dt: 1 / 60); r.care.tickGroom(r.actors, dt: 1 / 60)
        }
    }
    private func run(_ r: Room, _ s: Float, until: (() -> Bool)? = nil) { for _ in 0..<Int(s * 60) { step(r); if until?() == true { break } } }
    private func sleep(_ r: Room, _ ids: [Int]) {
        for id in ids { r.actors[id].brain?.commandedGoodnight = true }
        run(r, 60) { ids.allSatisfy { r.actors[$0].brain?.isNapping == true } }
        run(r, 1)
        for id in ids { XCTAssertTrue(r.actors[id].brain?.isNapping == true, "control: \(id) is asleep") }
    }
    private func asleep(_ r: Room) -> [Int] { r.actors.filter { $0.brain?.isSleeping == true }.map(\.id) }
    private func said(_ ask: () -> Void) -> String? { let c = GameMessageCenter.shared; c.clear(); ask(); return c.current?.text }

    /// One, two, all asleep by day: the park is not refused, nobody is left asleep, they run out together and the trip starts.
    private func daytimePark(count: Int, sleepers: [Int]) {
        let r = room(count), c = r.care
        sleep(r, sleepers)
        XCTAssertNil(c.parkBlocker(), "asleep by day: the park is not refused")
        XCTAssertNil(said { c.requestPark() }, "and nothing is said: it just opens the picker")
        XCTAssertTrue(c.park.picking)
        c.startPark()
        XCTAssertTrue(c.outing.waking, "the sleepers are being woken first")
        XCTAssertEqual(c.parkBlocker() == nil, false, "a second ask meanwhile is answered, not stacked")
        for id in sleepers { XCTAssertTrue(r.actors[id].brain?.sleep.shortUp == true, "\(id): the SHORT get-up, not the slow morning wake") }
        for id in sleepers { XCTAssertFalse(r.actors[id].brain?.sleep.softWake == true, "\(id): not the staged soft wake") }
        var sawRun = false, lyingWhenRunning = false
        run(r, 30) {
            if c.outing.running { sawRun = true; if !self.asleep(r).isEmpty { lyingWhenRunning = true } }
            return c.park.phase != .off
        }
        XCTAssertTrue(sawRun, "everybody ran out of the room first")
        XCTAssertFalse(lyingWhenRunning, "nobody runs out lying down")
        XCTAssertFalse(c.outing.waking)
        XCTAssertNotEqual(c.park.phase, .off, "the park trip started")
        XCTAssertEqual(c.park.picked, Array(0..<count), "everybody together")
        run(r, 60) { c.park.phase == .playing }
        XCTAssertEqual(c.park.phase, .playing, "the park loaded")
        XCTAssertTrue(asleep(r).isEmpty, "all awake at the park: \(asleep(r))")
        XCTAssertEqual(Set(c.parkBook.comers), Set(0..<count), "all of them came")
    }
    func testOneAsleepAtThePark() { daytimePark(count: 3, sleepers: [1]) }
    func testTwoAsleepAtThePark() { daytimePark(count: 3, sleepers: [0, 2]) }
    func testAllAsleepAtThePark() { daytimePark(count: 3, sleepers: [0, 1, 2]) }
    func testTwoJelmikoOneAsleepAtThePark() { daytimePark(count: 2, sleepers: [1]) }
    func testSingleJelmikoAsleepAtThePark() { daytimePark(count: 1, sleepers: [0]) }

    // MARK: a sleeper who stays home is left alone

    /// What a sleeping stay-home looks like: still asleep, never asked to wake, nothing reset.
    private func untouched(_ r: Room, _ id: Int, _ what: String) {
        let b = r.actors[id].brain!
        XCTAssertTrue(b.isSleeping, "\(what): \(id) is still asleep")
        XCTAssertFalse(b.sleep.shortUp, "\(what): \(id) was never asked to wake")
        XCTAssertFalse(b.sleep.wakeAsked, "\(what): \(id) was never asked to wake")
        XCTAssertEqual(b.idleState.kind, .sleep, "\(what): \(id) is in the same sleep")
    }

    /// 1 of 3 to the Spa, the traveller awake or asleep, with a sleeping stay-home: the stay-home keeps sleeping and the trip starts.
    private func spa(goingAsleep: Bool) {
        let r = room(3), c = r.care
        c.groomBook.fixedDt = 1 / 60
        c.bath.wallet.add(100 - c.bath.wallet.count, silent: true)
        sleep(r, goingAsleep ? [0, 2] : [2])
        XCTAssertNil(c.groomBlocker())
        c.groom.openPicker(all: [0]); c.groom.picked = [0]
        c.startGroom(.quick)
        XCTAssertEqual(c.outing.waking, goingAsleep, "only a sleeping traveller is waited for")
        var sawRun = false
        run(r, 40) { if c.outing.running { sawRun = true }; return c.groom.inScene }
        XCTAssertTrue(c.groom.active, "the Spa trip started")
        XCTAssertTrue(sawRun, "the traveller ran out")
        XCTAssertTrue(r.actors[0].brain?.isSleeping != true, "the traveller is awake")
        untouched(r, 2, "spa")
        run(r, 3); untouched(r, 2, "spa, later")
    }
    func testSpaOneOfThreeAwakeWithASleepingStayHome() { spa(goingAsleep: false) }
    func testSpaOneOfThreeAsleepWithASleepingStayHome() { spa(goingAsleep: true) }

    /// The park with a pick list of two: the sleeper who goes wakes and comes; the sleeper who stays keeps sleeping and does not hold the fade.
    func testParkTwoOfThreeWithASleepingStayHome() {
        let r = room(3), c = r.care
        sleep(r, [1, 2])
        c.requestPark(); c.park.picked = [0, 1]
        c.startPark()
        XCTAssertTrue(c.outing.waking)
        run(r, 60) { c.park.phase == .playing }
        XCTAssertEqual(c.park.phase, .playing, "the park loaded")
        XCTAssertEqual(Set(c.parkBook.comers), [0, 1])
        XCTAssertTrue(r.actors[1].brain?.isSleeping != true, "the traveller is awake")
        untouched(r, 2, "park")
    }

    /// The player's own Naptime a moment ago does not block the trip: the newer choice wins.
    func testNaptimeJustNowDoesNotBlockTheTrip() {
        let r = room(3), c = r.care
        _ = c.bedtime(ids: [0, 1, 2]); run(r, 0.3)
        XCTAssertNil(c.parkBlocker()); XCTAssertNil(c.cafeBlocker().flatMap { $0 == .noDrops ? nil : $0 })
        c.requestPark(); c.startPark()
        XCTAssertTrue(c.nightRest.wanted.isEmpty, "the pending nap is cancelled")
        run(r, 30) { c.park.phase != .off }
        XCTAssertNotEqual(c.park.phase, .off)
        XCTAssertTrue(asleep(r).isEmpty)
    }

    /// The wake costs nothing: no mood, no need changes.
    func testTheWakeIsNotGrumpyAndNeedsAreUntouched() {
        let r = room(3), c = r.care
        sleep(r, [1])
        let before = (0..<3).map { c.needs(for: $0).level(.attention) }
        c.requestPark(); c.startPark()
        run(r, 3)
        XCTAssertFalse(r.actors[1].brain?.sleep.groggy == true, "not groggy")
        for i in 0..<3 { XCTAssertEqual(c.needs(for: i).level(.attention), before[i], accuracy: 0.02) }
    }

    /// The café and the Spa follow the same rule: a sleeper is not a refusal by day.
    func testCafeAndSpaAreNotRefusedForASleeper() {
        let r = room(3), c = r.care
        c.bath.wallet.add(100 - c.bath.wallet.count, silent: true)
        sleep(r, [2])
        XCTAssertNil(c.cafeBlocker()); XCTAssertNil(c.groomBlocker())
        XCTAssertNil(said { c.requestCafe() }, "the café starts waking him instead of refusing")
        XCTAssertTrue(c.outing.waking)
        run(r, 30) { c.cafe.active }
        XCTAssertTrue(c.cafe.active, "the café trip started"); XCTAssertTrue(asleep(r).isEmpty)
    }

    /// Night: refused as before, now with the bedtime wording; a sleeper is not woken for it.
    func testNightRefusesWithTheBedtimeLine() {
        DayClock.shared.forcedHour = 23
        let r = room(3), c = r.care
        step(r, 10)
        XCTAssertEqual(said { c.requestPark() }, "It's bedtime, so the park is closed. It opens in the morning!")
        XCTAssertFalse(c.park.picking); XCTAssertFalse(c.outing.waking)
        XCTAssertEqual(c.parkBlocker(), "It's bedtime, so the park is closed. It opens in the morning!")
        DayClock.shared.forcedHour = 21
        XCTAssertNotNil(c.parkBlocker(), "21:00 is already bedtime hours")
        DayClock.shared.forcedHour = 19.5
        XCTAssertNil(c.parkBlocker(), "19:30 is not")
    }
}
