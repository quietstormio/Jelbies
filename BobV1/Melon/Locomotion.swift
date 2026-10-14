//
//  Locomotion.swift
//  Bob's gaits as scripted poses for SoftBody's rigid-pose attractor (see `Attractor`): hop, roll, throw-and-return.
//  The driver is ticked once per fixed sim step (so it honours pause and quarter speed). It only ever writes
//  `sim.attractor` (anchor, target rotation, squash, strength) and, for throws, `sim.launch`; the soft body itself
//  supplies the stretch / squash / wobble.
//
//  Public entry points for later installs (feeding, petting, tricks, ...):
//    hop(sim, to:)          one scripted hop to a ground point
//    roll(sim, toward:)     one tipping roll (sideways to his facing), then rights himself
//    throwBody(sim, velocity:)  fling: free flight, then bounce / roll home
//    returnHome(sim)        soft return after a gentle release
//    cancel(sim)            drop any script (attractor off, free physics)
//    wander                 true = "hop around": hops with an occasional roll, staying near `home`
//

import Foundation
import simd

struct GaitDriver {
    enum Phase { case idle, crouch, air, land, roll, right, thrown, recover, glide }
    enum Move { case hop, roll }

    // tuning
    var hopDuration: Float = 0.5      // fixed airtime
    var hopApex: Float = 0.6          // fixed apex height of the centroid above its ground pose
    var crouchTime: Float = 0.14
    var maxHop: Float = 1.6           // longest single hop
    var rollTravel: Float = 1.1       // distance covered by one roll
    var rollAngle: Float = 1.7        // radians tipped over before he rights himself
    var kHop: Float = 900             // attractor stiffness (1/s^2)
    var kRoll: Float = 700
    var kRecover: Float = 600
    var flingThreshold: Float = 2.0   // below this release speed a throw is just a gentle release
    var freeTime: Float = 1.05        // free flight after a fling
    var radius: Float = 1.2           // hop-around stays within this of `home`
    var wander = false                // "hop around"
    var rollChance: Float = 0.45      // chance of a roll (instead of a hop) once three hops have passed

    // world
    var home = SIMD2<Float>(0, 0)
    /// Heading he returns to when resting (set from the camera azimuth: rest +z toward the camera).
    var facingYaw: Float = CameraRig.defaultAzimuth

    // state
    private(set) var phase: Phase = .idle
    private var move: Move = .hop
    private var t: Float = 0           // time in the current phase
    private var tMove: Float = 0       // time since the move began (crouch + air)
    private var from = SIMD2<Float>(0, 0)
    private var to = SIMD2<Float>(0, 0)
    private var yaw0: Float = 0
    private var yaw1: Float = 0
    private var rollDir = SIMD2<Float>(1, 0)
    private var chained = false
    private var reduce = false
    private var waitTimer: Float = 0.4
    private var hopsSinceRoll = 0
    private var seed: UInt64 = 0x9E3779B97F4A7C15

    var isBusy: Bool { phase != .idle }
    var isFlying: Bool { phase == .thrown }

    // MARK: helpers

