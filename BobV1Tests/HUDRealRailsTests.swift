//
//  HUDRealRailsTests.swift
//  space-fix-r1: the roam floor's button cut-outs follow the REAL view size and the real button rectangles (`HUDLayout.phoneRails`, from the measured size + safe insets), not a 393 pt phone's fractions,
//  in portrait and landscape; and `GameCamera.constrain` keeps a body out from under a button with the floor's `railFree` spans, so a session's push cannot carry him there.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HUDRealRailsTests: XCTestCase {
    override func tearDown() {
        HUDLayout.measuredSize = .zero; HUDLayout.measuredInsets = .zero
        GameCamera.clearRoam(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// (window size in points, safe insets): an iPhone 17 Pro Max, 17 / 16, 8 / SE-like, in both orientations.
    private let phones: [(CGSize, UIEdgeInsets)] = [
        (CGSize(width: 440, height: 956), UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)),
        (CGSize(width: 402, height: 874), UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)),
        (CGSize(width: 393, height: 852), UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)),
        (CGSize(width: 375, height: 667), UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)),
        (CGSize(width: 956, height: 440), UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)),
        (CGSize(width: 874, height: 402), UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)),
        (CGSize(width: 667, height: 375), UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)),
    ]

    func testRectsAreTheRealButtons() {
        HUDLayout.measuredSize = CGSize(width: 440, height: 956); HUDLayout.measuredInsets = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        let r = HUDLayout.railRects(aspect: 440.0 / 956.0)
        XCTAssertEqual(r.count, 2)
        // left capsule: x 16...76 (+ 4 pt margin each side), its top 34 (safe) + 8 (padding) + 237.5 (4 rows, divider, padding) above the bottom edge
        XCTAssertEqual(r[0].minX * 440, 12, accuracy: 0.01); XCTAssertEqual(r[0].width * 440, 68, accuracy: 0.01)
        XCTAssertEqual(r[0].minY * 956, 956 - 34 - 8 - 237.5, accuracy: 0.01); XCTAssertEqual(r[0].maxY, 1, accuracy: 1e-6)
        // heart: 72 pt wide, 16 + 4 from the right edge, its top 34 + 8 + 72 + 4 above the bottom
        XCTAssertEqual(r[1].maxX * 440, 440 - 16 + 4, accuracy: 0.01)
        XCTAssertEqual(r[1].minY * 956, 956 - 34 - 8 - 72 - 4, accuracy: 0.01)
        // not measured: the old 393 pt rects, exactly as before
        HUDLayout.measuredSize = .zero; HUDLayout.measuredInsets = .zero
        XCTAssertEqual(HUDLayout.railRects(aspect: 0.46), HUDLayout.railRects)
    }

    /// Every spot the floor lets a body centre use has a body box clear of both real rectangles, and `constrain` returns such a spot from any push.
    func testNoBodyUnderTheRealButtonsAndConstrainKeepsItSo() throws {
        for (size, insets) in phones {
            HUDLayout.measuredSize = size; HUDLayout.measuredInsets = insets
            let aspect = Float(size.width / size.height)
            GameCamera.configureRoom(count: 3)
            let rf = try XCTUnwrap(GameCamera.refreshRoam(aspect: aspect))
            let cam = GameCamera.camera(aspect: aspect, gamePose: true)
            let rails = HUDLayout.railRects(aspect: aspect)
            XCTAssertEqual(rails.count, 2, "\(size): real rects in both orientations")
            func under(_ x: Float, _ z: Float) -> Bool { HUDLayout.bodyHitsRail(x: x, z: z, viewProj: cam.viewProj, size: size, rails: rails) }
            var spots = 0, pushedUnder = 0
            for (i, z) in rf.zs.enumerated() {
                for r in rf.free[i] { for x in stride(from: r.lowerBound, through: r.upperBound, by: 0.1) { spots += 1; XCTAssertFalse(under(x, z), "\(size): body at (\(x), \(z)) is under a button") } }
                // pushes: from every 0.2 across the row (and a little outside it), constrain lands on a spot with no button over the body (rows sit on the 0.25 grid: the check uses the row's own z)
                for px in stride(from: -rf.hw[i] - 0.5, through: rf.hw[i] + 0.5, by: 0.2) {
                    let q = GameCamera.constrain(SIMD3(px, 0, z), radius: 0.7)
                    if abs(q.z - z) < 1e-3, under(q.x, z) { pushedUnder += 1 }
                }
            }
            XCTAssertGreaterThan(spots, 100, "\(size)")
            XCTAssertEqual(pushedUnder, 0, "\(size): constrain never leaves a body under a button")
            XCTAssertGreaterThan(rf.area, 1)
        }
    }

    /// The cut-outs are not wider than the real buttons were measured to be: on the 440 pt phone the left rect is 68 pt wide, the old one 80 / 393 x 440 = 89.6 pt.
    func testTheRectIsNarrowerThanTheOldOneOnAWidePhone() {
        HUDLayout.measuredSize = CGSize(width: 440, height: 956); HUDLayout.measuredInsets = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        let real = HUDLayout.railRects(aspect: 440.0 / 956.0), old = HUDLayout.railRects
        XCTAssertLessThan(real[0].width * 440, old[0].width * 440)
    }
}
