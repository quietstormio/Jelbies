//
//  BathFlow.swift
//  "Clean": de-lint (roller) -> soap -> rinse -> shine, as a PHASE of the room (same stage, renderer and Bob, like dining; no second scene).
//
//  exit      Bob RUNS out of the room toward the camera (locked run gait: hurry + goTo). The soft-body fence and the brain's floor resolver are
//            lifted for this phase only (`fenceLifted`), so he can run past z = 3 and fill the frame.
//  fade      fade to white (opaque), swap the world while the overlay is fully opaque (fence back, Bob placed in the tub at `standPoint`, bath
//            set shown, camera SNAPPED to the bath close-up), hold a couple of frames, fade in. The same in reverse on return / cancel.
//  delint    the lint roller peels bits off (skipped when he has none)         soap   foam on the front he presents; >= 70 % -> rinse
//  rinse     spray washes the foam off; foam < 8 % and wet -> shine           shine  rub: wet dries, sparkle rises; full polish -> happy
//  finish    happy hop in place + hearts + success haptic, then back to the room.
//
//  The renderer reads `look`. Touches arrive from the stage already resolved (`touch(...)`), so tests drive the flow without ray casts.
//

import Foundation
import Observation
import simd
import QuartzCore

/// Every tunable of the clean-up in one place.
enum BathTuning {
    // exit
    static let exitCutZ: Float = 5.5, exitTimeout: Float = 3.5, exitTargetZ: Float = 7.2
    // white fade
    static let fadeOut: Float = 0.4, fadeIn: Float = 0.5
    /// Seconds the overlay stays opaque, and when inside that the world swap happens (the rest lets the room cache rebuild).
    static let holdSeconds: Float = 0.14, swapDelay: Float = 0.06
    // tools
    static let rollerRadius: Float = 0.2, brushRadius: Float = 0.18, rinseRadius: Float = 0.22
    static let soapGain: Float = 1.6, rinseGain: Float = 1.4, rinsePassive: Float = 0.35, polishGain: Float = 0.13
    static let soapDone: Float = 0.7, rinseDone: Float = 0.08, wetNeeded: Float = 0.5
    static let wetRise: Float = 1 / 1.2, wetFade: Float = 3
    static let promptSeconds: Float = 2.2, finishSeconds: Float = 2.5, delintSettle: Float = 0.5
    static let bubbleLife: ClosedRange<Float> = 0.9...1.8
}

enum BathPhase: Equatable { case off, exit, exitBack, fade, delint, soap, rinse, shine, finish }

@MainActor
@Observable
final class BathFlow {
    /// Where he stands in the tub (x, z on the floor; y = water level). The render worker's `BathSet.standPoint` wins at merge.
    static let standPoint = SIMD3<Float>(0, 0.17, 1.0)
    static var standXZ: SIMD2<Float> { SIMD2(standPoint.x, standPoint.z) }

    private(set) var phase: BathPhase = .off
    /// 0...1 white overlay opacity (the view draws it). Swaps only happen at exactly 1.
    private(set) var wipe: Float = 0
    /// Progress of the current tool (0...1) and the little prompt line. Rounded to 1 % so views do not redraw every step.
    private(set) var progress: Float = 0
    private(set) var prompt: String?
    /// The camera is on the bath close-up (0 / 1: it is snapped under the white, never blended on screen).
    @ObservationIgnored private(set) var cameraBlend: Float = 0

    /// What the renderer draws; written every step.
    @ObservationIgnored private(set) var look = BathLook()
    let grime: BlobGrime
    let wallet: DropsWallet
    @ObservationIgnored var sound: BathSound
    /// Light haptic tick (intensity, sharpness) and the success notification; GameCare wires them.
    @ObservationIgnored var haptic: (Float, Float) -> Void = { _, _ in }
    @ObservationIgnored var success: () -> Void = {}
    /// Capture aid: scripted fake scrubs (`-BlobGameDemo gclean`).
    @ObservationIgnored var demo = false

