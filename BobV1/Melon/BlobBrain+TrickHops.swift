//
//  BlobBrain+TrickHops.swift
//  The Shop tricks that ride the gait driver's hop / flip (trick plan, stage 2). They are trick-only IdleKinds: never in the idle / treat tables, only started by a command
//  (voice, the Show, the Tricks button). Phase 0 turns to the camera (runIdle); phase 1 is the jump (the gait driver owns the body, ticked from `idleBodyMoveTick` like the
//  jumping jacks); phase 2 (corkscrew only) is the ta-da back in pose mode.
//
//  CORKSCREW     the backflip's machinery (crouch, ballistic air, big landing squash and shake) with the turn about the VERTICAL axis (GaitDriver.flipTwist): one full twist in
//                the air, landing on the heading he left, then a held ta-da. The Show's flop: 1.5 turns, he lands sideways and goes dizzy.
//  SUPER SPRING  the squash goes very low (crouchDepth 0.30) and is HELD with a tremble, then a launch about twice the bounce's height (apex 0.24 u), arms thrown up, a long
//                stretch, a big landing squash (landDepth 0.28) with a big jelly kick, a beat, and a small rebound hop. The Show's flop: the same crouch, a weak hop, a forward
//                lurch on landing.
//  CORKSCREW     the backflip's machinery (crouch, ballistic air, big landing squash and shake) with the turn about the VERTICAL axis (GaitDriver.flipTwist): one full twist in
//                the air, landing on the heading he left, then a held ta-da. The Show's flop: 1.5 turns, he lands sideways and goes dizzy.
//

import Foundation
import simd

nonisolated enum SpringTuning {
    static let apex: Float = 0.24, apexCompact: Float = 0.16, failApex: Float = 0.07
    static let crouchDepth: Float = 0.27, crouchHold: Float = 0.25, airStretch: Float = 0.15, landDepth: Float = 0.30
    /// Seconds into the landing at which the rebound hop starts (the big squash and its jiggle show first), and the rebound's apex.
    static let beat: Float = 0.38, reboundApex: Float = 0.05
    static let kick: Float = 3.2, failKick: Float = 2.4
    /// The flop's forward lurch (rad) and when it peaks / is gone (seconds into the landing).
    static let lurch: Float = 0.40
    /// Seconds of the whole jump (not counting the turn): crouch + hold, air, the landing beat, the rebound.
    static var total: Float {
        let crouch = 0.13 + crouchHold, air = GaitDriver.flipAir(apex: apex)
        let rebound = 0.13 + GaitDriver.flipAir(apex: reboundApex) + 0.55
        return crouch + air + beat + rebound
    }
}

nonisolated enum CorkscrewTuning {
    static let apex: Float = 0.32, apexCompact: Float = 0.22
    static let crouchHold: Float = 0.14
    static let twist: Float = 2 * .pi, failTwist: Float = 1.5 * .pi
    static let kick: Float = 2.6
    /// The held ta-da after the landing (seconds).
    static let tada: Float = 0.45
    static var total: Float {
        let g = GaitDriver()
        return g.flipCrouch + crouchHold + GaitDriver.flipAir(apex: apex) + g.flipSquashTime + g.flipSettle + tada
    }
}

extension BlobBrain {
    func trickArms(_ tg: (el: Float, sa: Float, out: Float, tau: Float, w: Float), _ dt: Float) {
        let k = 1 - expf(-dt / max(tg.tau, 1e-3))
        idleState.trick.el += (tg.el - idleState.trick.el) * k
        idleState.trick.sa += (tg.sa - idleState.trick.sa) * k
        idleState.trick.out += (tg.out - idleState.trick.out) * k
        idleState.trick.armA += max(-dt / 0.10, min(dt / 0.10, tg.w - idleState.trick.armA))
        armWalkWant = 1
        armDirW = smooth01(idleState.trick.armA)
        armDirEl = [idleState.trick.el, idleState.trick.el]; armDirSa = [idleState.trick.sa, idleState.trick.sa]; armDirOut = idleState.trick.out
    }

