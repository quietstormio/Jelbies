//
//  BlobBrain+Expression.swift
//  The expression layer (user 2026-10-20: "make more facial expressions ... I mean expressions with eyes and eyebrows"). A small per-brain state machine that
//  drives the face while NOTHING ELSE owns it:
//    eyes    openness (squints, the "^^" arc), per eye
//    brows   a raise along the face's up axis and a tilt about each brow's own centre (Skinner.browRaise / browTilt; the rigid-brow path)
//    mouth   open-only shapes (a little "o", an open happy mouth); NO closed-mouth smile arc (user decision)
//    head    a roll (a curious tilt, an excited wiggle) added to the pose
//    blush   a soft pink cheek tint (renderer uniform), fading in over ~2 s on happy moments, petting, cuddles, admiring
//  Everything eases over ~0.2 s. The layer yields to every system that owns the face (dining, the wave, yawn / sit / sleep, touch, social squints,
//  focus / bath, meals waiting) and hands back cleanly: it only resets values it wrote itself and that nobody has overwritten since.
//  With nothing asking for anything (a zero-offset face) the render is exactly the locked one.
//

import Foundation
import simd

enum FaceKind: String, CaseIterable, Sendable {
    case neutral
    case happy        // eyes squint a little, brows up
    case joyArc       // "^^" eyes, a squash pulse
    case oh           // a little "o" mouth
    case surprised    // brows high, wide eyes, "o"
    case curious      // one brow up, a head tilt
    case worried      // inner brow ends up, eyes slightly lowered
    case grumpy       // inner brow ends down (determined)
    case sleepy       // brows relaxed down, eyes half closed
    case excited      // brows bounce twice, a wiggle
    case focused      // brows level and a touch down, eyes narrowed
    case hopeful      // brows up and in, wide eyes
    /// Kinds whose brows leave the rest pose.
    var usesBrows: Bool { self != .neutral && self != .joyArc }
}

/// A face as the layer shows it: eyes (1 = open), mouth (0 = none), per-brow raise (rest units) and tilt (rad, + = inner end up), head roll (rad).
struct FacePose: Equatable {
    var eyeL: Float = 1, eyeR: Float = 1, mouth: Float = 0
    var raiseL: Float = 0, raiseR: Float = 0, tiltL: Float = 0, tiltR: Float = 0
    var roll: Float = 0
}

extension FaceKind {
    /// The target face of this expression `t` seconds in (`sign` flips the side of the curious tilt).
    func pose(t: Float, sign: Float = 1) -> FacePose {
        let r = ExprTuning.raise
        var p = FacePose()
        switch self {
        case .neutral: break
        case .happy: p.eyeL = 0.55; p.eyeR = 0.55; p.raiseL = 0.55 * r; p.raiseR = 0.55 * r
        case .joyArc: p.eyeL = 0.12; p.eyeR = 0.12; p.raiseL = 0.7 * r; p.raiseR = 0.7 * r
        case .oh: p.mouth = 0.22; p.raiseL = 0.8 * r; p.raiseR = 0.8 * r
        case .surprised: p.mouth = 0.22; p.raiseL = r; p.raiseR = r; p.tiltL = 0.05; p.tiltR = 0.05
        case .curious: p.raiseL = 0.95 * r; p.raiseR = -0.1 * r; p.tiltL = 0.18; p.tiltR = -0.06; p.eyeR = 0.85; p.roll = sign * 0.10
        case .worried: p.tiltL = 0.30; p.tiltR = 0.30; p.raiseL = 0.25 * r; p.raiseR = 0.25 * r; p.eyeL = 0.82; p.eyeR = 0.82
        case .grumpy: p.tiltL = -0.30; p.tiltR = -0.30; p.raiseL = -0.35 * r; p.raiseR = -0.35 * r; p.eyeL = 0.75; p.eyeR = 0.75
        case .sleepy: p.raiseL = -0.55 * r; p.raiseR = -0.55 * r; p.eyeL = 0.42; p.eyeR = 0.42; p.tiltL = -0.08; p.tiltR = -0.08
        case .excited:
            let b = 0.5 - 0.5 * cosf(2 * .pi * 4 * min(t, 0.5))          // up, down, up, down in 0.5 s
            p.raiseL = (0.15 + 0.85 * b) * r; p.raiseR = p.raiseL; p.eyeL = 0.8; p.eyeR = 0.8; p.mouth = 0.3
            p.roll = t < 0.5 ? 0.09 * sinf(2 * .pi * 4 * t) : 0
        case .focused: p.raiseL = -0.35 * r; p.raiseR = -0.35 * r; p.tiltL = -0.12; p.tiltR = -0.12; p.eyeL = 0.78; p.eyeR = 0.78
        case .hopeful: p.raiseL = 0.8 * r; p.raiseR = 0.8 * r; p.tiltL = 0.22; p.tiltR = 0.22
        }
        return p
    }
}

