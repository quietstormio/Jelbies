//
//  BlobSocial+Friends2.swift
//  Ten more ways for two Jelbies to play (2026-10-26). Same shape as BlobSocial+Friends.swift: sequencers over the locked moves (the walk, the run, the in-place hop,
//  the spin, the flop, the sit, the pose overlays and jelly kicks), so the arms stay stubby and the feet attached. Bodies are ~1.4 wide (`peerGap`), so every
//  contact is body to body at about that gap (a soft squish), never an arm reach.
//    littleRace   side by side in two lanes, a countdown wiggle, run across the room and back; the winner hops for joy, the other pouts, then cheers
//    tag          a boop, the booper runs off, the booped chases and boops back (the roles swap each catch), three catches
//    leapfrog     one flops flat, the other hops over, then they swap
//    peekaboo     one ducks behind the other (from the camera), peeks out and pops up; the other jumps happily; twice
//    bellyBounce  side by side: lean into each other, a squish, bounce apart with a jiggle, twice
//    mirrorDance  face to face: the leader sways and hops, the other copies a beat later
//    noseBoop     face to face: one leans in and boops the other's face (a blush, a heart), then the other boops back
//    backToBack   sit back to back (the backs touch) and sway together
//    cuddleLean   side by side, leaning on each other, eyes closed, a slow sway
//    ringAround   face to face, close, they spin together, then flop over giggling
//

import Foundation
import simd

enum Friends2Tuning {
    /// Where the sides meet: centre distance as a fraction of `peerGap` (a body is ~1.4 wide, so the bodies just touch and squish a little).
    static let sideGap: Float = 0.82, faceGap: Float = 0.76
    static let raceLane: Float = 1.05
    static let tagRounds = 3
}

extension BlobBrain {
    // MARK: small helpers

    var fxFree: Bool { scriptIsNone && idleState.kind == nil }
    /// `fixed` for a spot beside a partner: the close-social gap applies (the room's peer push is shorter for a pair that is about to touch).
    func closeFixed(_ p: SIMD2<Float>) -> SIMD2<Float> { socialBook.closePending = true; defer { socialBook.closePending = false }; return fixed(p) }
    var inCloseSocial: Bool { socialBook.closePending || (social?.closeOK == true && social?.end == nil) }
    /// The leapfrog hop is a big slow one (over a crouched partner): a longer, higher hop than the locked little hop, put back afterwards.
    func leapGaitOn() { gait.hopDuration = 0.62; gait.hopApex = 0.66; gait.maxHop = 3.2 }
    func leapGaitOff() { gait.hopDuration = 0.26; gait.hopApex = 0.10; gait.maxHop = 1.6 }
    func letGo() { socialBook.hold = false; socialBook.faceYaw = nil }
    /// Resets the one-shot flags when the step changes.
    func stepKey(_ k: Int) {
        if socialBook.roundSeen != k { socialBook.roundSeen = k; socialBook.hopStarted = false; socialBook.apartStarted = false; socialBook.sheepishStarted = false }
    }
    /// Roll sign that tips his crown toward world +x (dx > 0) or -x.
    func worldLean(_ dx: Float) -> Float { leanSign(toward: position + SIMD2(dx >= 0 ? 1 : -1, 0)) }
    func holdFacing(_ yaw: Float) { socialBook.hold = true; socialBook.faceYaw = yaw }
    func turnedTo(_ yaw: Float, tol: Float = 0.12) -> Bool { abs(wrapAngle(self.yaw - yaw)) < tol && !feet.active && scriptIsNone }
    /// A hop in place (the locked hop) with a joy face.
    func hopJoy(_ sim: SoftBody, joy: Bool = true) {
        letGo()
        startHopPlay(sim: sim, distance: 0.0001)
        if joy { face(.joyArc, hold: 1.0) }
    }

    // MARK: starting

