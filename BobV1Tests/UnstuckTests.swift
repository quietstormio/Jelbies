//
//  UnstuckTests.swift
//  2026-10-27 "food cannot pop up where one is standing, they get stuck; ensure no getting stuck at all": the random food spot is never under a Jelbie,
//  every diner reaches his place and eats, and a long randomised session (toys, decor, repeated Feed / Drink) leaves nobody stuck or overlapping.
//

import XCTest
import simd
import Metal
import UIKit
@testable import BobV1

@MainActor
final class UnstuckTests: XCTestCase {
    private func room(count: Int = 3, wander: Bool = false) -> DiningJellyTests.Room {
        let r = DiningJellyTests.Room(count: count, wander: wander)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        return r
    }
    override func tearDown() { DecorField.shared.set([]) }

    /// Sends everyone to the given spots and waits for them to stand there.
    private func stand(_ r: DiningJellyTests.Room, at spots: [SIMD2<Float>]) {
        for (i, s) in spots.enumerated() where i < r.actors.count { r.actors[i].brain?.requestNow(.goTo(s)) }
        r.run(14) { zip(r.actors, spots).allSatisfy { simd_distance($0.floor, $1) < 0.25 } && r.actors.allSatisfy { !$0.isWalking } }
    }

    // MARK: spot choice

    func testChooseNeverPicksASpotUnderAJelbie() {
        let L3 = DiningLayout.make(n: 3), L1 = DiningLayout.make(n: 1)
        // is there any on-screen, decor-free spot a body-width from every Jelbie? (the oracle for "the pick must be one")
        func exists(_ L: TrayLayout, _ js: [SIMD2<Float>]) -> Bool {
            var x: Float = -1.6
            while x <= 1.6001 {
                var z: Float = 0.6
                while z <= DiningSpot.maxZ + 1e-4 {
                    let o = SIMD2<Float>(x, z)
                    if DiningSpot.isClear(origin: o, layout: L, of: SIMD2(99, 99), aspect: GameCamera.aspect), FreeFloor.isFree(o, radius: 0.9),
                       L.places.allSatisfy({ FreeFloor.isFree(o + $0.rel, radius: 0.7) }), DiningSpot.minJellyDistance(o, layout: L, jellies: js) >= DiningSpot.jellyClear { return true }
                    z += 0.2
                }
                x += 0.2
            }
            return false
        }
        var rng = SystemRandomNumberGenerator()
        for L in [L1, L3] {
            for _ in 0..<60 {
                let js = (0..<3).map { _ in SIMD2<Float>(Float.random(in: -1.6...1.6, using: &rng), Float.random(in: 0.2...2.4, using: &rng)) }
                let o = DiningSpot.choose(bob: SIMD2(99, 99), layout: L, jellies: js)
                if exists(L, js) { XCTAssertGreaterThanOrEqual(DiningSpot.minJellyDistance(o, layout: L, jellies: js), DiningSpot.jellyClear - 1e-4, "a free spot existed, tray at \(o) for \(js)") }
            }
        }
        // three standing on the usual spot and beside it: the tray goes elsewhere, never on top of anybody
        for _ in 0..<40 {
            let js: [SIMD2<Float>] = [SIMD2(0, 1.3), SIMD2(-1.0, 1.4), SIMD2(1.0, 1.4)]
            let o = DiningSpot.choose(bob: SIMD2(99, 99), layout: L3, jellies: js)
            XCTAssertGreaterThanOrEqual(DiningSpot.minJellyDistance(o, layout: L3, jellies: js), 0.3, "tray at \(o)")
            let o1 = DiningSpot.choose(bob: SIMD2(99, 99), layout: L1, jellies: js)
            XCTAssertGreaterThanOrEqual(DiningSpot.minJellyDistance(o1, layout: L1, jellies: js), DiningSpot.jellyClear - 1e-4, "single tray at \(o1)")
        }
    }

    // MARK: food appears while they stand there

