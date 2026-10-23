//
//  HUDLayoutTests.swift
//  The side rails stay clear of the front row of Jelbies (the old portrait overlap), portrait and landscape.
//

import XCTest
@testable import BobV1

@MainActor
final class HUDLayoutTests: XCTestCase {
    override func tearDown() { GameCamera.clearRoam(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    private func check(_ size: CGSize, safeBottom: CGFloat, compact: Bool) {
        let lift = HUDLayout.lift(size: size, safeBottom: safeBottom, compact: compact)
        let railBottom = size.height - safeBottom - 8 - lift          // (the HUD has 8 pt of vertical padding)
        let aspect = Float(size.width / size.height)
        let left: ClosedRange<CGFloat> = 16 ... 16 + 64
        let right: ClosedRange<CGFloat> = size.width - 16 - 64 - 10 - 56 ... size.width - 16
        for (name, r) in [("left rail", left), ("right rail", right)] {
            let top = HUDLayout.frontBandTop(aspect: aspect, size: size, xRange: r)
            XCTAssertGreaterThanOrEqual(top, railBottom + 4, "\(name) at \(size): front row top \(top) vs rail bottom \(railBottom) (lift \(lift))")
        }
    }

    func testPortraitRailsClearTheFrontRow() {
        check(CGSize(width: 402, height: 874), safeBottom: 34, compact: false)
        check(CGSize(width: 393, height: 852), safeBottom: 34, compact: false)
        check(CGSize(width: 440, height: 956), safeBottom: 34, compact: false)
    }

    func testLandscapeRailsClearTheFrontRow() {
        check(CGSize(width: 874, height: 402), safeBottom: 21, compact: true)
        check(CGSize(width: 956, height: 440), safeBottom: 21, compact: true)
    }

    func testLiftIsZeroInLandscapeAndPositiveInPortrait() {
        XCTAssertEqual(HUDLayout.lift(size: CGSize(width: 874, height: 402), safeBottom: 21, compact: true), HUDTuning.frontBandLandscape * 402)
        XCTAssertGreaterThan(HUDLayout.lift(size: CGSize(width: 402, height: 874), safeBottom: 34, compact: false), 0)
    }
}
