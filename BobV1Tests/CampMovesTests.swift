//
//  CampMovesTests.swift
//  camp-yard-r1 Y5 / Y6: the yard's moves through the core's wrappers, against a suite: Bring home, the swap, Drop off, Say goodbye; the lists after each move and a simulated relaunch; the header count, the chips and the
//  Town square's sub-line follow; a goodbye leaves no body, chip or key behind; the room is rebuilt once after a net change and never after none.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CampMovesTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var suiteNames: [String] = []
    private var savedCurrent: [Int] = [], savedMap: [Int: Int] = [:], savedNames: [Int: String] = [:], savedBase: [String] = []
    private var savedSuspended = false
    private var spawned: [[Int]] = []

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
        GameCare.campDefaults = .standard; GameCare.campLeave = { _ = StartFlow.shared.campVisitEnded($0) }; GameCare.campSource = { GameCare.campCreatures() }
        CampBook.shared.spawn = nil; CampBook.shared.bodies = [:]; JellyRoster.visitBodies = [:]; CampUI.shared.reset(arrival: nil)
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
        for s in suiteNames { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suiteNames = []
    }
    private func suite() -> (UserDefaults, String) { let s = "CampMoves.\(UUID().uuidString)"; suiteNames.append(s); return (UserDefaults(suiteName: s)!, s) }
    private func seed(_ d: UserDefaults, home: [Int], camp: [Int], coins: Int = 500) {
        d.set(home, forKey: JellyRoster.rosterKey); d.set(camp, forKey: JellyCamp.key); d.set(coins, forKey: DropsWallet.key)
    }
    private func bodies(_ n: Int, firstID: Int) -> [JellyActor] {
        let sm = buildSimMesh(), rm = buildRenderMesh()
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let spots = JellyRoster.spawnSpots(count: max(n, 1))
        let out = (0..<n).map { i -> JellyActor in
            let a = JellyActor(id: firstID + i, name: "t\(i)", simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[i % spots.count])
            a.reset(drop: 0.35, shift: true)
            let b = BlobBrain.forGame(); b.attach(renderMesh: rm, synchronous: true); b.autonomy = true; b.steerID = firstID + i
            a.brain = b
            for _ in 0..<60 { a.sim.step() }
            b.currentPose(a.sim)
            return a
        }
        Self.keep += out
        return out
    }

    /// A GameCare with `home` at home and `camp` at Camp (in suite `d`), standing in the yard with the stage's spawn stubbed.
    private func inTheYard(_ d: UserDefaults, home: [Int], camp: [Int]) -> (GameCare, [JellyActor]) {
        seed(d, home: home, camp: camp)
        GameCare.campDefaults = d
        GameCare.campSource = { GameCare.campCreatures(d) }
        var leaves = 0
        GameCare.campLeave = { dd in if StartFlow.homeChanged(since: CampUI.shared.entryHome, dd) { leaves += 1 } }
        let care = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "CampMovesCare.\(UUID().uuidString)")!); Self.keep.append(care)
        care.wardrobe.body = WearBody.shared; care.features.body = WearBody.shared
        let homeBodies = bodies(3, firstID: 0)
        care.parkBook.roster = homeBodies
        CampBook.shared.spawn = { list, _ in self.spawned.append(list.map(\.id)); return self.bodies(list.count, firstID: 3) }
        care.parkBook.clear = {}
        care.park.beginCamp()
        run(care, homeBodies, until: .playing)
        return (care, homeBodies)
    }
    private func run(_ care: GameCare, _ home: [JellyActor], until phase: ParkTrip.Phase, max: Int = 4000) {
        var n = 0
        while care.park.phase != phase, n < max { care.tickPark(home, dt: 1.0 / 60); n += 1 }
        XCTAssertEqual(care.park.phase, phase)
    }
    private func relaunched(_ name: String) -> JellyCamp.Lists { JellyCamp.savedLists(UserDefaults(suiteName: name)!) }

    func testHeaderChipsAndTownSubLineFollowTheYard() {
        let (d, _) = suite()
        let (care, home) = inTheYard(d, home: [0, 1, 2], camp: [3, 4])
        XCTAssertEqual(CampUI.shared.members.map(\.id), [3, 4], "header count 2/6 and one chip each")
        XCTAssertEqual(CampUI.townSub(count: 0), "Nobody here yet"); XCTAssertEqual(CampUI.townSub(count: 2), "2 at Camp")
        XCTAssertEqual(CampUI.shared.members.map(\.name), [JellyRoster.nameOf(3), JellyRoster.nameOf(4)])
        _ = (care, home)
    }

    func testBringHomeWithRoomGoesStraightAndTheYardIsRebuilt() {
        let (d, name) = suite()
        let (care, home) = inTheYard(d, home: [0, 1], camp: [3, 4])
        care.campBringHomeTapped(3, defaults: d)
        XCTAssertEqual(care.park.phase, .refreshOut)
        let l = relaunched(name); XCTAssertEqual(l.home, [0, 1, 3]); XCTAssertEqual(l.camp, [4])
        run(care, home, until: .playing)
        XCTAssertEqual(spawned.last, [4], "the yard shows exactly the new Camp list"); XCTAssertEqual(CampUI.shared.members.map(\.id), [4])
        XCTAssertEqual(CampBook.shared.bodies.count, 1); XCTAssertEqual(care.parkBook.actors.count, 1)
        XCTAssertNil(CampUI.shared.selected)
    }

    func testBringHomeWithAFullHomeOpensTheSwapSheetFromTheSavedLists() {
        let (d, name) = suite()
        let (care, home) = inTheYard(d, home: [0, 1, 2], camp: [3])
        care.campBringHomeTapped(3, defaults: d)
        XCTAssertEqual(CampUI.shared.sheet, .swap(incoming: 3)); XCTAssertEqual(care.park.phase, .playing, "no wipe yet")
        XCTAssertEqual(relaunched(name).home, [0, 1, 2])
        care.campSwapConfirmed(incoming: 3, out: 1, defaults: d)
        let l = relaunched(name); XCTAssertEqual(l.home, [0, 3, 2], "the newcomer takes the slot"); XCTAssertEqual(l.camp, [1])
        run(care, home, until: .playing)
        XCTAssertEqual(CampUI.shared.members.map(\.id), [1]); XCTAssertEqual(CampUI.shared.sheet, .none)
    }

    func testDropOffAndItsRefusals() {
        let (d, name) = suite()
        let (care, home) = inTheYard(d, home: [0, 1], camp: [])
        care.campDropOffTapped(defaults: d)
        XCTAssertEqual(CampUI.shared.sheet, .dropOff)
        care.campDropOffConfirmed(1, defaults: d)
        let l = relaunched(name); XCTAssertEqual(l.home, [0]); XCTAssertEqual(l.camp, [1])
        run(care, home, until: .playing)
        XCTAssertEqual(CampUI.shared.members.map(\.id), [1])
        CampUI.shared.sheet = .none
        care.campDropOffTapped(defaults: d)          // one at home: refused with a line, no sheet
        XCTAssertEqual(CampUI.shared.sheet, .none); XCTAssertNotNil(care.park.toast)
        // Camp full
        let (d2, _) = suite()
        let (care2, _) = inTheYard(d2, home: [0, 1, 2], camp: [3, 4, 5, 6, 7, 8].filter { JellyRoster.isValid($0) })
        if JellyCamp.saved(d2).count == JellyCamp.cap { care2.campDropOffTapped(defaults: d2); XCTAssertEqual(CampUI.shared.sheet, .none, "Camp is full") }
    }

    func testGoodbyeKeepsTheLookUntilTheWhiteAndLeavesNothingBehind() {
        let (d, name) = suite()
        let (care, home) = inTheYard(d, home: [0, 1, 2], camp: [3, 4])
        let body = care.parkBook.actors[0]
        let copy = CampBook.shared.bodies[body.id]!
        XCTAssertEqual(copy.id, 3)
        care.campGoodbyeConfirmed(3, defaults: d)
        XCTAssertEqual(care.bath.wallet.count, 600, "the live wallet follows the core's +100, once")
        XCTAssertEqual(d.integer(forKey: DropsWallet.key), 600)
        XCTAssertNotNil(CampUI.shared.leaving)
        XCTAssertEqual(CampBook.shared.bodies[body.id]?.name, copy.name, "the body keeps its copied look through the wave")
        XCTAssertEqual(CampBook.shared.bodies[body.id]?.feature, copy.feature)
        var n = 0
        while care.park.phase == .playing, n < 2000 { care.tickPark(home, dt: 1.0 / 60); n += 1 }
        XCTAssertEqual(CampBook.shared.bodies[body.id]?.name, copy.name, "still the same copy while the wave and the walk run")
        run(care, home, until: .playing)
        XCTAssertEqual(relaunched(name).camp, [4]); XCTAssertEqual(CampUI.shared.members.map(\.id), [4])
        XCTAssertEqual(CampBook.shared.bodies.count, 1); XCTAssertEqual(care.parkBook.actors.count, 1)
        XCTAssertFalse(JellyRoster.visitBodies.values.contains(3), "no voice mapping left")
        XCTAssertEqual(care.bath.wallet.count, 600, "paid once")
        XCTAssertEqual(CampUI.shared.members.filter { $0.id == 3 }.count, 0, "no chip")
        XCTAssertEqual(UserDefaults(suiteName: name)!.integer(forKey: DropsWallet.key), 600)
    }

    func testRoomIsRebuiltOnceAfterANetChangeAndNeverAfterNone() {
        var rebuilds = 0
        let (d, _) = suite()
        let (care, home) = inTheYard(d, home: [0, 1], camp: [3, 4])
        GameCare.campLeave = { dd in if StartFlow.homeChanged(since: CampUI.shared.entryHome, dd) { rebuilds += 1 } }
        // a move and its undo count as no change
        care.campBringHomeTapped(3, defaults: d); run(care, home, until: .playing)
        care.campDropOffConfirmed(3, defaults: d); run(care, home, until: .playing)
        care.park.goHome(); run(care, home, until: .off)
        XCTAssertEqual(rebuilds, 0, "bring home then drop off again: nothing changed, nothing rebuilt")
        // a net change
        let (d2, _) = suite()
        let (care2, home2) = inTheYard(d2, home: [0, 1], camp: [3])
        GameCare.campLeave = { dd in if StartFlow.homeChanged(since: CampUI.shared.entryHome, dd) { rebuilds += 1 } }
        care2.campBringHomeTapped(3, defaults: d2); run(care2, home2, until: .playing)
        care2.park.goHome(); run(care2, home2, until: .off)
        XCTAssertEqual(rebuilds, 1, "one net change: the room is rebuilt exactly once")
        // no move at all
        let (d3, _) = suite()
        let (care3, home3) = inTheYard(d3, home: [0, 1], camp: [3])
        GameCare.campLeave = { dd in if StartFlow.homeChanged(since: CampUI.shared.entryHome, dd) { rebuilds += 1 } }
        care3.park.goHome(); run(care3, home3, until: .off)
        XCTAssertEqual(rebuilds, 1, "no move: no rebuild")
    }

    func testRefreshPhasesAreWhiteBothWaysAndOnlyInCamp() {
        let t = ParkTrip()
        var refreshes = 0, wipeAtRefresh: Float = 0
        t.onRefresh = { refreshes += 1; wipeAtRefresh = t.wipe }
        t.beginRefresh(); XCTAssertEqual(t.phase, .off, "not in a trip")
        t.beginCamp(); var n = 0
        while t.phase != .playing, n < 3000 { t.step(dt: 1.0 / 60); n += 1 }
        t.beginRefresh(); XCTAssertEqual(t.phase, .refreshOut); XCTAssertTrue(t.inScene)
        n = 0
        while t.phase != .playing, n < 3000 { t.step(dt: 1.0 / 60); n += 1 }
        XCTAssertEqual(refreshes, 1); XCTAssertEqual(wipeAtRefresh, 1, "created and destroyed only under an opaque white")
    }
}
