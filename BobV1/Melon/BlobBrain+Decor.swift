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
    static let decorKinds: Set<IdleKind> = [.decorSit, .decorBoop, .decorKick, .decorHop, .decorPeek, .decorSlide, .decorThrow]

    /// The interactions the room offers right now (a piece nobody is using).
    static func decorOffers() -> Set<IdleKind> {
        let f = DecorField.shared
        var s = Set<IdleKind>()
        for p in f.feet where f.available(p) { if let k = p.kind.activeInteraction { s.insert(k) }; if p.kind.offers(.decorKick) { s.insert(.decorKick) } }
        return s
    }

    /// Releases the piece he was using (called by `idleEnd`).
    func decorRelease() {
        let uid = idleState.decorUID
        if uid >= 0 {
            DecorField.shared.leave(uid, by: steerID)
            // a football he was still hugging is let go (it drops and rolls a little)
            if idleState.kind == .decorThrow, DecorField.shared.anim[uid]?.held == true { DecorField.shared.fling(uid, vh: SIMD2(sinf(yaw), cosf(yaw)) * 0.8, vy: 0, kind: 2) }
            idleState.decorUID = -1
        }
        // he may still be standing in the beanbag he sat in: it stays soft for him until he has walked out of it
        if uid >= 0, idleState.kind == .decorSit || idleState.kind == .sleep, let f = DecorField.shared.foot(uid), f.distance(position) < footprint * f.spec.reach { decorIgnore = uid } else if decorIgnore == uid { decorIgnore = nil }
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

    /// Pieces with a front only: he stands in front of them (a bookshelf is not walked round to look at its back).
    static let frontOnly: Set<DecorKind> = [.bookshelf, .wardrobe, .divider]
    /// The candidate spots in front of a seat: straight in front first, then to either side.
    func hopStandSpots(_ f: DecorFoot, seat: Int) -> [SIMD2<Float>] {
        let sp = f.kind.sitPoints[min(seat, f.kind.sitPoints.count - 1)]
        let c = f.centre
        let dz = f.spec.half.y - sp.z + Self.bagHopGap
        return [Float(0), 0.35, -0.35, 0.7, -0.7].map { c + SIMD2(sp.x + $0, sp.z + dz) }
    }
    /// The first spot in front of the seat he can stand on, nil when there is none.
    func hopStand(_ f: DecorFoot, seat: Int) -> SIMD2<Float>? {
        for p in hopStandSpots(f, seat: seat) {
            let q = fixed(p)
            if simd_distance(p, q) < 0.06, peerFree(q) { return p }
        }
        return nil
    }
    /// A spot `gap` from the piece's edge on the side he comes from (a rounded-box piece: found by walking out from its centre).
    private func edgeStand(_ f: DecorFoot, from here: SIMD2<Float>, gap: Float) -> SIMD2<Float>? {
        let c = DecorField.shared.position(f)
        var angles: [Float]
        if Self.frontOnly.contains(f.kind) { angles = [0, 0.3, -0.3, 0.6, -0.6] }
        else {
            let base = simd_length(here - c) > 1e-3 ? simd_normalize(here - c) : SIMD2<Float>(0, 1)
            let a0 = atan2f(base.x, base.y)
            angles = []
            for k in 0..<9 {
                let step: Float = Float((k + 1) / 2) * 0.5
                let sign: Float = k % 2 == 0 ? 1 : -1
                angles.append(a0 + step * sign)
            }
        }
        for a in angles {
            let u = SIMD2(sinf(a), cosf(a))
            var t: Float = 0.2
            var g = f; g.centre = c
            while t < 4, g.distance(c + u * t) < gap { t += 0.05 }
            let p = c + u * t
            let q = fixed(p)
            if simd_distance(p, q) < 0.06, peerFree(q) { return q }
        }
        return nil
    }

    /// The spot to stand at for a piece, or nil when there is none he can reach.
    func decorStand(_ kind: IdleKind, _ f: DecorFoot, from here: SIMD2<Float>, seat: Int = 0) -> SIMD2<Float>? {
        let c = DecorField.shared.position(f)
        switch kind {
        case .decorSit where f.kind.hopSit && f.kind != .beanbag:
            return hopStand(f, seat: seat)
        case .decorSlide:
            // behind the slide, where the steps start (the JSON's approach point)
            let p = c + SIMD2(0, -DecorKind.slideApproach)
            let q = fixed(p)
            return simd_distance(p, q) < 0.08 && peerFree(q) ? q : nil
        case .decorThrow:
            // a body's length from the football, on the side he comes from
            var u = simd_length(here - c) > 1e-3 ? simd_normalize(here - c) : SIMD2<Float>(0, 1)
            if let aim = throwAim, simd_length(c - aim) > 1e-3 { u = simd_normalize(c - aim) }          // (a toss: on the far side of the ball from the friend)
            for a in [Float(0), 0.6, -0.6, 1.2, -1.2] {
                let v = SIMD2(u.x * cosf(a) - u.y * sinf(a), u.x * sinf(a) + u.y * cosf(a))
                let p = c + v * 0.75
                let q = fixed(p)
                if simd_distance(p, q) < 0.06, peerFree(q) { return q }
            }
            return nil
        case .decorSit where f.kind == .beanbag, .decorBoop, .decorPeek:
            if !DecorKind.original.contains(f.kind) { return edgeStand(f, from: here, gap: max(0.8, footprint * f.spec.reach + 0.06)) }
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
        default: return nil
        }
    }

    func decorStart(_ kind: IdleKind, _ sim: SoftBody, only: DecorKind? = nil) -> Bool {
        guard !sleepLocked else { return false }
        let here = SIMD2(px, pz)
        let field = DecorField.shared
        let exiting = decorIgnore          // (still standing in the bag he sat in: that stays soft for him)
        let wanted = field.feet.filter { $0.kind.offers(kind) && field.available($0) && (only == nil || $0.kind == only) }
        guard !wanted.isEmpty else { return false }
        // nearest first, with a little luck in it, then the first one he can walk to
        let ranked = wanted.map { f -> (DecorFoot, Float) in (f, simd_distance(here, field.position(f)) + rand(0, 1.6)) }.sorted { $0.1 < $1.1 }
        for (f, _) in ranked {
            if kind == .decorKick, field.anim[f.uid]?.moving == true || field.anim[f.uid]?.tumbling == true { continue }
            if kind == .decorThrow || (kind == .decorKick && f.kind == .football), field.anim[f.uid]?.moving == true || field.anim[f.uid]?.flying == true { continue }
            let seat = f.kind.hopSit ? (field.freeSeat(f, preferring: here.x - f.centre.x) ?? 0) : 0
            decorIgnore = (kind == .decorSit || kind == .decorHop || kind == .decorSlide) ? f.uid : exiting
            guard let stand = decorStand(kind, f, from: here, seat: seat),
                  simd_distance(here, stand) > 0.35 || kind == .decorHop || (kind == .decorSit && f.kind.hopSit) || kind == .decorThrow,
                  reachable(here, stand) else { decorIgnore = exiting; continue }
            idleBegin(kind)
            idleState.decorUID = f.uid; idleState.decorGo = true; idleState.decorKicked = false; idleState.decorBooped = false
            idleState.target = stand
            idleState.seat = seat; idleState.seatShift = .zero; idleState.cuddle = 0
            idleState.slideStage = 0; idleState.slideS = 0; idleState.slideStep = 0; idleState.throwStage = 0; throwAim = nil
            idleState.reps = kind == .decorKick && f.kind.rolls ? 1 + (rand() < 0.5 ? 1 : 0) : 0
            if f.kind.hopSit { field.take(f.uid, seat: seat, by: steerID) } else { field.occupant[f.uid] = steerID }
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
                if f.kind == .blocks {
                    DecorField.shared.tumble(f.uid, direction: SIMD2(sinf(a), cosf(a)))          // the tower flies apart
                    AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.8, rate: 0.8)
                    AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.5)
                } else {
                    DecorField.shared.kickBall(f.uid, direction: SIMD2(sinf(a), cosf(a)), speed: f.kind == .football ? rand(1.8, 2.6) : rand(2.5, 3.3))
                    AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.7)
                }
                DecorField.shared.kick(f.uid, 0.6)
                jellyKick = max(jellyKick, 1.4)
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
            else if f.kind.hopSit, let sw = DecorField.shared.seatWorld(f.uid, seat: idleState.seat) { let d = SIMD2(sw.x, sw.z) - position; idleState.goalYaw = atan2f(d.x, d.y); idleState.bagStage = 0 }
        case .decorSlide: slideArrived(sim, skinner, f)
        case .decorThrow: throwArrived(sim, skinner, f)
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
            decorSitPress(uid, k)               // (the cushion; the beanbag and the furniture are sat on top of, see runBagSit)
            if k > 0.55, !idleState.decorBooped { idleState.decorBooped = true; AudioHub.shared.play(.beanbagSit, jelly: steerID, x: px) }
            squash *= 1 - 0.10 * k          // lower in the bag
            pitch -= 0.13 * k               // and leaning back into it
        case .decorBoop:
            if idleState.phase == 1, idleState.phaseT > 0.7, !idleState.decorBooped {
                idleState.decorBooped = true
                jellyKick = max(jellyKick, 1.6)
                DecorField.shared.kick(uid, 1)
                switch DecorField.shared.foot(uid)?.kind {
                case .duck?: AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.7, rate: 1.9); AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.35, rate: 1.8)     // a rubber squeak
                case .drum?: AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.9, rate: Float(0.5 + 0.08 * Double(Int(rand() * 4)))); AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.4, rate: 0.6)
                case .spintop?: DecorField.shared.spinTop(uid); AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.5, rate: 1.4)
                default: AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.6)
                }
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
        case .happy: table = [(.decorSit, 2.0), (.decorBoop, 1.6), (.decorKick, 2.4), (.decorHop, 2.2), (.decorPeek, 1.3), (.decorSlide, 2.2), (.decorThrow, 1.8)]
        case .okay: table = [(.decorSit, 3.0), (.decorBoop, 1.4), (.decorKick, 1.0), (.decorHop, 0.8), (.decorPeek, 1.2), (.decorSlide, 0.8), (.decorThrow, 0.7)]
        case .grumpy: table = [(.decorSit, 1.6), (.decorBoop, 0.5)]
        }
        return table.filter { offers.contains($0.0) }.map { (kind: $0.0, weight: $0.1) }
    }
}

