//
//  SocialCaptureTests.swift
//  Not a regression test: renders a boop, a follow, shared zoomies and a squabble of 3 headless rigs with the REAL renderer (MelonRenderer, game room,
//  game camera, true phone aspect) and composes a labelled contact sheet. The renderer draws ONE body per pass, so each rig is rendered separately
//  (same camera, same room), and the bodies are composited over an empty-room render by the pixels each body changes, nearest to the camera last.
//  Output: SOCIAL_CAP_DIR (pass as TEST_RUNNER_SOCIAL_CAP_DIR): sheet.png and the cells. Skipped otherwise.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class SocialCaptureTests: XCTestCase {
    let W = 603, H = 1311

    func testCaptureSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["SOCIAL_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("SOCIAL_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }

        var rows: [(String, [LockImage])] = []
        func scene(_ label: String, kind: SocialKind, seconds: Float, frames: Int, positions: [SIMD2<Float>] = SocialTests.starts, setup: (SocialTests.Lab) -> Void = { _ in }) throws {
            let lab = SocialTests.Lab(positions: positions, seed: 31)
            SocialTests.keep.append(lab)
            let r0 = lab.rigs[0]
            for r in lab.rigs { r.skinner.autoBlink = false }
            guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r0.sim.edges, particleCount: r0.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
            ren.resize(width: W, height: H)
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            let target = device.makeTexture(descriptor: td)!
            ren.roomCacheEnabled = false
            setup(lab)
            XCTAssertTrue(r0.brain.socialStart(kind, with: lab.rigs[1].brain, r0.sim), "\(label) starts")
            var cells: [LockImage] = []
            let every = max(1, Int(seconds * 60) / frames)
            var f = 0
            while cells.count < frames && f < Int(seconds * 60) + 600 {
                lab.tick(watching: false)
                for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
                if f % every == 0 { cells.append(composite(lab, ren, target)) }
                f += 1
            }
            rows.append((label, cells))
        }
        try scene("boop: walks up, bump (heart + haptic beat)", kind: .boop, seconds: 4.6, frames: 6)
        try scene("follow: leader wanders, follower trails at a gap", kind: .follow, seconds: 7.5, frames: 6)
        try scene("shared zoomies: one dashes, the other loops round", kind: .zoomies, seconds: 6.0, frames: 6)
        try scene("squabble: face-off, puffy jiggle, shoves, annoyed eyes", kind: .squabble, seconds: 10.5, frames: 6)

        // sheet
        let cw = 232, ch = Int(Double(cw) * Double(H) / Double(W)), labelH = 34, pad = 6
        let cols = rows.map { $0.1.count }.max() ?? 6
        let sw = cols * (cw + pad) + pad, sh = rows.count * (ch + labelH + pad) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
            for (r, row) in rows.enumerated() {
                let y0 = pad + r * (ch + labelH + pad)
                (row.0 as NSString).draw(at: CGPoint(x: CGFloat(pad + 4), y: CGFloat(y0 + 8)), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: UIColor.white])
                for (c, cell) in row.1.enumerated() {
                    if let ui = cell.uiImage() { ui.draw(in: CGRect(x: pad + c * (cw + pad), y: y0 + labelH, width: cw, height: ch)) }
                    ("t\(c)" as NSString).draw(at: CGPoint(x: CGFloat(pad + c * (cw + pad) + 4), y: CGFloat(y0 + labelH + 2)), withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.darkGray])
                }
            }
        }
        try img.pngData()!.write(to: URL(fileURLWithPath: dir + "/sheet.png"))
        for (r, row) in rows.enumerated() { for (c, cell) in row.1.enumerated() { cell.png(to: URL(fileURLWithPath: dir + "/cell_\(r)_\(c).png")) } }
    }

    /// Room + every rig's body: an empty-room render, then per rig a render with only that body, pasted by the pixels it changes (farthest first).
    private func composite(_ lab: SocialTests.Lab, _ ren: MelonRenderer, _ target: MTLTexture) -> LockImage {
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        func shot(only: Int?) -> LockImage {
            let light = GameCamera.light(centroid: lab.rigs[only ?? 0].sim.centroid())
            ren.beginFrame()
            let k = only ?? 0
            lab.rigs[k].skinner.update(x: lab.rigs[k].sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            if only == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }       // the empty room: the body is far below the floor
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
