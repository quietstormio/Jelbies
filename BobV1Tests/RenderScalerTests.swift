import XCTest
@testable import BobV1

/// Pure state-machine tests for the adaptive render scale and the 60 / 120 Hz governor.
final class RenderScalerTests: XCTestCase {
    private let dt = 1.0 / 60

    /// Runs `secs` of frames at a constant gpu time, returns every scale change.
    private func run(_ s: inout RenderScaler, secs: Double, gpu: Double, thermal: ProcessInfo.ThermalState = .nominal) -> [Double] {
        var out: [Double] = []
        var t = 0.0
        while t < secs { if let n = s.update(dt: dt, gpuMs: gpu, thermal: thermal) { out.append(n) }; t += dt }
        return out
    }

    func testLadderFromNative() {
        XCTAssertEqual(RenderScaler(native: 3).levels, [3, 2.5, 2, 1.67, 1.5, 1.33])
        XCTAssertEqual(RenderScaler(native: 2).levels, [2, 1.67, 1.5, 1.33])
        XCTAssertEqual(RenderScaler(native: 1).levels, [1])
    }

    func testUnderBudgetNeverChanges() {
        var s = RenderScaler(native: 3)
        XCTAssertEqual(run(&s, secs: 20, gpu: 7.5), [])
        XCTAssertEqual(s.scale, 3)
    }

    func testStepsDownAfterHalfSecondOverBudget() {
        var s = RenderScaler(native: 3)
        XCTAssertEqual(s.budgetMs, 1000.0 / 60 * 0.85, accuracy: 1e-9)
        XCTAssertEqual(run(&s, secs: 0.4, gpu: 30), [], "not yet")
        let ch = run(&s, secs: 0.3, gpu: 30)
        XCTAssertEqual(ch, [2.5])
    }

    func testKeepsStepping_andBottomsOutAtMin() {
        var s = RenderScaler(native: 3)
        let ch = run(&s, secs: 30, gpu: 74)
        XCTAssertEqual(ch, [2.5, 2, 1.67, 1.5, 1.33])
        XCTAssertEqual(s.scale, 1.33)
    }

    func testBriefSpikeDoesNotStepDown() {
        var s = RenderScaler(native: 3)
        for _ in 0..<5 {
            XCTAssertEqual(run(&s, secs: 0.3, gpu: 40), [])
            XCTAssertEqual(run(&s, secs: 0.5, gpu: 6), [])
        }
        XCTAssertEqual(s.scale, 3)
    }

    func testStepsUpAfterThreeSecondsComfortablyUnder() {
        var s = RenderScaler(native: 3)
        _ = run(&s, secs: 1, gpu: 30)                // down to 2.5 (and maybe further)
        let low = s.scale
        XCTAssertLessThan(low, 3)
        XCTAssertEqual(run(&s, secs: 2.5, gpu: 3), [], "needs ~3 s under budget")
        XCTAssertFalse(run(&s, secs: 1.5, gpu: 3).isEmpty)
        XCTAssertGreaterThan(s.scale, low)
    }

    func testNoStepUpWhenPredictedCostAtHigherScaleWouldBust() {
        var s = RenderScaler(native: 3)
        _ = run(&s, secs: 1, gpu: 30)
        let low = s.scale
        // 11 ms at this scale: under budget (14.2) but x(3/2.5)^2 = 15.8 would bust it -> hold
        XCTAssertEqual(run(&s, secs: 10, gpu: 11.5), [])
        XCTAssertEqual(s.scale, low)
    }

    func testFailedStepUpBacksOffLonger() {
        var s = RenderScaler(native: 3)
        _ = run(&s, secs: 1, gpu: 30)
        XCTAssertEqual(s.scale, 2.5)
        XCTAssertEqual(run(&s, secs: 3.6, gpu: 3), [3])            // up after 3 s
        XCTAssertEqual(run(&s, secs: 1, gpu: 30), [2.5])           // did not hold: down again
        XCTAssertEqual(run(&s, secs: 4, gpu: 3), [], "second wait is longer (6 s)")
        XCTAssertEqual(run(&s, secs: 3, gpu: 3), [3])
    }

