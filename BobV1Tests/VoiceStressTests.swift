//
//  VoiceStressTests.swift
//  Seeded, randomised stress of the voice pipeline the way the recogniser feeds it: results (volatile / final) -> TranscriptAccumulator -> decision.
//  Every valid command must reach 100%, nothing may run twice, a lone name only selects, garbage never starts a trick.
//

import XCTest
@testable import BobV1

private struct VTSplitMix: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}


/// Tables for the hand-back go to a text file when -the VOICE_TABLE_DIR environment variable names a directory (the simulator shares the host's disk).
func voiceTableLog(_ line: String, file: String) {
    guard let dir = ProcessInfo.processInfo.environment["SIMCTL_CHILD_VOICE_TABLE_DIR"] ?? ProcessInfo.processInfo.environment["VOICE_TABLE_DIR"] else { return }
    let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close() }
    else { try? (line + "\n").write(to: url, atomically: true, encoding: .utf8) }
}

@MainActor
final class VoiceStressTests: XCTestCase {
    private var suites: [String] = []
    override func tearDown() { for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }; suites = [] }

    /// Two home Jelmiko, "Alien" (slot 0) and "Violet" (slot 1: a nickname of character 1), with real random rolls.
    private func book(seed: UInt64, knows: @escaping (VoiceTrick) -> Bool = { _ in true }) -> VoiceTraining {
        let n = "VoiceStressTests.\(UUID().uuidString)"
        suites.append(n)
        let v = VoiceTraining(defaults: UserDefaults(suiteName: n)!, random: VoiceTraining.seededRoll(seed))
        v.names.roster = [0, 1]
        XCTAssertTrue(v.names.addNickname("alien", for: 0))
        XCTAssertTrue(v.names.addNickname("violet", for: 1))
        v.unlocked = knows
        return v
    }
    private let tricks = VoiceTrick.allCases.filter { $0 != .come }
    private func word(_ t: VoiceTrick, _ g: inout VTSplitMix) -> String {
        var ws = Set(t.commandWords + [t.suggestion, t.title.lowercased()])
        for w in Array(ws) where w.contains(" ") { ws.insert(w.replacingOccurrences(of: " ", with: "-")); ws.insert(w.replacingOccurrences(of: " ", with: "")) }
        return ws.sorted().randomElement(using: &g)!
    }
    private func phrase(name: String, trick w: String, _ g: inout VTSplitMix) -> String {
        let pre = ["", "do", "do the", "do a", "can you", "can you please", "please", "now", "go"].randomElement(using: &g)!
        let post = ["", "", "now", "please", "for me"].randomElement(using: &g)!
        let punct = ["", "!", ".", ","].randomElement(using: &g)!
        let core = "\(pre) \(w) \(post)".split(separator: " ").joined(separator: " ")
        let s = Bool.random(using: &g) ? "\(name), \(core)\(punct)" : "\(core) \(name)\(punct)"
        switch Int.random(in: 0..<3, using: &g) { case 0: return s.lowercased(); case 1: return s.uppercased(); default: return s }
    }
    /// How the recogniser could deliver `full`: one final; volatile then final; name first then the phrase 0.2-2.5 s later; a final that covers only the name
    /// while the volatile text already had the verb; split finals.
    private func delivered(_ full: String, shape: Int, name: String) -> String {
        var acc = TranscriptAccumulator()
        switch shape {
        case 0: acc.add(text: full, isFinal: true)
        case 1: acc.add(text: name, isFinal: false); acc.add(text: full, isFinal: false); acc.add(text: full, isFinal: true)
        case 2: acc.add(text: name, isFinal: false); acc.add(text: full, isFinal: false)                       // released before a final
        case 3: acc.add(text: full, isFinal: false); acc.add(text: String(full.split(separator: " ").first ?? ""), isFinal: true)                         // final covers the name only; the tail stays volatile
        default:
            let toks = full.split(separator: " ").map(String.init)
            acc.add(text: full, isFinal: false)
            acc.add(text: toks.first ?? full, isFinal: true)
            acc.add(text: toks.dropFirst().joined(separator: " "), isFinal: true)
        }
        return acc.result
    }
    private static func performs(_ r: VoiceReaction) -> Bool { if case .perform = r { return true }; return false }
    private func isPerform(_ r: VoiceReaction, _ t: VoiceTrick) -> Bool { r == .perform(t) }

    func testValidCommandsEveryDeliveryShape() {
        var g = VTSplitMix(s: 20261116)
        var table: [Int: (ok: Int, n: Int)] = [:]
        var firstFails: [String] = []
        for i in 0..<6000 {
            let t = tricks.randomElement(using: &g)!
            let shape = [0, 1, 2, 4].randomElement(using: &g)!
            let who = Bool.random(using: &g) ? ("Alien", 0) : ("Violet", 1)
            let said = phrase(name: who.0, trick: word(t, &g), &g)
            let heard = delivered(said, shape: shape, name: who.0)
            let d = book(seed: UInt64(i)).decideFull(transcript: heard, runningMove: nil, mood: .happy, session: 1)
            let ok = isPerform(d.reaction, t) && d.target == .jelly(who.1)
            table[shape, default: (0, 0)].n += 1
            if ok { table[shape, default: (0, 0)].ok += 1 } else if firstFails.count < 25 { firstFails.append("shape \(shape) said \"\(said)\" heard \"\(heard)\" -> \(d.reaction) \(d.target)") }
        }
        let names = ["one final", "volatile+final", "no final", "final=first word only", "split finals"]
        voiceTableLog("VOICESTRESS valid commands (6000 trials)", file: "stress.txt")
        for k in table.keys.sorted() { voiceTableLog("VOICESTRESS  \(names[k]): \(table[k]!.ok)/\(table[k]!.n)", file: "stress.txt") }
        XCTAssertTrue(firstFails.isEmpty, firstFails.joined(separator: "\n"))
    }

    func testBackToBackAndTwoJelmikoInARow() {
        var g = VTSplitMix(s: 77)
        var bad: [String] = []
        let v = book(seed: 5)                                           // ONE book, many commands in a row (the roll sequence runs on)
        var runs = 0
        for i in 0..<3000 {
            let t = tricks.randomElement(using: &g)!
            let who = i % 2 == 0 ? ("Alien", 0) : ("Violet", 1)          // alternating
            let said = phrase(name: who.0, trick: word(t, &g), &g)
            let d = v.decideFull(transcript: said, runningMove: Bool.random(using: &g) ? tricks.randomElement(using: &g) : nil, mood: .happy, session: i)
            if d.reaction == .perform(t), d.target == .jelly(who.1) { runs += 1 } else if bad.count < 15 { bad.append("\"\(said)\" -> \(d.reaction) \(d.target)") }
        }
        voiceTableLog("VOICESTRESS back-to-back alternating Alien/Violet, mid-move: \(runs)/3000", file: "stress.txt")
        XCTAssertTrue(bad.isEmpty, bad.joined(separator: "\n"))
    }

    func testLoneNameOnlySelectsAndGarbageNeverStartsATrick() {
        var g = VTSplitMix(s: 9)
        var lone = 0, garbage = 0
        let junk = ["banana", "purple monkey", "uh", "the", "what time is it", "blorp snerf", "hello there friend", "spinach"]
        for i in 0..<2000 {
            let who = i % 2 == 0 ? ("Alien", 0) : ("Violet", 1)
            let v = book(seed: UInt64(i))
            let a = v.decideFull(transcript: ["\(who.0)", "\(who.0)!", "hey \(who.0)"].randomElement(using: &g)!, runningMove: nil, mood: .happy, session: 1)
            if a.target == .jelly(who.1), !Self.performs(a.reaction) { lone += 1 }
            let b = v.decideFull(transcript: "\(who.0) \(junk.randomElement(using: &g)!)", runningMove: nil, mood: .happy, session: 1)
            if !Self.performs(b.reaction) { garbage += 1 }
        }
        voiceTableLog("VOICESTRESS lone name only selects: \(lone)/2000; garbage after a name starts no trick: \(garbage)/2000", file: "stress.txt")
        XCTAssertEqual(lone, 2000); XCTAssertEqual(garbage, 2000)
    }

    func testUnknownAndGrumpyEveryTime() {
        var g = VTSplitMix(s: 31)
        var dk = 0, gr = 0
        for i in 0..<2000 {
            let t = tricks.randomElement(using: &g)!
            let said = phrase(name: "Violet", trick: word(t, &g), &g)
            let a = book(seed: UInt64(i), knows: { $0 != t }).decide(transcript: said, runningMove: nil, mood: .happy, session: 1)
            if a == .dontKnow(t) { dk += 1 }
            let b = book(seed: UInt64(i)).decide(transcript: said, runningMove: nil, mood: .grumpy, session: 1)
            if b == .grumpyIgnore { gr += 1 }
        }
        voiceTableLog("VOICESTRESS unknown -> doesn't know: \(dk)/2000; grumpy -> grumpy reaction: \(gr)/2000", file: "stress.txt")
        XCTAssertEqual(dk, 2000); XCTAssertEqual(gr, 2000)
    }
}
