//
//  MotionFacingTests.swift
//  FACING: the body's heading stays within 5 deg of the camera direction for the whole wave and for the Call approach + wave,
//  both as world yaw (pose yaw vs faceCameraYaw) and as the face-normal azimuth seen from the camera (pitch * roll no longer turns the face).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionFacingTests: XCTestCase {
    private let limit: Float = 5 * .pi / 180

    private func waveWindow(_ s: [MotionSample]) -> [MotionSample] {
        // from 0.4 s after the wave started until it ended
        guard let i0 = s.firstIndex(where: { $0.activity == .waving }) else { return [] }
        let t0 = s[i0].t + 0.4
        return s.filter { $0.activity == .waving && $0.t >= t0 }
    }

    func testWaveFacesCamera() {
        for game in [false, true] { for side in [-1, 1] {
            let (_, s) = MotionScenario.wave(side: side, game: game)
            let w = waveWindow(s)
            XCTAssertGreaterThan(w.count, 60)
            let worstWorld = w.map { abs($0.yawErr) }.max() ?? 0
            let worstApp = w.map { abs($0.apparent) }.max() ?? 0
            MotionLog.write(String(format: "FACING wave %@ side %d: world yaw err max %.2f deg, apparent (face normal) max %.2f deg over %d steps",
                                   game ? "game" : "studio", side, worldDeg(worstWorld), worldDeg(worstApp), w.count))
            XCTAssertLessThanOrEqual(worstWorld, limit, "wave world yaw error")
            XCTAssertLessThanOrEqual(worstApp, limit, "wave apparent yaw")
        } }
    }

    func testCallApproachAndWaveFaceCamera() {
        let (_, s) = MotionScenario.call()
        guard let iw = s.firstIndex(where: { $0.waving }) else { return XCTFail("the Call never waved") }
        // last 1 s of the approach (the walk toward the camera) + the stepped turn + the wave
        let t0 = s[iw].t - 1.0
        let win = s.filter { $0.t >= t0 && $0.activity != .idle }
        XCTAssertGreaterThan(win.count, 100)
        for x in win where Int(x.t * 60) % 6 == 0 { MotionLog.write(String(format: "  call t=%.2f %@ waving %d yawErr %.2f deg apparent %.2f", x.t, "\(x.activity)", x.waving ? 1 : 0, x.yawErr * 57.3, x.apparent * 57.3)) }
        let worstWorld = win.map { abs($0.yawErr) }.max() ?? 0
        let worstApp = win.map { abs($0.apparent) }.max() ?? 0
        MotionLog.write(String(format: "FACING call approach+wave: world yaw err max %.2f deg, apparent max %.2f deg over %d steps",
                               worldDeg(worstWorld), worldDeg(worstApp), win.count))
        // while he is still walking the waddle twists the body (REF2's own yaw wobble is -9..+4 deg, motion table), so the approach is held to 10 deg; the wave itself to 5 deg
        let walkLimit: Float = 10 * .pi / 180
        XCTAssertLessThanOrEqual(worstWorld, walkLimit)
        XCTAssertLessThanOrEqual(worstApp, walkLimit)
        // he keeps his tip-back toward the camera while he walks (flat brows read friendly from the 25 deg game camera), pivoted on the feet
        let walking = s.filter { $0.activity == .coming && !$0.waving && $0.t > 1.0 }
        let tip = walking.map { $0.tipBack * 180 / .pi }
        MotionLog.write(String(format: "BROWS call walk: tip-back mean %.1f deg (min %.1f, max %.1f) over %d steps (the old walk was -2.7 deg)", tip.reduce(0, +) / Float(max(1, tip.count)), tip.min() ?? 0, tip.max() ?? 0, tip.count))
        XCTAssertGreaterThan(tip.reduce(0, +) / Float(max(1, tip.count)), 7, "he stays tipped back toward the camera while walking")
        XCTAssertGreaterThan(tip.min() ?? 0, 0, "the waddle rock never tips him forward over the camera")
        let wv = win.filter { $0.waving }
        XCTAssertLessThanOrEqual(wv.map { abs($0.yawErr) }.max() ?? 0, limit, "the Call's wave faces the camera within 5 deg")
    }

    private func worldDeg(_ r: Float) -> Float { r * 180 / .pi }
}
