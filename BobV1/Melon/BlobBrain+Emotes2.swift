//
//  BlobBrain+Emotes2.swift
//  Batch 2 of the emotes (user-approved 2026-11-02, g-emotes3): six solo moves. All STANDING pose moves in the family of bow / sneeze / giggle (feet planted or stepping on the spot with the locked
//  march step, the stubby arms at the rest nubs, the walk and the face untouched, nobody walking through anybody). They are `IdleKind`s so EmoteFeetTests / OnePieceInvariantTests cover them for
//  all six characters, but they are NOT in the idle weight tables: `EmoteTreats.batch2` lists the random treats (with their gates), the player cues are `treatCue` (stage / care hooks), and
//  `treat2MaybeStart` is the ONE call that schedules the random ones (a single line at the top of `idleMaybeStart`; set `EmoteTreats.selfSchedule = false` to hand them to another treat slot).
//    stargazing    NIGHT only: waddles to the nearest window (the window antic's walk), turns, looks up with the starry eyes (the twinkle face + a soft twinkle), a slow happy sway, a little sigh
//    proudStrut    chest out (pitch back 0.07), high-knee march on the spot (the march step, knee 0.08 m), head-high bounce, a little alternate twist; then a happy hop (the joy hop).
//                  Cued after WINNING a race or a show (GameCare+Race / +Show), and rarely as a very-happy treat
//    floorNapFlop  really sleepy (evening, before bed): flops flat on his belly (pitch +0.30, squash 0.60), feet kept under / a touch behind him, eyes shut 3...6 s, then up - or straight into bed at bedtime
//    tapTilt       PLAYER: a tap on the glass near him: he turns toward it (stepping, if it is far round) and tilts his head with a curious "hm?"
//    welcomeWiggle PLAYER: the app is opened again after a short break (25 s ... the long-absence greeting): an excited shimmy, staggered per Jelbie
//    checkIn       PLAYER: nobody has touched the screen for ~75 s: he turns to you, leans in and asks "hello?"; then back to what he was doing
//

import Foundation
import QuartzCore
import simd

/// When the player last touched the room (any gesture on the stage, any HUD button). The check-in asks when this is old.
@MainActor enum PlayerPresence {
    static var last: Double = CACurrentMediaTime()
    static var lastCheckIn: Double = -1000
    static func touch() { last = CACurrentMediaTime() }
}

/// Per-brain bookkeeping of the batch-2 treats.
struct Treat2State {
    /// `variety.now` at which the next random treat may be rolled.
    var next: Float = -1
    /// Where the tap was (floor xz), the delay before a welcome wiggle starts.
    var tapPoint = SIMD2<Float>.zero
    var delay: Float = 0
    /// A win to celebrate: wanted, and how long ago it was asked (dropped after 40 s).
    var strutWanted = false, strutAsked: Float = 0
    var lastWelcome: Double = -1000
    /// Own random stream for haptic jitter (the brain's rand() sequence belongs to the seeded suites).
    var rngS: UInt64 = 0xD1B54A32D192ED03
    mutating func rnd(_ a: Float, _ b: Float) -> Float { a + (b - a) * rnd() }
    mutating func rnd() -> Float { rngS ^= rngS << 13; rngS ^= rngS >> 7; rngS ^= rngS << 17; return Float(rngS >> 40) / Float(1 << 24) }
    var plays: [IdleKind: Int] = [:]
}

enum EmoteTreats {
    /// False = the treats are not rolled by `treat2MaybeStart` (another treat slot starts `batch2` entries itself).
    nonisolated(unsafe) static var selfSchedule = false          // (2026-11-02: the additive treat slot in BlobBrain+Idle.swift rolls the batch-2 treats, on its own clock)
    /// Seconds between two random-treat rolls of one Jelbie, and the lowest wait after one has played.
    static let rollGap: ClosedRange<Float> = 120...240
    /// The player cues.
    static let welcomeAway: ClosedRange<Double> = 25...600
    static let checkInAfter: Double = 75, checkInGap: Double = 150
    static let tapCooldown: Float = 14, tapChance: Float = 0.65, tapRange: Float = 4.2

