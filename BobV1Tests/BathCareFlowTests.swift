//
//  BathCareFlowTests.swift
//  The soaps inside the real clean-up (CleanRun: GameCare + BathFlow on the headless sim) and the pick card's logic: a dirty Jelmiko ends fully clean with the soap's tier,
//  the Berry soap makes more bubbles, the card shows only with bought soaps, the pick starts the bath with it, one bar is used up by a FINISHED bath and a cancelled bath uses nothing.
//

import XCTest
import QuartzCore
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

    /// With NO bought soap there is no card and no pause: `requestClean` runs the very `clean` the build before this feature ran, in the same call (phase .exit at once).
    func testNoBoughtSoapMeansNoCardAndTheRunOutStartsInTheSameCall() {
        UserDefaults.standard.removeObject(forKey: GameCare.lastSoapKey)
        let r = CleanRun(dirt: 0.4); Self.keep.append(r)
        XCTAssertFalse(r.care.hasBoughtSoap)
        let t0 = CACurrentMediaTime()
        r.care.requestClean()
        let ms = (CACurrentMediaTime() - t0) * 1000
        print("[bathcare] tap -> run-out start (requestClean, no soaps): \(String(format: "%.3f", ms)) ms, phase \(r.bath.phase)")
        XCTAssertNil(r.care.soapPrompt, "no card"); XCTAssertEqual(r.bath.phase, .exit, "the run-out started in the same call"); XCTAssertEqual(r.bath.soap, .jelly)
        XCTAssertLessThan(ms, 50, "nothing slow ran: no soap art, no model")
    }

    func testTheCardShowsOnlyWithBoughtSoapsAndAPickStartsTheBath() {
        UserDefaults.standard.removeObject(forKey: GameCare.lastSoapKey)
        let r = CleanRun(dirt: 0.4); Self.keep.append(r)
        for s in [Soap.honey, .mint] { r.care.store.grant(s.storeID!) }
        r.care.requestClean()
        XCTAssertEqual(r.care.soapPrompt, 0, "owns soaps: the card shows first"); XCTAssertFalse(r.bath.active)
        XCTAssertEqual(r.care.soapChoices, [.jelly, .mint, .honey], "Jelly soap first, then the owned ones in order")
        XCTAssertEqual(r.care.soapCount(.mint), 1); XCTAssertEqual(r.care.preselectedSoap, .jelly)
        r.care.requestClean(); XCTAssertEqual(r.care.soapPrompt, 0, "a second tap with the card up changes nothing")
        r.care.chooseSoap(.mint)
        XCTAssertNil(r.care.soapPrompt); XCTAssertTrue(r.bath.active); XCTAssertEqual(r.bath.soap, .mint)
        XCTAssertEqual(r.care.store.count("mintsoap"), 1, "nothing is used up until the bath is finished")
        r.care.chooseSoap(.honey); XCTAssertEqual(r.bath.soap, .mint, "a late tap on a closed card does nothing")
        // a soap armed from the Bag is the pick: no card
        let bag = CleanRun(dirt: 0.4); Self.keep.append(bag)
        bag.care.store.grant("berrysoap")
        XCTAssertTrue(bag.care.useSupply("berrysoap", on: 0)); XCTAssertNil(bag.care.soapPrompt); XCTAssertEqual(bag.bath.soap, .berry)
        // a soap that is not owned cannot be chosen
        let nope = CleanRun(dirt: 0); Self.keep.append(nope)
        nope.care.store.grant("honeysoap"); nope.care.requestClean(); nope.care.chooseSoap(.mint)
        XCTAssertNotNil(nope.care.soapPrompt); XCTAssertFalse(nope.bath.active)
    }

    func testTheLastBarUsedMeansTheNextBathHasNoCardAndStartsCleanly() {
        let r = CleanRun(dirt: 0.4); Self.keep.append(r)
        defer { for k in PerkKind.allCases { r.care.jelly(0)?.perks.clear(k) } }
        r.care.store.grant("mintsoap")
        r.care.requestClean(); r.care.chooseSoap(.mint)
        r.care.soapFinished()          // the bath finished: the one bar is used up
        XCTAssertEqual(r.care.store.count("mintsoap"), 0)
        r.care.cancelClean(); r.run(8, scrubbing: false, autoNext: false)
        XCTAssertFalse(r.bath.active)
        r.care.requestClean()
        XCTAssertNil(r.care.soapPrompt, "no soap left: no card"); XCTAssertEqual(r.bath.phase, .exit); XCTAssertEqual(r.bath.soap, .jelly)
    }

    func testXClosesTheCardAndNothingIsStuck() {
        let r = CleanRun(dirt: 0); Self.keep.append(r)
        r.care.store.grant("lavender")
        r.care.requestClean(); XCTAssertEqual(r.care.soapPrompt, 0)
        r.care.dismissSoapCard()
        XCTAssertNil(r.care.soapPrompt); XCTAssertFalse(r.bath.active); XCTAssertTrue(r.care.canClean, "the menu works")
        XCTAssertEqual(r.care.armedSupplies[0] ?? [], [], "nothing armed")
        r.care.requestClean(); XCTAssertEqual(r.care.soapPrompt, 0, "the card opens again")
        r.care.chooseSoap(.jelly); XCTAssertTrue(r.bath.active)
    }

    func testTheCardClosesByItselfWhenTheMomentIsGone() {
        let r = CleanRun(dirt: 0); Self.keep.append(r)
        r.care.store.grant("lavender")
        r.care.requestClean(); XCTAssertEqual(r.care.soapPrompt, 0)
        r.care.callRunning = true; r.care.soapCardTick(); XCTAssertNil(r.care.soapPrompt, "a call closes it"); r.care.callRunning = false
        r.care.requestClean(); XCTAssertEqual(r.care.soapPrompt, 0)
        r.care.focus.force(.focused); r.care.soapCardTick(); XCTAssertNil(r.care.soapPrompt, "the come-here close-up closes it")
        let s = CleanRun(dirt: 0); Self.keep.append(s)
        s.care.store.grant("lavender"); s.care.requestClean(); XCTAssertEqual(s.care.soapPrompt, 0)
        s.care.store.use("lavender"); s.care.soapCardTick(); XCTAssertNil(s.care.soapPrompt, "no soap left: nothing to pick")
        // and it is the tick that does it
        let t = CleanRun(dirt: 0); Self.keep.append(t)
        t.care.store.grant("mintsoap"); t.care.requestClean(); t.care.callRunning = true
        for _ in 0..<3 { t.tick() }
        XCTAssertNil(t.care.soapPrompt, "the game step closes it")
    }

    func testCleanTappedTwiceFastIsOneBath() {
        let r = CleanRun(dirt: 0.3); Self.keep.append(r)
        r.care.requestClean(); r.care.requestClean(); r.care.clean()
        XCTAssertEqual(r.bath.phase, .exit); XCTAssertNil(r.care.soapPrompt)
        r.run(60, until: { r.bath.phase == .soap })
        XCTAssertEqual(r.bath.phase, .soap, "one bath, running normally")
        XCTAssertEqual(r.bath.swapLog.count, 1, "one world swap: a second bath never started")
        // with a soap too: two fast taps = one card
        let c = CleanRun(dirt: 0.3); Self.keep.append(c)
        c.care.store.grant("mintsoap"); c.care.requestClean(); c.care.requestClean()
        XCTAssertEqual(c.care.soapPrompt, 0); c.care.chooseSoap(.mint); c.care.chooseSoap(.mint)
        XCTAssertEqual(c.bath.phase, .exit)
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
