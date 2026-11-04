//
//  PandaCaptureTests.swift
//  Not a regression test: renders the Panda (character 6) and the Teddy / Pearl comparison shots with the REAL renderer when PANDA_DIR is set
//  (TEST_RUNNER_PANDA_DIR). Built on FeatureCaptureTests' rig (see TeddyCaptureTests).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    static let pandaID = JellyRoster.pandaID

    func pandaDir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["PANDA_DIR"], !d.isEmpty else { throw XCTSkip("PANDA_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    func pandaSave(_ img: UIImage, _ name: String) throws { try writePNG(img, try pandaDir() + "/" + name) }
    func pandaLabelled(_ s: TShot, _ text: String) -> UIImage { tlabel(s.img.uiImage()!, [text], bar: 26) }

    /// A still of one character on the real renderer with the brain ticking (so the body-mesh ears / pom are live: `teddyShot` never runs the brain, which leaves them collapsed).
    func pandaStill(id: Int, outfit: Outfit = [:], yaw: Float, size: Int = 600, dist: Float = 3.4, lookY: Float = 0.35, lift: Float = 0.1, warm: Int = 60,
                    start: ((MotionRig) -> Void)? = nil, more: Int = 0, specialised: Bool = true) throws -> TShot {
        W = size; H = size
        let c = Char(id: id, outfit: outfit)
        let lab = setUpLab([SIMD2(0.4, 0.6)], chars: [c], seed: 3)
        let r = lab.rigs[0]
        r.brain.autonomy = false; r.brain.expr.enabled = false
        let (ren, target) = try renderer(lab)
        ren.matteSpec = specialised          // (true = the specialised GfxBodyFast pipelines the game uses; false = Shaders.metal fsSoftMatte)
        let d = dress(lab, [c])
        for _ in 0..<warm { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(d, 0, r, c) }
        if let start { start(r); for _ in 0..<more { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(d, 0, r, c) } }
        let pose = r.sim.bodyPose(iterations: 3)
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_length(fwd) > 0.3 ? simd_normalize(fwd) : SIMD3(0, 0, 1)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let cc = pose.centroid
        let cam = Self.lookCamera(target: SIMD3(cc.x, cc.y + lookY, cc.z), dir: dir, dist: dist, aspect: 1, lift: lift)
        let img = composite(lab, d, [c], ren, target, cam: cam)
        return TShot(img: img, cam: cam, carry: d.feats[0].slot(0)?.carry ?? EyeMaskModel.Carry(), fit: d.feats[0].slot(0)?.fit ?? FeatureFit())
    }

    /// Fixed Teddy / Pearl shots, written raw: run before and after a Panda change and compare the bytes (they must not move).
    func testPandaZRefShots() throws {
        let d = try pandaDir() + "/" + (ProcessInfo.processInfo.environment["PANDA_REF"] ?? "ref")
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        DayClock.shared.forcedHour = 12
        for (name, id) in [("teddy", 4), ("pearl", 5)] {
            for (vn, yaw) in [("front", Float(0)), ("q34", 0.75), ("back", .pi)] {
                let s = try pandaStill(id: id, yaw: yaw, size: 480, dist: 3.9, lookY: 0.5, lift: 0.18)
                try s.img.uiImage()!.pngData()!.write(to: URL(fileURLWithPath: d + "/\(name)_\(vn).png"))
            }
        }
    }

    // MARK: the Panda boards

    func testPandaViews() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        var cells: [UIImage] = []
        let views: [(String, Float, Float, Float, Float)] = [("front", 0, 0.18, 3.9, 0.5), ("3-4 front", 0.75, 0.18, 3.9, 0.5), ("side", .pi / 2, 0.18, 3.9, 0.5),
                                                             ("back", .pi, 0.18, 3.9, 0.5), ("3-4 back", 2.4, 0.18, 3.9, 0.5), ("top-down", .pi * 0.9, 2.6, 3.8, 0.35)]
        for (name, yaw, lift, dist, lookY) in views {
            let s = try pandaStill(id: Self.pandaID, yaw: yaw, size: 600, dist: dist, lookY: lookY, lift: lift)
            let t = pandaLabelled(s, "Panda \(name)")
            cells.append(t)
            try pandaSave(t, "view_\(name.replacingOccurrences(of: " ", with: "_")).png")
        }
        try pandaSave(tgrid(cells, cols: 3), "views_sheet.png")
    }

    /// Close-ups of the face (patch vs eyes vs brows vs mouth), plus the numbers: the eye colour against the patch and the white.
    func testPandaFace() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        var cells: [UIImage] = []
        var notes = ""
        for (name, yaw) in [("face front", Float(0)), ("face 3-4", 0.6)] {
            let s = try pandaStill(id: Self.pandaID, yaw: yaw, size: 700, dist: 2.3, lookY: 0.3, lift: 0.04)
            cells.append(pandaLabelled(s, "Panda \(name)"))
            if yaw == 0 {
                let e = px(s, SIMD3(-0.215, 0.82, 0.62)), eye = darkest(s, e.0, e.1, r: 8)
                let pc = px(s, SIMD3(-0.265, 0.77, 0.58)), patch = medianRGB(s, pc.0, pc.1, r: 3)
                let fo = px(s, SIMD3(0, 1.05, 0.5)), fore = medianRGB(s, fo.0, fo.1)
                notes += "eye darkest \(hex(eye))  patch \(hex(patch))  forehead white \(hex(fore))  eye-vs-patch \(contrast(eye, patch))  patch-vs-white \(contrast(patch, fore))\n"
            }
        }
        try pandaSave(tgrid(cells, cols: 2), "face_sheet.png")
        try notes.write(toFile: try pandaDir() + "/face_numbers.txt", atomically: true, encoding: .utf8)
    }

    /// The same Panda through both matte shaders (GfxBodyFast = the game's, Shaders.metal = the fallback): they must agree.
    func testPandaBothShaders() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        var cells: [UIImage] = []
        for (name, spec) in [("GfxBodyFast (game)", true), ("Shaders.metal fsSoftMatte", false)] {
            for yaw in [Float(0.75), 2.4] {
                let s = try pandaStill(id: Self.pandaID, yaw: yaw, size: 480, dist: 3.9, lookY: 0.5, lift: 0.18, specialised: spec)
                cells.append(pandaLabelled(s, "\(name) \(yaw < 1 ? "3/4 front" : "3/4 back")"))
            }
        }
        try pandaSave(tgrid(cells, cols: 2), "both_shaders.png")
    }

    /// Teddy | Panda | Pearl in a row, each facing the game-like camera (three separate stills side by side: the bodies always face the same way).
    func testPandaCompareRow() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        for (suffix, yaw) in [("front", Float(0)), ("34", Float(0.6))] {
            var cells: [UIImage] = []
            for id in [4, Self.pandaID, 5] {
                let s = try pandaStill(id: id, yaw: yaw, size: 480, dist: 3.9, lookY: 0.5, lift: 0.18)
                cells.append(tlabel(s.img.uiImage()!, [JellyRoster.baseNames[id]], bar: 26))
            }
            try pandaSave(tgrid(cells, cols: 3), "compare_row_\(suffix).png")
        }
    }

    func testPandaCompare() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        W = 900; H = 600
        let chars = [Char(id: 4), Char(id: Self.pandaID), Char(id: 5)]
        let lab = setUpLab([SIMD2(-1.0, 0.6), SIMD2(0.0, 0.2), SIMD2(1.0, 0.6)], chars: chars, seed: 3)
        for r in lab.rigs { r.brain.autonomy = false; r.brain.expr.enabled = false }
        let (ren, target) = try renderer(lab)
        let d = dress(lab, chars)
        for _ in 0..<60 { lab.tick(watching: false); for (k, r) in lab.rigs.enumerated() { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(d, k, r, chars[k]) } }
        var out: [UIImage] = []
        for (name, lift, dist, lookY) in [("3/4 high", Float(0.2), Float(6.2), Float(0.5)), ("front", Float(0.08), Float(6.4), Float(0.55))] {
            let cc = SIMD3<Float>(0, lab.rigs[1].sim.floorY + lookY, 0.55)
            let dir = simd_normalize(name == "front" ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0.35, 0, 1))
            let cam = Self.lookCamera(target: cc, dir: dir, dist: dist, aspect: Float(W) / Float(H), lift: lift)
            let img = composite(lab, d, chars, ren, target, cam: cam)
            out.append(tlabel(img.uiImage()!, ["Teddy | Panda | Pearl  -  \(name)"], bar: 26))
        }
        try pandaSave(out[0], "compare_34.png"); try pandaSave(out[1], "compare_front.png")
    }

    func pandaMotion(_ name: String, start: @escaping (MotionRig) -> Void, warm: Float, secs: Float, every: Int, count: Int, yaw: Float, outfit: Outfit = [:], id: Int = 6, size: Int = 420) throws -> [UIImage] {
        W = size; H = size
        let c = Char(id: id, outfit: outfit)
        let lab = setUpLab([SIMD2(0.4, 0.6)], chars: [c], seed: 3)
        let r = lab.rigs[0]
        r.brain.autonomy = false; r.brain.expr.enabled = false
        let dd = dress(lab, [c])
        let (ren, target) = try renderer(lab)
        for _ in 0..<60 { lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(dd, 0, r, c) }
        start(r)
        var frames: [UIImage] = []
        let total = Int((warm + secs) * 60)
        for t in 0..<total {
            lab.tick(watching: false); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tick(dd, 0, r, c)
            if t >= Int(warm * 60), (t - Int(warm * 60)) % every == 0, frames.count < count {
                let pose = r.sim.bodyPose(iterations: 3)
                var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
                fwd = simd_length(fwd) > 0.3 ? simd_normalize(fwd) : SIMD3(0, 0, 1)
                let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
                let cam = Self.lookCamera(target: SIMD3(pose.centroid.x, r.sim.floorY + 0.55, pose.centroid.z), dir: dir, dist: 3.9, aspect: 1, lift: 0.18)
                frames.append(tlabel(composite(lab, dd, [c], ren, target, cam: cam).uiImage()!, ["\(name) f\(frames.count)"], bar: 22))
            }
        }
        return frames
    }

    func testPandaWalkSleep() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        func walk(_ dx: Float, _ dz: Float) -> (MotionRig) -> Void { { r in
            let p = r.sim.bodyPose(iterations: 3).centroid
            r.brain.script = .walk(target: SIMD2(p.x + dx, p.z + dz), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 } }
        let w34 = try pandaMotion("walk 3/4", start: walk(-3, 0.3), warm: 0.8, secs: 1.2, every: 9, count: 6, yaw: 0.75)
        let wBack = try pandaMotion("walk back 3/4", start: walk(-3, 0.3), warm: 0.8, secs: 1.2, every: 9, count: 6, yaw: 2.4)
        try pandaSave(tgrid(w34 + wBack, cols: 6), "walk_sheet.png")
        let sleepStart: (MotionRig) -> Void = { r in r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 500 }
        let sleep = try pandaMotion("sleep", start: sleepStart, warm: 5.0, secs: 1.0, every: 60, count: 1, yaw: 0.75)
        let sleepB = try pandaMotion("sleep back", start: sleepStart, warm: 5.0, secs: 1.0, every: 60, count: 1, yaw: 2.4)
        try pandaSave(tgrid(sleep + sleepB, cols: 2), "asleep.png")
        let hop = try pandaMotion("hop", start: { r in r.brain.startHopPlay(sim: r.sim) }, warm: 0.0, secs: 1.6, every: 12, count: 6, yaw: 0.75)
        try pandaSave(tgrid(hop, cols: 6), "hop_sheet.png")
    }

    func testPandaHats() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        let hats = WearLook.looks(.head)
        var cells: [UIImage] = []
        for (title, yaw) in [("Honey pom-pom beanie", Float(0.6)), ("Honey pom-pom beanie", 2.5), ("Royal crown", 0.6), ("Royal crown", 2.5), ("Flower crown", 0.6), ("Cat-ear headband", 0.6)] {
            guard let look = hats.first(where: { $0.title == title }) else { continue }
            let s = try pandaStill(id: Self.pandaID, outfit: [.head: look], yaw: yaw, size: 520, dist: 3.3, lookY: 0.6, lift: 0.12)
            let state = s.fit.earsHidden ? "ears tucked" : "ears out"
            cells.append(pandaLabelled(s, "Panda - \(title) - \(state)\(yaw > 2 ? " (back 3/4)" : "")"))
        }
        try pandaSave(tgrid(cells, cols: 3), "hats_sheet.png")
    }

    /// The lobby head portrait's framing (the head and a little body, the neutral face) through the same renderer and rig. (The live path is MelonStage.headSnapshot;
    /// this reproduces its camera offscreen, since that one needs the running stage.)
    func testPandaPortrait() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        var cells: [UIImage] = []
        for id in [4, Self.pandaID, 5] {
            let s = try pandaStill(id: id, yaw: 0.35, size: 300, dist: 2.9, lookY: 0.5, lift: 0.04)
            cells.append(tlabel(s.img.uiImage()!, [JellyRoster.baseNames[id] + " portrait"], bar: 24))
        }
        try pandaSave(tgrid(cells, cols: 3), "portraits.png")
    }
}
