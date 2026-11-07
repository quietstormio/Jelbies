//
//  MusicEarsStoreTests.swift
//  Music Ears: the Ears feature sold once for everyone (Shop > Tricks), locked until bought, grandfathered when it was already on.
//

import XCTest
@testable import BobV1

@MainActor
final class MusicEarsStoreTests: XCTestCase {
    private var suites: [String] = []
    private func suite() -> UserDefaults {
        let n = "MusicEarsStoreTests.\(UUID().uuidString)"
        suites.append(n)
        return UserDefaults(suiteName: n)!
    }
    override func tearDown() {
        for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }
        suites = []
    }

    func testTheShopSellsMusicEarsOnceForEveryone() {
        let item = StoreCatalog.item(TrickCatalog.earsID)!
        XCTAssertEqual(item.name, "Music Ears"); XCTAssertEqual(item.scope, .everyone); XCTAssertEqual(item.price, 150)
        XCTAssertEqual(item.description, "They dance to your music and react to claps, whistles and laughs. Uses the microphone while on.")
        XCTAssertTrue(ShopTab.tricks.items.contains { $0.id == item.id })
        let w = DropsWallet(persists: false); w.add(200, silent: true)
        let b = StoreBook(wallet: w, persists: false, defaults: suite(), key: "MusicEars.book")
        TrickStoreTests.keep.append(b)
        XCTAssertFalse(b.hasEars); XCTAssertFalse(b.owns(item))
        XCTAssertEqual(b.buy(item.id), .bought)
        XCTAssertEqual(w.count, 50)
        XCTAssertTrue(b.hasEars); XCTAssertTrue(b.owns(item))
        XCTAssertEqual(b.buy(item.id), .alreadyOwned); XCTAssertEqual(w.count, 50, "no second charge")
    }

    func testTheSwitchStaysOffWhileLocked() {
        let ears = Ears(defaults: suite(), inert: true)
        ears.owned = { false }
        XCTAssertTrue(ears.isLocked)
        ears.setOn(true)
        XCTAssertEqual(ears.state, .off, "locked: the switch does nothing"); XCTAssertFalse(ears.isOn)
        ears.owned = { true }
        XCTAssertFalse(ears.isLocked)
        ears.setOn(true)
        XCTAssertTrue(ears.isOn); XCTAssertEqual(ears.state, .listening)
    }

    func testLaunchLocksUntilTheShopSaleThenUnlocks() {
        let care = GameCare(jellyCount: 1, persistent: false)
        let ears = Ears(defaults: suite(), inert: true)
        ears.launch(care: care)
        XCTAssertTrue(ears.isLocked, "not bought, not on before: locked")
        ears.setOn(true); XCTAssertFalse(ears.isOn)
        care.store.grant(TrickCatalog.earsID)
        XCTAssertFalse(ears.isLocked, "bought: the switch is there")
        ears.setOn(true); XCTAssertTrue(ears.isOn)
    }

    func testAnEarsSwitchThatWasAlreadyOnIsGrandfatheredOnceOnly() {
        let on = suite(); on.set(true, forKey: Ears.key)
        let care = GameCare(jellyCount: 1, persistent: false)
        let ears = Ears(defaults: on, inert: true)
        ears.launch(care: care)
        XCTAssertTrue(care.store.hasEars, "it was on before Music Ears was sold: owned")
        XCTAssertFalse(ears.isLocked)
        let off = suite()
        let care2 = GameCare(jellyCount: 1, persistent: false)
        let ears2 = Ears(defaults: off, inert: true)
        ears2.launch(care: care2)
        XCTAssertFalse(care2.store.hasEars, "never on: it has to be bought")
        off.set(true, forKey: Ears.key)
        ears2.launch(care: care2)
        XCTAssertFalse(care2.store.hasEars, "the check ran once; a later switch does not grandfather")
    }
}
