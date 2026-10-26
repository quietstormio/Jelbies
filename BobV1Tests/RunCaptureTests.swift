//
//  RunCaptureTests.swift
//  Not a regression test: when RUN_CAP_DIR is set (TEST_RUNNER_RUN_CAP_DIR) it writes frame strips of the rolls with the real game
//  renderer (room, game camera), bare and in shoes, with the drawn-foot measurement of each frame in the label and in the motion log.
//  User, 2026-10-21 (phone): "When he rolled randomly his feet came off again."
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class RunCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func dir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["RUN_CAP_DIR"], !d.isEmpty else { throw XCTSkip("RUN_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    private func sheet(_ rows: [(String, [(String, LockImage)])], cw: Int, to path: String, cols: Int) throws {
        let ch = rows.flatMap { $0.1 }.map { Int(Double(cw) * Double($0.1.h) / Double($0.1.w)) }.max() ?? cw
        let labelH = 30, pad = 6, cellLabel = 30
        let sw = cols * (cw + pad) + pad
        var heights: [Int] = []
        for r in rows { heights.append(((r.1.count + cols - 1) / cols) * (ch + cellLabel + pad) + labelH) }
        let sh = heights.reduce(0, +) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
            var y = pad
            for (ri, row) in rows.enumerated() {
                (row.0 as NSString).draw(at: CGPoint(x: CGFloat(pad + 4), y: CGFloat(y + 6)), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white])
                for (c, cell) in row.1.enumerated() {
                    let cx = pad + (c % cols) * (cw + pad), cy = y + labelH + (c / cols) * (ch + cellLabel + pad)
                    (cell.0 as NSString).draw(in: CGRect(x: cx + 2, y: cy, width: cw, height: cellLabel), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor(white: 0.85, alpha: 1)])
                    if let ui = cell.1.uiImage() { ui.draw(in: CGRect(x: cx, y: cy + cellLabel, width: cw, height: Int(Double(cw) * Double(cell.1.h) / Double(cell.1.w)))) }
                }
                y += heights[ri]
            }
        }
        try img.pngData()!.write(to: URL(fileURLWithPath: path))
    }

    private func strip(dx: Float, dz: Float, device: MTLDevice, target: MTLTexture, Wc: Int, Hc: Int, C: Int) throws -> [(String, LockImage)] {
        let r = MotionRig(game: true); Self.keep.append(r)
        r.skinner.autoBlink = false
        r.brain.seed = 11; r.brain.autonomy = false
        r.brain.restTimer = 1e6; r.brain.idleState.cooldown = 1e6; r.brain.socialBook.cooldown = 1e6
        r.brain.expr.pickTimer = 1e6
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: Wc, height: Hc)
        let cam = GameCamera.camera(aspect: Float(Wc) / Float(Hc), focus: 0)
        let start = SIMD2<Float>(dx != 0 ? -1.6 : -0.2, dz != 0 ? -2.3 : -0.4)
        r.sim.teleport(toXZ: start)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.hurry = true
        r.brain.script = .walk(target: start + SIMD2(dx, dz) * 4.2, then: .none); r.brain.activity = .walking
        r.brain.scriptT = 0
        r.run(0.6)
        var out: [(String, LockImage)] = []
        var i = 0
        let every = Int(ProcessInfo.processInfo.environment["RUN_CAP_EVERY"] ?? "3") ?? 3
        while out.count < 10 {
            r.tick()
            r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            if i % every == 0 {
                ren.beginFrame()
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
                ren.setMouth(r.brain.mouthOpen, body: 0); ren.setBlush(r.brain.blushNow, body: 0)
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0
                let pal = PaletteKey.blue.palette
                fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                ren.setUniforms(camera: cam, light: GameCamera.light(centroid: r.sim.centroid()), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(Wc), Float(Hc)))
                let cmd = ren.queue.makeCommandBuffer()!
                ren.draw(to: target, commandBuffer: cmd, showMesh: false)
                cmd.waitUntilCompleted()
                var px = [UInt8](repeating: 0, count: Wc * Hc * 4)
                px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: Wc * 4, from: MTLRegionMake2D(0, 0, Wc, Hc), mipmapLevel: 0) }
                let c = r.sim.centroid()
                let clip = cam.viewProj * SIMD4<Float>(c.x, 0.45, c.z, 1)
                let sx = Int((clip.x / clip.w * 0.5 + 0.5) * Float(Wc)), sy = Int((0.5 - clip.y / clip.w * 0.5) * Float(Hc))
                let x0 = max(0, min(Wc - C, sx - C / 2)), y0 = max(0, min(Hc - C, sy - C / 2))
                var o = [UInt8](repeating: 0, count: C * C * 4)
                for y in 0..<C { for x in 0..<(C * 4) { o[y * C * 4 + x] = px[(y0 + y) * Wc * 4 + x0 * 4 + x] } }
                out.append((String(format: "f%d runW %.2f air %.3f\nbeans %d", out.count, r.brain.runW, r.brain.runAir, r.skinner.beansActive ? 1 : 0), LockImage(w: C, h: C, bgra: o)))
            }
            i += 1
            if i > 600 { break }
        }
        return out
    }

    func testRunStrip() throws {
        let d = try dir()
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let Wc = 1080, Hc = 1920, C = 420
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Wc, height: Hc, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: Float(Wc) / Float(Hc))
        var rows: [(String, [(String, LockImage)])] = []
        for (label, dx, dz) in [("run, side view (across the room)", Float(1), Float(0)), ("run, 3/4 view (toward the camera)", Float(0), Float(1))] {
            rows.append((label, try strip(dx: dx, dz: dz, device: device, target: target, Wc: Wc, Hc: Hc, C: C)))
        }
        try sheet(rows, cw: 200, to: d + "/run_cycle.png", cols: 10)
    }
}
