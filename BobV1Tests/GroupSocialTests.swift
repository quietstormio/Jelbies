//
//  GroupSocialTests.swift
//  The group socials (BlobSocial+Group.swift): hug, cheer, conga and circle dance with 3 Jelbies (the room) and 5 (the Park). Every frame of every run: feet attached, arms stubby
//  (the all-moves invariants through SocialTests.Watch); nobody busy is pulled in; they end by themselves, apart again; the autonomous roll makes a group hug within minutes.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class GroupSocialTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() { RoomLayout.dynamicBoxes = []; SocialTuning.pickChance = 0.12; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    static let five: [SIMD2<Float>] = [SIMD2(-1.6, 0.5), SIMD2(1.2, 0.6), SIMD2(0.0, 2.3), SIMD2(-1.2, 2.0), SIMD2(1.6, 2.2)]

    private func run(_ kind: SocialKind, n: Int, seed: UInt64 = 31, maxSeconds: Float = 60, reduce: Bool = false) -> (lab: SocialTests.Lab, seconds: Float, ok: Bool, minGap: Float) {
        let lab = SocialTests.Lab(n: n, positions: n == 3 ? SocialTests.starts : Self.five, seed: seed)
        for r in lab.rigs { r.brain.anticsEnabled = true; if reduce { r.brain.amplitude = 0.5 } }
        XCTAssertTrue(lab.rigs[0].brain.socialStart(kind, with: lab.rigs[1].brain, lab.rigs[0].sim), "\(kind) x\(n): starts")
        for r in lab.rigs { XCTAssertEqual(r.brain.isSocial, true, "\(kind) x\(n): everybody is pulled in") }
        var f = 0, minGap: Float = 9
        while f < Int(maxSeconds * 60) {
            lab.tick(); f += 1
            for i in 0..<n { for j in (i + 1)..<n { minGap = min(minGap, lab.centreGap(i, j)) } }
            if !lab.anySocial && f > 10 { break }
        }
        let ok = !lab.anySocial
        MotionLog.write(String(format: "GROUP %@ x%d reduce %d completed=%d in %.1f s, min centre gap %.2f, events %@", kind.rawValue, n, reduce ? 1 : 0, ok ? 1 : 0, Float(f) / 60, minGap, "\(lab.events.map(\.count))"))
        return (lab, Float(f) / 60, ok, minGap)
    }

    func testEveryGroupKindCompletesWithFeetAttachedAndArmsStubby() {
        for (n, kinds) in [(3, [SocialKind.groupHug, .groupCheer, .conga, .circleDance]), (5, [.groupHug, .circleDance])] {
            for kind in kinds {
                let (lab, secs, ok, _) = run(kind, n: n)
                XCTAssertTrue(ok, "\(kind) x\(n): completes (took \(secs) s)")
                XCTAssertGreaterThan(secs, 4, "\(kind) takes a while")
                for r in lab.rigs { XCTAssertNil(r.brain.social); XCTAssertEqual(r.brain.socialBook.pitch, 0, accuracy: 0.05); XCTAssertEqual(r.brain.socialBook.squash, 1, accuracy: 0.05); XCTAssertFalse(r.brain.socialBook.passThrough) }
                XCTAssertTrue(lab.events[0].contains { if case .ended(let k, _, let how) = $0, k == kind { return how == .done }; return false }, "\(kind) x\(n): ends happily")
                lab.checkAll("group \(kind) x\(n)", plainBound: 0.03)
            }
        }
    }

    /// The shy wave needs the pair far apart (the standard three start spots are too close).
    func testShyWaveFromAfarThenRunToEachOther() {
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-2.0, 0.5), SIMD2(1.9, 1.0)], seed: 12)
        for r in lab.rigs { r.brain.anticsEnabled = true }
        XCTAssertTrue(lab.rigs[0].brain.socialStart(.shyWave, with: lab.rigs[1].brain, lab.rigs[0].sim), "shyWave starts from afar")
        var f = 0, minGap: Float = 9
        while f < 60 * 45 { lab.tick(); f += 1; minGap = min(minGap, lab.centreGap(0, 1)); if !lab.anySocial && f > 10 { break } }
        XCTAssertFalse(lab.anySocial, "shyWave completes (\(Float(f) / 60) s)")
        XCTAssertGreaterThan(f, 60 * 4)
        XCTAssertLessThan(minGap, 1.3 * MelonController.jellyGap, "they end up next to each other")
        for r in lab.rigs { XCTAssertEqual(r.brain.socialBook.squash, 1, accuracy: 0.05) }
        lab.checkAll("shyWave", plainBound: 0.03)
    }

    func testReduceMotionRunsToo() {
        for kind in [SocialKind.groupHug, .circleDance] {
            let (lab, secs, ok, _) = run(kind, n: 3, reduce: true)
            XCTAssertTrue(ok, "\(kind) reduce motion: completes (\(secs) s)")
            lab.checkAll("group reduce \(kind)", plainBound: 0.03)
        }
    }

    func testHuddleIsTight() {
        let (_, _, ok, minGap) = run(.groupHug, n: 3)
        XCTAssertTrue(ok)
        XCTAssertLessThan(minGap, 0.95 * MelonController.jellyGap, "the huddle squeezes closer than the usual gap")
        XCTAssertGreaterThan(minGap, 0.4 * MelonController.jellyGap, "but they do not fuse")
    }

    func testBusyOnesAreNotPulledInAndTwoAreNotEnough() {
        let lab = SocialTests.Lab(seed: 5)
        for r in lab.rigs { r.brain.anticsEnabled = true }
        lab.rigs[2].brain.idleBlocked = true
        XCTAssertFalse(lab.rigs[0].brain.socialStart(.groupHug, with: lab.rigs[1].brain, lab.rigs[0].sim), "only two free: no group hug")
        XCTAssertFalse(lab.rigs[2].brain.isSocial)
        let lab2 = SocialTests.Lab(n: 5, positions: Self.five, seed: 6)
        for r in lab2.rigs { r.brain.anticsEnabled = true }
        lab2.rigs[3].brain.idleBlocked = true; lab2.rigs[4].brain.pending = .goTo(SIMD2(0, 1))
        XCTAssertTrue(lab2.rigs[0].brain.socialStart(.groupHug, with: lab2.rigs[1].brain, lab2.rigs[0].sim))
        XCTAssertTrue(lab2.rigs[2].brain.isSocial); XCTAssertFalse(lab2.rigs[3].brain.isSocial); XCTAssertFalse(lab2.rigs[4].brain.isSocial)
    }

    func testTakenMemberEndsTheGroupGently() {
        let lab = SocialTests.Lab(seed: 8)
        for r in lab.rigs { r.brain.anticsEnabled = true }
        XCTAssertTrue(lab.rigs[0].brain.socialStart(.groupHug, with: lab.rigs[1].brain, lab.rigs[0].sim))
        for _ in 0..<240 { lab.tick() }
        for _ in 0..<5 { lab.rigs[2].tick(touched: true); lab.rigs[0].tick(); lab.rigs[1].tick() }
        for _ in 0..<60 { lab.tick() }
        XCTAssertFalse(lab.anySocial, "the group ends when one is taken")
    }

    func testAutonomousGroupHugsHappenEveryFewMinutes() {
        let lab = SocialTests.Lab(quiet: false, seed: 77)
        for r in lab.rigs { r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.socialBook.cooldown = 8; r.brain.idleState.cooldown = 9 }
        for (i, r) in lab.rigs.enumerated() { r.brain.restTimer = 0.5 + Float(i) }
        var starts = [SocialKind: Int](), prev = false
        for _ in 0..<(60 * 360) {
            lab.tick(watching: lab.anySocial)
            let now = lab.rigs[0].brain.socialKind?.isGroup == true
            if now && !prev, let k = lab.rigs[0].brain.socialKind { starts[k, default: 0] += 1 }
            prev = now
        }
        MotionLog.write("GROUP roaming 360 s x3: \(starts.map { "\($0.key.rawValue)=\($0.value)" }.sorted())")
        let total = starts.values.reduce(0, +)
        XCTAssertGreaterThanOrEqual(total, 2, "group moves happen on their own")
        XCTAssertLessThanOrEqual(total, 12, "but not constantly")
        XCTAssertGreaterThanOrEqual(starts[.groupHug] ?? 0, 1, "and the hug is among them")
    }

    /// 2026-10-27 (more social): a simulated 5-minute idle session; counts what happens between the Jelbies and checks that every group hug took all the free ones.
    private func session(n: Int, seed: UInt64) {
        let lab = SocialTests.Lab(n: n, positions: n == 3 ? SocialTests.starts : Self.five, quiet: false, seed: seed)
        for (i, r) in lab.rigs.enumerated() { r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.restTimer = 0.5 + Float(i) }
        var seen = Set<ObjectIdentifier>(), hugs = 0, otherGroup = 0, pairs = 0, solo = 0, toy = 0, plain = 0, total = 0, leftOut = 0, short = 0
        var groupKinds = [String: Int](), pairKinds = [String: Int](), soloKinds = [String: Int]()
        var prevKind = [IdleKind?](repeating: nil, count: n)
        for _ in 0..<(60 * 300) {
            lab.tick(watching: false)
            for (i, r) in lab.rigs.enumerated() {
                let b = r.brain
                total += 1
                if let s = b.social {
                    if seen.insert(ObjectIdentifier(s)).inserted {
                        if s.kind.isGroup {
                            groupKinds[s.kind.rawValue, default: 0] += 1
                            if s.kind == .groupHug {
                                hugs += 1
                                let c = s.crewIDs.count
                                let pos = lab.rigs.map { $0.brain }
                                let free = pos.filter { $0.social == nil && ($0.socialFree || $0.socialWandering) && $0.idleState.kind != .sleep && simd_distance($0.position, b.position) < GroupTuning.radius }.count
                                if free > 0 { leftOut += 1 }
                                if c < n { short += 1 }
                            } else { otherGroup += 1 }
                        } else { pairs += 1; pairKinds[s.kind.rawValue, default: 0] += 1 }
                    }
                } else if let k = b.idleState.kind {
                    if k != prevKind[i], k != .wander, k != .sleep {
                        let toyKinds: Set<IdleKind> = [.decorSit, .decorBoop, .decorKick, .decorHop, .decorPeek, .decorSlide, .soccerKick]
                        if toyKinds.contains(k) { toy += 1 } else { solo += 1; soloKinds[k.rawValue, default: 0] += 1 }
                    }
                } else { plain += 1 }
                prevKind[i] = b.social == nil ? b.idleState.kind : nil
            }
        }
        let line = String(format: "MORESOCIAL 300 s x%d: groupHug=%d (all-joined: crew<n in %d, free-left-out in %d) otherGroup=%d %@ pair=%d solo=%d toy=%d plainIdle=%.0f%% pairKinds=%@ soloKinds=%@",
                          n, hugs, short, leftOut, otherGroup, "\(groupKinds)", pairs, solo, toy, 100 * Float(plain) / Float(total), "\(pairKinds)", "\(soloKinds)")
        MotionLog.write(line); print(line)
        XCTAssertGreaterThanOrEqual(hugs + otherGroup, 3, "group moves are frequent")
        XCTAssertGreaterThanOrEqual(hugs, 1, "and the hug is among them")
        if n == 3 { XCTAssertEqual(short, 0, "every group hug has all three") }
        XCTAssertEqual(leftOut, 0, "no free Jelby left out (x\(n))")
        XCTAssertGreaterThan(Float(plain) / Float(total), 0.25, "still plenty of plain roaming / rest")
    }

    func testMoreSocialSessionAtHome() { for seed in [101] as [UInt64] { session(n: 3, seed: seed) } }
    func testMoreSocialSessionAtThePark() { for seed in [303] as [UInt64] { session(n: 5, seed: seed) } }
}
