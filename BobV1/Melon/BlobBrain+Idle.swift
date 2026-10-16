//
//  BlobBrain+Idle.swift
//  Room life (I1): the random things Bob does while he roams. Five behaviours on top of the locked walk:
//    RUN      a short dash across the rug (the walk's stride x1.2, step rate x1.125 = speed x1.35, a 5.5 deg forward lean, a bigger arm sweep);
//             about one run in three ends in a STUMBLE (a trip that keeps one foot down: lurch, arms flung out, a wobble, a catch, an embarrassed
//             shake, then he carries on walking);
//    JACKS    4...6 jumping jacks in place (the hop is the only thing that takes both feet off the floor; the stub arms swing up over the sides, the
//             feet go apart and together, a squash on landing, then a satisfied little bounce);
//    SIT      he settles into a sitting blob (squash, feet forward, half-closed eyes, slow breathing, an occasional content sway) and gets up;
//             the grumpy version is a slump facing a little away;
//    LOOK     turns to look at something with a curious lean;
//    YAWN     a stretch up (body elongates, stub arms up) with a yawn (the mouth opens for the yawn only).
//  The scheduler hook is `idleMaybeStart` (top of `pickAutonomous`); behaviours are weighted by mood (`IdleTable`), at most one special every
//  15...30 s, never the same one twice in a row. They never run during focus mode, a meal, Come here or a touch / throw get-up, and they yield
//  to those within 0.3 s (`idleGate`). Everything is a render-side or pose-side drive that is released at the end: the walk, the hop and the arm
//  capsules are the existing machinery.
//

import Foundation
import simd

typealias IdleMood = BlobMood

enum IdleKind: String, CaseIterable, Sendable {
    case wander, run, stumble, jacks, sit, slump, look, yawn
}

/// Mood -> which behaviours he picks from. `.wander` = no special this time (the existing wander table, slow and small when grumpy).
enum IdleTable {
    static func weights(_ m: IdleMood) -> [(kind: IdleKind, weight: Float)] {
        switch m {
        case .happy: return [(.run, 3), (.jacks, 3), (.look, 0.8), (.wander, 2)]
        case .okay: return [(.sit, 3), (.look, 2), (.yawn, 1.5), (.wander, 2)]
        case .grumpy: return [(.slump, 3), (.wander, 2)]
        }
    }
    /// The special (non-wander) behaviours of a mood.
    static func set(_ m: IdleMood) -> Set<IdleKind> { Set(weights(m).map { $0.kind }.filter { $0 != .wander }) }
    /// Weighted pick, never `last`. `r` in 0..<1.
    static func pick(_ m: IdleMood, last: IdleKind?, r: Float) -> IdleKind {
        // never the same special twice in a row (unless the mood has only one)
        let w = weights(m).filter { $0.kind != last || $0.kind == .wander || set(m).count < 2 }
        let total = w.reduce(0) { $0 + $1.weight }
        var x = r * total
        for e in w { if x < e.weight { return e.kind }; x -= e.weight }
        return w.last!.kind
    }
}

struct IdleState {
    var kind: IdleKind?                         // the running behaviour (nil = none)
    var last: IdleKind?
    var cooldown: Float = 9                     // seconds until the next special may start
    var t: Float = 0                            // seconds since the behaviour began
    var phase = 0
    var phaseT: Float = 0
    var k: Float = 0                            // posture blend 0...1 (sit / slump / look / yawn)
    var hold: Float = 0                         // seconds of the held phase
    var sign: Float = 1
    var yielding = false
    var yieldT: Float = 0
    var target = SIMD2<Float>.zero              // the run's goal
    var stumbleAt: Float = 0                    // distance to the goal at which the run trips (0 = no trip)
    var steps = 0
    var baseYaw: Float = 0
    var goalYaw: Float = 0
    // jumping jacks
    var reps = 0, hop = 0, landT: Float = 0, jackA: Float = 0
    var counts: [IdleKind: Int] = [:]
    var tooFar = false
}

extension BlobBrain {
    static let runLean: Float = 5.5 * .pi / 180
    static let runArmGain: Float = 0.3
    var runStrideMul: Float { 1 + 0.2 * runW }
    var runRateMul: Float { 1 + 0.125 * runW }

    var idleActivity: Activity {
        switch idleState.kind {
        case .run, .stumble: return .walking
        case .jacks: return .playing
        default: return .lookingAround
        }
    }

