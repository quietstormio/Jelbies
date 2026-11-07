//
//  GroomVarietyTests.swift
//  Spa exit: 15 distinct slogans never repeating back to back; distinct exit emotes per Jelbie; harp once, no crowd cheer.
//
import XCTest
@testable import BobV1

final class GroomVarietyTests: XCTestCase {
    func testSloganBagDistinctAndNeverRepeats() {
        XCTAssertEqual(SpaSlogans.all.count, 15)
        XCTAssertEqual(Set(SpaSlogans.all).count, 15)
        XCTAssertTrue(SpaSlogans.all.contains { $0.hasPrefix("Fit for royalty!") })
        var bag = SpaSlogans.Bag(), g = SystemRandomNumberGenerator()
        var prev = -1, first15 = Set<Int>()
        for n in 0..<100 {
            let i = bag.next(using: &g)
            XCTAssertNotEqual(i, prev, "draw \(n)")
            if n < 15 { first15.insert(i) }
            prev = i
        }
        XCTAssertEqual(first15.count, 15, "the first bag has every slogan once")
    }

    func testExitEmotesAreAllDifferent() {
        var last: [IdleKind] = []
        for seed in 0..<500 {
            var g = SeededGen(seed: UInt64(seed + 1))
            for count in 1...3 {
                let set = SpaExitEmotes.assign(count: count, avoiding: last, using: &g)
                XCTAssertEqual(set.count, count)
                XCTAssertEqual(Set(set).count, count, "seed \(seed) \(set)")
                XCTAssertTrue(set.allSatisfy { SpaExitEmotes.pool.contains($0) })
                if count == 3 { XCTAssertTrue(Set(set).isDisjoint(with: last), "avoids last visit's set"); last = set }
            }
        }
        XCTAssertFalse(SpaExitEmotes.pool.contains { $0.rawValue.lowercased().contains("boop") || $0.rawValue.lowercased().contains("kiss") })
    }

    /// Each pool emote as the FIRST one out (the longest-running position): every Jelbie is handed back (no emote still running) half a second after the end, and roaming resumes.
    @MainActor
    func testEveryPoolEmoteLeavesThemFreeToRoam() throws {
        defer { SpaExitEmotes.forced = nil; RoomLayout.dynamicBoxes = [] }
        for lead in SpaExitEmotes.pool {
            RoomLayout.dynamicBoxes = []
            let aspect: Float = 603.0 / 1311.0
            GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: aspect); GameCamera.refreshRoam(aspect: aspect)
            let r = FocusAnyRun(count: 3, peers: true)
            W2CaptureTests.keep.append(r.care); W2CaptureTests.keep.append(r)
            let care = r.care
            care.bath.wallet.add(500, silent: true)
            for (i, a) in r.actors.enumerated() { a.brain?.autonomy = true; a.brain?.restTimer = 1e6; r.place(i, at: JellyRoster.spawnSpots(count: 3)[i]) }
            for _ in 0..<60 { r.tick() }
            let dt = r.actors[0].sim.stepDt
            care.groomBook.fixedDt = dt
            SpaExitEmotes.forced = [lead] + SpaExitEmotes.pool.filter { $0 != lead }.prefix(2)
            care.groom.openPicker(all: [0, 1, 2]); care.groom.begin(.quick)
            var t: Float = 0, doneT: Float?, n = 0
            var walked = Set<Int>(), handedBack = false
            while n < 60 * 40 {
                r.tick(); care.tickGroom(r.actors, dt: dt); t += dt; n += 1
                if doneT == nil, !care.groom.active, n > 60 { doneT = t }
                if let d = doneT, !handedBack, t - d >= 0.5 {
                    handedBack = true
                    for a in r.actors { let b = a.brain!; XCTAssertTrue(b.autonomy && !b.idleBlocked && b.commandedIdle == nil && b.idleState.kind == nil, "\(lead): \(a.id) is free again (no exit emote still running)") }
                }
                if let d = doneT, t - d <= 10 { for a in r.actors where a.isWalking { walked.insert(a.id) } }
                if let d = doneT, t - d > 10 { break }
            }
            XCTAssertNotNil(doneT, "\(lead): visit ended")
            print("POOLEMOTE \(lead) roaming=\(walked.sorted())")
            XCTAssertTrue(handedBack)
            XCTAssertGreaterThanOrEqual(walked.count, 2, "\(lead) first out: roaming resumes (autonomy picks the moment) \(walked.sorted())")
        }
    }

    @MainActor
    func testExitPlaysHarpOnceAndNoCheer() throws {
        RoomLayout.dynamicBoxes = []
        let aspect: Float = 603.0 / 1311.0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: aspect); GameCamera.refreshRoam(aspect: aspect)
        let r = FocusAnyRun(count: 3, peers: true)
        W2CaptureTests.keep.append(r.care); W2CaptureTests.keep.append(r)
        let care = r.care
        care.bath.wallet.add(500, silent: true)
        for (i, a) in r.actors.enumerated() { a.brain?.autonomy = true; a.brain?.restTimer = 1e6; r.place(i, at: JellyRoster.spawnSpots(count: 3)[i]) }
        for _ in 0..<60 { r.tick() }
        care.groomBook.fixedDt = r.actors[0].sim.stepDt
        var seen: [String] = []
        AudioHub.requestTap = { seen.append($0) }
        defer { AudioHub.requestTap = nil }
        care.groom.openPicker(all: [0, 1, 2]); care.groom.begin(.quick)
        var emotesAtArrival = Set<IdleKind>()
        var n = 0
        while n < 60 * 40 {
            r.tick(); care.tickGroom(r.actors, dt: care.groomBook.fixedDt ?? 1.0 / 60); n += 1
            if care.groom.phase == .reveal, emotesAtArrival.isEmpty { emotesAtArrival = Set(care.groomBook.emote.values) }
            if !care.groom.active, n > 60 { break }
        }
        XCTAssertEqual(seen.filter { $0 == "clip:groom_harp" }.count, 1, "harp once per exit")
        XCTAssertEqual(seen.filter { $0 == "cheer_small" }.count, 0, "no yay / crowd cheer")
        XCTAssertEqual(emotesAtArrival.count, 3, "three different emotes")
        XCTAssertFalse(care.groom.slogan.isEmpty)
    }
}

struct SeededGen: RandomNumberGenerator {
    var s: UInt64
    init(seed: UInt64) { s = seed }
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}
