//
//  Haptics.swift
//  Touch haptics for focus mode (pet / pick up / bounce / cheeks).
//
//  Layers (so the mapping and the CSV log run headless in the simulator, where CHHapticEngine.supportsHaptics is false):
//    HapticMap       pure functions: the numbers that decide how it feels (dead zone, monotonic depth, impact scale, wobble decay)
//    HapticSink      what a backend must do: start / stop (warm while in focus), two continuous channels, transients, a wobble curve
//    RecordingHapticSink   a fake that records every call (tests) and writes the CSV log (-HapticLog <path>)
//    CoreHapticsSink       the real CHHapticEngine path (device only)
//    HapticDriver    turns the touch state into sink calls: at most 60 Hz per channel, only on change, off when the Settings toggle is off
//
//  Sound hook: `HapticDriver.soundHook` is called for every transient / wobble so an audio layer can pair a soft sound later.
//

import Foundation
import QuartzCore
import CoreHaptics

// MARK: - Settings

enum HapticSettings {
    /// UserDefaults key of the Settings toggle ("Haptics").
    static let key = "HapticsEnabled"
    /// On by default (an unset key reads true). Worker A's settings UI binds a Toggle to this (`@AppStorage(HapticSettings.key)` with default true).
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Mapping (pure)

enum HapticMap {
    // pet: finger speed along his surface, in world units per second (one body width is about 1.1 u)
    static let petDeadZone: Float = 0.15
    static let petFullSpeed: Float = 4.5

    @inline(__always) static func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }

    /// 0...1 progress of a stroke above the dead zone.
    static func petProgress(speed v: Float) -> Float { clamp01((v - petDeadZone) / (petFullSpeed - petDeadZone)) }

    /// Silent in the dead zone, then rising with the stroke speed (a gentle floor so the first bit of motion is felt).
    static func petIntensity(speed v: Float) -> Float {
        let s = petProgress(speed: v)
        return s <= 0 ? 0 : 0.10 + 0.75 * powf(s, 0.75)
    }

    /// Belly rub: a deeper, softer rumble than the plain stroke at any speed (still silent in the dead zone), sharpness 0.05...0.10.
    static func bellyIntensity(speed v: Float) -> Float {
        let s = petProgress(speed: v)
        return s <= 0 ? 0 : 0.30 + 0.65 * powf(s, 0.6)
    }
    static func bellySharpness(speed v: Float) -> Float { 0.05 + 0.05 * petProgress(speed: v) }

    /// Low sharpness (soft, round) that rises a little with speed: 0.10 ... 0.30.
    static func petSharpness(speed v: Float) -> Float { 0.10 + 0.20 * petProgress(speed: v) }

    /// Deformation depth (sim units) at which the squish feel is full.
    static let squishFullDepth: Float = 0.35

    /// Squish / stretch / cheeks press: grows monotonically with the live deformation depth; 0 below a hair.
    static func squishIntensity(depth d: Float) -> Float {
        let s = clamp01(d / squishFullDepth)
        return d < 0.004 ? 0 : 0.12 + 0.66 * (s * s * (3 - 2 * s))
    }

    /// The sharpness falls as it deepens: a surface touch is crisp, a deep squish is dull and heavy.
    static func squishSharpness(depth d: Float) -> Float {
        let s = clamp01(d / squishFullDepth)
        return 0.30 - 0.20 * s          // jelly: always soft and round, deeper = duller (no crisp edge)
    }

    /// One soft pulse of the settling jelly after he is let go (`amp` = how far the squash swung past his resting height, sim units):
    /// it fades as the wobble does, low sharpness, never above a warm 0.55.
    static func jellyPulse(amplitude a: Float) -> (intensity: Float, sharpness: Float) {
        (min(0.55, 0.10 + 4.0 * max(0, a)), 0.12)
    }

    /// Bounce / landing transient from the impact speed (world units per second).
    static func impactIntensity(speed v: Float) -> Float { clamp01(0.22 + 0.78 * clamp01(v / 6)) }
    static func impactSharpness(speed v: Float) -> Float { 0.20 + 0.25 * clamp01(v / 6) }

    /// Wobble: a continuous buzz whose intensity decays like the measured wobble (time constant `tau`, seconds).
    /// Control points (relative time, 0...1 multiplier) of the intensity curve; at most 16 points.
    static func wobbleCurve(tau: Float, duration: Float) -> [(t: Float, v: Float)] {
        let n = 10
        return (0..<n).map { k in
            let t = duration * Float(k) / Float(n - 1)
            return (t, expf(-t / max(tau, 0.01)))
        }
    }
    static let wobbleTau: Float = 0.32
    static let wobbleDuration: Float = 1.0

