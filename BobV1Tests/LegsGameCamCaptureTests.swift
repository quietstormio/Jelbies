//
//  LegsGameCamCaptureTests.swift
//  Not a regression test: when AUDIT_CAP_DIR is set (TEST_RUNNER_AUDIT_CAP_DIR, optional TEST_RUNNER_AUDIT_TAG = before / after) it renders one full cartwheel per
//  character (Pip, Moss, Lavender, Bob), bare and in shoes, in the room with THREE Jelbies at the real game camera (portrait phone framing) and in a medium
//  side-on shot, at a 120 fps frame cadence, every frame: contact sheets (every 2nd frame) and one MP4 per case (played at half speed).
//

import XCTest
import Metal
import simd
import UIKit
import AVFoundation
@testable import BobV1

nonisolated final class MP4Out {
    let writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor
    let w: Int, h: Int, fps: Int32
    var n: Int64 = 0
    init?(url: URL, w: Int, h: Int, fps: Int32) {
        try? FileManager.default.removeItem(at: url)
        guard let wr = try? AVAssetWriter(url: url, fileType: .mp4) else { return nil }
        let inp = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        guard wr.canAdd(inp) else { return nil }
        wr.add(inp); writer = wr; input = inp; adaptor = ad; self.w = w; self.h = h; self.fps = fps
        wr.startWriting(); wr.startSession(atSourceTime: .zero)
    }
    func add(_ bgra: [UInt8]) {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let pb else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            bgra.withUnsafeBytes { src in for y in 0..<h { memcpy(base + y * bpr, src.baseAddress! + y * w * 4, w * 4) } }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        var spins = 0
        while !input.isReadyForMoreMediaData && writer.status == .writing && spins < 5000 { Thread.sleep(forTimeInterval: 0.002); spins += 1 }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { if n == 0 { MotionLog.write("MP4 writer failed: \(String(describing: writer.error))") }; n += 1; return }
        adaptor.append(pb, withPresentationTime: CMTime(value: n, timescale: fps)); n += 1
    }
    func finish() {
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
    }
}

