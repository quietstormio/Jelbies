//
//  RaceDepartProbe.swift
//  Simulator-only capture aid: `-RaceDepartProbe 1` logs every Jelmiko at home 20 times a second ("[rdp] ...": position, bib, jersey, what he is doing, the race phase)
//  from the launch on, so the bibs and the standing still around a race's departure can be MEASURED, not just seen. Not in device builds.
//
#if targetEnvironment(simulator)
import Foundation
import QuartzCore

enum RaceDepartProbe {
    nonisolated(unsafe) static let on = DevArgs.enabled && UserDefaults.standard.integer(forKey: "RaceDepartProbe") != 0
    nonisolated(unsafe) static var steps = 0
}

extension GameCare {
    func raceDepartProbe(_ actors: [JellyActor]) {
        guard RaceDepartProbe.on else { return }
        RaceDepartProbe.steps += 1
        guard RaceDepartProbe.steps % 3 == 0 else { return }
        let now = CACurrentMediaTime()
        for a in actors {
            guard let b = a.brain else { continue }
            let s = wardrobe.slot(a.id)
            let doing = "scr:\(b.scriptKindName) idle:\(b.idleState.kind.map { "\($0)" } ?? "-") act:\(b.activity) soc:\(b.social == nil ? 0 : 1) pend:\(b.pending == nil ? 0 : 1) hurry:\(b.hurry ? 1 : 0) auto:\(b.autonomy ? 1 : 0) sleep:\(b.isSleeping ? 1 : 0)"
            NSLog("[rdp] w=%.3f id=%d x=%.2f z=%.2f bib=%d jer=%d role=%@ ph=%@ out=%d wait=%d track=%d %@", now, a.id, a.floor.x, a.floor.y, s?.bib != nil ? 1 : 0, s?.jersey != nil ? 1 : 0,
                  "\(wearRole(for: a.id))", "\(race.phase)", outing.running ? 1 : 0, raceWait != nil ? 1 : 0, race.trackVisible ? 1 : 0, doing)
        }
    }
}
#endif
