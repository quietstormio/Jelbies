//
//  FurnCaptureTests.swift
//  Not a regression test: renders the second batch of furniture and toys with the REAL renderer when FURN_CAP_DIR is set
//  (pass it as TEST_RUNNER_FURN_CAP_DIR): furniture_ingame.png, toys_ingame.png, uses_1.png, football.png, room_full_land.png.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class FurnCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var dir: String? { ProcessInfo.processInfo.environment["FURN_CAP_DIR"].flatMap { $0.isEmpty ? nil : $0 } }

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0); DecorField.shared.clear() }
    override func tearDown() { DecorField.shared.clear(); DayClock.shared.forcedHour = 12; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    func makeRenderer(_ device: MTLDevice, _ rig: MotionRig, w: Int, h: Int) throws -> (MelonRenderer, MTLTexture) {
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: rig.sim.edges, particleCount: rig.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: w, height: h)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        return (ren, device.makeTexture(descriptor: td)!)
    }
    func camera(eye: SIMD3<Float>, at: SIMD3<Float>, aspect: Float, fov: Float = 32 * .pi / 180) -> CameraState {
        var c = CameraState()
        c.view = M4.lookAt(eye: eye, at: at, up: SIMD3(0, 1, 0))
        c.viewProj = M4.mul(M4.perspective(fovy: fov, aspect: aspect, near: 0.1, far: 60), c.view)
        c.invViewProj = M4.invert(c.viewProj)
        c.pos = eye; c.fwd = simd_normalize(at - eye)
        return c
    }
    func decorMesh(into ren: MelonRenderer, time: Float = 0.4) {
        let f = DecorField.shared
        ren.room!.setDecorStatic(DecorModels.build(feet: f.feet, field: f, time: time))
    }
    /// Draws the room and every `rigs` body (each in its own colour, composited by depth order).
    func shot(_ ren: MelonRenderer, _ target: MTLTexture, rigs: [MotionRig], cam: CameraState, w: Int, h: Int, hour: Double? = nil) -> LockImage {
        func one(_ k: Int?) -> LockImage {
            let rig = rigs[k ?? 0]
            let light = GameCamera.light(centroids: rigs.map { $0.sim.centroid() })
            ren.dayHourOverride = hour
            for _ in 0..<2 {
                ren.beginFrame()
                rig.skinner.update(x: rig.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
                if k == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0
                let pal = JellyRoster.palette(k ?? 0) ?? PaletteKey.blue.palette
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
        let empty = one(nil)
        var out = empty
        for k in (0..<rigs.count).sorted(by: { rigs[$0].sim.centroid().z < rigs[$1].sim.centroid().z }) {
            let b = one(k)
            for p in 0..<(w * h) {
                var d = 0
                for c in 0..<3 { d = max(d, abs(Int(b.bgra[4 * p + c]) - Int(empty.bgra[4 * p + c]))) }
                if d > 3 { for c in 0..<4 { out.bgra[4 * p + c] = b.bgra[4 * p + c] } }
            }
        }
        return out
    }
    func sheet(_ cells: [(LockImage, String)], cols: Int, title: String) -> UIImage {
        let cw = cells.map { $0.0.w }.max()!, ch = cells.map { $0.0.h }.max()!, bar = 36, head = 54
        let rows = (cells.count + cols - 1) / cols
        let W = cw * cols, H = head + rows * (ch + bar)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { _ in
            UIColor(white: 0.08, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: W, height: H))
            (title as NSString).draw(at: CGPoint(x: 12, y: 12), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.white])
            for (i, c) in cells.enumerated() {
                let x = (i % cols) * cw, y = head + (i / cols) * (ch + bar)
                (c.1 as NSString).draw(at: CGPoint(x: x + 10, y: y + 7), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 19), .foregroundColor: UIColor.white])
                c.0.uiImage()?.draw(in: CGRect(x: x, y: y + bar, width: c.0.w, height: c.0.h))
            }
        }
    }
    func save(_ img: UIImage, _ name: String) throws {
        guard let dir else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try img.pngData()?.write(to: URL(fileURLWithPath: dir + "/" + name))
    }

    /// Lays the pieces out with the placement rules (capacity ignored: this is a catalogue of the art), biggest first.
    static func layout(_ kinds: [DecorKind]) -> [PlacedDecor] {
        var placed: [PlacedDecor] = []
        for k in kinds.sorted(by: { $0.spec.half.x * $0.spec.half.y > $1.spec.half.x * $1.spec.half.y }) {
            if let p = DecorPlacement.findSpot(k, among: placed) { placed.append(PlacedDecor(uid: placed.count + 1, kind: k, x: p.x, z: p.y)) }
        }
        return placed
    }

    func catalogue(_ kinds: [DecorKind], file: String, title: String) throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.renderSamples = false
        var cells: [(LockImage, String)] = []
        for (label, W, H, a) in [("portrait", 603, 1311, Float(603.0 / 1311.0)), ("landscape", 1434, 660, Float(1434.0 / 660.0))] {
            GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: a); GameCamera.refreshRoam(aspect: a)
            let placed = Self.layout(kinds)
            DecorField.shared.set(placed)
            let (ren, target) = try makeRenderer(device, rig, w: W, h: H)
            decorMesh(into: ren)
            let cam = GameCamera.camera(aspect: a, focus: 0)
            let names = placed.map { $0.kind.title }.joined(separator: ", ")
            let missing = kinds.filter { k in !placed.contains { $0.kind == k } }.map { $0.title }
            cells.append((shot(ren, target, rigs: [rig], cam: cam, w: W, h: H), "\(label) game camera: \(names)\(missing.isEmpty ? "" : "  (no room for: \(missing.joined(separator: ", ")))")"))
        }
        if kinds.contains(.floorlamp) {          // the lamp's shade uses the lamp material: it glows with the night
            let a = Float(1434.0 / 660.0)
            GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: a); GameCamera.refreshRoam(aspect: a)
            DecorField.shared.set(Self.layout(kinds))
            let (ren, target) = try makeRenderer(device, rig, w: 1434, h: 660)
            decorMesh(into: ren)
            DayClock.shared.forcedHour = 23
            cells.append((shot(ren, target, rigs: [rig], cam: GameCamera.camera(aspect: a, focus: 0), w: 1434, h: 660, hour: 23), "landscape game camera at 23:00: the floor lamp's shade glows (lamp material)"))
        }
        try save(sheet(cells, cols: 1, title: title), file)
    }

    func testCaptureFurnitureInGame() throws {
        try catalogue(DecorKind.batch2.filter { $0.category == .furniture }, file: "furniture_ingame.png", title: "Furniture (Blender art) in the room, game camera, true proportion")
    }
    func testCaptureToysInGame() throws {
        try catalogue(DecorKind.batch2.filter { $0.category == .toys }, file: "toys_ingame.png", title: "Toys (Blender art) in the room, game camera, true proportion")
    }

    // MARK: scenes with Jellies

    func scene(_ kind: DecorKind, at p: SIMD2<Float>, start: IdleKind, from: SIMD2<Float>, fate: Int? = nil) -> MotionRig {
        DecorField.shared.clear()
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
        r.brain.throwFateForce = fate
        r.brain.idleForced = true
        if start == .sleep { XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 600 } else { XCTAssertTrue(r.brain.idleStart(start, r.sim)) }
        return r
    }
    func step(_ r: MotionRig) { r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); DecorField.shared.tick(dt: 1.0 / 60) }
    func stepLab(_ lab: SocialTests.Lab) {
        lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
        for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
    }
    /// A close-up of whatever is happening round `focus`: the room camera's tilt, true proportion (the same field of view for every cell).
    func closeUp(_ ren: MelonRenderer, _ target: MTLTexture, rigs: [MotionRig], focus: SIMD3<Float>, dist: Float = 4.6, w: Int, h: Int, hour: Double? = nil) -> LockImage {
        decorMesh(into: ren, time: 0.37)
        let cam = camera(eye: focus + SIMD3(1.6, 1.3, dist), at: focus, aspect: Float(w) / Float(h), fov: 33 * .pi / 180)
        return shot(ren, target, rigs: rigs, cam: cam, w: w, h: h, hour: hour)
    }

    func testCaptureUses1() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 560, h = 600
        var cells: [(LockImage, String)] = []
        // 1. the rocking chair, mid-rock
        do {
            let c = SIMD2<Float>(1.0, 0.7)
            let r = scene(.rockingchair, at: c, start: .decorSit, from: SIMD2(-1.0, 1.4))
            let (ren, t) = try makeRenderer(device, r, w: w, h: h)
            var n = 0
            while !(r.brain.idleState.bagStage == 2 && r.brain.idleState.phase == 2 && r.brain.idleState.phaseT > 2.0 && abs(DecorModels.rockAngle(DecorField.shared.anim[7]!)) > 0.09) && n < 7200 { step(r); n += 1 }
            let ang = DecorModels.rockAngle(DecorField.shared.anim[7]!)
            cells.append((closeUp(ren, t, rigs: [r], focus: SIMD3(c.x, 0.7, c.y), w: w, h: h), String(format: "Rocking chair mid-rock (%.2f of 0.14 rad)", ang)))
        }
        // 2. the swing with two Jellies
        do {
            DecorField.shared.set([PlacedDecor(uid: 7, kind: .swing, x: 0.0, z: -1.0)])
            let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.4, 1.6), SIMD2(1.4, 1.6)], quiet: true, seed: 7)
            for r in lab.rigs { r.skinner.autoBlink = false; r.brain.idleForced = true }
            XCTAssertTrue(lab.rigs[0].brain.idleStart(.decorSit, lab.rigs[0].sim)); XCTAssertTrue(lab.rigs[1].brain.idleStart(.decorSit, lab.rigs[1].sim))
            let (ren, t) = try makeRenderer(device, lab.rigs[0], w: w, h: h)
            var n = 0
            func seated(_ r: MotionRig) -> Bool { r.brain.idleState.bagStage == 2 && r.brain.idleState.phase == 2 && r.brain.idleState.phaseT > 2.5 }
            while !(seated(lab.rigs[0]) && seated(lab.rigs[1]) && abs(DecorModels.swingAngle(DecorField.shared.anim[7]!)) > 0.12) && n < 9000 { stepLab(lab); n += 1 }
            XCTAssertLessThan(n, 9000)
            let ang = DecorModels.swingAngle(DecorField.shared.anim[7]!)
            cells.append((closeUp(ren, t, rigs: lab.rigs, focus: SIMD3(0, 0.9, -1.0), dist: 6.4, w: w, h: h), String(format: "Swing for two (%.2f of 0.22 rad)", ang)))
        }
        // 3. the loveseat cuddle
        do {
            DecorField.shared.set([PlacedDecor(uid: 7, kind: .loveseat, x: 0.0, z: -0.8)])
            let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.6, 1.4), SIMD2(1.6, 1.9)], quiet: true, seed: 5)
            for r in lab.rigs { r.skinner.autoBlink = false }
            XCTAssertTrue(lab.rigs[0].brain.socialStart(.cuddle, with: lab.rigs[1].brain, lab.rigs[0].sim))
            let (ren, t) = try makeRenderer(device, lab.rigs[0], w: w, h: h)
            var n = 0
            while !(lab.rigs[0].brain.idleState.cuddle > 0.95 && lab.rigs[1].brain.idleState.cuddle > 0.95) && n < 12000 { stepLab(lab); n += 1 }
            XCTAssertLessThan(n, 12000)
            cells.append((closeUp(ren, t, rigs: lab.rigs, focus: SIMD3(0, 0.7, -0.8), dist: 5.4, w: w, h: h), "Loveseat cuddle: leaning together"))
        }
        // 4. the pet bed sleeper
        do {
            let c = SIMD2<Float>(1.0, 0.4)
            let r = scene(.petbed, at: c, start: .sleep, from: SIMD2(-1.0, 1.4))
            let (ren, t) = try makeRenderer(device, r, w: w, h: h)
            var n = 0
            while !(r.brain.isNapping && r.brain.sleep.t > 1.5) && n < 9000 { step(r); n += 1 }
            cells.append((closeUp(ren, t, rigs: [r], focus: SIMD3(c.x, 0.4, c.y), dist: 4.8, w: w, h: h), "Pet bed: curled up asleep on his back"))
        }
        // 5. the slide: climb, top, mid-slide
        do {
            let c = SIMD2<Float>(1.4, 0.3)
            let r = scene(.slide, at: c, start: .decorSlide, from: SIMD2(-1.0, 1.0))
            let (ren, t) = try makeRenderer(device, r, w: w, h: h)
            var n = 0
            let f = SIMD3<Float>(c.x, 0.6, c.y)
            while !(r.brain.idleState.slideStage == 1 && r.brain.idleState.slideStep == 1 && r.brain.gait.phase == .air) && n < 9000 { step(r); n += 1 }
            for _ in 0..<6 { step(r) }
            cells.append((closeUp(ren, t, rigs: [r], focus: f, dist: 6.0, w: w, h: h), "Slide 1: climbing (hop up the steps)"))
            while !(r.brain.idleState.slideStage == 4 && r.brain.idleState.phase == 2) && n < 18000 { step(r); n += 1 }
            for _ in 0..<20 { step(r) }
            cells.append((closeUp(ren, t, rigs: [r], focus: f, dist: 6.0, w: w, h: h), "Slide 2: sitting on the platform"))
            while !(r.brain.idleState.slideStage == 5 && r.brain.idleState.slideS > 1.4) && n < 27000 { step(r); n += 1 }
            cells.append((closeUp(ren, t, rigs: [r], focus: f, dist: 6.0, w: w, h: h), "Slide 3: mid-slide"))
        }
        try save(sheet(cells, cols: 3, title: "Furniture uses (arms stay stubby, feet stay under him)"), "uses_1.png")
    }

    func testCaptureFootball() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 520, h = 560
        var cells: [(LockImage, String)] = []
        let c = SIMD2<Float>(0.9, 0.9)
        func shotAt(_ r: MotionRig, _ ren: MelonRenderer, _ t: MTLTexture, _ label: String) {
            let p = r.sim.centroid()
            cells.append((closeUp(ren, t, rigs: [r], focus: SIMD3(p.x, 0.55, p.z), dist: 3.6, w: w, h: h), label))
        }
        // a plain throw: hug, squat, fling
        do {
            let r = scene(.football, at: c, start: .decorThrow, from: SIMD2(-1.0, 1.3), fate: 0)
            let (ren, t) = try makeRenderer(device, r, w: w, h: h)
            var n = 0
            while !(r.brain.idleState.throwStage == 1 && r.brain.idleState.phaseT > 0.45) && n < 9000 { step(r); n += 1 }
            shotAt(r, ren, t, "1. hug: the ball against his belly, between the stubby arms")
            while !(r.brain.idleState.throwStage == 2 && r.brain.idleState.phaseT > 0.28) && n < 9000 { step(r); n += 1 }
            shotAt(r, ren, t, "2. squat: down and back, ball pressed in")
            while !(r.brain.idleState.throwStage == 3 && DecorField.shared.anim[7]!.flying && DecorField.shared.anim[7]!.airV > 1.0) && n < 9000 { step(r); n += 1 }
            for _ in 0..<12 { step(r) }
            shotAt(r, ren, t, "3. fling: springs up, the ball leaves in a short arc")
        }
        // a fumble: bonk off the head
        do {
            let r = scene(.football, at: c, start: .decorThrow, from: SIMD2(-1.0, 1.3), fate: 1)
            let (ren, t) = try makeRenderer(device, r, w: w, h: h)
            var n = 0
            while !(DecorField.shared.anim[7]!.headHit) && n < 9000 { step(r); n += 1 }
            for _ in 0..<4 { step(r) }
            shotAt(r, ren, t, "4. fumble: it bonks off his head")
        }
        do {
            let r = scene(.football, at: c, start: .decorThrow, from: SIMD2(-1.0, 1.3), fate: 2)
            let (ren, t) = try makeRenderer(device, r, w: w, h: h)
            var n = 0
            while !(r.brain.idleState.throwStage == 3 && DecorField.shared.anim[7]!.flying) && n < 9000 { step(r); n += 1 }
            for _ in 0..<10 { step(r) }
            shotAt(r, ren, t, "5. fumble: it slips and drops")
        }
        // the two-Jelly toss
        do {
            DecorField.shared.clear()
            DecorField.shared.set([PlacedDecor(uid: 7, kind: .football, x: 0.2, z: 1.0)])
            let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.3, 1.4), SIMD2(1.6, 1.8)], quiet: true, seed: 5)
            for r in lab.rigs { r.skinner.autoBlink = false }
            XCTAssertTrue(lab.rigs[0].brain.socialStart(.toss, with: lab.rigs[1].brain, lab.rigs[0].sim))
            let (ren, t) = try makeRenderer(device, lab.rigs[0], w: w, h: h)
            var n = 0
            while !(DecorField.shared.anim[7]!.flying && DecorField.shared.anim[7]!.air > 0.4) && n < 9000 { stepLab(lab); n += 1 }
            let mid = (lab.rigs[0].sim.centroid() + lab.rigs[1].sim.centroid()) / 2
            cells.append((closeUp(ren, t, rigs: lab.rigs, focus: SIMD3(mid.x, 0.55, mid.z), dist: 7.0, w: w, h: h), "6. toss: the ball in flight toward his friend"))
            while !(lab.rigs[0].brain.social?.phase == 2) && n < 12000 { stepLab(lab); n += 1 }
            for _ in 0..<14 { stepLab(lab) }
            let mid2 = (lab.rigs[0].sim.centroid() + lab.rigs[1].sim.centroid()) / 2
            let caught = lab.rigs[0].brain.social?.fastMoves == 1
            cells.append((closeUp(ren, t, rigs: lab.rigs, focus: SIMD3(mid2.x, 0.55, mid2.z), dist: 7.0, w: w, h: h), caught ? "7. toss: caught, a hug" : "7. toss: missed, a comic lunge"))
        }
        try save(sheet(cells, cols: 3, title: "Football: hug, squat, fling, fumbles, and a two-Jelly toss (arms stay stubs)"), "football.png")
    }

    func testCaptureRoomFullLandscape() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let W = 1434, H = 660, a = Float(W) / Float(H)
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: a); GameCamera.refreshRoam(aspect: a)
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: false)
        for k in [DecorKind.swing, .loveseat, .slide, .petbed, .diningset] { book.grant(k.storeID); XCTAssertNotNil(book.place(k.storeID), "\(k) fits") }
        DecorField.shared.set(book.placedDecor)
        let lab = SocialTests.Lab(positions: [SIMD2(-1.0, 0.6), SIMD2(0.7, 0.9), SIMD2(0.0, 2.2)], quiet: false, seed: 5)
        for (i, r) in lab.rigs.enumerated() { r.skinner.autoBlink = false; AnticsLabTests.lively(r.brain); r.brain.idleMood = .happy; r.brain.idleState.cooldown = 3 + Float(i) * 2; r.brain.restTimer = 0.5 + Float(i) }
        var f = 0
        while f < 60 * 90 {
            stepLab(lab); f += 1
            if f > 60 * 10, lab.rigs.filter({ r in (r.brain.idleState.kind.map { BlobBrain.decorKinds.contains($0) } ?? false) && !r.brain.idleState.decorGo }).count >= 1 { break }
        }
        for _ in 0..<40 { stepLab(lab) }
        let (ren, target) = try makeRenderer(device, lab.rigs[0], w: W, h: H)
        decorMesh(into: ren)
        let cam = GameCamera.camera(aspect: a, focus: 0)
        let img = shot(ren, target, rigs: lab.rigs, cam: cam, w: W, h: H)
        let doing = lab.rigs.map { $0.brain.idleState.kind.map { $0.rawValue } ?? "-" }.joined(separator: ", ")
        try save(sheet([(img, "Landscape 2.17:1, \(book.roomUnitsUsed) of 10 spots: swing, loveseat, slide, pet bed, dining set; three Jellies (doing: \(doing))")], cols: 1, title: "Full room, landscape"), "room_full_land.png")
    }
}

