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
    static let winApex: Float = 0.16
    static let winLandHold: Float = 0.16
    static let winSettle: Float = 0.5

    /// `idleStart(.joy)` with `winCheer` set: four reps, the big face and the cheer.
    func winBegin() {
        idleState.reps = Self.winHops
        blushBump(hold: 3.4, peak: 0.9)
        face(.excited, hold: 3.2)
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
    func raceWinCue(_ sim: SoftBody) { race.winQueued = true; _ = raceWin(sim) }

    @discardableResult
    func raceWin(_ sim: SoftBody) -> Bool {
        guard race.active, raceCanLook, idleState.kind == nil else { return false }
        race.winQueued = false
        if winStart(sim) { restTimer = max(restTimer, 1); return true }
        return false
    }
}
