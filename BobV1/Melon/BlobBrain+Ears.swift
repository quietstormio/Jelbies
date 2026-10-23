//
//  BlobBrain+Ears.swift
//  "Ears on": what the Jellies DO when they hear something. Two parts:
//    EarsPose    a small additive channel on the brain's pose (pitch / roll about his facing, squash), like the touch and social channels, so
//                a dance bounce, a giggle, a startle flinch or a curious tilt ride on top of whatever he is doing without a new script. Eased
//                toward its wants; the dance writes it directly so the bounce lands exactly on the beat.
//    EarsReactor dispatches detector events to the Jellies in the room with the locks (meal, close-up approach, bath, voice, training, race) and
//                drives the dance from the beat: squash bounce + alternating sway per beat, a hop every 8 beats, a spin every 32, all on existing
//                moves (hop play, spin, turn, look). Sleeping Jellies only stir unless it is very loud. Cooldowns are the detector's.
//  Body, face and the walk are untouched: the pose channel is applied in `drivePose` next to the touch channel (`BlobBrain.ears`).
//

import Foundation
import simd

/// Additive pose channel (rad, rad, factor). `set` eases toward the wants; `write` sets the pose now (the beat-locked dance).
nonisolated struct EarsPose: Equatable {
    var pitch: Float = 0, roll: Float = 0, squash: Float = 1
    var wantPitch: Float = 0, wantRoll: Float = 0, wantSquash: Float = 1
    /// Ease rate (1/s).
    var rate: Float = 9
    /// A dance is on (the brain stays awake and in place).
    var dancing = false

    var isNeutral: Bool {
        abs(pitch) < 1e-3 && abs(roll) < 1e-3 && abs(squash - 1) < 1e-3 && abs(wantPitch) < 1e-3 && abs(wantRoll) < 1e-3 && abs(wantSquash - 1) < 1e-3
    }
    var isActive: Bool { dancing || !isNeutral }

    mutating func set(pitch p: Float = 0, roll r: Float = 0, squash s: Float = 1) { wantPitch = p; wantRoll = r; wantSquash = s }
    mutating func write(pitch p: Float, roll r: Float, squash s: Float) { pitch = p; roll = r; squash = s; wantPitch = p; wantRoll = r; wantSquash = s }
    mutating func clear() { set() }
    mutating func ease(dt: Float) {
        let k = min(1, rate * dt)
        pitch += (wantPitch - pitch) * k; roll += (wantRoll - roll) * k; squash += (wantSquash - squash) * k
        if abs(pitch) < 1e-4 && wantPitch == 0 { pitch = 0 }
        if abs(roll) < 1e-4 && wantRoll == 0 { roll = 0 }
        if abs(squash - 1) < 1e-4 && wantSquash == 1 { squash = 1 }
    }
}

extension BlobBrain {
    /// The ears channel is doing something (a dance, or a pose not yet back to neutral): the sim must not sleep.
    var earsActive: Bool { ears.isActive }
}

nonisolated enum EarsDance {
    /// Squash at the beat (1 - this), the sway amplitude (rad), the slight nod.
    static let bounce: Float = 0.09
    static let sway: Float = 0.07
    static let nod: Float = 0.03
    /// A hop every `hopEvery` beats, a spin every `spinEvery` (offset by half).
    static let hopEvery = 8
    static let spinEvery = 32
    /// With no tempo yet (the first seconds of a dance) they bob at this.
    static let defaultBPM: Float = 100
    /// They keep dancing this long after the music stopped.
    static let tail: Double = 2.5
    /// 0...1 bump that peaks on the beat (phase 0) and is 0 by the half beat.
    static func bump(_ phase: Double) -> Float { let c = Float(cos(2 * Double.pi * phase)); return c > 0 ? c * c : 0 }
}

/// Dispatches ear events to the room. Plain class, ticked from the stage (main thread); tests tick it with MotionRigs.
final class EarsReactor {
    /// What stops a reaction. `blocksAll`: nothing happens. `focus` (the close-up): only the small reactions, no come and no dance.
    struct Locks: Equatable {
        var meal = false, focus = false, focusApproach = false, bath = false, voice = false, training = false, race = false
        var blocksAll: Bool { meal || focusApproach || bath || voice || training || race }
        var blocksBig: Bool { blocksAll || focus }
    }
    struct Jelly {
        let id: Int
        let brain: BlobBrain
        let sim: SoftBody
        init(id: Int, brain: BlobBrain, sim: SoftBody) { self.id = id; self.brain = brain; self.sim = sim }
    }
    struct Dance: Equatable {
        var beat: EarBeat?
        var started: Double
        var endAt: Double?
        var lastIndex = Int.min
    }
    enum Anim: Equatable { case perk, giggle, startle(level: Float), curious, tilt, stir }

