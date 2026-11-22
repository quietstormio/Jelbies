//
//  StoryModelGate.swift
//  Phase 2, the parts of the on-device model writer that need no framework (so they are unit-tested everywhere): when the model may be asked at all, the fixed instructions, the prompt
//  (facts as short labelled lines, placeholders instead of every player-typed word), the failure reason codes and the counters for the dump, and the player's switch.
//

import Foundation
import os

/// Why the model was not used, or how it failed. The dev log and the dump show these codes; nothing here is ever shown to the player.
nonisolated enum StoryModelFailure: String, Sendable, CaseIterable {
    case unavailable, localeNotSupported, notEnglish, background, busy, lowPower, thermal, switchedOff, promptDenied
    case guardrail, refusal, unsupportedLanguage, contextSize, rateLimited, timeout, assets, unsupportedGuide, decoding, concurrent, unknown
    case tooLong
}

nonisolated enum StoryModelGate {
    struct Input: Sendable, Equatable {
        var modelAvailable = false, localeSupported = false, english = false, foreground = false
        var busy = false, lowPower = false, thermalOK = true, switchedOn = true
    }
    /// nil = the model may be asked; otherwise the reason it must not be (the template writer answers).
    static func skipReason(_ i: Input) -> StoryModelFailure? {
        if !i.switchedOn { return .switchedOff }
        if !i.modelAvailable { return .unavailable }
        if !i.localeSupported { return .localeNotSupported }
        if !i.english { return .notEnglish }
        if !i.foreground { return .background }
        if i.busy { return .busy }
        if i.lowPower { return .lowPower }
        if !i.thermalOK { return .thermal }
        return nil
    }
    static func thermalOK(_ s: ProcessInfo.ThermalState) -> Bool { s != .serious && s != .critical }
    /// The app's language is English (the game's text is English only).
    static var appIsEnglish: Bool { (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("en") && (Locale.current.language.languageCode?.identifier ?? "en") == "en" }
}

/// The player's switch: Settings > Game > "Notes written by Apple Intelligence". Default on; off = the pre-written notes only.
nonisolated enum StorySettings {
    static let key = "Story.modelNotes"
    static func isOn(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: key) == nil ? true : d.bool(forKey: key) }
    static var modelNotes: Bool { isOn() }
    static func setModelNotes(_ on: Bool, _ d: UserDefaults = .standard) { d.set(on, forKey: key) }
    static let explanation = "Little notes on the Profile are written on this iPhone. Nothing leaves it."
    static let title = "Notes written by Apple Intelligence"
}

/// Foreground / background, readable from any thread.
nonisolated enum StoryAppState {
    private static let fg = OSAllocatedUnfairLock(initialState: true)
    static var foreground: Bool { get { fg.withLock { $0 } } set { fg.withLock { $0 = newValue } } }
}

/// Counters for the dump and the log (dev only; never shown).
nonisolated final class StoryModelStats: @unchecked Sendable {
    static let shared = StoryModelStats()
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private(set) var log: [String] = []
    func bump(_ k: StoryModelFailure, _ detail: String = "") {
        lock.lock(); defer { lock.unlock() }
        counts[k.rawValue, default: 0] += 1
        if log.count < 200 { log.append("\(k.rawValue) \(detail)") }
    }
    func bump(_ name: String) { lock.lock(); counts[name, default: 0] += 1; lock.unlock() }
    func count(_ k: StoryModelFailure) -> Int { lock.lock(); defer { lock.unlock() }; return counts[k.rawValue] ?? 0 }
    func count(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[name] ?? 0 }
    func snapshot() -> [String: Int] { lock.lock(); defer { lock.unlock() }; return counts }
    func reset() { lock.lock(); counts = [:]; log = []; lock.unlock() }
}

