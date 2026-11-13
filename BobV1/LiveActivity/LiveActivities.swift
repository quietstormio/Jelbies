//
//  LiveActivities.swift
//  The app's side of the Live Activities (Shared/JelbiesActivityAttributes.swift): when to start, what to push, when to end.
//    race  - starts with the race, updates only when the placing or the lap changes or a quarter of the track is passed (RaceActivityPolicy:
//            the update budget), ends with the result ("🥇 Pip won! +12 JellyCoins"), dismissed a few minutes later.
//    nap   - optional, default on: when the Jelbies go to bed (the app leaves the foreground at night, or "Put my Jelbies to bed"),
//            a gentle "sleeping" card with the wake time (06:00); stale at the wake time; ended when they wake / the app is back by day.
//  Every ActivityKit call goes through `ActivityDriver`, so the decisions are unit-tested against `MockActivityDriver`.
//  Local updates only (no push). Orphans from a crashed / killed run are ended on launch (`cleanUp`).
//
//  Entry points for the race (call on the main actor):
//    LiveActivities.shared.raceStarted(jellyID:name:color:racers:laps:)
//    LiveActivities.shared.raceProgress(position:progress:lap:)
//    LiveActivities.shared.raceFinished(place:drops:)
//

import Foundation
import Observation
import ActivityKit

typealias JelbiesState = JelbiesActivityAttributes.ContentState

// MARK: - Driver

/// The thin seam over ActivityKit. `start` returns the activity id.
@MainActor
protocol ActivityDriver: AnyObject {
    var enabled: Bool { get }
    func start(_ attributes: JelbiesActivityAttributes, state: JelbiesState, staleDate: Date?) throws -> String
    func update(id: String, state: JelbiesState, staleDate: Date?)
    func end(id: String, state: JelbiesState, dismissAt: Date?)
    /// Every activity ActivityKit still knows about (id, attributes, last state).
    func existing() -> [(id: String, attributes: JelbiesActivityAttributes, state: JelbiesState)]
}

@MainActor
final class ActivityKitDriver: ActivityDriver {
    var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    nonisolated init() {}
    nonisolated deinit {}
    func start(_ attributes: JelbiesActivityAttributes, state: JelbiesState, staleDate: Date?) throws -> String {
        let a = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: staleDate), pushType: nil)
        return a.id
    }
    func update(id: String, state: JelbiesState, staleDate: Date?) {
        guard let a = Activity<JelbiesActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        Task { await a.update(ActivityContent(state: state, staleDate: staleDate)) }
    }
    func end(id: String, state: JelbiesState, dismissAt: Date?) {
        guard let a = Activity<JelbiesActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let policy: ActivityUIDismissalPolicy = dismissAt.map { .after($0) } ?? .default
        Task { await a.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy) }
    }
    func existing() -> [(id: String, attributes: JelbiesActivityAttributes, state: JelbiesState)] {
        Activity<JelbiesActivityAttributes>.activities.map { ($0.id, $0.attributes, $0.content.state) }
    }
}

/// The test double: records every call.
@MainActor
final class MockActivityDriver: ActivityDriver {
    enum Call: Equatable { case start(JelbiesActivityAttributes.Kind, JelbiesState), update(String, JelbiesState), end(String, JelbiesState) }
    var enabled = true
    var calls: [Call] = []
    var live: [String: (JelbiesActivityAttributes, JelbiesState)] = [:]
    var staleDates: [String: Date?] = [:]
    var dismissals: [String: Date?] = [:]
    private var n = 0
    var failStart = false
    nonisolated init() {}
    nonisolated deinit {}
    func start(_ attributes: JelbiesActivityAttributes, state: JelbiesState, staleDate: Date?) throws -> String {
        if failStart { throw NSError(domain: "mock", code: 1) }
        n += 1
        let id = "a\(n)"
        live[id] = (attributes, state); staleDates[id] = staleDate
        calls.append(.start(attributes.kind, state))
        return id
    }
    func update(id: String, state: JelbiesState, staleDate: Date?) {
        if let a = live[id] { live[id] = (a.0, state) }; staleDates[id] = staleDate
        calls.append(.update(id, state))
    }
    func end(id: String, state: JelbiesState, dismissAt: Date?) {
        live[id] = nil; dismissals[id] = dismissAt
        calls.append(.end(id, state))
    }
    func existing() -> [(id: String, attributes: JelbiesActivityAttributes, state: JelbiesState)] { live.map { ($0.key, $0.value.0, $0.value.1) } }
    var updates: Int { calls.filter { if case .update = $0 { return true }; return false }.count }
}

