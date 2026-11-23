//
//  StoryEvents.swift
//  A small per-Jelmiko log of RECENT EVENTS (the news the living line prefers): race results, Jelly Show results, volleyball, a park visit, a cafe visit, bubble play, ball play, a bath or a
//  groom, a trick on voice, a favourite meal, a cuddle, a new Relationship stage. Fed from the ONE funnel the Relationship already uses (`GameCare.bondEarn`), with the details each call site knows.
//  About the last 20, dropped after 14 days; saved as JSON under `JellyKeys.stats(id) + ".events"` (in `JellyCamp.instanceKeys`, so the purge removes it).
//

import Foundation

nonisolated struct StoryEvent: Codable, Equatable, Sendable {
    /// race, show, volley, park, cafe, bubbles, ball, bath, groom, trick, meal, cuddle, bond
    var kind: String
    /// Days since 1970 (the real calendar day).
    var day: Int
    /// A few details: "tier" (course / Show level / court title), "place" (1...), "win" ("1"), "food" (a snack id), "level" (a Relationship stage name).
    var d: [String: String] = [:]

    /// The fact key a line about it names.
    var factKey: String { "recent" + kind.prefix(1).uppercased() + kind.dropFirst() }
    /// A stable key for "this news item was already used for its day".
    var id: String { "\(kind).\(day).\(d.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))" }

    static let kinds = ["race", "show", "volley", "park", "cafe", "bubbles", "ball", "bath", "groom", "trick", "meal", "cuddle", "bond"]
    static let keep = 20, keepDays = 14
}

nonisolated struct StoryEventList: Codable, Equatable, Sendable {
    var events: [StoryEvent] = []

    /// Adds an event (newest last). The same kind with the same details on the same day is one entry; the list keeps the last 20 and drops what is older than two weeks.
    mutating func add(_ e: StoryEvent) {
        if let i = events.lastIndex(where: { $0.id == e.id }) { events.remove(at: i) }
        events.append(e)
        trim(today: e.day)
    }
    mutating func trim(today: Int) {
        events = events.filter { today - $0.day <= StoryEvent.keepDays }
        if events.count > StoryEvent.keep { events.removeFirst(events.count - StoryEvent.keep) }
    }
    /// The newest event of each kind first.
    func newestFirst() -> [StoryEvent] { events.reversed() }
}

@MainActor
final class StoryEventStore {
    static let shared = StoryEventStore()
    var defaults: UserDefaults = .standard
    var today: () -> Int = { Int(Date().timeIntervalSince1970 / 86400) }

    static func key(_ id: Int) -> String { JellyKeys.stats(id) + ".events" }

    func list(_ id: Int) -> StoryEventList {
        guard let data = defaults.data(forKey: Self.key(id)), var l = try? JSONDecoder().decode(StoryEventList.self, from: data) else { return StoryEventList() }
        l.trim(today: today())
        return l
    }

    func record(_ kind: String, character id: Int, _ d: [String: String] = [:]) {
        var l = list(id)
        l.add(StoryEvent(kind: kind, day: today(), d: d))
        if let data = try? JSONEncoder().encode(l) { defaults.set(data, forKey: Self.key(id)) }
    }
}

extension BondKind {
    /// The story kind of a Relationship event (nil = not news).
    func storyKind(_ d: [String: String]) -> String? {
        switch self {
        case .race: return "race"
        case .show: return "show"
        case .volley: return "volley"
        case .park: return "park"
        case .care: return d["care"] ?? "bath"
        case .toy: return d["toy"] ?? "ball"
        case .trick: return "trick"
        case .stroke: return "cuddle"
        case .meal: return d["where"] == "cafe" ? "cafe" : (d["food"] != nil ? "meal" : nil)
        case .drink, .dayOpen: return nil
        }
    }
}

extension GameCare {
    /// Called from `bondEarn` (after the Relationship counted): records the news item with the details the call site knew, and a "bond" event when a new Relationship stage was reached.
    func storyRecord(_ kind: BondKind, character c: Int, detail d: [String: String], levelBefore: Int, levelAfter: Int) {
        if let k = kind.storyKind(d) { StoryEventStore.shared.record(k, character: c, d.filter { $0.key != "care" && $0.key != "toy" && $0.key != "where" }) }
        if levelAfter > levelBefore { StoryEventStore.shared.record("bond", character: c, ["level": BondTuning.levelNames[min(levelAfter, BondTuning.levelNames.count - 1)]]) }
    }
}
