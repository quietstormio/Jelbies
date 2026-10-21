//
//  CameraAspectTests.swift
//  The Jellies must never look stretched on any phone: for every current iPhone size (portrait and landscape, 2x and 3x), a sphere at the room
//  centre projects to a circle in drawable pixels (within 1%), and the room camera's pose is exactly the expected framing (the W2 wide pose
//  in portrait, the unwidened room pose in landscape, `baseEye` for one Jelly). Guards the 2026-10-20 Xcode 27.1 / iOS 27 upgrade.
//

import XCTest
import simd
@testable import BobV1

final class CameraAspectTests: XCTestCase {
    // (the projection aspect is process-wide state - Skinning reads GameCamera.aspect - so the default phone's is put back too, as FurnitureFitTests does;
    //  left at the last drawable's, the social walks of SocialTests ran a different seeded path and failed on the plain-walk overlap)
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); super.tearDown() }

    /// Point sizes of every current iPhone (and the SE as the squarest phone), with their native scale.
    static let phones: [(name: String, w: CGFloat, h: CGFloat, scale: CGFloat)] = [
        ("iPhone 17 Pro / 17 / 16 Pro", 402, 874, 3), ("iPhone 17 Pro Max / 16 Pro Max", 440, 956, 3), ("iPhone Air", 420, 912, 3),
        ("iPhone 17e / 16e", 390, 844, 3), ("iPhone 16", 393, 852, 3), ("iPhone 16 Plus", 430, 932, 3), ("iPhone SE", 375, 667, 2),
    ]
    /// Every drawable: portrait and landscape, in pixels (points x scale, as MTKView sizes its drawable).
    static var drawables: [(name: String, w: Int, h: Int)] {
        phones.flatMap { p in [(p.name + " portrait", Int(p.w * p.scale), Int(p.h * p.scale)), (p.name + " landscape", Int(p.h * p.scale), Int(p.w * p.scale))] }
    }

    /// The projected pixel extents (width, height) of a sphere of radius `r` at `c`: the sphere's silhouette along the camera's right and up axes.
    private func projectedExtents(_ cam: CameraState, centre c: SIMD3<Float>, r: Float, w: Int, h: Int) -> (width: Float, height: Float) {
        let fwd = cam.fwd, right = simd_normalize(simd_cross(fwd, SIMD3<Float>(0, 1, 0))), up = simd_normalize(simd_cross(right, fwd))
        func px(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let q = cam.viewProj * SIMD4<Float>(p, 1)
            return SIMD2((q.x / q.w * 0.5 + 0.5) * Float(w), (1 - (q.y / q.w * 0.5 + 0.5)) * Float(h))
        }
        let l = px(c - right * r), rr = px(c + right * r), b = px(c - up * r), t = px(c + up * r)
        return (simd_length(rr - l), simd_length(t - b))
    }

    func testSphereAtRoomCentreStaysCircularOnEveryPhone() {
        for count in [1, 3] {
            GameCamera.configureRoom(count: count, option: .A, wide: 2)
            for d in Self.drawables {
                let aspect = Float(d.w) / Float(d.h)
                let cam = GameCamera.camera(aspect: aspect)
                XCTAssertEqual(GameCamera.aspect, aspect, "projection aspect must be the drawable's (\(d.name))")
                for c in [SIMD3<Float>(0, 0.7, 0), SIMD3<Float>(0, 0.7, GameCamera.callSpot.y), SIMD3<Float>(-1.5, 0.7, 1)] {
                    let e = projectedExtents(cam, centre: c, r: 0.5, w: d.w, h: d.h)
                    XCTAssertEqual(e.width / e.height, 1, accuracy: 0.01, "\(count) Jellies, \(d.name) \(d.w)x\(d.h): sphere at \(c) is \(e.width) x \(e.height) px")
                    XCTAssertGreaterThan(e.width, 10, "\(d.name): sphere too small")
                }
            }
        }
    }

    /// The pose matches the framing the references were rendered with: portrait = room pose A pulled back x1.6 and lifted 1.5 (W2); landscape = pose A as is;
    /// one Jelly = `baseEye` everywhere.
    func testPoseIsTheExpectedFramingOnEveryPhone() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let a = GameCamera.roomPose(.A)
        let widePortrait = (eye: a.target + (a.eye - a.target) * 1.6 + SIMD3<Float>(0, 1.5, 0), target: a.target + SIMD3<Float>(0, 1.5, 0))
        for d in Self.drawables {
            let aspect = Float(d.w) / Float(d.h)
            _ = GameCamera.camera(aspect: aspect)
            let expected = aspect < 1 ? widePortrait : a
            XCTAssertLessThan(simd_distance(GameCamera.eye, expected.eye), 1e-3, "\(d.name): eye \(GameCamera.eye) expected \(expected.eye)")
            XCTAssertLessThan(simd_distance(GameCamera.target, expected.target), 1e-3, "\(d.name): target \(GameCamera.target) expected \(expected.target)")
            XCTAssertEqual(GameCamera.portraitAmount(aspect), aspect < 1 ? 1 : 0, "\(d.name): every phone is fully portrait or fully landscape")
        }
        GameCamera.configureRoom(count: 1)
        for d in Self.drawables {
            _ = GameCamera.camera(aspect: Float(d.w) / Float(d.h))
            XCTAssertEqual(GameCamera.eye, GameCamera.baseEye, d.name); XCTAssertEqual(GameCamera.target, GameCamera.baseTarget, d.name)
        }
    }

    /// The reference renders (603 x 1311, an iPhone 17 Pro screenshot at half size) and the live 17 Pro drawable (1206 x 2622) share one framing.
    func testReferenceRenderAndLiveDrawableAgree() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let ref = GameCamera.camera(aspect: 603.0 / 1311.0), refEye = GameCamera.eye
        let live = GameCamera.camera(aspect: 1206.0 / 2622.0)
        XCTAssertEqual(refEye, GameCamera.eye)
        for c in [SIMD3<Float>(0, 0.7, 0), SIMD3<Float>(2, 0, -2.6)] {
            let p = ref.viewProj * SIMD4<Float>(c, 1), q = live.viewProj * SIMD4<Float>(c, 1)
            XCTAssertEqual(p.x / p.w, q.x / q.w, accuracy: 1e-3); XCTAssertEqual(p.y / p.w, q.y / q.w, accuracy: 1e-3)
        }
    }
}
