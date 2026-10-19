//
//  DayNightCaptureTests.swift
//  The room with three Jellies at true phone proportion (603 x 1311) at -ClockHour 8, 13, 19 and 23: one PNG each plus a labelled 2x2 sheet.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class DayNightCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let dir = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad"

    func testRoomAtFourHours() throws {
        let W = 603, H = 1311
        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let spots = JellyRoster.spawnSpots(count: 3)
        let actors: [JellyActor] = (0..<3).map {
            let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
            a.reset(drop: 0.35, shift: false)
            for _ in 0..<300 { a.sim.step() }
            a.skinner.autoBlink = false
            return a
        }
        let ren = try XCTUnwrap(MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: actors[0].sim.edges, particleCount: actors[0].sim.n, game: true, bodyCount: 3))
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        Self.keep += actors; Self.keep.append(ren)
        for i in 1..<3 { ren.setPalette(JellyRoster.palette(i) ?? PaletteKey.blue.palette, body: i) }
        for (i, a) in actors.enumerated() { a.sim.teleport(toXZ: spots[i]); for _ in 0..<90 { a.sim.step() } }
        let aspect = Float(W) / Float(H)
        let cam = GameCamera.camera(aspect: aspect, focus: 0)

        func frame(hour: Double) -> LockImage {
            ren.roomCacheEnabled = false
            ren.dayHourOverride = hour
            for i in 0..<3 { ren.setHidden(false, body: i) }
            var light = GameCamera.light(centroids: actors.map { $0.sim.centroid() })
            light.intensity *= DayLight.at(hour: hour).jellyMul
            for _ in 0..<2 {
                ren.beginFrame()
                for a in actors { a.skinner.update(x: a.sim.x, index: rm.index, into: ren.dynPointer(body: a.id)) }
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0; fp.time = 3.7
                let pal = PaletteKey.blue.palette
                fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
                let cmd = ren.queue.makeCommandBuffer()!
                ren.draw(to: target, commandBuffer: cmd, showMesh: false)
                cmd.waitUntilCompleted()
            }
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            return LockImage(w: W, h: H, bgra: px)
        }
        var panels: [(String, LockImage)] = []
        for (h, name) in [(8, "morning"), (13, "day"), (19, "evening"), (23, "night")] {
            let img = frame(hour: Double(h))
            img.png(to: URL(fileURLWithPath: Self.dir + String(format: "/daynight_%02d.png", h)))
            panels.append((String(format: "%02d:00  %@", h, name), img))
            var lum = 0.0
            for p in 0..<(W * H) { lum += Double(img.bgra[4 * p]) + Double(img.bgra[4 * p + 1]) + Double(img.bgra[4 * p + 2]) }
            NSLog("DAYNIGHT hour %d mean level %.1f", h, lum / Double(W * H * 3))
        }
        try BathJellyTests.sheet(panels, to: URL(fileURLWithPath: Self.dir + "/daynight_sheet.png"), columns: 2, panelHeight: 900)
    }
}
