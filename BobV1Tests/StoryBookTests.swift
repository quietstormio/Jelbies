//
//  StoryBookTests.swift
//  The schedule with a fake clock, the writer chain and its fallbacks, save / load, the purge on let-go, an old save, names put in at display.
//

import XCTest
@testable import BobV1

@MainActor
final class StoryBookTests: XCTestCase {
    private func suite() -> UserDefaults {
        let n = "story.book.\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!; d.removePersistentDomain(forName: n); return d
    }
    private func facts(id: Int = 1, name: String = "Berry", trophies: Int = 0) -> StoryFacts {
        var f = StoryFacts(id: id, name: name, kindName: "Blush", kindAbout: "", shownParagraph: "Pale pink with rose patches. Shy at first, then the friendliest one in the room.", mood: "happy")
        f.personality = "sleepy"; f.favouriteFood = "cookie"; f.favouriteActivity = "bounce"; f.minutesSeen = 120; f.daysTracked = 9
        f.trophies.raceWins = trophies; f.trophies.bestRaceTier = trophies > 0 ? "Puddle" : nil
        f.housemates = [.init(id: 2, name: "Latte", kindName: "Moo", playShare: 0.9, togetherSeconds: 400, topEmote: "chase", mostPlayedWith: true)]
        f.mostPlayedWithID = 2; f.togetherShare = 0.3
        return f
    }
    /// A writer that answers a fixed text (placeholders) or nothing.
    struct Fake: StoryWriter {
        var name: String
        var aboutText: String?
        var noteText: String?
        var keys: [String] = ["favouriteFood"]
        func about(facts: StoryFacts) async -> StoryAnswer? { aboutText.map { StoryAnswer($0, keys: keys) } }
        func friendship(facts: StoryFacts, with: StoryFacts.Housemate) async -> StoryAnswer? { noteText.map { StoryAnswer($0, keys: ["together"]) } }
    }
    private func book(_ d: UserDefaults, day: Box) -> StoryBook {
        let b = StoryBook(defaults: d)
        b.today = { day.v }; b.busy = { false }; b.lowPower = { false }; b.force = false
        b.chain = StoryChain([TemplateWriter(memory: b.memory)])          // (never the real model in a unit test)
        return b
    }
    final class Box { var v: Int; init(_ v: Int) { self.v = v } }

    // MARK: showing

    func testFirstViewWritesAtOnceAndIsNeverEmpty() {
        let b = book(suite(), day: Box(100))
        let l = b.aboutLine(facts())
        XCTAssertNotNil(l); XCTAssertFalse(l!.text.isEmpty); XCTAssertFalse(l!.byModel)
        XCTAssertEqual(b.aboutLine(facts())?.text, l?.text)          // the saved one is shown again, not rewritten
        let n = b.noteLine(facts(), with: facts().housemates[0])
        XCTAssertNotNil(n)
    }

    func testARenameShowsTheNewName() {
        let b = book(suite(), day: Box(100))
        let first = b.aboutLine(facts(name: "Berry"))!.text
        let second = b.aboutLine(facts(name: "Rosie"))!.text
        XCTAssertEqual(first.replacingOccurrences(of: "Berry", with: "Rosie"), second)
        XCTAssertFalse(b.saved.about["1"]!.template.contains("Berry"))          // the placeholders are what is saved
    }

    // MARK: the schedule

