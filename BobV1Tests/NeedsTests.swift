//
//  NeedsTests.swift
//  Needs + mood v1: decay, the offline away curve, the first-launch seed, restores (meal, drink, petting), mood, the bubble schedule,
//  bubble tap -> action, roster card -> highlight, persistence round-trip.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class NeedsTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []         // the runtime aborts when these are released (see MelonModel)

    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = [] }

    private func suite() -> UserDefaults {
        let name = "needs.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    private func make(_ d: UserDefaults, now: @escaping () -> Date = Date.init) -> BlobNeeds {
        let n = BlobNeeds(defaults: d, now: now); Self.keep.append(n); return n
    }
    private func run(_ n: BlobNeeds, seconds: Float, dt: Float = 1, petting: Bool = false, purring: Bool = false) {
        for _ in 0..<Int(seconds / dt) { n.step(dt: dt, petting: petting, purring: purring) }
    }

    // MARK: seed + decay

    func testFirstLaunchIsSeededWithHungerWantingAndOnlyHunger() {
        let d = suite()
        let n = make(d)
        XCTAssertEqual(n.level(.hunger), NeedsTuning.seedHunger, accuracy: 1e-6)
        XCTAssertEqual(n.wantedNeed, .hunger, "open the app -> food bubble")
        XCTAssertEqual(n.wantingCount, 1)
        XCTAssertEqual(n.mood, .grumpy)
        // a later launch does not seed again
        n.restore(.hunger); n.save()
        let again = make(d)
        XCTAssertGreaterThan(again.level(.hunger), 0.99)
        XCTAssertNil(again.wantedNeed)
    }

    func testNeedsDecayInRealTimeAtTheTunedRates() {
        let n = make(suite())
        for k in NeedKind.allCases { n.set(k, 1) }
        run(n, seconds: 3600, dt: 10)                                   // one hour
        XCTAssertEqual(n.level(.hunger), 1 - 1.0 / 3, accuracy: 0.002, "hunger empties in about 3 h")
        XCTAssertEqual(n.level(.thirst), 1 - 1.0 / 2, accuracy: 0.002, "thirst in about 2 h")
        XCTAssertEqual(n.level(.attention), 1 - 1.0 / 4, accuracy: 0.002, "attention in about 4 h")
        run(n, seconds: 3600, dt: 10)
        XCTAssertLessThan(n.level(.thirst), 0.001)
        XCTAssertTrue(n.isWanting(.thirst))
        run(n, seconds: 3 * 3600, dt: 30)
        for k in NeedKind.allCases { XCTAssertEqual(n.level(k), 0, accuracy: 1e-6, "clamped at 0") }
    }

    func testWantingBelowPointThree() {
        let n = make(suite())
        for k in NeedKind.allCases { n.set(k, 1) }
        n.set(.thirst, 0.31); XCTAssertFalse(n.isWanting(.thirst)); XCTAssertNil(n.wantedNeed)
        n.set(.thirst, 0.29); XCTAssertTrue(n.isWanting(.thirst)); XCTAssertEqual(n.wantedNeed, .thirst)
    }

    // MARK: offline (the away curve; the full set is in TimeAwayTests)

    func testOfflineDecayUsesTheAwayCurveAndStopsAtTheFloor() {
        for hours in [0.5, 1.5, 2.5, 5.0, 40.0] {
            let d = suite()
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            let first = make(d, now: { t0 })
            for k in NeedKind.allCases { first.set(k, 0.8) }
            first.save()
            let later = make(d, now: { t0.addingTimeInterval(hours * 3600) })
            for k in NeedKind.allCases {
                let want = max(0.8 - Float(hours / NeedsTuning.awayHoursToEmpty(k)), NeedsTuning.awayFloor)
                XCTAssertEqual(later.level(k), want, accuracy: 1e-4, "\(hours) h away: \(k) on the away curve, never under the floor")
            }
        }
        // a need already under the floor is not raised by the time away
        let d = suite()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let first = make(d, now: { t0 })
        first.set(.hunger, 0.05); first.set(.thirst, 0.9); first.set(.attention, 0.9); first.save()
        let later = make(d, now: { t0.addingTimeInterval(20 * 3600) })
        XCTAssertEqual(later.level(.hunger), 0.05, accuracy: 1e-5, "not lifted to the floor")
        XCTAssertEqual(later.level(.thirst), NeedsTuning.awayFloor, accuracy: 1e-5)
        // (the old clampOne, which lifted the other needs to 0.35, is gone: it silently changed tiers and the away floor already does the job)
    }

    // MARK: restores

    func testPettingRestoresAttentionAndThePurrRestoresItFaster() {
        let n = make(suite())
        for k in NeedKind.allCases { n.set(k, 1) }
        n.set(.attention, 0.1)
        run(n, seconds: 10, dt: 1.0 / 60, petting: true)
        XCTAssertEqual(n.level(.attention), 0.1 + 10 * NeedsTuning.petRate, accuracy: 0.01, "about 0.05/s while petting")
        n.set(.attention, 0.1)
        run(n, seconds: 4, dt: 1.0 / 60, petting: true, purring: true)
        XCTAssertEqual(n.level(.attention), 0.1 + 4 * NeedsTuning.purrRate, accuracy: 0.01, "more during the purr")
        XCTAssertGreaterThan(NeedsTuning.purrRate, NeedsTuning.petRate)
        n.set(.attention, 0.1)
        run(n, seconds: 10, dt: 1, petting: false)
        XCTAssertLessThan(n.level(.attention), 0.1, "no petting, no restore")
    }

    func testFixingAWantingNeedFiresOnce() {
        let n = make(suite())
        for k in NeedKind.allCases { n.set(k, 1) }
        n.set(.attention, 0.2)
        var fired: [NeedKind] = []
        let before = n.fixedCount
        n.onFixed = { fired.append($0) }
        run(n, seconds: 3, dt: 1.0 / 60, petting: true)                 // 0.2 -> 0.35
        XCTAssertEqual(fired, [.attention]); XCTAssertEqual(n.fixedCount, before + 1); XCTAssertEqual(n.lastFixed, .attention)
        run(n, seconds: 3, dt: 1.0 / 60, petting: true)
        XCTAssertEqual(fired.count, 1, "once")
    }

    private func feedRun(_ id: String?, drink: String? = nil, dropAt: Float? = nil) -> (FocusRun, GameCare) {
        let r = FocusRun(); Self.keep.append(r)
        let care = r.care
        for k in NeedKind.allCases { care.needs.set(k, 0.9) }
        care.needs.set(.hunger, 0.1); care.needs.set(.thirst, 0.1)
        r.run(2)
        if let id { care.feed(id) }
        if let drink { care.drink(drink) }
        return (r, care)
    }

    func testAMealRestoresHunger() {
        let (r, care) = feedRun("berries")
        XCTAssertLessThan(care.needs.level(.hunger), 0.2)
        XCTAssertTrue(r.run(120) { care.needs.level(.hunger) > 0.99 && !care.trayOut }, "three bites -> hunger back to 1")
        XCTAssertLessThan(care.needs.level(.thirst), 0.2, "a meal does not feed the thirst")
    }

    func testADrinkRestoresThirst() {
        let (r, care) = feedRun(nil, drink: "water")
        XCTAssertTrue(r.run(120) { care.needs.level(.thirst) > 0.99 && !care.trayOut }, "three gulps -> thirst back to 1")
        XCTAssertLessThan(care.needs.level(.hunger), 0.2, "a drink does not feed the hunger")
    }

    func testADroppedMealRestoresNothing() {
        let (r, care) = feedRun("berries")
        r.run(3)
        care.comeHere()                                                  // drops the meal
        r.run(30)
        XCTAssertLessThan(care.needs.level(.hunger), 0.2, "he never finished it")
    }

    // MARK: mood

    func testMoodIsDerivedFromTheNeeds() {
        XCTAssertEqual(BlobNeeds.mood(of: [1, 1, 1]), .happy)
        XCTAssertEqual(BlobNeeds.mood(of: [0.6, 0.7, 0.9]), .happy, "all at 0.6 or more")
        XCTAssertEqual(BlobNeeds.mood(of: [0.59, 1, 1]), .okay)
        XCTAssertEqual(BlobNeeds.mood(of: [0.3, 0.3, 0.3]), .okay, "0.3 is not wanting")
        XCTAssertEqual(BlobNeeds.mood(of: [1, 1, 0.29]), .grumpy)
        let n = make(suite())
        for k in NeedKind.allCases { n.set(k, 1) }
        XCTAssertEqual(n.mood, .happy); XCTAssertNil(n.wantedNeed)
        n.set(.thirst, 0.5); XCTAssertEqual(n.mood, .okay)
        n.set(.thirst, 0.1); XCTAssertEqual(n.mood, .grumpy); XCTAssertEqual(n.wantedNeed, .thirst)
        n.restore(.thirst); XCTAssertEqual(n.mood, .happy)
        XCTAssertEqual(BlobMood.grumpy.word, "Grumpy")
        // the lowest wanting need is the wanted one
        n.set(.hunger, 0.25); n.set(.attention, 0.1)
        XCTAssertEqual(n.wantedNeed, .attention)
    }

    // MARK: bubble schedule

    func testBubbleAppearsThenRepeatsEveryTwentySecondsForSix() {
        var s = BubbleSchedule()
        var log: [(Float, BubbleSchedule.Event)] = []
        var t: Float = 0
        func advance(_ sec: Float, wanted: NeedKind? = .hunger, suppressed: Bool = false, pinned: Bool = false) {
            for _ in 0..<Int(sec * 60) { t += 1.0 / 60; for e in s.update(wanted: wanted, dt: 1.0 / 60, suppressed: suppressed, pinned: pinned) { log.append((t, e)) } }
        }
        advance(1.3); XCTAssertTrue(log.isEmpty, "a beat before it pops")
        advance(0.4)
        XCTAssertEqual(log.first?.1, .appeared(.hunger)); XCTAssertEqual(log.first?.0 ?? 0, 1.5, accuracy: 0.05)
        advance(6)
        XCTAssertEqual(log.last?.1, .disappeared(.hunger)); XCTAssertEqual(log.last?.0 ?? 0, 7.5, accuracy: 0.05, "shown ~6 s")
        advance(13)                                                      // t = 21.2: not yet
        XCTAssertEqual(log.count, 2)
        advance(0.9)
        XCTAssertEqual(log.count, 3); XCTAssertEqual(log[2].1, .appeared(.hunger)); XCTAssertEqual(log[2].0, 21.5, accuracy: 0.05, "every ~20 s")
        advance(6.1)
        XCTAssertEqual(log.last?.1, .disappeared(.hunger), "not permanent")
        XCTAssertFalse(s.visible)
    }

    func testBubbleHoldsWhenSuppressedStaysWhenPinnedAndFixedReportsVisibility() {
        var s = BubbleSchedule()
        func go(_ sec: Float, _ w: NeedKind?, sup: Bool = false, pin: Bool = false) -> [BubbleSchedule.Event] {
            var out: [BubbleSchedule.Event] = []
            for _ in 0..<Int(sec * 60) { out += s.update(wanted: w, dt: 1.0 / 60, suppressed: sup, pinned: pin) }
            return out
        }
        XCTAssertTrue(go(10, .thirst, sup: true).isEmpty, "held back in focus mode: the cycle waits")
        XCTAssertEqual(go(1.7, .thirst), [.appeared(.thirst)], "then the beat starts")
        XCTAssertEqual(go(0.2, .thirst, sup: true), [.disappeared(.thirst)], "focus mode pulls it down at once")
        _ = go(1, .thirst)
        XCTAssertTrue(s.visible, "back after focus")
        _ = go(10, .thirst, pin: true); XCTAssertTrue(s.visible, "pinned during his meal")
        XCTAssertEqual(go(0.1, nil), [.fixed(.thirst, wasVisible: true)], "fixed while up: poof with a sparkle")
        XCTAssertFalse(s.visible)
        _ = go(5, .attention, sup: true)
        XCTAssertEqual(go(0.1, nil), [.fixed(.attention, wasVisible: false)], "fixed while hidden still sparkles")
        XCTAssertEqual(go(3, .hunger), [.appeared(.hunger)])
        XCTAssertEqual(s.dismiss(), [.disappeared(.hunger)])
        XCTAssertTrue(go(10, .hunger).isEmpty, "a tapped bubble waits for its next turn")
        XCTAssertEqual(go(12, .hunger), [.appeared(.hunger), .disappeared(.hunger)])
    }

    // MARK: bubble tap -> action

    private func bubbleRun(wanting k: NeedKind) -> (FocusRun, GameCare) {
        let r = FocusRun(); Self.keep.append(r)
        let care = r.care
        for kk in NeedKind.allCases { care.needs.set(kk, 0.95) }
        care.needs.set(k, 0.1)
        return (r, care)
    }

    func testTappingTheBubbleOpensTheMatchingAction() {
        for (k, want) in [(NeedKind.hunger, BubbleAction.feed), (.thirst, .drink), (.attention, .comeHere)] {
            let (r, care) = bubbleRun(wanting: k)
            XCTAssertNil(care.tapBubble(), "no bubble yet")
            XCTAssertTrue(r.run(5) { care.bubbleNeed != nil }, "the \(k) bubble pops up")
            XCTAssertEqual(care.bubbleNeed, k)
            XCTAssertEqual(care.mood, .grumpy); XCTAssertEqual(care.wantedNeed, k)
            let serial = care.bubbleEnd.serial
            XCTAssertEqual(care.tapBubble(), want)
            XCTAssertNil(care.bubbleNeed, "it goes away when tapped")
            XCTAssertEqual(care.bubbleEnd.serial, serial + 1); XCTAssertFalse(care.bubbleEnd.fixed)
            if want == .comeHere { XCTAssertEqual(care.focus.phase, .approaching, "Come here") }
            else { XCTAssertEqual(care.focus.phase, .roaming) }
            // while focus is on the bubble stays down
            if want == .comeHere { r.run(8); XCTAssertNil(care.bubbleNeed) }
        }
    }

    func testTheBubblePoofsWithASparkleWhenTheMealFixesTheNeed() {
        let (r, care) = bubbleRun(wanting: .hunger)
        XCTAssertTrue(r.run(5) { care.bubbleNeed == .hunger })
        care.feed("berries")
        r.run(1.5)
        XCTAssertEqual(care.bubbleNeed, .hunger, "it stays up through his meal")
        let serial = care.bubbleEnd.serial
        XCTAssertTrue(r.run(120) { care.bubbleEnd.serial > serial }, "then it poofs")
        XCTAssertTrue(care.bubbleEnd.fixed, "with a sparkle"); XCTAssertEqual(care.bubbleEnd.need, .hunger)
        XCTAssertNil(care.bubbleNeed)
    }

    // MARK: roster -> highlight

    func testRosterCardPlaysTheHighlightOnBobEvenWithOneBlob() {
        let r = FocusRun(); Self.keep.append(r)
        let care = r.care, sel = care.select
        XCTAssertEqual(sel.count, 1)
        var starts = 0, meets = 0
        sel.onDrawStart = { starts += 1 }; sel.onMeet = { meets += 1 }
        care.rosterPick(0)
        XCTAssertEqual(sel.phase, .drawing(id: 0)); XCTAssertEqual(sel.drawStarts, 1); XCTAssertEqual(starts, 1)
        XCTAssertFalse(sel.chipVisible)
        r.run(0.5); XCTAssertEqual(sel.phase, .drawing(id: 0)); XCTAssertGreaterThan(sel.drawProgress, 0.05)
        r.run(0.8); XCTAssertEqual(sel.phase, .pending(id: 0)); XCTAssertEqual(meets, 1)
        XCTAssertTrue(sel.glowing); XCTAssertFalse(sel.chipVisible, "a roster pick has no check chip")
        r.run(2.5)
        XCTAssertEqual(sel.phase, .none); XCTAssertEqual(sel.confirmed, 0, "then the action button shows for him")
        XCTAssertTrue(sel.actionVisible)
        // no 2D stand-in: his outline only ever comes from the stage's real render mesh
        XCTAssertNil(sel.outlines[0])
    }

    func testRosterPickAmongSeveralStartsTheDrawOnThatBlobAndIsIgnoredInFocus() {
        let r = FocusRun(); Self.keep.append(r)
        let care = r.care, sel = care.select
        sel.setBlobs([SelectBlob(id: 0, name: "Bob"), SelectBlob(id: 1, name: "Pip", floor: SIMD2(-1, 1.5)), SelectBlob(id: 2, name: "Moss", floor: SIMD2(1, 0.1))])
        care.rosterPick(1); XCTAssertEqual(sel.phase, .drawing(id: 1))
        r.run(0.1)
        care.rosterPick(2); XCTAssertEqual(sel.phase, .drawing(id: 2), "another card restarts the draw")
        XCTAssertEqual(sel.drawStarts, 2)
        XCTAssertFalse(sel.actionVisible)
        sel.cancel()
        care.focus.force(.focused)
        care.rosterPick(1); XCTAssertEqual(sel.phase, .none, "the roster is hidden in focus mode")
        // other Blobs have needs of their own (preview Blobs, in memory)
        XCTAssertNotNil(care.needs(for: 1).wantedNeed); XCTAssertNotEqual(care.needs(for: 1).wantedNeed, care.needs(for: 2).wantedNeed)
    }

    // MARK: persistence

    func testPersistenceRoundTripAndTheTimestamp() {
        let d = suite()
        let t0 = localNoon(2_000_000)          // daytime: the night half-rate on the needs (AwayMath.needSeconds) does not apply to this hour
        let a = make(d, now: { t0 })
        a.set(.hunger, 0.8); a.set(.thirst, 0.7); a.set(.attention, 0.9)
        a.save()
        let same = make(d, now: { t0 })
        XCTAssertEqual(same.level(.hunger), 0.8, accuracy: 1e-6); XCTAssertEqual(same.level(.thirst), 0.7, accuracy: 1e-6); XCTAssertEqual(same.level(.attention), 0.9, accuracy: 1e-6)
        let hourLater = make(d, now: { t0.addingTimeInterval(3600) })
        XCTAssertEqual(hourLater.level(.hunger), 0.8 - 1.0 / 10, accuracy: 1e-4, "the offline hour decayed it on the away curve")
        XCTAssertEqual(hourLater.level(.thirst), 0.7 - 1.0 / 8, accuracy: 1e-4)
        XCTAssertEqual(hourLater.level(.attention), 0.9 - 1.0 / 6, accuracy: 1e-4)
        // restores save at once
        hourLater.restore(.hunger)
        let again = make(d, now: { t0.addingTimeInterval(3600) })
        XCTAssertEqual(again.level(.hunger), 1, accuracy: 1e-6)
        // autosave while playing
        let b = make(d, now: { t0 })
        b.set(.attention, 0.55)
        run(b, seconds: NeedsTuning.saveEvery + 1, dt: 1)
        let c = make(d, now: { t0 })
        XCTAssertEqual(c.level(.attention), 0.55, accuracy: 0.01)
    }

    // MARK: cost

    func testNeedsAndBubbleCostPerFrameIsTiny() {
        let n = make(suite()); var sch = BubbleSchedule()
        let t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<20000 { n.step(dt: 1.0 / 60); _ = sch.update(wanted: n.wantedNeed, dt: 1.0 / 60, suppressed: false, pinned: false) }
        let step = (CFAbsoluteTimeGetCurrent() - t0) / 20000 * 1e6
        let t1 = CFAbsoluteTimeGetCurrent()
        var acc: CGFloat = 0
        for _ in 0..<5000 { acc += ThoughtBubbleView.project(SIMD3(0, 1.5, 1.5), size: CGSize(width: 440, height: 956), focus: 0)?.x ?? 0 }
        let proj = (CFAbsoluteTimeGetCurrent() - t1) / 5000 * 1e6
        NSLog("[needs] perf: needs.step + schedule %.2f us per sim step, bubble projection %.2f us per frame (%f)", step, proj, acc)
        XCTAssertLessThan(step, 20); XCTAssertLessThan(proj, 100)
    }
}
