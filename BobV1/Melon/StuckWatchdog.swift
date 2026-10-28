//
//  StuckWatchdog.swift
//  The general no-getting-stuck guarantee (2026-10-27: "they need to work it out"). One slot per body (a Jelbie at home, at the Park, a guest).
//  A body is STUCK while it is trying to walk and makes no progress (`steerStall`), or while it overlaps another body. How long decides what happens:
//    >= pushAt     a gentle separation push (a smooth nudge, the lower id gives the larger share: no mirrored dance)
//    >= replanAt   a re-plan: the less busy of the pair yields (tie: the higher id) and walks to a detour spot round the blocker; the walker's route is dropped
//    >= giveUpAt   the walk is dropped (its owner re-plans or picks something new); overlapping bodies keep being nudged apart, smoothly, never teleported
//  No allocation per step (fixed arrays); the work is O(n^2) over at most ~8 bodies.
//

import Foundation
import simd

final class StuckWatchdog {
    /// (Seconds of being stuck AFTER the 0.5 s a stall must last to count, so these act at about 1.5 / 2.5 / 3.5 s of no progress.)
    static let pushAt: Float = 1.0, replanAt: Float = 2.0, giveUpAt: Float = 3.0
    /// Centres closer than this are bodies inside each other (the room's own spring keeps normal neighbours >= ~1.0 apart, diners >= ~0.55).
    static let overlapDist: Float = 0.5
    static let nudgeSpeed: Float = 0.9          // u/s at the most

    private(set) var stuck = [Float](repeating: 0, count: 12)          // seconds stuck per slot (diagnostics / tests)
    private var free = [Float](repeating: 0, count: 12)                // seconds in a row doing fine
    private var replanned = [Bool](repeating: false, count: 12)
    private var gaveUp = [Bool](repeating: false, count: 12)
    private var blocker = [Int](repeating: -1, count: 12)
    private(set) var pushes = 0, replans = 0, giveUps = 0
    private var best: [Float] = [0, 0]

    func reset() { for i in stuck.indices { stuck[i] = 0; free[i] = 0; replanned[i] = false; gaveUp[i] = false; blocker[i] = -1 } }

    /// Busier bodies keep going; the less busy one yields.
    private func busy(_ b: BlobBrain) -> Int {
        var s = 0
        if b.commanded { s += 4 }
        if b.job != nil { s += 3 }
        if b.activity == .eating || b.activity == .drinking { s += 6 }
        if b.isSocial { s += 2 }
        if b.reserved { s += 1 }
        return s
    }
    /// Can this body be moved aside (not mid-meal, not asleep, not in a race / show)?
    private func movable(_ b: BlobBrain) -> Bool {
        b.enabled && b.attached && !b.isNapping && !b.race.active && b.activity != .eating && b.activity != .drinking && !b.isPerched
    }

    /// `pos[i]` = the snapshot spot of slot i (the stage's peer snapshot); `brains[i]` its brain. Hidden bodies (away spot) are ignored.
    func tick(pos: [(pos: SIMD2<Float>, walking: Bool)], brains: [BlobBrain?], dt: Float) {
        let n = min(pos.count, brains.count, stuck.count)
        guard n > 0 else { return }
        for i in 0..<n {
            guard let b = brains[i], b.enabled, pos[i].pos.x < 500 else { stuck[i] = 0; free[i] = 0; continue }
            // the nearest body inside mine (not for a sitter on a seat: the furniture's business)
            var other = -1, od = Self.overlapDist
            if !b.isPerched, !b.isSocial {
                for j in 0..<n where j != i {
                    guard let o = brains[j], o.enabled, pos[j].pos.x < 500, !o.isPerched, !o.isSocial else { continue }
                    let d = simd_distance(pos[i].pos, pos[j].pos)
                    if d < od { od = d; other = j }
                }
            }
            let walkStuck = b.tryingToMove && b.steerStall > 0.5
            let bad = walkStuck || other >= 0
            if bad { stuck[i] += dt; free[i] = 0 }
            else {
                free[i] += dt
                if free[i] > 1.0 { stuck[i] = 0; replanned[i] = false; gaveUp[i] = false; blocker[i] = -1 }
                continue
            }
            if other >= 0 { blocker[i] = other }
            let s = stuck[i]
            guard s >= Self.pushAt else { continue }
            let j = blocker[i]
            let me = pos[i].pos
            // 1. a gentle push apart (the lower id gives the larger share, so two never mirror each other)
            if j >= 0, let o = brains[j] {
                var away = me - pos[j].pos
                let L = simd_length(away)
                away = L > 1e-4 ? away / L : SIMD2<Float>(i > j ? 1 : -1, i > j ? 0.3 : -0.3)
                let iYield = Self.yields(i, j, b, o, busy(b), busy(o))
                if L < GameCareGap.value * 0.8 || other >= 0 {
                    let share: Float = iYield ? 1 : 0.35
                    if movable(b) { b.unstickNudge(away * Self.nudgeSpeed * dt * share, maxStep: Self.nudgeSpeed * dt) }
                    pushes += 1
                }
                // 2. re-plan: the yielder takes a detour spot round the blocker
                if s >= Self.replanAt, !replanned[i], iYield || !movable(o) {
                    replanned[i] = true
                    if let spot = detour(i, around: j, pos: pos, brains: brains, n: n), b.pending == nil, !b.commanded || b.job != nil {
                        b.route = []; b.requestNow(.goTo(spot)); replans += 1
                    }
                }
            } else if b.tryingToMove, s >= Self.replanAt, !replanned[i] {
                // boxed in by a wall or a piece of decor: a waypoint that leaves the pocket toward his goal, else the route is dropped and planned afresh
                replanned[i] = true; replans += 1
                if let spot = goalWaypoint(i, pos: pos, brains: brains, n: n), b.pending == nil { b.route = []; b.requestNow(.goTo(spot)) }
                else { b.route = []; b.steerWait = 0; b.steerGiveUp = false; b.stuckT = 0 }
            }
            // 3. give up the target
            if s >= Self.giveUpAt, !gaveUp[i], b.tryingToMove {
                gaveUp[i] = true; giveUps += 1
                b.unstickGiveUp()
            }
        }
    }

