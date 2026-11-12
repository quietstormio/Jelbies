//
//  BlobBrain+Tricks.swift
//  Shop tricks that are new moves (trick plan, stage 1: Sing). A trick-only IdleKind: never in the idle / treat tables, only started by a command
//  (voice, the Show, the Tricks button). Standing pose move: feet planted, `runIdle` drives it like the emotes.
//
//  Stage 2 (trick plan): HULA (below), SUPER SPRING and CORKSCREW (BlobBrain+TrickHops.swift), ONE-LEG SPIN (below).
//
//  SING   0 turn to the camera, 1 a breath (0.25 s), 2 the song (`SingTuning.notes`: the mouth opens on each note, the head lifts with its height,
//         a sway on the beat, the last note held with the head back and the arms a little out), 3 a small bow and a blush.
//         The voice is `AudioHub.sing(jelly:x:)`: `sing_jelly{n}` when that file exists, otherwise the `lala_jelly{n}` placeholder.
//

import Foundation
import simd

/// The song's timing. EDIT HERE when the real tune arrives: one row per note (seconds from the start of the song, length, height 0...1 = how high the head goes).
nonisolated enum SingTuning {
    static let notes: [(onset: Float, dur: Float, height: Float)] = [
        (0.00, 0.30, 0.4), (0.38, 0.30, 0.6), (0.76, 0.30, 0.8), (1.14, 0.25, 0.5), (1.45, 0.25, 0.7), (1.78, 0.62, 1.0),
    ]
    /// The song's length (the last note's end).
    static var length: Float { notes.last.map { $0.onset + $0.dur } ?? 2.4 }
    static let breath: Float = 0.25
    static let bow: Float = 0.45
    /// Mouth opening while a note sounds (0...0.65) and its attack / release (s).
    static let mouth: Float = 0.45, attack: Float = 0.04, release: Float = 0.08
    /// Seconds of the whole move after the turn (breath + song + bow), for the Show's timing and the tests.
    static var total: Float { breath + length + bow }
    /// The note sounding at song time `t`: (index, 0...1 envelope), or nil between notes.
    static func note(at t: Float) -> (index: Int, env: Float)? {
        for (i, n) in notes.enumerated() where t >= n.onset && t < n.onset + n.dur {
            let e = min(1, (t - n.onset) / attack) * min(1, (n.onset + n.dur - t) / release)
            return (i, max(0, e))
        }
        return nil
    }
}

extension BlobBrain {
    /// From `idleStart`: the turn to the camera first (phase 0).
    func singBegin(_ sim: SoftBody) -> Bool {
        idleBegin(.sing)
        script = .idle; activity = .playing
        idleState.steps = 0; idleState.hop = 0
        idleState.goalYaw = faceCameraYaw()
        idleState.phase = 0
        return true
    }

    private func singOnce(_ bit: Int) -> Bool {
        guard idleState.steps & (1 << bit) == 0 else { return false }
        idleState.steps |= 1 << bit
        return true
    }

    func runSing(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let a = amplitude
        if idleState.phase == 0 {
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.1)
            gaitPose(sway: 0.04, bob: 0, rock: 0.2)
            if turning || feet.active { idleState.phaseT = 0; return }
            idleState.phase = 1; idleState.phaseT = 0
        }
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        armWalkWant = 0
        let t = idleState.phaseT                                        // seconds since the turn ended
        let song = t - SingTuning.breath                                // seconds into the song
        let end = SingTuning.breath + SingTuning.length
        // 1. the breath in
        let breathK = smooth01(t / SingTuning.breath) * (1 - smooth01((t - SingTuning.breath) / 0.1))
        pitch -= 0.06 * breathK * a
        squash *= 1 + 0.04 * breathK * a
        if singOnce(0) { skinner.setEyeOpenness(0.8); face(.happy, hold: SingTuning.total + 0.4) }
        if song >= 0, song < SingTuning.length + 0.1 {
            if singOnce(1) { AudioHub.shared.sing(jelly: steerID, x: px) }
            // 2. the notes: mouth, a squash pulse, the head up with the note's height; the sway follows the beat
            if let n = SingTuning.note(at: song) {
                let h = SingTuning.notes[n.index].height
                mouthOpen = SingTuning.mouth * n.env * (0.8 + 0.2 * h)
                squash *= 1 + 0.03 * n.env * a
                pitch -= 0.05 * h * n.env * a
                if idleState.hop != n.index + 1 { idleState.hop = n.index + 1; jellyKick = max(jellyKick, 0.4 + 0.3 * h) }
            } else { mouthOpen = 0 }
            roll += 0.07 * sinf(2 * .pi * song / 0.76) * a
            // the held last note: head back, arms a little out, up on the toes
            let lastOn = SingTuning.notes.last?.onset ?? 0
            let hold = smooth01((song - lastOn) / 0.2) * (1 - smooth01((song - SingTuning.length + 0.1) / 0.2))
            pitch -= 0.14 * hold * a
            squash *= 1 + 0.05 * hold * a
            armDirW = hold; armDirOut = 0.03
            for s in 0..<2 { armDirEl[s] = 0.35; armDirSa[s] = s == 0 ? 0.9 : -0.9 }
        } else { mouthOpen = 0 }
        // 3. the little bow and a blush
        if t >= end {
            let u = t - end
            let k = smooth01(u / 0.2) * (1 - smooth01((u - 0.2) / 0.25))
            pitch += 0.12 * k * a
            armDirW = 0
            if singOnce(2) { skinner.setEyeOpenness(1); blushBump(hold: 2.0, peak: 0.5) }
            if u > SingTuning.bow, !feet.active { mouthOpen = 0; armDirW = 0; armDirOut = 0; skinner.setEyeOpenness(1); idleFinish(skinner) }
        }
    }
}

