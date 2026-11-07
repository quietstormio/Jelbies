//
//  ParkVarietyTests.swift
//  More park friends (pool 16 -> 48, an old save keeps its friends) and competition rivals that do not repeat (one big name list, 12 hues, a recent memory).
//

import XCTest
@testable import BobV1

@MainActor
final class ParkVarietyTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "ParkVarietyTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testOldSaveOfSixteenGrowsToFortyEightKeepingFriends() throws {
        var old = ParkPool.generate()
        XCTAssertEqual(old.count, ParkTuning.poolSize)
        old[3].friendship["0"] = 80; old[3].introduced = true; old[3].lastSeen = 123
        old[7].friendship["1"] = 30
        let d = freshDefaults()
        d.set(try JSONEncoder().encode(old), forKey: ParkBook.key)
        let book = ParkBook(defaults: d)
        XCTAssertEqual(book.visitors.count, 48)
        for i in 0..<16 {
            XCTAssertEqual(book.visitors[i].id, old[i].id)
            XCTAssertEqual(book.visitors[i].name, old[i].name)
            XCTAssertEqual(book.visitors[i].colour, old[i].colour)
            XCTAssertEqual(book.visitors[i].friendship, old[i].friendship)
        }
        XCTAssertEqual(book.visitors.map(\.id), Array(0..<48))
        // saved at once, and a second load keeps it
        let again = ParkBook(defaults: d)
        XCTAssertEqual(again.visitors, book.visitors)
        // the extras follow the signature rule
        for v in book.visitors { XCTAssertEqual(v.signature, v.colour.speciesFeature); XCTAssertTrue(JellyVariantBook.parkEligible(v.colour)) }
        // a new player gets the same 48
        XCTAssertEqual(ParkBook(defaults: freshDefaults()).visitors.map(\.name), book.visitors.map(\.name))
    }

    func testAllFortyEightNamesAreUniqueAndNotCompetitionNames() {
        let pool = ParkPool.all(reserved: ParkBook.reservedNames())
        XCTAssertEqual(pool.count, 48)
        let keys = pool.map { ParkNames.key($0.name) }
        XCTAssertEqual(Set(keys).count, 48, "every park name is unique")
        XCTAssertTrue(Set(keys).isDisjoint(with: Set(RivalNames.all.map(ParkNames.key))), "no park visitor shares a name with a competition rival")
        XCTAssertEqual(Set(RivalNames.all.map(ParkNames.key)).count, RivalNames.all.count)
        XCTAssertGreaterThanOrEqual(RivalNames.all.count, 48)
        XCTAssertEqual(Set(ParkWords.extraNames.map(ParkNames.key)).count, ParkTuning.extraCount)
        XCTAssertEqual(Set(keys.suffix(32)), Set(ParkWords.extraNames.map(ParkNames.key)), "the extras kept their own names")
        for v in pool.suffix(32) { XCTAssertTrue(ParkTextSafety.isSafe(v.name, isName: true), v.name) }
        for n in RivalNames.all { XCTAssertTrue(ParkTextSafety.isSafe(n, isName: true), n) }
    }

    func testRaceRivalsSkipRecentNames() {
        let me = RacerStats(waddle: 0.5, focus: 0.5), tint = JellyRoster.tint(0)
        let recent = Array(RivalNames.all.prefix(9))
        let src = LocalRivalSource(recent: recent)
        for seed in UInt64(1)...300 {
            let rs = src.rivals(count: 3, player: me, playerTint: tint, seed: seed)
            XCTAssertEqual(Set(rs.map(\.name)).count, 3)
            for r in rs { XCTAssertFalse(recent.contains(r.name), "seed \(seed): \(r.name) was met recently") }
        }
        // too few left: falls back instead of crashing
        let many = LocalRivalSource(recent: RivalNames.all)
        XCTAssertEqual(many.rivals(count: 2, player: me, playerTint: tint, seed: 1).count, 2)
    }

    func testRecentMemoryKeepsTheLastNine() {
        let d = freshDefaults()
        RivalMemory.remember(["A", "B", "C", "D", "E"], in: d)
        RivalMemory.remember(["F", "G", "H", "I", "J", "K"], in: d)
        XCTAssertEqual(RivalMemory.load(d), ["C", "D", "E", "F", "G", "H", "I", "J", "K"])
    }

    func testRaceRivalsAlwaysReturnCountWhateverThePlayerHue() {
        let me = RacerStats(waddle: 0.5, focus: 0.5)
        for h in RivalNames.hues + [0, 0.3, 0.99] {
            let tint = LocalRivalSource.hsv(h, 0.34, 0.96)
            for count in 0...6 {
                let rs = LocalRivalSource().rivals(count: count, player: me, playerTint: tint, seed: UInt64(count) &+ 9)
                XCTAssertEqual(rs.count, count)
                XCTAssertEqual(Set(rs.map(\.name)).count, count)
            }
        }
    }

    func testHuesSitInsideOneSignatureBand() {
        XCTAssertEqual(RivalNames.hues.count, 12)
        let edges: [Float] = [0.10, 0.17, 0.45, 0.60, 0.85]
        for h in RivalNames.hues {
            for e in edges { XCTAssertGreaterThan(abs(h - e), 0.02, "hue \(h) too near \(e)") }
        }
        let sigs = Set(RivalNames.hues.map { LocalRivalSource.signature(forTint: LocalRivalSource.hsv($0, 0.34, 0.96)) })
        XCTAssertEqual(sigs.count, 4, "plain, wings, spikes and daisy all appear")
    }
}
