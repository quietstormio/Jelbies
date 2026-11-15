//
//  ShowFlowTests.swift
//  The Jelly Show's trip, headless: the fade and the swaps, the rounds in order (Look, the countdown that waits for the music, the dance on the
//  grid, three trick turns off the menu, the Glow Burst), the one-time settlement (Drops, record, trophies), the cues, the Studio's dance drill,
//  the care glue (locks, inputs read from the Jelbie, rivals borrowed as bodies), and the stage camera keeping every body in the frame both ways.
//

import XCTest
import simd
import SwiftUI
import UIKit
@testable import BobV1

@MainActor
final class ShowFlowTests: XCTestCase {
    private func input() -> ShowPlayerInput {
        var p = ShowPlayerInput(name: "Bob")
        for t in WearTag.allCases { p.condition[t] = 0.5 }
        p.glow = 0.8; p.dirt = 0; p.dance = .sway
        p.tricks = [.sit: 0.9, .jacks: 0.9, .flip: 0.9]; p.care = 1
        return p
    }
    private func flow() -> (ShowFlow, [ShowCue]) {
        let f = ShowFlow()
        f.songClock = { _ in nil }
        f.audioReady = { _ in true }; f.danceSongPrepared = { _ in true }; f.prepareDanceSong = { _ in }; f.releaseDanceSong = {}
        return (f, [])
    }
    private func run(_ f: ShowFlow, seconds: Float, until: () -> Bool = { false }) {
        for _ in 0..<Int(seconds * 60) { f.tick(dt: 1 / 60); if until() { return } }
    }

    func testAWholeShowFromFadeToResultsAndHome() {
        let f = ShowFlow()
        f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.danceSongPrepared = { _ in true }; f.prepareDanceSong = { _ in }; f.releaseDanceSong = {}
        var cues: [ShowCue] = []; f.cue = { cues.append($0) }
        var swaps: [ShowFlow.Dest] = []; f.onSwap = { swaps.append($0) }
        var performs: [(VoiceTrick, Bool)] = []; f.onPerform = { performs.append(($0, $1)) }
        var dances: [(DanceID?, Bool)] = []; f.onDance = { dances.append(($0, $1)) }
        var returned: (Int, Bool, Bool)?; f.onReturned = { returned = ($0, $1, $2) }
        var celebrated: Int?; f.onResults = { celebrated = $0 }
        let wallet = DropsWallet(persists: false); f.wallet = wallet
        f.auto = true
        f.begin(playerID: 1, name: "Bob", character: 1, input: input(), rank: .puddle, dayKey: 20261021, bodies: 3, seed: 3)
        XCTAssertTrue(f.active); XCTAssertEqual(f.phase, .fade); XCTAssertEqual(f.theme, ShowSchedule.theme(dayKey: 20261021))
        f.setOutfit([.head: [f.theme.main], .feet: [f.theme.friend]])
        run(f, seconds: 2) { f.phase == .stage }
        XCTAssertEqual(swaps, [.stage]); XCTAssertTrue(f.onStage); XCTAssertEqual(f.musicScene, .show); XCTAssertEqual(f.round, .look)
        XCTAssertEqual(f.sim!.lookScore, 40 * 0.75 + 40 * 0.5 + 20 * 0.8, accuracy: 1e-3)
        // the auto player moves on after a moment: the countdown, then the dance on the grid
        run(f, seconds: 4) { f.beat == .countdown }
        XCTAssertEqual(f.round, .dance); XCTAssertEqual(f.countdown, 3); XCTAssertTrue(f.showsCountdown)
        XCTAssertEqual(dances.first?.0, .sway); XCTAssertEqual(dances.first?.1, true)
        run(f, seconds: 5) { f.beat == .dancing }
        XCTAssertTrue(f.buttonsLive); XCTAssertNotNil(f.sim?.dance)
        XCTAssertEqual(f.sim!.dance!.total, f.danceSong.promptCount, "one prompt per beat of the picked song")
        run(f, seconds: 30) { f.beat == .danced }
        XCTAssertTrue(f.sim!.danceDone); XCTAssertGreaterThan(f.sim!.danceScore!, 60, "the auto player dances well")
        XCTAssertGreaterThan(cues.filter { $0 == .perfect }.count, 8)
        XCTAssertTrue(cues.contains(.go)); XCTAssertEqual(cues.filter { $0 == .countdown }.count, 3)
        run(f, seconds: 4) { f.round == .trick }
        XCTAssertEqual(dances.last?.1, false, "the dance stops")
        // three turns: pick, perform, then each rival walks up and shows hers; the Burst is on offer after a good dance with a shiny Jelbie
        run(f, seconds: 120) { f.sim?.round == .results && f.trickStage == .pick }
        XCTAssertEqual(f.sim!.turns.count, 3); XCTAssertEqual(performs.count, 3)
        XCTAssertEqual(Set(f.sim!.turns.map(\.trick)).count, 3, "the auto player shows three different tricks")
        XCTAssertTrue(f.sim!.burstUsed, "Cheer and Glow were high: the Burst fired"); XCTAssertTrue(cues.contains(.burst))
        // settled once: Drops, the record, the awards
        XCTAssertTrue(f.hasResults); XCTAssertNotNil(celebrated)
        XCTAssertEqual(f.earned, ShowRank.puddle.drops(place: f.sim!.playerPlace!)); XCTAssertEqual(wallet.count, f.earned)
        XCTAssertEqual(f.progress.record(.puddle).shows, 1); XCTAssertNotNil(f.awards)
        XCTAssertEqual(f.awards?.stickers.contains(.firstShow), true); XCTAssertEqual(f.awards?.stickers.contains(.glowBurst), true)
        XCTAssertEqual(f.musicScene, .results); XCTAssertTrue(cues.contains { if case .jingle = $0 { return true }; return false })
        run(f, seconds: 1)
        XCTAssertEqual(wallet.count, f.earned, "paid once")
        // home again
        f.goHome(again: true)
        run(f, seconds: 3) { !f.active }
        XCTAssertEqual(swaps, [.stage, .room]); XCTAssertEqual(returned?.0, 1); XCTAssertEqual(returned?.2, true)
        XCTAssertEqual(returned?.1, f.progress.record(.puddle).wins == 1)
        XCTAssertNil(f.sim); XCTAssertEqual(f.musicScene, .none)
    }

