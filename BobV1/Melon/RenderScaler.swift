//
//  RenderScaler.swift
//  Continuous, adaptive render resolution + frame-rate request. Pure state machines (no UIKit / Metal) so they unit test.
//
//  Goal: Bob never drops below a smooth frame rate; resolution degrades before frame rate does. Only the drawable /
//  offscreen target size changes. Simulation physics and timestep are never touched.
//

import Foundation

/// Steps the render scale down when the smoothed GPU frame time stays over budget for ~0.5 s, and back up after ~3 s
/// comfortably under budget (hysteresis: a step up is only taken if the predicted cost at the higher scale still fits).
struct RenderScaler {
    /// Scales tried below native, highest first. Native itself (3x on iPhone Pro) is always level 0.
    static let ladder: [Double] = [3, 2.5, 2, 1.67, 1.5, 1.33]
    /// The `-MetalFX 1` ladder (native multiples; 3x = 1206 px wide on the Pro): native with no upscale, then 1005 / 880 / 603 px wide rendered and upscaled by MetalFX
    /// (a 603 px MetalFX picture looks about as crisp as a raw 880 one, so it replaces the raw 585 rung). Off = the raw ladder above.
    static let metalFXLadder: [Double] = [2.5, 2.19, 1.5]
    static let thermalCap = 2.0
    static let downAfter = 0.5          // s over budget before a step down
    static let upAfter = 3.0            // s comfortably under budget before a step up
    static let settle = 0.4             // s of ignored samples after any change (targets re-created, GPU warms)
    static let budgetFraction = 0.85    // of the target frame interval
    static let upHeadroom = 0.90        // predicted cost at the next scale must be under budget x this
    // Thermal-first mode (the game): the phone must stay cool, so the budget is a SUSTAINED GPU time, not "whatever fits in a frame".
    static let sustainedBudgetMs = 6.0          // GPU ms per frame we aim to stay under
    static let calmScale = 2.2                  // the sharpest scale used by default (the 2.19x MetalFX rung; 2.0 on the raw ladder)
    static let nativeClimbMs = 4.0              // climbing above calmScale needs this much GPU headroom ...
    static let nativeClimbAfter = 30.0          // ... for this long, with the thermal state nominal
    static let thermalHold = 60.0               // no climbing for this long after a thermal step down

    let levels: [Double]
    private(set) var level = 0
    var scale: Double { levels[level] }
    /// Frame interval the budget is measured against (s). Resolution is always judged against 60 Hz.
    var targetInterval: Double
    var budgetMs: Double { thermalFirst ? Self.sustainedBudgetMs : targetInterval * 1000 * Self.budgetFraction }
    let thermalFirst: Bool
    private var lastThermal = ProcessInfo.ThermalState.nominal
    private var holdT = 0.0

    private(set) var smoothedMs: Double?
    private var overT = 0.0, underT = 0.0, settleT = 0.0
    private var upWait = RenderScaler.upAfter
    private var lastStepUpAt = -1000.0, clock = 0.0
    private var cap = 0                 // lowest allowed level index (thermal)

    init(native: Double, targetInterval: Double = 1.0 / 60, metalFX: Bool = false, thermalFirst: Bool = false) {
        var l = [max(native, 1)]
        for s in (metalFX ? Self.metalFXLadder : Self.ladder) where s < l[0] - 0.01 { l.append(s) }
        levels = l
        self.thermalFirst = thermalFirst
        if thermalFirst { level = l.firstIndex { $0 <= Self.calmScale } ?? 0 }          // starts at the calm rung, climbs to native only when cool and idle
        self.targetInterval = targetInterval
    }

    /// Level index whose scale is <= `thermalCap` (the highest allowed under serious / critical thermal state).
    private var thermalLevel: Int { levels.firstIndex { $0 <= Self.thermalCap + 0.01 } ?? levels.count - 1 }

    /// Feed one frame. `gpuMs` = this frame's GPU time (nil if unknown). Returns the new scale if it changed.
    mutating func update(dt: Double, gpuMs: Double?, thermal: ProcessInfo.ThermalState) -> Double? {
        guard dt > 0, dt < 0.1 else { return nil }          // ignore stalls (first frames, backgrounding)
        clock += dt
        let newCap = (thermal == .serious || thermal == .critical) ? thermalLevel : 0
        cap = newCap
        if thermalFirst {
            if holdT > 0 { holdT -= dt }
            let worse = thermal.rawValue > lastThermal.rawValue
            lastThermal = thermal
            if worse, thermal != .nominal { holdT = Self.thermalHold; if level < max(cap, min(level + 1, levels.count - 1)) { return move(to: max(cap, level + 1)) } }
        }
        if level < cap { return move(to: cap) }              // thermal: drop at once
        if settleT > 0 { settleT -= dt; return nil }
        guard let g = gpuMs, g > 0 else { return nil }
        smoothedMs = smoothedMs.map { $0 + (g - $0) * min(1, dt / 0.15) } ?? g
        let ms = smoothedMs!

        if ms > budgetMs {
            overT += dt; underT = 0
            if overT >= Self.downAfter, level < levels.count - 1 {
                if clock - lastStepUpAt < 10 { upWait = min(upWait * 2, 24) }    // that step up did not hold: wait longer next time
                return move(to: level + 1)
            }
            return nil
        }
        overT = 0
        // Comfortably under: predicted cost at the next scale up (pixel count ~ scale^2) still fits with headroom.
        if level > cap {
            let r = levels[level - 1] / levels[level]
            let toNative = thermalFirst && levels[level - 1] > Self.calmScale
            let coolEnough = !thermalFirst || (holdT <= 0 && thermal == .nominal && (!toNative || ms < Self.nativeClimbMs))
            if coolEnough, ms * r * r < budgetMs * Self.upHeadroom {
                underT += dt
                if underT >= (toNative ? Self.nativeClimbAfter : upWait) {
                    lastStepUpAt = clock
                    return move(to: level - 1)
                }
            } else { underT = 0 }
        } else { underT = 0 }
        return nil
    }

