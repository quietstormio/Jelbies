//
//  BlobBrain+Hopscotch.swift
//  Hopscotch on the Park's court (2026-11-04). Jelbies have short closed bean legs and cannot stride from square to square, so they HOP: a bouncy two-footed hop from each square's
//  centre to the next (the existing hop machinery of the slide's steps: `bagHop` + the gait's crouch / air / land, so the landing squash is the body's own and the feet stay
//  under him), 1, 2, 3, 4 ... 8 in order, then two happy little hops on the spot and a walk off to the side.
//    NOTICE   the first one to start posts the court as news; every free Jelbie rolls once (`HopscotchTuning.joinChance`) to join (BlobBrain+ToyPlay.swift).
//    QUEUE    a joiner walks to a spot behind square 1 (spots 1.7 apart in a fan) and waits; he steps up to the start once the one ahead is a couple of squares in.
//    SPACING  he hops to square s only when the one ahead has landed on s + 2 or later, and no one stands within a body of the landing. The line breaks up at the end because everyone
//             walks off to a different free spot as the next one comes in.
//  Stages (`idleState.slideStage`): 0 walking to the queue spot, 5 waiting / turning there, 4 stepping up to the start, 6 settled on a square (the next hop's gate),
//  1 hopping (`hopscotchBodyTick`), 3 walking off. `idleState.slideStep` is the square he hops to next (8 and 9 = the two happy hops on the spot).
//

import Foundation
import simd

extension BlobBrain {
    /// The world spot of piece-local `p`.
    private func hopscotchWorld(_ f: DecorFoot, _ p: SIMD2<Float>) -> SIMD2<Float> { f.centre + f.turned(p) }
    private func hopscotchFacing(_ f: DecorFoot) -> Float { f.quarter == 0 ? faceCameraYaw() : f.yaw }

    /// Where he walks to join the court: the start spot when he is the first, else the next queue spot (nil when the line is full or the spot is blocked).
    func hopscotchStand(_ f: DecorFoot) -> SIMD2<Float>? {
        let line = HopscotchLine.shared
        guard line.players(f.uid).count < HopscotchTuning.maxPlayers || line.contains(f.uid, steerID) else { return nil }
        let slot = line.players(f.uid).first { $0.id == steerID }?.slot ?? line.nextSlot(f.uid)
        guard slot < HopscotchTuning.maxPlayers else { return nil }
        let base = HopscotchCourt.queueSpot(slot: slot)
        for off in [SIMD2<Float>(0, 0), SIMD2(0, 0.45), SIMD2(0.45, 0.45), SIMD2(0, -0.45)] {
            let p = hopscotchWorld(f, base + off), q = fixed(p)
            if simd_distance(p, q) < 0.5, peerFree(q) { return q }          // (a spot the room moves a little - a friend's gap, the seesaw's edge - is still the queue)
        }
        return nil
    }

    /// `decorStart` committed: he joins the line (the first one opens it and tells the others).
    func hopscotchCommit(_ f: DecorFoot) {
        let line = HopscotchLine.shared
        let first = line.players(f.uid).isEmpty
        let slot = line.enroll(f.uid, steerID)
        idleState.seat = slot; idleState.slideStage = 0; idleState.slideStep = 0
        if first { DecorField.shared.hopscotchInvite(f.uid, at: f.centre) }
    }

    /// A walk of the behaviour is over (`decorArrived`).
    func hopscotchWalkDone(_ f: DecorFoot, _ skinner: Skinner) {
        idleState.decorGo = false
        idleState.phase = 0; idleState.phaseT = 0; idleState.t = 0; idleState.steps = 0
        script = .idle; activity = .lookingAround
        switch idleState.slideStage {
        case 3: idleFinish(skinner)
        default:
            // (stepped up (slot 0) but the walk stopped over 0.5 short of the start - a friend on it: a bounded number of tries, then he gives the game up)
            let short = idleState.seat == 0 ? simd_distance(position, hopscotchWorld(f, HopscotchCourt.queueSpot(slot: 0))) : 0          // (the same start and 0.5 as stage 5 measures)
            if short > 0.5, short < HopscotchTuning.startBlockedWithin {          // (a walk that is still far from the start - round the slide, past the queue - is travelling, not blocked: only a stop near the start counts)
                idleState.decorRetry += 1
                if idleState.decorRetry > HopscotchTuning.startTries { idleFinish(skinner); return }
            }
            idleState.slideStage = 5          // (at the queue spot or the start: turn to face the court, then see whether it is his turn)
        }
    }

    /// Of the ones still queued (slot != 0) he is at the lowest slot, the nearest to the start: one steps up at a time, and nobody walks past a waiting friend to get there
    /// (a nearest-by-distance test cannot see friends who stand still: the roster hands those out under a placeholder id).
    private func hopscotchIsFront(_ uid: Int) -> Bool {
        let queued = HopscotchLine.shared.players(uid).filter { $0.slot != 0 }
        return queued.min { $0.slot < $1.slot }?.id == steerID
    }
    private func hopscotchStepUp(_ start: SIMD2<Float>) {
        let spot = fixed(start)
        idleState.slideStage = 4; idleState.decorGo = true; idleState.target = spot
        route = []; scriptT = 0; stuckT = 0; bestDist = .infinity; steerStall = 0
        script = .walk(target: spot, then: .none); activity = .walking
    }

