//
//  PerkTests.swift
//  Timed perks on a Jelly: each effect, expiry, persistence by absolute time, refresh-not-stack, time away, the race boost (bounded by what training
//  can give, never on a rival), the focus snack's wider tap window, and the condition stats foods nudge.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PerkTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    final class Clock { var t = Date(timeIntervalSince1970: 1_800_000_000); func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) } }

    private func perks(_ clock: Clock, defaults: UserDefaults? = nil, key: String = "PerkTests.k") -> JellyPerks {
        let p = JellyPerks(persists: defaults != nil, defaults: defaults ?? .standard, key: key, now: { clock.t })
        Self.keep.append(p)
        return p
    }
    private func suite(_ n: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "PerkTests.\(n)")!
        d.removePersistentDomain(forName: "PerkTests.\(n)")
        return d
    }

    // MARK: expiry, refresh, persistence

    func testPerkRunsForItsDurationThenEnds() {
        let c = Clock(), p = perks(c)
        p.grant(.cozy)
        XCTAssertTrue(p.isActive(.cozy))
        XCTAssertEqual(p.remaining(.cozy), PerkKind.cozy.duration, accuracy: 1)
        c.advance(PerkKind.cozy.duration - 60)
        XCTAssertTrue(p.isActive(.cozy))
        c.advance(61)
        XCTAssertFalse(p.isActive(.cozy))
        p.prune()
        XCTAssertTrue(p.active.isEmpty)
        XCTAssertEqual(p.cache.drain, [1, 1, 1])
    }

    func testTheSamePerkRefreshesTheDurationAndNeverStacksMagnitude() {
        let c = Clock(), p = perks(c)
        p.grant(.cozy)
        let once = p.needDrain
        c.advance(3600)
        p.grant(.cozy)
        XCTAssertEqual(p.remaining(.cozy), PerkKind.cozy.duration, accuracy: 1, "a fresh full duration, not 4 h + 3 h")
        p.grant(.cozy); p.grant(.cozy)
        XCTAssertEqual(p.needDrain, once, "same magnitude however often it is fed")
        p.grant(.fullBelly)
        XCTAssertEqual(p.needDrain[0], PerkTuning.fullBellyHunger, "the strongest slowing perk wins; they do not multiply (hunger 0.5 not 0.4)")
        XCTAssertEqual(p.needDrain[2], PerkTuning.cozyDrain[2])
    }

    func testPerksPersistByAbsoluteExpiryAcrossRelaunch() {
        let d = suite("persist"), c = Clock()
        let p = perks(c, defaults: d)
        p.grant(.shine); p.grant(.zoomies)
        c.advance(45 * 60)                     // zoomies (30 min) over, shine (12 h) going
        let q = perks(c, defaults: d)          // "relaunch"
        XCTAssertTrue(q.isActive(.shine))
        XCTAssertFalse(q.isActive(.zoomies), "an expired perk does not come back")
        XCTAssertEqual(q.remaining(.shine), PerkKind.shine.duration - 45 * 60, accuracy: 1)
        c.advance(12 * 3600)
        let r = perks(c, defaults: d)
        XCTAssertTrue(r.active.isEmpty)
    }

    // MARK: each effect

    func testEveryPerkEffect() {
        let c = Clock(), p = perks(c)
        // cozy: love / mood fall slower
        p.grant(.cozy)
        XCTAssertEqual(p.cache.drain, PerkTuning.cozyDrain)
        XCTAssertLessThan(p.cache.drain[2], 1)
        p.clear(.cozy)
        // full belly: hunger only
        p.grant(.fullBelly)
        XCTAssertEqual(p.cache.drain, [PerkTuning.fullBellyHunger, 1, 1])
        p.clear(.fullBelly)
        // shine / tidy
        p.grant(.shine); XCTAssertEqual(p.cache.fade, PerkTuning.shineFade); XCTAssertEqual(p.cache.dirt, 1)
        p.grant(.tidy); XCTAssertEqual(p.cache.dirt, PerkTuning.tidyDirt)
        // bedtime: deeper naps
        XCTAssertEqual(p.napDrain, NeedsTuning.napDrain)
        p.grant(.bedtime); XCTAssertEqual(p.napDrain, PerkTuning.bedtimeNapDrain)
        XCTAssertLessThan(PerkTuning.bedtimeNapDrain, NeedsTuning.napDrain)
        // race perks
        XCTAssertTrue(p.raceBoost.isNone)
        p.grant(.zoomies); XCTAssertEqual(p.raceBoost.strideMul, 1 + PerkTuning.raceStride); XCTAssertEqual(p.raceBoost.grace, 0)
        p.grant(.focus); XCTAssertEqual(p.raceBoost.grace, PerkTuning.focusGrace)
        XCTAssertTrue(PerkKind.allCases.allSatisfy { !$0.title.isEmpty && !$0.blurb.isEmpty && !$0.symbol.isEmpty && $0.duration > 0 })
    }

    func testCozyAndFullBellyReallyDrainSlower() {
        var out: [String: [Float]] = [:]
        for (name, drain) in [("plain", [1.0, 1, 1]), ("cozy", PerkTuning.cozyDrain), ("belly", [PerkTuning.fullBellyHunger, 1, 1])] {
            let n = BlobNeeds(persists: false)
            for k in NeedKind.allCases { n.set(k, 1) }
            for _ in 0..<(3 * 3600) { n.step(dt: 1, perkDrain: drain) }
            out[name] = NeedKind.allCases.map { n.level($0) }
        }
        XCTAssertGreaterThan(out["cozy"]![2], out["plain"]![2] + 0.1, "attention holds up longer")
        XCTAssertGreaterThan(out["belly"]![0], out["plain"]![0] + 0.1, "hunger falls slower")
        XCTAssertEqual(out["belly"]![1], out["plain"]![1], accuracy: 1e-4, "thirst is not touched by a full belly")
    }

    func testShineAndTidyReallySlowTheGrime() {
        let c = Clock()
        let plain = BlobGrime(persists: false), shiny = BlobGrime(persists: false), tidy = BlobGrime(persists: false)
        let ps = perks(c), pt = perks(c)
        ps.grant(.shine); pt.grant(.tidy)
        shiny.perks = ps; tidy.perks = pt
        for g in [plain, shiny, tidy] { g.sparkle = 1 }
        for g in [plain, shiny, tidy] { for _ in 0..<(60 * 60) { g.step(dt: 1 / 60, travelled: 0.02) } }
        XCTAssertGreaterThan(shiny.sparkle, plain.sparkle, "the shine fades slower")
        XCTAssertLessThan(tidy.dirt, plain.dirt, "lint comes back slower")
        XCTAssertEqual(tidy.dirt, plain.dirt * PerkTuning.tidyDirt, accuracy: plain.dirt * 0.02)
    }

    // MARK: time away

    func testTimeAwayRespectsPerks() {
        let c = Clock()
        let key = NeedsTuning.defaultsKey + ".perkaway"
        let pk = PerkTuning.key(forNeeds: key)!
        let d = suite("away")
        func run(cozy: Bool) -> [Float] {
            d.removeObject(forKey: key); d.removeObject(forKey: pk)
            let n = BlobNeeds(defaults: d, key: key, now: { c.t }, persists: true)
            for k in NeedKind.allCases { n.set(k, 1) }
            if cozy { let p = JellyPerks(persists: true, defaults: d, key: pk, now: { c.t }); p.grant(.cozy) }
            let t0 = c.t
            n.leaveActive(at: t0)
            n.returnActive(at: t0.addingTimeInterval(3 * 3600))
            return NeedKind.allCases.map { n.level($0) }
        }
        let plain = run(cozy: false), cozy = run(cozy: true)
        XCTAssertLessThan(plain[2], 1)
        XCTAssertGreaterThan(cozy[2], plain[2] + 0.02, "attention fell less while away")
        XCTAssertGreaterThan(cozy[0], plain[0], "hunger too")
        XCTAssertGreaterThanOrEqual(cozy[2], NeedsTuning.awayFloor, "and the floor still holds")
    }

    func testTimeAwayShineAndTidy() {
        let c = Clock(), d = suite("awaygrime")
        let key = GrimeTuning.defaultsKey + ".perkaway", pk = PerkTuning.key(forGrime: key)!
        func run(perk: Bool) -> (Float, Float) {
            d.removeObject(forKey: key); d.removeObject(forKey: pk)
            let g = BlobGrime(persists: true, defaults: d, key: key, now: { c.t })
            g.sparkle = 1; g.save()
            if perk { let p = JellyPerks(persists: true, defaults: d, key: pk, now: { c.t }); p.grant(.shine); p.grant(.tidy) }
            let t0 = c.t
            g.leaveActive(at: t0)
            g.returnActive(at: t0.addingTimeInterval(300))
            return (g.sparkle, g.dirt)
        }
        let a = run(perk: false), b = run(perk: true)
        XCTAssertGreaterThan(b.0, a.0, "the shine lasted longer while away")
        XCTAssertLessThanOrEqual(b.1, a.1, "and the lint grew no faster")
    }

    // MARK: the race

    func testRaceBoostIsModestAndBoundedByTraining() {
        let b = RaceBoost(strideMul: 1 + PerkTuning.raceStride, rateMul: 1 + PerkTuning.raceRate, grace: 0)
        var sawGain = false
        for k in 0...100 {
            let w = Float(k) / 100
            let s = RaceTuning.stride(waddle: w), r = RaceTuning.maxRate(waddle: w)
            let o = b.apply(stride: s, rate: r)
            XCTAssertLessThanOrEqual(o.stride, RaceTuning.stride(waddle: 1) + 1e-6, "never past the stride training can reach (and the feet-attached limit)")
            XCTAssertLessThanOrEqual(o.rate, RaceTuning.maxRate(waddle: 1) + 1e-6)
            XCTAssertLessThanOrEqual(o.stride, s * 1.0401); XCTAssertLessThanOrEqual(o.rate, r * 1.0601)
            XCTAssertGreaterThanOrEqual(o.stride, s); XCTAssertGreaterThanOrEqual(o.rate, r)
            if o.stride > s + 1e-4 { sawGain = true }
            XCTAssertLessThanOrEqual(o.stride * o.rate, RaceTuning.speed(waddle: 1) + 1e-5, "no faster than a fully trained Jelly")
        }
        XCTAssertTrue(sawGain)
        let top = b.apply(stride: RaceTuning.stride(waddle: 1), rate: RaceTuning.maxRate(waddle: 1))
        XCTAssertEqual(top.stride, RaceTuning.stride(waddle: 1), "a fully trained Jelly gains nothing")
        XCTAssertEqual(top.rate, RaceTuning.maxRate(waddle: 1))
        // training still matters: the snack lifts a waddle-0.5 Jelly less than 0.5 of training does
        let mid = b.apply(stride: RaceTuning.stride(waddle: 0.5), rate: RaceTuning.maxRate(waddle: 0.5))
        XCTAssertLessThan(mid.stride * mid.rate, RaceTuning.speed(waddle: 0.8), "a snack is worth less than a lot of training")
        XCTAssertLessThan(mid.stride * mid.rate, 1.12 * RaceTuning.speed(waddle: 0.5))
    }

    func testBoostIsOnTheRaceSimPlayerOnlyNeverOnRivals() {
        let rivals = LocalRivalSource().rivals(count: 2, player: RacerStats(waddle: 0.4, focus: 0.5), playerTint: SIMD3(0.5, 0.6, 0.9), seed: 5)
        let boost = RaceBoost(strideMul: 1.04, rateMul: 1.06, grace: PerkTuning.focusGrace)
        let plain = RaceSim(player: RacerStats(waddle: 0.4, focus: 0.5), playerName: "Bob", rivals: rivals, seed: 5)
        let boosted = RaceSim(player: RacerStats(waddle: 0.4, focus: 0.5), playerName: "Bob", rivals: rivals, seed: 5, playerBoost: boost)
        XCTAssertGreaterThan(boosted.racers[0].stride, plain.racers[0].stride)
        XCTAssertGreaterThan(boosted.racers[0].rate, plain.racers[0].rate)
        XCTAssertEqual(boosted.racers[0].tap.grace, PerkTuning.focusGrace)
        for i in 1..<boosted.racers.count {
            XCTAssertEqual(boosted.racers[i].stride, plain.racers[i].stride, "rival \(i) is unboosted")
            XCTAssertEqual(boosted.racers[i].rate, plain.racers[i].rate)
            XCTAssertTrue(boosted.racers[i].boost.isNone)
            XCTAssertEqual(boosted.racers[i].tap.grace, 0)
        }
    }

    func testRacePerksAreUsedUpByTheNextRace() {
        let c = Clock(), p = perks(c)
        p.grant(.zoomies); p.grant(.focus); p.grant(.cozy)
        let b = p.consumeRaceBoost()
        XCTAssertFalse(b.isNone)
        XCTAssertTrue(p.consumeRaceBoost().isNone, "one race only")
        XCTAssertFalse(p.isActive(.zoomies)); XCTAssertFalse(p.isActive(.focus))
        XCTAssertTrue(p.isActive(.cozy), "the other perks stay")
        // within 30 minutes: after that the sugar rush has worn off
        p.grant(.zoomies)
        c.advance(31 * 60)
        XCTAssertTrue(p.raceBoost.isNone)
    }

    func testBoostedRaceIsFasterPerStepAndGraceForgivesABounce() {
        var plain = RaceTapModel(), forgiving = RaceTapModel()
        forgiving.grace = PerkTuning.focusGrace
        XCTAssertEqual(plain.tap(0), .queued); XCTAssertEqual(forgiving.tap(0), .queued)
        plain.tick(dt: 0.1); forgiving.tick(dt: 0.1)
        XCTAssertEqual(plain.tap(0), .stumble, "no grace: the same foot twice is a stumble")
        XCTAssertEqual(forgiving.tap(0), .ignored, "inside the window a bounce is forgiven")
        XCTAssertEqual(forgiving.stumbles, 0)
        forgiving.tick(dt: 0.5)
        XCTAssertEqual(forgiving.tap(0), .stumble, "a real repeat still stumbles")
    }

    // MARK: eating, conditions, behaviour

    func testEatingAStoreFoodUsesOneServingStartsThePerkAndNudgesCondition() {
        let care = GameCare(jellyCount: 1, persistent: false)
        let prof = care.jelly(0)!
        prof.perks.clear(.fullBelly)
        care.store.grant("nuggets", 2)
        let before = prof.stats.condition(.sporty)
        care.servingCharged = false
        care.ate(jelly: 0, Consumables.nuggets, pieces: 1)
        XCTAssertEqual(care.store.count("nuggets"), 1, "one serving used on the first bite")
        care.ate(jelly: 0, Consumables.nuggets, pieces: 2)
        XCTAssertEqual(care.store.count("nuggets"), 1, "the same serving is not charged twice")
        XCTAssertTrue(prof.perks.isActive(.fullBelly))
        XCTAssertGreaterThan(prof.stats.condition(.sporty), before)
        prof.perks.clear(.fullBelly)
    }

    func testRefusedFoodCostsNothing() {
        let care = GameCare(jellyCount: 1, persistent: false)
        care.store.grant("fries", 1)
        care.ate(jelly: 0, Consumables.fries, pieces: 0)
        XCTAssertEqual(care.store.count("fries"), 1)
        XCTAssertFalse(care.jelly(0)!.perks.isActive(.bouncy))
    }

    func testSugarRushOwesZoomiesAndFreeFoodsDoNothing() {
        let care = GameCare(jellyCount: 1, persistent: false)
        care.store.grant("donut", 1)
        care.ate(jelly: 0, Consumables.donut, pieces: 3)
        XCTAssertTrue(care.zoomiesDue.contains(0))
        XCTAssertTrue(care.jelly(0)!.perks.isActive(.zoomies))
        care.jelly(0)!.perks.clear(.zoomies)
        care.zoomiesDue = []
        care.ate(jelly: 0, Consumables.berries, pieces: 3)
        care.ate(jelly: 0, Consumables.pizza, pieces: 3)
        XCTAssertTrue(care.zoomiesDue.isEmpty)
    }

    func testConditionRisesCapsAndDecaysSlowly() {
        let c = Clock()
        let s = JellyStats(persists: false, now: { c.t })
        XCTAssertEqual(s.condition(.cute), 0)
        s.nudge([.cute: 0.4, .cool: 0.2])
        XCTAssertEqual(s.condition(.cute), 0.4, accuracy: 1e-5)
        for _ in 0..<10 { s.nudge([.cute: 0.4]) }
        XCTAssertEqual(s.condition(.cute), 1, "capped")
        c.advance(10 * 3600)
        XCTAssertEqual(s.condition(.cute), 1 - 10 * ConditionTuning.decayPerHour, accuracy: 1e-4, "slow decay")
        XCTAssertEqual(s.condition(.cool), 0.2 - 10 * ConditionTuning.decayPerHour, accuracy: 1e-4)
        c.advance(1000 * 3600)
        XCTAssertEqual(s.condition(.cool), 0, "never below zero")
        XCTAssertEqual(ConditionKey.allCases.count, 5)
    }

    func testConditionPersists() {
        let d = suite("cond"), c = Clock()
        let a = JellyStats(persists: true, defaults: d, key: "PerkTests.stats", now: { c.t })
        a.nudge([.sparkle: 0.5])
        c.advance(3600)
        let b = JellyStats(persists: true, defaults: d, key: "PerkTests.stats", now: { c.t })
        XCTAssertEqual(b.condition(.sparkle), 0.5 - ConditionTuning.decayPerHour, accuracy: 1e-4)
    }

    func testEveryFoodHasAPerkAndAConditionNudge() {
        for f in Consumables.storeFoods {
            XCTAssertNotNil(f.perk, f.id)
            XCTAssertFalse(f.condition.isEmpty, f.id)
            XCTAssertTrue(f.condition.values.allSatisfy { $0 > 0 && $0 <= 0.2 }, f.id)
        }
        // bouncy and social tilt the idle pick toward the antics / play
        let base = IdleTable.weights(.happy, night: 0, morning: 0, antics: true)
        let boosted = IdleTable.weights(.happy, night: 0, morning: 0, antics: true, anticMul: PerkTuning.anticBoost)
        func w(_ l: [(kind: IdleKind, weight: Float)], _ k: IdleKind) -> Float { l.first { $0.kind == k }?.weight ?? 0 }
        XCTAssertGreaterThan(w(boosted, .bounce), w(base, .bounce) * 2)
        XCTAssertEqual(w(boosted, .run), w(base, .run), "the old moves are not touched")
    }

    func testPerkFlagsReachTheBrain() {
        let care = GameCare(jellyCount: 1, persistent: false)
        let rig = MotionRig(game: true)
        Self.keep.append(rig)
        let p = care.jelly(0)!.perks
        p.grant(.bouncy); p.grant(.social); p.grant(.bedtime)
        care.syncPerks(id: 0, brain: rig.brain)
        XCTAssertEqual(rig.brain.perkFlags, PerkFlags(bouncy: true, social: true, bedtime: true))
        XCTAssertLessThan(rig.brain.idleLively, 0.75)
        for k in [PerkKind.bouncy, .social, .bedtime] { p.clear(k) }
        care.syncPerks(id: 0, brain: rig.brain)
        XCTAssertEqual(rig.brain.perkFlags, PerkFlags())
    }
}
