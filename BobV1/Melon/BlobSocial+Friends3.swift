//
//  BlobSocial+Friends3.swift
//  Four more ways for two Jelbies to play (2026-10-26). Sequencers over the locked moves, like Friends / Friends2 (the walk, the run, the in-place hop, the spin,
//  the wave arm, the pose overlays and jelly kicks): the arms stay stubby and the feet attached, every contact is body to body at about `peerGap`.
//    swayHug       side by side, a side hug: both lean in, eyes soft, and sway together, a squeeze, hearts
//    danceOff      face to face, take turns: one shows a move (a hop), the other copies it, then the other shows a new one (a spin) and the first copies it
//    whisperGiggle side by side: one leans to the other's side and whispers, the other tilts an ear, a surprise, then both wiggle-laugh
//    shyWave       apart (across the room): one waves, a blush, the other waves back, then they run to each other and share a cheer hop
//

import Foundation
import simd

extension BlobBrain {
    /// Overlay size for reduce motion (the hops themselves shrink in the gait).
    var socialGentle: Float { amplitude < 0.7 ? 0.55 : 1 }

    // MARK: starting

    func socialStartFriends3(_ kind: SocialKind, with o: BlobBrain, _ sim: SoftBody) -> Bool {
        let me = position, you = o.position
        let d = simd_distance(me, you)
        if kind.isFast, fastOthers(except: [o]) > 0 { return false }
        switch kind {
        case .swayHug, .whisperGiggle:
            guard d > 0.5, d < 5.5, let spot = sideSpot(of: o, gap: peerGap * (kind == .swayHug ? 0.80 : 0.86)) else { return false }
            let s = newSession(kind, with: o, duration: kind == .swayHug ? vDur(5.6) : 0)
            s.goal = spot; s.roles = rand() < 0.5 ? 0 : 1
            o.socialBook.hold = true; o.socialBook.faceYaw = o.faceCameraYaw()
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        case .danceOff:
            guard d > 0.5, d < 5.5 else { return false }
            let away = (me - you) / max(d, 1e-3)
            let want = you + away * peerGap * 0.95
            let spot = closeFixed(want)
            guard simd_distance(spot, want) < 0.14, spotFree(spot, besides: [self, o]) else { return false }
            let s = newSession(kind, with: o, duration: 0)
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(me)
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        case .shyWave:
            guard d > 2.3, d < 5.2 else { return false }
            let s = newSession(kind, with: o, duration: 0)
            s.setPhase(2)
            holdFacing(yawTo(you)); o.holdFacing(o.yawTo(me))
        default: return false
        }
        return true
    }

    // MARK: driving

    func driveFriends3(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        switch s.kind {
        case .swayHug: driveSwayHug(s, o, isA)
        case .danceOff: driveDanceOff(s, o, isA, sim)
        case .whisperGiggle: driveWhisper(s, o, isA, sim)
        case .shyWave: driveShyWave(s, o, isA, sim)
        default: break
        }
    }

    // MARK: sway hug