    /// Picking a trick performs it at once (no ring); a pick while he is performing is ignored; the dance with no taps scores 0.
    func testPickingATrickPerformsItAtOnce() {
        let f = ShowFlow(); f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.danceSongPrepared = { _ in true }; f.prepareDanceSong = { _ in }; f.releaseDanceSong = {}; f.cue = { _ in }
        var performs: [(VoiceTrick, Bool)] = []; f.onPerform = { performs.append(($0, $1)) }
        f.begin(playerID: 0, name: "Bob", character: 0, input: input(), rank: .pond, dayKey: 20261022, bodies: 1, seed: 1)
        XCTAssertFalse(f.active, "the Pond is locked until a 1st at the Puddle")
        f.progress.record(rank: .puddle, place: 1, theme: .beachGames, character: 0, burst: false, perfectDance: false, hatTrick: false)
        f.begin(playerID: 0, name: "Bob", character: 0, input: input(), rank: .pond, dayKey: 20261022, bodies: 1, seed: 1)
        XCTAssertTrue(f.active)
        run(f, seconds: 2) { f.phase == .stage }
        XCTAssertEqual(f.round, .look)
        run(f, seconds: ShowFlow.lookSeconds + 0.5) { f.round == .dance }
        XCTAssertEqual(f.round, .dance, "the Look walk-on moves on by itself")
        run(f, seconds: 5) { f.beat == .dancing }
        // (no taps: every prompt slips, no failing)
        run(f, seconds: 25) { f.beat == .danced }
        XCTAssertEqual(f.sim!.dance!.misses, f.danceSong.promptCount); XCTAssertEqual(f.sim!.danceScore!, 0, accuracy: 1e-3, "all slips: 0 (the score is 100% accuracy)")
        f.finishDance()
        XCTAssertFalse(f.sim!.burstReady, "no cheer: no Burst")
        f.pick(.sit)
        XCTAssertEqual(f.trickStage, .performing); XCTAssertEqual(performs.count, 1)
        XCTAssertEqual(f.sim!.turns.count, 1)
        f.pick(.jacks)                    // not yet: he is still performing
        XCTAssertEqual(f.sim!.turns.count, 1)
        run(f, seconds: ShowFlow.performSeconds + 0.1)
        XCTAssertEqual(f.trickStage, .rivals, "the rivals take their turn before his next one")
        f.pick(.jacks)                    // not yet: it is the rivals' turn
        XCTAssertEqual(f.sim!.turns.count, 1)
        f.skipRivals()
        XCTAssertEqual(f.trickStage, .pick)
        f.pick(.jacks)
        XCTAssertEqual(f.sim!.turns.count, 2); XCTAssertEqual(f.lastTurn?.trick, .jacks)
    }

