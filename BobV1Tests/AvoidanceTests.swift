//
//  AvoidanceTests.swift
//  avoid-r1 phase 0: the awkward-moments logger (Melon/MoveLog.swift), measured headless. Home living room (3 bodies, all in one mood: happy / grumpy) and park (5 bodies).
//  Opt-in: TEST_RUNNER_MOVELOG_SOAK=1 (TEST_RUNNER_MOVELOG_SECONDS, default 120; TEST_RUNNER_MOVELOG_SEEDS, default 3). The numbers go to MotionLog (TEST_RUNNER_MOTION_LOG).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class AvoidanceTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    enum Place { case home(IdleMood), park }

    override func setUp() { BlobBrain.pickBudgetSeconds = .infinity }
    override func tearDown() {
        MoveLog.on = false; MoveLog.writeFile = true
        BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds
        DecorField.shared.clear(); HopscotchLine.shared.prune(keeping: [])
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    /// One logged run; returns the log's summary line and its cumulative totals.
    func measure(_ place: Place, seed: UInt64, seconds: Float, tag: String) -> (String, MoveLog.Totals) {
        let lab: SocialTests.Lab
        let n: Int
        switch place {
        case .home(let mood):
            n = 3
            GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
            _ = GameCamera.refreshRoam(aspect: 440 / 956)
            RoomLayout.dynamicBoxes = []
            lab = SocialTests.Lab(positions: SocialTests.starts, quiet: false, seed: seed)
            for (i, r) in lab.rigs.enumerated() {
                r.skinner.autoBlink = false
                let b = r.brain
                b.sleepEnabled = ProcessInfo.processInfo.environment["MOVELOG_SLEEP"] == "1"; b.anticsEnabled = true; b.watching = ProcessInfo.processInfo.environment["MOVELOG_WATCHING"] == "1"; b.homeRoom = ProcessInfo.processInfo.environment["MOVELOG_HOMEROOM"] != "0"          // (move-b-r1: TEST_RUNNER_MOVELOG_HOMEROOM=0 = the old headless way, homeRoom off)
                b.idleMood = mood; b.idleNight = 0; b.idleDeepNight = 0; b.idleMorning = 0
                b.socialBook.cooldown = 6 + Float(i) * 3; b.idleState.cooldown = 8 + Float(i) * 2; b.restTimer = 0.5 + Float(i)
                r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            }
        case .park:
            n = 5
            ParkVisitPlan.current = .all
            DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); HopscotchLine.shared.prune(keeping: [])
            RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
            let pts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(1.6, 1.2), SIMD2(-1.6, 1.6)]
            lab = SocialTests.Lab(n: n, positions: pts, quiet: false, seed: seed)
            for (k, r) in lab.rigs.enumerated() {
                r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
                r.brain.anticsEnabled = true; r.brain.watching = ProcessInfo.processInfo.environment["MOVELOG_WATCHING"] == "1"; r.brain.idleMood = .happy; r.brain.outingPlay = true; r.skinner.autoBlink = false; r.renderSamples = false
                r.brain.feature = JellyRoster.feature(k % 5)
                r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
                for (j, o) in lab.rigs.enumerated() where o !== r && (j >= 2 || k >= 2) { r.brain.socialBook.close[o.brain.steerID] = 0.55 }
            }
            WearBody.install(MotionRig.renderMesh)
            DecorField.shared.set(ParkVisitPlan.placedToday); DecorField.shared.toys.news.removeAll()
        }
        Self.keep.append(lab)
        MoveLog.shared.reset(); MoveLog.shared.tag = tag; MoveLog.writeFile = false; MoveLog.on = true
        let dt: Float = 1.0 / 60
        for _ in 0..<Int(seconds * 60) {
            lab.tick(watching: false)
            if case .park = place { DecorField.shared.tick(dt: dt) }
        }
        MoveLog.on = false
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        DecorField.shared.clear(); HopscotchLine.shared.prune(keeping: [])
        return (MoveLog.shared.summary, MoveLog.shared.total)
    }

    func testMoveLogSoak() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["MOVELOG_SOAK"] != nil else { throw XCTSkip("set TEST_RUNNER_MOVELOG_SOAK=1") }
        let seconds = Float(env["MOVELOG_SECONDS"].flatMap { Float($0) } ?? 180)
        let seeds: [UInt64] = (0..<(env["MOVELOG_SEEDS"].flatMap { Int($0) } ?? 3)).map { 41 + 7 * UInt64($0) }
        MotionLog.write("MOVELOG \(RoomTraffic.switchesText)")
        let places: [(String, Place)] = [("home happy", .home(.happy)), ("home grumpy", .home(.grumpy)), ("park 5", .park)]
        for (name, place) in places where env["MOVELOG_ONLY"] == nil || name.contains(env["MOVELOG_ONLY"]!) {
            var all = MoveLog.Totals()
            RoomTraffic.counts = [0, 0, 0, 0, 0, 0]; RoomRoam.ran = [0, 0, 0]
            for s in seeds {
                let (line, t) = measure(place, seed: s, seconds: seconds, tag: "\(name) seed \(s)")
                MotionLog.write("MOVELOG \(line)")
                MoveLog.add(&all, t)
            }
            let mins = all.gameSec / 60
            MotionLog.write("MOVELOG TABLE \(name) | " + zip(MoveLog.names, all.n).map { "\($0) \(String(format: "%.1f", Float($1) / mins))/min" }.joined(separator: " ") + String(format: " | %.1f game-min over %d seeds, walk %.0f s / %d walks = %.2f s per u (arrivals only), emotes %d (%.1f/min), walks %.1f/min", mins, seeds.count, all.walkSec, all.walkN, all.arrSec / Float(max(all.arrDist, 0.01)), all.emoteN, Float(all.emoteN) / mins, Float(all.walkN) / mins))
            MotionLog.write("MOVELOG TABLEX \(name) | \(MoveLog.extra(all))")
            MotionLog.write("MOVELOG ROOMTRAFFIC \(name) | \(RoomTraffic.report) | gate ran \(RoomRoam.ran[0])")
        }
    }

    /// move-mix round 3: a soccer ball (SOCCER_SOAK=1; SOCCER_GOAL=1 also the mini goal) placed in the home room, three happy Jelmiko, SOCCER_SECONDS (600) x SOCCER_SEEDS (3): how many soccer moments (a pass, a solo kick / dribble / shot), kicks per pass, goals, the ball-play share.
    func testSoccerSoak() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SOCCER_SOAK"] != nil else { throw XCTSkip("set TEST_RUNNER_SOCCER_SOAK=1") }
        let seconds = Float(env["SOCCER_SECONDS"].flatMap { Float($0) } ?? 600)
        let seeds: [UInt64] = (0..<(env["SOCCER_SEEDS"].flatMap { Int($0) } ?? 3)).map { 61 + 5 * UInt64($0) }
        let withGoal = env["SOCCER_GOAL"] != nil
        var totals = (moments: 0, passes: 0, solo: 0, kicksInPass: [Int](), goals: 0, kicks: 0, mins: Float(0), play: Float(0), all: Float(0))
        for seed in seeds {
            GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
            _ = GameCamera.refreshRoam(aspect: 440 / 956)
            RoomLayout.dynamicBoxes = []
            DecorField.shared.clear(); SoccerState.shared.reset(); SoccerEvents.clear()
            var placed = [PlacedDecor(uid: 7, kind: .soccerball, x: -1.2, z: 1.4)]
            if withGoal { placed.append(PlacedDecor(uid: 8, kind: .minigoal, x: 0, z: -1.6)) }
            DecorField.shared.set(placed)
            let lab = SocialTests.Lab(positions: SocialTests.starts, quiet: false, seed: seed)
            Self.keep.append(lab)
            for (i, r) in lab.rigs.enumerated() {
                r.skinner.autoBlink = false
                let b = r.brain
                b.sleepEnabled = false; b.anticsEnabled = true; b.watching = true; b.homeRoom = true
                b.idleMood = .happy; b.idleNight = 0; b.idleDeepNight = 0; b.idleMorning = 0
                b.socialBook.cooldown = 6 + Float(i) * 3; b.idleState.cooldown = 8 + Float(i) * 2; b.restTimer = 0.5 + Float(i)
                r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            }
            var kicks = 0, goals = 0
            SoccerEvents.sink = { e in switch e { case .kick: kicks += 1; case .goal: goals += 1; default: break } }
            var sessions: [ObjectIdentifier: Int] = [:], soloOn = [false, false, false], solo = 0
            var moment = 0, momentLast: Float = -99, momentsN = 0
            MoveLog.shared.reset(); MoveLog.shared.tag = "soccer seed \(seed)"; MoveLog.writeFile = false; MoveLog.on = true
            let dt: Float = 1.0 / 60
            for f in 0..<Int(seconds * 60) {
                lab.tick(watching: false)
                DecorField.shared.bodies = lab.rigs.map { ($0.brain.steerID, $0.brain.position) }; DecorField.shared.tick(dt: dt)
                var any = false
                for (i, r) in lab.rigs.enumerated() {
                    let b = r.brain
                    if let sn = b.social, sn.kind == .pass { sessions[ObjectIdentifier(sn)] = sn.passes; any = true }
                    let on = b.idleState.kind == .soccerKick
                    if on { any = true; if !soloOn[i] { solo += 1 } }
                    soloOn[i] = on
                }
                let t = Float(f) * dt
                if any { if t - momentLast > 6 { momentsN += 1 }; momentLast = t }
                _ = moment; moment = 0
            }
            MoveLog.on = false
            for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
            SoccerEvents.sink = nil
            let tt = MoveLog.shared.total
            totals.moments += momentsN; totals.passes += sessions.count; totals.solo += solo; totals.kicksInPass += sessions.values.map { $0 }; totals.goals += goals; totals.kicks += kicks; totals.mins += seconds / 60
            totals.play += tt.act[6]; totals.all += tt.act.reduce(0, +)
            MotionLog.write("SOCCER seed \(seed) \(seconds) s: moments \(momentsN), pass sessions \(sessions.count) kicks-per-pass \(sessions.values.sorted()), solo starts \(solo), kicks \(kicks), goals \(goals), ball play \(String(format: "%.1f", tt.act[6] / max(tt.act.reduce(0, +), 0.01) * 100))% of body time, MoveMix \(MoveMix.on)")
            DecorField.shared.clear()
        }
        MotionLog.write("SOCCER TOTAL goal=\(withGoal) MoveMix=\(MoveMix.on): \(totals.moments) moments in \(totals.mins) min (one per \(String(format: "%.0f", totals.mins * 60 / Float(max(totals.moments, 1)))) s), \(totals.passes) pass sessions (one per \(String(format: "%.1f", totals.mins / Float(max(totals.passes, 1)))) min) kicks per pass \(totals.kicksInPass.sorted()), solo starts \(totals.solo), kicks \(totals.kicks), goals \(totals.goals), ball play \(String(format: "%.1f", totals.play / max(totals.all, 0.01) * 100))%")
    }

    /// move-b-r1: the `back`, `side` and `overlap` counters were 0 everywhere and unproven. Forced scenario: two bodies walked straight at each other with avoidance off
    /// (the look-ahead off, the peer spring off: `passThrough`) must overlap; one body moved sideways by hand, and one backwards, while its walk script runs must log `side` / `back`.
    func testMoveLogCountersFire() throws {
        guard ProcessInfo.processInfo.environment["MOVELOG_FORCED"] != nil else { throw XCTSkip("set TEST_RUNNER_MOVELOG_FORCED=1") }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        _ = GameCamera.refreshRoam(aspect: 440 / 956)
        RoomLayout.dynamicBoxes = []
        let was = ContactTuning.lookAhead
        defer { ContactTuning.lookAhead = was }
        ContactTuning.lookAhead = false
        let lab = SocialTests.Lab(n: 3, positions: [SIMD2(-1.6, 0.8), SIMD2(1.6, 0.8), SIMD2(0, 2.4)], quiet: true, seed: 5)
        Self.keep.append(lab)
        let a = lab.rigs[0].brain, b = lab.rigs[1].brain, c = lab.rigs[2].brain
        for x in [a, b] { x.socialBook.passThrough = true; x.peers = { [] } }          // (blind to each other, no peer spring)
        a.script = .walk(target: SIMD2(1.6, 0.8), then: .none); a.activity = .walking
        b.script = .walk(target: SIMD2(-1.6, 0.8), then: .none); b.activity = .walking
        MoveLog.shared.reset(); MoveLog.shared.tag = "forced"; MoveLog.writeFile = false; MoveLog.on = true
        var minD: Float = 9, firstFire: Float?
        for t in 0..<(60 * 6) {
            lab.tick(watching: false); minD = min(minD, simd_distance(a.position, b.position))
            if firstFire == nil, MoveLog.shared.total.n[MoveLog.Kind.overlap.rawValue] > 0 { firstFire = simd_distance(a.position, b.position) / a.peerGap; _ = t }
        }
        MotionLog.write("MOVELOG FORCED gap source: ContactField.gap = \(String(describing: ContactField.gap(a.steerID, b.steerID, features: false))), peerGap \(a.peerGap), centre distance / peerGap at first overlap event \(String(describing: firstFire))")
        let overlapFired = MoveLog.shared.total.n[MoveLog.Kind.overlap.rawValue]
        MotionLog.write("MOVELOG FORCED head-on: closest centre distance \(minD), overlap events \(overlapFired), push \(MoveLog.shared.total.n[0]), hard \(MoveLog.shared.total.n[1])")
        // by hand: c faces +z (yaw 0) with a walk script; sampled directly while its root is moved sideways, then backwards
        a.script = .none; b.script = .none; a.activity = .idle; b.activity = .idle
        MoveLog.shared.reset(); MoveLog.on = true
        c.script = .walk(target: SIMD2(0, 9), then: .none); c.activity = .walking; c.yaw = 0
        for k in 0..<60 { c.px = Float(k) * 0.012; c.pz = 2.4; MoveLog.shared.sample(c, dt: 1.0 / 60) }          // 0.72 u/s straight to the side
        let sideN = MoveLog.shared.total.n[MoveLog.Kind.side.rawValue], backAfterSide = MoveLog.shared.total.n[MoveLog.Kind.back.rawValue]
        MoveLog.shared.reset(); MoveLog.on = true
        for k in 0..<60 { c.px = 0; c.pz = 2.4 - Float(k) * 0.012; MoveLog.shared.sample(c, dt: 1.0 / 60) }          // 0.72 u/s backwards
        let backN = MoveLog.shared.total.n[MoveLog.Kind.back.rawValue]
        MoveLog.on = false
        MotionLog.write("MOVELOG FORCED by hand: side events \(sideN) (back \(backAfterSide)), backward events \(backN)")
        for r in lab.rigs { r.brain.socialBook.passThrough = false; r.brain.abortScript(r.sim, r.skinner) }
        XCTAssertGreaterThan(overlapFired, 0, "overlap counter did not fire")
        XCTAssertGreaterThan(sideN, 0, "side counter did not fire")
        XCTAssertGreaterThan(backN, 0, "back counter did not fire")
    }
}
