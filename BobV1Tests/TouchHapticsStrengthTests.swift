import XCTest
@testable import BobV1

/// The touch-haptics strength curve (`TouchHapticsTuning`): pure number checks plus the sink boundary.
@MainActor
final class TouchHapticsStrengthTests: XCTestCase {
    override func tearDown() { super.tearDown(); TouchHapticsTuning.strength = 1 }

    func testCurvesNeverWeakenNeverClipAndStayMonotonic() {
        for f in [TouchHapticsTuning.continuous, TouchHapticsTuning.transient] {
            XCTAssertEqual(f(0), 0, "silence stays silent")
            XCTAssertEqual(f(1), 1, accuracy: 1e-6)
            var prev: Float = 0
            for k in 0...100 {
                let x = Float(k) / 100, y = f(x)
                XCTAssertGreaterThanOrEqual(y, x - 1e-6, "never weaker at \(x)")
                XCTAssertLessThanOrEqual(y, 1, "never above 1")
                XCTAssertGreaterThanOrEqual(y, prev - 1e-6, "monotonic")
                prev = y
            }
        }
    }

    func testTargetGains() {
        // long channels: +60 ... +80 % in the working range; transients +30 ... +40 %
        for x: Float in [0.2, 0.3, 0.4] { XCTAssertGreaterThanOrEqual(TouchHapticsTuning.continuous(x) / x, 1.6, "stroke / purr level \(x)") }
        for x: Float in [0.3, 0.4, 0.5] { XCTAssertGreaterThanOrEqual(TouchHapticsTuning.transient(x) / x, 1.28, "transient level \(x)") }
        XCTAssertLessThan(TouchHapticsTuning.transient(0.9), 1, "near 1 it does not hard-clip")
    }

    func testSharpnessSoftGetsRounderCrispStaysCrisp() {
        XCTAssertLessThan(TouchHapticsTuning.sharpness(0.2), 0.2)
        XCTAssertEqual(TouchHapticsTuning.sharpness(0.55), 0.55, accuracy: 1e-6)
        XCTAssertEqual(TouchHapticsTuning.sharpness(0.95), 0.95, accuracy: 1e-6, "grumpy hmph stays sharp")
        for k in 0...100 { let s = Float(k) / 100; XCTAssertLessThanOrEqual(TouchHapticsTuning.sharpness(s), s + 1e-6) }
    }

    func testStrengthZeroIsTheOldFeel() {
        TouchHapticsTuning.strength = 0
        for x: Float in [0, 0.13, 0.5, 1] { XCTAssertEqual(TouchHapticsTuning.continuous(x), x, accuracy: 1e-6); XCTAssertEqual(TouchHapticsTuning.transient(x), x, accuracy: 1e-6) }
        XCTAssertEqual(TouchHapticsTuning.sharpness(0.2), 0.2, accuracy: 1e-6)
    }

    func testPurrNeverDropsToZeroWhilePurring() {
        for k in 0...20 {
            let pulse = Float(k) / 20
            XCTAssertGreaterThan(TouchHapticsTuning.purr(level: 1, pulse: pulse), 0.1)
            XCTAssertGreaterThan(TouchHapticsTuning.continuous(TouchHapticsTuning.purr(level: 1, pulse: pulse)), 0.2, "after the curve the floor is felt")
        }
        XCTAssertEqual(TouchHapticsTuning.purr(level: 0, pulse: 1), 0, "no purr, no buzz")
    }

    func testSinkReceivesBoostedTouchValuesButNotRaceOrSoundValues() {
        let rec = RecordingHapticSink(); let d = HapticDriver(sinks: [rec]); d.setWarm(true)
        var heard: [Float] = []; d.soundHook = { _, i in heard.append(i) }
        var now = 50.0
        d.touchTransient(now: now, intensity: 0.3, sharpness: 0.2); now += 0.2
        d.transient(now: now, intensity: 0.3, sharpness: 0.2); now += 0.2                   // race / volleyball path: unchanged
        let tr = rec.events(.transient)
        XCTAssertEqual(tr.count, 2)
        XCTAssertGreaterThan(tr[0].intensity, 0.3 * 1.3 - 0.001)
        XCTAssertEqual(tr[1].intensity, 0.3, accuracy: 1e-6)
        XCTAssertEqual(tr[1].sharpness, 0.2, accuracy: 1e-6)
        XCTAssertEqual(heard, [0.3, 0.3], "the sound pairing keeps the unboosted number")
        for i in 0..<4 { d.update(now: now, petIntensity: 0.3, petSharpness: 0.2, squishIntensity: 0, squishSharpness: 0.2); now += 0.1; _ = i }
        XCTAssertGreaterThanOrEqual(rec.events(.continuous, channel: "pet").first?.intensity ?? 0, 0.3 * 1.6)
    }
}
