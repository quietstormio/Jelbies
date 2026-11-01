//
//  FeetSourceTests.swift
//  2026-11-01: the brain must place the foot pieces where the skin's leash never has to move them (sit, sway, decor seats, slide, kick, run).
//
import XCTest
import simd
import Metal
@testable import BobV1

@MainActor
final class FeetSourceTests: XCTestCase {
    static let out = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/feetsrc/"
    static let moves = ["idle sit", "idle sway", "idle decorSit", "idle decorSlide", "idle decorKick", "idle run", "idle zoomies", "walk", "idle jacks", "hop", "idle lieDown", "idle slump", "idle flop"]

    func testLeashNeverFiresInSourceMoves() throws {
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0; defer { ToyTuning.settle = 5; DecorField.shared.clear() }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        let only = (ProcessInfo.processInfo.environment["FEETSRC_ONLY"] ?? "").split(separator: ",").map(String.init)
        let jobs = OnePieceInvariantTests.jobs().filter { j in Self.moves.contains(j.name) && (only.isEmpty || only.contains(j.name)) }
        var report = "move | char shoes | frames bean | leashed maxpull(cm)\n"
        var bad = 0
        for job in jobs {
            for c in job.chars where (ProcessInfo.processInfo.environment["FEETSRC_CHAR"].map { Int($0) == c } ?? true) {
                for shoes in (ProcessInfo.processInfo.environment["FEETSRC_CHAR"] != nil ? [false] : [false, true]) {
                    var worstInfo = "", worstPull: Float = 0
                    let a = OnePieceInvariantTests.run(job.sc, char: c, shoes: shoes, pacing: .hz60, seed: 3) { frame, r, f in
                        let pull = max(f.leash, f.weldPull)
                        if pull > 0.002, pull > worstPull {
                            worstPull = pull
                            let pose = r.sim.bodyPose(iterations: 3)
                            var s = String(format: "  worst f%d tilt %.2f body y %.3f leash %.3f pre %.3f/%.3f disagree dc %.3f ang %.2f script %@ idle %@", frame, pose.tilt, pose.centroid.y, f.leash, r.skinner.leashPre[0], r.skinner.leashPre[1], r.skinner.frameDisagree.0, r.skinner.frameDisagree.1, r.brain.scriptKindName, "\(r.brain.idleState.kind.map { "\($0)" } ?? "-")")
                            for k in 0..<2 {
                                let b = r.skinner.beanPos[k]
                                let fp = (centroid: pose.centroid, rotation: pose.rotation, restCentroid: r.sim.restCentroid)
                                let pole = b[FootBean.vertexCount - 1]
                                let rel = pose.rotation.inverse.act(pole - pose.centroid)
                                var near = b[0]; var nd = Float.infinity
                                for v in b { let d = simd_length_squared(v - pose.centroid); if d < nd { nd = d; near = v } }
                                s += String(format: " | foot%d lowY %.3f topY %.3f poleDepth %.3f nearDepth %.3f poleRel(%.2f %.2f %.2f) hipDist %.3f brainTop %.3f fit %@", k, (b.map(\.y).min() ?? 0) - r.sim.floorY, (b.map(\.y).max() ?? 0) - r.sim.floorY, Skinner.fittedDepth(pole, fp).0, Skinner.fittedDepth(near, fp).0, rel.x, rel.y, rel.z, r.skinner.weldDist[k], BlobBrain.topDepth(b, pose: fp).0, r.brain.beanFitUsed == nil ? "att" : "fit")
                            }
                            worstInfo = s
                        }
                    }
                    guard a.started else { continue }
                    report += String(format: "%@ | %@ %@ | %d %d | %d %.1f\n", job.name, OnePieceInvariantTests.characters[c].0, shoes ? "shoes" : "bare", a.frames, a.beanFrames, a.leashed, a.leashMax * 100)
                    if a.leashed > 0 { report += worstInfo + "\n" }
                    bad += a.leashed
                }
            }
        }
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? report.write(toFile: Self.out + "leash.txt", atomically: true, encoding: .utf8)
        print(report)
        XCTAssertEqual(bad, 0, "the skin's leash had to move a foot piece: fix the placement (BlobBrain.attachBean / driveLimbs)")
    }