    /// The Look round is a judged walk-on: there is no wardrobe on the stage, it moves on after about 3 s, or at once on Next.
    func testLookWalkOnAdvancesByItselfOrOnNext() {
        let f = ShowFlow(); f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.danceSongPrepared = { _ in true }; f.prepareDanceSong = { _ in }; f.releaseDanceSong = {}; f.cue = { _ in }
        f.begin(playerID: 0, name: "Bob", character: 0, input: input(), rank: .puddle, dayKey: 20261022, bodies: 1, seed: 1)
        run(f, seconds: 2) { f.phase == .stage }
        f.setOutfit([.head: [f.theme.main]])
        let look = f.sim!.lookScore
        run(f, seconds: 2)
        XCTAssertEqual(f.round, .look, "still judging after 2 s")
        run(f, seconds: 1.5) { f.round == .dance }
        XCTAssertEqual(f.round, .dance); XCTAssertEqual(f.sim!.lookScore, look, "the outfit he walked on in is the one scored")
        let g = ShowFlow(); g.songClock = { _ in nil }; g.audioReady = { _ in true }; g.danceSongPrepared = { _ in true }; g.prepareDanceSong = { _ in }; g.releaseDanceSong = {}; g.cue = { _ in }
        g.begin(playerID: 0, name: "Bob", character: 0, input: input(), rank: .puddle, dayKey: 20261022, bodies: 1, seed: 1)
        run(g, seconds: 2) { g.phase == .stage }
        g.finishLook()
        XCTAssertEqual(g.round, .dance, "Next moves on at once")
    }

    /// A brand-new Jelbie (no tricks learned) can enter: the default tricks are on his menu, and the show reaches its results.
    func testNoTricksLearnedStillHasTheDefaultsAndFinishesTheShow() {
        let f = ShowFlow(); f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.danceSongPrepared = { _ in true }; f.prepareDanceSong = { _ in }; f.releaseDanceSong = {}; f.cue = { _ in }; f.auto = true
        var p = ShowPlayerInput(name: "Bob"); p.tricks = [:]
        f.begin(playerID: 0, name: "Bob", character: 0, input: p, rank: .puddle, dayKey: 20261023, bodies: 1, seed: 2)
        XCTAssertEqual(Set(f.sim!.knownTricks), Set(ShowTrickInfo.defaults))
        run(f, seconds: 240) { f.hasResults }
        XCTAssertTrue(f.hasResults)
        XCTAssertEqual(f.sim!.turns.count, 3)
        for t in f.sim!.turns { XCTAssertTrue(ShowTrickInfo.defaults.contains(t.trick)); XCTAssertGreaterThanOrEqual(t.points, ShowTuning.flopPoints) }
        XCTAssertNotNil(f.sim!.playerPlace)
    }

    func testAbortPutsEverythingBack() {
        let f = ShowFlow(); f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.danceSongPrepared = { _ in true }; f.prepareDanceSong = { _ in }; f.releaseDanceSong = {}; f.cue = { _ in }
        var swaps: [ShowFlow.Dest] = []; f.onSwap = { swaps.append($0) }
        f.begin(playerID: 0, name: "Bob", character: 0, input: input(), rank: .puddle, dayKey: 1, bodies: 2, seed: 1)
        run(f, seconds: 2) { f.phase == .stage }
        f.abort()
        XCTAssertFalse(f.active); XCTAssertEqual(f.wipe, 0); XCTAssertEqual(swaps, [.stage, .room]); XCTAssertNil(f.sim)
        // a locked rank cannot be entered
        f.begin(playerID: 0, name: "Bob", character: 0, input: input(), rank: .ocean, dayKey: 1, bodies: 2, seed: 1)
        XCTAssertFalse(f.active)
    }

    // MARK: the care glue

