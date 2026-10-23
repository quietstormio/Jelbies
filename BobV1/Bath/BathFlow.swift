//
//  BathFlow.swift
//  "Clean": soap -> rinse -> shine, as a PHASE of the room (same stage, renderer and Bob, like dining; no second scene).
//
//  exit      Bob RUNS out of the room toward the camera (locked run gait: hurry + goTo). The soft-body fence and the brain's floor resolver are
//            lifted for this phase only (`fenceLifted`), so he can run past z = 3 and fill the frame.
//  fade      fade to white (opaque), swap the world while the overlay is fully opaque (fence back, Bob placed in the tub at `standPoint`, bath
//            set shown, camera SNAPPED to the bath close-up), hold a couple of frames, fade in. The same in reverse on return / cancel.
//  soap      foam on the front he presents (grey over the soot); >= 85 % covered -> "All soapy! Tap Next"
//  rinse     spray washes the foam (and the soot under it) off; foam < 3 % and wet -> "Squeaky clean! Tap Next"
//  shine     rub: wet dries, sparkle rises, stray soot is wiped; full polish -> "So shiny! Tap Next"
//  finish    happy hop in place + hearts + success haptic; the player taps Done to go back to the room.
//  The player completes every stage: reaching a goal only sets `stageComplete`; `advance()` (the Next button) moves on.
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
    static let brushRadius: Float = 0.18, rinseRadius: Float = 0.22
    static let soapGain: Float = 1.6, rinseGain: Float = 1.4, rinsePassive: Float = 0.35, polishGain: Float = 0.13
    /// A stage is done only when its goal is met AND the player taps Next (nothing auto-advances): soap covers most of him, the suds are
    /// (nearly) all rinsed off and he is wet, the shine is full.
    static let soapDone: Float = 0.85, rinseDone: Float = 0.03, wetNeeded: Float = 0.7, polishDone: Float = 1.0
    static let completeHaptic: (Float, Float) = (0.6, 0.5)
    static let wetRise: Float = 1 / 1.2, wetFade: Float = 3
    /// Only the hearts' timing now (the finish card waits for Done).
    static let finishSeconds: Float = 2.5
    /// The room soot pattern is re-seeded when dirt moves this much.
    static let sootReseed: Float = 0.004
    static let bubbleLife: ClosedRange<Float> = 0.9...1.8
}

enum BathPhase: Equatable { case off, exit, exitBack, fade, soap, rinse, shine, finish }

@MainActor
@Observable
final class BathFlow {
    /// Where he stands in the tub (x, z on the floor; y = water level). One source of truth: `BathSet.standPoint`.
    static let standPoint = BathSet.standPoint
    static var standXZ: SIMD2<Float> { SIMD2(standPoint.x, standPoint.z) }

    private(set) var phase: BathPhase = .off
    /// 0...1 white overlay opacity (the view draws it). Swaps only happen at exactly 1.
    private(set) var wipe: Float = 0
    /// Progress of the current tool (0...1) and the little prompt line. Rounded to 1 % so views do not redraw every step.
    private(set) var progress: Float = 0
    private(set) var prompt: String?
    /// The current stage's goal is met; the Next button shows (`advance()` moves on). Never set outside soap / rinse / shine.
    private(set) var stageComplete = false
    /// The camera is on the bath close-up (0 / 1: it is snapped under the white, never blended on screen).
    @ObservationIgnored private(set) var cameraBlend: Float = 0

    /// What the renderer draws; written every step.
    @ObservationIgnored private(set) var look = BathLook()
    /// The grime of the Jelly being washed (Bob's unless a clean-up of another Jelly is running; GameCare+Bath swaps it for the run).
    @ObservationIgnored private(set) var grime: BlobGrime
    let wallet: DropsWallet
    @ObservationIgnored var sound: BathSound
    /// Light haptic tick (intensity, sharpness) and the success notification; GameCare wires them.
    @ObservationIgnored var haptic: (Float, Float) -> Void = { _, _ in }
    @ObservationIgnored var success: () -> Void = {}
    /// Capture aid: scripted fake scrubs (`-BlobGameDemo gclean`).
    @ObservationIgnored var demo = false
    /// Accessibility "Help me scrub": the scripted scrub runs for the current stage WITHOUT the demo's auto Next / Done (the player still taps Next). Reset on every stage.
    var assistScrub = false
    /// Capture aid (`-BathHold 1`): the demo stops at every complete stage (no auto Next / Done) so each can be filmed.
    @ObservationIgnored var demoHold = false
    @ObservationIgnored private var demoWait: Float = 0

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
    @ObservationIgnored private var sootSeededFor: Float = -1
    @ObservationIgnored private var rinseStartCoverage: Float = 1
    @ObservationIgnored private var finishT: Float = 0
    @ObservationIgnored private var heartsLeft = 0
    @ObservationIgnored private var heartT: Float = 0
    @ObservationIgnored private var bubbleAge: [Float] = []
    @ObservationIgnored private var bubbleT: Float = 0
    @ObservationIgnored private var touching = false
    @ObservationIgnored private var demoT: Float = 0
    @ObservationIgnored private var wetFading = false

