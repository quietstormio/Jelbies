//
//  RetiredTutuTests.swift
//  2026-11-22 (the owner: "Remove the tutu it looks stupid"): the Ballet tutu is out of the game. Not sold, not in the Dress up list, not worn by anyone generated;
//  a save that owns / wears it loads without it and is refunded at its price exactly once (StoreBook+RetiredTutu.swift).
//

import XCTest
@testable import BobV1

@MainActor
final class RetiredTutuTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    func testTheCatalogueNoLongerListsTheTutu() {
        XCTAssertTrue(WearLook.retired.contains(.tutuPink))
        XCTAssertNil(StoreCatalog.item(wearing: .tutuPink))
        XCTAssertFalse(StoreCatalog.items.contains { $0.wear == .tutuPink || $0.id.contains("tutu") })
        XCTAssertFalse(StoreCatalog.items(.wear).contains { $0.id.contains("tutu") })
        XCTAssertFalse(WearLook.pieces.contains(.tutuPink))
    }

    func testNobodyGeneratedWearsTheTutu() {
        XCTAssertFalse(ParkPool.wearables.contains(.tutuPink))
        // the park's generated visitors (the pool, the extras, the species ones) over several seeds: nobody wears a retired look (the Show rivals and the café guests wear no WearLook at all)
        for seed in [UInt64(1), 7, 42, 2026] {
            for v in ParkPool.generate(seed: seed) + ParkPool.extras(seed: seed) { XCTAssertFalse(WearLook.retired.contains { $0 == v.wear }, "\(v.name) seed \(seed)") }
        }
        for v in ParkPool.all() + ParkPool.speciesVisitors() { XCTAssertNotEqual(v.wear, .tutuPink, v.name) }
        // every piece a generator can reach (the shop catalogue and the pieces list) is free of it
        XCTAssertFalse(StoreCatalog.items.compactMap(\.wear).contains(.tutuPink))
        XCTAssertNil(WearLook.pieces.first { $0.art == "tutu_pink" })
    }

    func testASaveThatOwnsAndWearsTheTutuLosesItAndIsRefundedOnce() throws {
        let suite = "RetiredTutuTests.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        var saved = StoreBook.Saved()
        let tutu = WearLook.tutuPink.rawValue
        saved.wearables = [tutu, WearLook.tutuPink.row.storeID, WearLook.beret.rawValue]
        saved.worn = ["0": ["body": tutu, "head": WearLook.beret.rawValue], "1": ["body": tutu]]
        saved.showHome = ["0": ["body": tutu, "head": WearLook.beret.rawValue], "2": [:]]
        d.set(try JSONEncoder().encode(saved), forKey: StoreBook.key)
        let w = DropsWallet(persists: false)
        let before = w.count
        let b = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b)
        XCTAssertEqual(w.count - before, 2 * WearLook.tutuPink.row.price, "each copy is paid at its price")
        XCTAssertEqual(WearLook.tutuPink.row.price, 60)
        XCTAssertFalse(b.ownsLook(.tutuPink))
        XCTAssertEqual(b.saved.wearables, [WearLook.beret.rawValue])
        XCTAssertNil(b.worn(0, .body)); XCTAssertNil(b.worn(1, .body))
        XCTAssertEqual(b.worn(0, .head), .beret, "other clothes stay")
        XCTAssertFalse((b.saved.showHome ?? [:]).values.contains { $0.values.contains(tutu) }, "no remembered outfit holds it")
        XCTAssertFalse(b.saved.worn.values.contains { $0.values.contains(tutu) })
        // loading again pays nothing more
        let b2 = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b2)
        XCTAssertEqual(w.count - before, 120, "a second load never pays twice")
        let b3 = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b3)
        XCTAssertEqual(w.count - before, 120)
        XCTAssertFalse(StoreBook.dropRetiredTutu(b3.saved).changed)
        XCTAssertEqual(StoreBook.dropRetiredTutu(StoreBook.Saved()).refund, 0)
    }

    func testAShowWardrobeThatRemembersTheTutuComesBackWithoutIt() throws {
        let suite = "RetiredTutuTests.home.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        var saved = StoreBook.Saved()
        saved.showHome = ["0": ["body": WearLook.tutuPink.rawValue, "neck": WearLook.pearls.rawValue]]
        saved.worn = ["0": ["body": WearLook.capeHero.rawValue]]
        d.set(try JSONEncoder().encode(saved), forKey: StoreBook.key)
        let w = DropsWallet(persists: false); let before = w.count
        let b = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b)
        XCTAssertEqual(w.count, before, "never owned: nothing to refund")
        XCTAssertNil(b.saved.showHome, "restored on load")
        XCTAssertNil(b.worn(0, .body), "the remembered tutu is not put back")
        XCTAssertFalse(b.hasEveryday)
    }
    // MARK: the three necklaces (2026-11-23: "Remove all necklaces besides the diamond chain"): the same four checks for each, over the list

    static let necklaces: [(look: WearLook, price: Int)] = [(.pearls, 65), (.lei, 45), (.whistleCoach, 30)]

    func testTheCatalogueNoLongerListsTheNecklaces() {
        XCTAssertTrue(WearLook.retired.contains(.diamondJ) == false, "the Diamond J chain stays")
        XCTAssertNotNil(StoreCatalog.item(wearing: .diamondJ))
        XCTAssertTrue(WearLook.pieces.contains(.diamondJ))
        for (l, price) in Self.necklaces {
            XCTAssertTrue(WearLook.retired.contains(l), l.rawValue)
            XCTAssertEqual(l.row.price, price, "\(l.rawValue) price")
            XCTAssertNil(StoreCatalog.item(wearing: l), l.rawValue)
            XCTAssertFalse(StoreCatalog.items.contains { $0.wear == l }, l.rawValue)
            XCTAssertFalse(StoreCatalog.items(.wear).contains { $0.wear == l }, l.rawValue)
            XCTAssertFalse(WearLook.pieces.contains(l), l.rawValue)
            XCTAssertNil(WearLook.pieces.first { $0.art == l.art }, l.rawValue)
        }
        // other neck pieces are not necklaces and stay
        for l in [WearLook.bandanaCoral, .scarfCosy, .bowtiePink, .bibPink, .medalGold, .scarfSilk] { XCTAssertTrue(WearLook.pieces.contains(l), l.rawValue) }
        // no sold neck item is a string necklace
        XCTAssertFalse(StoreCatalog.items.contains { $0.name.lowercased().contains("necklace") || $0.name.lowercased().contains("lei") && $0.wear != nil || $0.name.lowercased().contains("whistle") && $0.wear != nil })
    }

    func testNobodyGeneratedWearsTheNecklaces() {
        for (l, _) in Self.necklaces { XCTAssertFalse(ParkPool.wearables.contains(l), l.rawValue) }
        for seed in [UInt64(1), 7, 42, 2026] {
            for v in ParkPool.generate(seed: seed) + ParkPool.extras(seed: seed) { XCTAssertFalse(WearLook.retired.contains { $0 == v.wear }, "\(v.name) seed \(seed)") }
        }
        for v in ParkPool.all() + ParkPool.speciesVisitors() { XCTAssertFalse(Self.necklaces.contains { $0.look == v.wear }, v.name) }
        XCTAssertFalse(StoreCatalog.items.compactMap(\.wear).contains { l in Self.necklaces.contains { $0.look == l } })
    }

    func testASaveThatOwnsAndWearsTheNecklacesLosesThemAndIsRefundedOnce() throws {
        let suite = "RetiredTutuTests.neck.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        var saved = StoreBook.Saved()
        // the owner's save shape: a whistle and pearls (one pearls twice), the Diamond J, a bandana; the lei worn by a second Jelmiko
        saved.wearables = [WearLook.whistleCoach.rawValue, WearLook.pearls.rawValue, WearLook.pearls.row.storeID, WearLook.diamondJ.rawValue, WearLook.bandanaCoral.rawValue, WearLook.lei.rawValue]
        saved.worn = ["0": ["neck": WearLook.pearls.rawValue, "head": WearLook.beret.rawValue], "1": ["neck": WearLook.lei.rawValue], "2": ["neck": WearLook.diamondJ.rawValue]]
        saved.showHome = ["0": ["neck": WearLook.whistleCoach.rawValue, "head": WearLook.beret.rawValue], "1": ["neck": WearLook.diamondJ.rawValue]]
        d.set(try JSONEncoder().encode(saved), forKey: StoreBook.key)
        let w = DropsWallet(persists: false); let before = w.count
        let b = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b)
        let expected = 30 + 2 * 65 + 45
        XCTAssertEqual(w.count - before, expected, "each copy is paid at its Shop price")
        for (l, _) in Self.necklaces { XCTAssertFalse(b.ownsLook(l), l.rawValue) }
        XCTAssertEqual(Set(b.saved.wearables), [WearLook.diamondJ.rawValue, WearLook.bandanaCoral.rawValue])
        XCTAssertNil(b.worn(0, .neck))
        XCTAssertEqual(b.worn(1, .neck), .diamondJ, "the remembered home outfit comes back on load (its lei gone, its Diamond J kept)")
        XCTAssertEqual(b.worn(2, .neck), .diamondJ, "the Diamond J stays on")
        XCTAssertEqual(b.worn(0, .head), .beret, "other clothes stay")
        let all = Set(Self.necklaces.flatMap { [$0.look.rawValue, $0.look.row.storeID] })
        XCTAssertFalse(b.saved.worn.values.contains { $0.values.contains { all.contains($0) } })
        XCTAssertNil(b.saved.showHome, "restored on load")
        XCTAssertFalse((b.saved.showHome ?? [:]).values.contains { $0.values.contains { all.contains($0) } }, "no remembered outfit holds one")
        let b2 = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b2)
        XCTAssertEqual(w.count - before, expected, "a second load never pays twice")
        XCTAssertFalse(StoreBook.dropRetiredRefunded(b2.saved).changed)
        XCTAssertEqual(StoreBook.dropRetiredRefunded(StoreBook.Saved()).refund, 0)
    }

    /// The owner's real save (a copy of the 11-21 phone backup, read only): one whistle, one pearls, no lei, one tutu, one Diamond J. Set NECK_SAVE_PLIST to run it.
    func testTheOwnersSaveIsRefundedWhatItOwns() throws {
        guard let path = ProcessInfo.processInfo.environment["NECK_SAVE_PLIST"] else { throw XCTSkip("NECK_SAVE_PLIST not set") }
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil) as? [String: Any])
        let raw = try XCTUnwrap(plist[StoreBook.key])
        let data: Data
        if let d = raw as? Data { data = d } else { data = try JSONSerialization.data(withJSONObject: raw) }
        let saved = try JSONDecoder().decode(StoreBook.Saved.self, from: data)
        let necklaces = StoreBook.dropRetiredWear(saved, [.pearls, .lei, .whistleCoach])
        let tutu = StoreBook.dropRetiredTutu(saved)
        print("[necklace] owner's save: necklaces refund \(necklaces.refund), tutu refund \(tutu.refund), all \(StoreBook.dropRetiredRefunded(saved).refund)")
        XCTAssertEqual(necklaces.refund, 30 + 65); XCTAssertEqual(tutu.refund, 60)
        XCTAssertTrue(StoreBook.dropRetiredRefunded(saved).saved.wearables.contains(WearLook.diamondJ.rawValue))
    }

    func testTheTutuPassStillPaysOnlyTheTutu() {
        var s = StoreBook.Saved()
        s.wearables = [WearLook.tutuPink.rawValue, WearLook.pearls.rawValue]
        let r = StoreBook.dropRetiredTutu(s)
        XCTAssertEqual(r.refund, 60); XCTAssertEqual(r.saved.wearables, [WearLook.pearls.rawValue])
        // an outfit that only WEARS a necklace (never owned) is still changed, nothing is paid
        var t = StoreBook.Saved(); t.worn = ["0": ["neck": WearLook.lei.rawValue]]
        let q = StoreBook.dropRetiredRefunded(t)
        XCTAssertEqual(q.refund, 0); XCTAssertTrue(q.changed); XCTAssertNil(q.saved.worn["0"]?["neck"])
    }

    func testAShowWardrobeThatRemembersANecklaceComesBackWithoutIt() throws {
        let suite = "RetiredTutuTests.homeneck.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        var saved = StoreBook.Saved()
        saved.showHome = ["0": ["neck": WearLook.lei.rawValue], "1": ["neck": WearLook.diamondJ.rawValue]]
        saved.worn = ["0": ["neck": WearLook.whistleCoach.rawValue], "1": [:]]
        d.set(try JSONEncoder().encode(saved), forKey: StoreBook.key)
        let w = DropsWallet(persists: false); let before = w.count
        let b = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b)
        XCTAssertEqual(w.count, before)
        XCTAssertNil(b.saved.showHome)
        XCTAssertNil(b.worn(0, .neck), "neither the Show outfit's lei nor the worn whistle is put back")
    }
}