    func testCareReadsTheJelbieAndBorrowsBodies() {
        // Bob's stats ride on UserDefaults.standard even in a non-persistent GameCare (JellyProfile's default), so a rerun on the same
        // simulator would stack the dance proficiency past 0.6: start (and leave) clean.
        func scrub() { for suffix in ["", ".cond", ".train", ".dances", ".meals"] { UserDefaults.standard.removeObject(forKey: JellyKeys.stats(0) + suffix) } }
        scrub(); defer { scrub() }
        let care = GameCare(jellyCount: 3, persistent: false)
        let p = care.jelly(0)!
        p.stats.setCondition(.sparkle, 0.7); p.stats.setCondition(.cute, 0.3)
        p.grime.sparkle = 0.6; p.grime.dirt = 0.2
        p.stats.learn(.sway, add: 0.4); p.stats.learn(.bop, add: 0.6)
        care.store.grantTrick(.flip, to: 1)          // bought for another Jelbie: not on his stage
        let i = care.showPlayerInput(jelly: 0)
        XCTAssertEqual(i.stat(.sparkly), 0.7, accuracy: 1e-4); XCTAssertEqual(i.stat(.cute), 0.3, accuracy: 1e-4)
        XCTAssertEqual(i.glow, 0.6, accuracy: 1e-5); XCTAssertEqual(i.dirt, 0.2, accuracy: 1e-5)
        XCTAssertEqual(i.dance, .bop)
        XCTAssertEqual(Set(i.tricks.keys), Set(ShowTrickInfo.defaults), "what he knows: the defaults (nothing was bought for him)")
        care.store.grantTrick(.flip, to: 0)
        XCTAssertNotNil(care.showPlayerInput(jelly: 0).tricks[.flip], "a trick bought for him is on his menu")
        XCTAssertGreaterThan(i.care, 0); XCTAssertLessThanOrEqual(i.care, 1)
        care.store.grant("wear-flower_crown"); care.store.wear(.flowerCrown, on: 0)
        XCTAssertEqual(care.showOutfitTags(jelly: 0)[.head], WearLook.flowerCrown.tags)
        let est = care.showEstimate(jelly: 0, rank: .puddle, theme: .starlightGala)
        XCTAssertGreaterThan(est.look, 30); XCTAssertGreaterThan(est.trick, 30); XCTAssertLessThanOrEqual(est.total, 300)
        // locks
        XCTAssertNil(care.showBlocker(jelly: 0)); XCTAssertNotNil(care.showBlocker(jelly: 7))
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.danceSongPrepared = { _ in true }; care.show.prepareDanceSong = { _ in }; care.show.releaseDanceSong = {}
        care.startShow(jelly: 0, rank: .puddle, seed: 5)
        XCTAssertTrue(care.show.active); XCTAssertTrue(care.tripActive); XCTAssertTrue(care.raceBusy)
        XCTAssertNotNil(care.showBlocker(jelly: 1)); XCTAssertNotNil(care.raceBlocker(jelly: 1))
        XCTAssertNil(care.showFrame, "not on stage yet")
        care.feed(jelly: 0); XCTAssertFalse(care.trayOut, "no meals during a show")
        care.beginFocus(ids: [0]); XCTAssertFalse(care.focus.isActive, "no close-up during a show")
        for _ in 0..<180 { care.tickShow([], dt: 1 / 60) }
        XCTAssertTrue(care.show.onStage); XCTAssertEqual(care.showFrame, .look)
        XCTAssertEqual(care.show.sim?.outfit[.head], WearLook.flowerCrown.tags, "the outfit reached the sim")
        XCTAssertEqual(care.showRivalsWithBodies, [], "headless: no bodies to borrow")
        XCTAssertTrue(care.showHidesWear(1)); XCTAssertFalse(care.showHidesWear(0))
        care.show.abort()
        XCTAssertFalse(care.show.active); XCTAssertNil(care.showBlocker(jelly: 0))
    }

    // MARK: the rivals' turns

    private final class Log { var a: [String] = [] }
    /// A show at the Trick round with nothing automatic; `log` hears every performance in order.
    private func showAtTrick(_ log: Log, day: Int = 20261021, seed: UInt64 = 3) -> ShowFlow {
        let f = ShowFlow(); f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.danceSongPrepared = { _ in true }; f.prepareDanceSong = { _ in }; f.releaseDanceSong = {}; f.cue = { _ in }
        f.onPerform = { t, _ in log.a.append("P:\(t.rawValue)") }
        f.onRival = { c in
            switch c {
            case .playerAside(let a): log.a.append("aside:\(a)")
            case .walkIn(let i): log.a.append("in:\(i)")
            case .perform(let i, let t, _): log.a.append("R\(i):\(t.rawValue)")
            case .walkOut(let i): log.a.append("out:\(i)")
            case .snap: log.a.append("snap")
            }
        }
        f.begin(playerID: 0, name: "Bob", character: 0, input: input(), rank: .puddle, dayKey: day, bodies: 1, seed: seed)
        run(f, seconds: 2) { f.phase == .stage }
        f.finishLook()
        run(f, seconds: 6) { f.beat == .dancing }
        run(f, seconds: 30) { f.beat == .danced }
        f.finishDance()
        return f
    }

