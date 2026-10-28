//
//  StoreCaptureTests.swift
//  Not a regression test: renders the store's 3D goods with the REAL renderer (MelonRenderer, the game room, true proportion) when STORE_CAP_DIR is set
//  (pass it as TEST_RUNNER_STORE_CAP_DIR). Output: foods_sheet.png (every new food on its tray, labelled, plus one being tossed into a mouth),
//  shoes_sheet.png (every shoe look on a Jelly, mid-walk, and a close-up).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class StoreCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var W = 480, H = 480

    override func setUp() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 1) }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    private func makeRenderer(_ device: MTLDevice, _ rig: MotionRig, w: Int, h: Int) throws -> (MelonRenderer, MTLTexture) {
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: rig.sim.edges, particleCount: rig.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: w, height: h)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        return (ren, device.makeTexture(descriptor: td)!)
    }

    private func camera(eye: SIMD3<Float>, at: SIMD3<Float>, aspect: Float, fov: Float = 34 * .pi / 180) -> CameraState {
        var c = CameraState()
        c.view = M4.lookAt(eye: eye, at: at, up: SIMD3(0, 1, 0))
        c.viewProj = M4.mul(M4.perspective(fovy: fov, aspect: aspect, near: 0.1, far: 60), c.view)
        c.invViewProj = M4.invert(c.viewProj)
        c.pos = eye; c.fwd = simd_normalize(at - eye)
        return c
    }

    /// One frame: the body of `rig` (nil = hidden under the floor), whatever the room holds, from `cam`.
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
    private func save(_ img: UIImage, _ dir: String, _ name: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try img.pngData()?.write(to: URL(fileURLWithPath: dir + "/" + name))
    }

    /// The real dining flow with a bought food or drink, from the game camera: a food is frozen in flight and as it lands in his mouth, a drink while he
    /// sips it (early and nearly empty). Crops follow his mouth, true proportion.
    private func mealShots(_ device: MTLDevice, id: String, w: Int, h: Int, size: Int) throws -> [(LockImage, String)] {
        let m = MealRun()
        Self.keep.append(m)
        let (ren, target) = try makeRenderer(device, m.rig, w: w, h: h)
        let room = ren.room!
        let cam = GameCamera.camera(aspect: Float(w) / Float(h))
        let c = try XCTUnwrap(Consumables.with(id: id))
        m.care.store.grant(id, 2)
        m.moveAway()
        if c.kind == .drink { m.care.drink(id) } else { m.care.feed(id) }
        var out: [(LockImage, String)] = []
        var flight: LockImage?, landed: LockImage?, early: LockImage?, late: LockImage?
        var flyTicks = 0, sipTicks = 0
        for _ in 0..<(60 * 40) {
            m.tick()
            if let f = m.tray.frame(theme: room.theme) { room.setDining(f) }
            let mouth = m.brain.mouthWorld(sim: m.rig.sim)
            let aim = mouth + SIMD3(c.kind == .drink ? -0.2 : -0.35, -0.3, 0)
            if c.kind == .drink {
                if m.brain.activity == .drinking {
                    sipTicks += 1
                    if early == nil, sipTicks == 45 { early = crop(shot(ren, target, rig: m.rig, showBody: true, cam: cam, w: w, h: h), cam: cam, around: aim, w: w, h: h, size: size) }
                    if late == nil, m.tray.drinkFill < 0.5 { late = crop(shot(ren, target, rig: m.rig, showBody: true, cam: cam, w: w, h: h), cam: cam, around: aim, w: w, h: h, size: size) }
                }
                if early != nil, late != nil { break }
            } else {
                if flight == nil, m.brain.dineFlying, !m.brain.dineLanded, m.brain.dineHolding {
                    flyTicks += 1
                    if flyTicks == 5 { flight = crop(shot(ren, target, rig: m.rig, showBody: true, cam: cam, w: w, h: h), cam: cam, around: aim, w: w, h: h, size: size) }
                }
                if landed == nil, m.brain.dineLanded { landed = crop(shot(ren, target, rig: m.rig, showBody: true, cam: cam, w: w, h: h), cam: cam, around: aim, w: w, h: h, size: size) }
                if flight != nil, landed != nil { break }
            }
        }
        if c.kind == .drink {
            XCTAssertNotNil(early, "\(id): a sip frame"); XCTAssertNotNil(late, "\(id): a late sip frame")
            if let e = early { out.append((e, "\(c.name): sipping")) }
            if let l = late { out.append((l, "\(c.name): level dropped")) }
        } else {
            XCTAssertNotNil(flight, "\(id): a flight frame"); XCTAssertNotNil(landed, "\(id): a landing frame")
            if let f = flight { out.append((f, "\(c.name): mid-toss")) }
            if let l = landed { out.append((l, "\(c.name): lands in his mouth")) }
        }
        return out
    }

    /// Eating moments of the foods / drinks named in FOOD_MEAL_IDS (comma separated; default "ramen,boba"), written to meals_<ids>.png in STORE_CAP_DIR:
    /// a food mid-toss and landing in his mouth, a drink while he sips it. Run a few ids per invocation (each is a full simulated meal).
    func testCaptureMeals() throws {
        guard let dir = ProcessInfo.processInfo.environment["STORE_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("STORE_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let ids = (ProcessInfo.processInfo.environment["FOOD_MEAL_IDS"] ?? "ramen,boba").split(separator: ",").map(String.init)
        var cells: [(LockImage, String)] = []
        for id in ids { cells += try mealShots(device, id: id, w: 1320, h: 2868, size: 640) }
        XCTAssertFalse(cells.isEmpty)
        try save(sheet(cells, cols: 2, title: "Eating moments (game camera, true proportion): tossed foods, sipped drinks"), dir, "meals_\(ids.joined(separator: "_")).png")
    }

    func testCaptureFoods() throws {
        guard let dir = ProcessInfo.processInfo.environment["STORE_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("STORE_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let m = MealRun()
        Self.keep.append(m)
        let (ren, target) = try makeRenderer(device, m.rig, w: W, h: H)
        let room = ren.room!
        var cells: [(LockImage, String)] = []
        // every food and drink on its tray, from the front and above
        for f in Consumables.storeFoods + Consumables.storeDrinks {
            let L = DiningLayout.make(n: 1)
            let g = DiningModels.trayGroup(layout: L, serving: f, state: ServingState(n: 1, bitesLeft: [3]), theme: room.theme)
            let b = RoomMeshBuilder(); b.material = .plain
            let tb = RoomMeshBuilder(); tb.material = .plain
            DiningModels.append(g.opaque, to: b, transform: DiningModels.translation(SIMD3(0, 0, 0.6)))
            DiningModels.append(g.translucent, to: tb, transform: DiningModels.translation(SIMD3(0, 0, 0.6)))
            room.setDining(DiningFrame(opaque: b.mesh, translucent: tb.mesh))
            let drink = f.kind == .drink          // a cup is taller than a plate food: the camera stands back
            let cam = camera(eye: drink ? SIMD3(0.0, 1.0, 1.75) : SIMD3(0.0, 0.78, 1.25), at: SIMD3(0, drink ? 0.38 : 0.3, 0.46), aspect: Float(W) / Float(H), fov: 30 * .pi / 180)
            cells.append((shot(ren, target, rig: m.rig, showBody: false, cam: cam, w: W, h: H), f.name + (StoreCatalog.item(forFood: f.id).map { "  \($0.price) JellyCoins" } ?? "")))
        }
        try save(sheet(cells, cols: 4, title: "Store foods: real 3D meshes on the tray, eaten through the toss flow"), dir, "foods_sheet.png")
    }

    /// The game camera, a phone-sized frame, cropped around a world point (true proportion: no scaling of the crop).
    private func crop(_ img: LockImage, cam: CameraState, around p: SIMD3<Float>, w: Int, h: Int, size: Int) -> LockImage {
        let q = cam.viewProj * SIMD4(p, 1)
        let cx = Int((q.x / q.w * 0.5 + 0.5) * Float(w)), cy = Int((1 - (q.y / q.w * 0.5 + 0.5)) * Float(h))
        let x0 = min(max(cx - size / 2, 0), w - size), y0 = min(max(cy - size / 2, 0), h - size)
        var px = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size { for x in 0..<size { for c in 0..<4 { px[(y * size + x) * 4 + c] = img.bgra[((y0 + y) * w + x0 + x) * 4 + c] } } }
        return LockImage(w: size, h: size, bgra: px)
    }

    /// dining_land.png: a phone on its side (2.17 : 1), the tray out and a sushi in flight to his mouth, the full frame from the game camera.
    func testCaptureDiningLandscape() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOOD_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("FOOD_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 1434, h = 660
        let m = MealRun()
        Self.keep.append(m)
        let (ren, target) = try makeRenderer(device, m.rig, w: w, h: h)
        let room = ren.room!
        let cam = GameCamera.camera(aspect: Float(w) / Float(h))
        m.care.store.grant("sushi", 2)
        m.moveAway()
        m.care.feed("sushi")
        var flyTicks = 0
        var frame: LockImage?
        for _ in 0..<(60 * 30) {
            m.tick()
            if let f = m.tray.frame(theme: room.theme) { room.setDining(f) }
            if m.brain.dineFlying, !m.brain.dineLanded, m.brain.dineHolding {
                flyTicks += 1
                if flyTicks == 5 { frame = shot(ren, target, rig: m.rig, showBody: true, cam: cam, w: w, h: h); break }
            }
        }
        let img = try XCTUnwrap(frame)
        let bar = 40
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: CGSize(width: w, height: h + bar), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + bar))
            ("Dining, landscape 2.17:1: the tray on the floor, a sushi tossed toward his mouth (game camera, true proportion)" as NSString).draw(at: CGPoint(x: 10, y: 9), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 19), .foregroundColor: UIColor.white])
            img.uiImage()?.draw(in: CGRect(x: 0, y: bar, width: w, height: h))
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try out.pngData()?.write(to: URL(fileURLWithPath: dir + "/dining_land.png"))
    }

    /// foods_ingame.png (every food on the real tray from the game camera), toss.png (a sushi in flight and landing), shop_snacks.png (the Shop/Bag thumbnails).
    func testCaptureFoodsInGame() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOOD_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("FOOD_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 1320, h = 2868, size = 330
        let m = MealRun()
        Self.keep.append(m)
        let (ren, target) = try makeRenderer(device, m.rig, w: w, h: h)
        let room = ren.room!
        let cam = GameCamera.camera(aspect: Float(w) / Float(h))
        var cells: [(LockImage, String)] = []
        let o = DiningSpot.preferred
        for f in Consumables.storeFoods + Consumables.storeDrinks {
            let L = DiningLayout.make(n: 1)
            let g = DiningModels.trayGroup(layout: L, serving: f, state: ServingState(n: 1, bitesLeft: [3]), theme: room.theme)
            let b = RoomMeshBuilder(); b.material = .plain
            let tb = RoomMeshBuilder(); tb.material = .plain
            DiningModels.append(g.opaque, to: b, transform: DiningModels.translation(SIMD3(o.x, 0, o.y)))
            DiningModels.append(g.translucent, to: tb, transform: DiningModels.translation(SIMD3(o.x, 0, o.y)))
            room.setDining(DiningFrame(opaque: b.mesh, translucent: tb.mesh))
            let full = shot(ren, target, rig: m.rig, showBody: false, cam: cam, w: w, h: h)
            cells.append((crop(full, cam: cam, around: SIMD3(o.x, f.kind == .drink ? 0.30 : 0.12, o.y), w: w, h: h, size: size), f.name))
        }
        try save(sheet(cells, cols: 6, title: "Store foods and drinks on the in-game tray (game camera, true proportion)"), dir, "foods_ingame.png")

        // the Shop / Bag thumbnails
        var scells: [(LockImage, String)] = []
        _ = scells
        let items = StoreCatalog.items.filter { $0.food != nil }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let tw = 240, th = 270, cols = 6, rows = (items.count + cols - 1) / cols
        let img = UIGraphicsImageRenderer(size: CGSize(width: tw * cols, height: 54 + th * rows), format: fmt).image { _ in
            UIColor(red: 1, green: 0.96, blue: 0.9, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: tw * cols, height: 54 + th * rows))
            ("Shop: snacks (3D thumbnails, as the Shop and Bag draw them)" as NSString).draw(at: CGPoint(x: 12, y: 12), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24), .foregroundColor: UIColor.black])
            for (i, it) in items.enumerated() {
                let x = (i % cols) * tw, y = 54 + (i / cols) * th
                UIColor.white.setFill(); UIBezierPath(roundedRect: CGRect(x: x + 8, y: y + 4, width: tw - 16, height: th - 12), cornerRadius: 22).fill()
                StoreThumb.image(for: it)?.draw(in: CGRect(x: x + 20, y: y + 10, width: tw - 40, height: tw - 40))
                ("\(it.name)  \(it.price) JellyCoins" as NSString).draw(at: CGPoint(x: x + 16, y: y + th - 38), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.black])
            }
        }
        try save(img, dir, "shop_snacks.png")
    }

    func testCaptureShoes() throws {
        guard let dir = ProcessInfo.processInfo.environment["STORE_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("STORE_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        var cells: [(LockImage, String)] = []
        let w = 360, h = 520
        for look in WearLook.allCases {
            let rig = MotionRig(game: true)
            Self.keep.append(rig)
            rig.renderSamples = false
            let (ren, target) = try makeRenderer(device, rig, w: w, h: h)
            rig.brain.request(.goTo(SIMD2(0.0, 1.2)))
            var got = false
            for _ in 0..<(60 * 4) {
                rig.tick()
                if rig.skinner.beansActive, rig.skinner.beanBlend > 0.95, rig.brain.beanMorphLast.contains(where: { $0 > 0.5 }) { got = true; break }
            }
            _ = got
            guard let beans = GameCare.footBeans(brain: rig.brain, sim: rig.sim, skinner: rig.skinner) else { XCTFail("beans"); continue }
            let b = RoomMeshBuilder(); b.material = .plain
            for s in 0..<2 { ShoeModel.build(look, bean: beans[s], floorY: rig.sim.floorY, time: 1.1, side: s, into: b) }
            ren.room!.setShoes(b.mesh)
            let c = rig.sim.centroid()
            let cam = camera(eye: SIMD3(c.x + 1.5, 0.45, c.z + 3.6), at: SIMD3(c.x, 0.55, c.z), aspect: Float(w) / Float(h), fov: 34 * .pi / 180)
            cells.append((shot(ren, target, rig: rig, showBody: true, cam: cam, w: w, h: h), look.title + " (mid-step)"))
            // the close-up of the feet, planted
            let near = camera(eye: SIMD3(c.x + 0.7, 0.16, c.z + 1.5), at: SIMD3(c.x, 0.12, c.z), aspect: Float(w) / Float(h), fov: 30 * .pi / 180)
            cells.append((shot(ren, target, rig: rig, showBody: true, cam: near, w: w, h: h), look.title + " (close-up)"))
        }
        try save(sheet(cells, cols: 4, title: "Shoes: 3D shells grown from the foot beans (cosmetic, no speed effect)"), dir, "shoes_sheet.png")
    }
}
