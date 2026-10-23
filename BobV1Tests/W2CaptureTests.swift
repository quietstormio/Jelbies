//
//  W2CaptureTests.swift
//  Not a regression test: the liveliness round's pictures (W2). Output: scratchpad/w2/ (override with W2_OUT).
//    testRoomMinuteMontage   12 frames over 60 s of the lively room, portrait (4x3) and landscape (3x4), each labelled with the three Jellies' activities
//    testCloseUpOthersRoam   comeHere(jelly:1), then +2 / +6 / +10 s after arrival, portrait and landscape, plus a copy with the keep-out wedge outlined
//    testMovesStrip          the new moves at their peak (cartwheel mid-air, lie-down hold, shake, window look), cropped around the Jelly
//

import XCTest
import Metal
import simd
import UIKit
import SwiftUI
@testable import BobV1

@MainActor
final class W2CaptureTests: XCTestCase {
    static var dir: String { ProcessInfo.processInfo.environment["W2_OUT"] ?? LivelinessMinuteTests.outDir }
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = []; DecorField.shared.clear(); GameCamera.clearRoam(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    @MainActor final class Shot {
        let ren: MelonRenderer, target: MTLTexture, W: Int, H: Int, device: MTLDevice
        init?(_ r: FocusAnyRun, W: Int, H: Int) {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: r.rm, simEdges: r.actors[0].sim.edges, particleCount: r.actors[0].sim.n, game: true, bodyCount: 3),
                  ren.room != nil else { return nil }
            ren.resize(width: W, height: H); ren.roomCacheEnabled = false
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            self.ren = ren; self.target = device.makeTexture(descriptor: td)!; self.W = W; self.H = H; self.device = device
        }
        func frame(_ r: FocusAnyRun) -> (LockImage, CameraState) {
            let aspect = Float(W) / Float(H)
            let cam = GameCamera.camera(aspect: aspect, focus: r.care.focus.blend)
            let light = GameCamera.light(centroids: r.care.litActors(r.actors, camIn: r.care.focus.blend > 0.25).map { $0.sim.centroid() })
            for a in r.actors { if let p = JellyRoster.palette(a.id) { ren.setPalette(p, body: a.id) }; ren.setHidden(false, body: a.id) }
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
            return (LockImage(w: W, h: H, bgra: px), cam)
        }
    }