    // MARK: scheduler

    /// Called from `pickAutonomous` (a pick is due, script .none): starts a special when the cooldown is over. True = a behaviour started.
    func idleMaybeStart(_ sim: SoftBody) -> Bool {
        guard idleState.kind == nil, !idleBlocked, idleState.cooldown <= 0, attached else { return false }
        let kind = IdleTable.pick(idleMood, last: idleState.last, r: rand())
        if kind == .wander { idleState.cooldown = rand(5, 9); return false }
        return idleStart(kind, sim)
    }

    /// Mood shapes the ordinary wander table too: grumpy skips waves and play, and idles longer.
    func idleShapeWander(_ w: inout [(Int, Float)]) {
        if idleMood == .grumpy { w.removeAll { $0.0 == 3 || $0.0 == 4 } }
    }
    func idleLegMax(_ m: Float) -> Float { idleMood == .grumpy ? min(m, 1.8) : m }

    /// Every tick before the gait: counts the cooldown, yields to anything else, notices the end of a run.
    func idleGate(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let kind = idleState.kind else {
            if autonomy && !idleBlocked { idleState.cooldown -= dt }
            return
        }
        idleState.t += dt
        // a script that is not ours any more (the care menu started a hop, ...)
        var mine = false
        switch script {
        case .idle: mine = true
        case .walk: mine = kind == .run || kind == .stumble
        default: mine = false
        }
        if !mine { idleReset(skinner); return }
        if (pending != nil || (!autonomy && demo == nil && !idleForced) || idleBlocked) && !idleState.yielding {
            switch kind {
            case .sit, .slump, .look, .yawn: idleState.yielding = true; idleState.yieldT = 0; feet.reset(); stepLive = false
            default: abortAll(sim, skinner); return
            }
        }
        if case .walk(let target, _) = script, kind == .run, idleState.stumbleAt > 0, runW > 0.9,
           simd_length(target - SIMD2(px, pz)) < idleState.stumbleAt {
            idleState.kind = .stumble; idleState.phase = 0; idleState.phaseT = 0; idleState.t = 0
            route = []; walkFinal = false
            script = .idle
        }
    }

    /// Ease the run blend: 1 while a run is under way and more than ~1.1 u from the goal, else back to 0 (exactly 0 once small).
    func idleUpdateRun(_ dt: Float) {
        var want: Float = 0
        if idleState.kind == .run, case .walk(let target, _) = script, simd_length(target - SIMD2(px, pz)) > 1.1 { want = 1 }
        if runW == want { return }
        runW += max(-dt / 0.6, min(dt / 0.6, want - runW))
        if want == 0 && runW < 1e-3 { runW = 0 }
    }

    func idleEnd(_ skinner: Skinner?, cooldown: Bool = true) {
        if let k = idleState.kind {
            idleState.last = k == .stumble ? .run : k
            idleState.counts[k, default: 0] += 1
            if cooldown { idleState.cooldown = max(8, rand(15, 30) - idleState.t) }
        }
        idleState.kind = nil; idleState.yielding = false; idleState.k = 0
        armDirW = 0; armDirOut = 0
        skinner?.setEyeOpenness(1)
    }

    /// Hard stop (abort, touch, request): the render overrides go, the eyes open, nothing of the behaviour is left.
    func idleReset(_ skinner: Skinner?) {
        guard idleState.kind != nil || armDirW != 0 || runW != 0 else { return }
        let wasRun = runW != 0
        idleEnd(skinner, cooldown: idleState.kind != nil)
        idleState.phase = 0
        if wasRun { runW = 0 }
        mouthOpen = 0
    }

    // MARK: starting

    private func idleBegin(_ kind: IdleKind) {
        idleState.kind = kind
        idleState.t = 0; idleState.phase = 0; idleState.phaseT = 0; idleState.k = 0; idleState.yielding = false; idleState.yieldT = 0
        idleState.steps = 0; idleState.stumbleAt = 0
        idleState.sign = rand() < 0.5 ? -1 : 1
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
    }

