//
//  BondTests.swift
//  The Relationship (Jelly/JellyBond.swift): points from each kind of event, the per-kind and per-day caps, a new day, never going down, save / load, the purge at
//  "Say goodbye", the one-time seed of an old save, and the level names and heart fills at the thresholds. Plus the night wording of the status sentence.
//

import XCTest
@testable import BobV1

@MainActor
final class BondTests: XCTestCase {
    private var suites: [String] = []
    override func tearDown() {
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
    }
    private func suite() -> UserDefaults {
        let s = "BondTests.\(UUID().uuidString)"; suites.append(s)
        return UserDefaults(suiteName: s)!
    }
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!)! }

    // MARK: points and caps

    func testEveryKindGrowsThePoints() {
        let d = suite()
        var last = JellyBond.points(3, d)
        XCTAssertEqual(last, 0, "a new creature starts at nothing")
        for k in BondKind.allCases {
            let add = JellyBond.earn(k, 3, d, now: day(0))
            XCTAssertGreaterThan(add, 0, "\(k)")
            XCTAssertEqual(JellyBond.points(3, d), last + add, "\(k)")
            last += add
        }
    }

    func testFavouriteMealAndWinsPayMore() {
        XCTAssertGreaterThan(BondTuning.points(.meal, favourite: true), BondTuning.points(.meal))
        for k in [BondKind.race, .show, .volley] { XCTAssertGreaterThan(BondTuning.points(k, win: true), BondTuning.points(k), "\(k)") }
    }

    func testPerKindCapHolds() {
        let d = suite()
        for k in BondKind.allCases {
            var sum = 0
            for _ in 0..<40 { sum += JellyBond.earn(k, 1, d, now: day(0)); if JellyBond.points(1, d) >= BondTuning.totalDayCap { break } }
            XCTAssertLessThanOrEqual(JellyBond.today(1, d, now: day(0))[k.rawValue] ?? 0, BondTuning.dayCap(k), "\(k)")
            XCTAssertLessThanOrEqual(sum, BondTuning.dayCap(k))
            JellyBond.remove(1, d)
        }
    }

    func testTotalDayCapHoldsAndTheBondCannotBeMaxedInOneSitting() {
        let d = suite()
        for _ in 0..<50 { for k in BondKind.allCases { JellyBond.earn(k, 2, win: true, d, now: day(0)) } }
        XCTAssertEqual(JellyBond.points(2, d), BondTuning.totalDayCap)
        XCTAssertLessThan(BondLevel(points: JellyBond.points(2, d)).hearts, BondTuning.hearts)
        XCTAssertEqual(JellyBond.earn(.stroke, 2, d, now: day(0)), 0, "nothing more today")
    }

    func testANewDayReopensTheCaps() {
        let d = suite()
        for _ in 0..<10 { JellyBond.earn(.stroke, 4, d, now: day(0)) }
        XCTAssertEqual(JellyBond.today(4, d, now: day(0))["stroke"], BondTuning.dayCap(.stroke))
        XCTAssertEqual(JellyBond.earn(.stroke, 4, d, now: day(0)), 0)
        XCTAssertGreaterThan(JellyBond.earn(.stroke, 4, d, now: day(1)), 0, "tomorrow counts again")
        XCTAssertEqual(JellyBond.today(4, d, now: day(1))["stroke"], BondTuning.points(.stroke))
        XCTAssertEqual(JellyBond.points(4, d), BondTuning.dayCap(.stroke) + BondTuning.points(.stroke))
    }

    func testNothingLowersThePoints() {
        let d = suite()
        for k in BondKind.allCases { JellyBond.earn(k, 5, d, now: day(0)) }
        let p = JellyBond.points(5, d)
        // time away: weeks pass, nothing is earned; the points stay
        XCTAssertEqual(JellyBond.points(5, d), p)
        JellyBond.earn(.dayOpen, 5, d, now: day(40)); XCTAssertGreaterThanOrEqual(JellyBond.points(5, d), p)
        // low needs (a starving creature) never touch the key: the model has no way down, and the needs store does not know the key
        let needs = BlobNeeds(defaults: d, key: JellyKeys.needs(5), persists: true)
        for k in NeedKind.allCases { needs.set(k, 0) }
        needs.save()
        XCTAssertGreaterThanOrEqual(JellyBond.points(5, d), p)
        // a refused event adds nothing and never subtracts
        for _ in 0..<5 { XCTAssertGreaterThanOrEqual(JellyBond.earn(.meal, 5, d, now: day(40)), 0) }
        XCTAssertGreaterThanOrEqual(JellyBond.points(5, d), p)
    }

    func testSaveAndLoadRoundTrip() {
        let d = suite()
        JellyBond.earn(.meal, 7, favourite: true, d, now: day(0))
        JellyBond.earn(.stroke, 7, d, now: day(0))
        let before = JellyBond.points(7, d)
        XCTAssertEqual(before, 8)
        let again = JellyBond.points(7, d)          // a rebuilt profile reads the same
        XCTAssertEqual(again, before)
        XCTAssertEqual(JellyBond.today(7, d, now: day(0)), ["meal": 5, "stroke": 3], "what was already counted today is kept")
        XCTAssertEqual(JellyBond.earn(.meal, 7, d, now: day(0)), 3, "meal cap 9: 5 + 3 fits, the next one is cut at the cap")
        XCTAssertEqual(JellyBond.earn(.meal, 7, d, now: day(0)), 1)
        XCTAssertEqual(JellyBond.earn(.meal, 7, d, now: day(0)), 0)
        XCTAssertEqual(JellyBond.key(0), "BlobBond.v1"); XCTAssertEqual(JellyBond.key(9), "BlobBond.v1.jelly9"); XCTAssertEqual(JellyKeys.bond(9), JellyBond.key(9))
    }

    // MARK: purge

    func testTheKeyIsGoneAfterLetGo() {
        let d = suite()
        d.set([4, 5], forKey: JellyRoster.rosterKey)
        d.set([6], forKey: JellyCamp.key)
        d.set(5000, forKey: DropsWallet.key)
        JellyBond.earn(.meal, 6, d, now: day(0)); JellyBond.earn(.meal, 4, d, now: day(0))
        XCTAssertTrue(JellyCamp.instanceKeys(6).contains(JellyBond.key(6)))
        XCTAssertNotNil(d.object(forKey: JellyBond.key(6)))
        XCTAssertTrue(JellyCamp.letGo(6, d))
        XCTAssertNil(d.object(forKey: JellyBond.key(6)), "the relationship goes with the creature")
        XCTAssertNotNil(d.object(forKey: JellyBond.key(4)), "and nobody else's")
        XCTAssertFalse(JellyCamp.instanceKeys(6).isEmpty)
    }

    func testANewcomersResetClearsAStaleBond() {
        let d = suite()
        JellyBond.earn(.meal, 8, d, now: day(0))
        StartFlow.resetCharacterState(8, d)
        XCTAssertNil(d.object(forKey: JellyBond.key(8)))
    }

    // MARK: the one-time seed of an old save

    func testAnOldSaveWithoutTheKeyIsSeededOnceAndNotAgain() {
        let d = suite()
        // what an old save records for creature 9: two meals in the diary, a race and a win, one learned trick, one trophy
        d.set([0.5, 0.5, 2.0, 1.0], forKey: "BlobStats.v1.jelly9")
        d.set(try! JSONSerialization.data(withJSONObject: [["food": "x", "at": 1.0, "gains": [:]], ["food": "y", "at": 2.0, "gains": [:]]] as [Any]), forKey: "BlobStats.v1.jelly9.meals")
        d.set(try! JSONSerialization.data(withJSONObject: ["tricks": ["come": ["learned": true], "spin": ["learned": false]]]), forKey: "BlobWords.v1.jelly9")
        d.set(try! JSONSerialization.data(withJSONObject: ["9": ["earned": ["first.puddle"]]]), forKey: "Circuit.trophies.v1")
        XCTAssertNil(d.object(forKey: JellyBond.key(9)))
        let expected = 2 * BondTuning.seedMeal + 2 * BondTuning.seedRace + 1 * BondTuning.seedWin + BondTuning.seedTrick + BondTuning.seedTrophy
        XCTAssertEqual(JellyBond.points(9, d), expected)
        XCTAssertNotNil(d.object(forKey: JellyBond.key(9)), "the key is written")
        // more history appears later: the seed is not run again
        d.set([0.5, 0.5, 9.0, 9.0], forKey: "BlobStats.v1.jelly9")
        XCTAssertEqual(JellyBond.points(9, d), expected)
        JellyBond.seedIfNeeded(9, d); XCTAssertEqual(JellyBond.points(9, d), expected)
    }

    func testANewPetIsSeededWithZeroAndStaysFreeOfLaterHistory() {
        let d = suite()
        JellyBond.seedIfNeeded(11, d)
        XCTAssertEqual(JellyBond.points(11, d), 0)
        d.set([0.5, 0.5, 9.0, 9.0], forKey: "BlobStats.v1.jelly11")
        XCTAssertEqual(JellyBond.points(11, d), 0, "the key exists: later races are not a seed")
    }

    func testTheSeedIsCappedInsideHeartFour() {
        let d = suite()
        d.set([0.5, 0.5, 99.0, 99.0], forKey: "BlobStats.v1.jelly12")
        d.set(try! JSONSerialization.data(withJSONObject: [["food": "x", "at": 1.0, "gains": [:]]] as [Any]), forKey: "BlobStats.v1.jelly12.meals")
        let p = JellyBond.points(12, d)
        XCTAssertLessThanOrEqual(p, BondTuning.seedCap)
        XCTAssertLessThan(BondLevel(points: p).hearts, 4, "a seed never gives more than three full hearts")
        XCTAssertGreaterThan(BondLevel(points: p).hearts, 0)
    }

    // MARK: levels and hearts

    func testLevelNamesAndHeartFillsAtTheThresholds() {
        let names = BondTuning.levelNames
        XCTAssertEqual(names, ["Just met", "Getting to know you", "Friends", "Good friends", "Close friends", "Best friends"])
        XCTAssertEqual(BondLevel(points: 0).name, "Just met"); XCTAssertEqual(BondLevel(points: 0).partial, 0)
        for (i, t) in BondTuning.heartFull.enumerated() {
            XCTAssertEqual(BondLevel(points: t - 1).hearts, i, "one below the threshold of heart \(i + 1)")
            XCTAssertEqual(BondLevel(points: t - 1).name, names[i])
            XCTAssertGreaterThan(BondLevel(points: t - 1).partial, 0.9)
            XCTAssertEqual(BondLevel(points: t).hearts, i + 1)
            XCTAssertEqual(BondLevel(points: t).name, names[i + 1])
        }
        let half = BondLevel(points: 40)          // halfway from 20 (heart 1 full) to 60 (heart 2 full)
        XCTAssertEqual(half.hearts, 1); XCTAssertEqual(half.partial, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.fill(0), 1); XCTAssertEqual(half.fill(1), 0.5, accuracy: 1e-9); XCTAssertEqual(half.fill(2), 0)
        let max = BondLevel(points: 5000)
        XCTAssertEqual(max.hearts, 5); XCTAssertEqual(max.partial, 0); XCTAssertEqual(max.name, "Best friends")
        XCTAssertEqual(BondLevel(points: 150).spoken, "Relationship: Good friends, 3 of 5 hearts")
    }

    /// Ordinary play (20 points a day) reaches the hearts on the planned days.
    func testDaysToEachHeartWithOrdinaryPlay() {
        let ordinary: [(BondKind, Bool)] = [(.dayOpen, false), (.stroke, false), (.stroke, false), (.meal, false), (.meal, false), (.drink, false), (.drink, false), (.toy, false), (.trick, false), (.trick, false)]
        let d = suite()
        var reached: [Int: Int] = [:]
        for n in 0..<60 {
            for (k, f) in ordinary { JellyBond.earn(k, 3, favourite: f, d, now: day(n)) }
            let h = BondLevel(points: JellyBond.points(3, d)).hearts
            for i in 1...h where reached[i] == nil { reached[i] = n + 1 }
        }
        XCTAssertEqual(reached[1], 1); XCTAssertEqual(reached[2], 3); XCTAssertEqual(reached[3], 7); XCTAssertEqual(reached[4], 18); XCTAssertEqual(reached[5], 42)
    }

    // MARK: the night wording

    func testNightSaysAsleepAndADaytimeNapStaysNapping() {
        let s = JellyState(record: JellyRecord(id: 0, name: "Berry", color: "blue", levels: [1, 1, 1], dirt: 0, sparkle: 0, mood: AwayMath.mood(of: [1, 1, 1]).rawValue), awaySeconds: 0)
        XCTAssertEqual(JellyStatus.sentence(s, sleeping: true, night: true), "Berry is asleep.")
        XCTAssertEqual(JellyStatus.sentence(s, sleeping: true, night: false), "Berry is napping.")
        XCTAssertEqual(JellyStatus.word(s, sleeping: true, night: true), "asleep")
        XCTAssertEqual(JellyStatus.headline(s, sleeping: true, night: true), "Berry is asleep")
        XCTAssertEqual(JellyStatus.spoken([s], sleeping: true, night: true), "Berry is asleep.")
        XCTAssertEqual(JellyStatus.inline([s], sleeping: true, night: true), "Berry is asleep")
        XCTAssertEqual(JellyStatus.inline([s, s], sleeping: true, night: true), "Everyone is asleep")
        let three = [s, s, s]
        XCTAssertEqual(JellyStatus.rectangularLine(three, sleeping: true, night: true), "Everyone is asleep")
        XCTAssertEqual(JellyStatus.rectangularLine(three, sleeping: true, night: false), "Everyone is napping")
        XCTAssertTrue(SleepHours.isNight(hour: 22) && !SleepHours.isNight(hour: 14))
    }
}
