//
//  BlobBrain.swift
//  Bob's autonomous brain. Call `tick` once per fixed sim step (before `sim.step()`); it picks what Bob does
//  (wander, look around, step in place, wave, play) and drives only existing handles of the soft body:
//    - the rigid-pose attractor (position, heading, sway, bob, lean),
//    - per-particle targets on the arm / foot particle chains (SoftBody.targets) with temporarily softened arm tets,
//    - the eye openness of the skinner,
//    - GaitDriver for the hop / roll tricks.
//  The body rest shape is never touched: every drive is released afterwards and the jelly settles back by itself.
//

import Foundation
import simd

enum BlobRequest {
    case wave
    case goTo(SIMD2<Float>)
    case eat(at: SIMD2<Float>)
    case drink(at: SIMD2<Float>)
    case come(to: SIMD2<Float>)
}

enum BlobActivity: Equatable {
    case idle, walking, turning, lookingAround, steppingInPlace, waving, playing, eating, drinking, coming
    case touched, recovering
}

final class BlobBrain {
    typealias Activity = BlobActivity

    // MARK: public surface

    /// Master switch: when false `tick` does nothing (the stage runs its old hop-around).
    var enabled = true
    /// The studio stage feeds its orbit camera position into `cameraPosXZ`; the game screen (fixed camera) sets this false.
    var followsStudioCamera = true
    /// Autonomous behaviour (wandering, looking, waving, playing). Requests still run when false.
    var autonomy = true
    private(set) var activity: Activity = .idle
    /// Mouth opening 0...1 for the renderer: exactly 0 except while eating / drinking.
    private(set) var mouthOpen: Float = 0
    /// Floor position resolver (point, radius) -> corrected point. Default identity; the game passes RoomLayout.resolve.
    var resolve: (SIMD3<Float>, Float) -> SIMD3<Float> = { p, _ in p }
    /// Wander area (disk) used to pick idle targets and as the default bounds.
    var wanderCenter = SIMD2<Float>(0, 0)
    var wanderRadius: Float = 2.5
    /// Where the player's camera is on the floor plane (xz): he faces it to wave.
    var cameraPosXZ = SIMD2<Float>(0, 10)
    /// Optional rectangular wander area (min, max in x, z); when set it replaces the disk.
    var wanderRect: (min: SIMD2<Float>, max: SIMD2<Float>)?
    /// Longest wander leg.
    var maxWanderLeg: Float = 2.6
    /// When idle he turns to face the player and tilts back a little (`attentionPitch` rad) so his flat brows read
    /// friendly from a camera that looks down on him; relaxed while he walks.
    var facePlayerWhenIdle = false
    var attentionPitch: Float = 0
    /// Footprint radius used with `resolve`.
    var footprint: Float = 0.55
    /// 1 = full motion; lower for reduce-motion.
    var amplitude: Float = 1
    /// Called when a requested job (goTo / eat / drink / come / wave) has finished.
    var onFinished: ((BlobRequest) -> Void)?
    /// Test hook: seeds the random choices.
    var seed: UInt64 { get { rng } set { rng = newValue | 1 } }

    var walkSpeed: Float = 0.7            // world units / s (~0.6 body widths per second)
    var turnRate: Float = 3.0             // rad / s while turning with small steps
    /// His current floor position (xz) and heading as last driven / measured.
    var position: SIMD2<Float> { SIMD2(px, pz) }
    var heading: Float { yaw }

    private(set) var gait = GaitDriver()

    // MARK: state

    private enum Script {
        case none
        case walk(target: SIMD2<Float>, then: After)
        case turn(to: Float, then: After)
        case look(index: Int, t: Float, base: Float)
        case stepInPlace(t: Float, dur: Float)
        case wave(t: Float, side: Int, then: After)
        case spin(t: Float)
        case hopPlay
        case rollPlay
        case eat(t: Float, bowl: SIMD2<Float>, dur: Float, drink: Bool)
    }
    private enum After { case none, faceCamera, wave, face(SIMD2<Float>), eat(SIMD2<Float>, Bool), doEat(SIMD2<Float>, Bool) }

    private var script: Script = .none
    private var job: BlobRequest?           // the request being served (for onFinished)
    private var pending: BlobRequest?
    private var restTimer: Float = 1.2
    private var lastPick = -1
    private var sinceWave: Float = 8        // seconds since the last wave
    private var sincePlay: Float = 4

