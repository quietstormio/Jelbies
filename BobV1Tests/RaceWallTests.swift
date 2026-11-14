//
//  RaceWallTests.swift
//  The room's round wall must not come back on the temporary race rivals. A roster of one races with two borrowed visitor bodies whose wall the race lifts (raceSpawnExtras);
//  the stage's syncRoam put the room's wall back on every visitor, pressing them flat against it at both ends of the track. `MelonController.applyRoomArena` is that step.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RaceWallTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func apply(_ room: RaceThreeTests.Room) {
        MelonController.applyRoomArena(actors: room.actors, parkActors: room.park, bathFenceLifted: false)
    }

    private func visitorSpec(_ id: Int) -> ParkVisitor {
        ParkVisitor(id: id, name: "V\(id)", colour: .cream, signature: .none, wear: nil, style: .balanced, blurb: "", greeting: "")
    }

    func testRuleKeepsTheTemporaryRivalsWallLifted() {
        let saved = MelonController.visitorArenaGuard
        defer { MelonController.visitorArenaGuard = saved }
        let room = RaceThreeTests.Room(count: 1)
        Self.keep.append(room)
        let care = room.care
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.2)
        care.startRace(jelly: 0, seed: 11)
        room.run(4) { care.race.trackVisible && care.raceBook.racers.count > 0 }
        XCTAssertTrue(care.race.trackVisible)
        XCTAssertEqual(room.park.count, 2)
        for a in room.park { XCTAssertEqual(a.sim.arenaRadius, .infinity); XCTAssertTrue(a.brain!.race.active) }

        MelonController.visitorArenaGuard = true
        apply(room)
        for a in room.park { XCTAssertEqual(a.sim.arenaRadius, .infinity, "guard on: the racing visitor keeps its wall lifted") }

        MelonController.visitorArenaGuard = false
        apply(room)
        for a in room.park { XCTAssertTrue(a.sim.arenaRadius.isFinite, "guard off (the old loop): the wall is back on the rival (the bug)") }
    }

    func testNonRacingVisitorsStillFollowTheRoom() {
        let saved = MelonController.visitorArenaGuard
        defer { MelonController.visitorArenaGuard = saved }
        MelonController.visitorArenaGuard = true
        let room = RaceThreeTests.Room(count: 1)
        Self.keep.append(room)
        let bodies = room.care.parkBook.spawn!([visitorSpec(9100), visitorSpec(9101)], [SIMD2<Float>(1, 1), SIMD2<Float>(-1, 1)])
        XCTAssertEqual(bodies.count, 2)
        bodies[0].sim.arenaCenter = SIMD2<Float>(7, 7); bodies[0].sim.arenaRadius = 2          // a stale room wall
        bodies[1].sim.arenaRadius = .infinity                                                   // a lifted one (guest run-in / show / café)
        XCTAssertFalse(bodies[0].brain!.race.active)
        MelonController.applyRoomArena(actors: room.actors, parkActors: room.park, bathFenceLifted: false)
        XCTAssertEqual(bodies[0].sim.arenaCenter, GameCamera.arenaCenter)
        XCTAssertEqual(bodies[0].sim.arenaRadius, GameCamera.arenaRadius)
        XCTAssertEqual(bodies[1].sim.arenaRadius, .infinity, "a lifted visitor wall stays lifted")
    }

    /// A full pull race with one creature at home, the room's wall step run every step (as if the aspect changed every frame).
    private func race(guardOn: Bool) -> (finished: [Bool], countdownGap: [Float], maxGapLastThird: [Float], radii: [Float], reachedResults: Bool) {
        let saved = MelonController.visitorArenaGuard
        defer { MelonController.visitorArenaGuard = saved }
        MelonController.visitorArenaGuard = guardOn
        let room = RaceThreeTests.Room(count: 1)
        Self.keep.append(room)
        let care = room.care
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.7)
        care.race.autoRate = nil
        care.race.control = .pull
        care.startRace(jelly: 0, seed: 7)
        let dt = room.actors[0].sim.stepDt
        func gap(_ k: Int) -> Float {
            let a = (room.actors + room.park)[care.raceBook.racers[k]]
            return simd_length(a.sim.attractor.anchor - a.sim.bodyPose(iterations: 3).centroid)
        }
        var cdGap: [Float] = [0, 0, 0], radii: [Float] = [], last = [Float](repeating: 0, count: 3), n = 0
        var gapsAtDist: [[(Float, Float)]] = [[], [], []]
        while n < 150 * 60, !care.race.hasResults {
            n += 1
            if let s = care.race.sim, care.race.phase == .racing, !s.pullState(0).buffered { _ = care.race.release(pull: 0.80) }
            room.step()
            apply(room)
            if let s = care.race.sim, care.raceBook.racers.count == 3, care.race.trackVisible {
                if s.phase == .countdown { for k in 0..<3 { cdGap[k] = gap(k) }; radii = (0..<3).map { (room.actors + room.park)[care.raceBook.racers[$0]].sim.arenaRadius } }
                if s.phase == .running { for k in 0..<3 { gapsAtDist[k].append((s.racers[k].dist, gap(k))) } }
            }
            _ = dt
        }
        let sim = care.race.sim
        let len = RaceTuning.length
        for k in 0..<3 { last[k] = gapsAtDist[k].filter { $0.0 > len * 2 / 3 }.map(\.1).max() ?? 0 }
        MotionLog.write("RACEWALL guard=\(guardOn) countdownGap=\(cdGap) radii=\(radii) lastThirdMaxGap=\(last) finished=\(sim?.racers.map(\.finished) ?? []) results=\(care.race.hasResults)")
        return (sim?.racers.map(\.finished) ?? [], cdGap, last, radii, care.race.hasResults)
    }

    func testRivalsFinishAndStayAttachedWithTheGuard() {
        let r = race(guardOn: true)
        XCTAssertEqual(r.finished.count, 3)
        XCTAssertTrue(r.finished[1] && r.finished[2], "both rivals finish: \(r.finished)")
        XCTAssertTrue(r.radii.dropFirst().allSatisfy { $0 == .infinity }, "rival walls lifted at the countdown: \(r.radii)")
        for k in 0..<3 { XCTAssertLessThan(r.countdownGap[k], 0.3, "racer \(k) fitted centroid near its attractor anchor at the countdown") }
        for k in 1..<3 { XCTAssertLessThan(r.maxGapLastThird[k], 0.5, "rival \(k) stays on its attractor in the last third") }
    }

    func testTheOldLoopWallsTheRivals() {
        let r = race(guardOn: false)
        let bad = !(r.finished.count == 3 && r.finished[1] && r.finished[2]) || r.countdownGap.dropFirst().contains { $0 >= 0.3 }
        XCTAssertTrue(bad, "with the old unguarded loop the rivals must fail to finish or be off their anchor at the countdown: finished \(r.finished), gaps \(r.countdownGap)")
        XCTAssertTrue(r.radii.dropFirst().allSatisfy { $0.isFinite }, "old loop: rivals walled \(r.radii)")
    }
}