    /// Stage 5 (turn and wait), 6 (settled on a square: the gate for the next hop).
    func runHopscotch(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let f = DecorField.shared.foot(idleState.decorUID) else { idleFinish(skinner); return }
        let line = HopscotchLine.shared, uid = f.uid, me = steerID
        let phT = idleState.phaseT
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        switch idleState.slideStage {
        case 5:
            idleState.goalYaw = hopscotchFacing(f)
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
            guard !turning, !feet.active, phT > 0.15 else { return }
            let start = hopscotchWorld(f, HopscotchCourt.queueSpot(slot: 0))
            if simd_distance(position, start) > 0.5 {
                if idleState.seat == 0 {
                    // already stepped up, the walk stopped short (a friend on the start): wait a moment, try again (bounded in hopscotchWalkDone)
                    if phT > (idleState.decorRetry > 0 ? 1.5 : 0.15) { hopscotchStepUp(start) }
                } else if line.startOpen(uid), hopscotchIsFront(uid) {
                    line.start(uid, me); idleState.seat = 0; idleState.decorRetry = 0
                    hopscotchStepUp(start)
                } else if phT > HopscotchTuning.patience { idleFinish(skinner) }
                else if phT > 1.2, Int(phT * 2) % 5 == 0, (phT * 2).truncatingRemainder(dividingBy: 1) < dt * 2 { jellyKick = max(jellyKick, 0.5) }          // (a little eager bounce while the line moves)
                return
            }
            idleState.slideStage = 6; idleState.slideStep = 0; idleState.phaseT = 0; idleState.k = 0
            face(.excited, hold: 1.4)
        case 6:
            let t = idleState.slideStep
            let celebrating = t >= HopscotchCourt.count
            let settle: Float = celebrating ? 0.10 : (t == 0 ? 0.25 : 0.12)          // (the landing's squash is seen before the next crouch)
            guard phT >= settle, !feet.active else { return }
            if !celebrating {
                let goal = hopscotchWorld(f, HopscotchCourt.squares[t])
                // (a friend who just stands on the square gets a few seconds to move on; a body only half over it is no reason to stop the game)
                let clear: Float = phT > 4 ? 0.9 : HopscotchTuning.landingClear
                let free = !steerPeers().contains { $0.id != me && simd_distance($0.pos, goal) < clear }
                guard line.mayHop(uid, me, to: t), free else {
                    if phT > HopscotchTuning.patience { idleFinish(skinner) }
                    return
                }
            }
            hopscotchHop(sim, f)
        default: break
        }
    }

    private func hopscotchHop(_ sim: SoftBody, _ f: DecorFoot) {
        let t = idleState.slideStep
        let goal = hopscotchWorld(f, HopscotchCourt.squares[min(t, HopscotchCourt.count - 1)])
        idleState.slideStage = 1; idleState.decorBooped = false; idleState.phaseT = 0
        bagHop(sim, to: goal, ground: sim.floorY, apex: t >= HopscotchCourt.count ? 0.13 : 0.19, facing: hopscotchFacing(f))
    }

    /// The hops own the body (like the slide's steps): true = this step is handled.
    func hopscotchBodyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard idleState.kind == .decorHopscotch, idleState.slideStage == 1, case .idle = script, let f = DecorField.shared.foot(idleState.decorUID) else { return false }
        let line = HopscotchLine.shared, t = idleState.slideStep
        activity = .playing
        mouthOpen = 0
        idleState.phaseT += dt
        let hopGoal: Float = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        gait.basePitch = pitchBase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        if poseW <= 0 { let cen = sim.centroid(); px = cen.x; pz = cen.z }          // (his floor spot follows the hop: what the others steer round and the line measures)
        if gait.phase == .land, !idleState.decorBooped {
            idleState.decorBooped = true
            if t < HopscotchCourt.count { line.landed(f.uid, steerID, t) }
            jellyKick = max(jellyKick, t < HopscotchCourt.count ? 0.8 : 1.4)
            AudioHub.shared.play(.footstep, jelly: steerID, x: px, volume: 0.6)
            AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.28, rate: 0.9 + 0.06 * Float(min(t, 9)))          // (a rising little scale up the court)
        }
        armWalkWant = 1
        let flap = sinf(2 * .pi * 5 * idleState.phaseT)
        armDirW = 1; armDirEl = [0.45 + 0.1 * flap, 0.45 - 0.1 * flap]; armDirSa = [0.1, 0.1]; armDirOut = 0.05
        driveBeansRigid(sim, skinner, dt, tuck: gait.tuck)
        driveArms(sim, skinner, dt)
        if !gait.isBusy {
            gait.basePitch = 0
            gait.hopApex = 0.10; gait.hopDuration = 0.26
            currentPose(sim)
            armDirW = 0; armDirOut = 0
            script = .idle; activity = .lookingAround
            idleState.phaseT = 0; idleState.decorBooped = false
            idleState.slideStep = t + 1
            if idleState.slideStep >= HopscotchCourt.count + 2 { hopscotchLeave(f) } else { idleState.slideStage = 6 }
        }
        return true
    }

    /// The two happy hops are done: he is out of the line (the next may come in) and walks off to a free spot beside the court.
    private func hopscotchLeave(_ f: DecorFoot) {
        HopscotchLine.shared.landed(f.uid, steerID, HopscotchLine.done)
        let want = hopscotchWorld(f, HopscotchCourt.exitSpot + SIMD2(0.5 * Float(idleState.seat & 1), 0))
        let spot = decorFreeSpot(near: want) ?? fixed(want)
        idleState.slideStage = 3; idleState.decorGo = true; idleState.target = spot
        route = []; scriptT = 0; stuckT = 0; bestDist = .infinity; steerStall = 0
        script = .walk(target: spot, then: .none); activity = .walking
        decorIgnore = nil
    }
}
