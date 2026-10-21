//
//  ShowFlowTests.swift
//  The Jelly Show's trip, headless: the fade and the swaps, the rounds in order (Look, the countdown that waits for the music, the dance on the
//  grid, three trick turns with the ring, the Glow Burst), the one-time settlement (Drops, record, trophies), the cues, the Studio's dance drill,
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
        p.glow = 0.8; p.dirt = 0; p.dance = .sway; p.danceSkill = 0.5
        p.tricks = [.sit: 0.9, .jacks: 0.9, .flip: 0.9]
        return p
    }
    private func flow() -> (ShowFlow, [ShowCue]) {
        let f = ShowFlow()
        f.songClock = { _ in nil }
        f.audioReady = { _ in true }
        return (f, [])
    }
    private func run(_ f: ShowFlow, seconds: Float, until: () -> Bool = { false }) {
        for _ in 0..<Int(seconds * 60) { f.tick(dt: 1 / 60); if until() { return } }
    }

    func testAWholeShowFromFadeToResultsAndHome() {
        let f = ShowFlow()
        f.songClock = { _ in nil }; f.audioReady = { _ in true }
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
        XCTAssertEqual(f.sim!.dance!.total, ShowRank.puddle.promptCount)
        run(f, seconds: 30) { f.beat == .danced }
        XCTAssertTrue(f.sim!.danceDone); XCTAssertGreaterThan(f.sim!.danceScore!, 60, "the auto player dances well")
        XCTAssertGreaterThan(cues.filter { $0 == .perfect }.count, 8)
        XCTAssertTrue(cues.contains(.go)); XCTAssertEqual(cues.filter { $0 == .countdown }.count, 3)
        run(f, seconds: 4) { f.round == .trick }
        XCTAssertEqual(dances.last?.1, false, "the dance stops")
        // three turns: pick, ring, perform; the Burst is on offer after a good dance with a shiny Jelbie
        run(f, seconds: 30) { f.sim?.round == .results && f.trickStage == .pick }
        XCTAssertEqual(f.sim!.turns.count, 3); XCTAssertEqual(performs.count, 3)
        XCTAssertEqual(Set(f.sim!.turns.map(\.trick)).count, 3, "the auto player shows three different tricks")
        XCTAssertTrue(f.sim!.burstUsed, "Cheer and Glow were high: the Burst fired"); XCTAssertTrue(cues.contains(.burst))
        for t in f.sim!.turns { XCTAssertGreaterThan(t.timing, 0.8, "the auto player taps near the ring's best") }
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

    func testRingTimingAndMissedRing() {
        let f = ShowFlow(); f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.cue = { _ in }
        f.begin(playerID: 0, name: "Bob", character: 0, input: input(), rank: .pond, dayKey: 20261022, bodies: 1, seed: 1)
        XCTAssertFalse(f.active, "the Pond is locked until a 1st at the Puddle")
        f.progress.record(rank: .puddle, place: 1, theme: .beachGames, character: 0, burst: false, perfectDance: false, hatTrick: false)
        f.begin(playerID: 0, name: "Bob", character: 0, input: input(), rank: .pond, dayKey: 20261022, bodies: 1, seed: 1)
        XCTAssertTrue(f.active)
        run(f, seconds: 2) { f.phase == .stage }
        f.finishLook()
        run(f, seconds: 5) { f.beat == .dancing }
        // (no taps: every prompt slips, no failing)
        run(f, seconds: 25) { f.beat == .danced }
        XCTAssertEqual(f.sim!.dance!.misses, ShowRank.pond.promptCount); XCTAssertEqual(f.sim!.danceScore!, 100 * 0.3 * 0.5, accuracy: 1e-3)
        f.finishDance()
        XCTAssertFalse(f.sim!.burstReady, "no cheer: no Burst")
        f.pick(.sit)
        XCTAssertEqual(f.trickStage, .ring)
        run(f, seconds: Float(ShowScoring.ringSeconds))
        f.tapRing()
        XCTAssertEqual(f.trickStage, .performing)
        XCTAssertGreaterThan(f.lastTurn!.timing, 0.9, "a tap as the ring hugs him is near-perfect")
        run(f, seconds: ShowFlow.performSeconds + 0.1)
        XCTAssertEqual(f.trickStage, .pick)
        f.pick(.jacks)
        run(f, seconds: Float(ShowScoring.ringSeconds + ShowFlow.ringGrace) + 0.2)
        XCTAssertEqual(f.trickStage, .performing, "a ring nobody tapped is judged (timing 0), still a turn")
        XCTAssertEqual(f.lastTurn!.timing, 0)
        XCTAssertEqual(f.sim!.turns.count, 2)
        f.pick(.sit)                      // not yet: he is still performing
        XCTAssertEqual(f.sim!.turns.count, 2); XCTAssertNil(f.sim!.ringTrick)
    }

    func testPracticeDrillTeachesTheDance() {
        let f = ShowFlow(); f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.auto = true
        var cues: [ShowCue] = []; f.cue = { cues.append($0) }
        let st = JellyStats(persists: false, dayKey: { 20261021 })
        f.beginPractice(playerID: 0, name: "Bob", character: 0, dance: .sway, stats: st, seed: 9)
        XCTAssertTrue(f.isPractice); XCTAssertEqual(f.track, .studioPractice); XCTAssertEqual(f.grid, .studio)
        run(f, seconds: 2) { f.phase == .stage }
        XCTAssertEqual(f.musicScene, .studio)
        run(f, seconds: 6) { f.beat == .dancing }
        XCTAssertEqual(f.practice!.total, ShowFlow.practicePrompts)
        run(f, seconds: 30) { f.practiceResult != nil }
        let r = f.practiceResult!
        XCTAssertEqual(r.dance, .sway); XCTAssertGreaterThan(r.accuracy, 0.6); XCTAssertGreaterThan(r.gain, 0.05)
        XCTAssertEqual(st.proficiency(.sway), r.after, accuracy: 1e-6); XCTAssertEqual(st.sessionsToday, 1)
        XCTAssertEqual(f.musicScene, .results); XCTAssertTrue(cues.contains(.jingle(win: true)))
        XCTAssertFalse(f.buttonsLive)
        f.goHome()
        run(f, seconds: 3) { !f.active }
        XCTAssertFalse(f.active)
    }

    func testAbortPutsEverythingBack() {
        let f = ShowFlow(); f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.cue = { _ in }
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
        let care = GameCare(jellyCount: 3, persistent: false)
        let p = care.jelly(0)!
        p.stats.setCondition(.sparkle, 0.7); p.stats.setCondition(.cute, 0.3)
        p.grime.sparkle = 0.6; p.grime.dirt = 0.2
        p.stats.learn(.sway, add: 0.4); p.stats.learn(.bop, add: 0.6)
        p.training.debugLearn(.sit, word: "sit", reliability: 0.8)
        p.training.debugLearn(.spin, word: "spin", reliability: 0.9)          // a store page he does not own: not on stage
        care.store.grant("page-hop"); p.training.debugLearn(.hop, word: "hop", reliability: 0.7)
        let i = care.showPlayerInput(jelly: 0)
        XCTAssertEqual(i.stat(.sparkly), 0.7, accuracy: 1e-4); XCTAssertEqual(i.stat(.cute), 0.3, accuracy: 1e-4)
        XCTAssertEqual(i.glow, 0.6, accuracy: 1e-5); XCTAssertEqual(i.dirt, 0.2, accuracy: 1e-5)
        XCTAssertEqual(i.dance, .bop); XCTAssertEqual(i.danceSkill, 0.6, accuracy: 1e-5)
        XCTAssertEqual(i.tricks, [.sit: 0.8, .hop: 0.7])
        care.store.grant("wear-flower_crown"); care.store.wear(.flowerCrown, on: 0)
        XCTAssertEqual(care.showOutfitTags(jelly: 0)[.head], WearLook.flowerCrown.tags)
        let est = care.showEstimate(jelly: 0, rank: .puddle, theme: .starlightGala)
        XCTAssertGreaterThan(est.look, 30); XCTAssertGreaterThan(est.trick, 30); XCTAssertLessThanOrEqual(est.total, 300)
        // locks
        XCTAssertNil(care.showBlocker(jelly: 0)); XCTAssertNotNil(care.showBlocker(jelly: 7))
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }
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

    func testSameDayReplayMeetsTheSameRivals() {
        let care = GameCare(jellyCount: 1, persistent: false)
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }
        care.startShow(jelly: 0, rank: .puddle, seed: 1)
        let a = care.show.sim!.rivals
        care.show.abort()
        care.startShow(jelly: 0, rank: .puddle, seed: 2)
        XCTAssertEqual(care.show.sim!.rivals, a)
        care.show.abort()
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

    /// The show's cards fit a phone on its side (440 pt tall).
    func testPracticeCardFitsTheLandscapeHeight() {
        let r = DancePracticeResult(dance: .sway, accuracy: 0.8, perfects: 14, goods: 4, misses: 2, before: 0.3, after: 0.42, pepLeft: 2, pepSpent: false)
        let h = UIHostingController(rootView: PracticeResultCard(result: r) {}.environment(\.verticalSizeClass, .compact))
        let height = h.sizeThatFits(in: CGSize(width: 520, height: CGFloat.infinity)).height
        print("SHOW practice card height \(height)")
        XCTAssertLessThanOrEqual(height, 400)
    }
}
