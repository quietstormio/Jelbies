//
//  RaceTests.swift
//  Jelly Circuit "Waddle Sprint" v1: the tap rules, the stat -> speed mapping, rivals, placings and Drops, stat growth, the race state machine,
//  and (on a real body) that the tap-stepped gait keeps the feet attached and the arms stubby at the slowest, trained and fastest cadence.
//

import XCTest
import simd
@testable import BobV1

// MARK: - tap rules

final class RaceTapRuleTests: XCTestCase {
    func testAlternatingTapsEachCommitOneStep() {
        var m = RaceTapModel()
        var feet: [Int] = []
        for k in 0..<6 {
            XCTAssertEqual(m.tap(k % 2), .queued, "tap \(k) alternates")
            feet.append(m.takeStep()!)
        }
        XCTAssertEqual(feet, [0, 1, 0, 1, 0, 1], "the steps alternate with the taps")
        XCTAssertEqual(m.steps, 6); XCTAssertEqual(m.stumbles, 0)
        // the first tap may be either foot
        var r = RaceTapModel()
        XCTAssertEqual(r.tap(1), .queued); XCTAssertEqual(r.takeStep(), 1)
        XCTAssertEqual(r.nextFoot, 0)
    }

    func testTheSameFootTwiceIsAStumble() {
        var m = RaceTapModel()
        XCTAssertEqual(m.tap(0), .queued)
        XCTAssertEqual(m.tap(0), .stumble, "L, L")
        XCTAssertEqual(m.stumbles, 1)
        XCTAssertNil(m.takeStep(), "the buffered step is lost")
        XCTAssertTrue(m.stumbling)
        XCTAssertEqual(m.stumbleLeft, RaceTuning.stumbleTime, accuracy: 1e-6)
        // taps during the stumble are ignored without a new penalty
        XCTAssertEqual(m.tap(1), .ignored); XCTAssertEqual(m.tap(1), .ignored)
        XCTAssertEqual(m.stumbles, 1)
        m.tick(dt: RaceTuning.stumbleTime + 0.01)
        XCTAssertFalse(m.stumbling)
        XCTAssertEqual(m.tap(0), .queued, "after the stumble the finger sequence carries on (R, then L)")
        // a stumble after steps: the foot that stepped last stays the reference for the next step
        var n = RaceTapModel()
        _ = n.tap(0); _ = n.takeStep()
        _ = n.tap(1); _ = n.takeStep()
        XCTAssertEqual(n.tap(1), .stumble)
        n.tick(dt: 1)
        XCTAssertEqual(n.tap(0), .queued); XCTAssertEqual(n.takeStep(), 0, "the next step is the other foot than the last step (R stepped last)")
    }

    func testTapsAreBufferedAtMostOneAhead() {
        var m = RaceTapModel()
        XCTAssertEqual(m.tap(0), .queued)
        XCTAssertEqual(m.tap(1), .ignored, "a second alternating tap before the step is taken is dropped")
        XCTAssertEqual(m.tap(0), .ignored)
        XCTAssertEqual(m.stumbles, 0, "alternating fast is never a fault")
        XCTAssertEqual(m.takeStep(), 0)
        XCTAssertNil(m.takeStep(), "only one step was buffered")
        XCTAssertEqual(m.steps, 1)
        XCTAssertEqual(m.ignored, 2)
    }

    /// Tapping faster than the trained step rate does not help: the distance after N seconds is the same at 8 taps/s as at the trained rate.
    func testTappingFasterThanTheTrainedRateDoesNotHelp() {
        func distance(tapsPerSecond: Float) -> Float {
            var sim = RaceSim(player: RacerStats(waddle: 0.5, focus: 1), playerName: "P", rivals: [], seed: 1)
            var tapT: Float = 0, foot = 0
            let dt: Float = 1 / 60
            for _ in 0..<(60 * 8) {
                if sim.phase == .running || sim.phase == .finishing {
                    tapT += dt
                    while tapT >= 1 / tapsPerSecond { tapT -= 1 / tapsPerSecond; sim.playerTap(foot: foot); foot = 1 - foot }
                }
                sim.tick(dt: dt)
                if sim.phase == .results { break }
            }
            return sim.racers[0].dist
        }
        let trained = RaceTuning.maxRate(waddle: 0.5)
        let atRate = distance(tapsPerSecond: trained * 1.02), fast = distance(tapsPerSecond: 9)
        XCTAssertEqual(fast, atRate, accuracy: 0.45, "9 taps/s gets nowhere further than the trained rate")
        XCTAssertGreaterThan(fast, 4)
        XCTAssertLessThan(distance(tapsPerSecond: trained * 0.5), atRate * 0.7, "tapping slower is slower")
    }

    func testStallingStopsHim() {
        var sim = RaceSim(player: RacerStats(waddle: 0.5, focus: 1), playerName: "P", rivals: [], seed: 1)
        let dt: Float = 1 / 60
        var foot = 0, tapT: Float = 0
        for _ in 0..<(60 * 5) {                                                     // countdown, then 2.5 s of tapping
            if sim.phase == .running, sim.clock < 2.5 { tapT += dt; if tapT >= 0.2 { tapT = 0; sim.playerTap(foot: foot); foot = 1 - foot } }
            sim.tick(dt: dt)
        }
        for _ in 0..<40 { sim.tick(dt: dt) }                                        // the step that was already buffered
        let before = sim.racers[0].dist
        XCTAssertGreaterThan(before, 1.5)
        for _ in 0..<60 { sim.tick(dt: dt) }                                        // a second of nothing
        XCTAssertEqual(sim.racers[0].dist, before, accuracy: 0.0001, "no tap, no step: he stands")
        XCTAssertTrue(sim.racers[0].stalled, "the stall hint is up")
        sim.playerTap(foot: foot)
        for _ in 0..<30 { sim.tick(dt: dt) }
        XCTAssertGreaterThan(sim.racers[0].dist, before, "one tap, one step")
        XCTAssertFalse(sim.racers[0].stalled)
    }

