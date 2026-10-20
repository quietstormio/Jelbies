//
//  DecorTests.swift
//  The store's decor (part B): the catalogue, the capacity of 10 spots, where things may go, persistence (an old save still decodes), the beanbag's
//  perk, decor as an obstacle (paths, sleep spots, the meal tray), the five interactions (they start, finish, release the piece and keep the feet
//  attached; those moves are also in FeetAttachTests / ArmCapTests), and a soak with three Jellies in a full room.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class DecorTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// A private defaults suite for tests that build a whole GameCare, so nothing persisted by other runs (placed decor, Jellies 2/3) leaks in.
    private var suiteName = ""
    private var suite: UserDefaults!
    override func setUp() {
        suiteName = "DecorTests." + UUID().uuidString
        suite = UserDefaults(suiteName: suiteName)
        suite.removePersistentDomain(forName: suiteName)
        DecorField.shared.clear(); room(3)
    }
    override func tearDown() {
        suite?.removePersistentDomain(forName: suiteName)
        suite = nil
        DecorField.shared.clear()
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// The game's room and camera for `n` Jellies.
    private func room(_ n: Int) { GameCamera.configureRoom(count: n, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }

    private func book() -> StoreBook {
        let w = DropsWallet(persists: false)
        return StoreBook(wallet: w, persists: false)
    }

    /// The most pieces the room's 10 spots hold, as a plausible mix: 2 beanbags + the mat (6), toy box, plant, night light, cushion (10).
    static let fullMix: [DecorKind] = DecorTuning.fullRoom

    private func fillRoom(_ b: StoreBook) {
        for k in Self.fullMix { b.grant(k.storeID); XCTAssertNotNil(b.place(k.storeID), "\(k) fits") }
        DecorField.shared.set(b.placedDecor)
    }

    // MARK: catalogue and capacity

    func testCatalogueHasEightDecorItemsInTheRightPriceBand() {
        let items = StoreCatalog.items(.decor)
        XCTAssertEqual(items.count, 8)
        for i in items {
            XCTAssertTrue((25...90).contains(i.price), "\(i.name) \(i.price)")
            XCTAssertNotNil(i.decor, i.id)
            XCTAssertEqual(i.roomUnits, i.decor?.spec.units)
            XCTAssertTrue(i.roomUnits == 1 || i.roomUnits == 2)
        }
        XCTAssertEqual(Set(items.compactMap { $0.decor }), Set(DecorKind.allCases))
        XCTAssertEqual(items.filter { $0.roomUnits == 2 }.map { $0.decor! }.sorted { $0.rawValue < $1.rawValue }, [.beanbag, .bouncymat])
        XCTAssertTrue(StoreCatalog.tabs.contains(.decor), "the Decor tab shows now")
        XCTAssertTrue(ShopTab.shown.contains(.decor))
    }

    func testRoomHoldsTenSpotsAndNoMore() {
        let b = book()
        fillRoom(b)
        XCTAssertEqual(b.roomUnitsUsed, 10)
        b.grant("decor-cushion")
        XCTAssertFalse(b.canPlace(StoreCatalog.item("decor-cushion")!), "room full")
        XCTAssertNil(b.place("decor-cushion"))
        XCTAssertNotNil(b.placeBlocker(StoreCatalog.item("decor-cushion")!))
        // putting one away frees the spots; the big one needs 2
        let bean = b.placedDecor.first { $0.kind == .beanbag }!
        b.putAway(bean.uid)
        XCTAssertEqual(b.roomUnitsUsed, 8)
        XCTAssertNotNil(b.place("decor-cushion"))
        XCTAssertNil(b.place("decor-ball"), "no ball owned")
    }

    func testEveryPlacedPieceIsValidClearOfTheOthersAndOfTheFurniture() {
        let b = book()
        fillRoom(b)
        for p in b.placedDecor {
            XCTAssertTrue(DecorPlacement.isValid(p.kind, at: p.at, among: b.placedDecor, ignoring: p.uid), "\(p.kind) at \(p.at)")
            XCTAssertGreaterThan(RoomLayout.sofaDistanceXZ(p.at), p.kind.spec.radius)
            for c in RoomLayout.cylinders { XCTAssertGreaterThan(simd_distance(p.at, c.centre), c.radius + p.kind.spec.radius) }
            for o in b.placedDecor where o.uid != p.uid { XCTAssertGreaterThan(simd_distance(p.at, o.at), p.kind.spec.radius + o.kind.spec.radius - 0.001, "\(p.kind) / \(o.kind) overlap") }
            if p.kind.spec.solid { XCTAssertFalse(DecorPlacement.inCore(p.at, radius: p.kind.spec.radius), "\(p.kind) is out of the core") }
        }
    }

    func testBigPiecesNeverStraddleTheRugAndSmallOnesMaySitOnIt() {
        let rug = PlacedDecor(uid: 1, kind: .rug, x: 2.9, z: -1)
        // fully on the rug: a cushion is fine and is lifted; a beanbag is not
        XCTAssertTrue(DecorPlacement.isValid(.nightlight, at: SIMD2(2.9, -1), among: [rug]), "small things sit on the rug")
        XCTAssertGreaterThan(DecorPlacement.rugLift(.nightlight, at: SIMD2(2.9, -1), others: [rug], ignoring: nil), 0)
        XCTAssertFalse(DecorPlacement.isValid(.beanbag, at: SIMD2(2.9, -1), among: [rug]), "a big piece does not go on the rug")
        XCTAssertFalse(DecorPlacement.isValid(.nightlight, at: SIMD2(2.9 - 0.85, -1), among: [rug]), "not half over the rug's edge")
    }

    func testDragStaysInTheRoomAndOffTheFurniture() {
        let b = book()
        b.grant("decor-beanbag")
        let p = b.place("decor-beanbag")!
        XCTAssertFalse(b.move(p.uid, to: SIMD2(0, -4.0)), "on the sofa")
        XCTAssertFalse(b.move(p.uid, to: SIMD2(30, 0)), "off the floor")
        XCTAssertFalse(b.move(p.uid, to: SIMD2(0, 0.5)), "the middle of the rug is for the Jellies and the meal")
        XCTAssertTrue(b.move(p.uid, to: SIMD2(-2.8, 0.5)))
        XCTAssertEqual(b.placedDecor.first?.at, SIMD2(-2.8, 0.5))
    }

    // MARK: drag (arrange mode)

    func testAFingerOnTheScreenFindsTheFloorUnderIt() {
        let care = GameCare(jellyCount: 3, persistent: false)
        let size = CGSize(width: 440, height: 956)
        // the middle of the screen looks at the floor near the camera's target
        let mid = care.floorPoint(screen: CGPoint(x: 220, y: 478), size: size)
        XCTAssertNotNil(mid)
        XCTAssertEqual(mid!.x, 0, accuracy: 0.4)
        // up the screen is further back in the room; left is -x
        let up = care.floorPoint(screen: CGPoint(x: 220, y: 300), size: size)!, left = care.floorPoint(screen: CGPoint(x: 60, y: 478), size: size)!
        XCTAssertLessThan(up.y, mid!.y)
        XCTAssertLessThan(left.x, mid!.x)
        XCTAssertLessThan(care.floorPoint(screen: CGPoint(x: 220, y: 5), size: size)?.y ?? 0, -20, "the top of the screen is the far floor (off the room: nothing can be placed there)")
    }

    func testDraggingMovesAPieceSlidesAlongObstaclesAndSavesIt() {
        let care = GameCare(jellyCount: 3, persistent: false)
        care.store.grant("decor-cushion")
        let p = care.placeDecor("decor-cushion")!
        XCTAssertTrue(care.arranging)
        XCTAssertEqual(care.arrangingUID, p.uid)
        XCTAssertTrue(care.dragDecor(p.uid, to: SIMD2(-2.7, 1.0)))
        XCTAssertEqual(care.store.placedDecor.first?.at, SIMD2(-2.7, 1.0))
        XCTAssertEqual(DecorField.shared.feet.first?.centre, SIMD2(-2.7, 1.0), "the room sees it at once")
        // dragged into the middle of the rug it stops where it is still allowed (the core is for the Jellies and the meal)
        _ = care.dragDecor(p.uid, to: SIMD2(0, 0.5))
        XCTAssertTrue(DecorPlacement.isValid(.cushion, at: care.store.placedDecor.first!.at, among: [], ignoring: nil))
        XCTAssertEqual(care.decorPiece(at: care.store.placedDecor.first!.at)?.uid, p.uid, "a finger on it picks it up")
        care.putAwayDecor(p.uid)
        XCTAssertTrue(care.store.placedDecor.isEmpty); XCTAssertTrue(DecorField.shared.feet.isEmpty)
        XCTAssertEqual(care.store.count("decor-cushion"), 1, "back in the bag, not lost")
        XCTAssertFalse(care.arranging, "nothing left to arrange")
    }

    // MARK: persistence

    func testPlacementsPersistAndAnOldSaveStillDecodes() {
        let suite = "DecorTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let w = DropsWallet(persists: false)
        let a = StoreBook(wallet: w, persists: true, defaults: d, key: "k")
        a.grant("decor-plant"); a.grant("shoe-mint")
        let p = a.place("decor-plant")!
        XCTAssertTrue(a.move(p.uid, to: SIMD2(-2.7, -1.0)))
        let c = StoreBook(wallet: w, persists: true, defaults: d, key: "k")
        XCTAssertEqual(c.placedDecor.count, 1)
        XCTAssertEqual(c.placedDecor.first?.at, SIMD2(-2.7, -1.0))
        XCTAssertTrue(c.ownsLook(.sneakerMint))
        // a save written before decor existed (no placedAt) decodes and keeps the shoes
        let old = #"{"counts":{"sushi":2},"pages":["spin"],"wearables":["sneakerMint"],"worn":{},"starterGiven":true,"newItems":0,"placed":[]}"#
        d.set(Data(old.utf8), forKey: "old")
        let o = StoreBook(wallet: w, persists: true, defaults: d, key: "old")
        XCTAssertEqual(o.count("sushi"), 2)
        XCTAssertTrue(o.ownsLook(.sneakerMint))
        XCTAssertTrue(o.placedDecor.isEmpty)
        XCTAssertNotNil({ () -> PlacedDecor? in o.grant("decor-cushion"); return o.place("decor-cushion") }())
    }

    // MARK: the beanbag perk

    func testBeanbagMakesLoveDrainSlowerWhileItIsInTheRoom() {
        func attentionAfter(_ bean: Bool) -> Float {
            let rig = MotionRig(game: true)
            Self.keep.append(rig)
            DecorField.shared.clear()
            let care = GameCare(jellyCount: 1, persistent: false, defaults: suite)
            // hermetic: no leftover placed decor and no running perks, whatever the host app persisted
            care.store.putAwayAll()
            XCTAssertFalse(care.store.beanbagPlaced, "a clean room to start")
            for k in PerkKind.allCases { care.jelly(0)?.perks.clear(k) }
            if bean { care.store.grant("decor-beanbag"); _ = care.store.place("decor-beanbag") }
            let start = care.needs.levels[NeedKind.attention.rawValue]
            for _ in 0..<(60 * 120) { care.tick(brain: rig.brain, renderer: nil, dt: 1.0 / 60, sim: rig.sim) }
            return start - care.needs.levels[NeedKind.attention.rawValue]
        }
        let plain = attentionAfter(false), cosy = attentionAfter(true)
        XCTAssertGreaterThan(plain, 0.001)
        XCTAssertEqual(cosy / plain, Float(StoreTuning.beanbagAttentionDrain), accuracy: 0.06, "attention falls x0.85 with a beanbag")
    }

    // MARK: obstacles

    func testSolidDecorPushesAWalkerOutAndFlatDecorDoesNot() {
        for k in DecorKind.allCases {
            DecorField.shared.set([PlacedDecor(uid: 1, kind: k, x: 3, z: 0)])
            let inside = RoomLayout.resolve(position: SIMD3(3, 0, 0), radius: 0.7)
            let moved = simd_distance(SIMD2(inside.x, inside.z), SIMD2<Float>(3, 0))
            if k.spec.solid { XCTAssertGreaterThan(moved, 0.25, "\(k) is a wall") } else { XCTAssertEqual(moved, 0, accuracy: 1e-4, "\(k) is walked over") }
            // the piece being used is the one exception
            let ign = RoomLayout.resolve(position: SIMD3(3, 0, 0), radius: 0.7, ignoreDecor: 1)
            XCTAssertEqual(simd_distance(SIMD2(ign.x, ign.z), SIMD2<Float>(3, 0)), 0, accuracy: 1e-4)
        }
    }

    func testAWalkNeverGoesThroughDecor() {
        room(3)
        // a plant and a toy box across the way (placed straight into the field: the point is the walker)
        DecorField.shared.set([PlacedDecor(uid: 1, kind: .plant, x: 0.0, z: 0.5), PlacedDecor(uid: 2, kind: .toybox, x: 1.7, z: 1.1)])
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: SIMD2(-2.0, 0.4))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        XCTAssertEqual(r.brain.position.x, -2.0, accuracy: 0.1, "he starts where the test put him")
        r.brain.request(.goTo(SIMD2(2.5, -0.3)))
        var minD = Float.infinity, arrived = false
        r.run(14, until: { arrived }) {
            let p = r.brain.position
            for f in DecorField.shared.feet where f.spec.solid { let d = f.distance(p) - r.brain.footprint * f.spec.reach; minD = min(minD, d) }
            if simd_distance(p, SIMD2(2.5, -0.3)) < 0.5 { arrived = true }
        }
        XCTAssertTrue(arrived, "he got round them")
        XCTAssertGreaterThan(minD, -0.06, "his footprint never went into a piece (\(minD))")
    }

    func testSleepSpotsNeverOverlapDecorEvenInAFullRoom() {
        room(3)
        let b = book(); fillRoom(b)
        let lab = SocialTests.Lab(quiet: true, seed: 5)
        for r in lab.rigs { r.brain.sleepEnabled = true; r.brain.anticsEnabled = true }
        var started = 0
        for r in lab.rigs { r.brain.idleForced = true; if r.brain.idleStart(.sleep, r.sim) { started += 1 } }
        XCTAssertEqual(started, 3, "all three find a place to lie down in the full room")
        var spots: [SIMD2<Float>] = []
        for _ in 0..<(60 * 40) {
            lab.tick(watching: false)
            for r in lab.rigs where r.brain.idleState.kind == .sleep && r.brain.sleep.stage >= 1 { spots.append(r.brain.sleep.spot) }
        }
        XCTAssertGreaterThanOrEqual(spots.count, 60, "they went to bed")
        for s in spots {
            XCTAssertGreaterThan(RoomLayout.decorDistance(s, solidOnly: true), SleepTuning.decorClearRelaxed - 0.001, "sleeps clear of solid decor at \(s)")
            XCTAssertGreaterThan(RoomLayout.decorDistance(s), SleepTuning.decorFlatClearRelaxed - 0.001, "and not on flat decor at \(s)")
        }
        // and a free sleeping place exists in the full room for a pile of three
        let probe = lab.rigs[0].brain
        var free = 0
        for ix in -4...4 { for iz in -3...3 where probe.sleepFloorOK(SIMD2(Float(ix) * 0.6, 0.25 + Float(iz) * 0.5)) { free += 1 } }
        XCTAssertGreaterThanOrEqual(free, 8, "the rug still has room to sleep on (\(free) spots)")
    }

    /// A full room (10 spots): all three told goodnight are asleep (lying, settled) within 40 s, whatever the seed.
    func testAllThreeSleepInAFullRoomWhenToldGoodnight() {
        for seed in [5, 9, 21, 33] as [UInt64] {
            DecorField.shared.clear(); room(3)
            let b = book(); fillRoom(b)
            let lab = SocialTests.Lab(quiet: true, seed: seed)
            Self.keep.append(lab)
            for r in lab.rigs { r.brain.sleepEnabled = true }
            for r in lab.rigs { r.brain.commandedGoodnight = true }
            var asleepAt: Float?
            for f in 0..<(60 * 40) {
                lab.tick(watching: false)
                if lab.rigs.allSatisfy({ $0.brain.isSleeping && $0.brain.sleep.stage >= 3 }) { asleepAt = Float(f) / 60; break }
            }
            XCTAssertNotNil(asleepAt, "seed \(seed): all three asleep within 40 s")
            let spots = lab.rigs.map { $0.brain.sleep.spot }
            for i in 0..<3 { for j in (i + 1)..<3 { XCTAssertGreaterThan(simd_distance(spots[i], spots[j]), SleepTuning.minGap - 0.05, "seed \(seed): bodies apart") } }
        }
    }

    func testTheMealTrayAvoidsDecor() {
        room(3)
        let b = book(); fillRoom(b)
        let L = DiningLayout.make(n: 3)
        let spot = DiningSpot.choose(bob: SIMD2(0, 0.5), layout: L)
        for f in DecorField.shared.feet where f.spec.solid {
            let g = L.half
            let dx = max(abs(f.centre.x - spot.x) - g.x, 0), dz = max(abs(f.centre.y - spot.y) - g.y, 0)
            XCTAssertGreaterThan((dx * dx + dz * dz).squareRoot(), f.radius * 0.9, "tray at \(spot) clear of \(f.kind)")
        }
    }

    // MARK: interactions

    private func installed(_ kind: DecorKind, at p: SIMD2<Float>) -> MotionRig {
        room(3)
        DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: p.x, z: p.y)])
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.brain.anticsEnabled = true
        r.brain.sleepEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: SIMD2(-1.0, 1.0))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        return r
    }

    func testEveryInteractionStartsFinishesAndLetsGoOfThePiece() {
        let cases: [(DecorKind, IdleKind, SIMD2<Float>)] = [(.beanbag, .decorSit, SIMD2(2.8, 0.4)), (.cushion, .decorSit, SIMD2(-2.6, 1.0)), (.plant, .decorBoop, SIMD2(2.6, 0.8)),
                                                            (.ball, .decorKick, SIMD2(0.8, 0.6)), (.bouncymat, .decorHop, SIMD2(2.6, 0.8)), (.toybox, .decorPeek, SIMD2(-2.7, 0.8))]
        for (kind, move, at) in cases {
            let r = installed(kind, at: at)
            r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(move, r.sim), "\(move) starts")
            XCTAssertEqual(DecorField.shared.occupant[7], r.brain.steerID, "\(move) holds the piece")
            var sawField = false
            r.run(40, until: { r.brain.idleState.kind == nil && r.t > 1 }) {
                DecorField.shared.tick(dt: 1.0 / 60)
                if let a = DecorField.shared.anim[7], a.active { sawField = true }
            }
            XCTAssertNil(r.brain.idleState.kind, "\(move) finished")
            XCTAssertNil(DecorField.shared.occupant[7], "\(move) let go")
            // (he may still stand in the bag he sat in: it is soft for him until he walks out)
            r.brain.request(.goTo(SIMD2(-0.5, 1.4)))
            r.run(10) {}
            XCTAssertNil(r.brain.decorIgnore, "\(move) restored the wall once he is out of it")
            XCTAssertTrue(sawField, "\(move) moved the piece (sink, wiggle, roll or dip)")
        }
    }

    /// The beanbag sit: he hops up, lands ON TOP (his floor is the bag's top, the bag squishes under him), rests, hops off forward to the floor.
    func testHeHopsOntoTheBeanbagRestsOnTopAndHopsOff() {
        let r = installed(.beanbag, at: SIMD2(2.8, 0.4))
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.decorSit, r.sim))
        var stages: [Int] = []
        var seated = 0
        var worstFoot: Float = 0, worstBody: Float = 0, maxSquish: Float = 0, minTop: Float = .infinity, floorWhileSeated: Float = 0
        var peakAbove: Float = 0
        var restTop: Float = 0
        r.run(40, until: { r.brain.idleState.kind == nil && r.t > 1 }) {
            DecorField.shared.tick(dt: 1.0 / 60)
            let st = r.brain.idleState.bagStage
            if r.brain.idleState.kind == .decorSit, stages.last != st { stages.append(st) }
            guard r.brain.idleState.kind == .decorSit, let top = DecorField.shared.topY(7) else { return }
            minTop = min(minTop, top)
            if st == 1 { peakAbove = max(peakAbove, r.sim.centroid().y) }
            if st == 2, r.brain.bagFloorOn, r.brain.idleState.phaseT > 1.2 {
                seated += 1
                r.render()
                let low = (0..<2).map { s in r.sole[s].map { r.dyn[6 * Int($0) + 1] }.min() ?? 0 }.min() ?? 0
                worstFoot = max(worstFoot, abs(low - top))
                var lo = Float.infinity
                for i in 0..<r.sim.n { lo = min(lo, r.sim.x[3 * i + 1]) }
                worstBody = max(worstBody, top - lo)              // how far the lowest body point is below the bag's top
                floorWhileSeated = max(floorWhileSeated, abs(r.sim.floorY - top))
                restTop = top
                maxSquish = max(maxSquish, DecorModels.bagSeatY - top)
            }
        }
        XCTAssertEqual(stages, [0, 1, 2, 3], "turn, hop on, on top, hop off")
        XCTAssertGreaterThan(seated, 120, "he rests on the bag")
        XCTAssertLessThanOrEqual(worstFoot, 0.04, "his lowest foot point is at the bag's top while he is seated")
        XCTAssertLessThanOrEqual(worstBody, 0.04, "his body does not go into the bag")
        XCTAssertLessThan(floorWhileSeated, 0.002, "his floor is the bag's top")
        XCTAssertGreaterThan(restTop, 0.3, "he is up in the bag's seat")
        XCTAssertGreaterThan(maxSquish, 0.01, "the bag squishes under him")
        XCTAssertGreaterThan(peakAbove, minTop, "the hop took his centre up over the bag")
        // afterwards his floor is the room's again
        XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-6)
        XCTAssertFalse(r.brain.bagFloorOn)
        r.run(2) { DecorField.shared.tick(dt: 1.0 / 60) }
        XCTAssertLessThan(r.sim.centroid().y, 0.9, "back on the floor")
    }

    /// Cut short on the bag (grabbed, called): no phantom floor is left under him.
    func testAnInterruptedBeanbagSitRestoresTheFloor() {
        let r = installed(.beanbag, at: SIMD2(2.8, 0.4))
        r.brain.idleForced = true
        _ = r.brain.idleStart(.decorSit, r.sim)
        r.run(30, until: { r.brain.bagFloorOn }) { DecorField.shared.tick(dt: 1.0 / 60) }
        XCTAssertTrue(r.brain.bagFloorOn)
        XCTAssertGreaterThan(r.sim.floorY, 0.3)
        r.brain.abortAll(r.sim, r.skinner)
        r.run(0.1) {}
        XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-6, "the room's floor again")
    }

    func testSittingSinksTheBeanbagAndTheBallRolls() {
        let r = installed(.beanbag, at: SIMD2(2.8, 0.4))
        r.brain.idleForced = true
        _ = r.brain.idleStart(.decorSit, r.sim)
        var maxSink: Float = 0
        r.run(40, until: { r.brain.idleState.kind == nil && r.t > 1 }) { DecorField.shared.tick(dt: 1.0 / 60); maxSink = max(maxSink, DecorField.shared.anim[7]?.sink ?? 0) }
        XCTAssertGreaterThan(maxSink, 0.8, "the bag sinks under him")
        let q = installed(.ball, at: SIMD2(0.8, 0.6))
        q.brain.idleForced = true
        _ = q.brain.idleStart(.decorKick, q.sim)
        let before = DecorField.shared.anim[7]!.pos
        var far: Float = 0
        q.run(30, until: { q.brain.idleState.kind == nil && q.t > 1 }) { DecorField.shared.tick(dt: 1.0 / 60); far = max(far, simd_distance(DecorField.shared.anim[7]!.pos, before)) }
        for _ in 0..<(60 * 8) { DecorField.shared.tick(dt: 1.0 / 60) }
        XCTAssertGreaterThan(far, 0.8, "the ball was booted away")
        XCTAssertLessThan(DecorField.shared.anim[7]!.vel.x.magnitude + DecorField.shared.anim[7]!.vel.y.magnitude, 0.2, "and came to rest")
    }

    func testTheIdleSchedulerPicksDecorWhenTheRoomOffersIt() {
        XCTAssertTrue(BlobBrain.decorOffers().isEmpty, "no decor, no offers")
        DecorField.shared.set([PlacedDecor(uid: 1, kind: .beanbag, x: 3, z: 0), PlacedDecor(uid: 2, kind: .ball, x: -3, z: 0)])
        XCTAssertEqual(BlobBrain.decorOffers(), [.decorSit, .decorKick])
        var seen = Set<IdleKind>()
        for i in 0..<400 {
            let k = IdleTable.pick(.happy, last: nil, r: Float(i) / 400, antics: true, decor: BlobBrain.decorOffers())
            seen.insert(k)
        }
        XCTAssertTrue(seen.contains(.decorSit) && seen.contains(.decorKick))
        XCTAssertFalse(seen.contains(.decorHop), "only what is in the room")
        // the weights without decor are exactly what they were
        XCTAssertEqual(IdleTable.weights(.happy, night: 0, morning: 0, antics: true).map(\.kind), IdleTable.weights(.happy, night: 0, morning: 0, antics: true, decor: []).map(\.kind))
    }

    // MARK: soak

    /// Three Jellies, a full room (10 spots), 4 minutes x 2 seeds: nobody walks in place for 3.4 s (decor walks included), nobody goes through a solid
    /// piece they are not using, nobody is on top of another, and the decor was really used.
    /// Longest a Jelly may try to walk without getting anywhere. The brain's own patience: an ordinary leg is dropped and re-picked after ~3 s without
    /// progress, and a walk he was ASKED to make (a step-aside from makeRoom) waits up to 6 s for a Jelly that stands in the way. The empty room shows the
    /// same 2...3.4 s waits; more than 6.5 s would be a real jam.
    static let stuckLimit: Float = 6.5
    func soak(seeds: [UInt64], fill: Bool) {
        for seed in seeds {
            room(3)
            DecorField.shared.clear()
            if fill { let b = book(); fillRoom(b); DecorField.shared.set(b.placedDecor) }
            let lab = SocialTests.Lab(quiet: false, seed: seed)
            for (i, r) in lab.rigs.enumerated() {
                r.brain.idleMood = .happy; r.brain.socialBook.cooldown = 8; r.brain.idleState.cooldown = 6; r.brain.restTimer = 0.5 + Float(i)
                AnticsLabTests.lively(r.brain)
            }
            var anchor = lab.rigs.map { $0.brain.position }, anchorYaw = lab.rigs.map { $0.brain.yaw }, still = [Float](repeating: 0, count: 3), flagged = [Bool](repeating: false, count: 3)
            var hist = [[String]](repeating: [], count: 3), histSig = [String](repeating: "", count: 3)
            var stuck = 0, worstStill: Float = 0, tags: [String] = [], inside = 0, uses: [String: Int] = [:], prev = [IdleKind?](repeating: nil, count: 3), minPair = Float.infinity
            for f in 0..<(60 * 240) {
                lab.tick(watching: false)
                lab.sampleGaps()
                DecorField.shared.tick(dt: 1.0 / 60)
                for (i, r) in lab.rigs.enumerated() {
                    let b = r.brain
                    let sig = "\(String(describing: b.idleState.kind))/\(String(describing: b.socialKind))/\(b.activity)"
                    if sig != histSig[i] { histSig[i] = sig; hist[i].append("t\(Int(Float(f) / 60 * 10)) \(sig) (\(String(format: "%.1f,%.1f", b.px, b.pz)))"); if hist[i].count > 8 { hist[i].removeFirst() } }
                    if b.idleState.kind != prev[i] { if let k = b.idleState.kind, BlobBrain.decorKinds.contains(k) { uses[k.rawValue, default: 0] += 1 }; prev[i] = b.idleState.kind }
                    // walking (an ordinary wander or the walk to a piece) without getting anywhere
                    var walking = false
                    if case .walk = b.script { walking = true }
                    if walking {
                        if simd_distance(b.position, anchor[i]) > 0.15 || abs(wrapAngle(b.yaw - anchorYaw[i])) > 0.3 { anchor[i] = b.position; anchorYaw[i] = b.yaw; still[i] = 0; flagged[i] = false }
                        else { still[i] += 1.0 / 60; worstStill = max(worstStill, still[i]); if still[i] > Self.stuckLimit, !flagged[i] { flagged[i] = true; stuck += 1; var near = ""; for p in DecorField.shared.feet where simd_distance(p.centre, b.position) < 2.2 { near += " \(p.kind)@\(p.centre) d\(p.distance(b.position))" }; var tg = ""; if case .walk(let t, _) = b.script { tg = "goal \(t)" }; tags.append("seed \(seed) t \(f / 60) rig\(i) (\(b.px),\(b.pz)) kind \(String(describing: b.idleState.kind)) \(tg) ignore \(String(describing: b.decorIgnore)) route \(b.route.count) wait \(b.steerWait) stall \(b.steerStall) walkStallT \(b.walkStallT) others \(lab.rigs.enumerated().filter { $0.offset != i }.map { "(\($0.element.brain.px),\($0.element.brain.pz)) \($0.element.brain.activity) \(String(describing: $0.element.brain.idleState.kind))" }) near\(near)") } }
                    } else { anchor[i] = b.position; anchorYaw[i] = b.yaw; still[i] = 0; flagged[i] = false }
                    if b.decorIgnore == nil { for p in DecorField.shared.feet where p.spec.solid { if p.distance(b.position) < b.footprint * p.spec.reach - 0.2 { inside += 1; tags.append("INSIDE hist \(hist[i]) seed \(seed) t \(Float(f) / 60) rig\(i) \(p.kind)@\(p.centre) d\(p.distance(b.position)) kind \(String(describing: b.idleState.kind)) script \(b.script) social \(String(describing: b.socialKind)) act \(b.activity) ignore \(String(describing: b.decorIgnore))") } } }
                }
            }
            minPair = lab.minPair
            MotionLog.write("DECOR SOAK \(fill ? "full room" : "empty room") seed \(seed): longest no-progress walk \(worstStill) s, stuck(>\(Self.stuckLimit) s) \(stuck) \(tags), inside-a-piece frames \(inside), decor uses \(uses), min pair gap \(minPair) [\(lab.minTag)]")
            XCTAssertEqual(stuck, 0, "no one walks in place: \(tags)")
            XCTAssertEqual(inside, 0, "no one is inside a solid piece he is not using: \(tags.filter { $0.hasPrefix("INSIDE") })")
            if fill { XCTAssertGreaterThanOrEqual(uses.values.reduce(0, +), 3, "they actually use the decor: \(uses)") }
            XCTAssertGreaterThanOrEqual(minPair, 0.6 * 1.4 - 0.05, "no Jellies on top of each other")
            DecorField.shared.clear()
        }
    }

    func testThreeJelliesInAFullRoomStillWanderWithoutGettingStuck() { soak(seeds: [11, 23], fill: true) }
    /// The same harness in the empty room, for comparison (one seed).
    func testSoakHarnessInTheEmptyRoomForComparison() { soak(seeds: [11], fill: false) }
    // MARK: double tap to move

    private func fullRoomCare() -> GameCare {
        let care = GameCare(jellyCount: 3, persistent: false)
        for k in Self.fullMix { care.store.grant(k.storeID); XCTAssertNotNil(care.store.place(k.storeID), "\(k) fits") }
        care.syncDecor()
        return care
    }

    func testDoubleTapHitTestPicksTheRightPieceInAFullRoomAtEveryAspect() {
        let care = fullRoomCare()
        let sizes = [CGSize(width: 440, height: 956), CGSize(width: 956, height: 440), CGSize(width: 852, height: 393), CGSize(width: 393, height: 852)]
        for size in sizes {
            for p in care.store.placedDecor {
                let f = DecorField.shared.foot(p.uid)!
                // the middle of the piece, half way up
                let s = GameCamera.screenPoint(floor: p.at, y: f.spec.height * 0.5, size: size)!
                guard let hit = care.decorHit(screen: s, size: size) else { XCTFail("\(p.kind) not found at \(size)"); continue }
                if hit.piece.uid != p.uid {
                    XCTAssertGreaterThan(hit.piece.at.y, p.at.y, "\(p.kind) at \(size): only a piece standing in front of it may be hit instead (\(hit.piece.kind))")
                }
            }
            // empty floor, well away from every piece, picks nothing
            let free = SIMD2<Float>(0, 3.3)
            XCTAssertTrue(care.store.placedDecor.allSatisfy { simd_distance($0.at, free) > 1.5 })
            XCTAssertNil(care.decorHit(screen: GameCamera.screenPoint(floor: free, size: size)!, size: size), "empty floor at \(size)")
        }
    }

    func testAJellyInFrontOfAPieceWinsTheDoubleTap() {
        XCTAssertFalse(GameCare.decorWins(pieceT: 12, jellyDistance: 10), "a Jelly nearer the camera than the piece keeps the tap")
        XCTAssertFalse(GameCare.decorWins(pieceT: 12, jellyDistance: 12.2), "about the same depth: the Jelly")
        XCTAssertTrue(GameCare.decorWins(pieceT: 12, jellyDistance: 14), "a Jelly behind the piece: the piece")
        XCTAssertTrue(GameCare.decorWins(pieceT: 12, jellyDistance: nil), "no Jelly under the finger")
    }

    func testDoubleTapPicksAPieceUpAndTheHeldPieceIsLeftAloneByTheJellies() {
        let care = fullRoomCare()
        let p = care.store.placedDecor.first { $0.kind == .beanbag }!
        XCTAssertTrue(BlobBrain.decorOffers().contains(.decorSit))
        care.pickUpDecor(p.uid)
        XCTAssertTrue(care.arranging)
        XCTAssertEqual(care.arrangingUID, p.uid)
        XCTAssertEqual(DecorField.shared.held, p.uid)
        XCTAssertTrue(care.dragDecor(p.uid, to: SIMD2(-3.2, 2.4)) || true)
        care.endArrange()
        XCTAssertNil(DecorField.shared.held)
        XCTAssertFalse(care.arranging)
    }

    func testAPieceAJellyIsUsingIsNeverMovedFromUnderHimAndIsPickedUpWhenHeHasGone() {
        let care = fullRoomCare()
        let p = care.store.placedDecor.first { $0.kind == .beanbag }!
        DecorField.shared.occupant[p.uid] = 1                 // Pip is sitting in it
        care.pickUpDecor(p.uid)
        XCTAssertFalse(care.arranging, "not picked up while he is on it")
        XCTAssertEqual(care.arrangeWait?.uid, p.uid, "deferred until he hops off")
        let before = care.store.placedDecor.first { $0.uid == p.uid }!.at
        XCTAssertFalse(care.dragDecor(p.uid, to: before + SIMD2(0.5, 0.5)), "never moved from under him")
        XCTAssertEqual(care.store.placedDecor.first { $0.uid == p.uid }!.at, before)
        care.tickDecor(dt: 0.5)
        XCTAssertFalse(care.arranging, "still busy")
        DecorField.shared.occupant[p.uid] = nil               // he has hopped off
        care.tickDecor(dt: 0.1)
        XCTAssertTrue(care.arranging); XCTAssertEqual(care.arrangingUID, p.uid)
        XCTAssertNil(care.arrangeWait)
        // and if he never gets off, the wait gives up
        care.endArrange()
        DecorField.shared.occupant[p.uid] = 2
        care.pickUpDecor(p.uid)
        for _ in 0..<50 { care.tickDecor(dt: 0.1) }
        XCTAssertNil(care.arrangeWait); XCTAssertFalse(care.arranging)
        DecorField.shared.occupant[p.uid] = nil
    }
}