    struct Entry {
        let name: String
        let idle: IdleKind?
        let social: SocialKind?
        let weight: Float
        /// Seconds this Jelbie (or pair) waits before the same treat again.
        let cooldown: ClosedRange<Float>
        /// Whether he may do it now (time of day, sleepiness, mood). Everything else (free, awake, not held ...) is checked by the starter.
        let eligible: (BlobBrain) -> Bool
    }

    /// The batch-2 random treats. The scheduler of the treat slot: pick by `weight` among the `eligible`, skip a kind still on its cooldown, start `idle` through `idleStart` or `social` through `socialStart(_, with: partner)`.
    /// (The three player cues and the win-cued strut are not rolled: they answer events.)
    static let batch2: [Entry] = [
        Entry(name: "spinHug", idle: nil, social: .spinHug, weight: 1.0, cooldown: 300...480, eligible: { $0.idleMood != .grumpy && $0.idleNight < 0.9 }),
        Entry(name: "stargazing", idle: .stargazing, social: nil, weight: 1.6, cooldown: 420...700, eligible: { $0.treat2Night }),
        Entry(name: "proudStrut", idle: .proudStrut, social: nil, weight: 0.6, cooldown: 420...700, eligible: { $0.idleMood == .happy && $0.idleNight < 0.5 }),
        Entry(name: "floorNapFlop", idle: .floorNapFlop, social: nil, weight: 1.4, cooldown: 360...600, eligible: { $0.treat2Sleepy }),
    ]

    // MARK: haptics (entries for the per-kind table; soft, rounded, intensity <= 0.4)

    struct Pulse { let delay: Double; let i: Float; let s: Float }
    /// "<move>.<beat>" -> soft transients. Each play scales intensity by the move's energy and by 1 +- 15 % (`BlobBrain.treatHaptic`). Mergeable as is.
    static let haptics: [String: [Pulse]] = [
        "spinHug.press": [Pulse(delay: 0, i: 0.30, s: 0.20)],
        "spinHug.step": [Pulse(delay: 0, i: 0.14, s: 0.12)],
        "spinHug.part": [Pulse(delay: 0, i: 0.22, s: 0.15), Pulse(delay: 0.18, i: 0.14, s: 0.12)],
        "stargazing.twinkle": [Pulse(delay: 0, i: 0.16, s: 0.35), Pulse(delay: 0.20, i: 0.12, s: 0.40)],
        "stargazing.sigh": [Pulse(delay: 0, i: 0.18, s: 0.10)],
        "proudStrut.step": [Pulse(delay: 0, i: 0.22, s: 0.15)],
        "proudStrut.hop": [Pulse(delay: 0, i: 0.34, s: 0.20)],
        "floorNapFlop.flop": [Pulse(delay: 0, i: 0.40, s: 0.10), Pulse(delay: 0.12, i: 0.20, s: 0.08)],
        "floorNapFlop.settle": [Pulse(delay: 0, i: 0.12, s: 0.08)],
        "tapTilt.tilt": [Pulse(delay: 0, i: 0.18, s: 0.20)],
        "welcomeWiggle.wiggle": [Pulse(delay: 0, i: 0.26, s: 0.20), Pulse(delay: 0.16, i: 0.20, s: 0.20), Pulse(delay: 0.32, i: 0.14, s: 0.20)],
        "checkIn.hello": [Pulse(delay: 0, i: 0.16, s: 0.18), Pulse(delay: 0.14, i: 0.10, s: 0.14)],          // (a soft two-tap hello: its own pattern, not tapTilt's single tilt tap)
        "hearts.pop": [Pulse(delay: 0, i: 0.10, s: 0.20)],
    ]
    /// Test seam: every request ("floorNapFlop.flop" ...), before the stage's rate limit.
    nonisolated(unsafe) static var requestTap: ((String) -> Void)?
}

extension BlobBrain {
    static let emote2Kinds: Set<IdleKind> = [.stargazing, .proudStrut, .floorNapFlop, .tapTilt, .welcomeWiggle, .checkIn]

    // MARK: gates

    /// Evening / night, before the deep-night bedtime (stargazing).
    var treat2Night: Bool { idleNight > 0.6 && idleDeepNight < 0.5 && !Self.windowXs().isEmpty }
    /// Really sleepy: it is evening (the needs model has no energy bar; the NightRest rule puts them to bed later) or the deep night is on and he is still up.
    var treat2Sleepy: Bool { idleNight > 0.35 || idleDeepNight > 0.4 }