enum ExprTuning {
    /// Largest brow raise (rest units along the face's up axis). The lowest head-top wearable edge is ~0.05 above the brow tops (ExpressionTests measures it).
    static let raise: Float = 0.030
    /// Blend time constant: 95 % of the way in ~0.2 s.
    static let tau: Float = 0.065
    static let blushPeak: Float = 0.85
    static let blushRise: Float = 2.0, blushFall: Float = 2.6
}

struct ExpressionState {
    var kind: FaceKind = .neutral
    var t: Float = 0, dur: Float = 3
    var pickTimer: Float = 2
    var forcedLeft: Float = 0
    // eased outputs
    var eyeL: Float = 1, eyeR: Float = 1, mouth: Float = 0
    var raiseL: Float = 0, raiseR: Float = 0, tiltL: Float = 0, tiltR: Float = 0
    var roll: Float = 0
    var blush: Float = 0, blushHold: Float = 0, blushPeak: Float = ExprTuning.blushPeak
    var owned = false
    /// What this layer last wrote to the face (so a hand-over resets only its own values).
    var wroteEyes = false, wroteMouth: Float = 0
    var clock: Float = 0
    var pulsed = false
    // statistics (tests)
    var changes = 0
    var seen: [FaceKind: Int] = [:]
    var browSeen: Set<FaceKind> = []
    var maxBlush: Float = 0
    var enabled = true
    var seedSign: Float = 1
    var seeded = false
    /// The layer's own random stream (the brain's `rand()` sequence, which the seeded suites depend on, is never consumed here).
    var rngS: UInt64 = 0x9E3779B97F4A7C15
    mutating func rnd() -> Float {
        rngS ^= rngS << 13; rngS ^= rngS >> 7; rngS ^= rngS << 17
        return Float(rngS >> 40) / Float(1 << 24)
    }
    mutating func rnd(_ a: Float, _ b: Float) -> Float { a + (b - a) * rnd() }
}

extension BlobBrain {
    // MARK: public hooks

    /// Show `k` for `hold` seconds (an event, a flourish, a reaction). The layer repicks on its own afterwards.
    func face(_ k: FaceKind, hold: Float) {
        guard expr.enabled else { return }
        setFace(k, dur: hold)
        expr.forcedLeft = hold
    }
    /// A soft pink blush: fades in over ~2 s, holds `hold` seconds, fades out.
    func blushBump(hold: Float = 2.5, peak: Float = ExprTuning.blushPeak) {
        expr.blushHold = max(expr.blushHold, hold)
        expr.blushPeak = peak
    }
    var blushNow: Float { expr.blush }

    private func setFace(_ k: FaceKind, dur: Float) {
        if k != expr.kind { expr.changes += 1; expr.seen[k, default: 0] += 1; if k.usesBrows { expr.browSeen.insert(k) } }
        expr.kind = k; expr.t = 0; expr.dur = dur; expr.pulsed = false
        if k == .joyArc, !expr.pulsed { expr.pulsed = true; jellyKick = max(jellyKick, 0.5) }
    }

    // MARK: ownership

    /// True while another system owns the eyes / mouth / brows (the layer stays out of the way).
    var faceOwned: Bool {
        if activity == .touched || activity == .recovering { return true }
        if !autonomy && !idleForced && !commanded && demo == nil { return true }          // focus mode, bath, the care menu: they set the face themselves
        if held && !commanded { return true }
        if socialBook.squinting { return true }
        if isNapping { return true }
        switch script {
        case .dine, .eat, .wave, .flipPlay: return true
        default: break
        }
        if let k = idleState.kind {
            switch k {
            case .sleep, .sit, .slump, .sway, .yawn, .stretch, .flop, .peek, .stumble, .decorSit, .decorBoop, .decorPeek, .decorSlide, .tail: return true
            default: break
            }
        }
        return false
    }