    private func watchMeal(_ r: DiningJellyTests.Room, seconds: Float, label: String) {
        var spawnChecked = false
        var sawPhase = false
        r.run(seconds) {
            if r.care.dining.phase == .popping, !spawnChecked {
                spawnChecked = true
                let o = r.care.dining.origin
                for a in r.actors {
                    XCTAssertGreaterThanOrEqual(DiningSpot.distance(from: a.floor, origin: o, layout: r.care.dining.layout), 0.3, "\(label): the tray popped in under Jelly \(a.id)")
                }
            }
            if r.care.dining.phase != .absent { sawPhase = true }
            return sawPhase && r.t > 3 && !r.care.trayOut && !r.care.groupActive && r.care.wanted == nil && r.care.meal == nil
        }
        XCTAssertTrue(spawnChecked, "\(label): the tray appeared")
        XCTAssertFalse(r.care.trayOut, "\(label): the meal finished")
        XCTAssertGreaterThan(r.minPair, 0.45, "\(label): no two bodies inside each other (closest \(r.minPair))")
        XCTAssertLessThan(r.maxStall, 2.0, "\(label): nobody stood stuck on a walk for 2 s (\(r.maxStall))")
    }

    func testGroupFoodWithEveryoneStandingAtTheUsualSpot() {
        for round in 0..<3 {
            let r = room()
            for i in 0..<3 { r.care.needs(for: i).set(.hunger, 0.1) }
            r.run(1)
            stand(r, at: [SIMD2(0, 1.3), SIMD2(-1.05, 1.5), SIMD2(1.05, 1.5)])
            r.care.feed()
            watchMeal(r, seconds: 90, label: "group food round \(round)")
            XCTAssertTrue(r.sawEating.allSatisfy { $0 }, "round \(round): all three ate \(r.sawEating)")
            for i in 0..<3 { XCTAssertGreaterThanOrEqual(r.level(i, .hunger), 0.85, "round \(round): Jelly \(i) is full") }
        }
    }

    func testGroupDrinkWithEveryoneStandingAtTheUsualSpot() {
        let r = room()
        for i in 0..<3 { r.care.needs(for: i).set(.thirst, 0.1) }
        r.run(1)
        stand(r, at: [SIMD2(0, 1.3), SIMD2(-1.05, 1.5), SIMD2(1.05, 1.5)])
        r.care.drink()
        watchMeal(r, seconds: 90, label: "group drink")
        XCTAssertTrue(r.sawEating.allSatisfy { $0 })
    }

    func testSingleFoodInACrowdedRoomOfFour() {
        let r = room(count: 4)
        r.care.needs(for: 1).set(.hunger, 0.1)
        r.run(1)
        stand(r, at: [SIMD2(0, 1.3), SIMD2(-1.2, 1.4), SIMD2(1.2, 1.4), SIMD2(-0.6, 0.4)])
        r.care.feed(jelly: 1)
        watchMeal(r, seconds: 90, label: "crowded room of four")
        XCTAssertTrue(r.sawEating[1], "Jelly 1 ate")
    }

    // MARK: stress

    /// A randomised 4-minute session: wandering Jelbies in a full room, Feed / Drink asked again and again.
    func testRandomisedSessionLeavesNobodyStuckOrOverlapping() {
        var rng = SystemRandomNumberGenerator()
        let r = room(wander: true)
        for k in DecorTuning.fullRoom { r.care.store.grant(k.storeID); _ = r.care.store.place(k.storeID) }
        r.care.syncDecor()
        r.run(1)
        var worstOverlapFor: Float = 0, overlapFor: Float = 0, worstStall: Float = 0
        var nextAsk: Float = 8
        let total: Float = 240
        while r.t < total {
            if r.t >= nextAsk {
                nextAsk = r.t + Float.random(in: 12...30, using: &rng)
                for i in 0..<3 { r.care.needs(for: i).set(Bool.random(using: &rng) ? .hunger : .thirst, Float.random(in: 0.05...0.5, using: &rng)) }
                switch Int.random(in: 0..<4, using: &rng) {
                case 0: r.care.feed()
                case 1: r.care.drink()
                case 2: r.care.feed(jelly: Int.random(in: 0..<3, using: &rng))
                default: r.care.drink(jelly: Int.random(in: 0..<3, using: &rng))
                }
            }
            for _ in 0..<30 {
                r.tick()
                var over = false
                for i in 0..<3 { for j in (i + 1)..<3 where !(r.actors[i].brain!.isSocial) && simd_distance(r.actors[i].floor, r.actors[j].floor) < 0.45 { over = true } }
                overlapFor = over ? overlapFor + r.actors[0].sim.stepDt : 0
                worstOverlapFor = max(worstOverlapFor, overlapFor)
                for a in r.actors { if let b = a.brain, b.tryingToMove {
                    if b.steerStall > 3.0, worstStall <= 3.0 { MotionLog.write("UNSTUCK stall>3 t=\(r.t) jelly \(a.id) at \(b.position) act \(b.activity) job \(String(describing: b.job)) script \(b.script) route \(b.route) commanded \(b.commanded) peers \(r.actors.map { $0.floor }) tray \(r.care.dining.phase) at \(r.care.dining.origin) stands \(r.care.dining.places.map(\.stand)) members \(r.care.group.memberIDs) others \(r.actors.map { "\($0.id):\($0.brain!.activity),\(String(describing: $0.brain!.job)),res=\($0.brain!.reserved),stall=\($0.brain!.steerStall)" }) wanted \(r.care.wanted != nil) group \(r.care.group.isActive)") }
                    worstStall = max(worstStall, b.steerStall) } }
            }
        }
        MotionLog.write("UNSTUCK stress: worst overlap \(worstOverlapFor)s, worst stall \(worstStall)s, pushes \(r.watchdog.pushes) replans \(r.watchdog.replans) giveUps \(r.watchdog.giveUps)")
        XCTAssertLessThan(worstOverlapFor, 1.0, "no overlap persists")
        XCTAssertLessThan(worstStall, 4.0, "nobody was stuck on a walk for 4 s (\(worstStall))")
    }