    private func lively(_ r: FocusAnyRun) {
        for a in r.actors {
            let b = a.brain!
            b.anticsEnabled = true; b.watching = true; b.autonomy = true; b.sleepEnabled = true
            b.idleState.cooldown = 4 + Float(a.id) * 3; b.restTimer = 0.5 + Float(a.id); b.socialBook.cooldown = 8
        }
    }
    private func setupRoom(_ aspect: Float) {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: aspect); GameCamera.refreshRoam(aspect: aspect)
    }
    private func project(_ cam: CameraState, _ p: SIMD3<Float>, _ W: Int, _ H: Int) -> CGPoint {
        let c = cam.viewProj * SIMD4<Float>(p.x, p.y, p.z, 1)
        return CGPoint(x: CGFloat(c.x / c.w * 0.5 + 0.5) * CGFloat(W), y: CGFloat(0.5 - c.y / c.w * 0.5) * CGFloat(H))
    }

    func testRoomMinuteMontage() throws {
        try FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        for portrait in [true, false] {
            let W = portrait ? 603 : 1311, H = portrait ? 1311 : 603
            setupRoom(Float(W) / Float(H))
            LivelyLabTests.placeToys()
            let r = FocusAnyRun(peers: true); Self.keep.append(r)
            lively(r)
            r.run(0.5)
            guard let shot = Shot(r, W: W, H: H) else { throw XCTSkip("no Metal") }
            var panels: [(String, LockImage)] = []
            for n in 1...12 {
                r.run(5)
                let (img, _) = shot.frame(r)
                let names = r.actors.map { LivelyLabTests.label($0.brain!) ?? ($0.brain!.activity == .walking ? "walking" : "standing") }
                panels.append(("t=\(n * 5)s  " + names.enumerated().map { "\($0.offset): \($0.element.replacingOccurrences(of: "idle:", with: ""))" }.joined(separator: " | "), img))
            }
            try BathCaptureTests.sheet(panels, to: URL(fileURLWithPath: Self.dir).appendingPathComponent(portrait ? "montage_60s_portrait.png" : "montage_60s_landscape.png"),
                                       columns: portrait ? 4 : 3, panelHeight: portrait ? 640 : 300)
        }
    }

    func testCloseUpOthersRoam() throws {
        try FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        for portrait in [true, false] {
            let W = portrait ? 603 : 1311, H = portrait ? 1311 : 603
            setupRoom(Float(W) / Float(H))
            let r = FocusAnyRun(peers: true); Self.keep.append(r)
            lively(r)
            r.run(1.0)
            guard let shot = Shot(r, W: W, H: H) else { throw XCTSkip("no Metal") }
            r.care.comeHere(jelly: 1)
            XCTAssertTrue(r.run(30) { r.care.focus.isFocused })
            r.run(1.5)
            var done: Float = 0
            for t in [2, 6, 10] as [Float] {
                r.run(t - done); done = t
                let (img, cam) = shot.frame(r)
                let name = "closeup_pip_\(portrait ? "portrait" : "landscape")_t\(String(format: "%02d", Int(t)))"
                img.png(to: URL(fileURLWithPath: Self.dir).appendingPathComponent(name + ".png"))
                if let ko = r.care.focusKeepOutFor(0), let ui = img.uiImage() {
                    let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
                    let out = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
                        ui.draw(at: .zero)
                        let path = UIBezierPath()
                        let zs: [Float] = [ko.backZ, ko.eyeZ - 0.5]
                        let pts = zs.map { z in (project(cam, SIMD3(ko.centreX - ko.halfWidth(at: z, radius: 0.55), 0.02, z), W, H), project(cam, SIMD3(ko.centreX + ko.halfWidth(at: z, radius: 0.55), 0.02, z), W, H)) }
                        path.move(to: pts[0].0); path.addLine(to: pts[1].0); path.addLine(to: pts[1].1); path.addLine(to: pts[0].1); path.close()
                        UIColor.red.withAlphaComponent(0.9).setStroke(); path.lineWidth = 4; path.stroke()
                        UIColor.red.withAlphaComponent(0.12).setFill(); path.fill()
                    }
                    try out.pngData()?.write(to: URL(fileURLWithPath: Self.dir).appendingPathComponent(name + "_wedge.png"))
                }
            }
            r.care.release(); r.run(6)
        }
    }

    func testMovesStrip() throws {
        try FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        setupRoom(440.0 / 956.0)
        let W = 905, H = 1967
        let r = FocusAnyRun(); Self.keep.append(r)
        r.run(1.0)
        guard let shot = Shot(r, W: W, H: H) else { throw XCTSkip("no Metal") }
        let a = r.actors[0], b = a.brain!
        b.idleForced = true
        func crop(_ img: LockImage, _ cam: CameraState) -> LockImage {
            let c = a.sim.centroid()
            let p = project(cam, c, W, H)
            let half = 230
            let x0 = max(0, min(W - 2 * half, Int(p.x) - half)), y0 = max(0, min(H - 2 * half, Int(p.y) - half))
            var out = [UInt8](repeating: 0, count: 4 * 2 * half * 2 * half)
            for y in 0..<(2 * half) { for x in 0..<(2 * half) { for ch in 0..<4 { out[4 * (y * 2 * half + x) + ch] = img.bgra[4 * ((y0 + y) * W + (x0 + x)) + ch] } } }
            return LockImage(w: 2 * half, h: 2 * half, bgra: out)
        }
        var panels: [(String, LockImage)] = []
        func snap(_ label: String) { let (img, cam) = shot.frame(r); panels.append((label, crop(img, cam))) }
        // cartwheel: three frames through the air
        r.place(0, at: SIMD2(0, 0.6))
        b.idleReset(a.skinner); b.restTimer = 1e6
        XCTAssertTrue(b.idleStart(.cartwheel, a.sim))
        var shots = 0
        for _ in 0..<(8 * 60) {
            r.tick()
            if b.gait.phase == .air, shots < 3, Int(b.gait.flipU * 6) == [1, 3, 5][shots] { snap("cartwheel u=\(String(format: "%.2f", b.gait.flipU))"); shots += 1 }
            if b.idleState.kind == nil && r.actors[0].sim.stepDt > 0 && shots >= 3 { break }
        }
        r.run(1.5)
        // lie down hold
        b.idleReset(a.skinner)
        XCTAssertTrue(b.idleStart(.lieDown, a.sim))
        for _ in 0..<(8 * 60) { r.tick(); if b.idleState.kind == .lieDown, b.idleState.phase == 2, b.idleState.phaseT > 1.0 { break } }
        snap("lie down (hold)")
        r.run(8)
        // shake peak
        b.idleReset(a.skinner)
        XCTAssertTrue(b.idleStart(.shake, a.sim))
        for _ in 0..<(3 * 60) { r.tick(); if b.idleState.kind == .shake, b.idleState.phaseT > 0.55 { break } }
        snap("shake (peak)")
        r.run(3)
        // window look
        b.idleReset(a.skinner)
        XCTAssertTrue(b.idleStart(.window, a.sim))
        for _ in 0..<(20 * 60) { r.tick(); if b.idleState.kind == .window, b.idleState.phase == 1, b.idleState.phaseT > 1.0 { break } }
        snap("window look")
        try BathCaptureTests.sheet(panels, to: URL(fileURLWithPath: Self.dir).appendingPathComponent("moves_strip.png"), columns: panels.count, panelHeight: 460)
    }

    /// The trick book of the training close-up (Pip, slot 1): its title must read "Pip's tricks" and show Pip's own book and the one name row, in portrait and on a phone on its side.
    func testTrickBookInTheTrainingCloseUp() throws {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        var now: Double = 100
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "W2CaptureTests")!, persists: false, random: { 0 })
        let voice = VoiceCoordinator(training: training, input: FakeSpeechInput(), now: { now })
        let r = FocusAnyRun(voice: voice)
        Self.keep.append(r)
        r.care.jelly(1)!.training.debugReps(.jacks, word: "boing", reps: 2)
        r.run(1.0)
        r.care.beginTraining(1)
        XCTAssertTrue(r.run(30) { r.care.focus.isFocused })
        r.run(0.5)
        XCTAssertTrue(r.care.isTrainingCloseUp)
        XCTAssertEqual(r.care.voice.subjectID, 1)
        XCTAssertEqual(r.care.voice.book.names.displayName(1), "Pip", "the title reads \"Pip's tricks\"")
        try FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        // (ImageRenderer leaves a ScrollView empty: host the view in a real window and snapshot that)
        func render(_ size: CGSize, _ name: String, compact: Bool) throws {
            let host = UIHostingController(rootView: VoiceTrickBook(voice: r.care.voice) {}.environment(\.colorScheme, .light))
            if compact { host.traitOverrides.verticalSizeClass = .compact }
            let win = UIWindow(frame: CGRect(origin: .zero, size: size))
            win.rootViewController = host
            win.makeKeyAndVisible()
            host.view.frame = win.bounds
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            host.view.layoutIfNeeded()
            let img = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) }
            try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: "\(Self.dir)/\(name).png"))
            win.isHidden = true
        }
        try render(CGSize(width: 440, height: 956), "trickbook_portrait_render", compact: false)
        try render(CGSize(width: 932, height: 430), "trickbook_landscape", compact: true)
    }
}
