//
//  BathCareFlowTests.swift
//  The Care items inside the real clean-up (CleanRun: GameCare + BathFlow on the headless sim): a dirty Jelmiko washed with any kit ends fully clean and carries the
//  kit's tier, the sea sponge scrubs faster, the bubble bath makes more bubbles, the soft brush has its moment, the supplies are used up only by a finished bath,
//  a stopped bath keeps them, and the picker changes the kit during the soap step.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BathCareFlowTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func run(dirt: Float = 0.5, kit: [String]) -> CleanRun {
        let r = CleanRun(dirt: dirt)
        Self.keep.append(r)
        for id in kit { r.care.store.grant(id) }
        r.care.armedSupplies[0] = kit
        r.care.clean()
        return r
    }

    func testADirtyOneWashedWellEndsFullyCleanWithTheKitsTier() {
        for (ids, tier) in [([String](), WashTier.plain), ([CareItems.gentle], .gentle), ([CareItems.deluxe], .deluxe), ([CareItems.deluxe, CareItems.duck, CareItems.sponge], .deluxe)] {
            let r = run(dirt: 0.9, kit: ids)
            XCTAssertEqual(r.bath.kit.tier, tier)
            r.run(90, until: { r.bath.phase == .finish })
            XCTAssertEqual(r.bath.phase, .finish, "\(ids): reached the finish")
            XCTAssertEqual(r.bath.grime.dirt, 0, "\(ids): a dirtier Jelmiko ends fully clean")
            XCTAssertEqual(r.bath.grime.sparkle, 1); XCTAssertEqual(r.bath.grime.coat, .beautiful)
            XCTAssertEqual(r.bath.grime.washMul, tier.cleanMul, "\(ids): stamped with the tier")
        }
    }

    func testTheSeaSpongeMakesTheSoapStepQuicker() {
        func soapSeconds(_ kit: [String]) -> Float { let r = run(kit: kit); r.run(60, autoNext: false, until: { r.bath.phase == .soap && r.bath.stageComplete }); return r.t }
        let plain = soapSeconds([]), sponge = soapSeconds([CareItems.sponge])
        XCTAssertLessThan(sponge, plain * 0.85, "sponge \(sponge) s vs plain \(plain) s")
    }

    func testTheBubbleBathMakesMoreBubblesAndNeverMoreThanTheCap() {
        func peak(_ kit: [String]) -> Int { let r = run(kit: kit); var m = 0; r.run(25, autoNext: false, until: { m = max(m, r.bath.look.bubbles.count); return r.bath.stageComplete }); return m }
        let plain = peak([]), foamy = peak([CareItems.bubblebath])
        XCTAssertGreaterThan(foamy, plain)
        XCTAssertLessThanOrEqual(foamy, BathLook.maxBubbles)
    }

    func testTheSoftBrushHasItsMomentInTheShineStep() {
        func progressWithNoFinger(_ kit: [String]) -> (Float, Bool) {
            let r = run(kit: kit)
            r.run(90, until: { r.bath.phase == .shine })
            XCTAssertEqual(r.bath.phase, .shine)
            let before = r.bath.progress
            r.run(1.2, scrubbing: false, autoNext: false)
            return (r.bath.progress - before, r.bath.look.kit.brushes)
        }
        let plain = progressWithNoFinger([]), soft = progressWithNoFinger([CareItems.brush])
        XCTAssertEqual(plain.0, 0, accuracy: 0.001, "without a brush nothing happens until he is rubbed")
        XCTAssertGreaterThan(soft.0, 0.1, "the brush sweeps by itself for a moment (the scripted scrub)")
        XCTAssertTrue(soft.1)
    }

    func testAFinishedBathUsesUpThePickedSuppliesAndGivesTheirPerks() {
        let r = run(kit: [CareItems.deluxe, CareItems.brush, CareItems.lintguard, CareItems.duck, CareItems.bubblebath])
        let n0 = r.care.jelly(0)!.needs.level(.attention)
        defer { for k in PerkKind.allCases { r.care.jelly(0)?.perks.clear(k) } }          // (the perks persist in the test host's defaults: leave none behind for the other suites)
        r.care.needs(for: 0).set(.attention, 0.5)
        r.care.soapFinished()
        let p = r.care.jelly(0)!.perks
        XCTAssertTrue(p.isActive(.shine)); XCTAssertTrue(p.isActive(.brushed)); XCTAssertTrue(p.isActive(.tidy))
        XCTAssertEqual(p.dirtMul, PerkTuning.tidyDirt)
        for id in [CareItems.deluxe, CareItems.brush, CareItems.lintguard, CareItems.duck, CareItems.bubblebath] { XCTAssertEqual(r.care.store.count(id), 0, "\(id) used up") }
        XCTAssertGreaterThan(r.care.needs(for: 0).level(.attention), 0.5 + 0.09, "bubble bath + duck: a little love")
        XCTAssertNil(r.care.armedSupplies[0]); _ = n0
    }

    func testAStoppedBathKeepsEverything() {
        let r = run(kit: [CareItems.deluxe, CareItems.duck])
        let had = r.care.jelly(0)!.perks.active
        r.run(3, autoNext: false)
        r.care.cancelClean()
        r.run(8, scrubbing: false, autoNext: false)
        XCTAssertEqual(r.care.store.count(CareItems.deluxe), 1); XCTAssertEqual(r.care.store.count(CareItems.duck), 1)
        XCTAssertNil(r.care.armedSupplies[0]); XCTAssertTrue(r.bath.kit.isEmpty)
        XCTAssertEqual(r.care.jelly(0)!.perks.active, had, "no perk was granted by a stopped bath")
    }

    func testThePickerChangesTheKitDuringTheSoapStepOnly() {
        let r = run(kit: [])
        for id in CareItems.all { r.care.store.grant(id) }
        r.run(30, scrubbing: false, autoNext: false, until: { r.bath.phase == .soap && r.bath.wipe == 0 })
        XCTAssertEqual(r.bath.phase, .soap)
        XCTAssertEqual(r.care.bathCareItems.count, 8)
        r.care.toggleSupply(CareItems.gentle); r.care.toggleSupply(CareItems.duck)
        XCTAssertEqual(r.bath.kit.ids, [CareItems.gentle, CareItems.duck]); XCTAssertEqual(r.care.armedSupplies[0] ?? [], r.bath.kit.ids)
        r.care.toggleSupply(CareItems.deluxe); XCTAssertEqual(r.bath.kit.tier, .deluxe); XCTAssertFalse(r.bath.kit.has(CareItems.gentle))
        r.run(0.1, scrubbing: false, autoNext: false); XCTAssertEqual(r.bath.look.kit, r.bath.kit, "the renderer sees it at once")
        r.care.toggleSupply(CareItems.duck); XCTAssertFalse(r.bath.kit.hasDuck)
        r.care.toggleSupply("lavender-not-an-item"); XCTAssertEqual(r.bath.kit.ids, [CareItems.deluxe])
    }
}

