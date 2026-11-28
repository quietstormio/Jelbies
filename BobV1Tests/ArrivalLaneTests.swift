import XCTest
@testable import BobV1

/// arrival-lane-r1: the strip a new Jelmiko runs along (pure geometry).
final class ArrivalLaneTests: XCTestCase {
    func testTheStripIsTheEntryDepthFromTheLeftToPastTheSpot() {
        let l = ArrivalLaneShape(z: 0.5, spotX: -1)
        XCTAssertTrue(l.contains(SIMD2(-4, 0.5)))
        XCTAssertTrue(l.contains(SIMD2(-1, 1.5)))          // a margin each side
        XCTAssertTrue(l.contains(SIMD2(0.5, 0.5)))         // a margin past the spot
        XCTAssertFalse(l.contains(SIMD2(-3, 2.4)))         // beside the strip
        XCTAssertFalse(l.contains(SIMD2(1.5, 0.5)))        // well to the right
    }

    func testALegAcrossTheStripCrossesAndOneBesideItDoesNot() {
        let l = ArrivalLaneShape(z: 0, spotX: -1)
        XCTAssertTrue(l.crosses(SIMD2(-2, -3), SIMD2(-2, 3)))
        XCTAssertFalse(l.crosses(SIMD2(-2, 2.5), SIMD2(2, 3)))
        XCTAssertFalse(l.crosses(SIMD2(2, -1), SIMD2(2, 1.5)))
    }
}
