//
//  BlobBrain+Scooter.swift
//  The kick scooter ride (2026-10-27, "ensure they can all be ridden"): built from the existing parts of the slide / seat sits (hop up onto a raised floor, a
//  driven root with both soles pinned under him, hop down), run as the `.decorSlide` behaviour of the scooter piece. The arms stay thumbs, the feet stay attached.
//    0  stand beside the deck, turn to it         1  hop onto the deck (both feet land on it; the scooter wobbles)
//   10  ready: plans a loop of free floor          11  the ride: a smooth circle, eased speed, wheels turning, a push bob, a lean into the turn
//   12  rolls to a stop on its parking spot        14  hops off beside it (the scooter is parked where it started)
//   13  a blocked ride (somebody stays in the way): he hops off, the scooter rolls back along the way it came
//  THE LOOP never meets anything: it is planned over free floor (walls, furniture and other decor by `resolve`, the Jellies standing now by the room's gap),
//  and every step the ride looks ahead along its own path for every other Jelly (where they are and where they are going, 0.2 / 0.5 / 0.9 s on): it slows,
//  stops and waits when the gap would close, and gives the ride up (13) when the way stays blocked.
//

import Foundation
import simd

enum ScooterTuning {
    /// Speed (u/s), the eased acceleration and braking.
    static let vmax: Float = 1.9, accel: Float = 2.2, brake: Float = 5.0, comfyBrake: Float = 2.4
    /// Where he stands on the deck along the scooter's heading (the scooter's origin is the middle of its footprint) and the deck's top.
    static let standOff: Float = -0.30, deckTop: Float = 0.34
    /// The wheel radius (world), for the wheels' turn.
    static let wheelR: Float = 0.18
    /// Radii of the loop to try, biggest first.
    static let radii: [Float] = [1.3, 1.05, 0.85, 0.7]
    /// A ride waits this long for the way to clear before it is given up.
    static let patience: Float = 3.5
}

/// One ride's state (the brain keeps one; nothing allocates while it runs).
struct ScooterRide {
    var start = SIMD2<Float>.zero, h0: Float = 0
    var kappa: Float = 0, total: Float = 0
    var s: Float = 0, v: Float = 0
    var waitT: Float = 0, bobT: Float = 0, t: Float = 0
    var peerPrev = [SIMD2<Float>](repeating: .zero, count: 8)
    var peerSeen = [Bool](repeating: false, count: 8)
    var planned = false
    /// Diagnostics (tests): the closest any other Jelly came to him while he rode, and the loops that were given up.
    var minGap: Float = .infinity
    var rides = 0, gaveUp = 0, noLoop = 0, blocked = 0
    var blockNote = ""
}

extension BlobBrain {
    /// The scooter piece he is on / at, if his behaviour is a scooter ride.
    var scooterFoot: DecorFoot? {
        guard idleState.kind == .decorSlide, idleState.decorUID >= 0, let f = DecorField.shared.foot(idleState.decorUID), f.kind == .kickscooter else { return nil }
        return f
    }

    // MARK: path

    /// The scooter's origin and heading at distance `s` along the loop (a constant-curvature circle through the parking spot).
    @inline(__always) func scooterAt(_ s: Float) -> (p: SIMD2<Float>, h: Float) {
        let r = ride, h = r.h0 + r.kappa * s
        let k = r.kappa
        return (SIMD2(r.start.x + (cosf(r.h0) - cosf(h)) / k, r.start.y + (sinf(h) - sinf(r.h0)) / k), h)
    }
    /// His root on the deck while the scooter is at `s`.
    @inline(__always) func scooterRoot(_ s: Float) -> (p: SIMD2<Float>, h: Float) {
        let a = scooterAt(s)
        return (a.p + SIMD2(sinf(a.h), cosf(a.h)) * ScooterTuning.standOff, a.h)
    }

