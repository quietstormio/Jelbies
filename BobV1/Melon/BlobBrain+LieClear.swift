//
//  BlobBrain+LieClear.swift
//  Lying down next to a friend (2026-11-02, the user's phone photo: Teddy and Pearl lay side by side, tipped over, and sank a third into each other).
//  Cause: the lie-down (and the flop) flattens the body (squash 0.62 / 0.64, volume kept) so it is ~1.27 x as wide on the floor, but the room only keeps standing bodies
//  `MelonStage.jellyGap` (1.4) apart - and the spring under it (`keepApart`) lets two bodies be pressed down to 0.78 of that. Two standing Jelbies 1.1 apart that both lie down
//  (or one lies next to one who already does) overlap by a third. A sleeper never had it (the pile spaces its row by `SleepTuning.pileSpacing`).
//  Fix at the placement: before he lies down he checks the room his lying body needs; too close to a neighbour (who may lie down as well: a body that is not walking is taken as
//  lying), he first walks to the nearest spot where the two lying bodies just touch (never closer), or - no such spot - stays up. The bodies are never pushed apart afterwards,
//  and the contact squish / boop (`contactTick`) and every social stay as they were.
//

import Foundation
import simd

enum LieClearTuning {
    /// false = the old placement (the captures' / tests' "before").
    nonisolated(unsafe) static var enabled = true
    /// The squash of the lie-down / flop at its fullest (BlobBrain+Lively lieDownPose 0.38, BlobBrain+Antics flop 0.36) -> the floor width of the body is 1 / sqrt(squash) as wide.
    static let squashLie: Float = 0.62
    /// Touching, a hair apart: the lying bodies' centre distance as a fraction of the sum of their half widths (1 = the surfaces just meet).
    static let touch: Float = 1.0
    /// How far he may walk to find the spot (u).
    static let maxWalk: Float = 1.1
}

extension BlobBrain {
    /// The width of a standing body on the floor (u).
    static var standWidth: Float { Float(2 * BobForm.halfW) }
    /// How much wider than standing the body is when lying flat.
    static var lieSpreadMax: Float { 1 / LieClearTuning.squashLie.squareRoot() }
    /// The centre distance two lying bodies need to just touch.
    static var lieTouch: Float { standWidth * lieSpreadMax * LieClearTuning.touch }

    /// The centre distance a lying body keeps from `o`: another lying body (lie-down, flop, a sleeper) - the two just touch; one who stands or walks - a flat body beside a standing one.
    func lieNeed(_ o: BlobBrain) -> Float {
        let lying: Bool
        switch o.idleState.kind { case .lieDown?, .flop?, .sleep?: lying = true; default: lying = false }
        if lying { return Self.lieTouch }
        let standing = Self.standWidth * (Self.lieSpreadMax + 1) / 2 * LieClearTuning.touch
        return o.activity == .walking || o.activity == .coming ? max(standing, peerGap * 0.97) : standing
    }

    /// The nearest spot to `here` (a ring of candidates) where a body lying down touches no other Jelbie's body; `here` itself when it is clear, nil when there is none.
    func lieSpot(from here: SIMD2<Float>) -> SIMD2<Float>? {
        guard LieClearTuning.enabled else { return here }
        let others = socialOthers().filter { $0 !== self && $0.enabled }
        if others.isEmpty { return here }
        let needs = others.map { lieNeed($0) }
        // (one who is walking to his own lying spot counts where he will lie)
        let spots = others.map { o -> SIMD2<Float> in (o.idleState.windowGo && Self.walksFirst(o.idleState.kind ?? .wander)) ? o.idleState.target : o.position }
        func clear(_ p: SIMD2<Float>) -> Bool {
            for k in others.indices where simd_distance(spots[k], p) < needs[k] - 0.01 { return false }
            return true
        }
        if clear(here) { return here }
        // straight away from the one who is nearest: exactly the distance that is missing (no overshoot: lying bodies just touch)
        if let k = others.indices.min(by: { simd_distance(spots[$0], here) < simd_distance(spots[$1], here) }) {
            var away = here - spots[k]
            let L = simd_length(away)
            away = L > 1e-3 ? away / L : SIMD2(0, 1)
            for extra: Float in [0.01, 0.06, 0.12] {
                let c = spots[k] + away * (needs[k] + extra)
                guard simd_distance(c, here) <= LieClearTuning.maxWalk, clear(c) else { continue }
                let q = fixed(c)
                if simd_distance(q, c) < 0.05, legClear(here, c, margin: steerMargin) { return c }
            }
        }
        var best: (p: SIMD2<Float>, d: Float)?
        for r: Float in [0.15, 0.3, 0.45, 0.6, 0.8, 1.0] where r <= LieClearTuning.maxWalk {
            for k in 0..<16 {
                let a = Float(k) * (.pi / 8)
                let c = here + SIMD2(sinf(a), cosf(a)) * r
                guard clear(c) else { continue }
                let q = fixed(c)
                guard simd_distance(q, c) < 0.05, legClear(here, c, margin: steerMargin) else { continue }
                if best == nil || r < best!.d { best = (c, r) }
            }
            if best != nil { break }
        }
        return best?.p
    }

    /// Lying next to a friend he tips onto the side toward him (cheek to cheek): `idleState.sign` (the roll side of the lie-down / flop) for a body that lies with heading `lieYaw` at `spot`.
    /// The room above (`lieTouch`) is for the two tipped INTO each other, so this is the closest they come; nobody near = his own random side stays.
    func lieTipToward(_ spot: SIMD2<Float>, lieYaw: Float) {
        guard LieClearTuning.enabled else { return }
        guard let o = socialOthers().filter({ $0 !== self && $0.enabled && $0.activity != .walking }).min(by: { simd_distance($0.position, spot) < simd_distance($1.position, spot) }),
              simd_distance(o.position, spot) < Self.lieTouch * 1.6 else { return }
        let right = SIMD2(cosf(lieYaw), -sinf(lieYaw))
        let side = simd_dot(o.position - spot, right)
        guard abs(side) > 0.3 else { return }          // (he is in front of / behind me: no side is nearer)
        idleState.sign = side > 0 ? -1 : 1          // (roll +: the body's -x side goes down)
    }

    /// The moves that first walk to a spot (the window antic, the lie-down, the flop): `windowGo` while he walks there, then the idle takes over.
    static func walksFirst(_ k: IdleKind) -> Bool { k == .window || k == .lieDown || k == .flop }

    /// After `idleBegin`: walk to `spot` (a lying body's room) before the move starts; no walk when he is already there.
    func lieWalk(to spot: SIMD2<Float>, from here: SIMD2<Float>) {
        guard simd_distance(spot, here) > 0.02 else { return }
        idleState.windowGo = true
        idleState.target = spot
        script = .walk(target: spot, then: .none); activity = .walking
    }
}
