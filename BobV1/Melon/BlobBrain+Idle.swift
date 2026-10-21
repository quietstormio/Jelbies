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
//  Build B (2026-10-17, body-led running actions, all with stub arms and the feet under him): ZOOMIES = a fast low dash (run + stride 5 %, cadence 15 %,
//  more lean / bob / sway) ending in a dead stop with a big jelly wobble; SLIDE = a run into a belly slide (dive, slide ~0.9 u decelerating, pop up with a
//  wobble; `GaitDriver.slide`); SCOOT = 3...5 quick little bunny hops forward. `-RunMove zoomies|slide|scoot` makes the scheduler pick that one for captures.
//  The scheduler hook is `idleMaybeStart` (top of `pickAutonomous`); behaviours are weighted by mood (`IdleTable`), at most one special every
//  15...30 s, never the same one twice in a row. They never run during focus mode, a meal, Come here or a touch / throw get-up, and they yield
//  to those within 0.3 s (`idleGate`). Everything is a render-side or pose-side drive that is released at the end: the walk, the hop and the arm
//  capsules are the existing machinery.
//

import Foundation
import simd

typealias IdleMood = BlobMood

/// The zoomies urge and the okay table's share of fast moves.
enum IdleTuning {
    static let okayZoomies: Float = 1.2, okayRun: Float = 1.6          // (2026-10-20, "too bland": was 0.8 / 0.6)
    /// Seconds between forced zoomies / runs while awake in the daytime and not grumpy (a visible burst every few minutes). Vars so the suites can shorten it.
    nonisolated(unsafe) static var zoomUrge: ClosedRange<Float> = 60...120
    /// The first urge, seconds after he starts roaming (a Jelly that is not first waits longer: `zoomUrge` = this + 35 s per Jelly id once he is wired).
    nonisolated(unsafe) static var zoomUrgeFirst: Float = 30
}

enum IdleKind: String, CaseIterable, Sendable {
    case wander, run, stumble, jacks, sit, slump, look, yawn, zoomies, slide, scoot, sleep
    // solo antics (2026-10-19), all built from the existing moves: BlobBrain+Antics.swift
    case tail          // spin in place 1...3 turns after his own tail, then a dizzy wobble
    case flop          // plops down flat (squash, a lean over) and wobbles back up
    case window        // walks nowhere: turns to the back wall and looks out of the nearest window
    case peek          // goes to the end of the sofa, ducks and peeks out
    case stretch       // the yawn's stretch without the yawn
    case bounce        // 3...5 happy hops on the spot
    case roll          // the existing roll, a short way sideways
    case sway          // sits and sways to the music
    // decor (2026-10-19): things he does with the store's decor, built from the existing moves: BlobBrain+Decor.swift
    case decorSit      // walks onto a beanbag / cushion and settles into it (the sit, a little lower), then gets up
    case decorBoop     // walks up to the potted plant and boops it (a lean in, a nudge; the leaves wiggle)
    case decorKick     // walks into the ball: it rolls away (once or twice)
    case decorHop      // walks onto the bouncy mat and bounces on it (the happy bounce)
    case decorPeek     // goes to the toy box and leans over to peek in
    case decorSlide    // (batch 2) climbs the slide's steps, sits on the platform, rides down and exits with a squash
    case decorThrow    // (batch 2) hugs the football, squats, flings it (or fumbles it)
    // mid-walk flourishes + the jump for joy + two reaction moves (2026-10-20): BlobBrain+Flourish.swift
    case skipHop, hopscotch, legSpin, trot, stopLook, joy, giggle, startle
    case rollTrip      // rolls a short way along the leg (1...2.5 u) and pops up with a squish; a mid-walk flourish and an idle moment
    case sigh          // a slow inhale, a long exhale and a slump, sleepy / worried face
    case hmph          // grumpy puff: squash widens, angry brows, a quick turn-away and a small stomp
}

