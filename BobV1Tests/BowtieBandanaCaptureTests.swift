//
//  BowtieBandanaCaptureTests.swift
//  Not a regression test: the 2026-11-06 bow tie + bandana sheet (NECK_CAP_DIR / TEST_RUNNER_NECK_CAP_DIR). Built on FeatureCaptureTests' rig (see NecklaceTiltCaptureTests).
//

import XCTest
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    /// Pip (yellow) + sky bow tie BEFORE (the old band, WearRules.bowKeepsBand) / AFTER (bow only), then Panda and Teddy with each bandana (unchanged: they already ride the chain's 0.685 / 1.25 tilt),
    /// at rest and walking, from the game's 3/4 room camera. NECK_CAP_ZOOM=1 = a close orbit view instead (the string's round section).
    func testBowtieBandanaSheet() throws {
        let d = try neckDir(); DayClock.shared.forcedHour = 12
        let zoom = ProcessInfo.processInfo.environment["NECK_CAP_ZOOM"] == "1"
        defer { WearRules.bowKeepsBand = false; WearMeshes.clearCache() }
        let poses: [(String, Int)] = [("rest", 0), ("walk", 40)]
        var cells: [UIImage] = []
        func shot(_ id: Int, _ look: WearLook, _ frames: Int) throws -> UIImage {
            zoom ? try neckStill(id: id, outfit: [.neck: look], yaw: 0.75, walkFrames: frames, size: 300, heading: SIMD2(-1.2, 2.2), motion: "walk", dist: 1.7, lift: 0.3, ty: 0.0)
                 : try neckStill(id: id, outfit: [.neck: look], yaw: 0, walkFrames: frames, room: true, heading: SIMD2(-1.2, 2.2), roomHalf: 70, outSize: 380)
        }
        for (pn, frames) in poses { for after in [false, true] {
            WearRules.bowKeepsBand = !after; WearMeshes.clearCache()
            let im = try shot(1, .bowtieSky, frames)
            cells.append(tlabel(im, ["Pip bowtieSky \(pn): \(after ? "AFTER (bow only)" : "BEFORE (band)")"], bar: 26))
            SocialTests.keep.removeAll()
        } }
        WearRules.bowKeepsBand = false; WearMeshes.clearCache()
        for id in [6, 4] { for look in [WearLook.bandanaCoral, .bandanaMint, .bandanaSun] { for (pn, frames) in poses {
            let im = try shot(id, look, frames)
            cells.append(tlabel(im, ["\(JellyRoster.baseNames[id]) \(look.rawValue) \(pn)"], bar: 26))
            SocialTests.keep.removeAll()
        } } }
        try writePNG(tgrid(cells, cols: 4), d + "/bowtie_bandana_sheet\(zoom ? "_zoom" : "").png", maxBytes: 14_000_000)
    }
}
