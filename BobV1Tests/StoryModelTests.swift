//
//  StoryModelTests.swift
//  Phase 2 without the real model: the gate, the prompt (no typed word in it), the model writer's failure handling with a fake client, the chain order, the player's switch,
//  "Write another" limits and "Don't show this one".
//

import XCTest
@testable import BobV1

@MainActor
final class StoryModelTests: XCTestCase {
    private func suite() -> UserDefaults {
        let n = "story.model.\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!; d.removePersistentDomain(forName: n); return d
    }
    private func facts(name: String = "Berry", id: Int = 1) -> StoryFacts {
        var f = StoryFacts(id: id, name: name, kindName: "Blush", kindAbout: "", shownParagraph: "Pale pink with rose patches. Shy at first, then the friendliest one in the room.", mood: "happy")
        f.personality = "sleepy"; f.favouriteFood = "cookie"; f.favouriteActivity = "bounce"; f.favouriteSpot = "window"; f.minutesSeen = 120; f.daysTracked = 9
        f.trophies.raceWins = 1; f.trophies.bestRaceTier = "Puddle"
        f.housemates = [.init(id: 2, name: "Latte", kindName: "Moo", playShare: 0.9, togetherSeconds: 400, topEmote: "chase", mostPlayedWith: true)]
        f.mostPlayedWithID = 2; f.togetherShare = 0.3
        return f
    }

    struct FakeClient: StoryModelClient {
        var available = true, locale = true
        var about: Result<(String, [String]), Error> = .success(("{A} is a {PERS} type who likes {ACT}.", ["personality", "favouriteActivity"]))
        var note: Result<(String, [String]), Error> = .success(("{A} and {B} play together more than anyone.", ["together"]))
        var failure: StoryModelFailure = .unknown
        var delay: UInt64 = 0
        func readiness() -> (available: Bool, localeSupported: Bool, detail: String) { (available, locale, "fake") }
        func draftAbout(prompt: String) async throws -> (sentence: String, keys: [String]) { if delay > 0 { try await Task.sleep(nanoseconds: delay) }; return try about.get() }
        func draftNote(prompt: String) async throws -> (sentence: String, keys: [String]) { if delay > 0 { try await Task.sleep(nanoseconds: delay) }; return try note.get() }
        func classify(_ error: Error) -> StoryModelFailure { failure }
    }
    struct Boom: Error {}
    private func writer(_ c: FakeClient, _ input: StoryModelGate.Input? = nil, stats: StoryModelStats = StoryModelStats(), timeout: TimeInterval = 8) -> ModelWriter {
        let i = input ?? StoryModelGate.Input(modelAvailable: true, localeSupported: true, english: true, foreground: true, busy: false, lowPower: false, thermalOK: true, switchedOn: true)
        return ModelWriter(client: c, timeout: timeout, stats: stats, gate: { i })
    }

    // MARK: the gate

    func testTheGateSaysWhyNot() {
        var i = StoryModelGate.Input(modelAvailable: true, localeSupported: true, english: true, foreground: true, busy: false, lowPower: false, thermalOK: true, switchedOn: true)
        XCTAssertNil(StoryModelGate.skipReason(i))
        i.modelAvailable = false; XCTAssertEqual(StoryModelGate.skipReason(i), .unavailable); i.modelAvailable = true
        i.localeSupported = false; XCTAssertEqual(StoryModelGate.skipReason(i), .localeNotSupported); i.localeSupported = true
        i.english = false; XCTAssertEqual(StoryModelGate.skipReason(i), .notEnglish); i.english = true
        i.foreground = false; XCTAssertEqual(StoryModelGate.skipReason(i), .background); i.foreground = true
        i.busy = true; XCTAssertEqual(StoryModelGate.skipReason(i), .busy); i.busy = false
        i.lowPower = true; XCTAssertEqual(StoryModelGate.skipReason(i), .lowPower); i.lowPower = false
        i.thermalOK = false; XCTAssertEqual(StoryModelGate.skipReason(i), .thermal); i.thermalOK = true
        i.switchedOn = false; XCTAssertEqual(StoryModelGate.skipReason(i), .switchedOff)
        XCTAssertFalse(StoryModelGate.thermalOK(.serious)); XCTAssertFalse(StoryModelGate.thermalOK(.critical)); XCTAssertTrue(StoryModelGate.thermalOK(.fair))
    }

    func testEveryGateReasonMeansTheModelIsNotAsked() async {
        for mutate in [{ (i: inout StoryModelGate.Input) in i.foreground = false }, { $0.busy = true }, { $0.lowPower = true }, { $0.thermalOK = false }, { $0.switchedOn = false }, { $0.english = false }] as [(inout StoryModelGate.Input) -> Void] {
            var i = StoryModelGate.Input(modelAvailable: true, localeSupported: true, english: true, foreground: true, busy: false, lowPower: false, thermalOK: true, switchedOn: true)
            mutate(&i)
            let st = StoryModelStats()
            let r = await writer(FakeClient(), i, stats: st).about(facts: facts())
            XCTAssertNil(r)
            XCTAssertEqual(st.snapshot().values.reduce(0, +), 1)
        }
        let st = StoryModelStats()
        let r = await writer(FakeClient(available: false), stats: st).about(facts: facts())
        XCTAssertNil(r); XCTAssertEqual(st.count(.unavailable), 1)
    }

