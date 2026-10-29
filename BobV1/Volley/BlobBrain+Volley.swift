//
//  BlobBrain+Volley.swift
//  How a Jelbie PLAYS volleyball. Every move is the body, never the arms (they stay stubby; small flaps for balance only), and every move is the soft
//  body doing it: the attractor (the rigid pose the soft body is pulled to, as in the hop and the flip) is driven with squash, stretch, lean and lift, the
//  feet follow it (tucked in the air, the beans drawn rigid), and a hit is an IMPULSE INTO THE SOFT SIM at the contact point: the ball's sphere is pressed
//  into the body (`SoftBody.setPress`, held and eased off for a moment, so a dent opens and the jelly springs back), a damped squash pulse runs on top, and
//  JellyJiggle's kick rings the render-side wobble. Nothing deforms the base body.
//
//    ground   the locked walk gait: one committed step at a time, strafing along the net (stride and rate from the Speed stat, as racing does)
//    bonk     crouch (squash) -> spring up (stretch) -> the ball meets the crown, which dents -> fall -> landing squash and a 5 Hz settle wobble
//    spike    the bonk's jump, then in the air he turns to the net and tips forward onto his round front (the lean, a tuck), smacks the ball down, and
//             rights himself before the landing
//    dig      a low dive: a short crouch, a skimming launch with the front leading (up to ~65 deg of lean), a slide on the belly, a body-led peel back up
//             with a little bounce and a wobble
//    cheer    two happy hops
//

import Foundation
import simd

/// The volley state of one brain.
struct VolleyDrive {
    enum Phase { case ground, crouch, air, land, diveCrouch, dive, slide, peel }
    var active = false
    var side: Float = 1
    var restYaw: Float = VolleyTuning.restYaw
    var wantX: Float = 0
    var wantZ: Float = 0
    var block = false
    var stride: Float = 0.3, rate: Float = 3.6
    var phase: Phase = .ground
    var t: Float = 0
    var from = SIMD2<Float>.zero, to = SIMD2<Float>.zero
    var apex: Float = 0.5, airT: Float = 0.8
    var yaw0: Float = 0
    var spikeT: Float = -1
    var diveDir: Float = 1
    var tuck: Float = 0
    var cheerLeft = 0
    var press: (c: SIMD3<Float>, r: Float, t: Float)?
    var pressOn = false
    var recoil: Float = 0, recoilV: Float = 0
    var pitchNow: Float = 0
    var arm: (el: Float, sa: Float, out: Float) = (0.3, 0.1, 0.05)
    var armA: Float = 0
    var finished = false          // set when a jump / dive has ended (the glue tells the sim and clears it)
    var lastAir = false
    var steps = 0
    /// Where his partner's body is (the glue sets it every step; nil in a drill): steps, jumps and dives never end closer to it than `VolleyTuning.brainGap`.
    var mate: SIMD2<Float>?
}

extension BlobBrain {
    static let volleyPressTime: Float = 0.17
    static let volleyKHop: Float = 900

    var volleyAirborne: Bool { volley.active && volley.phase != .ground && volley.phase != .land }
    var volleyBusy: Bool { volley.active && volley.phase != .ground }

    // MARK: begin / end

    func volleyBegin(sim: SoftBody, skinner: Skinner, x: Float, z: Float, side: Float) {
        abortScript(sim, skinner)
        pending = nil; interruptScript = false
        autonomy = false; idleBlocked = false
        runW = 0; zoomW = 0; hurry = false
        sim.endPress()
        volley = VolleyDrive()
        volley.active = true; volley.side = side; volley.restYaw = side * VolleyTuning.restYaw; volley.wantX = x; volley.wantZ = z
        currentPose(sim)
        yaw = volley.restYaw
        nextSwing = 0
        script = .none; activity = .playing
    }

    func volleyEnd(sim: SoftBody, skinner: Skinner) {
        guard volley.active else { return }
        sim.endPress(); sim.targets = []
        sim.attractor.strength = 0
        volley = VolleyDrive()
        gait.basePitch = 0
        armDirW = 0; armDirOut = 0
        restTimer = 1.0
        currentPose(sim)
    }

    // MARK: commands