    /// Start `kind` now (the scheduler, tests and the capture demos). False = no room / not possible.
    @discardableResult
    func idleStart(_ kind: IdleKind, _ sim: SoftBody) -> Bool {
        if idleState.kind != nil { return false }
        currentPose(sim)
        let here = SIMD2(px, pz)
        switch kind {
        case .wander, .stumble: return false
        case .run:
            var goal: SIMD2<Float>?
            for _ in 0..<160 {
                var cand: SIMD2<Float>
                if let r = wanderRect { cand = SIMD2(rand(r.min.x, r.max.x), rand(r.min.y, r.max.y)) }
                else {
                    let a = rand() * 2 * .pi, rr = wanderRadius * rand().squareRoot()
                    cand = wanderCenter + SIMD2(sinf(a), cosf(a)) * rr
                }
                let rv = resolve(SIMD3(cand.x, 0, cand.y), footprint)
                let c2 = SIMD2(rv.x, rv.z)
                let d = simd_length(c2 - here)
                if d >= 2.5 && d <= 4.4 && simd_length(c2 - cand) < 0.05 && legClear(here, c2, margin: steerMargin) { goal = c2; break }
            }
            guard let g = goal else { return false }
            idleBegin(.run)
            idleState.target = g
            // about one run in three ends in a trip (needs room: the trip happens 1.9 u before the goal)
            if rand() < 0.34 && simd_length(g - here) >= 3.2 { idleState.stumbleAt = 1.9 }
            script = .walk(target: g, then: .none); activity = .walking
        case .jacks:
            idleBegin(.jacks)
            idleState.reps = 4 + Int(rand() * 3)             // 4...6
            idleState.hop = 0; idleState.landT = 0; idleState.jackA = 0
            idleState.baseYaw = yaw
            script = .idle; activity = .playing
        case .sit, .slump:
            idleBegin(kind)
            idleState.hold = rand(6, 12)
            // face the camera, or a little away from it (a content sit is turned a touch, the slump faces away)
            let off: Float = kind == .slump ? 0.6 : 0.3
            idleState.goalYaw = faceCameraYaw() + idleState.sign * off * (kind == .slump ? 1 : rand(0.4, 1))
            script = .idle; activity = .lookingAround
        case .look:
            idleBegin(.look)
            idleState.baseYaw = yaw
            idleState.hold = rand(1.6, 2.6)
            idleState.goalYaw = faceCameraYaw() + idleState.sign * rand(0.8, 1.3)
            script = .idle; activity = .lookingAround
        case .yawn:
            idleBegin(.yawn)
            script = .idle; activity = .lookingAround
        }
        return true
    }

    // MARK: running the .idle script

    /// New foot step with the planted feet's reach (used by sit / get up: the feet go forward and come back under him).
    private func idleFootStep(reach: Float, rate: Float = 2.6, peak: Float = 0.055) {
        let u = SIMD2(sinf(yaw), cosf(yaw))
        startStep(reach: u * reach, peak: peak * amplitude, rate: rate, swingFrac: 0.8)
    }

    func runIdle(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let kind = idleState.kind else { script = .none; return }
        poseOn = true; ensureFeet(sim)
        idleState.phaseT += dt
        let hf = amplitude
        switch kind {
        case .stumble: runStumble(sim, skinner, dt)
        case .sit, .slump: runSit(sim, skinner, dt, slump: kind == .slump)
        case .look: runLook(sim, skinner, dt)
        case .yawn: runYawn(sim, skinner, dt)
        case .jacks:
            // phase 0 only: stand square toward the camera and lift the arms; the hops themselves run in `idleJacksTick`
            _ = turnSteps(goal: idleState.baseYaw, tol: 0.05)
            gaitPose(sway: 0.04, bob: 0.02, rock: 0.3)
            armWalkWant = 1
            if idleState.phaseT > 0.55 && !feet.active && armLift > 0.9 {
                idleState.phase = 1; idleState.phaseT = 0; idleState.landT = 0
                idleStartHop(sim, final: false)
            }
        default: break
        }
        _ = hf
    }

    // MARK: stumble

