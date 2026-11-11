//
//  VolleySwitchTests.swift
//  Switching the Jelbie you steer in Jelly Volleyball (a double-tap on the teammate) must not make him hop: a hop puts his brain in crouch / air, and a block or bonk jump
//  pressed right after the switch would be refused. Real GameCare, real soft bodies (the RaceThreeTests room: two Jelbies and the two visitors from `parkBook.spawn`),
//  a fixed seed, the stage's own `tickVolley`. The match waits at the serve (nobody jumps by himself) while the switch is made.
//

import XCTest
@testable import BobV1

@MainActor
final class VolleySwitchTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    @MainActor private struct Court {
        let room: RaceThreeTests.Room
        var care: GameCare { room.care }
        var mate: JellyActor { room.care.volleyWork.players[1] }
        func step() {
            room.step()
            care.tickVolley(room.actors, dt: room.actors[0].sim.stepDt)
        }
        func run(_ n: Int) { for _ in 0..<n { step() } }
    }

    /// A 2-against-2 match, seed 5, run until it waits at the serve with the teammate standing still on the ground.
    private func court() -> Court {
        let room = RaceThreeTests.Room(count: 2)
        Self.keep.append(room)
        let c = Court(room: room)
        c.care.startVolley(jelly: 0, mode: .match(.sandcastle), seed: 5)
        var guardTicks = 0
        while !(c.care.volley.live && c.care.volley.sim?.phase == .serveWait) && guardTicks < 60 * 40 { c.step(); guardTicks += 1 }
        XCTAssertTrue(c.care.volley.live, "the match is on")
        XCTAssertEqual(c.care.volley.sim?.phase, .serveWait)
        XCTAssertEqual(c.care.volleyWork.players.count, 4, "two Jelbies and two visitors")
        c.run(60)          // settle: the teammate has walked to his spot and stands
        let s = c.care.volley.sim!
        XCTAssertEqual(s.players[1].act, .stand)
        XCTAssertEqual(c.mate.brain?.volley.phase, .ground)
        XCTAssertEqual(s.controlled, 0)
        return c
    }

    private func heights(_ c: Court, ticks: Int) -> [Float] {
        (0..<ticks).map { _ in c.step(); return c.mate.sim.centroid().y }
    }

    func testManualSwitchDoesNotMakeTheNewJelbieHop() {
        let c = court()
        let before = heights(c, ticks: 30)
        c.care.volleySwitch(to: 1)
        XCTAssertEqual(c.care.volley.sim?.controlled, 1, "control moved")
        var bad: [Int] = []
        var after: [Float] = []
        for k in 0..<60 {
            c.step()
            after.append(c.mate.sim.centroid().y)
            let ph = c.mate.brain!.volley.phase
            if ph == .crouch || ph == .air { bad.append(k) }
        }
        XCTAssertTrue(bad.isEmpty, "he went into crouch / air on ticks \(bad.prefix(5)) after the switch")
        XCTAssertLessThan(after.max()! - before.max()!, 0.015, "his body rose after the switch")
        XCTAssertEqual(c.care.volley.sim?.players[1].act, .stand)
    }

    func testAJumpIsAcceptedOneTickAfterTheSwitch() {
        let c = court()
        c.care.volleySwitch(to: 1)
        c.step()          // the switch event is applied here
        let b = c.mate.brain!
        XCTAssertEqual(b.volley.phase, .ground, "no hop is running")
        b.volleyJump(sim: c.mate.sim, dx: 0, dz: 0, apex: 0.45, block: true)
        XCTAssertEqual(b.volley.phase, .crouch, "the block jump is accepted at once")
        XCTAssertTrue(b.volley.block, "it is the block jump that started, not a hop that was already running")
    }

    func testTheRingStillAnswersAManualSwitch() {
        let c = court()
        c.care.volleySwitch(to: 1)
        let queued = c.care.volley.sim!.events
        XCTAssertTrue(queued.contains { if case .switched(let to, let auto) = $0 { return to == 1 && !auto }; return false }, "the manual switch event: \(queued)")
        XCTAssertEqual(c.care.volley.sim?.controlled, 1)
        XCTAssertTrue(c.care.volley.sim!.players[1].human)
        XCTAssertFalse(c.care.volley.sim!.players[0].human)
    }

    func testAnAutomaticSwitchDoesNotHopEither() {
        let c = court()
        c.care.volley.sim?.switchTo(1, manual: false)
        XCTAssertEqual(c.care.volley.sim?.controlled, 1)
        for k in 0..<60 {
            c.step()
            let ph = c.mate.brain!.volley.phase
            XCTAssertTrue(ph != .crouch && ph != .air, "tick \(k): phase \(ph)")
            if ph == .crouch || ph == .air { break }
        }
    }
}
