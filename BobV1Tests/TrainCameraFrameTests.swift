//
//  TrainCameraFrameTests.swift
//  While the Train card is up the close-up camera keeps the WHOLE trained Jelbie (head top, feet, both sides) inside the screen area the card leaves free:
//  above the card in portrait, left of it in landscape (r1023-polish). Reduce Motion = the blend is instant, so the test reads the final pose.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TrainCameraFrameTests: XCTestCase {
    override func tearDown() { GameCamera.trainFrame = nil; GameCamera.trainInstant = false; super.tearDown() }

    /// Screen fractions (0...1, y down) of the body's extremes with the camera at focus 1.
    private func extremes(aspect: Float) -> (minX: Float, maxX: Float, minY: Float, maxY: Float) {
        let cam = GameCamera.camera(aspect: aspect, focus: 1)
        func scr(_ p: SIMD3<Float>) -> SIMD2<Float> { let q = cam.viewProj * SIMD4(p, 1); return SIMD2(q.x / q.w * 0.5 + 0.5, 0.5 - q.y / q.w * 0.5) }
        let s = GameCamera.callSpot, R = BobShape.R, H = BobShape.H
        let pts = [scr(SIMD3(s.x - R, 0.45 * H, s.y)), scr(SIMD3(s.x + R, 0.45 * H, s.y)), scr(SIMD3(s.x, H, s.y)), scr(SIMD3(s.x, 0, s.y))]
        return (pts.map(\.x).min()!, pts.map(\.x).max()!, pts.map(\.y).min()!, pts.map(\.y).max()!)
    }

    func testPortraitJelbieSitsAboveTheCard() {
        GameCamera.trainInstant = true
        let aspect: Float = 402 / 874
        let normal = extremes(aspect: aspect)
        let frame = GameCamera.TrainFrame(minX: 0.04, maxX: 0.96, minY: 0.14, maxY: 0.60)
        XCTAssertGreaterThan(normal.maxY, frame.maxY, "without the frame the feet are behind the card (the bug)")
        GameCamera.trainFrame = frame
        let e = extremes(aspect: aspect)
        XCTAssertGreaterThanOrEqual(e.minY, frame.minY - 0.005, "head clear of the top bar")
        XCTAssertLessThanOrEqual(e.maxY, frame.maxY + 0.005, "feet above the card")
        XCTAssertGreaterThanOrEqual(e.minX, frame.minX - 0.005); XCTAssertLessThanOrEqual(e.maxX, frame.maxX + 0.005)
    }

    func testLandscapeJelbieSitsLeftOfTheCard() {
        GameCamera.trainInstant = true
        let aspect: Float = 874 / 402
        let frame = GameCamera.TrainFrame(minX: 72 / 874, maxX: 494 / 874, minY: 0.14, maxY: 0.95)
        GameCamera.trainFrame = nil
        let normal = extremes(aspect: aspect)
        XCTAssertGreaterThan(normal.maxX, frame.maxX, "without the frame he is partly behind the card (the bug)")
        GameCamera.trainFrame = frame
        let e = extremes(aspect: aspect)
        XCTAssertGreaterThanOrEqual(e.minX, frame.minX - 0.005); XCTAssertLessThanOrEqual(e.maxX, frame.maxX + 0.005, "all of him left of the card")
        XCTAssertGreaterThanOrEqual(e.minY, frame.minY - 0.005); XCTAssertLessThanOrEqual(e.maxY, frame.maxY + 0.005)
    }

    func testNoFrameLeavesTheNormalCloseUpAlone() {
        let aspect: Float = 402 / 874
        GameCamera.trainFrame = nil
        let a = GameCamera.camera(aspect: aspect, focus: 1)
        GameCamera.trainFrame = .init(minX: 0, maxX: 1, minY: 0, maxY: 1)
        GameCamera.trainFrame = nil
        XCTAssertEqual(GameCamera.camera(aspect: aspect, focus: 1).viewProj, a.viewProj)
    }
}
