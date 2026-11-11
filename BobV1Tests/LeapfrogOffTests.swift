//
//  LeapfrogOffTests.swift
//  The leapfrog vault is no longer picked on its own (2026-11-11): gone from FriendTuning.base and every taste set, the move itself stays.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class LeapfrogOffTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }
    override func tearDown() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12 }

    func testLeapfrogIsNotInThePickTable() {
        XCTAssertFalse(FriendTuning.base.contains { $0.0 == .leapfrog }, "base table holds no leapfrog")
        for (feature, kinds) in FriendTuning.taste { XCTAssertFalse(kinds.contains(.leapfrog), "taste of \(feature) holds no leapfrog") }
        XCTAssertNotNil(SocialKind(rawValue: "leapfrog"), "the move itself is kept for the forced tests")
    }

    func testThePairPickNeverOffersLeapfrog() {
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.0, 0.6), SIMD2(1.0, 0.6)], quiet: true, seed: 5)
        let a = lab.rigs[0].brain, b = lab.rigs[1].brain
        for x in [a, b] { x.anticsEnabled = true; x.sleepEnabled = true }
        var printed = false
        for taste in [JellyFeature.none, .spines] {          // (.spines = Pip, whose taste used to hold the move)
            a.personalityOverride = taste
            for grumpy in [false, true] {
                for x in [a, b] { x.socialAbort(nil); x.idleState.kind = nil; x.socialBook.lastKind = nil }
                let base: [(SocialKind, Float)] = [(.boop, 1.5), (.follow, 2), (.squabble, grumpy ? SocialTuning.squabbleGrumpy : SocialTuning.squabbleBase)]
                let w = a.socialPlayWeights(base: base, partner: b, others: [b], grumpy: grumpy)
                let kinds = Set(w.map { $0.0 })
                XCTAssertFalse(kinds.contains(.leapfrog), "no leapfrog (taste \(taste), grumpy \(grumpy))")
                XCTAssertGreaterThanOrEqual(kinds.count, 10, "a varied table (taste \(taste), grumpy \(grumpy)): \(kinds.count) kinds")
                if !printed {
                    print("LEAPFROG-OFF-TABLE taste \(taste) grumpy \(grumpy): " + w.map { "\($0.0.rawValue)=\(String(format: "%.2f", $0.1))" }.joined(separator: " "))
                    printed = true
                }
            }
        }
    }
}