// MARK: - stage 2

/// The running stage-2 trick's own state (stored in `IdleState.trick`; reset by `trickBegin`).
struct TrickIdle {
    /// Hula: the root he circles round. Jumps / spin: the root and heading at the start (restored at the end).
    var base = SIMD2<Float>.zero
    var root = SIMD3<Float>.zero
    /// This run is the Show's flop (read once from `IdleState.trickFailNext`).
    var fail = false
    /// Smoothed arm targets (el, sa, out) and the arm weight.
    var el: Float = 0, sa: Float = 0, out: Float = 0, armA: Float = 0
    /// The twist the gait last carried (a short corkscrew folds it into the heading at the end).
    var twist: Float = 0
    /// Free counter / flags of the move.
    var stage = 0
    var flags = 0
}

/// HULA: the hips circle round and round with the feet planted, speeding up; the head stays over the spot (a counter-tilt), the arms sway, then a ta-da.
nonisolated enum HulaTuning {
    /// Seconds of circling at full size (the clean one / the Show's flop), the settle back to the spot, and the ta-da.
    static let swing: Float = 2.9, failSwing: Float = 2.0, settle: Float = 0.3, tada: Float = 0.5
    /// The circling speed (Hz) at the start and the end of the swing; the flop speeds up further.
    static let f0: Float = 0.9, f1: Float = 2.2, f1Fail: Float = 3.3
    /// The hip circle's radius (u) at the start and the end of the swing (the flop's end).
    nonisolated(unsafe) static var r0: Float = 0.080, r1: Float = 0.150, r1Fail: Float = 0.170
    /// 1 = the head stays exactly over the spot (the counter-tilt cancels the base's circle); the height of the head above the soles (u).
    nonisolated(unsafe) static var counter: Float = 1.0
    static let headHeight: Float = 0.9
    static var total: Float { swing + settle + tada }
    static func f1(fail: Bool) -> Float { fail ? f1Fail : f1 }
    /// Cycles of the circle after `s` seconds (the speed ramps linearly f0 -> f1 over the swing, then holds).
    static func cycles(_ s: Float, fail: Bool = false) -> Float {
        let sw = fail ? failSwing : swing, e = f1(fail: fail)
        let u = min(s, sw)
        return f0 * u + (e - f0) * u * u / (2 * sw) + max(0, s - sw) * e
    }
    /// Seconds at which the circle has made `c` cycles (strips are cut by hip phase, not by even time: a speed-up aliases).
    static func time(forCycles c: Float, fail: Bool = false) -> Float {
        var lo: Float = 0, hi: Float = 20
        for _ in 0..<40 { let m = (lo + hi) / 2; if cycles(m, fail: fail) < c { lo = m } else { hi = m } }
        return (lo + hi) / 2
    }
}

extension BlobBrain {
    /// How long a stage-2 move runs after its turn to the camera (seconds): what the Show's stage must give it (ShowTrickInfo.seconds), and the tests' check.
    static func trickMoveSeconds(_ k: IdleKind) -> Float? {
        switch k {
        case .hula: return HulaTuning.total
        case .superSpring: return SpringTuning.total
        default: return nil
        }
    }

    /// From `idleStart` for a stage-2 move that runs through `runIdle` / its own tick: the turn to the camera first (phase 0).
    func trickBegin(_ kind: IdleKind, _ sim: SoftBody) -> Bool {
        idleBegin(kind)
        script = .idle; activity = .playing
        idleState.steps = 0; idleState.hop = 0
        idleState.trick = TrickIdle()
        idleState.trick.fail = idleState.trickFailNext; idleState.trickFailNext = false
        idleState.goalYaw = faceCameraYaw()
        idleState.phase = 0
        return true
    }

