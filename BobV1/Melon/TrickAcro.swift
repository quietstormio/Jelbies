//
//  TrickAcro.swift
//  Trick plan stage 3b / 3c (prototypes): the two tricks that turn the body over, BACK BOUNCE and HEADSTAND. Trick-only IdleKinds. Phase 0 (runIdle) turns him side on to
//  the camera; phase 1 is this file's own tick: the brain writes the attractor directly (rotation about his x axis, a grounded anchor, the floor squish from a dip below
//  the grounded height, as the flip's faceplant and the sleep's on-back pose do), the beans are forced on the fitted pose (the boot shape), the legs kick about their
//  buried hips. `AcroProfile` is the pure time -> pose table (unit tested); `acroTick` applies it.
//
//  BACK BOUNCE  sits back, tips onto his back (a thump, a squish), bounces on it like a ball twice with the feet kicking in turn, springs up onto his feet, the landing jiggle.
//               The Show's flop: no spring; he lies there kicking, then peels slowly up, worried.
//  HEADSTAND    a crouch, a little hop forward over onto his head, the feet kick in turn up in the air through a held beat, then he pops on over (a half front flip) onto
//               his feet. `AcroTuning.headPitch` = pi rests on the crown; less rests on the forehead (the fallback if the crown reads as horns).
//               The Show's flop: he tips on past onto his back, lies there, peels up.
//  `trickTipped` is true for the whole of phase 1: an abort (the Show's walk-out, a voice stop, a teleport) goes to the recover path that rights him (BlobBrain.abortAll).
//

import Foundation
import simd

nonisolated enum AcroTuning {
    /// On his back (rad back from upright; the sleep's lie angle is about 1.5), and the headstand's pitch (pi = the crown; ~2.7 = the forehead).
    nonisolated(unsafe) static var backPitch: Float = 1.45, headPitch: Float = 2.75          // (the forehead version: the crown at pi read as a tuft / ears on top, strip try3)
    /// The legs' kick: the swing about the hip (rad) and its rate (Hz) on the back / on the head.
    nonisolated(unsafe) static var kick: Float = 0.80, kickHzBack: Float = 5.0, kickHzHead: Float = 4.0
    /// The kicking legs: a V out to the sides about the hips (rad) and a little longer (stubby still), so two feet read on top of him / off his end (one boot each, not a nub).
    nonisolated(unsafe) static var splay: Float = 0.55, stretch: Float = 0.35
    /// The staging: the heading off the camera (rad). pi/2 = pure profile (the feet hide behind each other, the face is an edge); ~1 = three-quarter (face, belly and both feet).
    nonisolated(unsafe) static var turnOff: Float = 1.0
    /// The headstand faces three-quarter AWAY from the camera (pi - 1): he tips forward away from it and ends with his upside-down face toward it (from behind, the two
    /// feet on top read as ears / horns: strip try2). Its V of the legs is narrower (a wide V on top reads as ears).
    nonisolated(unsafe) static var headTurnOff: Float = .pi - 1.0, headSplay: Float = 0.25
    /// The two bounces' heights on his back (u), the spring up's and the pop over's (u).
    nonisolated(unsafe) static var bounce1: Float = 0.12, bounce2: Float = 0.06, springLift: Float = 0.15, popLift: Float = 0.17
    /// How far the middle of the body rolls back as he lies down (u): he tips over his heels, not about his middle.
    nonisolated(unsafe) static var rollBack: Float = 0.22
}

