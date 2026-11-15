//
//  RoomRoamStaleWallTests.swift
//  A body's round wall is lifted (infinity) for a race, a Show and the bath's exit run, and used to come back from the SAVED RADIUS ALONE. When the roaming floor was
//  rebuilt meanwhile (a rotation, or the rivals' first floor) the old wall sat under the new floor (front row outside the wall: the body is dragged off its feet).
//  Now a finite saved wall comes back as the floor's arena AS IT IS NOW (centre and radius); with no floor, or a wall that was lifted before the trip, the old line runs.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RoomRoamStaleWallTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private static let landscape: Float = 852 / 393
    private static let portrait: Float = 393 / 852

    /// Everything these tests change in the camera's statics; `restore` puts it back.
    private struct Globals {
        let floor = GameCamera.roamFloor, centre = GameCamera.arenaCenter, radius = GameCamera.arenaRadius, walkMaxZ = GameCamera.walkMaxZ
        @MainActor func restore() {
            GameCamera.configureRoom(count: 1)
            if let f = floor { GameCamera.roamFloor = f; RoomLayout.setFront(z: f.maxZ + 0.8) } else { GameCamera.clearRoam() }
            GameCamera.arenaCenter = centre; GameCamera.arenaRadius = radius; GameCamera.walkMaxZ = walkMaxZ
        }
    }

    /// radius - the farthest distance from `centre` to a row end point of `floor`: 0.90 when the wall is the floor's own arena (`RoamFloor.arena`), < 0 when a row end is outside.
    private func farMargin(_ centre: SIMD2<Float>, _ radius: Float, _ floor: GameCamera.RoamFloor) -> Float {
        var far: Float = 0
        for (z, h) in zip(floor.zs, floor.hw) { far = max(far, simd_distance(centre, SIMD2(h, z)), simd_distance(centre, SIMD2(-h, z))) }
        return radius - far
    }

    private func apply(_ room: RaceThreeTests.Room) {
        MelonController.applyRoomArena(actors: room.actors, parkActors: room.park, bathFenceLifted: false)
    }

    /// One creature at home on the LANDSCAPE floor.
    private func landscapeRoom() -> RaceThreeTests.Room {
        GameCamera.configureRoom(count: 1)
        XCTAssertNotNil(GameCamera.refreshRoam(aspect: Self.landscape))
        let room = RaceThreeTests.Room(count: 1)
        Self.keep.append(room)
        return room
    }

    /// What the rotated floor and the restored wall must show (the shared assertions of the three trips).
    private func assertWallIsTheFloorsNow(_ sim: SoftBody, staleCentre: SIMD2<Float>, staleRadius: Float, portraitFloor: GameCamera.RoamFloor, _ what: String) {
        XCTAssertEqual(sim.arenaCenter, GameCamera.arenaCenter, "\(what): centre is the floor's now")
        XCTAssertEqual(sim.arenaRadius, GameCamera.arenaRadius, "\(what): radius is the floor's now")
        XCTAssertGreaterThanOrEqual(farMargin(sim.arenaCenter, sim.arenaRadius, portraitFloor), 0.90 - 0.001, "\(what): every row end of the floor is inside the wall")
        XCTAssertLessThan(farMargin(staleCentre, staleRadius, portraitFloor), 0, "\(what): the wall saved under the landscape floor would leave a row end outside the portrait floor (the bug)")
    }

    func testRaceRestoresTheWallOfTheFloorAsItIsNow() {
        let g = Globals(); defer { g.restore() }
        let room = landscapeRoom()
        let care = room.care, sim = room.actors[0].sim
        apply(room)
        let c0 = sim.arenaCenter, r0 = sim.arenaRadius
        XCTAssertTrue(r0.isFinite); XCTAssertEqual(c0, GameCamera.arenaCenter); XCTAssertEqual(r0, GameCamera.arenaRadius)
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.2)
        care.race.autoRate = 8; care.race.autoReturnAfter = 0.5
        care.startRace(jelly: 0, seed: 11)
        room.run(6) { care.race.trackVisible && care.raceBook.racers.count > 0 }
        XCTAssertTrue(care.race.trackVisible)
        XCTAssertEqual(sim.arenaRadius, .infinity, "the track lifts his wall")
        // rotate to portrait while the wall is lifted
        let portrait = GameCamera.refreshRoam(aspect: Self.portrait)
        XCTAssertNotNil(portrait)
        apply(room)
        XCTAssertEqual(sim.arenaRadius, .infinity, "the stage's wall step leaves a racer's lifted wall alone")
        room.run(200) { !care.race.active && care.raceBook.extra.isEmpty }          // the race plays itself and brings him home (autoRate, autoReturnAfter)
        XCTAssertFalse(care.race.active, "the trip is over")
        assertWallIsTheFloorsNow(sim, staleCentre: c0, staleRadius: r0, portraitFloor: portrait!, "race")
    }

    func testShowRestoresTheWallOfTheFloorAsItIsNow() {
        let g = Globals(); defer { g.restore() }
        let room = landscapeRoom()
        let care = room.care, sim = room.actors[0].sim
        apply(room)
        let c0 = sim.arenaCenter, r0 = sim.arenaRadius
        XCTAssertTrue(r0.isFinite)
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }
        func step() { room.step(); care.tickShow(room.actors, dt: sim.stepDt) }
        care.startShow(jelly: 0, seed: 3)
        XCTAssertTrue(care.show.active, "the show started")
        for _ in 0..<(8 * 60) { step(); if care.show.phase == .stage { break } }
        XCTAssertEqual(care.show.phase, .stage)
        XCTAssertEqual(sim.arenaRadius, .infinity, "the stage lifts his wall")
        let portrait = GameCamera.refreshRoam(aspect: Self.portrait)
        XCTAssertNotNil(portrait)
        apply(room)
        XCTAssertEqual(sim.arenaRadius, .infinity)
        care.show.goHome()          // "Done": the show's own way home (fade out, swap under the white, fade in)
        for _ in 0..<(12 * 60) { step(); if !care.show.active { break } }
        XCTAssertFalse(care.show.active, "he is back in the room")
        assertWallIsTheFloorsNow(sim, staleCentre: c0, staleRadius: r0, portraitFloor: portrait!, "show")
    }

    func testBathFenceRestoresTheWallOfTheFloorAsItIsNow() {
        let g = Globals(); defer { g.restore() }
        GameCamera.configureRoom(count: 1)
        XCTAssertNotNil(GameCamera.refreshRoam(aspect: Self.landscape))
        let run = CleanRun(dirt: 0.5)          // (one body, the real GameCare + BathFlow; its sim wall starts as the floor's)
        Self.keep.append(run)
        let sim = run.sim
        let c0 = sim.arenaCenter, r0 = sim.arenaRadius
        XCTAssertTrue(r0.isFinite); XCTAssertEqual(c0, GameCamera.arenaCenter)
        run.care.bath.start(brain: run.brain)
        for _ in 0..<5 { run.tick(probe: false) }
        XCTAssertTrue(run.bath.fenceLifted)
        XCTAssertEqual(run.bath.phase, .exit)
        XCTAssertEqual(sim.arenaRadius, .infinity, "the exit run lifts the fence")
        let portrait = GameCamera.refreshRoam(aspect: Self.portrait)          // (a stage with a bath body would run the room's wall step with bathFenceLifted: it skips him; there is no stage here)
        XCTAssertNotNil(portrait)
        run.care.bath.cancel(brain: run.brain, sim: sim)          // he is still inside the floor: the fence goes back at once
        for _ in 0..<5 { run.tick(probe: false) }
        XCTAssertFalse(run.bath.fenceLifted, "the fence is back")
        assertWallIsTheFloorsNow(sim, staleCentre: c0, staleRadius: r0, portraitFloor: portrait!, "bath")
    }

    func testNoFloorKeepsTheSavedRadius() {
        let g = Globals(); defer { g.restore() }
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam()
        XCTAssertNil(GameCamera.roamFloor)
        let room = RaceThreeTests.Room(count: 1)
        Self.keep.append(room)
        let care = room.care, sim = room.actors[0].sim
        sim.arenaCenter = SIMD2<Float>(0, 0.8); sim.arenaRadius = 3.9          // a recognisable wall that is NOT the camera's
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.2)
        care.race.autoRate = 8; care.race.autoReturnAfter = 0.5
        care.startRace(jelly: 0, seed: 11)
        room.run(6) { care.race.trackVisible && care.raceBook.racers.count > 0 }
        XCTAssertEqual(sim.arenaRadius, .infinity)
        room.run(200) { !care.race.active && care.raceBook.extra.isEmpty }
        XCTAssertFalse(care.race.active)
        XCTAssertEqual(sim.arenaRadius, 3.9, "no floor: the saved radius, as before")
        XCTAssertEqual(sim.arenaCenter, SIMD2<Float>(0, 0.8), "no floor: the centre is not touched")
    }

    func testAWallLiftedBeforeTheTripStaysLifted() {
        let g = Globals(); defer { g.restore() }
        let room = landscapeRoom()          // a floor exists, so only the "finite" half of the rule keeps this one lifted
        let care = room.care, sim = room.actors[0].sim
        sim.arenaRadius = .infinity
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.2)
        care.race.autoRate = 8; care.race.autoReturnAfter = 0.5
        care.startRace(jelly: 0, seed: 11)
        room.run(6) { care.race.trackVisible && care.raceBook.racers.count > 0 }
        room.run(200) { !care.race.active && care.raceBook.extra.isEmpty }
        XCTAssertFalse(care.race.active)
        XCTAssertEqual(sim.arenaRadius, .infinity, "a wall that was lifted before the race is lifted after it")
    }
}
