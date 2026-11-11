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

    func testAllowsPureFormWithInUse() {
        let off = ParkVisitPlan.Plan(visit: 1, seesaw: false, hopscotch: false)
        ParkVisitPlan.current = off
        for k in [DecorKind.seesaw, .hopscotch] {
            XCTAssertTrue(ParkVisitPlan.allows(k, outing: true, inUse: true), "\(k): off but in use, a friend may join")
            XCTAssertFalse(ParkVisitPlan.allows(k, outing: true, inUse: false), "\(k): off and not in use")
            XCTAssertTrue(ParkVisitPlan.allows(k, outing: false, inUse: false), "\(k): at home")
        }
        for k in [DecorKind.slide, .ball, .beanbag] {
            XCTAssertTrue(ParkVisitPlan.allows(k, outing: true, inUse: false), "\(k): never gated")
        }
        ParkVisitPlan.current = .all
        for k in [DecorKind.seesaw, .hopscotch] {
            XCTAssertTrue(ParkVisitPlan.allows(k, outing: true, inUse: false), "\(k): on")
        }
    }

    /// The shared-state form: the hopscotch line and the seesaw's seats count as "in use".
    func testAllowsReadsTheSharedState() {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        DecorField.shared.set(ParkToys.placed)
        defer { DecorField.shared.clear(); DecorField.shared.toys = ToyBook() }
        ParkVisitPlan.current = ParkVisitPlan.Plan(visit: 1, seesaw: false, hopscotch: false)
        XCTAssertFalse(ParkVisitPlan.allows(.hopscotch, outing: true))
        XCTAssertFalse(ParkVisitPlan.allows(.seesaw, outing: true))
        HopscotchLine.shared.enroll(ParkToys.hopscotchUID, 0)
        DecorField.shared.take(ParkToys.seesawUID, seat: 0, by: 0)
        XCTAssertTrue(ParkVisitPlan.allows(.hopscotch, outing: true), "a line is running")
        XCTAssertTrue(ParkVisitPlan.allows(.seesaw, outing: true), "a seat is taken")
        HopscotchLine.shared.remove(ParkToys.hopscotchUID, 0)
        DecorField.shared.leave(ParkToys.seesawUID, by: 0)
        XCTAssertFalse(ParkVisitPlan.allows(.hopscotch, outing: true))
        XCTAssertFalse(ParkVisitPlan.allows(.seesaw, outing: true))
    }
}

/// The plan inside a headless park (HopscotchTests' park lab, three Jelbies with their autonomy on): a visit without the seesaw has no autonomous seesaw sit, the other toys are still used,
/// the Jelbies do not stand around more, and a commanded seesaw start still works.
@MainActor
final class ParkVisitPlanSimTests: XCTestCase {
    override func setUp() {
        ParkVisitPlan.current = .all
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        HopscotchTuning.joinChance = 0.35
    }
    override func tearDown() {
        ParkVisitPlan.current = .all
        DecorField.shared.clear(); ToyTuning.settle = 5; HopscotchTuning.joinChance = 0.35
        HopscotchLine.shared.prune(keeping: [])
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    struct Tally { var starts = 0, seesawSits = 0, hopscotch = 0, slide = 0, commandedOK: Bool? }

    /// About `minutes` sim-minutes in the park with three Jelbies (outingPlay on, like the visit); `commanded` ends with a commanded seesaw start.
    func runPark(plan: ParkVisitPlan.Plan, seed: UInt64, minutes: Int, commanded: Bool) -> Tally {
        ParkVisitPlan.current = plan
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); HopscotchLine.shared.prune(keeping: [])
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let starts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4)]
        let lab = SocialTests.Lab(n: 3, positions: starts, quiet: false, seed: seed)
        for r in lab.rigs {
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = true
        }
        DecorField.shared.set(ParkToys.placed)
        DecorField.shared.toys.news.removeAll()
        var t = Tally()
        var prev: [IdleKind?] = [nil, nil, nil]
        for _ in 0..<(60 * 60 * minutes) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            for (i, r) in lab.rigs.enumerated() {
                let now = r.brain.idleState.kind
                if prev[i] == nil, let k = now {
                    t.starts += 1
                    let uid = r.brain.idleState.decorUID
                    if k == .decorSit, uid >= 0, DecorField.shared.foot(uid)?.kind == .seesaw { t.seesawSits += 1 }
                    if k == .decorHopscotch { t.hopscotch += 1 }
                    if k == .decorSlide { t.slide += 1 }
                }
                prev[i] = now
            }
        }
        if commanded {
            let r = lab.rigs[0]
            r.brain.abortAll(r.sim, r.skinner)
            t.commandedOK = r.brain.startCommandedDecor(.decorSit, only: .seesaw, r.sim, r.skinner)
        }
        return t
    }

    func testSeesawOffVisitHasNoAutonomousSeesawAndNoStandingAround() {
        let minutes = 6
        var all = Tally(), off = Tally()
        for (n, seed) in [UInt64(5), 17].enumerated() {
            let a = runPark(plan: .all, seed: seed, minutes: minutes, commanded: false)
            let o = runPark(plan: ParkVisitPlan.Plan(visit: 1, seesaw: false, hopscotch: true), seed: seed, minutes: minutes, commanded: n == 0)
            print("[visitplan] seed \(seed): all in play \(a), seesaw off \(o)")
            all.starts += a.starts; all.seesawSits += a.seesawSits; all.hopscotch += a.hopscotch; all.slide += a.slide
            off.starts += o.starts; off.seesawSits += o.seesawSits; off.hopscotch += o.hopscotch; off.slide += o.slide
            if n == 0 { off.commandedOK = o.commandedOK }
        }
        let jelbieMinutes = Double(3 * minutes * 2)
        let rateAll = Double(all.starts) / jelbieMinutes, rateOff = Double(off.starts) / jelbieMinutes
        print("[visitplan] idle starts per Jelbie-minute: all in play \(rateAll), seesaw off \(rateOff) (\(rateAll > 0 ? rateOff / rateAll : 0) of it); seesaw sits \(all.seesawSits) vs \(off.seesawSits); hopscotch \(all.hopscotch) vs \(off.hopscotch); slide \(all.slide) vs \(off.slide)")
        XCTAssertGreaterThan(all.starts, 0)
        XCTAssertEqual(off.seesawSits, 0, "no autonomous seesaw sit on a visit without the seesaw")
        XCTAssertGreaterThan(off.hopscotch, 0, "the hopscotch is still used")
        XCTAssertGreaterThan(off.slide, 0, "the slide is still used")
        XCTAssertGreaterThanOrEqual(rateOff, 0.9 * rateAll, "they must not stand around more")
        XCTAssertEqual(off.commandedOK, true, "a commanded seesaw start still works")
    }
}
