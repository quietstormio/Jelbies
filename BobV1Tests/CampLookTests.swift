//
//  CampLookTests.swift
//  camp-yard-r1 step Y4: a Camp body shows its creature as the room does at home, from a copy taken when the body appears.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CampLookTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func tearDown() { CampBook.shared.bodies = [:]; JellyRoster.visitBodies = [:] }

    private func actor(_ id: Int) -> JellyActor {
        let sm = buildSimMesh(), rm = buildRenderMesh()
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let a = JellyActor(id: id, name: "t", simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: SIMD2(Float(id), 0))
        a.reset(drop: 0.35, shift: true)
        let b = BlobBrain.forGame(); b.attach(renderMesh: rm, synchronous: true); b.autonomy = false; b.steerID = id
        a.brain = b
        for _ in 0..<90 { a.sim.step() }
        b.currentPose(a.sim)
        Self.keep.append(a)
        return a
    }

    /// For every species: the look copied for a Camp creature equals the look the room builds for the same creature at home (feature, tints, ink, fit, palette species).
    func testCopiedLookEqualsTheHomeLookForEverySpecies() {
        let keepRoster = JellyRoster.current
        defer { JellyRoster.current = keepRoster }
        for id in 0...6 {
            JellyRoster.current = [id]          // (the room with this creature in slot 0)
            let d = UserDefaults(suiteName: "CampLook.\(UUID().uuidString)")!
            let care = GameCare(jellyCount: 1, roster: [id], persistent: false, defaults: d); Self.keep.append(care)
            care.wardrobe.body = WearBody.shared; care.features.body = WearBody.shared
            let homeBody = actor(0), campBody = actor(1)
            homeBody.profile = care.jelly(0)
            let creature = CampCreature.make(instance: id, worn: [:])
            for _ in 0..<150 {
                care.tickFeature(homeBody, brain: homeBody.brain!, hideAll: false, dt: 1.0 / 60)
                care.campLook(campBody, creature, dt: 1.0 / 60)
            }
            let h = care.features.slot(0)!, c = care.features.slot(1)!
            let name = JellyRoster.nameOf(id)
            XCTAssertEqual(c.feature, h.feature, name); XCTAssertEqual(creature.feature, JellyRoster.feature(id), name)
            XCTAssertEqual(c.wingTint, h.wingTint, "\(name) wing tint"); XCTAssertEqual(c.spikeTint, h.spikeTint, "\(name) spike tint")
            XCTAssertEqual(care.features.shown(1), care.features.shown(0), "\(name) feature shown")
            XCTAssertEqual(campBody.brain!.feature, homeBody.brain!.feature, name)
            XCTAssertEqual(campBody.brain!.wingsFolded, homeBody.brain!.wingsFolded, name); XCTAssertEqual(campBody.brain!.wingFlapLimit, homeBody.brain!.wingFlapLimit, name)
            XCTAssertEqual(campBody.brain!.pandaInk, id == JellyRoster.pandaID, name)
            XCTAssertEqual(creature.palette?.flesh, JellyRoster.palette(slot: 0)?.flesh, "\(name) palette"); XCTAssertEqual(creature.palette?.jellySpecies, JellyRoster.palette(slot: 0)?.jellySpecies, name)
            XCTAssertEqual(creature.name, JellyRoster.name(slot: 0))
        }
    }

    func testWhatItWearsIsShown() {
        let d = UserDefaults(suiteName: "CampLook.\(UUID().uuidString)")!
        let care = GameCare(jellyCount: 1, persistent: false, defaults: d); Self.keep.append(care)
        care.wardrobe.body = WearBody.shared; care.features.body = WearBody.shared
        let body = actor(3)
        let worn: [WearSlot: WearLook] = [.head: .beanieHoney, .neck: .bandanaMint, .hands: .wristbandsSky, .feet: .hightopRed]
        let creature = CampCreature.make(instance: 4, worn: worn)
        CampBook.shared.bodies[3] = creature
        for _ in 0..<200 { care.campLook(body, creature, dt: 1.0 / 60) }
        XCTAssertEqual(care.wardrobe.shown(3, .head), .beanieHoney); XCTAssertEqual(care.wardrobe.shown(3, .neck), .bandanaMint); XCTAssertEqual(care.wardrobe.shown(3, .hands), .wristbandsSky)
        XCTAssertEqual(care.shoeLook(for: body), .hightopRed, "the shoes are the copied ones, not slot 3's outfit")
        XCTAssertNil(care.shoeLook(for: actor(4)), "a body with no copy reads no shoes of a slot")
    }

    /// The copy is a value: re-reading the save after a purge (the goodbye) cannot change a body on screen, which only ever reads `CampBook.bodies`.
    func testTheCopyIsNotReadFromTheSaveAgain() {
        let creature = CampCreature.make(instance: 3, worn: [.head: .beaniePink])
        CampBook.shared.bodies[3] = creature
        JellyRoster.visitBodies[3] = 3
        let again = CampCreature.make(instance: 3, worn: [:])          // what a re-read of a purged creature's outfit would give
        XCTAssertNotEqual(CampBook.shared.bodies[3]!.worn, again.worn)
        XCTAssertEqual(CampBook.shared.bodies[3]!.worn[.head], .beaniePink)
        XCTAssertEqual(JellyRoster.speciesOf(slot: 3), 3)
    }

    func testVisitBodiesOnlyForSlotsPastTheRosterAndGoneAfterwards() {
        JellyRoster.visitBodies = [5: 4]
        XCTAssertEqual(JellyRoster.speciesOf(slot: 5), 4)
        JellyRoster.visitBodies = [:]
        XCTAssertEqual(JellyRoster.character(5), min(5, JellyRoster.characterCount - 1), "as before: the same-numbered character")
        XCTAssertEqual(AudioHub.voiceFile(slot: 5, .happy), JellyVoiceSet.file(character: JellyRoster.speciesOf(slot: 5), .happy))
        JellyRoster.visitBodies = [5: 4]
        XCTAssertEqual(AudioHub.voiceFile(slot: 5, .happy), JellyVoiceSet.file(character: 4, .happy), "a Camp body speaks with its own species' voice")
        JellyRoster.visitBodies = [:]
    }
}
