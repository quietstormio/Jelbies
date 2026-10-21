//
//  NeedsCore.swift
//  The pure, UI-free half of the needs and grime rules, compiled into BOTH the app and the widget extension (Shared/ is a synchronized
//  folder of both targets), so the widget projects "time away" with exactly the arithmetic the app uses:
//  tiers, tunables, the away-decay curve and its floor, the away dirt / sparkle rules, mood and the wanted need.
//  Everything here is `nonisolated` so both modules (the app defaults to MainActor, the widget does not) see the same isolation.
//

import Foundation

nonisolated enum NeedKind: Int, CaseIterable, Sendable {
    case hunger, thirst, attention

    var title: String {
        switch self { case .hunger: return "Food"; case .thirst: return "Drink"; case .attention: return "Love" }
    }
}


nonisolated enum BlobMood: String, Sendable {
    case happy, okay, grumpy
    var word: String { switch self { case .happy: return "Happy"; case .okay: return "Okay"; case .grumpy: return "Grumpy" } }
}

/// How a need reads: Full > Normal > Hungry > Famished (the words differ per need).
nonisolated enum NeedTier: Int, CaseIterable, Sendable {
    case full, normal, hungry, famished
    func word(_ k: NeedKind) -> String {
        switch (k, self) {
        case (.hunger, .full): return "Full"
        case (.hunger, .hungry): return "Hungry"
        case (.hunger, .famished): return "Famished"
        case (.thirst, .full): return "Quenched"
        case (.thirst, .hungry): return "Thirsty"
        case (.thirst, .famished): return "Parched"
        case (.attention, .full): return "Content"
        case (.attention, .hungry): return "Lonely"
        case (.attention, .famished): return "Neglected"
        default: return "Normal"
        }
    }
    static func of(level: Float) -> NeedTier {
        if level >= NeedsTuning.fullFrom { return .full }
        if level >= NeedsTuning.normalFrom { return .normal }
        return level >= NeedsTuning.famishedBelow ? .hungry : .famished
    }
}

/// Every tunable of the needs in one place.
nonisolated enum NeedsTuning {
    /// Real hours for a full need to run empty.
    static func hoursToEmpty(_ k: NeedKind) -> Double {
        switch k { case .hunger: return 3; case .thirst: return 2; case .attention: return 4 }
    }
    /// Time AWAY has its own, gentler curve (the in-app rates above are unchanged): real hours for a full need to fall to empty, linearly
    /// (the floor stops it first), so after 3 h away: hunger 0.70, thirst 0.625, attention 0.50. After 8 h (or overnight) all three sit on the floor.
    static func awayHoursToEmpty(_ k: NeedKind) -> Double {
        switch k { case .hunger: return 10; case .thirst: return 8; case .attention: return 6 }
    }
    /// Named tiers (Nintendogs style): at or above `fullFrom` Full, at or above `normalFrom` Normal, at or above `famishedBelow` Hungry, else Famished.
    static let fullFrom: Float = 0.85
    static let normalFrom: Float = 0.5
    /// The Hungry / Famished boundary. The away floor IS this constant, so being away can never make him Famished / Parched / Neglected:
    /// that tier is reachable only by in-app neglect or exertion.
    static let famishedBelow: Float = 0.2
    /// Away decay never takes a need below this (and never raises one that was already lower).
    static let awayFloor: Float = famishedBelow
    /// Hunger and thirst drain this many times faster while he hurries / runs / does zoomies, slide or scoot (a stand-in for walks and contests).
    static let exertionDrain: Double = 3
    /// Hunger and thirst drain this many times slower while he naps at night.
    static let napDrain: Float = 0.5
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
    /// Seconds between automatic saves while playing.
    static let saveEvery: Float = 15
    static let defaultsKey = "BlobNeeds.v1"
}


/// Every tunable of the grime in one place.
nonisolated enum GrimeTuning {
    /// Dirt gained per 5 minutes of NORMAL roaming, and the world units that is (measured average roaming speed 0.198 u/s x 300 s, see TimeAwayTests; was 0.149 / 45 before the 2026-10-21 room-movement round, so the dirt per MINUTE is unchanged).
    /// Exertion (run / zoomies / slide / scoot) is `exertionMul` times faster per unit walked.
    static let dirtPer5Min: Float = 0.02
    static let roamUnitsPer5Min: Float = 60
    static let dirtPerUnit: Float = dirtPer5Min / roamUnitsPer5Min
    static let exertionMul: Float = 3
    /// Time away: +0.05 dirt per 2 h, at most +0.15 from one absence.
    static let awayEvery: TimeInterval = 2 * 3600
    static let awayDirt: Float = 0.05
    static let awayDirtMax: Float = 0.15
    /// Coat tiers by dirt: below `cleanBelow` he is Clean / Beautiful; then Normal below `normalBelow`, Dirty below `dirtyBelow`, else Filthy.
    static let cleanBelow: Float = 0.05
    static let normalBelow: Float = 0.35
    static let dirtyBelow: Float = 0.7
    /// Seconds for a full room sparkle to fade out on its own (wall clock: the same rate in the room and away). It also ends when dirt reaches `cleanBelow`.
    static let sparkleFade: Float = 600
    static let saveEvery: Float = 15
    static let defaultsKey = "BlobGrime.v1"
}

