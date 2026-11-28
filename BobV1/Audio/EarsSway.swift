//
//  EarsSway.swift
//  The ONE move of the Music Ears dance: a side-to-side sway whose extremes land on the beat, with a small bob (down at each extreme).
//  A free-running clock (phase `u` counts side changes; an integer is a beat landing and an extreme of the sway) that is only ever STEERED by the
//  tempo tracker, never set by it: a new tempo or beat anchor changes the clock's speed or slews its phase (rate-limited), so the pose is a
//  continuous function of time and can not pop when a phrase changes, the beat is re-anchored, found or lost. A phase measurement is taken as the
//  medoid of the last three (one wrong estimate, such as a half-beat flip between a kick and a backbeat, is ignored), and a different tempo has to
//  repeat before the clock follows it. Fast songs (above `foldAbove` BPM) sway on every second beat: the sway then lands on a beat all the same.
//  Without a beat (before the first one, or after it was lost) the clock keeps its last tempo (it coasts), so there is no switch to a "fallback" sway.
//  Pure Foundation (the offline harness compiles it).
//

import Foundation

nonisolated struct EarsSway {
    /// Side changes per second before any beat is known (a slow, gentle sway).
    static let idleRate: Double = 0.55
    /// Beat tempos from this BPM up sway on every second beat (side change per two beats); below `foldBelow` they are doubled (none in practice: the DSP's range is 70...160).
    static let foldAbove: Float = 116, foldBelow: Float = 58
    /// Largest phase correction (side changes per second) once locked, and for the first lock.
    static let maxSlew: Double = 0.35, firstSlew: Double = 0.8
    /// Largest change of the clock's speed (side changes per second, per second).
    static let maxRateChange: Double = 0.8
    /// Amplitude (0...1) before the beat is known and once it is: the sway grows into the beat.
    static let idleAmp: Float = 0.6
    static let ampRamp: Float = 0.6

    static func swayBpm(_ bpm: Float) -> Float {
        var b = max(bpm, 1)
        while b >= foldAbove { b /= 2 }
        while b < foldBelow { b *= 2 }
        return b
    }

    private(set) var u: Double = 0
    /// Side changes per beat of the heard tempo (1, or 1/2 for a tempo that is folded: the sway changes side on every second beat but every beat is a landing) and the
    /// clock's speed (side changes per second). The dance steps (ears-dance-r2) are timed on `u` in these units, so they land where the sway lands.
    private(set) var unit: Double = 1
    var ratePerSecond: Double { rate }
    private var u0: Double = 0, theta: Double = 0, thetaTarget: Double = 0
    private var rate: Double = EarsSway.idleRate, rateTarget: Double = EarsSway.idleRate
    private(set) var locked = false
    private var offsets: [Double] = []
    private var rateCand: Double = 0, rateCandRuns = 0
    private(set) var amp: Float = EarsSway.idleAmp
    /// Seconds since the last measurement (the clock's age: > ~3 s means it is coasting).
    private(set) var sinceHeard: Double = .infinity
    var isCoasting: Bool { sinceHeard > 3 }

    /// Back to the idle clock (a new dance).
    mutating func reset(startPhase: Double = 0) { self = EarsSway(); u0 = startPhase; u = startPhase }

    /// `x` wrapped to the nearest multiple of `unit` (the beat, in side changes: 1 or 1/2).
    private static func wrap(_ x: Double, _ unit: Double) -> Double { x - (x / unit).rounded() * unit }

    /// A tempo / beat estimate (host or stream time `now`, the same base as `b.anchor`).
    mutating func hear(_ b: EarBeat, now: Double) {
        sinceHeard = 0
        let sb = Double(Self.swayBpm(b.bpm))
        let period = 60 / sb
        let measured = sb / 60
        // tempo: the first one at once, a steady one smoothly, another one only when it repeats
        if !locked { rateTarget = measured; rate = measured; rateCandRuns = 0 }          // (the first tempo is taken at once: the clock does not ramp up to it, which would leave its phase behind)
        else if abs(measured / rateTarget - 1) < 0.06 { rateTarget = measured; rateCandRuns = 0 }
        else {
            if rateCandRuns > 0, abs(measured / rateCand - 1) < 0.06 { rateCandRuns += 1 } else { rateCand = measured; rateCandRuns = 1 }
            if rateCandRuns >= 2 { rateTarget = measured; rateCandRuns = 0 }
        }
        // phase: the offset between the heard grid and the free clock, unwrapped next to the one in use
        // (every beat is a landing, and with a folded tempo the sway side changes on every second one: the phase counts modulo ONE BEAT = `unit` side changes)
        let unit = 1 / Double(max(1, (Double(b.bpm) / sb).rounded()))
        self.unit = unit
        var th = (now - b.anchor) / period - u0
        th -= ((th - theta) / unit).rounded() * unit
        if !locked { offsets.removeAll(); thetaTarget = th }
        offsets.append(th)
        if offsets.count > 3 { offsets.removeFirst() }
        if offsets.count >= 3 {
            // medoid on the circle: the offset closest to the other two
            var best = offsets[2], bestCost = Double.infinity
            for i in [2, 1, 0] {
                var c = 0.0
                for j in 0..<3 where j != i { c += abs(Self.wrap(offsets[i] - offsets[j], unit)) }
                if c < bestCost - 1e-9 { bestCost = c; best = offsets[i] }
            }
            thetaTarget = best - ((best - theta) / unit).rounded() * unit
        } else if locked {
            thetaTarget = th          // (the second estimate after a lock: follow the newest)
        }
        if !locked { locked = true; firstLock = true }
    }

    private var firstLock = false

    /// The beat was lost: the clock coasts at its last tempo (nothing changes here).
    mutating func lost() {}

    /// Advances the clock by `dt` seconds.
    mutating func tick(dt: Double) {
        sinceHeard += dt
        let dr = min(max(rateTarget - rate, -Self.maxRateChange * dt), Self.maxRateChange * dt)
        rate += dr
        u0 += rate * dt
        let slew = (firstLock ? Self.firstSlew : Self.maxSlew) * dt
        let dth = min(max(thetaTarget - theta, -slew), slew)
        theta += dth
        if firstLock, abs(thetaTarget - theta) < 1e-6 { firstLock = false }
        u = u0 + theta
        let goal: Float = locked ? 1 : Self.idleAmp
        amp += min(max(goal - amp, -Float(dt) * Self.ampRamp), Float(dt) * Self.ampRamp)
    }

    /// Roll (rad, + = one side) at the current phase: extremes on the beats.
    func roll(maxRoll: Float) -> Float { maxRoll * amp * Float(cos(Double.pi * u)) }
    /// Squash factor (1 = none): lowest at each extreme, up between.
    func squash(depth: Float) -> Float { 1 - depth * amp * Float(0.5 + 0.5 * cos(2 * Double.pi * u)) }
}
