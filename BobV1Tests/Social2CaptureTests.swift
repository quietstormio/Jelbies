//
//  Social2CaptureTests.swift
//  Not a regression test: the ten new friend socials (BlobSocial+Friends2.swift) plus the chest bump and high five, rendered with the real renderer
//  (like SocialCaptureTests) into one contact sheet of key frames per interaction, with a run summary (seconds to the end, closest gap, ending).
//  Output: SOCIAL2_CAP_DIR (TEST_RUNNER_SOCIAL2_CAP_DIR); skipped otherwise. SOCIAL2_KINDS = comma list to limit; SOCIAL2_FRAMES = frames per kind.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class Social2CaptureTests: XCTestCase {
    let W = 603, H = 1311

    func testCaptureSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SOCIAL2_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("SOCIAL2_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let all: [SocialKind] = [.chestBump, .highFive, .littleRace, .tag, .leapfrog, .peekaboo, .bellyBounce, .mirrorDance, .noseBoop, .backToBack, .cuddleLean, .ringAround]
        let want = (env["SOCIAL2_KINDS"] ?? "").split(separator: ",").map(String.init)
        let kinds = want.isEmpty ? all : all.filter { want.contains($0.rawValue) }
        let nFrames = Int(env["SOCIAL2_FRAMES"] ?? "") ?? 8
        let startsPos: [SIMD2<Float>] = [SIMD2(-1.6, 0.4), SIMD2(0.9, 0.4)]
        var rows: [(String, [LockImage])] = []
        var log = ""

        for kind in kinds {
            // pass 1: how long it runs
            var total = 0
            do {
                let lab = SocialTests.Lab(n: 2, positions: startsPos, quiet: true, seed: 3)
                XCTAssertTrue(lab.rigs[0].brain.socialStart(kind, with: lab.rigs[1].brain, lab.rigs[0].sim), "\(kind) starts")
                var minGap: Float = 9
                for f in 0..<(60 * 45) {
                    lab.tick(watching: false)
                    minGap = min(minGap, lab.centreGap(0, 1))
                    if lab.rigs[0].brain.social == nil, lab.rigs[1].brain.social == nil, f > 10 { total = f; break }
                }
                let ended = lab.events[0].compactMap { e -> String? in if case .ended(let k, _, let how) = e, k == kind { return "\(how)" }; return nil }
                log += "\(kind.rawValue): \(Float(total) / 60) s, ended \(ended), min centre gap \(minGap)\n"
            }
            if total == 0 { total = 60 * 45 }
            if env["SOCIAL2_NORENDER"] != nil { continue }
            // pass 2: render
            let lab = SocialTests.Lab(n: 2, positions: startsPos, quiet: true, seed: 3)
            SocialTests.keep.append(lab)
            for r in lab.rigs { r.skinner.autoBlink = false }
            guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: lab.rigs[0].sim.edges, particleCount: lab.rigs[0].sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
            ren.resize(width: W, height: H)
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            let target = device.makeTexture(descriptor: td)!
            ren.roomCacheEnabled = false
            _ = lab.rigs[0].brain.socialStart(kind, with: lab.rigs[1].brain, lab.rigs[0].sim)
            var cells: [LockImage] = []
            let every = max(1, total / nFrames)
            for f in 0..<(total + 30) {
                lab.tick(watching: false)
                for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
                if f % every == every / 2, cells.count < nFrames { cells.append(composite(lab, ren, target)) }
            }
            rows.append((kind.rawValue, cells))
        }
        try log.write(toFile: dir + "/summary.txt", atomically: true, encoding: .utf8)
        if rows.isEmpty { return }

        // sheet: each cell cropped to the middle band where the pair plays
        let crop = CGRect(x: 0, y: CGFloat(H) * 0.30, width: CGFloat(W), height: CGFloat(H) * 0.34)
        let cw = 300, ch = Int(Double(cw) * Double(crop.height) / Double(crop.width)), labelH = 26, pad = 4
        let cols = rows.map { $0.1.count }.max() ?? nFrames
        let sw = cols * (cw + pad) + pad, sh = rows.count * (ch + labelH + pad) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
            for (r, row) in rows.enumerated() {
                let y0 = pad + r * (ch + labelH + pad)
                (row.0 as NSString).draw(at: CGPoint(x: CGFloat(pad + 4), y: CGFloat(y0 + 4)), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: UIColor.white])
                for (c, cell) in row.1.enumerated() {
                    guard let ui = cell.uiImage(), let cg = ui.cgImage?.cropping(to: crop) else { continue }
                    UIImage(cgImage: cg).draw(in: CGRect(x: pad + c * (cw + pad), y: y0 + labelH, width: cw, height: ch))
                }
            }
        }
        try img.pngData()!.write(to: URL(fileURLWithPath: dir + "/interactions.png"))
        for (r, row) in rows.enumerated() { for (c, cell) in row.1.enumerated() { cell.png(to: URL(fileURLWithPath: dir + "/cell_\(row.0)_\(c).png")) }; _ = r }
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
