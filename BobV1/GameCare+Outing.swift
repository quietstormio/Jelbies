//
//  GameCare+Outing.swift
//  Leaving the house: before an outing's fade starts, the Jelbies who are going RUN out of the room toward the camera (the same hurry + goTo the Clean
//  flow's departure uses, so they get whatever run gait the brain has), a little staggered. The fade starts as the last one reaches the front edge (or on a
//  timeout, so a stuck Jelbie never blocks the outing). The ones who stay home watch, pleased.
//
//  Mechanics: the room's floor rules and the body's arena wall are lifted for the runners only (`outing.lifted`, `SoftBody.arenaSuspended`). While they are out
//  of the frame `JellyActor.outingHome` makes a trip save the spot they LEFT FROM as their home; a short while after the trip has had its swap it is all
//  put back (and a Jelbie left out by an outing that never started is carried home).
//

import Foundation
import simd

enum OutingTuning {
    /// `cutZ`: the fade starts when the last runner passes this depth (he is still on screen, mid-stride). `targetZ`: the run's goal, far past the camera / the front edge, so
    /// nobody ARRIVES (an arrival is what used to stop them: the goal sat just off the front edge and the leaders stood idle there while the fade waited for the last one).
    static let cutZ: Float = 4.6, targetZ: Float = 18, timeout: Float = 6, stagger: Float = 0.08, runSpeed: Float = 1.75
    /// How long after the fade starts the runners are kept running (the longest fade-out is 0.5 s; the swap comes right after it).
    static let keepRunning: Float = 0.9
    static let tidyDelay: Float = 1.8
}

@MainActor
final class OutingBook {
    struct Runner { var delay: Float; var lane: Float = 0; var pace: Float = 1; var started = false; var swapped = false; var last = SIMD2<Float>.zero; var autonomy = true; var home = SIMD2<Float>.zero }
    var keepT: Float = 0
    var lifted: Set<Int> = []
    var runners: [Int: Runner] = [:]
    var t: Float = 0
    var then: (() -> Void)?
    var passed = false
    var tidyT: Float?
    var released: [Int] = []
    var running: Bool { then != nil }
    /// A daytime trip was asked while somebody slept: he is being woken (the short get-up) and `wakeThen` starts the trip once everybody is upright (`GameCare.wakeForTrip`).
    var wakeThen: (() -> Void)?
    var wakeT: Float = 0
    var wakeIDs: Set<Int> = []          // who is going (only they are woken, waited for and kept from dozing off; a sleeper who stays home is not touched)
    var waking: Bool { wakeThen != nil }
    nonisolated deinit {}
}

extension GameCare {
    /// The first call starts the run-out (true = the caller returns); `again` re-enters the caller once the Jelbies are out, and that second call passes (false).
    func outingGate(_ ids: [Int], cheer: Bool = true, again: @escaping () -> Void) -> Bool {
        if outing.passed { outing.passed = false; return false }
        guard !outing.running else { return true }
        runOut(ids, cheer: cheer) { [weak self] in self?.outing.passed = true; again(); self?.outing.passed = false }
        return true
    }

    /// A trip that is not a competition (park, café, Jelly Spa) never refuses a daytime ask because somebody sleeps: every sleeper (and anybody just asked to nap) gets the SHORT wake
    /// (`fast`, not groggy: the quick get-up a scene change uses, never the slow staged morning wake; needs untouched) and `go` runs once all are upright. False = nobody slept, the caller carries on.
    /// Night is refused before this is reached (`cafeBlocker`), so this only ever runs by day. The player's own Naptime does not block it: the newer choice wins.
    /// `ids` = who is going. A Jelmiko who stays home keeps sleeping exactly where and as he is (no wake, no pause, no reset).
    func wakeForTrip(_ ids: [Int], then go: @escaping () -> Void) -> Bool {
        let o = outing
        let going = Set(ids)
        let sleepers = raceBook.actors.filter { going.contains($0.id) && $0.brain?.isSleeping == true }.map(\.id)
        for id in Set(sleepers).union(nightRest.wanted.intersection(going)) { wakeSleeper(id, groggy: false, fast: true) }          // (also cancels a nap that was asked but not begun)
        guard !sleepers.isEmpty else { return false }
        o.wakeThen = go; o.wakeT = 0; o.wakeIDs = going
        for a in raceBook.actors where going.contains(a.id) { a.brain?.sleepLocked = true }
        return true
    }

