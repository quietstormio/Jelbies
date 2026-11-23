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
    /// The roam goal's pull toward an idle best friend (score units; the stale-floor and third terms are 6 and 30 x need, the "far from the others" term 0.6 per unit).
    nonisolated(unsafe) static var drift: Float = DevArgs.enabled && UserDefaults.standard.integer(forKey: "BondPairOff") != 0 ? 0 : 2.0
    /// Test hook (nil in the app): called after every weighted-or-not partner pick with the chooser, its candidates and the one chosen.
    nonisolated(unsafe) static var onPick: ((BlobBrain, [BlobBrain], BlobBrain) -> Void)?
    /// Distance (units) over which the pull fades to nothing.
    static let driftReach: Float = 6

    @MainActor static func isBest(_ a: BlobBrain, _ b: BlobBrain) -> Bool {
        a.socialBook.bestFriends.contains(b.steerID) || b.socialBook.bestFriends.contains(a.steerID)
    }
    /// 1 for everybody, `multiplier` for the chooser's best friend (either direction).
    @MainActor static func weight(chooser: BlobBrain, candidate: BlobBrain) -> Float {
        isBest(chooser, candidate) ? multiplier : 1
    }
    /// The partner pick: the old uniform index when every weight is 1 (same roll, same result), else the weighted one.
    @MainActor static func pick(_ cands: [BlobBrain], chooser: BlobBrain, roll: Float) -> BlobBrain {
        let chosen = choose(cands, chooser: chooser, roll: roll)
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
    /// The roam goal's extra score for `cand`: a little more the nearer it is to the chooser's best friend while that one is up and about (0 for everybody else).
    @MainActor static func driftTerm(for b: BlobBrain, others: [BlobBrain], cand: SIMD2<Float>) -> Float {
        guard drift != 0, !b.socialBook.bestFriends.isEmpty || others.contains(where: { !$0.socialBook.bestFriends.isEmpty }) else { return 0 }
        var t: Float = 0
        for o in others where isBest(b, o) && o.idleState.kind != .sleep && !o.held {
            t = max(t, drift * max(0, 1 - min(simd_distance(cand, o.position), driftReach) / driftReach))
        }
        return t
    }
}

// MARK: - the best-friend moment (round 2)

nonisolated enum BondMoment {
    /// About every this many seconds (game time) one of a best-friend pair goes to the other; the first one sooner.
    static let gap: ClosedRange<Float> = 60...100, firstGap: ClosedRange<Float> = 15...35
    /// A busy partner: look again after this long, at most `maxTries` times, then give up quietly until the next gap.
    static let retry: ClosedRange<Float> = 3...6, maxTries = 8
    /// After a moment starts, neither starts an ordinary pair for this long (the moment replaces one; the pair share stays where it was).
    static let quiet: Float = 45
    nonisolated(unsafe) static var fails: [String: Int] = [:]
    nonisolated(unsafe) static var logAt: Float = 0
    /// The friendly pair kinds a moment may use (all existing; the one not seen for longest goes first).
    /// Side by side, back to back, chasing, hopping: none puts two faces together (the owner's standing no-kiss rule): not chestBump, nuzzle, twirl, shyWave, mirrorDance, danceOff, highFive, cheekSquish, whisperGiggle, cuddleLean, spinHug.
    static let kinds: [SocialKind] = [.swayHug, .hopAlong, .littleRace, .tag, .peekaboo, .sitTogether, .dance, .follow, .ringAround, .backToBack, .chase]
}