    private func driveSwayHug(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool) {
        if openSideBySide(s, o, isA, settle: 0.7) { return }
        holdFacing(faceCameraYaw())
        let g = socialGentle
        let ft = s.phaseT
        let lean = smooth01(ft / 0.9) * (1 - smooth01((ft - (s.duration - 0.8)) / 0.8))
        let sway = sinf(2 * .pi * (ft - 0.9) / 2.4) * smooth01((ft - 0.9) / 0.8)          // (both sway the same way in the world: one body)
        socialBook.wantRoll = leanSign(toward: o.position) * 0.11 * lean * g + worldLean(1) * 0.07 * lean * sway * g
        socialBook.wantEyes = 1 - 0.6 * lean
        socialBook.wantSquash = 1 - 0.03 * lean
        if isA {
            if !s.impacted, ft > 0.8 {
                s.impacted = true
                jellyKick = max(jellyKick, 1.6); o.jellyKick = max(o.jellyKick, 1.6)
                onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                onSocial?(.makeUp(partner: o.steerID)); o.onSocial?(.makeUp(partner: steerID))
                AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.55)
                face(.joyArc, hold: 1.4); o.face(.joyArc, hold: 1.4)
            }
            if s.passes == 0, ft > 2.4 { s.passes = 1; AudioHub.shared.chirp(jelly: steerID, .happy); jellyKick = max(jellyKick, 1.0); o.jellyKick = max(o.jellyKick, 1.0) }
            if s.passes == 1, ft > 3.8 { s.passes = 2; AudioHub.shared.chirp(jelly: o.steerID, .babble); onSocial?(.makeUp(partner: o.steerID)) }
            if ft > s.duration { finishHappy(s, o) }
        }
    }

    // MARK: dance-off

    private func driveDanceOff(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if s.phase < 2, openFaceToFace(s, o, isA, settle: 0.5) { return }
        if s.phase >= 3 { cheerEnd3(s, o, isA, sim, key: 1050); return }
        let t = s.phaseT, g = socialGentle
        // turns: 0 a shows (hop), 1 b copies (hop), 2 b shows (spin), 3 a copies (spin)
        let r = s.round
        let performerIsA = (r == 0 || r == 3)
        let iPerform = performerIsA == isA
        stepKey(1000 + r)
        if iPerform {
            let lead: Float = (r == 1 || r == 3) ? 0.15 : 0.55          // (the copy answers at once; the first of a pair is shown with a little sway-up)
            let build = pulse(t, up: 0.4, down: 0.3) * ((r == 1 || r == 3) ? 0 : 1)
            socialBook.wantRoll = worldLean(1) * 0.10 * build * sinf(2 * .pi * 2.5 * t) * g
            if !socialBook.hopStarted, fxFree, t >= lead {
                socialBook.hopStarted = true
                socialBook.hold = false; socialBook.faceYaw = nil
                if r < 2 { hopJoy(sim) } else { startSpin(sim: sim); AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.5) }
                AudioHub.shared.chirp(jelly: steerID, .happy)
            } else if !socialBook.hopStarted || fxFree { faceEach(o) }
        } else {
            // watching: a curious tilt, a nod, then a cheer when the move is done
            faceEach(o)
            socialBook.wantPitch = 0.07 * pulse(t, up: 0.3, down: 0.5) * g
            if t > 0.4, !socialBook.sheepishStarted { socialBook.sheepishStarted = true; face(.curious, hold: 0.9) }
        }
        if isA {
            let performer = performerIsA ? self : o
            if performer.socialBook.hopStarted, performer.fxFree, t > 1.6 {
                // the watcher cheers the move (a kick and a chirp), then the next turn
                let watcher = performerIsA ? o : self
                watcher.jellyKick = max(watcher.jellyKick, 1.4)
                AudioHub.shared.chirp(jelly: watcher.steerID, .babble)
                s.round += 1
                s.setPhase(s.round >= 4 ? 3 : 2)
            } else if t > 8 { s.finish(.aborted) }
        }
    }

    /// Like Friends2's `cheerEnd`: both hop for joy, A finishes with the make-up hearts.
    private func cheerEnd3(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, key: Int) {
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

    // MARK: whisper and giggle

    private func driveWhisper(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if openSideBySide(s, o, isA, settle: 0.65) { return }
        holdFacing(faceCameraYaw())
        let t = s.phaseT, g = socialGentle
        let whisperer = (s.roles == 0) == isA
        let whisp = smooth01((t - 0.2) / 0.5) * (1 - smooth01((t - 1.9) / 0.4))
        let giggle = smooth01((t - 2.1) / 0.2) * (1 - smooth01((t - 4.0) / 0.5))
        if whisperer {
            socialBook.wantRoll = leanSign(toward: o.position) * 0.19 * whisp * g
            socialBook.wantPitch = 0.05 * whisp * g
        } else {
            socialBook.wantRoll = leanSign(toward: o.position) * 0.09 * whisp * g          // (an ear tilted toward the whisper)
            if t > 0.7, !socialBook.sheepishStarted { socialBook.sheepishStarted = true; face(.curious, hold: 1.1) }
            if t > 1.9, !socialBook.apartStarted { socialBook.apartStarted = true; face(.surprised, hold: 0.5) }
        }
        let wiggle = giggle * sinf(2 * .pi * 5.5 * (t - 2.1))
        socialBook.wantRoll += 0.09 * wiggle * g
        socialBook.wantSquash = 1 - 0.04 * giggle * abs(sinf(2 * .pi * 2.75 * (t - 2.1))) * g
        if isA {
            if !s.impacted, t >= 2.1 {
                s.impacted = true
                jellyKick = max(jellyKick, 1.8); o.jellyKick = max(o.jellyKick, 1.8)
                AudioHub.shared.chirp(jelly: steerID, .babble); AudioHub.shared.chirp(jelly: o.steerID, .happy)
                face(.joyArc, hold: 1.8); o.face(.joyArc, hold: 1.8)
                o.blushBump(hold: 2.0, peak: 0.5)
                onSocial?(.makeUp(partner: o.steerID)); o.onSocial?(.makeUp(partner: steerID))
            }
            if s.passes == 0, t >= 3.1 { s.passes = 1; jellyKick = max(jellyKick, 1.2); o.jellyKick = max(o.jellyKick, 1.2) }
            if t > 4.6 { finishHappy(s, o) }
        }
    }

    // MARK: shy wave

    private func driveShyWave(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        let t = s.phaseT, g = socialGentle
        switch s.phase {
        case 2:    // a waves from afar (a blush); b waves back; each ducks its head a little
            if fxFree { faceEach(o) }
            let turn: Float = isA ? 0.3 : 1.9
            if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil, t >= turn, (isA || o.socialBook.hopStarted) {
                socialBook.hopStarted = true
                currentPose(sim)
                let local = rotXZ(o.position - position, -yaw)
                armSide = local.x >= 0 ? 1 : -1
                scriptT = 0
                socialBook.hold = false; socialBook.faceYaw = nil
                script = .wave(t: 0, side: armSide, then: .none); activity = .waving
                blushBump(hold: 2.2, peak: 0.45)
                AudioHub.shared.chirp(jelly: steerID, isA ? .happy : .babble)
            }
            if socialBook.hopStarted { socialBook.wantPitch = 0.05 * pulse(t - turn, up: 0.4, down: 0.9) * g }
            if isA {
                if socialBook.hopStarted, o.socialBook.hopStarted, scriptIsNone, o.scriptIsNone, t > 3.2, planMeeting(s, o) { s.setPhase(3) }
                else if t > 9 { s.finish(.aborted) }
            }
        case 3:    // run (or walk) to each other
            stepKey(1200)
            if !socialBook.hopStarted, fxFree {
                letGo()
                let goal = isA ? s.goal : s.goal2
                if simd_distance(position, goal) > 1.4, idleStart(.run, sim, goal: goal) { socialBook.hopStarted = true }
                else { if simd_distance(position, goal) > 0.15 { socialWalk(to: goal, sim) }; socialBook.hopStarted = true }
            }
            if isA {
                if socialBook.hopStarted, o.socialBook.hopStarted, t > 0.8, fxFree, o.fxFree { s.setPhase(4) }
                else if t > 12 { s.finish(.aborted) }
            }
        default:
            cheerEnd3(s, o, isA, sim, key: 1240)
        }
    }

    /// The two meeting spots, face to face about the middle. False = no room (the pair just ends happily where it is).
    private func planMeeting(_ s: SocialSession, _ o: BlobBrain) -> Bool {
        let a = position, b = o.position
        let d = simd_distance(a, b)
        guard d > 0.6 else { return true }
        let u = (b - a) / d, mid = (a + b) / 2, half = peerGap * 0.76 / 2
        let wa = mid - u * half, wb = mid + u * half
        let ga = closeFixed(wa), gb = closeFixed(wb)
        if simd_distance(ga, wa) < 0.2, simd_distance(gb, wb) < 0.2, spotFree(ga, besides: [self, o]), spotFree(gb, besides: [self, o]) { s.goal = ga; s.goal2 = gb; return true }
        s.goal = a; s.goal2 = b          // (no room to meet: they stay, and cheer from there)
        return true
    }
}