    func volleyWant(x: Float, z: Float = 0, speed: Float) {
        volley.wantX = ownSide(x); volley.wantZ = ownZ(z)
        volley.stride = VolleyTuning.stride(speed: speed)
        volley.rate = VolleyTuning.rate(speed: speed)
    }

    /// The jump of a bonk, a serve or a spike: crouch, spring, fall. `dx` is how far he travels along the sand while he is up.
    func volleyJump(sim: SoftBody, dx: Float, dz: Float = 0, apex: Float, cheer: Bool = false, block: Bool = false) {
        guard volley.active, volley.phase == .ground || volley.phase == .land else { return }
        releaseFeetForAir(sim)
        volley.phase = .crouch; volley.t = 0
        volley.from = SIMD2(px, pz); volley.to = volley.from + SIMD2(dx, dz); volley.to.x = ownSide(volley.to.x); volley.to.y = ownZ(volley.to.y); volley.block = block
        volley.to = clearOfMate(volley.to, from: volley.from)
        volley.apex = apex; volley.airT = VolleyTuning.airTime(apex: apex)
        volley.yaw0 = yaw; volley.spikeT = -1; volley.pitchNow = 0
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: cheer ? 0.5 : 0.8)
    }

    /// Tap again in the air: turn to the net and tip forward onto the front.
    func volleySpike() {
        guard volley.active, volley.phase == .air || volley.phase == .crouch, volley.spikeT < 0 else { return }
        volley.spikeT = 0
        jellyKick = max(jellyKick, 0.6)
    }

    /// The dig: a low dive toward `dir` (+1 / -1 along x).
    func volleyDive(sim: SoftBody, dir: Float) {
        guard volley.active, volley.phase == .ground || volley.phase == .land else { return }
        releaseFeetForAir(sim)
        volley.phase = .diveCrouch; volley.t = 0
        volley.from = SIMD2(px, pz)
        // near the net he dives away from it (the body never reaches the net plane)
        let netDir: Float = volley.side > 0 ? 1 : -1
        let room = (volley.side > 0 ? -VolleyTuning.netMargin - px : px - VolleyTuning.netMargin)
        volley.diveDir = (dir == netDir && room < 0.5) ? -dir : dir
        volley.yaw0 = yaw; volley.spikeT = -1
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.6, rate: 1.1)
    }

    func volleyCheer(sim: SoftBody) {
        volley.cheerLeft = 1
        face(.joyArc, hold: 1.6)
        if volley.phase == .ground { volleyJump(sim: sim, dx: 0, apex: 0.34, cheer: true) }
    }

    private func releaseFeetForAir(_ sim: SoftBody) {
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        poseW = 0; poseOn = false
        gait.wander = false
        let p = sim.centroid(); px = p.x; pz = p.z
    }

    /// The ball met the body: the impulse into the soft sim. `point` = the ball's centre (x, y), `normal` points from the body to the ball.
    func volleyImpact(sim: SoftBody, kind: VolleyHit, quality: VolleyQuality = .good, ball: SIMD2<Float>, normal: SIMD2<Float>, speed: Float) {
        guard volley.active else { return }
        let z = sim.centroid().z
        volley.press = (SIMD3(ball.x, ball.y, z), VolleyTuning.ballR * 0.97, Self.volleyPressTime)
        let hard: Float = kind == .spike ? 1.0 : kind == .block ? 0.95 : kind == .serve ? 0.8 : kind == .dig ? 0.7 : 0.6
        let perfect: Float = quality == .perfect ? 1.25 : quality == .good ? 1 : 0.8          // a Perfect hit squishes bigger, a weak one less
        volley.recoilV += hard * perfect * (kind == .spike ? 3.2 : 2.4)
        jellyKick = max(jellyKick, (kind == .spike || kind == .block ? 2.6 : kind == .dig ? 2.0 : 1.6) * (quality == .perfect ? 1.2 : 1))
        let big = kind == .spike || kind == .block
        AudioHub.shared.play(big ? .squish : .boop, jelly: steerID, x: px, volume: big ? 0.9 : 0.75, rate: kind == .dig ? 0.85 : 1)
        if quality == .perfect { AudioHub.shared.play(.sparkle, jelly: steerID, x: px, volume: 0.5) }
        face(big || quality == .perfect ? .joyArc : .excited, hold: 0.55)
    }

    // MARK: the tick (called from BlobBrain.tick before anything else owns the body)

    func volleyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        activity = .playing
        mouthOpen = 0
        volley.finished = false
        // the damped squash pulse of a hit (5.5 Hz) and the held dent
        let w = 2 * Float.pi * 5.5
        volley.recoilV += (-w * w * volley.recoil - 2 * 0.22 * w * volley.recoilV) * dt
        volley.recoil += volley.recoilV * dt
        if abs(volley.recoil) < 1e-4, abs(volley.recoilV) < 1e-3 { volley.recoil = 0; volley.recoilV = 0 }
        if var pr = volley.press, pr.t > 0 {
            pr.t -= dt
            let k = max(pr.t, 0) / Self.volleyPressTime
            sim.setPress(center: pr.c, radius: pr.r * (0.80 + 0.20 * k), slot: 0)
            volley.press = pr; volley.pressOn = true
        } else if volley.pressOn {
            sim.endPress(); volley.pressOn = false; volley.press = nil
        }
        switch volley.phase {
        case .ground: volleyGround(sim, skinner, dt)
        default: volleyAirTick(sim, skinner, dt)
        }
    }

    private func volleyGround(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        roll = 0; pitch = 0; squash = 1; lift = 0; twist = 0
        armWalkWant = 0
        pivotSide = nil; pivotNominal = false; nubTarget = 0
        feetDrive = true
        advanceGait(dt)
        let dp = -attentionPitch * amplitude - pitchBase
        pitchBase += max(-1.2 * dt, min(1.2 * dt, dp))
        poseOn = true; ensureFeet(sim)
        if !feet.active {
            let dv = SIMD2(volley.wantX - px, volley.wantZ - pz)
            let dl = simd_length(dv)
            if dl > 0.06 {
                let (dir, L) = clearOfMate(from: SIMD2(px, pz), dir: dv / dl, length: min(volley.stride, max(0.14, dl * 1.1)))
                if L > 0.04 { volleyStep(dir: dir, L: L, rate: volley.rate) }
            } else if abs(wrapAngle(volley.restYaw - yaw)) > 0.05 {
                _ = turnSteps(goal: volley.restYaw, tol: 0.05)
            }
        }
        let standing = !feet.active
        gaitPose(sway: standing ? 0.6 * waddleRoll : waddleRoll, bob: standing ? 0.03 : 0.12, rock: standing ? 0.5 : 1)
        armWalkWant = feet.active ? 1 : 0.5
        squash *= 1 - volley.recoil * 0.9
        lift -= volley.recoil * 0.02
        drivePose(sim, dt)
        driveLimbs(sim, skinner, dt)
    }

    /// One step of the locked gait along the net line (the strafing step: the root goes `dir` on the sand, the heading stays square to the net).
    private func volleyStep(dir: SIMD2<Float>, L: Float, rate: Float) {
        let root = SIMD2(px, pz)
        let u = dir
        let foot = nextSwing, stance = 1 - foot
        let s = simd_dot(feet.pos[stance] - (root + rotXZ(geom.off[stance], yaw)), u)
        let r = 0.5 * L
        let a = min(max(s + r, 0.3 * L), 1.5 * L)
        let m = turnRate * min(max(amplitude, 0.5), 1) * (1 / rate)
        let err = wrapAngle(volley.restYaw - yaw)
        volley.steps += 1
        startStep(rootD: u * a, dyaw: max(-m, min(m, err)), reach: u * r, peak: stepLift * amplitude, rate: rate, outScale: 0.6)
    }

    // MARK: jump, spike, dive, landing: the attractor

    private func yawQ(_ y: Float, pitch p: Float) -> simd_quatf {
        let q = simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0))
        return p == 0 ? q : q * simd_quatf(angle: p, axis: SIMD3<Float>(1, 0, 0))
    }
    /// The partner's body is a wall: a step that would end closer to it than `brainGap` (or than he is now, when that is nearer already) slides round it instead,
    /// so two teammates never walk into each other. Returns the direction and length of the step to take (length 0: stay).
    private func clearOfMate(from p: SIMD2<Float>, dir: SIMD2<Float>, length L: Float) -> (SIMD2<Float>, Float) {
        guard volley.mate != nil else { return (dir, L) }
        let to = clearOfMate(p + dir * L, from: p)
        let d = to - p, l = simd_length(d)
        return l < 1e-4 ? (dir, 0) : (d / l, l)
    }
    private func clearOfMate(_ q: SIMD2<Float>, from p: SIMD2<Float>) -> SIMD2<Float> {
        guard let m = volley.mate else { return q }
        return VolleyTuning.clearOfMate(q, from: p, mate: m, lane: volley.side)
    }
    /// Keeps a body's centre on its own side of the net with a margin (the body is ~1.1 wide).
    private func ownSide(_ x: Float) -> Float { volley.side > 0 ? min(x, -VolleyTuning.netMargin) : max(x, VolleyTuning.netMargin) }
    private func ownZ(_ z: Float) -> Float { min(max(z, -VolleyTuning.zLimit), VolleyTuning.zLimit) }
    private func ease(_ x: Float) -> Float { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }

    private func place(_ sim: SoftBody, xz: SIMD2<Float>, yaw y: Float, pitch p: Float, squash sy: Float, lift l: Float, strength k: Float) {
        let q = yawQ(y, pitch: p)
        sim.attractor.rotation = q
        sim.attractor.squash = sy
        let ay = abs(p) > 0.02 ? sim.groundedAnchorY(rotation: q, squash: sy) : sim.restCentroid.y * sy + sim.floorY          // (a leaning body's lowest point must clear the sand)
        sim.attractor.anchor = SIMD3(xz.x, ay + l, xz.y)
        sim.attractor.strength = k
        px = xz.x; pz = xz.y; yaw = y
    }

    private func tuckFeet(_ sim: SoftBody, tuck: Float, ramp: Float) {
        let simTuck = min(tuck, 0.03)
        let q = sim.attractor.rotation, sy = sim.attractor.squash, sxz = 1 / sy.squareRoot()
        let R = simd_float3x3(q), c0 = sim.restCentroid
        var list: [ParticleTarget] = []
        for a in sim.appendages where a.kind == .foot {
            for p in a.particles {
                let o = sim.restPosition(p) - c0
                let wv = sim.attractor.anchor + R * SIMD3<Float>(o.x * sxz, o.y * sy, o.z * sxz) + SIMD3<Float>(0, simTuck, 0)
                list.append(ParticleTarget(index: p, pos: wv, stiffness: 60000 * ramp))
            }
        }
        sim.targets = list
    }

    private func armTarget() -> (el: Float, sa: Float, out: Float, tau: Float, w: Float) {
        let v = volley
        switch v.phase {
        case .crouch, .diveCrouch: return (-0.30, -1.15, 0.04, 0.05, 1)                    // wound back
        case .air:
            if v.spikeT >= 0 { return (0.55, 0.25, 0.08, 0.05, 1) }                           // tucked in along the lean
            if v.block { return (1.1, 0.85, 0.06, 0.04, 1) }                                   // thrown up and held: the wall
            return v.t < 0.12 ? (1.1, 0.85, 0.06, 0.035, 1) : (0.7, 0.5, 0.05, 0.06, 1)      // thrown up at take-off, then a balancing flap
        case .dive, .slide: return (0.9, 0.35, 0.10, 0.05, 1)
        case .land, .peel: return (0.3, 0.1, 0.06, 0.08, v.t < 0.2 ? 1 : 0)
        default: return (0.3, 0.1, 0.05, 0.08, 0)
        }
    }

    private func volleyAirTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        volley.t += dt
        let t = volley.t
        let k = Self.volleyKHop
        let amp: Float = amplitude < 0.7 ? 0.6 : 1
        var tuckNow: Float = 0
        var footRamp: Float = 1
        let side = volley.side
        let facingNet = side * Float.pi / 2
        let restY = volley.restYaw
        switch volley.phase {
        case .crouch:
            let u = ease(t / VolleyTuning.crouch)
            let sy = 1 - 0.21 * amp * u
            place(sim, xz: volley.from, yaw: volley.yaw0, pitch: 0, squash: sy, lift: 0, strength: k * min(1, t / 0.06))
            if t >= VolleyTuning.crouch { volley.phase = .air; volley.t = 0; jellyKick = max(jellyKick, 0.5) }
        case .air:
            let T = volley.airT * (amplitude < 0.7 ? 1.2 : 1)
            let u = min(1, t / T)
            let h = volley.apex * amp * 4 * u * (1 - u)
            let vy = 4 * volley.apex * amp * (1 - 2 * u) / T, vy0 = 4 * volley.apex * amp / T
            let stretch = 1 + 0.13 * amp * min(1, abs(vy) / max(vy0, 1e-3))
            var sy = (1 - 0.21 * amp) + (stretch - (1 - 0.21 * amp)) * ease(t / 0.09)
            var pitchGoal: Float = 0
            var yawNow = volley.yaw0
            if volley.spikeT >= 0 {
                volley.spikeT += dt
                let s = volley.spikeT
                let lean = ease(s / 0.20)
                let out = 1 - ease((u - 0.74) / 0.24)          // righted again before the landing
                pitchGoal = 1.02 * lean * out
                yawNow = volley.yaw0 + wrapAngle(facingNet - volley.yaw0) * ease(s / 0.16)
                sy -= 0.07 * lean * out                         // the tuck
                tuckNow = 0.02
            } else if volley.block {
                // the wall: square to the net, stretched tall and held
                yawNow = volley.yaw0 + wrapAngle(facingNet - volley.yaw0) * ease(t / 0.16)
                sy = (1 - 0.21 * amp) + (1.24 - (1 - 0.21 * amp)) * ease(t / 0.12)
            } else {
                yawNow = volley.yaw0 + wrapAngle(restY - volley.yaw0) * ease(t / 0.4)
            }
            volley.pitchNow += (pitchGoal - volley.pitchNow) * min(1, dt * 24)
            var xz = volley.from + (volley.to - volley.from) * ease(u)
            xz.x = ownSide(xz.x); xz.y = ownZ(xz.y)
            place(sim, xz: xz, yaw: yawNow, pitch: volley.pitchNow, squash: sy * (1 - volley.recoil * 0.5), lift: h, strength: k)
            tuckNow = max(tuckNow, 0.05 * amp * sinf(.pi * u))
            if t >= T {
                volley.phase = .land; volley.t = 0; volley.yaw0 = yawNow
                jellyKick = max(jellyKick, 2.0)
                AudioHub.shared.play(.footstep, jelly: steerID, x: px, volume: 0.8)
            }
        case .land:
            let sq = 0.24 * amp
            let sy = 1 - sq * expf(-t / 0.085) * cosf(2 * .pi * 5 * t) - 0.03 * volley.recoil
            let yawNow = volley.yaw0 + wrapAngle(restY - volley.yaw0) * ease(t / 0.30)
            volley.pitchNow += (0 - volley.pitchNow) * min(1, dt * 14)
            let kk = k * (1 - ease((t - 0.3) / 0.22))
            place(sim, xz: volley.to, yaw: yawNow, pitch: volley.pitchNow, squash: sy, lift: 0, strength: kk)
            footRamp = 0.5
            if t >= 0.52 { volleyFinishMove(sim) }
        case .diveCrouch:
            let u = ease(t / 0.10)
            place(sim, xz: volley.from, yaw: volley.yaw0, pitch: -0.10 * u, squash: 1 - 0.16 * amp * u, lift: 0, strength: k * min(1, t / 0.05))
            if t >= 0.10 { volley.phase = .dive; volley.t = 0; jellyKick = max(jellyKick, 1.0); volley.to = clearOfMate(volley.from + SIMD2(volley.diveDir * 1.0, 0), from: volley.from) }
        case .dive:
            let T: Float = 0.32
            let u = min(1, t / T)
            var xz = volley.from + (volley.to - volley.from) * (1 - (1 - u) * (1 - u))
            xz.x = ownSide(xz.x)          // (never into the net)
            let pitch = 1.12 * ease(u / 0.6)
            let yawNow = volley.yaw0 + wrapAngle(volley.diveDir * Float.pi / 2 - volley.yaw0) * ease(u / 0.5)
            let h = 0.20 * 4 * u * (1 - u)
            volley.pitchNow = pitch
            place(sim, xz: xz, yaw: yawNow, pitch: pitch, squash: 1.04 - 0.14 * ease(u), lift: h, strength: k * 1.1)
            footRamp = Self.volleyFlipGrip
            if t >= T { volley.phase = .slide; volley.t = 0; volley.from = xz; volley.to = clearOfMate(xz + SIMD2(volley.diveDir * 0.3, 0), from: xz); volley.yaw0 = yawNow; jellyKick = max(jellyKick, 2.4); AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.7) }
        case .slide:
            let T: Float = 0.26
            let u = min(1, t / T)
            var xz = volley.from + (volley.to - volley.from) * (1 - (1 - u) * (1 - u))
            xz.x = ownSide(xz.x)
            let wob = 1 + 0.02 * expf(-t / 0.15) * cosf(2 * .pi * 6 * t)
            volley.pitchNow = 1.12 * wob
            place(sim, xz: xz, yaw: volley.yaw0, pitch: volley.pitchNow, squash: 0.90 - 0.03 * expf(-t / 0.12) * cosf(2 * .pi * 6 * t), lift: 0, strength: k * 1.1)
            footRamp = Self.volleyFlipGrip
            if t >= T { volley.phase = .peel; volley.t = 0; volley.from = xz; volley.yaw0 = volley.yaw0 }
        case .peel:
            let T: Float = 0.38
            let u = min(1, t / T)
            let e = ease(u)
            let pitch = 1.12 * (1 - e)
            let yawNow = volley.yaw0 + wrapAngle(restY - volley.yaw0) * e
            let hop = 0.10 * sinf(.pi * min(1, u * 1.1))
            volley.pitchNow = pitch
            place(sim, xz: volley.from, yaw: yawNow, pitch: pitch, squash: 0.92 + 0.08 * e + 0.05 * sinf(.pi * u), lift: hop, strength: k * 1.1)
            footRamp = Self.volleyFlipGrip + (1 - Self.volleyFlipGrip) * e * 0.5
            if t >= T { volley.phase = .land; volley.t = 0; volley.to = volley.from; volley.yaw0 = yawNow; jellyKick = max(jellyKick, 2.2) }
        case .ground:
            break
        }
        volley.tuck += (tuckNow - volley.tuck) * min(1, dt * 20)
        tuckFeet(sim, tuck: volley.tuck, ramp: footRamp)
        // arms: small balance flaps only (the stub length never changes; only the direction turns)
        let tg = armTarget()
        let kk = 1 - expf(-dt / max(tg.tau, 1e-3))
        volley.arm.el += (tg.el - volley.arm.el) * kk; volley.arm.sa += (tg.sa - volley.arm.sa) * kk; volley.arm.out += (tg.out - volley.arm.out) * kk
        volley.armA += max(-dt / 0.10, min(dt / 0.10, tg.w - volley.armA))
        armWalkWant = 1
        armDirW = smooth01(volley.armA)
        armDirEl = [volley.arm.el, volley.arm.el]; armDirSa = [volley.arm.sa, volley.arm.sa]; armDirOut = volley.arm.out
        driveBeansRigid(sim, skinner, dt, tuck: volley.tuck)
        driveArms(sim, skinner, dt)
    }

    static let volleyFlipGrip: Float = 0.15

    /// The move is over: the soft body goes back to the walking pose (the next hop / cheer may start at once).
    private func volleyFinishMove(_ sim: SoftBody) {
        sim.targets = []
        sim.attractor.strength = 0
        volley.pitchNow = 0; volley.tuck = 0; volley.spikeT = -1; volley.block = false
        armDirW = 0; armDirOut = 0; volley.armA = 0
        currentPose(sim)
        yaw = volley.restYaw
        volley.phase = .ground; volley.t = 0
        if volley.cheerLeft > 0 { volley.cheerLeft -= 1; volleyJump(sim: sim, dx: 0, apex: 0.30, cheer: true); return }
        volley.finished = true
    }
}