    /// The trip: every step keeps one foot planted. Timeline: a short stubbed step, a long lurching step (forward lean up to 0.30 rad, arms flung out),
    /// two quick catching steps (a wobble), a square step, the embarrassed shake, then the walk to the goal resumes.
    private func runStumble(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let ph = idleState.phase
        let ts = idleState.t
        let u = SIMD2(sinf(yaw), cosf(yaw))
        armWalkWant = 1
        func clipRoot(_ d: Float) -> SIMD2<Float> {
            let cand = SIMD2(px, pz) + u * d
            let rv = resolve(SIMD3(cand.x, 0, cand.y), footprint)
            return SIMD2(rv.x, rv.z) - SIMD2(px, pz)
        }
        if !feet.active {
            switch ph {
            case 0: startStep(rootD: clipRoot(0.07), reach: u * 0.01, peak: 0.035 * amplitude, rate: 5.0, swingFrac: 0.75); idleState.phase = 1; idleState.phaseT = 0
            case 1: startStep(rootD: clipRoot(0.36), reach: u * 0.20, peak: 0.075 * amplitude, rate: 3.6, swingFrac: 0.8); idleState.phase = 2; idleState.phaseT = 0
            case 2: startStep(rootD: clipRoot(0.15), reach: u * 0.05, peak: 0.06 * amplitude, rate: 4.4, swingFrac: 0.8); idleState.phase = 3; idleState.phaseT = 0
            case 3: startStep(rootD: clipRoot(0.07), reach: u * 0.02, peak: 0.05 * amplitude, rate: 4.2, swingFrac: 0.8); idleState.phase = 4; idleState.phaseT = 0
            case 4: startStep(peak: 0.05 * amplitude, rate: 3.2); idleState.phase = 5; idleState.phaseT = 0; idleState.t = 0
            default: break
            }
        }
        // the lurch (pitch forward, rad) and the wobble
        var lurch: Float = 0
        var wob: Float = 1
        if ph < 5 {
            let a = ts
            lurch = 0.30 * smooth01(a / 0.45) * (1 - 0.8 * smooth01((a - 0.9) / 0.9))
            wob = 1.0 + 1.4 * smooth01(a / 0.5)
        }
        gaitPose(sway: waddleRoll * wob, bob: ph < 5 ? 0.08 : 0.04)
        pitch += lurch
        if ph == 5 && !feet.active {
            // the embarrassed shake: a quick yaw wobble and squash pulses, eyes squinted, then back to walking
            let s = idleState.phaseT
            let env = expf(-s / 0.35)
            twist = 0.20 * env * sinf(2 * .pi * 6.5 * s)
            squash *= 1 - 0.07 * env * (0.5 - 0.5 * cosf(2 * .pi * 6.5 * s))
            skinner.setEyeOpenness(1 - 0.45 * smooth01(s / 0.15) * (1 - smooth01((s - 0.6) / 0.25)))
            armWalkWant = 1
            if s > 0.95 {
                skinner.setEyeOpenness(1)
                idleState.phase = 6
                route = []; walkFinal = false; scriptT = 0; stuckT = 0; bestDist = .infinity
                script = .walk(target: idleState.target, then: .none)
                activity = .walking
            }
        }
        // arms flung out for the lurch, flapping through the wobble, down again at the catch
        var aw: Float = 0
        if ph < 5 { aw = smooth01(ts / 0.30) * (1 - smooth01((ts - 1.5) / 0.5)) }
        idleState.k += (aw - idleState.k) * min(1, 18 * dt)
        armDirW = idleState.k
        let flap = 0.12 * sinf(2 * .pi * 3.2 * ts)
        armDirEl = [0.55 + flap, 0.55 - flap]
        armDirSa = [0.10, 0.10]
        armDirOut = 0.06
    }

    // MARK: sit / slump

    private func runSit(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, slump: Bool) {
        var k = idleState.k
        let phT = idleState.phaseT
        if idleState.yielding {
            idleState.yieldT += dt
            k = max(0, k - dt / 0.2)
            for s in 0..<2 {
                let nominal = SIMD2(px, pz) + rotXZ(geom.off[s], yaw)
                feet.pos[s] += (nominal - feet.pos[s]) * min(1, dt / 0.07)
            }
            if k <= 0.001 { idleState.k = 0; sitPose(skinner, 0, slump: slump); idleFinish(skinner); return }
        } else {
            switch idleState.phase {
            case 0:     // turn to the sitting direction
                let turning = turnSteps(goal: idleState.goalYaw, tol: 0.06)
                if !turning && !feet.active { idleState.phase = 1; idleState.phaseT = 0; idleState.steps = 0 }
            case 1:     // sit down: two feet step forward while the body lowers
                k = smooth01(phT / 1.15)
                if !feet.active && idleState.steps < 2 && phT > Float(idleState.steps) * 0.35 { idleFootStep(reach: slump ? 0.17 : 0.22); idleState.steps += 1 }
                if phT >= 1.15 && !feet.active { idleState.phase = 2; idleState.phaseT = 0 }
            case 2:     // hold
                k = 1
                if phT >= idleState.hold { idleState.phase = 3; idleState.phaseT = 0; idleState.steps = 0 }
            case 3:     // get up: the body rises while the feet step back under him
                k = 1 - smooth01(phT / 1.0)
                if !feet.active && idleState.steps < 2 && phT > Float(idleState.steps) * 0.3 { idleFootStep(reach: 0); idleState.steps += 1 }
                if phT >= 1.0 && !feet.active && idleState.steps >= 2 { k = 0; idleState.k = 0; sitPose(skinner, 0, slump: slump); idleFinish(skinner); return }
            default: break
            }
        }
        idleState.k = k
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        sitPose(skinner, k, slump: slump)
    }

