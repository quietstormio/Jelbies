//
//  RaceDepartTests.swift
//  race-depart-r1 (owner 2026-11-19): "when I go out on a race the other Jelmikos in the room get race bibs on and that looks buggy". Only the racer's own bib shows while the
//  room is on screen; the housemates get a jersey and number only once they are on the track (they are the rivals there), never in the room's fade out / in.
//

import XCTest
@testable import BobV1

@MainActor
final class RaceDepartTests: XCTestCase {
    private func bibShown(_ care: GameCare, _ id: Int) -> Bool { care.wardrobe.slot(id)?.bib != nil || care.wardrobe.slot(id)?.jersey != nil }

    /// Runs a whole race for Jelly 0 and counts, per housemate, the steps with a bib / jersey drawn while the ROOM is what is on screen.
    private func inRoomBibSteps(roster n: Int) -> (out: [Int: Int], back: [Int: Int], sawOnTrack: Bool) {
        let room = RaceTripTests.Room(count: n)
        RaceTripTests.keep.append(room)
        let care = room.care
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.2)
        care.race.autoRate = 8; care.race.autoReturnAfter = 0.5
        for a in room.actors { a.brain?.autonomy = true }
        var out: [Int: Int] = [:], back: [Int: Int] = [:]
        var sawTrack = false, sawRival = false
        care.startRace(jelly: 0, seed: 11)
        for _ in 0..<(150 * 60) {
            room.step(); care.tickWear(room.actors, dt: 1.0 / 60)          // (the stage ticks the wardrobe after the bodies; the test room does not)
            if care.race.trackVisible { sawTrack = true; if (1..<n).contains(where: { bibShown(care, $0) }) || care.wardrobe.slot(0)?.bib != nil { sawRival = true } }
            guard care.race.active, !care.race.trackVisible else { if !care.race.active && sawTrack { break }; continue }
            for id in 1..<n where bibShown(care, id) { if sawTrack { back[id, default: 0] += 1 } else { out[id, default: 0] += 1 } }
        }
        XCTAssertTrue(sawTrack, "roster \(n): the race reached the track")
        XCTAssertFalse(care.race.active, "roster \(n): the trip is over")
        _ = sawRival
        return (out, back, sawTrack)
    }

    func testHousematesWearNoBibInTheRoomWhileAnotherRaces() {
        for n in [2, 3] {
            let r = inRoomBibSteps(roster: n)
            XCTAssertTrue(r.out.isEmpty, "roster \(n): no bib on a housemate in the room's fade out: \(r.out)")
            XCTAssertTrue(r.back.isEmpty, "roster \(n): no bib on a housemate in the room's fade in: \(r.back)")
        }
    }

    func testTheRivalsStillWearTheirNumbersOnTheTrack() {
        let room = RaceTripTests.Room(count: 3)
        RaceTripTests.keep.append(room)
        let care = room.care
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.2)
        care.startRace(jelly: 0, seed: 11)
        for _ in 0..<(12 * 60) { room.step(); care.tickWear(room.actors, dt: 1.0 / 60); if care.race.trackVisible && care.race.cameraBlend == 1 && room.t > 1 { break } }
        for _ in 0..<30 { room.step(); care.tickWear(room.actors, dt: 1.0 / 60) }
        for id in 0..<3 { XCTAssertNotNil(care.wardrobe.slot(id)?.bib, "racer body \(id) wears his numbered bib on the track") }
    }
}
