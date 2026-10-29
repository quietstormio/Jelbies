//
//  VolleyViewTests.swift
//  Jelly Volleyball's behind-the-team camera: the thumb / swipe -> court mapping (up = toward the net, right = +z), the screen layout of the court on a portrait and a
//  landscape phone (your Jelbies at the bottom, the net across the middle, the opponents above it, everything inside the frame, with the camera's drift too) and the
//  rest heading that faces the net.
//

import XCTest
import simd
@testable import BobV1

final class VolleyViewTests: XCTestCase {
    override func setUp() { super.setUp(); GameCamera.configureBeach(); GameCamera.beachNudge = 0 }
    override func tearDown() { GameCamera.beachNudge = 0; GameCamera.endBeach(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); super.tearDown() }

    func testStickMapsThumbToTheCourt() {
        XCTAssertEqual(VolleyView.stick(right: 0, down: -1), SIMD2(1, 0))          // up: toward the net (+x)
        XCTAssertEqual(VolleyView.stick(right: 0, down: 1), SIMD2(-1, 0))          // down: back toward your baseline
        XCTAssertEqual(VolleyView.stick(right: 1, down: 0), SIMD2(0, 1))           // right: +z, the screen's right
        XCTAssertEqual(VolleyView.stick(right: -1, down: 0), SIMD2(0, -1))
    }

    func testSwipeAimsDeepUpAndSideways() {
        XCTAssertEqual(VolleyView.aim(right: 0, down: -1), SIMD2(1, 0))            // up: deep
        XCTAssertEqual(VolleyView.aim(right: 0, down: 1), SIMD2(-1, 0))            // down: short
        XCTAssertEqual(VolleyView.aim(right: 1, down: 0), SIMD2(0, 1))
    }

    /// The sim's stick through to the wish: up on the screen walks the controlled Jelbie toward the net, right walks him to the screen's right.
    func testStickDrivesTheControlledJelbie() {
        var sim = VolleySim(mode: .match(.sandcastle), mine: [VolleyStats(), VolleyStats()], seed: 5, firstServe: 1)
        sim.autoMove = false
        let p0 = sim.players[sim.controlled]
        sim.setStick(VolleyView.stick(right: 0, down: -1))
        sim.tick(dt: 1 / 60)
        XCTAssertGreaterThan(sim.players[sim.controlled].wantX, p0.x)
        sim.setStick(VolleyView.stick(right: 1, down: 0))
        sim.tick(dt: 1 / 60)
        XCTAssertGreaterThan(sim.players[sim.controlled].wantZ, p0.z)
    }

    func testRestHeadingFacesTheNet() {
        // yaw is measured from +z toward +x: your team (x < 0, side +1) faces +x, the opponents (side -1) face -x, the camera
        XCTAssertEqual(sinf(1 * VolleyTuning.restYaw), 1, accuracy: 1e-5)
        XCTAssertEqual(sinf(-1 * VolleyTuning.restYaw), -1, accuracy: 1e-5)
    }

    private let sizes: [(String, CGSize)] = [("portrait Pro Max", CGSize(width: 440, height: 956)), ("portrait SE", CGSize(width: 375, height: 667)),
                                              ("landscape Pro Max", CGSize(width: 956, height: 440)), ("landscape SE", CGSize(width: 667, height: 375))]

    private func pt(_ x: Float, _ z: Float, _ y: Float = 0, _ size: CGSize) -> CGPoint {
        _ = GameCamera.camera(aspect: Float(size.width / size.height))
        return GameCamera.screenPoint(floor: SIMD2(x, z), y: y, size: size) ?? CGPoint(x: -1e6, y: -1e6)
    }

    func testCourtReadsFromBehindOnEveryPhone() {
        for (name, size) in sizes {
            let near = pt(VolleyTuning.startX[0], 0, 0, size), far = pt(VolleyTuning.startX[2], 0, 0, size), net = pt(0, 0, 0, size)
            XCTAssertGreaterThan(near.y, net.y, name); XCTAssertGreaterThan(net.y, far.y, name)          // your side at the bottom, theirs above the net
            XCTAssertGreaterThan(pt(0, 1, 0, size).x, pt(0, -1, 0, size).x, name)                         // +z is the screen's right
            XCTAssertGreaterThan(near.y, size.height * 0.6, name)                                         // your Jelbies sit low
            XCTAssertLessThan(far.y, size.height * 0.65, name)                                            // theirs is above the middle band
            XCTAssertGreaterThan(near.y - far.y, size.height * 0.1, name)                                  // and the court is not squashed into a thin band
            XCTAssertEqual(near.x, size.width / 2, accuracy: 2, name)                                     // the court is centred
        }
    }

    func testEverythingStaysInFrameEvenWithTheDrift() {
        for (name, size) in sizes {
            for nudge: Float in [-0.2, 0, 0.2] {
                GameCamera.beachNudge = nudge
                // the players at the edges of their reach, a ball going out at the sides, and the ball at its highest over each baseline
                var spots: [(Float, Float, Float)] = []
                for x in [Float(-VolleyTuning.backX), -VolleyTuning.netMargin, VolleyTuning.netMargin, VolleyTuning.backX] {
                    for z in [-VolleyTuning.zLimit - 0.6, VolleyTuning.zLimit + 0.6] { spots.append((x, z, 0)); spots.append((x, z, VolleyTuning.bodyTop)) }
                }
                for x in [Float(-3.4), 3.4] { spots.append((x, 0, 3.8)); spots.append((x, VolleyTuning.outZ, 0.3)); spots.append((x, -VolleyTuning.outZ, 0.3)) }
                for (x, z, y) in spots {
                    let p = pt(x, z, y, size)
                    XCTAssertTrue(p.x > 0 && p.x < size.width && p.y > 0 && p.y < size.height, "\(name) nudge \(nudge): (\(x), \(z), \(y)) -> \(p)")
                }
            }
        }
    }

    func testTheDriftMovesTheViewAcrossTheCourtOnly() {
        let size = sizes[0].1
        let a = pt(0, 0, 0, size)
        GameCamera.beachNudge = 0.2
        let b = pt(0, 0, 0, size)
        XCTAssertLessThan(b.x, a.x)          // the camera slid to the right (+z), so the court slides left
        XCTAssertEqual(b.y, a.y, accuracy: 1.0)
    }
}
