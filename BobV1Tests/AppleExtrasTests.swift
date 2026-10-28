//
//  AppleExtrasTests.swift
//  The Apple extras' logic: the Siri entity roster, the status words, route parsing and the App Group queue, Bedtime, the night-aware
//  projection against AwayMath / BlobNeeds, the Live Activity content state's Codable round trip and words, the race update policy and the
//  LiveActivities controller against MockActivityDriver, GameRouter applying routes on a real GameCare, and a GameScreen smoke test.
//

import XCTest
import SwiftUI
import UIKit
@testable import BobV1

@MainActor
final class AppleExtrasTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []         // the runtime aborts when these are released (see MelonModel)
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    /// A fixed calendar (UTC) so the night maths does not depend on the machine.
    static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    /// 2025-10-20 at `hour`:00 UTC.
    private func at(_ hour: Int, minute: Int = 0, day: Int = 20) -> Date {
        var c = DateComponents(); c.year = 2025; c.month = 10; c.day = day; c.hour = hour; c.minute = minute
        return Self.utc.date(from: c)!
    }

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("extras-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func suite(_ name: String) -> UserDefaults { UserDefaults(suiteName: "extras.\(name).\(UUID().uuidString)")! }
    private func rec(_ id: Int, _ name: String, _ color: String = "blue", levels: [Float] = [1, 1, 1], dirt: Float = 0, sparkle: Float = 0) -> JellyRecord {
        JellyRecord(id: id, name: name, color: color, levels: levels, dirt: dirt, sparkle: sparkle, mood: AwayMath.mood(of: levels).rawValue)
    }
    private func live(_ now: @escaping () -> Date, dir: URL, defaults: UserDefaults? = nil) -> (LiveActivities, MockActivityDriver) {
        let m = MockActivityDriver()
        let l = LiveActivities(driver: m, defaults: defaults ?? suite("live"))
        l.now = now; l.calendar = Self.utc; l.directory = dir
        Self.keep.append(l); Self.keep.append(m)
        return (l, m)
    }

    // MARK: entity roster

    func testEntityRosterFromSnapshotElseDefault() throws {
        let dir = try tempDir()
        let def = JelbieRoster.current(directory: dir, count: 3)
        XCTAssertEqual(def.map(\.name), ["Bob", "Pip", "Moss"])
        XCTAssertEqual(def.map(\.color), ["blue", "yellow", "green"])
        XCTAssertEqual(def.map(\.id), [0, 1, 2])
        XCTAssertEqual(JelbieRoster.current(directory: dir, count: 1).map(\.name), ["Bob"])
        XCTAssertEqual(JelbieRoster.current(directory: dir, count: 9).count, 3, "the roster cap")
        XCTAssertEqual(JelbieRoster.current(directory: dir, count: 3, roster: [1, 2, 3]).map(\.name), ["Pip", "Moss", "Lavender"])
        XCTAssertEqual(JelbieRoster.current(directory: dir, count: 3, roster: [1, 2, 3]).map(\.id), [0, 1, 2], "entity ids are slots")
        XCTAssertEqual(JelbieRoster.current(directory: dir, count: 3, roster: [1, 2, 3]).map(\.color), ["yellow", "green", "lavender"])
        XCTAssertEqual(JelbieRoster.colorName(3), "lavender", "the snapshot key WidgetBridge writes")
        JellySnapshot(savedAt: t0, jellies: [rec(1, "Pip", "yellow"), rec(0, "Bob")]).write(to: dir)
        let cur = JelbieRoster.current(directory: dir, count: 3)
        XCTAssertEqual(cur.map(\.id), [0, 1], "the published roster wins over the launch count, sorted by id")
        XCTAssertEqual(cur.map(\.name), ["Bob", "Pip"])
        XCTAssertEqual(JelbieRoster.match("bob", in: cur).map(\.name), ["Bob"])
        XCTAssertEqual(JelbieRoster.match("Pippy", in: cur).map(\.name), ["Pip"])
        XCTAssertEqual(JelbieRoster.match("feed pip", in: cur).map(\.name), ["Pip"])
        XCTAssertEqual(JelbieRoster.match("  ", in: cur).count, 2)
        XCTAssertTrue(JelbieRoster.match("zed", in: cur).isEmpty)
        XCTAssertEqual(JelbieEntity.colorWord("purple"), "Lavender")
    }

    func testEntityQueryAnswers() async throws {
        let q = JelbieQuery()
        let all = try await q.suggestedEntities()
        XCTAssertFalse(all.isEmpty)
        let zero = try await q.entities(for: [0])
        XCTAssertEqual(zero.map(\.id), [0])
        let none = try await q.entities(matching: "zzz")
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: status text

    func testStatusWordsLinesAndSpokenSummary() {
        let states = JellySnapshot(savedAt: t0, jellies: [
            rec(0, "Bob", levels: [0.4, 0.9, 0.9]), rec(1, "Pip", "yellow"), rec(2, "Moss", "green", levels: [0.9, 0.9, 0.9], sparkle: 1),
        ]).project(at: t0)
        XCTAssertEqual(JellyStatus.word(states[0], sleeping: false), "hungry")
        XCTAssertEqual(JellyStatus.word(states[0], sleeping: true), "hungry", "a need shows through a nap")
        XCTAssertEqual(JellyStatus.word(states[1], sleeping: true), "napping")
        XCTAssertEqual(JellyStatus.word(states[1], sleeping: false), "happy")
        XCTAssertEqual(JellyStatus.word(states[2], sleeping: false), "sparkling")
        XCTAssertEqual(JellyStatus.line(states, sleeping: true), "Bob is hungry · Pip napping · Moss napping")
        XCTAssertEqual(JellyStatus.line([], sleeping: false), "Open the game to meet your Jelbies")
        XCTAssertEqual(JellyStatus.inline(states, sleeping: true), "Bob is hungry")
        XCTAssertEqual(JellyStatus.inline([states[1], states[2]], sleeping: true), "Everyone is napping")
        XCTAssertEqual(JellyStatus.inline([states[1], states[2]], sleeping: false), "All 2 Jelbies are happy")
        XCTAssertEqual(JellyStatus.inline([states[1]], sleeping: false), "Pip is happy")
        XCTAssertEqual(JellyStatus.spoken(states, sleeping: false), "Bob is a little hungry. Pip is happy. Moss is happy and sparkling.")
        XCTAssertEqual(JellyStatus.spoken(states, sleeping: true), "Bob is a little hungry. Still dozing, though. Pip is napping. Moss is napping.")
        XCTAssertEqual(JellyStatus.spoken([], sleeping: false), "You have not met your Jelbies yet. Open the game to say hello.")
        let g = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", levels: [0.1, 0.9, 0.4], dirt: 0.8)]).project(at: t0)[0]
        XCTAssertEqual(JellyStatus.sentence(g, sleeping: false), "Bob is grumpy: famished, a little lonely and really dirty.")
        XCTAssertEqual(JellyStatus.needyCount(states), 1)
        XCTAssertEqual(JellyFaceMood.of(states[0], sleeping: true), .hungry)
        XCTAssertEqual(JellyFaceMood.of(states[1], sleeping: true), .sleeping)
        XCTAssertEqual(JellyFaceMood.of(g, sleeping: false), .grumpy)
    }

    // MARK: routes and the queue

    func testRouteParsingAndURLs() {
        let all: [JellyRoute] = [.jelly(0), .feed(nil), .feed(1), .water(nil), .water(2), .bed, .race(1), .train(2), .pet(0)]
        for r in all { XCTAssertEqual(JellyRoute.parse(r.url), r, "\(r)") }
        XCTAssertEqual(JellyRoute.feed(nil).url.absoluteString, "jelbies://feed")
        XCTAssertEqual(JellyRoute.race(1).url.absoluteString, "jelbies://race/1")
        XCTAssertEqual(JellyRoute.parse(URL(string: "jelbies://drink/1")!), .water(1))
        XCTAssertEqual(JellyRoute.parse(URL(string: "jelbies://goodnight")!), .bed)
        XCTAssertEqual(JellyRoute.parse(URL(string: "JELBIES://Feed/2/")!), .feed(2))
        for bad in ["jelbies://race", "jelbies://bed/1", "jelbies://feed/4", "jelbies://feed/x", "jelbies://nope/1", "https://feed/1", "jelbies://feed/1/2", "jelbies://"] {
            XCTAssertNil(JellyRoute.parse(URL(string: bad)!), bad)
        }
        XCTAssertNil(JellyRoute.bed.jellyID); XCTAssertEqual(JellyRoute.race(2).jellyID, 2); XCTAssertNil(JellyRoute.feed(nil).jellyID)
    }

    func testPendingQueueDedupesExpiresAndDrains() throws {
        let dir = try tempDir()
        XCTAssertEqual(PendingActions.read(from: dir), [])
        XCTAssertTrue(PendingActions.enqueue(.water(0), in: dir, now: t0))
        PendingActions.enqueue(.feed(1), in: dir, now: t0.addingTimeInterval(10))
        PendingActions.enqueue(.water(0), in: dir, now: t0.addingTimeInterval(20))         // a repeat replaces the first
        XCTAssertEqual(PendingActions.read(from: dir, now: t0.addingTimeInterval(30)).map(\.route), [.feed(1), .water(0)])
        XCTAssertEqual(PendingActions.queued(for: 0, from: dir, now: t0.addingTimeInterval(30)), [.water(0)])
        PendingActions.enqueue(.bed, in: dir, now: t0.addingTimeInterval(40))
        XCTAssertEqual(PendingActions.queued(for: 1, from: dir, now: t0.addingTimeInterval(50)), [.feed(1), .bed], "a route for everyone counts for each")
        XCTAssertTrue(PendingActions.read(from: dir, now: t0.addingTimeInterval(PendingActions.maxAge + 100)).isEmpty, "a day later: forgotten")
        XCTAssertEqual(PendingActions.drain(from: dir, now: t0.addingTimeInterval(60)), [.feed(1), .water(0), .bed])
        XCTAssertEqual(PendingActions.read(from: dir, now: t0.addingTimeInterval(60)), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(PendingActions.file).path))
        XCTAssertFalse(PendingActions.enqueue(.bed, in: nil), "no container: a quiet false")
    }

    func testBedtimeWakeSleepingAndFile() throws {
        let cal = Self.utc
        let night = at(22, minute: 30)
        let wake = Bedtime.wakeDate(after: night, calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: wake), 6); XCTAssertEqual(cal.component(.day, from: wake), 21)
        XCTAssertEqual(cal.component(.day, from: Bedtime.wakeDate(after: at(3), calendar: cal)), 20, "tucked in at 03:00: up at 06:00 the same morning")
        let afternoon = at(14)
        XCTAssertFalse(Bedtime.isSleeping(at: afternoon, tuckedIn: nil, calendar: cal))
        XCTAssertTrue(Bedtime.isSleeping(at: afternoon, tuckedIn: afternoon.addingTimeInterval(-600), calendar: cal), "tucked in early: asleep until 06:00")
        XCTAssertTrue(Bedtime.isSleeping(at: night, tuckedIn: nil, calendar: cal), "the room's night")
        XCTAssertTrue(Bedtime.isSleeping(at: at(5), tuckedIn: nil, calendar: cal))
        XCTAssertFalse(Bedtime.isSleeping(at: wake, tuckedIn: night, calendar: cal))
        let dir = try tempDir()
        XCTAssertNil(Bedtime.read(from: dir, now: night))
        XCTAssertTrue(Bedtime.write(night, to: dir))
        XCTAssertEqual(Bedtime.read(from: dir, now: night.addingTimeInterval(3600)), night)
        XCTAssertNil(Bedtime.read(from: dir, now: night.addingTimeInterval(Bedtime.maxAge + 1)), "yesterday's tuck-in is over")
        XCTAssertNil(Bedtime.read(from: dir, now: night.addingTimeInterval(-3600)), "a tuck-in in the future is ignored")
        XCTAssertTrue(Bedtime.write(nil, to: dir))
        XCTAssertNil(Bedtime.read(from: dir, now: night.addingTimeInterval(60)))
    }

    // MARK: night-aware projection

    func testNightAwareProjectionHalvesTheNightAndMatchesBlobNeeds() {
        let cal = Self.utc
        let leave = at(19), back = at(3, day: 21)                        // 8 h away: 2 h evening + 6 h of night
        let start: [Float] = [1, 1, 1]
        let snap = JellySnapshot(savedAt: leave, jellies: [rec(0, "Bob", levels: start, dirt: 0.1, sparkle: 0.5)])
        XCTAssertEqual(AwayMath.nightSeconds(from: leave, to: back, calendar: cal), 6 * 3600, accuracy: 1)
        XCTAssertEqual(AwayMath.needSeconds(from: leave, to: back, calendar: cal), 5 * 3600, accuracy: 1, "the night hours count half")
        let p = snap.projectNightAware(at: back, calendar: cal)[0]
        XCTAssertEqual(p.levels, AwayMath.needLevels(start, from: leave, to: back, calendar: cal))
        XCTAssertEqual(p.levels, AwayMath.needLevels(start, seconds: 5 * 3600))
        let plain = snap.project(at: back)[0]
        for k in NeedKind.allCases { XCTAssertGreaterThanOrEqual(p.levels[k.rawValue], plain.levels[k.rawValue], "\(k): the night is gentler") }
        XCTAssertGreaterThan(p.levels[NeedKind.hunger.rawValue], plain.levels[NeedKind.hunger.rawValue])
        XCTAssertEqual(p.dirt, plain.dirt, "dirt and sparkle follow the wall clock either way")
        XCTAssertEqual(p.sparkle, plain.sparkle)
        // a day-only window is the plain projection
        XCTAssertEqual(snap.projectNightAware(at: leave.addingTimeInterval(3600), calendar: cal)[0].levels, snap.project(at: leave.addingTimeInterval(3600))[0].levels)
        // and a real BlobNeeds coming back from the same absence (both on the current calendar) lands on the same numbers
        var clock = leave
        let n = BlobNeeds(defaults: suite("needs"), now: { clock }); Self.keep.append(n)
        for k in NeedKind.allCases { n.set(k, start[k.rawValue]) }
        n.leaveActive(at: leave); clock = back; n.returnActive(at: back)
        let q = snap.projectNightAware(at: back, calendar: .current)[0]
        for k in NeedKind.allCases { XCTAssertEqual(q.levels[k.rawValue], n.level(k), accuracy: 1e-6, "\(k)") }
        // the Siri report reads the same projection
        let dir = try! tempDir()
        snap.write(to: dir)
        let r = JelbiesSiriStatus.report(directory: dir, now: back, calendar: cal)
        XCTAssertEqual(r.states.first?.levels, p.levels)
        XCTAssertTrue(r.sleeping, "03:00 is the room's night")
        XCTAssertEqual(r.spoken, JellyStatus.spoken(r.states, sleeping: true))
    }

    // MARK: Live Activity content

    func testActivityStateCodableRoundTripAndWords() throws {
        let states: [JelbiesState] = [
            .race(position: 2, racers: 4, progress: 0.37, lap: 2, laps: 3), .finished(place: 1, racers: 4, drops: 12, laps: 3),
            .sleeping(["Bob", "Pip"], wakeAt: t0), .awake(["Bob"]), .refilling(until: t0), .refilled,
        ]
        for s in states {
            let d = try JSONEncoder().encode(s)
            XCTAssertEqual(try JSONDecoder().decode(JelbiesState.self, from: d), s)
        }
        let a = JelbiesActivityAttributes(kind: .race, jellyID: 1, jellyName: "Pip", jellyColor: "yellow", startedAt: t0)
        let b = try JSONDecoder().decode(JelbiesActivityAttributes.self, from: try JSONEncoder().encode(a))
        XCTAssertEqual(b.kind, .race); XCTAssertEqual(b.jellyID, 1); XCTAssertEqual(b.jellyName, "Pip"); XCTAssertEqual(b.startedAt, t0.timeIntervalSince1970)
        XCTAssertEqual(a.headline(states[0]), "Pip is racing!")
        XCTAssertEqual(a.detail(states[0]), "2nd of 4 · lap 2 of 3")
        XCTAssertEqual(a.headline(states[1]), "🥇 Pip won! +12 JellyCoins")
        XCTAssertEqual(a.detail(states[1]), "3 laps on the Jelly Circuit")
        XCTAssertEqual(JelbiesActivityAttributes(kind: .race).headline(.finished(place: 3, racers: 4, drops: 4, laps: 3)), "🥉 Bob came 3rd! +4 JellyCoins")
        XCTAssertEqual(JelbiesActivityAttributes(kind: .race).headline(.finished(place: 4, racers: 4, drops: 0, laps: 1)), "🏁 Bob came 4th!")
        let nap = JelbiesActivityAttributes(kind: .nap)
        XCTAssertEqual(nap.headline(states[2]), "The Jelbies are sleeping")
        XCTAssertEqual(nap.headline(states[3]), "Bob is up!")
        XCTAssertEqual(nap.detail(states[3]), "Good morning!")
        XCTAssertTrue(nap.detail(states[2]).hasPrefix("Up at "))
        XCTAssertEqual(JelbiesActivityAttributes(kind: .pep).headline(.refilled), "Pep is back!")
        XCTAssertEqual(JelbiesActivityAttributes(kind: .pep, jellyName: "Moss").headline(states[4]), "Moss is out of Pep")
        for (n, w) in [(1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"), (11, "11th"), (12, "12th"), (13, "13th"), (21, "21st"), (22, "22nd")] { XCTAssertEqual(JelbiesState.ordinal(n), w) }
        XCTAssertEqual(JelbiesState.race(position: 1, racers: 4, progress: 1.7, lap: 3, laps: 3).progress, 1, "clamped")
        XCTAssertEqual(states[2].untilDate, t0)
    }

    func testRacePolicyPublishesMilestonesOnly() {
        var p = RaceActivityPolicy()
        func s(_ pos: Int = 1, _ prog: Double, lap: Int = 1) -> JelbiesState { .race(position: pos, racers: 4, progress: prog, lap: lap, laps: 3) }
        XCTAssertTrue(p.shouldPublish(s(1, 0)), "the start")
        XCTAssertFalse(p.shouldPublish(s(1, 0.1)))
        XCTAssertFalse(p.shouldPublish(s(1, 0.24)))
        XCTAssertTrue(p.shouldPublish(s(1, 0.25)), "a quarter")
        XCTAssertFalse(p.shouldPublish(s(1, 0.3)))
        XCTAssertTrue(p.shouldPublish(s(2, 0.31)), "the placing changed")
        XCTAssertTrue(p.shouldPublish(s(2, 0.34, lap: 2)), "a new lap")
        XCTAssertFalse(p.shouldPublish(s(2, 0.49, lap: 2)))
        XCTAssertTrue(p.shouldPublish(s(2, 0.5, lap: 2)))
        XCTAssertTrue(p.shouldPublish(.finished(place: 2, racers: 4, drops: 6, laps: 3)))
        p.reset(); XCTAssertNil(p.last)
    }

    // MARK: the controller against the mock driver

    func testRaceActivityStartsUpdatesSparinglyAndEnds() throws {
        let dir = try tempDir()
        var clock = t0
        let (l, m) = live({ clock }, dir: dir)
        l.raceStarted(jellyID: 1, name: "Pip", color: "yellow", racers: 4, laps: 3)
        XCTAssertTrue(l.raceLive); XCTAssertEqual(m.calls.count, 1)
        guard case .start(.race, let s0) = m.calls[0] else { return XCTFail("start") }
        XCTAssertEqual(s0.phase, .running); XCTAssertEqual(s0.racers, 4); XCTAssertEqual(s0.laps, 3)
        XCTAssertEqual(m.live["a1"]?.0.jellyName, "Pip")
        XCTAssertEqual(m.staleDates["a1"]!, t0.addingTimeInterval(1800))
        for i in 0..<600 {                                           // every tick of a race
            let prog = Double(i) / 600
            l.raceProgress(position: prog < 0.3 ? 1 : 2, progress: prog, lap: 1 + Int(prog * 3))
        }
        XCTAssertEqual(m.updates, 6, "quarters (3) + the placing change (1) + laps 2 and 3 (2): never per tick")
        clock = t0.addingTimeInterval(90)
        l.raceFinished(place: 2, drops: 6)
        XCTAssertFalse(l.raceLive)
        guard case .end("a1", let fin) = m.calls.last! else { return XCTFail("end") }
        XCTAssertEqual(fin.phase, .finished); XCTAssertEqual(fin.place, 2); XCTAssertEqual(fin.drops, 6); XCTAssertEqual(fin.progress, 1)
        XCTAssertEqual(m.dismissals["a1"]!, clock.addingTimeInterval(LiveActivities.linger))
        l.raceProgress(position: 1, progress: 0.5, lap: 2); l.raceFinished(place: 1, drops: 1)
        XCTAssertEqual(m.calls.count, 8, "nothing without a race")
        m.enabled = false
        l.raceStarted(jellyID: 0, name: "Bob", color: "blue", racers: 4, laps: 3)
        XCTAssertFalse(l.raceLive, "Live Activities off in Settings: nothing starts")
        m.enabled = true; m.failStart = true
        l.raceStarted(jellyID: 0, name: "Bob", color: "blue", racers: 4, laps: 3)
        XCTAssertFalse(l.raceLive, "a failing request is quiet")
    }

    func testNapCardAtBedtimeAndGoodMorning() throws {
        let dir = try tempDir()
        var clock = at(22)
        let (l, m) = live({ clock }, dir: dir)
        XCTAssertTrue(l.napOn, "default on"); XCTAssertFalse(l.pepOn, "default off")
        XCTAssertTrue(l.isNight()); XCTAssertFalse(l.isNight(at(12)))
        let names = ["Bob", "Pip"]
        l.leftActive(names: names)
        XCTAssertTrue(l.napLive)
        guard case .start(.nap, let s) = m.calls[0] else { return XCTFail("start") }
        XCTAssertEqual(s.phase, .sleeping); XCTAssertEqual(s.sleepers, names)
        XCTAssertEqual(s.untilDate, Bedtime.wakeDate(after: clock, calendar: Self.utc))
        XCTAssertEqual(m.staleDates["a1"]!, s.untilDate, "stale at the wake time")
        XCTAssertNil(Bedtime.read(from: dir, now: clock), "leaving at night does not tuck in; only goodnight does")
        l.leftActive(names: names)
        XCTAssertEqual(m.calls.count, 1, "one nap card")
        clock = at(23); l.returnedActive(names: names)
        XCTAssertTrue(l.napLive, "still night: the card stays")
        clock = at(9, day: 21); l.returnedActive(names: names)
        XCTAssertFalse(l.napLive)
        guard case .end("a1", let e) = m.calls.last! else { return XCTFail("end") }
        XCTAssertEqual(e.phase, .awake); XCTAssertEqual(e.sleepers, names)
        XCTAssertEqual(m.dismissals["a1"]!, clock.addingTimeInterval(LiveActivities.linger))
        // goodnight by day (Siri / the bed route): tucked in, the card is up until 06:00
        clock = at(15, day: 21)
        l.bedtime(names: ["Bob"], now: clock)
        XCTAssertEqual(Bedtime.read(from: dir, now: clock), clock); XCTAssertTrue(l.napLive)
        l.returnedActive(names: ["Bob"])
        XCTAssertTrue(l.napLive, "tucked in: asleep by day too")
        l.napOn = false
        l.returnedActive(names: ["Bob"])
        XCTAssertFalse(l.napLive, "the setting off ends the card"); XCTAssertNil(Bedtime.read(from: dir, now: clock))
        clock = at(22, day: 21); l.leftActive(names: ["Bob"])
        XCTAssertFalse(l.napLive, "off: no card at night either")
    }

    func testPepCountdownOnlyWhenOnAndSettingsPersist() throws {
        let dir = try tempDir()
        let clock = at(15)
        let (l, m) = live({ clock }, dir: dir)
        l.pepDepleted(jellyID: 0, name: "Bob", color: "blue")
        XCTAssertFalse(l.pepLive, "off by default")
        l.pepOn = true
        l.pepDepleted(jellyID: 0, name: "Bob", color: "blue")
        XCTAssertTrue(l.pepLive)
        guard case .start(.pep, let s) = m.calls[0] else { return XCTFail("start") }
        XCTAssertEqual(s.phase, .refilling); XCTAssertEqual(s.pep, 0)
        XCTAssertEqual(s.untilDate, LiveActivities.nextMidnight(after: clock, calendar: Self.utc))
        XCTAssertEqual(s.untilDate, at(0, day: 21))
        XCTAssertEqual(m.staleDates["a1"]!, s.untilDate)
        l.pepDepleted(jellyID: 1, name: "Pip", color: "yellow")
        XCTAssertEqual(m.calls.count, 1, "one countdown at a time")
        l.pepRefilled()
        XCTAssertFalse(l.pepLive)
        guard case .end("a1", let e) = m.calls.last! else { return XCTFail("end") }
        XCTAssertEqual(e.phase, .refilled); XCTAssertEqual(e.pep, 1)
        // the settings persist and are read back
        let d = suite("settings")
        XCTAssertTrue(LiveActivitySettings.napOn(d)); XCTAssertFalse(LiveActivitySettings.pepOn(d))
        let l2 = LiveActivities(driver: MockActivityDriver(), defaults: d); Self.keep.append(l2)
        l2.napOn = false; l2.pepOn = true
        XCTAssertFalse(LiveActivitySettings.napOn(d)); XCTAssertTrue(LiveActivitySettings.pepOn(d))
        let l3 = LiveActivities(driver: MockActivityDriver(), defaults: d); Self.keep.append(l3)
        XCTAssertFalse(l3.napOn); XCTAssertTrue(l3.pepOn)
    }

    func testCleanUpEndsOrphansAndAdoptsLiveOnes() throws {
        let dir = try tempDir()
        let clock = at(9)
        let m = MockActivityDriver(); Self.keep.append(m)
        let race = try m.start(JelbiesActivityAttributes(kind: .race), state: .race(position: 2, racers: 4, progress: 0.5, lap: 2, laps: 3), staleDate: nil)
        let oldNap = try m.start(JelbiesActivityAttributes(kind: .nap), state: .sleeping(["Bob"], wakeAt: clock.addingTimeInterval(-3600)), staleDate: nil)
        let nap = try m.start(JelbiesActivityAttributes(kind: .nap), state: .sleeping(["Bob"], wakeAt: clock.addingTimeInterval(3600)), staleDate: nil)
        let pep = try m.start(JelbiesActivityAttributes(kind: .pep), state: .refilling(until: clock.addingTimeInterval(7200)), staleDate: nil)
        let d = suite("cleanup"); d.set(true, forKey: LiveActivitySettings.pepKey)
        let l = LiveActivities(driver: m, defaults: d); l.now = { clock }; l.calendar = Self.utc; l.directory = dir; Self.keep.append(l)
        l.cleanUp(names: ["Bob"])
        XCTAssertEqual(Set(m.live.keys), [nap, pep], "the race from a killed run and the nap past its wake are ended")
        XCTAssertEqual(l.napID, nap); XCTAssertEqual(l.pepID, pep)
        XCTAssertEqual(l.pepRefillAt, clock.addingTimeInterval(7200))
        XCTAssertFalse(l.raceLive)
        let ended = m.calls.compactMap { if case .end(let id, let s) = $0 { return (id, s) } else { return nil } }
        XCTAssertEqual(ended.first { $0.0 == race }?.1.phase, .finished)
        XCTAssertEqual(ended.first { $0.0 == race }?.1.place, 2)
        XCTAssertEqual(ended.first { $0.0 == oldNap }?.1.phase, .awake)
        XCTAssertEqual(m.dismissals[race]!, clock, "orphans go away at once")
        // the setting turned off: the adopted card goes too, and the controller forgets it
        l.pepOn = false
        l.cleanUp(names: ["Bob"])
        XCTAssertNil(l.pepID); XCTAssertFalse(l.pepLive); XCTAssertNil(m.live[pep])
        XCTAssertEqual(l.napID, nap, "the nap stays")
        // a refill time that has passed: refilled on launch
        let m2 = MockActivityDriver(); Self.keep.append(m2)
        let pep2 = try m2.start(JelbiesActivityAttributes(kind: .pep), state: .refilling(until: clock.addingTimeInterval(-60)), staleDate: nil)
        let d2 = suite("cleanup2"); d2.set(true, forKey: LiveActivitySettings.pepKey)
        let l2 = LiveActivities(driver: m2, defaults: d2); l2.now = { clock }; l2.calendar = Self.utc; l2.directory = dir; Self.keep.append(l2)
        l2.cleanUp(names: ["Bob"])
        XCTAssertNil(m2.live[pep2]); XCTAssertNil(l2.pepID)
    }

    // MARK: GameRouter on a real GameCare

    func testGameRouterAppliesRoutesThroughGameCare() throws {
        let dir = try tempDir()
        let care = GameCare(jellyCount: 3, persistent: false, defaults: suite("router.care")); Self.keep.append(care)
        let r = GameRouter(directory: dir); Self.keep.append(r)
        var clock = at(15)
        r.now = { clock }
        let (l, m) = live({ clock }, dir: dir); r.live = l
        var beds = 0; r.onBed = { beds += 1 }                       // keep the real DayClock out of the test
        var raced: [Int] = []; r.onRace = { raced.append($0) }
        // a deep link
        XCTAssertTrue(r.handle(URL(string: "jelbies://jelly/1")!))
        XCTAssertFalse(r.handle(URL(string: "https://example.com/jelly/1")!))
        XCTAssertEqual(r.pending, [.jelly(1)]); XCTAssertEqual(r.serial, 1)
        r.apply(care: care)
        XCTAssertEqual(r.applied, [.jelly(1)]); XCTAssertTrue(r.pending.isEmpty)
        XCTAssertEqual(care.select.drawStarts, 1, "the roster highlight played")
        // feed then water: the drink waits for the tray; a repeated request moves to the back without a duplicate
        r.request(.water(0)); r.request(.feed(0)); r.request(.water(0))
        XCTAssertEqual(r.pending, [.feed(0), .water(0)]); XCTAssertEqual(r.serial, 4)
        r.apply(care: care)
        XCTAssertTrue(care.trayOut); XCTAssertEqual(care.servingKind, .food)
        XCTAssertEqual(r.pending, [.water(0)], "water waits for the tray to go")
        XCTAssertEqual(r.applied.last, .feed(0))
        // goodnight, a race and training: the hooks (race) or the roster highlight (train, until its worker is merged)
        r.request(.bed); r.request(.race(2)); r.request(.train(1))
        r.apply(care: care)
        XCTAssertEqual(beds, 1); XCTAssertEqual(raced, [2])
        XCTAssertEqual(Array(r.applied.suffix(3)), [.bed, .race(2), .train(1)])
        XCTAssertTrue(l.napLive, "goodnight: the nap card"); XCTAssertEqual(Bedtime.read(from: dir, now: clock), clock)
        guard case .start(.nap, let s) = m.calls[0] else { return XCTFail("nap") }
        XCTAssertEqual(s.sleepers, ["Bob", "Pip", "Moss"])
        XCTAssertEqual(r.pending, [.water(0)])
        // the App Group queue (the widget's Water button / an intent run while away)
        PendingActions.enqueue(.pet(1), in: dir, now: clock)
        clock = clock.addingTimeInterval(60)
        r.drainQueued()
        XCTAssertEqual(r.pending, [.water(0), .pet(1)])
        XCTAssertEqual(PendingActions.read(from: dir, now: clock), [], "drained")
        r.apply(care: care)
        XCTAssertEqual(r.pending, [.water(0), .pet(1)], "both wait while the tray is out")
        // nothing to do: no-op
        let before = r.applied.count
        r.apply(care: care); XCTAssertEqual(r.applied.count, before)
    }

    // MARK: GameScreen smoke

    func testGameScreenHostsWithTheRouterHooks() {
        let host = UIHostingController(rootView: GameScreen())
        host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
        XCTAssertGreaterThan(host.view.bounds.width, 0)
        Self.keep.append(host)
    }
}
