//
//  ShowTurnOrderTests.swift
//  The Jelly Show's Trick round, 2026-11-17 (the owner: "my Jelmiko went three times and the other three went once, they should all go during a round"): after each of the player's
//  three tricks ALL THREE rivals perform on the stage, in a fixed order, one at a time; the totals and placings are the same as with one rival per turn (only the order on the stage
//  changed); a rival's turn is brisk; and the camera / marks give the performer the screen (large, the others behind it, nobody on top of anybody).
//

import XCTest
import simd
import SwiftUI
@testable import BobV1

@MainActor
final class ShowTurnOrderTests: XCTestCase {
    private func input() -> ShowPlayerInput {
        var p = ShowPlayerInput(name: "Bob")
        for t in WearTag.allCases { p.condition[t] = 0.5 }
        p.glow = 0.8; p.dirt = 0; p.dance = .sway
        p.tricks = [.sit: 0.9, .jacks: 0.9, .flip: 0.9]; p.care = 1
        return p
    }
    private final class Log { var a: [String] = [] }
    private func flowAtTrick(_ log: Log, perTurn: Int, day: Int = 20261021, seed: UInt64 = 3) -> ShowFlow {
        let f = ShowFlow(); f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.cue = { _ in }
        f.entrantsPerTurn = perTurn
        f.onPerform = { t, _ in log.a.append("P:\(t.rawValue)") }
        f.onRival = { c in
            switch c {
            case .playerAside(let a): log.a.append("aside:\(a)")
            case .walkIn(let i): log.a.append("in:\(i)")
            case .perform(let i, _, _): log.a.append("R\(i)")
            case .walkOut(let i): log.a.append("out:\(i)")
            case .snap: log.a.append("snap")
            case .enter: log.a.append("enter")
            }
        }
        f.begin(playerID: 0, name: "Bob", character: 0, input: input(), rank: .puddle, dayKey: day, bodies: 1, seed: seed)
        run(f, seconds: 2) { f.phase == .stage }
        f.finishLook()
        run(f, seconds: 6) { f.beat == .dancing }
        run(f, seconds: 30) { f.beat == .danced }
        f.finishDance()
        run(f, seconds: 6) { !f.trickEntering }
        return f
    }
    private func run(_ f: ShowFlow, seconds: Float, until: () -> Bool = { false }) {
        for _ in 0..<Int(seconds * 60) { f.tick(dt: 1 / 60); if until() { return } }
    }
    private func playAllThree(_ f: ShowFlow) {
        for t in [VoiceTrick.sit, .jacks, .flip] {
            f.pick(t)
            run(f, seconds: 5) { f.trickStage == .rivals }
            run(f, seconds: 90) { f.trickStage == .pick }
        }
    }

    /// The header pips and the turn pills read the SAME turn index at every step of a whole Trick round (never two counters), the kicker has no turn count, and
    /// the turn only ever moves forward 0 -> 1 -> 2, ending with every pip filled.
    func testPipsAndPillsAgreeAtEveryStepOfTheTrickRound() {
        let f = flowAtTrick(Log(), perTurn: 3)
        XCTAssertEqual(TurnPips.of(f).kicker, "ROUND 3 OF 3")
        var seen: [Int] = [], last = -1
        func check(_ where_: String) {
            let pills = (0..<3).filter { f.isTrickTurnNow($0) }
            XCTAssertLessThanOrEqual(pills.count, 1, "one pill at most is now: \(where_)")
            let pips = TurnPips.of(f)
            XCTAssertEqual(pips.current, pills.first ?? 3, "pips follow the pill: \(where_) stage \(f.trickStage)")
            XCTAssertEqual(pips.used, pills.first ?? 3, where_)
            if let k = pills.first {
                XCTAssertGreaterThanOrEqual(k, last, "never goes back: \(where_)"); last = k
                if seen.last != k { seen.append(k) }
            } else {
                XCTAssertTrue(f.sim?.tricksDone ?? false, "no turn now only when the round is over: \(where_)")
            }
        }
        for t in [VoiceTrick.sit, .jacks, .flip] {
            check("before pick")
            f.pick(t)
            var sawRivals = false
            for _ in 0..<(95 * 60) {
                f.tick(dt: 1 / 60); check("tick")
                if f.trickStage == .rivals { sawRivals = true }
                if sawRivals, f.trickStage == .pick { break }
            }
            XCTAssertTrue(sawRivals, "the rivals played after \(t)")
        }
        check("end")
        XCTAssertEqual(seen, [0, 1, 2])
        XCTAssertEqual(TurnPips.of(f).current, 3, "all filled when the round is over")
    }

