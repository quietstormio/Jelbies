//
//  VolleyFirstToThreeTests.swift
//  A match is first to 3 points (no win-by-2), and a "close" loss is a loss by one point (2-3), so the court unlock ("win, or three close ones") stays rare at this length.
//

import XCTest
@testable import BobV1

final class VolleyFirstToThreeTests: XCTestCase {
    private func play(_ order: [Int]) -> VolleySim {
        var s = VolleySim(mode: .match(.shore), mine: [VolleyStats(), VolleyStats()], seed: 1, firstServe: 0)
        for t in order where s.winner == nil { s.debugRally(possession: t, touches: 1); s.forcePoint(team: t) }
        return s
    }

    func testTheMatchEndsAtThreeWithNoWinByTwo() {
        XCTAssertEqual(VolleyTuning.pointsToWin, 3)
        let s = play([0, 1, 0, 1, 0])          // 3-2: over at once, one point clear is enough
        XCTAssertEqual(s.winner, 0); XCTAssertEqual(s.score, [3, 2])
        XCTAssertNil(play([0, 1, 0, 1]).winner)          // 2-2: still on
    }

    func testOnlyALossByOneIsClose() {
        let one = play([1, 0, 1, 0, 1])          // 2-3
        XCTAssertEqual(one.winner, 1); XCTAssertTrue(one.closeLoss)
        let two = play([1, 0, 1, 1])          // 1-3
        XCTAssertEqual(two.winner, 1); XCTAssertFalse(two.closeLoss)
        XCTAssertFalse(play([0, 0, 0]).closeLoss)          // a win is not a close loss
    }
}
