//
//  GroupCaptureTests.swift
//  Not a regression test: a group social with 3 Jelbies rendered with the real renderer into one contact sheet (GROUP_CAP_DIR; skipped otherwise). GROUP_KIND = kind (default groupHug).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class GroupCaptureTests: XCTestCase {
    let W = 603, H = 1311

    func testCaptureGroup() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["GROUP_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("GROUP_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        let kind = SocialKind(rawValue: env["GROUP_KIND"] ?? "groupHug") ?? .groupHug
        let nFrames = Int(env["GROUP_FRAMES"] ?? "") ?? 8
        let lab = SocialTests.Lab(n: 3, positions: SocialTests.starts, quiet: true, seed: 3)
        SocialTests.keep.append(lab)
        for r in lab.rigs { r.skinner.autoBlink = false; r.brain.anticsEnabled = true }
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: lab.rigs[0].sim.edges, particleCount: lab.rigs[0].sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        ren.roomCacheEnabled = false
        XCTAssertTrue(lab.rigs[0].brain.socialStart(kind, with: lab.rigs[1].brain, lab.rigs[0].sim))
        // pass 1 (no render): when does the huddle start and end; then frames spread over gather / huddle / break
        var cells: [LockImage] = []
        var f = 0, endF = 0
        var marks: [Int] = []
        var huddleStart = -1
        while f < 60 * 40 {
            lab.tick(watching: false)
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            if huddleStart < 0, let s = lab.rigs[0].brain.social, s.phase >= 2 { huddleStart = f }
            f += 1
            if !lab.anySocial && f > 10 { endF = f; break }
        }
        _ = marks; marks = []
        let total = max(endF, huddleStart + 60)
        // pass 2: same seed, render
        let lab2 = SocialTests.Lab(n: 3, positions: SocialTests.starts, quiet: true, seed: 3)
        SocialTests.keep.append(lab2)
        for r in lab2.rigs { r.skinner.autoBlink = false; r.brain.anticsEnabled = true }
        _ = lab2.rigs[0].brain.socialStart(kind, with: lab2.rigs[1].brain, lab2.rigs[0].sim)
        let first = max(0, huddleStart - 90), span = max(1, total + 20 - first)
        let every = max(1, span / nFrames)
        for g in 0..<(total + 20) {
            lab2.tick(watching: false)
            for r in lab2.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            if g >= first, (g - first) % every == every / 2, cells.count < nFrames { cells.append(composite(lab2, ren, target)) }
        }
        let crop = CGRect(x: 0, y: CGFloat(H) * 0.50, width: CGFloat(W), height: CGFloat(H) * 0.34)
        let cw = 300, ch = Int(Double(cw) * Double(crop.height) / Double(crop.width)), pad = 4
        let cols = min(4, cells.count), rows = (cells.count + cols - 1) / cols
        let sw = cols * (cw + pad) + pad, sh = rows * (ch + pad) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
            for (i, cell) in cells.enumerated() {
                guard let ui = cell.uiImage(), let cg = ui.cgImage?.cropping(to: crop) else { continue }
                UIImage(cgImage: cg).draw(in: CGRect(x: pad + (i % cols) * (cw + pad), y: pad + (i / cols) * (ch + pad), width: cw, height: ch))
            }
        }
        try img.pngData()!.write(to: URL(fileURLWithPath: dir + "/group_hug.png"))
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