    /// Not a regression test: 6-frame strips of the four moves the user's phone showed (env FEETSRC_STRIP=before|after names the files; skipped otherwise).
    func testStrips() throws {
        guard let tag = ProcessInfo.processInfo.environment["FEETSRC_STRIP"] else { throw XCTSkip("FEETSRC_STRIP not set") }
        _ = OnePieceInvariantTests.configured
        BlobBrain.topDepthFix = tag != "before"; Skinner.frameDisagreeDist = tag == "before" ? 0.06 : 0.12; Skinner.frameDisagreeAngle = tag == "before" ? 0.2 : 0.35
        defer { BlobBrain.topDepthFix = true; Skinner.frameDisagreeDist = 0.12; Skinner.frameDisagreeAngle = 0.35 }
        ToyTuning.settle = 0; defer { ToyTuning.settle = 5; DecorField.shared.clear() }
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let T = 420
        let probe = MotionRig(game: true)
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: probe.sim.edges, particleCount: probe.sim.n) else { throw XCTSkip("no Metal") }
        ren.resize(width: T, height: T)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: T, height: T, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        var rig = CameraRig()
        // (name, job, character, shoes, frames)
        let cases: [(String, String, Int, Bool, [Int])] = [
            ("teddy_decorSit", "idle decorSit", 4, false, [560, 620, 650, 670, 690, 720]),
            ("pip_shoes_sit", "idle sit", 1, true, [30, 50, 62, 80, 120, 200]),
            ("bob_decorSlide", "idle decorSlide", 0, false, [440, 480, 500, 517, 540, 580]),
            ("pip_shoes_sway", "idle sway", 1, true, [60, 120, 180, 240, 300, 360]),
            ("teddy_jacks", "idle jacks", 4, false, [70, 85, 100, 115, 130, 145]),
            ("teddy_hopPlay", "hop", 4, false, [30, 45, 60, 75, 90, 105]),
        ]
        let jobs = OnePieceInvariantTests.jobs()
        for (name, jobName, ch, shoes, frames) in cases {
            guard let job = jobs.first(where: { $0.name == jobName }) else { XCTFail("no job \(jobName)"); continue }
            var tiles: [[UInt8]] = []
            _ = OnePieceInvariantTests.run(job.sc, char: ch, shoes: shoes, pacing: .hz60, seed: 3) { frame, r, _ in
                guard frames.contains(frame) else { return }
                let c = r.sim.centroid()
                let tgt = SIMD3<Float>(c.x, 0.45, c.z)
                let az: Float = 0.65, el: Float = 0.22, dist: Float = 5.2
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
            XCTAssertEqual(tiles.count, frames.count, name)
            let cols = 3, rows = (tiles.count + cols - 1) / cols
            let W = T * cols, H = T * rows
            var all = [UInt8](repeating: 255, count: W * H * 4)
            for (i, t) in tiles.enumerated() {
                let ox = (i % cols) * T, oy = (i / cols) * T
                for y in 0..<T { for x in 0..<(T * 4) { all[((oy + y) * W + ox) * 4 + x] = t[y * T * 4 + x] } }
            }
            try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
            LockImage(w: W, h: H, bgra: all).png(to: URL(fileURLWithPath: Self.out + "\(name)_\(tag).png"))
        }
    }

    /// Phone r1052: at every scene change (room <-> park) all actors logged pole-to-hip 63-106 cm for a frame or more: the body root was teleported, the foot pieces were not. Teleport a walking / idling body 5 m
    /// (what `SoftBody.teleport` does for every scene entry path) and the very next skinned frame must have both pieces within the tether bound of the hip, with or without a brain tick in between.
    func testTeleportCarriesTheFeet() throws {
        _ = OnePieceInvariantTests.configured
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        var report = "TELEPORT 5 m: scenario | char | pole-to-hip right after the jump (render only) / after one more tick (cm)\n"
        var worst: Float = 0, tested = 0, controlWorst: Float = 0
        // control: with the carry-over off (jump threshold at infinity) the same jump must leave the pieces behind, or this test proves nothing
        Skinner.teleportJump = .infinity
        _ = OnePieceInvariantTests.run(OnePieceInvariantTests.gaitScenario("walk")!, char: 4, shoes: false, pacing: .hz60, seed: 3) { frame, r, f in
            guard controlWorst == 0, f.beans, f.blend > 0.9, frame > 50 else { return }
            let c = r.sim.centroid()
            r.sim.teleport(toXZ: SIMD2(c.x + 3.5, c.z - 3.5)); r.render()
            controlWorst = max(r.skinner.weldDist[0], r.skinner.weldDist[1])
        }
        Skinner.teleportJump = 1.0
        report += String(format: "control (carry-over off): %.1f cm\n", controlWorst * 100)
        XCTAssertGreaterThan(controlWorst, 0.45, "control: the jump should leave the pieces behind without the fix")
        for name in ["walk", "hop", "march"] {
            for ch in [0, 1, 4] {
                var done = false
                _ = OnePieceInvariantTests.run(OnePieceInvariantTests.gaitScenario(name)!, char: ch, shoes: false, pacing: .hz60, seed: 3) { frame, r, f in
                    guard !done, f.beans, f.blend > 0.9, frame > 50 else { return }
                    done = true
                    let c = r.sim.centroid()
                    r.sim.teleport(toXZ: SIMD2(c.x + 3.5, c.z - 3.5))
                    r.render()
                    let a = max(r.skinner.weldDist[0], r.skinner.weldDist[1])
                    r.brain.tick(sim: r.sim, skinner: r.skinner, dt: r.sim.stepDt, touched: false)
                    r.sim.step(); r.brain.refitBeans(r.sim, r.skinner); r.render()
                    let b = max(r.skinner.weldDist[0], r.skinner.weldDist[1])
                    report += String(format: "%@ | %@ | %.1f / %.1f\n", name, OnePieceInvariantTests.characters[ch].0, a * 100, b * 100)
                    worst = max(worst, a, b); tested += 1
                }
            }
        }
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? report.write(toFile: Self.out + "teleport.txt", atomically: true, encoding: .utf8)
        print(report)
        XCTAssertGreaterThan(tested, 0)
        XCTAssertLessThan(worst, 0.45, "a foot piece was left behind by a teleport")
    }
}
