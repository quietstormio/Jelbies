//
//  OpeningReplayTests.swift
//  Settings > "Watch the opening" replays the story, a preview of the species picker and the first-day scene, and saves NOTHING; a new game's
//  real flow (picker -> adopt) still saves the chosen Jelbie. The Jelbies in the story wear nothing (their species features are not clothes).
//

import XCTest
@testable import BobV1

@MainActor
final class OpeningReplayTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []          // StoreBook deinit is nonisolated; the suites keep theirs alive

    /// The keys a flow could touch: the roster, names, started flag, coins and every character's preview-written state.
    private var flowKeys: [String] {
        [JellyRoster.rosterKey, JellyRoster.namesKey, StartFlow.startedKey, DropsWallet.key]
            + (0..<4).flatMap { c in [JellyKeys.needs(c), JellyKeys.grime(c), JellyKeys.words(c), JellyKeys.stats(c), JellyKeys.perks(c)] }
    }
    private var saved: [String: Any] = [:]
    private var savedNames: [String] = []

    override func setUp() async throws {
        let d = UserDefaults.standard
        saved = [:]
        for k in flowKeys { if let v = d.object(forKey: k) { saved[k] = v } }
        savedNames = JellyRoster.names
    }
    override func tearDown() async throws {
        let d = UserDefaults.standard
        for k in flowKeys { if let v = saved[k] { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } }
        JellyRoster.names = savedNames
    }

    private func snapshot() -> NSDictionary {
        let d = UserDefaults.standard
        var s: [String: Any] = [:]
        for k in flowKeys { if let v = d.object(forKey: k) { s[k] = v } }
        return s as NSDictionary
    }

    /// The user's save: Pip, Moss and Lavender, with names, coins, a started flag and some state under each key.
    private func seedSave() {
        let d = UserDefaults.standard
        JellyRoster.save([1, 2, 3])
        JellyRoster.setName(1, "Pipsqueak"); JellyRoster.setName(2, "Mossy"); JellyRoster.setName(3, "Lav")
        d.set(true, forKey: StartFlow.startedKey)
        d.set(Data("pip".utf8), forKey: JellyKeys.needs(1))
        d.set(Data("moss".utf8), forKey: JellyKeys.stats(2))
    }

    func testReplaySavesNothing() {
        seedSave()
        let before = snapshot()
        let flow = StartFlow()
        flow.phase = .game
        flow.replayOpening()
        XCTAssertEqual(flow.phase, .opening)
        XCTAssertTrue(flow.replaying)

        flow.finishOpening()          // the story ends: the replay gets the picker too
        XCTAssertEqual(flow.phase, .adopt(.first))

        // the picker's previews write their Jelbies' state while they stand on the stage
        let d = UserDefaults.standard
        for c in 0..<4 { d.set(Data("preview\(c)".utf8), forKey: JellyKeys.needs(c)); d.set(Data("x".utf8), forKey: JellyKeys.stats(c)) }

        flow.bringHome(character: 0, name: "Bobbo")          // Blueberry is not in the save: still saved nowhere
        XCTAssertEqual(flow.phase, .firstDay(0, "Bobbo", true))
        XCTAssertEqual(JellyRoster.savedIDs(), [1, 2, 3])
        XCTAssertEqual(JellyRoster.names[0], "Bob")
        XCTAssertNil(flow.welcome)

        flow.finishFirstDay()
        XCTAssertEqual(flow.phase, .game)
        XCTAssertFalse(flow.replaying)
        XCTAssertEqual(snapshot(), before, "a replay leaves the save byte for byte as it was")
        XCTAssertEqual(JellyRoster.names[1], "Pipsqueak")
    }

    func testSkippingTheReplayPickerLeavesTheSaveAlone() {
        seedSave()
        let before = snapshot()
        let flow = StartFlow()
        flow.phase = .game
        flow.replayOpening()
        flow.finishOpening()
        UserDefaults.standard.set(Data("preview".utf8), forKey: JellyKeys.needs(3))
        flow.backToMenu()          // the picker's back button in a replay: out to the room, not the title screen
        XCTAssertEqual(flow.phase, .game)
        XCTAssertFalse(flow.replaying)
        XCTAssertEqual(snapshot(), before)
    }

    func testANewGameStillSavesTheChosenJelbie() {
        let d = UserDefaults.standard
        for k in flowKeys { d.removeObject(forKey: k) }
        let flow = StartFlow()
        flow.phase = .opening
        XCTAssertFalse(flow.replaying)
        flow.finishOpening()
        XCTAssertEqual(flow.phase, .adopt(.first))
        flow.bringHome(character: 3, name: "Wingy")
        XCTAssertEqual(flow.phase, .firstDay(3, "Wingy", false))
        XCTAssertEqual(JellyRoster.savedIDs(), [3])
        XCTAssertEqual(JellyRoster.names[3], "Wingy")
        XCTAssertTrue(d.bool(forKey: StartFlow.startedKey))
        flow.finishFirstDay()
        XCTAssertEqual(flow.phase, .game)
        XCTAssertEqual(JellyRoster.savedIDs(), [3])
    }

    func testStoryJelbiesWearNothing() {
        let w = DropsWallet(persists: false); w.add(500, silent: true)
        let b = StoreBook(wallet: w, persists: false); Self.keep.append(b)
        XCTAssertTrue(b.awardMedal())
        XCTAssertTrue(b.wear(.medalGold, on: 1))
        XCTAssertEqual(b.worn(1, .neck), .medalGold)
        XCTAssertFalse(b.outfit(1).isEmpty)
        b.bare = true
        XCTAssertNil(b.worn(1, .neck))
        XCTAssertTrue(b.outfit(1).isEmpty, "bare: nothing drawn")
        b.bare = false
        XCTAssertEqual(b.worn(1, .neck), .medalGold, "the save itself was never touched")
    }

    func testTheStageHandsItsStoreTheBareFlag() {
        for bare in [true, false] {
            let m = GameScreen.makeGameModel(jellyCount: 1)
            m.care.store.bare = bare
            XCTAssertEqual(m.care.store.bare, bare)
        }
        // the story, the replayed picker and the first-day scene all build their stages bare (compile-time wiring is the `bare:` argument)
        XCTAssertTrue(OpeningScript.characters.count == 4 && Set(OpeningScript.characters).count == 4)
    }
}