extension BlobBrain {
    /// pickAutonomous (before the ordinary pair roll): about every minute or so one of a Jelmiko and its best friend goes to the other and they do a friendly pair emote together. Same shape as `mixSoccerUrge`:
    /// a clock, a few retries while one of them is busy, a quiet give-up, never interrupting anything. True = a moment was started (or the partner asked to stop for it).
    func bondUrge(_ sim: SoftBody) -> Bool {
        guard BondPairing.multiplier != 1, MoveMix.on, anticsEnabled, !socialBook.bestFriends.isEmpty else { return false }
        guard idleMood != .grumpy, !mixSleepy, !reserved, social == nil, idleState.kind == nil, !socialBook.hold, socialBook.enabled, socialFree else { return false }
        let now = variety.now
        if socialBook.bondNextAt == 0 { socialBook.bondNextAt = now + rand(BondMoment.firstGap.lowerBound, BondMoment.firstGap.upperBound) }
        guard now >= socialBook.bondNextAt else { return false }
        func later(_ s: ClosedRange<Float>) { socialBook.bondNextAt = now + rand(s.lowerBound, s.upperBound) }
        func fail(_ why: String) {
            socialBook.bondTries += 1; if socialBook.bondTries > BondMoment.maxTries { socialBook.bondTries = 0; later(BondMoment.gap) } else { later(BondMoment.retry) }
            if EmoteSpot.logOn { BondMoment.fails["\(steerID):\(why)", default: 0] += 1; if now - BondMoment.logAt > 30 { BondMoment.logAt = now; NSLog("[bondurge] fails %@", BondMoment.fails.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")) } }
        }
        let friends = socialOthers().filter { $0 !== self && BondPairing.isBest(self, $0) }
        guard let o = friends.min(by: { simd_distance($0.position, position) < simd_distance($1.position, position) }) else { fail("nofriend"); return false }
        let d = simd_distance(o.position, position)
        if o.meetBusy || o.reserved { fail("busy"); return false }
        if o.idleMood == .grumpy || o.mixSleepy || o.idleState.kind == .sleep { fail("mood"); return false }
        if o.held || o.commanded || !o.socialBook.enabled { fail("held"); return false }
        if !(o.socialFree || (o.socialWandering && o.idleState.kind == nil)) { fail("notfree"); return false }
        if d <= 0.9 || d >= 9 { fail("dist"); return false }
        if !o.mixStopOK(o.position) { fail("stopok"); return false }
        if (socialBook.pair[o.steerID] ?? 0) > 0 || (o.socialBook.pair[steerID] ?? 0) > 0 { fail("paircool"); return false }
        let recent = Set((socialBook.recentWith[o.steerID] ?? []) + (o.socialBook.recentWith[steerID] ?? []))
        let night = idleNight >= 0.5
        let order = BondMoment.kinds.filter { !recent.contains($0) && !(night && $0.isFast) }
            .sorted { a, b in
                let ta = min(variety.lastSocial[a].map { now - $0 } ?? 1e6, o.variety.lastSocial[a].map { o.variety.now - $0 } ?? 1e6)
                let tb = min(variety.lastSocial[b].map { now - $0 } ?? 1e6, o.variety.lastSocial[b].map { o.variety.now - $0 } ?? 1e6)
                return ta > tb
            }
        for kind in order.prefix(5) {
            var ok = false
            if emoteMeetPlan(kind, with: o) { ok = true }
            else if !o.socialFree { if o.socialBeckonStop() { socialBook.invite = (kind, o.steerID, 0); ok = true } }
            else if socialStart(kind, with: o, sim) { ok = true }
            guard ok else { continue }
            for (a, b) in [(self, o), (o, self)] { var r = a.socialBook.recentWith[b.steerID] ?? []; r.append(kind); a.socialBook.recentWith[b.steerID] = Array(r.suffix(3)) }
            varietyNoteSocial(kind, with: o); socialBook.lastKind = kind
            for b in [self, o] { b.mix.quietUntil = max(b.mix.quietUntil, b.variety.now + BondMoment.quiet); b.socialBook.bondMoments += 1; b.socialBook.bondTries = 0 }
            later(BondMoment.gap); o.socialBook.bondNextAt = o.variety.now + rand(BondMoment.gap.lowerBound, BondMoment.gap.upperBound)
            mix.last = .social
            if EmoteSpot.logOn { NSLog("[bond] moment t=%.1f ids=%d,%d kind=%@ gap=%.1f", now, steerID, o.steerID, kind.rawValue, d) }
            return true
        }
        fail("nokind")
        return false
    }
}
