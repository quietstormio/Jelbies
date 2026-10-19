//
//  BodyPassPerfTests.swift
//  GPU cost of the Jelly body pass at a phone-like size (1100 x 2390), per pass via the renderer's own pass timers (PerfPasses).
//  Prints "BODYPERF ..." lines. Not a regression test beyond a sanity bound.
//

import XCTest
import Metal
import simd
import QuartzCore
@testable import BobV1

@MainActor
final class BodyPassPerfTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    struct Cfg { var n: Int; var dirt: Float; var sparkle: Float; var shadow: Int?; var wet: Float = 0 }

    func measure(_ c: Cfg, W: Int = 1100, H: Int = 2390, frames: Int = 30) throws -> String {
        UserDefaults.standard.set(true, forKey: "PerfPasses")
        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let spots = JellyRoster.spawnSpots(count: c.n)
        let actors: [JellyActor] = (0..<c.n).map {
            let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
            a.reset(drop: 0.35, shift: c.n > 1)
            for _ in 0..<200 { a.sim.step() }
            a.skinner.autoBlink = false
            return a
        }
        let ren = try XCTUnwrap(MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: actors[0].sim.edges, particleCount: actors[0].sim.n, game: true, bodyCount: c.n, shadowSizeOverride: c.shadow))
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        Self.keep += actors; Self.keep.append(ren)
        for i in 1..<max(c.n, 1) { ren.setPalette(JellyRoster.palette(i) ?? PaletteKey.blue.palette, body: i) }
        for i in 0..<c.n {
            var l = BathLook(); l.dirt = c.dirt; l.soot = BathLook.sootSeed(dirt: c.dirt); l.sparkle = c.sparkle; l.wet = c.wet; l.sootStyle = Float(i)
            ren.setBathLook(l, body: i)
        }
        ren.roomCacheEnabled = false
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        var wall = 0.0, gpu = 0.0
        func run(_ k: Int) {
            for f in 0..<k {
                ren.beginFrame()
                for a in actors { a.skinner.update(x: a.sim.x, index: rm.index, into: ren.dynPointer(body: a.id)) }
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0; fp.time = 3.7 + Float(f) * 0.016
                let pal = PaletteKey.blue.palette
                fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                ren.setUniforms(camera: cam, light: GameCamera.light(centroids: actors.map { $0.sim.centroid() }), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
                let cmd = ren.queue.makeCommandBuffer()!
                let t0 = CACurrentMediaTime()
                ren.draw(to: target, commandBuffer: cmd, showMesh: false)
                let fence = ren.queue.makeCommandBuffer()!; fence.commit(); fence.waitUntilCompleted()   // PerfPasses splits the frame: wait for the whole queue
                wall += CACurrentMediaTime() - t0; gpu += cmd.gpuEndTime - cmd.gpuStartTime
            }
        }
        run(8); _ = ren.takePassStats(); wall = 0; gpu = 0
        run(frames)
        usleep(200_000)
        if c.dirt == 0.85 && c.n == 1 && c.sparkle == 0 {
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            LockImage(w: W, h: H, bgra: px).png(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/perfframe.png"))
        }
        let line = "BODYPERF n=\(c.n) dirt=\(c.dirt) sparkle=\(c.sparkle) wet=\(c.wet) shadow=\(c.shadow.map(String.init) ?? "default") pipeline=\(ren.lastBodyPipeline) wall=\(String(format: "%.2f", wall / Double(frames) * 1000))ms lastcmdgpu=\(String(format: "%.2f", gpu / Double(frames) * 1000))ms | \(ren.takePassStats())"
        print(line); NSLog("%@", line)
        return line
    }

    func testBodyPass() throws {
        defer { UserDefaults.standard.removeObject(forKey: "PerfPasses") }     // do not leak the diagnostic mode into the other tests
        var out: [String] = []
        for n in [1, 3] {
            for d: Float in [0, 0.2, 0.5, 0.85] { out.append(try measure(Cfg(n: n, dirt: d, sparkle: 0, shadow: nil))) }
            out.append(try measure(Cfg(n: n, dirt: 0, sparkle: 0.8, shadow: nil)))
            out.append(try measure(Cfg(n: n, dirt: 0.85, sparkle: 0.8, shadow: nil)))
        }
        out.append(try measure(Cfg(n: 3, dirt: 0, sparkle: 0, shadow: 1024)))
        out.append(try measure(Cfg(n: 3, dirt: 0.85, sparkle: 0, shadow: 1024)))
        out.append(try measure(Cfg(n: 1, dirt: 0, sparkle: 0, shadow: 2048)))
        let path = ProcessInfo.processInfo.environment["BODYPERF_OUT"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/bodyperf.txt"
        try out.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
