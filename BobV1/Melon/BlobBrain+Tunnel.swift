//
//  BlobBrain+Tunnel.swift
//  The play tunnel (2026-10-27): he walks to one mouth, walks THROUGH (the tunnel is soft to him for the trip: his own walk, his own steps), squashes a little inside
//  (a touch lower, leaning forward, the tunnel rippling round him) and comes out of the other end. A second Jelbie follows once the first is well through (follow the
//  leader: `DecorField.available`), always from the same mouth, so two never meet inside. Run as the `.decorPeek` behaviour of the piece (stage 30).
//

import Foundation
import simd

extension BlobBrain {
    /// The mouth he walks up to: the one the leader went in by, else the nearer free one (0.8 outside the end ring).
    func tunnelEntry(_ f: DecorFoot, from here: SIMD2<Float>) -> SIMD2<Float>? {
        let c = DecorField.shared.position(f)
        let ax = f.turned(SIMD2(1, 0))
        let reach = f.kind.spec.half.x + 0.8
        var sides: [Float] = [-1, 1]
        if let d = DecorField.shared.tunnelDir[f.uid] { sides = [-d] }          // (he enters where the leader did)
        else if simd_dot(here - c, ax) > 0 { sides = [1, -1] }
        for s in sides {
            let p = c + ax * (s * reach)
            let q = fixed(p)
            if simd_distance(p, q) < 0.08, peerFree(q) { return q }
        }
        // no free mouth (a corner, the front edge of the floor): he stands at its side and peeks in instead
        return edgeStand(f, from: here, gap: max(0.8, footprint * f.spec.reach + 0.06))
    }
    /// Is he at one of the two mouths (as against beside the tunnel, peeking)?
    func tunnelAtMouth(_ f: DecorFoot) -> Bool {
        let c = DecorField.shared.position(f)
        let ax = f.turned(SIMD2(1, 0))
        let reach = f.kind.spec.half.x + 0.8
        return [Float(-1), 1].contains { simd_distance(position, c + ax * ($0 * reach)) < 0.9 }
    }

    /// He has set out for the tunnel (`decorStart` committed): the first one fixes the direction (the one behind goes in by the same mouth, never meeting him inside),
    /// and he counts as not through yet until he is.
    func tunnelCommit(_ f: DecorFoot, stand: SIMD2<Float>) {
        let c = DecorField.shared.position(f)
        let reach = f.kind.spec.half.x + 0.8, ax = f.turned(SIMD2(1, 0))
        guard [Float(-1), 1].contains(where: { simd_distance(stand, c + ax * ($0 * reach)) < 0.9 }) else { return }          // (a peek beside it: not a trip through)
        let side: Float = simd_dot(stand - c, ax) < 0 ? -1 : 1
        if DecorField.shared.tunnelDir[f.uid] == nil { DecorField.shared.tunnelDir[f.uid] = -side }
        DecorField.shared.progress[f.uid, default: [:]][steerID] = 0
    }

    /// Arrived at the mouth: the walk through begins.
    func tunnelBegin(_ f: DecorFoot) {
        let c = DecorField.shared.position(f)
        let ax = f.turned(SIMD2(1, 0))
        let dirSign: Float = simd_dot(c - position, ax) >= 0 ? 1 : -1
        let out = c + ax * (dirSign * (f.kind.spec.half.x + 0.8))
        DecorField.shared.tunnelDir[f.uid] = dirSign
        DecorField.shared.progress[f.uid, default: [:]][steerID] = 0
        decorIgnore = f.uid
        idleState.slideStage = 30; idleState.decorGo = true; idleState.target = out
        idleState.slideS = 0
        route = []; scriptT = 0; stuckT = 0; bestDist = .infinity; steerStall = 0
        script = .walk(target: out, then: .none); activity = .walking
    }

    /// Out the other end: a little joy and done.
    func tunnelEnd(_ skinner: Skinner) {
        idleState.slideStage = 0
        face(.excited, hold: 1.0)
        jellyKick = max(jellyKick, 1.2)
        AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.5, rate: 1.3)
        idleFinish(skinner)
    }

    /// Every step after the walk's pose is set, before it is applied: the squash inside the tunnel, the ripple, his progress (for the one behind him).
    func toyPoseTick() {
        guard idleState.kind == .decorPeek, idleState.slideStage == 30, idleState.decorUID >= 0, let f = DecorField.shared.foot(idleState.decorUID), f.kind == .playtunnel else { return }
        let c = DecorField.shared.position(f)
        let ax = f.turned(SIMD2(1, 0))
        let dirSign = DecorField.shared.tunnelDir[f.uid] ?? 1
        let half = f.kind.spec.half.x
        let u = simd_dot(position - c, ax) * dirSign / half          // -1 at the entry ring ... +1 at the exit ring
        DecorField.shared.progress[f.uid, default: [:]][steerID] = max(0, min(1, (u + 1) / 2))
        let w = 1 - smooth01((abs(u) - 0.85) / 0.5)
        squash *= 1 - 0.15 * w
        pitch += 0.12 * w
        roll += 0.03 * w * sinf(idleState.slideS * 9)
        idleState.slideS += runDt * w
        DecorField.shared.peek(f.uid, w)
        if w > 0.5, !idleState.decorBooped { idleState.decorBooped = true; DecorField.shared.kick(f.uid, 0.7); AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.5, rate: 1.3) }
    }
}
