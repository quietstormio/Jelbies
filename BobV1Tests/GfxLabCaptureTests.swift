//
//  GfxLabCaptureTests.swift
//  Not regression tests: they write stills / timings when GFX_OUT is set (pass it as TEST_RUNNER_GFX_OUT). Skipped otherwise.
//    testCaptureStills   old path vs room cache (and 2x / 3x renders for the MetalFX comparison) for roaming / focus / dining / throw
//    testPassTimings     per-pass GPU ms (-PerfPasses path) old vs cache, plus pixel counts
//    testIdleEnergy      sim kinetic energy per unit mass while Bob stands still, to size the idle-rest threshold
//

import XCTest
import Metal
import simd
@testable import BobV1

@MainActor
final class GfxLabCaptureTests: XCTestCase {
    private func outDir() throws -> URL {
        guard let d = ProcessInfo.processInfo.environment["GFX_OUT"] else { throw XCTSkip("GFX_OUT not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return URL(fileURLWithPath: d)
    }

    private func setup(_ s: GfxLabScene, _ name: String) -> Float {
        switch name {
        case "roaming": s.clearTray(); s.place(SIMD2(0.7, 0.4)); return 0
        case "dining": s.place(SIMD2(0.7, 0.4)); s.spawnTray(); return 0
        case "throw": s.clearTray(); s.shift(SIMD3(0.6, 1.7, -0.5)); return 0
        case "focus": s.clearTray(); s.place(GameCamera.callSpot); return 1
        default: return 0
        }
    }

    /// Scenario order matters (throw shifts the particles; it runs last and is undone by nothing).
    private let scenarios = ["roaming", "dining", "focus", "throw"]

    func testCaptureStills() throws {
        let out = try outDir()
        var lines: [String] = []
        for (W, H, tag) in [(1206, 2622, "3x"), (804, 1748, "2x")] {
            let s = try XCTUnwrap(GfxLabScene(width: W, height: H))
            for name in scenarios {
                let focus = setup(s, name)
                let old = s.render(focus: focus, cache: false)
                let new = s.render(focus: focus, cache: true, frames: 6)
                old.png(to: out.appendingPathComponent("\(name)_\(tag)_old.png"))
                new.png(to: out.appendingPathComponent("\(name)_\(tag)_new.png"))
                let d = GfxDiff(old, new)
                lines.append("\(tag) \(name): action \(s.ren.lastCacheAction) footprint \(String(format: "%.1f%%", s.ren.lastFootprintShare * 100)); \(d.summary)")
            }
        }
        try lines.joined(separator: "\n").write(to: out.appendingPathComponent("identity.txt"), atomically: true, encoding: .utf8)
        print("GFXCAP\n" + lines.joined(separator: "\n"))
    }

    func testPassTimings() throws {
        let out = try outDir()
        UserDefaults.standard.set(true, forKey: "PerfPasses")
        defer { UserDefaults.standard.removeObject(forKey: "PerfPasses") }
        let env = ProcessInfo.processInfo.environment
        let W = Int(env["GFX_W"] ?? "") ?? 1206, H = Int(env["GFX_H"] ?? "") ?? 2622
        let s = try XCTUnwrap(GfxLabScene(width: W, height: H))
        XCTAssertTrue(s.ren.perfPasses)
        var lines: [String] = []
        for name in scenarios {
            let focus = setup(s, name)
            for cache in [false, true, false, true, false, true] {
                s.ren.invalidateRoomCache()
                s.render(focus: focus, cache: cache, frames: 8)          // warm up (and build the cache)
                _ = s.ren.takePassStats(); _ = s.ren.takeGPUStats()
                s.ren.resetRoomCacheCounters()
                let t0 = CACurrentMediaTime()
                s.render(focus: focus, cache: cache, frames: 90)
                let wall = (CACurrentMediaTime() - t0) / 90 * 1000
                let g = s.ren.takeGPUStats()
                let passes = s.ren.takePassStats()
                let shaded = s.ren.roomPixelsBaseline > 0 ? s.ren.roomPixelsShaded / s.ren.roomPixelsBaseline : 1
                lines.append(String(format: "%@ %@ cache=%@: gpu total %.2f ms (%d frames, wall %.2f ms/frame) | %@ | room px shaded %.0f%% of %d (footprint %.0f%%, %@)",
                                    "\(W)x\(H)", name, cache ? "on " : "off", g.avgMs, g.frames, wall, passes, shaded * 100, W * H,
                                    s.ren.lastFootprintShare * 100, "\(s.ren.lastCacheAction)"))
            }
        }
        try lines.joined(separator: "\n").write(to: out.appendingPathComponent("timings_\(env["GFX_TAG"] ?? "run").txt"), atomically: true, encoding: .utf8)
        print("GFXTIME\n" + lines.joined(separator: "\n"))
    }

    func testIdleEnergy() throws {
        let out = try outDir()
        let r = MotionRig(game: true)
        var samples: [Float] = []
        for _ in 0..<(60 * 12) { r.tick(); samples.append(r.sim.kineticEnergy() / r.sim.totalMass) }
        func stat(_ a: ArraySlice<Float>) -> String {
            let m = a.reduce(0, +) / Float(a.count)
            return String(format: "mean %.6f max %.6f", m, a.max() ?? 0)
        }
        let line = "idle KE/mass: first 2 s \(stat(samples[0..<120])); 2-12 s \(stat(samples[120...])); calmEnergy \(IdleRestGovernor.calmEnergy)"
        try line.write(to: out.appendingPathComponent("idle_energy.txt"), atomically: true, encoding: .utf8)
        print("GFXIDLE \(line)")
    }
}
