//
//  RacePull.swift
//  Jelly Circuit, the pull-back-and-release hop control (stage A: the headless model only).
//
//  The player pulls back and lets go: one hop. A pull in the green zone is a "perfect" hop, one past it is "over" (weaker), one short of it is
//  "weak". Momentum (`vs`, in the Waddle Sprint prototype's units) carries from hop to hop, a release made in the air is remembered and fires at the
//  landing, a hurdle hit stuns. The numbers come from the prototype's physics (prototype_waddle_sprint.html lines 212-434); the conversion to this
//  game's units (`hopScale`, the stride and step rate of the racer) and the bar rules are ours.
//
//    RaceControl        which control a race uses (`.taps` = the two foot buttons, the default; `.pull` = this one).
//    RacePullTuning     every number, as an instance (the calibration test tries many values through `RaceSim.pullTuning`) + the pure functions.
//    RaceBarPass        one bar a hop passes, with its outcome decided at launch.
//
//  The state machine that uses these lives in RaceModel.swift (`// MARK: - pull control`): the sim's state is private(set).
//

import Foundation

nonisolated enum RaceControl: String, Sendable { case taps, pull }

nonisolated enum RaceHopGrade: Equatable, Sendable { case weak, perfect, over }

nonisolated enum RaceRelease: Equatable, Sendable { case ignored, buffered, hopped(RaceHopGrade) }

/// A bar a hop passes: `index` into `course.hurdles`, `u` = the fraction of the flight at which he is over its contact point, and the outcome.
nonisolated struct RaceBarPass: Equatable, Sendable {
    var index: Int
    var u: Float
    var hit: Bool
}

