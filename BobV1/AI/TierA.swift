//
//  TierA.swift
//  Apple Intelligence on the phone (FoundationModels): availability, and the one place the framework is called. Everything the game needs sits
//  behind protocols so unit tests (and phones without the model) never touch it:
//    `AICommandModel`  free phrasing -> RawCommand (guided generation, `JellyCommandOut`), validated by the caller against the live catalog
//    `AITextWriter`    the diary entry and the thought lines (short, capped, filtered by the caller)
//  Rules: no network, no keys; the session runs in an actor (off the main thread); a fresh single-turn session per request (a long-lived one
//  would grow its transcript); prewarm when the mic opens. The model never writes text the player sees except the diary / thought lines, which
//  are built from game events only and pass the safety filter in Diary.swift.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Where Apple Intelligence stands on this phone, right now.
nonisolated enum SmartVoiceState: Equatable, Sendable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    /// No framework / turned off (`-VoiceNoModel 1`) / an unknown reason.
    case unsupported(String)

    var isAvailable: Bool { self == .available }
    /// Settings: "On (Apple Intelligence)" / "Basic".
    var label: String { isAvailable ? "On (Apple Intelligence)" : "Basic" }
    var detail: String {
        switch self {
        case .available: return "Free phrasing is understood on your phone. Nothing leaves it."
        case .deviceNotEligible: return "This phone can't run Apple Intelligence. Simple commands still work."
        case .notEnabled: return "Turn on Apple Intelligence in Settings for free phrasing. Simple commands still work."
        case .modelNotReady: return "Apple Intelligence is still downloading. Simple commands work meanwhile."
        case .unsupported: return "Simple commands only on this phone."
        }
    }
}

/// Reads `SystemLanguageModel.default.availability` (there is no change notification in the SDK: refresh when the mic opens and on foreground).
@MainActor
@Observable
final class AIAvailability {
    static let shared = AIAvailability()
    private(set) var state: SmartVoiceState = .unsupported("not checked")
    /// Tests and `-VoiceNoModel 1` pin a state.
    @ObservationIgnored var override: SmartVoiceState?
    nonisolated deinit {}

    init() {
        if UserDefaults.standard.bool(forKey: "VoiceNoModel") { override = .unsupported("off") }
        if let s = UserDefaults.standard.string(forKey: "SmartVoiceState") { override = Self.parse(s) }     // capture aid: -SmartVoiceState available|notEnabled|...
        refresh()
    }
    static func parse(_ s: String) -> SmartVoiceState? {
        switch s { case "available": return .available; case "deviceNotEligible": return .deviceNotEligible; case "notEnabled": return .notEnabled
        case "modelNotReady": return .modelNotReady; case "basic", "off": return .unsupported("off"); default: return nil }
    }

    @discardableResult
    func refresh() -> SmartVoiceState {
        let s = override ?? Self.read()
        if s != state { state = s }
        return s
    }

    static func read() -> SmartVoiceState {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(let r):
                switch r {
                case .deviceNotEligible: return .deviceNotEligible
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady: return .modelNotReady
                @unknown default: return .unsupported(String(describing: r))
                }
            }
        }
        #endif
        return .unsupported("no framework")
    }
}

// MARK: - protocols

/// Free phrasing -> a raw command (names and ids as the model wrote them; the router validates).
protocol AICommandModel: AnyObject, Sendable {
    var state: SmartVoiceState { get }
    /// Build the next session ahead of time (called when the mic opens).
    func prewarm(catalog: AICatalog)
    func interpret(_ text: String, catalog: AICatalog, selected: String) async throws -> RawCommand
}

/// Short game text (a diary entry, a handful of thought lines) from facts the game gives it.
protocol AITextWriter: AnyObject, Sendable {
    var state: SmartVoiceState { get }
    /// One short paragraph for the diary. `facts` are the day's events as plain lines.
    func diary(name: String, personality: String, facts: [String]) async throws -> String
    /// Up to `count` tiny lines (3-6 words) fitting a moment.
    func thoughts(name: String, personality: String, moment: String, count: Int) async throws -> [String]
}

nonisolated enum AIError: Error, Equatable { case unavailable, timedOut, invalid }

// MARK: - the real thing

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A command the owner gave their jelly pets")
struct JellyCommandOut {
    @Guide(description: "Pet names that were addressed, or [\"everyone\"] when all were; empty when none was named")
    var targets: [String]
    @Guide(description: "Exactly one of: come, stop, stopFighting, praise, scold, play, sit, jacks, run, flip, look, spin, feed, drink, sleep, clean, goTo, wear, playWith, race, train, whoIsHungry, whoIsThirsty, whoWantsLove, none")
    var action: String
    @Guide(description: "The id of the food, drink, decor, toy or wearable mentioned, from the lists given; empty when none")
    var object: String
    @Guide(description: "The pet name of a play partner (\"play with Moss\"); empty when none")
    var partner: String
}

@available(iOS 26.0, *)
@Generable(description: "Tiny thoughts of a jelly pet")
struct ThoughtLinesOut {
    @Guide(description: "3 to 6 words each, cute, kid-friendly, first person, no names", .count(4))
    var lines: [String]
}

