//
//  BlobBrain+DecorPlay.swift
//  The two bigger toys of the second decor batch, built from the existing moves (hops, the bottom-sit, squash and lean). The arms stay thumbs and the feet
//  stay attached in both:
//    decorSlide   walks round behind the slide, hops up the two steps, sits on the platform, rides the exported `slide_path` and gets up with a squash
//    decorThrow   walks to the football, hugs it against his belly (between the stubby arm tips), squats, springs up and flings it a short arc, or fumbles it
//                 (40 %: it bonks off his head, or slips and drops); then the ball rolls on like a kick. No arm reach: the ball moves by the body's squash and spring.
//

import Foundation
import simd

// MARK: - the slide

extension BlobBrain {
    /// The slide's exported path (z, y) of the base point, local to the piece; the chute ends 0.35 beyond its lip.
    static let slidePath: [SIMD2<Float>] = slidePath0.map { $0 * DecorKind.slide.scale }
    private static let slidePath0: [SIMD2<Float>] = [SIMD2(-0.4, 0.66), SIMD2(-0.1, 0.68), SIMD2(0.23, 0.62), SIMD2(0.36, 0.536), SIMD2(0.49, 0.458), SIMD2(0.62, 0.386), SIMD2(0.75, 0.321),
                                            SIMD2(0.88, 0.264), SIMD2(1.01, 0.214), SIMD2(1.14, 0.174), SIMD2(1.27, 0.145), SIMD2(1.4, 0.13), SIMD2(1.75, 0.0)]
    /// The steps: (z, y) he hops to, then the platform.
    static let slideSteps: [SIMD2<Float>] = slideSteps0.map { $0 * DecorKind.slide.scale }
    private static let slideSteps0: [SIMD2<Float>] = [SIMD2(-1.28, 0.22), SIMD2(-1.04, 0.44), SIMD2(-0.4, 0.66)]
    static var slideLength: Float {
        var L: Float = 0
        for i in 1..<slidePath.count { L += simd_length(slidePath[i] - slidePath[i - 1]) }
        return L
    }
    /// The point `s` along the path: (z, y, slope angle).
    static func slideAt(_ s: Float) -> (z: Float, y: Float, slope: Float) {
        var left = max(s, 0)
        for i in 1..<slidePath.count {
            let d = slidePath[i] - slidePath[i - 1], L = simd_length(d)
            if left <= L || i == slidePath.count - 1 {
                let t = min(left / max(L, 1e-5), 1)
                let p = slidePath[i - 1] + d * t
                return (p.x, p.y, atan2f(-d.y, max(d.x, 0.05)))
            }
            left -= L
        }
        return (slidePath.last!.x, slidePath.last!.y, 0)
    }

    func slideArrived(_ sim: SoftBody, _ skinner: Skinner, _ f: DecorFoot) {
        idleState.slideStage = 0; idleState.goalYaw = faceCameraYaw(); idleState.slideStep = 0
        script = .idle; activity = .lookingAround
    }

