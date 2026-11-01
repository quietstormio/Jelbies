//
//  TeddyRoundTests.swift
//  Teddy's head must read as Bob's egg dome: the proof boards (TEDDYROUND_DIR) and the silhouette numbers (egg + fillet pushes vs the bare egg).
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    /// Silhouette radius per angle (720 bins) of the egg vertices in three projections, ears excluded; returns the worst relative deviation (%) of Teddy's egg (rest + fillet pushes) vs Bob's.
    func teddySilhouetteDeviation(guardBand: Double = 0.06) -> (worst: Double, maxPush: Double, farthestPushed: Double) {
        let rm = MotionRig.renderMesh
        let nEgg = rm.armCapsule?.firstVertex.min() ?? rm.vertexCount
        let rig = TeddyBean.rig(rest: rm.rest, eggLimit: nEgg)
        var teddy = (0..<nEgg).map { SIMD3<Double>(Double(rm.rest[3 * $0]), Double(rm.rest[3 * $0 + 1]), Double(rm.rest[3 * $0 + 2])) }
        let bob = teddy
        var maxPush = 0.0, far = 0.0
        for (pi, bumps) in rig.bumps.enumerated() {
            for (v, d) in bumps {
                if pi < 2 { teddy[v] += SIMD3(Double(d.x), Double(d.y), Double(d.z)) }       // (the pom is unchanged and not part of this check)
                if pi < 2 {
                    maxPush = max(maxPush, Double(simd_length(d)))
                    far = max(far, max(TeddyBean.parts[pi].sdf(bob[v]), 0))
                }
            }
        }
        // the ear roots (within guardBand of an ear's solid) are excluded from both
        var keep = [Bool](repeating: true, count: nEgg)
        for v in 0..<nEgg { for p in TeddyBean.parts.prefix(2) where p.sdf(bob[v]) < guardBand { keep[v] = false } }
        let c = SIMD3<Double>(0, 0.6, 0)
        var worst = 0.0
        let overlayDir = ProcessInfo.processInfo.environment["TEDDYROUND_DIR"]
        for proj in 0..<3 {
            func xy(_ p: SIMD3<Double>) -> SIMD2<Double> {
                let q = p - c
                return proj == 0 ? SIMD2(q.x, q.y) : proj == 1 ? SIMD2(q.z, q.y) : SIMD2(q.x, q.z)
            }
            var rb = [Double](repeating: 0, count: 720), rt = rb
            for v in 0..<nEgg where keep[v] {
                let sb = xy(bob[v])
                let bin = min(719, Int((atan2(sb.y, sb.x) + .pi) / (2 * .pi) * 720))          // (both shapes binned by Bob's angle: the same vertices on each side)
                rb[bin] = max(rb[bin], simd_length(sb)); rt[bin] = max(rt[bin], simd_length(xy(teddy[v])))
            }
            if guardBand > 0, let dir = overlayDir, !dir.isEmpty {              // the overlay: Bob's egg (grey) under Teddy's egg without ears (red), ears' roots (blue) marked
                let side: CGFloat = 800, sc: CGFloat = 330
                func pt(_ p: SIMD3<Double>) -> CGPoint { let q = xy(p); return CGPoint(x: side / 2 + CGFloat(q.x) * sc, y: side / 2 - CGFloat(q.y) * sc) }
                let bobPts = bob.map { pt($0) }, tedPts = teddy.map { pt($0) }
                let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { g in
                    UIColor.white.setFill(); g.fill(CGRect(x: 0, y: 0, width: side, height: side))
                    for v in 0..<nEgg { UIColor(white: 0.55, alpha: 1).setFill(); let a = bobPts[v]; g.fill(CGRect(x: a.x - 2.5, y: a.y - 2.5, width: 5, height: 5)) }
                    for v in 0..<nEgg { (keep[v] ? UIColor.red : UIColor.blue).setFill(); let a = tedPts[v]; g.fill(CGRect(x: a.x - 1, y: a.y - 1, width: 2, height: 2)) }
                    ("Silhouette overlay (\(["front", "side", "top"][proj])): Bob egg grey, Teddy egg red (blue = ear root band <0.06)" as NSString).draw(at: CGPoint(x: 8, y: 8), withAttributes: [.font: UIFont.systemFont(ofSize: 15)])
                }
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? img.pngData()?.write(to: URL(fileURLWithPath: dir + "/overlay_\(["front", "side", "top"][proj]).png"))
            }
            for b in 0..<720 where rb[b] > 0.3 { worst = max(worst, abs(rt[b] - rb[b]) / rb[b] * 100) }
        }
        return (worst, maxPush, far)
    }

    func testTeddyRoundNumbers() throws {
        let all = teddySilhouetteDeviation(guardBand: 0)
        print("TEDDYROUND silhouette deviation with NOTHING excluded (fillet pushes included): \(all.worst)%")
        let r = teddySilhouetteDeviation()
        print("TEDDYROUND silhouetteMaxDeviation%=\(r.worst) maxPush=\(r.maxPush) farthestPushedFromEar=\(r.farthestPushed)")
        XCTAssertLessThan(r.worst, 0.5, "silhouette dev % \(r.worst) maxPush \(r.maxPush) farthest \(r.farthestPushed)")
        XCTAssertLessThan(r.farthestPushed, 0.075, "farthest \(r.farthestPushed)")
    }

    func testTeddyRoundBoards() throws {
        guard let d = ProcessInfo.processInfo.environment["TEDDYROUND_DIR"], !d.isEmpty else { throw XCTSkip("TEDDYROUND_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        DayClock.shared.forcedHour = 12
        variant(.cream)
        var row: [UIImage] = []
        for (name, id) in [("Pearl", 5), ("Bob", 0), ("Teddy", 4)] {
            let s = try earShot(id: id, yaw: 0, size: 700, dist: 3.5, lookRest: SIMD3(0, 0.75, 0), lift: 0.12)
            row.append(tlabel(s.img.uiImage()!, [name + " front"]))
        }
        try writePNG(tgrid(row, cols: 3), d + "/front3.png")
        var cells: [UIImage] = []
        for (label, yaw) in [("Teddy 3/4", Float(0.7)), ("Teddy side", Float.pi / 2), ("Teddy front", Float(0))] {
            let s = try earShot(id: 4, yaw: yaw, size: 700, dist: 3.5, lookRest: SIMD3(0, 0.75, 0), lift: 0.12)
            cells.append(tlabel(s.img.uiImage()!, [label]))
        }
        try writePNG(tgrid(cells, cols: 3), d + "/teddy_views.png")
    }
}
