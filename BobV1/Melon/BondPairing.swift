//
//  BondPairing.swift
//  best-friend-r1 (owner: "When a best friend is identified they play more together at the park when there together, same for sleepovers").
//  WHO a Jelmiko pairs with, never how much: when a Jelmiko's best friend (the Profile's "Best friend at the Park", `ParkBestFriend` in Park/ParkModels.swift, the one
//  definition) is in the room, that body counts `multiplier` (2.4: at 3 the other Jelmiko fell below 90 % of their pair moments) times as much in the partner picks, and the roam goal leans a little toward it. Everything is 1 / 0 for everybody else,
//  and with no best friend present the old code paths run with the same random draws. Nothing is saved: the friendship points already are.
//  The brains only know body ids: GameCare (Park/GameCare+BestFriend.swift) writes `socialBook.bestFriends` from the park / guest tick.
//

import Foundation
import simd

nonisolated enum BondPairing {
    /// A best friend counts this many times in a partner pick (tests set 1 for the "weight off" run; `-BondPairOff 1` in the app).
    nonisolated(unsafe) static var multiplier: Float = DevArgs.enabled && UserDefaults.standard.integer(forKey: "BondPairOff") != 0 ? 1 : 2.4
    /// Test hook (nil in the app): called after every weighted-or-not partner pick with the chooser, its candidates and the one chosen.
    nonisolated(unsafe) static var onPick: ((BlobBrain, [BlobBrain], BlobBrain) -> Void)?

    @MainActor static func isBest(_ a: BlobBrain, _ b: BlobBrain) -> Bool {
        a.socialBook.bestFriends.contains(b.steerID) || b.socialBook.bestFriends.contains(a.steerID)
    }
    /// 1 for everybody, `multiplier` for the chooser's best friend (either direction).
    @MainActor static func weight(chooser: BlobBrain, candidate: BlobBrain) -> Float {
        var w: Float = isBest(chooser, candidate) ? multiplier : 1
        if chooser.socialBook.housemateBoost, chooser.socialBook.housemates.contains(candidate.steerID) { w *= 2 }          // (round 4: after a buddy block the next pair start prefers a housemate)
        return w
    }
    /// The partner pick: the old uniform index when every weight is 1 (same roll, same result), else the weighted one.
    @MainActor static func pick(_ cands: [BlobBrain], chooser: BlobBrain, roll: Float) -> BlobBrain {
        let chosen = choose(cands, chooser: chooser, roll: roll)
        if chooser.socialBook.housemateBoost, chooser.socialBook.housemates.contains(chosen.steerID) { chooser.socialBook.housemateBoost = false }
        onPick?(chooser, cands, chosen)
        return chosen
    }
    @MainActor private static func choose(_ cands: [BlobBrain], chooser: BlobBrain, roll: Float) -> BlobBrain {
        if multiplier != 1, cands.count > 1 {
            let ws = cands.map { weight(chooser: chooser, candidate: $0) }
            if ws.contains(where: { $0 != 1 }) {
                var x = roll * ws.reduce(0, +)
                for (i, w) in ws.enumerated() { if x < w { return cands[i] }; x -= w }
                return cands[cands.count - 1]
            }
        }
        return cands[min(cands.count - 1, Int(roll * Float(cands.count)))]
    }
    /// The best friend first, everybody else in their order.
    @MainActor static func bestFirst(_ xs: [BlobBrain], chooser: BlobBrain) -> [BlobBrain] {
        guard multiplier != 1 else { return xs }
        return xs.filter { isBest(chooser, $0) } + xs.filter { !isBest(chooser, $0) }
    }
    /// Join order at a park piece (the seesaw, the hopscotch court): bodies whose best friend is already at piece `uid` go first.
    @MainActor static func friendsFirst(_ xs: [BlobBrain], at uid: Int) -> [BlobBrain] {
        guard multiplier != 1 else { return xs }
        func with(_ b: BlobBrain) -> Bool { b.socialOthers().contains { $0 !== b && isBest(b, $0) && $0.idleState.kind != nil && $0.idleState.decorUID == uid } }
        return xs.filter(with) + xs.filter { !with($0) }
    }
}