    func socialStartMore(_ kind: SocialKind, with o: BlobBrain, _ sim: SoftBody) -> Bool {
        let me = position, you = o.position
        let d = simd_distance(me, you)
        if kind.isFast, fastOthers(except: [o]) > 0 { return false }
        switch kind {
        case .littleRace, .leapfrog, .bellyBounce, .cuddleLean, .backToBack:
            let gap: Float = kind == .littleRace ? peerGap * Friends2Tuning.raceLane : (kind == .leapfrog ? peerGap * 0.85 : peerGap * Friends2Tuning.sideGap)
            guard d > 0.5, d < 5.5, let spot = sideSpot(of: o, gap: gap) else { return false }
            let dur: Float = kind == .cuddleLean ? vDur(5.6) : (kind == .backToBack ? vDur(6.5) : 0)
            let s = newSession(kind, with: o, duration: dur)
            s.goal = spot; s.roles = rand() < 0.5 ? 0 : 1
            o.socialBook.hold = true; o.socialBook.faceYaw = o.faceCameraYaw()
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        case .tag, .mirrorDance, .noseBoop, .ringAround:
            guard d > 0.5, d < 5.5 else { return false }
            let gapK: Float = kind == .ringAround ? 0.72 : (kind == .noseBoop ? 0.68 : Friends2Tuning.faceGap)
            let away = (me - you) / max(d, 1e-3)
            let want = you + away * peerGap * gapK
            let spot = closeFixed(want)
            guard simd_distance(spot, want) < 0.14, spotFree(spot, besides: [self, o]) else { return false }
            let s = newSession(kind, with: o, duration: 0)
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(me)
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        case .peekaboo:
            guard d > 0.5, d < 5.5 else { return false }
            // behind him, seen from the camera (he stands between the camera and me)
            let cy = o.faceCameraYaw()
            let u = SIMD2(sinf(cy), cosf(cy))
            let want = you - u * peerGap * 0.95
            let spot = closeFixed(want)
            guard simd_distance(spot, want) < 0.14, spotFree(spot, besides: [self, o]) else { return false }
            let s = newSession(kind, with: o, duration: 0)
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = cy
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        default: return false
        }
        return true
    }

    // MARK: driving

    func driveMore(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        // (the peer push stays off only for the length of a leapfrog hop)
        if s.kind != .leapfrog, s.kind != .ringAround, socialBook.passThrough { socialBook.passThrough = false }
        switch s.kind {
        case .littleRace: driveRace(s, o, isA, sim)
        case .tag: driveTag(s, o, isA, sim)
        case .leapfrog: driveLeapfrog(s, o, isA, sim)
        case .peekaboo: drivePeekaboo(s, o, isA, sim)
        case .bellyBounce: driveBellyBounce(s, o, isA, sim)
        case .mirrorDance: driveMirror(s, o, isA, sim)
        case .noseBoop: driveNoseBoop(s, o, isA)
        case .backToBack: driveBackToBack(s, o, isA, sim)
        case .cuddleLean: driveCuddleLean(s, o, isA)
        case .ringAround: driveRing(s, o, isA, sim)
        default: break
        }
    }

    /// Ends a play where both do a last cheer hop and A finishes with the make-up hearts. `at`: the phase time to start (b a beat later).
    private func cheerEnd(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, key: Int) {
        stepKey(key)
        if !socialBook.apartStarted, fxFree, s.phaseT >= (isA ? 0.1 : 0.3) {
            socialBook.apartStarted = true
            hopJoy(sim)
            AudioHub.shared.chirp(jelly: steerID, .happy)
        }
        if !socialBook.apartStarted { faceEach(o) }
        if isA, socialBook.apartStarted, o.socialBook.apartStarted, s.phaseT > 0.5, fxFree, o.fxFree { finishHappy(s, o) }
        else if isA, s.phaseT > 5 { s.finish(.done) }
    }

    // MARK: little race

