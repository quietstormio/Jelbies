//
//  BlobBrain+Emotes.swift
//  Seven solo emotes (user-approved 2026-11-02), all STANDING pose emotes in the family of giggle / shake / sigh: the feet stay planted under him (or tuck with the body in the one little
//  hop), the arms stay the locked stubby capsules (ArmCap's global caps; the belly pat only turns their direction), the walk and the face are untouched. Each is an `IdleKind`, so the
//  scheduler (weights, cooldowns, Variety) and EmoteFeetTests / OnePieceInvariantTests pick them up like every other move.
//    hiccup            a surprised "hic!" squash-bounce straight up (a few cm), then an embarrassed look round (a worried face, a blush, a head turn each way) and a tiny second hic
//    sneeze            a wind-up (head back, eyes closing, "ah... ah..." with a small open mouth), one quick achoo squish forward (pitch <= 0.38 rad), a little shake and a blink
//    dizzyWobble       a woozy circular sway (yaw + a small circle of pitch / roll, never past 0.12 rad of side tilt), the dazed face, then a shake-off wiggle; also follows the spin antic now and then
//    politeBow         faces the player, bows forward 0.35 rad with a slight head dip, holds 0.6 s, rises (eyes lowered, a blush)
//    bellyDrum         faces the player; both stubby arms swing in and pat the belly in turn (direction only: the length stays capped), the body jiggling with each pat
//    signatureFlourish the species' own, by `feature`: Pip wags the tail, Lavender / Pearl flutter the wings, Moss spins the head daisy, Teddy wiggles ears + pom, Bob (and anyone whose
//                      feature is hidden or folded) a proud jiggle. Only the feature moves, plus the same happy squash bounce.
//  Sounds: one soft clip each (SFX.emote*), rate-limited to once per 10 s.
//

import Foundation
import simd

/// What the species flourish asks of the feature layer this tick (FeatureSet reads it; Pip's tail goes through `tailPlay` / `tailDrive`).
struct SignatureDrive: Equatable {
    var active = false
    /// 0...1 envelope of the flourish (the tail wag, the wing flutter, ... scale with it).
    var env: Float = 0
    /// Wings: degrees added to the flap (a quick flutter), clamped by what the worn items allow.
    var wingFlap: Float = 0
    /// Moss's daisy head: spin about its own axis (deg, accumulating) and the cone it wobbles in (deg).
    var spin: Float = 0, cone: Float = 0
    /// Teddy's ears + pom: extra follow-through (deg: nod, side).
    var ears = SIMD2<Float>.zero
}

enum SignatureKind: Int { case bob, tail, wings, daisy, ears }

extension BlobBrain {
    static let emoteKinds: Set<IdleKind> = [.hiccup, .sneeze, .dizzyWobble, .politeBow, .bellyDrum, .signatureFlourish]

    /// Which flourish this Jelbie has: his feature if it is out, else the plain proud jiggle.
    var signatureKind: SignatureKind {
        switch feature {
        case .spines: return hasTailToPlay && !A11ySettings.shared.reduceMotion ? .tail : .bob
        case .wings: return wingsFolded ? .bob : .wings
        case .daisy: return .daisy
        case .ears: return .ears
        case .none: return .bob
        }
    }

    // MARK: start

    /// From `idleStart`. False = not possible now.
    func emoteBegin(_ kind: IdleKind, _ sim: SoftBody) -> Bool {
        idleBegin(kind)
        script = .idle
        activity = (kind == .sneeze || kind == .politeBow) ? .lookingAround : .playing
        idleState.k = 0
        idleState.steps = 0; idleState.hop = 0; idleState.jackA = 0
        sig = SignatureDrive()
        if kind == .signatureFlourish { idleState.reps = signatureKind.rawValue; sig.active = true }
        idleState.goalYaw = emoteTurnGoal(kind) ?? yaw
        idleState.phase = emoteTurnGoal(kind) == nil ? 1 : 0          // (0 = turning first)
        if idleState.phase == 1 { emoteLaunch(kind) }
        return true
    }

