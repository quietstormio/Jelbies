//
//  StoryHabitsTests.swift
//  Sampling, the daily decay (by day stamp), the derived facts, saving, old saves, the area test.
//

import XCTest
@testable import BobV1

@MainActor
final class StoryHabitsTests: XCTestCase {
    private func suite() -> UserDefaults {
        let n = "story.habits.\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!; d.removePersistentDomain(forName: n); return d
    }

    func testSamplingCountsSecondsActivityPartnersAndArea() {
        var h = StoryHabits()
        for _ in 0..<100 { h.add(activity: "solo:bounce", partners: [], area: "window", day: 10) }
        for _ in 0..<50 { h.add(activity: "pair:chase", partners: [3], area: "rug", day: 10) }
        for _ in 0..<20 { h.add(activity: "group:conga", partners: [3, 4], area: nil, day: 10) }
        XCTAssertEqual(h.total, 170)
        XCTAssertEqual(h.act["solo:bounce"], 100)
        XCTAssertEqual(h.partner["3"], 70); XCTAssertEqual(h.partner["4"], 20)
        XCTAssertEqual(h.emote["3|chase"], 50); XCTAssertNil(h.emote["3|conga"])          // group time counts as time together, not as a pair emote
        XCTAssertEqual(h.area["window"], 100)
        XCTAssertEqual(h.firstDay, 10)
    }

    func testDecayIsWeeklyByDayStamp() {
        var h = StoryHabits()
        for _ in 0..<1000 { h.add(activity: "solo:bounce", partners: [], area: "rug", day: 100) }
        h.decay(toDay: 100); XCTAssertEqual(h.act["solo:bounce"]!, 1000, accuracy: 0.01)          // same day: nothing
        h.decay(toDay: 101); XCTAssertEqual(h.act["solo:bounce"]!, 800, accuracy: 0.5)
        h.decay(toDay: 108); XCTAssertEqual(h.act["solo:bounce"]!, 800 * powf(0.8, 7), accuracy: 0.5)          // a week away is caught up at the next load
        XCTAssertEqual(h.total, h.act["solo:bounce"]!, accuracy: 0.5)
        h.decay(toDay: 200); XCTAssertTrue(h.act.isEmpty)          // tiny entries go
    }

    func testFixedSize() {
        var h = StoryHabits()
        for p in 0..<50 { for k in 0..<50 { h.add(activity: "pair:k\(k)", partners: [p], area: nil, day: 1) } }
        XCTAssertLessThanOrEqual(h.emote.count, StoryHabits.maxEmoteKeys)
        XCTAssertLessThanOrEqual(h.partner.count, StoryHabits.maxPartnerKeys)
    }

    func testDerivedFacts() {
        var h = StoryHabits()
        for _ in 0..<400 { h.add(activity: "walk", partners: [], area: nil, day: 5) }
        for _ in 0..<300 { h.add(activity: "rest", partners: [], area: "couch", day: 5) }
        for _ in 0..<200 { h.add(activity: "solo:bounce", partners: [], area: "window", day: 5) }
        for _ in 0..<40 { h.add(activity: "solo:sway", partners: [], area: "window", day: 5) }
        for _ in 0..<150 { h.add(activity: "pair:chase", partners: [7], area: "window", day: 5) }
        for _ in 0..<30 { h.add(activity: "pair:dance", partners: [8], area: "rug", day: 5) }
        for _ in 0..<80 { h.add(activity: "pair:dance", partners: [7], area: "rug", day: 5) }
        XCTAssertTrue(h.hasHistory)
        XCTAssertEqual(h.favouriteActivity?.key, "bounce")                  // walking, standing and resting are not "a favourite thing"
        XCTAssertEqual(h.favouriteSpot, "window")
        XCTAssertEqual(h.mostPlayedWith, 7)
        XCTAssertEqual(h.topEmote(with: 7), "chase")
        XCTAssertEqual(h.topEmote(with: 8), "dance")                        // 30 s of one kind is the least that counts
        XCTAssertEqual(h.togetherShare, Double(260) / Double(1200), accuracy: 0.001)
        XCTAssertEqual(h.restShare, 0.25, accuracy: 0.001)
        XCTAssertEqual(h.seconds(with: 7), 230)
        XCTAssertEqual(h.playShare(with: 7), 230.0 / 260.0, accuracy: 0.001)
    }

    func testNotEnoughMeansNoFact() {
        var h = StoryHabits()
        for _ in 0..<20 { h.add(activity: "solo:bounce", partners: [], area: "window", day: 5) }
        XCTAssertFalse(h.hasHistory); XCTAssertNil(h.favouriteActivity); XCTAssertNil(h.favouriteSpot); XCTAssertNil(h.mostPlayedWith)
    }

