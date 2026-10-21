//
//  WidgetSnapshotTests.swift
//  The widget's logic: snapshot encoding / decoding and file round trip, forward projection (== the TimeAway math, floor 0.2),
//  neediest selection, headlines, the timeline dates, deep-link parsing and the app-side bridge's throttling.
//

import XCTest
@testable import BobV1

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []         // the runtime aborts when these are released (see MelonModel)
    let t0 = Date(timeIntervalSince1970: 4_000_000)
    let hour: TimeInterval = 3600

    private func rec(_ id: Int, _ name: String, _ color: String = "blue", levels: [Float] = [1, 1, 1], dirt: Float = 0, sparkle: Float = 0) -> JellyRecord {
        JellyRecord(id: id, name: name, color: color, levels: levels, dirt: dirt, sparkle: sparkle, mood: AwayMath.mood(of: levels).rawValue)
    }
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("widget-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: encoding

    func testSnapshotRoundTripsAndUsesPlainNumbers() throws {
        let snap = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", levels: [0.4, 0.8, 0.6], dirt: 0.25, sparkle: 0.5), rec(1, "Pip", "yellow")])
        let data = try XCTUnwrap(snap.encoded())
        let back = try XCTUnwrap(JellySnapshot.decode(data))
        XCTAssertEqual(back, snap)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["savedAt"] as? Double, t0.timeIntervalSince1970, "seconds since 1970, not a Date strategy")
        let first = try XCTUnwrap((json["jellies"] as? [[String: Any]])?.first)
        for key in ["id", "name", "color", "levels", "dirt", "sparkle", "mood"] { XCTAssertNotNil(first[key], key) }
        XCTAssertLessThan(data.count, 800, "compact")
    }

    func testDecodingIsTolerantAndClamps() throws {
        let json = #"{"version":1,"savedAt":10,"jellies":[{"id":2,"levels":[2,-1],"dirt":5}]}"#
        let s = try XCTUnwrap(JellySnapshot.decode(Data(json.utf8)))
        let r = try XCTUnwrap(s.jellies.first)
        XCTAssertEqual(r.id, 2); XCTAssertEqual(r.name, "Jelly"); XCTAssertEqual(r.color, "blue")
        XCTAssertEqual(r.levels, [1, 0, 1], "short list padded with full, values clamped to 0...1")
        XCTAssertEqual(r.dirt, 1)
        XCTAssertNil(JellySnapshot.decode(Data("not json".utf8)))
    }

    func testAtMostThreeJelliesAndFileRoundTrip() throws {
        let many = JellySnapshot(savedAt: t0, jellies: (0..<5).map { rec($0, "J\($0)") })
        XCTAssertEqual(many.jellies.count, 3)
        let dir = try tempDir()
        XCTAssertNil(JellySnapshot.read(from: dir), "nothing written yet")
        XCTAssertTrue(many.write(to: dir))
        XCTAssertEqual(JellySnapshot.read(from: dir), many)
        XCTAssertFalse(many.write(to: nil), "no container: a quiet false")
    }

    // MARK: forward projection == the TimeAway math

    func testProjectionMatchesTheAppsAwayMath() {
        let start: [Float] = [1, 0.9, 0.7]
        for h: Double in [0.0, 0.5, 3, 5, 8, 12, 30] {
            let s = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", levels: start, dirt: 0.1, sparkle: 0.4)])
            let p = s.project(at: t0.addingTimeInterval(h * hour))[0]
            XCTAssertEqual(p.levels, BlobNeeds.awayLevels(start, seconds: h * hour), "levels at +\(h) h")
        }
        // and through a real BlobNeeds returning from an absence (it counts night hours at half weight, so compare the night-aware projection)
        let d = UserDefaults(suiteName: "widget.test.\(UUID().uuidString)")!
        let n = BlobNeeds(defaults: d, now: { self.t0 }); Self.keep.append(n)
        for k in NeedKind.allCases { n.set(k, start[k.rawValue]) }
        n.leaveActive(at: t0); n.returnActive(at: t0.addingTimeInterval(4 * hour))
        let p = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", levels: start)]).projectNightAware(at: t0.addingTimeInterval(4 * hour), calendar: .current)[0]
        for k in NeedKind.allCases { XCTAssertEqual(p.levels[k.rawValue], n.level(k), accuracy: 1e-6, "\(k)") }
    }

    func testProjectionFloorsAtPointTwoAndNeverRaises() {
        let s = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", levels: [1, 1, 1]), rec(1, "Pip", levels: [0.1, 0.05, 0.15])])
        for h: Double in [8.0, 24, 336, 9600] {
            let p = s.project(at: t0.addingTimeInterval(h * hour))
            for l in p[0].levels { XCTAssertEqual(l, NeedsTuning.awayFloor, accuracy: 1e-6, "+\(h) h sits on the floor") }
            XCTAssertEqual(p[1].levels, [0.1, 0.05, 0.15], "already below the floor: left alone")
        }
        XCTAssertEqual(NeedsTuning.awayFloor, 0.2)
        // a clock that went backwards counts as nothing
        XCTAssertEqual(s.project(at: t0.addingTimeInterval(-5 * hour))[0].levels, [1, 1, 1])
    }

    func testProjectedDirtAndSparkleMatchGrime() {
        let d = UserDefaults(suiteName: "widget.test.\(UUID().uuidString)")!
        for (h, dirt, sparkle) in [(1.0, Float(0), Float(1)), (3.0, 0.3, 0), (8.0, 0.2, 0.0), (30.0, 0.9, 0)] {
            let g = BlobGrime(persists: true, defaults: d, now: { self.t0 }); Self.keep.append(g)
            g.dirt = dirt; g.sparkle = sparkle
            g.leaveActive(at: t0); g.returnActive(at: t0.addingTimeInterval(h * hour))
            let p = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", dirt: dirt, sparkle: sparkle)]).project(at: t0.addingTimeInterval(h * hour))[0]
            XCTAssertEqual(p.dirt, g.dirt, accuracy: 1e-5, "dirt after \(h) h")
            XCTAssertEqual(p.sparkle, g.sparkle, accuracy: 1e-5, "sparkle after \(h) h")
            XCTAssertEqual(p.coat, g.coat)
        }
    }

    func testHungerCrossesIntoHungryAboutFiveHoursAway() {
        let s = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob")])
        XCTAssertEqual(s.project(at: t0.addingTimeInterval(4 * hour))[0].tier(.food), .normal)
        let p5 = s.project(at: t0.addingTimeInterval(5.2 * hour))[0]
        XCTAssertEqual(p5.tier(.food), .hungry)
        XCTAssertEqual(p5.tier(.heart), .hungry, "attention is lonely by then")
        XCTAssertEqual(p5.headline, "Bob is lonely!", "attention (lowest) is the neediest at 5.2 h")
        XCTAssertNotEqual(p5.tier(.food), .famished, "away never makes him Famished")
    }

    // MARK: neediest and headlines

    func testNeediestJellyAndItem() {
        let s = JellySnapshot(savedAt: t0, jellies: [
            rec(0, "Bob", levels: [0.9, 0.9, 0.9]),
            rec(1, "Pip", levels: [0.9, 0.35, 0.9]),
            rec(2, "Moss", levels: [0.9, 0.9, 0.9], dirt: 0.5),
        ])
        let now = s.project(at: t0)
        XCTAssertEqual(JellyState.neediest(in: now)?.name, "Pip", "Pip (thirst 0.35) and Moss (dirty, 0.5 clean) are both Hungry-tier: the lower level wins")
        XCTAssertEqual(now[1].neediest.care, .water)
        XCTAssertEqual(now[1].headline, "Pip is thirsty!")
        XCTAssertEqual(now[2].neediest.care, .soap)
        XCTAssertEqual(now[2].headline, "Moss is dirty!")
        XCTAssertEqual(now[0].headline, "Bob is happy!")
        XCTAssertFalse(now[0].needsAttention)
        // a Famished item outranks a Hungry one
        let f = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", levels: [0.4, 0.9, 0.9]), rec(1, "Pip", levels: [0.9, 0.9, 0.1])]).project(at: t0)
        XCTAssertEqual(JellyState.neediest(in: f)?.id, 1)
        XCTAssertEqual(f[1].headline, "Pip is neglected!")
        // ties: lowest id; empty list: nil
        let tie = JellySnapshot(savedAt: t0, jellies: [rec(1, "Pip"), rec(0, "Bob")]).project(at: t0)
        XCTAssertEqual(JellyState.neediest(in: tie)?.id, 0)
        XCTAssertNil(JellyState.neediest(in: []))
    }

    func testFilthyCoatSparkleAndTierWords() {
        let sp = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", sparkle: 1)]).project(at: t0)[0]
        XCTAssertEqual(sp.headline, "Bob is sparkling!")
        let fi = JellySnapshot(savedAt: t0, jellies: [rec(0, "Bob", dirt: 0.8)]).project(at: t0)[0]
        XCTAssertEqual(fi.tier(.soap), .famished)
        XCTAssertEqual(fi.headline, "Bob is filthy!")
        XCTAssertEqual(fi.word(.soap), "Filthy")
        XCTAssertEqual(NeedTier.of(level: 0.5), .normal)
        XCTAssertEqual(NeedTier.of(level: 0.499), .hungry)
    }

    // MARK: timeline

    func testTimelineIsEveryThirtyMinutesForTwelveHours() {
        let d = JellyTimeline.entryDates(from: t0)
        XCTAssertEqual(d.count, 25)
        XCTAssertEqual(d.first, t0)
        XCTAssertEqual(d.last, t0.addingTimeInterval(12 * hour))
        for (a, b) in zip(d, d.dropFirst()) { XCTAssertEqual(b.timeIntervalSince(a), 1800) }
    }

    // MARK: deep link

    func testDeepLinkParsing() {
        for id in 0..<3 { XCTAssertEqual(JellyLink.parse(JellyLink.url(for: id)), id) }
        XCTAssertEqual(JellyLink.url(for: 1).absoluteString, "jelbies://jelly/1")
        XCTAssertEqual(JellyLink.parse(URL(string: "JELBIES://Jelly/2")!), 2)
        XCTAssertEqual(JellyLink.parse(URL(string: "jelbies://jelly/1/")!), 1)
        for bad in ["jelbies://jelly", "jelbies://jelly/3", "jelbies://jelly/-1", "jelbies://jelly/x", "jelbies://jelly/1/2", "jelbies://pet/1", "https://jelly/1", "jelbies://", "other://jelly/0"] {
            XCTAssertNil(JellyLink.parse(URL(string: bad)!), bad)
        }
    }

    func testDeepLinkSelectHookHighlightsTheJelly() {
        let sel = BlobSelect(); Self.keep.append(sel)
        sel.setBlobs([SelectBlob(id: 0, name: "Bob"), SelectBlob(id: 1, name: "Pip")])
        sel.highlight(JellyLink.parse(URL(string: "jelbies://jelly/1")!)!)
        XCTAssertEqual(sel.drawStarts, 1)
        sel.highlight(2)                       // not in the roster: ignored
        XCTAssertEqual(sel.drawStarts, 1)
    }

    // MARK: the app-side bridge

    private func input(_ id: Int = 0, hunger: Float = 1, dirt: Float = 0, sparkle: Float = 0, color: String = "blue") -> WidgetBridge.Input {
        WidgetBridge.Input(id: id, name: ["Bob", "Pip", "Moss"][id], color: color, levels: [hunger, 1, 1], dirt: dirt, sparkle: sparkle)
    }

    func testBridgeWritesSnapshotAndThrottlesReloads() throws {
        let dir = try tempDir()
        var clock = t0, reloads = 0
        let b = WidgetBridge(directory: dir, now: { clock }, rendersPortraits: false, reload: { reloads += 1 }); Self.keep.append(b)
        b.publish([input()], force: false)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(JellySnapshot.read(from: dir)?.jellies.first?.name, "Bob")
        XCTAssertEqual(JellySnapshot.read(from: dir)?.date, t0)
        clock = t0.addingTimeInterval(20)
        b.publish([input(hunger: 0.4)], force: false)
        XCTAssertEqual(reloads, 1, "within a minute: written, not reloaded")
        XCTAssertEqual(JellySnapshot.read(from: dir)?.jellies.first?.levels.first, 0.4, "the snapshot itself is always current")
        clock = t0.addingTimeInterval(70)
        b.tick(dt: 11) { [self] in [input(hunger: 0.4)] }
        XCTAssertEqual(reloads, 2, "the pending reload is flushed by the next check after a minute")
        clock = t0.addingTimeInterval(80)
        b.leftActive([input(hunger: 0.3)])
        XCTAssertEqual(reloads, 3, "leaving: unthrottled")
        XCTAssertEqual(JellySnapshot.read(from: dir)?.jellies.first?.levels.first, 0.3)
    }

    func testBridgePublishesOnTierChangeOrHeartbeatOnly() throws {
        let dir = try tempDir()
        var clock = t0
        let b = WidgetBridge(directory: dir, now: { clock }, rendersPortraits: false, reload: {}); Self.keep.append(b)
        b.tick(dt: 10) { [self] in [input()] }
        XCTAssertEqual(b.writes, 1, "first check publishes")
        clock = t0.addingTimeInterval(30)
        b.tick(dt: 10) { [self] in [input(hunger: 0.95)] }
        XCTAssertEqual(b.writes, 1, "no tier change (Full -> Full): nothing")
        clock = t0.addingTimeInterval(60)
        b.tick(dt: 10) { [self] in [input(hunger: 0.4)] }
        XCTAssertEqual(b.writes, 2, "Full -> Hungry")
        clock = t0.addingTimeInterval(400)
        b.tick(dt: 10) { [self] in [input(hunger: 0.4)] }
        XCTAssertEqual(b.writes, 3, "heartbeat")
        b.tick(dt: 3) { [self] in XCTFail("not due"); return [] }
    }

    func testPortraitLookKeyChangesOnlyWhenTheLookDoes() {
        let k = WidgetBridge.lookKey
        XCTAssertEqual(k(input(dirt: 0.11)), k(input(dirt: 0.19)), "same 0.1 step")
        XCTAssertNotEqual(k(input(dirt: 0.19)), k(input(dirt: 0.21)))
        XCTAssertNotEqual(k(input(sparkle: 0)), k(input(sparkle: 1)))
        XCTAssertNotEqual(k(input(color: "blue")), k(input(color: "yellow")))
        XCTAssertEqual(k(input(hunger: 1)), k(input(hunger: 0.1)), "hunger does not change the picture")
    }

    func testRecordsCarryMoodAndTheRenderedLook() {
        let s = WidgetBridge.snapshot([input(hunger: 0.1)], at: t0, looks: [0: "x"])
        XCTAssertEqual(s.jellies[0].mood, "grumpy")
        XCTAssertEqual(s.jellies[0].look, "x")
        XCTAssertEqual(s.jellies[0].color, "blue")
    }

    func testGameCarePublishesEveryJellyWithItsOwnState() {
        let d = UserDefaults(suiteName: "widget.care.\(UUID().uuidString)")!
        let care = GameCare(jellyCount: 3, persistent: false, defaults: d); Self.keep.append(care)
        for k in NeedKind.allCases { care.jellies[0].needs.set(k, 1) }      // Bob is seeded hungry on a first launch
        care.jellies[1].needs.set(.thirst, 0.2)
        care.jellies[2].grime.dirt = 0.5
        let ins = care.widgetInputs()
        XCTAssertEqual(ins.map(\.id), [0, 1, 2])
        XCTAssertEqual(ins.map(\.name), ["Bob", "Pip", "Moss"])
        XCTAssertEqual(ins.map(\.color), ["blue", "yellow", "green"])
        XCTAssertEqual(ins[1].levels[NeedKind.thirst.rawValue], 0.2, accuracy: 1e-6)
        XCTAssertEqual(ins[2].dirt, 0.5, accuracy: 1e-6)
        XCTAssertEqual(ins[0].dirt, 0, accuracy: 1e-6)
        let snap = WidgetBridge.snapshot(ins, at: t0)
        XCTAssertEqual(snap.jellies.count, 3)
        XCTAssertEqual(JellyState.neediest(in: snap.project(at: t0))?.name, "Pip")
    }
}