    /// The head roll allowed now: only when he stands (a roll through a walking step would fight the locked gait).
    private var tiltAllowed: Bool {
        if runW > 0.01 || zoomW > 0.01 { return false }
        switch script {
        case .none, .look, .stepInPlace, .turn: break
        case .idle:
            guard let k = idleState.kind else { return false }
            switch k { case .giggle: break; default: return false }          // (a look has its own lean; a head tilt on top of it would lift a foot past the cap)
        default: return false
        }
        return poseOn || { if case .none = script { return facePlayerWhenIdle }; return false }()
    }

    // MARK: tick

    func expressionTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard dt > 0 else { return }
        if !expr.seeded { expr.seeded = true; expr.rngS ^= UInt64(truncatingIfNeeded: steerID + 1) &* 0x2545F4914F6CDD1D; if expr.pickTimer < 100 { expr.pickTimer = expr.rnd(1.0, 4.0) } }
        expr.clock += dt
        // blush: rises for ~2 s while asked for, then falls (independent of who owns the rest of the face)
        if expr.blushHold > 0 {
            expr.blushHold -= dt
            expr.blush = min(expr.blushPeak, expr.blush + dt * expr.blushPeak / ExprTuning.blushRise)
        } else if expr.blush > 0 {
            expr.blush = max(0, expr.blush - dt * ExprTuning.blushPeak / ExprTuning.blushFall)
        }
        expr.maxBlush = max(expr.maxBlush, expr.blush)

        guard expr.enabled else { return }
        var owned = faceOwned
        var focusedRace = false
        if race.active { owned = false; focusedRace = true }          // the race: a focused brow, nothing else
        let k = min(1, dt / ExprTuning.tau)
        if owned {
            if !expr.owned {
                expr.owned = true
                // hand over: reset only what the layer wrote and nobody has touched since
                if expr.wroteEyes, skinner.openness.left == expr.eyeL, skinner.openness.right == expr.eyeR { skinner.setEyeOpenness(1) }
                if expr.wroteMouth > 0, mouthOpen == expr.wroteMouth { mouthOpen = 0 }
                expr.wroteEyes = false; expr.wroteMouth = 0
                if expr.kind != .neutral { expr.kind = .neutral; expr.t = 0; expr.changes += 1; expr.seen[.neutral, default: 0] += 1 }
                expr.forcedLeft = 0
            }
            expr.eyeL = 1; expr.eyeR = 1; expr.mouth = 0
            expr.raiseL += (0 - expr.raiseL) * k; expr.raiseR += (0 - expr.raiseR) * k
            expr.tiltL += (0 - expr.tiltL) * k; expr.tiltR += (0 - expr.tiltR) * k
            expr.roll += (0 - expr.roll) * k
            applyBrows(skinner)
            return
        }
        if expr.owned {
            expr.owned = false
            expr.eyeL = skinner.openness.left; expr.eyeR = skinner.openness.right; expr.mouth = mouthOpen
            expr.pickTimer = expr.rnd(0.8, 1.8)
        }