nonisolated struct RacePullTuning: Sendable {
    // MARK: the prototype's numbers (same names)
    var base: Float = 1.5
    var zoneA: Float = 0.70
    var zoneB: Float = 0.92
    var pullMax: Float = 1.1
    var kGround: Float = 2.4
    var kAir: Float = 0.5
    var vsMax: Float = 14
    var g: Float = 24
    var minPull: Float = 0.15
    var carry: Float = 0.35

    // MARK: ours
    /// Prototype length units -> world units, per u/s of the racer's top pace (stride x step rate). CAL.
    var hopScale: Float = 0.096
    /// No hop is longer than this (u).
    var hopCap: Float = 0.90
    /// The settle after a landing before the next hop can leave (no momentum decays inside it, a release buffered in the air waits this long).
    var landHold: Float = 0.10
    /// A hop that starts within this long of a landing re-uses the landing squash as its crouch.
    var chainWindow: Float = 0.55
    var crouchStanding: Float = 0.13
    var crouchChained: Float = 0.052
    /// A hop over a bar lands at least this far beyond its contact point / a hop that stops short stops at least `landShort` before it.
    var landBeyond: Float = 0.29
    var landShort: Float = 0.12
    /// A bar is passed at least this far into the flight (and at most 0.8).
    var uMin: Float = 0.2
    /// The arc passes the contact point at least this high (as far as `magnetApex` allows); the bar's top is `barTop`.
    var clearHeight: Float = 0.15
    var magnetApex: Float = 0.32
    var barTop: Float = 0.125
    /// How far the magnet may stretch or squash a green hop: `lo = stretchLo x L`, `hi = max(min(stretchHi x L, stretchMax), stretchFloor)`.
    var stretchLo: Float = 0.65
    var stretchHi: Float = 1.35
    var stretchMax: Float = 1.10
    var stretchFloor: Float = 0.80
    /// Trip chance scale (x the taps model's per-step chance x L / stride). CAL.
    var tripScale: Float = 1.0
    /// A rival's chance of a green pull: `rivalGreenBase + rivalGreenSkill x skill`; the auto player's is `autoGreen`.
    var rivalGreenBase: Float = 0.35
    var rivalGreenSkill: Float = 0.45
    /// Rivals' hop length scale (calibrated so their finish times match the taps race), and the Puddle's own. CAL.
    var rivalLength: Float = 1.0
    var rivalLengthPuddle: Float = 1.0
    var autoGreen: Float = 0.5

    // MARK: 1. the shot
    /// What a release at `pull` gives (the prototype's snapParams, with the green zone widened by `widen` for a perk). `streak` = perfects in a row BEFORE this hop.
    func shot(pull: Float, streak: Int, widen: Float) -> (grade: RaceHopGrade, v0: Float, vy: Float) {
        let p = min(max(pull, 0), pullMax)
        let lo = zoneA - widen, top = zoneB + 0.5 * widen
        let e: Float = 1e-5          // (float slack: 0.7 - 0.05 must still be the 0.65 pull)
        let grade: RaceHopGrade = (p >= lo - e && p <= top + e) ? .perfect : (p > top ? .over : .weak)
        let eff: Float
        switch grade {
        case .weak: eff = p
        case .perfect: eff = min(p, zoneB)
        case .over: eff = max(0.35, zoneB - (p - top) * 2.4)
        }
        let mult: Float = grade == .perfect ? 1.28 + 0.025 * Float(min(streak, 5)) : 1
        return (grade, (2.6 + 6.2 * eff) * mult, (3.3 + 3.4 * eff) * (grade == .perfect ? 1.08 : 1))
    }

    // MARK: 2. the prototype's flight
    /// Prototype flight time (s) for a take-off speed `vy`.
    func protoFlight(vy: Float) -> Float { 2 * vy / g }
    /// Prototype distance travelled in `flight` seconds from forward speed `vs0` (the prototype's sAt).
    func protoLength(vs0: Float, flight: Float) -> Float {
        base * flight + (vs0 - base) * (1 - expf(-kAir * flight)) / kAir
    }

    // MARK: 3. apex and air time
    /// Hop height (u): 0.10 at the weakest accepted pull, 0.20 in the middle of the green, about 0.22 at its top.
    func apex(vy: Float) -> Float { min(max(0.10 + 0.10 * (vy * vy - 14.5161) / 28.25, 0.08), 0.24) }
    /// Seconds in the air for an apex (0.368 s at 0.20: the same law as HurdleTuning.airTime).
    func air(apex: Float) -> Float { 0.26 * sqrtf(apex / 0.10) }

    // MARK: 5. the preview
    /// The hop length of a release now, in world units, before any bar and before the rival scale: shared by the launch and the gauge.
    func hopLength(vsLaunch: Float, flight: Float, pace: Float, slow: Bool) -> Float {
        var l = hopScale * pace * protoLength(vs0: vsLaunch, flight: flight)
        if slow { l *= HurdleTuning.slowFactor }
        return min(l, hopCap)
    }

    /// What a release would give now, bars not considered. `vs` = his momentum, `pace` = stride x step rate, `slow` = the after-a-hit slowdown is on.
    func preview(pull: Float, streak: Int, widen: Float, vs: Float, pace: Float, slow: Bool, airScale: Float = 1) -> (grade: RaceHopGrade, length: Float, apex: Float, air: Float) {
        let s = shot(pull: pull, streak: streak, widen: widen)
        let vsL = min(vsMax, carry * vs + s.v0)
        let l = hopLength(vsLaunch: vsL, flight: protoFlight(vy: s.vy), pace: pace, slow: slow)
        let a = apex(vy: s.vy)
        return (s.grade, l, a, air(apex: a) * airScale)
    }

    // MARK: 4. the magnet (a green hop passes its bars)
    /// A green hop that would reach the bar at `toBar` (distance to its CONTACT point, >= 0) is stretched or squashed so it either stops `landShort` before it or
    /// passes it well into the flight (`uMin ... 0.8`), high enough, and lands `landBeyond` beyond. `toNext` = distance to the contact point of the bar after it.
    func magnet(length l: Float, apex a: Float, toBar d: Float, toNext d2: Float?) -> (length: Float, apex: Float) {
        if l <= d - landShort { return (l, a) }
        let lo = stretchLo * l
        let hi = max(min(stretchHi * l, stretchMax), stretchFloor)
        let need = max(lo, d + landBeyond)
        let overOK = need <= hi
        let overL = overOK ? min(max(l, need), hi) : hi
        let shortL = min(l, d - landShort)
        let shortOK = d - landShort >= lo && d - landShort > 0.10
        let useOver: Bool
        if overOK && shortOK { useOver = abs(overL - l) <= abs(shortL - l) }
        else if overOK { useOver = true }
        else if shortOK { useOver = false }
        else { useOver = true }
        if !useOver { return (shortL, a) }
        var lp = overL
        var u = d / lp
        if u < uMin {
            lp = max(max(d + landBeyond, lo), min(lp, d / uMin))
            u = d / lp
        }
        // a following bar: do not land in its last `landShort` / just past it
        if let d2, lp > d2 - landShort, lp < d2 + landBeyond {
            let moved = d2 - landShort
            if moved >= d + landBeyond, moved >= lo {
                lp = moved
            } else {
                let beyond = d2 + landBeyond
                if beyond <= hi, d2 > d { lp = beyond }          // (else: leave it, the hop spans both bars)
            }
            u = d / lp
        }
        let ap = min(magnetApex, max(a, clearHeight / (4 * u * (1 - u))))
        return (lp, ap)
    }
}
