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
    func neckStill(id: Int, outfit: Outfit, yaw: Float, walkFrames: Int = 0, room: Bool = false, size: Int = 330, heading: SIMD2<Float> = SIMD2(-3, 0.2), roomHalf: CGFloat = 95, scale: Int = 1, outSize: Int = 380, motion: String = "walk", dy: Float = 0.35, dist: Float = 3.0, lift: Float = 0.22, ty: Float = 0.45) throws -> UIImage {
        W = room ? 603 * scale : size * 2; H = room ? 1311 * scale : size * 2
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
            switch motion {
            case "hop": r.brain.idleForced = true; _ = r.brain.idleStart(.bounce, r.sim)
            case "jacks": r.brain.idleForced = true; _ = r.brain.idleStart(.jacks, r.sim)
            default:
                r.brain.hurry = motion == "run"
                r.brain.script = .walk(target: SIMD2(p.x + heading.x, p.z + heading.y), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0
            }
            for _ in 0..<walkFrames { step() }
        }
        let pose = r.sim.bodyPose(iterations: 3)
        let cc = pose.centroid
        if room {
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            let img = composite(lab, d, [c], ren, target, cam: cam)
            let k = cam.viewProj * SIMD4<Float>(cc.x, cc.y + dy, cc.z, 1)
            let px = SIMD2((k.x / k.w * 0.5 + 0.5) * Float(W), (1 - (k.y / k.w * 0.5 + 0.5)) * Float(H))
            let half = roomHalf * CGFloat(scale)
            let rect = CGRect(x: CGFloat(px.x) - half, y: CGFloat(px.y) - half, width: half * 2, height: half * 2).intersection(CGRect(x: 0, y: 0, width: W, height: H))
            guard let cg = img.cgImage(), let part = cg.cropping(to: rect) else { throw XCTSkip("crop") }
            let small = UIImage(cgImage: part)
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: outSize, height: outSize), format: fmt).image { _ in small.draw(in: CGRect(x: 0, y: 0, width: outSize, height: outSize)) }
        }
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_length(fwd) > 0.3 ? simd_normalize(fwd) : SIMD3(0, 0, 1)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let cam = Self.lookCamera(target: SIMD3(cc.x, cc.y + ty, cc.z), dir: dir, dist: dist, aspect: 1, lift: lift)
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

    /// Round 2: bd9be370's curve (WearLevel.useLegacyTilt) on the left, the current curve on the right. Rows include the room camera 3/4 front-left view (the phone's angle).
    func testNecklaceTilt2Sheet() throws {
        let d = try neckDir(); DayClock.shared.forcedHour = 12
        struct Row { var id: Int; var look: WearLook; var view: String; var yaw: Float; var walk = 0; var room = false; var heading = SIMD2<Float>(-3, 0.2) }
        let panda = 6, teddy = 4, pip = 1, lav = 3
        var rows: [Row] = []
        // the room camera, 3/4 front-left: rest, and walking toward the camera-left
        for id in [panda, teddy] {
            rows += [Row(id: id, look: .diamondJ, view: "room cam rest", yaw: 0, room: true, heading: SIMD2(-1.2, 2.2)),
                     Row(id: id, look: .diamondJ, view: "room cam walking A", yaw: 0, walk: 40, room: true, heading: SIMD2(-1.2, 2.2)),
                     Row(id: id, look: .diamondJ, view: "room cam walking B", yaw: 0, walk: 55, room: true, heading: SIMD2(1.2, 2.2))]
        }
        for (id, look) in [(panda, WearLook.diamondJ), (teddy, .diamondJ), (pip, .chainGold)] {
            rows += [Row(id: id, look: look, view: "front", yaw: 0), Row(id: id, look: look, view: "3/4", yaw: 0.75), Row(id: id, look: look, view: "side", yaw: .pi / 2), Row(id: id, look: look, view: "walk", yaw: 0.75, walk: 45)]
        }
        rows += [Row(id: panda, look: .diamondJ, view: "3/4 back", yaw: 2.4), Row(id: panda, look: .diamondJ, view: "back", yaw: .pi), Row(id: lav, look: .diamondJ, view: "3/4 back", yaw: 2.4),
                 Row(id: pip, look: .chainGold, view: "3/4 back", yaw: 2.4), Row(id: lav, look: .pearls, view: "3/4 back", yaw: 2.4), Row(id: teddy, look: .diamondJ, view: "3/4 back", yaw: 2.4)]
        let only = ProcessInfo.processInfo.environment["NECK_CAP_ROWS"]?.split(separator: ",").compactMap { Int($0) }
        let cur = (WearLevel.tiltSideY, WearLevel.tiltBackY, WearLevel.tiltFrom, WearLevel.tiltSideAt)
        func setCurrent() { (WearLevel.tiltSideY, WearLevel.tiltBackY, WearLevel.tiltFrom, WearLevel.tiltSideAt) = cur; WearMeshes.clearCache() }
        var cells: [UIImage] = []
        for (k, row) in rows.enumerated() {
            if let only, !only.contains(k) { continue }
            var pair: [UIImage] = []
            for after in [false, true] {
                if after { setCurrent() } else { WearLevel.useLegacyTilt(); WearMeshes.clearCache() }
                let im = try neckStill(id: row.id, outfit: [.neck: row.look], yaw: row.yaw, walkFrames: row.walk, room: row.room, heading: row.heading, roomHalf: 70)
                pair.append(tlabel(im, ["\(JellyRoster.baseNames[row.id]) \(row.look.rawValue) \(row.view): \(after ? "NEW" : "bd9be370")"], bar: 26))
            }
            setCurrent()
            cells += pair
            SocialTests.keep.removeAll()
        }
        setCurrent()
        try writePNG(tgrid(cells, cols: 4), d + "/necklace_tilt2_sheet.png", maxBytes: 14_000_000)
        let split = min(12, cells.count)
        try writePNG(tgrid(Array(cells[0..<split]), cols: 4), d + "/tilt2_a_room.png", maxBytes: 14_000_000)
        if cells.count > split { try writePNG(tgrid(Array(cells[split...]), cols: 4), d + "/tilt2_b_rest.png", maxBytes: 14_000_000) }
    }

    /// Round 2 (chain / arm clearance): BEFORE = bd9be370's curve (WearLevel.useLegacyTilt), AFTER = the current constants. Room camera, 3/4 front-left; rest / walk / run / hop / jacks.
    /// NECK_CAP_ZOOM=1 renders 3x and crops to the chain / arm seam (the character is > 400 px tall). NECK_CAP_FRAMES = walk frames list.
    func testNecklaceR2Sheet() throws {
        let d = try neckDir(); DayClock.shared.forcedHour = 12
        let env = ProcessInfo.processInfo.environment
        let zoom = env["NECK_CAP_ZOOM"] == "1"
        let walkF = env["NECK_CAP_WALKF"].flatMap { Int($0) } ?? 40
        let cur = (WearLevel.tiltSideY, WearLevel.tiltBackY, WearLevel.tiltFrom, WearLevel.tiltSideAt)
        func setCurrent() { (WearLevel.tiltSideY, WearLevel.tiltBackY, WearLevel.tiltFrom, WearLevel.tiltSideAt) = cur; WearMeshes.clearCache() }
        defer { setCurrent() }
        let combos: [(Int, WearLook)] = [(6, .diamondJ), (4, .diamondJ), (4, .chainGold)]
        // (pose name, walk frames, motion, heading) - the walk goes toward the camera-left like the user's screenshot
        let poses: [(String, Int, String, SIMD2<Float>)] = [("rest", 0, "walk", SIMD2(-1.2, 2.2)), ("walk", walkF, "walk", SIMD2(-1.2, 2.2)), ("run", 40, "run", SIMD2(-1.2, 2.2)), ("hop", 85, "hop", SIMD2(-1.2, 2.2)), ("jacks", 45, "jacks", SIMD2(-1.2, 2.2))]
        let only = env["NECK_CAP_ROWS"]?.split(separator: ",").compactMap { Int($0) }
        var cells: [UIImage] = []
        var k = 0
        for (id, look) in combos { for (pn, frames, motion, heading) in poses {
            defer { k += 1 }
            if let only, !only.contains(k) { continue }
            var pair: [UIImage] = []
            for after in [false, true] {
                if after { setCurrent() } else { WearLevel.useLegacyTilt(); WearMeshes.clearCache() }
                let yaw = Float(env["NECK_CAP_YAW"] ?? "") ?? 0.75
                let im = zoom ? try neckStill(id: id, outfit: [.neck: look], yaw: yaw, walkFrames: frames, size: 300, heading: heading, motion: motion, dist: Float(env["NECK_CAP_DIST"] ?? "") ?? 1.7, lift: Float(env["NECK_CAP_LIFT"] ?? "") ?? 0.4, ty: Float(env["NECK_CAP_TY"] ?? "") ?? 0.30)
                              : try neckStill(id: id, outfit: [.neck: look], yaw: yaw, walkFrames: frames, size: 190, heading: heading, motion: motion, dist: 2.4, lift: 0.4, ty: 0.35)
                let tag = "\(JellyRoster.baseNames[id]) \(look.rawValue) \(pn): \(after ? "AFTER" : "BEFORE")"
                try writePNG(im, d + "/frame_\(zoom ? "zoom_" : "")\(JellyRoster.baseNames[id])_\(look.rawValue)_\(pn)_\(after ? "after" : "before").png", maxBytes: 12_000_000)
                pair.append(tlabel(im, [tag], bar: 26))
            }
            setCurrent()
            cells += pair
            SocialTests.keep.removeAll()
        } }
        try writePNG(tgrid(cells, cols: 4), d + (zoom ? "/necklace_r2_zoom.png" : "/necklace_r2_sheet.png"), maxBytes: 14_000_000)
    }

    /// Straight front view of Panda at rest, before / after: the pendant must not have moved and the mouth is clear.
    func testNecklaceR2Front() throws {
        let d = try neckDir(); DayClock.shared.forcedHour = 12
        let cur = (WearLevel.tiltSideY, WearLevel.tiltBackY, WearLevel.tiltFrom, WearLevel.tiltSideAt)
        func setCurrent() { (WearLevel.tiltSideY, WearLevel.tiltBackY, WearLevel.tiltFrom, WearLevel.tiltSideAt) = cur; WearMeshes.clearCache() }
        defer { setCurrent() }
        var cells: [UIImage] = []
        for (id, look) in [(6, WearLook.diamondJ), (4, .diamondJ)] { for after in [false, true] {
            if after { setCurrent() } else { WearLevel.useLegacyTilt(); WearMeshes.clearCache() }
            let im = try neckStill(id: id, outfit: [.neck: look], yaw: 0, size: 420)
            try writePNG(im, d + "/frame_front_\(JellyRoster.baseNames[id])_\(look.rawValue)_\(after ? "after" : "before").png", maxBytes: 12_000_000)
            cells.append(tlabel(im, ["\(JellyRoster.baseNames[id]) \(look.rawValue) front: \(after ? "AFTER" : "BEFORE")"], bar: 26))
            SocialTests.keep.removeAll()
        } }
        try writePNG(tgrid(cells, cols: 2), d + "/necklace_r2_front.png", maxBytes: 14_000_000)
    }
}
