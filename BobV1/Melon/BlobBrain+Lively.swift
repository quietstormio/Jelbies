//
//  BlobBrain+Lively.swift
//  Liveliness round (W2, 2026-10-22: "too much walk-stop-walk"): four more things to do, all body-led (the arms stay thumbs, the feet stay under him):
//    shake      a wet-dog wiggle on the spot
//    lieDown    flops flat on the floor, lies there a few seconds, pushes back up (NOT the sleep: no sleep code, no "lie down" voice word)
//    chirp      a little perk-up and a chirp (AudioHub only through `chirp(jelly:)`)
//    cartwheel  a sideways airborne turn over his side, landing ~0.8 u across on both feet (GaitDriver.cartwheel: the flip's machinery about the forward axis)
//  plus the window antic that now walks to the window before it looks out.
//

import Foundation
import simd

extension BlobBrain {
    // MARK: window

    /// Window centres (x) on the back wall of the room the Jellies are in. (W5: point this at the current room.)
    nonisolated(unsafe) static var windowXs: () -> [Float] = { RoomGeometry.windowXs }

    /// Where he stands to look out of a window: just in front of it at the back of the floor. Nearest window first; nil = none reachable (he looks from where he is).
    func windowSpot(from here: SIMD2<Float>) -> (spot: SIMD2<Float>, wx: Float)? {
        let xs = Self.windowXs().sorted { abs($0 - here.x) < abs($1 - here.x) }
        for wx in xs {
            for pull: Float in [0, 0.6, 1.2] {
                let rx = wx - (wx > 0 ? pull : (wx < 0 ? -pull : 0))
                let raw = SIMD2(rx, GameCamera.roamMinZ + 0.35)
                let q = fixed(raw)
                if simd_distance(q, raw) < 0.7, simd_distance(here, q) > 0.8, peerFree(q), reachable(here, q) { return (q, wx) }
            }
        }
        return nil
    }

    // MARK: starts

    /// Shake / lie down / chirp, from standing (`resume` nil) or in the middle of a walk. False = not possible now.
    func livelyStart(_ kind: IdleKind, _ sim: SoftBody, resume: SIMD2<Float>?) -> Bool {
        idleBegin(kind)
        idleState.resume = resume
        script = .idle
        switch kind {
        case .shake:
            activity = .playing
        case .lieDown:
            idleState.goalYaw = faceCameraYaw() + idleState.sign * rand(0.5, 0.9)
            idleState.hold = rand(3, 5.5)
            activity = .lookingAround
        default:       // chirp: turns toward a friend within 4 u first
            activity = .lookingAround
            idleState.goalYaw = yaw
            if let f = socialOthers().filter({ $0 !== self && simd_distance($0.position, position) < 4 && $0.idleState.kind != .sleep }).min(by: { simd_distance($0.position, position) < simd_distance($1.position, position) }) {
                idleState.goalYaw = clampedLook(yawTo(f.position))
            }
        }
        return true
    }

    // MARK: shake

