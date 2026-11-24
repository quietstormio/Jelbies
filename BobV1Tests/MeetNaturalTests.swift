//
//  MeetNaturalTests.swift
//  meet-natural-r1: the joint approach of a pair moment (BobV1/Melon/MeetNatural.swift). Two bodies 3 m apart start a pair kind; both must WALK in (the partner is no waiter), arrive about together, end facing
//  the way the kind wants, with no turn on the spot after arriving. Switch off = the old start (the partner stands).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MeetNaturalTests: XCTestCase {
    private var wasHeadless = false
    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12; wasHeadless = MeetNatural.headless; MeetNatural.headless = true }
    override func tearDown() { RoomLayout.dynamicBoxes = []; MeetNatural.enabled = true; MeetNatural.headless = wasHeadless }

    struct Result { var gap: Float; var moved: [Float]; var turn: [Float]; var phase2: Bool; var yawErr: [Float]; var seconds: Float }

    /// Runs the kind until the emote phase (session phase 2) and measures, per body: path length moved, arrival time (the last frame it translated > 0.08 u/s), the turn after arrival, and the yaw error
    /// at phase 2 against the kind's final facing (each other / the camera).
    private func run(_ kind: SocialKind, a pa: SIMD2<Float>, b pb: SIMD2<Float>, natural: Bool, faceEach: Bool) -> Result {
        MeetNatural.enabled = natural
        let lab = SocialTests.Lab(n: 2, positions: [pa, pb], seed: 31)
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(kind, with: b.brain, a.sim), "\(kind): starts")
        var last = [a.brain.position, b.brain.position], start = last
        var arrive: [Float] = [0, 0], yawAt: [Float] = [a.brain.yaw, b.brain.yaw], yawArr = yawAt
        var moved: [Float] = [0, 0]
        var f = 0, p2 = false
        var prevPos = last
        while f < 60 * 25 {
            lab.tick(); f += 1
            let t = Float(f) / 60
            for (i, r) in [a, b].enumerated() {
                let p = r.brain.position
                moved[i] += simd_distance(p, prevPos[i])
                if simd_distance(p, prevPos[i]) * 60 > 0.08 { arrive[i] = t; yawArr[i] = r.brain.yaw }
                prevPos[i] = p
            }
            if let s = a.brain.social, s.phase >= 2 { p2 = true; yawAt = [a.brain.yaw, b.brain.yaw]; break }
            if !a.brain.isSocial { break }
        }
        _ = last; _ = start; last = prevPos
        func wrap(_ x: Float) -> Float { wrapAngle(x) }
        let want: [Float] = faceEach
            ? [atan2f(b.brain.position.x - a.brain.position.x, b.brain.position.y - a.brain.position.y), atan2f(a.brain.position.x - b.brain.position.x, a.brain.position.y - b.brain.position.y)]
            : [a.brain.faceCameraYaw(), b.brain.faceCameraYaw()]
        return Result(gap: abs(arrive[0] - arrive[1]), moved: moved, turn: [abs(wrap(yawAt[0] - yawArr[0])), abs(wrap(yawAt[1] - yawArr[1]))], phase2: p2, yawErr: [abs(wrap(yawAt[0] - want[0])), abs(wrap(yawAt[1] - want[1]))], seconds: Float(f) / 60)
    }

    private let from = SIMD2<Float>(-1.6, 0.6), to = SIMD2<Float>(1.5, 0.9)

    func testSwitchOffKeepsThePartnerStanding() {
        let r = run(.highFive, a: from, b: to, natural: false, faceEach: false)
        XCTAssertTrue(r.phase2)
        XCTAssertLessThan(r.moved[1], 0.9, "the old start: the partner waits (only his own last small steps)")
    }

    func testBothWalkInAndArriveTogether() {
        for (kind, each) in [(SocialKind.highFive, false), (.chestBump, true), (.nuzzle, false), (.sitTogether, false), (.boop, false)] {
            let r = run(kind, a: from, b: to, natural: true, faceEach: each)
            XCTAssertTrue(r.phase2, "\(kind): reaches its emote")
            XCTAssertGreaterThan(r.moved[1], 0.7, "\(kind): the partner walks in too (no waiter): moved \(r.moved)")
            XCTAssertGreaterThan(r.moved[0], 0.7, "\(kind): the initiator walks too: moved \(r.moved)")
            XCTAssertLessThan(r.gap, 1.0, "\(kind): arrival gap \(r.gap)")
            MotionLog.write(String(format: "MEET %@ gap %.2f moved %.2f/%.2f turn %.0f/%.0f yawErr %.0f/%.0f secs %.1f", kind.rawValue, r.gap, r.moved[0], r.moved[1], r.turn[0] * 57.3, r.turn[1] * 57.3, r.yawErr[0] * 57.3, r.yawErr[1] * 57.3, r.seconds))
        }
    }

    func testFinalFacingIsReachedOnThePathNotByTurningAfterArrival() {
        for (kind, each) in [(SocialKind.highFive, false), (.chestBump, true), (.nuzzle, false)] {
            let r = run(kind, a: from, b: to, natural: true, faceEach: each)
            XCTAssertTrue(r.phase2)
            for i in 0..<2 { XCTAssertLessThan(r.turn[i] * 57.3, 45, "\(kind) body \(i): turn on the spot after arrival \(r.turn[i] * 57.3) deg") }
            for i in 0..<2 { XCTAssertLessThan(r.yawErr[i] * 57.3, 30, "\(kind) body \(i): final facing off by \(r.yawErr[i] * 57.3) deg") }
        }
    }

    func testShortLegKeepsTheOldStart() {
        MeetNatural.enabled = true
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-0.7, 0.6), SIMD2(0.8, 0.9)], seed: 5)
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.nuzzle, with: b.brain, a.sim))
        for _ in 0..<30 { lab.tick() }
        XCTAssertLessThan(simd_distance(b.brain.position, SIMD2(0.8, 0.9)), 0.6, "a short walk-up: the partner does not wander off")
    }
}
