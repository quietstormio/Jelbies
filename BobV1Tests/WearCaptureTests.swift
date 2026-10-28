//
//  WearCaptureTests.swift
//  Not a regression test: renders the wardrobe with the REAL renderer (game room, real body shader, jersey pipeline, wardrobe + shoe meshes) when
//  WEAR_CAP_DIR is set (TEST_RUNNER_WEAR_CAP_DIR). Like the other capture suites the renderer draws ONE body per pass: each rig is rendered alone and
//  pasted over an empty-room render. WEAR_CAP_LAND=left|right renders the landscape frame instead of the portrait one.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class WearCaptureTests: XCTestCase {
    var W = 603, H = 1311
    nonisolated(unsafe) static var keep: [AnyObject] = []

    typealias Outfit = [WearSlot: WearLook]

    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0) }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); DayClock.shared.forcedHour = 12 }

    private func dir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["WEAR_CAP_DIR"], !d.isEmpty else { throw XCTSkip("WEAR_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    private func renderer(_ lab: SocialTests.Lab) throws -> (MelonRenderer, MTLTexture) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        let r0 = lab.rigs[0]
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r0.sim.edges, particleCount: r0.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        ren.roomCacheEnabled = false
        return (ren, device.makeTexture(descriptor: td)!)
    }

    private func setUpLab(_ positions: [SIMD2<Float>], seed: UInt64 = 5) -> SocialTests.Lab {
        let lab = SocialTests.Lab(n: positions.count, positions: positions, quiet: true, seed: seed)
        SocialTests.keep.append(lab)
        for r in lab.rigs { r.skinner.autoBlink = false }
        WearBody.install(MotionRig.renderMesh)
        return lab
    }

    /// One wardrobe per rig (id 0 each: the renderer draws one body per pass).
    private func dress(_ lab: SocialTests.Lab, _ outfits: [Outfit], roles: [WearRaceRole] = []) -> [WornSet] {
        var sets: [WornSet] = []
        for (k, r) in lab.rigs.enumerated() {
            let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; Self.keep.append(w)
            let role = roles.indices.contains(k) ? roles[k] : WearRaceRole.none
            for _ in 0..<2 { w.tick(id: 0, brain: r.brain, sim: r.sim, outfit: outfits.indices.contains(k) ? outfits[k] : [:], role: role, hideAll: false, dt: 1.0 / 60) }
            sets.append(w)
        }
        return sets
    }

    private func skin(_ r: MotionRig) -> [Float] {
        var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &d)
        return d
    }

    static func lookCamera(target: SIMD3<Float>, dir: SIMD3<Float>, dist: Float, aspect: Float, lift: Float = 0.1) -> CameraState {
        let eye = target + dir * dist + SIMD3(0, dist * lift, 0)
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.2, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(target - eye)
        return cam
    }

    /// The scene with every rig drawn alone and pasted; `sets` = each rig's wardrobe, shoes from `outfits`.
    private func composite(_ lab: SocialTests.Lab, _ sets: [WornSet], _ outfits: [Outfit], _ ren: MelonRenderer, _ target: MTLTexture,
                           cam camOverride: CameraState? = nil, mouth: Float = 0, race: Bool = false, hour: Double? = 12, rigFilter: Int? = nil) -> LockImage {
        let cam = camOverride ?? GameCamera.camera(aspect: Float(W) / Float(H), focus: 0, race: race ? 1 : 0)
        ren.dayHourOverride = hour
        ren.raceVisible = race
        func shot(only: Int?) -> LockImage {
            let k = only ?? 0
            let light = GameCamera.light(centroids: lab.rigs.map { $0.sim.centroid() })
            ren.beginFrame()
            let r = lab.rigs[k]
            r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            if only == nil { for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 } }
            if let o = only {
                let sk = skin(r)
                if sets[o].shown(0, .hands) != nil { sets[o].setArms(0, GameCare.armFrames(brain: r.brain, sim: r.sim)) }
                let f = sk.withUnsafeBufferPointer { p in sets[o].frame(theme: ren.room!.theme, time: 0.4) { _ in p.baseAddress } }
                let sb = RoomMeshBuilder(); sb.material = .plain
                if let look = outfits.indices.contains(o) ? outfits[o][.feet] : nil, let beans = GameCare.footBeans(brain: r.brain, sim: r.sim, skinner: r.skinner) {
                    for s in 0..<2 { if legacyShoes { LegacyShoe.build(look, bean: beans[s], floorY: r.sim.floorY, into: sb) } else { ShoeModel.build(look, bean: beans[s], floorY: r.sim.floorY, time: 0.4, side: s, body: JellyRoster.palette(o)?.flesh ?? SIMD3(0.35, 0.5, 0.9), gpuPaint: gpuShoes, into: sb) } }
                }
                ren.room!.setWear(opaque: f.opaque, translucent: f.translucent, bounds: f.opaque.vertices.isEmpty ? [] : [])
                ren.room!.setShoes(sb.mesh)
                ren.setJersey(sets[o].jersey(0), body: 0)
            } else {
                ren.room!.setWear(opaque: RoomMesh(), translucent: RoomMesh(), bounds: []); ren.room!.setShoes(RoomMesh()); ren.setJersey(nil, body: 0)
            }
            ren.setMouth(only == mouthRig ? mouth : 0, body: 0)
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
        _ = shot(only: nil)
        let empty = shot(only: nil)
        var out = empty
        for k in (0..<lab.rigs.count).sorted(by: { lab.rigs[$0].sim.centroid().z < lab.rigs[$1].sim.centroid().z }) where rigFilter == nil || rigFilter == k {
            let b = shot(only: k)
            for p in 0..<(W * H) {
                var d = 0
                for c in 0..<3 { d = max(d, abs(Int(b.bgra[4 * p + c]) - Int(empty.bgra[4 * p + c]))) }
                if d > 3 { for c in 0..<4 { out.bgra[4 * p + c] = b.bgra[4 * p + c] } }
            }
        }
        return out
    }
    var mouthRig = -1
    var legacyShoes = false
    var gpuShoes = false

    private func labelled(_ img: UIImage, _ text: String) -> UIImage {
        let w = img.size.width, h = img.size.height, bar: CGFloat = 40
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + bar), format: fmt).image { _ in
            UIColor(white: 0.1, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: w, height: h + bar))
            (text as NSString).draw(at: CGPoint(x: 10, y: 9), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white])
            img.draw(in: CGRect(x: 0, y: bar, width: w, height: h))
        }
    }
    private func hstack(_ imgs: [UIImage]) -> UIImage {
        let h = imgs.map { $0.size.height }.max() ?? 0, w = imgs.reduce(0) { $0 + $1.size.width }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            var x: CGFloat = 0
            for i in imgs { i.draw(at: CGPoint(x: x, y: 0)); x += i.size.width }
        }
    }
    private func write(_ img: UIImage, _ path: String) throws { try img.pngData()!.write(to: URL(fileURLWithPath: path)) }

    /// The outfits of outfits.png / outfits_2.png (Bob / Pip / Moss).
    static let setA: [Outfit] = [[.head: .capTeamPink, .body: .bibPink, .hands: .glovePink, .feet: .sneakerCoral],
                                 [.head: .flowerCrown, .neck: .bowtieSky, .feet: .glitterShoes],
                                 [.head: .beaniePink, .neck: .bandanaCoral]]
    static let setB: [Outfit] = [[.head: .pirateHat, .face: .monocleGold, .neck: .scarfCosy, .hands: .boxingMitts, .feet: .hightopRed],
                                 [.head: .sweatband, .neck: .whistleCoach, .hands: .wristbandsSky, .body: .sashSky, .feet: .sneakerLightup],
                                 [.head: .crownGold, .neck: .pearls, .body: .tutuPink, .feet: .balletPink]]
    static let setC: [Outfit] = [[.head: .witchHat, .face: .gogglesAviator, .body: .capeHero, .feet: .rainBoots],
                                 [.head: .bucketHatPink, .neck: .scarfSky, .hands: .gloveSky, .feet: .rainBoots],
                                 [.head: .catEars, .face: .heartShades, .body: .backpackSky, .neck: .medalGold]]

    /// The part of a room frame around the three Jellies (2x render), cropped so the outfits read.
    private func cropJellies(_ img: LockImage, _ lab: SocialTests.Lab) -> UIImage? {
        let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        let pts = lab.rigs.map { r -> SIMD2<Float> in
            let c = r.sim.centroid(); let k = cam.viewProj * SIMD4<Float>(c.x, c.y, c.z, 1)
            return SIMD2((k.x / k.w * 0.5 + 0.5) * Float(W), (1 - (k.y / k.w * 0.5 + 0.5)) * Float(H))
        }
        let lo = pts.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }, hi = pts.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        let mid = (lo + hi) / 2
        let hw = max((hi.x - lo.x) / 2 + Float(W) * 0.09, Float(W) * 0.2), hh = hw * 0.62
        let r = CGRect(x: CGFloat(mid.x - hw), y: CGFloat(mid.y - hh * 1.15), width: CGFloat(hw * 2), height: CGFloat(hh * 2)).intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard let cg = img.cgImage(), let part = cg.cropping(to: r) else { return nil }
        return UIImage(cgImage: part)
    }

    func testCaptureOutfitsInGame() throws {
        let d = try dir()
        let land = ProcessInfo.processInfo.environment["WEAR_CAP_LAND"] ?? ""
        let isLand = !land.isEmpty
        if isLand { W = 1311 * 2; H = 603 * 2 } else { W = 603 * 2; H = 1311 * 2 }
        DayClock.shared.forcedHour = 12
        var shots: [UIImage] = []
        for (n, set) in [Self.setA, Self.setB, Self.setC].enumerated() {
            let lab = setUpLab([SIMD2(-1.9, 0.5), SIMD2(0.1, 0.9), SIMD2(2.0, 0.4)], seed: UInt64(5 + n))
            let (ren, target) = try renderer(lab)
            let sets = dress(lab, set)
            let img = composite(lab, sets, set, ren, target)
            if let c = cropJellies(img, lab) { shots.append(labelled(c, ["Set A: racer Bob, contest Pip, cosy Moss", "Set B: pirate Bob, sporty Pip, royal Moss", "Set C: witch Bob, winter Pip, cat-ear Moss"][n] + (isLand ? " (landscape)" : " (portrait)"))) }
        }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let w = shots.map { $0.size.width }.max()!, h = shots.map { $0.size.height }.reduce(0, +)
        try write(UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            var y: CGFloat = 0
            for s in shots { s.draw(at: CGPoint(x: 0, y: y)); y += s.size.height }
        }, d + (isLand ? "/outfits_land.png" : "/outfits_ingame.png"))
    }

    /// Pip in heart shades + beanie with the mouth open (a drink): the shades now stay on (left: the old behaviour for comparison, shades poofed off).
    func testCaptureDrinkWear() throws {
        let d = try dir()
        W = 900; H = 900
        DayClock.shared.forcedHour = 12
        let full: Outfit = [.head: .beaniePink, .face: .heartShades]
        var rows: [UIImage] = []
        for (label, outfit, yaw, mouth) in [("BEFORE (old rule: shades hidden mid-drink)", [.head: .beaniePink] as Outfit, Float(0.6), Float(1)),
                                             ("AFTER 3/4 mid-drink", full, Float(0.6), Float(1)), ("AFTER front mid-drink", full, Float(0), Float(1))] {
            let lab = setUpLab([SIMD2(0.2, 0.6), SIMD2(30, 30), SIMD2(32, 30)], seed: 3)
            let (ren, target) = try renderer(lab)
            let sets = dress(lab, [outfit])
            mouthRig = 0
            let r = lab.rigs[0]
            if outfit[.face] != nil { r.brain.script = .eat(t: 0.5, bowl: SIMD2(0, 0), dur: 3, drink: true); for _ in 0..<30 { sets[0].tick(id: 0, brain: r.brain, sim: r.sim, outfit: outfit, role: .none, hideAll: false, dt: 1.0 / 60) } }
            let pose = r.sim.bodyPose(iterations: 3)
            var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
            fwd = simd_normalize(fwd)
            let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
            let c = pose.centroid
            let cam = Self.lookCamera(target: SIMD3(c.x, c.y + 0.25, c.z), dir: dir, dist: 3.4, aspect: 1)
            rows.append(labelled(composite(lab, sets, [outfit], ren, target, cam: cam, mouth: mouth).uiImage()!, label))
        }
        mouthRig = -1
        try write(hstack(rows), d + "/wear_drink.png")
    }

    func testCaptureCloseups() throws {
        let d = try dir()
        W = 900; H = 900
        DayClock.shared.forcedHour = 12
        let looks: [(String, Outfit)] = [("Racer", Self.setA[0]), ("Royal", Self.setB[2]), ("Pirate", Self.setB[0]), ("Cosy", Self.setC[1])]
        var cols: [UIImage] = []
        for (name, outfit) in looks {
            var rows: [UIImage] = []
            for (label, yaw, mouth) in [("front", Float(0), Float(0)), ("3/4", Float(0.6), Float(0)), ("3/4 chomp", Float(0.6), Float(1))] {
                let lab = setUpLab([SIMD2(0.2, 0.6), SIMD2(30, 30), SIMD2(32, 30)], seed: 3)
                let (ren, target) = try renderer(lab)
                let sets = dress(lab, [outfit])
                mouthRig = 0
                let r = lab.rigs[0]
                let pose = r.sim.bodyPose(iterations: 3)
                var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
                fwd = simd_normalize(fwd)
                let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
                let c = pose.centroid
                let cam = Self.lookCamera(target: SIMD3(c.x, c.y + 0.25, c.z), dir: dir, dist: 3.4, aspect: 1)
                let img = composite(lab, sets, [outfit], ren, target, cam: cam, mouth: mouth)
                rows.append(labelled(img.uiImage()!, "\(name) \(label)"))
            }
            cols.append(hstack(rows))
        }
        mouthRig = -1
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let h = cols.map { $0.size.height }.reduce(0, +), w = cols.map { $0.size.width }.max()!
        try write(UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            var y: CGFloat = 0
            for c in cols { c.draw(at: CGPoint(x: 0, y: y)); y += c.size.height }
        }, d + "/closeups.png")
    }

    func testCaptureRaceBibs() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        let xs = (0..<3).map { RaceTuning.laneX($0) }
        let z = RaceTuning.finishZ - 4
        let lab = setUpLab(xs.map { SIMD2($0, z) }, seed: 4)
        let (ren, target) = try renderer(lab)
        let roles: [WearRaceRole] = [.rival(team: .lavender, number: 3), .player(team: .sky, number: WearTeam.playerNumber(roster: 0)), .rival(team: .coral, number: 9)]
        let outfits: [Outfit] = [[:], [.head: .capTeamSky, .hands: .gloveSky, .feet: .sneakerMint], [:]]
        let sets = dress(lab, outfits, roles: roles)
        W = 603 * 2; H = 1311 * 2
        let (ren2, target2) = try renderer(lab)
        let img = composite(lab, sets, outfits, ren2, target2, race: true)
        let r = CGRect(x: 0.12 * Double(W), y: 0.50 * Double(H), width: 0.76 * Double(W), height: 0.18 * Double(H))
        let crop = img.cgImage()!.cropping(to: r).map { UIImage(cgImage: $0) }!
        _ = (ren, target)
        try write(labelled(crop, "Jelly Circuit: racers with numbered bibs + jersey bands (lavender #3, player sky #7 with cap / mittens / sneakers, coral #9)"), d + "/race_bibs.png")
    }

    func testCaptureSleepHats() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 15
        W = 603 * 2; H = 1311 * 2
        let lab = setUpLab([SIMD2(0.2, 0.3), SIMD2(2.3, 1.8), SIMD2(-2.4, 1.6)], seed: 7)
        for r in lab.rigs { r.brain.sleepEnabled = false }
        let (ren, target) = try renderer(lab)
        let s = lab.rigs[0]
        let outfit: Outfit = [.head: .tophat, .face: .sunglassesStar, .neck: .bowtieSky]
        let set = WornSet(); set.body = WearBody.shared; set.soundOn = false
        let mask = SleepMaskSet(); mask.soundOn = false
        s.brain.idleForced = true
        XCTAssertTrue(s.brain.idleStart(.sleep, s.sim)); s.brain.sleep.hold = 500
        var f = 0
        func step() {
            lab.tick(watching: false)
            for (i, r) in lab.rigs.enumerated() { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            mask.tick(id: 0, brain: s.brain, sim: s.sim, dt: s.sim.stepDt); mask.stepPuffs(dt: 1.0 / 60)
            set.tick(id: 0, brain: s.brain, sim: s.sim, outfit: outfit, role: .none, hideAll: false, dt: 1.0 / 60); set.stepPuffs(dt: 1.0 / 60)
            f += 1
        }
        // awake first (hat on), then asleep (hat off, mask on)
        for _ in 0..<3 { set.tick(id: 0, brain: s.brain, sim: s.sim, outfit: outfit, role: .none, hideAll: false, dt: 1.0 / 60) }
        var frames: [UIImage] = []
        func shoot(_ label: String) throws {
            let sets = [set, WornSet(), WornSet()]
            let m = mask.frame(theme: ren.room!.theme)
            ren.room!.setMasks(opaque: m.opaque, translucent: m.translucent)
            let img = composite(lab, sets, [outfit], ren, target, hour: 15)
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            let c = s.sim.centroid()
            let clip = cam.viewProj * SIMD4<Float>(c.x, c.y + 0.4, c.z, 1)
            let sx = (clip.x / clip.w * 0.5 + 0.5) * Float(W), sy = (1 - (clip.y / clip.w * 0.5 + 0.5)) * Float(H)
            if let cg = img.cgImage(), let part = cg.cropping(to: CGRect(x: Int(sx) - 280, y: Int(sy) - 280, width: 560, height: 560)) { frames.append(labelled(UIImage(cgImage: part), label)) }
        }
        try shoot("1. awake: top hat + star shades + bow tie")
        for _ in 0..<5 { step() }
        while !s.brain.isNapping && f < 60 * 40 { step() }
        for _ in 0..<45 { step() }
        try shoot("2. asleep: hat and shades poofed off, mask on, bow tie stays")
        s.brain.sleepWake(groggy: false)
        while s.brain.sleep.stage < 4 && f < 60 * 60 { step() }
        for _ in 0..<45 { step() }
        try shoot("3. waking: mask poofs away, hat back on")
        try write(hstack(frames), d + "/sleep_hats.png")
    }
}