    private func trickOnce(_ bit: Int) -> Bool {
        guard idleState.steps & (1 << bit) == 0 else { return false }
        idleState.steps |= 1 << bit
        return true
    }

    /// The Show's flop, trick-made: the move ends in the dizzy wobble (like `dizzyFollowOn`, without its dice).
    func trickDizzyFollow(_ sim: SoftBody) {
        currentPose(sim)
        idleBegin(.dizzyWobble)
        script = .idle; activity = .playing
        idleState.phase = 1; idleState.phaseT = 0; idleState.steps = 0; idleState.hop = 0; idleState.jackA = 0
        sig = SignatureDrive()
        mouthOpen = 0
    }

    // MARK: hula

    func runHula(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let a = amplitude
        if idleState.phase == 0 {
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.1)
            gaitPose(sway: 0.04, bob: 0, rock: 0.2)
            if turning || feet.active { idleState.phaseT = 0; return }
            idleState.phase = 1; idleState.phaseT = 0
            idleState.trick.base = SIMD2(px, pz)
        }
        armWalkWant = 0
        let fail = idleState.trick.fail
        let sw = fail ? HulaTuning.failSwing : HulaTuning.swing
        let t = idleState.phaseT
        let env = smooth01(t / 0.3) * (1 - smooth01((t - sw) / HulaTuning.settle))
        if trickOnce(0) {
            skinner.setEyeOpenness(0.2); face(.happy, hold: HulaTuning.total + 0.4)
            AudioHub.shared.chirp(jelly: steerID, .happy, x: px)
        }
        if t < sw + HulaTuning.settle + 0.05 {
            // the hips: the base of the body circles round the spot (the soles stay planted: driveLimbs pins them), faster and bigger as it goes
            let phi = 2 * .pi * HulaTuning.cycles(t, fail: fail)
            let r1 = fail ? HulaTuning.r1Fail : HulaTuning.r1
            let r = (HulaTuning.r0 + (r1 - HulaTuning.r0) * min(1, t / sw)) * env * a
            let d = SIMD2<Float>(cosf(phi), sinf(phi)) * r
            let base = idleState.trick.base
            let moved = base + rotXZ(d, yaw)
            px = moved.x; pz = moved.y
            // the counter-tilt keeps the head over the spot: a roll by dx / h cancels the sideways swing of the crown, a pitch by -dz / h the forward one
            roll += HulaTuning.counter * d.x / HulaTuning.headHeight
            pitch += -HulaTuning.counter * d.y / HulaTuning.headHeight
            twist = 0.22 * env * sinf(phi + 0.6) * a
            squash *= 1 + 0.050 * env * sinf(2 * phi) * a
            // the arms sway out and in with the hips (a stub: only the direction turns)
            armDirW = smooth01(env * 3)
            for s in 0..<2 {
                let side: Float = s == 0 ? 1 : -1
                armDirEl[s] = 0.25 + 0.16 * sinf(phi + (s == 0 ? 0 : .pi))
                armDirSa[s] = side * (0.9 + 0.30 * sinf(phi + (s == 0 ? 0.8 : 0.8 + .pi)))
            }
            armDirOut = 0.03
            if idleState.hop != Int(phi / (2 * .pi)) + 1 { idleState.hop = Int(phi / (2 * .pi)) + 1; jellyKick = max(jellyKick, 0.35) }          // a little wobble on every turn of the hips
            if fail && t > sw - 0.4 { twist += 0.18 * smooth01((t - (sw - 0.4)) / 0.4) * sinf(2 * .pi * 3 * t) * a }          // the flop: he loses it
        } else if fail {
            skinner.setEyeOpenness(1)
            trickDizzyFollow(sim)          // the flop spins out into the dizzy wobble
            return
        } else {
            // the ta-da: back on the spot, a little up on the toes, arms up, a kick of jelly and a blush
            px = idleState.trick.base.x; pz = idleState.trick.base.y
            let u = t - (sw + HulaTuning.settle)
            let k = smooth01(u / 0.12) * (1 - smooth01((u - 0.3) / 0.2))
            squash *= 1 + 0.06 * k * a
            armDirW = k; armDirEl = [0.95, 0.95]; armDirSa = [0.2, -0.2]; armDirOut = 0.07
            if trickOnce(1) { skinner.setEyeOpenness(1); face(.joyArc, hold: 1.0); blushBump(hold: 1.6, peak: 0.45); jellyKick = max(jellyKick, 1.5); AudioHub.shared.chirp(jelly: steerID, .happy, x: px) }
            if u > HulaTuning.tada, !feet.active { armDirW = 0; armDirOut = 0; skinner.setEyeOpenness(1); idleFinish(skinner) }
        }
    }
}
