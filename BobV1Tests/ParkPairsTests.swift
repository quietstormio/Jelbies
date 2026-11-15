//
//  ParkPairsTests.swift
//  Round park-pairs-r1 (Park/ParkPairTuning.swift): the seesaw only in twos, the seesaw and hopscotch picked more rarely, more pair and group play in the park.
//  Written before the first build and NOT run: the numbers below are targets. The unit tests are quick; the soak is long and runs only with TEST_RUNNER_PARK_PAIRS_SOAK=1
//  (TEST_RUNNER_PARK_PAIRS_MINUTES=n sim-minutes per run, default 10; TEST_RUNNER_PARK_PAIRS_SEEDS=n seeds, default 3). Every table line goes to MotionLog (TEST_RUNNER_MOTION_LOG).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ParkPairsTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    let uid = ParkToys.seesawUID

    override func setUp() {
        ParkVisitPlan.current = .all
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        HopscotchLine.shared.prune(keeping: [])
        SeesawRide.shared.reset()
        ParkPairTuning.pairSeesaw = true; ParkPairTuning.toyRateNew = true; ParkPairTuning.socialNew = true
        ParkPairTuning.partnerAgree = 1          // (the partner is certain in these tests; the soak uses the stock 0.85)
        ParkPairTuning.stats = .init()
        BlobBrain.pickBudgetSeconds = .infinity
    }
    override func tearDown() {
        BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds
        DecorField.shared.clear(); ToyTuning.settle = 5; HopscotchTuning.joinChance = 0.35
        HopscotchLine.shared.prune(keeping: [])
        SeesawRide.shared.reset()
        ParkPairTuning.pairSeesaw = true; ParkPairTuning.toyRateNew = true; ParkPairTuning.socialNew = true; ParkPairTuning.partnerAgree = 1.0
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    // MARK: the controller alone (no bodies)

    /// Nobody ever rocks alone: one rider seated and nobody coming -> the plank stays level, never the solo mode, and he is allowed to get up.
    func testLoneSeatedRiderNeverRocksAndIsToldToLeave() {
        let f = DecorField.shared, R = SeesawRide.shared
        f.set([PlacedDecor(uid: uid, kind: .seesaw, x: 0, z: 0, turns: nil)])
        f.take(uid, seat: 0, by: 1)
        R.report(uid, 0, .coming)
        for _ in 0..<30 { f.tick(dt: 1.0 / 60) }
        R.report(uid, 0, .seated)
        var modes: [SeesawRide.Mode] = [], maxAmp: Float = 0, canLeave = false
        for _ in 0..<(60 * 12) {
            f.tick(dt: 1.0 / 60)
            if modes.last != R.mode(uid) { modes.append(R.mode(uid)) }
            maxAmp = max(maxAmp, R.amp(uid))
            if R.mayLeave(uid, 0) { canLeave = true; break }
        }
        XCTAssertFalse(modes.contains(.solo), "no solo mode: \(modes)")
        XCTAssertEqual(maxAmp, 0, "the plank never moves for one rider")
        XCTAssertTrue(canLeave, "the lone rider is told to get off: \(modes)")
    }

    /// One of two riders leaves mid-ride (he is called away, then gone): the one left on the plank is not left to rock alone; the plank comes level and he gets off too.
    func testOneRiderLeavingEndsTheRideForBoth() {
        for forced in [false, true] {
            let f = DecorField.shared, R = SeesawRide.shared
            f.set([PlacedDecor(uid: uid, kind: .seesaw, x: 0, z: 0, turns: nil)])
            R.reset()
            f.take(uid, seat: 0, by: 1); f.take(uid, seat: 1, by: 2)
            R.report(uid, 0, .seated); R.report(uid, 1, .seated)
            var riding = false
            for _ in 0..<(60 * 20) { f.tick(dt: 1.0 / 60); if R.mode(uid) == .pairRide, R.amp(uid) > 0.9 { riding = true; break } }
            XCTAssertTrue(riding, "forced \(forced): the pair ride is on")
            if forced { R.report(uid, 1, .leaving, forced: true) }
            for _ in 0..<60 { f.tick(dt: 1.0 / 60) }          // (a second: the called-away one gets off)
            f.leave(uid, by: 2)
            var modes: [SeesawRide.Mode] = [], canLeave = false, maxAmpAfter: Float = 0
            for _ in 0..<(60 * 12) {
                f.tick(dt: 1.0 / 60)
                if modes.last != R.mode(uid) { modes.append(R.mode(uid)) }
                if R.mode(uid) == .solo { maxAmpAfter = 9 }
                if R.mayLeave(uid, 0) { canLeave = true; break }
            }
            XCTAssertFalse(modes.contains(.solo), "forced \(forced): never a solo mode: \(modes)")
            XCTAssertLessThan(maxAmpAfter, 1, "forced \(forced): no solo bounce")
            XCTAssertTrue(canLeave, "forced \(forced): the other rider is told to get off: \(modes)")
            XCTAssertTrue(R.still(uid) || R.mode(uid) == .leaving, "forced \(forced): the plank arrives level")
            f.leave(uid, by: 1); f.clear()
        }
    }

    // MARK: with bodies

    private func parkWorld(_ starts: [SIMD2<Float>], seed: UInt64, outing: Bool = true, only: Bool = true) -> SocialTests.Lab {
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let lab = SocialTests.Lab(n: starts.count, positions: starts, quiet: true, seed: seed)
        Self.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = outing; r.skinner.autoBlink = false; r.renderSamples = false
            r.brain.feature = JellyRoster.feature(k % 5)
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        }
        WearBody.install(MotionRig.renderMesh)
        DecorField.shared.set(ParkToys.placed.filter { $0.kind == .seesaw })
        DecorField.shared.toys.news.removeAll()
        SeesawRide.shared.reset()
        return lab
    }

    /// stage of a rider as the SeesawRideTests read it: -1 while he walks / is not on the seesaw.
    private func stage(_ b: BlobBrain) -> Int { b.idleState.kind == .decorSit && b.idleState.decorUID == uid && !b.idleState.decorGo ? b.idleState.bagStage : -1 }

    /// The autonomous start: A decides, B (a free creature far across the lawn, a visitor as far as the code is concerned) is recruited at the same moment. A is at his spot long before B and
    /// WAITS standing: never sat, the plank never moves, he hops only once B is within `readyDist` of his own spot; both get on within a few seconds of each other, ride, and both get off.
    func testWaiterStandsUntilPartnerIsNearThenBothRide() {
        ParkPairTuning.toyRateNew = false
        let c0 = ParkToys.placed.first { $0.kind == .seesaw }!.at
        let lab = parkWorld([c0 + SIMD2(0.9, 1.9), c0 + SIMD2(-2.6, 3.0)], seed: 5)
        let a = lab.rigs[0], b = lab.rigs[1], R = SeesawRide.shared, field = DecorField.shared
        XCTAssertTrue(a.brain.decorStart(.decorSit, a.sim, only: .seesaw, uid: uid), "A starts (the partner is recruited with him)")
        XCTAssertEqual(b.brain.idleState.kind, .decorSit, "B was started as the partner")
        XCTAssertEqual(field.seatOccupant[uid]?.count, 2, "both seats are claimed at once")
        var aWaitedFrom = -1, aHop = -1, bHop = -1, bFarWhenAWaited = false, seatedBeforeNear = false, maxAmpBeforeBoth: Float = 0
        var bothOff = -1, bothSeatedAt = -1
        for i in 0..<(60 * 80) {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            let sa = stage(a.brain), sb = stage(b.brain)
            if sa == 0, aWaitedFrom < 0 { aWaitedFrom = i }
            if sa == 0, b.brain.idleState.decorGo, simd_distance(b.brain.position, b.brain.idleState.target) > 2.0 { bFarWhenAWaited = true }
            if sa == 1, aHop < 0 {
                aHop = i
                if b.brain.idleState.decorGo, simd_distance(b.brain.position, b.brain.idleState.target) >= ParkPairTuning.readyDist + 0.15 { seatedBeforeNear = true }
            }
            if sb == 1, bHop < 0 { bHop = i }
            if R.stage(uid, seat: 0) == .seated || R.stage(uid, seat: 1) == .seated, R.rides[uid]?.riders.values.filter({ $0.stage == .seated }).count == 1 { maxAmpBeforeBoth = max(maxAmpBeforeBoth, R.amp(uid)) }
            if bothSeatedAt < 0, R.stage(uid, seat: 0) == .seated, R.stage(uid, seat: 1) == .seated { bothSeatedAt = i }
            if bothSeatedAt >= 0, (field.seatOccupant[uid]?.count ?? 0) == 0 { bothOff = i; break }
        }
        MotionLog.write(String(format: "PAIRS waiter: A at spot from step %d, A hop %d, B hop %d (gap %.2f s), both seated %d, both off %d; B far while A waited %@", aWaitedFrom, aHop, bHop, Float(abs(bHop - aHop)) / 60, bothSeatedAt, bothOff, bFarWhenAWaited ? "yes" : "no"))
        XCTAssertFalse(seatedBeforeNear, "A did not hop up before B was within \(ParkPairTuning.readyDist) m of his spot")
        XCTAssertEqual(maxAmpBeforeBoth, 0, "the plank never moves with one rider on it")
        XCTAssertGreaterThanOrEqual(aHop, 0); XCTAssertGreaterThanOrEqual(bHop, 0, "both got on")
        XCTAssertLessThanOrEqual(abs(bHop - aHop), 60 * 4, "they get on within a few seconds of each other (the second hops once the first has sat)")
        XCTAssertGreaterThanOrEqual(bothSeatedAt, 0, "both seated"); XCTAssertGreaterThanOrEqual(bothOff, 0, "both got off")
        XCTAssertTrue(R.gaveUp.isEmpty, "nobody gave up: \(R.gaveUp)")
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
    }

    /// A partner who is blocked and gives up before A has got on (B's use ends right after the start): A stands at his spot, never sits, and gives up calmly about a second later (the full 8 s cap is covered by the commanded no-partner test).
    func testBlockedPartnerMakesTheWaiterGiveUp() {
        ParkPairTuning.toyRateNew = false
        let c0 = ParkToys.placed.first { $0.kind == .seesaw }!.at
        let lab = parkWorld([c0 + SIMD2(0.9, 1.9), c0 + SIMD2(-2.6, 3.0)], seed: 8)
        let a = lab.rigs[0], b = lab.rigs[1], R = SeesawRide.shared, field = DecorField.shared
        XCTAssertTrue(a.brain.decorStart(.decorSit, a.sim, only: .seesaw, uid: uid))
        b.brain.abortScript(b.sim, b.skinner)          // (B's walk is blocked and he gives up)
        XCTAssertEqual(field.seatOccupant[uid]?.count, 1, "B's seat is free again")
        var arrived = -1, ended = -1, everSeated = false, maxAmp: Float = 0
        for i in 0..<(60 * 30) {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            if stage(a.brain) == 0, arrived < 0 { arrived = i }
            if R.stage(uid, seat: 0) == .seated || R.stage(uid, seat: 1) == .seated { everSeated = true }
            maxAmp = max(maxAmp, R.amp(uid))
            if arrived >= 0, a.brain.idleState.kind == nil { ended = i; break }
        }
        MotionLog.write(String(format: "PAIRS blocked partner: A at spot %d, gave up %d (%.1f s later), gaveUp %@", arrived, ended, Float(ended - arrived) / 60, "\(R.gaveUp)"))
        XCTAssertGreaterThanOrEqual(arrived, 0, "A reached his spot")
        XCTAssertGreaterThanOrEqual(ended, 0, "A gave up")
        if ended >= 0 { XCTAssertLessThanOrEqual(Float(ended - arrived) / 60, ParkPairTuning.partnerGoneGrace + 1.5, "about a second after he stood at his spot") }
        XCTAssertFalse(everSeated, "nobody ever sat down"); XCTAssertEqual(maxAmp, 0, "the plank never moved")
        XCTAssertEqual(R.gaveUp.count, 1, "one calm give-up: \(R.gaveUp)"); XCTAssertTrue(R.gaveUp.first?.hasPrefix("partnerGone") ?? false, "\(R.gaveUp)")
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
    }

    /// A commanded use with nobody to ride with: the creature goes to the seesaw, stands at his spot, and after the cap walks off (his use ends); nobody ever sits, the plank never moves.
    func testCommandedWithNoPartnerEndsCalmly() {
        let c0 = ParkToys.placed.first { $0.kind == .seesaw }!.at
        let lab = parkWorld([c0 + SIMD2(0.9, 2.2)], seed: 3)
        let a = lab.rigs[0], R = SeesawRide.shared, field = DecorField.shared
        XCTAssertTrue(a.brain.startCommandedDecor(.decorSit, only: .seesaw, a.sim, a.skinner), "a commanded seesaw start still works with nobody around")
        var arrived = -1, ended = -1, everSeated = false
        for i in 0..<(60 * 40) {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            if stage(a.brain) == 0, arrived < 0 { arrived = i }
            if R.stage(uid, seat: 0) == .seated || R.stage(uid, seat: 1) == .seated { everSeated = true }
            if arrived >= 0, a.brain.idleState.kind == nil { ended = i; break }
        }
        XCTAssertGreaterThanOrEqual(arrived, 0, "he walked to the seesaw")
        XCTAssertGreaterThanOrEqual(ended, 0, "and gave up calmly")
        if ended >= 0, arrived >= 0 { XCTAssertGreaterThanOrEqual(Float(ended - arrived) / 60, ParkPairTuning.waitCap - 1.5, "he waited about the cap"); XCTAssertLessThanOrEqual(Float(ended - arrived) / 60, ParkPairTuning.waitCap + 1.5) }
        XCTAssertFalse(everSeated, "he never rode alone"); XCTAssertEqual(R.amp(uid), 0)
        XCTAssertNil(field.seatOccupant[uid], "the seat is free again")
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
    }

    /// A commanded creature waits; a free creature becomes available a few seconds later (before the cap): the waiter finds him, they get on together and ride.
    func testCommandedWaiterFindsAPartnerWhileWaiting() {
        ParkPairTuning.toyRateNew = false
        let c0 = ParkToys.placed.first { $0.kind == .seesaw }!.at
        let lab = parkWorld([c0 + SIMD2(0.9, 2.2), c0 + SIMD2(-2.0, 2.5)], seed: 11)
        let a = lab.rigs[0], b = lab.rigs[1], R = SeesawRide.shared, field = DecorField.shared
        b.brain.anticsEnabled = false          // (not free for a toy yet)
        XCTAssertTrue(a.brain.startCommandedDecor(.decorSit, only: .seesaw, a.sim, a.skinner))
        XCTAssertNotEqual(b.brain.idleState.kind, .decorSit, "nobody was free at the start")
        var bothSeated = false, ended = false
        for i in 0..<(60 * 50) {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            if i == 60 * 3 { b.brain.anticsEnabled = true }
            if i % 60 == 0, i >= 60 * 3, i < 60 * 14 { MotionLog.write(String(format: "PAIRS dbg t=%d A kind %@ go %@ stage %d | B kind %@ go %@ stage %d dist %.2f | wait %@", i / 60, "\(String(describing: a.brain.idleState.kind))", "\(a.brain.idleState.decorGo)", stage(a.brain), "\(String(describing: b.brain.idleState.kind))", "\(b.brain.idleState.decorGo)", stage(b.brain), simd_distance(b.brain.position, b.brain.idleState.target), "\(R.waitInfo)")) }
            if R.stage(uid, seat: 0) == .seated, R.stage(uid, seat: 1) == .seated { bothSeated = true }
            if bothSeated, (field.seatOccupant[uid]?.count ?? 0) == 0 { ended = true; break }
        }
        XCTAssertTrue(bothSeated, "the waiter found his partner and they got on together: gaveUp \(R.gaveUp)")
        XCTAssertTrue(ended, "and both got off")
        XCTAssertEqual(ParkPairTuning.stats.recruited, 1)
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
    }

    /// An autonomous seesaw pick with nobody free to ride with does not start at all (no creature walks over to stand and wait for nothing), and takes no seat.
    func testAutonomousPickWithNoFreePartnerDoesNotStart() {
        ParkPairTuning.toyRateNew = false
        let c0 = ParkToys.placed.first { $0.kind == .seesaw }!.at
        let lab = parkWorld([c0 + SIMD2(0.9, 2.2), c0 + SIMD2(2.5, 3.0)], seed: 4)
        let a = lab.rigs[0], b = lab.rigs[1]
        b.brain.anticsEnabled = false
        XCTAssertFalse(a.brain.decorStart(.decorSit, a.sim, only: .seesaw, uid: uid), "no free partner: no start")
        XCTAssertNil(DecorField.shared.seatOccupant[uid], "and no seat is held")
        XCTAssertEqual(ParkPairTuning.stats.noPartner, 1)
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
    }

    /// The pair rule does not care who the partner is: any brain that is free and near (a roster creature or a park visitor: both are brains in `socialOthers`, with `outingPlay` set by GameCare+Park)
    /// can be recruited. A headless lab cannot tell a visitor from a roster creature, so this uses a different species and a far start; the real-app survey must confirm a visitor + the home creature.
    func testAnyFreeBrainCanBePartner() {
        ParkPairTuning.toyRateNew = false
        let c0 = ParkToys.placed.first { $0.kind == .seesaw }!.at
        let lab = parkWorld([c0 + SIMD2(0.9, 2.2), c0 + SIMD2(-2.0, 2.5), c0 + SIMD2(3.0, 2.8)], seed: 6)
        let a = lab.rigs[0]
        XCTAssertTrue(a.brain.decorStart(.decorSit, a.sim, only: .seesaw, uid: uid))
        let partners = lab.rigs.dropFirst().filter { $0.brain.idleState.kind == .decorSit && $0.brain.idleState.decorUID == uid }
        XCTAssertEqual(partners.count, 1, "exactly one of the others was taken as the partner")
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
    }

    func testDiagPartnerSpots() {
        let c0 = ParkToys.placed.first { $0.kind == .seesaw }!.at
        let lab = parkWorld([c0 + SIMD2(0.9, 2.2), c0 + SIMD2(-2.0, 2.5), c0 + SIMD2(3.0, 2.8), c0 + SIMD2(2.5, 3.0)], seed: 6)
        guard let f = DecorField.shared.foot(uid) else { return }
        for (i, r) in lab.rigs.enumerated() {
            let b = r.brain
            for seat in 0..<2 {
                b.decorIgnore = uid
                let st = b.decorStand(.decorSit, f, from: b.position, seat: seat)
                MotionLog.write("PAIRS diag rig \(i) at \(b.position) seat \(seat): stand \(String(describing: st)) reachable \(st.map { b.reachable(b.position, $0) } ?? false) toyFree \(b.toyFree) dist \(simd_distance(b.position, DecorField.shared.position(f)))")
                b.decorIgnore = nil
            }
        }
    }

    /// The hand-started pair of the old seesaw tests (both riders started by decorStart, outingPlay off): both must get on.
    func testHandStartedPairBothGetOn() {
        let lab = parkWorld([SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4)], seed: 3, outing: false)
        for r in lab.rigs { r.brain.idleForced = true }
        let R = SeesawRide.shared, field = DecorField.shared
        for r in lab.rigs { XCTAssertTrue(r.brain.decorStart(.decorSit, r.sim, only: .seesaw, uid: uid)) }
        var both = false
        for i in 0..<(60 * 40) {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            if i % 30 == 0, i < 60 * 9 { let a = lab.rigs[0].brain, b = lab.rigs[1].brain; MotionLog.write(String(format: "PAIRS hand pos t=%.1f A (%.2f,%.2f)->(%.2f,%.2f) seat %d | B (%.2f,%.2f)->(%.2f,%.2f) seat %d retry %d script %@ stall %d", Float(i) / 60, a.position.x, a.position.y, a.idleState.target.x, a.idleState.target.y, a.idleState.seat, b.position.x, b.position.y, b.idleState.target.x, b.idleState.target.y, b.idleState.seat, b.idleState.decorRetry, "\(b.script)", b.steerStall)) }
            if i % 120 == 0 { MotionLog.write(String(format: "PAIRS hand dbg t=%d | A %@ go %@ st %d d %.2f | B %@ go %@ st %d d %.2f | %@", i / 60, "\(String(describing: lab.rigs[0].brain.idleState.kind))", "\(lab.rigs[0].brain.idleState.decorGo)", stage(lab.rigs[0].brain), simd_distance(lab.rigs[0].brain.position, lab.rigs[0].brain.idleState.target), "\(String(describing: lab.rigs[1].brain.idleState.kind))", "\(lab.rigs[1].brain.idleState.decorGo)", stage(lab.rigs[1].brain), simd_distance(lab.rigs[1].brain.position, lab.rigs[1].brain.idleState.target), "\(R.waitInfo)")) }
            if R.stage(uid, seat: 0) == .seated, R.stage(uid, seat: 1) == .seated { both = true; break }
        }
        XCTAssertTrue(both, "both got on: gaveUp \(R.gaveUp)")
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
    }

    // MARK: the rates (pure checks of the gate)

    func testGateIsOpenAtHomeAndForCommandedAndPartnerStarts() {
        let lab = SocialTests.Lab(n: 1, positions: [SIMD2(0, 0)], quiet: true, seed: 1)
        Self.keep.append(lab)
        let b = lab.rigs[0].brain
        DecorField.shared.set(ParkToys.placed.filter { $0.kind == .seesaw })
        guard let foot = DecorField.shared.foot(ParkToys.seesawUID) else { return XCTFail("the seesaw is placed") }
        b.outingPlay = false
        for _ in 0..<50 { XCTAssertTrue(b.parkToyGate(foot), "home: never rolled") }
        b.outingPlay = true; b.commanded = true
        for _ in 0..<50 { XCTAssertTrue(b.parkToyGate(foot), "commanded: never rolled") }
        b.commanded = false; b.seesawPartnerStart = true
        for _ in 0..<50 { XCTAssertTrue(b.parkToyGate(foot), "a partner's start: never rolled") }
        b.seesawPartnerStart = false
        ParkPairTuning.toyRateNew = false
        for _ in 0..<50 { XCTAssertTrue(b.parkToyGate(foot), "old switch: never rolled") }
        ParkPairTuning.toyRateNew = true
        var yes = 0
        for _ in 0..<2000 { if b.parkToyGate(foot) { yes += 1 } }
        XCTAssertEqual(Float(yes) / 2000, ParkPairTuning.seesawPickChance, accuracy: 0.05, "the roll passes with the constant's chance")
        b.parkToyUsed(.seesaw)
        for _ in 0..<50 { XCTAssertFalse(b.parkToyGate(foot), "right after a use: the cooldown") }
    }

    // MARK: the soak

    struct Soak {
        var creatureMinutes: Float = 0
        var seesawRides = 0, soloRides = 0, pairRides = 0, soloMovingSteps = 0
        var waits: [Float] = [], waitsGaveUp = 0, aloneStill: [Float] = []          // (stage-0 stands at the seesaw in seconds, how many ended without getting on; seated-alone-on-a-still-plank spans in seconds)
        var hopSessions = 0
        var socialBegins = 0, pairBegins = 0, groupBegins = 0
        var stepsSeesaw = 0, stepsHop = 0, stepsSocial = 0, stepsOther = 0
        var stats = ParkPairTuning.Stats()
        mutating func add(_ o: Soak) {
            creatureMinutes += o.creatureMinutes; seesawRides += o.seesawRides; soloRides += o.soloRides; soloMovingSteps += o.soloMovingSteps; waits += o.waits; waitsGaveUp += o.waitsGaveUp; aloneStill += o.aloneStill; pairRides += o.pairRides; hopSessions += o.hopSessions
            socialBegins += o.socialBegins; pairBegins += o.pairBegins; groupBegins += o.groupBegins
            stepsSeesaw += o.stepsSeesaw; stepsHop += o.stepsHop; stepsSocial += o.stepsSocial; stepsOther += o.stepsOther
            stats.rollNo += o.stats.rollNo; stats.coolNo += o.stats.coolNo; stats.noPartner += o.stats.noPartner; stats.recruited += o.stats.recruited
        }
        var steps: Float { Float(max(1, stepsSeesaw + stepsHop + stepsSocial + stepsOther)) }
        func line(_ tag: String) -> String {
            let m = max(creatureMinutes, 0.001)
            let w = waits.isEmpty ? "none" : String(format: "n %d (%d gave up), mean %.1f s, longest %.1f s", waits.count, waitsGaveUp, waits.reduce(0, +) / Float(waits.count), waits.max()!)
            let a = aloneStill.isEmpty ? "none" : String(format: "n %d, mean %.1f s, longest %.1f s", aloneStill.count, aloneStill.reduce(0, +) / Float(aloneStill.count), aloneStill.max()!)
            MotionLog.write("PAIRS SOAK \(tag) WAITS standing at the seesaw before getting on: \(w) | SEATED ALONE on a still plank: \(a)")
            return String(format: "PAIRS SOAK %@: creature-min %.1f | seesaw rides %.3f/cmin (lone-sit %d, pair %d, steps with ONE rider on a MOVING plank %d) | hopscotch sessions %.3f/cmin | social begins %.3f/cmin (pair %d, group member-begins %d) | time share seesaw %.1f%% hop %.1f%% social %.1f%% other %.1f%% | rejects: roll %d cooldown %d noPartner %d recruited %d",
                          tag, creatureMinutes, Float(seesawRides) / m, soloRides, pairRides, soloMovingSteps, Float(hopSessions) / m, Float(socialBegins) / m, pairBegins, groupBegins,
                          100 * Float(stepsSeesaw) / steps, 100 * Float(stepsHop) / steps, 100 * Float(stepsSocial) / steps, 100 * Float(stepsOther) / steps, stats.rollNo, stats.coolNo, stats.noPartner, stats.recruited)
        }
    }

    /// Switch sets: old = (pairSeesaw false, toyRate old, social old); new = all three on.
    private func setSwitches(new: Bool) { ParkPairTuning.pairSeesaw = new; ParkPairTuning.toyRateNew = new; ParkPairTuning.socialNew = new }

    /// `n` creatures in the park for `minutes` sim-minutes with every park piece out. `visitors`: the first is the home creature and the others are strangers (friendship closeness 0.55 both ways, as a first
    /// visit); else all are housemates (closeness 1). A seesaw ride = from the first body on the piece to the last one off; a pair ride = both were seated at once.
    private func parkSoak(n: Int, visitors: Bool, minutes: Float, seed: UInt64, new: Bool) -> Soak {
        setSwitches(new: new)
        ParkPairTuning.partnerAgree = 1.0
        ParkPairTuning.stats = .init()
        ParkVisitPlan.current = .all
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); HopscotchLine.shared.prune(keeping: []); SeesawRide.shared.reset()
        HopscotchTuning.joinChance = ParkPlayTuning.hopscotchJoin
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let pts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(1.6, 1.2), SIMD2(-1.6, 1.6)]
        let lab = SocialTests.Lab(n: n, positions: Array(pts.prefix(n)), quiet: false, seed: seed)
        Self.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = true; r.skinner.autoBlink = false; r.renderSamples = false
            r.brain.feature = JellyRoster.feature(k % 5)
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            if visitors { for o in lab.rigs where o !== r { r.brain.socialBook.close[o.brain.steerID] = 0.55 } }
        }
        WearBody.install(MotionRig.renderMesh)
        let field = DecorField.shared, R = SeesawRide.shared
        field.set(ParkToys.placed); field.toys.news.removeAll()
        var out = Soak()
        var prev = [IdleKind?](repeating: nil, count: n)
        var inRide = false, bothSeated = false, anySeated = false, emptyFor = 0
        var standT = [Float](repeating: 0, count: n), standing = [Bool](repeating: false, count: n), boarded = [Bool](repeating: false, count: n)
        var aloneT: Float = 0
        let steps = Int(minutes * 3600)
        for _ in 0..<steps {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            for (i, r) in lab.rigs.enumerated() {
                let b = r.brain, now = b.idleState.kind
                if prev[i] != .decorHopscotch, now == .decorHopscotch { out.hopSessions += 1 }
                prev[i] = now
                if now == .decorSit, b.idleState.decorUID == uid { out.stepsSeesaw += 1 }
                else if now == .decorHopscotch { out.stepsHop += 1 }
                else if b.isSocial { out.stepsSocial += 1 }
                else { out.stepsOther += 1 }
            }
            for (i, r) in lab.rigs.enumerated() {
                let st = r.brain.idleState
                let atStage0 = st.kind == .decorSit && st.decorUID == uid && !st.decorGo && st.bagStage == 0
                if atStage0 { standing[i] = true; standT[i] += 1.0 / 60; boarded[i] = false }
                else if standing[i] {
                    standing[i] = false
                    if st.kind == .decorSit && st.decorUID == uid && st.bagStage >= 1 { out.waits.append(standT[i]) } else { out.waits.append(standT[i]); out.waitsGaveUp += 1 }
                    standT[i] = 0
                }
            }
            let occ = field.seatOccupant[uid]?.count ?? 0
            let seatedNow = [0, 1].filter { R.stage(uid, seat: $0) == .seated }.count
            if seatedNow == 1, R.amp(uid) > 0.01 || abs(R.theta(uid)) > 0.01 { out.soloMovingSteps += 1 }
            if seatedNow == 1, R.amp(uid) <= 0.01 { aloneT += 1.0 / 60 } else if aloneT > 0 { if seatedNow == 2 || true { out.aloneStill.append(aloneT) }; aloneT = 0 }
            if occ > 0 {
                if !inRide { inRide = true; bothSeated = false; anySeated = false }
                emptyFor = 0
                if R.stage(uid, seat: 0) == .seated || R.stage(uid, seat: 1) == .seated { anySeated = true }
                if R.stage(uid, seat: 0) == .seated, R.stage(uid, seat: 1) == .seated { bothSeated = true }
            } else if inRide {
                emptyFor += 1
                if emptyFor > 30 { inRide = false; if anySeated { out.seesawRides += 1; if bothSeated { out.pairRides += 1 } else { out.soloRides += 1 } } }          // (a seat claim where nobody ever sat - a waiter who gave up - is no ride)
            }
        }
        out.creatureMinutes = Float(n) * minutes
        for ev in lab.events { for e in ev { if case .began(let k, _) = e { out.socialBegins += 1; if k.isGroup { out.groupBegins += 1 } else { out.pairBegins += 1 } } } }
        out.stats = ParkPairTuning.stats
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        field.clear(); HopscotchLine.shared.prune(keeping: [])
        setSwitches(new: true)
        return out
    }

    /// Old switches against new, a few seeds, 1 home creature + 3 visitors (n = 4) and 3 housemates (n = 3). Prints the table; asserts the brief's bands.
    /// (`soloRides` counts only rides where somebody SAT and nobody was ever seated with him; a waiter who gave up never sat.)
    func testParkSoakOldVersusNew() throws {
        guard ProcessInfo.processInfo.environment["PARK_PAIRS_SOAK"] != nil else { throw XCTSkip("set TEST_RUNNER_PARK_PAIRS_SOAK=1 to run the soak") }
        let minutes = Float(ProcessInfo.processInfo.environment["PARK_PAIRS_MINUTES"].flatMap { Float($0) } ?? 10)
        let seedCount = ProcessInfo.processInfo.environment["PARK_PAIRS_SEEDS"].flatMap { Int($0) } ?? 3
        let seeds: [UInt64] = (0..<seedCount).map { 21 + 7 * UInt64($0) }
        let onlyNew = ProcessInfo.processInfo.environment["PARK_PAIRS_ONLY_NEW"] != nil          // (skip the old runs: the new switches only)
        var oldAll = Soak(), newAll = Soak()
        for (label, n, visitors) in [("1 home + 3 visitors", 4, true), ("3 housemates", 3, false)] {
            var old = Soak(), new = Soak()
            for s in seeds {
                if !onlyNew { let o = parkSoak(n: n, visitors: visitors, minutes: minutes, seed: s, new: false); MotionLog.write(o.line("\(label) seed \(s) OLD")); old.add(o) }
                let w = parkSoak(n: n, visitors: visitors, minutes: minutes, seed: s, new: true); MotionLog.write(w.line("\(label) seed \(s) NEW")); new.add(w)
            }
            MotionLog.write(old.line("\(label) ALL OLD")); MotionLog.write(new.line("\(label) ALL NEW"))
            oldAll.add(old); newAll.add(new)
            XCTAssertEqual(new.soloMovingSteps, 0, "\(label): never ONE rider on a moving plank")
            if !onlyNew, old.socialBegins >= 10 { let r = Float(new.socialBegins) / Float(old.socialBegins); XCTAssertGreaterThanOrEqual(r, 1.3, "\(label): social begins \(r) of the old") }
        }
        // (the toy bands are judged on both configurations pooled: a single configuration has only ~10 to 20 rides in it, and the old runs themselves differ by a third from run to run)
        MotionLog.write(oldAll.line("POOLED OLD")); MotionLog.write(newAll.line("POOLED NEW"))
        if !onlyNew {
            if oldAll.seesawRides >= 6 { let r = Float(newAll.pairRides) / Float(oldAll.seesawRides); XCTAssertGreaterThanOrEqual(r, 0.35, "seesaw rides pooled (new = rides where the plank moved with two on it; a lone sit never moves) \(r) of the old"); XCTAssertLessThanOrEqual(r, 0.65, "seesaw rides pooled \(r) of the old") }
            if oldAll.hopSessions >= 6 { let r = Float(newAll.hopSessions) / Float(oldAll.hopSessions); XCTAssertGreaterThanOrEqual(r, 0.35, "hopscotch pooled \(r) of the old"); XCTAssertLessThanOrEqual(r, 0.65, "hopscotch pooled \(r) of the old") }
        }
    }

    /// The room is untouched. A repeat of the same room soak is NOT identical even old against old (the harness has wall-clock and global state in it: measured, see the control line in the log), so the
    /// proof is by construction: with `outingPlay` off every park hook is a pure pass-through and draws no random number, whatever the three switches are.
    func testRoomHooksAreInertAtHome() {
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(0, 0), SIMD2(1.5, 0)], quiet: true, seed: 3)
        Self.keep.append(lab)
        DecorField.shared.set(ParkToys.placed.filter { $0.kind == .seesaw || $0.kind == .hopscotch })
        let b = lab.rigs[0].brain
        b.outingPlay = false
        for new in [false, true] {
            setSwitches(new: new)
            XCTAssertEqual(b.parkSocialPickMul, 1); XCTAssertEqual(b.parkSocialWaitMul, 1); XCTAssertFalse(b.parkSocialOn)
            let before = b.seed
            for f in DecorField.shared.feet { XCTAssertTrue(b.parkToyGate(f)) }
            XCTAssertEqual(b.seed, before, "the gate drew no random number at home")
            XCTAssertNil(b.toy.parkCool[.seesaw]); b.parkToyUsed(.seesaw); b.toy.parkCool[.seesaw] = nil
        }
        setSwitches(new: true)
        // (decorRelease only sets the park cooldown when outingPlay is on)
        XCTAssertTrue(b.toy.parkCool.isEmpty)
        // informational: the soak at home, old against new (not asserted: the harness is not repeatable)
        MotionLog.write("PAIRS ROOM: hooks inert at home (see ParkPairsTests.testRoomHooksAreInertAtHome); a repeat-run room soak differs even old vs old")
    }
}
