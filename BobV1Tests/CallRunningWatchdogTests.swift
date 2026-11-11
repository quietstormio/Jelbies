//
//  CallRunningWatchdogTests.swift
//  `GameCare.callRunning` must not outlive its `.come`: a come that vanishes without `onFinished` (abortAll, sleepLingerEnd) used to block every later meal.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CallRunningWatchdogTests: XCTestCase {
    private func room(_ n: Int = 3) -> DiningJellyTests.Room {
        let r = DiningJellyTests.Room(count: n)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        for a in r.actors { a.brain?.autonomy = false }
        r.run(1)
        return r
    }
    override func setUp() { GameCare.callWatchdog = true }
    override func tearDown() { GameCare.callWatchdog = true }

    /// Hands a come to Bob and ticks until the care has passed it to the brain.
    private func handOver(_ r: DiningJellyTests.Room, to p: SIMD2<Float>) {
        r.care.queued = [.come(to: p)]
        r.tick()
        XCTAssertTrue(r.care.callRunning, "the hand-over sets callRunning")
    }

    func testNormalComeKeepsCallRunningUntilItFinishes() {
        let r = room()
        let target = SIMD2<Float>(1.4, 1.0)
        handOver(r, to: target)
        var ticks = 1, clearedAt = -1
        while ticks < 60 * 40 {
            r.tick(); ticks += 1
            if !r.care.callRunning { clearedAt = ticks; break }
        }
        XCTAssertGreaterThan(clearedAt, 60, "the walk takes a while; callRunning was cleared at tick \(clearedAt)")
        let b = r.actors[0].brain!
        XCTAssertNil(b.job); XCTAssertNil(b.pending)
        XCTAssertLessThan(simd_distance(r.actors[0].floor, target), 0.7, "cleared only when he had arrived, floor \(r.actors[0].floor)")
    }

    func testAbortedComeClearsCallRunning() {
        let r = room()
        handOver(r, to: SIMD2(1.4, 1.0))
        r.run(0.5)
        XCTAssertTrue(r.care.callRunning, "a real come is still walking")
        r.actors[0].brain!.abortAll(r.actors[0].sim, r.actors[0].skinner)
        var t: Float = 0
        while r.care.callRunning, t < 0.5 { r.tick(); t += 1 / 60 }
        XCTAssertFalse(r.care.callRunning, "callRunning still true \(t) s after abortAll")
    }

    func testGroupMealStartsAfterAnAbortedCome() {
        if ProcessInfo.processInfo.environment["CALLFIX_BEFORE"] != nil { GameCare.callWatchdog = false }       // (before-fix run: TEST_RUNNER_CALLFIX_BEFORE=1)
        let r = room()
        let c = r.care
        c.store.grant("berries", 7)
        handOver(r, to: SIMD2(1.4, 1.0))
        r.run(0.5)
        r.actors[0].brain!.abortAll(r.actors[0].sim, r.actors[0].skinner)
        for a in r.actors { a.profile?.needs.set(.hunger, 0.1) }
        c.feed("berries", jelly: nil)
        var started = false
        r.run(5) { if c.group.isActive { started = true }; return started }
        XCTAssertTrue(started, "the group meal did not start within 5 s (callRunning=\(c.callRunning) groupWanted=\(c.groupWanted != nil) notice=\(String(describing: c.notice)))")
    }

    func testComeReplacedDirectlyLikeSleepLingerEndClears() {
        let r = room()
        handOver(r, to: SIMD2(1.4, 1.0))
        r.run(0.5)
        XCTAssertTrue(r.care.callRunning)
        let b = r.actors[0].brain!
        b.job = nil; b.script = .walk(target: SIMD2(-1, 0.5), then: .none)
        var t: Float = 0
        while r.care.callRunning, t < 0.5 { r.tick(); t += 1 / 60 }
        XCTAssertFalse(r.care.callRunning, "callRunning still true \(t) s after the job was replaced")
    }

    /// Documents the old bug: without the watchdog the flag stays up and the group waits.
    func testWithoutTheWatchdogTheFlagStaysStuck() {
        GameCare.callWatchdog = false
        let r = room()
        handOver(r, to: SIMD2(1.4, 1.0))
        r.run(0.5)
        r.actors[0].brain!.abortAll(r.actors[0].sim, r.actors[0].skinner)
        r.run(3)
        XCTAssertTrue(r.care.callRunning, "(old behaviour) stuck")
    }
}
