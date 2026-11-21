//
//  BlobBrain+Win.swift
//  The WIN celebration (owner 2026-11-19: "when your Jelmikos wins first place make them bounce and lift little arms up and celebrate winning").
//  It is the existing jump for joy (`.joy`, BlobBrain+Flourish.swift: the hop machinery of `idleBodyMoveTick` and the jacks' arms-up pose, no new pose) run longer:
//  four tall bounces (apex `winApex`, a beat on the ground between them), the arms held up the whole time (the same stubby arms-up pose as the jacks / the joy: El 0.95, Sa 0.10),
//  a big happy face, a cheer in his own voice (`AudioHub.winVoice`), and a settle (the arms ease down over `winSettle`). About 3 s. Only the player's own Jelmiko, only at a first place.
//  `winCheer = true` before `idleStart(.joy)` turns it on; `idleEnd` clears it (so a cut - Done, a pick-up, a new command - leaves nothing behind).
//

import Foundation
import simd

extension BlobBrain {
    /// Bounces of the celebration, the apex of each (u; the plain joy is one hop of 0.12), the pause on the ground between two, and the arms' ease down at the end (s).
    static let winHops = 4
    /// The bounce's apex for THIS body's jiggle level (the skin's wobble at the strongest level makes the leash move a foot piece on a tall landing: RacePullFlowTests).
    func winApexNow() -> Float { WinTuning.apex(level: skinnerRef?.jelly.level ?? JellyJiggle.sharedLevel) }
    static let winLandHold: Float = 0.05
    static let winSettle: Float = 0.5

    /// `idleStart(.joy)` with `winCheer` set: four reps, the big face and the cheer.
    func winBegin() {
        if Self.idleLog { NSLog("[melon] win celebration begins (slot %d, race %@)", steerID, race.active ? "yes" : "no") }          // capture aid (-VoiceLog 1): proves it started in the real app
        gait.landDepth = WinTuning.landDepth          // (a deeper squash on every landing: the bounce reads at the race camera's distance; `idleEnd` puts 0.2 back)
        idleState.reps = Self.winHops
        winRoot = poseW > 0 ? SIMD2(px, pz) : nil; winPitch0 = pitchBase          // (the stance he goes back to when the bounces end: see the settle in `idleBodyMoveTick`)
        idleState.baseYaw = yaw
        winFlat = (skinnerRef?.jelly.level ?? JellyJiggle.sharedLevel) >= 2          // (the strongest jiggle: squash pulses on planted feet, no hops)
        blushBump(hold: 3.4, peak: 0.9)
        face(.joyArc, hold: 3.2)          // (the happy ^^ eyes, brows up, an open smile: `expressionTick` holds it for the whole move whatever his mood / needs / the race's focused brow)
        if !voiceMuted { AudioHub.shared.winVoice(jelly: steerID, x: px) }
    }

    /// Starts the celebration on a standing body now. False = he is busy (nothing is changed).
    @discardableResult
    func winStart(_ sim: SoftBody) -> Bool {
        guard idleState.kind == nil else { return false }
        winCheer = true; winSettleT = 0
        commanded = true
        if idleStart(.joy, sim) { return true }
        winCheer = false; commanded = false
        return false
    }

    /// The flat win (jiggle level 2): `winHops` squash pulses on planted feet with the same arms, face and cheer, then the arms ease down. From `runIdle` (`.joy` with `winCheer && winFlat`).
    func runWinFlat(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let t = idleState.phaseT
        let period: Float = 0.62, body = Float(Self.winHops) * period
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        activity = .playing
        if t < body {
            squash *= 1 + 0.06 * sinf(2 * .pi * t / period)
            let beat = Int(t / period)
            if beat >= idleState.hop { idleState.hop = beat + 1; jellyKick = max(jellyKick, 1.4) }          // (a skin kick on every pulse)
        } else { winSettleT += dt }
        armWalkWant = 1
        let wig = 0.06 * sinf(2 * .pi * 2.5 * t)
        armDirW = smooth01(min(1, t / 0.12)) * (1 - smooth01(winSettleT / Self.winSettle))
        armDirEl = [WinTuning.armEl + wig, WinTuning.armEl - wig]; armDirSa = [WinTuning.armSa, WinTuning.armSa]; armDirOut = WinTuning.armOut
        if winSettleT >= Self.winSettle && !feet.active { armDirW = 0; idleFinish(skinner) }
    }

    /// Race: the player crossed the line first (place 1 is final then; the results card covers the track a few seconds later). He celebrates as soon as his feet are planted between coast steps (queued until then; the race card never waits for it).
    func raceWinCue(_ sim: SoftBody) { if Self.idleLog { NSLog("[melon] win celebration asked at the finish (slot %d)", steerID) }; race.winQueued = true; _ = raceWin(sim) }

    @discardableResult
    func raceWin(_ sim: SoftBody) -> Bool {
        guard race.active, raceCanLook, idleState.kind == nil else { return false }
        race.winQueued = false
        if winStart(sim) { restTimer = max(restTimer, 1); return true }
        return false
    }
}

/// The numbers of the win move. The defaults are what ships; with developer arguments on (simulator / dev builds only) `-WinArmEl`, `-WinArmSa`, `-WinArmOut`,
/// `-WinApex`, `-WinLandDepth` change them for a capture session without a rebuild.
nonisolated enum WinTuning {
    private static func v(_ key: String, _ def: Float) -> Float {
        guard DevArgs.enabled else { return def }
        if let e = ProcessInfo.processInfo.environment["WIN_" + key], let f = Float(e) { return f }          // (test sweeps: TEST_RUNNER_WIN_<key>=...)
        guard UserDefaults.standard.object(forKey: key) != nil else { return def }
        return Float(UserDefaults.standard.double(forKey: key))
    }
    /// The arms-up pose: elevation above the horizontal (rad), sweep (0 = in the plane of the shoulders, so a camera looking down on him still sees them rise; the jacks' 0.10 swings them toward the camera and flattens them), and how far the stub stands out of the body (u).
    static let armEl: Float = v("WinArmEl", 0.85)
    static let armSa: Float = v("WinArmSa", 0.0)
    static let armOut: Float = v("WinArmOut", 0.17)
    /// Apex of a bounce (u; the plain joy is 0.12) and the landing squash.
    static let apex: Float = v("WinApex", 0.23)
    /// Apex by jiggle level: level 0 and 1 (the shipped default) keep `apex`; the strongest level 2 gets `apexL2`.
    static let apexL1: Float = v("WinApexL1", 0.23)
    static let apexL2: Float = v("WinApexL2", 0.16)
    static func apex(level: Int) -> Float { level >= 2 ? apexL2 : level == 1 ? apexL1 : apex }
    static let landDepth: Float = v("WinLandDepth", 0.20)
}
