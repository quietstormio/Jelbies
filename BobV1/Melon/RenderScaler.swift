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
    static let thermalCap = 2.0
    static let downAfter = 0.5          // s over budget before a step down
    static let upAfter = 3.0            // s comfortably under budget before a step up
    static let settle = 0.4             // s of ignored samples after any change (targets re-created, GPU warms)
    static let budgetFraction = 0.85    // of the target frame interval
    static let upHeadroom = 0.90        // predicted cost at the next scale must be under budget x this

    let levels: [Double]
    private(set) var level = 0
    var scale: Double { levels[level] }
    /// Frame interval the budget is measured against (s). Resolution is always judged against 60 Hz.
    var targetInterval: Double
    var budgetMs: Double { targetInterval * 1000 * Self.budgetFraction }

    private(set) var smoothedMs: Double?
    private var overT = 0.0, underT = 0.0, settleT = 0.0
    private var upWait = RenderScaler.upAfter
    private var lastStepUpAt = -1000.0, clock = 0.0
    private var cap = 0                 // lowest allowed level index (thermal)

    init(native: Double, targetInterval: Double = 1.0 / 60) {
        var l = [max(native, 1)]
        for s in Self.ladder where s < l[0] - 0.01 { l.append(s) }
        levels = l
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
            if ms * r * r < budgetMs * Self.upHeadroom {
                underT += dt
                if underT >= upWait {
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

/// Chooses 60 vs 120 Hz. 120 is only requested when the GPU has lots of headroom and the device is cool and not in
/// Low Power Mode; it falls back to 60 under load and stays there for a while.
struct RateGovernor {
    static let upBelowMs = 5.0          // 120 only if the smoothed GPU time is this low at the current scale
    static let downAboveMs = 7.0        // 8.33 ms x 0.85
    static let upAfter = 3.0, downAfter = 0.5, retryAfterDrop = 30.0

    let maxFPS: Int
    private(set) var fps = 60
    private var smoothed: Double?
    private var underT = 0.0, overT = 0.0, hold = 0.0

    init(maxFPS: Int) { self.maxFPS = maxFPS }

    /// Returns the new preferred fps if it changed.
    mutating func update(dt: Double, gpuMs: Double?, thermal: ProcessInfo.ThermalState, lowPower: Bool, atNative: Bool = true) -> Int? {
        guard dt > 0, dt < 0.1 else { return nil }
        let hot = thermal == .serious || thermal == .critical
        if hold > 0 { hold -= dt }
        if (hot || lowPower || maxFPS < 120), fps != 60 { return set(60, hold: 0) }
        guard maxFPS >= 120, let g = gpuMs, g > 0 else { return nil }
        smoothed = smoothed.map { $0 + (g - $0) * min(1, dt / 0.15) } ?? g
        let ms = smoothed!
        if fps == 120 {
            overT = ms > Self.downAboveMs ? overT + dt : 0
            if overT >= Self.downAfter { return set(60, hold: Self.retryAfterDrop) }
        } else if !hot, !lowPower, atNative, hold <= 0, thermal != .fair {   // only at full resolution: never trade resolution for Hz
            underT = ms < Self.upBelowMs ? underT + dt : 0
            if underT >= Self.upAfter { return set(120, hold: 0) }
        }
        return nil
    }

    private mutating func set(_ f: Int, hold h: Double) -> Int {
        fps = f; hold = h; underT = 0; overT = 0; smoothed = nil
        return f
    }
}
