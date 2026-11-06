//
//  HUDFixesTests.swift
//  Feed row lists only owned foods (an empty bag shows the one short line); the close-up's "too hungry to cuddle" notice follows the cuddle gate.
//

import XCTest
@testable import BobV1

@MainActor
final class HUDFixesTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    func testFeedRowListsOnlyOwnedFoods() {
        XCTAssertEqual(CareMenu.feedRowIDs(bag: ["popsicle": 3, "cookie": 2, "berries": 0, "pizza": 0]), ["popsicle", "cookie"], "exactly the ice pop and the cookie, in shop order")
    }

    func testEmptyBagListsNothingAndHasTheLine() {
        XCTAssertEqual(CareMenu.feedRowIDs(bag: ["berries": 0, "pizza": 0]), [])
        XCTAssertEqual(CareMenu.feedRowIDs(bag: [:]), [])
        XCTAssertEqual(CareMenu.noFoodLine, "No food. Visit the store.")
    }

    func testCuddleLineFollowsTheGate() {
        // blocked by hunger / thirst / both
        XCTAssertEqual(GameCare.cuddleBlockLine(name: "Teddy", mood: .grumpy, wanted: .hunger, hungry: true, thirsty: false), "Teddy is too hungry to cuddle")
        XCTAssertEqual(GameCare.cuddleBlockLine(name: "Teddy", mood: .grumpy, wanted: .thirst, hungry: false, thirsty: true), "Teddy is too thirsty to cuddle")
        XCTAssertEqual(GameCare.cuddleBlockLine(name: "Teddy", mood: .grumpy, wanted: .hunger, hungry: true, thirsty: true), "Teddy is too hungry and thirsty to cuddle")
        // not blocked: happy / okay, or love is exactly what he wants
        XCTAssertNil(GameCare.cuddleBlockLine(name: "Teddy", mood: .happy, wanted: nil, hungry: false, thirsty: false))
        XCTAssertNil(GameCare.cuddleBlockLine(name: "Teddy", mood: .okay, wanted: nil, hungry: false, thirsty: false))
        XCTAssertNil(GameCare.cuddleBlockLine(name: "Teddy", mood: .grumpy, wanted: .attention, hungry: false, thirsty: false))
    }

    func testNoticeShowsInTheCloseUpWhileHungryAndClearsWhenFed() {
        let c = GameCare(jellyCount: 1, persistent: false, defaults: UserDefaults(suiteName: "HUDFixes.1")!)
        Self.keep.append(c)
        c.focus.force(.focused); c.focusGroup.begin(ids: [0])
        c.needs(for: 0).set(.hunger, 0.1); c.needs(for: 0).set(.thirst, 1); c.needs(for: 0).set(.attention, 1)
        XCTAssertEqual(c.cuddleNotices.count, 1); XCTAssertTrue(c.cuddleNotices[0].hasSuffix("is too hungry to cuddle"), c.cuddleNotices.first ?? "")
        c.needs(for: 0).set(.hunger, 1)
        XCTAssertEqual(c.cuddleNotices, [], "need met: the notice is gone")
        c.needs(for: 0).set(.thirst, 0.1)
        XCTAssertEqual(c.cuddleNotices.count, 1)
        c.focus.force(.roaming)
        XCTAssertEqual(c.cuddleNotices, [], "no notice outside the close-up")
    }
}