    private func tickTripWake(_ actors: [JellyActor], dt: Float) {
        let o = outing
        o.wakeT += dt
        let sleeping = actors.filter { o.wakeIDs.contains($0.id) && ($0.brain?.isSleeping ?? false) }
        if o.wakeT > 1.5, o.wakeT.truncatingRemainder(dividingBy: 1) < dt { for a in sleeping { a.brain?.sleepWake(groggy: false, fast: true) } }
        if o.wakeT > 8 { for a in sleeping { if let b = a.brain { b.abortAll(a.sim, a.skinner); b.idleReset(a.skinner) } } }          // gave up waiting: stand him up (as the race does)
        if sleeping.isEmpty || o.wakeT > 8.5 {
            let go = o.wakeThen; o.wakeThen = nil
            go?()
        }
    }

    /// `cheer`: the ones who stay home watch, pleased (a forced happy face for 2 s). The race passes false: a housemate keeps doing exactly what he was doing (race-depart-r2).
    func runOut(_ ids: [Int], cheer: Bool = true, then done: @escaping () -> Void) {
        let o = outing
        let actors = groomBook.actors
        let going = actors.filter { ids.contains($0.id) && $0.brain != nil }
        if going.isEmpty || A11ySettings.shared.reduceMotion { done(); return }
        outingTidy()
        o.t = 0; o.runners = [:]; o.then = done; o.released = []
        // Fanned lanes (in today's left-to-right order, so paths never cross) and a start delay that evens out the arrival: whoever is nearest the camera leaves last.
        let byX = going.sorted { $0.floor.x < $1.floor.x }
        let far = going.map { OutingTuning.cutZ - $0.floor.y }.max() ?? 0
        for (k, a) in byX.enumerated() {
            let lane = max(-2.4, min(2.4, a.floor.x * 0.9 + (Float(k) - Float(going.count - 1) / 2) * 0.5))
            // nobody waits: starts are 0.08 s apart per rank; the arrival is evened out by pace instead (the farthest runs 10 % faster, the nearest 10 % slower)
            let d = OutingTuning.cutZ - a.floor.y
            let pace = far > 0.5 ? 0.9 + 0.2 * max(0, min(1, d / far)) : 1
            o.runners[a.id] = OutingBook.Runner(delay: Float(k) * OutingTuning.stagger, lane: lane, pace: pace)
        }
        o.keepT = 0
        for a in actors where cheer && !ids.contains(a.id) {          // the ones who stay: watch and cheer them off
            guard let b = a.brain, !b.isSleeping else { continue }
            b.face(.happy, hold: 2)
        }
    }

    /// Per fixed step (called with the groomer's tick).
    func tickOutExit(_ actors: [JellyActor], dt: Float) {
        let o = outing
        if o.waking { tickTripWake(actors, dt: dt) }
        if o.waking { for a in actors where o.wakeIDs.contains(a.id) { a.brain?.sleepLocked = true } }
        if o.running { for a in actors where o.runners[a.id] != nil { a.brain?.sleepLocked = true } }          // (nobody dozes off between the wake and the fade)
        if o.running {
            o.t += dt
            var allOut = true
            for (id, r0) in o.runners {
                guard let a = actors.first(where: { $0.id == id }), let b = a.brain else { continue }
                var r = r0
                if o.t < r.delay { allOut = false; continue }
                if !r.started {
                    r.started = true; r.autonomy = autonomySnapshot(id, b); r.home = a.floor
                    o.lifted.insert(id); a.sim.arenaSuspended = true
                    b.autonomy = false
                    b.hurry = true; b.outingPace = r.pace
                    b.requestNow(.goTo(SIMD2(r.lane, OutingTuning.targetZ)))
                    o.runners[id] = r
                }
                b.hurry = true
                if GameCare.floorPos(b, a.sim).y < OutingTuning.cutZ && o.t < r.delay + OutingTuning.timeout { allOut = false }
            }
            if allOut { outingGo(actors) }
        } else if let t = o.tidyT {
            o.tidyT = t - dt
            // Still running through the fade: nothing may stop, settle or idle before the screen is covered (and the trip's swap moves them).
            if o.keepT > 0 {
                o.keepT -= dt
                for (id, r0) in o.runners where r0.started && !r0.swapped {
                    guard let a = actors.first(where: { $0.id == id }), let b = a.brain else { continue }
                    var r = r0
                    let here = GameCare.floorPos(b, a.sim)
                    if simd_distance(here, r.last) > 0.6 { r.swapped = true; o.runners[id] = r; continue }          // (the trip's swap moved him: hands off)
                    r.last = here; o.runners[id] = r
                    b.hurry = true
                    if case .none = b.script, b.pending == nil { b.requestNow(.goTo(SIMD2(r.lane, OutingTuning.targetZ))) }
                }
            }
            if t - dt <= 0 { outingTidy() }
        }
    }

