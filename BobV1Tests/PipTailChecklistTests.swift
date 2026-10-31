//
//  PipTailChecklistTests.swift
//  Not a regression test: a REUSABLE visual-verification harness for Pip's body-mesh dino tail + orange ridge spikes. Env-gated on TAILCHECK_DIR
//  (xcodebuild passes it as TEST_RUNNER_TAILCHECK_DIR) and writes one labelled contact sheet per checklist item:
//    angles.png    rest views (front, 3/4 L/R, side L/R, 3/4 back, back, TOP) on a neutral backdrop and in the room
//    motions.png   sway, walk, run, turn, sit, sleep, hop, joy jump, cartwheel, backflip, eating, drinking (real brain / care paths)
//    wear.png      enclosing hat, crown, backpack, hero cape, hoodie, scarf from 3/4 back + side
//    others.png    Bob / Moss / Lavender from 3/4 back + top in the real brain path AND the bare MotionRig paths (no tail / back swell allowed)
//    picker.png    the Lemon Drop species-picker framing at its resting yaw + orbit yaws
//    closeups.png  zoomed back/tail junction + floor contact from back 3/4, side and top
//    walk_bob_vs_pip.png / walk_bob.txt   head bounce while walking: Pip vs Bob (+ numbers for several variants)
//  TAILCHECK_ONLY=angles,motions,... limits the run. It only uses the public tail / skinner state, so it runs against whatever tail code is present.
//  One REAL regression test lives here too (always runs): testPipHatStaysOnHisHeadWhileWalking.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class PipTailChecklistTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    typealias Outfit = [WearSlot: WearLook]

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0); DayClock.shared.forcedHour = 12 }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DayClock.shared.forcedHour = 12 }

    // MARK: plumbing

    private func dir(_ item: String) throws -> String {
        let env = ProcessInfo.processInfo.environment
        guard let d = env["TAILCHECK_DIR"], !d.isEmpty else { throw XCTSkip("TAILCHECK_DIR not set") }
        if let only = env["TAILCHECK_ONLY"], !only.isEmpty, !only.split(separator: ",").contains(where: { item.hasPrefix($0) }) { throw XCTSkip("TAILCHECK_ONLY excludes \(item)") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    struct Char { var id: Int; var outfit: Outfit = [:]; var featureOn = true }
    /// How the tail / feature state of a rig is set up. real = the game (feature from the roster, configureTail, brain drives tailOn); bare = a plain
    /// MotionRig (no configureTail at all, tailFirst = -1); bareCfg = configureTail called but nothing else; bareForced = configureTail + tailOn forced true
    /// (the testPipTailDbg setup), no brain ticks afterwards.
    enum TailPath: String { case real, bare, bareCfg, bareForced }

    final class Ctx { let ren: MelonRenderer; let target: MTLTexture; let W: Int, H: Int
        init(ren: MelonRenderer, target: MTLTexture, W: Int, H: Int) { self.ren = ren; self.target = target; self.W = W; self.H = H } }

    private func makeCtx(sim: SoftBody, W: Int, H: Int, bodies: Int = 1) throws -> Ctx {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: sim.edges, particleCount: sim.n, game: true, bodyCount: bodies), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        let c = Ctx(ren: ren, target: device.makeTexture(descriptor: td)!, W: W, H: H)
        Self.keep.append(ren)
        return c
    }

    private func makeLab(_ chars: [Char], path: TailPath = .real, positions: [SIMD2<Float>]? = nil, seed: UInt64 = 3) -> SocialTests.Lab {
        let pos = positions ?? chars.indices.map { SIMD2(0.2 + Float($0) * 1.0, 0.6) }
        let lab = SocialTests.Lab(n: pos.count, positions: pos, quiet: true, seed: seed)
        SocialTests.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.skinner.autoBlink = false
            switch path {
            case .real: r.brain.feature = JellyRoster.feature(chars[k].id); r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            case .bare: break
            case .bareCfg, .bareForced: r.skinner.configureTail(MotionRig.renderMesh)
            }
        }
        WearBody.install(MotionRig.renderMesh)
        return lab
    }

    final class Dressed { var worn: [WornSet] = [], feats: [FeatureSet] = [] }
    private func dress(_ lab: SocialTests.Lab, _ chars: [Char]) -> Dressed {
        let d = Dressed()
        for (k, r) in lab.rigs.enumerated() {
            let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; Self.keep.append(w)
            let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f)
            d.worn.append(w); d.feats.append(f)
            for _ in 0..<3 { wearTick(w, f, r.brain, r.sim, chars[k]) }
        }
        return d
    }
    private func wearTick(_ w: WornSet, _ f: FeatureSet, _ brain: BlobBrain, _ sim: SoftBody, _ c: Char) {
        w.tick(id: 0, brain: brain, sim: sim, outfit: c.outfit, role: .none, hideAll: false, dt: 1.0 / 60)
        var art: [String] = []
        for s in WearSlot.allCases where s != .feet { if let l = w.shown(0, s), !l.art.isEmpty { art.append(l.art) } }
        f.tick(id: 0, brain: brain, sim: sim, feature: c.featureOn ? JellyRoster.feature(c.id) : .none, worn: art, hideAll: false, dt: 1.0 / 60)
        if let s = f.slot(0) { w.setArtOverride(0, s.fit.hatVariant); brain.wingsFolded = s.fit.folded; brain.wingFlapLimit = s.fit.flapMax }
    }
    /// One game-ish step of a lab (brains + sims + the jelly layer + wardrobe / features).
    private func step(_ lab: SocialTests.Lab, _ d: Dressed, _ chars: [Char], brains: Bool = true) {
        if brains { lab.tick(watching: false) } else { for r in lab.rigs { r.sim.step() } }
        for (k, r) in lab.rigs.enumerated() { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); wearTick(d.worn[k], d.feats[k], r.brain, r.sim, chars[k]) }
    }
    private func settle(_ lab: SocialTests.Lab, _ d: Dressed, _ chars: [Char], frames: Int = 40, brains: Bool = true) {
        for r in lab.rigs { r.brain.autonomy = false; r.brain.expr.enabled = false }
        for _ in 0..<frames { step(lab, d, chars, brains: brains) }
        for r in lab.rigs { _ = skin(r.skinner, r.sim); _ = skin(r.skinner, r.sim); for _ in 0..<30 { _ = skin(r.skinner, r.sim) } }          // the tail eases in over 0.15 s of skinner updates
    }
    private func skin(_ s: Skinner, _ sim: SoftBody) -> [Float] {
        var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        s.update(x: sim.x, index: MotionRig.renderMesh.index, into: &d)
        return d
    }

    // MARK: render

    struct Subj { let skinner: Skinner; let sim: SoftBody; let brain: BlobBrain; let char: Char; let worn: WornSet; let feats: FeatureSet; let body: Int }
    private func subj(_ lab: SocialTests.Lab, _ d: Dressed, _ chars: [Char], _ k: Int = 0) -> Subj {
        Subj(skinner: lab.rigs[k].skinner, sim: lab.rigs[k].sim, brain: lab.rigs[k].brain, char: chars[k], worn: d.worn[k], feats: d.feats[k], body: 0)
    }

    /// Renders one Jelbie (others hidden): in the room, or (neutral) cut out by differencing against the empty room and pasted on a flat light backdrop.
    private func render(_ c: Ctx, _ s: Subj, cam: CameraState, neutral: Bool, prep: ((MelonRenderer) -> Void)? = nil) -> LockImage {
        let ren = c.ren, W = c.W, H = c.H
        let vc = MotionRig.renderMesh.vertexCount
        func shot(visible: Bool) -> LockImage {
            ren.beginFrame()
            for b in 0..<ren.bodyCount {
                ren.setHidden(!(b == s.body && visible), body: b)
                let p = ren.dynPointer(body: b)
                if b == s.body && visible { s.skinner.update(x: s.sim.x, index: MotionRig.renderMesh.index, into: p) }
                else { for v in 0..<vc { p[6 * v] = 0; p[6 * v + 1] = -60; p[6 * v + 2] = 0; p[6 * v + 3] = 0; p[6 * v + 4] = 1; p[6 * v + 5] = 0 } }
            }
            if visible {
                let sk = skin(s.skinner, s.sim)
                if s.worn.shown(0, .hands) != nil { s.worn.setArms(0, GameCare.armFrames(brain: s.brain, sim: s.sim)) }
                var f = sk.withUnsafeBufferPointer { p in s.worn.frame(theme: ren.room!.theme, time: 0.4) { _ in p.baseAddress } }
                let ff = sk.withUnsafeBufferPointer { p in s.feats.frame { _ in p.baseAddress } }
                let base = UInt32(f.opaque.vertices.count)
                f.opaque.vertices += ff.vertices; f.opaque.indices += ff.indices.map { $0 + base }
                let sb = RoomMeshBuilder(); sb.material = .plain
                if let look = s.char.outfit[.feet], let beans = GameCare.footBeans(brain: s.brain, sim: s.sim, skinner: s.skinner) {
                    for side in 0..<2 { ShoeModel.build(look, bean: beans[side], floorY: s.sim.floorY, time: 0.4, side: side, body: JellyRoster.palette(s.char.id)?.flesh ?? SIMD3(0.35, 0.5, 0.9), gpuPaint: false, into: sb) }
                }
                ren.room!.setWear(opaque: f.opaque, translucent: f.translucent, bounds: [])
                ren.room!.setShoes(sb.mesh)
                ren.setJersey(s.worn.jersey(0), body: s.body)
                ren.setMouth(s.brain.mouthOpen, body: s.body)
            } else {
                ren.room!.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []); ren.room!.setShoes(RoomMesh()); ren.setJersey(nil, body: s.body)
            }
            prep?(ren)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = JellyRoster.palette(s.char.id) ?? PaletteKey.blue.palette
            ren.setPalette(pal, body: s.body)
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
        _ = shot(visible: false)
        let b = shot(visible: true)
        guard neutral else { return b }
        let empty = shot(visible: false)
        var out = b
        for p in 0..<(W * H) {
            var dd = 0
            for k in 0..<3 { dd = max(dd, abs(Int(b.bgra[4 * p + k]) - Int(empty.bgra[4 * p + k]))) }
            if dd <= 3 { out.bgra[4 * p] = 236; out.bgra[4 * p + 1] = 232; out.bgra[4 * p + 2] = 228; out.bgra[4 * p + 3] = 255 }          // light warm grey (bgra)
        }
        return out
    }

    // MARK: cameras

    private func lookCamera(target: SIMD3<Float>, dir: SIMD3<Float>, dist: Float, aspect: Float = 1, lift: Float = 0.1, up: SIMD3<Float> = SIMD3(0, 1, 0)) -> CameraState {
        let eye = target + dir * dist + SIMD3(0, dist * lift, 0)
        return camera(eye: eye, target: target, aspect: aspect, up: up)
    }
    private func camera(eye: SIMD3<Float>, target: SIMD3<Float>, aspect: Float = 1, up: SIMD3<Float> = SIMD3(0, 1, 0)) -> CameraState {
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: up)
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        return cam
    }
    /// Body centre + horizontal facing (falls back to `memo` when the body lies flat and the face normal is vertical).
    private func pose(_ sim: SoftBody, memo: inout SIMD3<Float>) -> (c: SIMD3<Float>, fwd: SIMD3<Float>) {
        let p = sim.bodyPose(iterations: 3)
        var f = p.rotation.act(SIMD3<Float>(0, 0, 1)); f.y = 0
        if simd_length(f) > 0.3 { memo = simd_normalize(f) }
        return (p.centroid, memo)
    }
    struct View { var name: String; var yaw: Float; var dist: Float = 4.1; var lookY: Float = 0.2; var lookBack: Float = 0.3; var lift: Float = 0.12; var top = false; var floorLook = false }
    private func cam(_ v: View, _ sim: SoftBody, memo: inout SIMD3<Float>) -> CameraState {
        let (c, fwd) = pose(sim, memo: &memo)
        let ty = v.floorLook ? sim.floorY + 0.12 : c.y + v.lookY
        let t = SIMD3(c.x - fwd.x * v.lookBack, ty, c.z - fwd.z * v.lookBack)
        if v.top { return camera(eye: t + SIMD3(0, v.dist, 0), target: t, up: fwd) }
        let dir = SIMD3<Float>(fwd.x * cosf(v.yaw) + fwd.z * sinf(v.yaw), 0, -fwd.x * sinf(v.yaw) + fwd.z * cosf(v.yaw))
        return lookCamera(target: t, dir: dir, dist: v.dist, lift: v.lift)
    }

    // MARK: sheets

    private func labelled(_ img: UIImage, _ text: String, bar: CGFloat = 34) -> UIImage {
        let w = img.size.width, h = img.size.height
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + bar), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + bar))
            (text as NSString).draw(at: CGPoint(x: 8, y: 7), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.white])
            img.draw(in: CGRect(x: 0, y: bar, width: w, height: h))
        }
    }
    private func grid(_ imgs: [UIImage], cols: Int) -> UIImage {
        let cw = imgs.map { $0.size.width }.max() ?? 0, ch = imgs.map { $0.size.height }.max() ?? 0
        let rows = (imgs.count + cols - 1) / cols
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: cw * CGFloat(cols), height: ch * CGFloat(rows)), format: fmt).image { ctx in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: cw * CGFloat(cols), height: ch * CGFloat(rows)))
            for (i, im) in imgs.enumerated() { im.draw(at: CGPoint(x: CGFloat(i % cols) * cw, y: CGFloat(i / cols) * ch)) }
        }
    }
    private func write(_ img: UIImage, _ path: String) throws { try img.pngData()!.write(to: URL(fileURLWithPath: path)) }
    private func ui(_ i: LockImage, _ label: String) -> UIImage { labelled(i.uiImage()!, label) }

    // MARK: 1. angles

    func testAngles() throws {
        let d = try dir("angles")
        let chars = [Char(id: 1)]
        let lab = makeLab(chars); let dr = dress(lab, chars); settle(lab, dr, chars)
        let c = try makeCtx(sim: lab.rigs[0].sim, W: 440, H: 440)
        let s = subj(lab, dr, chars)
        let views: [View] = [View(name: "front", yaw: 0), View(name: "3/4 front L", yaw: 0.7), View(name: "3/4 front R", yaw: -0.7), View(name: "side L", yaw: .pi / 2), View(name: "side R", yaw: -.pi / 2),
                             View(name: "3/4 back", yaw: 2.5), View(name: "back", yaw: .pi), View(name: "TOP", yaw: 0, dist: 4.2, lookBack: 0.15, top: true)]
        var cells: [UIImage] = []
        var memo = SIMD3<Float>(0, 0, 1)
        for neutral in [true, false] { for v in views {
            cells.append(ui(render(c, s, cam: cam(v, s.sim, memo: &memo), neutral: neutral), "Pip \(v.name) \(neutral ? "(neutral)" : "(room)")"))
        } }
        try write(grid(cells, cols: 4), d + "/angles.png")
    }

    // MARK: 2. motions

    struct Motion { var name: String; var start: (SocialTests.Lab) -> Void; var wait: ((SocialTests.Lab) -> Bool)? = nil; var times: [Float]; var apex = false }
    private func motionList() -> [Motion] {
        func idle(_ k: IdleKind) -> (SocialTests.Lab) -> Void { { lab in let b = lab.rigs[0].brain; b.idleForced = true; XCTAssertTrue(b.idleStart(k, lab.rigs[0].sim), "idleStart \(k)") } }
        func walk(_ dx: Float, _ dz: Float, hurry: Bool) -> (SocialTests.Lab) -> Void { { lab in
            let r = lab.rigs[0], p = r.sim.bodyPose(iterations: 3).centroid
            r.brain.hurry = hurry
            r.brain.script = .walk(target: SIMD2(p.x + dx, p.z + dz), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 } }
        return [
            Motion(name: "idle sway", start: { _ in }, times: [0.4, 1.1]),
            Motion(name: "walk", start: walk(-3, 0.2, hurry: false), times: [1.3, 1.6]),
            Motion(name: "run", start: walk(-3.5, 0.2, hurry: true), times: [1.2, 1.45]),
            Motion(name: "turn in place (walk away)", start: walk(0, -2.5, hurry: false), times: [0.15, 0.45]),
            Motion(name: "sit", start: idle(.sit), times: [1.5, 3.0]),
            Motion(name: "sleep (lying)", start: { lab in let b = lab.rigs[0].brain; b.idleForced = true; XCTAssertTrue(b.idleStart(.sleep, lab.rigs[0].sim)); b.sleep.hold = 500 }, wait: { $0.rigs[0].brain.isNapping }, times: [1.0, 3.0]),
            Motion(name: "bounce hop", start: idle(.bounce), times: [-0.05, 0.2], apex: true),
            Motion(name: "joy jump", start: idle(.joy), times: [-0.05, 0.2], apex: true),
            Motion(name: "cartwheel", start: idle(.cartwheel), times: [-0.15, 0.15], apex: true),
            Motion(name: "backflip", start: { lab in lab.rigs[0].brain.startFlip(sim: lab.rigs[0].sim) }, times: [-0.15, 0.15], apex: true),
        ]
    }

    /// Runs a motion on a fresh lab; returns the frame times if `probe` (apex search) else renders cells.
    private func runMotion(_ m: Motion, ctx: Ctx?, times: [Float]?, apexOut: inout Float) -> [UIImage] {
        let chars = [Char(id: 1)]
        let lab = makeLab(chars); let dr = dress(lab, chars); settle(lab, dr, chars)
        let s = subj(lab, dr, chars)
        m.start(lab)
        var t: Float = 0, wt: Float = 0
        while let w = m.wait, !w(lab), wt < 25 { step(lab, dr, chars); wt += 1.0 / 60 }
        var cells: [UIImage] = [], memo = SIMD3<Float>(0, 0, 1), idx = 0
        var best: Float = -9
        let y0 = s.sim.centroid().y
        _ = y0
        let limit: Float = 5
        while t < limit {
            step(lab, dr, chars); t += 1.0 / 60
            if times == nil { let y = s.sim.centroid().y; if y > best { best = y; apexOut = t } }
            if let ts = times, idx < ts.count, t >= ts[idx] {
                for v in [View(name: "3/4 back", yaw: 2.5, dist: 4.3, lookBack: 0.3), View(name: "side", yaw: .pi / 2, dist: 4.3, lookBack: 0.3)] {
                    cells.append(ui(render(ctx!, s, cam: cam(v, s.sim, memo: &memo), neutral: false), String(format: "Pip %@ t=%.2f %@", m.name, t, v.name)))
                }
                idx += 1
                if idx == ts.count { break }
            }
        }
        return cells
    }

    func testMotions() throws {
        let d = try dir("motions")
        let probeLab = makeLab([Char(id: 1)])
        let c = try makeCtx(sim: probeLab.rigs[0].sim, W: 360, H: 360)
        var cells: [UIImage] = []
        for m in motionList() {
            var times = m.times
            if m.apex { var ap: Float = 0; _ = runMotion(m, ctx: nil, times: nil, apexOut: &ap); times = m.times.map { max(0.02, ap + $0) } }
            var dummy: Float = 0
            cells += runMotion(m, ctx: c, times: times, apexOut: &dummy)
        }
        cells += try dining(ctx: c)
        try write(grid(cells, cols: 4), d + "/motions.png")
    }

    /// Eating (toss) and drinking (sip) through the real care / dining path (the DiningJellyTests room), Pip alone drawn.
    private func dining(ctx: Ctx) throws -> [UIImage] {
        var out: [UIImage] = []
        for drink in [false, true] {
            let r = DiningJellyTests.Room()
            DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
            for a in r.actors { a.brain?.feature = JellyRoster.feature(a.id); a.brain?.skinnerRef = a.skinner }
            let pip = r.actors[1], b = pip.brain!
            r.actors[0].brain?.requestNow(.goTo(SIMD2(-1.6, 1.0)))
            r.run(5)
            if drink { r.care.needs(for: 1).set(.thirst, 0.1); r.run(1); r.care.drink(jelly: 1) } else { r.care.feed(jelly: 1) }
            let want: BlobBrain.Activity = drink ? .drinking : .eating
            r.run(40) { b.activity == want && (drink || b.dineHolding) }
            let chars = [Char(id: 1)]
            let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; Self.keep.append(w)
            let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f)
            WearBody.install(MotionRig.renderMesh)
            let s = Subj(skinner: pip.skinner, sim: pip.sim, brain: b, char: chars[0], worn: w, feats: f, body: 0)
            var memo = SIMD3<Float>(0, 0, 1)
            for _ in 0..<5 { r.run(0.05); wearTick(w, f, b, pip.sim, chars[0]) }
            for pass in 0..<2 {
                if pass == 1 { for _ in 0..<40 { r.tick(); wearTick(w, f, b, pip.sim, chars[0]) } }
                for _ in 0..<30 { _ = skin(pip.skinner, pip.sim) }
                for v in [View(name: "3/4 back", yaw: 2.5, dist: 4.3, lookBack: 0.3), View(name: "side", yaw: .pi / 2, dist: 4.3, lookBack: 0.3)] {
                    let img = render(ctx, s, cam: cam(v, pip.sim, memo: &memo), neutral: false) { ren in
                        if let room = ren.room, let fr = r.care.dining.frame(theme: room.theme) { room.setDining(fr) }
                    }
                    out.append(ui(img, "Pip \(drink ? "drinking (sip)" : "eating (toss)") \(b.activity) \(v.name)"))
                }
            }
        }
        return out
    }

    // MARK: 3. wear

    func testWear() throws {
        let d = try dir("wear")
        let sets: [(String, Outfit)] = [("beanie", [.head: .beanieHoney]), ("crown", [.head: .crownGold]), ("backpack", [.body: .backpackSky]), ("hero cape", [.body: .capeHero]),
                                       ("hoodie", [.body: .hoodie]), ("scarf", [.neck: .scarfCosy])]
        let base = makeLab([Char(id: 1)])
        let c = try makeCtx(sim: base.rigs[0].sim, W: 440, H: 440)
        var cells: [UIImage] = []
        for (name, outfit) in sets {
            let chars = [Char(id: 1, outfit: outfit)]
            let lab = makeLab(chars); let dr = dress(lab, chars); settle(lab, dr, chars, frames: 50)
            let s = subj(lab, dr, chars)
            var memo = SIMD3<Float>(0, 0, 1)
            for v in [View(name: "3/4 back", yaw: 2.5, dist: 4.0, lookY: 0.2, lookBack: 0.3), View(name: "side", yaw: .pi / 2, dist: 4.0, lookY: 0.2, lookBack: 0.3)] {
                cells.append(ui(render(c, s, cam: cam(v, s.sim, memo: &memo), neutral: false), "Pip + \(name): \(v.name)"))
            }
        }
        try write(grid(cells, cols: 4), d + "/wear.png")
    }

    /// One walk away from the camera in `hat`: how far the hat as drawn (crown fit included) stands above the drawn head top, every frame while walking
    /// (p2p / sd: how much the hat moves ON his head), plus close-ups from behind and above when `ctx` is given (the room camera's angle on a Jelbie walking away).
    private func hatWalk(id: Int, hat: WearLook, spikes: Bool = true, ctx: Ctx? = nil, label: String = "") -> (p2p: Float, sd: Float, cells: [UIImage]) {
        let chars = [Char(id: id, outfit: [.head: hat], featureOn: spikes)]
        let lab = makeLab(chars, positions: [SIMD2(0, 1.6)]); let dr = dress(lab, chars); settle(lab, dr, chars, frames: 50)
        let r = lab.rigs[0], s = subj(lab, dr, chars)
        r.brain.script = .walk(target: SIMD2(0, -2.6), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0
        let eggLimit = MotionRig.renderMesh.armCapsule?.firstVertex.min() ?? 0
        var t: Float = 0, cells: [UIImage] = [], tops: [Float] = []
        var memo = SIMD3<Float>(0, 0, -1)
        while t < 2.6 {
            step(lab, dr, chars); t += 1.0 / 60
            if t > 1.0 && r.brain.activity == .walking {
                let sk = skin(r.skinner, r.sim)
                let f = sk.withUnsafeBufferPointer { p in s.worn.frame(theme: RoomTheme(), time: 0.4) { _ in p.baseAddress } }
                var headTop: Float = -9
                for v in 0..<eggLimit { headTop = max(headTop, sk[6 * v + 1]) }
                tops.append((f.opaque.vertices.map { $0.pos.y }.max() ?? 0) - headTop)
            }
            if let c = ctx, t > 1.4, cells.count < 8, Int(((t - 1.4) * 60).rounded()) % 4 == 0 {
                let v = View(name: "back", yaw: .pi, dist: 2.3, lookY: 0.55, lookBack: 0.0, lift: 0.55)
                cells.append(ui(render(c, s, cam: cam(v, s.sim, memo: &memo), neutral: false), String(format: "%@ t=%.2f", label, t)))
            }
        }
        let mean = tops.reduce(0, +) / Float(max(tops.count, 1))
        let sd = (tops.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(max(tops.count, 1))).squareRoot()
        return ((tops.max() ?? 0) - (tops.min() ?? 0), sd, cells)
    }

    /// Regression (user, many times: "the yellow one's head is still bouncy and the back of the hat is glitching"): the tail's back swell reached the back of
    /// Pip's head, and the per-frame crown fit lifted and dropped an enclosing hat by up to 0.45 every step. His hat must sit as still on his head as Moss's does.
    func testPipHatStaysOnHisHeadWhileWalking() throws {
        for hat: WearLook in [.beanieHoney, .tophat, .cowboyHat, .crownGold] {
            let pip = hatWalk(id: 1, hat: hat), moss = hatWalk(id: 2, hat: hat)
            XCTAssertLessThan(pip.p2p, max(0.09, moss.p2p * 1.5), "\(hat): Pip's hat moves on his head (p2p \(pip.p2p)) much more than Moss's (\(moss.p2p))")
            XCTAssertLessThan(pip.sd, max(0.02, moss.sd * 1.5), "\(hat): Pip's hat bobs on his head (sd \(pip.sd)) much more than Moss's (\(moss.sd))")
        }
    }

    /// The back of an enclosing hat while walking, close up from behind and above: Pip, Pip without spikes, Pip with the crown fit off, Moss for reference.
    func testHatBack() throws {
        let d = try dir("hatback")
        let hat: WearLook = ProcessInfo.processInfo.environment["HATBACK_HAT"].flatMap { WearLook(rawValue: $0) } ?? .beanieHoney
        let base = makeLab([Char(id: 1)])
        let c = try makeCtx(sim: base.rigs[0].sim, W: 360, H: 300)
        var rows: [UIImage] = [], report = ""
        for (name, id, spikes, fit) in [("Pip", 1, true, true), ("Pip, no spikes", 1, false, true), ("Pip, crown fit OFF", 1, true, false), ("Moss", 2, true, true)] {
            CrownFit.enabled = fit
            defer { CrownFit.enabled = true }
            let w = hatWalk(id: id, hat: hat, spikes: spikes, ctx: c, label: name)
            report += String(format: "%@: hat top above head top: p2p %.4f sd %.4f\n", name, w.p2p, w.sd)
            rows.append(grid(w.cells, cols: 8))
        }
        try report.write(toFile: d + "/hatback.txt", atomically: true, encoding: .utf8)
        try write(grid(rows, cols: 1), d + "/hatback_\(hat.rawValue).png")
    }

    // MARK: 4. the others (no tail / back swell allowed)

    func testOthers() throws {
        let d = try dir("others")
        let base = makeLab([Char(id: 0)])
        let c = try makeCtx(sim: base.rigs[0].sim, W: 330, H: 330)
        var cells: [UIImage] = []
        for path in [TailPath.real, .bare, .bareCfg, .bareForced] {
            for (name, id) in [("Bob", 0), ("Moss", 2), ("Lavender", 3)] {
                let chars = [Char(id: id, featureOn: path == .real)]
                let lab = makeLab(chars, path: path); let dr = dress(lab, chars)
                if path == .bareForced {
                    for r in lab.rigs { r.skinner.tailOn = true }
                    settle(lab, dr, chars, frames: 20, brains: false)
                } else { settle(lab, dr, chars) }
                let s = subj(lab, dr, chars)
                var memo = SIMD3<Float>(0, 0, 1)
                for v in [View(name: "3/4 back", yaw: 2.5), View(name: "TOP", yaw: 0, dist: 4.0, lookBack: 0.1, top: true)] {
                    cells.append(ui(render(c, s, cam: cam(v, s.sim, memo: &memo), neutral: false), "\(name) \(path.rawValue): \(v.name)"))
                }
            }
        }
        try write(grid(cells, cols: 6), d + "/others.png")
    }

    // MARK: 5. picker

    /// The species picker's framing: the focus close-up over the jelly's spot, PhotoCam-style orbit (yaw / zoom 1.6), on a flat backdrop (the picker draws its own).
    func testPicker() throws {
        let d = try dir("picker")
        let chars = [Char(id: 1)]
        let lab = makeLab(chars, positions: [GameCamera.callSpot]); let dr = dress(lab, chars); settle(lab, dr, chars)
        let c = try makeCtx(sim: lab.rigs[0].sim, W: 420, H: 420)
        let s = subj(lab, dr, chars)
        var memo = SIMD3<Float>(0, 0, 1)
        let (_, fwd) = pose(s.sim, memo: &memo)
        let spot = GameCare.floorPos(s.brain, s.sim)
        let fp = GameCamera.focusPose(aspect: 1, spot: spot)
        var v0 = fp.eye - fp.target
        let hl: Float = simd_length(SIMD2<Float>(v0.x, v0.z))
        v0.x = fwd.x * hl; v0.z = fwd.z * hl                       // the focus camera looks at the front of the Jelbie
        let rest = PickerCamera.startYaw(1)
        let yaws: [(String, Float)] = [("RESTING yaw \(rest)", rest), ("orbit 0", 0), ("orbit 90", .pi / 2), ("orbit 180", .pi), ("orbit 270", 3 * .pi / 2)]
        let (sy, sp, sz, spn) = (PhotoCam.yaw, PhotoCam.pitch, PhotoCam.zoom, PhotoCam.pan)
        defer { PhotoCam.yaw = sy; PhotoCam.pitch = sp; PhotoCam.zoom = sz; PhotoCam.pan = spn }
        var cells: [UIImage] = []
        for (name, y) in yaws {
            PhotoCam.yaw = y; PhotoCam.pitch = 0; PhotoCam.zoom = PickerCamera.startZoom; PhotoCam.pan = .zero
            let e = PhotoCam.apply(eye: fp.target + v0, target: fp.target)
            cells.append(ui(render(c, s, cam: camera(eye: e.eye, target: e.target), neutral: true), "Lemon Drop picker: \(name)"))
        }
        try write(grid(cells, cols: 5), d + "/picker.png")
    }

    // MARK: 7. restyle stills (g-piptail3): one process per PIPTAIL variant, individual PNGs per view

    func testTail3Stills() throws {
        let env = ProcessInfo.processInfo.environment
        guard let root = env["PIPTAIL3_DIR"], !root.isEmpty else { throw XCTSkip("PIPTAIL3_DIR not set") }
        let name = PipTailVariant.active.rawValue
        for dressed in [false, true] {
            let outfit: Outfit = dressed ? [.head: .beaniePink, .face: .heartShades] : [:]
            let tag = dressed ? "dressed" : "bare"
            defer { try? PipSpikes.debug.write(toFile: "\(root)/\(name)/spikes_\(tag).txt", atomically: true, encoding: .utf8) }
            let d = "\(root)/\(name)/\(tag)"
            try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
            let chars = [Char(id: 1, outfit: outfit)]
            let lab = makeLab(chars); let dr = dress(lab, chars); settle(lab, dr, chars)
            let c = try makeCtx(sim: lab.rigs[0].sim, W: 560, H: 560)
            let s = subj(lab, dr, chars)
            let views: [(String, View)] = [("side", View(name: "side", yaw: .pi / 2, dist: 3.6, lookBack: 0.35)), ("back34", View(name: "back34", yaw: 2.5, dist: 3.6, lookBack: 0.35)),
                                           ("back", View(name: "back", yaw: .pi, dist: 3.6, lookBack: 0.35)), ("top", View(name: "top", yaw: 0, dist: 4.2, lookBack: 0.15, top: true)),
                                           ("front", View(name: "front", yaw: 0, dist: 3.6, lookBack: 0.35))]
            var memo = SIMD3<Float>(0, 0, 1)
            for (n, v) in views { try write(render(c, s, cam: cam(v, s.sim, memo: &memo), neutral: true).uiImage()!, "\(d)/\(n).png") }
            // the picker framing
            let (_, fwd) = pose(s.sim, memo: &memo)
            let fp = GameCamera.focusPose(aspect: 1, spot: GameCare.floorPos(s.brain, s.sim))
            var v0 = fp.eye - fp.target
            let hl = simd_length(SIMD2<Float>(v0.x, v0.z)); v0.x = fwd.x * hl; v0.z = fwd.z * hl
            let (sy, sp, sz, spn) = (PhotoCam.yaw, PhotoCam.pitch, PhotoCam.zoom, PhotoCam.pan)
            PhotoCam.yaw = PickerCamera.startYaw(1); PhotoCam.pitch = 0; PhotoCam.zoom = PickerCamera.startZoom; PhotoCam.pan = .zero
            let e = PhotoCam.apply(eye: fp.target + v0, target: fp.target)
            try write(render(c, s, cam: camera(eye: e.eye, target: e.target), neutral: true).uiImage()!, "\(d)/picker.png")
            PhotoCam.yaw = sy; PhotoCam.pitch = sp; PhotoCam.zoom = sz; PhotoCam.pan = spn
            // the room camera at native pixels (portrait, then landscape)
            for (n, W, H) in [("room_portrait", 603, 1311), ("room_landscape", 1311, 603)] {
                let rc = try makeCtx(sim: lab.rigs[0].sim, W: W, H: H)
                try write(render(rc, s, cam: GameCamera.camera(aspect: Float(W) / Float(H)), neutral: false).uiImage()!, "\(d)/\(n).png")
            }
        }
        _ = GameCamera.camera(aspect: 603.0 / 1311.0)
    }

    // MARK: 9. back shape comparison (g-piptail3 phase 1): PIPBACK_DIR, one process per PIPBACK value (the env var itself selects the back shape in TailBean)

    private func pbViews() -> [(String, View)] {
        [("side", View(name: "side", yaw: .pi / 2, dist: 3.6, lookBack: 0.35)), ("back34", View(name: "back34", yaw: 2.5, dist: 3.6, lookBack: 0.35)),
         ("back", View(name: "back", yaw: .pi, dist: 3.6, lookBack: 0.35)), ("top", View(name: "top", yaw: 0, dist: 4.2, lookBack: 0.15, top: true)),
         ("j_side", View(name: "j_side", yaw: .pi / 2, dist: 1.8, lookY: -0.4, lookBack: 0.95)), ("j_back34", View(name: "j_back34", yaw: 2.5, dist: 1.8, lookY: -0.4, lookBack: 0.95))]
    }
    /// The drawn body's silhouette (every body triangle projected, no shadow, no spikes / wear) as a white-on-black image.
    private func bodyMask(_ skin: [Float], cam: CameraState, W: Int, H: Int) -> LockImage {
        var px = [UInt8](repeating: 0, count: W * H * 4)
        for i in 0..<(W * H) { px[4 * i + 3] = 255 }
        let idx = MotionRig.renderMesh.index
        var proj: [SIMD3<Float>?] = []
        proj.reserveCapacity(skin.count / 6)
        for v in 0..<(skin.count / 6) {
            let c = cam.viewProj * SIMD4<Float>(skin[6 * v], skin[6 * v + 1], skin[6 * v + 2], 1)
            if c.w <= 0.01 { proj.append(nil); continue }
            proj.append(SIMD3((c.x / c.w * 0.5 + 0.5) * Float(W), (1 - (c.y / c.w * 0.5 + 0.5)) * Float(H), 0))
        }
        var t = 0
        while t + 2 < idx.count {
            defer { t += 3 }
            guard let a = proj[Int(idx[t])], let b = proj[Int(idx[t + 1])], let c = proj[Int(idx[t + 2])] else { continue }
            let minX = max(0, Int(min(a.x, b.x, c.x).rounded(.down))), maxX = min(W - 1, Int(max(a.x, b.x, c.x).rounded(.up)))
            let minY = max(0, Int(min(a.y, b.y, c.y).rounded(.down))), maxY = min(H - 1, Int(max(a.y, b.y, c.y).rounded(.up)))
            if minX > maxX || minY > maxY { continue }
            let den = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
            if abs(den) < 1e-6 { continue }
            for y in minY...maxY { for x in minX...maxX {
                let px_ = Float(x) + 0.5, py_ = Float(y) + 0.5
                let l1 = ((b.y - c.y) * (px_ - c.x) + (c.x - b.x) * (py_ - c.y)) / den
                let l2 = ((c.y - a.y) * (px_ - c.x) + (a.x - c.x) * (py_ - c.y)) / den
                let l3 = 1 - l1 - l2
                if l1 >= -0.02 && l2 >= -0.02 && l3 >= -0.02 { let o = 4 * (y * W + x); px[o] = 255; px[o + 1] = 255; px[o + 2] = 255 }
            } }
        }
        return LockImage(w: W, h: H, bgra: px)
    }

    private func closestOnTri(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return a }
        let bp = p - b, d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return b }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 { return a + ab * (d1 / (d1 - d3)) }
        let cp = p - c, d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return c }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 { return a + ac * (d2 / (d2 - d6)) }
        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 { return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))) }
        let den = 1 / (va + vb + vc)
        return a + ab * (vb * den) + ac * (vc * den)
    }

    /// (d) the world position of each spike's base in the settled pose, and its signed distance to the drawn (skinned) body surface (+ above it, - sunk in).
    private func spikeSeating(_ s: Subj, skin: [Float]) -> String {
        guard let slot = s.feats.slot(0), slot.feature == .spines, let body = s.feats.body,
              let p = FeatureMeshes.prepare(.spines, placement: FeatureMeshes.Placement(), body: body, spec: .shared, ridge: slot.layoutTo) else { return "  (no spikes)\n" }
        let c = slot.carry, R = simd_float3x3(c.rotation), sxz = 1 / c.squash.squareRoot()
        let M = R * simd_float3x3(diagonal: SIMD3(sxz, c.squash, sxz))
        let idx = MotionRig.renderMesh.index
        func P(_ i: UInt32) -> SIMD3<Float> { SIMD3(skin[6 * Int(i)], skin[6 * Int(i) + 1], skin[6 * Int(i) + 2]) }
        func N(_ i: UInt32) -> SIMD3<Float> { SIMD3(skin[6 * Int(i) + 3], skin[6 * Int(i) + 4], skin[6 * Int(i) + 5]) }
        var out = "", bases: [SIMD3<Float>] = []
        for part in p.parts {
            var w: SIMD3<Float>
            if part.tailLocal >= 0, slot.tailFirst >= 0 {
                let o = 6 * (slot.tailFirst + part.tailLocal), r = (part.tailLocal - 1) / TailBean.around
                let off = M * (part.pivot - part.skinAnchor)
                w = SIMD3(skin[o], skin[o + 1], skin[o + 2]) + (r >= 0 && r < slot.tailRingQ.count ? slot.tailRingQ[r].act(off) : off)
            } else if part.bind.tri != .zero {
                w = skin.withUnsafeBufferPointer { WearBody.world(part.bind, skin: $0.baseAddress!) }
            } else { continue }
            var best = Float.infinity, sign: Float = 1
            var t = 0
            while t + 2 < idx.count {
                defer { t += 3 }
                let a = P(idx[t]), b = P(idx[t + 1]), cc = P(idx[t + 2])
                if (a.y == b.y && b.y == cc.y && a.y < -50) { continue }
                let cp = closestOnTri(w, a, b, cc), d = simd_distance(w, cp)
                if d < best { best = d; sign = simd_dot(w - cp, N(idx[t]) + N(idx[t + 1]) + N(idx[t + 2])) >= 0 ? 1 : -1 }
            }
            out += String(format: "  %@ %@ signedDist=%.4f world=(%.3f,%.3f,%.3f)\n", part.name, part.tailLocal >= 0 ? "tail" : "back", sign * best, w.x, w.y, w.z)
            bases.append(w)
        }
        out += "  chords(base to next base)=" + zip(bases, bases.dropFirst()).map { String(format: "%.3f", simd_distance($0, $1)) }.joined(separator: ",") + "\n"
        return out
    }

    /// (a)(b)(c) analytic numbers about the displaced egg and the exposed tail, in rest space.
    private func backNumbers() -> String {
        let sd = TailBean.startDir, sH = TailBean.swellHeight, sh = TailBean.shape
        func fwd(_ q: SIMD3<Float>) -> SIMD3<Float> { q + sd * (sH * TailBean.swellWeight(q)) }
        func inv(_ q: SIMD3<Float>) -> SIMD3<Float> { var p = q; for _ in 0..<5 { p = q - sd * (sH * TailBean.swellWeight(p)) }; return p }
        func inside(_ q: SIMD3<Float>) -> Bool { BobForm.sdf(SIMD3(Double(inv(q).x), Double(inv(q).y), Double(inv(q).z))) <= 0 }
        // (a)
        var plain: [Int: Float] = [:], disp: [Int: Float] = [:]
        for xi in -29...29 where abs(Double(xi) * 0.01) < 0.3 {
            let x = Double(xi) * 0.01
            for yi in 0...560 {
                let y = Double(yi) * 0.0025
                if BobForm.sdf(SIMD3(x, y, 0)) > 0 { continue }
                var lo = -1.2, hi = 0.0
                for _ in 0..<40 { let m = (lo + hi) / 2; if BobForm.sdf(SIMD3(x, y, m)) > 0 { lo = m } else { hi = m } }
                let q0 = SIMD3(Float(x), Float(y), Float(hi)), q1 = fwd(q0)
                let k0 = Int((q0.y / 0.05).rounded(.down)), k1 = Int((q1.y / 0.05).rounded(.down))
                plain[k0] = max(plain[k0] ?? -9, -q0.z); disp[k1] = max(disp[k1] ?? -9, -q1.z)
            }
        }
        var exAbove: Float = 0, exAll: Float = 0, atY: Float = 0
        for (k, pz) in plain { if let dz = disp[k] { let e = dz - pz; if e > exAll { exAll = e; atY = Float(k) * 0.05 }; if Float(k) * 0.05 >= 0.9 { exAbove = max(exAbove, e) } } }
        var exMid: Float = 0
        for (k, pz) in plain { if let dz = disp[k], Float(k) * 0.05 >= 0.15 { exMid = max(exMid, dz - pz) } }
        var out = String(format: "backExcess_y>0.9=%.4f backExcess_max=%.4f (at y=%.2f; bottom bins are shifted-in tube root) backExcess_max_y>=0.15=%.4f\n", exAbove, exAll, atY, exMid)
        out += "backExcess profile by y: " + (0...27).compactMap { k -> String? in if let a = plain[2 * k], let b = disp[2 * k] { return String(format: "%.1f:%.3f", Float(2 * k) * 0.05, b - a) }; return nil }.joined(separator: " ") + "\n"
        // (b)
        var tExit = 0.0, t = 0.0
        while t <= sh.length { let pt = sh.point(t); if inside(SIMD3(Float(pt.x), Float(pt.y), Float(pt.z))) { tExit = t }; t += 0.004 }
        let exposed = sh.length - tExit + sh.tipR
        out += String(format: "exposedTail=%.4f tExit=%.3f length=%.3f sink=%.2f tipR=%.3f width=%.3f\n", exposed, tExit, sh.length, sh.sink, sh.tipR, sh.width)
        // (c)
        func hOf(_ q: SIMD3<Float>) -> Float { sH * TailBean.swellWeight(q) }
        var angles: [Double] = [], topAngles: [Double] = []
        for j in 0..<TailBean.around {
            let ph = 2 * Double.pi * Double(j) / Double(TailBean.around)
            var tj = -1.0
            var tt = 0.0
            while tt <= sh.length {
                let f = sh.frame(tt), tg = sh.tangent(tt), v = simd_normalize(simd_cross(tg, f.side))
                let rad = f.side * cos(ph) + v * sin(ph), q = sh.point(tt) + rad * sh.radius(tt)
                if inside(SIMD3(Float(q.x), Float(q.y), Float(q.z))) { tj = tt }
                tt += 0.004
            }
            if tj < 0 || tj >= sh.length - 0.01 { continue }
            let f = sh.frame(tj), tg = sh.tangent(tj), v = simd_normalize(simd_cross(tg, f.side))
            let rad = f.side * cos(ph) + v * sin(ph), q = sh.point(tj) + rad * sh.radius(tj)
            let qf = SIMD3(Float(q.x), Float(q.y), Float(q.z)), p0 = inv(qf)
            let n0 = BobForm.normal(SIMD3(Double(p0.x), Double(p0.y), Double(p0.z)))
            var cols = [SIMD3<Float>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
            for a in 0..<3 {
                var dq = SIMD3<Float>(repeating: 0); dq[a] = 0.01
                let g = (hOf(p0 + dq) - hOf(p0 - dq)) / 0.02
                cols[a] += sd * g
            }
            let Jm = simd_float3x3(cols[0], cols[1], cols[2])
            let nE = simd_normalize(Jm.inverse.transpose * SIMD3(Float(n0.x), Float(n0.y), Float(n0.z)))
            let nT = simd_normalize(SIMD3(Float(rad.x), Float(rad.y), Float(rad.z)))
            let ang = Double(acosf(max(-1, min(1, simd_dot(nE, nT))))) * 180 / .pi
            angles.append(ang); if v.y * sin(ph) > 0 { topAngles.append(ang) }
        }
        func st(_ a: [Double]) -> String { a.isEmpty ? "n/a" : String(format: "mean=%.1f max=%.1f n=%d", a.reduce(0, +) / Double(a.count), a.max()!, a.count) }
        out += "crease_deg all-around: \(st(angles)); upper half: \(st(topAngles))\n"
        return out
    }

    func testPipBackStills() throws {
        let env = ProcessInfo.processInfo.environment
        guard let root = env["PIPBACK_DIR"], !root.isEmpty else { throw XCTSkip("PIPBACK_DIR not set") }
        let tag = PipBack.tag.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: ",", with: "_")
        let base = "\(root)/\(tag)"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        var numbers = "PIPBACK=\(PipBack.tag)\n" + backNumbers()
        for (who, id, outfit, dressed) in [("bob", 0, Outfit(), false), ("bare", 1, Outfit(), false), ("dressed", 1, [.head: .beaniePink, .face: .heartShades] as Outfit, true)] {
            let d = "\(base)/\(who)"
            try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
            let chars = [Char(id: id, outfit: outfit)]
            let lab = makeLab(chars); let dr = dress(lab, chars); settle(lab, dr, chars)
            let c = try makeCtx(sim: lab.rigs[0].sim, W: 560, H: 560)
            let s = subj(lab, dr, chars)
            var memo = SIMD3<Float>(0, 0, 1)
            for (n, v) in pbViews() {
                let cm = cam(v, s.sim, memo: &memo)
                try write(render(c, s, cam: cm, neutral: true).uiImage()!, "\(d)/\(n).png")
                if !dressed { try write(bodyMask(skin(s.skinner, s.sim), cam: cm, W: 560, H: 560).uiImage()!, "\(d)/\(n)_mask.png") }
            }
            let rc = try makeCtx(sim: lab.rigs[0].sim, W: 603, H: 1311)
            let rcam = GameCamera.camera(aspect: 603.0 / 1311.0)
            try write(render(rc, s, cam: rcam, neutral: false).uiImage()!, "\(d)/room_portrait.png")
            if !dressed { try write(bodyMask(skin(s.skinner, s.sim), cam: rcam, W: 603, H: 1311).uiImage()!, "\(d)/room_portrait_mask.png") }
            if id == 1 { numbers += "[\(who)] spike seating (settled pose):\n" + spikeSeating(s, skin: skin(s.skinner, s.sim)) + "[\(who)] \(PipSpikes.debug.prefix(160))\n" }
        }
        try numbers.write(toFile: "\(base)/numbers.txt", atomically: true, encoding: .utf8)
        _ = GameCamera.camera(aspect: 603.0 / 1311.0)
    }

    // MARK: 8. hats re-flow the ridge (g-piptail3 round 2): PIPTAIL4_DIR, one process per PIPTAIL variant

    private func dir4() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["PIPTAIL4_DIR"], !d.isEmpty else { throw XCTSkip("PIPTAIL4_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    /// Crown-enclosing head pieces by brim height (lowest vertex y), and the perch items.
    private func hatInfo() -> (enclosing: [(WearLook, Float)], perch: [WearLook]) {
        var enc: [(WearLook, Float)] = [], perch: [WearLook] = []
        for look in WearLook.pieces where look.slot == .head {
            guard let piece = WearMeshes.prepare(look, body: WearBody.shared) else { continue }
            if piece.crownEnclosing { enc.append((look, piece.rest.map { $0.y }.min() ?? 0)) } else { perch.append(look) }
        }
        return (enc.sorted { $0.1 < $1.1 }, perch)
    }
    private func cellImage(_ outfit: Outfit, views: [View], size: Int = 520, settleFrames: Int = 40) throws -> [LockImage] {
        let chars = [Char(id: 1, outfit: outfit)]
        let lab = makeLab(chars); let dr = dress(lab, chars); settle(lab, dr, chars, frames: settleFrames)
        let c = try makeCtx(sim: lab.rigs[0].sim, W: size, H: size)
        let s = subj(lab, dr, chars)
        var memo = SIMD3<Float>(0, 0, 1)
        return views.map { render(c, s, cam: cam($0, s.sim, memo: &memo), neutral: true) }
    }

    func testTail4Hats() throws {
        let d = try dir4()
        let name = PipTailVariant.active.rawValue
        let od = "\(d)/\(name)"
        try FileManager.default.createDirectory(atPath: od, withIntermediateDirectories: true)
        _ = WearBody.install(MotionRig.renderMesh)
        let info = hatInfo()
        var report = "variant \(name)\ncrown-enclosing hats (brim y): " + info.enclosing.map { "\($0.0.art)=\(String(format: "%.3f", $0.1))" }.joined(separator: ", ") + "\nperch: " + info.perch.map { $0.art }.joined(separator: ", ") + "\n"
        let beanie = info.enclosing.first { $0.0 == .beaniePink }
        let others = info.enclosing.filter { $0.0 != .beaniePink }
        var picks: [(String, Outfit)] = [("bare", [:])]
        if let b = beanie { picks.append(("beanie", [.head: b.0])) }
        if let lo = others.first { picks.append(("hat_low_" + lo.0.art, [.head: lo.0])) }
        if let hi = others.last, hi.0 != others.first?.0 { picks.append(("hat_high_" + hi.0.art, [.head: hi.0])) }
        if let mid = others.count > 2 ? others[others.count / 2] : nil { picks.append(("hat_mid_" + mid.0.art, [.head: mid.0])) }
        if let pr = [WearLook.hairBow, .headphones, .catEars].first(where: { l in info.perch.contains(l) }) { picks.append(("perch_" + pr.art, [.head: pr])) }
        picks.append(("beanie_shades", [.head: .beaniePink, .face: .heartShades]))
        picks.append(("neck_scarf", [.neck: .scarfCosy]))
        picks.append(("neck_scarf_beanie", [.neck: .scarfCosy, .head: .beaniePink]))
        picks.append(("neck_chain", [.neck: .chainGold]))
        picks.append(("neck_chain_beanie", [.neck: .chainGold, .head: .beaniePink]))
        picks.append(("neck_medal", [.neck: .medalGold]))
        picks.append(("neck_medal_beanie", [.neck: .medalGold, .head: .beaniePink]))
        picks.append(("neck_pearls", [.neck: .pearls]))
        picks.append(("neck_pearls_beanie", [.neck: .pearls, .head: .beaniePink]))
        picks.append(("lowcap_scarf", [.neck: .scarfCosy, .head: .capTeamPink]))
        let views: [View] = [View(name: "back34", yaw: 2.5, dist: 3.6, lookBack: 0.35), View(name: "side", yaw: .pi / 2, dist: 3.6, lookBack: 0.35), View(name: "back", yaw: .pi, dist: 3.6, lookBack: 0.35)]
        for (n, outfit) in picks {
            let imgs = try cellImage(outfit, views: views)
            for (v, im) in zip(views, imgs) { try write(im.uiImage()!, "\(od)/\(n)__\(v.name).png") }
            let fit = FeatureCompat.solve(.spines, worn: outfit.values.map { $0.art })
            _ = PipSpikes.build(body: WearBody.shared, spec: .shared, layout: fit.spineLayout)
            report += "\(n): brimY=\(fit.spineBrimY.map { String(format: "%.3f", $0) } ?? "nil") hidden=\(fit.hiddenParts.sorted())  \(PipSpikes.debug)\n"
            if n.hasPrefix("perch") { XCTAssertNil(fit.spineBrimY, "a perch item moves nothing"); XCTAssertTrue(fit.hiddenParts.isEmpty) }
            if n == "beanie" || n.hasPrefix("hat_") { XCTAssertTrue(fit.hiddenParts.isEmpty, "\(n): a hat hides no spike") }
        }
        try report.write(toFile: "\(od)/hats_report.txt", atomically: true, encoding: .utf8)
    }

    /// A strip of the glide: beanie on, then off, one frame per 0.1 s, 3/4 back and side.
    func testTail4OnOff() throws {
        let d = try dir4()
        let name = PipTailVariant.active.rawValue
        let item = ProcessInfo.processInfo.environment["PIPTAIL4_ITEM"] ?? "beanie"
        let outfitOn: Outfit = item == "scarf" ? [.neck: .scarfCosy] : [.head: .beaniePink]
        let od = "\(d)/\(name)/onoff" + (item == "beanie" ? "" : "_" + item)
        try FileManager.default.createDirectory(atPath: od, withIntermediateDirectories: true)
        var chars = [Char(id: 1)]
        let lab = makeLab(chars); let dr = dress(lab, chars); settle(lab, dr, chars, frames: 40)
        let c = try makeCtx(sim: lab.rigs[0].sim, W: 400, H: 400)
        let s = subj(lab, dr, chars)
        var memo = SIMD3<Float>(0, 0, 1)
        let views: [View] = [View(name: "back34", yaw: 2.5, dist: 3.6, lookBack: 0.35), View(name: "side", yaw: .pi / 2, dist: 3.6, lookBack: 0.35)]
        var n = 0
        func shoot(_ label: String) throws {
            for v in views {
                let img = ui(render(c, s, cam: cam(v, s.sim, memo: &memo), neutral: true), "\(name) \(label) \(v.name)")
                try write(img, String(format: "%@/%03d_%@.png", od, n, v.name))
            }
            n += 1
        }
        try shoot("bare t=0")
        chars[0].outfit = outfitOn
        var log = ""
        for phase in ["\(item) on", "\(item) off"] {
            if phase.hasSuffix(" off") { chars[0].outfit = [:] }
            for f in 0..<120 {
                step(lab, dr, chars); _ = skin(s.skinner, s.sim)
                if f % 6 == 5, f < 100 { try shoot("\(phase) t=\(String(format: "%.1f", Float(f + 1) / 60))") }
                if let sl = dr.feats[0].slot(0), f % 6 == 5 { log += "\(phase) f\(f + 1): w=\(sl.layoutW) from=\(String(describing: sl.layoutFrom)) to=\(String(describing: sl.layoutTo))\n" }
            }
        }
        try log.write(toFile: od + "/glide_log.txt", atomically: true, encoding: .utf8)
    }

    // MARK: 6. closeups

    func testCloseups() throws {
        let d = try dir("closeups")
        let chars = [Char(id: 1)]
        let lab = makeLab(chars); let dr = dress(lab, chars); settle(lab, dr, chars)
        let c = try makeCtx(sim: lab.rigs[0].sim, W: 600, H: 600)
        let s = subj(lab, dr, chars)
        var cells: [UIImage] = []
        var memo = SIMD3<Float>(0, 0, 1)
        let junction: [View] = [View(name: "back34", yaw: 2.5, dist: 2.3, lookY: 0.0, lookBack: 0.85, lift: 0.25), View(name: "side", yaw: .pi / 2, dist: 2.3, lookY: 0.0, lookBack: 0.85, lift: 0.1),
                                View(name: "top", yaw: 0, dist: 2.6, lookBack: 0.85, top: true)]
        for v in junction { cells.append(ui(render(c, s, cam: cam(v, s.sim, memo: &memo), neutral: false), "junction \(v.name)")) }
        let floor: [View] = [View(name: "back34", yaw: 2.5, dist: 2.0, lookBack: 0.85, lift: 0.1, floorLook: true), View(name: "side", yaw: .pi / 2, dist: 2.0, lookBack: 0.85, lift: 0.03, floorLook: true),
                             View(name: "top", yaw: 0, dist: 2.2, lookBack: 0.85, top: true, floorLook: true)]
        for v in floor { cells.append(ui(render(c, s, cam: cam(v, s.sim, memo: &memo), neutral: false), "floor contact \(v.name)")) }
        try write(grid(cells, cols: 3), d + "/closeups.png")
    }

    // MARK: 7. walk bounce diagnostic (Pip vs Bob)

    struct WalkStats { var head = Float(0), face = Float(0), centroid = Float(0), headSD = Float(0), frames = 0, strip: [UIImage] = [] }
    private func walkSession(id: Int, path: TailPath, feature: JellyFeature? = nil, forceTailOff: Bool = false, hurry: Bool = false, ctx: Ctx? = nil, label: String) -> WalkStats {
        let chars = [Char(id: id, featureOn: path == .real)]
        let lab = makeLab(chars, path: path, positions: [SIMD2(hurry ? 2.8 : 1.8, 0.8)]); let dr = dress(lab, chars); settle(lab, dr, chars)
        let r = lab.rigs[0]
        if let f = feature { r.brain.feature = f }
        let rm = MotionRig.renderMesh
        let eggLimit = rm.armCapsule?.firstVertex.min() ?? rm.vertexCount
        var top = 0, face = 0
        var topY: Float = -9, faceZ: Float = -9
        for v in 0..<eggLimit { if rm.rest[3 * v + 1] > topY { topY = rm.rest[3 * v + 1]; top = v } }
        for v in 0..<eggLimit where rm.rest[3 * v + 1] > topY * 0.3 && rm.rest[3 * v + 1] < topY * 0.75 { if rm.rest[3 * v + 2] > faceZ { faceZ = rm.rest[3 * v + 2]; face = v } }
        let p0 = r.sim.bodyPose(iterations: 3).centroid
        r.brain.hurry = hurry
        r.brain.script = .walk(target: SIMD2(hurry ? -2.8 : -2.0, 0.8), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0
        let t0: Float = hurry ? 0.7 : 1.0
        var hs: [Float] = [], fs: [Float] = [], cs: [Float] = []
        var t: Float = 0
        var stripHeads: [(UIImage?, Float)] = []
        let stripTimes: [Float] = [1.5, 1.64, 1.78, 1.92]
        var si = 0
        let s = subj(lab, dr, chars)
        while t < 6 {
            step(lab, dr, chars); t += 1.0 / 60
            if forceTailOff { r.skinner.tailOn = false }
            let d = skin(r.skinner, r.sim)
            if t > t0 && r.brain.activity == .walking { hs.append(d[6 * top + 1]); fs.append(d[6 * face + 1]); cs.append(r.sim.centroid().y) }
            if let c = ctx, si < stripTimes.count, t >= stripTimes[si] {
                let cc = r.sim.centroid()
                let cm = camera(eye: SIMD3(cc.x, p0.y + 0.25, 0) + SIMD3(0, 0.6, 4.6), target: SIMD3(cc.x, p0.y + 0.25, cc.z))
                stripHeads.append((ui(render(c, s, cam: cm, neutral: false), String(format: "%@ t=%.2f head top y=%.3f face y=%.3f", label, t, d[6 * top + 1], d[6 * face + 1])), d[6 * top + 1])); si += 1
            }
            if t > t0 && r.brain.activity != .walking { break }
        }
        func p2p(_ a: [Float]) -> Float { (a.max() ?? 0) - (a.min() ?? 0) }
        let mean = hs.reduce(0, +) / Float(max(hs.count, 1))
        let sd = (hs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(max(hs.count, 1))).squareRoot()
        return WalkStats(head: p2p(hs), face: p2p(fs), centroid: p2p(cs), headSD: sd, frames: hs.count, strip: stripHeads.compactMap { $0.0 })
    }

    func testWalkBob() throws {
        let d = try dir("walk")
        let base = makeLab([Char(id: 1)])
        let c = try makeCtx(sim: base.rigs[0].sim, W: 420, H: 420)
        var report = "walk head/face bob (peak-to-peak, world units; body height ~1.3) over the walking frames after t>1 s\n"
        var rows: [UIImage] = []
        let cases: [(String, Int, TailPath, JellyFeature?, Bool, Bool, Bool)] = [
            ("Pip real (spines, tail on)", 1, .real, nil, false, true, false), ("Bob real", 0, .real, nil, false, true, false), ("Moss real", 2, .real, nil, false, false, false), ("Lavender real", 3, .real, nil, false, false, false),
            ("Pip real but tailOn forced OFF (personality kept)", 1, .real, nil, true, false, false), ("Pip feature .none (no tail, no Pip personality)", 1, .real, JellyFeature.none, false, false, false),
            ("Pip bare MotionRig (no configureTail)", 1, .bare, nil, false, false, false), ("Pip bareCfg (configureTail, feature none)", 1, .bareCfg, nil, false, false, false),
            ("RUN Pip real", 1, .real, nil, false, false, true), ("RUN Bob real", 0, .real, nil, false, false, true), ("RUN Moss real", 2, .real, nil, false, false, true), ("RUN Pip feature .none", 1, .real, JellyFeature.none, false, false, true),
        ]
        for (name, id, path, feat, off, strip, hurry) in cases {
            let st = walkSession(id: id, path: path, feature: feat, forceTailOff: off, hurry: hurry, ctx: strip ? c : nil, label: name)
            let line = String(format: "%@: head p2p %.4f  face p2p %.4f  centroid p2p %.4f  head sd %.4f  (%d frames)", name, st.head, st.face, st.centroid, st.headSD, st.frames)
            report += line + "\n"; NSLog("WALKBOB %@", line)
            if strip && st.strip.count == 4 { rows.append(grid(st.strip, cols: 4)) }
        }
        try report.write(toFile: d + "/walk_bob.txt", atomically: true, encoding: .utf8)
        if rows.count >= 2 { try write(grid(rows, cols: 1), d + "/walk_bob_vs_pip.png") }
    }
}