    /// Does the loop with curvature `kappa` keep to free floor (nothing solid, no wall, nobody standing there now)? `margin` is extra clearance.
    private func scooterLoopFree(_ f: DecorFoot, kappa: Float, margin: Float, avoidPeers: Bool) -> Bool {
        var probe = ride
        probe.kappa = kappa
        let total = 2 * Float.pi / abs(kappa)
        let saved = ride
        ride = probe
        defer { ride = saved }
        var s: Float = 0
        while s <= total + 0.001 {
            let a = scooterAt(s)
            let d = SIMD2<Float>(sinf(a.h), cosf(a.h))
            // his body, the front wheel and the back wheel
            for (q, r) in [(a.p + d * ScooterTuning.standOff, footprint + margin), (a.p + d * 0.62, 0.30 + margin), (a.p - d * 0.5, 0.30 + margin)] {
                // the floor rules alone (walls, solid furniture, other decor): the Jellies are looked for below and, while riding, every step
                let rv = GameCamera.constrain(SIMD3(q.x, 0, q.y), radius: r, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: f.uid)
                if simd_distance(SIMD2(rv.x, rv.z), q) > 0.02 { return false }
            }
            if avoidPeers {
                let me = a.p + d * ScooterTuning.standOff
                for o in socialOthers() where o !== self && simd_distance(o.position, me) < peerGap * 1.05 { return false }
            }
            s += 0.2
        }
        return true
    }

    // MARK: stand spots

    /// Where he may stand beside the deck to hop on / off, piece-local (the camera side first, then behind it, off its back end, off its front end, far side spots).
    static let scooterStands: [SIMD2<Float>] = [SIMD2(-0.30, 0.95), SIMD2(-0.30, -0.95), SIMD2(-1.35, 0), SIMD2(-0.1, 1.15), SIMD2(-0.30, 1.4), SIMD2(-0.30, -1.4), SIMD2(1.35, 0), SIMD2(-1.9, 0)]

    /// Where he stands to hop on: beside the deck (the camera side first), else behind it, else the back of it.
    func scooterStand(_ f: DecorFoot, from here: SIMD2<Float>) -> SIMD2<Float>? {
        let c = DecorField.shared.position(f)
        let cands = Self.scooterStands
        let ignore = decorIgnore
        decorIgnore = f.uid
        defer { decorIgnore = ignore }
        for l in cands {
            let p = c + f.turned(l)
            let q = fixed(p)
            if simd_distance(p, q) < 0.06, peerFree(q) { return q }
        }
        return nil
    }
    /// Where he hops off to (same candidates, nearest the way he came first); nil when all are blocked.
    func scooterExit(_ f: DecorFoot) -> SIMD2<Float> {
        let c = DecorField.shared.position(f)
        let cands = Self.scooterStands
        let ignore = decorIgnore
        decorIgnore = f.uid
        defer { decorIgnore = ignore }
        for l in cands {
            let p = c + f.turned(l)
            let q = fixed(p)
            if simd_distance(p, q) < 0.06, peerFree(q) { return q }
        }
        return fixed(c + f.turned(SIMD2(-0.30, 0.95)))
    }

    // MARK: arrive, hop on / off

    func scooterArrived(_ sim: SoftBody, _ skinner: Skinner, _ f: DecorFoot) {
        idleState.slideStage = 0; idleState.slideStep = 0
        let c = DecorField.shared.position(f)
        let d = c - position
        idleState.goalYaw = atan2f(d.x, d.y)
        script = .idle; activity = .lookingAround
    }

    private func scooterHeading(_ f: DecorFoot) -> Float {
        let d = f.turned(SIMD2(1, 0))
        return atan2f(d.x, d.y)
    }

