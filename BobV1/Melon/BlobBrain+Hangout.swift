//
//  BlobBrain+Hangout.swift
//  Six more SOLO "hangout" emotes (2026-11-09, "add more random emotes for a single Jelbie to do when they're just hanging out ... they should rarely just be standing around looking at the user").
//  Calm, self-absorbed little things: the Jelbie is busy with itself, three-quarter to the camera or looking where it is looking, never staring into the lens.
//    humTune      eyes closed (joyArc), a slow side-to-side sway with a tiny bounce on each beat, one hum (his own .hum)
//    curiousPeek  turns toward a room direction away from the player, leans in a little with a head tilt, "ooh?", a second smaller lean, straightens
//    bigStretch   both stubby arms up, the body stretches tall (feet planted), a little shiver at the top, drops back with a soft settle wobble and a content "aww"
//    tailPeek     looks over a shoulder at his own back, turns a slow half circle in place (the turn-in-place steps) trying to see it, stops, a puzzled "huh?", a small shrug-bounce
//    pawCheck     lifts one stubby arm, looks down at it, wiggles it twice, then the other arm; a pleased little nod and "ooh"
//    bugWatch     the eyes / head follow an imaginary fly (left, right, up), an "eep!", a small hop with one arm up to catch it (the joy hop machinery), misses, a giggle
//  They are ADDITIONS: not in `treatWeights` or `EmoteTreats.batch2` (those would dilute the old moves). Each Jelbie has its OWN clock (`HangoutState.next`, about one every 40...70 s,
//  rarer at night, none from `idleNight` 0.6), the gates of the batch-2 treats (`treat2Free`), and while one runs the old cycle's timers (special cooldown, zoomies urge, treat clock) keep
//  counting, so the old moves lose nothing but the pick that was taken. Vocals go through `AudioHub.hangoutVoice` (his own context-voice file, a guaranteed one-shot, a 2 s self-hush).
//  A touch / request / yield overrides them the way it does the batch-2 emotes (`idleGate`'s default: abortAll).
//

import Foundation
import simd

enum HangoutTuning {
    /// False = the hangout slot never starts (the headless soak's "before").
    nonisolated(unsafe) static var enabled = true
    /// Seconds between two hangout emotes of one Jelbie (a Jelbie's first one comes `firstGap` after he starts roaming, staggered per Jelbie).
    nonisolated(unsafe) static var gap: ClosedRange<Float> = 25...45
    nonisolated(unsafe) static var firstGap: ClosedRange<Float> = 8...25
    /// curiousPeek / bugWatch voice on this seeded roll (the others: humTune and bigStretch always, pawCheck and tailPeek never): the vocal family stays under its ceiling.
    nonisolated(unsafe) static var voiceChance: Float = 0.35
    /// No hangout emote from this `idleNight` on; below it the gap grows up to 4x.
    static let nightStop: Float = 0.6
    /// Room-wide haptic limiter: at most one hangout cue per this many seconds across all Jelbies.
    static let cueGap: Double = 4
    nonisolated(unsafe) static var lastCue: Double = -1e9
    nonisolated(unsafe) static var lastOwner = -1
    nonisolated(unsafe) static var lastKind: IdleKind?
}

/// Per-brain bookkeeping of the hangout slot. Its own random stream: the brain's `rand()` sequence belongs to the seeded suites.
struct HangoutState {
    var next: Float = -1
    var last: IdleKind?
    var rngS: UInt64 = 0xA24BAED4963EE407
    var turnLeft: Float = 0
    var voiceOn = true
    var plays: [IdleKind: Int] = [:]
    /// Voices that PLAYED (past every gate), per kind (the soak's numbers).
    var voices: [IdleKind: Int] = [:]
    mutating func rnd() -> Float { rngS ^= rngS << 13; rngS ^= rngS >> 7; rngS ^= rngS << 17; return Float(rngS >> 40) / Float(1 << 24) }
    mutating func rnd(_ a: Float, _ b: Float) -> Float { a + (b - a) * rnd() }
}

extension BlobBrain {
    static let hangoutKinds: Set<IdleKind> = [.humTune, .curiousPeek, .bigStretch, .tailPeek, .pawCheck, .bugWatch]

    // MARK: scheduler