    /// The heading the emote wants before it starts (nil = it starts where he stands).
    func emoteTurnGoal(_ kind: IdleKind) -> Float? {
        switch kind {
        case .politeBow: return faceCameraYaw()
        case .bellyDrum: return faceCameraYaw() + idleState.sign * 0.55          // (a little round: the patting arm shows against the belly)
        case .signatureFlourish:
            switch SignatureKind(rawValue: idleState.reps) ?? .bob {
            case .tail: return faceCameraYaw() - 1.15          // (the tail is on his +x side: that side to the room, a little short of the tail hug's full side view so the face still shows)
            case .wings: return faceCameraYaw() + idleState.sign * 0.75          // (a three-quarter back: the wings read, the face still shows)
            default: return faceCameraYaw()
            }
        default: return nil
        }
    }

    private func emoteLaunch(_ kind: IdleKind) {
        idleState.phaseT = 0
        if kind == .signatureFlourish { idleState.t = 0 }
    }

    /// After the spin antic: sometimes the chase ends woozy. True = the wobble took over (the caller must not finish).
    func dizzyFollowOn(_ sim: SoftBody) -> Bool {
        guard !A11ySettings.shared.reduceMotion, rand() < 0.35, idleMood != .grumpy else { return false }
        currentPose(sim)
        idleBegin(.dizzyWobble)          // (the spin's behaviour becomes the wobble without a stand in between)
        script = .idle; activity = .playing
        idleState.phase = 1; idleState.phaseT = 0; idleState.steps = 0; idleState.hop = 0; idleState.jackA = 0
        sig = SignatureDrive()
        kindCooldownStart(.dizzyWobble)
        return true
    }

    // MARK: run

