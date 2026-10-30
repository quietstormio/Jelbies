//
//  FocusAnyCaptureTests.swift
//  Not a regression test: renders "Pip, come here" and "Everyone, come here" offscreen at the true phone aspect, labelled.
//  Output: scratchpad/B1/ (override with FOCUSANY_OUT).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class FocusAnyCaptureTests: XCTestCase {
    static let outPath = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/B1"

    func testCaptureCloseUps() throws {
        let dir = ProcessInfo.processInfo.environment["FOCUSANY_OUT"] ?? Self.outPath
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let W = 603, H = 1311
        var panels: [(String, LockImage)] = []
        for (label, everyone) in [("comeHere(jelly:1)", false), ("comeHereEveryone", true)] {
            let r = FocusAnyRun(); FocusAnyJellyTests.keep.append(r)
            r.run(1.5)
            if everyone { r.care.comeHereEveryone() } else { r.care.comeHere(jelly: 1) }
            XCTAssertTrue(r.run(40) { r.care.focus.isFocused })
            r.run(2.5)
            guard let device = MTLCreateSystemDefaultDevice(),
                  let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: r.rm, simEdges: r.actors[0].sim.edges, particleCount: r.actors[0].sim.n, game: true, bodyCount: 3),
                  ren.room != nil else { throw XCTSkip("no Metal") }
            ren.resize(width: W, height: H)
            ren.roomCacheEnabled = false
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            let target = device.makeTexture(descriptor: td)!
            let aspect = Float(W) / Float(H)
            let blend = r.care.focus.blend
            let cam = GameCamera.camera(aspect: aspect, focus: blend)
            let lit = r.actors.filter { !r.care.focusHides($0.id) }
            let light = GameCamera.light(centroids: lit.map { $0.sim.centroid() })
            for a in r.actors { if let p = JellyRoster.palette(a.id) { ren.setPalette(p, body: a.id) }; ren.setHidden(r.care.focusHides(a.id), body: a.id) }
            for _ in 0..<2 {
                ren.beginFrame()
                for a in r.actors { a.skinner.update(x: a.sim.x, index: r.rm.index, into: ren.dynPointer(body: a.id)) }
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
            let img = LockImage(w: W, h: H, bgra: px)
            img.png(to: URL(fileURLWithPath: dir).appendingPathComponent(everyone ? "everyone.png" : "pip.png"))
            panels.append((label, img))
            r.care.release(); r.run(8)
        }
        try BathCaptureTests.sheet(panels, to: URL(fileURLWithPath: dir).appendingPathComponent("closeups.png"), columns: 2, panelHeight: 900)
    }

    /// The roaming camera options side by side: the same three Jellies at the same spots (same moment), at the one-Jelly pose, A and B.
    func testCaptureRoomCamOptions() throws {
        let dir = ProcessInfo.processInfo.environment["FOCUSANY_OUT"] ?? Self.outPath
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { GameCamera.configureRoom(count: 1) }
        let W = 603, H = 1311
        var panels: [(String, LockImage)] = []
        let marks: [(String, GameCamera.RoomCam)] = [("Current", .current), ("A pulled back (x1.2)", .A), ("B higher angle (x1.15, +9 deg)", .B)]
        for (label, opt) in marks {
            GameCamera.configureRoom(count: 3, option: opt, wide: 0)
            let r = FocusAnyRun(); FocusAnyJellyTests.keep.append(r)
            r.run(1.0)
            let goals: [SIMD2<Float>] = [SIMD2(-1.0, 2.6), SIMD2(1.1, 1.0), SIMD2(0, -1.2)]
            for (k, a) in r.actors.enumerated() { a.brain?.requestNow(.goTo(goals[k])) }
            r.run(12)
            guard let device = MTLCreateSystemDefaultDevice(),
                  let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: r.rm, simEdges: r.actors[0].sim.edges, particleCount: r.actors[0].sim.n, game: true, bodyCount: 3),
                  ren.room != nil else { throw XCTSkip("no Metal") }
            ren.resize(width: W, height: H)
            ren.roomCacheEnabled = false
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            let target = device.makeTexture(descriptor: td)!
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            let light = GameCamera.light(centroids: r.actors.map { $0.sim.centroid() })
            for a in r.actors { if let p = JellyRoster.palette(a.id) { ren.setPalette(p, body: a.id) } }
            for _ in 0..<2 {
                ren.beginFrame()
                for a in r.actors { a.skinner.update(x: a.sim.x, index: r.rm.index, into: ren.dynPointer(body: a.id)) }
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
            panels.append((label, LockImage(w: W, h: H, bgra: px)))
        }
        try BathCaptureTests.sheet(panels, to: URL(fileURLWithPath: dir).appendingPathComponent("room_cam_options.png"), columns: 3, panelHeight: 900)
    }

    /// Portrait room width candidates: A (current), W1 (x1.35), W2 (x1.6); same three Jellies, same moment.
    func testCaptureRoomWide() throws {
        let dir = ProcessInfo.processInfo.environment["FOCUSANY_OUT"] ?? Self.outPath
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { GameCamera.configureRoom(count: 1) }
        let W = 603, H = 1311
        var panels: [(String, LockImage)] = []
        let marks: [(String, Int)] = [("Current (A)", 0), ("W1 (x1.35 wider)", 1), ("W2 (x1.6 wider)", 2), ("W2 + tilt", 3)]
        for (label, opt) in marks {
            GameCamera.configureRoom(count: 3, option: .A, wide: min(opt, 2)); GameCamera.roomWideLift = opt == 3 ? GameCamera.wideLift(2) : 0
            let r = FocusAnyRun(); FocusAnyJellyTests.keep.append(r)
            r.run(1.0)
            let goals: [SIMD2<Float>] = [SIMD2(-1.0, 2.6), SIMD2(1.1, 1.0), SIMD2(0, -1.2)]
            for (k, a) in r.actors.enumerated() { a.brain?.requestNow(.goTo(goals[k])) }
            r.run(12)
            guard let device = MTLCreateSystemDefaultDevice(),
                  let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: r.rm, simEdges: r.actors[0].sim.edges, particleCount: r.actors[0].sim.n, game: true, bodyCount: 3),
                  ren.room != nil else { throw XCTSkip("no Metal") }
            ren.resize(width: W, height: H)
            ren.roomCacheEnabled = false
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            let target = device.makeTexture(descriptor: td)!
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            let light = GameCamera.light(centroids: r.actors.map { $0.sim.centroid() })
            for a in r.actors { if let p = JellyRoster.palette(a.id) { ren.setPalette(p, body: a.id) } }
            for _ in 0..<2 {
                ren.beginFrame()
                for a in r.actors { a.skinner.update(x: a.sim.x, index: r.rm.index, into: ren.dynPointer(body: a.id)) }
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
            panels.append((label, LockImage(w: W, h: H, bgra: px)))
        }
        try BathCaptureTests.sheet(panels, to: URL(fileURLWithPath: dir).appendingPathComponent("cam_wide.png"), columns: 4, panelHeight: 900)
    }
}
