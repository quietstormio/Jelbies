//
//  GameRouter.swift
//  Where every way INTO the game meets: the widget's deep links (`onOpenURL`), Siri / Shortcuts (App Intents run in this process and call
//  `request`), and the actions queued in the App Group by the widget's Water button or by an intent while the app was not running
//  (PendingActions, drained on `.active`). GameScreen owns one and calls `apply(care:)` when the game is up; a route that arrives before
//  that waits in `pending`.
//
//  What each route does is deliberately small and goes through the normal care flows:
//    jelly   -> the roster highlight (GameCare.openJelly)
//    feed    -> the basic food through the tray (GameCare.feed); left queued while a tray is out or a clean-up runs
//    water   -> water through the tray (GameCare.drink)
//    pet     -> Come here: the close-up where petting happens (GameCare.comeHere)
//    bed     -> the curtains to night (DayClock.skipToNextPhase until night) and the nap Live Activity
//    race    -> `onRace` (the Track panel; Jelly Circuit worker) - until it is wired, the roster highlight
//    train   -> `onTrain` (training; its worker) - until it is wired, the roster highlight
//  Food comes from the Bag when there is one: `foodFor` is the hook (default: the free basic food, Consumables.berries).
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class GameRouter {
    static let shared = GameRouter()

    /// Routes waiting for the game screen (oldest first).
    private(set) var pending: [JellyRoute] = []
    /// Bumped on every request, so a view can `onChange` it.
    private(set) var serial = 0
    /// Everything applied so far (tests, the debug log).
    private(set) var applied: [JellyRoute] = []

    /// Hooks other features plug into. Nil = the default fallback described above.
    @ObservationIgnored var onRace: ((Int) -> Void)?
    @ObservationIgnored var onTrain: ((Int) -> Void)?
    @ObservationIgnored var onBed: (() -> Void)?
    /// The food id to serve for a Siri / widget feed (the Bag's pick; default the free basic food).
    @ObservationIgnored var foodFor: (Int?) -> String = { _ in Consumables.berries.id }
    @ObservationIgnored var directory: URL? = JellyShare.containerURL
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var live: LiveActivities? = LiveActivities.shared

    init(directory: URL? = JellyShare.containerURL) { self.directory = directory }
    nonisolated deinit {}

    // MARK: in

    /// A deep link (widget tap, Live Activity tap, OpenURLIntent).
    func handle(_ url: URL) -> Bool {
        guard let r = JellyRoute.parse(url) else { return false }
        request(r)
        return true
    }
    /// An intent in this process, or anything else that wants the game to do something next.
    func request(_ route: JellyRoute) {
        pending.removeAll { $0 == route }
        pending.append(route)
        serial += 1
    }
    /// The App Group queue (the widget's Water button; an intent that ran while the app was not running). Call on `.active`.
    func drainQueued() {
        for r in PendingActions.drain(from: directory, now: now()) { request(r) }
    }

    // MARK: out

    /// Performs everything pending on `care`. A feed / water that cannot start yet (tray out, clean-up) stays pending for the next call.
    func apply(care: GameCare) {
        guard !pending.isEmpty else { return }
        var keep: [JellyRoute] = []
        for r in pending {
            if !perform(r, care: care) { keep.append(r) }
        }
        pending = keep
    }

    /// True when the route was handled (or is meaningless now); false to try again later.
    @discardableResult
    func perform(_ r: JellyRoute, care: GameCare) -> Bool {
        switch r {
        case .jelly(let id):
            care.openJelly(id)
        case .feed(let id):
            guard !care.trayOut, !care.bath.active else { return false }
            if care.focus.isActive { care.release() }
            care.feed(foodFor(id), jelly: care.jellyCount > 1 ? id : 0)
        case .water(let id):
            guard !care.trayOut, !care.bath.active else { return false }
            if care.focus.isActive { care.release() }
            care.drink(Consumables.water.id, jelly: care.jellyCount > 1 ? id : 0)
        case .pet(let id):
            guard !care.bath.active, !care.trayOut else { return false }
            if care.focus.isActive { return true }               // already in a close-up
            care.comeHere(jelly: id)
        case .bed:
            if let onBed { onBed() } else { Self.curtainsToNight() }
            live?.bedtime(names: care.jellies.map(\.name), now: now())
        case .race(let id):
            if let onRace { onRace(id) } else { care.openJelly(id) }
        case .train(let id):
            if let onTrain { onTrain(id) } else { care.openJelly(id) }
        }
        applied.append(r)
        return true
    }

    /// The curtains until it is night in the room (at most three skips: morning -> day -> evening -> night).
    static func curtainsToNight() {
        let clock = DayClock.shared
        var n = 0
        while clock.phase != .night, n < 3 { clock.skipToNextPhase(); n += 1 }
    }
}
