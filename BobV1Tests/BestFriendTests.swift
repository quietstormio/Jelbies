//
//  BestFriendTests.swift
//  best-friend-r1: "When a best friend is identified they play more together at the park ... same for sleepovers."
//  The one definition (ParkBestFriend), the pick weight (BondPairing), the headless five-body run (three Jelmiko + two visitors, one of them Jelmiko 0's best friend).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BestFriendTests: XCTestCase {
    private func visitor(_ id: Int, _ pts: [Int: Float], merged: Int? = nil) -> ParkVisitor {
        var v = ParkVisitor(id: id, name: "V\(id)", colour: .cream, signature: .none, wear: nil, style: .balanced, blurb: "", greeting: "")
        for (c, p) in pts { v.friendship[String(c)] = p }
        v.mergedInto = merged
        return v
    }

    // MARK: the definition

    func testDefinitionIsTheProfilesRule() {
        let vs = [visitor(0, [0: 44.9]), visitor(1, [0: 45, 1: 90]), visitor(2, [0: 80]), visitor(3, [0: 95], merged: 2), visitor(4, [0: 80])]
        XCTAssertEqual(ParkBestFriend.of(character: 0, in: vs)?.0.id, 2, "the most points; a merged record does not count; the first on a tie")
        XCTAssertEqual(ParkBestFriend.of(character: 0, in: vs)?.1, 80)
        XCTAssertEqual(ParkBestFriend.of(character: 1, in: vs)?.0.id, 1)
        XCTAssertNil(ParkBestFriend.of(character: 2, in: vs), "nobody: Still finding out")
        XCTAssertNil(ParkBestFriend.of(character: 0, in: [visitor(0, [0: 44.9]), visitor(1, [0: 20])]), "below Friend level: nil")
        XCTAssertEqual(ParkBestFriend.of(character: 0, in: [visitor(0, [0: ParkTuning.friendAt])])?.0.id, 0, "Friend level is enough (the row shows a name)")
        XCTAssertNil(ParkBestFriend.of(character: 0, in: []))
        // the same answer as the inline rule the Profile used before
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let pool = (0..<8).map { i in visitor(i, [0: Float.random(in: 0...100, using: &rng), 1: Float.random(in: 0...100, using: &rng)], merged: Int.random(in: 0..<5, using: &rng) == 0 ? 0 : nil) }
            for c in 0..<2 {
                let old = pool.filter { $0.mergedInto == nil }.compactMap { v -> (ParkVisitor, Float)? in let pts = v.friendship["\(c)"] ?? 0; return ParkFriendLevel.of(pts) >= .friend ? (v, pts) : nil }.max { $0.1 < $1.1 }
                let new = ParkBestFriend.of(character: c, in: pool)
                XCTAssertEqual(old?.0.id, new?.0.id); XCTAssertEqual(old?.1, new?.1)
            }
        }
    }

    // MARK: the weight

    /// Five bodies: Jelmiko 0, 1, 2 and visitors 3 (Jelmiko 0's best friend) and 4. Closeness as the park sets it (best friend 2.1, strangers 0.55, housemates 1).
    private func lab5(seed: UInt64, bond: Bool) -> SocialTests.Lab {
        let pos: [SIMD2<Float>] = [SIMD2(-1.2, 0.5), SIMD2(1.6, 1.4), SIMD2(0.2, 3.0), SIMD2(-0.2, 3.6), SIMD2(2.2, -0.3)]
        let lab = SocialTests.Lab(n: 5, positions: pos, quiet: true, seed: seed)
        for (i, r) in lab.rigs.enumerated() {
            for j in 0..<5 where j != i { r.brain.socialBook.close[j] = (i < 3 && j < 3) ? 1 : 0.55 }
            r.brain.anticsEnabled = true
        }
        if bond {
            lab.rigs[0].brain.socialBook.close[3] = FriendTuning.closeMul[3]; lab.rigs[3].brain.socialBook.close[0] = FriendTuning.closeMul[3]
            lab.rigs[0].brain.socialBook.bestFriends = [3]; lab.rigs[3].brain.socialBook.bestFriends = [0]
        }
        return lab
    }

    func testPartnerPickFavoursTheBestFriend() {
        let draws = 2000
        /// Every body is the chooser for `draws` rolls, the others standing where they are: (chooser, chosen) of every roll that picked.
        func run(multiplier: Float, bond: Bool) -> [(Int, Int)] {
            BondPairing.multiplier = multiplier
            let lab = lab5(seed: 5, bond: bond)
            var out: [(Int, Int)] = []
            for c in 0..<5 {
                let a = lab.rigs[c].brain
                for i in 0..<draws {
                    for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
                    for r in lab.rigs { let x = r.brain; x.socialAbort(nil); x.idleState.kind = nil; x.mix = MixBook(); x.socialBook.cooldown = 0; x.socialBook.pair = [:]; x.socialBook.recentWith = [:]; x.socialBook.lastKind = nil; x.socialBook.drought = 0; x.variety.lastSocial = [:]; x.variety.lastSocialAny = -999 }
                    a.watching = true
                    a.seed = UInt64(i + 1) &* 0x9E3779B97F4A7C15 &+ UInt64(c)
                    for _ in 0..<4 { _ = a.rand() }
                    _ = a.socialMaybeStart(lab.rigs[c].sim)
                    if let k = a.socialBook.recentWith.keys.first { out.append((c, k)) }
                }
            }
            return out
        }
        defer { BondPairing.multiplier = 2.4 }
        let off = run(multiplier: 1, bond: true), on = run(multiplier: 2.4, bond: true), none = run(multiplier: 2.4, bond: false), none1 = run(multiplier: 1, bond: false)
        func share(_ w: [(Int, Int)], _ chooser: Int, _ id: Int) -> Float { let m = w.filter { $0.0 == chooser }; return Float(m.filter { $0.1 == id }.count) / Float(max(m.count, 1)) }
        /// pair moments of body i per `draws` rolls each: its own picks plus the picks of the others that chose it
        func moments(_ w: [(Int, Int)], _ i: Int) -> Int { w.filter { $0.0 == i || $0.1 == i }.count }
        MotionLog.write("BESTFRIEND picks (\(draws) rolls per body): Jelmiko 0 picks friend off \(share(off, 0, 3)) on \(share(on, 0, 3)); other visitor off \(share(off, 0, 4)) on \(share(on, 0, 4)); Jelmiko 1 off \(share(off, 0, 1)) on \(share(on, 0, 1)); Jelmiko 2 off \(share(off, 0, 2)) on \(share(on, 0, 2)); the friend (3) picks Jelmiko 0 off \(share(off, 3, 0)) on \(share(on, 3, 0)); pair moments per body off \((0..<5).map { moments(off, $0) }) on \((0..<5).map { moments(on, $0) }) (the picks' own total off \(off.count) on \(on.count))")
        XCTAssertGreaterThan(on.count, 5 * draws / 10, "the roll passes often enough to measure")
        XCTAssertGreaterThanOrEqual(share(on, 0, 3), 2 * share(on, 0, 4), "the best friend is picked at least twice as often as the other visitor")
        XCTAssertGreaterThan(share(on, 0, 3), 0.4, "well above an even split (a quarter)")
        XCTAssertGreaterThan(share(on, 0, 3), share(off, 0, 3) * 1.4)
        XCTAssertGreaterThanOrEqual(share(on, 3, 0), 2 * share(on, 3, 4), "the friend's body does the same toward its Jelmiko")
        for c in [1, 2, 4] { XCTAssertGreaterThan(moments(on, c), Int(0.9 * Float(moments(off, c))), "body \(c) keeps at least 90 % of its pair moments") }
        for j in [1, 2] { XCTAssertGreaterThan(share(on, 0, j), 0.05, "the other Jelmiko still get picked") }
        XCTAssertGreaterThan(share(on, 0, 4), 0.05)
        XCTAssertGreaterThan(share(on, 0, 3) + share(on, 3, 0), 0.8 * (share(off, 0, 3) + share(off, 3, 0)) * 1.4)
        XCTAssertTrue(none.elementsEqual(none1, by: { $0 == $1 }), "nobody's best friend present: the weight is 1 and the picks are exactly the old ones")
    }

    func testWeightIsOneForEveryoneElse() {
        let lab = lab5(seed: 3, bond: true)
        let b = lab.rigs.map { $0.brain }
        XCTAssertEqual(BondPairing.weight(chooser: b[0], candidate: b[3]), 2.4)
        XCTAssertEqual(BondPairing.weight(chooser: b[3], candidate: b[0]), 2.4, "either direction")
        for (i, j) in [(0, 1), (0, 2), (0, 4), (1, 2), (1, 3), (2, 4), (3, 4)] { XCTAssertEqual(BondPairing.weight(chooser: b[i], candidate: b[j]), 1) }
        XCTAssertEqual(BondPairing.driftTerm(for: b[1], others: [b[0], b[2], b[3], b[4]], cand: .zero), 0, "no pull for a Jelmiko whose best friend is not there")
        XCTAssertGreaterThan(BondPairing.driftTerm(for: b[0], others: [b[1], b[2], b[3], b[4]], cand: b[3].position), 0)
        XCTAssertEqual(BondPairing.driftTerm(for: b[0], others: [b[1], b[2], b[3], b[4]], cand: b[3].position + SIMD2(30, 0)), 0, accuracy: 1e-6, "fades out")
    }

    // MARK: roaming

    private struct Tally { var pairMoments = [Int](repeating: 0, count: 5), pairFrames = [Int](repeating: 0, count: 5), withFriend = 0, withOther = 0, gapSum: Float = 0, frames = 0, picks: [(Int, [Int], Int)] = [] }

    private func roam(seed: UInt64, bond: Bool, seconds: Int) -> Tally {
        let lab = lab5(seed: seed, bond: bond)
        for (i, r) in lab.rigs.enumerated() { r.brain.idleMood = .okay; r.brain.socialBook.cooldown = 8; r.brain.idleState.cooldown = 9; r.brain.restTimer = 0.5 + Float(i) }
        var t = Tally()
        BondPairing.onPick = { c, cands, chosen in t.picks.append((c.steerID, cands.map(\.steerID), chosen.steerID)) }
        defer { BondPairing.onPick = nil }
        for _ in 0..<(60 * seconds) {
            lab.tick(watching: false)
            t.frames += 1
            t.gapSum += lab.brainGap(0, 3)
            for i in 0..<5 { if let s = lab.rigs[i].brain.social, !s.kind.isGroup { t.pairFrames[i] += 1 } }
        }
        for i in 0..<5 {
            for e in lab.events[i] { if case .began(let k, let p) = e, !k.isGroup {
                t.pairMoments[i] += 1
                if i == 0 { if p == 3 { t.withFriend += 1 } else if p == 4 { t.withOther += 1 } }
            } }
        }
        return t
    }

    func testFiveBodiesRoamingWithABestFriend() {
        let seeds = ProcessInfo.processInfo.environment["BESTFRIEND_SEEDS"].flatMap { Int($0) } ?? 2
        let secs = ProcessInfo.processInfo.environment["BESTFRIEND_SECS"].flatMap { Int($0) } ?? 150
        defer { BondPairing.multiplier = 2.4 }
        var off = Tally(), on = Tally(), strong = Tally()
        let drift0 = BondPairing.drift
        defer { BondPairing.drift = drift0 }
        func add(_ a: inout Tally, _ b: Tally) { for i in 0..<5 { a.pairMoments[i] += b.pairMoments[i]; a.pairFrames[i] += b.pairFrames[i] }; a.withFriend += b.withFriend; a.withOther += b.withOther; a.gapSum += b.gapSum; a.frames += b.frames; a.picks += b.picks }
        for s in 0..<seeds {
            BondPairing.multiplier = 1; BondPairing.drift = 0; add(&off, roam(seed: 100 + UInt64(s) * 13, bond: true, seconds: secs))
            BondPairing.multiplier = 2.4; BondPairing.drift = drift0; add(&on, roam(seed: 100 + UInt64(s) * 13, bond: true, seconds: secs))
            if ProcessInfo.processInfo.environment["BESTFRIEND_STRONG"] != nil { BondPairing.drift = 3.5; add(&strong, roam(seed: 100 + UInt64(s) * 13, bond: true, seconds: secs)) }
        }
        /// Picks by `c` where both `a` and `b` were candidates: how many chose a / b.
        func duel(_ t: Tally, _ c: Int, _ a: Int, _ b: Int) -> (Int, Int) {
            let p = t.picks.filter { $0.0 == c && $0.1.contains(a) && $0.1.contains(b) }
            return (p.filter { $0.2 == a }.count, p.filter { $0.2 == b }.count)
        }
        func line(_ n: String, _ t: Tally) -> String {
            "\(n): pair moments per body \(t.pairMoments), Jelmiko 0 with friend \(t.withFriend) with the other visitor \(t.withOther); picks with both in reach (friend vs other visitor): Jelmiko 0 \(duel(t, 0, 3, 4)), the friend \(duel(t, 3, 0, 4)); pair-time share per body \(t.pairFrames.map { String(format: "%.3f", Float($0) / Float(max(t.frames, 1))) }); mean gap 0-3 \(String(format: "%.2f", t.gapSum / Float(max(t.frames, 1))))"
        }
        MotionLog.write("BESTFRIEND roaming \(seeds) seeds x \(secs) s\n  " + line("weight OFF (x1)", off) + "\n  " + line("weight ON (x2.4)", on) + (strong.frames > 0 ? "\n  " + line("ON, drift 3.5", strong) : ""))
        /// Picks by Jelmiko 0 or its friend while the other was a candidate: how often the pair was chosen against the uniform expectation.
        func hits(_ t: Tally) -> (n: Int, hit: Int, expected: Float) {
            var n = 0, hit = 0, e: Float = 0
            for p in t.picks where (p.0 == 0 && p.1.contains(3)) || (p.0 == 3 && p.1.contains(0)) { n += 1; let f = p.0 == 0 ? 3 : 0; if p.2 == f { hit += 1 }; e += 1 / Float(p.1.count) }
            return (n, hit, e)
        }
        let hOn = hits(on), hOff = hits(off)
        MotionLog.write("BESTFRIEND roaming picks by Jelmiko 0 / its friend with the other in reach: off \(hOff) on \(hOn)")
        if hOn.n >= 8 { XCTAssertGreaterThan(Float(hOn.hit), 1.3 * hOn.expected, "in the run, Jelmiko 0 and its friend choose each other clearly more often than an even pick would") }
        let share0On = Float(on.pairFrames[0]) / Float(on.frames), share0Off = Float(off.pairFrames[0]) / Float(off.frames)
        XCTAssertLessThanOrEqual(share0On, max(share0Off + 0.05, 0.25), "Jelmiko 0's total pair time rises by a few points at most and stays in the approved range")
        XCTAssertGreaterThanOrEqual(share0On, 0.10)
    }

    // MARK: the best-friend moment (round 2)

    /// Two bodies, best friends of each other, roaming alone for `seconds`: the moments each started (mood set for the busy / grumpy cases).
    private func momentsIn(seed: UInt64, seconds: Int, grumpy: Int? = nil, bond: Bool = true) -> (Int, Int, [Int: Int]) {
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-1.6, 0.8), SIMD2(1.8, 1.6)], quiet: false, seed: seed)
        for (i, r) in lab.rigs.enumerated() {
            r.brain.anticsEnabled = true; r.brain.idleMood = i == grumpy ? .grumpy : .okay
            r.brain.socialBook.cooldown = 3; r.brain.idleState.cooldown = 9; r.brain.restTimer = 0.5 + Float(i)
            r.brain.socialBook.close[1 - i] = FriendTuning.closeMul[3]
            if bond { r.brain.socialBook.bestFriends = [1 - i] }
        }
        var first = -1, pairFrames = 0
        for f in 0..<(60 * seconds) {
            lab.tick(watching: false)
            if first < 0, lab.rigs.contains(where: { $0.brain.socialBook.bondMoments > 0 }) { first = f / 60 }
            if lab.rigs[0].brain.social != nil { pairFrames += 1 }
        }
        var kinds: [Int: Int] = [:]
        for e in lab.events[0] { if case .began(let k, _) = e { kinds[k.rawValue.hashValue & 0xff, default: 0] += 1 } }
        _ = pairFrames
        return (lab.rigs[0].brain.socialBook.bondMoments, first, kinds)
    }

    func testAMomentStartsWithinTwoMinutesWhenBothAreFreeAndNeverWhenOneIsGrumpy() {
        var started = 0, firsts: [Int] = []
        for seed in 0..<4 {
            let r = momentsIn(seed: 200 + UInt64(seed) * 7, seconds: 120)
            if r.0 > 0 { started += 1; firsts.append(r.1) }
        }
        MotionLog.write("BESTFRIEND moment: started within 120 s in \(started) of 4 runs, first at \(firsts) s")
        XCTAssertGreaterThanOrEqual(started, 3, "a best-friend moment starts within two minutes when both are free")
        for g in 0..<2 {
            let r = momentsIn(seed: 300 + UInt64(g), seconds: 120, grumpy: g)
            XCTAssertEqual(r.0, 0, "never while body \(g) is grumpy")
        }
        XCTAssertEqual(momentsIn(seed: 205, seconds: 120, bond: false).0, 0, "never without a best friend present")
    }

    /// Many seeds, five bodies: the moments raise Jelmiko 0's pair share by a few points at most and the others keep at least 90 % of their pair moments.
    func testMomentsKeepTheMixInRange() {
        let seeds = ProcessInfo.processInfo.environment["BESTFRIEND_SEEDS"].flatMap { Int($0) } ?? 2
        let secs = ProcessInfo.processInfo.environment["BESTFRIEND_SECS"].flatMap { Int($0) } ?? 150
        defer { BondPairing.multiplier = 2.4 }
        var offT = Tally(), onT = Tally()
        for s in 0..<seeds {
            BondPairing.multiplier = 1; let a = roam(seed: 400 + UInt64(s) * 11, bond: true, seconds: secs)
            BondPairing.multiplier = 2.4; let b = roam(seed: 400 + UInt64(s) * 11, bond: true, seconds: secs)
            for i in 0..<5 { offT.pairMoments[i] += a.pairMoments[i]; offT.pairFrames[i] += a.pairFrames[i]; onT.pairMoments[i] += b.pairMoments[i]; onT.pairFrames[i] += b.pairFrames[i] }
            offT.frames += a.frames; onT.frames += b.frames; offT.withFriend += a.withFriend; onT.withFriend += b.withFriend; offT.withOther += a.withOther; onT.withOther += b.withOther
        }
        MotionLog.write("BESTFRIEND mix (moments on, \(seeds) seeds x \(secs) s): pair moments off \(offT.pairMoments) on \(onT.pairMoments); pair-time share off \(offT.pairFrames.map { Float($0) / Float(offT.frames) }) on \(onT.pairFrames.map { Float($0) / Float(onT.frames) }); Jelmiko 0 with friend off \(offT.withFriend) on \(onT.withFriend), other visitor off \(offT.withOther) on \(onT.withOther)")
        for i in 0..<5 { XCTAssertLessThanOrEqual(Float(onT.pairFrames[i]) / Float(onT.frames), 0.30, "body \(i) stays inside the approved pair range") }
        for i in [1, 2, 4] { XCTAssertGreaterThanOrEqual(Float(onT.pairMoments[i]), 0.85 * Float(offT.pairMoments[i]), "body \(i) keeps its pair moments (the lab's noise allows 85 %; the pick-level test holds 90 %)") }
    }
}
