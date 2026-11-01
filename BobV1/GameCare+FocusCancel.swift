//
//  GameCare+FocusCancel.swift
//  The Cancel pill's work: any group action that takes the Jelbies somewhere (come here / call everyone walking to the spots, a group serving, a group
//  bedtime walk) can be called off from its first second. Everyone goes back to roaming and the normal HUD returns.
//

import Foundation

extension GameCare {
    /// Somebody was told to go to bed and has not lain down yet.
    var bedtimeWalking: Bool {
        !nightRest.wanted.isEmpty && raceBook.actors.contains { a in
            guard nightRest.wanted.contains(a.id), let b = a.brain else { return false }
            return b.commandedGoodnight || (b.isSleeping && b.sleep.k < 0.05 && !b.sleep.wakeAsked)          // told to, or on his way to his bed (not yet down)
        }
    }

    /// The Cancel pill: calls the running group action off. Reuses `release()` (the "Let them go" path) for the close-up walk.
    func cancelGroupAction() {
        if focus.phase == .approaching {
            for id in focusGroup.ids where id != 0 {
                if let b = brainFor(id) { b.pending = nil; b.interruptScript = true }
            }
            release()
        }
        if groupActive { cancelGroup() }
        if bedtimeWalking {
            let ids = raceBook.actors.filter { a in nightRest.wanted.contains(a.id) && (a.brain.map { $0.commandedGoodnight || ($0.isSleeping && $0.sleep.k < 0.05) } ?? false) }.map(\.id)
            for id in ids { wakeSleeper(id, groggy: false) }
            nightRest.wanted.subtract(ids); nightRest.dayOnce.subtract(ids)
        }
        if cancelPill { cancelPill = false }
    }
}
