//
//  FoodHandheldTests.swift
//  2026-11-16 (the user's ask: "Remove foods in bowls it looks weird because they eat with hands"): the Ramen bowl, Mac & cheese and Fruit cup are gone, replaced by a
//  Cinnamon roll and a Fruit skewer (same perk, same price; Mac & cheese's owners get the existing Donut); the café's Mini sundae is an Ice cream cone and its Jelly Cup a Jelly puff. Saves, favourites
//  and old ids keep working (Store/StoreBook+RetiredFoods.swift). Fast: no rooms, no dining runs (DiningFlowTests / StoreFoodTests toss every food).
//

import XCTest
@testable import BobV1

@MainActor
final class FoodHandheldTests: XCTestCase {
    private let retired = ["ramen", "macncheese", "fruitcup"]
    /// removed id -> (replacement id, name, price, perk): the owner's pairs; perk and price are the old food's own.
    private let pairs: [(old: String, new: String, name: String, price: Int, perk: PerkKind)] = [
        ("ramen", "cinnamonroll", "Cinnamon roll", 18, .cozy),
        ("fruitcup", "fruitskewer", "Fruit skewer", 11, .shine)]

    private func suite(_ n: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "FoodHandheldTests.\(n)")!
        d.removePersistentDomain(forName: "FoodHandheldTests.\(n)")
        addTeardownBlock { d.removePersistentDomain(forName: "FoodHandheldTests.\(n)") }
        return d
    }

    func testTheCatalogHasNoBowlOrCupFoods() {
        let sold = StoreCatalog.items.filter { $0.kind == .food || $0.kind == .treat }
        XCTAssertGreaterThan(sold.count, 15)
        for old in retired {
            XCTAssertNil(StoreCatalog.item(old), "\(old) is not sold")
            XCTAssertNil(Consumables.all.first { $0.id == old }, "\(old) is not a consumable")
            XCTAssertFalse(FoodMeshes.resourceIDs.contains(old), "\(old) has no model any more")
            XCTAssertNil(FoodMeshes.loaded[old])
        }
        let words = try! NSRegularExpression(pattern: "\\b(bowl|cup|bowls|cups|mug)\\b", options: .caseInsensitive)
        func hit(_ s: String) -> Bool { words.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
        for i in sold { XCTAssertFalse(hit(i.name) || hit(i.description), "\(i.name): a bowl / cup food (\(i.description))") }
        for t in CafeMenu.foods { XCTAssertFalse(hit(t.name) || hit(t.blurb), "café \(t.name): a bowl / cup food") }
        XCTAssertEqual(CafeMenu.treat(.sundae).name, "Ice cream cone"); XCTAssertEqual(CafeMenu.treat(.jellycup).name, "Jelly puff")
    }

    func testEachReplacementKeepsThePerkAndThePrice() {
        for p in pairs {
            let item = try! XCTUnwrap(StoreCatalog.item(p.new), p.new)
            XCTAssertEqual(item.name, p.name); XCTAssertEqual(item.price, p.price, "\(p.name): price"); XCTAssertEqual(item.perk, p.perk, "\(p.name): perk")
            XCTAssertEqual(item.food, p.new)
            let c = try! XCTUnwrap(Consumables.all.first { $0.id == p.new })
            XCTAssertEqual(c.perk, p.perk); XCTAssertEqual(c.name, p.name); XCTAssertEqual(c.kind, .food); XCTAssertEqual(c.eatStyle, .finger, "\(p.name): tossed like every hand-held food")
            XCTAssertEqual(RetiredFoods.current(p.old), p.new)
            // the bundled Blender model draws it (not the stand-in block)
            let b = RoomMeshBuilder(); b.material = .plain
            XCTAssertTrue(FoodMeshes.append(b, id: p.new, centre: .zero, variant: 0, scale: 1), "\(p.new): food_\(p.new).bin loads")
            XCTAssertGreaterThan(b.mesh.indices.count / 3, 1500)
        }
        // the café keeps its ids, prices and perks; the two models were replaced
        XCTAssertEqual(CafeMenu.treat(.sundae).price, 18); XCTAssertEqual(CafeMenu.treat(.sundae).perk, .bouncy)
        XCTAssertEqual(CafeMenu.treat(.jellycup).price, 8); XCTAssertEqual(CafeMenu.treat(.jellycup).perk, .cozy)
        for t in [CafeTreatID.sundae, .jellycup] {
            let b = RoomMeshBuilder(); b.material = .plain
            XCTAssertTrue(FoodMeshes.append(b, id: t.rawValue, centre: .zero, variant: 0, scale: 1), "\(t): bundled model")
        }
    }

    func testOwnedCountsConvertOnceAndKeepAnyReplacementAlreadyOwned() throws {
        let d = suite("counts")
        var s = StoreBook.Saved()
        s.counts = ["ramen": 2, "macncheese": 1, "fruitcup": 3, "cinnamonroll": 1, "taco": 4, "donut": 2]
        d.set(try JSONEncoder().encode(s), forKey: "book")
        let first = StoreBook(wallet: DropsWallet(persists: false), persists: true, defaults: d, key: "book")
        XCTAssertEqual(first.count("cinnamonroll"), 3, "2 + the 1 already owned"); XCTAssertEqual(first.count("donut"), 3, "1 Mac & cheese + the 2 Donuts already owned"); XCTAssertEqual(first.count("fruitskewer"), 3)
        for old in retired { XCTAssertEqual(first.count(old), 0); XCTAssertNil(first.saved.counts[old], "\(old) is gone from the save") }
        XCTAssertEqual(first.count("taco"), 4, "other foods untouched")
        // it ran and was saved: a second load changes nothing (no doubling)
        let second = StoreBook(wallet: DropsWallet(persists: false), persists: true, defaults: d, key: "book")
        XCTAssertEqual(second.count("cinnamonroll"), 3); XCTAssertEqual(second.count("donut"), 3); XCTAssertEqual(second.count("fruitskewer"), 3)
        // the pass on its own: pure, and a save with none of them comes back untouched
        let (_, changed) = StoreBook.convertRetiredFoods(second.saved)
        XCTAssertFalse(changed)
        // a zero count is dropped, not turned into an empty entry
        var z = StoreBook.Saved(); z.counts = ["ramen": 0]
        let r = StoreBook.convertRetiredFoods(z)
        XCTAssertTrue(r.changed); XCTAssertNil(r.saved.counts["ramen"]); XCTAssertNil(r.saved.counts["cinnamonroll"])
    }

    func testFavouritesThatWereRemovedFoodsBecomeTheirReplacement() throws {
        let d = suite("favs")
        let raw: [String: JellyTraits] = ["1": JellyTraits(personality: .brave, jars: [50, 50, 50, 50, 50], snack: "ramen"),
                                         "2": JellyTraits(personality: .cuddly, jars: [50, 50, 50, 50, 50], snack: "macncheese"),
                                         "3": JellyTraits(personality: .gentle, jars: [50, 50, 50, 50, 50], snack: "fruitcup"),
                                         "4": JellyTraits(personality: .bouncy, jars: [50, 50, 50, 50, 50], snack: "taco")]
        d.set(try JSONEncoder().encode(raw), forKey: JellyTraitsBook.key)
        let loaded = JellyTraitsBook.load(d)
        XCTAssertEqual(loaded[1]?.snack, "cinnamonroll"); XCTAssertEqual(loaded[2]?.snack, "donut"); XCTAssertEqual(loaded[3]?.snack, "fruitskewer"); XCTAssertEqual(loaded[4]?.snack, "taco")
        // rewritten once: the stored record already holds the new ids
        let stored = try JSONDecoder().decode([String: JellyTraits].self, from: try XCTUnwrap(d.data(forKey: JellyTraitsBook.key)))
        XCTAssertEqual(stored["1"]?.snack, "cinnamonroll"); XCTAssertEqual(stored["3"]?.snack, "fruitskewer")
        XCTAssertEqual(loaded[1]?.summary, "Brave · loves Cinnamon roll")
        // new Jelmiko can only pick foods that are sold
        for p in [JellyPersonality.cuddly, .brave, .gentle, .bouncy, .curious, .sleepy, .giggly, .cheeky] {
            for f in p.snacks { XCTAssertNotNil(StoreCatalog.item(f), "\(p) likes \(f), which is not sold"); XCTAssertFalse(retired.contains(f)) }
        }
        // and a favourite food is still a food with a power-up to double (FavouriteFoodTests covers the doubling itself)
        for p in [JellyPersonality.brave, .gentle] { XCTAssertTrue(p.snacks.contains { id in pairs.contains { $0.new == id } }) }
    }

    func testOldIdsNeverCrashAndTheDiaryKeepsItsNames() throws {
        // a stale tray / dev argument / old record naming a retired food finds its replacement
        XCTAssertEqual(Consumables.with(id: "ramen")?.id, "cinnamonroll"); XCTAssertEqual(Consumables.with(id: "macncheese")?.id, "donut"); XCTAssertEqual(Consumables.with(id: "fruitcup")?.id, "fruitskewer")
        XCTAssertNil(Consumables.with(id: "nonsense"))
        XCTAssertEqual(JellyTraits(personality: .brave, jars: [50, 50, 50, 50, 50], snack: "ramen").snackName, "Cinnamon roll")
        // the food diary stores the meal's NAME as text: an old "Ramen bowl" line still decodes and reads as it did
        let entry = try JSONDecoder().decode(MealEntry.self, from: Data(#"{"food":"Ramen bowl","at":1000,"gains":{"0":0.1}}"#.utf8))
        XCTAssertEqual(entry.food, "Ramen bowl")
        // an older backup merged in brings its Ramen bowls as Cinnamon rolls, not as dropped items
        let d = suite("import")
        let rep = ImportSave.merge(old: [StoreBook.key: Data(#"{"counts":{"ramen":2,"fruitcup":1,"taco":1}}"#.utf8)], into: d)
        let s = try JSONDecoder().decode(StoreBook.Saved.self, from: try XCTUnwrap(d.data(forKey: StoreBook.key)))
        XCTAssertEqual(s.counts["cinnamonroll"], 2); XCTAssertEqual(s.counts["fruitskewer"], 1); XCTAssertNil(s.counts["ramen"])
        XCTAssertFalse(rep.dropped.contains("item:ramen"))
    }

    func testSellBackWorksWithTheMovedCounts() throws {
        let d = suite("sell")
        var s = StoreBook.Saved(); s.counts = ["ramen": 2, "fruitcup": 1, "macncheese": 1, "donut": 1]
        d.set(try JSONEncoder().encode(s), forKey: "sellbook")
        let w = DropsWallet(persists: false)
        let b = StoreBook(wallet: w, persists: true, defaults: d, key: "sellbook")
        XCTAssertNil(b.sell("ramen"), "a retired id cannot be sold")
        XCTAssertNil(b.sell("fruitcup")); XCTAssertNil(b.sell("macncheese"))
        XCTAssertEqual(b.count("donut"), 2, "Mac & cheese moved into the Donuts"); XCTAssertEqual(b.sell("donut"), 7, "and sells as a Donut at half of 14")
        XCTAssertEqual(b.sell("cinnamonroll"), 9, "moved counts sell as the new food at half its price")
        XCTAssertEqual(b.count("cinnamonroll"), 1); XCTAssertEqual(b.sell("fruitskewer"), 5)
        XCTAssertEqual(w.count, 21)
    }
}
