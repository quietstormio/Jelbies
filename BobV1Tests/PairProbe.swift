//
//  PairProbe.swift
//  Test helper of the pair-distinct round (2026-11-19): runs ONE side-by-side pair emote between two Jelmiko (species by the ContactPolishTests cast indices), measures every pair every other frame with the ground-truth
//  BruteForceContactMetric and, when asked, renders the game camera (the home room view, phone aspect) every `shootEvery` frames and crops around the pair.
//    skin      whole-skin gap (egg + arms + ears + feet beans), negative = overlap
//    body      egg-only gap
//    armLevel  the gap of the two skins looked at only at ARM HEIGHT (the rest nub's height +- 12 cm): "do the arms / flanks touch"; apart = 9
//    head      the gap of the two skins looked at only at HEAD HEIGHT (y >= 0.78 of the body): where a nuzzle / lean is meant to touch
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
enum PairProbe {
    typealias Duo = FeatureClipTests.Duo
    static let W = 603, H = 1311
    nonisolated(unsafe) static var keep: [Duo] = []

    struct Sample { var t: Float; var phase: Int; var skin: Float; var body: Float; var armLevel: Float; var head: Float; var sepRoot: Float; var armArm: Float }
    struct Shot { var t: Float; var phase: Int; var skin: Float; var arm: Float; var image: UIImage; var crop: CGRect }
    struct Result {
        var kind = "", cast = ""
        var started = false, completed = false
        var seconds: Float = 0
        var samples: [Sample] = []
        var touchGaps: [Float] = []          // whole-skin gap at each touch event of the contact gate
        var shots: [Shot] = []
        var footSlide: Float = 0
        var sounds: [String: Int] = [:], haps: [String: Int] = [:]
        var chirps: Int { sounds.filter { $0.key.hasPrefix("chirp") }.values.reduce(0, +) }
        var hearts = 0                      // .boop + .makeUp events (both bodies)
        var minArmArmPerf: Float { perf.map { $0.armArm }.min() ?? 9 }
        var startedPhase2: Float = -1
        var minSkin: Float { samples.map { $0.skin }.min() ?? 9 }
        var minBody: Float { samples.map { $0.body }.min() ?? 9 }
        /// Over the frames of the performance (phase >= 2).
        var perf: [Sample] { samples.filter { $0.phase >= 2 } }
        var minArmLevelPerf: Float { perf.map { $0.armLevel }.min() ?? 9 }
        var minHeadPerf: Float { perf.map { $0.head }.min() ?? 9 }
        var minSkinPerf: Float { perf.map { $0.skin }.min() ?? 9 }
        var maxSeparationPerf: Float { perf.map { $0.sepRoot }.max() ?? 0 }
        var minSeparationPerf: Float { perf.map { $0.sepRoot }.min() ?? 0 }
    }

    static func setUpGlobals() {
        EmoteFeetTests.reset()
        RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12
        GameCamera.configureRoom(count: 3)
        _ = GameCamera.camera(aspect: Float(W) / Float(H))
        FeatureClip.enabled = true; LieClearTuning.enabled = true
    }
    static func tearDownGlobals() {
        AudioHub.requestTap = nil; EmoteHaptic.requestTap = nil; EmoteTreats.requestTap = nil; HapticDriver.cueTap = nil
        FeatureClip.enabled = true; FeatureClip.eggs = []; ContactField.reset(); ContactField.enabled = true
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        EmoteFeetTests.reset()
    }

    /// Surface of body i restricted to the vertices whose height lies in [lo, hi] (whole skin: egg, arms, ears).
    static func band(_ d: Duo, _ i: Int, lo: Float, hi: Float) -> ContactSurface {
        let full = d.contactSurfacesNoSkin()[i]
        return ContactSurface(root: full.root, points: full.points.filter { $0.y >= lo && $0.y <= hi })
    }

    /// The least 3D distance from any DRAWN ARM vertex of one body to the other body's whole skin (strided); 9 when no arm is drawn as a capsule.
    static func armToSkin(_ d: Duo, _ S: [ContactSurface]) -> Float {
        var m: Float = 9
        for i in 0..<2 {
            let arms = d.contactArmPoints(i)
            if arms.isEmpty { continue }
            let other = S[1 - i].points
            for p in arms { var k = 0; while k < other.count { m = min(m, simd_distance(p, other[k])); k += 4 } }
        }
        return m
    }

    static func gapOf(_ a: ContactSurface, _ b: ContactSurface) -> Float {
        guard !a.points.isEmpty, !b.points.isEmpty else { return 9 }
        return BruteForceContactMetric.skinGap(a, b)
    }

