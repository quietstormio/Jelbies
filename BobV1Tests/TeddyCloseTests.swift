//
//  TeddyCloseTests.swift
//  Capture (TEDDY_DIR set): close-ups of the pom (back, 3/4 back, side) and of an ear (front 3/4).
//

import XCTest
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func testTeddyPomAndEarClose() throws {
        let d = try teddyDir(); teddyTone()
        DayClock.shared.forcedHour = 12
        var cells: [UIImage] = []
        for (name, yaw, dist, lookY, lift) in [("pom back", Float.pi, Float(1.6), Float(-0.2), Float(0.05)), ("pom 3/4 back", 2.4, 1.6, -0.2, 0.05), ("pom side", Float.pi / 2, 1.6, -0.2, 0.05), ("ear 3/4", 0.6, 1.9, 0.55, 0.05)] {
            let s = try teddyShot(yaw: yaw, size: 500, dist: dist, lookY: lookY, lift: lift)
            cells.append(tlabel(s.img.uiImage()!, [name]))
        }
        try writePNG(tgrid(cells, cols: 4), d + "/09_pom_ear_closeups.png")
    }
}
