//
//  TigerBerryCaptureTests.swift
//  Not a regression test: renders the Tiger (character 7) and the Berry (character 8) with the REAL renderer when PANDA_DIR is set (TEST_RUNNER_PANDA_DIR),
//  on PandaCaptureTests' rig (`pandaStill`, `pandaMotion`, `pandaSave`). Every file lands in PANDA_DIR; the names start with "tiger" / "berry" / "family".
//  The check that no EXISTING species moved is PandaCaptureTests' own, run on the base and on the branch: testPandaZRefShots + testPandaZLookShots (raw bytes)
//  and testPandaBothShaders + testPandaBathAndJersey (sheets).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func tigerBerryPair() -> [(String, Int)] { [("Tiger", JellyRoster.tigerID), ("Berry", JellyRoster.berryID)] }

    /// Six views of each: the crown / cheek / back stripes of the Tiger; the seeds (none on the face) and the leaf top of the Berry.
    func testTigerBerryViews() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        let views: [(String, Float, Float, Float, Float)] = [("front", 0, 0.18, 3.9, 0.5), ("3-4 front", 0.75, 0.18, 3.9, 0.5), ("side", .pi / 2, 0.18, 3.9, 0.5),
                                                             ("back", .pi, 0.18, 3.9, 0.5), ("3-4 back", 2.4, 0.18, 3.9, 0.5), ("top-down", .pi * 0.9, 2.6, 3.8, 0.35)]
        for (who, id) in tigerBerryPair() {
            var cells: [UIImage] = []
            for (name, yaw, lift, dist, lookY) in views {
                let s = try pandaStill(id: id, yaw: yaw, size: 600, dist: dist, lookY: lookY, lift: lift)
                let t = pandaLabelled(s, "\(who) \(name)")
                cells.append(t)
                try pandaSave(t, "\(who.lowercased())_view_\(name.replacingOccurrences(of: " ", with: "_")).png")
            }
            try pandaSave(tgrid(cells, cols: 3), "\(who.lowercased())_views_sheet.png")
        }
    }

    /// Close-ups of the face: the cheek stripes next to the blush, no seed on the face, the eyes and the mouth clear.
    func testTigerBerryFace() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        var cells: [UIImage] = []
        for (who, id) in tigerBerryPair() {
            for (name, yaw) in [("face front", Float(0)), ("face 3-4", 0.6)] {
                let s = try pandaStill(id: id, yaw: yaw, size: 700, dist: 2.3, lookY: 0.3, lift: 0.04)
                cells.append(pandaLabelled(s, "\(who) \(name)"))
            }
        }
        try pandaSave(tgrid(cells, cols: 2), "tiger_berry_face_sheet.png")
    }

    /// Each through both matte shaders (GfxBodyFast = the game's, Shaders.metal fsSoftMatte = the fallback): they must agree.
    func testTigerBerryBothShaders() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        var cells: [UIImage] = []
        for (who, id) in tigerBerryPair() {
            for (name, spec) in [("game shader", true), ("fallback shader", false)] {
                for yaw in [Float(0.75), 2.4] {
                    let s = try pandaStill(id: id, yaw: yaw, size: 480, dist: 3.9, lookY: 0.5, lift: 0.18, specialised: spec)
                    cells.append(pandaLabelled(s, "\(who) \(name) \(yaw < 1 ? "3/4 front" : "3/4 back")"))
                }
            }
        }
        try pandaSave(tgrid(cells, cols: 4), "tiger_berry_both_shaders.png")
    }

    /// Each in the bath shader (wet + sparkle, suds) and in the team jersey shader: the marks must still be there, with no stripe and no seed on an arm or a foot.
    func testTigerBerryBathAndJersey() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        defer { Self.forceJersey = nil; Self.forceBath = nil }
        var wet = BathLook(); wet.wet = 0.8; wet.sparkle = 0.6; wet.visible = true
        var suds = BathLook(); suds.visible = true
        for r in 3..<9 { for c in 0..<BathLook.cols { suds.foam[r * BathLook.cols + c] = 0.9 } }
        for (who, id) in tigerBerryPair() {
            var cells: [UIImage] = []
            for (name, look) in [("bath: wet + sparkle", wet), ("bath: suds", suds)] {
                Self.forceBath = look
                for yaw in [Float(0.75), 2.4] { cells.append(pandaLabelled(try pandaStill(id: id, yaw: yaw, size: 480, dist: 3.9, lookY: 0.5, lift: 0.18), "\(who) \(name) \(yaw < 1 ? "3/4 front" : "3/4 back")")) }
            }
            Self.forceBath = nil
            for team in [WearTeam.sky, WearTeam.pink] {
                Self.forceJersey = team
                for yaw in [Float(0.75), 2.4] { cells.append(pandaLabelled(try pandaStill(id: id, yaw: yaw, size: 480, dist: 3.9, lookY: 0.5, lift: 0.18), "\(who) jersey \(team) \(yaw < 1 ? "3/4 front" : "3/4 back")")) }
            }
            Self.forceJersey = nil
            try pandaSave(tgrid(cells, cols: 4), "\(who.lowercased())_bath_jersey.png")
        }
    }

    /// Each walking (the arm capsules and the foot beans are drawn again in the plain colour: no stripe and no seed on a limb) and asleep.
    func testTigerBerryWalkSleep() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        func walk(_ dx: Float, _ dz: Float) -> (MotionRig) -> Void { { r in
            let p = r.sim.bodyPose(iterations: 3).centroid
            r.brain.script = .walk(target: SIMD2(p.x + dx, p.z + dz), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 } }
        let sleepStart: (MotionRig) -> Void = { r in r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 500 }
        for (who, id) in tigerBerryPair() {
            let w34 = try pandaMotion("\(who) walk 3/4", start: walk(-3, 0.3), warm: 0.8, secs: 1.2, every: 9, count: 6, yaw: 0.75, id: id)
            let wBack = try pandaMotion("\(who) walk back 3/4", start: walk(-3, 0.3), warm: 0.8, secs: 1.2, every: 9, count: 6, yaw: 2.4, id: id)
            try pandaSave(tgrid(w34 + wBack, cols: 6), "\(who.lowercased())_walk_sheet.png")
            let sleep = try pandaMotion("\(who) asleep", start: sleepStart, warm: 5.0, secs: 1.0, every: 60, count: 1, yaw: 0.75, id: id)
            let sleepB = try pandaMotion("\(who) asleep back", start: sleepStart, warm: 5.0, secs: 1.0, every: 60, count: 1, yaw: 2.4, id: id)
            try pandaSave(tgrid(sleep + sleepB, cols: 2), "\(who.lowercased())_asleep.png")
        }
    }

    /// Hats on each: the Berry's leaf top is paint on the crown, so a hat covers it like any body colour (what shows round the brim is the thing to judge);
    /// the Tiger's crown stripes under a hat.
    func testTigerBerryHats() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        let hats = WearLook.looks(.head)
        for (who, id) in tigerBerryPair() {
            var cells: [UIImage] = []
            for (title, yaw) in [("Honey pom-pom beanie", Float(0.6)), ("Honey pom-pom beanie", 2.5), ("Royal crown", 0.6), ("Royal crown", 2.5), ("Flower crown", 0.6), ("Cat-ear headband", 0.6)] {
                guard let look = hats.first(where: { $0.title == title }) else { continue }
                let s = try pandaStill(id: id, outfit: [.head: look], yaw: yaw, size: 520, dist: 3.3, lookY: 0.6, lift: 0.12)
                cells.append(pandaLabelled(s, "\(who) - \(title)\(yaw > 2 ? " (back 3/4)" : "")"))
            }
            if !cells.isEmpty { try pandaSave(tgrid(cells, cols: 3), "\(who.lowercased())_hats_sheet.png") }
        }
    }

    /// The whole family in a row (front and 3/4), each a separate still: the two new ones next to the seven there were.
    func testTigerBerryFamilyRow() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        for (suffix, yaw) in [("front", Float(0)), ("34", Float(0.6))] {
            var cells: [UIImage] = []
            for id in 0..<JellyRoster.knownCount {
                let s = try pandaStill(id: id, yaw: yaw, size: 360, dist: 3.9, lookY: 0.5, lift: 0.18)
                cells.append(tlabel(s.img.uiImage()!, [JellyRoster.baseNames[id]], bar: 26))
            }
            try pandaSave(tgrid(cells, cols: 9), "family_row_\(suffix).png")
        }
    }

    /// The lobby head portrait's framing (see testPandaPortrait), the Panda next to the two new ones.
    func testTigerBerryPortrait() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        var cells: [UIImage] = []
        for id in [JellyRoster.pandaID, JellyRoster.tigerID, JellyRoster.berryID] {
            let s = try pandaStill(id: id, yaw: 0.35, size: 300, dist: 2.9, lookY: 0.5, lift: 0.04)
            cells.append(tlabel(s.img.uiImage()!, [JellyRoster.baseNames[id] + " portrait"], bar: 24))
        }
        try pandaSave(tgrid(cells, cols: 3), "tiger_berry_portraits.png")
    }
}
