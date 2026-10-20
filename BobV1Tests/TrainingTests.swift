//
//  TrainingTests.swift
//  Practice: the gain formula, Pep (calendar day), dances, the beat grid, drill judging, trained vs untrained racing (trips), the drill flow, and the
//  scene music (loop points, rendering, director events).
//

import XCTest
import AVFoundation
@testable import BobV1

@MainActor
final class TrainingTests: XCTestCase {
    private func stats(waddle: Float = 0.2, focus: Float = 0.2, day: @escaping () -> Int = { 20261019 }) -> JellyStats {
        JellyStats(persists: false, seedWaddle: waddle, seedFocus: focus, dayKey: day)
    }

    // MARK: gain

    func testTenSessionsGiveStrictlyDecreasingGains() {
        let s = stats()
        var gains: [Float] = []
        for _ in 0..<10 { gains.append(s.finishPractice(accuracy: 0.9, steadiness: 0.5).waddle) }
        for i in 1..<gains.count { XCTAssertLessThan(gains[i], gains[i - 1], "session \(i + 1): \(gains)") }
        XCTAssertGreaterThan(gains.last!, 0)
        // 0.2 -> 0.4 is quick, 0.8 -> 0.9 is slow
        let q = stats(waddle: 0.2); var n = 0
        while q.waddle < 0.4, n < 50 { q.finishPractice(accuracy: 0.9, steadiness: 0); n += 1 }
        XCTAssertLessThanOrEqual(n, 4, "0.2 -> 0.4 in a few sessions")
        let sl = stats(waddle: 0.8); var m = 0
        while sl.waddle < 0.9, m < 200 { sl.finishPractice(accuracy: 0.9, steadiness: 0, ); m += 1 }
        XCTAssertGreaterThanOrEqual(m, 3 * n, "0.8 -> 0.9 is much slower (\(m) vs \(n))")
    }

    func testAccuracyZeroGivesNoGain() {
        let s = stats(waddle: 0.3, focus: 0.3)
        let g = s.finishPractice(accuracy: 0, steadiness: 0)
        XCTAssertEqual(g.waddle, 0, accuracy: 1e-6); XCTAssertEqual(g.focus, 0, accuracy: 1e-6)
        XCTAssertEqual(s.waddle, 0.3, accuracy: 1e-6)
        XCTAssertEqual(s.sessionsToday, 1, "the session still used a Pep")
    }

    func testStatsNeverPassOne() {
        let s = stats(waddle: 0.99, focus: 0.99)
        for _ in 0..<30 { s.finishPractice(accuracy: 1, steadiness: 1) }
        XCTAssertLessThanOrEqual(s.waddle, 1); XCTAssertLessThanOrEqual(s.focus, 1)
    }

    // MARK: pep

