//
//  VolleyFixesTests.swift
//  Three fixes to Jelly Volleyball (2026-11-17) and the species-signature fix for its borrowed bodies:
//   1. the serve ball rests ON the server's head (skin gap ~0, on the hat when one is worn), travels to the next server by an arc, never hangs in the air;
//   2. the computer is gentler early: the win rate of a scripted "ordinary" and a scripted "skilled" player per level, before (`VolleyTuning.old`) and after;
//   3. a double tap on the teammate switches control in every match state (the gesture's timing and hit-testing are VolleyDoubleTap / VolleyPick), a single tap does nothing, auto switch still works;
//   4. the borrowed bodies (opponents, a Park friend) show their species signature (spikes, wings) every step.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class VolleyFixesTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    // MARK: the court (real GameCare, real soft bodies)

    @MainActor private struct Court {
        let room: RaceThreeTests.Room
        var care: GameCare { room.care }
        var hat: WearLook?
        func step() {
            room.step()
            if let hat {
                let a = room.actors[0], dt = a.sim.stepDt
                care.wardrobe.body = WearBody.shared
                care.wardrobe.tick(id: 0, brain: a.brain!, sim: a.sim, outfit: [.head: hat], role: .none, hideAll: false, dt: dt)
                care.wardrobe.syncCarry(0, sim: a.sim)
                _ = care.wardrobe.frame(theme: RoomTheme(), time: 0.4) { _ in nil }
            }
            care.tickVolley(room.actors, dt: room.actors[0].sim.stepDt)
        }
        func run(_ n: Int) { for _ in 0..<n { step() } }
        var sim: VolleySim { care.volley.sim! }
        /// The highest point of body `i`'s soft skin (every particle).
        func skinTop(_ i: Int) -> Float {
            let sb = care.volleyWork.players[i].sim
            var t = -Float.infinity
            for p in 0..<sb.n { t = max(t, sb.x[3 * p + 1]) }
            return t
        }
        /// The top of the hat drawn for body 0 this tick (the highest vertex of the wardrobe's mesh).
        func hatTopDrawn() -> Float? {
            let f = care.wardrobe.frame(theme: RoomTheme(), time: 0.4) { _ in nil }
            return f.opaque.vertices.map { $0.pos.y }.max()
        }
    }

    private func court(seed: UInt64 = 5, hat: WearLook? = nil, feature: JellyFeature? = nil, until: ((Court) -> Bool)? = nil) -> Court {
        let room = RaceThreeTests.Room(count: 2)
        Self.keep.append(room)
        var c = Court(room: room)
        c.hat = hat
        if let feature { room.actors[0].brain?.feature = feature }
        c.care.startVolley(jelly: 0, mode: .match(.sandcastle), seed: seed)
        var guardTicks = 0
        while !(c.care.volley.live && c.care.volley.sim?.phase == .serveWait) && guardTicks < 60 * 40 { c.step(); guardTicks += 1 }
        XCTAssertTrue(c.care.volley.live, "the match is on")
        return c
    }

    /// The ball sits on the crown: its bottom within 0.02 of the head top, never sunk into it.
    private func assertOnHead(_ c: Court, server i: Int, top: Float, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let s = c.sim
        let bottom = s.ball.pos.y - VolleyTuning.ballR
        XCTAssertLessThanOrEqual(abs(bottom - top), 0.02, "\(what): ball bottom \(bottom) vs head top \(top)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(bottom, top - 0.002, "\(what): the ball sank into the head (\(bottom) < \(top))", file: file, line: line)
        XCTAssertLessThan(abs(s.ball.z - c.care.volleyWork.players[i].sim.centroid().z), 0.3, "\(what): over the head in depth", file: file, line: line)
    }

    // MARK: 1 · the ball before a serve

    func testBallRestsOnTheHeadOfEverySpecies() {
        for f in [JellyFeature.none, .spines, .daisy, .wings, .ears] {
            let c = court(feature: f)
            XCTAssertEqual(c.sim.servingPlayer, 0)
            for k in 0..<90 {
                c.step()
                if c.sim.phase == .serveWait, c.sim.ballOnHead { assertOnHead(c, server: 0, top: c.skinTop(0), "\(f) tick \(k)") }
            }
            XCTAssertTrue(c.sim.ballOnHead, "\(f): resting on the head in the serve wait")
        }
    }

    func testBallRestsOnTheHat() {
        for hat in [WearLook.tophat, .beanieHoney, .partyHat, .bucketHat] {
            let c = court(hat: hat)
            c.run(40)          // the hat pops in
            var seen = 0
            for k in 0..<60 {
                c.step()
                guard c.sim.ballOnHead, let top = c.hatTopDrawn() else { continue }
                seen += 1
                assertOnHead(c, server: 0, top: top, "\(hat) tick \(k)")
                XCTAssertGreaterThan(top, c.skinTop(0) - 0.01, "\(hat): the hat is at least as high as the skin")
            }
            XCTAssertGreaterThan(seen, 30, "\(hat): the hat was drawn and measured")
        }
    }

    func testBallRestsOnTheServersHeadForBothSidesAndTravelsThereByAnArc() {
        let c = court()
        c.run(30)
        var ok = 0
        // a point for each side in turn: the next server (theirs, then ours) gets the ball by a short arc, and it rests on his head
        for team in [1, 0, 1] {
            let before = c.sim.score
            c.care.volley.sim?.debugRally(possession: team, touches: 1)
            c.care.volley.sim?.forcePoint(team: team)
            XCTAssertEqual(c.sim.score[team], before[team] + 1)
            if c.sim.winner != nil { break }
            var prev: SIMD3<Float>?
            var maxStep: Float = 0, maxRise: Float = 0, arcTicks = 0
            var start: SIMD3<Float>?
            var guardTicks = 0
            while c.sim.phase != .serveWait, guardTicks < 60 * 6 {
                c.step(); guardTicks += 1
                let b = c.sim.ball
                let p = SIMD3<Float>(b.pos.x, b.pos.y, b.z)
                if c.sim.carry != nil {
                    arcTicks += 1
                    if start == nil { start = p }
                    if let prev { maxStep = max(maxStep, simd_length(p - prev)) }
                    maxRise = max(maxRise, b.pos.y - max(start!.y, 0.4))
                }
                prev = p
            }
            XCTAssertGreaterThan(arcTicks, 20, "the ball travels to the next server (an arc of \(arcTicks) steps)")
            XCTAssertLessThan(maxStep, 0.3, "no jump: the biggest step of the ball is \(maxStep)")
            XCTAssertGreaterThan(maxRise, 0.4, "it is a lob (rose \(maxRise)), not a slide")
            // the arc has landed by the time the serve wait begins, on the new server's head
            let i = c.sim.servingPlayer
            XCTAssertEqual(c.sim.phase, .serveWait)
            XCTAssertTrue(c.sim.ballOnHead, "landed on the head of server \(i)")
            c.run(20)
            assertOnHead(c, server: i, top: c.skinTop(i), "after the arc, server \(i)")
            ok += 1
        }
        XCTAssertGreaterThanOrEqual(ok, 2)
    }

    func testTheBallNeverHangsInTheAirWhileIdle() {
        let c = court()
        var hangs = 0, idleTicks = 0
        func watch(_ ticks: Int) {
            for _ in 0..<ticks {
                c.step()
                let s = c.sim
                let airborne = s.ball.pos.y > VolleyTuning.ballR + 0.05
                switch s.phase {
                case .intro, .serveWait: idleTicks += 1; if airborne, !s.ballOnHead, s.carry == nil { hangs += 1 }
                case .over: idleTicks += 1; if airborne, s.phaseT > 3 { hangs += 1 }          // (the ball settles on the sand)
                case .pointPause: idleTicks += 1          // (falls to the sand, then travels to the next server by the arc: see the arc test)
                case .rally: break
                }
            }
        }
        watch(60)
        for team in [1, 1, 0, 1] where c.sim.phase != .over {          // points to the end of the match (a fault, a drop: the reason does not matter here)
            c.care.volley.sim?.debugRally(possession: team, touches: 1)
            c.care.volley.sim?.forcePoint(team: team)
            watch(60 * 3)
        }
        c.run(60 * 5)
        XCTAssertEqual(c.sim.phase, .over)
        XCTAssertLessThanOrEqual(c.sim.ball.pos.y, VolleyTuning.ballR + 0.05, "at the match end the ball lies on the sand: \(c.sim.ball.pos.y)")
        XCTAssertEqual(hangs, 0, "the ball hung in mid-air for \(hangs) of \(idleTicks) idle ticks")
    }

    func testTheFirstFrameBeforeTheMatchHasTheBallOnTheServersHead() {
        let s = VolleySim(mode: .match(.sandcastle), mine: [VolleyStats(), VolleyStats()], seed: 1, firstServe: 0)
        XCTAssertEqual(s.ball.pos.y, VolleyTuning.bodyTop + VolleyTuning.ballR, accuracy: 0.001, "not the old (0, 3) in the air")
        XCTAssertEqual(s.ball.pos.x, s.players[0].x, accuracy: 0.001)
    }

    /// Pure sim: a head that breathes and bobs, tall and short crowns, intro / serve wait / the arc / the toss: the ball is on the crown at every step.
    func testBallFollowsABobbingCrown() {
        for crownY in [Float(1.35), 1.5, 1.9] {
            var s = VolleySim(mode: .match(.sandcastle), mine: [VolleyStats(), VolleyStats()], seed: 3, firstServe: 0)
            var worst: Float = 0
            for k in 0..<400 {
                for i in 0..<4 {
                    let bob = 0.04 * sinf(Float(k) * 0.07 + Float(i))
                    s.setBody(i, x: VolleyTuning.startX[i] + 0.05 * sinf(Float(k) * 0.05), z: VolleyTuning.startZ[i], lift: 0, top: crownY + bob, grounded: true)
                    s.setCrown(i, SIMD3(VolleyTuning.startX[i] + 0.05 * sinf(Float(k) * 0.05), crownY + bob, VolleyTuning.startZ[i]))
                }
                s.tick(dt: 1.0 / 60)
                _ = s.takeEvents()
                if s.ballOnHead {
                    let c = s.players[s.servingPlayer].crownPoint
                    let gap = (s.ball.pos.y - VolleyTuning.ballR) - c.y
                    worst = max(worst, abs(gap))
                    XCTAssertGreaterThanOrEqual(gap, -0.002, "never sinks in (tick \(k))")
                }
            }
            XCTAssertLessThanOrEqual(worst, 0.02, "crown \(crownY): worst gap \(worst)")
        }
    }

    /// The toss starts from the head and the serve keeps today's timing: toss to the serve contact within a few hundredths of a second of the old hover.
    func testTheServeTimingIsKept() {
        func serve(old: Bool) -> (toss: Float, hit: Float, firstContact: VolleyHit?) {
            VolleyTuning.old = old
            defer { VolleyTuning.old = false }
            var s = VolleySim(mode: .match(.reef), mine: [VolleyStats(), VolleyStats()], seed: 2, firstServe: 1)
            var bodies = (0..<4).map { VolleyKBody(x: VolleyTuning.startX[$0], z: VolleyTuning.startZ[$0], side: $0 < 2 ? 1 : -1) }
            var toss: Float = -1, hit: Float = -1
            var firstContact: VolleyHit?
            var k = 0
            while hit < 0, k < 60 * 20 {
                k += 1
                for i in 0..<4 {
                    bodies[i].step(1.0 / 60)
                    s.setBody(i, x: bodies[i].x, z: bodies[i].z, lift: bodies[i].lift, top: bodies[i].top, grounded: bodies[i].grounded)
                    let smp = bodies[i].samples(); s.setSamples(i) { $0 = smp }
                    if bodies[i].finished { s.bodyDone(i) }
                }
                s.tick(dt: 1.0 / 60)
                for e in s.takeEvents() {
                    switch e {
                    case .serveToss: toss = s.clock
                    case .jump(let i, let dx, let dz, let a, _): bodies[i].jump(dx: dx, dz: dz, apex: a)
                    case .contact(_, let kind, _, _, _, _): if firstContact == nil { firstContact = kind }; if kind == .serve { hit = s.clock }
                    default: break
                    }
                }
                for i in 0..<4 { bodies[i].wantX = s.players[i].wantX; bodies[i].wantZ = s.players[i].wantZ }
            }
            return (toss, hit, firstContact)
        }
        let old = serve(old: true), new = serve(old: false)
        XCTAssertGreaterThan(new.toss, 0); XCTAssertGreaterThan(new.hit, 0)
        XCTAssertEqual(new.hit - new.toss, old.hit - old.toss, accuracy: 0.08, "toss to serve: old \(old.hit - old.toss) s, new \(new.hit - new.toss) s")
        XCTAssertEqual(new.firstContact, .serve, "the toss popping off the head is no touch: the first contact is the serve itself")
    }

    // MARK: 2 · the computer, measured

    /// The win-rate table: a scripted ordinary player (reacts in 0.35-0.5 s, imperfect, mistimes ~25%) and a skilled one (fast, 5%), 200 matches per level, before (`-VolleyOld 1`) and after.
    func testWinRatesPerLevel() {
        let n = 200
        func rates(_ p: VolleyScriptProfile, old: Bool) -> [VolleyTier: Float] {
            VolleyTuning.old = old
            defer { VolleyTuning.old = false }
            return VolleyHarness.table(profile: p, n: n, seed0: 777).mapValues { $0.rate * 100 }
        }
        let before = (o: rates(.ordinary, old: true), s: rates(.skilled, old: true))
        let after = (o: rates(.ordinary, old: false), s: rates(.skilled, old: false))
        var lines = ["win rate over \(n) matches per level (ordinary / skilled)       before      after"]
        for t in VolleyTier.allCases {
            lines.append(String(format: "%-10@ ordinary %5.1f%% -> %5.1f%%    skilled %5.1f%% -> %5.1f%%", t.title as NSString, before.o[t]!, after.o[t]!, before.s[t]!, after.s[t]!))
        }
        print("VOLLEYTABLE\n" + lines.joined(separator: "\n"))
        // the bands (200 matches is about +-3.5 points): first level 75-85, second 60-70, then down to 45-50 at the top; the skilled player still finds the top a real match
        XCTAssertTrue((70...90).contains(after.o[.sandcastle]!), "Sandcastle ordinary \(after.o[.sandcastle]!)")
        XCTAssertTrue((55...75).contains(after.o[.shore]!), "Shore ordinary \(after.o[.shore]!)")
        XCTAssertTrue((45...65).contains(after.o[.reef]!), "Reef ordinary \(after.o[.reef]!)")
        XCTAssertTrue((38...55).contains(after.o[.tidal]!), "Tidal ordinary \(after.o[.tidal]!)")
        XCTAssertTrue((50...70).contains(after.s[.tidal]!), "Tidal skilled \(after.s[.tidal]!)")
        XCTAssertGreaterThan(after.o[.sandcastle]!, before.o[.sandcastle]! + 30, "the first level got much easier for an ordinary player")
        XCTAssertGreaterThan(after.o[.sandcastle]!, after.o[.shore]!, "a gentle climb: each level is a little harder than the one before for the ordinary player")
        XCTAssertGreaterThan(after.o[.shore]!, after.o[.tidal]!)
    }

    func testNoSmashesAtTheFirstLevel() {
        VolleyTuning.old = false
        for k in 0..<60 {
            let r = VolleyHarness.play(tier: .sandcastle, seed: UInt64(900 + k), profile: .ordinary)
            XCTAssertEqual(r.spikesByComputer, 0, "seed \(900 + k): the first level's computer never smashes")
        }
    }

    func testRewardsAndUnlocksAreUnchanged() {
        XCTAssertEqual(VolleyTier.allCases.map { VolleyTuning.drops(win: true, tier: $0) }, [250, 400, 550, 750])
        XCTAssertEqual(VolleyTier.allCases.map { VolleyTuning.drops(win: false, tier: $0) }, [75, 120, 165, 225])
        let b = VolleyBook()
        XCTAssertFalse(b.unlocked(.shore))
        b.finishMatch(character: 0, tier: .sandcastle, win: false, closeLoss: true)
        b.finishMatch(character: 0, tier: .sandcastle, win: false, closeLoss: true)
        XCTAssertFalse(b.unlocked(.shore))
        b.finishMatch(character: 0, tier: .sandcastle, win: false, closeLoss: true)
        XCTAssertTrue(b.unlocked(.shore), "three close losses open the next tier")
        let c = VolleyBook()
        c.finishMatch(character: 0, tier: .sandcastle, win: true, closeLoss: false)
        XCTAssertTrue(c.unlocked(.shore), "a win opens it")
    }

    /// Cross-check of the rig on REAL soft bodies: the scripted ordinary player against the first level, match after match in the real court, for a wall-clock budget
    /// (`TEST_RUNNER_VOLLEY_REAL_MINUTES=20`; skipped otherwise). Prints `VOLLEYREAL`.
    func testRealBodyWinRateAtTheFirstLevel() throws {
        let minutes = Double(ProcessInfo.processInfo.environment["VOLLEY_REAL_MINUTES"] ?? "") ?? 0
        try XCTSkipIf(minutes <= 0, "set TEST_RUNNER_VOLLEY_REAL_MINUTES to run")
        let start = Date()
        var wins = 0, matches = 0, simSeconds: Float = 0
        var k: UInt64 = 0
        while Date().timeIntervalSince(start) < minutes * 60 {
            k += 1
            let c = court(seed: 4000 + k * 31)
            var script = VolleyScript(.ordinary, seed: 4000 + k * 31)
            let dt = c.room.actors[0].sim.stepDt
            var ticks = 0
            while c.care.volley.live, c.sim.phase != .over, ticks < 60 * 360 {
                var s = c.sim
                script.drive(&s, dt: dt)
                c.care.volley.sim = s
                c.step(); ticks += 1
            }
            guard c.sim.phase == .over else { continue }
            matches += 1; simSeconds += Float(ticks) * dt
            if c.sim.winner == 0 { wins += 1 }
            print("VOLLEYREALMATCH \(matches) win=\(c.sim.winner == 0) score=\(c.sim.score) sim_s=\(Int(Float(ticks) * dt)) elapsed=\(Int(Date().timeIntervalSince(start)))s")
        }
        print("VOLLEYREAL ordinary vs Sandcastle on real bodies: \(wins) / \(matches) = \(matches > 0 ? 100 * Float(wins) / Float(matches) : 0)%, avg \(matches > 0 ? simSeconds / Float(matches) : 0) sim s")
        XCTAssertGreaterThan(matches, 0)
    }

    // MARK: 3 · double tap to switch

    func testDoubleTapTiming() {
        var d = VolleyDoubleTap()
        let p = CGPoint(x: 100, y: 300)
        XCTAssertFalse(d.lift(at: p, time: 10.0, press: 0.08, travel: 2), "a single tap is not a double tap")
        XCTAssertTrue(d.lift(at: CGPoint(x: 110, y: 305), time: 10.25, press: 0.08, travel: 2), "two taps within 0.3 s")
        XCTAssertFalse(d.lift(at: p, time: 10.3, press: 0.08, travel: 2), "the pair is used up: the next tap starts over")
        XCTAssertFalse(d.lift(at: p, time: 20.0, press: 0.08, travel: 2))
        XCTAssertFalse(d.lift(at: p, time: 20.45, press: 0.08, travel: 2), "0.45 s apart is too slow")
        XCTAssertFalse(d.lift(at: p, time: 30.0, press: 0.08, travel: 2))
        XCTAssertFalse(d.lift(at: CGPoint(x: 300, y: 300), time: 30.1, press: 0.08, travel: 2), "far apart is not a double tap")
        XCTAssertFalse(d.lift(at: p, time: 40.0, press: 0.08, travel: 2))
        XCTAssertFalse(d.lift(at: p, time: 40.1, press: 0.08, travel: 60), "a drag (the stick) is not a tap")
        XCTAssertFalse(d.lift(at: p, time: 50.0, press: 0.08, travel: 2))
        XCTAssertFalse(d.lift(at: p, time: 50.1, press: 0.9, travel: 2), "a held finger (the stick) is not a tap")
    }

    /// The gesture as the screen runs it: two lifts on the teammate (a generous area round his body) in a court `state`; `taps` = 1 for a single tap.
    private func tapTeammate(_ c: Court, taps: Int, near offset: CGPoint = .zero) {
        GameCamera.configureBeach()
        let size = CGSize(width: 390, height: 844)
        let bodies = c.care.volley.bodyPos
        XCTAssertGreaterThanOrEqual(bodies.count, 2)
        let mate = 1 - c.care.volley.ui.controlled
        guard let centre = VolleyPick.centre(bodies[mate], size: size) else { return XCTFail("the teammate is on the screen") }
        let at = CGPoint(x: centre.x + offset.x, y: centre.y + offset.y)
        var d = VolleyDoubleTap()
        var done = false
        for k in 0..<taps { done = d.lift(at: at, time: 100 + Double(k) * 0.2, press: 0.07, travel: 1) }
        if done, let i = VolleyPick.nearest(bodies: Array(bodies.prefix(2)), at: at, size: size), i != c.care.volley.ui.controlled { c.care.volleySwitch(to: i) }
    }

    func testDoubleTapSwitchesInEveryMatchState() {
        for autoSwitch in [true, false] {
            let c = court()
            c.care.volley.sim?.autoSwitch = autoSwitch
            c.run(30)
            // serve wait, human serving: switches who is steered, not who serves
            XCTAssertEqual(c.sim.controlled, 0); let server = c.sim.servingPlayer
            tapTeammate(c, taps: 1)
            XCTAssertEqual(c.sim.controlled, 0, "autoSwitch \(autoSwitch): a single tap does nothing")
            tapTeammate(c, taps: 2)
            XCTAssertEqual(c.sim.controlled, 1, "autoSwitch \(autoSwitch): a double tap in the serve wait switches")
            XCTAssertEqual(c.sim.servingPlayer, server, "...but not who serves")
            c.run(5)
            XCTAssertTrue(c.sim.players[1].human); XCTAssertFalse(c.sim.players[0].human)
            // a double tap at the same time on the near-body edge (a generous area) also counts
            tapTeammate(c, taps: 2, near: CGPoint(x: 40, y: -30))
            XCTAssertEqual(c.sim.controlled, 0, "autoSwitch \(autoSwitch): and back, tapping a little off his middle")
            // rally
            c.care.volley.sim?.debugRally(possession: 1, touches: 1)
            c.care.volley.sim?.debugBall(pos: SIMD2(1.5, 3), vel: SIMD2(-1, 0), z: 0)
            c.run(2)
            tapTeammate(c, taps: 2)
            XCTAssertEqual(c.sim.controlled, 1, "autoSwitch \(autoSwitch): a double tap in a rally switches")
            // point pause (then it is the computer's serve)
            c.care.volley.sim?.forcePoint(team: 1)
            c.run(2)
            XCTAssertEqual(c.sim.phase, .pointPause)
            tapTeammate(c, taps: 2)
            XCTAssertEqual(c.sim.controlled, 0, "autoSwitch \(autoSwitch): and in the point pause")
            // the computer's serve wait
            var guardTicks = 0
            while c.sim.phase != .serveWait, guardTicks < 60 * 5 { c.step(); guardTicks += 1 }
            let who = c.sim.controlled
            tapTeammate(c, taps: 2)
            XCTAssertNotEqual(c.sim.controlled, who, "autoSwitch \(autoSwitch): and in the next serve wait")
        }
    }

    func testAutoSwitchStillWorksAfterADoubleTap() {
        let r = VolleyHarness.play(tier: .sandcastle, seed: 12, profile: .ordinary, autoSwitch: true, manualSwitchAt: 3)
        XCTAssertEqual(r.manualSwitches, 1)
        XCTAssertGreaterThan(r.autoSwitches, 2, "control still follows the ball after the manual switch (\(r.autoSwitches) automatic switches)")
        let off = VolleyHarness.play(tier: .sandcastle, seed: 12, profile: .ordinary, autoSwitch: false, manualSwitchAt: 3)
        XCTAssertEqual(off.manualSwitches, 1)
        XCTAssertLessThanOrEqual(off.autoSwitches, 12, "auto switch off: only the serve hands control to the server (\(off.autoSwitches))")
        XCTAssertLessThan(off.autoSwitches, r.autoSwitches)
    }

    func testPickAreaIsGenerousAndSizeFollowsTheCamera() {
        GameCamera.configureBeach()
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            let bodies: [SIMD3<Float>] = [SIMD3(-2.5, 1.35, 0.35), SIMD3(-1.1, 1.35, -0.35)]
            for (i, b) in bodies.enumerated() {
                guard let c = VolleyPick.centre(b, size: size), let reach = VolleyPick.reach(b, size: size) else { return XCTFail("on screen") }
                XCTAssertGreaterThanOrEqual(reach, 72)
                XCTAssertEqual(VolleyPick.nearest(bodies: bodies, at: c, size: size), i)
                XCTAssertEqual(VolleyPick.nearest(bodies: bodies, at: CGPoint(x: c.x, y: c.y - 55), size: size), i, "above his head still counts")
                XCTAssertNil(VolleyPick.nearest(bodies: bodies, at: CGPoint(x: size.width - 4, y: 4), size: size), "a far corner is nobody")
            }
        }
    }

    // MARK: 4 · the borrowed bodies show their species signature

    /// A seed whose pool gives a yellow (spines) and a lavender (wings) opponent, found with the same shuffle `volleySwap` uses.
    private func seedWithYellowAndLavender() -> UInt64? {
        for seed in UInt64(1)...400 {
            var rng = ParkRandom(seed &+ 77)
            var pool = ParkPool.all(reserved: ParkBook.reservedNames()).filter { $0.species == nil }
            for i in stride(from: pool.count - 1, to: 0, by: -1) { pool.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
            let sig = pool.prefix(2).map(\.signature)
            if sig.contains(.spines), sig.contains(.wings) { return seed }
        }
        return nil
    }

    func testBorrowedBodiesShowTheirSignature() throws {
        let seed = try XCTUnwrap(seedWithYellowAndLavender(), "a seed with a yellow and a lavender opponent")
        print("VOLLEYSEED \(seed)")
        let c = court(seed: seed)
        c.run(60)
        let w = c.care.volleyWork
        XCTAssertEqual(w.visitors.count, 2)
        var spines = 0, wings = 0
        for v in w.visitors {
            let sig = v.spec.signature
            XCTAssertEqual(v.actor.brain?.feature, sig)
            guard sig == .spines || sig == .wings else { continue }
            let slot = c.care.features.slot(v.actor.id)
            XCTAssertEqual(slot?.feature, sig, "\(v.spec.name): the feature set grows \(sig)")
            XCTAssertGreaterThan(slot?.scale ?? 0, 0.001, "\(v.spec.name): shown")
            if sig == .spines { spines += 1 } else { wings += 1 }
        }
        XCTAssertEqual(spines, 1); XCTAssertEqual(wings, 1)
        // it goes on through the point pause and the serve waits, and is put away at home
        c.care.volley.sim?.debugRally(possession: 0, touches: 1)
        c.care.volley.sim?.forcePoint(team: 0)
        c.run(120)
        for v in w.visitors where v.spec.signature == .spines || v.spec.signature == .wings {
            XCTAssertGreaterThan(c.care.features.slot(v.actor.id)?.scale ?? 0, 0.001, "\(v.spec.name): still shown between points")
        }
        let ids = w.visitors.map(\.actor.id)
        c.care.volley.goHome()
        var guardTicks = 0
        while c.care.volley.active, guardTicks < 60 * 10 { c.step(); guardTicks += 1 }
        XCTAssertFalse(c.care.volley.active)
        for id in ids { XCTAssertNil(c.care.features.shown(id), "put away at home (body \(id))") }
        XCTAssertTrue(w.visitors.isEmpty)
    }

    /// The same class of bug in any scene: every place that borrows bodies from `parkBook.spawn` also ticks their looks (`visitorLook`).
    func testEverySceneThatSpawnsVisitorsTicksTheirLooks() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BobV1")
        let en = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var spawners: [String] = []
        for case let u as URL in en where u.pathExtension == "swift" {
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            if u.lastPathComponent == "ContactDemo.swift" { continue }          // (a simulator capture aid, not a scene)
            if text.contains("parkBook.spawn?(") || text.contains("book.spawn?(") {
                spawners.append(u.lastPathComponent)
                XCTAssertTrue(text.contains("visitorLook("), "\(u.lastPathComponent) spawns visitor bodies but never calls visitorLook (their spikes / wings would not show)")
            }
        }
        XCTAssertGreaterThanOrEqual(spawners.count, 4, "the scenes found: \(spawners)")
        XCTAssertTrue(spawners.contains("GameCare+Volley.swift"))
    }
}
