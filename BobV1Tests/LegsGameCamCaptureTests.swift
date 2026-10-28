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

    /// One move of one character (bare / shoes) in the room of three, rendered every frame at a 120 fps cadence: the real game camera, a medium shot along the game camera's
    /// own direction ("front") and a medium side-on shot. `move`: cartwheel / flip / faceplant. Output under AUDIT_CAP_DIR/game_cam2/<tag>/.
    func capture(char c: Int, shoes: Bool, move: String, tag: String, dir: String, device: MTLDevice) throws {
        let W = 604, H = 1312
        let rm = MotionRig.renderMesh
        let names = ["Bob", "Pip", "Moss", "Lavender"]
        BlobBrain.forceLegsFix = tag != "before"
        defer { BlobBrain.forceLegsFix = true }
        let ids = c == 0 ? [0, 2, 3] : [1, 2, 3]
        // the cartwheeler stands at the front spot (nearest the camera), the others at the two back spots: nobody within 1.5 u of him
        let spots = JellyRoster.spawnSpots(count: 3)
        let slot = 0
        var order = ids; order.removeAll { $0 == c }; order.insert(c, at: 0)
        var rigs: [MotionRig] = []
        for (k, id) in order.enumerated() {
            let r = MotionRig(game: true, settle: 0.5); Self.keep.append(r)
            r.renderSamples = false; r.skinner.autoBlink = false
            r.skinner.guardEnabled = tag != "before"
            r.brain.feature = JellyRoster.feature(id)
            r.skinner.configureTail(rm); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            r.sim.teleport(toXZ: spots[k]); for _ in 0..<90 { r.sim.step() }
            r.brain.currentPose(r.sim)
            rigs.append(r)
        }
        let me = rigs[slot]
        me.brain.shoesWorn = shoes
        me.brain.seed = 11
        me.brain.peers = { [unowned a = rigs[1], b = rigs[2]] in [(id: 1, pos: a.root), (id: 2, pos: b.root)] }
        me.brain.steerID = 0; me.brain.peerGap = 0.9
        me.brain.idleForced = true
        switch move {
        case "flip": me.brain.startFlip(sim: me.sim)
        case "faceplant": me.brain.startFlip(sim: me.sim, fail: true)
        default: guard me.brain.idleStart(.cartwheel, me.sim) else { XCTFail("cartwheel did not start for \(names[c])"); return }
        }
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: me.sim.edges, particleCount: me.sim.n, game: true, bodyCount: 3), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.roomCacheEnabled = false
        ren.resize(width: W, height: H)
        for (k, id) in order.enumerated() { ren.setPalette(JellyRoster.palette(id) ?? PaletteKey.blue.palette, body: k) }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let tex = device.makeTexture(descriptor: td)!
        WearBody.install(rm)
        let feats = FeatureSet(); feats.body = WearBody.shared; Self.keep.append(feats)
        let tag2 = "\(names[c])\(shoes ? "_shoes" : "")_\(move)"
        let mp4G = MP4Out(url: URL(fileURLWithPath: dir + "/\(tag2)_gamecam.mp4"), w: W, h: H, fps: 60)
        let mp4F = MP4Out(url: URL(fileURLWithPath: dir + "/\(tag2)_front.mp4"), w: W, h: H, fps: 60)
        let mp4S = MP4Out(url: URL(fileURLWithPath: dir + "/\(tag2)_side.mp4"), w: W, h: H, fps: 30)
        var cellsG: [(LockImage, String)] = [], cellsF: [(LockImage, String)] = [], cellsS: [(LockImage, String)] = []
        let camG = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)

        func render(_ cam: CameraState) -> LockImage {
            ren.beginFrame()
            for (k, r) in rigs.enumerated() { r.skinner.update(x: r.sim.x, index: rm.index, into: ren.dynPointer(body: k)) }
            // the character features (Pip's tail spikes, Moss's daisy, Lavender's wings) of all three, from this frame's skin
            for k in rigs.indices { feats.syncCarry(k, sim: rigs[k].sim) }
            let ff = feats.frame(hidden: false) { ren.skinPointer(body: $0) }
            ren.room!.setWear(opaque: ff, translucent: RoomMesh(), bounds: [])
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
            ren.setUniforms(camera: cam, light: GameCamera.light(centroids: rigs.map { $0.sim.centroid() }), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: tex, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { tex.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            return LockImage(w: W, h: H, bgra: px)
        }
        func mediumCam(_ cen: SIMD3<Float>, front: Bool) -> CameraState {
            let at = SIMD3<Float>(cen.x, max(0.55, cen.y), cen.z)
            let dirv: SIMD3<Float> = front ? simd_normalize(camG.pos - at) : simd_normalize(SIMD3(5.9, 0.5, 0.3))
            let eye = at + dirv * 5.9
            var cam = CameraState()
            cam.view = M4.lookAt(eye: eye, at: at, up: SIMD3(0, 1, 0))
            cam.viewProj = M4.mul(M4.perspective(fovy: 32 * .pi / 180, aspect: Float(W) / Float(H), near: 0.1, far: 60), cam.view)
            cam.invViewProj = M4.invert(cam.viewProj); cam.pos = eye; cam.fwd = simd_normalize(at - eye)
            return cam
        }

        let stepDt = me.sim.stepDt
        var acc: Float = 0, t: Float = 0, frame = 0, seen = false, after: Float = 0
        let dt: Float = 1.0 / 120
        var prevQ: [SIMD3<Float>] = [], maxJump: Float = 0, maxJumpFrame = 0
        var minLeg: Float = .infinity, minLegFrame = 0, maxFloorVerts = 0
        while t < 14 {
            acc += dt
            var steps = 0
            while acc >= stepDt && steps < 2 {
                for (k, r) in rigs.enumerated() {
                    r.brain.tick(sim: r.sim, skinner: r.skinner, dt: stepDt, touched: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: stepDt)
                    feats.tick(id: k, brain: r.brain, sim: r.sim, feature: r.brain.feature, worn: [], hideAll: false, dt: stepDt)
                    if let sl = feats.slot(k) { r.brain.wingsFolded = sl.fit.folded; r.brain.wingFlapLimit = sl.fit.flapMax }
                }
                for r in rigs { r.sim.step() }
                t += stepDt; acc -= stepDt; steps += 1
            }
            if steps > 0 { for r in rigs { r.brain.refitBeans(r.sim, r.skinner) } }
            for r in rigs { r.skinner.tickBlink(dt: dt) }
            let moving = me.brain.idleState.kind == .cartwheel || me.brain.gait.isBusy
            if moving { seen = true } else if seen { after += dt }
            if after > 0.5 { break }
            if !seen && t > 3 { break }
            frame += 1
            guard seen else { continue }
            let cen = me.sim.centroid()
            let g = render(camG)
            // leg metrics from this frame's skin
            me.render()
            let mm = LegsDrawnAuditTests.measure(me, shoes: false)
            if mm.beans { if mm.legOut < minLeg { minLeg = mm.legOut; minLegFrame = frame } }
            var atFloor = 0
            for sd in 0..<2 { for id in me.bean[sd] where me.dyn[6 * Int(id) + 1] <= me.sim.floorY + 1e-4 { atFloor += 1 } }
            maxFloorVerts = max(maxFloorVerts, atFloor)
            if me.skinner.beansActive, me.skinner.beanBlend > 0.05, !me.bean[0].isEmpty {
                let pose = me.sim.bodyPose(iterations: 4)
                var q: [SIMD3<Float>] = []
                for sd in 0..<2 { var i = 0; while i < FootBean.vertexCount { let o = 6 * Int(me.bean[sd][i]); q.append(pose.rotation.inverse.act(SIMD3(me.dyn[o], me.dyn[o + 1], me.dyn[o + 2]) - pose.centroid)); i += 31 } }
                if prevQ.count == q.count { for k in q.indices { let j = simd_distance(q[k], prevQ[k]); if j > maxJump { maxJump = j; maxJumpFrame = frame } } }
                prevQ = q
            } else { prevQ = [] }
            let f = render(mediumCam(cen, front: true))
            mp4G?.add(g.bgra); mp4F?.add(f.bgra)
            let evenFrame = frame % 2 == 0
            var sImg: LockImage? = nil
            if evenFrame { let s = render(mediumCam(cen, front: false)); sImg = s; mp4S?.add(s.bgra) }
            if [30, 40, 50, 60, 70, 86, 90].contains(frame) {
                try? FileManager.default.createDirectory(atPath: dir + "/stills", withIntermediateDirectories: true)
                Self.crop(f, cx: W / 2, cy: H / 2, size: 604).png(to: URL(fileURLWithPath: dir + "/stills/\(tag2)_front_f\(frame).png"))
                if let s = sImg { Self.crop(s, cx: W / 2, cy: H / 2, size: 604).png(to: URL(fileURLWithPath: dir + "/stills/\(tag2)_side_f\(frame).png")) }
            }
            if evenFrame {
                let clip = camG.viewProj * SIMD4<Float>(cen.x, cen.y, cen.z, 1)
                let sx = Int((clip.x / clip.w * 0.5 + 0.5) * Float(W)), sy = Int((0.5 - clip.y / clip.w * 0.5) * Float(H))
                let lbl = String(format: "f%d %@ y%.2f leg%.2f", frame, "\(me.brain.gait.phase)", cen.y, mm.beans ? mm.legOut : 0)
                cellsG.append((Self.crop(g, cx: sx, cy: sy, size: 240), lbl))
                cellsF.append((Self.crop(f, cx: W / 2, cy: H / 2, size: 604), lbl))
                if let s = sImg { cellsS.append((Self.crop(s, cx: W / 2, cy: H / 2, size: 604), lbl)) }
            }
        }
        mp4G?.finish(); mp4F?.finish(); mp4S?.finish()
        XCTAssertTrue(seen, "\(tag2): move seen")
        Self.sheet(cellsG, cols: 8, tile: 300, title: "\(tag) \(tag2) GAME camera (604x1312 portrait), 240px native crop on the mover, every 2nd frame at 120 fps", to: dir + "/\(tag2)_gamecam_sheet.png")
        Self.sheet(cellsF, cols: 8, tile: 300, title: "\(tag) \(tag2) medium FRONT (along the game camera direction), every 2nd frame", to: dir + "/\(tag2)_front_sheet.png")
        Self.sheet(cellsS, cols: 8, tile: 300, title: "\(tag) \(tag2) medium SIDE-ON (+x), every 2nd frame", to: dir + "/\(tag2)_side_sheet.png")
        MotionLog.write(String(format: "GAMECAM2 %@ %@: frames=%d minVisibleLeg=%.3f@f%d maxBeanVertsOnFloor=%d maxJump=%.3f@f%d", tag, tag2, frame, minLeg, minLegFrame, maxFloorVerts, maxJump, maxJumpFrame))
        Self.keep.removeAll()
    }

    func testGameCameraMoves() throws {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["AUDIT_CAP_DIR"], !base.isEmpty else { throw XCTSkip("AUDIT_CAP_DIR not set") }
        let tag = env["AUDIT_TAG"] ?? "before"
        let dir = base + "/game_cam2/" + tag
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        _ = GameCamera.camera(aspect: 604.0 / 1312.0)
        var cases: [(Int, Bool, String)] = []
        for c in [1, 2, 3, 0] { for shoes in [false, true] { cases.append((c, shoes, "cartwheel")) } }
        cases += [(0, false, "flip"), (1, true, "flip"), (2, false, "faceplant"), (0, true, "faceplant")]
        if let only = env["AUDIT_CASES"] { let idx = only.split(separator: ",").compactMap { Int($0) }; cases = idx.compactMap { $0 < cases.count ? cases[$0] : nil } }
        for (c, shoes, move) in cases { try capture(char: c, shoes: shoes, move: move, tag: tag, dir: dir, device: device) }
    }
}