extension FurnCaptureTests {
    /// Fix C QA: every piece in use, labelled, at the room camera's tilt in portrait; a close 3/4 view for the two-seat pieces.
    func testCaptureFurnitureQA() throws {
        guard dir != nil else { throw XCTSkip("FURN_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        let w = 520, h = 560
        var cells: [(LockImage, String)] = []
        func close(_ ren: MelonRenderer, _ t: MTLTexture, _ rigs: [MotionRig], focus: SIMD3<Float>, dist: Float) -> LockImage {
            decorMesh(into: ren, time: 0.37)
            return shot(ren, t, rigs: rigs, cam: camera(eye: focus + SIMD3(2.3, 1.0, dist * 0.62), at: focus, aspect: Float(w) / Float(h), fov: 33 * .pi / 180), w: w, h: h)
        }
        func sitCell(_ kind: DecorKind, n: Int, label: String, focusY: Float, dist: Float, extreme: Float? = nil, threeQuarter: Bool = false) throws {
            DecorField.shared.clear()
            let c = SIMD2<Float>(0.0, -0.8)
            DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: c.x, z: c.y)])
            let lab = SocialTests.Lab(n: n, positions: Array([SIMD2(c.x - 1.6, c.y + 2.0), SIMD2(c.x + 1.6, c.y + 2.0)].prefix(n)), quiet: true, seed: 7)
            Self.keep.append(lab)
            for r in lab.rigs { r.skinner.autoBlink = false; r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(.decorSit, r.sim)) }
            func seated(_ r: MotionRig) -> Bool { r.brain.idleState.bagStage == 2 && r.brain.idleState.phase == 2 && r.brain.idleState.phaseT > 3.0 }
            var f = 0
            func angle() -> Float { DecorField.shared.anim[7].map { abs(kind == .swing ? DecorModels.swingAngle($0) : DecorModels.rockAngle($0)) } ?? 0 }
            while f < 60 * 120 {
                stepLab(lab); f += 1
                if lab.rigs.allSatisfy(seated), extreme == nil || angle() > extreme! { break }
            }
            let (ren, t) = try makeRenderer(device, lab.rigs[0], w: w, h: h)
            let focus = SIMD3<Float>(c.x, focusY, c.y)
            cells.append((closeUp(ren, t, rigs: lab.rigs, focus: focus, dist: dist, w: w, h: h), label))
            if threeQuarter { cells.append((close(ren, t, lab.rigs, focus: focus, dist: dist), label + " (close 3/4)")) }
        }
        try sitCell(.pouf, n: 1, label: "Pouf", focusY: 0.5, dist: 4.4)
        try sitCell(.armchair, n: 1, label: "Armchair", focusY: 0.7, dist: 4.8)
        try sitCell(.diningset, n: 2, label: "Dining set: a Jelly on each stool", focusY: 0.6, dist: 9.0, threeQuarter: true)
        try sitCell(.rockingchair, n: 1, label: "Rocking chair at the rock extreme", focusY: 0.8, dist: 4.8, extreme: 0.1)
        try sitCell(.swing, n: 2, label: "Swing for two at the sway extreme", focusY: 0.9, dist: 6.6, extreme: 0.15, threeQuarter: true)
        try sitCell(.loveseat, n: 1, label: "Loveseat, one Jelly", focusY: 0.7, dist: 5.4)
        try sitCell(.loveseat, n: 2, label: "Loveseat, two Jellies", focusY: 0.7, dist: 5.6, threeQuarter: true)
        try sitCell(.beanbag, n: 1, label: "Beanbag", focusY: 0.5, dist: 4.4)
        // pet bed
        do {
            let c = SIMD2<Float>(1.0, 0.4)
            let r = scene(.petbed, at: c, start: .sleep, from: SIMD2(-1.0, 1.4))
            let (ren, t) = try makeRenderer(device, r, w: w, h: h)
            var n = 0
            while !(r.brain.isNapping && r.brain.sleep.t > 2.5) && n < 9000 { step(r); n += 1 }
            cells.append((closeUp(ren, t, rigs: [r], focus: SIMD3(c.x, 0.4, c.y), dist: 4.8, w: w, h: h), "Pet bed: asleep"))
        }
        // the slide
        do {
            let c = SIMD2<Float>(1.4, 0.3)
            let r = scene(.slide, at: c, start: .decorSlide, from: SIMD2(-1.0, 1.0))
            let (ren, t) = try makeRenderer(device, r, w: w, h: h)
            var n = 0
            let f = SIMD3<Float>(c.x, 0.7, c.y)
            while !(r.brain.idleState.slideStage == 1 && r.brain.idleState.slideStep == 1 && r.brain.gait.phase == .air) && n < 9000 { step(r); n += 1 }
            for _ in 0..<6 { step(r) }
            cells.append((closeUp(ren, t, rigs: [r], focus: f, dist: 6.4, w: w, h: h), "Slide: climbing"))
            while !(r.brain.idleState.slideStage == 4 && r.brain.idleState.phase == 2) && n < 18000 { step(r); n += 1 }
            for _ in 0..<20 { step(r) }
            cells.append((closeUp(ren, t, rigs: [r], focus: f, dist: 6.4, w: w, h: h), "Slide: sitting on the platform"))
            while !(r.brain.idleState.slideStage == 5 && r.brain.idleState.slideS > 1.4) && n < 27000 { step(r); n += 1 }
            cells.append((closeUp(ren, t, rigs: [r], focus: f, dist: 6.4, w: w, h: h), "Slide: mid-slide"))
        }
        try save(sheet(cells, cols: 3, title: "Furniture QA at 1.25x, portrait room camera"), "furniture_qa.png")
    }
}
