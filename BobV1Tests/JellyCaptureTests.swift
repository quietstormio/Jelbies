//
//  JellyCaptureTests.swift
//  Not a regression test: writes PNG frames of the walk with and without the jelly (same sim state, same moments) when
//  JIGGLE_CAPTURE_DIR is set (pass it as TEST_RUNNER_JIGGLE_CAPTURE_DIR). Skipped otherwise.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class JellyCaptureTests: XCTestCase {
    func testCaptureWalk() throws {
        guard let dir = ProcessInfo.processInfo.environment["JIGGLE_CAPTURE_DIR"] else { throw XCTSkip("JIGGLE_CAPTURE_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let W = 540, Hh = 960
        let r = MotionRig(game: true)
        r.skinner.autoBlink = false
        guard let device = MTLCreateSystemDefaultDevice(),
              let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n)
        else { throw XCTSkip("no Metal") }
        ren.resize(width: W, height: Hh)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: Hh, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        let cam = GameCamera.camera(aspect: Float(W) / Float(Hh), focus: 0)
        var rig = CameraRig()
        let light = rig.light(centroid: r.sim.centroid())

        func shot(_ name: String, jelly: Bool) {
            r.skinner.jelly.enabled = jelly
            ren.beginFrame()
            r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = PaletteKey.allCases.first!.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(Hh)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: W * Hh * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, Hh), mipmapLevel: 0) }
            LockImage(w: W, h: Hh, bgra: px).png(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }

        // scenario: still, walk right-forward, stop, walk back left (turn), stop, walk toward the camera, stop
        let legs: [(SIMD2<Float>, Float)] = [(.zero, 0.6), (SIMD2(1.4, 0.3), 3.2), (SIMD2(-1.4, 0.2), 4.2), (SIMD2(0, 1.2), 3.0)]
        var frame = 0, stepN = 0
        let start = r.root
        for (d, secs) in legs {
            if d != .zero { r.brain.request(.goTo(start + d)) }
            for _ in 0..<Int(secs * 60) {
                r.tick()
                r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
                stepN += 1
                if stepN % 2 == 0 {
                    let n = String(format: "%04d", frame)
                    shot("on_" + n, jelly: true); shot("off_" + n, jelly: false)
                    frame += 1
                }
            }
        }
        r.skinner.jelly.enabled = true
        MotionLog.write("JELLYCAP frames \(frame) at 30 fps in \(dir)")
    }
}
