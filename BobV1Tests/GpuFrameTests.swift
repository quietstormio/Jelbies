//
//  GpuFrameTests.swift
//  GPU frame structure outside the body shader, measured with real GPU timestamps (run with the "Designed for iPhone" Mac destination:
//  the simulator reports no usable gpuStart/EndTime). Prints "GPUFRAME ..." lines and writes scratchpad/gpuframe/table.txt.
//

import XCTest
import Metal
import simd
import QuartzCore
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
}
