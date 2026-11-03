//
//  FeatureClipCaptureTests.swift
//  Not a regression test: before / after strips of the feature clip + the lying-pair placement with the REAL renderer when FEATCLIP_DIR is set
//  (TEST_RUNNER_FEATCLIP_DIR): Teddy + Pearl lying side by side (the user's photo, a high 3/4 camera), Pearl + Lavender in a sway hug, Pip's tail in the group hug.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class FeatureClipCaptureTests: XCTestCase {
    let W = 520, H = 440

    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 1)
    }
    override func tearDown() {
        FeatureClip.enabled = true; LieClearTuning.enabled = true
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    private func dir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["FEATCLIP_DIR"], !d.isEmpty else { throw XCTSkip("FEATCLIP_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    @MainActor final class Shooter {
        let ren: MelonRenderer, target: MTLTexture, W: Int, H: Int
        init(device: MTLDevice, d: FeatureClipTests.Duo, W: Int, H: Int) throws {
            guard let r = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: d.lab.rigs[0].sim.edges, particleCount: d.lab.rigs[0].sim.n, game: true, bodyCount: d.lab.rigs.count), r.room != nil else { throw XCTSkip("no renderer") }
            ren = r; self.W = W; self.H = H
            ren.resize(width: W, height: H)
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            target = device.makeTexture(descriptor: td)!
            ren.roomCacheEnabled = false
        }
        /// One frame: every body skinned (+ the stage's clip pass), the features carried by the clipped streams, drawn.
        func shot(_ d: FeatureClipTests.Duo, palettes: [Palette], focus: SIMD3<Float>, dirv: SIMD3<Float>, dist: Float, lift: Float) -> UIImage {
            let n = d.lab.rigs.count
            ren.beginFrame()
            var jobs: [JellyParallel.SkinJob] = []
            for (i, r) in d.lab.rigs.enumerated() {
                let dst = ren.dynPointer(body: i)
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: dst)
                jobs.append(JellyParallel.SkinJob(skinner: r.skinner, sim: r.sim, dst: dst, id: i))
                ren.setPalette(palettes[i], body: i)
            }
            FeatureClip.apply(jobs: jobs)
            if FeatureClip.eggs.count != n { FeatureClip.eggs = jobs.map { ClipEgg(sim: $0.sim) } }
            var all = RoomMesh()
            for i in 0..<n {
                d.feats[i].syncCarry(i, sim: d.lab.rigs[i].sim)
                let m = d.feats[i].frame { [ren] id in UnsafePointer(ren.dynPointer(body: id)) }
                let base = UInt32(all.vertices.count)
                all.vertices += m.vertices; all.indices += m.indices.map { $0 + base }
            }
            ren.room!.setWear(opaque: all, translucent: RoomMesh(), bounds: [])
            ren.room!.setShoes(RoomMesh())
            ren.room!.setMasks(opaque: RoomMesh(), translucent: RoomMesh())
            var cam = CameraState()
            let eye = focus + dirv * dist + SIMD3(0, dist * lift, 0)
            cam.view = M4.lookAt(eye: eye, at: focus, up: SIMD3(0, 1, 0))
            cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: Float(W) / Float(H), near: 0.2, far: 60), cam.view)
            cam.invViewProj = M4.invert(cam.viewProj)
            cam.pos = eye; cam.fwd = simd_normalize(focus - eye)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            fp.bg = melonBackgroundLinear
            ren.setUniforms(camera: cam, light: GameCamera.light(centroids: d.lab.rigs.map { $0.sim.centroid() }), palette: palettes[0], params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            for p in 0..<(W * H) where px[4 * p] == 0 && px[4 * p + 1] == 0 && px[4 * p + 2] == 0 { px[4 * p] = 72; px[4 * p + 1] = 98; px[4 * p + 2] = 130 }
            return LockImage(w: W, h: H, bgra: px).uiImage()!
        }
    }

    private func strip(_ rows: [(String, [UIImage])], to path: String) throws {
        let cw = rows.first?.1.first.map { Int($0.size.width) } ?? 0, ch = rows.first?.1.first.map { Int($0.size.height) } ?? 0
        let cols = rows.map { $0.1.count }.max() ?? 1, pad = 4, label = 26
        let sw = cols * (cw + pad) + pad, sh = rows.count * (ch + label + pad) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
            for (r, row) in rows.enumerated() {
                let y0 = pad + r * (ch + label + pad)
                (row.0 as NSString).draw(at: CGPoint(x: CGFloat(pad + 4), y: CGFloat(y0 + 4)), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white])
                for (c, im) in row.1.enumerated() { im.draw(in: CGRect(x: pad + c * (cw + pad), y: y0 + label, width: cw, height: ch)) }
            }
        }
        try img.pngData()!.write(to: URL(fileURLWithPath: path))
    }

    /// Teddy (left) and Pearl (right) lie down 1.2 apart, tipped into each other (the photo): before / after.
    func testLyingTeddyAndPearl() throws {
        let out = try dir()
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let pal = [JellyRoster.palette(JellyRoster.teddyID)!, WhiteWing.palette]
        var rows: [(String, [UIImage])] = []
        for after in [false, true] {
            FeatureClip.enabled = after; LieClearTuning.enabled = after
            let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.ears, .wings])
            FeatureClipTests.keep.append(d)
            let sh = try Shooter(device: device, d: d, W: W, H: H)
            d.place([SIMD2(-0.6, 0.6), SIMD2(0.6, 0.6)])
            let a = d.lab.rigs[0], b = d.lab.rigs[1]
            a.brain.idleForced = true; b.brain.idleForced = true
            _ = a.brain.idleStart(.lieDown, a.sim); _ = b.brain.idleStart(.lieDown, b.sim)
            if !after { a.brain.idleState.sign = -1; b.brain.idleState.sign = 1 }
            var cells: [UIImage] = []
            for f in 0..<(60 * 5) {
                d.tick()
                guard f >= 150, f % 45 == 0, cells.count < 4 else { continue }
                let c = SIMD3((a.sim.centroid().x + b.sim.centroid().x) / 2, 0.45, (a.sim.centroid().z + b.sim.centroid().z) / 2)
                cells.append(sh.shot(d, palettes: pal, focus: c, dirv: simd_normalize(SIMD3(0.35, 0, 1)), dist: 3.4, lift: 0.75))
            }
            rows.append((after ? "AFTER: lie-down makes room, features clipped" : "BEFORE: the photo (placement + clip off)", cells))
        }
        try strip(rows, to: out + "/01_lying_teddy_pearl.png")
    }

    /// Pearl (left) and Lavender (right) in a sway hug: wings against the other's body.
    func testPearlAndLavenderHug() throws {
        let out = try dir()
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let pal = [WhiteWing.palette, JellyRoster.palette(3)!]
        var rows: [(String, [UIImage])] = []
        for after in [false, true] {
            FeatureClip.enabled = after; LieClearTuning.enabled = after
            let d = FeatureClipTests.Duo(positions: [SIMD2(-0.9, 0.6), SIMD2(0.9, 0.6)], features: [.wings, .wings], seed: 7)
            FeatureClipTests.keep.append(d)
            for (i, r) in d.lab.rigs.enumerated() { if i == 0 { d.feats[0].setWingTint(0, WhiteWing.wingTint) } else { d.feats[1].setWingTint(1, nil) }; _ = r }
            let sh = try Shooter(device: device, d: d, W: W, H: H)
            XCTAssertTrue(d.lab.rigs[0].brain.socialStart(.swayHug, with: d.lab.rigs[1].brain, d.lab.rigs[0].sim))
            var cells: [UIImage] = []
            var worstFrame = 0, worst: Float = -1
            var frames: [Int: Float] = [:]
            for f in 0..<(60 * 14) {
                d.tick()
                if f % 10 == 0, d.lab.rigs[0].brain.isSocial {
                    let raw = d.skinAll()
                    let p = max(d.penetration(raw[0], owner: 0), d.penetration(raw[1], owner: 1)); frames[f] = p
                    if p > worst { worst = p; worstFrame = f }
                }
            }
            _ = frames
            // replay to the worst frame region (the same seed) and shoot around it
            FeatureClip.enabled = after; LieClearTuning.enabled = after
            let d2 = FeatureClipTests.Duo(positions: [SIMD2(-0.9, 0.6), SIMD2(0.9, 0.6)], features: [.wings, .wings], seed: 7)
            FeatureClipTests.keep.append(d2)
            d2.feats[0].setWingTint(0, WhiteWing.wingTint)
            let sh2 = try Shooter(device: device, d: d2, W: W, H: H)
            _ = d2.lab.rigs[0].brain.socialStart(.swayHug, with: d2.lab.rigs[1].brain, d2.lab.rigs[0].sim)
            for f in 0..<(worstFrame + 40) {
                d2.tick()
                guard f >= worstFrame - 100, (f - worstFrame + 100) % 35 == 0, cells.count < 4 else { continue }
                let c = SIMD3((d2.lab.rigs[0].sim.centroid().x + d2.lab.rigs[1].sim.centroid().x) / 2, 0.6, (d2.lab.rigs[0].sim.centroid().z + d2.lab.rigs[1].sim.centroid().z) / 2)
                cells.append(sh2.shot(d2, palettes: pal, focus: c, dirv: simd_normalize(SIMD3(0.1, 0, -1)), dist: 3.3, lift: 0.35))
            }
            _ = sh
            rows.append((after ? "AFTER (back view: wings toward the camera)" : "BEFORE (back view)", cells))
            MotionLog.write("FEATCLIP capture hug clip \(after): worst raw feature pen \(worst) at frame \(worstFrame)")
        }
        try strip(rows, to: out + "/02_pearl_lavender_hug.png")
    }

    /// Pip (yellow, tail + spikes) in a group hug with Bob and Teddy.
    func testPipTailInGroupHug() throws {
        let out = try dir()
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let pal = [JellyRoster.palette(1)!, PaletteKey.blue.palette, JellyRoster.palette(JellyRoster.teddyID)!]
        var rows: [(String, [UIImage])] = []
        for after in [false, true] {
            FeatureClip.enabled = after; LieClearTuning.enabled = after
            let d = FeatureClipTests.Duo(positions: SocialTests.starts, features: [.spines, .none, .ears], seed: 3)
            FeatureClipTests.keep.append(d)
            let sh = try Shooter(device: device, d: d, W: W, H: H)
            for r in d.lab.rigs { r.brain.anticsEnabled = true }
            _ = d.lab.rigs[0].brain.socialStart(.groupHug, with: d.lab.rigs[1].brain, d.lab.rigs[0].sim)
            var cells: [UIImage] = []
            var huddle = -1
            for f in 0..<(60 * 40) {
                d.tick()
                if huddle < 0, let s = d.lab.rigs[0].brain.social, s.phase >= 2 { huddle = f }
                guard huddle >= 0, f >= huddle + 20, (f - huddle - 20) % 40 == 0, cells.count < 4 else { continue }
                let cs = d.lab.rigs.map { $0.sim.centroid() }
                let c = (cs[0] + cs[1] + cs[2]) / 3
                cells.append(sh.shot(d, palettes: pal, focus: SIMD3(c.x, 0.55, c.z), dirv: simd_normalize(SIMD3(0.5, 0, 1)), dist: 4.0, lift: 0.5))
            }
            rows.append((after ? "AFTER" : "BEFORE", cells))
        }
        try strip(rows, to: out + "/03_pip_tail_group_hug.png")
    }
}
