//
//  ShowModelTests.swift
//  The Jelly Show's rules, headless: the scoring formulas, the payout table and rank unlocks, the rivals' difficulty (a cared-for Jelbie wins the
//  Puddle most days, an untrained one hardly ever wins the Ocean), determinism (same day, same rank: same rivals and scores), the saves (new keys,
//  old condition saves untouched), the dance lane on the beat grid, and the day's theme schedule.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ShowModelTests: XCTestCase {

    // MARK: formulas

    func testLookFormula() {
        // Look = 40 x outfit + 40 x (0.7 main + 0.3 friend) + 20 x glow x (1 - 0.5 dirt)
        XCTAssertEqual(ShowScoring.look(outfit: 1, main: 1, friend: 1, glow: 1, dirt: 0), 100, accuracy: 1e-4)
        XCTAssertEqual(ShowScoring.look(outfit: 0, main: 0, friend: 0, glow: 0, dirt: 0), 0, accuracy: 1e-4)
        XCTAssertEqual(ShowScoring.look(outfit: 0.5, main: 0.5, friend: 0.5, glow: 1, dirt: 1), 20 + 20 + 10, accuracy: 1e-4)
        XCTAssertEqual(ShowScoring.look(outfit: 0.75, main: 0.6, friend: 0.2, glow: 0.5, dirt: 0.2), 30 + 40 * (0.42 + 0.06) + 20 * 0.5 * 0.9, accuracy: 1e-4)
        // the mockup's numbers: 2.5 of 3 slots, Sparkly 71 / Cute 62, glow 0.6 with a little lint
        let t = ShowTheme.starlightGala
        XCTAssertEqual(ShowScoring.outfitMatch(items: [[.sparkly], [.sparkly, .sweet], [.cute, .cool]], slots: 3, theme: t), 2.5 / 3, accuracy: 1e-5)
        XCTAssertEqual(ShowScoring.outfitMatch(items: [[.sparkly], [.sparkly], [.sparkly], [.sparkly]], slots: 3, theme: t), 1, "capped at 1")
        XCTAssertEqual(t.match([.sporty]), 0.15); XCTAssertEqual(t.match([.cool]), 0.5); XCTAssertEqual(t.match([.cool, .sparkly]), 1, "an item counts once, at its best tag")
    }

    func testDanceFormulaAndCheer() {
        XCTAssertEqual(ShowScoring.dance(accuracy: 1, skill: 1), 100, accuracy: 1e-4)
        XCTAssertEqual(ShowScoring.dance(accuracy: 1, skill: 0), 70, accuracy: 1e-4)
        XCTAssertEqual(ShowScoring.dance(accuracy: 0, skill: 1), 30, accuracy: 1e-4)
        XCTAssertEqual(ShowScoring.dance(accuracy: 0.8, skill: 0.4), 100 * (0.56 + 0.12), accuracy: 1e-4)
        var c: Float = 0
        c = ShowScoring.cheer(c, after: .perfect); XCTAssertEqual(c, 0.125, accuracy: 1e-6)
        c = ShowScoring.cheer(c, after: .good); XCTAssertEqual(c, 0.1875, accuracy: 1e-6)
        c = ShowScoring.cheer(c, after: .miss); XCTAssertEqual(c, 0.125, accuracy: 1e-6)
        for _ in 0..<20 { c = ShowScoring.cheer(c, after: .perfect) }; XCTAssertEqual(c, 1)
        for _ in 0..<40 { c = ShowScoring.cheer(c, after: .miss) }; XCTAssertEqual(c, 0)
    }

    func testTrickTurnPoints() {
        let t = ShowTheme.starlightGala           // sparkly, friend cool
        XCTAssertEqual(ShowScoring.turn(success: true, repeated: false, tags: [.sparkly], theme: t, timing: 1), 30, "18 + 6 + 6")
        XCTAssertEqual(ShowScoring.turn(success: true, repeated: true, tags: [.sparkly], theme: t, timing: 1), 24, "a repeat: 12")
        XCTAssertEqual(ShowScoring.turn(success: false, repeated: false, tags: [.sparkly], theme: t, timing: 1), 20, "a cute flop: 8")
        XCTAssertEqual(ShowScoring.turn(success: true, repeated: false, tags: [.cool], theme: t, timing: 0.5), 18 + 3 + 3)
        XCTAssertEqual(ShowScoring.turn(success: true, repeated: false, tags: [.sweet], theme: t, timing: 0), 18)
        XCTAssertEqual(ShowScoring.timing(error: 0), 1); XCTAssertEqual(ShowScoring.timing(error: 0.15), 0.5, accuracy: 1e-5); XCTAssertEqual(ShowScoring.timing(error: -0.4), 0)
        XCTAssertTrue(ShowScoring.burstReady(cheer: 0.75, glow: 0.5)); XCTAssertFalse(ShowScoring.burstReady(cheer: 0.74, glow: 1)); XCTAssertFalse(ShowScoring.burstReady(cheer: 1, glow: 0.49))
        // the flip, a starter, counts as Sparkly too; spin is Sparkly; hop Sporty; roll Cute
        XCTAssertTrue(ShowTrickInfo.tags(.flip).contains(.sparkly)); XCTAssertEqual(ShowTrickInfo.tags(.spin), [.sparkly])
        XCTAssertEqual(ShowTrickInfo.tags(.hop), [.sporty]); XCTAssertEqual(ShowTrickInfo.tags(.roll), [.cute])
        XCTAssertEqual(ConditionKey.sparkle.title, "Sparkly"); XCTAssertEqual(ConditionKey.sparkle.tag, .sparkly); XCTAssertEqual(WearTag.sparkly.condition, .sparkle)
    }

    func testTiesSharePlace() {
        XCTAssertEqual(ShowScoring.places(totals: [230, 214, 192, 188]), [1, 2, 3, 4])
        XCTAssertEqual(ShowScoring.places(totals: [200, 200, 150, 100]), [1, 1, 3, 4])
        XCTAssertEqual(ShowScoring.places(totals: [100, 200, 200, 200]), [4, 1, 1, 1])
    }

    /// A whole show through the sim: the max score is 300 (3 x 30 + 10 Burst = 100 in the Trick round).
    func testPerfectShowScoresThreeHundred() {
        var p = ShowPlayerInput(name: "Bob")
        for t in WearTag.allCases { p.condition[t] = 1 }
        p.glow = 1; p.dirt = 0; p.dance = .sway; p.danceSkill = 1; p.tricks = [.spin: 1, .flip: 1, .hop: 1]
        let theme = ShowTheme.starlightGala
        var s = ShowSim(rank: .puddle, theme: theme, dayKey: 20261021, player: p, rivals: ShowRivalSource.rivals(dayKey: 20261021, rank: .puddle, theme: theme), seed: 1)
        s.setOutfit([.head: [.sparkly], .feet: [.sparkly]])
        XCTAssertEqual(s.lookScore, 100, accuracy: 1e-4)
        s.finishLook()
        s.beginDance(grid: .stage, songTime: 10)
        let prompts = s.dance!.prompts
        for pr in prompts { _ = s.tapDance(foot: pr.foot, at: pr.time + ShowDanceSim.latencyOffset) }
        _ = s.tickDance(songTime: s.dance!.endTime + 1)
        XCTAssertTrue(s.danceDone); XCTAssertEqual(s.danceScore!, 100, accuracy: 1e-4); XCTAssertEqual(s.cheer, 1)
        s.finishDance()
        XCTAssertTrue(s.burstReady)
        for (i, t) in [VoiceTrick.spin, .flip, .hop].enumerated() {
            if i == 2 { s.armBurst() }
            s.beginTurn(t, at: 100 + Double(i) * 3)
            let turn = s.tapRing(at: 100 + Double(i) * 3 + ShowScoring.ringSeconds, roll: 0)!
            XCTAssertTrue(turn.success); XCTAssertEqual(turn.timing, 1)
        }
        XCTAssertEqual(s.turns.map(\.points), [30, 30, 24], "hop is Sporty: no theme points")
        XCTAssertEqual(s.trickTotal, 94)
        XCTAssertEqual(s.round, .results)
        XCTAssertEqual(s.playerScores.totalPts, 294)
        XCTAssertEqual(s.playerPlace, 1); XCTAssertEqual(s.playerDrops, 12)
        XCTAssertTrue(s.perfectDance); XCTAssertTrue(s.hatTrick)
    }

    // MARK: payouts and ranks

    func testPayoutTable() {
        let want: [ShowRank: [Int]] = [.puddle: [12, 7, 4, 2], .pond: [15, 9, 5, 3], .lagoon: [18, 11, 7, 4], .ocean: [22, 13, 8, 5]]
        for (r, row) in want { for p in 1...4 { XCTAssertEqual(r.drops(place: p), row[p - 1], "\(r) \(p)") } }
        XCTAssertEqual(ShowRank.ocean.drops(place: 9), 5, "past 4th pays 4th")
        XCTAssertEqual(ShowRank.allCases.map(\.slots), [2, 3, 4, 6]); XCTAssertEqual(ShowRank.allCases.map(\.promptCount), [16, 20, 24, 28])
        XCTAssertEqual(ShowRank.allCases.map(\.title), ["Puddle", "Pond", "Lagoon", "Ocean"])
        XCTAssertTrue(ShowRank.puddle.kindTiming && ShowRank.pond.kindTiming && !ShowRank.lagoon.kindTiming && !ShowRank.ocean.kindTiming)
    }

    func testRankUnlocksByAFirstOrThreeTopTwos() {
        let p = ShowProgress(persists: false)
        XCTAssertEqual(p.unlockedRanks, [.puddle]); XCTAssertNotNil(p.requirement(.pond)); XCTAssertTrue(p.firstShowEver)
        // three 2nds open the Pond
        for _ in 0..<2 { p.record(rank: .puddle, place: 2, theme: .beachGames, character: 0, burst: false, perfectDance: false, hatTrick: false) }
        XCTAssertEqual(p.unlockedRanks, [.puddle]); XCTAssertFalse(p.firstShowEver)
        let a = p.record(rank: .puddle, place: 2, theme: .beachGames, character: 0, burst: false, perfectDance: false, hatTrick: false)
        XCTAssertEqual(a.unlocked, .pond); XCTAssertEqual(p.unlockedRanks, [.puddle, .pond])
        XCTAssertEqual(p.trophies(character: 0).cup(.puddle), 2, "a silver cup for the best placing so far")
        // a 1st at the Pond opens the Lagoon, a cup and a rosette
        let b = p.record(rank: .pond, place: 1, theme: .starlightGala, character: 0, burst: true, perfectDance: false, hatTrick: true)
        XCTAssertEqual(b.unlocked, .lagoon); XCTAssertEqual(b.cup, 1); XCTAssertEqual(b.rosette, .sparkly)
        XCTAssertEqual(Set(b.stickers), Set([.glowBurst, .hatTrick]))
        XCTAssertEqual(p.unlockedRanks, [.puddle, .pond, .lagoon]); XCTAssertNil(p.requirement(.lagoon)); XCTAssertNotNil(p.requirement(.ocean))
        p.chosen = .ocean; XCTAssertEqual(p.chosen, .puddle, "a locked rank cannot be chosen")
        p.chosen = .lagoon; XCTAssertEqual(p.chosen, .lagoon)
        // 4th place: no unlock, no cup
        let c = p.record(rank: .lagoon, place: 4, theme: .coolCats, character: 1, burst: false, perfectDance: true, hatTrick: false)
        XCTAssertNil(c.unlocked); XCTAssertNil(c.cup); XCTAssertEqual(c.stickers, [.firstShow, .perfectDance])
        XCTAssertEqual(p.record(.lagoon).shows, 1); XCTAssertEqual(p.record(.puddle).topTwo, 3)
    }

    // MARK: rivals

    /// Plays one show for `input` at `rank` on `dayKey`: dance taps with the given Perfect / Good chances, every turn tapped with `timing`.
    private func play(_ input: ShowPlayerInput, outfit: [WearSlot: [WearTag]], rank: ShowRank, dayKey: Int, firstShow: Bool = false,
                      perfect pP: Float, good pG: Float, timing: Float, seed: UInt64) -> ShowSim {
        let theme = ShowSchedule.theme(dayKey: dayKey)
        var s = ShowSim(rank: rank, theme: theme, dayKey: dayKey, player: input, rivals: ShowRivalSource.rivals(dayKey: dayKey, rank: rank, theme: theme, firstShow: firstShow), seed: seed)
        var g = RaceRNG(seed: seed &* 77 &+ 3)
        s.setOutfit(outfit)
        s.finishLook()
        s.beginDance(grid: .stage, songTime: 5)
        for pr in s.dance!.prompts {
            let r = g.next()
            let at = pr.time + ShowDanceSim.latencyOffset
            if r < pP { _ = s.tapDance(foot: pr.foot, at: at) }
            else if r < pP + pG { _ = s.tapDance(foot: pr.foot, at: at + Double(s.rank.timing.perfect) + 0.01) }
            // else: no tap, a slip
        }
        _ = s.tickDance(songTime: s.dance!.endTime + 1)
        s.finishDance()
        let known = s.knownTricks
        for k in 0..<ShowScoring.turns {
            let t = known[k % max(known.count, 1)]
            if s.burstReady { s.armBurst() }
            s.beginTurn(t, at: Double(k) * 5)
            s.tapRing(at: Double(k) * 5 + ShowScoring.ringSeconds + Double((1 - timing) * 0.3), roll: g.next())
        }
        XCTAssertEqual(s.round, .results)
        return s
    }

    /// A cared-for Jelbie: fed to the theme a few times, bathed, one dance half learned, three starter tricks taught, a player who taps decently.
    private func caredFor(theme: ShowTheme) -> (ShowPlayerInput, [WearSlot: [WearTag]]) {
        var p = ShowPlayerInput(name: "Bob")
        for t in WearTag.allCases { p.condition[t] = 0.2 }
        p.condition[theme.main] = 0.5; p.condition[theme.friend] = 0.4
        p.glow = 0.7; p.dirt = 0.1; p.dance = .sway; p.danceSkill = 0.3
        p.tricks = [.sit: 0.6, .flip: 0.6, .jacks: 0.6]
        return (p, [.head: [theme.main], .feet: [theme.friend]])
    }
    /// A brand-new Jelbie: nothing fed, no bath, no dance, one wobbly trick, a player who misses a lot.
    private func untrained() -> ShowPlayerInput {
        var p = ShowPlayerInput(name: "Bob")
        for t in WearTag.allCases { p.condition[t] = 0.1 }
        p.glow = 0.2; p.dirt = 0.5; p.dance = nil; p.danceSkill = 0; p.tricks = [.sit: 0.4]
        return p
    }

    func testCaredForJelbieWinsThePuddleMostDays() {
        var wins = 0, podium = 0, totals: [Float] = []
        let days = (0..<200).map { ShowSchedule.dayKey(ordinal: ShowSchedule.dayOrdinal(20261021) + $0) }
        for (i, day) in days.enumerated() {
            let theme = ShowSchedule.theme(dayKey: day)
            let (p, o) = caredFor(theme: theme)
            let s = play(p, outfit: o, rank: .puddle, dayKey: day, perfect: 0.5, good: 0.3, timing: 0.6, seed: UInt64(i + 1))
            if s.playerPlace == 1 { wins += 1 }
            if (s.playerPlace ?? 9) <= 3 { podium += 1 }
            totals.append(s.playerScores.total)
        }
        let rate = Double(wins) / Double(days.count)
        print("SHOW puddle cared-for: wins \(wins)/\(days.count) (\(rate)), podium \(podium), mean total \(totals.reduce(0, +) / Float(totals.count))")
        XCTAssertGreaterThanOrEqual(rate, 0.6, "a cared-for Jelbie wins the Puddle at least 60% of the time")
    }

    func testUntrainedJelbieRarelyWinsTheOcean() {
        var wins = 0
        let days = (0..<200).map { ShowSchedule.dayKey(ordinal: ShowSchedule.dayOrdinal(20261021) + $0) }
        for (i, day) in days.enumerated() {
            let s = play(untrained(), outfit: [:], rank: .ocean, dayKey: day, perfect: 0.3, good: 0.3, timing: 0.4, seed: UInt64(i + 1))
            if s.playerPlace == 1 { wins += 1 }
        }
        print("SHOW ocean untrained: wins \(wins)/\(days.count)")
        XCTAssertLessThanOrEqual(Double(wins) / Double(days.count), 0.05, "an untrained Jelbie hardly ever wins the Ocean")
        // and the Ocean rivals really are the strongest, the Puddle's the softest
        var means: [Float] = []
        for r in ShowRank.allCases {
            var sum: Float = 0
            for day in days.prefix(30) {
                let rs = ShowRivalSource.rivals(dayKey: day, rank: r, theme: ShowSchedule.theme(dayKey: day))
                var t: Float = 0
                for x in rs { t += x.scores.total }
                sum += t / 3
            }
            means.append(sum / 30)
        }
        print("SHOW rival mean totals by rank: \(means)")
        for i in 1..<means.count { XCTAssertGreaterThan(means[i], means[i - 1] + 25) }
        XCTAssertGreaterThan(means[0], 100); XCTAssertLessThan(means[0], 165); XCTAssertGreaterThan(means[3], 240)
    }

    func testFirstShowRivalsAreSofterAndPersonasAreOneEach() {
        let theme = ShowSchedule.theme(dayKey: 20261021)
        let normal = ShowRivalSource.rivals(dayKey: 20261021, rank: .pond, theme: theme)
        let first = ShowRivalSource.rivals(dayKey: 20261021, rank: .pond, theme: theme, firstShow: true)
        XCTAssertEqual(normal.map(\.name), first.map(\.name), "the same rivals, going easy")
        XCTAssertLessThan(first.map(\.scores.total).reduce(0, +), normal.map(\.scores.total).reduce(0, +) - 20)
        XCTAssertEqual(Set(normal.map(\.persona)), Set(ShowPersona.allCases), "one Poser, one Dancer, one Trickster")
        XCTAssertEqual(Set(normal.map(\.name)).count, 3)
        for r in normal { XCTAssertEqual(Set(r.tricks).count, 3, "three different tricks, never a repeat") }
        let ocean = ShowRivalSource.rivals(dayKey: 20261021, rank: .ocean, theme: theme)
        XCTAssertTrue(ocean.contains { $0.headliner && $0.name == ShowRivalSource.headlinerName && $0.burst })
        XCTAssertFalse(ShowRivalSource.rivals(dayKey: 20261021, rank: .lagoon, theme: theme).contains(where: \.headliner))
    }

    // MARK: determinism

    func testSameDaySameRankGivesTheSameRivalsAndScores() {
        for r in ShowRank.allCases {
            let theme = ShowSchedule.theme(dayKey: 20261105)
            let a = ShowRivalSource.rivals(dayKey: 20261105, rank: r, theme: theme), b = ShowRivalSource.rivals(dayKey: 20261105, rank: r, theme: theme)
            XCTAssertEqual(a, b, "\(r): a same-day replay meets the same rivals with the same scores")
            let c = ShowRivalSource.rivals(dayKey: 20261106, rank: r, theme: ShowSchedule.theme(dayKey: 20261106))
            XCTAssertNotEqual(a.map(\.scores), c.map(\.scores), "\(r): another day, other scores")
        }
        XCTAssertNotEqual(ShowRivalSource.rivals(dayKey: 20261105, rank: .puddle, theme: .beachGames).map(\.scores),
                          ShowRivalSource.rivals(dayKey: 20261105, rank: .pond, theme: .beachGames).map(\.scores))
        // the schedule is a pure function of the calendar day, never the same two days running, and every theme turns up
        var seen: Set<ShowTheme> = []
        var prev: ShowTheme?
        for n in -400...400 {
            let t = ShowSchedule.theme(ordinal: n)
            XCTAssertEqual(t, ShowSchedule.theme(dayKey: ShowSchedule.dayKey(ordinal: n)))
            if let prev { XCTAssertNotEqual(t, prev, "day \(n) repeats yesterday's theme") }
            prev = t; seen.insert(t)
        }
        XCTAssertEqual(seen, Set(ShowTheme.allCases))
        XCTAssertEqual(ShowSchedule.tomorrow(dayKey: 20261031), ShowSchedule.theme(dayKey: 20261101), "the teaser is tomorrow's theme, across a month end")
        XCTAssertEqual(ShowSchedule.dayKey(ordinal: ShowSchedule.dayOrdinal(20261021)), 20261021)
        XCTAssertEqual(ShowSchedule.dayOrdinal(19700101), 0); XCTAssertEqual(ShowSchedule.dayOrdinal(20000301) - ShowSchedule.dayOrdinal(20000228), 2, "a leap day")
        for (t, m, f) in [(ShowTheme.sweetTeaParty, WearTag.sweet, WearTag.cute), (.starlightGala, .sparkly, .cool), (.beachGames, .sporty, .cute), (.coolCats, .cool, .sporty), (.bunnyPicnic, .cute, .sweet)] {
            XCTAssertEqual(t.main, m); XCTAssertEqual(t.friend, f)
        }
    }

    // MARK: saves

    func testProgressRoundTripsThroughDefaults() {
        let d = UserDefaults(suiteName: "ShowSave.\(UUID().uuidString)")!
        let p = ShowProgress(persists: true, defaults: d)
        p.record(rank: .puddle, place: 1, theme: .bunnyPicnic, character: 2, burst: true, perfectDance: false, hatTrick: false)
        p.record(rank: .pond, place: 3, theme: .coolCats, character: 2, burst: false, perfectDance: false, hatTrick: false)
        p.chosen = .pond
        let q = ShowProgress(persists: true, defaults: d)
        XCTAssertEqual(q.record(.puddle), ShowProgress.Record(shows: 1, wins: 1, topTwo: 1, best: 1))
        XCTAssertEqual(q.record(.pond), ShowProgress.Record(shows: 1, wins: 0, topTwo: 0, best: 3))
        XCTAssertEqual(q.chosen, .pond); XCTAssertEqual(q.unlockedRanks, [.puddle, .pond])
        XCTAssertEqual(q.trophies(character: 2).cup(.puddle), 1); XCTAssertEqual(q.trophies(character: 2).cup(.pond), 3)
        XCTAssertTrue(q.trophies(character: 2).hasRosette(.cute)); XCTAssertEqual(q.trophies(character: 2).stickers, ["firstShow", "glowBurst"])
        XCTAssertEqual(q.trophies(character: 0), ShowProgress.Trophies(), "another Jelbie: no trophies")
        // garbage under the key = nothing won (no crash)
        d.set(Data([1, 2, 3]), forKey: ShowProgress.key)
        XCTAssertEqual(ShowProgress(persists: true, defaults: d).unlockedRanks, [.puddle])
    }

    func testStatsSavesStayBackCompatible() {
        let d = UserDefaults(suiteName: "ShowStats.\(UUID().uuidString)")!
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        // a save written by the build before the show: the plain condition array and the one dance
        d.set([0.3, 0.1, 0.5, 0.2, 0.0, now.timeIntervalSince1970], forKey: "S.cond")
        d.set(["sway": 0.4], forKey: "S.dances")
        let s = JellyStats(persists: true, defaults: d, key: "S", now: { now })
        XCTAssertEqual(s.condition(.sparkle), 0.5, accuracy: 1e-5); XCTAssertEqual(s.proficiency(.sway), 0.4, accuracy: 1e-5)
        XCTAssertEqual(s.meals, [], "no diary yet")
        XCTAssertEqual(s.bestDance, .sway); XCTAssertTrue(s.danceOpen(.sway)); XCTAssertFalse(s.danceOpen(.bop))
        // meals: the same food within a minute is one line; eight are kept, newest first
        s.nudge([.sparkle: 0.1, .cute: 0.05], food: "Sushi")
        s.nudge([.sparkle: 0.1], food: "Sushi")
        XCTAssertEqual(s.meals.count, 1); XCTAssertEqual(s.meals[0].gains[ConditionKey.sparkle.rawValue]!, 0.2, accuracy: 1e-5)
        for i in 0..<10 { now = now.addingTimeInterval(120); s.nudge([.sweet: 0.05], food: "Donut \(i)") }
        XCTAssertEqual(s.meals.count, JellyStats.mealsKept); XCTAssertEqual(s.meals.first?.food, "Donut 9")
        s.learn(.bop, add: 0.6)
        let t = JellyStats(persists: true, defaults: d, key: "S", now: { now })
        XCTAssertEqual(t.meals, s.meals); XCTAssertEqual(t.proficiency(.bop), 0.6, accuracy: 1e-5); XCTAssertEqual(t.bestDance, .bop)
        XCTAssertEqual((d.array(forKey: "S.cond") as? [Double])?.count, ConditionKey.allCases.count + 1, "the condition array keeps its old shape")
        // a dance drill teaches the dance and uses a Pep; a brand-new dance always learns a little
        var day = 20261021
        let fresh = JellyStats(persists: false, dayKey: { day })
        let g = fresh.finishDancePractice(.sway, accuracy: 0.2)
        XCTAssertGreaterThanOrEqual(g, 0.05); XCTAssertEqual(fresh.sessionsToday, 1); XCTAssertEqual(fresh.pepLeft, 2)
        var p = fresh.proficiency(.sway); var n = 1
        while p < 0.5, n < 20 { if fresh.pepLeft == 0 { day += 1 }; fresh.finishDancePractice(.sway, accuracy: 0.85); p = fresh.proficiency(.sway); n += 1 }
        XCTAssertLessThanOrEqual(n, 6, "half known within a handful of good sessions with Pep (\(n))")
        let spent = JellyStats(persists: false, dayKey: { 1 })
        for _ in 0..<3 { spent.finishDancePractice(.sway, accuracy: 1) }
        let before = spent.proficiency(.sway)
        XCTAssertLessThan(spent.finishDancePractice(.sway, accuracy: 1), (before - 0) * 0.2, "after the day's Pep a session teaches much less")
    }

    // MARK: the dance lane

    func testDancePromptsSitOnTheStageBeatGridAndAreJudgedFromTheAudioClock() {
        // the two show tracks: 120 BPM, loops of exactly 64 beats
        for t in [SceneTrack.contestStage, .studioPractice] {
            let g = ShowBeat.grid(for: t)
            XCTAssertEqual(g.period, 0.5)
            let beats = (t.loopEnd - t.loopStart) / g.period
            XCTAssertEqual(beats, beats.rounded(), accuracy: 0.01, "\(t): the loop is a whole number of beats (\(beats))")
            XCTAssertEqual(beats, 64, accuracy: 0.01)
            let k = (t.loopStart - g.firstBeat) / g.period
            XCTAssertEqual(k, k.rounded(), accuracy: 0.01, "\(t): the loop starts on a beat of the grid")
        }
        let grid = ShowBeat.stage
        var s = ShowDanceSim(count: 20, grid: grid, timing: .kind, seed: 9, songTime: 12.0)
        XCTAssertEqual(s.total, 20)
        for (i, p) in s.prompts.enumerated() {
            XCTAssertEqual(p.time, grid.time(ofBeat: p.beat), accuracy: 1e-9)
            XCTAssertEqual(p.time, grid.firstBeat + Double(p.beat) * grid.period, accuracy: 1e-9)
            if i > 0 { XCTAssertEqual(p.beat, s.prompts[i - 1].beat + 1, "one prompt a beat"); XCTAssertNotEqual(p.foot, s.prompts[i - 1].foot, "feet alternate") }
        }
        XCTAssertGreaterThanOrEqual(s.prompts[0].time, 12.0 + 4 * grid.period - 1e-9, "four beats of lead-in")
        // judged at song time minus the latency offset: a tap exactly latencyOffset after the beat is Perfect
        let p0 = s.prompts[0]
        s.tap(foot: p0.foot, at: p0.time + ShowDanceSim.latencyOffset)
        XCTAssertEqual(s.perfects, 1)
        let p1 = s.prompts[1]
        s.tap(foot: p1.foot, at: p1.time + ShowDanceSim.latencyOffset + 0.07)
        XCTAssertEqual(s.perfects, 2, "Pond timing is kind: 70 ms is still Perfect")
        let p2 = s.prompts[2]
        s.tap(foot: p2.foot, at: p2.time + ShowDanceSim.latencyOffset + 0.12)
        XCTAssertEqual(s.goods, 1)
        let p3 = s.prompts[3]
        s.tap(foot: 1 - p3.foot, at: p3.time + ShowDanceSim.latencyOffset)
        XCTAssertEqual(s.misses, 1, "the wrong foot is a slip")
        s.tap(foot: 0, at: s.prompts[4].time - 1.0)
        XCTAssertEqual(s.strays, 1, "a tap far from any prompt is a stray")
        s.tick(songTime: s.endTime + 1)
        XCTAssertTrue(s.finished); XCTAssertEqual(s.judged, 20); XCTAssertEqual(s.misses, 17)
        XCTAssertEqual(s.cheer, 0, "the slips emptied the meter")
        // standard timing (Lagoon / Ocean): 70 ms is a Good
        var hard = ShowDanceSim(count: 24, grid: grid, timing: .standard, seed: 9, songTime: 12.0)
        let q = hard.prompts[0]
        hard.tap(foot: q.foot, at: q.time + ShowDanceSim.latencyOffset + 0.07)
        XCTAssertEqual(hard.goods, 1); XCTAssertEqual(hard.perfects, 0)
        // the studio grid works the same way
        var st = ShowDanceSim(count: 16, grid: .studio, timing: .kind, seed: 1, songTime: SceneTrack.studioPractice.loopStart)
        XCTAssertEqual(st.prompts[0].time, ShowBeat.studio.time(ofBeat: st.prompts[0].beat), accuracy: 1e-9)
        for p in st.prompts { st.tap(foot: p.foot, at: p.time + ShowDanceSim.latencyOffset) }
        XCTAssertEqual(st.accuracy, 1); XCTAssertTrue(st.finished)
    }

    func testDanceMovesAndTrickMovesAreKnownMoves() {
        XCTAssertEqual(DanceID.sway.move, .sway); XCTAssertEqual(DanceID.bop.move, .bounce); XCTAssertEqual(DanceID.twirl.move, .tail)
        XCTAssertEqual(DanceID.starter, .sway)
        for t in ShowTrickInfo.stageTricks where t != .flip { XCTAssertNotNil(VoiceCoordinator.idleKind(for: t), "\(t) has a body move") }
    }
}
