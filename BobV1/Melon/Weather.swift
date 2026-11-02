//
//  Weather.swift
//  The room's weather (user ask 2026-11-02: "occasional thunderstorms with lightning, and the Jelbies get scared"). Mostly clear; a storm rolls in rarely
//  (every 2-5 hours of play, persisted so a relaunch neither rerolls nor repeats it), lasts 2-4 minutes and has four parts:
//    clear      nothing
//    buildUp    the sky darkens, rain starts on the glass, distant rumbles, one Jelbie notices at the window first
//    peak       lightning (a gentle two-pulse flash in the window sky) and close thunder every 7-15 s; the Jelbies huddle (BlobBrain+Weather.swift)
//    clearing   rain and gloom ease away, a last far rumble, the Jelbies shake it off
//  Everything is local (no weather API). The storm is a pre-planned timeline (StormPlan, seeded) of events the stage turns into sound, window shader values
//  (WeatherLook -> RoomShaders.metal / gfxCacheFS) and Jelbie reactions, so tests can read the whole storm without a clock.
//  Lightning stays gentle: at most 3 flashes a second (WCAG), soft amplitudes, one slow glow instead under Reduce Motion.
//

import Foundation
import simd

nonisolated enum StormPhase: String, CaseIterable, Sendable { case clear, buildUp, peak, clearing }

nonisolated enum WeatherTuning {
    /// Real seconds of play between two storms: a roll in this range after each storm starts.
    static let gap: ClosedRange<Double> = (2 * 3600)...(5 * 3600)
    static let buildUp: ClosedRange<Double> = 40...60
    static let peak: ClosedRange<Double> = 60...140
    static let clearing: ClosedRange<Double> = 20...30
    /// The first close strike comes this long after the peak begins.
    static let firstStrikeDelay: Double = 3
    /// Seconds between strikes at the peak.
    static let strikeGap: ClosedRange<Double> = 7...15
    /// One Jelbie notices at the window this far into the build-up.
    static let noticeAt: Double = 16
    /// Window sky flash amplitude (0...1) of a strike; the room (post exposure) lifts by `roomLift` x flash.
    static let flashPeak: Float = 0.8
    static let roomLift: Float = 0.085, roomDip: Float = 0.12
    /// The launch argument forces a storm this many seconds after the room is up (`-StormDelay`).
    static let forcedDelay: Double = 5
}

nonisolated struct WeatherRNG: Sendable {
    var s: UInt64
    init(seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return Double(s >> 11) / Double(1 << 53)
    }
    mutating func range(_ r: ClosedRange<Double>) -> Double { r.lowerBound + (r.upperBound - r.lowerBound) * next() }
}

nonisolated struct StormPulse: Equatable, Sendable { var dt: Double; var amp: Float; var dur: Double }

nonisolated struct StormStrike: Equatable, Sendable {
    var t: Double
    /// 0...1 (a faint far flash is 0.3).
    var strength: Float
    var pulses: [StormPulse]
    /// Seconds from the flash to its thunder.
    var delay: Double
    var close: Bool
    /// Which thunder clip (1 or 2) for a close one.
    var variant: Int
    /// Where in the window sky the glow sits, 0...1 across the windows.
    var spot: Float
}

nonisolated enum StormEventKind: Equatable, Sendable {
    case began
    case phase(StormPhase)
    case notice
    case rumble
    case flash(Int)
    case thunder(Int)
    case ended
}

nonisolated struct StormEvent: Equatable, Sendable { var t: Double; var kind: StormEventKind }

