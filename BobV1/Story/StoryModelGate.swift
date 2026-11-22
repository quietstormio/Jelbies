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
    func logLines() -> [String] { lock.lock(); defer { lock.unlock() }; return log }
    func snapshot() -> [String: Int] { lock.lock(); defer { lock.unlock() }; return counts }
    func reset() { lock.lock(); counts = [:]; log = []; lock.unlock() }
}

/// The fixed words the model is given. NOTHING variable goes into the instructions; the prompt is our template with the facts as labelled lines.
nonisolated enum StoryPrompt {
    static let instructions = """
    You write one tiny, plain, useful note about a pet for a children's pet game. The reader is a young child and their parent.
    Rules: write exactly ONE sentence in the third person, the way a parent would say it aloud: a plain subject, a plain verb. Use present tense or the recent past, \
    warm and simple words a young child can read. State one or two TRUE things from the facts you are given and nothing else: never invent events or behaviour. \
    No stage directions, no cute extras, no strained verbs. Never use he, she, him or her: use the placeholder or no pronoun. Never mention being written or generated. \
    Nothing sad, scary, romantic or rude. Never use the word kiss. Ask no questions. No emoji. No numbers. Never write a name: keep every {...} placeholder exactly as given, such as {A}. \
    Also return the keys of the facts you used, exactly as written in square brackets.
    """

    /// The About prompt: the facts as short labelled lines, each with its key. No player-typed word: the pet is {A}.
    static func about(_ f: StoryFacts) -> String {
        let v = StoryFill.values(f), keys = StoryFill.facts(f)
        var lines = ["Write one plain sentence about the pet {A}, at most 70 characters, stating one or two of these facts.", "Facts:"]
        if keys.contains("personality") { lines.append("- [personality] personality: \(v["PERS"]!)") }
        if keys.contains("favouriteFood") { lines.append("- [favouriteFood] favourite food: {FOOD} (\(v["FOOD"]!))") }
        if keys.contains("favouriteActivity") { lines.append("- [favouriteActivity] has been doing this a lot this week: {ACT} (\(v["ACT"]!))") }
        if keys.contains("favouriteSpot") { lines.append("- [favouriteSpot] spends the most time here: {SPOT} (\(v["SPOT"]!))") }
        if keys.contains("partner") { lines.append("- [partner] plays with the housemate {B} most") }
        if keys.contains("topEmote") { lines.append("- [topEmote] they are often: {EMOTE} (\(v["EMOTE"]!))") }
        if keys.contains("raceWin") { lines.append("- [raceWin] has won a race on a course called {RACE} (\(v["RACE"]!))") }
        if keys.contains("showCup") { lines.append("- [showCup] has a cup from the Jelly Show, rank {SHOW} (\(v["SHOW"]!))") }
        if keys.contains("volleyWin") { lines.append("- [volleyWin] has won a volleyball match") }
        if let n = f.news, keys.contains(n.factKey) { lines.append("- [\(n.factKey)] NEWS \(v["WHEN"] ?? "today"): \(StoryPrompt.newsText(n))") }
        if keys.contains("raceMilestone") { lines.append("- [raceMilestone] needs {LEFT} for a new trophy (\(v["LEFT"]!))") }
        if keys.contains("nap") { lines.append("- [nap] takes lots of naps") }
        if keys.contains("newcomer") { lines.append("- [newcomer] has only just moved in") }
        if keys.contains("settled") { lines.append("- [settled] has lived here for a good while") }
        if let l = f.relationshipLevel { lines.append("- [bond] bond with the family: \(l)") }
        // the static paragraph is our own text, but a few kind descriptions use words the deny list refuses ("baby", "games", "sad"): then it is left out (the guard still rejects any colour word)
        if let s = f.shownParagraph, !s.isEmpty, denied(s) == nil { lines.append("Already shown above (do not repeat): \(s)") }
        lines.append("Placeholders you may use: " + v.keys.filter { $0 != "BKIND" }.sorted().map { "{\($0)}" }.joined(separator: " ") + ".")
        lines.append("Do not say the pet's colour or kind.")
        return lines.joined(separator: "\n")
    }

    /// The news as plain words with placeholders for the variable parts ({TIER}, {PLACE}, {LEVEL}); {WHEN} is today / yesterday.
    static func newsText(_ n: StoryEvent) -> String {
        switch n.kind {
        case "race": return n.d["win"] == "1" ? "won the {TIER} race" : "ran the {TIER} race"
        case "show": return "took part in the {TIER} Jelly Show, place {PLACE}"
        case "volley": return n.d["win"] == "1" ? "won a volleyball match on the {TIER} court" : "played volleyball on the {TIER} court"
        case "park": return "went to the park"
        case "cafe": return "went to the cafe for a treat"
        case "bubbles": return "played with bubbles"
        case "ball": return "played with the ball"
        case "bath": return "had a bath"
        case "groom": return "was groomed"
        case "trick": return "did a trick when asked"
        case "meal": return "had a favourite meal"
        case "cuddle": return "had a good cuddle"
        case "bond": return "moved up to {LEVEL}, a closer bond with the family"
        default: return n.kind
        }
    }

    static func note(_ f: StoryFacts, with h: StoryFacts.Housemate) -> String {
        let v = StoryFill.values(f, with: h)
        // The Profile row is titled with the housemate's name, so the note says "They" and never a name.
        var lines = ["Write one plain sentence, at most 45 characters, about how two housemate pets get on. Start with the word They. Do not use any name or placeholder.", "Facts:"]
        switch StoryTemplates.tier(h) {
        case .close: lines.append("- [together] they play together more than anyone, the closest of friends")
        case .regular: lines.append("- [together] they often play together")
        case .few: lines.append("- [gettingToKnow] they are still getting to know each other")
        }
        if h.sharedGroup { lines.append("- [sharedGroup] they joined in a group activity lately") }
        if let x = v["EMOTE"], StoryTemplates.tier(h) != .few { lines.append("- [topEmote] they are often: {EMOTE} (\(x))") }
        lines.append("Placeholder you may use: {EMOTE} only if you use the topEmote fact.")
        return lines.joined(separator: "\n")
    }

    /// The deny list over the prompt (Apple: check input and output). nil = clean.
    static func denied(_ prompt: String) -> String? { StoryGuard.denied(StoryGuard.masked(prompt), raw: prompt) }
}