    /// Three turns, each: his trick, then every rival walks up, performs and steps back, in order; then his again.
    func testTurnsAlternateThePlayerAndEachRivalThreeTimes() {
        let log = Log()
        let f = showAtTrick(log)
        XCTAssertEqual(f.round, .trick)
        let n = f.sim!.rivals.count
        XCTAssertEqual(n, 3)
        for (turn, t) in [VoiceTrick.sit, .jacks, .flip].enumerated() {
            log.a.removeAll()
            f.pick(t)
            run(f, seconds: 5) { f.trickStage == .rivals }
            XCTAssertEqual(f.trickStage, .rivals); XCTAssertEqual(f.rivalRound, turn)
            run(f, seconds: 60) { f.trickStage == .pick }
            XCTAssertEqual(f.trickStage, .pick)
            var want = ["P:\(t.rawValue)", "aside:true"]
            for i in 0..<n { want += ["in:\(i)", "R\(i):\(f.sim!.rivalTurns[i][turn].trick.rawValue)", "out:\(i)"] }
            want.append("aside:false")
            XCTAssertEqual(log.a, want, "turn \(turn + 1)")
            XCTAssertEqual(f.sim!.turns.count, turn + 1)
            for i in 0..<n { XCTAssertEqual(f.sim!.rivalTurns[i].count, turn + 1) }
        }
        XCTAssertEqual(f.sim!.round, .results); XCTAssertTrue(f.hasResults); XCTAssertTrue(f.settled)
        XCTAssertEqual(f.sim!.entrants.count, n + 1)
    }

    /// Skip settles the rest of the rivals (their points count), snaps the bodies and opens his next turn; a tap on the banner skips only the rival under the lights.
    func testSkipSettlesTheRestOfTheRivalsAndOpensHisNextTurn() {
        let log = Log()
        let f = showAtTrick(log)
        f.pick(.sit)
        run(f, seconds: 5) { f.trickStage == .rivals }
        run(f, seconds: 5) { f.rivalStep == .perform }
        XCTAssertEqual(f.rivalTurn, 0); XCTAssertNotNil(f.rivalNow)
        f.skipCurrentRival()
        XCTAssertEqual(f.rivalStep, .walkOut); XCTAssertEqual(log.a.last, "out:0")
        run(f, seconds: 5) { f.rivalTurn == 1 }
        XCTAssertEqual(f.rivalTurn, 1, "the next rival walks up")
        let before = f.sim!.rivalTurns
        f.skipRivals()
        XCTAssertEqual(f.trickStage, .pick); XCTAssertEqual(log.a.last, "snap"); XCTAssertNil(f.rivalTurn)
        XCTAssertEqual(f.sim!.rivalTurns, before, "their points were already counted")
        for r in f.sim!.rivalTurns { XCTAssertEqual(r.count, 1) }
        XCTAssertEqual(f.sim!.turns.count, 1)
        f.pick(.jacks)
        XCTAssertEqual(f.sim!.turns.count, 2, "his next turn is open at once")
        run(f, seconds: 5) { f.trickStage == .rivals }
        f.skipRivals()
        f.pick(.flip)
        run(f, seconds: 5) { f.trickStage == .rivals }
        f.skipRivals()
        XCTAssertEqual(f.sim!.round, .results); XCTAssertTrue(f.settled)
        run(f, seconds: 1)
        XCTAssertTrue(f.hasResults)
        let s = f.sim!
        for (i, e) in s.entrants.dropFirst().enumerated() {
            XCTAssertEqual(s.rivalTurns[i].count, 3)
            XCTAssertEqual(e.scores.trick, s.rivalScores(i).trick)
        }
    }

