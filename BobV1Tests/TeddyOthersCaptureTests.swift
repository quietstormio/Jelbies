//
//  TeddyOthersCaptureTests.swift
//  Not a regression test: renders Bob, Pip, Moss, Lavender and Pearl (front + back, bare and a few motions) with the real renderer into OTHERS_DIR, so a
//  before / after pair can be diffed pixel for pixel (Teddy's body-mesh ears must change nothing for any other species).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func othersShot(id: Int, yaw: Float, size: Int = 640, ticks: Int = 24) throws -> LockImage {
        W = size; H = size
        let c = Char(id: id)
        let lab = setUpLab([SIMD2(0.2, 0.6)], chars: [c], seed: 3)
        let (ren, target) = try renderer(lab)
        let d = dress(lab, [c])
        let r = lab.rigs[0]
        for _ in 0..<ticks { lab.tick(watching: false); tick(d, 0, r, c) }
        let pose = r.sim.bodyPose(iterations: 3)
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_normalize(fwd)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let cc = pose.centroid
        let cam = Self.lookCamera(target: SIMD3(cc.x, cc.y + 0.35, cc.z), dir: dir, dist: 3.4, aspect: 1, lift: 0.1)
        return composite(lab, d, [c], ren, target, cam: cam)
    }

    func testOthersBeforeAfter() throws {
        guard let d = ProcessInfo.processInfo.environment["OTHERS_DIR"], !d.isEmpty else { throw XCTSkip("OTHERS_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        DayClock.shared.forcedHour = 12
        let names = ["bob", "pip", "moss", "lavender", "teddy", "pearl"]
        for (i, name) in names.enumerated() {
            let id = i                                   // roster ids: 0 Bob, 1 Pip, 2 Moss, 3 Lavender, 4 Teddy, 5 Pearl
            for (vn, yaw) in [("front", Float(0)), ("back", Float.pi), ("q34", Float(0.7))] {
                let img = try othersShot(id: id, yaw: yaw)
                try img.uiImage()!.pngData()!.write(to: URL(fileURLWithPath: d + "/\(name)_\(vn).png"))
            }
        }
    }
}
