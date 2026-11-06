//
//  ContactTrace.swift
//  TEST-ONLY trace of the touch settle (2026-11-04, g-contactmig diagnosis). Off unless `ContactTrace.on` (the ContactPolishTests CONTACT_TRACE_ENGINE=1 flag sets it); the engine only
//  stamps short strings into `rec[steerID]` when it is on. The test harness resets `rec` before each tick and writes the columns into trace_<emote>_<cast>.tsv.
//

import Foundation

nonisolated enum ContactTrace {
    nonisolated(unsafe) static var on = false
    struct Rec {
        var step = "-"          // ContactSettle.step: what it did for the pair (this body = a): nil / stamp / anchored / onlySep / deadband / urgent / far / near
        var e: Float = 0, c: Float = 0, m: Float = 0       // skin error (m), wanted correction, applied share (m)
        var nudge = "-"          // contactNudge branch: lying / air / walk / lean / lean+shuffleReq / nolean
        var want: Float = 0       // lean want after this nudge
        var walk = "-"          // contactStanceWalk retarget: fired / noWalk / far / Lsmall / delta
        var tgt = "-"
        var shuffle = "-"          // shuffle clause: none / done:<reason> / blocked:script,feet,idle
    }
    nonisolated(unsafe) static var rec: [Int: Rec] = [:]
    static func mod(_ id: Int, _ f: (inout Rec) -> Void) { var r = rec[id] ?? Rec(); f(&r); rec[id] = r }
}