    func testAboutScheduleRules() {
        let e = StoryEntry(template: "{A} is happy.", fingerprint: "x", day: 100)
        XCTAssertFalse(StoryBook.aboutDue(e, fingerprint: "x", today: 100))          // never twice in a day
        XCTAssertFalse(StoryBook.aboutDue(e, fingerprint: "y", today: 100))          // not even when something changed
        XCTAssertFalse(StoryBook.aboutDue(e, fingerprint: "x", today: 101))          // too young and nothing new
        XCTAssertFalse(StoryBook.aboutDue(e, fingerprint: "x", today: 102))
        XCTAssertTrue(StoryBook.aboutDue(e, fingerprint: "x", today: 103))           // 3 days old
        XCTAssertFalse(StoryBook.aboutDue(e, fingerprint: "x", today: 103, rotate: false))          // ...but never just for its age while a Profile is open
        XCTAssertTrue(StoryBook.aboutDue(e, fingerprint: "y", today: 101))           // a day old but something notable changed
        XCTAssertTrue(StoryBook.aboutDue(e, fingerprint: "x", today: 100, news: true))          // a new event may replace it the same day
        XCTAssertTrue(StoryBook.aboutDue(nil, fingerprint: "x", today: 100))
    }
    func testNoteScheduleRules() {
        let e = StoryEntry(template: "They are pals.", fingerprint: "x", day: 100)
        XCTAssertFalse(StoryBook.noteDue(e, fingerprint: "y", today: 100))
        XCTAssertTrue(StoryBook.noteDue(e, fingerprint: "y", today: 101))
        XCTAssertFalse(StoryBook.noteDue(e, fingerprint: "x", today: 106))
        XCTAssertTrue(StoryBook.noteDue(e, fingerprint: "x", today: 107))
        XCTAssertFalse(StoryBook.noteDue(e, fingerprint: "x", today: 107, rotate: false))
    }

    func testFingerprintIgnoresMoodButSeesATrophy() {
        var a = facts(), b = facts()
        b.mood = "hungry"; b.togetherShare = 0.9; b.minutesSeen = 999
        XCTAssertEqual(StoryFingerprint.about(a), StoryFingerprint.about(b))
        a = facts(trophies: 0); b = facts(trophies: 1)
        XCTAssertNotEqual(StoryFingerprint.about(a), StoryFingerprint.about(b))
        var c = facts(); c.favouriteActivity = "sway"
        XCTAssertNotEqual(StoryFingerprint.about(facts()), StoryFingerprint.about(c))
        var d = facts(); d.relationshipLevel = "Best friends"
        XCTAssertNotEqual(StoryFingerprint.about(facts()), StoryFingerprint.about(d))
        var e = facts(); e.mostPlayedWithID = 3
        XCTAssertNotEqual(StoryFingerprint.about(facts()), StoryFingerprint.about(e))
    }

    func testRefreshFollowsTheClockAndTheGate() async {
        let day = Box(100)
        let b = book(suite(), day: day)
        _ = b.aboutLine(facts()); _ = b.noteLine(facts(), with: facts().housemates[0])
        let before = b.saved.about["1"]!.template
        var done = await b.refresh(facts()); XCTAssertEqual(done, [])                                  // same day
        day.v = 101; done = await b.refresh(facts()); XCTAssertEqual(done, [])                         // a day later, nothing new
        done = await b.refresh(facts(trophies: 1)); XCTAssertTrue(done.contains("about"))              // a new trophy
        XCTAssertEqual(b.saved.about["1"]!.day, 101)
        XCTAssertNotEqual(b.saved.about["1"]!.template, before)
        day.v = 102; b.busy = { true }
        done = await b.refresh(facts(trophies: 2)); XCTAssertEqual(done, [], "never during a meal, a Show, a race or a match")
        b.busy = { false }; b.lowPower = { true }
        done = await b.refresh(facts(trophies: 2)); XCTAssertEqual(done, [], "not in Low Power Mode")
        b.lowPower = { false }
        done = await b.refresh(facts(trophies: 2)); XCTAssertTrue(done.contains("about"))
        b.force = true; day.v = 102
        done = await b.refresh(facts(trophies: 2)); XCTAssertTrue(done.contains("about"), "-StoryForce ignores the schedule")
    }

    // MARK: the chain