    /// The hops up the steps own the body (like the bag's hops): true = this step is handled.
    func slideBodyTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard idleState.kind == .decorSlide, idleState.slideStage == 1, case .idle = script, let f = DecorField.shared.foot(idleState.decorUID) else { return false }
        activity = .playing
        mouthOpen = 0
        idleState.phaseT += dt
        let hopGoal: Float = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        gait.basePitch = pitchBase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        if gait.phase == .land, !idleState.decorBooped {
            idleState.decorBooped = true
            bagFloorOn = true; slideY = Self.slideSteps[idleState.slideStep].y
            applyBagFloor(sim, skinner)
            DecorField.shared.kick(f.uid, 0.4)
            AudioHub.shared.play(.footstep, jelly: steerID, x: px, volume: 0.9)
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
            if idleState.slideStep < 2 { idleState.slideStep += 1; slideHop(sim, f) }          // the next step
            else { idleState.slideStage = 4; idleState.phase = 1; idleState.steps = 0; idleState.k = 0; idleState.hold = rand(0.5, 1.0) }
        }
        return true
    }

    private func slideHop(_ sim: SoftBody, _ f: DecorFoot) {
        let st = Self.slideSteps[idleState.slideStep]
        idleState.slideStage = 1; idleState.decorBooped = false
        bagHop(sim, to: f.centre + SIMD2(0, st.x), ground: st.y, apex: 0.14, facing: faceCameraYaw())
    }

    /// Stage 0 (turn), 4 (sit down on the platform), 5 (ride), 6 (get up with a squash).
    func runSlide(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let f = DecorField.shared.foot(idleState.decorUID) else { idleFinish(skinner); return }
        let c = f.centre
        switch idleState.slideStage {
        case 0:
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            if !turning && !feet.active && idleState.phaseT > 0.15 {
                idleState.slideStep = 0; idleState.phaseT = 0
                slideHop(sim, f)
            }
        case 4:
            // on the platform: sits (the feet slide forward), a beat, then pushes off
            var k = idleState.k
            let phT = idleState.phaseT
            if idleState.phase == 1 {
                k = smooth01(phT / 0.9)
                if !feet.active && idleState.steps < 2 && phT > Float(idleState.steps) * 0.3 { idleFootStep(reach: Self.bagFootReach); idleState.steps += 1 }
                if phT >= 0.9 && !feet.active { idleState.phase = 2; idleState.phaseT = 0 }
            } else {
                k = 1
                if phT >= idleState.hold || idleState.yielding { idleState.slideStage = 5; idleState.slideS = 0; idleState.phaseT = 0; AudioHub.shared.play(.zoomies, jelly: steerID, x: px, volume: 0.45) }
            }
            idleState.k = k
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            sitPose(skinner, k, slump: false)
            skinner.setEyeOpenness(1 - 0.1 * k)
        case 5:
            // the ride: 1.6 -> 3 u/s (ease in); he is carried along the path with his feet (they stay under him), the body tilting to the slope
            let t = idleState.phaseT
            let speed = 1.6 + 1.4 * smooth01(t / 1.1)
            idleState.slideS += speed * dt
            let at = Self.slideAt(idleState.slideS)
            let want = SIMD2<Float>(c.x, c.y + at.z)
            let d = want - SIMD2(px, pz)
            px = want.x; pz = want.y
            feet.pos[0] += d; feet.pos[1] += d
            slideY = at.y; bagFloorOn = true
            applyBagFloor(sim, skinner)
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            sitPose(skinner, 1, slump: false)
            pitch += at.slope * 0.9
            jellyKick = max(jellyKick, 0.5)
            skinner.setEyeOpenness(0.8)
            if idleState.slideS >= Self.slideLength {
                idleState.slideStage = 6; idleState.phase = 1; idleState.phaseT = 0; idleState.steps = 0
                bagFloorOn = false; applyBagFloor(sim, skinner)
                jellyKick = max(jellyKick, 2.4)
                AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.9)
                AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.5, rate: 0.8)
            }
        case 6:
            // lands on the floor: a squash, then gets up
            let phT = idleState.phaseT
            let k = 1 - smooth01((phT - 0.35) / 0.9)
            if phT > 0.35, !feet.active && idleState.steps < 2 && phT > 0.35 + Float(idleState.steps) * 0.3 { idleFootStep(reach: 0); idleState.steps += 1 }
            idleState.k = k
            gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
            sitPose(skinner, k, slump: false)
            squash *= 1 - 0.14 * sinf(.pi * min(1, phT / 0.4)) * (phT < 0.4 ? 1 : 0)
            if phT >= 1.3 && !feet.active && idleState.steps >= 2 {
                idleState.k = 0; sitPose(skinner, 0, slump: false)
                currentPose(sim)
                idleFinish(skinner)
            }
        default: break
        }
    }
}

// MARK: - the football

extension BlobBrain {
    func throwArrived(_ sim: SoftBody, _ skinner: Skinner, _ f: DecorFoot) {
        let d = (throwAim ?? DecorField.shared.position(f)) - position
        idleState.goalYaw = atan2f(d.x, d.y)
        idleState.throwStage = 0; idleState.phase = 0; idleState.phaseT = 0
        idleState.throwFate = throwFateForce ?? { let u = rand(); return u < 0.6 ? 0 : (u < 0.8 ? 1 : 2) }()
        script = .idle; activity = .lookingAround
    }

    /// Where the ball hangs when hugged: 0.55 in front of him, 0.45 up (its resting centre is 0.105).
    func holdPoint() -> SIMD2<Float> { position + SIMD2(sinf(yaw), cosf(yaw)) * Self.holdForward }
    /// How far in front of his root the ball's centre hangs: its centre at his belly's surface (measured with the body SDF, the ball 0.05 sunk in at the winding up).
    static let holdForward: Float = 0.36
    static let holdLift: Float = 0.45 - 0.105

    /// A direction to throw: toward the open floor, within the visible room, with a little wobble.
    func throwDirection(range: Float) -> SIMD2<Float> {
        let fwd = SIMD2<Float>(sinf(yaw), cosf(yaw))
        var best = fwd
        for k in 0..<8 {
            let a = rand(-0.5, 0.5) + Float(k) * 0.5 * (k % 2 == 0 ? 1 : -1)
            let u = SIMD2(fwd.x * cosf(a) - fwd.y * sinf(a), fwd.x * sinf(a) + fwd.y * cosf(a))
            let p = position + u * (range + 0.8)
            let q = fixed(p)
            if simd_distance(p, q) < 0.15 { best = u; break }
        }
        return best
    }

