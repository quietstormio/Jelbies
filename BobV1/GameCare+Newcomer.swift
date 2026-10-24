//
//  GameCare+Newcomer.swift
//  Bring-home moment: a freshly adopted Jelbie is set down at the room's back edge, takes the existing come-to-front walk to the middle, then the
//  existing welcome-home (his hop + hearts, the others trot over) runs. The caption is StartFlow's WelcomeBanner. No new moves, no modal.
//

import Foundation
import simd

extension GameCare {
    /// Set by StartFlow.bringHome; the next room's first steps consume it.
    nonisolated(unsafe) static var newcomerPending = false
    static let newcomerEdge = SIMD2<Float>(1.1, -2.2)

    func tickNewcomer(_ actors: [JellyActor], dt: Float) {
        if var n = newcomer {
            n.age += dt
            guard actors.indices.contains(n.id), let b = actors[n.id].brain else { newcomer = nil; return }
            let calm = b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace
            n.calm = (calm && n.age > 0.8) ? n.calm + dt : 0
            if n.calm > 0.3 || n.age > 14 || greetBlocked && n.age > 2 { newcomer = nil; raceWelcomeHome(n.id, won: false) } else { newcomer = n }
            return
        }
        guard Self.newcomerPending, !LaunchGate.shared.visible, let last = actors.last, actors.count == max(jellies.count, 1), let b = last.brain else { return }
        Self.newcomerPending = false
        if actors.count > 1 { select.cancel() }
        rehome(last, at: Self.newcomerEdge)
        b.requestNow(.come(to: VoiceCoordinator.comeSpot))
        newcomer = NewcomerWalk(id: last.id)
    }
}

struct NewcomerWalk { let id: Int; var age: Float = 0; var calm: Float = 0 }
