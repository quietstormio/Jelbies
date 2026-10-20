//
//  Needs.swift
//  Needs + mood v1 (see docs/Emotions.md). Three needs the player can fix: hunger (Feed), thirst (Drink), attention (petting in focus mode).
//  Each is 0...1 and decays in real time; below `wanting` the Blob wants it. Mood is derived: happy / okay / grumpy.
//  Persisted to UserDefaults with a timestamp. Time away (cold launch AND every return to the foreground) goes through ONE path, `applyAway`:
//  a slower "away" curve with a floor, so he wants things when you come back but is never starving (see TimeAway.swift).
//  The first launch ever is seeded with hunger wanting, so a fresh install shows a food bubble.
//
//  Pure model (no views): GameCare ticks it, ThoughtBubbleView / the roster read it. Touch reactions read `mood` / `wantedNeed` (worker B).
//

import Foundation
import Observation

/// The app-side half of NeedKind (the rest lives in Shared/NeedsCore.swift, which the widget also compiles).
extension NeedKind {
    /// What the player does about it.
    var action: BubbleAction {
        switch self { case .hunger: return .feed; case .thirst: return .drink; case .attention: return .comeHere }
    }
}

/// What tapping a thought bubble opens.
enum BubbleAction: Equatable, Sendable { case feed, drink, comeHere, clean }

@MainActor
@Observable
final class BlobNeeds {
    /// UI snapshot of the levels (updated only when a bar would visibly move, so views do not re-render every step).
    private(set) var levels: [Float] = [1, 1, 1]
    private(set) var mood: BlobMood = .happy
    /// The need he wants most (lowest level below `wanting`; hunger first on a tie), or nil.
    private(set) var wantedNeed: NeedKind?

    @ObservationIgnored private var raw: [Float] = [1, 1, 1]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private var sinceSave: Float = 0
    /// Set when the app leaves the foreground, cleared when away time is applied. While set, `save()` keeps writing THIS as the timestamp, so the
    /// 15 s periodic save (or anything else that saves in the background) can never stamp over time that has not been applied yet.
    @ObservationIgnored private var awaySince: Date?
    /// The away time (seconds, clamped) the last load / return applied. GameCare reads it for the greeting.
    @ObservationIgnored private(set) var lastAway: TimeInterval = 0
    @ObservationIgnored private var lastWantedSet: Set<NeedKind> = []
    /// Where this Jelly's perks are persisted (their expiries shorten the time away that counts, see applyAway).
    @ObservationIgnored private var perkKey: String? { PerkTuning.key(forNeeds: key) }
    /// Counts the needs fixed (restored from wanting to not wanting), and which was the last (the bubble's sparkle reads this).
    @ObservationIgnored private(set) var fixedCount = 0
    @ObservationIgnored private(set) var lastFixed: NeedKind?
    @ObservationIgnored var onFixed: ((NeedKind) -> Void)?

    nonisolated deinit {}

    /// `persists: false` makes an in-memory Blob (preview Blobs); `key` separates Blobs.
    init(defaults: UserDefaults = .standard, key: String = NeedsTuning.defaultsKey, now: @escaping () -> Date = Date.init, persists: Bool = true) {
        self.defaults = defaults; self.key = key; self.now = now; self.persists = persists
        if persists {
            if defaults.bool(forKey: "NeedsReset") { defaults.removeObject(forKey: key) }       // capture aid: -NeedsReset 1 re-seeds
            load()
            if defaults.bool(forKey: "NeedsHappy") { raw = [1, 1, 1]; publish(force: true) }       // capture aid: -NeedsHappy 1 starts every need full
        } else {
            raw = [NeedsTuning.seedOthers, NeedsTuning.seedOthers, NeedsTuning.seedOthers]
        }
        lastWantedSet = wantedSet
        publish(force: true)
    }

    // MARK: queries

    func level(_ k: NeedKind) -> Float { raw[k.rawValue] }
    func tier(_ k: NeedKind) -> NeedTier { NeedTier.of(level: raw[k.rawValue]) }
    func isWanting(_ k: NeedKind) -> Bool { raw[k.rawValue] < NeedsTuning.wanting }
    var wantingCount: Int { NeedKind.allCases.filter(isWanting).count }

    static func mood(of levels: [Float]) -> BlobMood { AwayMath.mood(of: levels) }
    static func wanted(in levels: [Float]) -> NeedKind? { AwayMath.wanted(in: levels) }

    // MARK: change

