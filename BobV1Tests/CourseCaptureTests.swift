//
//  CourseCaptureTests.swift
//  Not a regression test: renders the four Jelly Circuit courses with the REAL track renderer from straight above when COURSE_CAP_DIR is set
//  (pass it as TEST_RUNNER_COURSE_CAP_DIR): courses_overview.png, one cell per course, the mini map of the picker beside each so the two can be
//  compared (same orientation: the start far / at the top, the finish near / at the bottom, as the race camera sees the track).
//

import XCTest
import Metal
import simd
import UIKit
import SwiftUI
@testable import BobV1

@MainActor
final class CourseCaptureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var dir: String? { ProcessInfo.processInfo.environment["COURSE_CAP_DIR"].flatMap { $0.isEmpty ? nil : $0 } }

    override func tearDown() { DayClock.shared.forcedHour = 12; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    /// The track of `course` from above: the camera over the middle of its bounds, high enough to hold the whole clay strip, -z (the start) up the screen.
    func topDown(_ ren: MelonRenderer, _ target: MTLTexture, rig: MotionRig, course: RaceCourse, w: Int, h: Int) -> LockImage {
        let bb = course.bounds(margin: RaceModels.trackHalfW + 3)
        let centre = SIMD2<Float>((bb.min.x + bb.max.x) / 2, (bb.min.y + bb.max.y) / 2)
        let size = bb.max - bb.min
        let aspect = Float(w) / Float(h), th = tanf(GameCamera.fovY / 2)
        let height = max(size.y / (2 * th), size.x / (2 * th * aspect)) * 1.04
        let eye = SIMD3<Float>(centre.x, height, centre.y + 0.001), at = SIMD3<Float>(centre.x, 0, centre.y)
        var cam = CameraState()
        cam.view = M4.lookAt(eye: eye, at: at, up: SIMD3(0, 0, -1))
        cam.viewProj = M4.mul(M4.perspective(fovy: GameCamera.fovY, aspect: aspect, near: 0.3, far: 400), cam.view)
        cam.invViewProj = M4.invert(cam.viewProj)
        cam.pos = eye; cam.fwd = simd_normalize(at - eye)
        ren.raceVisible = true; ren.raceCourse = course.tier
        ren.dayHourOverride = 12
        for _ in 0..<2 {
            ren.beginFrame()
            rig.skinner.update(x: rig.sim.x, index: MotionRig.renderMesh.index, into: ren.dynPointer)
            for v in 0..<MotionRig.renderMesh.vertexCount { ren.dynPointer[6 * v + 1] -= 60 }          // the body out of the picture
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = JellyRoster.palette(0) ?? PaletteKey.blue.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: GameCamera.light(centroids: [rig.sim.centroid()]), palette: pal, params: fp, viewSize: SIMD2<Float>(Float(w), Float(h)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
        }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
        return LockImage(w: w, h: h, bgra: px)
    }

    /// The picker's mini map of `course`, drawn as the card draws it, at `size`.
    func miniMap(_ course: RaceCourse, size: CGSize) -> UIImage {
        let pts = CourseMiniMap.points(course, in: size, margin: 18)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor(red: 0.98, green: 0.95, blue: 0.90, alpha: 1).setFill(); UIRectFill(CGRect(origin: .zero, size: size))
            let path = CourseMiniMap.path(pts).cgPath
            let g = ctx.cgContext
            g.setLineCap(.round); g.setLineJoin(.round)
            g.addPath(path); g.setLineWidth(size.width / 13); g.setStrokeColor(UIColor(red: 0.90, green: 0.66, blue: 0.56, alpha: 1).cgColor); g.strokePath()
            g.addPath(path); g.setLineWidth(1.5); g.setLineDash(phase: 0, lengths: [4, 4]); g.setStrokeColor(UIColor.white.cgColor); g.strokePath()
            g.setLineDash(phase: 0, lengths: [])
            if let s = pts.first { UIColor(red: 0.55, green: 0.85, blue: 0.70, alpha: 1).setFill(); g.fillEllipse(in: CGRect(x: s.x - 7, y: s.y - 7, width: 14, height: 14)) }
            if let f = pts.last {
                UIColor(white: 0.2, alpha: 1).setFill(); g.fill(CGRect(x: f.x - 1.5, y: f.y - 22, width: 3, height: 22))
                for i in 0..<3 { for j in 0..<2 { ((i + j) % 2 == 0 ? UIColor.black : UIColor.white).setFill(); g.fill(CGRect(x: f.x + 1.5 + CGFloat(i) * 5, y: f.y - 22 + CGFloat(j) * 5, width: 5, height: 5)) } }
            }
        }
    }

    func testCaptureCoursesOverview() throws {
        guard let dir else { throw XCTSkip("COURSE_CAP_DIR not set") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal") }
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        rig.renderSamples = false
        let W = 560, H = 760
        guard let ren = MelonRenderer(device: device, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: rig.sim.edges, particleCount: rig.sim.n, game: true), ren.room != nil else { throw XCTSkip("no renderer") }
        ren.resize(width: W, height: H)
        ren.roomCacheEnabled = false
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        let target = device.makeTexture(descriptor: td)!
        var cells: [(UIImage, String)] = []
        for t in CourseTier.allCases {
            let c = RaceCourse.course(t)
            let img = topDown(ren, target, rig: rig, course: c, w: W, h: H)
            let map = miniMap(c, size: CGSize(width: 184, height: 128))
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let cell = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { _ in
                img.uiImage()?.draw(at: .zero)
                map.draw(in: CGRect(x: W - 184 - 14, y: 14, width: 184, height: 128))
            }
            let turns = c.segments.filter(\.isTurn).count, bumps = c.segments.filter(\.isBump).count
            cells.append((cell, String(format: "%@ · %@ · %.1f u · %d turn%@, %d bump%@ · %.0f s", t.title, t.className, c.length, turns, turns == 1 ? "" : "s", bumps, bumps == 1 ? "" : "s", c.timeout)))
        }
        let cw = W, ch = H, bar = 34, head = 50, cols = 4
        let rows = (cells.count + cols - 1) / cols
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: cw * cols, height: head + rows * (ch + bar)), format: fmt).image { _ in
            UIColor(white: 0.08, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: cw * cols, height: head + rows * (ch + bar)))
            ("Jelly Circuit courses from above (start at the top, finish gantry at the bottom, as the race camera sees them); picker mini map inset top right" as NSString).draw(at: CGPoint(x: 12, y: 12), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24), .foregroundColor: UIColor.white])
            for (i, c) in cells.enumerated() {
                let x = (i % cols) * cw, y = head + (i / cols) * (ch + bar)
                (c.1 as NSString).draw(at: CGPoint(x: x + 10, y: y + 7), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.white])
                c.0.draw(in: CGRect(x: x, y: y + bar, width: cw, height: ch))
            }
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try sheet.pngData()?.write(to: URL(fileURLWithPath: dir + "/courses_overview.png"))
        ren.raceVisible = false
    }
}
