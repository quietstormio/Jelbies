//
//  BlobBrain+Decor.swift
//  Things he does with the store's decor (Room/DecorModel.swift), all built from the existing moves and postures (no new limb poses, no new gait: the
//  arms stay thumbs and the feet stay under him in every one of them):
//    decorSit    walks onto a beanbag / floor cushion (the one piece he may stand inside) and sits: the sit posture, a little lower, the bag sinks
//    decorBoop   walks up to the potted plant, leans in (the LOOK posture with a forward lean) and nudges it: a jelly kick, the leaves wiggle
//    decorKick   walks into the ball: it is booted and rolls away; if it stops nearby he walks after it for a second kick
//    decorHop    walks onto the bouncy mat and bounces (the happy bounce), the mat dips on every landing
//    decorPeek   goes to the toy box and leans over to peek in (the LOOK posture, a deeper lean); the toys jump
//  Picked by the idle scheduler like the other antics (weights in `IdleTable.decorWeights`, a per-kind cooldown, never while sleepLocked / racing).
//

import Foundation
import simd

extension BlobBrain {
    static let decorKinds: Set<IdleKind> = [.decorSit, .decorBoop, .decorKick, .decorHop, .decorPeek]

    /// The interactions the room offers right now (a piece nobody is using).
    static func decorOffers() -> Set<IdleKind> {
        let f = DecorField.shared
        var s = Set<IdleKind>()
        for p in f.feet where f.occupant[p.uid] == nil && p.uid != f.held { if let k = p.kind.interaction { s.insert(k) } }
        return s
    }

    /// Releases the piece he was using (called by `idleEnd`).
    func decorRelease() {
        let uid = idleState.decorUID
        if uid >= 0 {
            if DecorField.shared.occupant[uid] == steerID { DecorField.shared.occupant[uid] = nil }
            idleState.decorUID = -1
        }
        // he may still be standing in the beanbag he sat in: it stays soft for him until he has walked out of it
        if uid >= 0, idleState.kind == .decorSit, let f = DecorField.shared.foot(uid), f.distance(position) < footprint * f.spec.reach { decorIgnore = uid } else if decorIgnore == uid { decorIgnore = nil }
    }
    /// Every step with no behaviour running: the piece he sat in is a wall again once he is out of it.
    func decorExitCheck() {
        guard let uid = decorIgnore else {
            // a piece put down under him (or a push): he is let out of it the same way
            for f in DecorField.shared.feet where f.spec.solid && f.distance(position) < footprint * f.spec.reach - 0.1 { decorIgnore = f.uid; return }
            return
        }
        if let f = DecorField.shared.foot(uid), f.distance(position) < footprint * f.spec.reach + 0.05 { return }
        decorIgnore = nil
    }

    /// The spot to stand at for a piece, or nil when there is none he can reach.
    private func decorStand(_ kind: IdleKind, _ f: DecorFoot, from here: SIMD2<Float>) -> SIMD2<Float>? {
        let c = DecorField.shared.position(f)
        switch kind {
        case .decorSit where f.kind == .beanbag, .decorBoop, .decorPeek:
            // a spot just outside the piece, on the side he comes from (he walks straight up to it and turns little); the beanbag: close enough to hop up
            let base = simd_length(here - c) > 1e-3 ? simd_normalize(here - c) : SIMD2<Float>(0, 1)
            let gap = f.spec.radius + (kind == .decorSit ? Self.bagHopGap : 0.78)
            let a0 = atan2f(base.x, base.y)
            for k in 0..<9 {
                let off = Float((k + 1) / 2) * 0.5 * (k % 2 == 0 ? 1 : -1)
                let a = a0 + off
                let p = c + SIMD2(sinf(a), cosf(a)) * gap
                let q = fixed(p)
                if simd_distance(p, q) < 0.06 || kind == .decorSit, peerFree(q) { return kind == .decorSit ? p : q }
            }
            return nil
        case .decorSit, .decorHop: return c
        case .decorKick: return c
        case .decorBoop, .decorPeek:     // (handled above; kept for the exhaustive switch)
            // a spot just outside the piece, on the side he comes from (he walks straight up to it and turns little)
            let base = simd_length(here - c) > 1e-3 ? simd_normalize(here - c) : SIMD2<Float>(0, 1)
            let gap = f.spec.radius + 0.78
            let a0 = atan2f(base.x, base.y)
            for k in 0..<9 {
                let off = Float((k + 1) / 2) * 0.5 * (k % 2 == 0 ? 1 : -1)
                let a = a0 + off
                let p = c + SIMD2(sinf(a), cosf(a)) * gap
                let q = fixed(p)
                if simd_distance(p, q) < 0.06, peerFree(q) { return q }
            }
            return nil
        default: return nil
        }
    }

