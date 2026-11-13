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
//  Food comes from the Bag when there is one: `foodFor` is the hook (default: berries, a store food; with none owned the feed says so and serves nothing).
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
    /// When each pending route was first (re-)requested; a route older than `maxPendingAge` is dropped, never performed late.
    @ObservationIgnored private var requestedAt: [JellyRoute: Date] = [:]
    /// A route that waited longer than this (a cold launch that never reached the room, a feed stuck behind a tray) is stale.
    static let maxPendingAge: TimeInterval = 10 * 60
    /// Bumped on every request, so a view can `onChange` it.
    private(set) var serial = 0
    /// Everything applied so far (tests, the debug log).
    private(set) var applied: [JellyRoute] = []

    /// Hooks other features plug into. Nil = the default fallback described above.
    @ObservationIgnored var onRace: ((Int) -> Void)?
    @ObservationIgnored var onBed: (() -> Void)?
    /// Goodnight through the room's own flow: true when they were put to bed, false when the room refused (a meal, a race ...). Wins over `onBed`.
    @ObservationIgnored var onGoodnight: (() -> Bool)?
    /// The food id to serve for a Siri / widget feed (the Bag's pick; default berries, a store food; nothing is served when the bag has none).
    @ObservationIgnored var foodFor: (Int?) -> String = { _ in Consumables.berries.id }
    /// A Siri / widget feed with NO food in the bag: the screen opens the Feed row (everything dimmed "none left") and says so.
    @ObservationIgnored var onNoFood: (() -> Void)?
    /// What is said when there is nothing to feed.
    static let noFoodLine = "No food left. Visit the Shop to get more."
    private(set) var noFoodCount = 0
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
        requestedAt[route] = now()
        serial += 1
    }
    /// Forgets everything waiting (a new game starts: a Siri action asked for the old one must not land on it).
    func clearPending() { pending = []; requestedAt = [:] }
    /// The App Group queue (the widget's Water button; an intent that ran while the app was not running). Call on `.active`.
    func drainQueued() {
        for r in PendingActions.drain(from: directory, now: now()) { request(r) }
    }

    // MARK: out

    /// Performs everything pending on `care`. A feed / water that cannot start yet (tray out, clean-up) stays pending for the next call.
    func apply(care: GameCare) {
        guard !pending.isEmpty else { return }
        let t = now()
        var fresh: [JellyRoute] = []          // stale routes are only dropped; a live one is performed exactly as before
        for r in pending {
            let at = requestedAt[r] ?? t
            requestedAt[r] = at
            if t.timeIntervalSince(at) <= Self.maxPendingAge { fresh.append(r) }
        }
        if fresh.count != pending.count { pending = fresh }
        var keep: [JellyRoute] = []
        for r in pending {
            if !perform(r, care: care) { keep.append(r) }
        }
        pending = keep
        requestedAt = requestedAt.filter { keep.contains($0.key) }
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
            let want = foodFor(id)
            // the wanted food, else any food the player owns (foods before treats, shop order); with none: say so instead of doing nothing
            let owned = Consumables.with(id: want).map { !$0.stored || care.store.count(food: $0.id) > 0 } ?? false
            guard let serve = owned ? want : care.store.snacks.first?.item.food else {
                noFoodCount += 1
                if let onNoFood { onNoFood() } else { A11yAnnounce.say(Self.noFoodLine) }
                break
            }
            care.feed(serve, jelly: care.jellyCount > 1 ? id : 0)
        case .water(let id):
            guard !care.trayOut, !care.bath.active else { return false }
            if care.focus.isActive { care.release() }
            care.drink(Consumables.water.id, jelly: care.jellyCount > 1 ? id : 0)
        case .pet(let id):
            guard !care.bath.active, !care.trayOut else { return false }
            if care.focus.isActive { return true }               // already in a close-up
            care.comeHere(jelly: id)
        case .bed:
            let ran: Bool
            if let onGoodnight { ran = onGoodnight() } else if let onBed { onBed(); ran = true } else { Self.curtainsToNight(); ran = true }
            if ran { live?.bedtime(names: care.jellies.map(\.name), colors: care.jellyColorKeys, now: now()) }          // a refused goodnight stamps nothing and raises no card
        case .race(let id):
            if let onRace { onRace(id) } else { care.openJelly(id) }
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