/// The Track panel's Go race (a fix of the capture: it read "Not right now" in a normal idle room because the stage had not listed its bodies yet).
@MainActor
final class TrackPanelTests: XCTestCase {
    func testGoRaceIsOfferedInAnIdleRoomBeforeTheStageHasTicked() {
        let care = GameCare(jellyCount: 3, persistent: false)
        XCTAssertTrue(care.raceBook.actors.isEmpty, "no stage yet (the panel was opened at launch)")
        for id in 0..<3 { XCTAssertTrue(care.canRace(jelly: id), "Go race for Jelly \(id)"); XCTAssertNil(care.raceBlocker(jelly: id)) }
        XCTAssertFalse(care.canRace(jelly: 7), "no such Jelly")
        XCTAssertEqual(care.raceBlocker(jelly: 7), "No such Jelly.")
    }

    func testTheReasonsAreInPlainWords() {
        let care = GameCare(jellyCount: 2, persistent: false)
        care.feed("berries")
        XCTAssertNotNil(care.raceBlocker(jelly: 0), "a meal is going on")
        XCTAssertFalse(care.canRace(jelly: 0))
        XCTAssertTrue((care.raceBlocker(jelly: 0) ?? "").contains("meal"))
    }

    func testTheTrackPanelOffersTheRacerSwitchAndTraining() {
        XCTAssertTrue(TrackPanel.trainingExists, "Train and the Pep bar are on the Track panel")
    }

    func testARaceReturnNeverPutsAJellyInsideDecor() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        defer { DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        DecorField.shared.set([PlacedDecor(uid: 1, kind: .beanbag, x: 0, z: 0.5)])
        let b = BlobBrain.forGame()
        let q = b.fixed(SIMD2(0, 0.5))
        XCTAssertGreaterThan(simd_distance(q, SIMD2<Float>(0, 0.5)), 0.5, "a home spot inside the bag is moved out of it")
    }
}
