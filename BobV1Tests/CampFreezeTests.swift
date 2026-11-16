//
//  CampFreezeTests.swift
//  Frozen at Camp: a creature that comes home after weeks gets its saved clocks set to now, so no time away is applied; a home creature over the same weeks still gets
//  the existing gentle time-away treatment. Injected clocks; own UserDefaults suites.
//

import XCTest
@testable import BobV1

@MainActor
final class CampFreezeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var suites: [String] = []
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var weeks: Date { t0.addingTimeInterval(14 * 86400) }

    override func tearDown() { for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }; suites = [] }
    private func suite() -> UserDefaults {
        let s = "CampFreezeTests.\(UUID().uuidString)"; suites.append(s)
        return UserDefaults(suiteName: s)!
    }
    /// Saves a creature's three clocks as of `t0` under the keys of instance `id`: hunger .6, thirst .5, attention .4, dirt .3, a condition stat .7.
    private func leave(_ id: Int, _ d: UserDefaults) {
        let n = BlobNeeds(defaults: d, key: JellyKeys.needs(id), now: { self.t0 })
        n.set(.hunger, 0.6); n.set(.thirst, 0.5); n.set(.attention, 0.4); n.save()
        let g = BlobGrime(persists: true, defaults: d, key: JellyKeys.grime(id), now: { self.t0 })
        g.dirt = 0.3; g.save()
        let s = JellyStats(persists: true, defaults: d, key: JellyKeys.stats(id), now: { self.t0 })
        s.setCondition(.cute, 0.7)
        Self.keep += [n as AnyObject, g as AnyObject, s as AnyObject]
    }

    func testHomeCreatureOverWeeksStillGetsTheGentleTimeAway() {
        let d = suite(); leave(2, d)
        let n = BlobNeeds(defaults: d, key: JellyKeys.needs(2), now: { self.weeks })
        XCTAssertGreaterThan(n.lastAway, 0, "the existing treatment applies the time away")
        XCTAssertLessThan(n.level(.hunger), 0.6)
        let g = BlobGrime(persists: true, defaults: d, key: JellyKeys.grime(2), now: { self.weeks })
        XCTAssertGreaterThan(g.dirt, 0.3)
        let s = JellyStats(persists: true, defaults: d, key: JellyKeys.stats(2), now: { self.weeks })
        XCTAssertLessThan(s.condition(.cute), 0.7)
        Self.keep += [n as AnyObject, g as AnyObject, s as AnyObject]
    }

    func testRestampedCreatureComesHomeExactlyAsItLeft() {
        for id in [2, 0, 100] {          // 0 uses the legacy bare keys
            let d = suite()
            if id >= 100 { JellyRoster.speciesMap[100] = 1 }
            leave(id, d)
            JellyCamp.restamp(id, now: weeks, d)
            let n = BlobNeeds(defaults: d, key: JellyKeys.needs(id), now: { self.weeks })
            XCTAssertEqual(n.lastAway, 0, "id \(id)")
            XCTAssertEqual(n.level(.hunger), 0.6, accuracy: 1e-5); XCTAssertEqual(n.level(.thirst), 0.5, accuracy: 1e-5); XCTAssertEqual(n.level(.attention), 0.4, accuracy: 1e-5)
            XCTAssertEqual(n.asleepNow, false)
            let g = BlobGrime(persists: true, defaults: d, key: JellyKeys.grime(id), now: { self.weeks })
            XCTAssertEqual(g.lastAway, 0, "id \(id)")
            XCTAssertEqual(g.dirt, 0.3, accuracy: 1e-5)
            let s = JellyStats(persists: true, defaults: d, key: JellyKeys.stats(id), now: { self.weeks })
            XCTAssertEqual(s.condition(.cute), 0.7, accuracy: 1e-5, "condition does not decay at Camp")
            Self.keep += [n as AnyObject, g as AnyObject, s as AnyObject]
            if id >= 100 { JellyRoster.speciesMap[100] = nil }
        }
    }

    func testConditionDecayBeforeTheSendIsNotHandedBackOnTheWayHome() {
        let d = suite()
        // the stat was last set 10 days before the send (a meal long ago): by then it has decayed
        let s = JellyStats(persists: true, defaults: d, key: JellyKeys.stats(2), now: { self.t0 })
        s.setCondition(.cute, 0.7); Self.keep.append(s)
        let send = t0.addingTimeInterval(10 * 86400)
        let atSend = JellyStats(persists: true, defaults: d, key: JellyKeys.stats(2), now: { send }).condition(.cute)
        XCTAssertLessThan(atSend, 0.7, "it decays while at home")
        JellyCamp.settleCondition(2, now: send, d)
        JellyCamp.restamp(2, now: weeks, d)          // weeks at Camp, then home
        let home = JellyStats(persists: true, defaults: d, key: JellyKeys.stats(2), now: { self.weeks })
        XCTAssertEqual(home.condition(.cute), atSend, accuracy: 1e-4, "it comes home with what it had when it left, not what it had at the last meal")
        Self.keep.append(home)
    }

    func testRestampClearsAFrozenAsleepFlag() {
        let d = suite()
        d.set(["levels": [0.9, 0.9, 0.9], "time": t0.timeIntervalSince1970, "asleep": true] as [String: Any], forKey: JellyKeys.needs(1))
        JellyCamp.restamp(1, now: weeks, d)
        let saved = d.dictionary(forKey: JellyKeys.needs(1))
        XCTAssertEqual(saved?["asleep"] as? Bool, false)
        XCTAssertEqual(saved?["time"] as? Double, weeks.timeIntervalSince1970)
        XCTAssertEqual(saved?["levels"] as? [Double], [0.9, 0.9, 0.9], "levels untouched")
    }

    func testMissingKeysStayMissingAndNothingElseIsTouched() {
        let d = suite()
        d.set("keep", forKey: "BlobPerks.v1.jelly3")
        JellyCamp.restamp(3, now: weeks, d)
        XCTAssertNil(d.object(forKey: JellyKeys.needs(3))); XCTAssertNil(d.object(forKey: JellyKeys.grime(3))); XCTAssertNil(d.object(forKey: JellyKeys.stats(3) + ".cond"))
        XCTAssertEqual(d.string(forKey: "BlobPerks.v1.jelly3"), "keep", "boosts are not restamped: they run out on the clock")
    }

    func testRestampingOneCreatureLeavesTheOthersAlone() {
        let d = suite(); leave(1, d); leave(2, d)
        JellyCamp.restamp(1, now: weeks, d)
        let other = BlobNeeds(defaults: d, key: JellyKeys.needs(2), now: { self.weeks })
        XCTAssertGreaterThan(other.lastAway, 0, "the other one's stamp is as it was")
        Self.keep.append(other)
    }

    func testNothingTicksForACampCreature() {
        // A Camp creature has no profile in any room: the room's profiles are built from the home roster only.
        let d = suite()
        d.set([0, 1, 2], forKey: JellyRoster.rosterKey); d.set([3], forKey: JellyCamp.key)
        let care = GameCare(roster: JellyRoster.savedIDs(d), persistent: false, defaults: d); Self.keep.append(care)
        XCTAssertEqual(care.jellies.map(\.character), [0, 1, 2])
        XCTAssertFalse(care.jellies.contains { $0.character == 3 }, "needs / grime / bubbles / the night routine only ever see the three at home")
        // and building the yard's in-memory profiles writes nothing
        leave(3, d)
        let before = d.dictionaryRepresentation().filter { $0.key.hasPrefix("Blob") }.mapValues { "\($0)" }
        let yard = JellyCamp.profiles(d)
        XCTAssertEqual(yard.map(\.character), [3]); XCTAssertEqual(yard.map(\.id), [0])
        XCTAssertEqual(d.dictionaryRepresentation().filter { $0.key.hasPrefix("Blob") }.mapValues { "\($0)" }, before, "yard profiles are in memory: nothing read-applied, nothing written")
        Self.keep += yard.map { $0 as AnyObject }
    }
}
