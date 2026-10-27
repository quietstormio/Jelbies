//
//  AnticsTests.swift
//  The new solo antics (BlobBrain+Antics.swift) and social kinds (BlobSocial+Play.swift): each one runs to its end with the feet attached and the arms
//  stubby in EVERY frame (the all-moves invariants), no behaviour comes round twice in a row, nobody repeats what another is doing right now, at most
//  two Jellies are in fast moves at once, and napping Jellies are no social partners.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class AnticsTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    // MARK: solo antics

    func testEverySoloAnticRunsToItsEndWithFeetAttachedAndArmsStubby() {
        let kinds: [IdleKind] = [.tail, .flop, .window, .peek, .stretch, .bounce, .roll, .sway]
        for kind in kinds {
            let r = MotionRig(game: true)
            Self.keep.append(r)
            r.renderSamples = false
            r.skinner.autoBlink = false
            r.brain.seed = 11
            r.brain.anticsEnabled = true
            r.brain.idleForced = true
            // far from the sofa end for the peek, mid-rug for the rest
            r.sim.teleport(toXZ: SIMD2(0.4, 0.4))
            for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim)
            XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(kind) starts")
            var w = SocialTests.Watch()
            var frames = 0
            r.run(40, until: { r.brain.idleState.kind == nil && r.t > 0.6 }) { w.sample(r); frames += 1 }
            MotionLog.write("ANTIC \(kind): ran \(Float(frames) / 60) s")
            XCTAssertNil(r.brain.idleState.kind, "\(kind) ends by itself (took \(Float(frames) / 60) s)")
            XCTAssertGreaterThan(frames, 60, "\(kind) takes a moment")
            w.check("antic \(kind)", plainBound: 0.03)
            // and he is standing, settled, afterwards
            r.run(2) { }
            XCTAssertLessThan(r.sim.bodyPose(iterations: 6).tilt, 0.45, "\(kind): upright afterwards")
        }
    }

    func testSwayNeedsTheMusicAndOnlyThenIsInTheTable() {
        let off = IdleTable.weights(.happy, night: 0, morning: 0, sleep: false, antics: true, music: false).map(\.kind)
        let on = IdleTable.weights(.happy, night: 0, morning: 0, sleep: false, antics: true, music: true).map(\.kind)
        XCTAssertFalse(off.contains(.sway)); XCTAssertTrue(on.contains(.sway))
        // and with antics off the table is exactly the old one
        let a = IdleTable.weights(.happy, night: 0, morning: 0, sleep: false, antics: false, music: true), b = IdleTable.weights(.happy)
        XCTAssertEqual(a.map(\.kind), b.map(\.kind)); XCTAssertEqual(a.map(\.weight), b.map(\.weight))
        for m in [BlobMood.happy, .okay, .grumpy] {
            let kinds = Set(IdleTable.weights(m, night: 0, morning: 0, sleep: false, antics: true, music: true).map(\.kind))
            XCTAssertGreaterThan(kinds.count, IdleTable.set(m).count + (m == .grumpy ? 1 : 3), "\(m): many more behaviours")
        }
    }

    // MARK: variety, no back-to-back repeats

    func testPicksNeverRepeatAndRunThroughManyKinds() {
        var rng = SystemRandomNumberGenerator()
        for m in [BlobMood.happy, .okay] {
            var last: IdleKind?, seen = Set<IdleKind>(), repeats = 0
            var cooling = Set<IdleKind>()
            for i in 0..<3000 {
                let k = IdleTable.pick(m, last: last, r: Float.random(in: 0..<1, using: &rng), antics: true, music: true, cooling: cooling)
                if k != .wander { if k == last { repeats += 1 }; seen.insert(k); last = k; cooling.insert(k); if cooling.count > 3 { cooling.removeFirst() } }
                _ = i
            }
            XCTAssertEqual(repeats, 0, "\(m): never the same special twice in a row")
            XCTAssertGreaterThanOrEqual(seen.count, m == .happy ? 14 : 11, "\(m): variety \(seen.map(\.rawValue).sorted())")
        }
    }

    func testThreeJelliesNeverRepeatTheirLastBehaviourAndRarelyDoTheSameThingAtOnce() {
        let lab = SocialTests.Lab(quiet: false, seed: 77)
        for (i, r) in lab.rigs.enumerated() {
            r.brain.idleMood = .happy; AnticsLabTests.lively(r.brain); r.brain.sleepEnabled = false
            r.brain.socialBook.cooldown = 8; r.brain.idleState.cooldown = 3; r.brain.restTimer = 0.5 + Float(i)
        }
        var seq: [[IdleKind]] = [[], [], []], prev = [IdleKind?](repeating: nil, count: 3)
        var same = 0, both = 0
        var sameTags: [String: Int] = [:]
        for _ in 0..<(60 * 300) {
            lab.tick(watching: false)
            for (i, r) in lab.rigs.enumerated() {
                let k = (r.brain.social == nil && r.brain.idleState.reaction == nil && r.brain.idleState.resume == nil) ? r.brain.idleState.kind : nil          // (the moves a social session starts - the chase's runs, the dance - and the reactions / mid-walk flourishes of 2026-10-20 are not his own picks)
                if let k, k != prev[i] { seq[i].append(k) }
                prev[i] = k
            }
            // (the `join` reaction is the one deliberate same-moment move: he runs ALONG with a friend's zoomies, like the social zoomies session that is exempt as a social; every other
            // reaction, flourish and pick waits while a friend is in the same move - `othersDoing` - so those are counted)
            let free = lab.rigs.filter { $0.brain.social == nil && $0.brain.idleState.kind != nil && $0.brain.idleState.kind != .look && $0.brain.idleState.reaction != .join }
            let ks = free.compactMap { $0.brain.idleState.kind }
            if ks.count >= 2 {
                both += 1
                if Set(ks).count < ks.count {
                    same += 1
                    // who did what (a reaction, a mid-walk flourish or his own pick) in the colliding frames
                    let tag = free.map { r in "\(r.brain.idleState.kind!.rawValue)\(r.brain.idleState.reaction.map { "<\($0.rawValue)" } ?? (r.brain.idleState.resume != nil ? "<walk" : ""))" }.sorted().joined(separator: "+")
                    sameTags[tag, default: 0] += 1
                }
            }
        }
        MotionLog.write("ANTICS same-time tags: \(sameTags.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        for i in 0..<3 {
            var dup = 0
            for j in 1..<max(seq[i].count, 1) where seq[i][j] == seq[i][j - 1] && seq[i][j] != .stumble { dup += 1 }
            MotionLog.write("ANTICS rig\(i) sequence: \(seq[i].map(\.rawValue).joined(separator: " "))")
            XCTAssertEqual(dup, 0, "rig \(i): no behaviour twice in a row")
            XCTAssertGreaterThanOrEqual(Set(seq[i]).count, 7, "rig \(i): a good mix \(Set(seq[i]).map(\.rawValue).sorted())")
        }
        MotionLog.write("ANTICS same-time repeats \(same) of \(both) frames with two or more behaviours on")
        XCTAssertEqual(same, 0, "two Jellies never do the same behaviour at the same moment")
    }

    func testAtMostTwoJelliesInFastMovesAtOnce() {
        let lab = SocialTests.Lab(quiet: false, seed: 5)
        for (i, r) in lab.rigs.enumerated() {
            r.brain.idleMood = .happy; AnticsLabTests.lively(r.brain)
            r.brain.socialBook.cooldown = 4; r.brain.idleState.cooldown = 2; r.brain.restTimer = 0.4 + 0.3 * Float(i)
        }
        var worst = 0, over = 0, twoFrames = 0
        for _ in 0..<(60 * 400) {
            lab.tick(watching: false)
            let n = lab.rigs.filter { $0.brain.isFastMove }.count
            worst = max(worst, n); if n > 2 { over += 1 }; if n == 2 { twoFrames += 1 }
        }
        MotionLog.write("ANTICS fast cap: worst \(worst), frames over 2: \(over), frames with exactly 2: \(twoFrames)")
        XCTAssertLessThan(Float(over) / Float(60 * 400), 0.005, "at most two Jellies in fast moves at once (a social's own one-hop beats are the only exceptions)")
        XCTAssertGreaterThan(twoFrames, 60, "two do go at once (the cap is not just silence)")
    }

    func testFastStartsAreRefusedWhenTwoOthersAreInFastMoves() {
        let lab = SocialTests.Lab(quiet: true, seed: 9)
        for r in lab.rigs { AnticsLabTests.lively(r.brain); r.brain.sleepEnabled = false; r.brain.idleForced = true }
        XCTAssertTrue(lab.rigs[0].brain.idleStart(.jacks, lab.rigs[0].sim))
        XCTAssertTrue(lab.rigs[1].brain.idleStart(.jacks, lab.rigs[1].sim))
        let c = lab.rigs[2].brain
        XCTAssertEqual(c.fastOthers(), 2)
        // the scheduler's own check
        c.idleMood = .happy; c.runMoveDemo = nil; c.idleState.cooldown = 0
        var started = 0
        for _ in 0..<30 { c.idleState.cooldown = 0; if c.idleMaybeStart(lab.rigs[2].sim), let k = c.idleState.kind, BlobBrain.fastKinds.contains(k) { started += 1; c.abortAll(lab.rigs[2].sim, lab.rigs[2].skinner) } }
        XCTAssertEqual(started, 0, "no fast move while two others are in one")
        for kind in [SocialKind.chase, .dance, .keepAway] {
            XCTAssertFalse(c.socialStart(kind, with: lab.rigs[0].brain, lab.rigs[2].sim), "\(kind): not while the other two are fast")
        }
    }

    // MARK: the social kinds, deterministically

    private func runKind(_ kind: SocialKind, maxSeconds: Float = 60, seed: UInt64 = 31) -> (lab: SocialTests.Lab, seconds: Float, ok: Bool) {
        let lab = SocialTests.Lab(seed: seed)
        for r in lab.rigs { r.brain.anticsEnabled = true }
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(kind, with: b.brain, a.sim), "\(kind): starts")
        XCTAssertEqual(a.brain.socialKind, kind)
        var f = 0
        while f < Int(maxSeconds * 60) {
            lab.tick(); f += 1
            if !lab.anySocial && f > 10 { break }
        }
        let ok = !lab.anySocial
        MotionLog.write(String(format: "ANTICS SOCIAL %@ completed=%d in %.1f s, events %@", kind.rawValue, ok ? 1 : 0, Float(f) / 60, "\(lab.events.map(\.count))"))
        return (lab, Float(f) / 60, ok)
    }

    func testEveryNewSocialKindCompletesWithFeetAttachedAndArmsStubby() {
        for kind in [SocialKind.chase, .bump, .nuzzle, .sitTogether, .dance, .sneak, .keepAway, .line, .swayHug, .danceOff, .whisperGiggle] {
            let (lab, secs, ok) = runKind(kind)
            XCTAssertTrue(ok, "\(kind): completes (took \(secs) s)")
            XCTAssertGreaterThan(secs, 2, "\(kind) takes a while")
            XCTAssertGreaterThan(lab.events[0].count + lab.events[1].count, 1, "\(kind): events fired")
            XCTAssertEqual(lab.rigs[0].brain.socialStarts[kind], 1)
            for r in lab.rigs { XCTAssertNil(r.brain.social); XCTAssertEqual(r.brain.socialBook.pitch, 0, accuracy: 0.05); XCTAssertEqual(r.brain.socialBook.squash, 1, accuracy: 0.05) }
            lab.checkAll("social \(kind)", plainBound: 0.03)
        }
    }

    func testChaseSwapsRolesAndTagsEachRound() {
        let (lab, _, ok) = runKind(.chase)
        XCTAssertTrue(ok)
        let boops = lab.events[0].filter { if case .boop = $0 { return true }; return false }.count
        XCTAssertEqual(boops, SocialTuning.chaseRounds, "a tag per round, the roles swap each time")
    }

    func testBellyBumpBouncesTwiceAndNobodyOverlaps() {
        let (lab, _, ok) = runKind(.bump)
        XCTAssertTrue(ok)
        let boops = lab.events[0].filter { if case .boop = $0 { return true }; return false }.count
        XCTAssertEqual(boops, 2, "two bumps")
        XCTAssertGreaterThan(lab.minPair, 0.5)
    }

    func testSneakStartlesTheOtherWithAHop() {
        let lab = SocialTests.Lab(seed: 3)
        for r in lab.rigs { r.brain.anticsEnabled = true }
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.sneak, with: b.brain, a.sim))
        var hopped = false
        for _ in 0..<(60 * 40) {
            lab.tick()
            if case .hopPlay = b.brain.script { hopped = true }
            if !lab.anySocial { break }
        }
        XCTAssertTrue(hopped, "he is startled: a hop")
        XCTAssertFalse(lab.anySocial)
    }

    func testLineOfThreeFollowsTheLeader() {
        let lab = SocialTests.Lab(seed: 12)
        for r in lab.rigs { r.brain.anticsEnabled = true }
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.line, with: b.brain, a.sim))
        XCTAssertTrue(lab.rigs.allSatisfy { $0.brain.isSocial }, "all three in it")
        var moved: Float = 0
        let p0 = b.brain.position
        for _ in 0..<(60 * 30) { lab.tick(); moved = max(moved, simd_distance(b.brain.position, p0)); if !lab.anySocial { break } }
        XCTAssertGreaterThan(moved, 1.5, "the leader leads")
        XCTAssertFalse(lab.anySocial)
    }

    func testNoSocialPicksWithNappingJellies() {
        let lab = SocialTests.Lab(positions: [SIMD2(-1.0, 0.6), SIMD2(0.7, 0.9), SIMD2(1.6, -1.2)], quiet: false, seed: 14)
        SocialTuning.pickChance = 1
        for (i, r) in lab.rigs.enumerated() { AnticsLabTests.lively(r.brain); r.brain.idleMood = .happy; r.brain.socialBook.cooldown = 0; r.brain.restTimer = 0.2 + 0.2 * Float(i) }
        let sleeper = lab.rigs[2]
        sleeper.brain.idleForced = true
        XCTAssertTrue(sleeper.brain.idleStart(.sleep, sleeper.sim)); sleeper.brain.sleep.hold = 500
        var withSleeper = 0
        for _ in 0..<(60 * 120) {
            lab.tick(watching: false)
            if sleeper.brain.idleState.kind == .sleep {
                for r in lab.rigs where r.brain.isSocial { if r.brain.socialPartnerID == 2 || r.brain === sleeper.brain { withSleeper += 1 } }
            }
        }
        XCTAssertEqual(withSleeper, 0, "nobody socialises with the sleeper (and he with nobody)")
        XCTAssertGreaterThan(lab.rigs[0].brain.socialStarts.values.reduce(0, +) + lab.rigs[1].brain.socialStarts.values.reduce(0, +), 2, "the other two still do (pickChance 1)")
    }
}
