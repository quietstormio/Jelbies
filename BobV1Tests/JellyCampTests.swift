//
//  JellyCampTests.swift
//  Jelmiko Camp, the model: the loader, the pure rules, the crash-safe write order (a kill after every single write), the price, and the id-collision fix
//  (a buyer must never reuse the id of a creature staying at Camp). Fast and pure: own UserDefaults suites; the process-wide maps are put back in tearDown.
//

import XCTest
@testable import BobV1

@MainActor
final class JellyCampTests: XCTestCase {
    private var savedCurrent: [Int] = []
    private var savedMap: [Int: Int] = [:]
    private var savedNames: [Int: String] = [:]
    private var savedBase: [String] = []
    private var suites: [String] = []

    override func setUp() {
        savedCurrent = JellyRoster.current; savedMap = JellyRoster.speciesMap; savedNames = JellyRoster.extraNames; savedBase = JellyRoster.names
        JellyRoster.speciesMap = [:]; JellyRoster.extraNames = [:]
    }
    override func tearDown() {
        JellyRoster.current = savedCurrent; JellyRoster.speciesMap = savedMap; JellyRoster.extraNames = savedNames; JellyRoster.names = savedBase
        JellyVariants.reload(); JellyVariants.clearPreviews(); JellyTraitsBook.reload()
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
    }
    private func suite() -> UserDefaults {
        let s = "JellyCampTests.\(UUID().uuidString)"; suites.append(s)
        return UserDefaults(suiteName: s)!
    }
    /// Valid ids: 0...6 are the species, then two recorded duplicates (100, 101).
    private func nine(_ d: UserDefaults) -> [Int] {
        var ids = Array(0..<7)
        ids.append(JellyRoster.allocateInstance(species: 0, roster: [0], d))
        ids.append(JellyRoster.allocateInstance(species: 1, roster: [1], d))
        return ids
    }
    private func seed(_ d: UserDefaults, home: [Int], camp: [Int]) { d.set(home, forKey: JellyRoster.rosterKey); d.set(camp, forKey: JellyCamp.key) }
    private func assertSane(_ l: JellyCamp.Lists, all: [Int], _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(JellyCamp.owned(home: l.home, camp: l.camp)), Set(all), "nobody lost, nobody invented: \(msg)", file: file, line: line)
        XCTAssertEqual(l.home.count + l.camp.count, all.count, "nobody doubled: \(msg)", file: file, line: line)
        XCTAssertTrue(JellyCamp.isConsistent(l), "1...3 home, camp <= cap, disjoint: \(msg) \(l)", file: file, line: line)
    }

    func testTheCapIsSix() { XCTAssertEqual(JellyCamp.cap, 6) }

    // MARK: load

    func testLoadEmptyKeyIsEmptyAndNeverInventsTheStarters() {
        let d = suite()
        XCTAssertEqual(JellyCamp.load(home: [0, 1, 2], d), [])
        d.set([Int](), forKey: JellyCamp.key)
        XCTAssertEqual(JellyCamp.load(home: [0, 1, 2], d), [], "an empty list stays empty (sanitised would give [0,1,2])")
        XCTAssertEqual(JellyCamp.saved(d), [])
    }
    func testLoadDropsPreviewsUnknownIdsAndRepeats() {
        let d = suite()
        d.set([3, 3, 4, 1004, 555, -1, 5], forKey: JellyCamp.key)
        XCTAssertEqual(JellyCamp.load(home: [0, 1, 2], d), [3, 4, 5])
    }
    func testAnIdInBothListsStaysHome() {
        let d = suite()
        seed(d, home: [0, 1, 2], camp: [1, 3])
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 1, 2])
        XCTAssertEqual(JellyCamp.saved(d), [3])
    }
    func testLoadCutsToTheCap() {
        let d = suite()
        let ids = nine(d)
        d.set(Array(ids.suffix(JellyCamp.cap + 1)), forKey: JellyCamp.key)
        XCTAssertEqual(JellyCamp.load(home: [], d).count, JellyCamp.cap)
    }
    func testOldSaveHasAnEmptyCamp() {
        let d = suite()
        d.set([0, 1, 2], forKey: JellyRoster.rosterKey)
        XCTAssertNil(d.object(forKey: JellyCamp.key))
        XCTAssertEqual(JellyCamp.savedLists(d).camp, [])
        XCTAssertEqual(JellyCamp.savedLists(d).home, [0, 1, 2])
    }

    // MARK: rules

    func testDestination() {
        XCTAssertEqual(JellyCamp.destination(home: 0, camp: 0), .home)
        XCTAssertEqual(JellyCamp.destination(home: 2, camp: 0), .home)
        XCTAssertEqual(JellyCamp.destination(home: 3, camp: 0), .camp)
        XCTAssertEqual(JellyCamp.destination(home: 3, camp: JellyCamp.cap - 1), .camp)
        XCTAssertEqual(JellyCamp.destination(home: 3, camp: JellyCamp.cap), .full)
    }
    func testBringHomeSendToCampAndSwapKeepEveryone() {
        let all = [0, 1, 2, 3, 4, 5]
        var l = JellyCamp.bringHome(3, home: [0, 1], camp: [3, 4, 5])
        XCTAssertEqual(l?.home, [0, 1, 3], "appended to the END of home")
        XCTAssertEqual(l?.camp, [4, 5])
        assertSane(l!, all: [0, 1, 3, 4, 5], "bring home")
        XCTAssertNil(JellyCamp.bringHome(3, home: [0, 1, 2], camp: [3]), "home is full")
        XCTAssertNil(JellyCamp.bringHome(9, home: [0], camp: [3]), "not at Camp")
        l = JellyCamp.sendToCamp(1, home: [0, 1, 2], camp: [3, 4, 5])
        XCTAssertEqual(l?.home, [0, 2]); XCTAssertEqual(l?.camp, [3, 4, 5, 1])
        assertSane(l!, all: all, "send")
        l = JellyCamp.swap(in: 4, out: 1, home: [0, 1, 2], camp: [3, 4, 5])
        XCTAssertEqual(l?.home, [0, 4, 2], "the incoming one takes the outgoing one's SLOT; the others do not move")
        XCTAssertEqual(l?.camp, [3, 1, 5], "and the outgoing one takes its place at Camp")
        assertSane(l!, all: all, "swap")
        XCTAssertNil(JellyCamp.swap(in: 1, out: 4, home: [0, 1, 2], camp: [3, 4, 5]), "wrong sides")
        XCTAssertNil(JellyCamp.swap(in: 3, out: 3, home: [0, 1, 2], camp: [3]))
    }
    func testNobodyCanBeSentAwayWhenOnlyOneIsHome() {
        XCTAssertFalse(JellyCamp.canSendToCamp(5, home: [5], camp: []))
        XCTAssertNil(JellyCamp.sendToCamp(5, home: [5], camp: []), "home [5], send 5: refused (home must never be empty, the starters must never come back)")
        XCTAssertTrue(JellyCamp.canSendToCamp(5, home: [5, 1], camp: []))
        XCTAssertFalse(JellyCamp.canSendToCamp(5, home: [5, 1], camp: [2, 3, 4, 0, 6, 100].prefix(JellyCamp.cap).map { $0 }), "Camp is full")
        XCTAssertFalse(JellyCamp.canSendToCamp(7, home: [5, 1], camp: []), "not at home")
        XCTAssertTrue(JellyCamp.swap(in: 3, out: 5, home: [5], camp: [3]) != nil, "a swap keeps one at home, so it is allowed with one at home")
    }
    func testTheCampNeverTakesMoreThanTheCap() {
        let camp = Array(0..<JellyCamp.cap)
        XCTAssertNil(JellyCamp.sendToCamp(10, home: [10, 11], camp: camp))
        XCTAssertNotNil(JellyCamp.sendToCamp(10, home: [10, 11], camp: Array(camp.dropLast())))
    }

    // MARK: commit: a kill after every write

    /// Runs a move with the app killed after k writes (k = 0 ... all), for every k: reload through the loaders and check everyone exists once.
    private func killTest(home: [Int], camp: [Int], move: (JellyCamp.Lists) -> JellyCamp.Lists?, _ name: String, expectHomeAfterFirstWrite: [Int]? = nil) {
        let all = JellyCamp.owned(home: home, camp: camp)
        guard let target = move((home, camp)) else { return XCTFail("\(name): the move was refused") }
        let n = JellyCamp.writes(from: (home, camp), to: target).count
        XCTAssertGreaterThan(n, 0, name)
        for k in 0...n {
            let d = suite()
            seed(d, home: home, camp: camp)
            XCTAssertTrue(JellyCamp.commit(from: (home, camp), to: target, d, stopAfter: k), "\(name) k=\(k)")
            assertSane(JellyCamp.savedLists(d), all: all, "\(name), killed after \(k) of \(n) writes")
            if k == n { XCTAssertEqual(JellyCamp.savedLists(d).home, target.home, name); XCTAssertEqual(JellyCamp.savedLists(d).camp, target.camp, name) }
            if k == 0 { XCTAssertEqual(JellyCamp.savedLists(d).home, home, "\(name): killed before the first write = nothing happened") }
        }
    }
    func testKillAfterEveryWriteBringHome() { killTest(home: [0, 1], camp: [3, 4, 5], move: { JellyCamp.bringHome(4, home: $0.home, camp: $0.camp) }, "bring home") }
    func testKillAfterEveryWriteSendToCamp() { killTest(home: [0, 1, 2], camp: [3], move: { JellyCamp.sendToCamp(1, home: $0.home, camp: $0.camp) }, "send") }
    func testKillAfterEveryWriteSwap() { killTest(home: [0, 1, 2], camp: [3, 4, 5], move: { JellyCamp.swap(in: 4, out: 1, home: $0.home, camp: $0.camp) }, "swap") }
    func testKillAfterEveryWriteSwapWithAFullCamp() {
        let d = suite(); let ids = nine(d)
        killTest(home: Array(ids.prefix(3)), camp: Array(ids.dropFirst(3).prefix(JellyCamp.cap)), move: { JellyCamp.swap(in: ids[5], out: ids[0], home: $0.home, camp: $0.camp) }, "swap, full Camp")
        killTest(home: Array(ids.prefix(3)), camp: Array(ids.dropFirst(3).prefix(JellyCamp.cap)), move: { JellyCamp.swap(in: ids[3], out: ids[2], home: $0.home, camp: $0.camp) }, "swap, full Camp, first one")
    }
    func testKillAfterEveryWriteSendDownToOneAtHome() { killTest(home: [4, 1], camp: [], move: { JellyCamp.sendToCamp(1, home: $0.home, camp: $0.camp) }, "send, leaving one") }
    func testCommitRefusesAnInconsistentOrChangedSet() {
        let d = suite()
        seed(d, home: [0, 1, 2], camp: [3])
        XCTAssertFalse(JellyCamp.commit(from: ([0, 1, 2], [3]), to: ([], [0, 1, 2, 3]), d), "nobody at home")
        XCTAssertFalse(JellyCamp.commit(from: ([0, 1, 2], [3]), to: ([0, 1, 2], [3, 4]), d), "somebody invented")
        XCTAssertFalse(JellyCamp.commit(from: ([0, 1, 2], [3]), to: ([0, 1], [3]), d), "somebody lost")
        XCTAssertFalse(JellyCamp.commit(from: ([0, 1, 2], [3]), to: ([0, 1, 2, 3], []), d), "four at home")
        XCTAssertEqual(JellyCamp.savedLists(d).home, [0, 1, 2]); XCTAssertEqual(JellyCamp.savedLists(d).camp, [3])
    }
    func testCommitWritesTheCampListRawSoTheFirstWriteSurvives() {
        let d = suite()
        seed(d, home: [0, 1, 2], camp: [])
        JellyCamp.commit(from: ([0, 1, 2], []), to: ([0, 2], [1]), d, stopAfter: 1)
        XCTAssertEqual(d.array(forKey: JellyCamp.key) as? [Int], [1], "the id is in the Camp key while still in the home key")
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 1, 2], "still home")
    }

    // MARK: ids

    func testBuyingASpeciesWhoseFirstIsAtCampGetsANewId() {
        let d = suite()
        XCTAssertEqual(JellyRoster.allocateInstance(species: 0, roster: [1, 2, 3], d), 0, "(the old home-only view: Bob's own id again, the bug)")
        let id = JellyRoster.allocateInstance(species: 0, roster: JellyCamp.owned(home: [1, 2, 3], camp: [0]), d)
        XCTAssertEqual(id, 100, "Bob at Camp: the new blue gets 100, not 0")
    }

    // MARK: price

    func testPriceWithCamp() {
        XCTAssertEqual(AdoptionPrice.next(home: 3, camp: 0), 800)
        XCTAssertEqual(AdoptionPrice.next(home: 3, camp: 0, rare: true), 1100)
        XCTAssertEqual(AdoptionPrice.next(home: 3, camp: 0, special: true), 2000)
        XCTAssertEqual(AdoptionPrice.next(home: 3, camp: JellyCamp.cap - 1), 800)
        XCTAssertNil(AdoptionPrice.next(home: 3, camp: JellyCamp.cap))
        XCTAssertNil(AdoptionPrice.next(home: 3, camp: JellyCamp.cap, special: true))
        XCTAssertNil(AdoptionPrice.next(home: 3), "the old price function is unchanged")
        XCTAssertEqual(AdoptionPrice.next(home: 0, camp: 0), 0); XCTAssertEqual(AdoptionPrice.next(home: 1, camp: 0), 500); XCTAssertEqual(AdoptionPrice.next(home: 2, camp: 0, rare: true), 1100)
        XCTAssertEqual(AdoptionPrice.next(home: 1, camp: 0, special: true), 2000)
    }

    // MARK: Camp creatures count for candidates and names

    func testACampBobCountsForTheTwinCheck() {
        let withCamp = AdoptionCenter.makeCandidates(mode: .more, species: 0, dayKey: 5, home: [1, 2, 3], camp: [0])
        let without = AdoptionCenter.makeCandidates(mode: .more, species: 0, dayKey: 5, home: [1, 2, 3])
        let owned1 = AdoptionCenter.makeCandidates(mode: .more, species: 0, dayKey: 5, home: [0, 1, 2])
        XCTAssertEqual(withCamp, owned1, "a Camp Bob counts as owned exactly like a home Bob")
        XCTAssertNotEqual(withCamp, without, "and differs from offering the same day's candidates to someone who owns no Bob")
    }
}