    func testAStumbleCostsTime() {
        func finish(stumbleAt: Float?) -> Float {
            var sim = RaceSim(player: RacerStats(waddle: 1, focus: 1), playerName: "P", rivals: [], seed: 2)          // (fully trained: no random trips muddy the comparison)
            var tapT: Float = 0, foot = 0, done = false
            let dt: Float = 1 / 60
            for _ in 0..<(60 * 40) {
                if sim.phase == .running || sim.phase == .finishing {
                    tapT += dt
                    while tapT >= 1 / 5 { tapT -= 1 / 5; sim.playerTap(foot: foot); foot = 1 - foot }
                    if let s = stumbleAt, !done, sim.clock >= s { done = true; sim.playerTap(foot: 1 - foot); sim.playerTap(foot: 1 - foot) }   // the same foot twice
                }
                sim.tick(dt: dt)
                if sim.phase == .results { break }
            }
            return sim.racers[0].finishTime ?? 99
        }
        let clean = finish(stumbleAt: nil), tripped = finish(stumbleAt: 4)
        XCTAssertGreaterThan(tripped - clean, RaceTuning.stumbleTime * 0.8, "a stumble loses at least most of its stumble time (\(clean) vs \(tripped))")
        XCTAssertLessThan(tripped - clean, RaceTuning.stumbleTime + 0.6)
    }
}

// MARK: - stats, rivals, placings

@MainActor
final class RaceModelTests: XCTestCase {
    func testStatToSpeedMapping() {
        XCTAssertEqual(RaceTuning.stride(waddle: 0), 0.27, accuracy: 1e-6)
        XCTAssertEqual(RaceTuning.stride(waddle: 1), 0.32, accuracy: 1e-6)
        XCTAssertEqual(RaceTuning.maxRate(waddle: 0), 3.0, accuracy: 1e-6)
        XCTAssertEqual(RaceTuning.maxRate(waddle: 1), 4.2, accuracy: 1e-6)
        var prev: Float = 0
        for k in 0...20 {
            let w = Float(k) / 20, v = RaceTuning.speed(waddle: w)
            XCTAssertEqual(v, RaceTuning.stride(waddle: w) * RaceTuning.maxRate(waddle: w), accuracy: 1e-6, "speed = stride x rate")
            XCTAssertGreaterThan(v, prev); prev = v
        }
        XCTAssertEqual(RaceTuning.stride(waddle: -3), RaceTuning.stride(waddle: 0)); XCTAssertEqual(RaceTuning.maxRate(waddle: 9), RaceTuning.maxRate(waddle: 1))
        // stays inside the gait envelope the feet and arms were tuned for (the run: stride 0.366 at 4.2 steps/s)
        XCTAssertLessThanOrEqual(RaceTuning.stride(waddle: 1), 0.32 + 1e-6, "the longest stride that keeps the feet attached at every step rate")
        XCTAssertLessThanOrEqual(RaceTuning.maxRate(waddle: 1), 4.2 + 1e-6)
        // an average waddle finishes the track in about 12 s
        let t = RaceTuning.length / RaceTuning.speed(waddle: 0.5)
        XCTAssertTrue((10.0...14.0).contains(t), "an average Jelly's sprint is \(t) s")
    }

    func testRaceSpeedDoesNotUseTheRoamingPath() {
        let b = BlobBrain()
        let base = (b.stride, b.stepRate, b.runStrideMul, BlobBrain.walkBoost)
        // the race module has its own numbers: changing the roaming ones moves nothing in the stat mapping
        b.stride = 9; b.stepRate = 9; b.runW = 1
        XCTAssertEqual(RaceTuning.stride(waddle: 0.5), 0.295, accuracy: 1e-6)
        XCTAssertEqual(RaceTuning.maxRate(waddle: 0.5), 3.6, accuracy: 1e-6)
        b.stride = base.0; b.stepRate = base.1; b.runW = 0
        XCTAssertEqual(b.runStrideMul, base.2 * 1, accuracy: 1e-6)
    }

    func testStatsSeedPersistAndGrow() {
        let d = UserDefaults(suiteName: "RaceTests.stats.\(UUID().uuidString)")!
        let s = JellyStats(persists: true, defaults: d, key: "k", seedWaddle: StatTuning.seedWaddle(careLevels: [1, 1, 1]))
        XCTAssertEqual(s.waddle, StatTuning.seedBase + StatTuning.seedCare, accuracy: 1e-6, "all needs full seeds the top of the range")
        XCTAssertEqual(StatTuning.seedWaddle(careLevels: [0, 0, 0]), StatTuning.seedBase, accuracy: 1e-6)
        XCTAssertEqual(s.focus, 0.5, accuracy: 1e-6, "focus starts in the middle")
        s.set(waddle: 0.5)
        let g1 = s.afterRace(place: 1), g2 = s.afterRace(place: 2), g3 = s.afterRace(place: 3)
        XCTAssertGreaterThan(g1, g2); XCTAssertGreaterThan(g2, g3); XCTAssertGreaterThan(g3, 0, "every race helps a little, a win the most")
        XCTAssertEqual(s.waddle, 0.5 + g1 + g2 + g3, accuracy: 1e-5)
        XCTAssertEqual(s.races, 3); XCTAssertEqual(s.wins, 1)
        // persisted under the key; a second instance reads it back and does not re-seed
        let t = JellyStats(persists: true, defaults: d, key: "k", seedWaddle: 0.9)
        XCTAssertEqual(t.waddle, s.waddle, accuracy: 1e-6); XCTAssertEqual(t.races, 3)
        // capped at 1
        t.set(waddle: 0.995); t.afterRace(place: 1)
        XCTAssertEqual(t.waddle, 1)
        // other keys are separate (Jelly 1 has its own)
        XCTAssertNotEqual(JellyKeys.stats(0), JellyKeys.stats(1))
        // a Jelly's profile carries stats seeded from his care
        let p = JellyProfile(id: 1, name: "Pip", persists: false)
        XCTAssertEqual(p.stats.focus, 0.5)
        XCTAssertTrue((StatTuning.seedBase...(StatTuning.seedBase + StatTuning.seedCare)).contains(p.stats.waddle))
    }

