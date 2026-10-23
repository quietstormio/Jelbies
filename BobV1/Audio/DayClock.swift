//
//  DayClock.swift
//  The game's time of day: the phone clock (or `-ClockHour <0-23.99>`) plus the curtain-skip offset, the continuous four-way blend the
//  room light / music / behaviour read, and the 2-3 s time-lapse that plays ONLY when the player taps the curtain to skip ahead (a return snaps to the real clock).
//  Pure and headless apart from `DayClock.shared` (UserDefaults + Date); everything else here takes plain numbers so tests can drive it.
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

/// A sweep of the displayed hour from `from` to `to` (to >= from, in hours) over `duration` seconds, eased.
nonisolated struct TimeLapse: Equatable, Sendable {
    var from: Double, to: Double, start: Double
    var duration: Double = 2.6

    init(from: Double, to: Double, start: Double, duration: Double = 2.6) {
        self.from = from
        var t = to
        while t < from { t += 24 }
        self.to = min(t, from + 24)          // never whirl more than one day
        if t - from > 24 { self.from = t - 24; self.to = t }
        self.start = start; self.duration = duration
    }
    func progress(at now: Double) -> Double { min(max((now - start) / duration, 0), 1) }
    func isDone(at now: Double) -> Bool { now - start >= duration }
    func hour(at now: Double) -> Double {
        let p = progress(at: now)
        return DayMath.wrap(from + (to - from) * (p * p * (3 - 2 * p)))
    }
}

@MainActor
final class DayClock {
    /// Under XCTest the clock is frozen at noon (unless `-ClockHour` is given) so suites never depend on the hour they run at.
    static let shared: DayClock = {
        let c = DayClock()
        if c.forcedHour == nil, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { c.forcedHour = 12 }
        return c
    }()

    static let offsetKey = "DayClock.offset.v1", offsetPhaseKey = "DayClock.offsetPhase.v1", leftKey = "DayClock.left.v1"

    private let defaults: UserDefaults
    private let now: () -> Date
    private let uptime: () -> Double
    private let calendar: Calendar
    /// `-ClockHour` (debug): freezes the real clock at this hour.
    var forcedHour: Double?
    private(set) var offsetHours: Double
    private var offsetPhase: DayPhase?
    private(set) var lapse: TimeLapse?
    /// Bumped by every skip / sweep start (tests, the audio sting).
    private(set) var skipCount = 0

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, calendar: Calendar = .current) {
        self.defaults = defaults; self.now = now; self.uptime = uptime; self.calendar = calendar
        if defaults.object(forKey: "ClockHour") != nil { forcedHour = defaults.double(forKey: "ClockHour") }
        offsetHours = defaults.double(forKey: Self.offsetKey)
        offsetPhase = defaults.string(forKey: Self.offsetPhaseKey).flatMap(DayPhase.init(rawValue:))
        refresh()
    }
    nonisolated deinit {}

    /// The phone's calendar day as one number (yyyymmdd). It changes at local midnight, whatever time has gone by (Pep resets on it). The curtain offset does not move it.
    var dayKey: Int {
        let c = calendar.dateComponents([.year, .month, .day], from: now())
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// The phone's hour of day, 0..<24 (or the forced hour).
    var realHour: Double {
        if let f = forcedHour { return DayMath.wrap(f) }
        let c = calendar.dateComponents([.hour, .minute, .second], from: now())
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }
    /// Real clock + curtain offset (no time-lapse).
    var hour: Double { DayMath.wrap(realHour + offsetHours) }
    /// What the room and the music draw: the time-lapse hour while one runs.
    var displayHour: Double { lapse.map { $0.hour(at: uptime()) } ?? hour }
    var phase: DayPhase { DayPhase.of(hour: displayHour) }
    var blend: DayBlend { DayBlend(hour: displayHour) }
    var isLapsing: Bool { lapse != nil }

    /// Drops a finished lapse, and clears the curtain offset once the real clock has moved on to another phase. Call every frame / second.
    func refresh() {
        if let l = lapse, l.isDone(at: uptime()) { lapse = nil }
        if offsetHours != 0, let p = offsetPhase, DayPhase.of(hour: realHour) != p { clearOffset() }
    }

    private func clearOffset() {
        offsetHours = 0; offsetPhase = nil
        defaults.removeObject(forKey: Self.offsetKey); defaults.removeObject(forKey: Self.offsetPhaseKey)
    }

    /// The curtains: jump to the start of the next part of the day (an offset on the real clock) with a short time-lapse.
    func skipToNextPhase() {
        let here = hour
        let target = DayPhase.of(hour: here).next.startHour
        var delta = target - here
        if delta <= 0.001 { delta += 24 }
        let from = displayHour
        offsetHours = (offsetHours + delta).truncatingRemainder(dividingBy: 24)
        offsetPhase = DayPhase.of(hour: realHour)
        defaults.set(offsetHours, forKey: Self.offsetKey); defaults.set(offsetPhase?.rawValue, forKey: Self.offsetPhaseKey)
        lapse = TimeLapse(from: from, to: from + delta, start: uptime())
        skipCount += 1
    }

    /// The room, the music and the Jellies are on the real clock at once: no sweep, ever (round 1022: the player must never watch the day catch up on open).
    /// Called before the first frame on launch and on every return to the foreground. Only the curtain tap (`skipToNextPhase`) plays a time-lapse.
    func snapToNow() {
        lapse = nil
        refresh()
        defaults.removeObject(forKey: Self.leftKey)
    }

    /// Back after `awayFrom`: kept for old callers; it no longer sweeps, it snaps.
    func returned(from left: Date, now t: Date? = nil) {
        _ = left; _ = t
        snapToNow()
    }

    /// Stamps the moment the app left the foreground (read back by `returned`).
    func leaving() { defaults.set(now().timeIntervalSince1970, forKey: Self.leftKey) }
    func takeLeft() -> Date? {
        guard defaults.object(forKey: Self.leftKey) != nil else { return nil }
        let d = Date(timeIntervalSince1970: defaults.double(forKey: Self.leftKey))
        defaults.removeObject(forKey: Self.leftKey)
        return d
    }

    // MARK: derived behaviour factors

    /// 0...1: how night-like (naps, yawns).
    var nightFactor: Float { Float(DayBlend(hour: hour).night) }
    /// 1 from 23:00 to 6:00 (everybody asleep unless the player is busy with them), else 0.
    var deepNightFactor: Float { let h = hour; return (h >= 23 || h < 6) ? 1 : 0 }
    /// 0...1: the stretch-and-wake hour.
    var morningFactor: Float { Float(DayBlend(hour: hour).morning) }
}

/// The back-wall windows as a tap target (RoomGeometry lays them out).
enum DayWindow {
    static func contains(x: Float, y: Float) -> Bool {
        guard y >= RoomGeometry.windowY0 - 0.1, y <= RoomGeometry.windowY1 + 0.1 else { return false }
        return RoomGeometry.windowXs.contains { abs(x - $0) <= RoomGeometry.windowHalfW + 0.1 }
    }
}
