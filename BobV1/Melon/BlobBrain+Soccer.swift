//
//  BlobBrain+Soccer.swift
//  Soccer with stubby legs (user 2026-10-20: "no football, just soccer, hopefully they can kick it with their little stubby legs"). One behaviour,
//  `soccerKick`, in four modes, all built from the locked moves (the walk, the turn steps, the sit's forward foot step, the happy bounce); no leg swings:
//    kick     walks up behind the ball, turns onto the kick line and takes a STOMP STEP into it (the planted foot's forward step, `idleFootStep`, the sit's
//             reach): the ball leaves at 1.6...3.4 u/s along the line with a small spread as the foot comes down. One in ten plain kicks is a fumble.
//    dribble  walks a target with the ball ahead of him: on every footfall the toe nudges it on (a self-correcting nudge: the ball is kept ~0.75 ahead).
//    shoot    a mini goal is placed: he dribbles the ball to one of the goal's kick spots (minigoal.json) when it is not already there, stands 0.72 behind
//             it facing the mouth and stomps; a quarter of the shots go wide on purpose. A goal (the ball crossed the mouth, DecorField+Soccer.swift) is
//             celebrated with the happy bounce; a miss rolls on.
//    rescue   a ball stuck against a wall / in a corner / under furniture for 20 s is dribbled back to open floor.
//  The pass social (BlobSocial+Pass.swift) kicks the soccer ball with the same stomp (BlobSocial+Soccer.swift). Events: SoccerEvents.
//

import Foundation
import simd

/// The running kick's plan and progress (in `IdleState.soccer`; the stand-spot pick writes it to `BlobBrain.soccerPlan` first).
struct SoccerIdle {
    enum Mode: Int { case kick = 0, dribble = 1, shoot = 2, rescue = 3 }
    var mode: Mode = .kick
    /// Kick / shoot: 0 turn onto the line, 1 the stomp step (fires as the foot lands), 2 settle and watch. Dribble / rescue: 10 = walking legs.
    var stage = 0
    /// The kick line (unit), the dribble's destination (or the shot's aim), the goal (uid, -1 none).
    var dir = SIMD2<Float>(0, 1)
    var target = SIMD2<Float>.zero
    var goal = -1
    var fired = false
    var fumble = false
    var wasStepping = false
    var legs = 0
    /// Plain kicks left after this one (he walks after the ball for another go).
    var reps = 0
    /// The field's clock when the shot left the toe (-1 = no shot yet) and its speed.
    var shotT: Float = -1
    var kickSpeed: Float = 0
    /// A dribble leg re-aimed after a nudge: taken up between steps (a walk re-targeted mid-step pulls the feet off the locked gait).
    var pendingWalk: SIMD2<Float>?
    var isDribbling: Bool { mode == .dribble || mode == .rescue }
}

extension BlobBrain {
    /// A stuck ball's rescue outweighs everything else in the decor table.
    static let soccerRescueWeight: Float = 9

    private func rotate(_ v: SIMD2<Float>, _ a: Float) -> SIMD2<Float> { SIMD2(v.x * cosf(a) - v.y * sinf(a), v.x * sinf(a) + v.y * cosf(a)) }
    /// A spot he can stand on (the floor rules leave it alone, nobody is there).
    private func standable(_ p: SIMD2<Float>) -> SIMD2<Float>? { let q = fixed(p); return simd_distance(p, q) < 0.08 && peerFree(q) ? q : nil }

    /// The nearest goal to `p`.
    func nearestGoal(to p: SIMD2<Float>) -> DecorFoot? { DecorField.shared.goals.min { simd_distance($0.centre, p) < simd_distance($1.centre, p) } }

    /// A kick direction toward open floor from the ball, starting from "away from me" (he keeps walking the way he came).
    private func soccerOpenDirection(from here: SIMD2<Float>, ball: SIMD2<Float>) -> SIMD2<Float> {
        let field = DecorField.shared
        var base = ball - here; let L = simd_length(base); base = L > 1e-3 ? base / L : SIMD2(0, 1)
        var best = base, bestScore: Float = -.infinity
        for k in 0..<9 {
            let ring = Float((k + 1) / 2), side: Float = k % 2 == 0 ? 1 : -1
            let a = ring * 0.45 * side
            let u = rotate(base, a)
            var open: Float = 0
            for d in [Float(0.8), 1.6, 2.4] where field.openFloor(ball + u * d) { open += 1 }
            let score = open - 0.15 * abs(a)
            if score > bestScore { bestScore = score; best = u }
            if open == 3 { break }
        }
        return best
    }

