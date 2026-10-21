//
//  EventLog.swift
//  What happened to each Jelly, per day: ate X, napped, played with Y, raced and placed N, tripped, new outfit, trained, got bathed, social with Z.
//  The diary and the thought lines read it. Persisted lightly (one JSON blob in UserDefaults, `JellyEventLog.v1`), the last 7 days only, capped.
//  Days are local calendar days keyed "yyyy-MM-dd". The recorder (AIHub.swift) writes; views only read.
//

import Foundation
import Observation

nonisolated enum JellyEventKind: String, Codable, CaseIterable, Sendable {
    case ate, drank, napped, played, raced, tripped, outfit, trained, trick, bathed, social, cuddled, obeyed, squabbled
}

nonisolated struct JellyEvent: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var jelly: Int
    var kind: JellyEventKind
    /// What: the food, the trick, the game, the outfit, the race place ("2").
    var detail: String? = nil
    /// Who: the other Jelly of a social / play.
    var partner: Int? = nil
    var date: Date

    var day: String { EventLog.dayKey(date) }
}

@MainActor
@Observable
final class EventLog {
    static let defaultsKey = "JellyEventLog.v1"
    static let keepDays = 7
    static let cap = 600

    private(set) var events: [JellyEvent] = []
    /// Bumped on every record (cheap to observe).
    private(set) var serial = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var sinceSave: Double = 0

    nonisolated deinit {}

    init(defaults: UserDefaults = .standard, key: String = EventLog.defaultsKey, persists: Bool = true, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.key = key; self.persists = persists; self.now = now
        if persists {
            if defaults.bool(forKey: "VoiceReset") || defaults.bool(forKey: "DiaryReset") { defaults.removeObject(forKey: key) }
            load()
        }
        prune()
    }

    nonisolated static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = .current; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    nonisolated static func dayKey(_ d: Date) -> String { dayFormatter.string(from: d) }
    nonisolated static func date(ofDay key: String) -> Date? { dayFormatter.date(from: key) }

    var today: String { Self.dayKey(now()) }
    var yesterday: String { Self.dayKey(now().addingTimeInterval(-86_400)) }

    // MARK: write

    @discardableResult
    func record(_ kind: JellyEventKind, jelly: Int, detail: String? = nil, partner: Int? = nil, at date: Date? = nil) -> JellyEvent {
        let e = JellyEvent(jelly: jelly, kind: kind, detail: detail, partner: partner, date: date ?? now())
        events.append(e)
        serial += 1
        prune()
        dirty = true
        if VoiceCoordinator.logging { NSLog("AILOG event jelly=%d %@ %@ partner=%@", jelly, kind.rawValue, detail ?? "", partner.map(String.init) ?? "-") }
        return e
    }

    /// Drops everything older than `keepDays` days (by day key, so "today minus 7" is kept until midnight) and the oldest past the cap.
    func prune() {
        let cutoff = Self.dayKey(now().addingTimeInterval(-Double(Self.keepDays) * 86_400))
        events.removeAll { $0.day < cutoff }
        if events.count > Self.cap { events.removeFirst(events.count - Self.cap) }
    }

    /// Periodic save (the recorder calls it every step; writes at most every few seconds and only when something changed).
    func tick(dt: Double) {
        sinceSave += dt
        if dirty, sinceSave > 3 { save(); sinceSave = 0 }
    }

    func save() {
        dirty = false
        guard persists, let d = try? JSONEncoder().encode(events) else { return }
        defaults.set(d, forKey: key)
    }
    func load() {
        guard let d = defaults.data(forKey: key), let e = try? JSONDecoder().decode([JellyEvent].self, from: d) else { return }
        events = e
    }
    func clear() { events = []; serial += 1; save() }

    // MARK: read

    func events(jelly: Int, day: String) -> [JellyEvent] { events.filter { $0.jelly == jelly && $0.day == day } }
    func events(jelly: Int) -> [JellyEvent] { events.filter { $0.jelly == jelly } }
    /// Day keys with events for this Jelly, newest first.
    func days(jelly: Int) -> [String] { Array(Set(events(jelly: jelly).map(\.day))).sorted(by: >) }
    /// The last event of a kind for a Jelly today (the thought lines read "just ate").
    func last(_ kind: JellyEventKind, jelly: Int) -> JellyEvent? { events.last { $0.jelly == jelly && $0.kind == kind } }
    /// Seconds since the last event of a kind (nil = none today).
    func since(_ kind: JellyEventKind, jelly: Int) -> TimeInterval? { last(kind, jelly: jelly).map { now().timeIntervalSince($0.date) } }

    /// Counts per kind for a day (the summaries and the templates read it).
    static func tally(_ es: [JellyEvent]) -> [JellyEventKind: Int] {
        var t: [JellyEventKind: Int] = [:]
        for e in es { t[e.kind, default: 0] += 1 }
        return t
    }

    /// The day's events as short plain facts for the model ("ate berries twice", "napped in the sun", "played zoomies with Pip").
    static func facts(_ es: [JellyEvent], names: (Int) -> String) -> [String] {
        var out: [String] = []
        var seen: [String: Int] = [:]
        for e in es {
            var f: String
            switch e.kind {
            case .ate: f = "ate \(e.detail ?? "a snack")"
            case .drank: f = "drank \(e.detail ?? "water")"
            case .napped: f = "took a nap"
            case .played: f = "played \(e.detail ?? "a game")" + (e.partner.map { " with \(names($0))" } ?? "")
            case .raced: f = "raced" + (e.detail.map { " and came \($0)" } ?? "")
            case .tripped: f = "tripped and got up again"
            case .outfit: f = "wore \(e.detail ?? "a new outfit")"
            case .trained: f = "learned the word for \(e.detail ?? "a trick")"
            case .trick: f = "did the \(e.detail ?? "trick") trick"
            case .bathed: f = "had a bath"
            case .social: f = "\(e.detail ?? "hung out") with \(e.partner.map(names) ?? "a friend")"
            case .cuddled: f = "got cuddles"
            case .obeyed: f = "listened when asked to \(e.detail ?? "come")"
            case .squabbled: f = "had a little squabble with \(e.partner.map(names) ?? "a friend")"
            }
            seen[f, default: 0] += 1
            if seen[f] == 1 { out.append(f) }
        }
        return out.map { f in let n = seen[f] ?? 1; return n > 1 ? "\(f) (\(n) times)" : f }
    }
}
