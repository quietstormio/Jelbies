//
//  ParkVisitPlanTests.swift
//  Which park toys the Jelbies use on their own during a visit (Park/ParkVisitPlan.swift): the draw (both pieces at every visit), the persisted counter, `allows`, and the test-run bypass.
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

    func testEveryVisitHasBothPieces() {
        for v in 1...20 {
            let d = ParkVisitPlan.draw(visit: v, seesawOff: 0, hopscotchOff: 0)
            XCTAssertTrue(d.seesaw, "visit \(v): the seesaw is in play")
            XCTAssertTrue(d.hopscotch, "visit \(v): the hopscotch court is in play")
            // the saved streaks never change the answer
            let b = ParkVisitPlan.draw(visit: v, seesawOff: 2, hopscotchOff: 2)
            XCTAssertTrue(b.seesaw && b.hopscotch, "visit \(v): streaks are ignored")
        }
    }

    // MARK: begin

    /// 20 consecutive visits through the persisted counter (each one reading the store fresh, as a relaunch does): the counter advances from any starting value and every visit has both pieces.
    func testBeginAdvancesCounterAndAlwaysHasBoth() {
        for start in [0, 1, 7] {
            let d = freshDefaults()
            if start > 0 { d.set(["visit": start, "seesawOff": 0, "hopscotchOff": 0], forKey: ParkVisitPlan.key) }
            for v in 1...20 {
                let p = ParkVisitPlan.begin(defaults: d)
                XCTAssertEqual(p.visit, start + v)
                XCTAssertEqual(ParkVisitPlan.current, p)
                XCTAssertEqual(d.dictionary(forKey: ParkVisitPlan.key)?["visit"] as? Int, start + v)
                XCTAssertTrue(p.seesaw && p.hopscotch, "visit \(p.visit): both pieces")
            }
        }
    }

    /// The counter survives a relaunch: a store written by one run is read by the next, which continues from it.
    func testCounterSurvivesRelaunch() {
        let d = freshDefaults()
        XCTAssertEqual(ParkVisitPlan.begin(defaults: d).visit, 1)
        XCTAssertEqual(ParkVisitPlan.begin(defaults: d).visit, 2)
        ParkVisitPlan.current = .all          // a relaunch: the in-memory plan is gone, the store stays
        let p = ParkVisitPlan.begin(defaults: d)
        XCTAssertEqual(p.visit, 3)
        XCTAssertTrue(p.seesaw && p.hopscotch)
        XCTAssertEqual(d.dictionary(forKey: ParkVisitPlan.key)?["visit"] as? Int, 3)
    }

    /// Every visit places the slide, the seesaw and the court; the forcing argument and the default plan show everything too.
    func testEveryPieceIsPlacedAtEveryVisit() {
        let d = freshDefaults()
        for _ in 0..<20 {
            let p = ParkVisitPlan.begin(defaults: d)
            let kinds = ParkVisitPlan.placedToday.map(\.kind)
            XCTAssertTrue(kinds.contains(.slide), "visit \(p.visit): the slide is there")
            XCTAssertTrue(kinds.contains(.seesaw), "visit \(p.visit): the seesaw is there")
            XCTAssertTrue(kinds.contains(.hopscotch), "visit \(p.visit): the court is there")
            XCTAssertEqual(kinds.count, ParkToys.placed.count, "visit \(p.visit): nothing is left out")
            XCTAssertTrue(ParkVisitPlan.shows(.slide) && ParkVisitPlan.shows(.ball) && ParkVisitPlan.shows(.seesaw) && ParkVisitPlan.shows(.hopscotch))
        }
        ParkVisitPlan.current = .all
        let all = ParkVisitPlan.placedToday.map(\.kind)
        XCTAssertTrue(all.contains(.seesaw) && all.contains(.hopscotch) && all.contains(.slide), "the default plan / forcing argument show everything")
        let p = ParkVisitPlan.begin()
        XCTAssertTrue(p.seesaw && p.hopscotch)
        XCTAssertEqual(ParkVisitPlan.placedToday.count, ParkToys.placed.count)
    }

    /// The capture / test bypass still brings everything: both pieces in play, nothing written.
    func testForcingArgumentStillGivesBoth() {
        XCTAssertTrue(ParkVisitPlan.allInPlayAlways)
        let p = ParkVisitPlan.begin()
        XCTAssertTrue(p.seesaw && p.hopscotch)
        XCTAssertEqual(p, .all)
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

    /// At every visit's plan both big toys are open to the Jelbies in the park, and at home.
    func testAllowsBothAtEveryVisit() {
        let d = freshDefaults()
        for _ in 0..<20 {
            let p = ParkVisitPlan.begin(defaults: d)
            for k in [DecorKind.seesaw, .hopscotch] {
                XCTAssertTrue(ParkVisitPlan.allows(k, outing: true, inUse: false), "visit \(p.visit): \(k) in the park")
                XCTAssertTrue(ParkVisitPlan.allows(k, outing: false, inUse: false), "visit \(p.visit): \(k) at home")
            }
        }
        ParkVisitPlan.current = .all
        XCTAssertTrue(ParkVisitPlan.allows(.seesaw, outing: true))
        XCTAssertTrue(ParkVisitPlan.allows(.hopscotch, outing: true))
    }

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
