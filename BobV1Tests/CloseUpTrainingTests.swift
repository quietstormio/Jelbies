//
//  CloseUpTrainingTests.swift
//  Voice-trick training in the close-up, per Jelly (W2): the "Train" button's close-up opens THAT Jelly's trick book, a shown trick runs on his own brain,
//  three listens teach his own book (not slot 0's), and a named command out of the close-up goes to the named Jelly.
//

import XCTest
import simd
@testable import BobV1

@MainActor
private final class TClock { var t: Double = 100 }

@MainActor
final class CloseUpTrainingTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    private let clock = TClock()
    private func make() -> FocusAnyRun {
        let c = clock
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "CloseUpTrainingTests")!, persists: false, random: { 0 })
        let voice = VoiceCoordinator(training: training, input: FakeSpeechInput(), now: { c.t })
        let r = FocusAnyRun(voice: voice)
        Self.keep.append(r)
        for id in 0..<3 { for k in NeedKind.allCases { r.care.needs(for: id).set(k, 1) } }
        r.run(1.0)
        return r
    }
    private func go(_ r: FocusAnyRun, _ s: Float, until: (() -> Bool)? = nil) -> Bool {
        for _ in 0..<Int(s * 60) { r.tick(); clock.t += Double(1.0 / 60); if let until, until() { return true } }
        return until?() ?? false
    }
    private func listen(_ r: FocusAnyRun, _ words: String) {
        _ = go(r, 0.1)
        XCTAssertTrue(r.care.voice.begin(), "the hold opens")
        _ = go(r, 0.3)
        r.care.voice.hear(words)
        _ = go(r, 0.3)
    }

    func testBeginTrainingFocusesThatJellyAndOpensHisBook() {
        let r = make()
        r.care.beginTraining(1)
        XCTAssertEqual(r.care.focusedJellies, [1])
        XCTAssertTrue(go(r, 30) { r.care.focus.isFocused }, "Pip arrives")
        _ = go(r, 0.2)
        XCTAssertEqual(r.care.voice.train?.subject, 1, "the Train card started on Pip")
        XCTAssertEqual(r.care.voice.train?.step, .pick)
        XCTAssertEqual(r.care.trainingSubject, 1)
        XCTAssertTrue(r.care.isTrainingCloseUp)
        XCTAssertTrue(r.care.voice.book === r.care.jelly(1)!.training, "the book on screen is Pip's")
        r.care.voice.trainPick(.sit)
        r.care.beginTraining(1)
        XCTAssertEqual(r.care.voice.train?.step, .pick, "Train again in the same close-up starts over at the trick list")
    }

    func testAShownTrickRunsOnTheFocusedJellysBrain() {
        let r = make()
        r.care.beginTraining(1)
        XCTAssertTrue(go(r, 30) { r.care.focus.isFocused })
        r.care.voice.show(.jacks)
        XCTAssertTrue(go(r, 3) { r.actors[1].brain!.idleState.kind == .jacks }, "Pip does the jumping jacks")
        XCTAssertNotEqual(r.actors[0].brain!.idleState.kind, .jacks, "Bob is untouched")
    }

    func testThreeListensTeachTheFocusedJellysOwnBook() {
        let r = make()
        r.care.beginTraining(1)
        XCTAssertTrue(go(r, 30) { r.care.focus.isFocused && r.care.voice.train != nil })
        r.care.voice.trainPick(.jacks)
        for i in 0..<VoiceTuning.repsToLearn {
            XCTAssertTrue(go(r, 8) { r.care.voice.train?.step == .listen(.jacks) && r.care.voice.isListening })
            _ = go(r, 0.4)
            r.care.voice.hear("boing")
            XCTAssertEqual(r.care.jelly(1)!.training.lesson(.jacks).reps, i + 1, "rep \(i + 1) is in Pip's book")
        }
        XCTAssertTrue(r.care.jelly(1)!.training.isLearned(.jacks))
        XCTAssertFalse(r.care.jelly(0)!.training.lesson(.jacks).started, "slot 0's book is untouched")
    }

    func testANamedCommandOutOfTheCloseUpRunsOnThatJelly() {
        let r = make()
        r.care.jelly(2)!.training.debugLearn(.jacks, word: "boing")
        _ = go(r, 0.5)
        listen(r, "\(r.care.voice.book(for: 2).names.displayName(2)) boing")
        XCTAssertTrue(go(r, 3) { r.actors[2].brain!.idleState.kind == .jacks || r.actors[2].brain!.commandedIdle == .jacks }, "Jelly 2 does it")
        XCTAssertNotEqual(r.actors[0].brain!.idleState.kind, .jacks)
    }

    func testEveryBooksLocksFollowTheStore() {
        let r = make()
        for id in 0..<3 { XCTAssertFalse(r.care.jelly(id)!.training.unlocked(.spin), "book \(id): spin is locked until the page is bought") }
        for id in 0..<3 { XCTAssertTrue(r.care.jelly(id)!.training.unlocked(.sit), "book \(id): sit is a starter") }
    }
}
