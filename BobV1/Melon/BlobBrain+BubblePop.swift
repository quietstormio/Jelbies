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

// MARK: the hop chain (round 3, 2026-11-11: "they need to be constantly hopping to pop bubbles")

extension BlobBrain {
    /// The plain hop's centroid apex (Locomotion `hopApex`); a chained hop may set its own, the wand puts this back when no chain hop runs.
    static let bubbleDefaultApex: Float = 0.10
    /// The running hop is on the ground in its landing (the gait's land phase): the next hop of a chain may leave from it.
    var bubbleInLanding: Bool {
        if case .hopPlay = script, gait.phase == .land { return true }
        return false
    }
    /// While a chain of hops carries him the brain's root follows the body (as the race chain does, `raceChainRoot`): a root left at the first take-off skews the skin's jiggle and opens the foot join.
    func bubbleChainFollowRoot(_ sim: SoftBody) {
        guard case .hopPlay = script else { return }
        let c = sim.centroid()
        px = c.x; pz = c.z
    }
    /// No hop of a chain runs: the gait's apex is the plain hop's again (never while a hop of any kind is running, never in a race).
    func bubbleChainRestoreApex() {
        guard !race.active, gait.hopApex != Self.bubbleDefaultApex else { return }
        if case .hopPlay = script { return }
        gait.hopApex = Self.bubbleDefaultApex
    }
    /// One hop of the chain, `length` u toward floor point `p` (0 = on the spot), with its own apex. From a landing it leaves from the landing itself (the gait's chained re-hop: a short crouch of
    /// 0.4 x 0.13 s, the rebound of the landing); from standing it is the leap's start (the full crouch). The heading turns at most `maxTurn` away from the way he faces (the gait eases the yaw
    /// through the crouch and the air: no snap); a bubble further round gets a short turn hop first. False: not now, or no room (outside the floor, a friend or a piece in the way).
    @discardableResult
    func bubbleChainHop(_ sim: SoftBody, toward p: SIMD2<Float>, length: Float, apex: Float?, maxTurn: Float) -> Bool {
        let fromLand = bubbleInLanding
        guard fromLand || bubbleCanHop else { return false }
        let c = sim.centroid(), here = SIMD2(c.x, c.z)
        let cur = fromLand ? gait.facingYaw : yaw
        let want = atan2f(p.x - here.x, p.y - here.y)
        let err = wrapAngle(want - cur)
        let heading = length > 0.001 ? cur + max(-maxTurn, min(maxTurn, err)) : cur
        let len = max(length, 0.0001)
        let ahead = here + SIMD2(sinf(heading), cosf(heading)) * len
        let rv = resolve(SIMD3(ahead.x, 0, ahead.y), footprint)
        let t = SIMD2(rv.x, rv.z)
        if len > 0.01 {
            guard simd_distance(t, ahead) < 0.08, peerFree(t), legClear(here, t, margin: steerMargin) else { return false }
        }
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.7)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        gait.facingYaw = heading
        gait.home = t          // (a chained landing re-hops toward `home`: it is here, so the gait's own re-hop has nowhere to go)
        gait.hopApex = apex ?? Self.bubbleDefaultApex
        poseW = 0
        gait.hop(sim, to: t, reduceMotion: amplitude < 0.7, chained: fromLand)
        script = .hopPlay; activity = .playing
        return true
    }
}