    /// The posture at blend `k` (squash, lean back / slump forward, half-closed eyes, breathing, a content sway).
    private func sitPose(_ skinner: Skinner, _ k: Float, slump: Bool) {
        let t = idleState.t
        let breath = sinf(2 * .pi * t * 0.30)
        squash *= 1 - (slump ? 0.27 : 0.32) * k + (slump ? 0.008 : 0.016) * breath * k
        pitch += (slump ? 0.34 : -0.06) * k
        if !slump {
            let win = max(0, sinf(2 * .pi * t / 8.0)); roll += 0.055 * k * win * win * sinf(2 * .pi * t / 3.2)
        }
        skinner.setEyeOpenness(1 - (slump ? 0.62 : 0.5) * k)
    }

    // MARK: look

    private func runLook(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        var k = idleState.k
        let phT = idleState.phaseT
        if idleState.yielding {
            idleState.yieldT += dt
            k = max(0, k - dt / 0.2)
            if k <= 0.001 { idleState.k = 0; idleFinish(skinner); return }
        } else {
            switch idleState.phase {
            case 0:
                let turning = turnSteps(goal: idleState.goalYaw, tol: 0.06)
                k = min(1, k + dt / 0.5)
                if !turning && !feet.active { idleState.phase = 1; idleState.phaseT = 0 }
            case 1:     // look: a small nod / tilt
                k = 1
                if phT >= idleState.hold { idleState.phase = 2; idleState.phaseT = 0 }
            default:    // look back: lean off, turn back to the camera (or the heading he had)
                k = max(0, k - dt / 0.5)
                let home = facePlayerWhenIdle ? faceCameraYaw() : idleState.baseYaw
                let turning = turnSteps(goal: home, tol: 0.08)
                if !turning && !feet.active && k <= 0.001 { idleState.k = 0; idleFinish(skinner); return }
            }
        }
        idleState.k = k
        gaitPose(sway: 0.05, bob: 0.0, rock: 0.2)
        let t = idleState.t
        roll += idleState.sign * 0.10 * k + 0.012 * k * sinf(2 * .pi * t * 0.9)
        pitch += 0.05 * k + 0.02 * k * sinf(2 * .pi * t * 1.3)
    }

    // MARK: yawn / stretch

    private func runYawn(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        var k = idleState.k
        let phT = idleState.phaseT
        var mouth: Float = 0
        armWalkWant = 1
        if idleState.yielding {
            idleState.yieldT += dt
            k = max(0, k - dt / 0.2)
            if k <= 0.001 { idleState.k = 0; idleFinish(skinner); return }
        } else {
            switch idleState.phase {
            case 0:     // stretch up: arms up, body elongates, eyes squeeze
                if armLift < 0.9 && phT < 0.7 { break }
                k = min(1, k + dt / 0.9)
                if k >= 1 { idleState.phase = 1; idleState.phaseT = 0 }
            case 1:     // the yawn: the mouth opens wide, holds, closes
                k = 1
                let m = smooth01(phT / 0.55) * (1 - smooth01((phT - 1.05) / 0.45))
                mouth = 0.95 * m
                if phT >= 1.6 { idleState.phase = 2; idleState.phaseT = 0 }
            case 2:     // let go: arms down, a little slump
                k = max(0, k - dt / 0.6)
                if k <= 0.001 { idleState.k = 0; idleState.phase = 3; idleState.phaseT = 0 }
            default:    // a slow blink and a settle
                skinner.setEyeOpenness(1)
                if idleState.phaseT > 0.5 { idleFinish(skinner); return }
            }
        }
        idleState.k = k
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        let t = idleState.t
        let shake = idleState.phase == 1 ? 0.012 * sinf(2 * .pi * 7 * t) : 0
        squash *= 1 + 0.15 * smooth01(k) + shake
        pitch += -0.06 * smooth01(k)
        if idleState.phase == 2 { squash *= 1 - 0.05 * sinf(.pi * min(1, idleState.phaseT / 0.6)) }       // the let-go sag
        armDirW = smooth01(k)
        armDirEl = [0.95, 0.95]; armDirSa = [0.12, 0.12]; armDirOut = 0.07
        skinner.setEyeOpenness(1 - 0.85 * smooth01(k))
        mouthOpen = mouth
    }

