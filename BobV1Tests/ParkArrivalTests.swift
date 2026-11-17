//
//  ParkArrivalTests.swift
//  park-arrive-r1: right after the swap into the park a Jelbie who came stands where his body is, for himself and for everyone who steers round him. Before, `JellyActor.floor`
//  gave his HOME spot (`outingHome`, the run-out's) until the run-out's tidy, ~1.3 s into the park: the peers' snapshot had him at home and the stage built his skin's contact
//  profile around that spot (radii of 1-4 m), so the steering's wall pushed walk steps metres at a time (GameCare+Outing.swift, `outingLanded`).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ParkArrivalTests: XCTestCase {
    override func tearDown() { BlobBrain.slideFixLevel = 3; super.tearDown() }

    private func runner(level: Int) -> (GameCare, JellyActor, SIMD2<Float>) {
        BlobBrain.slideFixLevel = level
        let d = UserDefaults(suiteName: "ParkArrival.\(UUID().uuidString)")!
        let care = GameCare(jellyCount: 1, persistent: false, defaults: d)
        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let home = SIMD2<Float>(-0.15, 1.60)
        let a = JellyActor(id: 0, name: "Bob", simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: SIMD2(0.4, 4.8))
        a.profile = care.jelly(0); a.care = care
        let b = BlobBrain.forGame(); b.demo = nil; b.runMoveDemo = nil; b.autonomy = false; b.steerID = 0
        care.wireWorld(b, isBob: true); b.attach(renderMesh: rm, synchronous: true); a.brain = b
        b.currentPose(a.sim)
        // out in the street at the end of the run-out: his home spot held, the floor rules lifted for him
        a.outingHome = home
        care.outing.runners[0] = OutingBook.Runner(delay: 0, started: true, home: home)
        care.outing.lifted.insert(0); a.sim.arenaSuspended = true
        return (care, a, home)
    }

    /// The swap: rehome to his park spot, then `outingLanded` (the order of `parkSwap(.park)`). From that step on his floor position is the park spot.
    func testLandedRunnerStandsWhereHisBodyIs() {
        let (care, a, _) = runner(level: 3)
        let park = SIMD2<Float>(-1.29, 1.05)
        care.rehome(a, at: park)
        care.outingLanded(a)
        XCTAssertNil(a.outingHome, "the home spot is let go at the swap (the trip read it before)")
        XCTAssertLessThan(simd_distance(a.floor, park), 0.05, "his floor position is his park spot: \(a.floor)")
        XCTAssertFalse(care.outing.lifted.contains(0), "the floor rules are back")
        XCTAssertFalse(a.sim.arenaSuspended)
    }

    /// park-arrive-r2: the arrival spots (the ones who came, then the visitors) in the owner's park, portrait and landscape: none starts nearer the slide's box than
    /// `ParkLayout.slideClear` (slot 1 was 0.80 off it in portrait), they keep the steering gap from each other, and the floor rules leave them where they are.
    func testArrivalSpotsKeepClearOfTheSlide() {
        let seesaw = ParkPlayTuning.seesawInPark
        defer { ParkPlayTuning.seesawInPark = seesaw; GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home); DecorField.shared.clear() }
        ParkPlayTuning.seesawInPark = false
        for (name, aspect) in [("portrait", Float(440.0 / 956.0)), ("landscape", Float(956.0 / 440.0))] {
            DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
            RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: aspect)
            DecorField.shared.set(ParkToys.placed)
            let sl = DecorField.shared.foot(ParkToys.slideUID)!, court = DecorField.shared.foot(ParkToys.hopscotchUID)!
            let spots = ParkLayout.spots(count: 5)
            let line = spots.enumerated().map { String(format: "%d (%.2f,%.2f) slide %.2f court %.2f", $0.offset, $0.element.x, $0.element.y, sl.distance($0.element), court.distance($0.element)) }.joined(separator: " | ")
            print("[spots] \(name): \(line)")
            for (k, p) in spots.enumerated() {
                XCTAssertGreaterThanOrEqual(sl.distance(p), ParkLayout.slideClear - 0.03, "\(name) slot \(k) starts \(sl.distance(p)) off the slide's box. \(line)")
                let c = GameCamera.constrain(SIMD3(p.x, 0, p.y), radius: 0.8)
                XCTAssertLessThan(simd_distance(SIMD2(c.x, c.z), p), 0.02, "\(name) slot \(k) is on the floor. \(line)")
                for j in (k + 1)..<spots.count { XCTAssertGreaterThanOrEqual(simd_distance(p, spots[j]), MelonController.jellyGap, "\(name) slots \(k), \(j) apart. \(line)") }
            }
        }
    }

    /// `-ParkSlideFix r4` (level 2) keeps the old order, for the real-app before / after: the home spot stays until the tidy.
    func testLevelTwoKeepsTheHomeSpotUntilTheTidy() {
        let (care, a, home) = runner(level: 2)
        care.rehome(a, at: SIMD2(-1.29, 1.05))
        care.outingLanded(a)
        XCTAssertEqual(a.outingHome, home)
        XCTAssertLessThan(simd_distance(a.floor, home), 1e-4)
    }
}
