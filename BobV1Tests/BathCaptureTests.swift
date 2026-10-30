//
//  BathCaptureTests.swift
//  Not a regression test: renders the Bath frames offscreen at the true phone aspect and composes a labelled contact sheet.
//  Output: /private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/bath/render/
//  (override with TEST_RUNNER_BATH_OUT). Frames: a room lint, b roller mid-peel, c half foam + soap, d full foam, e wet + spray,
//  f shine cloth, g sparkle 1 in the bath, h sparkle 0.3 in the room (+ a wider bath angle to check the room holds up).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class BathCaptureTests: XCTestCase {
    static let outPath = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/bath/render"

    private func outDir() throws -> URL {
        let d = ProcessInfo.processInfo.environment["BATH_OUT"] ?? Self.outPath
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return URL(fileURLWithPath: d)
    }

    /// Renders one frame of `s` with `look` and a camera.
    static func render(_ s: GfxLabScene, look: BathLook, camera: CameraState, time: Float = 3.7, frames: Int = 2, palette key: PaletteKey = .blue) -> LockImage {
        s.ren.bathLook = look
        s.ren.roomCacheEnabled = false
        let light = GameCamera.light(centroid: s.rig.sim.centroid())
        for _ in 0..<frames {
            s.ren.beginFrame()
            s.rig.skinner.update(x: s.rig.sim.x, index: MotionRig.renderMesh.index, into: s.ren.dynPointer)
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0; fp.time = time
            let pal = key.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            s.ren.setUniforms(camera: camera, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(s.W), Float(s.H)))
            let cmd = s.ren.queue.makeCommandBuffer()!
            s.ren.draw(to: s.target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
        }
        var px = [UInt8](repeating: 0, count: s.W * s.H * 4)
        px.withUnsafeMutableBytes { s.target.getBytes($0.baseAddress!, bytesPerRow: s.W * 4, from: MTLRegionMake2D(0, 0, s.W, s.H), mipmapLevel: 0) }
        return LockImage(w: s.W, h: s.H, bgra: px)
    }

    static func bathCam(_ s: GfxLabScene) -> CameraState { BathSet.closeUpCamera(aspect: Float(s.W) / Float(s.H)) }
    static func roomCam(_ s: GfxLabScene, focus: Float = 0) -> CameraState { GameCamera.camera(aspect: Float(s.W) / Float(s.H), focus: focus) }

    /// World point on Bob's current surface in rest direction `dir` (body-local), for placing the tool.
    static func surface(_ s: GfxLabScene, dir: SIMD3<Float>) -> SIMD3<Float> {
        let r = s.ren.lintPoint(dir: dir)
        return r ?? .zero
    }

    func testCaptureBathFrames() throws {
        let out = try outDir()
        let s = try XCTUnwrap(GfxLabScene(width: 603, height: 1311))
        s.clearTray()
        s.place(SIMD2(BathSet.standPoint.x, BathSet.standPoint.z))
        var panels: [(String, LockImage)] = []
        func add(_ name: String, _ label: String, _ img: LockImage) {
            img.png(to: out.appendingPathComponent("\(name).png"))
            panels.append((label, img))
        }

        // (a) room camera, lint bits incl. a leaf on his head and a Jelly Drop
        do {
            s.place(SIMD2(0.4, 0.6))
            var l = BathLook()
            l.lint = [
                LintBit(kind: .leaf, dir: SIMD3(0.05, 1, 0.1), spin: 0.6, size: 0.12),
                LintBit(kind: .drop, dir: SIMD3(-1, -0.15, 0.25), spin: 0, size: 0.12),
                LintBit(kind: .dust, dir: SIMD3(1, 0.25, 0.2), spin: 1.1, size: 0.11),
                LintBit(kind: .crumb, dir: SIMD3(-0.85, 0.55, -0.1), spin: 2.0, size: 0.1),
                LintBit(kind: .fuzz, dir: SIMD3(0.7, -0.55, 0.35), spin: 0.3, size: 0.11),
                LintBit(kind: .glitter, dir: SIMD3(0.35, 0.8, -0.4), spin: 0.9, size: 0.12),
            ]
            add("a_room_lint", "a  room: lint (leaf on head, drop)", Self.render(s, look: l, camera: Self.roomCam(s)))
            add("a2_room_lint_closeup", "a2 room close-up", Self.render(s, look: l, camera: Self.roomCam(s, focus: 1)))
            s.place(SIMD2(BathSet.standPoint.x, BathSet.standPoint.z))
        }
        let cam = Self.bathCam(s)
        _ = Self.render(s, look: BathLook(), camera: cam)    // refresh the skinned surface at the stand point

        // (b) bath, roller mid-peel
        do {
            var l = BathLook(); l.visible = true
            l.lint = [
                LintBit(kind: .dust, dir: SIMD3(1, 0.3, 0.3), spin: 0.4, size: 0.12, peel: 0.5),
                LintBit(kind: .leaf, dir: SIMD3(-0.3, 1, 0.1), spin: 1.2, size: 0.12),
                LintBit(kind: .drop, dir: SIMD3(-1, -0.2, 0.3), spin: 0, size: 0.12),
                LintBit(kind: .crumb, dir: SIMD3(0.8, 0.7, -0.3), spin: 0.2, size: 0.1),
            ]
            l.tool = .roller
            let p = Self.surface(s, dir: SIMD3(1, 0.3, 0.3))
            l.toolAt = p + SIMD3(0.14, 0.12, 0.28)
            add("b_roller", "b  bath: roller, bit at peel 0.5", Self.render(s, look: l, camera: cam))
        }

        // (c) half foam with the soap bar
        do {
            var l = BathLook(); l.visible = true
            l.paint(local: SIMD3(1, 0.2, 0.2), radius: 1.1, amount: 1)
            l.paint(local: SIMD3(0.7, -0.4, 0.7), radius: 0.7, amount: 1)
            l.paint(local: SIMD3(0.4, 0.9, 0.2), radius: 0.5, amount: 0.9)
            l.tool = .soap
            let p = Self.surface(s, dir: SIMD3(-0.5, -0.3, 0.9))
            l.toolAt = p + SIMD3(-0.05, 0.06, 0.2)
            add("c_halffoam", "c  half foam + soap bar (cov \(String(format: "%.2f", l.coverage)))", Self.render(s, look: l, camera: cam))
        }

        // (d) full foam
        do {
            var l = BathLook(); l.visible = true
            l.foam = Array(repeating: 0.95, count: BathLook.rows * BathLook.cols)
            for k in 0..<BathLook.cols where k % 3 == 0 { l.foam[2 * BathLook.cols + k] = 0.45; l.foam[6 * BathLook.cols + k] = 0.6 }
            l.bubbles = [SIMD4(0.7, 1.7, 1.5, 0.09), SIMD4(-0.6, 1.9, 1.3, 0.07), SIMD4(0.2, 2.3, 1.6, 0.11), SIMD4(-0.9, 1.1, 1.9, 0.06), SIMD4(0.95, 1.2, 1.8, 0.08)]
            add("d_fullfoam", "d  full foam + bubbles", Self.render(s, look: l, camera: cam))
        }

        // (e) wet + spray
        do {
            var l = BathLook(); l.visible = true
            l.wet = 1
            l.foam = Array(repeating: 0, count: BathLook.rows * BathLook.cols)
            l.paint(local: SIMD3(-1, 0, 0.3), radius: 0.7, amount: 0.7)
            l.spray = BathSet.showerNozzle
            l.tool = .rinse
            add("e_wet_spray", "e  wet + spray (foam rinsing off)", Self.render(s, look: l, camera: cam))
        }

        // (f) shine mid-way with the cloth
        do {
            var l = BathLook(); l.visible = true
            l.wet = 0.3; l.sparkle = 0.5
            l.tool = .shine
            let p = Self.surface(s, dir: SIMD3(0.5, 0.2, 1))
            l.toolAt = p + SIMD3(0.03, 0.05, 0.13)
            add("f_shine", "f  shine: cloth, sparkle .5, wet .3", Self.render(s, look: l, camera: cam))
        }

        // (g) sparkle 1.0 in the bath, and a (h) 0.3 in the room
        do {
            var l = BathLook(); l.visible = true; l.sparkle = 1
            add("g_sparkle_bath", "g  sparkle 1.0 in the bath", Self.render(s, look: l, camera: cam, time: 5.2))
            add("g2_sparkle_bath_t2", "g2 same, other instant", Self.render(s, look: l, camera: cam, time: 6.0))
            var w = l
            w.sparkle = 1
            let wide = GameCamera.camera(aspect: Float(s.W) / Float(s.H), focus: 0)
            add("g3_bath_wide", "g3 bath seen from the game camera", Self.render(s, look: w, camera: wide, time: 5.2))
        }
        do {
            s.place(SIMD2(0.4, 0.6))
            var l = BathLook(); l.sparkle = 0.3
            add("h_sparkle_room", "h  sparkle 0.3 in the room", Self.render(s, look: l, camera: Self.roomCam(s), time: 4.4))
            add("h2_sparkle_room_close", "h2 sparkle 0.3 room close-up", Self.render(s, look: l, camera: Self.roomCam(s, focus: 1), time: 4.4))
            var l15 = BathLook(); l15.sparkle = 0.15
            add("h3_sparkle_room_015", "h3 sparkle 0.15 room close-up", Self.render(s, look: l15, camera: Self.roomCam(s, focus: 1), time: 4.4))
        }
        s.place(SIMD2(BathSet.standPoint.x, BathSet.standPoint.z))
        // other jelly colours against the grey room
        do {
            var l = BathLook(); l.visible = true
            l.paint(local: SIMD3(1, 0.2, 0.2), radius: 1.1, amount: 1)
            l.paint(local: SIMD3(0.7, -0.4, 0.7), radius: 0.7, amount: 1)
            l.sparkle = 0.6
            add("i_yellow", "i  butter-yellow Bob", Self.render(s, look: l, camera: cam, palette: .yellow))
            add("j_pink", "j  pink Bob", Self.render(s, look: l, camera: cam, palette: .pink))
            add("k_blush", "k  blush Bob, plain", Self.render(s, look: { var x = BathLook(); x.visible = true; return x }(), camera: cam, palette: .blush))
        }
        try Self.sheet(panels, to: out.appendingPathComponent("sheet.png"), columns: 4)
        print("BATHCAP wrote \(panels.count) frames to \(out.path)")
    }

    /// Contact sheet: every panel scaled uniformly (true proportions) with a label strip above it.
    static func sheet(_ panels: [(String, LockImage)], to url: URL, columns: Int, panelHeight: CGFloat = 760) throws {
        guard let first = panels.first else { return }
        let aspect = CGFloat(first.1.w) / CGFloat(first.1.h)
        let pw = panelHeight * aspect, strip: CGFloat = 34, gap: CGFloat = 10
        let rows = (panels.count + columns - 1) / columns
        let size = CGSize(width: CGFloat(columns) * (pw + gap) + gap, height: CGFloat(rows) * (panelHeight + strip + gap) + gap)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for (k, p) in panels.enumerated() {
                let x = gap + CGFloat(k % columns) * (pw + gap), y = gap + CGFloat(k / columns) * (panelHeight + strip + gap)
                (p.0 as NSString).draw(at: CGPoint(x: x + 4, y: y + 6), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white])
                if let ui = p.1.uiImage() { ui.draw(in: CGRect(x: x, y: y + strip, width: pw, height: panelHeight)) }
            }
        }
        try img.pngData()?.write(to: url)
    }
}
