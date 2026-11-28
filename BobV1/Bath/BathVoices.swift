//
//  BathVoices.swift
//  The Jelmiko's own little voice during the bath (2026-11-17: "more Jelmiko noises during baths, not the scrubbing, the creature noises, different ones").
//  Only EXISTING clips in the existing voice: the context voices (hum, lala, mmhmm, ooh, giggle, eep, huh, aww, pfft, yay, wheee, hello, tasty), the chirps
//  (happy / sad), and the babble. No new file. `BathVoicePlan` is pure (own seeded generator, no clock), so a test can run it;
//  `AudioHub.bathVoice` plays one past the same gates as the other voices, and `BathFlow.voiceTick` feeds it from the tick's dt.
//

import Foundation

/// A moment of the bath that gets a vocal. The raw value is what the tests and the log print.
nonisolated enum BathMoment: String, CaseIterable, Sendable {
    case getIn, grumble, scrubHum, scrubTickle, firstWater, rinseRelax, shinePurr, stageDone, allClean, idle

    /// The voices this moment may use. Several per moment so the same moment does not repeat one sound.
    var pool: [JellyVoice] {
        switch self {
        case .getIn: return [.wheee, .hello, .yay]                        // a little excited chirp
        case .grumble: return [.pfft, .huh, .sad]                         // a dirty one's first, grumbly sound
        case .scrubHum: return [.hum, .lala, .mmhmm, .ooh]                // happy hums
        case .scrubTickle: return [.giggle, .eep, .huh]                   // ticklish squeaks
        case .firstWater: return [.pfft, .eep]                            // the shivery "brr" at the first water
        case .rinseRelax: return [.aww, .hum, .mmhmm, .lala]              // relaxed sighs
        case .shinePurr: return [.hum, .aww, .ooh, .lala]                 // contented purr / hum while rubbed
        case .stageDone: return [.yay, .happy, .tasty, .hello]            // a pleased chirp
        case .allClean: return [.babble]                                  // proud, happy babble
        case .idle: return [.hum, .mmhmm, .lala, .aww, .ooh]              // an occasional soft sound in the tub
        }
    }
}

/// What to play: a voice, its variant (1...3 where the voice has them) and whether it is the quiet kind.
nonisolated struct BathCue: Equatable, Sendable {
    var moment: BathMoment
    var voice: JellyVoice
    var variant: Int
    var soft: Bool
    var kind: String { voice.rawValue }
}

/// The bath's vocal plan: which sound for which moment. Remembers only what really PLAYED (`played(_:)`), so the "never the same twice" and the share cap hold on
/// what the player heard, not on what was asked for.
nonisolated struct BathVoicePlan: Sendable {
    /// No kind may take more than `shareCap` of a bath's vocals; the pick keeps a kind under `softCap` while it can.
    static let shareCap = 0.35, softCap = 0.30
    /// Seconds between two vocals while the finger is on him / while he sits in the tub untouched.
    static let touchGap: ClosedRange<Float> = 2.5...4, idleGap: ClosedRange<Float> = 6...10

    private var rng: UInt32
    private(set) var counts: [String: Int] = [:]
    private(set) var total = 0
    private(set) var lastKind: String?
    private var lastVariant: [String: Int] = [:]

    init(seed: UInt32) { rng = seed == 0 ? 0x9E3779B9 : seed }

    /// 0..<1 from the plan's own generator (it never touches the flow's, so the bath's bubbles stay as they were).
    mutating func rand() -> Float { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return Float(rng >> 8) / Float(1 << 24) }
    mutating func range(_ r: ClosedRange<Float>) -> Float { r.lowerBound + (r.upperBound - r.lowerBound) * rand() }
    mutating func reset() { counts = [:]; total = 0; lastKind = nil; lastVariant = [:] }

    private func share(_ k: String) -> Double { total == 0 ? 0 : Double(counts[k, default: 0]) / Double(total) }

    /// The cue for a moment, or nil when it should be skipped (over its share).
    mutating func pick(_ m: BathMoment) -> BathCue? {
        let pool = m.pool
        func kind(_ v: JellyVoice) -> String { v.rawValue }
        var c = pool.filter { kind($0) != lastKind }
        if c.isEmpty { c = pool }
        let under = c.filter { total < 3 || (Double(counts[kind($0), default: 0] + 1) / Double(total + 1)) <= Self.softCap }
        if !under.isEmpty { c = under }
        let least = c.map { counts[kind($0), default: 0] }.min() ?? 0
        c = c.filter { counts[kind($0), default: 0] <= least + 1 }
        guard !c.isEmpty else { return nil }
        let v = c[min(Int(rand() * Float(c.count)), c.count - 1)]
        var variant = 1
        if v.hasVariants { repeat { variant = 1 + min(Int(rand() * 3), 2) } while variant == lastVariant[v.rawValue] ?? 0 }
        return BathCue(moment: m, voice: v, variant: variant, soft: m == .idle)
    }

    /// The hub played it.
    mutating func played(_ cue: BathCue) {
        counts[cue.kind, default: 0] += 1; total += 1; lastKind = cue.kind
        if cue.voice.hasVariants { lastVariant[cue.voice.rawValue] = cue.variant }
    }
}
