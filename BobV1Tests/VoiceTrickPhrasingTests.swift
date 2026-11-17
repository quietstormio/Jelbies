//
//  VoiceTrickPhrasingTests.swift
//  Every trick starts by voice however it is said or written ("Alien do the moonwalk", "moon-walk Alien", "Alien, sing!"); a trick the Jelmiko
//  was never given answers "doesn't know"; a grumpy one gives the grumpy reaction.
//

import XCTest
@testable import BobV1

@MainActor
final class VoiceTrickPhrasingTests: XCTestCase {
    private var suites: [String] = []
    override func tearDown() {
        for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }
        suites = []
    }
    private func alien(knows: @escaping (VoiceTrick) -> Bool = { _ in true }) -> VoiceTraining {
        let n = "VoiceTrickPhrasingTests.\(UUID().uuidString)"
        suites.append(n)
        let v = VoiceTraining(defaults: UserDefaults(suiteName: n)!, random: { 0 })          // a roll of 0 always obeys
        v.names.roster = [0]
        XCTAssertTrue(v.names.addNickname("alien", for: 0))
        v.unlocked = knows
        return v
    }
    /// Plain spellings of a trick: the title, its suggestion, every command word, hyphenated and glued.
    private func spellings(_ t: VoiceTrick) -> [String] {
        var s = Set([t.title.lowercased(), t.suggestion] + t.commandWords)
        for w in Array(s) where w.contains(" ") { s.insert(w.replacingOccurrences(of: " ", with: "-")); s.insert(w.replacingOccurrences(of: " ", with: "")) }
        return s.sorted()
    }
    private func variants(_ w: String) -> [String] {
        ["Alien do \(w)", "Alien do the \(w)", "Alien do a \(w)", "\(w) Alien", "Alien, \(w)!", "Alien \(w)", "Alien can you please do the \(w) now", "please \(w) Alien", "Moss... \(w)".replacingOccurrences(of: "Moss...", with: "Alien,")]
    }

    func testEveryTrickStartsByVoiceInEveryPhrasing() {
        var failures: [String] = []
        var table: [String] = []
        for t in VoiceTrick.allCases where t != .come {
            var fails = 0, total = 0
            for w in spellings(t) {
                for said in variants(w) {
                    total += 1
                    let r = alien().decide(transcript: said, runningMove: nil, mood: .happy, session: 1)
                    if r != .perform(t) { fails += 1; failures.append("\(t.rawValue): \"\(said)\" -> \(r)") }
                }
            }
            table.append("\(t.rawValue): \(total - fails)/\(total)")
        }
        voiceTableLog("VOICETRICKTABLE\n" + table.joined(separator: "\n"), file: "table.txt")
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testNameAndOneVerbWithNoFiller() {
        for who in ["Alien", "alien"] { for said in ["\(who) spin", "\(who), spin!", "spin \(who)", "\(who) twirl", "\(who) spin around", "\(who) hop", "\(who) jump", "\(who) sing", "\(who) moonwalk"] {
            let r = alien().decide(transcript: said, runningMove: nil, mood: .happy, session: 1)
            XCTAssertTrue({ if case .perform = r { return true }; return false }(), "\(said) -> \(r)")
        } }
        XCTAssertEqual(alien().decide(transcript: "Alien spin", runningMove: nil, mood: .happy, session: 1), .perform(.spin))
        XCTAssertEqual(alien(knows: { $0 != .spin }).decide(transcript: "Alien spin", runningMove: nil, mood: .happy, session: 1), .dontKnow(.spin))
    }

    /// A trick word must never be heard as some Jelmiko's name (then it is stripped and the command is just "a name": a highlight and nothing else).
    func testNoTrickWordIsHeardAsAName() {
        let v = alien()
        v.names.roster = Array(0..<JellyRoster.knownCount)
        var eaten: [String] = []
        for t in VoiceTrick.allCases { for w in t.commandWords + [t.suggestion] { for tok in VoiceMatcher.tokens(w) where v.names.match(token: tok) != nil { eaten.append("\(t.rawValue): \(tok)") } } }
        XCTAssertTrue(eaten.isEmpty, eaten.joined(separator: ", "))
    }

    func testDanceIsHulaAndWaveIsAlwaysKnown() {
        for said in ["Alien dance", "Alien do a dance", "Alien, dance for me!", "dance Alien", "Alien can you please dance"] {
            XCTAssertEqual(alien().decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .perform(.hula), said)
            XCTAssertEqual(alien(knows: { $0 != .hula }).decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .dontKnow(.hula), said)
        }
        for said in ["Alien wave", "Alien wave hi", "Alien, wave hello!", "wave Alien", "Alien say hi", "say hi Alien", "Alien do a wave", "Alien, please wave for me"] {
            for knows in [true, false] {
                XCTAssertEqual(alien(knows: { _ in knows }).decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .social(.wave), said)
            }
            XCTAssertEqual(alien().decide(transcript: said, runningMove: nil, mood: .grumpy, session: 1), .grumpyIgnore, said)
        }
        XCTAssertNotEqual(alien().decide(transcript: "Alien hello", runningMove: nil, mood: .happy, session: 1), .social(.wave), "a lone hello is not a wave")
    }

    func testSingSaidTheWaysPeopleSayIt() {
        for said in ["Alien sing", "Alien sing a song", "Alien, sing for me!", "sing me a song Alien", "Alien do sing", "Alien can you sing"] {
            XCTAssertEqual(alien().decide(transcript: said, runningMove: nil, mood: .happy, session: 1), .perform(.sing), said)
        }
    }

    func testAnUnknownTrickIsTheDontKnowReaction() {
        for t in VoiceTrick.allCases where t != .come {
            let v = alien(knows: { $0 != t })
            for said in ["Alien do \(t.suggestion)", "Alien do the \(t.suggestion)", "\(t.suggestion) Alien"] {
                let d = v.decideFull(transcript: said, runningMove: nil, mood: .happy, session: 1)
                XCTAssertEqual(d.reaction, .dontKnow(t), said)
                XCTAssertEqual(d.target, .jelly(0), said)
            }
        }
    }

    func testAGrumpyJelmikoGivesTheGrumpyReaction() {
        for t in VoiceTrick.allCases where t != .come {
            XCTAssertEqual(alien().decide(transcript: "Alien do \(t.suggestion)", runningMove: nil, mood: .grumpy, session: 1), .grumpyIgnore, t.rawValue)
            XCTAssertEqual(alien(knows: { $0 != t }).decide(transcript: "Alien do \(t.suggestion)", runningMove: nil, mood: .grumpy, session: 1), .grumpyIgnore, t.rawValue)
        }
    }

    func testPlacesAndOtherCommandsAreNotTricks() {
        XCTAssertNotEqual(alien().decide(transcript: "Alien sit on the couch", runningMove: nil, mood: .happy, session: 1), .perform(.sit))
        XCTAssertNotEqual(alien().decide(transcript: "Alien hop in the bath", runningMove: nil, mood: .happy, session: 1), .perform(.hop))
    }
}
