//
//  BlobSocial+Friends.swift
//  Six ways for two Jelbies to show they like each other (2026-10-25), at home and most of all at the Park. Each is a sequencer over the existing locked moves
//  (the walk, the in-place hop, the spin, the wave arm, the pose overlays and jelly kicks of the other socials), so the arms stay stubby and the feet attached:
//    chestBump    face to face, a small crouch, both hop and the bellies meet at the top (a big jelly squish, a bounce back), twice, a happy hop
//    highFive     face to face, both raise the hand toward the other's (the wave arm), the hands meet at the top: a clap, a kick, a cheer hop
//    hum          face to face, heads lean in, eyes close, a soft chirp each and a heart: a happy purr together
//    cheekSquish  side by side, leaning together, two gentle presses (squash + a soft squish each) and a giggle
//    twirl        face to face, each spins once (the second a beat after the first), twice, then a small bow and a heart
//    hopAlong     side by side: one hops, the other copies half a second later, three times (follow the leader, on the spot)
//  Same shape as the older kinds: a clean walk-up to a spot at the pair gap (or beside him), the act, then both let go (`finish`) and the usual cooldowns apply.
//  Close friends pick them more often (`SocialBook.close`, set by the Park from the friendship level; 1 = housemates), strangers a little less.
//

import Foundation
import simd

extension SocialKind {
    /// The "we like each other" kinds (the Park gives friendship a bonus while one is on).
    var isFriendly: Bool {
        switch self { case .chestBump, .highFive, .hum, .cheekSquish, .twirl, .hopAlong, .littleRace, .tag, .leapfrog, .peekaboo, .bellyBounce, .mirrorDance, .noseBoop, .backToBack, .cuddleLean, .ringAround: return true; default: return false }
    }
}

enum FriendTuning {
    /// Base weights in the social pick (the older kinds: boop 3, follow 2 ...).
    static let base: [(SocialKind, Float)] = [(.chestBump, 2.2), (.highFive, 2.2), (.hum, 1.8), (.cheekSquish, 1.8), (.twirl, 2.0), (.hopAlong, 2.0),
                                                      (.littleRace, 1.3), (.tag, 1.3), (.leapfrog, 1.2), (.peekaboo, 1.3), (.bellyBounce, 1.4), (.mirrorDance, 1.3), (.noseBoop, 1.4), (.backToBack, 1.2), (.cuddleLean, 1.3), (.ringAround, 1.2)]
    /// Closeness multiplier by friendship level (stranger, pal, friend, best friend); housemates are 1.
    static let closeMul: [Float] = [0.55, 0.95, 1.5, 2.1]
    /// How much a close pair raises the chance that a social starts at all (per unit of closeness above 1).
    static let pickBoost: Float = 0.4
    /// Per-character taste: the kinds a character likes a bit more (JellyFeature: none = Bob, spines = Pip, daisy = Moss, wings = Lavender).
    static let taste: [JellyFeature: Set<SocialKind>] = [
        .none: [.highFive, .chestBump, .littleRace, .peekaboo],
        .spines: [.chestBump, .highFive, .hopAlong, .tag, .leapfrog, .littleRace],
        .daisy: [.hum, .cheekSquish, .noseBoop, .cuddleLean, .backToBack],
        .wings: [.twirl, .hum, .hopAlong, .mirrorDance, .ringAround, .peekaboo],
    ]
    static let tasteMul: Float = 1.5
}

extension BlobBrain {
    /// How close this pair is (1 = housemates; the Park sets 0.55...2.1 from the friendship level, from both sides).
    func socialCloseness(to o: BlobBrain) -> Float {
        max(socialBook.close[o.steerID] ?? 1, o.socialBook.close[steerID] ?? 1)
    }

    /// The chance multiplier of a pick among these partners (close friends ask for company more often; strangers a bit less).
    func friendPickMul(_ partners: [BlobBrain]) -> Float {
        let c = partners.map { socialCloseness(to: $0) }.max() ?? 1
        return min(2.2, max(0.7, 1 + FriendTuning.pickBoost * (c - 1)))
    }

    /// Adds the friendly kinds to the pick table (BlobSocial+Play `socialPlayWeights`): closeness, mood, time of day and the character's taste.
    func socialFriendWeights(into w: inout [(SocialKind, Float)], partner o: BlobBrain, grumpy: Bool, night: Float, fastOK: Bool) {
        let c = socialCloseness(to: o)
        let taste = FriendTuning.taste[personalityKey] ?? []
        for (k, base) in FriendTuning.base {
            if k.isFast && !fastOK { continue }
            if k == socialBook.lastKind || k == o.socialBook.lastKind { continue }
            var x = base * c
            let tender = k == .hum || k == .cheekSquish || k == .cuddleLean || k == .backToBack || k == .noseBoop
            if tender { x *= (grumpy ? 0.3 : 1) * (1 + 0.6 * night) } else { x *= grumpy ? 0.15 : 1; if k.isFast { x *= 1 - 0.8 * night } }
            if taste.contains(k) { x *= FriendTuning.tasteMul }
            w.append((k, x))
        }
    }

