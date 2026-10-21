//
//  AIHub.swift
//  The glue of the natural voice commands, owned by VoiceCoordinator and ticked from it once per fixed step: the IntentRouter (Tier A / Tier B),
//  the command queue the executor drains (`execute`, CommandExecutor.swift), and the "go to sleep" nap driver. Brains of Jellies other than Bob
//  are registered by the stage (`register`); Bob's comes with every tick.
//  (The diary, thought lines and event log that lived here were removed on 2026-10-20 at the user's request.)
//

import Foundation
import Observation

@MainActor
@Observable
final class AIHub {
    let router: IntentRouter
    /// Commands waiting to run once the hold is over (one per step, like the reaction queue).
    @ObservationIgnored var commandQueue: [JellyCommand] = []
    /// Jellies asked to sleep: once their sit starts it becomes a nap (`napWanted` = seconds left to start sitting).
    @ObservationIgnored private var napWanted: [Int: Float] = [:]
    /// How many naps were forced by a sleep command (tests).
    @ObservationIgnored private(set) var napsStarted = 0
    @ObservationIgnored private var brains: [Int: Weak] = [:]
    private struct Weak { weak var b: BlobBrain? }

    nonisolated deinit {}

    /// `model` nil = Tier B only (unit tests, phones without the framework).
    init(model: AICommandModel? = nil, availability: AIAvailability? = nil) {
        router = IntentRouter(model: model, availability: availability)
    }

    /// The stage hands over the other Jellies' brains (Bob's arrives with `tick`).
    func register(_ b: BlobBrain, id: Int) { brains[id] = Weak(b: b) }
    func brain(_ id: Int) -> BlobBrain? { brains[id]?.b }

    func catalog(care: GameCare) -> AICatalog {
        AICatalogRegistry.catalog(jellies: care.jellies.map { ($0.id, $0.name) })
    }

    // MARK: tick

    func tick(care: GameCare, bob: BlobBrain, dt: Float) {
        brains[0] = Weak(b: bob)
        driveNaps(dt: dt)
    }

    // MARK: sleep

    /// Asks Jelly `id` to sleep: his sit is turned into a nap once it starts (the nap is the night sit with eyes closed; nothing new in the body).
    func requestNap(_ id: Int) {
        guard let b = brain(id) else { return }
        if b.idleState.kind == .sit, !b.idleState.yielding { b.napping = true; b.idleState.hold = max(b.idleState.hold, 55); napsStarted += 1; return }
        b.commandedIdle = .sit
        napWanted[id] = 4
    }
    private func driveNaps(dt: Float) {
        for (id, left) in napWanted {
            guard let b = brain(id) else { napWanted[id] = nil; continue }
            if b.idleState.kind == .sit, !b.idleState.yielding {
                b.napping = true
                b.idleState.hold = max(b.idleState.hold, 55)          // 55 s of eyes-closed sitting, like the night nap
                napsStarted += 1
                napWanted[id] = nil
            } else if left - dt <= 0 { napWanted[id] = nil } else { napWanted[id] = left - dt }
        }
    }
}
