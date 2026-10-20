//
//  BlobSocial+Toss.swift
//  Two more shared plays for the second decor batch (BlobSocial+Pass.swift is the pattern):
//    cuddle   two Jellies hop onto the two cushions of a loveseat, settle, and lean toward each other (the snuggle lean; BlobBrain+Decor `seatMotion`)
//    toss     the football: one hugs it, squats and flings it (40 % he fumbles: it bonks off his head or slips), the other stands a few steps away and tries to
//             catch it by hugging it (about half the time) or misses comically (a late lunge, a squash, a jelly wobble); then the catcher throws it back.
//             No arm reaches: the ball moves with the body's squash and spring (decorThrow), the catch is a squash around the ball.
//

import Foundation
import simd

extension BlobBrain {
    /// A loveseat with both cushions free.
    func freeLoveseat() -> DecorFoot? {
        let f = DecorField.shared
        return f.feet.first { $0.kind == .loveseat && f.available($0) && (f.seatOccupant[$0.uid]?.count ?? 0) == 0 }
    }
    /// A football at rest that nobody uses.
    func freeFootball() -> DecorFoot? {
        let f = DecorField.shared
        return f.feet.first { $0.kind == .football && DecorKind.wired.contains($0.kind) && f.occupant[$0.uid] == nil && $0.uid != f.held && f.anim[$0.uid]?.moving != true && f.anim[$0.uid]?.flying != true && f.anim[$0.uid]?.held != true }
    }

    func socialStartToss(_ kind: SocialKind, with o: BlobBrain, _ sim: SoftBody) -> Bool {
        let d = simd_distance(position, o.position)
        guard !sleepLocked, d > 1.2, d < 6.5 else { return false }
        if kind == .cuddle {
            guard freeLoveseat() != nil, idleState.kind == nil, decorStart(.decorSit, sim, only: .loveseat) else { return false }
            let s = newSession(.cuddle, with: o, duration: 70)
            s.uid = idleState.decorUID
            idleState.hold = rand(10, 13)
            o.socialBook.hold = true; o.socialBook.faceYaw = o.faceCameraYaw()
            return true
        }
        guard let ball = freeFootball() else { return false }
        let c = DecorField.shared.position(ball)
        guard simd_distance(position, c) < 6.5, simd_distance(o.position, c) < 6.5 else { return false }
        let s = newSession(.toss, with: o, duration: 80)
        s.uid = ball.uid; s.passTarget = 2 + Int(rand() * 2); s.roles = 0; s.passes = 0
        DecorField.shared.occupant[ball.uid] = steerID
        o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(c)
        return true
    }

    // MARK: cuddle on the loveseat

    func driveCuddle(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        if isA {
            if s.t > s.duration { s.finish(.aborted); return }
            if s.phaseT > 3, idleState.kind == nil, o.idleState.kind == nil, scriptIsNone, o.scriptIsNone, o.socialBook.hopStarted { s.finish(.done) }
            return
        }
        if !socialBook.hopStarted {
            guard s.phaseT > 0.5 else { socialBook.hold = true; socialBook.faceYaw = faceCameraYaw(); return }
            if scriptIsNone, idleState.kind == nil {
                socialBook.hold = false; socialBook.faceYaw = nil
                socialBook.hopStarted = true
                if decorStart(.decorSit, sim, only: .loveseat) { idleState.hold = rand(10, 13); return }
                s.finish(.aborted)          // no second cushion
            }
        }
    }

    // MARK: football toss

    /// Starts a throw at `aim` on this football (it may already be in his arms, caught).
    func tossBegin(_ f: DecorFoot, aim: SIMD2<Float>, _ sim: SoftBody) -> Bool {
        guard idleState.kind == nil, !sleepLocked else { return false }
        let field = DecorField.shared
        let held = field.anim[f.uid]?.held == true
        throwAim = aim
        var stand: SIMD2<Float>?
        if !held {
            decorIgnore = nil
            stand = decorStand(.decorThrow, f, from: position)
            if stand == nil { throwAim = nil; return false }
        }
        idleBegin(.decorThrow)
        idleState.decorUID = f.uid; idleState.decorKicked = false; idleState.decorBooped = false; idleState.throwStage = 0; idleState.reps = 0
        field.occupant[f.uid] = steerID
        if let st = stand {
            idleState.decorGo = true; idleState.target = st
            script = .walk(target: st, then: .none); activity = .walking
        } else {
            idleState.decorGo = false
            let d = aim - position
            idleState.goalYaw = atan2f(d.x, d.y)
            idleState.throwStage = 0; idleState.phase = 0; idleState.phaseT = 0
            idleState.throwFate = throwFateForce ?? { let u = rand(); return u < 0.6 ? 0 : (u < 0.8 ? 1 : 2) }()
            script = .idle; activity = .lookingAround
        }
        return true
    }

