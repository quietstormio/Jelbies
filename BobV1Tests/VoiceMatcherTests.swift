//
//  VoiceMatcherTests.swift
//  Voice v1 matcher: normalising, fuzzy + phonetic matching, the name prefix rule, and name-vs-trick priority.
//  Decision: name + trick in one utterance ("sit down bob") = the trick; the name only gets his attention. The name alone = the name.
//

import XCTest
@testable import BobV1

final class VoiceMatcherTests: XCTestCase {
    private let words = ["sit", "jump", "run", "sleepy", "look", "come"]

    private func match(_ said: String, _ stored: [String]? = nil) -> String? {
        let w = stored ?? words
        guard let h = VoiceMatcher.best(in: VoiceMatcher.tokens(said), among: w) else { return nil }
        return w[h.index]
    }

    func testNormalise() {
        XCTAssertEqual(VoiceMatcher.normalise("  Sit!!  Down, BOB... "), "sit down bob")
        XCTAssertEqual(VoiceMatcher.normalise("Café Señor"), "cafe senor")
        XCTAssertEqual(VoiceMatcher.normalise("don't"), "don t")
        XCTAssertEqual(VoiceMatcher.normalise("   "), "")
        XCTAssertEqual(VoiceMatcher.tokens("Come here!"), ["come", "here"])
        XCTAssertEqual(VoiceMatcher.normalise("座って"), "座って", "other scripts survive")
    }

    func testTable() {
        let table: [(String, String?)] = [
            ("Sit!", "sit"), ("sitt", "sit"), ("sits", "sit"), ("SIT", "sit"), ("set", "sit"),
            ("jump", "jump"), ("jumps", "jump"), ("run", "run"), ("runn", "run"),
            ("sleepy", "sleepy"), ("sleepe", "sleepy"), ("slepy", "sleepy"),
            ("look", "look"), ("come", "come"), ("cum", "come"),
            ("banana", nil), ("hello there", nil), ("", nil),
        ]
        for (said, want) in table { XCTAssertEqual(match(said), want, "\"\(said)\"") }
    }

    func testEditDistanceLimits() {
        XCTAssertEqual(VoiceMatcher.score(heard: "sat", stored: "sit"), 0.9, accuracy: 0.001)
        XCTAssertEqual(VoiceMatcher.score(heard: "spit", stored: "sit"), 0.9, accuracy: 0.001)
        XCTAssertEqual(VoiceMatcher.score(heard: "sleepi", stored: "sleepy"), 0.9, accuracy: 0.001)
        XCTAssertEqual(VoiceMatcher.score(heard: "slepi", stored: "sleepy"), 0.8, accuracy: 0.001, "2 edits are fine for long words")
        XCTAssertEqual(VoiceMatcher.score(heard: "cat", stored: "dog"), 0)
        XCTAssertEqual(VoiceMatcher.score(heard: "stand", stored: "sit"), 0, "2 edits is too far for a 3-letter word")
    }

    func testPlayerWordsMochi() {
        let stored = ["mochi"]
        XCTAssertEqual(match("Mochee", stored), "mochi")
        XCTAssertEqual(match("mochy", stored), "mochi")
        XCTAssertEqual(match("moch", stored), "mochi")
        XCTAssertNil(match("mango", stored))
        XCTAssertNil(match("jelly", stored))
    }

    func testPhonetic() {
        XCTAssertEqual(VoiceMatcher.soundex("Robert"), "R163")
        XCTAssertEqual(VoiceMatcher.soundex("Rupert"), "R163")
        XCTAssertEqual(VoiceMatcher.soundex("Tymczak"), "T522")
        XCTAssertEqual(VoiceMatcher.soundex("Pfister"), "P236")
        XCTAssertEqual(VoiceMatcher.soundex("座"), "")
        XCTAssertGreaterThan(VoiceMatcher.levenshtein("pfister", "pastor"), 2, "too far for edit distance")
        XCTAssertEqual(VoiceMatcher.score(heard: "pfister", stored: "pastor"), 0.6, accuracy: 0.001, "but it sounds the same")
        XCTAssertEqual(VoiceMatcher.score(heard: "kneel", stored: "nil"), 0, "different first letter: no")
    }

    func testBigramAndPhrases() {
        XCTAssertEqual(match("please sit down", ["sit down"]), "sit down")
        XCTAssertEqual(match("sit", ["sit down"]), nil, "a stored phrase needs the phrase")
        XCTAssertEqual(match("ok bob sit", ["sit"]), "sit")
        XCTAssertEqual(match("can you jump please", words), "jump")
    }

    func testBestScoreWins() {
        XCTAssertEqual(match("sit", ["sat", "sit"]), "sit", "exact beats one-edit")
        XCTAssertEqual(match("sit", ["sit", "sit"]), "sit")
        XCTAssertNil(VoiceMatcher.best(in: ["sit"], among: [""]))
    }

    func testNamePrefixRule() {
        for said in ["Bob", "Bobby", "Bobbie", "bobs", "BOB!"] {
            XCTAssertGreaterThan(VoiceMatcher.splitName(tokens: VoiceMatcher.tokens(said), name: "bob").nameScore, 0, said)
        }
        for said in ["rob", "job", "bog", "bobcatsrus", "boat", "sit"] {
            XCTAssertEqual(VoiceMatcher.splitName(tokens: VoiceMatcher.tokens(said), name: "bob").nameScore, 0, said)
        }
    }

    func testNameWithTrickSplits() {
        let r = VoiceMatcher.splitName(tokens: VoiceMatcher.tokens("sit down bob"), name: "bob")
        XCTAssertEqual(r.nameScore, 1)
        XCTAssertEqual(r.rest, ["sit", "down"])
        let alone = VoiceMatcher.splitName(tokens: VoiceMatcher.tokens("Bobby!"), name: "bob")
        XCTAssertGreaterThan(alone.nameScore, 0)
        XCTAssertTrue(alone.rest.isEmpty)
    }
}