    // pose state (what the attractor is told)
    private var px: Float = 0, pz: Float = 0
    private var yaw: Float = 0
    private var roll: Float = 0, pitch: Float = 0, squash: Float = 1, lift: Float = 0
    private var pitchBase: Float = 0
    private var poseW: Float = 0            // 0 = free physics, 1 = fully driven
    private var poseOn = false              // whether the current step wants the pose driven
    private let kPose: Float = 650

    var debugFeet = true
    var swayScale: Float = 1
    var footStiffness: Float = 20000
    private var feet = FootStepper()
    /// Precomputed arm-path keyframes by path name (built in the background by `attach(renderMesh:)`).
    private(set) var armKeyframes: [String: ArmKeyframes] = [:]
    private var attached = false
    private var armBuilding = false
    private var armCostSum = 0.0, armCostN = 0
    private var armDelta: [SIMD3<Float>] = []
    private var armAO: [Float] = []
    private var armSide = 1
    private var armActive = false
    private var armT: Float = 0
    private var armBlend: Float = 0
    private var rng: UInt64 = 0xA24BAED4963EE407

    // touch recovery
    private var calmT: Float = 0
    private var recoverT: Float = 0
    private var gaitRecover = false
    private var stuckT: Float = 0
    private var bestDist: Float = .infinity
    private var scriptT: Float = 0

    init() {}
    // Avoids the runtime's isolated-deinit hop (it crashed the iOS 26.2 simulator runtime when a brain was released).
    nonisolated deinit {}

    /// A brain set up for the game screen: fixed camera, GameCamera floor bounds, faces the player when idle.
    static func forGame() -> BlobBrain {
        let b = BlobBrain()
        b.followsStudioCamera = false
        b.cameraPosXZ = SIMD2(GameCamera.eye.x, GameCamera.eye.z)
        b.resolve = { p, r in GameCamera.constrain(p, radius: r) }
        b.footprint = 0.7
        b.wanderRect = (SIMD2(-2.2, -2.3), SIMD2(2.2, 3.1))
        b.maxWanderLeg = 4.0
        b.facePlayerWhenIdle = true
        b.attentionPitch = 0.28
        let d = UserDefaults.standard
        if d.object(forKey: "BlobPitch") != nil { b.attentionPitch = Float(d.double(forKey: "BlobPitch")) }
        if d.integer(forKey: "BlobNoWander") != 0 { b.autonomy = false }
        return b
    }

    // MARK: demo (launch argument -BlobDemo <name>, for visual testing in the studio)

    var demo: String?
    private var demoStep = 0

    static func fromLaunchArguments() -> BlobBrain? {
        guard let name = UserDefaults.standard.string(forKey: "BlobDemo") else { return nil }
        let b = BlobBrain()
        b.demo = name
        b.autonomy = name == "idle" || name == "play"
        b.restTimer = 1.0
        return b
    }

    private func demoTick(_ sim: SoftBody) {
        guard let demo, case .none = script, pending == nil else { return }
        restTimer -= 1.0 / 60
        guard restTimer <= 0 else { return }
        demoStep += 1
        restTimer = 1.0
        switch demo {
        case "wave": pending = .wave
        case "walk": pending = .goTo(SIMD2(demoStep % 2 == 0 ? -1.3 : 1.3, 0))
        case "come": pending = .come(to: SIMD2(0, demoStep % 2 == 0 ? 0.3 : 1.5))
        case "eat": pending = .eat(at: SIMD2(0, -1.4))
        case "drink": pending = .drink(at: SIMD2(0, -1.4))
        case "step": currentPose(sim); script = .stepInPlace(t: 0, dur: 4); activity = .steppingInPlace
        case "look": currentPose(sim); script = .look(index: 0, t: 0, base: yaw); activity = .lookingAround
        default: break
        }
    }

    /// Paths whose keyframes are precomputed on attach (the wave; eating paths later).
    nonisolated static let armPaths: [ArmPath] = [.wave]
    /// Launch argument -WaveArmScale <x> (default 1): scales the posed arm's protrusion and radii together (comparison captures).
    static var waveArmScale: Double {
        UserDefaults.standard.object(forKey: "WaveArmScale") != nil ? UserDefaults.standard.double(forKey: "WaveArmScale") : 1
    }