    // MARK: starting

    func socialStartFriends(_ kind: SocialKind, with o: BlobBrain, _ sim: SoftBody) -> Bool {
        let me = position, you = o.position
        let d = simd_distance(me, you)
        if kind.isFast, fastOthers(except: [o]) > 0 { return false }
        switch kind {
        case .cheekSquish, .hopAlong:
            guard d > 0.5, d < 5.5, let spot = sideSpot(of: o, gap: peerGap * (kind == .cheekSquish ? 0.9 : 1.0)) else { return false }
            let s = newSession(kind, with: o, duration: kind == .cheekSquish ? vDur(3.6) : 0)
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = o.faceCameraYaw()
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        case .chestBump, .highFive, .hum, .twirl:
            guard d > 0.5, d < 5.5 else { return false }
            let gapK: Float = kind == .twirl ? 1.1 : (kind == .highFive ? 0.70 : (kind == .hum ? 0.82 : 0.78))
            let away = (me - you) / max(d, 1e-3)
            let want = you + away * peerGap * gapK
            let spot = closeFixed(want)
            guard simd_distance(spot, want) < 0.12, spotFree(spot, besides: [self, o]) else { return false }
            let s = newSession(kind, with: o, duration: kind == .hum ? vDur(4.6) : 0)
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = o.yawTo(me)
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        default: return false
        }
        return true
    }

    // MARK: driving

    func driveFriends(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody, _ dt: Float) {
        switch s.kind {
        case .chestBump: driveChestBump(s, o, isA, sim)
        case .highFive: driveHighFive(s, o, isA, sim)
        case .hum: driveHum(s, o, isA)
        case .cheekSquish: driveCheekSquish(s, o, isA)
        case .twirl: driveTwirl(s, o, isA, sim)
        case .hopAlong: driveHopAlong(s, o, isA, sim)
        default: break
        }
    }

    /// The shared opening of the face-to-face kinds: the one who walked up (a) arrives, both square up and settle. True = still opening.
    func openFaceToFace(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, settle: Float) -> Bool {
        switch s.phase {
        case 0:
            if !isA { socialBook.hold = true; socialBook.faceYaw = yawTo(o.position); return true }
            _ = walkUpPhase(s, o, isA)
            return true
        case 1:
            faceEach(o)
            if isA, s.phaseT > settle { s.setPhase(2); s.impacted = false }
            return true
        default: return false
        }
    }

    /// Same, side by side facing the room.
    func openSideBySide(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, settle: Float) -> Bool {
        switch s.phase {
        case 0:
            if !isA { socialBook.hold = true; socialBook.faceYaw = faceCameraYaw(); return true }
            if scriptIsNone { socialBook.hold = true; socialBook.faceYaw = faceCameraYaw() }
            _ = walkUpPhase(s, o, isA, faceBoth: false, near: 0.55)
            return true
        case 1:
            socialBook.hold = true; socialBook.faceYaw = faceCameraYaw()
            if isA, s.phaseT > settle, !feet.active, !o.feet.active { s.setPhase(2); s.impacted = false }
            else if isA, s.phaseT > 3 { s.setPhase(2); s.impacted = false }
            return true
        default: return false
        }
    }

    func finishHappy(_ s: SocialSession, _ o: BlobBrain) {
        s.finish(.done)
        onSocial?(.makeUp(partner: o.steerID)); o.onSocial?(.makeUp(partner: steerID))
    }

    // MARK: chest bump