    func driveToss(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        let field = DecorField.shared
        guard let f = field.foot(s.uid) else { s.finish(.aborted); return }
        if isA {
            if s.t > s.duration { s.finish(.aborted); return }
            if field.occupant[s.uid] == nil { field.occupant[s.uid] = s.idA }          // (the thrower's behaviour let go of it: the session keeps it)
        }
        let iThrow = (s.roles == 0) == isA
        let thrower = iThrow ? self : o, catcher = iThrow ? o : self
        let ball = field.position(f)
        switch s.phase {
        case 0:      // the thrower fetches the ball (or turns with it) and winds up; the catcher walks to a spot a few steps away and faces him
            if iThrow {
                socialBook.hold = false; socialBook.faceYaw = nil
                if !s.impacted, scriptIsNone, idleState.kind == nil {
                    s.impacted = true
                    if !tossBegin(f, aim: o.position, sim) { s.finish(.aborted); return }
                }
                if s.impacted, s.phaseT > 0.8, field.anim[s.uid]?.flying == true { s.setPhase(1); s.fastMoves = 0; thrower.socialBook.apartStarted = false; catcher.socialBook.apartStarted = false; catcher.socialBook.sheepishStarted = false }
                else if s.phaseT > 25 { s.finish(.aborted) }
            } else {
                if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil, thrower.idleState.kind == .decorThrow, thrower.idleState.throwStage >= 1 || thrower.idleState.decorGo == false {
                    socialBook.hopStarted = true
                    var u = position - thrower.position; let L = simd_length(u); u = L > 1e-3 ? u / L : SIMD2(0, 1)
                    let spot = fixed(thrower.position + u * 1.25)
                    socialBook.hold = false
                    if simd_distance(position, spot) > 0.2 { socialWalk(to: spot, sim) }
                } else if scriptIsNone { socialBook.hold = true; socialBook.faceYaw = yawTo(thrower.position) }
            }
        case 1:      // in the air: the catcher decides when it is close (about half the time he catches it), and hugs it, or misses
            if !iThrow {
                socialBook.hold = true; socialBook.faceYaw = yawTo(ball)
                let a = field.anim[s.uid]
                if !socialBook.apartStarted, a?.flying == true, simd_distance(ball, position) < 1.2 {
                    socialBook.apartStarted = true
                    socialBook.sheepishStarted = rand() < 0.55 && a?.flightKind == 0          // (a fumbled throw never arrives)
                }
                if socialBook.sheepishStarted, a?.flying == true, simd_distance(ball, position) < 0.7, (a?.air ?? 9) < 1.0 {
                    field.hold(s.uid, at: holdPoint(), lift: Self.holdLift)
                    s.fastMoves = 1; s.setPhase(2)
                } else if a?.flying != true { s.fastMoves = 0; s.setPhase(2) }
            } else {
                socialBook.hold = true; socialBook.faceYaw = yawTo(catcher.position)
                if field.anim[s.uid]?.flying != true, s.phaseT > 0.3 { s.fastMoves = 0; s.setPhase(2) }
            }
            if isA, s.phaseT > 6 { s.finish(.aborted) }
        case 2:      // the reaction: a hug (the ball stays against his belly), or a comic miss
            let t = s.phaseT
            socialBook.hold = true; socialBook.faceYaw = yawTo(iThrow ? catcher.position : thrower.position)
            if !iThrow {
                if s.fastMoves == 1 {
                    field.hold(s.uid, at: holdPoint(), lift: Self.holdLift)
                    socialBook.wantSquash = 1 - 0.14 * pulse(t, up: 0.12, down: 0.5)
                    socialBook.wantPitch = 0.10 * pulse(t, up: 0.12, down: 0.5)
                    if !socialBook.hopStarted2 { socialBook.hopStarted2 = true; jellyKick = max(jellyKick, 1.6); AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.7) }
                } else {
                    // too late: a lunge, a squash and a wobble while the ball rolls past
                    socialBook.wantPitch = 0.20 * pulse(t - 0.05, up: 0.16, down: 0.4)
                    socialBook.wantSquash = 1 - 0.18 * pulse(t - 0.05, up: 0.14, down: 0.45)
                    socialBook.wantRoll = 0.10 * sinf(t * 14) * (1 - smooth01(t / 0.9))
                    if !socialBook.hopStarted2 { socialBook.hopStarted2 = true; jellyKick = max(jellyKick, 2.2); AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.6, rate: 1.3) }
                }
            }
            let rolling = field.anim[s.uid]?.moving == true || field.anim[s.uid]?.flying == true
            if isA, t > 1.4, !rolling || t > 6 {
                for x in [self, o] { x.socialBook.hopStarted = false; x.socialBook.hopStarted2 = false }
                s.passes += 1
                if s.passes >= s.passTarget { s.setPhase(3) }
                else { s.roles = 1 - s.roles; s.impacted = false; s.setPhase(0) }
            }
        default:     // good game: a hop each
            if s.phaseT < 0.05, field.anim[s.uid]?.held == true { field.fling(s.uid, vh: SIMD2(sinf(yaw), cosf(yaw)) * 0.6, vy: 0, kind: 2) }
            socialBook.hold = false; socialBook.faceYaw = nil
            socialBook.wantSquash = 1; socialBook.wantPitch = 0; socialBook.wantRoll = 0
            if !socialBook.apartStarted, scriptIsNone, idleState.kind == nil, isA || s.phaseT >= 0.18 {
                socialBook.apartStarted = true
                startHopPlay(sim: sim, distance: 0.0001)
            }
            if isA, socialBook.apartStarted, o.socialBook.apartStarted, s.phaseT > 0.4, scriptIsNone, o.scriptIsNone { s.finish(.done) }
            else if isA, s.phaseT > 5 { s.finish(.done) }
        }
    }
}
