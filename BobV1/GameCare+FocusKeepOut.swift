//
//  GameCare+FocusKeepOut.swift
//  The close-up keeps the others roaming (W2, 2026-10-22: "the other Jelbies should not freeze or vanish in the close-up"). Instead of holding them, a keep-out
//  WEDGE is laid between the close-up camera and the focused Jelly: nobody paths through it or parks in it. It is applied in the floor rules
//  (`wireWorld`'s resolver), so every walk, route, hop, social spot and run goal already avoids it; a Jelly who is standing in it when the call is made
//  is asked to walk out (`evictFromKeepOut`). Sleepers are left alone.
//

import Foundation
import simd

enum FocusKeepOutTuning {
    /// The wedge reaches this far behind the focused Jelly's spot, and this much wider than the picture's edge (plus the walker's own radius).
    static let back: Float = 0.30, margin: Float = 0.15
    /// Seconds between walk-out requests for a Jelly who stands inside it.
    static let evictEvery: Float = 1.2
}

extension GameCamera {
    /// Others whose centre is within this of a focused spot still light the close-up's shadow box (the far ones are small and soft in the background).
    static let focusShadowReach: Float = 3.2
}

struct FocusKeepOut {
    let centreX: Float        // spot x (a row: the middle of the spots)
    let backZ: Float          // the rearmost spot z - back
    let eyeZ: Float           // the close-up eye's z
    let tanH: Float           // tan(fovY / 2) * aspect: the picture's horizontal half-angle
    let halfSpan: Float       // a row: half the width of the spots; a single: 0

    func halfWidth(at z: Float, radius r: Float) -> Float { halfSpan + tanH * max(eyeZ - z, 0) + r + FocusKeepOutTuning.margin }
    func contains(_ p: SIMD2<Float>, radius r: Float) -> Bool { p.y > backZ && abs(p.x - centreX) < halfWidth(at: p.y, radius: r) }
    /// The nearest point outside: straight back, or straight out to either side at the same z.
    func exit(_ p: SIMD2<Float>, radius r: Float) -> SIMD2<Float> {
        let hw = halfWidth(at: p.y, radius: r) + 0.05
        let back = SIMD2(p.x, backZ - 0.05)
        let left = SIMD2(centreX - hw, p.y), right = SIMD2(centreX + hw, p.y)
        var best = back
        for c in [left, right] where simd_distance(c, p) < simd_distance(best, p) { best = c }
        return best
    }
}

extension FocusGroup {
    /// The wedge for the current close-up at `aspect` (nil when nothing is focused, or when `total` Jellies are all in it: "everyone" needs none).
    func keepOut(aspect: Float, total: Int) -> FocusKeepOut? {
        guard !ids.isEmpty, ids.count < total else { return nil }
        let sp = ids.compactMap { spots[$0] }
        guard let first = sp.first else { return nil }
        var lo = first, hi = first
        for s in sp { lo = simd_min(lo, s); hi = simd_max(hi, s) }
        let pose = sp.count > 1 ? GameCamera.focusPose(aspect: aspect, spots: sp) : GameCamera.focusPose(aspect: aspect, spot: first)
        return FocusKeepOut(centreX: (lo.x + hi.x) / 2, backZ: lo.y - FocusKeepOutTuning.back, eyeZ: pose.eye.z, tanH: tanf(GameCamera.fovY / 2) * aspect, halfSpan: (hi.x - lo.x) / 2)
    }
}

extension GameCare {
    /// The wedge that applies to Jelly `id` now: not to a focused one, not while roaming / leaving, not in a bath or a race.
    func focusKeepOutFor(_ id: Int) -> FocusKeepOut? {
        guard focus.phase == .approaching || focus.phase == .focused, !bath.active, !raceBusy, !focusGroup.ids.contains(id) else { return nil }
        let g = focusGroup
        let a = GameCamera.aspect
        if let c = g.koCache, g.koAspect == a, g.koKey == g.ids { return c }
        let ko = g.keepOut(aspect: a, total: jellies.count)
        g.koCache = ko; g.koAspect = a; g.koKey = g.ids
        return ko
    }

    /// The floor rules' extra step: a point inside the wedge is pushed out of it, unless the Jelly himself already stands in it (he can walk out without a jump).
    func applyKeepOut(_ q: SIMD3<Float>, id: Int, brain: BlobBrain?, radius rr: Float) -> SIMD3<Float> {
        guard let ko = focusKeepOutFor(id) else { return q }
        if let b = brain, ko.contains(b.position, radius: rr) { return q }
        let p2 = SIMD2(q.x, q.z)
        guard ko.contains(p2, radius: rr) else { return q }
        let e = ko.exit(p2, radius: rr)
        return SIMD3(e.x, q.y, e.y)
    }

    /// A Jelly standing in the wedge walks out of it (awake, nothing asked of him).
    func evictFromKeepOut(id: Int, brain: BlobBrain, dt: Float) {
        let g = focusGroup
        guard let ko = focusKeepOutFor(id), ko.contains(brain.position, radius: brain.footprint), !brain.isSleeping, brain.pending == nil, !brain.commanded, brain.job == nil, !brain.held else {
            g.evictT[id] = nil; return
        }
        g.evictT[id, default: 0] -= dt
        if g.evictT[id]! <= 0 {
            g.evictT[id] = FocusKeepOutTuning.evictEvery
            // the nearest way out that the floor allows (he is inside the wedge, so `fixed` is the plain floor here)
            let p = brain.position, r = brain.footprint
            let hw = ko.halfWidth(at: p.y, radius: r) + 0.05
            let cands = [SIMD2(p.x, ko.backZ - 0.05), SIMD2(ko.centreX - hw, p.y), SIMD2(ko.centreX + hw, p.y)].map { brain.fixed($0) }.filter { !ko.contains($0, radius: r) }
            if let go = cands.min(by: { simd_distance($0, p) < simd_distance($1, p) }) { brain.requestNow(.goTo(go)) }
        }
    }
}

extension GameCare {
    /// The Jellies that light the shadow box: all of them in the room camera; in the close-up the focused ones plus any other near a focused spot
    /// (the far ones are small and soft behind, and a wide box would soften the hero's shadow).
    func litActors(_ actors: [JellyActor], camIn: Bool) -> [JellyActor] {
        guard camIn, !focusGroup.ids.isEmpty else { return actors }
        let spots = focusGroup.ids.compactMap { focusGroup.spots[$0] }
        let lit = actors.filter { a in
            if focusGroup.ids.contains(a.id) { return true }
            guard let b = brainFor(a.id) else { return false }
            return spots.contains { simd_distance($0, b.position) < GameCamera.focusShadowReach }
        }
        return lit.isEmpty ? actors : lit
    }
}
