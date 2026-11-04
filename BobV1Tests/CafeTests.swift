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
        for j in r.care.jellies { r.care.needs(for: j.id).set(.hunger, 0.3) }          // hungry enough for food (a full Jelbie may only order a drink)
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
        XCTAssertEqual(CafeMenu.treats.count, 8)
        XCTAssertEqual(CafeMenu.treats.map(\.price), [14, 15, 16, 18, 8, 12, 11, 10])
        XCTAssertEqual(CafeMenu.drinks.map(\.id), [.latte, .cocoa, .juice])
        XCTAssertEqual(CafeMenu.foods.count, 5)
        XCTAssertEqual(CafeMenu.cheapest, 8)
        XCTAssertEqual(mixed.total(jellies: [0, 1, 2]), 14 + 16 + 18)
        let t = CafeOrder(forTable: .fizzmac)
        XCTAssertEqual(t.total(jellies: [0, 1, 2]), Int((Double(15 * 3) * 0.85).rounded(.down)))
        XCTAssertTrue(mixed.isComplete(jellies: [0, 1, 2]))
        XCTAssertFalse(CafeOrder(picks: [0: .swirl, 1: .sundae]).isComplete(jellies: [0, 1, 2]))
        XCTAssertTrue(t.isComplete(jellies: [0, 1, 2]))
        XCTAssertNil(CafeOrder.refusal(total: 20, wallet: 20))
        XCTAssertEqual(CafeOrder.refusal(total: 48, wallet: 20), "You need 28 more JellyCoins. Races pay JellyCoins!")
    }

    // 2/3. ordering

    func testOrderRefusedWhenShortOfDrops() {
        let r = room(drops: 100)
        enter(r)
        r.care.bath.wallet.add(20 - r.care.bath.wallet.count, silent: true)
        let big = CafeOrder(picks: [0: .sundae, 1: .sundae, 2: .sundae, ]); XCTAssertEqual(big.total(jellies: [0, 1, 2]), 54)
        let msg = r.care.orderCafe(big)
        XCTAssertEqual(msg, "You need 34 more JellyCoins. Races pay JellyCoins!")
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
        r.care.bath.wallet.add(7 - r.care.bath.wallet.count, silent: true)
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
        t.ordered(CafeOrder(forTable: .sundae))
        XCTAssertEqual(t.phase, .eating, "ordered is ignored outside the menu")
        t.servingEnded(); XCTAssertEqual(t.phase, .cheer)
        for _ in 0..<(Int(CafeTuning.cheerSeconds * 60) + 2) { t.step(dt: 1.0 / 60) }
        XCTAssertEqual(t.phase, .lounge, "after the cheer they stay at the table")
        for _ in 0..<(Int(CafeTuning.loungeSeconds * 60) + 2) { t.step(dt: 1.0 / 60) }
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
        for i in 0..<3 { c.needs(for: i).set(.hunger, 0.3); c.needs(for: i).set(.attention, 0.4) }
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
            XCTAssertGreaterThan(r.level(i), 0.3, "the treat filled him")
            XCTAssertGreaterThanOrEqual(r.level(i, .attention), 0.7, "an outing is love")
        }
        XCTAssertEqual(StoreCatalog.items.map { c.store.count($0.id) }, bag, "the bag is untouched")
    }

    /// The baby latte's burst starts during the serving, as soon as that drinker is done; the slower eaters are not interrupted, and the cheer skips the zoomer.
    func testLatteZoomiesStartWhileOthersStillEat() {
        let r = room(count: 3, drops: 100)
        enter(r)
        let c = r.care
        for i in 0..<3 { c.needs(for: i).set(.hunger, 0.3); c.needs(for: i).set(.attention, 0.4) }
        XCTAssertNil(c.orderCafe(CafeOrder(picks: [0: .latte, 1: .sundae, 2: .pancakes])))
        var zoomDuringEating = false
        step(r, 120) {
            if c.cafe.phase == .eating, r.actors[0].brain?.idleState.kind == .zoomies, c.group.isActive { zoomDuringEating = true }
            return c.cafe.phase == .cheer && c.cafeBook.zoomT.isEmpty
        }
        XCTAssertTrue(zoomDuringEating, "the latte drinker zoomed while the others were still at the table")
        XCTAssertTrue(c.cafeBook.zoomed.contains(0))
        XCTAssertNil(c.cafeBook.cheerIn[0], "a zoomer is not cheered again")
        step(r, 80) { c.cafe.phase == .lounge }
        XCTAssertEqual(c.cafe.phase, .lounge)
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
        step(r, 8) { c.cafe.phase == .lounge }
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

    // 13. the upgrade: hunger rule, drinks, special, stamps, diet, lounge, leaving, playlist

    func testFullJelbieMayOnlyOrderADrink() {
        let r = room(drops: 100)
        enter(r)
        let c = r.care
        c.needs(for: 0).set(.hunger, 0.95)
        XCTAssertFalse(c.cafeCanEat(0)); XCTAssertTrue(c.cafeCanEat(1))
        XCTAssertFalse(CafeRules.canOrder(.swirl, tier: .full)); XCTAssertTrue(CafeRules.canOrder(.cocoa, tier: .full)); XCTAssertTrue(CafeRules.canOrder(.latte, tier: .full))
        let msg = c.orderCafe(CafeOrder(picks: [0: .swirl, 1: .pancakes, 2: .sundae]))
        XCTAssertEqual(msg, "\(c.jelly(0)!.name)'s full. Pick a drink!")
        XCTAssertEqual(c.bath.wallet.count, 100, "nothing charged")
        XCTAssertEqual(c.cafe.phase, .menu)
        XCTAssertNil(c.orderCafe(CafeOrder(picks: [0: .juice, 1: .pancakes, 2: .sundae])))
        XCTAssertEqual(c.cafe.phase, .eating)
    }

    func testDrinkDoesNotFillHunger() {
        let r = room(drops: 100)
        enter(r)
        let c = r.care
        for i in 0..<3 { c.needs(for: i).set(.hunger, 0.3) }
        XCTAssertNil(c.orderCafe(CafeOrder(picks: [0: .cocoa, 1: .juice, 2: .swirl])))
        step(r, 120) { c.cafe.phase == .cheer }
        XCTAssertLessThan(r.level(0), 0.3 + 3 * CafeRules.drinkFillPerPiece + 0.02, "a drink is not a meal")
        XCTAssertLessThan(r.level(1), 0.3 + 3 * CafeRules.drinkFillPerPiece + 0.02)
        XCTAssertGreaterThan(r.level(2), 0.4, "the food filled him")
        XCTAssertTrue(c.jelly(0)!.perks.isActive(.cozy)); XCTAssertTrue(c.jelly(1)!.perks.isActive(.bouncy))
    }

    func testNobodyHungryStillOpensTheCafe() {
        let r = room(drops: 100)
        for j in r.care.jellies { r.care.needs(for: j.id).set(.hunger, 0.95) }
        XCTAssertTrue(r.care.cafeNobodyHungry)
        XCTAssertNil(r.care.cafeBlocker(), "the café still opens")
        r.care.needs(for: 1).set(.hunger, 0.2)
        XCTAssertFalse(r.care.cafeNobodyHungry)
    }

    func testDailySpecialFollowsTheShowTheme() {
        for theme in ShowTheme.allCases {
            let key = theme.main.condition
            let top = CafeMenu.treats.map { $0.condition[key] ?? 0 }.max() ?? 0
            for day in [20261101, 20261102, 20261103] {
                let sp = CafeMenu.special(theme: theme, dayKey: day)
                XCTAssertEqual(CafeMenu.treat(sp).condition[key] ?? 0, top, accuracy: 1e-5, "\(theme) special raises the theme's main stat")
                XCTAssertEqual(sp, CafeMenu.special(theme: theme, dayKey: day), "deterministic")
            }
        }
        XCTAssertEqual(CafeMenu.price(.sundae, special: .sundae), Int((18 * 0.8).rounded()))
        XCTAssertEqual(CafeMenu.price(.sundae, special: .swirl), 18)
        let o = CafeOrder(picks: [0: .sundae, 1: .swirl])
        XCTAssertEqual(o.total(jellies: [0, 1], special: .sundae), 14 + 14)
        XCTAssertEqual(o.fullPrice(jellies: [0, 1]), 32)
    }

    func testStampCardEighthOrderIsFree() {
        let r = room(drops: 500)
        let c = r.care
        XCTAssertEqual(c.cafe.stamps.card.count, 0)
        for visit in 1...7 {
            enter(r)
            let before = c.bath.wallet.count
            XCTAssertNil(c.orderCafe(CafeOrder(picks: [0: .jellycup, 1: .jellycup, 2: .jellycup])))
            XCTAssertEqual(c.cafe.stamps.card.count, visit)
            XCTAssertLessThan(c.bath.wallet.count, before)
            c.cafe.goHome(); step(r, 8) { c.cafe.phase == .off }; step(r, 2)
            for j in c.jellies { c.needs(for: j.id).set(.hunger, 0.3) }
        }
        XCTAssertTrue(c.cafe.stamps.isFull)
        enter(r)
        let before = c.bath.wallet.count
        XCTAssertNil(c.orderCafe(CafeOrder(picks: [0: .swirl, 1: .swirl, 2: .swirl])))
        XCTAssertEqual(c.bath.wallet.count, before, "the 8th order is free")
        XCTAssertTrue(c.cafe.wasFree)
        XCTAssertEqual(c.cafe.stamps.card.count, 0, "the card starts again")
    }

    func testFullCardBypassesNoDrops() {
        let r = room(drops: 100)
        r.care.bath.wallet.add(3 - r.care.bath.wallet.count, silent: true)
        XCTAssertEqual(r.care.cafeBlocker(), .noDrops)
        r.care.cafe.stamps.set(7)
        XCTAssertNil(r.care.cafeBlocker())
    }

    func testCafeFoodCountsTowardTheShowDiet() {
        let r = room(drops: 100)
        enter(r)
        let c = r.care
        let sweet0 = c.jelly(0)!.stats.condition(.sweet)
        XCTAssertNil(c.orderCafe(CafeOrder(picks: [0: .sundae, 1: .jellycup, 2: .swirl])))
        step(r, 120) { c.cafe.phase == .cheer }
        XCTAssertGreaterThan(c.jelly(0)!.stats.condition(.sweet), sweet0, "a café sundae raises the Sweet diet like the same food at home")
    }

    func testLoungeStaysAtTheTableAndLeavingCleansUp() {
        let r = room(drops: 100)
        enter(r)
        let c = r.care
        XCTAssertTrue(c.cafeBook.tableOut)
        XCTAssertTrue(c.dining.isPresent, "the table is out from the start")
        for a in r.actors { XCTAssertLessThan(simd_distance(a.floor, c.cafeBook.stands[a.id] ?? a.floor), 0.6, "already standing at the table") }
        XCTAssertNil(c.orderCafe(CafeOrder(picks: [0: .swirl, 1: .cocoa, 2: .juice])))
        step(r, 120) { c.cafe.phase == .lounge }
        XCTAssertEqual(c.cafe.phase, .lounge)
        XCTAssertTrue(c.dining.isPresent, "the table stays for the lounge")
        step(r, 8)
        for a in r.actors { XCTAssertLessThan(simd_distance(a.floor, c.cafeBook.stands[a.id] ?? a.floor), 0.9, "they stay at their own spot") }
        c.cafe.goHome(); step(r, 8) { c.cafe.phase == .off }; step(r, 2)
        XCTAssertFalse(c.dining.isPresent); XCTAssertFalse(c.cafeBook.tableOut)
    }

    func testLeavingMidMealRefundsWhenNothingWasEaten() {
        let r = room(drops: 100)
        enter(r)
        let c = r.care
        XCTAssertNil(c.orderCafe(CafeOrder(picks: [0: .swirl, 1: .swirl, 2: .swirl])))
        XCTAssertEqual(c.cafe.phase, .eating)
        c.cafe.goHome()
        step(r, 8) { c.cafe.phase == .off }; step(r, 2)
        XCTAssertEqual(c.bath.wallet.count, 100, "nothing eaten: refunded")
        XCTAssertFalse(c.dining.isPresent); XCTAssertFalse(c.groupActive); XCTAssertEqual(RoomLayout.current.id, c.store.currentRoom)
    }

    func testCafePlaylistAdvancesAndSkipsOnlyInTheCafe() {
        var rnd = 0.0
        var d = MusicDirector(length: { _ in 90 }, rand: { rnd += 0.37; return rnd.truncatingRemainder(dividingBy: 1) })
        var input = MusicInput(); input.scene = .none
        _ = d.update(dt: 1, input: input)
        XCTAssertFalse(d.skip().isEmpty, "skip works at home")
        input.scene = .cafe
        var ev = d.update(dt: 1, input: input)
        guard case .sceneOn(let first, _)? = ev.first(where: { if case .sceneOn = $0 { return true } else { return false } }) else { return XCTFail("the café starts a track") }
        XCTAssertTrue(CafeMusic.tracks.map(\.track).contains(first))
        var seen = [first]
        for _ in 0..<(CafeMusic.tracks.count - 1) {
            for _ in 0..<2 { _ = d.update(dt: 1, input: input) }          // (the skip interval)
            ev = d.skip()
            guard case .sceneOn(let t, _)? = ev.first else { return XCTFail("skip in the café plays the next café track") }
            XCTAssertFalse(seen.contains(t), "no repeat until the list is through")
            seen.append(t)
        }
        XCTAssertEqual(Set(seen).count, CafeMusic.tracks.count)
        // it advances by itself at the end of the track
        let len = d.sceneTrack!.loopEnd
        var advanced = false
        for _ in 0..<(Int(len) + 5) { if d.update(dt: 1, input: input).contains(where: { if case .sceneOn = $0 { return true } else { return false } }) { advanced = true; break } }
        XCTAssertTrue(advanced, "the playlist advances at the end of a track")
        XCTAssertEqual(NowPlaying.make(muted: false, musicOn: true, musicVolume: 1, otherAudioPlaying: false, mode: .day, scene: .cafe, current: nil, inGap: false, layerOn: false, sceneTrack: .cafe1).line, "Café · Morning Latte")
        input.scene = .race
        _ = d.update(dt: 1, input: input); _ = d.update(dt: 1, input: input)
        XCTAssertTrue(d.skip().isEmpty, "other screens keep their own music")
    }

    func testDrinkMeshesAndPlaylistFilesAreBundled() {
        for t in [CafeTreatID.cocoa, .juice] {
            let m = DiningModels.heldPiece(Consumables.cafeFood(t), index: 0, scale: 1)
            XCTAssertFalse(m.vertices.isEmpty, "\(t)")
        }
        XCTAssertEqual(CafeMusic.tracks.count, 8)
        for t in CafeMusic.tracks {
            guard let len = SceneRender.fileLength(t.track) else { XCTFail("\(t.track) is not bundled"); continue }
            XCTAssertGreaterThan(t.track.loopEndFrame, t.track.loopStartFrame, "\(t.track) loops a real span")
            XCTAssertLessThanOrEqual(t.track.loopEndFrame, len, "\(t.track): the loop ends inside the file")
            XCTAssertNotNil(SceneRender.render(t.track), "\(t.track) decodes to a playable loop")
            XCTAssertTrue(MusicScene.cafe.tracks.contains(t.track))
        }
    }

    /// Everybody finishes his own treat at the preset table (nobody is left with food on the plate), over several visits.
    func testEveryoneFinishesAtThePresetTable() {
        for visit in 0..<4 {
            let r = room(drops: 500)
            enter(r)
            let c = r.care
            XCTAssertNil(c.orderCafe(CafeOrder(picks: [0: .juice, 1: .cocoa, 2: .pancakes])), "visit \(visit)")
            step(r, 120) { c.cafe.phase == .cheer }
            XCTAssertFalse(c.group.gaveUp, "visit \(visit): the sitting was not given up (the table spot must be reachable: stands in front of the sofa collider)")
            for i in 0..<3 { XCTAssertEqual(c.cafeBook.ate[i], 3, "visit \(visit): Jelbie \(i) ate his whole treat") }
        }
    }

    func testNoMoreThanFiveJelbiesOnScreen() {
        XCTAssertEqual(CafeTuning.maxBodies, 5)
        XCTAssertEqual(CafeTuning.regularCount(owned: 3, want: 2), 2)
        XCTAssertEqual(CafeTuning.regularCount(owned: 3, want: 9), 2, "never more than two regulars")
        XCTAssertEqual(CafeTuning.regularCount(owned: 4, want: 2), 1)
        XCTAssertEqual(CafeTuning.regularCount(owned: 5, want: 2), 0)
        XCTAssertEqual(CafeTuning.regularCount(owned: 1, want: 2), 2)
        for owned in 1...6 { XCTAssertLessThanOrEqual(owned + CafeTuning.regularCount(owned: owned, want: 2), max(owned, CafeTuning.maxBodies)) }
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
