//
//  ParkFramePoseTests.swift
//  The park's camera pose (eye, target) per aspect: portrait (and the home room) must stay exactly as they were; the landscape park is pulled in (GameCamera.parkLandscapeFrame).
//

import XCTest
import simd
@testable import BobV1

final class ParkFramePoseTests: XCTestCase {
    override func tearDown() { GameCamera.endPark(count: 1); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); super.tearDown() }

    private func park(_ aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        GameCamera.configurePark()
        _ = GameCamera.camera(aspect: aspect)
        return (GameCamera.eye, GameCamera.target)
    }
    private func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ msg: String, tol: Float = 2e-3) {
        XCTAssertLessThan(simd_distance(a, b), tol, "\(msg): \(a) vs \(b)")
    }

    func testPortraitParkAndHomePosesAreUnchanged() {
        let p = park(440.0 / 956.0)
        close(p.eye, SIMD3(0, 23.8426, 28.526), "portrait park eye"); close(p.target, SIMD3(0, 3.7054, -0.5286), "portrait park target")
        let q = park(393.0 / 852.0)          // another phone portrait: the same pull-free path
        XCTAssertEqual(GameCamera.parkLandscapeFrame(aspect: 393.0 / 852.0).pull, 0); XCTAssertEqual(GameCamera.parkLandscapeFrame(aspect: 393.0 / 852.0).lower, 0)
        XCTAssertEqual(q.eye.x, 0)
        // the home room (2026-11-11): one Jelbie has the same wide view as three, in both orientations (the old close pose is `option: .current`)
        for a in [Float(440.0 / 956.0), 2.17] {
            GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: a)          // (out of the park first: its pan is not part of the home view)
            let wide = (GameCamera.eye, GameCamera.target)
            GameCamera.endPark(count: 1); GameCamera.configureRoom(count: 1)
            _ = GameCamera.camera(aspect: a)
            XCTAssertEqual(GameCamera.eye, wide.0); XCTAssertEqual(GameCamera.target, wide.1)
            XCTAssertNotEqual(GameCamera.eye, GameCamera.baseEye)
        }
    }

    func testLandscapeParkIsPulledIn() {
        let (pull, lower) = GameCamera.parkLandscapeFrame(aspect: 852.0 / 393.0)
        XCTAssertEqual(pull, 0.35, accuracy: 1e-6)
        XCTAssertEqual(lower, 12 * .pi / 180, accuracy: 1e-6)
        let pose = park(852.0 / 393.0)
        print("[parkframe] landscape eye \(pose.eye) target \(pose.target)")
        close(pose.eye, SIMD3(0, 5.4624, 14.2822), "landscape park eye"); close(pose.target, SIMD3(0, -0.0855, 1.0358), "landscape park target")
        let ipad = park(4.0 / 3.0)
        close(ipad.eye, SIMD3(0, 5.4624, 14.2822), "4:3 park eye"); close(ipad.target, SIMD3(0, -0.0855, 1.0358), "4:3 park target")
        // the pull is blended: nothing at aspect <= 1.0, full from 1.2
        XCTAssertEqual(GameCamera.parkLandscapeFrame(aspect: 1.0).pull, 0)
        XCTAssertEqual(GameCamera.parkLandscapeFrame(aspect: 0.46).pull, 0)
        XCTAssertEqual(GameCamera.parkLandscapeFrame(aspect: 1.2).pull, GameCamera.parkLandscapePull, accuracy: 1e-6)
        XCTAssertEqual(GameCamera.parkLandscapeFrame(aspect: 1.2).lower, GameCamera.parkLandscapeLower, accuracy: 1e-6)
        let mid = GameCamera.parkLandscapeFrame(aspect: 1.1).pull
        XCTAssertTrue(mid > 0 && mid < GameCamera.parkLandscapePull)
    }
}