    func testTheChainTakesTheFirstAcceptableAnswerAndEveryAnswerIsGuarded() async {
        let good = Fake(name: "model", aboutText: "{A} spends a lot of time {SPOT}.", noteText: "{A} and {B} are close friends.", keys: ["favouriteSpot"])
        let tmpl = TemplateWriter(memory: StoryMemory())
        var r = await StoryChain([good, tmpl]).about(facts())
        XCTAssertEqual(r?.writer, "template")          // {SPOT} was not offered for these facts: the guard refused the model's text, the template answered
        XCTAssertEqual(r?.attempts.map(\.writer), ["model", "template"])
        XCTAssertEqual(r?.attempts.first?.verdict, "reject(unknown-placeholder:SPOT)")
        var f = facts(); f.favouriteSpot = "window"
        r = await StoryChain([good, tmpl]).about(f)
        XCTAssertEqual(r?.writer, "model")
        XCTAssertEqual(r?.final, "Berry spends a lot of time by the window.")
        XCTAssertEqual(r?.keys, ["favouriteSpot"])
        // a model that answers nothing, or something bad, falls through
        for bad in [nil, "I like Berry a lot.", "Berry is sick today.", "Berry is VERY happy.", "Berry likes cookies best", "Berry is kissed.", "Berry and the AI model are friends.",
                    "{A} trots over the moment {FOOD} appears.", "{A} likes her {FOOD}.", "{A} likes {FOOD}. {A} likes {SPOT}."] as [String?] {
            r = await StoryChain([Fake(name: "model", aboutText: bad), tmpl]).about(facts())
            XCTAssertEqual(r?.writer, "template", "\(bad ?? "nil")")
        }
        // a line that states no fact, or names one the sheet does not back, is refused
        r = await StoryChain([Fake(name: "model", aboutText: "{A} is a Jelmiko.", keys: []), tmpl]).about(facts())
        XCTAssertEqual(r?.writer, "template"); XCTAssertEqual(r?.attempts.first?.verdict, "reject(no-fact-named)")
        r = await StoryChain([Fake(name: "model", aboutText: "{A} has won a volleyball match.", keys: ["volleyWin"]), tmpl]).about(facts())
        XCTAssertEqual(r?.attempts.first?.verdict, "reject(unknown-fact:volleyWin)")
        // the note too
        let h = facts().housemates[0]
        let n = await StoryChain([Fake(name: "model", aboutText: nil, noteText: "{A} kissed {B}."), tmpl]).friendship(facts(), with: h)
        XCTAssertEqual(n?.writer, "template")
        // nobody answers acceptably: nil (the caller keeps what it has)
        let none = await StoryChain([Fake(name: "model", aboutText: "no"), Fake(name: "other", aboutText: nil)]).about(facts())
        XCTAssertNil(none)
    }

    func testAChainWithAModelStoresWhoWroteIt() async {
        let day = Box(100)
        let b = book(suite(), day: day)
        b.chain = StoryChain([Fake(name: "model", aboutText: "{A} is a {PERS} type.", noteText: "{A} and {B} are close friends.", keys: ["personality"]), TemplateWriter(memory: b.memory)])
        _ = b.aboutLine(facts())                        // the first view is pre-written
        XCTAssertEqual(b.saved.about["1"]!.writer, "template")
        day.v = 101
        let done = await b.refresh(facts())             // the next day the model's turn comes (a pre-written one waits for it)
        XCTAssertTrue(done.contains("about"))
        XCTAssertTrue(b.aboutLine(facts())!.byModel)
        XCTAssertEqual(b.aboutLine(facts())!.text, "Berry is a sleepy type.")
    }

    // MARK: a line that is on screen does not change by itself

    /// A model writer that says it is usable but gives no answer (what the simulator, or a model that refused, looks like): the pre-written line must stay put.
    struct Silent: StoryWriter {
        var name: String { "model" }
        func about(facts: StoryFacts) async -> StoryAnswer? { nil }
        func friendship(facts: StoryFacts, with: StoryFacts.Housemate) async -> StoryAnswer? { nil }
    }

