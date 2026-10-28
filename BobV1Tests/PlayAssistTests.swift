//
//  PlayAssistTests.swift
//  The timing assists (round-1023 a11y): forgiving / one-button / auto race, relaxed drill and dance windows, the Show's ring, the bath's "Help me
//  scrub" (it does not press Next), and arranging the room one step at a time.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PlayAssistTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() {
        A11ySettings.shared.raceAssist = .off; A11ySettings.shared.relaxedTiming = false
        ShowAssist.reset(); A11yAnnounce.resetForTests(); A11yEvents.forceActive = false
    }
    override func tearDown() {
        A11ySettings.shared.raceAssist = .off; A11ySettings.shared.relaxedTiming = false
        ShowAssist.reset(); A11yAnnounce.resetForTests(); A11yEvents.forceActive = false; RaceFlow.cueLog = []
    }

    private func startRace(_ assist: RaceAssist, wallet: DropsWallet? = nil) -> RaceFlow {
        A11ySettings.shared.raceAssist = assist
        let f = RaceFlow()
        f.cue = { _ in }; f.drillCue = { _ in }
        f.wallet = wallet
        f.begin(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.9, focus: 1), playerTint: JellyRoster.tint(0), rivalCount: 2, seed: 5)
        var n = 0
        while !f.buttonsLive, n < 60 * 20 { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); n += 1 }
        XCTAssertTrue(f.buttonsLive, "the buttons go live")
        return f
    }
    private func tick(_ f: RaceFlow, _ s: Float) { for _ in 0..<Int(s * 60) { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) } }

    // MARK: race

    func testForgivingIgnoresARepeatedFootButOffStumbles() {
        let off = startRace(.off)
        XCTAssertEqual(off.tap(foot: 0), .queued)
        XCTAssertEqual(off.tap(foot: 0), .stumble, "as designed: the same foot twice stumbles")
        let f = startRace(.forgiving)
        XCTAssertEqual(f.assist, .forgiving)
        XCTAssertEqual(f.tap(foot: 0), .queued)
        XCTAssertEqual(f.tap(foot: 0), .ignored, "forgiven: a bounce of the same finger")
        XCTAssertEqual(f.sim?.racers[0].tap.stumbles, 0)
    }

    func testOneButtonAlternatesByItselfAndNeverStumbles() {
        let f = startRace(.oneButton)
        XCTAssertEqual(f.stepOne(), .queued)
        XCTAssertEqual(f.stepOne(), .ignored, "a second press before the step is taken is dropped, not a stumble")
        for _ in 0..<12 { tick(f, 0.35); _ = f.stepOne() }
        XCTAssertEqual(f.sim?.racers[0].tap.stumbles, 0, "one input can never repeat a foot")
        XCTAssertGreaterThan(f.sim?.racers[0].tap.steps ?? 0, 3, "it runs")
    }

    func testAutoRunFinishesWithNoTapsAndPaysHalf() {
        let w = DropsWallet(persists: false)
        let f = startRace(.auto, wallet: w)
        var n = 0
        while !f.hasResults, n < 60 * 90 { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); n += 1 }
        XCTAssertTrue(f.hasResults, "no taps from the player and the race still ends")
        let place = f.sim!.playerPlace!
        let full = RaceTuning.drops(place: place, tier: f.sim!.course.tier)
        XCTAssertEqual(w.count, full / 2, "auto run pays half")
        XCTAssertEqual(f.ui.earned, full / 2)
        XCTAssertGreaterThan(full / 2, 0)
    }

    func testAssistIsReadWhenTheRaceBegins() {
        let f = startRace(.off)
        XCTAssertEqual(f.assist, .off)
        XCTAssertNil(f.autoAssistRate)
        XCTAssertEqual(startRace(.auto).autoAssistRate, RaceFlow.autoAssistTapRate)
    }

    func testRaceCountdownAndFinishAreAnnounced() {
        A11yEvents.forceActive = true
        var said: [String] = []
        A11yAnnounce.sink = { t, _ in said.append(t) }
        let f = startRace(.auto)
        var n = 0
        while !f.hasResults, n < 60 * 90 { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); n += 1 }
        let idx = ["3", "2", "1", "Go!"].map { said.firstIndex(of: $0) }
        XCTAssertFalse(idx.contains { $0 == nil }, "\(said)")
        XCTAssertEqual(idx.compactMap { $0 }, idx.compactMap { $0 }.sorted(), "in order")
        XCTAssertTrue(said.contains { $0.hasPrefix("Bob finished") && $0.hasSuffix("JellyCoins") }, "\(said)")
    }

    // MARK: drill

    func testRelaxedWindowsGradeALateTapGood() {
        var strict = DrillSim(seed: 3, songTime: 0)
        let p = strict.prompts[0]
        strict.tap(foot: p.foot, at: p.time + TrainingTuning.latencyOffset + 0.15)
        XCTAssertEqual(strict.misses, 1, "150 ms late is a miss as designed")
        var relaxed = DrillSim(seed: 3, songTime: 0)
        relaxed.windowScale = A11ySettings.shared.timingScale == 1 ? 2.5 : A11ySettings.shared.timingScale
        relaxed.tap(foot: p.foot, at: p.time + TrainingTuning.latencyOffset + 0.15)
        XCTAssertEqual(relaxed.misses, 0)
        XCTAssertEqual(relaxed.perfects + relaxed.goods, 1, "relaxed windows: a hit")
    }

    func testOneButtonDrillJudgesTheBeatWhicheverFoot() {
        var d = DrillSim(seed: 3, songTime: 0)
        d.anyFoot = true
        let p = d.prompts[0]
        d.tap(foot: 1 - p.foot, at: p.time + TrainingTuning.latencyOffset)
        XCTAssertEqual(d.perfects, 1, "the wrong foot on the beat still counts with one button")
        var strict = DrillSim(seed: 3, songTime: 0)
        strict.tap(foot: 1 - p.foot, at: p.time + TrainingTuning.latencyOffset)
        XCTAssertEqual(strict.misses, 1)
    }

    func testRelaxedTimingScalesTheSettingsWindow() {
        A11ySettings.shared.relaxedTiming = true
        XCTAssertEqual(A11ySettings.shared.timingScale, 2.5)
        let f = RaceFlow(); f.cue = { _ in }; f.drillCue = { _ in }
        f.stats = JellyStats(persists: false, seedWaddle: 0.3, seedFocus: 0.3)
        f.beginDrill(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.3, focus: 0.3), seed: 5)
        var n = 0
        while f.drill == nil, n < 60 * 30 { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); n += 1 }
        XCTAssertNotNil(f.drill)
        XCTAssertEqual(f.drill?.windowScale, 2.5, "the drill is built with wide windows")
    }

    func testAutoDrillPlaysItselfForHalfTheGain() {
        A11ySettings.shared.raceAssist = .auto
        let st = JellyStats(persists: false, seedWaddle: 0.3, seedFocus: 0.3)
        let f = RaceFlow(); f.cue = { _ in }; f.drillCue = { _ in }; f.stats = st
        f.beginDrill(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.3, focus: 0.3), seed: 5)
        var n = 0
        while f.drillResult == nil, n < 60 * 160 { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); n += 1 }
        let r = f.drillResult
        XCTAssertNotNil(r, "he practises by himself")
        XCTAssertEqual(r?.misses, 0, "auto-steps every prompt")
        let full = st.practiceGain(accuracy: r?.accuracy ?? 0, steadiness: 0).waddle
        XCTAssertGreaterThan(r?.waddleGain ?? 0, 0)
        XCTAssertLessThan(r?.waddleGain ?? 1, full, "half the gain of a player who earned the same accuracy")
    }

    func testPromptsPlayALeftRightCueWhenRelaxed() {
        A11yEvents.forceActive = true
        let f = RaceFlow(); f.cue = { _ in }; f.drillCue = { _ in }
        f.beginDrill(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.3, focus: 0.3), seed: 5)
        var n = 0
        while f.drill == nil, n < 60 * 30 { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); n += 1 }
        let d = f.drill!
        RaceFlow.cueLog = []
        f.promptCues(song: d.prompts[2].time + 0.1)
        XCTAssertEqual(RaceFlow.cueLog, d.prompts.prefix(3).map(\.foot), "each prompt is cued once, on its own side, in order")
        f.promptCues(song: d.prompts[2].time + 0.1)
        XCTAssertEqual(RaceFlow.cueLog.count, 3, "never twice")
    }

    // MARK: show

    func testShowWindowsAndRingFollowRelaxedTiming() {
        XCTAssertEqual(ShowScoring.ringSeconds, 1.2, accuracy: 1e-9)
        A11ySettings.shared.relaxedTiming = true
        ShowAssist.refresh()
        XCTAssertEqual(ShowAssist.windowScale, 2.5)
        XCTAssertEqual(ShowScoring.ringSeconds, 2.4, accuracy: 1e-9, "the ring closes at half speed")
        XCTAssertGreaterThan(ShowScoring.timing(error: 0.3), 0.5, "a tap 300 ms off still scores well")
        let g = ShowBeat.stage
        let d = ShowDanceSim(count: 4, grid: g, timing: .standard, seed: 1, songTime: 0)
        XCTAssertEqual(d.timing.good, TrainingTuning.goodWindow * 2.5, accuracy: 1e-9)
        ShowAssist.reset()
        XCTAssertEqual(ShowDanceSim(count: 4, grid: g, timing: .standard, seed: 1, songTime: 0).timing.good, TrainingTuning.goodWindow, accuracy: 1e-9)
        XCTAssertEqual(ShowScoring.ringSeconds, 1.2, accuracy: 1e-9)
    }

    // MARK: bath

    /// A bath flow on a bare brain (no soft body: a Debug physics step costs ~100 ms), ticked until it reaches the soap step.
    private func bathAtSoap() -> (bath: BathFlow, brain: BlobBrain)? {
        let bath = BathFlow(persists: false, sound: SilentSound())
        Self.keep.append(bath)
        let brain = BlobBrain.forGame(); Self.keep.append(brain)
        bath.haptic = { _, _ in }; bath.success = {}
        bath.start(brain: brain)
        for _ in 0..<(60 * 20) { bath.tick(brain: brain, sim: nil, play: nil, dt: 1 / 60); if bath.phase == .soap { return (bath, brain) } }
        return nil
    }

    func testHelpMeScrubFinishesTheSoapStepButDoesNotPressNext() {
        guard let (bath, brain) = bathAtSoap() else { return XCTFail("the bath reaches the soap step") }
        XCTAssertFalse(bath.stageComplete)
        bath.assistScrub = true
        for _ in 0..<(60 * 60) { bath.tick(brain: brain, sim: nil, play: nil, dt: 1 / 60); if bath.stageComplete { break } }
        XCTAssertTrue(bath.stageComplete, "the assist scrubbed for him, with no touches at all")
        XCTAssertEqual(bath.phase, .soap, "and stopped at the step: the player still taps Next")
        XCTAssertFalse(bath.assistScrub, "the assist ends with the step")
        for _ in 0..<180 { bath.tick(brain: brain, sim: nil, play: nil, dt: 1 / 60) }
        XCTAssertEqual(bath.phase, .soap, "nothing advances by itself")
        bath.advance()
        XCTAssertEqual(bath.phase, .rinse)
        XCTAssertFalse(bath.assistScrub)
    }

    func testWithoutTheAssistNothingScrubs() {
        guard let (bath, brain) = bathAtSoap() else { return XCTFail("soap") }
        for _ in 0..<(60 * 10) { bath.tick(brain: brain, sim: nil, play: nil, dt: 1 / 60) }
        XCTAssertFalse(bath.stageComplete, "no finger, no assist: no progress")
        XCTAssertEqual(bath.progress, 0, accuracy: 1e-6)
    }

    func testBathStageDoneIsAnnounced() {
        A11yEvents.forceActive = true
        var said: [String] = []
        A11yAnnounce.sink = { t, _ in said.append(t) }
        guard let (bath, brain) = bathAtSoap() else { return XCTFail("soap") }
        bath.assistScrub = true
        for _ in 0..<(60 * 60) { bath.tick(brain: brain, sim: nil, play: nil, dt: 1 / 60); if bath.stageComplete { break } }
        XCTAssertTrue(said.contains("Scrub on the jelly soap"), "\(said)")
        XCTAssertTrue(said.contains("Soap done. Tap Next"), "\(said)")
        XCTAssertEqual(BathFlow.stageDoneAnnouncement(.rinse), "Rinse done. Tap Next")
    }

    // MARK: arranging

    func testArrangeStepsMoveThePieceAndRespectObstacles() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        let care = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "PlayAssist.arrange")!)
        Self.keep.append(care)
        care.store.grant("decor-cushion")
        let p = care.placeDecor("decor-cushion")!
        _ = care.dragDecor(p.uid, to: SIMD2(-2.7, 1.0))
        var said: [String] = []
        A11yAnnounce.sink = { t, _ in said.append(t) }
        let before = care.store.placedDecor.first!.at
        XCTAssertTrue(ArrangeAssist.move(p.uid, .right, care: care))
        let afterRight = care.store.placedDecor.first!.at
        XCTAssertGreaterThan(afterRight.x, before.x, "a step to the right")
        XCTAssertLessThanOrEqual(afterRight.x - before.x, ArrangeAssist.step + 0.05)
        XCTAssertTrue(ArrangeAssist.move(p.uid, .forward, care: care))
        XCTAssertGreaterThan(care.store.placedDecor.first!.at.y, afterRight.y, "a step closer to the camera")
        XCTAssertTrue(said.contains { $0.hasSuffix("moved right") })
        // walk it off the room: it stops at the wall and says so
        var stuck = false
        for _ in 0..<80 where !ArrangeAssist.move(p.uid, .left, care: care) { stuck = true; break }
        XCTAssertTrue(stuck, "it cannot leave the room")
        XCTAssertTrue(said.contains { $0.hasSuffix("can't go there") }, "\(said)")
        // pieces cycle
        care.store.grant("decor-cushion")
        _ = care.placeDecor("decor-cushion")
        let first = ArrangeAssist.next(care: care), second = ArrangeAssist.next(care: care), third = ArrangeAssist.next(care: care)
        XCTAssertNotNil(first); XCTAssertNotEqual(first, second); XCTAssertEqual(first, third, "wraps")
        care.putAwayDecor(p.uid)
    }
}
