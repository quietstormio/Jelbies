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
    enum Phase { case idle, crouch, air, land, roll, right, thrown, recover, glide, slide }
    enum Move { case hop, roll, flip, slide }

    // tuning
    var hopDuration: Float = 0.26     // fixed airtime (small and cute: motion table section 5)
    var hopApex: Float = 0.10         // fixed apex height of the centroid above its ground pose (0.075 H)
    var crouchTime: Float = 0.13
    var maxHop: Float = 1.6           // longest single hop
    /// Ground height the NEXT hop lands on (nil = the floor he is on): the beanbag hop onto / off a seat. `sim.floorY` itself is switched by the brain.
    var hopToGround: Float?
    var rollTravel: Float = 1.1       // distance covered by one roll
    var rollAngle: Float = 1.7        // radians tipped over before he rights himself
    var kHop: Float = 900             // attractor stiffness (1/s^2)
    var kRoll: Float = 700
    var kRecover: Float = 600
    var flingThreshold: Float = 2.0   // below this release speed a throw is just a gentle release
    var freeTime: Float = 1.05        // free flight after a fling
    var radius: Float = 1.2           // hop-around stays within this of `home`
    var wander = false                // "hop around"
    // backflip (voice trick, `flip(_:apex:)`): crouch, one full backward pitch about the centre of mass in the air, a big landing, then a short "covers it" shake
    static let flipGravity: Float = 12.4     // u/s^2 (the hop's)
    var flipCrouch: Float = 0.16
    var flipSettle: Float = 0.35             // the shake after the landing squash
    var flipSquashTime: Float = 0.15
    var kFlip: Float = 1000                  // stiffer than the hop so the rotation is followed (the soft body still jiggles on top)
    var flipApex: Float = 0.42
    /// `flipFail` = under-rotate and faceplant.
    /// Fraction of the stiff foot-sole targets used during a flip (1 = the full 60000: the soles snap onto the rigid pose and the catch-up is the fastest motion in the flip).
    static let flipFootGrip: Float = 0.15
    var flipFail = false
    /// Rotation (rad) of a clean flip / of the failed one (about 281 deg: he lands nose first).
    static let flipCleanTurn: Float = 2 * .pi
    static let flipFailTurn: Float = 4.9
    /// Faceplant timing (seconds into the landing phase): impact, lie, peel up, brush-off.
    static let fpImpact: Float = 0.14, fpLieEnd: Float = 0.64, fpPeelEnd: Float = 1.24, fpEnd: Float = 1.58
    // belly slide (idle move, `slide(_:to:yaw:)`): from a run he dives forward onto his belly, slides a short way on the front (decelerating from the
    // run's speed), pops back up with a little bounce and a wobble. Body-led: only the attractor, like the faceplant.
    static let slideDive: Float = 0.20, slideEnd: Float = 0.95, slidePopEnd: Float = 1.25, slideAll: Float = 1.70
    static let slidePitch: Float = 0.65     // rad forward (about 37 deg: belly toward the floor, crown leading)
    static let slideDist: Float = 0.9
    private(set) var slidePitchNow: Float = 0
    /// Seconds into the slide (the brain reads the dive impact / pop landing from it for the jelly kicks).
    private(set) var slideT: Float = 0
    var rollChance: Float = 0.45      // chance of a roll (instead of a hop) once three hops have passed

    // world
    var home = SIMD2<Float>(0, 0)
    /// Heading he returns to when resting (set from the camera azimuth: rest +z toward the camera).
    var facingYaw: Float = CameraRig.defaultAzimuth

    // state
    private(set) var phase: Phase = .idle
    /// How far the feet are tucked up toward the belly right now (world units): the sim soles only follow a few centimetres of it (the slab
    /// under a foot is 0.1 u tall); the brain draws the full tuck with the rigid render feet.
    private(set) var tuck: Float = 0
    var tuckHeight: Float = 0.05
    /// How far the SIM soles may follow the tuck (the slab is 0.1 u tall); kept public so a test can show what an unclamped tuck does.
    var simTuckCap: Float = 0.03
    private var move: Move = .hop
    private var t: Float = 0           // time in the current phase
    private var tMove: Float = 0       // time since the move began (crouch + air)
    private var from = SIMD2<Float>(0, 0)
    private var to = SIMD2<Float>(0, 0)
    private var yaw0: Float = 0
    private var yaw1: Float = 0
    private var rollDir = SIMD2<Float>(1, 0)
    private var groundFrom: Float = 0, groundTo: Float = 0      // ground heights at take-off / landing of the running hop (equal = an ordinary hop)
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
    /// Tip-back (rad, about his x axis, applied inside the heading) the brain asks for while he hops: the hop used to flatten the game's idle
    /// tip-back to upright, which makes the brows read angry from the camera.
    var basePitch: Float = 0
    /// Flip only: the extra pitch (rad, negative = backward) about his x axis on top of `basePitch`. 0 outside a flip.
    private(set) var flipPitch: Float = 0
    /// Flip only: seconds since the flip began / the airborne window (tests, haptics).
    private(set) var flipClock: Float = 0
    /// Flip only: progress through the air phase (0...1), through the rotation (0...1), and seconds in the landing phase (tests, arms).
    private(set) var flipU: Float = 0
    private(set) var flipV: Float = 0
    private(set) var flipLandT: Float = 0
    /// Flip only: seconds spent holding the crouch / since the give-up stand began.
    /// Flip only: true while he waits in the held crouch.
    var isFlipFaceplant: Bool { move == .flip && flipFail }
    /// A flip or cartwheel owns the body (the beans stay in their leg shape in its air / landing phases: BlobBrain.driveBeansRigid).
    var isSpinMove: Bool { move == .flip }
    /// Cartwheel only (W2, 2026-10-22): +1 / -1 = a flip taken sideways about his forward axis, travelling toward his right / left (0 = a normal backflip).
    private(set) var cartSide: Float = 0
    private func yawQ(_ y: Float) -> simd_quatf {
        let q = simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0))
        if cartSide != 0 {
            let p = basePitch + slidePitchNow
            let qp = p == 0 ? q : q * simd_quatf(angle: p, axis: SIMD3<Float>(1, 0, 0))
            return qp * simd_quatf(angle: cartSide * flipPitch, axis: SIMD3<Float>(0, 0, 1))
        }
        let p = basePitch + flipPitch + slidePitchNow
        return p == 0 ? q : q * simd_quatf(angle: p, axis: SIMD3<Float>(1, 0, 0))
    }
    /// Rotation progress 0...1 for turn progress `v`: constant angular speed with a 10 % ease at each end (a trapezoid rate; the abrupt start of a
    /// linear turn was the fastest thing in the flip).
    static func flipProfile(_ v: Float) -> Float {
        let a: Float = 0.10, x = min(1, max(0, v))
        if x < a { return 0.5 * x * x / (a * (1 - a)) }
        if x > 1 - a { return 1 - 0.5 * (1 - x) * (1 - x) / (a * (1 - a)) }
        return (x - a / 2) / (1 - a)
    }
    /// Airtime of a flip with this apex under the hop's gravity.
    static func flipAir(apex: Float) -> Float { 2 * (2 * apex / flipGravity).squareRoot() }
    private func yawEase(_ u: Float) -> Float { yaw0 + wrap(yaw1 - yaw0) * smooth(u) }

    // MARK: control

    mutating func start(_ sim: SoftBody) {
        phase = .idle; waitTimer = 0.4; hopsSinceRoll = 0
        sim.attractor.strength = 0
    }

    mutating func cancel(_ sim: SoftBody) {
        phase = .idle; chained = false; tuck = 0; flipPitch = 0; slidePitchNow = 0; slideT = 0; flipFail = false; cartSide = 0
        sim.attractor.strength = 0
        if !sim.targets.isEmpty { sim.targets = [] }
    }

    /// A backflip on the spot (apex in world units). Ignored while a move is running.
    mutating func flip(_ sim: SoftBody, apex: Float, reduceMotion: Bool = false, fail: Bool = false) {
        guard phase == .idle || phase == .recover || phase == .glide || phase == .land else { return }
        reduce = reduceMotion
        flipApex = apex
        flipFail = fail
        flipU = 0; flipV = 0; flipLandT = 0
        let pose = sim.bodyPose(iterations: 6)
        from = SIMD2(pose.centroid.x, pose.centroid.z)
        to = from
        yaw0 = pose.yaw; yaw1 = yaw0
        move = .flip; phase = .crouch; t = 0; tMove = 0; chained = false; flipPitch = 0; flipClock = 0
        sim.attractor.rotation = yawQ(yaw0)
    }

    /// A cartwheel (W2): the flip's machinery taken sideways. `side` +1 = toward his right (body x), -1 = left; he travels `travel` u across the air phase and lands there on both feet.
    mutating func cartwheel(_ sim: SoftBody, apex: Float, side: Float, travel: Float, reduceMotion: Bool = false) {
        guard phase == .idle || phase == .recover || phase == .glide || phase == .land else { return }
        reduce = reduceMotion
        flipApex = apex
        flipFail = false
        flipU = 0; flipV = 0; flipLandT = 0
        let pose = sim.bodyPose(iterations: 6)
        from = SIMD2(pose.centroid.x, pose.centroid.z)
        yaw0 = pose.yaw; yaw1 = yaw0
        let right = SIMD2<Float>(cosf(yaw0), -sinf(yaw0))
        to = from + right * side * travel
        cartSide = side
        move = .flip; phase = .crouch; t = 0; tMove = 0; chained = false; flipPitch = 0; flipClock = 0
        sim.attractor.rotation = yawQ(yaw0)
    }

    /// The belly slide: dive, slide to `target` (ground x, z), pop up. Ignored while a move is running.
    mutating func slide(_ sim: SoftBody, to target: SIMD2<Float>, yaw: Float) {
        guard phase == .idle || phase == .recover || phase == .glide || phase == .land else { return }
        reduce = false
        let pose = sim.bodyPose(iterations: 6)
        from = SIMD2(pose.centroid.x, pose.centroid.z)
        to = target
        yaw0 = yaw; yaw1 = yaw
        move = .slide; phase = .slide; t = 0; tMove = 0; chained = false; slidePitchNow = 0; slideT = 0
        sim.attractor.rotation = yawQ(yaw0)
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
        groundFrom = sim.floorY; groundTo = hopToGround ?? sim.floorY; hopToGround = nil
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
            let tc = move == .flip ? flipCrouch : (chained ? crouchTime * 0.4 : crouchTime * (move == .roll ? 1.3 : 1))
            let u = t / tc
            let sy = 1 - (move == .flip ? 0.24 : 0.18) * amp * smooth(u)
            let k = (move == .flip ? kFlip : kHop) * min(1, t / 0.06)
            let yawNow = move == .flip ? yaw0 : yawEase(t / (tc + 0.3))
            if move == .flip { flipClock = min(t, tc) }
            setUpright(sim, xz: from, yaw: yawNow, squash: sy, lift: 0, strength: k)
            if move == .flip { tuckFeet(sim, u: 0, amp: 0, ramp: Self.flipFootGrip * smooth(t / tc)) }       // the soles follow the squashed rigid pose from the start of the crouch
            if t >= tc { phase = move == .roll ? .roll : .air; t = 0; tMove = tc }

        case .slide:
            slideT = t
            let dive = Self.slideDive, glideEnd = Self.slideEnd, popEnd = Self.slidePopEnd
            let P = Self.slidePitch
            var pitch: Float = 0, sy: Float = 1, dip: Float = 0, lift: Float = 0
            let u = min(1, t / glideEnd)
            let xz = from + (to - from) * (1 - (1 - u) * (1 - u))            // decelerating from the run's speed
            if t < dive {
                let a = smooth(t / dive)
                pitch = P * a; sy = 1 - 0.08 * a
            } else if t < glideEnd {
                let s = t - dive
                pitch = P * (1 + 0.025 * expf(-s / 0.15) * cosf(2 * .pi * 5 * s))
                sy = 0.92 - 0.02 * expf(-s / 0.12) * cosf(2 * .pi * 6 * s)
                dip = 0.01
            } else if t < popEnd {
                let a = (t - glideEnd) / (popEnd - glideEnd), e = smooth(a)       // body-led peel up with a little hop
                pitch = P * (1 - e)
                sy = 0.92 + 0.08 * e + 0.05 * sinf(.pi * a)
                lift = 0.07 * sinf(.pi * a)
            } else {
                let s = t - popEnd
                pitch = -0.07 * expf(-s / 0.16) * sinf(2 * .pi * 6 * s)
                sy = 1 - 0.10 * expf(-s / 0.14) * cosf(2 * .pi * 5 * s)
            }
            slidePitchNow = pitch
            let q = yawQ(yaw0)
            sim.attractor.rotation = q
            sim.attractor.squash = sy
            sim.attractor.anchor = SIMD3(xz.x, sim.groundedAnchorY(rotation: q, squash: sy) - dip + lift, xz.y)
            let fade = 1 - smooth((t - (Self.slideAll - 0.15)) / 0.15)
            sim.attractor.strength = kFlip * max(0, fade)
            if t >= Self.slideAll { endMove(sim) }

        case .air where move == .flip:
            let apex = flipApex * amp
            let T = Self.flipAir(apex: apex) * (reduce ? 1.15 : 1)
            tMove += dt; flipClock = flipCrouch + t
            let u = min(1, t / T)
            flipU = u
            let h = apex * 4 * u * (1 - u)
            // one backward turn spread over nearly the whole air time (a mostly linear profile keeps the peak speed down); the clean one is
            // finished a hair before touch-down so he lands upright, the failed one arrives at touch-down still turning slowly
            let turn = flipFail ? Self.flipFailTurn : Self.flipCleanTurn
            let v = flipFail ? min(1, max(0, u / 0.995)) : min(1, max(0, u / 0.995))
            flipV = v
            flipPitch = -turn * Self.flipProfile(v)
            // a touch of stretch at take-off, a subtle tuck through the turn, open again to land
            // (the squash rises out of the crouch's over 0.10 s: a jump from 0.76 to 1.05 in one step is the fastest thing in the whole flip)
            let crouchSy = 1 - 0.24 * amp
            let stretch = 1 + 0.05 * amp * (1 - smooth(t / 0.14))
            let launch = crouchSy + (stretch - crouchSy) * smooth(t / 0.10)
            let sy = launch - 0.06 * amp * sinf(.pi * v)
            let xzAir = cartSide != 0 ? from + (to - from) * smooth(u) : from
            setUpright(sim, xz: xzAir, yaw: yaw0, squash: sy, lift: h + sim.restCentroid.y * 0.06 * amp * sinf(.pi * v), strength: kFlip)       // the tuck lowers the centre: lift it back so the apex is the centre's (only the tuck: the crouch's squash rises out of the floor by itself, not in one step)
            // 2026-10-25 (legs2): NO sim-sole targets in the air. They pulled the foot slab toward the ATTRACTOR's pose while the soft body lags it by tens of
            // degrees in a flip / cartwheel, so the embedded feet stretched off the surface ("feet come off"). The feet are the rigid beans there (`beanForce`).
            if !sim.targets.isEmpty { sim.targets = [] }; tuck = 0
            if t >= T { phase = .land; t = 0; sim.targets = []; tuck = 0; flipLandT = 0; if !flipFail { flipPitch = 0 }; if cartSide != 0 { from = to } }

        case .land where move == .flip && flipFail:
            // faceplant: nose-first impact (the body presses into the floor: front squash), a beat lying there, a body-led push back up onto the
            // feet (the same backward direction, so it is a push-up pivoting on the feet), then the "covers it" brush-off shake
            flipClock = flipCrouch + Self.flipAir(apex: flipApex * amp) * (reduce ? 1.15 : 1) + t
            flipLandT = t
            let impact = Self.fpImpact, lieEnd = Self.fpLieEnd, peelEnd = Self.fpPeelEnd, end = Self.fpEnd
            let down = -Self.flipFailTurn
            var pitch = down, sy: Float = 1, dip: Float = 0
            if t < impact {
                let a = smooth(t / impact)
                sy = 1 - 0.10 * amp * a
                dip = 0.07 * amp * a
            } else if t < lieEnd {
                let s = t - impact
                dip = 0.07 * amp * (0.45 + 0.55 * expf(-s / 0.12) * cosf(2 * .pi * 3.5 * s))      // a rebound, then the weight just rests
                sy = 1 - 0.10 * amp * (0.4 + 0.6 * expf(-s / 0.12))
            } else if t < peelEnd {
                let u = (t - lieEnd) / (peelEnd - lieEnd)
                // body-led: slow start (the weight shifts), then up, easing into upright
                let e = smooth(u)
                pitch = down - (Self.flipCleanTurn + down) * e
                dip = 0.03 * amp * (1 - smooth(u * 2))
                sy = 1 - 0.05 * amp * sinf(.pi * u)
            } else {
                let s = t - peelEnd
                pitch = -Self.flipCleanTurn + 0.06 * amp * expf(-s / 0.14) * sinf(2 * .pi * 8 * s)
                sy = 1 - 0.04 * amp * expf(-s / 0.12) * cosf(2 * .pi * 6 * s)
            }
            flipPitch = pitch
            let fade = 1 - smooth((t - (end - 0.15)) / 0.15)
            let q = yawQ(yaw0)
            sim.attractor.rotation = q
            sim.attractor.squash = sy
            sim.attractor.anchor = SIMD3(from.x, sim.groundedAnchorY(rotation: q, squash: sy) - dip, from.y)
            sim.attractor.strength = kFlip * max(0, fade)
            if t >= end { flipPitch = 0; flipFail = false; endMove(sim) }

        case .land where move == .flip:
            flipClock = flipCrouch + Self.flipAir(apex: flipApex * amp) * (reduce ? 1.15 : 1) + t
            flipLandT = t
            // a big squash, a quick rebound, then the shake: a tiny yaw / squash wobble that dies out ("covers it")
            let sq = flipSquashTime
            var sy: Float, jig: Float = 0
            if t < sq { sy = t < 0.05 ? 1 - 0.26 * smooth(t / 0.05) : 0.74 + 0.26 * smooth((t - 0.05) / (sq - 0.05)) }       // (it dips from 1.0 over 0.05 s: one step from 1 to 0.74 was a 12.6 u/s spike)
            else { let s = t - sq; sy = 1 - 0.035 * amp * expf(-s / 0.12) * cosf(2 * .pi * 6 * s); jig = 0.045 * amp * expf(-s / 0.16) * sinf(2 * .pi * 9 * s) }
            let fade = 1 - smooth((t - (sq + flipSettle - 0.15)) / 0.15)
            flipPitch = jig
            setUpright(sim, xz: from, yaw: yaw0, squash: sy, lift: 0, strength: kFlip * max(0, fade))
            if t >= sq + flipSettle { flipPitch = 0; endMove(sim) }

        case .air:
            let T = hopDuration * (reduce ? 1.25 : 1), apex = hopApex * amp
            tMove += dt
            let u = min(1, t / T)
            let h = apex * 4 * u * (1 - u)
            let vy = 4 * apex * (1 - 2 * u) / T, vy0 = 4 * apex / T
            let stretch = 1 + 0.12 * amp * min(1, abs(vy) / max(vy0, 1e-3))
            let crouchSy = 1 - 0.18 * amp
            let sy = crouchSy + (stretch - crouchSy) * smooth(t / 0.08)
            let xz = from + (to - from) * u
            let yawNow = yawEase(tMove / (crouchTime + 0.3))
            // a hop up onto a seat rises early (over its edge), a hop down drops late: the ground under him eases from take-off to landing height
            let ge = groundTo >= groundFrom ? 1 - (1 - u) * (1 - u) : u * u
            let gOff = groundFrom + (groundTo - groundFrom) * ge - sim.floorY
            setUpright(sim, xz: xz, yaw: yawNow, squash: sy, lift: h + gOff, strength: kHop)
            tuckFeet(sim, u: u, amp: amp)
            if t >= T { phase = .land; t = 0; sim.targets = []; tuck = 0 }

        case .land:
            let amp2 = amp
            // squash on impact (0.80), then a decaying 5 Hz jiggle (1.06 -> 0.97 -> 1.0)
            let sy = 1 - 0.2 * amp2 * expf(-t / 0.08) * cosf(2 * .pi * 5 * t)
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
            if t >= 0.55 { endMove(sim) }

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
        phase = .idle; chained = false; tuck = 0; flipPitch = 0; slidePitchNow = 0; cartSide = 0
        sim.attractor.strength = 0
        sim.targets = []
        waitTimer = (0.25 + 0.45 * rand()) * (reduce ? 1.4 : 1)
    }

    /// Feet tucked up toward the belly while he is in the air (the only time both feet may leave the floor).
    private mutating func tuckFeet(_ sim: SoftBody, u: Float, amp: Float, ramp: Float = 1) {
        tuck = tuckHeight * amp * sinf(.pi * min(1, max(0, u)))
        let simTuck = min(tuck, simTuckCap)
        let q = sim.attractor.rotation, sy = sim.attractor.squash, sxz = 1 / sy.squareRoot()
        let R = simd_float3x3(q), c0 = sim.restCentroid
        var list: [ParticleTarget] = []
        for a in sim.appendages where a.kind == .foot {
            for p in a.particles {
                let o = sim.restPosition(p) - c0
                let w = sim.attractor.anchor + R * SIMD3<Float>(o.x * sxz, o.y * sy, o.z * sxz) + SIMD3<Float>(0, simTuck, 0)
                list.append(ParticleTarget(index: p, pos: w, stiffness: 60000 * ramp))
            }
        }
        sim.targets = list
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