    /// A Jelbie who can take a treat or a cue now: awake, alone, on the floor, not held by a meal / close-up / game.
    var treat2Free: Bool {
        guard anticsEnabled, attached, !held, social == nil, pending == nil, job == nil, !race.active, !volley.active, !commandedFlip, !commandedNameHop, !interruptScript,
              !isSleeping, !sleepLocked, !socialTaken, runMoveDemo == nil else { return false }
        if idleState.kind != nil { return false }
        switch script { case .none, .walk: return true; default: return false }
    }

    // MARK: scheduler

    /// The one call that rolls the random batch-2 treats (top of `idleMaybeStart`). True = a treat started.
    func treat2MaybeStart(_ sim: SoftBody) -> Bool {
        // a win to celebrate comes first (asked by the race / show result)
        if treat2.strutWanted {
            if variety.now - treat2.strutAsked > 60 { treat2.strutWanted = false }
            else if treat2Free, idleStart(.proudStrut, sim) { treat2.strutWanted = false; return true }
        }
        // nobody has touched the screen for a while: one Jelbie (the first to roll) asks "hello?" (a player cue, always on)
        if watching, treat2Free, idleMood != .grumpy, idleNight < 0.5, kindCool[.checkIn] == nil {
            let now = CACurrentMediaTime()
            if now - max(PlayerPresence.last, PlayerPresence.lastCheckIn) > EmoteTreats.checkInAfter, treat2.rnd() < 0.35, idleStart(.checkIn, sim) {
                kindCool[.checkIn] = EmoteTreats.checkInAfter > 0 ? Float(EmoteTreats.checkInGap) : 150
                return true
            }
        }
        guard EmoteTreats.selfSchedule, treat2Free else { return false }
        if treat2.next < 0 { treat2.next = variety.now + treat2.rnd(30, 100) + 25 * Float(steerID % 4); return false }
        guard variety.now >= treat2.next else { return false }
        treat2.next = variety.now + treat2.rnd(EmoteTreats.rollGap.lowerBound, EmoteTreats.rollGap.upperBound)
        return treat2Pick(sim)
    }

    /// The batch-2 entries he may take now (eligible, off cooldown, nobody doing the same).
    var treat2Pool: [EmoteTreats.Entry] {
        EmoteTreats.batch2.filter { e in
            guard e.eligible(self) else { return false }
            if let k = e.idle { return kindCool[k] == nil && !kindCooling.contains(k) && !othersDoing(k) }
            return true
        }
    }

    /// Start one of `treat2Pool` by weight (called by the treat slot, `treatMaybeStart` in BlobBrain+Idle.swift, or by `treat2MaybeStart` itself when `selfSchedule`).
    func treat2Pick(_ sim: SoftBody) -> Bool {
        var pool = treat2Pool
        guard !pool.isEmpty else { return false }
        var x = treat2.rnd() * pool.reduce(0) { $0 + $1.weight }
        for e in pool { if x < e.weight { pool = [e]; break }; x -= e.weight }
        let e = pool[0]
        if let k = e.idle {
            guard idleStart(k, sim) else { return false }
            kindCool[k] = treat2.rnd(e.cooldown.lowerBound, e.cooldown.upperBound)
            return true
        }
        guard let kind = e.social, socialBook.enabled, socialBook.cooldown <= 0 else { return false }
        let partners = socialOthers().filter { $0 !== self && $0.treat2Free && $0.socialFree && simd_distance($0.position, position) < 5 && ($0.idleMood != .grumpy) && $0.socialBook.pair[steerID] ?? 0 <= 0 }
        guard let o = partners.min(by: { simd_distance($0.position, position) < simd_distance($1.position, position) }), socialFree else { return false }
        if socialStart(kind, with: o, sim) { socialBook.treatCool = max(socialBook.treatCool, 60); return true }
        return false
    }

    // MARK: player cues

    /// Ask for a player-cued move. Taken straight away when he is free (a plain wander leg is stopped for it): the commanded path of the tick starts it.
    @discardableResult
    func treatCue(_ kind: IdleKind, tap: SIMD2<Float>? = nil, delay: Float = 0) -> Bool {
        guard treat2Free, commandedIdle == nil, kindCool[kind] == nil else { return false }
        if let tap { treat2.tapPoint = tap }
        treat2.delay = delay
        commandedIdle = kind
        return true
    }