    var locks = Locks()
    /// Another worker's lock (the race): read every tick.
    var extraLock: () -> Bool = { false }
    /// Care hooks (GameCare.comeHere / comeHereEveryone); tests count them.
    var comeHere: (Int) -> Void = { _ in }
    var comeEveryone: () -> Void = {}
    /// The dance started / ended (the hub fades its own music down while they dance to someone else's).
    var onDance: (Bool) -> Void = { _ in }
    private(set) var dance: Dance?
    private var anims: [Int: (anim: Anim, t: Float)] = [:]
    private var hurrying: Set<Int> = []
    private var whistleComeAt: Double?
    private var startleHopped: Set<Int> = []
    private var startleTurned: Set<Int> = []
    /// Tests / the log: what was done.
    private(set) var log: [String] = []
    var isDancing: Bool { dance != nil }
    func anim(of id: Int) -> Anim? { anims[id]?.anim }

    init() {}
    nonisolated deinit {}

    // MARK: locks

    /// The locks from the game's state (plus `extraLock`).
    @MainActor
    func update(care: GameCare) {
        var l = Locks()
        l.meal = care.trayOut || care.wanted != nil || care.meal != nil || care.groupActive
        l.focus = care.focus.isActive
        l.focusApproach = care.focus.isActive && care.focus.phase == .approaching
        l.bath = care.bath.active
        l.voice = care.voice.mode.phase != .idle
        l.training = care.voice.nickLesson != nil || care.voice.teachPrompt != nil
        // Jelly Circuit / Rhythm Steps: from the moment a race or drill is asked (even while he is still rolling up) until the trip is over
        l.race = care.race.active || care.raceWait != nil || extraLock()
        locks = l
    }

    // MARK: events

    func handle(_ e: EarEvent, jellies: [Jelly], now: Double) {
        locks.race = extraLock()
        guard !locks.blocksAll else { note("blocked \(e)"); return }
        // a reserved Jelly (his meal is coming) waits where he stands: no reaction at all. (`idleBlocked` is NOT a reason: the close-up
        // sets it on everybody, and there the small reactions still land, see `Locks.focus`.)
        let free = jellies.filter { !$0.brain.reserved }
        let awake = free.filter { !$0.brain.isSleeping }          // (on his way to bed or rolling counts as asleep for sound)
        let asleep = free.filter { $0.brain.isSleeping }
        switch e {
        case .heard(.clap), .heard(.snap):
            for j in asleep { start(.stir, j) }
            guard !locks.blocksBig else { for j in awake { start(.giggle, j) }; return }
            for j in awake { start(.perk, j) }
            if let near = nearestToFront(awake) { come(near); note("clap: \(near.id) comes") }
        case .doubleClap:
            for j in asleep { start(.stir, j) }
            guard !locks.blocksBig else { for j in awake { start(.giggle, j) }; return }
            if !asleep.isEmpty {          // sleepers in the room: a double clap is only a clap (nobody calls everyone and wakes them)
                for j in awake { start(.perk, j) }
                if let near = nearestToFront(awake) { come(near); note("double clap (sleepers): \(near.id) comes") }
                return
            }
            for j in awake { start(.perk, j); j.brain.hurry = true; hurrying.insert(j.id) }
            comeEveryone(); note("double clap: everyone comes")
        case .musicStarted(let b):
            guard !locks.blocksBig else { return }
            if dance == nil { dance = Dance(beat: b, started: now); onDance(true); note("dance on \(b.map { "\($0.bpm) bpm" } ?? "no beat")") }
            else { dance?.endAt = nil; dance?.beat = b ?? dance?.beat }
            for j in awake { j.brain.ears.dancing = true; j.brain.face(.joyArc, hold: 1.6); j.brain.blushBump(hold: 2.4, peak: 0.5) }          // the dance: "^^" eyes and a blush
            for j in asleep { start(.stir, j) }
        case .musicBeat(let b):
            dance?.beat = b
        case .musicStopped:
            if dance != nil, dance?.endAt == nil { dance?.endAt = now + EarsDance.tail; note("music stopped: dance ends in \(EarsDance.tail) s") }
        case .heard(.laugh):
            for j in awake { start(.giggle, j) }
            for j in asleep { start(.stir, j) }
        case .heard(.whistle):
            for j in awake { start(.tilt, j) }
            for j in asleep { start(.stir, j) }
            if !locks.blocksBig { whistleComeAt = now + 2.4 }
        case .heard(.dogBark), .heard(.doorbell):
            for j in awake { start(.startle(level: 0.5), j) }
            for j in asleep { start(.stir, j) }
        case .heard(.catMeow), .heard(.babyCry):
            for j in awake { start(.curious, j) }
        case .bang(let level):
            for j in awake { start(.startle(level: level), j) }
            for j in asleep {
                if level >= SleepTuning.earsWakeLevel { j.brain.sleepWake(groggy: true, fast: true); start(.startle(level: level), j); note("bang woke \(j.id)") }
                else { start(.stir, j) }
            }
        case .heard(.speech), .heard(.music), .heard(.loudBang):
            break
        }
    }