/// Mood -> which behaviours he picks from. `.wander` = no special this time (the existing wander table, slow and small when grumpy).
enum IdleTable {
    static func weights(_ m: IdleMood) -> [(kind: IdleKind, weight: Float)] {
        switch m {
        case .happy: return [(.run, 3), (.jacks, 3), (.zoomies, 3.6), (.slide, 0.8), (.scoot, 1.2), (.look, 0.8), (.joy, 3), (.wander, 2)]
        case .okay: return [(.sit, 1.5), (.look, 2), (.yawn, 0.8), (.joy, 0.8), (.scoot, 0.8), (.zoomies, IdleTuning.okayZoomies), (.run, IdleTuning.okayRun), (.wander, 2)]          // (zoomies + runs in okay too: the happy table alone almost never came up)
        case .grumpy: return [(.slump, 3), (.wander, 2)]
        }
    }
    /// Time of day on top of the mood table: at night the lively moves fade and sit (nap) / yawn grow; in the morning yawn (stretch and wake) grows.
    /// With night = morning = 0 this is exactly `weights(m)`.
    static func weights(_ m: IdleMood, night: Float, morning: Float, sleep: Bool = false, antics: Bool = false, music: Bool = false, anticMul: Float = 1, decor: Set<IdleKind> = []) -> [(kind: IdleKind, weight: Float)] {
        var w = weights(m)
        if antics { w = anticWeights(m, base: w, music: music, mul: anticMul) }
        if !decor.isEmpty { w += decorWeights(m, offers: decor) }
        guard night > 0.001 || morning > 0.001 else { return w }
        func add(_ k: IdleKind, _ x: Float) {
            if let i = w.firstIndex(where: { $0.kind == k }) { w[i].weight += x } else { w.insert((k, x), at: 0) }
        }
        for i in w.indices where w[i].kind != .wander && w[i].kind != .sit && w[i].kind != .yawn && w[i].kind != .slump && w[i].kind != .sleep
            && w[i].kind != .stretch && w[i].kind != .window && w[i].kind != .sway && w[i].kind != .decorSit && w[i].kind != .sigh && w[i].kind != .hmph { w[i].weight *= BlobBrain.fastKinds.contains(w[i].kind) ? 1 - 0.75 * night : max(0.5, 1 - 0.75 * night) }          // (the calm ones keep half their weight: the one who is still up at night keeps doing things; the fast ones still fade)
        add(.sit, (sleep ? 1.5 : 4) * night)
        if sleep { add(.sleep, 12 * night) }          // bedtime: asleep on his back (BlobBrain+Sleep.swift)
        add(.yawn, 2.5 * night + 3 * morning)
        if antics { add(.stretch, 1.5 * morning) }
        return w
    }
    /// The extra solo antics on top of a mood's table (the room life; the headless suites that predate them do not ask for them). The wander share shrinks
    /// so something visible happens more often.
    static func anticWeights(_ m: IdleMood, base: [(kind: IdleKind, weight: Float)], music: Bool, mul: Float = 1) -> [(kind: IdleKind, weight: Float)] {
        var w = base
        let extra: [(IdleKind, Float)]
        switch m {
        case .happy: extra = [(.bounce, 2.6), (.tail, 1.8), (.roll, 1.2), (.stretch, 1.0), (.window, 1.0), (.flop, 1.2), (.peek, 0.9), (.sway, music ? 2.0 : 0),
                              (.skipHop, 1.6), (.hopscotch, 0.9), (.legSpin, 1.0), (.trot, 1.2), (.rollTrip, 0.8)]          // (2026-10-20: the skip / hopscotch / spin / trot flourishes also start from standing)
        case .okay: extra = [(.window, 1.8), (.stretch, 1.6), (.tail, 0.8), (.peek, 0.8), (.flop, 0.6), (.bounce, 0.8), (.sway, music ? 2.0 : 0),
                             (.skipHop, 1.0), (.hopscotch, 0.5), (.legSpin, 0.6), (.trot, 0.8), (.rollTrip, 0.5), (.sigh, 0.8)]
        case .grumpy: extra = [(.window, 1.0), (.stretch, 0.6), (.hmph, 2.4), (.sigh, 1.2)]
        }
        for (k, x) in extra where x > 0 { w.append((k, x * mul)) }
        if let i = w.firstIndex(where: { $0.kind == .wander }) { w[i].weight = 1 }
        return w
    }
    /// The special (non-wander) behaviours of a mood.
    static func set(_ m: IdleMood) -> Set<IdleKind> { Set(weights(m).map { $0.kind }.filter { $0 != .wander }) }
    /// Weighted pick, never `last`. `r` in 0..<1.
    static func pick(_ m: IdleMood, last: IdleKind?, r: Float, night: Float = 0, morning: Float = 0, sleep: Bool = false, antics: Bool = false, music: Bool = false,
                     cooling: Set<IdleKind> = [], anticMul: Float = 1, decor: Set<IdleKind> = []) -> IdleKind {
        // never the same special twice in a row (unless the mood has only one), and none that is still on its own cooldown
        var w = weights(m, night: night, morning: morning, sleep: sleep, antics: antics, music: music, anticMul: anticMul, decor: decor).filter { $0.kind != last || $0.kind == .wander || set(m).count < 2 }
        if !cooling.isEmpty { let f = w.filter { !cooling.contains($0.kind) }; if !f.isEmpty { w = f } }
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
    var reps = 0, hop = 0, landT: Float = 0, jackA: Float = 0, jackRoll: Float = 0
    var counts: [IdleKind: Int] = [:]
    var tooFar = false
    // decor
    var decorUID = -1
    var decorGo = false                         // walking to the piece (false once he is at it)
    var decorKicked = false
    var decorBooped = false
    /// The beanbag sit (hop on, rest on top, hop off): 0 turn to the bag, 1 hopping on, 2 on top, 3 hopping off.
    var bagStage = 0
    /// Which seat of a multi-seat piece he is on, and how far the rocking seat has carried him (so he follows it by the difference).
    var seat = 0
    var seatShift = SIMD2<Float>.zero
    var cuddle: Float = 0
    /// The slide: 0 climb, 1 sit on the platform, 2 ride, 3 exit; the distance ridden along the path.
    var slideStage = 0
    var slideS: Float = 0
    var slideStep = 0
    /// The throw: 0 walk, 1 hug, 2 wind up, 3 fling, 4 settle; and how it will end (0 plain, 1 bonk, 2 drop).
    var throwStage = 0
    var throwFate = 0
    var throwDir = SIMD2<Float>(0, 1)
    /// A flourish: the goal of the walk it interrupted (nil = it started from standing).
    var resume: SIMD2<Float>?
    /// A reaction in progress (BlobBrain+React.swift): what it is and who it is about.
    var reaction: ReactionKind?
}

extension BlobBrain {
    static let runLean: Float = 5.5 * .pi / 180
    static let runArmGain: Float = 0.3
    /// 2026-10-18: the roaming walk is ~14 % faster (stride x1.143, cadence unchanged, so speed = stride x rate stays slip-free; a faster cadence made the turn-in-place steps of the zoomies loop come off the belly); the boost is off whenever a run / zoomies / slide (or its
    /// blend-out) is on, so the run / zoomies / slide keep their tuned, feet-attached gait exactly (`runW` = 1 gives the old numbers).
    static let walkBoost: Float = 1.1427
    var walkBoostNow: Float { walkBoostK }
    /// Waits between behaviours: half while the player is watching (the stage turns `watching` on in the room; the headless suites leave it off).
    var idleLively: Float { (watching ? 0.5 : 1) * (perkFlags.bouncy ? 0.7 : 1) }
    var runStrideMul: Float { (1 + 0.2 * runW + 0.0 * zoomW) * walkBoostNow }
    var runRateMul: Float { 1 + 0.125 * runW + 0.20 * zoomW }