    func decorStart(_ kind: IdleKind, _ sim: SoftBody) -> Bool {
        guard !sleepLocked else { return false }
        let here = SIMD2(px, pz)
        let field = DecorField.shared
        let exiting = decorIgnore          // (still standing in the bag he sat in: that stays soft for him)
        let wanted = field.feet.filter { $0.kind.interaction == kind && field.occupant[$0.uid] == nil && $0.uid != field.held }
        guard !wanted.isEmpty else { return false }
        // nearest first, with a little luck in it, then the first one he can walk to
        let ranked = wanted.map { f -> (DecorFoot, Float) in (f, simd_distance(here, field.position(f)) + rand(0, 1.6)) }.sorted { $0.1 < $1.1 }
        for (f, _) in ranked {
            if kind == .decorKick, field.anim[f.uid]?.moving == true { continue }
            decorIgnore = (kind == .decorSit || kind == .decorHop) ? f.uid : exiting
            guard let stand = decorStand(kind, f, from: here), simd_distance(here, stand) > 0.35 || kind == .decorHop || (kind == .decorSit && f.kind == .beanbag),
                  reachable(here, stand) else { decorIgnore = exiting; continue }
            idleBegin(kind)
            idleState.decorUID = f.uid; idleState.decorGo = true; idleState.decorKicked = false; idleState.decorBooped = false
            idleState.target = stand
            idleState.reps = kind == .decorKick ? 1 + (rand() < 0.5 ? 1 : 0) : 0
            field.occupant[f.uid] = steerID
            script = .walk(target: stand, then: .none); activity = .walking
            return true
        }
        decorIgnore = exiting
        return false
    }

    /// Every step while a decor behaviour runs (before the gait): the kick lands when the ball is within reach.
    func decorTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let kind = idleState.kind, idleState.decorUID >= 0, let f = DecorField.shared.foot(idleState.decorUID) else { return }
        if kind == .decorKick, idleState.decorGo, !idleState.decorKicked {
            let ball = DecorField.shared.position(f)
            let d = simd_distance(position, ball)
            if d < 1.12 {
                idleState.decorKicked = true
                let away = ball - position
                let a = atan2f(away.x, away.y) + rand(-0.3, 0.3)
                DecorField.shared.kickBall(f.uid, direction: SIMD2(sinf(a), cosf(a)), speed: rand(2.5, 3.3))
                DecorField.shared.kick(f.uid, 0.6)
                jellyKick = max(jellyKick, 1.4)
                AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.7)
            }
        }
    }

    /// The walk to the piece is over.
    func decorArrived(_ sim: SoftBody, _ skinner: Skinner) {
        guard let kind = idleState.kind, let f = DecorField.shared.foot(idleState.decorUID) else { idleFinish(skinner); return }
        idleState.decorGo = false
        idleState.phase = 0; idleState.phaseT = 0; idleState.t = 0; idleState.steps = 0
        script = .idle; activity = .lookingAround
        let c = DecorField.shared.position(f)
        switch kind {
        case .decorSit:
            idleState.hold = rand(7, 14)
            idleState.goalYaw = faceCameraYaw() + idleState.sign * rand(0.1, 0.5)
            if f.kind == .beanbag { let d = c - position; idleState.goalYaw = atan2f(d.x, d.y); idleState.bagStage = 0 }
        case .decorBoop:
            idleState.hold = 2.6
            let d = c - position
            idleState.goalYaw = atan2f(d.x, d.y)
        case .decorPeek:
            idleState.hold = 3.4
            let d = c - position
            idleState.goalYaw = atan2f(d.x, d.y)
        case .decorHop:
            // become the happy bounce, on the mat
            idleState.kind = .bounce
            idleState.target = position
            idleState.reps = 4 + Int(rand() * 3)
            idleState.hop = 0; idleState.landT = 0
            script = .idle; activity = .playing
            idleState.phase = 1; idleState.phaseT = 0
            decorIgnore = nil
            idleScootHop(sim)
        case .decorKick:
            idleState.phase = 0
            activity = .lookingAround
        default: idleFinish(skinner)
        }
    }

    /// After a kick: wait for the ball to stop, then walk after it for the second one, or finish.
    func runDecorKick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let f = DecorField.shared.foot(idleState.decorUID) else { idleFinish(skinner); return }
        gaitPose(sway: 0.05, bob: 0.0, rock: 0.2)
        let a = DecorField.shared.anim[f.uid]
        let t = idleState.phaseT
        if a?.moving == true && t < 4.5 { return }
        guard !feet.active else { return }
        if idleState.reps > 0, t < 5 {
            let ball = DecorField.shared.position(f)
            let here = position
            if simd_distance(here, ball) > 0.9, simd_distance(here, ball) < 4.2, reachable(here, ball) {
                idleState.reps -= 1
                idleState.decorGo = true; idleState.decorKicked = false
                idleState.target = ball
                scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0
                script = .walk(target: ball, then: .none); activity = .walking
                return
            }
        }
        if t > 0.6 { idleFinish(skinner) }
    }

    /// The postures' decor hooks: called from the sit / look postures while they run.
    func decorPose(_ skinner: Skinner, k: Float) {
        guard let kind = idleState.kind, idleState.decorUID >= 0 else { return }
        let uid = idleState.decorUID
        switch kind {
        case .decorSit:
            DecorField.shared.sit(uid, k)       // (the cushion; the beanbag is sat on top of, see runBagSit)
            if k > 0.55, !idleState.decorBooped { idleState.decorBooped = true; AudioHub.shared.play(.beanbagSit, jelly: steerID, x: px) }
            squash *= 1 - 0.10 * k          // lower in the bag
            pitch -= 0.13 * k               // and leaning back into it
        case .decorBoop:
            if idleState.phase == 1, idleState.phaseT > 0.7, !idleState.decorBooped {
                idleState.decorBooped = true
                jellyKick = max(jellyKick, 1.6)
                DecorField.shared.kick(uid, 1)
                AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.6)
            }
            if idleState.phase == 1, idleState.phaseT > 1.7, idleState.decorBooped, idleState.decorKicked == false {
                idleState.decorKicked = true
                DecorField.shared.kick(uid, 0.7)
            }
        case .decorPeek:
            DecorField.shared.peek(uid, idleState.phase == 1 ? 1 : 0)
            if idleState.phase == 1, idleState.phaseT > 1.0, !idleState.decorBooped {
                idleState.decorBooped = true
                DecorField.shared.kick(uid, 0.8)
                AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.35)
            }
        default: break
        }
    }
}

