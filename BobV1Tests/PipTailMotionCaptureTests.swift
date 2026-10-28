//
//  PipTailMotionCaptureTests.swift
//  Not a regression test: visual capture of Pip's tail MOTION (walk, run, stop-settle, happy wag, mood carriage, the tail emotes) with the spikes drawn.
//  Env-gated on TAILMOTION_DIR (xcodebuild: TEST_RUNNER_TAILMOTION_DIR). Per scenario it writes frames (frames/<scenario>_<cam>/NNNN.png, 30 fps) and a contact
//  sheet <scenario>_<cam>.png; the numbers (tail floor clearance, spike seat, body clearance) go to stats.txt. TAILMOTION_ONLY=walk,run limits the run.
//  It only uses code that exists on the base commit (emotes are started by raw value), so the same file captures the "before".
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class PipTailMotionCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0); DayClock.shared.forcedHour = 12 }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DayClock.shared.forcedHour = 12 }

    // MARK: plumbing

    private func dir() throws -> String {
        let env = ProcessInfo.processInfo.environment
        guard let d = env["TAILMOTION_DIR"], !d.isEmpty else { throw XCTSkip("TAILMOTION_DIR not set") }
        try FileManager.default.createDirectory(atPath: d + "/frames", withIntermediateDirectories: true)
        return d
    }
    private func wanted(_ name: String) -> Bool {
        guard let only = ProcessInfo.processInfo.environment["TAILMOTION_ONLY"], !only.isEmpty else { return true }
        return only.split(separator: ",").contains { name.hasPrefix($0) }
    }

    final class Ctx { let ren: MelonRenderer; let target: MTLTexture; let W: Int, H: Int
        init(ren: MelonRenderer, target: MTLTexture, W: Int, H: Int) { self.ren = ren; self.target = target; self.W = W; self.H = H } }
    private func makeCtx(sim: SoftBody, W: Int, H: Int) throws -> Ctx {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: sim.edges, particleCount: sim.n, game: true, bodyCount: 1), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        Self.keep.append(ren)
        return Ctx(ren: ren, target: device.makeTexture(descriptor: td)!, W: W, H: H)
    }

    @MainActor final class Setup { let lab: SocialTests.Lab; let worn = WornSet(), feats = FeatureSet(); var skin: [Float]
        var rig: MotionRig { lab.rigs[0] }
        init(lab: SocialTests.Lab) { self.lab = lab; skin = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6) } }

    private func makeSetup(outfit: [WearSlot: WearLook] = [:], id: Int = 1) -> Setup {
        let lab = SocialTests.Lab(n: 1, positions: [SIMD2(0.4, 0.6)], quiet: true, seed: 3)
        SocialTests.keep.append(lab)
        let r = lab.rigs[0]
        r.skinner.autoBlink = false
        r.brain.feature = JellyRoster.feature(id); r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        WearBody.install(MotionRig.renderMesh)
        let s = Setup(lab: lab)
        s.worn.body = WearBody.shared; s.worn.soundOn = false; s.feats.body = WearBody.shared
        Self.keep.append(s.worn); Self.keep.append(s.feats); Self.keep.append(s)
        r.brain.autonomy = false; r.brain.expr.enabled = false
        outfitStore[ObjectIdentifier(s)] = outfit
        for _ in 0..<40 { step(s, id: id) }
        for _ in 0..<40 { step(s, id: id) }
        return s
    }
    private var outfitStore: [ObjectIdentifier: [WearSlot: WearLook]] = [:]

    /// One game tick: brain + sim + jelly layer + wardrobe + the skin (one skinner update per tick, as the game's 60 Hz render).
    private func step(_ s: Setup, id: Int = 1) {
        let r = s.rig
        s.lab.tick(watching: false)
        r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
        let outfit = outfitStore[ObjectIdentifier(s)] ?? [:]
        s.worn.tick(id: 0, brain: r.brain, sim: r.sim, outfit: outfit, role: .none, hideAll: false, dt: 1.0 / 60)
        var art: [String] = []
        for sl in WearSlot.allCases where sl != .feet { if let l = s.worn.shown(0, sl), !l.art.isEmpty { art.append(l.art) } }
        s.feats.tick(id: 0, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(id), worn: art, hideAll: false, dt: 1.0 / 60)
        if let sl = s.feats.slot(0) { s.worn.setArtOverride(0, sl.fit.hatVariant); r.brain.wingsFolded = sl.fit.folded; r.brain.wingFlapLimit = sl.fit.flapMax }
        r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &s.skin)
    }

    // MARK: render

    private func render(_ c: Ctx, _ s: Setup, cam: CameraState) -> LockImage {
        let ren = c.ren, W = c.W, H = c.H, r = s.rig
        let vc = MotionRig.renderMesh.vertexCount
        func shot(visible: Bool) -> LockImage {
            ren.beginFrame()
            ren.setHidden(!visible, body: 0)
            let p = ren.dynPointer(body: 0)
            if visible { s.skin.withUnsafeBufferPointer { p.update(from: $0.baseAddress!, count: vc * 6) } }
            else { for v in 0..<vc { p[6 * v] = 0; p[6 * v + 1] = -60; p[6 * v + 2] = 0; p[6 * v + 3] = 0; p[6 * v + 4] = 1; p[6 * v + 5] = 0 } }
            if visible {
                var f = s.skin.withUnsafeBufferPointer { p in s.worn.frame(theme: ren.room!.theme, time: 0.4) { _ in p.baseAddress } }
                let ff = s.skin.withUnsafeBufferPointer { p in s.feats.frame { _ in p.baseAddress } }
                let base = UInt32(f.opaque.vertices.count)
                f.opaque.vertices += ff.vertices; f.opaque.indices += ff.indices.map { $0 + base }
                ren.room!.setWear(opaque: f.opaque, translucent: f.translucent, bounds: [])
                ren.room!.setShoes(RoomMesh())
                ren.setJersey(s.worn.jersey(0), body: 0)
                ren.setMouth(r.brain.mouthOpen, body: 0)
            } else {
                ren.room!.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []); ren.room!.setShoes(RoomMesh()); ren.setJersey(nil, body: 0)
            }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = JellyRoster.palette(1) ?? PaletteKey.blue.palette
            ren.setPalette(pal, body: 0)
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: GameCamera.light(centroids: [r.sim.centroid()]), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: c.target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { c.target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            return LockImage(w: W, h: H, bgra: px)
        }
        ren.dayHourOverride = 12
        return shot(visible: true)
    }

    // MARK: cameras

    private func camera(eye: SIMD3<Float>, target: SIMD3<Float>, aspect: Float, up: SIMD3<Float> = SIMD3(0, 1, 0)) -> CameraState {
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: up)
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        return cam
    }
    enum Cam: String { case game, close, top, side }
    private func cam(_ k: Cam, _ s: Setup, memo: inout SIMD3<Float>, aspect: Float) -> CameraState {
        let p = s.rig.sim.bodyPose(iterations: 3)
        var f = p.rotation.act(SIMD3<Float>(0, 0, 1)); f.y = 0
        if simd_length(f) > 0.3 { memo = simd_normalize(f) }
        let c = p.centroid
        switch k {
        case .game: return GameCamera.camera(aspect: aspect)
        case .close:
            let t = SIMD3(c.x - memo.x * 0.5, 0.2, c.z - memo.z * 0.5)
            let yaw: Float = 2.45                       // 3/4 back
            let dir = SIMD3<Float>(memo.x * cosf(yaw) + memo.z * sinf(yaw), 0, -memo.x * sinf(yaw) + memo.z * cosf(yaw))
            return camera(eye: t + dir * 3.0 + SIMD3(0, 0.6, 0), target: t, aspect: aspect)
        case .side:
            let t = SIMD3(c.x - memo.x * 0.35, c.y + 0.1, c.z - memo.z * 0.35)
            let yaw: Float = .pi / 2
            let dir = SIMD3<Float>(memo.x * cosf(yaw) + memo.z * sinf(yaw), 0, -memo.x * sinf(yaw) + memo.z * cosf(yaw))
            return camera(eye: t + dir * 2.8 + SIMD3(0, 0.35, 0), target: t, aspect: aspect)
        case .top:
            let t = SIMD3(c.x - memo.x * 0.3, 0.2, c.z - memo.z * 0.3)
            return camera(eye: t + SIMD3(0, 4.0, 0), target: t, aspect: aspect, up: memo)
        }
    }
    /// Crops a square around the body for the game camera (the full frame is a tall phone frame).
    private func crop(_ img: LockImage, _ cam: CameraState, _ s: Setup, size: Int, out: Int) -> UIImage {
        let c = s.rig.sim.bodyPose(iterations: 3).centroid
        let clip = cam.viewProj * SIMD4<Float>(c.x, c.y, c.z, 1)
        let nx = clip.x / clip.w, ny = clip.y / clip.w
        let cx = Int((nx * 0.5 + 0.5) * Float(img.w)), cy = Int((1 - (ny * 0.5 + 0.5)) * Float(img.h))
        let x0 = max(0, min(img.w - size, cx - size / 2)), y0 = max(0, min(img.h - size, cy - size / 2))
        guard let cg = img.uiImage()?.cgImage?.cropping(to: CGRect(x: x0, y: y0, width: size, height: size)) else { return img.uiImage()! }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: fmt).image { _ in UIImage(cgImage: cg).draw(in: CGRect(x: 0, y: 0, width: out, height: out)) }
    }

    // MARK: sheets

    private func label(_ img: UIImage, _ text: String) -> UIImage {
        let w = img.size.width, h = img.size.height, bar: CGFloat = 26
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + bar), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + bar))
            (text as NSString).draw(at: CGPoint(x: 6, y: 5), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.white])
            img.draw(in: CGRect(x: 0, y: bar, width: w, height: h))
        }
    }
    private func grid(_ imgs: [UIImage], cols: Int) -> UIImage {
        let cw = imgs.map { $0.size.width }.max() ?? 0, ch = imgs.map { $0.size.height }.max() ?? 0
        let rows = (imgs.count + cols - 1) / cols
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: cw * CGFloat(cols), height: ch * CGFloat(rows)), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: cw * CGFloat(cols), height: ch * CGFloat(rows)))
            for (i, im) in imgs.enumerated() { im.draw(at: CGPoint(x: CGFloat(i % cols) * cw, y: CGFloat(i / cols) * ch)) }
        }
    }

    // MARK: stats

    struct Stats { var series: [String] = [], tipXLo: Float = 9, tipXHi: Float = -9, minY: Float = 9, maxTipDeg: Float = 0, minBodySDF: Double = 9, frames = 0, spikeOff: Float = 0 }
    private func measure(_ s: Setup, _ st: inout Stats) {
        let sk = s.rig.skinner
        guard sk.tailFirst >= 0, sk.tailOn else { return }
        let f = sk.tailFirst, n = TailBean.vertexCount
        let pose = s.rig.sim.bodyPose(iterations: 3)
        let R = pose.rotation.inverse
        for i in 0..<n {
            let p = SIMD3(s.skin[6 * (f + i)], s.skin[6 * (f + i) + 1], s.skin[6 * (f + i) + 2])
            st.minY = min(st.minY, p.y - s.rig.sim.floorY)
            // visible tail (past the back), in the body's rest frame
            if i > 1 {
                let ring = (i - 1) / TailBean.around
                if ring >= 12 && ring < TailBean.rings {
                    let q = R.act(p - pose.centroid) + s.rig.sim.restCentroid
                    st.minBodySDF = min(st.minBodySDF, BobForm.sdf(SIMD3<Double>(Double(q.x), Double(q.y), Double(q.z))))
                }
            }
        }
        let tp = SIMD3(s.skin[6 * (f + n - 1)], s.skin[6 * (f + n - 1) + 1], s.skin[6 * (f + n - 1) + 2])
        let tl = R.act(tp - pose.centroid); st.tipXLo = min(st.tipXLo, tl.x); st.tipXHi = max(st.tipXHi, tl.x)
        func ringC(_ r: Int) -> SIMD3<Float> { var c = SIMD3<Float>.zero; for j in 0..<TailBean.around { let o = 6 * (f + 1 + TailBean.around * r + j); c += SIMD3(s.skin[o], s.skin[o + 1], s.skin[o + 2]) }; return R.act(c / Float(TailBean.around) - pose.centroid) }
        let mid = ringC(15), tl2 = ringC(33)
        st.series.append(String(format: "%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f", st.frames, mid.x, mid.y, mid.z, tl2.x, tl2.y, tl2.z))
        st.maxTipDeg = max(st.maxTipDeg, abs(sk.tailYaw))
        st.frames += 1
    }
    private func appendStats(_ dir: String, _ line: String) {
        let path = dir + "/stats.txt"
        let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        try? (old + line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: scenarios

    struct Scenario { var name: String; var cams: [Cam] = [.game, .close]; var warm: Float = 0; var seconds: Float; var outfit: [WearSlot: WearLook] = [:]
        var id = 1
        var start: (Setup) -> Void
        var until: ((Setup) -> Bool)? = nil
        var sheetFrames = 8 }

    private func idle(_ raw: String) -> (Setup) -> Void { { s in
        let b = s.rig.brain; b.idleForced = true
        guard let k = IdleKind(rawValue: raw) else { XCTFail("no idle kind \(raw)"); return }
        XCTAssertTrue(b.idleStart(k, s.rig.sim), "idleStart \(raw)") } }
    private func walk(_ dx: Float, _ dz: Float, hurry: Bool) -> (Setup) -> Void { { s in
        let r = s.rig, p = r.sim.bodyPose(iterations: 3).centroid
        r.brain.hurry = hurry
        r.brain.script = .walk(target: SIMD2(p.x + dx, p.z + dz), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 } }

    private func scenarios() -> [Scenario] {
        [
            Scenario(name: "walk", warm: 0.9, seconds: 2.6, start: walk(-4, 0.2, hurry: false)),
            Scenario(name: "run", warm: 0.7, seconds: 1.8, start: walk(-4.2, 0.2, hurry: true)),
            Scenario(name: "stop", seconds: 3.2, start: walk(-1.5, 0.1, hurry: false), sheetFrames: 10),
            Scenario(name: "wag", warm: 0.4, seconds: 2.4, start: { s in let b = s.rig.brain; b.idleForced = true; b.expr.enabled = true; b.face(.happy, hold: 9) }),
            Scenario(name: "walkhappy", warm: 0.9, seconds: 2.4, start: { [self] s in let b = s.rig.brain; b.idleForced = true; b.expr.enabled = true; b.face(.happy, hold: 9); self.walk(-4, 0.2, hurry: false)(s) }),
            Scenario(name: "moodhigh", cams: [.close, .side], warm: 1.0, seconds: 1.0, start: { s in s.rig.brain.idleMood = .happy }),
            Scenario(name: "moodneutral", cams: [.close, .side], warm: 1.0, seconds: 1.0, start: { s in s.rig.brain.idleMood = .okay }),
            Scenario(name: "mooddroop", cams: [.close, .side], warm: 1.5, seconds: 1.0, start: { s in s.rig.brain.idleMood = .grumpy; s.rig.brain.idleForced = true; s.rig.brain.expr.enabled = true; s.rig.brain.face(.worried, hold: 9) }),
            Scenario(name: "hmph", cams: [.game, .close], seconds: 2.2, start: idle("hmph")),
            Scenario(name: "chase", seconds: 5.5, start: idle("tail"), until: { $0.rig.brain.idleState.kind == nil }, sheetFrames: 12),
            Scenario(name: "thump", cams: [.game, .close, .side], seconds: 6.0, start: idle("tailThump"), until: { $0.rig.brain.idleState.kind == nil }, sheetFrames: 12),
            Scenario(name: "hug", cams: [.game, .close, .top, .side], seconds: 7.0, start: idle("tailHug"), until: { $0.rig.brain.idleState.kind == nil }, sheetFrames: 12),
            Scenario(name: "hugwear", cams: [.close], seconds: 7.0, outfit: [.neck: .scarfCosy, .body: .backpackSky], start: idle("tailHug"), until: { $0.rig.brain.idleState.kind == nil }, sheetFrames: 8),
        ]
    }

    func testCaptureScenarios() throws {
        let d = try dir()
        let first = makeSetup()
        let W = 300, H = 300, GW = 414, GH = 900
        let ctxClose = try makeCtx(sim: first.rig.sim, W: W, H: H)
        let ctxGame = try makeCtx(sim: first.rig.sim, W: GW, H: GH)
        var summary = ""
        for sc in scenarios() where wanted(sc.name) {
            let s = makeSetup(outfit: sc.outfit, id: sc.id)
            sc.start(s)
            var st = Stats()
            var memo = SIMD3<Float>(0, 0, 1)
            var frames: [Cam: [UIImage]] = [:]
            var tick = 0, rec = 0
            let warmTicks = Int(sc.warm * 60), total = warmTicks + Int(sc.seconds * 60)
            var endTick = total
            while tick < total {
                step(s); tick += 1
                measure(s, &st)
                if let u = sc.until, tick > 20, u(s), endTick == total { endTick = min(total, tick + 50) }
                if tick >= endTick { break }
                if tick > warmTicks, tick % 2 == 0 {
                    for k in sc.cams {
                        let ctx = k == .game ? ctxGame : ctxClose
                        let aspect = Float(ctx.W) / Float(ctx.H)
                        let cm = cam(k, s, memo: &memo, aspect: aspect)
                        let img = render(ctx, s, cam: cm)
                        let ui = k == .game ? crop(img, cm, s, size: 170, out: 300) : img.uiImage()!
                        frames[k, default: []].append(ui)
                        let fdir = d + "/frames/\(sc.name)_\(k.rawValue)"
                        try? FileManager.default.createDirectory(atPath: fdir, withIntermediateDirectories: true)
                        try? ui.pngData()!.write(to: URL(fileURLWithPath: String(format: "%@/%04d.png", fdir, rec)))
                    }
                    rec += 1
                }
            }
            for (k, imgs) in frames {
                let n = imgs.count
                let pick = (0..<min(sc.sheetFrames, n)).map { imgs[$0 * n / min(sc.sheetFrames, n)] }
                let cells = pick.enumerated().map { label($0.element, "\(sc.name) \(k.rawValue) f\($0.offset * n / max(1, pick.count))/\(n)") }
                try grid(cells, cols: 4).pngData()!.write(to: URL(fileURLWithPath: d + "/\(sc.name)_\(k.rawValue).png"))
            }
            try? ("frame,midX,midY,midZ,tipX,tipY,tipZ\n" + st.series.joined(separator: "\n")).write(toFile: d + "/\(sc.name)_series.csv", atomically: true, encoding: .utf8)
            let line = String(format: "%@: frames=%d minTailY=%.4f maxTipYaw=%.1f minBodySDF=%.3f tipX(body frame)=%.2f...%.2f", sc.name, st.frames, st.minY, st.maxTipDeg, st.minBodySDF, st.tipXLo, st.tipXHi)
            summary += line + "\n"; appendStats(d, line)
            XCTAssertGreaterThan(st.minY, -0.003, "\(sc.name): tail went through the floor")
        }
        print(summary)
    }
}