    /// shootEvery > 0: render the game camera every that many frames while the session runs (phase >= 1).
    static func run(kind: SocialKind, cast: [Int], castName: String, maxSec: Float = 40, shootEvery: Int = 0, device: MTLDevice? = nil, hat: Bool = false, seed: UInt64 = 31) -> Result {
        setUpGlobals()
        ContactField.reset(); FeatureClip.eggs = []
        var res = Result(); res.kind = kind.rawValue; res.cast = castName
        let n = cast.count
        let starts: [SIMD2<Float>] = kind == .orbit ? [SIMD2(-1.6, 0.4), SIMD2(0.0, 0.4)] : Array(ContactPolishTests.farStarts.prefix(n))
        let d = Duo(positions: starts, features: cast.map { OnePieceInvariantTests.characters[$0].1 }, seed: seed, quiet: true)
        keep.append(d)
        for r in d.lab.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true }
        d.live = true
        let rigs = d.lab.rigs
        let a = rigs[0], b = rigs[1]
        var shooter: CameraShooter? = nil
        if shootEvery > 0, let device { shooter = try? CameraShooter(device: device, d: d) }
        let palettes = cast.map { ContactPolishTests.palette($0) }
        AudioHub.requestTap = { res.sounds[$0, default: 0] += 1 }
        EmoteHaptic.requestTap = { res.haps["emote:" + $0, default: 0] += 1 }
        EmoteTreats.requestTap = { res.haps["treat:" + $0, default: 0] += 1 }
        res.started = a.brain.socialStart(kind, with: b.brain, a.sim)
        guard res.started else { return res }
        var sessionSeen = false
        let maxF = Int(maxSec * 60)
        var evPrev = 0
        var frame = 0
        while frame < maxF {
            d.tick()
            for (i, r) in rigs.enumerated() { d.lab.watch[i].sample(r) }
            let ph = a.brain.social?.phase ?? -1
            if a.brain.social != nil { sessionSeen = true }
            let evNow = rigs.reduce(0) { $0 + $1.brain.contactEvents }
            if evNow > evPrev {
                let S = d.contactSurfaces()
                for _ in 0..<(evNow - evPrev) { res.touchGaps.append(BruteForceContactMetric.skinGap(S[0], S[1])) }
                evPrev = evNow
            }
            if frame % 2 == 0, ph >= 1 {
                let S = d.contactSurfaces()
                let Sb = d.contactSurfacesNoSkin(bodyOnly: true)
                let armY = HandReach.restExtreme.y
                let sa = band(d, 0, lo: armY - 0.12, hi: armY + 0.12), sb = band(d, 1, lo: armY - 0.12, hi: armY + 0.12)
                let tops = Sb.map { $0.points.map { $0.y }.max() ?? 1 }
                let ha = band(d, 0, lo: tops[0] - 0.22, hi: 9), hb = band(d, 1, lo: tops[1] - 0.22, hi: 9)
                let g = BruteForceContactMetric.skinGap(S[0], S[1])
                if g < 8 || true {
                    res.samples.append(Sample(t: Float(frame) / 60, phase: ph, skin: g, body: BruteForceContactMetric.skinGap(Sb[0], Sb[1]), armLevel: gapOf(sa, sb), head: gapOf(ha, hb), sepRoot: simd_distance(a.root, b.root), armArm: armToSkin(d, S)))
                }
                if res.startedPhase2 < 0, ph >= 2 { res.startedPhase2 = Float(frame) / 60 }
            }
            if let sh = shooter, ph >= 1, frame % shootEvery == 0 {
                let S = d.contactSurfaces()
                let g = BruteForceContactMetric.skinGap(S[0], S[1])
                let armY = HandReach.restExtreme.y
                let ag = gapOf(band(d, 0, lo: armY - 0.12, hi: armY + 0.12), band(d, 1, lo: armY - 0.12, hi: armY + 0.12))
                let (img, crop) = sh.shot(d, palettes: palettes)
                res.shots.append(Shot(t: Float(frame) / 60, phase: ph, skin: g, arm: ag, image: img, crop: crop))
            }
            frame += 1
            if sessionSeen && !d.lab.anySocial && frame > 10 { res.completed = true; break }
        }
        res.seconds = Float(frame) / 60
        for i in 0..<n { for e in d.lab.events[i] { switch e { case .boop, .makeUp: res.hearts += 1; default: break } } }
        AudioHub.requestTap = nil; EmoteHaptic.requestTap = nil; EmoteTreats.requestTap = nil
        return res
    }

    /// The home room camera, the real renderer, phone aspect; the full frame is cropped around the pair.
    @MainActor final class CameraShooter {
        let ren: MelonRenderer, target: MTLTexture
        init(device: MTLDevice, d: Duo) throws {
            guard let r = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: d.lab.rigs[0].sim.edges, particleCount: d.lab.rigs[0].sim.n, game: true, bodyCount: d.lab.rigs.count), r.room != nil else { throw XCTSkip("no renderer") }
            ren = r
            ren.resize(width: PairProbe.W, height: PairProbe.H)
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: PairProbe.W, height: PairProbe.H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            target = device.makeTexture(descriptor: td)!
            ren.roomCacheEnabled = false
        }
        func shot(_ d: Duo, palettes: [Palette]) -> (UIImage, CGRect) {
            let W = PairProbe.W, H = PairProbe.H
            let n = d.lab.rigs.count
            ren.beginFrame()
            var jobs: [JellyParallel.SkinJob] = []
            for (i, r) in d.lab.rigs.enumerated() {
                let dst = ren.dynPointer(body: i)
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: dst)
                jobs.append(JellyParallel.SkinJob(skinner: r.skinner, sim: r.sim, dst: dst, id: i))
                ren.setPalette(palettes[i], body: i)
            }
            FeatureClip.apply(jobs: jobs)
            if FeatureClip.eggs.count != n { FeatureClip.eggs = jobs.map { ClipEgg(sim: $0.sim) } }
            var all = RoomMesh()
            for i in 0..<n {
                d.feats[i].syncCarry(i, sim: d.lab.rigs[i].sim)
                let m = d.feats[i].frame { [ren] id in UnsafePointer(ren.dynPointer(body: id)) }
                let base = UInt32(all.vertices.count)
                all.vertices += m.vertices; all.indices += m.indices.map { $0 + base }
            }
            ren.room!.setWear(opaque: all, translucent: RoomMesh(), bounds: [])
            ren.room!.setShoes(RoomMesh())
            ren.room!.setMasks(opaque: RoomMesh(), translucent: RoomMesh())
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = palettes[0]
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: GameCamera.light(centroids: d.lab.rigs.map { $0.sim.centroid() }), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            let img = LockImage(w: W, h: H, bgra: px).uiImage()!
            // crop around the pair's middle (screen)
            let cs = d.lab.rigs.map { $0.sim.centroid() }
            var c = SIMD3<Float>.zero; for x in cs { c += x }; c /= Float(n)
            let p = cam.viewProj * SIMD4<Float>(c.x, c.y, c.z, 1)
            let sx = CGFloat((p.x / p.w * 0.5 + 0.5)) * CGFloat(W), sy = CGFloat((0.5 - p.y / p.w * 0.5)) * CGFloat(H)
            let cw: CGFloat = 340, ch: CGFloat = 250
            let rect = CGRect(x: min(max(sx - cw / 2, 0), CGFloat(W) - cw), y: min(max(sy - ch / 2, 0), CGFloat(H) - ch), width: cw, height: ch)
            let cg = img.cgImage!.cropping(to: rect)!
            return (UIImage(cgImage: cg), rect)
        }
    }

    // MARK: board

    static func board(rows: [(String, [UIImage])], to path: String, cell: CGSize) throws {
        let cols = rows.map { $0.1.count }.max() ?? 1, pad = 4, label = 26
        let sw = cols * (Int(cell.width) + pad) + pad, sh = rows.count * (Int(cell.height) + label + pad) + pad
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sw, height: sh), format: fmt).image { _ in
            UIColor(white: 0.12, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: sw, height: sh))
            for (r, row) in rows.enumerated() {
                let y0 = pad + r * (Int(cell.height) + label + pad)
                (row.0 as NSString).draw(at: CGPoint(x: CGFloat(pad + 4), y: CGFloat(y0 + 4)), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white])
                for (c, im) in row.1.enumerated() { im.draw(in: CGRect(x: pad + c * (Int(cell.width) + pad), y: y0 + label, width: Int(cell.width), height: Int(cell.height))) }
            }
        }
        try img.pngData()!.write(to: URL(fileURLWithPath: path))
    }

    /// Five frames spread over the run (the first at the start of the session, the last just before the end).
    static func five(_ shots: [Shot]) -> [Shot] {
        guard shots.count > 5 else { return shots }
        return (0..<5).map { shots[$0 * (shots.count - 1) / 4] }
    }
    static func contactMoment(_ shots: [Shot]) -> Shot? { shots.filter { $0.phase >= 2 }.min { $0.skin < $1.skin } }
}
