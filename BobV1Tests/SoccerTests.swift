//
//  SoccerTests.swift
//  Soccer (replaces the football, 2026-10-20): the ball and goal resources load; both place in portrait and landscape; a stomp kick moves the ball 0.8...3 u;
//  a dribble keeps the ball ahead and close; two Jellies complete a pass exchange; a scripted shot into the goal scores, puffs the net and rolls the ball back
//  out in front of the goal; a wide shot does not score; a stuck ball is recovered within 30 s (a Jelly's rescue dribble, and the boundary nudge on its own);
//  1000 random kicks never tunnel through a wall, a piece, the goal's frame or a Jelly; old saves with a football get a soccer ball; the catalogue and the
//  arrange flow treat both pieces like any decor. FeetAttach / ArmCap run the kick, dribble, shot and celebration (FeetAttachTests.batch2Decor).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SoccerTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let goalAt = SIMD2<Float>(0, -1.6)

    override func setUp() { room(440.0 / 956.0); DecorField.shared.clear(); DecorField.shared.bodies = []; SoccerState.shared.reset(); SoccerEvents.clear(); SoccerEvents.sink = nil }
    override func tearDown() { DecorField.shared.clear(); DecorField.shared.bodies = []; SoccerState.shared.reset(); SoccerEvents.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    private func room(_ aspect: Float) { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: aspect); GameCamera.refreshRoam(aspect: aspect) }

    /// A ball (uid 7) and maybe a goal (uid 8) in the room; a Jelly standing at `from`.
    func installed(ball: SIMD2<Float>, goal: SIMD2<Float>? = nil, from: SIMD2<Float> = SIMD2(-1.0, 1.0), extra: [PlacedDecor] = []) -> MotionRig {
        var placed = [PlacedDecor(uid: 7, kind: .soccerball, x: ball.x, z: ball.y)] + extra
        if let goal { placed.append(PlacedDecor(uid: 8, kind: .minigoal, x: goal.x, z: goal.y)) }
        DecorField.shared.set(placed)
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.brain.anticsEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: from)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        return r
    }
    /// The field's step after the Jelly's (`r.run` ticks him; inside its `each` this is all that is left): his position is a bumper.
    func step(_ r: MotionRig) { DecorField.shared.bodies = [(r.brain.steerID, r.brain.position)]; DecorField.shared.tick(dt: 1.0 / 60) }
    /// A whole frame outside `r.run`: the Jelly, then the field.
    func frame(_ r: MotionRig) { r.tick(); step(r) }
    func ball() -> SIMD2<Float> { DecorField.shared.anim[7]!.pos }
    func ballLocal() -> SIMD2<Float> { ball() - Self.goalAt }

    // MARK: resources, catalogue, placement

    func testTheSoccerResourcesLoadWithTheirPartsAndWeights() {
        guard let b = DecorMeshes.loaded[.soccerball], let g = DecorMeshes.loaded[.minigoal] else { return XCTFail("resources missing") }
        XCTAssertEqual(b.parts.map { $0.name }, ["ball"]); XCTAssertEqual(b.triangles, 1080)
        XCTAssertEqual(b.part("ball")?.pivot.y ?? 0, SoccerTuning.radius, accuracy: 1e-3, "the ball turns about its centre")
        XCTAssertEqual(Set(g.parts.map { $0.name }), ["frame", "net"]); XCTAssertEqual(g.triangles, 2276)
        let w = g.part("net")!.w
        XCTAssertEqual(w.max() ?? 0, 1, accuracy: 0.02, "the bulge weight peaks at 1 at the back of the net")
        XCTAssertEqual(g.part("frame")!.w.max() ?? 1, 0, accuracy: 1e-4, "the frame does not bulge")
        XCTAssertGreaterThan(DecorModels.thumbnail(.soccerball).indices.count / 3, 100)
        XCTAssertGreaterThan(DecorModels.thumbnail(.minigoal).indices.count / 3, 100)
        // the net pose: a goal's kick on the piece bulges the net toward -z by w * 0.16 * amount
        var a = DecorAnim(); a.kick = 1; a.kickT = 0
        XCTAssertEqual(DecorModels.netBulge(a), 1, accuracy: 1e-4)
        let b0 = RoomMeshBuilder(), b1 = RoomMeshBuilder()
        DecorModels.add(.minigoal, at: .zero, lift: 0, anim: DecorAnim(), time: 0, uid: 8, into: b0)
        DecorModels.add(.minigoal, at: .zero, lift: 0, anim: a, time: 0, uid: 8, into: b1)
        let dz = zip(b0.mesh.vertices, b1.mesh.vertices).map { $0.0.pos.z - $0.1.pos.z }
        XCTAssertEqual(dz.max() ?? 0, SoccerTuning.netPush, accuracy: 0.01, "the back of the net moves 0.16 toward -z at full bulge")
        XCTAssertGreaterThanOrEqual(dz.min() ?? -1, -1e-4, "nothing moves toward the room")
    }

    func testCatalogueHasTheBallAndGoalAndNoFootball() {
        let b = StoreCatalog.item("decor-soccerball"), g = StoreCatalog.item("decor-minigoal")
        XCTAssertEqual(b?.price, 35); XCTAssertEqual(b?.roomUnits, 1); XCTAssertEqual(b?.decor?.category, .toys)
        XCTAssertEqual(g?.price, 70); XCTAssertEqual(g?.roomUnits, 2); XCTAssertEqual(g?.decor?.category, .toys)
        XCTAssertNil(StoreCatalog.item("decor-football"))
        XCTAssertTrue(ShopTab.toys.items.contains { $0.id == "decor-soccerball" } && ShopTab.toys.items.contains { $0.id == "decor-minigoal" })
        XCTAssertEqual(DecorKind.soccerball.interaction, .soccerKick); XCTAssertNil(DecorKind.minigoal.interaction)
        XCTAssertTrue(DecorKind.soccerball.rolls && DecorKind.soccerball.isBallLike && !DecorKind.soccerball.spec.solid)
        XCTAssertTrue(DecorKind.minigoal.spec.solid, "walkers go round the goal")
    }

    func testAnOldSaveWithAFootballOwnsASoccerBall() throws {
        let json = """
        {"counts":{"decor-football":2,"sushi":1},"pages":[],"wearables":[],"worn":{},"starterGiven":true,"newItems":0,"placed":[],
         "placedAt":[{"uid":3,"kind":"football","x":1.0,"z":0.5},{"uid":4,"kind":"cushion","x":-1.0,"z":0.5}],"nextDecorUID":5}
        """
        let s = try JSONDecoder().decode(StoreBook.Saved.self, from: Data(json.utf8))
        XCTAssertEqual(s.placedAt?.map { $0.kind }, [.soccerball, .cushion], "a placed football is a soccer ball")
        let m = StoreBook.migrateSoccer(s)
        XCTAssertEqual(m.counts["decor-soccerball"], 2); XCTAssertNil(m.counts["decor-football"]); XCTAssertEqual(m.counts["sushi"], 1)
        // through the book itself
        let d = UserDefaults(suiteName: "SoccerTests.migration")!
        d.removePersistentDomain(forName: "SoccerTests.migration")
        d.set(Data(json.utf8), forKey: "k")
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: true, defaults: d, key: "k")
        XCTAssertEqual(book.count("decor-soccerball"), 2)
        XCTAssertEqual(book.placedDecor.first?.kind, .soccerball)
        XCTAssertEqual(book.placedCount("decor-soccerball"), 1); XCTAssertEqual(book.unplaced("decor-soccerball"), 1)
        d.removePersistentDomain(forName: "SoccerTests.migration")
    }

    func testBallAndGoalPlaceInPortraitAndLandscapeAndArrangeLikeAnyDecor() {
        for (name, a) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(956.0 / 440.0))] {
            room(a)
            let book = StoreBook(wallet: DropsWallet(persists: false), persists: false)
            book.grant("decor-minigoal"); book.grant("decor-soccerball")
            guard let g = book.place("decor-minigoal") else { return XCTFail("\(name): the goal has a spot") }
            guard let b = book.place("decor-soccerball") else { return XCTFail("\(name): the ball has a spot") }
            XCTAssertTrue(DecorPlacement.isValid(.minigoal, at: g.at, among: [b]), "\(name): the goal's spot is valid")
            XCTAssertEqual(book.roomUnitsUsed, 3)
            DecorField.shared.set(book.placedDecor)
            // the goal is in the room, where a Jelly can stand in front of it for a shot (at least three of the six kick spots are standable floor)
            let gf = DecorField.shared.foot(g.uid)!
            let standable = DecorField.shared.kickSpots(gf).filter { s in
                let q = RoomLayout.resolve(position: SIMD3(s.stand.x, 0, s.stand.y), radius: 0.55)
                return simd_distance(SIMD2(q.x, q.z), s.stand) < 0.1
            }.count
            XCTAssertGreaterThanOrEqual(standable, 3, "\(name): kick spots in front of the goal (\(standable) of 6)")
            // arrange: move the goal and the ball to another valid spot; the field (and the ball's live position) follow; the double tap finds them from above
            let to = DecorPlacement.findSpot(.minigoal, among: [b]).map { SIMD2($0.x + 0.1, $0.y) } ?? g.at
            if DecorPlacement.isValid(.minigoal, at: to, among: [b], ignoring: g.uid) { XCTAssertTrue(book.move(g.uid, to: to), "\(name): the goal moves") }
            let bto = b.at + SIMD2(0.4, 0)
            if DecorPlacement.isValid(.soccerball, at: bto, among: book.placedDecor.filter { $0.uid != b.uid }, ignoring: b.uid) {
                XCTAssertTrue(book.move(b.uid, to: bto), "\(name): the ball moves")
                DecorField.shared.set(book.placedDecor)
                XCTAssertEqual(DecorField.shared.anim[b.uid]!.pos, bto, "\(name): the ball's live position follows the drag")
            }
            DecorField.shared.set(book.placedDecor)
            for p in book.placedDecor {
                let c = DecorField.shared.position(DecorField.shared.foot(p.uid)!)
                let hit = DecorField.shared.hit(origin: SIMD3(c.x, 5, c.y), dir: SIMD3(0, -1, 0))
                XCTAssertEqual(hit?.uid, p.uid, "\(name): a tap from above picks the \(p.kind)")
            }
            XCTAssertNil(DecorField.shared.restingBall(), "\(name): a ball at its saved spot is not 'resting elsewhere'")
            DecorField.shared.clear()
        }
    }

    // MARK: the kick

    func testAStompKickMovesTheBallBetween08And3Units() {
        for (i, seed) in [UInt64(3), 11, 27].enumerated() {
            setUp()
            SoccerEvents.clear()
            let start = SIMD2<Float>(0.3, 0.9)
            let r = installed(ball: start, from: SIMD2(-1.4, 1.4))
            r.brain.seed = seed
            r.brain.soccerModeForce = 0
            r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(.soccerKick, r.sim), "seed \(seed): the kick starts")
            XCTAssertEqual(DecorField.shared.occupant[7], r.brain.steerID)
            var path: Float = 0, last = ball(), stomped = false, maxSpeed: Float = 0, lastInfo = ""
            r.run(30, until: { r.brain.idleState.kind == nil && r.t > 1 }) {
                if r.brain.idleState.kind != nil { lastInfo = String(format: "phaseT %.2f stage %d yielding %d feetActive %d script %@ speed %.3f steps %d", r.brain.idleState.phaseT, r.brain.idleState.soccer.stage, r.brain.idleState.yielding ? 1 : 0, r.brain.feet.active ? 1 : 0, "\(r.brain.script)", simd_length(DecorField.shared.anim[7]!.vel), r.brain.idleState.steps) }
                self.step(r)
                let p = self.ball(); path += simd_distance(p, last); last = p
                maxSpeed = max(maxSpeed, simd_length(DecorField.shared.anim[7]!.vel))
                if r.brain.idleState.soccer.stage == 1, r.brain.feet.active { stomped = true }
            }
            MotionLog.write("SOCCER kick seed \(seed) last frame: \(lastInfo)")
            let an = DecorField.shared.anim[7]!
            MotionLog.write(String(format: "SOCCER kick seed %d: t %.2f path %.2f ball (%.2f, %.2f) vel (%.3f, %.3f) kicker %d age %.2f jelly (%.2f, %.2f) stage %d mode %d events %@", Int(seed), r.t, path, an.pos.x, an.pos.y, an.vel.x, an.vel.y, an.kicker, an.kickAge, r.brain.px, r.brain.pz, r.brain.idleState.soccer.stage, r.brain.idleState.soccer.mode.rawValue, "\(SoccerEvents.recent)"))
            XCTAssertNil(r.brain.idleState.kind, "seed \(seed): finished"); XCTAssertNil(DecorField.shared.occupant[7], "seed \(seed): let go")
            XCTAssertTrue(stomped, "seed \(seed): the stomp step")
            let kicks = SoccerEvents.recent.compactMap { e -> Float? in if case .kick(let j, let v, let shot) = e, j == r.brain.steerID, !shot { return v }; return nil }
            XCTAssertGreaterThanOrEqual(kicks.count, 1, "seed \(seed): a kick event")
            for v in kicks { XCTAssertTrue(SoccerTuning.kickSpeed.contains(v), "seed \(seed): kick speed \(v) in 1.6...3.4") }
            XCTAssertGreaterThanOrEqual(path, 0.8, "seed \(seed): the ball rolled \(path)"); XCTAssertLessThanOrEqual(path, 3.0 * Float(max(kicks.count, 1)) + 0.1, "seed \(seed): not further than its kicks allow (\(path))")
            XCTAssertLessThanOrEqual(maxSpeed, SoccerTuning.kickSpeed.upperBound + 0.05, "seed \(seed): never faster than the hardest kick")
            XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-5)
            XCTAssertFalse(DecorField.shared.anim[7]!.moving, "seed \(seed): the ball has stopped")
            _ = i
        }
    }

    func testADribbleKeepsTheBallAheadAndCloseThenShoots() {
        let r = installed(ball: SIMD2(1.4, 1.2), goal: Self.goalAt, from: SIMD2(-1.0, 1.4))
        r.brain.seed = 5
        r.brain.soccerModeForce = 1
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.soccerKick, r.sim), "the dribble starts")
        XCTAssertEqual(r.brain.idleState.soccer.mode, .dribble)
        let spot = DecorField.shared.kickSpots(DecorField.shared.foot(8)!).min { simd_distance($0.ball, SIMD2(1.4, 1.2)) < simd_distance($1.ball, SIMD2(1.4, 1.2)) }!.ball
        var frames = 0, aheadOK = 0, lateralOK = 0, maxLateral: Float = 0, maxAhead: Float = 0, nudges = 0, nudged = false, reached = false, shot = false
        var lastKicks = 0
        r.run(45, until: { r.brain.idleState.kind == nil && r.t > 1 }) {
            self.step(r)
            let kicks = SoccerEvents.count { if case .kick(_, _, false) = $0 { return true }; return false }
            if kicks > lastKicks { lastKicks = kicks; nudged = true; nudges += 1 }
            if r.brain.idleState.kind == .soccerKick, r.brain.idleState.soccer.isDribbling, nudged {
                let fwd = SIMD2(sinf(r.brain.yaw), cosf(r.brain.yaw)), rel = self.ball() - r.brain.position
                let ahead = simd_dot(rel, fwd), lateral = abs(rel.x * fwd.y - rel.y * fwd.x)
                frames += 1
                if ahead > -0.1 { aheadOK += 1 }
                if lateral <= 0.6 { lateralOK += 1 }
                maxLateral = max(maxLateral, lateral); maxAhead = max(maxAhead, ahead)
            }
            if simd_distance(self.ball(), spot) < 0.9 { reached = true }
            if r.brain.idleState.soccer.mode == .shoot { shot = true }
            if Int(r.t * 60) % 20 == 0 {
                let fwd = SIMD2(sinf(r.brain.yaw), cosf(r.brain.yaw)), rel = self.ball() - r.brain.position, an = DecorField.shared.anim[7]!
                MotionLog.write(String(format: "SOCCER dribble trace t %.2f jelly (%.2f, %.2f) yaw %.2f ball (%.2f, %.2f) speed %.2f ahead %.2f lateral %.2f stage %d mode %d legs %d script %@ feet %d", r.t, r.brain.px, r.brain.pz, r.brain.yaw, an.pos.x, an.pos.y, simd_length(an.vel), simd_dot(rel, fwd), abs(rel.x * fwd.y - rel.y * fwd.x), r.brain.idleState.soccer.stage, r.brain.idleState.soccer.mode.rawValue, r.brain.idleState.soccer.legs, "\(r.brain.script)", r.brain.feet.active ? 1 : 0))
            }
        }
        MotionLog.write(String(format: "SOCCER dribble: %d frames, ahead ok %.2f, lateral ok %.2f, max lateral %.2f, max ahead %.2f, nudges %d", frames, Float(aheadOK) / Float(max(frames, 1)), Float(lateralOK) / Float(max(frames, 1)), maxLateral, maxAhead, nudges))
        XCTAssertGreaterThanOrEqual(nudges, 2, "the toe nudges the ball on at footfalls")
        XCTAssertGreaterThan(frames, 60)
        XCTAssertGreaterThanOrEqual(Float(aheadOK) / Float(max(frames, 1)), 0.9, "the ball stays ahead of him")
        XCTAssertGreaterThanOrEqual(Float(lateralOK) / Float(max(frames, 1)), 0.9, "and within 0.6 of his line")
        XCTAssertLessThanOrEqual(maxAhead, 2.2, "never runs away from him")
        XCTAssertTrue(reached, "the ball is taken to the goal's kick spot")
        XCTAssertTrue(shot, "then he lines up the shot")
        XCTAssertNil(r.brain.idleState.kind); XCTAssertNil(DecorField.shared.occupant[7]); XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-5)
    }

    func testTwoJelliesCompleteAPassExchange() {
        for seed in [UInt64(5), 9] {
            setUp()
            DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0.2, z: 1.0)])
            let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.5, 1.4), SIMD2(1.8, 1.6)], quiet: true, seed: seed)
            Self.keep.append(lab)
            let a = lab.rigs[0], b = lab.rigs[1]
            XCTAssertTrue(a.brain.socialStart(.pass, with: b.brain, a.sim), "seed \(seed): the pass starts")
            var passes = 0, done = false, stomps = 0, wasStep = false
            for _ in 0..<(60 * 80) {
                lab.tick(watching: false)
                DecorField.shared.bodies = lab.rigs.map { ($0.brain.steerID, $0.brain.position) }
                DecorField.shared.tick(dt: 1.0 / 60)
                if let s = a.brain.social { passes = max(passes, s.passes) }
                let kicker = (a.brain.social?.roles ?? 0) == 0 ? a : b
                let st = kicker.brain.feet.active && kicker.brain.social?.phase == 1
                if st && !wasStep { stomps += 1 }
                wasStep = st
                if a.brain.social == nil, b.brain.social == nil, passes > 0 { done = true; break }
            }
            XCTAssertTrue(done, "seed \(seed): the exchange ended")
            XCTAssertGreaterThanOrEqual(passes, 2, "seed \(seed): 2...4 passes (\(passes))"); XCTAssertLessThanOrEqual(passes, 4)
            let kicks = SoccerEvents.recent.compactMap { e -> (Int, Float)? in if case .kick(let j, let v, _) = e { return (j, v) }; return nil }
            XCTAssertEqual(Set(kicks.map { $0.0 }), [0, 1], "seed \(seed): both kicked")
            for (_, v) in kicks { XCTAssertTrue(SoccerTuning.kickSpeed.contains(v), "seed \(seed): pass speed \(v)") }
            XCTAssertGreaterThanOrEqual(stomps, 2, "seed \(seed): the kicker stomps")
            XCTAssertTrue((lab.events[0] + lab.events[1]).contains { if case .ended(.pass, _, .done) = $0 { return true }; return false }, "seed \(seed): ended well")
            XCTAssertNil(DecorField.shared.occupant[7])
            for r in lab.rigs { XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-5); XCTAssertNil(r.brain.idleState.kind) }
        }
    }

    // MARK: the goal

    func testAScriptedKickIntoTheGoalScoresPuffsTheNetAndRollsTheBallBackOut() {
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0.1, z: 0.1), PlacedDecor(uid: 8, kind: .minigoal, x: Self.goalAt.x, z: Self.goalAt.y)])
        DecorField.shared.kickBall(7, direction: SIMD2(-0.05, -1), speed: 3.0, by: 1)
        SoccerState.shared.newKick(7)
        var maxBulge: Float = 0, minZ: Float = 9, sawIn = false, t: Float = 0, stopT: Float = -1
        for _ in 0..<(60 * 10) {
            DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
            let g = DecorField.shared.anim[8]!
            maxBulge = max(maxBulge, DecorModels.netBulge(g))
            let l = ballLocal()
            minZ = min(minZ, l.y)
            if DecorField.shared.anim[7]!.inGoal == 8 { sawIn = true }
            if stopT < 0, t > 1, !DecorField.shared.anim[7]!.moving { stopT = t }
        }
        XCTAssertEqual(SoccerState.shared.goals, 1, "one goal")
        XCTAssertTrue(SoccerEvents.recent.contains { if case .goal(let s, let g) = $0 { return s == 1 && g == 8 }; return false }, "the goal event names the scorer and the goal")
        XCTAssertTrue(sawIn, "the ball was in the mouth")
        XCTAssertGreaterThan(maxBulge, 0.5, "the net puffs (\(maxBulge))")
        XCTAssertGreaterThanOrEqual(minZ, GoalGeometry.backZ + SoccerTuning.radius - 0.03, "never through the back of the net (\(minZ))")
        let l = ballLocal()
        XCTAssertFalse(DecorField.shared.anim[7]!.moving, "at rest"); XCTAssertGreaterThan(stopT, 0)
        XCTAssertEqual(l.y, GoalGeometry.mouthZ + SoccerTuning.rollOutStop, accuracy: 0.2, "it rolled back out to ~0.6 in front of the goal (\(l))")
        XCTAssertLessThan(abs(l.x), 0.6)
        XCTAssertEqual(DecorField.shared.anim[7]!.inGoal, -1, "out of the mouth again")
        XCTAssertFalse(SoccerState.shared.isStuck(7))
        // the net rang down: the goal piece is at rest again
        XCTAssertLessThan(DecorField.shared.anim[8]!.kick, 0.01)
        XCTAssertFalse(DecorField.shared.anim[8]!.active)
    }

    func testAWideShotAndAPostDoNotScore() {
        // wide: just outside the right post, a near miss
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 1.05, z: 0.1), PlacedDecor(uid: 8, kind: .minigoal, x: Self.goalAt.x, z: Self.goalAt.y)])
        DecorField.shared.kickBall(7, direction: SIMD2(0, -1), speed: 2.6, by: 1); SoccerState.shared.newKick(7)
        for _ in 0..<(60 * 8) { DecorField.shared.tick(dt: 1.0 / 60) }
        XCTAssertEqual(SoccerState.shared.goals, 0, "wide: no goal")
        XCTAssertTrue(SoccerEvents.recent.contains { if case .nearMiss(1, 8) = $0 { return true }; return false }, "a near miss is reported")
        XCTAssertFalse(SoccerEvents.recent.contains { if case .goal = $0 { return true }; return false })
        XCTAssertLessThan(ballLocal().y, GoalGeometry.mouthZ, "it rolled on past the goal line, outside")
        XCTAssertEqual(DecorField.shared.anim[7]!.inGoal, -1)
        // the post: from a kick spot at an angle onto the right post; it rattles off and stays out
        SoccerState.shared.reset(); SoccerEvents.clear()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0.3, z: 0.1), PlacedDecor(uid: 8, kind: .minigoal, x: Self.goalAt.x, z: Self.goalAt.y)])
        let post = Self.goalAt + SIMD2(0.77, GoalGeometry.mouthZ + 0.02)
        let d = simd_normalize(post - SIMD2(0.3, 0.1))
        DecorField.shared.kickBall(7, direction: d, speed: 2.8, by: 1); SoccerState.shared.newKick(7)
        var minPostDist: Float = 9
        for _ in 0..<(60 * 8) {
            DecorField.shared.tick(dt: 1.0 / 60)
            let l = ballLocal()
            for s in GoalGeometry.solids { minPostDist = min(minPostDist, RoomLayout.boxDistanceXZ(l, .init(centre: s.centre, half: s.half, height: 1, radius: 0.02))) }
        }
        XCTAssertEqual(SoccerState.shared.goals, 0, "off the post: no goal")
        XCTAssertGreaterThanOrEqual(minPostDist, SoccerTuning.radius - 0.03, "never inside the post")
        XCTAssertLessThan(minPostDist, SoccerTuning.radius + 0.05, "it did meet the post")
        XCTAssertFalse(DecorField.shared.anim[7]!.moving)
    }

    func testAShotFromTheKickSpotScoresAndHeCelebratesWithABounce() {
        let r = installed(ball: SIMD2(0.5, 0.1), goal: Self.goalAt, from: SIMD2(1.6, 1.6))
        r.brain.seed = 7
        r.brain.soccerModeForce = 2
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.soccerKick, r.sim), "the shot starts")
        XCTAssertEqual(r.brain.idleState.soccer.mode, .shoot)
        var bounced = false, goalBeforeBounce = false, maxBulge: Float = 0, k = 0
        r.run(40, until: { r.brain.idleState.kind == nil && r.t > 1 }) {
            self.step(r); k += 1
            maxBulge = max(maxBulge, DecorModels.netBulge(DecorField.shared.anim[8]!))
            if r.brain.idleState.kind == .bounce { bounced = true; if SoccerState.shared.goals == 1 { goalBeforeBounce = true } }
            let an = DecorField.shared.anim[7]!
            if k % 15 == 0, SoccerState.shared.goals > 0 || an.moving { MotionLog.write(String(format: "SOCCER shot trace t %.2f local (%.2f, %.2f) vel (%.2f, %.2f) inGoal %d inNet %d goals %d jelly (%.2f, %.2f) kind %@", r.t, self.ballLocal().x, self.ballLocal().y, an.vel.x, an.vel.y, an.inGoal, SoccerState.shared.inNet.contains(7) ? 1 : 0, SoccerState.shared.goals, r.brain.px, r.brain.pz, "\(r.brain.idleState.kind.map { $0.rawValue } ?? "-")")) }
        }
        XCTAssertNil(r.brain.idleState.kind, "the celebration is over")
        r.run(5, until: { !DecorField.shared.anim[7]!.moving && r.t > 1 }) { self.step(r) }          // (the ball finishes its gentle roll back out while he stands there)
        XCTAssertEqual(SoccerState.shared.goals, 1, "GOAL")
        XCTAssertTrue(SoccerEvents.recent.contains { if case .kick(_, _, true) = $0 { return true }; return false }, "the shot event")
        XCTAssertTrue(SoccerEvents.recent.contains { if case .goal(let s, 8) = $0 { return s == r.brain.steerID }; return false }, "he is the scorer")
        XCTAssertTrue(bounced && goalBeforeBounce, "the jump for joy after the goal")
        XCTAssertGreaterThan(maxBulge, 0.5, "the net puffed")
        XCTAssertEqual(ballLocal().y, GoalGeometry.mouthZ + SoccerTuning.rollOutStop, accuracy: 0.25, "the ball rolled back out in front of the goal (\(ballLocal()))")
        XCTAssertFalse(DecorField.shared.anim[7]!.moving, "the ball has come to rest")
        XCTAssertNil(DecorField.shared.occupant[7]); XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-5)
        XCTAssertLessThan(r.sim.centroid().y, 1.0)
    }

    // MARK: stuck

    func testAStuckBallIsFlaggedAt20sAndRescuedByAJellyWithin30s() {
        // against the back edge of the floor
        let r = installed(ball: SIMD2(-1.0, -2.3), from: SIMD2(0.8, 1.2))
        r.brain.seed = 3
        var t: Float = 0
        while t < SoccerTuning.stuckAfter + 0.1 { self.frame(r); t += 1.0 / 60 }
        XCTAssertTrue(SoccerState.shared.isStuck(7), "stuck after 20 s")
        XCTAssertNotNil(DecorField.shared.stuckBall())
        MotionLog.write("SOCCER rescue: open floor near the ball \(String(describing: DecorField.shared.nearestOpenFloor(to: ball()))) stand \(String(describing: r.brain.soccerStand(DecorField.shared.foot(7)!, from: r.brain.position))) plan mode \(r.brain.soccerPlan.mode) fixed(-1,-2.3+0.72) \(r.brain.fixed(SIMD2(-1.0, -1.58))) fixed(-0.3,-2.3) \(r.brain.fixed(SIMD2(-0.3, -2.3)))")
        XCTAssertEqual(IdleTable.decorWeights(.happy, offers: [.soccerKick]).first?.weight, BlobBrain.soccerRescueWeight, "the rescue dominates the decor table")
        // the scheduler's pick: the rescue mode
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.soccerKick, r.sim), "the rescue starts")
        XCTAssertEqual(r.brain.idleState.soccer.mode, .rescue)
        r.run(30 - t, until: { r.brain.idleState.kind == nil && r.t > 1 }) {
            self.step(r); t += 1.0 / 60
            if Int(t * 60) % 30 == 0 {
                let an = DecorField.shared.anim[7]!
                MotionLog.write(String(format: "SOCCER rescue trace t %.2f jelly (%.2f, %.2f) yaw %.2f ball (%.2f, %.2f) speed %.2f stage %d mode %d legs %d script %@ feet %d phaseT %.2f", t, r.brain.px, r.brain.pz, r.brain.yaw, an.pos.x, an.pos.y, simd_length(an.vel), r.brain.idleState.soccer.stage, r.brain.idleState.soccer.mode.rawValue, r.brain.idleState.soccer.legs, "\(r.brain.script)", r.brain.feet.active ? 1 : 0, r.brain.idleState.phaseT))
            }
        }
        XCTAssertLessThanOrEqual(t, 30.5, "within 30 s")
        XCTAssertTrue(DecorField.shared.openFloor(ball()), "the ball is on open floor (\(ball()))")
        XCTAssertFalse(SoccerState.shared.isStuck(7))
        XCTAssertNil(r.brain.idleState.kind); XCTAssertNil(DecorField.shared.occupant[7])
        XCTAssertGreaterThanOrEqual(SoccerEvents.count { if case .kick = $0 { return true }; return false }, 1, "dribbled out")
    }

    func testAStuckBallIsNudgedOutOnItsOwnBy30s() {
        for p in [SIMD2<Float>(-1.0, -2.3), SIMD2(3.1, 0.4)] {
            setUp()
            // a corner-ish spot and one against a side wall; furniture beside it too
            DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: p.x, z: p.y), PlacedDecor(uid: 9, kind: .armchair, x: 2.0, z: 0.4)])
            var t: Float = 0, movedAt: Float = -1
            MotionLog.write("SOCCER nudge \(p): open floor \(String(describing: DecorField.shared.nearestOpenFloor(to: p))) openFloor(3.1,1.8) \(DecorField.shared.openFloor(SIMD2(3.1, 1.8), margin: 0.5)) clear \(DecorField.shared.clearRoll(from: p, to: SIMD2(3.1, 1.8))) xlim(0.4) \(DecorField.soccerFloor(z: 0.4).xlim) xlim(1.8) \(DecorField.soccerFloor(z: 1.8).xlim) chair dist \(DecorField.shared.foot(9)!.distance(p)) sofa \(RoomLayout.sofaDistanceXZ(p))")
            while t < 40 {
                DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
                if movedAt < 0, simd_distance(ball(), p) > 0.1 { movedAt = t }
                if Int(t * 60) % 60 == 0, t > 19 { let a = DecorField.shared.anim[7]!; MotionLog.write(String(format: "SOCCER nudge trace t %.1f ball (%.2f, %.2f) vel (%.2f, %.2f) stuckT %.1f", t, a.pos.x, a.pos.y, a.vel.x, a.vel.y, SoccerState.shared.stuckT[7] ?? 0)) }
            }
            XCTAssertGreaterThan(movedAt, SoccerTuning.stuckAfter, "\(p): left alone for the first 20 s")
            XCTAssertLessThanOrEqual(movedAt, 30, "\(p): nudged by 30 s (\(movedAt))")
            XCTAssertTrue(DecorField.shared.openFloor(ball()), "\(p): rests on open floor (\(ball()))")
            XCTAssertFalse(DecorField.shared.anim[7]!.moving)
        }
    }

    // MARK: no tunnelling

    func testAThousandRandomKicksNeverTunnelThroughWallsFurnitureTheGoalOrJellies() {
        let furniture = [PlacedDecor(uid: 8, kind: .minigoal, x: 0, z: -1.6), PlacedDecor(uid: 9, kind: .armchair, x: 2.2, z: 0.3), PlacedDecor(uid: 10, kind: .bookshelf, x: -2.4, z: -1.4),
                         PlacedDecor(uid: 11, kind: .pouf, x: -1.6, z: 1.6), PlacedDecor(uid: 12, kind: .diningset, x: 1.6, z: 2.2)]
        let bodies: [(id: Int, pos: SIMD2<Float>)] = [(0, SIMD2(-0.6, 0.6)), (1, SIMD2(1.0, -0.4))]
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Float { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return Float(rng >> 40) / Float(1 << 24) }
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: 0, z: 0.8)] + furniture)
        DecorField.shared.bodies = bodies
        let field = DecorField.shared, r = SoccerTuning.radius, tol: Float = 0.03
        var violations: [String] = [], kicks = 0, frames = 0, bounces = 0
        let solids = field.feet.filter { $0.spec.solid && $0.kind != .minigoal }
        let goal = field.foot(8)!
        while kicks < 1000 {
            // a start on open floor, clear of the Jellies
            var p = SIMD2<Float>(rnd() * 6 - 3, rnd() * 5 - 2.2)
            var tries = 0
            while !(field.openFloor(p) && bodies.allSatisfy { simd_distance($0.pos, p) > 0.9 }) && tries < 200 { p = SIMD2(rnd() * 6 - 3, rnd() * 5 - 2.2); tries += 1 }
            guard tries < 200 else { continue }
            field.set([PlacedDecor(uid: 7, kind: .soccerball, x: p.x, z: p.y)] + furniture)
            let a = rnd() * 2 * .pi
            let speed = SoccerTuning.kickSpeed.lowerBound + rnd() * (SoccerTuning.kickSpeed.upperBound - SoccerTuning.kickSpeed.lowerBound)
            field.kickBall(7, direction: SIMD2(sinf(a), cosf(a)), speed: speed, by: -1)
            kicks += 1
            var lastV = field.anim[7]!.vel
            for _ in 0..<(60 * 5) {
                field.tick(dt: 1.0 / 60); frames += 1
                let an = field.anim[7]!, q = an.pos
                if simd_dot(an.vel, lastV) < 0, simd_length(an.vel) > 0.1 { bounces += 1 }
                lastV = an.vel
                let fl = DecorField.soccerFloor(z: q.y)
                if q.y < fl.zlo + r - tol || q.y > fl.zhi - r + tol || abs(q.x) > fl.xlim + tol { violations.append("kick \(kicks): outside the floor at \(q)") }
                if RoomLayout.sofaDistanceXZ(q) < r - tol { violations.append("kick \(kicks): in the sofa at \(q)") }
                for s in solids where s.distance(q) < r - tol { violations.append("kick \(kicks): inside the \(s.kind) at \(q)") }
                let l = q - goal.centre
                for s in GoalGeometry.solids where RoomLayout.boxDistanceXZ(l, .init(centre: s.centre, half: s.half, height: 1, radius: 0.02)) < r - tol { violations.append("kick \(kicks): inside the goal's frame at \(l)") }
                if abs(l.x) < GoalGeometry.outerHalfX, l.y < GoalGeometry.backZ + r - tol, l.y > GoalGeometry.rearZ - r { violations.append("kick \(kicks): through the back of the net at \(l)") }
                for b in bodies where simd_distance(q, b.pos) < SoccerTuning.bodyRadius + r - tol { violations.append("kick \(kicks): through Jelly \(b.id) at \(q)") }
                if !an.moving { break }
                if violations.count > 20 { break }
            }
            if violations.count > 20 { break }
        }
        MotionLog.write("SOCCER tunnelling: \(kicks) kicks, \(frames) frames, \(bounces) bounces, \(violations.count) violations")
        XCTAssertEqual(kicks, 1000)
        XCTAssertGreaterThan(bounces, 100, "the kicks did meet things")
        XCTAssertTrue(violations.isEmpty, "no tunnelling: \(violations.prefix(5))")
    }

    /// The ball bumps gently off a Jelly standing in its way and reports rolling past another.
    func testTheBallBumpsOffAJellyAndRollsPastAnother() {
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .soccerball, x: -1.5, z: 0.6)])
        DecorField.shared.bodies = [(0, SIMD2(0.5, 0.6)), (1, SIMD2(-0.5, 1.4))]
        DecorField.shared.kickBall(7, direction: SIMD2(1, 0), speed: 2.4, by: 2); SoccerState.shared.newKick(7)
        var minGap: Float = 9
        for _ in 0..<(60 * 5) { DecorField.shared.tick(dt: 1.0 / 60); minGap = min(minGap, simd_distance(ball(), SIMD2(0.5, 0.6))) }
        XCTAssertLessThan(ball().x, 0.5, "it came back off him")
        XCTAssertGreaterThanOrEqual(minGap, SoccerTuning.bodyRadius + SoccerTuning.radius - 0.03, "never into his body")
        XCTAssertTrue(SoccerEvents.recent.contains { if case .rolledPast(1, 2) = $0 { return true }; return false }, "it rolled past the other Jelly")
    }

    // MARK: the reaction bus (liveliness)

    func testSoccerEventsLandOnTheReactionBus() {
        let kicker = installed(ball: SIMD2(0, 0.6), goal: Self.goalAt, from: SIMD2(-1.0, 1.0))
        let other = installed(ball: SIMD2(0, 0.6), goal: Self.goalAt, from: SIMD2(0.8, 1.2))
        kicker.brain.steerID = 1; other.brain.steerID = 2
        kicker.brain.autonomy = true; other.brain.autonomy = true          // (a rig's brain is driven by the test; the reactions want a free one)
        let bus = ReactionBus()
        bus.brains = { [kicker.brain, other.brain] }
        kicker.brain.bus = bus; other.brain.bus = bus
        SoccerEvents.sink = { [weak bus] e in bus?.handleSoccer(e) }
        defer { SoccerEvents.sink = nil }
        SoccerEvents.emit(.kick(jelly: 1, speed: 2, shot: false))
        XCTAssertEqual(bus.posted.count, 0, "a kick posts nothing")
        SoccerEvents.emit(.goal(scorer: 1, goal: 8))
        XCTAssertEqual(bus.posted.last?.kind, .scoredGoal); XCTAssertEqual(bus.posted.last?.source, 1)
        XCTAssertEqual(bus.posted.last.map { simd_distance($0.pos, Self.goalAt) } ?? 9, 0, accuracy: 0.3, "at the goal")
        SoccerEvents.emit(.fumble(jelly: 1))
        XCTAssertEqual(bus.posted.last?.kind, .missedKick); XCTAssertEqual(kicker.brain.expr.kind, .oh)
        SoccerEvents.emit(.nearMiss(jelly: 1, goal: 8))
        XCTAssertTrue(kicker.brain.expr.kind == .worried || kicker.brain.expr.kind == .excited, "a near miss shows on his face: \(kicker.brain.expr.kind)")
        other.brain.react.cool = 0; other.brain.react.pending = nil
        SoccerEvents.emit(.rolledPast(jelly: 2, kicker: 1))
        XCTAssertEqual(other.brain.react.pending?.kind, .startle, "the ball rolling past startles the one it passed")
    }
}