extension WearCaptureTests {
    /// Every shoe look: the game camera (cropped) and a 2x close-up of the feet; the five original looks also as they were before (legacy shell).
    func testCaptureShoes() throws {
        let d = try dir()
        W = 603 * 2; H = 1311 * 2
        DayClock.shared.forcedHour = 12
        var rows: [UIImage] = []
        for look in WearLook.shoes {
            var cells: [UIImage] = []
            for legacy in [true, false] where !(legacy && LegacyShoe.pal(look) == nil) {
                legacyShoes = legacy
                let lab = setUpLab([SIMD2(0.2, 0.6), SIMD2(30, 30), SIMD2(32, 30)], seed: 3)
                let (ren, target) = try renderer(lab)
                let outfit: Outfit = [.feet: look]
                let sets = dress(lab, [outfit])
                let r = lab.rigs[0]
                let c = r.sim.centroid()
                // 2x close-up (about 3/4, low) and the game camera
                W = 900; H = 900
                let (ren2, t2) = try renderer(lab)
                let cam = Self.lookCamera(target: SIMD3(c.x, 0.1, c.z), dir: simd_normalize(SIMD3(0.55, 0, 0.85)), dist: 2.0, aspect: 1, lift: 0.4)
                let close = composite(lab, sets, [outfit], ren2, t2, cam: cam)
                cells.append(labelled(close.uiImage()!, "\(look.title) \(legacy ? "BEFORE" : "AFTER") 2x close-up"))
                W = 603 * 2; H = 1311 * 2
                let game = composite(lab, sets, [outfit], ren, target)
                let gc = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
                let k = gc.viewProj * SIMD4<Float>(c.x, 0.12, c.z, 1)
                let sx = (k.x / k.w * 0.5 + 0.5) * Float(W), sy = (1 - (k.y / k.w * 0.5 + 0.5)) * Float(H)
                if let cg = game.cgImage(), let part = cg.cropping(to: CGRect(x: Int(sx) - 60, y: Int(sy) - 60, width: 120, height: 120)) {
                    cells.append(labelled(UIImage(cgImage: part).scaled(450), "game camera 2x render, magnified"))
                }
            }
            legacyShoes = false
            rows.append(hstack(cells))
        }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let w = rows.map { $0.size.width }.max()!, h = rows.map { $0.size.height }.reduce(0, +)
        try write(UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            var y: CGFloat = 0
            for r in rows { r.draw(at: CGPoint(x: 0, y: y)); y += r.size.height }
        }, d + "/shoes_closeup.png")
    }
}