    /// Real-time decay by `dt` seconds, plus attention while petting (rate 0.05/s, more during the purr).
    /// `exerting`: hunger and thirst drain `exertionDrain` times faster.
    /// `drainScale`: 1 normally; `NeedsTuning.napDrain` (0.5) while he naps at night.
    func step(dt: Float, petting: Bool = false, purring: Bool = false, exerting: Bool = false, drainScale: Float = 1, perkDrain: [Double] = [1, 1, 1]) {
        for k in NeedKind.allCases {
            let mul = (exerting && k != .attention ? NeedsTuning.exertionDrain : 1) * Double(drainScale) * perkDrain[k.rawValue]
            raw[k.rawValue] -= Float(Double(dt) * mul / (NeedsTuning.hoursToEmpty(k) * 3600))
        }
        if petting || purring {
            raw[NeedKind.attention.rawValue] += dt * (purring ? NeedsTuning.purrRate : NeedsTuning.petRate)
        }
        settle()
        if persists {
            sinceSave += dt
            if sinceSave >= NeedsTuning.saveEvery { sinceSave = 0; save() }
        }
    }

    /// A meal restores hunger to 1, a drink thirst.
    func restore(_ k: NeedKind) {
        raw[k.rawValue] = 1
        settle()
        if persists { save() }
    }

    /// A bite or sip adds `amount` (clamped to 1); the meal pays per piece eaten.
    func gain(_ k: NeedKind, _ amount: Float) {
        raw[k.rawValue] += amount
        settle()
        if persists { save() }
    }

    func set(_ k: NeedKind, _ v: Float) { raw[k.rawValue] = min(max(v, 0), 1); settle() }

    private func settle() {
        for i in raw.indices { raw[i] = min(max(raw[i], 0), 1) }
        let after = wantedSet
        for k in NeedKind.allCases where lastWantedSet.contains(k) && !after.contains(k) {
            fixedCount += 1; lastFixed = k; onFixed?(k)
        }
        lastWantedSet = after
        publish(force: false)
    }
    private var wantedSet: Set<NeedKind> { Set(NeedKind.allCases.filter(isWanting)) }

    private func publish(force: Bool) {
        var changed = force
        for i in raw.indices where abs(raw[i] - levels[i]) >= 0.005 || (raw[i] == 1) != (levels[i] == 1) { changed = true }
        let m = Self.mood(of: raw), w = Self.wanted(in: raw)
        if m != mood { mood = m }
        if w != wantedNeed { wantedNeed = w }
        if changed { levels = raw }
    }

    // MARK: persistence

    func save() {
        guard persists else { return }
        let stamp = awaySince ?? now()                    // never advance the stamp past unapplied away time
        defaults.set(["levels": raw.map { Double($0) }, "time": stamp.timeIntervalSince1970] as [String: Any], forKey: key)
    }

    /// The app left the foreground: stamp the time (it is what the next return or cold launch measures from) and save.
    func leaveActive(at t: Date? = nil) {
        if awaySince == nil { awaySince = t ?? now() }
        save()
    }

    /// The app came back: apply the time since `leaveActive` exactly once. Returns the seconds applied (0 when there was no matching leave).
    @discardableResult
    func returnActive(at t: Date? = nil) -> TimeInterval {
        guard let since = awaySince else { return 0 }
        awaySince = nil
        let end = t ?? now()
        let away = TimeAway.clamp(end.timeIntervalSince(since))
        applyAway(seconds: away, endingAt: end)
        sinceSave = 0
        if persists { save() }
        return away
    }

    /// THE time-away path (cold launch and foreground resume both end here). Pure arithmetic on `raw`: each need falls linearly on the away curve,
    /// stops at the floor, and a need already below the floor is left alone.
    /// `endingAt`: when the absence ended; the hours of it that fell at night (21-6) count half on the needs (he slept through them).
    func applyAway(seconds: TimeInterval, endingAt end: Date? = nil) {
        let away = TimeAway.clamp(seconds)
        lastAway = away
        if let end {
            let from = end.addingTimeInterval(-away)
            let ex = perkKey.map { PerkStore.load(defaults: defaults, key: $0) } ?? [:]
            if ex.isEmpty { raw = AwayMath.needLevels(raw, from: from, to: end) }
            else {
                // a perk that slows a need shortens the time that counts for it (the strongest perk wins; they do not multiply)
                var out = raw
                for k in NeedKind.allCases {
                    let eff = max(0, away - PerkStore.needCredit(ex, need: k.rawValue, from: from, to: end))
                    out[k.rawValue] = AwayMath.needLevels(raw, from: end.addingTimeInterval(-eff), to: end)[k.rawValue]
                }
                raw = out
            }
        }
        else { raw = Self.awayLevels(raw, seconds: away) }
        lastWantedSet = wantedSet            // no "fixed" events for what the time away did
        publish(force: true)
    }

