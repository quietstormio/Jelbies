//
//  ShowStayHomeTests.swift
//  show-stayhome-r1 (owner rule): a trip never wakes or disturbs a Jelmiko who stays home; when it ends he is exactly where and as he was. The Show and the beach (Volleyball)
//  follow the race: only the one going is woken; the housemates are hidden and unstepped while away and come back as they were; a sleeper is not called to the welcome.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ShowStayHomeTests: XCTestCase {
    private func room() -> RaceThreeTests.Room {
        let r = RaceThreeTests.Room(count: 3)
        RaceThreeTests.keep.append(r)
        return r
    }
    private func step(_ r: RaceThreeTests.Room) {
        r.step()
        r.care.tickShow(r.actors, dt: 1 / 60)
        r.care.tickVolley(r.actors, dt: 1 / 60)
        r.care.tickWear(r.actors, dt: 1 / 60)
    }
    private func head(_ r: RaceThreeTests.Room, _ id: Int) -> String { r.care.wardrobe.slot(id)?.items[.head]?.look?.rawValue ?? "-" }
    private func run(_ r: RaceThreeTests.Room, _ s: Float, until: () -> Bool = { false }) { for _ in 0..<Int(s * 60) { step(r); if until() { return } } }

    private func putToBed(_ r: RaceThreeTests.Room, _ id: Int) throws {
        let b = r.actors[id].brain!
        b.commandedGoodnight = true
        run(r, 40) { b.isSleeping && b.sleep.stage >= 4 }
        try XCTSkipUnless(b.isSleeping, "no sleep in this host (the clock / night rest woke him)")
        run(r, 3)
    }
    private struct Snap { let floor: SIMD2<Float>, centroid: SIMD3<Float>, stage: Int, asleep: Bool }
    private func snap(_ r: RaceThreeTests.Room, _ id: Int) -> Snap {
        let a = r.actors[id]
        return Snap(floor: a.floor, centroid: a.sim.centroid(), stage: a.brain!.sleep.stage, asleep: a.brain!.isSleeping)
    }
    private func assertSame(_ r: RaceThreeTests.Room, _ id: Int, _ was: Snap, _ what: String) {
        let now = snap(r, id)
        XCTAssertLessThan(simd_distance(now.floor, was.floor), 0.02, "\(what): same spot")
        XCTAssertLessThan(simd_distance(now.centroid, was.centroid), 0.03, "\(what): same pose")
        XCTAssertEqual(now.asleep, was.asleep, "\(what): same sleeping state")
        XCTAssertEqual(now.stage, was.stage, "\(what): same sleep stage")
    }

    func testShowSleeperAndWalkerAtHomeAreUntouched() throws {
        let r = room(), care = r.care
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.cue = { _ in }
        r.actors[2].brain?.autonomy = true
        care.store.saved.wearables = [WearLook.flowerCrown.rawValue]
        XCTAssertTrue(care.store.wear(.flowerCrown, on: 2))
        try putToBed(r, 1)
        XCTAssertEqual(head(r, 2), WearLook.flowerCrown.rawValue, "the housemate is dressed before the Show")
        let sleeper = snap(r, 1), awake = snap(r, 2)
        var badWear = 0
        care.startShow(jelly: 0, rank: .puddle, seed: 5)
        XCTAssertNil(care.showBook.wait, "a sleeping housemate does not hold the Show up")
        var woke = false
        run(r, 8) { if !care.showBook.roomAway, head(r, 2) != WearLook.flowerCrown.rawValue { badWear += 1 }; return care.show.onStage }
        XCTAssertTrue(care.show.onStage)
        run(r, 3) { if !r.actors[1].brain!.isSleeping { woke = true }; return false }
        XCTAssertTrue(care.showStaysHome(1) && care.showStaysHome(2))
        assertSame(r, 2, awake, "awake stay-home while the stage is up")
        care.show.abort()
        run(r, 20) { !care.show.active && !care.showBook.roomAway }
        assertSame(r, 2, awake, "awake stay-home the moment the Show is over")
        let back = r.actors[2].floor
        run(r, 0.25)
        XCTAssertLessThan(simd_distance(r.actors[2].floor, back), 0.4, "no jump after the return")
        run(r, 8)
        XCTAssertEqual(badWear, 0, "a housemate keeps his wear through the fade out (no strip, no pop)")
        XCTAssertEqual(head(r, 2), WearLook.flowerCrown.rawValue, "and after the return")
        XCTAssertFalse(care.show.active)
        XCTAssertFalse(woke, "the sleeper was never woken")
        assertSame(r, 1, sleeper, "sleeper after the Show")
        XCTAssertFalse(care.greetPending.contains(1), "the welcome home does not call the sleeper")
    }

    func testShowContestantAsleepIsWokenAndWaitedFor() throws {
        let r = room(), care = r.care
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.cue = { _ in }
        try putToBed(r, 0)
        try putToBed(r, 1)
        let sleeper = snap(r, 1)
        care.startShow(jelly: 0, rank: .puddle, seed: 5)
        XCTAssertNotNil(care.showBook.wait, "the contestant is waited for")
        run(r, 20) { care.show.active }
        XCTAssertTrue(care.show.active, "the Show starts once he is up")
        XCTAssertFalse(r.actors[0].brain!.isSleeping)
        run(r, 8) { care.show.onStage }
        care.show.abort()
        run(r, 20) { !care.show.active }
        run(r, 3)
        assertSame(r, 1, sleeper, "sleeping housemate")
    }

    func testVolleySleeperAndWalkerAtHomeAreUntouched() throws {
        let r = room(), care = r.care
        r.actors[2].brain?.autonomy = true
        try putToBed(r, 2)
        let sleeper = snap(r, 2)
        care.startVolley(jelly: 0, mode: .match(care.volley.book.chosen), seed: 5)
        XCTAssertNil(care.volleyWork.wait, "a sleeping housemate does not hold the match up")
        var woke = false
        run(r, 15) { care.volley.live }
        XCTAssertTrue(care.volley.inScene)
        run(r, 3) { if !r.actors[2].brain!.isSleeping { woke = true }; return false }
        XCTAssertTrue(care.volleyHides(2))
        care.volley.goHome()
        run(r, 20) { !care.volley.active && !care.volley.inScene }
        run(r, 8)
        XCTAssertFalse(woke, "the sleeper was never woken")
        assertSame(r, 2, sleeper, "sleeper after the match")
    }

    /// A housemate frozen mid-emote resumes without a snap after the Show and after the match (the first step home moves him no more than a normal step).
    func testStayHomeMidEmoteResumesWithoutASnap() {
        for trip in ["show", "volley"] {
            let r = room(), care = r.care
            care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.cue = { _ in }
            let h = r.actors[2], b = h.brain!
            b.autonomy = true
            b.idleBegin(.bounce)
            func maxDelta(_ a: [Float], _ c: [Float]) -> Float { zip(a, c).map { abs($0 - $1) }.max() ?? 0 }
            var prev = h.sim.x, typical: Float = 0
            for _ in 0..<20 { step(r); typical = max(typical, maxDelta(prev, h.sim.x)); prev = h.sim.x }
            XCTAssertGreaterThan(typical, 0, "\(trip): he is moving before the trip")
            if trip == "show" { care.startShow(jelly: 0, rank: .puddle, seed: 5) } else { care.startVolley(jelly: 0, mode: .match(care.volley.book.chosen), seed: 5) }
            var lastBefore = h.sim.x, away = false, sawAway = false, resume: Float?
            var awaySteps = 0
            for _ in 0..<(120 * 60) {
                step(r)
                if care.tripFrozen(2) {
                    awaySteps += 1
                    if trip == "show" { if awaySteps == 180 { care.show.abort() } } else if awaySteps > 180 { care.volley.goHome() }          // (goHome is a no-op until the match is on)
                }
                if care.tripFrozen(2) { away = true; sawAway = true; continue }
                if away { resume = maxDelta(lastBefore, h.sim.x); break }
                lastBefore = h.sim.x
            }
            XCTAssertTrue(sawAway, trip); XCTAssertNotNil(resume, trip)
            XCTAssertLessThan(resume ?? 99, max(2 * typical, 0.05), "\(trip): the first step home moves him no more than a normal step (typical \(typical))")
        }
    }

    func testVolleyAwakeStayHomeIsBackWhereHeWas() {
        let r = room(), care = r.care
        r.actors[2].brain?.autonomy = true
        run(r, 2)
        let was = snap(r, 2)
        care.startVolley(jelly: 0, mode: .match(care.volley.book.chosen), seed: 5)
        run(r, 15) { care.volley.live }
        XCTAssertTrue(care.volley.inScene)
        run(r, 3)
        care.volley.goHome()
        run(r, 20) { !care.volley.active && !care.volley.inScene }
        assertSame(r, 2, was, "awake stay-home the moment the match is over (back where he was, no teleport, no reset)")
    }
}