    private func planLane(_ s: SocialSession, _ o: BlobBrain) -> Bool {
        let a = position, b = o.position
        for dir in [SIMD2<Float>(0, 1), SIMD2<Float>(0, -1)] {
            for L: Float in [3.0, 2.4, 1.8] {
                let ga = fixed(a + dir * L), gb = fixed(b + dir * L)
                guard simd_distance(ga, a + dir * L) < 0.1, simd_distance(gb, b + dir * L) < 0.1,
                      legClear(a, ga, margin: steerMargin), o.legClear(b, gb, margin: steerMargin) else { continue }
                guard !socialOthers().contains(where: { x in x !== self && x !== o && (simd_distance(x.position, ga) < peerGap || simd_distance(x.position, gb) < peerGap) }) else { continue }
                s.goal = ga; s.goal2 = gb; s.home0 = a; s.home1 = b
                s.laneYaw = atan2f(dir.x, dir.y)
                return true
            }
        }
        return false
    }

    private func driveRace(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if openSideBySide(s, o, isA, settle: 0.6) { return }
        let t = s.phaseT
        let iWin = (s.roles == 0) == isA
        let myOut = isA ? s.goal : s.goal2, myHome = isA ? s.home0 : s.home1
        switch s.phase {
        case 2:    // line up facing the lane; a tiny countdown wiggle (three little rocks)
            if isA, !s.ready {
                if planLane(s, o) { s.ready = true } else { s.finish(.aborted); return }
            }
            guard s.ready else { holdFacing(faceCameraYaw()); return }
            holdFacing(s.laneYaw)
            let wig = max(0, min(1, (t - 0.5) / 0.15)) * (1 - smooth01((t - 1.75) / 0.15))
            socialBook.wantRoll = 0.09 * wig * sinf(2 * .pi * 2.2 * (t - 0.5))
            socialBook.wantSquash = 1 - 0.05 * wig * abs(sinf(2 * .pi * 1.1 * (t - 0.5)))
            if isA, t > 1.95, turnedTo(s.laneYaw, tol: 0.2), o.turnedTo(s.laneYaw, tol: 0.2) { s.setPhase(3); AudioHub.shared.play(.zoomies, jelly: steerID, x: px, volume: 0.6) }
            else if isA, t > 5 { s.setPhase(3) }
        case 3, 4:    // out, then back (the one who is to lose starts a hair later)
            stepKey(310 + s.phase)
            let goal = s.phase == 3 ? myOut : myHome
            if !socialBook.hopStarted, fxFree, t >= (s.phase == 4 ? 0.45 : 0) + (iWin ? 0 : 0.28) {
                letGo()
                if idleStart(.run, sim, goal: goal) { socialBook.hopStarted = true } else { s.finish(.aborted) }
            }
            if socialBook.hopStarted, fxFree { holdFacing(s.phase == 3 ? s.laneYaw + .pi : s.laneYaw) }
            if isA {
                if socialBook.hopStarted, o.socialBook.hopStarted, t > 0.8, fxFree, o.fxFree { s.setPhase(s.phase + 1) }
                else if t > 14 { s.finish(.aborted) }
            }
        default:    // the winner hops for joy; the other pouts a moment, then cheers
            stepKey(330)
            if iWin {
                if !socialBook.apartStarted, fxFree, t >= 0.15 {
                    socialBook.apartStarted = true
                    if idleStart(.joy, sim) { face(.joyArc, hold: 1.3) } else { hopJoy(sim) }
                    AudioHub.shared.chirp(jelly: steerID, .happy)
                }
                if !socialBook.apartStarted { faceEach(o) }
            } else {
                if t < 1.5 {
                    faceEach(o)
                    if !socialBook.sheepishStarted { socialBook.sheepishStarted = true; face(.grumpy, hold: 1.2); AudioHub.shared.chirp(jelly: steerID, .sad) }
                    socialBook.wantPitch = 0.10 * pulse(t, up: 0.3, down: 0.9)
                    socialBook.wantSquash = 1 - 0.03 * pulse(t, up: 0.3, down: 0.9)
                } else if !socialBook.apartStarted, fxFree {
                    socialBook.apartStarted = true
                    hopJoy(sim)
                    AudioHub.shared.chirp(jelly: steerID, .babble)
                }
            }
            if isA, socialBook.apartStarted, o.socialBook.apartStarted, t > 2.0, fxFree, o.fxFree { finishHappy(s, o) }
            else if isA, t > 8 { s.finish(.done) }
        }
    }

