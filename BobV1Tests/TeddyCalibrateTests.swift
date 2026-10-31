//
//  TeddyCalibrateTests.swift
//  Calibration capture (TEDDY_DIR set): what the matte body shader DRAWS for a candidate Teddy flesh, so the three light browns are picked by their drawn colour.
//

import XCTest
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func testTeddyCalibrate() throws {
        let d = try teddyDir()
        DayClock.shared.forcedHour = 12
        let cands: [SIMD3<Float>] = [SIMD3(0.62, 0.36, 0.14), SIMD3(0.58, 0.31, 0.10), SIMD3(0.54, 0.28, 0.08), SIMD3(0.68, 0.42, 0.20), SIMD3(0.50, 0.26, 0.10), SIMD3(0.65, 0.38, 0.22), SIMD3(0.60, 0.40, 0.25), SIMD3(0.72, 0.48, 0.28)]
        var out = ""
        for f in cands {
            TeddyLook.current = TeddyLook.Tone(name: "cal", flesh: f, deep: f * 0.74)
            TeddyMesh.clearCache()
            let s = try teddyShot(yaw: 0, size: 600, dist: 3.5, lookY: 0.35, lift: 0.04)
            let p1 = px(s, SIMD3(0, 1.05, 0.5)), p2 = px(s, SIMD3(0, 0.33, 0.6)), p3 = px(s, SIMD3(-0.36, 0.6, 0.5))
            let body = medianRGB(s, p1.0, p1.1), belly = medianRGB(s, p2.0, p2.1), cheek = medianRGB(s, p3.0, p3.1, r: 4)
            out += String(format: "flesh (%.2f,%.2f,%.2f) -> body %@ cheek %@ belly %@ belly/body %.2f\n", f.x, f.y, f.z, hex(body), hex(cheek), hex(belly), contrast(belly, body))
        }
        try out.write(toFile: d + "/calibrate.txt", atomically: true, encoding: .utf8)
        print(out)
    }
}
