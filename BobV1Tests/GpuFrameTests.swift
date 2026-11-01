//
//  GpuFrameTests.swift
//  GPU frame structure outside the body shader, measured with real GPU timestamps (run with the "Designed for iPhone" Mac destination:
//  the simulator reports no usable gpuStart/EndTime). Prints "GPUFRAME ..." lines and writes scratchpad/gpuframe/table.txt.
//

import XCTest
import Metal
import simd
import QuartzCore
import SwiftUI
import MetalKit
import UIKit
@testable import BobV1

@MainActor
final class GpuFrameTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let outDir = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/gpuframe"

    /// Mean gpu ms of the frame's single command buffer (drained each frame), plus the kernel (queue) span, and the per-pass line when PerfPasses is on.
    func measure(_ s: GpuOptPerfTests.Scene, frames: Int = 60) -> (gpu: Double, kernel: Double, wall: Double, passes: String) {
        let perf = s.ren.splitPasses
        for _ in 0..<10 { s.frame(wait: false); s.lastCmd?.waitUntilCompleted() }
        _ = s.ren.takePassStats()
        var gpu = 0.0, kern = 0.0, wall = 0.0
        for _ in 0..<frames {
            let t0 = CACurrentMediaTime()
            s.frame(wait: false)
            if perf { let f = s.ren.queue.makeCommandBuffer()!; f.commit(); f.waitUntilCompleted() } else { s.lastCmd?.waitUntilCompleted() }
            wall += CACurrentMediaTime() - t0
            if let c = s.lastCmd { gpu += c.gpuEndTime - c.gpuStartTime; kern += c.kernelEndTime - c.kernelStartTime }
        }
        usleep(200_000)
        let n = Double(frames)
        return (gpu / n * 1000, kern / n * 1000, wall / n * 1000, s.ren.takePassStats())
    }

    func testFrameAccounting() throws {
        try FileManager.default.createDirectory(atPath: Self.outDir, withIntermediateDirectories: true)
        var rows: [String] = []
        func row(_ s: String) { rows.append(s); print("GPUFRAME " + s); NSLog("GPUFRAME %@", s) }
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        row("device \(device.name) unifiedMemory=\(device.hasUnifiedMemory)")
        for (W, H) in [(880, 1912), (1206, 2622)] {
            for (perf, enc) in [(false, false), (false, true), (true, false), (true, true)] {
                UserDefaults.standard.set(perf, forKey: "PerfPasses"); UserDefaults.standard.set(enc, forKey: "PerfEncoders")
                let before = device.currentAllocatedSize
                let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 3, W: W, H: H))
                Self.keep.append(s)
                var o = GfxOpt(); o.memorylessMSAA = true; o.frontToBack = false; s.ren.gfxOpt = o
                s.ren.roomCacheEnabled = true
                let mem = Double(device.currentAllocatedSize - before) / 1_048_576
                let r = measure(s)
                row(String(format: "%dx%d perfPasses=%@ encoders=%@ cmdgpu=%.2f ms kernel=%.2f ms wall=%.2f ms alloc=%.1f MB cache=%@ memoryless=%@ | %@", W, H, perf ? "on" : "off", enc ? "on" : "off", r.gpu, r.kernel, r.wall, mem, "\(s.ren.lastCacheAction)", s.ren.targetsMemoryless ? "y" : "n", r.passes))
            }
        }
        UserDefaults.standard.removeObject(forKey: "PerfPasses"); UserDefaults.standard.removeObject(forKey: "PerfEncoders")
        try? rows.joined(separator: "\n").write(toFile: Self.outDir + "/table.txt", atomically: true, encoding: .utf8)
    }

    /// Ablation: single command buffer GPU ms with parts of the frame switched off (interleaved blocks cancel clock drift).
    func testAblation() throws {
        UserDefaults.standard.removeObject(forKey: "PerfPasses"); UserDefaults.standard.removeObject(forKey: "PerfEncoders")
        func row(_ s: String) { print("GPUFRAME " + s); NSLog("GPUFRAME %@", s) }
        let variants: [(String, Set<String>, Bool)] = [("baseline", [], false), ("no post", ["post"], false), ("no shadow+height", ["shadow", "height"], false),
                                                       ("no blended", ["blended"], false), ("no bodies", [], true), ("no post/shadow/height/blended/bodies", ["post", "shadow", "height", "blended"], true)]
        for (W, H) in [(880, 1912), (1206, 2622)] {
            let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 3, W: W, H: H))
            Self.keep.append(s)
            var o = GfxOpt(); o.memorylessMSAA = true; s.ren.gfxOpt = o
            s.ren.roomCacheEnabled = true
            var sums = [Double](repeating: 0, count: variants.count)
            for _ in 0..<4 {
                for (i, v) in variants.enumerated() {
                    s.ren.debugSkip = v.1
                    for k in 0..<3 { s.ren.setHidden(v.2, body: k) }
                    sums[i] += measure(s, frames: 40).gpu
                }
            }
            s.ren.debugSkip = []; for k in 0..<3 { s.ren.setHidden(false, body: k) }
            for (i, v) in variants.enumerated() { row(String(format: "%dx%d ablation %@: %.2f ms (%+.2f vs baseline)", W, H, v.0, sums[i] / 4, (sums[i] - sums[0]) / 4)) }
        }
    }

    /// What makes a long GPU frame: per-frame GPU ms by room-cache action, a camera pan, a light step and a resize, 3 Jellies.
    func testSpikes() throws {
        UserDefaults.standard.removeObject(forKey: "PerfPasses"); UserDefaults.standard.removeObject(forKey: "PerfEncoders")
        func row(_ s: String) { print("GPUFRAME " + s); NSLog("GPUFRAME %@", s) }
        for (W, H) in [(880, 1912), (1206, 2622)] {
            let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 3, W: W, H: H))
            Self.keep.append(s)
            var o = GfxOpt(); o.memorylessMSAA = true; s.ren.gfxOpt = o
            s.ren.roomCacheEnabled = true
            var log: [(String, Double)] = []
            func one(_ tag: String) {
                s.frame(wait: false); s.lastCmd?.waitUntilCompleted()
                if let c = s.lastCmd { log.append((tag + ":" + "\(s.ren.lastCacheAction)", (c.gpuEndTime - c.gpuStartTime) * 1000)) }
            }
            func report(_ name: String) {
                var by: [String: [Double]] = [:]
                for (k, v) in log { by[k, default: []].append(v) }
                for k in by.keys.sorted() { let v = by[k]!.sorted(); row(String(format: "%dx%d %@ %@: n=%d mean %.2f max %.2f", W, H, name, k, v.count, v.reduce(0, +) / Double(v.count), v.last!)) }
                log = []
            }
            for _ in 0..<20 { s.frame(wait: false); s.lastCmd?.waitUntilCompleted() }
            for _ in 0..<60 { one("steady") }
            report("steady")
            // forced rebuilds: invalidate -> settling x3 (full room) -> build -> use
            for _ in 0..<6 { s.ren.invalidateRoomCache(); for _ in 0..<6 { one("rebuild") } }
            report("invalidate+rebuild")
            // light step every 20 frames (what a DayClock tick / tuck step does)
            for k in 0..<5 { s.ren.dayHourOverride = 12 + Double(k) * 0.5; for _ in 0..<12 { one("lightstep") } }
            report("lightstep")
            s.ren.dayHourOverride = nil
            // resize like the RenderScaler: 10% down and back
            for _ in 0..<3 {
                s.ren.resize(width: Int(Double(W) * 0.9), height: Int(Double(H) * 0.9)); for _ in 0..<8 { one("resized") }
                s.ren.resize(width: W, height: H); for _ in 0..<8 { one("restored") }
            }
            report("resize")
        }
    }

    /// Writes the PNG into the app container and attaches it to the result bundle (the sandboxed Mac app cannot write to the scratchpad).
    func save(_ img: LockImage, _ name: String) {
        let url = URL(fileURLWithPath: Self.outPath + "/" + name + ".png")
        img.png(to: url)
        if let d = try? Data(contentsOf: url) { let a = XCTAttachment(data: d, uniformTypeIdentifier: "public.png"); a.name = name + ".png"; a.lifetime = .keepAlways; add(a) }
    }
    static var outPath: String { NSTemporaryDirectory() + "gpuframe" }

    static func resized(_ img: LockImage, toW w: Int, h: Int) -> LockImage {
        var src = img.bgra
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let cg = src.withUnsafeMutableBytes { CGContext(data: $0.baseAddress, width: img.w, height: img.h, bitsPerComponent: 8, bytesPerRow: img.w * 4, space: cs, bitmapInfo: info)!.makeImage()! }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes {
            let c = CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: info)!
            c.interpolationQuality = .low        // bilinear: what the compositor does with a smaller drawable
            c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return LockImage(w: w, h: h, bgra: out)
    }

    static func psnr(_ a: LockImage, _ b: LockImage) -> Double {
        var se = 0.0
        for i in stride(from: 0, to: a.bgra.count, by: 4) { for c in 0..<3 { let d = Double(a.bgra[i + c]) - Double(b.bgra[i + c]); se += d * d } }
        let mse = se / Double(a.w * a.h * 3)
        return mse == 0 ? 99 : 10 * log10(255 * 255 / mse)
    }

    /// MetalFX spatial upscaling quality + cost against today's bilinear-scaled smaller drawable, all presented at native 1206 x 2622.
    func testMetalFX() throws {
        UserDefaults.standard.removeObject(forKey: "PerfPasses"); UserDefaults.standard.removeObject(forKey: "PerfEncoders")
        try FileManager.default.createDirectory(atPath: Self.outPath, withIntermediateDirectories: true)
        func row(_ s: String) { print("GPUFRAME " + s); NSLog("GPUFRAME %@", s) }
        row("out dir \(Self.outPath) metalfx supported \(GfxUpscaler.supported(MTLCreateSystemDefaultDevice()!))")
        let NW = 1206, NH = 2622
        func run(_ w: Int, _ h: Int, fx: Bool) throws -> (LockImage, Double) {
            let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 3, W: w, H: h))
            Self.keep.append(s)
            var o = GfxOpt(); o.memorylessMSAA = true; s.ren.gfxOpt = o
            s.ren.roomCacheEnabled = true
            if fx {
                let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: NW, height: NH, mipmapped: false)
                td.usage = [.renderTarget, .shaderRead, .shaderWrite]; td.storageMode = .shared
                s.target = s.ren.device.makeTexture(descriptor: td)!
                s.ren.metalFXEnabled = true
            }
            for _ in 0..<6 { s.frame(advance: false) }
            let ms = measure(s, frames: 60).gpu
            s.frame(advance: false)
            return (s.image(), ms)
        }
        let (native, nms) = try run(NW, NH, fx: false)
        save(native, "native_1206")
        row(String(format: "native %dx%d: gpu %.2f ms", NW, NH, nms))
        for (w, h) in [(1005, 2185), (880, 1912), (804, 1748), (603, 1311), (585, 1271)] {
            let (raw, rms) = try run(w, h, fx: false)
            let up = Self.resized(raw, toW: NW, h: NH)
            save(up, "bilinear_\(w)")
            row(String(format: "raw %dx%d + compositor bilinear: gpu %.2f ms, PSNR vs native %.2f dB", w, h, rms, Self.psnr(native, up)))
            let (fx, fms) = try run(w, h, fx: true)
            save(fx, "metalfx_\(w)")
            row(String(format: "MetalFX %dx%d -> %dx%d: gpu %.2f ms (upscale+present +%.2f), PSNR vs native %.2f dB", w, h, NW, NH, fms, fms - rms, Self.psnr(native, fx)))
        }
    }

    /// Room cache on/off x camera still / drifting x focus 0 / 0.5 / 1 / drifting, at the scaler rungs, 3 Jellies. GPU ms per frame.
    func testFocusAndMotion() throws {
        UserDefaults.standard.removeObject(forKey: "PerfPasses"); UserDefaults.standard.removeObject(forKey: "PerfEncoders")
        func row(_ s: String) { print("GPUFRAME " + s); NSLog("GPUFRAME %@", s) }
        struct Sc { var name: String; var cache: Bool; var focus: (Int) -> Float; var drift: Bool; var hide = false }
        let scs: [Sc] = [
            Sc(name: "room still, cache on", cache: true, focus: { _ in 0 }, drift: false),
            Sc(name: "room still, cache off", cache: false, focus: { _ in 0 }, drift: false),
            Sc(name: "room camera drifting, cache on", cache: true, focus: { _ in 0 }, drift: true),
            Sc(name: "focus 0.5 still, cache on", cache: true, focus: { _ in 0.5 }, drift: false),
            Sc(name: "focus 1 still, cache on", cache: true, focus: { _ in 1 }, drift: false),
            Sc(name: "focus 1 still, cache off", cache: false, focus: { _ in 1 }, drift: false),
            Sc(name: "focus drifting 0..1, cache on", cache: true, focus: { 0.5 + 0.5 * sinf(Float($0) * 0.05) }, drift: false),
            Sc(name: "focus 1 still, bodies hidden (room only)", cache: false, focus: { _ in 1 }, drift: false, hide: true),
            Sc(name: "room still, bodies hidden (room only)", cache: false, focus: { _ in 0 }, drift: false, hide: true),
        ]
        for (W, H) in [(585, 1271), (880, 1912), (1206, 2622)] {
            let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 3, W: W, H: H))
            Self.keep.append(s)
            var o = GfxOpt(); o.memorylessMSAA = true; s.ren.gfxOpt = o
            for sc in scs {
                s.ren.roomCacheEnabled = sc.cache
                for k in 0..<3 { s.ren.setHidden(sc.hide, body: k) }
                s.ren.invalidateRoomCache(); s.ren.resetRoomCacheCounters(); s.ren.perfFocus = sc.focus(0) > 0.9; _ = s.ren.takePerfContext()
                var gpu = 0.0, mx = 0.0, shaded = 0.0, base = 0.0
                let frames = 90
                for f in 0..<(frames + 10) {
                    var c = GameCamera.camera(aspect: Float(W) / Float(H), focus: sc.focus(f))
                    if sc.drift { c.pos.x += 0.0005 * Float(f) }
                    s.cam = c
                    s.frame(wait: false); s.lastCmd?.waitUntilCompleted()
                    if f == 9 { s.ren.resetRoomCacheCounters() }
                    if f >= 10, let cb = s.lastCmd { let t = (cb.gpuEndTime - cb.gpuStartTime) * 1000; gpu += t; mx = max(mx, t) }
                }
                shaded = s.ren.roomPixelsShaded; base = s.ren.roomPixelsBaseline
                row(String(format: "%dx%d %@: gpu mean %.2f max %.2f ms, cache hit %.0f%%, room px shaded %.0f%%, last %@ fp %.0f%%", W, H, sc.name, gpu / Double(frames), mx, s.ren.roomCacheHitRate * 100, base > 0 ? shaded / base * 100 : 0, "\(s.ren.lastCacheAction)", s.ren.lastFootprintShare * 100))
                usleep(100_000); row("    " + s.ren.takePerfContext())
            }
            for k in 0..<3 { s.ren.setHidden(false, body: k) }
        }
    }

    /// Our frame's GPU ms with a live MTKView in a real window and a SwiftUI HUD over it: no overlay, opaque pills, Liquid Glass pills.
    /// (Mac "Designed for iPhone": WindowServer composites, not backboardd - structure only, the phone decides.)
    func testGlassOverlayContention() throws {
        UserDefaults.standard.removeObject(forKey: "PerfPasses"); UserDefaults.standard.removeObject(forKey: "PerfEncoders")
        func row(_ s: String) { print("GPUFRAME " + s); NSLog("GPUFRAME %@", s) }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { throw XCTSkip("no window scene") }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let device = MTLCreateSystemDefaultDevice()!
        let view = MTKView(frame: window.bounds, device: device)
        view.colorPixelFormat = .bgra8Unorm; view.framebufferOnly = true; view.isPaused = true; view.enableSetNeedsDisplay = false
        view.isOpaque = true
        let ds = view.drawableSize
        row("window \(window.bounds.size) drawable \(Int(ds.width))x\(Int(ds.height)) scale \(view.contentScaleFactor)")
        let W = Int(ds.width), H = Int(ds.height)
        let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 3, W: W, H: H))
        Self.keep.append(s)
        var o = GfxOpt(); o.memorylessMSAA = true; s.ren.gfxOpt = o; s.ren.roomCacheEnabled = true

        func hud(_ mode: Int) -> some View {
            // mode 0 none, 1 opaque, 2 glass: a top pill row, a left rail, a paw circle and a roster-style panel
            ZStack {
                if mode > 0 {
                    VStack {
                        HStack { pill(mode, 90, 44); Spacer(); pill(mode, 160, 44) }.padding(.top, 60).padding(.horizontal, 16)
                        Spacer()
                        HStack(alignment: .bottom) { VStack { ForEach(0..<4, id: \.self) { _ in pill(mode, 52, 52) } }; Spacer(); pill(mode, 72, 72) }.padding(16).padding(.bottom, 20)
                    }
                    RoundedRectangle(cornerRadius: 26).fill(mode == 1 ? Color.white.opacity(0.95) : Color.white.opacity(0.01)).frame(width: 260, height: 300)
                        .modifier(GlassIf(on: mode == 2)).offset(y: -60)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        func pill(_ mode: Int, _ w: CGFloat, _ h: CGFloat) -> some View {
            Capsule().fill(mode == 1 ? Color.white.opacity(0.9) : Color.white.opacity(0.4)).frame(width: w, height: h).modifier(GlassIf(on: mode == 2))
        }
        func run(_ mode: Int, _ name: String) {
            let host = UIHostingController(rootView: hud(mode))
            host.view.backgroundColor = .clear
            let root = UIViewController(); root.view.addSubview(view); view.frame = root.view.bounds
            root.addChild(host); root.view.addSubview(host.view); host.view.frame = root.view.bounds; host.didMove(toParent: root)
            window.rootViewController = root; window.isHidden = false; window.makeKeyAndVisible()
            for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            var ms: [Double] = [], wall: [Double] = []
            let t0 = CACurrentMediaTime()
            for i in 0..<240 {
                guard let d = view.currentDrawable else { continue }
                s.frame(advance: true, wait: false, drawable: d)
                RunLoop.current.run(until: Date().addingTimeInterval(0.001))
                if i >= 30 { ms.append(s.ren.lastGPUMs) }
            }
            wall.append((CACurrentMediaTime() - t0) / 240 * 1000)
            usleep(100_000)
            ms.sort()
            row(String(format: "%@: gpu mean %.2f p95 %.2f max %.2f ms, frame interval %.1f ms", name, ms.reduce(0, +) / Double(max(ms.count, 1)), ms[Int(Double(ms.count) * 0.95)], ms.last ?? 0, wall[0]))
            host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent(); view.removeFromSuperview()
        }
        for round in 0..<2 { run(0, "r\(round) no overlay"); run(1, "r\(round) opaque pills"); run(2, "r\(round) Liquid Glass pills") }
    }
}

extension GpuFrameTests {
    /// -GpuCal: the calibration kernels should read the same cost every frame; the ctx line carries cal / qwait / thermal / gpuMem.
    func testGpuCalibrationLine() throws {
        UserDefaults.standard.set(true, forKey: "GpuCal"); defer { UserDefaults.standard.removeObject(forKey: "GpuCal") }
        let s = try XCTUnwrap(GpuOptPerfTests.Scene(n: 3, W: 880, H: 1912))
        Self.keep.append(s)
        s.ren.roomCacheEnabled = true
        for _ in 0..<150 { s.frame(wait: false); s.lastCmd?.waitUntilCompleted() }
        usleep(300_000)
        let line = s.ren.takePerfContext()
        print("GPUFRAME " + line); NSLog("GPUFRAME %@", line)
        XCTAssertTrue(line.contains("cal[alu"), line)
        XCTAssertTrue(line.contains("qwait["), line)
        XCTAssertTrue(line.contains("thermal "), line)
    }
}

private struct GlassIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { if on { content.glassEffect(.regular.tint(Color.white.opacity(0.55)).interactive(), in: .rect(cornerRadius: 26)) } else { content } }
}
