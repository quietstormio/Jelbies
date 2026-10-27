//
//  ParkGifts.swift
//  The park's friends: how many come on a visit, and the gift a friend brings over on about every other visit. Pure rules (no bodies): GameCare+Park.swift
//  drives the walk-over and the hand-off. Gifts are real store goods added to the bag (never Drops).
//

import Foundation

nonisolated enum ParkVisit {
    /// How many NPC friends come: 1...4 with weights 20 / 30 / 30 / 20 %, never more than the room left (`maxTotal` less the Jelbies that came; at least 1).
    static let visitorWeights: [Double] = [0.20, 0.30, 0.30, 0.20]
    static func visitorCount(playerCount: Int, using rng: inout some RandomNumberGenerator) -> Int {
        let room = min(max(ParkTuning.maxTotal - playerCount, 1), visitorWeights.count)
        var x = Double.random(in: 0..<visitorWeights.prefix(room).reduce(0, +), using: &rng)
        for (i, w) in visitorWeights.prefix(room).enumerated() { if x < w { return i + 1 }; x -= w }
        return room
    }
}

nonisolated enum ParkGifts {
    /// A gift is due after a visit with none (this share of the time), never twice running: about every other visit.
    static let chanceAfterNone = 0.85
    /// One visit in this share brings the nicer kind of gift.
    static let nicerShare = 0.10
    static func isDue(lastVisitGifted: Bool, using rng: inout some RandomNumberGenerator) -> Bool {
        !lastVisitGifted && Double.random(in: 0..<1, using: &rng) < chanceAfterNone
    }

    /// What the player already has: for foods and toys a count (more is fine, a stack), for one-of-a-kind goods whether they own it.
    static func pick(owns: (StoreItem) -> Bool, count: (StoreItem) -> Int, nicer: Bool, using rng: inout some RandomNumberGenerator) -> StoreItem? {
        var pool: [(StoreItem, Double)] = []
        for i in StoreCatalog.items where i.price > 0 && !i.awarded {
            switch i.kind {
            case .food, .treat:
                if !nicer, i.price <= 18 { pool.append((i, 3)) }
                else if nicer, i.price > 14 { pool.append((i, 2)) }
            case .shoes, .wear:
                guard !owns(i) else { continue }
                if !nicer, i.price <= 40 { pool.append((i, 2 * 30.0 / Double(i.price))) }
                else if nicer, i.price > 40, i.price <= 60 { pool.append((i, 1)) }
            case .decor:
                // small toys only (one room spot), a stack of up to two so decor limits are never pressed
                guard i.roomUnits == 1, i.decor?.category == .toys, count(i) < 2 else { continue }
                let w = count(i) == 0 ? 2.0 : 0.6
                if !nicer, i.price <= 35 { pool.append((i, w)) }
                else if nicer, i.price > 35, i.price <= 50 { pool.append((i, w)) }
            default: break
            }
        }
        if pool.isEmpty, nicer { return pick(owns: owns, count: count, nicer: false, using: &rng) }
        let total = pool.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var x = Double.random(in: 0..<total, using: &rng)
        for (i, w) in pool { if x < w { return i }; x -= w }
        return pool.last?.0
    }
}