extension UIImage {
    func scaled(_ side: CGFloat) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
    }
}

extension WearCaptureTests {
    /// Crisp shoes: every look, BEFORE (per-vertex colours) vs AFTER (per-pixel paint in the fragment shader): game-camera crop and a low, near close-up.
    func testCaptureShoesCrisp() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        var rows: [UIImage] = []
        let side: CGFloat = 420
        for look in WearLook.shoes {
            var cells: [UIImage] = []
            for gpu in [false, true] {
                gpuShoes = gpu
                let tag = gpu ? "AFTER" : "BEFORE"
                W = 603 * 2; H = 1311 * 2
                let lab = setUpLab([SIMD2(0.2, 0.6), SIMD2(30, 30), SIMD2(32, 30)], seed: 3)
                let (ren, target) = try renderer(lab)
                let outfit: Outfit = [.feet: look]
                let sets = dress(lab, [outfit])
                let c = lab.rigs[0].sim.centroid()
                let game = composite(lab, sets, [outfit], ren, target)
                let gc = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
                let k = gc.viewProj * SIMD4<Float>(c.x, 0.12, c.z, 1)
                let sx = (k.x / k.w * 0.5 + 0.5) * Float(W), sy = (1 - (k.y / k.w * 0.5 + 0.5)) * Float(H)
                if let cg = game.cgImage(), let part = cg.cropping(to: CGRect(x: Int(sx) - 90, y: Int(sy) - 90, width: 180, height: 180)) {
                    cells.append(labelled(UIImage(cgImage: part).scaled(side), "\(look.title) \(tag): game camera"))
                }
                W = 900; H = 900
                let (ren2, t2) = try renderer(lab)
                let cam = Self.lookCamera(target: SIMD3(c.x, 0.06, c.z + 0.02), dir: simd_normalize(SIMD3(0.5, 0, 0.87)), dist: 1.15, aspect: 1, lift: 0.14)
                let close = composite(lab, sets, [outfit], ren2, t2, cam: cam)
                cells.append(labelled(close.uiImage()!.scaled(side), "\(look.title) \(tag): close-up"))
            }
            gpuShoes = false
            rows.append(hstack(cells))
        }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let w = rows.map { $0.size.width }.max()!, h = rows.map { $0.size.height }.reduce(0, +)
        try write(UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            var y: CGFloat = 0
            for r in rows { r.draw(at: CGPoint(x: 0, y: y)); y += r.size.height }
        }, d + "/shoes_before_after.png")
        // one landscape frame
        gpuShoes = true
        W = 1311; H = 603
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: Float(W) / Float(H))
        let lab = setUpLab([SIMD2(0.2, 0.6), SIMD2(30, 30), SIMD2(32, 30)], seed: 3)
        let (ren, target) = try renderer(lab)
        let outfit: Outfit = [.feet: .sneakerLightup]
        let sets = dress(lab, [outfit])
        let c = lab.rigs[0].sim.centroid()
        let game = composite(lab, sets, [outfit], ren, target)
        let gc = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
        let k = gc.viewProj * SIMD4<Float>(c.x, 0.12, c.z, 1)
        let sx = (k.x / k.w * 0.5 + 0.5) * Float(W), sy = (1 - (k.y / k.w * 0.5 + 0.5)) * Float(H)
        try write(labelled(game.uiImage()!, "landscape, light-up sneakers (AFTER)"), d + "/shoes_landscape.png")
        if let cg = game.cgImage(), let part = cg.cropping(to: CGRect(x: max(0, Int(sx) - 60), y: max(0, Int(sy) - 60), width: 120, height: 120)) {
            try write(labelled(UIImage(cgImage: part).scaled(480), "landscape crop, magnified"), d + "/shoes_landscape_crop.png")
        }
        gpuShoes = false
    }
}

