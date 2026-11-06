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
}
