//
//  BlobBrain+WalkPolish.swift
//  walk-polish-r1 (2026-11-24). The owner: "they do walk kinda funny ... it doesn't match the way they run". The RUN is perfect and untouched; the WALK is polished toward the run's body language, at walking scale.
//  ONE launch switch, `-WalkPolish 0|1|2|3` (dev args; tests set `BlobBrain.walkPolish` directly):
//    0 = EXACTLY the locked walk (tag walk-lock-2026-11-23, fdb1acd0): none of this file's code runs.
//    1 = body: a forward lean that builds with the speed (eased in over ~0.3 s, the run's own easing), a snappy touch-down dip at each foot contact, banking into curves.
//    2 = 1 + follow-through: a lagged spring on the bob (the body and the head-top lag a few frames and overshoot on landings, as in the run) and the arms trail the stride on a spring (same
//        spring as the run's arms, the sweep a touch smaller so the nub tilt stays inside the old 22 deg limit).
//    3 = 2 + starts and stops: a small crouch-and-lean into the first steps, a settling dip into the last one.
//  Pose only: nothing here moves the root, the heading, a foot target, the step clock or `rand`, so routes, pushes, stances and meal stands cannot change.
//  The run is never touched: every effect is off (and its state reset) whenever the run blend / zoomies / trot / hurry / a play chase is on, and it uses its OWN state (`wp`), never the run's.
//  Roam walks only: no polish inside a social session, a job (meal, bath ...), a stance walk or a toss.
//

import Foundation
import simd

struct WalkPolishState {
    var w: Float = 0                  // 0...1, how much of the polish is on (eases in over 0.35 s, out over the last step)
    var walkT: Float = 0              // seconds this walk has been going
    var lastStep = -100              // `stepCounter` of the last hook call (a gap = a new walk)
    var yawPrev: Float = 0, yawRate: Float = 0
    var spring: Float = 0, springV: Float = 0
    var armS: [Float] = [0, 0], armV: [Float] = [0, 0]
    var armOn = false
}

extension BlobBrain {
    static let walkPolishDefault = 0
    /// The switch (`-WalkPolish N` honoured where dev arguments are on; the default is `walkPolishDefault`).
    nonisolated(unsafe) static var walkPolish: Int = {
        if DevArgs.enabled, UserDefaults.standard.object(forKey: "WalkPolish") != nil { return UserDefaults.standard.integer(forKey: "WalkPolish") }
        return walkPolishDefault
    }()

    /// A plain roam walk: no run-like gait, no social session, no job.
    var walkPolishAllowed: Bool {
        runW == 0 && zoomW == 0 && idleState.kind == nil && !hurry && playChase == 0 && walkPolishJobOK && social == nil && mealFinalYaw == nil && !tossBusy
    }

    /// A walk with no job, or a plain go-to / come (the meal, the sip and the other jobs are not polished).
    private var walkPolishJobOK: Bool {
        guard let j = job else { return true }
        switch j { case .goTo, .come: return true; default: return false }
    }

    private func wpSmooth(_ x: Float) -> Float { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }

    /// Called right after `gaitPose` in the `.walk` script (both calls). Adds to `roll` / `pitch` / `squash` / `lift`.
    func walkPolishPose(_ a: Float) {
        let level = Self.walkPolish
        guard level > 0 else { return }
        let dt = max(runDt, 1e-3)
        if stepCounter - wp.lastStep > 2 { wp = WalkPolishState(); wp.yawPrev = yaw }          // (a new walk starts clean)
        wp.lastStep = stepCounter
        guard walkPolishAllowed else { wp = WalkPolishState(); wp.yawPrev = yaw; return }
        wp.walkT += dt
        // yaw rate (smoothed) for banking, the same smoothing the run uses
        let dy = wrapAngle(yaw - wp.yawPrev); wp.yawPrev = yaw
        wp.yawRate += (dy / dt - wp.yawRate) * min(1, dt * 8)
        guard feet.active else { return }
        let target: Float = walkFinal ? 0 : 1
        wp.w += max(-dt / 0.22, min(dt / 0.35, target - wp.w))
        let ws = wpSmooth(wp.w)
        let speed = simd_length(stepRootD) * feet.rate          // ground speed of this step (u/s)
        let k = min(1.1, speed / 1.3) * min(1, a)
        let u = feet.stepU
        // lean forward with speed (run: 12 deg at full run)
        pitch += Self.walkLean * ws * k
        // touch-down dip: snappy at contact (the run's landing shape, a third of its depth)
        let land = powf(max(0, 1 - u / 0.2), 1.6)
        var dip: Float = -Self.walkLandDip * ws * k * land
        // banking into the turn
        roll += max(-0.045, min(0.045, wp.yawRate * 0.03)) * ws
        if level >= 3 {
            // start: a small crouch-and-lean into the first steps (the run's crouch-launch, a third of it); the last step settles
            let st = wp.walkT / 0.30
            if st < 1 { let cr = sinf(.pi * st); lift -= 0.006 * cr * a; dip -= 0.018 * cr; pitch += 0.02 * cr }
            if walkFinal { let sp = sinf(.pi * u); dip -= 0.025 * sp; pitch -= 0.025 * sp * k }
        }
        squash += dip
        if level >= 2 {
            // follow-through: a damped spring chasing the bob; the body lags a few frames and overshoots on landings, the head-top wobbles
            let tgt = (squash - 1)
            wp.springV += ((tgt - wp.spring) * 260 - wp.springV * 11) * dt
            wp.spring += wp.springV * dt
            let lag = wp.spring - tgt
            squash += lag * 0.5 * ws
            pitch += lag * 0.9 * ws
        }
    }

    nonisolated(unsafe) static var walkLean: Float = 4 * .pi / 180
    nonisolated(unsafe) static var walkLandDip: Float = 0.04

    /// The walking arm target on the run's trailing spring (level 2+), at walking scale. `tgt` = the locked walk's target (deg); returns the new one.
    func walkPolishArm(_ si: Int, _ tgt: Float, _ dt: Float) -> Float {
        guard Self.walkPolish >= 2, walkPolishAllowed, wp.w > 0, stepCounter - wp.lastStep <= 2 else { wp.armS[si] = tgt; wp.armV[si] = 0; return tgt }
        let c = ArmPath.armWalkCentreDeg
        let want = c + (tgt - c) * Self.walkArmGain
        wp.armV[si] += ((want - wp.armS[si]) * 700 - wp.armV[si] * 22) * dt
        wp.armS[si] += wp.armV[si] * dt
        let ws = wpSmooth(wp.w)
        return tgt + (wp.armS[si] - tgt) * ws
    }
    nonisolated(unsafe) static var walkArmGain: Float = 0.92
}