    // which Jelly is being washed (Bob = 0). The others borrow `grime` / `look` for the run and hand Bob's back at the end.
    @ObservationIgnored private(set) var targetID = 0
    @ObservationIgnored private var bobGrime: BlobGrime?
    @ObservationIgnored private(set) var savedBobLook: BathLook?
    /// Where a washed Jelly other than Bob goes back to (nil: the usual front spot). GameCare+Bath picks a spot clear of the others.
    @ObservationIgnored var returnSpot: SIMD2<Float>?
    /// Called once, when a clean-up of Jelly `id` (> 0) is over and Bob's grime / look are back (with the wetness he leaves the tub with).
    @ObservationIgnored var onTargetEnd: (Int, Float) -> Void = { _, _ in }

    /// `grimeKey` / `grimeSeed`: the dirt this flow owns is slot 0's; with a character other than Bob in slot 0 it saves under HIS key (JellyKeys.grime).
    init(persists: Bool? = nil, sound: BathSound? = nil, grimeKey: String? = nil, grimeSeed: UInt32 = 0xB47B) {
        let p = persists ?? (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)
        grime = grimeKey.map { BlobGrime(persists: p, seed: grimeSeed, key: $0) } ?? BlobGrime(persists: p)
        wallet = DropsWallet(persists: p)
        self.sound = sound ?? BathSilence.shared
        look.sparkle = grime.sparkle
        look.dirt = grime.dirt
        look.soot = BathLook.sootSeed(dirt: grime.dirt)
        sootSeededFor = grime.dirt
    }
    nonisolated deinit {}

    private func rand() -> Float { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return Float(rng >> 8) / Float(1 << 24) }

    // MARK: state queries

    var active: Bool { phase != .off }
    /// Finger scrubs reach him (the stage routes pet touches while this is true).
    var acceptsTouch: Bool { phase == .soap || phase == .rinse || phase == .shine }
    /// The tool bar, its cancel button.
    var showsChrome: Bool { acceptsTouch || phase == .finish }
    var currentTool: BathTool {
        switch phase { case .soap: return .soap; case .rinse: return .rinse; case .shine: return .shine; default: return .none }
    }

    // MARK: start / cancel

    /// Tapping "Clean". Ignored while anything else runs (the menu row is disabled then too).
    func start(brain: BlobBrain, hurry: Bool = true, jelly: Int = 0, grime g: BlobGrime? = nil, look l: BathLook? = nil) {
        guard phase == .off else { return }
        if jelly != 0, let g {
            targetID = jelly; bobGrime = grime; savedBobLook = look
            grime = g
            var nl = l ?? BathLook(); nl.sootStyle = Float(jelly); nl.dirt = g.dirt; nl.sparkle = g.sparkle
            nl.soot = BathLook.sootSeed(dirt: g.dirt)
            look = nl; sootSeededFor = g.dirt
        } else { targetID = 0 }
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
            brain.requestNow(.goTo(targetID != 0 ? (returnSpot ?? GameCamera.callSpot) : GameCamera.callSpot))
            phase = .exitBack
            if let sim, Self.floorZ(brain, sim) <= GameCamera.roamMaxZ { restoreAll(brain: brain, sim: sim) }
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
        look.soot = BathLook.sootSeed(dirt: grime.dirt)          // the same pattern the room showed
        sootSeededFor = grime.dirt
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
        if place, let sim { self.place(brain: brain, sim: sim, at: targetID != 0 ? (returnSpot ?? GameCamera.callSpot) : GameCamera.callSpot) }
        cameraBlend = 0
        look.visible = false
        look.foam = Array(repeating: 0, count: BathLook.rows * BathLook.cols)
        look.bubbles = []; bubbleAge = []; look.spray = nil; look.toolAt = nil; look.tool = .none
        touching = false; prompt = nil
        sootSeededFor = -1                       // the room re-seeds its soot from his dirt (a half-washed spot does not stay)
        if phase != .fade { phase = .off; releaseTarget() }
        lastPos = nil
    }