/// The pose of the two tipped tricks at time `t` of phase 1 (pure: tested in TrickStageThreeTests).
nonisolated struct AcroProfile {
    enum Beat: Int { case prep, tip, down, air, up, land, done }
    var pitch: Float = 0          // + = forward (face down), - = back (on his back)
    var squash: Float = 1
    var dip: Float = 0            // anchor below the grounded height (the squish into the floor)
    var lift: Float = 0           // anchor above it (airborne)
    var back: Float = 0           // the middle rolled back along -heading (u)
    var legs: Float = 0           // 0...1: the kicking legs' weight
    var beat: Beat = .prep

    static let headstand = true
    // back bounce: sit, tip, impact, bounce 1, bounce 2, spring, land
    static let bSit: Float = 0.28, bTip: Float = 0.52, bImpact: Float = 0.66, bB1: Float = 1.02, bB2: Float = 1.28, bSpring0: Float = 1.40, bSpring1: Float = 1.82, bEnd: Float = 2.38
    static let bFailLie: Float = 1.95, bFailPeel: Float = 2.85, bFailEnd: Float = 3.25
    // headstand: crouch, tip (a little hop), hold, pop over, land
    static let hCrouch: Float = 0.30, hTip: Float = 0.76, hHold: Float = 2.00, hPop: Float = 2.42, hEnd: Float = 2.95
    static let hFailTip: Float = 1.45, hFailDown: Float = 1.85, hFailLie: Float = 2.35, hFailPeel: Float = 3.15, hFailEnd: Float = 3.55

    static func total(_ kind: IdleKind, fail: Bool) -> Float {
        kind == .headstand ? (fail ? hFailEnd : hEnd) : (fail ? bFailEnd : bEnd)
    }

    private static func s(_ x: Float) -> Float { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }
    /// The hop's landing: a squash that rebounds and dies out.
    private static func landSquash(_ u: Float, depth: Float) -> Float { 1 - depth * expf(-u / 0.09) * cosf(2 * .pi * 4.5 * u) }
    /// The thump into the floor at a contact: pressed in over 0.03 s (no one-frame jump of the anchor), a rebound, settling.
    private static func thump(_ u: Float, _ amp: Float) -> Float { amp * min(1, u / 0.03) * expf(-u / 0.08) * cosf(2 * .pi * 2.2 * u) }
    /// The flop's held-headstand wobble at the moment it tips on over (the tip starts from it).
    private static var hFailHoldEnd: Float { 0.05 * sinf(2 * .pi * 1.6 * (hFailTip - hTip)) }

    init() {}
    init(_ kind: IdleKind, t: Float, fail: Bool, amp a: Float = 1) {
        if kind == .headstand { self = Self.headstandAt(t, fail: fail, a) } else { self = Self.backBounceAt(t, fail: fail, a) }
    }

    static func backBounceAt(_ t: Float, fail: Bool, _ a: Float) -> AcroProfile {
        typealias T = AcroTuning
        var p = AcroProfile()
        let P = T.backPitch
        func rolled(_ pitch: Float) -> Float { T.rollBack * a * sinf(min(.pi / 2, max(0, -pitch))) / sinf(min(.pi / 2, P)) }
        if t < bSit {
            // sits back: the weight over the heels, a squash, arms forward
            let u = s(t / bSit)
            p.pitch = -0.35 * u * a; p.squash = 1 - 0.12 * u * a; p.beat = .prep
        } else if t < bTip {
            // tips over: falling (it speeds up), the squash lets go
            let u = (t - bSit) / (bTip - bSit)
            p.pitch = -0.35 * a - (P - 0.35 * a) * u * u; p.squash = 1 - 0.12 * a * (1 - u); p.beat = .tip
        } else if t < bImpact {
            // the thump: pressed into the floor, a rebound starting
            let u = t - bTip
            p.pitch = -P - 0.06 * a * sinf(2 * .pi * 3 * u) * expf(-u / 0.12)
            p.dip = thump(u, 0.07 * a)
            p.squash = 1 - 0.06 * a * min(1, u / 0.03) * expf(-u / 0.08); p.beat = .down; p.legs = s(u / 0.08)
        } else if t < (fail ? bFailLie : bSpring0) {
            // the bounces like a ball (the second smaller), then (the flop) he just lies there kicking
            p.pitch = -P; p.legs = 1; p.beat = .air
            if t < bB1 { let u = (t - bImpact) / (bB1 - bImpact); p.lift = T.bounce1 * a * sinf(.pi * u); p.pitch += 0.08 * a * sinf(2 * .pi * u) }
            else if t < bB2 { let u = (t - bB1) / (bB2 - bB1); p.lift = T.bounce2 * a * sinf(.pi * u); p.pitch -= 0.05 * a * sinf(2 * .pi * u) }
            else { let u = t - bB2; p.dip = thump(u, 0.03 * a); p.squash = 1 - 0.03 * a * min(1, u / 0.03) * expf(-u / 0.08); if fail { p.beat = .down } }
            if t >= bB1 && t < bB1 + 0.06 { p.dip = 0.04 * a * sinf(.pi * (t - bB1) / 0.06) }
        } else if !fail {
            if t < bSpring1 {
                // springs up: a push off the back, up through upright with a little hop and a stretch
                let u = (t - bSpring0) / (bSpring1 - bSpring0), e = s(u)
                p.pitch = -P * (1 - e); p.lift = T.springLift * a * sinf(.pi * u); p.squash = 1 + 0.06 * a * sinf(.pi * u); p.beat = .up
                p.legs = 1 - s(u / 0.5)
            } else {
                p.pitch = 0; p.squash = landSquash(t - bSpring1, depth: 0.20 * a); p.beat = t < bEnd ? .land : .done
            }
        } else {
            if t < bFailPeel {
                // the flop's slow peel up: the weight shifts, then up, a little hop at the top
                let u = (t - bFailLie) / (bFailPeel - bFailLie), e = s(u)
                p.pitch = -P * (1 - e); p.lift = 0.05 * a * sinf(.pi * u); p.squash = 1 - 0.04 * a * sinf(.pi * u); p.beat = .up
                p.legs = 1 - s(u / 0.4)
            } else {
                p.pitch = 0; p.squash = landSquash(t - bFailPeel, depth: 0.10 * a); p.beat = t < bFailEnd ? .land : .done
            }
        }
        p.back = rolled(p.pitch)
        return p
    }

    static func headstandAt(_ t: Float, fail: Bool, _ a: Float) -> AcroProfile {
        typealias T = AcroTuning
        var p = AcroProfile()
        let H = T.headPitch
        if t < hCrouch {
            let u = s(t / hCrouch)
            p.pitch = 0.25 * u * a; p.squash = 1 - 0.18 * u * a; p.beat = .prep
        } else if t < hTip {
            // a little hop forward, over onto the head
            let u = (t - hCrouch) / (hTip - hCrouch), e = s(u)
            p.pitch = 0.25 * a + (H - 0.25 * a) * e; p.lift = 0.12 * a * sinf(.pi * u); p.squash = 0.82 + 0.18 * s(u / 0.3) + 0.04 * a * sinf(.pi * u); p.beat = .tip
            p.legs = s((u - 0.6) / 0.4) * 0.5
        } else if t < (fail ? hFailTip : hHold) {
            // the held headstand: a slow sway on the head, the feet kicking up in the air in turn
            let u = t - hTip
            p.pitch = H + 0.05 * a * sinf(2 * .pi * 1.6 * u)
            p.dip = thump(u, 0.035 * a)
            p.squash = 1 - 0.05 * a * min(1, u / 0.03) * expf(-u / 0.09); p.legs = 1; p.beat = .air
            if fail, u > 0.35 { p.pitch += 0.30 * a * s((u - 0.35) / 0.34) }          // (the flop leans on over, past the balance point)
        } else if !fail {
            if t < hPop {
                // pops on over: a half front flip to his feet, on the heading he had
                let u = (t - hHold) / (hPop - hHold), e = s(u)
                p.pitch = H + (2 * .pi - H) * e; p.lift = T.popLift * a * sinf(.pi * u); p.squash = 1 + 0.05 * a * sinf(.pi * u); p.beat = .up
                p.legs = 1 - s(u / 0.5)
            } else {
                p.pitch = 2 * .pi; p.squash = landSquash(t - hPop, depth: 0.22 * a); p.beat = t < hEnd ? .land : .done
            }
        } else {
            // the flop: he tips on past, down onto his back (the face up), lies there, peels up
            let lie = 2 * .pi - T.backPitch
            if t < hFailDown {
                let u = (t - hFailTip) / (hFailDown - hFailTip)
                let p0 = H + (0.30 + hFailHoldEnd) * a
                p.pitch = p0 + (lie - p0) * u * u; p.legs = 1 - u; p.beat = .tip
                p.back = -AcroTuning.rollBack * a * s(u)
            } else if t < hFailLie {
                let u = t - hFailDown
                p.pitch = lie + 0.05 * a * sinf(2 * .pi * 3 * u) * expf(-u / 0.12); p.dip = thump(u, 0.06 * a); p.squash = 1 - 0.05 * a * min(1, u / 0.03) * expf(-u / 0.08)
                p.legs = s(u / 0.15) * 0.6; p.beat = .down
            } else if t < hFailPeel {
                let u = (t - hFailLie) / (hFailPeel - hFailLie), e = s(u)
                p.pitch = lie + (2 * .pi - lie) * e; p.lift = 0.05 * a * sinf(.pi * u); p.squash = 1 - 0.04 * a * sinf(.pi * u); p.legs = 0.6 * (1 - s(u / 0.4)); p.beat = .up
            } else {
                p.pitch = 2 * .pi; p.squash = landSquash(t - hFailPeel, depth: 0.10 * a); p.beat = t < hFailEnd ? .land : .done
            }
            if t >= hFailDown { p.back = -AcroTuning.rollBack * a * sinf(min(.pi / 2, max(0, 2 * .pi - p.pitch))) / sinf(min(.pi / 2, AcroTuning.backPitch)) }          // (lying on his back the far side of the head: his middle is past the head, ahead)
        }
        return p
    }
}

