//
//  CowCaptureTests.swift
//  Not a regression test: renders the three cows with the REAL renderer when PANDA_DIR is set (TEST_RUNNER_PANDA_DIR): front / back / side at 768 px (cow_<name>_<view>.png) and a walk sheet.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func testCowViews() throws {
        _ = try pandaDir(); DayClock.shared.forcedHour = 12
        for (id, name) in [(13, "moo"), (14, "cocoa"), (15, "blush")] {
            for (view, yaw) in [("front", Float(0)), ("back", Float.pi), ("side", -Float.pi / 2), ("tq", 0.75)] {
                try pandaSave(pandaLabelled(try pandaStill(id: id, yaw: yaw, size: 768, dist: 3.9, lookY: 0.5, lift: 0.18), "\(name) \(view)"), "cow_\(name)_\(view).png")
            }
        }
    }
}

extension FeatureCaptureTests {
    /// The finish family (FinishLook.swift): cut-out front / back / side at 768 px with the phone build's jelly look (finish_<name>_<view>.png, transparent background), for the drawing boards.
    func testFinishViews() throws {
        let d = try pandaDir(); DayClock.shared.forcedHour = 12
        let was = (JellyLook.level, JellyLook.all); JellyLook.level = 1; JellyLook.all = true
        defer { JellyLook.level = was.0; JellyLook.all = was.1 }
        let env = ProcessInfo.processInfo.environment
        let dist = Float(env["CHAR_DIST"] ?? "") ?? 3.3, lookY = Float(env["CHAR_LOOKY"] ?? "") ?? 0.3, lift = Float(env["CHAR_LIFT"] ?? "") ?? 0.2
        for (id, name) in [(10, "gold"), (11, "silver"), (26, "bronze"), (17, "ruby"), (23, "emerald"), (24, "sapphire"), (25, "amethyst")] {
            for (view, yaw) in [("front", Float(0)), ("back", Float.pi), ("side", -Float.pi / 2)] {
                let s = try charSheetStill(id: id, yaw: yaw, size: 768, dist: dist, lookY: lookY, lift: lift, warm: 150)
                try charSheetWritePNG(s.cut, d + "/finish_\(name)_\(view).png")
                if view == "front" { try charSheetWritePNG(s.room, d + "/finish_\(name)_room.png") }
            }
        }
    }
}
