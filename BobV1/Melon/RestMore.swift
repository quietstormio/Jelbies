//
//  RestMore.swift
//  rest-more-r1 (owner 11-24: "they can rest a little more like sit down or lay down sometimes when just watching the room", then "just ever so slightly").
//  A Jelmiko at home now and then settles where he stands: a SIT or a LIE (the existing `.sit` / `.lieDown` poses and their soft get-up), 6...15 s, once
//  every ~2 minutes. Its own slot, like the treat slot: it never writes `last` / `recent` / the special cooldown, so the table's own sit / lie picks keep
//  every pick they had; the emote clocks keep counting during a slot rest (the time comes out of walking, not out of the emotes); a slot rester is
//  invitable like a body on a wander leg (a pair / group move asks him to stop = he gets up first, the move starts when he is up).
//  `-RestMore 0` (DevArgs builds only) = today's behaviour exactly (no random draw, no label, no hook).
//

import Foundation
import simd

nonisolated enum RestMore {
    private static func flag() -> Bool {
        if ProcessInfo.processInfo.environment["RESTMORE_OFF"] != nil { return false }          // (test runs: TEST_RUNNER_RESTMORE_OFF=1 = the base's behaviour for every other suite)
        guard DevArgs.enabled, let v = UserDefaults.standard.string(forKey: "RestMore") else { return true }
        return !["0", "no", "false", "old", "off"].contains(v.lowercased())
    }
    nonisolated(unsafe) static var on: Bool = flag()
    /// Seconds between one slot rest and the next urge (per body), the hold (s), the share of sits (the rest lie down).
    nonisolated(unsafe) static var gap: ClosedRange<Float> = 75...130
    nonisolated(unsafe) static var firstGap: ClosedRange<Float> = 25...100
    /// A rest only starts while the special cooldown still has this many seconds to run (it counts down during the rest: the next pick is due about when he is up).
    static let minCooldown: Float = 1.5
    static let lateAfter: Float = 40
    static let hold: ClosedRange<Float> = 6...15
    static let sitShare: Float = 0.6
    /// Clear of every other body by this much (u) to sit / to lie; a refused try is made again after `retry` s.
    static let sitClear: Float = 1.2, lieClear: Float = 1.8
    static let retry: ClosedRange<Float> = 3...6
    /// The gap is shorter for a grumpy body (tired) and longer in the evening is NOT used: the evening gets the table's own sit weight.
    static let grumpyGapMul: Float = 0.75
}

extension BlobBrain {
    /// A slot rest is on him (sit / lie, not yet finished).
    var restSlotOn: Bool { idleState.restSlot && (idleState.kind == .sit || idleState.kind == .lieDown) }

    /// Another body of the room is in a rest pose, whoever started it (the table's own sit / slump / lie / beanbag, a slot rest, sleep).
    private func restOthersCount() -> Int {
        socialOthers().filter { o in
            guard o !== self, let k = o.idleState.kind else { return false }
            return k == .sit || k == .slump || k == .lieDown || k == .decorSit || k == .sleep || k == .floorNapFlop
        }.count
    }

    /// Per scheduling pick (idleMaybeStart, a quiet moment, cooldown over): the rest urge. True = a rest started.
    func restSlotMaybeStart(_ sim: SoftBody) -> Bool {
        guard RestMore.on, homeRoom, anticsEnabled, autonomy, !held, attached, runMoveDemo == nil, !race.active, !volley.active else { return false }
        guard idleState.kind == nil, social == nil, pending == nil, job == nil, commandedIdle == nil, !commanded, !commandedFlip, !commandedNameHop, !interruptScript, !hurry,
              bubbleLeash == nil, trackPoint == nil, !mix.sess, !meetBusy, socialBook.invite == nil, socialBook.meet == nil, !socialMeetHeld, scriptIsNone else { return false }
        guard idleNight < 0.5, idleDeepNight < 0.1, !bedtimeUnderway else { return false }
        if !idleState.restArmed { idleState.restArmed = true; idleState.restUrge = rand(RestMore.firstGap.lowerBound, RestMore.firstGap.upperBound) }
        guard idleState.restUrge <= 0 else { return false }
        func later(_ s: Float) -> Bool { idleState.restUrge = s; return false }
        // a quiet spot: not under a HUD button, nobody else resting, nobody near
        guard mixStopOK(position), restOthersCount() == 0 else { return later(rand(RestMore.retry.lowerBound, RestMore.retry.upperBound)) }
        let near = socialOthers().filter { $0 !== self }.map { simd_distance($0.position, position) }.min() ?? .infinity
        let lie = rand() >= RestMore.sitShare
        guard near >= (lie ? RestMore.lieClear : RestMore.sitClear) else { return later(rand(RestMore.retry.lowerBound, RestMore.retry.upperBound)) }
        let kind: IdleKind = lie ? .lieDown : .sit
        if lie { guard let spot = lieSpot(from: position, yaw: faceCameraYaw()), simd_distance(spot, position) < 0.05 else { return later(rand(RestMore.retry.lowerBound, RestMore.retry.upperBound)) } }          // (in place only: a lie that would walk to a spot is not a rest)
        guard idleStart(kind, sim) else { return later(rand(RestMore.retry.lowerBound, RestMore.retry.upperBound)) }
        if kind == .lieDown, idleState.windowGo { idleReset(skinnerRef); script = .none; return later(rand(RestMore.retry.lowerBound, RestMore.retry.upperBound)) }
        idleState.restSlot = true
        idleState.hold = rand(RestMore.hold.lowerBound, RestMore.hold.upperBound)
        let g = rand(RestMore.gap.lowerBound, RestMore.gap.upperBound) * (idleMood == .grumpy ? RestMore.grumpyGapMul : 1)
        idleState.restUrge = g
        return true
    }

    /// A pair / group move wants him: get up first (the soft get-up of the sit / lie), the move starts when he is up.
    var restInvitable: Bool {
        guard RestMore.on, restSlotOn, !idleState.yielding, !idleState.windowGo, social == nil, pending == nil, !held else { return false }
        return true
    }
    /// The rester is awake-waking (getting up) or resting: he counts as "on his way to free" for an invite.
    var restWaking: Bool { RestMore.on && restSlotOn }
    func restGetUp() {
        idleState.yielding = true; idleState.yieldT = 0; feet.reset(); stepLive = false
    }
}
