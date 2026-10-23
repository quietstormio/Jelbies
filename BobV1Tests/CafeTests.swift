//
//  CafeTests.swift
//  The café outing: menu pricing and refusal, per-Jelbie needs / perks, the blocked states, the trip state machine, the swap in and out of the visiting room,
//  the mixed plate, the given-up refund, the room's floor and the bundled art. Rig: DiningJellyTests.Room (+ the per-step tickRace / tickCafe the stage adds).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CafeTests: XCTestCase {
    override func tearDown() {
        RoomLayout.apply(RoomCatalog.home)
        DecorField.shared.set([])
        DayClock.shared.forcedHour = 12
        super.tearDown()
    }

    private func room(count: Int = 3, drops: Int = 100) -> DiningJellyTests.Room {
        DayClock.shared.forcedHour = 12
        let r = DiningJellyTests.Room(count: count)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        r.care.bath.wallet.add(drops - r.care.bath.wallet.count, silent: true)
        step(r, 1)
        return r
    }
    /// One stage step: the rig's tick plus what MelonStage adds for the trips.
    private func step(_ r: DiningJellyTests.Room, _ s: Float, until: (() -> Bool)? = nil) {
        for _ in 0..<Int(s * 60) {
            r.tick()
            r.care.tickRace(r.actors, dt: 1.0 / 60)
            r.care.tickCafe(r.actors, dt: 1.0 / 60)
            r.care.tickDecor(dt: 1.0 / 60)
            if let until, until() { break }
        }
    }
    private func enter(_ r: DiningJellyTests.Room) {
        r.care.requestCafe()
        XCTAssertEqual(r.care.cafe.phase, .goOut)
        step(r, 6) { r.care.cafe.phase == .menu }
        XCTAssertEqual(r.care.cafe.phase, .menu)
    }
    private var mixed: CafeOrder { CafeOrder(picks: [0: .swirl, 1: .pancakes, 2: .sundae]) }

    // 1. menu

    func testMenuPricesAndTotals() {
        XCTAssertEqual(CafeMenu.treats.count, 4)
        XCTAssertEqual(CafeMenu.treats.map(\.price), [14, 15, 16, 18])
        XCTAssertEqual(CafeMenu.cheapest, 14)
        XCTAssertEqual(mixed.total(jellies: [0, 1, 2]), 14 + 16 + 18)
        let t = CafeOrder(forTable: .fizzmac)
        XCTAssertEqual(t.total(jellies: [0, 1, 2]), Int((Double(15 * 3) * 0.85).rounded(.down)))
        XCTAssertTrue(mixed.isComplete(jellies: [0, 1, 2]))
        XCTAssertFalse(CafeOrder(picks: [0: .swirl, 1: .sundae]).isComplete(jellies: [0, 1, 2]))
        XCTAssertTrue(t.isComplete(jellies: [0, 1, 2]))
        XCTAssertNil(CafeOrder.refusal(total: 20, wallet: 20))
        XCTAssertEqual(CafeOrder.refusal(total: 48, wallet: 20), "You need 28 more Drops. Races pay Drops!")
    }

    // 2/3. ordering

    func testOrderRefusedWhenShortOfDrops() {
        let r = room(drops: 100)
        enter(r)
        r.care.bath.wallet.add(20 - r.care.bath.wallet.count, silent: true)
        let big = CafeOrder(picks: [0: .sundae, 1: .sundae, 2: .sundae, ]); XCTAssertEqual(big.total(jellies: [0, 1, 2]), 54)
        let msg = r.care.orderCafe(big)
        XCTAssertEqual(msg, "You need 34 more Drops. Races pay Drops!")
        XCTAssertEqual(r.care.bath.wallet.count, 20)
        XCTAssertEqual(r.care.cafe.phase, .menu)
        XCTAssertNil(r.care.groupWanted)
    }

    func testOrderChargesExactlyOnce() {
        let r = room(drops: 100)
        enter(r)
        XCTAssertNil(r.care.orderCafe(mixed))
        XCTAssertEqual(r.care.bath.wallet.count, 100 - 48)
        XCTAssertEqual(r.care.cafe.phase, .eating)
        XCTAssertNil(r.care.orderCafe(mixed))
        XCTAssertEqual(r.care.bath.wallet.count, 100 - 48, "a second order is ignored")
    }

    // 4. blockers

    func testEntryBlockers() {
        let r = room(drops: 100)
        XCTAssertNil(r.care.cafeBlocker())
        DayClock.shared.forcedHour = 23; step(r, 0.1)
        XCTAssertEqual(r.care.cafeBlocker(), .night)
        DayClock.shared.forcedHour = 12; step(r, 0.1)
        r.care.bath.wallet.add(10 - r.care.bath.wallet.count, silent: true)
        XCTAssertEqual(r.care.cafeBlocker(), .noDrops)
        r.care.bath.wallet.add(90, silent: true)
        r.care.arranging = true
        XCTAssertEqual(r.care.cafeBlocker(), .arranging)
        r.care.arranging = false
        r.care.feed(); step(r, 0.2)
        XCTAssertEqual(r.care.cafeBlocker(), .meal)
        r.care.cancelGroup(); step(r, 3) { !r.care.trayOut && r.care.cafeBlocker() == nil }
        // a sleeper
        let b = r.actors[1].brain!
        b.idleForced = true; _ = b.idleStart(.sleep, r.actors[1].sim); b.sleep.hold = 500; b.sleep.holdForce = true
        step(r, 0.2)
        XCTAssertEqual(r.care.cafeBlocker(), .sleeping)
        b.idleForced = false; b.sleepWake(groggy: false, fast: true); step(r, 1)
        r.care.startRace(jelly: 0); step(r, 0.2)
        XCTAssertEqual(r.care.cafeBlocker(), .competition)
        r.care.requestCafe()
        XCTAssertEqual(r.care.cafe.phase, .off, "blocked: no fade")
        XCTAssertEqual(r.care.cafe.refusal, CafeBlock.competition.message)
    }

    func testRequestWhenClearStartsTheFade() {
        let r = room()
        XCTAssertNil(r.care.cafeBlocker())
        r.care.requestCafe()
        XCTAssertEqual(r.care.cafe.phase, .goOut)
        XCTAssertTrue(r.care.tripActive)
        XCTAssertEqual(r.care.cafeBlocker(), .busy)
    }

    // 5. state machine

    func testTripStateMachine() {
        let t = CafeTrip()
        var swaps: [CafeTrip.Dest] = []
        t.onSwap = { swaps.append($0) }
        t.begin()
        XCTAssertEqual(t.phase, .goOut)
        var last: Float = 0
        for _ in 0..<60 where t.phase == .goOut { t.step(dt: 1.0 / 60); XCTAssertGreaterThanOrEqual(t.wipe, last); last = t.wipe }
        XCTAssertEqual(swaps, [.cafe])
        XCTAssertEqual(t.phase, .arriveHold)
        for _ in 0..<CafeTuning.holdSteps { t.step(dt: 1.0 / 60) }
        XCTAssertEqual(t.phase, .arriveIn)
        for _ in 0..<60 { t.step(dt: 1.0 / 60) }
        XCTAssertEqual(t.phase, .menu)
        XCTAssertEqual(swaps, [.cafe], "one swap in")
        t.ordered(CafeOrder(forTable: .swirl)); XCTAssertEqual(t.phase, .eating)
        t.ordered(CafeOrder(forTable: .sundae)); t.goHome()
        XCTAssertEqual(t.phase, .eating, "goHome ignored while eating; ordered ignored outside the menu")
        t.servingEnded(); XCTAssertEqual(t.phase, .cheer)
        t.goHome(); XCTAssertEqual(t.phase, .cheer, "no leaving mid-cheer")
        for _ in 0..<(Int(CafeTuning.cheerSeconds * 60) + 2) { t.step(dt: 1.0 / 60) }
        XCTAssertEqual(t.phase, .done)
        t.goHome()
        for _ in 0..<200 { t.step(dt: 1.0 / 60) }
        XCTAssertEqual(t.phase, .off)
        XCTAssertEqual(swaps, [.cafe, .home])
        // blocked during the fade out: no swap at all
        swaps = []
        t.begin(); t.step(dt: 0.1); t.step(dt: 0.1, blocked: true)
        XCTAssertEqual(t.phase, .off); XCTAssertTrue(swaps.isEmpty); XCTAssertEqual(t.wipe, 0)
        // the menu's Head home
        t.begin(); for _ in 0..<400 where t.phase != .menu { t.step(dt: 1.0 / 60) }
        t.goHome(); for _ in 0..<200 { t.step(dt: 1.0 / 60) }
        XCTAssertEqual(t.phase, .off); XCTAssertEqual(swaps, [.cafe, .home])
    }

    // 6. the swap

    func testSwapEntersCafeAndRestoresHome() {
        let r = room()
        let c = r.care
        c.store.grant("decor-cushion"); XCTAssertNotNil(c.store.place("decor-cushion")); c.syncDecor()
        XCTAssertFalse(DecorField.shared.feet.isEmpty)
        for a in r.actors { a.brain!.autonomy = true }
        let homeRoom = c.store.currentRoom
        let before = r.actors.map(\.floor)
        enter(r)
        XCTAssertEqual(RoomLayout.current.id, .cafe)
        XCTAssertTrue(DecorField.shared.feet.isEmpty, "the room's furniture is away")
        XCTAssertTrue(c.tripActive)
        for a in r.actors { XCTAssertFalse(a.brain!.autonomy) }
        c.cafe.goHome()
        step(r, 6) { c.cafe.phase == .off }
        step(r, 2)          // past the leave hold
        for a in r.actors { XCTAssertTrue(a.brain!.autonomy, "wandering is restored at home") }
        XCTAssertEqual(c.cafe.phase, .off)
        XCTAssertEqual(RoomLayout.current.id, homeRoom)
        XCTAssertFalse(DecorField.shared.feet.isEmpty, "decor is back")
        XCTAssertEqual(c.store.currentRoom, homeRoom)
        for (i, a) in r.actors.enumerated() { XCTAssertLessThan(simd_distance(a.floor, before[i]), 1.6, "Jelbie \(i) is back near his spot") }
        XCTAssertFalse(c.tripActive)
    }

    // 7. each eats his own

    func testEachJelbieEatsHisOwnTreat() {
        let r = room(drops: 100)
        enter(r)
        let c = r.care
        for i in 0..<3 { c.needs(for: i).set(.hunger, 0.95); c.needs(for: i).set(.attention, 0.4) }
        let bag = StoreCatalog.items.map { c.store.count($0.id) }
        XCTAssertNil(c.orderCafe(mixed))
        step(r, 120) { c.cafe.phase == .cheer }
        XCTAssertEqual(c.cafe.phase, .cheer, "ate and cheered")
        let want: [PerkKind] = [.cozy, .fullBelly, .bouncy]
        for i in 0..<3 {
            XCTAssertEqual(c.cafeBook.ate[i], 3, "Jelbie \(i) ate the whole treat")
            let p = c.jelly(i)!.perks
            XCTAssertTrue(p.isActive(want[i]), "perk \(want[i]) for \(i)")
            XCTAssertGreaterThan(p.remaining(want[i]), want[i].duration + 1, "longer than the store's")
            XCTAssertGreaterThanOrEqual(r.level(i), 0.95)
            XCTAssertGreaterThanOrEqual(r.level(i, .attention), 0.7, "an outing is love")
        }
        XCTAssertEqual(StoreCatalog.items.map { c.store.count($0.id) }, bag, "the bag is untouched")
    }

    // 8. one Jelbie, the table treat

    func testForTableAndOneJelbie() {
        let r = room(count: 1, drops: 100)
        enter(r)
        let c = r.care
        XCTAssertNil(c.orderCafe(CafeOrder(forTable: .fizzmac)))
        XCTAssertEqual(c.bath.wallet.count, 100 - 12)
        step(r, 90) { c.cafe.phase == .cheer }
        XCTAssertEqual(c.cafeBook.ate[0], 3)
        XCTAssertTrue(c.zoomiesDue.contains(0))
        step(r, 8) { c.cafe.phase == .done }
        c.cafe.goHome()
        step(r, 20) { !c.zoomiesDue.contains(0) }
        XCTAssertFalse(c.zoomiesDue.contains(0), "the sugar rush fires at home")
    }

    func testForTableOneJelbieWithTheStagesGate() {
        let r = room(count: 1, drops: 100)
        r.stageGate = true
        enter(r)
        let c = r.care
        XCTAssertNil(c.orderCafe(CafeOrder(forTable: .fizzmac)))
        step(r, 90) { c.cafe.phase == .cheer }
        XCTAssertEqual(c.cafe.phase, .cheer, "the serving ran without tickOthers")
        XCTAssertEqual(c.cafeBook.ate[0], 3)
    }

    // 9. mixed plate

    func testMixedPlateBuildsPerPlaceMeshes() {
        let plate = CafePlate(order: mixed, serial: 1)
        plate.treatByPlace = [0: .swirl, 1: .pancakes, 2: .sundae]
        let f = plate.consumable()
        let a = DiningModels.heldPiece(f, index: 0, scale: 1), b = DiningModels.heldPiece(f, index: 3, scale: 1), c = DiningModels.heldPiece(f, index: 6, scale: 1)
        XCTAssertFalse(a.vertices.isEmpty)
        XCTAssertNotEqual(a.vertices.count, b.vertices.count)
        XCTAssertNotEqual(b.vertices.count, c.vertices.count)
        XCTAssertNotEqual(a.vertices.count, c.vertices.count)
        let layout = DiningLayout.make(n: 3)
        let g = DiningModels.trayGroup(layout: layout, serving: f, state: ServingState(n: 3, bitesLeft: [3, 3, 3]), theme: RoomTheme())
        XCTAssertGreaterThan(g.opaque.vertices.count, 500)
    }

    // 10. given up

    func testGivenUpServingRefunds() {
        let r = room(drops: 100)
        enter(r)
        let c = r.care
        XCTAssertNil(c.orderCafe(mixed))
        XCTAssertEqual(c.bath.wallet.count, 52)
        c.cancelGroup()
        step(r, 10) { c.cafe.phase == .cheer }
        XCTAssertEqual(c.cafe.phase, .cheer)
        XCTAssertEqual(c.bath.wallet.count, 100, "nobody ate a piece: the Drops come back")
    }

    // 11. the room's floor

    func testCafeDefKeepsTheFloor() {
        let d = RoomCatalog.cafe
        XCTAssertEqual(RoomCatalog.def(.cafe), d)
        XCTAssertFalse(RoomCatalog.all.contains { $0.id == .cafe })
        for b in d.allBoxes {
            XCTAssertGreaterThanOrEqual(b.centre.x - b.halfExtents.x, RoomLayout.minX); XCTAssertLessThanOrEqual(b.centre.x + b.halfExtents.x, RoomLayout.maxX)
            XCTAssertGreaterThanOrEqual(b.centre.z - b.halfExtents.z, RoomLayout.minZ)
            XCTAssertLessThanOrEqual(b.centre.z + b.halfExtents.z, -3.3, "front edge stays at the back")
        }
        RoomLayout.apply(d)
        for n in 1...3 {
            let L = DiningLayout.make(n: n)
            for aspect: Float in [603.0 / 1311.0, 1311.0 / 603.0] {
                XCTAssertTrue(DiningSpot.isClear(origin: DiningSpot.preferred, layout: L, of: SIMD2(99, 99), aspect: aspect), "tray n=\(n) aspect \(aspect) clear in the café")
            }
            for s in JellyRoster.spawnSpots(count: n) { XCTAssertGreaterThan(RoomLayout.sofaDistanceXZ(s), 0.3) }
        }
    }

    // 12. art

    func testCafeAssetsLoad() throws {
        guard let art = RoomArt.art("cafe") else { throw XCTSkip("room_cafe.bin is not bundled yet") }
        var tris = 0, verts = 0
        for p in art.parts { tris += p.indices.count / 3; verts += p.positions.count }
        XCTAssertLessThan(verts, 65536); XCTAssertLessThanOrEqual(tris, 15000)
        // everything below 1.2 stands inside a collider grown by 0.15, or within 0.6 of the back / side walls
        let d = RoomCatalog.cafe
        func covered(_ p: SIMD3<Float>) -> Bool {
            if p.z <= RoomLayout.minZ + 0.6 + 0.001 || abs(p.x) >= 4.4 { return true }
            for b in d.allBoxes where abs(p.x - b.centre.x) <= b.halfExtents.x + 0.15 && abs(p.z - b.centre.z) <= b.halfExtents.z + 0.15 { return true }
            for c in d.cylinders where simd_distance(SIMD2(p.x, p.z), c.centre) <= c.radius + 0.15 { return true }
            return false
        }
        var stray = 0
        for part in art.parts { for p in part.positions where p.y < 1.2 && !covered(p) { stray += 1 } }
        XCTAssertEqual(stray, 0, "floor-level art outside the colliders")
        for id in ["swirl", "pancakes", "sundae", "fizzmac"] { if let m = FoodMeshes.loaded[id] { XCTAssertLessThanOrEqual(m.triangles, 1500, id) } }
        for n in 1...3 {
            guard let m = FoodMeshes.loaded["cafetable_\(n)"] else { continue }
            XCTAssertLessThanOrEqual(m.triangles, 900)
            let L = DiningLayout.make(n: n)
            var hi: Float = -9
            for p in m.positions {
                XCTAssertLessThanOrEqual(abs(p.x), L.half.x + 0.01, "table \(n) x"); XCTAssertLessThanOrEqual(abs(p.z - L.trayCentreZ), L.half.y + 0.01, "table \(n) z")
                hi = max(hi, p.y)
            }
            XCTAssertEqual(hi, 0.25, accuracy: 0.015, "table \(n) top")
        }
    }
}
