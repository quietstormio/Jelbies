//
//  CampStrokeTests.swift
//  camp-yard-r1 Y7: stroking a Camp creature gives hearts over it, a soft haptic tick per heart and its species' happy chirp through the voice gate; wandering is paused while stroked and comes back after.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CampStrokeTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func tearDown() {
        GameCare.campSource = { GameCare.campCreatures() }; CampBook.shared.spawn = nil; CampBook.shared.bodies = [:]; JellyRoster.visitBodies = [:]; CampUI.shared.reset(arrival: nil)
        AudioHub.dropTap = nil
        GameCamera.endPark(count: 3); GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    private func bodies(_ n: Int, firstID: Int) -> [JellyActor] {
        let sm = buildSimMesh(), rm = buildRenderMesh()
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let out = (0..<n).map { i -> JellyActor in
            let a = JellyActor(id: firstID + i, name: "t\(i)", simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: SIMD2(Float(i) * 2 - 1, 0))
            a.reset(drop: 0.35, shift: true)
            let b = BlobBrain.forGame(); b.attach(renderMesh: rm, synchronous: true); b.autonomy = true; b.steerID = firstID + i
            a.brain = b
            for _ in 0..<60 { a.sim.step() }
            b.currentPose(a.sim)
            return a
        }
        Self.keep += out
        return out
    }

    func testAThreeSecondStrokeGivesHeartsHapticsAndTheOwnChirp() {
        let d = UserDefaults(suiteName: "CampStroke.\(UUID().uuidString)")!
        let care = GameCare(jellyCount: 3, persistent: false, defaults: d); Self.keep.append(care)
        care.wardrobe.body = WearBody.shared; care.features.body = WearBody.shared
        let home = bodies(3, firstID: 0); care.parkBook.roster = home
        GameCare.campSource = { [4, 5].map { CampCreature.make(instance: $0, worn: [:]) } }          // Teddy, Pearl
        CampBook.shared.spawn = { list, _ in self.bodies(list.count, firstID: 3) }
        care.parkBook.clear = {}
        care.park.beginCamp()
        var n = 0
        while care.park.phase != .playing, n < 3000 { care.tickPark(home, dt: 1.0 / 60); n += 1 }
        XCTAssertEqual(care.park.phase, .playing)
        var chirps: [(String, String?)] = []
        AudioHub.dropTap = { what, why in if what == "chirp:happy@camp" { chirps.append((what, why)) } }
        let ui = CampUI.shared, body = care.parkBook.actors[0], brain = body.brain!
        XCTAssertTrue(brain.autonomy)
        ui.beginDrag(id: ObjectIdentifier(care), at: .zero, body: body.id)
        XCTAssertTrue(ui.dragMoved(id: ObjectIdentifier(care), to: CGPoint(x: 10, y: 0), now: 100), "less than 30 pt is not a stroke yet")
        XCTAssertNil(ui.stroke)
        var t = 100.0
        for _ in 0..<(3 * 60) {          // a 3 s stroke: the finger keeps moving
            t += 1.0 / 60
            _ = ui.dragMoved(id: ObjectIdentifier(care), to: CGPoint(x: 40 + 30 * sin(t * 6), y: 0), now: t)
            care.tickCampStroke(dt: 1.0 / 60, now: t)
        }
        XCTAssertGreaterThanOrEqual(ui.strokeStats.hearts, 4, "a heart every 0.6 s")
        XCTAssertEqual(ui.strokeStats.haptics, ui.strokeStats.hearts, "a haptic tick with every heart")
        XCTAssertGreaterThanOrEqual(ui.strokeStats.chirps, 1)
        XCTAssertGreaterThanOrEqual(chirps.count, 1, "the chirp went through the voice gate (its src is `camp`)")
        let played = chirps.filter { $0.1 == nil }.count, dropped = chirps.filter { $0.1 != nil }.map { $0.1! }
        print("[campstroke] chirps requested \(chirps.count), PLAYED \(played), dropped by guard \(dropped)")
        XCTAssertEqual(played + dropped.count, chirps.count)
        XCTAssertTrue(care.bubbleHub.hearts.contains { $0.id == body.id }, "hearts over the stroked body")
        XCTAssertEqual(JellyRoster.speciesOf(slot: body.id), 4, "the chirp is Teddy's voice: the body's slot resolves to its species")
        XCTAssertFalse(brain.autonomy, "wandering is paused while it is stroked")
        // the finger lifts: it walks again
        for _ in 0..<60 { t += 1.0 / 60; care.tickCampStroke(dt: 1.0 / 60, now: t) }
        XCTAssertNil(ui.stroke); XCTAssertTrue(brain.autonomy, "and wanders again afterwards")
        // the other body is never touched
        XCTAssertTrue(care.parkBook.actors[1].brain!.autonomy)
    }
}
