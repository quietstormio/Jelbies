//
//  Toys4CaptureTests.swift
//  The fourth toy batch (2026-10-27): the stand-spot audit (every new kind has a valid stand wherever it can be placed), a play session per toy (the lever picks it,
//  the session finishes), and, when TOYS4_CAP_DIR is set (TEST_RUNNER_TOYS4_CAP_DIR), the contact sheet (toys4_sheet.png) and the in-room play frames
//  (toys4_play.png) rendered with the REAL renderer.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class Toys4CaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var dir: String? { ProcessInfo.processInfo.environment["TOYS4_CAP_DIR"].flatMap { $0.isEmpty ? nil : $0 } }
    static let log = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/toys4/"

    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0) }
    override func tearDown() { DecorField.shared.clear(); ToyTuning.settle = 5; DayClock.shared.forcedHour = 12; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    // MARK: audits

    func testNewToysAreRegistered() {
        XCTAssertEqual(DecorKind.batch4Toys.count, 6)
        for k in DecorKind.batch4Toys {
            XCTAssertEqual(k.category, .toys, "\(k)")
            XCTAssertNotNil(k.activeInteraction, "\(k) has a behaviour")
            XCTAssertNotNil(DecorMeshes.loaded[k], "\(k) art loads")
            XCTAssertTrue(StoreCatalog.items.contains { $0.id == k.storeID && $0.price >= 25 && $0.price <= 90 }, "\(k) is in the shop at 25...90")
            XCTAssertEqual(DecorKind(storeID: k.storeID), k)
            XCTAssertFalse(k.title.isEmpty); XCTAssertFalse(k.use.contains("Drops"), "JellyCoins wording")
        }
        XCTAssertTrue(DecorKind.beachball.rolls && DecorKind.beachball.isBallLike)
    }

    func testNewToysHaveAStandSpotWhereverTheyArePlaced() {
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.brain.anticsEnabled = true
        var report: [String] = []
        var controlMisses: [String] = []
        for k in [DecorKind.ball] + DecorKind.batch4Toys {
            guard let mv = k.activeInteraction else { XCTFail("\(k) none"); continue }
            var valid = 0, misses: [String] = []
            for q in 0..<4 { for xi in -3...3 { for zi in -3...3 {
                let at = SIMD2<Float>(Float(xi) * 1.2, Float(zi) * 1.2)
                guard DecorPlacement.isValid(k, at: at, among: [], ignoring: nil, quarter: q) else { continue }
                valid += 1
                DecorField.shared.set([PlacedDecor(uid: 7, kind: k, x: at.x, z: at.y, turns: q)])
                let f = DecorField.shared.foot(7)!
                rig.brain.px = -0.5; rig.brain.pz = 1.2
                if rig.brain.decorStand(mv, f, from: SIMD2(-0.5, 1.2)) == nil { misses.append("q\(q)@\(at.x),\(at.y)") }
            } } }
            report.append("\(k.rawValue): valid \(valid) misses \(misses.count) \(misses.prefix(30).joined(separator: " "))")
            XCTAssertGreaterThan(valid, 0, "\(k) can be placed")
            // (a rolling toy is kicked where it lies: the existing ball has no stand on the very front edge of the floor either, so the ball is the control)
            if k == .ball { controlMisses = misses; continue }
            if k == .beachball { XCTAssertEqual(misses, controlMisses, "the beach ball has the ball's stand spots"); continue }
            XCTAssertTrue(misses.isEmpty, "\(k) placements with no stand spot: \(misses.prefix(20))")
        }
        try? FileManager.default.createDirectory(atPath: Self.log, withIntermediateDirectories: true)
        try? report.joined(separator: "\n").write(toFile: Self.log + "toys4-stand.txt", atomically: true, encoding: .utf8)
    }

    /// The toy-choice lever: with one new toy out, a Jelly picks it, walks over, plays and finishes.
    func testEachNewToyIsPlayedWith() throws {
        var lines: [String] = []
        for k in DecorKind.batch4Toys {
            let mv = k.activeInteraction!
            DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
            let spot = SIMD2<Float>(k == .beachball ? 0.3 : 1.2, 0.6)
            DecorField.shared.set([PlacedDecor(uid: 7, kind: k, x: spot.x, z: spot.y)])
            let r = MotionRig(game: true)
            Self.keep.append(r)
            r.renderSamples = false
            r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: SIMD2(-1.4, 1.2))
            for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim)
            r.brain.idleForced = true
            XCTAssertTrue(r.brain.decorStart(mv, r.sim, only: k), "\(k): the lever starts it")
            var played = false, n = 0, ended = false
            while n < 60 * 40 {
                r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); DecorField.shared.tick(dt: r.sim.stepDt)
                if r.brain.idleState.decorBooped || r.brain.idleState.decorKicked { played = true }
                if played, r.brain.idleState.kind == nil { ended = true; break }
                n += 1
            }
            lines.append("\(k.rawValue) \(mv) played \(played) ended \(ended) after \(n) ticks")
            XCTAssertTrue(played, "\(k): he used it"); XCTAssertTrue(ended, "\(k): the session ended")
        }
        try? FileManager.default.createDirectory(atPath: Self.log, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(toFile: Self.log + "toys4-play.txt", atomically: true, encoding: .utf8)
    }

    // MARK: rendering helpers

    private func makeRenderer(_ device: MTLDevice, _ rig: MotionRig, w: Int, h: Int) throws -> (MelonRenderer, MTLTexture) {
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: rig.sim.edges, particleCount: rig.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: w, height: h)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        return (ren, device.makeTexture(descriptor: td)!)
    }
    private func camera(eye: SIMD3<Float>, at: SIMD3<Float>, aspect: Float, fov: Float = 32 * .pi / 180) -> CameraState {
        var c = CameraState()
        c.view = M4.lookAt(eye: eye, at: at, up: SIMD3(0, 1, 0))
        c.viewProj = M4.mul(M4.perspective(fovy: fov, aspect: aspect, near: 0.1, far: 60), c.view)
        c.invViewProj = M4.invert(c.viewProj)
        c.pos = eye; c.fwd = simd_normalize(at - eye)
        return c
    }
    private func decorMesh(into ren: MelonRenderer, time: Float = 0.4) {
        let f = DecorField.shared
        ren.room!.setDecorStatic(DecorModels.build(feet: f.feet, field: f, time: time))
    }
    private func shot(_ ren: MelonRenderer, _ target: MTLTexture, rig: MotionRig, showBody: Bool, cam: CameraState, w: Int, h: Int) -> LockImage {
        let light = GameCamera.light(centroids: [rig.sim.centroid()])
        for _ in 0..<2 {
            ren.beginFrame()
            rig.skinner.update(x: rig.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            if !showBody { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = JellyRoster.palette(0) ?? PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(w), Float(h)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
        }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
        return LockImage(w: w, h: h, bgra: px)
    }
    private func sheet(_ cells: [(LockImage, String)], cols: Int, title: String) -> UIImage {
        let cw = cells[0].0.w, ch = cells[0].0.h, bar = 36, head = 54
        let rows = (cells.count + cols - 1) / cols
        let W = cw * cols, H = head + rows * (ch + bar)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { _ in
            UIColor(white: 0.08, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: W, height: H))
            (title as NSString).draw(at: CGPoint(x: 12, y: 12), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.white])
            for (i, c) in cells.enumerated() {
                let x = (i % cols) * cw, y = head + (i / cols) * (ch + bar)
                (c.1 as NSString).draw(at: CGPoint(x: x + 10, y: y + 7), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 19), .foregroundColor: UIColor.white])
                c.0.uiImage()?.draw(in: CGRect(x: x, y: y + bar, width: cw, height: ch))
            }
        }
    }
    private func save(_ img: UIImage, _ name: String) throws {
        guard let dir else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try img.pngData()?.write(to: URL(fileURLWithPath: dir + "/" + name))
    }

    // MARK: the contact sheet

    func testCaptureToys4SheetV2() throws { try sheetFor([.plushdino, .kickscooter, .plushbear], name: "toys4_sheet_v2.png") }
    func testCaptureToys4Sheet() throws { try sheetFor(DecorKind.batch4Toys + [.rug, .bouncymat, .ball, .plushbear, .rockinghorse], name: "toys4_sheet.png", scaleRow: DecorKind.batch4Toys) }

    private func sheetFor(_ kinds: [DecorKind], name: String, scaleRow: [DecorKind]? = nil) throws {
        guard dir != nil else { throw XCTSkip("TOYS4_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.renderSamples = false
        let w = 400, h = 400
        let (ren, target) = try makeRenderer(device, rig, w: w, h: h)
        var cells: [(LockImage, String)] = []
        for k in kinds {
            DecorField.shared.set([PlacedDecor(uid: 1, kind: k, x: 0.2, z: 0.4)]); decorMesh(into: ren)
            let c = SIMD3<Float>(0.2, 0, 0.4)
            let cam = camera(eye: c + SIMD3(1.5, 1.7, 3.5), at: c + SIMD3(0, 0.35, 0), aspect: Float(w) / Float(h), fov: 31 * .pi / 180)
            let price = StoreCatalog.items.first { $0.id == k.storeID }?.price ?? 0
            cells.append((shot(ren, target, rig: rig, showBody: false, cam: cam, w: w, h: h), "\(k.title)  \(price) JellyCoins  \(k.spec.units) spot\(k.spec.units == 1 ? "" : "s")" + (DecorKind.batch4.contains(k) ? "  NEW" : "")))
        }
        // a Jelbie beside each new toy (true scale check): a second row of the new toys with the body shown next to them
        for k in (scaleRow ?? kinds) {
            DecorField.shared.set([PlacedDecor(uid: 1, kind: k, x: 0.2, z: 0.4)]); decorMesh(into: ren)
            rig.sim.teleport(toXZ: SIMD2(0.2 - k.spec.half.x - 0.9, 0.5)); for _ in 0..<90 { rig.sim.step() }
            rig.brain.currentPose(rig.sim)
            let c = SIMD3<Float>(-0.2, 0, 0.4)
            let cam = camera(eye: c + SIMD3(1.0, 1.5, 4.2), at: c + SIMD3(0, 0.5, 0), aspect: Float(w) / Float(h), fov: 36 * .pi / 180)
            cells.append((shot(ren, target, rig: rig, showBody: true, cam: cam, w: w, h: h), "\(k.title) next to a Jelbie (scale)"))
        }
        try save(sheet(cells, cols: 3, title: "Toys batch 4 (Blender art) in the room, real renderer, plus the polished rug and bouncy mat"), name)
    }

    // MARK: the play frames

    private func scene(_ kind: DecorKind, at p: SIMD2<Float>, start: IdleKind, from: SIMD2<Float>) -> MotionRig {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: p.x, z: p.y)])
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.skinner.autoBlink = false
        r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: from)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.decorStart(start, r.sim, only: kind), "\(kind) starts")
        return r
    }
    private func step(_ r: MotionRig) { r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); DecorField.shared.tick(dt: r.sim.stepDt) }

    func testCaptureToys4Play() throws {
        guard dir != nil else { throw XCTSkip("TOYS4_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 480, h = 480
        var cells: [(LockImage, String)] = []
        var report: [String] = []
        func frame(_ r: MotionRig, _ label: String, focus: SIMD2<Float>, until cond: () -> Bool, extra: Int = 0) throws {
            let (ren, target) = try makeRenderer(device, r, w: w, h: h)
            var n = 0
            while !cond() && n < 60 * 60 { step(r); n += 1 }
            XCTAssertLessThan(n, 60 * 60, "\(label): the moment came")
            for _ in 0..<extra { step(r) }
            decorMesh(into: ren, time: 0.37)
            let c = r.sim.centroid()
            let mid = SIMD3<Float>((c.x + focus.x) / 2 + 0.25, 0.6, (c.z + focus.y) / 2)
            let cam = camera(eye: mid + SIMD3(1.0, 1.4, 7.0), at: mid, aspect: Float(w) / Float(h), fov: 33 * .pi / 180)
            cells.append((shot(ren, target, rig: r, showBody: true, cam: cam, w: w, h: h), label))
            report.append("\(label): body \(String(format: "(%.2f, %.2f)", c.x, c.z)) toy \(String(format: "(%.2f, %.2f)", focus.x, focus.y))")
        }
        // beach ball: the kick, then the roll
        let bb = scene(.beachball, at: SIMD2(0.3, 1.2), start: .decorKick, from: SIMD2(-1.4, 1.2))
        try frame(bb, "Beach ball: the kick", focus: SIMD2(0.8, 1.2), until: { bb.brain.idleState.decorKicked }, extra: 6)
        try frame(bb, "Beach ball: rolling away", focus: SIMD2(1.4, 1.2), until: { false || (DecorField.shared.anim[7]?.moving == true && (DecorField.shared.anim[7]?.vel.x ?? 0) != 0 && bb.brain.idleState.kind != nil) }, extra: 22)
        // tunnel: leaning in to peek
        let tn = scene(.playtunnel, at: SIMD2(1.0, 0.3), start: .decorPeek, from: SIMD2(-1.2, 1.2))
        try frame(tn, "Play tunnel: peeking in", focus: SIMD2(1.0, 0.3), until: { tn.brain.idleState.decorBooped }, extra: 8)
        try frame(tn, "Play tunnel: the ripple", focus: SIMD2(1.0, 0.3), until: { tn.brain.idleState.decorBooped }, extra: 22)
        // ring stacker, rocket, dino, scooter: the boop and its aftermath
        for (kind, name, at) in [(DecorKind.ringstacker, "Ring stacker", SIMD2<Float>(1.1, 0.5)), (.toyrocket, "Toy rocket", SIMD2(1.0, 0.3)),
                                 (.plushdino, "Plush dino", SIMD2(1.1, 0.5)), (.kickscooter, "Kick scooter", SIMD2(1.0, 0.5))] {
            let r = scene(kind, at: at, start: .decorBoop, from: SIMD2(-1.2, 1.3))
            try frame(r, "\(name): the boop", focus: at, until: { r.brain.idleState.decorBooped }, extra: 5)
            try frame(r, "\(name): a moment later", focus: at, until: { r.brain.idleState.decorBooped }, extra: 14)
        }
        try save(sheet(cells, cols: 4, title: "Toys batch 4: a Jelbie playing with each (mid-action frames; arms stay stubby, feet stay under him)"), "toys4_play.png")
        try? report.joined(separator: "\n").write(toFile: Self.log + "toys4-play-frames.txt", atomically: true, encoding: .utf8)
    }
}
