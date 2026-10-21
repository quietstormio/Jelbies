//
//  DiningJellyTests.swift
//  Meals for the targeted Jelly: feed(jelly: 1) makes Pip eat and raises Pip's hunger only; a Full Moss refuses (label over Moss); one meal
//  at a time; an id outside the roster feeds Bob. Also writes the labelled capture (DINE_JELLY_OUT) of Pip eating with the others in the room.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class DiningJellyTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// Three Jellies on the stage's per-step order: every brain, Bob's care tick, the others' tick, the bodies, the held-piece refresh.
    @MainActor final class Room {
        let care: GameCare
        var actors: [JellyActor] = []
        var snapshot: [(pos: SIMD2<Float>, walking: Bool)] = []
        var t: Float = 0
        var sawEating: [Bool] = [false, false, false]
        init(count: Int = 3, wander: Bool = false) {
            sawEating = [Bool](repeating: false, count: count)
            let suite = UserDefaults(suiteName: "DiningJelly.\(UUID().uuidString)")!
            care = GameCare(jellyCount: count, persistent: false, defaults: suite)
            let sm = buildSimMesh(), rm = buildRenderMesh()
            let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
            let spots = JellyRoster.spawnSpots(count: count)
            actors = (0..<count).map { [unowned self] in
                let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
                a.reset(drop: 0.35, shift: count > 1)
                let b = BlobBrain.forGame()
                b.demo = nil; b.runMoveDemo = nil
                b.autonomy = wander && $0 > 0
                b.attach(renderMesh: rm, synchronous: true)
                care.wireWorld(b, isBob: $0 == 0)
                if count > 1 {
                    let id = $0
                    b.steerID = id; b.peerGap = MelonController.jellyGap
                    b.peers = { [unowned self] in self.snapshot.enumerated().filter { $0.offset != id }.map { (id: $0.element.walking ? $0.offset : Int.max / 2, pos: $0.element.pos) } }
                    let floorRules = b.resolve
                    b.resolve = { [unowned self] p, r in
                        self.snapshot.isEmpty ? floorRules(p, r) : floorRules(MelonController.keepApart(floorRules(p, r), id: id, peers: self.snapshot, gap: self.care.groupGap), r)
                    }
                }
                a.brain = b
                a.profile = care.jelly($0); a.care = care
                return a
            }
            for a in actors { for _ in 0..<240 { a.sim.step() }; a.brain?.currentPose(a.sim) }
            for a in actors { a.profile?.needs.set(.hunger, 0.1); a.profile?.needs.set(.thirst, 0.9); a.profile?.needs.set(.attention, 0.9) }
            care.eagerWhenFamished = false
        }
        func tick() {
            snapshot = actors.map { (pos: $0.floor, walking: $0.isWalking) }
            for a in actors {
                guard let b = a.brain else { continue }
                b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false)
                a.skinner.jelly.tick(brain: b, sim: a.sim, dt: a.sim.stepDt)
                if b.activity == .eating || b.activity == .drinking { sawEating[a.id] = true }
                if a.id == 0 { care.tick(brain: b, renderer: nil, dt: a.sim.stepDt, sim: a.sim) }
            }
            care.tickOthers(actors, dt: actors[0].sim.stepDt)
            JellyParallel.step(actors.map(\.sim))
            care.refreshHeld(actors: actors, renderer: nil)
            t += actors[0].sim.stepDt
        }
        func run(_ s: Float, until: (() -> Bool)? = nil) { for _ in 0..<Int(s * 60) { tick(); if let until, until() { break } } }
        func level(_ id: Int, _ k: NeedKind = .hunger) -> Float { care.needs(for: id).level(k) }
    }

    private func room(wander: Bool = false) -> Room { let r = Room(wander: wander); Self.keep.append(r.care); Self.keep.append(contentsOf: r.actors); return r }

    func testFeedPipRaisesPipsHungerOnly() {
        let r = room()
        r.run(1)
        let before = (0..<3).map { r.level($0) }
        r.care.feed(jelly: 1)
        XCTAssertEqual(r.care.diningJelly, 1)
        r.run(40) { r.t > 2 && !r.care.trayOut }
        XCTAssertFalse(r.care.trayOut, "the meal ended")
        XCTAssertTrue(r.sawEating[1], "Pip ate")
        XCTAssertFalse(r.sawEating[0] || r.sawEating[2], "nobody else ate")
        XCTAssertGreaterThan(r.level(1), before[1] + 2.5 * MealAppetite.gainPerPiece, "famished Pip: ~3 pieces paid, was \(before[1]) now \(r.level(1))")
        XCTAssertEqual(r.level(0), before[0], accuracy: 0.02, "Bob's hunger is unchanged")
        XCTAssertEqual(r.level(2), before[2], accuracy: 0.02, "Moss's hunger is unchanged")
        XCTAssertEqual(r.level(1, .thirst), 0.9, accuracy: 0.03)
    }

    func testPipDrinks() {
        let r = room()
        r.care.needs(for: 1).set(.thirst, 0.1)
        r.run(1)
        let before = (0..<3).map { r.level($0, .thirst) }
        r.care.drink(jelly: 1)
        r.run(40) { r.t > 2 && !r.care.trayOut }
        XCTAssertTrue(r.sawEating[1]); XCTAssertFalse(r.sawEating[0] || r.sawEating[2])
        XCTAssertGreaterThan(r.level(1, .thirst), before[1] + 2.5 * MealAppetite.gainPerPiece)
        XCTAssertEqual(r.level(0, .thirst), before[0], accuracy: 0.02)
        XCTAssertEqual(r.level(2, .thirst), before[2], accuracy: 0.02)
    }

    func testFullMossRefuses() {
        let r = room()
        r.care.needs(for: 2).set(.hunger, 1)
        r.run(1)
        r.care.feed(jelly: 2)
        var label: String?, head: SIMD3<Float>?
        r.run(40) {
            if r.care.notice != nil, label == nil { label = r.care.notice; head = r.care.noticeHeadWorld }
            return r.t > 2 && !r.care.trayOut
        }
        XCTAssertEqual(label, "Not hungry", "the refusal label comes up")
        let c = r.actors[2].sim.centroid()
        if let head { XCTAssertEqual(head.x, c.x, accuracy: 0.6, "the label sits over Moss, not Bob: \(head) vs \(c)") }
        XCTAssertEqual(r.level(2), 1, accuracy: 0.02, "Moss's hunger is unchanged")
        XCTAssertFalse(r.care.trayOut)
        XCTAssertEqual(r.level(0), 0.1, accuracy: 0.03)
    }

    func testOneMealAtATimeAndBadIdFeedsBob() {
        let r = room()
        r.care.feed(jelly: 1)
        r.care.feed(jelly: 2)                         // ignored: Pip's order is already running
        XCTAssertEqual(r.care.diningJelly, 1)
        r.run(60) { r.t > 2 && !r.care.trayOut }
        XCTAssertFalse(r.sawEating[2], "the ignored order did not run")
        r.care.feed(jelly: 9)                         // outside the roster: Bob
        XCTAssertEqual(r.care.diningJelly, 0)
    }

    func testOthersKeepOutOfTheEatersWay() {
        let r = room(wander: true)
        r.care.feed(jelly: 1)
        var closest = Float.infinity
        r.run(40) {
            let pip = r.actors[1].floor
            for j in [0, 2] { closest = min(closest, simd_distance(pip, r.actors[j].floor)) }
            return r.t > 2 && !r.care.trayOut
        }
        MotionLog.write("DINEJELLY closest approach to the eater \(closest)")
        XCTAssertGreaterThan(closest, 0.8 * BlobBrain().peerGap, "nobody path through the eater")
        XCTAssertTrue(r.sawEating[1])
    }

    func testIdleJellyAtTheStandStepsAsideAndPipEats() {
        let r = room()
        r.actors[2].brain?.requestNow(.goTo(SIMD2(0.5, 0.2)))          // Moss parks right by Pip's place
        r.run(8)
        r.care.feed(jelly: 1)
        let stand = (DiningSpot.preferred + DiningLayout.make(n: 1).places[0].rel)
        r.run(60) { r.t > 10 && !r.care.trayOut }
        XCTAssertTrue(r.sawEating[1], "Pip got to eat although Moss stood by his place")
        XCTAssertGreaterThan(simd_distance(r.actors[2].floor, stand), 1.3, "Moss made room")
    }

    // MARK: capture

    func testCapturePipEating() throws {
        guard let dir = ProcessInfo.processInfo.environment["DINE_JELLY_OUT"] else { throw XCTSkip("DINE_JELLY_OUT not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let r = room()
        r.care.needs(for: 0).set(.hunger, 0.8)
        r.actors[0].brain?.requestNow(.goTo(SIMD2(-1.6, 1.0)))          // Bob sits at the tray spot at the start: let him wander off to the side first
        r.run(6)
        r.care.feed(jelly: 1)
        var n = 0
        r.run(40) {
            n += 1
            if n % 120 == 0 { MotionLog.write("DINEJELLY t=\(r.t) Pip \(String(describing: r.actors[1].brain?.activity)) tray \(r.care.dining.isPresent) holding \(r.actors[1].brain?.dineHolding ?? false)") }
            return r.actors[1].brain?.activity == .eating && r.care.dining.isPresent && r.actors[1].brain?.dineHolding == true
        }
        MotionLog.write("DINEJELLY capture: tray present \(r.care.dining.isPresent), Pip \(String(describing: r.actors[1].brain?.activity)) at \(r.actors[1].floor), tray stand \(r.care.dining.places.first?.stand ?? .zero)")
        let W = 603, H = 1311
        guard let device = MTLCreateSystemDefaultDevice(),
              let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.actors[0].sim.edges, particleCount: r.actors[0].sim.n, game: true, bodyCount: 3),
              let room = ren.room else { throw XCTSkip("no Metal") }
        ren.resize(width: W, height: H)
        for a in r.actors.dropFirst() { if let p = JellyRoster.palette(a.id) { ren.setPalette(p, body: a.id) } }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        let light = GameCamera.light(centroid: r.actors[0].sim.centroid())
        if let f = r.care.dining.frame(theme: room.theme) { room.setDining(f) }
        for _ in 0..<2 {
            ren.beginFrame()
            for a in r.actors {
                a.skinner.update(x: a.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer(body: a.id))
                ren.setMouth(a.brain?.mouthOpen ?? 0, body: a.id)
            }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
        }
        var px = [UInt8](repeating: 0, count: W * H * 4)
        px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
        guard let base = LockImage(w: W, h: H, bgra: px).uiImage() else { return }
        let vp = cam.viewProj
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H)).image { _ in
            base.draw(at: .zero)
            let font = UIFont.boldSystemFont(ofSize: 34)
            for a in r.actors {
                let c = a.sim.centroid()
                let p = vp * SIMD4(c.x, c.y + BlobShape.H * 0.5 + 0.35, c.z, 1)
                let x = CGFloat((p.x / p.w * 0.5 + 0.5)) * CGFloat(W), y = CGFloat((1 - (p.y / p.w * 0.5 + 0.5))) * CGFloat(H)
                let t = a.id == 1 ? "Pip - eating" : a.name
                let s = t as NSString
                let sz = s.size(withAttributes: [.font: font])
                UIColor(white: 0, alpha: 0.55).setFill()
                UIBezierPath(roundedRect: CGRect(x: x - sz.width / 2 - 10, y: y - 8, width: sz.width + 20, height: sz.height + 16), cornerRadius: 14).fill()
                s.draw(at: CGPoint(x: x - sz.width / 2, y: y), withAttributes: [.font: font, .foregroundColor: UIColor.white])
            }
            let cap = "feed(jelly: 1): Pip eats at the tray; Bob and Moss stay in the room" as NSString
            cap.draw(in: CGRect(x: 20, y: H - 110, width: W - 40, height: 100), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.white])
        }
        try img.pngData()!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pip-eating.png"))
    }
}
