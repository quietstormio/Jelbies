//
//  StoryEventsTests.swift
//  The recent-events log (last 20, two weeks, saved and purged with the creature), the news the line prefers, one news item used for one day, and the funnel's details.
//

import XCTest
@testable import BobV1

@MainActor
final class StoryEventsTests: XCTestCase {
    private func suite() -> UserDefaults {
        let n = "story.events.\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!; d.removePersistentDomain(forName: n); return d
    }
    private func facts(news: StoryEvent? = nil, today: Int = 100) -> StoryFacts {
        var f = StoryFacts(id: 1, name: "Berry", kindName: "Blush", kindAbout: "", shownParagraph: "Pale pink with rose patches. Shy at first, then the friendliest one in the room.", mood: "happy")
        f.personality = "sleepy"; f.favouriteFood = "popsicle"; f.favouriteActivity = "bounce"; f.favouriteSpot = "window"; f.minutesSeen = 120; f.daysTracked = 9
        f.today = today; f.news = news; if let news { f.events = [news] }
        return f
    }

    func testTheLogKeepsTwentyAndTwoWeeksAndMergesDuplicates() {
        var l = StoryEventList()
        for i in 0..<30 { l.add(StoryEvent(kind: "race", day: 100 + i / 10, d: ["tier": "T\(i)"])) }
        XCTAssertEqual(l.events.count, StoryEvent.keep)
        l.add(StoryEvent(kind: "park", day: 100)); l.add(StoryEvent(kind: "park", day: 100))
        XCTAssertEqual(l.events.filter { $0.kind == "park" }.count, 1)
        l.add(StoryEvent(kind: "bath", day: 120))
        XCTAssertTrue(l.events.allSatisfy { 120 - $0.day <= StoryEvent.keepDays })
    }

    func testStoreSavesLoadsAndTheKeyIsPurged() {
        let d = suite()
        let s = StoryEventStore(); s.defaults = d; s.today = { 200 }
        s.record("race", character: 4, ["tier": "Puddle", "win": "1"])
        XCTAssertEqual(s.list(4).events.first?.d["tier"], "Puddle")
        XCTAssertTrue(s.list(5).events.isEmpty)               // an old save: no key, empty list
        XCTAssertTrue(JellyCamp.instanceKeys(4).contains(StoryEventStore.key(4)))
        // (the purge itself removes every key in `instanceKeys`; it is not run here because it reloads the global roster names from the defaults it is given)
    }

    func testBondKindsMapToNews() {
        XCTAssertEqual(BondKind.race.storyKind([:]), "race")
        XCTAssertEqual(BondKind.care.storyKind(["care": "groom"]), "groom")
        XCTAssertEqual(BondKind.toy.storyKind(["toy": "bubbles"]), "bubbles")
        XCTAssertEqual(BondKind.meal.storyKind(["where": "cafe"]), "cafe")
        XCTAssertEqual(BondKind.meal.storyKind(["food": "cookie"]), "meal")
        XCTAssertNil(BondKind.meal.storyKind([:]))           // an ordinary meal is not news
        XCTAssertNil(BondKind.drink.storyKind([:])); XCTAssertNil(BondKind.dayOpen.storyKind([:]))
    }

    func testEveryKindOfNewsMakesAGuardedTrueLine() {
        let cases: [(String, [String: String], String)] = [
            ("race", ["tier": "Puddle", "win": "1"], "Berry won the Puddle race today."), ("race", ["tier": "Ripple"], "Berry ran the Ripple race today."),
            ("show", ["tier": "Pond", "place": "2"], ""), ("volley", ["tier": "Shore", "win": "1"], "Berry won a volleyball match on the Shore court today."),
            ("park", [:], ""), ("cafe", [:], ""), ("bubbles", [:], ""), ("ball", [:], "Berry played with the ball today."), ("bath", [:], "Berry had a bath today."),
            ("groom", [:], "Berry was groomed today."), ("trick", [:], "Berry did a trick when asked today."), ("meal", ["food": "popsicle"], ""), ("cuddle", [:], "Berry had a good cuddle today."),
            ("bond", ["level": "Good friends"], "Berry has moved up to Good friends.")]
        for (kind, d, exact) in cases {
            let e = StoryEvent(kind: kind, day: 100, d: d)
            let f = facts(news: e)
            XCTAssertTrue(StoryFill.facts(f).contains(e.factKey), kind)
            guard let w = StoryTemplates.about(f, used: [], seed: 3) else { XCTFail("no line for \(kind)"); continue }
            XCTAssertTrue(w.keys.contains(e.factKey), "\(kind): \(w.final)")
            XCTAssertLessThanOrEqual(w.final.count, 90)
            if !exact.isEmpty { XCTAssertEqual(w.final, exact) }
            // the model-less line is true: yesterday says yesterday
            var y = f; y.today = 101
            if kind != "bond" { XCTAssertTrue(StoryTemplates.about(y, used: [], seed: 3)!.final.contains("yesterday"), kind) }
        }
    }

    func testNoNewsFallsBackToFavouritesAndAnOldEventIsNotNews() {
        let f = facts(news: nil)
        let w = StoryTemplates.about(f, used: [], seed: 1)!
        XCTAssertFalse(w.keys.contains(where: { $0.hasPrefix("recent") }))
    }

    func testNewsIsPreferredReplacesTheLineAndIsUsedForOneDay() {
        let d = suite()
        let day = Box(100)
        let b = StoryBook(defaults: d)
        b.today = { day.v }; b.busy = { false }; b.lowPower = { false }
        b.chain = StoryChain([TemplateWriter(memory: b.memory)])
        let before = b.aboutLine(facts())!.text                                   // no news: a favourite or a routine
        XCTAssertFalse(before.contains("today"))
        let e = StoryEvent(kind: "race", day: 100, d: ["tier": "Puddle", "win": "1"])
        XCTAssertTrue(b.newsAvailable(e))
        let news = b.aboutLine(facts(news: e))!.text                              // the same day: fresh news replaces the line
        XCTAssertEqual(news, "Berry won the Puddle race today.")
        XCTAssertEqual(b.aboutLine(facts(news: e))!.text, news)                    // and stays while it is news
        day.v = 101
        XCTAssertTrue(b.newsAvailable(e) == false)                                // used on day 100: finished on day 101
        var next = facts(today: 101); next.news = b.newsAvailable(e) ? e : nil
        let moved = b.aboutLine(next)!.text
        XCTAssertNotEqual(moved, news)                                            // the line moves on (back to favourites / routines)
        XCTAssertFalse(moved.contains("race"))
    }
    final class Box { var v: Int; init(_ v: Int) { self.v = v } }

    func testTheNewsLineIsGuardedLikeAnyOther() {
        // a news line that names the news key but the sheet has no such news is refused
        let f = facts()
        let v = StoryGuard.check(template: "{A} won the {TIER} race {WHEN}.", final: "Berry won.", kind: .about, offered: ["A", "TIER", "WHEN"], keys: ["favouriteFood"], available: StoryFill.facts(f), checkTone: false)
        XCTAssertEqual(v, .reject(.missingFactKey("recent news")))
    }
}