    private func outingGo(_ actors: [JellyActor]) {
        let o = outing
        let done = o.then
        o.then = nil
        for (id, r) in o.runners {
            guard let a = actors.first(where: { $0.id == id }), let b = a.brain else { continue }
            a.outingHome = r.home
            b.autonomy = r.autonomy
            o.released.append(id)
        }
        for (id, r0) in o.runners { if let a = actors.first(where: { $0.id == id }), let b = a.brain { var r = r0; r.last = GameCare.floorPos(b, a.sim); o.runners[id] = r } }
        o.tidyT = OutingTuning.tidyDelay
        o.keepT = OutingTuning.keepRunning
        done?()
    }

    /// park-slide-r3 (owner 2026-11-16, "They're still walking in slide"): the trip's swap has just put this runner in the park, so his run-out ends HERE: the floor rules and his
    /// arena wall come back, he stops hurrying, and the fade's keep-running loop leaves him alone. Before, all of it lasted until `outingTidy` (1.8 s after the fade began, about
    /// 1.4 s into the park), and his first wander leg (restTimer 1.2 s) was picked and walked with NO floor rules: its goal could lie inside the slide and its leg cross it (the
    /// real-app probe: the Panda over the slide's chute in the visit's first second, the owner's screenshot).
    /// park-arrive-r1: `outingHome` goes here too (level 3; the trip read the home spots before the swap). Until the tidy, `JellyActor.floor` gave the HOME spot for a body standing in
    /// the park, and the stage built his skin's contact profile around that spot (`root: a.floor`, MelonStage's skinning): its radii grew by the way from home to his park spot
    /// (0.9-4.2 m for the owner's three), so the steering's wall (`MelonController.keepApart`, ContactField) threw the walk steps and hops of the ones who came metres at a time (single
    /// steps of 1.8-4.2 m and a 1.5 m hop in the first 1.4 s in the arrival probe, the drawn body dragged after them; the floor rules alone left those spots where they were). The peers' snapshot
    /// had him at home too.
    func outingLanded(_ a: JellyActor) {
        let o = outing
        guard var r = o.runners[a.id] else { return }
        #if targetEnvironment(simulator)
        if ParkSlideProbe.on { NSLog("[slide3] landed body=%d lifted=%d hurry=%d fix=%d", a.id, o.lifted.contains(a.id) ? 1 : 0, (a.brain?.hurry ?? false) ? 1 : 0, BlobBrain.slideSoftEndEnabled ? 1 : 0) }
        #endif
        guard BlobBrain.slideSoftEndEnabled else { return }          // (`-ParkSlideFix old`: main's rule, the lifted floor rules last until the tidy)
        o.lifted.remove(a.id)
        a.sim.arenaSuspended = false
        r.swapped = true; o.runners[a.id] = r
        a.brain?.hurry = false; a.brain?.outingPace = 1
        if BlobBrain.slideFixLevel >= 3 { a.outingHome = nil }
    }

    /// Everything back to normal; a runner still out in the street (the trip never took him) walks in from home.
    func outingTidy() {
        let o = outing
        o.tidyT = nil
        let busy = tripActive || raceWait != nil || showBook.wait != nil
        for a in groomBook.actors where o.runners[a.id] != nil {
            a.outingHome = nil
            a.sim.arenaSuspended = false
            guard let b = a.brain else { continue }
            b.hurry = false; b.outingPace = 1
            if o.runners[a.id]?.started == true, !busy, GameCare.floorPos(b, a.sim).y > GameCamera.walkMaxZ {
                rehome(a, at: b.fixed(o.runners[a.id]?.home ?? Self.greetSpot(a.id)))
                b.restTimer = 1
            }
        }
        o.lifted = []; o.runners = [:]; o.released = []
    }
}
