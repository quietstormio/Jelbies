//
//  HighlightActsTests.swift
//  Every highlight action that settles on a Blob goes up the `highlightActs` counter the care menu observes, also when `highlighted` itself does not change
//  (the same Blob highlighted again), so the menu opens each time.
//

import XCTest
@testable import BobV1

@MainActor
final class HighlightActsTests: XCTestCase {
    nonisolated(unsafe) static var keep: [BlobSelect] = []

    private func two() -> BlobSelect {
        let s = BlobSelect(); Self.keep.append(s)
        s.setBlobs([SelectBlob(id: 0, name: "Bob"), SelectBlob(id: 1, name: "Pip")])
        return s
    }
    private func run(_ s: BlobSelect, _ sec: Float) { for _ in 0..<Int(sec * 60) { s.tick(dt: 1.0 / 60) } }

    func testAPickCountsAtOnceAndOnlyOnce() {
        let s = two()
        XCTAssertEqual(s.highlightActs, 0)
        s.pick(0)
        XCTAssertEqual(s.highlightActs, 1, "counted when the pick starts: the menu does not wait for the glow")
        XCTAssertEqual(s.selectedID, 0); XCTAssertNil(s.highlighted)
        s.pick(0)
        XCTAssertEqual(s.highlightActs, 1, "the same draw asked again is not a new action")
        run(s, 4)
        XCTAssertEqual(s.highlighted, 0)
        XCTAssertEqual(s.highlightActs, 1, "the glow ending settles the pick: no second count, so a menu the player closed meanwhile stays shut")
    }
    func testThePickedOneIsTheHighlightedJellyFromTheFirstFrame() {
        let s = two()
        s.pick(1)
        XCTAssertEqual(s.highlighted ?? s.selectedID, 1, "what GameCare.highlightedJelly reads: the same value at the tap and after the glow")
        run(s, 4)
        XCTAssertEqual(s.highlighted ?? s.selectedID, 1)
    }
    func testTheSameBlobHighlightedAgainCountsAgain() {
        let s = two()
        s.pick(0); run(s, 4)
        let before = s.highlightActs
        s.rehighlight()
        XCTAssertEqual(s.highlighted, 0, "the highlight did not change")
        XCTAssertEqual(s.highlightActs, before + 1, "but the action is counted: the menu opens again")
    }
    func testNothingHighlightedIsNotCounted() {
        let s = two()
        s.rehighlight()
        XCTAssertEqual(s.highlightActs, 0)
        s.pick(1); run(s, 4); s.clearHighlight()
        XCTAssertNil(s.highlighted ?? s.selectedID)
        let n = s.highlightActs
        s.rehighlight()
        XCTAssertEqual(s.highlightActs, n, "a cleared highlight opens nothing")
    }
    func testAnInstantSleeperPickCountsEvenOnTheSameBlob() {
        let s = two()
        s.pick(0, quietHop: true, instant: true)
        XCTAssertEqual(s.highlightActs, 1)
        s.pick(0, quietHop: true, instant: true)
        XCTAssertEqual(s.highlightActs, 2)
        XCTAssertEqual(s.highlighted, 0)
    }
    func testTheOtherBlobCounts() {
        let s = two()
        s.pick(0); run(s, 4)
        let n = s.highlightActs
        s.pick(1); run(s, 4)
        XCTAssertEqual(s.highlighted, 1)
        XCTAssertEqual(s.highlightActs, n + 1)
    }
}
