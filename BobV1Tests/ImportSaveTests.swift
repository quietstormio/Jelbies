//
//  ImportSaveTests.swift
//  `-ImportSave 1`: merges an old save's room into the current game. Real plists via env vars OLD_SAVE_PLIST / NEW_SAVE_PLIST (absolute paths); skipped if unset.
//

import XCTest
@testable import BobV1

@MainActor
final class ImportSaveTests: XCTestCase {
    private func plist(_ env: String, _ fallback: String) throws -> [String: Any] {
        let path = ProcessInfo.processInfo.environment[env] ?? fallback
        guard let data = FileManager.default.contents(atPath: path) else { throw XCTSkip("no \(path)") }
        return try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }
    private func suite(_ n: String, seed: [String: Any]) -> UserDefaults {
        let d = UserDefaults(suiteName: "ImportSaveTests.\(n)")!
        d.removePersistentDomain(forName: "ImportSaveTests.\(n)")
        for (k, v) in seed { d.set(v, forKey: k) }
        return d
    }
    private func store(_ d: UserDefaults) -> StoreBook.Saved { try! JSONDecoder().decode(StoreBook.Saved.self, from: d.data(forKey: StoreBook.key)!) }
    private let oldPath = "/Users/dmarshall94/BobV1_backups/save_20261031/prefs_20261031.plist"
    private let newPath = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/crash/prefs_after_clear2.plist"

    func testMergeKeepsCurrentIdentityAndBringsBackRoom() throws {
        let old = try plist("OLD_SAVE_PLIST", oldPath), cur = try plist("NEW_SAVE_PLIST", newPath)
        let d = suite("merge", seed: cur)
        let before = store(d)
        let rep = ImportSave.merge(old: old, into: d)
        XCTAssertTrue(rep.applied)
        // identity and progress untouched
        for k in cur.keys where k != StoreBook.key {
            XCTAssertTrue(NSDictionary(dictionary: [k: cur[k]!]).isEqual(to: [k: d.object(forKey: k) ?? "MISSING"]), "\(k) changed")
        }
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 8472)
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 5, 4])
        // settings came over
        XCTAssertEqual(d.string(forKey: "ThemeColor.v1"), "pink")
        XCTAssertEqual(d.string(forKey: "townCategory"), "All")
        XCTAssertEqual(d.double(forKey: "Audio.musicVolume"), 0.848739504814148, accuracy: 1e-9)
        XCTAssertNil(d.object(forKey: "DayClock.left.v1"))
        let s = store(d)
        // old placements present (the old soccerball, uid 2) and uid counter safe
        XCTAssertEqual(s.placedAt?.map(\.uid), [2])
        XCTAssertEqual(s.placedAt?.first?.kind, .soccerball)
        XCTAssertGreaterThanOrEqual(s.nextDecorUID ?? 0, 17)
        // ownership union: every decor id in either save is owned
        let oldCounts = ((try JSONSerialization.jsonObject(with: old[StoreBook.key] as! Data)) as! [String: Any])["counts"] as! [String: Int]
        for (k, n) in oldCounts { XCTAssertGreaterThanOrEqual(s.counts[k] ?? 0, n, k) }
        for (k, n) in before.counts { XCTAssertGreaterThanOrEqual(s.counts[k] ?? 0, n, "lost \(k)") }
        // consumables not duplicated (max, not sum)
        XCTAssertEqual(s.counts["taco"], 2); XCTAssertEqual(s.counts["decor-soccerball"], 1)
        XCTAssertEqual(s.counts["onigiri"], 3)
        for w in before.wearables { XCTAssertTrue(s.wearables.contains(w)) }
        XCTAssertTrue(s.wearables.contains("flowerCrown"))
        // worn and flags unchanged
        XCTAssertEqual(s.worn, before.worn)
        XCTAssertEqual(s.starterGiven, before.starterGiven)
        XCTAssertEqual(s.gardenRefunded, before.gardenRefunded)
        // a StoreBook built on the result loads it
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: true, defaults: d)
        XCTAssertEqual(book.placedDecor.count, 1)
    }

    func testUnknownIdsAreDroppedAndLogged() throws {
        let json = #"{"counts":{"seed-daisy":2,"decor-beanbag":1},"rooms":["garden","loft"],"room":"garden","placedAt":[{"kind":"nope","uid":3,"x":0,"z":0},{"kind":"beanbag","uid":4,"x":1,"z":1}],"nextDecorUID":9}"#
        let d = suite("drop", seed: [:])
        let rep = ImportSave.merge(old: [StoreBook.key: Data(json.utf8)], into: d)
        let s = store(d)
        XCTAssertNil(s.counts["seed-daisy"]); XCTAssertEqual(s.counts["decor-beanbag"], 1)
        XCTAssertEqual(s.rooms, ["loft"]); XCTAssertNil(s.room)
        XCTAssertEqual(s.placedAt?.map(\.uid), [4]); XCTAssertEqual(s.nextDecorUID, 9)
        XCTAssertTrue(rep.dropped.contains("placement:current/nope")); XCTAssertTrue(rep.dropped.contains("room:garden"))
    }

    func testHookIsOneShotAndMissingFileDoesNothing() throws {
        let d = suite("hook", seed: ["BlobRoster.v1": [0]])
        let dir = FileManager.default.temporaryDirectory.appending(path: "ImportSaveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "import_save.plist")
        XCTAssertFalse(ImportSave.apply(arg: 1, url: url, defaults: d).applied, "missing file")
        XCTAssertNil(d.string(forKey: ImportSave.appliedKey), "a missing file does not spend the one shot")
        let oldStore = Data(#"{"counts":{"decor-beanbag":1},"placedAt":[{"kind":"beanbag","uid":1,"x":1,"z":1}]}"#.utf8)
        try PropertyListSerialization.data(fromPropertyList: [StoreBook.key: oldStore, "ThemeColor.v1": "blue"], format: .binary, options: 0).write(to: url)
        XCTAssertFalse(ImportSave.apply(arg: nil, url: url, defaults: d).applied, "no argument")
        XCTAssertTrue(ImportSave.apply(arg: 1, url: url, defaults: d).applied)
        XCTAssertEqual(d.string(forKey: "ThemeColor.v1"), "blue")
        d.set("changed", forKey: "ThemeColor.v1")
        XCTAssertFalse(ImportSave.apply(arg: 1, url: url, defaults: d).applied, "second launch")
        XCTAssertEqual(d.string(forKey: "ThemeColor.v1"), "changed")
        XCTAssertFalse(ImportSave.apply(arg: 0, url: url, defaults: d).applied)       // re-arms
        XCTAssertTrue(ImportSave.apply(arg: 1, url: url, defaults: d).applied)
        XCTAssertEqual(d.string(forKey: "ThemeColor.v1"), "blue")
    }
}