    /// Cheeks: the firm press deepens with the pinch (0...1), and the release "bloop".
    static func cheeksIntensity(pinch p: Float) -> Float { p <= 0.01 ? 0 : 0.25 + 0.65 * (clamp01(p) * clamp01(p)) }
    static func cheeksSharpness(pinch p: Float) -> Float { 0.45 - 0.30 * clamp01(p) }
    static func bloop(pinch p: Float) -> (intensity: Float, sharpness: Float) { (0.45 + 0.4 * clamp01(p), 0.25) }
}

// MARK: - Sink

enum HapticChannel: String, Sendable { case pet, squish }

@MainActor
protocol HapticSink: AnyObject {
    /// Engine up (warm) / down. Called when focus mode starts / ends.
    func start()
    func stop()
    /// A looping continuous channel's live level. intensity 0 = silent.
    func setContinuous(_ ch: HapticChannel, intensity: Float, sharpness: Float)
    func transient(intensity: Float, sharpness: Float)
    /// A decaying buzz: starts at `peak`, falls on the curve with time constant `tau`.
    func wobble(peak: Float, sharpness: Float, tau: Float, duration: Float)
    /// Called every frame (housekeeping, for example stopping idle players).
    func poll(now: Double)
}

extension HapticSink { func poll(now: Double) {} }

// MARK: Recording fake (tests + CSV)

@MainActor
final class RecordingHapticSink: HapticSink {
    struct Event: Equatable {
        enum Kind: String { case start, stop, continuous, transient, wobble }
        var t: Double
        var kind: Kind
        var channel: String
        var intensity: Float
        var sharpness: Float
        var extra: Float      // wobble tau
    }
    private(set) var events: [Event] = []
    private(set) var running = false
    private(set) var startCount = 0, stopCount = 0
    /// Clock for the time column (tests set a manual one).
    var clock: () -> Double = { CACurrentMediaTime() }
    private var t0: Double?
    let logPath: String?

    init(logPath: String? = nil) { self.logPath = logPath }
    nonisolated deinit {}

    private func now() -> Double { let c = clock(); if t0 == nil { t0 = c }; return c - (t0 ?? c) }

    func start() { running = true; startCount += 1; events.append(Event(t: now(), kind: .start, channel: "", intensity: 0, sharpness: 0, extra: 0)) }
    func stop() {
        running = false; stopCount += 1
        events.append(Event(t: now(), kind: .stop, channel: "", intensity: 0, sharpness: 0, extra: 0))
        flush()
    }
    func setContinuous(_ ch: HapticChannel, intensity: Float, sharpness: Float) {
        events.append(Event(t: now(), kind: .continuous, channel: ch.rawValue, intensity: intensity, sharpness: sharpness, extra: 0))
    }
    func transient(intensity: Float, sharpness: Float) {
        events.append(Event(t: now(), kind: .transient, channel: "transient", intensity: intensity, sharpness: sharpness, extra: 0))
    }
    func wobble(peak: Float, sharpness: Float, tau: Float, duration: Float) {
        events.append(Event(t: now(), kind: .wobble, channel: "wobble", intensity: peak, sharpness: sharpness, extra: tau))
    }

    func clear() { events.removeAll(); t0 = nil }

    private var lastFlushCount = 0, lastFlushAt: Double = 0
    /// Keeps the CSV file current while focus is on (every ~1 s when something changed).
    func poll(now: Double) {
        guard logPath != nil, events.count != lastFlushCount, now - lastFlushAt > 1 else { return }
        lastFlushCount = events.count; lastFlushAt = now; flush()
    }

    func events(_ kind: Event.Kind, channel: String? = nil) -> [Event] {
        events.filter { $0.kind == kind && (channel == nil || $0.channel == channel) }
    }

    var csv: String {
        var s = "t,kind,channel,intensity,sharpness,tau\n"
        for e in events {
            s += String(format: "%.4f,%@,%@,%.4f,%.4f,%.3f\n", e.t, e.kind.rawValue, e.channel, e.intensity, e.sharpness, e.extra)
        }
        return s
    }

