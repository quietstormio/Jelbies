//
//  VoiceIntent.swift
//  What the player MEANT: the intent types, the deterministic phrase tables for the built-in social commands, and the on-device language model
//  fallback (Foundation Models, guided generation). The model NEVER writes text the player sees: it only fills a fixed structure
//  (target + action + confidence) and the game picks an existing move. Pipeline (see VoiceCoordinator.process):
//    transcript -> (a) deterministic: names + pet forms + nicknames, learned trick words, come aliases, social phrases, teaching
//               -> (b) only if (a) found nothing: the model maps free phrasing to an action (prewarmed when the mic opens, ~0.8 s target).
//  The model can only trigger a trick that is already learned (any word); an unlearned trick is a confused look.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Who a command is for.
nonisolated enum VoiceTarget: Equatable, Sendable {
    /// Nobody was named: the selected Jelly (Bob by default).
    case selected
    /// A Jelly by id (0 Bob, 1 Pip, 2 Moss).
    case jelly(Int)
    case everyone
}

/// The built-in social commands: known from the start, no training.
nonisolated enum VoiceSocial: String, CaseIterable, Equatable, Sendable {
    case stop, stopFighting, praise, scold, play
}

/// One action the player asked for.
nonisolated enum VoiceAction: Equatable, Sendable {
    case come
    case social(VoiceSocial)
    case trick(VoiceTrick)          // a learned trick (never .come)
    case none
}

/// Deterministic phrase tables for the social commands. Token lists are normalised (lowercase, "don't" = "don t").
nonisolated enum VoicePhrases {
    private static let stopFighting = ["stop fighting", "stop fight", "quit fighting", "no fighting", "break it up", "be nice", "play nice", "quit it",
                                       "knock it off", "cut it out", "stop arguing", "stop it you two", "that s enough", "leave him alone", "leave her alone"]
    private static let stopWords: Set<String> = ["stop", "stay", "freeze", "halt", "wait", "whoa", "enough"]
    private static let stopPhrases = ["hold on", "stand still", "stay put", "stay there", "stay here", "sit still"]
    private static let scoldWords: Set<String> = ["no", "bad", "naughty", "dont", "shame", "nope", "nono"]
    private static let scoldPhrases = ["don t", "bad boy", "bad girl", "not nice", "stop that"]
    private static let playWords: Set<String> = ["play", "playing", "fetch"]
    private static let praiseWords: Set<String> = ["good", "great", "cute", "adorable", "awesome", "amazing", "love", "proud", "clever", "smart",
                                                    "wonderful", "perfect", "cutie", "sweet", "bravo", "hooray", "yay", "handsome", "pretty",
                                                    "beautiful", "precious", "darling"]
    private static let praisePhrases = ["well done", "nice job", "nice one", "atta boy", "atta girl", "that s my", "so cute"]

    private static func has(_ padded: String, _ phrases: [String]) -> Bool { phrases.contains { padded.contains(" \($0) ") } }

    /// The social command in these tokens (name already stripped), if any. "come" is NOT here (see VoiceMatcher.looksLikeCome).
    static func social(_ t: [String]) -> VoiceSocial? {
        guard !t.isEmpty else { return nil }
        let padded = " " + t.joined(separator: " ") + " "
        let set = Set(t)
        if has(padded, stopFighting) { return .stopFighting }
        if !set.isDisjoint(with: stopWords) || has(padded, stopPhrases) { return .stop }
        if !set.isDisjoint(with: scoldWords) || has(padded, scoldPhrases) { return .scold }
        if !set.isDisjoint(with: playWords) { return .play }
        if !set.isDisjoint(with: praiseWords) || has(padded, praisePhrases) { return .praise }
        return nil
    }

    private static let everyoneWords: Set<String> = ["everyone", "everybody", "guys", "yall", "everyones"]
    private static let everyonePhrases = ["all of you", "you all", "y all", "all you", "you guys", "you two", "you three", "both of you"]
    /// "everyone" / "everybody" / "you guys" ...: true plus the tokens left after removing the address.
    static func everyone(_ t: [String]) -> (Bool, [String]) {
        var rest = t, found = false
        let padded = " " + t.joined(separator: " ") + " "
        for p in everyonePhrases where padded.contains(" \(p) ") {
            found = true
            let pt = p.split(separator: " ").map(String.init)
            var out: [String] = [], i = 0
            while i < rest.count {
                if i + pt.count <= rest.count, Array(rest[i..<(i + pt.count)]) == pt { i += pt.count; continue }
                out.append(rest[i]); i += 1
            }
            rest = out
        }
        let filtered = rest.filter { !everyoneWords.contains($0) }
        if filtered.count != rest.count { found = true }
        return (found, filtered)
    }
}

// MARK: - the model

