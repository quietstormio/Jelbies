//
//  BlobBrain+Flourish.swift
//  Mid-walk flourishes and the jump for joy (user 2026-10-20: "They literally walk and then stop then walk again. Maybe they do something else ... run more, do a few jumps,
//  hopscotch, something. They're too bland."). The walk gait itself is untouched: a flourish is inserted BETWEEN steps of an ordinary wander leg (feet planted, nothing
//  stepping) and the walk resumes toward the same goal afterwards.
//    skipHop    two low chained hops along the way (the scoot's hop)                          weight 3    cooldown 12 s
//    hopscotch  three hops of 0.34 u, alternating 0.12 u to the side                           weight 1.5  cooldown 25 s
//    legSpin    one quick turn on the spot (the tail-chase spin) and on                        weight 1    cooldown 20 s
//    trot       a bounce-trot: the run blend at 0.4 for 2 s, no stop                           weight 2    cooldown 15 s
//    stopLook   stops and looks at a friend, a toy or the window for 1...1.5 s (a curious tilt) weight 2   cooldown 10 s
//  One roll per leg (legs of 1.5 u or more, more than 0.6 u from the goal): 0.45 okay, 0.6 happy, 0.15 grumpy, none at night. All but the look are fast moves for the
//  cap of two. JOY is the jump for joy: one 0.12 u hop with the jacks' arms up, on an event (a social ended, a meal finished, a need fixed, drops earned) and as a happy special.
//

import Foundation
import simd

struct LegState {
    var from = SIMD2<Float>.zero
    var total: Float = 0
    var trigger: Float = 0
    var wants = false
    var rolled = true
    var resuming = false
    /// Waiting at the step boundaries for a friend to finish the same move (counted once in `blocked`).
    var waiting = false
    /// The flourish chosen for this leg (the leg is long enough for it), and the distance it needs ahead.
    var kind: IdleKind?
    // diagnostics (tests)
    var legs = 0, wanted = 0, fired = 0, noTrigger = 0, blocked = 0
}

enum FlourishTuning {
    /// Tests: switch the mid-walk flourishes off to find which behaviour a measurement belongs to.
    nonisolated(unsafe) static var enabled = true
    static func chance(_ m: IdleMood, night: Float) -> Float {
        if night > 0.5 { return 0 }
        switch m { case .okay: return 0.45; case .happy: return 0.6; case .grumpy: return 0.15 }
    }
    static let weights: [(IdleKind, Float)] = [(.skipHop, 3), (.hopscotch, 1.5), (.legSpin, 1), (.trot, 2), (.stopLook, 2), (.rollTrip, 1.2)]
    static let minLeg: Float = 1.5, minRemaining: Float = 0.6
    /// Distance along the leg each flourish needs (the hop distance, a trot's two seconds).
    static func need(_ k: IdleKind) -> Float {
        switch k { case .skipHop: return 1.2; case .hopscotch: return 1.7; case .trot: return 1.9; case .rollTrip: return 1.5; case .legSpin: return 0.8; default: return 0.8 }
    }
}

extension BlobBrain {
    static let flourishKinds: Set<IdleKind> = [.skipHop, .hopscotch, .legSpin, .trot, .stopLook, .joy, .giggle, .startle, .rollTrip]
    /// The flourishes that are rolled mid-walk (the reaction moves .giggle / .startle and .joy are started by their own triggers).
    static let walkFlourishes: [IdleKind] = [.skipHop, .hopscotch, .legSpin, .trot, .stopLook]

    // MARK: the leg roll

