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

    /// race-depart-r1 follow-up: the same rule for what else a housemate wears. In the room, before the swap to the track and after the return, a stay-home Jelmiko wears exactly what he wore before the tap:
    /// every wardrobe slot, his shoes (`shoeLook`) and the brain's `shoesWorn`. (Base: `shoeLook` and `syncPerks` hid the shoes of every body that was not the player the moment the trip began.)
    func testHousematesKeepOutfitAndShoesInTheRoomAroundTheRace() {
        let room = RaceTripTests.Room(count: 3)
        RaceTripTests.keep.append(room)
        let care = room.care
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.2)
        care.race.autoRate = 8; care.race.autoReturnAfter = 0.5
        let outfits: [Int: [WearLook]] = [1: [.sneakerCoral, .flowerCrown], 2: [.glitterShoes, .crownGold]]
        care.store.saved.wearables = outfits.values.flatMap { $0 }.map(\.rawValue)
        for (id, looks) in outfits { for l in looks { XCTAssertTrue(care.store.wear(l, on: id)) } }
        func tick() {
            room.step()
            care.tickWear(room.actors, dt: 1.0 / 60)
            for a in room.actors { if let b = a.brain { care.syncPerks(id: a.id, brain: b) } }
        }
        func snap(_ id: Int) -> [String] {
            let a = room.actors[id]
            var out = WearSlot.allCases.map { "\($0.rawValue)=\(care.wardrobe.slot(id)?.items[$0]?.look?.rawValue ?? "-")" }
            out.append("shoes=\(care.shoeLook(for: a)?.rawValue ?? "-")"); out.append("shod=\(a.brain?.shoesWorn == true)")
            return out
        }
        for _ in 0..<180 { tick() }
        let before = [1, 2].map(snap)
        XCTAssertTrue(before[0].contains("shoes=sneakerCoral") && before[1].contains("shoes=glitterShoes"), "the housemates are dressed: \(before)")
        care.startRace(jelly: 0, seed: 11)
        var roomSteps = 0, sawTrack = false, backSteps = 0
        var bad: [String] = []
        for _ in 0..<(150 * 60) {
            tick()
            if care.race.trackVisible { sawTrack = true }
            if !care.race.active { if sawTrack { break }; continue }
            if care.raceBook.onTrack.isEmpty {                       // the room: before the swap, or (onTrack cleared) after the return
                if sawTrack { backSteps += 1; if backSteps <= 1 { continue } }          // (one step for the wardrobe to see the swap home)
                roomSteps += 1
                for (k, id) in [1, 2].enumerated() where snap(id) != before[k] { bad.append("body \(id): \(snap(id)) != \(before[k])") }
            }
        }
        XCTAssertGreaterThan(roomSteps, 20, "the room's fade out and fade in were checked")
        XCTAssertTrue(bad.isEmpty, "a housemate's outfit or shoes changed in the room: \(bad.prefix(2))")
    }
}