    /// The switch is at three, and after each of his tricks every rival goes once, in the same order, one at a time (the others wait).
    func testAllThreeRivalsPerformAfterEachPlayerTrick() {
        XCTAssertEqual(ShowFlow.entrantsPerTurn, 3)
        let log = Log()
        let f = flowAtTrick(log, perTurn: ShowFlow.entrantsPerTurn)
        for (turn, t) in [VoiceTrick.sit, .jacks, .flip].enumerated() {
            log.a.removeAll()
            f.pick(t)
            run(f, seconds: 5) { f.trickStage == .rivals }
            XCTAssertEqual(f.rivalRound, turn)
            run(f, seconds: 90) { f.trickStage == .pick }
            XCTAssertEqual(log.a, ["P:\(t.rawValue)", "aside:true", "in:0", "R0", "out:0", "in:1", "R1", "out:1", "in:2", "R2", "out:2", "aside:false"], "turn \(turn + 1)")
        }
        XCTAssertEqual(f.sim!.round, .results)
    }

    /// Only the order on the stage changed: the same seed, the same three tricks give the same rival tricks, totals and placings with one rival per turn or with all three.
    func testTotalsAndPlacingsDoNotDependOnWhoGoesWhen() {
        for (day, seed) in [(20261021, UInt64(3)), (20261105, UInt64(9))] {
            let one = flowAtTrick(Log(), perTurn: 1, day: day, seed: seed), all = flowAtTrick(Log(), perTurn: 3, day: day, seed: seed)
            playAllThree(one); playAllThree(all)
            XCTAssertEqual(one.sim!.round, .results); XCTAssertEqual(all.sim!.round, .results)
            XCTAssertEqual(one.sim!.entrants, all.sim!.entrants, "totals and placings (day \(day))")
            XCTAssertEqual(one.sim!.rivalTurns, all.sim!.rivalTurns, "the same tricks (day \(day))")
            XCTAssertEqual(one.sim!.playerScores, all.sim!.playerScores)
            XCTAssertEqual(one.sim!.entrants.map(\.place), all.sim!.entrants.map(\.place))
        }
    }

    /// The scoreboard strip counts only the turns already shown: his own as he takes them, an entrant's once she has performed, all of them after Skip; at the end it is the Results' Trick score.
    func testStripPointsCountOnlyShownTurns() {
        let f = flowAtTrick(Log(), perTurn: 3)
        let s0 = f.sim!
        for i in 0..<3 { XCTAssertEqual(f.rivalTrickPoints(i), 0) }
        f.pick(.sit)
        for i in 0..<3 { XCTAssertEqual(f.rivalTrickPoints(i), 0, "her turn is rolled but not shown yet") }
        run(f, seconds: 5) { f.trickStage == .rivals }
        run(f, seconds: 10) { f.rivalStep == .perform }
        let first = f.rivalTurn!
        XCTAssertEqual(f.rivalTrickPoints(first), f.sim!.rivalTurns[first][0].points)
        for i in 0..<3 where i != first { XCTAssertEqual(f.rivalTrickPoints(i), 0) }
        f.skipRivals()
        for i in 0..<3 { XCTAssertEqual(f.rivalTrickPoints(i), f.sim!.rivalTurns[i][0].points, "Skip settles the rest") }
        XCTAssertEqual(f.playerTrickPoints, f.sim!.turns[0].points)
        _ = s0
        f.pick(.jacks); run(f, seconds: 5) { f.trickStage == .rivals }; f.skipRivals()
        f.pick(.flip); run(f, seconds: 5) { f.trickStage == .rivals }; f.skipRivals()
        let s = f.sim!
        for i in 0..<3 { XCTAssertEqual(f.rivalTrickPoints(i), Int(s.rivalScores(i).trick) - (s.rivals[i].burst ? ShowScoring.burstPoints : 0)) }
        XCTAssertEqual(f.playerTrickPoints, Int(s.playerScores.trick))
    }

