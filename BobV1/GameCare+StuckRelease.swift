//
//  GameCare+StuckRelease.swift
//  no-stuck-r1 (the owner, 2026-11-24: "Make sure nothing ... can ever get stuck"). The general release guard: the come-here-freeze safety net (`focusNetTick`, GameCare+FocusRelease.swift)
//  generalised from "a body the close-up took" to ANY Jelmiko. When nothing in the game holds anybody (no close-up or call, no trip or outing, no meal / tray / group serving, no bath,
//  no welcome (a newcomer's or the welcome home after a trip), no Play, no Show stage, no bedtime walk), a Jelmiko whose life is still switched off, or who is still `commanded` with nothing to do, is let go after `stuckReleaseAfter` s.
//  Each release logs `[stuck] released id=... was=...` so it is counted as a bug (the dev soak's stuck detector counts these too), never hidden.
//  Only a body that has been free before (autonomy on at some point) is given its life back. Never touches a sleeper, a pair / group moment (`social`), a reserved body, a commanded idle or a race / volley body. `-StuckRelease 0` (dev builds; also `-FreezeFix 0`) = off, for baselines.
//

import Foundation

extension GameCare {
    nonisolated(unsafe) static var stuckReleaseOn: Bool = {
        let d = UserDefaults.standard
        if ProcessInfo.processInfo.environment["STUCK_RELEASE_OFF"] != nil { return false }
        guard DevArgs.enabled else { return true }
        if d.object(forKey: "StuckRelease") != nil, d.integer(forKey: "StuckRelease") == 0 { return false }
        if d.object(forKey: "FreezeFix") != nil, d.integer(forKey: "FreezeFix") == 0 { return false }
        return true
    }()
    static let stuckReleaseAfter: Float = 6

    /// Nothing in the game may legitimately hold a Jelmiko's life off right now.
    var nothingHolds: Bool {
        focus.phase == .roaming && !tripActive && !raceBusy && !outing.running && newcomerWelcome == nil && !bath.active && !trayOut && !groupActive
            && !isPreview && !show.onStage && !bedtimeWalking && !play.active && !callRunning && queued.isEmpty && raceBook.returner == nil
    }

    /// Once per fixed step (Jelly 0's care tick).
    func stuckReleaseTick(dt: Float) {
        guard Self.stuckReleaseOn else { return }
        for id in 0..<max(jellies.count, 1) { if let b = brainFor(id), b.autonomy { stuckSeenFree.insert(ObjectIdentifier(b)) } }
        guard nothingHolds else { if !stuckHeldT.isEmpty { stuckHeldT = [:] }; return }
        for id in 0..<max(jellies.count, 1) {
            guard let b = brainFor(id), b.enabled else { continue }
            let free = b.isSleeping || b.social != nil || b.reserved || b.commandedIdle != nil || b.race.active || b.volley.active
            let off = !free && !b.autonomy && stuckSeenFree.contains(ObjectIdentifier(b))          // (only a life the game switched off: a body that was never free - a test rig's pinned one, a dev `-BlobNoWander` - is left alone)
            let orphan = !free && b.commanded && b.job == nil && b.pending == nil && b.scriptIsNone && b.commandedDecor == nil && !b.commandedFlip && !b.commandedNameHop
            for (what, on) in [("autonomy-off", off), ("commanded", orphan)] {
                let k = "\(what)#\(id)"
                guard on else { stuckHeldT[k] = nil; continue }
                let t = (stuckHeldT[k] ?? 0) + dt
                stuckHeldT[k] = t
                guard t >= (what == "commanded" ? Self.stuckReleaseAfter * 2 : Self.stuckReleaseAfter) else { continue }
                stuckHeldT[k] = nil
                NSLog("[stuck] released id=%d was=%@ scr=%@ job=%@ cmd=%d auto=%d idle=%@ act=%@", id, what, b.scriptKindName, b.job == nil ? "-" : "Y", b.commanded ? 1 : 0, b.autonomy ? 1 : 0, b.idleState.kind?.rawValue ?? "-", String(describing: b.activity))
                if what == "autonomy-off" { b.autonomy = true; b.restTimer = min(b.restTimer, 0.5); if id == 0 { savedAutonomy = true } }
                if b.commanded, b.job == nil, b.pending == nil, b.scriptIsNone { b.commanded = false }
                stuckReleased += 1
                #if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
                StuckDetector.shared.noteReleased(what, who: id)
                #endif
            }
        }
    }
}
