//
//  LegsStripCaptureTests.swift
//  Not a regression test: writes a labelled-by-order frame strip (PNG) of one spin move when LEGS_STRIP_OUT is set
//  (TEST_RUNNER_LEGS_STRIP_OUT=/path/x.png, TEST_RUNNER_LEGS_MOVE=cartwheel|flip|roll). Skipped otherwise.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class LegsStripCaptureTests: XCTestCase {
    func testStrip() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["LEGS_STRIP_OUT"] else { throw XCTSkip("LEGS_STRIP_OUT not set") }
        let move = env["LEGS_MOVE"] ?? "cartwheel"
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        let T = 450, cols = 4, nFrames = 12
        let r = MotionRig(game: true)
        r.brain.seed = 5; r.brain.amplitude = 1; r.brain.idleForced = true; r.brain.anticsEnabled = true
        r.skinner.autoBlink = false
        guard let device = MTLCreateSystemDefaultDevice(),
              let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n)
        else { throw XCTSkip("no Metal") }
        ren.resize(width: T, height: T)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: T, height: T, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        var rig = CameraRig()
        var tiles: [[UInt8]] = []

        func shot() {
            let c = r.sim.centroid()
            let tgt = SIMD3<Float>(c.x, 0.55, c.z)
            let az: Float = 0.65, el: Float = 0.18, dist: Float = 5.0
            let eye = tgt + SIMD3(dist * sinf(az) * cosf(el), dist * sinf(el), dist * cosf(az) * cosf(el))
            var cam = CameraState()
            cam.view = M4.lookAt(eye: eye, at: tgt, up: SIMD3(0, 1, 0))
            cam.viewProj = M4.mul(M4.perspective(fovy: CameraRig.fov, aspect: 1, near: 0.1, far: 60), cam.view)
            cam.invViewProj = M4.invert(cam.viewProj); cam.pos = eye; cam.fwd = simd_normalize(tgt - eye)
            rig.azimuth = az
            let light = rig.light(centroid: c)
            ren.beginFrame()
            r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(T), Float(T)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: T * T * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: T * 4, from: MTLRegionMake2D(0, 0, T, T), mipmapLevel: 0) }
            tiles.append(px)
        }

        func logFeet(_ r: MotionRig, _ i: Int) {
            r.render()
            let pose = r.sim.bodyPose(iterations: 3), c0 = r.sim.restCentroid
            let b = r.brain
            let beans = r.skinner.beansActive && r.skinner.beanBlend > 0.05
            var msg = String(format: "LEGSLOG %3d tilt %.2f cy %.2f beans %@ G %.2f blend %.2f tuck %.3f |", i, pose.tilt, r.sim.centroid().y, beans ? "Y" : "n", b.beanG, r.skinner.beanBlend, b.gait.tuck)
            for s in 0..<2 {
                let ids = beans ? r.bean[s] : r.core[s]
                var deepest = Float.infinity, cb = SIMD3<Float>.zero, hi: Float = -.infinity
                for id in ids {
                    let o = 6 * Int(id)
                    let q = c0 + pose.rotation.inverse.act(SIMD3(r.dyn[o], r.dyn[o + 1], r.dyn[o + 2]) - pose.centroid)
                    deepest = min(deepest, Float(BobForm.bodySDF(SIMD3(Double(abs(q.x)), Double(q.y), Double(q.z)))))
                    cb += q; hi = max(hi, Float(BobForm.bodySDF(SIMD3(Double(abs(q.x)), Double(q.y), Double(q.z)))))
                }
                cb /= Float(max(1, ids.count))
                msg += String(format: " f%d deepest %.3f shallowest %.3f ctr(%.2f %.2f %.2f)", s, deepest, hi, cb.x, cb.y, cb.z)
            }
            MotionLog.write(msg)
        }
        switch move {
        case "flip": r.brain.startFlip(sim: r.sim, compact: false)
        case "roll": XCTAssertTrue(r.brain.idleStart(.roll, r.sim))
        default: XCTAssertTrue(r.brain.idleStart(.cartwheel, r.sim))
        }
        // collect every tick while the body is meaningfully tilted or airborne, then thin to nFrames
        var cands: [[UInt8]] = []
        var started = false, quiet = 0
        for _ in 0..<(60 * 8) {
            r.tick()
            r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            let p = r.sim.bodyPose(iterations: 3)
            let active = p.tilt > 0.25 || r.sim.centroid().y > r.sim.floorY + 0.75
            if active { started = true; quiet = 0 } else if started { quiet += 1 }
            if started { shot(); cands.append(tiles.removeLast()); logFeet(r, cands.count - 1) }
            if started && quiet > 8 { break }
        }
        XCTAssertGreaterThan(cands.count, nFrames)
        for k in 0..<nFrames { tiles.append(cands[k * (cands.count - 1) / (nFrames - 1)]) }
        MotionLog.write("LEGSSTRIP \(move): \(cands.count) active ticks")
        let rows = (nFrames + cols - 1) / cols
        let W = T * cols, H = T * rows
        var all = [UInt8](repeating: 255, count: W * H * 4)
        for (i, t) in tiles.enumerated() {
            let ox = (i % cols) * T, oy = (i / cols) * T
            for y in 0..<T { for x in 0..<(T * 4) { all[((oy + y) * W + ox) * 4 + x] = t[y * T * 4 + x] } }
        }
        LockImage(w: W, h: H, bgra: all).png(to: URL(fileURLWithPath: out))
    }
}