/// One storm, fully planned from a seed.
nonisolated struct StormPlan: Equatable, Sendable {
    var buildUp: Double, peak: Double, clearing: Double
    var strikes: [StormStrike]
    var events: [StormEvent]
    var total: Double { buildUp + peak + clearing }
    var peakStart: Double { buildUp }
    var clearStart: Double { buildUp + peak }

    static func make(seed: UInt64) -> StormPlan {
        var g = WeatherRNG(seed: seed)
        let b = g.range(WeatherTuning.buildUp), p = g.range(WeatherTuning.peak), c = g.range(WeatherTuning.clearing)
        var strikes: [StormStrike] = []
        var ev: [StormEvent] = [StormEvent(t: 0, kind: .began), StormEvent(t: 0, kind: .phase(.buildUp)), StormEvent(t: WeatherTuning.noticeAt, kind: .notice)]
        // build-up: distant rumbles from ~12 s on, every 11-19 s; a faint far flash in the last quarter
        var t = 12.0
        while t < b - 6 { ev.append(StormEvent(t: t, kind: .rumble)); t += g.range(11...19) }
        let far = StormStrike(t: b - 5, strength: 0.3, pulses: [StormPulse(dt: 0, amp: 0.6, dur: 0.5)], delay: 2.5, close: false, variant: 1, spot: Float(g.range(0.1...0.9)))
        strikes.append(far)
        ev.append(StormEvent(t: b, kind: .phase(.peak)))
        // peak: the first strike is close (the startle), then every 7-15 s; about a third of the rest are far
        t = b + WeatherTuning.firstStrikeDelay
        var first = true
        while t < b + p - 5 {
            let close = first || g.next() < 0.65
            let amp = Float(g.range(0.7...1.0))
            var pulses = [StormPulse(dt: 0, amp: amp, dur: 0.22)]
            if close || g.next() < 0.5 { pulses.append(StormPulse(dt: 0.30, amp: amp * 0.7, dur: 0.30)) }           // (>= 0.3 s apart: three flashes a second at most)
            strikes.append(StormStrike(t: t, strength: close ? 1 : 0.5, pulses: pulses, delay: close ? g.range(0.45...0.9) : g.range(1.8...3.0), close: close, variant: g.next() < 0.5 ? 1 : 2, spot: Float(g.range(0.1...0.9))))
            first = false
            t += g.range(WeatherTuning.strikeGap)
        }
        // clearing: one far rumble
        ev.append(StormEvent(t: b + p, kind: .phase(.clearing)))
        ev.append(StormEvent(t: b + p + 6, kind: .rumble))
        ev.append(StormEvent(t: b + p + c, kind: .phase(.clear)))
        ev.append(StormEvent(t: b + p + c, kind: .ended))
        for (i, s) in strikes.enumerated() {
            ev.append(StormEvent(t: s.t, kind: .flash(i)))
            ev.append(StormEvent(t: s.t + s.delay, kind: s.close || s.strength > 0.4 ? .thunder(i) : .rumble))
        }
        ev.sort { $0.t < $1.t }
        return StormPlan(buildUp: b, peak: p, clearing: c, strikes: strikes, events: ev)
    }

    func phase(at t: Double) -> StormPhase {
        if t < 0 || t >= total { return .clear }
        return t < buildUp ? .buildUp : t < clearStart ? .peak : .clearing
    }

    /// Sky darkness 0...1: up over the build-up, full at the peak, away over the clearing.
    func gloom(at t: Double) -> Float {
        if t <= 0 || t >= total { return 0 }
        if t < buildUp { return 0.85 * Float(DayMath.smooth(0, buildUp, t)) }
        if t < clearStart { return 0.85 + 0.15 * Float(DayMath.smooth(buildUp, buildUp + 8, t)) }
        return 1 - Float(DayMath.smooth(clearStart, total, t))
    }
    /// Rain on the glass 0...1: starts a third of the way into the build-up.
    func rain(at t: Double) -> Float {
        if t <= 0 || t >= total { return 0 }
        if t < buildUp { return 0.5 * Float(DayMath.smooth(buildUp * 0.35, buildUp, t)) }
        if t < clearStart { return 0.5 + 0.5 * Float(DayMath.smooth(buildUp, buildUp + 10, t)) }
        return 1 - Float(DayMath.smooth(clearStart, total - 2, t))
    }
    /// The lightning flash 0...1 at storm time `t`: each pulse is a quick rise and an exponential fade.
    func flash(at t: Double, reduce: Bool = false) -> Float {
        var f: Float = 0
        for s in strikes where t >= s.t && t < s.t + 1.6 {
            for (i, p) in s.pulses.enumerated() {
                if reduce, i > 0 { continue }
                let x = t - (s.t + p.dt)
                guard x >= 0 else { continue }
                let rise = Float(min(x / (reduce ? 0.25 : 0.03), 1))
                let fall = Float(exp(-x / (reduce ? 0.7 : p.dur)))
                f = max(f, p.amp * s.strength * rise * fall)
            }
        }
        return min(f, 1)
    }
    func spot(at t: Double) -> Float {
        var best: (Double, Float) = (-1, 0.5)
        for s in strikes where s.t <= t && s.t > best.0 { best = (s.t, s.spot) }
        return best.1
    }
}

