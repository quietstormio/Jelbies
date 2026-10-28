//
//  JelbiesActivityAttributes.swift
//  The Live Activities (ActivityKit): a race in progress (Jelly Circuit), the night nap, and the training Pep refill countdown.
//  One attributes type with a `kind`, so the widget extension has ONE ActivityConfiguration; the content state carries whatever the kind shows.
//  Compiled into the app (which starts / updates / ends) and the widget extension (which draws). Local updates only: no push server.
//

import Foundation
import ActivityKit

nonisolated struct JelbiesActivityAttributes: ActivityAttributes, Sendable {
    nonisolated enum Kind: String, Codable, Sendable, CaseIterable { case race, nap, pep }

    var kind: Kind
    /// The Jelbie it is about (the racer / the trainee); the nap lists everyone in `ContentState.sleepers`.
    var jellyID: Int
    var jellyName: String
    /// A PaletteKey raw value ("blue", "yellow", "green", "purple").
    var jellyColor: String
    /// Seconds since 1970 the activity began.
    var startedAt: Double
    /// The race's course title ("Puddle", "Ripple", "Splash", "Wave"); nil = the plain Jelly Circuit wording.
    var course: String? = nil

    init(kind: Kind, jellyID: Int = 0, jellyName: String = "Bob", jellyColor: String = "blue", startedAt: Date = .now, course: String? = nil) {
        self.kind = kind; self.jellyID = jellyID; self.jellyName = jellyName; self.jellyColor = jellyColor; self.startedAt = startedAt.timeIntervalSince1970; self.course = course
    }

    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum Phase: String, Codable, Sendable { case running, finished, sleeping, awake, refilling, refilled }
        var phase: Phase
        // race
        /// 1-based position and the number of racers.
        var position: Int = 1
        var racers: Int = 4
        /// 0...1 around the whole race (all laps).
        var progress: Double = 0
        var lap: Int = 1
        var laps: Int = 3
        /// The finish: place (1 = won) and the Drops earned.
        var place: Int? = nil
        var drops: Int = 0
        // nap
        /// Names of the Jelbies asleep.
        var sleepers: [String] = []
        /// Seconds since 1970 they are expected up (nap) / Pep is back (pep).
        var until: Double? = nil
        // pep
        /// Pep left 0...1 (0 while refilling).
        var pep: Double = 0

        var untilDate: Date? { until.map { Date(timeIntervalSince1970: $0) } }

        /// A race on the track.
        static func race(position: Int, racers: Int, progress: Double, lap: Int, laps: Int) -> ContentState {
            ContentState(phase: .running, position: position, racers: racers, progress: min(max(progress, 0), 1), lap: lap, laps: laps)
        }
        /// The race result ("🥇 Bob won! +12 Drops").
        static func finished(place: Int, racers: Int, drops: Int, laps: Int) -> ContentState {
            ContentState(phase: .finished, position: place, racers: racers, progress: 1, lap: laps, laps: laps, place: place, drops: drops)
        }
        static func sleeping(_ names: [String], wakeAt: Date) -> ContentState {
            ContentState(phase: .sleeping, sleepers: names, until: wakeAt.timeIntervalSince1970)
        }
        static func awake(_ names: [String]) -> ContentState { ContentState(phase: .awake, sleepers: names) }
        static func refilling(until: Date) -> ContentState { ContentState(phase: .refilling, until: until.timeIntervalSince1970, pep: 0) }
        static let refilled = ContentState(phase: .refilled, pep: 1)

        /// "1st" / "2nd" / "3rd" / "4th".
        static func ordinal(_ n: Int) -> String {
            let t = n % 100
            if (11...13).contains(t) { return "\(n)th" }
            switch n % 10 { case 1: return "\(n)st"; case 2: return "\(n)nd"; case 3: return "\(n)rd"; default: return "\(n)th" }
        }
        /// The medal / place glyph.
        static func medal(_ place: Int) -> String { ["🥇", "🥈", "🥉"].indices.contains(place - 1) ? ["🥇", "🥈", "🥉"][place - 1] : "🏁" }
    }
}

// MARK: - Words

extension JelbiesActivityAttributes {
    /// The race headline: "Bob is racing!" / "🥇 Bob won! +12 Drops" / "🥈 Bob came 2nd! +6 Drops".
    nonisolated func headline(_ s: ContentState) -> String {
        switch (kind, s.phase) {
        case (.race, .finished):
            let p = s.place ?? s.position
            let drops = s.drops > 0 ? " +\(s.drops) JellyCoins" : ""
            return p == 1 ? "\(ContentState.medal(1)) \(jellyName) won!\(drops)" : "\(ContentState.medal(p)) \(jellyName) came \(ContentState.ordinal(p))!\(drops)"
        case (.race, _): return course.map { "\(jellyName) is racing on the \($0)!" } ?? "\(jellyName) is racing!"
        case (.nap, .awake): return s.sleepers.count > 1 ? "The Jelbies are up!" : "\(s.sleepers.first ?? jellyName) is up!"
        case (.nap, _): return s.sleepers.count > 1 ? "The Jelbies are sleeping" : "\(s.sleepers.first ?? jellyName) is sleeping"
        case (.pep, .refilled): return "Pep is back!"
        case (.pep, _): return "\(jellyName) is out of Pep"
        }
    }
    /// The second line: "2nd of 4 · lap 2 of 3" / "Up at 6:00 AM" / "Refills at midnight".
    nonisolated func detail(_ s: ContentState, timeStyle: DateFormatter.Style = .short) -> String {
        switch (kind, s.phase) {
        case (.race, .finished): return "\(s.laps) lap\(s.laps == 1 ? "" : "s") on the \(course ?? "Jelly Circuit")"
        case (.race, _): return "\(ContentState.ordinal(s.position)) of \(s.racers) · lap \(s.lap) of \(s.laps)"
        case (.nap, .awake): return "Good morning!"
        case (.nap, _):
            guard let w = s.untilDate else { return "Shh…" }
            let f = DateFormatter(); f.timeStyle = timeStyle; f.dateStyle = .none
            return "Up at \(f.string(from: w))"
        case (.pep, .refilled): return "Ready to train"
        case (.pep, _): return "Pep refills at midnight"
        }
    }
}
