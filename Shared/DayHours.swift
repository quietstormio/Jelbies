//
//  DayHours.swift
//  The game's day phases and the continuous four-way blend of the hour (moved here verbatim from Audio/DayClock.swift so the widget extension and Siri,
//  which compile Shared/ only, read the SAME night as the room), plus `SleepHours`: the ONE rule for "the Jelbies sleep at this hour".
//

import Foundation

nonisolated enum DayPhase: String, CaseIterable, Sendable {
    case morning, day, evening, night

    /// morning 6-11, day 11-17, evening 17-21, night 21-6.
    static func of(hour h: Double) -> DayPhase {
        let x = DayMath.wrap(h)
        if x >= 6 && x < 11 { return .morning }
        if x >= 11 && x < 17 { return .day }
        if x >= 17 && x < 21 { return .evening }
        return .night
    }
    /// The hour the phase begins.
    var startHour: Double {
        switch self { case .morning: return 6; case .day: return 11; case .evening: return 17; case .night: return 21 }
    }
    var next: DayPhase {
        switch self { case .morning: return .day; case .day: return .evening; case .evening: return .night; case .night: return .morning }
    }
}

nonisolated enum DayMath {
    static func wrap(_ h: Double) -> Double {
        guard h.isFinite else { return 12 }
        let r = h.truncatingRemainder(dividingBy: 24)
        return r < 0 ? r + 24 : r
    }
    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t)
    }
}

/// Four weights that always sum to 1 and move continuously with the hour (no hard jumps):
/// sunrise 6-8 night -> morning, 9.5-11.5 morning -> day, 16-18 day -> evening (golden), sunset 19.5-21.5 evening -> night.
nonisolated struct DayBlend: Equatable, Sendable {
    var morning = 0.0, day = 0.0, evening = 0.0, night = 0.0

    init(morning: Double = 0, day: Double = 0, evening: Double = 0, night: Double = 0) {
        self.morning = morning; self.day = day; self.evening = evening; self.night = night
    }

    init(hour: Double) {
        let h = DayMath.wrap(hour)
        func mix(_ a: DayPhase, _ b: DayPhase, _ s: Double) {
            set(a, 1 - s); set(b, s)
        }
        if h < 6 { set(.night, 1) }
        else if h < 8 { mix(.night, .morning, DayMath.smooth(6, 8, h)) }
        else if h < 9.5 { set(.morning, 1) }
        else if h < 11.5 { mix(.morning, .day, DayMath.smooth(9.5, 11.5, h)) }
        else if h < 16 { set(.day, 1) }
        else if h < 18 { mix(.day, .evening, DayMath.smooth(16, 18, h)) }
        else if h < 19.5 { set(.evening, 1) }
        else if h < 21.5 { mix(.evening, .night, DayMath.smooth(19.5, 21.5, h)) }
        else { set(.night, 1) }
    }

    private mutating func set(_ p: DayPhase, _ v: Double) {
        switch p { case .morning: morning = v; case .day: day = v; case .evening: evening = v; case .night: night = v }
    }
    subscript(p: DayPhase) -> Double {
        switch p { case .morning: return morning; case .day: return day; case .evening: return evening; case .night: return night }
    }
    var sum: Double { morning + day + evening + night }
    /// The phase with the largest weight.
    var dominant: DayPhase { DayPhase.allCases.max { self[$0] < self[$1] } ?? .day }
}

/// One rule for the night in the room: the same expression the game's bedtime hours use (`GameCare.isBedtimeHours`: `DayClock.nightFactor > nightEdge || deepNightFactor > 0.5`),
/// on a fractional clock hour. The game reads its own copy of the edge (`SleepTuning.nightEdge`, pinned equal by a test); the widget / Siri side reads this one.
nonisolated enum SleepHours {
    /// DayBlend night above this counts as bedtime hours (about 20:22 to 07:07).
    static let nightEdge: Float = 0.4
    /// Deep night: 23:00 to 06:00.
    static let deepNightFrom = 23.0, deepNightTo = 6.0

    /// True when the room is in its sleeping hours at this fractional hour (0..<24).
    static func isNight(hour h: Double) -> Bool {
        Float(DayBlend(hour: h).night) > nightEdge || (h >= deepNightFrom || h < deepNightTo)
    }
    /// The fractional local hour of a date.
    static func hour(of date: Date, calendar cal: Calendar) -> Double {
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }
    static func isNight(at date: Date, calendar cal: Calendar = .current) -> Bool { isNight(hour: hour(of: date, calendar: cal)) }

    /// The moment this night (the one `date` is in) or, by day, the next night ends: the first whole minute after `date` that is out of the night.
    static func wakeDate(after date: Date, calendar cal: Calendar = .current) -> Date {
        let step: TimeInterval = 60
        var t = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded(.down) * step + step)
        var guardN = 0
        while !isNight(at: t, calendar: cal), guardN < 36 * 60 { t = t.addingTimeInterval(step); guardN += 1 }          // by day: on to the night
        guardN = 0
        while isNight(at: t, calendar: cal), guardN < 36 * 60 { t = t.addingTimeInterval(step); guardN += 1 }          // then to its morning edge
        return t
    }
}
