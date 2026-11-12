//
//  BlobBrain+Tricks.swift
//  Shop tricks that are new moves (trick plan, stage 1: Sing). A trick-only IdleKind: never in the idle / treat tables, only started by a command
//  (voice, the Show, the Tricks button). Standing pose move: feet planted, `runIdle` drives it like the emotes.
//
//  SING   0 turn to the camera, 1 a breath (0.25 s), 2 the song (`SingTuning.notes`: the mouth opens on each note, the head lifts with its height,
//         a sway on the beat, the last note held with the head back and the arms a little out), 3 a small bow and a blush.
//         The voice is `AudioHub.sing(jelly:x:)`: `sing_jelly{n}` when that file exists, otherwise the `lala_jelly{n}` placeholder.
//

import Foundation

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
                pitch -= 0.03 * h * n.env * a
                if idleState.hop != n.index + 1 { idleState.hop = n.index + 1; jellyKick = max(jellyKick, 0.4 + 0.3 * h) }
            } else { mouthOpen = 0 }
            roll += 0.05 * sinf(2 * .pi * song / 0.76) * a
            // the held last note: head back, arms a little out, up on the toes
            let lastOn = SingTuning.notes.last?.onset ?? 0
            let hold = smooth01((song - lastOn) / 0.2) * (1 - smooth01((song - SingTuning.length + 0.1) / 0.2))
            pitch -= 0.10 * hold * a
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
