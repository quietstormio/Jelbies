//
//  BlobSocial+Friends.swift
//  Six ways for two Jelbies to show they like each other (2026-10-25), at home and most of all at the Park. Each is a sequencer over the existing locked moves
//  (the walk, the in-place hop, the spin, the wave arm, the pose overlays and jelly kicks of the other socials), so the arms stay stubby and the feet attached:
//    chestBump    face to face, a small crouch, both hop and the bellies meet at the top (a big jelly squish, a bounce back), twice, a happy hop
//    highFive     the JELLY BUMP: side by side angled ~30 deg inward, both lean in and bump cheeks / upper sides: squish, boop, double jiggle, happy look; no arm raise (2026-11-02)
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
        switch self { case .chestBump, .highFive, .cheekSquish, .twirl, .hopAlong, .littleRace, .tag, .leapfrog, .peekaboo, .bellyBounce, .mirrorDance, .backToBack, .cuddleLean, .ringAround, .swayHug, .danceOff, .whisperGiggle, .shyWave, .groupHug, .groupCheer, .conga, .circleDance, .congaLine, .ringDance, .spinHug: return true; default: return false }
    }
}

/// The high five's wind-up (BlobSocial+Friends.driveHighFive): the near arm lifts `windUp` rad above the meeting elevation in `windUpRise` s, swings back in `windUpFall` s and the hands meet.
enum HighFiveTuning {
    nonisolated(unsafe) static var windUp: Float = 0.45
    nonisolated(unsafe) static var windUpRise: Float = 0.18
    nonisolated(unsafe) static var windUpFall: Float = 0.22
}

