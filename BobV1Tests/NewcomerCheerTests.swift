import XCTest
@testable import BobV1

/// The pure parts of the bought Jelbie's welcome: the cheer's hop schedule, who chirps, and who goes back to bed.
final class NewcomerCheerTests: XCTestCase {
    func testThreeHopsAboutHalfASecondApartAndTheCheerOutlastsThem() {
        let h = NewcomerCheer.hopTimes
        XCTAssertEqual(h.count, 3)
        for i in 1..<h.count { XCTAssertEqual(h[i] - h[i - 1], 0.55, accuracy: 0.05) }
        XCTAssertGreaterThan(NewcomerCheer.endAt, h.last! + 0.8)
    }

    func testVoicesAreFewAndRotate() {
        let cast = [0, 1, 2]
        XCTAssertEqual(NewcomerCheer.voices(hop: 0, cast: cast, newcomer: 2), [2, 0])
        for hop in 1...2 { XCTAssertEqual(NewcomerCheer.voices(hop: hop, cast: cast, newcomer: 2).count, 1) }
        XCTAssertNotEqual(NewcomerCheer.voices(hop: 1, cast: cast, newcomer: 2), NewcomerCheer.voices(hop: 2, cast: cast, newcomer: 2))
        XCTAssertEqual(NewcomerCheer.voices(hop: 1, cast: [2], newcomer: 2), [])
    }

    func testBackToBedOnlyWhenTheHouseWasAsleepAndItIsBedtime() {
        XCTAssertEqual(NewcomerCheer.backToBed(slept: [0, 1], newcomer: 2, bedtimeHours: true), [0, 1, 2])
        XCTAssertEqual(NewcomerCheer.backToBed(slept: [0, 1], newcomer: 2, bedtimeHours: false), [])
        XCTAssertEqual(NewcomerCheer.backToBed(slept: [], newcomer: 2, bedtimeHours: true), [])
    }
}
