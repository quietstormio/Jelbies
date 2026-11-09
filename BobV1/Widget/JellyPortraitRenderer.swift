//
//  JellyPortraitRenderer.swift
//  A small portrait of a Jelly for the widget, drawn by the REAL Metal renderer (MelonRenderer in game mode: the living room, the locked
//  base body, skinned face and arms) offscreen, including his current dirt / sparkle look. This is the in-app twin of the capture tests' GfxLabScene path: a headless
//  soft body stood up by the game brain for a second, one frame to a texture, PNG out.
//
//  It builds its own rig (so the live stage is never touched) via `make` (off-main body, sliced walk); WidgetBridge caches it and frees it on a memory warning.
//  Metal work is only allowed while the app is in the foreground, so callers render while active / inactive and treat a failed
//  command buffer as "try again later" (`render` returns nil).
//

import Foundation
import Metal
import simd
import UIKit
import ImageIO

@MainActor
final class JellyPortraitRenderer {
    static let simMesh = buildSimMesh()
    static let renderMesh = buildRenderMesh()

    /// Square portrait size in pixels (the widget shows it at most ~170 pt, so 360 px is ~2x on the largest tile).
    let size: Int
    private let sim: SoftBody
    private let skinner: Skinner
    private let brain: BlobBrain
    private let ren: MelonRenderer
    private let target: MTLTexture

    private init(size: Int, sim: SoftBody, skinner: Skinner, brain: BlobBrain, ren: MelonRenderer, target: MTLTexture) {
        self.size = size; self.sim = sim; self.skinner = skinner; self.brain = brain; self.ren = ren; self.target = target
    }

    /// The sim + skinner, built and settled off the main thread (both are `nonisolated`; the meshes come from the process-wide `BobMeshCache`).
    private nonisolated final class Rig: @unchecked Sendable {
        let sim: SoftBody, skinner: Skinner
        init() {
            let sm = BobMeshCache.sim, rm = BobMeshCache.render
            skinner = Skinner(simTets: sm.tets, embedding: BobMeshCache.embedding, vertexCount: rm.vertexCount,
                              eyes: buildEyeRig(render: rm, sim: sm), antennae: buildAntennaRig(render: rm, sim: sm))
            skinner.autoBlink = false
            skinner.configureTail(rm)
            sim = SoftBody(mesh: sm, firmness: 0.95)
            sim.reset(drop: 0.35)
            for _ in 0..<300 { sim.step() }
        }
    }

    /// Builds a portrait rig without a long stall of the main thread: the body is built and dropped off-main, the walk to the front spot (the brain is
    /// main-actor) runs in short slices that yield in between. Returns nil when the GPU is unavailable, the task is cancelled or `deadline` passes.
    static func make(size: Int = 360, deadline: ContinuousClock.Instant? = nil) async -> JellyPortraitRenderer? {
        let rig = await Task.detached(priority: .utility) { Rig() }.value
        let sim = rig.sim, skinner = rig.skinner
        guard !Task.isCancelled else { return nil }
        let rm = renderMesh
        let brain = BlobBrain.forGame()
        brain.autonomy = false
        brain.attach(renderMesh: rm, synchronous: true)
        guard let device = MTLCreateSystemDefaultDevice(),
              let r = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: sim.edges, particleCount: sim.n, game: true),
              r.room != nil
        else { return nil }
        r.resize(width: size, height: size)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let t = device.makeTexture(descriptor: td) else { return nil }
        // walk to the front (call) spot, face the camera and settle: the same spot the focus close-up frames
        brain.request(.goTo(GameCamera.callSpot))
        var left = 60 * 5 + 30
        while left > 0 {
            for _ in 0..<min(15, left) { brain.tick(sim: sim, skinner: skinner, dt: sim.stepDt, touched: false); sim.step() }
            left -= 15
            await Task.yield()
            if Task.isCancelled || deadline.map({ ContinuousClock.now >= $0 }) == true { return nil }
        }
        return JellyPortraitRenderer(size: size, sim: sim, skinner: skinner, brain: brain, ren: r, target: t)
    }

    nonisolated deinit {}

    /// The bath look of a Jelly with this much dirt / sparkle (what the room shows: soot seeded from dirt, the shine from sparkle).
    static func look(dirt: Float, sparkle: Float) -> BathLook {
        var l = BathLook()
        l.dirt = dirt
        l.soot = BathLook.sootSeed(dirt: dirt)
        l.sparkle = sparkle
        return l
    }

    /// The focus-mode close-up pose (GameCamera.focusPose, aspect 1) pulled back a little so his arms fit, turned 0.25 rad for a 3/4 look.
    /// Built here rather than via `GameCamera.camera`, which also writes the stage's shared `GameCamera.aspect`.
    private func camera() -> CameraState {
        let pose = GameCamera.focusPose(aspect: 1)
        let t = pose.target
        let back = (pose.eye - t) * 1.18
        let az: Float = 0.25
        let eye = t + SIMD3<Float>(back.x * cosf(az) + back.z * sinf(az), back.y, -back.x * sinf(az) + back.z * cosf(az))
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: t, up: SIMD3(0, 1, 0))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: 1, near: 0.3, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye
        cam.fwd = simd_normalize(t - eye)
        return cam
    }

    /// BGRA pixels of one portrait, or nil if the GPU refused (backgrounded) or failed.
    func render(palette pal: Palette, look: BathLook, frames: Int = 2) -> [UInt8]? {
        ren.bathLook = look
        ren.roomCacheEnabled = false
        let cam = camera()
        let light = GameCamera.light(centroid: sim.centroid())
        var ok = true
        for _ in 0..<max(frames, 1) {
            ren.beginFrame()
            skinner.update(x: sim.x, index: Self.renderMesh.index, into: ren.dynPointer)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0; fp.time = 3.7
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(size), Float(size)))
            guard let cmd = ren.queue.makeCommandBuffer() else { return nil }
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            if cmd.status != .completed { ok = false }
        }
        guard ok else { return nil }
        var px = [UInt8](repeating: 0, count: size * size * 4)
        px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0) }
        return px
    }

    /// PNG-encodes BGRA pixels (opaque) to `url`, atomically.
    nonisolated static func writePNG(bgra: [UInt8], size: Int, to url: URL) -> Bool {
        var data = bgra
        let ctx = data.withUnsafeMutableBytes { p in
            CGContext(data: p.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        }
        guard let cg = ctx?.makeImage() else { return false }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return false }
        return (try? (out as Data).write(to: url, options: .atomic)) != nil
    }
}