    /// A new wander leg starts: decide once whether it gets a flourish and where along the leg.
    func flourishLegStart(target: SIMD2<Float>) {
        if leg.resuming { leg.resuming = false; return }
        if leg.wants && !leg.rolled { leg.noTrigger += 1 }          // (the last leg ended before its flourish)
        leg.from = position
        leg.total = simd_distance(position, target)
        leg.rolled = true
        leg.wants = false
        leg.waiting = false
        leg.kind = nil
        guard FlourishTuning.enabled, anticsEnabled, job == nil, !commanded, pending == nil, idleState.kind == nil, !held, !race.active, leg.total >= FlourishTuning.minLeg else { return }
        leg.legs += 1
        let p = FlourishTuning.chance(idleMood, night: idleNight)
        // (the roll consumes the brain's stream only on legs that qualify)
        guard rand() < p else { return }
        leg.wanted += 1
        // the kind is chosen now, from what this leg is long enough for and what is off cooldown (variety: what he has done least first)
        var w = FlourishTuning.weights.filter { kindCool[$0.0] == nil && leg.total - 0.3 >= FlourishTuning.need($0.0) }
        if idleMood == .grumpy { w.removeAll { $0.0 == .hopscotch || $0.0 == .skipHop || $0.0 == .rollTrip } }
        for i in w.indices { w[i].1 /= 1 + 0.7 * Float(idleState.counts[w[i].0] ?? 0) }
        guard !w.isEmpty else { return }
        let total = w.reduce(0) { $0 + $1.1 }
        var x = rand() * total
        var kind = w[0].0
        for (k, wt) in w { if x < wt { kind = k; break }; x -= wt }
        leg.kind = kind
        leg.wants = true; leg.rolled = false
        leg.trigger = rand(0.25, max(0.3, leg.total - FlourishTuning.need(kind)))
    }

    /// At a step boundary of a plain wander leg: start the leg's flourish when the time comes. True = the script was changed (the walk step must not start now).
    func flourishMaybe(_ sim: SoftBody, _ skinner: Skinner, target: SIMD2<Float>) -> Bool {
        guard leg.wants, !leg.rolled, anticsEnabled else { return false }
        guard job == nil, !commanded, pending == nil, idleState.kind == nil, !held, !race.active, social == nil, autonomy, !walkFinal, !isNapping else { leg.blocked += 1; return false }          // (a detour around a prop is fine: the walk re-plans after the flourish; the hops check their own way is clear)
        let remaining = simd_distance(position, target)
        if remaining <= FlourishTuning.minRemaining { leg.rolled = true; return false }
        guard simd_distance(position, leg.from) >= leg.trigger else { return false }
        if let k = leg.kind, othersDoing(k) { if !leg.waiting { leg.waiting = true; leg.blocked += 1 }; return false }          // (a friend is doing just that: try again at the next step, once he is done)
        leg.rolled = true
        guard let kind = leg.kind, kindCool[kind] == nil, !(Self.fastKinds.contains(kind) && fastOthers() >= 2), remaining >= FlourishTuning.need(kind) - 0.2 else { leg.blocked += 1; return false }
        if flourishStart(kind, resume: target, sim, skinner) { leg.fired += 1; return true }
        return false
    }