    /// Give the brain the render mesh so the arm paths can be precomputed (off the main thread unless `synchronous`).
    /// A wave is deferred until its keyframes are ready.
    var hasRenderMesh: Bool { attached }
    var armReady: Bool { !armBuilding && !armKeyframes.isEmpty }
    func attach(renderMesh rm: RenderMesh, synchronous: Bool = false) {
        attached = true
        guard let cap = rm.armCapsule else { return }
        let rest = rm.rest, mat = rm.mat, scale = Self.waveArmScale
        let index = rm.index
        if synchronous {
            for p in Self.armPaths { armKeyframes[p.name] = ArmKeyframeBuilder.build(path: p, rest: rest, mat: mat, capsule: cap, index: rm.index, scale: scale) }
            return
        }
        armBuilding = true
        let paths = Self.armPaths
        Task.detached(priority: .utility) { [weak self] in
            var built: [ArmKeyframes] = []
            for p in paths {
                let kf = ArmKeyframeBuilder.build(path: p, rest: rest, mat: mat, capsule: cap, index: index, scale: scale)
                NSLog("%@", String(format: "[melon] arm path '%@' precompute: %.0f ms (%d keyframes)", p.name, kf.seconds * 1000, kf.intervals + 1))
                built.append(kf)
            }
            let result = built
            await MainActor.run {
                guard let self else { return }
                for kf in result { self.armKeyframes[kf.name] = kf }
                self.armBuilding = false
            }
        }
    }

    // MARK: requests

    func request(_ r: BlobRequest) { pending = r }

    /// Convenience: cancel whatever he is doing right now and serve `r` immediately (used by the care menu).
    func requestNow(_ r: BlobRequest) { pending = r; interruptScript = true }
    private var interruptScript = false

    // MARK: rng

