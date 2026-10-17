//
//  GfxLabScene.swift
//  Shared harness for the render-cost tests: a game-screen MelonRenderer (room + Bob) fed by a headless MotionRig, rendered offscreen at a
//  chosen size. The same frame can be drawn twice in-process (old path vs room cache) for an exact pixel diff.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class GfxLabScene {
    let W: Int, H: Int
    let rig: MotionRig
    let ren: MelonRenderer
    let target: MTLTexture
    let dining = DiningSet()

    init?(width: Int = 603, height: Int = 1311) {
        W = width; H = height
        rig = MotionRig(game: true)
        rig.skinner.autoBlink = false
        guard let device = MTLCreateSystemDefaultDevice(),
              let r = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: rig.sim.edges, particleCount: rig.sim.n, game: true),
              r.room != nil
        else { return nil }
        ren = r
        ren.resize(width: width, height: height)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        target = device.makeTexture(descriptor: td)!
    }

    deinit { MainActor.assumeIsolated { dining.reset() } }

    /// Walks Bob to `p` (floor xz) and lets him settle.
    func place(_ p: SIMD2<Float>, seconds: Float = 5) {
        rig.brain.request(.goTo(p))
        rig.run(seconds)
        rig.run(0.5)
    }

    /// Lifts / shifts every particle (a throw frozen mid-air; the soft body is not stepped afterwards).
    func shift(_ d: SIMD3<Float>) {
        for i in 0..<rig.sim.n { rig.sim.x[3 * i] += d.x; rig.sim.x[3 * i + 1] += d.y; rig.sim.x[3 * i + 2] += d.z }
    }

    func spawnTray(_ serving: Consumable = Consumables.pizza) {
        _ = dining.spawn(serving: serving, n: 1, bobAt: rig.root)
        dining.update(dt: 3)
        if let room = ren.room, let f = dining.frame(theme: room.theme) { room.setDining(f) }
    }

    func clearTray() {
        dining.despawn(); dining.update(dt: 2)
        if let room = ren.room, let f = dining.frame(theme: room.theme) { room.setDining(f) }
    }

    /// Draws the current state `frames` times (the cache needs a few identical frames to build) and returns the last image.
    @discardableResult
    func render(focus: Float = 0, cache: Bool, frames: Int = 1, scale: Float = 1) -> LockImage {
        ren.roomCacheEnabled = cache
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: focus)
        let light = GameCamera.light(centroid: rig.sim.centroid())
        var img = LockImage(w: W, h: H, bgra: [])
        for _ in 0..<max(frames, 1) {
            ren.beginFrame()
            rig.skinner.update(x: rig.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = PaletteKey.allCases.first!.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
        }
        var px = [UInt8](repeating: 0, count: W * H * 4)
        px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
        img.bgra = px
        return img
    }
}

nonisolated struct GfxDiff {
    var maxLevel = 0
    var differing = 0           // pixels with any channel differing
    var over2 = 0               // pixels with any channel differing by more than 2/255
    var total = 0
    init(_ a: LockImage, _ b: LockImage) {
        total = a.w * a.h
        for p in 0..<total {
            var m = 0
            for c in 0..<3 { m = max(m, abs(Int(a.bgra[4 * p + c]) - Int(b.bgra[4 * p + c]))) }
            if m > 0 { differing += 1; if where_.count < 16 { where_.append((p % a.w, p / a.w)) } }
            if m > 2 { over2 += 1 }
            maxLevel = max(maxLevel, m)
        }
    }
    var where_: [(Int, Int)] = []
    var summary: String { "max \(maxLevel)/255, \(differing) of \(total) px differ, \(over2) by more than 2" }
}
