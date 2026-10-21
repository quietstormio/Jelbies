//
//  AIHub.swift
//  The glue of the natural voice commands, owned by VoiceCoordinator and ticked from it once per fixed step: the IntentRouter (Tier A / Tier B),
//  the command queue the executor drains (`execute`, CommandExecutor.swift) and the live catalog (the room's Jellies + the store's items). Brains
//  of Jellies other than Bob are registered by the stage (`register`); Bob's comes with every tick (the decor commands need them).
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
        AICatalogRegistry.catalog(jellies: care.jellies.map { ($0.id, $0.name) }, store: care.store)
    }

    // MARK: tick

    func tick(care: GameCare, bob: BlobBrain, dt: Float) {
        brains[0] = Weak(b: bob)
    }
}
