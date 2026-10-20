//
//  DecorCaptureTests.swift
//  Not a regression test: renders the store's decor with the REAL renderer (MelonRenderer, the game room, true proportion) when DECOR_CAP_DIR is set
//  (pass it as TEST_RUNNER_DECOR_CAP_DIR). Output: decor_sheet.png (every piece in the room, labelled), decor_interact.png (a Jelly sitting in the
//  beanbag, booping the plant, pushing the ball: mid-action frames), room_full.png (10 of 10 spots used, three Jellies, phone aspect).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class DecorCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0); DecorField.shared.clear() }
    override func tearDown() { DecorField.shared.clear(); DayClock.shared.forcedHour = 12; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

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

    /// One frame: bodies in `rigs` (none = hidden under the floor), the room and the decor, from `cam`.
    private func shot(_ ren: MelonRenderer, _ target: MTLTexture, rig: MotionRig, showBody: Bool, cam: CameraState, w: Int, h: Int, hour: Double? = nil) -> LockImage {
        let light = GameCamera.light(centroids: [rig.sim.centroid()])
        ren.dayHourOverride = hour
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
    private func save(_ img: UIImage, _ dir: String, _ name: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try img.pngData()?.write(to: URL(fileURLWithPath: dir + "/" + name))
    }

    private var dir: String? { ProcessInfo.processInfo.environment["DECOR_CAP_DIR"].flatMap { $0.isEmpty ? nil : $0 } }

    // MARK: the sheet

    func testCaptureDecorSheet() throws {
        guard let dir else { throw XCTSkip("DECOR_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.renderSamples = false
        let w = 400, h = 400
        let (ren, target) = try makeRenderer(device, rig, w: w, h: h)
        var cells: [(LockImage, String)] = []
        var items = StoreCatalog.items(.decor)
        items.sort { $0.price < $1.price }
        func place(_ k: DecorKind) { DecorField.shared.set([PlacedDecor(uid: 1, kind: k, x: 0.2, z: 0.4)]); decorMesh(into: ren) }
        for item in items {
            let k = item.decor!
            place(k)
            let c = SIMD3<Float>(0.2, 0, 0.4)
            let cam = camera(eye: c + SIMD3(1.5, 1.7, 3.5), at: c + SIMD3(0, 0.35, 0), aspect: Float(w) / Float(h), fov: 31 * .pi / 180)
            cells.append((shot(ren, target, rig: rig, showBody: false, cam: cam, w: w, h: h), "\(item.name)  \(item.price) Drops  \(item.roomUnits) spot\(item.roomUnits == 1 ? "" : "s")"))
        }
        // the night light after dark
        place(.nightlight)
        let c = SIMD3<Float>(0.2, 0, 0.4)
        let cam = camera(eye: c + SIMD3(1.5, 1.7, 3.5), at: c + SIMD3(0, 0.35, 0), aspect: Float(w) / Float(h), fov: 31 * .pi / 180)
        DayClock.shared.forcedHour = 23
        cells.append((shot(ren, target, rig: rig, showBody: false, cam: cam, w: w, h: h, hour: 23), "Night light at 23:00 (it glows)"))
        try save(sheet(cells, cols: 3, title: "Decor: real 3D meshes in the room (room capacity 10 spots; big pieces take 2)"), dir, "decor_sheet.png")
    }

    // MARK: interactions

    private func scene(_ kind: DecorKind, at p: SIMD2<Float>, start: IdleKind, from: SIMD2<Float>) -> MotionRig {
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
        XCTAssertTrue(r.brain.idleStart(start, r.sim))
        return r
    }
    private func step(_ r: MotionRig) { r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); DecorField.shared.tick(dt: r.sim.stepDt) }

    func testCaptureInteractions() throws {
        guard let dir else { throw XCTSkip("DECOR_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 480, h = 560
        var cells: [(LockImage, String)] = []

        func frame(_ r: MotionRig, _ label: String, focus: SIMD2<Float>, until cond: () -> Bool, extra: Int = 0) throws {
            let (ren, target) = try makeRenderer(device, r, w: w, h: h)
            var n = 0
            while !cond() && n < 60 * 60 { step(r); n += 1 }
            XCTAssertLessThan(n, 60 * 60, "\(label): the moment came")
            for _ in 0..<extra { step(r) }
            decorMesh(into: ren, time: 0.37)
            let c = r.sim.centroid()
            let mid = SIMD3<Float>((c.x + focus.x) / 2, 0.55, (c.z + focus.y) / 2)
            let cam = camera(eye: mid + SIMD3(1.6, 1.3, 4.6), at: mid, aspect: Float(w) / Float(h), fov: 33 * .pi / 180)
            cells.append((shot(ren, target, rig: r, showBody: true, cam: cam, w: w, h: h), label))
        }

        // sitting in the beanbag (he has sunk in: the bag dimples)
        let sit = scene(.beanbag, at: SIMD2(1.0, 0.7), start: .decorSit, from: SIMD2(-1.0, 1.4))
        try frame(sit, "Sitting in the beanbag (it sinks and dimples)", focus: SIMD2(1.0, 0.7), until: { (DecorField.shared.anim[7]?.sink ?? 0) > 0.9 }, extra: 20)
        // booping the plant (the leaves wiggle)
        let boop = scene(.plant, at: SIMD2(1.1, 0.5), start: .decorBoop, from: SIMD2(-1.0, 1.4))
        try frame(boop, "Booping the plant (leaves wiggle)", focus: SIMD2(1.1, 0.5), until: { boop.brain.idleState.decorBooped }, extra: 5)
        // pushing the ball (it rolls away from his belly)
        let kick = scene(.ball, at: SIMD2(0.3, 1.2), start: .decorKick, from: SIMD2(-1.4, 1.2))
        try frame(kick, "Pushing the ball (it rolls)", focus: SIMD2(0.9, 1.2), until: { kick.brain.idleState.decorKicked }, extra: 14)
        try save(sheet(cells, cols: 3, title: "Decor interactions: mid-action frames (arms stay stubby, feet stay under him)"), dir, "decor_interact.png")
    }

    // MARK: the Blender art captures

    /// decor_ingame.png: all eight pieces in the room from the game camera (phone aspect, true proportion).
    func testCaptureDecorInGame() throws {
        guard let dir else { throw XCTSkip("DECOR_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.renderSamples = false
        let W = 603, H = 1311
        let (ren, target) = try makeRenderer(device, rig, w: W, h: H)
        let spots: [(DecorKind, Float, Float)] = [(.beanbag, -3.0, -3.0), (.toybox, 3.0, -3.2), (.plant, -3.9, -1.0), (.nightlight, 3.8, -1.0),
                                                   (.cushion, -3.2, 1.6), (.ball, 3.3, 1.3), (.rug, 0.0, -2.6), (.bouncymat, 0.2, -0.1)]
        DecorField.shared.set(spots.enumerated().map { PlacedDecor(uid: $0.offset + 1, kind: $0.element.0, x: $0.element.1, z: $0.element.2) })
        decorMesh(into: ren)
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        let img = shot(ren, target, rig: rig, showBody: false, cam: cam, w: W, h: H)
        try save(sheet([(img, "all 8 decor pieces (Blender art) in the room: beanbag, toy box, plant, night light, cushion, ball, rug, bouncy mat")], cols: 1, title: "Decor in game"), dir, "decor_ingame.png")
    }

    /// decor_anims.png: plant wiggle, toy box open with the toys up, ball mid-roll, mat dip.
    func testCaptureDecorAnims() throws {
        guard let dir else { throw XCTSkip("DECOR_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.renderSamples = false
        let w = 420, h = 420
        let (ren, target) = try makeRenderer(device, rig, w: w, h: h)
        let f = DecorField.shared
        var cells: [(LockImage, String)] = []
        func cell(_ k: DecorKind, _ label: String, at p: SIMD2<Float> = SIMD2(0.2, 0.4), time: Float = 0.37, prep: () -> Void) {
            f.set([PlacedDecor(uid: 1, kind: k, x: p.x, z: p.y)])
            prep()
            decorMesh(into: ren, time: time)
            let c = f.anim[1].map { k == .ball ? SIMD3<Float>($0.pos.x, 0, $0.pos.y) : SIMD3(p.x, 0, p.y) } ?? SIMD3(p.x, 0, p.y)
            let cam = camera(eye: c + SIMD3(1.5, 1.7, 3.5), at: c + SIMD3(0, 0.4, 0), aspect: 1, fov: 33 * .pi / 180)
            cells.append((shot(ren, target, rig: rig, showBody: false, cam: cam, w: w, h: h), label))
        }
        cell(.plant, "plant boop: leaves wiggle", time: 0.3) { f.kick(1, 1); for _ in 0..<4 { f.tick(dt: 1.0 / 60) } }
        cell(.toybox, "toy box: peeked into, lid thrown back, toys up") { for _ in 0..<50 { f.peek(1, 1); f.tick(dt: 1.0 / 60) }; f.kick(1, 1); for _ in 0..<9 { f.peek(1, 1); f.tick(dt: 1.0 / 60) } }
        cell(.ball, "ball mid-roll (pattern turned)", at: SIMD2(-0.6, 0.4)) { f.kickBall(1, direction: SIMD2(1, 0.2), speed: 3.0); for _ in 0..<22 { f.tick(dt: 1.0 / 60) } }
        cell(.bouncymat, "bouncy mat: dip on a landing") { f.kick(1, 1); for _ in 0..<10 { f.tick(dt: 1.0 / 60) } }
        try save(sheet(cells, cols: 2, title: "Decor animations (Blender art)"), dir, "decor_anims.png")
    }

    // MARK: the full room

    func testCaptureFullRoom() throws { try fullRoom(sleeping: false) }
    func testCaptureFullRoomAsleep() throws { try fullRoom(sleeping: true) }
    /// Landscape (2868 x 1320 shot at half size) and a portrait phone: the same full room, for the landscape audit (room_full_land.png / room_full_port.png).
    func testCaptureFullRoomLandscape() throws { try fullRoom(sleeping: false, W: 1434, H: 660, name: "room_full_land.png") }
    func testCaptureFullRoomPortraitRef() throws { try fullRoom(sleeping: false, W: 603, H: 1311, name: "room_full_port.png") }

    func testCaptureBeanbagSit() throws {
        guard let dir else { throw XCTSkip("DECOR_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 600, h = 700
        let r = scene(.beanbag, at: SIMD2(1.0, 0.7), start: .decorSit, from: SIMD2(-1.0, 1.4))
        let (ren, target) = try makeRenderer(device, r, w: w, h: h)
        var n = 0
        while (DecorField.shared.anim[7]?.sink ?? 0) < 0.9 && n < 3600 { step(r); n += 1 }
        for _ in 0..<30 { step(r) }
        decorMesh(into: ren, time: 0.37)
        let c = r.sim.centroid()
        let mid = SIMD3<Float>(c.x, 0.5, c.z)
        let cam = camera(eye: mid + SIMD3(0.9, 1.5, 3.9), at: mid, aspect: Float(w) / Float(h), fov: 33 * .pi / 180)
        let img = shot(ren, target, rig: r, showBody: true, cam: cam, w: w, h: h)
        try save(sheet([(img, "Sitting INTO the beanbag: bag behind and around him, back raised, he leans back")], cols: 1, title: "Beanbag sit (feet attached, arms stubby)"), dir, "beanbag_sit.png")
    }

    /// beanbag_top.png: hop up, landed (the squish), settled on top, from the normal room camera (cropped, true scale), plus a close-up.
    func testCaptureBeanbagTop() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOOD_CAP_DIR"] ?? self.dir else { throw XCTSkip("no cap dir") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        let w = 1320, h = 2868, size = 900
        let bag = SIMD2<Float>(1.0, 0.7)
        let r = scene(.beanbag, at: bag, start: .decorSit, from: SIMD2(-1.0, 1.4))
        let (ren, target) = try makeRenderer(device, r, w: w, h: h)
        let cam = GameCamera.camera(aspect: Float(w) / Float(h))
        func cropShot(_ cam: CameraState) -> LockImage {
            decorMesh(into: ren, time: 0.37)
            let full = shot(ren, target, rig: r, showBody: true, cam: cam, w: w, h: h)
            let q = cam.viewProj * SIMD4(bag.x, 0.85, bag.y, 1)
            let cx = Int((q.x / q.w * 0.5 + 0.5) * Float(w)), cy = Int((1 - (q.y / q.w * 0.5 + 0.5)) * Float(h))
            let x0 = min(max(cx - size / 2, 0), w - size), y0 = min(max(cy - size / 2, 0), h - size)
            var px = [UInt8](repeating: 0, count: size * size * 4)
            for y in 0..<size { for x in 0..<size { for c in 0..<4 { px[(y * size + x) * 4 + c] = full.bgra[((y0 + y) * w + x0 + x) * 4 + c] } } }
            return LockImage(w: size, h: size, bgra: px)
        }
        var cells: [(LockImage, String)] = []
        var n = 0
        // hop up: the middle of the air phase of the hop on
        while !(r.brain.idleState.bagStage == 1 && r.brain.gait.phase == .air) && n < 3600 { step(r); n += 1 }
        for _ in 0..<9 { step(r) }
        cells.append((cropShot(cam), "1. hop up (in the air over the bag's edge)"))
        // landed: a few ticks after the floor became the bag's top (the squish is at its deepest)
        while !r.brain.bagFloorOn && n < 7200 { step(r); n += 1 }
        for _ in 0..<5 { step(r) }
        cells.append((cropShot(cam), "2. landed on top: the bag squishes"))
        // settled
        while !(r.brain.idleState.bagStage == 2 && r.brain.idleState.phaseT > 2.5) && n < 10800 { step(r); n += 1 }
        cells.append((cropShot(cam), "3. settled on top (idle)"))
        // close-up: the same camera, the feet and the bag's top, pixels doubled
        decorMesh(into: ren, time: 0.37)
        let img = shot(ren, target, rig: r, showBody: true, cam: cam, w: w, h: h)
        let q = cam.viewProj * SIMD4(bag.x, 0.75, bag.y, 1)
        let cx = Int((q.x / q.w * 0.5 + 0.5) * Float(w)), cy = Int((1 - (q.y / q.w * 0.5 + 0.5)) * Float(h))
        let half = size / 2, x0 = min(max(cx - half / 2, 0), w - half), y0 = min(max(cy - half / 2, 0), h - half)
        var px = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size { for x in 0..<size { for ch in 0..<4 { px[(y * size + x) * 4 + ch] = img.bgra[((y0 + y / 2) * w + x0 + x / 2) * 4 + ch] } } }
        cells.append((LockImage(w: size, h: size, bgra: px), "4. close-up (2x) of the feet on the bag's top"))
        try save(sheet(cells, cols: 2, title: "Beanbag: he hops on, lands on top, rests (room camera + close-up)"), dir, "beanbag_top.png")
    }

    /// beanbag_land.png: settled SITTING in the beanbag on a phone on its side (2.17 : 1), the full frame from the room camera.
    func testCaptureBeanbagSitLandscape() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOOD_CAP_DIR"] ?? self.dir else { throw XCTSkip("no cap dir") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 1)
        let w = 1434, h = 660
        _ = GameCamera.camera(aspect: Float(w) / Float(h))
        let bag = SIMD2<Float>(1.0, 0.7)
        let r = scene(.beanbag, at: bag, start: .decorSit, from: SIMD2(-1.0, 1.4))
        let (ren, target) = try makeRenderer(device, r, w: w, h: h)
        var n = 0
        while !(r.brain.idleState.bagStage == 2 && r.brain.idleState.phase == 2 && r.brain.idleState.phaseT > 2.0) && n < 10800 { step(r); n += 1 }
        decorMesh(into: ren, time: 0.37)
        let cam = GameCamera.camera(aspect: Float(w) / Float(h))
        let full = shot(ren, target, rig: r, showBody: true, cam: cam, w: w, h: h)
        let bar = 40
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: CGSize(width: w, height: h + bar), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + bar))
            ("Beanbag sit, landscape 2.17:1 (room camera, true proportion)" as NSString).draw(at: CGPoint(x: 10, y: 9), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 19), .foregroundColor: UIColor.white])
            full.uiImage()?.draw(in: CGRect(x: 0, y: bar, width: w, height: h))
        }
        try save(out, dir, "beanbag_land.png")
    }

    /// beanbag_sit_top.png: settled SITTING in the beanbag, from the room camera (front) and from a 3/4 angle.
    func testCaptureBeanbagSitTop() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOOD_CAP_DIR"] ?? self.dir else { throw XCTSkip("no cap dir") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        let w = 1320, h = 2868, size = 900
        let bag = SIMD2<Float>(1.0, 0.7)
        let r = scene(.beanbag, at: bag, start: .decorSit, from: SIMD2(-1.0, 1.4))
        let (ren, target) = try makeRenderer(device, r, w: w, h: h)
        var n = 0
        while !(r.brain.idleState.bagStage == 2 && r.brain.idleState.phase == 2 && r.brain.idleState.phaseT > 2.0) && n < 10800 { step(r); n += 1 }
        decorMesh(into: ren, time: 0.37)
        func crop(_ cam: CameraState, at p: SIMD3<Float>) -> LockImage {
            let full = shot(ren, target, rig: r, showBody: true, cam: cam, w: w, h: h)
            let q = cam.viewProj * SIMD4(p, 1)
            let cx = Int((q.x / q.w * 0.5 + 0.5) * Float(w)), cy = Int((1 - (q.y / q.w * 0.5 + 0.5)) * Float(h))
            let x0 = min(max(cx - size / 2, 0), w - size), y0 = min(max(cy - size / 2, 0), h - size)
            var px = [UInt8](repeating: 0, count: size * size * 4)
            for y in 0..<size { for x in 0..<size { for c in 0..<4 { px[(y * size + x) * 4 + c] = full.bgra[((y0 + y) * w + x0 + x) * 4 + c] } } }
            return LockImage(w: size, h: size, bgra: px)
        }
        let room = GameCamera.camera(aspect: Float(w) / Float(h))
        let mid = SIMD3<Float>(bag.x, 0.75, bag.y)
        let three = camera(eye: mid + simd_normalize(SIMD3<Float>(0.75, 0.3, 0.6)) * 11, at: mid, aspect: Float(w) / Float(h), fov: 36 * .pi / 180)
        let cells = [(crop(room, at: mid), "Sitting in the beanbag: room camera, front"), (crop(three, at: mid), "Sitting in the beanbag: 3/4 view")]
        try save(sheet(cells, cols: 2, title: "Beanbag SIT (seat hollow, lean back, feet over the front lip)"), dir, "beanbag_sit_top.png")
    }

    private func fullRoom(sleeping: Bool, W: Int = 603, H: Int = 1311, name: String? = nil) throws {
        guard let dir else { throw XCTSkip("DECOR_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: false)
        for k in DecorTests.fullMix { book.grant(k.storeID); _ = book.place(k.storeID) }
        // the ball too? (the mix is 10 spots: 2 beanbags, the mat, the toy box, the plant, the night light, a cushion)
        DecorField.shared.set(book.placedDecor)
        let lab = SocialTests.Lab(positions: [SIMD2(-1.0, 0.6), SIMD2(0.7, 0.9), SIMD2(0.0, 2.2)], quiet: false, seed: 5)
        SocialTests.keep.append(lab)
        for (i, r) in lab.rigs.enumerated() { r.skinner.autoBlink = false; AnticsLabTests.lively(r.brain); r.brain.idleMood = .happy; r.brain.idleState.cooldown = 3 + Float(i) * 2; r.brain.restTimer = 0.5 + Float(i) }
        if sleeping { for r in lab.rigs { r.brain.sleepEnabled = true; r.brain.commandedGoodnight = true } }
        let r0 = lab.rigs[0]
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r0.sim.edges, particleCount: r0.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        ren.roomCacheEnabled = false
        // run until someone is using a piece (or 90 s)
        var f = 0
        while f < 60 * 90 {
            if sleeping { if f > 60 * 12, lab.rigs.allSatisfy({ $0.brain.isSleeping && $0.brain.sleep.stage >= 3 }) { break } }
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            f += 1
            if !sleeping, f > 60 * 12, lab.rigs.contains(where: { r in r.brain.idleState.kind.map { BlobBrain.decorKinds.contains($0) && !r.brain.idleState.decorGo } ?? false }) { break }
        }
        for _ in 0..<45 { lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) } }
        decorMesh(into: ren)
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        func one(only: Int?) -> LockImage {
            let k = only ?? 0
            let light = GameCamera.light(centroids: lab.rigs.map { $0.sim.centroid() })
            ren.beginFrame()
            lab.rigs[k].skinner.update(x: lab.rigs[k].sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            if only == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = JellyRoster.palette(k) ?? PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            return LockImage(w: W, h: H, bgra: px)
        }
        _ = one(only: nil)
        let empty = one(only: nil)
        var out = empty
        for k in (0..<lab.rigs.count).sorted(by: { lab.rigs[$0].sim.centroid().z < lab.rigs[$1].sim.centroid().z }) {
            let b = one(only: k)
            for p in 0..<(W * H) {
                var d = 0
                for c in 0..<3 { d = max(d, abs(Int(b.bgra[4 * p + c]) - Int(empty.bgra[4 * p + c]))) }
                if d > 3 { for c in 0..<4 { out.bgra[4 * p + c] = b.bgra[4 * p + c] } }
            }
        }
        let doing = lab.rigs.map { $0.brain.idleState.kind.map { $0.rawValue } ?? "-" }.joined(separator: ", ")
        let bar: CGFloat = 40
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(W), height: CGFloat(H) + bar), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H) + bar))
            ("\(sleeping ? "FULL ROOM, all three asleep: " : "")Room full: \(book.roomUnitsUsed) of \(StoreTuning.roomCapacity) spots, three Jellies (doing: \(doing))" as NSString).draw(at: CGPoint(x: 10, y: 9), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 19), .foregroundColor: UIColor.white])
            out.uiImage()?.draw(in: CGRect(x: 0, y: bar, width: CGFloat(W), height: CGFloat(H)))
        }
        try save(img, dir, name ?? (sleeping ? "full_room_sleep.png" : "room_full.png"))
    }
}