    func testRivalsAreDeterministicPerSeed() {
        let src = LocalRivalSource()
        let me = RacerStats(waddle: 0.5, focus: 0.5), tint = JellyRoster.tint(0)
        let a = src.rivals(count: 2, player: me, playerTint: tint, seed: 42), b = src.rivals(count: 2, player: me, playerTint: tint, seed: 42)
        XCTAssertEqual(a, b, "the same seed, the same rivals")
        XCTAssertEqual(a.count, 2)
        var different = false
        for s in UInt64(1)...12 where src.rivals(count: 2, player: me, playerTint: tint, seed: s) != a { different = true }
        XCTAssertTrue(different, "other seeds give other rivals")
        for seed in UInt64(1)...30 {
            let rs = src.rivals(count: 2, player: me, playerTint: tint, seed: seed)
            XCTAssertNotEqual(rs[0].name, rs[1].name)
            XCTAssertNotEqual(LocalRivalSource.hue(of: rs[0].tint), LocalRivalSource.hue(of: rs[1].tint))
            for r in rs {
                XCTAssertFalse(r.name.isEmpty)
                XCTAssertLessThanOrEqual(abs(r.stats.waddle - me.waddle), LocalRivalSource.waddleSpread + 1e-5, "stats near the player's")
                XCTAssertLessThanOrEqual(abs(r.stats.focus - me.focus), LocalRivalSource.focusSpread + 1e-5)
                let dh = abs(LocalRivalSource.hue(of: r.tint) - LocalRivalSource.hue(of: tint)); XCTAssertGreaterThan(min(dh, 1 - dh), 0.08, "a pastel unlike the player's (seed \(seed))")
                XCTAssertGreaterThan(r.tint.min() , 0.5, "pastel: light")
            }
        }
        // every roster colour is avoided
        for id in 0..<3 {
            let rs = src.rivals(count: 2, player: me, playerTint: JellyRoster.tint(id), seed: 7)
            for r in rs { let dh = abs(LocalRivalSource.hue(of: r.tint) - LocalRivalSource.hue(of: JellyRoster.tint(id))); XCTAssertGreaterThan(min(dh, 1 - dh), 0.08) }
        }
        // the body palette made from a tint is a matte one (the same soft look as the roster)
        XCTAssertTrue(LocalRivalSource.palette(for: a[0].tint, name: a[0].name).matte)
    }

