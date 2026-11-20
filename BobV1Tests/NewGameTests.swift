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

    func testColdLaunchWithASaveStartsAtTheMainMenu() {
        let d = suite("coldmenu")
        d.set(true, forKey: StartFlow.startedKey)
        XCTAssertTrue(StartFlow.hasSave(d))
        d.set(true, forKey: "Jelbies.lastInRoom.v1")          // (the retired "left from the room" flag must not matter)
        let flow = StartFlow()
        if UserDefaults.standard.object(forKey: "MainMenu") == nil { XCTAssertEqual(flow.phase, .menu, "a cold launch shows Continue / New Game") }
    }

    private func at(_ day: Int, _ h: Int, _ m: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = day; c.hour = h; c.minute = m
        return Calendar.current.date(from: c)!
    }

    func testReturnFromTheBackgroundMenuRule() {
        let d = suite("returnrule")
        XCTAssertFalse(StartFlow.menuDueOnReturn(d, now: at(19, 9, 0)), "nothing stored: no menu")
        StartFlow.noteLeft(d, at: at(18, 20, 0))
        XCTAssertFalse(StartFlow.menuDueOnReturn(d, now: at(18, 23, 0)), "same day: no menu")
        XCTAssertTrue(StartFlow.menuDueOnReturn(d, now: at(19, 9, 0)), "next day after 3 h: the menu")
        XCTAssertTrue(StartFlow.returnShowsMenu(busy: false, d, now: at(19, 9, 0)))
        XCTAssertFalse(StartFlow.returnShowsMenu(busy: true, d, now: at(19, 9, 0)), "a meal / bath / trip in progress: no menu")
        StartFlow.noteLeft(d, at: at(18, 23, 55))
        XCTAssertFalse(StartFlow.menuDueOnReturn(d, now: at(19, 0, 5)), "23:55 -> 00:05: under the 3 h floor")
        XCTAssertTrue(StartFlow.menuDueOnReturn(d, now: at(19, 2, 55)), "3 h exactly, next day")
        StartFlow.noteLeft(d, at: at(18, 6, 0))
        XCTAssertFalse(StartFlow.menuDueOnReturn(d, now: at(18, 23, 0)), "17 h but the same day")
    }

    func testClockIsInjectable() {
        let d = suite("clock")
        let saved = StartFlow.clock; defer { StartFlow.clock = saved }
        StartFlow.clock = { self.at(18, 21, 0) }
        StartFlow.noteLeft(d)
        StartFlow.clock = { self.at(19, 8, 0) }
        XCTAssertTrue(StartFlow.menuDueOnReturn(d))
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
        XCTAssertTrue(SpeciesInfo.special.contains(5))
        XCTAssertEqual(JellyRoster.names.count, 7)
        _ = JellyRoster.selectBlobs(roster: [3, 5, 4])
        XCTAssertEqual(JelbieA11yText.description(character: 5), "white with pearly little wings")
    }
}

@MainActor
final class NewGameFirstTests: XCTestCase {
    private func suite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "NewGameFirstTests.\(name)")!
        d.removePersistentDomain(forName: "NewGameFirstTests.\(name)")
        return d
    }

    func testFirstWipesLeavesNoSaveAndAppliesOnce() {
        let d = suite("first")
        let saved = (JellyRoster.current, JellyRoster.names)
        defer { JellyRoster.current = saved.0; JellyRoster.names = saved.1 }
        JellyRoster.save([3, 5], to: d); d.set(77, forKey: DropsWallet.key); d.set(true, forKey: StartFlow.startedKey)
        XCTAssertTrue(StartFlow.hasSave(d))
        var wipes = 0
        let wipe = { wipes += 1; for k in [JellyRoster.rosterKey, DropsWallet.key, StartFlow.startedKey] { d.removeObject(forKey: k) } }
        XCTAssertTrue(StartFlow.applyNewGame(text: " First ", coins: 10_000, defaults: d, wipe: wipe))
        XCTAssertEqual(wipes, 1)
        XCTAssertFalse(StartFlow.hasSave(d))
        XCTAssertFalse(d.bool(forKey: IntroGate.seenKey))
        XCTAssertEqual(d.object(forKey: StartFlow.firstCoinsKey) as? Int, 10_000)
        XCTAssertEqual(d.string(forKey: StartFlow.newGameAppliedKey), "first|10000|intro2")
        XCTAssertEqual(JellyRoster.current, [0])
        d.set(5, forKey: StartFlow.firstCoinsKey)
        XCTAssertFalse(StartFlow.applyNewGame(text: "first", coins: 10_000, defaults: d, wipe: wipe))
        XCTAssertEqual(wipes, 1)
        XCTAssertEqual(d.object(forKey: StartFlow.firstCoinsKey) as? Int, 5)
        XCTAssertTrue(StartFlow.applyNewGame(text: "first", coins: 20, defaults: d, wipe: wipe))
        XCTAssertEqual(d.object(forKey: StartFlow.firstCoinsKey) as? Int, 20)
    }

    func testPendingCoinsApplyOnlyOnFirstAdoption() {
        let d = suite("pending")
        XCTAssertNil(StartFlow.applyPendingFirstCoins(10_000, first: false, defaults: d))
        XCTAssertFalse(StartFlow.hasSave(d))
        XCTAssertNil(StartFlow.applyPendingFirstCoins(nil, first: true, defaults: d))
        XCTAssertFalse(StartFlow.hasSave(d))
        d.set(10_000, forKey: StartFlow.firstCoinsKey)
        XCTAssertEqual(StartFlow.applyPendingFirstCoins(10_000, first: true, defaults: d), 10_000)
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 10_000)
        XCTAssertNil(d.object(forKey: StartFlow.firstCoinsKey))
        let store = try? JSONDecoder().decode(StoreBook.Saved.self, from: d.data(forKey: StoreBook.key) ?? Data())
        XCTAssertEqual(store?.starterGiven, true, "no 40-Drop starter on top of the pending balance")
    }

    func testStarterDoesNotAddOnTopOfPendingBalance() {
        let d = suite("starter")
        StartFlow.applyPendingFirstCoins(10_000, first: true, defaults: d)
        let w = DropsWallet(persists: false); w.add(10_000, silent: true)
        let b = StoreBook(wallet: w, persists: true, defaults: d)
        XCTAssertFalse(b.grantStarterIfNeeded())
        XCTAssertEqual(w.count, 10_000)
    }
}