    // MARK: tag

    private func driveTag(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if s.phase < 2, openFaceToFace(s, o, isA, settle: 0.5) { return }
        let t = s.phaseT
        let taggerIsA = s.round % 2 == 0
        let iTag = taggerIsA == isA
        switch s.phase {
        case 2:    // the boop: the tagger leans in, the other takes it (and is "it")
            faceEach(o)
            if iTag { socialBook.wantPitch = 0.20 * pulse(t, up: 0.14, down: 0.30) }
            else { socialBook.wantPitch = -0.10 * pulse(t - 0.12, up: 0.10, down: 0.35); socialBook.wantRoll = 0.08 * pulse(t - 0.12, up: 0.10, down: 0.35) }
            if isA {
                if !s.impacted, t >= 0.14 {
                    s.impacted = true
                    let tagger = taggerIsA ? self : o, tagged = taggerIsA ? o : self
                    tagger.jellyKick = max(tagger.jellyKick, 1.2); tagged.jellyKick = max(tagged.jellyKick, 2.6)
                    onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                    AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.9)
                    AudioHub.shared.chirp(jelly: tagged.steerID, .babble)
                }
                if t > 0.85 { s.setPhase(3); s.impacted = false }
            }
        case 3:    // the tagger runs off; "it" counts a beat, then chases
            stepKey(400 + s.round)
            if iTag {
                if !socialBook.hopStarted, fxFree {
                    letGo()
                    if let g = awayGoal(from: o.position), idleStart(.run, sim, goal: g) { socialBook.hopStarted = true; s.goal = g; s.impacted = true } else { s.finish(.aborted) }
                }
            } else {
                if !socialBook.hopStarted { holdFacing(yawTo(o.position)); socialBook.wantSquash = 1 - 0.04 * abs(sinf(2 * .pi * 3 * t)) }
                if !socialBook.hopStarted, s.impacted, t > 0.55, fxFree {
                    var u = position - s.goal; let L = simd_length(u); u = L > 1e-3 ? u / L : SIMD2(0, 1)
                    let spot = fixed(s.goal + u * (peerGap * Friends2Tuning.faceGap))
                    letGo()
                    socialBook.hopStarted = true
                    if simd_distance(position, spot) > 1.0 { if !idleStart(.run, sim, goal: spot) { socialWalk(to: spot, sim) } } else { socialWalk(to: spot, sim) }
                }
            }
            if isA {
                if socialBook.hopStarted, o.socialBook.hopStarted, t > 0.8, fxFree, o.fxFree {
                    s.round += 1; s.impacted = false
                    s.setPhase(s.round >= Friends2Tuning.tagRounds ? 4 : 2)
                } else if t > 14 || s.t > 60 { s.finish(.aborted) }
            }
        default:
            cheerEnd(s, o, isA, sim, key: 440)
        }
    }

    // MARK: leapfrog

    private func driveLeapfrog(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if openSideBySide(s, o, isA, settle: 0.6) { return }
        let t = s.phaseT
        // the one who crouches this turn (a first, then b); the other is the leaper
        let aCrouches = s.round % 2 == 0
        let crouch = aCrouches == isA
        switch s.phase {
        case 2:
            stepKey(500 + s.round)
            if crouch {
                if !socialBook.hopStarted {
                    if fxFree, t > 0.2 { letGo(); if idleStart(.flop, sim) { socialBook.hopStarted = true } else { s.finish(.aborted) } } else { holdFacing(yawTo(o.position)) }
                }
            } else {
                if !socialBook.hopStarted {
                    if fxFree { holdFacing(yawTo(o.position)) }
                    // the crouch is flat (flop t 0.3...1.5): the hop (~0.6 s) goes over it
                    if o.idleState.kind == .flop, o.idleState.t > 0.5, fxFree, turnedTo(yawTo(o.position), tol: 0.25) {
                        socialBook.hopStarted = true
                        socialBook.passThrough = true
                        letGo()
                        leapGaitOn()
                        let across = simd_distance(position, o.position) * 2
                        startHopPlay(sim: sim, distance: across)
                        AudioHub.shared.chirp(jelly: steerID, .happy)
                    } else if t > 4 { s.finish(.aborted) }
                } else if fxFree {
                    socialBook.passThrough = false; leapGaitOff()
                    holdFacing(yawTo(o.position))
                    if !socialBook.apartStarted { socialBook.apartStarted = true; face(.joyArc, hold: 0.8) }
                }
            }
            if isA, socialBook.hopStarted, o.socialBook.hopStarted, t > 1.0, fxFree, o.fxFree {
                s.round += 1
                s.setPhase(s.round >= 2 ? 3 : 2)
            } else if isA, t > 9 { s.finish(.aborted) }
        default:
            cheerEnd(s, o, isA, sim, key: 540)
        }
    }

    // MARK: peekaboo

    private func drivePeekaboo(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        switch s.phase {
        case 0:
            if !isA { holdFacing(faceCameraYaw()); return }
            if scriptIsNone { holdFacing(faceCameraYaw()) }
            _ = walkUpPhase(s, o, isA, faceBoth: false, near: 0.55)
            return
        case 1:
            holdFacing(faceCameraYaw())
            if isA, s.phaseT > 0.6, !feet.active, !o.feet.active { s.setPhase(2); s.impacted = false }
            else if isA, s.phaseT > 3 { s.setPhase(2); s.impacted = false }
            return
        case 2:
            stepKey(600 + s.round)
            let t = s.phaseT
            let side: Float = s.round == 0 ? 1 : -1
            if isA {   // hides, peeks to one side, pops up
                let duck = smooth01(t / 0.45) * (1 - smooth01((t - 1.5) / 0.35))
                let peek = smooth01((t - 1.5) / 0.4) * (1 - smooth01((t - 2.3) / 0.25))
                holdFacing(faceCameraYaw())
                socialBook.wantSquash = 1 - 0.20 * duck
                socialBook.wantRoll = worldLean(side) * 0.22 * peek
                socialBook.wantEyes = 1 - 0.85 * smooth01((t - 0.2) / 0.3) * (1 - smooth01((t - 1.5) / 0.25))
                if !socialBook.hopStarted, t >= 2.5, fxFree {
                    socialBook.hopStarted = true
                    hopJoy(sim)
                    AudioHub.shared.chirp(jelly: steerID, .happy)
                    jellyKick = max(jellyKick, 1.4)
                }
            } else {   // looks around for him, then jumps happily when he pops up
                if !socialBook.hopStarted {
                    holdFacing(faceCameraYaw() + (t < 1.6 ? 0.7 : -0.7) * side)
                    if t > 0.9, !socialBook.sheepishStarted { socialBook.sheepishStarted = true; face(.curious, hold: 1.2) }
                    if o.socialBook.hopStarted, fxFree {
                        socialBook.hopStarted = true
                        hopJoy(sim)
                        face(.surprised, hold: 0.5)
                        AudioHub.shared.chirp(jelly: steerID, .happy)
                        onSocial?(.makeUp(partner: o.steerID))
                    }
                }
            }
            if isA {
                if socialBook.hopStarted, o.socialBook.hopStarted, t > 3.4, fxFree, o.fxFree {
                    s.round += 1
                    if s.round >= 2 { s.setPhase(3) } else { s.setPhase(2) }
                } else if t > 8 { s.finish(.aborted) }
            }
        default:
            cheerEnd(s, o, isA, sim, key: 640)
        }
    }

    // MARK: belly bounce

    private func driveBellyBounce(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if openSideBySide(s, o, isA, settle: 0.65) { return }
        let t = s.phaseT
        switch s.phase {
        case 2:    // lean into each other, a squish, bounce apart with a jiggle
            holdFacing(faceCameraYaw())
            let toward = leanSign(toward: o.position)
            let into = pulse(t, up: 0.22, down: 0.12)
            let rebound = pulse(t - 0.34, up: 0.12, down: 0.45)
            socialBook.wantRoll = toward * (0.16 * into - 0.11 * rebound)
            socialBook.wantSquash = 1 - 0.10 * pulse(t - 0.16, up: 0.07, down: 0.26)
            if isA {
                if !s.impacted, t >= 0.2 {
                    s.impacted = true
                    jellyKick = max(jellyKick, 3.0); o.jellyKick = max(o.jellyKick, 3.0)
                    onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                    AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.9)
                    AudioHub.shared.chirp(jelly: steerID, .babble)
                }
                if t > 1.15 {
                    s.round += 1; s.impacted = false
                    s.setPhase(s.round >= 2 ? 3 : 2)
                }
            }
        default:
            cheerEnd(s, o, isA, sim, key: 740)
        }
    }

    // MARK: mirror dance

    private func driveMirror(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if s.phase < 2, openFaceToFace(s, o, isA, settle: 0.5) { return }
        let t = s.phaseT
        if s.phase >= 3 { cheerEnd(s, o, isA, sim, key: 840); return }
        // the leader (a) sways, hops twice; b copies 0.3 s later in the same world direction (a mirror image)
        let lag: Float = isA ? 0 : 0.3
        let m = t - lag
        if fxFree { holdFacing(yawTo(o.position)) }
        let sw = (m > 0.3 && m < 2.7) ? sinf(2 * .pi * (m - 0.3) / 1.2) : 0
        let env = smooth01((m - 0.3) / 0.3) * (1 - smooth01((m - 2.4) / 0.3))
        socialBook.wantRoll = worldLean(1) * 0.13 * sw * env
        socialBook.wantSquash = 1 - 0.03 * abs(sw) * env
        let count = isA ? s.bumps : s.passes
        if count < 2, m >= 3.0 + Float(count) * 1.4, fxFree {
            if isA { s.bumps += 1 } else { s.passes += 1 }
            hopJoy(sim, joy: false)
        }
        if isA {
            if s.bumps >= 2, s.passes >= 2, t > 6.5, fxFree, o.fxFree { s.setPhase(3) }
            else if t > 12 { s.finish(.aborted) }
        }
    }

    // MARK: nose boop

    private func driveNoseBoop(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool) {
        if s.phase < 2, openFaceToFace(s, o, isA, settle: 0.5) { return }
        let t = s.phaseT
        faceEach(o)
        // boop 1: a leans in at 0.2; boop 2: b leans in at 1.9
        func lean(_ m: Float) -> Float { pulse(m, up: 0.30, down: 0.35) }
        func take(_ m: Float) -> Float { pulse(m, up: 0.10, down: 0.45) }
        let leaning = isA ? lean(t - 0.2) : lean(t - 1.9)
        let taking = isA ? take(t - 1.9 - 0.30) : take(t - 0.2 - 0.30)
        socialBook.wantPitch = 0.24 * leaning - 0.10 * taking
        socialBook.wantRoll = 0.10 * taking * sinf(2 * .pi * 4.5 * max(0, (isA ? t - 2.2 : t - 0.5)))
        socialBook.wantSquash = 1 - 0.03 * taking
        if isA {
            if s.bumps == 0, t >= 0.5 { s.bumps = 1; noseBoopHit(booped: o) }
            if s.bumps == 1, t >= 2.2 { s.bumps = 2; noseBoopHit(booped: self) }
            if t > 3.8 { finishHappy(s, o) }
        }
    }
    private func noseBoopHit(booped: BlobBrain) {
        let booper = booped === self ? (socialPartner ?? self) : self
        booper.jellyKick = max(booper.jellyKick, 0.8); booped.jellyKick = max(booped.jellyKick, 2.2)
        onSocial?(.boop(partner: booped.steerID)); booped.onSocial?(.boop(partner: booper.steerID))
        booped.onSocial?(.makeUp(partner: booper.steerID)); onSocial?(.makeUp(partner: booped.steerID))
        AudioHub.shared.play(.boop, jelly: booper.steerID, x: booper.px, volume: 0.8)
        AudioHub.shared.chirp(jelly: booped.steerID, .babble)
        booped.blushBump(hold: 2.0, peak: 0.6)
    }
    private var socialPartner: BlobBrain? { guard let s = social else { return nil }; return s.a === self ? s.b : s.a }

    // MARK: back to back

    private func driveBackToBack(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if openSideBySide(s, o, isA, settle: 0.6) { return }
        let away = yawTo(o.position) + .pi
        switch s.phase {
        case 2:    // turn to face away from each other (the backs meet)
            holdFacing(away)
            if isA, turnedTo(away), o.turnedTo(o.yawTo(position) + .pi), s.phaseT > 0.3 { s.setPhase(3) }
            else if isA, s.phaseT > 4 { s.setPhase(3) }
        default:   // both sit, and sway together
            let ft = s.phaseT
            if !socialBook.hopStarted, fxFree, ft > (isA ? 0.1 : 0.35) {
                letGo()
                if idleStart(.sit, sim) { idleState.hold = s.duration + 0.5; idleState.goalYaw = away; socialBook.hopStarted = true } else { s.finish(.aborted) }
            }
            if idleState.kind == .sit {
                let sw = smooth01((ft - 1.0) / 0.8) * (1 - smooth01((ft - (s.duration - 0.6)) / 0.6))
                socialBook.wantRoll = worldLean(1) * 0.07 * sw * sinf(2 * .pi * (ft - 1.0) / 2.6)
                if isA, !s.impacted, ft > 1.0 {
                    s.impacted = true
                    jellyKick = max(jellyKick, 1.0); o.jellyKick = max(o.jellyKick, 1.0)
                    onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                    AudioHub.shared.chirp(jelly: steerID, .happy)
                }
                if isA, s.passes == 0, ft > 3.2 { s.passes = 1; AudioHub.shared.chirp(jelly: o.steerID, .babble) }
            }
            if isA {
                if ft > s.duration, idleState.kind == nil, o.idleState.kind == nil { finishHappy(s, o) }
                else if ft > s.duration + 8 { s.finish(.done) }
            }
        }
    }

    // MARK: cuddle lean

    private func driveCuddleLean(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool) {
        if openSideBySide(s, o, isA, settle: 0.7) { return }
        holdFacing(faceCameraYaw())
        let ft = s.phaseT
        let lean = smooth01(ft / 1.0) * (1 - smooth01((ft - (s.duration - 0.8)) / 0.8))
        let sway = 0.035 * lean * sinf(2 * .pi * ft / 2.8)
        socialBook.wantRoll = leanSign(toward: o.position) * 0.14 * lean + worldLean(1) * sway
        socialBook.wantEyes = 1 - 0.97 * smooth01((ft - 0.6) / 0.6) * (1 - smooth01((ft - (s.duration - 0.6)) / 0.4))
        socialBook.wantSquash = 1 - 0.025 * lean
        if isA {
            if !s.impacted, ft > 0.9 {
                s.impacted = true
                jellyKick = max(jellyKick, 1.2); o.jellyKick = max(o.jellyKick, 1.2)
                onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.5)
            }
            if s.passes == 0, ft > 2.0 { s.passes = 1; AudioHub.shared.chirp(jelly: steerID, .happy) }
            if s.passes == 1, ft > 3.4 { s.passes = 2; AudioHub.shared.chirp(jelly: o.steerID, .babble) }
            if ft > s.duration { finishHappy(s, o) }
        }
    }

    // MARK: ring around

    /// A hop (the locked hop: the body keeps facing the same way, the feet leave and land together) to a given floor spot, whatever side it is on.
    func startHopTo(_ sim: SoftBody, _ spot: SIMD2<Float>) {
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.6)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        gait.facingYaw = yaw
        gait.home = SIMD2(px, pz)
        let rv = resolve(SIMD3(spot.x, 0, spot.y), footprint)
        poseW = 0
        gait.hop(sim, to: SIMD2(rv.x, rv.z), reduceMotion: amplitude < 0.7)
        script = .hopPlay; activity = .playing
    }

    /// Face to face at nub distance, they hold hands and hop round their shared centre (a step of 60 degrees each, both facing each other the whole way, 1.5 turns),
    /// then let go and flop over giggling.
    private func driveRing(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if s.phase < 2, openFaceToFace(s, o, isA, settle: 0.5) { return }
        let t = s.phaseT
        let steps = 9
        switch s.phase {
        case 2:
            if isA, !s.ready {          // the circle: centre between us, radius half the distance
                s.ready = true
                s.home0 = (position + o.position) / 2
                let r = simd_distance(position, o.position) / 2
                s.goal = SIMD2(r, atan2f(position.x - s.home0.x, position.y - s.home0.y))          // (radius, A's angle)
            }
            guard s.ready else { faceEach(o); return }
            socialBook.passThrough = true
            stepKey(900 + s.round)
            if !socialBook.hopStarted { if fxFree { faceEach(o) } }
            if !socialBook.hopStarted, fxFree, t > (s.round == 0 ? 0.35 : 0.12), turnedTo(yawTo(o.position), tol: 0.2) {
                socialBook.hopStarted = true
                let ang = s.goal.y + (Float(s.round) + 1) * (.pi / 3) + (isA ? 0 : .pi)
                letGo()
                startHopTo(sim, s.home0 + SIMD2(sinf(ang), cosf(ang)) * s.goal.x)
                if isA, s.round % 4 == 0 { AudioHub.shared.chirp(jelly: steerID, .happy) }
                if !isA, s.round % 4 == 2 { AudioHub.shared.chirp(jelly: steerID, .babble) }
                if isA { jellyKick = max(jellyKick, 0.6) }
            }
            if isA {
                if socialBook.hopStarted, o.socialBook.hopStarted, t > 0.5, fxFree, o.fxFree {
                    s.round += 1
                    s.setPhase(s.round >= steps ? 3 : 2)
                } else if t > 4 { s.finish(.aborted) }
            }
        case 3:    // let go and flop over giggling
            stepKey(930)
            socialBook.passThrough = false
            if !socialBook.hopStarted, fxFree, t > (isA ? 0.2 : 0.4) {
                socialBook.hopStarted = true
                letGo()
                if !idleStart(.flop, sim) { hopJoy(sim) }
                AudioHub.shared.chirp(jelly: steerID, .babble)
            } else if !socialBook.hopStarted { faceEach(o) }
            if isA {
                if socialBook.hopStarted, o.socialBook.hopStarted, t > 1.0, fxFree, o.fxFree { s.setPhase(4) }
                else if t > 8 { s.finish(.done) }
            }
        default:
            faceEach(o)
            if isA, t > 0.6 { finishHappy(s, o) }
        }
    }
}