// MARK: - the beanbag and the furniture: hop on, rest on top, hop off

extension BlobBrain {
    /// Gap between the bag's edge and where he stands to hop up (his body radius is ~0.5).
    static let bagHopGap: Float = 0.42
    /// Apex of the hop up (over the edge of the bag) and of the hop down.
    /// How far his feet slide forward onto the bag's front slope as he sits down (they stay attached; the bag's crest is behind him).
    static let bagFootReach: Float = 0.27
    static let bagApexUp: Float = 0.18, bagApexDown: Float = 0.14

    /// The piece he is using is one he hops onto (the beanbag, the pouf, the chairs, the sofa, the stools, the swing; the cushion keeps the old sit).
    var isBagSit: Bool {
        guard idleState.kind == .decorSit, idleState.decorUID >= 0, let f = DecorField.shared.foot(idleState.decorUID) else { return false }
        return f.kind.hopSit
    }
    var sitPiece: DecorFoot? { idleState.decorUID >= 0 ? DecorField.shared.foot(idleState.decorUID) : nil }

    /// The press of his seat: the beanbag / cushion / pouf / armchair use one sink, the multi-seat pieces a sink per seat.
    func decorSitPress(_ uid: Int, _ k: Float) {
        guard let f = DecorField.shared.foot(uid) else { return }
        if f.kind.sitPoints.count > 1 { DecorField.shared.sit(uid, seat: idleState.seat, k) } else { DecorField.shared.sit(uid, k) }
    }

