//
//  BathCaptureTests.swift
//  Not a regression test: renders the Bath frames offscreen at the true phone aspect and composes a labelled contact sheet.
//  Output: /private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/bath/render/
//  (override with BATH_OUT). Frames: the room at several dirt levels, room close-ups, the colours, soap over soot,
//  mid-rinse with a clean streak, and after the shine.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class BathCaptureTests: XCTestCase {
    static let outPath = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/6a40096b-092a-48d0-8cbe-4e00ccea7702/scratchpad/bath/soot"

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

    /// A camera orbiting Bob at `azimuth` (0 = the front, pi = the back, pi/2 = his right side), at the close-up distance.
    static func orbitCam(_ s: GfxLabScene, azimuth: Float) -> CameraState {
        let c = s.rig.sim.centroid()
        let target = SIMD3<Float>(c.x, 0.62, c.z)
        let aspect = Float(s.W) / Float(s.H)
        let dist = (1.7 / max(aspect, 0.2)) / (2 * tanf(GameCamera.fovY / 2))        // ~1.7 world units across, like the bath close-up
        let el: Float = 0.30
        let eye = target + SIMD3<Float>(sinf(azimuth) * cosf(el), sinf(el), cosf(azimuth) * cosf(el)) * dist
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: target, up: SIMD3(0, 1, 0))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.3, far: 60), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye
        cam.fwd = simd_normalize(target - eye)
        return cam
    }

    static func bathCam(_ s: GfxLabScene) -> CameraState { BathSet.closeUpCamera(aspect: Float(s.W) / Float(s.H)) }
    static func roomCam(_ s: GfxLabScene, focus: Float = 0) -> CameraState { GameCamera.camera(aspect: Float(s.W) / Float(s.H), focus: focus) }

    /// World point on Bob's current surface in rest direction `dir` (body-local), for placing the tool.
    static func surface(_ s: GfxLabScene, dir: SIMD3<Float>) -> SIMD3<Float> {
        let r = s.ren.surfacePoint(dir: dir)
        return r ?? .zero
    }

    /// A look with soot for a dirt level (what the flow writes in the room).
    static func sooty(_ dirt: Float, visible: Bool = false) -> BathLook {
        var l = BathLook(); l.visible = visible; l.dirt = dirt; l.soot = BathLook.sootSeed(dirt: dirt)
        return l
    }

    func testCaptureBathFrames() throws {
        let out = try outDir()
        let s = try XCTUnwrap(GfxLabScene(width: 603, height: 1311))
        s.clearTray()
        var panels: [(String, LockImage)] = []
        func add(_ name: String, _ label: String, _ img: LockImage) {
            img.png(to: out.appendingPathComponent("\(name).png"))
            panels.append((label, img))
        }
        let stand = SIMD2(BathSet.standPoint.x, BathSet.standPoint.z)

        // room: the dirt ladder, then the close-ups and the other colours
        s.place(SIMD2(0.4, 0.6))
        for d: Float in [0, 0.2, 0.5, 0.85] {
            add("a_room_\(Int(d * 100))", "room, dirt \(d)", Self.render(s, look: Self.sooty(d), camera: Self.roomCam(s)))
        }
        for d: Float in [0.5, 0.85] {
            add("b_close_\(Int(d * 100))", "room close-up, dirt \(d)", Self.render(s, look: Self.sooty(d), camera: Self.roomCam(s, focus: 1)))
        }
        add("d_back_85", "back view, dirt 0.85", Self.render(s, look: Self.sooty(0.85), camera: Self.orbitCam(s, azimuth: .pi)))
        add("d_side_85", "side view, dirt 0.85", Self.render(s, look: Self.sooty(0.85), camera: Self.orbitCam(s, azimuth: .pi / 2)))
        add("d_rear34_85", "rear 3/4, dirt 0.85", Self.render(s, look: Self.sooty(0.85), camera: Self.orbitCam(s, azimuth: 2.5)))
        add("c_blue_50", "blue Bob, dirt 0.5", Self.render(s, look: Self.sooty(0.5), camera: Self.roomCam(s, focus: 1), palette: .blue))
        add("c_yellow_50", "butter-yellow, dirt 0.5", Self.render(s, look: Self.sooty(0.5), camera: Self.roomCam(s, focus: 1), palette: .yellow))
        add("c_pink_50", "pink, dirt 0.5", Self.render(s, look: Self.sooty(0.5), camera: Self.roomCam(s, focus: 1), palette: .pink))
        add("c_blush_50", "blush, dirt 0.5", Self.render(s, look: Self.sooty(0.5), camera: Self.roomCam(s, focus: 1), palette: .blush))
        add("c_yellow_85", "butter-yellow, dirt 0.85", Self.render(s, look: Self.sooty(0.85), camera: Self.roomCam(s, focus: 1), palette: .yellow))

        for (k, t) in [Float(3.1), 4.4].enumerated() {
            add("c_filthy_puffs_\(k)", "filthy 0.95 + dust puffs (t \(t))", Self.render(s, look: Self.sooty(0.95), camera: Self.roomCam(s, focus: 1), time: t))
        }

        // bath
        s.place(stand)
        let cam = Self.bathCam(s)
        _ = Self.render(s, look: BathLook(), camera: cam)
        do {   // soap over the soot: grey suds on one side, the rest still sooty
            var l = Self.sooty(0.7, visible: true)
            l.paint(local: SIMD3(0.9, 0.1, 0.3), radius: 0.55, amount: 1)
            l.paint(local: SIMD3(0.5, -0.5, 0.6), radius: 0.45, amount: 1)
            l.tool = .soap
            l.toolAt = Self.surface(s, dir: SIMD3(0.2, -0.2, 1)) + SIMD3(0.0, 0.06, 0.2)
            add("d_soap_on_soot", "bath: soap over soot (grey suds)", Self.render(s, look: l, camera: cam))
            // all soaped
            var f = Self.sooty(0.7, visible: true)
            f.foam = Array(repeating: 0.95, count: BathLook.rows * BathLook.cols)
            f.tool = .soap
            add("d2_all_soaped", "bath: fully soaped, grey", Self.render(s, look: f, camera: cam))
            // mid-rinse: everything foamed, then a vertical stripe rinsed with the real rinse
            var r = f
            for k in 0..<40 {
                let y = -0.55 + 1.3 * Float(k) / 39
                r.rinse(local: SIMD3(-0.2, y, 0.62), radius: 0.18, amount: 3)
            }
            r.wet = 1; r.tool = .rinse; r.spray = BathSet.showerNozzle
            add("e_mid_rinse", "bath: mid-rinse, a clean streak", Self.render(s, look: r, camera: cam))
        }
        do {   // after the shine
            var l = BathLook(); l.visible = true; l.sparkle = 1
            add("f_after_shine", "bath: after the shine", Self.render(s, look: l, camera: cam, time: 5.2))
        }
        try Self.sheet(panels, to: out.appendingPathComponent("sheet.png"), columns: 4, panelHeight: 640)
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