/// What the model returned, as plain values (the Generable struct is mapped into this).
nonisolated struct ModelIntent: Equatable, Sendable {
    enum TargetKind: Equatable, Sendable { case selected, named, everyone }
    var targetKind: TargetKind = .selected
    /// A Jelly name or nickname to look up (never shown to the player).
    var targetName = ""
    var action: VoiceAction = .none
    var confidence: Double = 1
}

nonisolated enum ModelAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
    var isAvailable: Bool { self == .available }
}

/// The language model behind a protocol: the real one is Apple's on-device model, tests use a fake.
@MainActor
protocol VoiceIntentModel: AnyObject {
    var availability: ModelAvailability { get }
    /// Called when the mic opens so the first request is fast.
    func prewarm()
    /// `learned`: the tricks he really knows (the only ones the model may pick); `names`: the Jelly names it may put in `targetName`.
    func interpret(_ text: String, learned: [VoiceTrick], names: [String]) async throws -> ModelIntent
}

nonisolated enum VoiceModelError: Error { case unavailable, timedOut }

/// Test double: returns `result` (or throws), optionally after a delay; counts calls.
@MainActor
final class FakeIntentModel: VoiceIntentModel {
    var availability: ModelAvailability = .available
    var result: ModelIntent = ModelIntent()
    var error: Error?
    var delay: Double = 0
    private(set) var calls: [String] = []
    private(set) var prewarms = 0
    private(set) var lastLearned: [VoiceTrick] = []
    func prewarm() { prewarms += 1 }
    func interpret(_ text: String, learned: [VoiceTrick], names: [String]) async throws -> ModelIntent {
        calls.append(text); lastLearned = learned
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
        if let error { throw error }
        return result
    }
}

enum VoiceIntentModels {
    /// The real model when this OS has it, else nil (everything falls back to the deterministic result).
    @MainActor static func make() -> VoiceIntentModel? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemIntentModel() }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct VoiceIntentOut {
    @Generable
    enum Target {
        case selected
        case named(String)
        case everyone
    }
    @Generable
    enum Act { case come, stop, stopFighting, praise, scold, play, sit, jumpingJacks, run, flip, look, none }

    @Guide(description: "selected when no pet is addressed, named(name) when a pet name or nickname is said, everyone when all pets are addressed")
    var target: Target
    var action: Act
    @Guide(description: "how sure you are, 0 to 1", .range(0.0...1.0))
    var confidence: Double
}

@available(iOS 26.0, *)
@MainActor
final class SystemIntentModel: VoiceIntentModel {
    private var session: LanguageModelSession?

    var availability: ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(let r): return .unavailable(String(describing: r))
        }
    }

    private func instructions(names: [String]) -> String {
        """
        Map what a pet owner said to their jelly pets onto ONE command. Never reply with words.
        Commands: come (call over, "come see me", "over here"), stop (stop, stay, wait), stopFighting (break up a fight, be nice, quit it), \
        praise (compliments, "I love you", "good boy"), scold (no, bad, don't), play, sit, jumpingJacks (jump, exercise), run, flip (backflip, somersault), \
        look (look around), none (anything else).
        target: everyone if all the pets are addressed, named(name) if one of [\(names.joined(separator: ", "))] or a nickname is said, otherwise selected.
        """
    }

    /// A single-turn session per request (a long-lived one would grow its transcript). `prewarm()` builds the next one ahead of time.
    func prewarm() {
        guard availability.isAvailable, session == nil else { return }
        let s = LanguageModelSession(instructions: instructions(names: JellyNameRoster.all.map(\.display)))
        session = s
        s.prewarm()
    }

    func interpret(_ text: String, learned: [VoiceTrick], names: [String]) async throws -> ModelIntent {
        guard availability.isAvailable else { throw VoiceModelError.unavailable }
        let s = session ?? LanguageModelSession(instructions: instructions(names: names))
        session = nil
        let r = try await s.respond(to: "Owner said: \"\(text)\"", generating: VoiceIntentOut.self, options: GenerationOptions(temperature: 0))
        var out = ModelIntent(confidence: r.content.confidence)
        switch r.content.target {
        case .selected: out.targetKind = .selected
        case .named(let n): out.targetKind = .named; out.targetName = VoiceMatcher.normalise(n)
        case .everyone: out.targetKind = .everyone
        }
        switch r.content.action {
        case .come: out.action = .come
        case .stop: out.action = .social(.stop)
        case .stopFighting: out.action = .social(.stopFighting)
        case .praise: out.action = .social(.praise)
        case .scold: out.action = .social(.scold)
        case .play: out.action = .social(.play)
        case .sit: out.action = .trick(.sit)
        case .jumpingJacks: out.action = .trick(.jacks)
        case .run: out.action = .trick(.run)
        case .flip: out.action = .trick(.flip)
        case .look: out.action = .trick(.look)
        case .none: out.action = .none
        }
        return out
    }
}
#endif
