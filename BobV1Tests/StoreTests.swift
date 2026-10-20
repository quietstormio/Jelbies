//
//  StoreTests.swift
//  The store as data and as a ledger: Drops are earned-only (races), the starter balance is once, a purchase spends from the wallet, the
//  inventory persists, nothing in care earns Drops.
//

import XCTest
@testable import BobV1

@MainActor
final class StoreTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func book(_ drops: Int = 0, persists: Bool = false, defaults: UserDefaults = .standard, key: String = "StoreTests.book") -> (StoreBook, DropsWallet) {
        let w = DropsWallet(persists: false)
        w.add(drops, silent: true)
        let b = StoreBook(wallet: w, persists: persists, defaults: defaults, key: key)
        Self.keep.append(b)
        return (b, w)
    }
    private func suite(_ n: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "StoreTests.\(n)")!
        d.removePersistentDomain(forName: "StoreTests.\(n)")
        return d
    }

    func testStarterBalanceIsGivenOnceAndOnlyOnce() {
        let (b, w) = book()
        XCTAssertEqual(w.count, 0)
        XCTAssertTrue(b.grantStarterIfNeeded())
        XCTAssertEqual(w.count, StoreTuning.starterDrops)
        XCTAssertEqual(StoreTuning.starterDrops, 40)
        XCTAssertFalse(b.grantStarterIfNeeded(), "never twice")
        XCTAssertTrue(w.spend(w.count))
        XCTAssertFalse(b.grantStarterIfNeeded(), "not even at zero")
        XCTAssertEqual(w.count, 0)
    }

    func testStarterSurvivesARelaunch() {
        let d = suite("starter")
        let (b, w) = book(0, persists: true, defaults: d)
        b.grantStarterIfNeeded()
        let (b2, w2) = book(w.count, persists: true, defaults: d)
        XCTAssertFalse(b2.grantStarterIfNeeded(), "the flag is saved")
        XCTAssertEqual(w2.count, 40)
    }

    func testBuySpendsDropsAndFillsTheBag() {
        let (b, w) = book(40)
        XCTAssertEqual(b.buy("fries"), .bought)
        XCTAssertEqual(w.count, 40 - StoreCatalog.item("fries")!.price)
        XCTAssertEqual(b.count("fries"), 1)
        XCTAssertEqual(b.buy("fries"), .bought)
        XCTAssertEqual(b.count("fries"), 2, "snacks stack")
        XCTAssertEqual(b.owned(StoreCatalog.item("fries")!), 2)
        XCTAssertEqual(b.count(food: "fries"), 2)
    }

    func testInsufficientFundsChangesNothing() {
        let (b, w) = book(5)
        XCTAssertEqual(b.buy("sushi"), .notEnough)
        XCTAssertEqual(w.count, 5)
        XCTAssertEqual(b.count("sushi"), 0)
        XCTAssertEqual(b.buy("nope"), .unknown)
        XCTAssertFalse(w.spend(6))
        XCTAssertFalse(w.spend(-1))
        XCTAssertEqual(w.count, 5)
    }

    func testPagesAndShoesAreBoughtOnce() {
        let (b, w) = book(500)
        XCTAssertFalse(b.hasPage(.spin))
        XCTAssertTrue(VoiceTrick.sit.isStarter)
        XCTAssertTrue(b.hasPage(.sit), "starter tricks need no page")
        XCTAssertEqual(b.buy("page-spin"), .bought)
        XCTAssertTrue(b.hasPage(.spin))
        let after = w.count
        XCTAssertEqual(b.buy("page-spin"), .alreadyOwned)
        XCTAssertEqual(w.count, after, "no second charge")
        XCTAssertEqual(b.buy("shoe-mint"), .bought)
        XCTAssertEqual(b.buy("shoe-mint"), .alreadyOwned)
        XCTAssertTrue(b.ownsLook(.sneakerMint))
    }

    func testWearingNeedsOwningAndIsPerJelly() {
        let (b, _) = book(500)
        XCTAssertFalse(b.wear(.rainBoots, on: 0), "not owned")
        b.buy("shoe-rain"); b.buy("shoe-mint")
        XCTAssertTrue(b.wear(.rainBoots, on: 0))
        XCTAssertTrue(b.wear(.sneakerMint, on: 1))
        XCTAssertEqual(b.worn(0, .feet), .rainBoots)
        XCTAssertEqual(b.worn(1, .feet), .sneakerMint)
        XCTAssertNil(b.worn(2, .feet))
        b.takeOff(.feet, from: 0)
        XCTAssertNil(b.worn(0, .feet))
        XCTAssertEqual(b.worn(1, .feet), .sneakerMint)
    }

    func testInventoryAndWearPersist() {
        let d = suite("persist")
        let (b, _) = book(500, persists: true, defaults: d)
        b.buy("nuggets"); b.buy("nuggets"); b.buy("page-hop"); b.buy("shoe-glitter"); b.wear(.glitterShoes, on: 2)
        let (c, _) = book(0, persists: true, defaults: d)
        XCTAssertEqual(c.count("nuggets"), 2)
        XCTAssertTrue(c.hasPage(.hop))
        XCTAssertEqual(c.worn(2, .feet), .glitterShoes)
        XCTAssertTrue(c.use("nuggets"))
        XCTAssertTrue(c.use("nuggets"))
        XCTAssertFalse(c.use("nuggets"), "none left")
    }

    func testCatalogIsConsistent() {
        let ids = StoreCatalog.items.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "unique ids")
        for i in StoreCatalog.items {
            if !i.awarded { XCTAssertGreaterThan(i.price, 0, i.id) }
            if let f = i.food {
                let c = Consumables.with(id: f)
                XCTAssertNotNil(c, "\(i.id) feeds a real food")
                XCTAssertTrue(c?.stored ?? false)
                XCTAssertEqual(c?.perk, i.perk, "\(i.id): the card's perk is what eating gives")
                XCTAssertNotNil(c?.piece == nil ? nil : 1, "\(i.id) has a 3D piece")
            }
            if i.kind == .trickPage { XCTAssertNotNil(i.trick); XCTAssertFalse(i.trick!.isStarter) }
            if i.kind == .shoes { XCTAssertNotNil(i.wear) }
            if i.kind == .supply { XCTAssertNotNil(i.perk) }
        }
        XCTAssertEqual(Consumables.storeFoods.count, 10)
        XCTAssertTrue(StoreCatalog.tabs.contains(.decor), "the Decor tab shows now that part B has items")
        XCTAssertEqual(StoreCatalog.items(.decor).count, 28)
        XCTAssertEqual(StoreTuning.roomCapacity, 10)
        XCTAssertFalse(Consumables.foods.contains { $0.stored }, "store foods stay out of the free Feed picker")
        XCTAssertTrue(Consumables.foods.map(\.id).contains("berries"))
        // a treat costs about two races (12 / 7 / 4)
        let treats = StoreCatalog.items(.treat).map(\.price)
        XCTAssertTrue(treats.allSatisfy { (8...16).contains($0) })
    }

    /// Drops come from competitions only: nothing in care (eating, cleaning, petting, tricks) pays.
    func testCareNeverPaysDrops() {
        let care = GameCare(jellyCount: 1, persistent: false)
        let before = care.bath.wallet.count
        care.store.grant("donut", 3)
        care.ate(jelly: 0, Consumables.donut, pieces: 3)
        care.needs.gain(.attention, 0.5)
        care.needs.restore(.hunger)
        care.bath.grime.addDirt(0.5)
        _ = care.voice.training.decide(transcript: "sit", runningMove: .sit, mood: .happy, session: 1)
        XCTAssertEqual(care.bath.wallet.count, before)
        care.jelly(0)?.perks.clear(.zoomies)
    }

    func testRaceIsAnIncomeAndTheStoreIsASink() {
        let (b, w) = book(0)
        XCTAssertEqual(RaceTuning.drops(place: 1), 12)
        w.add(RaceTuning.drops(place: 1) + RaceTuning.drops(place: 2), silent: true)
        XCTAssertEqual(b.buy("cookie"), .bought, "about two races buy a treat")
    }

    func testBagBadgeCountsNewGoods() {
        let (b, _) = book(100)
        XCTAssertEqual(b.newCount, 0)
        b.buy("fries"); b.buy("shoe-sun")
        XCTAssertEqual(b.newCount, 2)
        b.markSeen()
        XCTAssertEqual(b.newCount, 0)
    }

    func testBoughtTrickPageUnlocksTheVoiceTrick() {
        let care = GameCare(jellyCount: 1, persistent: false)
        XCTAssertFalse(care.voice.training.unlocked(.spin))
        XCTAssertTrue(care.voice.training.unlocked(.sit))
        care.store.grant("page-spin")
        XCTAssertTrue(care.voice.training.unlocked(.spin), "the page unlocks it in the trick book")
        XCTAssertFalse(care.voice.training.unlocked(.hop))
        XCTAssertFalse(care.voice.training.learnedTricks.contains(.hop))
    }

    func testASoapGivesItsPerkOnlyWhenTheCleanUpFinishes() {
        let care = GameCare(jellyCount: 1, persistent: false)
        let perks = care.jelly(0)!.perks
        perks.clear(.shine)
        care.store.grant("lavender")
        care.armedSupplies[0] = ["lavender"]
        XCTAssertFalse(perks.isActive(.shine))
        care.soapFinished()
        XCTAssertTrue(perks.isActive(.shine))
        XCTAssertEqual(care.store.count("lavender"), 0, "used up")
        XCTAssertTrue(care.armedSupplies[0] == nil)
        perks.clear(.shine)
    }
}