extension WearCaptureTests {
    /// Fix C: the bare blue foot under the shoes. Every look, Bob standing still (3 s) and mid-step: game camera (magnified) + a low close-up.
    /// SHOE_STAND_TAG labels the variant (before / after); writes shoes_stand_<tag>.png.
    func testCaptureShoesStanding() throws {
        let d = try dir()
        let tag = ProcessInfo.processInfo.environment["SHOE_STAND_TAG"] ?? "after"
        DayClock.shared.forcedHour = 12
        var rows: [UIImage] = []
        let side: CGFloat = 330
        for look in WearLook.shoes {
            var cells: [UIImage] = []
            W = 603 * 2; H = 1311 * 2
            let lab = setUpLab([SIMD2(0.2, 0.6), SIMD2(30, 30), SIMD2(32, 30)], seed: 3)
            let outfit: Outfit = [.feet: look]
            let sets = dress(lab, [outfit])
            let r = lab.rigs[0]
            r.brain.shoesWorn = true          // AFTERONLY
            func step() { lab.tick(watching: false); for q in lab.rigs { q.skinner.jelly.tick(brain: q.brain, sim: q.sim, dt: q.sim.stepDt) } }
            func shoot(_ pose: String) throws {
                let c = r.sim.centroid()
                W = 603 * 2; H = 1311 * 2
                let (ren, target) = try renderer(lab)
                let game = composite(lab, sets, [outfit], ren, target)
                let gc = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
                let k = gc.viewProj * SIMD4<Float>(c.x, 0.12, c.z, 1)
                let sx = (k.x / k.w * 0.5 + 0.5) * Float(W), sy = (1 - (k.y / k.w * 0.5 + 0.5)) * Float(H)
                if let cg = game.cgImage(), let part = cg.cropping(to: CGRect(x: Int(sx) - 90, y: Int(sy) - 90, width: 180, height: 180)) {
                    cells.append(labelled(UIImage(cgImage: part).scaled(side), "\(look.title) \(pose): game camera"))
                }
                W = 900; H = 900
                let (ren2, t2) = try renderer(lab)
                let cam = Self.lookCamera(target: SIMD3(c.x, 0.06, c.z + 0.02), dir: simd_normalize(SIMD3(0.5, 0, 0.87)), dist: 1.15, aspect: 1, lift: 0.1)
                cells.append(labelled(composite(lab, sets, [outfit], ren2, t2, cam: cam).uiImage()!.scaled(side), "\(look.title) \(pose): low close-up"))
            }
            for _ in 0..<(60 * 3) { step() }
            try shoot("STANDING")
            r.brain.request(.goTo(r.root + SIMD2(1.0, 1.2)))
            var n = 0
            while n < 60 * 5 { step(); n += 1; if n > 50, max(r.footBottom(0), r.footBottom(1)) - r.sim.floorY > 0.035 { break } }
            try shoot("MID-STEP")
            rows.append(hstack(cells))
        }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let w = rows.map { $0.size.width }.max()!, h = rows.map { $0.size.height }.reduce(0, +)
        try write(UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            var y: CGFloat = 0
            for r in rows { r.draw(at: CGPoint(x: 0, y: y)); y += r.size.height }
        }, d + "/shoes_stand_\(tag).png")
    }
}