/// What the renderer reads each frame.
nonisolated struct WeatherLook: Equatable, Sendable {
    var phase: StormPhase = .clear
    var gloom: Float = 0
    var rain: Float = 0
    var flash: Float = 0
    var spot: Float = 0.5
    var isClear: Bool { gloom <= 0.001 && rain <= 0.001 && flash <= 0.001 }
    /// The post exposure of the whole frame: the room dims as the sky darkens (less at night, which is dark already) and lifts a little with a flash.
    func exposure(night: Float) -> Float {
        (1 - WeatherTuning.roomDip * gloom * (1 - 0.5 * night)) * (1 + WeatherTuning.roomLift * flash * WeatherTuning.flashPeak)
    }
}

/// The weather book: when the next storm comes, the storm in progress, persisted in UserDefaults.
@MainActor
final class WeatherBook {
    static let shared: WeatherBook = {
        let w = WeatherBook()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { w.disabled = true }
        return w
    }()

    static let playKey = "Weather.playSec.v1", nextKey = "Weather.nextAt.v1", seedKey = "Weather.seedCounter.v1"

    private let defaults: UserDefaults
    /// Seconds of play so far (only counts while the room is on screen) and the play time of the next storm.
    private(set) var playSeconds: Double
    private(set) var nextStormAt: Double
    private(set) var plan: StormPlan?
    private(set) var stormTime: Double = 0
    private var cursor = 0
    private var rolls: UInt64
    private var lastSave: Double = 0
    /// Suites and captures: no storm ever starts by itself (a forced one still runs).
    var disabled = false
    /// A storm to start after `forcedDelay` seconds of play (`-Storm 1`), or at the peak (`-Storm 2`) / clearing (`-Storm 3`).
    private(set) var forced: Int
    private var forcedWait: Double
    private var reduce = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rolls = UInt64(max(0, defaults.integer(forKey: Self.seedKey)))
        playSeconds = defaults.double(forKey: Self.playKey)
        if defaults.object(forKey: Self.nextKey) != nil { nextStormAt = defaults.double(forKey: Self.nextKey) }
        else {
            var g = WeatherRNG(seed: UInt64(Date().timeIntervalSince1970))
            nextStormAt = playSeconds + g.range(WeatherTuning.gap)
            defaults.set(nextStormAt, forKey: Self.nextKey)
        }
        forced = defaults.integer(forKey: "Storm")
        forcedWait = defaults.object(forKey: "StormDelay") != nil ? defaults.double(forKey: "StormDelay") : WeatherTuning.forcedDelay
        if forced > 0 { disabled = false }
    }
    nonisolated deinit {}

    var phase: StormPhase { plan.map { $0.phase(at: stormTime) } ?? .clear }
    var isStorming: Bool { plan != nil }

    /// The current look (cheap; the stage calls it every frame).
    func look(reduce: Bool = false) -> WeatherLook {
        guard let p = plan else { return WeatherLook() }
        return WeatherLook(phase: p.phase(at: stormTime), gloom: p.gloom(at: stormTime), rain: p.rain(at: stormTime), flash: p.flash(at: stormTime, reduce: reduce), spot: p.spot(at: stormTime))
    }

    /// Advances the weather by `dt` seconds of play and returns the events that came due. `active` false (a menu, another scene) stops the clock.
    @discardableResult
    func tick(dt: Double, active: Bool = true, reduce: Bool = false) -> [StormEvent] {
        self.reduce = reduce
        guard active, dt > 0, dt < 5 else { return [] }
        var out: [StormEvent] = []
        if let p = plan {
            stormTime += dt
            while cursor < p.events.count, p.events[cursor].t <= stormTime { out.append(p.events[cursor]); cursor += 1 }
            if stormTime >= p.total { plan = nil; stormTime = 0; cursor = 0 }
            return out
        }
        playSeconds += dt
        if playSeconds - lastSave >= 10 { save() }
        if forced > 0 {
            forcedWait -= dt
            if forcedWait <= 0 { let f = forced; forced = 0; out = begin(seed: UInt64(f) &* 7919 &+ 11, jumpTo: f == 2 ? .peak : f == 3 ? .clearing : .buildUp) }
        } else if !disabled, playSeconds >= nextStormAt {
            rolls &+= 1
            out = begin(seed: UInt64(Date().timeIntervalSince1970) &+ rolls)
        }
        return out
    }

    /// Starts a storm now (tests, the forced launch argument, the next-storm roll). `jumpTo` skips ahead (a demo straight at the peak).
    @discardableResult
    func begin(seed: UInt64, jumpTo: StormPhase = .buildUp) -> [StormEvent] {
        let p = StormPlan.make(seed: seed)
        plan = p; stormTime = 0; cursor = 0
        var g = WeatherRNG(seed: seed ^ 0xABCDEF)
        nextStormAt = playSeconds + g.range(WeatherTuning.gap)         // rolled at the START: killing the app mid-storm neither repeats nor rerolls it
        save()
        var out: [StormEvent] = []
        switch jumpTo {
        case .peak: stormTime = p.peakStart
        case .clearing: stormTime = p.clearStart
        default: break
        }
        while cursor < p.events.count, p.events[cursor].t <= stormTime {
            let e = p.events[cursor]; cursor += 1
            if case .rumble = e.kind { continue }
            if case .notice = e.kind { continue }
            if case .flash = e.kind { continue }
            if case .thunder = e.kind { continue }
            out.append(e)
        }
        return out
    }

    /// Ends the storm at once (the app left the room, tests); the next one stays where it was.
    func endNow() { plan = nil; stormTime = 0; cursor = 0 }

    func save() {
        lastSave = playSeconds
        defaults.set(playSeconds, forKey: Self.playKey); defaults.set(nextStormAt, forKey: Self.nextKey); defaults.set(Int(truncatingIfNeeded: rolls), forKey: Self.seedKey)
    }
}