    func testPepResetsOnCalendarDayChangeNotElapsedHours() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var date = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 0, minute: 10))!
        let clock = DayClock(defaults: UserDefaults(suiteName: "TrainPep.\(UUID().uuidString)")!, now: { date }, calendar: cal)
        let s = JellyStats(persists: false, seedWaddle: 0.2, dayKey: { clock.dayKey })
        XCTAssertEqual(s.pepLeft, 3)
        var gains: [Float] = []
        for _ in 0..<3 { gains.append(s.finishPractice(accuracy: 1, steadiness: 0).waddle) }
        XCTAssertEqual(s.pepLeft, 0)
        let fourth = s.finishPractice(accuracy: 1, steadiness: 0).waddle
        XCTAssertLessThan(fourth, gains[2] * 0.4, "after the day's Pep a session still helps, but much less")
        XCTAssertGreaterThan(fourth, 0)
        date = date.addingTimeInterval(23 * 3600)                // 23:10 the same day: 23 hours later, no refill
        XCTAssertEqual(s.pepLeft, 0, "23 h later but the same day")
        date = date.addingTimeInterval(2 * 3600)                 // 01:10 next day: only 2 h later, a new day
        XCTAssertEqual(s.pepLeft, 3, "past midnight Pep is full again")
        XCTAssertEqual(s.sessionsToday, 0)
        // and a full 24 h inside no midnight is impossible, but 30 h later (same pep rules) is a new day too
        _ = s.finishPractice(accuracy: 1, steadiness: 0)
        XCTAssertEqual(s.pepLeft, 2)
    }

    func testPepAndDancesPersist() {
        let d = UserDefaults(suiteName: "TrainPersist.\(UUID().uuidString)")!
        let a = JellyStats(persists: true, defaults: d, key: "k", seedWaddle: 0.3, dayKey: { 7 })
        a.finishPractice(accuracy: 0.8, steadiness: 0.4)
        a.learn(.sway, add: 0.3)
        let b = JellyStats(persists: true, defaults: d, key: "k", seedWaddle: 0.9, dayKey: { 7 })
        XCTAssertEqual(b.waddle, a.waddle, accuracy: 1e-5)
        XCTAssertEqual(b.sessionsToday, 1)
        XCTAssertEqual(b.proficiency(.sway), 0.3, accuracy: 1e-5)
        XCTAssertEqual(b.knownDances, [.sway])
        let c = JellyStats(persists: true, defaults: d, key: "k", seedWaddle: 0.9, dayKey: { 8 })
        XCTAssertEqual(c.sessionsToday, 0, "another day")
        XCTAssertEqual(stats().proficiency(.sway), 0)
        a.learn(.sway, add: 5); XCTAssertEqual(a.proficiency(.sway), 1)
    }

    // MARK: beat grid

    func testBeatGridIs115BpmFromPoint279() {
        XCTAssertEqual(TrainingTuning.bpm, 115.0)
        XCTAssertEqual(TrainingTuning.firstBeat, 0.279, accuracy: 1e-9)
        XCTAssertEqual(BeatGrid.time(ofBeat: 0), 0.279, accuracy: 1e-9)
        XCTAssertEqual(BeatGrid.time(ofBeat: 115), 0.279 + 60, accuracy: 1e-9)       // 115 beats = one minute
        XCTAssertEqual(TrainingTuning.period, 60.0 / 115.0, accuracy: 1e-12)
        XCTAssertEqual(BeatGrid.beat(atOrAfter: 0.279), 0)
        XCTAssertEqual(BeatGrid.beat(atOrAfter: 0.28), 1)
        XCTAssertEqual(BeatGrid.phase(of: 0.279 + 0.5 * TrainingTuning.period), 0.5, accuracy: 1e-9)
        // the loop is 20 bars = 80 beats (within a millisecond), and starts on a beat
        let loop = TrainingTuning.loopEnd - TrainingTuning.loopStart
        XCTAssertEqual(loop, 80 * TrainingTuning.period, accuracy: 0.002)
        let p = BeatGrid.phase(of: TrainingTuning.loopStart)
        XCTAssertTrue(p < 0.01 || p > 0.99, "loop start on a beat, phase \(p)")
        // the drill's prompts sit on the grid
        let d = DrillSim(seed: 3, songTime: TrainingTuning.loopStart)
        for p in d.prompts { XCTAssertEqual(BeatGrid.phase(of: p.time) * TrainingTuning.period, 0, accuracy: 1e-6) }
        XCTAssertEqual(d.total, TrainingTuning.laps * TrainingTuning.promptsPerLap)
        XCTAssertEqual(Set(d.prompts.map(\.lap)), [1, 2, 3])
        for i in 1..<d.prompts.count where d.prompts[i].lap == d.prompts[i - 1].lap { XCTAssertNotEqual(d.prompts[i].foot, d.prompts[i - 1].foot, "feet alternate") }
    }

    // MARK: judging

    func testWindowsAndLatencyOffset() {
        func fresh() -> DrillSim { DrillSim(seed: 1, songTime: 100) }
        let off = TrainingTuning.latencyOffset
        var d = fresh()
        let p0 = d.prompts[0]
        d.tap(foot: p0.foot, at: p0.time + off)
        XCTAssertEqual(d.perfects, 1, "a tap on the beat (after the latency offset) is perfect")
        d = fresh()
        d.tap(foot: d.prompts[0].foot, at: p0.time + off + 0.09)
        XCTAssertEqual(d.goods, 1)
        d = fresh()
        d.tap(foot: d.prompts[0].foot, at: p0.time + off - 0.15)
        XCTAssertEqual(d.misses, 1, "too early")
        d = fresh()
        d.tap(foot: 1 - d.prompts[0].foot, at: p0.time + off)
        XCTAssertEqual(d.misses, 1, "wrong foot")
        d = fresh()
        d.tap(foot: d.prompts[0].foot, at: p0.time + off - 0.5)
        XCTAssertEqual(d.strays, 1); XCTAssertEqual(d.judged, 0, "a stray tap far from any beat")
        d = fresh()
        d.tick(songTime: p0.time + off + 0.2)
        XCTAssertEqual(d.misses, 1, "no tap: missed")
        XCTAssertTrue(d.takeEvents().contains(.miss(index: 0, foot: p0.foot, late: true)))
    }

    func testPerfectPlayAndNoPlay() {
        var d = DrillSim(seed: 9, songTime: 0)
        for p in d.prompts { d.tap(foot: p.foot, at: p.time + TrainingTuning.latencyOffset) }
        XCTAssertTrue(d.finished); XCTAssertEqual(d.perfects, d.total); XCTAssertEqual(d.accuracy, 1, accuracy: 1e-6)
        XCTAssertEqual(d.bestStreak, d.total)
        let ev = d.takeEvents()
        XCTAssertEqual(ev.filter { if case .lapEnd = $0 { return true }; return false }.count, 3)
        var n = DrillSim(seed: 9, songTime: 0)
        n.tick(songTime: 1000)
        XCTAssertTrue(n.finished); XCTAssertEqual(n.accuracy, 0); XCTAssertEqual(n.misses, n.total)
        // mashing both feet at 10 Hz is not a good strategy
        var m = DrillSim(seed: 9, songTime: 0)
        var t = 0.0, foot = 0
        while t < m.endTime + 1 { m.tap(foot: foot, at: t); foot = 1 - foot; t += 0.1 }
        XCTAssertLessThan(m.accuracy, 0.3, "mashing scores \(m.accuracy)")
    }

    // MARK: racing: trained beats untrained

    private func headlessRace(waddle: Float, focus: Float, seed: UInt64) -> (time: Float, trips: Int) {
        var sim = RaceSim(player: RacerStats(waddle: waddle, focus: focus), playerName: "P", rivals: [], seed: seed)
        let dt: Float = 1 / 60
        var tapT: Float = 0, foot = 0
        var guardN = 0
        while sim.phase != .results, guardN < 60 * 60 {
            tapT += dt
            if tapT >= 1 / 8 { tapT -= 1 / 8; sim.playerTap(foot: foot); foot = 1 - foot }        // the same fingers every time: 8 taps a second
            sim.tick(dt: dt)
            _ = sim.takeEvents()
            guardN += 1
        }
        return (sim.racers[0].finishTime ?? 99, sim.racers[0].tap.trips)
    }

    func testTrainedStatsRaceFasterAndTripLess() {
        let starter = stats(waddle: 0.40, focus: 0.40)
        let trained = stats(waddle: 0.40, focus: 0.40)
        var day = 20261019
        let tr = JellyStats(persists: false, seedWaddle: 0.40, seedFocus: 0.40, dayKey: { day })
        for i in 0..<14 { if i % 3 == 0 { day += 1 }; tr.finishPractice(accuracy: 0.9, steadiness: 0.5) }
        _ = trained
        XCTAssertGreaterThan(tr.waddle, 0.75); XCTAssertGreaterThan(tr.focus, starter.focus + 0.1)
        var tripsU = 0, tripsT = 0, faster = 0
        let seeds = 1...40
        for seed in seeds {
            let u = headlessRace(waddle: starter.waddle, focus: starter.focus, seed: UInt64(seed))
            let t = headlessRace(waddle: tr.waddle, focus: tr.focus, seed: UInt64(seed))
            tripsU += u.trips; tripsT += t.trips
            if t.time < u.time { faster += 1 }
        }
        XCTAssertEqual(faster, seeds.count, "the trained Jelly wins the same-taps race on every seed")
        XCTAssertGreaterThan(tripsU, tripsT * 3, "untrained trips \(tripsU) vs trained \(tripsT) over 40 races")
        let perRace = Double(tripsU) / 40
        XCTAssertGreaterThan(perRace, 0.5, "a starter visibly trips (\(perRace) a race)")
        XCTAssertLessThan(perRace, 3.5)
        XCTAssertEqual(RaceTuning.tripChance(waddle: 1, focus: 1), 0)
        XCTAssertGreaterThan(RaceTuning.tripChance(waddle: 0.4, focus: 0.4), RaceTuning.tripChance(waddle: 0.6, focus: 0.4))
        XCTAssertGreaterThan(RaceTuning.tripChance(waddle: 0.4, focus: 0.4), RaceTuning.tripChance(waddle: 0.4, focus: 0.7))
    }

    // MARK: the drill flow

    func testDrillFlowFromFadeToResultsWithGain() {
        let flow = RaceFlow()
        let st = stats(waddle: 0.3, focus: 0.3)
        flow.stats = st
        flow.cue = { _ in }; flow.drillCue = { _ in }
        flow.drillAuto = true
        var resets = 0, swaps: [RaceFlow.Dest] = []
        flow.onLapReset = { resets += 1 }
        flow.onSwap = { swaps.append($0) }
        var cues: [DrillCue] = []
        flow.drillCue = { cues.append($0) }
        flow.beginDrill(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.3, focus: 0.3), seed: 5)
        XCTAssertTrue(flow.isDrill); XCTAssertTrue(flow.active)
        var events: [RaceEvent] = []
        var n = 0
        while flow.drillResult == nil, n < 60 * 150 {
            events += flow.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true })
            n += 1
        }
        XCTAssertNotNil(flow.drillResult, "the drill ends by itself")
        XCTAssertEqual(swaps.first, .track)
        XCTAssertEqual(resets, 2, "a dip between laps 1-2 and 2-3")
        let r = flow.drillResult!
        XCTAssertGreaterThan(r.waddleGain, 0); XCTAssertGreaterThan(st.waddle, 0.3)
        XCTAssertEqual(st.sessionsToday, 1); XCTAssertEqual(r.pepLeft, 2); XCTAssertFalse(r.pepSpent)
        XCTAssertGreaterThan(r.perfects, 20); XCTAssertGreaterThan(r.misses, 0)
        XCTAssertTrue(events.contains { if case .step = $0 { return true }; return false }, "hits make the body step")
        XCTAssertTrue(events.contains { if case .stumble = $0 { return true }; return false }, "misses trip him")
        XCTAssertEqual(flow.sim?.racers.count, 1, "alone on the track")
        XCTAssertEqual(flow.musicScene, .results)
        XCTAssertTrue(cues.contains(.statUp)); XCTAssertTrue(cues.contains(.jingle(win: true)))
        XCTAssertEqual(flow.earnedDropsForTest, 0, "no Drops from practice")
        flow.goHome()
        for _ in 0..<400 { _ = flow.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
        XCTAssertFalse(flow.active); XCTAssertEqual(swaps.last, .room)
    }

    func testQuittingGivesNothing() {
        let flow = RaceFlow()
        let st = stats(waddle: 0.3)
        flow.stats = st; flow.cue = { _ in }; flow.drillCue = { _ in }
        flow.beginDrill(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.3, focus: 0.3), seed: 5)
        for _ in 0..<(60 * 8) { _ = flow.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
        XCTAssertNotNil(flow.drill)
        flow.quitDrill()
        for _ in 0..<400 { _ = flow.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
        XCTAssertFalse(flow.active)
        XCTAssertEqual(st.waddle, 0.3, accuracy: 1e-6); XCTAssertEqual(st.sessionsToday, 0)
    }

    func testCourseTierDefaultsToPuddle() {
        XCTAssertEqual(RaceFlow().courseTier, .puddle)
        XCTAssertEqual(CourseTier.puddle.title, "Puddle")
    }
}

