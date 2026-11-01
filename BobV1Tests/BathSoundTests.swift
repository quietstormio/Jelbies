//
//  BathSoundTests.swift
//  The Clean flow's sound rate limits: strokes at frame rate may not turn into a stream of honks.
//

import XCTest
@testable import BobV1

final class BathSoundTests: XCTestCase {
    /// 60 fps of strokes for `seconds`; how many get through a gate.
    private func passes(gap: Double, seconds: Double) -> Int {
        var g = SoundGate(gap: gap)
        var n = 0
        var t = 0.0
        while t < seconds { if g.allow(now: t) { n += 1 }; t += 1.0 / 60 }
        return n
    }

    func testRateLimitsPerSecond() {
        XCTAssertEqual(passes(gap: BathSFX.popGap, seconds: 1), 2)
        XCTAssertEqual(passes(gap: BathSFX.soapGap, seconds: 1), 1)
        XCTAssertEqual(passes(gap: BathSFX.splashGap, seconds: 1), 3)
        XCTAssertLessThanOrEqual(passes(gap: BathSFX.squeakGap, seconds: 1), 3)
        XCTAssertLessThanOrEqual(passes(gap: BathSFX.soapGap, seconds: 10), 7)
    }

    func testNewEffectsAreRegisteredWithTheirLevels() {
        XCTAssertEqual(SFX.scrubLoop.rawValue, "scrub_loop")
        XCTAssertEqual(SFX.squeakPolish.gain, 0.6)
        XCTAssertEqual(SFX.shineFinish.gain, 0.7)
        for n in ["scrub_loop_1", "squeak_polish_1", "shine_finish_1"] {
            XCTAssertNotNil(Bundle.main.url(forResource: n, withExtension: "m4a"), n)
        }
        XCTAssertLessThan(BathSFX.popVolume, 0.4)
    }

    @MainActor func testMutedHubPlaysNothingAndLoopStaysOff() {
        let hub = AudioHub.shared                // the test host is muted
        hub.scrubLoop(true)
        XCTAssertFalse(hub.scrubWanted)
        hub.play(.squeakPolish)
        XCTAssertTrue(hub._playLog.isEmpty)
    }
}
