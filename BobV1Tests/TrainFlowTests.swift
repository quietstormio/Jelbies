//
//  TrainFlowTests.swift
//  The close-up's voice trick training end to end (r1023-train): Train -> pick a trick -> he does it -> the mic opens by itself -> three reps fill the pips ->
//  "learned" -> Try it (no demo) -> he does it; unknown / empty / different words say why and never restart a lesson silently; books are per character and
//  saved; a learned word in the room goes to the named / highlighted Jelbie, else to every Jelbie who knows it; no word is ever bound outside a session.
//  A fake mic ("hear") stands for the recogniser. Slots are Bob 0, Pip 1, Moss 2 (FocusAnyRun's default roster).
//

import XCTest
import simd
@testable import BobV1

@MainActor
private final class TFClock { var t: Double = 100 }

@MainActor
final class TrainFlowTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    private let clock = TFClock()
    private func make() -> FocusAnyRun {
        let c = clock
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "TrainFlowTests")!, persists: false, random: { 0 })
        let voice = VoiceCoordinator(training: training, input: FakeSpeechInput(), now: { c.t })
        let r = FocusAnyRun(voice: voice)
        Self.keep.append(r)
        for id in 0..<3 { for k in NeedKind.allCases { r.care.needs(for: id).set(k, 1) } }
        for id in 1..<3 { r.care.jelly(id)!.training.unlocked = { _ in true } }
        r.run(1.0)
        return r
    }
    @discardableResult
    private func go(_ r: FocusAnyRun, _ s: Float, until: (() -> Bool)? = nil) -> Bool {
        for _ in 0..<Int(s * 60) { r.tick(); clock.t += Double(1.0 / 60); if let until, until() { return true } }
        return until?() ?? false
    }
    private func train(_ r: FocusAnyRun, _ id: Int) {
        r.care.beginTraining(id)
        XCTAssertTrue(go(r, 30) { r.care.voice.train != nil }, "the Train card starts on arrival")
        XCTAssertEqual(r.care.voice.train?.step, .pick)
    }
    /// Waits for the auto-opened listen of the current step and says `words` in it.
    private func say(_ r: FocusAnyRun, _ words: String, file: StaticString = #filePath, line: UInt = #line) {
        let v = r.care.voice
        XCTAssertTrue(go(r, 8) { v.train?.step.isListening == true && v.isListening }, "the mic opens by itself (step \(v.train?.step.name ?? "nil"))", file: file, line: line)
        go(r, 0.4)
        v.hear(words)
        go(r, 0.1)
    }
    private func book(_ r: FocusAnyRun, _ id: Int) -> VoiceTraining { r.care.jelly(id)!.training }

    func testTrainSitFullFlow() {
        let r = make(); let v = r.care.voice
        train(r, 1)
        v.trainPick(.sit)
        XCTAssertEqual(v.train?.step, .demo(.sit))
        var sat = false
        for i in 1...VoiceTuning.repsToLearn {
            XCTAssertTrue(go(r, 8) { if r.actors[1].brain!.idleState.kind == .sit { sat = true }; return v.train?.step == .listen(.sit) }, "rep \(i): demo then listen")
            XCTAssertTrue(sat, "he did the move to be named")
            XCTAssertEqual(v.train.map { TrainSession.headline($0.step, name: "Pip", word: { book(r, 1).word(for: $0) ?? $0.suggestion }, reps: { book(r, 1).progress($0) }) },
                           "Say \u{201C}\(i == 1 ? "sit" : "sit")\u{201D} now. \(i - 1) of 3")
            say(r, "sit")
            XCTAssertEqual(book(r, 1).lesson(.sit).reps, i, "pip \(i)")
            if i < VoiceTuning.repsToLearn { XCTAssertEqual(v.train?.step, .heard(.sit, reps: i)); sat = false }
        }
        XCTAssertEqual(v.train?.step, .learned(.sit))
        XCTAssertTrue(book(r, 1).isLearned(.sit))
        XCTAssertFalse(book(r, 0).lesson(.sit).started, "Bob is untouched")
        XCTAssertFalse(book(r, 2).lesson(.sit).started, "Moss is untouched")
        // Try it: no demo, he does it
        XCTAssertTrue(go(r, 8) { v.train?.step == .tryIt(.sit) })
        r.actors[1].brain!.idleReset(r.actors[1].skinner)
        let sitsBefore = r.actors[1].brain!.idleState.kind
        XCTAssertNotEqual(sitsBefore, .sit, "no demo before the try-it")
        say(r, "sit")
        XCTAssertEqual(v.train?.step, .tried(.sit, ok: true, heard: "sit"))
        XCTAssertTrue(go(r, 4) { r.actors[1].brain!.idleState.kind == .sit || r.actors[1].brain!.commandedIdle == .sit }, "the try-it always performs")
    }

    func testTrainJacksSecondTrickWithOwnWord() {
        let r = make(); let v = r.care.voice
        train(r, 2)
        v.trainPick(.jacks)
        for i in 1...VoiceTuning.repsToLearn {
            XCTAssertTrue(go(r, 8) { v.train?.step == .listen(.jacks) })
            if i > 1 {
                let bk = book(r, 2)
                XCTAssertTrue(TrainSession.headline(v.train!.step, name: "Moss", word: { bk.word(for: $0) ?? "" }, reps: { bk.progress($0) }).contains("boing"), "the prompt uses his word")
            }
            say(r, "boing")
        }
        XCTAssertTrue(book(r, 2).isLearned(.jacks))
        XCTAssertEqual(book(r, 2).word(for: .jacks), "boing")
        XCTAssertTrue(go(r, 8) { v.train?.step == .tryIt(.jacks) })
        say(r, "boing")
        XCTAssertEqual(v.train?.step, .tried(.jacks, ok: true, heard: "boing"))
        XCTAssertTrue(go(r, 4) { r.actors[2].brain!.idleState.kind == .jacks || r.actors[2].brain!.commandedIdle == .jacks })
    }

    func testLateWordStillCountsInTrain() {
        let r = make(); let v = r.care.voice
        train(r, 1); v.trainPick(.sit)
        XCTAssertTrue(go(r, 8) { v.train?.step == .listen(.sit) })
        r.actors[1].brain!.idleReset(r.actors[1].skinner)          // the move is over before the word
        XCTAssertNotEqual(r.actors[1].brain!.idleState.kind, .sit)
        say(r, "sit")
        XCTAssertEqual(book(r, 1).lesson(.sit).reps, 1, "a late word still counts: the demo already showed the move")
    }

    func testRunTeachableInCloseUp() {
        let r = make(); let v = r.care.voice
        train(r, 1); v.trainPick(.run)
        XCTAssertTrue(go(r, 8) { v.train?.step == .listen(.run) })
        say(r, "zoom")
        XCTAssertEqual(book(r, 1).lesson(.run).reps, 1, "run (a hop in the close-up) counts reps")
        XCTAssertEqual(book(r, 1).word(for: .run), "zoom")
    }

    func testDifferentWordDoesNotSilentlyRestart() {
        let r = make(); let v = r.care.voice
        train(r, 1); v.trainPick(.jacks)
        XCTAssertTrue(go(r, 8) { v.train?.step == .listen(.jacks) })
        say(r, "boing")
        XCTAssertTrue(go(r, 8) { v.train?.step == .listen(.jacks) })
        say(r, "set")
        XCTAssertEqual(v.train?.step, .missed(.jacks, why: .otherWord(expected: "boing", heard: "set")))
        XCTAssertEqual(book(r, 1).lesson(.jacks).reps, 1)
        XCTAssertEqual(book(r, 1).word(for: .jacks), "boing", "the word is still boing")
        v.trainUseInstead()                                         // the explicit restart
        XCTAssertEqual(book(r, 1).word(for: .jacks), "set")
        XCTAssertEqual(book(r, 1).lesson(.jacks).reps, 1)
    }

    func testUnknownEmptyNameAndReservedWordsSayWhy() {
        let r = make(); let v = r.care.voice
        train(r, 1); v.trainPick(.sit)
        XCTAssertTrue(go(r, 8) { v.train?.step == .listen(.sit) })
        say(r, "")
        XCTAssertEqual(v.train?.step, .missed(.sit, why: .nothing))
        XCTAssertEqual(book(r, 1).lesson(.sit).reps, 0)
        v.trainRetry()
        XCTAssertEqual(v.train?.step, .demo(.sit))
        XCTAssertTrue(go(r, 8) { v.train?.step == .listen(.sit) })
        say(r, "Pip")
        XCTAssertEqual(v.train?.step, .missed(.sit, why: .wasName))
        v.trainRetry()
        XCTAssertTrue(go(r, 8) { v.train?.step == .listen(.sit) })
        say(r, "stop")
        XCTAssertEqual(v.train?.step, .missed(.sit, why: .reserved(heard: "stop")))
        XCTAssertFalse(book(r, 1).lesson(.sit).started, "nothing was bound")
    }

    func testPerCharacterIsolation() {
        let r = make()
        let s = r.care.voice.nextSession()
        for k in 0..<VoiceTuning.repsToLearn { _ = book(r, 1).teachRep(.sit, transcript: "sit", session: s + k) }
        XCTAssertTrue(book(r, 1).isLearned(.sit))
        XCTAssertFalse(book(r, 0).lesson(.sit).started)
        XCTAssertFalse(book(r, 2).lesson(.sit).started)
    }

    func testPersistsAcrossRelaunchPerCharacter() {
        let suite = "TrainFlowPersist"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let a = GameCare(roster: [1, 2, 3], persistent: true, defaults: d)         // characters Pip, Moss, Lavender in slots 0, 1, 2
        for k in 1...VoiceTuning.repsToLearn { _ = a.jelly(0)!.training.teachRep(.sit, transcript: "sit", session: 50 + k) }      // Pip learns sit
        _ = a.jelly(1)!.training.teachRep(.jacks, transcript: "boing", session: 60)                                       // Moss: one rep of jacks
        XCTAssertTrue(a.jelly(0)!.training.isLearned(.sit))
        let b = GameCare(roster: [2, 1, 3], persistent: true, defaults: d)         // a relaunch with the order changed: Pip is now slot 1
        XCTAssertTrue(b.jelly(1)!.training.isLearned(.sit), "the book follows the character, not the slot")
        XCTAssertEqual(b.jelly(1)!.training.lesson(.sit).reps, VoiceTuning.repsToLearn)
        XCTAssertFalse(b.jelly(0)!.training.lesson(.sit).started, "Moss never learned sit")
        XCTAssertEqual(b.jelly(0)!.training.lesson(.jacks).reps, 1, "Moss's half-lesson survived")
        XCTAssertFalse(b.jelly(2)!.training.lesson(.sit).started, "Lavender never learned sit")
        d.removePersistentDomain(forName: suite)
    }

    // MARK: room commands

    private func roomSay(_ r: FocusAnyRun, _ words: String) {
        go(r, 0.1)
        XCTAssertTrue(r.care.voice.begin(), "the hold opens")
        go(r, 0.4)
        r.care.voice.hear(words)
    }
    private func sits(_ r: FocusAnyRun, _ id: Int) -> Bool { r.actors[id].brain!.idleState.kind == .sit || r.actors[id].brain!.commandedIdle == .sit }

    func testRoomPlainWordGoesToAllWhoKnowIt() {
        let r = make()
        book(r, 1).debugLearn(.sit, word: "sit", reliability: 1); book(r, 2).debugLearn(.sit, word: "sit", reliability: 1)
        go(r, 0.5)
        roomSay(r, "sit")
        var seen = Set<Int>()
        go(r, 6) { for id in 0..<3 where self.sits(r, id) { seen.insert(id) }; return seen.count >= 2 }
        XCTAssertEqual(seen, [1, 2], "Pip and Moss sit, Bob (who does not know it) does not")
    }

    func testRoomHighlightedOnlyHim() {
        let r = make()
        book(r, 1).debugLearn(.sit, word: "sit", reliability: 1); book(r, 2).debugLearn(.sit, word: "sit", reliability: 1)
        r.care.rosterPick(1)
        XCTAssertTrue(go(r, 5) { r.care.select.selectedID == 1 || r.care.select.confirmed == 1 })
        roomSay(r, "sit")
        var seen = Set<Int>()
        go(r, 5) { for id in 0..<3 where self.sits(r, id) { seen.insert(id) }; return false }
        XCTAssertEqual(seen, [1], "only the highlighted one")
    }

    func testRoomNamedOnlyThatOne() {
        let r = make()
        book(r, 1).debugLearn(.sit, word: "sit", reliability: 1); book(r, 2).debugLearn(.sit, word: "sit", reliability: 1)
        go(r, 0.5)
        roomSay(r, "\(book(r, 2).names.displayName(2)) sit")
        var seen = Set<Int>()
        go(r, 5) { for id in 0..<3 where self.sits(r, id) { seen.insert(id) }; return false }
        XCTAssertEqual(seen, [2], "only the one named")
    }

    func testNoAccidentalBindingOutsideTrain() {
        let r = make(); let v = r.care.voice
        let b = r.actors[1].brain!
        b.idleReset(r.actors[1].skinner); b.idleForced = true
        XCTAssertTrue(b.idleStart(.sit, r.actors[1].sim))
        roomSay(r, "hello there")
        go(r, 1)
        XCTAssertFalse(book(r, 1).lesson(.sit).started, "a word said while he happens to sit teaches nothing")
        XCTAssertFalse(book(r, 0).lesson(.sit).started)
        XCTAssertNil(v.train)
    }

    func testSessionIdsAreUniqueAcrossBooks() {
        let r = make(); let v = r.care.voice
        book(r, 2).adoptSession(40)
        let s = v.nextSession()
        XCTAssertGreaterThan(s, 40)
        for id in 0..<3 { XCTAssertEqual(book(r, id).sessionCounter, s, "every book moved to \(s)") }
        XCTAssertGreaterThan(v.nextSession(), s)
    }

    func testReliabilityJustAfterLearningIsHighEnough() {
        XCTAssertGreaterThanOrEqual(VoiceTuning.baseReliability, 0.6)
    }
}
