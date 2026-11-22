//
//  StoryHabits.swift
//  Tiny per-Jelmiko counters of what they do lately, fed by a SAMPLER (one call per body per second from the brain's tick; no hooks in the behaviour code).
//
//  Fixed-size dictionaries of seconds: activity kind ("walk", "stand", "rest", "toy", "solo:bounce", "pair:chase", "group:conga"), partners (by the housemate's instance id),
//  pair emotes ("<partner>|<kind>") and a coarse floor area ("window", "rug", "couch", "front"). Decayed by 0.8 for every day that has passed (applied by day stamp, so a week
//  away is caught up at the next load): "lately" means the last week or two. Saved as JSON under `JellyKeys.stats(id) + ".story"` (listed in `JellyCamp.instanceKeys`, so a
//  creature's purge removes it); an old save has no key and loads empty habits.
//
//  Cost: the brain adds `dt` to a Float each tick and does the real work once a second: one label (a few enum tests), 3-4 dictionary increments on dictionaries of <= ~60 keys,
//  one area test (a few distance checks). The save is one small JSON write about once a minute of sampled time and when the app leaves the foreground, never per second.
//

import Foundation
import UIKit

nonisolated struct StoryHabits: Codable, Equatable, Sendable {
    var act: [String: Float] = [:]
    var partner: [String: Float] = [:]
    var emote: [String: Float] = [:]
    var area: [String: Float] = [:]
    /// Seconds sampled lately (decayed like the rest) and ever (not decayed, capped for sanity).
    var total: Float = 0
    var everSeconds: Float = 0
    /// Day numbers (days since 1970): when the sampler first ran, and the day the decay was last applied.
    var firstDay: Int = 0
    var decayDay: Int = 0

    static let decayPerDay: Float = 0.8
    static let maxEmoteKeys = 24, maxPartnerKeys = 8
    static let dropBelow: Float = 0.4

    // MARK: sampling

    /// Adds one second (or `dt`).
    mutating func add(activity: String, partners: [Int], area areaKey: String?, day: Int, dt: Float = 1) {
        if firstDay == 0 { firstDay = day; decayDay = day }
        act[activity, default: 0] += dt
        total += dt; everSeconds = min(everSeconds + dt, 1e9)
        if let areaKey { area[areaKey, default: 0] += dt }
        if activity.hasPrefix("pair:") || activity.hasPrefix("group:") {
            let kind = String(activity.drop(while: { $0 != ":" }).dropFirst())
            for p in partners {
                partner[String(p), default: 0] += dt
                if activity.hasPrefix("pair:") { emote["\(p)|\(kind)", default: 0] += dt }
            }
            Self.cap(&emote, Self.maxEmoteKeys); Self.cap(&partner, Self.maxPartnerKeys)
        }
    }

    private static func cap(_ d: inout [String: Float], _ n: Int) {
        guard d.count > n else { return }
        for k in d.sorted(by: { $0.value < $1.value }).prefix(d.count - n).map(\.key) { d.removeValue(forKey: k) }
    }

    /// Applies the weekly fade: x0.8 for every whole day since the last time; tiny entries go.
    mutating func decay(toDay day: Int) {
        guard decayDay != 0, day > decayDay else { if decayDay == 0 { decayDay = day }; return }
        let f = powf(Self.decayPerDay, Float(min(day - decayDay, 60)))
        decayDay = day
        for k in act.keys { act[k]! *= f }
        for k in partner.keys { partner[k]! *= f }
        for k in emote.keys { emote[k]! *= f }
        for k in area.keys { area[k]! *= f }
        total *= f
        act = act.filter { $0.value >= Self.dropBelow }; partner = partner.filter { $0.value >= Self.dropBelow }
        emote = emote.filter { $0.value >= Self.dropBelow }; area = area.filter { $0.value >= Self.dropBelow }
    }

    // MARK: derived facts

    /// Activities that say nothing about what a Jelmiko likes to do (standing about, walking about, resting).
    static let plainKinds: Set<String> = ["stand", "walk", "rest"]

    /// How much has been seen lately, in minutes (decayed seconds).
    var minutes: Int { Int(total / 60) }
    /// Enough lately to say anything about habits (about five minutes of room life).
    var hasHistory: Bool { total >= 300 }

    /// The favourite thing to do lately: the solo / pair / toy activity with the most time, when it is a clear favourite (at least 8 % of the time and 60 s). Its key is "bounce", "chase", "toy" ...
    var favouriteActivity: (key: String, kindOfPlay: String)? {
        let pick = act.filter { !Self.plainKinds.contains($0.key) && !$0.key.hasPrefix("group:") && $0.value >= 60 && $0.value >= 0.08 * max(total, 1) }
            .max { ($0.value, $1.key) < ($1.value, $0.key) }
        guard let p = pick else { return nil }
        let parts = p.key.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[1], parts[0]) : (p.key, p.key)
    }
    /// What the day mostly is: "rest", "walk" or "play", when it clearly is.
    var restShare: Double { total > 0 ? Double((act["rest"] ?? 0) / total) : 0 }
    /// The time with housemates (pair + group sessions) as a share of the time sampled.
    var togetherShare: Double {
        guard total > 0 else { return 0 }
        let t = act.filter { $0.key.hasPrefix("pair:") || $0.key.hasPrefix("group:") }.values.reduce(0, +)
        return Double(min(t / total, 1))
    }
    /// The floor area where they spend the most time, when it clearly beats a fair share (>= 35 % of the area time and at least two minutes).
    var favouriteSpot: String? {
        let t = area.values.reduce(0, +)
        guard t >= 120, let m = area.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), m.value >= 0.35 * t else { return nil }
        return m.key
    }
    /// The housemate (instance id) played with most lately, when there is real time with someone (>= 60 s).
    var mostPlayedWith: Int? {
        guard let m = partner.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), m.value >= 60 else { return nil }
        return Int(m.key)
    }
    func seconds(with id: Int) -> Int { Int(partner[String(id)] ?? 0) }
    /// The share of all the pair time that was with this housemate (0 when there is none).
    func playShare(with id: Int) -> Double {
        let t = partner.values.reduce(0, +)
        return t > 0 ? Double((partner[String(id)] ?? 0) / t) : 0
    }
    /// The pair emote the two do together most, nil when there is not enough (>= 30 s of one kind).
    func topEmote(with id: Int) -> String? {
        let pre = "\(id)|"
        let m = emote.filter { $0.key.hasPrefix(pre) && $0.value >= 30 }.max { ($0.value, $1.key) < ($1.value, $0.key) }
        return m.map { String($0.key.dropFirst(pre.count)) }
    }
}

