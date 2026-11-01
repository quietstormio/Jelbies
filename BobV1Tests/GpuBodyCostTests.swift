//
//  GpuBodyCostTests.swift
//  Body-pass accounting (g-gpu-body): GPU time of ONE command buffer (gpuEndTime - gpuStartTime) at the phone's native / 2x / 1.33x sizes with
//  3 Jelbies (Bob / Pearl / Teddy), parts left out by difference (Renderer.bodyProbe), per-Jelbie cost, pixel coverage, and the pixel diff of every
//  body-shader variant against the locked one. Prints "GPUBODY ..." lines and writes scratchpad/gpubody/*.txt. Meaningful only on a real GPU
//  (run on the Mac destination: the simulator's timestamps are not usable).
//

import XCTest
import Metal
import simd
import QuartzCore
@testable import BobV1

@MainActor
final class GpuBodyCostTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    /// The app runs sandboxed on the Mac (Designed for iPad): files go to its tmp and are copied out by hand; the log lines are the record.
    static let outDir: String = { let d = NSTemporaryDirectory() + "gpubody"; try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true); return d }()
    typealias Scene = GpuOptPerfTests.Scene

    /// Bob (blue, belly), Pearl (white wings), Teddy -- the user's trio.
    func trio(W: Int, H: Int) throws -> Scene {
        let s = try XCTUnwrap(Scene(n: 3, W: W, H: H))
        Self.keep.append(s)
        s.ren.setPalette(PaletteKey.blue.palette, body: 0)
        s.ren.setPalette(WhiteWing.palette, body: 1)
        s.ren.setPalette(JellyRoster.palette(JellyRoster.teddyID) ?? PaletteKey.blue.palette, body: 2)
        s.ren.roomCacheEnabled = true
        s.ren.invalidateRoomCache()
        for _ in 0..<10 { s.frame() }
        return s
    }

    /// Median GPU ms of one command buffer over `frames` frames.
    func gpuMs(_ s: Scene, frames: Int = 25) -> Double {
        for _ in 0..<3 { s.frame() }
        var v: [Double] = []
        for _ in 0..<frames {
            s.frame(wait: false)
            let c = s.lastCmd!; c.waitUntilCompleted()
            v.append((c.gpuEndTime - c.gpuStartTime) * 1000)
        }
        v.sort()
        return v[v.count / 2]
    }

    /// Interleaved medians over `rounds` for several configurations (cancels clock drift / other processes).
    func compare(_ s: Scene, _ cfgs: [(String, () -> Void)], rounds: Int = 5) -> [String: Double] {
        var acc: [String: [Double]] = [:]
        for _ in 0..<rounds { for (name, set) in cfgs { set(); acc[name, default: []].append(gpuMs(s, frames: 15)) } }
        return acc.mapValues { let a = $0.sorted(); return a[a.count / 2] }
    }

    func testAccounting() throws {
        UserDefaults.standard.removeObject(forKey: "PerfPasses")
        var out: [String] = []
        func row(_ l: String) { out.append(l); print("GPUBODY " + l); NSLog("GPUBODY %@", l) }
        for (W, H, tag) in [(1206, 2622, "3x"), (880, 1912, "2x"), (585, 1271, "1.33x")] {
            let s = try trio(W: W, H: H)
            let ren = s.ren
            func probe(_ p: MelonRenderer.BodyProbe) { ren.bodyProbe = p }
            func hide(_ i: Int?) { for k in 0..<3 { ren.setHidden(k == i, body: k) } }
            hide(nil)
            let r = compare(s, [
                ("full", { probe([]); hide(nil) }),
                ("noBody", { probe(.skipBody); hide(nil) }),
                ("noEyes", { probe(.skipEyes); hide(nil) }),
                ("noBlended", { probe(.skipBlended); hide(nil) }),
                ("roomOnly", { probe([.skipBody, .skipEyes, .skipBlended]); hide(nil) }),
                ("nothing", { probe([.skipBody, .skipEyes, .skipBlended, .skipRoom]); hide(nil) }),
                ("bodyOnly", { probe([.skipEyes, .skipBlended]); hide(nil) }),
                ("bodyOnly-hide0", { probe([.skipEyes, .skipBlended]); hide(0) }),
                ("bodyOnly-hide1", { probe([.skipEyes, .skipBlended]); hide(1) }),
                ("bodyOnly-hide2", { probe([.skipEyes, .skipBlended]); hide(2) }),
            ])
            probe([]); hide(nil)
            func g(_ k: String) -> Double { r[k] ?? 0 }
            row(String(format: "%@ %dx%d frame %.2f ms | body draws %.2f | eyes %.2f | blended room pieces %.2f | rest-of-pass (room reshade, clears, resolve) %.2f | empty pass %.2f",
                       tag, W, H, g("full"), g("full") - g("noBody"), g("full") - g("noEyes"), g("full") - g("noBlended"), g("roomOnly"), g("nothing")))
            row(String(format: "%@ per Jelbie body draw: Bob %.2f  Pearl %.2f  Teddy %.2f (bodyOnly %.2f)", tag,
                       g("bodyOnly") - g("bodyOnly-hide0"), g("bodyOnly") - g("bodyOnly-hide1"), g("bodyOnly") - g("bodyOnly-hide2"), g("bodyOnly") - g("roomOnly")))
            // coverage: pixels the bodies change vs a frame without them
            probe([]); s.frame(advance: false); let withB = s.image()
            probe(.skipBody); s.frame(advance: false); let noB = s.image()
            probe([])
            var cov = 0
            for p in 0..<(W * H) { if withB.bgra[4*p] != noB.bgra[4*p] || withB.bgra[4*p+1] != noB.bgra[4*p+1] || withB.bgra[4*p+2] != noB.bgra[4*p+2] { cov += 1 } }
            row(String(format: "%@ body coverage %.1f%% of the frame (%d px, shaded once each by tile-deferred HSR; 3 bodies, 4x MSAA edges)", tag, Double(cov) / Double(W * H) * 100, cov))
            if tag == "3x" { withB.png(to: URL(fileURLWithPath: Self.outDir + "/frame_3x_trio.png")) }
        }
        try out.joined(separator: "\n").write(toFile: Self.outDir + "/accounting.txt", atomically: true, encoding: .utf8)
    }

    /// Mean / max absolute difference (0...255 levels) over the pixels the bodies cover, between two frames.
    func bodyDiff(_ a: LockImage, _ b: LockImage, mask m: LockImage, background bg: LockImage) -> (mean: Double, max: Int, over4: Int, n: Int) {
        var sum = 0, mx = 0, n = 0, o4 = 0
        for p in 0..<(a.w * a.h) {
            if m.bgra[4*p] == bg.bgra[4*p] && m.bgra[4*p+1] == bg.bgra[4*p+1] && m.bgra[4*p+2] == bg.bgra[4*p+2] { continue }
            n += 1
            var d = 0
            for c in 0..<3 { d = max(d, abs(Int(a.bgra[4*p+c]) - Int(b.bgra[4*p+c]))) }
            sum += d; mx = max(mx, d); if d > 4 { o4 += 1 }
        }
        return (n > 0 ? Double(sum) / Double(n) : 0, mx, o4, n)
    }

    /// Cost of the body draws for each shader variant (interleaved), plus the pixel diff of each against the locked shader.
    func testShaderCost() throws {
        UserDefaults.standard.removeObject(forKey: "PerfPasses")
        var out: [String] = []
        func row(_ l: String) { out.append(l); print("GPUBODY " + l); NSLog("GPUBODY %@", l) }
        for (W, H, tag) in [(2412, 5244, "6x"), (1206, 2622, "3x"), (880, 1912, "2x"), (585, 1271, "1.33x")] {
            let s = try trio(W: W, H: H)
            let ren = s.ren
            var variants: [(String, () -> Void)] = []
            func add(_ name: String, spec: Bool = true, tier: Int = 0, probe: Int = 0) {
                variants.append((name, { ren.bodyProbe = [.skipEyes, .skipBlended]; ren.matteSpec = spec; ren.matteProbe = probe
                    var o = ren.gfxOpt; o.fastMatteTier = tier; ren.gfxOpt = o }))
            }
            add("locked", spec: false); add("spec0")
            variants.append(("spec0-allblocks", { ren.bodyProbe = [.skipEyes, .skipBlended]; ren.matteSpec = true; ren.matteProbe = 0; ren.matteForceAllBlocks = true
                var o = ren.gfxOpt; o.fastMatteTier = 0; ren.gfxOpt = o }))
            for v in variants.indices { let f = variants[v].1; let nm = variants[v].0; if nm != "spec0-allblocks" { variants[v].1 = { ren.matteForceAllBlocks = false; f() } } }
             add("tier1", tier: 1); add("tier2", tier: 2); add("tier3", tier: 3)
            add("probe1-flat", probe: 1); add("probe2-nofibre", probe: 2); add("probe3-nobump", probe: 3); add("probe4-nocolnoise", probe: 4)
            variants.append(("roomOnly", { ren.bodyProbe = [.skipBody, .skipEyes, .skipBlended]; ren.matteSpec = true; ren.matteProbe = 0
                var o = ren.gfxOpt; o.fastMatteTier = 0; ren.gfxOpt = o }))
            let r = compare(s, variants, rounds: 5)
            let base = r["roomOnly"] ?? 0
            row(tag + " body-draw ms by variant (bodyOnly minus roomOnly " + String(format: "%.2f", base) + "): " + variants.dropLast().map { String(format: "%@ %.2f", $0.0, (r[$0.0] ?? 0) - base) }.joined(separator: " | "))
            // pixel diffs vs the locked shader
            ren.bodyProbe = []; ren.matteProbe = 0; ren.matteSpec = false
            var o = ren.gfxOpt; o.fastMatteTier = 0; ren.gfxOpt = o
            s.frame(advance: false); let locked = s.image()
            ren.bodyProbe = .skipBody; s.frame(advance: false); let bg = s.image()
            ren.bodyProbe = []
            var diffs: [String] = []
            for (name, spec, tier) in [("spec0", true, 0), ("tier1", true, 1), ("tier2", true, 2), ("tier3", true, 3)] {
                ren.matteSpec = spec; var o2 = ren.gfxOpt; o2.fastMatteTier = tier; ren.gfxOpt = o2
                s.frame(advance: false); let img = s.image()
                let d = bodyDiff(locked, img, mask: locked, background: bg)
                diffs.append(String(format: "%@ mean %.4f max %d (>4: %d of %d body px)", name, d.mean, d.max, d.over4, d.n))
                if tag == "3x" { img.png(to: URL(fileURLWithPath: Self.outDir + "/trio_3x_\(name).png")) }
            }
            if tag == "3x" { locked.png(to: URL(fileURLWithPath: Self.outDir + "/trio_3x_locked.png")) }
            row(tag + " pixel diff vs locked (levels/255): " + diffs.joined(separator: " | "))
            ren.matteSpec = true; var o3 = ren.gfxOpt; o3.fastMatteTier = 0; ren.gfxOpt = o3
        }
        try out.joined(separator: "\n").write(toFile: Self.outDir + "/shadercost.txt", atomically: true, encoding: .utf8)
    }
}
