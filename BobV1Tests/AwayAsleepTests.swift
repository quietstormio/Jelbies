//
//  AwayAsleepTests.swift
//  Time away when the creature was ASLEEP at the moment the player left: food and water run down on the slow asleep rates
//  (NeedsTuning.asleepAwayHours) for the whole absence, with no night half on top; awake ones use the awake rates and keep the 21:00-06:00 half weight.
//  Attention is unchanged by sleep. The foreground return, the cold launch and the widget / Siri projection must all give the same numbers.
//  Times are LOCAL (the night rule reads Calendar.current), on a June date away from any DST change.
//

import XCTest
@testable import BobV1

@MainActor
final class AwayAsleepTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []         // the runtime aborts when BlobNeeds are released (see MelonModel)
    private let cal = Calendar.current

    /// Local time on 2026-06-10 + `day`.
    private func at(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: 10 + day, hour: hour))!
    }
    private func suite() -> UserDefaults {
        let name = "awayasleep.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    private func make(_ d: UserDefaults, now: Date, key: String = NeedsTuning.defaultsKey) -> BlobNeeds {
        let n = BlobNeeds(defaults: d, key: key, now: { now }); Self.keep.append(n); return n
    }
    private func lv(_ n: BlobNeeds) -> [Float] { NeedKind.allCases.map { n.level($0) } }
    private func away(_ start: [Float], _ from: Date, _ to: Date, asleep: Bool) -> [Float] { AwayMath.needLevels(start, from: from, to: to, calendar: cal, asleep: asleep) }
    private func eq(_ a: [Float], _ b: [Float], _ msg: String = "", line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, line: line)
        for i in 0..<min(a.count, b.count) { XCTAssertEqual(a[i], b[i], accuracy: 1e-5, "\(msg) [\(i)]", line: line) }
    }

    // MARK: the numbers

    func testTheRatesAreNamedConstants() {
        XCTAssertEqual(NeedsTuning.awakeAwayHours, [20, 16, 6]); XCTAssertEqual(NeedsTuning.asleepAwayHours, [60, 48, 6])
        XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.hunger), 20); XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.thirst), 16); XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.attention), 6)
        XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.hunger, asleep: true), 60); XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.thirst, asleep: true), 48)
        XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.attention, asleep: true), 6, "attention is unchanged by sleep")
        XCTAssertEqual(NeedsTuning.awayFloor, 0.2)
    }

    func testAwakeDaytime() {
        // 14:00 -> 17:00 (3 h) and 14:00 -> 22:00 is not daytime, so 8 h daytime is 08:00 -> 16:00
        eq(away([1, 1, 1], at(0, 14), at(0, 17), asleep: false), [0.85, 0.8125, 0.5], "3 h from full")
        eq(away([1, 1, 1], at(0, 8), at(0, 16), asleep: false), [0.6, 0.5, 0.2], "8 h from full (attention on the floor)")
        eq(away([0.5, 0.5, 0.5], at(0, 14), at(0, 17), asleep: false), [0.65, 0.3125, 0.2], "3 h from 0.5 (thirst 0.5 - 3/16 = 0.3125)")
        eq(away([0.5, 0.5, 0.5], at(0, 8), at(0, 16), asleep: false), [0.2, 0.2, 0.2], "8 h from 0.5: hunger 0.1 and thirst 0.0 sit on the floor")
        eq(away([1, 1, 1], at(0, 12), at(0, 13), asleep: false), [0.95, 0.9375, 1 - 1.0 / 6], "1 h from full")
    }

    func testAwakeAcrossANight() {
        // 23:00 -> 07:00: 7 night hours at half weight + 1 day hour = 4.5 h on the needs
        eq(away([1, 1, 1], at(0, 23), at(1, 7), asleep: false), [1 - 4.5 / 20, 1 - 4.5 / 16, 1 - 4.5 / 6], "awake overnight from full")
        eq(away([0.5, 0.5, 0.5], at(0, 23), at(1, 7), asleep: false), [0.5 - 4.5 / 20, 0.5 - 4.5 / 16, 0.2], "awake overnight from 0.5")
    }

    func testAsleepAtLeaveOvernightAndByDayCostTheSamePerHour() {
        let night = away([1, 1, 1], at(0, 23), at(1, 7), asleep: true)      // 8 h
        let day = away([1, 1, 1], at(0, 14), at(0, 22), asleep: true)       // 8 h, one of them (21-22) at night
        eq([night[0], night[1]], [1 - 8.0 / 60, 1 - 8.0 / 48], "asleep overnight, food + water: 8 h on the asleep rates, no night discount on top")
        eq([day[0], day[1]], [night[0], night[1]], "the same food + water per hour by day")
        // attention is unchanged by sleep: it keeps today's night-weighted seconds (4.5 h overnight; 7.5 h for 14:00-22:00, which is on the floor)
        XCTAssertEqual(night[2], 1 - 4.5 / 6, accuracy: 1e-5)
        XCTAssertEqual(day[2], 0.2, accuracy: 1e-5)
        let h = away([0.5, 0.5, 0.5], at(0, 23), at(1, 7), asleep: true)
        eq(h, [0.5 - 8.0 / 60, 0.5 - 8.0 / 48, 0.2], "asleep overnight from 0.5")
        let h2 = away([0.5, 0.5, 0.5], at(0, 14), at(0, 22), asleep: true)
        eq([h2[0], h2[1]], [h[0], h[1]], "same from 0.5 by day")
        // 3 h asleep by day
        eq(away([1, 1, 1], at(0, 14), at(0, 17), asleep: true), [1 - 3.0 / 60, 1 - 3.0 / 48, 0.5], "3 h asleep")
    }

    func testTheFloorHolds() {
        for asleep in [false, true] {
            for days in [3, 14, 400] {
                let out = away([1, 1, 1], at(0, 9), at(days, 9), asleep: asleep)
                for v in out { XCTAssertGreaterThanOrEqual(v, 0.2 - 1e-6); XCTAssertLessThan(v, 0.2 + 1e-6, "a long absence lands on the floor (asleep \(asleep), \(days) d)") }
            }
            // already under the floor: left alone, not lifted
            eq(away([0.05, 0.1, 0.0], at(0, 9), at(0, 17), asleep: asleep), [0.05, 0.1, 0.0], "under the floor stays")
        }
        // asleep: 60 h of food from full reaches the floor only after 0.8 x 60 = 48 h; water after 0.8 x 48 = 38.4 h
        eq(away([1, 1, 1], at(0, 9), at(2, 9), asleep: true), [0.2, 0.2, 0.2], "48 h asleep: both on the floor")
        eq(away([1, 1, 1], at(0, 9), at(1, 9), asleep: true), [1 - 24.0 / 60, 0.5, 0.2], "24 h asleep")
    }

    // MARK: the app: foreground return, cold launch, old saves

    func testForegroundReturnAndColdLaunchAgree() {
        for asleep in [false, true] {
            let leave = at(0, 23), back = at(1, 7)
            let want = away([1, 1, 1], leave, back, asleep: asleep)
            // foreground: leave -> return
            let d1 = suite()
            let a = make(d1, now: leave)
            a.leaveActive(at: leave, asleep: asleep)
            a.leaveActive(at: leave.addingTimeInterval(60), asleep: !asleep)           // inactive, then background: the first leave wins, flag included
            a.returnActive(at: back)
            eq(lv(a), want, "foreground, asleep \(asleep)")
            // cold launch: the app was killed while away; a fresh model reads the save
            let d2 = suite()
            let b = make(d2, now: leave)
            b.leaveActive(at: leave, asleep: asleep)
            b.save()                                                                   // (a save while away keeps the frozen flag and the stamp)
            let c = make(d2, now: back)
            XCTAssertEqual(c.lastAway, back.timeIntervalSince(leave), accuracy: 1e-6)
            eq(lv(c), want, "cold launch, asleep \(asleep)")
        }
        // a creature that falls asleep in the room: the periodic save carries the flag as of that save (app killed in the room)
        let d = suite(), t = at(0, 23)
        let r = make(d, now: t); r.setAsleep(true)
        r.step(dt: NeedsTuning.saveEvery + 1)
        let k = make(d, now: at(1, 7))
        let inRoom = Float(NeedsTuning.saveEvery + 1) / Float(0.3 * 3600)          // the in-room drain of the 16 s before the save
        XCTAssertEqual(k.level(.hunger), 1 - inRoom - 8.0 / 60, accuracy: 0.002, "asleep rate (the awake one would leave about 0.76)")
    }

    func testASaveWithoutTheFlagBehavesAsAwake() {
        let d = suite(), leave = at(0, 14), back = at(0, 17)
        d.set(["levels": [1.0, 1.0, 1.0], "time": leave.timeIntervalSince1970] as [String: Any], forKey: NeedsTuning.defaultsKey)          // the old format
        let n = make(d, now: back)
        eq(lv(n), [0.85, 0.8125, 0.5], "old save = awake, new awake rates")
        // and the flag is written from then on
        let saved = d.dictionary(forKey: NeedsTuning.defaultsKey)
        XCTAssertEqual(saved?["asleep"] as? Bool, false)
        // an old snapshot file (no "asleep") decodes as awake
        let json = #"{"version":1,"savedAt":1000,"jellies":[{"id":0,"name":"Bob","color":"blue","levels":[1,1,1],"dirt":0,"sparkle":0,"mood":"happy"}]}"#
        XCTAssertEqual(JellySnapshot.decode(Data(json.utf8))?.jellies.first?.asleep, false)
    }

    func testAPerkThatSlowsANeedStillShortensTheTimeCounted() {
        let leave = at(0, 14), back = at(0, 17)
        let key = NeedsTuning.defaultsKey + ".asleepperk", pk = PerkTuning.key(forNeeds: key)!
        for asleep in [false, true] {
            func run(cozy: Bool) -> [Float] {
                let d = suite()
                let n = make(d, now: leave, key: key)
                for k in NeedKind.allCases { n.set(k, 1) }
                if cozy { let p = JellyPerks(persists: true, defaults: d, key: pk, now: { leave }); p.grant(.cozy) }          // 4 h: covers all 3 h away
                n.leaveActive(at: leave, asleep: asleep)
                n.returnActive(at: back)
                return lv(n)
            }
            let plain = run(cozy: false), cozy = run(cozy: true)
            let hungerH = asleep ? 60.0 : 20.0, thirstH = asleep ? 48.0 : 16.0
            // cozy drains hunger / thirst at 0.8 and attention at 0.5 over the covered 3 h: 3 h x (1 - mul) is credited
            eq(plain, [Float(1 - 3 / hungerH), Float(1 - 3 / thirstH), 0.5], "plain, asleep \(asleep)")
            eq(cozy, [Float(1 - 2.4 / hungerH), Float(1 - 2.4 / thirstH), Float(1 - 1.5 / 6)], "cozy, asleep \(asleep)")
        }
    }

    // MARK: the widget and Siri read the same flag

    func testWidgetProjectionEqualsTheApp() {
        for asleep in [false, true] {
            for (leave, back) in [(at(0, 23), at(1, 7)), (at(0, 14), at(0, 22)), (at(0, 9), at(0, 12))] {
                let start: [Float] = [0.9, 0.8, 0.7]
                let app = make(suite(), now: leave)
                for k in NeedKind.allCases { app.set(k, start[k.rawValue]) }
                app.leaveActive(at: leave, asleep: asleep); app.returnActive(at: back)
                let rec = JellyRecord(id: 0, name: "Bob", color: "blue", levels: start, dirt: 0, sparkle: 0, mood: "happy", asleep: asleep)
                let snap = JellySnapshot(savedAt: leave, jellies: [rec])
                let widget = snap.projectNightAware(at: back, calendar: cal)[0].levels
                eq(widget, lv(app), "widget == app (asleep \(asleep), \(leave) -> \(back))")
                // the file round trip keeps the flag
                let back2 = JellySnapshot.decode(snap.encoded()!)!
                XCTAssertEqual(back2.jellies[0].asleep, asleep)
                eq(back2.projectNightAware(at: back, calendar: cal)[0].levels, widget)
            }
        }
    }

    func testTheSnapshotCarriesTheFlagFromTheBridgeInput() {
        var i = WidgetBridge.Input(id: 0, name: "Bob", color: "blue", levels: [1, 1, 1], dirt: 0, sparkle: 0)
        XCTAssertFalse(WidgetBridge.record(i, look: "").asleep)
        i.asleep = true
        XCTAssertTrue(WidgetBridge.record(i, look: "").asleep)
        XCTAssertNotEqual(WidgetBridge.stateKey([i]), WidgetBridge.stateKey([WidgetBridge.Input(id: 0, name: "Bob", color: "blue", levels: [1, 1, 1], dirt: 0, sparkle: 0)]), "a nap starting republishes")
    }

    // MARK: time that passes INSIDE the app keeps the old numbers

    func testTripClockAndSkippedNightKeepTheOldInAppRates() {
        XCTAssertEqual(NeedsTuning.inAppAwayHours, [10, 8, 6], "the pre-change away curve, as on d7e30c42")
        // the skipped night (6 h): hunger 1 - 6/10, thirst 1 - 6/8, attention 1 - 6/6 -> the floor
        let n = BlobNeeds(persists: false); Self.keep.append(n)
        for k in NeedKind.allCases { n.set(k, 1) }
        n.applyInAppTime(seconds: GameClockTuning.skippedNightAway)
        eq(lv(n), [0.4, 0.25, 0.2], "skipped night")
        // the trip clock (2700 s) through GameCare.tripReturned: hunger 1 - 0.75/10, thirst 1 - 0.75/8, attention 1 - 0.75/6
        let care = GameCare(jellyCount: 1, persistent: false)
        for k in NeedKind.allCases { care.jellies[0].needs.set(k, 1) }
        care.tripReturned([0])
        eq(lv(care.jellies[0].needs), [0.925, 0.90625, 0.875], "trip clock")
        // and it never depends on the leave rates
        XCTAssertNotEqual(NeedsTuning.inAppAwayHours, NeedsTuning.awakeAwayHours)
    }
}