    /// Where he stands to kick `f` (the ball) from `here`, choosing the mode on the way (written to `soccerPlan`); nil = nowhere to stand.
    func soccerStand(_ f: DecorFoot, from here: SIMD2<Float>) -> SIMD2<Float>? {
        let field = DecorField.shared
        let ball = field.position(f)
        var plan = SoccerIdle()
        let force = soccerModeForce
        let goal = nearestGoal(to: ball)
        if force == 3 || (force == nil && SoccerState.shared.isStuck(f.uid)) {
            guard let open = field.nearestOpenFloor(to: ball) else { return nil }
            plan.mode = .rescue; plan.target = open
        } else if let g = goal, force == 1 || force == 2 || (force == nil && rand() < 0.7) {
            let spots = field.kickSpots(g)
            guard let near = spots.min(by: { simd_distance($0.ball, ball) < simd_distance($1.ball, ball) }) else { return nil }
            plan.goal = g.uid
            if force == 1 || (force != 2 && simd_distance(near.ball, ball) > 0.5) { plan.mode = .dribble; plan.target = near.ball }
            else { plan.mode = .shoot; plan.target = near.aim }
        } else {
            plan.mode = .kick
            plan.reps = force == nil && rand() < 0.5 ? 1 : 0
        }
        switch plan.mode {
        case .dribble, .rescue:
            let d = plan.target - ball; let L = simd_length(d)
            plan.dir = L > 1e-3 ? d / L : SIMD2(0, 1)
        case .shoot:
            let d = plan.target - ball; let L = simd_length(d)
            plan.dir = L > 1e-3 ? d / L : SIMD2(0, -1)
        case .kick:
            plan.dir = soccerOpenDirection(from: here, ball: ball)
        }
        // behind the ball on the line; when that is a wall / a piece / a friend, round the ball (the line turns with him, except for a shot).
        // A rescue takes the standable spot nearest to him (the ball is in a corner: the first touch is a side-foot out of it either way, no long turn first).
        var best: (q: SIMD2<Float>, a: Float)?
        for a in [Float(0), 0.5, -0.5, 1.0, -1.0, 1.5, -1.5] {
            let u = rotate(plan.dir, a)
            guard let q = standable(ball - u * SoccerTuning.standBack) else { continue }
            if plan.mode == .rescue {
                if best == nil || simd_distance(q, here) < simd_distance(best!.q, here) { best = (q, a) }
                continue
            }
            best = (q, a); break
        }
        guard let (q, a) = best else { return nil }
        if a != 0 {
            if plan.mode == .shoot { plan.mode = .kick; plan.target = .zero; plan.goal = -1 }
            if plan.mode == .kick { plan.dir = rotate(plan.dir, a) }
        }
        soccerPlan = plan
        return q
    }

    // MARK: arriving, legs

    /// The walk to the stand (or the end of a dribble leg) is over.
    func soccerArrived(_ sim: SoftBody, _ skinner: Skinner, _ f: DecorFoot) {
        if idleState.soccer.isDribbling { idleState.soccer.stage = 10; soccerDribbleLeg(sim, skinner, f); return }
        idleState.goalYaw = atan2f(idleState.soccer.dir.x, idleState.soccer.dir.y)
        idleState.soccer.stage = 0; idleState.soccer.fired = false
        script = .idle; activity = .lookingAround
    }

    /// Starts a walk leg with the route state fresh (as `runDecorKick` does for the second kick).
    private func soccerWalk(to p: SIMD2<Float>) {
        idleState.target = p; idleState.decorGo = true; idleState.decorKicked = false
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0
        script = .walk(target: p, then: .none); activity = .walking
    }