    /// The one call that rolls the hangout emotes (`idleMaybeStart`, next to the batch-2 treat roll). True = one started.
    func hangoutMaybeStart(_ sim: SoftBody) -> Bool {
        guard HangoutTuning.enabled, anticsEnabled, !idleBlocked, treat2Free, idleNight < HangoutTuning.nightStop else { return false }
        if hang.next < 0 {
            hang.rngS = (hang.rngS ^ (seed &* 0x9E3779B97F4A7C15)) | 1
            hang.next = variety.now + hang.rnd(HangoutTuning.firstGap.lowerBound, HangoutTuning.firstGap.upperBound) + 9 * Float(steerID % 4)
            return false
        }
        guard variety.now >= hang.next else { return false }
        let night = 1 + 3 * min(1, idleNight / HangoutTuning.nightStop)
        let cooling = kindCooling
        let pool = IdleKind.allCases.filter { Self.hangoutKinds.contains($0) && $0 != hang.last && !cooling.contains($0) && !varietyPeerJustStarted($0) && !othersDoing($0) }
        guard !pool.isEmpty else { hang.next = variety.now + 4; return false }
        let kind = pool[min(pool.count - 1, Int(hang.rnd() * Float(pool.count)))]
        let family = variety.lastFamily          // (the old moves' "same family twice" damping must not see this)
        guard idleStart(kind, sim) else { hang.next = variety.now + 5; return false }
        variety.lastFamily = family
        hang.last = kind
        hang.plays[kind, default: 0] += 1
        kindCooldownStart(kind)
        hang.next = variety.now + hang.rnd(HangoutTuning.gap.lowerBound, HangoutTuning.gap.upperBound) * night
        return true
    }

    // MARK: start

    func hangoutBegin(_ kind: IdleKind, _ sim: SoftBody) -> Bool {
        idleBegin(kind)
        script = .idle
        activity = kind == .humTune || kind == .bigStretch || kind == .bugWatch ? .playing : .lookingAround
        idleState.k = 0; idleState.steps = 0; idleState.hop = 0; idleState.jackA = 0; idleState.reps = 0; idleState.hold = 0
        sig = SignatureDrive()
        let cam = faceCameraYaw(), s = idleState.sign
        switch kind {
        case .curiousPeek: idleState.goalYaw = cam + s * hang.rnd(1.2, 1.9)          // (a room direction away from the player)
        default: idleState.goalYaw = cam + s * hang.rnd(0.5, 0.8)          // (three-quarter view, either side)
        }
        hang.turnLeft = kind == .tailPeek ? 2.3 : 0
        switch kind {
        case .humTune, .bigStretch: hang.voiceOn = true
        case .curiousPeek, .bugWatch: hang.voiceOn = hang.rnd() < HangoutTuning.voiceChance
        default: hang.voiceOn = false          // (pawCheck, tailPeek: silent)
        }
        idleState.phase = 0; idleState.phaseT = 0
        return true
    }

    // MARK: run

    private func hOnce(_ bit: Int, _ t: Float, at t0: Float) -> Bool {
        guard t >= t0, idleState.steps & (1 << bit) == 0 else { return false }
        idleState.steps |= 1 << bit
        return true
    }

    private func hDone(_ skinner: Skinner) {
        runAir = 0; armDirW = 0; armDirOut = 0; twist = 0
        skinner.setEyeOpenness(1)
        mouthOpen = 0
        idleFinish(skinner)
    }

    /// One soft haptic beat ("<move>.<beat>" in `EmoteTreats.haptics`).
    /// The room limiter: one hangout cue per `HangoutTuning.cueGap` s across all Jelbies (the two beats of ONE emote, bigStretch's peak and release, are exempt). Uses the haptic clock.
    func hangoutCueAllowed() -> Bool {
        let now = HapticDriver.clock()
        if now - HangoutTuning.lastCue >= HangoutTuning.cueGap || (HangoutTuning.lastOwner == steerID && HangoutTuning.lastKind == idleState.kind) {
            HangoutTuning.lastCue = now; HangoutTuning.lastOwner = steerID; HangoutTuning.lastKind = idleState.kind
            return true
        }
        return false
    }
    /// The ONE key-moment cue of an emote (`EmoteTreats.haptics`, one pulse; bigStretch two cues of one pulse).
    private func hHaptic(_ key: String, energy: Float = 1) { if hangoutCueAllowed() { treatHaptic(key, energy: energy) } }

    private func hVoice(_ v: JellyVoice) {
        guard !voiceMuted, hang.voiceOn else { return }
        if AudioHub.shared.hangoutVoice(jelly: steerID, v, x: px), let k = idleState.kind { hang.voices[k, default: 0] += 1 }
    }

    private func hBump(_ t: Float, _ lo: Float, _ hi: Float) -> Float { t > lo && t < hi ? sinf(.pi * (t - lo) / (hi - lo)) : 0 }

