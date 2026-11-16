//
//  SpringStatesTests.swift
//  The Jelly Spring's button, status line and Town square for every state of (home, Camp, wallet, price): pure functions, no views.
//

import XCTest
@testable import BobV1

final class SpringStatesTests: XCTestCase {
    private func pick(first: Bool = false, home: Int, camp: Int, wallet: Int, rare: Bool = false, special: Bool = false, hasPick: Bool = true) -> SpringStates.Pick {
        SpringStates.pick(first: first, hasPick: hasPick, home: home, camp: camp, wallet: wallet, price: AdoptionPrice.next(home: home, camp: camp, rare: rare, special: special))
    }

    func testHomeHasRoomIsTodaysFlow() {
        XCTAssertEqual(SpringStates.roomText(home: 1, camp: 0), "1/3 at home")
        XCTAssertEqual(SpringStates.roomText(home: 2, camp: 0), "2/3 at home")
        XCTAssertEqual(pick(home: 1, camp: 0, wallet: 10_000), .price(500))
        XCTAssertEqual(pick(home: 2, camp: 0, wallet: 10_000), .price(800))
        XCTAssertEqual(pick(home: 2, camp: 0, wallet: 10_000, rare: true), .price(1100))
        XCTAssertEqual(pick(home: 2, camp: 0, wallet: 100), .needMore(700))
        XCTAssertEqual(SpringStates.namingText(name: "Rex", home: 2, camp: 0), "Bring Rex home")
        XCTAssertTrue(SpringStates.townEnabled(home: 2, camp: 0)); XCTAssertEqual(SpringStates.townSub(home: 2, camp: 0), "2/3 at home")
        XCTAssertFalse(SpringStates.goesToCamp(home: 2, camp: 0))
        XCTAssertEqual(pick(first: true, home: 0, camp: 0, wallet: 0), .free)
        XCTAssertEqual(SpringStates.pickText(.free), "This one!")
    }
    func testHomeFullCampHasRoomSendsTheNewOneToCamp() {
        for camp in [0, 3, JellyCamp.cap - 1] {
            XCTAssertEqual(SpringStates.roomText(home: 3, camp: camp), "3/3 at home \u{00B7} new one goes to Camp")
            XCTAssertEqual(pick(home: 3, camp: camp, wallet: 10_000), .price(800), "camp \(camp): what a third costs")
            XCTAssertTrue(SpringStates.enabled(pick(home: 3, camp: camp, wallet: 10_000)))
            XCTAssertEqual(SpringStates.namingText(name: "Rex", home: 3, camp: camp), "Send Rex to Camp")
            XCTAssertTrue(SpringStates.townEnabled(home: 3, camp: camp), "the Town square is open")
            XCTAssertEqual(SpringStates.townSub(home: 3, camp: camp), "3/3 at home")
            XCTAssertTrue(SpringStates.goesToCamp(home: 3, camp: camp))
        }
        XCTAssertEqual(pick(home: 3, camp: 0, wallet: 10_000, rare: true), .price(1100))
        XCTAssertEqual(pick(home: 3, camp: 0, wallet: 10_000, special: true), .price(2000))
        XCTAssertEqual(pick(home: 3, camp: 0, wallet: 799), .needMore(1)); XCTAssertFalse(SpringStates.enabled(.needMore(1)))
        XCTAssertEqual(SpringStates.celebrationText(name: "Rex", toCamp: true), "Rex is off to Jelmiko Camp!")
        XCTAssertEqual(SpringStates.celebrationText(name: "Rex", toCamp: false), "Rex is coming home!")
        XCTAssertEqual(SpringStates.roomNote(name: "Rex"), "Rex is at Jelmiko Camp")
    }
    func testHomeAndCampFullDisablesEverythingAndSpendsNothing() {
        let p = pick(home: 3, camp: JellyCamp.cap, wallet: 1_000_000)
        XCTAssertEqual(p, .full)
        XCTAssertFalse(SpringStates.enabled(p))
        XCTAssertEqual(SpringStates.pickText(p), "Home and Camp are full")
        XCTAssertEqual(SpringStates.roomText(home: 3, camp: JellyCamp.cap), "Home and Camp are full")
        XCTAssertEqual(pick(home: 3, camp: JellyCamp.cap, wallet: 1_000_000, special: true), .full)
        XCTAssertFalse(SpringStates.townEnabled(home: 3, camp: JellyCamp.cap)); XCTAssertEqual(SpringStates.townSub(home: 3, camp: JellyCamp.cap), "Home and Camp are full")
        XCTAssertTrue(SpringStates.bothFull(home: 3, camp: JellyCamp.cap))
    }
    func testNothingPickedYet() {
        XCTAssertEqual(pick(home: 3, camp: 0, wallet: 5000, hasPick: false), .choose)
        XCTAssertEqual(SpringStates.pickText(.choose), "Pick one of the three")
        XCTAssertFalse(SpringStates.enabled(.choose))
    }
}
