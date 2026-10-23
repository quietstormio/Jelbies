//
//  JelbieA11yTests.swift
//  The Jelbies as accessibility elements (round-1023): the spoken label / value, the custom actions per state, each action calling the right care API,
//  blocked actions saying why, the scripted fingers, and the announcements.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class JelbieA11yTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() {
        A11yAnnounce.resetForTests()
        A11yEvents.forceActive = true
        A11ySettings.shared.announcements = true
    }
    override func tearDown() {
        A11yEvents.forceActive = false
        A11yAnnounce.resetForTests()
    }

    /// A headless care. (Released GameCares crash the runtime: see MelonModel, so every one is kept.)
    private func care3(_ suite: String) -> GameCare {
        let c = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: suite)!)
        Self.keep.append(c); return c
    }

    /// One shared three-Jelly rig (building it is slow); every test that uses it puts it back the way it was.
    private static var shared: FocusAnyRun?
    private func run3() -> FocusAnyRun {
        if Self.shared == nil { let r = FocusAnyRun(); Self.keep.append(r); r.run(1.5); r.care.tickRace(r.actors, dt: 1 / 60); Self.shared = r }
        let r = Self.shared!
        r.care.focus.force(.roaming); r.care.focusGroup.clear(); r.care.arranging = false; r.care.nightRest = NightRestBook()
        for a in r.actors { a.brain?.idleState.kind = nil; a.brain?.activity = .idle }
        return r
    }

    // MARK: words

    func testValueSaysWhereHowAndWhatHeWants() {
        var s = JelbieA11yText.State()
        s.xFraction = 0.5; s.front = true; s.mood = .happy; s.wanting = ["Hungry"]; s.activity = .sitting
        XCTAssertEqual(JelbieA11yText.value(s), "Middle, front. Happy. Hungry. Sitting.")
        s.xFraction = 0.1; s.front = false; s.wanting = []; s.activity = .asleep; s.mood = .okay
        XCTAssertEqual(JelbieA11yText.value(s), "Left, back. Okay. Needs are fine. Asleep.")
        s.xFraction = 0.9; s.highlighted = true; s.dirty = true; s.inCloseUp = true
        let v = JelbieA11yText.value(s)
        XCTAssertTrue(v.hasPrefix("Right, back."), v)
        XCTAssertTrue(v.contains("Highlighted") && v.contains("Coat is dirty") && v.contains("In close-up"), v)
    }

    func testLabelNamesTheFeatureNotJustTheColour() {
        XCTAssertEqual(JelbieA11yText.label(name: "Pip", character: 1), "Pip, yellow with soft spines")
        XCTAssertTrue(JelbieA11yText.label(name: "Moss", character: 2).contains("daisy"))
        XCTAssertTrue(JelbieA11yText.label(name: "Lavender", character: 3).contains("wings"))
        XCTAssertTrue(JelbieA11yText.label(name: "Bob", character: 0).contains("plain"))
        for c in 0..<4 { XCTAssertEqual(Set((0..<4).map { JelbieA11yText.description(character: $0) }).count, 4, "all four are told apart by words (\(c))") }
    }

    func testRoomValueListsThemLeftToRight() {
        let v = JelbieA11yText.room(phase: "Day", placed: [("Moss", 0.5), ("Pip", 0.1), ("Lavender", 0.9)])
        XCTAssertEqual(v, "Day. 3 Jelbies: Pip on the left, Moss in the middle, Lavender on the right")
        XCTAssertEqual(JelbieA11yText.room(phase: "Night", placed: []), "Night. No Jelbies in the room")
    }

    func testActivityFromTheBrain() {
        let r = run3()
        let b = r.actors[1].brain!
        XCTAssertEqual(JelbieA11yContainer.activity(of: nil), .standing)
        b.activity = .eating
        XCTAssertEqual(JelbieA11yContainer.activity(of: b), .eating)
        b.activity = .idle
        b.idleState.kind = .sleep
        XCTAssertEqual(JelbieA11yContainer.activity(of: b), .asleep)
        XCTAssertEqual(JelbieA11yContainer.activity(of: b, washing: true), .beingWashed)
    }

    // MARK: actions per state

    func testActionListPerState() {
        let care = care3("JA11y.list")
        XCTAssertEqual(JelbieActions.available(care, id: 1, asleep: false), [.highlight, .callOver, .feed, .water, .train, .bed])
        XCTAssertEqual(JelbieActions.available(care, id: 1, asleep: true), [.highlight, .callOver, .feed, .water, .train, .wake])
        // in a close-up on him: the touches
        care.focusGroup.begin(ids: [1]); care.focus.force(.focused)
        XCTAssertEqual(JelbieActions.available(care, id: 1, asleep: false), [.pet, .patHead, .boopCheek, .pokeBelly, .squishCheeks, .toss, .letGo])
        XCTAssertTrue(JelbieActions.available(care, id: 2, asleep: false).isEmpty, "someone else is not in this close-up")
        care.focus.force(.roaming); care.focusGroup.clear()
        // away at the track: nothing
        care.arranging = true
        XCTAssertTrue(JelbieActions.available(care, id: 1, asleep: false).isEmpty, "arranging the room blocks them")
    }

    func testEveryActionHasATitleWithTheName() {
        for a in JelbieAction.allCases { XCTAssertTrue(a.title("Pip").contains("Pip"), "\(a)") }
        XCTAssertEqual(Set(JelbieAction.allCases.compactMap(\.script)).count, 6, "six scripted touches")
    }

    // MARK: each action calls the care API the HUD calls

    func testHighlightCallTrainFeedBedWake() {
        let care = care3("JA11y.hl")
        XCTAssertTrue(JelbieActions.perform(.highlight, id: 2, care: care))
        XCTAssertEqual(care.highlightedJelly, 2)
        XCTAssertTrue(JelbieActions.perform(.feed, id: 1, care: care))
        XCTAssertTrue(care.trayOut, "Feed starts a meal like the HUD button")
        // bed
        XCTAssertTrue(JelbieActions.perform(.bed, id: 2, care: care3("JA11y.bed")))
        // call
        let c2 = care3("JA11y.call")
        XCTAssertTrue(JelbieActions.perform(.callOver, id: 1, care: c2))
        XCTAssertEqual(c2.focus.phase, .approaching)
        XCTAssertEqual(c2.focusGroup.ids, [1])
        // train
        let c3 = care3("JA11y.train")
        XCTAssertTrue(JelbieActions.perform(.train, id: 2, care: c3))
        XCTAssertTrue(c3.focusGroup.trainPending)
        XCTAssertEqual(c3.focusGroup.ids, [2])
    }

    func testBedAndWakeAskTheRightJelbie() {
        let r = run3(); let care = r.care
        XCTAssertTrue(JelbieActions.perform(.bed, id: 2, care: care))
        XCTAssertTrue(care.nightRest.wanted.contains(2) || care.nightRest.dayOnce.contains(2))
        XCTAssertFalse(care.nightRest.wanted.contains(1) || care.nightRest.dayOnce.contains(1))
        let b = care.selectBrain(1)!
        b.idleState.kind = .sleep
        XCTAssertTrue(JelbieActions.perform(.wake, id: 1, care: care, asleep: true))
        XCTAssertTrue(b.sleep.wakeAsked, "wake asked only for him")
        XCTAssertFalse(JelbieActions.perform(.wake, id: 2, care: care, asleep: false), "an awake one cannot be woken")
        XCTAssertEqual(A11yAnnounce.log.last, "Moss is awake")
    }

    func testBlockedActionsReturnFalseAndSayWhy() {
        let care = care3("JA11y.blk")
        XCTAssertTrue(JelbieActions.perform(.feed, id: 1, care: care))
        A11yAnnounce.resetForTests(); var said: [String] = []
        A11yAnnounce.sink = { t, _ in said.append(t) }
        XCTAssertFalse(JelbieActions.perform(.feed, id: 2, care: care), "a tray is already out")
        XCTAssertEqual(said, ["Food is already out"])
        said = []
        XCTAssertFalse(JelbieActions.perform(.water, id: 2, care: care))
        XCTAssertEqual(said, ["A drink is already out"])
        // close-up touches before he has arrived
        let c = care3("JA11y.blocked")
        c.comeHere(jelly: 1)
        said = []
        XCTAssertFalse(JelbieActions.perform(.pet, id: 1, care: c))
        XCTAssertEqual(said, ["Pip is still coming over"])
        // a roaming Jelbie cannot be petted
        c.focus.force(.roaming); c.focusGroup.clear(); said = []
        XCTAssertFalse(JelbieActions.perform(.pet, id: 1, care: c))
        XCTAssertEqual(said, ["Call Pip over first"])
        // arranging
        c.arranging = true; said = []
        XCTAssertFalse(JelbieActions.perform(.feed, id: 1, care: c))
        XCTAssertEqual(said, ["Finish arranging the room first"])
    }

    func testTouchesStartAScriptOnlyInTheCloseUp() {
        let care = care3("JA11y.touch")
        care.focusGroup.begin(ids: [1]); care.focus.force(.focused)
        var started: [(ScriptedTouch.Kind, Int)] = []
        for a in [JelbieAction.pet, .patHead, .boopCheek, .pokeBelly, .squishCheeks, .toss] {
            XCTAssertTrue(JelbieActions.perform(a, id: 1, care: care) { k, id in started.append((k, id)); return true })
        }
        XCTAssertEqual(started.map(\.0), [.pet, .patHead, .boopCheek, .pokeBelly, .squishCheeks, .toss])
        XCTAssertTrue(started.allSatisfy { $0.1 == 1 })
        XCTAssertTrue(JelbieActions.perform(.letGo, id: 1, care: care))
        XCTAssertEqual(care.focus.phase, .leaving)
    }

    // MARK: scripted fingers

    func testScriptsStartDownAndEndUpAndAreGentle() {
        for kind in ScriptedTouch.Kind.allCases {
            var run = ScriptedTouchRun(kind, jelly: 0, start: 0)
            var downs = [0, 0], ups = [0, 0], maxStep: Float = 0
            var last: [SIMD2<Float>?] = [nil, nil]
            var t = 0.0
            while !run.finished, t < 6 {
                for e in run.step(now: t) {
                    switch e {
                    case .down(let k, let p): downs[k] += 1; last[k] = p
                    case .move(let k, let p): if let l = last[k] { maxStep = max(maxStep, simd_length(p - l)) }; last[k] = p
                    case .up(let k): ups[k] += 1; last[k] = nil
                    }
                }
                t += 1.0 / 60
            }
            XCTAssertTrue(run.finished, "\(kind)")
            XCTAssertEqual(downs, ups, "\(kind): every finger goes down once per lift")
            XCTAssertGreaterThan(downs[0], 0, "\(kind)")
            XCTAssertLessThan(maxStep, 0.12, "\(kind): a smooth path (no flick)")
        }
        // the cheeks are two fingers, 0.1 s apart; nothing else is
        XCTAssertNotNil(ScriptedTouch(kind: .squishCheeks).frame(at: 0.2)[1])
        XCTAssertNil(ScriptedTouch(kind: .squishCheeks).frame(at: 0.05)[1])
        XCTAssertNil(ScriptedTouch(kind: .pet).frame(at: 0.5)[1])
    }

    func testARealTouchCancelsTheScript() {
        var run = ScriptedTouchRun(.pet, jelly: 0, start: 0)
        _ = run.step(now: 0.3)
        let e = run.step(now: 0.4, cancelled: true)
        XCTAssertEqual(e, [.up(0)])
        XCTAssertTrue(run.finished)
    }

    func testTossStaysBelowAThrow() {
        // the lift's speed (sim units / s) times a generous 500 pt per unit stays under the throw threshold
        let t = ScriptedTouch(kind: .toss)
        var peak: Float = 0
        var prev = t.frame(at: 0.35)[0]!
        var x = 0.36
        while x < 1.05 { let p = t.frame(at: x)[0]!; peak = max(peak, abs(p.y - prev.y) * 60); prev = p; x += 1.0 / 60 }
        XCTAssertLessThan(Double(peak) * 500, Double(TouchGesture.throwSpeed), "a toss is put down, not thrown (peak \(peak) u/s)")
    }

    // MARK: announcements

    func testNeedsSleepAndCloseUpAreAnnounced() {
        let r = run3(); let care = r.care
        var said: [String] = []
        A11yAnnounce.sink = { t, _ in said.append(t) }
        let ev = care.a11yEvents
        ev.poll(now: 0)                                  // the first poll only records
        care.selectBrain(2)?.idleState.kind = .sleep
        ev.poll(now: 20)
        XCTAssertTrue(said.contains("Moss fell asleep"), "\(said)")
        care.selectBrain(2)?.idleState.kind = nil
        ev.poll(now: 40)
        XCTAssertTrue(said.contains("Moss woke up"), "\(said)")
        care.focusGroup.begin(ids: [1]); care.focus.force(.focused)
        ev.poll(now: 41)
        XCTAssertTrue(said.contains { $0.hasPrefix("Close-up with Pip") }, "\(said)")
        XCTAssertEqual(A11yEvents.needAppeared(name: "Pip", kind: .hunger, tier: .hungry), "Pip is hungry")
        XCTAssertEqual(A11yEvents.needFixed(name: "Pip", kind: .hunger), "Pip is full")
        XCTAssertEqual(A11yEvents.raceFinish(name: "Pip", place: 2, drops: 7), "Pip finished 2nd. 7 Drops")
        XCTAssertEqual(A11yEvents.trickLearned(name: "Moss", trick: "Sit"), "Moss learned Sit")
    }

    func testNothingIsSpokenWhenVoiceOverIsOff() {
        A11yEvents.forceActive = false
        A11yAnnounce.resetForTests()
        var said: [String] = []
        A11yAnnounce.sink = { t, _ in said.append(t) }
        A11yEvents.say("Pip is hungry")
        if !UIAccessibility.isVoiceOverRunning { XCTAssertTrue(said.isEmpty) }
    }
}