// MARK: the floor area and the label (pure, used by the sampler)

nonisolated enum StorySampling {
    /// Window side (the back wall), the couch, the rug, the front of the room; nil for the open floor in between. From the floor position (x, z), the room's own layout.
    static func area(x: Float, z: Float, sofaDistance: Float, rugDistance: Float, backZ: Float, frontZ: Float) -> String? {
        if sofaDistance < 1.1 { return "couch" }
        if z < backZ + 1.7 { return "window" }
        if rugDistance < 1.8 { return "rug" }
        if z > frontZ - 2.0 { return "front" }
        return nil
    }
}

/// Where the counters live: in memory per instance id, saved lazily. MainActor (the stage's tick and the Profile are on it).
@MainActor
final class StoryHabitStore {
    static let shared = StoryHabitStore()
    private(set) var books: [Int: StoryHabits] = [:]
    private var dirty: Set<Int> = []
    private var sinceSave: Float = 0
    var defaults: UserDefaults = .standard
    /// Slot (the room's body index) -> instance id; set by the stage. nil = not a home Jelmiko.
    var resolve: (Int) -> Int? = { $0 }
    /// Test hook: today's day number.
    var today: () -> Int = { Int(Date().timeIntervalSince1970 / 86400) }
    private var observer: NSObjectProtocol?

    static func key(_ id: Int) -> String { JellyKeys.stats(id) + ".story" }

    init() {
        observer = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    func habits(_ id: Int) -> StoryHabits {
        if let b = books[id] { return b }
        var b = Self.load(id, defaults)
        b.decay(toDay: today())
        books[id] = b
        return b
    }

    static func load(_ id: Int, _ d: UserDefaults) -> StoryHabits {
        guard let data = d.data(forKey: key(id)), let h = try? JSONDecoder().decode(StoryHabits.self, from: data) else { return StoryHabits() }
        return h
    }

    /// The sampler's one entry: a second of life for `slot`.
    func sample(slot: Int, activity: String, partnerSlots: [Int], area: String?) {
        guard let id = resolve(slot) else { return }
        let ps = partnerSlots.compactMap { resolve($0) }.filter { $0 != id }
        var h = habits(id)
        let day = today()
        if h.decayDay != 0, day > h.decayDay { h.decay(toDay: day) }
        h.add(activity: activity, partners: ps, area: area, day: day)
        books[id] = h; dirty.insert(id)
        sinceSave += 1
        if sinceSave >= 60 { flush() }
    }

    func flush() {
        sinceSave = 0
        for id in dirty { if let b = books[id], let data = try? JSONEncoder().encode(b) { defaults.set(data, forKey: Self.key(id)) } }
        dirty.removeAll()
    }

    /// Replaces a body's counters (dev seeding, tests).
    func set(_ h: StoryHabits, for id: Int) { books[id] = h; dirty.insert(id); flush() }
    /// Drops everything held for `id` (the purge); the saved key is removed by `JellyCamp.purge`.
    func forget(_ id: Int) { books.removeValue(forKey: id); dirty.remove(id) }
    func reset() { books = [:]; dirty = [] }
}
