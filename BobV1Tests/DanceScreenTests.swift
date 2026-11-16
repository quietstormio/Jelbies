//
//  DanceScreenTests.swift
//  The trimmed Dance screen's logic: the cheer word of the score card, the song-progress value, and the lane's spacing (two chips half a beat apart never touch).
//

import XCTest
@testable import BobV1

@MainActor
final class DanceScreenTests: XCTestCase {
    func testCheerWordsFollowTheScore() {
        XCTAssertEqual(ShowFlow.danceCheerWord(score: 100), "Great dancing!"); XCTAssertEqual(ShowFlow.danceCheerWord(score: 80), "Great dancing!")
        XCTAssertEqual(ShowFlow.danceCheerWord(score: 79.9), "Nice moves!"); XCTAssertEqual(ShowFlow.danceCheerWord(score: 50), "Nice moves!")
        XCTAssertEqual(ShowFlow.danceCheerWord(score: 49.9), "Good try!"); XCTAssertEqual(ShowFlow.danceCheerWord(score: 0), "Good try!")
    }

    /// Chips are 40 pt, the next one 52 pt: radii 26 + 20 = 46 pt. Every pair of consecutive prompts of every pattern is at least half a beat apart: 48 pt at 96 pt per beat.
    func testNoTwoLaneChipsTouch() {
        var smallest = CGFloat.infinity
        for s in DanceSong.all { for p in DancePattern.allCases {
            for (a, b) in zip(s.prompts(p), s.prompts(p).dropFirst()) {
                let beats = (s.time(ofSlot: b.slot) - s.time(ofSlot: a.slot)) / s.grid.period
                smallest = min(smallest, CGFloat(beats) * PromptLane.pointsPerBeat)
            }
        } }
        XCTAssertGreaterThanOrEqual(smallest, 26 + 20 + 1.9, "closest centres \(smallest) pt")
    }

    func testProgressAndTheDoneState() {
        let f = ShowFlow(); f.cue = { _ in }; f.songClock = { _ in nil }; f.audioReady = { _ in true }
        f.auto = true
        f.begin(playerID: 1, name: "Bob", character: 1, input: ShowPlayerInput(name: "Bob"), rank: .puddle, dayKey: 20261021, bodies: 1, seed: 3)
        XCTAssertEqual(f.danceProgress, 0)
        XCTAssertGreaterThan(f.danceLength, 10); XCTAssertLessThan(f.danceLength, 15)
        for _ in 0..<(40 * 60) where f.beat != .dancing { f.tick(dt: 1 / 60) }
        for _ in 0..<(5 * 60) { f.tick(dt: 1 / 60) }
        XCTAssertGreaterThan(f.danceProgress, 0.2); XCTAssertLessThan(f.danceProgress, 0.7)
        for _ in 0..<(60 * 60) where f.beat != .danced { f.tick(dt: 1 / 60) }
        XCTAssertEqual(f.beat, .danced); XCTAssertEqual(f.danceProgress, 1)
    }
}

extension DanceScreenTests {
    /// "GO!" is gone (song clock) before the first step's chip reaches the word's area, for every song and pattern, in the narrowest lane (a phone on its side: about 422 pt) and the
    /// portrait phone lane (370 pt). The word is about 130 pt wide, centred; the NEXT chip is 52 pt and sits at `18 + ahead * pointsPerBeat` from the lane's left edge.
    func testGoWordIsGoneBeforeTheFirstChipArrives() {
        var fastest = Double.infinity
        for s in DanceSong.all {
            for p in DancePattern.allCases {
                guard let first = s.prompts(p).first else { XCTFail("empty pattern"); continue }
                let beatsAhead = Double(first.slot) / 2          // the first prompt's beat at GO (song time 0)
                for laneW in [370.0, 422.0] {
                    let wordRight = laneW / 2 + 65
                    let aheadAtWord = (wordRight - 18) / Double(PromptLane.pointsPerBeat)
                    let secondsToWord = (beatsAhead - aheadAtWord) * s.grid.period
                    fastest = min(fastest, secondsToWord)
                    XCTAssertGreaterThan(secondsToWord, ShowFlow.goWordSeconds + 0.1, "song \(s.song) \(p) lane \(laneW): chip reaches the word at \(secondsToWord) s")
                }
            }
        }
        print("[gotest] fastest chip arrival at the GO word's area: \(Int(fastest * 1000)) ms after GO; the word is shown \(Int(ShowFlow.goWordSeconds * 1000)) ms of song time")
    }
    func testGoWordFollowsTheDanceClock() {
        let f = ShowFlow(); f.cue = { _ in }; f.songClock = { _ in nil }; f.audioReady = { _ in true }
        f.auto = true
        f.begin(playerID: 1, name: "Bob", character: 1, input: ShowPlayerInput(name: "Bob"), rank: .puddle, dayKey: 20261021, bodies: 1, seed: 3)
        for _ in 0..<(40 * 60) where f.beat != .dancing { f.tick(dt: 1 / 60) }
        XCTAssertEqual(f.beat, .dancing)
        var shown = 0.0
        for _ in 0..<(60 * 3) { f.tick(dt: 1 / 60); if f.showsGo { shown += 1 / 60 } }
        XCTAssertLessThanOrEqual(shown, 2.0 + 0.05, "never longer than 2 s")
        XCTAssertFalse(f.showsGo, "gone after the first seconds")
    }
}
