//
//  Needs.swift
//  Needs + mood v1 (see docs/Emotions.md). Three needs the player can fix: hunger (Feed), thirst (Drink), attention (petting in focus mode).
//  Each is 0...1 and decays in real time; below `wanting` the Blob wants it. Mood is derived: happy / okay / grumpy.
//  Persisted to UserDefaults with a timestamp; the offline decay is clamped so at most ONE need is wanting when the app opens.
//  The first launch ever is seeded with hunger wanting, so a fresh install shows a food bubble.
//
//  Pure model (no views): GameCare ticks it, ThoughtBubbleView / the roster read it. Touch reactions read `mood` / `wantedNeed` (worker B).
//

import Foundation
import Observation

enum NeedKind: Int, CaseIterable, Sendable {
    case hunger, thirst, attention

    var title: String {
        switch self { case .hunger: return "Food"; case .thirst: return "Drink"; case .attention: return "Love" }
    }
    /// What the player does about it.
    var action: BubbleAction {
        switch self { case .hunger: return .feed; case .thirst: return .drink; case .attention: return .comeHere }
    }
}

/// What tapping a thought bubble opens.
enum BubbleAction: Equatable, Sendable { case feed, drink, comeHere }

enum BlobMood: String, Sendable {
    case happy, okay, grumpy
    var word: String { switch self { case .happy: return "Happy"; case .okay: return "Okay"; case .grumpy: return "Grumpy" } }
}

/// Every tunable of the needs in one place.
enum NeedsTuning {
    /// Real hours for a full need to run empty.
    static func hoursToEmpty(_ k: NeedKind) -> Double {
        switch k { case .hunger: return 3; case .thirst: return 2; case .attention: return 4 }
    }
    /// Below this a need is "wanting" (bubble, grumpy).
    static let wanting: Float = 0.3
    /// All needs at or above this: happy.
    static let happy: Float = 0.6
    /// Attention per second while petting, and during the purr.
    static let petRate: Float = 0.05
    static let purrRate: Float = 0.15
    /// First launch ever: hunger is seeded wanting, the rest comfortably full.
    static let seedHunger: Float = 0.2
    static let seedOthers: Float = 0.85
    /// When the offline clamp rescues a need from wanting it lands here (just above the line).
    static let clampedTo: Float = 0.35
    /// Seconds between automatic saves while playing.
    static let saveEvery: Float = 15
    static let defaultsKey = "BlobNeeds.v1"
}

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
    @ObservationIgnored private var lastWantedSet: Set<NeedKind> = []
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
        } else {
            raw = [NeedsTuning.seedOthers, NeedsTuning.seedOthers, NeedsTuning.seedOthers]
        }
        lastWantedSet = wantedSet
        publish(force: true)
    }

    // MARK: queries

    func level(_ k: NeedKind) -> Float { raw[k.rawValue] }
    func isWanting(_ k: NeedKind) -> Bool { raw[k.rawValue] < NeedsTuning.wanting }
    var wantingCount: Int { NeedKind.allCases.filter(isWanting).count }

    static func mood(of levels: [Float]) -> BlobMood {
        if levels.contains(where: { $0 < NeedsTuning.wanting }) { return .grumpy }
        return levels.allSatisfy({ $0 >= NeedsTuning.happy }) ? .happy : .okay
    }
    static func wanted(in levels: [Float]) -> NeedKind? {
        var best: NeedKind?
        for k in NeedKind.allCases where levels[k.rawValue] < NeedsTuning.wanting {
            if best == nil || levels[k.rawValue] < levels[best!.rawValue] { best = k }
        }
        return best
    }

    // MARK: change

    /// Real-time decay by `dt` seconds, plus attention while petting (rate 0.05/s, more during the purr).
    func step(dt: Float, petting: Bool = false, purring: Bool = false) {
        for k in NeedKind.allCases {
            raw[k.rawValue] -= Float(Double(dt) / (NeedsTuning.hoursToEmpty(k) * 3600))
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
        defaults.set(["levels": raw.map { Double($0) }, "time": now().timeIntervalSince1970] as [String: Any], forKey: key)
    }

    /// Reads the stored levels and applies the offline decay (clamped to one wanting need); seeds a first launch.
    func load() {
        guard let d = defaults.dictionary(forKey: key), let l = d["levels"] as? [Double], l.count == 3, let t = d["time"] as? Double else {
            raw = [NeedsTuning.seedHunger, NeedsTuning.seedOthers, NeedsTuning.seedOthers]       // first launch: hunger wanting
            lastWantedSet = wantedSet
            if persists { save() }
            publish(force: true)
            return
        }
        let elapsed = max(0, now().timeIntervalSince1970 - t)
        var v = l.map { Float($0) }
        for k in NeedKind.allCases { v[k.rawValue] -= Float(elapsed / (NeedsTuning.hoursToEmpty(k) * 3600)) }
        for i in v.indices { v[i] = min(max(v[i], 0), 1) }
        raw = Self.clampOne(v)
        lastWantedSet = wantedSet
        sinceSave = 0
        if persists { save() }
        publish(force: true)
    }

    /// At most ONE need may be wanting: the emptiest keeps its level, the others are lifted just above the line.
    static func clampOne(_ v: [Float]) -> [Float] {
        var v = v
        guard let keep = wanted(in: v) else { return v }
        for k in NeedKind.allCases where k != keep && v[k.rawValue] < NeedsTuning.wanting { v[k.rawValue] = NeedsTuning.clampedTo }
        return v
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

    /// The player tapped the bubble: it goes away until the next cycle.
    mutating func dismiss() -> [Event] {
        guard visible, let n = need else { return [] }
        visible = false; t = Self.shown
        return [.disappeared(n)]
    }
}
