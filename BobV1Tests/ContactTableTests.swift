//
//  ContactTableTests.swift
//  User rule 3 (2026-11-04): ONE formula for every interactive emote, enforced in code. Every SocialKind has an explicit ContactStance row (no default / fallthrough class)
//  and the polish harness measures it; a new emote that misses either fails here. Checklist: docs/CONTACT_EMOTES.md "Adding an interactive emote".
//

import XCTest
@testable import BobV1

@MainActor
final class ContactTableTests: XCTestCase {
    func testEveryKindHasAnExplicitRowAndIsMeasured() {
        let measured = Set((ContactPolishTests.pairEntries + ContactPolishTests.groupEntries).compactMap { e -> SocialKind? in
            if case .social(let k) = e.scenario { return k }; return nil })
        for k in SocialKind.allCases {
            guard let row = ContactStance.table[k] else { XCTFail("SocialKind.\(k) has no ContactStance row (ContactStance.swift table)"); continue }
            XCTAssertNotEqual(row.cls, .none, "\(k): the row's class must be touching or proximity, never none")
            XCTAssertTrue(measured.contains(k), "\(k) is missing from ContactPolishTests.pairEntries / groupEntries (a new emote must be measured automatically)")
        }
    }

    /// Every touching row must walk (decide the meeting spot once) and hold at the plush press; a touching row with no press step is a default in disguise.
    func testTouchingRowsPressAtTheHold() {
        for (k, row) in ContactStance.table where row.cls == .touching && ![.bagSit, .cuddle].contains(k) {
            XCTAssertTrue(row.steps.contains { $0.target == ContactStance.hold }, "\(k): touching row without a hold/press step")
        }
    }

    /// A ring (group hug, circle dance) never WALKS in its hold: the drive walks everybody to a place that is the touch + 1.2 cm first, the hold only presses (a retargeting hold turned bodies through each other).
    func testRingHoldsPressWithoutWalking() {
        for k in [SocialKind.groupHug, .circleDance] {
            let hold = ContactStance.table[k]?.steps.first { $0.target == ContactStance.hold }
            XCTAssertNotNil(hold, "\(k) has a hold step")
            XCTAssertEqual(hold?.retargets, false, "\(k): the hold does not retarget walks")
        }
    }
}