/// Typed teaching: three typed submits during the move teach a trick like three listens, with no microphone, and VoiceOver hears it.
@MainActor
final class VoiceTypedTeachTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { RoomLayout.dynamicBoxes = []; A11yAnnounce.resetForTests(); A11yEvents.forceActive = true; A11ySettings.shared.announcements = true }
    override func tearDown() { RoomLayout.dynamicBoxes = []; A11yEvents.forceActive = false; A11yAnnounce.resetForTests() }

    @MainActor final class Run {
        let rig = MotionRig(game: true, settle: 1.0)
        var t = 100.0
        let care: GameCare
        let training: VoiceTraining
        init() {
            training = VoiceTraining(defaults: UserDefaults(suiteName: "VoiceTypedTeach")!, persists: false, random: { 0 })
            var clock: () -> Double = { 0 }
            care = GameCare(voice: VoiceCoordinator(training: training, input: FakeSpeechInput(), now: { clock() }))
            clock = { [unowned self] in self.t }
            for k in NeedKind.allCases { care.needs.set(k, 1) }
            rig.brain.autonomy = true; rig.brain.seed = 7
        }
        func run(_ s: Float) {
            for _ in 0..<Int(s * 60) {
                rig.brain.idleBlocked = care.trayOut && !rig.brain.commanded
                rig.brain.tick(sim: rig.sim, skinner: rig.skinner, dt: rig.sim.stepDt, touched: false)
                care.tick(brain: rig.brain, renderer: nil, dt: rig.sim.stepDt, sim: rig.sim)
                rig.sim.step(); rig.t += rig.sim.stepDt; t += Double(rig.sim.stepDt)
            }
        }
    }

    func testThreeTypedLessonsTeachATrickAndAreAnnounced() {
        let r = Run(); Self.keep.append(r)
        var said: [String] = []
        A11yAnnounce.sink = { t, _ in said.append(t) }
        r.run(0.3)
        for i in 0..<VoiceTuning.repsToLearn {
            r.care.voice.show(.sit)                    // the trick-book row: he does it now and the next word binds
            r.run(0.3)
            r.care.voice.typed("sit")
            r.run(0.3)
            XCTAssertEqual(r.training.lesson(.sit).reps, i + 1, "typed lesson \(i + 1) counted")
        }
        XCTAssertTrue(r.training.isLearned(.sit))
        XCTAssertEqual(r.training.word(for: .sit), "sit")
        XCTAssertTrue(said.contains("Bob learned Sit"), "\(said)")
        XCTAssertTrue(said.contains("Sit: 1 of 3 lessons"), "\(said)")
    }

    func testEmptyTypedWordDoesNothing() {
        let r = Run(); Self.keep.append(r)
        r.care.voice.typed("   ")
        r.run(0.2)
        XCTAssertEqual(r.training.lesson(.sit).reps, 0)
        XCTAssertTrue(A11yAnnounce.log.isEmpty)
    }

    func testTapToTalkToggles() {
        let r = Run(); Self.keep.append(r)
        A11ySettings.shared.tapToTalk = true
        defer { A11ySettings.shared.tapToTalk = false }
        XCTAssertTrue(VoiceCoordinator.tapMode)
        XCTAssertTrue(r.care.voice.toggleListening(), "the first tap opens the listen")
        XCTAssertTrue(r.care.voice.isListening)
        r.care.voice.toggleListening()                  // the second tap closes it
        XCTAssertFalse(r.care.voice.isListening)
    }
}
