//
//  VoiceFocusTests.swift
//  Voice "come" goes to the focus close-up of the Jelly meant: a name -> that Jelly, plain "come here" -> the targeted Jelly, "everyone" -> the row.
//  Grumpy Jellies always come.
//

import XCTest
@testable import BobV1

@MainActor
private final class VClock { var t: Double = 100 }
@MainActor
private final class NoMic: SpeechInput {
    var availability: VoiceAvailability = .ready
    var onLevel: ((Float) -> Void)?
    func prepare(contextualWords: [String]) async {}
    func start(contextualWords: [String]) async throws { throw SpeechInputError.notReady }
    func stop() async -> String { "" }
}

@MainActor
final class VoiceFocusTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var clock = VClock()

    private func make(roll: Double = 0) -> FocusAnyRun {
        RoomLayout.dynamicBoxes = []
        let c = VClock(); clock = c
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "VoiceFocusTests")!, persists: false, random: { roll })
        let v = VoiceCoordinator(training: training, input: NoMic(), now: { c.t })
        let r = FocusAnyRun(voice: v); Self.keep.append(r)
        for id in 0..<3 { for k in NeedKind.allCases { r.care.needs(for: id).set(k, 1) } }
        r.run(0.3)
        return r
    }
    private func say(_ r: FocusAnyRun, _ words: String) {
        r.run(0.1); clock.t += 0.1
        XCTAssertTrue(r.care.voice.begin(), "the hold opens")
        for _ in 0..<20 { r.run(0.02); clock.t += 0.02 }
        r.care.voice.hear(words)
        r.run(0.2)
    }

    func testNameComesToThatJellysCloseUp() {
        let r = make()
        say(r, "Pip come here")
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused })
        XCTAssertEqual(r.care.focusedJellies, [1])
        XCTAssertEqual(r.care.targetJelly, 1)
    }

    func testPlainComeHereGoesToTheTargetedJelly() {
        let r = make()
        r.care.rosterPick(2, quietHop: true)
        r.run(0.5)
        XCTAssertEqual(r.care.targetJelly, 2)
        say(r, "come here")
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused })
        XCTAssertEqual(r.care.focusedJellies, [2])
    }

    func testEveryoneComeHereFramesTheRow() {
        let r = make()
        say(r, "everyone come here")
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused })
        XCTAssertEqual(r.care.focusedJellies, [0, 1, 2])
    }

    /// A grumpy Jelly comes even when the reliability roll fails.
    func testGrumpyJellyAlwaysComes() {
        let r = make(roll: 0.999)
        for k in NeedKind.allCases { r.care.needs(for: 1).set(k, 0) }
        r.run(0.3)
        XCTAssertEqual(r.care.needs(for: 1).mood, .grumpy)
        say(r, "Pip come here")
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused })
        XCTAssertEqual(r.care.focusedJellies, [1])
    }
}
