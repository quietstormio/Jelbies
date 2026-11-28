//
//  EarsDanceTests.swift
//  The Music Ears cycle (ears-dance-r2): they sway where they stand, walk to the row after 5-8 s, do a simple stepped routine on the beat (real foot steps:
//  never sliding, never crossing, the bodies >= 1.2 apart), sway in the row, do the next routine, and stop when the music does.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class EarsDanceTests: XCTestCase {
    typealias Room = EarsReactorTests.Room

    /// The tracker's estimates every 0.5 s on one grid, like the app's music events.
    private func feed(_ room: Room, bpm: Float, anchor: Double, seconds: Double, each: (() -> Void)? = nil) {
        var left = seconds
        while left > 0 {
            let step = min(0.5, left)
            room.run(step, each: each)
            room.handle(.musicBeat(EarBeat(bpm: bpm, anchor: anchor, strength: 3)))
            left -= step
        }
    }

    func testTheySwayWhereTheyStandThenWalkToTheRowAfterTheWait() {
        let room = Room(count: 3); Self.keep.append(room)
        room.reactor.rowWaitRange = 6...6
        let start = room.rigs.map { GameCare.floorPos($0.brain, $0.sim) }
        let anchor = room.now + 0.2
        room.handle(.musicStarted(EarBeat(bpm: 100, anchor: anchor, strength: 3)))
        var rollMax: Float = 0, drift: Float = 0
        feed(room, bpm: 100, anchor: anchor, seconds: 5.5) {
            for (i, r) in room.rigs.enumerated() {
                rollMax = max(rollMax, abs(r.brain.ears.roll))
                drift = max(drift, simd_distance(GameCare.floorPos(r.brain, r.sim), start[i]))
                XCTAssertTrue(r.brain.held, "a dancer is held")
            }
        }
        XCTAssertEqual(room.reactor.cycle.stage, .inPlace)
        XCTAssertTrue(room.reactor.rows.values.allSatisfy { $0.spot == nil }, "no row yet")
        XCTAssertGreaterThan(rollMax, 0.06, "they sway on the spot")
        XCTAssertLessThan(drift, 0.2, "nobody walks before the wait is over")
        feed(room, bpm: 100, anchor: anchor, seconds: 1.5)
        XCTAssertNotEqual(room.reactor.cycle.stage, .inPlace, "the walk to the row begins after the wait: \(room.reactor.log)")
        XCTAssertTrue(room.reactor.rows.values.contains { $0.spot != nil })
    }

    /// The whole cycle on a tempo that is stepped on every beat (100) and on one stepped every second beat (150): routines alternate, every plant is on the beat,
    /// the feet never slide or cross, the bodies stay >= 1.2 apart, nothing but the dance moves them, and the music's end puts them back to normal life.
    func testRoutinesLandOnTheBeatAndKeepTheFeetAndBodiesClean() {
        for bpm: Float in [100, 150] { runCycle(bpm: bpm) }
    }

    private func runCycle(bpm: Float) {
        let room = Room(count: 2); Self.keep.append(room)
        room.reactor.rowWaitRange = 5...5
        let anchor = room.now + 0.2, period = 60.0 / Double(bpm)
        room.handle(.musicStarted(EarBeat(bpm: bpm, anchor: anchor, strength: 3)))
        var routines: [EarsRoutine] = []
        var plants: [Double] = [], minBody = Float.infinity, minFeet = Float.infinity, slide: Float = 0, heldAlways = true
        var prevPos: [[SIMD2<Float>]] = room.rigs.map { $0.brain.feet.pos }
        var prevSwing: [(Bool, Int)] = room.rigs.map { _ in (false, 0) }
        var prevStage = EarsReactor.Cycle.Stage.inPlace
        var maxOff: Float = 0
        feed(room, bpm: bpm, anchor: anchor, seconds: 110) {
            let c = room.reactor.cycle
            if c.stage == .routine, prevStage != .routine { routines.append(c.routine) }
            prevStage = c.stage
            let ps = room.rigs.map { GameCare.floorPos($0.brain, $0.sim) }
            if room.reactor.rows.values.allSatisfy({ $0.spot != nil }), c.stage != .inPlace, c.stage != .toRow {
                for i in 0..<ps.count { for j in (i + 1)..<ps.count { minBody = min(minBody, simd_distance(ps[i], ps[j])) } }
            }
            for (i, r) in room.rigs.enumerated() {
                let b = r.brain
                heldAlways = heldAlways && b.held
                if c.stage == .routine, b.danceDrive != nil, b.feetInit {
                    // feet: never crossed (seen from the body), a planted foot never moves
                    let d = rotXZ(b.feet.pos[1] - b.feet.pos[0], -b.yaw).x
                    minFeet = min(minFeet, d)
                    for f in 0..<2 where !(prevSwing[i].0 && prevSwing[i].1 == f) && !(b.feet.swinging && b.feet.side == f) {
                        slide = max(slide, simd_distance(b.feet.pos[f], prevPos[i][f]))
                    }
                    if prevSwing[i].0, !b.feet.swinging { plants.append(room.now) }
                    if i == 0 { maxOff = max(maxOff, simd_distance(ps[0], room.reactor.rows[0]?.spot ?? ps[0])) }
                }
                prevPos[i] = b.feet.pos; prevSwing[i] = (b.feet.swinging, b.feet.side)
            }
        }
        XCTAssertGreaterThanOrEqual(routines.count, 2, "at \(bpm) BPM: two routines in 110 s: \(room.reactor.log)")
        for k in 1..<max(routines.count, 1) { XCTAssertNotEqual(routines[k], routines[k - 1], "a different routine each time") }
        XCTAssertTrue(heldAlways, "held covers the whole dance")
        XCTAssertGreaterThanOrEqual(minBody, 1.2, "bodies stay apart")
        XCTAssertGreaterThan(minFeet, 0.15, "the feet never cross")
        XCTAssertLessThan(slide, 0.002, "a planted foot never slides")
        XCTAssertLessThan(maxOff, 0.35, "the routine returns to the spot")
        // the plants land on the beat grid (the clock's lock follows the grid: within 60 ms; one plant is a foot, the dancers plant together)
        XCTAssertGreaterThan(plants.count, 60, "steps were taken")
        var late = 0
        for t in plants {
            let k = ((t - anchor) / period).rounded()
            if abs(t - (anchor + k * period)) > 0.06 { late += 1 }
        }
        XCTAssertLessThanOrEqual(Double(late) / Double(max(plants.count, 1)), 0.05, "at \(bpm) BPM \(late) of \(plants.count) plants off the beat")
        // the music stops: everything back to normal life
        room.handle(.musicStopped)
        room.run(EarsDance.tail + 3)
        XCTAssertFalse(room.reactor.isDancing)
        for r in room.rigs {
            XCTAssertNil(r.brain.danceDrive); XCTAssertFalse(r.brain.ears.dancing); XCTAssertTrue(r.brain.ears.isNeutral)
            if case .stepInPlace = r.brain.script { XCTFail("still stepping") }
        }
    }

    func testClapsAndWhistlesDoNotPullADancerAway() {
        let room = Room(count: 2); Self.keep.append(room)
        room.handle(.musicStarted(EarBeat(bpm: 100, anchor: room.now, strength: 3)))
        room.run(1)
        room.handle(.heard(.clap)); room.handle(.doubleClap); room.handle(.heard(.whistle)); room.handle(.bang(level: 0.6))
        room.run(4)
        XCTAssertTrue(room.came.isEmpty, "nobody comes while dancing: \(room.came)")
        XCTAssertEqual(room.everyone, 0)
        for i in 0..<2 { XCTAssertNil(room.reactor.anim(of: i)) }
    }

    nonisolated(unsafe) static var keep: [AnyObject] = []
}
