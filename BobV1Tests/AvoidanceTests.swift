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
                b.sleepEnabled = false; b.anticsEnabled = true; b.watching = false; b.homeRoom = true
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
                r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = true; r.skinner.autoBlink = false; r.renderSamples = false
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
        let seconds = Float(env["MOVELOG_SECONDS"].flatMap { Float($0) } ?? 120)
        let seeds: [UInt64] = (0..<(env["MOVELOG_SEEDS"].flatMap { Int($0) } ?? 3)).map { 41 + 7 * UInt64($0) }
        let places: [(String, Place)] = [("home happy", .home(.happy)), ("home grumpy", .home(.grumpy)), ("park 5", .park)]
        for (name, place) in places where env["MOVELOG_ONLY"] == nil || name.contains(env["MOVELOG_ONLY"]!) {
            var all = MoveLog.Totals()
            for s in seeds {
                let (line, t) = measure(place, seed: s, seconds: seconds, tag: "\(name) seed \(s)")
                MotionLog.write("MOVELOG \(line)")
                for k in 0..<6 { all.n[k] += t.n[k] }
                for c in 0..<9 { all.bodySec[c] += t.bodySec[c]; all.emoteSec[c] += t.emoteSec[c] }
                all.walkSec += t.walkSec; all.gameSec += t.gameSec
            }
            let mins = all.gameSec / 60
            MotionLog.write("MOVELOG TABLE \(name) | " + zip(MoveLog.names, all.n).map { "\($0) \(String(format: "%.1f", Float($1) / mins))/min" }.joined(separator: " ") + String(format: " | %.1f game-min over %d seeds, walk %.0f s", mins, seeds.count, all.walkSec))
        }
    }
}
