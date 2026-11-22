//
//  ShowWardrobeTests.swift
//  show-wardrobe-r1 (owner rule): what a Jelmiko is dressed in FOR the Jelly Show is a show outfit only; after the show (or any other way out of the lobby) he wears exactly what
//  he wore before, which may be nothing. Case (a): nothing at home, hat and shoes for the show. Case (b): item X at home, item Y for the show.
//

import XCTest
@testable import BobV1

@MainActor
final class ShowWardrobeTests: XCTestCase {
    private typealias Room = RaceThreeTests.Room
    nonisolated(unsafe) static var suites: [String] = []
    override func setUp() { DayClock.shared.forcedHour = 12 }
    override func tearDown() { for s in Self.suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }; Self.suites = [] }

    private func defaults() -> UserDefaults { let n = "ShowWardrobe.\(UUID().uuidString)"; Self.suites.append(n); return UserDefaults(suiteName: n)! }
    private func book(_ d: UserDefaults, persists: Bool = true) -> StoreBook {
        let b = StoreBook(wallet: DropsWallet(persists: false), persists: persists, defaults: d, key: "ShowWardrobeTests.book")
        return b
    }
    private func stocked(_ d: UserDefaults) -> StoreBook {
        let b = book(d)
        b.saved.wearables = [WearLook.partyHat, .glitterShoes, .flowerCrown, .pearls].map(\.rawValue)
        b.save()
        return b
    }
    private func owned(_ b: StoreBook) -> [String] { b.saved.wearables.sorted() }

    // MARK: the store

    func testCaseA_NothingAtHome_HatAndShoesForTheShow_NothingAfter() {
        let b = stocked(defaults())
        let items = owned(b)
        b.rememberEveryday(0)
        XCTAssertTrue(b.wear(.partyHat, on: 0)); XCTAssertTrue(b.wear(.glitterShoes, on: 0))
        XCTAssertEqual(b.outfit(0).count, 2, "dressed for the show")
        b.restoreEveryday()
        XCTAssertTrue(b.outfit(0).isEmpty, "back to nothing")
        XCTAssertEqual(owned(b), items, "nothing bought, lost or duplicated")
        XCTAssertFalse(b.hasEveryday)
    }
    func testCaseB_XAtHome_YForTheShow_XAfter() {
        let b = stocked(defaults())
        XCTAssertTrue(b.wear(.flowerCrown, on: 0)); XCTAssertTrue(b.wear(.pearls, on: 0))
        let before = b.outfit(0), items = owned(b)
        b.rememberEveryday(0)
        XCTAssertTrue(b.wear(.partyHat, on: 0)); b.takeOff(.neck, from: 0)
        XCTAssertEqual(b.outfit(0)[.head], .partyHat)
        b.restoreEveryday()
        XCTAssertEqual(b.outfit(0), before)
        XCTAssertEqual(owned(b), items)
    }
    func testRestoreHappensOnce_AndNeverOntoALaterChangeAtHome() {
        let b = stocked(defaults())
        b.rememberEveryday(0)
        XCTAssertTrue(b.wear(.partyHat, on: 0))
        b.restoreEveryday()
        XCTAssertTrue(b.outfit(0).isEmpty)
        XCTAssertTrue(b.wear(.flowerCrown, on: 0))          // the player's own change at home
        b.restoreEveryday(); b.restoreEveryday()
        XCTAssertEqual(b.outfit(0)[.head], .flowerCrown, "a second restore never undoes it")
    }
    func testRememberingTwiceKeepsTheFirst() {
        let b = stocked(defaults())
        XCTAssertTrue(b.wear(.flowerCrown, on: 0))
        b.rememberEveryday(0)
        XCTAssertTrue(b.wear(.partyHat, on: 0))
        b.rememberEveryday(0)          // (Dress up open, the show starts: the capture start remembers again)
        b.restoreEveryday()
        XCTAssertEqual(b.outfit(0)[.head], .flowerCrown)
    }
    func testAHousematesPieceTakenForTheShowGoesBack() {
        let b = stocked(defaults())
        XCTAssertTrue(b.wear(.partyHat, on: 1))
        b.rememberEveryday(0)
        XCTAssertTrue(b.wear(.partyHat, on: 0), "the only copy moves to the contestant")
        XCTAssertNil(b.outfit(1)[.head])
        b.restoreEveryday()
        XCTAssertNil(b.outfit(0)[.head]); XCTAssertEqual(b.outfit(1)[.head], .partyHat)
    }
    func testClosedInTheLobby_NextLaunchPutsItBackOnce() {
        let d = defaults()
        let b = stocked(d)
        XCTAssertTrue(b.wear(.flowerCrown, on: 0))
        b.rememberEveryday(0)
        XCTAssertTrue(b.wear(.partyHat, on: 0)); XCTAssertTrue(b.wear(.glitterShoes, on: 0))
        // the app is killed here: a new launch reads the same save
        let again = book(d)
        XCTAssertEqual(again.outfit(0), [.head: .flowerCrown], "the everyday outfit is back at launch")
        XCTAssertFalse(again.hasEveryday, "and cleared")
        XCTAssertTrue(again.wear(.partyHat, on: 0))          // a later change at home
        let third = book(d)
        XCTAssertEqual(third.outfit(0)[.head], .partyHat, "never restored a second time")
    }
    func testAnOldSaveWithoutTheFieldDecodes() throws {
        let d = defaults()
        let b = stocked(d)
        XCTAssertTrue(b.wear(.partyHat, on: 0))
        XCTAssertNil(book(d).saved.showHome)
        XCTAssertEqual(book(d).outfit(0)[.head], .partyHat)
    }

    // MARK: the room

    private func step(_ r: Room, _ n: Int = 1) {
        for _ in 0..<n { r.step(); r.care.tickShow(r.actors, dt: 1 / 60); r.care.tickWear(r.actors, dt: 1 / 60) }
    }
    private func run(_ r: Room, seconds: Float, until: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) { step(r); if let u = until, u() { break } }
    }
    private func room() -> Room {
        let r = Room(count: 3)
        RaceThreeTests.keep.append(r)
        r.care.show.songClock = { _ in nil }; r.care.show.audioReady = { _ in true }; r.care.show.cue = { _ in }
        r.care.store.saved.wearables = [WearLook.partyHat, .glitterShoes, .flowerCrown, .pearls].map(\.rawValue)
        return r
    }
    private func toStage(_ r: Room) {
        r.care.startShow(jelly: 0, rank: .puddle, seed: 5)
        run(r, seconds: 8) { r.care.show.onStage && r.care.show.phase == .stage && r.care.show.wipe == 0 }
        XCTAssertTrue(r.care.show.onStage)
    }
    /// The Studio's way: remember, dress, enter.
    private func dressInLobby(_ r: Room, home: [WearLook], show: [WearLook]) {
        let c = r.care
        for l in home { XCTAssertTrue(c.store.wear(l, on: 0)) }
        c.showWardrobeReady(0)
        for s in WearSlot.allCases { c.store.takeOff(s, from: 0) }
        for l in show { XCTAssertTrue(c.store.wear(l, on: 0)) }
    }

    func testStageShowsTheShowOutfit_AndAShowThatEndsGivesTheHomeOneBack() {
        for (home, show) in [([WearLook](), [WearLook.partyHat, .glitterShoes]), ([.flowerCrown], [.partyHat])] {
            let r = room(), c = r.care
            let items = c.store.saved.wearables.sorted()
            dressInLobby(r, home: home, show: show)
            let homeOutfit = Dictionary(uniqueKeysWithValues: home.map { ($0.slot, $0) })
            toStage(r)
            XCTAssertEqual(c.outfit(0), Dictionary(uniqueKeysWithValues: show.map { ($0.slot, $0) }), "the stage wears the show outfit")
            XCTAssertEqual(c.show.sim?.outfit.count, show.count, "and the show scores it")
            c.show.goHome()
            run(r, seconds: 8) { !c.show.active }
            XCTAssertFalse(c.show.active)
            step(r, 3)
            XCTAssertEqual(c.outfit(0), homeOutfit, "home again: the everyday outfit")
            XCTAssertEqual(c.store.outfit(0), homeOutfit)
            XCTAssertFalse(c.store.hasEveryday)
            XCTAssertEqual(c.store.saved.wearables.sorted(), items)
        }
    }
    func testForfeitAndAbortGiveItBackToo() {
        for how in 0..<2 {
            let r = room(), c = r.care
            dressInLobby(r, home: [.flowerCrown], show: [.partyHat])
            toStage(r)
            if how == 0 { c.askForfeit(); c.confirmForfeit(); run(r, seconds: 8) { !c.show.active } } else { c.show.abort() }
            step(r, 3)
            XCTAssertEqual(c.outfit(0), [.head: .flowerCrown], "way \(how)")
            XCTAssertFalse(c.store.hasEveryday)
        }
    }
    func testBackingOutOfTheLobbyGivesItBack() {
        let r = room(), c = r.care
        dressInLobby(r, home: [], show: [.partyHat])
        c.showWardrobeLeaveLobby()
        XCTAssertTrue(c.store.outfit(0).isEmpty)
        XCTAssertFalse(c.store.hasEveryday)
    }
    func testPickingAnotherJelmikoInTheLobbyGivesTheFirstItsClothesBack() {
        let r = room(), c = r.care
        XCTAssertTrue(c.store.wear(.pearls, on: 1))
        dressInLobby(r, home: [.flowerCrown], show: [.partyHat])
        c.showWardrobeLeaveLobby(); c.showWardrobeReady(1)          // (the Studio's who change)
        XCTAssertEqual(c.store.outfit(0), [.head: .flowerCrown])
        XCTAssertTrue(c.store.wear(.glitterShoes, on: 1))
        c.showWardrobeLeaveLobby()
        XCTAssertEqual(c.store.outfit(1), [.neck: .pearls])
        XCTAssertEqual(c.store.outfit(0), [.head: .flowerCrown])
    }
    func testClosingTheStudioToEnterTheShowKeepsTheShowOutfitUntilHome() {
        let r = room(), c = r.care
        dressInLobby(r, home: [.flowerCrown], show: [.partyHat])
        c.startShow(jelly: 0, rank: .puddle, seed: 5)
        c.showWardrobeLeaveLobby()          // (the Town closes right after Enter)
        XCTAssertEqual(c.store.outfit(0), [.head: .partyHat], "the way in does not give it back")
        run(r, seconds: 8) { c.show.onStage && c.show.phase == .stage && c.show.wipe == 0 }
        c.show.goHome(); run(r, seconds: 8) { !c.show.active }
        step(r, 3)
        XCTAssertEqual(c.store.outfit(0), [.head: .flowerCrown])
    }
    func testNoOutfitAdmiringForTheOldOneComingBack() {
        let r = room(), c = r.care
        dressInLobby(r, home: [.flowerCrown], show: [.partyHat])
        step(r, 2)
        c.showWardrobeLeaveLobby(); step(r, 1)
        XCTAssertEqual(c.outfitSeen[0], GameCare.outfitSig(c.outfit(0)))
    }
}
