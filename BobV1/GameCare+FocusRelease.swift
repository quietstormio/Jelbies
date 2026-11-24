//
//  GameCare+FocusRelease.swift
//  come-here-freeze-r1 (the owner, 2026-11-23: "Pink has not moved at all after I started them come here to cuddle then I cancelled it ... closing the app fixed it").
//
//  1. `handBackEveryone`: when a call ends without a close-up (the Cancel pill, "Let go" from the walk, the approach giving up), EVERY Jelmiko the call touched gets his life
//     back in one place: autonomy (Jelly 0's too: his was only ever given back on the camera's way out), the row's steering gap, the walk's finish hook, the group forgotten.
//  2. `focusNetTick`: the safety net, independent of the cause. A Jelmiko whose autonomy the close-up switched off (`FocusGroup.took`) and who is still off after
//     `focusNetAfter` s with NO close-up and NO approach on is released, with one console line: `[stuck] released id=... was=...`.
//     It never touches a body that something else holds (a clean-up, a meal / group serving, a trip, a race, a newcomer's welcome, a pair or group moment, sleep).
//

import Foundation

extension GameCare {
    /// Seconds a forgotten hold must last (close-up off, nobody walking to it) before the net lets go.
    static let focusNetAfter: Float = 4
    var focusNetReleased: Int { focusGroup.netReleased }
    /// The close-up switched this Jelmiko's autonomy off (the net's record; the hand-back removes it).
    func focusTook(_ id: Int) { focusGroup.took[id] = 0 }

    /// The call is over (phase roaming): give everybody back, once.
    func handBackEveryone() {
        let g = focusGroup
        guard focus.phase == .roaming else { return }
        for (id, a) in g.saved { brainFor(id)?.autonomy = a; g.took[id] = nil }
        g.saved = [:]
        for (id, gp) in g.gapSaved { brainFor(id)?.peerGap = gp }
        g.gapSaved = [:]
        for id in g.ids where id != 0 { brainFor(id)?.onFinished = nil }
        if g.took[0] != nil, let b0 = brainFor(0) {          // Jelly 0 waited on his spot for the others (`enterFocus`) and the walk was called off: his autonomy was never handed back
            b0.autonomy = savedAutonomy; g.took[0] = nil; wantHop = false
            if !b0.autonomy { NSLog("[stuck] hand-back id=0 saved autonomy was off") }
        }
        g.clear()
    }

    /// The safety net, once per fixed step (Jelly 0's tick).
    func focusNetTick(brain: BlobBrain, dt: Float) {
        let g = focusGroup
        guard FocusGroup.netEnabled, !g.took.isEmpty else { return }
        guard focus.phase == .roaming else { for k in g.took.keys { g.took[k] = 0 }; return }          // (a call or a close-up is on: the clock waits)
        let held = bath.active || tripActive || raceBusy || trayOut || groupActive || newcomerWelcome != nil || isPreview || show.onStage
        for (id, t) in g.took {
            guard let b = brainFor(id) else { g.took[id] = nil; continue }
            if b.autonomy { g.took[id] = nil; continue }          // (free again: nothing to do)
            if held || b.isSleeping || b.social != nil || b.reserved || b.commandedIdle != nil { g.took[id] = 0; continue }
            g.took[id] = t + dt
            guard t + dt >= Self.focusNetAfter else { continue }
            NSLog("[stuck] released id=%d was=autonomy-off phase=%@ ids=%@ saved=%@ job=%@ cmd=%d", id, String(describing: focus.phase), String(describing: g.ids), String(describing: g.saved), b.job == nil ? "-" : "Y", b.commanded ? 1 : 0)
            b.autonomy = true; b.restTimer = min(b.restTimer, 0.5)
            if b.commanded, b.job == nil, b.pending == nil, b.scriptIsNone { b.commanded = false }
            g.took[id] = nil; g.netReleased += 1
        }
    }
}