    var idleActivity: Activity {
        switch idleState.kind {
        case .run, .stumble, .zoomies, .decorKick: return .walking
        case .jacks, .slide, .scoot, .bounce, .tail, .roll, .flop, .skipHop, .hopscotch, .legSpin, .joy, .giggle, .startle, .rollTrip: return .playing
        case .trot: return .walking
        default: return .lookingAround
        }
    }

    // MARK: scheduler

    /// Called from `pickAutonomous` (a pick is due, script .none): starts a special when the cooldown is over. True = a behaviour started.
    func idleMaybeStart(_ sim: SoftBody) -> Bool {
        if sleepEnabled, runMoveDemo == nil, idleState.kind == nil, !held, attached, sleepWanted(), idleStart(.sleep, sim) { return true }
        if hmphMaybeStart(sim) { return true }
        guard idleState.kind == nil, !held, idleState.cooldown <= 0, attached else { return false }
        // the zoomies urge: a burst of energy every few minutes (not at night, never grumpy, one of the two fast Jellies at a time)
        if (sleepEnabled || anticsEnabled), runMoveDemo == nil, zoomUrge <= 0, idleMood != .grumpy, idleNight < 0.5, idleDeepNight < 0.5, !race.active, fastOthers() < 1 {
            let k: IdleKind = rand() < 0.6 ? .zoomies : .run
            let started = idleStart(k, sim)
            zoomUrge = started ? rand(IdleTuning.zoomUrge.lowerBound, IdleTuning.zoomUrge.upperBound) : 20
            if started {
                if anticsEnabled { kindCooldownStart(k) }
                if k == .zoomies { socialOfferZoomies(sim) }
                return true
            }
        }
        var kind = runMoveDemo ?? IdleTable.pick(idleMood, last: idleState.last, r: rand(), night: idleNight, morning: idleMorning, sleep: sleepEnabled, antics: anticsEnabled, music: musicPlaying,
                                                 cooling: anticsEnabled ? kindCooling : [], anticMul: perkFlags.bouncy ? PerkTuning.anticBoost : 1,
                                                 decor: anticsEnabled && !sleepLocked ? Self.decorOffers() : [])
        if sleepEnabled, runMoveDemo == nil, kind != .wander, kind != .sleep, idleNight < 0.2, rand() < 0.012 { kind = .sleep }       // a daytime nap now and then
        if kind == .wander { idleState.cooldown = rand(5, 9) * idleLively; return false }
        if kind == .look { socialPrepareLook(sim) }          // sometimes at a nearby Jelly, who glances back
        if anticsEnabled, Self.fastKinds.contains(kind), fastOthers() >= 2 { idleState.cooldown = rand(1.2, 2.5); return false }          // at most two Jellies in fast moves at once
        let started = idleStart(kind, sim)
        if started, kind == .run || kind == .zoomies { zoomUrge = max(zoomUrge, rand(IdleTuning.zoomUrge.lowerBound, IdleTuning.zoomUrge.upperBound) * 0.6) }          // (a burst of energy just happened: the urge starts over)
        if started, anticsEnabled { kindCooldownStart(kind) }
        if started && kind == .zoomies { socialOfferZoomies(sim) }
        return started
    }

    /// Mood shapes the ordinary wander table too: grumpy skips waves and play, and idles longer.
    func idleShapeWander(_ w: inout [(Int, Float)]) {
        if idleMood == .grumpy { w.removeAll { $0.0 == 3 || $0.0 == 4 } }
        if anticsEnabled { for i in w.indices where w[i].0 == 1 || w[i].0 == 2 { w[i].1 *= 0.5 } }          // (the lively room stands and looks about less: the "look" and the step on the spot are the plain stops)
    }
    func idleLegMax(_ m: Float) -> Float { idleMood == .grumpy ? min(m, 1.8) : m }