    private func driveChestBump(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        let key = 100 + s.round
        if socialBook.roundSeen != key { socialBook.roundSeen = key; socialBook.hopStarted = false }
        if openFaceToFace(s, o, isA, settle: 0.55) {
            if s.phase == 1 { socialBook.wantSquash = 1 - 0.08 * smooth01(s.phaseT / 0.35) }          // a small crouch before the jump
            return
        }
        let t = s.phaseT
        switch s.phase {
        case 2:    // both hop on the spot (b a hair later); the bellies meet at the top
            if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil, isA || t >= 0.06 {
                socialBook.hopStarted = true; socialBook.hold = false; socialBook.faceYaw = nil
                startHopPlay(sim: sim, distance: 0.0001)
            }
            let m = t - 0.16
            socialBook.wantPitch = 0.20 * pulse(m, up: 0.12, down: 0.20) - 0.12 * pulse(m - 0.26, up: 0.10, down: 0.30)
            socialBook.wantRoll = (isA ? 1 : -1) * 0.06 * pulse(m - 0.26, up: 0.10, down: 0.30)
            socialBook.wantSquash = 1 - 0.12 * pulse(m - 0.10, up: 0.08, down: 0.26)
            if isA {
                if !s.impacted, t >= 0.34 {
                    s.impacted = true
                    jellyKick = max(jellyKick, 3.0); o.jellyKick = max(o.jellyKick, 3.0)
                    onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                    AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.9)
                }
                if t > 0.6, socialBook.hopStarted, o.socialBook.hopStarted, scriptIsNone, o.scriptIsNone, idleState.kind == nil, o.idleState.kind == nil {
                    s.round += 1
                    if s.round >= 2 { s.setPhase(3) } else { s.setPhase(1) }
                } else if t > 4 { s.finish(.aborted) }
            }
        default:    // a happy hop each and a cheer
            faceEach(o)
            if !socialBook.apartStarted, scriptIsNone, idleState.kind == nil, isA || t >= 0.18 {
                socialBook.apartStarted = true; socialBook.hold = false; socialBook.faceYaw = nil
                startHopPlay(sim: sim, distance: 0.0001)
                face(.joyArc, hold: 1.2)
            }
            if isA, socialBook.apartStarted, o.socialBook.apartStarted, t > 0.5, scriptIsNone, o.scriptIsNone { finishHappy(s, o) }
            else if isA, t > 5 { s.finish(.done) }
        }
    }

    // MARK: high five

    private func driveHighFive(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if openFaceToFace(s, o, isA, settle: 0.5) { return }
        let t = s.phaseT
        switch s.phase {
        case 2:    // both raise the hand on the side the hands meet (a on its +x, b on its -x: the same side of the world)
            if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil, isA || t >= 0.04 {
                socialBook.hopStarted = true; socialBook.hold = false; socialBook.faceYaw = nil
                currentPose(sim)
                armSide = isA ? 1 : -1
                scriptT = 0
                script = .wave(t: 0, side: armSide, then: .none); activity = .waving
            }
            if !socialBook.hopStarted { faceEach(o) }
            if isA {
                if !s.impacted, socialBook.hopStarted, case .wave(let wt, _, _) = script, wt >= WaveScript.firstPeak + 0.02 {          // the hands are up: the clap
                    s.impacted = true
                    jellyKick = max(jellyKick, 2.2); o.jellyKick = max(o.jellyKick, 2.2)
                    onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID))
                    AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.9)
                    AudioHub.shared.chirp(jelly: steerID, .happy); AudioHub.shared.chirp(jelly: o.steerID, .happy)
                }
                if s.impacted, o.socialBook.hopStarted, scriptIsNone, o.scriptIsNone, t > 1.0 { s.setPhase(3) }
                else if t > 9 { s.finish(.aborted) }
            }
        default:   // a cheer hop each
            faceEach(o)
            if !socialBook.apartStarted, scriptIsNone, idleState.kind == nil, isA || t >= 0.15 {
                socialBook.apartStarted = true; socialBook.hold = false; socialBook.faceYaw = nil
                startHopPlay(sim: sim, distance: 0.0001)
                face(.joyArc, hold: 1.2)
            }
            if isA, socialBook.apartStarted, o.socialBook.apartStarted, t > 0.5, scriptIsNone, o.scriptIsNone { finishHappy(s, o) }
            else if isA, t > 5 { s.finish(.done) }
        }
    }

    // MARK: happy hum

    private func driveHum(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool) {
        if openFaceToFace(s, o, isA, settle: 0.45) { return }
        faceEach(o)
        let ft = s.phaseT
        let lean = smooth01(ft / 0.8) * (1 - smooth01((ft - (s.duration - 0.8)) / 0.8))
        socialBook.wantPitch = 0.10 * lean
        socialBook.wantRoll = (isA ? 1 : -1) * 0.05 * lean
        socialBook.wantEyes = 1 - 0.9 * lean                                                  // eyes closed
        socialBook.wantSquash = 1 - 0.022 * lean * (0.6 + 0.4 * sinf(2 * .pi * ft * 1.3))    // the hum, felt as a faint shiver
        // a soft ripple about every 1.1 s, one chirp each (a first, b after), and a heart
        if lean > 0.6, ft.truncatingRemainder(dividingBy: 1.1) < 0.03 { jellyKick = max(jellyKick, 0.7) }
        if isA {
            if !s.impacted, ft > 0.7 {
                s.impacted = true
                AudioHub.shared.chirp(jelly: steerID, .happy)
                onSocial?(.makeUp(partner: o.steerID)); o.onSocial?(.makeUp(partner: steerID))
            }
            if s.passes == 0, ft > 1.6 { s.passes = 1; AudioHub.shared.chirp(jelly: o.steerID, .babble) }
            if s.passes == 1, ft > 3.0 { s.passes = 2; AudioHub.shared.chirp(jelly: steerID, .babble) }
            if ft > s.duration { s.finish(.done) }
        }
    }

    // MARK: cheek squish

    private func driveCheekSquish(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool) {
        if openSideBySide(s, o, isA, settle: 0.7) { return }
        socialBook.hold = true; socialBook.faceYaw = faceCameraYaw()
        let ft = s.phaseT
        let lean = smooth01(ft / 0.5) * (1 - smooth01((ft - (s.duration - 0.6)) / 0.6))
        let press = max(pulse(ft - 0.6, up: 0.22, down: 0.30), pulse(ft - 1.7, up: 0.22, down: 0.30))          // two gentle squishes
        socialBook.wantRoll = leanSign(toward: o.position) * (0.09 * lean + 0.09 * press)
        socialBook.wantSquash = 1 - 0.07 * press
        socialBook.wantEyes = 1 - 0.55 * lean
        if isA {
            if s.bumps == 0, ft > 0.82 { s.bumps = 1; squishBoth(o, first: true) }
            if s.bumps == 1, ft > 1.92 { s.bumps = 2; squishBoth(o, first: false) }
            if ft > s.duration { finishHappy(s, o) }
        }
    }
    private func squishBoth(_ o: BlobBrain, first: Bool) {
        jellyKick = max(jellyKick, 1.5); o.jellyKick = max(o.jellyKick, 1.5)
        AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.7)
        if first { onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID)) }
        else { face(.joyArc, hold: 1.0); o.face(.joyArc, hold: 1.0) }
    }

    // MARK: twirl

    private func driveTwirl(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        let key = 200 + s.round
        if socialBook.roundSeen != key { socialBook.roundSeen = key; socialBook.hopStarted = false }
        if openFaceToFace(s, o, isA, settle: 0.5) { return }
        let t = s.phaseT
        switch s.phase {
        case 2:    // a spins once, b a beat later; each turns back to face the other afterwards
            if !socialBook.hopStarted, scriptIsNone, idleState.kind == nil, t > (isA ? 0.1 : 0.45) {
                socialBook.hopStarted = true; socialBook.hold = false; socialBook.faceYaw = nil
                startSpin(sim: sim)
                AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.5)
            } else if socialBook.hopStarted, scriptIsNone { faceEach(o) }
            if isA, socialBook.hopStarted, o.socialBook.hopStarted, scriptIsNone, o.scriptIsNone, t > 2.0 {
                s.round += 1
                if s.round >= 2 { s.setPhase(3) } else { s.setPhase(2) }
            } else if isA, t > 8 { s.finish(.aborted) }
        default:   // a small bow and a heart
            faceEach(o)
            socialBook.wantPitch = 0.14 * pulse(t, up: 0.25, down: 0.40)
            if isA {
                if !s.impacted, t > 0.2 {
                    s.impacted = true
                    onSocial?(.makeUp(partner: o.steerID)); o.onSocial?(.makeUp(partner: steerID))
                    AudioHub.shared.chirp(jelly: steerID, .happy)
                }
                if t > 1.0 { s.finish(.done) }
            }
        }
    }

    // MARK: hop along

    private func driveHopAlong(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        if openSideBySide(s, o, isA, settle: 0.6) { return }
        let t = s.phaseT
        let rounds = 3
        let gap: Float = 1.6, lag: Float = 0.5
        if isA {
            if s.bumps < rounds, t >= Float(s.bumps) * gap, scriptIsNone, idleState.kind == nil {
                s.bumps += 1
                socialBook.hold = false; socialBook.faceYaw = nil
                startHopPlay(sim: sim, distance: 0.0001)
            }
        } else if s.passes < rounds, t >= Float(s.passes) * gap + lag, scriptIsNone, idleState.kind == nil {
            s.passes += 1
            socialBook.hold = false; socialBook.faceYaw = nil
            startHopPlay(sim: sim, distance: 0.0001)
            face(.joyArc, hold: 0.8)
        }
        if scriptIsNone { socialBook.hold = true; socialBook.faceYaw = faceCameraYaw() }
        if isA {
            if s.bumps >= rounds, s.passes >= rounds, t > Float(rounds) * gap + lag + 0.4, scriptIsNone, o.scriptIsNone {
                jellyKick = max(jellyKick, 1.2); o.jellyKick = max(o.jellyKick, 1.2)
                finishHappy(s, o)
            } else if t > 14 { s.finish(.done) }
        }
    }
}
