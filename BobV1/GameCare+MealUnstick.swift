//
//  GameCare+MealUnstick.swift
//  night-meal-r1 (the owner, 2026-11-24 00:15: "Food and drink isn't working ... I had to restart app to get it to work. Ensure that never happens again").
//  The meal system has a few locks that only a finished job / a timer clears. If any of them is ever left on (a walk that was cut short and never reported, a tray whose diners are gone), Feed and Water
//  do nothing until the app is relaunched. This is the guarantee, independent of the cause: when the player ASKS for food or water and nothing legitimate holds the meal system (no clean-up, no outing, no
//  close-up), the leftover locks are cleared first, with one console line `[mealunstick] cleared=...` so a future case can be read from a connected phone.
//  It never changes how a meal looks or flows: a live meal (its own timers have not run out) is left exactly as it is.
//

import Foundation

extension GameCare {
    /// A Come call whose walk nobody is walking any more (no job, nothing pending on Jelly 0's brain) is stale after this many seconds of the meal's clock.
    static let staleCallAfter: Float = 6
    /// Dev / test switch: off = the earlier behaviour (a stale lock stays until a relaunch). Tests turn it off to show the bug.
    nonisolated(unsafe) static var unstickOn = true
    /// No real meal (the walk to the tray, the sitting, the second sitting, the poof) lasts this long: past it the lock is a leftover.
    static let staleMealAfter: Float = 240

    /// `callRunning` set, but Jelly 0's brain has no come job in flight: clears it. True when it did.
    @discardableResult
    func clearStaleCall(brain: BlobBrain, why: String) -> Bool {
        guard Self.unstickOn, callRunning, brain.job == nil, brain.pending == nil else { return false }
        callRunning = false
        NSLog("[mealunstick] cleared=callRunning why=%@ queued=%d focus=%@ greeting=%d", why, queued.count, String(describing: focus.phase), greeting ? 1 : 0)
        return true
    }

    /// Called when the player taps Feed / Water (`order`): clears whatever outlived its meal. Returns what it cleared (tests read it).
    @discardableResult
    func mealUnstick(why: String) -> [String] {
        guard Self.unstickOn, !bath.active, !tripActive, !isPreview, focus.phase == .roaming else { return [] }
        var cleared: [String] = []
        if callRunning, let b0 = brainFor(0), b0.job == nil, b0.pending == nil { callRunning = false; cleared.append("callRunning") }
        if mealLockAge > Self.staleMealAfter {
            if wanted != nil { wanted = nil; cleared.append("wanted") }
            if meal != nil { endMeal(); cleared.append("meal") }
            if groupWanted != nil || group.isActive || !groupQueue.isEmpty { cancelGroup(); cleared.append("group") }
            if dining.phase != .absent { dining.despawn(); cleared.append("tray") }
            retries = 0; resetStandWalk(); mealLockAge = 0
        }
        if !cleared.isEmpty {
            NSLog("[mealunstick] cleared=%@ why=%@ queued=%d wanted=%d meal=%d group=%d tray=%@ lockAge=%.0f", cleared.joined(separator: ","), why, queued.count, wanted != nil ? 1 : 0, meal != nil ? 1 : 0, groupActive ? 1 : 0, String(describing: dining.phase), mealLockAge)
        }
        return cleared
    }
}
