//
//  VoiceIntentTests.swift
//  Names known from the start (base, pet forms, recogniser near-misses, nicknames), the false-hit guard, targets, the built-in social phrases,
//  nickname persistence, and the model fallback with a fake (plus one live model test, skipped when Apple Intelligence is not available).
//

import XCTest
@testable import BobV1

@MainActor
final class VoiceIntentTests: XCTestCase {
    private var suites: [String] = []
    private func suite() -> UserDefaults {
        let n = "VoiceIntentTests.\(UUID().uuidString)"
        suites.append(n)
        return UserDefaults(suiteName: n)!
    }
    override func tearDown() {
        for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }
        suites = []
    }
    private func names(_ d: UserDefaults? = nil) -> JellyNames { JellyNames(defaults: d ?? suite(), key: "nick", persists: true) }
    private func id(_ n: JellyNames, _ said: String) -> Int? { n.resolve(tokens: VoiceMatcher.tokens(said)).first?.id }

    // MARK: names

    func testBaseNamesAndPetForms() {
        let n = names()
        for (said, want) in [("Bob", 0), ("Bobby", 0), ("Bobbie", 0), ("Bobo", 0), ("Bobster", 0), ("Bob-bob", 0), ("bob bob", 0),
                             ("Pip", 1), ("Pippy", 1), ("Pipster", 1), ("Pipsqueak", 1), ("Pippie", 1),
                             ("Moss", 2), ("Mossy", 2), ("Mossie", 2), ("Mossmoss", 2), ("Mosso", 2)] {
            XCTAssertEqual(id(n, said), want, said)
        }
    }

    func testRecogniserNearMissesAreNames() {
        let n = names()
        for (said, want) in [("Bab", 0), ("Bop", 0), ("Bub", 0), ("Pep", 1), ("Pit", 1), ("Peep", 1), ("Moth", 2), ("Mos", 2), ("Mauss", 2)] {
            XCTAssertEqual(id(n, said), want, said)
        }
    }

    func testCommonWordsAreNotNames() {
        let n = names()
        for said in ["bad", "bat", "bit", "bed", "big", "bag", "bug", "bud", "boy", "baby", "back", "bib", "boob", "pop", "pup", "pub", "pet", "pot", "put", "pick",
                     "pin", "pill", "pipe", "sit", "pat", "most", "mass", "miss", "mess", "mouse", "moose", "maze", "boss", "toss", "job", "rob", "mom", "come", "here",
                     "good", "stop", "jump", "run", "flip", "look", "play", "no", "water", "hello", "cute", "love"] {
            XCTAssertNil(id(n, said), said)
        }
        XCTAssertNil(id(n, "come here good boy"))
    }

    func testRegistryIsPerJellyIdNotBobOnly() {
        let n = names()
        XCTAssertEqual(JellyNameRoster.all.map(\.id), [0, 1, 2, 3])
        XCTAssertEqual(JellyNameRoster.all.map(\.display), ["Bob", "Pip", "Moss", "Lavender"])          // Lavender joined with the characters round
        XCTAssertEqual(n.displayName(3), "Lavender")
        XCTAssertEqual(n.resolve(tokens: ["lavender", "come", "here"]).rest, ["come", "here"])
        XCTAssertEqual(n.displayName(1), "Pip")
        XCTAssertEqual(n.resolve(tokens: ["pip", "come", "here"]).rest, ["come", "here"])
    }

    func testNicknamesPersistPerJellyAndMatchFuzzily() {
        let d = suite()
        let n = names(d)
        XCTAssertTrue(n.addNickname("Bubbles", for: 1))
        XCTAssertTrue(n.addNickname("Mister Squish", for: 2))
        XCTAssertTrue(n.addNickname("pie", for: 0))
        XCTAssertFalse(n.addNickname("bobby", for: 1), "already a name")
        XCTAssertFalse(n.addNickname("bubbles", for: 0), "another Jelly's nickname")
        XCTAssertFalse(n.addNickname("", for: 0))
        XCTAssertFalse(n.addNickname("a b c", for: 0), "at most two words")
        let again = names(d)                                          // a new launch
        XCTAssertEqual(again.nicknames(for: 1), ["bubbles"])
        XCTAssertEqual(again.nicknames(for: 2), ["mister squish"])
        XCTAssertEqual(again.nicknames(for: 0), ["pie"])
        XCTAssertEqual(id(again, "bubbles"), 1)
        XCTAssertEqual(id(again, "Bubble"), 1, "one edit away (6+ letter nickname)")
        XCTAssertEqual(id(again, "hey mister squish"), 2, "two-word nickname")
        XCTAssertEqual(id(again, "pie"), 0)
        XCTAssertNil(id(again, "pine"), "short nicknames are exact only (pie vs pine)")
        again.removeNickname("bubbles", for: 1)
        XCTAssertEqual(names(d).nicknames(for: 1), [])
        XCTAssertTrue(again.contextualWords.contains("pie"))
    }

    func testVoiceResetClearsNicknames() {
        let d = suite()
        _ = { let n = names(d); n.addNickname("bubbles", for: 1) }()
        d.set(true, forKey: "VoiceReset")
        XCTAssertEqual(names(d).nicknames(for: 1), [])
    }

    // MARK: parsing / targets / social phrases

    private func training() -> VoiceTraining { VoiceTraining(defaults: suite(), persists: false, random: { 0 }) }
    private func decide(_ v: VoiceTraining, _ said: String, mood: BlobMood = .happy, running: VoiceTrick? = nil) -> VoiceDecision {
        v.decideFull(transcript: said, runningMove: running, mood: mood, session: 1)
    }

    func testTargets() {
        let v = training()
        XCTAssertEqual(decide(v, "come here").target, .selected)
        XCTAssertEqual(decide(v, "Pip, come here").target, .jelly(1))
        XCTAssertEqual(decide(v, "Pip, come here").reaction, .perform(.come))
        XCTAssertEqual(decide(v, "hey Moss come").target, .jelly(2))
        XCTAssertEqual(decide(v, "everyone, come here").target, .everyone)
        XCTAssertEqual(decide(v, "everybody over here").target, .everyone)
        XCTAssertEqual(decide(v, "you guys come here").reaction, .perform(.come))
        XCTAssertEqual(decide(v, "all of you come here").target, .everyone)
        XCTAssertEqual(decide(v, "Bobby").reaction, .nameHeard)
        XCTAssertEqual(decide(v, "Bobby").target, .jelly(0))
        XCTAssertEqual(decide(v, "everyone").target, .everyone)
    }

    /// Two or more named in one breath: exactly those, in the order said, whatever the filler ("and", commas, "come" before or after).
    func testSeveralNamedAreTheTarget() {
        let v = training()
        v.names.roster = [0, 1, 2, 3]          // slot == character, whatever roster the host app launched with
        for (said, want) in [("come here Pip and Moss", [1, 2]), ("Pip and Lavender come here", [1, 3]), ("Moss, Pip, come here", [2, 1]),
                             ("come Pip and Moss", [1, 2]), ("Pip and Moss, come here", [1, 2]), ("hey Moss and Pip come", [2, 1]),
                             ("come here Pip, Moss and Lavender", [1, 2, 3])] {
            let d = decide(v, said)
            XCTAssertEqual(d.target, .jellies(want), said)
            XCTAssertEqual(d.reaction, .perform(.come), said)
        }
        XCTAssertEqual(decide(v, "Pip and Pip come here").target, .jelly(1), "one name said twice is one Jelbie")
        XCTAssertEqual(decide(v, "everyone, Pip and Moss come here").target, .everyone)
        XCTAssertEqual(decide(v, "Pip and Moss").reaction, .nameHeard)
        XCTAssertEqual(decide(v, "Pip and Moss").target, .jellies([1, 2]))
        XCTAssertEqual(decide(v, "good night Pip and Moss").target, .jellies([1, 2]))
        XCTAssertEqual(decide(v, "good night Pip and Moss").reaction, .social(.goodnight))
    }

    func testSeveralNamedRulesParserAndTargetMapping() {
        let n = names()
        n.roster = [0, 1, 2, 3]
        let cat = AICatalogRegistry.catalog(jellies: [(0, "Bob"), (1, "Pip"), (2, "Moss"), (3, "Lavender")])
        for (said, want) in [("come here Pip and Moss", [1, 2]), ("Pip and Lavender come here", [1, 3]), ("Moss, Pip, come here", [2, 1]), ("come Pip and Moss", [1, 2])] {
            let r = RuleParser.parse(said, names: n, catalog: cat)
            XCTAssertEqual(r.command.who, .jellies(want), said)
            XCTAssertEqual(r.command.action, .come, said)
            XCTAssertEqual(r.command.who.asVoiceTarget, .jellies(want), said)
        }
        XCTAssertEqual(JellyWho.jellies([2]).asVoiceTarget, .jelly(2))
        XCTAssertEqual(VoiceTarget.named([]), .selected)
    }

    func testWakeUpPhrasesBeatPraiseAndKeepTheirTargets() {
        let v = training()
        for said in ["wake up", "rise and shine", "good morning", "time to get up", "wakey wakey"] {
            XCTAssertEqual(decide(v, said).reaction, .social(.wakeUp), said)
        }
        XCTAssertEqual(decide(v, "wake up everyone").target, .everyone)
        XCTAssertEqual(decide(v, "wake up").target, .selected)
        XCTAssertEqual(decide(v, "good morning Pip").reaction, .social(.wakeUp))
        XCTAssertEqual(decide(v, "good morning Pip").target, .jelly(1))
        XCTAssertEqual(decide(v, "good boy").reaction, .social(.praise), "good boy stays praise")
        XCTAssertEqual(decide(v, "goodnight").reaction, .social(.goodnight))
    }

    func testGoodnightPhrasesBeatPraiseAndKeepTheirTargets() {
        let v = training()
        for said in ["goodnight", "good night", "Good night!", "night night", "nighty night", "bedtime", "it's bedtime", "time for bed", "go to sleep", "sleep tight", "sweet dreams", "lights out"] {
            XCTAssertEqual(decide(v, said).reaction, .social(.goodnight), said)
        }
        XCTAssertEqual(decide(v, "good night everyone").target, .everyone)
        XCTAssertEqual(decide(v, "goodnight everybody").target, .everyone)
        XCTAssertEqual(decide(v, "Pip goodnight").target, .jelly(1))
        XCTAssertEqual(decide(v, "goodnight").target, .selected)
        XCTAssertEqual(decide(v, "good boy").reaction, .social(.praise), "praise is untouched")
        XCTAssertEqual(decide(v, "stop").reaction, .social(.stop))
        XCTAssertNotEqual(decide(v, "night").reaction, .social(.goodnight), "a lone word is not a command")
        XCTAssertFalse(decide(v, "goodnight").noMatch, "deterministic: no model needed")
    }

    func testSocialPhrases() {
        let v = training()
        let table: [(String, VoiceSocial)] = [
            ("stop fighting", .stopFighting), ("break it up", .stopFighting), ("be nice", .stopFighting), ("play nice", .stopFighting),
            ("hey, quit it", .stopFighting), ("no fighting", .stopFighting),
            ("stop", .stop), ("stay", .stop), ("freeze", .stop), ("stay put", .stop),
            ("good boy", .praise), ("good girl", .praise), ("you're so cute", .praise), ("I love you", .praise), ("well done", .praise), ("great job", .praise),
            ("no", .scold), ("bad", .scold), ("don't", .scold), ("bad boy", .scold), ("naughty", .scold),
            ("let's play", .play), ("want to play", .play),
        ]
        for (said, want) in table { XCTAssertEqual(decide(v, said).reaction, .social(want), said) }
        XCTAssertEqual(decide(v, "Pip stop fighting").target, .jelly(1))
        XCTAssertEqual(decide(v, "good boy, come here").reaction, .perform(.come), "come wins over praise")
        XCTAssertEqual(decide(v, "banana").reaction, .puzzled)
        XCTAssertTrue(decide(v, "banana").noMatch, "free phrasing may go to the model")
        XCTAssertFalse(decide(v, "good boy").noMatch)
    }

    func testGrumpyRefusesTricksAndPlayButNotComeOrComfort() {
        let v = training()
        v.debugLearn(.sit, word: "sit")
        XCTAssertEqual(decide(v, "come here", mood: .grumpy).reaction, .perform(.come))
        XCTAssertEqual(decide(v, "Pip come", mood: .grumpy).reaction, .perform(.come))
        XCTAssertEqual(decide(v, "sit", mood: .grumpy).reaction, .grumpyIgnore)
        XCTAssertEqual(decide(v, "let's play", mood: .grumpy).reaction, .grumpyIgnore)
        XCTAssertEqual(decide(v, "good boy", mood: .grumpy).reaction, .social(.praise))
    }

    func testReservedSocialWordsAreNotTaughtAsTricks() {
        let v = training()
        XCTAssertEqual(decide(v, "good boy", running: .sit).reaction, .social(.praise))
        XCTAssertNil(v.word(for: .sit))
        XCTAssertEqual(decide(v, "mochi", running: .sit).reaction, .learnedStep(.sit, reps: 1), "a teaching word still binds before the model")
    }

    // MARK: model mapping rules

    func testModelTrickMustAlreadyBeLearned() {
        let v = training()
        XCTAssertEqual(v.decide(model: .trick(.flip), target: .selected, mood: .happy).reaction, .puzzled, "not learned: confused")
        v.debugLearn(.flip, word: "wheee")
        XCTAssertEqual(v.decide(model: .trick(.flip), target: .selected, mood: .happy).reaction, .perform(.flip), "learned under ANY word")
        XCTAssertEqual(v.decide(model: .come, target: .everyone, mood: .grumpy).reaction, .perform(.come))
        XCTAssertEqual(v.decide(model: .social(.praise), target: .jelly(2), mood: .happy).target, .jelly(2))
        XCTAssertEqual(v.decide(model: .none, target: .selected, mood: .happy).reaction, .puzzled)
    }

    func testBudgetRaceTimesOut() async {
        do {
            _ = try await VoiceCoordinator.withBudget(0.05) { try await Task.sleep(nanoseconds: 2_000_000_000); return 1 }
            XCTFail("should time out")
        } catch { XCTAssertEqual(error as? VoiceModelError, .timedOut) }
        let v = try? await VoiceCoordinator.withBudget(1) { 7 }
        XCTAssertEqual(v, 7)
    }

    // MARK: live model (skipped unless the runtime has Apple Intelligence)

    func testLiveModelMapsFreePhrasing() async throws {
        guard let model = VoiceIntentModels.make(), model.availability.isAvailable else {
            throw XCTSkip("Foundation Models not available here: \(VoiceIntentModels.make()?.availability ?? .unavailable("no framework"))")
        }
        model.prewarm()
        for (said, want) in [("do a backflip for me", VoiceAction.trick(.flip)), ("who wants to come see me", .come), ("you are such a good boy", .social(.praise))] {
            let t0 = CACurrentMediaTime()
            let r: ModelIntent
            do { r = try await model.interpret(said, learned: [.flip, .sit], names: ["Bob", "Pip", "Moss"]) }
            catch { throw XCTSkip("Foundation Models cannot generate here (no model assets on this runtime): \(error)") }
            print("LIVEMODEL \"\(said)\" -> \(r.action) target \(r.targetKind) conf \(r.confidence) in \(Int((CACurrentMediaTime() - t0) * 1000)) ms")
            XCTAssertEqual(r.action, want, said)
        }
    }
}
