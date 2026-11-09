//
//  TeddySpeciesTests.swift
//  The Teddy species (character 4): it exists, but is offered nowhere; an existing save loads unchanged; the `-ForceSpecies teddy` hook spawns one without saving;
//  the feature's hat rule and its geometry budget.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TeddySpeciesTests: XCTestCase {
    private func suite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "TeddySpeciesTests.\(name)")!
        d.removePersistentDomain(forName: "TeddySpeciesTests.\(name)")
        return d
    }

    func testTeddyIsCharacterFourWithEarsAndIsNotOfferedAnywhere() {
        XCTAssertEqual(JellyRoster.teddyID, 4)
        XCTAssertEqual(JellyRoster.baseNames[4], "Teddy")
        XCTAssertEqual(JellyRoster.feature(4), .ears)
        XCTAssertNotNil(JellyRoster.palette(4))
        XCTAssertEqual(JellyRoster.characterCount, 4, "the characters on offer are still the four")
        XCTAssertFalse(JellyRoster.defaultIDs.contains(4), "not a starter")
        XCTAssertFalse(SpeciesInfo.order.contains(4), "not in the starter picker (the free first gift)")
        XCTAssertTrue(SpeciesInfo.pages(includingSpecial: true).contains(4), "bought in the Jelly Spring")
        XCTAssertNil(AdoptionPrice.next(home: 3, special: true), "room full")
        // a short roster is never padded with him
        for n in 1...3 { XCTAssertFalse(JellyRoster.sanitised(Array(0..<n)).contains(4)) }
    }

    func testExistingSaveLoadsUnchanged() {
        let d = suite("save")
        d.set([1, 2, 3], forKey: JellyRoster.rosterKey)                    // the user's phone: Pip, Moss, Lavender
        XCTAssertEqual(JellyRoster.savedIDs(d), [1, 2, 3])
        XCTAssertEqual(JellyRoster.launchIDs(d), [1, 2, 3])
        d.set(["", "Pipsqueak", "", ""], forKey: JellyRoster.namesKey)    // a name saved before Teddy existed (4 entries)
        let names = JellyRoster.loadNames(d)
        XCTAssertEqual(names.count, 7)
        XCTAssertEqual(Array(names.prefix(4)), ["Bob", "Pipsqueak", "Moss", "Lavender"])
        XCTAssertEqual(names[4], "Teddy")
        XCTAssertEqual(JellyKeys.needs(1), NeedsTuning.defaultsKey + ".jelly1", "other characters' keys are untouched")
    }

    func testForceSpeciesPutsTeddyInSlotZeroForThisLaunchOnly() {
        let d = suite("force")
        d.set([1, 2, 3], forKey: JellyRoster.rosterKey)
        d.set("teddy", forKey: JellyRoster.forceSpeciesKey)
        XCTAssertEqual(JellyRoster.launchIDs(d), [4, 1, 2])
        d.set(1, forKey: "BlobCount")
        XCTAssertEqual(JellyRoster.launchIDs(d), [4])
        XCTAssertEqual(JellyRoster.savedIDs(d), [1, 2, 3], "the saved roster is never rewritten")
        d.removeObject(forKey: JellyRoster.forceSpeciesKey)
        XCTAssertEqual(JellyRoster.launchIDs(d), [1])
    }

    func testBellyAndPaletteAreTeddysOnly() {
        let teddy = JellyRoster.palette(4)!
        XCTAssertEqual(BlueBelly.mode(for: teddy), 43, "the clear belly oval in tone 3")
        XCTAssertEqual(BlueBelly.mode(for: JellyRoster.palette(0) ?? PaletteKey.blue.palette), Float(BlueBelly.shipped.rawValue), "Bob has the shipped blue front (not Teddy's)")
        for c in 1..<4 { let p = JellyRoster.palette(c) ?? PaletteKey.blue.palette; XCTAssertEqual(BlueBelly.mode(for: p), 0, "character \(c) has no belly patch") }
        for c in 0..<4 { XCTAssertNotEqual(JellyRoster.palette(c)?.flesh ?? PaletteKey.blue.palette.flesh, teddy.flesh) }
    }

    func testEarsAndPomAreThreePartsOnTheSurfaceWithinTheBudget() {
        let body = WearBody.shared
        for slide in [Float(0), 24, -12] {
            let p = TeddyMesh.prepare(slide: slide, body: body)
            XCTAssertEqual(p.parts.map(\.name), ["ear_r", "ear_l", "pom"])
            XCTAssertLessThanOrEqual(p.rest.count, FeatureMeshes.vertexBudget)
            XCTAssertLessThanOrEqual(p.triangles, FeatureMeshes.triangleBudget)
            for part in p.parts {
                XCTAssertNotEqual(part.bind.tri, .zero, "\(part.name) is bound to the egg")
                let rest = body.restPoint(part.bind)
                XCTAssertLessThan(simd_distance(rest, part.pivot), 0.01, "\(part.name)'s pivot is on the surface")
            }
            // mirrored ears
            let r = p.parts[0], l = p.parts[1]
            XCTAssertEqual(r.pivot.x, -l.pivot.x, accuracy: 0.01)
            XCTAssertEqual(r.pivot.y, l.pivot.y, accuracy: 0.01)
            XCTAssertGreaterThan(r.pivot.x, 0.25, "the ears sit out toward the sides of the head")
        }
    }

    func testPomIsOnTheLowerBackAndClearOfTheFeet() {
        let p = TeddyMesh.prepare(slide: 0, body: WearBody.shared)
        let pom = p.parts[2]
        let verts = (pom.first..<(pom.first + pom.count)).map { p.rest[$0] }
        XCTAssertGreaterThan(pom.pivot.y, 0.35); XCTAssertLessThan(pom.pivot.y, 0.7)
        XCTAssertLessThan(pom.pivot.z, -0.3, "on the back")
        XCTAssertEqual(pom.pivot.x, 0, accuracy: 0.01)
        XCTAssertGreaterThan(verts.map(\.y).min() ?? 0, Float(BobForm.lift) + 0.2, "the pom hangs well above the body's underside")
        // it stands out of the back: the ball reaches past the surface point by its own size or less
        XCTAssertGreaterThan(pom.pivot.z - (verts.map(\.z).min() ?? 0), 0.05)
        XCTAssertLessThan(pom.pivot.z - (verts.map(\.z).min() ?? 0), 0.16)
    }

    func testHatRule() {
        TeddyFit.clearCache()
        let bare = TeddyFit.solve(worn: [])
        XCTAssertEqual(bare, TeddyFitResult())
        // snug hats that enclose the head hide the ears; they come back with the hat off
        for hat in ["beanie_pink", "cap_team_sky", "pirate_hat", "cowboy_hat", "beret", "viking_hat"] {
            let r = TeddyFit.solve(worn: [hat])
            XCTAssertTrue(r.earsHidden, "\(hat): the ears tuck")
            XCTAssertEqual(r.slide, 0)
        }
        // ear headbands are ears themselves
        for hat in ["cat_ears", "frog_ears", "bunny_ears", "headphones"] { XCTAssertTrue(TeddyFit.solve(worn: [hat]).earsHidden, hat) }
        // open / perching pieces leave the ears out (possibly nudged)
        for hat in ["flower_clip", "sweatband", "visor_tennis", "hair_bow", "flower_crown", "crown_gold", "bee_antennae"] {
            let r = TeddyFit.solve(worn: [hat])
            XCTAssertFalse(r.earsHidden, "\(hat): the ears stay out")
            XCTAssertEqual(r.slide, 0, "no slide any more")
        }
        // party / top hats enclose the crown too: the ears tuck, the head under them is exactly Bob's
        for hat in ["party_hat", "tophat"] { XCTAssertTrue(TeddyFit.solve(worn: [hat]).earsHidden, "\(hat): the ears tuck") }
        // the pom tucks under what covers the lower back, and stays under hats / scarves
        XCTAssertTrue(TeddyFit.solve(worn: ["cape_hero"]).pomHidden)
        XCTAssertTrue(TeddyFit.solve(worn: ["backpack_sky"]).pomHidden)
        XCTAssertFalse(TeddyFit.solve(worn: ["beanie_pink"]).pomHidden)
        XCTAssertFalse(TeddyFit.solve(worn: ["bandana_coral"]).pomHidden)
    }

    func testFeatureFitFlowsThroughTheSolver() {
        let f = FeatureCompat.solve(.ears, worn: ["beanie_pink", "cape_hero"])
        XCTAssertTrue(f.earsHidden); XCTAssertTrue(f.pomHidden)
        let g = FeatureCompat.solve(.ears, worn: [])
        XCTAssertFalse(g.earsHidden); XCTAssertFalse(g.pomHidden); XCTAssertEqual(g.earSlide, 0)
    }
}