    // fade state
    enum Dest { case bath, room }
    enum FadeStage { case out, hold, `in` }
    @ObservationIgnored private(set) var fadeDest: Dest = .bath
    @ObservationIgnored private(set) var fadeStage: FadeStage = .out
    @ObservationIgnored private var holdT: Float = 0
    @ObservationIgnored private var swapped = false
    /// Every world swap that happened (tests assert the overlay was opaque at each).
    @ObservationIgnored private(set) var swapLog: [(wipe: Float, dest: Dest)] = []

    // exit / saved state
    @ObservationIgnored private var exitT: Float = 0
    @ObservationIgnored private var savedAutonomy = true
    @ObservationIgnored private var savedArena: Float?
    @ObservationIgnored private(set) var fenceLifted = false
    @ObservationIgnored private var lastPos: SIMD2<Float>?
    @ObservationIgnored private var rng: UInt32 = 0xBA7B

    // tool state
    @ObservationIgnored private var polish: Float = 0
    @ObservationIgnored private var wetStart: Float = 0
    @ObservationIgnored private var lintStart = 0
    @ObservationIgnored private var settleT: Float = 0
    @ObservationIgnored private var promptT: Float = 0
    @ObservationIgnored private var finishT: Float = 0
    @ObservationIgnored private var heartsLeft = 0
    @ObservationIgnored private var heartT: Float = 0
    @ObservationIgnored private var bubbleAge: [Float] = []
    @ObservationIgnored private var bubbleT: Float = 0
    @ObservationIgnored private var touching = false
    @ObservationIgnored private var demoT: Float = 0
    @ObservationIgnored private var wetFading = false

    init(persists: Bool? = nil, sound: BathSound? = nil) {
        let p = persists ?? (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)
        grime = BlobGrime(persists: p)
        wallet = DropsWallet(persists: p)
        self.sound = sound ?? PeelSound.shared
        look.sparkle = grime.sparkle
        look.lint = grime.bits
    }
    nonisolated deinit {}

    private func rand() -> Float { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return Float(rng >> 8) / Float(1 << 24) }

    // MARK: state queries

    var active: Bool { phase != .off }
    /// Finger scrubs reach him (the stage routes pet touches while this is true).
    var acceptsTouch: Bool { phase == .delint || phase == .soap || phase == .rinse || phase == .shine }
    /// The tool bar, its cancel button.
    var showsChrome: Bool { acceptsTouch || phase == .finish }
    var currentTool: BathTool {
        switch phase { case .delint: return .roller; case .soap: return .soap; case .rinse: return .rinse; case .shine: return .shine; default: return .none }
    }

    // MARK: start / cancel

    /// Tapping "Clean". Ignored while anything else runs (the menu row is disabled then too).
    func start(brain: BlobBrain, hurry: Bool = true) {
        guard phase == .off else { return }
        savedAutonomy = brain.autonomy
        brain.autonomy = false
        fenceLifted = true                      // sim fence: applied in `tick` (needs the sim); the brain's resolver reads this flag
        exitT = 0
        phase = .exit
        brain.hurry = hurry
        let here = brain.position
        brain.requestNow(.goTo(SIMD2(here.x * 0.5, BathTuning.exitTargetZ)))
        wetFading = false
        look.wet = 0
    }

    /// The cancel button / Done: everything goes back to the room.
    func cancel(brain: BlobBrain, sim: SoftBody?) {
        switch phase {
        case .off, .exitBack: return
        case .exit:
            brain.hurry = false
            brain.requestNow(.goTo(GameCamera.callSpot))
            phase = .exitBack
            if let sim, Self.floorZ(brain, sim) <= GameCamera.walkMaxZ { restoreAll(brain: brain, sim: sim) }
        case .fade:
            guard fadeDest == .bath else { return }             // already on the way back
            fadeDest = .room
            if fadeStage == .in { fadeStage = .out; swapped = false; holdT = 0 }      // the bath was already shown: fade out again, then swap back
        default:
            beginFade(.room)
        }
    }
    /// "Done" on the finish card.
    func done(brain: BlobBrain, sim: SoftBody?) { if phase == .finish { cancel(brain: brain, sim: sim) } }

    private static func floorZ(_ brain: BlobBrain, _ sim: SoftBody?) -> Float { GameCare.floorPos(brain, sim).y }