    /// Phase 0 of both jumps (from `runIdle`): square to the camera, arms at rest, then the jump begins.
    func runTrickHopTurn(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard idleState.phase == 0 else { return }
        let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
        gaitPose(sway: 0.04, bob: 0.02, rock: 0.3)
        armWalkWant = 0
        if turning || feet.active { idleState.phaseT = 0; return }
        if idleState.phaseT > 0.25 { trickJumpLaunch(sim) }
    }

    /// The jump starts: the feet and the root are handed over to the gait driver (as the flip / the jacks do).
    private func trickJumpLaunch(_ sim: SoftBody) {
        let keep = (px, pz, yaw)
        currentPose(sim)
        (px, pz, yaw) = keep
        idleState.trick.root = SIMD3(keep.0, keep.1, keep.2)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        gait.facingYaw = yaw
        let pose = sim.bodyPose(iterations: 6)
        gait.home = SIMD2(px, pz)
        poseW = 0; poseOn = false
        idleState.phase = 1; idleState.phaseT = 0; idleState.landT = 0; idleState.trick.stage = 0
        idleState.trick.el = -0.30; idleState.trick.sa = -1.15; idleState.trick.out = 0.04; idleState.trick.armA = 0
        let fail = idleState.trick.fail
        if idleState.kind == .superSpring {
            gait.crouchDepth = SpringTuning.crouchDepth; gait.crouchHold = SpringTuning.crouchHold
            gait.airStretch = SpringTuning.airStretch; gait.landDepth = SpringTuning.landDepth
            let apex = fail ? SpringTuning.failApex : (flipCompact ? SpringTuning.apexCompact : SpringTuning.apex)
            gait.hopApex = apex; gait.hopDuration = GaitDriver.flipAir(apex: apex)
            gait.hop(sim, to: SIMD2(pose.centroid.x, pose.centroid.z), reduceMotion: amplitude < 0.7)
            face(.excited, hold: SpringTuning.crouchHold + 0.4)
        } else {
            gait.crouchHold = CorkscrewTuning.crouchHold
            gait.flipTwist = fail ? CorkscrewTuning.failTwist : CorkscrewTuning.twist
            gait.flip(sim, apex: flipCompact ? CorkscrewTuning.apexCompact : CorkscrewTuning.apex, reduceMotion: amplitude < 0.7, fail: false)          // (not the gait's faceplant: the flop is the short twist)
            face(.excited, hold: 0.5)
        }
    }

