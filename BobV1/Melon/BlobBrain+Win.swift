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
    static var winApex: Float { WinTuning.apex }
    static let winLandHold: Float = 0.12
    static let winSettle: Float = 0.5

    /// `idleStart(.joy)` with `winCheer` set: four reps, the big face and the cheer.
    func winBegin() {
        if Self.idleLog { NSLog("[melon] win celebration begins (slot %d, race %@)", steerID, race.active ? "yes" : "no") }          // capture aid (-VoiceLog 1): proves it started in the real app
        gait.landDepth = WinTuning.landDepth          // (a deeper squash on every landing: the bounce reads at the race camera's distance; `idleEnd` puts 0.2 back)
        idleState.reps = Self.winHops
        idleState.baseYaw = yaw
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
        guard DevArgs.enabled, UserDefaults.standard.object(forKey: key) != nil else { return def }
        return Float(UserDefaults.standard.double(forKey: key))
    }
    /// The arms-up pose: elevation above the horizontal (rad), sweep (0 = in the plane of the shoulders, so a camera looking down on him still sees them rise; the jacks' 0.10 swings them toward the camera and flattens them), and how far the stub stands out of the body (u).
    static let armEl: Float = v("WinArmEl", 0.85)
    static let armSa: Float = v("WinArmSa", 0.0)
    static let armOut: Float = v("WinArmOut", 0.17)
    /// Apex of a bounce (u; the plain joy is 0.12) and the landing squash.
    static let apex: Float = v("WinApex", 0.26)
    static let landDepth: Float = v("WinLandDepth", 0.30)
}
