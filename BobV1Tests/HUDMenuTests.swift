//
//  HUDMenuTests.swift
//  The one main HUD control: group controls with nobody highlighted, individual controls with a Jelbie highlighted, the routes of each row,
//  and a highlight never waking a sleeper.
//

import XCTest
import simd
import SwiftUI
@testable import BobV1

@MainActor
final class HUDMenuTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func care3() -> GameCare {
        let c = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "HUDMenu.3")!)
        Self.keep.append(c)
        return c
    }
    private func tickSelect(_ care: GameCare, _ sec: Float) { for _ in 0..<Int(sec * 60) { care.select.tick(dt: 1.0 / 60) } }
    private func room() -> FocusAnyRun { let r = FocusAnyRun(peers: true); Self.keep.append(r); r.run(1.0); r.care.tickRace(r.actors, dt: 1.0 / 60); return r }          // (the stage's tickRace registers the bodies for selectBrain)

    func testRoomsLiveInTheBagAndTheRailHasNoRoomsButton() {
        XCTAssertTrue(BagSheet.BagTab.allCases.contains(.rooms), "owned rooms are a Bag category")
        XCTAssertEqual(BagSheet.BagTab.rooms.rawValue, "Rooms")
        let care = care3()
        XCTAssertTrue(care.store.ownsRoom(.home), "the home room is always in the Bag's Rooms")
        XCTAssertEqual(HUDMenu.items(.group).count, 6)          // (the paw's menu is unchanged; Go out is a rail button that opens the Town)
    }

    func testGroupModeWhenNothingHighlighted() {
        let care = care3()
        XCTAssertEqual(HUDMenu.mode(care), .group)
        XCTAssertEqual(HUDMenu.items(.group), [.feed, .drink, .play, .decor, .bedtime, .callAll])
    }

    func testOneJelbieCanBeHighlightedForTheIndividualMenu() {
        let c = GameCare(jellyCount: 1, persistent: false, defaults: UserDefaults(suiteName: "HUDMenu.1")!)
        Self.keep.append(c)
        XCTAssertEqual(HUDMenu.mode(c), .group)
        c.tapJelly(0)
        XCTAssertEqual(HUDMenu.mode(c), .individual(0))
        XCTAssertTrue(HUDMenu.items(.individual(0)).contains(.clean))
        c.clearHighlight()
        XCTAssertEqual(HUDMenu.mode(c), .group)
    }

    func testIndividualModeAfterATapPick() {
        let care = care3()
        care.tapJelly(1)
        tickSelect(care, 2.5)
        XCTAssertEqual(care.select.highlighted, 1); XCTAssertFalse(care.select.isSelecting)
        XCTAssertEqual(HUDMenu.mode(care), .individual(1))
        XCTAssertEqual(HUDMenu.items(.individual(1)), [.dress, .clean, .train, .compete, .come])
        XCTAssertEqual(care.targetJelly, 1); XCTAssertEqual(care.singledOutJelly, 1)
        XCTAssertEqual(HUDMenu.title(.train, .individual(1), care: care), "Train")
        XCTAssertEqual(HUDMenu.spokenLabel(.train, .individual(1), care: care), "Train \(care.jelly(1)!.name)")
    }

    func testGroupMenuHasACallEveryoneRowAtTheEndOnlyWhenNobodyIsHighlighted() {
        let care = care3()
        XCTAssertEqual(HUDMenu.items(.group).last, .callAll, "Come here is the last option, after Bedtime")
        XCTAssertEqual(HUDMenu.visibleItems(.group, care: care).last, .callAll)
        XCTAssertEqual(HUDMenu.title(.callAll, .group, care: care), "Come here")
        XCTAssertEqual(HUDMenu.spokenLabel(.callAll, .group, care: care), "Call everyone")
        XCTAssertEqual(HUDItem.callAll.rawValue, "hud-call-all")
        XCTAssertEqual(HUDMenu.perform(.callAll, .group, care: care), .none)
        XCTAssertEqual(care.focusedJellies, [0, 1, 2], "tapping it calls all three")
        XCTAssertFalse(HUDMenu.visibleItems(.group, care: care).contains(.callAll), "hidden once they are called")
        care.release()
        let c2 = care3()
        c2.tapJelly(1); tickSelect(c2, 2.5)
        XCTAssertFalse(HUDMenu.items(.individual(1)).contains(.callAll))
        XCTAssertFalse(HUDMenu.visibleItems(.group, care: c2).contains(.callAll), "not while a Jelbie is highlighted")
    }

    func testSleepButtonReadsNaptimeByDayAndBedtimeInTheEvening() {
        let care = care3()
        let clock = DayClock.shared, saved = clock.forcedHour
        defer { clock.forcedHour = saved }
        for (hour, want) in [(8.0, "Naptime"), (12.0, "Naptime"), (15.0, "Naptime"), (18.0, "Bedtime"), (20.5, "Bedtime"), (23.0, "Bedtime"), (3.0, "Bedtime")] {
            clock.forcedHour = hour
            XCTAssertEqual(HUDMenu.title(.bedtime, .group, care: care), want, "at \(hour):00")
            XCTAssertEqual(HUDMenu.spokenLabel(.bedtime, .group, care: care), want)
            XCTAssertEqual(HUDMenu.symbol(.bedtime), "moon.zzz.fill")
        }
    }

    func testComeHereRowCallsHimAndDisablesInTheCloseUp() {
        let care = care3()
        care.tapJelly(1)
        tickSelect(care, 2.5)
        let m = HUDMode.individual(1)
        XCTAssertTrue(HUDMenu.enabled(.come, m, care: care)); XCTAssertNil(HUDMenu.disabledReason(.come, m, care: care))
        XCTAssertEqual(HUDMenu.spokenLabel(.come, m, care: care), "Call \(care.jelly(1)!.name) over")
        XCTAssertFalse(HUDMenu.items(.group).contains(.come))
        XCTAssertEqual(HUDMenu.perform(.come, m, care: care), .none)
        XCTAssertTrue(care.focus.isActive)
        XCTAssertFalse(HUDMenu.enabled(.come, m, care: care)); XCTAssertEqual(HUDMenu.disabledReason(.come, m, care: care), "Already in the close-up")
    }

    func testClearHighlightBringsGroupBack() {
        let care = care3()
        care.tapJelly(2); tickSelect(care, 2.5)
        XCTAssertEqual(HUDMenu.mode(care), .individual(2))
        care.clearHighlight()
        XCTAssertEqual(HUDMenu.mode(care), .group); XCTAssertEqual(care.targetJelly, 0); XCTAssertNil(care.singledOutJelly)
    }

    func testDrawInProgressAlreadyShowsHisMenu() {
        let care = care3()
        care.tapJelly(1)
        XCTAssertTrue(care.select.isSelecting)
        XCTAssertEqual(HUDMenu.mode(care), .individual(1))
    }

    func testRoutes() {
        let care = care3()
        XCTAssertEqual(HUDMenu.perform(.dress, .individual(2), care: care), .bag(.wear, who: 2))
        XCTAssertEqual(HUDMenu.perform(.play, .group, care: care), .picker(.toy))          // (2026-11-02: Play opens the toy picker)
        XCTAssertEqual(HUDMenu.perform(.decor, .group, care: care), .bag(.furniture, who: 0))
        XCTAssertEqual(HUDMenu.perform(.compete, .individual(2), care: care), .competeChips)
        XCTAssertEqual(HUDMenu.compete(.track, id: 2), .town(.track, who: 2))
        XCTAssertEqual(HUDMenu.compete(.studio, id: 2), .town(.studio, who: 2))
        XCTAssertEqual(HUDMenu.perform(.feed, .group, care: care), .picker(.food))
        XCTAssertEqual(HUDMenu.perform(.drink, .group, care: care), .picker(.drink))
    }

    func testBedtimeCallsBedtimeAll() {
        let care = care3()
        var got: [Int] = []
        care.voice.onGoodnight = { ids in got = ids }
        XCTAssertEqual(HUDMenu.perform(.bedtime, .group, care: care), .none)
        XCTAssertEqual(got, [0, 1, 2])
    }

    func testTrainOpensTheCloseUpForThatJelbie() {
        let r = room()
        XCTAssertEqual(HUDMenu.perform(.train, .individual(2), care: r.care), .none)
        XCTAssertTrue(r.run(20) { r.care.focus.phase == .focused }, "phase \(r.care.focus.phase)")
        XCTAssertEqual(r.care.focusGroup.ids, [2])
    }

    @MainActor func testGoOutOpensTheTownAndTheTownOffersTheCafe() {
        // The button's action is the whole behaviour: one tap, one callback (the game sets town = .town).
        var taps = 0
        _ = GoOutButton { taps += 1 }
        XCTAssertEqual(taps, 0)
        // The Town's Café destination closes the Town (goHome) and then starts the trip (cafe).
        var log: [String] = []
        let flow = TownFlow(care: care3(), screen: .constant(.town), who: 0, cafe: { log.append("cafe") }, goHome: { log.append("home") })
        XCTAssertEqual(flow.currentScreen, .town)
        flow.chooseCafe()
        XCTAssertEqual(log, ["home", "cafe"])
    }

    // MARK: highlight and sleep

    private func putToSleep(_ r: FocusAnyRun, _ id: Int) {
        let b = r.actors[id].brain!
        b.idleForced = true; _ = b.idleStart(.sleep, r.actors[id].sim); b.sleep.hold = 500; b.sleep.holdForce = true
        r.run(40) { b.isSleeping }
        XCTAssertTrue(b.isSleeping, "Jelbie \(id) fell asleep")
    }

    func testHighlightingASleeperDoesNotWakeHim() {
        let r = room()
        putToSleep(r, 2)
        var drew = false
        r.care.tapJelly(2)
        for _ in 0..<(4 * 60) { r.tick(); if r.care.select.isSelecting { drew = true } }
        XCTAssertTrue(r.actors[2].brain!.isSleeping, "he is still asleep")
        XCTAssertEqual(r.care.select.highlighted, 2)
        XCTAssertFalse(drew, "no draw"); XCTAssertNil(r.care.select.takeHopRequest())
    }

    func testRosterPickOnASleeperDoesNotHang() {
        let r = room()
        putToSleep(r, 2)
        r.care.rosterPick(2)
        XCTAssertEqual(r.care.select.highlighted, 2)
        XCTAssertFalse(r.care.select.waiting)
        r.run(2)
        XCTAssertTrue(r.actors[2].brain!.isSleeping)
    }

    func testCleanOnASleepingHighlightedJelbieStarts() {
        let r = room()
        putToSleep(r, 2)
        r.care.tapJelly(2)
        XCTAssertEqual(HUDMenu.perform(.clean, .individual(2), care: r.care), .none)
        var t: Float = 0
        for _ in 0..<(60 * 40) {
            if r.care.bath.acceptsTouch {
                let c = r.actors[2].sim.centroid()
                let l = SIMD3<Float>(sinf(t * 3.1) * 0.5, 0.1, 0.6)
                r.care.bath.touch(contact: true, hitLocal: l, world: c + l, speed: 2.5, dt: 1.0 / 60)
            }
            r.tick(); t += 1.0 / 60
            if r.care.bath.phase == .soap { break }
        }
        XCTAssertEqual(r.care.bath.phase, .soap, "clean reached the soap for a sleeper")
    }
}
