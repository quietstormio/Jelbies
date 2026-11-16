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