extension IdleTable {
    /// What the decor adds to a mood's table, for the interactions the room offers.
    static func decorWeights(_ m: IdleMood, offers: Set<IdleKind>) -> [(kind: IdleKind, weight: Float)] {
        let table: [(IdleKind, Float)]
        switch m {
        case .happy: table = [(.decorSit, 2.0), (.decorBoop, 1.6), (.decorKick, 2.4), (.decorHop, 2.2), (.decorPeek, 1.3)]
        case .okay: table = [(.decorSit, 3.0), (.decorBoop, 1.4), (.decorKick, 1.0), (.decorHop, 0.8), (.decorPeek, 1.2)]
        case .grumpy: table = [(.decorSit, 1.6), (.decorBoop, 0.5)]
        }
        return table.filter { offers.contains($0.0) }.map { (kind: $0.0, weight: $0.1) }
    }
}

// MARK: - the beanbag: hop on, rest on top, hop off

extension BlobBrain {
    /// Gap between the bag's edge and where he stands to hop up (his body radius is ~0.5).
    static let bagHopGap: Float = 0.42
    /// Apex of the hop up (over the edge of the bag) and of the hop down.
    /// How far his feet slide forward onto the bag's front slope as he sits down (they stay attached; the bag's crest is behind him).
    static let bagFootReach: Float = 0.27
    static let bagApexUp: Float = 0.18, bagApexDown: Float = 0.14

    /// The piece he is using is a beanbag (the cushion keeps the old sit).
    var isBagSit: Bool {
        guard idleState.kind == .decorSit, idleState.decorUID >= 0, let f = DecorField.shared.foot(idleState.decorUID) else { return false }
        return f.kind == .beanbag
    }

    /// His floor: the bag's top while he is on it (it squishes and wobbles under him, so it follows), else the room's. Every step, so a behaviour that
    /// is cut short (grab, come-here, sleep, race) can never leave him on a phantom floor. Only HIS sim changes (every Jelly has its own).
    func applyBagFloor(_ sim: SoftBody, _ skinner: Skinner) {
        var y: Float = 0
        if bagFloorOn, idleState.kind == .decorSit, idleState.decorUID >= 0, let top = DecorField.shared.topY(idleState.decorUID) { y = top } else { bagFloorOn = false }
        if sim.floorY != y { sim.floorY = y; skinner.jelly.floorY = y }
    }

