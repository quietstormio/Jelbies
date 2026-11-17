//
//  LoveSlowerTests.swift
//  2026-11-16: love (attention) falls half as fast, time away alone never takes it under 0.35 (just above the grumpy line), and a pair / group
//  emote that ends well gives each of the player's own Jelmiko +0.03 love, filling only up to 0.8. Visitors get nothing.
//

import XCTest
@testable import BobV1

@MainActor
final class LoveSlowerTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []         // the runtime aborts when BlobNeeds are released (see MelonModel)

    func testInAppAttentionDecayIsHalfTheOldRate() {
        let n = BlobNeeds(persists: false); Self.keep.append(n)
        for k in NeedKind.allCases { n.set(k, 1) }
        for _ in 0..<3600 { n.step(dt: 1) }          // one hour awake
        XCTAssertEqual(n.level(.attention), 1 - 0.125, accuracy: 0.002, "0.125 per hour (was 0.25)")
        // the nap / night rate is half of that again
        let m = BlobNeeds(persists: false); Self.keep.append(m)
        m.set(.attention, 1)
        for _ in 0..<3600 { m.step(dt: 1, drainScale: NeedsTuning.napDrain) }
        XCTAssertEqual(m.level(.attention), 1 - 0.0625, accuracy: 0.002)
    }

    func testAwayDecayIsHalfAndAttentionStopsAt035ButFoodAndWaterAreUnchanged() {
        XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.attention), 12, "0.083 per hour (was 0.167)")
        XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.hunger), 20); XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.thirst), 16)
        XCTAssertEqual(NeedsTuning.hoursToEmpty(.hunger), 0.3); XCTAssertEqual(NeedsTuning.hoursToEmpty(.thirst), 0.2)
        let hour: TimeInterval = 3600
        let one = AwayMath.needLevels([1, 1, 1], seconds: hour)
        XCTAssertEqual(one[0], 1 - 1.0 / 20, accuracy: 1e-5); XCTAssertEqual(one[1], 1 - 1.0 / 16, accuracy: 1e-5); XCTAssertEqual(one[2], 1 - 1.0 / 12, accuracy: 1e-5)
        for secs in [8 * hour, 24 * hour, 400 * 24 * hour] {
            let v = AwayMath.needLevels([1, 1, 1], seconds: secs)
            XCTAssertGreaterThanOrEqual(v[2], 0.35 - 1e-6, "time away alone never makes love lonely-grumpy")
            XCTAssertEqual(v[0], max(1 - Float(secs / hour) / 20, 0.2), accuracy: 1e-5, "hunger keeps its own floor")
        }
        XCTAssertEqual(AwayMath.needLevels([1, 1, 1], seconds: 400 * 24 * hour)[2], 0.35, accuracy: 1e-6)
        XCTAssertEqual(AwayMath.needLevels([1, 1, 1], seconds: 400 * 24 * hour)[0], 0.2, accuracy: 1e-6)
        XCTAssertEqual(AwayMath.needLevels([1, 1, 0.1], seconds: 8 * hour)[2], 0.1, accuracy: 1e-6, "already lower (in-app neglect): left alone")
        XCTAssertNotEqual(AwayMath.mood(of: AwayMath.needLevels([1, 1, 1], seconds: 400 * 24 * hour).enumerated().map { $0.offset == 2 ? $0.element : 1 }), .grumpy)
    }

    func testACompletedPairEmoteRaisesBothByThreeHundredths() {
        let care = GameCare(jellyCount: 2, persistent: false)
        care.needs(for: 0).set(.attention, 0.5); care.needs(for: 1).set(.attention, 0.4)
        care.socialSessionCompleted(id: 0, kind: .spinHug, end: .done); care.socialSessionCompleted(id: 1, kind: .spinHug, end: .done)
        XCTAssertEqual(care.needs(for: 0).level(.attention), 0.53, accuracy: 1e-5)
        XCTAssertEqual(care.needs(for: 1).level(.attention), 0.43, accuracy: 1e-5)
        care.socialSessionCompleted(id: 0, kind: .groupHug, end: .done)
        XCTAssertEqual(care.needs(for: 0).level(.attention), 0.56, accuracy: 1e-5, "group emotes count too")
        // not completed, or not a friendly one
        care.socialSessionCompleted(id: 1, kind: .spinHug, end: .aborted); care.socialSessionCompleted(id: 1, kind: .spinHug, end: .stopped)
        care.socialSessionCompleted(id: 1, kind: .squabble, end: .done)
        XCTAssertEqual(care.needs(for: 1).level(.attention), 0.43, accuracy: 1e-5)
    }

    func testTheSocialGainStopsAtEightTenths() {
        let care = GameCare(jellyCount: 1, persistent: false)
        let n = care.needs(for: 0)
        n.set(.attention, 0.79); care.socialSessionCompleted(id: 0, kind: .swayHug, end: .done)
        XCTAssertEqual(n.level(.attention), 0.8, accuracy: 1e-6, "from below it can reach 0.8")
        care.socialSessionCompleted(id: 0, kind: .swayHug, end: .done)
        XCTAssertEqual(n.level(.attention), 0.8, accuracy: 1e-6, "never above")
        n.set(.attention, 0.95); care.socialSessionCompleted(id: 0, kind: .swayHug, end: .done)
        XCTAssertEqual(n.level(.attention), 0.95, accuracy: 1e-6, "an already fuller one is not pulled down")
        n.gain(.attention, 0.5)
        XCTAssertEqual(n.level(.attention), 1, accuracy: 1e-6, "cuddles and play still fill to 1")
    }

    func testAVisitorGetsNothing() {
        let care = GameCare(jellyCount: 1, persistent: false)
        care.needs(for: 0).set(.attention, 0.5)
        care.socialSessionCompleted(id: 7, kind: .spinHug, end: .done)          // a visitor's id is beyond the player's own
        XCTAssertEqual(care.needs(for: 0).level(.attention), 0.5, accuracy: 1e-6)
    }

    func testAWarmSessionsStartPlusEndGainNeverTakesLoveAboveEightTenthsFromSocialAlone() {
        let care = GameCare(jellyCount: 1, persistent: false)
        let n = care.needs(for: 0)
        n.set(.attention, 0.77)
        // start gain (tickSocialLove) then end gain (socialSessionCompleted), repeated
        for _ in 0..<5 {
            n.gain(.attention, SocialLoveTuning.gain, upTo: NeedsTuning.socialLoveCap)
            care.socialSessionCompleted(id: 0, kind: .cuddle, end: .done)
        }
        XCTAssertEqual(n.level(.attention), 0.8, accuracy: 1e-6)
        n.gain(.attention, 0.1)
        XCTAssertEqual(n.level(.attention), 0.9, accuracy: 1e-6, "the player's own play still fills past 0.8")
    }
}
