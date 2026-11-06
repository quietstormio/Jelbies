//
//  RaceThreeTests.swift
//  The track meet is always three racers (the player + two rivals), whatever the roster: a roster of 1 or 2 borrows temporary rival bodies (the park's visitor bodies) for the
//  race and gives them back when it ends or is quit. A roster of 3 is unchanged.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RaceThreeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// A roster of `count` Jelbies ticked like the stage does, plus the stage's spare "park" bodies (what `parkBook.spawn` hands out).
    @MainActor
    final class Room {
        let care: GameCare
        let actors: [JellyActor]
        var park: [JellyActor] = []
        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        init(count: Int) {
            let d = UserDefaults(suiteName: "RaceThree.\(UUID().uuidString)")!
            let care = GameCare(jellyCount: count, persistent: false, defaults: d)
            self.care = care
            let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
            let spots = JellyRoster.spawnSpots(count: count)
            let sm = self.sm, rm = self.rm
            actors = (0..<count).map {
                let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
                a.profile = care.jelly($0); a.care = care
                a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius
                a.reset(drop: 0.35, shift: true)
                let b = BlobBrain.forGame()
                b.demo = nil; b.runMoveDemo = nil; b.autonomy = false
                b.steerID = $0
                care.wireWorld(b, isBob: $0 == 0)
                b.attach(renderMesh: rm, synchronous: true)
                a.brain = b
                b.currentPose(a.sim)
                return a
            }
            care.race.cue = { _ in }
            care.parkBook.spawn = { [unowned self] specs, spots in
                self.park.removeAll()
                for (k, v) in specs.enumerated() {
                    let a = JellyActor(id: self.actors.count + k, name: v.name, simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[k])
                    a.care = care
                    let b = BlobBrain.forGame()
                    b.demo = nil; b.runMoveDemo = nil; b.autonomy = true
                    b.steerID = a.id
                    care.wireWorld(b, isBob: false)
                    b.attach(renderMesh: rm, synchronous: true)
                    a.brain = b
                    b.feature = v.signature
                    b.currentPose(a.sim)
                    self.park.append(a)
                }
                return self.park
            }
            care.parkBook.clear = { [unowned self] in self.park.removeAll() }
            for _ in 0..<120 { step() }
        }
        func step() {
            let dt = actors[0].sim.stepDt
            for a in actors + park {
                a.brain?.tick(sim: a.sim, skinner: a.skinner, dt: dt, touched: false)
                a.skinner.jelly.tick(brain: a.brain!, sim: a.sim, dt: dt)
            }
            care.tick(brain: actors[0].brain!, renderer: nil, dt: dt, sim: actors[0].sim)
            care.tickOthers(actors, dt: dt)
            care.tickRace(actors, dt: dt)
            for a in actors + park { a.sim.step() }
        }
        func run(_ s: Float, until: (() -> Bool)? = nil) { for _ in 0..<Int(s * 60) { step(); if let u = until, u() { break } } }
    }

    func testRivalBodiesNeededByRosterSize() {
        XCTAssertEqual(GameCare.raceRivalCount, 2)
        XCTAssertEqual(GameCare.temporaryRivalBodies(roster: 1), 2)
        XCTAssertEqual(GameCare.temporaryRivalBodies(roster: 2), 1)
        XCTAssertEqual(GameCare.temporaryRivalBodies(roster: 3), 0)
        XCTAssertEqual(GameCare.temporaryRivalBodies(roster: 4), 0)
    }

    func testSignatureFollowsTheColourSpecies() {
        XCTAssertEqual(LocalRivalSource.signature(forTint: LocalRivalSource.hsv(0.76, 0.34, 0.96)), .wings, "lilac / purple = wings")
        XCTAssertEqual(LocalRivalSource.signature(forTint: LocalRivalSource.hsv(0.68, 0.34, 0.96)), .wings)
        XCTAssertEqual(LocalRivalSource.signature(forTint: LocalRivalSource.hsv(0.22, 0.34, 0.96)), .daisy, "lime / green = daisy")
        XCTAssertEqual(LocalRivalSource.signature(forTint: LocalRivalSource.hsv(0.13, 0.34, 0.96)), .spines, "yellow = tail + spikes")
        for h in [Float(0.93), 0.05, 0.50] { XCTAssertEqual(LocalRivalSource.signature(forTint: LocalRivalSource.hsv(h, 0.34, 0.96)), JellyFeature.none, "pink / peach / aqua = none") }
    }

    private func raceThrough(roster n: Int) {
        let room = Room(count: n)
        Self.keep.append(room)
        let care = room.care
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.2)
        care.race.autoRate = 8; care.race.autoReturnAfter = 0.5
        XCTAssertTrue(care.canRace(jelly: 0))
        care.startRace(jelly: 0, seed: 11)
        room.run(4) { care.race.trackVisible && care.raceBook.racers.count > 0 }
        XCTAssertTrue(care.race.trackVisible, "roster \(n)")
        let sim = care.race.sim!
        XCTAssertEqual(care.race.rivals.count, 2, "roster \(n): always two rivals")
        XCTAssertEqual(sim.racers.count, 3, "roster \(n): three racers")
        XCTAssertEqual(care.raceBook.racers.count, 3, "roster \(n): three bodies on the track")
        XCTAssertEqual(Set(care.raceBook.racers).count, 3, "roster \(n): three different bodies")
        XCTAssertEqual(Set(sim.racers.map(\.lane)).count, 3, "roster \(n): three lanes filled")
        XCTAssertEqual(care.raceBook.racers.first, 0, "the player's own Jelbie is the player lane")
        XCTAssertEqual(care.raceBook.extra.count, 3 - n, "roster \(n): temporary rivals = \(3 - n)")
        XCTAssertEqual(room.park.count, 3 - n)
        let all = room.actors + room.park
        for (k, aid) in care.raceBook.racers.enumerated() {
            let a = all[aid]
            XCTAssertEqual(a.sim.centroid().x, RaceTuning.laneX(sim.racers[k].lane), accuracy: 0.35, "roster \(n): racer \(k) on his lane")
            XCTAssertTrue(a.brain!.race.active, "roster \(n): racer \(k) runs the race script")
            if k > 0 { XCTAssertNotNil(care.racePalette(for: aid), "rival \(k) is tinted"); XCTAssertEqual(care.wearRole(for: aid), .rival(team: WearTeam.rivals[(k - 1) % WearTeam.rivals.count], number: WearTeam.rivalNumbers[(k - 1) % WearTeam.rivalNumbers.count]), "rival \(k) has his jersey") }
        }
        for (a, v) in zip(care.raceBook.extra, care.raceBook.extraSpecs) {
            XCTAssertTrue(care.race.rivals.contains { $0.name == v.name }, "named from the race's rivals")
            XCTAssertEqual(v.name, a.name)
            XCTAssertEqual(v.signature, LocalRivalSource.signature(forTint: care.race.rivals.first { $0.name == v.name }!.tint))
            XCTAssertEqual(a.brain!.feature, v.signature)
        }
        let rosterBefore = care.jellies.count
        // the race runs and the player is back home by himself
        room.run(120) { !care.race.active && care.raceBook.extra.isEmpty && !care.race.trackVisible }
        XCTAssertFalse(care.race.active, "roster \(n): the trip is over")
        XCTAssertTrue(care.raceBook.extra.isEmpty, "roster \(n): no temporary bodies left")
        XCTAssertTrue(room.park.isEmpty, "roster \(n): the spare bodies are given back")
        XCTAssertTrue(care.raceBook.extraSpecs.isEmpty)
        XCTAssertEqual(care.raceBook.racers.count, n, "roster \(n): only the roster's own bodies remain")
        XCTAssertTrue(care.raceBook.palettes.isEmpty)
        XCTAssertEqual(care.jellies.count, rosterBefore, "no roster change")
        XCTAssertEqual(care.jellies.count, n)
    }

    func testRosterOfOneRacesThreeAndGivesTheBodiesBack() { raceThrough(roster: 1) }
    func testRosterOfTwoRacesThreeAndGivesTheBodyBack() { raceThrough(roster: 2) }
    func testRosterOfThreeIsUnchanged() { raceThrough(roster: 3) }

    func testQuitAlsoGivesTheBodiesBack() {
        let room = Room(count: 1)
        Self.keep.append(room)
        let care = room.care
        care.startRace(jelly: 0, seed: 5)
        room.run(4) { care.race.trackVisible && !care.raceBook.extra.isEmpty }
        XCTAssertEqual(care.raceBook.extra.count, 2)
        care.race.abort()
        room.run(8) { !care.race.active && care.raceBook.extra.isEmpty }
        XCTAssertTrue(care.raceBook.extra.isEmpty, "quit: no bodies left")
        XCTAssertTrue(room.park.isEmpty)
    }
}