    /// One hop between the floor and the bag's top (`ground` = the height he lands on).
    private func bagHop(_ sim: SoftBody, to goal: SIMD2<Float>, ground: Float, apex: Float) {
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.6)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        let pose = sim.bodyPose(iterations: 6)
        gait.facingYaw = faceCameraYaw()
        gait.home = SIMD2(pose.centroid.x, pose.centroid.z)
        poseW = 0; poseOn = false
        gait.hopApex = apex
        gait.hopDuration = 0.26 * sqrtf(apex / 0.10)
        gait.hopToGround = ground
        gait.hop(sim, to: goal, reduceMotion: amplitude < 0.7, chained: false)
        idleState.landT = 0
    }

    /// Stage 0 (turn to the bag, then hop up) and stage 2 (on top: rests, then hops off), run as the posture.
    func runBagSit(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let f = DecorField.shared.foot(idleState.decorUID) else { idleFinish(skinner); return }
        let c = f.centre
        switch idleState.bagStage {
        case 0:
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if !turning && !feet.active && idleState.phaseT > 0.1 {
                idleState.bagStage = 1; idleState.phaseT = 0; idleState.decorBooped = false
                bagHop(sim, to: c + SIMD2(0, DecorModels.bagSeatZ), ground: DecorField.shared.topY(f.uid) ?? 0.4, apex: Self.bagApexUp)
            }
        case 2:
            // in the seat: sits down (two feet slide forward over the lip, the body lowers and leans back), rests, gets up, hops off
            var k = idleState.k
            let phT = idleState.phaseT
            switch idleState.phase {
            case 1:
                k = smooth01(phT / 1.15)
                if !feet.active && idleState.steps < 2 && phT > Float(idleState.steps) * 0.35 { idleFootStep(reach: Self.bagFootReach); idleState.steps += 1 }
                if phT >= 1.15 && !feet.active { idleState.phase = 2; idleState.phaseT = 0 }
            case 2:
                k = 1
                if phT >= idleState.hold { idleState.phase = 3; idleState.phaseT = 0; idleState.steps = 0 }
            default:
                k = 1 - smooth01(phT / 1.0)
                if !feet.active && idleState.steps < 2 && phT > Float(idleState.steps) * 0.3 { idleFootStep(reach: 0); idleState.steps += 1 }
                if phT >= 1.0 && !feet.active && idleState.steps >= 2 {
                    idleState.k = 0; sitPose(skinner, 0, slump: false)
                    idleState.bagStage = 3; idleState.phaseT = 0
                    let goal = bagExitSpot(c, radius: f.spec.radius)          // forward (toward the camera) when it is clear, else the nearest clear side: never onto the plant / cushion beside the bag
                    bagHop(sim, to: goal, ground: 0, apex: Self.bagApexDown)
                    return
                }
            }
            idleState.k = k
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            sitPose(skinner, k, slump: false)
            skinner.setEyeOpenness(1 - 0.25 * k)
        default: break
        }
    }

    /// Where he hops down to: the way he sat (toward the camera), else to either side, else behind; the first spot the floor rules leave alone. A bag in a crowded
    /// corner used to throw him forward onto the plant beside it.
    func bagExitSpot(_ c: SIMD2<Float>, radius: Float) -> SIMD2<Float> {
        let d = radius + Self.bagHopGap
        let dirs: [SIMD2<Float>] = [SIMD2(0, 1), SIMD2(0.7071, 0.7071), SIMD2(-0.7071, 0.7071), SIMD2(1, 0), SIMD2(-1, 0), SIMD2(0.7071, -0.7071), SIMD2(-0.7071, -0.7071), SIMD2(0, -1)]
        let ignore = decorIgnore
        for u in dirs {
            let p = c + u * d
            let q = fixed(p)
            if simd_distance(p, q) < 0.05, peerFree(q) { return p }
        }
        decorIgnore = ignore
        return fixed(c + SIMD2<Float>(0, 1) * d)
    }

    /// The two hops of the bag sit (they own the body like the bounce): true = this step is handled.
    func bagBodyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard isBagSit, idleState.bagStage == 1 || idleState.bagStage == 3, case .idle = script else { return false }
        let uid = idleState.decorUID
        activity = .playing
        mouthOpen = 0
        idleState.phaseT += dt
        let hopGoal: Float = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        gait.basePitch = pitchBase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        if idleState.bagStage == 1 {
            if gait.phase == .land, !bagFloorOn {
                // landed ON TOP: his floor is the bag's top from now on; the bag squishes, wobbles, settles
                bagFloorOn = true
                applyBagFloor(sim, skinner)
                DecorField.shared.kick(uid, 1)
                if !idleState.decorBooped { idleState.decorBooped = true; AudioHub.shared.play(.beanbagSit, jelly: steerID, x: px) }
            }
            if bagFloorOn { DecorField.shared.sit(uid, 0.5) }
        } else {
            DecorField.shared.sit(uid, gait.phase == .crouch ? 1 : 0)
            if gait.phase == .air || gait.phase == .land { bagFloorOn = false; applyBagFloor(sim, skinner) }
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
            if idleState.bagStage == 1 {
                idleState.bagStage = 2; idleState.phaseT = 0; idleState.phase = 1; idleState.steps = 0; idleState.k = 0
                script = .idle; activity = .lookingAround
                idleState.hold = rand(7, 14)
            } else {
                idleFinish(skinner)
            }
        }
        return true
    }
}
