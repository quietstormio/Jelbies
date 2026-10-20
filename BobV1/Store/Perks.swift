//
//  Perks.swift
//  Timed perks on a Jelly (from store food, treats and supplies). Pure model, persisted per Jelly under ABSOLUTE expiry dates, so a relaunch (and
//  time away) respects them. The same perk again refreshes the duration; it never stacks magnitude.
//
//    cozy       love / mood falls slower (attention x0.5, hunger and thirst x0.8)
//    zoomies    "Sugar rush": zoomies in the room now AND a small boost in his next race (consumed by it), if raced within 30 min
//    focus      "Focus snack": a wider same-foot tolerance window in his next race (consumed by it), within 30 min
//    fullBelly  hunger falls slower (x0.5)
//    shine      the shine after a Clean lasts longer (sparkle fades x0.4 as fast)
//    tidy       lint comes back slower (dirt builds x0.5)
//    bedtime    falls asleep faster, deeper (night naps drain slower) - the "bedtime cookie"
//    bouncy     more antics while you watch
//    social     plays with the others more
//

import Foundation
import Observation

nonisolated enum PerkKind: String, CaseIterable, Codable, Sendable {
    case cozy, zoomies, focus, fullBelly, shine, tidy, bedtime, bouncy, social

    var title: String {
        switch self {
        case .cozy: return "Cozy"; case .zoomies: return "Sugar rush"; case .focus: return "Focused"; case .fullBelly: return "Full belly"
        case .shine: return "Shiny"; case .tidy: return "Tidy"; case .bedtime: return "Sleepy"; case .bouncy: return "Bouncy"; case .social: return "Social"
        }
    }
    var blurb: String {
        switch self {
        case .cozy: return "Stays happy longer and needs less love."
        case .zoomies: return "Zoomies now, and a little faster in his next race."
        case .focus: return "Fewer stumbles in his next race."
        case .fullBelly: return "Gets hungry much more slowly."
        case .shine: return "Clean shine lasts longer."
        case .tidy: return "Lint comes back slower."
        case .bedtime: return "Falls asleep fast and sleeps deep."
        case .bouncy: return "Bounces and plays more."
        case .social: return "Plays with the others more."
        }
    }
    var symbol: String {
        switch self {
        case .cozy: return "heart.fill"; case .zoomies: return "bolt.fill"; case .focus: return "scope"; case .fullBelly: return "fork.knife"
        case .shine: return "sparkles"; case .tidy: return "wind"; case .bedtime: return "moon.zzz.fill"; case .bouncy: return "arrow.up.circle.fill"
        case .social: return "person.2.fill"
        }
    }
    /// Seconds a fresh serving lasts.
    var duration: TimeInterval {
        switch self {
        case .cozy: return 4 * 3600; case .zoomies: return 30 * 60; case .focus: return 30 * 60; case .fullBelly: return 4 * 3600
        case .shine: return 12 * 3600; case .tidy: return 6 * 3600; case .bedtime: return 8 * 3600; case .bouncy: return 3600; case .social: return 3600
        }
    }
    /// Used up by the next race.
    var raceOnly: Bool { self == .zoomies || self == .focus }
}

nonisolated enum PerkTuning {
    static let defaultsKey = "BlobPerks.v1"
    /// Drain multipliers by need (hunger, thirst, attention).
    static let cozyDrain: [Double] = [0.8, 0.8, 0.5]
    static let fullBellyHunger = 0.5
    static let shineFade: Float = 0.4
    static let tidyDirt: Float = 0.5
    /// Race boost: modest, and never above what a fully trained Jelly has (the clamp is in RaceBoost).
    static let raceStride: Float = 0.04
    static let raceRate: Float = 0.06
    /// The focus snack forgives a repeated foot tap inside this window (seconds).
    static let focusGrace: Float = 0.22
    /// Night naps drain by this instead of NeedsTuning.napDrain while the bedtime perk is on.
    static let bedtimeNapDrain: Float = 0.35
    /// Weight multiplier for the antic kinds / social play while bouncy / social is on.
    static let anticBoost: Float = 2.2
    static let socialBoost: Float = 2.0

    /// The persisted key of the perks that belong to a needs / grime key (nil = no perks for that Jelly).
    static func key(forNeeds k: String) -> String? { k.contains(NeedsTuning.defaultsKey) ? k.replacingOccurrences(of: NeedsTuning.defaultsKey, with: defaultsKey) : nil }
    static func key(forGrime k: String) -> String? { k.contains(GrimeTuning.defaultsKey) ? k.replacingOccurrences(of: GrimeTuning.defaultsKey, with: defaultsKey) : nil }
}

/// What a race gets from the player's perks.
nonisolated struct RaceBoost: Equatable, Sendable {
    var strideMul: Float = 1
    var rateMul: Float = 1
    /// Seconds a repeated foot is forgiven.
    var grace: Float = 0
    static let none = RaceBoost()
    var isNone: Bool { self == .none }

    /// `stride` / `rate` after the boost, never above the fully trained value (waddle 1).
    func apply(stride: Float, rate: Float) -> (stride: Float, rate: Float) {
        (min(stride * strideMul, max(stride, RaceTuning.stride(waddle: 1))), min(rate * rateMul, max(rate, RaceTuning.maxRate(waddle: 1))))
    }
}