    private mutating func move(to l: Int) -> Double {
        level = max(0, min(l, levels.count - 1))
        overT = 0; underT = 0; settleT = Self.settle; smoothedMs = nil
        return scale
    }
}

/// Chooses the frame rate: 60 or 120 Hz when cool, 30 Hz under thermal `.serious` or Low Power Mode, 24 Hz under `.critical`.
/// 120 is only requested when the GPU has lots of headroom and the device is cool and not in Low Power Mode; it falls back to 60 under
/// load and stays there for a while. Nominal / fair behaviour (without Low Power Mode) is exactly the old 60 / 120 logic.
struct RateGovernor {
    static let upBelowMs = 5.0          // 120 only if the smoothed GPU time is this low at the current scale
    static let downAboveMs = 7.0        // 8.33 ms x 0.85
    static let cpuUpBelowMs = 5.0       // 120 also needs the main thread under this (a 120 Hz frame is 8.33 ms of CPU too)
    static let cpuDownAboveMs = 7.0
    static let upAfter = 3.0, downAfter = 0.5, retryAfterDrop = 30.0
    static let seriousFPS = 30          // thermal serious or Low Power Mode
    static let criticalFPS = 24         // thermal critical (the display runs 24 Hz on every panel that has ProMotion; others round to 30)
    static let recoverAfter = 20.0      // s a lower cap must have been lifted before the rate climbs back to 60 (no flapping at a thermal edge)

    let maxFPS: Int
    private(set) var fps = 60
    private var smoothed: Double?
    private var underT = 0.0, overT = 0.0, hold = 0.0

    init(maxFPS: Int) { self.maxFPS = maxFPS }

    /// The highest rate allowed by the thermal state and Low Power Mode (60 = no cap; the 60 / 120 choice is made below).
    static func cap(thermal: ProcessInfo.ThermalState, lowPower: Bool) -> Int {
        if thermal == .critical { return criticalFPS }
        if thermal == .serious || lowPower { return seriousFPS }
        return 60
    }

    /// Returns the new preferred fps if it changed.
    mutating func update(dt: Double, gpuMs: Double?, thermal: ProcessInfo.ThermalState, lowPower: Bool, atNative: Bool = true, cpuMs: Double = 0) -> Int? {
        guard dt > 0, dt < 0.1 else { return nil }
        let hot = thermal == .serious || thermal == .critical
        let cap = Self.cap(thermal: thermal, lowPower: lowPower)
        if hold > 0 { hold -= dt }
        if cap < 60 {
            // thermal / Low Power cap: take it at once; the GPU headroom logic below is off while capped
            if fps != cap { return set(cap, hold: Self.recoverAfter) }
            return nil
        }
        if fps < 60 {          // the cap was lifted: back to 60 after a settling wait
            if hold <= 0 { return set(60, hold: 0) }
            return nil
        }
        if maxFPS < 120, fps != 60 { return set(60, hold: 0) }
        guard maxFPS >= 120, let g = gpuMs, g > 0 else { return nil }
        smoothed = smoothed.map { $0 + (g - $0) * min(1, dt / 0.15) } ?? g
        let ms = smoothed!
        if fps == 120 {
            overT = ms > Self.downAboveMs ? overT + dt : 0
            if overT >= Self.downAfter || cpuMs > Self.cpuDownAboveMs { return set(60, hold: Self.retryAfterDrop) }
        } else if !hot, atNative, hold <= 0, thermal != .fair {   // only at full resolution: never trade resolution for Hz
            underT = (ms < Self.upBelowMs && cpuMs < Self.cpuUpBelowMs) ? underT + dt : 0          // CPU headroom too: cpuMs is the main thread's frame time (0 = not measured, tests)
            if underT >= Self.upAfter { return set(120, hold: 0) }
        }
        return nil
    }

    private mutating func set(_ f: Int, hold h: Double) -> Int {
        fps = f; hold = h; underT = 0; overT = 0; smoothed = nil
        return f
    }
}
