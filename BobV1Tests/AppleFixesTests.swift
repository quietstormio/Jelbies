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

    // MARK: B

    func testStalePendingRouteIsDroppedFreshOneKept() throws {
        let dir = try tempDir()
        let care = GameCare(jellyCount: 3, persistent: false, defaults: suite()); Self.keep.append(care)
        let r = GameRouter(directory: dir); Self.keep.append(r)
        var clock = at(15); r.now = { clock }
        r.live = nil
        r.request(.jelly(1))
        r.request(.race(2)); r.onRace = { _ in }
        clock = clock.addingTimeInterval(9 * 60)
        r.request(.jelly(0))                                  // a fresh one
        clock = clock.addingTimeInterval(2 * 60)             // jelly(1), race(2): 11 min old; jelly(0): 2 min old
        r.apply(care: care)
        XCTAssertEqual(r.applied, [.jelly(0)], "the 11-minute-old routes are dropped unseen, the fresh one runs")
        XCTAssertTrue(r.pending.isEmpty)
        r.request(.jelly(2)); clock = clock.addingTimeInterval(9 * 60)
        r.apply(care: care)
        XCTAssertEqual(r.applied.last, .jelly(2), "9 minutes: still kept and performed")
    }

    func testClearPendingForgetsEverything() {
        let r = GameRouter(directory: nil); Self.keep.append(r)
        r.request(.bed); r.request(.feed(1))
        XCTAssertEqual(r.pending.count, 2)
        r.clearPending()
        XCTAssertTrue(r.pending.isEmpty, "a new game (wipeAll) starts with nothing waiting")
    }

    // MARK: C

    private func careAndLive(_ dir: URL, clock: @escaping () -> Date) -> (GameCare, LiveActivities, MockActivityDriver) {
        let care = GameCare(jellyCount: 3, persistent: false, defaults: suite()); Self.keep.append(care)
        let (l, m) = live(clock, dir: dir)
        care.raceBook.live = l
        care.syncsAppGroup = true
        return (care, l, m)
    }

    func testRefusedGoodnightWritesNoBedtimeAndRaisesNoCard() throws {
        let dir = try tempDir()
        let clock = at(15)
        let (care, l, m) = careAndLive(dir, clock: { clock })
        let r = GameRouter(directory: dir); Self.keep.append(r)
        r.now = { clock }; r.live = l
        r.onGoodnight = { care.goodnight() }
        care.meal = Consumables.berries                       // a meal is out: canBedtime is false
        XCTAssertFalse(care.canBedtime)
        XCTAssertFalse(care.goodnight())
        r.request(.bed); r.apply(care: care)
        XCTAssertNil(Bedtime.read(from: dir, now: clock), "refused: nothing stamped")
        XCTAssertFalse(l.napLive); XCTAssertTrue(m.calls.isEmpty, "and no nap card")
        XCTAssertEqual(r.applied, [.bed], "the route itself is handled, not retried")
        care.meal = nil
        XCTAssertTrue(care.canBedtime)
        r.request(.bed); r.apply(care: care)
        XCTAssertEqual(Bedtime.read(from: dir, now: clock), clock, "it ran: stamped")
        XCTAssertTrue(l.napLive)
    }

    func testHUDBedtimeStampsAndWakingClears() throws {
        let dir = try tempDir()
        let clock = at(22)
        let (care, l, _) = careAndLive(dir, clock: { clock })
        XCTAssertTrue(care.bedtimeAll())
        XCTAssertEqual(Bedtime.read(from: dir, now: clock), clock, "the HUD Bedtime button stamps too: Siri and the widget agree with the room")
        care.wakeAll()
        XCTAssertNil(Bedtime.read(from: dir, now: clock), "waking everybody in game clears it")
        XCTAssertFalse(l.napLive)
        // one of three woken while the others are still wanted: the stamp stays
        XCTAssertTrue(care.bedtimeAll())
        care.wakeSleeper(0)
        XCTAssertNotNil(Bedtime.read(from: dir, now: clock), "the others are still going to bed")
        care.wakeAll()
        XCTAssertNil(Bedtime.read(from: dir, now: clock))
    }

    func testReturnedActiveWithNobodyAsleepEndsStampAndCard() throws {
        let dir = try tempDir()
        let clock = at(23)
        let (l, m) = live({ clock }, dir: dir)
        l.bedtime(names: ["Bob"], colors: ["teddy"], now: clock)
        XCTAssertTrue(l.napLive)
        l.returnedActive(names: ["Bob"], nobodyAsleep: false)
        XCTAssertTrue(l.napLive, "night and asleep: the card stays")
        l.returnedActive(names: ["Bob"], nobodyAsleep: true)
        XCTAssertFalse(l.napLive); XCTAssertNil(Bedtime.read(from: dir, now: clock))
        XCTAssertEqual(m.dismissals["a1"]!, clock, "ended at once, no morning linger")
    }

    // MARK: E, F

    func testNapCardStaleDateIsTheWakeDateAndStaleShowsGoodMorning() throws {
        let dir = try tempDir()
        let clock = at(22)
        let (l, m) = live({ clock }, dir: dir)
        l.bedtime(names: ["Bob", "Pip"], colors: ["blue", "yellow"], now: clock)
        let wake = Bedtime.wakeDate(after: clock, calendar: Self.utc)
        XCTAssertEqual(m.staleDates["a1"]!, wake)
        guard case .start(.nap, let s) = m.calls[0] else { return XCTFail("start") }
        XCTAssertEqual(s.untilDate, wake)
        XCTAssertEqual(s.shown(stale: false).phase, .sleeping)
        let stale = s.shown(stale: true)
        XCTAssertEqual(stale.phase, .awake); XCTAssertEqual(stale.sleepers, ["Bob", "Pip"])
        let attrs = JelbiesActivityAttributes(kind: .nap, jellyName: "Bob")
        XCTAssertEqual(attrs.detail(stale), "Good morning!")
        XCTAssertEqual(JelbiesActivityAttributes.ContentState.race(position: 1, racers: 4, progress: 0.5, lap: 1, laps: 3).shown(stale: true).phase, .running, "a race is not touched")
    }

    func testSleeperColoursRoundTripAndOldPayloadDecodes() throws {
        let s = JelbiesActivityAttributes.ContentState.sleeping(["Bob", "Teddy", "Pan"], colors: ["blue", "teddy", "panda"], wakeAt: at(7))
        let back = try JSONDecoder().decode(JelbiesActivityAttributes.ContentState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        XCTAssertEqual((0..<3).map(back.sleeperColor), ["blue", "teddy", "panda"])
        // a payload written before the field existed
        let old = #"{"phase":"sleeping","position":1,"racers":4,"progress":0,"lap":1,"laps":3,"drops":0,"sleepers":["Bob","Pip"],"until":1760000000}"#
        let o = try JSONDecoder().decode(JelbiesActivityAttributes.ContentState.self, from: Data(old.utf8))
        XCTAssertNil(o.sleeperColors)
        XCTAssertEqual((0..<2).map(o.sleeperColor), ["blue", "yellow"], "the old by-position colours")
        // the controller passes the real colours through
        let dir = try tempDir()
        let (l, m) = live({ self.at(23) }, dir: dir)
        l.bedtime(names: ["Pearl", "Pan"], colors: ["pearl", "panda"], now: at(23))
        guard case .start(_, let st) = m.calls[0] else { return XCTFail() }
        XCTAssertEqual(st.sleeperColors, ["pearl", "panda"])
        XCTAssertEqual(m.live["a1"]!.0.jellyColor, "pearl")
    }

    // MARK: I

    func testPhotoSaveMessages() {
        XCTAssertEqual(PhotoAlbum.message(for: .failed), "Couldn't save the photo. Try again.")
        XCTAssertEqual(PhotoAlbum.message(for: .noSpace), PhotoAlbum.noSpaceMessage)
        XCTAssertTrue(PhotoAlbum.isOutOfSpace(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)))
        XCTAssertTrue(PhotoAlbum.isOutOfSpace(NSError(domain: "x", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])))
        XCTAssertFalse(PhotoAlbum.isOutOfSpace(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)))
    }

    // MARK: G

    func testWidgetNameChangeRepublishesAndAsksSiriToRelearn() throws {
        let dir = try tempDir()
        var reloads = 0
        let w = WidgetBridge(directory: dir, now: { self.at(12) }, rendersPortraits: false, isForeground: { true }, reload: { reloads += 1 })
        Self.keep.append(w)
        var relearn = 0; w.onNamesChanged = { relearn += 1 }
        func input(_ name: String) -> WidgetBridge.Input { .init(id: 0, name: name, color: "blue", levels: [1, 1, 1], dirt: 0, sparkle: 0) }
        w.publish([input("Bob")], force: true, render: false)
        XCTAssertEqual(relearn, 0, "the first publish of a session: GameScreen refreshes Siri itself")
        XCTAssertEqual(JellySnapshot.read(from: dir)?.jellies.first?.name, "Bob")
        XCTAssertNotEqual(WidgetBridge.stateKey([input("Bob")]), WidgetBridge.stateKey([input("Bobby")]), "a rename changes the key, so the 10 s tick republishes")
        w.publish([input("Bobby")], force: false, render: false)
        XCTAssertEqual(relearn, 1)
        w.publish([input("Bobby")], force: false, render: false)
        XCTAssertEqual(relearn, 1, "unchanged names: no refresh")
    }
}
