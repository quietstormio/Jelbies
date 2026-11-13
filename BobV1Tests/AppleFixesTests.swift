//
//  AppleFixesTests.swift
//  apple-fixes-r1: one shared sleeping-hours rule (D), stale pending routes and the wipe (B), a refused goodnight and wakes clearing the Bedtime stamp (C),
//  the nap card's stale date and real colours (E, F), the empty Siri roster before the game has run (H).
//

import XCTest
import SwiftUI
@testable import BobV1

@MainActor
final class AppleFixesTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func at(_ hour: Int, minute: Int = 0, day: Int = 20) -> Date {
        var c = DateComponents(); c.year = 2025; c.month = 10; c.day = day; c.hour = hour; c.minute = minute
        return Self.utc.date(from: c)!
    }
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("fixes-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func suite() -> UserDefaults { UserDefaults(suiteName: "fixes.\(UUID().uuidString)")! }
    private func live(_ now: @escaping () -> Date, dir: URL) -> (LiveActivities, MockActivityDriver) {
        let m = MockActivityDriver()
        let l = LiveActivities(driver: m, defaults: suite())
        l.now = now; l.calendar = Self.utc; l.directory = dir
        Self.keep.append(l); Self.keep.append(m)
        return (l, m)
    }

    // MARK: D

    /// The widget / Siri rule equals the game's bedtime-hours expression (`GameCare.isBedtimeHours`) at every minute of the day.
    func testSharedSleepRuleMatchesTheGamesNightEdgeEveryMinute() {
        XCTAssertEqual(SleepHours.nightEdge, SleepTuning.nightEdge)
        XCTAssertEqual(SleepHours.nightEdge, NightRestTuning.nightEdge)
        var firstDay: Double?, lastNight: Double?
        for m in 0..<(24 * 60) {
            let h = Double(m) / 60
            let nightFactor = Float(DayBlend(hour: h).night), deep: Float = (h >= 23 || h < 6) ? 1 : 0
            let game = nightFactor > NightRestTuning.nightEdge || deep > 0.5          // GameCare.isBedtimeHours, on a fractional hour
            XCTAssertEqual(SleepHours.isNight(hour: h), game, "hour \(h)")
            if !game, firstDay == nil, h > 6 { firstDay = h }
            if game, h < 23, h > 12 { lastNight = lastNight ?? h }
        }
        XCTAssertEqual(firstDay!, 7.0 + 8.0 / 60, accuracy: 1.0 / 60, "the room wakes about 07:07")
        XCTAssertEqual(lastNight!, 20.0 + 22.0 / 60, accuracy: 1.0 / 60, "and goes to bed about 20:22")
    }

    func testSiriAndWidgetSleepAtTheGamesEdges() {
        XCTAssertTrue(Bedtime.isSleeping(at: at(6, minute: 30), tuckedIn: nil, calendar: Self.utc), "06:30: the game opens on sleepers")
        XCTAssertTrue(Bedtime.isSleeping(at: at(20, minute: 45), tuckedIn: nil, calendar: Self.utc))
        XCTAssertFalse(Bedtime.isSleeping(at: at(7, minute: 30), tuckedIn: nil, calendar: Self.utc))
        XCTAssertFalse(Bedtime.isSleeping(at: at(20, minute: 0), tuckedIn: nil, calendar: Self.utc))
        let wake = Bedtime.wakeDate(after: at(22), calendar: Self.utc)
        XCTAssertEqual(Self.utc.component(.day, from: wake), 21)
        XCTAssertEqual(Self.utc.component(.hour, from: wake), 7)
        XCTAssertFalse(Bedtime.isSleeping(at: wake, tuckedIn: at(22), calendar: Self.utc))
        XCTAssertTrue(Bedtime.isSleeping(at: wake.addingTimeInterval(-60), tuckedIn: at(22), calendar: Self.utc))
        XCTAssertEqual(Bedtime.wakeDate(after: at(15), calendar: Self.utc), wake, "by day: the next morning")
    }
}
