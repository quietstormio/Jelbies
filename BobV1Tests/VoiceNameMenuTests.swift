//
//  VoiceNameMenuTests.swift
//  A Jelmiko's name AND a trick / command, in any order, with fillers, split words and mishearings: that Jelmiko does it and the care menu does NOT open
//  (the menu opens for the name by itself only). Table-driven over every trick word x every name x five orders (the decision), plus the real coordinator
//  (the highlight is set, `highlightActs` stays put, the menu is not wanted), the refusal lines, and partial results.
//

import XCTest
@testable import BobV1

@MainActor
private final class MenuClock { var t: Double = 100 }

@MainActor
private final class MenuNoMic: SpeechInput {
    var availability: VoiceAvailability = .ready
    var onLevel: ((Float) -> Void)?
    func prepare(contextualWords: [String]) async {}
    func start(contextualWords: [String]) async throws { throw SpeechInputError.notReady }
    func stop() async -> String { "" }
}

@MainActor
final class VoiceNameMenuTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var suites: [String] = []
    private var savedNames: [String] = []
    private var clock = MenuClock()
    /// The owner's names (real renames of slots 0, 1, 2): ordinary English words on purpose.
    private let owners = ["Alien", "Violet", "Pogo"]

    override func setUp() { savedNames = JellyRoster.names; JellyRoster.names[0] = owners[0]; JellyRoster.names[1] = owners[1]; JellyRoster.names[2] = owners[2] }
    override func tearDown() {
        JellyRoster.names = savedNames
        for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }
        suites = []
    }

    /// Other roster names to run the table over: the species names, and ordinary words (Berry, Tiger are foods / animals).
    private let nameSets = [["Bob", "Pip", "Moss"], ["Berry", "Tiger", "Moss"], ["Alien", "Violet", "Pogo"]]
    private func rename(_ set: [String]) { for i in 0..<3 { JellyRoster.names[i] = set[i] } }

    private func book(roll: Double = 0.99, unlocked: @escaping (VoiceTrick) -> Bool = { _ in true }) -> VoiceTraining {
        let n = "VoiceNameMenuTests.\(UUID().uuidString)"; suites.append(n)
        let v = VoiceTraining(defaults: UserDefaults(suiteName: n)!, persists: false, random: { roll })          // the worst roll: a valid command must still obey
        v.names.roster = [0, 1, 2]
        v.unlocked = unlocked
        return v
    }

    /// The five orders of the brief. `t` is the trick words as said ("moon walk").
    private func orders(_ name: String, _ t: String) -> [String] {
        ["\(name) \(t)", "\(t) \(name)", "\(name) do the \(t)", "hey \(name) can you \(t)", "\(t), \(name)"]
    }

    // MARK: the decision

    func testEveryTrickWordEveryNameEveryOrder() {
        let v = book()
        var n = 0
        for set in nameSets { rename(set)
        for trick in VoiceTrick.allCases where trick != .come {
            for word in trick.commandWords {
                for (slot, name) in set.enumerated() {
                    for said in orders(name, word) {
                        let d = v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 1)
                        XCTAssertEqual(d.reaction, .perform(trick), "\"\(said)\"")
                        XCTAssertEqual(d.target, .named([slot]), "\"\(said)\"")
                        XCTAssertFalse(d.nameOnly, "no menu: \"\(said)\"")
                        n += 1
                    }
                }
            }
        }
        }
        XCTAssertGreaterThan(n, 1500)
    }

    func testSplitFormsAndMishearings() {
        let v = book()
        let cases: [(String, VoiceTrick)] = [
            ("Moonwalk Alien", .moonwalk), ("moonwalk alien", .moonwalk), ("Moon walk Alien", .moonwalk), ("Moonwalk, Alien", .moonwalk), ("moan walk Alien", .moonwalk),
            ("Alien moon walk", .moonwalk), ("Alien do moonwalk", .moonwalk), ("Alien do the moonwalk", .moonwalk), ("Alien, do the moon walk", .moonwalk), ("Alien moonwalking", .moonwalk),
            ("Alien Sing", .sing), ("sing Alien", .sing), ("hey Alien can you sing", .sing), ("Alien sing a song", .sing),
            ("Violet spin", .spin), ("spin Violet", .spin), ("do a spin Violet", .spin), ("Violet, can you please spin around", .spin),
            ("Pogo take a bow", .bow), ("take a bow Pogo", .bow), ("Pogo take bow", .bow), ("Pogo, do a bow", .bow),
            ("belly drum Alien", .bellyDrum), ("Alien belly drum", .bellyDrum), ("Alien drum your belly", .bellyDrum),
            ("Alien dizzy spin", .dizzySpin), ("dizzy spin Alien", .dizzySpin), ("Alien do a dizzy spin", .dizzySpin),
            ("Alien back flip", .flip), ("Alien do a flip", .flip), ("Alien dance", .hula), ("Alien do the hula", .hula),
            ("Alien head stand", .headstand), ("Violet back bounce", .backBounce), ("Pogo one leg spin", .oneLegSpin), ("Alien show off", .showOff),
        ]
        for (said, t) in cases {
            let d = v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 1)
            XCTAssertEqual(d.reaction, .perform(t), "\"\(said)\"")
            XCTAssertFalse(d.nameOnly, "no menu: \"\(said)\"")
            XCTAssertNotEqual(d.target, .selected, "\"\(said)\" names him")
        }
    }

    func testSocialAndComeWithANameNeverOpenTheMenu() {
        let v = book(roll: 0)          // come is a taught lesson at 0.92 (a miss shrugs); the roll is not what is tested here
        let cases: [(String, VoiceReaction)] = [
            ("Alien wave", .social(.wave)), ("say hi Alien", .social(.wave)), ("hey Alien can you wave", .social(.wave)), ("Violet stop", .social(.stop)),
            ("good job Pogo", .social(.praise)), ("Alien go to sleep", .social(.goodnight)), ("Alien come here", .perform(.come)), ("come here Violet", .perform(.come)),
            ("hey Alien come", .perform(.come)),
        ]
        for (said, r) in cases {
            let d = v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 1)
            XCTAssertEqual(d.reaction, r, "\"\(said)\""); XCTAssertFalse(d.nameOnly, "no menu: \"\(said)\"")
        }
    }

    func testTheNameByItselfOpensTheMenu() {
        let v = book()
        for said in ["Alien", "alien", "Alien!", "hey Alien", "oh Alien", "Alien please", "hi Violet", "Pogo"] {
            let d = v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 1)
            XCTAssertTrue(d.nameOnly, "\"\(said)\" opens the menu")
            XCTAssertEqual(d.reaction, .nameHeard, "\"\(said)\"")
        }
        // grumpy: his name alone still opens the menu (so the player can feed him)
        XCTAssertTrue(v.decideFull(transcript: "Alien", runningMove: nil, mood: .grumpy, session: 1).nameOnly)
    }

    func testAnUnknownTrickAndAHungryOneStillNoMenu() {
        let v = book(unlocked: { $0 != .moonwalk })
        for said in orders("Alien", "moonwalk") + ["Moon walk Alien", "moan walk Alien"] {
            let d = v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 1)
            XCTAssertEqual(d.reaction, .dontKnow(.moonwalk), "\"\(said)\"")
            XCTAssertFalse(d.nameOnly, "no menu: \"\(said)\"")
            XCTAssertEqual(d.target, .named([0]), "\"\(said)\"")
        }
        let w = book()
        for said in orders("Alien", "sing") + orders("Violet", "moonwalk") {
            let d = w.decideFull(transcript: said, runningMove: nil, mood: .grumpy, session: 1)
            XCTAssertEqual(d.reaction, .grumpyIgnore, "\"\(said)\"")
            XCTAssertFalse(d.nameOnly, "no menu: \"\(said)\"")
        }
    }

    // MARK: the real coordinator (typed phrase = the heard path; three Jelmiko)

    private func make() -> FocusAnyRun {
        RoomLayout.dynamicBoxes = []
        let c = MenuClock(); clock = c
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "VoiceNameMenuTests")!, persists: false, random: { 0.99 })
        let v = VoiceCoordinator(training: training, input: MenuNoMic(), now: { c.t })
        let r = FocusAnyRun(voice: v); Self.keep.append(r)
        for id in 0..<3 { for k in NeedKind.allCases { r.care.needs(for: id).set(k, 1) }; r.care.jelly(id)?.training.unlocked = { _ in true } }
        r.run(0.3)
        return r
    }
    private func type(_ r: FocusAnyRun, _ words: String) {
        r.run(0.5); clock.t += 0.5
        r.care.voice.typed(words)
        r.run(0.3)
    }
    private func obeyed(_ r: FocusAnyRun, _ t: VoiceTrick) -> Int { r.care.voice.feedbackLog.filter { $0 == .obeyed(t) }.count }

    func testRealCoordinatorHighlightsWithoutTheMenuAndTheNameAloneOpensIt() {
        let tricks: [(VoiceTrick, String)] = [(.moonwalk, "moonwalk"), (.sing, "sing"), (.spin, "spin"), (.bow, "take a bow"), (.bellyDrum, "belly drum"), (.dizzySpin, "dizzy spin")]
        for (i, (trick, word)) in tricks.enumerated() {
            let slot = i % 3
            for said in orders(owners[slot], word) {
                let r = make()
                let acts = r.care.select.highlightActs
                type(r, said)
                XCTAssertNil(r.care.highlightedJelly, "no highlight: \"\(said)\"")
                XCTAssertEqual(r.care.select.highlightActs, acts, "the menu count did not move: \"\(said)\"")
                XCTAssertNil(r.care.highlightedJelly, "no menu: \"\(said)\"")
                XCTAssertEqual(obeyed(r, trick), 1, "does it: \"\(said)\" \(r.care.voice.feedbackLog)")
            }
        }
        for said in ["Alien", "hey Alien", "Alien!"] {
            let r = make()
            let acts = r.care.select.highlightActs
            type(r, said)
            XCTAssertEqual(r.care.targetJelly, 0, "highlighted: \"\(said)\"")
            XCTAssertEqual(r.care.select.highlightActs, acts + 1, "the name alone opens the menu: \"\(said)\"")
            XCTAssertTrue(r.care.select.menuWanted(for: r.care.highlightedJelly), "\"\(said)\"")
        }
        // a command, then his name alone: the quiet highlight does not swallow the next menu
        let r = make()
        type(r, "Moonwalk Alien")
        let acts = r.care.select.highlightActs
        type(r, "Alien")
        XCTAssertEqual(r.care.select.highlightActs, acts + 1); XCTAssertTrue(r.care.select.menuWanted(for: r.care.highlightedJelly))
    }

    func testRealCoordinatorRefusalsSayWhyAndNeverOpenTheMenu() {
        var r = make()
        r.care.jelly(0)?.training.unlocked = { $0 != .moonwalk }
        var acts = r.care.select.highlightActs
        type(r, "Moonwalk Alien")
        XCTAssertNil(r.care.highlightedJelly)
        XCTAssertEqual(r.care.select.highlightActs, acts); XCTAssertNil(r.care.highlightedJelly)
        XCTAssertEqual(r.care.voice.understood?.text, "Alien doesn't know Moonwalk yet")
        r = make()
        for k in NeedKind.allCases { r.care.needs(for: 0).set(k, k == .hunger ? 0 : 1) }
        r.run(0.3)
        acts = r.care.select.highlightActs
        type(r, "Alien moonwalk")
        XCTAssertNil(r.care.highlightedJelly)
        XCTAssertEqual(r.care.select.highlightActs, acts); XCTAssertNil(r.care.highlightedJelly)
        XCTAssertEqual(r.care.voice.understood?.text, "Alien is too hungry for tricks")
    }

    func testTwoWordNamesAndACommandWithNoName() {
        rename(["Cotton Candy", "Lemon-Lime", "Pogo"])
        let v = book()
        for said in ["Cotton Candy", "hey Cotton Candy", "Lemon-Lime!"] {
            XCTAssertTrue(v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 1).nameOnly, "\"\(said)\" opens the menu")
        }
        for said in ["Cotton Candy do a spin", "spin Cotton Candy", "Cotton Candy moonwalk", "Lemon-Lime take a bow", "hey Cotton Candy can you sing"] {
            let d = v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 1)
            XCTAssertFalse(d.nameOnly, "no menu: \"\(said)\""); XCTAssertNotEqual(d.reaction, .nameHeard, "\"\(said)\"")
            XCTAssertNotEqual(d.target, .selected, "\"\(said)\" still names him")
        }
        // a command with no name is unchanged: it goes to whoever is selected
        for said in ["spin", "do a spin", "moonwalk", "take a bow"] {
            let d = v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 1)
            XCTAssertEqual(d.target, .selected, "\"\(said)\""); XCTAssertFalse(d.nameOnly)
        }
    }

    func testRealCoordinatorCommandWithNoNameStillGoesToTheSelectedOne() {
        let r = make()
        r.care.rosterPick(1)
        r.run(0.5)
        type(r, "moonwalk")
        XCTAssertEqual(obeyed(r, .moonwalk), 1, "\(r.care.voice.feedbackLog)")
        XCTAssertEqual(r.care.targetJelly, 1)
    }

    /// The coordinator has NO partial entry point: the recogniser's results only fill a TranscriptAccumulator inside the input, `stop()` returns its final text once, and `release` -> `hear`
    /// decides once. This drives that exact path with a fake input whose stop() returns what the accumulator holds after the partials and the final.
    func testPartialResultsNeverActAndTheFinalTextDecidesOnce() async {
        for (partials, final) in [(["Moonwalk"], "Moonwalk Alien"), (["Alien"], "Alien moonwalk"), (["Moon", "Moonwalk", "Moonwalk Alien"], "Moonwalk Alien")] {
            RoomLayout.dynamicBoxes = []
            let c = MenuClock(); clock = c
            let input = MenuPartialInput()
            let training = VoiceTraining(defaults: UserDefaults(suiteName: "VoiceNameMenuTests")!, persists: false, random: { 0.99 })
            let v = VoiceCoordinator(training: training, input: input, now: { c.t })
            let r = FocusAnyRun(voice: v); Self.keep.append(r)
            for id in 0..<3 { for k in NeedKind.allCases { r.care.needs(for: id).set(k, 1) }; r.care.jelly(id)?.training.unlocked = { _ in true } }
            r.run(0.3)
            let acts = r.care.select.highlightActs
            XCTAssertTrue(v.begin())
            for _ in 0..<20 { r.run(0.02); c.t += 0.02 }
            for p in partials {
                input.feed(p, isFinal: false)
                r.run(0.2); c.t += 0.2
                XCTAssertEqual(r.care.select.highlightActs, acts, "a partial \"\(p)\" opens nothing")
                XCTAssertNil(r.care.select.highlighted, "a partial \"\(p)\" highlights nothing")
                XCTAssertTrue(v.feedbackLog.isEmpty, "a partial \"\(p)\" does nothing")
            }
            input.feed(final, isFinal: true)
            v.release()
            for _ in 0..<100 where v.feedbackLog.isEmpty { try? await Task.sleep(nanoseconds: 50_000_000); r.run(0.05); c.t += 0.05 }
            r.run(0.3)
            XCTAssertEqual(input.stops, 1, "the text is collected once, at the release")
            XCTAssertEqual(r.care.select.highlightActs, acts, "no menu for \"\(final)\"")
            XCTAssertNil(r.care.highlightedJelly, "no highlight")
            XCTAssertEqual(obeyed(r, .moonwalk), 1, "\(v.feedbackLog)")
        }
    }
}

@MainActor
private final class MenuPartialInput: SpeechInput {
    var availability: VoiceAvailability = .ready
    var onLevel: ((Float) -> Void)?
    private var acc = TranscriptAccumulator()
    private(set) var stops = 0
    func feed(_ text: String, isFinal: Bool) { acc.add(text: text, isFinal: isFinal) }
    func prepare(contextualWords: [String]) async {}
    func start(contextualWords: [String]) async throws {}
    func stop() async -> String { stops += 1; return acc.result }
}
