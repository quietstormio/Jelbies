import XCTest
@testable import BobV1

/// 2026-11-06: friendships take ~1.3x longer, mostly by cutting passive proximity (the friendly emotes only a little).
final class ParkFriendSlowTests: XCTestCase {
    private struct Rates { var pps, social, friendly, bonus, home: Float }
    private let before = Rates(pps: 0.36, social: 4, friendly: 8, bonus: 2.5, home: 0.7)
    private let after = Rates(pps: ParkTuning.pointsPerSecond, social: ParkTuning.socialMul, friendly: ParkTuning.friendlyMul,
                              bonus: ParkTuning.friendlyStartBonus, home: ParkTuning.homeMul)

    /// Points with ONE visitor over a modelled stretch: seconds near doing nothing, in a generic social, and in `friendlyCount` friendly socials of 8 s each.
    private func points(_ r: Rates, plain: Float, social: Float, friendlyCount: Int, home: Bool) -> Float {
        let base = r.pps * (home ? r.home : 1)
        let fs = Float(friendlyCount) * 8
        return base * plain + base * r.social * social + base * r.friendly * fs + r.bonus * Float(friendlyCount)
    }

    func testParkVisitIsAboutThirtyPercentSlower() {
        // ~2 min near one visitor: 86 s standing, a 10 s generic social, 3 friendly socials of 8 s
        let b = points(before, plain: 86, social: 10, friendlyCount: 3, home: false)
        let a = points(after, plain: 86, social: 10, friendlyCount: 3, home: false)
        XCTAssertEqual(b, 0.36 * 86 + 14.4 + 69.12 + 7.5, accuracy: 0.5)
        XCTAssertEqual(b / a, 1.3, accuracy: 0.1, "before \(b) after \(a)")
        // standing about is cut harder than the emotes
        XCTAssertGreaterThan(before.pps / after.pps, 1.5)
        XCTAssertLessThan(before.pps * before.friendly / (after.pps * after.friendly), 1.3)
    }

    func testThresholdsUnchanged() {
        XCTAssertEqual(ParkTuning.palAt, 20); XCTAssertEqual(ParkTuning.friendAt, 45); XCTAssertEqual(ParkTuning.bestAt, 75)
    }

    func testOneSleepoverNightCannotMakeBestFriends() {
        // awake play only counts (both asleep = no points): ~2 min of evening play, 3 friendly socials, 10 s generic
        let b = points(before, plain: 86, social: 10, friendlyCount: 3, home: true)
        let a = points(after, plain: 86, social: 10, friendlyCount: 3, home: true)
        XCTAssertLessThan(a, ParkTuning.bestAt, "a sleepover evening gave \(a) (before \(b))")
        XCTAssertLessThan(a, b)
    }
}