    /// Where a dribble leg walks to: `standOff` behind `ball` on its line to the target, or, when the floor rules move that spot onto the ball (it is
    /// against a wall), round the ball to the nearest spot that is outside his body's bump circle; the plain spot when there is none.
    private func dribbleStand(ball: SIMD2<Float>, u: SIMD2<Float>) -> SIMD2<Float> {
        let want = SoccerTuning.dribbleStandOff
        let lo = SoccerTuning.bodyRadius + SoccerTuning.radius - 0.03
        for a in [Float(0), 0.5, -0.5, 1.0, -1.0, 1.5, -1.5] {
            let q = fixed(ball - rotate(u, a) * want)
            let d = simd_distance(q, ball)
            if d >= lo && d <= want + 0.2 && peerFree(q) { return q }
        }
        return fixed(ball - u * want)
    }

    /// The next dribble leg: toward the ball on its line to the target; at the target, the shot (when a goal is the point) or done.
    private func soccerDribbleLeg(_ sim: SoftBody, _ skinner: Skinner, _ f: DecorFoot) {
        let field = DecorField.shared
        let ball = field.position(f)
        var s = idleState.soccer
        let toT = s.target - ball, L = simd_length(toT)
        if L < 0.55 || s.legs > 14 || idleState.t > 40 || (s.mode == .rescue && s.legs >= 1 && field.openFloor(ball)) {
            if s.mode == .dribble, s.goal >= 0, let g = field.foot(s.goal), L < 0.9 {
                // the ball is at the kick spot: line up the shot
                let aim = g.centre + g.turned(GoalGeometry.kickSpots[1].aim)
                let d = aim - ball, dl = simd_length(d)
                s.mode = .shoot; s.target = aim; s.dir = dl > 1e-3 ? d / dl : SIMD2(0, -1); s.stage = 0; s.fired = false
                idleState.soccer = s
                if let q = standable(ball - s.dir * SoccerTuning.standBack), reachable(position, q) { soccerWalk(to: q); return }
            }
            idleFinish(skinner); return
        }
        let u = toT / L
        let goalPt = dribbleStand(ball: ball, u: u)
        s.legs += 1; s.wasStepping = feet.active
        idleState.soccer = s
        if simd_distance(position, goalPt) < 0.35 {
            // already at the ball: he stands (turning to it if need be) and the touch comes from `soccerTick`
            idleState.decorGo = false; idleState.phaseT = 0
            script = .idle; activity = .lookingAround
            return
        }
        soccerWalk(to: goalPt)
    }

    /// Standing at the ball between dribble legs (stage 10 in the .idle script): turns to face it; after a quiet 2 s the leg is planned again (the ball was moved).
    private func runDribbleStand(_ sim: SoftBody, _ skinner: Skinner, _ f: DecorFoot) {
        let ball = DecorField.shared.position(f)
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        if idleState.yielding { idleFinish(skinner); return }
        if simd_distance(ball, position) > 0.15 { _ = turnSteps(goal: yawTo(ball), tol: 0.15) }
        if idleState.phaseT > 2.0, !feet.active, DecorField.shared.anim[f.uid]?.moving != true { idleState.phaseT = 0; soccerDribbleLeg(sim, skinner, f) }
    }