    /// Ticked from `idleBodyMoveTick`: true = the jump owns this step.
    func trickBodyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard let kind = idleState.kind, kind == .superSpring || kind == .corkscrew, idleState.phase == 1, case .idle = script else { return false }
        activity = .playing
        mouthOpen = 0
        idleState.phaseT += dt
        let fail = idleState.trick.fail
        let hopGoal = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        gait.basePitch = pitchBase
        if gait.twistNow != 0 { idleState.trick.twist = gait.twistNow }
        let before = gait.phase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        let tookOff = before == .crouch && gait.phase == .air
        let landed = before == .air && gait.phase == .land
        noteFlipBeats(tookOff, landed)
        if gait.phase == .land { idleState.landT += dt } else if gait.phase != .idle { idleState.landT = 0 }
        let a = amplitude
        if kind == .superSpring {
            // the held crouch trembles (the spring is wound), the launch throws the arms up, the landing is a big squash and a bigger jelly kick
            if gait.phase == .crouch, idleState.phaseT > 0.13 { sim.attractor.squash *= 1 + 0.015 * a * sinf(2 * .pi * 15 * idleState.phaseT) }
            if landed {
                if idleState.trick.stage == 0 { jellyKick = max(jellyKick, fail ? SpringTuning.failKick : SpringTuning.kick); face(fail ? .worried : .joyArc, hold: 1.4) }
                else { jellyKick = max(jellyKick, 0.8) }
            }
            if tookOff, idleState.trick.stage == 0 { AudioHub.shared.chirp(jelly: steerID, fail ? .uhoh : .wheee, x: px) }
            var tg: (el: Float, sa: Float, out: Float, tau: Float, w: Float)
            switch gait.phase {
            case .crouch: tg = (-0.30, -1.15, 0.04, 0.05, 1)
            case .air: tg = fail ? (0.95, 0.35, 0.10, 0.06, 1) : (0.95, 0.10, 0.07, 0.035, 1)
            case .land: tg = idleState.landT < 0.25 ? (0.90, 0.20, 0.08, 0.05, 1) : (0.30, 0.10, 0.05, 0.08, 0)
            default: tg = (0.3, 0.1, 0.05, 0.08, 0)
            }
            trickArms(tg, dt)
            if fail, gait.phase == .land {
                // the lurch: he lands off balance, tips forward and rights himself
                let u = idleState.landT
                gait.basePitch = pitchBase + SpringTuning.lurch * a * smooth01(u / 0.12) * (1 - smooth01((u - 0.28) / 0.3))
                let wob = 0.16 * expf(-u / 0.35) * sinf(2 * .pi * 3 * u) * a          // (and sways, so the stumble reads from the front too)
                sim.attractor.rotation = simd_quatf(angle: wob, axis: SIMD3<Float>(0, 0, 1)) * sim.attractor.rotation
            }
            // the beat, then the small rebound (the clean one only)
            if !fail, idleState.trick.stage == 0, gait.phase == .land, idleState.landT >= SpringTuning.beat {
                idleState.trick.stage = 1
                gait.crouchDepth = 0.18; gait.crouchHold = 0; gait.airStretch = 0.12; gait.landDepth = 0.2
                gait.hopApex = SpringTuning.reboundApex; gait.hopDuration = GaitDriver.flipAir(apex: SpringTuning.reboundApex)
                let p = sim.bodyPose(iterations: 3)
                gait.hop(sim, to: SIMD2(p.centroid.x, p.centroid.z), reduceMotion: amplitude < 0.7, chained: false)
            }
            driveBeansRigid(sim, skinner, dt, tuck: gait.tuck)
            driveArms(sim, skinner, dt)
            if !gait.isBusy { trickJumpEnd(sim, skinner) }
            return true
        }
        // corkscrew: the flip's arms, the flip's beans (forced through isSpinMove), a kick on the landing
        if landed { jellyKick = max(jellyKick, CorkscrewTuning.kick); face(fail ? .oh : .joyArc, hold: 1.0) }
        if tookOff { AudioHub.shared.chirp(jelly: steerID, fail ? .uhoh : .wheee, x: px) }
        trickArms(flipArmTarget(), dt)
        driveBeansRigid(sim, skinner, dt, tuck: gait.tuck, force: gait.phase == .air || gait.phase == .land)
        driveArms(sim, skinner, dt)
        if !gait.isBusy { trickJumpEnd(sim, skinner) }
        return true
    }

    /// The jump is over: root and heading back to where he took off (a short twist leaves him turned), the clean corkscrew goes on to its ta-da, the flop to the dizzy wobble.
    private func trickJumpEnd(_ sim: SoftBody, _ skinner: Skinner) {
        gait.basePitch = 0
        let kind = idleState.kind
        let root = idleState.trick.root
        currentPose(sim)
        px = root.x; pz = root.y
        let fail = idleState.trick.fail
        yaw = (kind == .corkscrew && fail) ? wrapAngle(root.z + idleState.trick.twist) : root.z          // (a short twist leaves him turned)
        armDirW = 0; armDirOut = 0; idleState.trick.armA = 0
        if kind == .corkscrew, fail { trickDizzyFollow(sim, reseed: false); return }          // the flop: he lands sideways and goes dizzy
        if kind == .corkscrew { idleState.phase = 2; idleState.phaseT = 0; return }          // the ta-da (pose mode: runCorkscrewTada)
        idleFinish(skinner)
    }

    /// Phase 2 of the corkscrew (from `runIdle`, pose mode): the held ta-da.
    func runCorkscrewTada(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let t = idleState.phaseT
        armWalkWant = 0
        let k = smooth01(t / 0.12) * (1 - smooth01((t - (CorkscrewTuning.tada - 0.15)) / 0.15))
        squash *= 1 + 0.05 * k * amplitude
        armDirW = k; armDirEl = [0.95, 0.95]; armDirSa = [0.2, -0.2]; armDirOut = 0.07
        if t > 0.1, idleState.steps & 1 == 0 { idleState.steps |= 1; face(.joyArc, hold: 0.9); blushBump(hold: 1.4, peak: 0.4) }
        if t > CorkscrewTuning.tada, !feet.active { armDirW = 0; armDirOut = 0; idleFinish(skinner) }
    }
}