/// The fixed words the model is given. NOTHING variable goes into the instructions; the prompt is our template with the facts as labelled lines.
nonisolated enum StoryPrompt {
    static let instructions = """
    You write tiny, gentle notes about a pet for a children's pet game. The reader is a young child and their parent.
    Rules: write in the third person only. Use the present tense or the recent past. Be warm and use simple words a young child can read. \
    Use ONLY the facts you are given and never invent events. Never mention being written or generated. Nothing sad, scary, romantic or rude. \
    Never use the word kiss. Ask no questions. No emoji. No numbers. Never write a name: keep every {...} placeholder exactly as given, such as {A}.
    """

    /// The About prompt: the facts as short labelled lines. No player-typed word: the pet is {A}.
    static func about(_ f: StoryFacts) -> String {
        let v = StoryFill.values(f)
        var lines = ["Write a short note about the pet {A}: one or two short sentences, at most 80 characters in all.", "Facts:"]
        if let p = v["PERS"] { lines.append("- personality: \(p)") }
        if let x = v["FOOD"] { lines.append("- favourite food: {FOOD} (\(x))") }
        if let x = v["ACT"] { lines.append("- likes lately: {ACT} (\(x))") }
        if let x = v["SPOT"] { lines.append("- favourite spot: {SPOT} (\(x))") }
        if let x = v["RACE"] { lines.append("- has won a race on a course called {RACE} (\(x))") }
        if let x = v["SHOW"] { lines.append("- has a cup from the Jelly Show at the level called {SHOW} (\(x))") }
        if f.trophies.volleyWins > 0 { lines.append("- has won on the volleyball sand") }
        if f.sleepHabit != nil { lines.append("- takes lots of naps") }
        if f.togetherShare >= 0.12 { lines.append("- plays with the housemates a lot") }
        if f.newcomer { lines.append("- has only just moved in") } else if f.daysTracked >= 4 { lines.append("- has lived here for a good while") }
        if let l = f.relationshipLevel { lines.append("- bond with the player: \(l)") }
        // the static paragraph is our own text, but a few kind descriptions use words the deny list refuses ("baby", "games", "sad"): then it is left out (the guard still rejects any colour word)
        if let s = f.shownParagraph, !s.isEmpty, denied(s) == nil { lines.append("Already shown above (do not repeat): \(s)") }
        lines.append("Placeholders you may use: " + v.keys.sorted().map { "{\($0)}" }.joined(separator: " ") + ".")
        lines.append("Do not say the pet's colour or kind.")
        return lines.joined(separator: "\n")
    }

    static func note(_ f: StoryFacts, with h: StoryFacts.Housemate) -> String {
        let v = StoryFill.values(f, with: h)
        var lines = ["Write one short sentence, at most 55 characters, about how the pet {A} gets on with its housemate {B}.", "Facts:"]
        switch StoryTemplates.tier(h) {
        case .close: lines.append("- they play together all the time, the closest of friends")
        case .regular: lines.append("- they often play together")
        case .few: lines.append("- they are still getting to know each other")
        }
        if let x = v["EMOTE"] { lines.append("- they do this together most: {EMOTE} (\(x))") }
        lines.append("Placeholders you may use: " + v.keys.filter { $0 != "BKIND" }.sorted().map { "{\($0)}" }.joined(separator: " ") + ".")
        return lines.joined(separator: "\n")
    }

    /// The deny list over the prompt (Apple: check input and output). nil = clean.
    static func denied(_ prompt: String) -> String? { StoryGuard.denied(StoryGuard.masked(prompt), raw: prompt) }
}

/// What the model's typed answer becomes: the sentences joined into one text with placeholders.
nonisolated enum StoryDraft {
    static func about(first: String, second: String?) -> String {
        let a = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = (second ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? a : a + " " + b
    }
}

/// A model that can be asked for a typed draft. The real one is `AppleModelClient` (StoryModelWriter.swift); tests use a fake.
nonisolated protocol StoryModelClient: Sendable {
    /// What the model can do right now (before any prompt).
    func readiness() -> (available: Bool, localeSupported: Bool, detail: String)
    func draftAbout(prompt: String) async throws -> (first: String, second: String?)
    func draftNote(prompt: String) async throws -> String
    /// The reason code of a thrown error.
    func classify(_ error: Error) -> StoryModelFailure
}

/// The model-backed writer: gate -> prompt (deny-listed) -> typed draft within a timeout -> text with placeholders. Any trouble = nil (the next writer answers) and a reason code in the log.
nonisolated struct ModelWriter: StoryWriter {
    var name: String { "model" }
    let client: StoryModelClient
    /// Reads the live state (foreground, busy, Low Power Mode, the switch); main-actor values are fetched by the caller's closure.
    let gate: @Sendable () async -> StoryModelGate.Input
    var timeout: TimeInterval = 8
    var stats: StoryModelStats = .shared

    init(client: StoryModelClient, timeout: TimeInterval = 8, stats: StoryModelStats = .shared, gate: @escaping @Sendable () async -> StoryModelGate.Input) {
        self.client = client; self.timeout = timeout; self.stats = stats; self.gate = gate
    }

    private func mayAsk() async -> Bool {
        var i = await gate()
        let r = client.readiness()
        i.modelAvailable = r.available; i.localeSupported = r.localeSupported
        if let why = StoryModelGate.skipReason(i) { stats.bump(why, r.detail); return false }
        return true
    }

    func about(facts: StoryFacts) async -> String? {
        guard await mayAsk() else { return nil }
        let prompt = StoryPrompt.about(facts)
        if let bad = StoryPrompt.denied(prompt) { stats.bump(.promptDenied, bad); return nil }
        do {
            let d = try await withTimeout { try await client.draftAbout(prompt: prompt) }
            return StoryDraft.about(first: d.first, second: d.second)
        } catch { fail(error); return nil }
    }

    func friendship(facts: StoryFacts, with h: StoryFacts.Housemate) async -> String? {
        guard await mayAsk() else { return nil }
        let prompt = StoryPrompt.note(facts, with: h)
        if let bad = StoryPrompt.denied(prompt) { stats.bump(.promptDenied, bad); return nil }
        do { return try await withTimeout { try await client.draftNote(prompt: prompt) }.trimmingCharacters(in: .whitespacesAndNewlines) }
        catch { fail(error); return nil }
    }

    private struct TimedOut: Error {}
    private func fail(_ e: Error) {
        let r: StoryModelFailure = e is TimedOut ? .timeout : client.classify(e)
        stats.bump(r, String(describing: e).prefix(80).description)
    }
    private func withTimeout<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let secs = timeout
        return try await withThrowingTaskGroup(of: T.self) { g in
            g.addTask { try await work() }
            g.addTask { try await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000)); throw TimedOut() }
            defer { g.cancelAll() }
            guard let first = try await g.next() else { throw TimedOut() }
            return first
        }
    }
}

/// Whether this device and system can run the model at all (the Settings switch is shown only then).
enum StoryModelSupport {
    static var deviceHasModel: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { let r = AppleModelClient.shared.readiness(); return r.available && r.localeSupported }
        #endif
        return false
    }
}
