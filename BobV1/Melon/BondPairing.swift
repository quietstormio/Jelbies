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
        if chooser.socialBook.housemateBoost, !chooser.socialBook.housemates.isEmpty {          // (round 6: after a block the next pair start takes a housemate when one is among the candidates)
            let hs = cands.filter { chooser.socialBook.housemates.contains($0.steerID) }
            if !hs.isEmpty { return hs[min(hs.count - 1, Int(roll * Float(hs.count)))] }
        }
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
    static let awayRetry: ClosedRange<Float> = 8...12, cancelRetry: ClosedRange<Float> = 20...25, yieldRetry: ClosedRange<Float> = 20...30
    static let waitFor: Float = 12, deadline: Float = 40, spotApart: Float = 1.4, blockMax: Float = 28
    static let travel: [SocialKind] = [.littleRace, .tag, .chase, .follow, .hopAlong]
    /// None puts two faces together (the owner's standing no-kiss rule).
    static let stay: [SocialKind] = [.swayHug, .sitTogether, .dance]
    nonisolated(unsafe) static var onBlockEnd: ((_ kinds: Int, _ seconds: Float) -> Void)?
    nonisolated(unsafe) static var nextID = 1
    /// Round 5: more than this many bodies up in the place = crowded: no chasing kinds, one travelling kind per block at most.
    static let crowd = 3
    /// Crowded: the calm kinds (one of the travelling pair at most, the others stay put).
    static let calmTravel: [SocialKind] = [.hopAlong, .follow]
    static let calmStay: [SocialKind] = [.swayHug, .sitTogether, .dance, .peekaboo, .backToBack]
    /// The one block in progress in a place (round 5: at most one at a time).
    nonisolated(unsafe) static var active: BuddyBlock?
    /// Test hook: a kind of a block started with `up` bodies up.
    /// Soccer sessions (another branch): true for a body that is a member of a running soccer session; such a body is "away" (no flag). The session code sets this one closure.
    nonisolated(unsafe) static var soccerMember: ((_ steerID: Int) -> Bool)?
    nonisolated(unsafe) static var onKind: ((_ block: Int, _ kind: SocialKind, _ up: Int) -> Void)?
}

final class BuddyBlock {
    let id: Int, idA: Int, idB: Int
    var spot: [Int: SIMD2<Float>] = [:]
    var arrived: Set<Int> = []
    var plan: [SocialKind] = [], done: [SocialKind] = []
    var running = false, ended = false
    var stall = 0
    var waiter: Int?
    var allowed: [SocialKind] = []
    var up = 0
    var startedAt: [Int: Float] = [:]
    /// Round 6: where each body stood when it took its flag (the `[bond] flag` / `[bond] meet` lines).
    var flagAt: [Int: SIMD2<Float>] = [:]
    init(id: Int, a: Int, b: Int) { self.id = id; idA = a; idB = b }
}

extension BlobBrain {
    /// Away: nothing is asked of a body that sleeps, naps, eats, is held or commanded, is in a group emote, a ball game or on park equipment, is grumpy or sleepy.
    /// Round 6: after a block the two part: the next roam goal (one pick) is at least 2.5 from where the other stood and on its own side of the midpoint.
    func partOK(_ cand: SIMD2<Float>) -> Bool {
        guard let f = socialBook.partFrom, variety.now < socialBook.partUntil else { return true }
        if simd_distance(cand, f) < 2.5 { return false }
        let s = socialBook.partSide
        return s == 0 || (cand.x - socialBook.partMidX) * s > 0
    }
    var partActive: Bool { socialBook.partFrom != nil && variety.now < socialBook.partUntil }
    func partDone() { socialBook.partFrom = nil }

    /// True while the body holds a buddy-block flag or is in a block: a soccer session leaves such a body alone until the block ends.
    var inBuddyBlock: Bool { socialBook.block != nil }
    var buddyAway: Bool {
        if BondMoment.soccerMember?(steerID) == true { return true }
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
        // one block at a time in a place; of two pairs due, the closer friends go (the other waits 20...30 s)
        if let act = BondMoment.active, !act.ended, ([self] + socialOthers()).contains(where: { ($0.steerID == act.idA || $0.steerID == act.idB) && $0.socialBook.block === act }) { later(BondMoment.yieldRetry); return false }
        let mine = socialBook.bestPoints[o.steerID] ?? 0
        for x in socialOthers() where x !== self && x !== o && !x.socialBook.bestFriends.isEmpty && x.socialBook.block == nil && x.variety.now >= x.socialBook.bondNextAt && x.socialBook.bondNextAt != 0 {
            let theirs = x.socialBook.bestFriends.compactMap { x.socialBook.bestPoints[$0] }.max() ?? 0
            if theirs > mine + 0.01 { later(BondMoment.yieldRetry); return false }
        }
        guard let wait = buddyWaitSpot(for: o) else { later(BondMoment.awayRetry); return false }
        let blk = BuddyBlock(id: BondMoment.nextID, a: steerID, b: o.steerID); BondMoment.nextID += 1
        blk.waiter = steerID; blk.spot[steerID] = wait
        let up = ([self] + socialOthers().filter { $0 !== self }).filter { $0.idleState.kind != .sleep }.count
        blk.up = up
        blk.plan = buddyPlan(with: o, crowded: up > BondMoment.crowd)
        blk.allowed = up > BondMoment.crowd ? BondMoment.calmTravel + BondMoment.calmStay : BondMoment.travel + BondMoment.stay
        BondMoment.active = blk
        for b in [self, o] { b.socialBook.block = blk; b.socialBook.buddyAssigned = b.variety.now; b.socialBook.buddyArrivedAt = -1; b.socialBook.bondNextAt = b.variety.now + 1000 }
        if EmoteSpot.logOn { NSLog("[bond] block start id=%d ids=%d,%d t=%.1f plan=%@", blk.id, steerID, o.steerID, now, blk.plan.map(\.rawValue).joined(separator: ",")) }
        return buddyPickDue(sim)
    }

