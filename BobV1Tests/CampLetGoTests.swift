//
//  CampLetGoTests.swift
//  "Say goodbye": the rule, the purge (every per-instance thing goes, nothing of anyone else), the clothes returning to the bag, the thank-you paid exactly once, a kill
//  at every point of the write order, and a later purchase of the same species starting fresh.
//

import XCTest
@testable import BobV1

@MainActor
final class CampLetGoTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var suites: [String] = []
    private var savedCurrent: [Int] = []
    private var savedMap: [Int: Int] = [:]
    private var savedNames: [Int: String] = [:]
    private var savedBase: [String] = []

    override func setUp() {
        savedCurrent = JellyRoster.current; savedMap = JellyRoster.speciesMap; savedNames = JellyRoster.extraNames; savedBase = JellyRoster.names
        JellyRoster.speciesMap = [:]; JellyRoster.extraNames = [:]; JellyCamp.onPurge = []
    }
    override func tearDown() {
        JellyRoster.current = savedCurrent; JellyRoster.speciesMap = savedMap; JellyRoster.extraNames = savedNames; JellyRoster.names = savedBase
        JellyVariants.reload(); JellyVariants.clearPreviews(); JellyTraitsBook.reload(); JellyCamp.onPurge = []
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
    }
    private func suite() -> UserDefaults {
        let s = "CampLetGoTests.\(UUID().uuidString)"; suites.append(s)
        return UserDefaults(suiteName: s)!
    }
    private func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }
    private func obj(_ d: UserDefaults, _ k: String) -> Any? { d.data(forKey: k).flatMap { try? JSONSerialization.jsonObject(with: $0) } }
    private func str(_ d: UserDefaults, _ k: String) -> String { d.data(forKey: k).flatMap { String(data: $0, encoding: .utf8) } ?? "" }

    /// A fully played creature `id` (and the same for `other`), written into every store that holds an entry per instance. Returns the clothes it wore.
    @discardableResult
    private func play(_ d: UserDefaults, _ id: Int, other: Int) -> (WearSlot, WearLook) {
        let slot = WearSlot.allCases[0]
        let look = WearLook.allCases.first { $0.slot == slot }!
        let other2 = WearLook.allCases.first { $0.slot == slot && $0 != look }!
        for c in [id, other] {
            for k in JellyCamp.instanceKeys(c) { d.set(Data("x\(c)".utf8), forKey: k) }
        }
        let t = JellyTraits.self; _ = t
        d.set(json(["\(id)": ["a": 1], "\(other)": ["a": 2]]), forKey: "JellyTraits.v1")
        d.set(json(["\(id)": ["a": 1], "\(other)": ["a": 2]]), forKey: "JellyVariants.v1")
        d.set(json(["\(id)": ["bobby"], "\(other)": ["pip"]]), forKey: JellyNames.defaultsKey)
        d.set(json(["\(id)": ["cups": 1], "\(other)": ["cups": 2]]), forKey: "Circuit.trophies.v1")
        var store = StoreBook.Saved()
        store.wearables = [look.rawValue, other2.rawValue]; store.counts = ["berries": 3]
        store.worn = ["\(id)": [slot.rawValue: look.rawValue], "\(other)": [slot.rawValue: other2.rawValue]]
        store.ownedTricks = ["\(id)": ["spin"], "\(other)": ["roll"]]; store.everyone = ["ears"]
        d.set(try! JSONEncoder().encode(store), forKey: StoreBook.key)
        d.set(json(["records": [:], "trophies": ["\(id)": ["shows": 4], "\(other)": ["shows": 1]]]), forKey: ShowProgress.key)
        d.set(json(["stats": ["\(id)": ["sessions": 3], "\(other)": ["sessions": 1]], "records": [:]]), forKey: "Volley.book.v1")
        d.set(id, forKey: "volley.partner")
        d.set(json(["points": ["race.\(id)": 5, "show.\(other)": 7, "race.\(id)1": 9], "chosen": ["race.\(id)": "x"]]), forKey: UpgradeTuning.defaultsKey)
        d.set(json([["name": "V", "friendship": ["\(id)": 40.0, "\(other)": 20.0]]]), forKey: ParkBook.key)
        d.set(json(["day": "x", "love": ["\(id)": 0.5, "\(other)": 0.25]]), forKey: ParkBook.ledgerKey)
        if id < 7 { d.set(["A", "B", "C", "D", "E", "F", "G"].enumerated().map { $0.offset == id ? "Gone" : $0.element }, forKey: JellyRoster.namesKey) }
        else { d.set(["\(id)": "Gone"], forKey: JellyRoster.extraNamesKey); d.set(["\(id)": 1], forKey: JellyRoster.speciesKey); JellyRoster.speciesMap[id] = 1 }
        d.set(5000, forKey: DropsWallet.key)
        return (slot, look)
    }
    private func seed(_ d: UserDefaults, home: [Int], camp: [Int]) { d.set(home, forKey: JellyRoster.rosterKey); d.set(camp, forKey: JellyCamp.key) }

    // MARK: rule

    func testOnlyACampCreatureCanBeLetGo() {
        XCTAssertTrue(JellyCamp.canLetGo(3, home: [0], camp: [3]))
        XCTAssertFalse(JellyCamp.canLetGo(0, home: [0, 1], camp: [3]), "a home creature must be sent to Camp first")
        XCTAssertFalse(JellyCamp.canLetGo(9, home: [0], camp: [3]), "nobody by that id")
        XCTAssertFalse(JellyCamp.canLetGo(3, home: [], camp: [3]), "never leaves the player with nobody")
        let l = JellyCamp.letGo(3, home: [0, 1], camp: [3, 4])
        XCTAssertEqual(l?.home, [0, 1]); XCTAssertEqual(l?.camp, [4])
        XCTAssertNil(JellyCamp.letGo(0, home: [0, 1], camp: [3]))
    }

    // MARK: the purge

    func testEverythingOfTheCreatureGoesAndNothingOfAnyoneElse() {
        for id in [100, 4] {
            let d = suite()
            seed(d, home: [1, 2], camp: [id, 5])
            let other = 1
            let (slot, look) = play(d, id, other: other)
            XCTAssertTrue(JellyCamp.letGo(id, d))
            XCTAssertEqual(JellyRoster.savedIDs(d), [1, 2]); XCTAssertEqual(JellyCamp.saved(d), [5], "gone from both lists")
            XCTAssertNil(JellyCamp.pendingRelease(d))
            XCTAssertEqual(d.integer(forKey: DropsWallet.key), 5000 + JellyCamp.thankYouCoins)
            for k in JellyCamp.instanceKeys(id) { XCTAssertNil(d.object(forKey: k), "id \(id): \(k)") }
            for k in JellyCamp.instanceKeys(other) { XCTAssertNotNil(d.object(forKey: k), "the other creature keeps \(k)") }
            // nothing else carries the id: no key with its suffix, no entry in any shared book
            XCTAssertFalse(d.dictionaryRepresentation().keys.contains { $0.contains(".jelly\(id)") }, "no key with the instance suffix remains")
            for k in ["JellyTraits.v1", "JellyVariants.v1", JellyNames.defaultsKey, "Circuit.trophies.v1"] {
                let o = obj(d, k) as? [String: Any]
                XCTAssertNil(o?["\(id)"], "\(k) id \(id)"); XCTAssertNotNil(o?["\(other)"], "\(k) keeps the other")
            }
            let store = try! JSONDecoder().decode(StoreBook.Saved.self, from: d.data(forKey: StoreBook.key)!)
            XCTAssertNil(store.worn["\(id)"]); XCTAssertNotNil(store.worn["\(other)"])
            XCTAssertNil(store.ownedTricks?["\(id)"]); XCTAssertNotNil(store.ownedTricks?["\(other)"]); XCTAssertEqual(store.everyone, ["ears"], "everyone-tricks stay")
            XCTAssertEqual(store.counts["berries"], 3)
            XCTAssertNil(((obj(d, ShowProgress.key) as? [String: Any])?["trophies"] as? [String: Any])?["\(id)"]); XCTAssertNotNil(((obj(d, ShowProgress.key) as? [String: Any])?["trophies"] as? [String: Any])?["\(other)"])
            XCTAssertNil(((obj(d, "Volley.book.v1") as? [String: Any])?["stats"] as? [String: Any])?["\(id)"])
            XCTAssertNil(d.object(forKey: "volley.partner"))
            let up = obj(d, UpgradeTuning.defaultsKey) as? [String: Any]
            let pts = up?["points"] as? [String: Int] ?? [:]
            XCTAssertNil(pts["race.\(id)"]); XCTAssertEqual(pts["show.\(other)"], 7); XCTAssertEqual(pts["race.\(id)1"], 9, "a different id that merely starts with the digits is not touched")
            XCTAssertNil((up?["chosen"] as? [String: Any])?["race.\(id)"])
            let v = (obj(d, ParkBook.key) as? [[String: Any]])?.first?["friendship"] as? [String: Double]
            XCTAssertNil(v?["\(id)"]); XCTAssertEqual(v?["\(other)"], 20)
            XCTAssertNil(((obj(d, ParkBook.ledgerKey) as? [String: Any])?["love"] as? [String: Any])?["\(id)"])
            if id < 7 { XCTAssertEqual(d.stringArray(forKey: JellyRoster.namesKey)?[id], "", "back to the base name") }
            else { XCTAssertNil(d.dictionary(forKey: JellyRoster.extraNamesKey)?["\(id)"]); XCTAssertNil(d.dictionary(forKey: JellyRoster.speciesKey)?["\(id)"]); XCTAssertNil(JellyRoster.speciesMap[id]) }
            _ = (slot, look)
        }
    }

    func testClothesGoBackToTheBagAndAnotherCreatureCanWearThem() {
        let d = suite()
        seed(d, home: [1], camp: [4])
        let (slot, look) = play(d, 4, other: 1)
        let before = try! JSONDecoder().decode(StoreBook.Saved.self, from: d.data(forKey: StoreBook.key)!).wearables
        JellyCamp.letGo(4, d)
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: true, defaults: d); Self.keep.append(book)
        XCTAssertEqual(book.saved.wearables, before, "every item it wore is still owned")
        XCTAssertTrue(book.ownsLook(look))
        XCTAssertNil(book.outfit(4)[slot], "nobody wears it now")
        XCTAssertTrue(book.wear(look, on: 0), "and another creature can put it on")
        XCTAssertEqual(book.worn(0, slot), look)
    }

    func testThePurgeRunsTheHooks() {
        let d = suite(); seed(d, home: [1], camp: [4])
        var seen: [Int] = []; JellyCamp.onPurge.append { seen.append($0) }
        JellyCamp.letGo(4, d)
        XCTAssertEqual(seen, [4])
    }

    // MARK: paid once

    func testLettingGoTwiceIsImpossibleAndPaysOnce() {
        let d = suite(); seed(d, home: [1], camp: [4, 5]); d.set(100, forKey: DropsWallet.key)
        XCTAssertTrue(JellyCamp.letGo(4, d))
        XCTAssertFalse(JellyCamp.letGo(4, d), "already gone")
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 200)
        XCTAssertFalse(JellyCamp.letGo(1, d), "the only creature at home cannot be let go (not at Camp)")
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 200)
        XCTAssertTrue(JellyCamp.letGo(5, d)); XCTAssertEqual(d.integer(forKey: DropsWallet.key), 300)
        XCTAssertEqual(JellyRoster.savedIDs(d), [1]); XCTAssertEqual(JellyCamp.saved(d), [])
    }

    func testKillAtEveryPointLeavesTheCreatureFullyThereOrGonePaidOnce() {
        for k in 0...5 {
            let d = suite(); seed(d, home: [1, 2], camp: [4, 5])
            play(d, 4, other: 1)
            XCTAssertTrue(JellyCamp.letGo(4, d, stopAfter: k), "k=\(k)")
            if k == 0 {
                XCTAssertEqual(JellyCamp.saved(d), [4, 5]); XCTAssertEqual(d.integer(forKey: DropsWallet.key), 5000, "killed before anything: fully there, unpaid")
                XCTAssertNil(JellyCamp.pendingRelease(d))
            } else {
                XCTAssertFalse(JellyCamp.saved(d).contains(4), "k=\(k): from the marker on nobody sees it half there")
                XCTAssertEqual(JellyCamp.saved(d).contains(5), true); XCTAssertEqual(JellyRoster.savedIDs(d), [1, 2])
            }
            // the next launch
            JellyCamp.resumeRelease(d)
            JellyCamp.resumeRelease(d)
            if k == 0 { XCTAssertEqual(d.integer(forKey: DropsWallet.key), 5000); XCTAssertEqual(JellyCamp.saved(d), [4, 5]); continue }
            XCTAssertEqual(d.integer(forKey: DropsWallet.key), 5000 + JellyCamp.thankYouCoins, "k=\(k): paid exactly once, however often the launch repeats")
            XCTAssertEqual(JellyCamp.saved(d), [5]); XCTAssertNil(JellyCamp.pendingRelease(d))
            for key in JellyCamp.instanceKeys(4) { XCTAssertNil(d.object(forKey: key), "k=\(k) \(key)") }
            XCTAssertFalse(d.dictionaryRepresentation().keys.contains { $0.contains(".jelly4") })
        }
    }
    func testALaterLetGoAfterAKillFinishesTheOldOneFirstWithoutPayingTwice() {
        let d = suite(); seed(d, home: [1], camp: [4, 5]); d.set(0, forKey: DropsWallet.key)
        JellyCamp.letGo(4, d, stopAfter: 2)          // marker + wallet written, then killed
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 100)
        XCTAssertFalse(JellyCamp.letGo(4, d), "this id is already being let go: finishes it, pays nothing more")
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 100)
        XCTAssertEqual(JellyCamp.saved(d), [5])
    }

    // MARK: the id comes back fresh

    func testBuyingTheSameSpeciesAfterwardsStartsFresh() {
        let d = suite(); seed(d, home: [1, 2, 3], camp: [4])
        play(d, 4, other: 1)
        JellyCamp.letGo(4, d)
        let p = StartFlow.placeNew(species: 4, name: "Brand new", variant: nil, traits: nil, first: false, d)
        XCTAssertEqual(p?.id, 4, "the freed species id is used again, only after the purge")
        XCTAssertEqual(p?.destination, .camp)
        let store = try! JSONDecoder().decode(StoreBook.Saved.self, from: d.data(forKey: StoreBook.key)!)
        XCTAssertNil(store.ownedTricks?["4"], "none of the old one's tricks"); XCTAssertNil(store.worn["4"])
        XCTAssertNil(((obj(d, ShowProgress.key) as? [String: Any])?["trophies"] as? [String: Any])?["4"], "no trophies")
        XCTAssertNil(((obj(d, "Circuit.trophies.v1") as? [String: Any])?["4"]))
        XCTAssertNil(((obj(d, ParkBook.key) as? [[String: Any]])?.first?["friendship"] as? [String: Any])?["4"], "no park friendship")
        XCTAssertEqual(JellyRoster.nameOf(4), "Brand new")
        XCTAssertNil(d.object(forKey: JellyKeys.needs(4)))
    }
}
