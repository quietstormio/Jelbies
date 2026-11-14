//
//  VolleyUpgradeTests.swift
//  The Volleyball Upgrade menu's model: levels from the four stats, buying (stat up, points down, never short), points by result (once), the chosen power-up food used up at the
//  match start with a one-match bump that is never saved, and the race and volleyball choices being separate.
//

import XCTest
@testable import BobV1

@MainActor
final class VolleyUpgradeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func care() -> GameCare {
        let c = GameCare(jellyCount: 1, persistent: false, defaults: UserDefaults(suiteName: "VolleyUpgradeTests.\(UUID().uuidString)")!)
        Self.keep.append(c)
        return c
    }

    func testLevelFromEachStat() {
        let b = UpgradeBook(persists: false)
        for k in VolleyStatKind.allCases {
            var s = VolleyStats()
            s.setValue(k, 0.35); XCTAssertEqual(b.level(k, stats: s), 1, "\(k)")
            s.setValue(k, 0.4); XCTAssertEqual(b.level(k, stats: s), 2, "\(k)")
            s.setValue(k, 0.6); XCTAssertEqual(b.level(k, stats: s), 3, "\(k)")
            s.setValue(k, 0.8); XCTAssertEqual(b.level(k, stats: s), 4, "\(k)")
            s.setValue(k, 1); XCTAssertEqual(b.level(k, stats: s), 5, "\(k)")
        }
        XCTAssertEqual(VolleyStatKind.allCases.count, 4)
    }

    func testBuyRaisesSavedStatSpendsPointsRefusesWhenShortAndAtMax() {
        let b = UpgradeBook(persists: false), v = VolleyBook(persists: false)
        XCTAssertEqual(b.level(.power, stats: v.stats(character: 0)), 1)         // 0.35
        XCTAssertFalse(b.buy(.power, volley: v, character: 0), "no points: refused")
        b.add(5, .volley, character: 0)
        XCTAssertFalse(b.buy(.power, volley: v, character: 1), "another Jelmiko's balance is separate")
        XCTAssertTrue(b.buy(.power, volley: v, character: 0))          // level 1 -> 2 costs 2
        XCTAssertEqual(v.stats(character: 0).power, 0.4, accuracy: 1e-6)
        XCTAssertEqual(b.points(.volley, character: 0), 3)
        XCTAssertEqual(v.stats(character: 0).speed, 0.35, accuracy: 1e-6, "other stats untouched")
        XCTAssertTrue(b.buy(.power, volley: v, character: 0))          // 2 -> 3 costs 3
        XCTAssertEqual(b.points(.volley, character: 0), 0)
        XCTAssertFalse(b.buy(.power, volley: v, character: 0))
        // never lowers a stat that is already above the next level's value
        v.raise(.hops, to: 0.59, character: 2)
        b.add(10, .volley, character: 2)
        XCTAssertTrue(b.buy(.hops, volley: v, character: 2))
        XCTAssertGreaterThanOrEqual(v.stats(character: 2).hops, 0.59)
        // max level: nothing to buy, nothing spent
        v.raise(.timing, to: 1, character: 3); b.add(50, .volley, character: 3)
        XCTAssertFalse(b.buy(.timing, volley: v, character: 3))
        XCTAssertEqual(b.points(.volley, character: 3), 50)
        XCTAssertEqual(b.points(.race, character: 3), 0, "race points are a different balance")
    }

    func testPointsByResult() {
        XCTAssertEqual(UpgradeTuning.volleyPoints(win: true), 3)
        XCTAssertEqual(UpgradeTuning.volleyPoints(win: false, closeLoss: true), 2)
        XCTAssertEqual(UpgradeTuning.volleyPoints(win: false, closeLoss: false), 1)
        XCTAssertEqual(UpgradeTuning.volleyPoints(win: nil), 0, "no result (abandoned): nothing")
    }

    func testFlowAwardsOnceAndNothingForNoResult() {
        let b = UpgradeBook(persists: false), f = VolleyFlow()
        f.upgrades = b; f.playerCharacter = 2
        f.awardPoints(win: false, closeLoss: true)
        XCTAssertEqual(f.pointsEarned, 2); XCTAssertEqual(f.pointsAfter, 2)
        f.awardPoints(win: true, closeLoss: false)
        XCTAssertEqual(b.points(.volley, character: 2), 2, "once: a second call does not pay again")
        XCTAssertEqual(b.points(.volley, character: 0), 0)
        let b2 = UpgradeBook(persists: false), g = VolleyFlow()
        g.upgrades = b2; g.playerCharacter = 1
        g.awardPoints(win: nil, closeLoss: false)
        XCTAssertEqual(b2.points(.volley, character: 1), 0); XCTAssertEqual(g.pointsEarned, 0)
    }

    func testMatchGainIsGone() {
        let v = VolleyBook(persists: false)
        let before = v.stats(character: 0)
        v.finishMatch(character: 0, tier: .sandcastle, win: true, closeLoss: false)
        v.finishMatch(character: 0, tier: .sandcastle, win: false, closeLoss: true)
        let after = v.stats(character: 0)
        XCTAssertEqual(after.speed, before.speed); XCTAssertEqual(after.power, before.power)
        XCTAssertEqual(after.hops, before.hops); XCTAssertEqual(after.timing, before.timing)
        XCTAssertEqual(after.matches, 2); XCTAssertEqual(after.wins, 1)
    }

    func testChosenFoodIsUsedUpAtStartWithAnUnsavedBump() {
        let c = care(), prof = c.jelly(0)!
        let saved = c.volley.book.stats(character: prof.character)
        c.store.grant("donut", 2)
        c.upgrades.choose("donut", .volley, character: prof.character)
        let s = c.volleyStartStats(prof)
        XCTAssertEqual(s.speed, saved.speed + UpgradeTuning.volleyBump, accuracy: 1e-6, "zoomies food: Speed")
        XCTAssertEqual(s.timing, saved.timing, accuracy: 1e-6)
        XCTAssertEqual(c.store.count("donut"), 1, "one used up")
        XCTAssertEqual(c.volley.book.stats(character: prof.character).speed, saved.speed, "the bump is never saved")
        _ = c.volleyStartStats(prof)
        XCTAssertEqual(c.store.count("donut"), 0)
        // none left: no bump, choice cleared quietly
        XCTAssertEqual(c.volleyStartStats(prof).speed, saved.speed, accuracy: 1e-6)
        XCTAssertNil(c.upgrades.chosen(.volley, character: prof.character))
        // a focus food lifts Timing, clamped to 1
        c.volley.book.raise(.timing, to: 0.95, character: prof.character)
        c.store.grant("sandwich"); c.upgrades.choose("sandwich", .volley, character: prof.character)
        let t = c.volleyStartStats(prof)
        XCTAssertEqual(t.timing, 1, accuracy: 1e-6); XCTAssertEqual(t.speed, saved.speed, accuracy: 1e-6)
        // a food with no match perk is not a power-up
        c.store.grant("pizza"); c.upgrades.choose("pizza", .volley, character: prof.character)
        XCTAssertEqual(c.volleyStartStats(prof).speed, saved.speed, accuracy: 1e-6)
        XCTAssertEqual(c.store.count("pizza"), 1, "not used up")
    }

    func testRaceAndVolleyChoicesAreIndependent() {
        let c = care(), prof = c.jelly(0)!
        c.store.grant("donut", 2); c.store.grant("sandwich", 1)
        c.upgrades.choose("donut", .race, character: prof.character)
        c.upgrades.choose("sandwich", .volley, character: prof.character)
        XCTAssertEqual(c.upgrades.chosen(.race, character: prof.character), "donut")
        XCTAssertEqual(c.upgrades.chosen(.volley, character: prof.character), "sandwich")
        _ = c.volleyStartStats(prof)
        XCTAssertEqual(c.store.count("sandwich"), 0); XCTAssertEqual(c.store.count("donut"), 2, "volleyball start leaves the race food alone")
        XCTAssertEqual(c.upgrades.chosen(.race, character: prof.character), "donut")
        c.upgrades.choose(nil, .race, character: prof.character)
        XCTAssertNil(c.upgrades.chosen(.race, character: prof.character))
    }
}