    private mutating func rand() -> Float {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Float(seed >> 40) / Float(1 << 24)
    }
    private func smooth(_ x: Float) -> Float { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }
    private func wrap(_ a: Float) -> Float {
        var d = a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
    private func yawQ(_ y: Float) -> simd_quatf { simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0)) }
    private func yawEase(_ u: Float) -> Float { yaw0 + wrap(yaw1 - yaw0) * smooth(u) }

    // MARK: control

    mutating func start(_ sim: SoftBody) {
        phase = .idle; waitTimer = 0.4; hopsSinceRoll = 0
        sim.attractor.strength = 0
    }

    mutating func cancel(_ sim: SoftBody) {
        phase = .idle; chained = false
        sim.attractor.strength = 0
    }

    /// One scripted hop to the ground point `target` (x, z). Ignored while a move is running.
    mutating func hop(_ sim: SoftBody, to target: SIMD2<Float>, reduceMotion: Bool = false, chained: Bool = false) {
        guard phase == .idle || phase == .recover || phase == .glide || phase == .land else { return }
        reduce = reduceMotion
        let pose = sim.bodyPose(iterations: 6)
        from = SIMD2(pose.centroid.x, pose.centroid.z)
        var d = target - from
        let dl = simd_length(d)
        if dl > maxHop { to = from + d / dl * maxHop } else { to = target }
        d = to - from
        yaw0 = pose.yaw
        yaw1 = simd_length(d) > 1e-3 ? atan2f(d.x, d.y) : yaw0
        move = .hop; phase = .crouch; t = 0; tMove = 0
        self.chained = chained
        sim.attractor.rotation = yawQ(yaw0)
    }

    /// One tipping roll along `dir` (a horizontal x, z direction; it is projected sideways to his facing).
    mutating func roll(_ sim: SoftBody, toward dir: SIMD2<Float>, reduceMotion: Bool = false) {
        guard phase == .idle || phase == .glide || phase == .land else { return }
        reduce = reduceMotion
        let pose = sim.bodyPose(iterations: 6)
        from = SIMD2(pose.centroid.x, pose.centroid.z)
        let right = SIMD2<Float>(cosf(facingYaw), -sinf(facingYaw))
        rollDir = simd_dot(dir, right) >= 0 ? right : -right
        to = from + rollDir * rollTravel
        yaw0 = pose.yaw; yaw1 = facingYaw
        move = .roll; phase = .crouch; t = 0; tMove = 0; chained = false
        sim.attractor.rotation = yawQ(yaw0)
    }

    /// Fling: the body gets `velocity` (and a rolling spin), the attractor stays off for `freeTime`, then he rights
    /// himself and bounces / rolls back to `home`. A slow release just returns him softly.
    mutating func throwBody(_ sim: SoftBody, velocity: SIMD3<Float>) {
        var v = velocity
        let sp = simd_length(v)
        if sp > 9 { v *= 9 / sp }
        if simd_length(v) < flingThreshold { returnHome(sim); return }
        let spin = simd_cross(SIMD3<Float>(0, 1, 0), v) * (0.5 / BobShape.R)
        sim.attractor.strength = 0
        sim.launch(velocity: v, spin: spin)
        phase = .thrown; t = 0; chained = false
    }

    /// Soft return after a gentle release (no free flight): rights him, then glides or hops back to `home`.
    mutating func returnHome(_ sim: SoftBody) {
        let pose = sim.bodyPose(iterations: 8)
        let off = SIMD2(pose.centroid.x, pose.centroid.z) - home
        if simd_length(off) < 0.12 && pose.tilt < 0.12 { phase = .idle; sim.attractor.strength = 0; return }
        beginRecover(sim, pose: pose)
    }

    private mutating func beginRecover(_ sim: SoftBody, pose: BodyPose) {
        sim.attractor.rotation = pose.rotation
        sim.attractor.anchor = pose.centroid
        sim.attractor.squash = 1
        sim.attractor.strength = 0
        phase = .recover; t = 0
    }

    // MARK: tick

    /// Call once before each fixed sim step.
    mutating func tick(_ sim: SoftBody, held: Bool, reduce rm: Bool) {
        let dt = sim.stepDt
        if held { cancel(sim); waitTimer = max(waitTimer, 1.0); return }
        reduce = rm
        t += dt
        let c0y = sim.restCentroid.y
        let amp: Float = reduce ? 0.55 : 1
        switch phase {
        case .idle:
            if wander {
                waitTimer -= dt
                if waitTimer <= 0 { nextMove(sim) }
            }

        case .crouch:
            tMove = t
            let tc = chained ? crouchTime * 0.4 : crouchTime * (move == .roll ? 1.3 : 1)
            let u = t / tc
            let sy = 1 - 0.22 * amp * smooth(u)
            let k = kHop * min(1, t / 0.06)
            let yawNow = yawEase(t / (tc + 0.3))
            setUpright(sim, xz: from, yaw: yawNow, squash: sy, lift: 0, strength: k)
            if t >= tc { phase = move == .roll ? .roll : .air; t = 0; tMove = tc }

        case .air:
            let T = hopDuration * (reduce ? 1.25 : 1), apex = hopApex * amp
            tMove += dt
            let u = min(1, t / T)
            let h = apex * 4 * u * (1 - u)
            let vy = 4 * apex * (1 - 2 * u) / T, vy0 = 4 * apex / T
            let stretch = 1 + 0.2 * amp * min(1, abs(vy) / max(vy0, 1e-3))
            let crouchSy = 1 - 0.22 * amp
            let sy = crouchSy + (stretch - crouchSy) * smooth(t / 0.08)
            let xz = from + (to - from) * u
            let yawNow = yawEase(tMove / (crouchTime + 0.3))
            setUpright(sim, xz: xz, yaw: yawNow, squash: sy, lift: h, strength: kHop)
            if t >= T { phase = .land; t = 0 }

        case .land:
            let amp2 = amp
            // squash on impact (1.2 -> 0.8 over 70 ms), then ease back to 1
            let sy: Float
            if t < 0.07 { sy = 1 + 0.2 * amp2 - 0.4 * amp2 * smooth(t / 0.07) }
            else { sy = 1 - 0.2 * amp2 * (1 - smooth((t - 0.07) / 0.33)) }
            let faceT = chained ? 0 : smooth((t - 0.1) / 0.4)
            let yawNow = yaw1 + wrap(facingYaw - yaw1) * faceT
            let k = kHop * (1 - smooth((t - 0.4) / 0.25))
            setUpright(sim, xz: to, yaw: yawNow, squash: sy, lift: 0, strength: k)
            if chained, t >= 0.1 {
                let here = to
                let rem = home - here
                if simd_length(rem) > 0.1 { hop(sim, to: home, reduceMotion: reduce, chained: true); return }
                chained = false
            }
            if t >= 0.65 { endMove(sim) }

        case .roll:
            let T: Float = 0.75
            let u = min(1, t / T)
            let th = rollAngle * smooth(u)
            let xz = from + (to - from) * smooth(u)
            setTilted(sim, xz: xz, theta: th, strength: kRoll)
            if t >= T { phase = .right; t = 0 }

        case .right:
            let T: Float = 0.6
            let u = min(1, t / T)
            // ease-out-back: overshoots a little past upright and settles
            let c1: Float = 1.70158, c3 = c1 + 1
            let e = 1 + c3 * powf(u - 1, 3) + c1 * powf(u - 1, 2)
            let th = rollAngle * (1 - e)
            let k = kRoll * (1 - smooth((t - 0.35) / 0.25))
            setTilted(sim, xz: to, theta: th, strength: k)
            if t >= T { endMove(sim) }

        case .thrown:
            sim.attractor.strength = 0
            if t >= freeTime { beginRecover(sim, pose: sim.bodyPose(iterations: 8)) }

        case .recover:
            // the target rotates up to upright at a limited rate (so a tumbling body is rolled over, never passed
            // through itself); the anchor follows the body horizontally until he is upright
            let want = yawQ(facingYaw)
            let cur = sim.attractor.rotation
            let ang = 2 * acosf(min(1, abs(simd_dot(cur.vector, want.vector))))
            let step = 5.5 * dt
            sim.attractor.rotation = ang <= step ? want : simd_slerp(cur, want, step / ang)
            let pose = sim.bodyPose(iterations: 3)
            sim.attractor.anchor = SIMD3(pose.centroid.x, sim.groundedAnchorY(rotation: sim.attractor.rotation), pose.centroid.z)
            sim.attractor.squash = 1
            sim.attractor.strength = kRecover * smooth(t / 0.35)
            if t > 0.3 && ang <= step && pose.tilt < 0.35 {
                let off = SIMD2(pose.centroid.x, pose.centroid.z) - home
                let dist = simd_length(off)
                if dist > 0.5 { hop(sim, to: home, reduceMotion: reduce, chained: true) }
                else if dist > 0.04 { phase = .glide; t = 0 }
                else { phase = .glide; t = 0 }
            }

        case .glide:
            // upright, anchor eased toward home
            let a = sim.attractor.anchor
            let d = home - SIMD2(a.x, a.z)
            let dl = simd_length(d)
            let sp = min(1.4, 4 * dl) * dt
            let nxz = dl > 1e-5 ? SIMD2(a.x, a.z) + d / dl * min(sp, dl) : home
            let k = kRecover * (dl < 0.03 ? 1 - smooth((t - 0.2) / 0.3) : 1)
            sim.attractor.rotation = yawQ(facingYaw)
            sim.attractor.anchor = SIMD3(nxz.x, c0y, nxz.y)
            sim.attractor.squash = 1
            sim.attractor.strength = k
            if dl < 0.03 && t > 0.5 { endMove(sim) }
        }
    }

    private mutating func endMove(_ sim: SoftBody) {
        phase = .idle; chained = false
        sim.attractor.strength = 0
        waitTimer = (0.25 + 0.45 * rand()) * (reduce ? 1.4 : 1)
    }

    private func setUpright(_ sim: SoftBody, xz: SIMD2<Float>, yaw: Float, squash sy: Float, lift: Float, strength: Float) {
        // lowest point of the upright, squashed target sits on the floor (+ lift while he is in the air)
        sim.attractor.rotation = yawQ(yaw)
        sim.attractor.squash = sy
        sim.attractor.anchor = SIMD3(xz.x, sim.restCentroid.y * sy + lift + sim.floorY, xz.y)
        sim.attractor.strength = strength
    }

    private func setTilted(_ sim: SoftBody, xz: SIMD2<Float>, theta: Float, strength: Float) {
        // tip about the horizontal axis perpendicular to the roll direction, on top of the facing yaw
        let axis = simd_cross(SIMD3<Float>(0, 1, 0), SIMD3<Float>(rollDir.x, 0, rollDir.y))
        let q = simd_quatf(angle: theta, axis: axis) * yawQ(facingYaw)
        sim.attractor.rotation = q
        sim.attractor.squash = 1
        sim.attractor.anchor = SIMD3(xz.x, sim.groundedAnchorY(rotation: q), xz.y)
        sim.attractor.strength = strength
    }

    /// "Hop around": mostly hops, an occasional roll, staying within `radius` of `home`.
    private mutating func nextMove(_ sim: SoftBody) {
        if sim.minY() > 0.03 { waitTimer = 0.1; return }          // only start from the ground
        let pose = sim.bodyPose(iterations: 6)
        let here = SIMD2(pose.centroid.x, pose.centroid.z)
        let outside = simd_length(here - home) > radius - 0.3
        if hopsSinceRoll >= 3 && !reduce && rand() < rollChance {
            let right = SIMD2<Float>(cosf(facingYaw), -sinf(facingYaw))
            let dirs = [right, -right]
            let best = dirs.min { simd_length(here + $0 * rollTravel - home) < simd_length(here + $1 * rollTravel - home) }!
            if simd_length(here + best * rollTravel - home) < radius {
                hopsSinceRoll = 0
                roll(sim, toward: best, reduceMotion: reduce)
                return
            }
        }
        var target = home
        if !outside {
            for _ in 0..<8 {
                let a = rand() * 2 * .pi, rr = radius * (0.3 + 0.7 * rand()).squareRoot()
                let cand = home + SIMD2<Float>(sinf(a), cosf(a)) * rr
                if simd_length(cand - here) > 0.5 { target = cand; break }
            }
        }
        hopsSinceRoll += 1
        hop(sim, to: target, reduceMotion: reduce)
    }
}
