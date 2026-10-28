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
    nonisolated deinit {}
}

extension GameCare {
    /// The first call starts the run-out (true = the caller returns); `again` re-enters the caller once the Jelbies are out, and that second call passes (false).
    func outingGate(_ ids: [Int], again: @escaping () -> Void) -> Bool {
        if outing.passed { outing.passed = false; return false }
        guard !outing.running else { return true }
        runOut(ids) { [weak self] in self?.outing.passed = true; again(); self?.outing.passed = false }
        return true
    }

    func runOut(_ ids: [Int], then done: @escaping () -> Void) {
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
        for a in actors where !ids.contains(a.id) {          // the ones who stay: watch and cheer them off
            guard let b = a.brain, !b.isSleeping else { continue }
            b.face(.happy, hold: 2)
        }
    }

    /// Per fixed step (called with the groomer's tick).
    func tickOutExit(_ actors: [JellyActor], dt: Float) {
        let o = outing
        if o.running {
            o.t += dt
            var allOut = true
            for (id, r0) in o.runners {
                guard let a = actors.first(where: { $0.id == id }), let b = a.brain else { continue }
                var r = r0
                if o.t < r.delay { allOut = false; continue }
                if !r.started {
                    r.started = true; r.autonomy = b.autonomy; r.home = a.floor
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

    /// Everything back to normal; a runner still out in the street (the trip never took him) walks in from home.
    func outingTidy() {
        let o = outing
        o.tidyT = nil
        let busy = tripActive || raceWait != nil
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