    /// The hop onto the deck (stage 1) and off it (stage 14) own the body, like the seat sits' hops: true = this step is handled.
    func scooterBodyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) -> Bool {
        let up = idleState.slideStage == 1
        activity = .playing
        mouthOpen = 0
        idleState.phaseT += dt
        let hopGoal: Float = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        gait.basePitch = pitchBase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        if poseW <= 0 { let cen = sim.centroid(); px = cen.x; pz = cen.z }
        if up {
            if gait.phase == .land, !bagFloorOn {
                bagFloorOn = true; slideY = ScooterTuning.deckTop
                applyBagFloor(sim, skinner)
                DecorField.shared.kick(f.uid, 0.5)
                AudioHub.shared.play(.footstep, jelly: steerID, x: px, volume: 0.9)
            }
        } else if gait.phase == .air || gait.phase == .land { bagFloorOn = false; applyBagFloor(sim, skinner) }
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
            idleState.phaseT = 0
            if up { idleState.slideStage = 10; idleState.k = 0; ride.planned = false }
            else if idleState.slideStage == 15 { idleState.slideStage = 16; ride.v = 0 }
            else { idleState.slideStage = 0; scooterParked(f); idleFinish(skinner) }
        }
        return true
    }

    /// He has hopped off and the scooter is home: it is parked.
    func scooterParked(_ f: DecorFoot) {
        if var a = DecorField.shared.anim[f.uid] { a.carried = false; a.pos = f.centre; a.heading = 0; a.wheel = a.wheel.truncatingRemainder(dividingBy: 2 * .pi); a.steer = 0; DecorField.shared.setAnim(f.uid, a) }
    }

    // MARK: the run (stages 0, 10, 11, 12, 13)

    func runScooter(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) {
        switch idleState.slideStage {
        case 0:
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.1)
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if !turning && !feet.active && idleState.phaseT > 0.15 {
                // hop on: the deck's middle-back; he faces the scooter's nose
                let h0 = scooterHeading(f)
                let c = DecorField.shared.position(f)
                let goal = c + SIMD2(sinf(h0), cosf(h0)) * ScooterTuning.standOff
                idleState.slideStage = 1; idleState.phaseT = 0
                bagHop(sim, to: goal, ground: ScooterTuning.deckTop, apex: 0.16, facing: h0)
            }
        case 10: scooterReady(sim, skinner, dt, f)
        case 11: scooterRide(sim, skinner, dt, f)
        case 12:
            // rolled to a stop on the parking spot: a beat, then hop off
            standOnDeck(f, s: ride.s, k: 1)
            if idleState.phaseT > 0.5 { scooterDismount(sim, f) }
        case 13: scooterReturn(sim, skinner, dt, f)
        case 16: scooterRollHome(sim, skinner, dt, f)
        default: break
        }
    }

    /// Both soles on the deck under him, root on the deck's stance spot at `s`, the scooter at `s`.
    private func standOnDeck(_ f: DecorFoot, s: Float, k: Float) {
        let r = scooterRoot(s)
        px = r.p.x; pz = r.p.y; yaw = r.h
        for i in 0..<2 { feet.pos[i] = r.p + rotXZ(geom.off[i], yaw); feet.yaw[i] = yaw }
        feet.reset(); stepLive = false
        placeScooter(f, s: s)
        bagFloorOn = true; slideY = ScooterTuning.deckTop
    }
    /// The scooter's piece follows the loop (`carried`: it is drawn at `pos`, heading `heading`).
    private func placeScooter(_ f: DecorFoot, s: Float) {
        guard var a = DecorField.shared.anim[f.uid] else { return }
        let at = scooterAt(s)
        a.carried = true; a.pos = at.p
        a.heading = atan2f(-cosf(at.h), sinf(at.h)) - f.yaw
        a.wheel = s / ScooterTuning.wheelR
        a.steer = max(-1, min(1, ride.kappa * 0.9)) * min(1, ride.v / ScooterTuning.vmax) * 0.5
        DecorField.shared.setAnim(f.uid, a)
    }

    private func scooterReady(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) {
        if !ride.planned {
            // first step on the deck: plan the loop
            let probe = PerfProbe.begin(); defer { PerfProbe.end("scooterPlan", probe) }
            ride.planned = true
            idleState.phaseT = 0
            ride.start = DecorField.shared.position(f)
            ride.h0 = scooterHeading(f)
            ride.s = 0; ride.v = 0; ride.waitT = 0; ride.bobT = 0; ride.t = 0
            ride.peerSeen = [Bool](repeating: false, count: 8)
            var planned = false
            outer: for avoid in [true, false] {
                for margin: Float in [0.22, 0.05] {
                    for r in ScooterTuning.radii {
                        let first: Float = rand() < 0.5 ? 1 : -1
                        for side in [first, -first] {
                            let kappa = side / r
                            if scooterLoopFree(f, kappa: kappa, margin: margin, avoidPeers: avoid) { ride.kappa = kappa; ride.total = 2 * .pi * r; planned = true; break outer }
                        }
                    }
                }
            }
            if !planned { ride.noLoop += 1; ride.kappa = 1; ride.total = 0; idleState.hold = -1 }
            else { idleState.hold = 0.45 }
        }
        standOnDeck(f, s: 0, k: 1)
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        scooterArms()
        if idleState.hold < 0 { if idleState.phaseT > 0.5 { scooterDismount(sim, f) }; return }          // (no free loop: a beat on the deck, then off)
        if idleState.phaseT >= idleState.hold || idleState.yielding {
            if idleState.yielding { scooterDismount(sim, f); return }
            idleState.slideStage = 11; idleState.phaseT = 0; ride.rides += 1
            postEvent(.slid, piece: .kickscooter)
            AudioHub.shared.play(.sparkle, jelly: steerID, x: px, volume: 0.6, rate: 1.35)
        }
    }

    /// Arms forward and low, resting toward the grips (the cap keeps them thumbs).
    private func scooterArms() {
        armWalkWant = 1
        armDirW = 1; armDirEl = [0.5, 0.5]; armDirSa = [0.12, 0.12]; armDirOut = 0.05
    }

    /// 0...1: how freely he may roll on at `s` given every other Jelly (where they are and where they are going). Also records the closest approach.
    private func scooterFreeWay(_ f: DecorFoot, s: Float, v: Float, dt: Float, tracking: Bool = true, root: Bool = true) -> Float {
        let probe = PerfProbe.begin(); defer { PerfProbe.end("scooterFreeWay", probe) }
        var factor: Float = 1
        let stop = peerGap * 1.03, span = peerGap * 0.9
        let vv = max(v, 0.8)
        let me = root ? scooterRoot(s).p : scooterAt(s).p
        for o in socialOthers() where o !== self {
            let pos = o.position
            let i = o.steerID & 7
            var vel = SIMD2<Float>.zero
            if ride.peerSeen[i], dt > 1e-5 { vel = (pos - ride.peerPrev[i]) / dt; let l = simd_length(vel); if l > 3 { vel *= 3 / l } }
            ride.peerPrev[i] = pos; ride.peerSeen[i] = true
            let dNow = simd_distance(me, pos)
            if tracking { ride.minGap = min(ride.minGap, dNow) }
            var fo: Float = (dNow - stop) / span
            for tau: Float in [0.2, 0.5, 0.9] {
                let sf = s + vv * tau
                let mp = root ? scooterRoot(sf).p : scooterAt(sf).p
                let q = pos + vel * tau
                fo = min(fo, (simd_distance(mp, q) - stop) / span + (tau - 0.2) * 0.15)
            }
            factor = min(factor, fo)
        }
        return max(0, min(1, factor))
    }

    private func scooterRide(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) {
        ride.t += dt
        // the ride is cut short (a touch, a request): roll to the end of the way back
        if idleState.yielding { scooterBeginReturn(f); return }
        let free = scooterFreeWay(f, s: ride.s, v: ride.v, dt: dt)
        let remain = ride.total - ride.s
        var want = ScooterTuning.vmax * free
        want = min(want, max(0.3, sqrtf(2 * ScooterTuning.comfyBrake * max(remain, 0))))
        let dv = want - ride.v
        ride.v += max(-ScooterTuning.brake * dt, min(ScooterTuning.accel * dt, dv))
        if ride.v < 0.02 && want < 0.05 { ride.v = 0; ride.waitT += dt } else { ride.waitT = max(0, ride.waitT - dt * 0.5) }
        if ride.waitT > ScooterTuning.patience {
            ride.blocked += 1
            ride.blockNote += "[s \(ride.s) me \(scooterRoot(ride.s).p) others \(socialOthers().map { ($0.steerID, $0.position, $0.activity, String(describing: $0.idleState.kind)) })] "
 scooterBeginReturn(f); return }
        ride.s = min(ride.total, ride.s + ride.v * dt)
        ride.bobT += dt * ride.v / ScooterTuning.vmax
        standOnDeck(f, s: ride.s, k: 1)
        // the pose: a push bob (squash with the push rhythm), a lean into the turn, a faint pitch forward with speed
        let vn = ride.v / ScooterTuning.vmax
        let push = 0.5 + 0.5 * sinf(2 * .pi * ride.bobT / 0.95)
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        squash *= 1 - 0.045 * vn * push
        roll += -ride.kappa * 0.20 * vn * vn * (ScooterTuning.vmax * ScooterTuning.vmax) / 3.6 * 0.5
        pitch += 0.05 * vn
        jellyKick = max(jellyKick, 0.25 + 0.3 * vn * push)
        scooterArms()
        skinner.setEyeOpenness(1)
        if ride.s >= ride.total - 0.005 {
            ride.s = ride.total; ride.v = 0
            idleState.slideStage = 12; idleState.phaseT = 0
            placeScooterHome(f)
        }
    }

    /// The loop is closed: the scooter is exactly on its parking spot, pointing the way it did.
    private func placeScooterHome(_ f: DecorFoot) {
        guard var a = DecorField.shared.anim[f.uid] else { return }
        a.carried = true; a.pos = f.centre; a.heading = 0; a.steer = 0
        DecorField.shared.setAnim(f.uid, a)
        let r = scooterRoot(0)
        px = r.p.x; pz = r.p.y; yaw = r.h
        ride.s = 0
    }

    // MARK: blocked / cut short

    private func scooterBeginReturn(_ f: DecorFoot) {
        idleState.slideStage = 13; idleState.phaseT = 0; idleState.phase = 0
        ride.v = 0
        idleState.hop = 0
    }
    /// A ride that was given up: he brakes on the deck, hops off onto the nearest free floor (stage 15), and the scooter rolls back along the way it came (16).
    private func scooterReturn(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) {
        ride.v = max(0, ride.v - ScooterTuning.brake * dt)
        ride.s = min(ride.total, ride.s + ride.v * dt)
        standOnDeck(f, s: ride.s, k: 1)
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        scooterArms()
        if ride.v <= 0.01 && idleState.phaseT > 0.3 {
            let r = scooterRoot(ride.s)
            let side = SIMD2<Float>(cosf(r.h), -sinf(r.h)) * (ride.kappa > 0 ? -1 : 1)          // (outside the loop)
            let spot = decorFreeSpot(near: r.p + side * 1.1) ?? fixed(r.p)
            idleState.slideStage = 15; idleState.phaseT = 0
            bagHop(sim, to: spot, ground: 0, apex: 0.14, facing: faceCameraYaw())
        }
    }
    /// The scooter rolls home by itself along the loop (stopping for anybody in its way), then it is parked and he is done.
    private func scooterRollHome(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, _ f: DecorFoot) {
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        let free = scooterFreeWay(f, s: ride.s, v: 0.8, dt: dt, tracking: false, root: false)
        let want = (ride.s > 0.4 ? 1.3 : 0.5) * free
        ride.v += max(-ScooterTuning.brake * dt, min(1.5 * dt, want - ride.v))
        ride.s = max(0, ride.s - ride.v * dt)
        placeScooter(f, s: ride.s)
        if ride.s <= 0.001 || idleState.phaseT > 25 {
            scooterParked(f)
            idleState.slideStage = 0
            idleFinish(skinner)
        }
    }

    // MARK: ending

    func scooterDismount(_ sim: SoftBody, _ f: DecorFoot) {
        let spot = scooterExit(f)
        idleState.slideStage = 14; idleState.phaseT = 0
        bagHop(sim, to: spot, ground: 0, apex: 0.14, facing: faceCameraYaw())
    }
}
