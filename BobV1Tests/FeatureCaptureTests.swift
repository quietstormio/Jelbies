//
//  FeatureCaptureTests.swift
//  Not a regression test: renders the character features (Pip's spines, Moss's daisy, Lavender's wings) with the REAL renderer when CHAR_CAP_DIR is
//  set (TEST_RUNNER_CHAR_CAP_DIR). One body per pass like the other capture suites (each rig rendered alone and pasted over an empty-room render).
//  CHAR_CAP_LAND=1 renders the lineup in landscape.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class FeatureCaptureTests: XCTestCase {
    var W = 603 * 2, H = 1311 * 2
    nonisolated(unsafe) static var keep: [AnyObject] = []
    typealias Outfit = [WearSlot: WearLook]

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0) }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DayClock.shared.forcedHour = 12 }

    private func dir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["CHAR_CAP_DIR"], !d.isEmpty else { throw XCTSkip("CHAR_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    /// A character on a rig: the roster id (palette + feature) and what he wears.
    struct Char { var id: Int; var outfit: Outfit = [:] }

    private func renderer(_ lab: SocialTests.Lab) throws -> (MelonRenderer, MTLTexture) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let r0 = lab.rigs[0]
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r0.sim.edges, particleCount: r0.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        return (ren, device.makeTexture(descriptor: td)!)
    }

    private func setUpLab(_ positions: [SIMD2<Float>], chars: [Char], seed: UInt64 = 5) -> SocialTests.Lab {
        let lab = SocialTests.Lab(n: positions.count, positions: positions, quiet: true, seed: seed)
        SocialTests.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.skinner.autoBlink = false; r.brain.feature = JellyRoster.feature(chars[k].id)
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        }
        WearBody.install(MotionRig.renderMesh)
        return lab
    }

    /// The wardrobe + feature of every rig (id 0 each: the renderer draws one body per pass).
    final class Dressed { var worn: [WornSet] = [], feats: [FeatureSet] = [] }
    private func dress(_ lab: SocialTests.Lab, _ chars: [Char]) -> Dressed {
        let d = Dressed()
        for (k, r) in lab.rigs.enumerated() {
            let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; Self.keep.append(w)
            let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f)
            d.worn.append(w); d.feats.append(f)
            for _ in 0..<3 { tick(d, k, r, chars[k]) }
        }
        return d
    }
    private func tick(_ d: Dressed, _ k: Int, _ r: MotionRig, _ c: Char, dt: Float = 1.0 / 60) {
        let w = d.worn[k], f = d.feats[k]
        w.tick(id: 0, brain: r.brain, sim: r.sim, outfit: c.outfit, role: .none, hideAll: false, dt: dt)
        var art: [String] = []
        for s in WearSlot.allCases where s != .feet { if let l = w.shown(0, s), !l.art.isEmpty { art.append(l.art) } }
        f.tick(id: 0, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(c.id), worn: art, hideAll: false, dt: dt)
        if let s = f.slot(0) { w.setArtOverride(0, s.fit.hatVariant); r.brain.wingsFolded = s.fit.folded; r.brain.wingFlapLimit = s.fit.flapMax }
    }

    private func skin(_ r: MotionRig) -> [Float] {
        var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &d)
        return d
    }

    private func composite(_ lab: SocialTests.Lab, _ d: Dressed, _ chars: [Char], _ ren: MelonRenderer, _ target: MTLTexture, cam camOverride: CameraState? = nil, hour: Double? = 12, bboxes: ((Int, CGRect) -> Void)? = nil) -> LockImage {
        let cam = camOverride ?? GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        ren.dayHourOverride = hour
        func shot(only: Int?) -> LockImage {
            let k = only ?? 0
            let light = GameCamera.light(centroids: lab.rigs.map { $0.sim.centroid() })
            ren.beginFrame()
            let r = lab.rigs[k]
            r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            if only == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
            if let o = only {
                let sk = skin(r)
                if d.worn[o].shown(0, .hands) != nil { d.worn[o].setArms(0, GameCare.armFrames(brain: r.brain, sim: r.sim)) }
                var f = sk.withUnsafeBufferPointer { p in d.worn[o].frame(theme: ren.room!.theme, time: 0.4) { _ in p.baseAddress } }
                let ff = sk.withUnsafeBufferPointer { p in d.feats[o].frame { _ in p.baseAddress } }
                let base = UInt32(f.opaque.vertices.count)
                f.opaque.vertices += ff.vertices; f.opaque.indices += ff.indices.map { $0 + base }
                let sb = RoomMeshBuilder(); sb.material = .plain
                if let look = chars[o].outfit[.feet], let beans = GameCare.footBeans(brain: r.brain, sim: r.sim, skinner: r.skinner) {
                    for s in 0..<2 { ShoeModel.build(look, bean: beans[s], floorY: r.sim.floorY, time: 0.4, side: s, body: JellyRoster.palette(chars[o].id)?.flesh ?? SIMD3(0.35, 0.5, 0.9), gpuPaint: false, into: sb) }
                }
                ren.room!.setWear(opaque: f.opaque, translucent: f.translucent, bounds: [])
                ren.room!.setShoes(sb.mesh)
                ren.setJersey(d.worn[o].jersey(0), body: 0)
            } else {
                ren.room!.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []); ren.room!.setShoes(RoomMesh()); ren.setJersey(nil, body: 0)
            }
            ren.setMouth(0, body: 0)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = JellyRoster.palette(chars[k].id) ?? PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            return LockImage(w: W, h: H, bgra: px)
        }
        _ = shot(only: nil)
        let empty = shot(only: nil)
        var out = empty
        for k in (0..<lab.rigs.count).sorted(by: { lab.rigs[$0].sim.centroid().z < lab.rigs[$1].sim.centroid().z }) {
            let b = shot(only: k)
            var x0 = W, x1 = -1, y0 = H, y1 = -1
            for p in 0..<(W * H) {
                var dd = 0
                for c in 0..<3 { dd = max(dd, abs(Int(b.bgra[4 * p + c]) - Int(empty.bgra[4 * p + c]))) }
                if dd > 3 {
                    for c in 0..<4 { out.bgra[4 * p + c] = b.bgra[4 * p + c] }
                    let px = p % W, py = p / W
                    x0 = min(x0, px); x1 = max(x1, px); y0 = min(y0, py); y1 = max(y1, py)
                }
            }
            bboxes?(k, CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1))
        }
        return out
    }

    static func lookCamera(target: SIMD3<Float>, dir: SIMD3<Float>, dist: Float, aspect: Float, lift: Float = 0.1) -> CameraState {
        let eye = target + dir * dist + SIMD3(0, dist * lift, 0)
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        return cam
    }

    // MARK: sheets

    private func labelled(_ img: UIImage, _ text: String) -> UIImage {
        let w = img.size.width, h = img.size.height, bar: CGFloat = 40
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + bar), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + bar))
            (text as NSString).draw(at: CGPoint(x: 10, y: 9), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white])
            img.draw(in: CGRect(x: 0, y: bar, width: w, height: h))
        }
    }
    private func hstack(_ imgs: [UIImage]) -> UIImage {
        let h = imgs.map { $0.size.height }.max() ?? 0, w = imgs.reduce(0) { $0 + $1.size.width }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            var x: CGFloat = 0
            for i in imgs { i.draw(at: CGPoint(x: x, y: 0)); x += i.size.width }
        }
    }
    private func vstack(_ imgs: [UIImage]) -> UIImage {
        let w = imgs.map { $0.size.width }.max() ?? 0, h = imgs.reduce(0) { $0 + $1.size.height }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            var y: CGFloat = 0
            for i in imgs { i.draw(at: CGPoint(x: 0, y: y)); y += i.size.height }
        }
    }
    private func write(_ img: UIImage, _ path: String) throws { try img.pngData()!.write(to: URL(fileURLWithPath: path)) }

    /// The part of a room frame around the Jellies.
    private func cropJellies(_ img: LockImage, _ lab: SocialTests.Lab, cam: CameraState, pad: Float = 0.09) -> UIImage? {
        let pts = lab.rigs.map { r -> SIMD2<Float> in
            let c = r.sim.centroid(); let k = cam.viewProj * SIMD4<Float>(c.x, c.y, c.z, 1)
            return SIMD2((k.x / k.w * 0.5 + 0.5) * Float(W), (1 - (k.y / k.w * 0.5 + 0.5)) * Float(H))
        }
        let lo = pts.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }, hi = pts.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        let mid = (lo + hi) / 2
        let hw = max((hi.x - lo.x) / 2 + Float(W) * pad, Float(W) * 0.2), hh = max((hi.y - lo.y) / 2 + Float(H) * 0.08, hw * 0.55)
        let r = CGRect(x: CGFloat(mid.x - hw), y: CGFloat(mid.y - hh * 1.2), width: CGFloat(hw * 2), height: CGFloat(hh * 2)).intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard let cg = img.cgImage(), let part = cg.cropping(to: r) else { return nil }
        return UIImage(cgImage: part)
    }

    /// A 900 x 900 close-up of rig 0 of a one-character lab from `yaw` radians round his facing (0 front, pi back).
    private func closeup(_ c: Char, yaw: Float, label: String, seed: UInt64 = 3, dist: Float = 3.4, lookY: Float = 0.25, lookBack: Float = 0, lift: Float = 0.1, prepare: ((SocialTests.Lab, Dressed) -> Void)? = nil) throws -> UIImage {
        W = 900; H = 900
        let chars = [c]
        let lab = setUpLab([SIMD2(0.2, 0.6)], chars: chars, seed: seed)
        let (ren, target) = try renderer(lab)
        let d = dress(lab, chars)
        prepare?(lab, d)
        let r = lab.rigs[0]
        var sk0 = skin(r); for _ in 0..<30 { sk0 = skin(r) }                    // the tail eases in over 0.15 s of skinner updates: let it finish
        if label.contains("back34"), let tf = MotionRig.renderMesh.armCapsule?.tailFirst {
            var t = "tailOn=\(r.skinner.tailOn) tailFirst=\(tf)\n"
            for ring in stride(from: 0, to: TailBean.rings, by: 3) { let i = tf + 1 + TailBean.around * ring; t += String(format: "ring %d: (%.2f,%.2f,%.2f)\n", ring, sk0[6 * i], sk0[6 * i + 1], sk0[6 * i + 2]) }
            try? t.write(toFile: (ProcessInfo.processInfo.environment["CHAR_CAP_DIR"] ?? "/tmp") + "/dbg2.txt", atomically: true, encoding: .utf8)
        }
        let pose = r.sim.bodyPose(iterations: 3)
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_normalize(fwd)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let cc = pose.centroid
        let cam = Self.lookCamera(target: SIMD3(cc.x - fwd.x * lookBack, cc.y + lookY, cc.z - fwd.z * lookBack), dir: dir, dist: dist, aspect: 1, lift: lift)
        let img = composite(lab, d, chars, ren, target, cam: cam)
        return labelled(img.uiImage()!, label)
    }

    func testCaptureFeaturesCloseup() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        var rows: [UIImage] = []
        for (name, id) in [("Pip: two-tone spines", 1), ("Moss: daisy sprout", 2), ("Lavender: feathered wings", 3)] {
            var cells: [UIImage] = []
            for (label, yaw) in [("front", Float(0)), ("3/4", Float(0.7)), ("back", Float.pi)] {
                cells.append(try closeup(Char(id: id), yaw: yaw, label: "\(name) \(label)"))
            }
            rows.append(hstack(cells))
        }
        try write(vstack(rows), d + "/features_closeup.png")
    }

    func testCaptureLineupInGame() throws {
        let d = try dir()
        let land = !(ProcessInfo.processInfo.environment["CHAR_CAP_LAND"] ?? "").isEmpty
        if land { W = 1311 * 2; H = 603 * 2 } else { W = 603 * 2; H = 1311 * 2 }
        DayClock.shared.forcedHour = 12
        let chars = [Char(id: 0), Char(id: 1), Char(id: 2), Char(id: 3)]
        let positions: [SIMD2<Float>] = land ? [SIMD2(-2.6, 0.6), SIMD2(-0.9, 0.9), SIMD2(0.9, 0.9), SIMD2(2.6, 0.6)] : [SIMD2(-1.6, 0.3), SIMD2(-0.55, 1.2), SIMD2(0.55, 1.2), SIMD2(1.6, 0.3)]
        let lab = setUpLab(positions, chars: chars, seed: 9)
        for r in lab.rigs { r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim); r.brain.idleState.goalYaw = r.faceYaw; r.brain.idleState.hold = 0.01 }
        for _ in 0..<120 { lab.tick(watching: false) }
        let (ren, target) = try renderer(lab)
        let dd = dress(lab, chars)
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        let img = composite(lab, dd, chars, ren, target, cam: cam)
        let crop = cropJellies(img, lab, cam: cam) ?? img.uiImage()!
        try write(labelled(crop, "Bob, Pip (spines), Moss (daisy), Lavender (wings) in the room" + (land ? " (landscape)" : " (portrait)")), d + (land ? "/landscape_lineup.png" : "/lineup_ingame.png"))
    }

    /// W6: the medal ribbon from four angles on all four Jelbies, plus the backpack and cape combos.
    func testCaptureMedalWrap() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        let cols: [(String, Float)] = [("front", 0), ("3/4", 0.7), ("side", .pi / 2), ("back", .pi)]
        var rows: [UIImage] = []
        for (name, id) in [("Bob", 0), ("Pip", 1), ("Moss", 2), ("Lavender", 3)] {
            var cells: [UIImage] = []
            for (label, yaw) in cols { cells.append(try closeup(Char(id: id, outfit: [.neck: .medalGold]), yaw: yaw, label: "\(name) medal \(label)")) }
            rows.append(hstack(cells))
        }
        var extra: [UIImage] = []
        for (label, yaw) in [("3/4", Float(0.7)), ("back", Float.pi)] {
            extra.append(try closeup(Char(id: 3, outfit: [.neck: .medalGold, .body: .backpackSky]), yaw: yaw, label: "Lavender medal + backpack \(label)"))
        }
        for (label, yaw) in [("3/4", Float(0.7)), ("back", Float.pi)] {
            extra.append(try closeup(Char(id: 1, outfit: [.neck: .medalGold, .body: .capeHero]), yaw: yaw, label: "Pip medal + cape \(label)"))
        }
        rows.append(hstack(extra))
        try write(vstack(rows), d + "/medal_wrap.png")
    }

    func testCaptureMedalLineup() throws {
        let d = try dir()
        let land = !(ProcessInfo.processInfo.environment["CHAR_CAP_LAND"] ?? "").isEmpty
        if land { W = 1311 * 2; H = 603 * 2 } else { W = 603 * 2; H = 1311 * 2 }
        DayClock.shared.forcedHour = 12
        let chars = (0..<4).map { Char(id: $0, outfit: [.neck: .medalGold]) }
        let positions: [SIMD2<Float>] = land ? [SIMD2(-2.6, 0.6), SIMD2(-0.9, 0.9), SIMD2(0.9, 0.9), SIMD2(2.6, 0.6)] : [SIMD2(-1.6, 0.3), SIMD2(-0.55, 1.2), SIMD2(0.55, 1.2), SIMD2(1.6, 0.3)]
        let lab = setUpLab(positions, chars: chars, seed: 9)
        for r in lab.rigs { r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim); r.brain.idleState.goalYaw = r.faceYaw; r.brain.idleState.hold = 0.01 }
        for _ in 0..<120 { lab.tick(watching: false) }
        let (ren, target) = try renderer(lab)
        let dd = dress(lab, chars)
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        let img = composite(lab, dd, chars, ren, target, cam: cam)
        let crop = cropJellies(img, lab, cam: cam) ?? img.uiImage()!
        try write(labelled(crop, "Medals on Bob, Pip, Moss, Lavender" + (land ? " (landscape)" : " (portrait)")), d + (land ? "/medal_lineup_landscape.png" : "/medal_lineup_portrait.png"))
    }

    /// Pip's spines through the crown of every enclosing hat: front 3/4 and back (pip_spines_hats.png).
    func testCaptureCrownFit() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        var sp: [UIImage] = []
        for (name, look) in [("beret", WearLook.beret), ("pirate", .pirateHat), ("bucket", .bucketHat), ("cowboy", .cowboyHat), ("beanie", .beanieHoney)] {
            sp.append(try closeup(Char(id: 1, outfit: [.head: look]), yaw: 0.7, label: "Pip + \(name) 3/4"))
            sp.append(try closeup(Char(id: 1, outfit: [.head: look]), yaw: Float.pi * 0.85, label: "Pip + \(name) back"))
        }
        try write(vstack([hstack(Array(sp[0..<4])), hstack(Array(sp[4..<8])), hstack(Array(sp[8..<10]))]), d + "/pip_spines_hats.png")
    }

    /// Pip's small default spikes: no hat (3/4 + side), five hats (3/4 + back), the cowboy hat squashed and stretched (pip_small_spikes.png).
    func testCaptureSmallSpikes() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        var sp: [UIImage] = []
        sp.append(try closeup(Char(id: 1), yaw: 0.7, label: "Pip no hat 3/4"))
        sp.append(try closeup(Char(id: 1), yaw: Float.pi / 2, label: "Pip no hat side"))
        for (name, look) in [("beret", WearLook.beret), ("pirate", .pirateHat), ("bucket", .bucketHat), ("cowboy", .cowboyHat), ("beanie", .beanieHoney)] {
            sp.append(try closeup(Char(id: 1, outfit: [.head: look]), yaw: 0.7, label: "Pip + \(name) 3/4"))
            sp.append(try closeup(Char(id: 1, outfit: [.head: look]), yaw: Float.pi * 0.85, label: "Pip + \(name) back"))
        }
        for (hn, hl) in [("cowboy", WearLook.cowboyHat), ("pirate", .pirateHat), ("bucket", .bucketHat), ("beret", .beret), ("beanie", .beanieHoney)] {
            for (sq, name) in [(Float(1.35), "stretch"), (Float(0.75), "squash")] {
                let c = Char(id: 1, outfit: [.head: hl])
                sp.append(try closeup(c, yaw: 0.7, label: "Pip + \(hn) \(name) 3/4") { lab, dr in
                    let r = lab.rigs[0]
                    r.sim.attractor.squash = sq
                    for _ in 0..<90 { r.sim.step(); r.brain.currentPose(r.sim); self.tick(dr, 0, r, c) }
                })
            }
        }
        var rows: [UIImage] = []
        var i = 0
        while i < sp.count { rows.append(hstack(Array(sp[i..<min(i + 4, sp.count)]))); i += 4 }
        try write(vstack(rows), d + "/pip_small_spikes.png")
    }

    /// Review sheet: the batch-3 wearables (headphones, cowboy hat, beret, hair bow, bee antennae, lei) on Pip, Moss and Lavender, front 3/4, normal pose.
    func testCaptureBatch3Wear() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        var rows: [UIImage] = []
        for (name, id) in [("Pip", 1), ("Moss", 2), ("Lavender", 3)] {
            var cells: [UIImage] = []
            for (label, look) in [("headphones", WearLook.headphones), ("cowboy hat", .cowboyHat), ("beret", .beret), ("hair bow", .hairBow), ("bee antennae", .beeAntennae), ("lei", .lei)] {
                cells.append(try closeup(Char(id: id, outfit: [look.slot: look]), yaw: 0.6, label: "\(name) + \(label)"))
            }
            rows.append(hstack(cells))
        }
        try write(vstack(rows), d + "/batch3_wear.png")
    }

    func testCaptureDaisyHats() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        let hats: [(String, WearLook)] = [("honey beanie (no pom)", .beanieHoney), ("sky team cap (no button)", .capTeamSky), ("party hat (short)", .partyHat),
                                           ("mint bucket hat", .bucketHat), ("cat ears", .catEars), ("tiny top hat", .tophat),
                                           ("chef hat", .chefHat), ("witch hat", .witchHat), ("flower crown", .flowerCrown)]
        var cells: [UIImage] = []
        for (name, look) in hats { cells.append(try closeup(Char(id: 2, outfit: [.head: look]), yaw: 0.55, label: "Moss + \(name)")) }
        var rows: [UIImage] = []
        var i = 0
        while i < cells.count { rows.append(hstack(Array(cells[i..<min(i + 3, cells.count)]))); i += 3 }
        try write(vstack(rows), d + "/daisy_hats.png")
    }

    func testCaptureOutfitsAlt() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        let sets: [[Char]] = [
            [Char(id: 1, outfit: [.body: .capeHero, .face: .sunglassesStar, .feet: .sneakerSun]), Char(id: 2, outfit: [.head: .bucketHatPink, .neck: .bowtiePink, .feet: .rainBoots]), Char(id: 3, outfit: [.body: .backpackSky, .face: .glassesRound, .feet: .balletPink])],
            [Char(id: 1, outfit: [.head: .sweatband, .neck: .whistleCoach, .hands: .wristbandsSky, .feet: .sneakerLightup]), Char(id: 2, outfit: [.head: .partyHat, .body: .tutuPink, .neck: .pearls, .feet: .glitterShoes]), Char(id: 3, outfit: [.head: .beaniePink, .neck: .scarfSky, .hands: .gloveSky, .feet: .frogBoots])],
        ]
        let labels = ["Alt 1: Pip cape+shades | Moss bucket hat+bow tie | Lavender backpack+glasses (wings up)",
                      "Alt 2: Pip sweatband+whistle | Moss party hat+tutu+pearls | Lavender beanie+scarf (wings low)"]
        var rows: [UIImage] = []
        for (n, chars) in sets.enumerated() {
            W = 603 * 2; H = 1311 * 2
            let lab = setUpLab([SIMD2(-1.9, 0.5), SIMD2(0.1, 0.9), SIMD2(2.0, 0.4)], chars: chars, seed: UInt64(5 + n))
            let (ren, target) = try renderer(lab)
            let dd = dress(lab, chars)
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            let img = composite(lab, dd, chars, ren, target, cam: cam)
            if let c = cropJellies(img, lab, cam: cam) { rows.append(labelled(c, labels[n])) }
        }
        try write(vstack(rows), d + "/outfits_alt.png")
    }

    /// wings_v2: the wings before (full size) / after (0.85 about the hinges) from the front 3/4 and the back, and a 6-frame strip of one flap burst.
    func testCaptureWingsV2() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        let was = FeatureMeshes.wingScale
        defer { FeatureMeshes.wingScale = was; FeatureMeshes.clearCache() }
        var rows: [UIImage] = []
        for (name, scale) in [("BEFORE (full size)", Float(1)), ("AFTER (0.85 about the hinge)", Float(0.85))] {
            FeatureMeshes.wingScale = scale; FeatureMeshes.clearCache()
            var cells: [UIImage] = []
            for (label, yaw) in [("front 3/4", Float(0.7)), ("back", Float.pi), ("back 3/4", Float(2.4))] {
                cells.append(try closeup(Char(id: 3), yaw: yaw, label: "Lavender wings \(name): \(label)") { lab, _ in lab.rigs[0].brain.autonomy = false })
            }
            rows.append(hstack(cells))
        }
        try write(vstack(rows), d + "/wings_size_before_after.png")
        // the burst strip (the smaller wings)
        FeatureMeshes.wingScale = 0.85; FeatureMeshes.clearCache()
        W = 900; H = 900
        let chars = [Char(id: 3)]
        let lab = setUpLab([SIMD2(0.2, 0.6)], chars: chars, seed: 3)
        let (ren, target) = try renderer(lab)
        let dd = dress(lab, chars)
        let r = lab.rigs[0]
        r.brain.autonomy = false; r.brain.expr.enabled = false
        let pose0 = r.sim.bodyPose(iterations: 3)
        var fwd = pose0.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0; fwd = simd_normalize(fwd)
        let yaw: Float = 2.3
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let c0 = pose0.centroid
        let cam = Self.lookCamera(target: SIMD3(c0.x, c0.y + 0.25, c0.z), dir: dir, dist: 3.4, aspect: 1)
        for _ in 0..<30 { lab.tick(watching: false); tick(dd, 0, r, chars[0]) }
        dd.feats[0].primeBurst(0)
        var frames: [UIImage] = []
        let fracs: [Float] = [0.06, 0.22, 0.39, 0.56, 0.73, 0.9]
        var fi = 0, ticks = 0, started = false
        while fi < fracs.count && ticks < 600 {
            lab.tick(watching: false); tick(dd, 0, r, chars[0]); ticks += 1
            guard let s = dd.feats[0].slot(0) else { continue }
            if s.burstActive { started = true }
            if started, !s.burstActive { break }
            guard s.burstActive else { continue }
            let dur = Float(s.burstN) / s.burstHz
            if s.burstT / dur >= fracs[fi] {
                let img = composite(lab, dd, chars, ren, target, cam: cam)
                frames.append(labelled(img.uiImage()!, String(format: "burst t=%.2f/%.2fs  %d flaps @ %.1f Hz  amp %.0f  flap %+.0f deg", s.burstT, dur, s.burstN, s.burstHz, s.burstAmp, s.flap)))
                fi += 1
            }
        }
        XCTAssertEqual(frames.count, 6, "six frames across one burst")
        if frames.count == 6 { try write(vstack([hstack(Array(frames[0..<3])), hstack(Array(frames[3..<6]))]), d + "/wings_burst_strip.png") }
    }

    func testCaptureLavenderHop() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        W = 900; H = 900
        let chars = [Char(id: 3)]
        let lab = setUpLab([SIMD2(0.2, 0.6)], chars: chars, seed: 3)
        let (ren, target) = try renderer(lab)
        let dd = dress(lab, chars)
        let r = lab.rigs[0]
        // face a little away from the camera so the lift and the drift read
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.flapHop, r.sim))
        let pose0 = r.sim.bodyPose(iterations: 3)
        var fwd = pose0.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0; fwd = simd_normalize(fwd)
        let yaw: Float = 0.9
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let c0 = pose0.centroid
        let cam = Self.lookCamera(target: SIMD3(c0.x + fwd.x * 0.3, c0.y + 0.3, c0.z + fwd.z * 0.3), dir: dir, dist: 4.2, aspect: 1, lift: 0.12)
        let times: [(Float, String)] = [(0.2, "crouch, wings tucked"), (0.62, "launch, big flap"), (1.2, "rising, feet dangle"), (1.8, "hover ~0.33 u, rapid flaps"), (2.9, "tiring, coming down"), (3.38, "PLOP: squash, wings flop")]
        var frames: [UIImage] = []
        var ti = 0
        var t: Float = 0
        while ti < times.count && t < 5 {
            lab.tick(watching: false); t += 1.0 / 60
            tick(dd, 0, r, chars[0])
            if t >= times[ti].0 {
                let img = composite(lab, dd, chars, ren, target, cam: cam)
                frames.append(labelled(img.uiImage()!, String(format: "t=%.2fs lift %.2f: %@", t, r.brain.flapHop.lift, times[ti].1)))
                ti += 1
            }
        }
        XCTAssertEqual(frames.count, 6)
        try write(vstack([hstack(Array(frames[0..<3])), hstack(Array(frames[3..<6]))]), d + "/lavender_hop.png")
    }

    /// 2026-10-27 (cartwheel feet): a cartwheel's crouch, take-off, inverted, descent and landing frames for one character.
    private func cartwheelSheet(id: Int, name: String, shoes: Bool = false) throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        W = 700; H = 700
        let chars = [Char(id: id, outfit: shoes ? [.feet: .rainBoots] : [:])]
        let lab = setUpLab([SIMD2(0.2, 0.6)], chars: chars, seed: 3)
        let (ren, target) = try renderer(lab)
        let dd = dress(lab, chars)
        let r = lab.rigs[0]
        r.brain.shoesWorn = shoes
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.cartwheel, r.sim))
        let cam0 = r.brain.cameraPosXZ, c00 = r.sim.bodyPose(iterations: 3).centroid
        var dir3 = SIMD3<Float>(cam0.x - c00.x, 0, cam0.y - c00.z); dir3 = simd_normalize(dir3)
        var frames: [UIImage] = []
        var want: [(String, (BlobBrain) -> Bool)] = [("crouch", { $0.gait.phase == .crouch }), ("take-off", { $0.gait.phase == .air && $0.gait.flipU > 0.08 }), ("rising", { $0.gait.phase == .air && $0.gait.flipU > 0.28 }), ("inverted", { $0.gait.phase == .air && $0.gait.flipU > 0.5 }), ("coming down", { $0.gait.phase == .air && $0.gait.flipU > 0.78 }), ("landing", { $0.gait.phase == .land })]
        var t: Float = 0, lastShot: Float = -1
        while !want.isEmpty && t < 8 {
            lab.tick(watching: false); t += 1.0 / 60
            tick(dd, 0, r, chars[0])
            if want[0].1(r.brain), t - lastShot > 0.04 {
                let c = r.sim.bodyPose(iterations: 3).centroid
                let cam = Self.lookCamera(target: SIMD3(c.x, 0.55, c.z), dir: dir3, dist: 4.4, aspect: 1, lift: 0.08)
                let img = composite(lab, dd, chars, ren, target, cam: cam)
                frames.append(labelled(img.uiImage()!, String(format: "%@ t=%.2f", want[0].0, t)))
                want.removeFirst(); lastShot = t
            }
        }
        XCTAssertGreaterThanOrEqual(frames.count, 5, "the cartwheel reached its phases")
        try write(vstack([hstack(Array(frames.prefix(3))), hstack(Array(frames.dropFirst(3)))]), d + "/cartwheel_\(name).png")
    }
    func testCaptureCartwheelPip() throws { try cartwheelSheet(id: 1, name: "pip") }
    func testCaptureCartwheelLavender() throws { try cartwheelSheet(id: 3, name: "lavender") }
    func testCaptureCartwheelMossShoes() throws { try cartwheelSheet(id: 2, name: "moss_shoes", shoes: true) }

    // MARK: Pip's teardrop tail + back spikes

    func testCapturePipTeardrop() throws {
        let d = try dir(); DayClock.shared.forcedHour = 12
        var t: [UIImage] = []
        t.append(try closeup(Char(id: 1), yaw: 0.7, label: "Pip: front 3/4"))
        t.append(try closeup(Char(id: 1), yaw: Float.pi * 0.85, label: "Pip: back 3/4"))
        t.append(try closeup(Char(id: 1, outfit: [.head: .cowboyHat]), yaw: 0.7, label: "Pip: cowboy hat 3/4"))
        t.append(try closeup(Char(id: 1), yaw: Float.pi / 2, label: "Pip: side"))
        let c = Char(id: 1)
        t.append(try closeup(c, yaw: 0.9, label: "Pip: mid-hop") { lab, dr in
            let r = lab.rigs[0]
            r.brain.feature = .wings; r.brain.idleForced = true
            _ = r.brain.idleStart(.flapHop, r.sim)
            for _ in 0..<110 { lab.tick(watching: false); self.tick(dr, 0, r, c) }
            r.brain.feature = .spines
        })
        t.append(try closeup(Char(id: 1, outfit: [.head: .beret]), yaw: 0.7, label: "Pip: beret 3/4"))
        // large close-ups on the back and tail: the side, and a back 3/4
        let z1 = try closeup(Char(id: 1), yaw: Float.pi / 2, label: "Pip: side close-up (back + tail)", dist: 1.7, lookY: 0.0, lookBack: 0.45)
        let z2 = try closeup(Char(id: 1), yaw: Float.pi * 0.8, label: "Pip: back 3/4 close-up", dist: 1.7, lookY: 0.0, lookBack: 0.4)
        NSLog("PIPLAYOUT spacing=%.3f widths=%@ minGap=%.3f", PipSpikes.lastLayout.spacing, PipSpikes.lastLayout.widths.map { String(format: "%.3f", $0) }.joined(separator: ","), PipSpikes.lastLayout.minGap)
        try write(vstack([hstack(Array(t[0..<3])), hstack(Array(t[3..<6])), hstack([z1, z2])]), d + "/pip_tail_pro8.png")
    }

    /// Pip's new long tail: back 3/4, side, front 3/4, top-ish close-ups and a walking frame (piptail2_*.png).
    func testPipTailDbg() throws {
        let d = try dir()
        let sh = TailBean.shape
        var dbg = String(format: "width=%.3f length=%.3f sink=%.3f root=(%.2f,%.2f,%.2f)\n", sh.width, sh.length, sh.sink, sh.root.x, sh.root.y, sh.root.z)
        var tt = 0.0; while tt <= sh.length { let q = sh.point(tt); dbg += String(format: "t%.2f (%.2f,%.2f,%.2f) r%.3f\n", tt, q.x, q.y, q.z, sh.radius(tt)); tt += 0.15 }
        let r = MotionRig(game: true); Self.keepRigs.append(r)
        r.skinner.tailOn = true
        r.sim.teleport(toXZ: SIMD2(0, 0)); for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        var dd = skin(r); dd = skin(r)
        let tf = MotionRig.renderMesh.armCapsule!.tailFirst; r.skinner.tailFirst = tf
        dbg += "tailFirst=\(tf) vertexCount=\(MotionRig.renderMesh.vertexCount) tailV=\(TailBean.vertexCount)\n"
        var ymin: Float = 9; for i in 0..<tf { ymin = min(ymin, dd[6 * i + 1]) }
        dbg += "min y of body+feet verts = \(ymin)\n"
        for ring in stride(from: 0, to: TailBean.rings, by: 3) { let i = tf + 1 + TailBean.around * ring; dbg += String(format: "ring %d centre-ish v: (%.2f,%.2f,%.2f)\n", ring, dd[6 * i], dd[6 * i + 1], dd[6 * i + 2]) }
        try dbg.write(toFile: d + "/dbg.txt", atomically: true, encoding: .utf8)
    }
    static var keepRigs: [MotionRig] = []

    func testCapturePipTail2() throws {
        let d = try dir(); DayClock.shared.forcedHour = 12
        let c = Char(id: 1)
        let sh = TailBean.shape
        var dbg = String(format: "TAILDBG width=%.3f length=%.3f sink=%.3f root=(%.2f,%.2f,%.2f)", sh.width, sh.length, sh.sink, sh.root.x, sh.root.y, sh.root.z)
        var tt = 0.0; while tt <= sh.length { let q = sh.point(tt); dbg += String(format: " | t%.2f (%.2f,%.2f,%.2f) r%.3f", tt, q.x, q.y, q.z, sh.radius(tt)); tt += 0.2 }
        try dbg.write(toFile: d + "/dbg.txt", atomically: true, encoding: .utf8)
        let views: [(String, Float)] = (ProcessInfo.processInfo.environment["TAIL_VIEWS_ONLY"] != nil ? [("view1.3", Float.pi * 1.4), ("back34", Float.pi * 1.2), ("front34", 0.9)] : [])
        for (n, y) in views { try write(try closeup(c, yaw: y, label: "Pip \(n)", dist: 4.6, lookY: 0.15, lookBack: 0.5, lift: 0.3), d + "/piptail2_\(n).png") }
        if ProcessInfo.processInfo.environment["TAIL_VIEWS_ONLY"] != nil { return }
        try write(try closeup(c, yaw: Float.pi * 0.8, label: "walk back 3/4", dist: 4.6, lookY: 0.15, lookBack: 0.5, lift: 0.3) { lab, dr in
            let r = lab.rigs[0]
            let p0 = r.sim.bodyPose(iterations: 3).centroid
            r.brain.script = .walk(target: SIMD2(p0.x - 2.0, p0.z + 0.3), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0
            for _ in 0..<70 { lab.tick(watching: false); self.tick(dr, 0, r, c) }
        }, d + "/piptail2_walk.png")
    }

    func testCapturePipHatsRidge() throws {
        let d = try dir(); DayClock.shared.forcedHour = 12
        var rows: [UIImage] = []
        for (name, look) in [("cowboy", WearLook.cowboyHat), ("beret", .beret), ("bucket", .bucketHat), ("beanie", .beanieHoney)] {
            let a = try closeup(Char(id: 1, outfit: [.head: look]), yaw: Float.pi * 0.85, label: "Pip + \(name): back 3/4", dist: 2.6, lookY: 0.35, lookBack: 0.15)
            let b = try closeup(Char(id: 1, outfit: [.head: look]), yaw: Float.pi / 2, label: "Pip + \(name): side", dist: 2.6, lookY: 0.35, lookBack: 0.15)
            rows.append(hstack([a, b]))
        }
        try write(vstack([hstack([rows[0], rows[1]]), hstack([rows[2], rows[3]])]), d + "/pip_hats_ridge.png")
    }

    // MARK: roam corners (2026-10-21 room movement v2)

    /// A Jelbie at each extreme corner of the roaming polygon (front-left, front-right, back-left, back-right), the real renderer, the real room camera, with
    /// Lavender (wings), Pip (spines) and Moss (flower): the saved contact sheet + a pixel check that the whole body (shadow included) is on screen and the
    /// side margin / bottom margin hold. Output: corners_port.png / corners_land.png (ROAM_DIR or CHAR_CAP_DIR).
    private func cornersSheet(land: Bool) throws {
        let env = ProcessInfo.processInfo.environment
        guard let d = (env["ROAM_DIR"] ?? env["CHAR_CAP_DIR"]).flatMap({ $0.isEmpty ? nil : $0 }) else { throw XCTSkip("ROAM_DIR / CHAR_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        if land { W = 1311; H = 603 } else { W = 603; H = 1311 }
        let aspect = Float(W) / Float(H)
        DayClock.shared.forcedHour = 12
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        _ = GameCamera.camera(aspect: aspect)
        let rf = try XCTUnwrap(GameCamera.refreshRoam(aspect: aspect))
        let corners = rf.extremeCorners
        let names = ["front-left", "front-right", "back-left", "back-right"]
        let sets: [(String, [Int])] = [("Lavender FL, Pip FR, Pip BL, Lavender BR", [3, 1, 1, 3]), ("Pip FL, Lavender FR, Lavender BL, Pip BR", [1, 3, 3, 1]), ("Moss at all four", [2, 2, 2, 2])]
        var frames = [UIImage]()
        var minSide: Float = 1, minBottom: Float = 1
        var report = [String]()
        for (title, ids) in sets {
            let chars = ids.map { Char(id: $0) }
            let lab = setUpLab(corners, chars: chars, seed: 9)
            for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius; r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim); r.brain.idleState.goalYaw = r.faceYaw; r.brain.idleState.hold = 0.01 }
            for _ in 0..<90 { lab.tick(watching: false) }
            let (ren, target) = try renderer(lab)
            let dd = dress(lab, chars)
            let cam = GameCamera.camera(aspect: aspect, focus: 0)
            var boxes = [CGRect](repeating: .zero, count: 4)
            let img = composite(lab, dd, chars, ren, target, cam: cam) { boxes[$0] = $1 }
            for (k, b) in boxes.enumerated() {
                let side = Float(min(b.minX, CGFloat(W) - b.maxX)) / Float(W), bottom = Float(CGFloat(H) - b.maxY) / Float(H)
                minSide = min(minSide, side); minBottom = min(minBottom, bottom)
                let p = lab.rigs[k].brain.position
                let sofa = RoomLayout.sofaDistanceXZ(p), cyl = RoomLayout.cylinders.map { simd_distance(p, $0.centre) - $0.radius }.min() ?? 9
                report.append(String(format: "ROAMV2 %@ %@ %@: centre (%.2f, %.2f) want (%.2f, %.2f), side margin %.3f W, bottom margin %.3f H, bbox h %.3f H, sofa gap %.2f, cyl gap %.2f",
                                     land ? "land" : "port", title, names[k], p.x, p.y, corners[k].x, corners[k].y, side, bottom, Float(b.height) / Float(H), sofa, cyl))
                XCTAssertGreaterThan(side, 0.02, "\(title) \(names[k]): inside the side edges"); XCTAssertGreaterThan(bottom, 0.012, "\(title) \(names[k]): above the bottom edge")
                XCTAssertGreaterThan(sofa, 0.6, "\(title) \(names[k]): off the sofa"); XCTAssertGreaterThan(cyl, 0.6, "\(title) \(names[k]): off the plant and table")
            }
            frames.append(labelled(img.uiImage()!, title + (land ? "  (landscape)" : "  (portrait)")))
        }
        for r in report { MotionLog.write(r) }
        MotionLog.write(String(format: "ROAMV2 %@ corners %@: min side margin %.3f W, min bottom margin %.3f H, polygon z %.2f...%.2f", land ? "land" : "port", "\(corners)", minSide, minBottom, rf.minZ, rf.maxZ))
        try write(land ? vstack(frames) : hstack(frames), d + (land ? "/corners_land.png" : "/corners_port.png"))
    }
    func testCaptureRoamCornersPortrait() throws { try cornersSheet(land: false) }
    func testCaptureRoamCornersLandscape() throws { try cornersSheet(land: true) }
}