    /// A clean-up of another Jelly is over: Bob's grime and look are his again (the washed Jelly's profile re-reads its own).
    private func releaseTarget() {
        guard targetID != 0 else { return }
        let id = targetID, wet = look.wet
        targetID = 0
        if let g = bobGrime { grime = g }
        look = savedBobLook ?? BathLook()
        bobGrime = nil; savedBobLook = nil; returnSpot = nil
        sootSeededFor = -1; wetFading = false; lastPos = nil
        onTargetEnd(id, wet)
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
        // dirt builds up only while he roams the room
        let here = GameCare.floorPos(brain, sim)
        if phase == .off {
            var travelled: Float = 0
            let exerting = brain.isExerting
            let moving = brain.activity == .walking || brain.activity == .coming || brain.runW > 0.1 || exerting
            if moving, let l = lastPos { let d = simd_length(here - l); if d < 0.5 { travelled = d } }
            lastPos = here
            grime.step(dt: dt, travelled: travelled, exerting: exerting)
            if wetFading { look.wet = max(0, look.wet - dt / BathTuning.wetFade); if look.wet == 0 { wetFading = false } }
            // the room shows the soot for his dirt (same stable pattern the bath starts from)
            if abs(grime.dirt - sootSeededFor) > BathTuning.sootReseed || (grime.dirt == 0) != (sootSeededFor == 0) {
                look.soot = BathLook.sootSeed(dirt: grime.dirt); sootSeededFor = grime.dirt
            }
        }

        switch phase {
        case .off: break
        case .exit:
            liftFence(true, sim: sim)
            exitT += dt
            if here.y >= BathTuning.exitCutZ || exitT >= BathTuning.exitTimeout { beginFade(.bath) }
        case .exitBack:
            if here.y <= GameCamera.roamMaxZ { restoreAll(brain: brain, sim: sim) }
        case .fade: tickFade(dt: dt, brain: brain, sim: sim)
        case .soap:
            look.tool = .soap
            if demo || assistScrub { demoTouch(dt: dt, sim: sim) }
            progress = stageComplete ? 1 : rounded(min(1, look.coverage / BathTuning.soapDone))
            tickBubbles(dt: dt)
            if !stageComplete, look.coverage >= BathTuning.soapDone { markComplete() }
        case .rinse:
            look.tool = .rinse
            if demo || assistScrub { demoTouch(dt: dt, sim: sim) }
            tickBubbles(dt: dt)
            if stageComplete { progress = 1 } else {
                let foam = min(1, max(0, (rinseStartCoverage - look.coverage) / max(rinseStartCoverage - BathTuning.rinseDone, 0.01)))
                let wetP = min(1, look.wet / BathTuning.wetNeeded)
                progress = rounded(min(foam, wetP))
                if look.coverage < BathTuning.rinseDone && look.wet >= BathTuning.wetNeeded { markComplete() }
            }
        case .shine:
            look.tool = .shine
            if demo || assistScrub { demoTouch(dt: dt, sim: sim) }
            tickBubbles(dt: dt)
            progress = stageComplete ? 1 : rounded(polish)
            if !stageComplete, polish >= BathTuning.polishDone { markComplete() }
        case .finish:
            look.tool = .none; look.toolAt = nil; look.spray = nil
            finishT += dt
            if heartsLeft > 0 { heartT -= dt; if heartT <= 0 { heartT = 0.45; heartsLeft -= 1; play?.spawnHeart(now: CACurrentMediaTime()) } }
        }
        if demo, !demoHold { demoAdvance(dt: dt, brain: brain, sim: sim) }
        if !acceptsTouch { touching = false; if phase != .exit { look.toolAt = nil; look.spray = nil } }
        look.sparkle = grime.sparkle
        look.dirt = grime.dirt
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
                else { phase = .off; prompt = nil; releaseTarget() }
            }
        }
    }

    private func enterAfterFade() { enter(.soap) }

    private func enter(_ p: BathPhase) {
        phase = p
        stageComplete = false; demoWait = 0; assistScrub = false
        if let t = Self.workPrompt(p) { A11yEvents.say(t, .normal) }
        if p != .soap && p != .rinse { look.bubbles = []; bubbleAge = [] }      // sud bubbles live only in the soap / rinse phases
        switch p {
        case .soap: progress = 0; prompt = Self.workPrompt(.soap); AudioHub.shared.play(.splash)
        case .rinse: prompt = Self.workPrompt(.rinse); progress = 0; rinseStartCoverage = max(look.coverage, BathTuning.rinseDone + 0.01)
        case .shine:
            prompt = Self.workPrompt(.shine)
            polish = 0; wetStart = look.wet; progress = 0
            look.foam = Array(repeating: 0, count: look.foam.count)
        case .finish:
            polish = 1; look.wet = 0; look.sparkle = 1; grime.sparkle = 1; grime.dirt = 0; grime.save()
            look.soot = BathLook.sootSeed(dirt: 0); sootSeededFor = 0
            finishT = 0; heartsLeft = 3; heartT = 0
            prompt = Self.workPrompt(.finish)
            AudioHub.shared.play(.sparkle)
            success()
        default: break
        }
        if p == .finish { finishPending = true }
    }
    // MARK: stages the player completes

    /// What the prompt says while a stage is being worked, and once its goal is met.
    static func workPrompt(_ p: BathPhase) -> String? {
        switch p { case .soap: return "Scrub on the jelly soap"; case .rinse: return "Rinse all the suds off"; case .shine: return "Rub to shine him up"; case .finish: return "Sparkling clean!"; default: return nil }
    }
    static func completePrompt(_ p: BathPhase) -> String? {
        switch p { case .soap: return "All soapy! Tap Next"; case .rinse: return "Squeaky clean! Tap Next"; case .shine: return "So shiny! Tap Next"; default: return nil }
    }
    /// "Soap done. Tap Next" for a screen reader.
    static func stageDoneAnnouncement(_ p: BathPhase) -> String {
        switch p { case .soap: return "Soap done. Tap Next"; case .rinse: return "Rinse done. Tap Next"; case .shine: return "Shine done. Tap Next"; default: return "Done" }
    }
    /// The prompt for the current stage (persistent: it never times out).
    var stagePrompt: String? { stageComplete ? Self.completePrompt(phase) : Self.workPrompt(phase) }

    private func markComplete() {
        stageComplete = true; progress = 1
        prompt = Self.completePrompt(phase)
        assistScrub = false
        A11yEvents.say(Self.stageDoneAnnouncement(phase), .high)          // (the checkmark and the prompt are the visible half of the haptic)
        haptic(BathTuning.completeHaptic.0, BathTuning.completeHaptic.1)
        AudioHub.shared.uiConfirm()
    }

    /// The Next button: soap -> rinse -> shine -> finish. Ignored until the stage's goal is met.
    func advance() {
        guard acceptsTouch, stageComplete else { return }
        switch phase {
        case .soap: enter(.rinse)
        case .rinse: enter(.shine)
        case .shine: enter(.finish)
        default: break
        }
    }

    /// Capture aid only (`demo`): presses Next 1 s after a stage is complete, and Done 2.5 s after the finish card shows.
    private func demoAdvance(dt: Float, brain: BlobBrain, sim: SoftBody?) {
        if stageComplete { demoWait += dt; if demoWait >= 1 { advance() } }
        else if phase == .finish { demoWait += dt; if demoWait >= 2.5 { done(brain: brain, sim: sim) } }
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
        case .soap:
            look.paint(local: l, radius: BathTuning.brushRadius, amount: BathTuning.soapGain * v * dt)
            if v > 0.3 { spawnBubbles(at: w, dt: dt) }
        case .rinse:
            look.spray = w + BathLook.sprayOffset
            look.rinse(local: l, radius: BathTuning.rinseRadius, amount: (BathTuning.rinsePassive + BathTuning.rinseGain * v) * dt)
            look.wet = min(1, look.wet + BathTuning.wetRise * dt)
            if v > 0.3 { AudioHub.shared.play(.splash, volume: 0.6) }
        case .shine:
            if v > 0.3 { AudioHub.shared.play(.lintroller) }
            let before = polish
            polish = min(1, polish + BathTuning.polishGain * v * dt)
            look.wet = wetStart * (1 - polish)
            grime.sparkle = polish
            look.sparkle = polish
            look.wipeSoot(local: l, radius: BathTuning.brushRadius, amount: 1.5 * v * dt)
            if Int(before * 10) != Int(polish * 10) { haptic(0.25, 0.6) }
        default: break
        }
    }

    private func spawnBubbles(at w: SIMD3<Float>, dt: Float) {
        bubbleT -= dt
        guard bubbleT <= 0 else { return }
        bubbleT = 0.09
        AudioHub.shared.play(.soapbubbles, volume: 0.8)
        let p = w + SIMD3(rand() - 0.5, rand() * 0.3, rand() * 0.3) * 0.3
        look.bubbles.append(SIMD4(p.x, p.y, p.z, 0.03 + 0.05 * rand()))
        bubbleAge.append(BathTuning.bubbleLife.lowerBound + (BathTuning.bubbleLife.upperBound - BathTuning.bubbleLife.lowerBound) * rand())
        if look.bubbles.count > BathLook.maxBubbles { look.bubbles.removeFirst(); bubbleAge.removeFirst() }
    }

    private func tickBubbles(dt: Float) {
        guard !look.bubbles.isEmpty else { return }
        for i in look.bubbles.indices { look.bubbles[i].y += 0.35 * dt; bubbleAge[i] -= dt }
        var k = 0
        while k < look.bubbles.count { if bubbleAge[k] <= 0 { look.bubbles.remove(at: k); bubbleAge.remove(at: k); AudioHub.shared.play(.bubblepop, volume: 0.6) } else { k += 1 } }
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
    }
}