/// Persisted expiries without the object (the needs / grime models read the time away from it at load).
nonisolated enum PerkStore {
    static func load(defaults: UserDefaults, key: String) -> [PerkKind: Date] {
        guard let d = defaults.dictionary(forKey: key) as? [String: Double] else { return [:] }
        var out: [PerkKind: Date] = [:]
        for (k, t) in d { if let p = PerkKind(rawValue: k) { out[p] = Date(timeIntervalSince1970: t) } }
        return out
    }
    /// Seconds of the window [from, to] during which `kind` (expiring at `e`) was on.
    static func overlap(expiry e: Date, from: Date, to: Date) -> TimeInterval { max(0, min(e, to).timeIntervalSince(from)) }
    /// The effective away seconds when a need drains at `mul` while a perk is on: away - covered x (1 - mul).
    static func effective(away: TimeInterval, covered: TimeInterval, mul: Double) -> TimeInterval { max(0, away - covered * (1 - mul)) }
    /// Sums the cover of perks that slow need `kind` index (0 hunger, 1 thirst, 2 attention) from `from` to `to`, as a single multiplier-weighted credit.
    static func needCredit(_ ex: [PerkKind: Date], need i: Int, from: Date, to: Date) -> TimeInterval {
        var credit: TimeInterval = 0
        // the strongest slowing perk wins over the window (they do not multiply)
        var best = 1.0, covered: TimeInterval = 0
        for (k, e) in ex {
            var mul = 1.0
            if k == .cozy { mul = PerkTuning.cozyDrain[i] }
            if k == .fullBelly, i == 0 { mul = PerkTuning.fullBellyHunger }
            guard mul < 1 else { continue }
            let c = overlap(expiry: e, from: from, to: to)
            if mul < best || (mul == best && c > covered) { best = mul; covered = c }
        }
        if best < 1 { credit = covered * (1 - best) }
        return credit
    }
}

@MainActor
@Observable
final class JellyPerks {
    /// Perk -> absolute expiry. Only live perks are kept.
    private(set) var expiry: [PerkKind: Date] = [:]
    /// Bumped whenever the set changes (the UI badge reads it).
    private(set) var revision = 0

    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var sinceCheck: Float = 0

    nonisolated deinit {}

    init(persists: Bool = true, defaults: UserDefaults = .standard, key: String = PerkTuning.defaultsKey, now: @escaping () -> Date = Date.init) {
        self.persists = persists; self.defaults = defaults; self.key = key; self.now = now
        if persists { expiry = PerkStore.load(defaults: defaults, key: key) }
        prune(); refreshCache()
    }

    // MARK: queries

    func isActive(_ k: PerkKind) -> Bool { (expiry[k] ?? .distantPast) > now() }
    func remaining(_ k: PerkKind) -> TimeInterval { max(0, (expiry[k] ?? .distantPast).timeIntervalSince(now())) }
    /// Live perks, soonest to end first.
    var active: [PerkKind] { expiry.filter { $0.value > now() }.sorted { $0.value < $1.value }.map(\.key) }

    /// Need drain multipliers (hunger, thirst, attention): the strongest slowing perk for each, not a product.
    var needDrain: [Double] {
        var m = [1.0, 1.0, 1.0]
        if isActive(.cozy) { for i in 0..<3 { m[i] = min(m[i], PerkTuning.cozyDrain[i]) } }
        if isActive(.fullBelly) { m[0] = min(m[0], PerkTuning.fullBellyHunger) }
        return m
    }
    var sparkleFadeMul: Float { isActive(.shine) ? PerkTuning.shineFade : 1 }
    var dirtMul: Float { isActive(.tidy) ? PerkTuning.tidyDirt : 1 }
    var napDrain: Float { isActive(.bedtime) ? PerkTuning.bedtimeNapDrain : NeedsTuning.napDrain }

    /// The same values, cached for the per-step callers (refreshed on every change and about once a second).
    struct Cache { var drain: [Double] = [1, 1, 1]; var fade: Float = 1; var dirt: Float = 1; var any = false }
    @ObservationIgnored private(set) var cache = Cache()
    private func refreshCache() { cache = Cache(drain: needDrain, fade: sparkleFadeMul, dirt: dirtMul, any: !expiry.isEmpty) }

    /// What the next race would get (not consumed).
    var raceBoost: RaceBoost {
        var b = RaceBoost()
        if isActive(.zoomies) { b.strideMul = 1 + PerkTuning.raceStride; b.rateMul = 1 + PerkTuning.raceRate }
        if isActive(.focus) { b.grace = PerkTuning.focusGrace }
        return b
    }

    // MARK: change

    /// Starts the perk, or refreshes it to a full duration. Never stacks.
    func grant(_ k: PerkKind, duration: TimeInterval? = nil) {
        expiry[k] = now().addingTimeInterval(duration ?? k.duration)
        revision += 1
        refreshCache()
        save()
    }
    func clear(_ k: PerkKind) { if expiry.removeValue(forKey: k) != nil { revision += 1; refreshCache(); save() } }

    /// A race starts for him: the race perks go with it. Returns what the race gets.
    @discardableResult
    func consumeRaceBoost() -> RaceBoost {
        let b = raceBoost
        for k in PerkKind.allCases where k.raceOnly { expiry[k] = nil }
        if !b.isNone { revision += 1; refreshCache(); save() }
        return b
    }

    /// Drops expired perks (the model calls it about once a second).
    func prune() {
        let t = now()
        let live = expiry.filter { $0.value > t }
        if live.count != expiry.count { expiry = live; revision += 1; save() }
        if cache.any || !live.isEmpty { refreshCache() }
    }
    func step(dt: Float) {
        sinceCheck += dt
        if sinceCheck >= 1 { sinceCheck = 0; prune() }
    }

    func save() {
        guard persists else { return }
        defaults.set(Dictionary(uniqueKeysWithValues: expiry.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }), forKey: key)
    }
}
