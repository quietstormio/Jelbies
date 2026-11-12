//
//  EmoteInventoryCaptureTests.swift
//  Not a regression test: one 5-tile picture strip (about 1200 x 260, JPEG) for every emote of the inventory, with the REAL renderer (lab rigs, wardrobe + feature layer, decor in the room).
//  Set EMOTE_INV_DIR (TEST_RUNNER_EMOTE_INV_DIR) to write them; EMOTE_INV_ONLY="hiccup,social.boop" filters by code.
//  File name = the inventory code with non-alphanumerics replaced by "_"; each finished strip also writes _parts/<file>.json (code, file, seconds_captured, cast) and each skipped one
//  _parts/<file>.skip.json (code, file: null, why). The methods are split so that one failing emote does not lose the rest.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class EmoteInventoryCaptureTests: XCTestCase {
    static let W = 480, H = 520
    static let castNames = ["Bob (blue)", "Pip (yellow)", "Moss (green)", "Lavender (purple)", "Teddy (brown)", "Pearl (white)"]
    nonisolated(unsafe) static var keep: [AnyObject] = []
    nonisolated(unsafe) static var shared: (MelonRenderer, MTLTexture)?

    override func setUp() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        DayClock.shared.forcedHour = 12
        ToyTuning.settle = 0
    }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    struct Skip: Error { let why: String }

    enum Mode { case idle(IdleKind), social, fixed }
    struct Job {
        var code: String
        var chars: [Int]
        var positions: [SIMD2<Float>]
        var mode: Mode
        var maxSeconds: Float = 30
        var decor: [PlacedDecor] = []
        var setup: (SocialTests.Lab) -> Bool
        var each: ((MotionRig) -> Void)? = nil
        var seed: UInt64 = 3
        var lead: Float = 0          // (fixed mode: seconds skipped before the first tile)
        var storm = false            // (the weather lab: the storm at its peak, drawn at 19:00 with rain; stepped by the weather room)
    }
    nonisolated(unsafe) static var stormRoom: WeatherTests.Room?

    // MARK: files

    static var outDir: String? { ProcessInfo.processInfo.environment["EMOTE_INV_DIR"].flatMap { $0.isEmpty ? nil : $0 } }
    static func fileName(_ code: String) -> String { String(code.map { $0.isLetter || $0.isNumber ? $0 : "_" }) + ".jpg" }
    static func writePart(_ dir: String, _ file: String, _ obj: [String: Any]) {
        try? FileManager.default.createDirectory(atPath: dir + "/_parts", withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) { try? d.write(to: URL(fileURLWithPath: dir + "/_parts/" + file)) }
    }

    // MARK: rig pieces (as FeatureCaptureTests, without the shoes)

    struct Char { var id: Int }
    final class Dressed { var worn: [WornSet] = [], feats: [FeatureSet] = [] }

    func makeLab(_ job: Job) -> (SocialTests.Lab, Dressed) {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); SoccerState.shared.reset()
        if !job.decor.isEmpty { DecorField.shared.set(job.decor) }
        let lab: SocialTests.Lab
        if job.storm {
            let book = WeatherBook(defaults: UserDefaults(suiteName: "emote-inv-\(UUID().uuidString)")!)
            let room = WeatherTests.Room(book: book)
            Self.keep.append(room); Self.stormRoom = room; lab = room.lab
        } else {
            lab = SocialTests.Lab(n: job.positions.count, positions: job.positions, quiet: true, seed: job.seed)
        }
        SocialTests.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            let id = job.chars[k % job.chars.count]
            r.skinner.autoBlink = false; r.brain.feature = JellyRoster.feature(id); r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        }
        WearBody.install(MotionRig.renderMesh)
        let d = Dressed()
        for (k, r) in lab.rigs.enumerated() {
            let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; Self.keep.append(w)
            let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f)
            d.worn.append(w); d.feats.append(f)
            for _ in 0..<3 { wearTick(d, k, r, job.chars[k % job.chars.count]) }
        }
        return (lab, d)
    }
    func wearTick(_ d: Dressed, _ k: Int, _ r: MotionRig, _ id: Int) {
        let w = d.worn[k], f = d.feats[k]
        w.tick(id: 0, brain: r.brain, sim: r.sim, outfit: [:], role: .none, hideAll: false, dt: 1.0 / 60)
        var art: [String] = []
        for s in WearSlot.allCases where s != .feet { if let l = w.shown(0, s), !l.art.isEmpty { art.append(l.art) } }
        f.tick(id: 0, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(id), worn: art, hideAll: false, dt: 1.0 / 60)
        if let s = f.slot(0) { w.setArtOverride(0, s.fit.hatVariant); r.brain.wingsFolded = s.fit.folded; r.brain.wingFlapLimit = s.fit.flapMax }
    }
    func stepLab(_ lab: SocialTests.Lab, _ d: Dressed, _ job: Job) {
        if job.storm, let room = Self.stormRoom { room.step() } else { lab.tick(watching: false) }
        DecorField.shared.tick(dt: 1.0 / 60)
        for (k, r) in lab.rigs.enumerated() {
            r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            wearTick(d, k, r, job.chars[k % job.chars.count])
        }
        job.each?(lab.rigs[0])
    }

    func renderer(_ lab: SocialTests.Lab) throws -> (MelonRenderer, MTLTexture) {
        if let s = Self.shared { return s }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let r0 = lab.rigs[0]
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r0.sim.edges, particleCount: r0.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: Self.W, height: Self.H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Self.W, height: Self.H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        let s = (ren, device.makeTexture(descriptor: td)!)
        Self.shared = s
        return s
    }

    static func lookCamera(target: SIMD3<Float>, dir: SIMD3<Float>, dist: Float, aspect: Float, lift: Float) -> CameraState {
        let eye = target + dir * dist + SIMD3(0, dist * lift, 0)
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        return cam
    }

    func composite(_ lab: SocialTests.Lab, _ d: Dressed, _ job: Job, _ ren: MelonRenderer, _ target: MTLTexture, cam: CameraState) -> LockImage {
        let W = Self.W, H = Self.H
        ren.dayHourOverride = job.storm ? 19 : 12
        if job.storm, let room = Self.stormRoom { var l = room.book.look(); l.rain = max(l.rain, 0.9); ren.weatherLook = l } else { ren.weatherLook = WeatherLook() }
        let f0 = DecorField.shared
        ren.room!.setDecorStatic(DecorModels.build(feet: f0.feet, field: f0, time: 0.4))
        func shot(only: Int?) -> LockImage {
            let k = only ?? 0
            let light = GameCamera.light(centroids: lab.rigs.map { $0.sim.centroid() })
            ren.beginFrame()
            let r = lab.rigs[k]
            r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            if only == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
            if let o = only {
                var sk = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &sk)
                var f = sk.withUnsafeBufferPointer { p in d.worn[o].frame(theme: ren.room!.theme, time: 0.4) { _ in p.baseAddress } }
                let ff = sk.withUnsafeBufferPointer { p in d.feats[o].frame { _ in p.baseAddress } }
                let base = UInt32(f.opaque.vertices.count)
                f.opaque.vertices += ff.vertices; f.opaque.indices += ff.indices.map { $0 + base }
                ren.room!.setWear(opaque: f.opaque, translucent: f.translucent, bounds: [])
                ren.room!.setShoes(RoomMeshBuilder().mesh)
                ren.setJersey(d.worn[o].jersey(0), body: 0)
            } else {
                ren.room!.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []); ren.room!.setShoes(RoomMesh()); ren.setJersey(nil, body: 0)
            }
            ren.setMouth(0, body: 0)
            ren.setBathLook(.dry, body: 0)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = JellyRoster.palette(job.chars[k % job.chars.count]) ?? PaletteKey.blue.palette
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

    // MARK: one strip

    struct PassOut { var start = -1, end = -1, spread: Float = 0, tiles: [UIImage] = [] }

    func pass(_ job: Job, frames: [Int]?, spread: Float, probeFrames: Int) throws -> PassOut {
        let (lab, d) = makeLab(job)
        let (ren, target) = try renderer(lab)
        guard job.setup(lab) else { throw Skip(why: "the emote refused to start (start call returned false in the lab with this cast and prop setup)") }
        var out = PassOut()
        var first = -1, p1 = -1, ended = -1, nilRun = 0
        let maxF = Int(job.maxSeconds * 60)
        var cam: CameraState?
        let r0 = lab.rigs[0]
        for f in 0..<maxF {
            stepLab(lab, d, job)
            switch job.mode {
            case .social:
                if out.start < 0 { out.start = 0 }
                if f > 10, !lab.anySocial { ended = f }
            case .idle(let k):
                let st = r0.brain.idleState
                if st.kind == k {
                    if first < 0 { first = f }
                    if p1 < 0, st.phase >= 1 { p1 = f }
                }
                // the end: the idle slot has been empty for half a second (a move may hand over to a follow-up kind, e.g. the spin to its dizzy wobble, or pause between legs)
                if first >= 0, ended < 0 { if st.kind == nil { nilRun += 1; if nilRun >= 30 { ended = f - 24 } } else { nilRun = 0 } }
                if out.start < 0, first >= 0, (p1 >= 0 || f > first + 90) { out.start = p1 >= 0 ? p1 : first }
                if first < 0, f > 240 { throw Skip(why: "idleState.kind never became \(k) within 4 s of a successful start call (the move did not begin in the lab)") }
            case .fixed:
                if out.start < 0, f >= Int(job.lead * 60) { out.start = f }
            }
            if frames == nil {
                if lab.rigs.count > 1 || f % 10 == 0 {
                    var s: Float = 0
                    let cs = lab.rigs.map { $0.sim.centroid() }
                    for i in 0..<cs.count { for j in (i + 1)..<cs.count { s = max(s, simd_distance(SIMD2(cs[i].x, cs[i].z), SIMD2(cs[j].x, cs[j].z))) } }
                    out.spread = max(out.spread, s)
                }
                if ended >= 0 { out.end = ended; break }
            } else if let frames, frames.contains(f) {
                var cc = SIMD3<Float>(repeating: 0)
                for r in lab.rigs { cc += r.sim.centroid() }
                cc /= Float(lab.rigs.count)
                if cam == nil {
                    let cp = GameCamera.camera(aspect: 1, focus: 0).pos
                    var dir = SIMD3<Float>(cp.x - cc.x, 0, cp.z - cc.z); dir = simd_normalize(dir)
                    let az: Float = 0.5
                    cam0Dir = SIMD3(dir.x * cosf(az) + dir.z * sinf(az), 0, -dir.x * sinf(az) + dir.z * cosf(az))
                    cam = Self.lookCamera(target: .zero, dir: .zero, dist: 1, aspect: 1, lift: 0)
                }
                let dist = min(9, 3.9 + 1.2 * spread)
                let c = Self.lookCamera(target: SIMD3(cc.x, cc.y + 0.25, cc.z), dir: cam0Dir, dist: dist, aspect: Float(Self.W) / Float(Self.H), lift: 0.12)
                let img = composite(lab, d, job, ren, target, cam: c)
                out.tiles.append(img.uiImage()!)
                if out.tiles.count == frames.count { break }
            }
        }
        if frames == nil {
            if out.end < 0 { out.end = maxF - 1 }          // (never ended within the cap: the cap is the window)
            if case .idle = job.mode, out.start < 0, first >= 0 { out.start = p1 >= 0 ? p1 : first }          // (an emote shorter than 1.5 s: from its first frame)
            if case .idle = job.mode, out.start < 0 { throw Skip(why: "never reached its active phase") }
            if case .fixed = job.mode { out.end = maxF - 1 }
        }
        return out
    }
    var cam0Dir = SIMD3<Float>(0, 0, 1)

    func strip(_ job: Job, dir: String) throws {
        let file = Self.fileName(job.code)
        let probe = try pass(job, frames: nil, spread: 0, probeFrames: 0)
        let len = max(probe.end - probe.start, 10)
        let fr = [0.0, 0.25, 0.5, 0.75, 1.0].map { probe.start + min(len - 2, Int(Double(len) * $0)) }
        let shots = try pass(job, frames: fr, spread: probe.spread, probeFrames: 0)
        guard shots.tiles.count == 5 else { throw Skip(why: "only \(shots.tiles.count) of 5 frames could be captured") }
        let tw = 240, th = 260
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: tw * 5, height: th), format: fmt).image { _ in
            for (i, t) in shots.tiles.enumerated() { t.draw(in: CGRect(x: i * tw, y: 0, width: tw, height: th)) }
        }
        guard let jpg = img.jpegData(compressionQuality: 0.8) else { throw Skip(why: "jpeg encode failed") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try jpg.write(to: URL(fileURLWithPath: dir + "/" + file))
        let secs = Float(probe.end - probe.start) / 60
        Self.writePart(dir, file + ".json", ["code": job.code, "file": file, "seconds_captured": Double(String(format: "%.1f", secs))!, "cast": job.chars.prefix(job.positions.count).map { Self.castNames[$0] }])
        print("EMOTE INV \(job.code): \(String(format: "%.1f", secs)) s, spread \(probe.spread)")
    }

    func runJobs(_ jobs: [Job]) throws {
        guard let dir = Self.outDir else { throw XCTSkip("EMOTE_INV_DIR not set") }
        let only = (ProcessInfo.processInfo.environment["EMOTE_INV_ONLY"] ?? "").split(separator: ",").map(String.init)
        for job in jobs where only.isEmpty || only.contains(job.code) {
            let file = Self.fileName(job.code)
            do { try strip(job, dir: dir) }
            catch let s as Skip {
                print("EMOTE INV SKIP \(job.code): \(s.why)")
                Self.writePart(dir, file + ".skip.json", ["code": job.code, "file": NSNull(), "why": s.why])
            } catch let e as XCTSkip { throw e }
            catch {
                print("EMOTE INV ERROR \(job.code): \(error)")
                Self.writePart(dir, file + ".skip.json", ["code": job.code, "file": NSNull(), "why": "error: \(error)"])
            }
        }
    }

    // MARK: the job lists

    static let solo: [SIMD2<Float>] = [SIMD2(0.2, 0.6)]
    static let pair: [SIMD2<Float>] = [SIMD2(-1.0, 0.6), SIMD2(0.7, 0.9)]

    static func idleJobs() -> [Job] {
        IdleKind.allCases.map { k in
            let chars: [Int] = (k == .tailThump || k == .tailHug) ? [1] : (k == .flapHop ? [3] : [0])
            if let via = OnePieceInvariantTests.idleTable[k]?.via, let sc = LegsDrawnAuditTests.fromMove(via) {
                return Job(code: k.rawValue, chars: chars, positions: solo, mode: .idle(k), maxSeconds: min(sc.seconds + 4, 40), setup: { lab in sc.setup(lab.rigs[0], 3) }, each: sc.each)
            }
            if k == .wander {
                return Job(code: k.rawValue, chars: chars, positions: solo, mode: .fixed, maxSeconds: 7, setup: { lab in lab.rigs[0].brain.request(.goTo(SIMD2(1.6, 0.4))); return true })
            }
            let secs = min((OnePieceInvariantTests.idleTable[k]?.seconds ?? 6) + 6, 40)
            return Job(code: k.rawValue, chars: chars, positions: solo, mode: .idle(k), maxSeconds: secs, setup: { lab in
                let r = lab.rigs[0]; r.brain.idleForced = true; return r.brain.idleStart(k, r.sim) })
        }
    }

    static let groupKinds: Set<SocialKind> = [.groupHug, .groupCheer, .conga, .circleDance, .congaLine, .ringDance, .line]

    static func socialJobs() -> [Job] {
        SocialKind.allCases.map { k in
            let group = groupKinds.contains(k)
            var positions = group ? SocialTests.starts : pair
            var decor: [PlacedDecor] = []
            switch k {
            case .shyWave: positions = [SIMD2(-2.0, 0.8), SIMD2(1.4, 1.0)]
            case .pass: decor = [PlacedDecor(uid: 1, kind: .ball, x: -0.9, z: 1.0)]; positions = [SIMD2(-2.2, 1.0), SIMD2(1.6, 1.0)]
            case .bagSit: decor = [PlacedDecor(uid: 2, kind: .beanbag, x: 0.0, z: 0.6)]; positions = [SIMD2(-2.0, 1.8), SIMD2(2.0, 1.8)]
            case .cuddle: decor = [PlacedDecor(uid: 7, kind: .loveseat, x: 0.0, z: -0.8)]; positions = [SIMD2(-1.6, 1.4), SIMD2(1.6, 1.9)]
            default: break
            }
            return Job(code: "social.\(k.rawValue)", chars: [0, 1, 2], positions: positions, mode: .social, maxSeconds: 50, decor: decor, setup: { lab in
                lab.rigs[0].brain.socialStart(k, with: lab.rigs[1].brain, lab.rigs[0].sim) }, seed: 31)
        }
    }

    /// The remaining entries that an existing rig can start. (code, scenario)
    static func otherJobs() -> [Job] {
        var out: [Job] = []
        func gait(_ code: String, _ name: String, lead: Float = 0, secs: Float? = nil) {
            guard let sc = OnePieceInvariantTests.gaitScenario(name) else { return }
            out.append(Job(code: code, chars: [0], positions: solo, mode: .fixed, maxSeconds: secs ?? sc.seconds, setup: { lab in sc.setup(lab.rigs[0], 3) }, each: sc.each, lead: lead))
        }
        gait("script.walk", "walk"); gait("script.turn", "turn"); gait("script.stepInPlace", "march"); gait("script.wave", "wave"); gait("script.spin", "spin")
        gait("script.hopPlay", "hop"); gait("script.flipPlay", "flip"); gait("script.faceplant", "faceplant")
        gait("volley.spike", "volleySpike"); gait("volley.block", "volleyBlock"); gait("volley.dive", "volleyDive"); gait("volley.cheer", "volleyCheer")
        gait("play.rally", "toss: rally", secs: 20)
        out.append(Job(code: "storm.huddle", chars: [0, 1, 2], positions: SocialTests.starts, mode: .fixed, maxSeconds: 14, setup: { _ in
            guard let room = stormRoom else { return false }
            let ev = room.book.begin(seed: 4, jumpTo: .peak)
            room.reactor.handle(ev, plan: room.book.plan, jellies: room.js, care: nil)
            return true }, storm: true))
        for (code, name) in [("ears.dance", "ears dance"), ("ears.reactions", "ears startle")] {
            if let m = FeetAttachTests.moves.first(where: { $0.name == name }) {
                out.append(Job(code: code, chars: [4], positions: solo, mode: .fixed, maxSeconds: min(m.seconds, 12), setup: { lab in m.start(lab.rigs[0]); return true }, each: m.each))
            }
        }
        return out
    }

    // MARK: tests

    func testIdle1() throws { try runJobs(Array(Self.idleJobs()[0..<20])) }
    func testIdle2() throws { try runJobs(Array(Self.idleJobs()[20..<40])) }
    func testIdle3() throws { try runJobs(Array(Self.idleJobs()[40...])) }
    func testSocial1() throws { try runJobs(Array(Self.socialJobs()[0..<21])) }
    func testSocial2() throws { try runJobs(Array(Self.socialJobs()[21...])) }
    func testOther() throws { try runJobs(Self.otherJobs()) }
}
