//
//  TeddyEarsBoardTests.swift
//  Teddy's body-mesh ears + pom (TeddyBean): the proof boards (TEST_RUNNER_TEDDYEARS_DIR) and the unit checks.
//  Built on FeatureCaptureTests' rig / TeddyCaptureTests' helpers.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func earsDir() throws -> String {
        guard let d = ProcessInfo.processInfo.environment["TEDDYEARS_DIR"], !d.isEmpty else { throw XCTSkip("TEDDYEARS_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    func variant(_ v: TeddyEarsVariant) { TeddyEarsVariant.active = v; TeddyMesh.clearCache(); TeddyFit.clearCache(); FeatureMeshes.clearCache() }

    /// One frame of a Teddy (or any character) looking at `lookRest` (a rest-space point carried to the world) from `yaw` off his front.
    func earShot(id: Int = 4, outfit: Outfit = [:], yaw: Float, size: Int = 700, dist: Float = 3.5, lookRest: SIMD3<Float> = SIMD3(0, 0.6, 0), lift: Float = 0.04, seed: UInt64 = 3,
                 ticks: Int = 12, prepare: ((SocialTests.Lab, Dressed) -> Void)? = nil) throws -> TShot {
        W = size; H = size
        let c = Char(id: id, outfit: outfit)
        let lab = setUpLab([SIMD2(0.2, 0.6)], chars: [c], seed: seed)
        let (ren, target) = try renderer(lab)
        let d = dress(lab, [c])
        prepare?(lab, d)
        let r = lab.rigs[0]
        for _ in 0..<ticks { lab.tick(watching: false); tick(d, 0, r, c) }
        let pose = r.sim.bodyPose(iterations: 3)
        var fwd = pose.rotation.act(SIMD3<Float>(0, 0, 1)); fwd.y = 0
        fwd = simd_normalize(fwd)
        let dir = SIMD3<Float>(fwd.x * cosf(yaw) + fwd.z * sinf(yaw), 0, -fwd.x * sinf(yaw) + fwd.z * cosf(yaw))
        let carry = d.feats[0].slot(0)?.carry ?? EyeMaskModel.Carry(centroid: pose.centroid, rotation: pose.rotation, squash: r.sim.attractor.squash, restCentroid: r.sim.restCentroid)
        let tgt = carry.world(lookRest)
        let cam = Self.lookCamera(target: tgt, dir: dir, dist: dist, aspect: 1, lift: lift)
        let img = composite(lab, d, [c], ren, target, cam: cam)
        return TShot(img: img, cam: cam, carry: carry, fit: d.feats[0].slot(0)?.fit ?? FeatureFit())
    }

    func refPanel(_ side: CGFloat) -> UIImage? {
        let refPath = ProcessInfo.processInfo.environment["TEDDY_REF"] ?? "/Users/dmarshall94/.claude/uploads/9cd2e159-911b-4a04-879f-e5e34721a64a/7a76d791-image.png"
        guard let ref = UIImage(contentsOfFile: refPath), let cg = ref.cgImage else { return nil }
        let crop = CGRect(x: 230, y: 250, width: 900, height: 900).intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return scaled(UIImage(cgImage: cg.cropping(to: crop)!), side)
    }

    // MARK: 01 old / cream / fur

    func testEarsBoard01() throws {
        let d = try earsDir(); DayClock.shared.forcedHour = 12
        var cells: [UIImage] = []
        if let r = refPanel(700) { cells.append(tlabel(r, ["REFERENCE (pink)"])) }
        for v in [TeddyEarsVariant.old, .cream, .fur] {
            variant(v)
            for (label, yaw) in [("front", Float(0)), ("3/4", Float(0.45))] {
                let s = try earShot(yaw: yaw, size: 700, dist: 3.5, lookRest: SIMD3(0, 0.75, 0), lift: 0.04)
                cells.append(tlabel(s.img.uiImage()!, ["\(v.rawValue) - Teddy \(label)"]))
            }
        }
        variant(.cream)
        try writePNG(tgrid(cells, cols: 3), d + "/01_old_cream_fur.png")
    }

    /// Ear close-ups from several sides (the root: no seam, crease, colour step) and the pom.
    func testEarsBoard03() throws {
        let d = try earsDir(); DayClock.shared.forcedHour = 12
        variant(.cream)
        let ear = TeddyBean.parts[0].o
        let earTip = SIMD3<Float>(Float(ear.x), Float(ear.y) + 0.1, Float(ear.z))
        var cells: [UIImage] = []
        for (label, yaw, dist) in [("ear front", Float(0), Float(1.1)), ("ear 3/4 front", Float(0.6), 1.1), ("ear side (from outside)", .pi / 2, 1.1), ("ear 3/4 back", 2.3, 1.1), ("ear back", .pi, 1.1), ("ear from above-front", 0.3, 1.1)] {
            let s = try earShot(yaw: yaw, size: 560, dist: dist, lookRest: earTip, lift: label.contains("above") ? 0.9 : 0.05)
            cells.append(tlabel(s.img.uiImage()!, [label]))
        }
        try writePNG(tgrid(cells, cols: 3), d + "/03_ear_closeups.png")
        let pom = TeddyBean.parts[2].o
        let pomP = SIMD3<Float>(Float(pom.x), Float(pom.y), Float(pom.z))
        var cells2: [UIImage] = []
        for (label, yaw) in [("pom back", Float.pi), ("pom 3/4 back", 2.4), ("pom side", .pi / 2)] {
            let s = try earShot(yaw: yaw, size: 560, dist: 1.0, lookRest: pomP, lift: 0.05)
            cells2.append(tlabel(s.img.uiImage()!, [label]))
        }
        try writePNG(tgrid(cells2, cols: 3), d + "/03_pom_closeups.png")
    }

    // MARK: 02 turnaround

    func testEarsBoard02() throws {
        let d = try earsDir(); DayClock.shared.forcedHour = 12
        variant(.cream)
        var cells: [UIImage] = []
        let views: [(String, Float, Float, Float)] = [("front", 0, 0.1, 3.4), ("3/4 L", -0.75, 0.1, 3.4), ("3/4 R", 0.75, 0.1, 3.4), ("side", .pi / 2, 0.1, 3.4), ("back", .pi, 0.1, 3.4), ("high 3/4 from above", 0.6, 1.9, 3.4)]
        for (name, yaw, lift, dist) in views {
            let s = try earShot(yaw: yaw, size: 640, dist: dist, lookRest: SIMD3(0, 0.75, 0), lift: lift)
            cells.append(tlabel(s.img.uiImage()!, ["Teddy \(name)"]))
        }
        try writePNG(tgrid(cells, cols: 3), d + "/02_cream_turnaround.png")
    }
}
