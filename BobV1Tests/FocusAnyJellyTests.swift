//
//  FocusAnyJellyTests.swift
//  Touch, pick-up and the close-up for ANY Jelly: picking by hit, "Pip, come here", "Everyone, come here", the camera framing the row,
//  the one-Jelly game unchanged. The mini stage (`FocusAnyRun`) ticks the brains and the care like the stage does, with no renderer.
//

import XCTest
import simd
@testable import BobV1

/// Three actors + a care, ticked in the stage's order: Bob's brain, the others' brains, the care (`tick`, `tickOthers`), then the bodies.
@MainActor
final class FocusAnyRun {
    let care: GameCare
    let actors: [JellyActor]
    let rm: RenderMesh
    /// `peers`: wired like the stage's `wireRoster` (peer snapshot with a huge id for a standing Jelly, keepApart under the floor rules, makeRoom every 0.25 s),
    /// autonomy ON: the bodies block each other as in the room (RoomMovementTests). Default off: the older focus tests walk through each other.
    let peersWired: Bool
    var snapshot: [(pos: SIMD2<Float>, walking: Bool)] = []
    var aside: [Float] = [], asideClock: Float = 0
    /// The stage's no-getting-stuck guarantee (it runs it every step; a wanderer standing beside the call spot can pin a walker until it acts).
    let watchdog = StuckWatchdog()
    init(count: Int = 3, voice: VoiceCoordinator? = nil, peers: Bool = false) {
        peersWired = peers
        let rm = buildRenderMesh(); self.rm = rm
        let care = GameCare(voice: voice, jellyCount: count, persistent: false, defaults: UserDefaults(suiteName: "FocusAny.\(count)")!)
        let sm = buildSimMesh()
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let spots = JellyRoster.spawnSpots(count: count)
        self.care = care
        actors = (0..<count).map {
            let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
            a.profile = care.jelly($0); a.care = care
            a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius
            let b = BlobBrain.forGame()
            b.demo = nil; b.runMoveDemo = nil; b.autonomy = peers
            b.seed = UInt64(7 + $0)
            care.wireWorld(b, isBob: $0 == 0)
            b.attach(renderMesh: rm, synchronous: true)
            a.brain = b
            a.reset(drop: 0.35, shift: count > 1)
            return a
        }
        care.touchPlay = nil
        if peers {
            aside = [Float](repeating: 0, count: max(count, JellyRoster.maxCount))
            snapshot = actors.map { (pos: $0.floor, walking: false) }
            for (i, a) in actors.enumerated() {
                let b = a.brain!
                b.steerID = i; b.peerGap = MelonController.jellyGap
                b.socialOthers = { [unowned self] in self.actors.compactMap(\.brain).filter { $0 !== b } }
                let floorRules = b.resolve
                b.resolve = { [unowned self] p, rad in floorRules(MelonController.keepApart(floorRules(p, rad), id: i, peers: self.snapshot), rad) }
                b.peers = { [unowned self] in self.snapshot.enumerated().filter { $0.offset != i }.map { (id: $0.element.walking ? $0.offset : Int.max / 2, pos: $0.element.pos) } }
                b.restTimer = 1.0 + Float(i); b.idleState.cooldown = 1e6; b.socialBook.cooldown = 1e6          // (plain wandering: no specials, no socials)
            }
        }
    }
    /// Puts Jelly `id` down at `xz`, standing (the body settles, the brain re-reads its pose).
    func place(_ id: Int, at xz: SIMD2<Float>, rest: Float = 1e6) {
        let a = actors[id]
        guard let b = a.brain else { return }
        b.abortScript(a.sim, a.skinner)
        b.restTimer = rest
        a.sim.teleport(toXZ: xz)
        for _ in 0..<120 { a.sim.step() }
        b.currentPose(a.sim)
        if peersWired { snapshot = actors.map { (pos: $0.floor, walking: false) } }
    }
    func tick() {
        let dt = actors[0].sim.stepDt
        if peersWired {
            snapshot = actors.map { (pos: $0.floor, walking: $0.isWalking) }
            asideClock += dt
            if asideClock >= 0.25 { MelonController.makeRoom(snapshot: snapshot, brains: actors.map(\.brain), cooldown: &aside, dt: asideClock); asideClock = 0 }
            if actors.count > 1 { watchdog.tick(pos: snapshot, brains: actors.map(\.brain), dt: dt) }
        }
        for a in actors {
            guard let b = a.brain else { continue }
            if peersWired, a.id == 0 {          // (the stage's per-frame flags for Jelly 0; the care sets the others' in `tickOthers`)
                b.idleBlocked = ((care.focus.isActive && care.focusGroup.includes(0)) || care.trayOut || care.bath.active) && !b.commanded
                b.focusPaused = false
            }
            b.tick(sim: a.sim, skinner: a.skinner, dt: dt, touched: false)
            a.skinner.jelly.tick(brain: b, sim: a.sim, dt: dt)
            if a.id == 0 { care.tick(brain: b, renderer: nil, dt: dt, sim: a.sim) }
        }
        if actors.count > 1 { care.tickOthers(actors, dt: dt) }
        for a in actors { a.sim.step() }
    }
    @discardableResult
    func run(_ s: Float, until: (() -> Bool)? = nil) -> Bool {
        for _ in 0..<Int(s * 60) { tick(); if let until, until() { return true } }
        return until?() ?? false
    }
    func centroid(_ id: Int) -> SIMD3<Float> { actors[id].sim.centroid() }
}