    func testThermalSeriousCapsAtTwoImmediately() {
        var s = RenderScaler(native: 3)
        XCTAssertEqual(s.update(dt: dt, gpuMs: 5, thermal: .serious), 2)
        XCTAssertEqual(run(&s, secs: 20, gpu: 2, thermal: .serious), [], "cannot climb above the cap while hot")
        XCTAssertEqual(s.scale, 2)
        XCTAssertEqual(run(&s, secs: 12, gpu: 2, thermal: .nominal).last, 3, "climbs back once cool")
    }

    func testThermalCriticalAlsoCapsAndRecoversWhenCool() {
        var s = RenderScaler(native: 3)
        XCTAssertEqual(s.update(dt: dt, gpuMs: 5, thermal: .critical), 2)
        let up = run(&s, secs: 12, gpu: 2, thermal: .nominal)
        XCTAssertEqual(up.last, 3)
    }

    func testThermalCapNeverRaisesAnAlreadyLowerScale() {
        var s = RenderScaler(native: 3)
        _ = run(&s, secs: 30, gpu: 74)
        XCTAssertEqual(s.scale, 1.33)
        XCTAssertNil(s.update(dt: dt, gpuMs: 74, thermal: .serious))
        XCTAssertEqual(s.scale, 1.33)
    }

    func testStallsAreIgnored() {
        var s = RenderScaler(native: 3)
        for _ in 0..<100 { XCTAssertNil(s.update(dt: 0.5, gpuMs: 80, thermal: .nominal)) }
        XCTAssertEqual(s.scale, 3)
    }

    // MARK: RateGovernor

    func testRateStays60WhenGPUBusy() {
        var g = RateGovernor(maxFPS: 120)
        var changes: [Int] = []
        for _ in 0..<(60 * 20) { if let f = g.update(dt: dt, gpuMs: 7.5, thermal: .nominal, lowPower: false) { changes.append(f) } }
        XCTAssertEqual(changes, [])
    }

    func testRateGoes120WhenIdleThenFallsBackUnderLoad() {
        var g = RateGovernor(maxFPS: 120)
        var f: [Int] = []
        for _ in 0..<(60 * 4) { if let x = g.update(dt: dt, gpuMs: 3, thermal: .nominal, lowPower: false) { f.append(x) } }
        XCTAssertEqual(f, [120])
        for _ in 0..<60 { if let x = g.update(dt: dt, gpuMs: 9, thermal: .nominal, lowPower: false) { f.append(x) } }
        XCTAssertEqual(f, [120, 60])
        for _ in 0..<(60 * 10) { if let x = g.update(dt: dt, gpuMs: 3, thermal: .nominal, lowPower: false) { f.append(x) } }
        XCTAssertEqual(f, [120, 60], "holds at 60 for 30 s after a load drop")
    }

    func testRateNeverHighOnLowPowerHotOr60HzPanel() {
        for (t, lp, mx) in [(ProcessInfo.ThermalState.nominal, true, 120), (.serious, false, 120), (.nominal, false, 60), (.fair, false, 120)] {
            var g = RateGovernor(maxFPS: mx)
            var f: [Int] = []
            for _ in 0..<(60 * 8) { if let x = g.update(dt: dt, gpuMs: 2, thermal: t, lowPower: lp) { f.append(x) } }
            XCTAssertEqual(f, [], "\(t) lp=\(lp) max=\(mx)")
        }
    }

    func testRateDropsImmediatelyOnLowPower() {
        var g = RateGovernor(maxFPS: 120)
        for _ in 0..<(60 * 4) { _ = g.update(dt: dt, gpuMs: 3, thermal: .nominal, lowPower: false) }
        XCTAssertEqual(g.fps, 120)
        XCTAssertEqual(g.update(dt: dt, gpuMs: 3, thermal: .nominal, lowPower: true), 60)
    }

    func testRateOnlyAtNativeResolution() {
        var g = RateGovernor(maxFPS: 120)
        for _ in 0..<(60 * 8) { XCTAssertNil(g.update(dt: dt, gpuMs: 3, thermal: .nominal, lowPower: false, atNative: false)) }
    }
}