    /// Start `kind` in the middle of a walk toward `resume` (nil = from standing; the move then just ends).
    func flourishStart(_ kind: IdleKind, resume: SIMD2<Float>?, _ sim: SoftBody, _ skinner: Skinner?) -> Bool {
        let here = position
        let dir: SIMD2<Float> = {
            if let r = resume { let d = r - here; let l = simd_length(d); if l > 1e-3 { return d / l } }
            return SIMD2(sinf(yaw), cosf(yaw))
        }()
        switch kind {
        case .trot:
            idleBegin(.trot)
            idleState.resume = nil
            idleState.target = resume ?? here + dir * 2.2
            if resume == nil { script = .walk(target: idleState.target, then: .none); activity = .walking }
        case .skipHop, .hopscotch:
            let n = kind == .skipHop ? 2 : 3
            let dist: Float = kind == .skipHop ? 0.7 : 1.1
            let goal = fixed(here + dir * dist)
            guard simd_distance(goal, here + dir * dist) < 0.12, legClear(here, goal, margin: steerMargin), peerFree(goal) else { return false }
            idleBegin(kind)
            idleState.resume = resume
            idleState.target = here + dir * dist
            idleState.baseYaw = atan2f(dir.x, dir.y)
            idleState.reps = n; idleState.hop = 0; idleState.landT = 0
            script = .idle; activity = .playing
            idleState.phase = 1; idleState.phaseT = 0
            idleScootHop(sim)
        case .rollTrip:
            let remaining = resume.map { simd_distance($0, here) } ?? 2.5
            var d = min(2.5, max(1.0, remaining - 0.4))
            idleBegin(.rollTrip)
            idleState.resume = resume
            var ok = false
            while d >= 1.0 {
                let tgt = here + dir * d, rv = resolve(SIMD3(tgt.x, 0, tgt.y), footprint)
                if simd_length(SIMD2(rv.x, rv.z) - tgt) < 0.05, legClear(here, tgt, margin: steerMargin), peerFree(tgt) { ok = true; break }
                d -= 0.3
            }
            guard ok else { idleState.kind = nil; return false }
            sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false; walkFinal = false; route = []
            gait.wander = false; gait.rollTravel = d
            gait.facingYaw = atan2f(dir.x, dir.y) - .pi / 2          // (the roll goes sideways to his facing: face across the leg so it rolls ALONG it)
            gait.home = here
            poseW = 0; poseOn = false
            gait.roll(sim, toward: dir, reduceMotion: amplitude < 0.7)
            script = .rollPlay; activity = .playing
            AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.6)
        case .legSpin:
            idleBegin(.legSpin)
            idleState.resume = resume
            startSpin(sim: sim)
            AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.4)
        case .stopLook:
            idleBegin(.stopLook)
            idleState.resume = resume
            idleState.baseYaw = atan2f(dir.x, dir.y)
            idleState.hold = rand(1.0, 1.5)
            idleState.goalYaw = clampedLook(lookAimYaw() ?? (yaw + idleState.sign * 0.9))
            if abs(wrapAngle(idleState.goalYaw - yaw)) < 0.25 { idleState.goalYaw = yaw + idleState.sign * 0.9 }
            script = .idle; activity = .lookingAround
            face(.curious, hold: 1.0 + idleState.hold + 0.8)
        default: return false
        }
        kindCooldownStart(kind)
        switch kind { case .skipHop, .hopscotch: postEvent(.joyJump); case .trot: postEvent(.zoomies); default: break }          // (a skip is a happy hop; a trot a small dash: the others may notice)
        return true
    }

    /// A look turns at most this far from where he faces (a bigger turn on the spot lifts a foot higher than the cap allows).
    static let maxLookTurn: Float = 1.2
    func clampedLook(_ goal: Float) -> Float { yaw + max(-Self.maxLookTurn, min(Self.maxLookTurn, wrapAngle(goal - yaw))) }

    /// Where a stop-and-look looks: a nearby friend, else a toy, else the window.
    func lookAimYaw() -> Float? {
        let others = socialOthers().filter { $0 !== self && simd_distance($0.position, position) < 4.5 && $0.idleState.kind != .sleep }
        var cands: [Float] = others.map { yawTo($0.position) }
        for f in DecorField.shared.feet where simd_distance(DecorField.shared.position(f), position) < 4 && simd_distance(DecorField.shared.position(f), position) > 0.8 { cands.append(yawTo(DecorField.shared.position(f))) }
        if let wx = RoomGeometry.windowXs.min(by: { abs($0 - px) < abs($1 - px) }) { cands.append(atan2f(wx - px, RoomLayout.minZ - pz)) }
        guard !cands.isEmpty else { return nil }
        return cands[min(cands.count - 1, Int(rand() * Float(cands.count)))]
    }

    // MARK: ending

    /// A flourish is over: resume the walk (or stand), without the special cooldown a normal behaviour sets.
    func flourishEnd(_ skinner: Skinner?) {
        let r = idleState.resume
        idleEnd(skinner, cooldown: false)
        armWalkWant = 0
        if let r, autonomy, !held, !race.active, social == nil, pending == nil {
            leg.resuming = true; leg.rolled = true
            route = []; walkFinal = false; scriptT = 0; stuckT = 0; bestDist = .infinity; steerStall = 0; walkStallRoot = position; walkStallT = 0; job = nil
            script = .walk(target: r, then: .none); activity = .walking
        } else {
            script = .none
            restTimer = rand(1.0, 2.2) * idleLively
        }
        idleState.resume = nil
    }

    /// The trot's end test (called from idleGate): 2 s, or close to the goal.
    func trotCheck(_ skinner: Skinner?) {
        guard idleState.kind == .trot else { return }
        var done = idleState.t > 2.0
        if case .walk(let tg, _) = script { if simd_distance(tg, position) < 0.9 { done = true } } else { done = true }
        if done { idleEnd(skinner, cooldown: false) }
    }

    // MARK: joy

    /// Ask for a jump for joy (an event happened). Taken at the next free moment; dropped after a few seconds.
    func wantJoy() {
        guard anticsEnabled || sleepEnabled else { return }
        joyWanted = true; joyAge = 0
    }

    /// Top of the scheduler. True = the jump for joy started.
    func joyMaybeStart(_ sim: SoftBody) -> Bool {
        guard joyWanted else { return false }
        if joyAge > 5 || idleNight > 0.7 || idleMood == .grumpy { joyWanted = false; return false }
        guard idleState.kind == nil, !held, attached, !race.active, kindCool[.joy] == nil, fastOthers() < 2 else { return false }
        if othersDoing(.joy) { return false }          // (both ends of a dance want to jump: the second one jumps once the first has landed)
        joyWanted = false
        if idleStart(.joy, sim) { kindCooldownStart(.joy); blushBump(hold: 2.4, peak: 0.7); face(.excited, hold: 1.1); postEvent(.joyJump); return true }
        return false
    }

    /// The little squash-and-giggle (reaction): feet planted, two quick squash pulses, a happy "^^".
    func runGiggle(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let t = idleState.phaseT
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        let env = max(0, 1 - t / 1.0)
        squash *= 1 - 0.09 * env * (0.5 - 0.5 * cosf(2 * .pi * 4.5 * t))
        roll += 0.03 * env * sinf(2 * .pi * 4.5 * t)
        armWalkWant = 1
        if idleState.phase == 0 { idleState.phase = 1; face(.joyArc, hold: 0.9); jellyKick = max(jellyKick, 0.8); AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.3) }
        if t > 1.0 && !feet.active { idleFinish(skinner) }
    }

    /// The big sigh: a slow inhale (swells ~4 %), a long exhale that deflates into a slump, a sleepy / worried face with droopy eyes.
    func runSigh(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let t = idleState.phaseT
        gaitPose(sway: 0.03, bob: 0.0, rock: 0.2)
        if idleState.phase == 0 { idleState.phase = 1; face(idleMood == .grumpy ? .worried : .sleepy, hold: 4.6) }
        var s: Float
        var slump: Float = 0
        if t < 1.3 { s = 0.04 * smooth01(t / 1.3) }
        else if t < 3.0 { let e = smooth01((t - 1.3) / 1.7); s = 0.04 - 0.10 * e; slump = e }
        else { let e = smooth01((t - 3.0) / 1.2); s = -0.06 + 0.06 * e; slump = 1 - e }
        squash *= 1 + s
        pitch += 0.09 * slump
        armWalkWant = 1
        if t > 4.3 && !feet.active { idleFinish(skinner) }
    }

    /// The grumpy "hmph": squash widens ~6 % for 0.6 s, angry brows, a quick turn-away and back, a small stomp.
    func runHmph(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let t = idleState.phaseT
        gaitPose(sway: 0.03, bob: 0.0, rock: 0.2)
        if idleState.phase == 0 { idleState.phase = 1; face(.grumpy, hold: 1.6) }
        let puff = smooth01(t / 0.15) * (1 - smooth01((t - 0.6) / 0.2))
        squash *= 1 - 0.06 * puff
        let turn = smooth01(t / 0.2) * (1 - smooth01((t - 0.8) / 0.35))
        twist = idleState.sign * 0.6 * turn
        if idleState.phase == 1, t > 0.35 { idleState.phase = 2; jellyKick = max(jellyKick, 1.5); AudioHub.shared.play(.footstep, jelly: steerID, x: px, volume: 0.8) }          // the stomp
        if idleState.phase == 2 { squash *= 1 - 0.05 * max(0, 1 - (t - 0.35) / 0.25) }
        armWalkWant = 1
        if t > 1.4 && !feet.active { idleFinish(skinner) }
    }

    func wantHmph() { hmphWanted = true; hmphAge = 0 }
    func hmphMaybeStart(_ sim: SoftBody) -> Bool {
        guard hmphWanted else { return false }
        if hmphAge > 5 || idleMood == .happy { hmphWanted = false; return false }
        guard idleState.kind == nil, !held, attached, !race.active else { return false }
        if othersDoing(.hmph) { return false }          // (after a squabble both huff: one after the other)
        hmphWanted = false
        return idleStart(.hmph, sim)
    }
}