// MARK: - the buddy block (round 4)
//  A best-friend pair does a BLOCK together on a clock: both bodies are RESERVED (a pending flag, not a request), each takes the flag at its next autonomous pick before every other urge,
//  walks to its stand spot of a meeting point (1.4 apart), waits there facing the other, and when both are there a chain of 2-3 face-safe pair kinds runs with the same partner,
//  the next one started at the next pick after each ends. Nothing running is interrupted; a body that is away gets no flag; a partner that does not come within 12 s of the first arrival cancels the block quietly.

nonisolated enum BondMoment {
    static let firstGap: ClosedRange<Float> = 10...20, nextGap: ClosedRange<Float> = 35...50
    static let awayRetry: ClosedRange<Float> = 8...12, cancelRetry: ClosedRange<Float> = 10...15
    static let waitFor: Float = 12, deadline: Float = 40, spotApart: Float = 1.4, blockMax: Float = 28
    static let travel: [SocialKind] = [.littleRace, .tag, .chase, .follow, .hopAlong]
    /// None puts two faces together (the owner's standing no-kiss rule).
    static let stay: [SocialKind] = [.swayHug, .sitTogether, .dance]
    nonisolated(unsafe) static var onBlockEnd: ((_ kinds: Int, _ seconds: Float) -> Void)?
    nonisolated(unsafe) static var nextID = 1
}

final class BuddyBlock {
    let id: Int, idA: Int, idB: Int
    var spot: [Int: SIMD2<Float>] = [:]
    var arrived: Set<Int> = []
    var plan: [SocialKind] = [], done: [SocialKind] = []
    var running = false, ended = false
    var stall = 0
    var startedAt: [Int: Float] = [:]
    init(id: Int, a: Int, b: Int) { self.id = id; idA = a; idB = b }
}

extension BlobBrain {
    /// Away: nothing is asked of a body that sleeps, naps, eats, is held or commanded, is in a group emote, a ball game or on park equipment, is grumpy or sleepy.
    var buddyAway: Bool {
        if isSleeping || isNapping || reserved || held || commanded || commandedIdle != nil || isPerched || idleMood == .grumpy || mixSleepy { return true }
        if let s = social, s.kind.isGroup || s.kind == .pass { return true }
        if let k = idleState.kind, k == .decorSit || k == .decorSlide || k == .decorHopscotch || k == .decorKick || k == .soccerKick || k == .tossBump || k == .sleep { return true }
        return false
    }

    /// The pair's clock (pickAutonomous, after `buddyPickDue`): when it fires and both are not away, reserve both and set off at once.
    func bondUrge(_ sim: SoftBody) -> Bool {
        guard BondPairing.multiplier != 1, MoveMix.on, anticsEnabled, !socialBook.bestFriends.isEmpty, socialBook.block == nil, socialBook.enabled, social == nil else { return false }
        let now = variety.now
        if socialBook.bondNextAt == 0 { socialBook.bondNextAt = now + rand(BondMoment.firstGap.lowerBound, BondMoment.firstGap.upperBound) }
        guard now >= socialBook.bondNextAt else { return false }
        func later(_ r: ClosedRange<Float>) { socialBook.bondNextAt = now + rand(r.lowerBound, r.upperBound) }
        let friends = socialOthers().filter { $0 !== self && BondPairing.isBest(self, $0) }
        guard let o = friends.min(by: { simd_distance($0.position, position) < simd_distance($1.position, position) }) else { later(BondMoment.awayRetry); return false }
        if buddyAway || o.buddyAway || o.socialBook.block != nil || !o.socialBook.enabled || simd_distance(o.position, position) > 8 { later(BondMoment.awayRetry); return false }
        guard let (sa, sb) = buddySpots(with: o) else { later(BondMoment.awayRetry); return false }
        let blk = BuddyBlock(id: BondMoment.nextID, a: steerID, b: o.steerID); BondMoment.nextID += 1
        blk.spot[steerID] = sa; blk.spot[o.steerID] = sb
        blk.plan = buddyPlan(with: o)
        for b in [self, o] { b.socialBook.block = blk; b.socialBook.buddyAssigned = b.variety.now; b.socialBook.buddyArrivedAt = -1; b.socialBook.bondNextAt = b.variety.now + 1000 }
        if EmoteSpot.logOn { NSLog("[bond] block start id=%d ids=%d,%d t=%.1f plan=%@", blk.id, steerID, o.steerID, now, blk.plan.map(\.rawValue).joined(separator: ",")) }
        return buddyPickDue(sim)
    }