    func flush() {
        guard let logPath else { return }
        try? csv.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

// MARK: Core Haptics (device only)

@MainActor
final class CoreHapticsSink: HapticSink {
    private var engine: CHHapticEngine?
    private var players: [HapticChannel: CHHapticAdvancedPatternPlayer] = [:]
    private var running: Set<HapticChannel> = []
    private var lastLevel: [HapticChannel: Float] = [:]
    private var silentSince: [HapticChannel: Double] = [:]
    private var wanted = false
    private var lastTransient: Double = 0

    static var supported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    /// nil where the hardware has no haptics (the simulator, iPads).
    static func make() -> CoreHapticsSink? { supported ? CoreHapticsSink() : nil }

    init() {}
    nonisolated deinit {}

    func start() {
        wanted = true
        guard engine == nil else { return }
        do {
            let e = try CHHapticEngine()
            e.playsHapticsOnly = true
            e.isAutoShutdownEnabled = false        // warm while in focus
            e.resetHandler = { [weak self] in
                Task { @MainActor in self?.rebuild() }
            }
            e.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.engineStopped() }
            }
            try e.start()
            engine = e
            try makePlayers()
        } catch {
            engine = nil
        }
    }

    func stop() {
        wanted = false
        for (_, p) in players { try? p.stop(atTime: CHHapticTimeImmediate) }
        players.removeAll(); running.removeAll(); lastLevel.removeAll(); silentSince.removeAll()
        engine?.stop(completionHandler: { _ in })
        engine = nil
    }

    private func engineStopped() {
        // the system stopped it (audio session, background): the players are dead; start again if focus is still on
        players.removeAll(); running.removeAll(); lastLevel.removeAll()
        guard wanted else { engine = nil; return }
        try? engine?.start()
        try? makePlayers()
    }

    private func rebuild() {
        players.removeAll(); running.removeAll(); lastLevel.removeAll()
        guard wanted, let e = engine else { return }
        do { try e.start(); try makePlayers() } catch { engine = nil }
    }

    private func makePlayers() throws {
        guard let e = engine else { return }
        for ch in [HapticChannel.pet, .squish] {
            // one long continuous event at full intensity / zero base sharpness; the live controls scale it (intensity multiplies,
            // sharpness adds), and the advanced player loops it
            let ev = CHHapticEvent(eventType: .hapticContinuous,
                                   parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                                                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0)],
                                   relativeTime: 0, duration: 30)
            let pattern = try CHHapticPattern(events: [ev], parameters: [])
            let p = try e.makeAdvancedPlayer(with: pattern)
            p.loopEnabled = true
            players[ch] = p
        }
    }

    func setContinuous(_ ch: HapticChannel, intensity: Float, sharpness: Float) {
        guard let p = players[ch] else { return }
        do {
            if intensity > 0, !running.contains(ch) {
                try p.sendParameters(controls(intensity, sharpness), atTime: CHHapticTimeImmediate)
                try p.start(atTime: CHHapticTimeImmediate)
                running.insert(ch)
            } else if running.contains(ch) {
                try p.sendParameters(controls(intensity, sharpness), atTime: CHHapticTimeImmediate)
            }
        } catch { return }
        if intensity <= 0 { if silentSince[ch] == nil { silentSince[ch] = CACurrentMediaTime() } } else { silentSince[ch] = nil }
    }

    private func controls(_ i: Float, _ s: Float) -> [CHHapticDynamicParameter] {
        [CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: i, relativeTime: 0),
         CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: s, relativeTime: 0)]
    }

    /// Stops a looping player that has been silent for a while (saves power); it restarts at the next non-zero level.
    func poll(now: Double) {
        for (ch, t) in silentSince where now - t > 1.0 {
            if running.contains(ch) { try? players[ch]?.stop(atTime: CHHapticTimeImmediate); running.remove(ch) }
            silentSince[ch] = nil
        }
    }

    func transient(intensity: Float, sharpness: Float) {
        guard let e = engine else { return }
        let now = CACurrentMediaTime()
        guard now - lastTransient > 0.04 else { return }
        lastTransient = now
        let ev = CHHapticEvent(eventType: .hapticTransient,
                               parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)],
                               relativeTime: 0)
        do {
            let p = try e.makePlayer(with: CHHapticPattern(events: [ev], parameters: []))
            try p.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    func wobble(peak: Float, sharpness: Float, tau: Float, duration: Float) {
        guard let e = engine else { return }
        let ev = CHHapticEvent(eventType: .hapticContinuous,
                               parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: peak),
                                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)],
                               relativeTime: 0, duration: TimeInterval(duration))
        let pts = HapticMap.wobbleCurve(tau: tau, duration: duration).map {
            CHHapticParameterCurve.ControlPoint(relativeTime: TimeInterval($0.t), value: $0.v)
        }
        let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: pts, relativeTime: 0)
        do {
            let p = try e.makePlayer(with: CHHapticPattern(events: [ev], parameterCurves: [curve]))
            try p.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }
}

