//
//  CampTripTests.swift
//  camp-yard-r1 step Y3: the Camp visit as a mode of the park trip: the phases, the six spawn spots, the cap of 6, nothing ticked or saved for a Camp creature, the home room as it was.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CampTripTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    var savedSource: (() -> [CampCreature])!

    override func setUp() { savedSource = GameCare.campSource }
    override func tearDown() {
        GameCare.campSource = savedSource; CampBook.shared.spawn = nil; CampBook.shared.bodies = [:]; JellyRoster.visitBodies = [:]
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    // MARK: the state machine

    func testPhasesOfACampTrip() {
        let t = ParkTrip()
        var swaps: [ParkTrip.Dest] = [], placeAtSwap: [ParkTrip.Place] = []
        t.onSwap = { swaps.append($0); placeAtSwap.append(t.place) }
        XCTAssertEqual(t.place, .park)
        t.beginCamp()
        XCTAssertEqual(t.phase, .goOut); XCTAssertEqual(t.place, .camp); XCTAssertTrue(t.picked.isEmpty)
        var guardN = 0
        while t.phase != .playing, guardN < 2000 { t.step(dt: 1.0 / 60); guardN += 1 }
        XCTAssertEqual(t.phase, .playing); XCTAssertEqual(swaps, [.park]); XCTAssertTrue(t.inScene)
        t.goHome()
        guardN = 0
        while t.phase != .off, guardN < 2000 { t.step(dt: 1.0 / 60); guardN += 1 }
        XCTAssertEqual(swaps, [.park, .home]); XCTAssertEqual(placeAtSwap, [.camp, .camp], "both swaps ran as Camp swaps")
        XCTAssertEqual(t.place, .park, "back to the park's default once the trip is over")
        t.beginCamp(); t.beginCamp()
        XCTAssertEqual(t.phase, .goOut)
    }

    // MARK: the spots

    func testSixSpotsInsideTheFloorAndApart() {
        RoomLayout.apply(RoomCatalog.camp); GameCamera.configureCamp()
        for a: Float in [0.46, 0.695, 1.44, 2.17] {
            let f = try! XCTUnwrap(GameCamera.refreshRoam(aspect: a))
            let spots = CampLayout.spots(count: 9)
            XCTAssertEqual(spots.count, 6, "the cap of six")
            XCTAssertEqual(CampLayout.spots(count: 0).count, 0); XCTAssertEqual(CampLayout.spots(count: 3).count, 3)
            for s in spots {
                XCTAssertGreaterThanOrEqual(s.y, f.minZ - 0.01, "aspect \(a) \(s)"); XCTAssertLessThanOrEqual(s.y, f.maxZ + 0.01, "aspect \(a) \(s)")
                XCTAssertLessThanOrEqual(abs(s.x), f.halfWidth(at: s.y) + 0.01, "aspect \(a) \(s)")
                XCTAssertLessThan(abs(s.x) + 0.8, 4.1, "inside the fence")
            }
            for i in spots.indices { for j in spots.indices where j > i { XCTAssertGreaterThan(simd_distance(spots[i], spots[j]), 1.4, "aspect \(a): spots \(i) and \(j)") } }
        }
    }

    // MARK: a whole visit through GameCare

    private func bodies(_ n: Int, firstID: Int) -> [JellyActor] {
        let sm = buildSimMesh(), rm = buildRenderMesh()
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let spots = JellyRoster.spawnSpots(count: max(n, 1))
        let out = (0..<n).map { i -> JellyActor in
            let a = JellyActor(id: firstID + i, name: "t\(i)", simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[i % spots.count])
            a.reset(drop: 0.35, shift: true)
            let b = BlobBrain.forGame(); b.attach(renderMesh: rm, synchronous: true); b.autonomy = true; b.steerID = firstID + i
            a.brain = b
            for _ in 0..<90 { a.sim.step() }
            b.currentPose(a.sim)
            return a
        }
        Self.keep += out
        return out
    }

    func testVisitCreatesOnlyTheCampCreaturesAndLeavesHomeAsItWas() {
        let d = UserDefaults(suiteName: "CampTrip.\(UUID().uuidString)")!
        let care = GameCare(jellyCount: 3, persistent: false, defaults: d); Self.keep.append(care)
        care.wardrobe.body = WearBody.shared
        let home = bodies(3, firstID: 0)
        care.parkBook.roster = home
        let homeFloor = home.map(\.floor), homeAuto = home.map { $0.brain!.autonomy }
        let fake = [4, 5, 3, 1, 2, 6, 0].map { CampCreature.make(instance: $0, worn: [:]) }          // seven: the visit shows six
        GameCare.campSource = { fake }
        var spawned = 0
        CampBook.shared.spawn = { list, spots in spawned = list.count; XCTAssertEqual(spots.count, list.count); return self.bodies(list.count, firstID: 3) }
        care.parkBook.clear = {}
        let jelliesBefore = care.jellies.map(\.character)
        let before = d.dictionaryRepresentation() as NSDictionary

        XCTAssertNil(care.campBlocker(), "Camp opens at any hour, with nobody asleep or not")
        care.park.beginCamp()
        var n = 0
        while care.park.phase != .playing, n < 3000 { care.tickPark(home, dt: 1.0 / 60); n += 1 }
        XCTAssertEqual(care.park.phase, .playing)
        XCTAssertEqual(RoomLayout.current.id, .camp)
        XCTAssertEqual(spawned, 6, "six, never seven")
        XCTAssertEqual(care.parkBook.actors.map(\.id), [3, 4, 5, 6, 7, 8], "ids continue after the roster of three")
        XCTAssertTrue(care.parkBook.cast.isEmpty, "no park visitors from the pool"); XCTAssertTrue(care.parkBook.comers.isEmpty, "no home creature comes along")
        XCTAssertTrue(home.allSatisfy { care.parkHides($0.id) }, "every home creature is away")
        XCTAssertTrue(DecorField.shared.feet.isEmpty, "no toys, no decor")
        XCTAssertEqual(CampBook.shared.bodies.count, 6)
        XCTAssertEqual(JellyRoster.speciesOf(slot: 3), 4, "the first Camp body speaks as Teddy")
        XCTAssertEqual(care.jellies.map(\.character), jelliesBefore, "no profile for a Camp creature: nothing ticks or saves for it")
        // five simulated minutes on the yard: nothing is written
        for _ in 0..<(5 * 60 * 60) { care.tickPark(home, dt: 1.0 / 60) }
        XCTAssertEqual(d.dictionaryRepresentation() as NSDictionary, before, "no key of the save changed while on the yard (needs, grime, stats, park book ...)")

        care.park.goHome()
        n = 0
        while care.park.phase != .off, n < 3000 { care.tickPark(home, dt: 1.0 / 60); n += 1 }
        XCTAssertEqual(care.park.phase, .off)
        XCTAssertEqual(RoomLayout.current.id, care.store.currentRoom, "the home room is back")
        XCTAssertNil(GameCamera.campCap)
        XCTAssertTrue(care.parkBook.actors.isEmpty); XCTAssertTrue(CampBook.shared.bodies.isEmpty); XCTAssertTrue(JellyRoster.visitBodies.isEmpty)
        XCTAssertEqual(d.dictionaryRepresentation() as NSDictionary, before, "and nothing was written by the visit")
        for (i, a) in home.enumerated() {
            XCTAssertLessThan(simd_distance(a.floor, homeFloor[i]), 0.1, "home creature \(i) is on its spot")
            XCTAssertEqual(a.brain!.autonomy, homeAuto[i]); XCTAssertFalse(a.brain!.idleBlocked)
            XCTAssertFalse(care.parkHides(a.id))
        }
    }

    func testEmptyYardIsFine() {
        let care = GameCare(jellyCount: 1, persistent: false, defaults: UserDefaults(suiteName: "CampTrip0.\(UUID().uuidString)")!); Self.keep.append(care)
        let home = bodies(1, firstID: 0); care.parkBook.roster = home
        GameCare.campSource = { [] }
        CampBook.shared.spawn = { list, _ in XCTAssertTrue(list.isEmpty); return [] }
        care.parkBook.clear = {}
        care.park.beginCamp()
        var n = 0
        while care.park.phase != .playing, n < 3000 { care.tickPark(home, dt: 1.0 / 60); n += 1 }
        XCTAssertEqual(care.park.phase, .playing); XCTAssertTrue(care.parkBook.actors.isEmpty)
        care.park.goHome(); n = 0
        while care.park.phase != .off, n < 3000 { care.tickPark(home, dt: 1.0 / 60); n += 1 }
        XCTAssertEqual(care.park.phase, .off)
    }
}