@MainActor
final class LegsGameCamCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    static func crop(_ img: LockImage, cx: Int, cy: Int, size C: Int) -> LockImage {
        let x0 = max(0, min(img.w - C, cx - C / 2)), y0 = max(0, min(img.h - C, cy - C / 2))
        var o = [UInt8](repeating: 0, count: C * C * 4)
        for y in 0..<C { for x in 0..<(C * 4) { o[y * C * 4 + x] = img.bgra[(y0 + y) * img.w * 4 + x0 * 4 + x] } }
        return LockImage(w: C, h: C, bgra: o)
    }

    static func sheet(_ cells: [(LockImage, String)], cols: Int, tile: Int, title: String, to path: String) {
        let lab = 16, head = 28
        let rows = (cells.count + cols - 1) / cols
        let W = cols * tile, H = head + rows * (tile + lab)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: W, height: H))
            (title as NSString).draw(at: CGPoint(x: 6, y: 5), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: UIColor.white])
            for (i, c) in cells.enumerated() {
                let x = (i % cols) * tile, y = head + (i / cols) * (tile + lab)
                (c.1 as NSString).draw(at: CGPoint(x: x + 3, y: y + 1), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor(white: 0.9, alpha: 1)])
                c.0.uiImage()?.draw(in: CGRect(x: x, y: y + lab, width: tile, height: tile))
            }
        }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? img.pngData()?.write(to: URL(fileURLWithPath: path))
    }

    func testGameCameraCartwheels() throws {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["AUDIT_CAP_DIR"], !base.isEmpty else { throw XCTSkip("AUDIT_CAP_DIR not set") }
        let tag = env["AUDIT_TAG"] ?? "before"
        let dir = base + "/game_cam/" + tag
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let W = 604, H = 1312
        _ = GameCamera.camera(aspect: Float(W) / Float(H))
        let only = env["AUDIT_CHARS"]?.split(separator: ",").compactMap { Int($0) }
        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        let names = ["Bob", "Pip", "Moss", "Lavender"]
        for c in (only ?? [1, 2, 3, 0]) {
            for shoes in [false, true] {
                let ids = c == 0 ? [0, 2, 3] : [1, 2, 3]
                let slot = ids.firstIndex(of: c)!
                let spots = JellyRoster.spawnSpots(count: 3)
                var rigs: [MotionRig] = []
                for (k, id) in ids.enumerated() {
                    let r = MotionRig(game: true, settle: 0.5); Self.keep.append(r)
                    r.renderSamples = false; r.skinner.autoBlink = false
                    r.skinner.guardEnabled = tag != "before"          // (before = the drawn-space bean guard off, shoes from the undrawn bean)
                    r.brain.feature = JellyRoster.feature(id)
                    r.skinner.configureTail(rm); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
                    r.sim.teleport(toXZ: spots[k]); for _ in 0..<90 { r.sim.step() }
                    r.brain.currentPose(r.sim)
                    rigs.append(r)
                }
                let me = rigs[slot]
                me.brain.shoesWorn = shoes
                me.brain.seed = 11
                me.brain.peers = { [unowned rigs0 = rigs[(slot + 1) % 3], rigs1 = rigs[(slot + 2) % 3]] in [(id: 1, pos: rigs0.root), (id: 2, pos: rigs1.root)] }
                me.brain.steerID = 0; me.brain.peerGap = 0.9
                me.brain.idleForced = true
                guard me.brain.idleStart(.cartwheel, me.sim) else { XCTFail("cartwheel did not start for \(names[c])"); continue }

                guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: me.sim.edges, particleCount: me.sim.n, game: true, bodyCount: 3), ren.room != nil else { throw XCTSkip("no renderer") }
                ren.roomCacheEnabled = false
                ren.resize(width: W, height: H)
                for (k, id) in ids.enumerated() { ren.setPalette(JellyRoster.palette(id) ?? PaletteKey.blue.palette, body: k) }
                func target(_ w: Int, _ h: Int) -> MTLTexture {
                    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
                    td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
                    return device.makeTexture(descriptor: td)!
                }
                let texG = target(W, H)
                let tag2 = "\(names[c])\(shoes ? "_shoes" : "")"
                let mp4G = MP4Out(url: URL(fileURLWithPath: dir + "/\(tag2)_gamecam.mp4"), w: W, h: H, fps: 60)
                let mp4M = MP4Out(url: URL(fileURLWithPath: dir + "/\(tag2)_medium.mp4"), w: W, h: H, fps: 60)
                var cellsG: [(LockImage, String)] = [], cellsM: [(LockImage, String)] = []

                func render(_ w: Int, _ h: Int, _ tex: MTLTexture, cam: CameraState) -> LockImage {
                    ren.beginFrame()
                    for (k, r) in rigs.enumerated() { r.skinner.update(x: r.sim.x, index: rm.index, into: ren.dynPointer(body: k)) }
                    // shoes of the cartwheeler, built from the bean as drawn
                    if shoes {
                        let beans = GameCare.footBeans(brain: me.brain, sim: me.sim, skinner: me.skinner, drawn: tag == "before" ? nil : ren.skinPointer(body: slot))
                        let b = RoomMeshBuilder(); b.material = .plain
                        if let beans { for s in 0..<2 { ShoeModel.buildShell(WearLook.shoes[0], bean: beans[s], floorY: me.sim.floorY, body: SIMD3(0.35, 0.5, 0.9), time: 0, gpuPaint: true, side: s, into: b) } }
                        ren.room!.setShoes(b.mesh)
                    }
                    var fp = FrameParams()
                    fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                    fp.exposure = 1; fp.meshAlpha = 0; fp.time = 3.7
                    let pal = PaletteKey.blue.palette
                    fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                    ren.setUniforms(camera: cam, light: GameCamera.light(centroids: rigs.map { $0.sim.centroid() }), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(w), Float(h)))
                    let cmd = ren.queue.makeCommandBuffer()!
                    ren.draw(to: tex, commandBuffer: cmd, showMesh: false)
                    cmd.waitUntilCompleted()
                    var px = [UInt8](repeating: 0, count: w * h * 4)
                    px.withUnsafeMutableBytes { tex.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
                    return LockImage(w: w, h: h, bgra: px)
                }
                func medium(_ cen: SIMD3<Float>) -> CameraState {
                    let at = SIMD3<Float>(cen.x, max(0.55, cen.y), cen.z), eye = at + SIMD3(5.9, 0.5, 0.3)
                    var cam = CameraState()
                    cam.view = M4.lookAt(eye: eye, at: at, up: SIMD3(0, 1, 0))
                    cam.viewProj = M4.mul(M4.perspective(fovy: 32 * .pi / 180, aspect: Float(W) / Float(H), near: 0.1, far: 60), cam.view)
                    cam.invViewProj = M4.invert(cam.viewProj); cam.pos = eye; cam.fwd = simd_normalize(at - eye)
                    return cam
                }
                let camG = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
                let stepDt = me.sim.stepDt
                // pop detector: the cartwheeler's bean vertices (every 31st) in the fitted body frame, frame to frame
                var prevQ: [SIMD3<Float>] = [], maxJump: Float = 0, maxJumpFrame = 0, jumpBlend: Float = 0
                var acc: Float = 0, t: Float = 0, frame = 0, seen = false, after: Float = 0
                let dt: Float = 1.0 / 120
                while t < 14 {
                    acc += dt
                    var steps = 0
                    while acc >= stepDt && steps < 2 {
                        for r in rigs { r.brain.tick(sim: r.sim, skinner: r.skinner, dt: stepDt, touched: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: stepDt) }
                        for r in rigs { r.sim.step() }
                        t += stepDt; acc -= stepDt; steps += 1
                    }
                    if steps > 0 { for r in rigs { r.brain.refitBeans(r.sim, r.skinner) } }
                    for r in rigs { r.skinner.tickBlink(dt: dt) }
                    if me.brain.idleState.kind == .cartwheel { seen = true } else if seen { after += dt }
                    if after > 0.5 { break }
                    if !seen && t > 3 { break }
                    frame += 1
                    if frame % 40 == 0 { MotionLog.write("GAMECAM progress \(names[c]) shoes=\(shoes) frame \(frame) t=\(t) seen=\(seen)") }
                    guard seen || t > 0 else { continue }
                    let cen = me.sim.centroid()
                    if frame <= 3 { MotionLog.write("GAMECAM render game frame \(frame)") }
                    let g = render(W, H, texG, cam: camG)
                    if me.skinner.beansActive, me.skinner.beanBlend > 0.05, !me.bean[0].isEmpty {
                        let pose = me.sim.bodyPose(iterations: 4)
                        var q: [SIMD3<Float>] = []
                        for sd in 0..<2 { var i = 0; while i < FootBean.vertexCount { let o = 6 * Int(me.bean[sd][i]); let p = ren.skinPointer(body: slot); q.append(pose.rotation.inverse.act(SIMD3(p[o], p[o + 1], p[o + 2]) - pose.centroid)); i += 31 } }
                        if prevQ.count == q.count { var fj: Float = 0; for k in q.indices { fj = max(fj, simd_distance(q[k], prevQ[k])) }; if fj > 0.05 && names[c] == "Bob" { MotionLog.write(String(format: "GAMECAM jump %@ f%d %.3f blend %.2f beanG %.2f phase %@ morph %.2f/%.2f", tag2, frame, fj, me.skinner.beanBlend, me.brain.beanG, "\(me.brain.gait.phase)", me.brain.beanMorphLast[0], me.brain.beanMorphLast[1])) }; for k in q.indices { let j = simd_distance(q[k], prevQ[k]); if j > maxJump { maxJump = j; maxJumpFrame = frame; jumpBlend = me.skinner.beanBlend } } }
                        prevQ = q
                    } else { prevQ = [] }
                    if frame <= 3 { MotionLog.write("GAMECAM rendered game frame \(frame)") }
                    let m = render(W, H, texG, cam: medium(cen))
                    mp4G?.add(g.bgra); mp4M?.add(m.bgra)
                    if [30, 40, 50, 60, 70, 86, 90].contains(frame) {
                        let still = Self.crop(m, cx: W / 2, cy: H / 2, size: 604)
                        try? FileManager.default.createDirectory(atPath: dir + "/stills", withIntermediateDirectories: true)
                        still.png(to: URL(fileURLWithPath: dir + "/stills/\(tag2)_medium_f\(frame).png"))
                    }
                    if frame % 2 == 0 && (seen || frame < 400) {
                        let clip = camG.viewProj * SIMD4<Float>(cen.x, cen.y, cen.z, 1)
                        let sx = Int((clip.x / clip.w * 0.5 + 0.5) * Float(W)), sy = Int((0.5 - clip.y / clip.w * 0.5) * Float(H))
                        let lbl = String(format: "f%d %@ y%.2f beans%d", frame, "\(me.brain.gait.phase)", cen.y, me.skinner.beansActive ? 1 : 0)
                        cellsG.append((Self.crop(g, cx: sx, cy: sy, size: 240), lbl))
                        cellsM.append((Self.crop(m, cx: W / 2, cy: H / 2, size: 604), lbl))
                    }
                }
                mp4G?.finish(); mp4M?.finish()
                XCTAssertTrue(seen, "\(tag2): cartwheel seen")
                Self.sheet(cellsG, cols: 8, tile: 300, title: "\(tag) \(tag2) game camera (604x1312 portrait), 240px crop (native pixels) on the cartwheeler, every 2nd frame at 120 fps", to: dir + "/\(tag2)_gamecam_sheet.png")
                Self.sheet(cellsM, cols: 8, tile: 300, title: "\(tag) \(tag2) medium shot, side-on, every 2nd frame at 120 fps", to: dir + "/\(tag2)_medium_sheet.png")
                MotionLog.write(String(format: "GAMECAM popcheck \(tag) \(tag2): largest frame-to-frame move of a bean vertex in the body frame %.3f u at frame %d (blend %.2f)", maxJump, maxJumpFrame, jumpBlend))
                MotionLog.write("GAMECAM \(tag) \(tag2): frames=\(frame) tiles=\(cellsG.count) mp4=\(dir)/\(tag2)_gamecam.mp4")
                Self.keep.removeAll()
            }
        }
    }
}
