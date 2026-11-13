//
//  SiriStatusTests.swift
//  What Siri says: the asleep / hungry answers, the collapsed "everyone is fine" sentence, the name joiner, the report read from a temp
//  App Group folder at day and at night, and the App Shortcuts phrase limits.
//

import XCTest
@testable import BobV1

@MainActor
final class SiriStatusTests: XCTestCase {
    // levels: hunger, thirst, attention
    private let fine: [Float] = [1, 1, 1]
    private func s(_ id: Int, _ name: String, _ levels: [Float] = [1, 1, 1], dirt: Float = 0) -> JellyState {
        let r = JellyRecord(id: id, name: name, color: "blue", levels: levels, dirt: dirt, sparkle: 0, mood: AwayMath.mood(of: levels).rawValue)
        return JellyState(record: r, awaySeconds: 0)
    }
    private let none = "You have not met your Jelbies yet. Open the game to say hello."

    // MARK: names

    func testJoinNames() {
        XCTAssertEqual(JellyStatus.joinNames([]), "")
        XCTAssertEqual(JellyStatus.joinNames(["A"]), "A")
        XCTAssertEqual(JellyStatus.joinNames(["A", "B"]), "A and B")
        XCTAssertEqual(JellyStatus.joinNames(["A", "B", "C"]), "A, B and C")
    }

    // MARK: asleep

    func testAsleepAnswerEmptyRoster() {
        XCTAssertEqual(JellyStatus.asleepAnswer([], sleeping: true), none)
        XCTAssertEqual(JellyStatus.asleepAnswer([], sleeping: false), none)
    }

    func testAsleepAnswerAwake() {
        XCTAssertEqual(JellyStatus.asleepAnswer([s(0, "Lemon")], sleeping: false), "No, Lemon is awake.")
        XCTAssertEqual(JellyStatus.asleepAnswer([s(0, "Lemon"), s(1, "Pip")], sleeping: false), "No, they are awake.")
        XCTAssertEqual(JellyStatus.asleepAnswer([s(0, "A"), s(1, "B"), s(2, "C")], sleeping: false), "No, they are awake.")
    }

    func testAsleepAnswerAsleep() {
        XCTAssertEqual(JellyStatus.asleepAnswer([s(0, "Lemon")], sleeping: true), "Yes, Lemon is asleep.")
        XCTAssertEqual(JellyStatus.asleepAnswer([s(1, "Pip"), s(0, "Lemon")], sleeping: true), "Yes, Lemon and Pip are asleep.")
        XCTAssertEqual(JellyStatus.asleepAnswer([s(0, "A"), s(1, "B"), s(2, "C")], sleeping: true), "Yes, A, B and C are asleep.")
    }

    func testAsleepAnswerAddsWhatWillNeedCare() {
        XCTAssertEqual(JellyStatus.asleepAnswer([s(0, "Lemon"), s(1, "Pip", [0.3, 1, 1])], sleeping: true),
                       "Yes, Lemon and Pip are asleep. Pip will wake up hungry.")
        XCTAssertEqual(JellyStatus.asleepAnswer([s(0, "Lemon", [0.1, 1, 1]), s(1, "Pip", [1, 0.3, 1])], sleeping: true),
                       "Yes, Lemon and Pip are asleep. Lemon will wake up very hungry and Pip will wake up thirsty.")
        XCTAssertEqual(JellyStatus.asleepAnswer([s(0, "Lemon", [1, 1, 0.3])], sleeping: true), "Yes, Lemon is asleep. Lemon will wake up lonely.")
        XCTAssertEqual(JellyStatus.asleepAnswer([s(0, "Lemon", dirt: 0.9)], sleeping: true), "Yes, Lemon is asleep. Lemon will wake up dirty.")
        // awake: no clause, even when hungry
        XCTAssertEqual(JellyStatus.asleepAnswer([s(0, "Lemon", [0.1, 1, 1])], sleeping: false), "No, Lemon is awake.")
    }

