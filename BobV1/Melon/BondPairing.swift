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
    /// The roam goal's extra score for `cand`: a little more the nearer it is to the chooser's best friend while that one is up and about (0 for everybody else).
    @MainActor static func driftTerm(for b: BlobBrain, others: [BlobBrain], cand: SIMD2<Float>) -> Float {
        guard drift != 0, !b.socialBook.bestFriends.isEmpty || others.contains(where: { !$0.socialBook.bestFriends.isEmpty }) else { return 0 }
        var t: Float = 0
        for o in others where isBest(b, o) && o.idleState.kind != .sleep && !o.held {
            t = max(t, drift * max(0, 1 - min(simd_distance(cand, o.position), driftReach) / driftReach))
        }
        return t
    }
    /// Where a sleepover guest lies down near the friend's Jelmiko that is already asleep: the nearest fair spot on rings round it (nil = none: he lies where he is, as before).
    @MainActor static func bedSpot(for guest: BlobBrain, near friend: BlobBrain) -> SIMD2<Float>? {
        let c = friend.position
        var r: Float = 1.2
        while r <= 2.6 {
            for i in 0..<16 {
                let a = Float(i) / 16 * 2 * .pi + Float(guest.steerID)
                let p = c + SIMD2(cosf(a), sinf(a)) * r
                guard guest.sleepFairAnywhere(p, strict: true), guest.mixStopOK(p), guest.reachable(guest.position, p) else { continue }
                return p
            }
            r += 0.2
        }
        return nil
    }
}