    /// A spot clear for a body to stand on (clear visible floor, off the slide foot / hopscotch court, no third body within 1.3).
    private func buddyClear(_ p: SIMD2<Float>, besides o: BlobBrain) -> Bool {
        let q = fixed(p)
        guard simd_distance(q, p) < 0.2, mixStopOK(p), !slideFootPoint(p), !hopCourtWithin(p, footprint * HopscotchTuning.wallReach + HopscotchTuning.noRest) else { return false }
        return !socialOthers().contains { $0 !== self && $0 !== o && simd_distance($0.position, p) < 1.3 }
    }
    /// The first one stays: its own spot if that is clear floor with room for the partner 1.4 away, else the nearest such spot within 1.0 (nil = none).
    private func buddyWaitSpot(for o: BlobBrain) -> SIMD2<Float>? {
        func roomFor(_ p: SIMD2<Float>) -> Bool {
            let toward = o.position - p, l = simd_length(toward)
            let base = l > 0.1 ? atan2f(toward.y, toward.x) : 0
            for da: Float in [0, 0.6, -0.6, 1.2, -1.2, 2.0, -2.0, .pi] {
                let q = p + SIMD2(cosf(base + da), sinf(base + da)) * BondMoment.spotApart
                if buddyClear(q, besides: o) { return true }
            }
            return false
        }
        if buddyClear(position, besides: o), roomFor(position) { return position }
        for r: Float in [0.4, 0.7, 1.0] {
            for k in 0..<8 {
                let a = Float(k) / 8 * 2 * .pi + rand()
                let p = position + SIMD2(cosf(a), sinf(a)) * r
                if buddyClear(p, besides: o), roomFor(p), reachable(position, p) { return p }
            }
        }
        return nil
    }
    /// The second one walks: a spot 1.4 from the waiter on the side it comes from.
    private func buddyStandSpot(near w: SIMD2<Float>, partner o: BlobBrain) -> SIMD2<Float>? {
        let from = position - w, l = simd_length(from)
        let base = l > 0.1 ? atan2f(from.y, from.x) : 0
        for da: Float in [0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9] {
            let p = w + SIMD2(cosf(base + da), sinf(base + da)) * BondMoment.spotApart
            if buddyClear(p, besides: o), reachable(position, p) { return p }
        }
        return nil
    }

    private func shuffledByRand<T>(_ a: [T]) -> [T] { var x = a; var i = x.count - 1; while i > 0 { let j = min(i, Int(rand() * Float(i + 1))); x.swapAt(i, j); i -= 1 }; return x }