    // MARK: finishing

    /// The behaviour is over: back to rest through the normal idle path.
    func idleFinish(_ skinner: Skinner) {
        idleEnd(skinner)
        mouthOpen = 0
        armWalkWant = 0
        script = .none
        restTimer = rand(1.0, 2.5)
    }

    // MARK: jumping jacks

    private func idleStartHop(_ sim: SoftBody, final: Bool) {
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        gait.facingYaw = yaw
        let pose = sim.bodyPose(iterations: 6)
        gait.home = SIMD2(pose.centroid.x, pose.centroid.z)
        poseW = 0; poseOn = false
        gait.hop(sim, to: SIMD2(pose.centroid.x, pose.centroid.z), reduceMotion: final || amplitude < 0.7)
        idleState.landT = 0
    }

    /// Hops 1... of the jacks (the hop machinery owns the body like a hop play): 2 hops per rep (arms up + feet apart, arms down + feet together),
    /// then one small satisfied bounce. True = this tick is fully handled.
    func idleJacksTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        guard idleState.kind == .jacks, idleState.phase >= 1, case .idle = script else { return false }
        let total = idleState.reps * 2 + 1
        activity = .playing
        mouthOpen = 0
        idleState.phaseT += dt
        // the hop machinery
        let hopGoal = -hopTipBack * attentionPitch * amplitude
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        gait.basePitch = pitchBase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        // next hop once the landing has shown its squash
        if gait.phase == .land { idleState.landT += dt } else { idleState.landT = 0 }
        let h = idleState.hop
        let finishing = h >= total
        if !finishing && (gait.phase == .land && idleState.landT >= 0.13) {
            idleState.hop += 1
            if idleState.hop < total { idleStartHop(sim, final: idleState.hop == total - 1) }
        }
        if idleState.hop >= total && !gait.isBusy {
            gait.basePitch = 0
            currentPose(sim)
            armDirW = 0; armDirOut = 0
            idleState.jackA = 0
            idleFinish(skinner)
            return true
        }
        // arms + feet: out on even hops (not the last bounce), together on odd
        let out: Float = (idleState.hop < total - 1 && idleState.hop % 2 == 0) ? 1 : 0
        idleState.jackA += max(-dt / 0.26, min(dt / 0.26, out - idleState.jackA))
        let a = smooth01(idleState.jackA)
        armWalkWant = 1
        armDirW = a
        armDirEl = [0.95, 0.95]; armDirSa = [0.10, 0.10]; armDirOut = 0.07
        driveBeansSpread(sim, skinner, dt, tuck: gait.tuck, spread: 0.20 * a)
        driveArms(sim, skinner, dt)
        return true
    }

    /// `driveBeansRigid` with the feet moved sideways (body frame) by `spread` each: apart for the jack, together at 0.
    private func driveBeansSpread(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float, tuck: Float, spread: Float) {
        guard beanFirstIdx.count == 2, geom.valid || { if !geom.valid { geom = FootGeom(sim: sim) }; return geom.valid }() else { return }
        prepareBeans(sim, skinner)
        guard footSkin.valid else { return }
        if beanScratch[0].count != FootBean.vertexCount { beanScratch = [[SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount), [SIMD3<Float>](repeating: .zero, count: FootBean.vertexCount)] }
        footShift = [.zero, .zero]
        fillBeansRigid(sim, into: &beanScratch, tuck: tuck)
        if spread != 0 {
            for s in 0..<2 {
                let d = sim.attractor.rotation.act(SIMD3<Float>((s == 0 ? -1 : 1) * spread, 0, 0))
                for i in 0..<FootBean.vertexCount { beanScratch[s][i] += d }
            }
        }
        commitBeans(sim, skinner, dt, want: tuck > 0.002 || spread > 0.002)
    }
}
