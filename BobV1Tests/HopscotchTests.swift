//
//  HopscotchTests.swift
//  The Park's hopscotch court and its line (BlobBrain+Hopscotch.swift, Park/HopscotchCourt.swift): the hop path visits the squares in order, followers keep their spacing and never overlap,
//  the join chance is in range, every toy spot is released on the park exit, and the new park pieces (court, slide, tunnel) fit the lawn without overlapping each other.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HopscotchTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    let uid = ParkToys.hopscotchUID

    override func setUp() {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        HopscotchTuning.joinChance = 0.35
    }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5; HopscotchTuning.joinChance = 0.35
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        // leave the process-wide room state as a fresh launch has it (one-Jelly camera and floor, the home room's colliders): endPark(3) keeps the wide 3-Jelly camera and the park's
        // layout, which widened every later suite's walkable width (LineupTests testTrayNeverOffersAnUnreachableSidePlace failed after HopscotchTests)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    func parkLab(n: Int, seed: UInt64 = 5) -> SocialTests.Lab {
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let starts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4)]
        let lab = SocialTests.Lab(n: n, positions: Array(starts.prefix(n)), quiet: true, seed: seed)
        for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius; r.brain.anticsEnabled = true; r.brain.idleMood = .happy }
        DecorField.shared.set(ParkToys.placed)
        DecorField.shared.toys.news.removeAll()          // (placing the park's toys is news too: this is about the line)
        return lab
    }

    // MARK: the join chance

    func testJoinChanceIsInRangeAndRollsOncePerLine() {
        XCTAssertTrue(HopscotchTuning.joinRange.contains(HopscotchTuning.joinChance), "join chance \(HopscotchTuning.joinChance)")
        let line = HopscotchLine.shared
        line.enroll(uid, 0)
        var joined = 0, trials = 4000
        var rng = SystemRandomNumberGenerator()
        for i in 0..<trials {
            let id = 100 + i
            let roll = Float.random(in: 0..<1, using: &rng)
            if line.invitation(uid, id, roll: roll) { joined += 1 }
            XCTAssertFalse(line.invitation(uid, id, roll: 0), "a second roll for the same line is refused")
        }
        let p = Double(joined) / Double(trials)
        XCTAssertTrue((0.28...0.42).contains(p), "observed join rate \(p)")
        line.remove(uid, 0)
        XCTAssertFalse(line.active)
        trials = 0
    }

    func testLineHoldsFourAtMost() {
        let line = HopscotchLine.shared
        for id in 0..<HopscotchTuning.maxPlayers { line.enroll(uid, id) }
        XCTAssertFalse(line.invitation(uid, 77, roll: 0), "a full line takes nobody")
        XCTAssertEqual(Set(line.players(uid).map(\.slot)).count, HopscotchTuning.maxPlayers, "every player has his own queue spot")
        for id in 0..<HopscotchTuning.maxPlayers { line.remove(uid, id) }
        XCTAssertFalse(line.active)
    }

    // MARK: the court

    func testSquaresAreNumberedInOrderLeadingTowardTheCamera() {
        let s = HopscotchCourt.squares
        XCTAssertEqual(s.count, 8)
        for i in 1..<s.count { XCTAssertGreaterThanOrEqual(s[i].y, s[i - 1].y - 1e-4, "square \(i + 1) is not behind square \(i)") }
        for i in 1..<s.count { let d = simd_distance(s[i], s[i - 1]); XCTAssertTrue((0.6...1.0).contains(d), "hop \(i) is \(d) long: short legs, small hops") }
        XCTAssertEqual(s[2].y, s[3].y, accuracy: 1e-5, "3 and 4 are a double"); XCTAssertEqual(s[5].y, s[6].y, accuracy: 1e-5, "6 and 7 are a double")
    }

    func testParkPiecesFitTheLawnWithoutOverlap() {
        _ = parkLab(n: 1)
        let feet = DecorField.shared.feet
        XCTAssertEqual(feet.count, ParkToys.placed.count)
        func box(_ f: DecorFoot) -> (lo: SIMD2<Float>, hi: SIMD2<Float>) { let h = f.spec.half; return (f.centre - h, f.centre + h) }
        for i in feet.indices { for j in feet.indices where j > i {
            let a = box(feet[i]), b = box(feet[j])
            let overlap = a.lo.x < b.hi.x && b.lo.x < a.hi.x && a.lo.y < b.hi.y && b.lo.y < a.hi.y
            XCTAssertFalse(overlap, "\(feet[i].kind) overlaps \(feet[j].kind)")
        } }
        // the court is on the grass, not on the path (x = 0.7 sin(0.34 z), 0.62 wide), and inside the roam rect
        let court = feet.first { $0.kind == .hopscotch }!
        let b = box(court)
        var z = b.lo.y
        while z <= b.hi.y { let px = 0.7 * sinf(z * 0.34); XCTAssertTrue(px - 0.62 > b.hi.x || px + 0.62 < b.lo.x, "the path crosses the court at z=\(z)"); z += 0.25 }
        XCTAssertGreaterThanOrEqual(b.lo.x, -4.2); XCTAssertLessThanOrEqual(b.hi.y, 4.6)
        // the squares and the queue spots are not inside anything solid
        let solids = feet.filter { $0.kind != .hopscotch && $0.spec.solid }
        let spots = (0..<HopscotchTuning.maxPlayers).map { court.centre + court.turned(HopscotchCourt.queueSpot(slot: $0)) } + HopscotchCourt.squares.map { court.centre + court.turned($0) }
        for p in spots { for f in solids { XCTAssertGreaterThan(f.distance(p), 0.3, "a court spot at \(p) is inside the \(f.kind)") } }
    }

    func testEveryNewParkPieceHasAStandSpot() {
        let lab = parkLab(n: 1)
        let b = lab.rigs[0].brain
        for (kind, move) in [(DecorKind.hopscotch, IdleKind.decorHopscotch), (.slide, .decorSlide), (.seesaw, .decorSit), (.sandbox, .decorSit)] {
            let f = DecorField.shared.feet.first { $0.kind == kind }!
            b.decorIgnore = f.uid
            XCTAssertNotNil(b.decorStand(move, f, from: SIMD2(0, 0.5)), "\(kind) has a stand spot in the park")
        }
        XCTAssertFalse(DecorField.shared.feet.contains { $0.kind == .playtunnel }, "the park has no play tunnel")
    }

    // MARK: release

    func testToySpotsReleaseOnParkExit() {
        _ = parkLab(n: 1)
        let f = DecorField.shared
        for id in 0..<3 { f.use(uid, by: id); HopscotchLine.shared.enroll(uid, id) }
        f.take(ParkToys.seesawUID, seat: 0, by: 6); f.take(ParkToys.sandUID, seat: 1, by: 7)
        XCTAssertTrue(HopscotchLine.shared.active)
        f.set([PlacedDecor(uid: 1, kind: .beanbag, x: 0, z: 0, turns: nil)])          // (the room again)
        for u in [ParkToys.seesawUID, ParkToys.sandUID, uid, ParkToys.slideUID] {
            XCTAssertNil(f.occupant[u], "occupant \(u)"); XCTAssertNil(f.coUsers[u], "coUsers \(u)"); XCTAssertNil(f.seatOccupant[u], "seats \(u)")
            XCTAssertNil(f.progress[u], "progress \(u)"); XCTAssertNil(f.tunnelDir[u], "tunnelDir \(u)")
        }
        XCTAssertFalse(HopscotchLine.shared.active, "the line is gone with the court")
    }

    // MARK: the hops

    /// One Jelbie alone: walks to square 1, hops 1...8 in order (landing on each), two happy hops, walks off; the line is empty afterwards.
    func testLeaderHopsEverySquareInOrderThenLeaves() {
        let lab = parkLab(n: 1)
        let b = lab.rigs[0].brain, line = HopscotchLine.shared
        b.idleForced = true
        XCTAssertTrue(b.decorStart(.decorHopscotch, lab.rigs[0].sim, only: nil, uid: uid))
        var seq: [Int] = [], last = -1, finishedAt: Float = -1
        var dists: [Float] = []
        let court = DecorField.shared.foot(uid)!
        for i in 0..<(60 * 40) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            let s = line.square(uid, 0)
            if s != last && s >= 0 && s < 8 { seq.append(s); if s < 8 { dists.append(simd_distance(b.position, court.centre + court.turned(HopscotchCourt.squares[s]))) } }
            if s >= 0 { last = s }
            if b.idleState.kind == nil, !seq.isEmpty { finishedAt = Float(i) / 60; break }
        }
        XCTAssertEqual(seq, Array(0..<8), "the squares are landed on in order")
        XCTAssertGreaterThan(finishedAt, 0, "the hopscotch ends")
        for (i, d) in dists.enumerated() { XCTAssertLessThan(d, 0.55, "landing \(i + 1) is on its square (\(d) away)") }
        XCTAssertFalse(line.active, "everything is released")
        XCTAssertNil(DecorField.shared.occupant[uid]); XCTAssertNil(DecorField.shared.coUsers[uid])
    }

    /// The line: the leader starts, the others join (join chance forced to 1), queue behind and follow; they keep their spacing and nobody overlaps.
    func testFollowersQueueKeepSpacingAndNeverOverlap() {
        HopscotchTuning.joinChance = 1
        let lab = parkLab(n: 3)
        let line = HopscotchLine.shared
        for r in lab.rigs { r.brain.autonomy = true }
        lab.rigs[0].brain.idleForced = true
        XCTAssertTrue(lab.rigs[0].brain.decorStart(.decorHopscotch, lab.rigs[0].sim, only: nil, uid: uid))
        var minWhere = ""
        var minGap = Float.infinity, maxPlayers = 0, minSqGap = 99
        var seqs: [[Int]] = [[], [], []]
        var allDone = false
        for i in 0..<(60 * 80) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            maxPlayers = max(maxPlayers, line.players(uid).count)
            for a in 0..<3 {
                let s = line.square(uid, a)
                if s >= 0, s < 8, seqs[a].last != s { seqs[a].append(s) }
                for c in (a + 1)..<3 where c < 3 {
                    // overlap check on the floor spots (a hopper's centroid, a queuer's root)
                    let pa = lab.snapshot[a].pos, pc = lab.snapshot[c].pos
                    let g = simd_distance(pa, pc)
                    if g < minGap { minGap = g; minWhere = "rigs \(a),\(c) at t=\(Float(i) / 60) squares \(line.players(uid).map { "\($0.id):\($0.sq)" }) kinds \(lab.rigs.map { $0.brain.idleState.kind.map { "\($0)" } ?? "-" }) stages \(lab.rigs.map { $0.brain.idleState.slideStage })" }
                }
            }
            // spacing: whoever is behind is at least 2 squares behind the one ahead while both are hopping
            let ps = line.players(uid)
            for k in 1..<max(ps.count, 1) where ps[k].sq >= 0 && ps[k - 1].sq >= 0 && ps[k - 1].sq < 8 { minSqGap = min(minSqGap, ps[k - 1].sq - ps[k].sq) }
            if i > 600, !line.active, lab.rigs.allSatisfy({ $0.brain.idleState.kind == nil }) { allDone = true; break }
        }
        XCTAssertEqual(maxPlayers, 3, "the others joined the line: " + lab.rigs.enumerated().map { "#\($0.offset) noticed \($0.element.brain.toy.noticed) queued \($0.element.brain.toy.queued) took \($0.element.brain.toy.tookTurn) bored \($0.element.brain.toy.bored) kind \(String(describing: $0.element.brain.idleState.kind))" }.joined(separator: " | "))
        XCTAssertTrue(allDone, "the line breaks up at the end")
        for a in 0..<3 { XCTAssertEqual(seqs[a], Array(0..<8), "Jelbie \(a) landed on 1...8 in order: \(seqs[a])") }
        XCTAssertGreaterThanOrEqual(minSqGap, HopscotchTuning.spacingAhead, "followers stay \(HopscotchTuning.spacingAhead) squares behind (landed index gap \(minSqGap))")
        XCTAssertGreaterThan(minGap, 0.75, "bodies never overlap: closest centres \(minGap) \(minWhere)")
        XCTAssertFalse(line.active)
        XCTAssertTrue(DecorField.shared.coUsers[uid] == nil && DecorField.shared.occupant[uid] == nil, "the court is released")
    }

    // MARK: the Go home pill is cut out of the park's roam floor

    /// Both orientations: no free front-row spot has a body under the Go home pill, the floor still reaches the new front edge at the sides, and the slide's rider lands on free floor.
    func testParkRoamFloorKeepsOffTheGoHomePillAndHoldsTheSlideLanding() {
        RoomLayout.apply(RoomCatalog.park)
        for (label, aspect) in [("portrait", Float(393.0 / 852.0)), ("landscape", Float(852.0 / 393.0))] {
            GameCamera.configurePark()
            guard let rf = GameCamera.refreshRoam(aspect: aspect) else { return XCTFail("\(label): no roam floor") }
            let size = CGSize(width: CGFloat(1000 * aspect), height: 1000)
            let cam = GameCamera.camera(aspect: aspect)
            let pill = [HUDLayout.parkHomeRect(aspect: aspect)]
            XCTAssertGreaterThanOrEqual(rf.maxZ, 5.75,  // (the cap is 6.0; the polygon's rows are 0.25 apart and end at 5.78)
                                   "\(label): the floor reaches the front edge")
            var hits = 0, freeFront = 0
            for (i, z) in rf.zs.enumerated() where z >= 4.0 {
                for span in rf.free[i] {
                    var x = span.lowerBound
                    while x <= span.upperBound {
                        freeFront += 1
                        if HUDLayout.bodyHitsRail(x: x, z: z, viewProj: cam.viewProj, size: size, rails: pill) { hits += 1 }
                        x += 0.1
                    }
                }
            }
            XCTAssertEqual(hits, 0, "\(label): \(hits) free spots have a body under the Go home pill")
            XCTAssertGreaterThan(freeFront, 20, "\(label): there is still floor at the front")
            // the sides of the front row stay reachable
            XCTAssertTrue(rf.free.last.map { !$0.isEmpty } ?? false, "\(label): the front row has free floor")
            // the slide's rider lands inside a free span, with a body clear of the pill
            DecorField.shared.set(ParkToys.placed)
            let sf = DecorField.shared.foot(ParkToys.slideUID)!
            let landing = sf.centre + sf.turned(SIMD2(0, BlobBrain.slideAt(BlobBrain.slideLength).z))
            let row = rf.zs.indices.min { abs(rf.zs[$0] - landing.y) < abs(rf.zs[$1] - landing.y) }!
            XCTAssertTrue(rf.free[row].contains { $0.contains(landing.x) }, "\(label): landing \(landing) is not in a free span of row z \(rf.zs[row])")
            XCTAssertFalse(HUDLayout.bodyHitsRail(x: landing.x, z: landing.y, viewProj: cam.viewProj, size: size, rails: pill), "\(label): the rider lands under the Go home pill")
        }
    }

    // MARK: the slide is solid

    /// The park has no tunnel, and over a long soak (many seeds) nobody has a root inside the slide's footprint except while really using it (the ladder, the platform, the ride, getting up).
    func testNoOneStandsInsideTheParkSlide() {
        XCTAssertFalse(ParkToys.placed.contains { $0.kind == .playtunnel }, "no tunnel in the park")
        var longest: Float = 0, where_ = ""
        let sf = DecorField.shared.foot(ParkToys.slideUID) ?? { _ = parkLab(n: 1); return DecorField.shared.foot(ParkToys.slideUID)! }()
        let landing = sf.centre + sf.turned(SIMD2(0, BlobBrain.slideAt(BlobBrain.slideLength).z))
        XCTAssertLessThanOrEqual(landing.y + 0.5, GameCamera.roamRect.max.y, "the chute's end (\(landing)) leaves floor for a body")
        XCTAssertGreaterThan(sf.distance(landing), 0.3, "the rider lands clear of the footprint")
        for seed in UInt64(1)...6 {
            let lab = parkLab(n: 3, seed: seed)
            for r in lab.rigs { r.brain.autonomy = true }
            let sl = DecorField.shared.foot(ParkToys.slideUID)!
            if seed % 2 == 1 { lab.rigs[0].brain.idleForced = true; _ = lab.rigs[0].brain.decorStart(.decorSlide, lab.rigs[0].sim, only: .slide, uid: nil) }          // (odd seeds: someone really rides)
            var inside = [Float](repeating: 0, count: 3)
            for i in 0..<(60 * 60) {
                lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
                for (k, r) in lab.rigs.enumerated() {
                    let using = r.brain.idleState.kind == .decorSlide && r.brain.idleState.decorUID == ParkToys.slideUID
                    if !using, sl.distance(r.brain.position) < -0.15 { inside[k] += 1.0 / 60 } else { inside[k] = 0 }
                    if inside[k] > longest { longest = inside[k]; where_ = "seed \(seed) rig \(k) t=\(Float(i) / 60) kind \(String(describing: r.brain.idleState.kind)) ignore \(String(describing: r.brain.decorIgnore)) pending \(String(describing: r.brain.pending)) held \(r.brain.held) sl \(r.brain.sleepLocked) insT \(r.brain.insideDecorT) free \(String(describing: r.brain.decorFreeSpot(near: r.brain.position))) script \(r.brain.script) auton \(r.brain.autonomy) at \(r.brain.position) depth \(sl.distance(r.brain.position))" }
                }
            }
        }
        // (a rider lands at the chute's end and walks out: nobody is inside it unless riding)
        XCTAssertLessThan(longest, 1.5, "someone stood inside the slide without using it for \(longest) s: \(where_)")
    }

    /// The room slide's ride ends with him walking on to clear floor: 1 s after the script ends he is outside the footprint, and `decorExitCheck` never had to ease him out.
    func testRoomSlideRideEndsClearOfTheSlide() throws {
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        defer { DecorField.shared.clear() }
        guard let base = LegsDrawnAuditTests.fromMove("decor2: climb the slide, sit, ride, exit") else { return XCTFail("no slide scenario") }
        var report = ""
        for c in 0..<OnePieceInvariantTests.characters.count {
            var sc = base
            var need: Float = 0.5          // (decorExitCheck's own "inside": footprint * reach - 0.05)
            var ended: Float?, clock: Float = 0, rode = false, maxStuck: Float = 0, depthAfter: Float?, edgeAtEnd: Float = 0, clearAt: Float?
            sc.each = { r in
                clock += r.sim.stepDt
                let k = r.brain.idleState.kind
                if k == .decorSlide { rode = true }
                guard rode, let f = DecorField.shared.foot(7) else { return }
                maxStuck = max(maxStuck, r.brain.insideStuckT)
                need = r.brain.footprint * f.spec.reach - 0.05
                if let e = ended, clearAt == nil, f.distance(r.brain.position) >= need { clearAt = clock - e }
                if k == nil, ended == nil { ended = clock; edgeAtEnd = f.distance(r.brain.position) }
                if let e = ended, depthAfter == nil, clock >= e + 1 { depthAfter = f.distance(r.brain.position) }
            }
            _ = OnePieceInvariantTests.run(sc, char: c, shoes: false, pacing: .hz60, seed: 3)
            let who = OnePieceInvariantTests.characters[c].0
            XCTAssertTrue(rode, "\(who): rode the slide")
            XCTAssertNotNil(ended, "\(who): the script ended")
            guard let d = depthAfter else { XCTFail("\(who): ran out of time before 1 s after the ride"); continue }
            report += String(format: "%@: at script end %.2f from the footprint edge, 1 s later %.2f (clear after %.2f s, maxStuckT %.2f)\n", who, edgeAtEnd, d, clearAt ?? -1, maxStuck)
            XCTAssertGreaterThanOrEqual(d, need, "\(who): 1 s after the ride he is still inside the slide's footprint (\(d) from its edge, needs \(need))")
            XCTAssertLessThan(maxStuck, 3, "\(who): decorExitCheck had to ease him out (insideStuckT \(maxStuck))")
        }
        print("ROOMSLIDE\n" + report)
    }
}