    /// 2 or 3 kinds, never the same twice: one or two that travel and one that stays, in a random order.
    private func buddyPlan(with o: BlobBrain, crowded: Bool) -> [SocialKind] {
        let recent = Set((socialBook.recentWith[o.steerID] ?? []) + (o.socialBook.recentWith[steerID] ?? []))
        var tr = (crowded ? BondMoment.calmTravel : BondMoment.travel).filter { !recent.contains($0) }
        var st = (crowded ? BondMoment.calmStay : BondMoment.stay).filter { !recent.contains($0) }
        if tr.isEmpty { tr = crowded ? BondMoment.calmTravel : BondMoment.travel }; if st.count < 2 { st = crowded ? BondMoment.calmStay : BondMoment.stay }
        tr = shuffledByRand(tr); st = shuffledByRand(st)
        var plan = [tr[0], st[0]]
        if rand() < 0.5 { if crowded { plan.append(st[1]) } else if tr.count > 1 { plan.append(tr[1]) } else { plan.append(st[1]) } }
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
            if blk.flagAt[steerID] == nil {
                blk.flagAt[steerID] = position
                if EmoteSpot.logOn { NSLog("[bond] flag id=%d body=%d role=%@ at=%.2f,%.2f t=%.1f", blk.id, steerID, blk.waiter == steerID ? "waiter" : "walker", position.x, position.y, now) }
            }
            if now - socialBook.buddyAssigned > BondMoment.deadline { buddyCancel(blk, "late"); return false }
            if blk.spot[steerID] == nil {          // the second one: a spot 1.4 from the waiter, on the side it comes from
                guard let w = blk.waiter, let wb = socialBrain(w), let ws = blk.spot[w], let sp = buddyStandSpot(near: ws, partner: wb) else { buddyCancel(blk, "nospot"); return false }
                blk.spot[steerID] = sp
            }
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
        let fallback = blk.allowed.filter { !blk.done.contains($0) && !remaining.contains($0) && (blk.up <= BondMoment.crowd || !BondMoment.calmTravel.contains($0) || !blk.done.contains(where: { BondMoment.calmTravel.contains($0) }) && !remaining.contains(where: { BondMoment.calmTravel.contains($0) })) }
        for kind in remaining + fallback {
            letGo(); o.letGo()
            if socialStart(kind, with: o, sim) {
                if blk.done.isEmpty, EmoteSpot.logOn, let w = blk.waiter, let wb = socialBrain(w) ?? (w == steerID ? self : nil) {
                    let other = wb === self ? o : self
                    NSLog("[bond] meet id=%d waiter=%d at=%.2f,%.2f moved=%.2f walker=%d at=%.2f,%.2f moved=%.2f t=%.1f", blk.id, w, wb.position.x, wb.position.y, simd_distance(wb.position, blk.flagAt[w] ?? wb.position), other.steerID, other.position.x, other.position.y, simd_distance(other.position, blk.flagAt[other.steerID] ?? other.position), now)
                }
                blk.done.append(kind); blk.running = true; blk.stall = 0
                if blk.startedAt[steerID] == nil { blk.startedAt[steerID] = now }
                if blk.startedAt[o.steerID] == nil { blk.startedAt[o.steerID] = o.variety.now }
                for (a, b) in [(self, o), (o, self)] { var r = a.socialBook.recentWith[b.steerID] ?? []; r.append(kind); a.socialBook.recentWith[b.steerID] = Array(r.suffix(3)) }
                varietyNoteSocial(kind, with: o); socialBook.lastKind = kind
                for b in [self, o] { b.socialBook.bondMoments += 1 }
                BondMoment.onKind?(blk.id, kind, blk.up)
                if EmoteSpot.logOn { NSLog("[bond] block id=%d kind=%@ ids=%d,%d t=%.1f up=%d", blk.id, kind.rawValue, steerID, o.steerID, now, blk.up) }
                return true
            }
        }
        if blk.done.isEmpty { buddyCancel(blk, "nokind") } else { buddyEnd(blk) }
        return false
    }

    private func buddyEnd(_ blk: BuddyBlock) {
        guard !blk.ended else { return }
        blk.ended = true; if BondMoment.active === blk { BondMoment.active = nil }
        let secs = variety.now - (blk.startedAt[steerID] ?? variety.now)
        BondMoment.onBlockEnd?(blk.done.count, secs)
        if EmoteSpot.logOn { NSLog("[bond] block end id=%d t=%.1f seconds=%.1f kinds=%d", blk.id, variety.now, secs, blk.done.count) }
        let pair = [blk.idA, blk.idB].compactMap { id in socialBrain(id) ?? (id == steerID ? self : nil) }
        for b in pair {
            let o = pair.first { $0 !== b }
            b.socialBook.block = nil; b.letGo(); b.socialBook.buddyArrivedAt = -1
            if let o { b.socialBook.partFrom = o.position; b.socialBook.partMidX = (o.position.x + b.position.x) / 2; b.socialBook.partSide = b.position.x == o.position.x ? 0 : (b.position.x < o.position.x ? -1 : 1); b.socialBook.partUntil = b.variety.now + 25 }
            b.socialBook.bondNextAt = b.variety.now + b.rand(BondMoment.nextGap.lowerBound, BondMoment.nextGap.upperBound)
            b.socialBook.housemateBoost = !b.socialBook.housemates.isEmpty
        }
    }

    private func buddyCancel(_ blk: BuddyBlock, _ why: String) {
        guard !blk.ended else { socialBook.block = nil; letGo(); return }
        blk.ended = true; if BondMoment.active === blk { BondMoment.active = nil }
        if EmoteSpot.logOn { NSLog("[bond] block cancel id=%d why=%@ t=%.1f", blk.id, why, variety.now) }
        for id in [blk.idA, blk.idB] {
            guard let b = socialBrain(id) ?? (id == steerID ? self : nil) else { continue }
            b.socialBook.block = nil; b.letGo(); b.socialBook.buddyArrivedAt = -1
            b.socialBook.bondNextAt = b.variety.now + b.rand(BondMoment.cancelRetry.lowerBound, BondMoment.cancelRetry.upperBound)
        }
    }
}
