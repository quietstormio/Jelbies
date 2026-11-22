//
//  StoryWriters.swift
//  The writer protocol, the pre-written writer and the chain: `[StoryWriter]`, the first acceptable answer wins, EVERY answer goes through `StoryGuard` with the real names put in.
//  A writer returns text WITH placeholders ({A}, {B}, {FOOD} ...) and never sees a player-typed word. Phase 2 puts the on-device model writer in front of `TemplateWriter`.
//

import Foundation

nonisolated protocol StoryWriter: Sendable {
    /// Short name for the log and the dump ("template", "model").
    var name: String { get }
    /// The About blurb with placeholders; nil = no answer (the next writer is asked).
    func about(facts: StoryFacts) async -> String?
    /// The note about how `facts` gets on with housemate `with`, with placeholders; nil = no answer.
    func friendship(facts: StoryFacts, with: StoryFacts.Housemate) async -> String?
}

/// What a writer answered and what the guard said (every attempt is kept for the dump and the log).
nonisolated struct StoryAttempt: Sendable, Equatable {
    var writer: String
    var raw: String?
    var verdict: String
}

nonisolated struct StoryResult: Sendable, Equatable {
    /// Placeholders still in (what is saved), the real words in (what is shown), who wrote it.
    var template: String
    var final: String
    var writer: String
    var attempts: [StoryAttempt]
}

/// The memory the pre-written writer needs between calls: which patterns were used lately (no repeat until the bank is through) and the seed counter. Saved by `StoryBook`.
nonisolated final class StoryMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var used: [String: [Int]] = [:]
    private var counter: [String: Int] = [:]
    let salt: UInt64
    init(salt: UInt64 = 0x5EED, used: [String: [Int]] = [:], counter: [String: Int] = [:]) { self.salt = salt; self.used = used; self.counter = counter }

    func usedSet(_ key: String) -> Set<Int> { lock.lock(); defer { lock.unlock() }; return Set(used[key] ?? []) }
    func remember(_ key: String, _ ids: [Int], bankSize: Int) {
        lock.lock(); defer { lock.unlock() }
        var a = used[key] ?? []
        a.append(contentsOf: ids)
        if a.count > bankSize { a.removeFirst(a.count - bankSize) }
        used[key] = a
    }
    func nextSeed(_ key: String) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        let n = (counter[key] ?? 0) + 1
        counter[key] = n
        return StoryTemplates.fnv([String(salt), key, String(n)])
    }
    func replace(used: [String: [Int]], counter: [String: Int]) { lock.lock(); defer { lock.unlock() }; self.used = used; self.counter = counter }
    func snapshot() -> (used: [String: [Int]], counter: [String: Int]) { lock.lock(); defer { lock.unlock() }; return (used, counter) }
    func forget(prefixes: [String]) {
        lock.lock(); defer { lock.unlock() }
        for k in used.keys where prefixes.contains(where: { k.hasPrefix($0) }) { used.removeValue(forKey: k) }
        for k in counter.keys where prefixes.contains(where: { k.hasPrefix($0) }) { counter.removeValue(forKey: k) }
    }
}

nonisolated struct TemplateWriter: StoryWriter {
    var name: String { "template" }
    let memory: StoryMemory
    init(memory: StoryMemory = StoryMemory()) { self.memory = memory }

    static func aboutKey(_ id: Int) -> String { "about.\(id)" }
    static func noteKey(_ a: Int, _ b: Int) -> String { "note.\(a)>\(b)" }

    func about(facts: StoryFacts) async -> String? { writeAbout(facts) }
    func friendship(facts: StoryFacts, with h: StoryFacts.Housemate) async -> String? { writeNote(facts, h) }

    func writeAbout(_ f: StoryFacts) -> String? {
        let key = Self.aboutKey(f.id)
        guard let w = StoryTemplates.about(f, used: memory.usedSet(key), seed: memory.nextSeed(key)) else { return nil }
        memory.remember(key, w.ids, bankSize: StoryTemplates.aboutBank.count)
        return w.template
    }
    func writeNote(_ f: StoryFacts, _ h: StoryFacts.Housemate) -> String? {
        let key = Self.noteKey(f.id, h.id)
        guard let w = StoryTemplates.friendship(f, with: h, used: memory.usedSet(key), seed: memory.nextSeed(key)) else { return nil }
        memory.remember(key, w.ids, bankSize: StoryTemplates.noteBank.count)
        return w.template
    }
}

/// The chain: every writer in order, each answer through the guard; the first that passes wins.
nonisolated struct StoryChain: Sendable {
    var writers: [StoryWriter]
    /// Texts the player hid: no writer's answer with one of these fingerprints is accepted.
    var hidden: StoryHiddenSet?
    init(_ writers: [StoryWriter]) { self.writers = writers }
    private func hiddenByPlayer(_ t: String) -> Bool { hidden?.contains(StoryFingerprint.text(t)) ?? false }

    func about(_ f: StoryFacts) async -> StoryResult? {
        let values = StoryFill.values(f), offered = Set(values.keys)
        var attempts: [StoryAttempt] = []
        for w in writers {
            guard let t = await w.about(facts: f) else { attempts.append(StoryAttempt(writer: w.name, raw: nil, verdict: "no answer")); continue }
            let fin = StoryFill.apply(t, values)
            let v = StoryGuard.check(template: t, final: fin, kind: .about, offered: offered, shown: f.shownParagraph, values: values)
            let hid = v.passed && hiddenByPlayer(t)
            attempts.append(StoryAttempt(writer: w.name, raw: t, verdict: hid ? "hidden-by-player" : v.description))
            if v.passed && !hid { return StoryResult(template: t, final: fin, writer: w.name, attempts: attempts) }
        }
        return nil
    }

    func friendship(_ f: StoryFacts, with h: StoryFacts.Housemate) async -> StoryResult? {
        let values = StoryFill.values(f, with: h), offered = Set(values.keys)
        var attempts: [StoryAttempt] = []
        for w in writers {
            guard let t = await w.friendship(facts: f, with: h) else { attempts.append(StoryAttempt(writer: w.name, raw: nil, verdict: "no answer")); continue }
            let fin = StoryFill.apply(t, values)
            let v = StoryGuard.check(template: t, final: fin, kind: .friendship, offered: offered, values: values)
            let hid = v.passed && hiddenByPlayer(t)
            attempts.append(StoryAttempt(writer: w.name, raw: t, verdict: hid ? "hidden-by-player" : v.description))
            if v.passed && !hid { return StoryResult(template: t, final: fin, writer: w.name, attempts: attempts) }
        }
        return nil
    }
}
