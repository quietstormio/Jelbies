//
//  RaceDepartProbe.swift
//  Simulator-only capture aid, inside the DevArgs gate: `-RaceDepartProbe 1` logs every Jelmiko at home 20 times a second ("[rdp] ...": position, heading, bib, jersey, what he is doing,
//  the idle timer, rest timer and forced-face timer, the race phase) from the launch on, so the bibs and the standing still around a race's departure can be MEASURED, not just seen.
//  `-RaceDepartSetup pair|walkemote|toy` (with the marker file /tmp/racedep_go, which the UI test writes) keeps the two housemates in that situation until a trip starts:
//  pair = a pair emote (dance); walkemote = #1 walking somewhere, #2 in a solo emote; toy = #1 playing with a bouncy ball (kick). Not in device builds.
//
#if targetEnvironment(simulator)
import Foundation
import QuartzCore
import simd

enum RaceDepartProbe {
    nonisolated(unsafe) static let on = DevArgs.enabled && UserDefaults.standard.integer(forKey: "RaceDepartProbe") != 0
    nonisolated(unsafe) static let setup: String? = DevArgs.enabled ? UserDefaults.standard.string(forKey: "RaceDepartSetup") : nil
    nonisolated(unsafe) static var steps = 0
    nonisolated(unsafe) static var toyPlaced = false
    static func mark(_ s: String) { if on { NSLog("[rdp] MARK w=%.3f %@", CACurrentMediaTime(), s) } }
}

extension GameCare {
    func raceDepartProbe(_ actors: [JellyActor]) {
        guard RaceDepartProbe.on else { return }
        RaceDepartProbe.steps += 1
        if RaceDepartProbe.setup != nil, RaceDepartProbe.steps % 30 == 0 { raceDepartSetup(actors) }
        guard RaceDepartProbe.steps % 3 == 0 else { return }
        let now = CACurrentMediaTime()
        for a in actors {
            guard let b = a.brain else { continue }
            let s = wardrobe.slot(a.id)
            let doing = "scr:\(b.scriptKindName) idle:\(b.idleState.kind.map { "\($0)" } ?? "-") act:\(b.activity) soc:\(b.social.map { "\($0.kind.rawValue)" } ?? "-") pend:\(b.pending == nil ? 0 : 1) hurry:\(b.hurry ? 1 : 0) auto:\(b.autonomy ? 1 : 0) cmd:\(b.commanded ? 1 : 0) sleep:\(b.isSleeping ? 1 : 0) it:\(String(format: "%.2f", b.idleState.t)) rest:\(String(format: "%.2f", b.restTimer)) face:\(String(format: "%.2f", b.expr.forcedLeft)) yaw:\(String(format: "%.2f", b.yaw))"
            NSLog("[rdp] w=%.3f id=%d x=%.2f z=%.2f bib=%d jer=%d role=%@ ph=%@ out=%d wait=%d track=%d %@", now, a.id, a.floor.x, a.floor.y, s?.bib != nil ? 1 : 0, s?.jersey != nil ? 1 : 0,
                  "\(wearRole(for: a.id))", "\(race.phase)", outing.running ? 1 : 0, raceWait != nil ? 1 : 0, race.trackVisible ? 1 : 0, doing)
        }
    }

    /// Keeps the two housemates (ids 1 and 2) in the chosen situation until a trip starts. Needs the marker file (the UI test writes it just before it taps "Go out").
    private func raceDepartSetup(_ actors: [JellyActor]) {
        guard let kind = RaceDepartProbe.setup, FileManager.default.fileExists(atPath: "/tmp/racedep_go"), !tripActive, !outing.running, raceWait == nil, actors.count >= 3,
              let b1 = actors[1].brain, let b2 = actors[2].brain else { return }
        func free(_ b: BlobBrain) -> Bool { b.social == nil && b.idleState.kind == nil && b.scriptIsNone && b.pending == nil && !b.isSleeping }
        switch kind {
        case "pair":
            if free(b1), free(b2) { _ = b1.socialStart(.dance, with: b2, actors[1].sim) }
        case "walkemote":
            if free(b1) { b1.requestNow(.goTo(SIMD2<Float>(b1.position.x > 0 ? -2.2 : 2.2, b1.position.y > 0 ? -1.5 : 1.0))) }
            if free(b2) { b2.idleBegin(.bounce) }
        case "toy":
            if !RaceDepartProbe.toyPlaced {
                RaceDepartProbe.toyPlaced = true
                store.grant("decor-ball"); _ = store.place("decor-ball"); syncDecor()
            }
            if free(b1) { _ = b1.startCommandedDecor(.decorKick, only: .ball, actors[1].sim, actors[1].skinner) }
        default: break
        }
    }
}
#endif
