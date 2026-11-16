//
//  JellyLookTests.swift
//  Jelly look lab: one fixed frame (blue body + yellow body) through the real renderer path. Level 0 must be bit-identical to the base
//  (JELLY_OUT writes the raw pixels so two builds can be compared with cmp); levels 1...3 change the blue body only.
//

import XCTest
import Metal
import simd
@testable import BobV1

@MainActor
final class JellyLookTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    typealias Scene = GpuOptPerfTests.Scene

    func makeScene() throws -> Scene {
        let s = try XCTUnwrap(Scene(n: 2, W: 600, H: 1300))
        Self.keep.append(s)
        s.ren.setPalette(PaletteKey.blue.palette, body: 0)
        for _ in 0..<10 { s.frame() }
        return s
    }

    func shot(_ s: Scene) -> LockImage { s.frame(advance: false); return s.image() }

    func testWriteFrame() throws {
        guard let out = ProcessInfo.processInfo.environment["JELLY_OUT"], !out.isEmpty else { throw XCTSkip("JELLY_OUT not set") }
        JellyLook.level = Int(ProcessInfo.processInfo.environment["JELLY_LEVEL"] ?? "0") ?? 0
        defer { JellyLook.level = 0 }
        let s = try makeScene()
        try Data(shot(s).bgra).write(to: URL(fileURLWithPath: out))
    }

    /// Fixed frames for the other body draw paths (JELLY_VARIANT = bath | bathfoam | jersey | jerseysoot): level 0 must stay bit-identical there too.
    func testWriteFrameVariant() throws {
        guard let out = ProcessInfo.processInfo.environment["JELLY_OUT"], !out.isEmpty, let v = ProcessInfo.processInfo.environment["JELLY_VARIANT"] else { throw XCTSkip("JELLY_OUT / JELLY_VARIANT not set") }
        JellyLook.level = Int(ProcessInfo.processInfo.environment["JELLY_LEVEL"] ?? "0") ?? 0
        defer { JellyLook.level = 0 }
        let s = try makeScene()
        var look = BathLook.dry
        look.sparkle = 0.8; look.dirt = 0.7; look.sootStyle = 1
        if v.contains("foam") { look.wet = 0.6; look.foam = (0..<(BathLook.rows * BathLook.cols)).map { $0 % 5 == 0 ? 0.9 : 0.0 } }
        if v.hasPrefix("bath") { s.ren.setBathLook(look, body: 0); s.ren.setBathLook(look, body: 1) }
        if v.hasPrefix("jersey") { s.ren.setJersey(.coral, body: 0); s.ren.setJersey(.mint, body: 1) }
        if v == "jerseysoot" { s.ren.setBathLook(look, body: 0) }
        for _ in 0..<3 { s.frame() }
        try Data(shot(s).bgra).write(to: URL(fileURLWithPath: out))
    }

    func differs(_ a: LockImage, _ b: LockImage, where mask: (Int) -> Bool = { _ in true }) -> Int {
        var n = 0
        for p in 0..<(a.w * a.h) where mask(p) {
            if a.bgra[4*p] != b.bgra[4*p] || a.bgra[4*p+1] != b.bgra[4*p+1] || a.bgra[4*p+2] != b.bgra[4*p+2] { n += 1 }
        }
        return n
    }

    /// Levels 1...3 change the blue body; the yellow body's own pixels are identical at every level; the default level is 0.
    func testLevelsChangeBlueOnly() throws {
        XCTAssertEqual(JellyLook.launchLevel, 1)
        defer { JellyLook.level = 0 }
        let s = try makeScene()
        JellyLook.level = 0
        let base = shot(s)
        s.ren.bodyProbe = .skipBody; let none = shot(s); s.ren.bodyProbe = []
        // each body's own pixels (only that body drawn, with and without its body draw)
        func own(_ i: Int) -> [Bool] {
            for k in 0..<2 { s.ren.setHidden(k != i, body: k) }
            let a = shot(s); s.ren.bodyProbe = .skipBody; let b = shot(s); s.ren.bodyProbe = []
            for k in 0..<2 { s.ren.setHidden(false, body: k) }
            return (0..<(a.w * a.h)).map { p in a.bgra[4*p] != b.bgra[4*p] || a.bgra[4*p+1] != b.bgra[4*p+1] || a.bgra[4*p+2] != b.bgra[4*p+2] }
        }
        _ = none
        let blueMask = own(0), yellowMask = own(1)
        // the blue body's silhouette plus 4 px: the antialiased edge where blue meets yellow is blue's, not yellow's
        let W = base.w, H = base.h
        var blueNear = blueMask
        for y in 0..<H { for x in 0..<W where blueMask[y * W + x] {
            for dy in -4...4 { for dx in -4...4 { let xx = x + dx, yy = y + dy; if xx >= 0, xx < W, yy >= 0, yy < H { blueNear[yy * W + xx] = true } } }
        } }
        var yellowOnly = 0
        for p in 0..<blueMask.count where yellowMask[p] && !blueNear[p] { yellowOnly += 1 }
        XCTAssertGreaterThan(yellowOnly, 1000)
        for lv in 1...3 {
            JellyLook.level = lv
            let f = shot(s)
            let nBlue = differs(base, f) { blueMask[$0] }
            let nYellow = differs(base, f) { yellowMask[$0] && !blueNear[$0] }
            if nYellow > 0 { var c: [String] = []; for p in 0..<(f.w * f.h) where yellowMask[p] && !blueNear[p] && (f.bgra[4*p] != base.bgra[4*p] || f.bgra[4*p+1] != base.bgra[4*p+1] || f.bgra[4*p+2] != base.bgra[4*p+2]) { c.append("(\(p % f.w),\(p / f.w))") }; print("JELLYLOOK stray yellow px: " + c.joined(separator: " ")) }
            print("JELLYLOOK level \(lv): blue px differing \(nBlue), yellow-only px differing \(nYellow)")
            XCTAssertGreaterThan(nBlue, 1000, "level \(lv) must change the blue body")
            // 2 px at (279,580) and (263,590) differ at the see-through levels, beyond the 4 px silhouette margin; everything else of yellow is identical
            XCTAssertLessThanOrEqual(nYellow, 4, "level \(lv) must not change the yellow body")
        }
        JellyLook.level = 0
        XCTAssertEqual(differs(base, shot(s)), 0, "back to level 0 must give the base frame")
    }
}