    private struct FixedRivals: RivalSource {
        var stats: RacerStats
        func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64) -> [Rival] {
            (0..<count).map { Rival(name: "R\($0)", tint: LocalRivalSource.hsv(Float($0) * 0.3 + 0.1, 0.3, 0.95), stats: stats) }
        }
    }

    /// Runs a flow with the player auto-tapping until the placings card is up; returns the flow.
    private func raceToResults(player: RacerStats, rivals: RacerStats, autoRate: Float = 6, seed: UInt64 = 5, wallet: DropsWallet? = nil, stats: JellyStats? = nil) -> RaceFlow {
        let f = RaceFlow()
        f.rivalSource = FixedRivals(stats: rivals)
        f.wallet = wallet; f.stats = stats
        f.cue = { _ in }
        f.autoRate = autoRate
        f.begin(playerID: 0, name: "Bob", player: player, playerTint: JellyRoster.tint(0), rivalCount: 2, seed: seed)
        for _ in 0..<(60 * 80) { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); if f.hasResults { break } }
        return f
    }

    func testPlacingsAndDropsPayout() {
        XCTAssertEqual(RaceTuning.drops(place: 1), 12); XCTAssertEqual(RaceTuning.drops(place: 2), 7); XCTAssertEqual(RaceTuning.drops(place: 3), 4)
        XCTAssertGreaterThan(RaceTuning.drops(place: 1), RaceTuning.drops(place: 2)); XCTAssertGreaterThan(RaceTuning.drops(place: 2), RaceTuning.drops(place: 3))
        // a quick Jelly against slow rivals wins; the Drops land in the wallet once
        let w = DropsWallet(persists: false)
        let win = raceToResults(player: RacerStats(waddle: 0.9, focus: 1), rivals: RacerStats(waddle: 0.15, focus: 1), wallet: w)
        let sim = win.sim!
        XCTAssertEqual(sim.phase, .results)
        XCTAssertEqual(sim.placings.map(\.place), [1, 2, 3])
        XCTAssertEqual(sim.placings.first?.isPlayer, true, "the quick one is first")
        XCTAssertEqual(sim.playerPlace, 1)
        XCTAssertEqual(w.count, 12, "1st pays 12 Drops")
        let times = sim.placings.compactMap(\.time)
        XCTAssertGreaterThanOrEqual(times.count, 1); XCTAssertEqual(times, times.sorted(), "finishers are in time order, ahead of the ones still running")
        XCTAssertNotNil(sim.placings.first?.time)
        XCTAssertGreaterThan(win.earned, 0)
        // a slow Jelly against quick rivals comes last: 3rd pays 4
        let w2 = DropsWallet(persists: false)
        let lose = raceToResults(player: RacerStats(waddle: 0.1, focus: 1), rivals: RacerStats(waddle: 0.95, focus: 1), wallet: w2)
        XCTAssertEqual(lose.sim?.playerPlace, 3)
        XCTAssertEqual(w2.count, 4)
        XCTAssertEqual(lose.sim?.placings.last?.isPlayer, true)
        // the sum of times: a faster Jelly is quicker
        XCTAssertLessThan(win.sim!.player.finishTime!, lose.sim!.player.finishTime!)
    }

    func testAJellyThatNeverMovesIsPlacedLastWithoutATime() {
        var sim = RaceSim(player: RacerStats(waddle: 0.5, focus: 1), playerName: "P", rivals: [Rival(name: "A", tint: .one, stats: RacerStats(waddle: 0.5, focus: 1))], seed: 3)
        for _ in 0..<(60 * 60) { sim.tick(dt: 1 / 60); if sim.phase == .results { break } }
        XCTAssertEqual(sim.phase, .results)
        XCTAssertEqual(sim.playerPlace, 2)
        XCTAssertNil(sim.placings.last?.time)
        XCTAssertEqual(sim.playerDrops, 7)
    }

    func testStatsGrowAfterARace() {
        let d = UserDefaults(suiteName: "RaceTests.growth.\(UUID().uuidString)")!
        let s = JellyStats(persists: true, defaults: d, key: "k", seedWaddle: 0.5)
        let f = raceToResults(player: RacerStats(waddle: 0.9, focus: 1), rivals: RacerStats(waddle: 0.15, focus: 1), stats: s)
        XCTAssertEqual(f.sim?.playerPlace, 1)
        XCTAssertEqual(s.waddle, 0.5 + StatTuning.waddleGain(place: 1), accuracy: 1e-5, "a win nudges waddle up the most")
        XCTAssertEqual(f.waddleGain, StatTuning.waddleGain(place: 1), accuracy: 1e-5)
        XCTAssertEqual(s.races, 1); XCTAssertEqual(s.wins, 1)
        // settled once: more ticks change nothing
        for _ in 0..<120 { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
        XCTAssertEqual(s.races, 1)
        let s2 = JellyStats(persists: false, seedWaddle: 0.5)
        _ = raceToResults(player: RacerStats(waddle: 0.1, focus: 1), rivals: RacerStats(waddle: 0.95, focus: 1), stats: s2)
        XCTAssertEqual(s2.waddle, 0.5 + StatTuning.waddleGain(place: 3), accuracy: 1e-5)
        XCTAssertLessThan(StatTuning.waddleGain(place: 3), StatTuning.waddleGain(place: 1))
    }

    func testRaceStateMachine() {
        let f = RaceFlow()
        f.rivalSource = FixedRivals(stats: RacerStats(waddle: 0.15, focus: 1))
        f.autoRate = 6
        f.autoReturnAfter = 0.5
        var cues: [RaceCue] = []
        f.cue = { cues.append($0) }
        var swaps: [(RaceFlow.Dest, Float)] = []
        var returned: [(Int, Bool)] = []
        f.onSwap = { d in swaps.append((d, f.wipe)) }
        f.onReturned = { id, won in returned.append((id, won)) }
        XCTAssertFalse(f.active)
        f.begin(playerID: 1, name: "Pip", player: RacerStats(waddle: 0.9, focus: 1), playerTint: JellyRoster.tint(1), rivalCount: 2, seed: 9)
        XCTAssertEqual(f.phase, .fade); XCTAssertTrue(f.active)
        f.begin(playerID: 2, name: "x", player: RacerStats(waddle: 0, focus: 0), playerTint: .zero, rivalCount: 2, seed: 1)
        XCTAssertEqual(f.playerID, 1, "a second begin is ignored while a trip runs"); XCTAssertEqual(f.started, 1)
        var seen: [RacePhase] = []
        var sawCountdown: [Int] = []
        var wentGo = false
        func step() -> [RaceEvent] {
            let ev = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true })
            if let p = f.sim?.phase, seen.last != p { seen.append(p) }
            for e in ev { if case .countdown(let n) = e { sawCountdown.append(n) }; if e == .go { wentGo = true } }
            return ev
        }
        var n = 0
        while !returned.isEmpty == false, n < 60 * 120 { _ = step(); n += 1 }
        XCTAssertEqual(swaps.map { $0.0 }, [.track, .room], "to the track, then home")
        XCTAssertTrue(swaps.allSatisfy { $0.1 == 1 }, "the worlds swap only under a fully opaque white")
        XCTAssertEqual(seen, [.countdown, .running, .finishing, .results])
        XCTAssertEqual(sawCountdown, [3, 2, 1], "3-2-1")
        XCTAssertTrue(wentGo, "then GO")
        XCTAssertEqual(cues.first, .countdownBeep)
        XCTAssertEqual(cues.filter { $0 == .countdownBeep }.count, 3)
        XCTAssertEqual(cues.filter { $0 == .go }.count, 1)
        XCTAssertEqual(cues.filter { $0 == .finish }.count, 1)
        XCTAssertEqual(cues.firstIndex(of: .go)!, 3, "beeps, then go")
        XCTAssertEqual(returned.count, 1)
        XCTAssertEqual(returned.first?.0, 1); XCTAssertEqual(returned.first?.1, true, "the quick one came home a winner")
        XCTAssertEqual(f.phase, .off); XCTAssertEqual(f.wipe, 0); XCTAssertEqual(f.cameraBlend, 0)
        XCTAssertNil(f.sim)
        // the countdown takes 3 beats and nobody moves before GO
        var sim = RaceSim(player: RacerStats(waddle: 0.5, focus: 0.5), playerName: "P", rivals: [], seed: 1)
        sim.playerTap(foot: 0)
        for _ in 0..<60 { sim.tick(dt: 1 / 60) }
        XCTAssertEqual(sim.phase, .countdown); XCTAssertEqual(sim.player.dist, 0); XCTAssertEqual(sim.countdownNumber, 3 - Int(1.0 / RaceTuning.countdownBeat))
        // the buttons are dead on the line, live once running
        let live = RaceFlow()
        live.rivalSource = FixedRivals(stats: RacerStats(waddle: 0.5, focus: 1)); live.cue = { _ in }
        live.begin(playerID: 0, name: "Bob", player: RacerStats(waddle: 0.5, focus: 1), playerTint: JellyRoster.tint(0), rivalCount: 2, seed: 2)
        XCTAssertEqual(live.tap(foot: 0), .ignored)
        while live.sim?.phase != .running { _ = live.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }) }
        XCTAssertTrue(live.buttonsLive)
        XCTAssertEqual(live.tap(foot: 0), .queued)
        XCTAssertEqual(live.tap(foot: 0), .stumble)
    }

    func testFocusPausesHappenToLowFocusRacersMore() {
        func pauses(focus: Float) -> Int {
            var total = 0
            for seed in UInt64(1)...12 {
                var sim = RaceSim(player: RacerStats(waddle: 0.5, focus: focus), playerName: "P", rivals: [Rival(name: "A", tint: .one, stats: RacerStats(waddle: 0.5, focus: focus))], seed: seed)
                var tapT: Float = 0, foot = 0
                for _ in 0..<(60 * 40) {
                    if sim.phase == .running { tapT += 1 / 60; if tapT >= 0.2 { tapT = 0; sim.playerTap(foot: foot); foot = 1 - foot } }
                    sim.tick(dt: 1 / 60)
                    for e in sim.takeEvents() { if case .pauseBegan = e { total += 1 } }
                    if sim.phase == .results { break }
                }
            }
            return total
        }
        XCTAssertEqual(RaceTuning.pauseHazard(focus: 1), 0)
        XCTAssertGreaterThan(RaceTuning.pauseHazard(focus: 0), RaceTuning.pauseHazard(focus: 0.5))
        let low = pauses(focus: 0.1), high = pauses(focus: 1)
        XCTAssertEqual(high, 0, "a fully focused Jelly never stops to look")
        XCTAssertGreaterThan(low, 3, "a distracted one does, for racers of either kind")
        // a pause costs time and no steps are taken during it
        var sim = RaceSim(player: RacerStats(waddle: 0.5, focus: 0), playerName: "P", rivals: [], seed: 4)
        var tapT: Float = 0, foot = 0
        var inPause = false, stepsInPause = 0
        for _ in 0..<(60 * 40) {
            if sim.phase == .running { tapT += 1 / 60; if tapT >= 0.2 { tapT = 0; sim.playerTap(foot: foot); foot = 1 - foot } }
            sim.tick(dt: 1 / 60)
            for e in sim.takeEvents() {
                if case .pauseBegan = e { inPause = true }
                if case .pauseEnded = e { inPause = false }
                if case .step = e, inPause { stepsInPause += 1 }
            }
            if sim.phase == .results { break }
        }
        XCTAssertEqual(stepsInPause, 0)
    }
}

// MARK: - the gait on a real body

/// A MotionRig with a RaceSim stepping his gait: taps at a given rate, the glue exactly as the game does it.
@MainActor
final class RaceBodyRig {
    let rig: MotionRig
    var sim: RaceSim
    let startZ: Float
    var tapsPerSecond: Float
    private var tapT: Float = 0, foot = 0
    var stumbleEvery: Float?
    private var sinceStumble: Float = 0
    /// Distances travelled, by time.
    private(set) var log: [(t: Float, z: Float)] = []