// MARK: - music

@MainActor
final class SceneMusicTests: XCTestCase {
    func testLoopPointsInsideTheFiles() {
        for t in SceneTrack.allCases {
            guard let len = SceneRender.fileLength(t, bundle: Bundle(for: AudioHub.self)) else { XCTFail("\(t) is not in the bundle"); continue }
            XCTAssertGreaterThan(t.loopStartFrame, SceneRender.crossfadeFrames, "\(t)")
            XCTAssertLessThan(t.loopStartFrame, t.loopEndFrame, "\(t)")
            XCTAssertLessThanOrEqual(t.loopEndFrame, len, "\(t): loop end \(t.loopEndFrame) past the file's \(len) frames")
        }
        for j in [Jingle.win, .lose] {
            XCTAssertNotNil(Bundle(for: AudioHub.self).url(forResource: j.rawValue, withExtension: "m4a"))
        }
        XCTAssertEqual(SceneTrack.training.loopStartFrame, 587_500); XCTAssertEqual(SceneTrack.circuitRace.loopEndFrame, 3_732_037)
    }

    func testRenderedLoopIsSeamless() throws {
        let b = Bundle(for: AudioHub.self)
        let t = SceneTrack.training
        let r = try XCTUnwrap(SceneRender.render(t, bundle: b))
        XCTAssertEqual(Int(r.loop.frameLength), t.loopEndFrame - t.loopStartFrame)
        XCTAssertNil(r.intro, "training starts at its loop")
        let d = try XCTUnwrap(r.loop.floatChannelData)
        let n = Int(r.loop.frameLength)
        // the step across the seam (last frame -> first frame) is no bigger than a normal step in the music
        var maxStep: Float = 0
        for i in stride(from: 1000, to: 200_000, by: 7) { maxStep = max(maxStep, abs(d[0][i] - d[0][i - 1])) }
        let seam = abs(d[0][0] - d[0][n - 1])
        XCTAssertLessThan(seam, max(maxStep * 2, 0.05), "seam step \(seam) vs typical max \(maxStep)")
        let race = try XCTUnwrap(SceneRender.render(.circuitRace, bundle: b))
        XCTAssertEqual(Int(race.intro?.frameLength ?? 0), SceneTrack.circuitRace.loopStartFrame, "the race plays its intro first")
    }

