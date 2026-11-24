//
//  GlitchProbeTests.swift
//  glitch-hunt-r1: the dev glitch probe's core (Melon/GlitchProbe.swift) flags a jump, a yaw snap, a pose pop, a planted-foot slide and a blend snap, stays quiet on smooth motion,
//  divides by the steps run, and tags a deliberate move (SoftBody.teleport / shift) instead of reporting it as a plain jump.
//

#if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
import XCTest
import simd
@testable import BobV1

final class GlitchProbeTests: XCTestCase {
    private func sample(_ c: SIMD3<Float> = .zero, yaw: Float = 0, serial: Int = 0, arm: SIMD3<Float> = SIMD3(0.4, 0.5, 0), feet: [(minY: Float, xz: SIMD2<Float>)]? = nil, blends: [Float] = [1, 1]) -> GlitchSample {
        GlitchSample(centroid: c, rotation: simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)), tilt: 0, moveSerial: serial, brainYaw: yaw,
                     local: [SIMD3(0, 0.5, 0.3), arm], group: [GlitchGroup.body.rawValue, GlitchGroup.arm.rawValue], feet: feet, blends: blends, footMorph: [0, 1])
    }

    func testSmoothMotionIsQuiet() {
        var core = GlitchCore()
        for i in 0..<120 {
            let t = Float(i) / 60
            let ev = core.observe(sample(SIMD3(t * 1.5, 0, 0), yaw: t * 2, arm: SIMD3(0.4, 0.5 + 0.05 * sinf(t * 6), 0), feet: [(0, SIMD2(0, 0)), (0.05, SIMD2(0.2, 0))]), steps: 1)
            XCTAssertTrue(ev.isEmpty, "frame \(i): \(ev.map(\.kind))")
        }
    }

    func testEachKindIsFlagged() {
        var core = GlitchCore()
        _ = core.observe(sample(feet: [(0, SIMD2(0, 0)), (0, SIMD2(0.2, 0))]), steps: 1)
        _ = core.observe(sample(feet: [(0, SIMD2(0, 0)), (0, SIMD2(0.2, 0))]), steps: 1)
        let ev = core.observe(sample(SIMD3(0.2, 0, 0), yaw: 1.0, arm: SIMD3(0.4, 0.7, 0), feet: [(0, SIMD2(0.03, 0)), (0, SIMD2(0.2, 0))], blends: [0, 1]), steps: 1)
        let kinds = Set(ev.map(\.kind))
        XCTAssertEqual(kinds, ["jump", "yaw", "pose", "slide", "blend"])
        XCTAssertEqual(ev.first { $0.kind == "pose" }?.detail, "part=arm")
    }

    func testStepsDivideAndZeroStepsKeepTheSample() {
        var core = GlitchCore()
        _ = core.observe(sample(), steps: 1); _ = core.observe(sample(), steps: 1)
        XCTAssertTrue(core.observe(sample(SIMD3(0.5, 0, 0)), steps: 0).isEmpty)
        XCTAssertTrue(core.observe(sample(SIMD3(0.07, 0, 0)), steps: 2).isEmpty, "0.07 u over two steps is 0.035 a step: under the 0.04 logging bar")
    }

    func testSteadyRunAndSpinAreQuiet() {
        var core = GlitchCore()
        for i in 0..<60 {          // 6 u/s and 600 deg/s: fast, but smooth
            let ev = core.observe(sample(SIMD3(Float(i) * 0.1, 0, 0), yaw: Float(i) * 0.17), steps: 1)
            XCTAssertTrue(ev.isEmpty, "frame \(i): \(ev.map(\.kind))")
        }
    }

    func testDeliberateMoveIsTagged() {
        var core = GlitchCore()
        _ = core.observe(sample(), steps: 1); _ = core.observe(sample(), steps: 1)
        let ev = core.observe(sample(SIMD3(3, 0, 0), serial: 1, arm: SIMD3(1, 1, 1)), steps: 1)
        XCTAssertEqual(ev.map(\.kind), ["jump"])
        XCTAssertTrue(ev[0].detail.hasPrefix("tele=1"))
    }

    func testBurstCollapsesToOneEventWithItsLargestSize() {
        var b = GlitchBurst()
        b.add(GlitchEvent(kind: "yaw", size: 30, perStep: 30, detail: ""), who: "0", ctx: "a", now: 1.0)
        b.add(GlitchEvent(kind: "yaw", size: 50, perStep: 50, detail: ""), who: "0", ctx: "b", now: 1.1)
        XCTAssertTrue(b.flush(now: 1.2).isEmpty)
        let out = b.flush(now: 2)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].ev.perStep, 50); XCTAssertEqual(out[0].n, 2); XCTAssertEqual(out[0].ctx, "b")
    }
}
#endif
