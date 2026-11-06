//
//  NecklaceTiltCaptureTests.swift
//  Not a regression test: renders necklace pieces on the real renderer, BEFORE (WearLevel.tiltOn = false: the old level loop) and AFTER (the tilted loop), when
//  NECK_CAP_DIR is set (TEST_RUNNER_NECK_CAP_DIR). Built on FeatureCaptureTests' rig (see PandaCaptureTests.pandaStill). Writes one sheet per group plus one combined sheet.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func neckDir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["NECK_CAP_DIR"], !d.isEmpty else { throw XCTSkip("NECK_CAP_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    /// One still: character `id` in `outfit`; `walkFrames` > 0 sends him walking first (an arm is swinging at the shot); `room` = the game's own room camera (looking down from behind and above)
    /// cropped round him, otherwise an orbit camera at `yaw` off his facing.
    func neckStill(id: Int, outfit: Outfit, yaw: Float, walkFrames: Int = 0, room: Bool = false, size: Int = 330) throws -> UIImage {
        W = room ? 603 : size * 2; H = room ? 1311 : size * 2
        let c = Char(id: id, outfit: outfit)
        let lab = setUpLab([SIMD2(0.4, 0.6)], chars: [c], seed: 3)
        let r = lab.rigs[0]
        r.brain.autonomy = false; r.brain.expr.enabled = false
        let (ren, target) = try renderer(lab)
        ren.matteSpec = true
        let d = dress(lab, [c])
        func step() { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(d, 0, r, c) }
        for _ in 0..<70 { step() }
        if walkFrames > 0 {
            let p = r.sim.bodyPose(iterations: 3).centroid
            r.brain.script = .walk(target: SIMD2(p.x - 3, p.z + 0.2), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0
            for _ in 0..<walkFrames { step() }
        }
        let pose = r.sim.bodyPose(iterations: 3)
        let cc = pose.centroid
        if room {
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            let img = composite(lab, d, [c], ren, target, cam: cam)
            let k = cam.viewProj * SIMD4<Float>(cc.x, cc.y + 0.35, cc.z, 1)
            let px = SIMD2((k.x / k.w * 0.5 + 0.5) * Float(W), (1 - (k.y / k.w * 0.5 + 0.5)) * Float(H))
            let half: CGFloat = 95
            let rect = CGRect(x: CGFloat(px.x) - half, y: CGFloat(px.y) - half, width: half * 2, height: half * 2).intersection(CGRect(x: 0, y: 0, width: W, height: H))
            guard let cg = img.cgImage(), let part = cg.cropping(to: rect) else { throw XCTSkip("crop") }
            let small = UIImage(cgImage: part)
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 380, height: 380), format: fmt).image { _ in small.draw(in: CGRect(x: 0, y: 0, width: 380, height: 380)) }
        }
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_length(fwd) > 0.3 ? simd_normalize(fwd) : SIMD3(0, 0, 1)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let cam = Self.lookCamera(target: SIMD3(cc.x, cc.y + 0.45, cc.z), dir: dir, dist: 3.0, aspect: 1, lift: 0.22)
        return composite(lab, d, [c], ren, target, cam: cam).uiImage()!
    }

    /// Rows of (character, necklace, view), each rendered level (before) and tilted (after); a sheet of before | after pairs.
    func testNecklaceTiltSheet() throws {
        let d = try neckDir(); DayClock.shared.forcedHour = 12
        struct Row { var id: Int; var look: WearLook; var view: String; var yaw: Float; var walk = 0; var room = false }
        let panda = 6, teddy = 4, pip = 1, lav = 3
        var rows: [Row] = []
        for (id, look) in [(panda, WearLook.diamondJ), (teddy, .diamondJ), (pip, .chainGold)] {
            rows += [Row(id: id, look: look, view: "front", yaw: 0), Row(id: id, look: look, view: "3/4", yaw: 0.75), Row(id: id, look: look, view: "side", yaw: .pi / 2), Row(id: id, look: look, view: "walk", yaw: 0.75, walk: 45)]
        }
        rows += [Row(id: panda, look: .diamondJ, view: "room cam, walking", yaw: 0, walk: 45, room: true),
                 Row(id: panda, look: .diamondJ, view: "3/4 back", yaw: 2.4), Row(id: lav, look: .diamondJ, view: "front", yaw: 0), Row(id: lav, look: .diamondJ, view: "3/4 back", yaw: 2.4),
                 Row(id: pip, look: .chainGold, view: "3/4 back", yaw: 2.4), Row(id: panda, look: .diamondJ, view: "back", yaw: .pi), Row(id: lav, look: .pearls, view: "3/4 back", yaw: 2.4)]
        let only = ProcessInfo.processInfo.environment["NECK_CAP_ROWS"]?.split(separator: ",").compactMap { Int($0) }
        var cells: [UIImage] = []
        var k = 0
        for row in rows {
            k += 1
            if let only, !only.contains(k - 1) { continue }
            var pair: [UIImage] = []
            for tilt in [false, true] {
                WearLevel.tiltOn = tilt; WearMeshes.clearCache()
                let im = try neckStill(id: row.id, outfit: [.neck: row.look], yaw: row.yaw, walkFrames: row.walk, room: row.room)
                pair.append(tlabel(im, ["\(JellyRoster.baseNames[row.id]) \(row.look.rawValue) \(row.view): \(tilt ? "AFTER" : "BEFORE")"], bar: 26))
            }
            WearLevel.tiltOn = true; WearMeshes.clearCache()
            cells += pair
            SocialTests.keep.removeAll()
        }
        WearLevel.tiltOn = true; WearMeshes.clearCache()
        try writePNG(tgrid(cells, cols: 4), d + "/necklace_tilt_sheet.png", maxBytes: 12_000_000)
        for (i, n) in [("a_panda_teddy_pip", 0..<24), ("b_extra", min(24, cells.count)..<cells.count)] where n.lowerBound < n.upperBound {
            try writePNG(tgrid(Array(cells[n.lowerBound..<min(n.upperBound, cells.count)]), cols: 4), d + "/sheet_\(i).png", maxBytes: 12_000_000)
        }
    }
}
