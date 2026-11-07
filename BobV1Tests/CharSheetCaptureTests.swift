//
//  CharSheetCaptureTests.swift
//  Not a regression test: front / back / side stills of every character (bare, at rest) with the REAL renderer when CHAR_DIR is set
//  (TEST_RUNNER_CHAR_DIR). Built on PandaCaptureTests' pandaStill rig.
//

import XCTest
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func testCharSheetViews() throws {
        guard let d = ProcessInfo.processInfo.environment["CHAR_DIR"], !d.isEmpty else { throw XCTSkip("CHAR_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        DayClock.shared.forcedHour = 12
        Self.forceCutout = ProcessInfo.processInfo.environment["CHAR_CUTOUT"] == "1"; defer { Self.forceCutout = false }
        let sideYaw = Float(ProcessInfo.processInfo.environment["CHAR_SIDE_YAW"] ?? "") ?? (-.pi / 2)
        let dist = Float(ProcessInfo.processInfo.environment["CHAR_DIST"] ?? "") ?? 3.9
        let lookY = Float(ProcessInfo.processInfo.environment["CHAR_LOOKY"] ?? "") ?? 0.5
        let lift = Float(ProcessInfo.processInfo.environment["CHAR_LIFT"] ?? "") ?? 0.2
        let only = ProcessInfo.processInfo.environment["CHAR_ONLY"].flatMap { Int($0) }
        for id in 0..<JellyRoster.knownCount where only == nil || only == id {
            let name = JellyRoster.baseNames[id].lowercased()
            for (vn, yaw) in [("front", Float(0)), ("back", Float.pi), ("side", sideYaw)] {
                let s = try pandaStill(id: id, yaw: yaw, size: 768, dist: dist, lookY: lookY, lift: lift, warm: 150)
                try s.img.uiImage()!.pngData()!.write(to: URL(fileURLWithPath: d + "/\(id)_\(name)_\(vn).png"))
            }
        }
    }
}
