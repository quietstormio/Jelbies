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

    func testNeverBothAndEachPieceEveryOtherVisit() {
        var seesawVisits: [Int] = [], hopscotchVisits: [Int] = []
        for v in 1...20 {
            let d = ParkVisitPlan.draw(visit: v, seesawOff: 0, hopscotchOff: 0)
            XCTAssertFalse(d.seesaw && d.hopscotch, "visit \(v): both pieces in play")
            XCTAssertTrue(d.seesaw || d.hopscotch, "visit \(v): neither piece in play")
            if d.seesaw { seesawVisits.append(v) }; if d.hopscotch { hopscotchVisits.append(v) }
        }
        XCTAssertEqual(seesawVisits.count, 10); XCTAssertEqual(hopscotchVisits.count, 10)
        for list in [seesawVisits, hopscotchVisits] {
            for (a, b) in zip(list, list.dropFirst()) { XCTAssertEqual(b - a, 2, "a piece appears in exactly every other visit") }
        }
        // the saved streaks never change the answer
        for v in 1...20 {
            let a = ParkVisitPlan.draw(visit: v, seesawOff: 0, hopscotchOff: 0), b = ParkVisitPlan.draw(visit: v, seesawOff: 2, hopscotchOff: 2)
            XCTAssertTrue(a.seesaw == b.seesaw && a.hopscotch == b.hopscotch)
        }
    }

    // MARK: begin

    /// 20 consecutive visits through the persisted counter (each one reading the store fresh, as a relaunch does): never both, alternating, from any starting counter.
    func testBeginAlternatesAcrossRelaunches() {
        for start in [0, 1, 7] {
            let d = freshDefaults()
            if start > 0 { d.set(["visit": start, "seesawOff": 0, "hopscotchOff": 0], forKey: ParkVisitPlan.key) }
            var plans: [ParkVisitPlan.Plan] = []
            for v in 1...20 {
                let p = ParkVisitPlan.begin(defaults: d)
                XCTAssertEqual(p.visit, start + v)
                XCTAssertEqual(ParkVisitPlan.current, p)
                XCTAssertEqual(d.dictionary(forKey: ParkVisitPlan.key)?["visit"] as? Int, start + v)
                XCTAssertFalse(p.seesaw && p.hopscotch, "visit \(p.visit): both")
                XCTAssertTrue(p.seesaw != p.hopscotch, "visit \(p.visit): exactly one")
                plans.append(p)
            }
            XCTAssertEqual(plans.filter(\.seesaw).count, 10, "start \(start)")
            XCTAssertEqual(plans.filter(\.hopscotch).count, 10, "start \(start)")
            for (a, b) in zip(plans, plans.dropFirst()) { XCTAssertNotEqual(a.seesaw, b.seesaw, "visit \(b.visit) alternates") }
        }
    }

    /// Only the piece that is in today's plan is placed (drawn): one of the seesaw / the court, always the slide; the forcing argument and the default plan show both.
    func testOnlyTodaysBigToyIsPlaced() {
        let d = freshDefaults()
        for _ in 0..<6 {
            let p = ParkVisitPlan.begin(defaults: d)
            let kinds = ParkVisitPlan.placedToday.map(\.kind)
            XCTAssertTrue(kinds.contains(.slide), "visit \(p.visit): the slide is always there")
            XCTAssertEqual(kinds.contains(.seesaw), p.seesaw, "visit \(p.visit)")
            XCTAssertEqual(kinds.contains(.hopscotch), p.hopscotch, "visit \(p.visit)")
            XCTAssertEqual(kinds.filter { $0 == .seesaw || $0 == .hopscotch }.count, 1, "visit \(p.visit): exactly one big toy")
            XCTAssertEqual(kinds.count, ParkToys.placed.count - 1)
            XCTAssertTrue(ParkVisitPlan.shows(.slide) && ParkVisitPlan.shows(.ball))
        }
        ParkVisitPlan.current = .all
        let all = ParkVisitPlan.placedToday.map(\.kind)
        XCTAssertTrue(all.contains(.seesaw) && all.contains(.hopscotch) && all.contains(.slide), "the default plan / forcing argument show everything")
        XCTAssertEqual(ParkVisitPlan.begin().seesaw && ParkVisitPlan.begin().hopscotch, true)
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