    /// Every tick before the gait: counts the cooldown, yields to anything else, notices the end of a run.
    func idleGate(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        if !kindCool.isEmpty { for k in Array(kindCool.keys) { let v = kindCool[k]! - dt; if v <= 0 { kindCool[k] = nil } else { kindCool[k] = v } } }
        let boostWant: Float = (runW == 0 && zoomW == 0 && idleState.kind == nil && !hurry) ? Self.walkBoost : 1
        // a run / zoomies / slide drops the boost at once (their gait is tuned without it); it comes back eased (~0.5 s) so the stride never jumps mid-step
        if boostWant < walkBoostK { walkBoostK = boostWant } else { walkBoostK = min(boostWant, walkBoostK + dt * 0.3) }
        guard let kind = idleState.kind else {
            commanded = false
            if decorIgnore != nil || !DecorField.shared.feet.isEmpty { decorExitCheck() }
            if autonomy && !held { idleState.cooldown -= dt; zoomUrge -= dt }
            return
        }
        idleState.t += dt
        // a script that is not ours any more (the care menu started a hop, ...)
        var mine = false
        switch script {
        case .idle: mine = true
        case .spin: mine = kind == .tail || kind == .legSpin
        case .hopPlay, .rollPlay: mine = kind == .roll || kind == .rollTrip
        case .walk: mine = (Self.decorKinds.contains(kind) && idleState.decorGo) || kind == .run || kind == .stumble || kind == .zoomies || (kind == .slide && idleState.phase == 0) || (kind == .sleep && sleep.stage == 0) || (kind == .peek && idleState.phase == 0) || kind == .trot
        case .none:
            // the zoomies' dash is over (the walk planted him): the dead stop and the big wobble
            if kind == .zoomies && idleState.phase == 0 {
                mine = true
                idleState.phase = 1; idleState.phaseT = 0; idleState.t = 0
                script = .idle; activity = .walking
                jellyKick = 3.2
            }
            else if kind == .sleep && sleep.stage == 0 { mine = true; sleepArrived(sim, skinner) }
            else if kind == .peek && idleState.phase == 0 { mine = true; peekArrived() }
            else if Self.decorKinds.contains(kind) && idleState.decorGo { mine = true; decorArrived(sim, skinner); return }
            else if kind == .tail { mine = true; tailNext(skinner) ; return }
            else if kind == .legSpin { mine = true; mouthOpen = 0; flourishEnd(skinner); return }
            else if kind == .roll && idleState.t > 0.15 { idleFinish(skinner); return }
            else if kind == .rollTrip && idleState.t > 0.15 { mine = true; jellyKick = max(jellyKick, 2.0); AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.6); mouthOpen = 0; flourishEnd(skinner); return }          // (the pop-up squish)
        default: mine = false
        }
        if !mine { idleReset(skinner); return }
        if kind == .trot { trotCheck(skinner); if idleState.kind == nil { return } }
        // woken (a tap / the selection / a request) before he lay down: the walk to bed or the yawn just ends (nothing else read `yielding` for stages 0 / 1: he used to lie down anyway)
        if kind == .sleep, idleState.yielding, sleep.stage <= 1 { abortAll(sim, skinner); return }
        if Self.decorKinds.contains(kind) { decorTick(sim, skinner, dt) }
        if (pending != nil || (!autonomy && demo == nil && !idleForced && !commanded) || (held && !commanded)) && !idleState.yielding {
            switch kind {
            case .sit, .slump, .look, .yawn, .stretch, .window, .sway, .stopLook: idleState.yielding = true; idleState.yieldT = 0; feet.reset(); stepLive = false
            case .decorSit where isBagSit && !idleState.decorGo:
                // on the bag he hops off (the hold ends now); a turn on the floor just stops; a hop in progress is finished first
                if idleState.bagStage == 2 { idleState.hold = 0 } else if idleState.bagStage == 0 { abortAll(sim, skinner); return }
            case .decorSit where !idleState.decorGo, .decorBoop where !idleState.decorGo, .decorPeek where !idleState.decorGo: idleState.yielding = true; idleState.yieldT = 0; feet.reset(); stepLive = false
            case .decorSlide where !idleState.decorGo && idleState.slideStage == 0: abortAll(sim, skinner); return          // (still turning on the floor: just stop)
            case .decorSlide where !idleState.decorGo, .decorThrow where !idleState.decorGo: idleState.yielding = true          // (they finish: the slide hurries its ride, the throw its flight)
            case .sleep where sleep.stage >= 2 && sleep.stage <= 4: idleState.yielding = true; sleepWake(groggy: false, fast: true)
            default: abortAll(sim, skinner); return
            }
        }
        if case .walk(let target, _) = script, kind == .slide, idleState.phase == 0, runW > 0.9, idleState.stumbleAt > 0,
           simd_length(target - SIMD2(px, pz)) < idleState.stumbleAt {
            idleBeginSlide(sim, skinner)
            return
        }
        if case .walk(let target, _) = script, kind == .run, idleState.stumbleAt > 0, runW > 0.9,
           simd_length(target - SIMD2(px, pz)) < idleState.stumbleAt {
            idleState.kind = .stumble; idleState.phase = 0; idleState.phaseT = 0; idleState.t = 0
            postEvent(.tripped)
            route = []; walkFinal = false
            script = .idle
        }
    }

    /// Ease the run blend: 1 while a run is under way and more than ~1.1 u from the goal, else back to 0 (exactly 0 once small).
    func idleUpdateRun(_ dt: Float) {
        var want: Float = 0
        if idleState.kind == .run, case .walk(let target, _) = script, simd_length(target - SIMD2(px, pz)) > 1.1 { want = 1 }
        if idleState.kind == .slide, idleState.phase == 0, case .walk = script { want = 1 }
        if idleState.kind == .trot, case .walk = script { want = 0.4 }          // the bounce-trot: a fraction of the run blend, no stop
        // zoomies: full tilt until the last few steps, then a dead stop (the zoom / run blends drop quickly)
        var zoomWant: Float = 0
        if idleState.kind == .zoomies, idleState.phase == 0, case .walk(let target, _) = script {
            if simd_length(target - SIMD2(px, pz)) > 0.5 { want = 1; zoomWant = 1 }
        }
        zoomW += max(-dt / 0.25, min(dt / 0.45, zoomWant - zoomW))
        if zoomWant == 0 && zoomW < 1e-3 { zoomW = 0 }
        if idleState.kind == .zoomies { runW += max(-dt / 0.2, min(dt / 0.45, want - runW)); if want == 0 && runW < 1e-3 { runW = 0 }; return }
        if hurry, case .walk(let target, _) = script, simd_length(target - SIMD2(px, pz)) > 0.35 { want = 1 }       // touch play: running back after a throw
        if runW == want { return }
        let rampT: Float = hurry ? 0.3 : 0.6                    // a throw's run back starts quickly
        runW += max(-dt / rampT, min(dt / rampT, want - runW))
        if want == 0 && runW < 1e-3 { runW = 0 }
    }

