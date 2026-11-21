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
