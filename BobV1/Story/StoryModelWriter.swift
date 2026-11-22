//
//  StoryModelWriter.swift
//  Phase 2: Apple's on-device language model (Foundation Models), offline. Compiled only where the framework exists; used only where `SystemLanguageModel` says it is available.
//
//  Verified against the iOS 27.2 SDK (swiftinterface) and the research file jelmiko-apple-foundation-models-2026-11-22.md:
//   - guardrails are set ON THE MODEL: SystemLanguageModel(useCase: .general, guardrails: .default); there is no stricter option.
//   - a FRESH LanguageModelSession per text, fixed Instructions (no variable word in them), non-streaming `respond(to:generating:)` with a typed @Generable answer, so a refusal THROWS.
//   - both error families: LanguageModelError (iOS 27) and LanguageModelSession.GenerationError (26.x).
//   - the sentence strings sit under a `.pattern` guide (letters, spaces, commas, apostrophes, hyphens, {PLACEHOLDERS}, one closing full stop, bounded length); StoryGuard still checks everything.
//

#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, *)
nonisolated enum StoryModelPatterns {
    /// One sentence: 8 to 80 characters of letters, spaces, commas, apostrophes, hyphens or a {PLACEHOLDER}, then one full stop.
    static let sentence: Regex<AnyRegexOutput> = try! Regex("(?:[A-Za-z ,'-]|\\{[A-Z]{1,6}\\}){8,80}\\.")
}

@available(iOS 26.0, *)
@Generable(description: "A short note about a pet")
nonisolated struct StoryAboutDraft {
    @Guide(description: "First sentence", .pattern(StoryModelPatterns.sentence))
    var first: String
    @Guide(description: "Optional second sentence", .pattern(StoryModelPatterns.sentence))
    var second: String?
}

@available(iOS 26.0, *)
@Generable(description: "One short sentence about two pets")
nonisolated struct StoryNoteDraft {
    @Guide(description: "The sentence", .pattern(StoryModelPatterns.sentence))
    var sentence: String
}

@available(iOS 26.0, *)
nonisolated final class AppleModelClient: StoryModelClient, @unchecked Sendable {
    let model: SystemLanguageModel
    /// The sessions of the last few texts written this launch (for "Don't show this one": the feedback needs the transcript). Fingerprint of the final template -> session.
    private let lock = NSLock()
    private var sessions: [(key: String, session: LanguageModelSession)] = []

    static let shared = AppleModelClient()
    init() { model = SystemLanguageModel(useCase: .general, guardrails: .default) }

    func readiness() -> (available: Bool, localeSupported: Bool, detail: String) {
        let a = model.availability
        let ok: Bool, detail: String
        switch a {
        case .available: ok = true; detail = "available"
        case .unavailable(let r): ok = false; detail = "unavailable(\(r))"
        @unknown default: ok = false; detail = "unavailable(unknown)"
        }
        return (ok, model.supportsLocale(Locale.current), detail)
    }

    private func options() -> GenerationOptions { GenerationOptions(temperature: 0.8, maximumResponseTokens: 120) }

    private func fresh() -> LanguageModelSession { LanguageModelSession(model: model, instructions: StoryPrompt.instructions) }

    /// The prompt, the instructions and the answer's schema must fit the window (4096 in older systems).
    private func checkWindow(_ prompt: String, schema: GenerationSchema) async throws {
        if #available(iOS 26.4, *) {          // (`tokenCount(for:)` / `contextSize` are 26.4+; on 26.0 - 26.3 the window is 4096 tokens and the fixed text below is far under it)
            let ctx = model.contextSize
            let used = try await model.tokenCount(for: Instructions(StoryPrompt.instructions)) + model.tokenCount(for: Prompt(prompt)) + model.tokenCount(for: schema)
            if used + 400 > ctx { throw StoryWindowError() }
        } else if prompt.count + StoryPrompt.instructions.count > 3000 { throw StoryWindowError() }
    }
    struct StoryWindowError: Error {}

    func draftAbout(prompt: String) async throws -> (first: String, second: String?) {
        try await checkWindow(prompt, schema: StoryAboutDraft.generationSchema)
        let s = fresh()
        let r = try await s.respond(to: prompt, generating: StoryAboutDraft.self, options: options())
        remember(StoryDraft.about(first: r.content.first, second: r.content.second), s)
        return (r.content.first, r.content.second)
    }

    func draftNote(prompt: String) async throws -> String {
        try await checkWindow(prompt, schema: StoryNoteDraft.generationSchema)
        let s = fresh()
        let r = try await s.respond(to: prompt, generating: StoryNoteDraft.self, options: options())
        remember(r.content.sentence, s)
        return r.content.sentence
    }

    private func remember(_ template: String, _ s: LanguageModelSession) {
        lock.lock(); defer { lock.unlock() }
        sessions.append((StoryFingerprint.text(template), s))
        if sessions.count > 6 { sessions.removeFirst() }
    }

    /// "Don't show this one": files Apple's feedback attachment for the session that wrote `template` (nil when this launch did not write it). Returns the attachment data.
    @discardableResult
    func fileFeedback(forTemplate template: String) -> Data? {
        lock.lock(); let s = sessions.first { $0.key == StoryFingerprint.text(template) }?.session; lock.unlock()
        guard let s else { return nil }
        return s.logFeedbackAttachment(sentiment: .negative, issues: [LanguageModelFeedback.Issue(category: .unhelpful, explanation: "A player chose not to see this note.")], desiredResponseText: nil)
    }

    // MARK: errors: both families

    func classify(_ error: Error) -> StoryModelFailure {
        if error is StoryWindowError { return .contextSize }
        if #available(iOS 27.0, *) {
            if let e = error as? LanguageModelError {
                switch e {
                case .guardrailViolation: return .guardrail
                case .refusal: return .refusal
                case .unsupportedLanguageOrLocale: return .unsupportedLanguage
                case .contextSizeExceeded: return .contextSize
                case .rateLimited: return .rateLimited
                case .timeout: return .timeout
                case .unsupportedGenerationGuide: return .unsupportedGuide
                default: return .unknown          // non-exhaustive: capabilities, transcript content, anything added later
                }
            }
            if error is SystemLanguageModel.Error { return .assets }
            if let e = error as? LanguageModelSession.Error { _ = e; return .concurrent }
        }
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .guardrailViolation: return .guardrail
            case .refusal: return .refusal
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            case .exceededContextWindowSize: return .contextSize
            case .rateLimited: return .rateLimited
            case .assetsUnavailable: return .assets
            case .unsupportedGuide: return .unsupportedGuide
            case .decodingFailure: return .decoding
            case .concurrentRequests: return .concurrent
            @unknown default: return .unknown
            }
        }
        return .unknown
    }
}
#endif