    /// The glue: a roster of 2 has one spare Jelbie, so the other two rivals borrow park-visitor bodies for the Trick round, shown only then, and give them back.
    func testRivalsBorrowBodiesAndGiveThemBack() {
        let room = RaceThreeTests.Room(count: 2)
        RaceThreeTests.keep.append(room)
        let care = room.care
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.danceSongPrepared = { _ in true }; care.show.prepareDanceSong = { _ in }; care.show.releaseDanceSong = {}; care.show.cue = { _ in }
        func step() {
            for a in room.actors + room.park { if let b = a.brain { b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false) } }
            care.tickRace(room.actors, dt: 1 / 60)
            care.tickShow(room.actors, dt: 1 / 60)
        }
        func run(_ s: Float, until: () -> Bool = { false }) { for _ in 0..<Int(s * 60) { step(); if until() { return } } }
        care.startShow(jelly: 0, rank: .puddle, seed: 5)
        run(4) { care.show.onStage }
        XCTAssertTrue(care.show.onStage)
        let book = care.showBook
        XCTAssertEqual(book.extra.count, 2, "3 rivals, 1 spare Jelmiko: two borrowed bodies")
        XCTAssertEqual(room.park.count, 2)
        XCTAssertEqual(book.rivalBody.count, 3); XCTAssertEqual(Set(book.rivalBody.values).count, 3, "every rival has her own body")
        XCTAssertEqual(book.rivalBody[0], book.performers[1], "the spare Jelmiko first")
        for a in book.extra { XCTAssertTrue(care.showHides(a.id), "hidden until the Trick round") }
        care.show.auto = true
        run(120) { care.show.trickStage == .rivals }
        XCTAssertEqual(care.show.trickStage, .rivals)
        for a in book.extra { XCTAssertFalse(care.showHides(a.id), "on stage for the rivals' turn") }
        XCTAssertFalse(care.showHides(book.rivalBody[0]!))
        care.show.abort()
        XCTAssertTrue(book.extra.isEmpty, "borrowed bodies released"); XCTAssertTrue(room.park.isEmpty)
        XCTAssertTrue(book.rivalBody.isEmpty)
        XCTAssertFalse(care.show.active)
    }

    func testSameDayReplayMeetsTheSameRivals() {
        let care = GameCare(jellyCount: 1, persistent: false)
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.danceSongPrepared = { _ in true }; care.show.prepareDanceSong = { _ in }; care.show.releaseDanceSong = {}
        care.startShow(jelly: 0, rank: .puddle, seed: 1)
        let a = care.show.sim!.rivals
        care.show.abort()
        care.startShow(jelly: 0, rank: .puddle, seed: 2)
        XCTAssertEqual(care.show.sim!.rivals, a)
        care.show.abort()
    }

    // MARK: the dance song's clock

    /// A show brought to the first frame of the dance (GO), with the audio stubs given.
    private func danceFlow(clock: @escaping (SceneTrack) -> Double?, ready: @escaping (MusicScene) -> Bool) -> ShowFlow {
        let f = ShowFlow(); f.cue = { _ in }; f.auto = true
        f.songClock = clock; f.audioReady = ready; f.danceSongPrepared = { _ in true }; f.prepareDanceSong = { _ in }; f.releaseDanceSong = {}; f.songClockWhy = { "test: \($0.rawValue) has no clock" }
        f.begin(playerID: 1, name: "Bob", character: 1, input: input(), rank: .puddle, dayKey: 20261021, bodies: 3, seed: 3)
        run(f, seconds: 2) { f.phase == .stage }
        run(f, seconds: 6) { f.beat == .countdown }
        run(f, seconds: 8) { f.beat == .dancing }
        return f
    }

    /// The song's clock never comes (voice not playing): after 1.5 s of dancing the flow records ONE reason, and keeps it.
    func testDanceRecordsWhyTheSongWasNotHeard() {
        let f = danceFlow(clock: { _ in nil }, ready: { _ in true })
        XCTAssertEqual(f.beat, .dancing); XCTAssertNil(f.danceFallback)
        run(f, seconds: 1.3); XCTAssertNil(f.danceFallback, "not before 1.5 s")
        run(f, seconds: 0.5)
        let why = f.danceFallback
        XCTAssertEqual(why, "test: \(f.danceTrack.rawValue) has no clock")
        run(f, seconds: 3); XCTAssertEqual(f.danceFallback, why, "one record per dance")
        // a voice that is not even ready: the same, once the 1.5 s wait is over
        let g = danceFlow(clock: { _ in nil }, ready: { s in if case .danceSong = s { return false }; return true })
        run(g, seconds: 1.3); XCTAssertNil(g.danceFallback)
        run(g, seconds: 0.6)
        XCTAssertEqual(g.danceFallback, "test: \(g.danceTrack.rawValue) has no clock; scene voice not playing")
    }

    /// A song clock that answers: no fallback record, however long the dance runs.
    func testDanceRecordsNothingWhenTheSongIsHeard() {
        var t = 0.0
        let f = danceFlow(clock: { _ in t += 1 / 60; return t }, ready: { _ in true })
        run(f, seconds: 5)
        XCTAssertNil(f.danceFallback); XCTAssertGreaterThan(f.danceT, 4)
    }

    // MARK: the prepared dance song

    private func countdownFlow(prepared: @escaping (SceneTrack) -> Bool, ready: @escaping (MusicScene) -> Bool = { _ in true }) -> (ShowFlow, () -> [SceneTrack]) {
        var asked: [SceneTrack] = []
        let f = ShowFlow(); f.cue = { _ in }; f.auto = true
        f.songClock = { _ in nil }; f.audioReady = ready; f.songClockWhy = { _ in "test" }
        f.prepareDanceSong = { asked.append($0) }; f.danceSongPrepared = prepared; f.releaseDanceSong = {}
        f.begin(playerID: 1, name: "Bob", character: 1, input: input(), rank: .puddle, dayKey: 20261021, bodies: 3, seed: 3)
        run(f, seconds: 2) { f.phase == .stage }
        run(f, seconds: 6) { f.beat == .countdown }
        return (f, { asked })
    }

    /// The countdown asks for the dance song to be prepared, and does not count down while it is not (the stage loop is up).
    func testCountdownWaitsForThePreparedDanceSong() {
        var ready = false
        let (f, asked) = countdownFlow(prepared: { _ in ready })
        XCTAssertEqual(f.beat, .countdown); XCTAssertEqual(asked(), [f.danceTrack], "prepared once, at the start of the countdown")
        run(f, seconds: 2)
        XCTAssertEqual(f.beat, .countdown); XCTAssertEqual(f.countdown, 3, "no number counted while the song is not ready")
        ready = true
        run(f, seconds: 6) { f.beat == .dancing }
        XCTAssertEqual(f.beat, .dancing, "GO comes once it is ready")
        XCTAssertNil(f.danceFallback, "it was ready in time")
    }

    /// A slow start that became ready before GO records no reason: the stage loop is up and the song is prepared when the count ends, and the
    /// dance track itself is (still) not playing, as on a device where the director's sceneOn comes a frame after GO.
    func testSlowStartThatBecameReadyRecordsNoFalseReason() {
        var prepared = false
        let (f, _) = countdownFlow(prepared: { _ in prepared }, ready: { s in if case .danceSong = s { return false }; return true })
        run(f, seconds: 3.3)          // the 3 s wait is spent: the count goes on
        prepared = true
        var guardTicks = 0
        while f.beat != .dancing, guardTicks < 12 * 60 { f.tick(dt: 1 / 60); guardTicks += 1 }
        XCTAssertEqual(f.beat, .dancing)
        XCTAssertNil(f.danceFallback, "both were ready at GO: \(f.danceFallback ?? "")")
    }

    // MARK: the prepared voice in the scene engine (state only: no audio device here)

    /// A prepare is "in flight" until it is loaded or discarded; a discarded one is not waited for.
    func testPreparingIsOnlyWhileADecodeRuns() {
        let e = SceneMusicEngine()
        e.prepare(.dance1)
        XCTAssertTrue(e.isPreparing(.dance1)); XCTAssertFalse(e.isPrepared(.dance1)); XCTAssertEqual(e.decodeRequests, 1)
        e._markPreparedLoaded()
        XCTAssertFalse(e.isPreparing(.dance1)); XCTAssertTrue(e.isPrepared(.dance1))
        e.discardPrepared()
        XCTAssertFalse(e.isPreparing(.dance1)); XCTAssertFalse(e.isPrepared(.dance1))
        e.stopAll(fade: 0)
    }

    /// A config change rebuilds the prepared voice even with nothing else playing: it is discarded and a new decode asked for.
    func testConfigChangeRebuildsThePreparedVoiceEvenWithNothingPlaying() {
        let e = SceneMusicEngine()
        e.prepare(.dance2); e._markPreparedLoaded()
        XCTAssertTrue(e.isPrepared(.dance2)); XCTAssertNil(e.current)
        e.restartAfterConfigChange()
        XCTAssertFalse(e.isPrepared(.dance2), "the old voice is gone")
        XCTAssertTrue(e.isPreparing(.dance2)); XCTAssertEqual(e.decodeRequests, 2, "a new decode was asked for")
        e.stopAll(fade: 0)
    }

    /// The song never gets ready: after the 3 s wait the countdown runs anyway and GO carries the reason.
    func testCountdownGoesAnywayAfterThreeSecondsWithTheReasonSet() {
        let (f, _) = countdownFlow(prepared: { _ in false })
        run(f, seconds: 2.7); XCTAssertEqual(f.countdown, 3, "still waiting"); XCTAssertEqual(f.beat, .countdown); XCTAssertNil(f.danceFallback)
        var ticks = 0
        for _ in 0..<(12 * 60) where f.beat != .dancing { f.tick(dt: 1 / 60); ticks += 1 }
        XCTAssertEqual(f.beat, .dancing, "GO comes anyway")
        XCTAssertGreaterThan(Double(ticks) / 60, 2.5, "after the 3 s wait and the three counts")
        XCTAssertEqual(f.danceFallback?.contains("dance song not prepared"), true, f.danceFallback ?? "nil")
        XCTAssertEqual(f.danceFallback?.contains("then no song clock") ?? true, false, "the clock's own 1.5 s have not run yet")
        run(f, seconds: 2)
        XCTAssertEqual(f.danceFallback?.contains("dance song not prepared"), true, "the GO reason is kept")
        XCTAssertEqual(f.danceFallback?.contains("then no song clock: test"), true, "and the clock's reason is added once: \(f.danceFallback ?? "nil")")
        XCTAssertEqual(f.danceFallback?.components(separatedBy: "then no song clock").count, 2)
    }

    // MARK: the stage camera

    private func ndc(_ cam: CameraState, _ p: SIMD3<Float>) -> SIMD3<Float>? {
        let c = cam.viewProj * SIMD4<Float>(p.x, p.y, p.z, 1)
        guard c.w > 1e-3 else { return nil }
        return SIMD3(c.x / c.w, c.y / c.w, c.z / c.w)
    }

    /// Every stage frame keeps every body on it (floor to the top of the head, a body's width either side) inside the screen, portrait and landscape.
    func testStageFramesKeepTheBodiesInViewBothWays() {
        let frames: [(String, ShowFrame)] = [("look", .look), ("trick", .trick), ("dance1", .dance(bodies: 1)), ("dance3", .dance(bodies: 3)), ("results", .results), ("practice", .practice)]
        for (name, size) in LandscapeTests.sizes {
            let aspect = Float(size.width / size.height)
            for (fname, frame) in frames {
                let cam = GameCamera.camera(aspect: aspect, show: 1, showFrame: frame)
                for s in frame.spots {
                    for dx in [-BobShape.R, BobShape.R] { for y in [Float(0), BobShape.H + 0.1] {
                        guard let n = ndc(cam, SIMD3(s.x + dx, y, s.y)) else { XCTFail("\(name) \(fname) behind the camera"); continue }
                        XCTAssertLessThanOrEqual(abs(n.x), 0.98, "\(name) \(fname): a body is cropped at the side")
                        XCTAssertLessThanOrEqual(abs(n.y), 0.98, "\(name) \(fname): a body is cropped top / bottom")
                    } }
                }
                // the stage set is behind the camera's near plane and in front of the far one
                XCTAssertNotNil(ndc(cam, SIMD3(0, 3, ShowModels.backdropZ)), "\(name) \(fname): the backdrop is in view")
            }
        }
        // the player's spot projects to the upper part of a portrait screen (the cards take the bottom)
        let p = StageProject.body(ShowStage.playerSpot, frame: .look, size: CGSize(width: 440, height: 956))
        XCTAssertLessThan(p.centre.y, 956 * 0.4); XCTAssertGreaterThan(p.radius, 30)
        let l = StageProject.body(ShowStage.playerSpot, frame: .look, size: CGSize(width: 956, height: 440))
        XCTAssertLessThan(l.centre.x, 956 * 0.42, "a phone on its side: the solo rounds put him on the left")
    }

}