    // MARK: tick

    func tick(jellies: [Jelly], dt: Float, now: Double) {
        // the dance ends a little after the music, or at once when something takes the room (meal, bath ...)
        if let d = dance {
            if locks.blocksBig || (d.endAt.map { now >= $0 } ?? false) { endDance(jellies) }
            else { driveDance(jellies, now: now) }
        }
        if let t = whistleComeAt, now >= t {
            whistleComeAt = nil
            if !locks.blocksBig, let near = nearestToFront(jellies.filter { !$0.brain.isSleeping }) { come(near); note("whistle: \(near.id) comes") }
        }
        for j in jellies {
            if hurrying.contains(j.id) {
                j.brain.hurryUpdate(dt: dt)
                if !j.brain.hurry { hurrying.remove(j.id) }
            }
            guard var a = anims[j.id] else { continue }
            a.t += dt
            if drive(a.anim, t: a.t, j) { anims[j.id] = nil; if !j.brain.ears.dancing { j.brain.ears.clear() } } else { anims[j.id] = a }
        }
    }

    private func driveDance(_ jellies: [Jelly], now: Double) {
        guard var d = dance else { return }
        let beat = d.beat ?? EarBeat(bpm: EarsDance.defaultBPM, anchor: d.started, strength: 0)
        let (ph, idx) = beat.phase(at: now)
        let newBeat = idx != d.lastIndex
        d.lastIndex = idx
        dance = d
        let b = EarsDance.bump(ph)
        for j in jellies where j.brain.ears.dancing {
            let brain = j.brain
            if brain.isNapping || brain.reserved || anims[j.id] != nil { continue }
            // stay for the song: no wander legs or idle specials start while dancing
            brain.restTimer = max(brain.restTimer, 1.5)
            brain.idleState.cooldown = max(brain.idleState.cooldown, 1.5)
            let side: Float = (idx & 1) == 0 ? 1 : -1
            let sway = EarsDance.sway * side * Float(sin(Double.pi * ph)) * brain.amplitude
            brain.ears.write(pitch: -EarsDance.nod * b * brain.amplitude, roll: sway, squash: 1 - EarsDance.bounce * b * brain.amplitude)
            if newBeat, case .none = brain.script, brain.idleState.kind == nil, brain.pending == nil, !brain.gait.isBusy {
                if idx % EarsDance.spinEvery == EarsDance.spinEvery / 2 { brain.startSpin(sim: j.sim); note("spin \(j.id) beat \(idx)") }
                else if idx % EarsDance.hopEvery == 0 { brain.startHopPlay(sim: j.sim, distance: 0.0001); note("hop \(j.id) beat \(idx)") }
            }
        }
    }

    private func endDance(_ jellies: [Jelly]) {
        dance = nil
        for j in jellies { j.brain.ears.dancing = false; if anims[j.id] == nil { j.brain.ears.clear() } }
        onDance(false)
        note("dance off")
    }

    /// Stops everything (Ears switched off, app backgrounded).
    func reset(_ jellies: [Jelly]) {
        if dance != nil { endDance(jellies) }
        for j in jellies { j.brain.ears.clear(); if hurrying.contains(j.id) { j.brain.hurry = false } }
        anims.removeAll(); hurrying.removeAll(); whistleComeAt = nil; startleHopped.removeAll(); startleTurned.removeAll()
    }

    // MARK: the small reactions