    func testStoreSavesLoadsAndTheOldSaveIsEmpty() {
        let d = suite()
        let s = StoryHabitStore()
        s.defaults = d; s.resolve = { $0 == 0 ? 5 : ($0 == 1 ? 6 : nil) }; s.today = { 50 }
        for _ in 0..<70 { s.sample(slot: 0, activity: "pair:chase", partnerSlots: [1, 9], area: "rug") }          // slot 9 is not a home Jelmiko: dropped
        s.flush()
        XCTAssertNotNil(d.data(forKey: StoryHabitStore.key(5)))
        XCTAssertEqual(StoryHabitStore.load(5, d).partner["6"], 70)
        XCTAssertNil(StoryHabitStore.load(5, d).partner["9"])
        XCTAssertEqual(StoryHabitStore.load(7, d), StoryHabits())          // an old save (no key) loads empty habits
        // a day later: decayed on load
        let s2 = StoryHabitStore(); s2.defaults = d; s2.today = { 51 }
        XCTAssertEqual(s2.habits(5).act["pair:chase"]!, 56, accuracy: 0.5)
        XCTAssertEqual(StoryHabitStore.key(0), "BlobStats.v1.story"); XCTAssertEqual(StoryHabitStore.key(3), "BlobStats.v1.jelly3.story")
    }

    func testPurgeRemovesTheHabitKey() {
        XCTAssertTrue(JellyCamp.instanceKeys(4).contains(JellyKeys.stats(4) + ".story"))
        // (not run through `JellyCamp.purge`: it reloads the global roster names from the defaults it is given, which would leak into other suites)
        XCTAssertEqual(StoryHabitStore.key(4), JellyKeys.stats(4) + ".story")
    }

    func testAreas() {
        XCTAssertEqual(StorySampling.area(x: 0, z: 0, sofaDistance: 0.5, rugDistance: 0, backZ: -5, frontZ: 3.5), "couch")
        XCTAssertEqual(StorySampling.area(x: 0, z: -4.5, sofaDistance: 3, rugDistance: 4, backZ: -5, frontZ: 3.5), "window")
        XCTAssertEqual(StorySampling.area(x: 0, z: 0, sofaDistance: 3, rugDistance: 1, backZ: -5, frontZ: 3.5), "rug")
        XCTAssertEqual(StorySampling.area(x: 3, z: 3, sofaDistance: 3, rugDistance: 4, backZ: -5, frontZ: 3.5), "front")
        XCTAssertNil(StorySampling.area(x: 4, z: -1, sofaDistance: 3, rugDistance: 4, backZ: -5, frontZ: 3.5))
    }

    /// The sampler's per-second work for one body, measured: the habit counters and the store (the per-tick part is one Float add and one compare).
    func testASecondOfSamplingCostsMicroseconds() {
        let st = StoryHabitStore(); st.defaults = suite(); st.resolve = { $0 }; st.today = { 50 }
        let kinds = ["walk", "stand", "rest", "solo:bounce", "pair:chase", "group:conga", "toy", "solo:sway"]
        let n = 100_000
        let t0 = CFAbsoluteTimeGetCurrent()
        for i in 0..<n { st.sample(slot: i % 3, activity: kinds[i % kinds.count], partnerSlots: i % 3 == 0 ? [1, 2] : [0], area: i % 2 == 0 ? "rug" : "window") }
        let per = (CFAbsoluteTimeGetCurrent() - t0) / Double(n) * 1_000_000
        try? "sampler: \(per) microseconds per body-second (includes the once-a-minute save)".write(toFile: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/e0755ccf-aeea-4c40-b871-1f1d2b621362/scratchpad/story/sampler_cost.txt", atomically: true, encoding: .utf8)
        XCTAssertLessThan(per, 50, "a body-second of sampling must stay in the tens of microseconds")
    }

    func testTheKindOfGroupSessionIsKnownOnlyWhenSampled() {
        var h = StoryHabits()
        for _ in 0..<25 { h.add(activity: "group:groupHug", partners: [7], area: nil, day: 5) }
        for _ in 0..<10 { h.add(activity: "group:conga", partners: [8], area: nil, day: 5) }
        XCTAssertEqual(h.topGroupKind(with: 7), "groupHug")
        XCTAssertNil(h.topGroupKind(with: 8))          // 10 s is not enough to name it
        XCTAssertNil(h.topGroupKind(with: 9))
        var f = StoryFacts(id: 1, name: "Berry", kindName: "Blush", kindAbout: "", mood: "")
        let m = StoryFactsBuilder.housemate(h, id: 7, name: "Latte", kind: "Moo")
        XCTAssertEqual(m.groupKind, "groupHug"); XCTAssertTrue(m.sharedGroup)
        f.housemates = [m]
        XCTAssertFalse(StoryFactsBuilder.housemate(h, id: 8, name: "Pip", kind: "Moo").sharedGroup)
    }
}