    func runEmote(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let kind = idleState.kind else { return }
        runAir = 0
        if idleState.phase == 0 {          // turn first (bow, belly drum, the species flourish)
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.1)
            gaitPose(sway: 0.04, bob: 0, rock: 0.2)
            armWalkWant = 1
            if turning || feet.active { idleState.phaseT = 0; return }
            idleState.phase = 1; emoteLaunch(kind)
        }
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        armWalkWant = kind == .bellyDrum ? 1 : 0          // (every emote but the belly pat keeps the arms at the rest nubs, close to the body)
        let t = idleState.phaseT
        switch kind {
        case .hiccup: runHiccup(skinner, t)
        case .sneeze: runSneeze(skinner, t)
        case .dizzyWobble: runDizzy(skinner, t)
        case .politeBow: runBow(skinner, t)
        case .bellyDrum: runBellyDrum(skinner, t, dt)
        default: runSignature(skinner, t, dt)
        }
    }

    private func emoteDone(_ skinner: Skinner) {
        runAir = 0; sig = SignatureDrive(); armDirW = 0; armDirOut = 0
        skinner.setEyeOpenness(1)
        idleFinish(skinner)
    }

    /// A one-off event at time `t0` (counted in `idleState.steps` as a bitset so it fires once).
    private func emoteOnce(_ bit: Int, _ t: Float, at t0: Float) -> Bool {
        guard t >= t0, idleState.steps & (1 << bit) == 0 else { return false }
        idleState.steps |= 1 << bit
        return true
    }

    // MARK: hiccup

    private func runHiccup(_ skinner: Skinner, _ t: Float) {
        let a = amplitude
        let hic1: Float = 0.22, dur1: Float = 0.30, hic2: Float = 2.45, dur2: Float = 0.2
        var h: Float = 0, stretch: Float = 0, land: Float = 0
        // the anticipation squash, then a small straight-up hop: stretched in the air, a squash on landing
        if t < hic1 { squash *= 1 - 0.05 * smooth01(t / hic1) }
        let u1 = (t - hic1) / dur1
        if u1 >= 0, u1 < 1 { h = 0.035 * sinf(.pi * u1); stretch = 0.06 * sinf(.pi * u1) }
        else if u1 >= 1 { land = expf(-(t - hic1 - dur1) / 0.13) }
        let u2 = (t - hic2) / dur2
        var tiny: Float = 0
        if u2 >= 0, u2 < 1 { h = max(h, 0.014 * sinf(.pi * u2)); stretch = max(stretch, 0.025 * sinf(.pi * u2)) }
        else if u2 >= 1 { tiny = expf(-(t - hic2 - dur2) / 0.1) }
        squash *= 1 + stretch - 0.075 * land - 0.03 * tiny
        pitch += -0.04 * stretch / 0.06
        lift += h * a; runAir = h * a
        if emoteOnce(0, t, at: hic1) {
            AudioHub.shared.play(.emoteHic, x: px, volume: 1)
            emoteHaptic(.hic)
            jellyKick = max(jellyKick, 1.4)
            face(.surprised, hold: 0.8)
        }
        // the embarrassed look round: a worried face, a blush, a head turn to one side and the other
        let l0: Float = 1.0, l1: Float = 2.4
        if emoteOnce(1, t, at: l0) { face(.worried, hold: 1.5); blushBump(hold: 2.4, peak: 0.75) }
        if t > l0, t < l1 {
            let u = (t - l0) / (l1 - l0)
            twist = idleState.sign * 0.5 * a * sinf(2 * .pi * u)
            pitch += 0.05 * sinf(.pi * u)
        }
        if emoteOnce(2, t, at: hic2) { jellyKick = max(jellyKick, 0.7); face(.surprised, hold: 0.5) }
        if t > 3.0 && !feet.active { emoteDone(skinner) }
    }

    // MARK: sneeze

    private func runSneeze(_ skinner: Skinner, _ t: Float) {
        let a = amplitude
        let ach: Float = 1.25
        func bump(_ lo: Float, _ hi: Float) -> Float { t > lo && t < hi ? sinf(.pi * (t - lo) / (hi - lo)) : 0 }
        let in1 = bump(0.10, 0.65), in2 = bump(0.72, 1.20)
        // "ah..." "ah...": the head goes back, he stretches a touch, the mouth opens a little, the eyes close more and more
        pitch -= (0.05 * in1 + 0.09 * in2) * a
        squash *= 1 + 0.025 * in1 + 0.045 * in2
        var mouth = 0.30 * max(0.6 * in1, in2)
        // ACHOO: a fast squish forward (<= 0.38 rad), then it springs back with a small overshoot
        let u = t - ach
        if u >= 0 {
            let pk = smooth01(u / 0.06) * (1 - smooth01((u - 0.10) / 0.42))
            pitch += 0.38 * pk * a
            squash *= 1 - 0.11 * pk
            let open = u < 0.34 ? smooth01(u / 0.04) * (1 - smooth01((u - 0.22) / 0.10)) : 0
            mouth = max(mouth, 0.65 * open)
            if u > 0.45, u < 0.95 { pitch -= 0.04 * sinf(.pi * (u - 0.45) / 0.5) }
            // a small shake after it
            if u > 0.9, u < 1.4 { let e = 1 - (u - 0.9) / 0.5; twist = 0.12 * e * sinf(2 * .pi * 7 * (u - 0.9)) }
        }
        mouthOpen = mouth
        if emoteOnce(5, t, at: 0.12) { emoteHaptic(.sneezeBuild) }          // (tick-tick with the first "ah")
        if emoteOnce(0, t, at: ach - 0.02) {
            emoteHaptic(.sneezeBump)
            AudioHub.shared.play(.emoteAchoo, x: px, volume: 1)
            jellyKick = max(jellyKick, 2.4)
        }
        // the eyes: closing in the wind-up, shut for the sneeze, open again, one blink
        var eyes: Float = 1
        if t < ach - 0.05 { eyes = 1 - 0.65 * smooth01(t / 1.15) }
        else if u < 0.8 { eyes = 0.04 }
        else if u < 1.0 { eyes = 0.04 + 0.96 * smooth01((u - 0.8) / 0.2) }
        if u > 1.3, u < 1.5 { eyes = min(eyes, 1 - sinf(.pi * (u - 1.3) / 0.2)) }
        skinner.setEyeOpenness(max(0, eyes))
        if t > ach + 1.65 && !feet.active { emoteDone(skinner) }
    }

    // MARK: dizzy wobble

    private func runDizzy(_ skinner: Skinner, _ t: Float) {
        let a = amplitude
        let wob: Float = 2.25
        if emoteOnce(0, t, at: 0) { face(.dazed, hold: wob + 0.1); AudioHub.shared.play(.emoteWoozy, x: px, volume: 1) }
        if t < wob + 0.1 {
            let env = smooth01(t / 0.45) * (1 - smooth01((t - (wob - 0.4)) / 0.4))
            let w = 2 * .pi * 0.85 * t
            // a slow circle: the top draws a ring (a little roll and pitch out of phase), the head swings left and right
            twist = 0.20 * env * sinf(w) * a
            roll += 0.12 * env * cosf(w) * a
            pitch += 0.09 * env * sinf(w) * a
            squash *= 1 + 0.015 * env * sinf(2 * w)
        } else {
            // shake it off: a quick decaying wiggle and a squash pulse, then a blink
            let s = t - (wob + 0.1)
            if emoteOnce(1, t, at: wob + 0.1) { jellyKick = max(jellyKick, 1.8); face(.joyArc, hold: 0.5); emoteHaptic(.wobble) }
            let e = expf(-s / 0.32)
            twist = 0.30 * e * sinf(2 * .pi * 8 * s) * a
            squash *= 1 - 0.07 * e * (0.5 - 0.5 * cosf(2 * .pi * 8 * s))
        }
        if t > wob + 1.0 && !feet.active { emoteDone(skinner) }
    }

    // MARK: polite bow

    private func runBow(_ skinner: Skinner, _ t: Float) {
        let a = amplitude
        let down: Float = 0.55, hold: Float = 0.6, up: Float = 0.6
        let k = smooth01(t / down) * (1 - smooth01((t - down - hold) / up))
        // the bow: forward 0.35 rad about the feet, a slight extra dip of the head near the bottom, a touch lower
        let dip = smooth01((t - 0.35) / 0.25) * (1 - smooth01((t - down - hold + 0.1) / 0.2))
        pitch += (0.35 * k + 0.035 * dip) * a
        squash *= 1 - 0.03 * k
        if emoteOnce(0, t, at: 0) { face(.happy, hold: down + hold + up + 0.2); blushBump(hold: 2.4, peak: 0.6) }
        if emoteOnce(1, t, at: down) { AudioHub.shared.play(.emoteBow, x: px, volume: 1); emoteHaptic(.bowTick) }
        if t > down + hold + up + 0.35 && !feet.active { emoteDone(skinner) }
    }

    // MARK: belly drum

    /// Pat tuning: the arm's direction when it is away from the belly and when it touches it (elevation, sweep; rad), the pat rate (Hz per arm) and the start / number of pats.
    static let patAway: (el: Float, sa: Float) = (-0.05, 0.50)
    static let patTouch: (el: Float, sa: Float) = (-0.45, 1.55)
    static let patHz: Float = 1.7, patStart: Float = 0.35, patCount = 6

    private func runBellyDrum(_ skinner: Skinner, _ t: Float, _ dt: Float) {
        let a = amplitude
        let f = Self.patHz
        let total = Self.patStart + Float(Self.patCount) / (2 * f) + 0.15
        let on = smooth01(t / 0.25) * (1 - smooth01((t - total) / 0.3))
        armDirW = on
        armDirOut = 0.03
        for s in 0..<2 {
            // arm s touches the belly at phase 0 of its own cycle, the other arm half a cycle later
            let p = f * (t - Self.patStart) + (s == 0 ? 0 : 0.5)
            let w = t < Self.patStart ? 0 : 0.5 + 0.5 * cosf(2 * .pi * p)
            let e = w * w
            armDirEl[s] = Self.patAway.el + (Self.patTouch.el - Self.patAway.el) * e
            armDirSa[s] = Self.patAway.sa + (Self.patTouch.sa - Self.patAway.sa) * e
        }
        // each pat: a squash pulse and a lean toward the patting arm, a soft jelly kick on every other one
        let n = t < Self.patStart ? -1 : Int(floorf((t - Self.patStart) * 2 * f))
        if n >= 0, n < Self.patCount, idleState.hop != n + 1 {
            idleState.hop = n + 1; idleState.jackA = 1
            jellyKick = max(jellyKick, n % 2 == 0 ? 0.8 : 0.5)
            if n % 2 == 0 { emoteHaptic(n % 4 == 0 ? .patA : .patB) }          // (a soft tap on every second pat: <= 2 a second)
            if n == 0 { AudioHub.shared.play(.emotePat, x: px, volume: 1) }
        }
        idleState.jackA = max(0, idleState.jackA - dt / 0.13)
        let pulse = idleState.jackA
        squash *= 1 - 0.05 * pulse * a
        roll += ((idleState.hop % 2 == 0) ? 1 : -1) * 0.025 * pulse * a
        if emoteOnce(0, t, at: 0) { face(.happy, hold: total + 0.3) }
        if t > total + 0.4 && !feet.active { idleState.hop = 0; idleState.jackA = 0; emoteDone(skinner) }
    }

    // MARK: signature

    private func runSignature(_ skinner: Skinner, _ t: Float, _ dt: Float) {
        let a = amplitude
        let kind = SignatureKind(rawValue: idleState.reps) ?? .bob
        let total: Float = 2.5
        let env = smooth01(t / 0.25) * (1 - smooth01((t - (total - 0.45)) / 0.4))
        sig.active = true; sig.env = env
        // the happy bounce all of them share: squash pulses at 3 Hz and a little sway
        let beat = 0.5 - 0.5 * cosf(2 * .pi * 3 * t)
        squash *= 1 - 0.04 * env * beat * a
        roll += 0.025 * env * sinf(2 * .pi * 1.5 * t) * a
        if emoteOnce(0, t, at: 0) {
            face(kind == .bob ? .joyArc : .happy, hold: total); blushBump(hold: 2.4, peak: 0.6)
            emoteHaptic(.flourish)
            switch kind {
            case .tail: AudioHub.shared.play(.emoteTail, x: px, volume: 1)
            case .wings: AudioHub.shared.play(.emoteFlutter, x: px, volume: 1)
            case .daisy: AudioHub.shared.play(.emoteSpin, x: px, volume: 1)
            case .ears: AudioHub.shared.play(.emoteWiggle, x: px, volume: 1)
            case .bob: AudioHub.shared.play(.emoteWiggle, x: px, volume: 1)
            }
        }
        switch kind {
        case .tail:
            tailPlay.lift = 9 * env          // the wag itself is in tailPlayTick (wagDeg x env)
        case .wings:
            // a quick flutter that swells three times
            let swell = 0.45 + 0.55 * powf(sinf(.pi * 1.25 * t), 2)
            sig.wingFlap = 40 * env * swell * sinf(2 * .pi * 7 * t) * a
        case .daisy:
            // two turns of the head, eased in and out, tipping round a small cone as it goes
            let u = min(1, t / (total - 0.25))
            let ease = u * u * (3 - 2 * u)
            sig.spin = 720 * ease * a
            sig.cone = 30 * env * a
        case .ears:
            let w = 2 * .pi * 6 * t
            sig.ears = SIMD2(7 * sinf(w + 1.1), 16 * sinf(w)) * env * a
            twist = 0.10 * env * sinf(2 * .pi * 3 * t) * a
        case .bob:
            // a proud full-body jiggle: chest out, three kicks, a quick wiggle
            pitch -= 0.05 * env * a
            twist = 0.14 * env * sinf(2 * .pi * 4.5 * t) * a
            for (i, tk) in [Float(0.30), 0.85, 1.4].enumerated() where emoteOnce(1 + i, t, at: tk) { jellyKick = max(jellyKick, 2.0) }
        }
        if t > total && !feet.active { emoteDone(skinner) }
    }
}