    /// A tap on the empty floor / glass at floor point `p`: the nearest awake free Jelbie within range may tilt his head toward it.
    static func tapCue(at p: SIMD2<Float>, brains: [BlobBrain]) -> Bool {
        let c = brains.filter { $0.treat2Free && $0.kindCool[.tapTilt] == nil && simd_distance($0.position, p) < EmoteTreats.tapRange && simd_distance($0.position, p) > 0.9 }
        guard let b = c.min(by: { simd_distance($0.position, p) < simd_distance($1.position, p) }) else { return false }
        guard b.treat2.rnd() < EmoteTreats.tapChance else { return false }
        return b.treatCue(.tapTilt, tap: p)
    }

    /// A win (race / show): this Jelbie struts when he is next free.
    func proudStrutCue() {
        guard !isSleeping else { return }
        treat2.strutWanted = true; treat2.strutAsked = variety.now
    }

    // MARK: haptics

    /// One soft haptic beat of a batch-2 move. `energy` scales it; every play varies +- 15 %.
    func treatHaptic(_ key: String, energy: Float = 1) {
        guard !race.active, !volley.active, EmoteTreats.haptics[key] != nil else { return }
        EmoteTreats.requestTap?(key)
        roomCue(.beat(key), energy: energy)          // (the one HapticDriver: Haptics+Emotes.swift; the whole pattern plays, its later pulses are not rate-limited away)
    }

    // MARK: start

    func emote2Begin(_ kind: IdleKind, _ sim: SoftBody) -> Bool {
        if kind == .stargazing {
            guard let w = windowSpot(from: position) else { return false }
            idleBegin(.stargazing)
            idleState.windowGo = true
            idleState.target = w.spot
            idleState.hold = rand(5.2, 6.8)
            idleState.reps = 0
            let wy = atan2f(w.wx - w.spot.x, RoomLayout.minZ - w.spot.y), cam = faceCameraYaw()
            // (a three-quarter turn to the glass, the side nearer the room: the starry face still shows to the player)
            idleState.goalYaw = abs(wrapAngle(wy + 2.0 - cam)) < abs(wrapAngle(wy - 2.0 - cam)) ? wy + 2.0 : wy - 2.0
            idleState.k = 0; idleState.hop = 0; idleState.jackA = 0
            script = .walk(target: w.spot, then: .none); activity = .walking
            treat2.plays[kind, default: 0] += 1
            return true
        }
        idleBegin(kind)
        script = .idle
        activity = (kind == .tapTilt || kind == .checkIn) ? .lookingAround : .playing
        idleState.k = 0; idleState.hop = 0; idleState.jackA = 0; idleState.steps = 0; idleState.reps = 0
        idleState.hold = kind == .floorNapFlop ? rand(3, 6) : 0
        switch kind {
        case .tapTilt:
            let err = wrapAngle(yawTo(treat2.tapPoint) - yaw)
            idleState.goalYaw = abs(err) > 0.6 ? clampedLook(yawTo(treat2.tapPoint)) : yaw          // (a small turn is done with the head)
            idleState.sign = leanSign(toward: treat2.tapPoint)
        case .welcomeWiggle, .checkIn, .proudStrut, .floorNapFlop:
            idleState.goalYaw = faceCameraYaw()
            if kind == .floorNapFlop { idleState.goalYaw += idleState.sign * 0.35 }          // (a little turned: the flat body shows its side as well as its face)
        default: idleState.goalYaw = yaw
        }
        if kind == .checkIn { PlayerPresence.lastCheckIn = CACurrentMediaTime() }
        treat2.plays[kind, default: 0] += 1
        return true
    }

    // MARK: run

    private func e2Once(_ bit: Int, _ t: Float, at t0: Float) -> Bool {
        guard t >= t0, idleState.steps & (1 << bit) == 0 else { return false }
        idleState.steps |= 1 << bit
        return true
    }

    private func e2Done(_ skinner: Skinner) {
        runAir = 0; armDirW = 0; armDirOut = 0
        skinner.setEyeOpenness(1)
        mouthOpen = 0
        idleFinish(skinner)
    }

