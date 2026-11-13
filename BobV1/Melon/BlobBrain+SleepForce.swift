//
//  BlobBrain+SleepForce.swift
//  A bedtime always works (W1, round 1022): the last-resort floor spot for a Jelly who must lie down even in a full room, and the instant
//  "already asleep" arrival used when the player comes back at night after a long time away.
//

import Foundation
import simd

extension BlobBrain {
    /// The nearest point on a 0.25 grid that he can stand on, that is clear of decor and of the others (asleep or not), and that he can reach.
    func forceSpot() -> SIMD2<Float>? {
        let L = RoomLayout.self
        var cands: [(SIMD2<Float>, Float)] = []
        var x: Float = -3.2
        while x <= 3.2001 {
            var z: Float = -2.6
            while z <= 2.8001 {
                let p = SIMD2<Float>(x, z)
                z += 0.25
                guard simd_distance(fixed(p), p) < 0.12,
                      L.decorDistance(p, solidOnly: true) > 0.3, L.decorDistance(p) > 0.05 else { continue }
                var clash = false
                for o in socialOthers() where o !== self {
                    if simd_distance(o.position, p) < SleepTuning.minGap { clash = true; break }
                    if o.idleState.kind == .sleep, simd_distance(o.sleep.spot, p) < SleepTuning.minGap || Self.lieClash(p - o.sleep.spot, yawA: faceCameraYaw(), yawB: o.sleep.lieYaw) { clash = true; break }
                }
                if !clash { cands.append((p, simd_distance(position, p))) }
            }
            x += 0.25
        }
        cands.sort { $0.1 < $1.1 }
        for c in cands where reachable(position, c.0) { return c.0 }          // nearest first: the route is planned only until one works
        return nil
    }

    /// Asleep on his back at once, in place (no walk, no yawn, no flop squish): the player came back at night after a long time away.
    /// The next `sleepBodyTick` goes straight to stage 3.
    func sleepInstant(_ sim: SoftBody, _ skinner: Skinner) {
        idleBegin(.sleep)
        sleep = SleepState()
        sleep.force = true
        let c = chooseSleepSpot()
        var spot = c.spot
        if (!sleepFloorOK(spot, relaxed: true) && !c.joined) || sleepOverlapsOthers(spot, yaw: c.yaw), let f = forceSpot() { spot = f }
        sim.teleport(toXZ: spot)
        poseW = 0
        currentPose(sim)
        px = spot.x; pz = spot.y
        yaw = c.yaw; gait.facingYaw = yaw
        sleep.spot = spot; sleep.lieYaw = c.yaw; sleep.joined = c.joined
        if c.joined, let lead = sleepMates.min(by: { $0.steerID < $1.steerID }) {
            sleep.partner = sleepMates.min(by: { simd_distance($0.position, spot) < simd_distance($1.position, spot) }) ?? lead
        }
        sleep.hold = NightRestTuning.untilMorning
        sleep.minHold = 20
        sleep.tucked = true
        commanded = true
        script = .idle; activity = .lookingAround
        sleepToLie(sim, skinner)
        sleep.stage = 2; sleep.t = SleepTuning.lieTime; sleep.impacted = true; sleep.k = 1
    }

    /// 2026-11-12: on again, with the fixes the first version lacked (the group meal and the single flow count a meal-waking sleeper as busy, `mealWaking`; the end of the wake starts the walk in the
    /// same tick, `sleepFinish`; a call during the stretch is kept, not pending; the group's bounded fallback). Off (or `-MealOld 1` in the simulator) = every meal call is `requestNow`, exactly as
    /// before the staggered-sleep change; on = a sleeper is woken softly (stir, roll up, stretch) and then walks to the tray.
    nonisolated(unsafe) static var softMealWake = true

    /// True while the meal's soft wake is in hand: he is "busy" to every idle check of the tray (his `activity` can read idle for a tick between two wake stages).
    var mealWaking: Bool { idleState.kind == .sleep && sleep.mealWake }
    /// The soft path is on for this process (the flag, and not the simulator's `-MealOld 1` A/B switch).
    static var softMealWakeOn: Bool { softMealWake && !MealTrace.oldFlow }

    /// The meal tray's call (`DiningGroup.beginApproach`, `GameCare.serveWanted`): a Jelbie lying asleep is NOT hard-aborted (`requestNow` would snap him up and walking). The request just waits (`request`), the gentle wake
    /// (BlobBrain+Idle: yielding + `sleepWake(fast: true)`) sees `mealWake` and gives the soft, staggered wake: stir, roll up, stretch, then the walk to the tray. During the stretch the call is kept in `sleep.mealCall`
    /// (a pending request there would abort the stretch). Everybody else: `requestNow`, as before. The soft path only runs when `softMealWake` is on.
    func callToMeal(_ r: BlobRequest) {
        if Self.softMealWakeOn, idleState.kind == .sleep, sleep.stage >= 2, sleep.stage <= 5 {
            if !sleep.mealWake { sleep.mealWake = true; sleep.mealWakeT = 0; MealTrace.log("meal call to sleeper jelly=\(steerID) stage=\(sleep.stage)") }
            activity = .turning
            if sleep.stage == 5 { sleep.mealCall = r } else { request(r) }
        } else { requestHard(r) }          // (the meal's own fallback must really abort; `requestNow` would be softened again)
    }
}