    // MARK: hungry

    func testHungryAnswerEmptyRoster() {
        XCTAssertEqual(JellyStatus.hungryAnswer([], sleeping: false), none)
    }

    func testHungryAnswerNobodyHungry() {
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "Lemon")], sleeping: false), "No, Lemon is full.")
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "Lemon"), s(1, "Pip")], sleeping: false), "No, everyone has eaten.")
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "A"), s(1, "B"), s(2, "C")], sleeping: true), "No, everyone has eaten.")
        // normal tier and a lonely Jelbie are not hungry
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "Lemon", [0.6, 0.6, 0.3])], sleeping: false), "No, Lemon is full.")
    }

    func testHungryAnswerFoodAndWater() {
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "Lemon", [0.3, 1, 1])], sleeping: false), "Yes, Lemon is hungry.")
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "Lemon", [1, 0.3, 1])], sleeping: false), "Yes, Lemon is thirsty.")
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "Lemon", [0.3, 0.3, 1])], sleeping: false), "Yes, Lemon is hungry and thirsty.")
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "Lemon", [0.3, 1, 1]), s(1, "Pip", [1, 0.3, 1])], sleeping: false),
                       "Yes, Lemon is hungry and Pip is thirsty.")
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "Lemon", [0.3, 1, 1]), s(1, "Pip")], sleeping: false), "Yes, Lemon is hungry.")
    }

    func testHungryAnswerFamishedTier() {
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "Lemon", [0.1, 1, 1])], sleeping: false), "Yes, Lemon is very hungry.")
        XCTAssertEqual(JellyStatus.hungryAnswer([s(0, "Lemon", [1, 0.1, 1])], sleeping: false), "Yes, Lemon is very thirsty.")
    }

    func testHungryAnswerThreeJelbies() {
        let a = JellyStatus.hungryAnswer([s(0, "Lemon", [0.1, 1, 1]), s(1, "Pip", [1, 0.3, 1]), s(2, "Moss")], sleeping: false)
        XCTAssertEqual(a, "Yes, Lemon is very hungry and Pip is thirsty.")
        let b = JellyStatus.hungryAnswer([s(0, "A", [0.3, 1, 1]), s(1, "B", [1, 0.3, 1]), s(2, "C", [0.1, 1, 1])], sleeping: false)
        XCTAssertEqual(b, "Yes, A is hungry, B is thirsty and C is very hungry.")
    }

    // MARK: collapsed spoken

    func testSpokenCollapsesWhenEveryoneIsFineAndAwake() {
        XCTAssertEqual(JellyStatus.spoken([s(0, "Lemon")], sleeping: false), "Lemon is happy.", "one Jelbie keeps its sentence")
        XCTAssertEqual(JellyStatus.spoken([s(0, "Lemon"), s(1, "Pip")], sleeping: false), "Lemon and Pip are both happy.")
        XCTAssertEqual(JellyStatus.spoken([s(0, "A"), s(1, "B"), s(2, "C")], sleeping: false), "All three are happy.")
        // okay mood (not happy): "doing fine"
        let ok: [Float] = [0.55, 0.55, 0.55]
        XCTAssertEqual(AwayMath.mood(of: ok), .okay)
        XCTAssertEqual(JellyStatus.spoken([s(0, "Lemon", ok), s(1, "Pip", ok)], sleeping: false), "Lemon and Pip are both doing fine.")
        XCTAssertEqual(JellyStatus.spoken([s(0, "A", ok), s(1, "B", ok), s(2, "C", ok)], sleeping: false), "All three are doing fine.")
    }

    func testSpokenDoesNotCollapseWhenSomeoneNeedsCareOrSleeps() {
        XCTAssertEqual(JellyStatus.spoken([s(0, "Lemon", [0.3, 1, 1]), s(1, "Pip")], sleeping: false),
                       "Lemon is a little hungry. Pip is happy.")
        XCTAssertEqual(JellyStatus.spoken([s(0, "Lemon"), s(1, "Pip")], sleeping: true), "Lemon is napping. Pip is napping.")
        XCTAssertEqual(JellyStatus.spoken([], sleeping: false), none)
    }

    func testSpokenThreeWithFamishedAndThirsty() {
        let text = JellyStatus.spoken([s(0, "Lemon", [0.1, 1, 1]), s(1, "Pip", [1, 0.3, 1]), s(2, "Moss")], sleeping: false)
        XCTAssertEqual(text, "Lemon is grumpy: famished. Pip is a little thirsty. Moss is happy.")
    }

    func testWidgetStringsUnchanged() {
        let a = s(0, "Lemon", [0.3, 1, 1])
        XCTAssertEqual(JellyStatus.word(a, sleeping: false), "hungry")
        XCTAssertEqual(JellyStatus.line([a, s(1, "Pip")], sleeping: false), "Lemon is hungry · Pip happy")
        XCTAssertEqual(a.headline, "Lemon is hungry!")
    }

    // MARK: report from a temp App Group folder

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("siri-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func at(_ hour: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 15; c.hour = hour
        return Calendar.current.date(from: c)!
    }
    private func write(_ dir: URL, saved: Date, _ jellies: [JellyRecord]) {
        XCTAssertTrue(JellySnapshot(savedAt: saved, jellies: jellies).write(to: dir))
    }
    private func rec(_ id: Int, _ name: String, _ levels: [Float] = [1, 1, 1]) -> JellyRecord {
        JellyRecord(id: id, name: name, color: "blue", levels: levels, dirt: 0, sparkle: 0, mood: "happy")
    }

    func testReportAtDay() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = at(12)
        write(dir, saved: now, [rec(0, "Lemon"), rec(1, "Pip", [0.3, 1, 1])])
        let r = JelbiesSiriStatus.report(directory: dir, now: now)
        XCTAssertEqual(r.states.map(\.name), ["Lemon", "Pip"])
        XCTAssertFalse(r.sleeping)
        XCTAssertEqual(r.asleepAnswer, "No, they are awake.")
        XCTAssertEqual(r.hungryAnswer, "Yes, Pip is hungry.")
        XCTAssertEqual(r.spoken, "Lemon is happy. Pip is a little hungry.")
    }

    func testReportAtNightAndTuckedIn() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = at(23)
        write(dir, saved: now, [rec(0, "Lemon"), rec(1, "Pip", [0.3, 1, 1])])
        let r = JelbiesSiriStatus.report(directory: dir, now: now)
        XCTAssertTrue(r.sleeping)
        XCTAssertEqual(r.asleepAnswer, "Yes, Lemon and Pip are asleep. Pip will wake up hungry.")
        // tucked in at 19:00 counts as asleep before the night hours start (the night edge is about 20:22)
        let evening = at(19).addingTimeInterval(1800)
        write(dir, saved: evening, [rec(0, "Lemon")])
        XCTAssertFalse(JelbiesSiriStatus.report(directory: dir, now: evening).sleeping)
        XCTAssertTrue(Bedtime.write(at(19), to: dir))
        XCTAssertTrue(JelbiesSiriStatus.report(directory: dir, now: evening).sleeping)
    }

    func testReportWithNoSnapshot() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = JelbiesSiriStatus.report(directory: dir, now: at(12))
        XCTAssertTrue(r.states.isEmpty)
        XCTAssertEqual(r.asleepAnswer, none)
        XCTAssertEqual(r.hungryAnswer, none)
        XCTAssertEqual(r.spoken, none)
    }

    // MARK: App Shortcuts

    func testShortcutLimits() {
        let shortcuts = JelbiesShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 7)
        XCTAssertLessThanOrEqual(shortcuts.count, 10, "Apple allows at most 10 App Shortcuts per app")
    }
}
