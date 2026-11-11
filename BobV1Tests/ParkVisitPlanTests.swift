//
//  ParkVisitPlanTests.swift
//  Which park toys the Jelbies use on their own during a visit (Park/ParkVisitPlan.swift): the draw's guards and rates, the persisted counter, `allows`, and the test-run bypass.
//

import XCTest
@testable import BobV1

@MainActor
final class ParkVisitPlanTests: XCTestCase {
    var suites: [String] = []

    override func setUp() { ParkVisitPlan.current = .all }
    override func tearDown() {
        ParkVisitPlan.current = .all
        for s in suites { UserDefaults.standard.removePersistentDomain(forName: s) }
        suites = []
    }

    func freshDefaults() -> UserDefaults {
        let name = "ParkVisitPlanTests.\(UUID().uuidString)"
        suites.append(name)
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: the draw

    func testDrawGuardsAndRatesOverTenThousandVisits() {
        var sOff = 0, hOff = 0
        var sOn = 0, hOn = 0
        var sMaxOff = 0, hMaxOff = 0
        var prev: (Bool, Bool)?
        var sOnOn = 0, sOffOff = 0, hOnOn = 0, hOffOff = 0
        let n = 10_000
        for v in 1...n {
            let d = ParkVisitPlan.draw(visit: v, seesawOff: sOff, hopscotchOff: hOff)
            XCTAssertTrue(d.seesaw || d.hopscotch, "visit \(v): both off")
            sOff = d.seesaw ? 0 : sOff + 1; hOff = d.hopscotch ? 0 : hOff + 1
            sMaxOff = max(sMaxOff, sOff); hMaxOff = max(hMaxOff, hOff)
            if d.seesaw { sOn += 1 }; if d.hopscotch { hOn += 1 }
            if let p = prev {
                if p.0 && d.seesaw { sOnOn += 1 }; if !p.0 && !d.seesaw { sOffOff += 1 }
                if p.1 && d.hopscotch { hOnOn += 1 }; if !p.1 && !d.hopscotch { hOffOff += 1 }
            }
            prev = (d.seesaw, d.hopscotch)
        }
        let sRate = Double(sOn) / Double(n), hRate = Double(hOn) / Double(n)
        print("[visitplan] seesaw in play \(sRate), hopscotch in play \(hRate); longest off run \(sMaxOff) / \(hMaxOff); on-on \(sOnOn)/\(hOnOn), off-off \(sOffOff)/\(hOffOff)")
        XCTAssertLessThanOrEqual(sMaxOff, 2)
        XCTAssertLessThanOrEqual(hMaxOff, 2)
        XCTAssertGreaterThanOrEqual(sRate, 0.55); XCTAssertLessThanOrEqual(sRate, 0.75)
        XCTAssertGreaterThanOrEqual(hRate, 0.55); XCTAssertLessThanOrEqual(hRate, 0.75)
        XCTAssertGreaterThan(sOnOn, 0, "the seesaw sequence is a strict alternation (no on, on)")
        XCTAssertGreaterThan(sOffOff, 0, "the seesaw sequence is a strict alternation (no off, off)")
        XCTAssertGreaterThan(hOnOn, 0, "the hopscotch sequence is a strict alternation (no on, on)")
        XCTAssertGreaterThan(hOffOff, 0, "the hopscotch sequence is a strict alternation (no off, off)")
    }

    func testDrawIsDeterministic() {
        for v in 1...200 {
            let a = ParkVisitPlan.draw(visit: v, seesawOff: 0, hopscotchOff: 1)
            let b = ParkVisitPlan.draw(visit: v, seesawOff: 0, hopscotchOff: 1)
            XCTAssertTrue(a.seesaw == b.seesaw && a.hopscotch == b.hopscotch)
        }
    }

    func testStreakForcesOn() {
        for v in 1...500 {
            XCTAssertTrue(ParkVisitPlan.draw(visit: v, seesawOff: 2, hopscotchOff: 0).seesaw)
            XCTAssertTrue(ParkVisitPlan.draw(visit: v, seesawOff: 0, hopscotchOff: 2).hopscotch)
            let both = ParkVisitPlan.draw(visit: v, seesawOff: 2, hopscotchOff: 2)
            XCTAssertTrue(both.seesaw && both.hopscotch)
        }
    }

    // MARK: begin

    func testBeginPersistsAndContinues() {
        let d = freshDefaults()
        XCTAssertNil(d.dictionary(forKey: ParkVisitPlan.key), "an empty store")
        // the first visit is drawn like any other (visit 1, no streaks)
        let first = ParkVisitPlan.begin(defaults: d)
        let want1 = ParkVisitPlan.draw(visit: 1, seesawOff: 0, hopscotchOff: 0)
        XCTAssertEqual(first.visit, 1)
        XCTAssertTrue(first.seesaw == want1.seesaw && first.hopscotch == want1.hopscotch)
        XCTAssertEqual(ParkVisitPlan.current, first)
        // carry the streaks by hand over 60 visits, reading the store fresh each time
        var sOff = want1.seesaw ? 0 : 1, hOff = want1.hopscotch ? 0 : 1
        for v in 2...60 {
            let saved = d.dictionary(forKey: ParkVisitPlan.key)
            XCTAssertEqual(saved?["visit"] as? Int, v - 1)
            XCTAssertEqual(saved?["seesawOff"] as? Int, sOff)
            XCTAssertEqual(saved?["hopscotchOff"] as? Int, hOff)
            let p = ParkVisitPlan.begin(defaults: d)
            let w = ParkVisitPlan.draw(visit: v, seesawOff: sOff, hopscotchOff: hOff)
            XCTAssertEqual(p.visit, v)
            XCTAssertTrue(p.seesaw == w.seesaw && p.hopscotch == w.hopscotch, "visit \(v)")
            sOff = w.seesaw ? 0 : sOff + 1; hOff = w.hopscotch ? 0 : hOff + 1
        }
    }

    func testBeginUsesOnlyItsOwnKey() {
        let d = freshDefaults()
        _ = ParkVisitPlan.begin(defaults: d)
        let keys = d.persistentDomain(forName: suites.last!).map { Array($0.keys) } ?? []
        XCTAssertEqual(keys, [ParkVisitPlan.key])
    }

    func testStandardDefaultsUnderXCTestAreAllInPlayAndWriteNothing() {
        let before = UserDefaults.standard.object(forKey: ParkVisitPlan.key)
        XCTAssertNil(before)
        for _ in 0..<20 {
            let p = ParkVisitPlan.begin()
            XCTAssertEqual(p, .all)
            XCTAssertTrue(ParkVisitPlan.current.seesaw && ParkVisitPlan.current.hopscotch)
        }
        XCTAssertNil(UserDefaults.standard.object(forKey: ParkVisitPlan.key), "the standard defaults must stay untouched")
    }

    // MARK: allows

    func testAllows() {
        ParkVisitPlan.current = ParkVisitPlan.Plan(visit: 1, seesaw: false, hopscotch: false)
        for k in [DecorKind.seesaw, .hopscotch, .slide, .ball, .beanbag] { XCTAssertTrue(ParkVisitPlan.allows(k, outing: false), "\(k) at home") }
        XCTAssertFalse(ParkVisitPlan.allows(.seesaw, outing: true))
        XCTAssertFalse(ParkVisitPlan.allows(.hopscotch, outing: true))
        XCTAssertTrue(ParkVisitPlan.allows(.slide, outing: true))
        XCTAssertTrue(ParkVisitPlan.allows(.ball, outing: true))
        ParkVisitPlan.current = ParkVisitPlan.Plan(visit: 2, seesaw: true, hopscotch: false)
        XCTAssertTrue(ParkVisitPlan.allows(.seesaw, outing: true))
        XCTAssertFalse(ParkVisitPlan.allows(.hopscotch, outing: true))
        ParkVisitPlan.current = ParkVisitPlan.Plan(visit: 3, seesaw: false, hopscotch: true)
        XCTAssertFalse(ParkVisitPlan.allows(.seesaw, outing: true))
        XCTAssertTrue(ParkVisitPlan.allows(.hopscotch, outing: true))
    }
}
