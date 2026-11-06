//
//  MealFeedbackTests.swift
//  A feed tap that is refused must say so (a label over the head, a reason on the Food row); never a silent nothing.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MealFeedbackTests: XCTestCase {
    private func room(_ roster: [Int]) -> DiningJellyTests.Room {
        let r = DiningJellyTests.Room(count: roster.count, roster: roster)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        for a in r.actors { a.brain?.autonomy = false }
        r.run(1)
        return r
    }

    /// The user's case: Teddy + Panda, Food 7 in the bag, a Full belly with ~3 h left, tap feed.
    func testTeddyAndPandaFullBellyTapFeed() {
        let r = room([4, 6])
        let c = r.care
        XCTAssertEqual(c.jellies.map(\.character), [4, 6])
        c.store.grant("berries", 7)
        for j in c.jellies { j.perks.grant(.fullBelly, duration: 3 * 3600 - 360) }
        for a in r.actors { a.profile?.needs.set(.hunger, 0.95) }
        c.feed("berries", jelly: nil)
        XCTAssertEqual(c.notice, "Teddy and Panda aren't hungry (full belly, 2h 54m left)", "the answer is up at the tap")
        r.run(1)
        print("MEALFB full-belly: trayOut=\(c.trayOut) groupWanted=\(c.groupWanted != nil) phase=\(c.dining.phase) notice=\(String(describing: c.notice))")
        var sawTray = false, sawGroup = false, trayAt: Float = -1, endAt: Float = -1, walked = [Float](repeating: 0, count: 2), last = r.actors.map { $0.floor }
        let t0 = r.t
        r.run(20) {
            if c.dining.isPresent, !sawTray { sawTray = true; trayAt = r.t - t0 }
            if c.groupActive { sawGroup = true } else if sawGroup, endAt < 0 { endAt = r.t - t0 }
            for i in 0..<2 { walked[i] += simd_distance(r.actors[i].floor, last[i]); last[i] = r.actors[i].floor }
            return false
        }
        print("MEALFB timeline: sawTray=\(sawTray) at \(trayAt) sawGroup=\(sawGroup) groupEnded=\(endAt) walked=\(walked)")
        print("MEALFB after 20s: groupActive=\(c.groupActive) tray=\(c.dining.isPresent) notice=\(String(describing: c.notice)) refusals=\(c.noticeSerial)")
        XCTAssertTrue(sawTray, "the tray still comes out for two full bellies (it stays ~3 s while they shake their heads); the label now says why")
        XCTAssertEqual(c.noticeSerial, 1)
    }

    func testTeddyAndPandaHungryEat() {
        let r = room([4, 6])
        let c = r.care
        c.store.grant("berries", 7)
        for a in r.actors { a.profile?.needs.set(.hunger, 0.1) }
        c.feed("berries", jelly: nil)
        r.run(25)
        print("MEALFB dbg wanted=\(c.groupWanted != nil) phase=\(c.dining.phase) gstate=\(c.group.state) gaveUp=\(c.group.gaveUp) bag=\(c.store.count(food: "berries")) acts=\(r.actors.map { String(describing: $0.brain?.activity) }) pos=\(r.actors.map { $0.floor }) call=\(c.callRunning) q=\(c.queued.count) jc=\(c.jellies.count)")
        print("MEALFB hungry: groupActive=\(c.groupActive) tray=\(c.dining.isPresent) levels=\(r.level(0)),\(r.level(1))")
        XCTAssertGreaterThan(r.level(0), 0.3)
        XCTAssertGreaterThan(r.level(1), 0.3)
    }

    func testRefusedTapsAnswerAtOnce() {
        let r = room([4, 6])
        let c = r.care
        // empty bag (the rig stocks every food)
        for _ in 0..<40 { c.store.use("pizza") }
        c.feed("pizza", jelly: nil)
        XCTAssertEqual(c.notice, "No Pizza left in the bag")
        XCTAssertFalse(c.trayOut)
        r.run(2.5)
        XCTAssertNil(c.notice, "the label goes away by itself")
        // a meal already out
        c.store.grant("berries", 3)
        for a in r.actors { a.profile?.needs.set(.hunger, 0.1) }
        c.feed("berries", jelly: nil)
        r.run(0.5)
        XCTAssertTrue(c.trayOut)
        XCTAssertNil(c.notice)
        c.feed("berries", jelly: nil)
        XCTAssertEqual(c.notice, "Food is already out")
        XCTAssertFalse(HUDMenu.enabled(.feed, .group, care: c))
        XCTAssertEqual(HUDMenu.disabledReason(.feed, .group, care: c), "Food is already out")
    }

    func testTapDuringACleanUpAnswers() {
        let r = room([4, 6])
        let c = r.care
        c.store.grant("berries", 3)
        c.clean()
        r.run(0.3)
        if c.bath.active {
            c.feed("berries", jelly: nil)
            XCTAssertEqual(c.notice, "Not while cleaning")
            XCTAssertFalse(c.trayOut)
        }
    }

    /// The pair is fed again and again from the rest spots: a serving must never end without a tray and without anyone eating (it did, once in a few runs).
    func testPairIsNeverGivenUpOnSilently() {
        var bad: [String] = []
        for rep in 0..<8 {
            let r = room([4, 6])
            let c = r.care
            c.store.grant("berries", 7)
            for a in r.actors { a.profile?.needs.set(.hunger, 0.1) }
            c.feed("berries", jelly: nil)
            var sawTray = false, dbg = ""
            r.run(30) {
                if c.dining.isPresent { sawTray = true }
                if c.group.gaveUp, dbg.isEmpty { dbg = "approach=\((0..<2).map { c.group.approachPoint(blob: $0) }) floors=\(r.actors.map(\.floor)) acts=\(r.actors.map { String(describing: $0.brain?.activity) }) t=\(r.t)" }
                return false
            }
            let ate = r.level(0) > 0.3 && r.level(1) > 0.3
            if !ate || !sawTray { bad.append("rep \(rep): tray=\(sawTray) ate=\(ate) notice=\(String(describing: c.notice)) \(dbg)") }
        }
        print("MEALFB loop bad=\(bad)")
        XCTAssertTrue(bad.isEmpty, "\(bad)")
    }
}