    func idleEnd(_ skinner: Skinner?, cooldown: Bool = true) {
        bagFloorOn = false          // (the floor goes back to the room's at the next step, whatever cut the behaviour short)
        decorRelease()
        if let k = idleState.kind {
            if k == .sleep { awakeMin = rand(SleepTuning.awakeMin.lowerBound, SleepTuning.awakeMin.upperBound) }          // he stays up a while after any wake (no sleep / wake / sleep loop)
            let flourish = Self.flourishKinds.contains(k) && (idleState.resume != nil || idleState.reaction != nil)          // (a flourish inserted in a walk / a reaction is not his own pick of a special: no "last", no special cooldown; one the scheduler picked from standing is)
            if social == nil && !flourish { idleState.last = k == .stumble ? .run : k }          // (the moves a social session starts - a bump's bounces, a dance - are not his own pick: they must not hide his last solo one)
            idleState.counts[k, default: 0] += 1
            if cooldown && !flourish { idleState.cooldown = runMoveDemo != nil ? 2.5 : max(6 * idleLively, rand(11, 22) * idleLively - idleState.t) }
        }
        if idleState.kind == .rollTrip { gait.rollTravel = 1.1 }
        idleState.kind = nil; idleState.yielding = false; idleState.k = 0
        napping = false
        zoomW = 0
        gait.basePitch = 0
        commanded = false
        armDirW = 0; armDirOut = 0
        idleState.jackRoll = 0
        if !nameHopping { gait.hopApex = 0.10; gait.hopDuration = 0.26 }       // the jacks' higher hop ends with them
        skinner?.setEyeOpenness(1)
    }

    /// Hard stop (abort, touch, request): the render overrides go, the eyes open, nothing of the behaviour is left.
    func idleReset(_ skinner: Skinner?) {
        guard idleState.kind != nil || armDirW != 0 || runW != 0 else { return }
        let wasRun = runW != 0 || zoomW != 0
        idleEnd(skinner, cooldown: idleState.kind != nil)
        idleState.phase = 0
        if wasRun { runW = 0; zoomW = 0 }
        mouthOpen = 0
    }

    /// Voice v1: he does `kind` now because the player said so. Whatever he was doing is stopped first (a wander leg, a running behaviour); the
    /// behaviour then runs even in focus mode (`commanded`). A failed start (a run with no room) leaves him standing.
    func startCommanded(_ kind: IdleKind, _ sim: SoftBody, _ skinner: Skinner) {
        var busy = idleState.kind != nil
        if case .none = script {} else { busy = true }
        if busy { abortAll(sim, skinner) }
        pending = nil
        commanded = true
        if idleStart(kind, sim) { restTimer = max(restTimer, 1) } else { commanded = false }
    }

    // MARK: starting

    func idleBegin(_ kind: IdleKind) {
        idleState.kind = kind; walkBoostK = 1
        idleState.t = 0; idleState.phase = 0; idleState.phaseT = 0; idleState.k = 0; idleState.yielding = false; idleState.yieldT = 0
        idleState.steps = 0; idleState.stumbleAt = 0; flopKicks = 0; idleState.resume = nil; idleState.reaction = nil
        idleState.sign = rand() < 0.5 ? -1 : 1
        scriptT = 0; stuckT = 0; bestDist = .infinity; route = []; steerStall = 0; job = nil
    }