extension WearCaptureTests {
    /// STORE SWEEP (shoes): every shoe on all four Jelbies (Bob, Pip, Moss, Lavender) standing, mid-walk, mid-run, sitting and in two cartwheel frames, one
    /// low 3/4 camera over the whole row. SHOE_LOOKS="sneakerMint,rainBoots" and SHOE_POSES="stand,walk" limit the run; writes shoes4_<look>.png.
    func testCaptureShoesAllJelbies() throws {
        let d = try dir()
        DayClock.shared.forcedHour = 12
        let env = ProcessInfo.processInfo.environment
        let looks = (env["SHOE_LOOKS"].map { $0.isEmpty ? [] : $0.components(separatedBy: ",") } ?? []).compactMap { WearLook(rawValue: $0) }
        let poses = (env["SHOE_POSES"].map { $0.isEmpty ? [] : $0.components(separatedBy: ",") } ?? [])
        let allPoses = ["stand", "walk", "run", "sit", "cartwheelA", "cartwheelB"]
        let names = ["Bob", "Pip", "Moss", "Lavender"]
        let cell = (w: 600, h: 520)
        W = cell.w; H = cell.h
        var shared: (MelonRenderer, MTLTexture)?
        for look in (looks.isEmpty ? WearLook.shoes : looks) {
            var rows: [UIImage] = []
            for pose in (poses.isEmpty ? allPoses : poses) {
                let lab = setUpLab([SIMD2(-1.7, -0.3), SIMD2(1.7, -0.3), SIMD2(-0.9, 1.9), SIMD2(1.0, 1.9)], seed: 3)
                if shared == nil { shared = try renderer(lab) }
                let (ren, target) = shared!
                let outfit: Outfit = [.feet: look]
                let outfits = [Outfit](repeating: outfit, count: 4)
                let sets = dress(lab, outfits)
                for r in lab.rigs { r.brain.shoesWorn = true }
                func step(_ n: Int) { for _ in 0..<n { lab.tick(watching: false); for q in lab.rigs { q.skinner.jelly.tick(brain: q.brain, sim: q.sim, dt: q.sim.stepDt) } } }
                step(60 * 2)
                switch pose {
                case "walk": for r in lab.rigs { r.brain.request(.goTo(r.root + SIMD2(0, 1.2))) }; step(70)
                case "run":
                    for r in lab.rigs { r.brain.idleForced = true; _ = r.brain.idleStart(.run, r.sim) }
                    step(80)
                    var n = 0
                    while n < 120, lab.rigs[0].footBottom(0) - lab.rigs[0].sim.floorY < 0.05, lab.rigs[0].footBottom(1) - lab.rigs[0].sim.floorY < 0.05 { step(1); n += 1 }
                case "sit": for r in lab.rigs { r.brain.idleForced = true; _ = r.brain.idleStart(.sit, r.sim) }; step(60 * 3)
                case "cartwheelA", "cartwheelB":
                    for r in lab.rigs { r.brain.idleForced = true; _ = r.brain.idleStart(.cartwheel, r.sim) }
                    let want: Float = pose == "cartwheelA" ? 1.0 : 2.3
                    var n = 0
                    while n < 60 * 6, lab.rigs[0].sim.bodyPose(iterations: 4).tilt < want { step(1); n += 1 }
                default: break
                }
                var cells: [UIImage] = []
                for (k, r) in lab.rigs.enumerated() {
                    let c = r.sim.centroid()
                    let cam = Self.lookCamera(target: SIMD3(c.x, 0.12, c.z), dir: simd_normalize(SIMD3(0.35, 0, 1)), dist: 2.3, aspect: Float(W) / Float(H), lift: 0.3)
                    let img = composite(lab, sets, outfits, ren, target, cam: cam, rigFilter: k)
                    cells.append(labelled(img.uiImage()!, "\(look.title): \(pose), \(names[k])"))
                }
                rows.append(hstack(cells))
                SocialTests.keep.removeAll()
            }
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let w = rows.map { $0.size.width }.max()!, h = rows.map { $0.size.height }.reduce(0, +)
            try write(UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
                var y: CGFloat = 0
                for r in rows { r.draw(at: CGPoint(x: 0, y: y)); y += r.size.height }
            }, d + "/shoes4_\(look.rawValue).png")
        }
    }
}
