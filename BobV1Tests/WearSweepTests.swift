//
//  WearSweepTests.swift
//  Not a regression test: the wardrobe sweep. When WEAR4_DIR is set (TEST_RUNNER_WEAR4_DIR) every non-shoe wearable is rendered with the REAL renderer on
//  all four Jelbies (Bob, Pip with tail + spines, Moss with the daisy, Lavender with wings): front, 3/4, (back for back pieces), a mid-walk frame and, for
//  head and face pieces, a sleeping frame. Per-slot contact sheets go to WEAR4_DIR/wear4_<slot>.png (static views) and wear4_<slot>_walk.png (walk + sleep),
//  and wear4_new_items.png shows the newest pieces on all four. WEAR4_ONLY=comma separated look names (or slot names) limits the run;
//  WEAR4_TAG names the output files (default none).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class WearSweepTests: XCTestCase {
    let S = 400
    nonisolated(unsafe) static var keep: [AnyObject] = []
    typealias Outfit = [WearSlot: WearLook]

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 1) }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DayClock.shared.forcedHour = 12 }

    static let names = ["Bob", "Pip", "Moss", "Lavender"]
    /// The pieces added by this sweep (wear4_new_items.png).
    static let newPieces: [WearLook] = WearGenerated.rows.filter { $0.batch >= 4 }.map(\.look)

    /// Shipped pieces rebuilt in this sweep.
    static let upgraded: [WearLook] = [.glassesRound, .sunglassesStar, .heartShades, .gogglesAviator, .monocleGold, .sashPink, .sashSky, .bibPink, .bibSky, .bandanaCoral, .bandanaMint,
                                       .tutuPink, .capeHero, .pearls, .lei, .whistleCoach, .backpackSky, .scarfCosy, .scarfSky, .bowtiePink, .bowtieSky]

    private func env(_ k: String) -> String? { ProcessInfo.processInfo.environment[k].flatMap { $0.isEmpty ? nil : $0 } }
    private func dir() throws -> String {
        guard let d = env("WEAR4_DIR") else { throw XCTSkip("WEAR4_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    private func looks() -> [WearLook] {
        var all = WearLook.pieces
        if let only = env("WEAR4_ONLY")?.split(separator: ",").map(String.init) {
            all = all.filter { l in only.contains(l.rawValue) || only.contains(l.slot.rawValue) || (only.contains("new") && Self.newPieces.contains(l)) || (only.contains("upg") && Self.upgraded.contains(l)) }
        }
        return all
    }

    /// One Jelbie on his own rig + renderer.
    @MainActor final class Stage {
        let id: Int, lab: SocialTests.Lab, ren: MelonRenderer, target: MTLTexture
        var worn = WornSet(), feat = FeatureSet(), mask = SleepMaskSet()
        init(id: Int, lab: SocialTests.Lab, ren: MelonRenderer, target: MTLTexture) { self.id = id; self.lab = lab; self.ren = ren; self.target = target }
        var rig: MotionRig { lab.rigs[0] }
    }

    private func makeStage(_ id: Int) throws -> Stage {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let lab = SocialTests.Lab(n: 1, positions: [SIMD2(0.2, 0.6)], quiet: true, seed: 3)
        SocialTests.keep.append(lab)
        let r = lab.rigs[0]
        r.skinner.autoBlink = false; r.brain.feature = JellyRoster.feature(id)
        r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        WearBody.install(MotionRig.renderMesh)
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: S, height: S)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: S, height: S, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        let st = Stage(id: id, lab: lab, ren: ren, target: device.makeTexture(descriptor: td)!)
        Self.keep.append(st)
        for _ in 0..<30 { _ = skin(r) }
        return st
    }

    /// Fresh wardrobe + feature set wearing `look` (a few ticks so the carry settles).
    private func dress(_ st: Stage, _ look: WearLook, ticks: Int = 3) {
        let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; Self.keep.append(w)
        let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f)
        st.worn = w; st.feat = f
        for _ in 0..<ticks { tick(st, look) }
    }
    private func tick(_ st: Stage, _ look: WearLook, dt: Float = 1.0 / 60) {
        let r = st.rig
        st.worn.tick(id: 0, brain: r.brain, sim: r.sim, outfit: [look.slot: look], role: .none, hideAll: false, dt: dt)
        var art: [String] = []
        for s in WearSlot.allCases where s != .feet { if let l = st.worn.shown(0, s), !l.art.isEmpty { art.append(l.art) } }
        st.feat.tick(id: 0, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(st.id), worn: art, hideAll: false, dt: dt)
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
        cam.view = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: 1, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        return cam
    }

    /// Where the camera looks per slot: (look height above the centroid, distance).
    private func framing(_ slot: WearSlot, full: Bool) -> (Float, Float) {
        if full { return (0.3, 3.3) }
        switch slot {
        case .head: return (0.50, 2.8)
        case .face: return (0.40, 2.1)
        case .neck: return (0.12, 2.9)
        case .body: return (0.08, 3.2)
        case .hands: return (0.25, 2.7)
        case .feet: return (0.0, 3.0)
        }
    }

    /// A frame of the stage from `yaw` radians round his facing.
    private func shot(_ st: Stage, _ look: WearLook, yaw: Float, full: Bool = false, masks: Bool = false, extra: Float = 0, time: Float = 0.4, tight: Bool = false, focus: (Float, Float)? = nil, side: Float = 0) -> UIImage {
        let r = st.rig, ren = st.ren
        let pose = r.sim.bodyPose(iterations: 3)
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_normalize(fwd)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let c = pose.centroid
        var (ly, dist) = framing(look.slot, full: full)
        if tight { ly = 0.05; dist = 2.0 }
        if let focus { (ly, dist) = focus }
        let cam = Self.lookCamera(target: SIMD3(c.x, c.y + ly, c.z) + SIMD3(dir.z, 0, -dir.x) * side, dir: dir, dist: dist + extra)
        ren.dayHourOverride = masks ? 15 : 12
        let light = GameCamera.light(centroids: [r.sim.centroid()])
        ren.beginFrame()
        r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
        let sk = skin(r)
        if st.worn.shown(0, .hands) != nil { st.worn.setArms(0, GameCare.armFrames(brain: r.brain, sim: r.sim)) }
        var f = sk.withUnsafeBufferPointer { p in st.worn.frame(theme: ren.room!.theme, time: time) { _ in p.baseAddress } }
        let ff = sk.withUnsafeBufferPointer { p in st.feat.frame { _ in p.baseAddress } }
        let base = UInt32(f.opaque.vertices.count)
        f.opaque.vertices += ff.vertices; f.opaque.indices += ff.indices.map { $0 + base }
        ren.room!.setWear(opaque: f.opaque, translucent: f.translucent, bounds: [])
        ren.room!.setShoes(RoomMesh())
        if masks { let m = st.mask.frame(theme: ren.room!.theme); ren.room!.setMasks(opaque: m.opaque, translucent: m.translucent) }
        else { ren.room!.setMasks(opaque: RoomMesh(), translucent: RoomMesh()) }
        ren.setJersey(st.worn.jersey(0), body: 0)
        ren.setMouth(0, body: 0)
        var fp = FrameParams()
        fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
        fp.exposure = 1; fp.meshAlpha = 0
        let pal = JellyRoster.palette(st.id) ?? PaletteKey.blue.palette
        fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
        ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(S), Float(S)))
        let cmd = ren.queue.makeCommandBuffer()!
        ren.draw(to: st.target, commandBuffer: cmd, showMesh: false)
        cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: S * S * 4)
        px.withUnsafeMutableBytes { st.target.getBytes($0.baseAddress!, bytesPerRow: S * 4, from: MTLRegionMake2D(0, 0, S, S), mipmapLevel: 0) }
        return LockImage(w: S, h: S, bgra: px).uiImage()!
    }

    // MARK: sheet helpers

    private func caption(_ img: UIImage, _ text: String) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: img.size, format: fmt).image { _ in
            img.draw(at: .zero)
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.white, .backgroundColor: UIColor(white: 0, alpha: 0.55)]
            (" " + text + " " as NSString).draw(at: CGPoint(x: 6, y: 6), withAttributes: attrs)
        }
    }
    private func stack(_ rows: [[UIImage]], header: String? = nil) -> UIImage {
        let cell = CGFloat(S), hb: CGFloat = header == nil ? 0 : 34
        let w = CGFloat(rows.map(\.count).max() ?? 1) * cell, h = CGFloat(rows.count) * cell + hb
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            UIColor(white: 0.12, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h))
            if let header { (header as NSString).draw(at: CGPoint(x: 8, y: 6), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white]) }
            for (ri, row) in rows.enumerated() { for (ci, i) in row.enumerated() { i.draw(in: CGRect(x: CGFloat(ci) * cell, y: hb + CGFloat(ri) * cell, width: cell, height: cell)) } }
        }
    }
    private func write(_ img: UIImage, _ path: String) throws { try img.pngData()!.write(to: URL(fileURLWithPath: path)) }

    // MARK: the sweep

    /// Cells: [look][jelbie] -> (static: front, 3/4, back?), (walk: 1 frame), (sleep: 1 frame, head and face only)
    struct Cells { var front: Data?, tq: Data?, side: Data?, backq: Data?, back: Data?, walk: Data?, sleep: Data? }

    func testSweep() throws {
        let d = try dir()
        let tag = env("WEAR4_TAG") ?? ""
        let list = looks()
        guard !list.isEmpty else { throw XCTSkip("nothing selected") }
        var cells: [WearLook: [Cells]] = [:]
        for l in list { cells[l] = Array(repeating: Cells(), count: 4) }
        for id in 0..<4 {
            DayClock.shared.forcedHour = 12
            let st = try makeStage(id)
            let tg: [SIMD2<Float>] = [SIMD2(1.6, 0.4), SIMD2(-1.2, 1.0)]
            // 1. static views
            for l in list {
                dress(st, l)
                var c = cells[l]![id]
                c.front = caption(shot(st, l, yaw: 0), "\(Self.names[id]) \(l.rawValue) front").pngData()
                c.tq = caption(shot(st, l, yaw: 0.65), "\(Self.names[id]) \(l.title) 3/4").pngData()
                if l.slot == .neck || l.slot == .body { c.side = caption(shot(st, l, yaw: 1.5), "\(Self.names[id]) side").pngData(); c.backq = caption(shot(st, l, yaw: 2.4), "\(Self.names[id]) 3/4 back").pngData() }
                if l.anchor == .back || l.slot == .body || l.slot == .neck { c.back = caption(shot(st, l, yaw: .pi), "\(Self.names[id]) back").pngData() }
                cells[l]![id] = c
            }
            // 2. mid-walk
            let r = st.rig
            var which = 0
            r.brain.request(.goTo(tg[which]))
            for _ in 0..<90 { st.lab.tick(watching: false) }
            for l in list {
                dress(st, l, ticks: 1)
                for _ in 0..<26 {
                    st.lab.tick(watching: false)
                    if r.brain.activity != .walking && r.brain.activity != .coming { which = 1 - which; r.brain.request(.goTo(tg[which])) }
                    tick(st, l)
                }
                cells[l]![id].walk = caption(shot(st, l, yaw: 0.65, extra: 0.9), "\(Self.names[id]) mid-walk").pngData()
            }
            // 3. asleep (head and face pieces poof off, the eye mask goes on)
            r.brain.abortScript(r.sim, r.skinner)
            for _ in 0..<60 { st.lab.tick(watching: false) }
            r.brain.sleepEnabled = false
            r.brain.idleForced = true
            if r.brain.idleStart(.sleep, r.sim) {
                r.brain.sleep.hold = 5000
                var f = 0
                while !r.brain.isNapping && f < 60 * 40 { st.lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); f += 1 }
                for _ in 0..<45 { st.lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); st.mask.tick(id: 0, brain: r.brain, sim: r.sim, dt: r.sim.stepDt); st.mask.stepPuffs(dt: 1.0 / 60) }
                for l in list where l.slot == .head || l.slot == .face {
                    dress(st, l, ticks: 1)
                    for _ in 0..<50 {
                        st.lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
                        st.mask.tick(id: 0, brain: r.brain, sim: r.sim, dt: r.sim.stepDt); st.mask.stepPuffs(dt: 1.0 / 60)
                        tick(st, l); st.worn.stepPuffs(dt: 1.0 / 60)
                    }
                    cells[l]![id].sleep = caption(shot(st, l, yaw: 0.65, masks: true), "\(Self.names[id]) asleep").pngData()
                }
            }
        }
        // sheets per slot
        for slot in [WearSlot.head, .face, .neck, .body, .hands] {
            let ls = list.filter { $0.slot == slot }
            if ls.isEmpty { continue }
            var pageNo = 0
            let per = slot == .head || slot == .face || slot == .neck ? 3 : 3
            var i = 0
            while i < ls.count {
                let chunk = Array(ls[i..<min(i + per, ls.count)])
                // static page: front + 3/4 (+ back for neck/body) of the four Jelbies
                var rows: [[UIImage]] = [], wrows: [[UIImage]] = []
                for l in chunk {
                    var row: [UIImage] = [], row2: [UIImage] = [], wrow: [UIImage] = []
                    let wide = slot == .body || slot == .neck
                    for id in 0..<4 {
                        let c = cells[l]![id]
                        var mine: [UIImage] = [c.front, c.tq].compactMap { $0.flatMap { UIImage(data: $0) } }
                        if wide { mine += [c.side, c.backq, c.back].compactMap { $0.flatMap { UIImage(data: $0) } } }
                        if wide && id >= 2 { row2 += mine } else { row += mine }
                        wrow += [c.walk, c.sleep].compactMap { $0.flatMap { UIImage(data: $0) } }
                    }
                    rows.append(row); if wide { rows.append(row2) }
                    wrows.append(wrow)
                }
                let suffix = (ls.count > per ? "_p\(pageNo)" : "") + tag
                try write(stack(rows, header: "\(slot.rawValue): \(chunk.map(\.rawValue).joined(separator: ", ")) (Bob, Pip, Moss, Lavender; front | 3/4\(slot == .body || slot == .neck ? " | side | 3/4 back | back (Bob + Pip on the first row, Moss + Lavender on the second)" : ""))"), d + "/wear4_\(slot.rawValue)\(suffix).png")
                try write(stack(wrows, header: "\(slot.rawValue) walk\(slot == .head || slot == .face ? " + asleep" : ""): \(chunk.map(\.rawValue).joined(separator: ", "))"), d + "/wear4_\(slot.rawValue)_walk\(suffix).png")
                pageNo += 1; i += per
            }
        }
        // the newest pieces: 3/4 on all four, full-body for the body-and-neck pieces
        let fresh = list.filter { Self.newPieces.contains($0) }
        if !fresh.isEmpty {
            var rows: [[UIImage]] = []
            for l in fresh { rows.append((0..<4).compactMap { cells[l]![$0].tq.flatMap { UIImage(data: $0) } }) }
            try write(stack(rows, header: "NEW pieces on Bob, Pip, Moss, Lavender (3/4)"), d + "/wear4_new_items\(tag).png")
        }
    }

    /// The shop thumbnails of every wearable (each piece on a Jelbie): wear4_thumbs.png.
    func testStoreThumbs() throws {
        let d = try dir()
        let items = StoreCatalog.wearItems.filter { !($0.wear?.isShoe ?? true) }
        let t0 = Date()
        var imgs: [(String, UIImage)] = []
        for it in items { if let im = StoreThumb.image(for: it) { imgs.append((it.name, im)) } }
        let ms = Date().timeIntervalSince(t0) * 1000
        let again = Date()
        for it in items { _ = StoreThumb.image(for: it) }
        let cached = Date().timeIntervalSince(again) * 1000
        print("STORETHUMB first pass \(Int(ms)) ms for \(items.count) items, cached pass \(Int(cached)) ms")
        XCTAssertEqual(imgs.count, items.count)
        let cols = 10, cell: CGFloat = 200
        let rows = (imgs.count + cols - 1) / cols
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(cols) * cell, height: CGFloat(rows) * (cell + 22)), format: fmt).image { _ in
            UIColor(red: 1, green: 0.93, blue: 0.9, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: CGFloat(cols) * cell, height: CGFloat(rows) * (cell + 22)))
            for (k, (title, im)) in imgs.enumerated() {
                let x = CGFloat(k % cols) * cell, y = CGFloat(k / cols) * (cell + 22)
                im.draw(in: CGRect(x: x, y: y, width: cell, height: cell))
                (title as NSString).draw(at: CGPoint(x: x + 4, y: y + cell + 2), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.black])
            }
        }
        try write(sheet, d + "/wear4_thumbs.png")
    }

    /// Closeups of the Diamond J chain on all four Jelbies (front, 3/4, side, back, mid-walk, and the twinkle at three moments): wear4_diamond_j.png.
    func testDiamondCloseups() throws {
        let d = try dir()
        let l = WearLook.diamondJ
        var rows: [[UIImage]] = [], bigRows: [[UIImage]] = []
        for id in 0..<4 {
            DayClock.shared.forcedHour = 12
            let st = try makeStage(id)
            dress(st, l)
            var row: [UIImage] = []
            for (label, yaw, t) in [("front t0", Float(0), Float(0.35)), ("front t1", Float(0), Float(1.05)), ("front t2", Float(0), Float(1.85)), ("3/4", Float(0.65), Float(0.7)), ("side", Float(1.5), Float(0.7)), ("back", Float.pi, Float(0.7))] {
                row.append(caption(shot(st, l, yaw: yaw, time: t, focus: (-0.14, 2.35)), "\(Self.names[id]) \(label)"))
            }
            let r = st.rig
            r.brain.request(.goTo(SIMD2(1.6, 0.4)))
            for _ in 0..<90 { st.lab.tick(watching: false) }
            dress(st, l, ticks: 1)
            for _ in 0..<26 { st.lab.tick(watching: false); tick(st, l) }
            row.append(caption(shot(st, l, yaw: 0.65, extra: 0.6, time: 0.9, focus: (-0.14, 2.35)), "\(Self.names[id]) mid-walk"))
            rows.append(row)
            // large close-ups of the J and the chain (front, a twist to the side, tilted), then the game-distance pair
            var big: [UIImage] = []
            let r2 = st.rig; r2.brain.abortScript(r2.sim, r2.skinner)
            for _ in 0..<40 { st.lab.tick(watching: false) }
            dress(st, l)
            for (label, yaw, t, fo, sd) in [("J close", Float(0), Float(0.35), (Float(-0.28), Float(1.7)), Float(0)), ("J close t2", Float(0.35), Float(1.4), (Float(-0.28), Float(1.7)), Float(0)),
                                            ("chain close", Float(0.9), Float(0.7), (Float(-0.12), Float(1.6)), Float(0)), ("chain close 2", Float(-0.7), Float(1.1), (Float(-0.12), Float(1.6)), Float(0))] {
                big.append(caption(shot(st, l, yaw: yaw, time: t, focus: fo, side: sd), "\(Self.names[id]) \(label)"))
            }
            for (yaw, t) in [(Float(0), Float(0.5)), (Float(0.65), Float(1.3))] { big.append(caption(shot(st, l, yaw: yaw, full: true, extra: 3.4, time: t), "\(Self.names[id]) game distance")) }
            bigRows.append(big)
        }
        try write(stack(rows, header: "Diamond J chain: Bob, Pip, Moss, Lavender (front at three twinkle moments, 3/4, side, back, mid-walk)"), d + "/wear4_diamond_j.png")
        try write(stack(bigRows, header: "Diamond J chain close-ups (J, J at another twinkle, chain 3/4, chain other side) + game distance"), d + "/wear4_diamond_j_close.png")
    }

    /// The held-back pieces at about the game camera's distance (a whole Jelbie in a small frame), front and 3/4 on all four: wear4_five_game_distance.png.
    func testHeldBackPiecesAtGameDistance() throws {
        let d = try dir()
        let looks: [WearLook] = [.cardiganCable, .vestPuffer, .scarfSilk, .chainGold, .diamondJ]
        var rows: [[UIImage]] = []
        for l in looks { rows.append([]) }
        for id in 0..<4 {
            DayClock.shared.forcedHour = 12
            let st = try makeStage(id)
            for (k, l) in looks.enumerated() {
                dress(st, l)
                for yaw in [Float(0), Float(0.65)] {
                    rows[k].append(caption(shot(st, l, yaw: yaw, full: true, extra: 3.4), "\(Self.names[id]) \(l.title)"))
                }
            }
        }
        try write(stack(rows, header: "Held-back pieces at game-camera distance: Bob, Pip, Moss, Lavender (front | 3/4)"), d + "/wear4_five_game_distance.png")
    }

    /// Writes Pip's shipped spike + tail geometry (rest space) to WEAR4_DIR/pip_geometry.json: the Blender generator of the Pip wardrobe variants clears it
    /// (tools/make_wear4/work/kit5.py reads tools/make_wear4/art/pip_geometry.json), so a respaced spike row or a new tail moves the variants with it.
    func testDumpPipGeometry() throws {
        let d = try dir()
        guard let p = FeatureMeshes.prepare(.spines, placement: FeatureMeshes.Placement(), body: WearBody.shared) else { return XCTFail("no spines") }
        var spikes: [[Float]] = []
        for (k, part) in p.parts.enumerated() where part.name.hasPrefix("spike") || part.name.hasPrefix("tail") {
            _ = k
            for v in part.first..<(part.first + part.count) { let r = p.rest[v]; spikes.append([r.x, r.y, r.z]) }
        }
        let sh = TailBean.shape
        var spheres: [[Double]] = []
        var t = 0.0
        while t <= sh.length { let c = sh.point(t); spheres.append([c.x, c.y, c.z, sh.radius(t) * sh.ys]); t += 0.02 }
        let obj: [String: Any] = ["spikeVertices": spikes, "tailSpheres": spheres, "restTop": Double(FeatureSpec.shared.top)]
        try JSONSerialization.data(withJSONObject: obj).write(to: URL(fileURLWithPath: d + "/pip_geometry.json"))
        MotionLog.write("PIPGEOM \(spikes.count) spike vertices, \(spheres.count) tail spheres")
    }
}
