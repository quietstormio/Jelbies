//
//  OutingNowTests.swift
//  An outing asked during the welcome home after a race or a show starts at once: the welcome is cut, nothing is left greeting, callRunning is false.
//

import XCTest
@testable import BobV1

@MainActor
final class OutingNowTests: XCTestCase {
    private func hasCome(_ care: GameCare) -> Bool {
        care.queued.contains { if case .come = $0 { return true }; return false }
    }

    private func assertWelcomeCut(_ care: GameCare, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(care.raceBook.returner, "\(what): the welcome is over", file: file, line: line)
        XCTAssertTrue(care.greetPending.isEmpty, "\(what): nobody is left to greet", file: file, line: line)
        XCTAssertTrue(care.greetOthers.isEmpty, file: file, line: line)
        XCTAssertFalse(care.greeting, file: file, line: line)
        XCTAssertFalse(care.greetHop, file: file, line: line)
        XCTAssertFalse(care.callRunning, "\(what): callRunning gates group meals", file: file, line: line)
        XCTAssertFalse(hasCome(care), "\(what): no come in the queue", file: file, line: line)
    }

    private func check(_ welcome: (GameCare) -> Void, _ what: String) throws {
        let room = RaceTripTests.Room(count: 2)
        RaceTripTests.keep.append(room)
        let care = room.care
        let parkBefore = care.parkBlocker(), cafeBefore = care.cafeBlocker(), groomBefore = care.groomBlocker()
        try XCTSkipIf(parkBefore != nil, "the park is closed on this host right now (night): \(parkBefore ?? "")")
        welcome(care)
        XCTAssertNotNil(care.raceBook.returner, "\(what): the welcome is running")
        XCTAssertTrue(hasCome(care) || care.greeting, "\(what): Bob is greeting")
        XCTAssertEqual(care.parkBlocker(), parkBefore, "\(what): the welcome does not block the park")
        XCTAssertEqual(care.cafeBlocker(), cafeBefore, "\(what): nor the café")
        XCTAssertEqual(care.groomBlocker(), groomBefore, "\(what): nor the spa")
        XCTAssertNotEqual(care.groomBlocker(), "Finish this trip first.")
        XCTAssertFalse(care.raceBlocker(jelly: 0)?.hasPrefix("Welcome") ?? false)
        XCTAssertFalse(care.showBlocker(jelly: 0)?.hasPrefix("Welcome") ?? false)
        XCTAssertFalse(care.volleyBlocker(jelly: 0)?.hasPrefix("Welcome") ?? false)
        care.callRunning = true                                              // as if Bob were mid come-to-front
        care.requestPark()
        assertWelcomeCut(care, what)
    }

    func testParkRequestDuringARaceWelcomeEndsTheWelcome() throws {
        try check({ $0.raceWelcomeHome(1, won: true) }, "race welcome")
    }

    func testParkRequestDuringAShowWelcomeEndsTheWelcome() throws {
        try check({ $0.showWelcomeHome(1, won: true, again: false) }, "show welcome")
    }
}
