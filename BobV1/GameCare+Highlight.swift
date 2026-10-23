//
//  GameCare+Highlight.swift
//  A tap on a Jelbie highlights him (a persistent floor ring + the individual HUD menu); a tap on empty floor clears it.
//

import Foundation

extension GameCare {
    /// A tap (or double tap) on a Jelbie in the room: highlight him. A sleeper gets the ring at once, with no draw and no hop, and stays asleep.
    func tapJelly(_ id: Int) {
        guard jellyCount > 1, jelly(id) != nil, !focus.isActive, !bath.active, !tripActive, !arranging else { return }
        let asleep = selectBrain(id)?.isSleeping ?? (id == 0 ? (lastBrain?.isSleeping ?? false) : false)
        if select.highlighted == id && !asleep { return }
        select.pick(id, quietHop: asleep, instant: asleep)
    }
    /// A tap on empty floor.
    func clearHighlight() { select.clearHighlight() }
    /// The highlighted Jelbie (a settled pick, or the one whose outline is drawing).
    var highlightedJelly: Int? { select.highlighted ?? select.selectedID }
}
