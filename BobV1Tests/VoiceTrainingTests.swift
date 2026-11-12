//
//  VoiceTrainingTests.swift
//  Commanding: the tricks a Jelbie knows (defaults, bought) obey their plain word, a word taught in the old lessons keeps working with its own reliability,
//  the wrong-trick / ignore split, grumpy, names, persistence. (There is no teaching any more: tricks are bought in the Shop.)
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
    /// A trick taught the old way (a saved lesson): `word`, learned, at `reliability`.
    private func legacy(_ v: VoiceTraining, _ word: String, _ trick: VoiceTrick, _ reliability: Float = 0.6) {
        v.debugLearn(trick, word: word, reliability: reliability)
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


    func testKnownTricksObeyTheirPlainWord() {
        let v = VoiceTraining(defaults: suite(), persists: false, random: { 0 })
        for (said, t) in [("sit", VoiceTrick.sit), ("spin", .spin), ("hop", .hop), ("jump", .jacks), ("jumping jacks", .jacks), ("run", .run), ("sit down", .sit), ("Bob spin", .spin)] {
            XCTAssertEqual(v.decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .perform(t), said)
        }
        XCTAssertEqual(v.reliability(.sit), VoiceTuning.knownReliability, "a trick nobody taught obeys at the known reliability")
        XCTAssertFalse(v.isLearned(.sit), "and no lesson is invented for it")
        // places and sentences are not tricks
        for said in ["sit on the couch", "hop in the bath", "go for a run please now", "have some pizza"] {
            XCTAssertNotEqual(v.decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .perform(.sit), said)
            XCTAssertNotEqual(v.decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .perform(.hop), said)
        }
    }

    /// Longest command word wins; the shop tricks' words never swallow the old ones ("spin", "jump").
    func testShopTrickWordsAndCollisions() {
        let v = VoiceTraining(defaults: suite(), persists: false, random: { 0 })
        for (said, t) in [("spin", VoiceTrick.spin), ("show off", .showOff), ("showoff", .showOff), ("show it off", .showOff), ("sing", .sing), ("sing a song", .sing), ("strut", .strut),
                          ("jump", .jacks), ("jumping jacks", .jacks), ("hop", .hop), ("flip", .flip), ("Bob sing", .sing)] {
            XCTAssertEqual(v.decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .perform(t), said)
        }
        XCTAssertEqual(VoiceTrick.starters, [.sit, .jacks, .run, .flip, .look, .come], "the starters are explicit")
        for t in [VoiceTrick.showOff, .strut, .sing] { XCTAssertFalse(t.isStarter) }
    }

    /// Stage 2: the new moves' words, and the old words they must not swallow ("spin" stays spin, "jump" stays jumping jacks).
    func testStageTwoTrickWordsAndCollisions() {
        let v = VoiceTraining(defaults: suite(), persists: false, random: { 0 })
        for (said, t) in [("hula", VoiceTrick.hula), ("hula dance", .hula), ("super spring", .superSpring), ("spring", .superSpring), ("corkscrew jump", .corkscrew), ("corkscrew", .corkscrew), ("one leg spin", .oneLegSpin), ("pirouette", .oneLegSpin), ("spin", .spin), ("jump", .jacks), ("hop", .hop)] {
            XCTAssertEqual(v.decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .perform(t), said)
        }
        XCTAssertFalse(VoiceTrick.hula.isStarter)
        XCTAssertEqual(JellyAction(key: "hula"), .trick(.hula))
    }

    func testAnOldTaughtWordKeepsWorkingWithItsOwnReliability() {
        let v = VoiceTraining(defaults: suite(), persists: false, random: { 0 })
        legacy(v, "mochi", .sit, 0.6)
        XCTAssertEqual(v.decide(transcript: "mochi", runningMove: nil, mood: .happy, session: 1), .perform(.sit))
        XCTAssertGreaterThan(v.reliability(.sit), 0.6, "a success still nudges a taught word up")
        XCTAssertEqual(v.word(for: .sit), "mochi")
        XCTAssertEqual(v.decide(transcript: "sit", runningMove: nil, mood: .happy, session: 2), .perform(.sit), "the plain word works too")
        XCTAssertTrue(Set(["bob", "pip", "moss", "mochi", "come here", "spin"]).isSubset(of: Set(v.contextualWords)), "names, taught words, command words")
    }

    func testMissSplitsWrongTrickAndIgnore() {
        var wrong = 0, ignored = 0, performed = 0
        let trials = 3000
        let roll = VoiceTraining.seededRoll(42)
        for _ in 0..<trials {
            let v = VoiceTraining(defaults: suite(), persists: false, random: roll)
            legacy(v, "sit", .sit, 0.6)          // a fresh model each trial so the reliability stays 0.6: the miss rate is 40 %
            switch v.decide(transcript: "sit", runningMove: nil, mood: .happy, session: 9) {
            case .perform(.sit): performed += 1
            case .wrongTrick(let said, let did): XCTAssertEqual(said, .sit); XCTAssertNotEqual(did, .sit); wrong += 1
            case .ignore: ignored += 1
            default: XCTFail("unexpected")
            }
        }
        let miss = Double(wrong + ignored)
        XCTAssertEqual(Double(performed) / Double(trials), 0.6, accuracy: 0.04)
        XCTAssertEqual(Double(wrong) / miss, 0.5, accuracy: 0.05)
        XCTAssertEqual(Double(ignored) / miss, 0.5, accuracy: 0.05)
    }

    func testWrongTrickNeedsAnotherKnownTrick() {
        let only = VoiceTraining(defaults: suite(), persists: false, random: { 0.99 })       // always a miss, always the "ignore" half
        only.unlocked = { $0 == .sit }
        XCTAssertEqual(only.decide(transcript: "sit", runningMove: nil, mood: .happy, session: 9), .ignore)
        let w = VoiceTraining(defaults: suite(), persists: false, random: sequence([0.99, 0.1, 0.0]))   // miss, wrong half, first other
        XCTAssertEqual(w.decide(transcript: "sit", runningMove: nil, mood: .happy, session: 9), .wrongTrick(said: .sit, did: .jacks))
    }

    func testGrumpyComeIsAlwaysObeyed() {
        let v = VoiceTraining(defaults: suite(), persists: false, random: { 0.999 })      // would always miss the roll
        for _ in 0..<10 { XCTAssertEqual(v.decide(transcript: "come here", runningMove: nil, mood: .grumpy, session: 9), .perform(.come)) }
        XCTAssertEqual(v.decide(transcript: "come", runningMove: nil, mood: .grumpy, session: 9), .perform(.come))
        XCTAssertEqual(v.decide(transcript: "come here", runningMove: nil, mood: .happy, session: 9), .ignore, "happy still rolls")
    }

    func testGrumpyIgnoresEveryTrickButCome() {
        let v = VoiceTraining(defaults: suite(), persists: false, random: { 0 })          // would always succeed
        legacy(v, "plop", .sit, 0.6)
        for said in ["sit", "plop", "spin"] { XCTAssertEqual(v.decide(transcript: said, runningMove: nil, mood: .grumpy, session: 9), .grumpyIgnore, said) }
        XCTAssertEqual(v.reliability(.sit), 0.6, accuracy: 0.0001, "no success counted")
    }

    func testUnknownWordAndEmptyTranscript() {
        let v = make()
        XCTAssertEqual(v.decide(transcript: "banana", runningMove: nil, mood: .happy, session: 1), .puzzled)
        XCTAssertEqual(v.decide(transcript: "", runningMove: .sit, mood: .happy, session: 1), .ignore)
        XCTAssertEqual(v.decide(transcript: "banana", runningMove: .sit, mood: .happy, session: 1), .puzzled)
    }

    func testNamesAreKnownFromTheStart() {
        let v = VoiceTraining(defaults: suite(), persists: false, random: { 0 })
        XCTAssertTrue(v.nameLearned)
        XCTAssertTrue(v.book.name.learned)
        XCTAssertEqual(v.decide(transcript: "Bob", runningMove: nil, mood: .happy, session: 1), .nameHeard, "first hearing: no lesson")
        XCTAssertEqual(v.decide(transcript: "Bobby", runningMove: nil, mood: .happy, session: 1), .nameHeard)
        XCTAssertEqual(v.decide(transcript: "bob!", runningMove: .sit, mood: .happy, session: 2), .nameHeard, "name alone never binds to a move")
        XCTAssertNil(v.word(for: .sit))
        XCTAssertEqual(v.decide(transcript: "Bob", runningMove: nil, mood: .grumpy, session: 3), .grumpyIgnore)
        // name + trick = the trick
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

    func testPersistenceRoundTripAndReset() {
        let d = suite()
        let a = make(defaults: d)
        let s1 = a.newSession(), s2 = a.newSession()
        XCTAssertNotEqual(s1, s2)
        legacy(a, "mochi", .sit, 0.7)
        let b = make(defaults: d)
        XCTAssertEqual(b.book, a.book)
        XCTAssertTrue(b.isLearned(.sit))
        XCTAssertEqual(b.word(for: .sit), "mochi")
        XCTAssertEqual(b.newSession(), s2 + 1, "session ids keep counting across launches")
        let learned = VoiceTraining.savedLearnedTricks(defaults: d, key: VoiceTuning.defaultsKey)
        XCTAssertTrue(learned.contains(.sit)); XCTAssertTrue(learned.contains(.come))
        d.set(true, forKey: "VoiceReset")
        let c = make(defaults: d)
        XCTAssertEqual(c.book, VoiceBook(name: VoiceTraining.knownName, tricks: ["come": VoiceTraining.innateCome]), "reset leaves the known name and the innate come")
        XCTAssertFalse(c.isLearned(.sit))
    }

    func testUnpersistedModelDoesNotWrite() {
        let d = suite()
        let v = VoiceTraining(defaults: d, persists: false)
        legacy(v, "sit", .sit)
        _ = v.decide(transcript: "sit", runningMove: nil, mood: .happy, session: 1)
        XCTAssertNil(d.data(forKey: VoiceTuning.defaultsKey))
    }

    private func sequence(_ values: [Double]) -> () -> Double {
        var i = 0
        return { defer { i += 1 }; return i < values.count ? values[i] : 0.5 }
    }
}