/// How dirty he looks (the named tier of dirt + sparkle). `BlobGrime.CoatTier` is an alias of this.
nonisolated enum JellyCoatTier: Int, CaseIterable, Sendable {
    case beautiful, clean, normal, dirty, filthy
    var word: String { ["Beautiful", "Clean", "Normal", "Dirty", "Filthy"][rawValue] }
    static func of(dirt: Float, sparkle: Float) -> JellyCoatTier {
        if dirt < GrimeTuning.cleanBelow { return sparkle > 0 ? .beautiful : .clean }
        if dirt < GrimeTuning.normalBelow { return .normal }
        return dirt < GrimeTuning.dirtyBelow ? .dirty : .filthy
    }
}

/// The away arithmetic, in one place. `BlobNeeds.applyAway` / `BlobGrime.applyAway` call these; the widget calls the same ones to project forward.
nonisolated enum AwayMath {
    /// Each need falls linearly on the away curve, stops at the floor, and a need already below the floor is left alone.
    static func needLevels(_ v: [Float], seconds: TimeInterval) -> [Float] {
        var v = v
        for k in NeedKind.allCases where k.rawValue < v.count {
            let i = k.rawValue
            let drop = Float(TimeAway.clamp(seconds) / (NeedsTuning.awayHoursToEmpty(k) * 3600))
            v[i] = max(min(max(v[i], 0), 1) - drop, min(v[i], NeedsTuning.awayFloor))
            v[i] = min(max(v[i], 0), 1)
        }
        return v
    }
    /// Night hours (21:00-06:00) count `nightAwayFactor` on the needs: he slept through them, so an overnight absence is gentle.
    static let nightAwayFactor = 0.5
    /// Seconds of [from, to] that fall between 21:00 and 06:00 local time.
    static func nightSeconds(from: Date, to: Date, calendar cal: Calendar = .current) -> TimeInterval {
        guard to > from else { return 0 }
        var total: TimeInterval = 0
        var day = cal.startOfDay(for: from)
        var guardN = 0
        while day < to && guardN < 40 {
            guardN += 1
            guard let next = cal.date(byAdding: .day, value: 1, to: day),
                  let six = cal.date(byAdding: .hour, value: 6, to: day),
                  let nine = cal.date(byAdding: .hour, value: 21, to: day) else { break }
            for (a, b) in [(day, six), (nine, next)] {
                let lo = max(a, from), hi = min(b, to)
                if hi > lo { total += hi.timeIntervalSince(lo) }
            }
            day = next
        }
        return total
    }
    /// The away seconds the needs feel: the night part at half weight.
    static func needSeconds(from: Date, to: Date, calendar: Calendar = .current) -> TimeInterval {
        let total = max(0, to.timeIntervalSince(from))
        return total - nightSeconds(from: from, to: to, calendar: calendar) * (1 - nightAwayFactor)
    }
    static func needLevels(_ v: [Float], from: Date, to: Date, calendar: Calendar = .current) -> [Float] {
        needLevels(v, seconds: needSeconds(from: from, to: to, calendar: calendar))
    }
    /// Dirt gained from one absence: +0.05 per 2 h, at most +0.15.
    static func dirtGain(awaySeconds: TimeInterval) -> Float {
        min(GrimeTuning.awayDirtMax, Float(TimeAway.clamp(awaySeconds) / GrimeTuning.awayEvery) * GrimeTuning.awayDirt)
    }
    /// The room sparkle fades at the wall-clock rate.
    static func sparkle(_ s: Float, awaySeconds: TimeInterval) -> Float {
        max(0, s - Float(TimeAway.clamp(awaySeconds)) / GrimeTuning.sparkleFade)
    }
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
    /// Dirt and sparkle after `seconds` away (dirt grows, sparkle fades and ends once he is no longer clean).
    static func coat(dirt: Float, sparkle: Float, awaySeconds: TimeInterval) -> (dirt: Float, sparkle: Float) {
        var s = Self.sparkle(sparkle, awaySeconds: awaySeconds)
        let d = min(1, max(0, dirt + dirtGain(awaySeconds: awaySeconds)))
        if d >= GrimeTuning.cleanBelow { s = 0 }
        return (d, s)
    }
}
