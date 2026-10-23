//
//  NightRestTests.swift
//  Bedtime is the player's call (GameCare+NightRest.swift): nobody goes to bed just because it is night; they go when told, or after the idle
//  rule; all three always go (the highlighted one too); selecting never wakes; a name / poke wakes only that one; a woken one goes back after a
//  while; coming back at night after a long time they are already asleep. Built on the real GameCare + three bodies (RaceTripTests.Room).
//  The idle rule's 180 s is shortened to 30 s here (`NightRestTuning.idleBedtime`); the rule is the same.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class NightRestTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var room: RaceTripTests.Room!
    private var care: GameCare { room.care }

    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        DayClock.shared.forcedHour = 23
        NightRestTuning.idleBedtime = 30
    }
    override func tearDown() {
        DayClock.shared.forcedHour = 12
        NightRestTuning.idleBedtime = 180
        DecorField.shared.clear()
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    private func make(seed: UInt64 = 5, hour: Double = 23) {
        DayClock.shared.forcedHour = hour
        let r = RaceTripTests.Room()
        Self.keep.append(r)
        room = r
        for a in r.actors {
            guard let b = a.brain else { continue }
            b.sleepEnabled = true; b.autonomy = true
            b.seed = seed &+ UInt64(a.id)
            b.socialOthers = { [unowned r] in r.actors.compactMap(\.brain) }
        }
    }
    private var brains: [BlobBrain] { room.actors.compactMap(\.brain) }
    private func step() {
        for b in brains { b.idleNight = DayClock.shared.nightFactor; b.idleMorning = DayClock.shared.morningFactor; b.idleDeepNight = DayClock.shared.deepNightFactor }
        room.step()
    }
    @discardableResult
    private func go(_ s: Float, until: (() -> Bool)? = nil) -> Bool {
        for _ in 0..<Int(s * 60) { step(); if let u = until, u() { return true } }
        return until?() ?? false
    }
    private var allNapping: Bool { brains.allSatisfy { $0.isNapping } }

    // MARK: the night alone does nothing

    func testNightAloneDoesNotPutAnyoneToSleep() {
        make()
        var asleep = false
        for _ in 0..<(25 * 60) { step(); if brains.contains(where: { $0.isSleeping }) { asleep = true; break } }
        XCTAssertFalse(asleep, "23:00 with the player idle for less than the bedtime rule: nobody chose bed by himself")
    }

    func testIdleAtNightPutsAllThreeToBed() {
        make()
        XCTAssertTrue(go(30 + 60, until: { self.allNapping }), "after the idle rule all three are asleep: \(brains.map { $0.sleep.stage })")
        XCTAssertTrue(brains.allSatisfy { $0.sleep.tucked }, "tucked in")
        XCTAssertEqual(brains[0].sleep.hold, NightRestTuning.untilMorning, "asleep until morning")
    }

    /// THE 3-JELBIE BUG: the highlighted one used to be skipped for good.
    func testTheHighlightedOneGoesToBedToo() {
        make()
        care.select.doubleTap(2)
        XCTAssertEqual(care.select.selectedID, 2)
        XCTAssertTrue(go(30 + 100, until: { self.allNapping }), "all three asleep, the highlighted one too: \(brains.map { $0.sleep.stage })")
    }

    func testBedtimeAllPutsAllThreeDownEvenInAFullRoom() {
        for seed in [5, 9] as [UInt64] {
            DecorField.shared.clear()
            let b = StoreBook(wallet: DropsWallet(persists: false), persists: false)
            for k in DecorTuning.fullRoom { b.grant(k.storeID); _ = b.place(k.storeID) }
            DecorField.shared.set(b.placedDecor)
            make(seed: seed)
            room.actors[2].sim.teleport(toXZ: SIMD2(3.0, -2.2))          // off the rug, in a corner
            room.actors[2].brain?.currentPose(room.actors[2].sim)
            care.bedtimeAll()
            XCTAssertTrue(go(60, until: { self.brains.allSatisfy { $0.isSleeping && $0.sleep.stage >= 3 } }), "seed \(seed): all three down within 60 s: \(brains.map { $0.sleep.stage })")
            let spots = brains.map { $0.sleep.spot }
            for i in 0..<3 {
                XCTAssertGreaterThan(RoomLayout.decorDistance(spots[i], solidOnly: true), 0.29, "seed \(seed): nobody inside solid decor")
                for j in (i + 1)..<3 { XCTAssertGreaterThan(simd_distance(spots[i], spots[j]), SleepTuning.minGap - 0.1, "seed \(seed): bodies apart") }
            }
        }
    }

    func testInteractionResetsTheIdleClock() {
        make()
        go(20)
        care.noteInteraction()
        go(20)         // 40 s in: the unbroken 30 s would have fired by now
        XCTAssertFalse(brains.contains { $0.isSleeping }, "an interaction restarted the clock")
        XCTAssertTrue(go(10 + 60, until: { self.allNapping }), "then all asleep after another idle stretch")
    }

    // MARK: waking

    private func allAsleep() {
        care.bedtimeAll()
        XCTAssertTrue(go(60, until: { self.allNapping }), "all asleep first: \(brains.map { $0.sleep.stage })")
    }

    func testSelectionDoesNotWakeASleeper() {
        make(); allAsleep()
        care.select.doubleTap(2)
        go(10)
        XCTAssertTrue(allNapping, "selecting a sleeper highlights him without waking anyone")
        XCTAssertGreaterThan(care.select.clock, 0.2, "and the outline is not held back")
    }

    func testPokeWakesOnlyThatSleeper() {
        make(); allAsleep()
        care.pokeSleeper(1)
        go(0.5)
        XCTAssertTrue(brains[1].sleep.groggy && brains[1].sleep.wakeAsked, "1 rolls up groggy")
        go(10)
        XCTAssertFalse(brains[1].isSleeping, "and is up")
        XCTAssertTrue(brains[0].isNapping && brains[2].isNapping, "0 and 2 sleep on")
    }

    func testNameWakesOnlyThatOne() {
        make(); allAsleep()
        care.voice.finish(VoiceDecision(reaction: .nameHeard, target: .jelly(1)), transcript: "moss")
        go(10)
        XCTAssertFalse(brains[1].isNapping, "the named one is waking / up")
        XCTAssertTrue(brains[0].isNapping && brains[2].isNapping, "the others stay asleep")
        XCTAssertFalse(brains[0].commandedNameHop, "a sleeper takes no name hop")
    }

    func testWokenAtNightGoesBackToBedAfterIdle() {
        make(); allAsleep()
        care.voice.finish(VoiceDecision(reaction: .nameHeard, target: .jelly(1)), transcript: "moss")
        go(8)
        XCTAssertFalse(brains[1].isSleeping, "up")
        go(60)
        care.noteInteraction(jelly: 1)
        go(100)
        XCTAssertFalse(brains[1].isSleeping, "still up 100 s after the last time he was played with")
        XCTAssertTrue(brains[0].isNapping && brains[2].isNapping, "the others sleep throughout")
        XCTAssertTrue(go(20 + 40, until: { self.brains[1].isNapping }), "then back to bed by himself")
    }

    func testWakeUpEveryoneWakesAll() {
        make(); allAsleep()
        care.voice.finish(VoiceDecision(reaction: .social(.wakeUp), target: .everyone), transcript: "wake up everyone")
        XCTAssertTrue(go(12, until: { self.brains.allSatisfy { !$0.isSleeping } }), "all awake: \(brains.map { $0.sleep.stage })")
        go(15)
        XCTAssertFalse(brains.contains { $0.isSleeping }, "and they do not go straight back to bed")
    }

    func testAnotherJellysBathOrCloseUpDoesNotWakeANapper() {
        make(hour: 13)
        let b = brains[2]
        b.idleForced = true
        XCTAssertTrue(b.idleStart(.sleep, room.actors[2].sim)); b.sleep.hold = 500
        XCTAssertTrue(go(30, until: { b.isNapping }))
        for _ in 0..<(10 * 60) { b.idleBlocked = true; step() }
        XCTAssertTrue(b.isNapping, "a bath / close-up elsewhere (idleBlocked) does not wake him")
    }

    func testPeersWalkingPastDoNotWakeSleepers() {
        make(hour: 13)
        for i in [0, 1] {
            let b = brains[i]; b.idleForced = true
            XCTAssertTrue(b.idleStart(.sleep, room.actors[i].sim)); b.sleep.hold = 500
        }
        brains[2].autonomy = true
        go(90)
        XCTAssertTrue(brains[0].isNapping && brains[1].isNapping, "the sleepers stay down while the third roams")
    }

    // MARK: away

    func testBackAtNightAfterALongAbsenceTheyAreAlreadyAsleep() {
        make()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let g0 = care.greetings
        care.leftActive(at: t0)
        care.returnedActive(at: t0.addingTimeInterval(2 * 3600))
        XCTAssertTrue(care.nightRest.arrivalAsleep)
        go(3)
        XCTAssertTrue(allNapping, "asleep within 3 s: \(brains.map { $0.sleep.stage })")
        XCTAssertEqual(care.greetings, g0, "no greeting")
        XCTAssertTrue(care.queued.isEmpty)
    }

    func testBackByDayAfterALongAbsenceTheyAreAwakeAndGreet() {
        make(hour: 13)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let g0 = care.greetings
        care.leftActive(at: t0)
        care.returnedActive(at: t0.addingTimeInterval(2 * 3600))
        go(2)
        XCTAssertFalse(care.nightRest.arrivalAsleep)
        XCTAssertFalse(brains.contains { $0.isSleeping })
        XCTAssertEqual(care.greetings, g0 + 1, "the usual greeting")
    }
}
