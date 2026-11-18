//
//  ShowDanceStepsTests.swift
//  The Jelly Show's Dance round is danced ON HIS FEET: a step on every beat of the song's grid (the owner: "he didn't make steps during the dance section").
//  Run in the test lab with the real stage rig (Room + the Show), a calm song (Puddle) and a lively song (Ocean), on songs of 24 and of 16 beats:
//    steps       at least one foot plant per two beats on average, both feet used (the step-touch is L R R L: no foot more than twice running);
//    timing      the plants are within 80 ms of a (half) beat for at least 80 % of the steps (the song's own clock);
//    stage       never sitting, the root stays within 0.3 u of where the dance began, he ends facing front;
//    plan        at least 3 different moves in a round, never the same one twice running, the lively songs add moves the calm ones do not have;
//    miss        a Slip never stops the stepping (no taps at all); a Perfect is a stomp on the next step.
//  (The lines marked PLAN use the plan's symbols: the "before" run of the base build drops them.)
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ShowDanceStepsTests: XCTestCase {
    struct Result {
        var plants: [(t: Double, side: Int, err: Double)] = []
        var beats = 0
        var drift: Float = 0
        var sat = false
        var yawEnd: Float = 1
        var phrases: [ShowDanceMove] = []          // PLAN
        var song = 0, rank = ShowRank.puddle
        var stomp = false
        var maxLift: Float = 0
        var span: Float = 0
        var presses: [(t: Double, foot: Int)] = []
    }

    private func ready(_ care: GameCare) { care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.cue = { _ in } }
    private func step(_ room: RaceThreeTests.Room) {
        for a in room.actors + room.park { if let b = a.brain { b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false) } }
        room.care.tickRace(room.actors, dt: 1 / 60)
        room.care.tickShow(room.actors, dt: 1 / 60)
    }
    static func seed(forSong n: Int) -> UInt64 { (1...400).map { UInt64($0) }.first { DanceSong.pick(seed: $0).song == n } ?? 1 }

    /// One Show to the end of its dance, polling only the body's feet and root: the same on the base build and with the steps.
    private func dance(rank: ShowRank, song: Int, auto: Bool, onHit: ((GameCare, Int) -> Void)? = nil) -> Result {
        let room = RaceThreeTests.Room(count: 1)
        RaceThreeTests.keep.append(room)
        let care = room.care
        ready(care)
        for b in ShowRank.allCases where b.index < rank.index { care.show.progress.record(rank: b, place: 1, theme: .bunnyPicnic, character: 0, burst: false, perfectDance: false, hatTrick: false) }
        care.show.progress.chosen = rank
        care.show.auto = auto
        care.startShow(jelly: 0, rank: rank, seed: Self.seed(forSong: song))
        XCTAssertEqual(care.show.rank, rank, "the rank is unlocked and chosen")
        var r = Result(); r.song = care.show.danceSong.song; r.rank = rank
        XCTAssertEqual(r.song, song)
        let b = room.actors[0].brain!
        for _ in 0..<(60 * 40) { step(room); if care.show.onStage { break } }
        XCTAssertTrue(care.show.onStage)
        var started = false, start = SIMD2<Float>.zero, swinging = false, frames = 0, minX: Float = .infinity, maxX = -Float.infinity
        let origTap = care.show.onTap
        care.show.onTap = { foot in if care.show.beat == .dancing { r.presses.append((care.show.danceNow(), foot)) }; origTap(foot) }
        let g = care.show.danceSong.grid
        for _ in 0..<(60 * 60) {
            step(room)
            if !started, care.show.beat == .dancing { started = true; start = b.position }
            if started, care.show.beat == .dancing {
                frames += 1
                let now = care.show.danceNow()
                if swinging, !b.feet.swinging {
                    let k = ((now - g.firstBeat) / (g.period / 2)).rounded()
                    r.plants.append((now, b.feet.side, now - (g.firstBeat + k * g.period / 2)))
                }
                swinging = b.feet.swinging
                r.drift = max(r.drift, simd_distance(b.position, start))
                r.maxLift = max(r.maxLift, b.feet.state(b.feet.side).h)
                minX = min(minX, b.position.x); maxX = max(maxX, b.position.x); r.span = maxX - minX
                if [IdleKind.sit, .sway, .slump, .decorSit].contains(b.idleState.kind) { r.sat = true }
                onHit?(care, frames)
                if let ph = care.showBook.danceRun?.phrases { r.phrases = ph }          // PLAN
            }
            if started, care.show.beat == .danced { break }
        }
        XCTAssertTrue(started, "the dance began")
        for _ in 0..<90 { step(room) }          // (the dance is over: he settles)
        r.beats = care.show.danceSong.lastBeat
        r.yawEnd = abs(wrapAngle(b.yaw))
        if [IdleKind.sit, .sway, .slump, .decorSit].contains(b.idleState.kind) { r.sat = true }
        return r
    }

    private func report(_ name: String, _ r: Result) -> String {
        let within = r.plants.filter { abs($0.err) <= 0.08 }.count
        var run = 1, maxRun = 1
        for i in 1..<max(r.plants.count, 1) where r.plants.count > 1 { if r.plants[i].side == r.plants[i - 1].side { run += 1; maxRun = max(maxRun, run) } else { run = 1 } }
        let line = String(format: "%@: song %d (%d beats) steps %d (%.2f per beat) within 80 ms %d (%.0f %%) max same-foot run %d drift %.3f u sat %@ end yaw %.2f rad",
                          name, r.song, r.beats, r.plants.count, Double(r.plants.count) / Double(max(r.beats, 1)), within, 100 * Double(within) / Double(max(r.plants.count, 1)), maxRun, r.drift, r.sat ? "YES" : "no", r.yawEnd)
        print("SHOWDANCE " + line)
        return line
    }

    private func check(_ name: String, _ r: Result) {
        _ = report(name, r)
        XCTAssertGreaterThanOrEqual(Double(r.plants.count), Double(r.beats) / 2, "\(name): fewer than one foot plant per two beats (\(r.plants.count) plants in \(r.beats) beats)")
        let within = r.plants.filter { abs($0.err) <= 0.08 }.count
        XCTAssertGreaterThanOrEqual(Double(within), 0.8 * Double(max(r.plants.count, 1)), "\(name): only \(within) of \(r.plants.count) plants are within 80 ms of a (half) beat")
        XCTAssertGreaterThan(r.plants.count, 0, "\(name): no steps at all")
        XCTAssertEqual(Set(r.plants.map(\.side)).count, 2, "\(name): both feet step")
        var run = 1
        for i in 1..<max(r.plants.count, 1) where r.plants.count > 1 {
            if r.plants[i].side == r.plants[i - 1].side { run += 1 } else { run = 1 }
            XCTAssertLessThanOrEqual(run, 2, "\(name): the same foot stepped \(run) times running at plant \(i)")
        }
        XCTAssertFalse(r.sat, "\(name): he sat down")
        XCTAssertGreaterThan(r.span, 0.12, "\(name): the step-touch should sway clearly side to side (span \(r.span) u)")
        XCTAssertGreaterThan(r.maxLift, 0.07, "\(name): the feet barely leave the floor (\(r.maxLift) u)")
        XCTAssertLessThan(r.drift, 0.3, "\(name): he drifted \(r.drift) u off his mark")
        XCTAssertLessThan(r.yawEnd, 0.25, "\(name): he does not end facing front (\(r.yawEnd) rad)")
    }

    /// Every L / R press makes his foot on that side step (lift and land) within a third of a second, whether it was on time or not (auto play presses a little late, skips some).
    func testLPlantsHisOwnLeftFoot() {
        XCTAssertEqual(ShowDancePlan.side(forFoot: 0), 1, "L (0) is his own left foot: foot index 1, drawn on the screen's right as he faces the camera")
        XCTAssertEqual(ShowDancePlan.side(forFoot: 1), 0, "R (1) is his own right foot: foot index 0, drawn on the screen's left")
    }
    func testEveryPressStepsThatFoot() {
        for (rank, song) in [(ShowRank.puddle, 1), (.ocean, 2), (.puddle, 4)] {
            let r = dance(rank: rank, song: song, auto: true)
            XCTAssertGreaterThanOrEqual(r.presses.count, 8, "at least 8 presses")
            for p in r.presses {
                let want = ShowDancePlan.side(forFoot: p.foot)
                XCTAssertTrue(r.plants.contains { $0.side == want && $0.t > p.t - 0.35 && $0.t < p.t + 0.4 }, "\(rank) song \(song): the press of foot \(p.foot) at \(p.t) was not answered by a step of side \(want)")
            }
        }
    }
    func testCalmSong24Beats() { check("calm / Puddle", dance(rank: .puddle, song: 1, auto: true)) }
    func testCalmSong16Beats() { check("calm / Puddle", dance(rank: .puddle, song: 4, auto: true)) }
    func testLivelySong24Beats() { check("lively / Ocean", dance(rank: .ocean, song: 2, auto: true)) }
    func testLivelySong16Beats() { check("lively / Ocean", dance(rank: .ocean, song: 4, auto: true)) }
    func testPondAndLagoonTiers() {
        check("calm / Pond", dance(rank: .pond, song: 3, auto: true))
        check("lively / Lagoon", dance(rank: .lagoon, song: 3, auto: true))
    }
    /// No taps at all: every prompt is a Slip (the wobble), and the stepping never stops.
    func testMissesNeverStopTheSteps() {
        check("no taps / Puddle", dance(rank: .puddle, song: 1, auto: false))
        check("no taps / Ocean", dance(rank: .ocean, song: 4, auto: false))
    }

    // PLAN-BEGIN
    func testPlanHasVarietyAndNeverRepeats() {
        for rank in ShowRank.allCases {
            for song in DanceSong.all {
                for seed in UInt64(1)...12 {
                    let p = ShowDancePlan.phrases(rank: rank, lastBeat: song.lastBeat, seed: seed)
                    XCTAssertEqual(p.count, song.lastBeat / 4, "one phrase per bar")
                    XCTAssertGreaterThanOrEqual(Set(p).count, 3, "\(rank) song \(song.song) seed \(seed): at least 3 different moves")
                    for i in 1..<p.count { XCTAssertNotEqual(p[i], p[i - 1], "\(rank) song \(song.song) seed \(seed): \(p[i]) twice running at bar \(i)") }
                    XCTAssertEqual(p.first, .stepTouch); XCTAssertEqual(p.last, .stepTouch, "he comes back to the base step and ends with the feet together")
                    let pool = Set(ShowDanceMove.pool(lively: ShowDancePlan.lively(rank)))
                    for m in p where m != .stepTouch { XCTAssertTrue(pool.contains(m), "\(rank): \(m) is not in its tier's pool") }
                }
            }
        }
        XCTAssertFalse(Set(ShowDanceMove.pool(lively: false)).contains(.kickOut), "the calm songs have the gentle moves only")
        XCTAssertTrue(Set(ShowDanceMove.pool(lively: true)).isSuperset(of: Set(ShowDanceMove.pool(lively: false)).union([.kickOut, .hopStep])), "the lively songs add the energetic ones")
    }
    func testRoundShowsAtLeastThreeMovesNoRepeat() {
        for (rank, song) in [(ShowRank.puddle, 1), (.puddle, 4), (.ocean, 2), (.ocean, 4)] {
            let r = dance(rank: rank, song: song, auto: true)
            XCTAssertGreaterThanOrEqual(Set(r.phrases).count, 3, "\(rank) song \(song): at least 3 distinct moves in the round")
            for i in 1..<max(r.phrases.count, 1) where r.phrases.count > 1 { XCTAssertNotEqual(r.phrases[i], r.phrases[i - 1]) }
        }
    }
    /// A Perfect is a stomp on the next step (a higher foot lift); a Miss does not change the stepping.
    func testPerfectIsAStomp() {
        var peak: Float = 0, plain: Float = 0
        _ = dance(rank: .puddle, song: 1, auto: false) { care, f in
            guard let b = care.showBook.actors.first?.brain else { return }
            let h = b.feet.state(b.feet.side).h
            // (song 1: 0.5 s beats, the step for beat n starts at 0.5 n - 0.37 s: the step of beat 2 is plain, the Perfect at frame 45 lands on the step of beat 3)
            if f >= 40, f < 66 { plain = max(plain, h) }
            if f == 45 { care.show.onHit(.perfect) }
            if f >= 70, f < 100 { peak = max(peak, h) }
        }
        XCTAssertGreaterThan(plain, 0.03, "the plain step lifts the foot")
        XCTAssertGreaterThan(peak, plain * 1.4, "the Perfect's step is lifted higher (stomp \(peak) vs \(plain))")
    }
    // PLAN-END
}
