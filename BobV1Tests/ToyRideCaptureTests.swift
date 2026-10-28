//
//  ToyRideCaptureTests.swift
//  Not a regression test: the mid-ride and multi-Jelbie frames of the ride-on toys with the REAL renderer, when TOYRIDE_CAP_DIR is set
//  (TEST_RUNNER_TOYRIDE_CAP_DIR). Output: toyride_*.png.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class ToyRideCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var dir: String? { ProcessInfo.processInfo.environment["TOYRIDE_CAP_DIR"].flatMap { $0.isEmpty ? nil : $0 } }
    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0) }
    override func tearDown() { DecorField.shared.clear(); ToyTuning.settle = 5; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    func makeRenderer(_ device: MTLDevice, _ rig: MotionRig, w: Int, h: Int) throws -> (MelonRenderer, MTLTexture) {
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: rig.sim.edges, particleCount: rig.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: w, height: h)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        return (ren, device.makeTexture(descriptor: td)!)
    }
    func camera(eye: SIMD3<Float>, at: SIMD3<Float>, aspect: Float, fov: Float = 32 * .pi / 180) -> CameraState {
        var c = CameraState()
        c.view = M4.lookAt(eye: eye, at: at, up: SIMD3(0, 1, 0))
        c.viewProj = M4.mul(M4.perspective(fovy: fov, aspect: aspect, near: 0.1, far: 60), c.view)
        c.invViewProj = M4.invert(c.viewProj)
        c.pos = eye; c.fwd = simd_normalize(at - eye)
        return c
    }
    func decorMesh(into ren: MelonRenderer, time: Float = 0.4) {
        let f = DecorField.shared
        ren.room!.setDecorStatic(DecorModels.build(feet: f.feet, field: f, time: time))
    }
    /// Draws the room and every `rigs` body (each in its own colour, composited by depth order).
    func shot(_ ren: MelonRenderer, _ target: MTLTexture, rigs: [MotionRig], cam: CameraState, w: Int, h: Int) -> LockImage {
        func one(_ k: Int?) -> LockImage {
            let rig = rigs[k ?? 0]
            let light = GameCamera.light(centroids: rigs.map { $0.sim.centroid() })
            for _ in 0..<2 {
                ren.beginFrame()
                rig.skinner.update(x: rig.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
                if k == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
                var fp = FrameParams()
                fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                fp.exposure = 1; fp.meshAlpha = 0
                let pal = JellyRoster.palette(k ?? 0) ?? PaletteKey.blue.palette
                fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(w), Float(h)))
                let cmd = ren.queue.makeCommandBuffer()!
                ren.draw(to: target, commandBuffer: cmd, showMesh: false)
                cmd.waitUntilCompleted()
            }
            var px = [UInt8](repeating: 0, count: w * h * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
            return LockImage(w: w, h: h, bgra: px)
        }
        let empty = one(nil)
        var out = empty
        for k in (0..<rigs.count).sorted(by: { rigs[$0].sim.centroid().z < rigs[$1].sim.centroid().z }) {
            let b = one(k)
            for p in 0..<(w * h) {
                var d = 0
                for c in 0..<3 { d = max(d, abs(Int(b.bgra[4 * p + c]) - Int(empty.bgra[4 * p + c]))) }
                if d > 3 { for c in 0..<4 { out.bgra[4 * p + c] = b.bgra[4 * p + c] } }
            }
        }
        return out
    }
    func sheet(_ cells: [(LockImage, String)], cols: Int, title: String) -> UIImage {
        let cw = cells.map { $0.0.w }.max()!, ch = cells.map { $0.0.h }.max()!, bar = 36, head = 54
        let rows = (cells.count + cols - 1) / cols
        let W = cw * cols, H = head + rows * (ch + bar)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { _ in
            UIColor(white: 0.08, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: W, height: H))
            (title as NSString).draw(at: CGPoint(x: 12, y: 12), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.white])
            for (i, c) in cells.enumerated() {
                let x = (i % cols) * cw, y = head + (i / cols) * (ch + bar)
                (c.1 as NSString).draw(at: CGPoint(x: x + 10, y: y + 7), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 19), .foregroundColor: UIColor.white])
                c.0.uiImage()?.draw(in: CGRect(x: x, y: y + bar, width: c.0.w, height: c.0.h))
            }
        }
    }
    func save(_ img: UIImage, _ name: String) throws {
        guard let dir else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try img.pngData()?.write(to: URL(fileURLWithPath: dir + "/" + name))
    }
    func closeUp(_ ren: MelonRenderer, _ target: MTLTexture, rigs: [MotionRig], focus: SIMD3<Float>, dist: Float = 5.2, w: Int, h: Int, eyeX: Float = 1.4) -> LockImage {
        decorMesh(into: ren, time: 0.37)
        let cam = camera(eye: focus + SIMD3(eyeX, 1.5, dist), at: focus, aspect: Float(w) / Float(h), fov: 33 * .pi / 180)
        return shot(ren, target, rigs: rigs, cam: cam, w: w, h: h)
    }

    // MARK: scooter

    /// Solo ride: frames at the mount, on the deck, along the loop, the dismount.
    func testCaptureScooterRide() throws {
        guard dir != nil else { throw XCTSkip("TOYRIDE_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 480, h = 520
        let p = SIMD2<Float>(1.2, 0.4)
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .kickscooter, x: p.x, z: p.y)])
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.brain.anticsEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: SIMD2(-1.2, 1.4))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.decorStart(.decorSlide, r.sim, only: .kickscooter))
        let (ren, target) = try makeRenderer(device, r, w: w, h: h)
        var cells: [(LockImage, String)] = []
        let marks: [(String, (MotionRig) -> Bool)] = [
            ("hopping onto the deck", { $0.brain.idleState.slideStage == 1 && $0.brain.gait.phase == .air }),
            ("on the deck, ready", { $0.brain.idleState.slideStage == 10 && $0.brain.idleState.phaseT > 0.3 }),
            ("riding: pushing off", { $0.brain.idleState.slideStage == 11 && $0.brain.ride.s > 0.5 }),
            ("riding: into the turn", { $0.brain.idleState.slideStage == 11 && $0.brain.ride.s > 2.6 }),
            ("riding: far side", { $0.brain.idleState.slideStage == 11 && $0.brain.ride.s > 4.4 }),
            ("riding: coming home", { $0.brain.idleState.slideStage == 11 && $0.brain.ride.s > 6.8 }),
            ("parked, about to hop off", { $0.brain.idleState.slideStage == 12 && $0.brain.idleState.phaseT > 0.3 }),
            ("hopping off", { $0.brain.idleState.slideStage == 14 && $0.brain.gait.phase == .air }),
        ]
        let closeMarks: [(String, (MotionRig) -> Bool)] = [
            ("close-up: on the deck, ready", { $0.brain.idleState.slideStage == 10 && $0.brain.idleState.phaseT > 0.3 }),
            ("close-up: riding (feet on the deck, arms at the grips)", { $0.brain.idleState.slideStage == 11 && $0.brain.ride.s > 1.3 && $0.brain.ride.s < 1.5 }),
        ]
        var mi = 0, n = 0
        while mi < marks.count && n < 60 * 40 {
            r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); DecorField.shared.tick(dt: r.sim.stepDt); n += 1
            if marks[mi].1(r) {
                let c = r.sim.centroid()
                cells.append((closeUp(ren, target, rigs: [r], focus: SIMD3(c.x, 0.7, c.z), w: w, h: h), marks[mi].0))
                mi += 1
            }
        }
        XCTAssertEqual(mi, marks.count, "every moment came")
        try save(sheet(cells, cols: 4, title: "Kick scooter ride (solo): feet on the deck, arms stubby, a smooth loop, parked again"), "toyride_scooter.png")
        // a second run for the close-ups
        DecorField.shared.clear(); DecorField.shared.set([PlacedDecor(uid: 7, kind: .kickscooter, x: p.x, z: p.y)])
        let r2 = MotionRig(game: true); Self.keep.append(r2); r2.renderSamples = false
        r2.brain.anticsEnabled = true; r2.brain.abortScript(r2.sim, r2.skinner); r2.sim.teleport(toXZ: SIMD2(-1.2, 1.4))
        for _ in 0..<120 { r2.sim.step() }
        r2.brain.currentPose(r2.sim); r2.brain.idleForced = true
        XCTAssertTrue(r2.brain.decorStart(.decorSlide, r2.sim, only: .kickscooter))
        let (ren2, target2) = try makeRenderer(device, r2, w: 560, h: 560)
        var cc: [(LockImage, String)] = [], ci = 0, n2 = 0
        while ci < closeMarks.count && n2 < 60 * 40 {
            r2.tick(); r2.skinner.jelly.tick(brain: r2.brain, sim: r2.sim, dt: r2.sim.stepDt); DecorField.shared.tick(dt: r2.sim.stepDt); n2 += 1
            if closeMarks[ci].1(r2) {
                let c = r2.sim.centroid()
                for (k, ex) in [(0, Float(1.4)), (1, Float(-2.2))] { cc.append((closeUp(ren2, target2, rigs: [r2], focus: SIMD3(c.x, 0.7, c.z), dist: 3.4, w: 560, h: 560, eyeX: ex), closeMarks[ci].0 + (k == 0 ? " (3/4 front)" : " (from the side)"))) }
                ci += 1
            }
        }
        try save(sheet(cc, cols: 2, title: "Kick scooter close-ups: arms rest toward the grips, feet on the deck, nothing clipping"), "toyride_scooter_close.png")
    }

    // MARK: rocket and horse

    func rockerFrames(_ kind: DecorKind, name: String, title: String) throws {
        guard dir != nil else { throw XCTSkip("TOYRIDE_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let w = 480, h = 520
        let p = SIMD2<Float>(1.1, 0.5)
        DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: p.x, z: p.y)])
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.brain.anticsEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: SIMD2(-1.2, 1.4))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.decorStart(.decorSit, r.sim, only: kind))
        let (ren, target) = try makeRenderer(device, r, w: w, h: h)
        var cells: [(LockImage, String)] = []
        var mi = 0, n = 0
        func ang() -> Float { DecorModels.arcTheta(DecorField.shared.anim[7] ?? DecorAnim()) }
        let marks: [(String, () -> Bool)] = [
            ("hopping on", { r.brain.idleState.bagStage == 1 && r.brain.gait.phase == .air }),
            ("seated, rocking forward", { r.brain.idleState.bagStage == 2 && r.brain.idleState.phase == 2 && r.brain.idleState.phaseT > 3 && ang() > 0.12 }),
            ("seated, rocking back", { r.brain.idleState.bagStage == 2 && r.brain.idleState.phase == 2 && r.brain.idleState.phaseT > 3 && ang() < -0.12 }),
            ("hopping off", { r.brain.idleState.bagStage == 3 && r.brain.gait.phase == .air }),
        ]
        while mi < marks.count && n < 60 * 60 {
            r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); DecorField.shared.tick(dt: r.sim.stepDt); n += 1
            if marks[mi].1() {
                let c = r.sim.centroid()
                cells.append((closeUp(ren, target, rigs: [r], focus: SIMD3(p.x, 0.9, p.y), dist: 5.6, w: w, h: h), marks[mi].0))
                mi += 1
            }
        }
        XCTAssertEqual(mi, marks.count, "every moment came")
        try save(sheet(cells, cols: 4, title: title), name)
    }
    func testCaptureRocketRide() throws { try rockerFrames(.toyrocket, name: "toyride_rocket.png", title: "Toy rocket: he climbs on, rocks with it, climbs off") }
    func testCaptureHorseRide() throws { try rockerFrames(.rockinghorse, name: "toyride_horse.png", title: "Rocking horse: he climbs on, rocks with it, climbs off") }

    // MARK: several Jelbies

    /// n Jelbies in a lab (like the stage: peers, keepApart) with `pieces`; `go` starts them on the toy; renders the frames asked for by `want`.
    func labFrames(n: Int, pieces: [PlacedDecor], seed: UInt64 = 11, seconds: Float, w: Int = 520, h: Int = 560, dist: Float = 7.0, go: (SocialTests.Lab) -> Void, want: (SocialTests.Lab, Int) -> String?, focus: (SocialTests.Lab) -> SIMD3<Float>) throws -> [(LockImage, String)] {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        let starts: [SIMD2<Float>] = n == 2 ? [SIMD2(-2.0, 1.6), SIMD2(-2.4, -0.4)] : [SIMD2(-1.8, 1.4), SIMD2(-0.2, 1.8), SIMD2(1.4, 1.2)]
        let lab = SocialTests.Lab(n: n, positions: starts, quiet: false, seed: seed)
        for r in lab.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = false; r.brain.idleMood = .happy; r.skinner.autoBlink = false }
        DecorField.shared.set(pieces); DecorField.shared.toys = ToyBook()
        go(lab)
        let (ren, target) = try makeRenderer(device, lab.rigs[0], w: w, h: h)
        var cells: [(LockImage, String)] = []
        for i in 0..<Int(seconds * 60) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            if let label = want(lab, i) {
                let f = focus(lab)
                cells.append((closeUp(ren, target, rigs: lab.rigs, focus: f, dist: dist, w: w, h: h), label))
            }
        }
        return cells
    }

    func testCaptureScooterPassingAnotherJelbie() throws {
        guard dir != nil else { throw XCTSkip("TOYRIDE_CAP_DIR not set") }
        let piece = SIMD2<Float>(0.6, 0.0)
        var lastGap: Float = 99, minGap: Float = 99, nearShots = 0
        var cells = try labFrames(n: 2, pieces: [PlacedDecor(uid: 1, kind: .kickscooter, x: piece.x, z: piece.y)], seconds: 32, dist: 7.6, go: { lab in
            _ = lab.rigs[0].brain.decorStart(.decorSlide, lab.rigs[0].sim, only: .kickscooter, uid: 1)
            // the second Jelbie walks across the loop's area on purpose
            lab.rigs[1].brain.requestNow(.goTo(SIMD2(1.9, 0.6)))
        }, want: { lab, i in
            let a = lab.rigs[0].brain, b = lab.rigs[1].brain
            let riding = a.scooterFoot != nil && a.idleState.slideStage == 11
            let gap = simd_distance(a.position, b.position)
            defer { lastGap = gap }
            if riding, a.ride.s > 1.0, gap > lastGap, lastGap < minGap, lastGap < 2.6 { minGap = lastGap; nearShots += 1; return String(format: "riding past the other Jelbie: centres %.2f apart (a body is ~1.4 wide)", lastGap) }
            if riding, a.ride.s > 0.5, i % 120 == 0 { return String(format: "ride, %.1f m along, other Jelbie %.2f away", a.ride.s, gap) }
            return nil
        }, focus: { lab in
            let a = lab.rigs[0].brain.position, b = lab.rigs[1].brain.position
            return SIMD3((a.x + b.x) / 2, 0.8, (a.y + b.y) / 2)
        })
        XCTAssertFalse(cells.isEmpty)
        if cells.count > 8 { cells = Array(cells.prefix(8)) }
        try save(sheet(cells, cols: 4, title: "Kick scooter: the ride yields to another Jelbie (centre gaps shown)"), "toyride_scooter_pass.png")
    }

    func testCaptureTunnelFollowTheLeader() throws {
        guard dir != nil else { throw XCTSkip("TOYRIDE_CAP_DIR not set") }
        let c = SIMD2<Float>(0.6, 0.0)
        var shots = Set<String>()
        let cells = try labFrames(n: 2, pieces: [PlacedDecor(uid: 1, kind: .playtunnel, x: c.x, z: c.y)], seconds: 30, dist: 8.2, go: { lab in
            for j in 0..<2 { lab.rigs[j].brain.toyGo(1, lab.rigs[j].sim) }
        }, want: { lab, i in
            let f = DecorField.shared.foot(1)!, ax = f.turned(SIMD2(1, 0))
            let dirS = DecorField.shared.tunnelDir[1] ?? 1
            let us = lab.rigs.map { simd_dot($0.brain.position - c, ax) * dirS / f.kind.spec.half.x }          // -1 entry ... +1 exit
            let st = lab.rigs.map { $0.brain.idleState.slideStage == 30 }
            func once(_ k: String) -> Bool { if shots.contains(k) { return false }; shots.insert(k); return true }
            for j in 0..<2 where st[j] {
                if us[j] > -1.25, us[j] < -0.9, once("enter\(j)") { return "squeezing in at the mouth" }
                if abs(us[j]) < 0.15, once("mid\(j)") { return "in the middle: squashed, the tunnel ripples" }
                if us[j] > 0.9, us[j] < 1.3, once("exit\(j)") { return "out the other end" }
            }
            if st[0], st[1], abs(us[0]) < 1.1, abs(us[1]) < 1.1, once("both") { return "follow the leader: two in the tunnel" }
            return nil
        }, focus: { _ in SIMD3(c.x, 0.7, c.y) })
        XCTAssertGreaterThanOrEqual(cells.count, 3)
        try save(sheet(cells, cols: 3, title: "Play tunnel: walk through, follow the leader"), "toyride_tunnel.png")
    }

    /// Two (the ball: three) Jelbies on each toy: three moments of the session, for every toy.
    func testCaptureMultiJelbieToys() throws {
        guard dir != nil else { throw XCTSkip("TOYRIDE_CAP_DIR not set") }
        var all: [(LockImage, String)] = []
        let toys: [(DecorKind, String, [Float])] = [
            (.kickscooter, "Scooter: take turns", [6, 16, 38]),
            (.toyrocket, "Rocket: take turns", [8, 18, 40]),
            (.rockinghorse, "Horse: take turns", [8, 18, 40]),
            (.playtunnel, "Tunnel: follow the leader", [5, 9, 14]),
            (.ringstacker, "Ring stacker: turns", [6, 10, 18]),
            (.plushdino, "Dino: hug together", [7, 10, 14]),
            (.beachball, "Beach ball x3", [8, 14, 22]),
        ]
        for (k, title, times) in toys {
            let n = k == .beachball ? 3 : 2
            let at = k == .playtunnel ? SIMD2<Float>(0.6, 0.0) : SIMD2<Float>(0.9, 0.2)
            var next = 0
            let cells = try labFrames(n: n, pieces: [PlacedDecor(uid: 1, kind: k, x: at.x, z: at.y)], seconds: (times.last ?? 10) + 0.5, w: 440, h: 470, dist: k == .playtunnel ? 8.4 : 7.2, go: { lab in
                for j in 0..<n { lab.rigs[j].brain.toyGo(1, lab.rigs[j].sim) }
            }, want: { _, i in
                guard next < times.count, Float(i) / 60 >= times[next] else { return nil }
                next += 1
                return "\(title)  [\(Int(times[next - 1])) s]"
            }, focus: { lab in
                var c = SIMD2<Float>(at.x, at.y)
                if k == .beachball, let b = DecorField.shared.anim[1]?.pos { c = b }
                return SIMD3(c.x, 0.7, c.y)
            })
            all += cells
        }
        XCTAssertFalse(all.isEmpty)
        try save(sheet(all, cols: 3, title: "Two or three Jelbies on every new toy (turn-taking, cheering, sharing)"), "toyride_multi.png")
    }
}
