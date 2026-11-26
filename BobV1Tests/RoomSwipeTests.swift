//
//  RoomSwipeTests.swift
//  The room swipe's maths (Room/RoomSwipe.swift): the rubber band, the 4 s idle + 0.8 s ease home, the fast snap-in when a close-up turns it off.
//

import XCTest
import simd
@testable import BobV1

final class RoomSwipeTests: XCTestCase {
    override func setUp() { RoomSwipe.yaw = 0; RoomSwipe.pitch = 0; RoomSwipe.end(now: 0) }

    private func run(_ seconds: Double, from t0: Double, allowed: Bool = true) -> Double {
        var t = t0
        for _ in 0..<Int(seconds * 60) { t += 1.0 / 60; RoomSwipe.tick(dt: 1.0 / 60, now: t, allowed: allowed) }
        return t
    }

    func testBandStaysNearTheLimit() {
        XCTAssertEqual(RoomSwipe.band(0.1), 0.1, accuracy: 1e-6)          // (inside the 10 deg limit)
        XCTAssertLessThan(RoomSwipe.band(5), RoomSwipe.limit + RoomSwipe.stretch + 1e-4)
        XCTAssertGreaterThan(RoomSwipe.band(0.6), RoomSwipe.limit)
        XCTAssertEqual(RoomSwipe.band(-0.6), -RoomSwipe.band(0.6), accuracy: 1e-6)
    }

    func testDragThenIdleEasesHomeInAboutFourPointEightSeconds() {
        var t = 100.0
        RoomSwipe.begin(now: t)
        for _ in 0..<40 { t += 1.0 / 60; RoomSwipe.drag(dx: -12, dt: 1.0 / 60, now: t) }          // a long swipe left
        RoomSwipe.end(now: t + 0.2)
        XCTAssertGreaterThan(abs(RoomSwipe.yaw), 0.15)
        XCTAssertLessThanOrEqual(abs(RoomSwipe.yaw), RoomSwipe.limit + RoomSwipe.stretch + 1e-4)
        t = run(3.0, from: t + 0.2)
        XCTAssertNotEqual(RoomSwipe.yaw, 0, "still turned before the 4 s are up")
        t = run(2.5, from: t)
        XCTAssertEqual(RoomSwipe.yaw, 0, accuracy: 1e-5, "home after 4 s + 0.8 s")
    }

    func testTurnedOffSnapsBackFast() {
        var t = 200.0
        RoomSwipe.begin(now: t)
        for _ in 0..<20 { t += 1.0 / 60; RoomSwipe.drag(dx: 12, dt: 1.0 / 60, now: t) }
        RoomSwipe.end(now: t)
        XCTAssertNotEqual(RoomSwipe.yaw, 0)
        _ = run(0.6, from: t, allowed: false)
        XCTAssertEqual(RoomSwipe.yaw, 0, accuracy: 0.003)
    }

    func testPitchStaysInItsBandAndKeepsDistance() {
        var t = 300.0
        RoomSwipe.begin(now: t)
        for _ in 0..<80 { t += 1.0 / 60; RoomSwipe.drag(dx: -12, dy: 15, dt: 1.0 / 60, now: t) }          // a long diagonal drag, far past both limits
        XCTAssertLessThanOrEqual(abs(RoomSwipe.pitch), RoomSwipe.pitchLimit + RoomSwipe.pitchStretch + 1e-4)
        XCTAssertGreaterThan(RoomSwipe.pitch, RoomSwipe.pitchLimit * 0.9)
        XCTAssertLessThanOrEqual(abs(RoomSwipe.yaw), RoomSwipe.limit + RoomSwipe.stretch + 1e-4)
        let tgt = SIMD3<Float>(0, 1, 0), eye = SIMD3<Float>(0, 6, 9)
        let e2 = RoomSwipe.apply(eye: eye, target: tgt)
        XCTAssertEqual(simd_length(e2 - tgt), simd_length(eye - tgt), accuracy: 1e-3)
        XCTAssertGreaterThan(e2.y, eye.y)          // finger down: the eye rises
    }

    func testPitchAndYawEaseHomeTogether() {
        var t = 400.0
        RoomSwipe.begin(now: t)
        for _ in 0..<30 { t += 1.0 / 60; RoomSwipe.drag(dx: 10, dy: -10, dt: 1.0 / 60, now: t) }
        RoomSwipe.end(now: t + 0.2)
        XCTAssertLessThan(RoomSwipe.pitch, -0.02)
        t = run(3.0, from: t + 0.2)
        XCTAssertNotEqual(RoomSwipe.pitch, 0, "still tipped before the 4 s are up")
        t = run(2.5, from: t)
        XCTAssertEqual(RoomSwipe.pitch, 0, accuracy: 1e-5)
        XCTAssertEqual(RoomSwipe.yaw, 0, accuracy: 1e-5)
    }

    func testVerticalOnlyDragTipsWithoutTurning() {
        var t = 500.0
        RoomSwipe.begin(now: t)
        for _ in 0..<20 { t += 1.0 / 60; RoomSwipe.drag(dx: 0, dy: 6, dt: 1.0 / 60, now: t) }
        XCTAssertEqual(RoomSwipe.yaw, 0, accuracy: 1e-6)
        XCTAssertGreaterThan(RoomSwipe.pitch, 0.02)
    }

    func testTurnedOffSnapsPitchBackFast() {
        var t = 600.0
        RoomSwipe.begin(now: t)
        for _ in 0..<20 { t += 1.0 / 60; RoomSwipe.drag(dx: 0, dy: 12, dt: 1.0 / 60, now: t) }
        RoomSwipe.end(now: t)
        XCTAssertNotEqual(RoomSwipe.pitch, 0)
        _ = run(0.6, from: t, allowed: false)
        XCTAssertEqual(RoomSwipe.pitch, 0, accuracy: 0.003)
    }

    func testUpPitchShrinksToNothingAtTheYawLimit() {
        let up = -RoomSwipe.pitchLimit
        XCTAssertEqual(RoomSwipe.effectivePitch(yaw: 0, pitch: up), up, accuracy: 1e-6)
        XCTAssertEqual(RoomSwipe.effectivePitch(yaw: RoomSwipe.limit / 2, pitch: up), up / 2, accuracy: 1e-5)
        XCTAssertEqual(RoomSwipe.effectivePitch(yaw: -RoomSwipe.limit, pitch: up), 0, accuracy: 1e-6)
        XCTAssertEqual(RoomSwipe.effectivePitch(yaw: RoomSwipe.limit + RoomSwipe.stretch, pitch: up), 0, accuracy: 1e-6)
        let down = RoomSwipe.pitchLimit
        XCTAssertEqual(RoomSwipe.effectivePitch(yaw: RoomSwipe.limit, pitch: down), down, accuracy: 1e-6)
    }
}
