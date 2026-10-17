//
//  RunMoveCaptureTests.swift
//  Not a regression test: writes square crops (one fixed scale, centred on the body, game camera) of the Build B running actions and of the walk
//  jiggle before (legacy tuning) / after, when RUNMOVE_CAP_DIR is set (pass it as TEST_RUNNER_RUNMOVE_CAP_DIR). Skipped otherwise.
//  Files: <name>_<k>.png every `every` sim steps; the frame times are written to <name>.txt.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class RunMoveCaptureTests: XCTestCase {
    func testCapture() throws {
        guard let dir = ProcessInfo.processInfo.environment["RUNMOVE_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("RUNMOVE_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let W = 1080, Hh = 1920, C = 440
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: Hh, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!

        func run(_ name: String, seconds: Float, every: Int, legacy: Bool = false, from: Float = 0, start: (MotionRig) -> Void) throws {
            let r = MotionRig(game: true)
            r.skinner.autoBlink = false
            r.brain.seed = 11; r.brain.amplitude = 1
            r.skinner.jelly.legacy = legacy
            guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n) else { throw XCTSkip("no Metal") }
            ren.resize(width: W, height: Hh)
            let cam = GameCamera.camera(aspect: Float(W) / Float(Hh), focus: 0)
            var rig = CameraRig()
            let light = rig.light(centroid: r.sim.centroid())
            start(r)
            var k = 0, log = ""
            for i in 0..<Int(seconds * 60) {
                r.tick()
                r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
                if i % every != 0 || Float(i) / 60 < from { continue }
                ren.beginFrame()
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0
                let pal = PaletteKey.blue.palette
                fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(Hh)))
                let cmd = ren.queue.makeCommandBuffer()!
                ren.draw(to: target, commandBuffer: cmd, showMesh: false)
                cmd.waitUntilCompleted()
                var px = [UInt8](repeating: 0, count: W * Hh * 4)
                px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, Hh), mipmapLevel: 0) }
                // crop a fixed-size square around the body centre (its screen position, with a little lift so the feet stay in frame)
                let c = r.sim.centroid()
                let clip = cam.viewProj * SIMD4<Float>(c.x, 0.55, c.z, 1)
                let sx = Int((clip.x / clip.w * 0.5 + 0.5) * Float(W)), sy = Int((0.5 - clip.y / clip.w * 0.5) * Float(Hh))
                let x0 = max(0, min(W - C, sx - C / 2)), y0 = max(0, min(Hh - C, sy - C / 2))
                var out = [UInt8](repeating: 0, count: C * C * 4)
                for y in 0..<C { for x in 0..<(C * 4) { out[y * C * 4 + x] = px[(y0 + y) * W * 4 + x0 * 4 + x] } }
                let fn = String(format: "%@_%03d.png", name, k)
                LockImage(w: C, h: C, bgra: out).png(to: URL(fileURLWithPath: dir).appendingPathComponent(fn))
                log += String(format: "%d %.3f\n", k, Float(i) / 60)
                k += 1
            }
            try log.write(toFile: dir + "/" + name + ".txt", atomically: true, encoding: .utf8)
        }
        let only = ProcessInfo.processInfo.environment["RUNMOVE_ONLY"].flatMap { $0.isEmpty ? nil : $0 }
        func want(_ n: String) -> Bool { only == nil || only == n }
        /// `aim`: replace the random goal with one toward the camera (+z) and a little to the side, so the face is seen through the move.
        func idle(_ k: IdleKind, aim: SIMD2<Float>) -> (MotionRig) -> Void {
            { r in
                r.brain.idleForced = true
                _ = r.brain.idleStart(k, r.sim)
                let g = r.root + aim
                r.brain.idleState.target = g
                if k != .scoot { r.brain.script = .walk(target: g, then: .none) }
            }
        }
        if want("zoomies") { try run("zoomies", seconds: 5, every: 3, start: idle(.zoomies, aim: SIMD2(1.0, 3.6))) }
        if want("slide") { try run("slide", seconds: 5, every: 3, start: idle(.slide, aim: SIMD2(1.0, 3.4))) }
        if want("scoot") { try run("scoot", seconds: 3.2, every: 3, start: idle(.scoot, aim: SIMD2(0.5, 1.7))) }
        if want("walk") {
            for (n, legacy) in [("walkold", true), ("walknew", false)] {
                try run(n, seconds: 5, every: 3, legacy: legacy) { r in r.brain.request(.goTo(r.root + SIMD2(1.8, 0.9))) }
            }
        }
    }
}
