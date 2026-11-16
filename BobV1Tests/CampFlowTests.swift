//
//  CampFlowTests.swift
//  The Camp phase of the start flow, against own UserDefaults suites: a purchase with a full home goes to Camp (no arrival, coins untouched here), the moves between home and
//  Camp, a relaunch from the same defaults, the id collision end to end, and what the room / widget / Siri / voice may see (only the three at home).
//

import XCTest
@testable import BobV1

@MainActor
final class CampFlowTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var suites: [String] = []
    private var savedCurrent: [Int] = []
    private var savedMap: [Int: Int] = [:]
    private var savedNames: [Int: String] = [:]
    private var savedBase: [String] = []
    private var savedSuspended = false
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        savedCurrent = JellyRoster.current; savedMap = JellyRoster.speciesMap; savedNames = JellyRoster.extraNames; savedBase = JellyRoster.names
        savedSuspended = JellyRoster.setRosterSuspended
        JellyRoster.speciesMap = [:]; JellyRoster.extraNames = [:]
        GameCare.newcomerPending = false; GameCare.newcomerWithOthers = false
    }
    override func tearDown() {
        JellyRoster.current = savedCurrent; JellyRoster.speciesMap = savedMap; JellyRoster.extraNames = savedNames; JellyRoster.names = savedBase
        JellyRoster.setRosterSuspended = savedSuspended
        GameCare.newcomerPending = false; GameCare.newcomerWithOthers = false
        JellyVariants.reload(); JellyVariants.clearPreviews(); JellyTraitsBook.reload()
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
    }
    private func suite() -> UserDefaults {
        let s = "CampFlowTests.\(UUID().uuidString)"; suites.append(s)
        return UserDefaults(suiteName: s)!
    }
    private func seed(_ d: UserDefaults, home: [Int], camp: [Int]) { d.set(home, forKey: JellyRoster.rosterKey); d.set(camp, forKey: JellyCamp.key) }
    private func traits(_ s: Int) -> JellyTraits? { JellyCandidates.make(species: s, dayKey: 3, classic: true, owned: 0).first?.traits }

    // MARK: buying

    func testBuyWithFullHomeGoesToCampAndNobodyArrives() {
        let d = suite()
        seed(d, home: [0, 1, 2], camp: [])
        GameRouter.shared.request(.jelly(1))
        let flow = StartFlow(); flow.phase = .adopt(.more)
        flow.bringHome(species: 4, name: "Biscuit", traits: traits(4), defaults: d)
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 1, 2], "home is unchanged")
        XCTAssertEqual(JellyCamp.saved(d), [4], "Teddy is at Camp")
        XCTAssertEqual(flow.phase, .game, "back to the room, as adoption does (there is no Camp phase)")
        XCTAssertEqual(flow.campArrival, 4, "the room may say who is waiting at Camp")
        XCTAssertFalse(GameCare.newcomerPending, "no arrival: it would welcome the last home creature"); XCTAssertFalse(GameCare.newcomerWithOthers)
        XCTAssertNil(flow.welcome)
        XCTAssertTrue(GameRouter.shared.pending.isEmpty, "slot-numbered routes are cleared")
        XCTAssertEqual(JellyRoster.nameOf(4), "Biscuit", "name saved")
        XCTAssertTrue(d.bool(forKey: StartFlow.startedKey))
    }
    func testBuyWithBobAtCampGetsAFreshIdAndCampBobKeepsEverything() {
        let d = suite()
        seed(d, home: [1, 2, 3], camp: [0])
        JellyRoster.setName(0, "Old Bob", d)
        d.set(["levels": [0.25, 0.5, 0.75], "time": t0.timeIntervalSince1970, "asleep": false] as [String: Any], forKey: JellyKeys.needs(0))
        d.set([1.0, 0.5, 3.0, 2.0], forKey: JellyKeys.stats(0))
        d.set(Data("grime".utf8), forKey: JellyKeys.grime(0))
        let bobVariant = JellyVariants.adopted(0)
        let flow = StartFlow(); flow.phase = .adopt(.more)
        flow.bringHome(species: 0, name: "Newblue", traits: traits(0), defaults: d)
        guard let id = flow.campArrival else { return XCTFail("not at Camp") }
        XCTAssertEqual(id, 100, "a fresh id, not Bob's 0")
        XCTAssertEqual(JellyCamp.saved(d), [0, 100])
        XCTAssertEqual(JellyRoster.nameOf(0), "Old Bob"); XCTAssertEqual(JellyRoster.nameOf(100), "Newblue")
        XCTAssertEqual(d.dictionary(forKey: JellyKeys.needs(0))?["levels"] as? [Double], [0.25, 0.5, 0.75], "Camp Bob's needs untouched")
        XCTAssertEqual(d.array(forKey: JellyKeys.stats(0)) as? [Double], [1.0, 0.5, 3.0, 2.0], "stats untouched")
        XCTAssertEqual(d.data(forKey: JellyKeys.grime(0)), Data("grime".utf8), "dirt untouched")
        XCTAssertEqual(JellyVariants.adopted(0), bobVariant, "colour untouched")
        XCTAssertNil(d.object(forKey: JellyKeys.needs(100)), "the new one starts clean")
    }
    func testCampBobWardrobeAndTraitsSurviveBuyingABlue() {
        let d = suite()
        seed(d, home: [1, 2, 3], camp: [0])
        let slot = WearSlot.allCases[0]
        guard let look = WearLook.allCases.first(where: { $0.slot == slot }) else { return XCTFail("no look") }
        var store = StoreBook.Saved(); store.worn["0"] = [slot.rawValue: look.rawValue]
        d.set(try? JSONEncoder().encode(store), forKey: StoreBook.key)
        let bobTraits = traits(0); JellyTraitsBook.adopt(0, bobTraits, d)
        let flow = StartFlow(); flow.phase = .adopt(.more)
        flow.bringHome(species: 0, name: "Twin", traits: JellyCandidates.make(species: 0, dayKey: 9, classic: false, owned: 1).first?.traits, defaults: d)
        XCTAssertEqual(JellyTraitsBook.record(0), bobTraits, "personality untouched")
        XCTAssertEqual(JellyCamp.members(d).first?.worn[slot], look, "wardrobe untouched, and the yard reads it")
        XCTAssertEqual(JellyCamp.members(d).map(\.id), [0, 100])
    }
    func testTheVisitHookSaysWhetherHomeChangedAndRebuildsOnce() {
        let d = suite()
        seed(d, home: [0, 1, 2], camp: [4, 5])
        let flow = StartFlow(); flow.phase = .menu
        flow.campVisitBegan(d)
        XCTAssertFalse(StartFlow.homeChanged(since: JellyRoster.savedIDs(d), d))
        let s0 = flow.session
        XCTAssertFalse(flow.campVisitEnded(d), "no move: no rebuild"); XCTAssertEqual(flow.session, s0)
        flow.campVisitBegan(d)
        XCTAssertTrue(flow.campSwap(in: 4, out: 1, now: t0, defaults: d))
        XCTAssertTrue(flow.campVisitEnded(d), "home changed"); XCTAssertEqual(flow.session, s0 + 1, "rebuilt exactly once")
        XCTAssertFalse(flow.campVisitEnded(d), "the entry is forgotten: a second call rebuilds nothing"); XCTAssertEqual(flow.session, s0 + 1)
        flow.campVisitBegan(d)
        XCTAssertTrue(flow.campSendToCamp(0, now: t0, defaults: d))          // drop off
        XCTAssertTrue(flow.campVisitEnded(d)); XCTAssertEqual(flow.session, s0 + 2)
        flow.campVisitBegan(d)
        XCTAssertTrue(flow.campSwap(in: 1, out: 4, now: t0, defaults: d)); XCTAssertTrue(flow.campSwap(in: 4, out: 1, now: t0, defaults: d))
        XCTAssertFalse(flow.campVisitEnded(d), "moved and moved back: the home list is the same, no rebuild"); XCTAssertEqual(flow.session, s0 + 2)
    }
    func testSayGoodbyeFromTheYardClearsRoutesAndPaysOnce() {
        let d = suite(); seed(d, home: [0, 1], camp: [4]); d.set(10, forKey: DropsWallet.key)
        let flow = StartFlow(); GameRouter.shared.request(.jelly(1))
        XCTAssertTrue(flow.campSayGoodbye(4, defaults: d))
        XCTAssertFalse(flow.campSayGoodbye(4, defaults: d))
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 10 + JellyCamp.thankYouCoins)
        XCTAssertTrue(GameRouter.shared.pending.isEmpty)
        XCTAssertEqual(JellyCamp.saved(d), [])
    }
    func testNoCampCreatureHasAProfileOrIsSavedByTheYardData() {
        let d = suite(); seed(d, home: [0, 1], camp: [4])
        let before = d.dictionaryRepresentation().mapValues { "\($0)" }
        let members = JellyCamp.members(d); let profiles = JellyCamp.profiles(d)
        XCTAssertEqual(members.map(\.id), [4]); XCTAssertEqual(profiles.map(\.character), [4])
        XCTAssertEqual(d.dictionaryRepresentation().mapValues { "\($0)" }, before, "reading the yard's data writes nothing")
        Self.keep += profiles.map { $0 as AnyObject }
    }

    /// From the Jelly Spring's own entry points (AdoptionCenter.pay + StartFlow.bringHome) down to the save, home full.
    func testSpringPurchaseIntoCampSpendsOnceAndLeavesHomeAlone() {
        let d = suite()
        seed(d, home: [0, 1, 2], camp: [4])
        let wallet = DropsWallet(persists: false); wallet.add(10_000, silent: true)
        let price = AdoptionPrice.next(home: 3, camp: 1)
        XCTAssertEqual(price, 800)
        XCTAssertTrue(SpringStates.townEnabled(home: 3, camp: 1), "the Town card is open")
        XCTAssertTrue(AdoptionCenter.pay(price!, wallet: wallet, defaults: d))
        XCTAssertEqual(wallet.count, 10_000 - 800, "coins spent once")
        let flow = StartFlow(); flow.phase = .adopt(.more)
        flow.bringHome(species: 0, name: "Spring Bob", traits: traits(0), defaults: d)
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 1, 2], "home untouched")
        XCTAssertEqual(JellyCamp.saved(d), [4, 100], "at Camp with a fresh id (Bob is at home, so 100)")
        XCTAssertEqual(wallet.count, 9_200, "bringHome takes no coins")
        XCTAssertEqual(flow.campNote, "Spring Bob is at Jelmiko Camp"); XCTAssertEqual(flow.campArrival, 100)
        XCTAssertFalse(GameCare.newcomerPending)
    }
    func testSpringPurchaseWithHomeAndCampFullSpendsNothing() {
        let d = suite()
        let ids = (0..<7).map { $0 } + [JellyRoster.allocateInstance(species: 0, roster: [0], d), JellyRoster.allocateInstance(species: 1, roster: [1], d)]
        seed(d, home: Array(ids.prefix(3)), camp: Array(ids.dropFirst(3).prefix(JellyCamp.cap)))
        let wallet = DropsWallet(persists: false); wallet.add(10_000, silent: true)
        XCTAssertNil(AdoptionPrice.next(home: 3, camp: JellyCamp.cap))
        XCTAssertFalse(SpringStates.townEnabled(home: 3, camp: JellyCamp.cap))
        XCTAssertFalse(AdoptionCenter.pay(800, wallet: wallet, defaults: d), "even a stale caller cannot take coins")
        XCTAssertEqual(wallet.count, 10_000)
    }
    func testSpringPurchaseWithRoomAtHomeIsTodaysFlow() {
        let d = suite(); seed(d, home: [0, 1], camp: [])
        let wallet = DropsWallet(persists: false); wallet.add(1000, silent: true)
        XCTAssertTrue(AdoptionCenter.pay(AdoptionPrice.next(home: 2, camp: 0)!, wallet: wallet, defaults: d))
        XCTAssertEqual(wallet.count, 200)
        XCTAssertEqual(StartFlow.placeNew(species: 2, name: "Moss", variant: nil, traits: nil, first: false, d)?.destination, .home)
    }

    func testBuyingWhenBothAreFullChangesNothing() {
        let d = suite()
        let ids = (0..<7).map { $0 } + [JellyRoster.allocateInstance(species: 0, roster: [0], d), JellyRoster.allocateInstance(species: 1, roster: [1], d)]
        seed(d, home: Array(ids.prefix(3)), camp: Array(ids.dropFirst(3).prefix(JellyCamp.cap)))
        XCTAssertNil(StartFlow.placeNew(species: 2, name: "X", variant: nil, traits: nil, first: false, d), "full: nothing placed, so nothing may be paid")
        XCTAssertEqual(JellyCamp.saved(d).count, JellyCamp.cap)
        let flow = StartFlow(); flow.phase = .adopt(.more)
        XCTAssertEqual(JellyCamp.destination(home: 3, camp: JellyCamp.cap), .full)
        XCTAssertNil(AdoptionPrice.next(home: 3, camp: JellyCamp.cap), "the picker shows no price, so the spend is never reached")
    }
    func testBuyingWithRoomAtHomeIsUnchanged() {
        let d = suite()
        seed(d, home: [0, 1], camp: [])
        let p = StartFlow.placeNew(species: 2, name: "Moss", variant: nil, traits: nil, first: false, d)
        XCTAssertEqual(p, StartFlow.Placement(id: 2, destination: .home))
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 1, 2]); XCTAssertEqual(JellyCamp.saved(d), [])
    }

    // MARK: moves

    func testBringHomeFromCampRestampsAndAppendsToTheEnd() {
        let d = suite()
        seed(d, home: [0, 1], camp: [3, 4])
        d.set(["levels": [0.5, 0.5, 0.5], "time": t0.timeIntervalSince1970, "asleep": true] as [String: Any], forKey: JellyKeys.needs(3))
        let now = t0.addingTimeInterval(20 * 86400)
        XCTAssertTrue(StartFlow.campMove(.bringHome(3), now: now, d))
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 1, 3]); XCTAssertEqual(JellyCamp.saved(d), [4])
        XCTAssertEqual(d.dictionary(forKey: JellyKeys.needs(3))?["time"] as? Double, now.timeIntervalSince1970, "stamps are now")
        XCTAssertFalse(StartFlow.campMove(.bringHome(4), now: now, d), "home is full: refused")
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 1, 3]); XCTAssertEqual(JellyCamp.saved(d), [4], "and nothing changed")
    }
    func testRefusedMoveDoesNotRestamp() {
        let d = suite()
        seed(d, home: [0, 1, 2], camp: [3])
        d.set(["levels": [0.5, 0.5, 0.5], "time": t0.timeIntervalSince1970, "asleep": false] as [String: Any], forKey: JellyKeys.needs(3))
        XCTAssertFalse(StartFlow.campMove(.bringHome(3), now: t0.addingTimeInterval(9999), d))
        XCTAssertEqual(d.dictionary(forKey: JellyKeys.needs(3))?["time"] as? Double, t0.timeIntervalSince1970)
    }
    func testSwapKeepsTheOtherSlotsAndSendToCampIsRefusedAtOne() {
        let d = suite()
        seed(d, home: [0, 1, 2], camp: [4, 5])
        XCTAssertTrue(StartFlow.campMove(.swap(in: 4, out: 1), now: t0, d))
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 4, 2]); XCTAssertEqual(JellyCamp.saved(d), [1, 5])
        seed(d, home: [5], camp: [1])
        XCTAssertFalse(StartFlow.campMove(.sendToCamp(5), now: t0, d), "nobody can be sent away when only one is home")
        XCTAssertEqual(JellyRoster.savedIDs(d), [5]); XCTAssertEqual(JellyCamp.saved(d), [1])
        XCTAssertNil(d.object(forKey: "BlobRoster.v1.other"))
    }
    func testLiveFlowMovesClearPendingRoutesAndKeepTheNewcomerFlagsOff() {
        let d = suite()
        let flow = StartFlow()
        let moves: [(String, () -> Bool)] = [
            ("send", { flow.campSendToCamp(1, now: self.t0, defaults: d) }),
            ("bring home", { flow.campBringHome(1, now: self.t0, defaults: d) }),
            ("swap", { flow.campSwap(in: 3, out: 1, now: self.t0, defaults: d) })]
        seed(d, home: [0, 1, 2], camp: [3])
        for (name, move) in moves {
            JellyRoster.setRosterSuspended = false
            GameRouter.shared.request(.jelly(2)); GameCare.newcomerPending = true; GameCare.newcomerWithOthers = true; flow.welcome = "x"
            seed(d, home: name == "bring home" ? [0, 2] : [0, 1, 2], camp: name == "bring home" ? [1] : [3])
            XCTAssertTrue(move(), name)
            XCTAssertTrue(GameRouter.shared.pending.isEmpty, "\(name): pending route cleared")
            XCTAssertFalse(GameCare.newcomerPending, name); XCTAssertFalse(GameCare.newcomerWithOthers, name)
            XCTAssertNil(flow.welcome, name)
            XCTAssertTrue(JellyRoster.setRosterSuspended, "\(name): a dev -SetRoster must not put the old list back")
            XCTAssertNotEqual(flow.phase, .game, "no room is touched: the flow stays where it is until Home")
        }
        XCTAssertEqual(JellyRoster.savedIDs(d), [0, 3, 2], "the swap put the incoming one in slot 1")
        XCTAssertFalse(flow.campSendToCamp(77, now: t0, defaults: d), "a refused move changes nothing")
    }
    func testThePurchaseGuardReadsTheSave() {
        let d = suite()
        XCTAssertTrue(StartFlow.canPlaceNew(d))
        let ids = (0..<7).map { $0 } + [JellyRoster.allocateInstance(species: 0, roster: [0], d), JellyRoster.allocateInstance(species: 1, roster: [1], d)]
        seed(d, home: Array(ids.prefix(3)), camp: Array(ids.dropFirst(3).prefix(JellyCamp.cap - 1)))
        XCTAssertTrue(StartFlow.canPlaceNew(d), "one place left at Camp")
        seed(d, home: Array(ids.prefix(3)), camp: Array(ids.dropFirst(3).prefix(JellyCamp.cap)))
        XCTAssertFalse(StartFlow.canPlaceNew(d), "full: AdoptionCenter.bringHome returns before wallet.spend")
    }
    func testRelaunchReadsBackTheMovedListsAndPositionBoundThingsBelongToTheRightCreature() {
        let d = suite()
        seed(d, home: [0, 1, 2], camp: [4])
        XCTAssertTrue(StartFlow.campMove(.swap(in: 4, out: 1), now: t0, d))
        // "relaunch": everything is read again from the same defaults
        XCTAssertEqual(JellyRoster.launchIDs(d), [0, 4, 2], "Teddy is in Pip's old spot")
        XCTAssertEqual(JellyCamp.saved(d), [1])
        let care = GameCare(roster: JellyRoster.launchIDs(d), persistent: false, defaults: d); Self.keep.append(care)
        XCTAssertEqual(care.jellies.map(\.character), [0, 4, 2]); XCTAssertEqual(care.jellies.map(\.id), [0, 1, 2])
        XCTAssertEqual(care.jellies.map(\.name), ["Bob", "Teddy", "Moss"])
        let ins = care.widgetInputs()
        XCTAssertEqual(ins.map(\.id), [0, 1, 2]); XCTAssertEqual(ins.map(\.color), ["blue", "teddy", "green"], "widget slots hold the new three")
        XCTAssertEqual(ins.map(\.character), [0, 4, 2])
        XCTAssertEqual(care.jellyColorKeys, ["blue", "teddy", "green"])
        XCTAssertEqual(care.store.characterOf(1), 4, "outfits are looked up by the creature in the slot")
        XCTAssertEqual(care.store.characterOf(0), 0); XCTAssertEqual(care.store.characterOf(2), 2)
        XCTAssertEqual(care.store.rosterCharacters(), [0, 4, 2])
        JellyRoster.current = [0, 4, 2]
        XCTAssertEqual(JellyRoster.slot(ofCharacter: 4), 1); XCTAssertNil(JellyRoster.slot(ofCharacter: 1), "Pip is at Camp: not in the room")
        let names = JellyNames(defaults: d, key: "nick", persists: false)
        XCTAssertEqual(names.id(ofCharacter: 4), 1, "voice: Teddy answers in slot 1")
        XCTAssertEqual(names.id(ofCharacter: 1), JellyNames.absentID(1), "voice: Pip is at Camp = 'not here'")
    }

    // MARK: only the three at home are seen

    func testRoomWidgetSiriAndVoiceNeverSeeACampCreature() throws {
        let d = suite()
        seed(d, home: [0, 1, 2], camp: [4, 3])
        JellyRoster.setName(4, "Camper", d)
        JellyRoster.current = JellyRoster.launchIDs(d)
        XCTAssertEqual(JellyRoster.current, [0, 1, 2])
        // the room
        let care = GameCare(roster: JellyRoster.launchIDs(d), persistent: false, defaults: d); Self.keep.append(care)
        XCTAssertEqual(care.jellies.count, 3); XCTAssertFalse(care.roster.contains(4)); XCTAssertFalse(care.roster.contains(3))
        // the widget snapshot writer + the Siri entities read from what it wrote
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("camp-widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bridge = WidgetBridge(directory: dir, now: { self.t0 }, rendersPortraits: false, reload: {}); Self.keep.append(bridge)
        bridge.publish(care.widgetInputs(), force: true, render: false)
        let snap = JellySnapshot.read(from: dir)
        XCTAssertEqual(snap?.jellies.map(\.name), ["Bob", "Pip", "Moss"])
        let entities = JelbieRoster.current(directory: dir)
        XCTAssertEqual(entities.map(\.name), ["Bob", "Pip", "Moss"], "Siri / Shortcuts offer only the three at home")
        XCTAssertFalse(entities.contains { $0.name == "Camper" })
        // the voice name list
        XCTAssertEqual(JellyRoster.currentNames, ["Bob", "Pip", "Moss"])
        let names = JellyNames(defaults: d, key: "nick", persists: false)
        let hit = names.resolve(tokens: ["teddy"]).first
        XCTAssertEqual(hit?.id, JellyNames.absentID(4), "a Camp creature's name gets the existing 'not here'")
        XCTAssertNil(care.jelly(hit?.id ?? 0), "and no profile answers to it")
    }

    func testWidgetPortraitOfASlotIsStaleAfterASwap() {
        let a = WidgetBridge.Input(id: 1, name: "Pip", color: "yellow", levels: [1, 1, 1], dirt: 0, sparkle: 0, character: 1)
        let b = WidgetBridge.Input(id: 1, name: "Teddy", color: "teddy", levels: [1, 1, 1], dirt: 0, sparkle: 0, character: 4)
        XCTAssertNotEqual(WidgetBridge.lookKey(a), WidgetBridge.lookKey(b), "slot 1's picture is re-rendered")
    }
}
