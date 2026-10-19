//
//  GpuOptPerfTests.swift
//  GPU-side options (GfxOpt: memoryless targets, body order, fast matte tiers, shadow size, room cache with 3 Jellies) measured headless at
//  phone proportion (1100 x 2390, one command buffer per frame, PerfPasses OFF). The simulator's gpuStart/EndTime are not usable, so the
//  cost is wall time per frame with the GPU drained each frame; the body pass is isolated as wall(bodies visible) - wall(bodies hidden),
//  which also cancels skinning / encoding CPU time. Variants are interleaved in blocks to cancel clock drift.
//  Also the pixel diff of every fast tier against the locked shader (in-process A/B, same frame) and the frames for the MetalFX
//  side-by-side (gpuopt/frames). Prints "GPUOPT ..." lines; writes scratchpad/gpuopt/perf_table.txt.
//

import XCTest
import Metal
import simd
import QuartzCore
@testable import BobV1

@MainActor
final class GpuOptPerfTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let outDir = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/gpuopt"

    @MainActor final class Scene {
        let W: Int, H: Int, n: Int
        let actors: [JellyActor]
        let ren: MelonRenderer
        let target: MTLTexture
        let cam: CameraState
        var time: Float = 3.7

        init?(n: Int, W: Int, H: Int, shadow: Int? = nil) {
            self.W = W; self.H = H; self.n = n
            let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
            let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            let spots = JellyRoster.spawnSpots(count: n)
            actors = (0..<n).map {
                let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
                a.reset(drop: 0.35, shift: n > 1)
                for _ in 0..<200 { a.sim.step() }
                a.skinner.autoBlink = false
                return a
            }
            guard let r = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: rm, simEdges: actors[0].sim.edges, particleCount: actors[0].sim.n, game: true, bodyCount: n, shadowSizeOverride: shadow) else { return nil }
            ren = r
            ren.resize(width: W, height: H)
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            target = device.makeTexture(descriptor: td)!
            for i in 1..<max(n, 1) { ren.setPalette(JellyRoster.palette(i) ?? PaletteKey.blue.palette, body: i) }
            cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            ren.roomCacheEnabled = false
        }

        func setDirt(_ dirt: Float) {
            for i in 0..<n {
                var l = BathLook(); l.dirt = dirt; l.soot = BathLook.sootSeed(dirt: dirt); l.sootStyle = Float(i)
                ren.setBathLook(l, body: i)
            }
        }

        /// One frame; GPU drained unless `wait` is false (then the ring lets up to BodySlot.ring frames overlap). Returns the wall time (s).
        @discardableResult
        func frame(advance: Bool = true, wait: Bool = true) -> Double {
            ren.beginFrame()
            for a in actors { a.skinner.update(x: a.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer(body: a.id)) }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0; fp.time = time
            if advance { time += 0.016 }
            let pal = PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: GameCamera.light(centroids: actors.map { $0.sim.centroid() }), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(W), Float(H)))
            let cmd = ren.queue.makeCommandBuffer()!
            let t0 = CACurrentMediaTime()
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            if wait { cmd.waitUntilCompleted() } else { lastCmd = cmd }
            return CACurrentMediaTime() - t0
        }
        var lastCmd: MTLCommandBuffer?

        /// Mean wall ms per frame with frames submitted back to back (CPU skin + encode overlapping the GPU, as the app runs).
        func pipelinedMs(frames: Int = 60) -> Double {
            for _ in 0..<4 { frame(wait: false) }
            lastCmd?.waitUntilCompleted()
            let t0 = CACurrentMediaTime()
            for _ in 0..<frames { frame(wait: false) }
            lastCmd?.waitUntilCompleted()
            return (CACurrentMediaTime() - t0) / Double(frames) * 1000
        }

        /// Mean wall ms per frame over `frames` (after `warm` warm-up frames).
        func ms(frames: Int = 40, warm: Int = 4) -> Double {
            for _ in 0..<warm { frame() }
            var t = 0.0
            for _ in 0..<frames { t += frame() }
            return t / Double(frames) * 1000
        }

        func image() -> LockImage {
            var px = [UInt8](repeating: 0, count: W * H * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0) }
            return LockImage(w: W, h: H, bgra: px)
        }
    }

    /// Interleaved A/B: `blocks` alternations of A then B, each `frames` long; returns (msA, msB).
    func ab(_ s: Scene, blocks: Int = 3, frames: Int = 30, a: () -> Void, b: () -> Void) -> (Double, Double) {
        var ta = 0.0, tb = 0.0
        for _ in 0..<blocks {
            a(); ta += s.ms(frames: frames, warm: 3)
            b(); tb += s.ms(frames: frames, warm: 3)
        }
        return (ta / Double(blocks), tb / Double(blocks))
    }

    func testBodyCostAndOptions() throws {
        UserDefaults.standard.removeObject(forKey: "PerfPasses")      // BodyPassPerfTests persists it; this test wants the real single-command-buffer frame
        try FileManager.default.createDirectory(atPath: Self.outDir + "/frames", withIntermediateDirectories: true)
        var rows: [String] = []
        func row(_ s: String) { rows.append(s); print("GPUOPT " + s); NSLog("GPUOPT %@", s) }
        let W = 1100, H = 2390
        for n in [1, 3] {
            let s = try XCTUnwrap(Scene(n: n, W: W, H: H))
            Self.keep.append(s)
            XCTAssertFalse(s.ren.perfPasses)
            // ---- baseline: old path (no memoryless, slot order, locked shader) ----
            var old = GfxOpt(); old.memorylessMSAA = false; old.frontToBack = false; old.fastMatteTier = 0
            s.ren.gfxOpt = old
            let total = s.ms(frames: 40)
            for i in 0..<n { s.ren.setHidden(true, body: i) }
            let hidden = s.ms(frames: 40)
            for i in 0..<n { s.ren.setHidden(false, body: i) }
            row(String(format: "n=%d %dx%d baseline: frame %.3f ms, bodies hidden %.3f ms -> body pass ~%.3f ms (memoryless=%@)", n, W, H, total, hidden, total - hidden, s.ren.targetsMemoryless ? "on" : "off"))
            // ---- Q1 ring: frames submitted back to back (CPU and GPU overlap) vs drained each frame (the old 1-deep semaphore behaviour) ----
            let piped = s.pipelinedMs(frames: 60)
            row(String(format: "n=%d triple-buffered pipeline: %.3f ms/frame back-to-back vs %.3f ms drained per frame (ring %d, skin+encode CPU per frame ~%.3f ms)", n, piped, total, BodySlot.ring, hidden))
            if n == 3 { s.frame(); s.image().png(to: URL(fileURLWithPath: Self.outDir + "/frames/before_3_1100.png")) }

            // ---- memoryless targets (pixel-identical) ----
            var mem = old; mem.memorylessMSAA = true
            var (a, b) = ab(s, a: { s.ren.gfxOpt = old }, b: { s.ren.gfxOpt = mem })
            s.ren.gfxOpt = mem; s.frame()
            row(String(format: "n=%d memoryless MSAA/depth: %.3f -> %.3f ms (%+.3f) targets memoryless=%@", n, a, b, b - a, s.ren.targetsMemoryless ? "yes" : "NO (unsupported here)"))
            // pixel identity of the memoryless path
            s.ren.gfxOpt = old; s.frame(advance: false); let imgOld = s.image()
            s.ren.gfxOpt = mem; s.frame(advance: false); let imgMem = s.image()
            row("n=\(n) memoryless pixel diff vs old path: \(GfxDiff(imgOld, imgMem).summary)")
            XCTAssertEqual(imgOld.maxDiff(imgMem), 0, "memoryless targets must not change pixels")

            // ---- front-to-back order (pixel-identical) ----
            if n > 1 {
                var ord = mem; ord.frontToBack = true
                (a, b) = ab(s, a: { s.ren.gfxOpt = mem }, b: { s.ren.gfxOpt = ord })
                s.ren.gfxOpt = ord; s.frame(advance: false); let imgOrd = s.image()
                row(String(format: "n=%d front-to-back order %@: %.3f -> %.3f ms (%+.3f); pixel diff %@", n, "\(s.ren.lastBodyOrder)", a, b, b - a, GfxDiff(imgMem, imgOrd).summary))
                XCTAssertEqual(imgMem.maxDiff(imgOrd), 0, "draw order must not change pixels")
            }

            // ---- fast matte tiers (pixel-changing opt-in) ----
            var ref = mem; ref.frontToBack = true
            s.ren.gfxOpt = ref; s.frame(advance: false); let imgRef = s.image()
            for tier in 1...3 {
                var fast = ref; fast.fastMatteTier = tier
                (a, b) = ab(s, a: { s.ren.gfxOpt = ref }, b: { s.ren.gfxOpt = fast })
                s.ren.gfxOpt = fast; s.frame(advance: false)
                let img = s.image()
                XCTAssertEqual(s.ren.lastBodyPipeline, "matteFast\(tier)")
                row(String(format: "n=%d fast matte tier %d: %.3f -> %.3f ms (%+.3f, body pass %.0f%%); pixel diff vs locked: %@", n, tier, a, b, b - a,
                           (total - hidden) > 0 ? (1 - (a - b) / (total - hidden)) * 100 : 0, GfxDiff(imgRef, img).summary))
                if n == 3 { img.png(to: URL(fileURLWithPath: Self.outDir + "/frames/fast\(tier)_3_1100.png")) }
            }
            s.ren.gfxOpt = ref
            if n == 3 { s.frame(advance: false); s.image().png(to: URL(fileURLWithPath: Self.outDir + "/frames/after_3_1100.png")) }

            // ---- dirty (bath shader) cost with the soot reject; function-constant variants vs the all-in-one bath shader ----
            s.setDirt(0.85)
            var noVar = ref; noVar.bathVariants = false
            var withVar = ref; withVar.bathVariants = true
            (a, b) = ab(s, a: { s.ren.gfxOpt = noVar }, b: { s.ren.gfxOpt = withVar })
            s.ren.gfxOpt = noVar; s.frame(advance: false); let imgNoVar = s.image()
            s.ren.gfxOpt = withVar; s.frame(advance: false); let imgVar = s.image()
            s.setDirt(0); s.ren.gfxOpt = ref
            row(String(format: "n=%d dirt 0.85 (soot reject in): frame %.3f ms (clean %.3f); bath function-constant variant: %.3f -> %.3f ms (%+.3f), pixel diff %@", n, a, total, a, b, b - a, GfxDiff(imgNoVar, imgVar).summary))
            if n == 3 { imgVar.png(to: URL(fileURLWithPath: Self.outDir + "/frames/dirty_3_1100.png")) }
            // ---- 16-bit shadow / height maps (flagged) ----
            var d16 = ref; d16.shadowDepth16 = true
            (a, b) = ab(s, a: { s.ren.gfxOpt = ref }, b: { s.ren.gfxOpt = d16 })
            s.ren.gfxOpt = d16; s.frame(advance: false); let img16 = s.image()
            let fmt16 = s.ren.lastShadowFormat
            s.ren.gfxOpt = ref; s.frame(advance: false)
            row(String(format: "n=%d shadow depth16 (%@): %.3f -> %.3f ms (%+.3f); pixel diff vs depth32 %@", n, "\(fmt16)", a, b, b - a, GfxDiff(s.image(), img16).summary))
            if n == 3 { img16.png(to: URL(fileURLWithPath: Self.outDir + "/frames/depth16_3_1100.png")) }

            // ---- room cache with several footprints ----
            s.ren.roomCacheEnabled = true
            s.ren.invalidateRoomCache(); s.ren.resetRoomCacheCounters()
            for _ in 0..<12 { s.frame() }
            let cached = s.ms(frames: 30)
            row(String(format: "n=%d room cache: frame %.3f ms (off %.3f), action %@, footprint %.0f%%, %@", n, cached, total, "\(s.ren.lastCacheAction)", s.ren.lastFootprintShare * 100, s.ren.roomCacheSummary))
            if n == 3 { XCTAssertEqual(s.ren.lastCacheAction, .use, "the room cache should be in use with 3 settled Jellies") }
            s.ren.roomCacheEnabled = false
        }
        // ---- shadow map size with 3 Jellies ----
        do {
            let s2048 = try XCTUnwrap(Scene(n: 3, W: W, H: H, shadow: 2048)), s1024 = try XCTUnwrap(Scene(n: 3, W: W, H: H, shadow: 1024))
            Self.keep += [s2048, s1024]
            var ta = 0.0, tb = 0.0
            for _ in 0..<3 { ta += s2048.ms(frames: 30, warm: 3); tb += s1024.ms(frames: 30, warm: 3) }
            s2048.frame(advance: false); s1024.frame(advance: false)
            row(String(format: "n=3 shadow 2048 -> 1024: %.3f -> %.3f ms (%+.3f); pixel diff %@", ta / 3, tb / 3, (tb - ta) / 3, GfxDiff(s2048.image(), s1024.image()).summary))
        }
        // ---- frames for the MetalFX side-by-side: the same 3-Jelly frame at 1.5x-equivalent (660 x 1434) and 2x (880 x 1912) ----
        for (w, h) in [(660, 1434), (880, 1912)] {
            let s = try XCTUnwrap(Scene(n: 3, W: w, H: h))
            Self.keep.append(s)
            s.frame(advance: false)
            s.image().png(to: URL(fileURLWithPath: Self.outDir + "/frames/before_3_\(w).png"))
            let t = s.ms(frames: 30)
            row(String(format: "n=3 %dx%d: frame %.3f ms", w, h, t))
        }
        try rows.joined(separator: "\n").write(toFile: Self.outDir + "/perf_table.txt", atomically: true, encoding: .utf8)
    }

    /// Frames for the before/after sheet: a fresh 3-Jelly scene per variant at 1100 x 2390 (and the 1.5x / 2x-equivalent sizes for MetalFX).
    func testCaptureFrames() throws {
        UserDefaults.standard.removeObject(forKey: "PerfPasses")
        try FileManager.default.createDirectory(atPath: Self.outDir + "/frames", withIntermediateDirectories: true)
        func capture(_ name: String, W: Int = 1100, H: Int = 2390, dirt: Float = 0, _ set: (GfxOpt) -> GfxOpt) throws -> LockImage {
            let s = try XCTUnwrap(Scene(n: 3, W: W, H: H))
            var old = GfxOpt(); old.memorylessMSAA = false; old.frontToBack = false; old.fastMatteTier = 0; old.bathVariants = false; old.shadowDepth16 = false
            s.ren.gfxOpt = set(old)
            if dirt > 0 { s.setDirt(dirt) }
            for _ in 0..<3 { s.frame(advance: false) }
            let img = s.image()
            XCTAssertGreaterThan(stride(from: 0, to: img.bgra.count, by: 4).reduce(0) { $0 + Int(img.bgra[$1]) + Int(img.bgra[$1 + 1]) + Int(img.bgra[$1 + 2]) }, 0, "\(name): black frame")
            img.png(to: URL(fileURLWithPath: Self.outDir + "/frames/\(name).png"))
            print("GPUOPT capture \(name): pipeline \(s.ren.lastBodyPipeline), memoryless \(s.ren.targetsMemoryless), order \(s.ren.lastBodyOrder), shadow \(s.ren.lastShadowFormat.rawValue)")
            return img
        }
        let before = try capture("before_3_1100") { $0 }
        let after = try capture("after_3_1100") { var o = $0; o.memorylessMSAA = true; o.frontToBack = true; o.bathVariants = true; return o }
        XCTAssertEqual(before.maxDiff(after), 0, "defaults must be pixel-identical")
        for tier in 1...3 { _ = try capture("fast\(tier)_3_1100") { var o = $0; o.fastMatteTier = tier; return o } }
        _ = try capture("depth16_3_1100") { var o = $0; o.shadowDepth16 = true; return o }
        let dirtyOld = try capture("dirty_3_1100_old", dirt: 0.85) { $0 }
        let dirtyVar = try capture("dirty_3_1100", dirt: 0.85) { var o = $0; o.bathVariants = true; return o }
        XCTAssertEqual(dirtyOld.maxDiff(dirtyVar), 0, "bath function-constant variants must be pixel-identical")
        // exact (all four channels) identity of the bath variants and memoryless targets on the kind of frame BathSootSeedZeroTests hashes
        do {
            let s = try XCTUnwrap(Scene(n: 1, W: 301, H: 655))
            var old = GfxOpt(); old.memorylessMSAA = false; old.frontToBack = false; old.bathVariants = false
            var l = BathLook(); l.dirt = 0.3; l.soot = BathLook.sootSeed(dirt: 0.3); l.sootStyle = 0
            s.ren.setBathLook(l, body: 0)
            s.ren.gfxOpt = old; s.frame(advance: false); s.frame(advance: false); let a = s.image()
            var v = old; v.bathVariants = true
            s.ren.gfxOpt = v; s.frame(advance: false); s.frame(advance: false); let b = s.image()
            var m = old; m.memorylessMSAA = true
            s.ren.gfxOpt = m; s.frame(advance: false); s.frame(advance: false); let c = s.image()
            print("GPUOPT soot-frame identity (301x655, dirt 0.3, all channels): bath variants max diff \(a.maxDiff(b)) (\(GfxDiff(a, b).summary)); memoryless max diff \(a.maxDiff(c))")
        }
        // the exact frame BathSootSeedZeroTests flags (Bob from the back, dirt 0.7): which option moves it?
        do {
            let s = try XCTUnwrap(GfxLabScene(width: 301, height: 655))
            s.place(SIMD2(0.4, 0.6))
            let cam = BathCaptureTests.orbitCam(s, azimuth: .pi)
            var old = GfxOpt(); old.memorylessMSAA = false; old.frontToBack = false; old.bathVariants = false
            s.ren.gfxOpt = old
            let a = BathCaptureTests.render(s, look: BathCaptureTests.sooty(0.7), camera: cam)
            var v = old; v.bathVariants = true; s.ren.gfxOpt = v
            let b = BathCaptureTests.render(s, look: BathCaptureTests.sooty(0.7), camera: cam)
            var m = old; m.memorylessMSAA = true; s.ren.gfxOpt = m
            let c = BathCaptureTests.render(s, look: BathCaptureTests.sooty(0.7), camera: cam)
            s.ren.gfxOpt = old
            let a2 = BathCaptureTests.render(s, look: BathCaptureTests.sooty(0.7), camera: cam)
            print("GPUOPT back_70 probe: old-vs-old max \(a.maxDiff(a2)); bath variants \(GfxDiff(a, b).summary); memoryless \(GfxDiff(a, c).summary); fnv old \(BathSootSeedZeroTests.fnv(a)) variants \(BathSootSeedZeroTests.fnv(b)) (recorded 159a053c8d58f292)")
        }
        _ = try capture("before_3_660", W: 660, H: 1434) { $0 }
        _ = try capture("before_3_880", W: 880, H: 1912) { $0 }
    }
}
