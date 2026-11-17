//
//  ForfeitHomeTests.swift
//  "Go home" in the middle of a competition (Race/ForfeitHome.swift): the card holds the competition still, "Keep playing" resumes, "Go home" leaves with nothing
//  settled (no Drops, trophy, points, stats, win) and with every flag clean, so the player can go out again at once.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ForfeitHomeTests: XCTestCase {
    private typealias Room = RaceThreeTests.Room

    private func step(_ r: Room, _ n: Int = 1) {
        for _ in 0..<n {
            r.step()
            r.care.tickShow(r.actors, dt: 1 / 60)
            r.care.tickVolley(r.actors, dt: 1 / 60)
        }
    }
    private func run(_ r: Room, seconds: Float, until: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) { step(r); if let u = until, u() { break } }
    }
    private func room() -> Room {
        let r = Room(count: 3)
        r.care.show.songClock = { _ in nil }; r.care.show.audioReady = { _ in true }
        r.care.race.recentRivals = nil
        return r
    }
    /// Everything a competition could pay or record, as one comparable string.
    private func ledger(_ c: GameCare) -> String {
        "\(c.bath.wallet.count)|\(c.jelly(0)?.stats.races ?? -1)|\(c.jelly(0)?.stats.wins ?? -1)|\(c.race.progress.records)|\(c.show.progress.totalShows)|\(c.volley.book.stats(character: c.jelly(0)?.character ?? 0))"
    }
    private func assertClean(_ c: GameCare, _ r: Room, file: StaticString = #filePath, line: UInt = #line) {
        step(r, 3)          // (the sleep lock follows `raceBusy` on the next step)
        XCTAssertFalse(c.race.active, file: file, line: line); XCTAssertFalse(c.show.active, file: file, line: line); XCTAssertFalse(c.volley.active, file: file, line: line)
        XCTAssertFalse(c.tripActive, file: file, line: line); XCTAssertFalse(c.raceBusy, file: file, line: line); XCTAssertFalse(c.forfeitAsk, file: file, line: line)
        XCTAssertNil(c.raceWait, file: file, line: line)
        XCTAssertNil(c.volleyWork.wait, file: file, line: line); XCTAssertTrue(c.volleyWork.players.isEmpty, file: file, line: line)
        XCTAssertTrue(c.raceBook.parked.isEmpty, file: file, line: line); XCTAssertTrue(c.showBook.parked.isEmpty, file: file, line: line); XCTAssertTrue(c.raceBook.extra.isEmpty, file: file, line: line)
        for a in r.actors {
            XCTAssertEqual(a.brain?.idleBlocked, false, "idle block cleared for \(a.id)", file: file, line: line)
            XCTAssertEqual(a.brain?.sleepLocked, false, "sleep lock cleared for \(a.id)", file: file, line: line)
        }
    }
    /// The welcome home runs; going out again right now must work, and with the welcome still going it ends it (nothing stuck in `callRunning`).
    private func assertCanGoOutAgain(_ c: GameCare, _ r: Room, file: StaticString = #filePath, line: UInt = #line) {
        step(r, 5)
        XCTAssertNotNil(c.raceBook.returner, "the usual welcome home runs", file: file, line: line)
        XCTAssertFalse(c.raceBook.won, "a forfeit is never a win", file: file, line: line)
        c.startRace(jelly: 0, seed: 9)
        step(r, 3)
        XCTAssertTrue(c.race.active, "out again at once", file: file, line: line)
        XCTAssertFalse(c.callRunning, file: file, line: line)
        c.race.abort(); step(r, 3)
    }

    // MARK: the race

    private func raceMidway(_ r: Room) {
        r.care.startRace(jelly: 0, seed: 5)
        run(r, seconds: 12) { r.care.race.phase == .racing && r.care.race.wipe == 0 && (r.care.race.sim?.racers[1].dist ?? 0) > 3 }
        XCTAssertTrue(r.care.race.canForfeit)
    }

    func testRaceForfeitMidwayIsCleanAndFree() {
        let r = room(), c = r.care
        let before = ledger(c)
        raceMidway(r)
        XCTAssertTrue(c.canForfeit)
        c.askForfeit(); XCTAssertTrue(c.forfeitAsk)
        c.confirmForfeit()
        XCTAssertFalse(c.forfeitAsk)
        run(r, seconds: 8) { !c.race.active }
        XCTAssertFalse(c.race.active, "back in the room")
        XCTAssertEqual(c.race.earnedDropsForTest, 0)
        XCTAssertFalse(c.race.hasResults)
        XCTAssertEqual(ledger(c), before, "no Drops, trophy, ribbon, stats")
        assertClean(c, r)
        assertCanGoOutAgain(c, r)
    }

    func testRaceKeepPlayingResumesExactlyWhereItWas() {
        let r = room(), c = r.care
        raceMidway(r)
        c.askForfeit()
        let held = c.race.sim?.racers[1].dist ?? 0
        run(r, seconds: 2)
        XCTAssertEqual(c.race.sim?.racers[1].dist ?? -1, held, accuracy: 1e-6, "the race waits behind the card")
        XCTAssertTrue(c.race.active); XCTAssertEqual(c.race.phase, .racing)
        c.keepPlaying(); XCTAssertFalse(c.forfeitAsk)
        run(r, seconds: 1.5)
        XCTAssertGreaterThan(c.race.sim?.racers[1].dist ?? -1, held, "and goes on from there")
        XCTAssertTrue(c.race.canForfeit)
    }

    func testRaceForfeitAfterCrossingTheLineButBeforeResultsIsNotAWin() {
        let r = room(), c = r.care
        let before = ledger(c)
        raceMidway(r)
        // (the player cannot be put over the line from here: `finishTrip` reads `forfeited` before `playerWon`, which this checks through the flags)
        XCTAssertFalse(c.race.hasResults)
        c.askForfeit(); c.confirmForfeit()
        XCTAssertTrue(c.race.forfeited)
        run(r, seconds: 8) { !c.race.active }
        XCTAssertFalse(c.race.active)
        XCTAssertEqual(ledger(c), before)
        step(r, 5)
        XCTAssertFalse(c.raceBook.won, "no winner's medal and no win bounce")
        assertClean(c, r)
    }

    func testNoForfeitBeforeTheRaceStartsOrAtTheResults() {
        let r = room(), c = r.care
        c.startRace(jelly: 0, seed: 5)
        step(r, 3)
        XCTAssertFalse(c.canForfeit, "still fading to the track")
        c.askForfeit(); XCTAssertFalse(c.forfeitAsk)
        c.race.abort(); step(r, 3)
        XCTAssertFalse(c.canForfeit)
    }

    func testTheCardDoesNotOutliveItsCompetition() {
        let r = room(), c = r.care
        raceMidway(r)
        c.askForfeit(); XCTAssertTrue(c.forfeitAsk)
        c.race.abort(); step(r, 2)
        XCTAssertFalse(c.forfeitAsk)
    }

    // MARK: the show

    private func showMidway(_ r: Room, round: ShowRound = .look) {
        r.care.startShow(jelly: 0, rank: .puddle, seed: 5)
        run(r, seconds: 8) { r.care.show.onStage && r.care.show.phase == .stage && r.care.show.wipe == 0 }
        XCTAssertTrue(r.care.show.canForfeit)
    }

    func testShowForfeitInTheLookRoundIsCleanAndFree() {
        let r = room(), c = r.care
        let before = ledger(c)
        showMidway(r)
        c.askForfeit(); XCTAssertTrue(c.forfeitAsk)
        let age = c.show.lookAge
        run(r, seconds: 1)
        XCTAssertEqual(c.show.lookAge, age, accuracy: 1e-6, "the walk-on waits behind the card")
        c.keepPlaying()
        run(r, seconds: 0.5)
        XCTAssertGreaterThan(c.show.lookAge, age)
        c.askForfeit(); c.confirmForfeit()
        run(r, seconds: 8) { !c.show.active }
        XCTAssertFalse(c.show.active)
        XCTAssertTrue(c.show.forfeited); XCTAssertEqual(c.show.earned, 0); XCTAssertFalse(c.show.hasResults)
        XCTAssertEqual(ledger(c), before)
        assertClean(c, r)
        XCTAssertNotNil(c.raceBook.returner); XCTAssertFalse(c.raceBook.won)
        c.startShow(jelly: 0, rank: .puddle, seed: 6)
        step(r, 3)
        XCTAssertTrue(c.show.active, "the show can be entered again at once")
        c.show.abort(); step(r, 3)
        c.startRace(jelly: 0, seed: 9); step(r, 3)
        XCTAssertTrue(c.race.active, "and so can the race")
        c.race.abort()
    }

    func testShowForfeitInTheDanceRound() {
        let r = room(), c = r.care
        let before = ledger(c)
        showMidway(r)
        c.show.finishLook()
        run(r, seconds: 3)
        XCTAssertEqual(c.show.round, .dance)
        XCTAssertTrue(c.show.canForfeit)
        c.askForfeit(); c.confirmForfeit()
        run(r, seconds: 8) { !c.show.active }
        XCTAssertFalse(c.show.active)
        XCTAssertEqual(ledger(c), before)
        assertClean(c, r)
    }

    // MARK: the match

    func testVolleyForfeitMidMatchIsCleanAndFree() {
        let r = room(), c = r.care
        let before = ledger(c)
        c.startVolley(jelly: 0, mode: .match(.shore), seed: 5)
        run(r, seconds: 12) { c.volley.phase == .playing && c.volley.live }
        XCTAssertEqual(c.volley.phase, .playing)
        XCTAssertTrue(c.volley.canForfeit)
        c.askForfeit(); XCTAssertTrue(c.forfeitAsk)
        let ball = c.volley.sim?.ball.pos.y ?? 0, t = c.volley.sim?.clock ?? 0
        run(r, seconds: 1)
        XCTAssertEqual(c.volley.sim?.clock ?? -1, t, accuracy: 1e-6, "the match waits behind the card"); XCTAssertEqual(c.volley.sim?.ball.pos.y ?? -1, ball, accuracy: 1e-6)
        c.keepPlaying()
        run(r, seconds: 1)
        XCTAssertNotEqual(c.volley.sim?.clock ?? -1, t, "and goes on")
        c.askForfeit(); c.confirmForfeit()
        run(r, seconds: 8) { !c.volley.active }
        XCTAssertFalse(c.volley.active)
        XCTAssertTrue(c.volley.forfeited); XCTAssertEqual(c.volley.earned, 0); XCTAssertFalse(c.volley.hasResults)
        XCTAssertEqual(ledger(c), before)
        assertClean(c, r)
        c.startVolley(jelly: 0, mode: .match(.shore), seed: 6); step(r, 3)
        XCTAssertTrue(c.volley.active || c.volleyWork.wait != nil, "out again at once")
        c.startRace(jelly: 0, seed: 9)
        XCTAssertFalse(c.race.active, "(one trip at a time: the race waits for the match)")
    }
}