    func testTheSameSheetOpenedFiftyTimesGivesTheSameSentence() async {
        let day = Box(500)
        let b = book(StoryBookTests.suiteFor(self), day: day)
        b.chain = StoryChain([Silent(), TemplateWriter(memory: b.memory)])
        let news = StoryEvent(kind: "bubbles", day: 500)
        var f = facts(); f.today = 500; f.news = news; f.events = [news]
        let first = b.aboutLine(f)!.text
        let note = b.noteLine(f, with: f.housemates[0])!.text
        for i in 0..<50 {
            _ = await b.refresh(f, rotate: i == 0)                // the Profile's loop: only the first ask may rotate
            XCTAssertEqual(b.aboutLine(f)!.text, first, "open \(i)")
            XCTAssertEqual(b.noteLine(f, with: f.housemates[0])!.text, note, "open \(i)")
            // the facts are rebuilt every few seconds: the news item must not change under the same day
            var g = facts(); g.today = 500; g.news = b.newsAvailable(news) ? news : nil; g.events = [news]
            XCTAssertEqual(b.aboutLine(g)!.text, first)
        }
        XCTAssertTrue(first.contains("bubbles"))
    }

    func testAModelLineReplacesAPreWrittenOneOnceAndThenStaysPut() async {
        let day = Box(600)
        let b = book(StoryBookTests.suiteFor(self), day: day)
        b.chain = StoryChain([Fake(name: "model", aboutText: "{A} is a {PERS} type.", noteText: "They play together a lot.", keys: ["personality"]), TemplateWriter(memory: b.memory)])
        let f = facts()
        let pre = b.aboutLine(f)!
        XCTAssertFalse(pre.byModel)                              // the pre-written line is what shows first: the model never delays or blocks it
        _ = await b.refresh(f, rotate: false)
        let after = b.aboutLine(f)!
        XCTAssertTrue(after.byModel); XCTAssertEqual(after.text, "Berry is a sleepy type.")
        for _ in 0..<20 { _ = await b.refresh(f, rotate: false); XCTAssertEqual(b.aboutLine(f)!.text, after.text) }
    }

    static func suiteFor(_ t: XCTestCase) -> UserDefaults { let n = "story.book.\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!; d.removePersistentDomain(forName: n); return d }

    // MARK: save / load / purge / old save

    func testSaveLoadAndOldSave() {
        let d = suite()
        let b = book(d, day: Box(100))
        let t = b.aboutLine(facts())!.text
        _ = b.noteLine(facts(), with: facts().housemates[0])
        let b2 = book(d, day: Box(100))
        XCTAssertEqual(b2.aboutLine(facts())!.text, t)               // loaded, not rewritten
        XCTAssertEqual(b2.saved.salt, b.saved.salt)
        // an old save (nothing under the key) loads empty
        let fresh = StoryBook(defaults: suite())
        XCTAssertTrue(fresh.saved.about.isEmpty && fresh.saved.notes.isEmpty)
        // the pattern memory survives a relaunch
        XCTAssertFalse(b2.memory.snapshot().used.isEmpty)
    }

    func testPurgeOnLetGoRemovesTheBlurbAndEveryNoteNamingIt() {
        let d = suite()
        let b = book(d, day: Box(100))
        _ = b.aboutLine(facts(id: 1)); _ = b.aboutLine(facts(id: 2, name: "Latte"))
        var f1 = facts(id: 1); f1.housemates = [.init(id: 2, name: "Latte", kindName: "Moo")]
        var f2 = facts(id: 2, name: "Latte"); f2.housemates = [.init(id: 1, name: "Berry", kindName: "Blush")]
        var f3 = facts(id: 3, name: "Pip"); f3.housemates = [.init(id: 1, name: "Berry", kindName: "Blush"), .init(id: 2, name: "Latte", kindName: "Moo")]
        _ = b.noteLine(f1, with: f1.housemates[0]); _ = b.noteLine(f2, with: f2.housemates[0])
        _ = b.noteLine(f3, with: f3.housemates[0]); _ = b.noteLine(f3, with: f3.housemates[1])
        XCTAssertEqual(b.saved.notes.count, 4)
        StoryBook.purge(2, d)
        b.defaults = d; b.reload()
        XCTAssertNil(b.saved.about["2"]); XCTAssertNotNil(b.saved.about["1"])
        XCTAssertEqual(Set(b.saved.notes.keys), ["3>1"])                  // every note naming 2, in either direction, is gone
        XCTAssertTrue(b.saved.used.keys.allSatisfy { !$0.contains("2") || $0 == "about.1" || $0 == "note.3>1" })
    }
}
