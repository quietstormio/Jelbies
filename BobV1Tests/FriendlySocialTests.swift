//
//  FriendlySocialTests.swift
//  The six "we like each other" socials (BlobSocial+Friends.swift) each start, run to the end and let go, with both on the floor; the guest's clock rules
//  (Park/GuestBook.swift): the sleepover ends the next morning, a visit that ended long ago has "gone home", one that ended a moment ago is waved off.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FriendlySocialTests: XCTestCase {
    func testEachFriendlyKindRunsToTheEnd() {
        for kind in [SocialKind.chestBump, .highFive, .hum, .cheekSquish, .twirl, .hopAlong] {
            let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.6, 0.5), SIMD2(1.0, 0.5)], quiet: true, seed: 3)
            let a = lab.rigs[0], b = lab.rigs[1]
            XCTAssertTrue(a.brain.socialStart(kind, with: b.brain, a.sim), "\(kind) starts")
            var ended = false
            for _ in 0..<(60 * 40) {
                lab.tick(watching: false)
                if a.brain.social == nil, b.brain.social == nil, lab.events[0].contains(where: { if case .ended(let k, _, _) = $0 { return k == kind }; return false }) { ended = true; break }
            }
            XCTAssertTrue(ended, "\(kind) ended")
            XCTAssertTrue(lab.events[0].contains { if case .ended(let k, _, .done) = $0 { return k == kind }; return false }, "\(kind) ended well")
            for r in lab.rigs { XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-5, "\(kind): on the floor") }
        }
    }

    func testClosePairsPickFriendlyKindsMoreOften() {
        let lab = SocialTests.Lab(n: 2, quiet: true)
        let a = lab.rigs[0].brain, b = lab.rigs[1].brain
        XCTAssertEqual(a.friendPickMul([b]), 1, accuracy: 1e-4)
        a.socialBook.close[b.steerID] = FriendTuning.closeMul[3]
        XCTAssertGreaterThan(a.friendPickMul([b]), 1.3)
        a.socialBook.close[b.steerID] = FriendTuning.closeMul[0]
        XCTAssertLessThan(a.friendPickMul([b]), 1)
    }

    func testGuestClockRules() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let evening = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 19, minute: 0))!
        let end = GuestRules.endsAt(.sleepover, arrival: evening, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day, .hour, .minute], from: end), DateComponents(day: 25, hour: 7, minute: 30))
        let late = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 2, minute: 0))!
        XCTAssertEqual(cal.component(.day, from: GuestRules.endsAt(.sleepover, arrival: late, calendar: cal)), 25)
        let play = GuestRules.endsAt(.playDate, arrival: evening, calendar: cal, roll: 0.5)
        XCTAssertEqual(play.timeIntervalSince(evening), 750, accuracy: 1)

        var v = GuestVisit(visitor: 1, kind: .sleepover, invitedAt: 100)
        XCTAssertEqual(GuestRules.verdict(v, now: 200), .stay, "invited, not here yet")
        XCTAssertEqual(GuestRules.verdict(v, now: 100 + GuestTuning.inviteExpires + 1), .dropped)
        v.arrivedAt = 100; v.endsAt = 1000
        XCTAssertEqual(GuestRules.verdict(v, now: 900), .stay)
        XCTAssertEqual(GuestRules.verdict(v, now: 1000 + 600), .goodbye, "the app is back in the morning: the goodbye")
        XCTAssertEqual(GuestRules.verdict(v, now: 1000 + GuestTuning.graceAfterSleepover + 1), .wentHome)
        XCTAssertEqual(GuestRules.note("Poppy", .sleepover), "Poppy went home after the sleepover")
        v.kind = .playDate
        XCTAssertEqual(GuestRules.verdict(v, now: 1000 + GuestTuning.graceAfterPlayDate + 1), .wentHome)
    }

    func testGuestBookKeepsOneVisitAcrossRelaunch() {
        let suite = UserDefaults(suiteName: "GuestBookTests.\(UUID().uuidString)")!
        let book = GuestBook(defaults: suite)
        XCTAssertTrue(book.invite(visitor: 3, kind: .sleepover, now: 500))
        XCTAssertFalse(book.invite(visitor: 4, kind: .playDate, now: 501), "only one guest at a time")
        book.markArrived(now: 600)
        let again = GuestBook(defaults: suite)
        XCTAssertEqual(again.visit?.visitor, 3)
        XCTAssertEqual(again.visit?.kind, .sleepover)
        XCTAssertTrue(again.visit?.arrived ?? false)
        again.finish()
        XCTAssertNil(GuestBook(defaults: suite).visit)
    }
}
