//
//  RoomRoamWalkInTests.swift
//  Remedy D1 (2026-11-15, the home room round). A rotation changes the roaming floor (a phone: portrait z -4.22..9.03, landscape z -4.22..5.78). A body that stood
//  where the new floor does not reach used to stay there, off the screen, until its own next walk (the round wall only drags one that is far outside). Now the
//  stage's `syncRoam`, right after its wall step, sends every free home body that stands outside the floor on a walk to the nearest floor spot
//  (`BlobBrain.roomWalkIn`, RoomRoam+Traffic.swift). D1 alone still slides at the first step (the walk's `resolve` brings the root in at once); remedy D2 cures that.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RoomRoamWalkInTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private static let landscape: Float = 852 / 393
    private static let portrait: Float = 393 / 852

    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    /// Everything these tests change in the statics; `restore` puts it back.
    private struct Globals {
        let floor = GameCamera.roamFloor, centre = GameCamera.arenaCenter, radius = GameCamera.arenaRadius, walkMaxZ = GameCamera.walkMaxZ
        let walkIn = RoomTraffic.walkIn, walkIns = RoomTraffic.walkIns, walkInMin = RoomTraffic.walkInMin, walkInInset = RoomTraffic.walkInInset, traffic = RoomRoam.traffic
        @MainActor func restore() {
            GameCamera.configureRoom(count: 1)
            if let f = floor { GameCamera.roamFloor = f; RoomLayout.setFront(z: f.maxZ + 0.8) } else { GameCamera.clearRoam() }
            GameCamera.arenaCenter = centre; GameCamera.arenaRadius = radius; GameCamera.walkMaxZ = walkMaxZ
            RoomTraffic.walkIn = walkIn; RoomTraffic.walkIns = walkIns; RoomTraffic.walkInMin = walkInMin; RoomTraffic.walkInInset = walkInInset; RoomRoam.traffic = traffic
        }
    }

    /// The switches on, the numbers at their defaults, the LANDSCAPE floor of one creature's room.
    private func landscapeFloor() -> GameCamera.RoamFloor? {
        RoomRoam.traffic = true; RoomTraffic.walkIn = true; RoomTraffic.walkInMin = 0.3; RoomTraffic.walkInInset = 0.2
        GameCamera.configureRoom(count: 1)
        let f = GameCamera.refreshRoam(aspect: Self.landscape)
        XCTAssertNotNil(f, "premise: the landscape floor exists")
        return f
    }

    /// A brain with no body, as the game makes it, free and at rest at `p`.
    private func bare(at p: SIMD2<Float>, id: Int = 0) -> BlobBrain {
        let b = BlobBrain.forGame()
        b.steerID = id; b.peerGap = 1.4
        b.enabled = true; b.autonomy = true; b.homeRoom = true
        b.script = .none; b.activity = .idle
        b.px = p.x; b.pz = p.y
        Self.keep.append(b)
        return b
    }

    /// The spot a `.goTo` that waits in `b` leads to.
    private func goal(_ b: BlobBrain) -> SIMD2<Float>? {
        if case .goTo(let p)? = b.pending { return p }
        return nil
    }

    // MARK: the floor's nearest spot

    func testNearestSpotOfAFloor() {
        let f = GameCamera.RoamFloor(aspect: 1, minZ: 0, maxZ: 1, zs: [0, 0.25, 0.5, 0.75, 1.0], hw: [2, 2, 2, 2, 2])
        func near(_ p: SIMD2<Float>, _ inset: Float, _ want: SIMD2<Float>, _ what: String, line: UInt = #line) {
            let r = f.nearestSpot(to: p, inset: inset)
            XCTAssertEqual(r.x, want.x, accuracy: 1e-5, what, line: line)
            XCTAssertEqual(r.y, want.y, accuracy: 1e-5, what, line: line)
        }
        near(SIMD2(0.5, 0.5), 0, SIMD2(0.5, 0.5), "a point on the floor stays")
        near(SIMD2(0.5, 3), 0, SIMD2(0.5, 1), "in front of the floor: the front row")
        near(SIMD2(0.5, -2), 0, SIMD2(0.5, 0), "behind the floor: the back row")
        near(SIMD2(5, 0.5), 0, SIMD2(2, 0.5), "beside the floor: the row's end")
        near(SIMD2(-5, 0.5), 0, SIMD2(-2, 0.5), "beside the floor, the other side")
        near(SIMD2(5, 3), 0, SIMD2(2, 1), "past a corner: the corner")
        near(SIMD2(0.5, 3), 0.2, SIMD2(0.5, 0.8), "inset: 0.2 inside the front row")
        near(SIMD2(5, 0.5), 0.2, SIMD2(1.8, 0.5), "inset: 0.2 inside the row's end")
        near(SIMD2(1.9, 0.5), 0.2, SIMD2(1.8, 0.5), "inset: a point in the edge band moves in")
        near(SIMD2(0.5, 0.5), 0.2, SIMD2(0.5, 0.5), "inset: a point far enough inside stays")
        near(SIMD2(5, 3), 0.6, SIMD2(1.4, 0.5), "an inset wider than the floor is deep: the middle row")

        let t = GameCamera.RoamFloor(aspect: 1, minZ: 0, maxZ: 1, zs: [0, 0.25, 0.5, 0.75, 1.0], hw: [3, 2.5, 2, 1.5, 1])
        XCTAssertEqual(t.nearestSpot(to: SIMD2(5, 0.5)).x, 2, accuracy: 1e-5, "a narrowing floor: the row's own half width")
        XCTAssertEqual(t.nearestSpot(to: SIMD2(5, 2)).x, 1, accuracy: 1e-5, "in front of a narrowing floor: the front row's half width")
        XCTAssertEqual(t.nearestSpot(to: SIMD2(5, 0.625)).x, 1.75, accuracy: 1e-5, "between two rows: the half width between them")

        let e = GameCamera.RoamFloor(aspect: 1, minZ: 0, maxZ: 0, zs: [], hw: [])
        XCTAssertEqual(e.nearestSpot(to: SIMD2(5, 3)), SIMD2<Float>(5, 3), "no rows: the point comes back")
        XCTAssertTrue(f.nearestSpot(to: SIMD2(Float.nan, 0.5)).x.isNaN, "not a number: the point comes back")
    }

    // MARK: who is sent

    func testWhoIsSent() {
        let g = Globals(); defer { g.restore() }
        guard let floor = landscapeFloor() else { return }
        let out = SIMD2<Float>(0, floor.maxZ + 1)
        typealias Row = (name: String, wanted: Bool, set: (BlobBrain) -> Void)
        let rows: [Row] = [
            ("at rest", true, { _ in }),
            ("looking around", true, { $0.script = .look(index: 0, t: 0, base: 0); $0.activity = .lookingAround }),
            ("stepping in place", true, { $0.script = .stepInPlace(t: 0, dur: 1); $0.activity = .steppingInPlace }),
            ("disabled", false, { $0.enabled = false }),
            ("not the home room (the park, a trip, a meal, the bath)", false, { $0.homeRoom = false }),
            ("autonomy off (a welcome, a tour)", false, { $0.autonomy = false }),
            ("a player command runs", false, { $0.commanded = true }),
            ("goodnight", false, { $0.commandedGoodnight = true }),
            ("idles blocked", false, { $0.idleBlocked = true }),
            ("reserved", false, { $0.reserved = true }),
            ("a close-up", false, { $0.focusPaused = true }),
            ("a request waits", false, { $0.pending = .wave }),
            ("a request runs", false, { $0.job = .wave }),
            ("asleep", false, { $0.idleState.kind = .sleep }),
            ("sitting (an idle)", false, { $0.idleState.kind = .sit }),
            ("walking", false, { $0.script = .walk(target: SIMD2(0, 0), then: .none); $0.activity = .walking }),
            ("an idle's script", false, { $0.script = .idle }),
            ("waving", false, { $0.script = .wave(t: 0, side: 1, then: .none); $0.activity = .waving }),
            ("touched", false, { $0.activity = .touched }),
            ("racing", false, { $0.race.active = true }),
            ("volleyball", false, { $0.volley.active = true }),
            ("the bubble wand", false, { $0.bubbleLeash = BubbleLeash(lo: SIMD2(-1, -1), hi: SIMD2(1, 1), slot: SIMD2(0, 0), look: SIMD2(0, 0)) }),
            ("waits for a toy", false, { $0.toy.waitUID = 3 }),
            ("chases a toy", false, { $0.toy.chaseSpot = SIMD2(0, 0) }),
        ]
        for row in rows {
            let b = bare(at: out)
            row.set(b)
            XCTAssertEqual(b.roomWalkInWanted(floor), row.wanted, row.name)
        }
        XCTAssertFalse(bare(at: SIMD2(0, floor.maxZ - 1)).roomWalkInWanted(floor), "on the floor")
        XCTAssertFalse(bare(at: SIMD2(0, floor.maxZ + 0.2)).roomWalkInWanted(floor), "0.2 outside: nearer than walkInMin, left alone")
        XCTAssertTrue(bare(at: SIMD2(0, floor.maxZ + 0.4)).roomWalkInWanted(floor), "0.4 outside in front")
        XCTAssertTrue(bare(at: SIMD2(floor.halfWidth(at: 0) + 1, 0)).roomWalkInWanted(floor), "1.0 outside at the side")
        XCTAssertEqual(bare(at: out).roomOutside(floor), 1, accuracy: 1e-4, "how far outside: the distance to the outline")
    }

    func testSwitchesAndEmptyInputs() {
        let g = Globals(); defer { g.restore() }
        guard let floor = landscapeFloor() else { return }
        let b = bare(at: SIMD2(0, floor.maxZ + 1))
        XCTAssertEqual(BlobBrain.roomWalkIn([]), 0)
        XCTAssertEqual(BlobBrain.roomWalkIn([nil]), 0)
        RoomTraffic.walkIn = false
        XCTAssertEqual(BlobBrain.roomWalkIn([b]), 0, "D1's own switch off")
        XCTAssertNil(b.pending)
        RoomTraffic.walkIn = true; RoomRoam.traffic = false
        XCTAssertEqual(BlobBrain.roomWalkIn([b]), 0, "the whole traffic step off (-RoomTraffic 0)")
        XCTAssertNil(b.pending)
        RoomRoam.traffic = true; GameCamera.clearRoam()
        XCTAssertEqual(BlobBrain.roomWalkIn([b]), 0, "no floor")
        XCTAssertNil(b.pending)
        XCTAssertNotNil(GameCamera.refreshRoam(aspect: Self.landscape))
        let before = RoomTraffic.walkIns
        XCTAssertEqual(BlobBrain.roomWalkIn([b]), 1, "on: the body outside is sent")
        XCTAssertEqual(RoomTraffic.walkIns, before + 1)
        guard let to = goal(b) else { return XCTFail("a .goTo waits in the brain") }
        XCTAssertTrue(floor.contains(to), "the spot is on the floor: \(to)")
        XCTAssertEqual(to.x, 0, accuracy: 0.02)
        XCTAssertEqual(to.y, floor.maxZ - 0.2, accuracy: 0.02, "the nearest floor point, walkInInset inside the front row")
        XCTAssertEqual(BlobBrain.roomWalkIn([b]), 0, "a second call sends nobody twice (a request waits)")
        XCTAssertEqual(RoomTraffic.walkIns, before + 1)
    }

    // MARK: which spot

    func testTwoBodiesGetTwoSpots() {
        let g = Globals(); defer { g.restore() }
        guard let floor = landscapeFloor() else { return }
        let near = bare(at: SIMD2(0, floor.maxZ + 1.0), id: 0), far = bare(at: SIMD2(0, floor.maxZ + 2.4), id: 1)
        XCTAssertEqual(BlobBrain.roomWalkIn([far, near]), 2)
        guard let a = goal(near), let b = goal(far) else { return XCTFail("both get a .goTo") }
        XCTAssertTrue(floor.contains(a) && floor.contains(b), "both spots are on the floor: \(a) \(b)")
        XCTAssertEqual(a.y, floor.maxZ - 0.2, accuracy: 0.02, "the nearer body keeps the nearest spot")
        XCTAssertGreaterThanOrEqual(simd_distance(a, b), 1.4 * 1.05 - 0.001, "the two spots are a body's width apart")
    }

    func testASpotAnotherBodyHoldsIsNotGiven() {
        let g = Globals(); defer { g.restore() }
        guard let floor = landscapeFloor() else { return }
        let front = SIMD2<Float>(0, floor.maxZ - 0.2), out = SIMD2<Float>(0, floor.maxZ + 1.0), back = SIMD2<Float>(0, floor.maxZ - 3.5)
        // control: the other body is far away, so the nearest spot is given
        let alone = bare(at: out, id: 0)
        XCTAssertEqual(BlobBrain.roomWalkIn([alone, bare(at: back, id: 1)]), 1)
        XCTAssertEqual(goal(alone)?.y ?? 0, front.y, accuracy: 0.02, "control: the nearest spot")
        // another body STANDS on the nearest spot
        let b1 = bare(at: out, id: 0), stander = bare(at: front + SIMD2<Float>(0.2, -0.1), id: 1)
        XCTAssertEqual(BlobBrain.roomWalkIn([b1, stander]), 1)
        guard let s1 = goal(b1) else { return XCTFail("a .goTo waits") }
        XCTAssertTrue(floor.contains(s1), "on the floor: \(s1)")
        XCTAssertGreaterThanOrEqual(simd_distance(s1, stander.position), 1.4 * 1.05 - 0.001, "not onto the one who stands there")
        // another body WALKS to the nearest spot
        let b2 = bare(at: out, id: 0), walker = bare(at: back, id: 1)
        walker.script = .walk(target: front, then: .none); walker.activity = .walking
        XCTAssertEqual(BlobBrain.roomWalkIn([b2, walker]), 1)
        guard let s2 = goal(b2) else { return XCTFail("a .goTo waits") }
        XCTAssertTrue(floor.contains(s2), "on the floor: \(s2)")
        XCTAssertGreaterThanOrEqual(simd_distance(s2, front), 1.4 * 1.05 - 0.001, "not onto the spot another walks to")
    }

    // MARK: a rotation, with a real body

    private struct Take { var sent = 0, walkIns = 0; var outStart: Float = 0, doneAt: Float = -1, outEnd: Float = 0, bodyOutEnd: Float = 0, maxStep: Float = 0 }

    /// One real body (FootWallTurnTests' rig: the stage's frame order, every frame skinned) stands on the PORTRAIT floor, in front of where the landscape floor ends.
    /// The room turns to landscape as the stage's `syncRoam` does it (the new floor, the wall step, then D1's call), then `seconds` of frames run.
    /// nil = a premise failed (already reported).
    private func rotate(walkIn: Bool, seconds: Float) -> Take? {
        RoomRoam.traffic = true; RoomTraffic.walkIn = walkIn; RoomTraffic.walkInMin = 0.3; RoomTraffic.walkInInset = 0.2
        GameCamera.configureRoom(count: 1)
        guard let lf0 = GameCamera.refreshRoam(aspect: Self.landscape), let pf = GameCamera.refreshRoam(aspect: Self.portrait) else { XCTFail("premise: both floors exist"); return nil }
        // (the camera's statics are the PORTRAIT floor's now: the floor, the front wall, the arena)
        let outBy = min(1.2, pf.maxZ - 0.3 - lf0.maxZ)
        guard outBy > 0.8 else { XCTFail("premise: the portrait floor (front \(pf.maxZ)) reaches well past the landscape floor (front \(lf0.maxZ))"); return nil }
        let start = SIMD2<Float>(0, lf0.maxZ + outBy)

        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let a = JellyActor(id: 0, name: "Solo", simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: start)
        a.skinner.configureTail(rm)
        a.reset(drop: 0.35, shift: false)
        a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius          // (MelonStage.init: every game body gets the room's round wall)
        let b = BlobBrain.forGame()
        b.attach(renderMesh: rm, synchronous: true)
        b.seed = 5; b.steerID = 0; b.feature = .wings
        a.brain = b
        Self.keep.append(a); Self.keep.append(b)
        a.sim.teleport(toXZ: start)
        for _ in 0..<150 { a.sim.step() }
        b.currentPose(a.sim)
        b.autonomy = false; b.idleMood = .happy; b.anticsEnabled = false; b.watching = true; b.sleepEnabled = false; b.amplitude = 1
        var dyn = [Float](repeating: 0, count: rm.vertexCount * 6)
        func frame() {
            b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false)
            a.skinner.jelly.tick(brain: b, sim: a.sim, dt: a.sim.stepDt)
            if a.updateSleep(forceAwake: false) { a.sim.step() }
            b.refitBeans(a.sim, a.skinner)
            dyn.withUnsafeMutableBufferPointer { a.skinner.update(x: a.sim.x, index: rm.index, into: $0.baseAddress!) }
        }
        for _ in 0..<60 { frame() }
        var settle = 0
        while !b.scriptIsNone, settle < 180 { frame(); settle += 1 }
        guard b.scriptIsNone else { XCTFail("premise: the body stands still before the rotation (activity \(b.activity))"); return nil }

        // the rotation, in the order of MelonStage.syncRoam: the floor for the new aspect, the wall step, D1's call
        guard let lf = GameCamera.refreshRoam(aspect: Self.landscape) else { XCTFail("premise: the landscape floor"); return nil }
        MelonController.applyRoomArena(actors: [a], parkActors: [], bathFenceLifted: false)
        var take = Take()
        take.outStart = b.roomOutside(lf)
        b.homeRoom = true; b.autonomy = true
        if walkIn { XCTAssertTrue(b.roomWalkInWanted(lf), "premise: the standing body is free and outside the new floor (activity \(b.activity), outside by \(take.outStart))") }
        let before = RoomTraffic.walkIns
        take.sent = BlobBrain.roomWalkIn([a.brain])
        take.walkIns = RoomTraffic.walkIns - before
        b.autonomy = false          // (nothing but the walk-in moves him from here on: no wander pick of his own)

        var prev = b.position
        for f in 0..<Int(seconds * 60) {
            frame()
            take.maxStep = max(take.maxStep, simd_distance(prev, b.position)); prev = b.position
            if take.doneAt < 0, take.sent > 0, f > 10, b.activity != .walking, b.activity != .coming, b.isWalkScript == false { take.doneAt = Float(f) / 60 }
        }
        take.outEnd = b.roomOutside(lf)
        let c = a.sim.centroid()
        let body = SIMD2<Float>(c.x, c.z)
        take.bodyOutEnd = simd_distance(body, lf.nearestSpot(to: body))
        func n(_ v: Float) -> String { String(format: "%.3f", v) }
        MotionLog.write("RoomRoamWalkIn rotate walkIn=\(walkIn) sent=\(take.sent) outStart=\(n(take.outStart)) doneAt=\(n(take.doneAt)) outEnd=\(n(take.outEnd)) bodyOutEnd=\(n(take.bodyOutEnd)) maxRootStep=\(n(take.maxStep))")
        return take
    }

    func testARotationBringsAFreeBodyBackOntoTheFloor() {
        let g = Globals(); defer { g.restore() }
        guard let on = rotate(walkIn: true, seconds: 8) else { return }
        XCTAssertGreaterThan(on.outStart, 0.8, "premise: after the rotation he stands outside the new floor")
        XCTAssertEqual(on.sent, 1, "the stage's call sends him")
        XCTAssertEqual(on.walkIns, 1)
        XCTAssertGreaterThanOrEqual(on.doneAt, 0, "his walk ends within 8 s")
        XCTAssertLessThan(on.outEnd, 0.01, "his root is on the floor")
        XCTAssertLessThan(on.bodyOutEnd, 0.25, "and so is his body")
    }

    /// Control: with D1's switch off nothing else brings a body that stands still onto the new floor (the round wall does not reach him, the standing brain does not
    /// move its root). In the game he would stay there until his own next walk.
    func testWithTheSwitchOffTheStandingBodyStaysOutside() {
        let g = Globals(); defer { g.restore() }
        guard let off = rotate(walkIn: false, seconds: 4) else { return }
        XCTAssertGreaterThan(off.outStart, 0.8, "premise: after the rotation he stands outside the new floor")
        XCTAssertEqual(off.sent, 0)
        XCTAssertEqual(off.walkIns, 0)
        XCTAssertGreaterThan(off.outEnd, 0.3, "he is still outside")
    }
}
