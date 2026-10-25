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

    // MARK: three Jelbies in a room

    /// Pip (spines), Moss (daisy) and Lavender (wings) at the spawn spots of `RoomLayout.current`, noon or `hour`.
    func threeShot(w: Int, h: Int, hour: Double) throws -> LockImage {
        guard let _ = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let a = Float(w) / Float(h)
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: a); GameCamera.refreshRoam(aspect: a)
        let ids = [1, 2, 3]
        let lab = SocialTests.Lab(n: 3, positions: JellyRoster.spawnSpots(count: 3), quiet: true, seed: 5)
        SocialTests.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            r.skinner.autoBlink = false; r.brain.feature = JellyRoster.feature(ids[k])
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim); r.brain.idleState.goalYaw = r.faceYaw; r.brain.idleState.hold = 0.01
        }
        WearBody.install(MotionRig.renderMesh)
        for _ in 0..<90 { lab.tick(watching: false) }
        let (ren, target) = try makeRenderer(MTLCreateSystemDefaultDevice()!, lab.rigs[0], w: w, h: h)
        var feats: [FeatureSet] = []
        for (k, r) in lab.rigs.enumerated() {
            let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f); feats.append(f)
            for _ in 0..<3 { f.tick(id: 0, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(ids[k]), worn: [], hideAll: false, dt: 1.0 / 60) }
        }
        let cam = GameCamera.camera(aspect: a, focus: 0)
        ren.dayHourOverride = hour
        func shot(only: Int?) -> LockImage {
            let k = only ?? 0
            let light = GameCamera.light(centroids: lab.rigs.map { $0.sim.centroid() })
            ren.beginFrame()
            let r = lab.rigs[k]
            r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            if only == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
            if only != nil {
                var sk = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &sk)
                let ff = sk.withUnsafeBufferPointer { p in feats[k].frame { _ in p.baseAddress } }
                ren.room!.setWear(opaque: ff, translucent: RoomMesh(), bounds: [])
            } else { ren.room!.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []) }
            ren.setMouth(0, body: 0)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = JellyRoster.palette(ids[k]) ?? PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(w), Float(h)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: w * h * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
            return LockImage(w: w, h: h, bgra: px)
        }
        _ = shot(only: nil)
        let empty = shot(only: nil)
        var out = empty
        for k in (0..<3).sorted(by: { lab.rigs[$0].sim.centroid().z < lab.rigs[$1].sim.centroid().z }) {
            let b = shot(only: k)
            for p in 0..<(w * h) {
                var dd = 0
                for c in 0..<3 { dd = max(dd, abs(Int(b.bgra[4 * p + c]) - Int(empty.bgra[4 * p + c]))) }
                if dd > 3 { for c in 0..<4 { out.bgra[4 * p + c] = b.bgra[4 * p + c] } }
            }
        }
        return out
    }

    func labelled(_ img: LockImage, _ text: String) -> UIImage {
        let bar = max(img.h / 40, 28)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: img.w, height: img.h + bar), format: fmt).image { _ in
            UIColor(white: 0.08, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: img.w, height: img.h + bar))
            (text as NSString).draw(at: CGPoint(x: 10, y: CGFloat(bar) * 0.2), withAttributes: [.font: UIFont.boldSystemFont(ofSize: CGFloat(bar) * 0.6), .foregroundColor: UIColor.white])
            img.uiImage()?.draw(in: CGRect(x: 0, y: CGFloat(bar), width: CGFloat(img.w), height: CGFloat(img.h)))
        }
    }

    /// Loft and cabin (and home): portrait + landscape at noon, portrait at 21:30, with Pip, Moss and Lavender.
    func testCaptureRooms() throws {
        guard let dir else { throw XCTSkip("ROOMS_CAP_DIR not set") }
        let only = ProcessInfo.processInfo.environment["ROOMS_CAP_ONLY"].map { $0.split(separator: ",").map(String.init) }
        defer { RoomLayout.apply(RoomCatalog.home) }
        for d in RoomCatalog.all where only == nil || only!.contains(d.id.rawValue) {
            RoomLayout.apply(d)
            for (label, w, h, hour) in [("portrait", 603 * 2, 1311 * 2, 12.0), ("landscape", 1311 * 2, 603 * 2, 12.0), ("night", 603 * 2, 1311 * 2, 21.5)] {
                DayClock.shared.forcedHour = hour
                let img = try threeShot(w: w, h: h, hour: hour)
                let png = labelled(img, "\(d.title): \(label) (Pip, Moss, Lavender)").pngData()!
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try png.write(to: URL(fileURLWithPath: "\(dir)/room_\(d.id.rawValue)_\(label).png"))
            }
        }
    }

    /// An empty room at noon, square 512: the Shop / picker thumbnail.
    func testRenderRoomThumbs() throws {
        guard dir != nil else { throw XCTSkip("ROOMS_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        defer { RoomLayout.apply(RoomCatalog.home) }
        let rig = MotionRig(game: true); Self.keep.append(rig); rig.renderSamples = false
        DayClock.shared.forcedHour = 12
        for d in RoomCatalog.all {
            RoomLayout.apply(d)
            let a: Float = 1
            GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: a)
            let (ren, target) = try makeRenderer(device, rig, w: 512, h: 512)
            let img = emptyRoom(ren, target, rig: rig, w: 512, h: 512, aspect: a, hour: 12)
            try saveRaw(img, "room_thumb_\(d.id.rawValue)")
        }
    }

    /// The park's empty scenery at noon, portrait + landscape, on the park camera (capture aid, scenery review).
    func testCaptureParkScenery() throws {
        guard let dir else { throw XCTSkip("ROOMS_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        defer { RoomLayout.apply(RoomCatalog.home) }
        let rig = MotionRig(game: true); Self.keep.append(rig); rig.renderSamples = false
        DayClock.shared.forcedHour = 12
        RoomLayout.apply(RoomCatalog.park)
        for (label, w, h) in [("portrait", 1206, 2622), ("landscape", 2622, 1206)] {
            let a = Float(w) / Float(h)
            GameCamera.configurePark(); _ = GameCamera.camera(aspect: a)
            let (ren, target) = try makeRenderer(device, rig, w: w, h: h)
            let img = emptyRoom(ren, target, rig: rig, w: w, h: h, aspect: a, hour: 12)
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try img.uiImage()?.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/park_\(label).png"))
        }
    }
}