    /// With a walk of about a second each way (the real pace of the stage walk), an entrant's turn is about 3 s and the three entrants, his step aside and back included, take 10 to 13 s.
    func testRoundLengthWithWalksOfAboutASecond() {
        let f = flowAtTrick(Log(), perTurn: 3)
        var clock: Float = 0, cueAt: [Int: Float] = [:]
        f.onRival = { c in
            switch c {
            case .walkIn(let i): cueAt[i] = clock
            case .walkOut(let i): cueAt[10 + i] = clock
            case .playerAside(let a): cueAt[a ? 20 : 21] = clock
            default: break
            }
        }
        f.rivalReady = { who, centre in
            guard let who else { return clock - (cueAt[centre ? 21 : 20] ?? 0) >= 1.3 }
            return clock - (cueAt[centre ? who : 10 + who] ?? 0) >= 0.95
        }
        f.pick(.sit)
        run(f, seconds: 5) { f.trickStage == .rivals }
        var t = 0, perform: [Float] = [], last: ShowFlow.RivalStep?
        while f.trickStage == .rivals, t < 60 * 40 {
            clock += 1 / 60; f.tick(dt: 1 / 60); t += 1
            if f.rivalStep != last { last = f.rivalStep; if last == .perform { perform.append(Float(t) / 60) } }
        }
        let total = Float(t) / 60
        print("[ShowTurnOrder] with 1 s walks: performs at", perform, "round", total)
        XCTAssertEqual(perform.count, 3)
        XCTAssertGreaterThan(total, 8); XCTAssertLessThan(total, 13.5, "three entrants and his step aside and back: about 12 s")
        for k in 1..<perform.count { XCTAssertLessThan(perform[k] - perform[k - 1], 4.0, "an entrant's turn is about 3 s") }
    }

    // MARK: real bodies: how long a turn takes, and that nobody walks through anybody