    func runEmote2(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard let kind = idleState.kind else { return }
        runAir = 0
        armWalkWant = (kind == .proudStrut || kind == .welcomeWiggle) ? 1 : 0
        switch kind {
        case .stargazing: runStargaze(skinner, dt)
        case .proudStrut: runStrut(sim, skinner, dt)
        case .floorNapFlop: runFlop(sim, skinner, dt)
        case .tapTilt: runTapTilt(skinner, dt)
        case .welcomeWiggle: runWelcome(skinner, dt)
        default: runCheckIn(skinner, dt)
        }
    }

    /// The shared opening: turn to `idleState.goalYaw` on the spot (steps), a wait of `treat2.delay` for the staggered ones. True = still opening.
    private func e2Opening(tol: Float = 0.1, wait: Float = 0) -> Bool {
        if idleState.phase == 0 {
            let turning = turnSteps(goal: idleState.goalYaw, tol: tol)
            gaitPose(sway: 0.04, bob: 0, rock: 0.2)
            if turning || feet.active { idleState.phaseT = 0; return true }
            if idleState.phaseT < wait { return true }
            idleState.phase = 1; idleState.phaseT = 0
        }
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        return false
    }

    // MARK: stargazing

    private func runStargaze(_ skinner: Skinner, _ dt: Float) {
        if idleState.windowGo { return }          // (still walking: the gate runs the walk)
        var k = idleState.k
        let hold = idleState.hold
        switch idleState.phase {
        case 0:     // turn to the glass
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.06)
            if !turning && !feet.active { idleState.phase = 1; idleState.phaseT = 0 }
        case 1:     // look up and sway
            k = min(1, k + dt / 0.8)
            if idleState.phaseT >= hold { idleState.phase = 2; idleState.phaseT = 0 }
        default:    // look back down, turn to the room
            k = max(0, k - dt / 0.6)
            let turning = turnSteps(goal: faceCameraYaw(), tol: 0.1)
            if !turning && !feet.active && k <= 0.001 { idleState.k = 0; e2Done(skinner); return }
        }
        idleState.k = k
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        let t = idleState.phaseT, ease = smooth01(k)
        if idleState.phase == 1 {
            let w = 2 * Float.pi * t / 2.9
            roll += 0.075 * ease * sinf(w) * amplitude                    // the slow happy sway
            twist = 0.05 * ease * sinf(w + 1.1) * amplitude
            squash *= 1 + 0.012 * ease * sinf(2 * Float.pi * t / 3.6)
            if e2Once(0, t, at: 0.5) {
                face(.starry, hold: hold + 0.6)
                AudioHub.shared.play(.emoteTwinkle, x: px, volume: 1)
                treatHaptic("stargazing.twinkle", energy: 0.9)
            }
            // the little sigh: a soft coo, the mouth a small "o", a gentle sag
            let s0 = hold - 1.7
            if e2Once(1, t, at: s0) {
                AudioHub.shared.play(.emoteStarSigh, jelly: steerID, x: px, volume: 1)
                treatHaptic("stargazing.sigh")
            }
            if t > s0 {
                let u = (t - s0) / 1.3
                mouthOpen = 0.22 * sinf(.pi * min(1, max(0, u)))
                squash *= 1 - 0.03 * sinf(.pi * min(1, max(0, u)))
                pitch += 0.05 * smooth01(u)          // the head sinks a touch with it
            }
        }
        pitch -= 0.15 * ease                                              // the head back: looking up
    }

    // MARK: proud strut

    private func runStrut(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        if e2Opening() { return }
        let a = amplitude
        let t = idleState.phaseT
        let total: Float = commanded ? 1.8 : 3.5          // (the Shop trick's cut: 4 steps, then the hop; the Show gives it 3.2 s)
        let env = smooth01(t / 0.35) * (1 - smooth01((t - (total - 0.4)) / 0.4))
        if t < total, !feet.active {
            startStep(peak: 0.095 * a, rate: 2.2, swingFrac: 0.8, inPlace: true)
            idleState.hop += 1
            if idleState.hop == 1 { AudioHub.shared.play(.emoteStrut, x: px, volume: 1) }
            if idleState.hop % 2 == 0 { treatHaptic("proudStrut.step", energy: 0.9) }
        }
        gaitPose(sway: 0.05, bob: 0.05, rock: 0.3)
        let sideSign: Float = feet.side == 1 ? 1 : -1
        let bounce = feet.active ? sinf(.pi * feet.stepU) : 0
        pitch -= 0.09 * env * a                                          // chest out
        squash *= 1 + 0.05 * env * bounce * a                            // the head-high bounce with each knee
        if feet.active { twist = 0.07 * env * sideSign * sinf(.pi * feet.stepU) * a }
        if e2Once(0, t, at: 0) { face(.happy, hold: total + 0.4); blushBump(hold: 2.6, peak: 0.55) }
        if t >= total && !feet.active {
            // the happy hop: the joy hop takes over on the spot (a hop is the one move that lifts both feet, with the tuck)
            idleBegin(.joy)
            idleState.target = position
            idleState.reps = 1
            idleState.hop = 0; idleState.landT = 0
            script = .idle; activity = .playing
            idleState.phase = 1; idleState.phaseT = 0
            armDirW = 0; twist = 0
            idleScootHop(sim)
            face(.joyArc, hold: 1.0)
            AudioHub.shared.chirp(jelly: steerID, .happy, x: px)
            treatHaptic("proudStrut.hop")
            if !commanded { kindCool[.proudStrut] = rand(420, 700) }
        }
    }

    // MARK: floor nap flop (the sploot)

    private func runFlop(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        var k = idleState.k
        if idleState.yielding {
            k = max(0, k - dt / 0.25)
            if k <= 0.001 { idleState.k = 0; floorFlopPose(skinner, 0); e2Done(skinner); return }
        } else {
            switch idleState.phase {
            case 0:
                if e2Opening(tol: 0.08) { floorFlopPose(skinner, 0); return }
            case 1:     // the flop: a quick drop, a squash on landing
                k = smooth01(idleState.phaseT / 0.30)
                if e2Once(0, idleState.phaseT, at: 0.22) {
                    jellyKick = max(jellyKick, 2.6)
                    AudioHub.shared.play(.emoteSploot, x: px, volume: 1)
                    treatHaptic("floorNapFlop.flop")
                }
                if idleState.phaseT >= 0.30 { idleState.phase = 2; idleState.phaseT = 0; face(.sleepy, hold: idleState.hold + 0.5) }
            case 2:     // lie there, eyes shut, breathing
                k = 1
                if e2Once(1, idleState.phaseT, at: 0.6) { treatHaptic("floorNapFlop.settle") }
                if idleState.phaseT >= idleState.hold { idleState.phase = 3; idleState.phaseT = 0 }
            default:    // up again with a little stretch overshoot
                let u = min(1, idleState.phaseT / 0.65)
                k = 1 - u * (2 - u)
                if u >= 1 {
                    idleState.k = 0; floorFlopPose(skinner, 0)
                    jellyKick = max(jellyKick, 1.4)
                    runAir = 0; armDirW = 0; skinner.setEyeOpenness(1)
                    if idleDeepNight > 0.5 || bedtimeHours {          // bedtime: straight into bed
                        idleEnd(skinner, cooldown: false)
                        script = .none
                        if idleStart(.sleep, sim) { return }
                    }
                    idleFinish(skinner); return
                }
            }
        }
        idleState.k = k
        // the feet stay under him, a touch behind (they splay back as he lies on his belly)
        if k > 0 || idleState.phase >= 1 {
            let back = SIMD2(-sinf(yaw), -cosf(yaw)) * 0.06 * smooth01(k)
            for s in 0..<2 {
                let nominal = SIMD2(px, pz) + rotXZ(geom.off[s], yaw) + back
                feet.pos[s] += (nominal - feet.pos[s]) * min(1, dt / 0.07)
            }
        }
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        floorFlopPose(skinner, k)
    }

    func floorFlopPose(_ skinner: Skinner, _ k: Float) {
        let a = amplitude
        var stretch: Float = 1
        if idleState.phase == 3 && !idleState.yielding { let u = min(1, idleState.phaseT / 0.65); stretch = 1 + 0.05 * sinf(.pi * smooth01(max(0, (u - 0.6) / 0.4))) }
        squash *= (1 - 0.46 * k) * stretch
        pitch += 0.34 * k * a                                             // forward onto the belly (never sideways)
        lift -= 0.0 * k
        if idleState.phase == 2 { squash *= 1 + 0.012 * sinf(2 * Float.pi * 0.4 * idleState.phaseT) * k }
        // the arms out to the sides, still the stubby capsules (direction only: the length stays capped)
        armDirW = smooth01(k)
        armDirEl = [-0.10, -0.10]; armDirSa = [0.85, 0.85]; armDirOut = 0.04
        skinner.setEyeOpenness(max(0.03, 1 - 0.97 * smooth01(max(0, (k - 0.4) / 0.5))))
        mouthOpen = 0
    }

    // MARK: tap tilt

    private func runTapTilt(_ skinner: Skinner, _ dt: Float) {
        if idleState.phase == 0 {
            let turning = turnSteps(goal: idleState.goalYaw, tol: 0.5)
            gaitPose(sway: 0.04, bob: 0, rock: 0.2)
            if turning || feet.active { idleState.phaseT = 0; return }
            idleState.phase = 1; idleState.phaseT = 0
        }
        gaitPose(sway: 0.04, bob: 0, rock: 0.2)
        let t = idleState.phaseT
        let hold: Float = 1.3
        let k = smooth01(t / 0.35) * (1 - smooth01((t - 0.35 - hold) / 0.5))
        // the head turn toward the tap (what the steps did not do), the tilt toward it, a little lean in
        let err = max(-0.45, min(0.45, wrapAngle(yawTo(treat2.tapPoint) - yaw)))
        twist = err * k
        roll += idleState.sign * 0.20 * k * amplitude
        pitch += 0.05 * k
        if e2Once(0, t, at: 0.05) {
            face(.curious, hold: hold + 0.8)
            AudioHub.shared.play(.emoteTilt, jelly: steerID, x: px, volume: 1)
            treatHaptic("tapTilt.tilt")
        }
        if t > 0.35 + hold + 0.6 && !feet.active { twist = 0; e2Done(skinner) }
    }

    // MARK: welcome wiggle

    private func runWelcome(_ skinner: Skinner, _ dt: Float) {
        if e2Opening(wait: treat2.delay) { return }
        let a = amplitude
        let t = idleState.phaseT
        let dur: Float = 1.8
        let env = smooth01(t / 0.2) * (1 - smooth01((t - (dur - 0.45)) / 0.45))
        let w = 2 * Float.pi * 5.5 * t
        twist = 0.28 * env * sinf(w) * a
        roll += 0.05 * env * sinf(w + 0.6) * a
        squash *= 1 - 0.05 * env * (0.5 - 0.5 * cosf(2 * w)) * a
        if e2Once(0, t, at: 0) {
            face(.excited, hold: 1.2); blushBump(hold: 2.6, peak: 0.6)
            AudioHub.shared.play(.emoteWelcome, jelly: steerID, x: px, volume: 1)
            treatHaptic("welcomeWiggle.wiggle")
            jellyKick = max(jellyKick, 1.6)
        }
        if e2Once(1, t, at: 0.9) { face(.joyArc, hold: 0.8) }
        if t > dur && !feet.active { twist = 0; e2Done(skinner) }
    }

    // MARK: check in

    private func runCheckIn(_ skinner: Skinner, _ dt: Float) {
        if e2Opening(tol: 0.1) { return }
        let a = amplitude
        let t = idleState.phaseT
        let ask: Float = 3.2
        // the ask: lean in toward the player, hopeful brows, two small expectant bobs; then back to what he was doing (no touch handling)
        let lean = smooth01(t / 0.5) * (1 - smooth01((t - (ask - 0.5)) / 0.5))
        pitch += 0.16 * lean * a
        roll += 0.07 * lean * sinf(2 * Float.pi * t / 1.9) * a          // (a questioning sway)
        let bob = (t > 0.9 && t < 1.25 ? sinf(.pi * (t - 0.9) / 0.35) : 0) + (t > 1.7 && t < 2.05 ? sinf(.pi * (t - 1.7) / 0.35) : 0)
        squash *= 1 + 0.06 * bob * lean * a
        if e2Once(0, t, at: 0.15) { face(.hopeful, hold: ask); }
        if e2Once(1, t, at: 0.4) { AudioHub.shared.play(.emoteCheckIn, jelly: steerID, x: px, volume: 1); treatHaptic("checkIn.hello") }
        if t > ask + 0.3 && !feet.active { e2Done(skinner) }
    }
}
