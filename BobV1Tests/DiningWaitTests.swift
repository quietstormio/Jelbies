//
//  DiningWaitTests.swift
//  A Jelly that is ready for the group meal waits where he stands (the `reserved` lock + wait pose) while the others walk in: autonomy ON, a lively
//  room (antics, sleep, watching, socials, zoomies urge). Nobody wanders off before the tray pops, nobody leaves his stand until done.
//  Capture: DINE_WAIT_OUT (three frames of the first arrival waiting).
//

import XCTest
import simd
import Metal
import UIKit
@testable import BobV1

@MainActor
final class DiningWaitTests: XCTestCase {
    override func tearDown() { IdleTuning.zoomUrge = 180...300; IdleTuning.zoomUrgeFirst = 70; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DecorField.shared.clear() }
    override func setUp() { DecorField.shared.clear(); RoomLayout.dynamicBoxes = [] }

    static func lively(_ r: DiningJellyTests.Room, seed: UInt64) {
        IdleTuning.zoomUrge = 5...10; IdleTuning.zoomUrgeFirst = 5
        for (i, a) in r.actors.enumerated() {
            guard let b = a.brain else { continue }
            b.autonomy = true; b.seed = seed &* 31 &+ UInt64(i) * 977
            b.sleepEnabled = true; b.anticsEnabled = true; b.watching = true
            b.idleMood = .happy; b.idleNight = 0; b.idleDeepNight = 0; b.idleMorning = 0
            b.zoomUrge = 5; b.restTimer = 0.2; b.idleState.cooldown = 0
            b.socialBook.cooldown = 0
        }
    }

    private func runMeal(seed: UInt64, drink: Bool, game: Bool = false) {
        if game { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0); GameCamera.refreshRoam(aspect: 440.0 / 956.0) } else { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        let kind: NeedKind = drink ? .thirst : .hunger
        for i in 0..<3 { r.care.needs(for: i).set(kind, 0.1) }
        r.run(1)
        // Jelly 2 is parked far away; the others are near the tray
        r.actors[2].brain?.requestNow(.goTo(SIMD2(-2.2, 3.4)))
        r.run(12) { r.actors[2].brain?.activity != .walking }
        Self.lively(r, seed: seed)
        if drink { r.care.drink() } else { r.care.feed() }
        XCTAssertTrue(r.care.groupActive)
        let g = r.care.group
        var arrivedAt: [Int: SIMD2<Float>] = [:]
        var drift: Float = 0
        var worstAtStand: Float = 0
        var started = false
        r.run(120) {
            if g.isActive { started = true }
            if g.isActive, g.state == .approaching, r.care.dining.phase == .absent {
                for i in 0..<3 {
                    let f = r.actors[i].floor
                    if arrivedAt[i] == nil, r.actors[i].brain?.activity != .walking, simd_distance(f, g.approachPoint(blob: i)) < 0.3 { arrivedAt[i] = f }
                    if let a = arrivedAt[i] { drift = max(drift, simd_distance(f, a)) }
                }
            }
            if g.isActive, g.state == .serving {
                for i in 0..<3 where r.actors[i].brain?.activity == .eating || r.actors[i].brain?.activity == .drinking {
                    worstAtStand = max(worstAtStand, simd_distance(r.actors[i].floor, r.care.dining.places[g.placeOf[i]].stand))
                }
            }
            return started && !g.isActive && r.t > 3
        }
        let tag = "seed \(seed) \(drink ? "drink" : "food")\(game ? " (game room)" : "")"
        if g.gaveUp { for i in 0..<3 { MotionLog.write("DINEWAIT gaveUp \(tag): jelly \(i) at \(r.actors[i].floor) approach \(g.approachPoint(blob: i)) act \(String(describing: r.actors[i].brain?.activity))") } }
        XCTAssertFalse(g.gaveUp, "the meal was never given up (\(tag))")
        XCTAssertEqual(g.walkRetries, [0, 0, 0], "no waiting Jelly had to be sent again (\(tag))")
        XCTAssertLessThan(drift, 0.3, "a ready Jelly stayed within 0.3 u of his spot until the tray popped (\(tag)): drifted \(drift)")
        XCTAssertLessThan(worstAtStand, 0.6, "eating Jellies stayed at their stand (\(tag)): \(worstAtStand)")
        XCTAssertTrue(r.sawEating.allSatisfy { $0 }, "all three ate (\(tag)) \(r.sawEating)")
        r.run(3)
        XCTAssertFalse(r.care.trayOut)
        MotionLog.write("DINEWAIT \(tag) drift \(drift) atStand \(worstAtStand)")
    }

    func testReadyJelliesWaitWhileTheLastOneWalksIn() {
        for seed in [11, 22, 33] as [UInt64] {
            runMeal(seed: seed, drink: false)
            runMeal(seed: seed, drink: true)
            runMeal(seed: seed, drink: false, game: true)
            runMeal(seed: seed, drink: true, game: true)
        }
    }