    func runShake(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let t = idleState.phaseT
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        if idleState.phase == 0 {
            idleState.phase = 1
            AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.6)
            face(idleMood == .grumpy ? .grumpy : .joyArc, hold: 1.3)
        }
        let crouch = smooth01(t / 0.15) * (1 - smooth01((t - 1.25) / 0.2))
        squash *= 1 - 0.06 * crouch
        if t > 0.15 {
            let s = t - 0.15
            let env = max(0, sinf(.pi * min(1.1, s) / 1.1))
            twist = 0.26 * env * sinf(2 * .pi * 7.5 * s)
            roll += 0.05 * env * sinf(2 * .pi * 7.5 * s + 0.6)
            squash *= 1 - 0.05 * env * (0.5 - 0.5 * cosf(2 * .pi * 15 * s))
        }
        armWalkWant = 1
        if idleState.phase == 1, t > 1.25 { idleState.phase = 2; jellyKick = max(jellyKick, 2.4) }
        if t > 1.6 && !feet.active { twist = 0; idleFinish(skinner) }
    }

    // MARK: chirp

    func runChirp(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        // phase 0: turn toward the friend (or nothing to turn to), phase 1: the perk-up
        if idleState.phase == 0 {
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.1)
            gaitPose(sway: 0.04, bob: 0, rock: 0.2)
            if turning || feet.active { idleState.phaseT = 0; return }
            idleState.phase = 1; idleState.phaseT = 0
            AudioHub.shared.chirp(jelly: steerID, .happy, x: px)
            face(rand() < 0.5 ? .curious : .happy, hold: 1.0)
        }
        let t = idleState.phaseT
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        let env = max(0, sinf(.pi * min(1, t / 0.9)))
        pitch -= 0.07 * env
        squash *= 1 + 0.05 * env
        mouthOpen = t < 0.25 ? 0.35 : 0
        armWalkWant = 1
        if t > 0.9 && !feet.active { idleFinish(skinner) }
    }

    // MARK: lie down

    func runLieDown(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        var k = idleState.k
        let phT = idleState.phaseT
        if idleState.yielding {
            idleState.yieldT += dt
            k = max(0, k - dt / 0.2)
            if k <= 0.001 { idleState.k = 0; lieDownPose(skinner, 0); idleFinish(skinner); return }
        } else {
            switch idleState.phase {
            case 0:     // turn to the lying direction
                let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
                if !turning && !feet.active { idleState.phase = 1; idleState.phaseT = 0 }
            case 1:     // the plop
                k = smooth01(phT / 0.35)
                if k >= 0.9, idleState.steps == 0 { idleState.steps = 1; jellyKick = max(jellyKick, 2.4); AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.7) }
                if phT >= 0.35 { idleState.phase = 2; idleState.phaseT = 0; face(idleMood == .okay ? .sleepy : .happy, hold: idleState.hold + 0.4) }
            case 2:     // lie there
                k = 1
                if phT >= idleState.hold { idleState.phase = 3; idleState.phaseT = 0 }
            default:    // the push-up, an ease-out with a little stretch overshoot
                let u = min(1, phT / 0.6)
                k = 1 - (1 - (1 - u) * (1 - u))
                if u >= 1 {
                    idleState.k = 0; lieDownPose(skinner, 0)
                    jellyKick = max(jellyKick, 1.6)
                    idleFinish(skinner); return
                }
            }
        }
        idleState.k = k
        // the feet stay under him
        if k > 0 || idleState.phase >= 1 {
            for s in 0..<2 {
                let nominal = SIMD2(px, pz) + rotXZ(geom.off[s], yaw)
                feet.pos[s] += (nominal - feet.pos[s]) * min(1, dt / 0.07)
            }
        }
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        lieDownPose(skinner, k)
    }

    func lieDownPose(_ skinner: Skinner, _ k: Float) {
        let t = idleState.t
        let side = idleState.sign
        var kk = k
        var stretch: Float = 1
        if idleState.phase == 3 && !idleState.yielding { let u = min(1, idleState.phaseT / 0.6); stretch = 1 + 0.06 * sinf(.pi * smooth01(max(0, (u - 0.6) / 0.4))); kk = k }
        squash *= (1 - 0.38 * kk) * stretch          // (backed off from 0.40 / 0.26 / 0.34 toward the flop's tested 0.36 / 0.20 / 0.30: FeetAttachTests read a sole rise of 0.125 u with those)
        pitch += 0.21 * kk
        roll += side * 0.30 * kk
        if idleState.phase == 2 {
            squash *= 1 + 0.012 * sinf(2 * .pi * 0.35 * t) * kk
            let win = max(0, sinf(2 * .pi * t / 1.6))
            roll += 0.04 * sinf(2 * .pi * 2.2 * t) * win * kk
        }
        skinner.setEyeOpenness(1 - 0.55 * kk)
    }

    // MARK: cartwheel

    static let cartwheelApex: Float = 0.34

    /// Start attempts and refusals by reason (diagnostics: a minute of the 3-Jelly room logs them, LivelinessMinuteTests).
    static var cartwheelStats = (tried: 0, floor: 0, leg: 0, peer: 0, started: 0)
    /// Travels tried in turn: the full cartwheel, then shorter ones when a wall, a piece of furniture or a Jelly is in the way.
    static var cartwheelTravels: [Float] = [0.8, 0.6, 0.45]

    /// Where a cartwheel toward `side` (+1 right / -1 left of `yawNow`) would land and how far it travels, or nil when it has no room even for the shortest.
    func cartwheelLanding(side: Float, yawNow: Float, from here: SIMD2<Float>, count: Bool = false) -> (to: SIMD2<Float>, travel: Float)? {
        let right = SIMD2<Float>(cosf(yawNow), -sinf(yawNow))
        var why = 0
        for travel in Self.cartwheelTravels {
            let raw = here + right * side * travel
            let to = fixed(raw)
            if simd_distance(to, raw) >= 0.1 { why = max(why, 1); continue }
            if !legClear(here, to, margin: steerMargin) { why = max(why, 2); continue }
            if !peerFree(to) { why = max(why, 3); continue }
            return (to, travel)
        }
        if count { if why == 1 { Self.cartwheelStats.floor += 1 } else if why == 2 { Self.cartwheelStats.leg += 1 } else { Self.cartwheelStats.peer += 1 } }
        return nil
    }

    /// A cartwheel from standing (`resume` nil: he turns to the camera first, so it reads side-on) or in the middle of a walk (to the side of the leg, no turn).
    func cartwheelStart(_ sim: SoftBody, resume: SIMD2<Float>?) -> Bool {
        let here = position
        let yawFor = resume == nil ? faceCameraYaw() : yaw
        var side: Float = idleState.kind == nil ? (rand() < 0.5 ? -1 : 1) : 1
        Self.cartwheelStats.tried += 1
        if cartwheelLanding(side: side, yawNow: yawFor, from: here) == nil {
            side = -side
            if cartwheelLanding(side: side, yawNow: yawFor, from: here, count: true) == nil { return false }
        }
        Self.cartwheelStats.started += 1
        idleBegin(.cartwheel)
        idleState.resume = resume
        idleState.sign = side
        idleState.goalYaw = yawFor
        script = .idle; activity = .playing
        if resume != nil { cartwheelLaunch(sim) }
        return true
    }

    /// The turn to the camera before the launch (phase 0 of the idle script).
    func runCartwheelTurn(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard idleState.phase == 0 else { return }
        let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        if turning || feet.active { return }
        if cartwheelLanding(side: idleState.sign, yawNow: yaw, from: position) == nil {
            let other = -idleState.sign
            if cartwheelLanding(side: other, yawNow: yaw, from: position) != nil { idleState.sign = other } else { idleFinish(skinner); return }
        }
        cartwheelLaunch(sim)
    }

    func cartwheelLaunch(_ sim: SoftBody) {
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.7)
        postEvent(.joyJump)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false; walkFinal = false; route = []
        gait.wander = false
        gait.facingYaw = yaw
        gait.home = position
        poseW = 0; poseOn = false
        flipArmA = 0
        let travel = cartwheelLanding(side: idleState.sign, yawNow: yaw, from: position)?.travel ?? Self.cartwheelTravels.last!
        gait.cartwheel(sim, apex: Self.cartwheelApex, side: idleState.sign, travel: travel, reduceMotion: amplitude < 0.7)
        idleState.phase = 1; idleState.phaseT = 0; idleState.landT = 0
        idleState.hop = 0
        script = .idle; activity = .playing
    }

    /// The cartwheel's flight (the hop machinery owns the body, like the flip): arms up as thumbs throughout, a kick at the landing.
    func cartwheelBodyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        activity = .playing
        mouthOpen = 0
        idleState.phaseT += dt
        let goal = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, goal - pitchBase))
        gait.basePitch = pitchBase
        let before = gait.phase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        if before == .air && gait.phase == .land {
            jellyKick = max(jellyKick, 2.4)
            AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.6)
            if rand() < 0.4 { AudioHub.shared.chirp(jelly: steerID, .happy, x: px) }
        }
        flipArmA += max(-dt / 0.10, min(dt / 0.10, 1 - flipArmA))
        armWalkWant = 1
        armDirW = smooth01(flipArmA)
        armDirEl = [0.95, 0.95]; armDirSa = [0.10, 0.10]; armDirOut = 0.07
        driveBeansRigid(sim, skinner, dt, tuck: gait.tuck, force: gait.phase == .air || gait.phase == .land)
        driveArms(sim, skinner, dt)
        if !gait.isBusy {
            gait.basePitch = 0
            currentPose(sim)
            armDirW = 0; armDirOut = 0; flipArmA = 0
            idleFinish(skinner)
        }
        return true
    }
}
