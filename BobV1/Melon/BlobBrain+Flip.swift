//
//  BlobBrain+Flip.swift
//  The voice backflip (replaces "yawn" as a trick; the yawn stays an idle behaviour). Built on the hop machinery (GaitDriver `.flip`):
//  crouch 0.16 s (squash, arms down) -> launch -> air (apex 0.42 u roaming / 0.28 u in focus, hop gravity 12.4 u/s^2, so 0.52 s / 0.43 s)
//  with ONE full backward pitch about his centre of mass (slow-fast-slow, arms out) -> both feet land together: big squash, a rebound and the
//  JellyJiggle landing wobble -> a 0.35 s "covers it" shake -> exact rest. No horizontal travel. Locked body / face / walk are untouched; the
//  move only writes the attractor (Locomotion.swift), the arm override and the rigid foot beans, like the jumping jacks.
//

import Foundation
import simd

extension BlobBrain {
    static let flipApexRoam: Float = 0.42
    static let flipApexFocus: Float = 0.28

    /// One backflip now (crouch -> flip -> land, no player input). `fail` = the funny faceplant instead of the clean landing.
    func startFlip(sim: SoftBody, compact: Bool = false, fail: Bool = false) {
        // the root / heading he already has are kept (currentPose would re-seed the root from the centroid, which sits behind the root while he
        // holds the idle tip-back, and the idle pose would then shift him that far again after the flip)
        let keep = (px, pz, yaw)
        currentPose(sim)
        (px, pz, yaw) = keep
        flipRoot = SIMD3(keep.0, keep.1, keep.2)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        gait.facingYaw = yaw
        gait.home = SIMD2(px, pz)
        poseW = 0
        flipArmA = 0
        flipEl = 0; flipSa = 0; flipOut = 0
        gait.flip(sim, apex: compact ? Self.flipApexFocus : Self.flipApexRoam, reduceMotion: amplitude < 0.7, fail: fail)
        script = .flipPlay; activity = .playing
    }

    /// Voice / trick book: stop whatever he is doing and flip (or faceplant when `commandedFlipFail`).
    func startCommandedFlip(_ sim: SoftBody, _ skinner: Skinner) {
        var busy = idleState.kind != nil
        if case .none = script {} else { busy = true }
        if busy { abortAll(sim, skinner) }
        pending = nil
        restTimer = max(restTimer, 1)
        let fail = commandedFlipFail
        commandedFlipFail = false
        startFlip(sim: sim, compact: flipCompact, fail: fail)
    }

    /// Voice: his learned name. Stop whatever he is doing and perk up with one in-place hop (apex `nameHopApex`, a little higher than the idle hop).
    static let nameHopApex: Float = 0.20
    /// Capture aid (`-VoiceSlow 4`): the name hop's airtime is stretched N times (the apex and everything else are unchanged).
    static let nameHopSlow: Float = {
        let s = Float(UserDefaults.standard.double(forKey: "VoiceSlow"))
        return s > 1 ? s : 1
    }()
    func startNameHop(_ sim: SoftBody, _ skinner: Skinner) {
        var busy = idleState.kind != nil
        if case .none = script {} else { busy = true }
        if busy { abortAll(sim, skinner) }
        pending = nil
        restTimer = max(restTimer, 1)
        gait.hopDuration = GaitDriver.flipAir(apex: Self.nameHopApex) * Self.nameHopSlow      // 0.36 s: ballistic under the hop's gravity
        gait.hopApex = Self.nameHopApex                            // read while the air phase runs: restored by `nameHopDone`
        startHopPlay(sim: sim, distance: 0.0001)
        nameHopping = true
    }
    /// Restores the idle hop's apex once the name hop is over (called by the coordinator).
    func nameHopDone() { if nameHopping { nameHopping = false; gait.hopApex = 0.10; gait.hopDuration = 0.26 } }

