//
//  JelbiesActivityAttributes.swift
//  The Live Activities (ActivityKit): a race in progress (Jelly Race) and the night nap.
//  One attributes type with a `kind`, so the widget extension has ONE ActivityConfiguration; the content state carries whatever the kind shows.
//  Compiled into the app (which starts / updates / ends) and the widget extension (which draws). Local updates only: no push server.
//

import Foundation
import ActivityKit

nonisolated struct JelbiesActivityAttributes: ActivityAttributes, Sendable {
    nonisolated enum Kind: String, Codable, Sendable, CaseIterable { case race, nap }

    var kind: Kind
    /// The Jelbie it is about (the racer); the nap lists everyone in `ContentState.sleepers`.
    var jellyID: Int
    var jellyName: String
    /// A PaletteKey raw value ("blue", "yellow", "green", "purple").
    var jellyColor: String
    /// Seconds since 1970 the activity began.
    var startedAt: Double
    /// The race's course title ("Puddle", "Ripple", "Splash", "Wave"); nil = the plain Jelly Race wording.
    var course: String? = nil

    init(kind: Kind, jellyID: Int = 0, jellyName: String = "Jelmiko", jellyColor: String = "blue", startedAt: Date = .now, course: String? = nil) {
        self.kind = kind; self.jellyID = jellyID; self.jellyName = jellyName; self.jellyColor = jellyColor; self.startedAt = startedAt.timeIntervalSince1970; self.course = course
    }

    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum Phase: String, Codable, Sendable { case running, finished, sleeping, awake }
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
        /// Each sleeper's colour key, in `sleepers` order ("blue", "yellow", "green", "lavender", "teddy", "pearl", "panda": the strings the widget snapshot uses).
        /// Optional so a payload from before this field decodes (nil: the old position colours).
        var sleeperColors: [String]? = nil
        /// Seconds since 1970 they are expected up (nap).
        var until: Double? = nil

        var untilDate: Date? { until.map { Date(timeIntervalSince1970: $0) } }

        /// A race on the track.
        static func race(position: Int, racers: Int, progress: Double, lap: Int, laps: Int) -> ContentState {
            ContentState(phase: .running, position: position, racers: racers, progress: min(max(progress, 0), 1), lap: lap, laps: laps)
        }
        /// The race result ("🥇 Pip won! +12 JellyCoins").
        static func finished(place: Int, racers: Int, drops: Int, laps: Int) -> ContentState {
            ContentState(phase: .finished, position: place, racers: racers, progress: 1, lap: laps, laps: laps, place: place, drops: drops)
        }
        static func sleeping(_ names: [String], colors: [String]? = nil, wakeAt: Date) -> ContentState {
            ContentState(phase: .sleeping, sleepers: names, sleeperColors: colors?.isEmpty == true ? nil : colors, until: wakeAt.timeIntervalSince1970)
        }
        static func awake(_ names: [String], colors: [String]? = nil) -> ContentState { ContentState(phase: .awake, sleepers: names, sleeperColors: colors?.isEmpty == true ? nil : colors) }

        /// The colour key of sleeper `i`: its own when the payload has it, else the old by-position colours.
        func sleeperColor(_ i: Int) -> String {
            if let c = sleeperColors, c.indices.contains(i) { return c[i] }
            return ["blue", "yellow", "green", "purple"][min(max(i, 0), 3)]
        }
        /// What the card draws: a nap card whose wake time has passed (`isStale`) says good morning instead of "sleeping".
        func shown(stale: Bool) -> ContentState {
            guard stale, phase == .sleeping else { return self }
            return .awake(sleepers, colors: sleeperColors)
        }

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
    /// The race headline: "Pip is racing!" / "🥇 Pip won! +12 JellyCoins" / "🥈 Pip came 2nd! +6 JellyCoins".
    nonisolated func headline(_ s: ContentState) -> String {
        switch (kind, s.phase) {
        case (.race, .finished):
            let p = s.place ?? s.position
            let drops = s.drops > 0 ? " +\(s.drops) JellyCoins" : ""
            return p == 1 ? "\(ContentState.medal(1)) \(jellyName) won!\(drops)" : "\(ContentState.medal(p)) \(jellyName) came \(ContentState.ordinal(p))!\(drops)"
        case (.race, _): return course.map { "\(jellyName) is racing on the \($0)!" } ?? "\(jellyName) is racing!"
        case (.nap, .awake): return s.sleepers.count > 1 ? "The Jelmiko are up!" : "\(s.sleepers.first ?? jellyName) is up!"
        case (.nap, _): return s.sleepers.count > 1 ? "The Jelmiko are sleeping" : "\(s.sleepers.first ?? jellyName) is sleeping"
        }
    }
    /// The second line: "2nd of 4 · lap 2 of 3" / "Up at 6:00 AM".
    /// `roundedWake`: the card a child reads says "Up around 7 AM" (the wake edge is about 07:07), not the exact minute.
    nonisolated func detail(_ s: ContentState, timeStyle: DateFormatter.Style = .short, roundedWake: Bool = false) -> String {
        switch (kind, s.phase) {
        case (.race, .finished): return "\(s.laps) lap\(s.laps == 1 ? "" : "s") on the \(course ?? "Jelly Race")"
        case (.race, _): return "\(ContentState.ordinal(s.position)) of \(s.racers) · lap \(s.lap) of \(s.laps)"
        case (.nap, .awake): return "Good morning!"
        case (.nap, _):
            guard let w = s.untilDate else { return "Shh…" }
            if roundedWake { return "Up around \(Self.hourText(nearestHour(w)))" }
            let f = DateFormatter(); f.timeStyle = timeStyle; f.dateStyle = .none
            return "Up at \(f.string(from: w))"
        }
    }
}

extension JelbiesActivityAttributes {
    /// The date rounded to the nearest whole local hour.
    nonisolated func nearestHour(_ d: Date, calendar cal: Calendar = .current) -> Date {
        let c = cal.dateComponents([.minute, .second], from: d)
        let back = TimeInterval((c.minute ?? 0) * 60 + (c.second ?? 0))
        return back >= 1800 ? d.addingTimeInterval(3600 - back) : d.addingTimeInterval(-back)
    }
    /// "7 AM" (the locale's own hour style).
    nonisolated static func hourText(_ d: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("j")
        return f.string(from: d)
    }
    /// The headline, longest first, then shorter ones for a narrow card (a long name or course): the course goes, then the "JellyCoins" word.
    nonisolated func headlineCandidates(_ s: ContentState) -> [String] {
        let full = headline(s)
        switch (kind, s.phase) {
        case (.race, .finished):
            let p = s.place ?? s.position
            let lead = p == 1 ? "\(ContentState.medal(1)) \(jellyName) won!" : "\(ContentState.medal(p)) \(jellyName) came \(ContentState.ordinal(p))!"
            return s.drops > 0 ? [full, "\(lead) +\(s.drops) coins", "\(lead) +\(s.drops)", lead] : [full, full, full, full]
        case (.race, _): return [full, "\(jellyName) is racing!", "\(jellyName) is racing!", "\(jellyName) is racing!"]
        default: return [full, full, full, full]
        }
    }
}
