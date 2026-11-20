//
//  RaceDepartTests.swift
//  race-depart-r1 / r2 (owner 2026-11-19): "when I go out on a race the other Jelmikos in the room get race bibs on and that looks buggy. Also don't make the other Jelmikos pause or stall
//  while the one is going to a race they keep doing what they're doing". Only the racer wears a bib (and shoes stay on whoever is at home); the rivals are separate visitor bodies, so the
//  housemates are never woken, moved, scripted or reset: they stay in the room, hidden while the track is up, and are exactly as they were when it ends.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RaceDepartTests: XCTestCase {
    private func room(_ n: Int = 3, runsOut: Bool = false) -> RaceTripTests.Room {
        let r = RaceTripTests.Room(count: n)
        r.spawns = true          // the production path: visitor rival bodies (the headless fallback borrows the housemates)
        r.runsOut = runsOut
        RaceTripTests.keep.append(r)
        r.care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.2)
        r.care.race.autoRate = 8; r.care.race.autoReturnAfter = 0.5
        return r
    }
    private func tick(_ r: RaceTripTests.Room) {
        r.step()
        r.care.tickWear(r.actors, dt: 1.0 / 60)
        for a in r.actors { if let b = a.brain { r.care.syncPerks(id: a.id, brain: b) } }
    }
    private func shown(_ care: GameCare, _ id: Int) -> Bool { care.wardrobe.slot(id)?.bib != nil || care.wardrobe.slot(id)?.jersey != nil }

    /// A housemate never shows a bib or a jersey: not before the swap, not while he is away, not after the return; the three on the track do.
    func testOnlyTheRacersWearNumbersAndNeverAHousemate() {
        for n in [1, 2, 3] {
            let r = room(n); let care = r.care
            care.startRace(jelly: 0, seed: 11)
            var housemateSteps = 0, racerOnTrack = Set<Int>(), sawTrack = false
            for _ in 0..<(150 * 60) {
                tick(r)
                if care.race.trackVisible { sawTrack = true; for id in care.raceBook.racers where care.wardrobe.slot(id)?.bib != nil { racerOnTrack.insert(id) } }
                for id in 1..<max(n, 1) where shown(care, id) { housemateSteps += 1 }
                if !care.race.active && sawTrack { break }
            }
            XCTAssertTrue(sawTrack, "roster \(n)")
            XCTAssertFalse(care.race.active, "roster \(n): the trip is over")
            XCTAssertEqual(housemateSteps, 0, "roster \(n): a housemate never wears a bib or a jersey, in the room or away")
            XCTAssertEqual(racerOnTrack.count, 3, "roster \(n): the racer and the two rival bodies are the ones on the track")
        }
    }

    func testTheRivalsWearTheirNumbersOnTheTrack() {
        let r = room(3); let care = r.care
        care.startRace(jelly: 0, seed: 11)
        for _ in 0..<(12 * 60) { tick(r); if care.race.trackVisible && care.race.cameraBlend == 1 && r.t > 1 { break } }
        for _ in 0..<30 { tick(r) }
        for id in care.raceBook.racers { XCTAssertNotNil(care.wardrobe.slot(id)?.bib, "racer body \(id) wears his numbered bib on the track") }
        XCTAssertEqual(care.raceBook.racers.count, 3)
    }

    /// In the room, before the swap and after the return, a housemate wears exactly what he wore before the tap: every wardrobe slot and his shoes.
    func testHousematesKeepOutfitAndShoesInTheRoomAroundTheRace() {
        let r = room(3); let care = r.care
        let outfits: [Int: [WearLook]] = [1: [.sneakerCoral, .flowerCrown], 2: [.glitterShoes, .crownGold]]
        care.store.saved.wearables = outfits.values.flatMap { $0 }.map(\.rawValue)
        for (id, looks) in outfits { for l in looks { XCTAssertTrue(care.store.wear(l, on: id)) } }
        func snap(_ id: Int) -> [String] {
            let a = r.actors[id]
            var out = WearSlot.allCases.map { "\($0.rawValue)=\(care.wardrobe.slot(id)?.items[$0]?.look?.rawValue ?? "-")" }
            out.append("shoes=\(care.shoeLook(for: a)?.rawValue ?? "-")"); out.append("shod=\(a.brain?.shoesWorn == true)")
            return out
        }
        for _ in 0..<180 { tick(r) }
        let before = [1, 2].map(snap)
        XCTAssertTrue(before[0].contains("shoes=sneakerCoral") && before[1].contains("shoes=glitterShoes"), "the housemates are dressed: \(before)")
        care.startRace(jelly: 0, seed: 11)
        var roomSteps = 0, sawTrack = false, homeSteps = 0
        var bad: [String] = []
        for _ in 0..<(150 * 60) {
            tick(r)
            if care.race.trackVisible { sawTrack = true }
            if !care.race.active { if sawTrack { break }; continue }
            if !care.raceBook.roomAway {
                if sawTrack { homeSteps += 1; if homeSteps <= 1 { continue } }          // (one step for the wardrobe to see the swap home)
                roomSteps += 1
                for (k, id) in [1, 2].enumerated() where snap(id) != before[k] { bad.append("body \(id): \(snap(id)) != \(before[k])") }
            }
        }
        XCTAssertGreaterThan(roomSteps, 20, "the room's fade out and fade in were checked")
        XCTAssertTrue(bad.isEmpty, "a housemate's outfit or shoes changed in the room: \(bad.prefix(2))")
    }

    /// A housemate asleep at the tap is never woken: still asleep, in the same spot and pose, after the return (and through the whole trip).
    func testASleeperStaysAsleepInTheSameSpotAndPose() throws {
        for n in [2, 3] {
            let r = room(n); let care = r.care
            let sleeper = r.actors[1], b = sleeper.brain!
            b.commandedGoodnight = true
            r.run(40) { b.isSleeping && b.sleep.stage >= 4 }
            try XCTSkipUnless(b.isSleeping, "no sleep in this host (the clock / night rest woke him)")
            r.run(3)
            let spot = sleeper.floor, centroid = sleeper.sim.centroid(), stage = b.sleep.stage
            care.startRace(jelly: 0, seed: 11)
            XCTAssertNil(care.raceWait, "roster \(n): a sleeping housemate does not hold the race up")
            var wokeAt: Float?
            var sawTrack = false
            for _ in 0..<(150 * 60) {
                tick(r)
                if !b.isSleeping, wokeAt == nil { wokeAt = r.t }
                if care.race.trackVisible { sawTrack = true }
                if !care.race.active && sawTrack { break }
            }
            XCTAssertTrue(sawTrack, "roster \(n)")
            XCTAssertNil(wokeAt, "roster \(n): the sleeper was never woken")
            XCTAssertTrue(b.isSleeping, "roster \(n): still asleep after the return")
            XCTAssertEqual(b.sleep.stage, stage, "roster \(n): in the same sleep stage")
            XCTAssertLessThan(simd_distance(sleeper.floor, spot), 0.02, "roster \(n): in the same spot")
            let c = sleeper.sim.centroid()
            XCTAssertLessThan(simd_distance(c, centroid), 0.03, "roster \(n): in the same pose (the body is where it was)")
            XCTAssertFalse(care.greetPending.contains(1), "roster \(n): the welcome home does not call the sleeper")
        }
    }

    /// The racer runs out; a housemate who is walking keeps walking until the white (nobody stops, cheers or faces anybody), and is exactly where he was when the track went up once it is over.
    func testAWalkerKeepsWalkingUntilTheWhiteAndIsWhereHeWasAfterTheReturn() throws {
        let r = room(3, runsOut: true); let care = r.care
        for a in r.actors { a.brain?.autonomy = true }
        let walker = r.actors[1]
        walker.brain?.requestNow(.goTo(SIMD2(-2.4, -1.2)))
        r.run(0.3)
        let start = walker.floor
        care.startRace(jelly: 0, seed: 11)
        try XCTSkipUnless(care.outing.running, "no run-out in this host (reduce motion)")
        var moved: Float = 0, last = start, forced: Float = 0, hurry = false
        while !care.raceBook.roomAway, r.t < 60 {
            tick(r)
            let f = walker.floor
            moved += simd_distance(f, last); last = f
            forced = max(forced, walker.brain!.expr.forcedLeft); hurry = hurry || walker.brain!.hurry
            XCTAssertTrue(walker.brain!.autonomy, "his own will stays on")
        }
        XCTAssertGreaterThan(moved, 0.4, "he walked on while the racer ran out")
        XCTAssertLessThan(forced, 1.9, "no forced happy face (hold 2 s): nobody is told to cheer")
        XCTAssertFalse(hurry, "he is not made to hurry")
        let frozen = walker.floor
        for _ in 0..<60 { tick(r) }
        XCTAssertLessThan(simd_distance(walker.floor, frozen), 1e-4, "he is away while the track is up: he does not move")
        var sawTrack = false
        for _ in 0..<(150 * 60) { tick(r); if care.race.trackVisible { sawTrack = true }; if !care.race.active && sawTrack { break } }
        XCTAssertLessThan(simd_distance(walker.floor, frozen), 1.0, "back in the room where he was when the track went up (the welcome home starts him walking over)")
    }

    /// Nobody is told to stand still or cheer: the departure leaves a housemate's expression and timers alone (the race's run-out no longer sends the cheer the other trips keep).
    func testTheRaceRunOutDoesNotForceAFaceOnHousemates() throws {
        let r = room(3, runsOut: true); let care = r.care
        r.run(0.3)          // (the groomer glue lists the bodies on its first tick)
        care.startRace(jelly: 0, seed: 11)
        try XCTSkipUnless(care.outing.running, "no run-out in this host (reduce motion)")
        var forced: Float = 0
        while care.outing.running, r.t < 30 { tick(r); for id in [1, 2] { forced = max(forced, r.actors[id].brain!.expr.forcedLeft) } }
        XCTAssertLessThan(forced, 1.9, "no forced happy face on the housemates during the run-out")
    }
}
