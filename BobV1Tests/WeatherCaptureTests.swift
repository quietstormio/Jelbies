//
//  WeatherCaptureTests.swift
//  Renders the storm with the real renderer at true phone proportion (603 x 1311), three Jelbies in the room:
//    huddle_strip.png     six frames of the huddle: the startle, the scurry, arriving, the stance, a flash flinch, the tremble afterwards
//    window_lightning.png the windows over a storm: clear, build-up, peak, a lightning flash, clearing (day and evening)
//    lightning_frame.png  one full frame at the flash
//  and a test that the cached room (the rain is applied at the cache blit) draws the same window as the uncached one.
//  Output: scratchpad/weather/. Not a regression test beyond the cache equality.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class WeatherCaptureTests: XCTestCase {
    static let dir = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/weather"
    nonisolated(unsafe) static var keep: [AnyObject] = []
    let W = 603, H = 1311

    override func setUp() { super.setUp(); RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0) }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); super.tearDown() }

    final class Shooter {
        let ren: MelonRenderer, target: MTLTexture, W: Int, H: Int
        init?(W: Int, H: Int, rigs: [MotionRig]) {
            self.W = W; self.H = H
            guard let device = MTLCreateSystemDefaultDevice(),
                  let r = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: rigs[0].sim.edges, particleCount: rigs[0].sim.n, game: true, bodyCount: rigs.count) else { return nil }
            ren = r
            r.resize(width: W, height: H)
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            target = device.makeTexture(descriptor: td)!
            for i in 1..<rigs.count { r.setPalette(JellyRoster.palette(i) ?? PaletteKey.blue.palette, body: i) }
            r.roomCacheEnabled = false
        }
        nonisolated deinit {}

        func shot(rigs: [MotionRig], hour: Double, look: WeatherLook, frames: Int = 2) -> LockImage {
            ren.dayHourOverride = hour
            ren.weatherLook = look
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            for _ in 0..<frames {
                var light = GameCamera.light(centroids: rigs.map { $0.sim.centroid() })
                light.intensity *= DayLight.at(hour: hour).jellyMul
                ren.beginFrame()
                for (i, r) in rigs.enumerated() { r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer(body: i)) }
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = look.isClear ? 1 : look.exposure(night: Float(DayBlend(hour: hour).night)); fp.meshAlpha = 0; fp.time = 3.7
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
    }

    static func strip(_ panels: [(String, LockImage)], crop: CGRect?, to url: URL, panelWidth: CGFloat) throws {
        let imgs = panels.compactMap { p -> (String, UIImage)? in
            guard var ui = p.1.uiImage() else { return nil }
            if let c = crop, let cg = ui.cgImage?.cropping(to: c) { ui = UIImage(cgImage: cg) }
            return (p.0, ui)
        }
        guard let first = imgs.first else { return }
        let ph = panelWidth * first.1.size.height / first.1.size.width, label: CGFloat = 26, pad: CGFloat = 4
        let size = CGSize(width: pad + CGFloat(imgs.count) * (panelWidth + pad), height: ph + label + 2 * pad)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            UIColor(white: 0.12, alpha: 1).setFill(); UIRectFill(CGRect(origin: .zero, size: size))
            for (i, p) in imgs.enumerated() {
                let x = pad + CGFloat(i) * (panelWidth + pad)
                p.1.draw(in: CGRect(x: x, y: label + pad, width: panelWidth, height: ph))
                (p.0 as NSString).draw(at: CGPoint(x: x + 4, y: 4), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.white])
            }
        }
        try out.pngData()!.write(to: url)
    }

    // MARK: the huddle

    func testHuddleStrip() throws {
        try FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        let book = WeatherBook(defaults: UserDefaults(suiteName: "wc-\(UUID().uuidString)")!)
        let room = WeatherTests.Room(book: book)
        for r in room.lab.rigs { r.skinner.autoBlink = false }
        Self.keep.append(room)
        guard let shooter = Shooter(W: W, H: H, rigs: room.lab.rigs) else { throw XCTSkip("no renderer") }
        Self.keep.append(shooter)
        let ev = book.begin(seed: 4, jumpTo: .peak)
        room.reactor.handle(ev, plan: book.plan, jellies: room.js, care: nil)
        let plan = book.plan!
        let first = plan.strikes.first { $0.close }!
        // the sky during the capture: the peak, with the flash of the strike when it happens
        func look() -> WeatherLook { var l = book.look(); l.rain = max(l.rain, 0.9); return l }
        var panels: [(String, LockImage)] = []
        func take(_ name: String) { panels.append((name, shooter.shot(rigs: room.lab.rigs, hour: 19, look: look()))) }
        // run to the first strike, then capture at moments of the sequence
        while book.stormTime < first.t + first.delay + 0.15 { room.step() }
        take("thunder: startle")
        room.run(1.0); take("scurry")
        room.run(1.6); take("scurry")
        var guardT = 0
        while !(0...2).allSatisfy({ room.reactor.members[$0]?.mode == .huddle }) && guardT < 60 * 20 { room.step(); guardT += 1 }
        room.run(0.6); take("huddled")
        // the next flash: capture right after it
        let next = plan.strikes.first { $0.t > book.stormTime + 0.5 }!
        while book.stormTime < next.t + 0.12 { room.step() }
        take("flash: flinch")
        room.run(1.4); take("trembling")
        XCTAssertEqual(panels.count, 6)
        try Self.strip(panels, crop: CGRect(x: 0, y: CGFloat(H) * 0.18, width: CGFloat(W), height: CGFloat(H) * 0.58), to: URL(fileURLWithPath: Self.dir + "/huddle_strip.png"), panelWidth: 300)
        for (i, p) in panels.enumerated() { p.1.png(to: URL(fileURLWithPath: Self.dir + "/huddle_\(i).png")) }
    }

    // MARK: the windows

    func testWindowLightning() throws {
        try FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        let rigs = (0..<3).map { _ in MotionRig(game: true) }
        let spots = JellyRoster.spawnSpots(count: 3)
        for (i, r) in rigs.enumerated() { r.sim.teleport(toXZ: spots[i]); for _ in 0..<90 { r.sim.step() }; r.brain.currentPose(r.sim); r.skinner.autoBlink = false }
        Self.keep += rigs
        guard let shooter = Shooter(W: W, H: H, rigs: rigs) else { throw XCTSkip("no renderer") }
        Self.keep.append(shooter)
        let states: [(String, WeatherLook)] = [
            ("clear", WeatherLook()),
            ("build-up", WeatherLook(phase: .buildUp, gloom: 0.55, rain: 0.35, flash: 0, spot: 0.5)),
            ("peak", WeatherLook(phase: .peak, gloom: 1, rain: 1, flash: 0, spot: 0.5)),
            ("flash", WeatherLook(phase: .peak, gloom: 1, rain: 1, flash: 0.8, spot: 0.3)),
            ("clearing", WeatherLook(phase: .clearing, gloom: 0.3, rain: 0.25, flash: 0, spot: 0.5)),
        ]
        let crop = CGRect(x: 0, y: CGFloat(H) * 0.05, width: CGFloat(W), height: CGFloat(H) * 0.40)
        for (hour, tag) in [(13.0, "day"), (19.0, "evening")] {
            var panels: [(String, LockImage)] = []
            for (n, l) in states { panels.append(("\(tag) \(n)", shooter.shot(rigs: rigs, hour: hour, look: l))) }
            try Self.strip(panels, crop: crop, to: URL(fileURLWithPath: Self.dir + "/window_lightning_\(tag).png"), panelWidth: 300)
            if tag == "day" { panels[3].1.png(to: URL(fileURLWithPath: Self.dir + "/lightning_frame.png")) }
            var means: [Double] = []
            for p in panels { var s = 0.0; for k in 0..<(W * H) { s += Double(p.1.bgra[4 * k]) + Double(p.1.bgra[4 * k + 1]) + Double(p.1.bgra[4 * k + 2]) }; means.append(s / Double(W * H * 3)) }
            print("WEATHER mean level \(tag): \(means.map { String(format: "%.1f", $0) })")
            XCTAssertLessThan(means[2], means[0] - (tag == "day" ? 5 : 1), "\(tag): the storm darkens the room")
            XCTAssertGreaterThan(means[3], means[2] + 3, "\(tag): the flash lights it")
        }
    }

    /// The rain and the flash are applied at the room-cache blit (the cache build marks the glass): the cached room must draw the same window as the uncached one.
    func testCachedRoomDrawsTheSameStorm() throws {
        let rigs = (0..<3).map { _ in MotionRig(game: true) }
        let spots = JellyRoster.spawnSpots(count: 3)
        for (i, r) in rigs.enumerated() { r.sim.teleport(toXZ: spots[i]); for _ in 0..<90 { r.sim.step() }; r.brain.currentPose(r.sim); r.skinner.autoBlink = false }
        Self.keep += rigs
        guard let shooter = Shooter(W: W, H: H, rigs: rigs) else { throw XCTSkip("no renderer") }
        Self.keep.append(shooter)
        for look in [WeatherLook(), WeatherLook(phase: .peak, gloom: 1, rain: 1, flash: 0.7, spot: 0.4), WeatherLook(phase: .buildUp, gloom: 0.5, rain: 0.4, flash: 0, spot: 0.5)] {
            shooter.ren.roomCacheEnabled = false
            let plain = shooter.shot(rigs: rigs, hour: 13, look: look)
            shooter.ren.roomCacheEnabled = true
            shooter.ren.invalidateRoomCache()
            let cached = shooter.shot(rigs: rigs, hour: 13, look: look, frames: 8)
            XCTAssertTrue([RoomCacheAction.use, .build].contains(shooter.ren.lastCacheAction), "the cache was in use: \(shooter.ren.lastCacheAction)")
            var big = 0, sum = 0
            for k in stride(from: 0, to: W * H * 4, by: 4) {
                var d = 0
                for c in 0..<3 { d = max(d, abs(Int(plain.bgra[k + c]) - Int(cached.bgra[k + c]))) }
                sum += d; if d > 10 { big += 1 }
            }
            let frac = Double(big) / Double(W * H)
            print("WEATHER cache vs plain (flash \(look.flash), rain \(look.rain)): mean diff \(Double(sum) / Double(W * H)), >10 levels: \(frac * 100)%")
            XCTAssertLessThan(frac, 0.004, "cached and uncached rooms differ (rain \(look.rain) flash \(look.flash))")
        }
    }
}