    /// The course he runs (nil: the straight from where the rig stands, the pre-course rig).
    let course: RaceCourse?
    let lane: Int

    /// With a `course` the rig is put on the start line of `lane` and runs that lane (the glue's progress, not pz - startZ).
    init(waddle: Float, tapsPerSecond: Float, focus: Float = 1, seed: UInt64 = 3, course: RaceCourse? = nil, lane: Int = RaceTuning.playerLane) {
        rig = MotionRig(game: true)
        rig.brain.amplitude = 1
        rig.brain.seed = 11
        self.course = course; self.lane = lane
        sim = course.map { RaceSim(player: RacerStats(waddle: waddle, focus: focus), playerName: "P", rivals: [], seed: seed, course: $0) }
            ?? RaceSim(player: RacerStats(waddle: waddle, focus: focus), playerName: "P", rivals: [], seed: seed)
        self.tapsPerSecond = tapsPerSecond
        if let c = course {
            let spot = c.lanePoint(lane, at: 0)
            if simd_distance(spot, SIMD2(rig.brain.px, rig.brain.pz)) > 1e-3 {          // (a course placed where the rig stands keeps the rig's state as it is)
                rig.sim.arenaRadius = .infinity
                rig.sim.teleport(toXZ: spot)
                for _ in 0..<60 { rig.sim.step() }
                rig.brain.currentPose(rig.sim)
            }
            rig.brain.startRace(sim: rig.sim, skinner: rig.skinner, heading: c.pose(at: 0).heading, laneX: spot.x, course: c, lane: lane)
        } else {
            rig.brain.startRace(sim: rig.sim, skinner: rig.skinner, heading: 0, laneX: rig.root.x)
        }
        startZ = rig.brain.pz
    }

    func tick() {
        let dt = rig.sim.stepDt
        if sim.phase == .running || sim.phase == .finishing {
            tapT += dt; sinceStumble += dt
            while tapsPerSecond > 0, tapT >= 1 / tapsPerSecond { tapT -= 1 / tapsPerSecond; sim.playerTap(foot: foot); foot = 1 - foot }
            if let e = stumbleEvery, sinceStumble >= e { sinceStumble = 0; sim.playerTap(foot: foot); sim.playerTap(foot: foot) }
        }
        if sim.phase != .countdown { sim.setMeasured(0, dist: course == nil ? rig.brain.pz - startZ : rig.brain.raceProgress) }
        sim.tick(dt: dt, bodyFree: { [rig] _ in rig.brain.raceStepFree }, bodyReady: { [rig] _ in rig.brain.raceBodyReady }, bodyBetween: { [rig] _ in rig.brain.raceBetweenSteps })
        for e in sim.takeEvents() { rig.brain.raceApply(e, sim: rig.sim) }
        rig.brain.raceKeepAlive()
        rig.tick()
        log.append((rig.t, rig.brain.pz - startZ))
    }

    func run(_ seconds: Float, each: (() -> Void)? = nil) { for _ in 0..<Int(seconds * 60) { tick(); each?() } }
}