extension BlobBrain {
    /// The body is turned over by a trick (back bounce / headstand, its whole own tick): a stop / walk-out rights him through the recover path, the touch get-up leaves him be.
    var trickTipped: Bool {
        guard let k = idleState.kind, k == .backBounce || k == .headstand, idleState.phase == 1, case .idle = script else { return false }
        return true
    }

    /// A stop / walk-out while he is turned over (from `idleReset`, inside `abortAll`): released, the jelly would roll and jiggle for a second before the recover path
    /// (which waits for a still body) rights him. Instead he is held still where he is, on the floor, so the recover path starts at once.
    func acroAbortHold(_ sim: SoftBody) {
        let pose = sim.bodyPose(iterations: 6)
        sim.attractor.rotation = pose.rotation
        sim.attractor.squash = 1
        sim.attractor.anchor = SIMD3(pose.centroid.x, sim.groundedAnchorY(rotation: pose.rotation), pose.centroid.z)
        sim.attractor.strength = kPose
        for i in sim.v.indices { sim.v[i] *= 0.3 }
    }

    /// Phase 0 of both (from `runIdle`): side on to the camera with steps, a beat, then the body is handed to `acroTick`.
    func runAcroTurn(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard idleState.phase == 0 else { return }
        if idleState.trick.flags & 1 == 0 { idleState.trick.flags |= 1; idleState.goalYaw = faceCameraYaw() + Float(idleState.sign) * (idleState.kind == .headstand ? AcroTuning.headTurnOff : AcroTuning.turnOff) }
        let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
        gaitPose(sway: 0.04, bob: 0.02, rock: 0.3)
        armWalkWant = 0
        if turning || feet.active { idleState.phaseT = 0; return }
        if idleState.phaseT > 0.2 {
            idleState.trick.root = SIMD3(px, pz, yaw)
            idleState.trick.el = 0.3; idleState.trick.sa = 0.1; idleState.trick.out = 0.05; idleState.trick.armA = 0
            idleState.trick.strength = sim.attractor.strength
            sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
            poseW = 0; poseOn = false
            idleState.phase = 1; idleState.phaseT = 0
        }
    }

