//
//  NewcomerFullTests.swift
//  Owner 11-24: "when a new Jelmiko comes home their status should be full like not hungry or thirsty".
//  Every arrival path (the first gift, a Spring adoption, a Camp return) shows Full / Quenched on the Profile, no need bubble, no "needs you".
//

import XCTest
@testable import BobV1

@MainActor
final class NewcomerFullTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var suites: [String] = []
    private var savedMap: [Int: Int] = [:], savedCurrent: [Int] = [], savedNames: [Int: String] = [:]

    override func setUp() { savedMap = JellyRoster.speciesMap; savedCurrent = JellyRoster.current; savedNames = JellyRoster.extraNames; JellyRoster.speciesMap = [:]; JellyRoster.extraNames = [:] }
    override func tearDown() {
        JellyRoster.speciesMap = savedMap; JellyRoster.current = savedCurrent; JellyRoster.extraNames = savedNames
        JellyVariants.reload(); JellyTraitsBook.reload()
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }; suites = []
    }
    private func suite() -> UserDefaults {
        let s = "NewcomerFullTests.\(UUID().uuidString)"; suites.append(s)
        return UserDefaults(suiteName: s)!
    }

    /// What the Profile and the roster would say for these levels (the same JellyState the Profile reads).
    private func assertFull(_ n: BlobNeeds, _ why: String, file: StaticString = #filePath, line: UInt = #line) {
        let st = JellyState(record: JellyRecord(id: 0, name: "X", color: "", levels: NeedKind.allCases.map { n.level($0) }, dirt: 0, sparkle: 0, mood: "happy"), awaySeconds: 0)
        XCTAssertEqual(ProfileWords.need(st, .food).value, "Full", why, file: file, line: line)
        XCTAssertEqual(ProfileWords.need(st, .water).value, "Quenched", why, file: file, line: line)
        XCTAssertNil(n.wantedNeed, "\(why): no need bubble", file: file, line: line)
        XCTAssertEqual(n.wantingCount, 0, "\(why): no pink 'needs you' dot", file: file, line: line)
        XCTAssertEqual(n.mood, .happy, why, file: file, line: line)
    }

    func testFirstGiftOfANewGameArrivesFull() {
        let d = suite()
        let n = BlobNeeds(defaults: d, key: JellyKeys.needs(0)); Self.keep.append(n)          // the slot-0 first launch (StartFlow wipes the key first)
        for k in NeedKind.allCases { XCTAssertEqual(n.level(k), 1, accuracy: 1e-6) }
        assertFull(n, "first gift")
    }

    func testSpringAdoptionArrivesFull() {
        let d = suite()
        d.set([0, 1], forKey: JellyRoster.rosterKey)
        guard let p = StartFlow.placeNew(species: 2, name: "Moss", variant: nil, traits: nil, first: false, d) else { return XCTFail("no room") }
        XCTAssertEqual(p.destination, .home)
        let j = JellyProfile(id: 2, character: p.id, name: "Moss", persists: true, defaults: d); Self.keep.append(j)
        for k in NeedKind.allCases { XCTAssertEqual(j.needs.level(k), 1, accuracy: 1e-6, "\(k)") }
        assertFull(j.needs, "Spring adoption")
        // every species id arrives the same (it used to pick one need by id % 3)
        for c in 1...5 {
            let x = JellyProfile(id: c, name: "N\(c)", persists: false); Self.keep.append(x)
            for k in NeedKind.allCases { XCTAssertEqual(x.needs.level(k), 1, accuracy: 1e-6, "c\(c) \(k)") }
        }
    }

    func testBroughtBackFromCampArrivesFullAndFallsFromThere() {
        let d = suite()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        d.set([0, 1], forKey: JellyRoster.rosterKey); d.set([3], forKey: JellyCamp.key)
        d.set(["levels": [0.2, 0.3, 0.5], "time": t0.timeIntervalSince1970, "asleep": false] as [String: Any], forKey: JellyKeys.needs(3))
        let home = t0.addingTimeInterval(14 * 86400)
        XCTAssertTrue(StartFlow.campMove(.bringHome(3), now: home, d))
        let n = BlobNeeds(defaults: d, key: JellyKeys.needs(3), now: { home }); Self.keep.append(n)
        for k in NeedKind.allCases { XCTAssertEqual(n.level(k), 1, accuracy: 1e-6, "\(k)") }
        assertFull(n, "Camp return")
        // normal fall from that moment
        let later = BlobNeeds(defaults: d, key: JellyKeys.needs(3), now: { home }); Self.keep.append(later)
        for _ in 0..<600 { later.step(dt: 1, petting: false, purring: false) }
        XCTAssertLessThan(later.level(.hunger), 1)
    }

    func testAnExistingSaveIsNotTouchedByTheNewSeed() {
        let d = suite(); let t = Date(timeIntervalSince1970: 5_000_000)
        d.set(["levels": [0.2, 0.9, 0.4], "time": t.timeIntervalSince1970, "asleep": false] as [String: Any], forKey: JellyKeys.needs(0))
        let n = BlobNeeds(defaults: d, key: JellyKeys.needs(0), now: { t }); Self.keep.append(n)
        XCTAssertEqual(n.level(.hunger), 0.2, accuracy: 1e-5); XCTAssertEqual(n.level(.attention), 0.4, accuracy: 1e-5)
    }
}
