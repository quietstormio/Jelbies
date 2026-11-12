//
//  TrickStoreTests.swift
//  Tricks bought in the Shop (Store/TrickCatalog.swift): owned per Jelbie or for everyone, the defaults always known, the one-time migration from
//  the lesson books, and the voice refusing a trick the Jelbie does not know.
//

import XCTest
@testable import BobV1

@MainActor
final class TrickStoreTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var suites: [String] = []

    private func suite() -> UserDefaults {
        let n = "TrickStoreTests.\(UUID().uuidString)"
        suites.append(n)
        return UserDefaults(suiteName: n)!
    }
    override func tearDown() {
        for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }
        suites = []
    }
    private func book(_ drops: Int, persists: Bool = false, defaults: UserDefaults? = nil) -> (StoreBook, DropsWallet) {
        let w = DropsWallet(persists: false)
        w.add(drops, silent: true)
        let b = StoreBook(wallet: w, persists: persists, defaults: defaults ?? suite(), key: "TrickStoreTests.book")
        Self.keep.append(b)
        return (b, w)
    }

    func testPerJelbieTrickIsOwnedByThatJelbieOnly() {
        let (b, w) = book(500)
        XCTAssertFalse(b.knows(.flip, character: 1))
        XCTAssertEqual(b.buyTrick(.flip, for: nil), .unknown, "a per-Jelbie trick needs a Jelbie")
        XCTAssertEqual(b.buyTrick(.flip, for: 1), .bought)
        XCTAssertEqual(w.count, 500 - TrickCatalog.def(.flip)!.price)
        XCTAssertTrue(b.knows(.flip, character: 1))
        XCTAssertFalse(b.knows(.flip, character: 0), "only one Jelbie")
        XCTAssertFalse(b.knows(.flip, character: 2))
        XCTAssertEqual(b.trickScope(.flip, character: 1), .perJelbie)
        let after = w.count
        XCTAssertEqual(b.buyTrick(.flip, for: 1), .alreadyOwned)
        XCTAssertEqual(w.count, after, "no second charge")
        let item = StoreCatalog.item("trick-flip")!
        XCTAssertFalse(b.owns(item), "the card shows owned only when the whole roster has it")
        b.rosterCharacters = { [1] }
        XCTAssertTrue(b.owns(item))
    }

    /// Stage 1 of the trick plan: Show off (3 stars, one Jelbie), Strut and Sing (1 star, everyone).
    func testStageOneTrickRows() {
        let want: [(VoiceTrick, Int, TrickScope, Int)] = [(.showOff, 3, .perJelbie, 110), (.strut, 1, .everyone, 40), (.sing, 1, .everyone, 40)]
        for (t, stars, scope, price) in want {
            let d = TrickCatalog.def(t)
            XCTAssertEqual(d?.stars, stars, "\(t) stars"); XCTAssertEqual(d?.scope, scope, "\(t) scope"); XCTAssertEqual(d?.price, price, "\(t) price")
            XCTAssertEqual(d?.scope.tag, scope == .everyone ? "For all your Jelbies" : "Only one Jelbie")
            XCTAssertFalse(TrickCatalog.isDefault(t)); XCTAssertTrue(ShowTrickInfo.stageTricks.contains(t))
            XCTAssertNotNil(VoiceCoordinator.idleKind(for: t), "\(t) has a move"); XCTAssertEqual(VoiceCoordinator.trick(for: VoiceCoordinator.idleKind(for: t)), t)
            XCTAssertNotNil(StoreCatalog.item("trick-\(t.rawValue)"), "\(t) is in the Shop")
            XCTAssertGreaterThan(ShowTrickInfo.seconds(t), 3, "the stage waits for the longer moves")
        }
        XCTAssertEqual(VoiceCoordinator.idleKind(for: .showOff), .signatureFlourish); XCTAssertEqual(VoiceCoordinator.idleKind(for: .strut), .proudStrut); XCTAssertEqual(VoiceCoordinator.idleKind(for: .sing), .sing)
        XCTAssertEqual(ShowTrickInfo.seconds(.sit), 2.6, "the others keep the old time")
        let (b, w) = book(500)
        XCTAssertEqual(b.buyTrick(.strut, for: nil), .bought); XCTAssertEqual(w.count, 460)
        XCTAssertTrue(b.knows(.strut, character: 2), "everyone")
        XCTAssertEqual(b.buyTrick(.showOff, for: 1), .bought); XCTAssertFalse(b.knows(.showOff, character: 0))
    }

    /// Stage 2 of the trick plan: the four new moves (rows, stars, scope, price, moves both ways, the Show's time and its own fail variant).
    func testStageTwoTrickRows() {
        let want: [(VoiceTrick, Int, TrickScope, Int, IdleKind)] = [(.hula, 1, .everyone, 40, .hula), (.superSpring, 2, .everyone, 70, .superSpring)]
        for (t, stars, scope, price, kind) in want {
            let d = TrickCatalog.def(t)
            XCTAssertEqual(d?.stars, stars, "\(t) stars"); XCTAssertEqual(d?.scope, scope, "\(t) scope"); XCTAssertEqual(d?.price, price, "\(t) price")
            XCTAssertFalse(TrickCatalog.isDefault(t)); XCTAssertFalse(t.isStarter); XCTAssertTrue(ShowTrickInfo.stageTricks.contains(t))
            XCTAssertEqual(VoiceCoordinator.idleKind(for: t), kind); XCTAssertEqual(VoiceCoordinator.trick(for: kind), t)
            XCTAssertNotNil(StoreCatalog.item("trick-\(t.rawValue)"), "\(t) is in the Shop")
            XCTAssertFalse(ShowTrickInfo.symbol(t).isEmpty); XCTAssertFalse(ShowTrickInfo.tags(t).isEmpty)
            XCTAssertTrue(ShowTrickInfo.ownsFlop.contains(t), "\(t) has its own fail variant")
            XCTAssertGreaterThanOrEqual(ShowTrickInfo.seconds(t), BlobBrain.trickMoveSeconds(kind) ?? 0, "the stage waits for the whole \(t)")
        }
        XCTAssertEqual(VoiceTrick.hula.rawValue, "hula", "the raw value is the save key")
    }

    func testTrickNeedsEnoughCoins() {
        let (b, w) = book(10)
        XCTAssertEqual(b.buyTrick(.flip, for: 0), .notEnough)
        XCTAssertEqual(w.count, 10)
        XCTAssertFalse(b.knows(.flip, character: 0))
    }

    func testEveryoneTrickCoversANewlyAdoptedJelbie() {
        let (b, w) = book(500)
        XCTAssertEqual(TrickCatalog.def(.look)?.scope, .everyone)
        XCTAssertEqual(b.buyTrick(.look, for: nil), .bought)
        XCTAssertEqual(w.count, 500 - TrickCatalog.def(.look)!.price)
        for c in 0..<6 { XCTAssertTrue(b.knows(.look, character: c), "character \(c), adopted later too") }
        XCTAssertEqual(b.trickScope(.look, character: 5), .everyone)
        XCTAssertEqual(b.buyTrick(.look, for: 3), .alreadyOwned)
    }

    func testDefaultsAreAlwaysKnownAndNeverSold() {
        let (b, _) = book(0)
        for t in [VoiceTrick.sit, .spin, .hop, .jacks, .run, .come] {
            for c in 0..<6 { XCTAssertTrue(b.knows(t, character: c), "\(t) is a default") }
            XCTAssertTrue(TrickCatalog.isDefault(t))
            XCTAssertNil(TrickCatalog.def(t), "\(t) is never sold")
            XCTAssertNil(b.trickScope(t, character: 0))
        }
        XCTAssertEqual(Set(ShowTrickInfo.defaults), [.sit, .spin, .hop, .jacks])
        for d in TrickCatalog.forSale { XCTAssertFalse(TrickCatalog.isDefault(d.trick)); XCTAssertEqual(d.price, TrickCatalog.price(stars: d.stars)) }
        XCTAssertEqual(TrickCatalog.price(stars: 3), 110)
    }

    func testMigrationMakesLearnedTricksPerJelbieAndPagesForEveryone() throws {
        let d = suite()
        var s = StoreBook.Saved()
        s.pages = ["spin", "hop"]
        d.set(try JSONEncoder().encode(s), forKey: "TrickStoreTests.book")
        let (b, w) = book(77, persists: true, defaults: d)
        b.migrateTricks(learned: [0: [.sit, .flip, .come], 1: [.look]], roster: [0, 1])
        XCTAssertTrue(b.knows(.flip, character: 0)); XCTAssertEqual(b.trickScope(.flip, character: 0), .perJelbie)
        XCTAssertFalse(b.knows(.flip, character: 1), "flip was Bob's lesson only")
        XCTAssertTrue(b.knows(.look, character: 1)); XCTAssertFalse(b.knows(.look, character: 0))
        XCTAssertEqual(b.trickScope(.spin, character: 0), .perJelbie, "an owned page is owned by every current Jelbie")
        XCTAssertEqual(b.trickScope(.hop, character: 1), .perJelbie)
        XCTAssertEqual(w.count, 77, "no coins lost or gained")
        XCTAssertEqual(b.saved.tricksMigrated, true)
        // once: a second run (different books) changes nothing, also after a relaunch
        b.migrateTricks(learned: [1: [.flip]], roster: [0, 1])
        XCTAssertFalse(b.knows(.flip, character: 1))
        let (again, _) = book(0, persists: true, defaults: d)
        again.migrateTricks(learned: [1: [.flip]], roster: [0, 1])
        XCTAssertTrue(again.knows(.flip, character: 0)); XCTAssertFalse(again.knows(.flip, character: 1))
    }

    func testGameCareWiresEachJelbiesKnowledge() {
        let care = GameCare(jellyCount: 2, persistent: false)
        let c1 = care.jelly(1)!.character
        XCTAssertFalse(care.jelly(0)!.training.unlocked(.flip))
        XCTAssertFalse(care.jelly(1)!.training.unlocked(.flip))
        care.store.grantTrick(.flip, to: c1)
        XCTAssertFalse(care.jelly(0)!.training.unlocked(.flip))
        XCTAssertTrue(care.jelly(1)!.training.unlocked(.flip), "bought for him")
        XCTAssertTrue(care.knows(.flip, jelly: 1)); XCTAssertFalse(care.knows(.flip, jelly: 0))
        care.store.grantTrickToEveryone(.look)
        XCTAssertTrue(care.jelly(0)!.training.unlocked(.look))
        XCTAssertTrue(care.jelly(0)!.training.unlocked(.spin), "a default")
    }

    func testVoiceRefusesATrickTheJelbieDoesNotKnow() {
        let v = VoiceTraining(defaults: suite(), persists: false, random: { 0 })
        v.unlocked = { $0 != .flip }
        let no = v.decideFull(transcript: "flip", runningMove: nil, mood: .happy, session: 1)
        XCTAssertEqual(no.reaction, .dontKnow(.flip), "the small don't-know-that shrug")
        XCTAssertFalse(no.noMatch)
        XCTAssertEqual(v.decideFull(transcript: "sit", runningMove: nil, mood: .happy, session: 2).reaction, .perform(.sit), "a default needs no lesson")
        XCTAssertEqual(v.decideFull(transcript: "spin", runningMove: nil, mood: .happy, session: 3).reaction, .perform(.spin))
        XCTAssertEqual(v.decide(model: .trick(.flip), target: .selected, mood: .happy).reaction, .dontKnow(.flip), "the model path obeys the same rule")
        v.unlocked = { _ in true }
        XCTAssertEqual(v.decideFull(transcript: "flip", runningMove: nil, mood: .happy, session: 4).reaction, .perform(.flip), "bought: obeyed at once")
        XCTAssertNotEqual(v.decideFull(transcript: "sit on the couch", runningMove: nil, mood: .happy, session: 5).reaction, .perform(.sit), "a place, not a trick")
    }
}