    /// Two stand spots 1.4 apart round the midpoint of the pair, on clear floor (nil = none found).
    private func buddySpots(with o: BlobBrain) -> (SIMD2<Float>, SIMD2<Float>)? {
        let a = position, b = o.position
        var u = b - a; let l = simd_length(u); u = l > 0.1 ? u / l : SIMD2(1, 0)
        let m = (a + b) / 2, h = BondMoment.spotApart / 2
        let others = socialOthers().filter { $0 !== self && $0 !== o }
        for k in 0..<16 {
            var c = m
            if k > 0 { let ang = rand() * 2 * .pi; c = m + SIMD2(cosf(ang), sinf(ang)) * rand(0.3, 1.9) }
            let ra = c - u * h, rb = c + u * h
            let pa = fixed(ra), pb = fixed(rb)
            guard simd_distance(pa, ra) < 0.2, simd_distance(pb, rb) < 0.2, simd_distance(pa, pb) >= 1.3, mixStopOK(pa), mixStopOK(pb) else { continue }
            guard !slideFootPoint(pa), !slideFootPoint(pb), !hopCourtWithin(pa, footprint * HopscotchTuning.wallReach + HopscotchTuning.noRest), !hopCourtWithin(pb, footprint * HopscotchTuning.wallReach + HopscotchTuning.noRest) else { continue }
            guard !others.contains(where: { simd_distance($0.position, pa) < 1.3 || simd_distance($0.position, pb) < 1.3 }), reachable(a, pa), o.reachable(b, pb) else { continue }
            return (pa, pb)
        }
        return nil
    }

    private func shuffledByRand<T>(_ a: [T]) -> [T] { var x = a; var i = x.count - 1; while i > 0 { let j = min(i, Int(rand() * Float(i + 1))); x.swapAt(i, j); i -= 1 }; return x }

    /// 2 or 3 kinds, never the same twice: one or two that travel and one that stays, in a random order.
    private func buddyPlan(with o: BlobBrain) -> [SocialKind] {
        let recent = Set((socialBook.recentWith[o.steerID] ?? []) + (o.socialBook.recentWith[steerID] ?? []))
        var tr = BondMoment.travel.filter { !recent.contains($0) }, st = BondMoment.stay.filter { !recent.contains($0) }
        if tr.count < 2 { tr = BondMoment.travel }; if st.isEmpty { st = BondMoment.stay }
        tr = shuffledByRand(tr); st = shuffledByRand(st)
        var plan = [tr[0], st[0]]
        if rand() < 0.5, tr.count > 1 { plan.append(tr[1]) }
        return shuffledByRand(plan)
    }

    /// pickAutonomous, FIRST of all the urges: a body with a reserved buddy block takes its flag here (nothing running is interrupted; this is the next pick). True = this pick is used up.
    func buddyPickDue(_ sim: SoftBody) -> Bool {
        guard let blk = socialBook.block else { return false }
        if blk.ended { socialBook.block = nil; letGo(); return false }
        let now = variety.now
        let pid = blk.idA == steerID ? blk.idB : blk.idA
        guard let o = socialBrain(pid) else { buddyCancel(blk, "gone"); return false }
        if buddyAway || o.buddyAway { buddyCancel(blk, "away"); return false }
        if !blk.running {
            if now - socialBook.buddyAssigned > BondMoment.deadline { buddyCancel(blk, "late"); return false }
            guard let spot = blk.spot[steerID] else { buddyCancel(blk, "nospot"); return false }
            if simd_distance(position, spot) > 0.3 {
                socialBook.buddyArrivedAt = -1; blk.arrived.remove(steerID); letGo()
                requestNow(.goTo(spot))
                return true
            }
            if socialBook.buddyArrivedAt < 0 { socialBook.buddyArrivedAt = now; blk.arrived.insert(steerID) }
            holdFacing(yawTo(o.position)); restTimer = 0.3
            if blk.arrived.contains(pid) { return buddyStartNext(blk, o, sim) }
            if now - socialBook.buddyArrivedAt > BondMoment.waitFor { buddyCancel(blk, "timeout"); return false }
            return true
        }
        if social != nil || o.social != nil { restTimer = 0.3; return true }
        return buddyStartNext(blk, o, sim)
    }