    private func rand() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(rng >> 40) / Float(1 << 24)
    }
    private func rand(_ a: Float, _ b: Float) -> Float { a + (b - a) * rand() }

    // MARK: tick

    func tick(sim: SoftBody, skinner: Skinner, dt: Float, touched: Bool) {
        guard enabled else { return }
        sinceWave += dt; sincePlay += dt

        if touched {
            if activity != .touched { abortAll(sim, skinner) }
            activity = .touched
            calmT = 0; recoverT = 0
            return
        }
        if activity == .touched { activity = .recovering; gaitRecover = false; calmT = 0; recoverT = 0 }
        if activity == .recovering { recover(sim, skinner, dt); return }

        if interruptScript { interruptScript = false; if case .none = script {} else { abortScript(sim, skinner) } }

        // gait-driven tricks (hop / roll) own the attractor while they run
        switch script {
        case .hopPlay, .rollPlay:
            gait.tick(sim, held: false, reduce: amplitude < 0.7)
            if !gait.isBusy { finishScript(sim, after: false) }
            return
        default: break
        }

        if demo != nil { demoTick(sim) }
        if case .none = script {
            if let r = pending { pending = nil; start(request: r, sim) }
            else if autonomy {
                restTimer -= dt
                if restTimer <= 0 { pickAutonomous(sim) }
            }
        }

        poseOn = false
        runScript(sim, skinner, dt)
        drivePose(sim, dt)
        driveLimbs(sim, skinner, dt)
        updateActivity()
    }

    private func updateActivity() {
        switch script {
        case .none: activity = .idle
        case .walk: activity = isCome ? .coming : .walking
        case .turn: activity = isCome ? .coming : .turning
        case .look: activity = .lookingAround
        case .stepInPlace: activity = .steppingInPlace
        case .wave: activity = isCome ? .coming : .waving
        case .spin, .hopPlay, .rollPlay: activity = .playing
        case .eat(_, _, _, let drink): activity = drink ? .drinking : .eating
        }
    }

    // MARK: choosing

    private func currentPose(_ sim: SoftBody) {
        if poseW <= 0 {
            let p = sim.bodyPose(iterations: 8)
            px = p.centroid.x; pz = p.centroid.z; yaw = p.yaw
            roll = 0; pitch = 0; squash = 1; lift = 0
        }
    }

    private func faceCameraYaw() -> Float {
        #if DEBUG
        // capture aid: -BlobFaceYawOffset <rad> turns him away from the camera by that angle (back 3/4 views of the wave)
        let off = Float(UserDefaults.standard.double(forKey: "BlobFaceYawOffset"))
        #else
        let off: Float = 0
        #endif
        return atan2f(cameraPosXZ.x - px, cameraPosXZ.y - pz) + off
    }

    private func start(request r: BlobRequest, _ sim: SoftBody) {
        currentPose(sim)
        job = r
        scriptT = 0; stuckT = 0; bestDist = .infinity
        switch r {
        case .wave:
            script = .turn(to: faceCameraYaw(), then: .wave); activity = .turning
        case .goTo(let p):
            script = .walk(target: fixed(p), then: .none); activity = .walking
        case .eat(let b):
            script = .walk(target: fixed(bowlSpot(b)), then: .eat(b, false)); activity = .walking
        case .drink(let b):
            script = .walk(target: fixed(bowlSpot(b)), then: .eat(b, true)); activity = .walking
        case .come(let p):
            script = .walk(target: fixed(p), then: .faceCamera); activity = .coming
        }
    }

    private func fixed(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let r = resolve(SIMD3(p.x, 0, p.y), footprint)
        return SIMD2(r.x, r.z)
    }

    /// Where he stands to eat: right behind the bowl (away from the camera), facing the player over it, so the bowl's
    /// back rim is just in front of his feet and his mouth is above it.
    private func bowlSpot(_ bowl: SIMD2<Float>) -> SIMD2<Float> {
        return bowl + SIMD2(0, -0.66)
    }

    private func pickAutonomous(_ sim: SoftBody) {
        currentPose(sim)
        var w: [(Int, Float)] = [(0, 5), (1, 2), (2, 1.5)]
        if sinceWave > 18 { w.append((3, 2)) }
        if sincePlay > 10 { w.append((4, 2)) }
        w.removeAll { $0.0 == lastPick && $0.0 != 0 }
        let total = w.reduce(0) { $0 + $1.1 }
        var r = rand() * total
        var choice = w[0].0
        for (k, wt) in w { if r < wt { choice = k; break }; r -= wt }
        lastPick = choice
        scriptT = 0; stuckT = 0; bestDist = .infinity; job = nil
        switch choice {
        case 0:
            let here = SIMD2(px, pz)
            var target = here
            for _ in 0..<16 {
                var cand: SIMD2<Float>
                if let r = wanderRect { cand = SIMD2(rand(r.min.x, r.max.x), rand(r.min.y, r.max.y)) }
                else {
                    let a = rand() * 2 * .pi, rr = wanderRadius * rand().squareRoot()
                    cand = wanderCenter + SIMD2(sinf(a), cosf(a)) * rr
                }
                let rv = resolve(SIMD3(cand.x, 0, cand.y), footprint); cand = SIMD2(rv.x, rv.z)
                let d = simd_length(cand - here)
                if d > 0.8 && d < maxWanderLeg { target = cand; break }
            }
            if simd_length(target - here) < 0.3 { restTimer = 0.6; return }
            script = .walk(target: target, then: .none); activity = .walking
        case 1: script = .look(index: 0, t: 0, base: yaw)
        case 2: script = .stepInPlace(t: 0, dur: rand(1.8, 3.0)); activity = .steppingInPlace
        case 3:
            sinceWave = 0
            script = .turn(to: faceCameraYaw(), then: .wave); activity = .turning
        default:
            sincePlay = 0
            let k = rand()
            if k < 0.4 { startHop(sim) } else if k < 0.7 { script = .spin(t: 0); activity = .playing } else { startRoll(sim) }
        }
    }

    private func startHop(_ sim: SoftBody) {
        gait.wander = false
        gait.facingYaw = yaw
        gait.home = SIMD2(px, pz)
        let a = rand() * 2 * .pi
        var t = SIMD2(px, pz) + SIMD2(sinf(a), cosf(a)) * 0.6
        let rv = resolve(SIMD3(t.x, 0, t.y), footprint); t = SIMD2(rv.x, rv.z)
        poseW = 0
        gait.hop(sim, to: t, reduceMotion: amplitude < 0.7)
        script = .hopPlay; activity = .playing
    }

    private func startRoll(_ sim: SoftBody) {
        gait.wander = false
        gait.facingYaw = yaw
        gait.home = SIMD2(px, pz)
        let right = SIMD2<Float>(cosf(yaw), -sinf(yaw))
        let dir = rand() < 0.5 ? right : -right
        let target = SIMD2(px, pz) + dir * gait.rollTravel
        let rv = resolve(SIMD3(target.x, 0, target.y), footprint)
        if simd_length(SIMD2(rv.x, rv.z) - target) > 0.05 { startHop(sim); return }
        poseW = 0
        gait.roll(sim, toward: dir, reduceMotion: amplitude < 0.7)
        script = .rollPlay; activity = .playing
    }

    // MARK: scripts

    private func finishScript(_ sim: SoftBody, after served: Bool) {
        script = .none
        restTimer = rand(1.5, 4.0)
        if let j = job { job = nil; onFinished?(j) }
        _ = served
    }

    private func abortScript(_ sim: SoftBody, _ skinner: Skinner) {
        abortAll(sim, skinner)
        script = .none
        job = nil
    }

    private func abortAll(_ sim: SoftBody, _ skinner: Skinner) {
        mouthOpen = 0
        clearSkinOverride()
        sim.targets = []
        sim.restoreStiffness()
        gait.cancel(sim)
        sim.attractor.strength = 0
        skinner.setEyeOpenness(1)
        armActive = false; armBlend = 0
        feet.wantStep = false; feet.stepping = false; feet.clock = 0
        poseW = 0; poseOn = false
        script = .none
        job = nil
    }

    private func steer(to desired: Float, rate: Float, dt: Float) -> Float {
        let err = wrapAngle(desired - yaw)
        yaw += max(-rate * dt, min(rate * dt, err))
        return wrapAngle(desired - yaw)
    }

    private func runScript(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        scriptT += dt
        mouthOpen = 0
        feet.wantStep = false
        roll = 0; pitch = 0; squash = 1; lift = 0
        var attentive = true
        switch script { case .walk, .spin, .eat: attentive = false; default: break }
        let goal: Float = attentive ? -attentionPitch * amplitude : 0
        let dp = goal - pitchBase
        pitchBase += max(-1.2 * dt, min(1.2 * dt, dp))
        switch script {
        case .hopPlay, .rollPlay:
            break

        case .none:
            if facePlayerWhenIdle {
                poseOn = true
                let err = steer(to: faceCameraYaw(), rate: 1.4, dt: dt)
                feet.wantStep = abs(err) > 0.12
                sway(0)
            }

        case .walk(let target, let then):
            poseOn = true
            var d = target - SIMD2(px, pz)
            let dist = simd_length(d)
            if dist < 0.05 || scriptT > dist / 0.25 + 12 {
                step(after: then, sim); return
            }
            d /= dist
            let err = steer(to: atan2f(d.x, d.y), rate: turnRate * amplitude.clamped(0.5, 1), dt: dt)
            let align = smooth01(1 - abs(err) / 0.6)
            let sp = walkSpeed * amplitude.clamped(0.6, 1) * align * min(1, 0.25 + dist * 1.6)
            feet.wantStep = abs(err) > 0.12 || sp > 0.05
            let move = min(dist, sp * dt)
            let old = SIMD2(px, pz)
            px += sinf(yaw) * move; pz += cosf(yaw) * move
            let rv = resolve(SIMD3(px, 0, pz), footprint)
            px = rv.x; pz = rv.z
            if simd_length(SIMD2(px, pz) - old) < move * 0.3 { stuckT += dt } else { stuckT = max(0, stuckT - dt) }
            let nd = simd_length(target - SIMD2(px, pz))
            if nd < bestDist - 0.04 { bestDist = nd; stuckT = max(0, stuckT - 0.5) }
            if stuckT > 1.5 { step(after: .none, sim, giveUp: true); return }
            sway(sp)

        case .turn(let to, let then):
            poseOn = true
            let err = steer(to: to, rate: turnRate * amplitude.clamped(0.5, 1), dt: dt)
            feet.wantStep = abs(err) > 0.1
            sway(0)
            if abs(err) < 0.05 && !feet.stepping { step(after: then, sim) }

        case .look(let i, let t, let base):
            poseOn = true
            let seq: [Float] = [0.7, -0.7, 0.0]
            let err = steer(to: base + seq[i], rate: 1.6, dt: dt)
            feet.wantStep = abs(err) > 0.1
            sway(0)
            if abs(err) < 0.06 {
                let nt = t + dt
                if nt > (i == 2 ? 0.3 : 0.7) {
                    if i == 2 { finishScript(sim, after: false) } else { script = .look(index: i + 1, t: 0, base: base) }
                } else { script = .look(index: i, t: nt, base: base) }
            } else { script = .look(index: i, t: 0, base: base) }

        case .stepInPlace(let t, let dur):
            poseOn = true
            feet.wantStep = t < dur
            sway(0)
            script = .stepInPlace(t: t + dt, dur: dur)
            if t > dur && !feet.stepping { finishScript(sim, after: false) }

        case .spin(let t):
            poseOn = true
            let rate: Float = 5.5
            yaw = wrapAngle(yaw + rate * dt)
            feet.wantStep = true
            sway(0)
            let u = min(1, t / (2 * .pi / rate))
            squash = 1 - 0.05 * sinf(.pi * u) ; lift = 0
            script = .spin(t: t + dt)
            if t > 2 * .pi / rate + 0.1 && !feet.stepping { finishScript(sim, after: false) }

        case .wave(let t, let side, let then):
            poseOn = true
            if armBuilding { return }          // keyframes still being precomputed: stand and wait
            if !armActive { armSide = side; beginWave(sim, side: side) }
            script = .wave(t: t + dt, side: side, then: then)
            // lean away from the waving arm with a slight bounce
            let ext = WaveScript.extend(at: t)
            let lean = 0.24 * ext
            roll = Float(side) * lean
            squash = 1 + 0.03 * ext * sinf(2 * .pi * WaveScript.hz * max(0, t - WaveScript.raise))
            skinner.setEyeOpenness(WaveScript.eyeOpenness(at: t))
            if t >= WaveScript.duration {
                skinner.setEyeOpenness(1)
                endWave(sim)
                step(after: then, sim)
            }

        case .eat(let t, let bowl, let dur, let drink):
            poseOn = true
            let face = atan2f(bowl.x - px, bowl.y - pz)
            _ = steer(to: face, rate: turnRate, dt: dt)
            let down = smooth01(t / 0.5) * (1 - smooth01((t - (dur - 0.5)) / 0.5))
            pitch = 0.2 * down * amplitude
            let rhythm = sinf(2 * .pi * (drink ? 2.2 : 2.8) * t)
            squash = 1 - 0.05 * down * (0.5 + 0.5 * rhythm)
            // eyes stay open, with a quick happy squint now and then
            let pulse = max(0, sinf(2 * .pi * t / 1.25 - 1.2)) > 0.93 ? Float(1) : 0
            skinner.setEyeOpenness(1 - 0.7 * down * pulse)
            // chomp (eat: 2.8 Hz, 0.25...1) or quick lapping (drink: 4 Hz, 0.2...0.6), eased in and out with the lean
            let m = 0.5 + 0.5 * sinf(2 * .pi * (drink ? 4.0 : 2.8) * t)
            mouthOpen = down * (drink ? 0.2 + 0.4 * m : 0.25 + 0.75 * m)
            script = .eat(t: t + dt, bowl: bowl, dur: dur, drink: drink)
            if t >= dur { skinner.setEyeOpenness(1); mouthOpen = 0; finishScript(sim, after: true) }
        }
    }

    private func sway(_ speed: Float) {
        guard feet.stepping else { return }
        let s = feet.swing
        roll = feet.swingSide * 0.07 * swayScale * s * amplitude
        squash = 1 + 0.022 * swayScale * s * amplitude
        _ = speed
    }

    private func step(after: After, _ sim: SoftBody, giveUp: Bool = false) {
        scriptT = 0
        if giveUp { job = nil; script = .none; restTimer = 1; return }
        switch after {
        case .none: finishScript(sim, after: true)
        case .faceCamera:
            if isCome { script = .turn(to: faceCameraYaw(), then: .wave) }
            else { script = .turn(to: faceCameraYaw(), then: .none) }
        case .wave:
            armSide = rand() < 0.5 ? -1 : 1
            if UserDefaults.standard.object(forKey: "BlobWaveSide") != nil { armSide = UserDefaults.standard.integer(forKey: "BlobWaveSide") == 0 ? -1 : 1 }   // capture aid: -BlobWaveSide 0 = left (-1), 1 = right (+1)
            script = .wave(t: 0, side: armSide, then: .none)
        case .face(let p):
            script = .turn(to: atan2f(p.x - px, p.y - pz), then: .none)
        case .eat(let bowl, let drink):
            let face = atan2f(bowl.x - px, bowl.y - pz)
            script = .turn(to: face, then: .doEat(bowl, drink))
        case .doEat(let bowl, let drink):
            script = .eat(t: 0, bowl: bowl, dur: drink ? 3.2 : 3.0, drink: drink)
        }
    }
    private var isCome: Bool { if case .some(.come) = job { return true }; return false }

    // MARK: pose

    private func drivePose(_ sim: SoftBody, _ dt: Float) {
        if poseOn { poseW = min(1, poseW + dt / 0.25) } else { poseW = max(0, poseW - dt / 0.3) }
        guard poseW > 0 else { if sim.attractor.strength > 0 && !gait.isBusy { sim.attractor.strength = 0 }; return }
        let q = yawQuat(yaw) * simd_quatf(angle: roll, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: pitch + pitchBase, axis: SIMD3(1, 0, 0))
        sim.attractor.rotation = q
        sim.attractor.squash = squash
        sim.attractor.anchor = SIMD3(px, sim.groundedAnchorY(rotation: q, squash: squash) + lift, pz)
        sim.attractor.strength = kPose * smooth01(poseW)
    }

    // MARK: limbs

    private func beginWave(_ sim: SoftBody, side: Int) {
        armActive = true; armT = 0; armBlend = 0
    }

    private func endWave(_ sim: SoftBody) {
        if armCostN > 0 {
            NSLog("%@", String(format: "[melon] wave arm runtime: %.1f us per sim step (evaluate + hand-off), %d steps", armCostSum / Double(armCostN) * 1e6, armCostN))
            armCostSum = 0; armCostN = 0
        }
        armActive = false
        sim.targets.removeAll()
        sim.restoreStiffness()
        clearSkinOverride()
    }

    private func clearSkinOverride() {
        skinnerRef?.clearOverride()
    }
    private weak var skinnerRef: Skinner?

    private func driveLimbs(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        feet.advance(dt)
        if !debugFeet { feet.stepping = false }
        var list: [ParticleTarget] = []
        let needPose = armActive || feet.stepping
        guard needPose else {
            if !sim.targets.isEmpty { sim.targets.removeAll() }
            return
        }
        let pose = sim.bodyPose(iterations: 3)
        let c0 = sim.restCentroid
        @inline(__always) func world(_ rest: SIMD3<Float>) -> SIMD3<Float> { pose.centroid + pose.rotation.act(rest - c0) }

        if armActive, let kf = armKeyframes[ArmPath.wave.name] {
            armT += dt
            let tt0 = CFAbsoluteTimeGetCurrent()
            defer { armCostSum += CFAbsoluteTimeGetCurrent() - tt0; armCostN += 1 }
            kf.evaluate(side: armSide, s: WaveScript.s(at: armT), rotation: pose.rotation, delta: &armDelta, ao: &armAO)
            skinner.overrideVertices = kf.side(armSide).vertices
            skinner.overrideDelta = armDelta
            skinner.overrideMat = armAO
            skinnerRef = skinner
        }
        if feet.stepping {
            let s = feet.swing
            for a in sim.appendages where a.kind == .foot && Float(a.side) == feet.swingSide {
                for p in a.particles {
                    var r = sim.restPosition(p)
                    r.y += feet.lift * s * amplitude
                    r.z += feet.forward * s * amplitude
                    var w = world(r)
                    w.y = max(w.y, sim.floorY)
                    list.append(ParticleTarget(index: p, pos: w, stiffness: footStiffness))
                }
            }
        }
        sim.targets = list
    }

    // MARK: touch recovery

    private func recover(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        recoverT += dt
        if gaitRecover {
            gait.tick(sim, held: false, reduce: false)
            if !gait.isBusy { settleDone(sim) }
            return
        }
        let pose = sim.bodyPose(iterations: 6)
        let calm = sim.kineticEnergy() / sim.totalMass < 0.03 && sim.minY() < 0.04
        calmT = calm ? calmT + dt : 0
        if calmT > 0.5 || recoverT > 6 {
            gait.home = SIMD2(pose.centroid.x, pose.centroid.z)
            gait.facingYaw = yaw
            if pose.tilt > 0.5 {
                gaitRecover = true
                gait.returnHome(sim)
                if !gait.isBusy { settleDone(sim) }
            } else { settleDone(sim) }
        }
    }

    private func settleDone(_ sim: SoftBody) {
        let pose = sim.bodyPose(iterations: 8)
        gait.home = SIMD2(pose.centroid.x, pose.centroid.z)
        gaitRecover = false
        activity = .idle
        script = .none
        poseW = 0
        restTimer = rand(1.0, 2.0)
        currentPose(sim)
    }
}

private extension Float {
    func clamped(_ a: Float, _ b: Float) -> Float { Swift.min(b, Swift.max(a, self)) }
}
