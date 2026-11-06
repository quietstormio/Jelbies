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

    /// Measured (FeatureClipTests, tipped toward each other): two lying bodies' surfaces meet at this centroid distance when neither is tipped, and each body's centroid slides this far toward the side he is tipped onto.
    static let lieTouchCentroid: Float = 1.235, lieTipShift: Float = 0.09

    /// The unit vector of the side a lying body at heading `yaw` with roll side `sign` tips onto (`lieTipToward`: roll +: the -x side goes down).
    static func lieTipDir(yaw: Float, sign: Float) -> SIMD2<Float> { SIMD2(cosf(yaw), -sinf(yaw)) * -sign }

    /// The root distance at which a body lying at `p` (heading `myYaw`, tipped toward `o`) and `o` (where he lies / will lie, at `at`) just touch: the touching centroid distance plus the
    /// slide of both centroids toward each other. A neighbour who is not lying yet is taken as tipping toward me; a sleeper does not tip.
    func lieNeed(_ o: BlobBrain, at: SIMD2<Float>, from p: SIMD2<Float>, myYaw: Float) -> Float {
        var dir = at - p
        let L = simd_length(dir)
        guard L > 1e-3 else { return Self.lieTouchCentroid }
        dir /= L
        let right = SIMD2(cosf(myYaw), -sinf(myYaw))
        let cosMe = abs(simd_dot(right, dir)) > 0.3 / max(L, 1) ? abs(simd_dot(right, dir)) : 0
        var shiftO: Float = 0.7          // (not lying yet: he will tip toward me, about so)
        switch o.idleState.kind {
        case .lieDown?: shiftO = max(0, simd_dot(Self.lieTipDir(yaw: o.idleState.goalYaw, sign: o.idleState.sign), -dir))
        case .flop?: shiftO = max(0, simd_dot(Self.lieTipDir(yaw: o.yaw, sign: o.idleState.sign), -dir))
        case .sleep?: shiftO = 0
        default: break
        }
        return Self.lieTouchCentroid + Self.lieTipShift * (cosMe + shiftO) + 0.01
    }
    func isLying(_ o: BlobBrain) -> Bool {
        switch o.idleState.kind { case .lieDown?, .flop?, .sleep?: return !o.idleState.windowGo; default: return false }
    }

    /// Where a body lying down with heading `myYaw` goes: `here` when it is clear (and no lying neighbour is near enough to snuggle up to), else the spot that is just touching:
    /// walking away only the distance that is missing, or - a lying neighbour within reach but not touching - a few steps toward him. nil = no room.
    func lieSpot(from here: SIMD2<Float>, yaw myYaw: Float) -> SIMD2<Float>? {
        guard LieClearTuning.enabled else { return here }
        let others = socialOthers().filter { $0 !== self && $0.enabled }
        if others.isEmpty { return here }
        // (one who is walking to his own lying spot counts where he will lie)
        let spots = others.map { o -> SIMD2<Float> in (o.idleState.windowGo && Self.walksFirst(o.idleState.kind ?? .wander)) ? o.idleState.target : o.position }
        func need(_ k: Int, _ p: SIMD2<Float>) -> Float { lieNeed(others[k], at: spots[k], from: p, myYaw: myYaw) }
        func clear(_ p: SIMD2<Float>) -> Bool {
            for k in others.indices where simd_distance(spots[k], p) < need(k, p) - 0.006 { return false }
            return true
        }
        func reachableSpot(_ c: SIMD2<Float>, walk: Float) -> Bool {
            guard simd_distance(c, here) <= walk, clear(c) else { return false }
            return simd_distance(fixed(c), c) < 0.05 && legClear(here, c, margin: steerMargin)
        }
        guard let k = others.indices.min(by: { simd_distance(spots[$0], here) < simd_distance(spots[$1], here) }) else { return here }
        let d0 = simd_distance(spots[k], here)
        let out = d0 > 1e-3 ? (here - spots[k]) / d0 : SIMD2<Float>(0, 1)
        // exactly touching, on the line from the nearest one
        func touchSpot(_ extra: Float) -> SIMD2<Float> { spots[k] + out * (need(k, spots[k] + out * 1.4) + extra) }
        if clear(here) {
            // a lying neighbour not far off: snuggle up to him
            if isLying(others[k]), d0 > need(k, here) + 0.04, d0 < 2.4 {
                let c = touchSpot(0)
                if reachableSpot(c, walk: 1.5) { return c }
            }
            return here
        }
        for extra: Float in [0, 0.04, 0.1] {
            let c = touchSpot(extra)
            if reachableSpot(c, walk: LieClearTuning.maxWalk) { return c }
        }
        var best: (p: SIMD2<Float>, d: Float)?
        for r: Float in [0.15, 0.3, 0.45, 0.6, 0.8, 1.0] where r <= LieClearTuning.maxWalk {
            for i in 0..<16 {
                let a = Float(i) * (.pi / 8)
                let c = here + SIMD2(sinf(a), cosf(a)) * r
                guard reachableSpot(c, walk: LieClearTuning.maxWalk) else { continue }
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
    static func walksFirst(_ k: IdleKind) -> Bool { k == .window || k == .lieDown || k == .flop || k == .stargazing }

    /// After `idleBegin`: walk to `spot` (a lying body's room) before the move starts; no walk when he is already there.
    func lieWalk(to spot: SIMD2<Float>, from here: SIMD2<Float>) {
        guard simd_distance(spot, here) > 0.02 else { return }
        idleState.windowGo = true
        idleState.target = spot
        script = .walk(target: spot, then: .none); activity = .walking
    }

    // MARK: the snuggle: ContactSettle on the lying pair

    /// While he lies next to a lying neighbour: the settle controller on the DRAWN skin gap (ContactProfile.swift). During the plop (phase 1) it only pushes the bodies out of each other;
    /// lying (phase 2) it eases them until the skins just touch (band -0.5 ... +0.5 cm). The older one stays, the later one scoots in (or away).
    func snuggleTick(_ sim: SoftBody, _ dt: Float) {
        guard LieClearTuning.enabled, idleState.kind == .lieDown, !idleState.windowGo, idleState.phase >= 1, idleState.phase <= 2 else { return }
        var best: (o: BlobBrain, g: Float)?
        for o in socialOthers() where o !== self && o.enabled && o.idleState.kind == .lieDown && !o.idleState.windowGo && o.idleState.phase >= 1 && o.idleState.phase <= 2 {
            guard let g = ContactField.gap(steerID, o.steerID, features: true), g < 0.7 else { continue }
            if best == nil || g < best!.g { best = (o, g) }
        }
        guard let (o, _) = best else { return }
        let older = o.idleState.t > idleState.t + 0.05 || (abs(o.idleState.t - idleState.t) <= 0.05 && o.steerID < steerID)
        ContactSettle.step(self, o, target: 0, anchoredA: !older, anchoredB: older, onlySeparate: idleState.phase == 1, features: true)          // (a folded wing between the backs is touched, never sunk into)
    }
}
