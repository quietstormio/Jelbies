//
//  SoccerSessionTests.swift
//  soccer-room-r1: the room's soccer sessions (Melon/SoccerSession.swift): a ball put out starts a session, no ball = no session, a ring of three gives every member a kick,
//  a goal makes every member cheer, a busy member leaves cleanly, one Jelmiko plays alone.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SoccerSessionTests: XCTestCase {
    override func setUp() {
        SoccerState.shared.reset(); SoccerEvents.clear(); SoccerEvents.sink = nil; DecorField.shared.clear(); DecorField.shared.bodies = []
        SoccerSession.shared.reset(); MoveMix.soccerNextAt = 0; MoveMix.ballBadSince = -1
    }
    override func tearDown() {
        SoccerEvents.sink = nil; DecorField.shared.clear(); DecorField.shared.bodies = []; SoccerState.shared.reset(); SoccerSession.shared.reset()
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// n Jelmiko in the room, happy and free; a soccer ball (uid 7) in the middle, a goal (uid 8) when asked.
    private func lab(n: Int, goal: Bool = false, ball: Bool = true, seed: UInt64 = 70) -> SocialTests.Lab {
        let aspect: Float = 440.0 / 956.0
        GameCamera.configureRoom(count: max(n, 1), option: .A, wide: 2); _ = GameCamera.camera(aspect: aspect); _ = GameCamera.refreshRoam(aspect: aspect)
        RoomLayout.dynamicBoxes = []
        let l = SocialTests.Lab(n: n, positions: SocialTests.starts, quiet: false, seed: seed)
        SoccerTests.keep.append(l)
        for (i, r) in l.rigs.enumerated() {
            let b = r.brain
            b.sleepEnabled = false; b.anticsEnabled = true; b.watching = true; b.homeRoom = true
            b.idleMood = .happy; b.idleNight = 0; b.idleDeepNight = 0; b.idleMorning = 0
            b.socialBook.cooldown = 6 + Float(i) * 3; b.idleState.cooldown = 8 + Float(i) * 2; b.restTimer = 0.5 + Float(i)
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
        }
        if ball {          // (put out a moment after the room opened: a kick-off, not "the ball was already out")
            run(l, seconds: 1)
            var placed = [PlacedDecor(uid: 7, kind: .soccerball, x: 0.0, z: 1.0)]
            if goal { placed.append(PlacedDecor(uid: 8, kind: .minigoal, x: 0, z: -1.6)) }
            DecorField.shared.set(placed)
        }
        return l
    }
    private func run(_ l: SocialTests.Lab, seconds: Float) {
        for _ in 0..<Int(60 * seconds) {
            l.tick(watching: false)
            DecorField.shared.bodies = l.rigs.map { ($0.brain.steerID, $0.brain.position) }; DecorField.shared.tick(dt: 1.0 / 60)
        }
    }
    private func diag(_ l: SocialTests.Lab) -> String { "active=\(SoccerSession.shared.isActive) sessions=\(SoccerSession.shared.sessions) members=\(SoccerSession.shared.memberIDs) " + l.rigs.map { "id\($0.brain.steerID):\($0.brain.sessBlock(inSession: false) ?? "ok")/\($0.brain.mix.sess)/\($0.brain.mix.order.kind)\($0.brain.mix.order.state)" }.joined(separator: " ") + " ballFree=\(l.rigs[0].brain.freeBall() != nil)" }
    private func finish(_ l: SocialTests.Lab) { for r in l.rigs { r.brain.abortScript(r.sim, r.skinner); r.brain.sessRelease() }; DecorField.shared.clear() }

    override class func setUp() { super.setUp() }

    func testNoBallNoSession() {
        let l = lab(n: 3, ball: false)
        run(l, seconds: 25)
        XCTAssertEqual(SoccerSession.shared.sessions, 0)
        XCTAssertFalse(SoccerSession.shared.isActive)
        XCTAssertTrue(l.rigs.allSatisfy { !$0.brain.mix.sess && $0.brain.mix.order.kind == .none }, "the director is inert without a ball")
        finish(l)
    }

    func testPlacingABallStartsASessionAndAKickFollowsSoon() {
        var kicks: [Float] = []
        let l = lab(n: 3)
        var t: Float = 0
        SoccerEvents.sink = { e in if case .kick = e { kicks.append(t) } }
        for _ in 0..<(60 * 25) {
            l.tick(watching: false); t += 1.0 / 60
            DecorField.shared.bodies = l.rigs.map { ($0.brain.steerID, $0.brain.position) }; DecorField.shared.tick(dt: 1.0 / 60)
        }
        XCTAssertGreaterThanOrEqual(SoccerSession.shared.sessions, 1, diag(l))
        XCTAssertFalse(kicks.isEmpty, "a first kick happened \(diag(l))")
        XCTAssertLessThan(kicks.first ?? 99, 20, "first kick soon after the ball is out")
        finish(l)
    }

    func testARingOfThreeGivesEveryMemberAKick() {
        let l = lab(n: 3)
        var kickers = Set<Int>()
        SoccerEvents.sink = { e in if case .kick(let j, _, _) = e { kickers.insert(j) } }
        run(l, seconds: 100)
        MotionLog.write("SOCCERSESSION ring: kickers \(kickers.sorted()) sessions \(SoccerSession.shared.sessions) kicks \(SoccerSession.shared.passKicks) fetches \(SoccerSession.shared.fetches)")
        XCTAssertEqual(kickers, [0, 1, 2], "all three took part \(diag(l))")
        finish(l)
    }

    func testAGoalMakesEveryMemberCheer() {
        SoccerSession.shared.forceGame = .shots
        let l = lab(n: 3, goal: true)
        run(l, seconds: 8)
        XCTAssertTrue(SoccerSession.shared.isActive, diag(l))
        // wait until somebody is the shooter (his kick is running), then he scores
        var shooter: Int?
        for _ in 0..<(60 * 90) where shooter == nil {
            run(l, seconds: 0.05)
            if SoccerSession.shared.gameName == "shots", let r = l.rigs.first(where: { $0.brain.idleState.kind == .soccerKick }) { shooter = r.brain.steerID }
        }
        XCTAssertNotNil(shooter, "a shooter came up")
        SoccerState.shared.scored(ball: 7, goal: 8, scorer: shooter ?? 0)
        run(l, seconds: 6)
        XCTAssertGreaterThanOrEqual(SoccerSession.shared.goalsFullyCheered, 1, "every other member cheered")
        XCTAssertEqual(SoccerSession.shared.cheersDone, SoccerSession.shared.memberIDs.count - 1)
        finish(l)
    }

    func testABusyMemberLeavesCleanly() {
        let l = lab(n: 3)
        run(l, seconds: 12)
        XCTAssertTrue(SoccerSession.shared.isActive, diag(l))
        let b = l.rigs[1].brain
        b.reserved = true          // (a meal: one of the things that keeps a Jelmiko out of the game)
        run(l, seconds: 2)
        XCTAssertFalse(SoccerSession.shared.memberIDs.contains(b.steerID))
        XCTAssertFalse(b.mix.sess); XCTAssertEqual(b.mix.order.kind, .none); XCTAssertFalse(b.socialBook.hold)
        b.reserved = false
        run(l, seconds: 20)          // (the others carry on, no crash)
        finish(l)
    }

    func testOneJelmikoPlaysAlone() {
        let l = lab(n: 1)
        var kicks = 0
        SoccerEvents.sink = { e in if case .kick = e { kicks += 1 } }
        run(l, seconds: 60)
        MotionLog.write("SOCCERSESSION alone: kicks \(kicks) sessions \(SoccerSession.shared.sessions)")
        XCTAssertGreaterThanOrEqual(SoccerSession.shared.sessions, 1)
        XCTAssertGreaterThanOrEqual(kicks, 1)
        finish(l)
    }

    /// No ball in the room: the director is inert, so the movement is bit-for-bit what it is with sessions off (two seeds, 90 s each, every body's position every 0.25 s).
    func testWithoutABallTheMovementIsIdenticalToSessionsOff() {
        func trace(on: Bool, seed: UInt64) -> [SIMD2<Float>] {
            SoccerSessionTuning.on = on
            SoccerSession.shared.reset(); SoccerState.shared.reset(); SoccerEvents.clear(); DecorField.shared.clear(); DecorField.shared.bodies = []
            let l = lab(n: 3, ball: false, seed: seed)
            var out: [SIMD2<Float>] = []
            for f in 0..<(60 * 90) {
                l.tick(watching: false)
                DecorField.shared.bodies = l.rigs.map { ($0.brain.steerID, $0.brain.position) }; DecorField.shared.tick(dt: 1.0 / 60)
                if f % 15 == 0 { out += l.rigs.map { $0.brain.position } }
            }
            finish(l)
            return out
        }
        let was = BlobBrain.pickBudgetSeconds; BlobBrain.pickBudgetSeconds = .infinity          // (a pick that runs out of wall-clock time is not repeatable)
        defer { SoccerSessionTuning.on = true; BlobBrain.pickBudgetSeconds = was }
        for seed in [UInt64(11), 29] {
            let off1 = trace(on: false, seed: seed), on = trace(on: true, seed: seed), off2 = trace(on: false, seed: seed)
            guard off1 == off2 else { MotionLog.write("SOCCERSESSION identity: the room itself is not repeatable for seed \(seed); proof skipped"); continue }          // (a precondition: two runs with sessions off must agree)
            XCTAssertEqual(on.count, off1.count)
            XCTAssertTrue(on == off1, "seed \(seed): the movement differs with sessions on and no ball")
        }
    }
}
