//
//  ParkNoMealsTests.swift
//  park-no-meals-r1: "They shouldn't eat or drink at the park." While the Park or the Camp is on (any phase), every food / drink request is refused with the park's / camp's own line
//  on the message bar and nothing starts: no order, no tray, nobody eating. Back home the same request works. Rig: DiningJellyTests.Room.
//

import XCTest
@testable import BobV1

@MainActor
final class ParkNoMealsTests: XCTestCase {
    override func tearDown() { GameMessageCenter.shared.clear(); DayClock.shared.forcedHour = 12; super.tearDown() }

    private func room() -> DiningJellyTests.Room {
        DayClock.shared.forcedHour = 12
        let r = DiningJellyTests.Room(count: 2)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        r.care.park.onSwap = { _ in }          // (the world swap is not under test: only the trip's phases)
        r.run(0.5)
        return r
    }

    /// Steps the trip (and the room) until it reaches `phase`.
    private func go(_ r: DiningJellyTests.Room, to phase: ParkTrip.Phase) {
        var n = 0
        while r.care.park.phase != phase, n < 4000 { r.care.park.step(dt: 1.0 / 60); r.tick(); n += 1 }
        XCTAssertEqual(r.care.park.phase, phase)
    }

    private func start(_ r: DiningJellyTests.Room, camp: Bool) {
        if camp { r.care.park.beginCamp() } else { r.care.park.resume(picked: [0, 1]) }
    }

    private func assertNothingStarted(_ r: DiningJellyTests.Room, _ tag: String, file: StaticString = #filePath, line: UInt = #line) {
        let c = r.care
        r.run(1.0)
        XCTAssertNil(c.wanted, tag, file: file, line: line); XCTAssertNil(c.meal, tag, file: file, line: line); XCTAssertNil(c.groupWanted, tag, file: file, line: line)
        XCTAssertFalse(c.groupActive, tag, file: file, line: line); XCTAssertFalse(c.trayOut, tag, file: file, line: line)
        XCTAssertEqual(c.dining.phase, .absent, tag, file: file, line: line)
        XCTAssertFalse(r.sawEating.contains(true), tag, file: file, line: line)
        XCTAssertFalse(r.actors.contains { $0.brain?.activity == .eating || $0.brain?.activity == .drinking }, tag, file: file, line: line)
    }

    /// Every route a food / drink request can come by.
    private func askEveryWay(_ r: DiningJellyTests.Room, line expected: String, tag: String) {
        let c = r.care, bar = GameMessageCenter.shared
        c.store.grant("berries", 1)
        bar.clear(); c.feed()
        XCTAssertEqual(bar.current?.text, expected, "\(tag): the bar says it")
        XCTAssertEqual(bar.current?.priority, .important, tag)
        c.feed(jelly: 0); c.drink("water"); c.water(); c.water(jelly: 1); c.feedSnack("berries"); c.feedSnack("berries", jelly: 0)
        XCTAssertFalse(GameRouter.shared.perform(.feed(0), care: c) && c.trayOut, tag)
        _ = GameRouter.shared.perform(.water(1), care: c)
        c.voice.execute(JellyCommand(who: .everyone, action: .feed), care: c, brain: r.actors[0].brain!)
        c.voice.execute(JellyCommand(who: .jellies([0]), action: .drink), care: c, brain: r.actors[0].brain!)
        XCTAssertEqual(c.orderBlocker(Consumables.water), expected, tag)
        XCTAssertEqual(HUDMenu.disabledReason(.feed, .group, care: c), expected, "\(tag): the menu row says the same")
        XCTAssertEqual(HUDMenu.disabledReason(.drink, .group, care: c), expected, tag)
        assertNothingStarted(r, tag)
    }

    func testNoFoodOrDrinkAtTheParkInAnyPhase() {
        let r = room()
        start(r, camp: false)
        for phase in [ParkTrip.Phase.goOut, .arriveHold, .playing, .leaveHold] {
            if phase == .leaveHold { r.care.park.goHome() }
            go(r, to: phase)
            askEveryWay(r, line: "No food or drinks at the park", tag: "park \(phase)")
        }
    }

    func testNoFoodOrDrinkAtCampInAnyPhase() {
        let r = room()
        start(r, camp: true)
        for phase in [ParkTrip.Phase.goOut, .arriveHold, .playing, .leaveHold] {
            if phase == .leaveHold { r.care.park.goHome() }
            go(r, to: phase)
            askEveryWay(r, line: "No food or drinks at camp", tag: "camp \(phase)")
        }
    }

    func testOtherTripsKeepTheirLineAndHomeFeedsAgain() {
        let r = room()
        start(r, camp: false); go(r, to: .playing)
        askEveryWay(r, line: "No food or drinks at the park", tag: "park")
        r.care.park.finish()
        XCTAssertFalse(r.care.park.active)
        XCTAssertNil(r.care.orderBlocker(Consumables.water), "home: nothing blocks")
        r.care.feed()
        XCTAssertTrue(r.care.trayOut, "back home the tray comes out")
        XCTAssertNotNil(r.care.groupWanted ?? r.care.wanted)
    }

    /// A trip never starts under a tray: the fade-out cancels (`parkFadeBlocked`), so nobody can be mid-meal when the park is up.
    func testAParkTripDoesNotStartWhileATrayIsOut() {
        for camp in [false, true] {
            let r = room()
            r.care.store.grant("berries", 1)
            r.care.feed(); XCTAssertTrue(r.care.trayOut)
            start(r, camp: camp)
            XCTAssertTrue(r.care.parkFadeBlocked)
            r.care.tickPark(r.actors, dt: 1.0 / 60)
            XCTAssertEqual(r.care.park.phase, .off, "camp \(camp): the trip is cancelled under the tray")
            XCTAssertFalse(r.care.park.inScene)
        }
    }
}