    /// His floor: the seat's top while he is on a piece (it squishes, wobbles, rocks under him, so it follows), the slide's step / chute while he is on it, else the room's.
    /// Every step, so a behaviour that is cut short (grab, come-here, sleep, race) can never leave him on a phantom floor. Only HIS sim changes (every Jelly has its own).
    func applyBagFloor(_ sim: SoftBody, _ skinner: Skinner) {
        var y: Float = 0
        if bagFloorOn, idleState.kind == .decorSit, idleState.decorUID >= 0, let sw = DecorField.shared.seatWorld(idleState.decorUID, seat: idleState.seat) { y = sw.y }
        else if bagFloorOn, idleState.kind == .decorSlide { y = slideY }
        else if bagFloorOn, idleState.kind == .sleep, sleep.bed >= 0, let f = DecorField.shared.foot(sleep.bed) { y = DecorModels.bedFloor(DecorField.shared.anim[f.uid] ?? DecorAnim(), lift: f.lift) }
        else { bagFloorOn = false }
        if sim.floorY != y { sim.floorY = y; skinner.jelly.floorY = y }
    }

    /// One hop between the floor and a seat / step (`ground` = the height he lands on).
    func bagHop(_ sim: SoftBody, to goal: SIMD2<Float>, ground: Float, apex: Float, facing: Float? = nil) {
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.6)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        let pose = sim.bodyPose(iterations: 6)
        gait.facingYaw = facing ?? faceCameraYaw()
        gait.home = SIMD2(pose.centroid.x, pose.centroid.z)
        poseW = 0; poseOn = false
        gait.hopApex = apex
        gait.hopDuration = 0.26 * sqrtf(apex / 0.10) * (1 + 5.0 * max(0, abs(ground - sim.floorY) - 0.41))          // (a taller seat: a slower rise, so the soles keep up with the body)
        gait.hopToGround = ground
        gait.hop(sim, to: goal, reduceMotion: amplitude < 0.7, chained: false)
        idleState.landT = 0
    }

    /// The seat's neutral spot (xz) and its height now.
    private func seatGoal(_ f: DecorFoot) -> (xz: SIMD2<Float>, y: Float) {
        if f.kind == .beanbag { return (f.centre + SIMD2(0, DecorModels.bagSeatZ), DecorField.shared.topY(f.uid) ?? 0.4) }
        let sw = DecorField.shared.seatWorld(f.uid, seat: idleState.seat) ?? SIMD3(f.centre.x, f.spec.height, f.centre.y)
        // (a rocking seat is hopped onto where it rests: the neutral spot)
        let sp = f.kind.sitPoints[min(idleState.seat, f.kind.sitPoints.count - 1)]
        return (f.centre + SIMD2(sp.x, sp.z), sw.y)
    }

    /// While he sits on a rocking chair / swing the seat carries him: his root and planted feet move by the seat's change.
    func seatFollow(_ f: DecorFoot) {
        guard f.kind == .rockingchair || f.kind == .swing, let sw = DecorField.shared.seatWorld(f.uid, seat: idleState.seat) else { return }
        let sp = f.kind.sitPoints[min(idleState.seat, f.kind.sitPoints.count - 1)]
        let want = SIMD2<Float>(0, sw.z - (f.centre.y + sp.z))
        let d = want - idleState.seatShift
        guard simd_length(d) > 1e-6 else { return }
        pz += d.y
        feet.pos[0] += d; feet.pos[1] += d
        idleState.seatShift = want
    }

    /// Stage 0 (turn to the seat, then hop up) and stage 2 (on top: rests, then hops off), run as the posture.
    func runBagSit(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let f = DecorField.shared.foot(idleState.decorUID) else { idleFinish(skinner); return }
        let c = f.centre
        switch idleState.bagStage {
        case 0:
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if !turning && !feet.active && idleState.phaseT > 0.1 {
                idleState.bagStage = 1; idleState.phaseT = 0; idleState.decorBooped = false
                let g = seatGoal(f)
                bagHop(sim, to: g.xz, ground: g.y, apex: Self.bagApexUp, facing: f.kind.seatFacing(idleState.seat))
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
                    let goal = hopExitSpot(f)          // forward (toward the camera) when it is clear, else the nearest clear side: never onto the plant / cushion beside the piece
                    bagHop(sim, to: goal, ground: 0, apex: Self.bagApexDown + max(0, seatGoal(f).y - 0.45) * 0.3)
                    return
                }
            }
            idleState.k = k
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            sitPose(skinner, k, slump: false)
            skinner.setEyeOpenness(1 - 0.25 * k)
            seatMotion(f, k: k)
        default: break
        }
    }

    /// What the seat does to a sitter: a rocking chair / swing rocks (and carries him), a loveseat with a friend on the other cushion leans him toward them.
    private func seatMotion(_ f: DecorFoot, k: Float) {
        let uid = f.uid
        if f.kind == .rockingchair || f.kind == .swing {
            let on = k > 0.5 && idleState.phase == 2 || idleState.phase == 1 && k > 0.3
            let level: Float = on ? max(0.45, 1 - 0.06 * idleState.phaseT) : 0.3
            DecorField.shared.rock(uid, f.kind == .swing ? level : max(level, 0.6))
            seatFollow(f)
            let a = DecorField.shared.anim[uid] ?? DecorAnim()
            pitch += (f.kind == .swing ? DecorModels.swingAngle(a) : DecorModels.rockAngle(a)) * 0.9
        }
        if f.kind == .armchair || f.kind == .loveseat { pitch += 0.12 * k }          // (upright against the backrest: leaning back sank his rear and a tall hat into it)
        if f.kind == .loveseat {
            // both seats taken and both settled: lean toward each other (the snuggle lean), a hair closer
            var want: Float = 0
            if idleState.phase == 2, let o = cuddlePartner(f) { want = o.sign }
            idleState.cuddle += (abs(want) - idleState.cuddle) * 0.06
            if idleState.cuddle > 0.001 {
                let sgn: Float = f.kind.sitPoints[idleState.seat].x < 0 ? 1 : -1       // toward the middle
                roll += -sgn * 0.12 * idleState.cuddle
                let want = SIMD2<Float>(sgn * 0.03 * idleState.cuddle, 0)
                let d = want - idleState.seatShift
                px += d.x; feet.pos[0] += d; feet.pos[1] += d
                idleState.seatShift = want
            }
        }
    }
    /// The other Jelly on the same loveseat, settled on his cushion.
    private func cuddlePartner(_ f: DecorFoot) -> (brain: BlobBrain, sign: Float)? {
        for o in socialOthers() where o !== self {
            if o.idleState.kind == .decorSit, o.idleState.decorUID == f.uid, o.idleState.bagStage == 2, o.idleState.phase == 2, o.idleState.seat != idleState.seat { return (o, 1) }
        }
        return nil
    }

    /// Where he hops down to: in front of his seat when that is clear (the spot he came from), else to either side; the first spot the floor rules leave alone. A bag in
    /// a crowded corner used to throw him forward onto the plant beside it.
    func hopExitSpot(_ f: DecorFoot) -> SIMD2<Float> {
        if f.kind != .beanbag {
            let ignore = decorIgnore
            for p in hopStandSpots(f, seat: idleState.seat) {
                let q = fixed(p)
                if simd_distance(p, q) < 0.05, peerFree(q) { return p }
            }
            decorIgnore = ignore
            return fixed(hopStandSpots(f, seat: idleState.seat)[0])
        }
        return bagExitSpot(f.centre, radius: f.spec.radius)
    }
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

    /// The two hops of the seat sit (they own the body like the bounce): true = this step is handled.
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
                // landed ON TOP: his floor is the seat's top from now on; it squishes, wobbles, settles
                bagFloorOn = true
                applyBagFloor(sim, skinner)
                DecorField.shared.kick(uid, 1)
                if !idleState.decorBooped { idleState.decorBooped = true; AudioHub.shared.play(.beanbagSit, jelly: steerID, x: px) }
            }
            if bagFloorOn { decorSitPress(uid, 0.5) }
        } else {
            decorSitPress(uid, gait.phase == .crouch ? 1 : 0)
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
                idleState.seatShift = .zero
                script = .idle; activity = .lookingAround
                idleState.hold = rand(7, 14)
            } else {
                idleFinish(skinner)
            }
        }
        return true
    }
}
