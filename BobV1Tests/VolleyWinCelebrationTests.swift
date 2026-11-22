//
//  VolleyWinCelebrationTests.swift
//  Winning a beach volleyball match gives the race win's celebration (owner 11-22): the results jingle (the director's `.results` scene, the court track out)
//  and the confetti burst, once, at the moment the match is over. A loss gives neither.
//

import XCTest
@testable import BobV1

@MainActor
final class VolleyWinCelebrationTests: XCTestCase {
    private func play(winner team: Int) -> (jingles: [Bool], winMusic: Bool, rain: Double, over: Bool) {
        let r = RaceThreeTests.Room(count: 3), c = r.care
        c.show.songClock = { _ in nil }; c.show.audioReady = { _ in true }
        var jingles: [Bool] = []
        c.volley.jingle = { jingles.append($0) }
        c.startVolley(jelly: 0, mode: .match(.shore), seed: 5)
        var rainAtOver = 0.0
        for _ in 0..<(60 * 150) {
            r.step(); c.tickShow(r.actors, dt: 1 / 60); c.tickVolley(r.actors, dt: 1 / 60)
            if c.volley.live, let sm = c.volley.sim {
                if sm.waitingToServe, sm.servingPlayer == sm.controlled { c.volley.sim?.tap() }          // (his own serve; an AI serve goes by itself)
                if sm.phase == .rally, sm.clock > 1 { c.volley.sim?.forcePoint(team: team) }
            }
            if c.volley.hasResults { rainAtOver = c.guestBook.confettiRain; break }
        }
        return (jingles, c.volley.winMusic, rainAtOver, c.volley.hasResults)
    }

    func testWinPlaysTheRaceJingleAndConfettiOnce() {
        let w = play(winner: 0)
        XCTAssertTrue(w.over)
        XCTAssertEqual(w.jingles, [true], "one win jingle (the race's), no second piece of music")
        XCTAssertTrue(w.winMusic, "the court track steps out for the results scene")
        XCTAssertGreaterThan(w.rain, 0, "the arrival's confetti burst, the race win's")
    }

    func testLossPlaysNeither() {
        let l = play(winner: 1)
        XCTAssertTrue(l.over)
        XCTAssertEqual(l.jingles, []); XCTAssertFalse(l.winMusic); XCTAssertEqual(l.rain, 0)
    }
}
