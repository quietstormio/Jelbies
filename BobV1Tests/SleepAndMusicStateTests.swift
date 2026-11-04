//
//  SleepAndMusicStateTests.swift
//  Pure state logic: the home-ambience gate (cafe mute clears), the recovery watchdog (music comes back after an interruption), the sleep sounds.
//

import XCTest
@testable import BobV1

final class SleepAndMusicStateTests: XCTestCase {
    func testCafeMuteClearsOnAnyExit() {
        var a: Float = 1
        for _ in 0..<60 { a = HomeAmbience.slew(a, scene: .cafe, dt: 0.05) }
        XCTAssertEqual(a, 0, accuracy: 0.001)
        for scene in [MusicScene.none, .town, .park, .volley] {          // Go home, a town screen or any trip: all bring it back
            var b: Float = 0
            for _ in 0..<60 { b = HomeAmbience.slew(b, scene: scene, dt: 0.05) }
            XCTAssertEqual(b, 1, accuracy: 0.001, "\(scene)")
        }
        XCTAssertEqual(HomeAmbience.slew(1, scene: .cafe, dt: 0.05), 1 - 0.05 / HomeAmbience.fadeSeconds, accuracy: 0.001)          // a fade, not a step
    }

    func testWatchdogRestartsSilentMusicThenRetriesSlowly() {
        var w = MusicWatchdog()
        var fires = 0
        for _ in 0..<(Int(MusicWatchdog.grace / 0.1) + 2) { if w.update(dt: 0.1, shouldPlay: true, isPlaying: false) { fires += 1 } }
        XCTAssertEqual(fires, 1)
        for _ in 0..<40 { if w.update(dt: 0.1, shouldPlay: true, isPlaying: false) { fires += 1 } }          // 4 s later: still waiting
        XCTAssertEqual(fires, 1)
        for _ in 0..<40 { if w.update(dt: 0.1, shouldPlay: true, isPlaying: false) { fires += 1 } }
        XCTAssertEqual(fires, 2)
    }

    func testWatchdogQuietWhenPlayingOrNotWanted() {
        var w = MusicWatchdog()
        for _ in 0..<200 {
            XCTAssertFalse(w.update(dt: 0.1, shouldPlay: true, isPlaying: true))
            XCTAssertFalse(w.update(dt: 0.1, shouldPlay: false, isPlaying: false))
        }
    }

    func testDirectorPlaysAfterInterruptionWhenDecksDied() {
        var d = MusicDirector(length: { _ in 60 }, rand: { 0 })
        for _ in 0..<20 { _ = d.update(dt: 0.25, input: MusicInput(phase: .day)) }
        XCTAssertEqual(d.resumed(deckPlaying: false).count, 1)
    }

    func testSleepSoundsAreRareQuietAndOnlyWhileNapping() {
        var s = SleepSoundScheduler()
        var n = 0, soft = 0
        var t = 100.0
        while t < 400 { for e in s.due(napping: [true, false, false], now: t, random: { $0.lowerBound + ($0.upperBound - $0.lowerBound) * 0.5 }) { n += 1; if e.sound == .softSnore { soft += 1 } }; t += 0.1 }
        XCTAssertGreaterThan(n, 15); XCTAssertLessThan(n, 40)          // about one per 13 s
        XCTAssertLessThanOrEqual(soft, n / 2)
        XCTAssertTrue(s.due(napping: [false, false, false], now: 500, random: { $0.lowerBound }).isEmpty)
        XCTAssertEqual(JellyVoiceSet.sleepCooFile(character: 0, roll: 0.99), "sleep_coo_jelly1_3")
    }
}
