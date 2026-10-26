//
//  BlobBrain+Contact.swift
//  Soft meetings (2026-10-26): Jelbies that walk into or past each other used to be pushed apart hard. Now
//    - the room's peer separation is a spring (MelonStage.keepApart: a continuous, partial push, no pop),
//    - an autonomous walker whose straight leg would pass a Jelly closer than the gap curves round him EARLY (a side-step waypoint on the side away from him,
//      his right if he is dead ahead, so two walkers meeting head on pass each other),
//    - bodies that press touch with a small squish and a wobble (a jelly kick, a faint lean away), once per contact, never a buzz.
//  All of it rides on existing mechanisms (the route waypoints, the jelly kick, the social overlay): the walk, the feet and the arms are untouched.
//

import Foundation
import simd

enum ContactTuning {
    nonisolated(unsafe) static var lookAhead = true
    static let lookDistance: Float = 2.4          // how far ahead along the leg a Jelly counts
    static let contactFrac: Float = 0.97          // closer than this fraction of the gap = the bodies touch
    static let cooldown: Float = 1.6
}

extension BlobBrain {
    /// A waypoint beside the leg root -> target that clears a Jelly in the way by the gap, or nil (nobody in the way, or no free spot).
    func lookAheadSidestep(_ root: SIMD2<Float>, _ target: SIMD2<Float>) -> SIMD2<Float>? {
        guard ContactTuning.lookAhead, job == nil, !commanded, pending == nil else { return nil }
        let d = target - root, L = simd_length(d)
        guard L > 1.0 else { return nil }
        let dir = d / L, right = SIMD2(dir.y, -dir.x)
        let clear = peerGap * 0.97
        var hit: (t: Float, side: Float, pos: SIMD2<Float>)?
        for p in steerPeers() {
            if simd_distance(p.pos, target) < clear * 1.3 { continue }          // (he is where I am going: a social walk-up, a meal)
            let rel = p.pos - root
            let t = simd_dot(rel, dir), side = simd_dot(rel, right)
            guard t > 0.15, t < min(L, ContactTuning.lookDistance), abs(side) < clear * 0.85 else { continue }
            if hit == nil || t < hit!.t { hit = (t, side, p.pos) }
        }
        guard let h = hit else { return nil }
        let sgn: Float = h.side > 0.12 ? -1 : (h.side < -0.12 ? 1 : 1)          // away from him; dead ahead: my right
        for k: Float in [1.0, 1.15, 1.35] {
            let w = h.pos + right * (sgn * clear * k)
            guard simd_distance(fixed(w), w) < 0.03, intrusion(w, margin: steerMargin) < 0.01, legClear(root, w, margin: steerMargin) else { continue }
            return w
        }
        return nil
    }

    /// A soft meeting: the bodies press, a small squish + wobble (once per contact, with a cooldown), nothing while a social drives the pair.
    func contactTick(_ dt: Float) {
        socialBook.contactCool -= dt
        guard social == nil, attached, !held else { return }
        for o in socialOthers() where o !== self {
            let d = simd_distance(o.position, position)
            let prev = socialBook.contactPrev[o.steerID] ?? d
            socialBook.contactPrev[o.steerID] = d
            guard o.social == nil, socialBook.contactCool <= 0, d < peerGap * ContactTuning.contactFrac, d < prev - 0.002 else { continue }          // (closing in)
            socialBook.contactCool = ContactTuning.cooldown
            let press = min(1, (peerGap - d) / (peerGap * 0.25) + 0.4)
            jellyKick = max(jellyKick, 0.9 + 0.9 * press)
            AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.25)
        }
    }
}
