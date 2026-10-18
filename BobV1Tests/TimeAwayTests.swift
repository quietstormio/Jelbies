//
//  TimeAwayTests.swift
//  Time away: needs on the away curve with a floor, and the sparkle, the greeting, and the "one path" rules (cold launch == foreground
//  resume, the periodic save cannot eat away time, a negative clock change does nothing). The clock is injected: `at:` / `now:` closures.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TimeAwayTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []         // the runtime aborts when these are released (see MelonModel)
    let t0 = Date(timeIntervalSince1970: 3_000_000)
    let hour: TimeInterval = 3600

    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = [] }

    private func suite() -> UserDefaults {
        let name = "timeaway.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    private func needs(_ d: UserDefaults, now: Date) -> BlobNeeds {
        let n = BlobNeeds(defaults: d, now: { now }); Self.keep.append(n); return n
    }
    private func full(_ n: BlobNeeds) { for k in NeedKind.allCases { n.set(k, 1) } }
    private func levels(_ n: BlobNeeds) -> [Float] { NeedKind.allCases.map { n.level($0) } }
    private func grime(_ d: UserDefaults, now: Date) -> BlobGrime {
        let g = BlobGrime(persists: true, defaults: d, now: { now }); Self.keep.append(g); return g
    }

    // MARK: needs

    func testThreeHoursAwayMatchesTheCurve() {
        let n = needs(suite(), now: t0)
        full(n)
        n.leaveActive(at: t0)
        let applied = n.returnActive(at: t0.addingTimeInterval(3 * hour))
        XCTAssertEqual(applied, 3 * hour, accuracy: 1e-6)
        XCTAssertEqual(n.level(.hunger), 0.70, accuracy: 0.01)
        XCTAssertEqual(n.level(.thirst), 0.625, accuracy: 0.01)
        XCTAssertEqual(n.level(.attention), 0.50, accuracy: 0.01)
        XCTAssertEqual(n.mood, .okay)
        XCTAssertNil(n.wantedNeed, "not wanting yet after 3 h")
    }

    func testOvernightLandsOnTheFloorNotAtZero() {
        for (name, secs) in [("8 h", 8 * hour), ("24 h", 24 * hour), ("14 days", 14 * 24 * hour), ("30 days", 30 * 24 * hour), ("a year", 365 * 24 * hour)] {
            let n = needs(suite(), now: t0)
            full(n)
            n.leaveActive(at: t0)
            n.returnActive(at: t0.addingTimeInterval(secs))
            for k in NeedKind.allCases { XCTAssertEqual(n.level(k), NeedsTuning.awayFloor, accuracy: 0.01, "\(name): \(k) at the floor") ; XCTAssertGreaterThan(n.level(k), 0.19) }
            XCTAssertEqual(n.wantingCount, 3, "\(name): he wants things")
        }
    }

    func testAwayDoesNotRaiseANeedThatWasAlreadyLower() {
        let n = needs(suite(), now: t0)
        full(n); n.set(.thirst, 0.1)
        n.leaveActive(at: t0)
        n.returnActive(at: t0.addingTimeInterval(24 * hour))
        XCTAssertEqual(n.level(.thirst), 0.1, accuracy: 1e-5)
        XCTAssertEqual(n.level(.hunger), NeedsTuning.awayFloor, accuracy: 1e-5)
    }

    func testColdLaunchAndForegroundResumeGiveTheSameResult() {
        for secs in [600.0, 3 * hour, 5 * hour, 30 * hour] {
            // resume: background, then foreground
            let a = needs(suite(), now: t0)
            a.set(.hunger, 0.9); a.set(.thirst, 0.8); a.set(.attention, 0.95)
            a.leaveActive(at: t0)
            a.returnActive(at: t0.addingTimeInterval(secs))
            // cold launch: the same state saved, a new process opens `secs` later
            let d = suite()
            let b = needs(d, now: t0)
            b.set(.hunger, 0.9); b.set(.thirst, 0.8); b.set(.attention, 0.95)
            b.leaveActive(at: t0)
            let c = needs(d, now: t0.addingTimeInterval(secs))
            XCTAssertEqual(levels(a), levels(c), "\(secs) s")
            XCTAssertEqual(a.lastAway, c.lastAway, accuracy: 1e-6)
        }
    }

    func testThePeriodicSaveDoesNotEatTheAwayTime() {
        let d = suite()
        var clock = t0
        let n = BlobNeeds(defaults: d, now: { clock }); Self.keep.append(n)
        full(n)
        n.leaveActive(at: t0)
        // 5 h pass in the background; a periodic save fires meanwhile (step() autosaves every saveEvery seconds)
        clock = t0.addingTimeInterval(5 * hour)
        for _ in 0..<Int(NeedsTuning.saveEvery) + 2 { n.step(dt: 1) }
        n.save()
        let applied = n.returnActive(at: clock)
        XCTAssertEqual(applied, 5 * hour, accuracy: 1, "the background save did not advance the stamp")
        XCTAssertEqual(n.level(.hunger), 0.5, accuracy: 0.01)
        XCTAssertEqual(n.level(.attention), NeedsTuning.awayFloor, accuracy: 0.02, "5 h of the 6 h curve is already near the floor")
        // and a process that is killed in the background still measures from the time it left
        let n2 = needs(d, now: t0.addingTimeInterval(5 * hour))
        XCTAssertEqual(n2.level(.hunger), 0.5, accuracy: 0.02)
    }

    func testAForegroundReturnAppliesOnceAndTwoActivesDoNotDoubleCount() {
        let n = needs(suite(), now: t0)
        full(n)
        n.leaveActive(at: t0); n.leaveActive(at: t0.addingTimeInterval(60))          // inactive then background: the earliest stamp wins
        XCTAssertEqual(n.returnActive(at: t0.addingTimeInterval(2 * hour)), 2 * hour, accuracy: 1e-6)
        let h = n.level(.hunger)
        XCTAssertEqual(n.returnActive(at: t0.addingTimeInterval(4 * hour)), 0, "no matching leave: nothing")
        XCTAssertEqual(n.level(.hunger), h)
    }

    func testNegativeClockSkewDoesNothing() {
        let n = needs(suite(), now: t0)
        full(n); n.set(.hunger, 0.7)
        n.leaveActive(at: t0)
        XCTAssertEqual(n.returnActive(at: t0.addingTimeInterval(-6 * hour)), 0)
        XCTAssertEqual(n.level(.hunger), 0.7, accuracy: 1e-6)
        XCTAssertEqual(n.level(.thirst), 1, accuracy: 1e-6)
        // a cold launch with the saved time in the future likewise
        let d = suite()
        let a = needs(d, now: t0); full(a); a.save()
        let b = needs(d, now: t0.addingTimeInterval(-3 * hour))
        for k in NeedKind.allCases { XCTAssertEqual(b.level(k), 1, accuracy: 1e-6) }
        XCTAssertEqual(TimeAway.clamp(-5), 0); XCTAssertEqual(TimeAway.clamp(.infinity), 0); XCTAssertEqual(TimeAway.clamp(1e12), TimeAway.maxAway)
    }

    func testInAppRatesAreUnchanged() {
        XCTAssertEqual(NeedsTuning.hoursToEmpty(.hunger), 3); XCTAssertEqual(NeedsTuning.hoursToEmpty(.thirst), 2); XCTAssertEqual(NeedsTuning.hoursToEmpty(.attention), 4)
        XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.hunger), 10); XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.thirst), 8); XCTAssertEqual(NeedsTuning.awayHoursToEmpty(.attention), 6)
    }

    // MARK: dirt away

    private func awayDirt(_ secs: TimeInterval, startingAt have: Float = 0) -> Float {
        let g = BlobGrime(persists: false)
        g.addDirt(have)
        g.leaveActive(at: t0)
        g.returnActive(at: t0.addingTimeInterval(secs))
        return g.dirt - have
    }

    func testDirtAwayIsPointZeroFivePerTwoHoursAtMostPointOneFive() {
        XCTAssertEqual(awayDirt(0), 0)
        XCTAssertEqual(awayDirt(1 * hour), 0.025, accuracy: 1e-5)
        XCTAssertEqual(awayDirt(2 * hour), 0.05, accuracy: 1e-5)
        XCTAssertEqual(awayDirt(5 * hour), 0.125, accuracy: 1e-5)
        XCTAssertEqual(awayDirt(6 * hour), 0.15, accuracy: 1e-5)
        XCTAssertEqual(awayDirt(3 * 24 * hour), 0.15, accuracy: 1e-5, "at most +0.15 from one absence")
        XCTAssertEqual(awayDirt(14 * 24 * hour), 0.15, accuracy: 1e-5)
        XCTAssertEqual(awayDirt(3 * 24 * hour, startingAt: 0.95), 0.05, accuracy: 1e-5, "never above 1")
        XCTAssertEqual(awayDirt(-5 * hour), 0, "negative clock change")
    }

    func testDirtAwayColdLaunchEqualsResumeAndIsPersisted() {
        let d = suite()
        let a = grime(d, now: t0)
        a.addDirt(0.3); a.leaveActive(at: t0)
        let b = grime(d, now: t0.addingTimeInterval(5 * hour))      // a new process 5 h later
        XCTAssertEqual(b.dirt, 0.3 + 0.125, accuracy: 1e-5)
        XCTAssertEqual(b.lastAway, 5 * hour, accuracy: 1e-6)
        let c = grime(d, now: t0.addingTimeInterval(5 * hour))      // opening again right away: the 5 h are not applied twice
        XCTAssertEqual(c.dirt, 0.3 + 0.125, accuracy: 1e-5)
        // resume gives the same
        let r = BlobGrime(persists: false); r.addDirt(0.3); r.leaveActive(at: t0); r.returnActive(at: t0.addingTimeInterval(5 * hour))
        XCTAssertEqual(r.dirt, b.dirt, accuracy: 1e-6)
    }

    func testTheBackgroundGrimeSaveDoesNotEatTheAwayTime() {
        var clock = t0
        let d = suite()
        let g = BlobGrime(persists: true, defaults: d, now: { clock }); Self.keep.append(g)
        g.leaveActive(at: t0)
        clock = t0.addingTimeInterval(5 * hour)
        g.step(dt: GrimeTuning.saveEvery + 1, travelled: 0)        // a periodic save in the background
        XCTAssertEqual(g.returnActive(at: clock), 5 * hour, accuracy: 1)
        XCTAssertEqual(g.dirt, 0.125, accuracy: 1e-4)
    }

    // MARK: coat tiers

    func testCoatTiersComeFromDirtAndSparkle() {
        let t = GrimeTuning.self
        XCTAssertEqual(BlobGrime.CoatTier.of(dirt: 0, sparkle: 0.5), .beautiful)
        XCTAssertEqual(BlobGrime.CoatTier.of(dirt: 0.049, sparkle: 0.5), .beautiful)
        XCTAssertEqual(BlobGrime.CoatTier.of(dirt: 0, sparkle: 0), .clean)
        XCTAssertEqual(BlobGrime.CoatTier.of(dirt: 0.049, sparkle: 0), .clean)
        XCTAssertEqual(BlobGrime.CoatTier.of(dirt: t.cleanBelow, sparkle: 0), .normal)
        XCTAssertEqual(BlobGrime.CoatTier.of(dirt: 0.34, sparkle: 0), .normal)
        XCTAssertEqual(BlobGrime.CoatTier.of(dirt: t.normalBelow, sparkle: 0), .dirty)
        XCTAssertEqual(BlobGrime.CoatTier.of(dirt: 0.69, sparkle: 0), .dirty)
        XCTAssertEqual(BlobGrime.CoatTier.of(dirt: t.dirtyBelow, sparkle: 0), .filthy)
        XCTAssertEqual(BlobGrime.CoatTier.of(dirt: 1, sparkle: 0), .filthy)
        XCTAssertEqual(BlobGrime.CoatTier.allCases.map(\.word), ["Beautiful", "Clean", "Normal", "Dirty", "Filthy"])
        let g = BlobGrime(persists: false)
        g.sparkle = 1; XCTAssertEqual(g.coat, .beautiful)
        g.addDirt(0.04); XCTAssertEqual(g.coat, .beautiful, "a little dirt keeps the shine")
        g.addDirt(0.02); XCTAssertEqual(g.coat, .normal); XCTAssertEqual(g.sparkle, 0, "the sparkle ends when he stops being clean")
    }

    func testExertionMakesDirtThreeTimesFaster() {
        let a = BlobGrime(persists: false), b = BlobGrime(persists: false)
        a.step(dt: 1, travelled: 10); b.step(dt: 1, travelled: 10, exerting: true)
        XCTAssertEqual(b.dirt, a.dirt * 3, accuracy: 1e-6)
        for _ in 0..<2000 { b.step(dt: 1, travelled: 5, exerting: true) }
        XCTAssertEqual(b.dirt, 1)
    }

    func testAFinishedCleanSetsDirtToZero() {
        let r = CleanRun(dirt: 0)
        Self.keep.append(r)
        r.care.bath.grime.addDirt(0.8)
        r.care.clean()
        r.run(60, until: { r.bath.phase == .off && r.phases.contains(.finish) })
        XCTAssertEqual(r.care.bath.grime.dirt, 0)
        XCTAssertEqual(r.care.bath.grime.coat, .beautiful)
    }

    // MARK: need tiers

    func testNeedTiersAndWords() {
        let n = needs(suite(), now: t0)
        func tier(_ v: Float) -> NeedTier { n.set(.hunger, v); return n.tier(.hunger) }
        XCTAssertEqual(tier(1), .full); XCTAssertEqual(tier(0.85), .full)
        XCTAssertEqual(tier(0.849), .normal); XCTAssertEqual(tier(0.5), .normal)
        XCTAssertEqual(tier(0.499), .hungry); XCTAssertEqual(tier(0.2), .hungry)
        XCTAssertEqual(tier(0.199), .famished); XCTAssertEqual(tier(0), .famished)
        XCTAssertEqual(NeedTier.allCases.map { $0.word(.hunger) }, ["Full", "Normal", "Hungry", "Famished"])
        XCTAssertEqual(NeedTier.allCases.map { $0.word(.thirst) }, ["Quenched", "Normal", "Thirsty", "Parched"])
        XCTAssertEqual(NeedTier.allCases.map { $0.word(.attention) }, ["Content", "Normal", "Lonely", "Neglected"])
        n.set(.thirst, 0.1); XCTAssertEqual(n.tier(.thirst), .famished)
    }

    func testTheAwayFloorIsTheFamishedBoundaryAndAwayNeverFamishes() {
        XCTAssertEqual(NeedsTuning.awayFloor, NeedsTuning.famishedBelow)
        for secs in [8 * hour, 24 * hour, 400 * 24 * hour] {
            let n = needs(suite(), now: t0)
            full(n); n.leaveActive(at: t0); n.returnActive(at: t0.addingTimeInterval(secs))
            for k in NeedKind.allCases { XCTAssertEqual(n.tier(k), .hungry, "\(k) after \(secs / hour) h away is Hungry, not Famished") }
        }
        // in-app neglect does get there
        let n = needs(suite(), now: t0)
        full(n)
        for _ in 0..<(4 * 3600 / 10) { n.step(dt: 10) }
        XCTAssertEqual(n.tier(.thirst), .famished)
    }

    func testExertionDrainsHungerAndThirstFaster() {
        let calm = needs(suite(), now: t0), hard = needs(suite(), now: t0)
        full(calm); full(hard)
        for _ in 0..<120 { calm.step(dt: 10); hard.step(dt: 10, exerting: true) }
        for k in [NeedKind.hunger, .thirst] {
            XCTAssertEqual(1 - hard.level(k), (1 - calm.level(k)) * Float(NeedsTuning.exertionDrain), accuracy: 0.002, "\(k) drains 3x")
        }
        XCTAssertEqual(hard.level(.attention), calm.level(.attention), accuracy: 1e-6, "attention is not exertion")
    }

    func testTheBrainReportsExertionForRunsAndZoomiesButNotAWalk() {
        let r = CleanRun(dirt: 0)
        Self.keep.append(r)
        XCTAssertFalse(r.brain.isExerting)
        r.brain.runW = 1; XCTAssertTrue(r.brain.isExerting); r.brain.runW = 0
        r.brain.zoomW = 1; XCTAssertTrue(r.brain.isExerting); r.brain.zoomW = 0
        r.brain.hurry = true; XCTAssertTrue(r.brain.isExerting); r.brain.hurry = false
        XCTAssertFalse(r.brain.isExerting)
    }

    // MARK: bath bubble

    func testTheBathBubbleShowsAtDirtyAndMoreOftenAtFilthy() {
        func shows(_ dirt: Float, seconds: Float) -> Int {
            var s = CoatBubbleSchedule(); var ups = 0
            let coat = BlobGrime.CoatTier.of(dirt: dirt, sparkle: 0)
            for _ in 0..<Int(seconds * 10) { if s.update(coat: coat, dt: 0.1, suppressed: false), s.visible { ups += 1 } }
            return ups
        }
        XCTAssertEqual(shows(0.2, seconds: 300), 0, "Normal: no bath bubble")
        XCTAssertEqual(shows(0.0, seconds: 300), 0)
        let dirty = shows(0.5, seconds: 300), filthy = shows(0.9, seconds: 300)
        XCTAssertGreaterThanOrEqual(dirty, 5); XCTAssertLessThanOrEqual(dirty, 8)
        XCTAssertGreaterThan(filthy, dirty * 2, "Filthy is more insistent")
    }

    func testTheBathBubbleSharesTheSlotAndTapOpensClean() {
        let r = CleanRun(dirt: 0)
        Self.keep.append(r)
        let care = r.care
        for k in NeedKind.allCases { care.needs.set(k, 1) }
        care.bath.grime.addDirt(0.5)                                  // Dirty
        r.run(8, scrubbing: false, until: { care.bubbleClean })
        XCTAssertTrue(care.bubbleClean, "the bath bubble comes up at Dirty")
        XCTAssertNil(care.bubbleNeed); XCTAssertEqual(care.bubbleIcon, .clean)
        XCTAssertEqual(care.tapBubble(), .clean)
        XCTAssertTrue(care.bath.active || care.bath.phase != .off || !care.bubbleClean)
        XCTAssertFalse(care.bubbleClean)
    }

    func testFilthyTakesTheSlotFromAHungryNeedButNotFromAFamishedOne() {
        // hungry-tier need + Filthy: the bath bubble wins
        let a = CleanRun(dirt: 0); Self.keep.append(a)
        for k in NeedKind.allCases { a.care.needs.set(k, 1) }
        a.care.needs.set(.hunger, 0.25)
        a.care.bath.grime.addDirt(0.9)
        var sawClean = false
        a.run(60, scrubbing: false, until: { if a.care.bubbleClean { sawClean = true }; return sawClean })
        XCTAssertTrue(sawClean, "Filthy shows the bath bubble although he is Hungry")
        XCTAssertNil(a.care.bubbleNeed, "one bubble at a time")
        // famished: the need keeps the slot, the bath bubble never preempts it
        let b = CleanRun(dirt: 0); Self.keep.append(b)
        for k in NeedKind.allCases { b.care.needs.set(k, 1) }
        b.care.needs.set(.hunger, 0.05)
        b.care.bath.grime.addDirt(0.9)
        var both = false, sawNeed = false
        b.run(40, scrubbing: false, until: { if b.care.bubbleNeed != nil { sawNeed = true }; if b.care.bubbleNeed != nil && b.care.bubbleClean { both = true }; return false })
        XCTAssertTrue(sawNeed); XCTAssertFalse(both, "never two bubbles")
    }

    // MARK: sparkle

    func testSparkleIsGoneAfterTenMinutesInAppAndAway() {
        XCTAssertEqual(GrimeTuning.sparkleFade, 600)
        let g = BlobGrime(persists: false)
        g.sparkle = 1
        for _ in 0..<300 { g.step(dt: 1, travelled: 0) }
        XCTAssertEqual(g.sparkle, 0.5, accuracy: 0.01, "half after 5 min")
        for _ in 0..<301 { g.step(dt: 1, travelled: 0) }
        XCTAssertEqual(g.sparkle, 0, accuracy: 1e-4, "gone after 10 min in the room")
        let a = BlobGrime(persists: false)
        a.sparkle = 1
        a.leaveActive(at: t0); a.returnActive(at: t0.addingTimeInterval(300))
        XCTAssertEqual(a.sparkle, 0.5, accuracy: 0.01, "the same rate away")
        a.sparkle = 1
        a.leaveActive(at: t0); a.returnActive(at: t0.addingTimeInterval(601))
        XCTAssertEqual(a.sparkle, 0, accuracy: 1e-4, "gone after 10 min away")
        // two hours away ends it by dirt too (and the clock anyway)
        let d = suite()
        let s = grime(d, now: t0); s.sparkle = 1; s.save()
        XCTAssertEqual(grime(d, now: t0.addingTimeInterval(450)).sparkle, 0.25, accuracy: 0.01)
    }

    // MARK: room dirt rate (measured)

    /// Normal roaming, headless: the real GameCare + BathFlow feed, autonomy on. Measures the floor speed of his non-exertion roaming.
    func testRoomDirtIsPointZeroTwoPerFiveMinutesOfNormalRoaming() {
        var speeds: [Float] = [], exertFrac: [Float] = []
        for seed: UInt64 in [3, 17, 41] {
            let r = CleanRun(dirt: 0)
            Self.keep.append(r)
            r.brain.autonomy = true
            r.brain.seed = seed
            var last = GameCare.floorPos(r.brain, r.sim)
            var distN: Float = 0, tN: Float = 0, tE: Float = 0
            let total: Float = 8 * 60
            r.run(total, scrubbing: false, until: {
                let here = GameCare.floorPos(r.brain, r.sim)
                let ex = r.brain.isExerting
                let moving = r.brain.activity == .walking || r.brain.activity == .coming || r.brain.runW > 0.1 || ex
                let d = simd_length(here - last)
                if ex { tE += r.sim.stepDt } else { tN += r.sim.stepDt; if moving && d < 0.5 { distN += d } }
                last = here
                return false
            })
            speeds.append(distN / tN); exertFrac.append(tE / total)
        }
        let avg = speeds.reduce(0, +) / Float(speeds.count)
        let msg = "TIMEAWAY normal roaming speed \(avg) u/s per seed \(speeds); exertion fraction of time \(exertFrac); units per 5 min \(avg * 300) (tuned \(GrimeTuning.roamUnitsPer5Min))"
        print(msg); MotionLog.write(msg)
        XCTAssertEqual(avg * 300, GrimeTuning.roamUnitsPer5Min, accuracy: GrimeTuning.roamUnitsPer5Min * 0.3, "0.02 dirt per 5 min of normal roaming: \(msg)")
    }

    // MARK: greeting

    func testGreetingFiresAfterThirtyMinutesAndNotAfterFive() {
        let short = CleanRun(dirt: 0)
        short.care.leftActive(at: t0)
        short.care.returnedActive(at: t0.addingTimeInterval(5 * 60))
        XCTAssertEqual(short.care.greetings, 0, "5 min away: no greeting")

        let r = CleanRun(dirt: 0)
        r.brain.request(.goTo(SIMD2(-2, -1.5))); r.run(12, scrubbing: false)          // start away from the front
        r.care.leftActive(at: t0)
        r.care.returnedActive(at: t0.addingTimeInterval(31 * 60))
        XCTAssertEqual(r.care.greetings, 1, "31 min away: greets")
        var seen: Set<BlobActivity> = []
        r.run(25, scrubbing: false, until: { seen.insert(r.brain.activity); return false })
        XCTAssertTrue(seen.contains(.coming), "he comes to the front")
        XCTAssertLessThan(simd_length(r.rig.root - VoiceCoordinator.comeSpot), 0.8, "and ends at the front spot")
        XCTAssertTrue(seen.contains(.playing), "with a happy hop")
        XCTAssertFalse(r.care.focus.isActive, "no close-up")
        FeetAttachTests.check("greeting", r.feet, frames: r.feetFrames)
    }

    func testGreetingIsSkippedWhileAMealBathOrVoiceIsOn() {
        let meal = CleanRun(dirt: 0)
        meal.care.feed("berries")
        meal.run(0.2, scrubbing: false)
        meal.care.leftActive(at: t0); meal.care.returnedActive(at: t0.addingTimeInterval(2 * hour))
        XCTAssertEqual(meal.care.greetings, 0, "a meal is on")

        let bath = CleanRun(dirt: 0)
        bath.care.clean()
        bath.run(0.2, scrubbing: false)
        bath.care.leftActive(at: t0); bath.care.returnedActive(at: t0.addingTimeInterval(2 * hour))
        XCTAssertEqual(bath.care.greetings, 0, "a clean-up is on")

        let voice = CleanRun(dirt: 0)
        XCTAssertTrue(voice.care.voice.begin())
        voice.care.leftActive(at: t0); voice.care.returnedActive(at: t0.addingTimeInterval(2 * hour))
        XCTAssertEqual(voice.care.greetings, 0, "he is listening")
        voice.care.voice.cancel()

        let ok = CleanRun(dirt: 0)
        ok.care.leftActive(at: t0); ok.care.returnedActive(at: t0.addingTimeInterval(2 * hour))
        XCTAssertEqual(ok.care.greetings, 1)
    }

    func testColdLaunchGreetsOnceAfterALongAbsence() {
        let r = CleanRun(dirt: 0)
        r.care.needs.applyAway(seconds: 3 * hour)               // what the loader did on this launch
        r.care.launched(); r.care.launched()
        XCTAssertEqual(r.care.greetings, 1, "once")
        let q = CleanRun(dirt: 0)
        q.care.needs.applyAway(seconds: 600)
        q.care.launched()
        XCTAssertEqual(q.care.greetings, 0)
    }
}
