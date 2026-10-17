//
//  VoiceIntegrationTests.swift
//  Voice v1 wired into the game: a rep taught while he does a move, a learned word started from a wander and in focus, commands ignored while a
//  tray is out, grumpy ignoring, the name walk (stays out of focus mode) and the voice "come here" (walks, then enters focus). FakeSpeechInput + isolated, non-persisting
//  training; `hear(_:)` is the synchronous end of a listen, the clock is injected so a hold counts as long.
//

import XCTest
import simd
@testable import BobV1

@MainActor
private final class Clock { var t: Double = 100 }

@MainActor
private final class StubInput: SpeechInput {
    var availability: VoiceAvailability
    var onLevel: ((Float) -> Void)?
    init(_ a: VoiceAvailability) { availability = a }
    func prepare(contextualWords: [String]) async {}
    func start(contextualWords: [String]) async throws { throw SpeechInputError.notReady }
    func stop() async -> String { "" }
}

/// Game brain + care ticked like the stage does (idleBlocked from the care, the way MelonStage sets it).
@MainActor
private final class VoiceRun {
    let rig = MotionRig(game: true, settle: 1.0)
    let clock = Clock()
    let care: GameCare
    var voice: VoiceCoordinator { care.voice }
    var brain: BlobBrain { rig.brain }
    init(roll: Double = 0) {
        let c = clock
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "VoiceIntegrationTests")!, persists: false, random: { roll })
        care = GameCare(voice: VoiceCoordinator(training: training, input: FakeSpeechInput(), now: { c.t }))
        for k in NeedKind.allCases { care.needs.set(k, 1) }            // not grumpy unless a test says so
        brain.autonomy = true; brain.seed = 7
    }
    func tick() {
        brain.idleMood = care.mood
        brain.idleBlocked = (care.focus.isActive || care.trayOut) && !brain.commanded
        brain.tick(sim: rig.sim, skinner: rig.skinner, dt: rig.sim.stepDt, touched: false)
        care.tick(brain: brain, renderer: nil, dt: rig.sim.stepDt, sim: rig.sim)
        rig.sim.step()
        rig.t += rig.sim.stepDt
        clock.t += Double(rig.sim.stepDt)
    }
    @discardableResult
    func run(_ s: Float, until: (() -> Bool)? = nil) -> Bool {
        for _ in 0..<Int(s * 60) { tick(); if let until, until() { return true } }
        return until?() ?? false
    }
    /// One listen: open, let the pose / running move register, hold, say `words`, let the reaction start.
    func say(_ words: String, settle: Float = 0.2) {
        run(0.1)
        XCTAssertTrue(voice.begin(), "the hold opens")
        run(0.3)
        voice.hear(words)
        run(settle)
    }
}

