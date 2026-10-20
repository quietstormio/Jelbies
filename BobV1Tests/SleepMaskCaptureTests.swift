//
//  SleepMaskCaptureTests.swift
//  Not a regression test: renders the sleep eye mask (pile, close-up, poof strip) with the REAL renderer (MelonRenderer, game room, W2 portrait camera,
//  true phone aspect) when MASK_CAP_DIR is set (pass it as TEST_RUNNER_MASK_CAP_DIR). Output: sleep_back.png, cuddle_pile.png, antics_sheet.png.
//  Like SocialCaptureTests the renderer draws ONE body per pass, so every rig is rendered on its own and pasted over an empty-room render.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class SleepMaskCaptureTests: XCTestCase {
    var W = 603, H = 1311
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0) }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DayClock.shared.forcedHour = 12 }

    private func renderer(_ device: MTLDevice, _ lab: SocialTests.Lab) throws -> (MelonRenderer, MTLTexture) {
        let r0 = lab.rigs[0]
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r0.sim.edges, particleCount: r0.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        return (ren, device.makeTexture(descriptor: td)!)
    }

    private func composite(_ lab: SocialTests.Lab, _ ren: MelonRenderer, _ target: MTLTexture, hour: Double?, tuck: Float = 0) -> LockImage {
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        ren.dayHourOverride = hour
        ren.tuckAmount = tuck
        func shot(only: Int?) -> LockImage {
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
        _ = shot(only: nil)
        let empty = shot(only: nil)
        var out = empty
        for k in (0..<lab.rigs.count).sorted(by: { lab.rigs[$0].sim.centroid().z < lab.rigs[$1].sim.centroid().z }) {
            let b = shot(only: k)
            for p in 0..<(W * H) {
                var d = 0
                for c in 0..<3 { d = max(d, abs(Int(b.bgra[4 * p + c]) - Int(empty.bgra[4 * p + c]))) }
                if d > 3 { for c in 0..<4 { out.bgra[4 * p + c] = b.bgra[4 * p + c] } }
            }
        }
        return out
    }

    private func labelled(_ img: LockImage, _ text: String, scale: CGFloat = 1) -> UIImage {
        let w = CGFloat(img.w) * scale, h = CGFloat(img.h) * scale, bar: CGFloat = 40
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + bar), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + bar))
            (text as NSString).draw(at: CGPoint(x: 10, y: 9), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white])
            img.uiImage()?.draw(in: CGRect(x: 0, y: bar, width: w, height: h))
        }
    }

    private func setUpLab(_ positions: [SIMD2<Float>], seed: UInt64 = 5) -> SocialTests.Lab {
        let lab = SocialTests.Lab(positions: positions, quiet: true, seed: seed)
        SocialTests.keep.append(lab)
        for r in lab.rigs { r.skinner.autoBlink = false; r.brain.anticsEnabled = true; r.brain.sleepEnabled = true }
        return lab
    }

    private func stepAll(_ lab: SocialTests.Lab, _ set: SleepMaskSet) {
        lab.tick(watching: false)
        for (i, r) in lab.rigs.enumerated() {
            r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            set.tick(id: i, brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
        }
        set.stepPuffs(dt: 1.0 / 60)
    }
    private func hand(_ ren: MelonRenderer, _ set: SleepMaskSet) {
        let f = set.frame(theme: ren.room!.theme)
        ren.room!.setMasks(opaque: f.opaque, translucent: f.translucent)
    }
    private func crop(_ img: LockImage, around c0: SIMD3<Float>, size: Int, label: String, lift: Float = 0) -> UIImage? {
        let c = c0 + SIMD3(0, lift, 0)
        let cam = GameCamera.camera(aspect: Float(603) / Float(1311), focus: 0)
        let clip = cam.viewProj * SIMD4<Float>(c.x, c.y, c.z, 1)
        let sx = (clip.x / clip.w * 0.5 + 0.5) * Float(img.w), sy = (1 - (clip.y / clip.w * 0.5 + 0.5)) * Float(img.h)
        let rect = CGRect(x: Int(sx) - size / 2, y: Int(sy) - size / 2, width: size, height: size)
        guard let cg = img.cgImage(), let part = cg.cropping(to: rect) else { return nil }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size + 40), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: size, height: size + 40))
            (label as NSString).draw(at: CGPoint(x: 8, y: 11), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white])
            UIImage(cgImage: part).draw(in: CGRect(x: 0, y: 40, width: size, height: size))
        }
    }

    func testCaptureEyeMask() throws {
        guard let dir = ProcessInfo.processInfo.environment["MASK_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("MASK_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }

        // ---- 23:00 goodnight pile, everybody masked
        do {
            DayClock.shared.forcedHour = 23
            SleepTuning.holdChance = 1
            defer { SleepTuning.holdChance = 0.4 }
            let lab = setUpLab([SIMD2(-0.9, 0.4), SIMD2(0.8, 0.9), SIMD2(1.8, -1.0)])
            let set = SleepMaskSet(); set.soundOn = false
            let (ren, target) = try renderer(device, lab)
            for r in lab.rigs { r.brain.idleNight = 1; r.brain.idleDeepNight = 1; r.brain.idleForced = true; r.brain.idleState.cooldown = 0; r.brain.restTimer = 0.3 }
            lab.rigs[0].brain.commandedGoodnight = true
            var f = 0
            while !lab.rigs.allSatisfy({ $0.brain.isNapping }) && f < 60 * 70 {
                stepAll(lab, set)
                if f == 60 { for r in lab.rigs.dropFirst() { r.brain.commandedGoodnight = true } }
                f += 1
            }
            for _ in 0..<200 { stepAll(lab, set) }
            var extra = 0
            while !(0..<3).allSatisfy({ set.liveZ($0) > 0 }) && extra < 600 { stepAll(lab, set); extra += 1 }
            for _ in 0..<40 { stepAll(lab, set) }
            XCTAssertTrue((0..<3).allSatisfy { set.isShown($0) }, "all three masked")
            XCTAssertTrue(lab.rigs.contains { $0.brain.sleep.holdW > 0.9 }, "at least one hand-hold in the pile")
            MotionLog.write("MASKCAP pile modes \(lab.rigs.map { "\($0.brain.sleep.mode) hold \($0.brain.sleep.holdW)" })")
            hand(ren, set)
            let tuck: Float = lab.rigs.allSatisfy({ $0.brain.isNapping && $0.brain.sleep.tucked }) ? 1 : 0
            ren.quiltSpot = MelonController.quiltSpot(for: lab.rigs.map { $0.brain.position })
            let img = composite(lab, ren, target, hour: 23, tuck: tuck)
            try labelled(img, "23:00 goodnight: all three asleep with sleep masks (navy Bob, lavender Pip, rose Moss), tuck \(tuck)").pngData()!.write(to: URL(fileURLWithPath: dir + "/eyemask_pile.png"))

            // ---- 2x close-up of one sleeper
            W = 603 * 2; H = 1311 * 2
            defer { W = 603; H = 1311 }
            let (ren2, target2) = try renderer(device, lab)
            hand(ren2, set)
            ren2.quiltSpot = ren.quiltSpot
            let big = composite(lab, ren2, target2, hour: 23, tuck: tuck)
            for k in 0..<3 {
                if let u = crop(big, around: lab.rigs[k].sim.centroid(), size: 560, label: "Sleeper \(k) close-up: mask + z's (2x render, game camera)", lift: 0.5) {
                    try u.pngData()!.write(to: URL(fileURLWithPath: dir + (k == 1 ? "/eyemask_closeup.png" : "/eyemask_closeup\(k).png")))
                }
            }
        }

        // ---- poof strip: in, asleep, away (one Jelly, afternoon)
        do {
            DayClock.shared.forcedHour = 15
            W = 603 * 2; H = 1311 * 2
            defer { W = 603; H = 1311 }
            let lab = setUpLab([SIMD2(0.2, 0.3), SIMD2(2.3, 1.8), SIMD2(-2.4, 1.6)], seed: 7)
            for r in lab.rigs.dropFirst() { r.brain.sleepEnabled = false }
            let set = SleepMaskSet(); set.soundOn = false
            let (ren, target) = try renderer(device, lab)
            let s = lab.rigs[0]
            s.brain.idleForced = true
            XCTAssertTrue(s.brain.idleStart(.sleep, s.sim)); s.brain.sleep.hold = 500
            var f = 0
            while set.popIns == 0 && f < 60 * 25 { stepAll(lab, set); f += 1 }
            var frames: [UIImage] = []
            func shoot(_ label: String) throws {
                hand(ren, set)
                let img = composite(lab, ren, target, hour: 15)
                if let u = crop(img, around: s.sim.centroid(), size: 420, label: label) { frames.append(u) }
            }
            for _ in 0..<4 { stepAll(lab, set) }
            try shoot("1. poof in (0.07 s)")
            for _ in 0..<8 { stepAll(lab, set) }
            try shoot("2. pop (0.2 s)")
            for _ in 0..<150 { stepAll(lab, set) }
            try shoot("3. asleep")
            s.brain.sleepWake(groggy: true)
            for _ in 0..<5 { stepAll(lab, set) }
            try shoot("4. wake starts: rolling back, mask stays on")
            for _ in 0..<31 { stepAll(lab, set) }
            try shoot("5. halfway through the roll: poof away")
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let sheet = UIGraphicsImageRenderer(size: CGSize(width: 420 * frames.count, height: 460), format: fmt).image { _ in
                for (i, u) in frames.enumerated() { u.draw(at: CGPoint(x: 420 * i, y: 0)) }
            }
            try sheet.pngData()!.write(to: URL(fileURLWithPath: dir + "/eyemask_poof.png"))
        }

        // ---- z strip: one Z rising, drifting, growing and fading
        do {
            DayClock.shared.forcedHour = 15
            W = 603 * 2; H = 1311 * 2
            defer { W = 603; H = 1311 }
            let lab = setUpLab([SIMD2(0.2, 0.3), SIMD2(2.3, 1.8), SIMD2(-2.4, 1.6)], seed: 9)
            for r in lab.rigs.dropFirst() { r.brain.sleepEnabled = false }
            let set = SleepMaskSet(); set.soundOn = false
            let (ren, target) = try renderer(device, lab)
            let s = lab.rigs[0]
            s.brain.idleForced = true
            XCTAssertTrue(s.brain.idleStart(.sleep, s.sim)); s.brain.sleep.hold = 500
            var f = 0
            while !(set.phase(0) == .shown) && f < 60 * 25 { stepAll(lab, set); f += 1 }
            var zf: [UIImage] = []
            let before = set.zSpawns
            var g = 0
            while set.zSpawns == before && g < 60 * 6 { stepAll(lab, set); g += 1 }
            XCTAssertGreaterThan(set.zSpawns, before)
            var elapsed: Float = 0
            for (n, t) in [Float(0.4), 1.1, 1.9, 2.6, 3.2].enumerated() {
                let steps = Int((t - elapsed) * 60); for _ in 0..<steps { stepAll(lab, set) }; elapsed = t
                hand(ren, set)
                let img = composite(lab, ren, target, hour: 15)
                if let u = crop(img, around: s.sim.centroid(), size: 420, label: "\(n + 1). z at \(t) s", lift: 0.6) { zf.append(u) }
            }
            let fmt2 = UIGraphicsImageRendererFormat(); fmt2.scale = 1
            let sheet2 = UIGraphicsImageRenderer(size: CGSize(width: 420 * zf.count, height: 460), format: fmt2).image { _ in
                for (i, u) in zf.enumerated() { u.draw(at: CGPoint(x: 420 * i, y: 0)) }
            }
            try sheet2.pngData()!.write(to: URL(fileURLWithPath: dir + "/zzz_strip.png"))
        }
    
        // ---- snuggle strip: one asleep, another walks over, lies down beside, the mask poofs on, they hold hands
        do {
            DayClock.shared.forcedHour = 15
            SleepTuning.holdChance = 1
            defer { SleepTuning.holdChance = 0.4 }
            W = 603 * 2; H = 1311 * 2
            defer { W = 603; H = 1311 }
            let lab = setUpLab([SIMD2(-0.3, 0.3), SIMD2(2.2, 1.0), SIMD2(-2.4, 1.6)], seed: 13)
            for r in lab.rigs.dropFirst(2) { r.brain.sleepEnabled = false }
            let set = SleepMaskSet(); set.soundOn = false
            let (ren, target) = try renderer(device, lab)
            let a = lab.rigs[0], b = lab.rigs[1]
            a.brain.idleForced = true
            XCTAssertTrue(a.brain.idleStart(.sleep, a.sim)); a.brain.sleep.hold = 900
            var f = 0
            while !(set.phase(0) == .shown) && f < 60 * 25 { stepAll(lab, set); f += 1 }
            for _ in 0..<60 { stepAll(lab, set) }
            var frames: [UIImage] = []
            func shoot(_ label: String) {
                hand(ren, set)
                let img = composite(lab, ren, target, hour: 15)
                let m = (a.sim.centroid() + b.sim.centroid()) * 0.5
                if let u = crop(img, around: m, size: 560, label: label, lift: 0.35) { frames.append(u) }
            }
            shoot("1. one Jelly asleep (mask on)")
            b.brain.idleForced = true
            XCTAssertTrue(b.brain.idleStart(.sleep, b.sim))
            XCTAssertEqual(b.brain.sleep.mode, .hold)
            for _ in 0..<60 { stepAll(lab, set) }
            shoot("2. another walks over")
            f = 0; while b.brain.sleep.stage < 2 && f < 60 * 30 { stepAll(lab, set); f += 1 }
            for _ in 0..<35 { stepAll(lab, set) }
            shoot("3. lies down beside him")
            f = 0; while set.phase(1) != .popIn && f < 60 * 10 { stepAll(lab, set); f += 1 }
            for _ in 0..<5 { stepAll(lab, set) }
            shoot("4. mask poofs on")
            f = 0; while !(b.brain.sleep.holdW > 0.99 && a.brain.sleep.holdW > 0.99) && f < 60 * 10 { stepAll(lab, set); f += 1 }
            for _ in 0..<20 { stepAll(lab, set) }
            shoot("5. sleepy hand-hold")
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let sheet = UIGraphicsImageRenderer(size: CGSize(width: 560 * frames.count, height: 600), format: fmt).image { _ in
                for (i, u) in frames.enumerated() { u.draw(at: CGPoint(x: 560 * i, y: 0)) }
            }
            try sheet.pngData()!.write(to: URL(fileURLWithPath: dir + "/snuggle_join.png"))
        }
    }
}
