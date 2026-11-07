//
//  PortraitEarsTests.swift
//  A Panda / Teddy lobby portrait drawn right after a hat came off must show the ears: the portrait skins with its own throwaway FeatureSet's ear scales, never the live (still tucked,
//  or frozen while the stage is paused) ones, and the live drive is left untouched.
//

import XCTest
@testable import BobV1

@MainActor
final class PortraitEarsTests: XCTestCase {
    private func check(_ character: Int, _ name: String) {
        let r = MotionRig(game: true)
        let feature = JellyRoster.feature(character)
        XCTAssertEqual(feature, .ears, name)
        // the live room: a band hat on (the ears tucked, faded to 0)
        let live = FeatureSet()
        r.run(1.0) { live.tick(id: 0, brain: r.brain, sim: r.sim, feature: feature, worn: ["headphones"], hideAll: false, dt: 1.0 / 60) }
        XCTAssertEqual(r.brain.teddyEarScale, 0, accuracy: 0.001, "\(name): live ears tucked under the hat")
        // the hat comes off; the stage has NOT ticked since (paused behind the Bag) or is mid fade: the live drive is still tucked
        let before = TeddyDrive(r.brain)
        // the portrait of the hat-free wardrobe
        let bare = TeddyDrive.portrait(fs: FeatureSet(), id: 0, brain: r.brain, sim: r.sim, feature: feature, worn: [])
        XCTAssertEqual(bare.ear, 1, accuracy: 0.001, "\(name): hat off -> portrait ears out (the old path used the live scale 0)")
        XCTAssertEqual(bare.pom, 1, accuracy: 0.001, "\(name): pom out")
        XCTAssertEqual(TeddyDrive(r.brain), before, "\(name): the live brain's drive is untouched by the portrait")
        // and the hat-on portrait still tucks them
        let hat = TeddyDrive.portrait(fs: FeatureSet(), id: 0, brain: r.brain, sim: r.sim, feature: feature, worn: ["headphones"])
        XCTAssertEqual(hat.ear, 0, accuracy: 0.001, "\(name): hat on -> portrait ears tucked")
        // the reverse staleness: live ears out, portrait with the hat
        let out = FeatureSet(); let r2 = MotionRig(game: true)
        r2.run(1.0) { out.tick(id: 0, brain: r2.brain, sim: r2.sim, feature: feature, worn: [], hideAll: false, dt: 1.0 / 60) }
        XCTAssertEqual(r2.brain.teddyEarScale, 1, accuracy: 0.001)
        XCTAssertEqual(TeddyDrive.portrait(fs: FeatureSet(), id: 0, brain: r2.brain, sim: r2.sim, feature: feature, worn: ["headphones"]).ear, 0, accuracy: 0.001)
        XCTAssertEqual(r2.brain.teddyEarScale, 1, accuracy: 0.001)
    }
    func testPandaPortraitEarsAfterHatOff() { check(JellyRoster.pandaID, "Panda") }
    func testTeddyPortraitEarsAfterHatOff() { check(JellyRoster.teddyID, "Teddy") }
}