    /// Start `kind` now (the scheduler, tests and the capture demos). False = no room / not possible.
    @discardableResult
    func idleStart(_ kind: IdleKind, _ sim: SoftBody, goal: SIMD2<Float>? = nil) -> Bool {
        if idleState.kind != nil { return false }
        currentPose(sim)
        let here = SIMD2(px, pz)
        switch kind {
        case .wander, .stumble: return false
        case .zoomies, .slide:
            // a dash across the rug like the run (slide: the last ~0.9 u is the belly slide, so the goal is the end of the slide)
            guard let g = goal ?? pickRunGoal(from: here, minD: kind == .slide ? 2.6 : 2.6, maxD: kind == .slide ? 4.4 : 4.2) else { return false }
            idleBegin(kind)
            idleState.target = g
            AudioHub.shared.play(.zoomies, jelly: steerID, x: px)
            if kind == .zoomies { postEvent(.zoomies) }
            if kind == .slide { idleState.stumbleAt = GaitDriver.slideDist + 0.12 }
            script = .walk(target: g, then: .none); activity = .walking
        case .scoot:
            // 3...5 quick bunny hops toward a spot ~1.2...1.9 u away (the hops themselves run in `idleBodyMoveTick`)
            guard let g = goal ?? pickRunGoal(from: here, minD: 1.3, maxD: 2.0) else { return false }
            idleBegin(.scoot)
            idleState.target = g
            idleState.reps = 3 + Int(rand() * 3)
            idleState.hop = 0; idleState.landT = 0
            script = .idle; activity = .playing
            idleState.phase = 1; idleState.phaseT = 0
            postEvent(.joyJump)          // bunny hops are happy hops
            idleScootHop(sim)
        case .run:
            guard let g = goal ?? pickRunGoal(from: here, minD: 2.5, maxD: 4.4) else { return false }
            idleBegin(.run)
            idleState.target = g
            // about one run in three ends in a trip (needs room: the trip happens 1.9 u before the goal)
            if rand() < 0.34 && goal == nil && simd_length(g - here) >= 3.2 { idleState.stumbleAt = 1.9 }
            script = .walk(target: g, then: .none); activity = .walking
            postEvent(.zoomies)          // (a dash starts: the others may look, cheer or run along)
        case .jacks:
            idleBegin(.jacks)
            idleState.reps = 4 + Int(rand() * 3)             // 4...6
            postEvent(.joyJump)          // jumping jacks are jumping for joy
            idleState.hop = 0; idleState.landT = 0; idleState.jackA = 0
            idleState.baseYaw = yaw
            script = .idle; activity = .playing
        case .sit, .slump, .sway:
            idleBegin(kind)
            idleState.hold = (kind == .sit && idleNight < 0.3) ? rand(3, 6) : rand(6, 12)          // (a daytime sit is short: 3...6 s)
            // face the camera, or a little away from it (a content sit is turned a touch, the slump faces away)
            let off: Float = kind == .slump ? 0.6 : 0.3
            idleState.goalYaw = faceCameraYaw() + idleState.sign * off * (kind == .slump ? 1 : rand(0.4, 1))
            script = .idle; activity = .lookingAround
        case .look:
            idleBegin(.look)
            idleState.baseYaw = yaw
            idleState.hold = rand(1.6, 2.6)
            idleState.goalYaw = faceCameraYaw() + idleState.sign * rand(0.8, 1.3)
            if let aim = socialLookAim() { idleState.goalYaw = aim.yaw; idleState.hold = aim.hold }
            script = .idle; activity = .lookingAround
        case .window:
            // turn to the back wall and look out of the nearest window (the LOOK posture, held longer)
            idleBegin(.window)
            idleState.baseYaw = yaw
            idleState.hold = rand(3.0, 4.6)
            let wx = RoomGeometry.windowXs.min { abs($0 - px) < abs($1 - px) } ?? 0
            idleState.goalYaw = atan2f(wx - px, RoomLayout.minZ - pz)
            script = .idle; activity = .lookingAround
        case .yawn, .stretch:
            idleBegin(kind)
            script = .idle; activity = .lookingAround
        case .tail:
            idleBegin(.tail)
            idleState.reps = Int(rand() * 3)          // 0...2 more turns after the first
            startSpin(sim: sim)
            AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.5)
        case .roll:
            idleBegin(.roll)
            startRoll(sim)
            AudioHub.shared.play(.wobble, jelly: steerID, x: px, volume: 0.6)
        case .bounce:
            idleBegin(.bounce)
            postEvent(.joyJump)          // a happy bounce
            idleState.target = here
            idleState.reps = 3 + Int(rand() * 3)
            idleState.hop = 0; idleState.landT = 0
            script = .idle; activity = .playing
            idleState.phase = 1; idleState.phaseT = 0
            idleScootHop(sim)
        case .flop:
            idleBegin(.flop)
            script = .idle; activity = .playing
        case .peek:
            guard let spot = peekSpot(from: here) else { return false }
            idleBegin(.peek)
            idleState.target = spot
            script = .walk(target: spot, then: .none); activity = .walking
        case .sleep:
            return sleepBegin(sim, night: idleNight > SleepTuning.nightEdge || idleDeepNight > 0.5)
        case .decorSit, .decorBoop, .decorKick, .decorHop, .decorPeek, .decorSlide, .decorThrow:
            return decorStart(kind, sim)
        case .skipHop, .hopscotch, .legSpin, .trot, .stopLook:
            return flourishStart(kind, resume: nil, sim, nil)
        case .rollTrip:
            return flourishStart(.rollTrip, resume: nil, sim, nil)
        case .sigh, .hmph:
            idleBegin(kind)
            script = .idle; activity = .lookingAround
        case .joy:
            idleBegin(.joy)
            idleState.target = here
            idleState.reps = 1
            idleState.hop = 0; idleState.landT = 0
            script = .idle; activity = .playing
            idleState.phase = 1; idleState.phaseT = 0
            idleScootHop(sim)
        case .giggle:
            idleBegin(.giggle)
            script = .idle; activity = .playing
        case .startle:
            idleBegin(.startle)
            idleState.target = goal ?? here
            idleState.reps = 1
            idleState.hop = 0; idleState.landT = 0
            script = .idle; activity = .playing
            idleState.phase = 1; idleState.phaseT = 0
            idleScootHop(sim)
        }
        return true
    }

    /// A random spot inside the roaming area `minD...maxD` from `here` that is reachable in a straight line (nil = no room).
    func pickRunGoal(from here: SIMD2<Float>, minD: Float, maxD: Float) -> SIMD2<Float>? {
        for _ in 0..<160 {
            var cand: SIMD2<Float>
            if let rf = roamProvider?() { cand = rf.sampleArea(rand(), rand(), rand()) }
            else if let r = wanderRect { cand = SIMD2(rand(r.min.x, r.max.x), rand(r.min.y, r.max.y)) }
            else {
                let a = rand() * 2 * .pi, rr = wanderRadius * rand().squareRoot()
                cand = wanderCenter + SIMD2(sinf(a), cosf(a)) * rr
            }
            let rv = resolve(SIMD3(cand.x, 0, cand.y), footprint)
            let c2 = SIMD2(rv.x, rv.z)
            let d = simd_length(c2 - here)
            if d >= minD && d <= maxD && simd_length(c2 - cand) < 0.05 && peerFree(c2) && legClear(here, c2, margin: steerMargin) { return c2 }
        }
        return nil
    }

    // MARK: running the .idle script

    /// New foot step with the planted feet's reach (used by sit / get up: the feet go forward and come back under him).
    func idleFootStep(reach: Float, rate: Float = 2.6, peak: Float = 0.055) {
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
        case .zoomies: runZoomStop(sim, skinner, dt)
        case .decorSit where isBagSit: runBagSit(sim, skinner, dt)
        case .sit, .slump, .sway, .decorSit: runSit(sim, skinner, dt, slump: kind == .slump)
        case .look, .window, .decorBoop, .decorPeek, .stopLook: runLook(sim, skinner, dt)
        case .giggle: runGiggle(sim, skinner, dt)
        case .sigh: runSigh(sim, skinner, dt)
        case .hmph: runHmph(sim, skinner, dt)
        case .decorKick: runDecorKick(sim, skinner, dt)
        case .decorSlide: runSlide(sim, skinner, dt)
        case .decorThrow: runThrow(sim, skinner, dt)
        case .yawn, .stretch: runYawn(sim, skinner, dt)
        case .flop, .peek: runPosePlay(sim, skinner, dt)
        case .sleep: runSleep(sim, skinner, dt)
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
            case 1: startStep(rootD: clipRoot(0.36), reach: u * 0.20, peak: 0.06 * amplitude, rate: 3.6, swingFrac: 0.8); idleState.phase = 2; idleState.phaseT = 0
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

    // MARK: zoomies stop

    /// The dead stop after the dash: feet planted square; a big jelly wobble (squash pulses, a side-to-side rock, a quick twist, a small lean back that
    /// settles forward) that dies out in ~0.8 s. Body-led: the arms stay thumbs (armShortW).
    private func runZoomStop(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        let s = idleState.phaseT
        let env = expf(-s / 0.30)
        gaitPose(sway: 0.04, bob: 0.0, rock: 0.2)
        squash *= 1 + 0.10 * env * cosf(2 * .pi * 5.5 * s)
        roll += 0.06 * env * sinf(2 * .pi * 4.2 * s)
        twist = 0.10 * env * sinf(2 * .pi * 6.0 * s)
        pitch += 0.05 * env * sinf(2 * .pi * 3.5 * s)
        armWalkWant = 1
        if s > 0.85 && !feet.active { twist = 0; idleFinish(skinner) }
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
    func sitPose(_ skinner: Skinner, _ k: Float, slump: Bool) {
        let t = idleState.t
        let breath = sinf(2 * .pi * t * 0.30)
        squash *= 1 - (slump ? 0.27 : 0.32) * k + (slump ? 0.008 : 0.016) * breath * k
        pitch += (slump ? 0.34 : -0.06) * k
        if idleState.kind == .sway { roll += 0.10 * k * sinf(2 * .pi * t / 1.7) }          // sways to the music
        else if !slump {
            let win = max(0, sinf(2 * .pi * t / 8.0)); roll += 0.055 * k * win * win * sinf(2 * .pi * t / 3.2)
        }
        skinner.setEyeOpenness(1 - (slump ? 0.62 : (napping ? 0.93 : 0.5)) * k)
        if idleState.kind == .decorSit { decorPose(skinner, k: k) }
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
                let home = (facePlayerWhenIdle && idleState.kind != .stopLook) ? faceCameraYaw() : idleState.baseYaw
                let turning = turnSteps(goal: home, tol: 0.08)
                if !turning && !feet.active && k <= 0.001 { idleState.k = 0; idleFinish(skinner); return }
            }
        }
        idleState.k = k
        gaitPose(sway: 0.05, bob: 0.0, rock: 0.2)
        let t = idleState.t
        roll += idleState.sign * 0.10 * k + 0.012 * k * sinf(2 * .pi * t * 0.9)
        pitch += (idleState.kind == .window ? -0.06 : 0.05) * k + 0.02 * k * sinf(2 * .pi * t * 1.3)
        if idleState.kind == .decorBoop || idleState.kind == .decorPeek { decorPose(skinner, k: k) }
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
                if phT < dt && idleState.kind == .yawn { postEvent(.yawned) }          // (a yawn is catching)
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
        mouthOpen = idleState.kind == .stretch ? 0 : mouth
    }

    // MARK: finishing

    /// The behaviour is over: back to rest through the normal idle path.
    func idleFinish(_ skinner: Skinner) {
        if let k = idleState.kind, Self.flourishKinds.contains(k) { mouthOpen = 0; flourishEnd(skinner); return }
        idleEnd(skinner)
        mouthOpen = 0
        armWalkWant = 0
        script = .none
        restTimer = rand(1.0, 2.5) * idleLively
    }

    // MARK: belly slide + scoot (the hop machinery owns the body, like the jacks)

    /// The run reached the slide's mark: hand the body to the gait driver's belly slide (feet and root re-seeded from the body afterwards).
    func idleBeginSlide(_ sim: SoftBody, _ skinner: Skinner) {
        let u = SIMD2(sinf(yaw), cosf(yaw))
        let pose = sim.bodyPose(iterations: 6)
        let from = SIMD2(pose.centroid.x, pose.centroid.z)
        let rv = resolve(SIMD3(from.x + u.x * GaitDriver.slideDist, 0, from.y + u.y * GaitDriver.slideDist), footprint)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false; walkFinal = false; route = []
        gait.wander = false; gait.facingYaw = yaw; gait.home = from
        poseW = 0; poseOn = false
        pitchBase = 0
        gait.basePitch = 0
        gait.slide(sim, to: SIMD2(rv.x, rv.z), yaw: yaw)
        postEvent(.slid)
        script = .idle; activity = .playing
        idleState.phase = 1; idleState.phaseT = 0; idleState.t = 0; idleState.landT = 0
        slideKicks = 0
    }

    /// One bunny hop of the scoot: a small low hop toward the goal.
    func idleScootHop(_ sim: SoftBody) {
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.6)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        let pose = sim.bodyPose(iterations: 6)
        let here = SIMD2(pose.centroid.x, pose.centroid.z)
        let d = idleState.target - here
        let dl = simd_length(d)
        var step = (idleState.kind == .bounce || idleState.kind == .joy) ? 0 : min(Self.scootHop, dl)
        var u = dl > 1e-3 ? d / dl : SIMD2(sinf(yaw), cosf(yaw))
        if idleState.kind == .hopscotch {          // 0.34 u ahead along the leg, alternating 0.12 u to either side
            let f = SIMD2(sinf(idleState.baseYaw), cosf(idleState.baseYaw)), right = SIMD2(f.y, -f.x)
            let v = f * Self.scootHop + right * (idleState.hop % 2 == 0 ? 0.12 : -0.12)
            step = simd_length(v); u = v / step
        }
        let rv = resolve(SIMD3(here.x + u.x * step, 0, here.y + u.y * step), footprint)
        gait.facingYaw = idleState.kind == .startle ? yaw : atan2f(u.x, u.y)
        gait.home = here
        poseW = 0; poseOn = false
        let apex: Float = (idleState.kind == .bounce || idleState.kind == .joy) ? Self.bounceApex : (idleState.kind == .startle ? 0.09 : Self.scootApex)
        gait.hopApex = apex
        gait.hopDuration = 0.26 * sqrtf(apex / 0.10)
        gait.hop(sim, to: SIMD2(rv.x, rv.z), reduceMotion: amplitude < 0.7, chained: false)
        idleState.landT = 0
    }
    static let scootHop: Float = 0.34, scootApex: Float = 0.07, bounceApex: Float = 0.12

    /// Belly slide and scoot, ticked each step while they run (true = this tick is fully handled).
    func idleBodyMoveTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) -> Bool {
        if bagBodyTick(sim, skinner, dt) { return true }
        if slideBodyTick(sim, skinner, dt) { return true }
        guard let kind = idleState.kind, kind == .slide || kind == .scoot || kind == .bounce || kind == .skipHop || kind == .hopscotch || kind == .joy || kind == .startle, idleState.phase >= 1, case .idle = script else { return false }
        activity = .playing
        mouthOpen = 0
        idleState.phaseT += dt
        let hopGoal: Float = kind != .slide ? -hopTipBack * attentionPitch * amplitude : 0
        pitchBase += max(-1.2 * dt, min(1.2 * dt, hopGoal - pitchBase))
        gait.basePitch = pitchBase
        gait.tick(sim, held: false, reduce: amplitude < 0.7)
        if kind == .slide {
            // the jelly kicks: the dive's impact and the pop-up landing
            let st = gait.slideT
            if slideKicks == 0 && st >= GaitDriver.slideDive { slideKicks = 1; jellyKick = 2.0 }
            if slideKicks == 1 && st >= GaitDriver.slidePopEnd { slideKicks = 2; jellyKick = 3.0 }
            armWalkWant = 1
            armDirW = 1; armDirEl = [0.25, 0.25]; armDirSa = [-0.25, -0.25]; armDirOut = 0.05
        } else {
            if gait.phase == .land { idleState.landT += dt } else { idleState.landT = 0 }
            if idleState.decorUID >= 0, gait.phase == .land, idleState.landT > 0, idleState.landT <= dt * 1.5 { DecorField.shared.kick(idleState.decorUID, 1) }
            let total = idleState.reps
            if idleState.hop < total && gait.phase == .land && idleState.landT >= 0.05 {
                idleState.hop += 1
                if idleState.hop < total { idleScootHop(sim) }
            }
            let flap = sinf(2 * .pi * 5 * idleState.phaseT)
            armWalkWant = 1
            if kind == .joy {          // the jacks' arms-up pose, one rep
                armDirW = smooth01(min(1, idleState.phaseT / 0.12)); armDirEl = [0.95, 0.95]; armDirSa = [0.10, 0.10]; armDirOut = 0.07
            } else {
                armDirW = 1; armDirEl = [0.45 + 0.1 * flap, 0.45 - 0.1 * flap]; armDirSa = [0.1, 0.1]; armDirOut = 0.05
            }
        }
        driveBeansRigid(sim, skinner, dt, tuck: gait.tuck)
        driveArms(sim, skinner, dt)
        let done = kind == .slide ? !gait.isBusy : (idleState.hop >= idleState.reps && !gait.isBusy)
        if done {
            gait.basePitch = 0
            gait.hopApex = 0.10; gait.hopDuration = 0.26
            currentPose(sim)
            armDirW = 0; armDirOut = 0
            idleFinish(skinner)
        }
        return true
    }

    // MARK: jumping jacks

    /// Apex (u) of a jacks hop: 0.14 u (about 0.10 H), the idle hop's 0.10 u with a bit more air.
    static let jacksApex: Float = 0.14

    private func idleStartHop(_ sim: SoftBody, final: Bool) {
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.7)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        gait.facingYaw = yaw
        let pose = sim.bodyPose(iterations: 6)
        gait.home = SIMD2(pose.centroid.x, pose.centroid.z)
        poseW = 0; poseOn = false
        // BODY-LED: the jacks' hop is higher (the body does the work; the arms are only little thumbs that flap), ballistic duration for the apex
        gait.hopApex = Self.jacksApex
        gait.hopDuration = 0.26 * sqrtf(Self.jacksApex / 0.10)
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
        // a small side-to-side sway: the body leans toward the side of the hop's parity and swings over in the air (render-only via the attractor's rotation)
        let swayGoal: Float = (idleState.hop % 2 == 0 ? 1 : -1) * (gait.phase == .air ? 0.09 : 0.03) * (idleState.hop < total - 1 ? 1 : 0)
        idleState.jackRoll += (swayGoal - idleState.jackRoll) * min(1, 9 * dt)
        if idleState.jackRoll != 0 { sim.attractor.rotation = simd_quatf(angle: idleState.jackRoll, axis: SIMD3<Float>(0, 0, 1)) * sim.attractor.rotation }
        driveBeansSpread(sim, skinner, dt, tuck: gait.tuck, spread: 0.12 * a)
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
