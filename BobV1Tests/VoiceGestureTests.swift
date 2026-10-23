//
//  VoiceGestureTests.swift
//  Double-tap then hold on empty space: the second down within 0.35 s and 40 pt of the previous empty tap-up. Anything on a Blob resets.
//

import XCTest
import CoreGraphics
@testable import BobV1

final class VoiceGestureTests: XCTestCase {
    private let p = CGPoint(x: 200, y: 400)

    func testDoubleTapOnEmptySpaceBegins() {
        var g = VoiceGesture()
        XCTAssertEqual(g.touchDown(time: 0, point: p, hitBlob: false), .none)
        g.tapUp(time: 0.08, downTime: 0.03, point: p, hitBlob: false)
        XCTAssertEqual(g.touchDown(time: 0.25, point: CGPoint(x: 210, y: 410), hitBlob: false), .beginVoice)
    }

    func testTooSlow() {
        var g = VoiceGesture()
        g.tapUp(time: 0, downTime: -0.05, point: p, hitBlob: false)
        XCTAssertEqual(g.touchDown(time: 0.36, point: p, hitBlob: false), .none)
    }

    func testWindowEdge() {
        var g = VoiceGesture()
        g.tapUp(time: 1, downTime: 0.95, point: p, hitBlob: false)
        XCTAssertEqual(g.touchDown(time: 1.35, point: p, hitBlob: false), .beginVoice)
    }

    func testTooFar() {
        var g = VoiceGesture()
        g.tapUp(time: 0, downTime: -0.05, point: p, hitBlob: false)
        XCTAssertEqual(g.touchDown(time: 0.1, point: CGPoint(x: 245, y: 400), hitBlob: false), .none)
        g.tapUp(time: 1, downTime: 0.95, point: p, hitBlob: false)
        XCTAssertEqual(g.touchDown(time: 1.1, point: CGPoint(x: 239, y: 400), hitBlob: false), .beginVoice)
    }

    func testOnBlobResets() {
        var g = VoiceGesture()
        g.tapUp(time: 0, downTime: -0.05, point: p, hitBlob: true)
        XCTAssertEqual(g.touchDown(time: 0.1, point: p, hitBlob: false), .none, "a tap that landed on a Blob never arms it")
        g.tapUp(time: 1, downTime: 0.95, point: p, hitBlob: false)
        XCTAssertEqual(g.touchDown(time: 1.1, point: p, hitBlob: true), .none, "second down on a Blob: pet / hold instead")
        XCTAssertEqual(g.touchDown(time: 1.15, point: p, hitBlob: false), .none, "and it consumed the pending tap")
    }

    func testTapOnBlobBetweenResets() {
        var g = VoiceGesture()
        g.tapUp(time: 0, downTime: -0.05, point: p, hitBlob: false)
        g.tapUp(time: 0.1, downTime: 0.05, point: p, hitBlob: true)
        XCTAssertEqual(g.touchDown(time: 0.2, point: p, hitBlob: false), .none)
    }

    func testOneShotAndTripleTap() {
        var g = VoiceGesture()
        g.tapUp(time: 0, downTime: -0.05, point: p, hitBlob: false)
        XCTAssertEqual(g.touchDown(time: 0.1, point: p, hitBlob: false), .beginVoice)
        XCTAssertEqual(g.touchDown(time: 0.15, point: p, hitBlob: false), .none, "consumed")
    }

    func testSingleTapNeverBegins() {
        var g = VoiceGesture()
        XCTAssertEqual(g.touchDown(time: 5, point: p, hitBlob: false), .none)
        g.reset()
        XCTAssertEqual(g.touchDown(time: 5.1, point: p, hitBlob: false), .none)
    }

    func testLongFirstTapDoesNotArm() {
        var g = VoiceGesture()
        g.tapUp(time: 0.40, downTime: 0, point: p, hitBlob: false)
        XCTAssertEqual(g.touchDown(time: 0.5, point: p, hitBlob: false), .none, "a 0.40 s press is a hold, not a tap")
    }

    func testTapOf0_33Arms() {
        var g = VoiceGesture()
        g.tapUp(time: 0.33, downTime: 0, point: p, hitBlob: false)
        XCTAssertEqual(g.touchDown(time: 0.5, point: p, hitBlob: false), .beginVoice)
    }
}