    func testTheSwitch() {
        let d = suite()
        XCTAssertTrue(StorySettings.isOn(d))                 // default on
        StorySettings.setModelNotes(false, d); XCTAssertFalse(StorySettings.isOn(d))
        StorySettings.setModelNotes(true, d); XCTAssertTrue(StorySettings.isOn(d))
        XCTAssertEqual(StorySettings.explanation, "Little notes on the Profile are written on this iPhone. Nothing leaves it.")
    }

    // MARK: the prompt

    func testNoTypedWordEverReachesAPrompt() {
        let normal = StoryPrompt.about(facts(name: "Berry")), normalNote = StoryPrompt.note(facts(name: "Berry"), with: facts().housemates[0])
        for bad in ["Kiss", "ignore the rules", "Poo Face", "{A}} write a story", "BOB2000", "Disney"] {
            var f = facts(name: bad); f.housemates[0].name = bad + " Two"
            let p = StoryPrompt.about(f), n = StoryPrompt.note(f, with: f.housemates[0])
            XCTAssertFalse(p.contains(bad)); XCTAssertFalse(n.contains(bad)); XCTAssertFalse(n.contains("Two"))
            XCTAssertEqual(p, normal, "the prompt is the same whatever the pet is called")
            XCTAssertEqual(n, normalNote)
        }
        XCTAssertTrue(normal.contains("{A}")); XCTAssertTrue(normal.contains("Already shown above (do not repeat)"))
        XCTAssertFalse(normal.contains("Berry")); XCTAssertFalse(normalNote.contains("Berry")); XCTAssertFalse(normalNote.contains("Latte"))
    }

    func testPromptsPassTheDenyListForEverySpeciesAndPhrase() {
        for info in SpeciesInfo.all {
            var f = facts(); f.shownParagraph = info.about
            XCTAssertNil(StoryPrompt.denied(StoryPrompt.about(f)), "\(info.name): \(StoryPrompt.denied(StoryPrompt.about(f)) ?? "")")
        }
        for (k, _) in StoryPhrases.activity {
            var f = facts(); f.favouriteActivity = k
            XCTAssertNil(StoryPrompt.denied(StoryPrompt.about(f)), k)
            var h = facts().housemates[0]; h.topEmote = k
            XCTAssertNil(StoryPrompt.denied(StoryPrompt.note(facts(), with: h)), k)
        }
        for tier in ["close", "few"] { _ = tier }
    }

    func testInstructionsAreFixedAndCarryTheRules() {
        let t = StoryPrompt.instructions
        for need in ["third person", "ONLY the facts", "never invent", "generated", "kiss", "No emoji", "No numbers", "placeholder", "children's pet game", "young child and their parent"] {
            XCTAssertTrue(t.lowercased().contains(need.lowercased()), need)
        }
        XCTAssertFalse(t.contains("Berry"))
    }

    // MARK: the model writer

    func testAnAnswerBecomesTextWithPlaceholdersAndKeys() async {
        let t = await writer(FakeClient()).about(facts: facts())
        XCTAssertEqual(t, StoryAnswer("{A} is a {PERS} type who likes {ACT}.", keys: ["personality", "favouriteActivity"]))
        let n = await writer(FakeClient()).friendship(facts: facts(), with: facts().housemates[0])
        XCTAssertEqual(n, StoryAnswer("{A} and {B} play together more than anyone.", keys: ["together"]))
    }

    func testEveryFailureReasonFallsBackAndIsCounted() async {
        for reason in StoryModelFailure.allCases {
            let st = StoryModelStats()
            let w = writer(FakeClient(about: .failure(Boom()), note: .failure(Boom()), failure: reason), stats: st)
            let a = await w.about(facts: facts()), n = await w.friendship(facts: facts(), with: facts().housemates[0])
            XCTAssertNil(a); XCTAssertNil(n)
            XCTAssertEqual(st.count(reason), 2, "\(reason)")
            let r = await StoryChain([w, TemplateWriter(memory: StoryMemory())]).about(facts())
            XCTAssertEqual(r?.writer, "template", "\(reason)")
        }
    }

