//
//  GuestEveningTests.swift
//  2026-11-05: a SLEEPOVER friend only comes in the evening and goes home in the morning (also across a time skip / a closed app); a play date is unchanged (any hour,
//  10...15 minutes); the Jelly Wash is closed while either is coming or here; visitor names are unique (the generator, the writer's check and the save migration).
//

import XCTest
@testable import BobV1

@MainActor
final class GuestEveningTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func suite() -> UserDefaults { UserDefaults(suiteName: "GuestEvening.\(UUID().uuidString)")! }

    // MARK: when he comes

    func testSleepoverArrivalOnlyFromTheEveningPlayDateAnytime() {
        for h in [0.0, 2.0, 5.9, 6, 8, 11, 12, 16.99] {
            XCTAssertFalse(GuestRules.canArrive(.sleepover, hour: h), "\(h): a morning / day / small-hours sleepover waits for the evening")
            XCTAssertTrue(GuestRules.canArrive(.playDate, hour: h), "\(h): a play date comes at any hour")
        }
        for h in [17.0, 18.5, 20.99, 21, 22.5, 23.99] { XCTAssertTrue(GuestRules.canArrive(.sleepover, hour: h), "\(h): evening (and the night before midnight) he comes") }
        XCTAssertEqual(GuestRules.when(hour: 9), "this evening")
        XCTAssertEqual(GuestRules.when(hour: 18), "this evening")
        XCTAssertEqual(GuestRules.when(hour: 22), "tonight")
        XCTAssertEqual(GuestRules.when(hour: 3), "this evening", "after midnight the next evening is the same calendar day")
    }

    func testStatusLineSaysWhenHeComes() {
        let care = GameCare(jellyCount: 1, persistent: false, defaults: suite())
        defer { care.guestBook.finish() }
        care.guestBook.finish()
        XCTAssertNil(care.guestStatusText())
        let name = care.parkBook.visitor(0)!.name
        XCTAssertTrue(care.guestBook.invite(visitor: 0, kind: .sleepover, now: 1000))
        XCTAssertEqual(care.guestStatusText(hour: 10), "\(name) is coming for a sleepover this evening")
        XCTAssertEqual(care.guestStatusText(hour: 1), "\(name) is coming for a sleepover this evening")
        XCTAssertEqual(care.guestStatusText(hour: 18), "\(name) is on the way", "invited in the evening: soon, after the knock")
        XCTAssertEqual(care.guestStatusText(hour: 22), "\(name) is on the way", "at night before midnight he still comes")
        care.guestBook.markArrived(now: 2000)
        XCTAssertEqual(care.guestStatusText(hour: 19), "\(name) is visiting")
        care.guestBook.finish()
        XCTAssertTrue(care.guestBook.invite(visitor: 0, kind: .playDate, now: 1000))
        XCTAssertEqual(care.guestStatusText(hour: 10), "\(name) is on the way", "a play date does not wait for the evening")
    }

    // MARK: when he goes

    func testPlayDateTimingUnchangedSleepoverEndsNextMorning() {
        let cal = utc
        let evening = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 19))!
        let end = GuestRules.endsAt(.sleepover, arrival: evening, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day, .hour, .minute], from: end), DateComponents(day: 6, hour: 7, minute: 30))
        let night = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 23, minute: 30))!
        XCTAssertEqual(cal.component(.day, from: GuestRules.endsAt(.sleepover, arrival: night, calendar: cal)), 6)
        XCTAssertEqual(GuestRules.endsAt(.playDate, arrival: evening, calendar: cal, roll: 0.5).timeIntervalSince(evening), 750, accuracy: 1)
        XCTAssertEqual(GuestRules.endsAt(.playDate, arrival: evening, calendar: cal, roll: 0).timeIntervalSince(evening), 600, accuracy: 1)
        XCTAssertEqual(GuestRules.endsAt(.playDate, arrival: evening, calendar: cal, roll: 1).timeIntervalSince(evening), 900, accuracy: 1)
        // a play date never records a game-clock end; a sleepover does
        let pd = GuestBook(defaults: suite())
        _ = pd.invite(visitor: 1, kind: .playDate, now: 1)
        pd.markArrived(now: 1000, endsGame: 31.5)
        XCTAssertNil(pd.visit?.endsGame)
        XCTAssertLessThanOrEqual(pd.visit!.endsAt - 1000, 900)
        let so = GuestBook(defaults: suite())
        _ = so.invite(visitor: 1, kind: .sleepover, now: 1)
        so.markArrived(now: 1000, sleepoverSeconds: 750, endsGame: 31.5)
        XCTAssertEqual(so.visit?.endsGame, 31.5)
        XCTAssertEqual(so.visit!.endsAt, 1750)
        // the grace after a play date is still 30 minutes
        var v = GuestVisit(visitor: 1, kind: .playDate, invitedAt: 1)
        v.arrivedAt = 1000; v.endsAt = 1700
        XCTAssertEqual(GuestRules.verdict(v, now: 1700 + GuestTuning.graceAfterPlayDate + 1), .wentHome)
        XCTAssertEqual(GuestRules.verdict(v, now: 1700 + 60), .goodbye)
        XCTAssertEqual(GuestRules.note("Poppy", .sleepover), "Poppy went home after the sleepover")
        XCTAssertEqual(GuestRules.note("Poppy", .playDate), "Poppy went home after the play date")
    }

    func testMorningIsJudgedOnTheGameClockAcrossASkip() {
        // arrived at 19:00 game time (day 1 = 19.0), ends 7:30 the next game day (31.5); the wall end is only 750 s later
        var v = GuestVisit(visitor: 1, kind: .sleepover, invitedAt: 100)
        v.arrivedAt = 1000; v.endsAt = 1750; v.endsGame = 31.5
        XCTAssertEqual(GuestRules.verdict(v, now: 1750 + 1200, gameNow: 19.2), .stay)
        XCTAssertFalse(GuestRules.isOver(v, now: 1750 + 1200, gameNow: 19.2))
        XCTAssertEqual(GuestRules.verdict(v, now: 1000 + 9 * 3600, gameNow: 31.0), .stay)
        XCTAssertEqual(GuestRules.verdict(v, now: 1000 + 9 * 3600, gameNow: 31.6), .goodbye)
        XCTAssertEqual(GuestRules.verdict(v, now: 1000 + 9 * 3600, gameNow: 31.5 + GuestTuning.graceGameHours + 1), .wentHome)
        XCTAssertEqual(GuestRules.verdict(v, now: 1750 + GuestTuning.staleAfter + 1, gameNow: 19.2), .wentHome)
        XCTAssertEqual(GuestRules.verdict(v, now: 1700, gameNow: nil), .stay)
        XCTAssertEqual(GuestRules.verdict(v, now: 1800, gameNow: nil), .goodbye)
        XCTAssertEqual(GuestRules.verdict(v, now: 1750 + GuestTuning.graceAfterSleepover + 1, gameNow: nil), .wentHome)
        let book = GuestBook(defaults: suite())
        _ = book.invite(visitor: 1, kind: .sleepover, now: 100)
        book.markArrived(now: 1000, sleepoverSeconds: 750, endsGame: 31.5)
        book.endNow(now: 1100)
        XCTAssertNil(book.visit?.endsGame)
        XCTAssertTrue(GuestRules.isOver(book.visit!, now: 1100, gameNow: 19.5))
    }

    func testGameClockEndsAtNextHalfPastSeven() {
        let d = suite()
        let clock = DayClock(defaults: d)
        let now = clock.gameNow
        let end = clock.sleepoverEndGame
        XCTAssertNotNil(now); XCTAssertNotNil(end)
        let hours = end! - now!
        XCTAssertGreaterThan(hours, 0); XCTAssertLessThanOrEqual(hours, 24)
        XCTAssertEqual(DayMath.wrap(end!), 7.5, accuracy: 1e-6)
    }

    func testOldPlayDateSaveStillLoads() {
        let d = suite()
        let old = Data(#"{"invitedAt":1000,"visitor":2,"kind":"playDate","arrivedAt":0,"endsAt":0}"#.utf8)
        d.set(old, forKey: GuestBook.key)
        let book = GuestBook(defaults: d)
        XCTAssertEqual(book.visit?.visitor, 2)
        XCTAssertEqual(book.visit?.kind, .playDate)
        XCTAssertNil(book.visit?.endsGame)
        XCTAssertTrue(GuestRules.canArrive(book.visit!.kind, hour: 12), "an old play date still comes at any hour")
        book.markArrived(now: 1_800_000_000, calendar: utc)
        XCTAssertLessThanOrEqual(book.visit!.endsAt - 1_800_000_000, 900, "and stays its short time")
        // an arrived old save (short end stored, no game end) is judged on the wall clock as before
        let arrived = Data(#"{"invitedAt":1,"visitor":2,"kind":"playDate","arrivedAt":100,"endsAt":900}"#.utf8)
        d.set(arrived, forKey: GuestBook.key)
        let v = GuestBook(defaults: d).visit!
        XCTAssertEqual(GuestRules.verdict(v, now: 500, gameNow: 20), .stay)
        XCTAssertEqual(GuestRules.verdict(v, now: 1000, gameNow: 20), .goodbye)
    }

    // MARK: the Jelly Wash

    func testJellyWashClosedWhileAFriendIsComingOrHere() {
        let care = GameCare(jellyCount: 1, persistent: false, defaults: suite())
        care.guestBook.finish()
        defer { care.guestBook.finish() }
        XCTAssertNil(care.groomGuestBlocker)
        XCTAssertNotEqual(care.groomBlocker()?.hasPrefix("Not while"), true)
        let name = care.parkBook.visitor(0)!.name
        XCTAssertTrue(care.guestBook.invite(visitor: 0, kind: .sleepover, now: 1000))
        XCTAssertEqual(care.groomGuestBlocker, "Not while \(name) is visiting")
        XCTAssertEqual(care.groomBlocker(), "Not while \(name) is visiting", "on the way: closed")
        care.requestGroom()
        XCTAssertFalse(care.groom.picking, "the picker does not open")
        XCTAssertEqual(care.groom.toast, "Not while \(name) is visiting")
        care.guestBook.markArrived(now: 2000)
        XCTAssertEqual(care.groomBlocker(), "Not while \(name) is visiting", "here: closed")
        care.guestBook.finish()
        XCTAssertNil(care.groomGuestBlocker, "he went home: open again")
        // a play date closes it too, on the way and here
        XCTAssertTrue(care.guestBook.invite(visitor: 0, kind: .playDate, now: 1000))
        XCTAssertEqual(care.groomBlocker(), "Not while \(name) is visiting")
        care.guestBook.markArrived(now: 2000)
        XCTAssertEqual(care.groomBlocker(), "Not while \(name) is visiting")
    }

    // MARK: names

    private func visitor(_ id: Int, _ name: String, _ colour: ParkColour, friendship: [String: Float] = [:], introduced: Bool = true) -> ParkVisitor {
        var v = ParkVisitor(id: id, name: name, colour: colour, signature: colour.speciesFeature, wear: nil, style: .calm, blurb: "", greeting: "")
        v.friendship = friendship; v.introduced = introduced
        return v
    }
    private var reserved: Set<String> { ParkNames.reserved(rosterNames: JellyRoster.baseNames) }

    func testGeneratorNeverReusesOrReservesANameForAnySeed() {
        for seed in [ParkTuning.poolSeed, 1, 2, 99, 12345, 0xDEADBEEF] as [UInt64] {
            let pool = ParkPool.generate(seed: seed)
            let keys = pool.map { ParkNames.key($0.name) }
            XCTAssertEqual(Set(keys).count, pool.count, "unique names (seed \(seed))")
            XCTAssertTrue(Set(keys).isDisjoint(with: reserved), "no Jelbie / personality / colour name (seed \(seed))")
        }
        // an extra reserved set is honoured too
        let pool = ParkPool.generate(reserved: Set(ParkWords.names.prefix(12).map(ParkNames.key)))
        XCTAssertTrue(Set(pool.map { ParkNames.key($0.name) }).isDisjoint(with: Set(ParkWords.names.prefix(12).map(ParkNames.key))))
        XCTAssertEqual(Set(pool.map { ParkNames.key($0.name) }).count, pool.count)
        for n in ["Bob", "Pip", "Moss", "Lavender", "Teddy", "Pearl", "Panda", "Zippy", "Mellow", "Mint", "Coral"] { XCTAssertTrue(reserved.contains(ParkNames.key(n)), n) }
    }

    func testWriterNamesMustBeFree() {
        var taken = reserved
        taken.insert(ParkNames.key("Luma"))
        XCTAssertFalse(ParkNames.isFree("luma", taken: taken))
        XCTAssertFalse(ParkNames.isFree("Pip", taken: taken))
        XCTAssertFalse(ParkNames.isFree("Zippy", taken: taken))
        XCTAssertFalse(ParkNames.isFree("  ", taken: taken))
        XCTAssertTrue(ParkNames.isFree("Coco", taken: taken))
    }

    func testMigrationMergesTwinsRenamesNamesakesAndIsIdempotent() {
        var vs: [ParkVisitor] = [
            visitor(0, "Zippy", .blue, friendship: ["4": 80, "6": 10]),                      // reserved (a personality word): renamed
            visitor(1, "Luma", .green, friendship: ["4": 50, "6": 90]),                      // keeps the name (first)
            visitor(2, "Luma", .green, friendship: ["4": 70, "5": 30]),                      // a true twin of 1: merged
            visitor(3, "Luma", .yellow, friendship: ["4": 46]),                              // a namesake, different colour: renamed, friendship kept
            visitor(4, "Pip", .lavender, friendship: ["6": 100]),                            // a Jelbie's name: renamed
            visitor(5, "Coco", .teal), visitor(6, "coco ", .teal),                          // case / space twin of 5: merged
        ]
        XCTAssertTrue(ParkNames.reconcile(&vs, reserved: reserved))
        // the twins: the survivor has the max per character, the twin points at it
        XCTAssertEqual(vs[2].mergedInto, 1)
        XCTAssertEqual(vs[1].friendship["4"], 70); XCTAssertEqual(vs[1].friendship["6"], 90); XCTAssertEqual(vs[1].friendship["5"], 30)
        XCTAssertEqual(vs[6].mergedInto, 5)
        // the namesake keeps its friendship and gets a fresh unique name
        XCTAssertNil(vs[3].mergedInto)
        XCTAssertEqual(vs[3].friendship["4"], 46)
        XCTAssertNotEqual(ParkNames.key(vs[3].name), "luma")
        // reserved names are gone
        XCTAssertFalse(reserved.contains(ParkNames.key(vs[0].name))); XCTAssertEqual(vs[0].friendship["4"], 80)
        XCTAssertFalse(reserved.contains(ParkNames.key(vs[4].name))); XCTAssertEqual(vs[4].friendship["6"], 100)
        // every live visitor has a unique, free name
        let live = vs.filter { $0.mergedInto == nil }
        let keys = live.map { ParkNames.key($0.name) }
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(Set(keys).isDisjoint(with: reserved))
        // idempotent: a second run (and a third) changes nothing
        let once = vs
        XCTAssertFalse(ParkNames.reconcile(&vs, reserved: reserved))
        XCTAssertEqual(vs, once)
        XCTAssertFalse(ParkNames.reconcile(&vs, reserved: reserved))
        XCTAssertEqual(vs, once)
    }

    func testParkBookMigratesASaveOnLoadAndAMergedGuestFollowsTheSurvivor() throws {
        let d = suite()
        var vs = ParkPool.generate()
        // a true twin pair: two records with one name whose generated colours match (a load takes the colours from the generator)
        var pair: (Int, Int)?
        outer: for a in 0..<vs.count { for b in (a + 1)..<vs.count where vs[a].colour == vs[b].colour { pair = (a, b); break outer } }
        let (lo, hi) = try XCTUnwrap(pair)
        vs[hi].name = "Luma"; vs[lo].name = "Luma"
        let other = vs.indices.first { $0 != lo && $0 != hi }!
        vs[lo].friendship = ["4": 60]; vs[hi].friendship = ["4": 90, "6": 20]
        vs[other].name = "Pip"; vs[other].friendship = ["6": 50]
        d.set(try JSONEncoder().encode(vs), forKey: ParkBook.key)
        let book = ParkBook(defaults: d)
        let a = book.visitors
        XCTAssertEqual(a[hi].mergedInto, lo)
        XCTAssertEqual(a[lo].friendship["4"], 90); XCTAssertEqual(a[lo].friendship["6"], 20)
        XCTAssertEqual(book.visitor(hi)?.id, lo, "a lookup by the merged id answers with the survivor")
        XCTAssertNotEqual(ParkNames.key(a[other].name), "pip"); XCTAssertEqual(a[other].friendship["6"], 50)
        XCTAssertFalse(book.chooseCast(count: 16, characters: [4], now: 0).contains { $0.id == hi }, "a merged twin never goes to the park")
        // saved: a second load changes nothing
        let again = ParkBook(defaults: d)
        XCTAssertEqual(again.visitors, a)
        // points added to the merged id land on the survivor
        _ = book.add(points: 5, visitor: hi, character: 7)
        XCTAssertEqual(book.visitors[lo].friendship["7"], 5)
        // a guest invited as the merged twin is pointed at the survivor
        let g = GuestBook(defaults: suite())
        _ = g.invite(visitor: hi, kind: .sleepover, now: 1)
        g.repoint(to: book.visitor(hi)!.id)
        XCTAssertEqual(g.visit?.visitor, lo)
    }

    func testFriendsToInviteHasNoDuplicateNames() {
        let care = GameCare(jellyCount: 1, persistent: false, defaults: suite())
        defer { UserDefaults.standard.removeObject(forKey: ParkBook.key) }
        let c = care.jelly(0)!.character
        let book = care.parkBook
        for v in book.visitors.indices {
            book.markSeen([v], at: 1)
            _ = book.add(points: 100, visitor: v, character: c)
        }
        let list = care.friendsToInvite()
        let keys = list.map { ParkNames.key($0.name) }
        XCTAssertEqual(Set(keys).count, keys.count, "one card per friend, no repeated names")
        // sorted: best level first, then by name
        let sortedNames = list.map(\.name)
        XCTAssertEqual(sortedNames, sortedNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, "all best friends: by name")
    }
}
