//
//  IntentRouter.swift
//  Speech text -> one validated JellyCommand. The rule parser (Tier B) runs first because it is instant and deterministic; when it recognises a
//  verb the command stands. Only free phrasing goes to the on-device model (Tier A) when Apple Intelligence is available: its answer is checked
//  against the live catalog (unknown names / ids are rejected) and it must come back within `VoiceTuning.modelBudget` (1.5 s). Unavailable,
//  not ready, timeout, error or an invalid answer all fall back to the rule result silently. `path` records which happened (log / tests).
//

import Foundation
import QuartzCore

nonisolated struct RoutedCommand: Equatable, Sendable {
    var command: JellyCommand
    /// "rules", "model", "model-timeout", "model-error", "model-unavailable", "model-invalid", "model-none".
    var path: String
    var ms: Int = 0
}

@MainActor
final class IntentRouter {
    /// Tier A (nil = none: everything is Tier B).
    var model: AICommandModel?
    let availability: AIAvailability
    /// Rule parses that name a verb skip the model (fast path). Off = the model is asked for everything the legacy layer did not catch.
    var rulesFirst = true
    /// The last route (tests, the HUD).
    private(set) var last: RoutedCommand?
    private(set) var modelCalls = 0

    nonisolated deinit {}           // an isolated deinit hops executors on release: the project keeps deinits nonisolated (it aborts in the 26.2 runtime)

    init(model: AICommandModel? = nil, availability: AIAvailability? = nil) {
        self.model = model; self.availability = availability ?? .shared
    }

    /// Current Apple Intelligence state (refreshed), as the settings show it.
    var state: SmartVoiceState { availability.refresh() }
    var smartVoiceOn: Bool { state.isAvailable && model != nil }

    /// Called when the mic opens: refresh availability and build the model's next session.
    func prewarm(catalog: AICatalog) {
        guard let model, availability.refresh().isAvailable else { return }
        model.prewarm(catalog: catalog)
    }

    /// The synchronous answer when the model will not be asked: a confident rule parse, no model, or Apple Intelligence unavailable. Nil = free
    /// phrasing for the model (`route`). The coordinator uses this first so Tier B stays as instant as the legacy path (no Task hop).
    func routeNow(_ text: String, names: JellyNames, catalog: AICatalog) -> RoutedCommand? {
        let t0 = CACurrentMediaTime()
        let rules = RuleParser.parse(text, names: names, catalog: catalog)
        let path: String
        if rulesFirst, rules.confident, rules.command.isActionable { path = "rules" }
        else if model == nil { path = "rules" }
        else if !availability.refresh().isAvailable { path = "model-unavailable" }
        else { return nil }
        let r = RoutedCommand(command: rules.command, path: path, ms: Int((CACurrentMediaTime() - t0) * 1000))
        last = r
        if VoiceCoordinator.logging { NSLog("AILOG route path=%@ ms=%d action=%@ text=\"%@\"", path, r.ms, rules.command.action.key, text) }
        return r
    }

    func route(_ text: String, names: JellyNames, catalog: AICatalog, selected: Int) async -> RoutedCommand {
        let t0 = CACurrentMediaTime()
        func done(_ c: JellyCommand, _ p: String) -> RoutedCommand {
            let r = RoutedCommand(command: c, path: p, ms: Int((CACurrentMediaTime() - t0) * 1000))
            last = r
            if VoiceCoordinator.logging { NSLog("AILOG route path=%@ ms=%d action=%@ text=\"%@\"", p, r.ms, c.action.key, text) }
            return r
        }
        let rules = RuleParser.parse(text, names: names, catalog: catalog)
        if rulesFirst, rules.confident, rules.command.isActionable { return done(rules.command, "rules") }
        guard let model else { return done(rules.command, "rules") }
        guard availability.refresh().isAvailable else { return done(rules.command, "model-unavailable") }
        modelCalls += 1
        let selectedName = catalog.jellies.first { $0.id == selected }?.name ?? catalog.jellies.first?.name ?? "Bob"
        let raw: RawCommand
        do {
            raw = try await VoiceCoordinator.withBudget(VoiceTuning.modelBudget) { try await model.interpret(text, catalog: catalog, selected: selectedName) }
        } catch VoiceModelError.timedOut { return done(rules.command, "model-timeout") }
        catch { return done(rules.command, "model-error") }
        guard var c = CommandValidation.validate(raw, catalog: catalog, names: names) else { return done(rules.command, "model-invalid") }
        if c.action == .none { return done(rules.command, "model-none") }
        if c.who == .selected, rules.command.who != .selected { c.who = rules.command.who }        // a name the rules heard that the model dropped
        if c.partner == nil { c.partner = rules.command.partner }
        return done(c, "model")
    }
}

/// Test double for Tier A.
final class FakeCommandModel: AICommandModel, @unchecked Sendable {
    var state: SmartVoiceState = .available
    var result = RawCommand()
    var error: Error?
    var delay: Double = 0
    private(set) var calls: [String] = []
    private(set) var prewarms = 0
    private(set) var lastCatalog: AICatalog?
    func prewarm(catalog: AICatalog) { prewarms += 1; lastCatalog = catalog }
    func interpret(_ text: String, catalog: AICatalog, selected: String) async throws -> RawCommand {
        calls.append(text); lastCatalog = catalog
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
        if let error { throw error }
        return result
    }
}
