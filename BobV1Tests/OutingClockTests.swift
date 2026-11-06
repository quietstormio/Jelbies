import XCTest
@testable import BobV1

/// 2026-11-06: game time runs `outingRateMul` times faster while the player is out (Town, competitions, café, park, groomer); home stays 1x.
@MainActor
final class OutingClockTests: XCTestCase {
    private var uptime = 1000.0

    private func makeClock(follow: Bool = false, forced: Double? = nil) -> DayClock {
        let suite = UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        if follow { d.set(true, forKey: DayClock.followKey) }
        if let f = forced { d.set(f, forKey: "ClockHour") }
        uptime = 1000
        return DayClock(defaults: d, now: { Date(timeIntervalSince1970: 1_800_000_000) }, uptime: { self.uptime }, calendar: .current)
    }

    /// Runs `seconds` real seconds in 0.5 s frames (the clock ignores a step over 1 s).
    private func run(_ c: DayClock, _ seconds: Double) {
        for _ in 0..<Int(seconds * 2) { uptime += 0.5; c.refresh() }
    }

    func testHomeIsOneGameHourPerMinute() {
        let c = makeClock(); let t0 = c.gameTime
        run(c, 60)
        XCTAssertEqual(c.gameTime - t0, 1, accuracy: 1e-6)
    }

    func testOutingRunsTwiceAsFast() {
        let c = makeClock(); let t0 = c.gameTime
        c.setOutingRate(true)
        run(c, 60)
        XCTAssertEqual(c.gameTime - t0, GameClockTuning.outingRateMul, accuracy: 1e-6)
        XCTAssertEqual(GameClockTuning.outingRateMul, 2.0)
        c.setOutingRate(false)
        let t1 = c.gameTime
        run(c, 60)
        XCTAssertEqual(c.gameTime - t1, 1, accuracy: 1e-6, "home is back at 1x")
    }

    func testTheSwitchIsClean() {
        let c = makeClock(); let t0 = c.gameTime
        run(c, 30)                                     // 30 s at home = 0.5 h
        uptime += 0.4                                  // 0.4 s pass with no frame, THEN the player goes out: they belong to the home rate
        c.setOutingRate(true)
        XCTAssertEqual(c.gameTime - t0, 0.5 + 0.4 / 60, accuracy: 1e-6)
        uptime += 0.4                                  // 0.4 s out, then home again: those belong to the outing rate
        c.setOutingRate(false)
        XCTAssertEqual(c.gameTime - t0, 0.5 + 0.4 / 60 + 0.8 / 60, accuracy: 1e-6)
    }

    func testSleepoverSecondsFollowTheCurrentRate() {
        let c = makeClock()
        let home = c.secondsToSleepoverEnd!
        c.setOutingRate(true)
        XCTAssertEqual(c.secondsToSleepoverEnd!, home / 2, accuracy: 0.5)
    }

    func testRealClockAndForcedHourAreUntouched() {
        let f = makeClock(follow: true)
        f.setOutingRate(true)
        XCTAssertEqual(f.effectiveRateMul, 1)
        let h = makeClock(forced: 12)
        h.setOutingRate(true)
        XCTAssertEqual(h.effectiveRateMul, 1)
        XCTAssertEqual(h.hour, 12, accuracy: 1e-9)
        XCTAssertEqual(DayClock.shared.effectiveRateMul, 1, "under XCTest the shared clock is forced to noon")
    }
}