/// A model that can be asked for a typed draft. The real one is `AppleModelClient` (StoryModelWriter.swift); tests use a fake.
nonisolated protocol StoryModelClient: Sendable {
    /// What the model can do right now (before any prompt).
    func readiness() -> (available: Bool, localeSupported: Bool, detail: String)
    /// The sentence (placeholders in) and the fact keys it says it used.
    func draftAbout(prompt: String) async throws -> (sentence: String, keys: [String])
    func draftNote(prompt: String) async throws -> (sentence: String, keys: [String])
    /// The reason code of a thrown error.
    func classify(_ error: Error) -> StoryModelFailure
}

/// The model-backed writer: gate -> prompt (deny-listed) -> typed draft within a timeout -> text with placeholders + fact keys. Any trouble = nil (the next writer answers) and a reason code in the log.
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

    /// Cheap: the model exists here, speaks this locale, and the player's switch is on.
    var isUsable: Bool {
        let r = client.readiness()
        return r.available && r.localeSupported && StorySettings.modelNotes && StoryModelGate.appIsEnglish
    }

    func about(facts: StoryFacts) async -> StoryAnswer? {
        guard await mayAsk() else { return nil }
        let prompt = StoryPrompt.about(facts)
        if let bad = StoryPrompt.denied(prompt) { stats.bump(.promptDenied, bad); return nil }
        do {
            let d = try await withTimeout { try await client.draftAbout(prompt: prompt) }
            return StoryAnswer(d.sentence.trimmingCharacters(in: .whitespacesAndNewlines), keys: d.keys)
        } catch { fail(error); return nil }
    }

    func friendship(facts: StoryFacts, with h: StoryFacts.Housemate) async -> StoryAnswer? {
        guard await mayAsk() else { return nil }
        let prompt = StoryPrompt.note(facts, with: h)
        if let bad = StoryPrompt.denied(prompt) { stats.bump(.promptDenied, bad); return nil }
        do {
            let d = try await withTimeout { try await client.draftNote(prompt: prompt) }
            return StoryAnswer(d.sentence.trimmingCharacters(in: .whitespacesAndNewlines), keys: d.keys)
        } catch { fail(error); return nil }
    }

    private struct TimedOut: Error {}
    private func fail(_ e: Error) {
        let r: StoryModelFailure = e is TimedOut ? .timeout : client.classify(e)
        stats.bump(r, String(describing: e).prefix(80).description)
    }

    /// Our own timeout: the first of the work and the clock wins, and the caller is released at once even if the framework call ignores cancellation (the abandoned call just finishes in the background).
    private func withTimeout<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let secs = timeout
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
            let once = OSAllocatedUnfairLock(initialState: false)
            @Sendable func finish(_ r: Result<T, Error>) { if once.withLock({ let was = $0; $0 = true; return !was }) { c.resume(with: r) } }
            let job = Task { do { finish(.success(try await work())) } catch { finish(.failure(error)) } }
            Task { try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000)); finish(.failure(TimedOut())); job.cancel() }
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
