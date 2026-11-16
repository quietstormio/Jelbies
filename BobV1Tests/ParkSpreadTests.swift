//
//  ParkSpreadTests.swift
//  A mixed park (Park/ParkPlayTuning.swift `spreadNew`, `-ParkSpread old` = off): who comes (ParkPool.pickCast) over 200 visit seeds, household of two greens / a green and a lavender.
//

import XCTest
@testable import BobV1

nonisolated struct SplitMix: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E37_79B9_7F4A_7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return z ^ (z >> 31) }
}

@MainActor
final class ParkSpreadTests: XCTestCase {
    override func tearDown() { ParkPlayTuning.spreadNew = true }

    private func run(household: Set<Int>, characters: [Int], count: Int, friendID: Int?, new: Bool) -> (share: Double, minKinds: Int, friendShare: Double, visits: Int) {
        ParkPlayTuning.spreadNew = new
        var pool = ParkPool.all()
        if let f = friendID { pool[f].friendship[String(characters[0])] = 50 }          // (level 2: a friend)
        var own = 0, total = 0, minKinds = 99, friendIn = 0
        for seed in 0..<200 {
            var rng = SplitMix(s: UInt64(seed) &* 0x1234_5679 &+ 7)
            let cast = ParkPool.pickCast(from: pool, count: count, characters: characters, now: 1_000_000, household: household, using: &rng)
            for v in cast { total += 1; if household.contains(v.kind) { own += 1 } }
            if count >= 3 { minKinds = min(minKinds, Set(cast.map(\.kind)).count) }
            if let f = friendID, cast.contains(where: { $0.id == f }) { friendIn += 1 }
        }
        return (Double(own) / Double(total), minKinds, Double(friendIn) / 200, 200)
    }

    func testHouseholdKindsAreRarerAndVisitsAreMixed() {
        let pool = ParkPool.all()
        XCTAssertEqual(Set(pool.map(\.kind)), [0, 1, 2, 3], "the pool has all four kinds")
        for (label, household, chars) in [("two greens", Set([2]), [2, 102]), ("a green and a lavender", Set([2, 3]), [2, 3])] {
            let before = run(household: household, characters: chars, count: 4, friendID: nil, new: false)
            let after = run(household: household, characters: chars, count: 4, friendID: nil, new: true)
            MotionLog.write(String(format: "SPREAD %@: visitors of the household's kinds %.2f -> %.2f; fewest kinds in a 4-visitor visit %d -> %d", label, before.share, after.share, before.minKinds, after.minKinds))
            XCTAssertLessThan(after.share, before.share * 0.8, "\(label): fewer of the household's own kinds")
            XCTAssertLessThan(after.share, 0.4, "\(label): well under half")
            XCTAssertGreaterThanOrEqual(after.minKinds, 3, "\(label): at least three different kinds in every 4-visitor visit")
            let three = run(household: household, characters: chars, count: 3, friendID: nil, new: true)
            XCTAssertGreaterThanOrEqual(three.minKinds, 3, "\(label): a 3-visitor visit is three different kinds")
        }
    }

    func testAFriendStillComesBackAtLeastAsOften() {
        let pool = ParkPool.all()
        let friend = pool.first { $0.kind == 2 }!.id          // (a green visitor, a friend of the green at home)
        let before = run(household: [2], characters: [2, 102], count: 3, friendID: friend, new: false)
        let after = run(household: [2], characters: [2, 102], count: 3, friendID: friend, new: true)
        MotionLog.write(String(format: "SPREAD friend: in %.2f of the visits before, %.2f after", before.friendShare, after.friendShare))
        XCTAssertGreaterThanOrEqual(after.friendShare, before.friendShare * 0.95, "the friend comes back at least about as often")
    }

    /// The special species: six visitors after the extras, each with the species' own feature; an old save of 48 grows to 54 and keeps its friends; classic visitors have no species.
    func testSpecialSpeciesVisitors() throws {
        let pool = ParkPool.all(reserved: ParkBook.reservedNames())
        let sp = pool.filter { $0.species != nil }
        XCTAssertEqual(sp.count, ParkTuning.speciesVisitorCount)
        XCTAssertEqual(sp.map(\.id), Array(48..<54))
        XCTAssertEqual(Set(sp.compactMap(\.species)), [JellyRoster.teddyID, JellyRoster.pearlID, JellyRoster.pandaID])
        for v in sp { XCTAssertEqual(v.signature, JellyRoster.feature(v.species!), "\(v.name): the species' own feature"); XCTAssertNil(v.wear); XCTAssertEqual(v.kind, v.species) }
        XCTAssertTrue(pool.filter { $0.species == nil }.allSatisfy { [0, 1, 2, 3].contains($0.kind) })
        XCTAssertEqual(Set(pool.map(\.kind)), [0, 1, 2, 3, 4, 5, 6], "all seven kinds")
        // an old save keeps its friends and gains the six
        var old = Array(pool[0..<48]); old[5].friendship["2"] = 60
        let d = UserDefaults(suiteName: "parkspread.\(UUID().uuidString)")!
        d.set(try JSONEncoder().encode(old), forKey: ParkBook.key)
        let book = ParkBook(defaults: d)
        XCTAssertEqual(book.visitors.count, 54); XCTAssertEqual(book.visitors[5].friendship["2"], 60)
        XCTAssertEqual(book.visitors.filter { $0.species != nil }.count, 6)
        // with seven kinds the household's share falls further (a visit of four)
        ParkPlayTuning.spreadNew = true
        var own = 0, total = 0
        for seed in 0..<200 {
            var rng = SplitMix(s: UInt64(seed) &* 0x1234_5679 &+ 11)
            for v in ParkPool.pickCast(from: pool, count: 4, characters: [2, 102], now: 1_000_000, household: [2], using: &rng) { total += 1; if v.kind == 2 { own += 1 } }
        }
        MotionLog.write(String(format: "SPREAD seven kinds, two greens at home: the household's kind is %.2f of the visitors (4 per visit)", Double(own) / Double(total)))
        XCTAssertLessThan(Double(own) / Double(total), 0.15)
    }
}
