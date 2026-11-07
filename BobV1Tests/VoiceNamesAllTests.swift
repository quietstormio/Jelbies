//
//  VoiceNamesAllTests.swift
//  Every character is called by name with no teaching: all base names, mishearings, word orders around the name, English-word guards,
//  custom names, and the recogniser word list.
//

import XCTest
@testable import BobV1

@MainActor
final class VoiceNamesAllTests: XCTestCase {
    private var suites: [String] = []
    private func suite() -> UserDefaults {
        let n = "VoiceNamesAllTests.\(UUID().uuidString)"
        suites.append(n)
        return UserDefaults(suiteName: n)!
    }
    override func tearDown() {
        for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }
        suites = []
        JellyRoster.names = JellyRoster.baseNames
    }
    private func names(_ d: UserDefaults? = nil) -> JellyNames {
        let n = JellyNames(defaults: d ?? suite(), key: "nick", persists: false)
        n.roster = Array(0..<JellyRoster.baseNames.count)
        return n
    }
    private func id(_ n: JellyNames, _ said: String) -> Int? { n.resolve(tokens: VoiceMatcher.tokens(said)).first?.id }
    private func trained(flip word: String = "flip") -> VoiceTraining {
        let v = VoiceTraining(defaults: suite(), persists: false, random: { 0 })
        v.names.roster = Array(0..<JellyRoster.baseNames.count)          // slot == character, whatever roster the host app launched with
        for s in 1...VoiceTuning.repsToLearn + 2 { _ = v.decide(transcript: word, runningMove: .flip, mood: .happy, session: s) }
        return v
    }

    func testEveryCharacterHasANameEntry() {
        XCTAssertEqual(JellyNameRoster.all.count, JellyRoster.baseNames.count)
        let n = names()
        for (i, raw) in JellyRoster.baseNames.enumerated() {
            XCTAssertEqual(id(n, raw), i, raw)
            XCTAssertEqual(id(n, raw.uppercased() + "!"), i, raw)
            XCTAssertEqual(id(n, "hey \(raw) come here"), i, raw)
        }
    }

    func testMisTranscriptions() {
        let n = names()
        for (said, want) in [("Teddy", 4), ("Tetty", 4), ("Teddie", 4), ("Ted dy", 4), ("Taddy", 4),
                             ("Pearl", 5), ("Purl", 5), ("Pearly", 5), ("Perl", 5), ("pear l", 5),
                             ("Panda", 6), ("Pander", 6), ("Pandy", 6), ("Banda", 6), ("band a", 6), ("pan da", 6), ("Pandas", 6),
                             ("Lavender", 3), ("Lavendar", 3), ("Pip", 1), ("Moss", 2), ("Bob", 0)] {
            XCTAssertEqual(id(n, said), want, said)
        }
    }

    func testCommonWordsAreNotNames() {
        let n = names()
        for said in ["ready set go", "ready", "steady", "tidy", "today", "toady", "pull", "pond", "pants", "panther", "peril", "poorly", "paddy", "toddy"] {
            XCTAssertNil(id(n, said), said)
        }
    }

    func testFlipWithTheNameInEveryOrder() {
        let v = trained()
        XCTAssertTrue(v.isLearned(.flip))
        for said in ["do a flip Panda", "flip panda", "Panda, flip", "Panda can you flip", "hey panda could you please do a flip",
                     "flip Panda please", "Panda do a flip", "um do a flip panda"] {
            let d = v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 99)
            XCTAssertEqual(d.reaction, .perform(.flip), said)
            XCTAssertEqual(d.target, .named([6]), said)
        }
        let plain = v.decideFull(transcript: "flip", runningMove: nil, mood: .happy, session: 99)
        XCTAssertEqual(plain.reaction, .perform(.flip)); XCTAssertEqual(plain.target, .selected, "no name keeps today's behaviour")
    }

    func testCustomNameMatchesWithNoTeaching() {
        let d = suite()
        JellyRoster.names = JellyRoster.baseNames
        JellyRoster.names[6] = "Biscuit"
        JellyRoster.names[4] = "Mister Cuddles"
        let n = names(d)
        XCTAssertEqual(id(n, "Biscuit"), 6)
        XCTAssertEqual(id(n, "biscuits"), 6)
        XCTAssertEqual(id(n, "biscut"), 6, "one edit")
        XCTAssertEqual(id(n, "mister cuddles"), 4)
        XCTAssertEqual(id(n, "Panda"), 6, "the species name still works")
        XCTAssertNil(id(n, "basket"))
        XCTAssertTrue(n.contextualWords.contains("biscuit"))
        XCTAssertTrue(n.contextualWords.contains("mister cuddles"))
    }

    func testEveryNameIsInTheRecogniserListFirst() {
        let n = names()
        n.roster = Array(0..<JellyRoster.baseNames.count)
        let words = n.contextualWords
        for b in JellyRoster.baseNames { XCTAssertTrue(words.prefix(JellyRoster.baseNames.count + 4).contains(b.lowercased()), b) }
        XCTAssertEqual(Array(n.priorityWords.prefix(JellyRoster.baseNames.count)), JellyRoster.baseNames.map { $0.lowercased() })
    }

    func testSavedNicknamesStillWork() {
        let d = suite()
        let n = JellyNames(defaults: d, key: "nick", persists: true)
        n.roster = Array(0..<JellyRoster.baseNames.count)
        XCTAssertTrue(n.addNickname("Bubbles", for: 6))
        let again = JellyNames(defaults: d, key: "nick", persists: true)
        again.roster = Array(0..<JellyRoster.baseNames.count)
        XCTAssertEqual(id(again, "bubbles"), 6)
        XCTAssertTrue(again.priorityWords.contains("bubbles"))
    }
}