/// Slow wake everywhere (user 2026-11-12: "Whenever they wake up it should be slow with a yawn and stretch"): ONE tuning struct. The staged wake = lag + stir (`SleepTuning.stirTime`) + slow roll-up (`softRollTime`) + the YAWN
/// (this struct) + the groggy stretch (`softStretch`) + the half-lid look; the call that woke him starts when it ends.
enum SlowWakeTuning {
    /// The yawn beat (seconds), between the roll-up and the stretch.
    static let yawnTime: Float = 1.0
    /// How far the slow lift of the body goes in the yawn (0...1 of the stretch's lift; the stretch carries on from here), and how long it takes.
    static let yawnLift: Float = 0.5, yawnLiftTime: Float = 0.45
    /// The mouth: wide and round (as the idle yawn's 0.95), opens from `yawnMouthAt` in `yawnMouthOpenTime`, closes from `yawnMouthCloseAt` in `yawnMouthCloseTime`.
    static let yawnMouth: Float = 0.95, yawnMouthAt: Float = 0.2, yawnMouthOpenTime: Float = 0.3, yawnMouthCloseAt: Float = 0.62, yawnMouthCloseTime: Float = 0.36
    /// Eyes squeezed (extra closing on top of the lift's own).
    static let yawnEyes: Float = 0.45
    /// A slow wake of the brain's own (not a meal's) that has not finished after this many seconds ends hard: lag <= 2.8 (+0.8 per extra sleeper) + stir 1.2 + roll 1.0 + yawn 1.0 + stretch 1.75 + look 0.55 + a bed hop.
    static let cap: Float = 13
    /// The meal group's cap with the yawn in it (was 11).
    static let mealCap: Float = 12
}

extension BlobBrain {
    /// 2026-11-12: every wake is the slow one (stir, roll up, yawn, stretch), then the action that woke him starts. Off = today's wakes exactly (a tap / a request / a natural wake roll up quickly, no yawn beat).
    /// The immediate causes never change: the finger picking him up, the scene changes (`sleepWake(fast: true)`: race, volley, show, the newcomer's welcome; leaving for the park), app relaunch, every watchdog.
    nonisolated(unsafe) static var slowWakeEverywhere = true
    static var slowWakeOn: Bool { slowWakeEverywhere }

    /// Snores (and the nap music) go on while he is `isNapping`; with the slow wake they stop the moment a wake is in hand (the lag, the stir), not at the roll.
    var isSnoring: Bool { isNapping && !(Self.slowWakeOn && (sleep.slowWake || sleep.mealWake)) }

    /// `requestNow` met a sleeper (BlobBrain.swift): a lying or stretching sleeper is not hard-aborted; the call waits for the staged wake (`request` for the lying stages: `idleGate` starts the wake; the stretch keeps it in
    /// `sleep.mealCall`, a pending request there would abort the stretch). True = taken. An immediate wake in hand (`sleep.quick`), a sleeper not yet down (stages 0 and 1) and the switch off: today's hard path.
    func slowWakeCall(_ r: BlobRequest) -> Bool {
        guard Self.slowWakeOn, idleState.kind == .sleep, sleep.stage >= 2, sleep.stage <= 5, !sleep.quick else { return false }
        if sleep.mealWake { callToMeal(r); return true }
        if !sleep.slowWake { sleep.slowWake = true; sleep.mealWakeT = 0 }
        activity = .turning
        if sleep.stage == 5 { pending = nil; sleep.mealCall = r } else { request(r) }          // (a later call replaces an earlier one, as for an awake Jelbie)
        return true
    }

    /// A voice / trick command (`commandedIdle`, flip, decor, name hop) came while he sleeps: it wakes him (the slow way) and is kept until the wake ends. Called every tick from `tick`, before the commands are read.
    func slowWakeHoldCommands() {
        guard Self.slowWakeOn, idleState.kind == .sleep, sleep.stage >= 2, sleep.stage <= 5, !sleep.quick,
              commandedIdle != nil || commandedFlip || commandedDecor != nil || commandedNameHop else { return }
        sleep.heldIdle = commandedIdle ?? sleep.heldIdle; sleep.heldFlip = sleep.heldFlip || commandedFlip; sleep.heldDecor = commandedDecor ?? sleep.heldDecor; sleep.heldNameHop = sleep.heldNameHop || commandedNameHop
        commandedIdle = nil; commandedFlip = false; commandedDecor = nil; commandedNameHop = false
        if !sleep.slowWake && !sleep.mealWake { sleep.slowWake = true; sleep.mealWakeT = 0 }
        if sleep.stage <= 4, !sleep.wakeAsked, sleep.stirT < 0 { sleepWake(groggy: false, slow: true) }
    }

    /// The brain's own bound on a slow wake: past `SlowWakeTuning.cap` seconds the wake ends hard (the sleep is aborted), and the call that woke him is handed back as a plain pending request.
    func slowWakeFallback(_ sim: SoftBody, _ skinner: Skinner) {
        MealTrace.log("slow wake FALLBACK jelly=\(steerID) after \(sleep.mealWakeT) s stage \(sleep.stage)")
        let call = pending ?? sleep.mealCall
        let held = (sleep.heldIdle, sleep.heldFlip, sleep.heldDecor, sleep.heldNameHop)
        sleep.slowWake = false; sleep.mealCall = nil; sleep.heldIdle = nil; sleep.heldFlip = false; sleep.heldDecor = nil; sleep.heldNameHop = false
        abortAll(sim, skinner)
        commandedIdle = held.0 ?? commandedIdle; commandedFlip = commandedFlip || held.1; commandedDecor = held.2 ?? commandedDecor; commandedNameHop = commandedNameHop || held.3
        if let r = call { pending = r }
    }
}