    /// Arm targets (el, sa in rad; out) for the flip's phases: swing BACK in the crouch, the forward-and-up "throw" at take-off, tucked through
    /// the fast part of the turn, open before landing. The arm keeps its stub length (only the direction turns). Returns (el, sa, out, tau, weight).
    func flipArmTarget() -> (el: Float, sa: Float, out: Float, tau: Float, w: Float) {
        let g = gait
        switch g.phase {
        case .crouch:
            return (-0.30, -1.15, 0.04, 0.05, 1)                                       // wound up: arms swung back
        case .air:
            let u = g.flipU, v = g.flipV
            if u < 0.16 { return (1.15, 0.85, 0.06, 0.035, 1) }                       // the throw, timed with take-off
            if g.isFlipFaceplant && v > 0.62 { return (0.95, 0.35, 0.10, 0.06, 1) }   // flailing: he knows it is short
            if u < 0.80 { return (0.15, 0.55, 0.0, 0.05, 1) }                         // tucked in through the fast part
            return (0.55, 0.20, 0.10, 0.05, 1)                                         // open to balance for the landing
        case .land:
            let t = g.flipLandT
            if g.isFlipFaceplant {
                if t < GaitDriver.fpImpact + 0.1 { return (0.90, 0.30, 0.10, 0.04, 1) }
                if t < GaitDriver.fpLieEnd {
                    // lies there; the arms flop once (up and over, then slack)
                    let s = t - (GaitDriver.fpImpact + 0.1)
                    if s < 0.12 { return (1.0, 0.25, 0.12, 0.05, 1) }
                    return (-0.25, -0.15, 0.03, 0.07, 1)
                }
                if t < GaitDriver.fpPeelEnd { return (-0.45, -0.25, 0.04, 0.08, 1) }     // short arms push down behind the body-led peel
                let s = t - GaitDriver.fpPeelEnd                                          // brush-off: a quick dusting pat, then down
                if s < 0.22 { return (0.55 + 0.25 * sinf(2 * .pi * 6 * s), 0.35, 0.06, 0.04, 1) }
                return (0.3, 0, 0, 0.08, 0)
            }
            if t < 0.15 { return (0.30, 0.10, 0.07, 0.05, 1) }
            return (0.30, 0.10, 0.05, 0.08, 0)
        default:
            return (0.3, 0.1, 0.05, 0.08, 0)
        }
    }

    /// Ticked from `tick` before the generic script pass; true = the flip owns this step.
    func flipTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard case .flipPlay = script else { return false }
        activity = .playing
        mouthOpen = 0
        let goal = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, goal - pitchBase))
        gait.basePitch = pitchBase
        let before = gait.phase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        let tookOff = before == .crouch && gait.phase == .air
        let landed = before == .air && gait.phase == .land
        let plant = landed && gait.isFlipFaceplant
        noteFlipBeats(tookOff, landed && !plant)
        if plant { noteFaceplant(); jellyKick = 2.6 }
        // arms: back in the crouch, the throw at take-off, tucked / open in the air (smoothed, stubby: only the direction turns)
        let tg = flipArmTarget()
        let k = 1 - expf(-dt / max(tg.tau, 1e-3))
        flipEl += (tg.el - flipEl) * k; flipSa += (tg.sa - flipSa) * k; flipOut += (tg.out - flipOut) * k
        flipArmA += max(-dt / 0.10, min(dt / 0.10, tg.w - flipArmA))
        armWalkWant = 1
        armDirW = smooth01(flipArmA)
        armDirEl = [flipEl, flipEl]; armDirSa = [flipSa, flipSa]; armDirOut = flipOut
        driveBeansRigid(sim, skinner, dt, tuck: gait.tuck)
        driveArms(sim, skinner, dt)
        if !gait.isBusy {
            gait.basePitch = 0
            currentPose(sim)
            px = flipRoot.x; pz = flipRoot.y; yaw = flipRoot.z
            armDirW = 0; armDirOut = 0; flipArmA = 0
            finishScript(sim, after: false)
        }
        return true
    }
}
