//
//  BehaviourRoundTests.swift
//  The 2026-10-20 behaviour round: the awake Jelly keeps living while the others sleep, no sleep / wake flip-flop, one wake per selection, the whole visible
//  room is used (portrait and landscape), zoomies in the okay mood, a floor under the socials, and the quick FLOP lie-down.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BehaviourRoundTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() {
        RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
    }
    override func tearDown() {
        RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12
        IdleTuning.zoomUrge = 60...120; IdleTuning.zoomUrgeFirst = 30
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// The room as the game runs it: 3 Jellies, antics + sleep on, the roaming polygon for `aspect`, the safety arena on every sim.
    private func roomLab(aspect: Float = 440 / 956, mood: IdleMood = .okay, seed: UInt64 = 101, positions: [SIMD2<Float>] = SocialTests.starts) -> SocialTests.Lab {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        _ = GameCamera.camera(aspect: aspect)
        GameCamera.refreshRoam(aspect: aspect)
        let lab = SocialTests.Lab(positions: positions, quiet: false, seed: seed)
        for (i, r) in lab.rigs.enumerated() {
            r.skinner.autoBlink = false
            let b = r.brain
            b.sleepEnabled = true; b.anticsEnabled = true; b.watching = false
            b.idleMood = mood; b.idleNight = 0; b.idleDeepNight = 0; b.idleMorning = 0
            b.socialBook.cooldown = 6 + Float(i) * 3; b.idleState.cooldown = 8 + Float(i) * 2; b.restTimer = 0.5 + Float(i)
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
        }
        return lab
    }
    private func tick(_ l: SocialTests.Lab) {
        l.tick(watching: false)
        for r in l.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
    }

    // MARK: 1. the awake Jelly keeps roaming while two sleep

    private func awakeWhileOthersSleep(night: Float) -> (path: Float, kinds: Set<IdleKind>, repicks: Int, asleep: Bool, pile: Float) {
        let lab = roomLab(seed: 77)
        for r in lab.rigs { r.brain.idleNight = night }
        for i in 0..<2 { lab.rigs[i].brain.startGoodnight(lab.rigs[i].sim, lab.rigs[i].skinner) }
        let me = lab.rigs[2]
        var path: Float = 0, last = me.brain.position
        var kinds = Set<IdleKind>()
        for f in 0..<(60 * 180) {
            tick(lab)
            if f % 6 == 0 { path += simd_distance(me.brain.position, last); last = me.brain.position }
            if let k = me.brain.idleState.kind, k != .sleep { kinds.insert(k) }
            if me.brain.activity == .walking, me.brain.idleState.kind == nil { kinds.insert(.wander) }
        }
        let mates = lab.rigs[0..<2].map { $0.brain.position }
        let pile = mates.map { simd_distance($0, me.brain.position) }.min() ?? 99
        return (path, kinds, me.brain.stuckRepicks, me.brain.isSleeping, pile)
    }

    func testAwakeJellyKeepsRoamingWhileTwoSleepByDay() {
        let r = awakeWhileOthersSleep(night: 0)
        MotionLog.write("BEHAV awake roam day: path \(r.path), kinds \(r.kinds.map { $0.rawValue }.sorted()), repicks \(r.repicks), asleep \(r.asleep)")
        XCTAssertGreaterThan(r.path, 12, "he walks about")
        XCTAssertGreaterThanOrEqual(r.kinds.count, 4, "and does different things: \(r.kinds)")
        XCTAssertLessThan(r.repicks, 10, "no give-up loop")
        XCTAssertTrue(r.asleep || r.path > 12)
    }

    func testAwakeJellyAtDuskIsEitherAsleepByThePileOrStillRoaming() {
        let r = awakeWhileOthersSleep(night: 0.6)
        MotionLog.write("BEHAV awake roam dusk: path \(r.path), kinds \(r.kinds.map { $0.rawValue }.sorted()), repicks \(r.repicks), asleep \(r.asleep), pile \(r.pile)")
        XCTAssertLessThan(r.repicks, 10, "no give-up loop at the pile")
        XCTAssertTrue(r.asleep ? r.pile < 3.2 : r.path > 12, "asleep beside the pile, or still roaming (path \(r.path), asleep \(r.asleep), pile \(r.pile))")
    }

    // MARK: 5. no flip-flop; one wake per selection; woken before lying down

    func testNoSleepWakeSleepLoopWithin120Seconds() {
        for night: Float in [0.6, 0.0] {
            let lab = roomLab(seed: 41)
            for r in lab.rigs { r.brain.idleNight = night }
            if night == 0 {          // by day: a nap now and then, one starts the pile
                let s = lab.rigs[0]; s.brain.idleForced = true
                XCTAssertTrue(s.brain.idleStart(.sleep, s.sim)); s.brain.sleep.hold = 18
            } else {
                for r in lab.rigs { r.brain.idleState.cooldown = 1 }
            }
            var starts = [[Float]](repeating: [], count: 3), was = [false, false, false]
            var t: Float = 0
            for _ in 0..<(60 * 420) {
                tick(lab); t += 1.0 / 60
                for i in 0..<3 {
                    let s = lab.rigs[i].brain.isSleeping
                    if s && !was[i] { starts[i].append(t) }
                    was[i] = s
                }
            }
            MotionLog.write("BEHAV sleep starts (night \(night)): \(starts.map { $0.map { Int($0) } })")
            for i in 0..<3 {
                for k in 0..<max(0, starts[i].count - 2) {
                    XCTAssertGreaterThan(starts[i][k + 2] - starts[i][k], 120, "night \(night) Jelly \(i): three sleeps within 120 s \(starts[i])")
                }
                for k in 0..<max(0, starts[i].count - 1) {
                    XCTAssertGreaterThan(starts[i][k + 1] - starts[i][k], 60, "night \(night) Jelly \(i): back to bed within a minute of waking \(starts[i])")
                }
            }
            if night > 0 { XCTAssertTrue(starts.contains { !$0.isEmpty }, "some bedtime happened at dusk") }
        }
    }

    func testWokenBeforeLyingDownHeJustStaysUp() {
        let lab = roomLab(seed: 9)
        let r = lab.rigs[1]
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim))
        r.brain.sleep.hold = 100
        var f = 0
        while r.brain.sleep.stage < 1 && f < 60 * 20 { tick(lab); f += 1 }
        XCTAssertLessThanOrEqual(r.brain.sleep.stage, 1)
        r.brain.sleepWake(groggy: true)
        var lay = false
        for _ in 0..<(60 * 6) { tick(lab); if r.brain.sleep.stage >= 2 && r.brain.idleState.kind == .sleep { lay = true } }
        XCTAssertFalse(lay, "woken on the way to bed / in the yawn: he does not lie down anyway")
        XCTAssertNotEqual(r.brain.idleState.kind, .sleep)
        XCTAssertFalse(r.brain.idleState.yielding, "and the yield flag is not left on")
        XCTAssertGreaterThan(r.brain.awakeMin, 30, "he stays up a while")
    }

    func testASelectedSleeperWakesOnceAndStaysAwake() {
        let room = RaceTripTests.Room()
        RaceTripTests.keep.append(room)
        let care = room.care
        for a in room.actors { a.brain!.sleepEnabled = true }
        room.actors[2].brain!.commandedGoodnight = true
        room.run(40, until: { room.actors[2].brain!.isNapping })
        XCTAssertTrue(room.actors[2].brain!.isNapping)
        care.select.doubleTap(2)
        room.run(0.4)
        XCTAssertTrue(room.actors[2].brain!.sleep.wakeAsked || !room.actors[2].brain!.isSleeping, "the pick woke him")
        room.run(10, until: { !room.actors[2].brain!.isSleeping })
        XCTAssertFalse(room.actors[2].brain!.isSleeping)
        XCTAssertTrue(room.actors[2].brain!.selectedNow)
        // the selection stays up; he is put back to sleep (the old code woke him again on every tick)
        let b = room.actors[2].brain!
        b.idleForced = true
        XCTAssertTrue(b.idleStart(.sleep, room.actors[2].sim))
        b.sleep.hold = 100
        var woke = false
        room.run(6)
        for _ in 0..<(60 * 4) { room.step(); if b.sleep.wakeAsked { woke = true } }
        XCTAssertFalse(woke, "one wake per selection (edge-triggered)")
        // and nobody who is picked goes to bed by himself
        b.idleReset(room.actors[2].skinner)
        b.awakeMin = 0; b.sleepTryCool = 0
        b.idleNight = 0.9
        XCTAssertFalse(b.sleepWanted(), "no sleepWanted while selected")
        care.select.cancel()
        room.run(0.2)
        XCTAssertFalse(b.selectedNow)
        care.release()
    }

    // MARK: 3. the whole visible room

    private func coverage(aspect: Float, label: String) {
        let lab = roomLab(aspect: aspect, mood: .happy, seed: 5)
        guard let rf = GameCamera.roamFloor else { return XCTFail("no roaming polygon") }
        let cell: Float = 0.5
        func key(_ x: Float, _ z: Float) -> Int { (Int(floorf(x / cell)) + 100) * 1000 + Int(floorf(z / cell)) + 100 }
        var cells = Set<Int>(), walkable = Set<Int>()
        var z = rf.minZ + cell / 2
        while z < rf.maxZ {
            var x = -rf.halfWidth(at: z) + cell / 2
            while x < rf.halfWidth(at: z) {
                let rv = lab.rigs[0].brain.resolve(SIMD3(x, 0, z), 0.7)
                if rf.contains(SIMD2(x, z)), simd_distance(SIMD2(rv.x, rv.z), SIMD2(x, z)) < 0.2 { walkable.insert(key(x, z)) }
                x += cell
            }
            z += cell
        }
        var maxZs = [Float](repeating: -9, count: 3)
        let frames = 60 * 600
        for f in 0..<frames {
            tick(lab)
            if f % 6 != 0 { continue }
            for (i, r) in lab.rigs.enumerated() {
                let p = r.brain.position
                maxZs[i] = max(maxZs[i], p.y)
                let n = Int(ceilf(GameCamera.bobRadius / cell))
                for dx in -n...n { for dz in -n...n {
                    let q = SIMD2(p.x + Float(dx) * cell, p.y + Float(dz) * cell)
                    if simd_distance(q, p) <= GameCamera.bobRadius { cells.insert(key(q.x, q.y)) }
                } }
            }
        }
        let seen = walkable.intersection(cells)
        let frontMin = rf.minZ + (rf.maxZ - rf.minZ) * 2 / 3
        let front = walkable.filter { Float($0 % 1000 - 100) * cell >= frontMin }
        let frontSeen = front.intersection(cells)
        MotionLog.write("BEHAV coverage \(label): aspect \(aspect) polygon z \(rf.minZ)...\(rf.maxZ) max half width \(rf.hw.max() ?? 0), cells \(seen.count)/\(walkable.count) = \(Float(seen.count) / Float(max(walkable.count, 1))), front third \(frontSeen.count)/\(front.count), max z per Jelly \(maxZs), arena r \(GameCamera.arenaRadius)")
        XCTAssertGreaterThanOrEqual(Float(seen.count) / Float(walkable.count), 0.65, "\(label): most of the visible floor is walked over")
        XCTAssertGreaterThanOrEqual(Float(frontSeen.count) / Float(max(front.count, 1)), 0.5, "\(label): and the front third too")
        for (i, m) in maxZs.enumerated() { XCTAssertGreaterThanOrEqual(m, rf.maxZ - 0.6, "\(label): Jelly \(i) reached the front (\(m) of \(rf.maxZ))") }
        if aspect > 1 { XCTAssertGreaterThan(rf.hw.max() ?? 0, 3.6, "landscape: wider than the old +-3.2 box") }
        else { XCTAssertGreaterThan(rf.maxZ, 3.9, "portrait: the front half of the screen is walkable (old limit 2.8)") }
    }

    func testRoomCoveragePortrait() { coverage(aspect: 440 / 956, label: "portrait") }
    func testRoomCoverageLandscape() { coverage(aspect: 956 / 440, label: "landscape") }

    // MARK: 4. zoomies and runs in the okay mood

    func testZoomiesAndRunsEveryFewMinutesInOkayMood() {
        let lab = roomLab(mood: .okay, seed: 31)
        var perBrain = [Int](repeating: 0, count: 3), prev = [IdleKind?](repeating: nil, count: 3)
        for _ in 0..<(60 * 600) {
            tick(lab)
            for (i, r) in lab.rigs.enumerated() {
                let k = r.brain.idleState.kind
                // a solo run or zoomies starting (not the runs inside a game of tag)
                if (k == .run || k == .zoomies), prev[i] != k, r.brain.social == nil || r.brain.social?.kind == .zoomies { perBrain[i] += 1 }
                prev[i] = k
            }
        }
        MotionLog.write("BEHAV okay mood 10 min: solo runs+zoomies per Jelly \(perBrain), all counts \(lab.rigs.map { $0.brain.idleState.counts.map { "\($0.key.rawValue)=\($0.value)" }.sorted() })")
        XCTAssertGreaterThanOrEqual(perBrain.reduce(0, +), 3, "at least 3 runs or zoomies in 10 sim minutes")
        XCTAssertGreaterThanOrEqual(perBrain.min() ?? 0, 1, "everybody gets some energy")
        XCTAssertLessThanOrEqual(perBrain.max() ?? 0, 12, "but it is not constant (2026-10-20 \"too bland\": more runs, was 7 per 10 min; now at most about one a minute)")
    }

    // MARK: 8. a floor under the socials

    func testSocialRateFloor() {
        let lab = roomLab(mood: .okay, seed: 63)
        for r in lab.rigs { r.brain.watching = true }          // (the player is looking)
        var starts = [Float](), ends = [Float](), t: Float = 0
        var lastSession: SocialSession?
        var concurrent = 0
        var kinds = [SocialKind: Int]()
        for _ in 0..<(60 * 600) {
            tick(lab); t += 1.0 / 60
            let live = Set(lab.rigs.compactMap { $0.brain.social }.map { ObjectIdentifier($0) })
            concurrent = max(concurrent, live.count)
            if let s = lab.rigs.compactMap({ $0.brain.social }).first, s !== lastSession {
                starts.append(t); kinds[s.kind, default: 0] += 1
                if lastSession != nil, ends.count < starts.count - 1 { ends.append(t) }
                lastSession = s
            }
            if lab.rigs.allSatisfy({ $0.brain.social == nil }) { lastSession = nil }
        }
        var maxGap: Float = starts.first ?? 600
        for k in 1..<max(starts.count, 1) { maxGap = max(maxGap, starts[k] - starts[k - 1]) }
        maxGap = max(maxGap, 600 - (starts.last ?? 0))
        MotionLog.write("BEHAV social floor: \(starts.count) sessions in 10 min, longest wait \(maxGap), concurrent max \(concurrent), kinds \(kinds.map { "\($0.key.rawValue)=\($0.value)" }.sorted())")
        XCTAssertGreaterThanOrEqual(starts.count, 9, "at least one social about every minute")
        XCTAssertLessThanOrEqual(starts.count, 45, "but it is not constant")
        XCTAssertLessThan(maxGap, 110, "never a long quiet stretch")
        XCTAssertLessThanOrEqual(concurrent, 1, "socials do not stack")
    }

    // MARK: 2. the flop

    func testLieDownIsAQuickFlopWithASquashOnImpact() {
        let r = MotionRig(game: true)
        SleepBackTests.keep.append(r)
        r.renderSamples = false
        r.skinner.autoBlink = false
        r.sim.teleport(toXZ: SIMD2(0, 0.2))
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        r.brain.seed = 11
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim))
        r.brain.sleep.hold = 30
        var yawnStart: Float?, fallStart: Float?, impact: Float?, settled: Float?
        var minSquash: Float = 9, ks = [Float](), kickAtImpact: Float = 0
        var w = SocialTests.Watch()
        var stage1Start: Float?
        r.run(20, until: { r.brain.sleep.stage >= 3 }) {
            if r.brain.idleState.kind == .sleep {
                if r.brain.sleep.stage == 1, r.brain.sleep.turned, yawnStart == nil { yawnStart = r.t }
                if r.brain.sleep.stage == 1, stage1Start == nil { stage1Start = r.t }
                if r.brain.sleep.stage == 2 {
                    if fallStart == nil { fallStart = r.t }
                    minSquash = min(minSquash, r.sim.attractor.squash)
                    ks.append(r.brain.sleep.k)
                    if impact == nil, r.brain.sleep.impacted { impact = r.t; kickAtImpact = r.brain.jellyKick }
                }
                if r.brain.sleep.stage == 3, settled == nil { settled = r.t }
            }
            w.sample(r)
        }
        XCTAssertNotNil(fallStart); XCTAssertNotNil(impact)
        let yawn = (fallStart ?? 0) - (yawnStart ?? 0)
        let fall = (impact ?? 0) - (fallStart ?? 0)
        MotionLog.write("BEHAV flop: yawn \(yawn) s, fall to impact \(fall) s, min squash \(minSquash), max k \(ks.max() ?? 0), kick at impact \(kickAtImpact)")
        XCTAssertLessThan(fall, 0.6, "from the start of the fall to the impact: a quick flop")
        XCTAssertEqual(yawn, SleepTuning.yawnTime, accuracy: 0.25, "a yawn of about 1.8 s")
        XCTAssertLessThan(minSquash, 0.86, "the squash dips on impact")
        XCTAssertGreaterThan(ks.max() ?? 0, 1.05, "and overshoots the lying pose a little")
        XCTAssertGreaterThan(kickAtImpact, 1.5, "a jelly kick")
        // settled: the attractor is exactly the lying pose, the sim can sleep
        XCTAssertEqual(r.sim.attractor.squash, SleepTuning.lieSquash, accuracy: 0.002)
        r.run(4) { w.sample(r) }
        XCTAssertTrue(r.brain.isNapping)
        XCTAssertTrue(r.sim.isSettled, "the sim sleep still holds")
        w.check("flop")
        // the wake: a quick roll-up, then a short stretch
        r.brain.sleepWake(groggy: false)
        var rollT: Float = 0, stretchT: Float = 0
        r.run(8, until: { r.brain.idleState.kind == nil }) {
            if r.brain.idleState.kind == .sleep { if r.brain.sleep.stage == 4 { rollT = max(rollT, r.brain.sleep.t) } else if r.brain.sleep.stage == 5 { stretchT = max(stretchT, r.brain.sleep.t) } }
            w.sample(r)
        }
        MotionLog.write("BEHAV wake: roll-up \(rollT) s, stretch \(stretchT) s")
        XCTAssertLessThan(rollT, 0.6)
        XCTAssertLessThan(stretchT, 1.9, "the stretch is shorter than the old 2.7 s")
        XCTAssertNil(r.brain.idleState.kind)
        w.check("flop + wake")
    }
}
