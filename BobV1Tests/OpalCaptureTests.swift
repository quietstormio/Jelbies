//
//  OpalCaptureTests.swift
//  Not a regression test: renders Opal (character 12, the iridescent wave, body mode 86) with the REAL renderer when PANDA_DIR is set (TEST_RUNNER_PANDA_DIR), on PandaCaptureTests' rig
//  (`pandaStill`, `pandaMotion`, `pandaSave`), copied from TigerBerryCaptureTests. Every file lands in PANDA_DIR; the names are opal_*.png.
//  Views at 768 px: front / back / side / three-quarter; asleep with the mask; wet in the bath; under a jersey; wearing a hat and shoes; walking (feet colours).
//  The wave is ONE plane through the rest body, so the same colours must read from every side, and a foot or a limb piece takes the colour of its own height and side.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    /// Front / back / side / three-quarter at 768 px, plus a sheet.
    func testOpalViews() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        let id = JellyRoster.opalID
        var cells: [UIImage] = []
        for (name, yaw) in [("front", Float(0)), ("back", Float.pi), ("side", Float.pi / 2), ("three-quarter", 0.75)] {
            let s = try pandaStill(id: id, yaw: yaw, size: 768, dist: 3.9, lookY: 0.5, lift: 0.18)
            let t = pandaLabelled(s, "Opal \(name)")
            cells.append(t)
            try pandaSave(t, "opal_view_\(name).png")
        }
        try pandaSave(tgrid(cells, cols: 2), "opal_views_sheet.png")
    }

    /// Asleep with the sleep mask (lilac), front and back three-quarter.
    func testOpalAsleep() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        let sleepStart: (MotionRig) -> Void = { r in r.brain.idleForced = true; XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 500 }
        let a = try pandaMotion("Opal asleep", start: sleepStart, warm: 5.0, secs: 1.0, every: 60, count: 1, yaw: 0.75, id: JellyRoster.opalID, size: 768)
        let b = try pandaMotion("Opal asleep back", start: sleepStart, warm: 5.0, secs: 1.0, every: 60, count: 1, yaw: 2.4, id: JellyRoster.opalID, size: 768)
        try pandaSave(tgrid(a + b, cols: 2), "opal_asleep.png")
    }

    /// Wet in the bath (wet + sparkle, suds) and under a team jersey: the wave must still read.
    func testOpalBathAndJersey() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        defer { Self.forceJersey = nil; Self.forceBath = nil }
        var wet = BathLook(); wet.wet = 0.8; wet.sparkle = 0.6; wet.visible = true
        var suds = BathLook(); suds.visible = true
        for r in 3..<9 { for c in 0..<BathLook.cols { suds.foam[r * BathLook.cols + c] = 0.9 } }
        let id = JellyRoster.opalID
        var cells: [UIImage] = []
        for (name, look) in [("bath: wet", wet), ("bath: suds", suds)] {
            Self.forceBath = look
            for yaw in [Float(0.75), 2.4] { cells.append(pandaLabelled(try pandaStill(id: id, yaw: yaw, size: 768, dist: 3.9, lookY: 0.5, lift: 0.18), "Opal \(name) \(yaw < 1 ? "3/4 front" : "3/4 back")")) }
        }
        Self.forceBath = nil
        for team in [WearTeam.sky, WearTeam.pink] {
            Self.forceJersey = team
            for yaw in [Float(0.75), 2.4] { cells.append(pandaLabelled(try pandaStill(id: id, yaw: yaw, size: 768, dist: 3.9, lookY: 0.5, lift: 0.18), "Opal jersey \(team) \(yaw < 1 ? "3/4 front" : "3/4 back")")) }
        }
        Self.forceJersey = nil
        try pandaSave(tgrid(cells, cols: 4), "opal_bath_jersey.png")
    }

    /// A hat, and shoes (the shoes cover the feet: what shows above them is the thing to judge).
    func testOpalHatAndShoes() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        let id = JellyRoster.opalID
        var cells: [UIImage] = []
        if let hat = WearLook.looks(.head).first(where: { $0.title == "Honey pom-pom beanie" }) {
            for yaw in [Float(0.6), 2.5] { cells.append(pandaLabelled(try pandaStill(id: id, outfit: [.head: hat], yaw: yaw, size: 768, dist: 3.3, lookY: 0.6, lift: 0.12), "Opal hat \(yaw > 2 ? "(back 3/4)" : "")")) }
        }
        if let shoes = WearLook.looks(.feet).first {
            for yaw in [Float(0.6), 2.5] { cells.append(pandaLabelled(try pandaStill(id: id, outfit: [.feet: shoes], yaw: yaw, size: 768, dist: 3.9, lookY: 0.5, lift: 0.18), "Opal shoes \(yaw > 2 ? "(back 3/4)" : "")")) }
        }
        if !cells.isEmpty { try pandaSave(tgrid(cells, cols: 2), "opal_hat_shoes.png") }
    }

    /// Walking: the arm capsules and the foot beans take the colour of their own height and side (one foot pinkish, one blue-ish), no renderer split.
    func testOpalWalk() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        func walk(_ dx: Float, _ dz: Float) -> (MotionRig) -> Void { { r in
            let p = r.sim.bodyPose(iterations: 3).centroid
            r.brain.script = .walk(target: SIMD2(p.x + dx, p.z + dz), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0 } }
        let id = JellyRoster.opalID
        let w34 = try pandaMotion("Opal walk 3/4", start: walk(-3, 0.3), warm: 0.8, secs: 1.2, every: 9, count: 6, yaw: 0.75, id: id, size: 768)
        let wBack = try pandaMotion("Opal walk back 3/4", start: walk(-3, 0.3), warm: 0.8, secs: 1.2, every: 9, count: 6, yaw: 2.4, id: id, size: 768)
        try pandaSave(tgrid(w34 + wBack, cols: 6), "opal_walk_sheet.png")
    }
}
