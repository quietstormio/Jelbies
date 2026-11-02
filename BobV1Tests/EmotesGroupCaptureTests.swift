//
//  EmotesGroupCaptureTests.swift
//  Not a regression test: the group emotes (highFive, congaLine, ringDance) rendered with the real renderer into a 6-frame strip (EMOTE_DIR; skipped otherwise).
//  EMOTE_KIND = the SocialKind raw value, EMOTE_FRAMES (6), EMOTE_FROM / EMOTE_TO = seconds of the run to spread the frames over (default: the whole run),
//  EMOTE_CHARS = "0,1,2" characters of the three rigs (0 Bob, 1 Pip, 2 Moss, 3 Lavender, 4 Teddy, 5 Pearl), EMOTE_ZOOM = 1 crops tighter on the group.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class EmotesGroupCaptureTests: XCTestCase {
    let S = Int(ProcessInfo.processInfo.environment["EMOTE_SCALE"] ?? "") ?? 2
    var W: Int { 603 * S }
    var H: Int { 1311 * S }

    func testCaptureEmote() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["EMOTE_DIR"], !dir.isEmpty else { throw XCTSkip("EMOTE_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        let kind = SocialKind(rawValue: env["EMOTE_KIND"] ?? "highFive") ?? .highFive
        let nFrames = Int(env["EMOTE_FRAMES"] ?? "") ?? 6
        let chars = (env["EMOTE_CHARS"] ?? "0,1,2").split(separator: ",").compactMap { Int($0) }
        let seed = UInt64(env["EMOTE_SEED"] ?? "") ?? 3
        func makeLab() -> SocialTests.Lab {
            var pos = SocialTests.starts
            if let c = env["EMOTE_POS3"]?.split(separator: ",").compactMap({ Float($0) }), c.count == 2 { pos[2] = SIMD2(c[0], c[1]) }
            let lab = SocialTests.Lab(n: 3, positions: pos, quiet: true, seed: seed)
            SocialTests.keep.append(lab)
            for (i, r) in lab.rigs.enumerated() {
                r.skinner.autoBlink = false; r.brain.anticsEnabled = true
                let c = chars[i % chars.count]
                r.brain.feature = OnePieceInvariantTests.characters[c].1
                r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            }
            return lab
        }
        let lab = makeLab()
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: lab.rigs[0].sim.edges, particleCount: lab.rigs[0].sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        ren.roomCacheEnabled = false
        XCTAssertTrue(lab.rigs[0].brain.socialStart(kind, with: lab.rigs[1].brain, lab.rigs[0].sim), "\(kind) starts")
        var f = 0, endF = 0
        while f < 60 * 60 {
            lab.tick(watching: false)
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            f += 1
            if !lab.anySocial && f > 10 { endF = f; break }
        }
        MotionLog.write("EMOTE CAPTURE \(kind) lasts \(Float(endF) / 60) s")
        let lab2 = makeLab()
        _ = lab2.rigs[0].brain.socialStart(kind, with: lab2.rigs[1].brain, lab2.rigs[0].sim)
        let from = Int((Float(env["EMOTE_FROM"] ?? "") ?? 0.5) * 60), to = Int((Float(env["EMOTE_TO"] ?? "") ?? (Float(endF) / 60)) * 60)
        let every = max(1, (to - from) / nFrames)
        var cells: [LockImage] = []
        for g in 0..<(max(endF, to) + 10) {
            lab2.tick(watching: false)
            for r in lab2.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            if g >= from, (g - from) % every == every / 2, cells.count < nFrames { cells.append(composite(lab2, ren, target)) }
        }
        var crop = CGRect(x: CGFloat(W) * 0.12, y: CGFloat(H) * 0.50, width: CGFloat(W) * 0.76, height: CGFloat(H) * 0.20)
        if let c = env["EMOTE_CROP"]?.split(separator: ",").compactMap({ Double($0) }), c.count == 4 { crop = CGRect(x: CGFloat(c[0]) * CGFloat(W), y: CGFloat(c[1]) * CGFloat(H), width: CGFloat(c[2]) * CGFloat(W), height: CGFloat(c[3]) * CGFloat(H)) }
        let cw = 600, ch = Int(Double(cw) * Double(crop.height) / Double(crop.width)), pad = 4
        let cols = min(3, cells.count), rows = (cells.count + cols - 1) / cols
        let sw = cols * (cw + pad) + pad, sh = rows * (ch + pad) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
            for (i, cell) in cells.enumerated() {
                guard let ui = cell.uiImage(), let cg = ui.cgImage?.cropping(to: crop) else { continue }
                UIImage(cgImage: cg).draw(in: CGRect(x: pad + (i % cols) * (cw + pad), y: pad + (i / cols) * (ch + pad), width: cw, height: ch))
            }
        }
        let tag = env["EMOTE_TAG"] ?? ""
        try img.pngData()!.write(to: URL(fileURLWithPath: dir + "/\(kind.rawValue)\(tag).png"))
    }

    private func composite(_ lab: SocialTests.Lab, _ ren: MelonRenderer, _ target: MTLTexture) -> LockImage {
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        func shot(only: Int?) -> LockImage {
            let light = GameCamera.light(centroid: lab.rigs[only ?? 0].sim.centroid())
            ren.beginFrame()
            let k = only ?? 0
            lab.rigs[k].skinner.update(x: lab.rigs[k].sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            if only == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = PaletteKey.blue.palette
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
}
