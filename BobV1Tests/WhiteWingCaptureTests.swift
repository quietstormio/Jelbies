//
//  WhiteWingCaptureTests.swift
//  Not a regression test: the look sheets of the candidate "whitewing" species (Features/WhiteWing.swift) with the REAL renderer when WW_DIR is set
//  (TEST_RUNNER_WW_DIR): next to Lavender, a six-view turnaround, the wing tint options, every wearable with the wings, motion frames and a light /
//  blush check. Skips without WW_DIR. The two tiny assertions at the end (white never clips flat, the tint ramp stays in range) always run.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class WhiteWingCaptureTests: XCTestCase {
    var S = 420
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 1) }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DayClock.shared.forcedHour = 12 }

    /// What a stage looks like: the body palette and the wing tint (nil = the art's own purple).
    struct Look { var name: String; var palette: Palette; var tint: WingTint? }
    static let lavender = Look(name: "Lavender", palette: JellyRoster.palette(3)!, tint: nil)
    static let white = Look(name: "Whitewing", palette: WhiteWing.palette, tint: WhiteWing.wingTint)

    private func dir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["WW_DIR"], !d.isEmpty else { throw XCTSkip("WW_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    @MainActor final class Stage {
        let look: Look, lab: SocialTests.Lab, ren: MelonRenderer, target: MTLTexture
        var worn = WornSet(), feat = FeatureSet(), mask = SleepMaskSet()
        init(look: Look, lab: SocialTests.Lab, ren: MelonRenderer, target: MTLTexture) { self.look = look; self.lab = lab; self.ren = ren; self.target = target }
        var rig: MotionRig { lab.rigs[0] }
    }

    private func makeStage(_ look: Look, seed: UInt64 = 3) throws -> Stage {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let lab = SocialTests.Lab(n: 1, positions: [SIMD2(0.2, 0.6)], quiet: true, seed: seed)
        SocialTests.keep.append(lab)
        let r = lab.rigs[0]
        r.skinner.autoBlink = false; r.brain.feature = .wings
        r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = false; r.brain.skinnerRef = r.skinner
        WearBody.install(MotionRig.renderMesh)
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: S, height: S)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: S, height: S, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        let st = Stage(look: look, lab: lab, ren: ren, target: device.makeTexture(descriptor: td)!)
        Self.keep.append(st)
        dress(st, nil, ticks: 3)
        for _ in 0..<30 { _ = skin(r) }
        return st
    }

    /// Fresh wardrobe + feature set wearing `wear` (nil = bare).
    private func dress(_ st: Stage, _ wear: WearLook?, ticks: Int = 3) {
        let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; Self.keep.append(w)
        let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f)
        f.setWingTint(0, st.look.tint)
        st.worn = w; st.feat = f
        for _ in 0..<ticks { tick(st, wear) }
    }
    private func tick(_ st: Stage, _ wear: WearLook?, dt: Float = 1.0 / 60) {
        let r = st.rig
        st.worn.tick(id: 0, brain: r.brain, sim: r.sim, outfit: wear.map { [$0.slot: $0] } ?? [:], role: .none, hideAll: false, dt: dt)
        var art: [String] = []
        for s in WearSlot.allCases where s != .feet { if let l = st.worn.shown(0, s), !l.art.isEmpty { art.append(l.art) } }
        st.feat.tick(id: 0, brain: r.brain, sim: r.sim, feature: .wings, worn: art, hideAll: false, dt: dt)
        if let s = st.feat.slot(0) { st.worn.setArtOverride(0, s.fit.hatVariant); r.brain.wingsFolded = s.fit.folded; r.brain.wingFlapLimit = s.fit.flapMax }
    }
    private func skin(_ r: MotionRig) -> [Float] {
        var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &d)
        return d
    }

    static func lookCamera(target: SIMD3<Float>, dir: SIMD3<Float>, dist: Float, lift: Float = 0.1) -> CameraState {
        let eye = target + dir * dist + SIMD3(0, dist * lift, 0)
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: lift > 3 ? SIMD3(0, 0, -1) : SIMD3(0, 1, 0))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: 1, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        return cam
    }

    /// A frame of the stage from `yaw` radians round his facing (0 front, pi back).
    private func shot(_ st: Stage, yaw: Float, ly: Float = 0.3, dist: Float = 3.3, lift: Float = 0.24, hour: Double = 12, masks: Bool = false, time: Float = 0.4, blush: Float = 0, mouth: Float = 0, palette: Palette? = nil, hideBody: Bool = false) -> UIImage {
        let r = st.rig, ren = st.ren
        let pose = r.sim.bodyPose(iterations: 3)
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_normalize(fwd)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let c = pose.centroid
        let cam = Self.lookCamera(target: SIMD3(c.x, c.y + ly, c.z), dir: dir, dist: dist, lift: lift)
        ren.dayHourOverride = hour
        let light = GameCamera.light(centroids: [r.sim.centroid()])
        ren.beginFrame()
        r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
        if hideBody { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
        let sk = skin(r)
        var f = sk.withUnsafeBufferPointer { p in st.worn.frame(theme: ren.room!.theme, time: time) { _ in p.baseAddress } }
        let ff = sk.withUnsafeBufferPointer { p in st.feat.frame { _ in p.baseAddress } }
        let base = UInt32(f.opaque.vertices.count)
        f.opaque.vertices += ff.vertices; f.opaque.indices += ff.indices.map { $0 + base }
        if hideBody { f.opaque = RoomMesh(); f.translucent = RoomMesh() }
        ren.room!.setWear(opaque: f.opaque, translucent: f.translucent, bounds: [])
        ren.room!.setShoes(RoomMesh())
        if masks { let m = st.mask.frame(theme: ren.room!.theme); ren.room!.setMasks(opaque: m.opaque, translucent: m.translucent) }
        else { ren.room!.setMasks(opaque: RoomMesh(), translucent: RoomMesh()) }
        ren.setJersey(st.worn.jersey(0), body: 0)
        ren.setMouth(mouth, body: 0); ren.setBlush(blush, body: 0)
        var fp = FrameParams()
        fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
        fp.exposure = 1; fp.meshAlpha = 0
        let pal = palette ?? st.look.palette
        fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
        ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(S), Float(S)))
        let cmd = ren.queue.makeCommandBuffer()!
        ren.draw(to: st.target, commandBuffer: cmd, showMesh: false)
        cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: S * S * 4)
        px.withUnsafeMutableBytes { st.target.getBytes($0.baseAddress!, bytesPerRow: S * 4, from: MTLRegionMake2D(0, 0, S, S), mipmapLevel: 0) }
        // the room has no back wall: the void behind the camera-facing-back views is painted the wall tone so the boards read cleanly
        if !hideBody { for p in 0..<(S * S) where px[4 * p] == 0 && px[4 * p + 1] == 0 && px[4 * p + 2] == 0 { px[4 * p] = 72; px[4 * p + 1] = 98; px[4 * p + 2] = 130 } }
        lastPixels = px
        return LockImage(w: S, h: S, bgra: px).uiImage()!
    }
    var lastPixels: [UInt8] = []

    // MARK: sheet helpers

    private func caption(_ img: UIImage, _ text: String, size: CGFloat = 17) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: img.size, format: fmt).image { _ in
            img.draw(at: .zero)
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: size), .foregroundColor: UIColor.white, .backgroundColor: UIColor(white: 0, alpha: 0.55)]
            (" " + text + " " as NSString).draw(at: CGPoint(x: 6, y: 6), withAttributes: attrs)
        }
    }
    /// A grid of cells at `cell` px (rows of images), with an optional header line, scaled so the sheet stays small enough.
    private func grid(_ rows: [[UIImage]], cell: CGFloat, header: String? = nil) -> UIImage {
        let hb: CGFloat = header == nil ? 0 : 34
        let w = CGFloat(rows.map(\.count).max() ?? 1) * cell, h = CGFloat(rows.count) * cell + hb
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            UIColor(white: 0.12, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h))
            if let header { (header as NSString).draw(at: CGPoint(x: 8, y: 6), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white]) }
            for (ri, row) in rows.enumerated() { for (ci, i) in row.enumerated() { i.draw(in: CGRect(x: CGFloat(ci) * cell, y: hb + CGFloat(ri) * cell, width: cell, height: cell)) } }
        }
    }
    /// PNG, scaled down in steps until the file is under 1.9 MB.
    private func write(_ img: UIImage, _ path: String) throws {
        var cur = img
        while true {
            let data = cur.pngData()!
            if data.count < 1_900_000 || cur.size.width < 600 { try data.write(to: URL(fileURLWithPath: path)); return }
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let ns = CGSize(width: (cur.size.width * 0.85).rounded(), height: (cur.size.height * 0.85).rounded())
            cur = UIGraphicsImageRenderer(size: ns, format: fmt).image { _ in cur.draw(in: CGRect(origin: .zero, size: ns)) }
        }
    }

    static let views: [(String, Float)] = [("front", 0), ("3/4", 0.65), ("side", 1.57), ("3/4 back", 2.4), ("back", .pi)]

    // MARK: 1 + 2 + 3: lavender comparison, turnaround, tints

    func testBoards() throws {
        let d = try dir()
        let lav = try makeStage(Self.lavender), wht = try makeStage(Self.white)
        // 1. next to Lavender, the same views (front, 3/4, side, 3/4 back, back)
        var rows: [[UIImage]] = []
        for st in [lav, wht] { rows.append(Self.views.map { caption(shot(st, yaw: $0.1), "\(st.look.name) \($0.0)") }) }
        try write(grid(rows, cell: 400, header: "Whitewing (bottom) next to Lavender (top): same body, same wings"), d + "/01_next_to_lavender.png")
        // 2. turnaround: front, 3/4, side, back, 3/4 back, top
        var cells: [UIImage] = []
        for (n, y) in [("front", Float(0)), ("3/4", 0.65), ("side", 1.57), ("back", Float.pi), ("3/4 back", 2.4)] { cells.append(caption(shot(wht, yaw: y), n)) }
        cells.append(caption(shot(wht, yaw: 0, ly: 0.3, dist: 1.1, lift: 3.6), "top"))
        try write(grid([Array(cells[0..<3]), Array(cells[3..<6])], cell: 520, header: "Whitewing turnaround"), d + "/02_turnaround.png")
        // 3. wing tint options (pearl, silver, iridescent), 3/4 front, 3/4 back, back, plus the original purple for reference
        var trows: [[UIImage]] = []
        let options: [WingTint?] = WhiteWing.tints.map { Optional($0) } + [nil]
        for t in options {
            let n = t?.name ?? "purple (Lavender's)"
            let st = try makeStage(Look(name: "Whitewing", palette: WhiteWing.palette, tint: t))
            trows.append([caption(shot(st, yaw: 0.65), "\(n) 3/4"), caption(shot(st, yaw: 2.4), "\(n) 3/4 back"), caption(shot(st, yaw: .pi), "\(n) back"), caption(shot(st, yaw: 1.57), "\(n) side")])
        }
        try write(grid(trows, cell: 420, header: "Wing tint options: pearl cream / silver-blue / iridescent pearl"), d + "/03_wing_tints.png")
    }

    // MARK: 4: every wearable with the wings

    func testWear() throws {
        let d = try dir()
        let wht = try makeStage(Self.white), lav = try makeStage(Self.lavender)
        let hatNeck: [WearLook] = WearLook.pieces.filter { $0.slot == .head || $0.slot == .neck }
        var report: [String] = []
        for l in WearLook.pieces {
            let fit = FeatureCompat.solve(.wings, worn: [l.art])
            report.append(String(format: "%@ (%@) folded=%d flapMax=%.0f dy=%.2f", l.rawValue, l.slot.rawValue, fit.folded ? 1 : 0, fit.flapMax, fit.wingDY))
        }
        try report.joined(separator: "\n").write(toFile: d + "/wear_wing_fit.txt", atomically: true, encoding: .utf8)
        // sheets per slot: a row = look, cells = front, 3/4 back, back (Whitewing) + Lavender 3/4 back for reference on the hat/neck sheet
        let slots: [(String, [WearLook])] = [("head", hatNeck.filter { $0.slot == .head }), ("neck", hatNeck.filter { $0.slot == .neck }),
                                             ("face", WearLook.pieces.filter { $0.slot == .face }), ("body", WearLook.pieces.filter { $0.slot == .body }),
                                             ("hands", WearLook.pieces.filter { $0.slot == .hands })]
        for (sn, ls) in slots where !ls.isEmpty {
            var page = 0, i = 0
            while i < ls.count {
                let chunk = Array(ls[i..<min(i + 4, ls.count)])
                var rows: [[UIImage]] = []
                for l in chunk {
                    dress(wht, l); dress(lav, l)
                    let ly: Float = l.slot == .head ? 0.5 : 0.3
                    let dist: Float = l.slot == .head ? 3.0 : 3.3
                    rows.append([caption(shot(wht, yaw: 0, ly: ly, dist: dist), "\(l.title) front", size: 15), caption(shot(wht, yaw: 2.4, ly: ly, dist: dist), "3/4 back", size: 15),
                                 caption(shot(wht, yaw: .pi, ly: ly, dist: dist), "back", size: 15), caption(shot(lav, yaw: 2.4, ly: ly, dist: dist), "Lavender 3/4 back", size: 15)])
                }
                try write(grid(rows, cell: 330, header: "Whitewing wearing: \(sn) (page \(page + 1))"), d + "/04_wear_\(sn)_\(page + 1).png")
                page += 1; i += 4
            }
        }
    }

    // MARK: 5: motion frames

    func testMotion() throws {
        let d = try dir()
        let st = try makeStage(Self.white)
        let r = st.rig
        r.brain.autonomy = false
        func frame(_ yaw: Float, _ label: String, extra: Float = 0) -> UIImage { caption(shot(st, yaw: yaw, dist: 3.3 + extra), label) }
        var rows: [[UIImage]] = []
        // walk
        let tg: [SIMD2<Float>] = [SIMD2(1.6, 0.4), SIMD2(-1.2, 1.0)]
        var which = 0
        r.brain.request(.goTo(tg[which]))
        for _ in 0..<90 { st.lab.tick(watching: false) }
        var walk: [UIImage] = []
        for k in 0..<4 {
            for _ in 0..<9 {
                st.lab.tick(watching: false)
                if r.brain.activity != .walking && r.brain.activity != .coming { which = 1 - which; r.brain.request(.goTo(tg[which])) }
                tick(st, nil)
            }
            walk.append(frame(0.65, "walk \(k + 1)", extra: 0.9))
        }
        rows.append(walk)
        // run
        r.brain.hurry = true
        var run: [UIImage] = []
        for k in 0..<4 {
            for _ in 0..<7 {
                st.lab.tick(watching: false)
                if r.brain.activity != .walking && r.brain.activity != .coming { which = 1 - which; r.brain.request(.goTo(tg[which])) }
                tick(st, nil)
            }
            run.append(frame(0.65, "run \(k + 1)", extra: 0.9))
        }
        rows.append(run)
        r.brain.hurry = false
        r.brain.abortScript(r.sim, r.skinner)
        for _ in 0..<90 { st.lab.tick(watching: false); tick(st, nil) }
        // flap-hop (the hop with the flap): frames across the jump
        r.brain.idleForced = true; r.brain.amplitude = 1
        var hop: [UIImage] = []
        if r.brain.idleStart(.flapHop, r.sim) {
            var n = 0
            while n < 150 && hop.count < 4 {
                st.lab.tick(watching: false); tick(st, nil); n += 1
                if n % 16 == 8 { hop.append(frame(0.65, String(format: "flap-hop %d (flap %.0f)", hop.count + 1, st.feat.slot(0)?.flap ?? 0), extra: 0.7)) }
            }
        }
        rows.append(hop)
        // flourish: happy bounces, wings fluttering with the body
        for _ in 0..<150 { st.lab.tick(watching: false); tick(st, nil) }
        var joy: [UIImage] = []
        r.brain.idleForced = true
        if r.brain.idleStart(.bounce, r.sim) {
            var n = 0
            while n < 140 && joy.count < 4 {
                st.lab.tick(watching: false); tick(st, nil); n += 1
                if n % 14 == 6 { joy.append(caption(shot(st, yaw: 0.2, dist: 3.1, blush: r.brain.blushNow), String(format: "bounce %d (blush %.2f)", joy.count + 1, r.brain.blushNow))) }
            }
        }
        rows.append(joy)
        try write(grid(rows.filter { !$0.isEmpty }, cell: 360, header: "Whitewing motion: walk / run / flap-hop / happy bounce"), d + "/05_motion_a.png")
        // sleep (wings lie flat and hide, the eye mask goes on)
        r.brain.abortScript(r.sim, r.skinner)
        for _ in 0..<60 { st.lab.tick(watching: false) }
        r.brain.sleepEnabled = false; r.brain.idleForced = true
        var sleepCells: [UIImage] = []
        if r.brain.idleStart(.sleep, r.sim) {
            r.brain.sleep.hold = 5000
            var f = 0
            while !r.brain.isNapping && f < 60 * 40 { st.lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); f += 1 }
            for _ in 0..<120 { st.lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); st.mask.tick(id: 0, brain: r.brain, sim: r.sim, dt: r.sim.stepDt); st.mask.stepPuffs(dt: 1.0 / 60); tick(st, nil) }
            for (n, y) in [("sleep front", Float(0)), ("sleep 3/4", 0.65), ("sleep side", 1.57), ("sleep 3/4 back", 2.4)] { sleepCells.append(caption(shot(st, yaw: y, hour: 21, masks: true), n)) }
        }
        try write(grid([sleepCells], cell: 420, header: "Whitewing asleep (night light)"), d + "/05_motion_sleep.png")
    }

    // MARK: light + blush check

    /// White must not clip flat: sample the body pixels at several hours of the day and in the blush peak, and report the fraction at 255 plus the luminance spread.
    func testLightAndBlush() throws {
        let d = try dir()
        let wht = try makeStage(Self.white), lav = try makeStage(Self.lavender)
        var report: [String] = []
        var cells: [UIImage] = []
        func stats(_ label: String, _ px: [UInt8], bg: [UInt8]) {
            var n = 0, clipped = 0, sum = 0.0, lo = 255.0, hi = 0.0
            for p in 0..<(S * S) {
                var diff = 0
                for c in 0..<3 { diff = max(diff, abs(Int(px[4 * p + c]) - Int(bg[4 * p + c]))) }
                if diff > 6 {
                    let l = 0.114 * Double(px[4 * p]) + 0.587 * Double(px[4 * p + 1]) + 0.299 * Double(px[4 * p + 2])
                    n += 1; sum += l; lo = min(lo, l); hi = max(hi, l)
                    if px[4 * p] > 250 && px[4 * p + 1] > 250 && px[4 * p + 2] > 250 { clipped += 1 }
                }
            }
            report.append(String(format: "%@: body px %d, mean luma %.1f, min %.0f, max %.0f, flat-white (>250 all channels) %.2f%%", label, n, sum / Double(max(n, 1)), lo, hi, 100 * Double(clipped) / Double(max(n, 1))))
        }
        for (hn, h) in [("morning 8", 8.0), ("noon 12", 12.0), ("dusk 18", 18.0), ("night 22", 22.0)] {
            let img = shot(wht, yaw: 0.3, hour: h)
            // the empty room for the same hour: hide the body by sending it under the floor
            let px = lastPixels
            stats("whitewing \(hn)", px, bg: bgPixels(wht, yaw: 0.3, hour: h))
            cells.append(caption(img, "whitewing \(hn)"))
            cells.append(caption(shot(lav, yaw: 0.3, hour: h), "lavender \(hn)"))
        }
        // blush at the usual peaks, close up (and the resting face)
        var face: [UIImage] = []
        for (n, b) in [("resting (no blush)", Float(0)), ("blush 0.5", 0.5), ("blush 0.85", 0.85)] {
            face.append(caption(shot(wht, yaw: 0, ly: 0.14, dist: 2.1, blush: b), "whitewing \(n)"))
        }
        face.append(caption(shot(lav, yaw: 0, ly: 0.14, dist: 2.1, blush: 0.85), "lavender blush 0.85"))
        face.append(caption(shot(wht, yaw: 0, ly: 0.14, dist: 2.1, blush: 0.5, mouth: 0.8), "whitewing open mouth + blush"))
        try write(grid([Array(cells[0..<4]), Array(cells[4..<8])], cell: 420, header: "Whitewing vs Lavender through the day (morning, noon, dusk, night)"), d + "/06_light_day.png")
        try write(grid([Array(face[0..<3]), Array(face[3..<5])], cell: 480, header: "Face and cheek blush, default (resting) vs peak"), d + "/06_face_blush.png")
        try report.joined(separator: "\n").write(toFile: d + "/light_stats.txt", atomically: true, encoding: .utf8)
    }

    /// The same view with no body drawn (pushed far below the floor), for pixel-difference stats.
    private func bgPixels(_ st: Stage, yaw: Float, hour: Double) -> [UInt8] {
        _ = shot(st, yaw: yaw, hour: hour, hideBody: true)
        return lastPixels
    }

    // MARK: invariants (always run)

    func testWhiteStaysBelowClip() {
        let p = WhiteWing.palette
        XCTAssertLessThan(max(p.flesh.x, p.flesh.y, p.flesh.z), 0.95, "white leaves headroom for the key light")
        XCTAssertGreaterThan(p.flesh.x - p.fleshDeep.x, 0.15, "the shaded tone is clearly darker than the lit one, so the form reads")
        XCTAssertTrue(p.matte)
        for t in WhiteWing.tints {
            for l in stride(from: Float(0.2), through: 1.0, by: 0.03) {
                let c = t.recolour(SIMD3(l, l, l))
                XCTAssertTrue((0.5...1.6).contains(c.x) && (0.5...1.6).contains(c.y) && (0.5...1.6).contains(c.z))
            }
        }
        XCTAssertEqual(WhiteWing.parse("whitewing"), 0)
        XCTAssertEqual(WhiteWing.parse("WhiteWing:3"), 3)
        XCTAssertNil(WhiteWing.parse("teddy"))
        XCTAssertNil(WhiteWing.parse(nil))
        XCTAssertFalse(WhiteWing.isForced(1), "no launch argument in a test run: nobody is forced")
    }
}
