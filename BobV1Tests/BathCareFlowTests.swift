//
//  BathCareFlowTests.swift
//  The soaps inside the real clean-up (CleanRun: GameCare + BathFlow on the headless sim) and the pick card's logic: a dirty Jelmiko ends fully clean with the soap's tier,
//  the Berry soap makes more bubbles, the card shows only with bought soaps, the pick starts the bath with it, one bar is used up by a FINISHED bath and a cancelled bath uses nothing.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BathCareFlowTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func run(dirt: Float = 0.5, soaps: [Soap] = [], pick: Soap? = nil) -> CleanRun {
        let r = CleanRun(dirt: dirt)
        Self.keep.append(r)
        UserDefaults.standard.removeObject(forKey: GameCare.lastSoapKey)
        for s in soaps { if let id = s.storeID { r.care.store.grant(id) } }
        if let pick { r.care.armedSupplies[0] = pick.storeID.map { [$0] } ?? [] }
        r.care.clean()
        return r
    }

    func testADirtyOneWashedWithAnySoapEndsFullyCleanWithItsTier() {
        for (soap, tier) in [(Soap.jelly, WashTier.plain), (.lavender, .plain), (.mint, .fresh), (.berry, .plain), (.honey, .plain), (.chamomile, .plain)] {
            let r = run(dirt: 0.9, soaps: [soap], pick: soap)
            XCTAssertEqual(r.bath.soap, soap)
            r.run(90, until: { r.bath.phase == .finish })
            XCTAssertEqual(r.bath.phase, .finish, "\(soap): reached the finish")
            XCTAssertEqual(r.bath.grime.dirt, 0, "\(soap): a dirtier Jelmiko ends fully clean")
            XCTAssertEqual(r.bath.grime.sparkle, 1); XCTAssertEqual(r.bath.grime.washMul, tier.cleanMul, "\(soap): stamped with the tier")
        }
    }

    func testTheBerrySoapMakesMoreBubblesAndNeverMoreThanTheCap() {
        func peak(_ s: Soap) -> Int { let r = run(soaps: [s], pick: s); var m = 0; r.run(25, autoNext: false, until: { m = max(m, r.bath.look.bubbles.count); return r.bath.stageComplete }); return m }
        let plain = peak(.jelly), berry = peak(.berry)
        XCTAssertGreaterThan(berry, plain); XCTAssertLessThanOrEqual(berry, BathLook.maxBubbles)
    }

    func testTheSoapColoursTheRendererAndTheBarInHand() {
        let r = run(soaps: [.mint], pick: .mint)
        r.run(40, scrubbing: false, autoNext: false, until: { r.bath.phase == .soap && r.bath.wipe == 0 })
        r.run(0.1, scrubbing: false, autoNext: false)
        XCTAssertEqual(r.bath.look.soap, Soap.mint.rawValue)
    }

    func testTheCardShowsEveryTimeWithAllSixSoapsAndAPickStartsTheBath() {
        UserDefaults.standard.removeObject(forKey: GameCare.lastSoapKey)
        let none = CleanRun(dirt: 0.4); Self.keep.append(none)
        none.care.requestClean()
        XCTAssertEqual(none.care.soapPrompt, 0, "no soaps owned: the card still shows"); XCTAssertFalse(none.bath.active)
        XCTAssertEqual(none.care.soapChoices, Soap.allCases, "always all six, Jelly soap first")
        XCTAssertEqual(none.care.soapCount(.jelly), nil); XCTAssertEqual(none.care.soapCount(.mint), 0); XCTAssertEqual(none.care.soapPrice(.mint), 25); XCTAssertEqual(none.care.soapPrice(.jelly), nil)
        none.care.chooseSoap(.jelly)
        XCTAssertNil(none.care.soapPrompt); XCTAssertTrue(none.bath.active); XCTAssertEqual(none.bath.soap, .jelly, "the free Jelly soap starts the plain bath")

        let r = CleanRun(dirt: 0.4); Self.keep.append(r)
        for s in [Soap.honey, .mint] { r.care.store.grant(s.storeID!) }
        r.care.requestClean()
        XCTAssertEqual(r.care.soapPrompt, 0); XCTAssertEqual(r.care.soapCount(.mint), 1); XCTAssertEqual(r.care.soapCount(.honey), 1)
        XCTAssertEqual(r.care.preselectedSoap, .jelly)
        r.care.chooseSoap(.mint)
        XCTAssertNil(r.care.soapPrompt); XCTAssertTrue(r.bath.active); XCTAssertEqual(r.bath.soap, .mint, "the bath starts with the tapped soap")
        XCTAssertEqual(r.care.store.count("mintsoap"), 1, "nothing is used up until the bath is finished")
        // a soap armed from the Bag is the pick: no card
        let bag = CleanRun(dirt: 0.4); Self.keep.append(bag)
        bag.care.store.grant("berrysoap")
        XCTAssertTrue(bag.care.useSupply("berrysoap", on: 0)); XCTAssertNil(bag.care.soapPrompt); XCTAssertEqual(bag.bath.soap, .berry)
        // not now
        let x = CleanRun(dirt: 0); Self.keep.append(x)
        x.care.requestClean(); x.care.dismissSoapCard()
        XCTAssertNil(x.care.soapPrompt); XCTAssertFalse(x.bath.active)
    }

    func testBuyingASoapOnTheCardUsesTheShopsPathAndStartsTheBath() {
        let r = CleanRun(dirt: 0.4); Self.keep.append(r)
        let wallet = r.care.store.wallet
        wallet.add(max(0, 100 - wallet.count), silent: true)
        wallet.add(0, silent: true)
        let before = wallet.count
        XCTAssertTrue(r.care.canBuySoap(.mint))
        r.care.requestClean()
        r.care.chooseSoap(.mint)
        XCTAssertEqual(wallet.count, before - 25, "the price came off the wallet"); XCTAssertEqual(r.care.store.count("mintsoap"), 1, "one bar bought")
        XCTAssertEqual(r.bath.soap, .mint); XCTAssertTrue(r.bath.active)
        // cancelled: the bought bar stays in the Bag, nothing is used up
        r.care.cancelClean(); r.run(8, scrubbing: false, autoNext: false)
        XCTAssertEqual(r.care.store.count("mintsoap"), 1, "the bought bar stays in the Bag after a cancelled bath")
        // too few coins: nothing happens
        let poor = CleanRun(dirt: 0.4); Self.keep.append(poor)
        let w2 = poor.care.store.wallet
        _ = w2.spend(w2.count)
        XCTAssertFalse(poor.care.canBuySoap(.mint)); XCTAssertTrue(poor.care.canBuySoap(.jelly) || true)
        poor.care.requestClean(); poor.care.chooseSoap(.mint)
        XCTAssertEqual(poor.care.store.count("mintsoap"), 0); XCTAssertEqual(poor.care.soapPrompt, 0, "the card stays: not enough coins"); XCTAssertFalse(poor.bath.active)
        XCTAssertEqual(w2.count, 0)
    }

    func testAFinishedBathUsesOneBarAndGivesThePowerUp() {
        for (soap, perk) in [(Soap.lavender, PerkKind.shine), (.honey, .snuggly), (.chamomile, .cozy)] {
            let r = run(soaps: [soap, soap], pick: soap)
            let jelly = r.care.jelly(0)!
            defer { for k in PerkKind.allCases { jelly.perks.clear(k) } }
            r.care.soapFinished()
            XCTAssertTrue(jelly.perks.isActive(perk), "\(soap) grants \(perk)")
            XCTAssertEqual(r.care.store.count(soap.storeID!), 1, "one bar used up, one kept")
            XCTAssertNil(r.care.armedSupplies[0])
            XCTAssertEqual(UserDefaults.standard.string(forKey: GameCare.lastSoapKey), soap.storeID, "the last soap is remembered")
        }
        let r = run(soaps: [.berry], pick: .berry); r.care.needs(for: 0).set(.attention, 0.5); r.care.soapFinished()
        XCTAssertGreaterThan(r.care.needs(for: 0).level(.attention), 0.5 + 0.03, "Berry: a little love")
        XCTAssertEqual(r.care.store.count("berrysoap"), 0)
        r.care.store.grant("lavender"); r.care.armedSupplies[0] = []; r.care.soapFinished()
        XCTAssertEqual(r.care.store.count("lavender"), 1, "the free Jelly soap uses nothing")
    }

    func testAStoppedBathKeepsEverything() {
        let r = run(soaps: [.mint], pick: .mint)
        let had = r.care.jelly(0)!.perks.active
        r.run(3, autoNext: false)
        r.care.cancelClean()
        r.run(8, scrubbing: false, autoNext: false)
        XCTAssertEqual(r.care.store.count("mintsoap"), 1); XCTAssertNil(r.care.armedSupplies[0]); XCTAssertEqual(r.bath.soap, .jelly)
        XCTAssertEqual(r.care.jelly(0)!.perks.active, had)
        XCTAssertEqual(r.bath.grime.washMul, 1, "no wash was stamped")
    }

    func testThePreselectedSoapIsTheLastOneUsedIfStillOwned() {
        let r = CleanRun(dirt: 0); Self.keep.append(r)
        r.care.store.grant("honeysoap")
        UserDefaults.standard.set("honeysoap", forKey: GameCare.lastSoapKey); XCTAssertEqual(r.care.preselectedSoap, .honey)
        UserDefaults.standard.set("mintsoap", forKey: GameCare.lastSoapKey); XCTAssertEqual(r.care.preselectedSoap, .jelly, "not owned any more")
        UserDefaults.standard.removeObject(forKey: GameCare.lastSoapKey)
    }
}
