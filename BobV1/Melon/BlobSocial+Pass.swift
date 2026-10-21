//
//  BlobSocial+Pass.swift
//  Two more shared plays (user 2026-10-20: "more interaction between the Jellies"), both built from the existing moves and the room's decor:
//    pass     ball pass: the kicker walks to a spot behind the ball (the far side from his friend), leans in and kicks it AT the friend, who watches it come;
//             when it has stopped the friend walks up and kicks it back. 2...4 passes, then a hop each. Needs a placed ball that nobody uses.
//    bagSit   sit together: both settle onto a beanbag / cushion (a second piece each when the room has two), else one sits on the piece and the other
//             sits on the floor beside it. The sits are the ordinary decor sit / sit; this only brings the pair together.
//  Never with a sleeper, a meal, a touch (the base class's `socialTaken`), like every social.
//

import Foundation
import simd

extension BlobBrain {
    /// A placed ball nobody is using and that is at rest.
    func freeBall() -> DecorFoot? {
        let f = DecorField.shared
        return f.feet.first { $0.kind.isBallLike && DecorKind.wired.contains($0.kind) && f.occupant[$0.uid] == nil && $0.uid != f.held && f.anim[$0.uid]?.moving != true }
    }
    /// A beanbag / cushion nobody is using.
    func freeSeat() -> DecorFoot? {
        let f = DecorField.shared
        return f.feet.first { $0.kind.activeInteraction == .decorSit && f.occupant[$0.uid] == nil && $0.uid != f.held }
    }

    func socialStartPass(_ kind: SocialKind, with o: BlobBrain, _ sim: SoftBody) -> Bool {
        let me = position, you = o.position
        let d = simd_distance(me, you)
        if kind == .cuddle { return socialStartToss(kind, with: o, sim) }
        guard !sleepLocked, d > 1.6, d < 5.5 || kind == .bagSit else { return false }
        if kind == .pass {
            guard let ball = freeBall() else { return false }
            let c = DecorField.shared.position(ball)
            guard simd_distance(me, c) < 6.5, simd_distance(you, c) < 6.5 else { return false }
            let s = newSession(.pass, with: o, duration: 60)
            s.uid = ball.uid; s.passTarget = 2 + Int(rand() * 3); s.roles = 0; s.passes = 0
            DecorField.shared.occupant[ball.uid] = steerID
            o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(c)
            return true
        }
        // bagSit: A heads for the piece now (the ordinary decor sit), B follows a beat later
        guard idleState.kind == nil, decorStart(.decorSit, sim) else { return false }
        let s = newSession(.bagSit, with: o, duration: 60)
        s.uid = idleState.decorUID
        o.socialBook.hold = true; o.socialBook.faceYaw = o.faceCameraYaw()
        return true
    }

    // MARK: ball pass