    func testSingleServingWaitsToo() {
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        r.care.needs(for: 1).set(.hunger, 0.1)
        r.actors[1].brain?.requestNow(.goTo(SIMD2(-2.2, 3.4)))
        r.run(12) { r.actors[1].brain?.activity != .walking }
        Self.lively(r, seed: 5)
        r.care.feed(jelly: 1)
        r.run(60) { r.t > 14 && !r.care.trayOut && r.care.wanted == nil }
        XCTAssertTrue(r.sawEating[1], "Pip ate")
        XCTAssertFalse(r.actors[1].brain?.reserved ?? true, "the lock is released after the meal")
    }

    /// DINE_WAIT_OUT: three frames of the first Jelly to arrive waiting in place (look / step / bounce) while the others walk in.
    func testCaptureMealWait() throws {
        guard let dir = ProcessInfo.processInfo.environment["DINE_WAIT_OUT"], !dir.isEmpty else { throw XCTSkip("DINE_WAIT_OUT not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let r = DiningJellyTests.Room(count: 3)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        for i in 0..<3 { r.care.needs(for: i).set(.hunger, 0.1) }
        r.run(1)
        r.actors[2].brain?.requestNow(.goTo(SIMD2(-2.2, 3.4)))
        r.actors[1].brain?.requestNow(.goTo(SIMD2(2.2, 2.4)))
        r.run(12) { r.actors[2].brain?.activity != .walking && r.actors[1].brain?.activity != .walking }
        Self.lively(r, seed: 11)
        r.care.feed()
        let g = r.care.group
        let W = 603, H = 1311
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.actors[0].sim.edges, particleCount: r.actors[0].sim.n, game: true, bodyCount: 3), let room = ren.room else { throw XCTSkip("no Metal") }
        ren.resize(width: W, height: H)
        for a in r.actors.dropFirst() { if let p = JellyRoster.palette(a.id) { ren.setPalette(p, body: a.id) } }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        func frame(_ label: String) -> UIImage? {
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
            guard let base = LockImage(w: W, h: H, bgra: px).uiImage() else { return nil }
            return UIGraphicsImageRenderer(size: CGSize(width: W, height: H)).image { _ in
                base.draw(at: .zero)
                for a in r.actors {
                    let c = a.sim.centroid(); let p = cam.viewProj * SIMD4(c.x, c.y + BlobShape.H * 0.5 + 0.35, c.z, 1)
                    let x = CGFloat(p.x / p.w * 0.5 + 0.5) * CGFloat(W), y = CGFloat(1 - (p.y / p.w * 0.5 + 0.5)) * CGFloat(H)
                    let ready = g.isActive && simd_distance(a.floor, g.approachPoint(blob: a.id)) < 0.5
                    let t = "\(a.name): \(ready ? "waiting" : "walking in")" as NSString
                    let font = UIFont.boldSystemFont(ofSize: 30), sz = t.size(withAttributes: [.font: font])
                    UIColor(white: 0, alpha: 0.55).setFill()
                    UIBezierPath(roundedRect: CGRect(x: x - sz.width / 2 - 8, y: y - 6, width: sz.width + 16, height: sz.height + 12), cornerRadius: 12).fill()
                    t.draw(at: CGPoint(x: x - sz.width / 2, y: y), withAttributes: [.font: font, .foregroundColor: UIColor.white])
                }
                (label as NSString).draw(in: CGRect(x: 16, y: H - 100, width: W - 32, height: 90), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.white])
            }
        }
        // the first Jelly that is ready (settled at his approach point) while another is still walking
        var first = -1, shots: [UIImage] = [], t0: Float = 0
        r.run(40) {
            if first < 0, g.isActive, g.state == .approaching {
                for a in r.actors where r.actors.contains(where: { $0.id != a.id && simd_distance($0.floor, g.approachPoint(blob: $0.id)) > 1.2 }) && a.brain?.activity != .walking && simd_distance(a.floor, g.approachPoint(blob: a.id)) < 0.3 { first = a.id; t0 = r.t }
            }
            return first >= 0
        }
        XCTAssertGreaterThanOrEqual(first, 0, "somebody was ready while another walked in")
        var due: [Float] = [0, 0.6, 1.2], k = 0
        let start = r.t
        r.run(30) {
            if k < due.count, r.t - start >= due[k] {
                if let img = frame(String(format: "meal wait: %@ waits at his spot, t = +%.1f s (the tray is not out yet: state %@)", r.actors[first].name, r.t - t0, "\(g.state)")) { shots.append(img) }
                k += 1
            }
            return k >= due.count
        }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        try UIGraphicsImageRenderer(size: CGSize(width: W * 3, height: H), format: fmt).image { _ in
            for (i, s) in shots.enumerated() { s.draw(at: CGPoint(x: i * W, y: 0)) }
        }.pngData()!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("meal_wait.png"))
    }
}
