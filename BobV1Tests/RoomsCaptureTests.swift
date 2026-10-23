//
//  RoomsCaptureTests.swift
//  Not a regression test: renders the rooms with the REAL renderer when ROOMS_CAP_DIR is set (TEST_RUNNER_ROOMS_CAP_DIR).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class RoomsCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var dir: String? { ProcessInfo.processInfo.environment["ROOMS_CAP_DIR"].flatMap { $0.isEmpty ? nil : $0 } }

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0); DecorField.shared.clear() }
    override func tearDown() { DecorField.shared.clear(); DayClock.shared.forcedHour = 12; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    func makeRenderer(_ device: MTLDevice, _ rig: MotionRig, w: Int, h: Int) throws -> (MelonRenderer, MTLTexture) {
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: rig.sim.edges, particleCount: rig.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: w, height: h)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        return (ren, device.makeTexture(descriptor: td)!)
    }

    /// One frame of the room with every body pushed out of view (room only).
    func emptyRoom(_ ren: MelonRenderer, _ target: MTLTexture, rig: MotionRig, w: Int, h: Int, aspect: Float, hour: Double?) -> LockImage {
        let cam = GameCamera.camera(aspect: aspect, focus: 0)
        let light = GameCamera.light(centroids: [rig.sim.centroid()])
        ren.dayHourOverride = hour
        var out = LockImage(w: w, h: h, bgra: [])
        for _ in 0..<2 {
            ren.beginFrame()
            rig.skinner.update(x: rig.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(w), Float(h)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: w * h * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
            out = LockImage(w: w, h: h, bgra: px)
        }
        return out
    }

    func saveRaw(_ img: LockImage, _ name: String) throws {
        guard let dir else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        img.png(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
        try Data(img.bgra).write(to: URL(fileURLWithPath: dir + "/" + name + ".raw"))
    }

    /// Home, empty, noon, portrait + landscape. ROOMS_CAP_TAG=before|after; "after" also writes home_diff.txt against the saved "before".
    func testCaptureHomeBaseline() throws {
        guard dir != nil else { throw XCTSkip("ROOMS_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let tag = ProcessInfo.processInfo.environment["ROOMS_CAP_TAG"] ?? "before"
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.renderSamples = false
        DayClock.shared.forcedHour = 12
        var report = ""
        for (label, W, H) in [("portrait", 1206, 2622), ("landscape", 2622, 1206)] {
            let a = Float(W) / Float(H)
            GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: a); GameCamera.refreshRoam(aspect: a)
            let (ren, target) = try makeRenderer(device, rig, w: W, h: H)
            let img = emptyRoom(ren, target, rig: rig, w: W, h: H, aspect: a, hour: 12)
            try saveRaw(img, "home_\(tag)_\(label)")
            if tag == "after", let dir, let d = FileManager.default.contents(atPath: dir + "/home_before_\(label).raw") {
                var maxD = 0, n = 0
                let before = [UInt8](d)
                XCTAssertEqual(before.count, img.bgra.count)
                for p in 0..<(W * H) {
                    var dd = 0
                    for c in 0..<3 { dd = max(dd, abs(Int(before[4 * p + c]) - Int(img.bgra[4 * p + c]))) }
                    maxD = max(maxD, dd); if dd > 2 { n += 1 }
                }
                report += "\(label): max per-channel delta \(maxD), pixels with delta > 2: \(n)\n"
                XCTAssertEqual(n, 0, "\(label): home must not change")
            }
        }
        if !report.isEmpty { try report.write(toFile: dir! + "/home_diff.txt", atomically: true, encoding: .utf8) }
    }
}
