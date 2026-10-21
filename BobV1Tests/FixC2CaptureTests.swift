//
//  FixC2CaptureTests.swift
//  Not a regression test: when FIXC2_CAP_DIR is set (TEST_RUNNER_FIXC2_CAP_DIR) it writes the "too bland" round's captures, labelled and at true proportion:
//    faces.png        every expression of the layer on Bob at a front close-up (brows, eyes, the open mouths, the blush) + the neutral rest
//    flourishes.png   skip-hop, hopscotch (3 frames), spin, bounce-trot, jump for joy
//    reactions.png    cheer, giggle, comfort, startle, copycat boop, yawn contagion, admire
//    strip.png        10 s of the 3 Jellies in a normal okay-mood room, one frame per second
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class FixC2CaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    let W = 603, H = 1311

    private func dir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["FIXC2_CAP_DIR"], !d.isEmpty else { throw XCTSkip("FIXC2_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: sheet

    private func sheet(_ rows: [(String, [(String, LockImage)])], cw: Int, to path: String, cols: Int? = nil) throws {
        let ch = rows.flatMap { $0.1 }.map { Int(Double(cw) * Double($0.1.h) / Double($0.1.w)) }.max() ?? cw
        let labelH = 30, pad = 6, cellLabel = 16
        let nc = cols ?? (rows.map { $0.1.count }.max() ?? 1)
        let sw = nc * (cw + pad) + pad
        // rows wrap at `nc` cells
        var heights: [Int] = []
        for r in rows { heights.append(((r.1.count + nc - 1) / nc) * (ch + cellLabel + pad) + labelH) }
        let sh = heights.reduce(0, +) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: sw, height: sh))
            var y = pad
            for (ri, row) in rows.enumerated() {
                if !row.0.isEmpty { (row.0 as NSString).draw(at: CGPoint(x: CGFloat(pad + 4), y: CGFloat(y + 6)), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white]) }
                for (c, cell) in row.1.enumerated() {
                    let cx = pad + (c % nc) * (cw + pad), cy = y + labelH + (c / nc) * (ch + cellLabel + pad)
                    (cell.0 as NSString).draw(at: CGPoint(x: CGFloat(cx + 2), y: CGFloat(cy)), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor(white: 0.8, alpha: 1)])
                    if let ui = cell.1.uiImage() { ui.draw(in: CGRect(x: cx, y: cy + cellLabel, width: cw, height: Int(Double(cw) * Double(cell.1.h) / Double(cell.1.w)))) }
                }
                y += heights[ri]
            }
        }
        try img.pngData()!.write(to: URL(fileURLWithPath: path))
    }

    private func crop(_ im: LockImage, x0: Int, y0: Int, w: Int, h: Int) -> LockImage {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let sx = min(max(x0 + x, 0), im.w - 1), sy = min(max(y0 + y, 0), im.h - 1)
            for c in 0..<4 { out[(y * w + x) * 4 + c] = im.bgra[(sy * im.w + sx) * 4 + c] }
        } }
        return LockImage(w: w, h: h, bgra: out)
    }

    // MARK: faces

    func testFaces() throws {
        let d = try dir()
        let scene = try XCTUnwrap(LockScene(settledSteps: 200))
        scene.skinner.prepareBrows(rest: scene.rm.rest)
        var scratch = [Float](repeating: 0, count: scene.rm.vertexCount * 6)
        let view = LockView(name: "close", azimuth: 0.056, elevation: 0.10, zoom: 1)
        func shot(_ label: String, _ p: FacePose, blush: Float = 0, mouth: Float? = nil) -> (String, LockImage) {
            let sk = scene.skinner
            sk.browRaise = [p.raiseL, p.raiseR]; sk.browTilt = [p.tiltL, p.tiltR]
            sk.setEyeOpenness(left: p.eyeL, right: p.eyeR)
            scene.renderer.mouthOpen = mouth ?? p.mouth
            scene.renderer.setBlush(blush, body: 0)
            for _ in 0..<90 { scene.body.step() }
            for _ in 0..<80 { sk.update(x: scene.body.x, index: scene.rm.index, into: &scratch) }
            let full = scene.render(view, palette: .blue)
            return (label, crop(full, x0: 340, y0: 330, w: 640, h: 440))
        }
        var cells: [(String, LockImage)] = []
        cells.append(shot("neutral rest (the locked face)", FacePose()))
        for k in [FaceKind.happy, .joyArc, .oh, .surprised, .curious, .worried, .grumpy, .sleepy, .focused, .hopeful] {
            cells.append(shot(k.rawValue, k.pose(t: 1)))
        }
        cells.append(shot("sigh (sleepy brows, droopy eyes)", FaceKind.sleepy.pose(t: 1)))
        cells.append(shot("hmph (angry brows, narrowed eyes)", FaceKind.grumpy.pose(t: 1)))
        cells.append(shot("excited (brows up, peak)", FaceKind.excited.pose(t: 0.125)))
        cells.append(shot("open happy mouth (skip / run)", FacePose(mouth: 0.45)))
        cells.append(shot("blush only (neutral)", FacePose(), blush: 0.85))
        cells.append(shot("happy + blush", FaceKind.happy.pose(t: 1), blush: 0.85))
        cells.append(shot("joyArc ^^ + blush + open mouth", FacePose(eyeL: 0.12, eyeR: 0.12, mouth: 0.45, raiseL: 0.035, raiseR: 0.035), blush: 0.85))
        try sheet([("faces: Bob, front close-up, one scale; the brows are rigid to the face frame, raise <= 0.05 u, tilt <= 0.3 rad", cells)], cw: 340, to: d + "/faces.png", cols: 4)
        for (i, c) in cells.enumerated() { c.1.png(to: URL(fileURLWithPath: d + "/face_\(i).png")) }
    }

    // MARK: flourishes

    func testFlourishes() throws {
        let d = try dir()
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let Wc = 1080, Hc = 1920, C = 440
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Wc, height: Hc, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        func frames(_ kind: IdleKind, seconds: Float, every: Int, mood: BlobMood = .happy) throws -> [(String, LockImage)] {
            let r = MotionRig(game: true); Self.keep.append(r)
            r.skinner.autoBlink = false
            r.brain.seed = 11; r.brain.idleMood = mood; r.brain.anticsEnabled = true; r.brain.autonomy = true
            r.brain.restTimer = 1e6; r.brain.idleState.cooldown = 1e6; r.brain.socialBook.cooldown = 1e6
            r.brain.expr.pickTimer = 1e6
            guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n) else { throw XCTSkip("no Metal") }
            ren.resize(width: Wc, height: Hc)
            let cam = GameCamera.camera(aspect: Float(Wc) / Float(Hc), focus: 0)
            var rig = CameraRig()
            let light = rig.light(centroid: r.sim.centroid())
            // a long walk across the room, then the flourish between two steps (started by the walk's own hook)
            r.sim.teleport(toXZ: SIMD2(-0.4, -0.5))
            for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim)
            guard let goal = r.brain.pickRunGoal(from: r.root, minD: 3.0, maxD: 4.4) else { throw XCTSkip("no goal") }
            r.brain.script = .walk(target: goal, then: .none); r.brain.activity = .walking
            r.brain.scriptT = 0; r.brain.leg = LegState()
            var started = false
            if kind == .joy || kind == .sigh || kind == .hmph {
                r.run(0.9)
                started = r.brain.idleStart(kind, r.sim); r.brain.idleState.resume = goal
            } else {
                r.run(0.1)
                r.brain.leg.kind = kind; r.brain.leg.wants = true; r.brain.leg.rolled = false; r.brain.leg.trigger = 0.5; r.brain.leg.from = r.brain.position
                r.run(4.0, until: { r.brain.idleState.kind == kind })
                started = r.brain.idleState.kind == kind
            }
            XCTAssertTrue(started, "\(kind) started")
            var out: [(String, LockImage)] = []
            var i = 0
            let total = Int(seconds * 60)
            var t0: Float = 0
            while i < total {
                r.tick()
                r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
                if i % every == 0 {
                    ren.beginFrame()
                    r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
                    ren.setMouth(r.brain.mouthOpen, body: 0); ren.setBlush(r.brain.blushNow, body: 0)
                    var fp = FrameParams()
                    fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
                    fp.exposure = 1; fp.meshAlpha = 0
                    let pal = PaletteKey.blue.palette
                    fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
                    ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(Wc), Float(Hc)))
                    let cmd = ren.queue.makeCommandBuffer()!
                    ren.draw(to: target, commandBuffer: cmd, showMesh: false)
                    cmd.waitUntilCompleted()
                    var px = [UInt8](repeating: 0, count: Wc * Hc * 4)
                    px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: Wc * 4, from: MTLRegionMake2D(0, 0, Wc, Hc), mipmapLevel: 0) }
                    let c = r.sim.centroid()
                    let clip = cam.viewProj * SIMD4<Float>(c.x, 0.55, c.z, 1)
                    let sx = Int((clip.x / clip.w * 0.5 + 0.5) * Float(Wc)), sy = Int((0.5 - clip.y / clip.w * 0.5) * Float(Hc))
                    let x0 = max(0, min(Wc - C, sx - C / 2)), y0 = max(0, min(Hc - C, sy - C / 2))
                    var o = [UInt8](repeating: 0, count: C * C * 4)
                    for y in 0..<C { for x in 0..<(C * 4) { o[y * C * 4 + x] = px[(y0 + y) * Wc * 4 + x0 * 4 + x] } }
                    out.append((String(format: "%.2f s  %@  face %@", t0, "\(r.brain.idleState.kind.map { $0.rawValue } ?? "walk")", "\(r.brain.expr.kind.rawValue)"), LockImage(w: C, h: C, bgra: o)))
                }
                i += 1; t0 += 1.0 / 60
                if r.brain.idleState.kind == nil, i > 20 { break }
            }
            return out
        }
        var rows: [(String, [(String, LockImage)])] = []
        let skip = try frames(.skipHop, seconds: 1.6, every: 9)
        rows.append(("skip-hop: two low chained hops along the leg, open happy mouth", skip))
        let hs = try frames(.hopscotch, seconds: 2.4, every: 12)
        rows.append(("hopscotch: three hops of 0.34 u, 0.12 u to alternate sides", hs))
        let sp = try frames(.legSpin, seconds: 1.5, every: 12)
        rows.append(("mid-leg spin: one quick turn on the spot, then on", sp))
        let tr = try frames(.trot, seconds: 2.2, every: 20)
        rows.append(("bounce-trot: the run blend at 0.4 for 2 s, no stop", tr))
        let jy = try frames(.joy, seconds: 1.2, every: 8)
        rows.append(("jump for joy: 0.12 u hop, arms up, excited brows, blush", jy))
        let rl = try frames(.rollTrip, seconds: 3.2, every: 20)
        rows.append(("roll along the leg: tips over, rolls 1...2.5 u, pops up with a squish", rl))
        let sg = try frames(.sigh, seconds: 4.4, every: 26, mood: .okay)
        rows.append(("big sigh: slow inhale (+4 %), long exhale and slump, sleepy brows and droopy eyes", sg))
        let hm = try frames(.hmph, seconds: 1.5, every: 9, mood: .grumpy)
        rows.append(("grumpy hmph: puffs up (squash widens 6 %), angry brows, turns away, a stomp", hm))
        try sheet(rows, cw: 220, to: d + "/flourishes.png", cols: 6)
        for (ri, r) in rows.enumerated() { for (ci, c) in r.1.enumerated() { c.1.png(to: URL(fileURLWithPath: d + "/flourish_\(ri)_\(ci).png")) } }
    }

    // MARK: the room: reactions and the strip

    private func composite(_ lab: SocialTests.Lab, _ ren: MelonRenderer, _ target: MTLTexture) -> LockImage {
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        func shot(only: Int?) -> LockImage {
            let k = only ?? 0
            let light = GameCamera.light(centroid: lab.rigs[k].sim.centroid())
            ren.beginFrame()
            lab.rigs[k].skinner.update(x: lab.rigs[k].sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            ren.setMouth(only == nil ? 0 : lab.rigs[k].brain.mouthOpen, body: 0)
            ren.setBlush(only == nil ? 0 : lab.rigs[k].brain.blushNow, body: 0)
            if only == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            return LockImage(w: W, h: H, bgra: px)
        }
        _ = shot(only: nil)
        let empty = shot(only: nil)
        var out = empty
        for k in (0..<lab.rigs.count).sorted(by: { lab.rigs[$0].sim.centroid().z < lab.rigs[$1].sim.centroid().z }) {
            let b = shot(only: k)
            for p in 0..<(W * H) {
                var dd = 0
                for c in 0..<3 { dd = max(dd, abs(Int(b.bgra[4 * p + c]) - Int(empty.bgra[4 * p + c]))) }
                if dd > 3 { for c in 0..<4 { out.bgra[4 * p + c] = b.bgra[4 * p + c] } }
            }
        }
        return out
    }

    private func screenOf(_ lab: SocialTests.Lab, _ i: Int) -> (x: Int, y: Int) {
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        let c = lab.rigs[i].sim.centroid()
        let clip = cam.viewProj * SIMD4<Float>(c.x, 0.6, c.z, 1)
        return (Int((clip.x / clip.w * 0.5 + 0.5) * Float(W)), Int((0.5 - clip.y / clip.w * 0.5) * Float(H)))
    }

    func testReactions() throws {
        let d = try dir()
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: Float(W) / Float(H))
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DecorField.shared.clear() }
        var rows: [(String, [(String, LockImage)])] = []
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!

        func scene(_ label: String, seconds: Float, frames: Int, pair: (Int, Int) = (0, 1), toys: [DecorKind] = [], positions: [SIMD2<Float>] = SocialTests.starts,
                   setup: (SocialTests.Lab) -> Void) throws {
            var placed: [PlacedDecor] = []
            for (i, k) in toys.enumerated() { if let p = DecorPlacement.findSpot(k, among: placed) { placed.append(PlacedDecor(uid: 30 + i, kind: k, x: p.x, z: p.y)) } }
            DecorField.shared.set(placed)
            let lab = SocialTests.Lab(positions: positions, seed: 31)
            SocialTests.keep.append(lab)
            let r0 = lab.rigs[0]
            for r in lab.rigs { r.skinner.autoBlink = false; r.brain.anticsEnabled = true; r.brain.sleepEnabled = true; r.brain.watching = true; r.brain.idleMood = .happy
                r.brain.restTimer = 1e6; r.brain.idleState.cooldown = 1e6; r.brain.socialBook.cooldown = 1e6; r.brain.expr.pickTimer = 1e6 }
            guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r0.sim.edges, particleCount: r0.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
            ren.resize(width: W, height: H)
            ren.roomCacheEnabled = false
            setup(lab)
            var cells: [(String, LockImage)] = []
            let every = max(1, Int(seconds * 60) / frames)
            var f = 0
            while cells.count < frames && f < Int(seconds * 60) + 600 {
                lab.tick(watching: false)
                DecorField.shared.tick(dt: 1.0 / 60)
                for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
                if f % every == 0 {
                    let full = composite(lab, ren, target)
                    let a = screenOf(lab, pair.0), b = screenOf(lab, pair.1)
                    let cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2 - 30
                    let cw = 400, ch = 330
                    let kinds = lab.rigs.map { $0.brain.idleState.kind.map { $0.rawValue } ?? ($0.brain.social.map { "social:" + $0.kind.rawValue } ?? "-") }
                    cells.append((String(format: "%.1f s  %@ / %@", Float(f) / 60, kinds[pair.0], kinds[pair.1]), crop(full, x0: cx - cw / 2, y0: cy - ch / 2, w: cw, h: ch)))
                }
                f += 1
            }
            rows.append((label, cells))
        }
        func event(_ k: BusEventKind, from i: Int, _ lab: SocialTests.Lab, piece: DecorKind? = nil) -> BusEvent { BusEvent(kind: k, source: i, pos: lab.rigs[max(i, 0)].brain.position, piece: piece) }

        try scene("cheer: one rides the slide, the friend hops for joy (excited brows, blush)", seconds: 5.2, frames: 6, toys: [.slide]) { lab in
            let a = lab.rigs[0].brain, b = lab.rigs[1].brain
            _ = a.idleStart(.slide, lab.rigs[0].sim)
            _ = b.accept(.cheer, event(.slid, from: 0, lab), delay: 1.6)
        }
        try scene("giggle: the tower topples, the friend giggles (squash bounce, ^^)", seconds: 3.4, frames: 6, toys: [.blocks]) { lab in
            if let f = DecorField.shared.kinds(.blocks).first { DecorField.shared.tumble(f.uid, direction: SIMD2(0, 1)) }
            _ = lab.rigs[1].brain.accept(.giggle, event(.towerToppled, from: -1, lab), delay: 0.6)
        }
        try scene("comfort: a trip, the friend walks over and nuzzles", seconds: 9.0, frames: 6) { lab in
            let a = lab.rigs[0].brain, b = lab.rigs[1].brain
            a.postEvent(.tripped)
            _ = b.accept(.comfort, event(.tripped, from: 0, lab), delay: 0.5)
        }
        let ballSpot = DecorPlacement.findSpot(.ball, among: []) ?? SIMD2(1.5, 0.8)
        let jellyAt = ballSpot + SIMD2(1.7, 0.1)
        try scene("startle: a ball rolls past, a little hop and a surprised face", seconds: 3.0, frames: 6, toys: [.ball], positions: [SIMD2(-1.0, 0.6), jellyAt, SIMD2(0.0, 2.4)]) { lab in
            if let f = DecorField.shared.kinds(.ball).first {
                let b = lab.rigs[1].brain
                let dir = simd_normalize(b.position - f.centre + SIMD2(0, 0.35))
                DecorField.shared.kickBall(f.uid, direction: dir, speed: 2.6)
            }
            lab.rigs[1].brain.react.cool = 0
        }
        try scene("copycat: one boops the drum, the friend does the same", seconds: 9.0, frames: 6, toys: [.drum]) { lab in
            let a = lab.rigs[0].brain, b = lab.rigs[1].brain
            _ = a.decorStart(.decorBoop, lab.rigs[0].sim, only: .drum)
            _ = b.accept(.copycat, event(.booped, from: 0, lab, piece: .drum), delay: 4.5)
        }
        try scene("yawn contagion: one yawns, the friend yawns too", seconds: 5.0, frames: 6) { lab in
            lab.rigs[0].brain.idleNight = 0.5; lab.rigs[1].brain.idleNight = 0.5
            _ = lab.rigs[0].brain.idleStart(.yawn, lab.rigs[0].sim)
            _ = lab.rigs[1].brain.accept(.yawn, event(.yawned, from: 0, lab), delay: 1.6)
        }
        try scene("admire: a friend's new outfit, a look and a blush", seconds: 4.4, frames: 6) { lab in
            _ = lab.rigs[1].brain.accept(.admire, event(.newOutfit, from: 0, lab), delay: 0.4)
        }
        try sheet(rows.map { ($0.0, $0.1) }, cw: 260, to: d + "/reactions.png", cols: 6)
        for (ri, r) in rows.enumerated() { for (ci, c) in r.1.enumerated() { c.1.png(to: URL(fileURLWithPath: d + "/reaction_\(ri)_\(ci).png")) } }
    }

    func testStrip() throws {
        let d = try dir()
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: Float(W) / Float(H))
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DecorField.shared.clear() }
        LivelyLabTests.placeToys()
        let lab = SocialTests.Lab(quiet: false, seed: 202)
        SocialTests.keep.append(lab)
        for (i, r) in lab.rigs.enumerated() {
            let b = r.brain
            r.skinner.autoBlink = false
            b.idleMood = .okay; b.socialBook.cooldown = 8; b.idleState.cooldown = 9; b.restTimer = 0.5 + Float(i)
            b.anticsEnabled = true; b.watching = true; b.sleepEnabled = true
        }
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: lab.rigs[0].sim.edges, particleCount: lab.rigs[0].sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H); ren.roomCacheEnabled = false
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        // warm up 40 s, then 10 s at one frame per second
        var cells: [(String, LockImage)] = []
        for f in 0..<(60 * 50) {
            lab.tick(watching: false)
            DecorField.shared.tick(dt: 1.0 / 60)
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            if f >= 60 * 40 && (f - 60 * 40) % 60 == 0 {
                let tag = lab.rigs.map { b -> String in
                    let k = b.brain.idleState.kind.map { $0.rawValue } ?? (b.brain.social.map { "s:" + $0.kind.rawValue } ?? "-")
                    return k + "/" + b.brain.expr.kind.rawValue
                }.joined(separator: "  ")
                cells.append((String(format: "t+%d s  %@", cells.count, tag), composite(lab, ren, target)))
            }
        }
        try sheet([("10 s of the 3 Jellies, normal okay-mood room, one frame per second (idle kind / face)", cells)], cw: 232, to: d + "/strip.png", cols: 10)
        for (i, c) in cells.enumerated() { c.1.png(to: URL(fileURLWithPath: d + "/strip_\(i).png")) }
    }
}
