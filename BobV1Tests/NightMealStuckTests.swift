//
//  NightMealStuckTests.swift
//  night-meal-r1 (the owner, 2026-11-24 00:15: "Food and drink isn't working ... I had to restart app to get it to work"). A stuck meal system: whatever the player did before, a Feed / Water tap with nothing
//  legitimately holding the meal must put the tray out and the Jelmiko must eat. A fuzz of care actions, then the check.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class NightMealStuckTests: XCTestCase {
    private var savedHour: Double?
    override func setUp() { savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = Double(ProcessInfo.processInfo.environment["NIGHT_MEAL_HOUR"].flatMap(Double.init) ?? 14) }
    override func tearDown() { DayClock.shared.forcedHour = savedHour }

    struct LCG { var s: UInt64; mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(n)) } }

    static let opCount = 13
    func step(_ r: DiningJellyTests.Room, _ s: Float, until: (() -> Bool)? = nil) {
        for _ in 0..<Int(s * 60) { r.tick(); r.care.tickDecor(dt: 1 / 60); r.care.tickPlay(r.actors, dt: 1 / 60); if let until, until() { break } }
    }

    func state(_ r: DiningJellyTests.Room) -> String {
        let c = r.care
        return "wanted=\(c.wanted != nil) meal=\(c.meal != nil) tray=\(c.dining.phase) groupWanted=\(c.groupWanted != nil) group=\(c.group.isActive) queue=\(c.groupQueue.count) callRunning=\(c.callRunning) queued=\(c.queued.count) focus=\(c.focus.phase) trayOut=\(c.trayOut) bath=\(c.bath.active) play=\(c.play.active) sess=\(r.actors.map { $0.brain!.mix.sess }) cancelPill=\(c.cancelPill) auto=\(r.actors.map { $0.brain!.autonomy }) reserved=\(r.actors.map { $0.brain!.reserved })"
    }

    /// Runs one random sequence; returns nil when fine, else a description.
    func sequence(seed: UInt64, steps: Int) -> String? {
        let r = DiningJellyTests.Room(count: 3, wander: true)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        DiningGroup.homeSeats = 3
        var g = LCG(s: seed)
        var trace: [String] = []
        step(r, 1)
        for _ in 0..<steps {
            let op = g.next(Self.opCount), j = g.next(3)
            for a in r.actors { a.profile?.needs.set(.hunger, 0.1); a.profile?.needs.set(.thirst, 0.1) }
            switch op {
            case 0: r.care.feed(); trace.append("feed")
            case 1: r.care.water(); trace.append("water")
            case 2: r.care.feed(jelly: j); trace.append("feed(\(j))")
            case 3: r.care.drink(jelly: j); trace.append("drink(\(j))")
            case 4: r.care.comeHere(jelly: j); trace.append("come(\(j))")
            case 5: r.care.comeHereEveryone(); trace.append("comeAll")
            case 6: r.care.cancelGroupAction(); trace.append("cancel")
            case 7: r.care.release(); trace.append("release")
            case 8: r.care.showWelcomeHome(1 + j % 2, won: true, again: false); trace.append("showHome")
            case 9: r.care.store.grant(DecorKind.ball.storeID); r.care.beginPlay(ball: .ball); trace.append("play ball")
            case 10: r.care.endPlay(); trace.append("endPlay")
            case 11: r.care.store.grant(DecorKind.soccerball.storeID); r.care.beginPlay(ball: .soccerball); trace.append("play soccer")
            case 12:
                if !r.care.store.placedDecor.contains(where: { $0.kind == .soccerball }) { r.care.store.grant(DecorKind.soccerball.storeID); _ = r.care.store.place(DecorKind.soccerball.storeID, dev: true); r.care.syncDecor() }
                trace.append("soccerball room")
            default: break
            }
            let s = Float(g.next(70)) / 10; step(r, s); trace.append("run \(s)")
        }
        // the player stops doing things: everything is let go, the room settles
        r.care.cancelGroupAction(); r.care.release(); r.care.endPlay()
        step(r, 40)
        r.care.release(); step(r, 10)
        if r.care.trayOut || r.care.focus.isActive { return "seed \(seed): not settled after 50 s: \(state(r)) :: \(trace.joined(separator: ", "))" }
        // the check: Feed then Water must work
        for what in ["feed", "water"] {
            for a in r.actors { a.profile?.needs.set(.hunger, 0.1); a.profile?.needs.set(.thirst, 0.1) }
            let before = r.actors.map { r.level($0.id, what == "feed" ? .hunger : .thirst) }
            if what == "feed" { r.care.feed() } else { r.care.water() }
            var tray = false
            step(r, 70) { if r.care.dining.isPresent { tray = true }; return tray }
            if !tray { return "seed \(seed): \(what): no tray in 70 s: \(state(r)) :: \(trace.joined(separator: ", "))" }
            step(r, 120) { !r.care.trayOut }
            let after = r.actors.map { r.level($0.id, what == "feed" ? .hunger : .thirst) }
            if !zip(before, after).allSatisfy({ $0.1 > $0.0 + 0.2 }) || r.care.trayOut { return "seed \(seed): \(what): did not eat/finish before \(before) after \(after): \(state(r)) :: \(trace.joined(separator: ", "))" }
            step(r, 5)
        }
        return nil
    }

    func testFuzzThenFeedAndWaterAlwaysWork() {
        let n = Int(ProcessInfo.processInfo.environment["NIGHT_MEAL_SEEDS"] ?? "") ?? 12
        var bad: [String] = []
        for seed in 1...UInt64(n) { if let f = sequence(seed: seed, steps: 8) { bad.append(f); print("NIGHTMEAL-FAIL \(f)") } }
        XCTAssertTrue(bad.isEmpty, bad.joined(separator: "\n"))
    }

    // MARK: the guarantee

    private func room() -> DiningJellyTests.Room {
        let r = DiningJellyTests.Room(count: 3, wander: true)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        DiningGroup.homeSeats = 3
        step(r, 1)
        return r
    }
    private func hungry(_ r: DiningJellyTests.Room) { for a in r.actors { a.profile?.needs.set(.hunger, 0.1); a.profile?.needs.set(.thirst, 0.1) } }
    /// Taps Feed / Water (a group serving, or Jelly 0 alone) and reports whether the tray came out and everybody who should eat ate.
    private func serve(_ r: DiningJellyTests.Room, drink: Bool, single: Bool) -> Bool {
        hungry(r)
        let kind: NeedKind = drink ? .thirst : .hunger
        let before = r.actors.map { r.level($0.id, kind) }
        if drink { r.care.water(jelly: single ? 0 : nil) } else { r.care.feed(jelly: single ? 0 : nil) }
        var tray = false
        step(r, 70) { if r.care.dining.isPresent { tray = true }; return tray }
        guard tray else { return false }
        step(r, 120) { !r.care.trayOut }
        let after = r.actors.map { r.level($0.id, kind) }
        return !r.care.trayOut && after[0] > before[0] + 0.2
    }

    /// A come call nobody walks (its job was cut short and never reported) left `callRunning` set: before the guarantee Feed / Water never started (relaunch needed), now they do.
    func testStaleCallRunningNeverBlocksFeedOrWater() {
        for hour in [14.0, 22.0] {
            DayClock.shared.forcedHour = hour
            for (drink, single) in [(false, false), (true, false), (false, true), (true, true)] {
                GameCare.unstickOn = false
                let bad = room()
                bad.care.callRunning = true
                XCTAssertFalse(serve(bad, drink: drink, single: single), "hour \(hour) drink \(drink) single \(single): WITHOUT the guarantee the stale lock blocks the meal (the owner's bug)")
                GameCare.unstickOn = true
                let r = room()
                r.care.callRunning = true
                XCTAssertTrue(serve(r, drink: drink, single: single), "hour \(hour) drink \(drink) single \(single): with the guarantee the meal runs; \(state(r))")
            }
        }
        GameCare.unstickOn = true
    }

    /// A tray / wanted meal that outlived any real meal (nobody eating, lock older than the limit) is cleared by the next tap; a LIVE meal is left alone and the tap is refused as ever.
    func testStaleMealLockClearedButLiveMealUntouched() {
        let r = room()
        hungry(r)
        r.care.feed()
        step(r, 3)
        XCTAssertTrue(r.care.groupActive, "a live meal is running")
        XCTAssertTrue(r.care.mealUnstick(why: "test").isEmpty, "a live meal is not touched")
        r.care.feed()          // refused ("Food is already out")
        XCTAssertTrue(r.care.groupActive)
        // the lock outlives any real meal (its diners are gone): the next tap clears it and serves
        r.care.mealLockAge = GameCare.staleMealAfter + 1
        XCTAssertFalse(r.care.mealUnstick(why: "test").isEmpty, "a stale lock is cleared")
        XCTAssertFalse(r.care.groupActive)
        step(r, 2)
        XCTAssertTrue(serve(r, drink: false, single: false), "and the next Feed works")
    }

    /// The leak itself: a welcome-home come call (the Show / race return) that a ball game's line then takes over never reports; `callRunning` must not stay set.
    func testWelcomeHomeThenPlayDoesNotLeaveTheCallRunning() {
        for play in [DecorKind.ball, .soccerball] {
            for delay in [0.1, 0.5, 1.5, 3.0] {
                let r = room()
                r.care.store.grant(play.storeID)
                r.care.showWelcomeHome(1, won: true, again: false)
                step(r, Float(delay))
                r.care.beginPlay(ball: play)
                step(r, 6)
                r.care.endPlay()
                step(r, 30)
                XCTAssertFalse(r.care.callRunning, "\(play) after \(delay) s: the call is over (\(state(r)))")
                XCTAssertTrue(serve(r, drink: false, single: false), "\(play) after \(delay) s: Feed works afterwards")
            }
        }
    }
}
