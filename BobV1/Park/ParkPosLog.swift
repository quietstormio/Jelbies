//
//  ParkPosLog.swift
//  park-open-r1: capture aid (simulator, `-ParkPosLog 1`): twice a second, one `[parkpos]` line per body in the park (the ones who came and the visitors): park time, id, floor x / z and what he is doing.
//  Log only; the takes' closest approach and the share of time any pair is closer than 1.2 are read from it. Nothing in the game reads it.
//

import Foundation
import simd

#if targetEnvironment(simulator)
enum ParkPosLog {
    nonisolated(unsafe) static var on: Bool = DevArgs.enabled && UserDefaults.standard.integer(forKey: "ParkPosLog") != 0
    nonisolated(unsafe) static var clock: Double = 0
    nonisolated(unsafe) static var next: Double = 0
}

extension GameCare {
    func parkPosLog(_ bodies: [JellyActor], dt: Float) {
        ParkPosLog.clock += Double(dt)
        guard ParkPosLog.clock >= ParkPosLog.next else { return }
        ParkPosLog.next = ParkPosLog.clock + 0.5
        for a in bodies {
            var st = "stand"
            if let b = a.brain {
                if let s = b.social { st = "social:\(s.kind.rawValue)" }
                else if let k = b.idleState.kind { st = "idle:\(k.rawValue)" }
                else if b.activity == .walking || b.activity == .coming { st = "walk" }
            }
            NSLog("[parkpos] t=%.1f id=%d x=%.2f z=%.2f %@", ParkPosLog.clock, a.id, a.floor.x, a.floor.y, st)
        }
    }
}
#endif