    /// Ticked from `trickBodyTick` (phase 1 of the back bounce / the headstand): true = this step is handled.
    func acroTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard geom.valid, let kind = idleState.kind else { idleFinish(skinner); return true }
        activity = .playing
        idleState.phaseT += dt
        let t = idleState.phaseT, fail = idleState.trick.fail, a = amplitude
        let p = AcroProfile(kind, t: t, fail: fail, amp: a)
        let end = AcroProfile.total(kind, fail: fail)
        let root = idleState.trick.root
        let fwd = SIMD2<Float>(sinf(root.z), cosf(root.z))
        pitchBase += max(-1.2 * dt, min(1.2 * dt, 0 - pitchBase))
        // the attractor: pitched about his own x axis inside the heading, grounded (the lowest point of the pose on the floor), the squish and the airborne lift on top
        let q = yawQuat(root.z) * simd_quatf(angle: p.pitch + pitchBase, axis: SIMD3<Float>(1, 0, 0))
        let xz = SIMD2(root.x, root.y) - fwd * p.back
        sim.attractor.rotation = q
        sim.attractor.squash = p.squash
        sim.attractor.anchor = SIMD3(xz.x, sim.groundedAnchorY(rotation: q, squash: p.squash) - p.dip + p.lift, xz.y)
        let k0 = idleState.trick.strength, kA: Float = 1000
        let ramp = min(1, t / 0.08), fade = 1 - smooth01((t - (end - 0.15)) / 0.15)
        sim.attractor.strength = (k0 + (kA - k0) * ramp) * max(0, fade)
        sim.targets = []
        px = root.x; pz = root.y; yaw = root.z
        // the events: the face, the voice, the jelly kicks
        let st = idleState.trick.stage
        if p.beat.rawValue > st {
            idleState.trick.stage = p.beat.rawValue
            switch (kind, p.beat) {
            case (.backBounce, .prep): face(.excited, hold: 0.6)
            case (.backBounce, .down):
                if st < AcroProfile.Beat.down.rawValue { jellyKick = max(jellyKick, 2.2); face(.surprised, hold: 0.5); noteFlipBeats(false, true) }
            case (.backBounce, .air): face(.joyArc, hold: 0.8); AudioHub.shared.chirp(jelly: steerID, .giggle, x: px)
            case (.backBounce, .up): face(fail ? .worried : .excited, hold: 0.8); if !fail { AudioHub.shared.chirp(jelly: steerID, .wheee, x: px); noteFlipBeats(true, false) } else { AudioHub.shared.chirp(jelly: steerID, .uhoh, x: px) }
            case (.backBounce, .land): jellyKick = max(jellyKick, fail ? 1.2 : 2.4); face(fail ? .worried : .joyArc, hold: 1.0); noteFlipBeats(false, true)
            case (.headstand, .prep): face(.focused, hold: 0.5)
            case (.headstand, .tip): if !fail || t < AcroProfile.hHold { face(.excited, hold: 0.6); AudioHub.shared.chirp(jelly: steerID, .wheee, x: px); noteFlipBeats(true, false) }
            case (.headstand, .air): jellyKick = max(jellyKick, 1.8); face(.excited, hold: 1.3); blushBump(hold: 1.6, peak: 0.45); noteFlipBeats(false, true)
            case (.headstand, .up): face(fail ? .worried : .excited, hold: 0.6)
            case (.headstand, .land): jellyKick = max(jellyKick, fail ? 1.2 : 2.6); face(fail ? .worried : .joyArc, hold: 1.0); noteFlipBeats(false, true)
            default: break
            }
        }
        if kind == .headstand, fail, t >= AcroProfile.hFailTip, idleState.trick.flags & 4 == 0 { idleState.trick.flags |= 4; face(.worried, hold: 0.6) }
        if kind == .headstand, fail, t >= AcroProfile.hFailDown, idleState.trick.flags & 8 == 0 { idleState.trick.flags |= 8; jellyKick = max(jellyKick, 2.0); AudioHub.shared.chirp(jelly: steerID, .uhoh, x: px); noteFlipBeats(false, true) }
        if kind == .backBounce, t >= AcroProfile.bB1, t < AcroProfile.bB1 + dt * 1.5 { jellyKick = max(jellyKick, 1.0) }
        // the arms: forward as he sits back, out and flapping on his back / on his head, up as he springs, then back to rest
        var tg: (el: Float, sa: Float, out: Float, tau: Float, w: Float)
        switch p.beat {
        case .prep: tg = kind == .headstand ? (-0.30, -1.0, 0.04, 0.06, 1) : (0.50, 0.15, 0.05, 0.08, 1)
        case .tip, .down, .air: tg = (0.85 + 0.12 * sinf(2 * .pi * 3 * t), 0.75, 0.08, 0.05, 1)
        case .up: tg = (0.95, 0.15, 0.07, 0.05, 1)
        case .land, .done: tg = (0.30, 0.10, 0.05, 0.08, 0)
        }
        trickArms(tg, dt)
        mouthOpen = (p.beat == .air && kind == .backBounce) ? 0.25 + 0.15 * max(0, sinf(2 * .pi * 2.5 * t)) : 0
        acroBeans(sim, skinner, dt, legs: p.legs, hz: kind == .headstand ? AcroTuning.kickHzHead : AcroTuning.kickHzBack, t: t)
        driveArms(sim, skinner, dt)
        if t >= end {
            sim.attractor.strength = 0
            armDirW = 0; armDirOut = 0; idleState.trick.armA = 0; mouthOpen = 0
            currentPose(sim)
            yaw = root.z          // (the heading he had: a whole half flip lands on it; the position is where the body is)
            idleFinish(skinner)
        }
        return true
    }

    /// The feet in a tipped trick: both beans on the FITTED pose in their boot shape (forced, as in the flip), each leg swung about its buried hip in the body's
    /// y-z plane (a kick in turn), then clamped to the body again.
    private func acroBeans(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, legs: Float, hz: Float, t: Float) {
        guard beanFirstIdx.count == 2 else { return }
        prepareBeans(sim, skinner)
        guard footSkin.valid else { return }
        if beanScratch[0].count != FootBean.vertexCount { beanScratch = [[SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount), [SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount)] }
        footShift = [.zero, .zero]
        beanForce = true; beanForceLast = true
        fillBeansRigid(sim, into: &beanScratch, tuck: 0)
        beanForce = false
        let pose = sim.bodyPose(iterations: 3)
        if legs > 0.001 {
            let R = beanFitUsed?.rotation ?? pose.rotation, Ri = R.inverse
            for s in 0..<2 {
                let hip = beanScratch[s][FootBean.vertexCount - 1]
                let phi = AcroTuning.kick * legs * amplitude * sinf(2 * .pi * hz * t + (s == 0 ? 0 : .pi))
                let cs = cosf(phi), sn = sinf(phi)
                let side: Float = geom.contact[s].x < 0 ? -1 : 1
                let v = side * (idleState.kind == .headstand ? AcroTuning.headSplay : AcroTuning.splay) * legs * amplitude, cv = cosf(v), sv = sinf(v)
                for i in 0..<FootBean.vertexCount {
                    var l = Ri.act(beanScratch[s][i] - hip)
                    l.y *= 1 + AcroTuning.stretch * legs
                    l = SIMD3<Float>(l.x * cv - l.y * sv, l.x * sv + l.y * cv, l.z)          // the V (body x-y plane)
                    let r = SIMD3<Float>(l.x, l.y * cs - l.z * sn, l.y * sn + l.z * cs)          // the kick (body y-z plane)
                    beanScratch[s][i] = hip + R.act(r)
                }
                attachBean(sim, pose, lifted: true, &beanScratch[s])
                attachBean(sim, pose, lifted: true, &beanScratch[s])
                Self.liftOntoFloor(&beanScratch[s], floorY: sim.floorY)
            }
        }
        commitBeans(sim, skinner, dt, want: true)
    }
}