    static func awayLevels(_ v: [Float], seconds: TimeInterval) -> [Float] { AwayMath.needLevels(v, seconds: seconds) }

    /// Reads the stored levels and applies the time since the stored stamp through `applyAway`; seeds a first launch.
    func load() {
        guard let d = defaults.dictionary(forKey: key), let l = d["levels"] as? [Double], l.count == 3, let t = d["time"] as? Double else {
            raw = [NeedsTuning.seedHunger, NeedsTuning.seedOthers, NeedsTuning.seedOthers]       // first launch: hunger wanting
            lastWantedSet = wantedSet
            if persists { save() }
            publish(force: true)
            return
        }
        raw = l.map { min(max(Float($0), 0), 1) }
        awaySince = nil
        applyAway(seconds: now().timeIntervalSince1970 - t, endingAt: now())
        sinceSave = 0
        if persists { save() }
        publish(force: true)
    }
}

// MARK: - Thought-bubble schedule

/// When the bubble shows: ~1.5 s after a need starts wanting, then 6 s on / 14 s off (every ~20 s) while the need persists.
/// Pure and headless: GameCare feeds it dt each step.
struct BubbleSchedule {
    static let firstDelay: Float = 1.5
    static let shown: Float = 6
    static let period: Float = 20

    enum Event: Equatable { case appeared(NeedKind), disappeared(NeedKind), fixed(NeedKind, wasVisible: Bool) }

    private(set) var need: NeedKind?
    private(set) var visible = false
    private var t: Float = 0

    /// `suppressed`: the bubble is held back (focus mode, a pending selection); the cycle waits. `pinned`: keep it up (his meal is on).
    mutating func update(wanted: NeedKind?, dt: Float, suppressed: Bool, pinned: Bool) -> [Event] {
        var out: [Event] = []
        if wanted != need {
            if let old = need {
                if wanted == nil { out.append(.fixed(old, wasVisible: visible)) }
                else if visible { out.append(.disappeared(old)) }
            }
            need = wanted; t = -Self.firstDelay; visible = false
        }
        guard let n = need else { return out }
        if !suppressed && !pinned { t += dt; if t >= Self.period { t -= Self.period } }
        let want = !suppressed && (pinned || (t >= 0 && t < Self.shown))
        if want != visible {
            visible = want
            out.append(want ? .appeared(n) : .disappeared(n))
        }
        return out
    }

    /// Voice v1: show the bubble now for a normal stay (a grumpy Bob that ignored an order). No-op without a wanted need or while it is up.
    mutating func showNow() -> [Event] {
        guard let n = need, !visible else { return [] }
        visible = true; t = 0
        return [.appeared(n)]
    }

    /// The player tapped the bubble: it goes away until the next cycle.
    mutating func dismiss() -> [Event] {
        guard visible, let n = need else { return [] }
        visible = false; t = Self.shown
        return [.disappeared(n)]
    }
}

// MARK: - Bath bubble schedule

/// The bath/clean thought bubble: a source parallel to the need bubbles (the coat is not a NeedKind). Shows at Dirty (6 s every 45 s) and, more
/// insistently, at Filthy (6 s every 14 s). GameCare arbitrates the one bubble slot between this and BubbleSchedule.
struct CoatBubbleSchedule {
    static let firstDelay: Float = 3
    static let shown: Float = 6
    static let dirtyPeriod: Float = 45
    static let filthyPeriod: Float = 14

    private(set) var visible = false
    private var t: Float = -CoatBubbleSchedule.firstDelay
    private var active = false

    /// Returns true when `visible` changed.
    mutating func update(coat: BlobGrime.CoatTier, dt: Float, suppressed: Bool) -> Bool {
        let wants = coat == .dirty || coat == .filthy
        if !wants { active = false; t = -Self.firstDelay; return set(false) }
        if !active { active = true; t = -Self.firstDelay }
        if !suppressed {
            t += dt
            let p = coat == .filthy ? Self.filthyPeriod : Self.dirtyPeriod
            if t >= p { t -= p }
        }
        return set(!suppressed && t >= 0 && t < Self.shown)
    }
    /// Tapped: gone until the next cycle.
    mutating func dismiss() -> Bool { t = Self.shown; return set(false) }
    private mutating func set(_ v: Bool) -> Bool { if v == visible { return false }; visible = v; return true }
}
