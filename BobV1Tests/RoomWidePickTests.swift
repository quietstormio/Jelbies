//
//  RoomWidePickTests.swift
//  Default wide portrait room (W2 + lift): every Jelly's body and thought-bubble anchor stay on screen, and a tap at a Jelly's projected centre
//  unprojects to a ray through him (what touch picking relies on); landscape and one Jelly keep the old pose.
//

import XCTest
import simd
@testable import BobV1

final class RoomWidePickTests: XCTestCase {
    override func tearDown() { GameCamera.configureRoom(count: 1); super.tearDown() }

    func testPortraitWideKeepsJelliesPickableAndBubbleOnScreen() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let size = CGSize(width: 440, height: 956)
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let spots: [SIMD2<Float>] = [SIMD2(-2.0, 3.0), SIMD2(2.0, 3.0), SIMD2(0, -2.0), SIMD2(0, 0.8)]
        for s in spots {
            let c = SIMD3<Float>(s.x, 0.7, s.y)
            guard let p = ThoughtBubbleView.project(c, size: size, focus: 0) else { return XCTFail("behind camera") }
            XCTAssertTrue(p.x > 20 && p.x < size.width - 20 && p.y > 120 && p.y < size.height - 150, "centre off screen \(s) -> \(p)")
            let head = ThoughtBubbleView.project(SIMD3(s.x, 1.6, s.y), size: size, focus: 0)!
            let cloud = ThoughtBubbleView.cloudCenter(head: head)
            XCTAssertTrue(cloud.x > ThoughtBubbleView.radius && cloud.x < size.width - ThoughtBubbleView.radius && cloud.y > ThoughtBubbleView.radius, "bubble off screen \(s) -> \(cloud)")
            let ndc = SIMD2<Float>(Float(p.x / size.width) * 2 - 1, 1 - Float(p.y / size.height) * 2)
            let ray = unproject(ndc: ndc, invViewProj: cam.invViewProj)
            let d = simd_normalize(ray.d), t = simd_dot(c - ray.o, d)
            XCTAssertLessThan(simd_length(c - (ray.o + d * t)), 0.05)
            let edge = ThoughtBubbleView.project(SIMD3(s.x + 0.8, 0.7, s.y), size: size, focus: 0)!
            XCTAssertGreaterThan(abs(edge.x - p.x) * 2, 60, "too small to touch at \(s)")
        }
    }

    func testLandscapeAndOneJellyKeepPose() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let a = GameCamera.roomPose(.A)
        _ = GameCamera.camera(aspect: 2.1)
        XCTAssertEqual(GameCamera.eye, a.eye); XCTAssertEqual(GameCamera.target, a.target)
        GameCamera.configureRoom(count: 1, option: .current)          // (the explicit old close pose is still available)
        _ = GameCamera.camera(aspect: 0.46)
        XCTAssertEqual(GameCamera.eye, GameCamera.baseEye)
    }

    /// 2026-11-11: the wide room is the home view at every Jelbie count: one Jelbie gets exactly the camera pose and the roam rectangle of two and three.
    func testHomeCameraAndRoamAreTheSameForOneTwoThree() {
        func snapshot(_ n: Int, _ aspect: Float) -> [Float] {
            GameCamera.configureRoom(count: n)
            _ = GameCamera.camera(aspect: aspect)
            let f = GameCamera.refreshRoam(aspect: aspect)
            let r = GameCamera.roamRect, w = GameCamera.roamRectWide
            return [GameCamera.eye.x, GameCamera.eye.y, GameCamera.eye.z, GameCamera.target.x, GameCamera.target.y, GameCamera.target.z, r.min.x, r.min.y, r.max.x, r.max.y, w.min.x, w.min.y, w.max.x, w.max.y,
                    GameCamera.walkMaxZ, GameCamera.arenaCenter.x, GameCamera.arenaCenter.y, GameCamera.arenaRadius, f?.maxZ ?? -99, f?.minZ ?? -99, Float(f?.zs.count ?? -1)]
        }
        for aspect: Float in [440.0 / 956.0, 0.75, 1.33, 2.17] {
            let one = snapshot(1, aspect)
            XCTAssertEqual(one, snapshot(2, aspect), "1 vs 2 at \(aspect)")
            XCTAssertEqual(one, snapshot(3, aspect), "1 vs 3 at \(aspect)")
        }
        _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1)
        let wide = GameCamera.roomPose(.A)
        XCTAssertEqual(GameCamera.roomEye, wide.eye, "one Jelbie is no longer the base pose")
        XCTAssertNotEqual(GameCamera.roomEye, GameCamera.baseEye)
        XCTAssertEqual(GameCamera.roomWideScale, GameCamera.wideScale(2))
    }
}
