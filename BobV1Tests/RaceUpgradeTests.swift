//
//  RaceUpgradeTests.swift
//  The Race Upgrade menu's model: levels from the stats, buying (stat up, points down, never short), race points by place (once), and the chosen power-up food being used up at the start.
//

import XCTest
@testable import BobV1

@MainActor
final class RaceUpgradeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func book() -> UpgradeBook { UpgradeBook(persists: false) }

    func testLevelFromStat() {
        XCTAssertEqual(UpgradeTuning.level(stat: 0), 1)
        XCTAssertEqual(UpgradeTuning.level(stat: 0.19), 1)
        XCTAssertEqual(UpgradeTuning.level(stat: 0.2), 1)
        XCTAssertEqual(UpgradeTuning.level(stat: 0.39), 1)
        XCTAssertEqual(UpgradeTuning.level(stat: 0.4), 2)
        XCTAssertEqual(UpgradeTuning.level(stat: 0.59), 2)
        XCTAssertEqual(UpgradeTuning.level(stat: 0.6), 3)
        XCTAssertEqual(UpgradeTuning.level(stat: 0.8), 4)
        XCTAssertEqual(UpgradeTuning.level(stat: 0.99), 4)
        XCTAssertEqual(UpgradeTuning.level(stat: 1), 5)
        XCTAssertEqual(UpgradeTuning.cost(level: 1), 2); XCTAssertEqual(UpgradeTuning.cost(level: 4), 5); XCTAssertNil(UpgradeTuning.cost(level: 5))
    }

    func testBuyRaisesStatSpendsPointsAndRefusesWhenShort() {
        let b = book(), s = JellyStats(persists: false, seedWaddle: 0.5)       // level 2
        s.set(focus: 0.5)
        XCTAssertEqual(b.level(.speed, stats: s), 2)
        XCTAssertFalse(b.buy(.speed, stats: s, character: 0), "no points: refused")
        XCTAssertEqual(s.waddle, 0.5, accuracy: 1e-6)
        b.add(5, .race, character: 0)
        XCTAssertFalse(b.buy(.speed, stats: s, character: 1), "another Jelbie's balance is separate")
        XCTAssertTrue(b.buy(.speed, stats: s, character: 0))          // level 2 -> 3 costs 3
        XCTAssertEqual(s.waddle, 0.6, accuracy: 1e-6)
        XCTAssertEqual(b.points(.race, character: 0), 2)
        XCTAssertEqual(b.level(.speed, stats: s), 3)
        XCTAssertFalse(b.buy(.speed, stats: s, character: 0), "level 3 -> 4 costs 4, only 2 left")
        XCTAssertEqual(b.points(.race, character: 0), 2)
        XCTAssertEqual(s.focus, 0.5, accuracy: 1e-6, "Focus untouched by a Speed purchase")
        // a stat already above the next level's value is never lowered
        let hi = JellyStats(persists: false, seedWaddle: 0.5); hi.set(waddle: 0.59)
        XCTAssertEqual(UpgradeTuning.level(stat: 0.59), 2)
        b.add(10, .race, character: 2)
        XCTAssertTrue(b.buy(.speed, stats: hi, character: 2))
        XCTAssertGreaterThanOrEqual(hi.waddle, 0.59)
    }

    func testMaxLevel() {
        let b = book(), s = JellyStats(persists: false, seedWaddle: 0.5)
        s.set(focus: 1)
        b.add(50, .race, character: 0)
        XCTAssertEqual(b.level(.focus, stats: s), 5)
        XCTAssertFalse(b.buy(.focus, stats: s, character: 0), "max level: nothing to buy")
        XCTAssertEqual(b.points(.race, character: 0), 50, "and nothing spent")
        XCTAssertEqual(s.focus, 1)
    }

    func testPersistsUnderItsOwnKey() {
        let d = UserDefaults(suiteName: "RaceUpgradeTests.\(UUID().uuidString)")!
        let a = UpgradeBook(persists: true, defaults: d)
        a.add(4, .race, character: 3); a.choose("donut", .race, character: 3)
        let r = UpgradeBook(persists: true, defaults: d)
        XCTAssertEqual(r.points(.race, character: 3), 4); XCTAssertEqual(r.chosen(.race, character: 3), "donut")
        XCTAssertEqual(r.points(.race, character: 0), 0)
    }

    func testPointsByPlace() {
        XCTAssertEqual(UpgradeTuning.racePoints(place: 1), 3)
        XCTAssertEqual(UpgradeTuning.racePoints(place: 2), 2)
        XCTAssertEqual(UpgradeTuning.racePoints(place: 3), 1)
        XCTAssertEqual(UpgradeTuning.racePoints(place: 4), 1)
        XCTAssertEqual(UpgradeTuning.racePoints(place: 0), 0, "no result (abort): nothing")
    }

    func testRaceAwardsPointsOnceAndAbortAwardsNone() {
        let b = book(), s = JellyStats(persists: false, seedWaddle: 0.5)
        let f = RaceFlow()
        f.cue = { _ in }; f.autoRate = 6; f.stats = s; f.upgrades = b; f.playerCharacter = 2
        f.begin(playerID: 0, name: "Moss", player: RacerStats(waddle: 0.9, focus: 1), playerTint: JellyRoster.tint(2), rivalCount: 2, seed: 5)
        for _ in 0..<(60 * 80) { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); if f.hasResults { break } }
        let place = f.sim?.playerPlace ?? 0
        XCTAssertGreaterThan(place, 0)
        let want = UpgradeTuning.racePoints(place: place)
        XCTAssertEqual(b.points(.race, character: 2), want)
        XCTAssertEqual(f.ui.pointsEarned, want); XCTAssertEqual(f.ui.pointsAfter, want)
        for _ in 0..<240 { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
        XCTAssertEqual(b.points(.race, character: 2), want, "settled once: more ticks do not pay again")
        XCTAssertEqual(b.points(.race, character: 0), 0)
        // an aborted race (no results) pays nothing
        let b2 = book(), g = RaceFlow()
        g.cue = { _ in }; g.upgrades = b2; g.playerCharacter = 1
        g.begin(playerID: 0, name: "Pip", player: RacerStats(waddle: 0.5, focus: 0.5), playerTint: JellyRoster.tint(1), rivalCount: 2, seed: 5)
        for _ in 0..<60 { _ = g.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
        XCTAssertFalse(g.hasResults)
        XCTAssertEqual(b2.points(.race, character: 1), 0)
    }

    func testPowerUpIsUsedUpOnceAndCombinesWithoutStacking() {
        let c = GameCare(jellyCount: 1, persistent: false, defaults: UserDefaults(suiteName: "RaceUpgradeTests.care.\(UUID().uuidString)")!)
        Self.keep.append(c)
        let prof = c.jelly(0)!
        c.store.grant("donut", 2)
        c.upgrades.choose("donut", .race, character: prof.character)
        let boost = c.raceStartBoost(prof)
        XCTAssertEqual(boost, RaceBoost.powerUp(.zoomies))
        XCTAssertGreaterThan(boost.strideMul, 1)
        XCTAssertEqual(c.store.count("donut"), 1, "one donut used up, once")
        // the choice stays while he still has some; the next race uses the second
        XCTAssertEqual(c.upgrades.chosen(.race, character: prof.character), "donut")
        _ = c.raceStartBoost(prof)
        XCTAssertEqual(c.store.count("donut"), 0)
        // none left: quietly no boost, and the choice is cleared
        XCTAssertEqual(c.raceStartBoost(prof), .none)
        XCTAssertNil(c.upgrades.chosen(.race, character: prof.character))
        XCTAssertEqual(c.store.count("donut"), 0)
        // an eaten sugar rush plus the same power-up is ONE boost; a focus snack adds its grace
        c.store.grant("donut"); c.upgrades.choose("donut", .race, character: prof.character)
        prof.perks.grant(.zoomies)
        XCTAssertEqual(c.raceStartBoost(prof), RaceBoost.powerUp(.zoomies), "same perk: no stacking")
        XCTAssertFalse(prof.perks.isActive(.zoomies), "the eaten perk is used up too")
        c.store.grant("donut"); c.upgrades.choose("donut", .race, character: prof.character)
        prof.perks.grant(.focus)
        let both = c.raceStartBoost(prof)
        XCTAssertEqual(both.strideMul, RaceBoost.powerUp(.zoomies).strideMul); XCTAssertEqual(both.grace, PerkTuning.focusGrace)
        // a food with no race perk is not a power-up
        c.store.grant("pizza"); c.upgrades.choose("pizza", .race, character: prof.character)
        XCTAssertEqual(c.raceStartBoost(prof), .none)
        XCTAssertEqual(c.store.count("pizza"), 1, "not used up")
    }
}