@MainActor
final class RaceGaitTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// Steady ground speed (u/s) between t0 and t1 seconds after GO.
    private func speed(_ r: RaceBodyRig, from t0: Float, to t1: Float) -> Float {
        let a = r.log.first { $0.t >= t0 }!, b = r.log.last { $0.t <= t1 }!
        return (b.z - a.z) / (b.t - a.t)
    }

    func testTrainedCadenceWalksAtStrideTimesRate() {
        let w: Float = 0.5
        let r = RaceBodyRig(waddle: w, tapsPerSecond: RaceTuning.maxRate(waddle: w) * 1.05)
        Self.keep.append(r)
        r.run(2.9)                                         // the countdown
        let go = r.rig.t
        r.run(6)
        let v = speed(r, from: go + 2, to: go + 6)
        let want = RaceTuning.speed(waddle: w)
        MotionLog.write(String(format: "RACE gait: trained cadence waddle %.2f: %.3f u/s measured vs %.3f (stride %.3f x rate %.2f); roaming walk would be %.3f", w, v, want, RaceTuning.stride(waddle: w), RaceTuning.maxRate(waddle: w), 0.305 * BlobBrain.walkBoost * 3.75))
        XCTAssertEqual(v, want, accuracy: want * 0.05, "ground speed = stride x trained rate")
        XCTAssertNotEqual(r.rig.brain.activity, .idle)
        XCTAssertEqual(r.rig.brain.runW, 0); XCTAssertEqual(r.rig.brain.zoomW, 0, "the roaming run / zoomies blends are never involved")
        XCTAssertGreaterThan(r.rig.brain.race.steps, 20)
        // stalling: he stops within a step or two
        r.tapsPerSecond = 0
        r.run(1.5)
        let z0 = r.log.last!.z
        r.run(1.0)
        XCTAssertEqual(r.log.last!.z, z0, accuracy: 0.02, "no taps, no movement")
    }

    func testFasterWaddleIsFaster() {
        func v(_ w: Float) -> Float {
            let r = RaceBodyRig(waddle: w, tapsPerSecond: 9)
            Self.keep.append(r)
            r.run(2.9); let go = r.rig.t; r.run(5)
            return speed(r, from: go + 1.5, to: go + 5)
        }
        let slow = v(0.1), quick = v(0.9)
        MotionLog.write(String(format: "RACE gait: waddle 0.1 -> %.3f u/s, waddle 0.9 -> %.3f u/s", slow, quick))
        XCTAssertGreaterThan(quick, slow * 1.3)
    }

    /// Feet attached and arms stubby while tap-stepping at the slowest, trained and fastest cadence (with stumbles and a finish).
    func testFeetAttachedAndArmsStubbyAtEveryCadence() {
        struct Case { let name: String; let waddle: Float; let taps: Float; let stumbleEvery: Float? }
        let cases = [Case(name: "slow taps (1.4/s)", waddle: 0.5, taps: 1.4, stumbleEvery: nil),
                     Case(name: "trained cadence (waddle 0.5)", waddle: 0.5, taps: 3.8, stumbleEvery: nil),
                     Case(name: "max cadence (waddle 1, tapping 9/s)", waddle: 1, taps: 9, stumbleEvery: nil),
                     Case(name: "max cadence with stumbles", waddle: 1, taps: 7, stumbleEvery: 2.2),
                     Case(name: "min waddle", waddle: 0, taps: 6, stumbleEvery: nil)]
        for c in cases {
            let r = RaceBodyRig(waddle: c.waddle, tapsPerSecond: c.taps)
            Self.keep.append(r)
            r.stumbleEvery = c.stumbleEvery
            r.rig.renderSamples = false
            var feet = FeetAttachTests.FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity), frames = 0
            var arms = ArmCapTests.Stat()
            var armFrames = 0
            r.run(2.6 + (c.taps < 2 ? 12 : 21)) {
                if let f = FeetAttachTests.footFrame(r.rig) { FeetAttachTests.accumulate(&feet, f); frames += 1 }
                guard r.rig.brain.armG > 0.5 else { return }
                for si in 0..<2 {
                    let g = r.rig.brain.armLastGeom[si]
                    arms.add(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), rawB: SIMD3<Double>(r.rig.brain.armLastRawTip[si]), r1: Double(g.r1), r2: Double(g.r2))
                    armFrames += 1
                }
            }
            XCTAssertGreaterThan(frames, 100, "\(c.name): the foot beans were out")
            XCTAssertGreaterThan(armFrames, 100, "\(c.name): the walking arms were drawn")
            FeetAttachTests.check("race \(c.name)", feet, frames: frames)
            MotionLog.write(String(format: "RACE arms %@: exposed max %.3f H (cap %.3f H), min root depth %.3f u, %d frames", c.name, arms.capMax / ArmCapTests.H, ArmCap.maximum / ArmCapTests.H, arms.minDepth, armFrames))
            XCTAssertLessThanOrEqual(arms.capMax, ArmCap.maximum * 1.02, "\(c.name): arms within the wave's maximum")
            XCTAssertGreaterThanOrEqual(arms.minDepth, 0.015, "\(c.name): arm bases stay buried")
            if c.taps >= 3 { XCTAssertNotNil(r.sim.racers[0].finishTime, "\(c.name): he crossed the line (the finish coast was measured too)") }
        }
    }

    // MARK: curved courses (Race/RaceCourse.swift)

    /// Every lane of the Wave: a body tap-stepped round both hairpins stays on its lane (lateral error small), its heading tracks the lane's, its
    /// progress climbs monotonically (the glue's measured distance), and it crosses the line. The same for the Splash's S-bends and bumps.
    func testBodiesFollowTheirLanesRoundTheBends() {
        for (course, name) in [(RaceCourse.wave, "wave"), (RaceCourse.splash, "splash")] {
            for lane in 0..<3 {
                let r = RaceBodyRig(waddle: 0.7, tapsPerSecond: 6, focus: 1, seed: 5, course: course, lane: lane)
                Self.keep.append(r)
                r.rig.renderSamples = false
                var worstLat: Float = 0, worstHead: Float = 0, lastS: Float = -1, backsteps = 0, n = 0
                r.run(2.9 + course.length / 0.9 + 6) {
                    n += 1
                    guard n % 10 == 0, r.sim.phase == .running || r.sim.phase == .finishing, !r.sim.racers[0].finished else { return }
                    let s = r.rig.brain.raceProgress
                    let lat = abs(r.rig.brain.raceLateral)
                    worstLat = max(worstLat, lat)
                    if s > 1, s < course.length - 1 {
                        let want = course.pose(at: s).heading
                        worstHead = max(worstHead, abs(wrapAngle(r.rig.brain.yaw - want)))
                    }
                    if s < lastS - 0.3 { backsteps += 1 }
                    lastS = max(lastS, s)
                }
                MotionLog.write(String(format: "RACE course %@ lane %d: worst lateral %.3f u, worst heading error %.3f rad, steps %d, finished %@", name, lane, worstLat, worstHead, r.rig.brain.race.steps, r.sim.racers[0].finishTime.map { String(format: "%.1f s", $0) } ?? "no"))
                XCTAssertLessThan(worstLat, 0.7, "\(name) lane \(lane): stays on his lane (worst \(worstLat))")
                XCTAssertLessThan(worstHead, 0.6, "\(name) lane \(lane): faces along the lane (worst \(worstHead))")
                XCTAssertEqual(backsteps, 0, "\(name) lane \(lane): progress never jumps back")
                XCTAssertNotNil(r.sim.racers[0].finishTime, "\(name) lane \(lane): he crossed the line")
                XCTAssertGreaterThan(r.rig.brain.raceProgress, course.length - 0.5)
            }
        }
    }

    /// Feet attached and arms stubby round the Wave's hairpins: a fast trained Jelly with forced stumbles in the bends, and a starter who trips
    /// in the corners by the course rule (the trip pose on a curve).
    func testFeetAttachedAndArmsStubbyRoundTheHairpinsWithTrips() {
        struct Case { let name: String; let waddle: Float; let focus: Float; let taps: Float; let stumbleEvery: Float?; let lane: Int }
        let cases = [Case(name: "wave: max cadence with stumbles (lane 1)", waddle: 1, focus: 1, taps: 9, stumbleEvery: 2.2, lane: 1),
                     Case(name: "wave: starter trips in the corners (lane 0)", waddle: 0.4, focus: 0.3, taps: 5, stumbleEvery: nil, lane: 0),
                     Case(name: "wave: trained, outer lane (lane 2)", waddle: 0.85, focus: 0.75, taps: 7, stumbleEvery: nil, lane: 2)]
        for c in cases {
            let r = RaceBodyRig(waddle: c.waddle, tapsPerSecond: c.taps, focus: c.focus, seed: 9, course: .wave, lane: c.lane)
            Self.keep.append(r)
            r.stumbleEvery = c.stumbleEvery
            r.rig.renderSamples = false
            var feet = FeetAttachTests.FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity), frames = 0
            var arms = ArmCapTests.Stat()
            var armFrames = 0, cornerTrips = 0, inCornerFrames = 0
            r.run(2.9 + RaceCourse.wave.length / 0.8 + 4) {
                if let f = FeetAttachTests.footFrame(r.rig) { FeetAttachTests.accumulate(&feet, f); frames += 1 }
                if RaceCourse.wave.turnRadius(at: r.sim.racers[0].dist) != nil { inCornerFrames += 1 }
                cornerTrips = r.sim.racers[0].cornerTrips
                guard r.rig.brain.armG > 0.5 else { return }
                for si in 0..<2 {
                    let g = r.rig.brain.armLastGeom[si]
                    arms.add(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), rawB: SIMD3<Double>(r.rig.brain.armLastRawTip[si]), r1: Double(g.r1), r2: Double(g.r2))
                    armFrames += 1
                }
            }
            XCTAssertGreaterThan(frames, 100, "\(c.name): the foot beans were out")
            XCTAssertGreaterThan(armFrames, 100, "\(c.name): the walking arms were drawn")
            XCTAssertGreaterThan(inCornerFrames, 200, "\(c.name): he went round the bends")
            FeetAttachTests.check("race \(c.name)", feet, frames: frames)
            MotionLog.write(String(format: "RACE arms %@: exposed max %.3f H (cap %.3f H), min root depth %.3f u, %d frames, %d corner trips", c.name, arms.capMax / ArmCapTests.H, ArmCap.maximum / ArmCapTests.H, arms.minDepth, armFrames, cornerTrips))
            XCTAssertLessThanOrEqual(arms.capMax, ArmCap.maximum * 1.02, "\(c.name): arms within the wave's maximum")
            XCTAssertGreaterThanOrEqual(arms.minDepth, 0.015, "\(c.name): arm bases stay buried")
            XCTAssertNotNil(r.sim.racers[0].finishTime, "\(c.name): he crossed the line")
            if c.name.contains("starter") { XCTAssertGreaterThan(cornerTrips + r.sim.racers[0].tap.trips, 0, "\(c.name): the starter tripped") }
        }
    }

    /// A look-around pause (focus) hands the body to the look behaviour and back; steps resume.
    func testFocusPauseLooksAroundThenResumes() {
        let r = RaceBodyRig(waddle: 0.5, tapsPerSecond: 6, focus: 0)
        Self.keep.append(r)
        r.rig.renderSamples = false
        var sawLook = false, steps0 = 0
        r.run(2.9)
        for _ in 0..<(60 * 25) {
            r.tick()
            if r.rig.brain.idleState.kind == .look { sawLook = true; steps0 = r.rig.brain.race.steps }
            if sawLook, r.rig.brain.idleState.kind == nil, r.rig.brain.race.steps > steps0 + 2 { break }
        }
        XCTAssertTrue(sawLook, "a distracted racer stopped to look around")
        XCTAssertGreaterThan(r.rig.brain.race.steps, steps0 + 2, "and carried on afterwards")
        XCTAssertGreaterThan(r.rig.brain.race.looks, 0)
    }
}

