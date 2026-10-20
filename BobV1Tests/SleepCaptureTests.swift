//
//  SleepCaptureTests.swift
//  Not a regression test: renders the sleep-on-back scenes and the new antics with the REAL renderer (MelonRenderer, game room, W2 portrait camera,
//  true phone aspect) when BEDS_CAP_DIR is set (pass it as TEST_RUNNER_BEDS_CAP_DIR). Output: sleep_back.png, cuddle_pile.png, antics_sheet.png.
//  Like SocialCaptureTests the renderer draws ONE body per pass, so every rig is rendered on its own and pasted over an empty-room render.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class SleepCaptureTests: XCTestCase {
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

    func testCaptureSleepScenes() throws {
        guard let dir = ProcessInfo.processInfo.environment["BEDS_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("BEDS_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }

        // ---- one Jelly asleep on his back, the others awake (evening light)
        do {
            let lab = setUpLab([SIMD2(-0.2, 0.3), SIMD2(1.9, 1.6), SIMD2(-2.1, 1.2)])
            let (ren, target) = try renderer(device, lab)
            let s = lab.rigs[0]
            s.brain.idleForced = true
            XCTAssertTrue(s.brain.idleStart(.sleep, s.sim)); s.brain.sleep.hold = 500
            var f = 0
            while !s.brain.isNapping && f < 60 * 20 { lab.tick(watching: false); for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }; f += 1 }
            for _ in 0..<150 { lab.tick(watching: false); for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) } }
            let img = composite(lab, ren, target, hour: 15)
            try labelled(img, "Bob asleep on his back (face to the ceiling, eyes shut); Pip and Moss awake").pngData()!.write(to: URL(fileURLWithPath: dir + "/sleep_back.png"))
        }

        // ---- 23:00, everybody asleep in a cuddle pile, tucked in
        do {
            DayClock.shared.forcedHour = 23
            let lab = setUpLab([SIMD2(-0.9, 0.4), SIMD2(0.8, 0.9), SIMD2(1.8, -1.0)])
            let (ren, target) = try renderer(device, lab)
            for r in lab.rigs { r.brain.idleNight = 1; r.brain.idleDeepNight = 1; r.brain.idleForced = true; r.brain.idleState.cooldown = 0; r.brain.restTimer = 0.3 }
            lab.rigs[0].brain.commandedGoodnight = true
            var f = 0
            while !lab.rigs.allSatisfy({ $0.brain.isNapping }) && f < 60 * 70 {
                lab.tick(watching: false); for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
                if f == 60 { for r in lab.rigs.dropFirst() { r.brain.commandedGoodnight = true } }
                f += 1
            }
            for _ in 0..<200 { lab.tick(watching: false); for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) } }
            MotionLog.write("SLEEPCAP pile after \(Float(f) / 60) s: \(lab.rigs.map { "\($0.brain.sleep.stage) \($0.brain.position)" })")
            let tuck: Float = lab.rigs.allSatisfy({ $0.brain.isNapping && $0.brain.sleep.tucked }) ? 1 : 0
            ren.quiltSpot = MelonController.quiltSpot(for: lab.rigs.map { $0.brain.position })
            let img = composite(lab, ren, target, hour: 23, tuck: tuck)
            try labelled(img, "23:00 goodnight: real cuddle pile, tucked in (no quilt)").pngData()!.write(to: URL(fileURLWithPath: dir + "/cuddle_pile2.png"))
            // ---- close-up of one sleeper from the same pile: 2x render, cropped around him, game camera (true proportion)
            W = 603 * 2; H = 1311 * 2
            defer { W = 603; H = 1311 }
            let (ren2, target2) = try renderer(device, lab)
            let big = composite(lab, ren2, target2, hour: 23, tuck: tuck)
            let cam = GameCamera.camera(aspect: Float(603) / Float(1311), focus: 0)
            let c = lab.rigs[1].sim.centroid()
            let clip = cam.viewProj * SIMD4<Float>(c.x, c.y, c.z, 1)
            let sx = (clip.x / clip.w * 0.5 + 0.5) * Float(W), sy = (1 - (clip.y / clip.w * 0.5 + 0.5)) * Float(H)
            let cw = 560, ch = 560
            let rect = CGRect(x: Int(sx) - cw / 2, y: Int(sy) - ch / 2, width: cw, height: ch)
            if let cg = big.cgImage(), let part = cg.cropping(to: rect) {
                let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
                let out = UIGraphicsImageRenderer(size: CGSize(width: cw, height: ch + 40), format: fmt).image { _ in
                    UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: cw, height: ch + 40))
                    ("Sleeper close-up (2x render, game cam): feet toward camera" as NSString).draw(at: CGPoint(x: 10, y: 11), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.white])
                    UIImage(cgImage: part).draw(in: CGRect(x: 0, y: 40, width: cw, height: ch))
                }
                try out.pngData()!.write(to: URL(fileURLWithPath: dir + "/sleep_closeup.png"))
            }
        }
    }

    func testCaptureAnticsSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["BEDS_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("BEDS_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        enum Act { case solo(IdleKind), social(SocialKind) }
        let scenes: [(String, Act, Float, [SIMD2<Float>])] = [
            ("spin after his own tail", .solo(.tail), 4.0, [SIMD2(0.2, 0.2), SIMD2(-2.4, 2.3), SIMD2(2.4, 2.2)]),
            ("flop over and wobble back up", .solo(.flop), 2.9, [SIMD2(0.2, 0.2), SIMD2(-2.4, 2.3), SIMD2(2.4, 2.2)]),
            ("happy bounce", .solo(.bounce), 2.9, [SIMD2(0.2, 0.2), SIMD2(-2.4, 2.3), SIMD2(2.4, 2.2)]),
            ("look out of the window", .solo(.window), 7.5, [SIMD2(0.2, -0.6), SIMD2(-2.4, 2.3), SIMD2(2.4, 2.2)]),
            ("nuzzle side by side", .social(.nuzzle), 6.8, [SIMD2(-1.2, 0.3), SIMD2(1.0, 0.9), SIMD2(2.4, 2.2)]),
            ("belly bump", .social(.bump), 4.6, [SIMD2(-1.6, 0.3), SIMD2(1.2, 0.5), SIMD2(2.4, 2.2)]),
            ("sneak up and boop (startle hop)", .social(.sneak), 6.4, [SIMD2(-1.8, 0.8), SIMD2(0.9, -0.3), SIMD2(2.4, 2.2)]),
            ("tag: chase, swap", .social(.chase), 12.0, [SIMD2(-1.6, 0.3), SIMD2(1.2, 0.5), SIMD2(2.4, 2.2)]),
        ]
        var rows: [(String, [LockImage])] = []
        for (label, act, seconds, pos) in scenes {
            let lab = setUpLab(pos, seed: 31)
            let (ren, target) = try renderer(device, lab)
            let a = lab.rigs[0], b = lab.rigs[1]
            switch act {
            case .solo(let k):
                a.brain.idleForced = true
                XCTAssertTrue(a.brain.idleStart(k, a.sim), "\(label) starts")
            case .social(let k):
                XCTAssertTrue(a.brain.socialStart(k, with: b.brain, a.sim), "\(label) starts")
            }
            var cells: [LockImage] = []
            let frames = 5, every = max(1, Int(seconds * 60) / frames)
            var f = 0
            while cells.count < frames && f < Int(seconds * 60) + 300 {
                lab.tick(watching: false)
                for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
                if f % every == every / 2 { cells.append(composite(lab, ren, target, hour: 12)) }
                f += 1
            }
            rows.append((label, cells))
        }
        // sheet: each cell is cropped to the middle of the floor at one fixed scale (true proportion)
        let cw = 360, ch = 330, labelH = 30, pad = 6
        let cols = 5
        let sw = cols * (cw + pad) + pad, sh = rows.count * (ch + labelH + pad) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
            for (r, row) in rows.enumerated() {
                let y0 = pad + r * (ch + labelH + pad)
                (row.0 as NSString).draw(at: CGPoint(x: CGFloat(pad + 4), y: CGFloat(y0 + 5)), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.white])
                for (c, cell) in row.1.enumerated() {
                    guard let cg = cell.cgImage() else { continue }
                    // crop: x 40...563, y 360...800 of the 603 x 1311 frame (the floor where the scenes are staged)
                    let crop = CGRect(x: 40, y: 380, width: 523, height: 480)
                    if let part = cg.cropping(to: crop) { UIImage(cgImage: part).draw(in: CGRect(x: pad + c * (cw + pad), y: y0 + labelH, width: cw, height: ch)) }
                    ("t\(c + 1)/\(cols)" as NSString).draw(at: CGPoint(x: CGFloat(pad + c * (cw + pad) + 4), y: CGFloat(y0 + labelH + 2)), withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.lightGray])
                }
            }
        }
        try img.pngData()!.write(to: URL(fileURLWithPath: dir + "/antics_sheet.png"))
    }
}