    /// Every tick of a dribble (walking a leg or standing at the ball): the toe nudges the ball on at each footfall (and a standing touch when it is right at his feet); the leg is re-aimed as the ball moves.
    func soccerTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) {
        var s = idleState.soccer
        guard s.isDribbling, s.stage == 10 else { return }
        let field = DecorField.shared
        if let p = s.pendingWalk, !feet.active { idleState.soccer.pendingWalk = nil; s.pendingWalk = nil; soccerWalk(to: p) }
        let ball = field.position(f)
        let fwd = SIMD2(sinf(yaw), cosf(yaw))
        let rel = ball - position, dist = simd_length(rel), ahead = simd_dot(rel, fwd)
        let stepping = feet.active
        let landed = s.wasStepping && !stepping
        s.wasStepping = stepping
        idleState.soccer = s
        let speedNow = simd_length(field.anim[f.uid]?.vel ?? .zero)
        guard speedNow < 0.35 else { return }          // (still rolling from the last nudge)
        // at the target (or a rescued ball already on open floor): no more nudges; the leg decision ends it or lines up the shot
        let toTarget = simd_length(s.target - ball)
        if toTarget < 0.55 || (s.mode == .rescue && s.legs >= 1 && field.openFloor(ball)) {
            if speedNow < SoccerTuning.stopSpeed + 1e-3 { soccerDribbleLeg(sim, skinner, f) }
            return
        }
        var standing = false
        if case .idle = script, !stepping, speedNow < SoccerTuning.stopSpeed + 1e-3, idleState.phaseT > 0.3 { standing = true }
        // a footfall with the ball ahead (within ~50 degrees) in reach; the ball right at his toe (before his belly walks into it); or, standing at a ball
        // at rest a stride ahead of him, a touch after a short beat (he has turned to it by then)
        let footfall = landed && ahead > 0.6 * dist && dist < SoccerTuning.dribbleReach
        let atToe = (dist < SoccerTuning.dribbleTouch && ahead > 0.5 * dist) || (dist < 0.5 && ahead > -0.1 && !stepping)          // (facing it within ~60 degrees, or right under him)
        let standTouch = standing && dist < SoccerTuning.dribbleReach && ahead > 0.8 * dist
        if footfall || atToe || standTouch {
            let toT = s.target - ball, L = simd_length(toT)
            let u = L > 0.05 ? toT / L : fwd
            // a nudge that leaves the ball a stride ahead of him (and never past the target)
            let want = min(SoccerTuning.dribbleAhead + SoccerTuning.dribbleStride - max(ahead, 0), L)
            let speed = min(max(want * SoccerTuning.linearDecayPerS, L < 0.6 ? 0.45 : SoccerTuning.dribbleNudge.lowerBound), SoccerTuning.dribbleNudge.upperBound)
            field.kickBall(f.uid, direction: u, speed: speed, by: steerID)
            SoccerState.shared.newKick(f.uid)
            field.kick(f.uid, 0.3)
            jellyKick = max(jellyKick, 0.8)
            AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.35, rate: 1.3)
            SoccerEvents.emit(.kick(jelly: steerID, speed: speed, shot: false))
            // the leg follows the ball
            let goalPt = dribbleStand(ball: ball + u * (speed / SoccerTuning.linearDecayPerS), u: u)
            var follow: SIMD2<Float>? = goalPt
            if case .walk(let t, _) = script, simd_distance(t, goalPt) <= 0.4 { follow = nil }
            if let follow { if feet.active { idleState.soccer.pendingWalk = follow } else { soccerWalk(to: follow) } }
        }
    }

    // MARK: the kick itself (the .idle script)

    func runSoccer(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let f = DecorField.shared.foot(idleState.decorUID) else { idleFinish(skinner); return }
        let field = DecorField.shared
        var s = idleState.soccer
        let t = idleState.phaseT
        if s.stage == 10 { runDribbleStand(sim, skinner, f); return }
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        switch s.stage {
        case 0:   // onto the kick line
            if idleState.yielding { idleFinish(skinner); return }
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
            if !turning && !feet.active && t > 0.12 {
                let ball = field.position(f)
                if simd_distance(ball, position) > SoccerTuning.kickReach + 0.3 || field.anim[f.uid]?.moving == true {
                    // the ball is not where he lined up for it (bumped away): once more, or done
                    if s.reps > 0, soccerAgain(f) { idleState.soccer.reps = s.reps - 1 } else { idleFinish(skinner) }
                    return
                }
                s.stage = 1; s.fired = false; idleState.phaseT = 0
                idleFootStep(reach: SoccerTuning.stompReach, rate: SoccerTuning.stompRate, peak: SoccerTuning.stompPeak)          // the stomp
            }
        case 1:   // the stomp: the ball leaves as the foot comes down; a small dip and lean into it
            let k = sinf(.pi * min(1, t / 0.4))
            squash *= 1 - 0.05 * k
            pitch += 0.08 * k
            if !s.fired, feet.stepU > 0.7 || !feet.active { s.fired = true; soccerFire(f, &s) }
            if !feet.active, t > 0.3 { s.stage = 2; idleState.phaseT = 0; idleState.steps = 0 }
        default:  // settle: the foot comes back under him; he watches the ball go
            if !feet.active, idleState.steps < 1, t > 0.25 { idleFootStep(reach: 0); idleState.steps += 1 }
            let rolling = field.anim[f.uid]?.moving == true
            if s.mode == .shoot, let lg = SoccerState.shared.lastGoal, lg.ball == f.uid, lg.scorer == steerID, s.shotT >= 0, lg.at >= s.shotT {
                idleState.soccer = s
                soccerCelebrate(sim, skinner)          // GOAL
                return
            }
            if idleState.yielding, t > 0.5 { idleFinish(skinner); return }
            if (!rolling && t > 0.8) || t > 6 {
                if s.mode == .kick, s.reps > 0, !s.fumble, soccerAgain(f) { idleState.soccer.reps = s.reps - 1; return }
                idleFinish(skinner); return
            }
        }
        idleState.soccer = s
    }

    /// Another go at the ball where it stopped (a new stand, maybe a new mode). False = it is out of reach.
    private func soccerAgain(_ f: DecorFoot) -> Bool {
        let ball = DecorField.shared.position(f)
        guard simd_distance(position, ball) < 4.5, let stand = soccerStand(f, from: position), reachable(position, stand) else { return false }
        idleState.soccer = soccerPlan
        soccerWalk(to: stand)
        return true
    }

    /// The foot lands: the ball goes (or it is a fumble).
    private func soccerFire(_ f: DecorFoot, _ s: inout SoccerIdle) {
        let field = DecorField.shared
        let ball = field.position(f)
        let rel = ball - position, dist = simd_length(rel)
        let fwd = SIMD2(sinf(yaw), cosf(yaw))
        let inReach = dist < SoccerTuning.kickReach && dist > 1e-3 && simd_dot(rel / dist, fwd) > 0.45
        if !inReach || (soccerModeForce == nil && s.mode == .kick && rand() < 0.10) {
            // a fumble: the toe grazes it (or meets air): a wobble, the ball barely moves
            s.fumble = true
            if inReach { field.kickBall(f.uid, direction: s.dir, speed: 0.45, by: steerID); SoccerState.shared.newKick(f.uid) }
            jellyKick = max(jellyKick, 1.8)
            AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.5)
            SoccerEvents.emit(.fumble(jelly: steerID))
            return
        }
        var dir = s.dir
        var speed: Float
        if s.mode == .shoot {
            var aim = s.target
            if soccerModeForce == nil, rand() < 0.25, let g = field.foot(s.goal) {
                aim = g.centre + g.turned(SIMD2((rand() < 0.5 ? -1 : 1) * (GoalGeometry.mouthHalfWidth + 0.35), GoalGeometry.mouthZ))          // wide, just outside a post
            } else {
                aim += (field.foot(s.goal)?.turned(SIMD2(rand(-0.25, 0.25), 0))) ?? SIMD2(rand(-0.25, 0.25), 0)
            }
            let d = aim - ball, L = simd_length(d)
            dir = L > 1e-3 ? d / L : s.dir
            // reaches the net with some pace (the roll is v / 1.15)
            speed = min(max((L + 0.9) * SoccerTuning.linearDecayPerS, SoccerTuning.kickSpeed.lowerBound), SoccerTuning.kickSpeed.upperBound)
        } else {
            dir = rotate(dir, rand(-0.18, 0.18))
            speed = rand(SoccerTuning.kickSpeed.lowerBound, SoccerTuning.kickSpeed.upperBound)
        }
        field.kickBall(f.uid, direction: dir, speed: speed, by: steerID)
        SoccerState.shared.newKick(f.uid)
        field.kick(f.uid, 0.6)
        jellyKick = max(jellyKick, 1.4)
        AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.8)
        s.shotT = SoccerState.shared.clock; s.kickSpeed = speed
        SoccerEvents.emit(.kick(jelly: steerID, speed: speed, shot: s.mode == .shoot))
    }

    /// GOAL: the happy bounce on the spot (the `decorHop` hand-over: the bounce owns the body from here; the ball is let go at the end as usual).
    func soccerCelebrate(_ sim: SoftBody, _ skinner: Skinner) {
        idleState.kind = .bounce
        idleState.target = position
        idleState.reps = 3
        idleState.hop = 0; idleState.landT = 0
        script = .idle; activity = .playing
        idleState.phase = 1; idleState.phaseT = 0
        jellyKick = max(jellyKick, 2.0)
        idleScootHop(sim)
    }
}
