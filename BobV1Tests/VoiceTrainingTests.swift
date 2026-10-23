//
//  VoiceTrainingTests.swift
//  Teaching and commanding: reps, sessions, the learned threshold, reliability, wrong-trick / ignore split, grumpy, bound words, persistence.
//

import XCTest
@testable import BobV1

@MainActor
final class VoiceTrainingTests: XCTestCase {
    private var suites: [String] = []

    private func suite() -> UserDefaults {
        let n = "VoiceTrainingTests.\(UUID().uuidString)"
        suites.append(n)
        return UserDefaults(suiteName: n)!
    }
    override func tearDown() {
        for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }
        suites = []
    }
    private func make(seed: UInt64 = 1, defaults: UserDefaults? = nil) -> VoiceTraining {
        VoiceTraining(defaults: defaults ?? suite(), random: VoiceTraining.seededRoll(seed))
    }
    /// Teaches `word` for `trick` over the given sessions (one rep each).
    @discardableResult
    private func teach(_ v: VoiceTraining, _ word: String, _ trick: VoiceTrick, sessions: [Int]) -> VoiceReaction {
        var last = VoiceReaction.ignore
        for s in sessions { last = v.decide(transcript: word, runningMove: trick, mood: .happy, session: s) }
        return last
    }

    func testComeIsLearnedOnFreshInstallAndAfterReset() {
        let d = suite()
        let v = make(defaults: d)
        XCTAssertTrue(v.isLearned(.come))
        XCTAssertEqual(v.word(for: .come), "come here")
        XCTAssertGreaterThanOrEqual(v.reliability(.come), 0.9)
        d.set(true, forKey: "VoiceReset")
        let again = make(defaults: d)
        XCTAssertTrue(again.isLearned(.come), "after -VoiceReset too")
        d.removeObject(forKey: "VoiceReset")
        XCTAssertEqual(again.progress(.come), VoiceTuning.repsToLearn, "the trick book shows it learned")
    }

    func testComeMigratesOldSaves() throws {
        let d = suite()
        var old = VoiceBook()
        var half = VoiceLesson(); half.word = "come here"; half.reps = 2; half.sessions = [1]
        old.tricks["come"] = half
        d.set(try JSONEncoder().encode(old), forKey: VoiceTuning.defaultsKey)
        XCTAssertTrue(make(defaults: d).isLearned(.come), "a half-learned come is completed on load")
        let d2 = suite()
        var own = VoiceBook()
        own.tricks["come"] = Self.learnedLesson("hither", 0.5)
        d2.set(try JSONEncoder().encode(own), forKey: VoiceTuning.defaultsKey)
        let v = make(defaults: d2)
        XCTAssertEqual(v.word(for: .come), "hither", "a word the player taught is kept")
        XCTAssertEqual(v.reliability(.come), 0.5)
    }
    private static func learnedLesson(_ w: String, _ r: Float) -> VoiceLesson {
        var l = VoiceLesson(); l.word = w; l.reps = VoiceTuning.repsToLearn; l.sessions = [0, 1, 2]; l.learned = true; l.reliability = r; return l
    }

    func testComeVariantsPerformAndForgetRestoresIt() {
        let v = VoiceTraining(defaults: suite(), persists: false, random: { 0 })
        for said in ["come here", "come", "Come here Bob", "here boy", "come on", "cum here"] {
            XCTAssertEqual(v.decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .perform(.come), said)
        }
        XCTAssertEqual(v.decide(transcript: "come here", runningMove: nil, mood: .grumpy, session: 1), .perform(.come), "grumpy still comes")
        XCTAssertNotEqual(v.decide(transcript: "home", runningMove: nil, mood: .happy, session: 1), .perform(.come), "no loose 'home'")
        v.forget(.come)
        XCTAssertTrue(v.isLearned(.come), "come is innate")
    }

    func testProgressionAndLearnedThreshold() {
        XCTAssertEqual(VoiceTuning.repsToLearn, 3)
        let v = make()
        XCTAssertEqual(v.decide(transcript: "sit", runningMove: .sit, mood: .happy, session: 1), .learnedStep(.sit, reps: 1))
        XCTAssertEqual(v.word(for: .sit), "sit")
        XCTAssertEqual(v.decide(transcript: "sitt", runningMove: .sit, mood: .happy, session: 2), .learnedStep(.sit, reps: 2), "fuzzy repeats count")
        XCTAssertFalse(v.isLearned(.sit))
        XCTAssertEqual(v.progress(.sit), 2)
        XCTAssertEqual(v.decide(transcript: "Sit!", runningMove: .sit, mood: .happy, session: 3), .trickLearned(.sit))
        XCTAssertTrue(v.isLearned(.sit))
        XCTAssertEqual(v.reliability(.sit), 0.35, accuracy: 0.0001)
        XCTAssertEqual(v.progress(.sit), VoiceTuning.repsToLearn)
    }

    func testOneRepPerListen() {
        let v = make()
        XCTAssertEqual(v.decide(transcript: "sit", runningMove: .sit, mood: .happy, session: 7), .learnedStep(.sit, reps: 1))
        for _ in 0..<5 { XCTAssertEqual(v.decide(transcript: "sit", runningMove: .sit, mood: .happy, session: 7), .learnedStep(.sit, reps: 1)) }
        XCTAssertFalse(v.isLearned(.sit), "saying it again and again in one listen counts once")
        XCTAssertEqual(v.decide(transcript: "sit", runningMove: .sit, mood: .happy, session: 8), .learnedStep(.sit, reps: 2))
        XCTAssertEqual(v.decide(transcript: "sit", runningMove: .sit, mood: .happy, session: 9), .trickLearned(.sit))
    }

    func testReliabilityAtLearnCappedAndGrows() {
        let v = make()
        teach(v, "run", .run, sessions: [1, 2, 3])
        XCTAssertEqual(v.reliability(.run), 0.6, accuracy: 0.0001)
        // successes grow it (reliability 0.95 stays at the cap; use a low one)
        let x = VoiceTraining(defaults: suite(), random: { 0 })      // roll 0 always succeeds
        teach(x, "run", .run, sessions: [1, 2, 3])
        var prev = x.reliability(.run)
        for _ in 0..<5 {
            XCTAssertEqual(x.decide(transcript: "run", runningMove: nil, mood: .happy, session: 9), .perform(.run))
            XCTAssertGreaterThan(x.reliability(.run), prev); prev = x.reliability(.run)
        }
        for _ in 0..<100 { _ = x.decide(transcript: "run", runningMove: nil, mood: .okay, session: 9) }
        XCTAssertEqual(x.reliability(.run), 0.95, accuracy: 0.0001)
    }

    func testMissSplitsWrongTrickAndIgnore() {
        var wrong = 0, ignored = 0, performed = 0
        let trials = 3000
        let roll = VoiceTraining.seededRoll(42)
        for _ in 0..<trials {
            // a fresh model each trial so reliability stays at its learn value (0.35): the miss rate is 65 %
            let v = VoiceTraining(defaults: suite(), persists: false, random: roll)
            teach(v, "sit", .sit, sessions: [1, 2, 3])
            teach(v, "run", .run, sessions: [1, 2, 3])
            teach(v, "look", .look, sessions: [1, 2, 3])
            switch v.decide(transcript: "sit", runningMove: nil, mood: .happy, session: 9) {
            case .perform(.sit): performed += 1
            case .wrongTrick(let said, let did): XCTAssertEqual(said, .sit); XCTAssertNotEqual(did, .sit); wrong += 1
            case .ignore: ignored += 1
            default: XCTFail("unexpected")
            }
        }
        let miss = Double(wrong + ignored)
        XCTAssertEqual(Double(performed) / Double(trials), 0.35, accuracy: 0.04)
        XCTAssertEqual(Double(wrong) / miss, 0.5, accuracy: 0.05)
        XCTAssertEqual(Double(ignored) / miss, 0.5, accuracy: 0.05)
    }

    func testWrongTrickNeedsAnotherLearnedTrick() {
        let v = VoiceTraining(defaults: suite(), random: { 0.99 })       // always a miss, always the "ignore" half
        teach(v, "sit", .sit, sessions: [1, 2, 3])
        XCTAssertEqual(v.decide(transcript: "sit", runningMove: nil, mood: .happy, session: 9), .ignore)
        let w = VoiceTraining(defaults: suite(), random: sequence([0.99, 0.1, 0.0]))   // miss, wrong half, first other
        teach(w, "sit", .sit, sessions: [1, 2, 3])
        teach(w, "run", .run, sessions: [1, 2, 3])
        XCTAssertEqual(w.decide(transcript: "sit", runningMove: nil, mood: .happy, session: 9), .wrongTrick(said: .sit, did: .run))
    }

    func testGrumpyComeIsAlwaysObeyed() {
        let v = VoiceTraining(defaults: suite(), random: { 0.999 })      // would always miss the roll
        for _ in 0..<10 { XCTAssertEqual(v.decide(transcript: "come here", runningMove: nil, mood: .grumpy, session: 9), .perform(.come)) }
        XCTAssertEqual(v.decide(transcript: "come", runningMove: nil, mood: .grumpy, session: 9), .perform(.come))
        XCTAssertEqual(v.decide(transcript: "come here", runningMove: nil, mood: .happy, session: 9), .ignore, "happy still rolls")
    }

    func testGrumpyIgnoresEveryTrickButCome() {
        let v = VoiceTraining(defaults: suite(), random: { 0 })          // would always succeed
        teach(v, "sit", .sit, sessions: [1, 2, 3])
        for _ in 0..<20 { XCTAssertEqual(v.decide(transcript: "sit", runningMove: nil, mood: .grumpy, session: 9), .grumpyIgnore) }
        XCTAssertEqual(v.reliability(.sit), 0.35, accuracy: 0.0001, "no success counted")
    }

    func testPartialWordAndUnknown() {
        let v = make()
        XCTAssertEqual(v.decide(transcript: "banana", runningMove: nil, mood: .happy, session: 1), .puzzled)
        XCTAssertEqual(v.decide(transcript: "", runningMove: .sit, mood: .happy, session: 1), .ignore)
        teach(v, "sit", .sit, sessions: [1, 2])
        XCTAssertEqual(v.decide(transcript: "sit", runningMove: nil, mood: .happy, session: 3), .puzzled, "half-learned word, no move: ?")
        XCTAssertEqual(v.progress(.sit), 2, "and it did not count")
    }

    func testWordBoundElsewhereIsIgnored() {
        let v = make()
        teach(v, "sit", .sit, sessions: [1, 2])
        XCTAssertEqual(v.decide(transcript: "sit", runningMove: .run, mood: .happy, session: 3), .ignore, "half-learned, bound to sit")
        XCTAssertNil(v.word(for: .run))
        teach(v, "sit", .sit, sessions: [3])
        XCTAssertTrue(v.isLearned(.sit))
        // learned word while another move runs is a command, not a rebind
        let r = VoiceTraining(defaults: suite(), random: { 0 })
        teach(r, "sit", .sit, sessions: [1, 2, 3])
        XCTAssertEqual(r.decide(transcript: "sit", runningMove: .run, mood: .happy, session: 5), .perform(.sit))
        XCTAssertNil(r.word(for: .run))
        // a new word while a learned move runs: no rebind in v1
        XCTAssertEqual(r.decide(transcript: "plop", runningMove: .sit, mood: .happy, session: 5), .puzzled)
        XCTAssertEqual(r.word(for: .sit), "sit")
    }

    func testDifferentWordRestartsAHalfLearnedTrick() {
        let v = make()
        teach(v, "sit", .sit, sessions: [1, 2])
        XCTAssertEqual(v.decide(transcript: "plop", runningMove: .sit, mood: .happy, session: 4), .learnedStep(.sit, reps: 1))
        XCTAssertEqual(v.word(for: .sit), "plop")
    }

    func testPlayerWordsAnyLanguageAndNameStripped() {
        let v = make()
        XCTAssertEqual(v.decide(transcript: "Bob, Mochi!", runningMove: .sit, mood: .happy, session: 1), .learnedStep(.sit, reps: 1))
        XCTAssertEqual(v.word(for: .sit), "mochi", "his name is not part of the bound word")
        XCTAssertEqual(v.decide(transcript: "mochee", runningMove: .sit, mood: .happy, session: 2), .learnedStep(.sit, reps: 2))
        XCTAssertEqual(v.decide(transcript: "座って", runningMove: .jacks, mood: .happy, session: 2), .learnedStep(.jacks, reps: 1))
        XCTAssertTrue(Set(["bob", "pip", "moss", "mochi", "座って", "come here"]).isSubset(of: Set(v.contextualWords)), "names + bound words (come here is innate)")
    }

    func testNamesAreKnownFromTheStart() {
        let v = VoiceTraining(defaults: suite(), random: { 0 })
        XCTAssertTrue(v.nameLearned)
        XCTAssertTrue(v.book.name.learned)
        XCTAssertEqual(v.decide(transcript: "Bob", runningMove: nil, mood: .happy, session: 1), .nameHeard, "first hearing: no lesson")
        XCTAssertEqual(v.decide(transcript: "Bobby", runningMove: nil, mood: .happy, session: 1), .nameHeard)
        XCTAssertEqual(v.decide(transcript: "bob!", runningMove: .sit, mood: .happy, session: 2), .nameHeard, "name alone never binds to a move")
        XCTAssertNil(v.word(for: .sit))
        XCTAssertEqual(v.decide(transcript: "Bob", runningMove: nil, mood: .grumpy, session: 3), .grumpyIgnore)
        // name + trick = the trick
        teach(v, "sit", .sit, sessions: [1, 2, 3])
        XCTAssertEqual(v.decide(transcript: "sit down bob", runningMove: nil, mood: .happy, session: 5), .perform(.sit))
        XCTAssertEqual(v.decide(transcript: "bob sit", runningMove: nil, mood: .happy, session: 5), .perform(.sit))
    }

    func testOldSavesWithAHalfLearnedNameAreMigrated() throws {
        for reps in [0, 1, 2] {
            let d = suite()
            var old = VoiceBook()
            old.name.word = "bob"; old.name.reps = reps; old.name.sessions = Array(0..<reps)
            d.set(try JSONEncoder().encode(old), forKey: VoiceTuning.defaultsKey)
            let v = make(defaults: d)
            XCTAssertTrue(v.nameLearned)
            XCTAssertTrue(v.book.name.learned, "reps \(reps): completed on load")
            XCTAssertEqual(v.book.name.reps, VoiceTuning.repsToLearn)
            XCTAssertEqual(make(defaults: d).book.name, VoiceTraining.knownName, "and saved")
        }
    }

    func testForget() {
        let v = make()
        teach(v, "sit", .sit, sessions: [1, 2, 3])
        v.forget(.sit)
        XCTAssertFalse(v.isLearned(.sit))
        XCTAssertNil(v.word(for: .sit))
        XCTAssertEqual(v.progress(.sit), 0)
        XCTAssertEqual(v.decide(transcript: "sit", runningMove: nil, mood: .happy, session: 9), .puzzled)
        XCTAssertEqual(v.decide(transcript: "sit", runningMove: .sit, mood: .happy, session: 9), .learnedStep(.sit, reps: 1), "can be taught again")
    }

    func testPersistenceRoundTripAndReset() {
        let d = suite()
        let a = make(defaults: d)
        let s1 = a.newSession(), s2 = a.newSession()
        XCTAssertNotEqual(s1, s2)
        let s3 = a.newSession()
        teach(a, "mochi", .sit, sessions: [s1, s2, s3])
        teach(a, "run", .run, sessions: [s1])
        XCTAssertTrue(a.nameLearned)
        let b = make(defaults: d)
        XCTAssertEqual(b.book, a.book)
        XCTAssertTrue(b.isLearned(.sit))
        XCTAssertEqual(b.word(for: .sit), "mochi")
        XCTAssertEqual(b.progress(.run), 1)
        XCTAssertTrue(b.nameLearned)
        XCTAssertEqual(b.newSession(), s3 + 1, "session ids keep counting across launches")
        d.set(true, forKey: "VoiceReset")
        let c = make(defaults: d)
        XCTAssertEqual(c.book, VoiceBook(name: VoiceTraining.knownName, tricks: ["come": VoiceTraining.innateCome]), "reset leaves the known name and the innate come")
        XCTAssertFalse(c.isLearned(.sit))
    }

    func testUnpersistedModelDoesNotWrite() {
        let d = suite()
        let v = VoiceTraining(defaults: d, persists: false)
        teach(v, "sit", .sit, sessions: [1])
        XCTAssertNil(d.data(forKey: VoiceTuning.defaultsKey))
    }

    private func sequence(_ values: [Double]) -> () -> Double {
        var i = 0
        return { defer { i += 1 }; return i < values.count ? values[i] : 0.5 }
    }
}
