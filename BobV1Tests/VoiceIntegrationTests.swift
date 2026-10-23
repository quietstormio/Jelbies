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
    init(roll: Double = 0, model: VoiceIntentModel? = nil) {
        let c = clock
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "VoiceIntegrationTests")!, persists: false, random: { roll })
        care = GameCare(voice: VoiceCoordinator(training: training, input: FakeSpeechInput(), intentModel: model, now: { c.t }))
        for k in NeedKind.allCases { care.needs.set(k, 1) }            // not grumpy unless a test says so
        brain.autonomy = true; brain.seed = 7
    }
    func tick() {
        brain.idleMood = care.mood
        brain.idleBlocked = ((care.focus.isActive && care.focusGroup.includes(0)) || care.trayOut) && !brain.commanded
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

    private func make(roll: Double = 0, model: VoiceIntentModel? = nil) -> VoiceRun {
        let r = VoiceRun(roll: roll, model: model)
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

    func testNameWorksOnTheFirstListen() {
        let r = make()
        XCTAssertTrue(r.voice.training.nameLearned, "nothing to learn")
        r.say("bob", settle: 0)
        var hopped = false
        r.run(1) { if case .hopPlay = r.brain.script { hopped = true }; return hopped }
        XCTAssertTrue(r.voice.feedbackLog.isEmpty, "no lesson dots, no bubble: \(r.voice.feedbackLog)")
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

    func testGrumpyComeStillEntersFocus() {
        for roll in [0.0, 0.999] {                                // even a failing reliability roll: grumpy come is always obeyed
            let r = make(roll: roll)
            for k in NeedKind.allCases { r.care.needs.set(k, 0) }
            r.run(0.2)
            XCTAssertEqual(r.care.mood, .grumpy)
            r.say("come here", settle: 0)
            XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused }, "a grumpy Bob comes for the love he wants")
            XCTAssertEqual(r.voice.feedbackLog.last, .obeyed(.come), "check bubble, not the grumpy refusal")
        }
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

// MARK: - names, targets, social commands, the model fallback

extension VoiceIntegrationTests {
    func testGrumpyOtherTricksStillRefuseButComeIsObeyed() {
        let r = make()
        r.voice.training.debugLearn(.sit, word: "sit")
        for k in NeedKind.allCases { r.care.needs.set(k, 0) }
        r.run(0.2)
        r.say("sit", settle: 0.3)
        XCTAssertEqual(r.voice.feedbackLog.last, .grumpy)
        r.say("come here", settle: 0)
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused }, "grumpy Bob still comes")
    }

    func testNamingBobSelectsHimWithTheTapHighlight() {
        let r = make()
        r.brain.autonomy = false
        XCTAssertNil(r.care.select.selectedID)
        r.say("Bobby", settle: 0)
        XCTAssertEqual(r.care.select.selectedID, 0, "same outline highlight a tap gives")
        XCTAssertGreaterThanOrEqual(r.care.select.drawStarts, 1)
        XCTAssertTrue(r.care.select.rosterPick)
    }

    func testNamePlusTrickSelectsAndDoesTheTrick() {
        let r = make()
        r.voice.training.debugLearn(.sit, word: "sit")
        r.say("Bob, sit", settle: 0)
        XCTAssertEqual(r.care.select.selectedID, 0)
        XCTAssertTrue(r.run(3) { r.brain.idleState.kind == .sit })
    }

    func testComeHereIsForTheSelectedOneByDefaultAndPipIsAbsent() {
        let r = make()
        var remote: [(VoiceReaction, [Int])] = []
        r.voice.onRemote = { remote.append(($0, $1)) }
        r.say("Pip, come here", settle: 0)
        r.run(3)
        XCTAssertEqual(r.care.focus.phase, .roaming, "Pip is not in the room: nothing happens to Bob")
        XCTAssertTrue(remote.isEmpty)
        XCTAssertEqual(r.voice.feedbackLog.last, .unknown, "confused look")
    }

    func testPipComeHereGoesToPhaseBHooksNotBob() {
        let r = make()
        r.voice.jellyIDs = { [0, 1, 2] }
        var remote: [(VoiceReaction, [Int])] = []
        var selected: [Int] = []
        r.voice.onRemote = { remote.append(($0, $1)) }
        r.voice.onSelect = { selected.append($0) }
        r.say("Pip, come here", settle: 0)
        r.run(3)
        XCTAssertEqual(r.care.focus.phase, .roaming, "Bob stays")
        XCTAssertEqual(remote.count, 1)
        XCTAssertEqual(remote.first?.0, .perform(.come)); XCTAssertEqual(remote.first?.1, [1])
        XCTAssertTrue(selected.isEmpty, "naming for come skips the highlight: the close-up is the selection")
    }

    func testEveryoneComeHereCallsAllAndBobComes() {
        let r = make()
        r.voice.jellyIDs = { [0, 1, 2] }
        var every: [[Int]] = [], came: [[Int]] = []
        r.voice.onEveryone = { every.append($0) }
        r.voice.onComeHere = { ids in came.append(ids); if ids.contains(0) { r.care.comeHere() } }
        r.say("everyone, come here", settle: 0)
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused })
        XCTAssertEqual(every, [[0, 1, 2]]); XCTAssertEqual(came, [[0, 1, 2]])
    }

    func testPlainEveryoneComeWithOneJellyIsBob() {
        let r = make()
        r.say("everybody over here", settle: 0)
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused })
    }

    func testStopEndsASitAndStopFightingCallsTheHook() {
        let r = make()
        r.voice.training.debugLearn(.sit, word: "sit")
        var fought: [[Int]] = []
        r.voice.onStopFighting = { fought.append($0) }
        r.brain.autonomy = false
        r.say("sit", settle: 0)
        XCTAssertTrue(r.run(3) { r.brain.idleState.kind == .sit })
        r.run(1)
        r.say("stop", settle: 0)
        XCTAssertTrue(r.run(4) { r.brain.idleState.kind == nil }, "the sit ended")
        r.say("stop fighting", settle: 0)
        r.run(1)
        XCTAssertEqual(fought, [[0]])
        XCTAssertEqual(r.voice.feedbackLog.last, .social(.stopFighting))
    }

    func testPraiseGivesAttentionAndAHeartScoldDroops() {
        let r = make()
        r.care.needs.set(.attention, 0.5)
        r.brain.autonomy = false
        r.say("good boy", settle: 0)
        r.run(0.5)
        XCTAssertEqual(r.care.needs.levels[NeedKind.attention.rawValue], 0.5 + VoiceTuning.praiseAttention, accuracy: 0.02)
        var hopped = false
        r.run(3) { if case .hopPlay = r.brain.script { hopped = true }; return hopped }
        XCTAssertTrue(hopped, "happy hop")
        r.run(2)
        r.say("bad", settle: 0)
        XCTAssertTrue(r.run(3) { r.brain.idleState.kind == .slump }, "droop")
        XCTAssertEqual(r.voice.feedbackLog.last, .social(.scold))
    }

    func testGoodnightPutsHimToBedOnHisBackTuckedInAndATapWakesHim() {
        let r = make()
        r.brain.autonomy = false
        var asked: [[Int]] = []
        r.voice.jellyIDs = { [0, 1, 2] }
        r.voice.onGoodnight = { ids in asked.append(ids); r.brain.commandedGoodnight = true }
        r.say("goodnight everyone", settle: 0)
        r.run(1)
        XCTAssertEqual(asked, [[0, 1, 2]], "everyone is asked to go to bed")
        XCTAssertEqual(r.voice.feedbackLog.last, .social(.goodnight))
        XCTAssertTrue(r.run(40) { r.brain.isNapping }, "yawn, roll onto the back, asleep")
        XCTAssertTrue(r.brain.sleep.tucked, "tucked in")
        XCTAssertGreaterThan(r.rig.sim.bodyPose(iterations: 4).rotation.act(SIMD3<Float>(0, 0, 1)).y, sinf(SleepTuning.lieAngle) - 0.02, "on his back")
        // a tap wakes him gently
        for _ in 0..<8 { r.brain.tick(sim: r.rig.sim, skinner: r.rig.skinner, dt: r.rig.sim.stepDt, touched: true); r.rig.sim.step() }
        XCTAssertTrue(r.run(10) { r.brain.idleState.kind == nil }, "up again")
        // a named one, and the selected one
        r.say("Pip good night", settle: 0)
        r.run(1)
        XCTAssertEqual(asked.last, [1])
        r.say("night night", settle: 0)
        r.run(1)
        XCTAssertEqual(asked.last, [0, 1, 2], "nobody selected: every awake Jelly goes to bed")
    }

    func testGoodnightWithoutAGroupHookSendsTheOneBrainToBed() {
        let r = make()
        r.brain.autonomy = false
        r.say("bedtime", settle: 0)
        XCTAssertTrue(r.run(40) { r.brain.isNapping }, "he goes to bed on his own")
        XCTAssertEqual(r.voice.goodnightLog.last, [0])
    }

    func testNicknameTaughtByVoiceThreeTimesThenUsed() {
        let r = make()
        r.voice.startNicknameLesson(for: 0)
        r.say("bubbles", settle: 0.1); XCTAssertEqual(r.voice.nickLesson?.reps, 1)
        r.say("bubbles", settle: 0.1); XCTAssertEqual(r.voice.nickLesson?.reps, 2)
        r.say("bubbles", settle: 0.1)
        XCTAssertNil(r.voice.nickLesson)
        XCTAssertEqual(r.voice.training.names.nicknames(for: 0), ["bubbles"])
        r.run(5)
        r.say("bubbles, come here", settle: 0)
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused }, "the nickname is a name")
    }

    func testNicknameLessonRestartsOnADifferentWordAndRejectsNames() {
        let r = make()
        r.voice.startNicknameLesson(for: 0)
        r.say("bubbles", settle: 0.1)
        r.say("wiggles", settle: 0.1)
        XCTAssertEqual(r.voice.nickLesson?.reps, 1); XCTAssertEqual(r.voice.nickLesson?.word, "wiggles")
        r.say("Pip", settle: 0.1)
        XCTAssertEqual(r.voice.nickLesson?.reps, 1, "an existing name is not a nickname")
    }

    // The model fallback

    private func hearAndAwait(_ r: VoiceRun, _ words: String) async {
        r.run(0.1)
        XCTAssertTrue(r.voice.begin())
        r.run(0.3)
        r.voice.hear(words)
        await r.voice.intentTask?.value
        r.run(0.3)
        r.run(4) { r.brain.idleState.kind == nil }                     // the "?" tilt (a look) ends: a word said during it would teach "look"
    }

    func testModelMapsFreePhrasingToALearnedTrick() async {
        let fake = FakeIntentModel()
        fake.result = ModelIntent(action: .trick(.flip), confidence: 0.9)
        let r = make(model: fake)
        r.voice.training.debugLearn(.flip, word: "wheee")
        r.brain.autonomy = false
        await hearAndAwait(r, "do a backflip for me")
        XCTAssertEqual(fake.calls, ["do a backflip for me"])
        XCTAssertEqual(r.voice.lastParse?.path, "model")
        XCTAssertEqual(r.voice.feedbackLog.last, .obeyed(.flip))
        XCTAssertEqual(fake.prewarms, 1, "prewarmed when the mic opened")
        XCTAssertEqual(fake.lastLearned, [.flip])
    }

    func testModelCannotTriggerAnUnlearnedTrick() async {
        let fake = FakeIntentModel()
        fake.result = ModelIntent(action: .trick(.flip), confidence: 0.95)
        let r = make(model: fake)
        r.brain.autonomy = false
        await hearAndAwait(r, "do a backflip for me")
        XCTAssertEqual(r.voice.feedbackLog.last, .unknown, "confused look, no flip")
        XCTAssertEqual(r.brain.flipTakeoffs, 0)
    }

    func testModelTargetsAndSocialAndComeWhenGrumpy() async {
        let fake = FakeIntentModel()
        let r = make(model: fake)
        r.voice.jellyIDs = { [0, 1, 2] }
        var remote: [(VoiceReaction, [Int])] = []
        r.voice.onRemote = { remote.append(($0, $1)) }
        fake.result = ModelIntent(targetKind: .named, targetName: "pippy", action: .social(.praise), confidence: 0.8)
        await hearAndAwait(r, "what a lovely creature you are")
        XCTAssertEqual(remote.first?.1, [1], "the model's name goes through the registry")
        fake.result = ModelIntent(targetKind: .everyone, action: .come, confidence: 0.8)
        for k in NeedKind.allCases { r.care.needs.set(k, 0) }
        r.run(0.2)
        r.voice.onComeHere = { _ in r.care.comeHere() }
        await hearAndAwait(r, "who wants to come see me")
        XCTAssertTrue(r.run(40) { r.care.focus.phase == .focused }, "grumpy come through the model path too")
    }

    func testModelLowConfidenceNoneErrorAndTimeoutFallBack() async {
        let fake = FakeIntentModel()
        let r = make(model: fake)
        r.brain.autonomy = false                                   // no wander move running that a word could be taught on
        fake.result = ModelIntent(action: .social(.praise), confidence: 0.2)
        await hearAndAwait(r, "go get some water buddy")
        XCTAssertEqual(r.voice.feedbackLog.last, .unknown, "low confidence ignored")
        fake.result = ModelIntent(action: .none, confidence: 1)
        await hearAndAwait(r, "the weather is nice")
        XCTAssertEqual(r.voice.feedbackLog.last, .unknown)
        fake.error = VoiceModelError.unavailable
        await hearAndAwait(r, "something else entirely")
        XCTAssertEqual(r.voice.lastParse?.path, "error")
        fake.error = nil; fake.delay = 2; fake.result = ModelIntent(action: .social(.praise), confidence: 1)
        let old = VoiceTuning.modelBudget; VoiceTuning.modelBudget = 0.1
        defer { VoiceTuning.modelBudget = old }
        await hearAndAwait(r, "very slow phrase")
        XCTAssertEqual(r.voice.lastParse?.path, "timeout")
        XCTAssertEqual(r.voice.feedbackLog.last, .unknown, "slow model: the deterministic result stands")
    }

    func testUnavailableModelAndDeterministicHitsNeverCallIt() async {
        let fake = FakeIntentModel()
        fake.availability = .unavailable("deviceNotEligible")
        let r = make(model: fake)
        await hearAndAwait(r, "unmatched phrase")
        XCTAssertEqual(r.voice.lastParse?.path, "unavailable")
        XCTAssertTrue(fake.calls.isEmpty)
        fake.availability = .available
        r.voice.training.debugLearn(.sit, word: "sit")
        for w in ["come here", "good boy", "Bob", "sit", "stop fighting"] { await hearAndAwait(r, w); r.run(1) }
        XCTAssertTrue(fake.calls.isEmpty, "the deterministic path is primary: \(fake.calls)")
        XCTAssertEqual(r.voice.lastParse?.path, "det")
    }

    func testTeachingAWordNeverGoesToTheModel() async {
        let fake = FakeIntentModel()
        fake.result = ModelIntent(action: .social(.praise), confidence: 1)
        let r = make(model: fake)
        r.brain.idleReset(r.rig.skinner)
        XCTAssertTrue(r.brain.idleStart(.sit, r.rig.sim))
        await hearAndAwait(r, "mochi")
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertEqual(r.voice.training.lesson(.sit).reps, 1)
    }
}

