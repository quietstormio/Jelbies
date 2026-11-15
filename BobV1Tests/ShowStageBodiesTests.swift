//
//  ShowStageBodiesTests.swift
//  The Jelly Show's stage has ONE roster body (the contestant); every other entrant is a borrowed visitor body; every other home Jelmiko waits off stage
//  (parked) and is back, with its autonomy, after the Show (also after an aborted one).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ShowStageBodiesTests: XCTestCase {
    private func ready(_ care: GameCare) {
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.danceSongPrepared = { _ in true }
        care.show.prepareDanceSong = { _ in }; care.show.releaseDanceSong = {}; care.show.cue = { _ in }
    }
    private func step(_ room: RaceThreeTests.Room) {
        for a in room.actors + room.park { if let b = a.brain { b.tick(sim: a.sim, skinner: a.skinner, dt: a.sim.stepDt, touched: false) } }
        room.care.tickRace(room.actors, dt: 1 / 60)
        room.care.tickShow(room.actors, dt: 1 / 60)
    }
    private func run(_ room: RaceThreeTests.Room, _ s: Float, until: () -> Bool = { false }) { for _ in 0..<Int(s * 60) { step(room); if until() { return } } }

    /// No two off-stage spots, stage spots, rest spots or visitor spawn spots are closer than two body radii (0.7 each) plus room, for every contestant.
    func testNoTwoStageSpotsOverlap() {
        var spots: [(String, SIMD2<Float>)] = []
        for k in 0..<4 { spots.append(("stage\(k)", ShowStage.spots(bodies: 4)[k])) }
        spots.append(("aside", ShowStage.playerAside))
        for k in 0..<3 { spots.append(("rest\(k)", ShowStage.rivalRest(k))) }
        for j in 0..<3 { spots.append(("far\(j)", GameCare.showFarSpot(j))); spots.append(("spawn\(j)", SIMD2(40 + Float(j) * 3, 0))) }
        for id in 0..<6 { spots.append(("park\(id)", ShowStage.parkSpot(id))) }
        for i in spots.indices { for j in spots.indices where j > i {
            let (a, b) = (spots[i], spots[j])
            if a.0 == "stage0" && b.0 == "stage0" { continue }
            XCTAssertGreaterThan(simd_distance(a.1, b.1), 1.5, "\(a.0) and \(b.0) overlap")
        } }
        for id in 0..<6 { XCTAssertTrue(ShowStage.parkSpot(id).y >= GameCamera.walkMinZ && ShowStage.parkSpot(id).y <= GameCamera.walkMaxZ, "park spot inside the floor's depth range") }
    }

    private func oneShow(count: Int, player: Int, abort: Bool) {
        let room = RaceThreeTests.Room(count: count)
        RaceThreeTests.keep.append(room)
        let care = room.care
        ready(care)
        var homes: [Int: SIMD2<Float>] = [:]
        for a in room.actors { homes[a.id] = a.floor }
        let auto: [Int: Bool] = Dictionary(uniqueKeysWithValues: room.actors.map { ($0.id, true) })
        for a in room.actors { a.brain?.autonomy = true }
        care.startShow(jelly: player, rank: .puddle, seed: 5)
        run(room, 6) { care.show.onStage }
        XCTAssertTrue(care.show.onStage, "\(count) at home")
        let book = care.showBook
        XCTAssertEqual(book.performers, [player], "one roster body on the stage (\(count) at home)")
        XCTAssertEqual(Set(book.parked), Set(room.actors.indices.filter { $0 != player }))
        XCTAssertEqual(book.extra.count, 3, "three borrowed entrants (\(count) at home)")
        XCTAssertEqual(Set(book.rivalBody.values), Set(book.extra.map(\.id)), "every entrant is a borrowed body")
        for id in book.parked { XCTAssertTrue(care.showHides(id), "parked bodies are never drawn"); XCTAssertTrue(care.showHidesWear(id)) }
        XCTAssertFalse(care.showHides(player))
        for a in book.extra { XCTAssertTrue(care.showHides(a.id), "hidden outside the wide Trick shot") }
        // nobody overlaps: every body that exists is at least 1.5 apart
        func spread() {
            let all = room.actors + book.extra
            for i in all.indices { for j in all.indices where j > i { XCTAssertGreaterThan(simd_distance(all[i].floor, all[j].floor), 1.4, "bodies \(all[i].id) and \(all[j].id) overlap") } }
        }
        spread()
        let parkedAt = Dictionary(uniqueKeysWithValues: book.parked.map { ($0, room.actors[$0].floor) })
        for (id, p) in parkedAt { XCTAssertLessThan(simd_distance(p, ShowStage.parkSpot(id)), 0.6) }
        if abort {
            run(room, 2)
            care.show.abort()
        } else {
            care.show.auto = true
            run(room, 130) { care.show.trickStage == .rivals }
            XCTAssertEqual(care.show.trickStage, .rivals)
            for (id, p) in parkedAt { XCTAssertLessThan(simd_distance(room.actors[id].floor, p), 0.6, "parked body \(id) has not moved") ; XCTAssertTrue(care.showHides(id)) }
            for a in book.extra { XCTAssertFalse(care.showHides(a.id)) }
            spread()
            care.show.abort()
        }
        XCTAssertFalse(care.show.active)
        XCTAssertTrue(book.parked.isEmpty); XCTAssertTrue(book.extra.isEmpty); XCTAssertTrue(room.park.isEmpty)
        var seen: [SIMD2<Float>] = []
        for a in room.actors {
            guard let b = a.brain else { continue }
            XCTAssertEqual(b.autonomy, auto[a.id], "Jelmiko \(a.id) has its autonomy back")
            XCTAssertFalse(b.idleBlocked)
            XCTAssertEqual(a.sim.arenaRadius, GameCamera.arenaRadius, accuracy: 1e-3)
            let f = a.floor
            XCTAssertLessThan(simd_distance(f, GameCamera.arenaCenter), GameCamera.arenaRadius + 0.5, "Jelmiko \(a.id) is back in the room")
            for g in seen { XCTAssertGreaterThan(simd_distance(f, g), 1.0, "Jelmiko \(a.id) has its own spot") }
            seen.append(f)
            // a home Jelmiko is back where it stood, unless that is the contestant's come-home spot (then the existing return path moves it aside)
            if a.id != player, let h = homes[a.id], simd_distance(h, VoiceCoordinator.comeSpot) >= 1.5 { XCTAssertLessThan(simd_distance(f, b.fixed(h)), 0.8, "Jelmiko \(a.id) is back at its home spot") }
        }
        run(room, 2)          // settles without a jump
        for a in room.actors { XCTAssertLessThan(simd_distance(a.floor, seen[a.id]), 0.8, "no jump after the return") }
    }

    func testOneTwoThreeAtHome() {
        for count in 1...3 { oneShow(count: count, player: 0, abort: false) }
    }
    func testContestantNotFirstAtHome() {
        oneShow(count: 3, player: 1, abort: false)
        oneShow(count: 2, player: 1, abort: false)
    }
    func testAbortedShow() {
        for count in 1...3 { oneShow(count: count, player: count - 1, abort: true) }
    }
}
