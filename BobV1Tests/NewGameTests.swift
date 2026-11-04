//
//  NewGameTests.swift
//  `-NewGame lavender,pearl,teddy`: the roster, the JellyCoins balance and the save flags it writes, applied once per value; and the two real species added
//  with it (Pearl = id 5, white with pearl wings; Teddy = id 4, ears).
//

import XCTest
@testable import BobV1

@MainActor
final class NewGameTests: XCTestCase {
    private func suite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "NewGameTests.\(name)")!
        d.removePersistentDomain(forName: "NewGameTests.\(name)")
        return d
    }

    func testNewGameWritesRosterCoinsAndFlagsOnceOnly() {
        let d = suite("once")
        let saved = JellyRoster.current
        defer { JellyRoster.current = saved }
        d.set(77, forKey: DropsWallet.key)
        var wipes = 0
        XCTAssertTrue(StartFlow.applyNewGame(text: "lavender,pearl,teddy", coins: 10_000, defaults: d, wipe: { wipes += 1; d.removeObject(forKey: DropsWallet.key) }))
        XCTAssertEqual(wipes, 1)
        XCTAssertEqual(JellyRoster.savedIDs(d), [3, 5, 4])
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 10_000)
        XCTAssertTrue(d.bool(forKey: StartFlow.startedKey))
        XCTAssertTrue(StartFlow.hasSave(d))
        XCTAssertTrue(d.bool(forKey: IntroGate.seenKey))
        let store = try? JSONDecoder().decode(StoreBook.Saved.self, from: d.data(forKey: StoreBook.key) ?? Data())
        XCTAssertEqual(store?.starterGiven, true, "no 40-Drop starter on top of the 10,000")
        // the same value again: nothing is wiped or rewritten (play changes the balance and the roster)
        d.set(9_500, forKey: DropsWallet.key)
        XCTAssertFalse(StartFlow.applyNewGame(text: "lavender,pearl,teddy", coins: 10_000, defaults: d, wipe: { wipes += 1 }))
        XCTAssertEqual(wipes, 1)
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 9_500)
        // a different value applies again; no argument / junk does nothing
        XCTAssertTrue(StartFlow.applyNewGame(text: "3,5,4", coins: 500, defaults: d, wipe: { wipes += 1 }))
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 500)
        XCTAssertFalse(StartFlow.applyNewGame(text: nil, coins: 1, defaults: d, wipe: { wipes += 1 }))
        XCTAssertFalse(StartFlow.applyNewGame(text: "nobody", coins: 1, defaults: d, wipe: { wipes += 1 }))
        XCTAssertEqual(wipes, 2)
    }

    func testPearlIsWhiteWingedAndTeddyHasEars() {
        XCTAssertEqual(JellyRoster.pearlID, 5)
        XCTAssertEqual(JellyRoster.baseNames[5], "Pearl")
        XCTAssertEqual(JellyRoster.feature(5), .wings)
        XCTAssertEqual(JellyRoster.palette(5)?.flesh, WhiteWing.palette.flesh)
        XCTAssertEqual(JellyRoster.tint(5), WhiteWing.swatch)
        XCTAssertTrue(WhiteWing.hasLook(5))
        XCTAssertFalse(WhiteWing.hasLook(3), "Lavender keeps her own purple wings")
        XCTAssertEqual(JellyRoster.feature(4), .ears)
        XCTAssertEqual(JellyRoster.knownCount, 7)
        XCTAssertEqual(JellyRoster.sanitised([3, 5, 4]), [3, 5, 4])
        XCTAssertEqual(JellyRoster.characterID(named: "Pearl"), 5)
        XCTAssertEqual(JellyRoster.characterCount, 4, "neither is on offer")
        XCTAssertFalse(JellyRoster.defaultIDs.contains(5))
        XCTAssertFalse(SpeciesInfo.order.contains(5))
        XCTAssertEqual(JellyRoster.names.count, 6)
        _ = JellyRoster.selectBlobs(roster: [3, 5, 4])
        XCTAssertEqual(JelbieA11yText.description(character: 5), "white with pearly little wings")
    }
}
