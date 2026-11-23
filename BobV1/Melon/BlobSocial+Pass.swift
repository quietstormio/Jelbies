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
        let longPass = MoveMix.on && kind == .pass          // (round 3b: the receiver walks out to a spot 2.6...3.4 u away, so the two may start further apart)
        guard !sleepLocked, d > 1.6, d < (longPass ? 9 : 5.5) || kind == .bagSit else { return false }
        if kind == .pass {
            guard let ball = freeBall() else { return false }
            let c = DecorField.shared.position(ball)
            guard simd_distance(me, c) < (longPass ? 7.5 : 6.5), simd_distance(you, c) < (longPass ? 7.5 : 6.5) else { return false }
            var plan: (pk: SIMD2<Float>, pr: SIMD2<Float>)?
            if MoveMix.on, ball.kind == .soccerball {
                plan = mixPassPlan(ball: c, with: o)
                if EmoteSpot.logOn {
                    if let pl = plan { NSLog("[pass] plan t=%.1f ball=(%.2f,%.2f) kicker id%d=(%.2f,%.2f) receiver id%d=(%.2f,%.2f) spots kicker=(%.2f,%.2f) receiver=(%.2f,%.2f) line=%.2f", variety.now, c.x, c.y, steerID, me.x, me.y, o.steerID, you.x, you.y, pl.pk.x, pl.pk.y, pl.pr.x, pl.pr.y, simd_distance(pl.pk, pl.pr)) }
                    else { NSLog("[pass] refused t=%.1f ball=(%.2f,%.2f) kicker=(%.2f,%.2f) receiver=(%.2f,%.2f) why=%@", variety.now, c.x, c.y, me.x, me.y, you.x, you.y, mix.passWhy) }
                }
                if plan == nil { return false }
            }
            let s = newSession(.pass, with: o, duration: 75)
            s.mixSpot = plan?.pr
            if plan != nil { socialBook.hopStarted = false; o.socialBook.hopStarted = false; socialBook.roundSeen = -1; o.socialBook.roundSeen = -1 }          // (the flags of an earlier session must not skip the receiver's walk out)
            s.uid = ball.uid; s.passTarget = (MoveMix.on && ball.kind == .soccerball) ? MoveMix.passKicksMin + Int(rand() * Float(MoveMix.passKicksMax - MoveMix.passKicksMin + 1)) : 2 + Int(rand() * 3); s.roles = 0; s.passes = 0
            DecorField.shared.occupant[ball.uid] = steerID
            if plan == nil { o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(c) } else { o.socialBook.hold = false; o.socialBook.faceYaw = nil }
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
            if MoveMix.on, f.kind == .soccerball, s.passes == 0, s.roles == 0, let sp = s.mixSpot, !s.mixReady {          // (round 3b: first the receiver walks out to his spot; the kicker waits for him)
                if iKick { socialBook.hold = true; socialBook.faceYaw = yawTo(ball); if isA, s.phaseT > 12 { s.finish(.aborted) }; return }
                if !socialBook.hopStarted { socialBook.hopStarted = true; socialBook.hold = false; socialBook.faceYaw = nil; if simd_distance(position, sp) > 0.3 { socialWalk(to: sp, sim) } }
                if scriptIsNone, idleState.kind == nil, !feet.active, s.phaseT > 0.6, simd_distance(position, sp) < 0.5 || (s.phaseT > 2.5 && simd_distance(position, ball) > 1.9) { s.mixReady = true; socialBook.hopStarted = false }          // (arrived; or the walk ended short of the spot but still a pass away from the ball)
                else { if isA, s.phaseT > 12 { s.finish(.aborted) }; return }
            }
            if !iKick { socialBook.hold = true; socialBook.faceYaw = yawTo(ball); if isA, s.phaseT > 12 { s.finish(.aborted) }; return }
            if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil {
                socialBook.hopStarted = true
                let from = o.position
                var u = ball - from; let L = simd_length(u); u = L > 1e-3 ? u / L : SIMD2(0, 1)
                var spot = fixed(ball + u * 0.95)
                if simd_distance(spot, ball + u * 0.95) > 0.1 {
                    var found = false
                    if MoveMix.on {          // (MoveMix round 3: the spot straight behind the ball is a wall / a piece: come at it from a little to the side, the kick still goes at the friend)
                        for a in [Float(0.4), -0.4, 0.8, -0.8, 1.2, -1.2] {
                            let uu = SIMD2(u.x * cosf(a) - u.y * sinf(a), u.x * sinf(a) + u.y * cosf(a))
                            let sp = fixed(ball + uu * 0.95)
                            if simd_distance(sp, ball + uu * 0.95) <= 0.1, peerFree(sp) { spot = sp; found = true; break }
                        }
                    }
                    if !found { s.finish(.aborted); return }
                }
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
            if !s.impacted, t >= 0.38, !(MoveMix.on && f.kind == .soccerball) || socialBook.hopStarted2 || t > 1.4 {          // (round 3b: the kicker walked up to his spot: the ball waits for the stomp step to have started)
                if MoveMix.on, f.kind == .soccerball, simd_distance(position, o.position) < MoveMix.passMinDist {          // (round 3c: never a close exchange: under 2.0 u apart the pass ends, nobody kicks)
                    if EmoteSpot.logOn { NSLog("[pass] refused-kick t=%.1f ids %d,%d distance=%.2f", variety.now, steerID, o.steerID, simd_distance(position, o.position)) }
                    s.finish(.aborted); return
                }
                s.impacted = true
                if EmoteSpot.logOn { NSLog("[pass] kick t=%.1f n=%d ball=(%.2f,%.2f) kicker id%d=(%.2f,%.2f) receiver id%d=(%.2f,%.2f) distance=%.2f", variety.now, s.passes + 1, ball.x, ball.y, steerID, position.x, position.y, o.steerID, o.position.x, o.position.y, simd_distance(position, o.position)) }
                let to = o.position
                var dir = to - ball; let L = simd_length(dir); dir = L > 1e-3 ? dir / L : SIMD2(0, 1)
                let roll = max(L - 1.0, 0.45)           // (the ball slows by e^-1.15 t: it stops about `roll` on, a body-length short of him)
                if f.kind == .soccerball { soccerPassKick(s.uid, direction: dir, roll: roll) }
                else { field.kickBall(s.uid, direction: dir, speed: min(1.15 * roll + 0.1, 4.2)) }
                field.kick(s.uid, 0.6)
                jellyKick = max(jellyKick, 1.4)
                AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.7)
            }
            if t > 0.9, !(MoveMix.on && f.kind == .soccerball) || socialBook.soccerReturned || t > 2.2 { s.setPhase(2) }
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

extension BlobBrain {
    /// Round 3b: where the two stand for a real pass of the soccer ball: the kicker 0.95 u behind the ball, the receiver `D` = 3.4...2.0 u from the ball on the other side, along a line that is clear of bodies, furniture,
    /// sleepers and the HUD buttons. nil = the room has no such line (no pass).
    func mixPassPlan(ball c: SIMD2<Float>, with o: BlobBrain, restOK: ((SIMD2<Float>) -> Bool)? = nil, bodyGap: Float = 1.0) -> (pk: SIMD2<Float>, pr: SIMD2<Float>)? {
        let field = DecorField.shared
        guard let rf = roamProvider?() else { return nil }
        let others = socialOthers().filter { $0 !== self && $0 !== o }
        if others.contains(where: { $0.reserved }) { return nil }          // (a meal is on: no ball across the floor)
        var why: [String: Int] = [:]
        func good(_ p: SIMD2<Float>) -> Bool {
            if !rf.contains(p) || rf.halfWidth(at: p.y) - abs(p.x) <= 0.45 { why["floorEdge", default: 0] += 1; return false }
            if !rf.stopOK(p) { why["hudKeepOut", default: 0] += 1; return false }
            if simd_distance(fixed(p), p) >= 0.08 { why["furniture", default: 0] += 1; return false }
            if others.contains(where: { simd_distance($0.position, p) < bodyGap }) { why["body", default: 0] += 1; return false }
            if mixBallSpotBad(p) { why["sleeperOrHud", default: 0] += 1; return false }
            return true
        }
        defer { mix.passWhy = why.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") }
        var best: (pk: SIMD2<Float>, pr: SIMD2<Float>, score: Float)?
        for D in [Float(3.4), 3.2, 3.0, 2.8, 2.6, 2.3, 2.0] {
            for k in 0..<16 {
                let a = Float(k) * .pi / 8
                let v = SIMD2(sinf(a), cosf(a))
                let pk = c - v * 0.95, pr = c + v * D
                guard good(pk), good(pr) else { continue }
                if let ok = restOK, !ok(c + v * max(D - 1.0, 0.45)) { why["restInPocket", default: 0] += 1; continue }          // (soccer-room-r1: where the ball will stop must be open floor)
                var clear = true
                var d: Float = 0.4
                while d <= D { let p = c + v * d; if !field.openFloor(p) { why["lineFurniture", default: 0] += 1; clear = false; break }; if mixBallSpotBad(p) { why["lineSleeperHud", default: 0] += 1; clear = false; break }; if others.contains(where: { simd_distance($0.position, p) < 0.9 }) { why["lineBody", default: 0] += 1; clear = false; break }; d += 0.4 }
                guard clear else { continue }
                guard reachable(position, pk), reachable(o.position, pr) else { why["unreachable", default: 0] += 1; continue }
                let score = -(simd_distance(position, pk) + simd_distance(o.position, pr))
                if best == nil || score > best!.score { best = (pk, pr, score) }
            }
            if best != nil { break }
        }
        return best.map { ($0.pk, $0.pr) }
    }
}
