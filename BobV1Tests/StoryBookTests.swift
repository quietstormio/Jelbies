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
        f.housemates = [.init(id: 2, name: "Latte", kindName: "Moo", playShare: 0.9, togetherSeconds: 700, topEmote: "chase", mostPlayedWith: true)]
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
        let n = b.noteLine(facts(), with: facts().housemates[0])
        XCTAssertNotNil(n); XCTAssertFalse(n!.text.isEmpty); XCTAssertFalse(n!.byModel)
        XCTAssertEqual(b.noteLine(facts(), with: facts().housemates[0])?.text, n?.text)          // the saved one is shown again, not rewritten
    }

    func testARenameShowsTheNewNameInANote() {
        let b = book(suite(), day: Box(100))
        let first = b.noteLine(facts(name: "Berry"), with: facts().housemates[0])!.text
        let second = b.noteLine(facts(name: "Rosie"), with: facts().housemates[0])!.text
        XCTAssertEqual(first.replacingOccurrences(of: "Berry", with: "Rosie"), second)
        XCTAssertFalse(b.saved.notes["1>2"]!.template.contains("Berry"))          // the placeholders are what is saved
    }

    // MARK: the schedule

    func testNoteScheduleRules() {
        let e = StoryEntry(template: "They are pals.", fingerprint: "x", day: 100)
        XCTAssertFalse(StoryBook.noteDue(e, fingerprint: "y", today: 100))
        XCTAssertTrue(StoryBook.noteDue(e, fingerprint: "y", today: 101))
        XCTAssertFalse(StoryBook.noteDue(e, fingerprint: "x", today: 106))
        XCTAssertTrue(StoryBook.noteDue(e, fingerprint: "x", today: 107))
        XCTAssertFalse(StoryBook.noteDue(e, fingerprint: "x", today: 107, rotate: false))
    }

    func testRefreshFollowsTheClockAndTheGate() async {
        let day = Box(100)
        let b = book(suite(), day: day)
        _ = b.noteLine(facts(), with: facts().housemates[0])
        let before = b.saved.notes["1>2"]!.template
        var changed = facts(); changed.housemates[0].topEmote = "cuddle"
        var done = await b.refresh(facts()); XCTAssertEqual(done, [])                                  // same day
        day.v = 101; done = await b.refresh(facts()); XCTAssertEqual(done, [])                         // a day later, nothing new
        done = await b.refresh(changed); XCTAssertTrue(done.contains("note:1>2"))                      // the facts of the pair changed
        XCTAssertEqual(b.saved.notes["1>2"]!.day, 101)
        XCTAssertNotEqual(b.saved.notes["1>2"]!.template, before)
        changed.housemates[0].topEmote = "dance"
        day.v = 102; b.busy = { true }
        done = await b.refresh(changed); XCTAssertEqual(done, [], "never during a meal, a Show, a race or a match")
        b.busy = { false }; b.lowPower = { true }
        done = await b.refresh(changed); XCTAssertEqual(done, [], "not in Low Power Mode")
        b.lowPower = { false }
        done = await b.refresh(changed); XCTAssertTrue(done.contains("note:1>2"))
        b.force = true
        done = await b.refresh(changed); XCTAssertTrue(done.contains("note:1>2"), "-StoryForce ignores the schedule")
    }

    /// The owner removed the living line from the Profile: nothing asks for it or writes it, whatever the writers would say.
    func testRefreshNeverRequestsOrWritesTheRemovedLivingLine() async {
        final class Counter: @unchecked Sendable { var about = 0 }
        struct Counting: StoryWriter {
            let c: Counter
            var name: String { "model" }
            func about(facts: StoryFacts) async -> StoryAnswer? { c.about += 1; return StoryAnswer("{A} is a {PERS} type.", keys: ["personality"]) }
            func friendship(facts: StoryFacts, with: StoryFacts.Housemate) async -> StoryAnswer? { StoryAnswer("{A} and {B} are close friends.", keys: ["together"]) }
        }
        let c = Counter(), day = Box(100)
        let b = book(suite(), day: day)
        b.chain = StoryChain([Counting(c: c), TemplateWriter(memory: b.memory)])
        for d in 100...110 { day.v = d; b.force = d % 2 == 0; _ = await b.refresh(facts(trophies: d - 100), rotate: true) }
        XCTAssertEqual(c.about, 0, "the About line is never requested")
        XCTAssertTrue(b.saved.about.isEmpty, "and nothing is saved under it")
        XCTAssertFalse(b.saved.notes.isEmpty, "the housemate notes are still written")
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
        b.chain = StoryChain([Fake(name: "model", aboutText: nil, noteText: "{A} and {B} are close friends.", keys: ["personality"]), TemplateWriter(memory: b.memory)])
        _ = b.noteLine(facts(), with: facts().housemates[0])                        // the first view is pre-written
        XCTAssertEqual(b.saved.notes["1>2"]!.writer, "template")
        day.v = 101
        let done = await b.refresh(facts())             // the next day the model's turn comes (a pre-written one waits for it)
        XCTAssertTrue(done.contains("note:1>2"))
        XCTAssertTrue(b.noteLine(facts(), with: facts().housemates[0])!.byModel)
        XCTAssertEqual(b.noteLine(facts(), with: facts().housemates[0])!.text, "Berry and Latte are close friends.")
    }

    // MARK: a line that is on screen does not change by itself

    /// A model writer that says it is usable but gives no answer (what the simulator, or a model that refused, looks like): the pre-written line must stay put.
    struct Silent: StoryWriter {
        var name: String { "model" }
        func about(facts: StoryFacts) async -> StoryAnswer? { nil }
        func friendship(facts: StoryFacts, with: StoryFacts.Housemate) async -> StoryAnswer? { nil }
    }

    func testTheSameSheetOpenedFiftyTimesGivesTheSameNote() async {
        let day = Box(500)
        let b = book(StoryBookTests.suiteFor(self), day: day)
        b.chain = StoryChain([Silent(), TemplateWriter(memory: b.memory)])
        let f = facts()
        let note = b.noteLine(f, with: f.housemates[0])!.text
        for i in 0..<50 {
            _ = await b.refresh(f, rotate: i == 0)                // the Profile's loop: only the first ask may rotate
            XCTAssertEqual(b.noteLine(f, with: f.housemates[0])!.text, note, "open \(i)")
        }
    }

    func testAModelNoteReplacesAPreWrittenOneOnceAndThenStaysPut() async {
        let day = Box(600)
        let b = book(StoryBookTests.suiteFor(self), day: day)
        b.chain = StoryChain([Fake(name: "model", aboutText: nil, noteText: "{A} and {B} are close friends.", keys: ["personality"]), TemplateWriter(memory: b.memory)])
        let f = facts(), h = f.housemates[0]
        let pre = b.noteLine(f, with: h)!
        XCTAssertFalse(pre.byModel)                              // the pre-written note is what shows first: the model never delays or blocks it
        _ = await b.refresh(f, rotate: false)
        let after = b.noteLine(f, with: h)!
        XCTAssertTrue(after.byModel); XCTAssertEqual(after.text, "Berry and Latte are close friends.")
        for _ in 0..<20 { _ = await b.refresh(f, rotate: false); XCTAssertEqual(b.noteLine(f, with: h)!.text, after.text) }
    }

    static func suiteFor(_ t: XCTestCase) -> UserDefaults { let n = "story.book.\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!; d.removePersistentDomain(forName: n); return d }

    // MARK: save / load / purge / old save

    func testSaveLoadAndOldSave() {
        let d = suite()
        let b = book(d, day: Box(100))
        let t = b.noteLine(facts(), with: facts().housemates[0])!.text
        let b2 = book(d, day: Box(100))
        XCTAssertEqual(b2.noteLine(facts(), with: facts().housemates[0])!.text, t)               // loaded, not rewritten
        XCTAssertEqual(b2.saved.salt, b.saved.salt)
        // an old save (nothing under the key) loads empty
        let fresh = StoryBook(defaults: suite())
        XCTAssertTrue(fresh.saved.notes.isEmpty)
        // the pattern memory survives a relaunch
        XCTAssertFalse(b2.memory.snapshot().used.isEmpty)
    }

    func testPurgeOnLetGoRemovesTheBlurbAndEveryNoteNamingIt() {
        let d = suite()
        let b = book(d, day: Box(100))
        var f1 = facts(id: 1); f1.housemates = [.init(id: 2, name: "Latte", kindName: "Moo", playShare: 0.8, togetherSeconds: 700)]
        var f2 = facts(id: 2, name: "Latte"); f2.housemates = [.init(id: 1, name: "Berry", kindName: "Blush", playShare: 0.8, togetherSeconds: 700)]
        var f3 = facts(id: 3, name: "Pip"); f3.housemates = [.init(id: 1, name: "Berry", kindName: "Blush", playShare: 0.8, togetherSeconds: 700), .init(id: 2, name: "Latte", kindName: "Moo", playShare: 0.8, togetherSeconds: 700)]
        _ = b.noteLine(f1, with: f1.housemates[0]); _ = b.noteLine(f2, with: f2.housemates[0])
        _ = b.noteLine(f3, with: f3.housemates[0]); _ = b.noteLine(f3, with: f3.housemates[1])
        XCTAssertEqual(b.saved.notes.count, 4)
        var old = StoryBook.load(d)          // an older save still holds About blurbs: the purge removes them too
        old.about = ["1": StoryEntry(template: "{A} is happy.", fingerprint: "x", day: 100), "2": StoryEntry(template: "{A} is happy.", fingerprint: "x", day: 100)]
        d.set(try? JSONEncoder().encode(old), forKey: StoryBook.defaultsKey)
        StoryBook.purge(2, d)
        b.defaults = d; b.reload()
        XCTAssertNil(b.saved.about["2"]); XCTAssertNotNil(b.saved.about["1"])
        XCTAssertEqual(Set(b.saved.notes.keys), ["3>1"])                  // every note naming 2, in either direction, is gone
        XCTAssertTrue(b.saved.used.keys.allSatisfy { !$0.contains("2") || $0 == "about.1" || $0 == "note.3>1" })
    }

    func testTwoNotesOnOneProfileNeverStartWithTheSameWord() {
        var g = StoryTemplatesTests.RNG(s: 99)
        for round in 0..<300 {
            let b = book(suite(), day: Box(100))
            var f = StoryTemplatesTests.randomFacts(&g)
            f.id = 1
            f.housemates = [.init(id: 2, name: "Latte", kindName: "Moo", playShare: 0.8, togetherSeconds: [650, 700, 900][round % 3], topEmote: round % 2 == 0 ? "chase" : "cuddle"),
                            .init(id: 3, name: "Pip", kindName: "Moo", playShare: 0.8, togetherSeconds: [900, 650, 700][round % 3], topEmote: round % 2 == 0 ? "chase" : "dance")]
            let a = b.noteLine(f, with: f.housemates[0])!.text, c = b.noteLine(f, with: f.housemates[1])!.text
            XCTAssertNotEqual(StoryTemplates.firstWord(a), StoryTemplates.firstWord(c), "\(a) / \(c)")
            // and it stays so when shown again
            XCTAssertEqual(b.noteLine(f, with: f.housemates[0])!.text, a); XCTAssertEqual(b.noteLine(f, with: f.housemates[1])!.text, c)
        }
    }

    // MARK: housemate-notes-r1

    private func mate(play: Int = 0, shared: Int = 0, lived: Bool = false, emote: String? = nil, share: Double = 0.9) -> StoryFacts.Housemate {
        var m = StoryFacts.Housemate(id: 2, name: "Latte", kindName: "Moo", playShare: share, togetherSeconds: play, topEmote: emote)
        m.sharedSeconds = shared; m.livedTogether = lived
        return m
    }
    private func pair(_ m: StoryFacts.Housemate) -> StoryFacts { var f = facts(); f.housemates = [m]; f.mostPlayedWithID = m.togetherSeconds >= 60 ? 2 : nil; return f }

    func testAnEstablishedPairHasANoteWithTheModelOff() {
        for m in [mate(play: 700, shared: 900, emote: "chase"), mate(shared: 800), mate(lived: true), mate(play: 90, shared: 400)] {
            let b = book(suite(), day: Box(100))
            let f = pair(m)
            let n = b.noteLine(f, with: f.housemates[0])
            XCTAssertNotNil(n, "\(m)"); XCTAssertFalse(n!.byModel)
            XCTAssertNotEqual(n!.text, "Still finding out")
        }
        let b = book(suite(), day: Box(100)); let f = pair(mate())          // just met: the row's own placeholder
        XCTAssertNil(b.noteLine(f, with: f.housemates[0]))
    }

    func testANoteChangesWhenTheFactsChangeAtMostOncePerDay() async {
        let day = Box(100), b = book(suite(), day: day)
        let few = pair(mate(play: 120, shared: 300)), more = pair(mate(play: 700, shared: 5000, emote: "chase")), cuddly = pair(mate(play: 700, shared: 5000, emote: "cuddle"))
        let first = b.noteLine(few, with: few.housemates[0])!.text
        let r0 = await b.refresh(few, rotate: false); XCTAssertTrue(r0.isEmpty)          // same facts, same day: nothing
        day.v = 101
        let r1 = await b.refresh(few, rotate: false); XCTAssertTrue(r1.isEmpty, "same facts a day later and the Profile open: no change")
        XCTAssertEqual(b.noteLine(few, with: few.housemates[0])!.text, first)
        let r2 = await b.refresh(more, rotate: false); XCTAssertEqual(r2, ["note:1>2"], "a closer pair: the note is rewritten")
        let changed = b.noteLine(more, with: more.housemates[0])!.text
        XCTAssertNotEqual(changed, first)
        let r3 = await b.refresh(cuddly, rotate: false); XCTAssertTrue(r3.isEmpty, "once a day")
        for _ in 0..<5 { XCTAssertEqual(b.noteLine(more, with: more.housemates[0])!.text, changed) }
        day.v = 102
        let r4 = await b.refresh(cuddly, rotate: false); XCTAssertEqual(r4, ["note:1>2"], "the next day a changed favourite shows")
    }

    func testNoFlickerWhenTheFactsCrossAThresholdMidVisit() async {
        let b = book(suite(), day: Box(100))
        var seen: [String] = []
        for i in 0..<12 {
            let f = pair(i < 6 ? mate(shared: 700) : mate(play: 400, shared: 1200, emote: "chase"))          // the pair crosses into play at step 6
            _ = await b.refresh(f, rotate: false)
            seen.append(b.noteLine(f, with: f.housemates[0])!.text)
        }
        var flips = 0; for i in 1..<seen.count where seen[i] != seen[i - 1] { flips += 1 }
        XCTAssertLessThanOrEqual(flips, 1, "\(seen)")
        XCTAssertEqual(Set(seen[6...]).count, 1)
    }

    func testOldHabitsJSONWithoutTheNewKeysStillLoads() throws {
        let json = #"{"act":{"walk":10},"partner":{"2":700},"emote":{"2|chase":300},"area":{},"total":900,"everSeconds":5000,"firstDay":10,"decayDay":20}"#
        let h = try JSONDecoder().decode(StoryHabits.self, from: Data(json.utf8))
        XCTAssertNil(h.near); XCTAssertNil(h.shared)
        XCTAssertEqual(h.sharedEver(with: 2), 700)          // an old save's pair seconds are the floor
        XCTAssertEqual(h.partner["2"], 700)
        let m = StoryFactsBuilder.housemate(h, id: 2, name: "Latte", kind: "Moo", other: h)
        XCTAssertGreaterThanOrEqual(m.sharedSeconds, 600); XCTAssertTrue(m.livedTogether)
        XCTAssertNotEqual(StoryTemplates.tier(m), .few)
    }

    func testNearnessIsRecordedAndNotDecayedAway() {
        var h = StoryHabits()
        for _ in 0..<700 { h.add(activity: "stand", partners: [], area: nil, day: 10, nearby: [2]) }
        XCTAssertEqual(h.near?["2"], 700); XCTAssertEqual(h.sharedEver(with: 2), 700); XCTAssertNil(h.partner["2"])          // not counted as play
        h.decay(toDay: 100)
        XCTAssertEqual(h.sharedEver(with: 2), 700, "a month away does not make them strangers")
        XCTAssertNil(h.near?["2"])
        for _ in 0..<30 { h.add(activity: "pair:chase", partners: [2], area: nil, day: 100, nearby: [2]) }
        XCTAssertEqual(h.sharedEver(with: 2), 730)          // a session second is counted once even when they are also near
    }
}
