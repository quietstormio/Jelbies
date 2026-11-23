//
//  PlayNetTests.swift
//  The soccer net of Play mode (play-net-r1, owner 2026-11-23): the picker card, the net's geometry and the ball's paths (goal / post / bar / over / wide), where it is placed and its
//  fallbacks, nothing saved, the player's own goal hidden and restored, the goal's hold and roll-out, the celebration.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PlayNetTests: XCTestCase {
    override func setUp() { reset() }
    override func tearDown() { reset() }
    func reset() {
        GameCamera.playBlend = 0; RoomLayout.ballSpheres = []
        DecorField.shared.clear()
        TossTuning.zBack = -2.4; TossTuning.zFront = 9
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 393.0 / 852.0)
    }
    func book() -> StoreBook { StoreBook(wallet: DropsWallet(persists: false), persists: false) }
    static let net = TossNet(centre: SIMD2(0, -2.4 - GoalGeometry.backZ * PlayNetTuning.scale))

    // MARK: the card

    func testTheNetCardIsOfferedOnlyWithTheSoccerBallAndNeverInThePark() {
        let b = book()
        b.wallet.add(500)
        XCTAssertFalse(PlayToyRegistry.offered(book: b).contains { $0.toyID == SoccerNetToy.id }, "nothing owned: no net card")
        XCTAssertEqual(b.buy("decor-ball"), .bought)
        XCTAssertFalse(PlayToyRegistry.offered(book: b).contains { $0.toyID == SoccerNetToy.id }, "the bouncy ball alone: no net card")
        b.grant("decor-soccerball")
        XCTAssertEqual(PlayToyRegistry.offered(book: b).map(\.toyID), ["ball-ball", "ball-soccerball"], "the soccer ball alone: nothing about a net")
        XCTAssertEqual(b.count("decor-minigoal"), 0)
        b.grant("decor-minigoal")
        XCTAssertEqual(PlayToyRegistry.offered(book: b).map(\.toyID), ["ball-ball", "ball-soccerball", SoccerNetToy.id], "with the net owned too, its card follows the soccer ball directly")
        let b2 = book(); b2.grant("decor-minigoal")
        XCTAssertTrue(PlayToyRegistry.offered(book: b2).isEmpty, "the net alone (no soccer ball): no card")
        XCTAssertFalse(PlayToyRegistry.offered(book: b, park: true).contains { $0.toyID == SoccerNetToy.id }, "the park's strip never shows the net")
        XCTAssertEqual(PlayToyRegistry.toy(SoccerNetToy.id)?.title, "Soccer net")
        XCTAssertNotNil(StoreCatalog.item(PlayToyRegistry.toy(SoccerNetToy.id)!.storeID), "the card's picture is the Mini goal's store art")
        XCTAssertEqual(PlayToyRegistry.toy(SoccerNetToy.id)?.storeID, "decor-minigoal")
        XCTAssertEqual(b.count("decor-minigoal"), 1, "showing the card bought nothing more")
    }

    func testTheNetIsNotAStoreOrBagOrCatalogueItem() {
        XCTAssertFalse(DecorKind.allCases.contains { $0.rawValue.contains("playnet") }, "no new decor kind")
        XCTAssertEqual(StoreCatalog.items.filter { $0.id == "decor-minigoal" }.count, 1, "the Mini goal is sold once, as before")
        XCTAssertFalse(StoreCatalog.items.contains { $0.id.contains("net") && $0.id != "decor-minigoal" })
    }

    /// Owner 2026-11-23: the net is bought in the Shop (decor-minigoal), is not a room piece, and an old save with one placed puts it away (still owned).
    func testTheSoccerNetIsSoldOwnedNotPlaceableAndAPlacedOneIsPutAwayOnLoad() throws {
        let item = try XCTUnwrap(StoreCatalog.item("decor-minigoal"))
        XCTAssertEqual(item.name, "Soccer net"); XCTAssertEqual(item.price, 70)
        XCTAssertEqual(item.description, "A goal for soccer. Comes out in Play.")
        XCTAssertTrue(ShopTab.toys.items.contains { $0.id == "decor-minigoal" }, "still sold")
        let b = book(); b.wallet.add(500)
        XCTAssertEqual(b.buy("decor-minigoal"), .bought)
        XCTAssertEqual(b.count("decor-minigoal"), 1, "owned")
        XCTAssertFalse(b.canPlace(item)); XCTAssertNotNil(b.placeBlocker(item))
        XCTAssertNil(b.place("decor-minigoal")); XCTAssertTrue(b.placedDecor.isEmpty, "not placeable")
        XCTAssertNotNil(b.place("decor-minigoal", dev: true), "the dev aid still can")
        // a save with a placed one (and one in another room's stash) loads with them put away, ownership kept, the rest untouched
        var s = StoreBook.Saved()
        s.counts = ["decor-minigoal": 1, "decor-soccerball": 1]
        s.placedAt = [PlacedDecor(uid: 4, kind: .minigoal, x: 0, z: -1.6), PlacedDecor(uid: 5, kind: .soccerball, x: 1, z: 1)]
        s.stash = ["loft": [PlacedDecor(uid: 6, kind: .minigoal, x: 0, z: -1.6)]]
        let back = try JSONDecoder().decode(StoreBook.Saved.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(back.placedAt?.map(\.uid), [5], "the net is put away, the ball stays")
        XCTAssertEqual(back.stash?["loft"]?.count, 0)
        XCTAssertEqual(back.counts["decor-minigoal"], 1, "still owned")
    }

    // MARK: the ball and the net: fixed paths

    /// Flies one shot of the list and says what it did first (goal / post / bar / over / wide).
    func fly(_ s: PlayNetShot, net n: TossNet, radius: Float = SoccerTuning.radius, seconds: Float = 6) -> (result: String, goals: Int, ball: TossBall) {
        var b = TossBall(pos: .zero, radius: radius)
        let (from, v) = s.launch(n)
        b.pos = from; b.vel = v
        var w = TossWorld(); w.xHalf = { _ in 4 }; w.net = n
        var first: String?, over = false, goals = 0
        for _ in 0..<Int(seconds * 60) {
            for e in b.step(1.0 / 60, in: w) {
                guard case .net(let ne) = e else { continue }
                switch ne {
                case .goal: goals += 1; first = first ?? "goal"
                case .post: first = first ?? "post"
                case .bar: first = first ?? "bar"
                case .lid: first = first ?? "over"
                }
            }
            if n.contains(SIMD2(b.pos.x, b.pos.z)), b.pos.y - radius > n.barTop { over = true }
        }
        return (first ?? (over ? "over" : "wide"), goals, b)
    }

    func testEveryFixedPathDoesWhatItShould() {
        for s in PlayNetShot.list(innerHalf: Self.net.innerHalf, radius: SoccerTuning.radius) {
            let r = fly(s, net: Self.net)
            XCTAssertEqual(r.result, s.expect, "\(s.name)")
            if s.expect == "goal" { XCTAssertEqual(r.goals, 1, "\(s.name): one goal only") } else { XCTAssertEqual(r.goals, 0, "\(s.name): no goal") }
        }
    }

    func testAGoalBallDiesInTheNetAndStaysThere() {
        let s = PlayNetShot.list(innerHalf: Self.net.innerHalf, radius: SoccerTuning.radius)[0]
        let r = fly(s, net: Self.net, seconds: 3)
        XCTAssertTrue(r.ball.inNet)
        XCTAssertLessThan(r.ball.speedXZ, 0.1, "its speed dies inside the net")
        XCTAssertLessThan(r.ball.pos.z, Self.net.mouthZ, "it stays inside")
        XCTAssertGreaterThan(r.ball.pos.z, Self.net.rearZ)
        XCTAssertLessThan(abs(r.ball.pos.x), Self.net.innerHalf)
    }

    func testABallOverTheBarNeverRestsOnTheNet() {
        // dropped from above onto the net's top: it rolls off the front and ends on the floor, never perched
        for x in [Float(-0.9), 0, 0.5, 1.1] {
            var b = TossBall(pos: SIMD3(x, 3.2, Self.net.centre.y + 0.1), radius: SoccerTuning.radius)
            var w = TossWorld(); w.xHalf = { _ in 4 }; w.net = Self.net
            for _ in 0..<(60 * 8) { b.step(1.0 / 60, in: w) }
            XCTAssertLessThan(b.pos.y, SoccerTuning.radius + 0.05, "x \(x): on the floor, not on the net")
            XCTAssertFalse(b.inNet, "x \(x): it did not score from above")
        }
    }

    func testTheNetIsInertWithoutIt() {
        // a ball through where the mouth would be, no net in the world: the same flight as before this change
        let s = PlayNetShot.list(innerHalf: Self.net.innerHalf, radius: SoccerTuning.radius)[0]
        var a = TossBall(pos: s.launch(Self.net).from, radius: SoccerTuning.radius); a.vel = s.launch(Self.net).v
        var b = a
        var w = TossWorld(); w.xHalf = { _ in 4 }
        var evs: [TossEvent] = []
        for _ in 0..<240 { evs += a.step(1.0 / 60, in: w); b.step(1.0 / 60, in: w) }
        XCTAssertEqual(a.pos, b.pos)
        XCTAssertFalse(evs.contains { if case .net = $0 { return true }; return false })
        XCTAssertFalse(a.inNet)
    }

    func testTheNetsNumbers() {
        let n = Self.net
        XCTAssertEqual(n.outerHalf * 2, 2.6, accuracy: 0.02, "2.6 wide")
        XCTAssertEqual(n.barTop, 1.46, accuracy: 0.02, "about 1.4 tall")
        XCTAssertEqual(n.barBottom / PlayNetTuning.scale, 0.855, accuracy: 0.001)
        XCTAssertEqual(n.rearZ + 0.576 - 0.576, n.centre.y + GoalGeometry.rearZ * 1.6, accuracy: 1e-4)
        XCTAssertEqual(n.centre.y - GoalGeometry.backZ * 1.6 + GoalGeometry.backZ * 1.6, n.centre.y, accuracy: 1e-5)
        XCTAssertEqual(n.centre.y + GoalGeometry.backZ * PlayNetTuning.scale, TossTuning.zBack, accuracy: 1e-4, "the back of the net is the ball's back limit")
    }

    // MARK: where it stands

    func testPlacementDefaultsToTheBackCentreAndSlidesAndFallsBack() {
        let reach: (Float) -> Float = { _ in 4 }
        let k = PlayNetTuning.scale
        let z0 = TossTuning.zBack - GoalGeometry.backZ * k
        // free: centred, back at zBack
        let a = PlayNetPlacement.place(zBack: TossTuning.zBack, lineZ: 1.0, reach: reach, blocked: { _ in false })
        XCTAssertEqual(a?.x ?? 9, 0, accuracy: 1e-5); XCTAssertEqual(a?.y ?? 9, z0, accuracy: 1e-5)
        // a piece in the middle of the back row: it slides to the nearest clear spot along x (inside the row, clear of the piece)
        let piece = SIMD2<Float>(0, z0)
        let b = PlayNetPlacement.place(zBack: TossTuning.zBack, lineZ: 1.0, reach: reach, blocked: { simd_distance($0, piece) < 0.5 })
        XCTAssertNotNil(b)
        XCTAssertEqual(b!.y, z0, accuracy: 1e-5, "slid, not moved forward")
        XCTAssertGreaterThanOrEqual(abs(b!.x), 0.5 + TossNet(centre: b!).outerHalf - 0.25, "clear of the piece")
        XCTAssertLessThanOrEqual(abs(b!.x) + TossNet(centre: b!).outerHalf, 4 + 1e-4, "inside the visible row")
        // the whole back row blocked (a wall of furniture across z0 .. z0 + 0.6): forward in 0.3 steps
        let c = PlayNetPlacement.place(zBack: TossTuning.zBack, lineZ: 1.0, reach: reach, blocked: { $0.y < z0 - 0.3 })
        XCTAssertNotNil(c)
        XCTAssertEqual(c!.y, z0 + 0.3, accuracy: 1e-4, "one step forward")
        XCTAssertEqual((c!.y - z0) / 0.3, ((c!.y - z0) / 0.3).rounded(), accuracy: 1e-3, "in steps of 0.3")
        XCTAssertLessThanOrEqual(TossNet(centre: c!).mouthZ, 1.0 - PlayNetTuning.minLineGap + 1e-4, "never nearer than 1.6 to the line")
        // everything blocked: none
        XCTAssertNil(PlayNetPlacement.place(zBack: TossTuning.zBack, lineZ: 1.0, reach: reach, blocked: { _ in true }))
        // a line too near to leave the gap: none at all
        XCTAssertNil(PlayNetPlacement.place(zBack: TossTuning.zBack, lineZ: -0.3, reach: reach, blocked: { _ in false }))
        // a narrow visible row: slides never leave it
        let narrow = PlayNetPlacement.place(zBack: TossTuning.zBack, lineZ: 1.0, reach: { _ in 1.0 }, blocked: { _ in false })
        XCTAssertNil(narrow, "a row narrower than the net: it does not fit")
    }

    // MARK: the controller: hold, roll-out, celebration, nothing left behind

    func rigs(_ n: Int) -> [MotionRig] {
        BlobBrain.pickBudgetSeconds = .infinity
        _ = OnePieceInvariantTests.configured
        return (0..<n).map { i in
            let r = MotionRig(game: true, settle: 0.5)
            PlayTossTests.keep.append(r)
            r.renderSamples = false
            r.brain.autonomy = true; r.brain.seed = UInt64(i * 7 + 5)
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: SIMD2(Float(i - 1) * 1.6, 0.8)); r.run(0.3)
            return r
        }
    }

    func testAGoalIsHeldRolledOutAndCelebratedAndDoneLeavesNothing() {
        PlayTossTests.room(PlayTossTests.portrait)
        ToyTuning.settle = 0
        let rs = rigs(3)
        func js() -> [PlayJelly] { rs.enumerated().map { PlayJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) } }
        let p = PlayToss(); p.viewSize = PlayTossTests.portrait
        var events: [PlayEvent] = []
        p.onEvent = { events.append($0) }
        var goalCalls: [Int?] = []
        p.begin(ball: .soccerball, title: "Soccer ball", jellies: js(), snapCamera: true)
        XCTAssertFalse(p.netUp, "without the net call: no net")
        p.netStart(blockers: [])
        XCTAssertTrue(p.netUp)
        p.net.onGoal = { goalCalls.append($0) }
        let n = p.net.spec!
        XCTAssertLessThanOrEqual(n.mouthZ, (p.spots.values.map(\.y).min() ?? 9) - PlayNetTuning.minLineGap + 1e-3, "the mouth keeps 1.6 off the line")
        var w = TossWorld(); w.xHalf = PlayToss.ballXHalf; w.net = n
        for _ in 0..<200 { for r in rs { r.tick() }; p.tick(dt: rs[0].sim.stepDt, world: w, jellies: js()) }
        let shot = PlayNetShot.list(innerHalf: n.innerHalf, radius: p.ball.radius)[0]
        let (from, v) = shot.launch(n)
        p.launch(from: from, velocity: v)
        var t: Float = 0, goalAt: Float?, rolledOut: Float?
        let dt = rs[0].sim.stepDt
        var cheering = Set<Int>()
        while t < 6 {
            for r in rs { r.tick() }
            p.tick(dt: dt, world: w, jellies: js()); t += dt
            if goalAt == nil, events.contains(where: { if case .goal = $0 { return true }; return false }) { goalAt = t }
            if let g = goalAt {
                for (i, r) in rs.enumerated() where r.brain.idleState.kind == .joy || r.brain.idleState.kind == .bounce { cheering.insert(i) }
                if rolledOut == nil, !p.ball.inNet, p.ball.pos.z > n.mouthZ { rolledOut = t - g }
                if t - g < PlayNetTuning.holdTime - 0.1 { XCTAssertTrue(p.ball.inNet, "held in the net"); XCTAssertEqual(p.phase, .loose) }
            }
        }
        XCTAssertNotNil(goalAt, "the middle shot scores")
        XCTAssertEqual(events.filter { if case .goal = $0 { return true }; return false }.count, 1, "one goal event")
        XCTAssertEqual(goalCalls.count, 1, "the goal callback fires once")
        XCTAssertEqual(p.net.goals, 1)
        XCTAssertEqual(cheering.count, 3, "the player's own throw: all three cheer")
        if let r = rolledOut { XCTAssertGreaterThan(r, PlayNetTuning.holdCheer - 0.2, "the ball stays in the net while the cheer runs (1.6 s at least)"); XCTAssertLessThan(r, 3.0) } else { XCTFail("the ball never rolled out of the net") }
        p.end()
        XCTAssertFalse(p.netUp)
        XCTAssertNil(p.net.spec)
        for r in rs { XCTAssertFalse(r.brain.reserved, "released") }
        for _ in 0..<400 { for r in rs { r.tick() } }
        for r in rs { XCTAssertFalse(r.brain.commanded, "the cheer's commanded flag clears itself when the cheer ends"); XCTAssertNil(r.brain.idleState.kind == .joy ? 1 : nil) }
    }

    /// A game with the net, the middle shot fired; steps until `until` says stop (or `maxT`), returns the controller and the rigs.
    func goalGame(returns: Bool, maxT: Float, until: (PlayToss, [MotionRig]) -> Bool) -> (PlayToss, [MotionRig], TossNet, Float?) {
        PlayTossTests.room(PlayTossTests.portrait)
        ToyTuning.settle = 0
        let rs = rigs(3)
        func js() -> [PlayJelly] { rs.enumerated().map { PlayJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) } }
        let p = PlayToss(); p.viewSize = PlayTossTests.portrait
        p.begin(ball: .soccerball, title: "Soccer ball", jellies: js(), snapCamera: true)
        p.netStart(blockers: [])
        p.net.returnsToPlayer = returns
        let n = p.net.spec!
        var w = TossWorld(); w.xHalf = PlayToss.ballXHalf; w.net = n
        for _ in 0..<200 { for r in rs { r.tick() }; p.tick(dt: rs[0].sim.stepDt, world: w, jellies: js()) }
        let (from, v) = PlayNetShot.list(innerHalf: n.innerHalf, radius: p.ball.radius)[0].launch(n)
        p.launch(from: from, velocity: v)
        var t: Float = 0, goalAt: Float?
        while t < maxT {
            for r in rs { r.tick() }
            p.tick(dt: rs[0].sim.stepDt, world: w, jellies: js()); t += rs[0].sim.stepDt
            if goalAt == nil, p.net.goals > 0 { goalAt = t }
            if until(p, rs) { break }
        }
        return (p, rs, n, goalAt)
    }

    func testAfterAGoalTheBallIsReturnedToThePlayerAndNobodyIsSentToTheNet() {
        var sawReturn = false, flyingAtLaunch = false, walkedToNet = false, cheerEnd: Float?
        var goalT: Float?
        let (p, rs, n, g) = goalGame(returns: true, maxT: 14) { p, rs in
            if p.net.returning, !sawReturn { sawReturn = true; flyingAtLaunch = p.phase == .flying && p.returnAim != nil && p.ball.vel.z > 0.5 }
            if p.net.goals > 0, !sawReturn, rs.allSatisfy({ $0.brain.idleState.kind == nil }) { cheerEnd = cheerEnd ?? p.clock }
            if p.net.goals > 0 {
                let net = p.net.spec!
                for r in rs { if case .walk(let t, _) = r.brain.script, net.contains(t, margin: 0.8) { walkedToNet = true } }
            }
            return sawReturn && p.phase == .inHand
        }
        _ = goalT; goalT = g
        XCTAssertNotNil(g, "the middle shot scores")
        XCTAssertTrue(sawReturn, "the net sends the ball back to the player")
        XCTAssertTrue(flyingAtLaunch, "the next phase is a return flight with a landing aim, toward the player")
        XCTAssertFalse(walkedToNet, "nobody is ordered to the net")
        XCTAssertEqual(p.phase, .inHand, "caught at the hand")
        XCTAssertEqual(p.rescues, 0, "no rescue was needed")
        _ = (rs, n)
        p.end()
    }

    /// Merge with ball step 3: a goal while a pass chain runs ends the chain before the cheer; "Pass it back" (`recall()`) while the ball is held does nothing.
    func testAGoalEndsAPassChainAndRecallInTheNetDoesNothing() {
        var set = false, atGoal = false, chainAtGoal = true, pendingAtGoal = -1, holdBefore = false, holdAfter = false, phaseSame = false, keepingAfter = true, cheersStarted = false
        let (p, rs, _, g) = goalGame(returns: true, maxT: 14) { p, rs in
            if !set { set = true; p.setOwn(.passing(left: 2, from: 0, to: 1)); return false }
            if p.net.goals > 0, !atGoal {
                atGoal = true; chainAtGoal = p.keeping; pendingAtGoal = p.pendingPasses
                holdBefore = p.net.hold != nil
                let ph = p.phase
                p.recall()
                holdAfter = p.net.hold != nil; phaseSame = p.phase == ph; keepingAfter = p.keeping
            }
            if atGoal, rs.contains(where: { $0.brain.idleState.kind == .joy || $0.brain.idleState.kind == .bounce }) { cheersStarted = true }
            return atGoal && p.phase == .inHand
        }
        XCTAssertNotNil(g, "the middle shot scores")
        XCTAssertFalse(chainAtGoal, "a goal ends the pass chain (keeping false)")
        XCTAssertEqual(pendingAtGoal, 0, "no pass is pending")
        XCTAssertTrue(holdBefore && holdAfter && phaseSame, "recall() in the net changes nothing: the ball is still held")
        XCTAssertFalse(keepingAfter)
        XCTAssertTrue(cheersStarted, "the cheers start")
        XCTAssertEqual(p.phase, .inHand, "the ball still comes back to the hand")
        _ = rs
        p.end()
    }

    func testWithReturnsToPlayerOffTheOldShortRollOutHappens() {
        var returning = false, rolledOutLoose = false
        let (p, _, n, g) = goalGame(returns: false, maxT: 6) { p, _ in
            if p.net.returning { returning = true }
            if p.net.goals > 0, p.net.hold == nil, p.phase == .loose || p.phase == .flying, p.ball.pos.z > p.net.spec!.mouthZ { rolledOutLoose = p.phase == .loose || rolledOutLoose }
            return rolledOutLoose
        }
        XCTAssertNotNil(g)
        XCTAssertFalse(returning, "no return flight to the player")
        XCTAssertTrue(rolledOutLoose, "the ball rolled out of the mouth and is handed back as a loose ball")
        XCTAssertLessThan(p.ball.pos.z, n.mouthZ + 1.6, "it lies near the mouth (0.9 in front), for the loose-ball handling to fetch")
        p.end()
    }

    func testTheScorerBouncesAndTheOthersCheer() {
        PlayTossTests.room(PlayTossTests.portrait)
        ToyTuning.settle = 0
        let rs = rigs(3)
        func js() -> [PlayJelly] { rs.enumerated().map { PlayJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) } }
        let p = PlayToss(); p.viewSize = PlayTossTests.portrait
        p.begin(ball: .soccerball, title: "Soccer ball", jellies: js(), snapCamera: true)
        p.netStart(blockers: [])
        var w = TossWorld(); w.xHalf = PlayToss.ballXHalf; w.net = p.net.spec
        for _ in 0..<120 { for r in rs { r.tick() }; p.tick(dt: rs[0].sim.stepDt, world: w, jellies: js()) }
        p.celebrateGoal(scorer: 1)
        var kinds: [Int: IdleKind] = [:]
        for _ in 0..<60 { for r in rs { r.tick() }; p.tick(dt: rs[0].sim.stepDt, world: w, jellies: js()); for (i, r) in rs.enumerated() { if let k = r.brain.idleState.kind { kinds[i] = k } } }
        XCTAssertEqual(kinds[1], .bounce, "the scorer does the bounce")
        XCTAssertEqual(kinds[0], .joy); XCTAssertEqual(kinds[2], .joy)
        XCTAssertEqual(rs[1].brain.idleState.reps, 3, "three reps")
        p.end()
    }

    func testShotApi() {
        PlayTossTests.room(PlayTossTests.portrait)
        let rs = rigs(3)
        func js() -> [PlayJelly] { rs.enumerated().map { PlayJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) } }
        let p = PlayToss(); p.viewSize = PlayTossTests.portrait
        p.begin(ball: .soccerball, title: "Soccer ball", jellies: [], snapCamera: true)
        XCTAssertNil(p.shotSpot(ball: SIMD2(0, 0)), "no net: no spot")
        p.netStart(blockers: [])
        let n = p.net.spec!
        XCTAssertEqual(p.netMouth, SIMD2(n.centre.x, n.mouthZ))
        XCTAssertEqual(p.netInnerHalfWidth ?? 0, n.innerHalf, accuracy: 1e-5)
        var wide = 0
        for _ in 0..<400 {
            let a = p.shotAim(spread: 1)
            XCTAssertEqual(a.y, n.mouthZ, accuracy: 1e-5, "on the mouth line")
            if abs(a.x - n.centre.x) > n.innerHalf { wide += 1 }
        }
        XCTAssertTrue((70...130).contains(wide), "about a quarter wide of a post on purpose: \(wide)/400")
        let ball = SIMD2<Float>(0.4, n.mouthZ + 1.2)
        if let s = p.shotSpot(ball: ball) {
            XCTAssertEqual(simd_length(s.dir), 1, accuracy: 1e-4)
            XCTAssertFalse(n.contains(s.stand, margin: 0.3), "never inside the net")
            XCTAssertEqual(simd_distance(s.stand + s.dir * SoccerTuning.standBack, ball), 0, accuracy: 1e-3, "the ball is in front of him")
            XCTAssertGreaterThan(simd_dot(s.dir, SIMD2(0, -1)), 0.5, "he shoots toward the mouth")
        } else { XCTFail("a ball in front of the net has a spot") }
        XCTAssertNil(p.shotSpot(ball: SIMD2(0, n.mouthZ - 0.5)), "a ball in the net / beside it: no spot")
        p.end()
    }

    // MARK: the decor: temporary, never saved, the owner's own goal hidden and back

    func testTheNetIsTemporaryNothingIsSavedAndTheOwnersGoalComesBack() {
        let care = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "PlayNet.1")!)
        care.store.grant("decor-soccerball"); care.store.grant("decor-minigoal")
        _ = care.store.place("decor-minigoal", dev: true)
        care.syncDecor()
        let before = care.store.placedDecor
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        let encBefore = try! enc.encode(before)
        XCTAssertEqual(DecorField.shared.kinds(.minigoal).count, 1)
        let ownUID = DecorField.shared.kinds(.minigoal)[0].uid
        let ownAt = DecorField.shared.kinds(.minigoal)[0].centre
        care.play.begin(ball: .soccerball, title: "Soccer ball", jellies: [], snapCamera: true)
        care.play.netStart(blockers: [])
        care.syncDecor()
        let goals = DecorField.shared.kinds(.minigoal)
        XCTAssertEqual(goals.count, 1, "never two goals")
        XCTAssertEqual(goals[0].uid, PlayNetTuning.uid)
        XCTAssertEqual(goals[0].spec.half.x, DecorKind.minigoal.spec.half.x * 1.6, accuracy: 1e-4, "measured 1.6 times")
        XCTAssertEqual(care.store.placedDecor, before, "the store's list is untouched")
        XCTAssertEqual(try! enc.encode(care.store.placedDecor), encBefore, "byte-identical")
        XCTAssertNotNil(DecorField.shared.anim[PlayNetTuning.uid], "an anim: the puff can be driven")
        // the play world has the net, the room's own goal is not a solid piece of it
        XCTAssertNotNil(care.tossWorld().net)
        care.play.end()
        care.syncDecor()
        XCTAssertFalse(DecorField.shared.feet.contains { $0.uid == PlayNetTuning.uid }, "no temporary piece left")
        let after = DecorField.shared.kinds(.minigoal)
        XCTAssertEqual(after.count, 1); XCTAssertEqual(after[0].uid, ownUID); XCTAssertEqual(after[0].centre, ownAt, "the room's goal is back where it was")
        XCTAssertEqual(try! enc.encode(care.store.placedDecor), encBefore)
        XCTAssertNil(care.tossWorld().net)
    }

    func testTheNetSurvivesARotationAndStaysClearOfTheLine() {
        PlayTossTests.room(PlayTossTests.portrait)
        let rs = rigs(3)
        func js() -> [PlayJelly] { rs.enumerated().map { PlayJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) } }
        let p = PlayToss(); p.viewSize = PlayTossTests.portrait
        var goals = 0
        p.net.onGoal = { _ in goals += 1 }
        p.begin(ball: .soccerball, title: "Soccer ball", jellies: js(), snapCamera: true)
        p.netStart(blockers: [])
        XCTAssertNotNil(p.net.onGoal, "the goal callback survives the start")
        var w = TossWorld(); w.xHalf = PlayToss.ballXHalf
        for size in [PlayTossTests.landscape, PlayTossTests.portrait, PlayTossTests.landscape] {
            PlayTossTests.room(size)
            p.viewSize = size
            for _ in 0..<60 { for r in rs { r.tick() }; w.net = p.net.spec; p.tick(dt: rs[0].sim.stepDt, world: w, jellies: js()) }
            XCTAssertTrue(p.netUp, "still up after the turn")
            let n = p.net.spec!
            XCTAssertLessThanOrEqual(n.mouthZ, (p.spots.values.map(\.y).min() ?? 9) - PlayNetTuning.minLineGap + 1e-3, "keeps 1.6 off the new line")
            XCTAssertLessThanOrEqual(abs(n.centre.x) + n.outerHalf, min(PlayToss.ballReach(n.rearZ), PlayToss.ballReach(n.frontZ)) + 1e-3, "inside the new frame's back row")
        }
        p.end()
        XCTAssertNotNil(p.net.onGoal, "and the end")
    }

    func testNoRoomPostsTheMessage() {
        PlayTossTests.room(PlayTossTests.portrait)
        let rs = rigs(1)
        let p = PlayToss(); p.viewSize = PlayTossTests.portrait
        p.begin(ball: .soccerball, title: "Soccer ball", jellies: [PlayJelly(id: 0, brain: rs[0].brain, sim: rs[0].sim, skinner: rs[0].skinner)], snapCamera: true)
        // a blocker body in front of every candidate: none fits
        let wall = stride(from: Float(-6), through: 6, by: 0.5).flatMap { x in stride(from: Float(-3), through: 3, by: 0.5).map { SIMD2(x, $0) } }
        p.netStart(blockers: wall)
        XCTAssertFalse(p.netUp, "no room: the game starts without the net")
        XCTAssertNil(p.net.spec)
        p.end()
    }

    // MARK: keep-out round (no body in the goal; the net returns what lands in it)

    private func netGame() -> (PlayToss, [MotionRig], TossWorld, () -> [PlayJelly]) {
        PlayTossTests.room(PlayTossTests.portrait)
        ToyTuning.settle = 0
        let rs = rigs(3)
        func js() -> [PlayJelly] { rs.enumerated().map { PlayJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) } }
        let p = PlayToss(); p.viewSize = PlayTossTests.portrait
        p.begin(ball: .soccerball, title: "Soccer ball", jellies: js(), snapCamera: true)
        p.netStart(blockers: [])
        var w = TossWorld(); w.xHalf = PlayToss.ballXHalf; w.net = p.net.spec
        for _ in 0..<120 { for r in rs { r.tick() }; p.tick(dt: rs[0].sim.stepDt, world: w, jellies: js()) }
        return (p, rs, w, js)
    }

    func testAStandInTheKeepOutIsMovedOutAndWithoutTheNetNothingIsKeptOut() {
        let (p, _, _, _) = netGame()
        let n = p.net.spec!
        let inside: [SIMD2<Float>] = [SIMD2(0, n.mouthZ - 0.3), SIMD2(0, n.mouthZ + 0.2), SIMD2(n.outerHalf + 0.2, n.centre.y), SIMD2(-n.outerHalf - 0.3, n.mouthZ + 0.3), SIMD2(0.4, n.rearZ - 0.1)]
        for q in inside {
            XCTAssertTrue(p.netKeepOut(q), "\(q) is in the keep-out")
            let m = p.netStand(q)
            XCTAssertFalse(p.netKeepOut(m), "\(q) is moved out: \(m)")
            XCTAssertTrue(m.y >= n.mouthZ + PlayNetTuning.standFront - 1e-3 || abs(m.x - n.centre.x) >= n.outerHalf + PlayNetTuning.keepOutMargin, "in front of the mouth line by 0.6, or beside the net")
        }
        for dz in [Float(0.6), 1.0, 1.7] { let q = SIMD2<Float>(0.3, n.mouthZ + dz); if !p.netKeepOut(q) { XCTAssertEqual(p.netStand(q), q) } }
        let front = SIMD2<Float>(0.3, n.mouthZ + 1.6)
        XCTAssertFalse(p.netKeepOut(front)); XCTAssertEqual(p.netStand(front), front, "a stand in front of the mouth stays")
        p.end()
        XCTAssertFalse(p.netKeepOut(inside[0]), "no net: nothing is kept out")
        XCTAssertEqual(p.netStand(inside[0]), inside[0])
    }

    func testADeadBallInTheZoneIsReturnedWithoutACheerAndABallInFrontOfTheMouthIsPlayed() {
        // (a) a ball that came to rest beside the goal without scoring
        var (p, rs, w, js) = netGame()
        let n = p.net.spec!
        p.ball.pos = SIMD3(n.centre.x + n.outerHalf + 0.15, p.ball.radius, n.centre.y + 0.2); p.ball.vel = .zero          // (beside the net, in the keep-out: no one may stand there to play it)
        p.phase = .loose; p.looseT = 0
        var dead = false, cheered = false, back = false
        for _ in 0..<900 {
            for r in rs { r.tick() }
            p.tick(dt: rs[0].sim.stepDt, world: w, jellies: js())
            if p.net.deadReturns > 0 { dead = true }
            if rs.contains(where: { $0.brain.idleState.kind == .joy || $0.brain.idleState.kind == .bounce }) { cheered = true }
            if p.phase == .inHand { back = true; break }
        }
        XCTAssertTrue(dead, "the dead ball is returned by the net"); XCTAssertEqual(p.net.goals, 0, "it was not a goal")
        XCTAssertFalse(cheered, "no cheer")
        XCTAssertTrue(back, "and it comes back to the hand")
        p.end()
        // (b) a ball in front of the mouth is played as ever
        (p, rs, w, js) = netGame()
        let n2 = p.net.spec!
        p.ball.pos = SIMD3(0.2, p.ball.radius, n2.mouthZ + 1.7); p.ball.vel = .zero
        p.phase = .loose; p.looseT = 0
        var moved = false
        for _ in 0..<900 {
            for r in rs { r.tick() }
            p.tick(dt: rs[0].sim.stepDt, world: w, jellies: js())
            if simd_distance(SIMD2(p.ball.pos.x, p.ball.pos.z), SIMD2(0.2, n2.mouthZ + 1.7)) > 0.5 || p.phase == .inHand { moved = true; break }
        }
        XCTAssertEqual(p.net.deadReturns, 0, "in front of the mouth: not dead")
        XCTAssertTrue(moved, "a Jelmiko plays it (kick / return)")
        p.end()
    }
}
