//
//  StoryTemplatesTests.swift
//  10,000 generated blurbs and notes over randomised facts: every one passes the guard (with the real names in), lengths in range, no immediate repeats, variety.
//

import XCTest
@testable import BobV1

final class StoryTemplatesTests: XCTestCase {
    static let names = ["Berry", "Latte", "Mochi", "Pip", "Bob", "Moss", "Zo", "Fluffernutter", "Bubbles", "Tiger", "Kiss", "Ignore rules", "Max2", "BOB", "Jelly-Bean", "O'Malley"]
    static let kinds = ["Blue Jelmiko", "Blush", "Moo", "Teddy", "Opal"]
    static let pers = ["bouncy", "cuddly", "curious", "sleepy", "giggly", "brave", "gentle", "cheeky"]
    static let foods = Array(StoryPhrases.food.keys).sorted()
    static let acts = Array(StoryPhrases.activity.keys).sorted()
    static let spots = ["window", "rug", "couch", "front"]
    static let tiers = ["Puddle", "Ripple", "Splash", "Wave", "Tsunami"]

    struct RNG: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s ^ (s >> 29) } }

    static func randomFacts(_ g: inout RNG) -> StoryFacts {
        func pick<T>(_ a: [T]) -> T { a[Int(g.next() % UInt64(a.count))] }
        func chance(_ p: Double) -> Bool { Double(g.next() % 1000) / 1000 < p }
        var f = StoryFacts(id: Int(g.next() % 6), name: pick(names), kindName: pick(kinds), kindAbout: "", shownParagraph: "Pale pink with rose patches. Shy at first, then the friendliest one in the room.", mood: pick(["happy", "hungry", "sleepy", ""]))
        f.personality = chance(0.9) ? pick(pers) : nil
        f.favouriteFood = chance(0.8) ? pick(foods) : nil
        f.newcomer = chance(0.2)
        f.minutesSeen = f.newcomer ? Int(g.next() % 4) : Int(g.next() % 200)
        if !f.newcomer && chance(0.7) { f.favouriteActivity = pick(acts); f.favouriteActivityKind = "solo" }
        if !f.newcomer && chance(0.5) { f.favouriteSpot = pick(spots) }
        if chance(0.4) { f.trophies.raceWins = Int(g.next() % 6) + 1; f.trophies.bestRaceTier = pick(tiers) }
        if chance(0.2) { f.trophies.showCups = 1; f.trophies.bestShowRank = pick(["Puddle", "Pond", "Lagoon", "Ocean"]) }
        if chance(0.15) { f.trophies.volleyWins = 2 }
        if chance(0.3), f.trophies.total > 0 { f.trophies.recentDaysAgo = Int(g.next() % 12) }
        if chance(0.3) { f.sleepHabit = "naps" }
        f.daysTracked = Int(g.next() % 15)
        let nh = Int(g.next() % 3)
        for i in 0..<nh {
            let secs = chance(0.3) ? 0 : Int(g.next() % 900)
            f.housemates.append(.init(id: 10 + i, name: pick(names), kindName: pick(kinds), playShare: Double(g.next() % 100) / 100, togetherSeconds: secs, topEmote: chance(0.6) ? pick(["chase", "dance", "highFive", "cuddle", "pass", "hopAlong", "nuzzle", "boop"]) : nil))
        }
        if f.housemates.contains(where: { $0.togetherSeconds >= 60 }) { f.togetherShare = 0.2 }
        StoryFactsBuilder.markMostPlayed(&f)
        return f
    }

    func testTenThousandBlurbsAndNotesAllPassTheGuard() {
        XCTAssertGreaterThanOrEqual(StoryTemplates.aboutBank.count, 40)
        XCTAssertGreaterThanOrEqual(StoryTemplates.noteBank.count, 25)
        var g = RNG(s: 42)
        let memory = StoryMemory(salt: 7)
        var aboutCount = 0, noteCount = 0, rejectedInside = 0, skippedEmpty = 0
        var distinctAbout = Set<String>(), distinctNote = Set<String>()
        var lastAbout: [Int: String] = [:], lastNote: [String: String] = [:], immediate = 0
        var maxAbout = 0, maxNote = 0
        while aboutCount < 10_000 || noteCount < 10_000 {
            let f = Self.randomFacts(&g)
            if aboutCount < 10_000 {
                let key = TemplateWriter.aboutKey(f.id)
                guard let w = StoryTemplates.about(f, used: memory.usedSet(key), seed: memory.nextSeed(key)) else {
                    XCTAssertTrue(StoryFill.facts(f).isEmpty, "no line although the sheet has facts: \(f)")          // a Jelmiko with nothing true to say gets no line (the slot is hidden)
                    skippedEmpty += 1; if skippedEmpty > 100_000 { return }; continue
                }
                memory.remember(key, w.ids, bankSize: StoryTemplates.aboutBank.count)
                rejectedInside += w.rejected
                let v = StoryGuard.check(template: w.template, final: w.final, kind: .about, offered: StoryFill.offered(f), shown: f.shownParagraph, values: StoryFill.values(f), keys: w.keys, available: StoryFill.facts(f))
                XCTAssertTrue(v.passed, "\(w.final) -> \(v)")
                XCTAssertLessThanOrEqual(w.final.count, 90, w.final)
                XCTAssertFalse(w.keys.isEmpty)
                XCTAssertTrue(Set(w.keys).isSubset(of: StoryFill.facts(f)), "\(w.final) names a fact the sheet does not back")
                XCTAssertTrue(w.final.hasSuffix("."), w.final)
                let eligibleCount = StoryTemplates.aboutBank.filter { $0.needs.isSubset(of: StoryTemplates.needs(f)) }.count
                if lastAbout[f.id] == w.template, eligibleCount >= 4 { immediate += 1 }          // (a Jelmiko with one or two true things says them again: that is not a repeat of a pool)
                lastAbout[f.id] = w.template
                distinctAbout.insert(w.template); maxAbout = max(maxAbout, w.final.count); aboutCount += 1
            }
            for h in f.housemates where noteCount < 10_000 {
                let key = TemplateWriter.noteKey(f.id, h.id)
                guard let w = StoryTemplates.friendship(f, with: h, used: memory.usedSet(key), seed: memory.nextSeed(key)) else { XCTFail("no note"); return }
                memory.remember(key, w.ids, bankSize: StoryTemplates.noteBank.count)
                let v = StoryGuard.check(template: w.template, final: w.final, kind: .friendship, offered: StoryFill.offered(f, with: h), values: StoryFill.values(f, with: h), keys: w.keys, available: StoryFill.facts(f, with: h))
                XCTAssertTrue(v.passed, "\(w.final) -> \(v)")
                XCTAssertLessThanOrEqual(w.final.count, 80, w.final)
                let k = "\(f.id)>\(h.id)"
                if lastNote[k] == w.template { immediate += 1 }
                lastNote[k] = w.template
                distinctNote.insert(w.template); maxNote = max(maxNote, w.final.count); noteCount += 1
            }
        }
        print("[story-test] blurbs \(aboutCount) distinct templates \(distinctAbout.count), notes \(noteCount) distinct \(distinctNote.count), rejected inside \(rejectedInside), longest blurb \(maxAbout), longest note \(maxNote), immediate repeats \(immediate)")
        XCTAssertGreaterThan(distinctAbout.count, 40)
        XCTAssertGreaterThanOrEqual(distinctNote.count, 20)
        try? "blurbs \(aboutCount) distinct \(distinctAbout.count), notes \(noteCount) distinct \(distinctNote.count), rejected inside \(rejectedInside), longest blurb \(maxAbout), longest note \(maxNote), immediate repeats \(immediate)".write(toFile: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/e0755ccf-aeea-4c40-b871-1f1d2b621362/scratchpad/story/test_stats.txt", atomically: true, encoding: .utf8)
        XCTAssertLessThan(Double(immediate) / 20_000, 0.05)
    }

    func testNoRepeatUntilTheBankIsThrough() {
        var f = StoryFacts(id: 1, name: "Berry", kindName: "Blush", kindAbout: "", mood: "")
        f.personality = "sleepy"; f.favouriteFood = "cookie"; f.favouriteActivity = "bounce"; f.favouriteSpot = "window"; f.minutesSeen = 90; f.daysTracked = 9
        f.trophies.raceWins = 1; f.trophies.bestRaceTier = "Puddle"; f.sleepHabit = "naps"
        let memory = StoryMemory(salt: 3)
        var seenFirst: [Int] = []
        let eligible = StoryTemplates.aboutBank.filter { $0.needs.isSubset(of: StoryTemplates.needs(f)) }
        XCTAssertGreaterThan(eligible.count, 20)
        for _ in 0..<6 {
            let key = "t"
            let w = StoryTemplates.about(f, used: memory.usedSet(key), seed: memory.nextSeed(key))!
            for id in w.ids { XCTAssertFalse(memory.usedSet(key).contains(id), "pattern \(id) repeated before the bank was through") }
            memory.remember(key, w.ids, bankSize: 100)
            seenFirst.append(w.ids[0])
        }
        XCTAssertEqual(Set(seenFirst).count, seenFirst.count)
    }

    func testTwoJelmikoDoNotReadAlike() {
        var f = StoryFacts(id: 1, name: "Berry", kindName: "Blush", kindAbout: "", mood: "")
        f.personality = "sleepy"; f.favouriteFood = "cookie"; f.favouriteActivity = "bounce"; f.minutesSeen = 90
        var g = f; g.id = 2; g.name = "Latte"
        let a = StoryTemplates.about(f, used: [], seed: StoryTemplates.fnv(["x", "1"]))!, b = StoryTemplates.about(g, used: [], seed: StoryTemplates.fnv(["x", "2"]))!
        XCTAssertNotEqual(a.template, b.template)
    }

    func testABrandNewJelmikoReadsWell() {
        var f = StoryFacts(id: 1, name: "Berry", kindName: "Blush", kindAbout: "", shownParagraph: "Pale pink with rose patches.", mood: "happy")
        f.newcomer = true; f.personality = "shy".isEmpty ? nil : "gentle"
        let w = StoryTemplates.about(f, used: [], seed: 1)!
        print("[story-test] newcomer: \(w.final)")
        XCTAssertTrue(["moved in", "settling in", "getting to know the room"].contains { w.final.contains($0) }, w.final)
        // with nothing at all known (no personality, no food)
        var bare = StoryFacts(id: 2, name: "Pip", kindName: "Blue", kindAbout: "", mood: "")
        bare.newcomer = true
        XCTAssertNotNil(StoryTemplates.about(bare, used: [], seed: 2))
    }

    func testRudeNamesStillGetAGuardedText() {
        var f = StoryFacts(id: 1, name: "Kiss", kindName: "Blush", kindAbout: "", mood: "")
        f.personality = "cheeky"
        let w = StoryTemplates.about(f, used: [], seed: 5)!
        XCTAssertTrue(w.final.contains("Kiss"))                 // the player's own word is shown as theirs
        XCTAssertFalse(StoryGuard.denied(StoryGuard.masked(w.template)) != nil)
        XCTAssertFalse(w.template.contains("Kiss"))              // but the writer never held it
    }
}
