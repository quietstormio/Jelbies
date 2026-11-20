//
//  WinCelebrationTests.swift
//  "When your Jelmikos wins first place make them bounce and lift little arms up and celebrate winning" (owner 2026-11-19).
//  BlobBrain+Win.swift: the jump for joy run as four tall bounces with the arms held up, a cheer in his own voice, a settle. Only the player's own Jelmiko at 1st place.
//    - the move: four bounces, 2.5...3.6 s, arms at the joy pose all the way (never stretched), arms and feet attached in every frame, nothing left behind when it is cut
//    - the sound: PLAYED past the hub's guards (AudioHub.firedTap), with the race's results scene up (the home room's context voices are dropped there)
//    - the race: 1st place starts it for the player's body, not for the rivals'; another place does not
//    - the Show: results with place 1 start it; place 2...4 keep the plain jump for joy
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WinCelebrationTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    nonisolated(unsafe) static var clockBase = 90_000.0

    override func setUp() { DayClock.shared.forcedHour = 12 }

    /// Runs `body` with the hub open in dry-run and every fired clip recorded.
    private func withHub(scene: MusicScene = .none, _ body: @MainActor (_ fired: () -> [String]) -> Void) {
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        let base = Self.clockBase
        var names: [String] = []
        AudioHub.firedTap = { names.append($0) }
        hub.situation(napping: [], playing: false, xs: [], moods: [], scene: scene)
        defer { AudioHub.firedTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() }; hub.situation(napping: [], playing: false, xs: [], moods: [], scene: .none); Self.clockBase = base + 500 }
        AudioHub.clock = { base }
        body { names }
    }

    // MARK: the move

    private func rig() -> MotionRig {
        let r = MotionRig(game: true)
        r.renderSamples = false
        Self.keep.append(r)
        r.brain.idleForced = true
        return r
    }

    func testTheWinIsFourBouncesWithTheArmsUpAndASettle() {
        let r = rig(), b = r.brain
        let yaw0 = b.yaw
        var maxTurn: Float = 0
        XCTAssertTrue(b.winStart(r.sim))
        XCTAssertEqual(b.idleState.kind, .joy)
        XCTAssertEqual(b.idleState.reps, BlobBrain.winHops)
        var airs = 0, wasAir = false, armsUpFrames = 0, frames = 0, maxW: Float = 0
        var minElev: Float = .infinity, maxApex: Float = 0, happyFrames = 0, smileFrames = 0
        let y0 = r.sim.centroid().y
        var w = SocialTests.Watch()
        r.run(8, until: { b.idleState.kind == nil && r.t > 0.5 }, each: {
            let air = b.gait.phase == .air
            if air && !wasAir { airs += 1 }
            wasAir = air
            frames += 1
            maxW = max(maxW, b.armDirW)
            maxTurn = max(maxTurn, abs(wrapAngle(b.yaw - yaw0)))
            if b.armLiftNow > 0.95 && b.armDirW > 0.95 && abs(b.armDirEl[0] - WinTuning.armEl) < 0.1 { armsUpFrames += 1 }
            maxApex = max(maxApex, r.sim.centroid().y - y0)
            if b.armLiftNow > 0.95 && b.armDirW > 0.99 {          // (the arm rig has caught up with the command: its lift spring takes ~0.5 s)
                // the DRAWN arms: the tip of each stub against its root in the body frame (elevation above the horizontal)
                for si in 0..<2 { let g = b.armLastGeom[si]; let d = g.b - g.a; minElev = min(minElev, asinf(d.y / max(simd_length(d), 1e-4))) }
            }
            if b.expr.kind == .joyArc { happyFrames += 1 }
            if b.mouthOpen > 0.5 { smileFrames += 1 }
            w.sample(r)
        })
        let secs = r.t - 1.0          // (MotionRig settles for 1 s first)
        MotionLog.write("WIN move: \(String(format: "%.2f", secs)) s, \(airs) bounces, arms up \(armsUpFrames) of \(frames) frames")
        XCTAssertNil(b.idleState.kind, "it ends by itself")
        XCTAssertEqual(airs, BlobBrain.winHops, "four bounces")
        XCTAssertGreaterThan(secs, 2.5); XCTAssertLessThan(secs, 3.6)
        XCTAssertLessThan(maxTurn, 0.15, "he bounces on the spot facing the way he stood (was seen turning his back in the race)")
        MotionLog.write("WIN arms: lowest drawn tip elevation \(minElev) rad (jacks pose 0.95), apex \(maxApex) u, happy frames \(happyFrames) / \(frames), smile frames \(smileFrames)")
        XCTAssertGreaterThan(minElev, 0.7, "both drawn arm tips stay clearly above the shoulder line (> 40 degrees) through the bounces")
        XCTAssertGreaterThan(Float(happyFrames) / Float(frames), 0.9, "the happy arc face for the whole move")
        XCTAssertGreaterThan(Float(smileFrames) / Float(frames), 0.8, "an open smile")
        XCTAssertGreaterThan(maxW, 0.99, "the arms are fully up")
        XCTAssertGreaterThan(Float(armsUpFrames) / Float(frames), 0.6, "the arms stay up through the bounces")
        XCTAssertFalse(b.winCheer); XCTAssertEqual(b.armDirW, 0); XCTAssertEqual(b.gait.hopApex, 0.10, accuracy: 1e-6, "the plain hop's numbers are back")
        w.check("win celebration")
    }

    /// Low needs / a grumpy mood must not frown during the celebration, and his own faces come back after it.
    func testTheFaceIsHappyWithLowNeedsAndComesBack() {
        let r = rig(), b = r.brain
        b.idleMood = .grumpy
        r.run(0.5)
        XCTAssertTrue(b.winStart(r.sim))
        var frown = 0, frames = 0
        r.run(5, until: { b.idleState.kind == nil && r.t > 0.5 }, each: { frames += 1; if b.expr.kind != .joyArc || b.expr.raiseL < 0 || b.expr.tiltL < 0 { frown += 1 } })
        XCTAssertLessThanOrEqual(Float(frown) / Float(max(frames, 1)), 0.05, "no frown (a grumpy mood does not show) during the win: \(frown) of \(frames)")
        r.run(1.0)
        XCTAssertNotEqual(b.expr.kind, .joyArc, "the held happy arc does not stay on afterwards")
        XCTAssertFalse(b.winCheer)
    }

    /// The strongest jiggle level (2): the win is squash pulses on planted feet (a hop landing made the skin leash move a foot piece in the pull race), the same arms / face / length.
    func testTheWinAtTheStrongestJiggleIsFlatAndKeepsTheLeashQuiet() {
        for level in [0, 1, 2] {
            let r = rig(), b = r.brain
            r.skinner.jelly.levelOverride = level
            b.skinnerRef = r.skinner
            var hits = 0, worst: Float = 0, airs = 0
            Skinner.leashObserver = { _, pull, _ in hits += 1; worst = max(worst, pull) }
            defer { Skinner.leashObserver = nil }
            XCTAssertTrue(b.winStart(r.sim), "level \(level)")
            XCTAssertEqual(b.winFlat, level >= 2, "level \(level): only the strongest level is flat")
            var armsUp = 0, frames = 0
            r.run(6, until: { b.idleState.kind == nil && r.t > 0.5 }, each: {
                r.render()
                frames += 1
                if b.gait.phase == .air { airs += 1 }
                if b.armLiftNow > 0.95 && b.armDirW > 0.95 { armsUp += 1 }
            })
            MotionLog.write("WIN level \(level): flat \(b.winFlat), \(String(format: "%.2f", r.t - 1.0)) s, air frames \(airs), arms up \(armsUp) of \(frames), leash hits \(hits) worst \(worst * 100) cm")
            XCTAssertNil(b.idleState.kind, "level \(level): it ends by itself")
            XCTAssertEqual(hits, 0, "level \(level): the skin leash never moves a foot piece (worst \(worst * 100) cm)")
            if level >= 2 { XCTAssertEqual(airs, 0, "the strongest level does not hop") }
            else { XCTAssertGreaterThan(airs, 20, "levels 0 and 1 bounce") }
            XCTAssertGreaterThan(Float(armsUp) / Float(max(frames, 1)), 0.5, "level \(level): arms up")
            XCTAssertGreaterThan(r.t - 1.0, 2.4); XCTAssertLessThan(r.t - 1.0, 3.8)
        }
    }

    func testThePlainJoyIsUnchanged() {
        let r = rig(), b = r.brain
        XCTAssertTrue(b.idleStart(.joy, r.sim))
        XCTAssertEqual(b.idleState.reps, 1, "the ordinary jump for joy is one hop")
        XCTAssertFalse(b.winCheer)
        var airs = 0, wasAir = false
        r.run(4, until: { b.idleState.kind == nil && r.t > 0.5 }, each: { let air = b.gait.phase == .air; if air && !wasAir { airs += 1 }; wasAir = air })
        XCTAssertEqual(airs, 1)
        XCTAssertLessThan(r.t - 1.0, 1.6)
    }

    func testCuttingTheWinLeavesNothingBehind() {
        let r = rig(), b = r.brain
        XCTAssertTrue(b.winStart(r.sim))
        r.run(1.1)
        XCTAssertEqual(b.idleState.kind, .joy)
        b.abortAll(r.sim, r.skinner)
        XCTAssertNil(b.idleState.kind); XCTAssertFalse(b.winCheer); XCTAssertEqual(b.armDirW, 0)
        XCTAssertEqual(b.gait.hopApex, 0.10, accuracy: 1e-6)
        r.run(2)
        XCTAssertNil(b.idleState.kind, "he does not take it up again")
    }

    func testEveryFeatureKeepsItsBody() {
        for f in [JellyFeature.none, .spines, .daisy, .wings, .ears] {
            let r = rig(), b = r.brain
            b.feature = f
            XCTAssertTrue(b.winStart(r.sim), "\(f)")
            var w = SocialTests.Watch()
            r.run(5, until: { b.idleState.kind == nil && r.t > 0.5 }, each: { w.sample(r) })
            XCTAssertNil(b.idleState.kind, "\(f) finishes")
            w.check("win celebration \(f)")
        }
    }

    // MARK: the sound

    func testTheCheerIsPlayedPastTheGuardsEvenWithTheResultsSceneUp() {
        for scene in [MusicScene.none, .results, .race] {
            withHub(scene: scene) { fired in
                let r = rig(), b = r.brain
                XCTAssertTrue(b.winStart(r.sim))
                let yays = fired().filter { $0.hasPrefix("yay_jelly") }
                XCTAssertEqual(yays.count, 1, "scene \(scene): one cheer PLAYED, fired: \(fired())")
            }
        }
    }

    func testAMutedBrainStaysQuiet() {
        withHub { fired in
            let r = rig(), b = r.brain
            b.voiceMuted = true
            XCTAssertTrue(b.winStart(r.sim))
            XCTAssertTrue(fired().filter { $0.hasPrefix("yay_jelly") }.isEmpty)
        }
    }

    // MARK: the race

    /// A race to the results; `waddle` = the rivals' speed, `rate` = the player's taps per second. Returns what happened to each body.
    private func raceRun(waddle: Float, rate: Float, seed: UInt64) -> (place: Int?, finished: Bool, playerWin: Bool, rivalWin: Bool, played: Int, held: Bool) {
        var out: (Int?, Bool, Bool, Bool, Int, Bool) = (nil, false, false, false, 0, false)
        withHub(scene: .results) { fired in
            let room = RaceThreeTests.Room(count: 3)
            Self.keep.append(room)
            let care = room.care
            care.race.rivalSource = LocalRivalSourceFixed(waddle: waddle)
            care.race.autoRate = rate; care.race.autoReturnAfter = 60
            care.startRace(jelly: 0, seed: seed)
            var playerWin = false, rivalWin = false
            let book = care.raceBook
            room.run(150) {
                let all = room.actors + book.extra
                for (k, aid) in book.racers.enumerated() where all.indices.contains(aid) {
                    guard let b = all[aid].brain else { continue }
                    if b.winCheer || (b.idleState.kind == .joy && b.race.active) { if k == 0 { playerWin = true } else { rivalWin = true } }
                }
                return care.race.sim?.phase == .results && care.race.cardAge > 6
            }
            let s = care.race.sim
            out = (s?.playerPlace, s?.playerFinished ?? false, playerWin, rivalWin, fired().filter { $0.hasPrefix("yay_jelly") }.count, care.race.winHoldT != nil)
        }
        return out
    }

    func testRaceFirstPlaceStartsTheCelebrationForThePlayerOnly() {
        var r = raceRun(waddle: 0.0, rate: 14, seed: 11)
        for (w, rate, seed) in [(0.0 as Float, 14 as Float, 3 as UInt64), (0.0, 14, 5), (0.0, 20, 7)] where r.place != 1 { r = raceRun(waddle: w, rate: rate, seed: seed) }          // (the first draw whose player wins)
        XCTAssertEqual(r.place, 1); XCTAssertTrue(r.finished)
        XCTAssertTrue(r.playerWin, "the player's body celebrates at the results")
        XCTAssertFalse(r.rivalWin, "no rival does")
        XCTAssertEqual(r.played, 1, "one cheer PLAYED")
        XCTAssertTrue(r.held, "the results card was held for the win")
    }

    func testRaceOtherPlacesDoNothingNew() {
        let r = raceRun(waddle: 1.0, rate: 5, seed: 11)
        XCTAssertNotEqual(r.place, 1, "the rivals win this one")
        XCTAssertFalse(r.playerWin)
        XCTAssertFalse(r.rivalWin)
        XCTAssertEqual(r.played, 0, "no win cheer")
        XCTAssertFalse(r.held, "2nd / 3rd place: the card timing is exactly as today (no hold)")
    }

    /// First place holds the results card for the celebration (3 s cap after the finish, a tap brings it at once); nothing else changes.
    func testTheWinHoldRules() {
        let f = RaceFlow()
        XCTAssertFalse(f.holdsCard, "no first place: the card comes when the results are in, exactly as before")
        f.noteWinMove(active: true); f.noteWinMove(active: false)
        XCTAssertFalse(f.holdsCard, "a move that was never asked changes nothing")
        f.startWinHold()
        XCTAssertTrue(f.holdsCard)
        f.noteWinMove(active: false); XCTAssertTrue(f.holdsCard, "not started yet: still holding")
        f.noteWinMove(active: true); XCTAssertTrue(f.holdsCard, "running")
        f.noteWinMove(active: false); XCTAssertFalse(f.holdsCard, "the move ended: the card may come")
        f.startWinHold(); f.skipWinHold(); XCTAssertFalse(f.holdsCard, "a tap brings the card at once")
        f.startWinHold(); f.winHoldT = RaceFlow.winHoldMax - 0.01; XCTAssertTrue(f.holdsCard)
        f.winHoldT = RaceFlow.winHoldMax; XCTAssertFalse(f.holdsCard, "3.0 s after the finish at the latest")
    }

    func testTwoBodiesOverTheLineInOneTickTheEarlierInterpolatedTimeWins() {
        XCTAssertTrue(RaceSim.leadsAtFinish(player: 12.80, others: [13.7, nil]))
        XCTAssertFalse(RaceSim.leadsAtFinish(player: 12.80, others: [12.79, nil]), "a rival over the line in the same tick with the earlier time is first")
        XCTAssertFalse(RaceSim.leadsAtFinish(player: 12.80, others: [12.80, nil]), "an exact tie is not a clear first")
        XCTAssertTrue(RaceSim.leadsAtFinish(player: 12.80, others: [nil, nil]))
    }

    // MARK: the Jelly Show

    private func showResults(place: Int) -> (win: Bool, joy: Bool, played: Int) {
        var out = (false, false, 0)
        withHub(scene: .results) { fired in
            let room = RaceThreeTests.Room(count: 3)
            Self.keep.append(room)
            let care = room.care
            care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.cue = { _ in }
            care.startShow(jelly: 0, rank: .puddle, seed: 5)
            @MainActor func step() {
                for a in room.actors + room.park { if let b = a.brain { b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false) } }
                care.tickRace(room.actors, dt: 1 / 60); care.tickShow(room.actors, dt: 1 / 60)
                for a in room.actors { a.sim.step() }
            }
            for _ in 0..<360 { step(); if care.show.onStage { break } }
            XCTAssertTrue(care.show.onStage)
            care.showBook.trickSet = true          // (the Trick round was on: the first tick of the results snaps the player back to the podium spot, which cuts any move started before it)
            care.show.onResults(place)          // (what ShowFlow.settle sends when the results are in)
            var win = false, joy = false
            for _ in 0..<90 { step(); let b = room.actors[0].brain!; win = win || b.winCheer; joy = joy || b.idleState.kind == .joy }
            if place == 1 { let b = room.actors[0].brain!; XCTAssertTrue(b.winCheer && b.idleState.kind == .joy, "still celebrating 1.5 s after the snap") }
            out = (win, joy, fired().filter { $0.hasPrefix("yay_jelly") }.count)
        }
        return out
    }

    func testShowFirstPlaceCelebratesAndTheOthersKeepThePlainJoy() {
        let first = showResults(place: 1)
        XCTAssertTrue(first.win); XCTAssertTrue(first.joy); XCTAssertEqual(first.played, 1)
        for p in 2...4 {
            let o = showResults(place: p)
            XCTAssertFalse(o.win, "place \(p)"); XCTAssertTrue(o.joy, "place \(p): the plain jump for joy as before"); XCTAssertEqual(o.played, 0, "place \(p)")
        }
    }
}
