//
//  HUDLayoutTests.swift
//  The side rails sit at the bottom of the screen (as on release) and the roam floor keeps Jelbies out from under them in portrait (corner cut-outs).
//

import XCTest
@testable import BobV1

@MainActor
final class HUDLayoutTests: XCTestCase {
    override func tearDown() { GameCamera.clearRoam(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    private func rects(_ size: CGSize) -> [CGRect] {
        let h = HUDLayout.railHeightFraction * size.height
        return [CGRect(x: 16, y: size.height - h, width: 60, height: h),
                CGRect(x: size.width - 20 - 72, y: size.height - h, width: 72, height: h)]
    }

    /// Every sampled spot the floor lets a body centre use (rows x free spans, ends and middle) must have a body box clear of both rail rectangles.
    private func check(_ size: CGSize) throws {
        let aspect = Float(size.width / size.height)
        GameCamera.configureRoom(count: 3)
        let rf = try XCTUnwrap(GameCamera.refreshRoam(aspect: aspect))
        let cam = GameCamera.camera(aspect: aspect)
        var usable = 0
        for (i, z) in rf.zs.enumerated() {
            for r in rf.free[i] {
                for x in stride(from: r.lowerBound, through: r.upperBound, by: 0.1) {
                    usable += 1
                    let e = GameCamera.roamLateralExtent, h = BobShape.H * 1.25, d: Float = 0.8
                    var cs = [SIMD3<Float>]()
                    for cx in [x - e, x + e] { for cy in [0, h] { for cz in [z - d, z + d] { cs.append(SIMD3(cx, cy, cz)) } } }
                    let pts = Silhouette.project(cs, viewProj: cam.viewProj, size: size)
                    let box = CGRect(x: pts.map(\.x).min()!, y: pts.map(\.y).min()!, width: pts.map(\.x).max()! - pts.map(\.x).min()!, height: pts.map(\.y).max()! - pts.map(\.y).min()!)
                    for rr in rects(size) { XCTAssertFalse(rr.intersects(box), "body at x \(x) z \(z) is under a rail at \(size)") }
                }
            }
        }
        XCTAssertGreaterThan(usable, 100)
        // the middle front stays usable: the front row has free floor around x = 0
        XCTAssertTrue(rf.free[rf.zs.count - 1].contains { $0.contains(0) }, "front middle must stay walkable at \(size)")
        XCTAssertTrue(rf.free[rf.zs.count - 2].contains { $0.contains(0) })
        XCTAssertGreaterThan(rf.area, 1)
    }

    func testPortraitNoFrontRowBodyUnderTheRails() throws {
        try check(CGSize(width: 402, height: 874))
        try check(CGSize(width: 393, height: 852))
        try check(CGSize(width: 440, height: 956))
    }

    func testLandscapeFloorIsNotCut() throws {
        GameCamera.configureRoom(count: 3)
        let rf = try XCTUnwrap(GameCamera.refreshRoam(aspect: 874.0 / 402.0))
        let last = rf.zs.count - 1
        XCTAssertEqual(rf.free[last].first?.lowerBound ?? 9, -rf.hw[last], accuracy: 0.06, "landscape keeps the full front row")
    }

    func testRailsAreAtTheBottomInBothOrientations() {
        XCTAssertEqual(HUDLayout.lift(size: CGSize(width: 402, height: 874), safeBottom: 34, compact: false), 0)
        XCTAssertEqual(HUDLayout.lift(size: CGSize(width: 874, height: 402), safeBottom: 21, compact: true), 0)
        XCTAssertEqual(HUDTuning.frontBandPortrait, 0)
    }

    func testFrontParkCornersAreOutsideTheRails() throws {
        let size = CGSize(width: 402, height: 874)
        GameCamera.configureRoom(count: 3)
        let rf = try XCTUnwrap(GameCamera.refreshRoam(aspect: Float(size.width / size.height)))
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        for c in rf.extremeCorners.prefix(2) {
            let p = Silhouette.project([SIMD3(c.x, 0, c.y)], viewProj: cam.viewProj, size: size)[0]
            for r in rects(size) { XCTAssertFalse(r.contains(p), "front corner foot point \(p) in a rail") }
        }
    }
}