// MARK: - Race update policy

/// Which race states are worth an update: the start, a placing change, a new lap, a quarter of the track passed, the finish. Never per tick.
nonisolated struct RaceActivityPolicy: Sendable {
    static let milestones: [Double] = [0.25, 0.5, 0.75]
    private(set) var last: JelbiesState?

    /// True when `new` should be published; remembers it if so.
    mutating func shouldPublish(_ new: JelbiesState) -> Bool {
        let publish: Bool
        if let l = last {
            publish = new.phase != l.phase || new.position != l.position || new.lap != l.lap
                || Self.milestones.contains(where: { l.progress < $0 && new.progress >= $0 })
        } else { publish = true }
        if publish { last = new }
        return publish
    }
    mutating func reset() { last = nil }
}

// MARK: - Settings

nonisolated enum LiveActivitySettings {
    static let napKey = "LiveActivity.nap.v1"
    static func napOn(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: napKey) == nil ? true : d.bool(forKey: napKey) }
}

// MARK: - Controller

@MainActor
@Observable
final class LiveActivities {
    static let shared = LiveActivities()

    /// Settings (persisted): the nap card (default on).
    var napOn: Bool { didSet { defaults.set(napOn, forKey: LiveActivitySettings.napKey) } }

    @ObservationIgnored let driver: ActivityDriver
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var calendar: Calendar = .current
    @ObservationIgnored var directory: URL? = JellyShare.containerURL
    /// How long the finished race / morning card lingers before it is dismissed.
    static let linger: TimeInterval = 10 * 60

    @ObservationIgnored private(set) var raceID: String?
    @ObservationIgnored private(set) var raceAttrs: JelbiesActivityAttributes?
    @ObservationIgnored private(set) var racePolicy = RaceActivityPolicy()
    @ObservationIgnored private(set) var napID: String?

    init(driver: ActivityDriver = ActivityKitDriver(), defaults: UserDefaults = .standard) {
        self.driver = driver; self.defaults = defaults
        napOn = LiveActivitySettings.napOn(defaults)
    }
    nonisolated deinit {}

    var raceLive: Bool { raceID != nil }
    var napLive: Bool { napID != nil }

    // MARK: race

    func raceStarted(jellyID: Int, name: String, color: String, racers: Int, laps: Int, course: String? = nil) {
        if raceID != nil { raceFinished(place: 0, drops: 0) }           // a race was somehow still up: close it
        let attrs = JelbiesActivityAttributes(kind: .race, jellyID: jellyID, jellyName: name, jellyColor: color, startedAt: now(), course: course)
        let s = JelbiesState.race(position: 1, racers: racers, progress: 0, lap: 1, laps: laps)
        racePolicy.reset(); _ = racePolicy.shouldPublish(s)
        guard driver.enabled, let id = try? driver.start(attrs, state: s, staleDate: now().addingTimeInterval(30 * 60)) else { return }
        raceID = id; raceAttrs = attrs
    }
    /// Call as often as you like: only placing / lap / quarter changes go out.
    func raceProgress(position: Int, progress: Double, lap: Int) {
        guard let id = raceID, let last = racePolicy.last else { return }
        let s = JelbiesState.race(position: position, racers: last.racers, progress: progress, lap: lap, laps: last.laps)
        guard racePolicy.shouldPublish(s) else { return }
        driver.update(id: id, state: s, staleDate: now().addingTimeInterval(30 * 60))
    }
    /// `place` 1 = won; 0 = abandoned (ended quietly).
    func raceFinished(place: Int, drops: Int) {
        guard let id = raceID else { return }
        let last = racePolicy.last ?? JelbiesState.race(position: 1, racers: 4, progress: 1, lap: 3, laps: 3)
        let s = JelbiesState.finished(place: max(place, 1), racers: last.racers, drops: drops, laps: last.laps)
        driver.end(id: id, state: s, dismissAt: now().addingTimeInterval(place == 0 ? 0 : Self.linger))
        raceID = nil; raceAttrs = nil; racePolicy.reset()
    }