    func testRivalTurnsAreBriskAndNobodyOverlaps() {
        let room = RaceThreeTests.Room(count: 1)
        RaceThreeTests.keep.append(room)
        let care = room.care
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.cue = { _ in }
        func step() {
            for a in room.actors + room.park { if let b = a.brain { b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false) } }
            care.tickRace(room.actors, dt: 1 / 60)
            care.tickShow(room.actors, dt: 1 / 60)
        }
        care.startShow(jelly: 0, rank: .puddle, seed: 5)
        for _ in 0..<(6 * 60) { step(); if care.show.onStage { break } }
        XCTAssertTrue(care.show.onStage)
        care.show.auto = true
        let book = care.showBook
        var t = 0.0, t0 = -1.0
        var turnStart: [Int: Double] = [:], turnLen: [Double] = [], aroundLen: [Double] = []
        var minGap: Float = 99
        var minWhere = ""
        var round = -1
        var lastStep = ShowFlow.RivalStep.playerBack, diag: [String] = []
        var cur: Int? = nil, curT = 0.0
        for _ in 0..<(400 * 60) {
            step(); t += 1.0 / 60
            guard care.show.round == .trick || care.show.round == .results else { continue }
            if care.show.trickStage == .rivals {
                if care.show.rivalRound != round { round = care.show.rivalRound; t0 = t }
                let now = care.show.rivalTurn
                if now != cur {
                    if let c = cur, let st = turnStart[c * 10 + round] { turnLen.append(t - st); _ = st }
                    cur = now; curT = t
                    if let n = now { turnStart[n * 10 + round] = t }
                }
                let all = [room.actors[0]] + book.extra
                if care.show.rivalStep != lastStep { lastStep = care.show.rivalStep; if lastStep == .perform, let n = care.show.rivalTurn, let id = care.showRivalBody(n), let body = book.extra.first(where: { $0.id == id }) { diag.append(String(format: "r%d perform at %.1f s, %.2f from the middle", n, t - t0, simd_distance(body.floor, ShowStage.playerSpot))) } }
                for i in all.indices { for j in all.indices where j > i {
                    let g = simd_distance(all[i].floor, all[j].floor)
                    if g < minGap { minGap = g; minWhere = "bodies \(all[i].id) \(all[i].floor) and \(all[j].floor) \(all[j].id) at \(String(format: "%.1f", t - t0)) s, step \(care.show.rivalStep), turn \(String(describing: care.show.rivalTurn))" }
                } }
            } else if t0 >= 0 {
                aroundLen.append(t - t0); t0 = -1; cur = nil
            }
            if care.show.round == .results && care.show.trickStage == .pick { break }
        }
        _ = curT
        print("[ShowTurnOrder] diag", diag); print("[ShowTurnOrder] per-rival turn lengths (s):", turnLen.map { String(format: "%.1f", $0) }, "rivals' part per round:", aroundLen.map { String(format: "%.1f", $0) }, "min gap:", minGap, minWhere)
        XCTAssertEqual(aroundLen.count, 3, "three rounds of entrants")
        // (the headless room's bodies do not walk on their own, so the flow's arrival time-outs set the lengths here: the real pace is `testRoundLengthWithWalksOfAboutASecond`)
        XCTAssertGreaterThan(minGap, 0.9, "no two bodies ever overlap while the entrants swap at the middle")
    }

    // MARK: the screen: the performer is the hero, the marks stay apart

    /// The performer on the middle mark is big (phone 14%+ of the screen height, iPad 17%+), his feet are above the trick menu and his top under the header; the waiting entrants stand on the back row:
    /// each whole body is INSIDE the picture (never half cut by the edge), their faces are clear above the performer's head, and rival 2 is wholly OFF the picture; marks are 1.5+ apart.
    func testPerformerIsLargeAndTheWaitingRowIsWhollyInOrWhollyOut() {
        func extent(_ spot: SIMD2<Float>, _ f: ShowFrame, _ size: CGSize) -> (l: CGFloat, r: CGFloat, face: CGFloat) {
            let c = StageProject.point(spot, y: BobShape.H * 0.5, frame: f, size: size)
            let e = StageProject.point(SIMD2(spot.x + BobShape.R * 1.25, spot.y), y: BobShape.H * 0.5, frame: f, size: size)          // (the body and its arms)
            let face = StageProject.point(spot, y: BobShape.H * 0.65, frame: f, size: size)
            return (c.x - abs(e.x - c.x), c.x + abs(e.x - c.x), face.y)
        }
        for (name, size, pad) in [("17e", CGSize(width: 390, height: 844), false), ("17 Pro Max", CGSize(width: 440, height: 956), false), ("small phone", CGSize(width: 375, height: 812), false), ("iPad", CGSize(width: 820, height: 1180), true)] {
            let f = ShowFrame.trick(pad: pad)
            let foot = StageProject.point(ShowStage.playerSpot, y: 0, frame: f, size: size), top = StageProject.point(ShowStage.playerSpot, y: BobShape.H, frame: f, size: size)
            XCTAssertGreaterThan((foot.y - top.y) / size.height, pad ? 0.17 : 0.13, "\(name): the performer is big")
            XCTAssertLessThan(foot.y / size.height, 0.58, "\(name): his feet are above the menu")
            XCTAssertGreaterThan(top.y / size.height, 0.2, "\(name): his top is under the header")
            for spot in [ShowStage.rivalRest(0), ShowStage.rivalRest(1), ShowStage.playerAside] {
                let e = extent(spot, f, size)
                XCTAssertGreaterThanOrEqual(e.l, 0, "\(name): a waiting body is cut by the left edge"); XCTAssertLessThanOrEqual(e.r, size.width, "\(name): a waiting body is cut by the right edge")
                XCTAssertLessThan(e.face, top.y + 4, "\(name): a waiting face is above the performer's head, never behind her")
            }
            let off = extent(ShowStage.rivalRest(2), f, size)
            XCTAssertTrue(off.l >= size.width || off.r <= 0, "\(name): rival 2 is wholly off the picture")
        }
        // a phone / tablet on its side: the same, in the left part (the chrome column is on the right), rival 2 off to the left
        for (name, size, pad) in [("17e on its side", CGSize(width: 844, height: 390), false), ("iPad on its side", CGSize(width: 1180, height: 820), true)] {
            let f = ShowFrame.trick(pad: pad)
            for spot in [ShowStage.rivalRest(0, sideways: true), ShowStage.rivalRest(1, sideways: true), ShowStage.playerAside] {
                let e = extent(spot, f, size)
                XCTAssertGreaterThanOrEqual(e.l, 0, "\(name)"); XCTAssertLessThanOrEqual(e.r, size.width * (pad ? 0.55 : 0.52), "\(name): a waiting body is not under the chrome column")
            }
            let off = extent(ShowStage.rivalRest(2, sideways: true), f, size)
            XCTAssertLessThanOrEqual(off.r, 0, "\(name): rival 2 is off to the left")
        }
        let marks = [ShowStage.playerSpot, ShowStage.playerAside, ShowStage.rivalRest(0), ShowStage.rivalRest(1), ShowStage.rivalRest(2), ShowStage.rivalRest(2, sideways: true)]
        for i in marks.indices { for j in marks.indices where j > i && !(i == 4 && j == 5) { XCTAssertGreaterThan(simd_distance(marks[i], marks[j]), 1.5) } }
    }
}