    /// Where this walker is headed (nil when he is not on a walk).
    private func goal(_ b: BlobBrain) -> SIMD2<Float>? { if case .walk(let t, _) = b.script { return t }; return nil }

    /// A free spot 0.6-2.2 u away that the floor rules leave alone, with a clear straight leg to it, no body on it, and nearer his goal than he is now.
    private func goalWaypoint(_ i: Int, pos: [(pos: SIMD2<Float>, walking: Bool)], brains: [BlobBrain?], n: Int) -> SIMD2<Float>? {
        guard let b = brains[i], let g = goal(b) else { return nil }
        let me = pos[i].pos, here = simd_distance(me, g), gap = GameCareGap.value
        var bestSpot: SIMD2<Float>?, bestCost = Float.infinity
        for r: Float in [0.7, 1.1, 1.6, 2.2] {
            for k in 0..<16 {
                let a = Float(k) * (.pi / 8) + (i.isMultiple(of: 2) ? 0.1 : -0.1)
                let c = me + SIMD2(sinf(a), cosf(a)) * r
                let rc = b.resolve(SIMD3(c.x, 0, c.y), b.footprint)
                guard simd_distance(SIMD2(rc.x, rc.z), c) < 0.05 else { continue }
                let d = simd_distance(c, g)
                guard d < here - 0.25 else { continue }
                var ok = true
                for m in 0..<n where m != i { if simd_distance(pos[m].pos, c) < gap * 0.8 { ok = false; break } }
                guard ok, b.legClear(me, c, margin: b.steerMargin) else { continue }
                let cost = d + 0.15 * r
                if cost < bestCost { bestCost = cost; bestSpot = c }
            }
        }
        return bestSpot
    }

    /// Who steps aside: the less busy; equal -> the higher id.
    private static func yields(_ i: Int, _ j: Int, _ a: BlobBrain, _ b: BlobBrain, _ ba: Int, _ bb: Int) -> Bool {
        ba != bb ? ba < bb : i > j
    }

    /// A spot about 1.2-1.5 gaps round `j` that the floor rules leave alone and that is clear of every body; nearest to slot i wins.
    private func detour(_ i: Int, around j: Int, pos: [(pos: SIMD2<Float>, walking: Bool)], brains: [BlobBrain?], n: Int) -> SIMD2<Float>? {
        guard let b = brains[i] else { return nil }
        let from = pos[j].pos, me = pos[i].pos
        let gap = GameCareGap.value
        var bestSpot: SIMD2<Float>?, bestCost = Float.infinity
        for k in 0..<12 {
            let a = Float(k) * (.pi / 6) + (i > j ? 0.13 : -0.13)          // (a different start angle per side: no mirrored choice)
            let dir = SIMD2<Float>(sinf(a), cosf(a))
            for r: Float in [1.15, 1.45] {
                let c = from + dir * (gap * r)
                let rc = b.resolve(SIMD3(c.x, 0, c.y), b.footprint)
                let q = SIMD2(rc.x, rc.z)
                guard simd_distance(q, c) < 0.05 else { continue }
                var ok = true
                for m in 0..<n where m != i { if simd_distance(pos[m].pos, q) < gap * 0.95 { ok = false; break } }
                guard ok else { continue }
                let cost = simd_distance(me, q)
                if cost < bestCost { bestCost = cost; bestSpot = q }
            }
        }
        return bestSpot
    }
}

/// The room's usual centre gap between two Jelbies (MelonController.jellyGap), read without importing the stage into the watchdog.
enum GameCareGap { static var value: Float { MelonController.jellyGap } }