    func runThrow(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let f = DecorField.shared.foot(idleState.decorUID) else { idleFinish(skinner); return }
        let uid = f.uid, field = DecorField.shared
        let t = idleState.phaseT
        let fwd = SIMD2<Float>(sinf(yaw), cosf(yaw))
        gaitPose(sway: 0.03, bob: 0.0, rock: 0.1)
        switch idleState.throwStage {
        case 0:
            if field.anim[uid]?.held == true { field.hold(uid, at: holdPoint(), lift: Self.holdLift) }          // (a ball he caught: it stays against his belly while he turns)
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.08)
            if !turning && !feet.active && t > 0.1 { idleState.throwStage = 1; idleState.phaseT = 0 }
        case 1:   // hug: the ball is scooped up against the belly (0.35 s of squash 0.92)
            let k = smooth01(t / 0.35)
            let from = field.position(f)
            field.hold(uid, at: from + (holdPoint() - from) * k, lift: Self.holdLift * k)
            squash *= 1 - 0.08 * k
            pitch += 0.04 * k
            if t > 0.55 { idleState.throwStage = 2; idleState.phaseT = 0; AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.4) }
        case 2:   // wind up: squat, lean back, the ball pressed in
            let k = smooth01(t / 0.3)
            field.hold(uid, at: holdPoint() - fwd * 0.04 * k, lift: Self.holdLift - 0.04 * k)
            squash *= 1 - 0.08 - 0.14 * k
            pitch += 0.04 - 0.14 * k
            if t > 0.34 {
                idleState.throwStage = 3; idleState.phaseT = 0; idleState.decorBooped = false
                var range = rand(0.8, 1.5)
                idleState.throwDir = idleState.throwFate == 0 ? throwDirection(range: range) : fwd
                if let aim = throwAim {          // a toss: straight at the friend, landing about on him
                    let d = aim - position, L = simd_length(d)
                    if L > 1e-3 { idleState.throwDir = d / L; range = min(max(L - 0.1, 0.8), 1.5) }
                }
                idleState.reps = Int(range * 100)
            }
        case 3:   // spring up and let go (squash 1.12, lean forward)
            let k = smooth01(t / 0.12)
            squash *= 0.78 + (1.12 - 0.78) * k
            pitch += -0.10 + 0.22 * k
            if t < 0.06 { field.hold(uid, at: holdPoint(), lift: Self.holdLift + 0.05 * (t / 0.06)) }
            else if !idleState.decorBooped {
                idleState.decorBooped = true
                jellyKick = max(jellyKick, 1.6)
                AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.6)
                let range = Float(idleState.reps) / 100
                switch idleState.throwFate {
                case 1:      // bonk: straight up, it comes down on his head
                    field.fling(uid, vh: -fwd * (Self.holdForward / 0.76), vy: 3.2, kind: 1, bonkDir: fwd)
                case 2:      // drop: it slips and falls at the front
                    field.fling(uid, vh: fwd * rand(0.5, 0.9), vy: 0, kind: 2)
                default:     // a short wobbly arc
                    field.fling(uid, vh: idleState.throwDir * (range / 0.8) , vy: 2.4, kind: 0)
                }
                field.kick(uid, 0.5)
            }
            if t > 0.22 { idleState.throwStage = 4; idleState.phaseT = 0 }
        case 4:   // settle (the existing damped jelly settle), and the bonk when the ball meets his head
            squash *= 1 + 0.10 * expf(-t * 7) * cosf(t * 16)
            pitch += 0.12 * expf(-t * 6)
            if field.takeBonk(uid) {
                squash *= 0.9
                jellyKick = max(jellyKick, 2.0)
                AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.8)
            }
            let a = field.anim[uid]
            if throwAim != nil { if t > 0.8 { idleFinish(skinner) } }          // (a toss: the friend takes over)
            else if t > 0.6, a?.flying != true, a?.moving != true { if t > 1.0 { idleFinish(skinner) } }
            else if t > 7 { idleFinish(skinner) }
        default: break
        }
        if idleState.throwStage != 4, field.takeBonk(uid) {      // (the head is hit while he is still springing)
            squash *= 0.9; jellyKick = max(jellyKick, 2.0)
            AudioHub.shared.play(.boop, jelly: steerID, x: px, volume: 0.8)
        }
    }
}