        expr.t += dt
        if expr.forcedLeft > 0 { expr.forcedLeft -= dt }
        // choose
        if focusedRace {
            if expr.kind != .focused { setFace(.focused, dur: 99) }
        } else if expr.forcedLeft <= 0 {
            expr.pickTimer -= dt
            if expr.t >= expr.dur && expr.kind != .neutral { setFace(.neutral, dur: 99) }
            if expr.pickTimer <= 0 {
                let next = pickFace()
                setFace(next.0, dur: next.1)
                expr.pickTimer = expr.rnd(3.0, 6.0)
                if (next.0 == .happy || next.0 == .joyArc || next.0 == .excited) && idleMood == .happy && expr.rnd() < 0.45 { blushBump(hold: 2.4, peak: 0.6) }
            }
        }
        // targets
        let pose = expr.kind.pose(t: expr.t, sign: expr.seedSign)
        let eL = pose.eyeL, eR = pose.eyeR, tL = pose.tiltL, tR = pose.tiltR, rL = pose.raiseL, rR = pose.raiseR
        var m = pose.mouth, roll = pose.roll
        // an open happy mouth while he is bouncing about (never grumpy)
        if idleMood != .grumpy, expr.kind != .sleepy {
            var lively = runW > 0.3
            if let ik = idleState.kind { switch ik { case .skipHop, .hopscotch, .trot, .joy, .zoomies, .run, .scoot, .bounce, .jacks, .startle: lively = true; default: break } }
            if lively { m = max(m, 0.45) }
        }
        if !tiltAllowed { roll = 0 }
        // ease
        expr.eyeL += (eL - expr.eyeL) * k; expr.eyeR += (eR - expr.eyeR) * k
        expr.mouth += (m - expr.mouth) * min(1, dt / 0.04)
        expr.raiseL += (rL - expr.raiseL) * k; expr.raiseR += (rR - expr.raiseR) * k
        expr.tiltL += (tL - expr.tiltL) * k; expr.tiltR += (tR - expr.tiltR) * k
        expr.roll += (roll - expr.roll) * k
        if abs(expr.eyeL - 1) < 0.004 && eL == 1 { expr.eyeL = 1 }
        if abs(expr.eyeR - 1) < 0.004 && eR == 1 { expr.eyeR = 1 }
        if expr.mouth < 0.004 && m == 0 { expr.mouth = 0 }
        for p in [\ExpressionState.raiseL, \.raiseR, \.tiltL, \.tiltR, \.roll] as [WritableKeyPath<ExpressionState, Float>] {
            if abs(expr[keyPath: p]) < 1e-4 { expr[keyPath: p] = 0 }
        }
        // apply to the face
        if expr.eyeL < 1 || expr.eyeR < 1 || expr.wroteEyes {
            skinner.setEyeOpenness(left: expr.eyeL, right: expr.eyeR)
            expr.wroteEyes = !(expr.eyeL == 1 && expr.eyeR == 1)
        }
        if expr.mouth > 0 {
            if mouthOpen == 0 || mouthOpen == expr.wroteMouth { mouthOpen = expr.mouth; expr.wroteMouth = expr.mouth }
        } else if expr.wroteMouth > 0 {
            if mouthOpen == expr.wroteMouth { mouthOpen = 0 }
            expr.wroteMouth = 0
        }
        applyBrows(skinner)
    }

    private func applyBrows(_ skinner: Skinner) {
        let any = expr.raiseL != 0 || expr.raiseR != 0 || expr.tiltL != 0 || expr.tiltR != 0
        if any, !skinner.browsPrepared, !renderRest.isEmpty { skinner.prepareBrows(rest: renderRest) }
        skinner.browRaise[0] = expr.raiseL; skinner.browRaise[1] = expr.raiseR
        skinner.browTilt[0] = expr.tiltL; skinner.browTilt[1] = expr.tiltR
    }

    /// The next idle face (kind, how long): by mood and time of day; never the one he already shows.
    private func pickFace() -> (FaceKind, Float) {
        var w: [(FaceKind, Float)]
        switch idleMood {
        case .happy: w = [(.neutral, 30), (.happy, 18), (.joyArc, 13), (.excited, 12), (.curious, 9), (.focused, 4), (.surprised, 3), (.hopeful, 2)]
        case .okay: w = [(.neutral, 44), (.happy, 11), (.joyArc, 5), (.curious, 10), (.focused, 8), (.oh, 3), (.worried, 3), (.hopeful, 2), (.excited, 2)]
        case .grumpy: w = [(.neutral, 36), (.grumpy, 26), (.worried, 14), (.sleepy, 8), (.focused, 6)]
        }
        if idleNight > 0.05 {
            for i in w.indices { if w[i].0 == .neutral { w[i].1 *= 1 - 0.5 * idleNight } else if w[i].0 != .sleepy { w[i].1 *= 1 - 0.6 * idleNight } }
            w.append((.sleepy, 38 * idleNight))
        }
        w.removeAll { $0.0 == expr.kind }
        let total = w.reduce(0) { $0 + $1.1 }
        var x = expr.rnd() * total
        var pick = w[0].0
        for (kd, wt) in w { if x < wt { pick = kd; break }; x -= wt }
        expr.seedSign = expr.rnd() < 0.5 ? -1 : 1
        let dur: Float
        switch pick {
        case .neutral: dur = 99
        case .happy: dur = 1.5
        case .joyArc: dur = 0.6
        case .oh: dur = 0.8
        case .surprised: dur = 1.2
        case .curious: dur = 2.0
        case .worried: dur = 2.2
        case .grumpy: dur = 2.4
        case .sleepy: dur = 3.0
        case .excited: dur = 0.9
        case .focused: dur = 2.5
        case .hopeful: dur = 2.0
        }
        return (pick, dur)
    }
}