    private func beginFade(_ d: Dest) {
        fadeDest = d; fadeStage = .out; holdT = 0; swapped = false
        phase = .fade
        touching = false
        look.toolAt = nil; look.spray = nil
    }

    // MARK: world swaps (only ever called while the white overlay is fully opaque)

    private func swapToBath(brain: BlobBrain, sim: SoftBody?) {
        liftFence(false, sim: sim)
        fenceLifted = false
        brain.hurry = false; brain.runW = 0; brain.zoomW = 0
        if let sim { place(brain: brain, sim: sim, at: Self.standXZ) }
        look.visible = true
        look.foam = Array(repeating: 0, count: BathLook.rows * BathLook.cols)
        look.bubbles = []; bubbleAge = []; look.spray = nil; look.toolAt = nil
        look.wet = 0
        cameraBlend = 1
        polish = 0
        lintStart = grime.bits.count
        grime.sparkle = 0                       // he is about to be washed: the old shine goes
    }

    private func swapToRoom(brain: BlobBrain, sim: SoftBody?) {
        restoreAll(brain: brain, sim: sim, place: true)
        wetFading = true
    }

    /// Idempotent: fence, autonomy, hurry, camera, look.
    private func restoreAll(brain: BlobBrain, sim: SoftBody?, place: Bool = false) {
        liftFence(false, sim: sim)
        fenceLifted = false
        brain.hurry = false
        brain.autonomy = savedAutonomy
        if place, let sim { self.place(brain: brain, sim: sim, at: GameCamera.callSpot) }
        cameraBlend = 0
        look.visible = false
        look.foam = Array(repeating: 0, count: BathLook.rows * BathLook.cols)
        look.bubbles = []; bubbleAge = []; look.spray = nil; look.toolAt = nil; look.tool = .none
        touching = false; prompt = nil
        if phase != .fade { phase = .off }
        lastPos = nil
    }

    private func liftFence(_ lift: Bool, sim: SoftBody?) {
        guard let sim else { return }
        if lift {
            if savedArena == nil { savedArena = sim.arenaRadius }
            sim.arenaRadius = .infinity
        } else if let r = savedArena {
            sim.arenaRadius = r; savedArena = nil
        }
    }

    /// Teleports the body to a floor spot at rest (no velocity, no foot targets), resets the brain's pose and the jelly follow-through.
    private func place(brain: BlobBrain, sim: SoftBody, at p: SIMD2<Float>) {
        // stop whatever the brain was doing first (planted feet, gait, arm targets all live in the OLD world spot)
        if let sk = brain.skinnerRef { brain.abortScript(sim, sk) } else { brain.pending = nil; brain.feet.reset(); brain.feetInit = false; brain.poseW = 0 }
        brain.pending = nil
        sim.teleport(toXZ: p)
        brain.currentPose(sim)
        brain.runW = 0; brain.zoomW = 0
        brain.skinnerRef?.jelly.reset()
        lastPos = p
    }

    // MARK: per step

