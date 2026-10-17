//
//  ArmCapCaptureTests.swift
//  Not a regression test: writes PNG frames of jacks / flip / wave with the global arm cap off (before) and on (after) from the SAME sim
//  state (the cap is render-only) when ARMCAP_DIR is set (pass it as TEST_RUNNER_ARMCAP_DIR). Skipped otherwise.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class ArmCapCaptureTests: XCTestCase {
    func testCaptureMoves() throws {
        guard let dir = ProcessInfo.processInfo.environment["ARMCAP_DIR"] else { throw XCTSkip("ARMCAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let W = 1080, Hh = 1920
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: Hh, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        defer { ArmCap.enabled = true }

        func run(_ move: String, seconds: Float, every: Int, start: (MotionRig) -> Void) throws {
            for cap in [false, true] {
                ArmCap.enabled = cap
                let r = MotionRig(game: true)
                r.skinner.autoBlink = false
                r.brain.seed = 11; r.brain.amplitude = 1
                guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n) else { throw XCTSkip("no Metal") }
                ren.resize(width: W, height: Hh)
                let cam = GameCamera.camera(aspect: Float(W) / Float(Hh), focus: 0)
                var rig = CameraRig()
                let light = rig.light(centroid: r.sim.centroid())
                start(r)
                var k = 0
                for i in 0..<Int(seconds * 60) {
                    r.tick()
                    r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
                    if i % every != 0 { continue }
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
                    let name = String(format: "%@_%@_%03d.png", move, cap ? "after" : "before", k)
                    LockImage(w: W, h: Hh, bgra: px).png(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
                    k += 1
                }
            }
        }
        try run("jacks", seconds: 7, every: 3) { r in r.brain.idleForced = true; _ = r.brain.idleStart(.jacks, r.sim) }
        try run("flip", seconds: 1.6, every: 3) { r in r.brain.startFlip(sim: r.sim) }
        try run("wave", seconds: 3.2, every: 6) { r in r.brain.request(.wave) }
    }
}
