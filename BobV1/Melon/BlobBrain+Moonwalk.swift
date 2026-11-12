//
//  BlobBrain+Moonwalk.swift
//  Trick plan stage 3a (prototype): the MOONWALK. A trick-only IdleKind, run through `runIdle` in pose mode (feet world-planted, the locked walk is not used: its swing
//  foot lifts and lands AHEAD, the opposite of a moonwalk).
//
//  0  turn three-quarter on to the camera (the side whose backward path has room), so the feet show
//  1  the set: the feet slide apart fore and aft (the front one flat, the back one up on its toe), a forward lean, arms bent
//  2  the glides: the root glides BACKWARD at a steady speed (no bob). In each glide the front foot slides back FLAT past the other, which stays pinned up on its toe;
//     at the switch the slid foot pops up onto its toe and the other heel drops: it becomes the slider. A small dip at each switch, the hips roll / twist in turn.
//  3  the point: he turns to the camera, a flick of one arm, up on the toes, a giggle
//  4  the walk back to his spot (the locked walk), then the move ends
//  The Show's flop: the second glide slips (the slider shoots back, he lurches back and wobbles, arms up), then the walk back.
//  Heel up: `MoonwalkTuning.heelUp` > 0 holds the standing foot up on its toe through the hook in `driveLimbs` (v2, BlobBrain.swift); 0 = v1: the standing foot's
//  heel only lifts with a swing in place (FootGait: lift and toe-down tilt together), no BlobBrain.swift edit.
//

import Foundation
import simd

nonisolated enum MoonwalkTuning {
    /// Seconds of the set, of one glide, of the point.
    nonisolated(unsafe) static var prep: Float = 0.40, glide: Float = 0.62, point: Float = 0.95
    /// Glides in the full / the close-up (focus) version.
    nonisolated(unsafe) static var glides = 4, glidesCompact = 2
    /// How far the root glides back in one glide (u): the slider travels twice that in the world, so each foot stays within +-half of it of the root.
    nonisolated(unsafe) static var stride: Float = 0.13
    /// The forward lean (rad), the dip at each switch (squash), the hips' roll and twist per glide (rad).
    nonisolated(unsafe) static var lean: Float = 0.16, dip: Float = 0.035, hipRoll: Float = 0.05, twist: Float = 0.10
    /// The heading off the camera (rad): three-quarter on.
    nonisolated(unsafe) static var turnOff: Float = 1.1
    /// v2: the standing foot up on its toe (rad about the toe; 0 = v1, no hook). v1's in-place swing of the standing foot: its lift (u) and toe-down tilt (rad).
    nonisolated(unsafe) static var heelUp: Float = 0.55
    nonisolated(unsafe) static var v1Lift: Float = 0.030, v1Tilt: Float = 0.45
    /// The foot's length (u, heel to toe of the boot): raising the heel by `footLen * sin(a)` while tilting the toe down by `a` turns the foot about its toe.
    static let footLen: Float = 0.11
    /// The walk back to the spot he started from (false = he stays where the glides took him).
    nonisolated(unsafe) static var walkBack = true
    static let walkBackPhase = 4
    /// Seconds of the move after the turn, not counting the walk back (the Show waits for the walk back too: ShowTrickInfo.seconds).
    static func total(compact: Bool = false) -> Float { prep + Float(compact ? glidesCompact : glides) * glide + 0.5 + point }
}

extension BlobBrain {
    private func mwOnce(_ bit: Int) -> Bool {
        guard idleState.steps & (1 << bit) == 0 else { return false }
        idleState.steps |= 1 << bit
        return true
    }

    /// The moonwalk's walk back is over (idleGate): the move ends.
    func moonwalkHome(_ skinner: Skinner) {
        idleState.trick.heelUp = .zero
        idleFinish(skinner)
    }