// MARK: - Driver

/// What the touch state asks of the hardware, each frame. At most 60 Hz per channel (a call closer than 1/60 s after the last one on
/// that channel waits for the next frame), and only when the level changed by more than an epsilon.
@MainActor
final class HapticDriver {
    var sinks: [HapticSink] = []
    /// Honours the Settings toggle; re-read every half second.
    var enabled = HapticSettings.enabled
    private(set) var warm = false
    var soundHook: ((_ kind: String, _ intensity: Float) -> Void)?

    static let minInterval: Double = 1.0 / 60 - 0.0006
    static let epsilon: Float = 0.012
    static let impactGap: Double = 0.08

    private struct Level { var i: Float = 0; var s: Float = 0; var t: Double = -1 }
    private var level: [HapticChannel: Level] = [:]
    private var lastImpact: Double = -1
    private var settingsT: Double = 0
    /// Wall time spent in `update` (perf log).
    private(set) var costSum: Double = 0, costN = 0

    init(sinks: [HapticSink] = []) { self.sinks = sinks }
    nonisolated deinit {}

    /// Real device sink when the hardware has haptics, plus the CSV recorder when `-HapticLog <path>` is set.
    static func makeDefault() -> HapticDriver {
        var sinks: [HapticSink] = []
        if let s = CoreHapticsSink.make() { sinks.append(s) }
        if let path = UserDefaults.standard.string(forKey: "HapticLog") { sinks.append(RecordingHapticSink(logPath: path)) }
        return HapticDriver(sinks: sinks)
    }

    var recorder: RecordingHapticSink? { sinks.compactMap { $0 as? RecordingHapticSink }.first }

    /// Focus mode on / off: the engine is warm exactly while this is true.
    func setWarm(_ on: Bool) {
        guard on != warm else { return }
        warm = on
        if on { enabled = HapticSettings.enabled }
        if on, !enabled { return }
        for s in sinks { on ? s.start() : s.stop() }
        if !on { level.removeAll() }
    }

    /// One call per frame with the wanted levels (time `now` in seconds on any monotonic clock).
    func update(now: Double, petIntensity: Float, petSharpness: Float, squishIntensity: Float, squishSharpness: Float) {
        let c0 = CACurrentMediaTime()
        defer { costSum += CACurrentMediaTime() - c0; costN += 1 }
        if now - settingsT > 0.5 {
            settingsT = now
            let e = HapticSettings.enabled
            if e != enabled { enabled = e; if warm { for s in sinks { e ? s.start() : s.stop() }; level.removeAll() } }
        }
        guard warm, enabled else { return }
        send(.pet, now: now, i: petIntensity, s: petSharpness)
        send(.squish, now: now, i: squishIntensity, s: squishSharpness)
        for s in sinks { s.poll(now: now) }
    }

    private func send(_ ch: HapticChannel, now: Double, i: Float, s: Float) {
        var l = level[ch] ?? Level()
        if l.t >= 0, now - l.t < Self.minInterval { return }
        let changed = abs(i - l.i) > Self.epsilon || (i > 0 && abs(s - l.s) > 0.02) || (i == 0 && l.i != 0)
        guard changed else { return }
        l.i = i; l.s = s; l.t = now
        level[ch] = l
        for k in sinks { k.setContinuous(ch, intensity: i, sharpness: s) }
    }

    func transient(now: Double, intensity: Float, sharpness: Float) {
        guard warm, enabled else { return }
        for k in sinks { k.transient(intensity: intensity, sharpness: sharpness) }
        soundHook?("transient", intensity)
    }

    /// Bounce / landing thump scaled by the impact speed; rate limited.
    func impact(now: Double, speed: Float) {
        guard warm, enabled, now - lastImpact >= Self.impactGap else { return }
        lastImpact = now
        let i = HapticMap.impactIntensity(speed: speed), s = HapticMap.impactSharpness(speed: speed)
        for k in sinks { k.transient(intensity: i, sharpness: s) }
        soundHook?("impact", i)
    }

    func wobble(now: Double, peak: Float) {
        guard warm, enabled else { return }
        for k in sinks { k.wobble(peak: peak, sharpness: 0.2, tau: HapticMap.wobbleTau, duration: HapticMap.wobbleDuration) }
        soundHook?("wobble", peak)
    }

    func takeCost() -> (ms: Double, n: Int) {
        let r = (costN > 0 ? costSum / Double(costN) * 1000 : 0, costN); costSum = 0; costN = 0; return r
    }
}
