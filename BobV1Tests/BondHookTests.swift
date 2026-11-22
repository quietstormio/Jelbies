//
//  BondHookTests.swift
//  INTEGRATION tests for the Relationship hooks (Jelly/JellyBond.swift, GameCare+Bond.swift): each one goes through the real GameCare path (the touch frame, the dining flow,
//  the bath / spa / park trips, the toys, the voice coordinator, the race / show / volley flows, the launch paths) and asserts that the right Jelmiko's points rise by the
//  expected amount once and that the per-day cap then holds. Points live in the care's own scratch defaults (`care.bondDefaults`).
//

import XCTest
import simd
@testable import BobV1

@MainActor
private final class HClock { var t: Double = 100 }
@MainActor
private final class HNoMic: SpeechInput {
    var availability: VoiceAvailability = .ready
    var onLevel: ((Float) -> Void)?
    func prepare(contextualWords: [String]) async {}
    func start(contextualWords: [String]) async throws { throw SpeechInputError.notReady }
    func stop() async -> String { "" }
}

@MainActor
final class BondHookTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private typealias Room = RaceThreeTests.Room
    private var savedHour: Double?
    private var clock = HClock()

    override func setUp() {
        savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 14
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        SleepOrder.reset(); GameMessageCenter.shared.clear()
    }
    override func tearDown() {
        DayClock.shared.forcedHour = savedHour
        JellyTraitsBook.reload()
        GameMessageCenter.shared.clear()
        GameCamera.endPark(count: 3); GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); _ = GameCamera.camera(aspect: 440.0 / 956.0); RoomLayout.apply(RoomCatalog.home)
    }

    // MARK: helpers

    private func char(_ c: GameCare, _ slot: Int) -> Int { c.jelly(slot)!.character }
    private func pts(_ c: GameCare, _ slot: Int) -> Int { JellyBond.points(char(c, slot), c.bondDefaults) }
    private func today(_ c: GameCare, _ slot: Int, _ k: BondKind) -> Int { JellyBond.today(char(c, slot), c.bondDefaults)[k.rawValue] ?? 0 }
    private func reset(_ c: GameCare) { for j in c.jellies { JellyBond.remove(j.character, c.bondDefaults); JellyBond.seedIfNeeded(j.character, c.bondDefaults) } }
    private func all(_ c: GameCare) -> [Int] { c.jellies.indices.map { pts(c, $0) } }
    private func hasKey(_ d: UserDefaults, _ c: Int) -> Bool { d.object(forKey: JellyBond.key(c)) != nil }
    private func fullNeeds(_ c: GameCare) { for j in c.jellies { for k in NeedKind.allCases { j.needs.set(k, 1) } } }

    private func focusRun() -> FocusAnyRun {
        let r = FocusAnyRun(); Self.keep.append(r)
        reset(r.care); fullNeeds(r.care)
        r.run(0.5)
        return r
    }

    // MARK: (1) strokes through TouchPlay.petFrame

    private func stroke(slot: Int, seconds: Float, annoyed: Bool = false) -> (FocusAnyRun, [Int]) {
        let r = focusRun(), care = r.care
        care.comeHere(jelly: slot)
        XCTAssertTrue(r.run(30) { care.focus.isFocused }, "the close-up on \(slot)")
        let play = TouchPlay(); Self.keep.append(play); care.touchPlay = play
        play.mood = annoyed ? .grumpy : .happy; play.attentionWanted = false
        let surface = RestSurface(mesh: MotionRig.renderMesh); Self.keep.append(surface)
        let a = r.actors[slot]
        let eye = SIMD3<Float>(0, 0.9, 6)
        var t: Float = 0, now = 100.0
        let before = all(care)
        while t < seconds {
            let e = BodyEllipsoid(sim: a.sim)
            let p = e.center + e.rot.act(SIMD3(0.38 + 0.12 * sinf(2 * .pi * 1.2 * t), 0.15, 0))
            play.petFrame(dt: 1 / 60, now: now, ray: (eye, simd_normalize(p - eye)), screen: SIMD2(0.5, 0.5), sim: a.sim, brain: a.brain, skinner: a.skinner, surface: surface)
            r.tick(); t += 1 / 60; now += 1 / 60
        }
        return (r, zip(all(care), before).map { $0 - $1 })
    }

    func testAnEnjoyedStrokeOnSlotZeroEarnsOnceAndTheCapHolds() {
        let (r, d) = stroke(slot: 0, seconds: 5)
        XCTAssertEqual(d, [BondTuning.points(.stroke), 0, 0], "4 s of stroking = one stroke event, only for Jelmiko 0")
        _ = r
        let (r2, d2) = stroke(slot: 0, seconds: 24)
        XCTAssertEqual(d2, [BondTuning.dayCap(.stroke), 0, 0], "24 s of stroking stops at the per-day stroke cap")
        XCTAssertEqual(today(r2.care, 0, .stroke), BondTuning.dayCap(.stroke))
    }

    func testAnEnjoyedStrokeOnAnotherSlotEarnsForThatSlotOnly() {
        let (_, d) = stroke(slot: 1, seconds: 5)
        XCTAssertEqual(d, [0, BondTuning.points(.stroke), 0])
        let (_, d2) = stroke(slot: 2, seconds: 5)
        XCTAssertEqual(d2, [0, 0, BondTuning.points(.stroke)])
    }

    func testAnAnnoyedStrokeEarnsNothing() {
        for slot in [0, 1] {
            let (_, d) = stroke(slot: slot, seconds: 8, annoyed: true)
            XCTAssertEqual(d, [0, 0, 0], "a grumpy Jelmiko who is stroked slot \(slot)")
        }
    }

    // MARK: (2) a meal and a drink through the real feeding path

    private func eatToTheEnd(_ r: FocusAnyRun, _ what: String) {
        var started = false
        XCTAssertTrue(r.run(60) { if r.care.trayOut || r.care.meal != nil { started = true }; return started && !r.care.trayOut && r.care.meal == nil }, "\(what): the meal ran to its end")
    }

    func testAMealIsCountedOncePerServingAndTheFavouriteGivesTheBonus() {
        let r = focusRun(), care = r.care
        care.store.grant("berries", 30)
        care.needs(for: 0).set(.hunger, 0.1)
        care.feed("berries", jelly: 0)
        eatToTheEnd(r, "plain")
        XCTAssertEqual(all(care), [BondTuning.points(.meal), 0, 0], "one serving, three bites: counted once, for slot 0 only")
        // his favourite: the bonus
        JellyTraitsBook.adopt(char(care, 0), JellyTraits(personality: .brave, jars: [50, 50, 50, 50, 50], snack: "berries"), care.bondDefaults)
        care.needs(for: 0).set(.hunger, 0.1)
        care.feed("berries", jelly: 0)
        eatToTheEnd(r, "favourite")
        XCTAssertEqual(today(care, 0, .meal), BondTuning.points(.meal) + BondTuning.points(.meal, favourite: true), "3 + 5 = 8, inside the meal cap of 9")
        // a third and the cap: 8 + 3 would be 11, cut at 9; then nothing
        care.needs(for: 0).set(.hunger, 0.1); care.feed("berries", jelly: 0); eatToTheEnd(r, "third")
        XCTAssertEqual(today(care, 0, .meal), BondTuning.dayCap(.meal))
        care.needs(for: 0).set(.hunger, 0.1); care.feed("berries", jelly: 0); eatToTheEnd(r, "fourth")
        XCTAssertEqual(today(care, 0, .meal), BondTuning.dayCap(.meal), "the cap holds")
        XCTAssertEqual(pts(care, 1), 0); XCTAssertEqual(pts(care, 2), 0)
    }

    func testADrinkIsCountedAsADrinkOnceAndTheCapHolds() {
        let r = focusRun(), care = r.care
        for _ in 0..<5 {
            care.needs(for: 0).set(.thirst, 0.1)
            care.drink("water", jelly: 0)
            eatToTheEnd(r, "drink")
        }
        XCTAssertEqual(today(care, 0, .drink), BondTuning.dayCap(.drink), "one point per drink, capped at 3 a day: 5 drinks give 3")
        XCTAssertEqual(today(care, 0, .meal), 0)
        XCTAssertEqual(pts(care, 1) + pts(care, 2), 0)
    }

    /// A group serving pays each diner through the same `ate` (GameCare+Group `pay`): once per serving per diner, each for his own slot.
    func testAGroupServingCountsEachDinerOnceThroughTheSharedAtePath() {
        let r = focusRun(), care = r.care
        care.servingCharged = false
        for slot in 0..<3 { for _ in 0..<DiningTiming.bitesPerServing { care.ate(jelly: slot, Consumables.berries, pieces: 1) } }
        XCTAssertEqual(all(care), Array(repeating: BondTuning.points(.meal), count: 3))
        care.servingCharged = false          // the next serving
        for slot in 0..<3 { care.ate(jelly: slot, Consumables.water, pieces: 1) }
        XCTAssertEqual(all(care), Array(repeating: BondTuning.points(.meal) + BondTuning.points(.drink), count: 3))
    }

    // MARK: (3) a finished bath and a groom

    func testAFinishedBathEarnsForTheWashedJelmikoOnly() {
        let r = focusRun(), care = r.care
        care.jelly(2)!.grime.dirt = 0.6
        for _ in 0..<30 { r.tick() }
        care.clean(jelly: 2)
        XCTAssertTrue(care.bath.active)
        var t: Float = 0
        for _ in 0..<(60 * 240) {
            if care.bath.acceptsTouch {
                let c = r.actors[2].sim.centroid()
                let az = sinf(t * 3.1) * 1.3, polar = 1.5 + 0.9 * sinf(t * 1.3)
                let l = SIMD3(sinf(polar) * sinf(az), cosf(polar), sinf(polar) * cosf(az)) * 0.62
                care.bath.touch(contact: true, hitLocal: l, world: c + l, speed: 2.5, dt: r.actors[2].sim.stepDt)
            }
            r.tick(); t += 1 / 60
            if t > 3, !care.bath.active { break }
            if care.bath.stageComplete { care.nextCleanStep() }
            if care.bath.phase == .finish, care.bath.wipe == 0 { care.finishClean(jelly: 2) }
        }
        XCTAssertFalse(care.bath.active)
        XCTAssertEqual(all(care), [0, 0, BondTuning.points(.care)], "the washed Jelmiko only, once")
        care.bondEarn(.care, slot: 2); care.bondEarn(.care, slot: 2); care.bondEarn(.care, slot: 2)
        XCTAssertEqual(today(care, 2, .care), BondTuning.dayCap(.care), "the cap holds")
    }

    func testACancelledBathEarnsNothing() {
        let r = focusRun(), care = r.care
        care.jelly(1)!.grime.dirt = 0.6
        for _ in 0..<30 { r.tick() }
        care.clean(jelly: 1)
        for _ in 0..<120 { r.tick() }
        care.cancelClean(jelly: 1)
        for _ in 0..<300 { r.tick() }
        XCTAssertEqual(all(care), [0, 0, 0])
    }

    private func room(_ n: Int) -> Room {
        let r = Room(count: n); r.withPark = true; Self.keep.append(r)
        for a in r.actors { a.brain?.sleepEnabled = true; a.brain?.seed = 5 &+ UInt64(a.id) }
        reset(r.care)
        return r
    }
    private func step(_ r: Room, _ n: Int = 1) {
        for _ in 0..<n {
            for a in r.actors { a.brain.map { $0.idleNight = DayClock.shared.nightFactor; $0.idleMorning = DayClock.shared.morningFactor; $0.idleDeepNight = DayClock.shared.deepNightFactor } }
            r.step(); r.care.tickCafe(r.actors, dt: 1 / 60); r.care.tickGroom(r.actors, dt: 1 / 60)
        }
    }
    private func run(_ r: Room, _ s: Float, until: (() -> Bool)? = nil) { for _ in 0..<Int(s * 60) { step(r); if until?() == true { break } } }

    func testAGroomEarnsForEachJelmikoWhoGoes() {
        let r = room(3), c = r.care
        c.groomBook.fixedDt = 1 / 60
        c.bath.wallet.add(200 - c.bath.wallet.count, silent: true)
        XCTAssertNil(c.groomBlocker())
        c.groom.openPicker(all: [0, 1]); c.groom.picked = [0, 1]
        c.startGroom(.quick)
        run(r, 90) { c.groom.inScene && self.all(c).reduce(0, +) > 0 }
        XCTAssertEqual(all(c), [BondTuning.points(.care), BondTuning.points(.care), 0], "slots 0 and 1 went to the Spa, slot 2 stayed home")
    }

    // MARK: (4) toys the player starts

    func testABallAndAWandPlayEarnForTheAwakeJelmikoAndTheCapHolds() {
        let r = focusRun(), care = r.care
        r.run(1)
        care.tickPlay(r.actors, dt: 1 / 60)          // (the stage hands the actors to the play code every step)
        care.beginPlay(ball: .ball)
        XCTAssertTrue(care.play.active, "the ball came out")
        XCTAssertEqual(all(care), Array(repeating: BondTuning.points(.toy), count: 3), "every awake Jelmiko, once")
        care.endPlay()
        care.beginPlay(wand: BubbleWand.shared)
        XCTAssertEqual(all(care), Array(repeating: 2 * BondTuning.points(.toy), count: 3))
        care.endPlay()
        for _ in 0..<5 { care.beginPlay(ball: .ball); care.endPlay() }
        XCTAssertEqual(all(care), Array(repeating: BondTuning.dayCap(.toy), count: 3), "the cap holds")
    }

    // MARK: (5) voice

    private func voiceRun(roll: Double) -> FocusAnyRun {
        let c = HClock(); clock = c
        let training = VoiceTraining(defaults: UserDefaults(suiteName: "BondHookTests.voice")!, persists: false, random: { roll })
        let v = VoiceCoordinator(training: training, input: HNoMic(), now: { c.t })
        let r = FocusAnyRun(voice: v); Self.keep.append(r)
        reset(r.care); fullNeeds(r.care)
        r.run(0.3)
        return r
    }
    private func say(_ r: FocusAnyRun, _ words: String) {
        r.run(0.1); clock.t += 0.1
        XCTAssertTrue(r.care.voice.begin(), "the hold opens")
        for _ in 0..<20 { r.run(0.02); clock.t += 0.02 }
        r.care.voice.hear(words)
        r.run(2)
    }

    func testAVoiceTrickThatSucceedsEarnsOnce() {
        let r = voiceRun(roll: 0)
        say(r, "sit")
        XCTAssertEqual(all(r.care), Array(repeating: BondTuning.points(.trick), count: 3), "a command with no name goes to everyone in the room: each earns once")
        for _ in 0..<8 { say(r, "sit") }
        XCTAssertEqual(today(r.care, 0, .trick), BondTuning.dayCap(.trick), "the cap holds")
    }

    func testAVoiceTrickOnAnotherJelmikoByNameEarnsForThatJelmiko() {
        let r = voiceRun(roll: 0)
        say(r, "Pip sit")
        XCTAssertEqual(all(r.care), [0, BondTuning.points(.trick), 0])
    }

    /// A refused order (a grumpy Jelmiko ignores everything but "come") is a different reaction from `.perform`: nothing counts. (A known trick's reliability roll
    /// cannot fail with the default book, so the refusal is the reachable "did not do it" case; the hook itself is `if case .perform = r`.)
    func testARefusedTrickEarnsNothing() {
        let r = voiceRun(roll: 0.999)
        for j in r.care.jellies { for k in NeedKind.allCases { j.needs.set(k, 0) } }
        r.run(0.5)
        say(r, "sit")
        XCTAssertEqual(all(r.care), [0, 0, 0], "a trick that was refused counts for nothing")
    }

    func testComeHereObeyedEarnsForTheJelmikoCalledAndEveryoneForEveryone() {
        let r = voiceRun(roll: 0)
        say(r, "Pip come here")
        XCTAssertEqual(all(r.care), [0, BondTuning.points(.trick), 0])
        let r2 = voiceRun(roll: 0)
        say(r2, "everyone come here")
        XCTAssertEqual(all(r2.care), Array(repeating: BondTuning.points(.trick), count: 3))
    }

    // MARK: (6) a park visit

    func testAParkVisitEarnsForThoseWhoGoOnly() {
        let r = room(3), c = r.care
        XCTAssertNil(c.parkBlocker())
        c.requestPark(); c.park.picked = [0, 1]
        c.startPark()
        run(r, 60) { c.park.phase == .playing }
        XCTAssertEqual(c.park.phase, .playing)
        XCTAssertEqual(all(c), [BondTuning.points(.park), BondTuning.points(.park), 0])
        c.bondEarn(.park, slot: 0); c.bondEarn(.park, slot: 0)
        XCTAssertEqual(today(c, 0, .park), BondTuning.dayCap(.park), "the cap holds")
    }

    // MARK: (7) race, show, volley results

    private struct SlowRivals: RivalSource { func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64) -> [Rival] { (0..<count).map { Rival(name: "R\($0)", tint: .one, stats: RacerStats(waddle: 0.15, focus: 1)) } } }

    private func raceResult(auto: Float?, slot: Int) -> GameCare {
        let c = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "BondHookTests.race.\(UUID().uuidString)")!); Self.keep.append(c)
        let f = c.race
        f.rivalSource = SlowRivals(); f.cue = { _ in }; f.jingle = { _ in }; f.autoRate = auto; f.onSwap = { _ in }
        let prof = c.jelly(slot)!
        f.stats = prof.stats; f.playerCharacter = prof.character
        f.begin(playerID: slot, name: prof.name, player: RacerStats(waddle: 0.9, focus: 1), playerTint: JellyRoster.tint(prof.character), rivalCount: 2, seed: 5, course: .puddle)
        for _ in 0..<(60 * 150) { _ = f.tick(dt: 1 / 60, bodyFree: { _ in true }, bodyReady: { _ in true }); if f.hasResults { break } }
        XCTAssertTrue(f.hasResults)
        return c
    }
    func testAWonRaceEarnsTheWinBonusForThatJelmikoOnly() {
        let c = raceResult(auto: 6, slot: 1)
        XCTAssertEqual(all(c), [0, BondTuning.points(.race, win: true), 0])
        XCTAssertEqual(BondTuning.points(.race, win: true), 5)
        c.bondEarn(.race, slot: 1)
        XCTAssertEqual(today(c, 1, .race), BondTuning.dayCap(.race), "the cap holds")
    }
    func testAnIdleRaceEarnsNothing() {
        let c = raceResult(auto: nil, slot: 1)
        XCTAssertFalse(c.race.sim?.playerFinished ?? true, "the idle player never crossed the line")
        XCTAssertEqual(all(c), [0, 0, 0])
    }

    func testAShowResultEarnsForTheJelmikoWhoEnteredWithTheWinBonusOnlyForFirst() {
        let c = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "BondHookTests.show.\(UUID().uuidString)")!); Self.keep.append(c)
        let f = c.show
        f.songClock = { _ in nil }; f.audioReady = { _ in true }; f.onSwap = { _ in }; f.auto = true
        f.wallet = DropsWallet(persists: false)
        var p = ShowPlayerInput(name: "Pip")
        for t in WearTag.allCases { p.condition[t] = 0.5 }
        p.glow = 0.8; p.dirt = 0; p.dance = .sway; p.tricks = [.sit: 0.9, .jacks: 0.9, .flip: 0.9]; p.care = 1
        let ch = char(c, 1)
        f.begin(playerID: 1, name: "Pip", character: ch, input: p, rank: .puddle, dayKey: 20261021, bodies: 3, seed: 3)
        for _ in 0..<(60 * 400) { f.tick(dt: 1 / 60); if f.hasResults { break } }
        XCTAssertTrue(f.hasResults)
        let place = f.sim!.playerPlace!
        XCTAssertEqual(all(c), [0, BondTuning.points(.show, win: place == 1), 0], "place \(place)")
        for _ in 0..<60 { f.tick(dt: 1 / 60) }
        XCTAssertEqual(pts(c, 1), BondTuning.points(.show, win: place == 1), "counted once")
    }

    private func volley(win: Bool, played: Bool) -> GameCare {
        let c = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "BondHookTests.volley.\(UUID().uuidString)")!); Self.keep.append(c)
        var s = VolleySim(mode: .match(.shore), mine: [VolleyStats(), VolleyStats()], seed: 1, firstServe: 0)
        if played { for _ in 0..<VolleySim.minInputsToCount { s.setStick(SIMD2(1, 0)); s.setStick(SIMD2(0, 0)) } }          // (fresh pushes of the stick are the inputs)
        let prof = c.jelly(2)!
        c.volley.begin(mode: .match(.shore), playerID: 2, character: prof.character, name: prof.name, sim: s)
        for team in win ? [0, 0, 0] : [1, 1, 1] {
            c.volley.sim?.debugRally(possession: team, touches: 1)
            c.volley.sim?.forcePoint(team: team)
            for _ in 0..<(60 * 5) { c.volley.sim?.tick(dt: 1 / 60); if c.volley.sim?.phase == .over { break } }
        }
        for _ in 0..<(60 * 6) { c.volley.sim?.tick(dt: 1 / 60) }
        XCTAssertEqual(c.volley.sim?.phase, .over)
        c.volley.settle()
        return c
    }
    func testAWonVolleyMatchEarnsTheWinBonus() {
        let c = volley(win: true, played: true)
        XCTAssertEqual(all(c), [0, 0, BondTuning.points(.volley, win: true)])
        c.volley.settle()
        XCTAssertEqual(pts(c, 2), BondTuning.points(.volley, win: true), "settled once")
    }
    func testALostVolleyMatchThatWasPlayedEarnsTheEntryPointsAndAnIdleOneNothing() {
        XCTAssertEqual(all(volley(win: false, played: true)), [0, 0, BondTuning.points(.volley)])
        XCTAssertEqual(all(volley(win: false, played: false)), [0, 0, 0])
    }

    // MARK: (8) the first open of a new day, from both launch paths

    func testTheNewDayOpenFromAColdLaunchAndFromAReturnEachEarnForEveryJelmikoAndShareOneCap() {
        let a = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "BondHookTests.open1.\(UUID().uuidString)")!); Self.keep.append(a)
        a.launched(away: 0)
        XCTAssertEqual(all(a), Array(repeating: BondTuning.points(.dayOpen), count: 3), "cold launch")
        a.returnedActive()
        XCTAssertEqual(all(a), Array(repeating: BondTuning.points(.dayOpen), count: 3), "a return the same day counts nothing more")
        let b = GameCare(jellyCount: 3, persistent: false, defaults: UserDefaults(suiteName: "BondHookTests.open2.\(UUID().uuidString)")!); Self.keep.append(b)
        b.returnedActive()
        XCTAssertEqual(all(b), Array(repeating: BondTuning.points(.dayOpen), count: 3), "back from the background")
        b.launched(away: 0)
        XCTAssertEqual(all(b), Array(repeating: BondTuning.points(.dayOpen), count: 3), "and a cold launch after it counts nothing more")
    }

    // MARK: (9) previews, Jelly Spring showcase creatures and park visitors earn nothing

    func testAPreviewCreatureEarnsNothing() {
        let d = UserDefaults(suiteName: "BondHookTests.preview.\(UUID().uuidString)")!
        let c = GameCare(jellyCount: 1, persistent: false, defaults: d, preview: true); Self.keep.append(c)
        let id = c.jelly(0)!.character
        c.launched(away: 0); c.returnedActive(); c.bondDayOpen()
        c.servingCharged = false; c.ate(jelly: 0, Consumables.berries, pieces: 1)
        c.bondEarn(.stroke, slot: 0); c.bondTouch(slot: 0, seconds: 10); c.bondObeyed([0])
        c.bondEarn(.race, character: id, win: true)
        XCTAssertFalse(hasKey(d, id), "nothing was written for the showcase creature")
        let p = JellyRoster.previewID(species: 1, slot: 0)
        c.bondEarn(.meal, character: p)
        XCTAssertFalse(hasKey(d, p))
    }

    func testAParkVisitorOrAStrangerEarnsNothingAndNoOneElseIsTouched() {
        let r = room(3), c = r.care
        c.requestPark(); c.park.picked = [0]; c.startPark()
        run(r, 60) { c.park.phase == .playing }
        XCTAssertEqual(c.park.phase, .playing)
        let before = all(c)
        let visitorSlot = r.actors.count + 1
        c.servingCharged = false
        c.ate(jelly: visitorSlot, Consumables.berries, pieces: 1)          // a park visitor's slot is past the Jelmiko at home
        c.bondEarn(.toy, slot: visitorSlot); c.bondTouch(slot: visitorSlot, seconds: 10); c.bondObeyed([visitorSlot])
        c.bondEarn(.meal, character: 777)
        XCTAssertEqual(all(c), before)
        XCTAssertFalse(hasKey(c.bondDefaults, 777))
        XCTAssertFalse(hasKey(c.bondDefaults, visitorSlot))
    }
}
