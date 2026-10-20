//
//  FixACaptureTests.swift
//  Not a regression test: renders the 2026-10-20 behaviour round with the REAL renderer (MelonRenderer, game room, the real camera) when FIXA_CAP_DIR is set
//  (pass it as TEST_RUNNER_FIXA_CAP_DIR). Output: flop_strip.png, coverage_port.png, coverage_land.png, awake_roam.png, zoomies.png, social_strip.png.
//  Every frame is one fixed scale (no per-cell zoom), so proportions are true.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class FixACaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var W = 603, H = 1311
    var aspect: Float { Float(W) / Float(H) }

    override func setUp() { RoomLayout.dynamicBoxes = []; DecorField.shared.clear(); SocialTuning.pickChance = 0.12 }
    override func tearDown() {
        DecorField.shared.clear(); DayClock.shared.forcedHour = 12; SocialTuning.pickChance = 0.12
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }
    private var dir: String? { ProcessInfo.processInfo.environment["FIXA_CAP_DIR"].flatMap { $0.isEmpty ? nil : $0 } }

    // MARK: plumbing

    private func room(aspect: Float) {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        _ = GameCamera.camera(aspect: aspect)
        GameCamera.refreshRoam(aspect: aspect)
    }
    private func renderer(_ device: MTLDevice, _ lab: SocialTests.Lab) throws -> (MelonRenderer, MTLTexture) {
        let r0 = lab.rigs[0]
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r0.sim.edges, particleCount: r0.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        return (ren, device.makeTexture(descriptor: td)!)
    }
    private func shot(_ lab: SocialTests.Lab, _ ren: MelonRenderer, _ target: MTLTexture, only: Int?, hour: Double?, decor: Bool) -> LockImage {
        let cam = GameCamera.camera(aspect: aspect, focus: 0)
        ren.dayHourOverride = hour
        let k = only ?? 0
        let light = GameCamera.light(centroids: lab.rigs.map { $0.sim.centroid() })
        ren.beginFrame()
        ren.setMouth(only == nil ? 0 : lab.rigs[k].brain.mouthOpen, body: 0)
        if decor { ren.room!.setDecorStatic(DecorModels.build(feet: DecorField.shared.feet, field: DecorField.shared, time: 0.4)) }
        lab.rigs[k].skinner.update(x: lab.rigs[k].sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
        if only == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
        var fp = FrameParams()
        fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
        fp.exposure = 1; fp.meshAlpha = 0
        let pal = JellyRoster.palette(k) ?? PaletteKey.blue.palette
        fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
        ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
        let cmd = ren.queue.makeCommandBuffer()!
        ren.draw(to: target, commandBuffer: cmd, showMesh: false)
        cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: W * H * 4)
        px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
        return LockImage(w: W, h: H, bgra: px)
    }
    private func emptyRoom(_ lab: SocialTests.Lab, _ ren: MelonRenderer, _ target: MTLTexture, hour: Double? = 12, decor: Bool = false) -> LockImage {
        _ = shot(lab, ren, target, only: nil, hour: hour, decor: decor)
        return shot(lab, ren, target, only: nil, hour: hour, decor: decor)
    }
    private func composite(_ lab: SocialTests.Lab, _ ren: MelonRenderer, _ target: MTLTexture, hour: Double? = 12, decor: Bool = false, only: [Int]? = nil) -> LockImage {
        let empty = emptyRoom(lab, ren, target, hour: hour, decor: decor)
        var out = empty
        let order = (only ?? Array(lab.rigs.indices)).sorted(by: { lab.rigs[$0].sim.centroid().z < lab.rigs[$1].sim.centroid().z })
        for k in order {
            let b = shot(lab, ren, target, only: k, hour: hour, decor: decor)
            for p in 0..<(W * H) {
                var d = 0
                for c in 0..<3 { d = max(d, abs(Int(b.bgra[4 * p + c]) - Int(empty.bgra[4 * p + c]))) }
                if d > 3 { for c in 0..<4 { out.bgra[4 * p + c] = b.bgra[4 * p + c] } }
            }
        }
        return out
    }
    private func project(_ p: SIMD3<Float>) -> CGPoint {
        let cam = GameCamera.camera(aspect: aspect, focus: 0)
        let c = cam.viewProj * SIMD4<Float>(p.x, p.y, p.z, 1)
        return CGPoint(x: CGFloat((c.x / c.w * 0.5 + 0.5) * Float(W)), y: CGFloat((1 - (c.y / c.w * 0.5 + 0.5)) * Float(H)))
    }
    private func save(_ img: UIImage, _ name: String) throws {
        let d = try XCTUnwrap(dir)
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        try img.pngData()?.write(to: URL(fileURLWithPath: d + "/" + name))
    }
    private func tick(_ lab: SocialTests.Lab) {
        lab.tick(watching: false)
        for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); DecorField.shared.tick(dt: r.sim.stepDt / 3) }
    }
    private func newLab(_ positions: [SIMD2<Float>], n: Int = 3, seed: UInt64 = 31, quiet: Bool = true) -> SocialTests.Lab {
        let lab = SocialTests.Lab(n: n, positions: positions, quiet: quiet, seed: seed)
        Self.keep.append(lab)
        for r in lab.rigs { r.skinner.autoBlink = false; r.brain.anticsEnabled = true; r.brain.sleepEnabled = true }
        return lab
    }
    /// A framed, labelled UIImage of a frame, optionally with a drawing on top (in frame pixels).
    private func labelled(_ img: LockImage, _ text: String, scale: CGFloat = 1, crop: CGRect? = nil, over: ((CGContext) -> Void)? = nil) -> UIImage {
        let bar: CGFloat = 38
        let src = crop ?? CGRect(x: 0, y: 0, width: img.w, height: img.h)
        let w = src.width * scale, h = src.height * scale
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + bar), format: fmt).image { ctx in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + bar))
            (text as NSString).draw(at: CGPoint(x: 8, y: 9), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.white])
            if let cg = img.cgImage(), let part = cg.cropping(to: src) { UIImage(cgImage: part).draw(in: CGRect(x: 0, y: bar, width: w, height: h)) }
            let c = ctx.cgContext
            c.saveGState(); c.translateBy(x: -src.minX * scale, y: bar - src.minY * scale); c.scaleBy(x: scale, y: scale)
            over?(c)
            c.restoreGState()
        }
    }
    private func sheet(_ cells: [UIImage], cols: Int, title: String) -> UIImage {
        let cw = Int(cells.map { $0.size.width }.max() ?? 0), ch = Int(cells.map { $0.size.height }.max() ?? 0), head = 44, pad = 4
        let rows = (cells.count + cols - 1) / cols
        let SW = cols * (cw + pad) + pad, SH = head + rows * (ch + pad) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: SW, height: SH), format: fmt).image { _ in
            UIColor(white: 0.06, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: SW, height: SH))
            (title as NSString).draw(at: CGPoint(x: 10, y: 10), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.white])
            for (i, c) in cells.enumerated() { c.draw(at: CGPoint(x: pad + (i % cols) * (cw + pad), y: head + (i / cols) * (ch + pad))) }
        }
    }

    // MARK: flop strip

    func testCaptureFlopStrip() throws {
        guard dir != nil else { throw XCTSkip("FIXA_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        W = 1206; H = 2622
        room(aspect: aspect)
        let lab = newLab([SIMD2(0.0, 0.6), SIMD2(-3.0, -1.5), SIMD2(3.0, -1.5)], n: 1)
        let (ren, target) = try renderer(device, lab)
        let r = lab.rigs[0]
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 600
        struct Want { var label: String; var done = false; var test: (BlobBrain) -> Bool }
        var wants: [Want] = [
            Want(label: "1 yawn peak (stage 1, 0.9 s in)") { $0.sleep.stage == 1 && $0.sleep.turned && $0.sleep.t >= 0.85 },
            Want(label: "2 the fall (0.30 s)") { $0.sleep.stage == 2 && $0.sleep.t >= 0.30 },
            Want(label: "3 impact: squash + kick (0.44 s)") { $0.sleep.stage == 2 && $0.sleep.t >= 0.44 },
            Want(label: "4 overshoot (0.53 s)") { $0.sleep.stage == 2 && $0.sleep.t >= 0.53 },
            Want(label: "5 settling (0.70 s)") { $0.sleep.stage == 2 && $0.sleep.t >= 0.70 },
            Want(label: "6 asleep (stage 3)") { $0.sleep.stage == 3 && $0.sleep.t >= 0.8 },
            Want(label: "WAKE 7 roll-up pop (0.18 s)") { $0.sleep.stage == 4 && $0.sleep.t >= 0.18 },
            Want(label: "WAKE 8 stretch (0.6 s)") { $0.sleep.stage == 5 && $0.sleep.t >= 0.6 },
        ]
        var cells = [UIImage]()
        var woke = false
        for _ in 0..<(60 * 40) where cells.count < wants.count {
            tick(lab)
            guard r.brain.idleState.kind == .sleep else { continue }
            if wants[5].done, !woke { woke = true; r.brain.sleepWake(groggy: false) }
            for i in wants.indices where !wants[i].done && wants[i].test(r.brain) {
                wants[i].done = true
                let img = composite(lab, ren, target, hour: 15)
                let c = project(r.sim.centroid())
                let crop = CGRect(x: max(0, c.x - 260), y: max(0, c.y - 300), width: 520, height: 520)
                cells.append(labelled(img, wants[i].label + String(format: "  (k %.2f sq %.2f)", r.brain.sleep.k, r.sim.attractor.squash), crop: crop))
            }
        }
        XCTAssertEqual(cells.count, wants.count, "all frames caught")
        try save(sheet(cells, cols: 4, title: "Lie-down FLOP (yawn 1.8 s, fall 0.42 s, squash on impact, settle) and the quick wake pop: same scale, game camera 2x"), "flop_strip.png")
    }

    // MARK: coverage

    private func coverageCapture(aspectValue: Float, label: String, file: String, device: MTLDevice) throws {
        W = aspectValue < 1 ? 603 : 1400; H = aspectValue < 1 ? 1311 : Int(1400 / aspectValue)
        room(aspect: aspect)
        let lab = newLab(SocialTests.starts, seed: 5, quiet: false)
        for (i, r) in lab.rigs.enumerated() {
            let b = r.brain
            b.idleMood = .happy; b.socialBook.cooldown = 6 + Float(i) * 3; b.idleState.cooldown = 8 + Float(i) * 2; b.restTimer = 0.5 + Float(i)
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
        }
        let (ren, target) = try renderer(device, lab)
        let rf = try XCTUnwrap(GameCamera.roamFloor)
        var heat = [Int: Int](), trails = [[SIMD2<Float>]](repeating: [], count: 3)
        let cell: Float = 0.5
        func key(_ x: Float, _ z: Float) -> Int { (Int(floorf(x / cell)) + 100) * 1000 + Int(floorf(z / cell)) + 100 }
        for f in 0..<(60 * 600) {
            tick(lab)
            if f % 6 == 0 {
                for (i, r) in lab.rigs.enumerated() {
                    let p = r.brain.position
                    heat[key(p.x, p.y), default: 0] += 1
                    if f % 30 == 0 { trails[i].append(p) }
                }
            }
        }
        let bg = composite(lab, ren, target, hour: 12)
        let colors: [UIColor] = [UIColor(red: 0.2, green: 0.45, blue: 1, alpha: 1), UIColor(red: 1, green: 0.8, blue: 0.1, alpha: 1), UIColor(red: 0.2, green: 0.85, blue: 0.3, alpha: 1)]
        let peak = Float(heat.values.max() ?? 1)
        let walked = heat.keys.filter { k in let x = (Float(k / 1000 - 100) + 0.5) * cell, z = (Float(k % 1000 - 100) + 0.5) * cell; return rf.contains(SIMD2(x, z)) }.count
        let img = labelled(bg, "\(label) 10 sim min: heat+paths; yellow = roam area, red dashed = OLD box") { [self] c in
            // heat cells
            for (k, n) in heat {
                let x0 = Float(k / 1000 - 100) * cell, z0 = Float(k % 1000 - 100) * cell
                let a = 0.18 + 0.5 * min(1, Float(n) / (peak * 0.5))
                let pts = [project(SIMD3(x0, 0, z0)), project(SIMD3(x0 + cell, 0, z0)), project(SIMD3(x0 + cell, 0, z0 + cell)), project(SIMD3(x0, 0, z0 + cell))]
                c.setFillColor(UIColor(red: 1, green: 0.3, blue: 0.1, alpha: CGFloat(a)).cgColor)
                c.move(to: pts[0]); for p in pts.dropFirst() { c.addLine(to: p) }; c.closePath(); c.fillPath()
            }
            for (i, t) in trails.enumerated() {
                c.setStrokeColor(colors[i].withAlphaComponent(0.9).cgColor); c.setLineWidth(3)
                for (j, p) in t.enumerated() { let s = project(SIMD3(p.x, 0.02, p.y)); if j == 0 { c.move(to: s) } else { c.addLine(to: s) } }
                c.strokePath()
            }
            // the polygon
            c.setStrokeColor(UIColor.yellow.cgColor); c.setLineWidth(4)
            var left = [CGPoint](), right = [CGPoint]()
            for (z, h) in zip(rf.zs, rf.hw) { left.append(project(SIMD3(-h, 0.03, z))); right.append(project(SIMD3(h, 0.03, z))) }
            c.move(to: left[0]); for p in left.dropFirst() { c.addLine(to: p) }; c.addLine(to: right.last!); for p in right.reversed() { c.addLine(to: p) }; c.closePath(); c.strokePath()
            // the old box
            c.setStrokeColor(UIColor.red.cgColor); c.setLineWidth(3); c.setLineDash(phase: 0, lengths: [14, 10])
            let old = [project(SIMD3(-3.2, 0.03, -2.6)), project(SIMD3(3.2, 0.03, -2.6)), project(SIMD3(3.2, 0.03, 2.8)), project(SIMD3(-3.2, 0.03, 2.8))]
            c.move(to: old[0]); for p in old.dropFirst() { c.addLine(to: p) }; c.closePath(); c.strokePath()
        }
        MotionLog.write("FIXA coverage \(label): polygon z \(rf.minZ)...\(rf.maxZ), cells with a Jelly in them (centre only) \(walked), peak \(peak)")
        try save(img, file)
    }
    func testCaptureCoveragePortrait() throws {
        guard dir != nil else { throw XCTSkip("FIXA_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        try coverageCapture(aspectValue: 440 / 956, label: "PORTRAIT", file: "coverage_port.png", device: device)
    }
    func testCaptureCoverageLandscape() throws {
        guard dir != nil else { throw XCTSkip("FIXA_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        try coverageCapture(aspectValue: 956 / 440, label: "LANDSCAPE", file: "coverage_land.png", device: device)
    }

    // MARK: the awake Jelly while two sleep

    func testCaptureAwakeRoam() throws {
        guard dir != nil else { throw XCTSkip("FIXA_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        room(aspect: aspect)
        let lab = newLab([SIMD2(-1.2, 0.1), SIMD2(0.5, 0.1), SIMD2(0.0, 2.2)], seed: 77, quiet: false)
        for r in lab.rigs { r.brain.idleMood = .okay; r.brain.idleNight = 0; r.brain.restTimer = 0.5; r.brain.idleState.cooldown = 4; r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius }
        let (ren, target) = try renderer(device, lab)
        for i in 0..<2 { lab.rigs[i].brain.startGoodnight(lab.rigs[i].sim, lab.rigs[i].skinner) }
        let me = lab.rigs[2]
        var trail = [SIMD2<Float>](), kinds = [(Float, IdleKind)](), lastKind: IdleKind?
        var t: Float = 0
        for f in 0..<(60 * 120) {
            tick(lab); t += 1.0 / 60
            if f % 12 == 0 { trail.append(me.brain.position) }
            if me.brain.idleState.kind != lastKind { lastKind = me.brain.idleState.kind; if let k = lastKind { kinds.append((t, k)) } }
        }
        let img = composite(lab, ren, target, hour: 15)
        let names = kinds.map { "\(Int($0.0))s \($0.1.rawValue)" }.joined(separator: ", ")
        let out = labelled(img, "2 asleep, 1 awake: his 120 s path (white); \(kinds.count) things done") { [self] c in
            c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(4)
            for (j, p) in trail.enumerated() { let s = project(SIMD3(p.x, 0.03, p.y)); if j == 0 { c.move(to: s) } else { c.addLine(to: s) } }
            c.strokePath()
            c.setFillColor(UIColor.yellow.cgColor)
            if let p = trail.last { let s = project(SIMD3(p.x, 0.03, p.y)); c.fillEllipse(in: CGRect(x: s.x - 7, y: s.y - 7, width: 14, height: 14)) }
        }
        MotionLog.write("FIXA awake roam: kinds \(names), sleepers \(lab.rigs.prefix(2).map { $0.brain.sleep.stage })")
        try save(out, "awake_roam.png")
    }

    // MARK: zoomies + a chase

    func testCaptureZoomies() throws {
        guard dir != nil else { throw XCTSkip("FIXA_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        room(aspect: aspect)
        var cells = [UIImage]()
        do {
            let lab = newLab([SIMD2(-1.8, 0.4), SIMD2(2.3, -0.8), SIMD2(2.2, 2.6)], seed: 31)
            let (ren, target) = try renderer(device, lab)
            let a = lab.rigs[0]
            a.brain.idleForced = true
            XCTAssertTrue(a.brain.idleStart(.zoomies, a.sim, goal: SIMD2(1.0, 2.4)))
            var n = 0
            while !(a.brain.idleState.kind == .zoomies && a.brain.zoomW > 0.95 && a.brain.runW > 0.9 && simd_distance(a.brain.position, SIMD2(1.0, 2.4)) < 2.2) && n < 60 * 12 { tick(lab); n += 1 }
            cells.append(labelled(composite(lab, ren, target), String(format: "ZOOMIES mid-dash (okay mood): zoomW %.2f, runW %.2f", a.brain.zoomW, a.brain.runW)))
        }
        do {
            let lab = newLab([SIMD2(-1.6, 0.3), SIMD2(1.4, 0.6), SIMD2(2.4, 2.4)], seed: 31)
            let (ren, target) = try renderer(device, lab)
            let a = lab.rigs[0], b = lab.rigs[1]
            XCTAssertTrue(a.brain.socialStart(.chase, with: b.brain, a.sim))
            var n = 0
            while !(a.brain.social?.phase == 1 && a.brain.runW > 0.8 && b.brain.runW > 0.8) && n < 60 * 20 { tick(lab); n += 1 }
            cells.append(labelled(composite(lab, ren, target), String(format: "TAG: two-Jelly chase, phase %d (round %d of %d)", a.brain.social?.phase ?? -1, (a.brain.social?.round ?? 0) + 1, SocialTuning.chaseRounds)))
        }
        try save(sheet(cells, cols: 2, title: "Zoomies and a chase (same scale, portrait game camera)"), "zoomies.png")
    }

    // MARK: ball pass and beanbag sit-together

    func testCaptureSocials() throws {
        guard dir != nil else { throw XCTSkip("FIXA_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        room(aspect: aspect)
        var cells = [UIImage]()
        let crop = CGRect(x: 40, y: 430, width: 523, height: 470)
        // ball pass
        do {
            DecorField.shared.set([PlacedDecor(uid: 1, kind: .ball, x: -0.9, z: 1.0)])
            let lab = newLab([SIMD2(-2.2, 1.0), SIMD2(1.6, 1.0), SIMD2(2.4, -1.5)], seed: 31)
            let (ren, target) = try renderer(device, lab)
            let a = lab.rigs[0], b = lab.rigs[1]
            XCTAssertTrue(a.brain.socialStart(.pass, with: b.brain, a.sim), "ball pass starts")
            var want: [(String, (SocialSession) -> Bool)] = [
                ("BALL PASS 1: kicker lines up behind the ball", { $0.phase == 1 && $0.phaseT > 0.1 }),
                ("2: the kick (lean in, ball away)", { $0.phase == 2 && $0.phaseT > 0.25 && $0.passes == 0 }),
                ("3: the ball rolls to his friend", { $0.phase == 2 && $0.passes == 0 && $0.phaseT > 1.2 }),
                ("4: the friend kicks it back", { $0.passes >= 1 && $0.phase == 2 && $0.phaseT > 0.25 }),
            ]
            var n = 0
            while !want.isEmpty && n < 60 * 50 {
                tick(lab); n += 1
                if let s = a.brain.social, s.kind == .pass, want[0].1(s) {
                    cells.append(labelled(composite(lab, ren, target, decor: true), want[0].0 + " [pass \(s.passes + 1)/\(s.passTarget)]", crop: crop))
                    want.removeFirst()
                }
            }
            XCTAssertTrue(want.isEmpty, "ball-pass frames caught (\(want.count) missing), session \(String(describing: a.brain.social?.phase))")
        }
        // beanbag sit-together (one bag: one on it, one beside it)
        do {
            DecorField.shared.set([PlacedDecor(uid: 2, kind: .beanbag, x: 0.0, z: 0.6)])
            let lab = newLab([SIMD2(-2.0, 1.8), SIMD2(2.0, 1.8), SIMD2(2.4, -1.5)], seed: 31)
            let (ren, target) = try renderer(device, lab)
            let a = lab.rigs[0], b = lab.rigs[1]
            XCTAssertTrue(a.brain.socialStart(.bagSit, with: b.brain, a.sim), "bag sit starts")
            var got = [Bool](repeating: false, count: 3)
            var n = 0
            while got.contains(false) && n < 60 * 45 {
                tick(lab); n += 1
                if !got[0], a.brain.idleState.kind == .decorSit, a.brain.idleState.bagStage == 1, a.brain.gait.phase == .air {
                    got[0] = true; cells.append(labelled(composite(lab, ren, target, decor: true), "BEANBAG 1: hops up onto the bag, friend walks over", crop: crop))
                }
                if !got[1], a.brain.idleState.kind == .decorSit, a.brain.idleState.bagStage == 2, a.brain.idleState.phase == 2, b.brain.idleState.kind == .sit {
                    got[1] = true; cells.append(labelled(composite(lab, ren, target, decor: true), "2: sitting together (one on the bag, one beside it)", crop: crop))
                }
                if !got[2], got[1], a.brain.idleState.kind == .decorSit, a.brain.idleState.bagStage == 2, a.brain.idleState.phase == 2, a.brain.idleState.phaseT > 4 {
                    got[2] = true; cells.append(labelled(composite(lab, ren, target, decor: true), "3: still resting together", crop: crop))
                }
            }
            XCTAssertFalse(got.contains(false), "bag-sit frames caught \(got), a kind \(String(describing: a.brain.idleState.kind)), b kind \(String(describing: b.brain.idleState.kind)), session \(String(describing: a.brain.social?.kind))")
        }
        try save(sheet(cells, cols: 4, title: "Ball pass and beanbag sit-together (same scale, portrait game camera, cropped to the floor)"), "social_strip.png")
    }
}