    func tick(brain: BlobBrain, sim: SoftBody?, play: TouchPlay?, dt: Float) {
        // lint builds up only while he roams the room
        let here = GameCare.floorPos(brain, sim)
        if phase == .off {
            var travelled: Float = 0
            let moving = brain.activity == .walking || brain.activity == .coming || brain.runW > 0.1
            if moving, let l = lastPos { let d = simd_length(here - l); if d < 0.5 { travelled = d } }
            lastPos = here
            grime.step(dt: dt, travelled: travelled)
            if wetFading { look.wet = max(0, look.wet - dt / BathTuning.wetFade); if look.wet == 0 { wetFading = false } }
        }
        let peeled = grime.advancePeel(dt: dt)
        for b in peeled where b.kind == .drop { wallet.add() }

        switch phase {
        case .off: break
        case .exit:
            liftFence(true, sim: sim)
            exitT += dt
            if here.y >= BathTuning.exitCutZ || exitT >= BathTuning.exitTimeout { beginFade(.bath) }
        case .exitBack:
            if here.y <= GameCamera.walkMaxZ { restoreAll(brain: brain, sim: sim) }
        case .fade: tickFade(dt: dt, brain: brain, sim: sim)
        case .delint:
            look.tool = .roller
            if demo { demoTouch(dt: dt, sim: sim) }
            let remaining = Float(grime.bits.count)
            progress = rounded(lintStart > 0 ? 1 - remaining / Float(lintStart) : 1)
            if grime.bits.isEmpty { settleT += dt; if settleT >= BathTuning.delintSettle { enter(.soap) } } else { settleT = 0 }
        case .soap:
            look.tool = .soap
            if demo { demoTouch(dt: dt, sim: sim) }
            progress = rounded(min(1, look.coverage / BathTuning.soapDone))
            tickBubbles(dt: dt)
            if look.coverage >= BathTuning.soapDone { enter(.rinse) }
        case .rinse:
            look.tool = .rinse
            if demo { demoTouch(dt: dt, sim: sim) }
            tickBubbles(dt: dt)
            if promptT > 0 { promptT -= dt; if promptT <= 0 { prompt = nil } }
            progress = rounded(min(1, max(0, 1 - look.coverage / BathTuning.soapDone)))
            if look.coverage < BathTuning.rinseDone && look.wet > BathTuning.wetNeeded { enter(.shine) }
        case .shine:
            look.tool = .shine
            if demo { demoTouch(dt: dt, sim: sim) }
            tickBubbles(dt: dt)
            progress = rounded(polish)
            if polish >= 1 { enter(.finish) }
        case .finish:
            look.tool = .none; look.toolAt = nil; look.spray = nil
            finishT += dt
            if heartsLeft > 0 { heartT -= dt; if heartT <= 0 { heartT = 0.45; heartsLeft -= 1; play?.spawnHeart(now: CACurrentMediaTime()) } }
            if finishT >= BathTuning.finishSeconds { beginFade(.room) }
        }
        if !acceptsTouch { touching = false; if phase != .exit { look.toolAt = nil; look.spray = nil } }
        look.lint = grime.bits
        look.sparkle = grime.sparkle
        happyHop(brain: brain, sim: sim)
    }

    private func rounded(_ v: Float) -> Float { (v * 100).rounded() / 100 }

    private func tickFade(dt: Float, brain: BlobBrain, sim: SoftBody?) {
        switch fadeStage {
        case .out:
            wipe = min(1, wipe + dt / BathTuning.fadeOut)
            if wipe >= 1 { fadeStage = .hold; holdT = 0 }
        case .hold:
            wipe = 1
            holdT += dt
            if !swapped, holdT >= BathTuning.swapDelay {
                swapped = true
                swapLog.append((wipe, fadeDest))
                if fadeDest == .bath { swapToBath(brain: brain, sim: sim) } else { swapToRoom(brain: brain, sim: sim) }
            }
            if holdT >= BathTuning.holdSeconds { fadeStage = .in }
        case .in:
            wipe = max(0, wipe - dt / BathTuning.fadeIn)
            if wipe <= 0 {
                if fadeDest == .bath { swapped = false; enterAfterFade() }
                else { phase = .off; prompt = nil }
            }
        }
    }

    private func enterAfterFade() {
        if grime.bits.isEmpty { enter(.soap) } else { enter(.delint) }
    }

    private func enter(_ p: BathPhase) {
        phase = p
        settleT = 0
        switch p {
        case .delint: lintStart = grime.bits.count; progress = 0
        case .soap: progress = 0; prompt = nil
        case .rinse: prompt = "Rinse him off!"; promptT = BathTuning.promptSeconds; progress = 0
        case .shine:
            prompt = "Shine him up!"; promptT = BathTuning.promptSeconds
            polish = 0; wetStart = look.wet; progress = 0
            look.foam = Array(repeating: 0, count: look.foam.count)
        case .finish:
            polish = 1; look.wet = 0; look.sparkle = 1; grime.sparkle = 1; grime.save()
            finishT = 0; heartsLeft = 3; heartT = 0
            prompt = "Sparkling clean!"
            success()
        default: break
        }
        if p == .finish { finishPending = true }
    }
    /// The happy hop needs the sim: flagged in `enter`, issued at the end of `tick`.
    @ObservationIgnored private var finishPending = false