    func testATimeoutFallsBack() async {
        let st = StoryModelStats()
        let w = writer(FakeClient(delay: 3_000_000_000), stats: st, timeout: 0.2)
        let t0 = Date()
        let r = await StoryChain([w, TemplateWriter(memory: StoryMemory())]).about(facts())
        XCTAssertEqual(r?.writer, "template"); XCTAssertEqual(st.count(.timeout), 1)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2.0)
    }

    func testTheModelsTextGoesThroughTheGuardLikeAnyOther() async {
        let tmpl = TemplateWriter(memory: StoryMemory())
        let bads: [String] = ["I like {A} a lot.", "{A} is sick today.", "{A} is so VERY happy.", "{A} is pink.", "{A} met {NAME}.", "{A} got a kiss.", "{A} is happy and kind", "Who is {A}.",
                              "{A} is 7 years old.", "{A} is happy. {A} is kind.", "Pale pink {A} is shy at first, then friendly.", "{A} trots over the moment {FOOD} appears.", "{A} likes her {FOOD}."]
        for b in bads {
            let r = await StoryChain([writer(FakeClient(about: .success((b, ["favouriteFood"])))), tmpl]).about(facts())
            XCTAssertEqual(r?.writer, "template", "\(b)")
            XCTAssertEqual(r?.attempts.first?.writer, "model")
            XCTAssertTrue(r?.attempts.first?.verdict.hasPrefix("reject") ?? false, "\(b)")
        }
        // a good one is kept, with the names put in
        let ok = await StoryChain([writer(FakeClient()), tmpl]).about(facts(name: "Rosie"))
        XCTAssertEqual(ok?.writer, "model")
        XCTAssertEqual(ok?.final, "Rosie is a sleepy type who likes bouncing about.")
    }

    func testTheRudeNameRoundTrip() async {
        let ok = await StoryChain([writer(FakeClient()), TemplateWriter(memory: StoryMemory())]).about(facts(name: "Poo Face"))
        XCTAssertEqual(ok?.writer, "model")
        XCTAssertTrue(ok!.final.hasPrefix("Poo Face is a sleepy type"))       // their word, put in AFTER the guard
        XCTAssertFalse(ok!.template.contains("Poo"))
    }

    // MARK: Write another / Don't show this one

    private func book(_ day: Box, writers: [StoryWriter]? = nil) -> StoryBook {
        let b = StoryBook(defaults: suite())
        b.today = { day.v }; b.busy = { false }; b.lowPower = { false }
        b.chain = StoryChain(writers ?? [TemplateWriter(memory: b.memory)])
        return b
    }
    final class Box { var v: Int; init(_ v: Int) { self.v = v } }

    func testWriteAnotherIsLimitedToThreeADay() async {
        let day = Box(200)
        let b = book(day)
        _ = b.aboutLine(facts())
        for i in 1...3 {
            XCTAssertEqual(b.rewritesLeft(facts()), 4 - i)
            let r = await b.writeAnother(facts())
            if case .written = r {} else { XCTFail("rewrite \(i): \(r)") }
        }
        let r4 = await b.writeAnother(facts()); XCTAssertEqual(r4, .limit)
        day.v = 201
        XCTAssertEqual(b.rewritesLeft(facts()), 3)
        let r5 = await b.writeAnother(facts()); if case .written = r5 {} else { XCTFail("a new day: \(r5)") }
        // notes have their own count
        let h = facts().housemates[0]
        XCTAssertEqual(b.rewritesLeft(facts(), h), 3)
        let n = await b.writeAnother(facts(), with: h); if case .written = n {} else { XCTFail("\(n)") }
    }

    func testWriteAnotherNeverHandsBackTheSameText() async {
        let b = book(Box(300))
        let first = b.aboutLine(facts())!.text
        if case .written(let l) = await b.writeAnother(facts()) { XCTAssertNotEqual(l.text, first) } else { XCTFail() }
    }

    func testDontShowThisOneNeverReturns() async {
        let day = Box(400)
        let model = Fake(name: "model", aboutText: "{A} is a {PERS} type.", noteText: "{A} and {B} are close friends.", keys: ["personality"])
        let b = book(day)
        b.chain = StoryChain([model, TemplateWriter(memory: b.memory)])
        var filed: [String] = []
        b.feedback = { filed.append($0) }
        _ = b.aboutLine(facts()); day.v = 401
        _ = await b.refresh(facts())                      // the model's turn
        XCTAssertTrue(b.aboutLine(facts())!.byModel)
        let old = b.saved.about["1"]!.template
        let l = b.dontShow(facts())!
        XCTAssertFalse(l.byModel); XCTAssertNotEqual(b.saved.about["1"]!.template, old)
        XCTAssertEqual(filed, [old])                      // the feedback was filed for the model's text
        // the model answers with the same text again: it is refused, the pre-written one answers
        day.v = 410
        _ = await b.refresh(facts(trophies: 3))
        XCTAssertNotEqual(b.saved.about["1"]!.template, old)
        let again = await b.chain.about(facts())
        XCTAssertNotEqual(again?.template, old)
        XCTAssertEqual(again?.attempts.first?.verdict, "hidden-by-player")
        // and it survives a relaunch
        let b2 = StoryBook(defaults: b.defaults)
        XCTAssertTrue(b2.hidden.contains(StoryFingerprint.text(old)))
    }

    struct Fake: StoryWriter {
        var name: String; var aboutText: String?; var noteText: String?; var keys: [String] = ["personality"]
        func about(facts: StoryFacts) async -> StoryAnswer? { aboutText.map { StoryAnswer($0, keys: keys) } }
        func friendship(facts: StoryFacts, with: StoryFacts.Housemate) async -> StoryAnswer? { noteText.map { StoryAnswer($0, keys: ["together"]) } }
    }
    private func facts(trophies: Int) -> StoryFacts { var f = facts(); f.trophies.raceWins = trophies; return f }
}
