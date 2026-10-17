//
//  VoiceModeTests.swift
//  The listen-mode state machine: idle -> listening -> processing -> idle, short holds cancel, the glow is a smoothed 0...1.
//

import XCTest
@testable import BobV1

@MainActor
final class VoiceModeTests: XCTestCase {
    private var t = 0.0
    private func make() -> (VoiceMode, Counts) {
        let c = Counts()
        let m = VoiceMode(now: { [unowned self] in self.t })
        m.onOpen = { c.opens += 1 }
        m.onClose = { c.closes += 1 }
        m.onSend = { c.sent.append($0) }
        return (m, c)
    }
    final class Counts { var opens = 0, closes = 0; var sent: [String] = [] }

    func testShortHoldCancels() {
        let (m, c) = make()
        XCTAssertTrue(m.begin())
        XCTAssertTrue(m.isListening)
        t = 0.2
        XCTAssertFalse(m.holdLongEnough)
        XCTAssertEqual(m.end(transcript: "sit"), .cancelled)
        XCTAssertEqual(m.phase, .idle)
        XCTAssertTrue(c.sent.isEmpty)
        XCTAssertEqual(c.opens, 1); XCTAssertEqual(c.closes, 1, "the close tick still plays")
    }

    func testReleaseSends() {
        let (m, c) = make()
        m.begin()
        t = 0.25
        XCTAssertEqual(m.end(transcript: "sit"), .sent("sit"))
        XCTAssertEqual(m.phase, .processing)
        XCTAssertFalse(m.isListening)
        XCTAssertEqual(c.sent, ["sit"])
        m.finish()
        XCTAssertEqual(m.phase, .idle)
        XCTAssertTrue(m.begin(), "ready for the next hold")
    }

    func testBeginOnlyFromIdle() {
        let (m, c) = make()
        XCTAssertTrue(m.begin())
        XCTAssertFalse(m.begin())
        XCTAssertEqual(c.opens, 1)
        t = 1; m.end(transcript: "a")
        XCTAssertFalse(m.begin(), "not while processing")
    }

    func testCancel() {
        let (m, c) = make()
        m.begin(); m.levelUpdate(0.8)
        m.cancel()
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(m.glowLevel, 0)
        XCTAssertTrue(c.sent.isEmpty)
        XCTAssertEqual(c.closes, 1)
        m.cancel()
        XCTAssertEqual(c.closes, 1, "cancel while idle does nothing")
        t = 5; XCTAssertEqual(m.end(transcript: "x"), .cancelled)
    }

    func testGlowSmoothingBounds() {
        let (m, _) = make()
        m.levelUpdate(1)
        XCTAssertEqual(m.glowLevel, 0, "ignored unless listening")
        m.begin()
        m.levelUpdate(1)
        XCTAssertGreaterThan(m.glowLevel, 0)
        XCTAssertLessThan(m.glowLevel, 1, "smoothed, not a jump")
        for _ in 0..<60 { m.levelUpdate(1) }
        XCTAssertEqual(m.glowLevel, 1, accuracy: 0.001)
        m.levelUpdate(0)
        XCTAssertGreaterThan(m.glowLevel, 0.5, "falls slower than it rises")
        for v in [5, -3, Float.nan, Float.infinity, 0.3] as [Float] {
            m.levelUpdate(v)
            XCTAssertTrue(m.glowLevel >= 0 && m.glowLevel <= 1, "stays in 0...1 for \(v)")
        }
    }

    func testGlowZeroAfterRelease() {
        let (m, _) = make()
        m.begin(); m.levelUpdate(1)
        t = 1; m.end(transcript: "")
        XCTAssertEqual(m.glowLevel, 0)
    }
}
