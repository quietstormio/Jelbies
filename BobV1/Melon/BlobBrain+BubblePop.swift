//
//  BlobBrain+BubblePop.swift
//  The bubble wand's pop moves: thin starters over hops that already exist (no new gait, stubby arms and attached feet as ever). The wand (Toys/BubbleWand.swift) decides which one and when.
//    header  the on-the-spot header hop (BlobBrain+PlayToss)        leap   the travelling hop (`startHop(distance:)`) from 0.35...0.9 u away
//    bounce  `.bounce` under a hovering bubble                     flap   `.flapHop` (winged only)           skip   `.skipHop` into a low bubble
//

import Foundation
import simd

enum BubblePopMove: String, CaseIterable, Sendable {
    case header, leap, bounce, flap, skip
}

extension BlobBrain {
    /// A hop of any wand kind is running (or about to): the retry check of the wand (`tossBusy` only knew the header).
    var bubbleHopBusy: Bool {
        if let k = idleState.kind {
            switch k { case .tossHeader, .tossBump, .bounce, .skipHop, .flapHop, .joy: return true; default: break }
        }
        if case .hopPlay = script { return true }
        return false
    }
    /// He can start a pop move now.
    var bubbleCanHop: Bool { idleState.kind == nil && scriptIsNone && pending == nil && !feet.active && !bubbleHopBusy }

    /// The leap: the travelling hop `distance` u along the way he faces (the wand turns him toward the bubble first).
    @discardableResult
    func bubbleLeap(_ sim: SoftBody, distance: Float) -> Bool {
        guard bubbleCanHop else { return false }
        face(.excited, hold: 1.2)
        startHop(sim, distance: distance)
        return true
    }
    /// A few hops on the spot under the bubble; the wand pops it on the hop whose crown reaches it.
    @discardableResult
    func bubbleBounce(_ sim: SoftBody) -> Bool {
        guard bubbleCanHop else { return false }
        face(.excited, hold: 1.6)
        guard idleStart(.bounce, sim) else { return false }
        idleState.reps = BubbleTuning.bounceReps          // (hops: one for the target, the rest for another bubble in reach; 3 before 2026-11-11)
        return true
    }
    /// The winged species' flap-hop (false for everybody else, folded wings, or no room ahead).
    @discardableResult
    func bubbleFlap(_ sim: SoftBody) -> Bool {
        guard bubbleCanHop, flapHopAllowed else { return false }
        face(.excited, hold: 1.6)
        return idleStart(.flapHop, sim)
    }
    /// The skip: two hops ahead (0.7 u) along the way he faces, into a low bubble.
    @discardableResult
    func bubbleSkip(_ sim: SoftBody) -> Bool {
        guard bubbleCanHop else { return false }
        face(.excited, hold: 1.4)
        return idleStart(.skipHop, sim)
    }
    /// Whether a skip (two hops, 0.7 u along the way he faces) has the room, and which check says no (tests / diagnosis): "ok", "bounds", "leg", "peer".
    func bubbleSkipProbe() -> String {
        let here = position, dir = SIMD2(sinf(yaw), cosf(yaw))
        let want = here + dir * 0.7
        let goal = fixed(want)
        if simd_distance(goal, want) >= 0.12 { return "bounds" }
        if !legClear(here, goal, margin: steerMargin) { return "leg" }
        if !peerFree(goal) { return "peer" }
        return "ok"
    }
    /// Whether the flap-hop will start now (the gate of `flapHopBegin`, without starting it): "ok", "notWinged", "folded", "notAllowed", "bounds" (no floor for the drift ahead), "peer", "leg".
    func bubbleFlapProbe() -> String {
        guard feature == .wings else { return "notWinged" }
        guard !wingsFolded else { return "folded" }
        guard flapHopAllowed else { return "notAllowed" }
        let here = position, goal = here + SIMD2(sinf(yaw), cosf(yaw)) * FeatureSpec.shared.hop.drift
        let rv = resolve(SIMD3(goal.x, 0, goal.y), footprint)
        guard simd_distance(SIMD2(rv.x, rv.z), goal) < 0.05 else { return "bounds" }
        guard peerFree(SIMD2(rv.x, rv.z)) else { return "peer" }
        guard legClear(here, SIMD2(rv.x, rv.z), margin: steerMargin) else { return "leg" }
        return "ok"
    }
    /// Which hop of a bounce / skip is running (0-based), for the lighter beat of the second and third pop.
    var bubbleHopIndex: Int { idleState.hop }
    /// The yaw from here to a floor point (for the facing check before a travelling move).
    func bubbleYawError(to p: SIMD2<Float>) -> Float { abs(wrapAngle(yawTo(p) - yaw)) }
}