/// The storm's haptics (user 2026-11-02): soft and cozy. A far rumble is one very soft long low pulse (<= 0.8 s) with the rumble sound, a close thunder at the peak a slightly stronger
/// but still gentle one, a lightning flash alone nothing, the huddle's tremble nothing (it is only visual), the relieved shake-off one soft tick. Thunder haptics are at most one
/// per 10 s and skipped while a race, volleyball or the bath has the haptics. Requests are counted (tests); the driver call is a no-op unless the engine is warm and Haptics is on.
enum StormHaptic: Equatable { case farRumble, closeRumble, softTick }

@MainActor
final class StormHaptics {
    static let shared = StormHaptics()
    static let thunderGap: Double = 10
    static let farPeak: Float = 0.16, closePeak: Float = 0.30, farDuration: Float = 0.8, closeDuration: Float = 0.6, tick: Float = 0.22

    private var lastThunder = -Double.infinity
    /// Every request that went out (kind, time), for the log and the tests.
    private(set) var sent: [(kind: StormHaptic, at: Double)] = []
    init() {}
    nonisolated deinit {}

    func reset() { lastThunder = -.infinity; sent = [] }

    /// Returns true when it went out. `blocked`: another system owns the haptics right now.
    @discardableResult
    func request(_ h: StormHaptic, now: Double, blocked: Bool, driver: HapticDriver?) -> Bool {
        guard !blocked else { return false }
        if h != .softTick {
            guard now - lastThunder >= Self.thunderGap else { return false }
            lastThunder = now
        }
        sent.append((h, now)); if sent.count > 200 { sent.removeFirst() }
        guard let driver else { return true }
        switch h {
        case .farRumble: driver.ambient(peak: Self.farPeak, duration: Self.farDuration)
        case .closeRumble: driver.ambient(peak: Self.closePeak, duration: Self.closeDuration)
        case .softTick: driver.ambientTick(intensity: Self.tick)
        }
        return true
    }

    /// The haptic for one storm event (nil = none).
    static func haptic(for e: StormEvent, plan: StormPlan?) -> StormHaptic? {
        switch e.kind {
        case .rumble: return .farRumble
        case .thunder(let i): return (plan?.strikes[safe: i]?.close ?? false) ? .closeRumble : .farRumble
        default: return nil          // a flash alone, the phases, the notice: nothing
        }
    }
}