extension RawCommand {
    @available(iOS 26.0, *)
    init(out: JellyCommandOut) { self.init(targets: out.targets, action: out.action, object: out.object, partner: out.partner) }
}

/// The session lives in an actor: `respond` inherits the caller's executor, so every request runs off the main thread.
@available(iOS 26.0, *)
actor FoundationSession {
    private var warm: LanguageModelSession?
    private var warmKey = ""

    /// Builds (and prewarms) the next single-turn session for these instructions.
    func prewarm(instructions: String) {
        guard warm == nil || warmKey != instructions else { return }
        let s = LanguageModelSession(instructions: instructions)
        warm = s; warmKey = instructions
        s.prewarm()
    }
    private func take(_ instructions: String) -> LanguageModelSession {
        defer { warm = nil }
        if let s = warm, warmKey == instructions, !s.isResponding { return s }
        return LanguageModelSession(instructions: instructions)
    }
    func command(instructions: String, prompt: String) async throws -> RawCommand {
        let s = take(instructions)
        let r = try await s.respond(to: prompt, generating: JellyCommandOut.self, options: GenerationOptions(temperature: 0))
        return RawCommand(out: r.content)
    }
    func text(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        let s = take(instructions)
        var o = GenerationOptions(temperature: 0.8)
        o.maximumResponseTokens = maxTokens
        return try await s.respond(to: prompt, options: o).content
    }
    func lines(instructions: String, prompt: String) async throws -> [String] {
        let s = take(instructions)
        let r = try await s.respond(to: prompt, generating: ThoughtLinesOut.self, options: GenerationOptions(temperature: 0.9))
        return r.content.lines
    }
}

@available(iOS 26.0, *)
final class SystemCommandModel: AICommandModel, @unchecked Sendable {
    private let session = FoundationSession()
    var state: SmartVoiceState { AIAvailability.read() }

    static func instructions(_ c: AICatalog) -> String {
        var s = """
        Map what a pet owner said to their jelly pets onto ONE command. Never reply with words.
        Pets in the room: \(c.jellies.map(\.name).joined(separator: ", ")). targets: the pet names addressed, ["everyone"] if all are, [] if none.
        action: come (call over), stop, stopFighting, praise (compliments), scold (no, bad), play, sit, jacks (jump), run, flip, look, spin, \
        feed (eat / a food), drink (a drink), sleep (bed, nap, goodnight), clean (bath, wash), goTo (go to / sit on decor), wear (put on), \
        playWith (play a game with another pet: partner), race, train, whoIsHungry, whoIsThirsty, whoWantsLove, none (anything else).
        """
        for k in [CatalogItem.Kind.food, .drink, .decor, .toy, .wearable] {
            let l = c.promptList(of: k)
            s += "\n\(k.rawValue) ids: " + (l.isEmpty ? "(none)" : l)
        }
        s += "\nobject: one of those ids or empty. partner: a pet name or empty."
        return s
    }
    func prewarm(catalog: AICatalog) {
        guard state.isAvailable else { return }
        let ins = Self.instructions(catalog)
        Task { await session.prewarm(instructions: ins) }
    }
    func interpret(_ text: String, catalog: AICatalog, selected: String) async throws -> RawCommand {
        guard state.isAvailable else { throw AIError.unavailable }
        return try await session.command(instructions: Self.instructions(catalog), prompt: "Selected pet: \(selected). Owner said: \"\(text)\"")
    }
}

@available(iOS 26.0, *)
final class SystemTextWriter: AITextWriter, @unchecked Sendable {
    private let session = FoundationSession()
    var state: SmartVoiceState { AIAvailability.read() }
    static let diaryInstructions = """
        You write a jelly pet's diary for a children's game. First person, as the pet. 2 to 4 short sentences, under 60 words, warm and simple, \
        no emoji. Use ONLY the events given; never invent events, people, places or names that are not in them. No dates, no headings, no quotes.
        """
    static let thoughtInstructions = """
        You write tiny thoughts for a jelly pet in a children's game: 3 to 6 words each, first person, cute, simple words, no names, no emoji, no punctuation except an exclamation mark.
        """
    func diary(name: String, personality: String, facts: [String]) async throws -> String {
        guard state.isAvailable else { throw AIError.unavailable }
        let f = facts.isEmpty ? "- a quiet day at home, nothing special happened" : facts.map { "- " + $0 }.joined(separator: "\n")
        return try await session.text(instructions: Self.diaryInstructions, prompt: "Pet: \(name) (\(personality)).\nToday's events:\n\(f)\nWrite today's diary entry.", maxTokens: 120)
    }
    func thoughts(name: String, personality: String, moment: String, count: Int) async throws -> [String] {
        guard state.isAvailable else { throw AIError.unavailable }
        return try await session.lines(instructions: Self.thoughtInstructions, prompt: "Pet: \(name) (\(personality)). Moment: \(moment). Write \(count) thoughts.")
    }
}
#endif

enum AIModels {
    /// The real model when this OS has the framework, else nil (the router then always uses the rules).
    @MainActor static func commandModel() -> AICommandModel? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemCommandModel() }
        #endif
        return nil
    }
    @MainActor static func textWriter() -> AITextWriter? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemTextWriter() }
        #endif
        return nil
    }
}
