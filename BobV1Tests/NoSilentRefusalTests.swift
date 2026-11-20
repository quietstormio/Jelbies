//
//  NoSilentRefusalTests.swift
//  THE RULE: a refused start never returns silently. Every blocker that stops the Spa, the Café, the Park, Camp, a race, a show or a match says why on the message bar
//  (UI/GameMessageCenter.swift `refuse`). Rig: DiningJellyTests.Room (as CafeTests).
//

import XCTest
@testable import BobV1

@MainActor
final class NoSilentRefusalTests: XCTestCase {
    override func tearDown() {
        RoomLayout.apply(RoomCatalog.home)
        DecorField.shared.set([])
        DayClock.shared.forcedHour = 12
        GameMessageCenter.shared.clear()
        super.tearDown()
    }

    private func room() -> DiningJellyTests.Room {
        DayClock.shared.forcedHour = 12
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        r.care.bath.wallet.add(100 - r.care.bath.wallet.count, silent: true)
        step(r, 1)
        return r
    }
    private func step(_ r: DiningJellyTests.Room, _ s: Float, until: (() -> Bool)? = nil) {
        for _ in 0..<Int(s * 60) {
            r.tick()
            r.care.tickRace(r.actors, dt: 1.0 / 60)
            r.care.tickCafe(r.actors, dt: 1.0 / 60)
            r.care.tickDecor(dt: 1.0 / 60)
            if let until, until() { break }
        }
    }

    /// Runs `ask` and returns what the bar said (nil = silence).
    private func said(_ ask: () -> Void) -> String? {
        let c = GameMessageCenter.shared
        c.clear()
        ask()
        return c.current?.text
    }

    func testNightClosesTheSpaTheCafeAndTheParkOutLoud() {
        let r = room()
        DayClock.shared.forcedHour = 23; step(r, 0.1)
        XCTAssertEqual(said { r.care.requestGroom() }, "The Jelly Spa is closed at night. Come back in the morning!")
        XCTAssertEqual(said { r.care.requestCafe() }, CafeBlock.night.message)
        XCTAssertEqual(said { r.care.requestPark() }, "The park is closed at night. Come back in the morning!")
        XCTAssertEqual(TownRefusals.closedSub, "Closed until morning")
    }

    func testAMealOutStopsARaceAShowAndAMatchOutLoud() {
        let r = room()
        r.care.store.grant("berries", 3); r.care.feed(); step(r, 0.2)
        XCTAssertNotNil(r.care.raceBlocker(jelly: 0), "a meal is out")
        let race = said { r.care.startRace(jelly: 0) }
        XCTAssertTrue(race?.hasPrefix("A meal is out") == true, race ?? "silent")
        let show = said { r.care.startShow(jelly: 0) }
        XCTAssertTrue(show?.hasPrefix("A meal is out") == true, show ?? "silent")
        let volley = said { r.care.startVolley(jelly: 0, mode: .match(.sandcastle)) }
        XCTAssertNotNil(volley, "a match refused for a meal is not silent")
    }

    func testEveryStartRefusalSpeaksForAnUnknownJelmiko() {
        let r = room()
        for (name, ask) in [("race", { r.care.startRace(jelly: 99) }), ("show", { r.care.startShow(jelly: 99) }), ("volley", { r.care.startVolley(jelly: 99, mode: .match(.sandcastle)) })] as [(String, () -> Void)] {
            XCTAssertEqual(said(ask), "No such Jelmiko.", "\(name): a refused start is never silent")
        }
    }

    func testTheCafeBlockersAllSpeak() {
        let r = room()
        r.care.arranging = true
        XCTAssertEqual(said { r.care.requestCafe() }, CafeBlock.arranging.message); r.care.arranging = false
        r.care.bath.wallet.add(7 - r.care.bath.wallet.count, silent: true)
        XCTAssertEqual(said { r.care.requestCafe() }, CafeBlock.noDrops.message)
    }

    func testAMutedLobbyButtonSaysWhyAndStartsNothing() {
        var started = false
        let c = GameMessageCenter.shared; c.clear()
        LobbyBottomBar.tap(blocked: true, why: "Alien is asleep. Let them rest first.", play: { started = true })
        XCTAssertFalse(started); XCTAssertEqual(c.current?.text, "Alien is asleep. Let them rest first."); XCTAssertEqual(c.current?.priority, .important)
        c.clear()
        LobbyBottomBar.tap(blocked: true, why: nil, play: { started = true })
        XCTAssertEqual(c.current?.text, GameMessageCenter.fallback, "no reason is still not silence")
        c.clear()
        LobbyBottomBar.tap(blocked: false, why: nil, play: { started = true })
        XCTAssertTrue(started); XCTAssertNil(c.current)
    }

    func testRefuseIsImportantAndNeverEmpty() {
        let c = GameMessageCenter(); c.autoSchedule = false; c.tipShowing = { false }
        c.refuse(""); XCTAssertEqual(c.current?.text, GameMessageCenter.fallback); XCTAssertEqual(c.current?.priority, .important)
    }

    func testTheSpringSaysWhyItIsClosed() {
        XCTAssertTrue(TownRefusals.springFull.contains("Home and Camp are full"))
    }
}