    private func happyHop(brain: BlobBrain, sim: SoftBody?) {
        guard finishPending, let sim else { return }
        finishPending = false
        brain.startHopPlay(sim: sim, distance: 0.0001)       // an existing in-place hop (arm / feet caps already hold for it)
    }

    // MARK: touches

    /// One frame of finger input, already resolved on his body. `hitLocal` is in the REST frame relative to the rest centroid (TouchPlay.hitLocal);
    /// `world` is the same point in the world. Call every frame while `acceptsTouch` (contact false = finger off him).
    func touch(contact: Bool, hitLocal: SIMD3<Float>?, world: SIMD3<Float>?, speed: Float, dt: Float) {
        guard acceptsTouch else { return }
        touching = contact && hitLocal != nil
        guard touching, let l = hitLocal else { look.toolAt = nil; look.spray = nil; return }
        let w = world ?? l
        let v = min(speed, 4)
        look.toolAt = w
        switch phase {
        case .delint:
            if speed > 0.05 {
                for i in grime.startPeel(hit: l, radius: BathTuning.rollerRadius) {
                    sound.peel(kind: grime.bits[i].kind)
                    haptic(0.45, 0.8)
                }
            }
        case .soap:
            look.paint(local: l, radius: BathTuning.brushRadius, amount: BathTuning.soapGain * v * dt)
            if v > 0.3 { spawnBubbles(at: w, dt: dt) }
        case .rinse:
            look.spray = w + SIMD3(0, 0.55, 0.15)
            look.rinse(local: l, radius: BathTuning.rinseRadius, amount: (BathTuning.rinsePassive + BathTuning.rinseGain * v) * dt)
            look.wet = min(1, look.wet + BathTuning.wetRise * dt)
        case .shine:
            let before = polish
            polish = min(1, polish + BathTuning.polishGain * v * dt)
            look.wet = wetStart * (1 - polish)
            grime.sparkle = polish
            look.sparkle = polish
            if Int(before * 10) != Int(polish * 10) { haptic(0.25, 0.6) }
        default: break
        }
    }

    private func spawnBubbles(at w: SIMD3<Float>, dt: Float) {
        bubbleT -= dt
        guard bubbleT <= 0 else { return }
        bubbleT = 0.09
        let p = w + SIMD3(rand() - 0.5, rand() * 0.3, rand() * 0.3) * 0.3
        look.bubbles.append(SIMD4(p.x, p.y, p.z, 0.03 + 0.05 * rand()))
        bubbleAge.append(BathTuning.bubbleLife.lowerBound + (BathTuning.bubbleLife.upperBound - BathTuning.bubbleLife.lowerBound) * rand())
        if look.bubbles.count > BathLook.maxBubbles { look.bubbles.removeFirst(); bubbleAge.removeFirst() }
    }

    private func tickBubbles(dt: Float) {
        guard !look.bubbles.isEmpty else { return }
        for i in look.bubbles.indices { look.bubbles[i].y += 0.35 * dt; bubbleAge[i] -= dt }
        var k = 0
        while k < look.bubbles.count { if bubbleAge[k] <= 0 { look.bubbles.remove(at: k); bubbleAge.remove(at: k) } else { k += 1 } }
    }

    // MARK: scripted fake scrubs (capture aid)

    private func demoTouch(dt: Float, sim: SoftBody?) {
        demoT += dt
        let a = demoT * 3.1, b = demoT * 1.3
        // sweep the front: azimuth +-1.3 rad, polar 35-140 deg
        let az = sinf(a) * 1.3, polar = 1.5 + 0.9 * sinf(b)
        let dir = SIMD3(sinf(polar) * sinf(az), cosf(polar), sinf(polar) * cosf(az))
        let l = dir * 0.62
        let c = sim?.centroid() ?? SIMD3(0, 0.6, Self.standPoint.z)
        touch(contact: true, hitLocal: l, world: c + l, speed: 2.5, dt: dt)
        if phase == .delint, let b = grime.bits.first(where: { $0.peel == 0 }) {
            touch(contact: true, hitLocal: b.dir * 0.62, world: c + b.dir * 0.62, speed: 2.5, dt: dt)
        }
    }
}