enum FriendTuning {
    /// Base weights in the social pick (the older kinds: boop 3, follow 2 ...).
    // 2026-11-06 user: standing hand-holding too often; restore when the hands emotes get their own looks (r4-hands)
    static let base: [(SocialKind, Float)] = [(.chestBump, 2.2), (.highFive, 2.2), (.cheekSquish, 0.4), (.twirl, 2.0), (.hopAlong, 2.0),
                                                      (.littleRace, 1.3), (.tag, 1.3), (.peekaboo, 1.3), (.bellyBounce, 1.4), (.mirrorDance, 1.3), (.backToBack, 1.2), (.cuddleLean, 1.3), (.ringAround, 1.2),
                                                      (.swayHug, 1.5), (.danceOff, 1.3), (.whisperGiggle, 0.3), (.shyWave, 1.2)]
    /// Closeness multiplier by friendship level (stranger, pal, friend, best friend); housemates are 1.
    static let closeMul: [Float] = [0.55, 0.95, 1.5, 2.1]
    /// How much a close pair raises the chance that a social starts at all (per unit of closeness above 1).
    static let pickBoost: Float = 0.4
    /// Per-character taste: the kinds a character likes a bit more (JellyFeature: none = Bob, spines = Pip, daisy = Moss, wings = Lavender).
    static let taste: [JellyFeature: Set<SocialKind>] = [
        .none: [.highFive, .chestBump, .littleRace, .peekaboo],
        .spines: [.chestBump, .highFive, .hopAlong, .tag, .littleRace],
        .daisy: [.cheekSquish, .cuddleLean, .backToBack],
        .wings: [.twirl, .hopAlong, .mirrorDance, .ringAround, .peekaboo],
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
            if k == .highFive, (socialBook.fiveCool[o.steerID] ?? 0) > 0 || (o.socialBook.fiveCool[steerID] ?? 0) > 0 { continue }          // (a pair high-fives at most once a minute)
            var x = base * c
            if k == .highFive { x *= EmoteTuning.fiveWeight / 2.2 * (o.socialWandering ? EmoteTuning.fiveCrossingBoost : 1) }          // (modest; likelier when they cross paths: he is out on a wander leg)
            let tender = k == .cheekSquish || k == .cuddleLean || k == .backToBack
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
        case .highFive:
            // (user rule 2: side by side, both arms up, the hands meet in the middle - BlobSocial+Hands.swift)
            guard d > 0.5, d < 5.5, let spot = sideSpot(of: o, gap: peerGap * 0.9) else { return false }
            let s = newSession(kind, with: o, duration: 0)
            s.goal = spot
            o.socialBook.hold = true; o.socialBook.faceYaw = o.faceCameraYaw()
            if simd_distance(me, spot) > 0.12 { socialWalk(to: spot, sim) } else { s.setPhase(1) }
        case .chestBump, .twirl:
            guard d > 0.5, d < 5.5 else { return false }
            let gapK: Float = kind == .twirl ? 1.1 : 0.78
            let away = (me - you) / max(d, 1e-3)
            let want = you + away * standGap(o, along: away, peerGap * gapK)
            let spot = closeFixed(want)
            guard simd_distance(spot, want) < 0.12, spotFree(spot, besides: [self, o]) else { return false }
            let s = newSession(kind, with: o, duration: 0)
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
        case 2:    // both crouch, rise (a stretch up = the "jump") and meet bellies at the top, then settle: the pair keeps its skin contact through the move (a scripted hop on the spot moved a touching pair 7-14 cm apart
            // at take-off / landing - Locomotion eases the body from the sim centroid to the root - and the stance then walked it out and back; the real hop is the cheer after the bump)
            faceEach(o)
            socialBook.hopStarted = true
            let m = t - 0.16
            socialBook.wantPitch = 0.20 * pulse(m, up: 0.12, down: 0.20) - 0.12 * pulse(m - 0.26, up: 0.10, down: 0.30)
            socialBook.wantRoll = (isA ? 1 : -1) * 0.06 * pulse(m - 0.26, up: 0.10, down: 0.30)
            socialBook.wantSquash = 1 - 0.12 * pulse(m - 0.10, up: 0.08, down: 0.26) + 0.05 * pulse(m - 0.34, up: 0.08, down: 0.22)
            if isA {
                if !s.impacted, t >= 0.34 {
                    s.impacted = true
                    jellyKick = max(jellyKick, impactKick(3.0)); o.jellyKick = max(o.jellyKick, impactKick(3.0))
                    contactBoopFallback(o)
                    contactCueFallback(o, .squish, 0.9)
                }
                if t > 1.0, o.socialBook.hopStarted {
                    s.round += 1
                    // (round 2 bumps again from where they stand: going back through phase 1 re-squared the pair, a turn step at contact whose parting retreat opened the gap 20 cm before the second bump)
                    if s.round >= 2 { s.setPhase(3) } else { s.setPhase(2); s.impacted = false }
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

    // MARK: high five (the "jelly bump")

    /// 2026-11-05 (user rule 2, replaces the jelly bump of 11-02): the HIGH FIVE. The two stand side by side facing the camera, the arms up from the first step, each raising the arm toward the other (elevation `elFive`, a wave-sized
    /// thumb, never longer than the wave's) and the hands MEET tip to tip in the middle (the stance holds the hands' gap at a squeeze: hand to hand 0 +- 0.5 cm); a slap: a jelly kick, the boop, the one haptic tap, happy eyes and hearts;
    /// both spring back with a second jiggle, the arms go down and they part. Cooldown per pair >= 60 s (EmoteTuning.fiveCooldown). (The old version leaned the bodies together and raised no arm: the hands hovered 55 cm from the partner.)
    private func driveHighFive(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool, _ sim: SoftBody) {
        let reach = { (w: Float, el: Float) in self.socialBook.handWant = HandReach(side: self.handSide(toward: o), w: w, el: el, seek: false, partner: o.steerID) }
        if openSideBySide(s, o, isA, settle: 0.7) {
            // the arms come up on the way in (the walk-up's touch distance then counts the hands: the last steps land the HANDS together, not the arm nubs)
            reach(1, HandReach.elFive)
            return
        }
        let t = s.phaseT
        socialBook.hold = true; socialBook.faceYaw = faceCameraYaw()
        let g = socialGentle
        switch s.phase {
        case 2:
            // THE WIND-UP (a readable high five): after the plant both lift the near arm HIGHER (elevation up by `HighFiveTuning.windUp`, which also draws the hands apart: the pole's reach is cos(el)) with a small
            // body-weight dip, then swing the hands back in to meet at the walk's own elevation `elFive` (the stance's meeting distance was planned for it: a steeper MEET shortens the reach and opens the gap by itself).
            // The stance row holds the pair at the stand-off through this phase (no press: the opened outline must not make the settle shuffle the feet); phase 3 is the slap.
            let up = HighFiveTuning.windUp * pulse(t, up: HighFiveTuning.windUpRise, down: HighFiveTuning.windUpFall)
            reach(1, HandReach.elFive + up)
            socialBook.wantSquash = 1 - 0.02 * pulse(t, up: 0.12, down: 0.25) * g
            socialBook.wantEyes = 1 - 0.55 * smooth01((t - 0.1) / 0.4)
            if isA, t >= HighFiveTuning.windUpRise + HighFiveTuning.windUpFall { s.bumps = contactEvents + o.contactEvents; s.setPhase(3); s.impacted = false }
        case 3:
            reach(1, HandReach.elFive)
            let sinceBump = s.impacted ? t - s.bumpT : -1
            let press = s.impacted ? pulse(sinceBump, up: 0.07, down: 0.35) : 0
            socialBook.wantSquash = 1 - 0.025 * press * g          // (a squashed body is wider: the hands are the contact, a 7 % squash drives them into each other)
            socialBook.wantEyes = 1 - 0.55 * (s.impacted ? 0 : 1)
            if isA {
                // the hands meet: the touch gate's own event (the wind-up opened the outline past its 3 cm re-arm, so it fires on the slap), or the timer if the gate never fires
                if !s.impacted, contactEvents + o.contactEvents > s.bumps || t >= 0.35 {
                    s.impacted = true; s.bumpT = t
                    jellyKick = max(jellyKick, impactKick(2.0)); o.jellyKick = max(o.jellyKick, impactKick(2.0))
                    contactBoopFallback(o)
                    contactCueFallback(o, .highFiveBoop, 0.85, haptic: .emote("highFive.bump"))
                    face(.joyArc, hold: 1.8); o.face(.joyArc, hold: 1.8)
                } else if !s.impacted, t > 9 { s.finish(.aborted) }
                if s.impacted {
                    if s.passes == 0, t - s.bumpT >= 0.42 {          // the second jiggle
                        s.passes = 1
                        jellyKick = max(jellyKick, impactKick(1.8)); o.jellyKick = max(o.jellyKick, impactKick(1.8))
                        AudioHub.shared.chirp(jelly: steerID, .happy); AudioHub.shared.chirp(jelly: o.steerID, .happy)
                        onSocial?(.makeUp(partner: o.steerID)); o.onSocial?(.makeUp(partner: steerID))
                    }
                    if s.passes == 1, t - s.bumpT > 1.2 { s.setPhase(4) }
                }
            }
        default:   // phase 4: the happy look, the arms go down, then they part
            socialBook.wantEyes = 1
            if isA, s.phaseT > 0.6 { finishHappy(s, o) }
        }
    }

    // MARK: cheek squish

    private func driveCheekSquish(_ s: SocialSession, _ o: BlobBrain, _ isA: Bool) {
        // 2026-11-05 (user rule 2): the squisher's hand rests ON the partner (the arm comes up on the way in, BlobSocial+Hands.swift): the stub arm cannot reach a cheek from beside him, so it lands on his arm / shoulder where the
        // skins meet, the pair stands at hand reach and the squish is the lean + squash of the bodies around it.
        let reaching = isA
        if reaching { socialBook.handWant = HandReach(side: handSide(toward: o), w: 1, el: HandReach.elBoop, seek: true, partner: o.steerID) }
        if openSideBySide(s, o, isA, settle: 0.7) { return }
        socialBook.hold = true; socialBook.faceYaw = faceCameraYaw()
        let ft = s.phaseT
        let lean = smooth01(ft / 0.5) * (1 - smooth01((ft - (s.duration - 0.6)) / 0.6))
        let press = max(pulse(ft - 0.6, up: 0.22, down: 0.30), pulse(ft - 1.7, up: 0.22, down: 0.30))          // two gentle squishes
        let tilt: Float = 0.3          // (a hand rests between the two: the full lean of two bodies pressed together would swing the arm nub of the one into the hand of the other)
        socialBook.wantRoll = leanSign(toward: o.position) * (0.09 * lean + 0.09 * press) * tilt
        socialBook.wantSquash = 1 - 0.04 * press          // (a squashed body is wider: with a hand between them the squish is smaller)
        socialBook.wantEyes = 1 - 0.55 * lean
        if isA {
            if s.bumps == 0, ft > 0.82 { s.bumps = 1; squishBoth(o, first: true) }
            if s.bumps == 1, ft > 1.92 { s.bumps = 2; squishBoth(o, first: false) }
            if ft > s.duration { finishHappy(s, o) }
        }
    }
    private func squishBoth(_ o: BlobBrain, first: Bool) {
        jellyKick = max(jellyKick, 1.0); o.jellyKick = max(o.jellyKick, 1.0)          // (softer: the hand is on the partner, a hard kick swings the bodies into each other)
        contactCueFallback(o, .squish, 0.7)
        if first { contactBoopFallback(o) }
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