// MARK: - natural commands (AI/IntentRouter.swift -> CommandExecutor.swift) through the real VoiceCoordinator + GameCare

@MainActor
final class AIVoiceIntegrationTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = [] }

    private func make() -> VoiceRun {
        let r = VoiceRun()
        VoiceIntegrationTests.keep.append(r)
        r.brain.autonomy = false                      // no wander move running that a word could be taught on
        r.run(0.5)
        return r
    }
    /// One listen that goes through the router (rules, no model in tests), then lets the queued command run.
    private func say(_ r: VoiceRun, _ words: String) async {
        r.run(0.1)
        XCTAssertTrue(r.voice.begin())
        r.run(0.3)
        r.voice.hear(words)
        await r.voice.intentTask?.value
        r.run(0.5)
        r.run(4) { r.brain.idleState.kind != .look }           // a "?" look ends before the next phrase (a word said during it would teach "look")
    }

    func testGoToSleepIsTheGoodnight() async {
        let r = make()
        await say(r, "take a nap")                                  // (a phrase the legacy goodnight table does not have: it goes through the router)
        XCTAssertEqual(r.voice.lastParse?.path, "rules")
        XCTAssertEqual(r.voice.feedbackLog.last, .social(.goodnight), "bedtime is the existing goodnight")
        XCTAssertEqual(r.voice.goodnightLog.last, [0])
        XCTAssertTrue(r.run(14) { r.brain.isSleeping }, "he goes to bed")
    }

    func testEveryoneComeEatPutsTheTrayOut() async {
        let r = make()
        XCTAssertFalse(r.care.trayOut)
        await say(r, "everyone come eat")
        XCTAssertEqual(r.voice.lastParse?.path, "rules", "the meal beats the loose come")
        XCTAssertEqual(r.voice.understood?.text, "Everyone: eat")
        XCTAssertTrue(r.care.trayOut, "the meal is ordered")
        XCTAssertEqual(r.voice.feedbackLog.last, .command(.feed))
        XCTAssertNotEqual(r.care.focus.phase, .focused, "no come-here close-up")
    }

    func testWhoIsHungryAnswersWithThePill() async {
        let r = make()
        r.care.needs.set(.hunger, 0.1)
        await say(r, "who's hungry")
        XCTAssertEqual(r.voice.understood?.text, "Bob is hungry"); XCTAssertEqual(r.voice.understood?.ok, true)
        XCTAssertEqual(r.voice.feedbackLog.last, .answer(.hunger, 0))
        // nobody: the thumbs-up answer
        r.care.needs.set(.hunger, 1)
        r.run(3)
        await say(r, "who's hungry")
        XCTAssertEqual(r.voice.understood?.text, "Nobody's hungry")
        XCTAssertEqual(r.voice.feedbackLog.last, .answer(.hunger, nil))
    }

    func testDoASpinNeedsTheTrickPageThenRuns() async {
        let r = make()
        await say(r, "do a spin")
        XCTAssertEqual(r.voice.feedbackLog.last, .unknown, "no spin page bought: the confused look")
        r.care.store.grant("page-spin")
        r.voice.training.debugLearn(.spin, word: "twirl")
        r.run(1)
        await say(r, "do a spin")
        XCTAssertEqual(r.voice.feedbackLog.last, .obeyed(.spin))
        XCTAssertTrue(r.run(3) { r.brain.idleState.kind == .tail }, "the spin trick runs")
    }

    func testGoSitOnThePlacedBeanbagAndWearAnOwnedHat() async {
        let r = make()
        r.care.store.grant("decor-beanbag")
        XCTAssertNotNil(r.care.store.place("decor-beanbag"))
        r.care.syncDecor()
        defer { DecorField.shared.set([]) }
        await say(r, "go sit on the beanbag")
        XCTAssertEqual(r.voice.understood?.text, "go to beanbag"); XCTAssertEqual(r.voice.understood?.ok, true)
        XCTAssertEqual(r.voice.feedbackLog.last, .command(.goTo))
        XCTAssertTrue(r.run(2) { r.brain.idleState.kind == .decorSit }, "he heads for the beanbag")
        // the wardrobe: an owned hat goes on; one he does not own is "not in the wardrobe"
        await say(r, "put on the pirate hat")
        XCTAssertEqual(r.voice.understood?.text, "No pirate hat in the wardrobe"); XCTAssertEqual(r.voice.understood?.ok, false)
        r.care.store.grant("wear-pirate_hat")
        r.run(1)
        await say(r, "put on the pirate hat")
        XCTAssertEqual(r.voice.understood?.text, "put on pirate hat"); XCTAssertEqual(r.voice.understood?.ok, true)
        XCTAssertEqual(r.care.store.worn(0, .head), .pirateHat)
    }

    func testLetsRaceOpensTheTrack() async {
        let r = make()
        let before = r.care.townRequest
        await say(r, "let's race")
        XCTAssertEqual(r.voice.understood?.text, "race"); XCTAssertEqual(r.voice.understood?.ok, true)
        XCTAssertEqual(r.care.townRequest, before + 1); XCTAssertEqual(r.care.townScreen, .track)
    }

    func testUnknownPlaceGetsTheMissingPillAndTheConfusedLook() async {
        let r = make()
        await say(r, "go to the beanbag")
        XCTAssertEqual(r.voice.understood?.text, "No beanbag in the room"); XCTAssertEqual(r.voice.understood?.ok, false)
        XCTAssertEqual(r.voice.feedbackLog.last, .unknown, "the confused \"?\"")
    }

    func testLegacyWordsStillTakeTheDeterministicPath() async {
        let r = make()
        for w in ["come here", "good boy", "stop fighting"] { await say(r, w); XCTAssertEqual(r.voice.lastParse?.path, "det", w); r.run(1) }
        XCTAssertNil(r.voice.understood)
    }
}
