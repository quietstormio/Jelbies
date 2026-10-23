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
                    if o.idleState.kind == .sleep, simd_distance(o.sleep.spot, p) < SleepTuning.minGap { clash = true; break }
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
        if !sleepFloorOK(spot, relaxed: true), !c.joined, let f = forceSpot() { spot = f }
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
}