    func driveBallPass(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        let field = DecorField.shared
        guard let f = field.foot(s.uid) else { s.finish(.aborted); return }
        if isA, s.t > s.duration { s.finish(.aborted); return }
        let ball = field.position(f)
        let kickerIsA = s.roles == 0
        let iKick = kickerIsA == isA
        let key = s.passes * 2 + s.roles
        if socialBook.roundSeen != key { socialBook.roundSeen = key; socialBook.hopStarted = false }
        let rolling = field.anim[s.uid]?.moving == true
        switch s.phase {
        case 0:   // the kicker walks to his spot behind the ball; the other watches the ball
            if !iKick { socialBook.hold = true; socialBook.faceYaw = yawTo(ball); if isA, s.phaseT > 12 { s.finish(.aborted) }; return }
            if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil {
                socialBook.hopStarted = true
                let from = o.position
                var u = ball - from; let L = simd_length(u); u = L > 1e-3 ? u / L : SIMD2(0, 1)
                let spot = fixed(ball + u * 0.95)
                if simd_distance(spot, ball + u * 0.95) > 0.1 { s.finish(.aborted); return }
                socialBook.hold = false
                if simd_distance(position, spot) > 0.15 { socialWalk(to: spot, sim) }
            }
            if socialBook.hopStarted, scriptIsNone, s.phaseT > 0.3 {
                if simd_distance(position, ball) < 1.5 { s.setPhase(1); s.impacted = false } else { s.finish(.aborted) }
            } else if s.phaseT > 12 { s.finish(.aborted) }
        case 1:   // the lean in and the kick
            let t = s.phaseT
            if !iKick { socialBook.hold = true; socialBook.faceYaw = yawTo(ball); if t > 2.5 { s.setPhase(2) }; return }
            socialBook.hold = true; socialBook.faceYaw = yawTo(o.position)
            socialBook.wantPitch = 0.16 * pulse(t - 0.15, up: 0.14, down: 0.30)
            if f.kind == .soccerball { soccerPassStomp(s, t) }          // (the soccer ball is kicked with the stomp step)
            if !s.impacted, t >= 0.38 {
                s.impacted = true
                let to = o.position
                var dir = to - ball; let L = simd_length(dir); dir = L > 1e-3 ? dir / L : SIMD2(0, 1)
                let roll = max(L - 1.0, 0.45)           // (the ball slows by e^-1.15 t: it stops about `roll` on, a body-length short of him)
                if f.kind == .soccerball { soccerPassKick(s.uid, direction: dir, roll: roll) }
                else { field.kickBall(s.uid, direction: dir, speed: min(1.15 * roll + 0.1, 4.2)) }
                field.kick(s.uid, 0.6)
                jellyKick = max(jellyKick, 1.4)
                AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.7)
            }
            if t > 0.9 { s.setPhase(2) }
        case 2:   // the ball rolls; both watch it; then the roles swap
            socialBook.hold = true; socialBook.faceYaw = yawTo(ball)
            if isA, s.phaseT > 0.5, !rolling {
                s.passes += 1
                if s.passes >= s.passTarget { s.setPhase(3) } else { s.roles = 1 - s.roles; s.setPhase(0) }
            } else if isA, s.phaseT > 9 { s.finish(.aborted) }
        default:  // good game: a hop each
            socialBook.hold = false
            if !socialBook.apartStarted, scriptIsNone, idleState.kind == nil, isA || s.phaseT >= 0.18 {
                socialBook.apartStarted = true
                startHopPlay(sim: sim, distance: 0.0001)
            }
            if isA, socialBook.apartStarted, o.socialBook.apartStarted, s.phaseT > 0.4, scriptIsNone, o.scriptIsNone { s.finish(.done) }
            else if isA, s.phaseT > 5 { s.finish(.done) }
        }
    }

    // MARK: sit together on the beanbag

    func driveBagSit(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        if isA {
            if s.t > s.duration { s.finish(.aborted); return }
            // done when both are up again (after the sits ran their course)
            if s.phaseT > 3, idleState.kind == nil, o.idleState.kind == nil, scriptIsNone, o.scriptIsNone, o.socialBook.hopStarted { s.finish(.done) }
            return
        }
        // B: a beat after A set off, onto a second piece, else onto the floor beside A's
        if !socialBook.hopStarted {
            guard s.phaseT > 0.5 else { socialBook.hold = true; socialBook.faceYaw = faceCameraYaw(); return }
            if scriptIsNone, idleState.kind == nil {
                socialBook.hold = false; socialBook.faceYaw = nil
                socialBook.hopStarted = true
                if decorStart(.decorSit, sim) { socialBook.sheepishStarted = true; return }
                if let f = DecorField.shared.foot(s.uid) {
                    let c = DecorField.shared.position(f)
                    let dir: Float = position.x >= c.x ? 1 : -1
                    for sgn in [dir, -dir] {
                        let p = c + SIMD2(sgn * (f.spec.radius + 0.95), 0.25)
                        let q = fixed(p)
                        if simd_distance(p, q) < 0.06, spotFree(q, besides: [self, o]) { socialWalk(to: q, sim); socialBook.apartStarted = true; return }
                    }
                }
                s.finish(.aborted)          // nowhere to sit
            }
            return
        }
        if socialBook.apartStarted, !socialBook.sheepishStarted, scriptIsNone, idleState.kind == nil, !feet.active {
            socialBook.sheepishStarted = true
            if idleStart(.sit, sim) { idleState.hold = rand(6, 11) } else { s.finish(.aborted) }
        }
    }
}
