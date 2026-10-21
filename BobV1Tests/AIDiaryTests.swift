//
//  AIDiaryTests.swift
//  EventLog persistence and pruning; the template diary for each personality (non-empty, varied across days, uses the top events); the safety
//  filter on model text; the DiaryBook's daily schedule with a mock writer (and its fallback); the thought-line scheduler and templates.
//

import XCTest
@testable import BobV1

@MainActor
final class AIDiaryTests: XCTestCase {
    private var suites: [String] = []
    private func suite() -> UserDefaults { let n = "AIDiaryTests.\(UUID().uuidString)"; suites.append(n); return UserDefaults(suiteName: n)! }
    override func tearDown() { for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }; suites = [] }

    private let names: (Int) -> String = { ["Bob", "Pip", "Moss"][$0] }
    private let roster = [(0, "Bob"), (1, "Pip"), (2, "Moss")]

    // MARK: event log

    func testEventLogPersistsAndPrunesToSevenDays() {
        let d = suite()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)      // 2027-01-15
        let log = EventLog(defaults: d, persists: true, now: { clock })
        log.record(.ate, jelly: 0, detail: "Berries")
        log.record(.napped, jelly: 1)
        log.record(.social, jelly: 0, detail: "zoomies", partner: 1, at: clock.addingTimeInterval(-6 * 86_400))
        log.record(.tripped, jelly: 2, at: clock.addingTimeInterval(-9 * 86_400))        // too old already: pruned on record
        XCTAssertEqual(log.events.count, 3)
        log.save()
        let again = EventLog(defaults: d, persists: true, now: { clock })
        XCTAssertEqual(again.events.map(\.kind), [.social, .ate, .napped].sorted { $0.rawValue < $1.rawValue } == again.events.map(\.kind).sorted { $0.rawValue < $1.rawValue } ? again.events.map(\.kind) : [])
        XCTAssertEqual(again.events(jelly: 0, day: again.today).map(\.detail), ["Berries"])
        XCTAssertEqual(again.days(jelly: 0).count, 2)
        // 2 days later the 6-day-old social is 8 days old: gone on prune
        clock = clock.addingTimeInterval(2 * 86_400)
        again.prune()
        XCTAssertEqual(again.events.map(\.kind), [.ate, .napped])
        // the cap
        for _ in 0..<(EventLog.cap + 20) { again.record(.cuddled, jelly: 0) }
        XCTAssertEqual(again.events.count, EventLog.cap)
        again.clear()
        XCTAssertTrue(EventLog(defaults: d, persists: true, now: { clock }).events.isEmpty)
    }

    func testEventLogPeriodicSaveAndFacts() {
        let d = suite()
        let log = EventLog(defaults: d, persists: true)
        log.record(.ate, jelly: 0, detail: "Pizza"); log.record(.ate, jelly: 0, detail: "Pizza")
        log.record(.raced, jelly: 0, detail: "2nd"); log.record(.social, jelly: 0, detail: "booped noses", partner: 2)
        XCTAssertNil(d.data(forKey: EventLog.defaultsKey), "not written on every record")
        log.tick(dt: 3.5)
        XCTAssertNotNil(d.data(forKey: EventLog.defaultsKey), "written a few seconds later")
        let facts = EventLog.facts(log.events(jelly: 0), names: names)
        XCTAssertEqual(facts, ["ate Pizza (2 times)", "raced and came 2nd", "booped noses with Moss"])
        XCTAssertNotNil(log.since(.ate, jelly: 0)); XCTAssertNil(log.since(.napped, jelly: 0))
    }

    // MARK: templates

    private func sample(_ jelly: Int, day: Date) -> [JellyEvent] {
        [JellyEvent(jelly: jelly, kind: .ate, detail: "Berries", date: day), JellyEvent(jelly: jelly, kind: .ate, detail: "Berries", date: day),
         JellyEvent(jelly: jelly, kind: .napped, date: day), JellyEvent(jelly: jelly, kind: .social, detail: "zoomies", partner: (jelly + 1) % 3, date: day),
         JellyEvent(jelly: jelly, kind: .tripped, date: day)]
    }

    func testTemplateDiaryForEveryPersonalityIsNonEmptyAndVariedAcrossDays() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for p in JellyPersonality.allCases {
            var texts: Set<String> = []
            for dayN in 0..<7 {
                let day = base.addingTimeInterval(Double(dayN) * 86_400)
                let key = EventLog.dayKey(day)
                let t = TemplateDiary.entry(name: p.word, personality: p, events: sample(0, day: day), day: key, names: names)
                XCTAssertFalse(t.isEmpty, "\(p)")
                let sentences = t.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                XCTAssertTrue((3...6).contains(sentences.count), "\(p) day \(dayN): \(t)")
                XCTAssertTrue(t.lowercased().contains("berries"), "the top event is in: \(t)")
                XCTAssertLessThanOrEqual(t.count, DiarySafety.maxChars + 80, "\(t.count)")
                XCTAssertEqual(t, TemplateDiary.entry(name: p.word, personality: p, events: sample(0, day: day), day: key, names: names), "deterministic per day")
                texts.insert(t)
            }
            XCTAssertGreaterThanOrEqual(texts.count, 4, "\(p): varied phrasing across 7 days, got \(texts.count)")
            // a quiet day reads nicely too
            let quiet = TemplateDiary.entry(name: p.word, personality: p, events: [], day: "2027-01-01", names: names)
            XCTAssertTrue(quiet.count > 30 && quiet.hasSuffix(".") || quiet.hasSuffix("!"), quiet)
        }
        XCTAssertEqual(JellyPersonality.of(name: "Bob"), .calm); XCTAssertEqual(JellyPersonality.of(name: "Pip"), .energetic)
        XCTAssertEqual(JellyPersonality.of(name: "Moss"), .gentle); XCTAssertEqual(JellyPersonality.of(name: "Lavender"), .dreamy)
        // every event kind has a sentence
        var pick = TemplateDiary.Pick(seed: 1)
        for k in JellyEventKind.allCases {
            let s = TemplateDiary.sentence(JellyEvent(jelly: 0, kind: k, detail: "x", partner: 1, date: base), count: 1, p: .calm, pick: &pick, names: names)
            XCTAssertGreaterThan(s.count, 8, k.rawValue)
        }
    }

    func testDiarySafetyCapsAndRejectsStrangers() {
        let roster = ["Bob", "Pip", "Moss"]
        XCTAssertEqual(DiarySafety.check("  \"I ate berries with Pip. Then I napped!\"  ", roster: roster), "I ate berries with Pip. Then I napped!")
        XCTAssertNil(DiarySafety.check("I played with Rex all afternoon.", roster: roster), "a name that is not in the roster")
        XCTAssertNil(DiarySafety.check("Visit http://example.com for more.", roster: roster))
        XCTAssertNil(DiarySafety.check("ok", roster: roster), "too short")
        let long = (0..<12).map { "Sentence number \($0) is here." }.joined(separator: " ")
        let capped = DiarySafety.check(long, roster: roster)!
        XCTAssertEqual(capped.components(separatedBy: ". ").count, DiarySafety.maxSentences)
        XCTAssertLessThanOrEqual(capped.count, DiarySafety.maxChars)
        XCTAssertNotNil(DiarySafety.check("Moss and I played. Bob watched. I love Mum.", roster: roster), "roster names and allowed words anywhere")
        XCTAssertEqual(ThoughtSafety.check("Zoomies time!", roster: roster), "zoomies time!")
        XCTAssertNil(ThoughtSafety.check("I", roster: roster)); XCTAssertNil(ThoughtSafety.check("one two three four five six seven", roster: roster))
        XCTAssertNil(ThoughtSafety.check("hello Rex my friend", roster: roster)); XCTAssertNil(ThoughtSafety.check("call 555 1234 now", roster: roster))
    }

    // MARK: the book

    func testDiaryBookWritesInTheEveningAndNextMorningAndMarksUnread() async {
        let d = suite()
        var clock = Date(timeIntervalSince1970: 1_800_000_000 + 10 * 3600)          // 10:00 on day 1
        let log = EventLog(defaults: d, persists: false, now: { clock })
        let book = DiaryBook(defaults: d, persists: true, writer: nil, now: { clock })
        log.record(.ate, jelly: 0, detail: "Berries"); log.record(.napped, jelly: 1)
        book.tick(dt: 1, hour: 10, log: log, jellies: roster)
        XCTAssertTrue(book.entries.isEmpty, "not before the evening")
        book.tick(dt: 1, hour: 18.5, log: log, jellies: roster)
        XCTAssertEqual(book.entries.count, 3, "every Jelly gets tonight's entry (quiet ones too)")
        XCTAssertEqual(book.unread, [0, 1, 2])
        XCTAssertTrue(book.entries(jelly: 0)[0].text.lowercased().contains("berries"))
        XCTAssertFalse(book.entries(jelly: 0)[0].smart)
        book.markRead(0)
        XCTAssertEqual(book.unread, [1, 2])
        book.tick(dt: 1, hour: 20, log: log, jellies: roster)
        XCTAssertEqual(book.entries.count, 3, "once per day")
        // the game was closed in the evening of day 2; it opens on the morning of day 3: day 2's entry is written for those with events
        clock = clock.addingTimeInterval(86_400)
        log.record(.tripped, jelly: 2)
        clock = clock.addingTimeInterval(86_400)
        let reopened = DiaryBook(defaults: d, persists: true, writer: nil, now: { clock })
        XCTAssertEqual(reopened.entries.count, 3, "persisted")
        XCTAssertEqual(reopened.unread, [1, 2], "persisted")
        reopened.tick(dt: 1, hour: 9, log: log, jellies: roster)
        XCTAssertEqual(reopened.entries(jelly: 2).count, 2, "Moss gets yesterday's entry")
        XCTAssertEqual(reopened.entries(jelly: 0).count, 1, "Bob had a quiet yesterday: nothing extra in the morning")
        XCTAssertEqual(reopened.entries(jelly: 2)[0].day, EventLog.dayKey(clock.addingTimeInterval(-86_400)))
        // 7-day pruning of entries
        clock = clock.addingTimeInterval(8 * 86_400)
        reopened.prune()
        XCTAssertTrue(reopened.entries.isEmpty)
    }

    func testDiaryBookUsesTheModelWhenAvailableAndFallsBackWhenItMisbehaves() async throws {
        let d = suite()
        let clock = Date(timeIntervalSince1970: 1_800_000_000 + 19 * 3600)
        let log = EventLog(defaults: d, persists: false, now: { clock })
        log.record(.ate, jelly: 0, detail: "Pizza"); log.record(.social, jelly: 0, detail: "zoomies", partner: 1)
        let writer = FakeTextWriter()
        writer.diaryText = "Pizza day! I zoomed around with Pip until we both flopped over. Best day."
        let book = DiaryBook(defaults: d, persists: false, writer: writer, now: { clock })
        book.tick(dt: 1, hour: 19, log: log, jellies: roster)
        for _ in 0..<50 where book.entries.count < 3 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(book.entries.count, 3)
        XCTAssertEqual(book.entries(jelly: 0)[0].text, writer.diaryText)
        XCTAssertTrue(book.entries(jelly: 0)[0].smart)
        XCTAssertEqual(writer.diaryCalls.first, ["ate Pizza", "zoomies with Pip"], "only the day's facts go to the model")
        XCTAssertEqual(book.smartCount, 3)
        // a stranger's name / an error: the template stands
        let d2 = suite()
        let bad = FakeTextWriter(); bad.diaryText = "I went to the park with Rex and Lavender."
        let book2 = DiaryBook(defaults: d2, persists: false, writer: bad, now: { clock })
        book2.tick(dt: 1, hour: 19, log: log, jellies: [(0, "Bob")])
        for _ in 0..<50 where book2.entries.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(book2.entries[0].smart)
        XCTAssertTrue(book2.entries[0].text.lowercased().contains("pizza"))
        let d3 = suite()
        let err = FakeTextWriter(); err.error = AIError.unavailable
        let book3 = DiaryBook(defaults: d3, persists: false, writer: err, now: { clock })
        book3.tick(dt: 1, hour: 19, log: log, jellies: [(0, "Bob")])
        for _ in 0..<50 where book3.entries.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(book3.entries[0].smart)
        // not available: the template at once, no call
        let off = FakeTextWriter(); off.state = .deviceNotEligible
        let book4 = DiaryBook(defaults: suite(), persists: false, writer: off, now: { clock })
        book4.tick(dt: 1, hour: 19, log: log, jellies: [(0, "Bob")])
        XCTAssertEqual(book4.entries.count, 1); XCTAssertTrue(off.diaryCalls.isEmpty); XCTAssertEqual(book4.fallbackCount, 1)
    }

    // MARK: thought lines

    func testThoughtLinesAreRareFitTheMomentAndNeverBlock() {
        let t = ThoughtLines(writer: nil, firstAfter: 10)
        t.minGap = 100
        let m = [(jelly: 0, moment: ThoughtMoment(scene: .idle, personality: .calm), name: "Bob"), (jelly: 1, moment: ThoughtMoment(scene: .zooming, personality: .energetic), name: "Pip")]
        var shown = 0
        for _ in 0..<(60 * 400) { if t.tick(dt: 1.0 / 60, moments: m, blocked: false, roster: ["Bob", "Pip"]) { shown += 1 } }      // 400 s
        XCTAssertTrue((2...4).contains(shown), "at most one every few minutes: \(shown) in 400 s")
        XCTAssertTrue(t.shown.allSatisfy { $0.jelly == 1 }, "the interesting one (zoomies) wins")
        XCTAssertTrue(t.shown.allSatisfy { ThoughtTemplates.lines(ThoughtMoment(scene: .zooming, personality: .energetic)).contains($0.text) })
        XCTAssertTrue(t.shown.allSatisfy { (1...6).contains($0.text.split(separator: " ").count) })
        // blocked: nothing shows
        let b = ThoughtLines(writer: nil, firstAfter: 0)
        for _ in 0..<600 { XCTAssertFalse(b.tick(dt: 0.1, moments: m, blocked: true, roster: [])) }
        // every scene / personality has templates of 1-6 words
        for s in [ThoughtMoment.Scene.napping, .zooming, .playing, .hungry, .thirsty, .lonely, .justAte, .justBathed, .grumpy, .night, .morning, .idle] {
            for p in JellyPersonality.allCases {
                let lines = ThoughtTemplates.lines(ThoughtMoment(scene: s, personality: p))
                XCTAssertFalse(lines.isEmpty); for l in lines { XCTAssertLessThanOrEqual(l.split(separator: " ").count, 6, l) }
            }
        }
    }

    func testThoughtLinesReadTheModelCacheOnlyFromTheTick() async throws {
        let w = FakeTextWriter(); w.thoughtLines = ["so cosy right now", "Rex is my friend", "nap o clock"]
        let t = ThoughtLines(writer: w, firstAfter: 0)
        let m = [(jelly: 0, moment: ThoughtMoment(scene: .napping, personality: .calm), name: "Bob")]
        XCTAssertTrue(t.tick(dt: 1, moments: m, blocked: false, roster: ["Bob"]), "the first line is a template (the cache is empty) and the fetch starts")
        XCTAssertEqual(t.fromModel, 0)
        for _ in 0..<50 where w.thoughtCalls.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        try await Task.sleep(nanoseconds: 50_000_000)
        t.debugShowNow()
        for _ in 0..<300 { t.tick(dt: 0.1, moments: m, blocked: false, roster: ["Bob"]) }       // the line on screen ages out, then the next shows
        XCTAssertEqual(t.fromModel, 1, "the next line came from the cache")
        XCTAssertEqual(t.shown.last?.text, "so cosy right now", "the stranger's line was filtered out")
    }
}
