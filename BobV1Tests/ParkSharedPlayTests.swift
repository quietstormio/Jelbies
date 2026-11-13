//
//  ParkSharedPlayTests.swift
//  Shared seesaw rides and hopscotch lines with a park visitor pay friendship (Park/ParkSharedPlay.swift): the pure tracker, the numbers, and the real seesaw / court feeding it.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ParkSharedPlayTests: XCTestCase {
    let dt: Float = 1.0 / 60
    let uid = ParkToys.seesawUID
    // body ids: 0, 1 are home Jelbies; 10, 11 are visitors
    func isHome(_ i: Int) -> Bool { i < 10 }
    func isVisitor(_ i: Int) -> Bool { i >= 10 }

    func steps(_ t: inout SharedPlayTracker, _ n: Int, mode: SeesawRide.Mode, seats: [Int] = [0, 10]) -> [SharedPlayAward] {
        var out: [SharedPlayAward] = []
        for _ in 0..<n { out += t.step(dt: dt, seesaws: [SharedSeesaw(uid: 1, mode: mode, seats: seats)], courts: [], isHome: isHome, isVisitor: isVisitor) }
        return out
    }
    func court(_ t: inout SharedPlayTracker, _ players: [(id: Int, sq: Int)]) -> [SharedPlayAward] {
        t.step(dt: dt, seesaws: [], courts: [SharedCourt(uid: 2, players: players)], isHome: isHome, isVisitor: isVisitor)
    }

    override func setUp() {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        SeesawRide.shared.reset()
    }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5
        SeesawRide.shared.reset(); HopscotchTuning.joinChance = 0.35
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    // 1
    func testOneRideOneAward() {
        var t = SharedPlayTracker()
        XCTAssertTrue(steps(&t, 600, mode: .pairBeat).isEmpty, "a beat alone pays nothing")
        var out: [SharedPlayAward] = []
        var at = -1
        for i in 0..<(15 * 60) { let a = steps(&t, 1, mode: .pairRide); if !a.isEmpty, at < 0 { at = i }; out += a }
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.points, SharedPlayTuning.rideBonus)
        XCTAssertEqual(out.first?.home, 0); XCTAssertEqual(out.first?.visitor, 10); XCTAssertEqual(out.first?.kind, .ride)
        XCTAssertEqual(Float(at) * dt, SharedPlayTuning.rideSeconds, accuracy: 0.1)
        var t2 = SharedPlayTracker()
        XCTAssertTrue(steps(&t2, Int((SharedPlayTuning.rideSeconds - 0.5) * 60), mode: .pairRide).isEmpty, "a ride cut short pays nothing")
        XCTAssertTrue(steps(&t2, 600, mode: .idle, seats: []).isEmpty)
    }

    // 2
    func testSameRideNotPaidTwiceNewRidePays() {
        var t = SharedPlayTracker()
        var n = steps(&t, 60 * 6, mode: .pairRide).count
        n += steps(&t, 120, mode: .ending).count + steps(&t, 120, mode: .endBeat).count
        XCTAssertEqual(n, 1)
        XCTAssertTrue(steps(&t, 60, mode: .idle, seats: []).isEmpty)
        XCTAssertEqual(steps(&t, 60 * 6, mode: .pairRide).count, 1, "a later ride of the same two pays again")
    }

    // 3
    func testSamePartiesNeverPay() {
        var t = SharedPlayTracker()
        XCTAssertTrue(steps(&t, 60 * 10, mode: .pairRide, seats: [0, 1]).isEmpty)
        XCTAssertTrue(steps(&t, 60 * 10, mode: .pairRide, seats: [10, 11]).isEmpty)
        var c = SharedPlayTracker()
        XCTAssertTrue(court(&c, [(0, 2), (1, 2)]).isEmpty)
        XCTAssertTrue(court(&c, [(10, 2), (11, 3)]).isEmpty)
    }

    // 4
    func testHopscotchLine() {
        var t = SharedPlayTracker()
        XCTAssertTrue(court(&t, [(10, 3), (0, -1)]).isEmpty, "the home one has not hopped yet")
        let a = court(&t, [(10, 3), (0, 0)])
        XCTAssertEqual(a.count, 1); XCTAssertEqual(a.first?.points, SharedPlayTuning.hopBonus); XCTAssertEqual(a.first?.kind, .line)
        XCTAssertTrue(court(&t, [(10, 99), (0, 99)]).isEmpty)
        XCTAssertTrue(court(&t, [(10, 99), (0, 99)]).isEmpty)
        XCTAssertTrue(court(&t, [(10, 99)]).isEmpty, "one leaves")
        XCTAssertTrue(court(&t, [(10, -1), (0, -1)]).isEmpty, "a new line, nobody landed yet")
        XCTAssertEqual(court(&t, [(10, 0), (0, 0)]).count, 1, "the new line pays again")
        // three in a line: each home-visitor pair on its own
        var u = SharedPlayTracker()
        XCTAssertEqual(court(&u, [(0, 1), (10, 1), (11, 0)]).count, 2)
    }

    // 5
    func testCap() {
        var t = SharedPlayTracker()
        var paid = 0
        for _ in 0..<4 {
            paid += court(&t, [(0, 0), (10, 0)]).count
            _ = court(&t, [])          // leave
        }
        XCTAssertEqual(paid, SharedPlayTuning.capPerPair, "the 4th for the same pair is refused")
        XCTAssertEqual(court(&t, [(0, 0), (11, 0)]).count, 1, "another pair is still paid")
        t.reset()
        XCTAssertEqual(court(&t, [(0, 0), (10, 0)]).count, 1, "after reset it pays again")
        // rides and lines share the cap
        var s = SharedPlayTracker()
        for _ in 0..<2 { _ = steps(&s, 60 * 5, mode: .pairRide); _ = steps(&s, 10, mode: .idle, seats: []) }
        XCTAssertEqual(court(&s, [(0, 0), (10, 0)]).count, 1)
        _ = court(&s, [])
        XCTAssertTrue(court(&s, [(0, 0), (10, 0)]).isEmpty, "3 used: rides + lines share the cap")
    }

    // 6
    func testNumbers() {
        let trickle = ParkTuning.pointsPerSecond * 22
        for b in [SharedPlayTuning.rideBonus, SharedPlayTuning.hopBonus] {
            XCTAssertGreaterThan(b, trickle)
            XCTAssertLessThan(b, ParkTuning.palAt)
        }
        XCTAssertLessThanOrEqual(Float(SharedPlayTuning.capPerPair) * SharedPlayTuning.rideBonus, ParkTuning.bestAt - ParkTuning.friendAt)
        XCTAssertLessThanOrEqual(Float(SharedPlayTuning.capPerPair) * SharedPlayTuning.hopBonus, ParkTuning.bestAt - ParkTuning.friendAt)
    }

    // 7: the real seesaw, riders seated by hand (as SeesawRideTests.testControllerSequenceAndContinuity)
    func testRealSeesawRide() {
        let f = DecorField.shared, R = SeesawRide.shared
        f.set([PlacedDecor(uid: uid, kind: .seesaw, x: 0, z: 0, turns: nil)])
        var t = SharedPlayTracker()
        var awards: [SharedPlayAward] = []
        var modes: [SeesawRide.Mode] = []
        func step() {
            f.tick(dt: dt)
            let feet = f.feet.filter { $0.kind == .seesaw }
            let see = feet.map { SharedSeesaw(uid: $0.uid, mode: R.mode($0.uid), seats: (f.seatOccupant[$0.uid] ?? [:]).sorted { $0.key < $1.key }.map(\.value)) }
            awards += t.step(dt: dt, seesaws: see, courts: [], isHome: { $0 == 0 }, isVisitor: { $0 == 1 })
            if modes.last != R.mode(uid) { modes.append(R.mode(uid)) }
        }
        f.take(uid, seat: 0, by: 0)
        R.report(uid, 0, .coming)
        for _ in 0..<30 { step() }
        R.report(uid, 0, .seated)
        for _ in 0..<(60 * 4) { step() }
        f.take(uid, seat: 1, by: 1)
        R.report(uid, 1, .coming)
        for _ in 0..<(60 * 3) { step() }
        R.report(uid, 1, .boarding)
        for _ in 0..<30 { step() }
        R.report(uid, 1, .seated)
        for _ in 0..<(60 * 60) { step(); if R.mode(uid) == .leaving { break } }
        XCTAssertTrue(modes.contains(.pairRide), "the ride reached .pairRide: \(modes)")
        XCTAssertEqual(awards.count, 1, "exactly one award for the ride; modes \(modes)")
        XCTAssertEqual(awards.first?.points, SharedPlayTuning.rideBonus)
    }

    // 8: the real court, three Jelbies (HopscotchTests.testFollowersQueueKeepSpacingAndNeverOverlap): 0 home, 1 visitor, 2 neither
    func testRealHopscotchLine() {
        for seed: UInt64 in [5, 6, 7, 8] { realHopscotchLine(seed: seed) }
    }

    private func realHopscotchLine(seed: UInt64) {
        // (a clean park per seed: the court and toys as setUp leaves them, no player left in the line)
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        for (u, ps) in HopscotchLine.shared.lines { for pl in ps { HopscotchLine.shared.remove(u, pl.id) } }
        HopscotchTuning.joinChance = 1
        let huid = ParkToys.hopscotchUID
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let starts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4)]
        let lab = SocialTests.Lab(n: 3, positions: starts, quiet: true, seed: seed)
        for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius; r.brain.anticsEnabled = true; r.brain.idleMood = .happy }
        DecorField.shared.set(ParkToys.placed)
        DecorField.shared.toys.news.removeAll()
        let line = HopscotchLine.shared
        for r in lab.rigs { r.brain.autonomy = true }
        lab.rigs[0].brain.idleForced = true
        XCTAssertTrue(lab.rigs[0].brain.decorStart(.decorHopscotch, lab.rigs[0].sim, only: nil, uid: huid))
        var t = SharedPlayTracker()
        var awards: [SharedPlayAward] = []
        var maxPlayers = 0
        var minPlayers = Float.infinity, minPlayersAt = "", minAll = Float.infinity, minAllAt = ""
        for i in 0..<(60 * 80) {
            lab.tick(watching: false); DecorField.shared.tick(dt: dt)
            maxPlayers = max(maxPlayers, line.players(huid).count)
            for a in 0..<3 { for c in (a + 1)..<3 {
                let g = simd_distance(lab.snapshot[a].pos, lab.snapshot[c].pos)
                let w = "t=\(String(format: "%.1f", Float(i) / 60)) ids \(a),\(c) squares \(line.square(huid, a)),\(line.square(huid, c))"
                if g < minAll { minAll = g; minAllAt = w }
                if line.contains(huid, a), line.contains(huid, c), g < minPlayers { minPlayers = g; minPlayersAt = w }
            } }
            let c = [SharedCourt(uid: huid, players: line.players(huid).map { (id: $0.id, sq: $0.sq) })]
            awards += t.step(dt: dt, seesaws: [], courts: c, isHome: { $0 == 0 }, isVisitor: { $0 == 1 })
            if i > 600, !line.active { break }
        }
        print("[hopline] real seed=\(seed) minPlayers=\(minPlayers)@\(minPlayersAt) minAll=\(minAll)@\(minAllAt) players=\(maxPlayers) awards=\(awards.count)")
        XCTAssertEqual(maxPlayers, 3)
        XCTAssertEqual(awards.count, 1, "seed \(seed): exactly one award during the line: \(awards)")
        XCTAssertEqual(awards.first?.points, SharedPlayTuning.hopBonus)
    }
}