@MainActor
final class VoiceIntegrationTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []        // the runtime aborts when a rig is released (see MelonModel)

    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = [] }

    private func make(roll: Double = 0) -> VoiceRun {
        let r = VoiceRun(roll: roll)
        Self.keep.append(r)
        return r
    }

    func testTeachSitThreeTimesThenCommandFromWander() {
        let r = make()
        for i in 0..<VoiceTuning.repsToLearn {
            if r.brain.idleState.kind != .sit {                                        // the sit he was doing ended: he starts another
                r.brain.idleReset(r.rig.skinner)
                XCTAssertTrue(r.brain.idleStart(.sit, r.rig.sim))
            }
            r.say("sit")
            XCTAssertEqual(r.voice.training.lesson(.sit).reps, i + 1, "rep \(i + 1) counted")
        }
        XCTAssertTrue(r.voice.training.isLearned(.sit), "learned after \(VoiceTuning.repsToLearn) reps over \(VoiceTuning.repsToLearn) listens")
        XCTAssertEqual(r.voice.training.word(for: .sit), "sit")
        // from a wander
        r.brain.idleReset(r.rig.skinner)
        r.brain.requestNow(.goTo(SIMD2(1.5, 0.6)))
        XCTAssertTrue(r.run(2) { r.brain.activity == .walking }, "he is wandering")
        r.say("sit", settle: 0)
        XCTAssertTrue(r.run(2) { r.brain.idleState.kind == .sit }, "he sits within 2 s")
        XCTAssertEqual(r.care.focus.phase, .roaming)
    }

    func testCommandWorksInFocus() {
        let r = make()
        r.voice.training.debugLearn(.sit, word: "sit")
        r.care.comeHere()
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused })
        XCTAssertFalse(r.brain.autonomy)
        r.say("sit", settle: 0)
        XCTAssertTrue(r.run(2) { r.brain.idleState.kind == .sit }, "he sits in focus mode")
        XCTAssertTrue(r.run(1.0) { r.brain.idleState.kind == nil } == false, "the sit is not cut short by focus")
        XCTAssertEqual(r.care.focus.phase, .focused)
    }

    func testIgnoredWhileTrayOut() {
        let r = make()
        r.voice.training.debugLearn(.sit, word: "sit")
        r.care.feed("berries")
        r.run(0.2)
        XCTAssertTrue(r.care.trayOut)
        r.say("sit", settle: 0)
        var sat = false
        r.run(2) { if r.brain.idleState.kind == .sit { sat = true }; return sat }
        XCTAssertFalse(sat, "no trick while a meal is out")
    }

    func testGrumpyIgnoresAndNeverDoesTheTrick() {
        let r = make()
        r.voice.training.debugLearn(.sit, word: "sit")
        for k in NeedKind.allCases { r.care.needs.set(k, 0) }
        r.run(0.2)
        XCTAssertEqual(r.care.mood, .grumpy)
        r.say("sit", settle: 0)
        var sat = false
        r.run(3) { if r.brain.idleState.kind == .sit { sat = true }; return sat }
        XCTAssertFalse(sat, "grumpy does not sit")
    }

    func testNameLearnedHopsWalksTowardCameraAndHoldsAttention() {
        let r = make()
        r.voice.training.debugLearnName()
        r.brain.autonomy = true
        r.run(0.5)
        let start = r.brain.position
        let rest = r.rig.sim.restCentroid.y
        r.say("bob", settle: 0)
        var apex: Float = 0
        r.run(0.6) { apex = max(apex, r.rig.sim.bodyPose(iterations: 4).centroid.y - rest); return false }
        XCTAssertGreaterThanOrEqual(apex, 0.12, "he hops within 0.6 s (name hop apex 0.20 u): apex \(apex)")
        XCTAssertEqual(r.care.focus.phase, .roaming)
        // walks, turns, then holds
        let target = min(start.y + VoiceCoordinator.nameWalk, GameCamera.callSpot.y + 0.4)
        var arrived = false
        r.run(10) { if case .none = r.brain.script, r.brain.activity == .idle, r.voice.voiceGoing == false, abs(r.brain.yaw - r.brain.faceCameraYaw()) < 0.2 { arrived = true }; return arrived }
        XCTAssertTrue(arrived, "he arrives and faces the camera")
        let closer = r.brain.position.y - start.y
        XCTAssertGreaterThanOrEqual(closer, min(1.0, target - start.y - 0.05), "closer to the camera (+z): \(closer)")
        var worst: Float = 0
        var idle = false
        r.run(2.0) {
            var d = r.brain.yaw - r.brain.faceCameraYaw()
            while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
            worst = max(worst, abs(d))
            if r.brain.idleState.kind != nil { idle = true }
            if case .none = r.brain.script {} else { idle = true }
            return false
        }
        XCTAssertLessThan(worst, 10 * .pi / 180, "holds the camera facing: \(worst) rad")
        XCTAssertFalse(idle, "no idle behaviour or script during the hold")
        XCTAssertEqual(r.care.focus.phase, .roaming, "no focus mode")
    }

    func testNameLearnedInFocusIsJustAHop() {
        let r = make()
        r.voice.training.debugLearnName()
        r.brain.autonomy = false
        r.care.comeHere()
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused })
        let before = r.brain.position
        r.say("bob", settle: 0)
        r.run(3)
        XCTAssertLessThan(simd_length(r.brain.position - before), 0.3, "no walk in focus mode")
        XCTAssertTrue(r.care.focus.isActive)
    }

    func testNameLessonLearnsOverThreeListens() {
        let r = make()
        for _ in 0..<VoiceTuning.repsToLearn { r.say("bob", settle: 0.1) }
        XCTAssertTrue(r.voice.training.nameLearned)
    }

    func testVoiceComeHereWalksThenEntersFocus() {
        let r = make()                                          // come is innate: nothing taught
        XCTAssertTrue(r.voice.training.isLearned(.come))
        r.brain.autonomy = false
        r.say("come here", settle: 0)
        var sawApproach = false
        let ok = r.run(40) {
            if r.care.focus.phase == .approaching { sawApproach = true }
            return r.care.focus.phase == .focused
        }
        XCTAssertTrue(ok, "voice come here ends in focus (cuddle) mode")
        XCTAssertTrue(sawApproach, "he walked to the front first")
        XCTAssertFalse(r.brain.autonomy, "same as tapping him: he stays on the front spot")
    }

    func testLooseComeVariantsEnterFocus() {
        for words in ["come", "Come here, Bob!", "here boy"] {
            let r = make()
            r.say(words, settle: 0)
            XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused }, "\(words) -> focus")
        }
    }

    func testVoiceComeInFocusIsJustAHop() {
        let r = make()
        r.care.comeHere()
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused })
        let before = r.brain.position
        r.say("come here", settle: 0)
        var hopped = false
        r.run(2) { if case .hopPlay = r.brain.script { hopped = true }; return hopped }
        XCTAssertTrue(hopped, "happy hop")
        XCTAssertLessThan(simd_length(r.brain.position - before), 0.3)
        XCTAssertEqual(r.care.focus.phase, .focused, "still focused, no second entry")
    }

    func testGrumpyComeDoesNotEnterFocus() {
        let r = make()
        for k in NeedKind.allCases { r.care.needs.set(k, 0) }
        r.run(0.2)
        XCTAssertEqual(r.care.mood, .grumpy)
        r.say("come here", settle: 0)
        r.run(6)
        XCTAssertEqual(r.care.focus.phase, .roaming, "a grumpy Bob refuses")
    }

    func testMissedRollDoesNotEnterFocus() {
        let r = make(roll: 0.99)                                // above the 0.92 reliability: ignored
        r.say("come here", settle: 0)
        r.run(6)
        XCTAssertEqual(r.care.focus.phase, .roaming)
    }

    func testReleaseEndsListeningBeforeTheTranscriptIsReady() async {
        let r = make()
        r.run(0.1)
        XCTAssertTrue(r.voice.begin())
        XCTAssertTrue(r.voice.isListening, "listening (glow state) is set synchronously by begin")
        r.run(0.4)
        r.voice.debugTranscript = "sit"
        r.voice.release()
        XCTAssertFalse(r.voice.isListening, "glow state clears synchronously on release")
        XCTAssertEqual(r.voice.mode.glowLevel, 0)
    }

    func testShortHoldReleaseIsASilentCancel() {
        let r = make()
        XCTAssertTrue(r.voice.begin())
        r.voice.release()                                       // no time passed: under 0.25 s
        XCTAssertFalse(r.voice.isListening)
        XCTAssertEqual(r.voice.mode.phase, .idle)
        r.run(1)
        XCTAssertEqual(r.care.focus.phase, .roaming)
    }

    func testTutorialIsRetired() {
        let r = make()
        XCTAssertTrue(r.voice.tutorial.isDone)
        XCTAssertEqual(r.voice.tutorial.phase, .hidden)
    }

    // MARK: feedback events

    func testFeedbackRepThenLearnedShowsHeardPillAndHop() {
        let r = make()
        for i in 0..<VoiceTuning.repsToLearn {
            if r.brain.idleState.kind != .sit {
                r.brain.idleReset(r.rig.skinner)
                XCTAssertTrue(r.brain.idleStart(.sit, r.rig.sim))
            }
            r.say("sit down")
            if i < VoiceTuning.repsToLearn - 1 { XCTAssertEqual(r.voice.feedbackLog.last, .rep(.sit, reps: i + 1)) }
        }
        XCTAssertEqual(r.voice.feedbackLog.last, .learned(.sit, word: "sit down"))
        XCTAssertEqual(r.voice.heard?.text, "\u{201C}sit down\u{201D}", "the heard pill quotes the player's words")
        XCTAssertEqual(r.voice.toast?.text, "Learned \u{201C}sit down\u{201D} \u{2192} Sit")
    }

    func testFeedbackObeyedUnknownNothingGrumpyMissed() {
        let r = make()
        r.voice.training.debugLearn(.sit, word: "sit")
        r.say("sit", settle: 0.1)
        XCTAssertEqual(r.voice.feedbackLog.last, .obeyed(.sit))
        r.run(4)
        r.say("banana", settle: 0.1)
        XCTAssertEqual(r.voice.feedbackLog.last, .unknown)
        r.say("", settle: 0.1)
        XCTAssertEqual(r.voice.feedbackLog.last, .nothing)
        XCTAssertEqual(r.voice.heard?.text, "\u{2026}")
        for k in NeedKind.allCases { r.care.needs.set(k, 0) }
        r.run(0.2)
        r.say("sit", settle: 0.1)
        XCTAssertEqual(r.voice.feedbackLog.last, .grumpy)
        let m = make(roll: 0.99)
        m.voice.training.debugLearn(.sit, word: "sit", reliability: 0.5)
        m.say("sit", settle: 0.1)
        XCTAssertEqual(m.voice.feedbackLog.last, .missed(.sit, pct: 50))
    }

    func testFeedbackComeHereShowsCheckThenFocus() {
        let r = make()
        r.say("come here", settle: 0.1)
        XCTAssertEqual(r.voice.feedbackLog.last, .obeyed(.come), "check bubble before the zoom")
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused })
    }

    func testTrickBookRowShowsPromptAndNoBubble() {
        let r = make()
        r.voice.show(.sit)
        XCTAssertEqual(r.voice.teachPrompt?.trick, .sit)
        r.run(0.3)
        XCTAssertTrue(r.voice.feedbackLog.isEmpty, "a demonstration is not a command")
        r.say("sit", settle: 0.1)
        XCTAssertNil(r.voice.teachPrompt, "the prompt ends with the word")
    }

    func testUnusableMicOpensTheBookInstead() {
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "VoiceIntegrationTests")!, persists: false)
        let s = StubInput(.unavailable(reason: "x"))
        let v2 = VoiceCoordinator(training: training, input: s)
        XCTAssertTrue(v2.micUnusable)
        XCTAssertFalse(v2.begin(), "no listening on an unusable mic")
        XCTAssertEqual(v2.bookRequest, 1, "the trick book is requested instead")
        XCTAssertEqual(v2.mode.phase, .idle)
    }

    func testShortHoldCancelsAndTeachesNothing() {
        let r = make()
        r.brain.idleReset(r.rig.skinner)
        XCTAssertTrue(r.brain.idleStart(.sit, r.rig.sim))
        r.run(0.1)
        XCTAssertTrue(r.voice.begin())
        r.voice.hear("sit")                                   // no time passed: under 0.25 s
        XCTAssertEqual(r.voice.training.lesson(.sit).reps, 0)
    }
}