    // MARK: watchdog unit

    func testWatchdogNudgesTwoOverlappingBodiesApartWithoutTeleporting() {
        let r = room(count: 2)
        r.run(1)
        // squeeze Jelly 1 onto Jelly 0 through the brain's own spot
        let a = r.actors[0].brain!, b = r.actors[1].brain!
        b.requestNow(.goTo(a.position + SIMD2(0.2, 0))); r.run(1)
        let before = simd_distance(r.actors[0].floor, r.actors[1].floor)
        r.run(6)
        let after = simd_distance(r.actors[0].floor, r.actors[1].floor)
        XCTAssertGreaterThanOrEqual(after, min(before, 0.8) - 0.05, "not pressed closer: \(before) -> \(after)")
        XCTAssertGreaterThan(r.minPair, 0.3)
    }
    // MARK: capture (UNSTUCK_OUT = directory)

    func testCaptureCrowdedGroupMeal() throws {
        guard let dir = ProcessInfo.processInfo.environment["UNSTUCK_OUT"] else { throw XCTSkip("UNSTUCK_OUT not set") }
        let r = room()
        for i in 0..<3 { r.care.needs(for: i).set(.hunger, 0.1) }
        r.run(1)
        stand(r, at: [SIMD2(0, 1.3), SIMD2(-1.05, 1.5), SIMD2(1.05, 1.5)])
        let W = 603, H = 1311
        guard let device = MTLCreateSystemDefaultDevice(),
              let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.actors[0].sim.edges, particleCount: r.actors[0].sim.n, game: true, bodyCount: 3),
              let room = ren.room else { throw XCTSkip("no Metal") }
        ren.resize(width: W, height: H)
        for a in r.actors.dropFirst() { if let p = JellyRoster.palette(a.id) { ren.setPalette(p, body: a.id) } }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot(_ name: String, _ caption: String) throws {
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
            let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H)).image { _ in
                base.draw(at: .zero)
                (caption as NSString).draw(in: CGRect(x: 20, y: H - 110, width: W - 40, height: 100), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.white])
            }
            try img.pngData()!.write(to: URL(fileURLWithPath: dir + "/" + name))
        }
        try shot("unstuck_1_before.png", "three Jelbies stand where the food usually lands")
        r.care.feed()
        r.run(0.3)
        try shot("unstuck_2_food_pops.png", "feed(): the plate pops in on free floor, not under anybody")
        r.run(2.0)
        try shot("unstuck_3_walking.png", "each walks to his own spot")
        r.run(40) { r.actors.filter { $0.brain?.activity == .eating }.count == 3 && r.care.dining.bitesLeft.allSatisfy { $0 <= 2 } }
        try shot("unstuck_4_eating.png", "all three eating, nobody inside anybody")
        MotionLog.write("UNSTUCK capture: closest pair \(r.minPair), longest stall \(r.maxStall)")
    }
}