    private func start(_ a: Anim, _ j: Jelly) {
        if case .stir = a, anims[j.id] != nil { return }
        if case .startle = a { startleHopped.remove(j.id); startleTurned.remove(j.id) }
        anims[j.id] = (a, 0)
        note("\(a) \(j.id)")
        // the face goes with it (the liveliness expression layer, BlobBrain+Expression.swift): a clap perks the brows up, a laugh is "^^" eyes,
        // a bang is wide-eyed, a meow / whistle is the one-brow tilt. Sleepers only stir, no face.
        switch a {
        case .perk: j.brain.face(.happy, hold: 1.2)
        case .giggle: j.brain.face(.joyArc, hold: 1.0)
        case .startle(let level): j.brain.face(.surprised, hold: 1.0 + 0.6 * level)
        case .curious, .tilt: j.brain.face(.curious, hold: 1.4)
        case .stir: break
        }
    }

    /// One frame of a reaction; true when it is over.
    private func drive(_ a: Anim, t: Float, _ j: Jelly) -> Bool {
        let brain = j.brain, amp = brain.amplitude
        switch a {
        case .perk:
            // ears up: a blink, a small lift, and he turns to the front if he is free and facing away
            if t < 0.02 { brain.blinkRequested = true }
            brain.ears.set(pitch: -0.06 * amp)
            if t >= 0.1, t < 0.1 + 1.0 / 60, case .none = brain.script, brain.idleState.kind == nil, abs(wrapAngle(brain.yaw - brain.faceCameraYaw())) > 0.35 {
                brain.startTurn(to: brain.faceCameraYaw(), sim: j.sim)
            }
            if t >= 0.9 { brain.ears.clear() }
            return t >= 1.2
        case .giggle:
            let d: Float = 1.0, k = max(0, 1 - t / d)
            brain.ears.write(pitch: 0, roll: 0.05 * amp * k * sinf(2 * .pi * 2.5 * t), squash: 1 - 0.07 * amp * k * abs(sinf(2 * .pi * 5 * t)))
            return t >= d
        case .startle(let level):
            let depth: Float = (0.12 + 0.1 * level) * amp
            if t < 0.12 { brain.ears.write(pitch: 0.04 * amp, roll: 0, squash: 1 - depth * (t / 0.12)) }          // the flinch: down fast
            else if t < 0.3 { brain.ears.write(pitch: 0.04 * amp * (1 - (t - 0.12) / 0.18), roll: 0, squash: 1 - depth * (1 - (t - 0.12) / 0.18)) }
            else { brain.ears.clear() }
            if t >= 0.18, !startleHopped.contains(j.id) {
                startleHopped.insert(j.id)
                if case .none = brain.script, brain.pending == nil { brain.startHopPlay(sim: j.sim, distance: 0.0001) }
            }
            if t >= 0.9, !startleTurned.contains(j.id), case .none = brain.script, brain.idleState.kind == nil, !brain.gait.isBusy {
                startleTurned.insert(j.id)
                // look toward the door (the front, where the player is)
                if abs(wrapAngle(brain.yaw - brain.faceCameraYaw())) > 0.25 { brain.startTurn(to: brain.faceCameraYaw(), sim: j.sim) }
            }
            return t >= 2.2
        case .curious:
            if t < 0.02 { brain.blinkRequested = true }
            if t < 1.2 { brain.ears.set(pitch: -0.08 * amp, roll: 0.09 * amp) } else { brain.ears.clear() }
            return t >= 1.6
        case .tilt:
            if t < 0.6 { brain.ears.set(roll: 0.14 * amp) }
            else {
                brain.ears.clear()
                if t < 0.6 + 1.0 / 60, case .none = brain.script, brain.idleState.kind == nil, !locks.focus { brain.commandedIdle = .look }
            }
            return t >= 1.0
        case .stir:
            let d: Float = 0.8
            brain.ears.write(pitch: 0, roll: 0.03 * amp * sinf(2 * .pi * 3 * t) * max(0, 1 - t / d), squash: 1)
            return t >= d
        }
    }

    // MARK: helpers

    private func nearestToFront(_ js: [Jelly]) -> Jelly? {
        js.min { simd_length($0.brain.position - GameCamera.callSpot) < simd_length($1.brain.position - GameCamera.callSpot) }
    }
    private func come(_ j: Jelly) {
        j.brain.hurry = true; hurrying.insert(j.id)
        comeHere(j.id)
    }
    private func note(_ s: String) { log.append(s); if log.count > 60 { log.removeFirst() } }
}
