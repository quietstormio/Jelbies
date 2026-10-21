//
//  AIRouterTests.swift
//  The intent router: Tier B when the model is unavailable / not ready / slow / wrong, validation of the model's ids against the catalog, the
//  Tier A mapping from the Generable output (compiled against FoundationModels; no model runs in the simulator), and the availability states.
//

import XCTest
@testable import BobV1
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AIRouterTests: XCTestCase {
    private var suites: [String] = []
    private func names() -> JellyNames {
        let n = "AIRouterTests.\(UUID().uuidString)"; suites.append(n)
        return JellyNames(defaults: UserDefaults(suiteName: n)!, key: "nick", persists: true)
    }
    override func tearDown() { for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }; suites = [] }

    private func availability(_ s: SmartVoiceState) -> AIAvailability { let a = AIAvailability(); a.override = s; a.refresh(); return a }
    private var catalog: AICatalog { AITierBTests.catalog }

    func testUnavailableModelUsesTierB() async {
        for state in [SmartVoiceState.deviceNotEligible, .notEnabled, .modelNotReady, .unsupported("off")] {
            let fake = FakeCommandModel(); fake.state = state
            let r = IntentRouter(model: fake, availability: availability(state))
            XCTAssertFalse(r.smartVoiceOn)
            XCTAssertEqual(r.state.label, "Basic")
            let out = await r.route("hmm what a lovely day for a nap", names: names(), catalog: catalog, selected: 0)
            XCTAssertEqual(out.path, "model-unavailable", "\(state)")
            XCTAssertEqual(out.command.action, .sleep, "the rules still read 'nap'")
            XCTAssertTrue(fake.calls.isEmpty)
            r.prewarm(catalog: catalog)
            XCTAssertEqual(fake.prewarms, 0, "no session is built when the model is unavailable")
        }
        let none = IntentRouter(model: nil, availability: availability(.available))
        XCTAssertFalse(none.smartVoiceOn, "no framework: Basic even if the OS said available")
        let out = await none.route("banana", names: names(), catalog: catalog, selected: 0)
        XCTAssertEqual(out.path, "rules"); XCTAssertEqual(out.command.action, .none)
    }

    func testConfidentRulesSkipTheModelAndFreePhrasingGoesToIt() async {
        let fake = FakeCommandModel()
        fake.result = RawCommand(targets: ["Moss"], action: "sleep")
        let r = IntentRouter(model: fake, availability: availability(.available))
        XCTAssertTrue(r.smartVoiceOn)
        XCTAssertEqual(r.state.label, "On (Apple Intelligence)")
        let a = await r.route("Pip go to bed", names: names(), catalog: catalog, selected: 0)
        XCTAssertEqual(a.path, "rules"); XCTAssertEqual(a.command.who, .jellies([1]))
        XCTAssertTrue(fake.calls.isEmpty, "a clear verb never pays for the model")
        let b = await r.route("I think the green one looks tired", names: names(), catalog: catalog, selected: 0)
        XCTAssertEqual(b.path, "model")
        XCTAssertEqual(b.command, JellyCommand(who: .jellies([2]), action: .sleep, source: .model))
        XCTAssertEqual(fake.calls, ["I think the green one looks tired"])
        r.prewarm(catalog: catalog)
        XCTAssertEqual(fake.prewarms, 1)
        XCTAssertEqual(fake.lastCatalog?.jellyIDs, [0, 1, 2])
    }

    func testValidationRejectsUnknownIds() {
        let n = names()
        // unknown Jelly
        XCTAssertNil(CommandValidation.validate(RawCommand(targets: ["Lavender"], action: "come"), catalog: catalog, names: n))
        // unknown object, object of the wrong kind, unknown partner
        XCTAssertNil(CommandValidation.validate(RawCommand(action: "goTo", object: "sofa"), catalog: catalog, names: n))
        XCTAssertNil(CommandValidation.validate(RawCommand(action: "feed", object: "beanbag"), catalog: catalog, names: n))
        XCTAssertNil(CommandValidation.validate(RawCommand(action: "playWith", partner: "Rex"), catalog: catalog, names: n))
        // a required object / partner missing
        XCTAssertNil(CommandValidation.validate(RawCommand(action: "wear"), catalog: catalog, names: n))
        XCTAssertNil(CommandValidation.validate(RawCommand(action: "playWith"), catalog: catalog, names: n))
        // good ones (names via the registry: pet forms work; ids exact; "everyone")
        let ok = CommandValidation.validate(RawCommand(targets: ["Bobby"], action: "goTo", object: "beanbag"), catalog: catalog, names: n)
        XCTAssertEqual(ok, JellyCommand(who: .jellies([0]), action: .goTo, object: "beanbag", source: .model))
        let all = CommandValidation.validate(RawCommand(targets: ["everyone"], action: "feed", object: "pizza"), catalog: catalog, names: n)
        XCTAssertEqual(all?.who, .everyone); XCTAssertEqual(all?.object, "pizza")
        let p = CommandValidation.validate(RawCommand(targets: ["Pip"], action: "playWith", object: "ball", partner: "Moss"), catalog: catalog, names: n)
        XCTAssertEqual(p?.partner, 2); XCTAssertEqual(p?.object, "ball")
        // unknown action = none (the router falls back); "jumpingJacks" alias
        XCTAssertEqual(CommandValidation.validate(RawCommand(action: "teleport"), catalog: catalog, names: n)?.action, .none)
        XCTAssertEqual(CommandValidation.validate(RawCommand(action: "jumpingJacks"), catalog: catalog, names: n)?.action, .trick(.jacks))
        for k in JellyAction.allKeys { XCTAssertEqual(JellyAction(key: k)?.key, k, k) }
    }

    func testModelInvalidNoneErrorAndTimeoutFallBackToRules() async {
        let fake = FakeCommandModel()
        let r = IntentRouter(model: fake, availability: availability(.available))
        let n = names()
        fake.result = RawCommand(targets: ["Lavender"], action: "come")
        var out = await r.route("hey purple one get over here", names: n, catalog: catalog, selected: 0)
        XCTAssertEqual(out.path, "model-invalid"); XCTAssertEqual(out.command.action, .none)
        fake.result = RawCommand(action: "none")
        out = await r.route("the weather is nice", names: n, catalog: catalog, selected: 0)
        XCTAssertEqual(out.path, "model-none")
        fake.error = AIError.unavailable
        out = await r.route("something else entirely", names: n, catalog: catalog, selected: 0)
        XCTAssertEqual(out.path, "model-error")
        fake.error = nil; fake.delay = 2; fake.result = RawCommand(action: "sleep")
        let old = VoiceTuning.modelBudget; VoiceTuning.modelBudget = 0.1
        defer { VoiceTuning.modelBudget = old }
        out = await r.route("very slow phrase", names: n, catalog: catalog, selected: 0)
        XCTAssertEqual(out.path, "model-timeout"); XCTAssertEqual(out.command.action, .none)
        XCTAssertEqual(r.modelCalls, 4)
    }

    func testModelAnswerKeepsTheNameTheRulesHeard() async {
        let fake = FakeCommandModel()
        fake.result = RawCommand(action: "sleep")                       // the model dropped the name
        let r = IntentRouter(model: fake, availability: availability(.available))
        let out = await r.route("Moss you look exhausted buddy", names: names(), catalog: catalog, selected: 0)
        XCTAssertEqual(out.path, "model")
        XCTAssertEqual(out.command.who, .jellies([2]))
    }

    func testAvailabilityStatesAndLabels() {
        XCTAssertEqual(SmartVoiceState.available.label, "On (Apple Intelligence)")
        for s in [SmartVoiceState.deviceNotEligible, .notEnabled, .modelNotReady, .unsupported("x")] { XCTAssertEqual(s.label, "Basic", "\(s)"); XCTAssertFalse(s.detail.isEmpty) }
        XCTAssertEqual(AIAvailability.parse("notEnabled"), .notEnabled)
        XCTAssertEqual(AIAvailability.parse("basic"), .unsupported("off"))
        let a = AIAvailability()
        a.override = .modelNotReady
        XCTAssertEqual(a.refresh(), .modelNotReady)
        a.override = nil
        // in the simulator the framework answers (no model assets): whatever it says, it must map to one of our states without crashing
        _ = a.refresh()
        XCTAssertEqual(AIAvailability.read(), a.state)
    }

    #if canImport(FoundationModels)
    /// The Generable output maps onto RawCommand (the mapping the real session uses; the model itself cannot run in the simulator).
    func testGenerableOutputMapsToRawCommand() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let out = JellyCommandOut(targets: ["Pip", "Moss"], action: "playWith", object: "ball", partner: "Moss")
        let raw = RawCommand(out: out)
        XCTAssertEqual(raw, RawCommand(targets: ["Pip", "Moss"], action: "playWith", object: "ball", partner: "Moss"))
        let c = CommandValidation.validate(raw, catalog: catalog, names: names())
        XCTAssertEqual(c?.who, .jellies([1, 2])); XCTAssertEqual(c?.partner, 2)
        // the schema the model is constrained to has our four fields
        let schema = String(describing: JellyCommandOut.generationSchema)
        for f in ["targets", "action", "object", "partner"] { XCTAssertTrue(schema.contains(f), f) }
        let ins = SystemCommandModel.instructions(catalog)
        XCTAssertTrue(ins.contains("beanbag") && ins.contains("pirate_hat") && ins.contains("Moss"), "the instructions list the live ids")
        XCTAssertLessThan(ins.count, 1400, "short prompt")
    }
    #endif
}