// MARK: - the whole trip with three real bodies

/// GameCare + three Jellies ticked like the stage does: Race button -> fade -> track -> countdown -> race -> card -> home -> welcome home.
@MainActor
final class RaceTripTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    @MainActor
    final class Room {
        let care: GameCare
        let actors: [JellyActor]
        var t: Float = 0
        init() {
            let d = UserDefaults(suiteName: "RaceTrip.\(UUID().uuidString)")!
            let care = GameCare(jellyCount: 3, persistent: false, defaults: d)
            self.care = care
            let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
            let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
            let spots = JellyRoster.spawnSpots(count: 3)
            actors = (0..<3).map {
                let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
                a.profile = care.jelly($0); a.care = care
                a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius
                a.reset(drop: 0.35, shift: true)
                let b = BlobBrain.forGame()
                b.demo = nil; b.runMoveDemo = nil; b.autonomy = false
                b.steerID = $0
                care.wireWorld(b, isBob: $0 == 0)
                b.attach(renderMesh: rm, synchronous: true)
                a.brain = b
                b.currentPose(a.sim)
                return a
            }
            care.race.cue = { _ in }
            for _ in 0..<120 { step() }
        }
        func step() {
            let dt = actors[0].sim.stepDt
            for a in actors {
                a.brain?.tick(sim: a.sim, skinner: a.skinner, dt: dt, touched: false)
                a.skinner.jelly.tick(brain: a.brain!, sim: a.sim, dt: dt)
            }
            care.tick(brain: actors[0].brain!, renderer: nil, dt: dt, sim: actors[0].sim)
            care.tickOthers(actors, dt: dt)
            care.tickRace(actors, dt: dt)
            for a in actors { a.sim.step() }
            t += dt
        }
        func run(_ s: Float, until: (() -> Bool)? = nil) { for _ in 0..<Int(s * 60) { step(); if let u = until, u() { break } } }
    }

    func testTheWholeTripWithThreeBodies() {
        let room = Room()
        Self.keep.append(room)
        let care = room.care
        // a quick player and slow rivals, auto-tapped, back home by itself
        care.jelly(1)!.stats.set(waddle: 0.95)
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.2)
        care.race.autoRate = 8; care.race.autoReturnAfter = 0.5
        XCTAssertTrue(care.canRace(jelly: 1), "Race is offered for the picked Jelly")
        let homes = room.actors.map(\.floor)
        let waddleBefore = care.jelly(1)!.stats.waddle
        let dropsBefore = care.bath.wallet.count
        care.startRace(jelly: 1, seed: 11)
        XCTAssertTrue(care.race.active)
        XCTAssertFalse(care.canRace(jelly: 0), "one trip at a time")
        // fade out, swap under the white
        room.run(3) { care.race.trackVisible }
        XCTAssertTrue(care.race.trackVisible); XCTAssertEqual(care.race.cameraBlend, 1)
        XCTAssertEqual(care.race.swapLog.last?.wipe, 1, "swapped under a fully opaque white")
        XCTAssertEqual(care.raceBook.racers.first, 1, "the picked Jelly races in the player's place")
        XCTAssertEqual(Set(care.raceBook.racers), [0, 1, 2], "the two others' bodies are the rivals")
        XCTAssertNotNil(care.racePalette(for: 0)); XCTAssertNotNil(care.racePalette(for: 2)); XCTAssertNil(care.racePalette(for: 1), "the player keeps his own colours")
        for (k, aid) in care.raceBook.racers.enumerated() {
            let c = room.actors[aid].sim.centroid()
            XCTAssertEqual(c.x, RaceTuning.laneX(care.race.sim!.racers[k].lane), accuracy: 0.35, "racer \(k) on his lane")
            XCTAssertEqual(c.z, RaceTuning.startZ, accuracy: 0.4, "on the start line")
            XCTAssertTrue(room.actors[aid].brain!.race.active)
            XCTAssertEqual(room.actors[aid].sim.arenaRadius, .infinity, "no room fence out there")
        }
        // countdown, race
        room.run(8, until: { care.race.sim?.phase == .running })
        XCTAssertEqual(care.race.sim?.phase, .running)
        let z0 = care.raceBook.racers.map { room.actors[$0].brain!.pz }
        room.run(3)
        for (k, aid) in care.raceBook.racers.enumerated() { XCTAssertGreaterThan(room.actors[aid].brain!.pz, z0[k] + 1.0, "racer \(k) is running toward the camera") }
        room.run(40, until: { care.race.hasResults })
        XCTAssertTrue(care.race.hasResults)
        XCTAssertEqual(care.race.sim?.playerPlace, 1, "the quick player won")
        XCTAssertEqual(care.bath.wallet.count - dropsBefore, 12, "1st pays 12 Drops")
        XCTAssertGreaterThan(care.jelly(1)!.stats.waddle, waddleBefore, "the race made him a little quicker")
        XCTAssertEqual(care.jelly(1)!.stats.races, 1)
        // card, then home under the white
        room.run(10, until: { !care.race.active })
        XCTAssertFalse(care.race.active)
        XCTAssertEqual(care.race.cameraBlend, 0); XCTAssertEqual(care.race.wipe, 0)
        for a in room.actors { XCTAssertFalse(a.brain!.race.active); XCTAssertEqual(a.sim.arenaRadius, GameCamera.arenaRadius, accuracy: 1e-3) }
        XCTAssertNil(care.racePalette(for: 0))
        // the returner is at the front spot; the others are home and on their way over to greet him
        XCTAssertEqual(care.raceBook.returner, 1)
        let c = room.actors[1].sim.centroid()
        XCTAssertEqual(SIMD2(c.x, c.z).x, VoiceCoordinator.comeSpot.x, accuracy: 0.5)
        XCTAssertEqual(SIMD2(c.x, c.z).y, VoiceCoordinator.comeSpot.y, accuracy: 0.5)
        XCTAssertEqual(care.greetSpotNow(1), VoiceCoordinator.comeSpot)
        XCTAssertNotEqual(care.greetSpotNow(0), care.greetSpotNow(2), "the two greeters fan out behind him")
        let spots = [0: care.greetSpotNow(0), 2: care.greetSpotNow(2)]
        // ... and they arrive, hop, and (he won) everybody bounces together
        var hopped = Set<Int>()
        room.run(25, until: { care.raceBook.returner == nil }) ; _ = homes
        for _ in 0..<1 {}
        XCTAssertNil(care.raceBook.returner, "the welcome home is over")
        XCTAssertTrue(care.raceBook.celebrated || !care.raceBook.won)
        _ = hopped; hopped.removeAll()
        for aid in [0, 2] {
            let p = room.actors[aid].floor
            XCTAssertLessThan(simd_distance(p, spots[aid]!), 1.3, "Jelly \(aid) waddled over to the returner")
        }
        XCTAssertTrue(care.canRace(jelly: 1), "back to normal: Race is available again")
    }

    // MARK: room life is off for racers; sleep rolls up first

    /// The stage's rule, restated: what GameCare says about a trip (the stage turns sleep / antics / watching off whenever `raceBusy` is true).
    func testSleepWaitsAndGoodnightIsBlockedDuringARace() {
        let room = Room()
        Self.keep.append(room)
        let care = room.care
        for a in room.actors { a.brain!.sleepEnabled = true; a.brain!.anticsEnabled = true }
        // Jelly 1 goes to bed (the usual flow) ...
        room.actors[1].brain!.commandedGoodnight = true
        room.run(40, until: { room.actors[1].brain!.isNapping })
        XCTAssertTrue(room.actors[1].brain!.isNapping, "asleep on his back")
        // ... and the player picks him to race: he rolls up first, the trip starts when he is upright
        XCTAssertFalse(care.raceBusy)
        care.startRace(jelly: 1, seed: 3)
        XCTAssertTrue(care.raceBusy)
        XCTAssertFalse(care.race.active, "the trip has not started: he is still lying")
        XCTAssertFalse(care.canRace(jelly: 0), "a second Race is refused while the first waits")
        // a goodnight now does nothing (voice or brain)
        room.actors[0].brain!.commandedGoodnight = true
        room.run(0.5)
        XCTAssertFalse(room.actors[0].brain!.isSleeping, "no bedtime while a race is on its way")
        room.run(12, until: { care.race.active })
        XCTAssertTrue(care.race.active, "the race starts once he is up")
        XCTAssertFalse(room.actors[1].brain!.isSleeping, "he is not asleep when the trip starts")
        room.run(3) { care.race.trackVisible }
        XCTAssertTrue(care.race.trackVisible)
        // on the track nothing sleeps or plays antics, a goodnight is ignored for every body
        for a in room.actors {
            let b = a.brain!
            XCTAssertTrue(b.race.active)
            b.commandedGoodnight = true
            XCTAssertFalse(b.isSleeping)
        }
        room.run(1)
        for a in room.actors { XCTAssertFalse(a.brain!.isSleeping, "no sleeping on the track") }
        XCTAssertTrue(care.raceBusy)
    }

    /// The tap on a sleeper wakes him AND the selection goes on once he is upright (it does not start the draw while he lies).
    func testSelectingASleeperWakesHimThenSelects() {
        let room = Room()
        Self.keep.append(room)
        let care = room.care
        for a in room.actors { a.brain!.sleepEnabled = true }
        room.actors[2].brain!.commandedGoodnight = true
        room.run(40, until: { room.actors[2].brain!.isNapping })
        XCTAssertTrue(room.actors[2].brain!.isNapping)
        care.select.doubleTap(2)
        XCTAssertEqual(care.select.selectedID, 2)
        room.run(0.5)
        XCTAssertTrue(room.actors[2].brain!.sleep.wakeAsked || !room.actors[2].brain!.isSleeping, "the pick woke him")
        XCTAssertEqual(care.select.clock, 0, "the draw waits while he is lying")
        room.run(10, until: { !room.actors[2].brain!.isSleeping && care.select.clock > 0.2 })
        XCTAssertFalse(room.actors[2].brain!.isSleeping)
        XCTAssertGreaterThan(care.select.clock, 0.2, "then the selection proceeds")
        XCTAssertEqual(care.select.selectedID, 2)
    }

    func testRaceIsRefusedWhileSomethingElseRuns() {
        let room = Room()
        Self.keep.append(room)
        let care = room.care
        XCTAssertTrue(care.canRace(jelly: 0))
        XCTAssertFalse(care.canRace(jelly: 7), "no such Jelly")
        care.comeHere(jelly: 0)
        XCTAssertFalse(care.canRace(jelly: 0), "not in the close-up")
        care.startRace(jelly: 0)
        XCTAssertFalse(care.race.active)
    }
}

struct LocalRivalSourceFixed: RivalSource {
    var waddle: Float
    func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64) -> [Rival] {
        LocalRivalSource().rivals(count: count, player: player, playerTint: playerTint, seed: seed).map { var r = $0; r.stats = RacerStats(waddle: waddle, focus: 1); return r }
    }
}