    func runHangout(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let kind = idleState.kind else { return }
        runAir = 0
        // the old cycle goes on counting while he is busy with this (add, never displace)
        idleState.cooldown -= dt; zoomUrge -= dt; idleState.treat -= dt
        armWalkWant = (kind == .bigStretch || kind == .pawCheck || kind == .bugWatch) ? 1 : 0
        if idleState.phase == 0 {          // turn to the three-quarter view / the room direction first
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.1)
            gaitPose(sway: 0.04, bob: 0, rock: 0.2)
            if turning || feet.active { idleState.phaseT = 0; return }
            idleState.phase = 1; idleState.phaseT = 0
        }
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        let t = idleState.phaseT
        switch kind {
        case .humTune: runHum(skinner, t)
        case .curiousPeek: runCuriousPeek(skinner, t)
        case .bigStretch: runBigStretch(skinner, t)
        case .tailPeek: runTailPeek(skinner, t)
        case .pawCheck: runPawCheck(skinner, t)
        default: runBugWatch(sim, skinner, t)
        }
    }

    // MARK: humTune

    private func runHum(_ skinner: Skinner, _ t: Float) {
        let a = amplitude, T: Float = 4.0
        let env = smooth01(t / 0.5) * (1 - smooth01((t - (T - 0.6)) / 0.5))
        let w = 2 * Float.pi * 0.55 * t
        roll += 0.07 * env * sinf(w) * a
        twist = 0.06 * env * sinf(w + 1.2) * a
        // a tiny bounce on each beat (every half sway)
        let period: Float = 1 / (2 * 0.55)
        if t > 0.3 {
            let u = (t - 0.3).truncatingRemainder(dividingBy: period)
            squash *= 1 + 0.03 * env * a * (u < 0.25 ? sinf(.pi * u / 0.25) : 0)
        }
        if hOnce(0, t, at: 0.05) { face(.joyArc, hold: T - 0.1) }
        if hOnce(1, t, at: 0.3) { hVoice(.hum); hHaptic("humTune.hum") }
        if t > T && !feet.active { hDone(skinner) }
    }

    // MARK: curiousPeek

    private func runCuriousPeek(_ skinner: Skinner, _ t: Float) {
        let a = amplitude, T: Float = 4.2
        let k = smooth01((t - 0.3) / 0.5) * (1 - smooth01((t - 3.4) / 0.6))
        let b1 = hBump(t, 0.5, 1.3), b2 = hBump(t, 2.0, 2.8)
        pitch += (0.06 * k + 0.07 * b1 + 0.05 * b2) * a          // (forward: a little, then a second smaller lean)
        roll += idleState.sign * 0.12 * k * a          // (the head tilt)
        squash *= 1 + 0.02 * (b1 + b2) * a
        if hOnce(0, t, at: 0.4) { face(.curious, hold: 3.0) }
        if hOnce(1, t, at: 0.6) { hVoice(.ooh); hHaptic("curiousPeek.lean") }
        if t > T && !feet.active { hDone(skinner) }
    }

    // MARK: bigStretch

    private func runBigStretch(_ skinner: Skinner, _ t: Float) {
        let a = amplitude, T: Float = 4.0
        let up = smooth01(t / 0.9) * (1 - smooth01((t - 2.3) / 0.7))
        let shiver: Float = (t > 1.1 && t < 2.2) ? 0.012 * sinf(2 * .pi * 9 * t) * up : 0
        squash *= 1 + 0.15 * up * a + shiver          // (taller, the feet stay planted: no lift)
        pitch += -0.06 * up * a
        armDirW = smooth01(t / 0.5) * (1 - smooth01((t - 2.8) / 0.4))
        armDirEl = [0.95, 0.95]; armDirSa = [0.12, 0.12]; armDirOut = 0.07
        // the drop back: a soft settle wobble
        if t > 3.0 {
            let s = t - 3.0, e = expf(-s / 0.4)
            twist = 0.05 * e * sinf(2 * .pi * 4 * s) * a
            squash *= 1 + 0.03 * e * sinf(2 * .pi * 3.5 * s) * a
        }
        skinner.setEyeOpenness(1 - 0.55 * up)
        if hOnce(0, t, at: 0.1) { face(.happy, hold: T - 0.4) }
        if hOnce(1, t, at: 1.1) { hHaptic("bigStretch.top") }
        if hOnce(2, t, at: 3.0) { hVoice(.aww); hHaptic("bigStretch.settle"); jellyKick = max(jellyKick, 0.8); blushBump(hold: 2.0, peak: 0.5) }
        if t > T && !feet.active { hDone(skinner) }
    }

    // MARK: tailPeek

    private func runTailPeek(_ skinner: Skinner, _ t: Float) {
        let a = amplitude
        let d = idleState.sign          // (the way round he turns; the head leads it)
        let stopped = idleState.hold > 0
        let lead = stopped ? 1 - smooth01((t - idleState.hold) / 0.4) : smooth01(t / 0.4)
        twist = d * 0.35 * lead * a
        if hOnce(0, t, at: 0.05) { face(.curious, hold: 3.4) }
        if hOnce(3, t, at: 0.6) { hHaptic("tailPeek.look") }          // (the look over the shoulder, as he starts to turn)
        if !stopped {
            // the half circle: short turn-in-place legs until it is done (or the time is up)
            if t > 0.5, !feet.active {
                if hang.turnLeft > 0.05, t < 3.4 {
                    let step = min(0.85, hang.turnLeft)
                    hang.turnLeft -= step
                    idleState.goalYaw = yaw + d * step
                    _ = turnSteps(goal: idleState.goalYaw, tol: 0.05)
                } else { idleState.hold = max(0.01, t) }
            }
            return
        }
        // stopped: puzzled, a small shrug-bounce
        let s = t - idleState.hold
        if hOnce(1, t, at: idleState.hold + 0.25) { face(.worried, hold: 1.3) }
        let b = hBump(s, 0.7, 1.0) + hBump(s, 1.05, 1.35)
        squash *= 1 + 0.04 * b * a
        pitch += -0.03 * b * a
        if hOnce(2, t, at: idleState.hold + 0.7) { jellyKick = max(jellyKick, 0.6) }          // (the shrug-bounce)
        if s > 1.8 && !feet.active { hDone(skinner) }
    }

    // MARK: pawCheck

    private func runPawCheck(_ skinner: Skinner, _ t: Float) {
        let a = amplitude, T: Float = 4.8
        let first = idleState.sign < 0 ? 0 : 1, second = 1 - first
        armDirW = smooth01(t / 0.25) * (1 - smooth01((t - 4.2) / 0.3))
        armDirOut = 0.05
        var look: Float = 0
        let wins: [(Int, Float, Float)] = [(first, 0.4, 2.0), (second, 2.0, 3.6)]
        for (i, wa, wb) in wins {
            let e = smooth01((t - wa) / 0.3) * (1 - smooth01((t - wb) / 0.3))
            let wig: Float = (t > wa + 0.4 && t < wa + 1.2) ? sinf(2 * .pi * 2.5 * (t - wa - 0.4)) : 0          // (two wiggles)
            armDirEl[i] = -0.05 + 0.65 * e
            armDirSa[i] = 0.5 + 0.3 * e + 0.25 * e * wig
            look = max(look, e)
        }
        pitch += 0.08 * look * a          // (looks down at it)
        // the pleased little nod
        pitch += 0.07 * (hBump(t, 3.7, 4.0) + hBump(t, 4.05, 4.35)) * a
        if hOnce(0, t, at: 0.3) { face(.focused, hold: 3.3) }
        if hOnce(1, t, at: 0.5) { hHaptic("pawCheck.raise") }
        if hOnce(2, t, at: 3.7) { face(.happy, hold: 1.2); blushBump(hold: 2.0, peak: 0.5) }
        if t > T && !feet.active { hDone(skinner) }
    }

    // MARK: bugWatch

    private func runBugWatch(_ sim: SoftBody, _ skinner: Skinner, _ t: Float) {
        let a = amplitude
        // the head follows the fly: left, right, up
        let left = smooth01((t - 0.3) / 0.5), right = smooth01((t - 1.3) / 0.6), mid = smooth01((t - 2.2) / 0.4), up = smooth01((t - 2.5) / 0.5)
        twist = (-0.42 * left + 0.84 * right - 0.42 * mid) * a
        pitch += -0.14 * up * a
        roll += 0.03 * sinf(2 * .pi * 0.6 * t) * a
        if hOnce(0, t, at: 0.15) { face(.focused, hold: 3.4) }
        if hOnce(1, t, at: 3.2) { face(.surprised, hold: 0.8); hVoice(.eep); jellyKick = max(jellyKick, 0.7) }
        if t >= 3.75, !feet.active {
            // the grab: the joy hop's machinery takes the body (feet reset, in-place hop); the arm and the giggle are in `bugHopTick`
            idleState.target = position
            idleState.reps = 1; idleState.hop = 0; idleState.landT = 0
            idleState.phase = 2; idleState.phaseT = 0; idleState.steps = 0
            twist = 0; armDirW = 0
            script = .idle; activity = .playing
            idleScootHop(sim)
            hHaptic("bugWatch.hop")
        }
    }

    /// While the hop runs (`idleBodyMoveTick`): one arm up, then the giggle as he comes down empty-handed.
    func bugHopTick() {
        armDirW = smooth01(min(1, idleState.phaseT / 0.1))
        armDirEl = [0.95, -0.05]; armDirSa = [0.10, 0.50]; armDirOut = 0.06
        if hOnce(5, idleState.phaseT, at: 0.3) { face(.joyArc, hold: 1.0); hVoice(.giggle) }
    }
}
