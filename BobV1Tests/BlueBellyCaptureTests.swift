//
//  BlueBellyCaptureTests.swift
//  Not a regression test (except testOnlyBlueGetsIt): when BLUEBELLY_DIR is set (TEST_RUNNER_BLUEBELLY_DIR) it renders Bob (character 0) with the real game renderer, once
//  per variant (off / A / B1 / B2) from the SAME frozen pose, angle and light, and writes the mockup boards for the user to pick from. See BobV1/Melon/BlueBelly.swift.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class BlueBellyCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    typealias V = BlueBelly
    static let width = ProcessInfo.processInfo.environment["BLUEBELLY_WIDTH"] == "w3" ? "w3" : "w4"
    static let variants: [(V, String)] = width == "w3" ? [(.off, "off"), (.eggW3, "C2w3"), (.eggW3D1, "C2w3-D1"), (.eggW3D2, "C2w3-D2")]
                                                       : [(.off, "off"), (.eggW4, "C2w4"), (.eggW4D1, "C2w4-D1"), (.eggW4D2, "C2w4-D2")]

    override func setUp() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 603.0 / 1311.0); DayClock.shared.forcedHour = 12 }
    override func tearDown() { BlueBelly.current = .off; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DayClock.shared.forcedHour = 12 }

    // MARK: plumbing (a trimmed copy of PipTailChecklistTests' harness)

    struct Char { var id: Int }
    final class Ctx { let ren: MelonRenderer; let target: MTLTexture; let W: Int, H: Int
        init(ren: MelonRenderer, target: MTLTexture, W: Int, H: Int) { self.ren = ren; self.target = target; self.W = W; self.H = H } }

    private func makeCtx(sim: SoftBody, W: Int, H: Int) throws -> Ctx {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: sim.edges, particleCount: sim.n, game: true, bodyCount: 1), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        let c = Ctx(ren: ren, target: device.makeTexture(descriptor: td)!, W: W, H: H)
        Self.keep.append(ren)
        return c
    }

    private func makeLab(ids: [Int], positions: [SIMD2<Float>]) -> SocialTests.Lab {
        let lab = SocialTests.Lab(n: ids.count, positions: positions, quiet: true, seed: 3)
        SocialTests.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.skinner.autoBlink = false
            r.brain.feature = JellyRoster.feature(ids[k]); r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        }
        WearBody.install(MotionRig.renderMesh)
        return lab
    }
    final class Dressed { var worn: [WornSet] = [], feats: [FeatureSet] = [] }
    private func dress(_ lab: SocialTests.Lab, _ ids: [Int]) -> Dressed {
        let d = Dressed()
        for (k, r) in lab.rigs.enumerated() {
            let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; Self.keep.append(w)
            let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f)
            d.worn.append(w); d.feats.append(f)
            for _ in 0..<3 { wearTick(w, f, r.brain, r.sim, ids[k]) }
        }
        return d
    }
    private func wearTick(_ w: WornSet, _ f: FeatureSet, _ brain: BlobBrain, _ sim: SoftBody, _ id: Int) {
        w.tick(id: 0, brain: brain, sim: sim, outfit: [:], role: .none, hideAll: false, dt: 1.0 / 60)
        f.tick(id: 0, brain: brain, sim: sim, feature: JellyRoster.feature(id), worn: [], hideAll: false, dt: 1.0 / 60)
        if let s = f.slot(0) { w.setArtOverride(0, s.fit.hatVariant); brain.wingsFolded = s.fit.folded; brain.wingFlapLimit = s.fit.flapMax }
    }
    private func step(_ lab: SocialTests.Lab, _ d: Dressed, _ ids: [Int], brains: Bool = true) {
        if brains { lab.tick(watching: false) } else { for r in lab.rigs { r.sim.step() } }
        for (k, r) in lab.rigs.enumerated() { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); wearTick(d.worn[k], d.feats[k], r.brain, r.sim, ids[k]) }
    }
    private func skin(_ s: Skinner, _ sim: SoftBody) -> [Float] {
        var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        s.update(x: sim.x, index: MotionRig.renderMesh.index, into: &d)
        return d
    }
    private func settle(_ lab: SocialTests.Lab, _ d: Dressed, _ ids: [Int]) {
        for r in lab.rigs { r.brain.autonomy = false; r.brain.expr.enabled = false }
        for _ in 0..<40 { step(lab, d, ids) }
        for r in lab.rigs { for _ in 0..<32 { _ = skin(r.skinner, r.sim) } }
    }

    struct Subj { let skinner: Skinner; let sim: SoftBody; let brain: BlobBrain; let worn: WornSet; let feats: FeatureSet; let id: Int }
    private func subj(_ lab: SocialTests.Lab, _ d: Dressed, _ ids: [Int]) -> Subj {
        Subj(skinner: lab.rigs[0].skinner, sim: lab.rigs[0].sim, brain: lab.rigs[0].brain, worn: d.worn[0], feats: d.feats[0], id: ids[0])
    }

    /// One Jelbie in the room (or, `neutral`, cut out by differencing against the empty room and pasted on a flat warm backdrop).
    private func render(_ c: Ctx, _ s: Subj, cam: CameraState, neutral: Bool, prep: ((MelonRenderer) -> Void)? = nil) -> LockImage {
        let ren = c.ren, W = c.W, H = c.H
        let vc = MotionRig.renderMesh.vertexCount
        func shot(visible: Bool) -> LockImage {
            ren.beginFrame()
            let p = ren.dynPointer(body: 0)
            ren.setHidden(!visible, body: 0)
            if visible { s.skinner.update(x: s.sim.x, index: MotionRig.renderMesh.index, into: p) }
            else { for v in 0..<vc { p[6 * v] = 0; p[6 * v + 1] = -60; p[6 * v + 2] = 0; p[6 * v + 3] = 0; p[6 * v + 4] = 1; p[6 * v + 5] = 0 } }
            if visible {
                let sk = skin(s.skinner, s.sim)
                var f = sk.withUnsafeBufferPointer { p in s.worn.frame(theme: ren.room!.theme, time: 0.4) { _ in p.baseAddress } }
                let ff = sk.withUnsafeBufferPointer { p in s.feats.frame { _ in p.baseAddress } }
                let base = UInt32(f.opaque.vertices.count)
                f.opaque.vertices += ff.vertices; f.opaque.indices += ff.indices.map { $0 + base }
                ren.room!.setWear(opaque: f.opaque, translucent: f.translucent, bounds: [])
                ren.room!.setShoes(RoomMeshBuilder().mesh)
                ren.setJersey(s.worn.jersey(0), body: 0)
                ren.setMouth(s.brain.mouthOpen, body: 0)
                ren.setBlush(0, body: 0)
            } else {
                ren.room!.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []); ren.room!.setShoes(RoomMesh()); ren.setJersey(nil, body: 0)
            }
            if visible { prep?(ren) }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = JellyRoster.palette(s.id) ?? PaletteKey.blue.palette
            ren.setPalette(pal, body: 0)
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: GameCamera.light(centroids: [s.sim.centroid()]), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: c.target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { c.target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            return LockImage(w: W, h: H, bgra: px)
        }
        ren.dayHourOverride = 12
        let b = shot(visible: true)
        guard neutral else { return b }
        let empty = shot(visible: false)
        var out = b
        for p in 0..<(W * H) {
            var dd = 0
            for k in 0..<3 { dd = max(dd, abs(Int(b.bgra[4 * p + k]) - Int(empty.bgra[4 * p + k]))) }
            if dd <= 3 { out.bgra[4 * p] = 236; out.bgra[4 * p + 1] = 232; out.bgra[4 * p + 2] = 228; out.bgra[4 * p + 3] = 255 }
        }
        return out
    }

    // MARK: cameras

    private func camera(eye: SIMD3<Float>, target: SIMD3<Float>, aspect: Float = 1, up: SIMD3<Float> = SIMD3(0, 1, 0)) -> CameraState {
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: up)
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        return cam
    }
    private func pose(_ sim: SoftBody, memo: inout SIMD3<Float>) -> (c: SIMD3<Float>, fwd: SIMD3<Float>) {
        let p = sim.bodyPose(iterations: 3)
        var f = p.rotation.act(SIMD3<Float>(0, 0, 1)); f.y = 0
        if simd_length(f) > 0.3 { memo = simd_normalize(f) }
        return (p.centroid, memo)
    }
    /// A camera `yaw` radians around the body's own facing (0 = straight at his face), `dist` away, looking at his middle.
    private func view(_ sim: SoftBody, memo: inout SIMD3<Float>, yaw: Float, dist: Float = 3.3, lookY: Float = 0.12, lift: Float = 0.10, aspect: Float = 1) -> CameraState {
        let (c, fwd) = pose(sim, memo: &memo)
        let t = SIMD3(c.x, c.y + lookY, c.z)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        return camera(eye: t + dir * dist + SIMD3(0, dist * lift, 0), target: t, aspect: aspect)
    }

    // MARK: output

    private func outDir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["BLUEBELLY_DIR"], !d.isEmpty else { throw XCTSkip("BLUEBELLY_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    private func labelled(_ img: UIImage, _ text: String, bar: CGFloat = 40) -> UIImage {
        let w = img.size.width, h = img.size.height
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + bar), format: fmt).image { _ in
            UIColor(white: 0.12, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + bar))
            (text as NSString).draw(at: CGPoint(x: 10, y: 8), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.white])
            img.draw(in: CGRect(x: 0, y: bar, width: w, height: h))
        }
    }
    private func grid(_ imgs: [UIImage], cols: Int) -> UIImage {
        let cw = imgs.map { $0.size.width }.max() ?? 0, ch = imgs.map { $0.size.height }.max() ?? 0
        let rows = (imgs.count + cols - 1) / cols
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: cw * CGFloat(cols), height: ch * CGFloat(rows)), format: fmt).image { _ in
            UIColor(white: 0.12, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: cw * CGFloat(cols), height: ch * CGFloat(rows)))
            for (i, im) in imgs.enumerated() { im.draw(at: CGPoint(x: CGFloat(i % cols) * cw, y: CGFloat(i / cols) * ch)) }
        }
    }
    private func save(_ img: UIImage, _ path: String) throws { try img.pngData()!.write(to: URL(fileURLWithPath: path)) }

    /// Renders `scene` once per variant from the same pose; saves each (cropped) PNG and returns the four labelled tiles.
    @discardableResult
    private func fourUp(_ dir: String, _ name: String, _ title: String, ctx: Ctx, subj s: Subj, cam: CameraState, neutral: Bool = true, crop: (Int, Int, Int)? = nil, prep: ((MelonRenderer) -> Void)? = nil) throws -> [UIImage] {
        var tiles: [UIImage] = []
        var imgs: [LockImage] = []
        for (v, tag) in Self.variants {
            BlueBelly.current = v
            var img = render(ctx, s, cam: cam, neutral: neutral, prep: prep)
            if let (cx, cy, size) = crop { img = LegsGameCamCaptureTests.crop(img, cx: cx, cy: cy, size: size) }
            imgs.append(img)
            try save(img.uiImage()!, dir + "/\(name)_\(tag).png")
            tiles.append(labelled(img.uiImage()!, "\(title)   [\(tag)]"))
        }
        BlueBelly.current = .off
        _ = imgs
        return tiles
    }

    // MARK: the capture

    func testCaptureBoards() throws {
        let dir = try outDir()
        let ids = [0]
        let lab = makeLab(ids: ids, positions: [SIMD2(0.0, 0.6)]); let dr = dress(lab, ids); settle(lab, dr, ids)
        let r0 = lab.rigs[0]
        let c = try makeCtx(sim: r0.sim, W: 640, H: 640)
        let s = subj(lab, dr, ids)
        var memo = SIMD3<Float>(0, 0, 1)
        var boards: [String: [UIImage]] = [:]

        // 1. standing: front, 3/4, side, back
        let angles: [(String, Float)] = [("front", 0), ("34", 0.7), ("side", .pi / 2), ("back", .pi)]
        for (n, yaw) in angles {
            let cam = view(s.sim, memo: &memo, yaw: yaw)
            boards["angle_" + n] = try fourUp(dir, "stand_" + n, "standing \(n)", ctx: c, subj: s, cam: cam)
        }
        // mouth open + blush (the patch must never touch the mouth), front and 3/4
        let mouthPrep: (MelonRenderer) -> Void = { $0.setMouth(1.0, body: 0); $0.setBlush(0.85, body: 0) }
        boards["mouth"] = try fourUp(dir, "mouthopen_front", "mouth wide open + blush, front", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: 0, dist: 2.4, lookY: 0.05), prep: mouthPrep)
        boards["mouth34"] = try fourUp(dir, "mouthopen_34", "mouth wide open + blush, 3/4", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: 0.7, dist: 2.6, lookY: 0.05), prep: mouthPrep)
        for (n, yaw, ly) in [("front", Float(0), Float(0.35)), ("34", 0.7, 0.35), ("side", .pi / 2, 0.35)] {
            boards["face_" + n] = try fourUp(dir, "face_" + n, "forehead close-up \(n)", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: yaw, dist: 2.3, lookY: ly), prep: { $0.setBlush(0.6, body: 0) })
        }
        // jersey
        let jerseyPrep: (MelonRenderer) -> Void = { $0.setJersey(.sky, body: 0) }
        boards["jersey"] = try fourUp(dir, "jersey_front", "wearing the sky jersey, front", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: 0), prep: jerseyPrep)
        boards["jersey34"] = try fourUp(dir, "jersey_34", "wearing the sky jersey, 3/4", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: 0.7), prep: jerseyPrep)

        // (the rig's direct fingertip-sphere poke was removed from this board: see testPokeRealVsRig, which drives the real touch code)
        // 2b. dragged (grabbed on the belly and pulled sideways + up)
        do {
            let (cen, fwd) = pose(s.sim, memo: &memo)
            let hit = SIMD3(cen.x, s.sim.floorY + 0.36, cen.z) + fwd * 0.6
            s.sim.beginGrab(hit: hit, radius: 0.42)
            let side = SIMD3<Float>(fwd.z, 0, -fwd.x)
            for i in 0...45 {
                let k = Float(i) / 45
                s.sim.moveGrab(target: hit + side * (0.95 * k) + SIMD3(0, 0.25 * k, 0) + fwd * (0.1 * k), rot: nil)
                step(lab, dr, ids, brains: false)
            }
            for _ in 0..<5 { step(lab, dr, ids, brains: false) }
            boards["drag"] = try fourUp(dir, "drag_front", "dragged by the belly, front", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: 0, dist: 3.8))
            boards["drag34"] = try fourUp(dir, "drag_34", "dragged by the belly, 3/4", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: 0.7, dist: 3.8))
            s.sim.endGrab()
            for _ in 0..<200 { step(lab, dr, ids) }
        }

        // 3. mid-walk
        do {
            let p = s.sim.bodyPose(iterations: 3).centroid
            s.brain.hurry = false
            s.brain.script = .walk(target: SIMD2(p.x - 3.0, p.z + 0.2), then: .none); s.brain.activity = .walking; s.brain.scriptT = 0
            var t: Float = 0
            while t < 1.35 { step(lab, dr, ids); t += 1.0 / 60 }
            XCTAssertEqual(s.brain.activity, .walking, "he is walking for the capture")
            boards["walk"] = try fourUp(dir, "walk_34", "mid-walk, 3/4", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: 0.7, dist: 3.9))
            boards["walkside"] = try fourUp(dir, "walk_side", "mid-walk, side", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: .pi / 2, dist: 3.9))
            boards["walkfront"] = try fourUp(dir, "walk_front", "mid-walk, front", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: 0, dist: 3.9))
        }

        // 4. lying asleep
        do {
            let b = s.brain
            for _ in 0..<240 { step(lab, dr, ids) }
            b.idleForced = true
            XCTAssertTrue(b.idleStart(.sleep, s.sim), "sleep starts")
            b.sleep.hold = 500
            var t: Float = 0
            while !b.isNapping && t < 25 { step(lab, dr, ids); t += 1.0 / 60 }
            for _ in 0..<150 { step(lab, dr, ids) }
            let pn = s.sim.bodyPose(iterations: 3)
            let lying = (pn.rotation.act(SIMD3<Float>(0, 0, 1))).y
            NSLog("BLUEBELLY sleep: napping=%d faceNormalY=%.2f", b.isNapping ? 1 : 0, lying)
            for (n, yaw) in [("front", Float(0)), ("34", 0.9), ("side", .pi / 2)] {
                boards["sleep_" + n] = try fourUp(dir, "sleep_" + n, "lying asleep \(n)", ctx: c, subj: s, cam: view(s.sim, memo: &memo, yaw: yaw, dist: 3.4, lookY: 0.0, lift: 0.35))
            }
            // top-down on the lying body: the belly faces the sky or the floor depending on how he lies
            let cen = s.sim.centroid()
            boards["sleep_top"] = try fourUp(dir, "sleep_top", "lying asleep, from above", ctx: c, subj: s, cam: camera(eye: cen + SIMD3(0, 3.6, 0.6), target: cen))
        }

        // 5. a fresh standing Bob for the context shots (room camera, landscape, picker)
        let lab2 = makeLab(ids: ids, positions: [SIMD2(0.2, 0.6)]); let dr2 = dress(lab2, ids); settle(lab2, dr2, ids)
        let s2 = subj(lab2, dr2, ids)
        // normal room camera (portrait phone framing): a 1:1 native crop on him, plus the whole frame
        do {
            let W = 603, H = 1311
            let cr = try makeCtx(sim: s2.sim, W: W, H: H)
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            let cen = s2.sim.centroid()
            let clip = cam.viewProj * SIMD4<Float>(cen.x, cen.y, cen.z, 1)
            let sx = Int((clip.x / clip.w * 0.5 + 0.5) * Float(W)), sy = Int((0.5 - clip.y / clip.w * 0.5) * Float(H))
            boards["room"] = try fourUp(dir, "room_crop", "room camera (native pixels)", ctx: cr, subj: s2, cam: cam, neutral: false, crop: (sx, sy, 300))
            // whole frame
            var full: [UIImage] = []
            for (v, tag) in Self.variants {
                BlueBelly.current = v
                let img = render(cr, s2, cam: cam, neutral: false)
                try save(img.uiImage()!, dir + "/room_full_\(tag).png")
                full.append(labelled(img.uiImage()!, "room camera, whole frame [\(tag)]"))
            }
            BlueBelly.current = .off
            boards["roomfull"] = full
        }
        // landscape room shot
        do {
            let W = 1311, H = 603
            let cl = try makeCtx(sim: s2.sim, W: W, H: H)
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            let cen = s2.sim.centroid()
            let clip = cam.viewProj * SIMD4<Float>(cen.x, cen.y, cen.z, 1)
            let sx = Int((clip.x / clip.w * 0.5 + 0.5) * Float(W)), sy = Int((0.5 - clip.y / clip.w * 0.5) * Float(H))
            boards["landscape_crop"] = try fourUp(dir, "landscape_crop", "landscape room (native crop)", ctx: cl, subj: s2, cam: cam, neutral: false, crop: (sx, sy, 360))
            var full: [UIImage] = []
            for (v, tag) in Self.variants {
                BlueBelly.current = v
                let img = render(cl, s2, cam: cam, neutral: false)
                try save(img.uiImage()!, dir + "/landscape_full_\(tag).png")
                full.append(labelled(img.uiImage()!, "landscape room, whole frame [\(tag)]"))
            }
            BlueBelly.current = .off
            boards["landscape"] = full
        }
        // species picker stage (focus close-up, PhotoCam orbit at the resting yaw / zoom 1.6), and the opening's bare look (the same framing, flat backdrop)
        do {
            var memo2 = SIMD3<Float>(0, 0, 1)
            let (_, fwd) = pose(s2.sim, memo: &memo2)
            let spot = GameCare.floorPos(s2.brain, s2.sim)
            let fp = GameCamera.focusPose(aspect: 1, spot: spot)
            var v0 = fp.eye - fp.target
            let hl: Float = simd_length(SIMD2<Float>(v0.x, v0.z))
            v0.x = fwd.x * hl; v0.z = fwd.z * hl
            let (sy, sp, sz, spn) = (PhotoCam.yaw, PhotoCam.pitch, PhotoCam.zoom, PhotoCam.pan)
            defer { PhotoCam.yaw = sy; PhotoCam.pitch = sp; PhotoCam.zoom = sz; PhotoCam.pan = spn }
            for (n, y) in [("rest", PickerCamera.startYaw(0)), ("orbit_front", 0), ("orbit_side", Float.pi / 2), ("orbit_back", Float.pi)] {
                PhotoCam.yaw = y; PhotoCam.pitch = 0; PhotoCam.zoom = PickerCamera.startZoom; PhotoCam.pan = .zero
                let e = PhotoCam.apply(eye: fp.target + v0, target: fp.target)
                boards["picker_" + n] = try fourUp(dir, "picker_" + n, "species picker stage (\(n))", ctx: c, subj: s2, cam: camera(eye: e.eye, target: e.target), neutral: true)
            }
        }

        // 6. every render tier / fast path: B2 and A, standing 3/4, matte (tier 0), fast tiers 1...3, bath shader, and the jersey shader (done above)
        do {
            var cells: [UIImage] = []
            let cam = view(s2.sim, memo: &memo, yaw: 0.7)
            for (label, tier, bath) in [("tier 0 (locked matte)", 0, false), ("fast tier 1", 1, false), ("fast tier 2", 2, false), ("fast tier 3", 3, false), ("bath shader", 0, true)] {
                c.ren.gfxOpt.fastMatteTier = tier
                c.ren.forceBathShader = bath
                for (v, tag) in [(V.eggW4, "C2w4"), (V.eggW4D1, "C2w4-D1"), (V.eggW4D2, "C2w4-D2")] {
                    BlueBelly.current = v
                    let img = render(c, s2, cam: cam, neutral: true)
                    try save(img.uiImage()!, dir + "/tier_\(tier)\(bath ? "bath" : "")_\(tag).png")
                    cells.append(labelled(img.uiImage()!, "\(label) [\(tag)] pipeline=\(c.ren.lastBodyPipeline)"))
                }
            }
            c.ren.gfxOpt.fastMatteTier = 0; c.ren.forceBathShader = false
            BlueBelly.current = .off
            boards["tiers"] = cells
        }

        // 7. only character 0 (blue) gets it: Pip (yellow) is pixel-identical off vs A, and so is Bob's body in a non-blue palette
        do {
            let ids1 = [1]
            let lab3 = makeLab(ids: ids1, positions: [SIMD2(0.2, 0.6)]); let dr3 = dress(lab3, ids1); settle(lab3, dr3, ids1)
            let s3 = subj(lab3, dr3, ids1)
            let c3 = try makeCtx(sim: s3.sim, W: 320, H: 320)
            var m3 = SIMD3<Float>(0, 0, 1)
            let cam = view(s3.sim, memo: &m3, yaw: 0)
            BlueBelly.current = .off
            let a = render(c3, s3, cam: cam, neutral: false)
            var noise = 0
            for _ in 0..<3 { let a2 = render(c3, s3, cam: cam, neutral: false); for i in 0..<a.bgra.count { noise = max(noise, abs(Int(a.bgra[i]) - Int(a2.bgra[i]))) } }          // render-to-render noise of the same state (room dither / ripple)
            var worst = 0
            for v in BlueBelly.allCases.dropFirst() {
                BlueBelly.current = v
                let b = render(c3, s3, cam: cam, neutral: false)
                for i in 0..<a.bgra.count { worst = max(worst, abs(Int(a.bgra[i]) - Int(b.bgra[i]))) }
            }
            BlueBelly.current = .off
            NSLog("BLUEBELLY pip noise=%d worst=%d", noise, worst)
            XCTAssertLessThanOrEqual(worst, noise, "Pip (yellow) must not change with any blue-belly variant")
        }

        // boards
        func row(_ keys: [String]) -> [UIImage] { keys.flatMap { boards[$0] ?? [] } }
        try save(grid(row(["angle_front", "angle_34", "angle_side", "face_front"]), cols: 4), dir + "/OVERVIEW_\(Self.width).png")
        try save(grid(row(["angle_front", "angle_34", "angle_side", "angle_back"]), cols: 4), dir + "/BOARD_angles_\(Self.width).png")
        try save(grid(row(["walkfront", "walk", "walkside", "drag", "drag34"]), cols: 4), dir + "/BOARD_motion_\(Self.width).png")
        try save(grid(row(["sleep_front", "sleep_34", "sleep_side", "sleep_top"]), cols: 4), dir + "/BOARD_sleep_\(Self.width).png")
        try save(grid(row(["room", "landscape_crop", "picker_rest", "picker_orbit_front"]), cols: 4), dir + "/BOARD_context_\(Self.width).png")
        try save(grid(row(["roomfull", "landscape"]), cols: 4), dir + "/BOARD_room_landscape_full_\(Self.width).png")
        try save(grid(row(["picker_rest", "picker_orbit_front", "picker_orbit_side", "picker_orbit_back"]), cols: 4), dir + "/BOARD_picker_\(Self.width).png")
        try save(grid(row(["jersey", "jersey34", "mouth", "mouth34"]), cols: 4), dir + "/BOARD_clothes_mouth_\(Self.width).png")
        try save(grid(boards["tiers"] ?? [], cols: 3), dir + "/BOARD_tiers_\(Self.width).png")
        try save(grid(row(["face_front", "face_34", "face_side"]), cols: 4), dir + "/BOARD_face_\(Self.width).png")
    }

    // MARK: the poke "mustache": the real touch path vs the rig's direct press

    /// Drives the REAL touch code (TouchPlay.petFrame = what MelonStage calls every frame for a press-hold / stroke, with the real finger radius, dent depth,
    /// eased centre, skinner dent relaxation and normal smoothing; and SoftBody.beginGrab / moveGrab as the pick-up gesture does) and, for comparison, the
    /// capture rig's old direct fingertip-sphere poke (radius 0.34, depth 0.52, no skinner smoothing). Writes BOARD_poke_real_vs_rig.png and BOARD_squish.png.
    func testPokeRealVsRig() throws {
        let dir = try outDir()
        let ids = [0]
        let lab = makeLab(ids: ids, positions: [SIMD2(0.0, 0.6)]); let dr = dress(lab, ids); settle(lab, dr, ids)
        let r0 = lab.rigs[0]
        let c = try makeCtx(sim: r0.sim, W: 560, H: 560)
        let s = subj(lab, dr, ids)
        var memo = SIMD3<Float>(0, 0, 1)
        let rec = RecordingHapticSink()
        let driver = HapticDriver(sinks: [rec]); rec.clock = { 0 }
        let play = TouchPlay(haptics: driver); driver.enabled = true; driver.setWarm(true)
        var clock = 100.0; rec.clock = { clock }
        let surface = RestSurface(mesh: MotionRig.renderMesh)
        for _ in 0..<60 { r0.tick() }
        let camF = view(s.sim, memo: &memo, yaw: 0, dist: 3.0, lookY: 0.05)
        func ray(_ x: Float, _ y: Float) -> (o: SIMD3<Float>, d: SIMD3<Float>) {
            let e = BodyEllipsoid(sim: s.sim)
            let p = e.center + e.rot.act(SIMD3(x, y, 0))
            return (camF.pos, simd_normalize(p - camF.pos))
        }
        /// One stage frame of touch: petFrame (ray nil = no finger), then the brain / sim / jelly like the stage.
        func frame(_ rayIn: (o: SIMD3<Float>, d: SIMD3<Float>)?) {
            play.petFrame(dt: 1.0 / 60, now: clock, ray: rayIn, screen: nil, sim: s.sim, brain: s.brain, skinner: s.skinner, surface: surface)
            play.trackImpacts(now: clock, sim: s.sim)
            r0.tick(touched: play.contact)
            s.skinner.jelly.tick(brain: s.brain, sim: s.sim, dt: s.sim.stepDt)
            clock += 1.0 / 60
        }
        func settleOut() { for _ in 0..<240 { frame(nil) } }
        var rows: [(String, [UIImage])] = []     // each row: label + tiles (front, 3/4)
        func shotPair(_ label: String, variants: [(V, String)] = [(.off, "off")], name: String) throws -> [UIImage] {
            var out: [UIImage] = []
            for (yaw, vn) in [(Float(0), "front"), (Float(0.7), "3/4")] {
                let cam = view(s.sim, memo: &memo, yaw: yaw, dist: 3.0, lookY: 0.05)
                for (v, tag) in variants {
                    BlueBelly.current = v
                    let img = render(c, s, cam: cam, neutral: true)
                    try save(img.uiImage()!, dir + "/poke_\(name)_\(vn.replacingOccurrences(of: "/", with: ""))_\(tag).png")
                    out.append(labelled(img.uiImage()!, "\(label) \(vn) [\(tag)]", bar: 36))
                }
            }
            BlueBelly.current = .off
            return out
        }
        var squishBoard: [UIImage] = []
        let allVariants = Self.variants
        // real press-and-hold at three spots, then let go
        for (spot, x, y) in [("belly", Float(0), Float(-0.30)), ("mouth level", 0, 0), ("cheek", 0.40, 0.15)] {
            let tag = spot.replacingOccurrences(of: " ", with: "")
            for _ in 0..<12 { frame(nil) }
            var tiles: [UIImage] = []
            for k in 0..<110 {
                frame(ray(x, y))
                if k == 29 { tiles += try shotPair("REAL press \(spot) 0.5 s", name: tag + "_p05") }
                if k == 109 {
                    tiles += try shotPair("REAL press \(spot) 1.8 s", name: tag + "_p18")
                    if spot != "cheek" { squishBoard += try shotPair("REAL press \(spot) 1.8 s", variants: allVariants, name: tag + "_v") }
                    NSLog("BLUEBELLY real press %@: pressDepth=%.3f ramp=%.2f contact=%d zone=%@ smoothing=%.2f", spot, s.sim.pressDepth, play.ramp, play.contact ? 1 : 0, "\(play.zone)", s.skinner.normalSmoothing)
                }
            }
            for k in 0..<30 {
                frame(nil)
                if k == 5 { tiles += try shotPair("REAL just released (+0.1 s)", name: tag + "_r01") }
                if k == 17 { tiles += try shotPair("REAL released +0.3 s", name: tag + "_r03") }
            }
            rows.append(("real " + spot, tiles))
            settleOut()
        }
        // a real stroke across the body (drag)
        do {
            var tiles: [UIImage] = []
            for _ in 0..<10 { frame(nil) }
            for k in 0..<100 {
                let x = -0.32 + 0.64 * Float(k) / 99
                frame(ray(x, -0.10))
                if k == 50 { tiles += try shotPair("REAL stroke (mid)", name: "stroke_mid") }
            }
            for k in 0..<12 { frame(nil); if k == 5 { tiles += try shotPair("REAL stroke released", name: "stroke_rel") } }
            rows.append(("real stroke", tiles))
            settleOut()
        }
        // the two-finger cheek pinch (TouchPlay.cheeksFrame: two fingertip spheres + a smooth skin squeeze), as the stage drives it
        do {
            var tiles: [UIImage] = []
            for _ in 0..<10 { frame(nil) }
            func cframe(_ rays: [(o: SIMD3<Float>, d: SIMD3<Float>)]?, gap: Float) {
                play.cheeksFrame(dt: 1.0 / 60, now: clock, rays: rays, gap: gap, sim: s.sim, brain: s.brain, skinner: s.skinner, surface: surface)
                r0.tick(touched: rays != nil); s.skinner.jelly.tick(brain: s.brain, sim: s.sim, dt: s.sim.stepDt); clock += 1.0 / 60
            }
            for k in 0..<60 { let g = 0.5 - 0.3 * Float(k) / 60; cframe([ray(-g, 0.25), ray(g, 0.25)], gap: g * 400) }
            for k in 0..<60 { cframe([ray(-0.2, 0.25), ray(0.2, 0.25)], gap: 80); if k == 40 { tiles += try shotPair("REAL two-finger cheek pinch", name: "cheeks_pinch") } }
            for k in 0..<30 { cframe(nil, gap: 0); if k == 6 { tiles += try shotPair("REAL cheeks released (+0.1 s)", name: "cheeks_rel") } }
            rows.append(("real cheeks", tiles))
            for _ in 0..<240 { cframe(nil, gap: 0) }
        }
        // the pick-up gesture's grab (SoftBody.beginGrab radius 0.4 + moveGrab), held on the belly and pulled
        do {
            var tiles: [UIImage] = []
            let (cen, fwd) = pose(s.sim, memo: &memo)
            let hit = SIMD3(cen.x, s.sim.floorY + 0.36, cen.z) + fwd * 0.6
            s.sim.beginGrab(hit: hit, radius: 0.4)
            let side = SIMD3<Float>(fwd.z, 0, -fwd.x)
            for i in 0...45 {
                let k = Float(i) / 45
                s.sim.moveGrab(target: hit + side * (0.5 * k) + SIMD3(0, 0.45 * k, 0), rot: nil)
                r0.tick(touched: true); s.skinner.jelly.tick(brain: s.brain, sim: s.sim, dt: s.sim.stepDt)
                play.heldFrame(dt: 1.0 / 60, now: clock, grabbing: true, liftHeight: 0.3 * k, sim: s.sim, brain: s.brain, skinner: s.skinner); clock += 1.0 / 60
            }
            tiles += try shotPair("REAL pick-up grab held", name: "grab_held")
            s.sim.endGrab(); play.heldFrame(dt: 1.0 / 60, now: clock, grabbing: false, liftHeight: 0, sim: s.sim, brain: s.brain, skinner: s.skinner)
            for k in 0..<30 { frame(nil); if k == 8 { tiles += try shotPair("REAL pick-up dropped (+0.15 s)", name: "grab_drop") } }
            rows.append(("real pick-up", tiles))
            settleOut()
        }
        // the rig's old direct poke (what the earlier board showed): a big sphere, 0.52 deep, no skinner smoothing
        do {
            var tiles: [UIImage] = []
            let (cen, fwd) = pose(s.sim, memo: &memo)
            let radius: Float = 0.34
            for i in 0...50 {
                let depth = 0.52 * Float(i) / 50
                s.sim.setPress(center: SIMD3(cen.x, s.sim.floorY + 0.38, cen.z) + fwd * (0.62 + radius - depth), radius: radius)
                r0.tick(); s.skinner.jelly.tick(brain: s.brain, sim: s.sim, dt: s.sim.stepDt)
            }
            tiles += try shotPair("RIG direct sphere (r .34, depth .52)", name: "rig")
            s.sim.endPress(); s.skinner.normalSmoothing = 0
            rows.append(("rig direct", tiles))
        }
        BlueBelly.current = .off
        // boards: one row per case; tiles are front / 3-4 pairs per moment
        var all: [UIImage] = []
        for (_, tiles) in rows { all += tiles }
        try save(grid(all, cols: 4), dir + "/BOARD_poke_real_vs_rig_\(Self.width).png")
        try save(grid(squishBoard, cols: 4), dir + "/BOARD_squish_\(Self.width).png")
    }

    /// Always runs: the default is off, and only the baby blue palette ever gets a mode.
    func testOnlyBlueGetsIt() {
        XCTAssertEqual(BlueBelly.current, .off)
        for v in BlueBelly.allCases {
            BlueBelly.current = v
            XCTAssertEqual(BlueBelly.mode(for: PaletteKey.blue.palette), Float(v.rawValue))
            XCTAssertEqual(BlueBelly.mode(for: PaletteKey.yellow.palette), 0)
            XCTAssertEqual(BlueBelly.mode(for: PaletteKey.blush.palette), 0)
            XCTAssertEqual(BlueBelly.mode(for: JellyPalettes.green), 0)
            XCTAssertEqual(BlueBelly.mode(for: JellyPalettes.lavender), 0)
            for c in ParkColour.allCases { XCTAssertEqual(BlueBelly.mode(for: JellyPalettes.park(c)), 0, "\(c)") }
        }
        BlueBelly.current = .off
        XCTAssertEqual(BlueBelly.parse("B1"), .bellySubtle); XCTAssertEqual(BlueBelly.parse("a"), .front); XCTAssertEqual(BlueBelly.parse("off"), .off)
    }
}
