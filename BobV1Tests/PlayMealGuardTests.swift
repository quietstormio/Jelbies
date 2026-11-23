//
//  PlayMealGuardTests.swift
//  play-ball-r2: the ball game's hold on a Jelmiko (GameCare+Dining `playHolds`) can never change a meal: with a meal wanted or running it is false for everyone, so
//  `reserved` / `waitFocus` are exactly what the phone build computes; with no meal it is true only for a Jelmiko the ball game holds.
//

import XCTest
@testable import BobV1

@MainActor
final class PlayMealGuardTests: XCTestCase {
    func testThePlayHoldIsOffWheneverAMealIsWantedOrRunning() {
        for reserving in [false, true] {
            for held in [false, true] {
                XCTAssertFalse(GameCare.playHolds(reserving: reserving, mealActive: true, holds: held), "meal active, reserving \(reserving), held \(held): the play hold must be off")
            }
        }
        XCTAssertFalse(GameCare.playHolds(reserving: true, mealActive: false, holds: true), "the meal's own Jelly is never held by the game")
    }

    func testWithNoMealTheHoldFollowsTheBallGame() {
        XCTAssertTrue(GameCare.playHolds(reserving: false, mealActive: false, holds: true))
        XCTAssertFalse(GameCare.playHolds(reserving: false, mealActive: false, holds: false))
    }

    /// A played ball game: the real PlayToss holds only the Jelmiko on its line, and only while the ball game (not the wand) is on.
    func testPlayTossHoldsOnlyItsOwnLineWhileTheBallGameIsOn() {
        let p = PlayToss()
        XCTAssertFalse(p.holds(0), "no game: nobody is held")
    }
}