    // MARK: nap

    /// Is it bedtime in the room right now (about 20:22-07:07: `SleepHours`, the room's own night)?
    func isNight(_ t: Date? = nil) -> Bool { SleepHours.isNight(at: t ?? now(), calendar: calendar) }

    /// The Jelbies go to bed: the nap card (when the setting is on). `tuckIn`: also stamp Bedtime in the App Group (Siri's "goodnight").
    func bedtime(names: [String], colors: [String] = [], now t: Date? = nil, tuckIn: Bool = true) {
        let t = t ?? now()
        if tuckIn { Bedtime.write(t, to: directory) }
        guard napOn, napID == nil, driver.enabled else { return }
        let wake = Bedtime.wakeDate(after: t, calendar: calendar)
        let attrs = JelbiesActivityAttributes(kind: .nap, jellyID: 0, jellyName: names.first ?? "Jelbie", jellyColor: colors.first ?? "blue", startedAt: t)
        guard let id = try? driver.start(attrs, state: .sleeping(names, colors: colors, wakeAt: wake), staleDate: wake) else { return }
        napID = id
    }
    /// The tuck-in alone (the in-game Bedtime button): Siri and the widget now say "asleep", no card is raised while the app is on screen.
    func tuckedIn(now t: Date? = nil) { Bedtime.write(t ?? now(), to: directory) }
    /// They are up: the stamp goes; the card says good morning and goes away (`linger` false: at once, for a card that should never have been up).
    func wake(names: [String], linger: Bool = true) {
        Bedtime.write(nil, to: directory)
        guard let id = napID else { return }
        driver.end(id: id, state: .awake(names), dismissAt: linger ? now().addingTimeInterval(Self.linger) : now())
        napID = nil
    }

    /// The app left the foreground: at night (or tucked in) the Jelbies sleep.
    func leftActive(names: [String], colors: [String] = []) {
        guard napOn else { return }
        if isNight() || Bedtime.read(from: directory, now: now()) != nil { bedtime(names: names, colors: colors, tuckIn: false) }
    }
    /// The app is back: by day the nap is over; also ends a nap whose wake time has passed. `nobodyAsleep`: the room says nobody is asleep or about to be
    /// (they were woken in game): the stamp and the card go at once, even at night.
    func returnedActive(names: [String], nobodyAsleep: Bool = false) {
        let tucked = Bedtime.read(from: directory, now: now())
        if nobodyAsleep { wake(names: names, linger: false) }
        else if !Bedtime.isSleeping(at: now(), tuckedIn: tucked, calendar: calendar) || !napOn { wake(names: names) }
    }

    // MARK: housekeeping

    /// On launch: adopt what is still running and end what is over (a race from a killed run, a nap past 06:00,
    /// anything the settings now say off).
    func cleanUp(names: [String]) {
        let t = now()
        for a in driver.existing() {
            switch a.attributes.kind {
            case .race:
                driver.end(id: a.id, state: .finished(place: max(a.state.position, 1), racers: a.state.racers, drops: 0, laps: a.state.laps), dismissAt: t)
                if raceID == a.id { raceID = nil; raceAttrs = nil; racePolicy.reset() }
            case .nap:
                let over = !napOn || (a.state.untilDate.map { $0 <= t } ?? true)
                if over { driver.end(id: a.id, state: .awake(a.state.sleepers), dismissAt: t); if napID == a.id { napID = nil } }
                else if napID == nil { napID = a.id }
            }
        }
    }
}
