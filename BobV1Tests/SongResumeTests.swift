//
//  SongResumeTests.swift
//  A dance song whose engine is rebuilt mid-song (route / configuration change, a failed first start) must carry on where the song has got to, not from 0,
//  and must not restart after it is over. Pure frame maths (Audio/SceneMusic.swift `SongResume`).
//

import XCTest
@testable import BobV1

final class SongResumeTests: XCTestCase {
    private let sr = 44100.0, len = 44100 * 60          // a 60 s song

    func testFreshStartBeginsAtFrameZero() {
        XCTAssertEqual(SongResume.startFrame(elapsed: 0, lengthFrames: len, sampleRate: sr), 0)
        XCTAssertEqual(SongResume.startFrame(elapsed: 0.02, lengthFrames: len, sampleRate: sr), 0)          // under the noise floor: from the top
    }

    func testRestartMidSongContinuesAtTheElapsedFrame() {
        XCTAssertEqual(SongResume.startFrame(elapsed: 12.5, lengthFrames: len, sampleRate: sr), Int(12.5 * sr))
        XCTAssertEqual(SongResume.startFrame(elapsed: 30, lengthFrames: len, sampleRate: sr), 30 * 44100)
    }

    func testNoRestartPastTheEndOfTheSong() {
        XCTAssertNil(SongResume.startFrame(elapsed: 60, lengthFrames: len, sampleRate: sr))
        XCTAssertNil(SongResume.startFrame(elapsed: 59.8, lengthFrames: len, sampleRate: sr))          // inside the last half second: it is over
        XCTAssertNil(SongResume.startFrame(elapsed: 500, lengthFrames: len, sampleRate: sr))
    }

    func testEngineStartRetryPolicy() {
        XCTAssertTrue(EngineStartRetry.shouldRetry(attempt: 0))
        XCTAssertTrue(EngineStartRetry.shouldRetry(attempt: EngineStartRetry.maxAttempts - 1))
        XCTAssertFalse(EngineStartRetry.shouldRetry(attempt: EngineStartRetry.maxAttempts))
        XCTAssertLessThanOrEqual(EngineStartRetry.delay * Double(EngineStartRetry.maxAttempts), 4.0)
        XCTAssertLessThanOrEqual(EngineStartRetry.delay, 0.5)          // audible again within a second of the session letting go
    }
}