    private func run(_ d: inout MusicDirector, _ input: MusicInput, seconds: Double = 1) -> [MusicEvent] {
        var out: [MusicEvent] = []
        var t = 0.0
        while t < seconds { out += d.update(dt: 0.25, input: input); t += 0.25 }
        return out
    }

    func testDirectorSwitchesTracksForRaceFinalShopTown() {
        var d = MusicDirector(length: { _ in 600 }, rand: { 0.5 })
        _ = run(&d, MusicInput(phase: .day), seconds: 6)
        var ev = run(&d, MusicInput(phase: .day, scene: .race))
        XCTAssertTrue(ev.contains(.sceneOn(.circuitRace, fade: MusicDirector.sceneFade)))
        XCTAssertTrue(ev.contains(.fadeOutMain(fade: MusicDirector.sceneFade)), "the room music makes way")
        ev = run(&d, MusicInput(phase: .day, scene: .raceFinal))
        XCTAssertTrue(ev.contains(.sceneOn(.circuitFinal, fade: 0.8)), "the final stretch kicks in")
        ev = run(&d, MusicInput(phase: .day, scene: .results))
        XCTAssertTrue(ev.contains(.sceneOff(fade: 0.5)))
        XCTAssertFalse(ev.contains { if case .playTrack = $0 { return true }; return false }, "no room music over the jingle")
        ev = run(&d, MusicInput(phase: .day, scene: .none))
        XCTAssertTrue(ev.contains { if case .playTrack = $0 { return true }; return false }, "back in the room the playlist returns")
        ev = run(&d, MusicInput(phase: .day, scene: .shop))
        XCTAssertTrue(ev.contains(.sceneOn(.shop, fade: MusicDirector.sceneFade)))
        ev = run(&d, MusicInput(phase: .day, scene: .town))
        XCTAssertTrue(ev.contains(.sceneOn(.town, fade: 0.8)))
        ev = run(&d, MusicInput(phase: .day, scene: .training))
        XCTAssertTrue(ev.contains(.sceneOn(.training, fade: 0.8)))
    }

    func testRaceDoesNotTurnOnThePlayLayerAndLeavesItOff() {
        var d = MusicDirector(length: { _ in 600 }, rand: { 0.5 })
        _ = run(&d, MusicInput(phase: .day), seconds: 6)
        _ = run(&d, MusicInput(phase: .day, playing: true), seconds: 2)
        XCTAssertTrue(d.layerOn)
        let ev = run(&d, MusicInput(phase: .day, playing: true, scene: .race))
        XCTAssertTrue(ev.contains(.layerOff(fade: MusicDirector.sceneFade)))
        XCTAssertFalse(d.layerOn)
        let ev2 = run(&d, MusicInput(phase: .day, playing: true, scene: .race), seconds: 30)
        XCTAssertFalse(ev2.contains(.layerOn(fade: 1)))
    }

    func testFlowPicksTheSceneByPhase() {
        let f = RaceFlow()
        XCTAssertEqual(f.musicScene, .none)
        XCTAssertEqual(MusicScene.race.track, .circuitRace); XCTAssertEqual(MusicScene.raceFinal.track, .circuitFinal)
        XCTAssertEqual(MusicScene.training.track, .training); XCTAssertNil(MusicScene.results.track)
    }
}