    private func buddyStartNext(_ blk: BuddyBlock, _ o: BlobBrain, _ sim: SoftBody) -> Bool {
        let now = variety.now
        let started = blk.startedAt[steerID] ?? now
        if blk.done.count >= blk.plan.count || (blk.running && now - started > BondMoment.blockMax) { buddyEnd(blk); return false }
        guard socialFree, o.socialFree else {          // (the other is still finishing the last one: next pick)
            blk.stall += 1; restTimer = 0.3
            if blk.stall > 20 { if blk.done.isEmpty { buddyCancel(blk, "notfree") } else { buddyEnd(blk) } ; return false }
            return true
        }
        let remaining = blk.plan.filter { !blk.done.contains($0) }
        let fallback = (BondMoment.travel + BondMoment.stay).filter { !blk.done.contains($0) && !remaining.contains($0) }
        for kind in remaining + fallback {
            letGo(); o.letGo()
            if socialStart(kind, with: o, sim) {
                blk.done.append(kind); blk.running = true; blk.stall = 0
                if blk.startedAt[steerID] == nil { blk.startedAt[steerID] = now }
                if blk.startedAt[o.steerID] == nil { blk.startedAt[o.steerID] = o.variety.now }
                for (a, b) in [(self, o), (o, self)] { var r = a.socialBook.recentWith[b.steerID] ?? []; r.append(kind); a.socialBook.recentWith[b.steerID] = Array(r.suffix(3)) }
                varietyNoteSocial(kind, with: o); socialBook.lastKind = kind
                for b in [self, o] { b.socialBook.bondMoments += 1 }
                if EmoteSpot.logOn { NSLog("[bond] block id=%d kind=%@ ids=%d,%d t=%.1f", blk.id, kind.rawValue, steerID, o.steerID, now) }
                return true
            }
        }
        if blk.done.isEmpty { buddyCancel(blk, "nokind") } else { buddyEnd(blk) }
        return false
    }

    private func buddyEnd(_ blk: BuddyBlock) {
        guard !blk.ended else { return }
        blk.ended = true
        let secs = variety.now - (blk.startedAt[steerID] ?? variety.now)
        BondMoment.onBlockEnd?(blk.done.count, secs)
        if EmoteSpot.logOn { NSLog("[bond] block end id=%d t=%.1f seconds=%.1f kinds=%d", blk.id, variety.now, secs, blk.done.count) }
        for id in [blk.idA, blk.idB] {
            guard let b = socialBrain(id) ?? (id == steerID ? self : nil) else { continue }
            b.socialBook.block = nil; b.letGo(); b.socialBook.buddyArrivedAt = -1
            b.socialBook.bondNextAt = b.variety.now + b.rand(BondMoment.nextGap.lowerBound, BondMoment.nextGap.upperBound)
            b.socialBook.housemateBoost = !b.socialBook.housemates.isEmpty
        }
    }

    private func buddyCancel(_ blk: BuddyBlock, _ why: String) {
        guard !blk.ended else { socialBook.block = nil; letGo(); return }
        blk.ended = true
        if EmoteSpot.logOn { NSLog("[bond] block cancel id=%d why=%@ t=%.1f", blk.id, why, variety.now) }
        for id in [blk.idA, blk.idB] {
            guard let b = socialBrain(id) ?? (id == steerID ? self : nil) else { continue }
            b.socialBook.block = nil; b.letGo(); b.socialBook.buddyArrivedAt = -1
            b.socialBook.bondNextAt = b.variety.now + b.rand(BondMoment.cancelRetry.lowerBound, BondMoment.cancelRetry.upperBound)
        }
    }
}
