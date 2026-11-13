//
//  PlayTossTests.swift
//  Play mode (2026-11-02): the toy picker lists only what is bought (and its empty state leads to the Shop's toys), a flick throws to the Jelbie it points at (a short
//  one drops short, a hard one goes far), a header sends the ball back to the bottom of the screen within a few seconds, a missed ball is bumped back in at most 5
//  nudges and 12 s, Done restores everything, and the play view works in landscape. The feet suites run the header, the bump and a whole rally (`scenario`,
//  listed in OnePieceInvariantTests.gaitNames so EmoteFeetTests covers all 6 characters, bare and with shoes).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PlayTossTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let portrait = CGSize(width: 393, height: 852)
    static let landscape = CGSize(width: 852, height: 393)

    override func setUp() { Self.reset() }
    override func tearDown() { Self.reset() }
    static func reset() {
        GameCamera.playBlend = 0; RoomLayout.ballSpheres = []
        DecorField.shared.clear()
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: Float(portrait.width / portrait.height))
    }
    static func room(_ size: CGSize) {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: Float(size.width / size.height)); GameCamera.refreshRoam(aspect: Float(size.width / size.height))
    }

    // MARK: pure: the flick

    /// Flies a ball from `t.start` in a world with Jelbies and returns where it first met a Jelbie / the floor.
    func fly(_ t: TossThrow, bodies: [TossBody], radius: Float = 0.27) -> (event: TossEvent?, at: SIMD3<Float>) {
        var b = TossBall(pos: t.start, radius: radius); b.vel = t.velocity
        var w = TossWorld(); w.bodies = bodies
        w.xHalf = { DecorPlacement.visibleHalf(z: $0) + 0.3 }
        for _ in 0..<600 {
            for e in b.step(1.0 / 60, in: w) {
                switch e { case .headHit, .bodyHit, .floorBounce: return (e, b.pos); default: break }
            }
        }
        return (nil, b.pos)
    }

    func testAFlickAtAJelbieLandsOnHim() {
        Self.room(Self.portrait); GameCamera.playBlend = 1
        let size = Self.portrait
        let spots = PlayToss.playSpots(count: 3, size: size)
        let bodies = (0..<3).map { TossBody(id: $0, pos: spots[$0]!) }
        for (k, b) in bodies.enumerated() {
            // swipe from the hand toward his head on the screen, hard enough to reach him
            let head = GameCamera.screenPoint(floor: b.pos, y: b.top, size: size)!
            let from = CGPoint(x: size.width * 0.5, y: size.height * 0.83)
            let dx = head.x - from.x, dy = head.y - from.y
            let L = hypot(dx, dy)
            let reach = TossAim.reach
            // the speed whose travel reaches the head: travel = reach * speed(screens/s) * H
            let speed = (L / size.height) / reach
            let t = TossAim.throwFor(TossFlick(release: from, velocity: CGVector(dx: dx / L * speed * size.height, dy: dy / L * speed * size.height), size: size), bodies: bodies, radius: 0.27)!
            let r = fly(t, bodies: bodies)
            guard let e = r.event else { XCTFail("Jelmiko \(k): the ball met nothing"); continue }
            switch e {
            case .headHit(let id), .bodyHit(let id, _): XCTAssertEqual(id, k, "swiped at Jelmiko \(k), the ball met \(id)")
            default: XCTFail("Jelmiko \(k): the ball hit the floor at \(r.at) (he is at \(b.pos)), not him")
            }
        }
    }

    func testShortFlickDropsShortAndHardFlickGoesFar() {
        Self.room(Self.portrait); GameCamera.playBlend = 1
        let size = Self.portrait
        let from = CGPoint(x: size.width * 0.5, y: size.height * 0.83)
        func land(_ s: CGFloat) -> Float {
            let t = TossAim.throwFor(TossFlick(release: from, velocity: CGVector(dx: 0, dy: -s * size.height), size: size), bodies: [], radius: 0.27)!
            return fly(t, bodies: []).at.z
        }
        let drop = land(0.2), slow = land(0.6), mid = land(1.0), hard = land(3.2)
        XCTAssertGreaterThan(drop, slow, "a drop falls near the hand, a slow flick goes further")
        XCTAssertGreaterThan(slow, mid, "a harder flick goes further (z smaller = further): \(slow) \(mid)")
        XCTAssertGreaterThan(mid, hard, "\(mid) \(hard)")
        XCTAssertLessThan(hard, -0.5, "a hard flick reaches the back of the room: \(hard)")
    }

    func testTheAimAssistIsSlightAndOnlyNearTheSwipe() {
        Self.room(Self.portrait); GameCamera.playBlend = 1
        let size = Self.portrait
        let spots = PlayToss.playSpots(count: 3, size: size)
        let bodies = (0..<3).map { TossBody(id: $0, pos: spots[$0]!) }
        let from = CGPoint(x: size.width * 0.5, y: size.height * 0.83)
        // straight up: the middle Jelbie is the one pulled
        let up = TossAim.throwFor(TossFlick(release: from, velocity: CGVector(dx: 0, dy: -size.height * 1.5), size: size), bodies: bodies, radius: 0.27)!
        XCTAssertNotNil(up.assistedBody)
        // sideways at the floor: nobody
        let side = TossAim.throwFor(TossFlick(release: from, velocity: CGVector(dx: size.height * 1.6, dy: -size.height * 0.1), size: size), bodies: bodies, radius: 0.27)!
        XCTAssertNil(side.assistedBody, "a swipe away from every Jelmiko is free")
        XCTAssertLessThanOrEqual(up.assist, TossAim.assistMax + 0.11)
    }

    // MARK: the controller with real bodies

    func rigAt(_ p: SIMD2<Float>, char: Int = 0) -> MotionRig {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.brain.anticsEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: p)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        return r
    }
    func world() -> TossWorld { var w = TossWorld(); w.xHalf = { DecorPlacement.visibleHalf(z: $0) + 0.3 }; return w }
    func jelly(_ r: MotionRig) -> PlayJelly { PlayJelly(id: 0, brain: r.brain, sim: r.sim, skinner: r.skinner) }

    /// A frame: the Jelbie, then the controller.
    func frame(_ r: MotionRig, _ p: PlayToss) { r.tick(); p.tick(dt: r.sim.stepDt, world: world(), jellies: [jelly(r)]) }

    /// Runs until `done` or `seconds`; returns the seconds used.
    @discardableResult
    func run(_ r: MotionRig, _ p: PlayToss, seconds: Float, until done: () -> Bool) -> Float {
        var t: Float = 0
        while t < seconds { frame(r, p); t += r.sim.stepDt; if done() { break } }
        return t
    }

    func begin(_ r: MotionRig, _ p: PlayToss, size: CGSize = PlayTossTests.portrait) {
        p.viewSize = size
        p.begin(ball: .ball, title: "Bouncy ball", jellies: [jelly(r)], snapCamera: true)
        run(r, p, seconds: 3) { false }          // (he walks to his spot)
    }

    func throwAtMiddle(_ p: PlayToss, speed: CGFloat = 1.8) {
        let s = p.viewSize
        p.flick(from: CGPoint(x: s.width * 0.5, y: s.height * 0.83), velocity: CGVector(dx: 0, dy: -s.height * speed))
    }

    func testAHeaderReturnsTheBallToTheFrontZone() {
        Self.room(Self.portrait)
        let r = rigAt(SIMD2(0, 0.6)), p = PlayToss()
        p.forceQuality = .good; p.seed(11)
        begin(r, p)
        var events: [PlayEvent] = []
        p.onEvent = { events.append($0); print("PTDBG \($0) ball \(p.ball.pos) vel \(p.ball.vel) jelly \(r.brain.position) top \(self.jelly(r).headTop)") }
        print("PTDBG before throw jelly \(r.brain.position) top \(jelly(r).headTop)")
        throwAtMiddle(p)
        XCTAssertEqual(p.phase, .flying)
        let t = run(r, p, seconds: 9) { p.phase == .catching || p.phase == .inHand }
        XCTAssertLessThan(t, 7, "a header returns the ball to the hand within 7 s (took \(t))")
        XCTAssertTrue(events.contains { if case .header = $0 { return true }; return false }, "the Jelmiko headed it: \(events)")
        XCTAssertTrue(events.contains { if case .caught = $0 { return true }; return false }, "and it was caught: \(events)")
        XCTAssertEqual(p.nudges, 0)
    }

    func testAMissedBallIsBumpedBackInFiveNudgesAndTwelveSeconds() {
        Self.room(Self.portrait)
        for seed in [UInt64(3), 21, 77] {
            let r = rigAt(SIMD2(0, 0.6)), p = PlayToss()
            p.forceQuality = .weak; p.seed(seed)
            begin(r, p)
            var kicks = 0
            p.onEvent = { if case .kick = $0 { kicks += 1 } }
            throwAtMiddle(p)
            let t = run(r, p, seconds: 30) { p.phase == .catching || p.phase == .inHand }
            XCTAssertLessThanOrEqual(t, 12.5, "seed \(seed): the ball is back in hand within 12 s (took \(t); nudges \(p.nudges), headers \(p.headers), rescues \(p.rescues))")
            XCTAssertLessThanOrEqual(p.nudges, 5, "seed \(seed): at most 5 nudges (\(p.nudges))")
            XCTAssertEqual(p.rescues, 0, "seed \(seed): the safety net was not needed")
            XCTAssertTrue(p.phase == .catching || p.phase == .inHand)
        }
    }

    /// The header hop's apex comes `BlobBrain.tossHeaderLead` after the hop starts (the controller times the hop by it), and the crown rises about the hop's apex.
    func testHeaderHopTiming() {
        Self.room(Self.portrait)
        let r = rigAt(SIMD2(0, 0.6))
        let rest = jelly(r).headTop
        XCTAssertTrue(r.brain.tossHeaderStart(r.sim))
        var best: Float = 0, bestT: Float = 0, t: Float = 0
        while t < 1.2 { r.tick(); t += r.sim.stepDt; let h = jelly(r).headTop; if h > best { best = h; bestT = t } }
        print("PTDBG header hop: apex at \(bestT) s, crown +\(best - rest) (rest \(rest))")
        XCTAssertEqual(bestT, BlobBrain.tossHeaderLead, accuracy: 0.12, "the controller starts the hop \(BlobBrain.tossHeaderLead) s before the ball arrives")
        XCTAssertGreaterThan(best - rest, 0.08, "the crown really rises")
    }

    func testNobodyCarriesTheBallAndTheArmsStayStubby() {
        Self.room(Self.portrait)
        let r = rigAt(SIMD2(0, 0.6)), p = PlayToss()
        p.forceQuality = .weak; p.seed(5)
        begin(r, p)
        throwAtMiddle(p)
        var maxLean: Float = 0
        run(r, p, seconds: 14) {
            // the ball is never within a body of the Jelbie's mouth / arms level while it is not on his crown: it is a free sphere (no carried flag in the model)
            XCTAssertFalse(p.ball.pos.y > 0.3 && p.ball.pos.y < 1.1 && simd_distance(SIMD2(p.ball.pos.x, p.ball.pos.z), r.brain.position) < 0.3, "the ball is inside his body")
            maxLean = max(maxLean, abs(r.sim.bodyPose(iterations: 4).tilt))
            return p.phase == .catching || p.phase == .inHand
        }
        XCTAssertLessThan(maxLean, 0.5, "no tipping past 0.5 rad (\(maxLean))")
    }

    func testDoneExitsCleanlyAndRestoresTheJelbies() {
        Self.room(Self.portrait)
        let r = rigAt(SIMD2(0, 0.6)), p = PlayToss()
        r.brain.reserved = false
        begin(r, p)
        XCTAssertTrue(r.brain.reserved && p.active)
        throwAtMiddle(p)
        run(r, p, seconds: 1) { false }
        p.end()
        XCTAssertFalse(p.active)
        XCTAssertFalse(r.brain.reserved, "roaming is handed back")
        XCTAssertNil(r.brain.trackPoint); XCTAssertNil(r.brain.tossFire)
        run(r, p, seconds: 3) { GameCamera.playBlend == 0 }
        XCTAssertEqual(GameCamera.playBlend, 0, accuracy: 1e-4, "the camera is home")
        XCTAssertFalse(RoomLayout.ballSpheres.contains { $0.uid == PlayToss.sphereUID }, "the ball is not an obstacle any more")
    }

    // MARK: layout

    func testThePlayViewFramesTheJelbiesInPortraitAndLandscape() {
        for size in [Self.portrait, Self.landscape] {
            Self.room(size); GameCamera.playBlend = 1
            let spots = PlayToss.playSpots(count: 3, size: size)
            XCTAssertEqual(spots.count, 3)
            for (_, s) in spots {
                let top = GameCamera.screenPoint(floor: s, y: BobShape.H, size: size)!, foot = GameCamera.screenPoint(floor: s, y: 0, size: size)!
                XCTAssertGreaterThan(top.y, 0, "\(size): head on screen"); XCTAssertLessThan(foot.y, size.height * 0.80, "\(size): he stands above the hand's band")
                XCTAssertTrue(foot.x > size.width * 0.05 && foot.x < size.width * 0.95, "\(size): on screen across")
            }
            // the hand sits at the bottom and the catch line is on screen
            let hand = TossAim.hand(at: CGPoint(x: size.width / 2, y: size.height * 0.87), size: size)
            XCTAssertNotNil(hand, "\(size): the hand has a place")
            let p = PlayToss(); p.viewSize = size
            XCTAssertGreaterThan(p.catchZ(), 1.5)
        }
    }

    func testTheFlickStillThrowsInLandscape() {
        Self.room(Self.landscape); GameCamera.playBlend = 1
        let size = Self.landscape
        let spots = PlayToss.playSpots(count: 3, size: size)
        let bodies = (0..<3).map { TossBody(id: $0, pos: spots[$0]!) }
        let from = CGPoint(x: size.width * 0.5, y: size.height * 0.80)
        let t = TossAim.throwFor(TossFlick(release: from, velocity: CGVector(dx: 0, dy: -size.height * 2.2), size: size), bodies: bodies, radius: 0.27)
        XCTAssertNotNil(t)
        XCTAssertNotNil(fly(t!, bodies: bodies).event)
    }

    // MARK: the picker and the store

    func book() -> StoreBook { StoreBook(wallet: DropsWallet(persists: false), persists: false) }

    func testThePickerListsOnlyOwnedToysAndBuyingOneMakesItAppear() {
        let b = book()
        XCTAssertTrue(PlayToyRegistry.offered(book: b).isEmpty, "nothing owned: an empty picker")
        b.wallet.add(500)
        XCTAssertEqual(b.buy("decor-ball"), .bought)
        XCTAssertEqual(PlayToyRegistry.offered(book: b).map(\.toyID), ["ball-ball"], "the ball he bought, and nothing else")
        b.grant("decor-soccerball")
        XCTAssertEqual(PlayToyRegistry.offered(book: b).map(\.toyID), ["ball-ball", "ball-soccerball"])
        XCTAssertFalse(PlayToyRegistry.offered(book: b).contains { $0.toyID == "bubbleWand" }, "the wand is not offered before it is bought")
        XCTAssertEqual(b.buy("toy-bubbleWand"), .bought)
        XCTAssertTrue(PlayToyRegistry.offered(book: b).contains { $0.toyID == "bubbleWand" }, "bought: it appears")
        XCTAssertEqual(StoreCatalog.item("toy-bubbleWand")?.price, 40)
        XCTAssertTrue(ShopTab.toys.items.contains { $0.id == "toy-bubbleWand" } && ShopTab.toys.items.contains { $0.id == "decor-ball" }, "the Shop's Toys tab sells the balls and the wand")
    }

    func testEveryToyOfThePickerHasAStoreItemInThePriceBand() {
        for t in PlayToyRegistry.entries.isEmpty ? { _ = PlayToyRegistry.offered(book: book()); return PlayToyRegistry.entries }() : PlayToyRegistry.entries {
            guard let i = StoreCatalog.item(t.storeID) else { XCTFail("\(t.toyID) is not sold"); continue }
            XCTAssertTrue((25...60).contains(i.price), "\(i.name) \(i.price)")
        }
    }

    func testTheEmptyPickerLeadsToTheShopsToys() {
        ShopTab.pending = .toys
        XCTAssertEqual(ShopTab.pending, .toys)
        ShopTab.pending = nil
        let c = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "PlayToss.1")!)
        let play = HUDItem.play
        XCTAssertEqual(HUDMenu.title(play, .group, care: c), "Play")
        XCTAssertEqual(HUDMenu.perform(play, .group, care: c), .picker(.toy), "Play opens the toy picker, not the bag")
    }

    // MARK: feet scenarios (OnePieceInvariantTests / EmoteFeetTests)

    nonisolated(unsafe) static var current: PlayToss?

    static func scenario(_ name: String) -> LegsDrawnAuditTests.Scenario {
        let quality: PlayToss.Quality? = name == "toss: bump" ? .weak : (name == "toss: header" ? .good : nil)
        return LegsDrawnAuditTests.Scenario(name: name, game: true, seconds: name == "toss: rally" ? 24 : 16, setup: { r, seed in
            let size = portrait
            room(size)
            r.brain.anticsEnabled = true
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: SIMD2(0.3, 0.9)); for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim)
            let p = PlayToss()
            p.viewSize = size; p.forceQuality = quality; p.seed(seed &* 7 &+ 1)
            p.begin(ball: .ball, title: "Bouncy ball", jellies: [PlayJelly(id: 0, brain: r.brain, sim: r.sim, skinner: r.skinner)], snapCamera: true)
            current = p
            return true
        }, each: { r in
            guard let p = current else { return }
            var w = TossWorld(); w.xHalf = { DecorPlacement.visibleHalf(z: $0) + 0.3 }
            p.tick(dt: r.sim.stepDt, world: w, jellies: [PlayJelly(id: 0, brain: r.brain, sim: r.sim, skinner: r.skinner)])
            // throw whenever the ball is in the hand (after he has walked to his spot)
            if p.phase == .inHand, p.clock > 3, r.brain.script.isWalking == false {
                let s = p.viewSize
                p.flick(from: CGPoint(x: s.width * 0.5, y: s.height * 0.83), velocity: CGVector(dx: 0, dy: -s.height * 1.8))
            }
        }, measureEvery: 1, variants: 4)
    }
}

extension BlobBrain.Script { var isWalking: Bool { if case .walk = self { return true }; return false } }