@MainActor
final class FocusAnyJellyTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []     // the runtime aborts when these are released (see MelonModel)

    private func run3() -> FocusAnyRun { let r = FocusAnyRun(); Self.keep.append(r); r.run(1.5); return r }

    // MARK: picking

    /// A hit at each Jelly's own position picks that Jelly; a hit between all of them picks nobody.
    func testEachJellyIdIsPickedByAHitAtItsPosition() {
        let r = run3()
        let size = CGSize(width: 440, height: 956)
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let n = r.rm.vertexCount * 6
        var dyn = [Float](repeating: 0, count: n * 3)
        dyn.withUnsafeMutableBufferPointer { buf in
            for a in r.actors { a.skinner.update(x: a.sim.x, index: r.rm.index, into: buf.baseAddress! + a.id * n) }
            let bodies = r.actors.map { TouchPick.Body(id: $0.id, dyn: UnsafePointer(buf.baseAddress! + $0.id * n), x: $0.sim.x) }
            func screen(_ w: SIMD3<Float>) -> CGPoint {
                let c = cam.viewProj * SIMD4<Float>(w.x, w.y, w.z, 1)
                return CGPoint(x: CGFloat(c.x / c.w * 0.5 + 0.5) * size.width, y: CGFloat(0.5 - c.y / c.w * 0.5) * size.height)
            }
            for a in r.actors {
                let c = a.sim.centroid()
                let p = screen(c)
                XCTAssertTrue(CGRect(origin: .zero, size: size).contains(p), "Jelly \(a.id) is on screen at \(p)")
                let hit = TouchPick.pick(p, size: size, viewProj: cam.viewProj, invViewProj: cam.invViewProj, bodies: bodies,
                                         index: r.rm.index, bodyIndexCount: r.rm.body.first + r.rm.body.count)
                XCTAssertEqual(hit?.id, a.id, "a hit on Jelly \(a.id)")
                // only that Jelly in the list (the others hidden): still him, and nobody else answers
                let solo = TouchPick.pick(p, size: size, viewProj: cam.viewProj, invViewProj: cam.invViewProj, bodies: bodies.filter { $0.id == a.id },
                                          index: r.rm.index, bodyIndexCount: r.rm.body.first + r.rm.body.count)
                XCTAssertEqual(solo?.id, a.id)
                let others = TouchPick.pick(p, size: size, viewProj: cam.viewProj, invViewProj: cam.invViewProj, bodies: bodies.filter { $0.id != a.id },
                                            index: r.rm.index, bodyIndexCount: r.rm.body.first + r.rm.body.count)
                XCTAssertNotEqual(others?.id, a.id)
            }
            let none = TouchPick.pick(CGPoint(x: 8, y: 8), size: size, viewProj: cam.viewProj, invViewProj: cam.invViewProj, bodies: bodies,
                                      index: r.rm.index, bodyIndexCount: r.rm.body.first + r.rm.body.count)
            XCTAssertNil(none, "the corner of the room is nobody")
        }
    }

    // MARK: Pip, come here

    func testComeHerePipFocusesPipAndTheOthersKeepRoaming() {
        let r = run3()
        let care = r.care
        care.comeHere(jelly: 1)
        XCTAssertEqual(care.focusedJellies, [1])
        XCTAssertEqual(care.focus.phase, .approaching)
        XCTAssertEqual(care.focusGroup.touchID, 1, "the touch goes to the focused Jelly")
        XCTAssertTrue(GameCamera.focusSpots.isEmpty, "one Jelly: the ordinary close-up on the call spot")
        XCTAssertTrue(r.run(30) { care.focus.isFocused }, "Pip runs up and the close-up starts: phase \(care.focus.phase) pip \(r.centroid(1)) act \(String(describing: r.actors[1].brain?.activity)) arrived \(care.focusGroup.arrived)")
        let c = r.centroid(1)
        XCTAssertLessThan(simd_length(SIMD2(c.x, c.z) - GameCamera.callSpot), 0.7, "Pip is on the front spot: \(c)")
        XCTAssertEqual(care.touchPlayTarget, 1)
        // the others are not frozen or hidden (W2): their idles and autonomy stay as they were, and Bob never came
        r.run(3)
        XCTAssertFalse(r.actors[2].brain!.idleBlocked, "Moss's idle legs are not held")
        XCTAssertFalse(r.actors[0].brain!.focusPaused); XCTAssertFalse(r.actors[2].brain!.focusPaused)
        XCTAssertNil(care.focusGroup.saved[0], "Bob's wandering is not paused")
        XCTAssertNil(care.focusGroup.saved[2])
        // leaving: everyone is normal again
        care.release()
        XCTAssertTrue(r.run(8) { care.focus.phase == .roaming })
        r.run(0.5)
        XCTAssertEqual(care.focusedJellies, [])
        XCTAssertFalse(r.actors[2].brain!.idleBlocked)
        XCTAssertNil(care.focusGroup.saved[0])
        XCTAssertEqual(care.focusGroup.touchID, 0)
    }

    /// Plain "come here" calls the selected Jelly; Bob without a selection.
    func testPlainComeHereCallsTheTargetJelly() {
        let r = run3()
        r.care.comeHere()
        XCTAssertEqual(r.care.focusedJellies, [0])
        r.care.release()
    }

    /// Come is always obeyed, in any mood, by any Jelly (the order is a brain request, never mood-gated).
    func testComeIsObeyedByAGrumpyJelly() {
        let r = run3()
        r.care.needs(for: 1).set(.hunger, 0.0); r.care.needs(for: 1).set(.thirst, 0.0); r.care.needs(for: 1).set(.attention, 0.0)
        XCTAssertEqual(r.care.needs(for: 1).mood, .grumpy)
        r.care.comeHere(jelly: 1)
        XCTAssertTrue(r.run(30) { r.care.focus.isFocused })
    }

    // MARK: everyone

    func testEveryoneComesAndTheCameraFramesAllThree() {
        let r = run3()
        let care = r.care
        care.comeHereEveryone()
        XCTAssertEqual(care.focusedJellies, [0, 1, 2])
        XCTAssertEqual(GameCamera.focusSpots.count, 3)
        XCTAssertTrue(r.run(40) { care.focus.isFocused }, "all three arrive before the camera goes in")
        r.run(1.5)                                               // the spring settles
        let aspect: Float = 440.0 / 956.0
        let cam = GameCamera.camera(aspect: aspect, focus: 1)
        for id in 0..<3 {
            let c = r.centroid(id)
            XCTAssertLessThan(simd_length(SIMD2(c.x, c.z) - care.focusSpot(for: id)), 0.8, "Jelly \(id) at his spot: \(c)")
            // both sides of his body and the crown are inside the frame
            for off in [SIMD3<Float>(-BobShape.R, 0, 0), SIMD3(BobShape.R, 0, 0), SIMD3(0, BobShape.H * 0.5, 0), SIMD3(0, -c.y, 0)] {
                let q = cam.viewProj * SIMD4<Float>(c.x + off.x, c.y + off.y, c.z + off.z, 1)
                XCTAssertLessThanOrEqual(abs(q.x / q.w), 1.0, "Jelly \(id) fits the width (\(off))")
                XCTAssertLessThanOrEqual(abs(q.y / q.w), 1.0, "Jelly \(id) fits the height (\(off))")
            }
        }
        // the targeted Jelly (Bob) is front and centre, the others a little behind at the sides
        XCTAssertEqual(care.focusSpot(for: 0), GameCamera.callSpot)
        XCTAssertLessThan(care.focusSpot(for: 1).y, GameCamera.callSpot.y - 0.3)
        XCTAssertLessThan(care.focusSpot(for: 2).y, GameCamera.callSpot.y - 0.3)
        XCTAssertLessThan(abs(care.focusSpot(for: 1).x - care.focusSpot(for: 2).x), 2.6)
        // the touch picks the right Jelly even where they overlap, through the close-up camera
        do {
            let size = CGSize(width: 440, height: 956)
            let pc = GameCamera.camera(aspect: Float(size.width / size.height), focus: 1)
            let n = r.rm.vertexCount * 6
            var dyn = [Float](repeating: 0, count: n * 3)
            dyn.withUnsafeMutableBufferPointer { buf in
                for a in r.actors { a.skinner.update(x: a.sim.x, index: r.rm.index, into: buf.baseAddress! + a.id * n) }
                let bodies = r.actors.map { TouchPick.Body(id: $0.id, dyn: UnsafePointer(buf.baseAddress! + $0.id * n), x: $0.sim.x) }
                for a in r.actors {
                    let c = a.sim.centroid()
                    let q = pc.viewProj * SIMD4<Float>(c.x, c.y, c.z, 1)
                    let pt = CGPoint(x: CGFloat(q.x / q.w * 0.5 + 0.5) * size.width, y: CGFloat(0.5 - q.y / q.w * 0.5) * size.height)
                    let hit = TouchPick.pick(pt, size: size, viewProj: pc.viewProj, invViewProj: pc.invViewProj, bodies: bodies,
                                             index: r.rm.index, bodyIndexCount: r.rm.body.first + r.rm.body.count)
                    XCTAssertEqual(hit?.id, a.id, "the close-up pick at Jelly \(a.id)")
                }
                // on the overlap of the front Jelly and a side one: the front (nearer the camera) wins
                let f = r.centroid(0), sd = r.centroid(1)
                let mid = (f + sd) * 0.5
                let q = pc.viewProj * SIMD4<Float>(mid.x, mid.y, mid.z, 1)
                let pt = CGPoint(x: CGFloat(q.x / q.w * 0.5 + 0.5) * size.width, y: CGFloat(0.5 - q.y / q.w * 0.5) * size.height)
                let hit = TouchPick.pick(pt, size: size, viewProj: pc.viewProj, invViewProj: pc.invViewProj, bodies: bodies,
                                         index: r.rm.index, bodyIndexCount: r.rm.body.first + r.rm.body.count)
                XCTAssertEqual(hit?.id, 0, "the front Jelly wins on the overlap")
            }
        }
        XCTAssertEqual(care.focusGroup.ids, [0, 1, 2])
        care.release()
        XCTAssertTrue(r.run(10) { care.focus.phase == .roaming })
        r.run(0.5)
        XCTAssertTrue(GameCamera.focusSpots.isEmpty, "the wide pose is gone once the camera is home")
        XCTAssertEqual(care.focusedJellies, [])
        for a in r.actors { XCTAssertFalse(a.brain!.idleBlocked, "Jelly \(a.id) wanders again") }
    }

    func testEveryoneRowIsWiderThanOneJelly() {
        let aspect: Float = 440.0 / 956.0
        let one = GameCamera.focusPose(aspect: aspect)
        XCTAssertEqual(GameCamera.focusPose(aspect: aspect, spots: [GameCamera.callSpot]).eye, one.eye, "one spot is exactly the one-Jelly pose")
        let row = GameCamera.focusPose(aspect: aspect, spots: GameCamera.focusRowSpots(count: 3))
        XCTAssertGreaterThan(simd_length(row.eye - row.target), simd_length(one.eye - one.target) * 2, "the camera backs off to take the row in")
        XCTAssertEqual(row.target.x, 0, accuracy: 1e-4)
    }

    func testEveryoneStandsAroundTheTargetedJelly() {
        let r = run3()
        r.care.select.setBlobs(JellyRoster.selectBlobs(count: 3))
        r.care.select.doubleTap(2)
        XCTAssertEqual(r.care.targetJelly, 2)
        r.care.comeHereEveryone()
        XCTAssertEqual(r.care.focusSpot(for: 2), GameCamera.callSpot, "the selected Jelly is front and centre")
        XCTAssertLessThan(r.care.focusSpot(for: 0).y, GameCamera.callSpot.y)
        r.care.release()
    }

    /// The dock's Feed / Drink target the Jelly in a single close-up (`targetJelly`), and Bob again afterwards.
    func testDockTargetsTheFocusedJelly() {
        let r = run3()
        XCTAssertEqual(r.care.targetJelly, 0)
        r.care.comeHere(jelly: 1)
        XCTAssertEqual(r.care.targetJelly, 1)
        XCTAssertTrue(r.run(30) { r.care.focus.isFocused })
        XCTAssertEqual(r.care.targetJelly, 1)
        r.care.release()
        XCTAssertTrue(r.run(10) { r.care.focus.phase == .roaming })
        XCTAssertEqual(r.care.targetJelly, 0)
    }

    // MARK: one Jelly unchanged

    func testSingleJellyFocusIsUnchanged() {
        let r = FocusAnyRun(count: 1); Self.keep.append(r)
        r.run(1)
        r.care.comeHere()
        XCTAssertEqual(r.care.focusedJellies, [0])
        XCTAssertTrue(GameCamera.focusSpots.isEmpty)
        XCTAssertFalse(r.care.focusGroup.rowOpen)
        XCTAssertTrue(r.run(30) { r.care.focus.isFocused })
        let aspect: Float = 440.0 / 956.0
        let p = GameCamera.focusPose(aspect: aspect)
        let cam = GameCamera.camera(aspect: aspect, focus: 1)
        XCTAssertEqual(cam.pos.x, p.eye.x, accuracy: 1e-4); XCTAssertEqual(cam.pos.y, p.eye.y, accuracy: 1e-4); XCTAssertEqual(cam.pos.z, p.eye.z, accuracy: 1e-4)
        r.care.comeHereEveryone()                                  // already focused: ignored
        XCTAssertEqual(r.care.focusedJellies, [0])
        r.care.release()
        XCTAssertTrue(r.run(10) { r.care.focus.phase == .roaming })
        XCTAssertEqual(r.care.focusedJellies, [])
    }
}