    func runMoonwalk(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        typealias T = MoonwalkTuning
        let a = amplitude
        let fwd = SIMD2<Float>(sinf(yaw), cosf(yaw))
        switch idleState.phase {
        case 0:
            // which three-quarter side: the one whose backward path stays clear (the room's walls / props)
            if idleState.trick.flags & 1 == 0 {
                idleState.trick.flags |= 1
                let here = SIMD2(px, pz), cam = faceCameraYaw()
                var best: (Float, Float) = (-1, cam + T.turnOff)
                for sgn: Float in [Float(idleState.sign), -Float(idleState.sign)] {
                    let y = cam + sgn * T.turnOff
                    let back = -SIMD2<Float>(sinf(y), cosf(y))
                    let want = here + back * (T.stride * Float(T.glides) + 0.15)
                    let got = resolve(SIMD3(want.x, 0, want.y), footprint)
                    let room = simd_length(SIMD2(got.x, got.z) - here)
                    if room > best.0 + 0.02 { best = (room, y) }
                }
                idleState.goalYaw = best.1
                idleState.trick.root = SIMD3(px, pz, yaw)
            }
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.06)
            gaitPose(sway: 0.04, bob: 0.02, rock: 0.3)
            armWalkWant = 0
            if turning || feet.active { idleState.phaseT = 0; return }
            if idleState.phaseT > 0.15 {
                idleState.phase = 1; idleState.phaseT = 0
                idleState.trick.base = SIMD2(px, pz)
                idleState.trick.stage = idleState.sign > 0 ? 1 : 0          // the first slider (its foot is set in front)
                idleState.trick.feet0 = feet.pos
                idleState.trick.el = 0.30; idleState.trick.sa = 0.1; idleState.trick.out = 0.04; idleState.trick.armA = 0
                stepLive = false
            }
            return
        case 1, 2:
            break
        case 3:
            runMoonwalkPoint(sim, skinner, dt)
            return
        default:
            return          // (4: the walk back runs as the .walk script; idleGate ends the move when it arrives)
        }
        let compact = flipCompact
        let n = max(1, compact ? T.glidesCompact : T.glides)
        let fail = idleState.trick.fail
        let D = T.stride * a
        let s0 = idleState.trick.stage
        let base = idleState.trick.base
        let off = [rotXZ(geom.off[0], yaw), rotXZ(geom.off[1], yaw)]
        pivotSide = nil; pivotNominal = false
        stepLive = false
        armWalkWant = 0
        if mwOnce(0) { face(.focused, hold: 1.0); skinner.setEyeOpenness(0.75) }
        let t = idleState.phaseT
        if idleState.phase == 1 {
            // the set: the first slider's foot slides forward half a stride, the other back half a stride (both flat on the floor; the back one goes up on its toe), the lean comes in
            let u = smooth01(t / T.prep)
            for s in 0..<2 {
                let f: Float = s == s0 ? 0.5 : -0.5
                let goal = base + off[s] + fwd * (f * D)
                feet.pos[s] = idleState.trick.feet0[s] + (goal - idleState.trick.feet0[s]) * u
                feet.yaw[s] = yaw
            }
            px = base.x; pz = base.y
            pitch += T.lean * u * a
            squash = 1 - 0.02 * u
            roll = 0; lift = 0; twist = 0
            if T.heelUp > 0 { moonHeel(stand: 1 - s0, k: u) }          // (v1: the in-place heel swing starts with the first glide)
            trickArms((0.30, 0.15, 0.04, 0.10, 1), dt)
            if t >= T.prep { idleState.phase = 2; idleState.phaseT = 0; AudioHub.shared.chirp(jelly: steerID, .ooh, x: px) }
            return
        }
        // phase 2: the glides
        let gl = T.glide
        let slipAt: Float = 1.45 * gl          // the flop slips here (in the second glide)
        let slipping = fail && t > slipAt
        let tg = slipping ? slipAt : t
        let gIdx = min(n - 1, Int(tg / gl))
        let u = min(1, (tg - Float(gIdx) * gl) / gl)
        let slider = (s0 + gIdx) % 2, stand = 1 - slider
        // the root glides back at a steady speed (it never stops between glides: that is the trick)
        var back = D * (tg / gl)
        if slipping {
            // the flop: the slider shoots on back, he lurches back and wobbles with the arms up, then gives up and walks back
            let w = t - slipAt, k = smooth01(w / 0.18)
            back += 0.10 * a * k
            let rootW = base - fwd * back
            px = rootW.x; pz = rootW.y
            pitch += -0.30 * a * smooth01(w / 0.12) * expf(-max(0, w - 0.12) / 0.45) + 0.08 * a * expf(-w / 0.3) * sinf(2 * .pi * 3.5 * w)
            roll = 0.14 * a * expf(-w / 0.4) * sinf(2 * .pi * 2.6 * w)
            squash = 1 - 0.06 * expf(-w / 0.15)
            twist = 0; lift = 0
            let rootG0 = Float(gIdx) * D
            let sFrom = base + off[slider] + fwd * (0.5 * D - rootG0)
            let sTo = base + off[slider] + fwd * (-0.5 * D - rootG0 - D)
            feet.pos[slider] = sFrom + (sTo - sFrom) * u - fwd * (0.16 * a * k)
            moonHeel(stand: stand, k: 1 - smooth01(w / 0.15))
            trickArms((0.95, 0.35, 0.09, 0.05, 1), dt)
            if mwOnce(1) { face(.worried, hold: 1.4); AudioHub.shared.chirp(jelly: steerID, .uhoh, x: px); jellyKick = max(jellyKick, 1.6) }
            if w > 0.85 { moonwalkLeaveGlides(sim, skinner, toPoint: false) }
            return
        }
        let rootW = base - fwd * back
        px = rootW.x; pz = rootW.y
        // the standing foot: pinned where it is (up on its toe); the slider: from half a stride ahead of the root to half a stride behind it, flat, at twice the root's speed
        let rootG0 = Float(gIdx) * D
        let sFrom = base + off[slider] + fwd * (0.5 * D - rootG0)
        let sTo = base + off[slider] + fwd * (-0.5 * D - rootG0 - D)
        feet.pos[slider] = sFrom + (sTo - sFrom) * u
        feet.pos[stand] = base + off[stand] + fwd * (-0.5 * D - rootG0)
        feet.yaw = [yaw, yaw]
        // the switch: the slid foot pops up onto its toe as the other heel drops (crossfaded over the last / first ~0.1 s of a glide)
        let xf: Float = 0.10 / gl
        let kIn = smooth01(u / xf), kOut = 1 - smooth01((u - (1 - xf)) / xf)
        moonHeel(stand: stand, k: kOut, other: gIdx < n - 1 ? 1 - kOut : 0)
        _ = kIn
        // the body: the lean, NO bob through the slide, a small dip at each switch, the hips roll toward the standing foot and twist with the slider
        let sw = 1 - smooth01(min(u, 1 - u) / xf)          // 1 at a switch, 0 mid-glide
        let side: Float = stand == 1 ? 1 : -1
        pitch += T.lean * a
        squash = 1 - T.dip * sw * a
        roll = -side * T.hipRoll * a * (1 - sw)
        twist = side * T.twist * a * sinf(.pi * u)
        lift = 0
        // the arms: bent, swinging a little against the slider (stubs: only the direction turns)
        armDirW = 1; armDirOut = 0.04
        for s in 0..<2 {
            let sd: Float = s == 0 ? -1 : 1
            let sway: Float = (s == slider ? 1 : -1) * 0.35 * sinf(.pi * u)
            armDirEl[s] = 0.32 + 0.10 * sway
            armDirSa[s] = sd * (0.55 + sway)
        }
        if idleState.hop != gIdx + 1 { idleState.hop = gIdx + 1; jellyKick = max(jellyKick, 0.3); if gIdx > 0 { AudioHub.shared.footstep(jelly: steerID, x: px, running: false) } }
        if t >= Float(n) * gl { moonwalkLeaveGlides(sim, skinner, toPoint: true) }
    }

    /// The standing foot up on its toe (`k` 0...1), the other foot's heel coming up at the switch (`other`). v2 writes `trick.heelUp` (the driveLimbs hook); v1 swings the
    /// standing foot in place (lift and toe-down tilt together) once per glide.
    private func moonHeel(stand: Int, k: Float, other: Float = 0) {
        typealias T = MoonwalkTuning
        if T.heelUp > 0 {
            var h = SIMD2<Float>.zero
            h[stand] = T.heelUp * k * amplitude
            h[1 - stand] = T.heelUp * other * amplitude
            idleState.trick.heelUp = h
        } else {
            idleState.trick.heelUp = .zero
            // v1: one in-place swing of the standing foot per glide (it stays where it is; FootGait reports a lift and a toe-down tilt)
            if !feet.active || feet.side != stand, k > 0.5, idleState.trick.flags & (1 << (8 + stand)) == 0 {
                idleState.trick.flags |= 1 << (8 + stand); idleState.trick.flags &= ~(1 << (8 + (1 - stand)))
                feet.begin(side: stand, to: feet.pos[stand], toYaw: feet.yaw[stand], peak: T.v1Lift * amplitude, rate: 1 / T.glide, swingFrac: 0.98, tilt: -T.v1Tilt)
            }
        }
    }

    /// The glides are over: square the feet under him and turn to the camera for the point (or, the flop, straight to the walk back).
    private func moonwalkLeaveGlides(_ sim: SoftBody, _ skinner: Skinner, toPoint: Bool) {
        idleState.trick.heelUp = .zero
        feet.reset()
        idleState.goalYaw = faceCameraYaw()
        if toPoint { idleState.phase = 3; idleState.phaseT = 0 } else { moonwalkWalkBack(sim, skinner) }
    }

    private func runMoonwalkPoint(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        // turn to the camera with steps, then the pose: one arm flicked out and up (within the stub's cap), up on the toes, a giggle
        if idleState.trick.flags & 2 == 0 {
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.15)
            gaitPose(sway: 0.04, bob: 0.02, rock: 0.3)
            trickArms((0.30, 0.15, 0.04, 0.08, 0.6), dt)
            if turning || feet.active { idleState.phaseT = 0; return }
            idleState.trick.flags |= 2; idleState.phaseT = 0
        }
        let t = idleState.phaseT, a = amplitude
        let k = smooth01(t / 0.14) * (1 - smooth01((t - (MoonwalkTuning.point - 0.25)) / 0.25))
        squash *= 1 + 0.06 * k * a
        roll += Float(idleState.sign) * 0.06 * k * a
        armWalkWant = 0
        armDirW = k; armDirOut = 0.06
        let pt = idleState.sign > 0 ? 1 : 0
        for s in 0..<2 {
            let sd: Float = s == 0 ? -1 : 1
            armDirEl[s] = s == pt ? 0.55 : 0.20
            armDirSa[s] = sd * (s == pt ? 1.1 : 0.4)
        }
        if mwOnce(2) { face(.excited, hold: 1.0); skinner.setEyeOpenness(1); jellyKick = max(jellyKick, 1.2); AudioHub.shared.chirp(jelly: steerID, .giggle, x: px); blushBump(hold: 1.4, peak: 0.4) }
        if t > MoonwalkTuning.point, !feet.active { armDirW = 0; armDirOut = 0; moonwalkWalkBack(sim, skinner) }
    }

    private func moonwalkWalkBack(_ sim: SoftBody, _ skinner: Skinner) {
        armDirW = 0; armDirOut = 0; idleState.trick.armA = 0
        let home = SIMD2(idleState.trick.root.x, idleState.trick.root.y)
        guard MoonwalkTuning.walkBack, simd_length(home - SIMD2(px, pz)) > 0.12 else { moonwalkHome(skinner); return }
        idleState.phase = MoonwalkTuning.walkBackPhase; idleState.phaseT = 0
        script = .walk(target: home, then: .none); activity = .walking
    }
}
