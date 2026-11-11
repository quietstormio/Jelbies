//
//  BlobBrain+Weather.swift
//  What the Jelbies do in a storm (Melon/Weather.swift is the storm). StormReactor turns the storm's events into reactions, on moves that already exist:
//    notice     in the build-up one Jelbie walks to a window and peers out worried (the window antic, `commandedIdle = .window`)
//    startle    the first close thunder: a surprised face and a flinch (and a hop, the startle's own)
//    huddle     during the peak every free Jelbie scurries (the walk at the hurry speed, `hurry`) to a tight cluster and stands pressed close: slots a little more than
//               the room's keep-apart gap apart (`Lineup` picks who takes which, walks never cross and never run through a standing Jelbie), a hunched stance,
//               a fine tremble, worried eyes, and a flinch at every flash. Everything is the storm POSE CHANNEL (`BlobBrain.storm`, an EarsPose added in `drivePose`):
//               the body, the feet and the walk are untouched, so the feet stay attached by construction (StormFeetTests).
//    comfort    a Jelbie the player is holding or petting (a finger on him, a close-up) stays with the player and calms: no gather, no tremble, a calm face
//    sleepers   flinch (a jelly wobble), and at the first close thunder of the peak wake grumpy and join the others
//    comfort    (2026-11-11) after a few seconds of trembling every scared Jelbie gets better while the storm goes on, and stays better: one calm, brave Jelbie comes to the most scared and holds it side by side
//               (swayHug / cuddleLean: hearts, a soft chirp each, one light haptic), two scared ones hold each other, a left-over one calms beside them, a lone one sighs, lies down with its eyes closed
//               (floorNapFlop) and settles; a stroking finger of 1.5 s makes the calm stick. A comforted Jelbie only flinches a little at later thunder.
//    relief     when the storm clears the cluster breaks with a relieved group shake-off (the `shake` move), a sigh, and they scatter; the comforted ones skip it: a stretch, a happy hop, free
//  Busy Jelbies (a meal, the bath, a race or any trip, a voice lesson) skip all of it; a lock that starts mid-huddle lets everybody go at once.
//

import Foundation
import simd

nonisolated enum StormTuning {
    /// Centre distance of two huddled Jelbies relative to the room's keep-apart gap (MelonController.jellyGap): a hair more, so nobody is pushed.
    static let gapFactor: Float = 1.05
    /// The tremble.
    static let trembleHz: Float = 9, trembleRoll: Float = 0.030, trembleSquash: Float = 0.012
    /// The hunched stance (squash below 1) and the lean forward (rad).
    static let hunch: Float = 0.05, lean: Float = 0.02
    /// The flash flinch: squash dip, forward pitch (rad), rise and fall times (s).
    static let flinchSquash: Float = 0.10, flinchPitch: Float = 0.07, flinchRise: Float = 0.08, flinchFall: Float = 0.22
    /// Seconds the startle lasts before the scurry begins.
    static let startleTime: Float = 0.8
    /// A scurrying Jelbie that has not arrived after this long is taken as arrived where he stands.
    static let gatherLimit: Float = 12
    /// The shake-offs are staggered this much; the scatter walks start after the shake.
    static let shakeStagger: Float = 0.28, shakeTime: Float = 3.2, scatterTime: Float = 5
}

/// The comfort arcs (user 2026-11-11: "they shake in fear but never comfort or get better"). Times in seconds.
nonisolated enum StormComfortTuning {
    /// A comfort arc starts when the latest arrival of the huddle has stood trembling this long (random per storm) and the earliest has trembled at least `firstTremble` (so the first scared one has shaken 6...9 s or more).
    static let delay: ClosedRange<Double> = 4.5...7.5
    static let firstTremble: Float = 6
    /// The brave one's breath (a sigh's squash curve in the storm channel) and the fade of its tremble.
    static let breath: Float = 1.5
    /// The scared one's tremble fades over this once the comforter has arrived (or `fadeLatest` after the hold was started); two scared ones hold each other and fade over `mutualFade`.
    static let scaredFade: Float = 2.0, mutualFade: Float = 2.5, fadeLatest: Float = 1.6
    /// Retries of the side-by-side emote (it needs a free side spot), the wait between them, and the walk limit of the last resort.
    static let maxTries = 6, retryEvery: Float = 1.2, walkLimit: Float = 3.0
    /// Seconds into the hold (or into the in-place calm): the one light haptic, the hearts, the comforter's chirp, the comforted one's babble.
    static let hapticAt: Float = 0.4, heartTimes: [Float] = [0.5, 2.8], voiceA: Float = 0.6, voiceB: Float = 1.2
    /// The in-place calm of the last resort takes this long.
    static let calmPlaceTime: Float = 3.0
    /// Two scared ones (not a comforter and one scared) hold each other this often; the chance that the pair sits together afterwards.
    static let mutualChance = 0.45, sitChance = 0.6
    /// A comforted Jelbie's flash flinch is this fraction of the huddle's; a small chirp now and then; the chance that a calm pair leans in again after a close flash, and the wait between two.
    static let flinchScale: Float = 0.35, calmChirp = 0.35, releanChance = 0.15, releanCool: Float = 25
    /// A finger on a trembling Jelbie this long makes the calm stick for the rest of the storm.
    static let petStick: Float = 1.5
    /// The clearing: comforted Jelbies wait this long (staggered by id) before the stretch, give up after `cheerLimit`.
    static let cheerStagger: Float = 0.5, cheerLimit: Float = 22
}

extension BlobBrain {
    /// The storm pose channel is doing something (a huddle, a flinch, a pose not yet back to neutral): the sim must not sleep.
    var stormActive: Bool { storm.isActive }
}

/// The flinch curve: 0...1, up fast, away slowly. `t` seconds after the flash.
nonisolated func stormFlinch(_ t: Float) -> Float {
    guard t >= 0 else { return 0 }
    if t < StormTuning.flinchRise { return t / StormTuning.flinchRise }
    return expf(-(t - StormTuning.flinchRise) / StormTuning.flinchFall)
}

/// The storm pose channel's values (also what the feet suites drive).
nonisolated enum StormPose {
    /// The huddle stance `t` seconds into the storm clock, `standing` seconds after he arrived, `flinch` seconds since the last flash (-1 = none).
    static func huddle(t: Float, standing: Float, phase: Float, flinch: Float, amplitude amp: Float) -> (pitch: Float, roll: Float, squash: Float) {
        let w = 2 * Float.pi * StormTuning.trembleHz
        let build = min(1, standing / 0.5)          // the tremble builds over the first half second of standing there, and swells a little now and then
        let swell = 0.75 + 0.25 * sinf(2 * .pi * 0.37 * t + phase)
        let roll = StormTuning.trembleRoll * amp * build * swell * sinf(w * t + phase)
        let k = stormFlinch(flinch)
        let sq = 1 - StormTuning.hunch * amp * build + StormTuning.trembleSquash * amp * build * sinf(1.27 * w * t + phase * 1.7) - StormTuning.flinchSquash * amp * k
        return ((StormTuning.lean * build + StormTuning.flinchPitch * k) * amp, roll, sq)
    }
}

@MainActor
final class StormReactor {
    static let shared = StormReactor()

    struct Jelly {
        let id: Int
        let brain: BlobBrain
        let sim: SoftBody
        let skinner: Skinner
    }
    struct Locks: Equatable {
        var meal = false, focus = false, focusApproach = false, bath = false, voice = false, training = false, race = false, trip = false
        var blocksAll: Bool { meal || focusApproach || bath || voice || training || race || trip }
    }
    /// `comforted` = the player's finger is on him; `arc` = he is in a comfort arc (his tremble fades, `arcs` drives the rest); `calm` = he got better and stays so for the rest of the storm (still the reactor's);
    /// `cheer` = the storm is clearing: a stretch and a happy hop, then free.
    enum Mode: Equatable { case startled, gather, huddle, comforted, shaking, scatter, arc, calm, cheer }
    enum ArcKind: Equatable { case comfort, mutual, alone, inPlace }
    enum ArcStage: Equatable { case breath, hold, holding, walkBeside, calmPlace, together, lie, done }
    /// One comfort arc: `a` is the brave one (comfort), the first one (mutual), or the lone / left-over one; `b` the scared one (-1 when alone).
    struct Arc {
        let id: Int
        let kind: ArcKind
        var a: Int, b: Int
        var stage: ArcStage = .hold
        var t: Float = 0
        /// The comforter was already calm (a friend who got better before): no breath.
        var braveCalm = false
        var emote: SocialKind = .swayHug
        var flip = false
        var tries = 0
        var retryAt: Float = 0
        /// Seconds since the emote started (-1 = not running), seconds of the hold proper (the emote's phase 2), the beats already given.
        var emoteAge: Float = -1
        var holdT: Float = 0
        var faded = false
        var hapticDone = false, voiceA = false, voiceB = false
        var hearts = 0
        var closing = false
        var wantSit = false, sitDecided = false, sitTries = 0
        var asked: Float = -1
        var walking = false
        var fallback = false
        var sighStarted = false, lieStarted = false
        var log = -1
        mutating func go(_ s: ArcStage) { stage = s; t = 0 }
    }
    /// What the tests read: what ran, when.
    struct ArcRecord {
        var kind: ArcKind
        var ids: [Int]
        var emote: SocialKind?
        var fallback = false
        var startedAt: Float
        var holdStart: Float?, holdEnd: Float?, endedAt: Float?
        var tries = 0
        var hearts = 0, haptics = 0, voices = 0
    }
    struct Member {
        var mode: Mode
        var t: Float = 0
        var slot = -1
        /// Seconds since the walk to the slot was asked (-1 = not yet), and how many times it was asked.
        var asked: Float = -1
        var tries = 0
        var flinch: Float = -1
        var faceClock: Float = 0
        var phase: Float = 0
        var inPlace = false
        var shakeAt: Float = 0
        var shook = false
        var spot = SIMD2<Float>.zero
        /// The comfort: the tremble's strength (1 = the full huddle tremble, fading to 0), the fade's rate (1/s; 0 = not fading), the breath's clock (-1 = none), the arc he is in (-1 none),
        /// "got better for the rest of the storm", seconds of the player's stroking, lying down with his eyes shut (the alone arc), seconds since the lie-down ended by itself, the clearing's step.
        var tremble: Float = 1
        var fadeRate: Float = 0
        var breathT: Float = -1
        var arc = -1
        var calm = false
        var petT: Float = 0
        var lying = false
        var lieGone: Float = 0
        var cheerStage = 0
    }

    var locks = Locks()
    /// The first shake-off of the relief (one soft haptic tick goes with it).
    var onFirstShake: (() -> Void)?
    /// The comfort arcs' beats (wired in MelonStage+Weather): hearts over a Jelbie (id), a soft chirp / babble (id, the comforter?), ONE light haptic per arc.
    var onComfortHearts: ((Int) -> Void)?
    var onComfortVoice: ((Int, Bool) -> Void)?
    var onComfortHaptic: (() -> Void)?
    /// The comfort arcs running, what has run (tests), when each Jelbie got better (the reactor's clock), the clock itself.
    /// The comfort arcs (and the come-here guard of `lateJoiners`) are on; a test switches them off to compare with the storm as it was before.
    nonisolated(unsafe) static var comfortOn = true
    /// A held body is at rest (no storm pose on it during an emote, the emote waits for rest). A test switches it off to trace round 1's hold next to this one.
    nonisolated(unsafe) static var holdAtRest = true
    private(set) var arcs: [Arc] = []
    private(set) var arcLog: [ArcRecord] = []
    private(set) var calmAt: [Int: Float] = [:]
    private(set) var clock: Float = 0
    private var arcRng = WeatherRNG(seed: 4242)
    private var arcDelay: Float = 6
    /// The storm's seed (the roll of the comfort), the same number the arcs' rng starts from.
    private var stormKey: UInt64 = 1
    /// A test pins the hold's emote (so both occur in a run of seeds); nil in the app.
    nonisolated(unsafe) static var forceEmote: SocialKind?
    /// Which side-by-side hold an arc uses: about half and half, by the storm's seed and the arc's number (splitmix64 of both).
    nonisolated static func emoteChoice(stormKey: UInt64, arc: Int) -> SocialKind {
        var z = stormKey &* 0x9E3779B97F4A7C15 &+ UInt64(arc + 1) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; z ^= z >> 31
        return (z >> 20) & 1 == 0 ? .swayHug : .cuddleLean
    }
    private var nextArc = 0
    private var planClock: Float = 0
    private var relean: (a: Int, b: Int, at: Float)?
    private var lastRelean: Float = -999
    private var shakeTicked = false
    private(set) var members: [Int: Member] = [:]
    private(set) var slots: [SIMD2<Float>] = []
    private(set) var stormOn = false
    private(set) var peakOn = false
    private(set) var huddleOn = false
    private(set) var firstCloseDone = false
    private var gatherAt: Float?
    private var noticer: Int?
    private var noticeFace: Float = 0, noticeClock: Float = 0
    private var joinClock: Float = 0
    private var replanClock: Float = 0
    private var committed: Set<Int> = []
    private var slotOf: [Int: Int] = [:]
    private var seenSleep: Set<Int> = []
    private var rng = WeatherRNG(seed: 99)
    /// Tests / the log.
    private(set) var log: [String] = []
    private(set) var replans = 0
    private var jellies: [Jelly] = []
    private var plan: StormPlan?

    init() {}
    nonisolated deinit {}

    /// The reactor's view of the room, rebuilt only when an actor or a brain changes (no array per step).
    func refresh(actors: [JellyActor]) -> [Jelly] {
        if jellies.count == actors.count, zip(jellies, actors).allSatisfy({ $0.brain === $1.brain && $0.sim === $1.sim }) { return jellies }
        jellies = actors.compactMap { a in a.brain.map { Jelly(id: a.id, brain: $0, sim: a.sim, skinner: a.skinner) } }
        return jellies
    }

    // MARK: locks

    func update(care: GameCare) {
        var l = Locks()
        l.meal = care.trayOut || care.wanted != nil || care.meal != nil || care.groupActive
        l.focus = care.focus.isActive
        l.focusApproach = care.focus.isActive && care.focus.phase == .approaching
        l.bath = care.bath.active
        l.voice = care.voice.mode.phase != .idle
        l.training = false
        l.race = care.race.active || care.raceWait != nil
        l.trip = care.tripActive || care.raceBusy
        locks = l
    }

    /// Is the player holding or petting him (a finger on him, or he is in the close-up)?
    func comforted(_ j: Jelly, care: GameCare?) -> Bool {
        if j.brain.activity == .touched || j.brain.activity == .recovering { return true }
        if let c = care, c.focus.isActive, c.focusGroup.ids.contains(j.id) { return true }
        return false
    }

    /// Can he join the storm reactions at all (not busy with something of his own)?
    func available(_ j: Jelly, care: GameCare?) -> Bool {
        let b = j.brain
        if b.reserved || b.race.active || b.volley.active || b.commanded || !b.enabled { return false }
        if let c = care, c.parkHides(j.id) { return false }
        return true
    }

    // MARK: events

    /// The storm's events of this step (WeatherBook.tick) and the plan they belong to.
    func handle(_ events: [StormEvent], plan p: StormPlan?, jellies js: [Jelly], care: GameCare?) {
        jellies = js
        if let p { plan = p }
        for e in events {
            switch e.kind {
            case .began:
                stormOn = true; peakOn = false; firstCloseDone = false; huddleOn = false; gatherAt = nil; seenSleep = []; noticer = nil
                // the comfort: a new seeded roll per storm (who is brave, which hold, how long they shake first)
                arcs = []; arcLog = []; calmAt = [:]; relean = nil; lastRelean = -999; planClock = 0
                stormKey = UInt64(max(1, Int(((plan?.peak ?? 70) * 1000).rounded())))
                var g = WeatherRNG(seed: stormKey &+ 7919)
                arcDelay = Float(g.range(StormComfortTuning.delay))
                arcRng = g
                note("storm begins")
            case .phase(let ph):
                if ph == .peak { peakOn = true }
                if ph == .clearing { peakOn = false; reliefBegin(care: care) }
            case .notice:
                notice(care: care)
            case .rumble:
                for j in js where available(j, care: care) && !j.brain.isSleeping && members[j.id] == nil && j.id != noticer && rng.next() < 0.5 { j.brain.face(.worried, hold: 1.4) }
            case .flash(let i):
                guard let s = plan?.strikes[safe: i], s.strength > 0.4 else { continue }
                flinchAll(care: care, big: s.close)
            case .thunder(let i):
                guard let s = plan?.strikes[safe: i] else { continue }
                if s.close { closeThunder(care: care) }
            case .ended:
                releaseAll(note: "storm ends")
                stormOn = false; peakOn = false; huddleOn = false
            }
        }
    }

    private func notice(care: GameCare?) {
        let cands = jellies.filter { available($0, care: care) && !$0.brain.isSleeping && !comforted($0, care: care) && $0.brain.idleState.kind == nil && !locks.blocksAll && !locks.focus }
        guard !cands.isEmpty else { return }
        let j = cands[Int(rng.next() * Double(cands.count)) % cands.count]
        noticer = j.id
        noticeFace = 9
        j.brain.commandedIdle = .window
        j.brain.face(.worried, hold: 3)
        note("\(j.id) notices at the window")
    }

    /// A flash: the huddled flinch; the others (awake, free) flinch where they stand; sleepers wobble.
    private func flinchAll(care: GameCare?, big: Bool) {
        for j in jellies {
            if j.brain.isSleeping { j.brain.jellyKick = max(j.brain.jellyKick, big ? 0.6 : 0.3); continue }
            if var m = members[j.id], m.mode == .huddle || m.mode == .gather || m.mode == .arc || m.mode == .calm {
                m.flinch = 0; members[j.id] = m
                switch m.mode {
                case .huddle: j.brain.face(.surprised, hold: 0.45)
                case .arc: if m.tremble > 0.3, !j.brain.isSocial { j.brain.face(.surprised, hold: 0.45) }
                case .calm:
                    // a comforted one only flinches a little (calmStep draws it), looks round, and now and then a small chirp: no tremble, no going back
                    if big, !m.lying, !j.brain.isSocial, j.brain.idleState.kind == nil {
                        j.brain.face(.curious, hold: 0.9)
                        if arcRng.next() < StormComfortTuning.calmChirp { onComfortVoice?(j.id, false) }
                    }
                default: break
                }
            }
            else if members[j.id] == nil, available(j, care: care), !comforted(j, care: care), j.brain.activity == .idle {
                var m = Member(mode: .startled); m.flinch = 0; m.inPlace = true
                members[j.id] = m
                j.brain.face(.surprised, hold: 0.6)
            }
        }
        if big { maybeRelean() }
    }

    /// After a close flash two calm, free friends may lean in to each other once more (a short cuddleLean, rarely).
    private func maybeRelean() {
        guard relean == nil, clock - lastRelean > StormComfortTuning.releanCool else { return }
        let calm = jellies.filter { members[$0.id]?.mode == .calm && members[$0.id]?.lying == false }
        guard calm.count >= 2, arcRng.next() < StormComfortTuning.releanChance else { return }
        relean = (a: calm[0].id, b: calm[1].id, at: clock + 1.2)
        lastRelean = clock
    }

    /// The thunder of a close strike: the first one at the peak startles everybody and starts the gather; sleepers wake grumpy.
    private func closeThunder(care: GameCare?) {
        guard peakOn, !firstCloseDone else { return }
        firstCloseDone = true
        for j in jellies {
            if j.brain.isSleeping, available(j, care: care), !seenSleep.contains(j.id) {
                seenSleep.insert(j.id)
                j.brain.sleepWake(groggy: true, fast: true)
                j.brain.face(.grumpy, hold: 2.2)
                note("\(j.id) wakes grumpy")
            }
        }
        for j in jellies where !j.brain.isSleeping && available(j, care: care) && !locks.blocksAll {
            if comforted(j, care: care) { setComforted(j); continue }
            var m = members[j.id] ?? Member(mode: .startled)
            m.mode = .startled; m.t = 0; m.flinch = 0; m.phase = Float(j.id) * 1.7
            m.inPlace = locks.focus
            members[j.id] = m
            j.brain.face(.surprised, hold: 1.0)
            if !locks.focus, case .none = j.brain.script, j.brain.pending == nil, j.brain.idleState.kind == nil { j.brain.startHopPlay(sim: j.sim, distance: 0.0001) }
        }
        gatherAt = clock + StormTuning.startleTime
        note("first close thunder: startle")
    }

    // MARK: tick

    func tick(jellies js: [Jelly], care: GameCare?, dt: Float) {
        jellies = js
        clock += dt
        if locks.blocksAll, !members.isEmpty { releaseAll(note: "locked: \(locks)"); huddleOn = false; gatherAt = nil }
        if let t = gatherAt, clock >= t {
            gatherAt = nil
            if !locks.blocksAll { beginGather(care: care) }
        }
        if huddleOn, peakOn, !locks.blocksAll {
            joinClock += dt
            if joinClock >= 0.5 { joinClock = 0; lateJoiners(care: care) }
            replanClock += dt
            if replanClock >= Lineup.period { replanClock = 0; replan(care: care) }
            planClock += dt
            if planClock >= 0.5 { planClock = 0; planArcs(care: care) }
        }
        tickArcs(care: care, dt: dt)
        tickRelean()
        if noticeFace > 0, let n = noticer, let j = jellies.first(where: { $0.id == n }) {
            noticeFace -= dt
            noticeClock += dt
            if noticeClock >= 1.3 { noticeClock = 0; if members[n] == nil, !j.brain.isSleeping { j.brain.face(.worried, hold: 1.6) } }
        }
        for j in jellies {
            guard var m = members[j.id] else { continue }
            let alive = step(&m, j, care: care, dt: dt)
            if alive { members[j.id] = m } else { members[j.id] = nil }
        }
        if !huddleOn, members.isEmpty { slots = [] }
    }

    /// One member for one step; false when he is released.
    private func step(_ m: inout Member, _ j: Jelly, care: GameCare?, dt: Float) -> Bool {
        let b = j.brain
        m.t += dt
        if m.flinch >= 0 { m.flinch += dt; if m.flinch > 0.9 { m.flinch = -1 } }
        // the stage must not let him wander off: hold the autonomous pick back like the dance does
        if m.mode != .shaking, m.mode != .scatter, m.mode != .cheer {
            b.restTimer = max(b.restTimer, 1.5)
            b.idleState.cooldown = max(b.idleState.cooldown, 1.5)
            if m.mode == .arc || m.mode == .calm { b.socialBook.cooldown = max(b.socialBook.cooldown, 2) }          // (nothing else pulls a comforted Jelbie into a social of its own either)
        }
        if b.hurry { b.hurryUpdate(dt: dt) }
        // the player has him: he stays with the player and calms (and after a stroke of `petStick` seconds the calm sticks for the rest of the storm)
        if m.mode != .shaking, m.mode != .scatter, comforted(j, care: care) {
            if m.mode != .comforted {
                setComforted(j); m.mode = .comforted; m.t = 0; m.slot = -1; slotOf[j.id] = nil; committed.remove(j.id)
                m.petT = 0; m.lying = false; m.breathT = -1; m.fadeRate = 0; m.arc = -1
                note("\(j.id) comforted")
            }
            m.petT += dt
            if m.petT >= StormComfortTuning.petStick, !m.calm { m.calm = true; m.tremble = 0; if calmAt[j.id] == nil { calmAt[j.id] = clock }; note("\(j.id) calm (the player's hand)") }
            b.storm.clear()
            m.faceClock += dt
            if m.faceClock >= 1.5 { m.faceClock = 0; b.face(.neutral, hold: 1.6) }
            return true
        }
        if m.mode == .comforted {
            m.petT = 0
            // let go again: he stays calm when the stroke was long enough; else back to the huddle while the peak lasts, else free
            if m.calm, peakOn { m.mode = .calm; m.t = 0; m.flinch = -1; return true }
            if peakOn, huddleOn, !locks.blocksAll { m.mode = .gather; m.asked = -1; m.tries = 0; m.t = 0; m.inPlace = false; members[j.id] = m; _ = assignLate(j.id, care: care); m = members[j.id] ?? m }
            else { return release(j, care: care) }
            return true
        }
        if b.isSleeping { b.storm.clear(); return release(j, care: care) }
        // a comforted one the player calls (a request, a meal coming) is released at once: the player's commands always win
        if m.mode == .calm || m.mode == .cheer, b.pending != nil || b.reserved { return release(j, care: care) }
        let amp = b.amplitude
        switch m.mode {
        case .startled:
            let k = stormFlinch(m.flinch)
            b.storm.write(pitch: StormTuning.flinchPitch * amp * k, roll: 0, squash: 1 - StormTuning.flinchSquash * amp * k)
            // a flinch where he stands (a flash before the thunder) lets go after a second; the thunder's startle waits for the gather (or the lock that cancels it)
            if m.inPlace, m.t >= 1.0, !huddleOn { return release(j, care: care) }
            if !m.inPlace, gatherAt == nil, !huddleOn, m.t >= 3 { return release(j, care: care) }
            return true
        case .gather:
            if m.inPlace || locks.focus { trembleInPlace(&m, j, dt: dt); return true }
            if m.asked < 0 {
                guard m.slot >= 0, slots.indices.contains(m.slot) else { return true }
                if b.isSocial { b.stop() }
                b.hurry = true
                b.requestNow(.come(to: slots[m.slot]))
                m.asked = 0; m.tries += 1
                b.storm.clear()
            }
            m.asked += dt
            m.faceClock += dt
            if m.faceClock >= 1.3 { m.faceClock = 0; b.face(.worried, hold: 1.6) }
            let flinchK = stormFlinch(m.flinch)
            if flinchK > 0 { b.storm.write(pitch: StormTuning.flinchPitch * 0.6 * amp * flinchK, roll: 0, squash: 1 - StormTuning.flinchSquash * 0.6 * amp * flinchK) } else { b.storm.clear() }
            let here = GameCare.floorPos(b, j.sim)
            let near = m.slot >= 0 && slots.indices.contains(m.slot) ? simd_distance(here, slots[m.slot]) : 99
            if near < Lineup.commitDistance { committed.insert(j.id) }
            let idle = b.pending == nil && b.activity == .idle && { if case .none = b.script { return true }; return false }()
            if m.asked > 0.4, idle {
                if near < 0.5 || m.tries >= 3 || m.asked > StormTuning.gatherLimit { m.mode = .huddle; m.t = 0; m.asked = -1; committed.insert(j.id); b.hurry = false }
                else { m.asked = -1 }          // stopped short (steering held him): ask again
            } else if m.asked > StormTuning.gatherLimit { m.mode = .huddle; m.t = 0; committed.insert(j.id); b.hurry = false }
            return true
        case .huddle:
            if m.inPlace || locks.focus { trembleInPlace(&m, j, dt: dt); return true }
            // a member pushed away (a mate's step-aside) walks back
            if m.slot >= 0, slots.indices.contains(m.slot), b.pending == nil, b.activity == .idle, simd_distance(GameCare.floorPos(b, j.sim), slots[m.slot]) > 0.7, m.t > 1.0 {
                m.mode = .gather; m.asked = -1; m.tries = 0; return true
            }
            trembleInPlace(&m, j, dt: dt)
            return true
        case .shaking:
            b.storm.clear()
            if !m.shook, m.t >= m.shakeAt {
                m.shook = true
                if !shakeTicked { shakeTicked = true; onFirstShake?() }
                b.commandedIdle = .shake
                b.face(.happy, hold: 2.6)
            }
            if m.t >= m.shakeAt + StormTuning.shakeTime { m.mode = .scatter; m.t = 0; m.asked = -1 }
            return true
        case .scatter:
            if m.asked < 0 {
                m.asked = 0
                b.hurry = false
                b.requestNow(.goTo(m.spot))
            }
            m.asked += dt
            let idle = b.pending == nil && b.activity == .idle && { if case .none = b.script { return true }; return false }()
            if (m.asked > 0.4 && idle) || m.asked > StormTuning.scatterTime { return release(j, care: care) }
            return true
        case .arc:
            arcPose(&m, j, dt: dt)
            return true
        case .calm:
            calmStep(&m, j, dt: dt)
            return true
        case .cheer:
            return cheerStep(&m, j, care: care)
        default:
            return true
        }
    }

    /// The huddle stance: hunched, a fine tremble, worried eyes, the flinch on top.
    private func trembleInPlace(_ m: inout Member, _ j: Jelly, dt: Float) {
        let b = j.brain
        m.faceClock += dt
        if m.faceClock >= 1.3 { m.faceClock = 0; b.face(.worried, hold: 1.6) }
        let p = StormPose.huddle(t: clock, standing: m.t, phase: m.phase, flinch: m.flinch, amplitude: b.amplitude)
        b.storm.write(pitch: p.pitch, roll: p.roll, squash: p.squash)
        b.storm.dancing = false
    }

    private func setComforted(_ j: Jelly) {
        j.brain.hurry = false
        j.brain.storm.clear()
        j.brain.face(.neutral, hold: 1.6)
    }

    // MARK: comfort

    private func jelly(_ id: Int) -> Jelly? { jellies.first { $0.id == id } }

    private func rec(_ arc: Arc, _ f: (inout ArcRecord) -> Void) { if arcLog.indices.contains(arc.log) { f(&arcLog[arc.log]) } }

    /// A comfort-arc member's pose: the huddle tremble at its fading strength (none once the fade is through), the brave one's breath, the small flinch. Never a roll while a side-by-side emote holds him (the contact).
    private func arcPose(_ m: inout Member, _ j: Jelly, dt: Float) {
        let b = j.brain, S = StormComfortTuning.self
        if m.fadeRate > 0 {
            m.tremble = max(0, m.tremble - m.fadeRate * dt)
            if m.tremble <= 0, !m.calm { m.calm = true; if calmAt[j.id] == nil { calmAt[j.id] = clock }; note("\(j.id) calm") }
        }
        let amp = b.amplitude
        let free = b.idleState.kind == nil && !b.isSocial
        var pose: (pitch: Float, roll: Float, squash: Float) = (0, 0, 1)
        m.faceClock += dt
        if m.tremble > 0.001 {
            if m.faceClock >= 1.3 { m.faceClock = 0; if free { b.face(m.tremble > 0.5 ? .worried : .neutral, hold: 1.6) } }
            pose = StormPose.huddle(t: clock, standing: m.t, phase: m.phase, flinch: m.flinch, amplitude: amp * m.tremble)
        } else {
            if m.faceClock >= 1.5 { m.faceClock = 0; if free { b.face(.neutral, hold: 1.6) } }
            let s = S.flinchScale * amp * stormFlinch(m.flinch)
            pose = (StormTuning.flinchPitch * s, 0, 1 - StormTuning.flinchSquash * s)
        }
        if m.breathT >= 0 {          // a sigh's squash curve (BlobBrain+Flourish runSigh) in the storm channel: up a little, then the slump
            m.breathT += dt
            let u = m.breathT, L = S.breath
            let inhale: Float = u < 0.6 ? sinf(.pi * u / 0.6) : 0
            let exhale: Float = u >= 0.6 ? sinf(.pi * min(1, (u - 0.6) / (L - 0.6))) : 0
            pose.squash *= 1 + 0.035 * inhale - 0.05 * exhale
            pose.pitch += 0.06 * exhale
            if u > L { m.breathT = -1 }
        }
        // a side-by-side emote has him (or is forming): the contact settle places a body that is at rest, so nothing of the storm is on it: no tremble, no flinch, no breath. A flash during the hold is the face's only (flinchAll).
        if b.isSocial, Self.holdAtRest { pose = (0, 0, 1); m.flinch = -1; m.breathT = -1 } else if b.isSocial { pose.roll = 0 }
        b.storm.write(pitch: pose.pitch, roll: pose.roll, squash: pose.squash)
        b.storm.dancing = false
    }

    /// A Jelbie who got better: no tremble for the rest of the storm, only the small flinch; the lying one stays down (eyes shut) however long the peak lasts.
    private func calmStep(_ m: inout Member, _ j: Jelly, dt: Float) {
        let b = j.brain
        if b.isSocial, Self.holdAtRest { m.flinch = -1 }          // (a lean-in or a sit together has him: a flash moves nothing of the held body)
        let k = stormFlinch(m.flinch)
        if k > 0 {
            let s = StormComfortTuning.flinchScale * b.amplitude * k
            b.storm.write(pitch: StormTuning.flinchPitch * s, roll: 0, squash: 1 - StormTuning.flinchSquash * s)
        } else { b.storm.clear() }
        b.storm.dancing = false
        if m.lying {
            if b.idleState.kind == .floorNapFlop {
                if b.idleState.phase == 2 { b.idleState.hold = max(b.idleState.hold, b.idleState.phaseT + 3) }          // (the flop's own 3...6 s hold never runs out while the storm lasts)
                m.lieGone = 0
            } else {
                m.lieGone += dt
                if m.lieGone > 1.5, b.commandedIdle == nil, b.pending == nil, b.scriptIsNone, !b.isSocial { b.commandedIdle = .floorNapFlop; m.lieGone = -1.5 }
            }
        } else {
            m.faceClock += dt
            if m.faceClock >= 1.5 { m.faceClock = 0; if b.idleState.kind == nil, !b.isSocial { b.face(.neutral, hold: 1.6) } }
        }
    }

    /// The clearing, for a comforted one: up again (the flop's push-up has its stretch) or a stretch, then a small happy hop, then free.
    private func cheerStep(_ m: inout Member, _ j: Jelly, care: GameCare?) -> Bool {
        let b = j.brain
        b.storm.clear()
        if m.t < m.shakeAt { return true }
        if m.t > StormComfortTuning.cheerLimit { return release(j, care: care) }
        switch m.cheerStage {
        case 0:
            if b.idleState.kind == .floorNapFlop {
                b.idleState.hold = 0
                m.cheerStage = 1; b.face(.happy, hold: 2)
            } else if b.social == nil, b.idleState.kind == nil, b.commandedIdle == nil, b.pending == nil, b.scriptIsNone {
                b.commandedIdle = .stretch; b.face(.happy, hold: 2.2)
                m.cheerStage = 1
            }
        case 1:
            if b.social == nil, b.idleState.kind == nil, b.commandedIdle == nil {
                b.commandedIdle = .joy; b.face(.joyArc, hold: 1.4)
                m.cheerStage = 2
            }
        default:
            if b.idleState.kind == nil, b.commandedIdle == nil { return release(j, care: care) }
        }
        return true
    }

    /// How brave he is this storm: a little by character (Moss calm, Teddy cuddly, Pip excitable), a seeded roll on top. (There is no stored courage trait.)
    private func courage(_ j: Jelly) -> Float {
        let base: Float
        switch j.brain.personalityKey {
        case .daisy: base = 0.30
        case .ears: base = 0.15
        case .none: base = 0.05
        case .spines: base = -0.10
        default: base = 0
        }
        return base + Float(arcRng.next()) * 0.45
    }

    /// The nearest calm, free friend (not in an arc, not lying, free for a social) within reach of `id`.
    private func nearestCalmFree(to id: Int) -> Int? {
        guard let t = jelly(id) else { return nil }
        let tp = GameCare.floorPos(t.brain, t.sim)
        let cands = jellies.filter { j in
            guard let m = members[j.id], m.mode == .calm, m.arc < 0, !m.lying else { return false }
            return j.brain.socialFree && simd_distance(GameCare.floorPos(j.brain, j.sim), tp) < 4.5
        }
        return cands.min { simd_distance(GameCare.floorPos($0.brain, $0.sim), tp) < simd_distance(GameCare.floorPos($1.brain, $1.sim), tp) }?.id
    }

    /// Twice a second during the peak: who has trembled long enough gets an arc. One scared: a calm friend comes, else (nobody else here) it sighs and lies down, else it calms where it stands.
    /// Two or more: the bravest comforts the most scared (or, for two, now and then they hold each other); the rest pair up; a left-over one calms beside them.
    private func planArcs(care: GameCare?) {
        guard Self.comfortOn, peakOn, huddleOn, !locks.blocksAll else { return }
        let S = StormComfortTuning.self
        let huddlers = jellies.filter { members[$0.id]?.mode == .huddle && !$0.brain.isSleeping }
        guard !huddlers.isEmpty else { return }
        let ready = huddlers.filter { (members[$0.id]?.t ?? 0) >= arcDelay }
        guard !ready.isEmpty else { return }
        let oldest = ready.map { members[$0.id]?.t ?? 0 }.max() ?? 0
        guard oldest >= S.firstTremble else { return }
        // somebody is still on the way or only just arrived: wait a few seconds so the pair / the trio is planned together
        let stillComing = members.values.contains { $0.mode == .gather || $0.mode == .startled } || ready.count < huddlers.count
        if stillComing, oldest < S.firstTremble + 3 { return }
        var score: [Int: Float] = [:]
        for j in ready { score[j.id] = courage(j) }
        var pool = ready.map(\.id).sorted { (score[$0] ?? 0) > (score[$1] ?? 0) }          // bravest first
        if locks.focus { for id in pool { startArc(.inPlace, a: id) }; return }          // (a close-up: nobody walks, everybody calms where he stands)
        if pool.count == 1 {
            let id = pool[0]
            if let c = nearestCalmFree(to: id) { startArc(.comfort, a: c, b: id, braveCalm: true) }
            else if members.count > 1 { if (members[id]?.t ?? 0) >= arcDelay + 2.5 { startArc(.inPlace, a: id) } }
            else { startArc(.alone, a: id) }
            return
        }
        if pool.count == 2, arcRng.next() < S.mutualChance { startArc(.mutual, a: pool[0], b: pool[1]); return }
        let brave = pool.removeFirst(), scared = pool.removeLast()
        startArc(.comfort, a: brave, b: scared)
        while pool.count >= 2 { let x = pool.removeFirst(), y = pool.removeFirst(); startArc(.mutual, a: x, b: y) }
        if let last = pool.first { startArc(.inPlace, a: last) }
    }

    private func startArc(_ kind: ArcKind, a: Int, b: Int = -1, braveCalm: Bool = false) {
        let S = StormComfortTuning.self
        var arc = Arc(id: nextArc, kind: kind, a: a, b: b)
        nextArc += 1
        arc.braveCalm = braveCalm
        arc.emote = Self.forceEmote ?? Self.emoteChoice(stormKey: stormKey, arc: arc.id)
        switch kind {
        case .comfort: arc.stage = braveCalm ? .hold : .breath
        case .mutual: arc.stage = .hold
        case .alone: arc.stage = .breath
        case .inPlace: arc.stage = .calmPlace
        }
        for id in [a, b] where id >= 0 { members[id]?.mode = .arc; members[id]?.arc = arc.id; members[id]?.faceClock = 0 }
        if kind == .comfort, !braveCalm { members[a]?.breathT = 0; members[a]?.fadeRate = 1 / S.breath }
        arcLog.append(ArcRecord(kind: kind, ids: b >= 0 ? [a, b] : [a], emote: nil, startedAt: clock))
        arc.log = arcLog.count - 1
        arcs.append(arc)
        note("comfort arc \(kind): \(a)" + (b >= 0 ? " + \(b)" : ""))
    }

    /// The player's hand or call on one of them ends the arc; everything else is the arcs' own sequence.
    private func tickArcs(care: GameCare?, dt: Float) {
        guard !arcs.isEmpty else { return }
        var finished: Set<Int> = []
        for idx in arcs.indices {
            var arc = arcs[idx]
            arc.t += dt
            guard let ja = jelly(arc.a), members[arc.a] != nil else { cancelArc(arc, why: "a member is gone"); finished.insert(arc.id); continue }
            var jb: Jelly?
            if arc.b >= 0 {
                guard let x = jelly(arc.b), members[arc.b] != nil else { cancelArc(arc, why: "a member is gone"); finished.insert(arc.id); continue }
                jb = x
            }
            if comforted(ja, care: care) || (jb.map { comforted($0, care: care) } ?? false) { cancelArc(arc, why: "the player has one"); finished.insert(arc.id); continue }
            if taken(ja, arc) || (jb.map { taken($0, arc) } ?? false) { dropArc(arc, why: "the player called one"); finished.insert(arc.id); continue }
            advance(&arc, ja, jb, dt: dt)
            if arc.stage == .done { finishArc(arc); finished.insert(arc.id) } else { arcs[idx] = arc }
        }
        if !finished.isEmpty { arcs.removeAll { finished.contains($0.id) } }
    }

    /// Something of the player's (a request, a meal coming, a race) has one of them: the arc ends for both at once.
    private func taken(_ j: Jelly, _ arc: Arc) -> Bool {
        let b = j.brain
        if b.reserved || b.race.active || b.volley.active || !b.enabled { return true }
        if b.pending != nil, !(arc.walking && j.id == arc.a) { return true }
        return false
    }

    private func advance(_ arc: inout Arc, _ ja: Jelly, _ jb: Jelly?, dt: Float) {
        let S = StormComfortTuning.self
        switch arc.kind {
        case .inPlace:
            calmPlace(&arc, dt: dt)
        case .alone:
            switch arc.stage {
            case .breath:
                // the real sigh (4.3 s) and the fade of the tremble with it; then down on its belly, eyes shut
                if !arc.sighStarted {
                    arc.sighStarted = true
                    ja.brain.hurry = false
                    ja.brain.commandedIdle = .sigh
                    members[arc.a]?.fadeRate = 1 / S.breath
                }
                let sighDone = ja.brain.idleState.kind == nil && ja.brain.commandedIdle == nil
                if (arc.t >= S.breath && sighDone) || arc.t > 8 { arc.go(.lie) }
            case .lie:
                if !arc.lieStarted {
                    arc.lieStarted = true
                    if ja.brain.isSocial { ja.brain.stop() }
                    ja.brain.commandedIdle = .floorNapFlop
                }
                if ja.brain.idleState.kind == .floorNapFlop, ja.brain.idleState.phase >= 2 {
                    arc.hapticDone = true
                    rec(arc) { $0.holdStart = clock; $0.haptics += 1; $0.voices += 1 }
                    onComfortHaptic?(); onComfortVoice?(arc.a, false)
                    arc.stage = .done
                } else if arc.t > 6 { arc.fallback = true; arc.go(.calmPlace) }
            case .calmPlace:
                calmPlace(&arc, dt: dt)
            default:
                arc.stage = .done
            }
        case .comfort, .mutual:
            guard let jb else { arc.stage = .done; return }
            switch arc.stage {
            case .breath:
                if arc.t >= S.breath + 0.15 { arc.go(.hold); arc.retryAt = clock }
            case .hold:
                // the scared one's tremble (both, for two scared ones) fades BEFORE the emote starts: a pose on the body during the hold broke the contact gap (round 1: -0.8...-2.3 cm)
                for id in (arc.kind == .mutual ? [arc.a, arc.b] : [arc.b]) where (members[id]?.tremble ?? 0) > 0 && (members[id]?.fadeRate ?? 0) == 0 {
                    members[id]?.fadeRate = 1 / (arc.kind == .mutual ? S.mutualFade : S.scaredFade)
                }
                arc.faded = true
                if (members[arc.a]?.tremble ?? 0) > 0.02 || (members[arc.b]?.tremble ?? 0) > 0.02 { return }
                // both bodies fully at rest before the emote forms (like a plain start): the tremble is exactly zero, no flinch or breath is on them, the storm channel is neutral
                if Self.holdAtRest { for id in [arc.a, arc.b] { members[id]?.tremble = 0 } }
                if Self.holdAtRest, !(ja.brain.storm.isNeutral && jb.brain.storm.isNeutral) || (members[arc.a]?.flinch ?? -1) >= 0 || (members[arc.b]?.flinch ?? -1) >= 0 || (members[arc.a]?.breathT ?? -1) >= 0 { return }
                if clock < arc.retryAt { return }
                if arc.tries >= S.maxTries { arc.fallback = true; arc.go(.walkBeside); return }
                ja.brain.hurry = false; jb.brain.hurry = false
                let (i, o) = arc.flip ? (jb, ja) : (ja, jb)
                if i.brain.socialFree, o.brain.socialFree, i.brain.socialStart(arc.emote, with: o.brain, i.sim) {
                    arc.go(.holding); arc.emoteAge = 0
                    rec(arc) { $0.emote = arc.emote; $0.tries = arc.tries }
                } else {
                    arc.tries += 1; arc.retryAt = clock + S.retryEvery
                    if arc.tries == 2 { arc.emote = arc.emote == .swayHug ? .cuddleLean : .swayHug }
                    if arc.tries == 4 { arc.flip.toggle() }
                }
            case .holding:
                arc.emoteAge += dt
                let sess = ja.brain.social ?? jb.brain.social
                let ph = sess?.phase ?? 0
                if !arc.faded, ph >= 1 || arc.emoteAge >= S.fadeLatest {          // the scared one's tremble fades as the friend arrives (two scared ones: both)
                    arc.faded = true
                    if arc.kind == .mutual { members[arc.a]?.fadeRate = 1 / S.mutualFade; members[arc.b]?.fadeRate = 1 / S.mutualFade }
                    else { members[arc.b]?.fadeRate = 1 / S.scaredFade }
                }
                if ph >= 2 {
                    if arc.holdT == 0 { rec(arc) { $0.holdStart = clock } }
                    arc.holdT += dt
                    comfortBeats(&arc)
                }
                let over = ja.brain.social == nil && jb.brain.social == nil
                if over, arc.emoteAge > 0.3 {
                    if arc.holdT < 1.0 {          // it did not hold (a Jelbie was taken away for a moment): again
                        arc.tries += 1; arc.retryAt = clock + S.retryEvery; arc.emoteAge = -1; arc.holdT = 0
                        arc.go(.hold)
                    } else { rec(arc) { $0.holdEnd = clock }; arc.go(.together) }
                } else if arc.emoteAge > 14 {
                    ja.brain.stop(); jb.brain.stop()
                    rec(arc) { $0.holdEnd = clock }
                    arc.go(.together)
                }
            case .walkBeside:
                // the last resort: the comforter walks to a spot beside the scared one and they calm side by side where they stand
                ja.brain.hurry = false
                if arc.asked < 0 {
                    guard let spot = besideSpot(of: jb, for: ja) else { arc.go(.calmPlace); return }
                    if ja.brain.isSocial { ja.brain.stop() }
                    ja.brain.requestNow(.come(to: spot))
                    arc.asked = 0; arc.walking = true
                }
                arc.asked += dt
                let idle = ja.brain.pending == nil && ja.brain.activity == .idle && ja.brain.scriptIsNone
                if (arc.asked > 0.4 && idle) || arc.asked > S.walkLimit { arc.walking = false; arc.go(.calmPlace) }
            case .calmPlace:
                calmPlace(&arc, dt: dt)
            case .together:
                // they stay together and calm; now and then they sit side by side a while
                if !arc.sitDecided { arc.sitDecided = true; arc.wantSit = !arc.closing && arcRng.next() < S.sitChance; arc.retryAt = clock + 0.8 }
                if arc.wantSit, peakOn, clock >= arc.retryAt {
                    if ja.brain.socialFree, jb.brain.socialFree, ja.brain.socialStart(.sitTogether, with: jb.brain, ja.sim) { arc.wantSit = false; arc.stage = .done; return }
                    arc.sitTries += 1; arc.retryAt = clock + 1.0
                    if arc.sitTries >= 3 { arc.wantSit = false }
                }
                if !arc.wantSit || arc.t > 6 { arc.stage = .done }
            default:
                arc.stage = .done
            }
        }
    }

    /// The in-place calm (a close-up, a left-over one, the last resort): the tremble fades, hearts, a chirp, one light haptic; nobody walks.
    private func calmPlace(_ arc: inout Arc, dt: Float) {
        let S = StormComfortTuning.self
        if !arc.faded {
            arc.faded = true
            for id in [arc.a, arc.b] where id >= 0 { if (members[id]?.tremble ?? 0) > 0 { members[id]?.fadeRate = 1 / S.mutualFade } }
            if arc.kind == .alone { arc.hearts = S.heartTimes.count }          // (a lone one has nobody to hug: no hearts)
            rec(arc) { $0.fallback = true; $0.holdStart = clock }
        }
        arc.holdT += dt
        comfortBeats(&arc)
        if arc.t >= S.calmPlaceTime { rec(arc) { $0.holdEnd = clock }; arc.stage = .done }
    }

    /// The beats of a hold (or an in-place calm), by the seconds of it: ONE light haptic, hearts over both, the comforter's chirp, then the comforted one's babble.
    private func comfortBeats(_ arc: inout Arc) {
        let S = StormComfortTuning.self
        let t = arc.holdT
        if !arc.hapticDone, t >= S.hapticAt { arc.hapticDone = true; rec(arc) { $0.haptics += 1 }; onComfortHaptic?() }
        if arc.hearts < S.heartTimes.count, t >= S.heartTimes[arc.hearts] {
            arc.hearts += 1
            if arc.kind != .alone { rec(arc) { $0.hearts += 1 }; onComfortHearts?(arc.a); if arc.b >= 0 { onComfortHearts?(arc.b) } }
        }
        if !arc.voiceA, t >= S.voiceA { arc.voiceA = true; rec(arc) { $0.voices += 1 }; onComfortVoice?(arc.a, arc.kind == .comfort) }
        if !arc.voiceB, arc.b >= 0, t >= S.voiceB { arc.voiceB = true; rec(arc) { $0.voices += 1 }; onComfortVoice?(arc.b, false) }
    }

    /// A floor spot a gap from `target` that the resolver leaves alone and nobody else stands on; the one nearest to `walker`.
    private func besideSpot(of target: Jelly, for walker: Jelly) -> SIMD2<Float>? {
        let gap = MelonController.jellyGap * StormTuning.gapFactor
        let tpos = GameCare.floorPos(target.brain, target.sim)
        let here = GameCare.floorPos(walker.brain, walker.sim)
        let others = jellies.filter { $0.id != target.id && $0.id != walker.id }.map { GameCare.floorPos($0.brain, $0.sim) }
        var best: (d: Float, p: SIMD2<Float>)?
        for k in 0..<16 {
            let ang = Float(k) * (.pi / 8)
            let p = tpos + SIMD2(cosf(ang), sinf(ang)) * gap
            let q = walker.brain.resolve(SIMD3(p.x, 0, p.y), walker.brain.footprint)
            guard simd_distance(SIMD2(q.x, q.z), p) < 0.05, others.allSatisfy({ simd_distance($0, p) >= gap * 0.99 }) else { continue }
            let d = simd_distance(here, p)
            if best == nil || d < best!.d { best = (d, p) }
        }
        return best?.p
    }

    /// The arc is over: both stay calm (the reactor's, no tremble) until the clearing, or cheer at once when the storm is already clearing.
    private func finishArc(_ arc: Arc) {
        for id in [arc.a, arc.b] where id >= 0 {
            guard var m = members[id] else { continue }
            m.arc = -1; m.breathT = -1; m.fadeRate = 0; m.tremble = 0; m.calm = true
            if calmAt[id] == nil { calmAt[id] = clock }
            if arc.kind == .alone, !arc.closing, arc.stage == .done, !arc.fallback { m.lying = true; m.lieGone = 0 }
            if arc.closing { m.mode = .cheer; m.t = 0; m.cheerStage = 0; m.shakeAt = StormComfortTuning.cheerStagger * Float(id % 3) } else { m.mode = .calm }
            members[id] = m
        }
        rec(arc) { $0.endedAt = clock }
    }

    /// The arc stops (the player has one of them, the clearing came early): a Jelbie who had already calmed stays calm, a still scared one goes back to the huddle (and is planned again).
    private func cancelArc(_ arc: Arc, why: String) {
        for id in [arc.a, arc.b] where id >= 0 {
            guard var m = members[id] else { continue }
            if let j = jelly(id), let k = j.brain.socialKind, k == .swayHug || k == .cuddleLean { j.brain.stop() }
            m.arc = -1; m.breathT = -1; m.fadeRate = 0
            if m.calm { m.mode = .calm; m.tremble = 0 } else { m.mode = .huddle; m.tremble = 1; m.t = max(m.t, arcDelay) }
            members[id] = m
        }
        rec(arc) { $0.endedAt = clock }
        note("comfort arc cancelled: \(why)")
    }

    /// The player called one of them: both are free at once (nothing of the storm or the emote is left on them).
    private func dropArc(_ arc: Arc, why: String) {
        for id in [arc.a, arc.b] where id >= 0 {
            if let j = jelly(id) {
                letGo(j, lying: members[id]?.lying ?? false)
                if j.brain.isSocial { j.brain.stop() }
            }
            members[id] = nil; committed.remove(id); slotOf[id] = nil
        }
        rec(arc) { $0.endedAt = clock }
        note("comfort arc dropped: \(why)")
    }

    /// A calm pair that flinched together leans in once more (a short cuddleLean): only when both are free for it.
    private func tickRelean() {
        guard let r = relean, clock >= r.at else { return }
        relean = nil
        guard peakOn, !locks.blocksAll, let ja = jelly(r.a), let jb = jelly(r.b),
              members[r.a]?.mode == .calm, members[r.b]?.mode == .calm, members[r.a]?.lying == false, members[r.b]?.lying == false,
              ja.brain.socialFree, jb.brain.socialFree else { return }
        _ = ja.brain.socialStart(.cuddleLean, with: jb.brain, ja.sim)
    }

    /// His storm pose and speed off him; the lying one gets up (his hold ends, and the voice command flag that kept the meal from lifting him is dropped).
    private func letGo(_ j: Jelly, lying: Bool) {
        let b = j.brain
        b.storm.clear()
        b.hurry = false
        if lying, b.idleState.kind == .floorNapFlop { b.idleState.hold = 0; b.commanded = false }
    }

    /// The comfort sound the stage and the tests share: the comforter's happy chirp, the comforted one's babble (the existing chirp / babble voice set, deterministic: no chance roll).
    static func playComfortVoice(on hub: AudioHub = .shared, id: Int, comforter: Bool, x: Float) {
        hub.chirp(jelly: id, comforter ? .happy : .babble, x: x, src: "storm")
    }

    // MARK: the huddle

    private func beginGather(care: GameCare?) {
        let ids = jellies.filter { j in
            guard available(j, care: care), !j.brain.isSleeping, !comforted(j, care: care) else { return false }
            return true
        }.map(\.id)
        huddleOn = true
        committed = []; slotOf = [:]; replans = 0
        guard !ids.isEmpty else { note("huddle: nobody free"); return }
        for id in ids {
            var m = members[id] ?? Member(mode: .gather)
            m.mode = .gather; m.t = 0; m.asked = -1; m.tries = 0; m.inPlace = locks.focus; m.phase = Float(id) * 1.7
            members[id] = m
        }
        if locks.focus {
            for id in ids { members[id]?.mode = .huddle; members[id]?.inPlace = true }
            note("huddle in place (close-up on)"); return
        }
        planCluster(ids: ids, care: care)
        note("huddle begins: \(ids.count) at \(slots.map { String(format: "(%.1f,%.1f)", $0.x, $0.y) })")
    }

    /// The cluster slots for `ids` and who takes which.
    private func planCluster(ids: [Int], care: GameCare?) {
        let js = ids.compactMap { id in jellies.first { $0.id == id } }
        guard !js.isEmpty else { return }
        let floors = js.map { GameCare.floorPos($0.brain, $0.sim) }
        let others = jellies.filter { !ids.contains($0.id) }.map { GameCare.floorPos($0.brain, $0.sim) }
        let gap = MelonController.jellyGap * StormTuning.gapFactor
        let centroid = floors.reduce(SIMD2<Float>.zero, +) / Float(floors.count)
        let probe = js[0].brain
        // the cluster centre: the nearest to where they are such that every slot is a floor the resolver leaves alone (walls, decor) and clear of the others
        var offsets: [SIMD2<Float>] = [.zero]
        for r in stride(from: Float(0.5), through: 3.5, by: 0.5) { for k in 0..<12 { let a = Float(k) * (.pi / 6); offsets.append(SIMD2(cosf(a), sinf(a)) * r) } }
        var chosen: [SIMD2<Float>]?
        for off in offsets {
            let c = centroid + off
            let s = Self.clusterSlots(centre: c, count: js.count, gap: gap)
            let ok = s.allSatisfy { p in
                let q = probe.resolve(SIMD3(p.x, 0, p.y), probe.footprint)
                return simd_distance(SIMD2(q.x, q.z), p) < 0.05 && others.allSatisfy { simd_distance($0, p) >= gap }
            }
            if ok { chosen = s; break }
        }
        let s = chosen ?? Self.clusterSlots(centre: centroid, count: js.count, gap: gap).map { p in let q = probe.resolve(SIMD3(p.x, 0, p.y), probe.footprint); return SIMD2(q.x, q.z) }
        slots = s
        let plan = Lineup.best(from: floors, slots: s, locked: [Int?](repeating: nil, count: js.count), centre: nil, bystanders: others)
        for (i, j) in js.enumerated() { slotOf[j.id] = plan[i]; members[j.id]?.slot = plan[i] }
    }

    /// Slots in a tight cluster: `count` points `gap` apart round `centre` (one: the centre; two: side by side; more: a regular polygon, the first at the back).
    nonisolated static func clusterSlots(centre c: SIMD2<Float>, count n: Int, gap: Float) -> [SIMD2<Float>] {
        switch n {
        case 0: return []
        case 1: return [c]
        case 2: return [c + SIMD2(-gap / 2, 0), c + SIMD2(gap / 2, 0)]
        default:
            let r = gap / (2 * sinf(.pi / Float(n)))
            return (0..<n).map { k in let a = -Float.pi / 2 + 2 * .pi * Float(k) / Float(n); return c + SIMD2(cosf(a), sinf(a)) * r }
        }
    }

    /// Re-read a few times a second until each commits (within `Lineup.commitDistance`), like the close-up row.
    private func replan(care: GameCare?) {
        let ids = members.filter { $0.value.mode == .gather && !$0.value.inPlace && $0.value.slot >= 0 }.map(\.key).sorted()
        guard ids.count > 1, slots.count >= ids.count else { return }
        let all = members.filter { ($0.value.mode == .gather || $0.value.mode == .huddle) && !$0.value.inPlace && $0.value.slot >= 0 }.map(\.key).sorted()
        let js = all.compactMap { id in jellies.first { $0.id == id } }
        guard js.count == all.count else { return }
        let floors = js.map { GameCare.floorPos($0.brain, $0.sim) }
        for (i, id) in all.enumerated() where !committed.contains(id) {
            if let s = slotOf[id], slots.indices.contains(s), simd_distance(floors[i], slots[s]) < Lineup.commitDistance { committed.insert(id) }
        }
        guard committed.count < all.count else { return }
        let bystanders = jellies.filter { !all.contains($0.id) }.map { GameCare.floorPos($0.brain, $0.sim) }
        let plan = Lineup.best(from: floors, slots: slots, locked: all.map { committed.contains($0) ? slotOf[$0] : nil }, centre: nil, bystanders: bystanders, current: all.map { slotOf[$0] ?? -1 })
        for (i, id) in all.enumerated() where slotOf[id] != plan[i] && !committed.contains(id) {
            slotOf[id] = plan[i]; members[id]?.slot = plan[i]; replans += 1
            if members[id]?.mode == .gather, members[id]?.asked ?? -1 >= 0, let b = jellies.first(where: { $0.id == id })?.brain {
                b.requestNow(.come(to: slots[plan[i]])); members[id]?.asked = 0
            }
        }
    }

    /// A Jelbie who becomes free during the peak (woke up, was let go by the player, finished a move) joins the cluster beside it.
    private func lateJoiners(care: GameCare?) {
        guard !locks.focus else { return }
        for j in jellies where members[j.id] == nil && available(j, care: care) && !j.brain.isSleeping && !comforted(j, care: care) && j.brain.idleState.kind != .sleep && (!Self.comfortOn || (j.brain.pending == nil && j.brain.activity != .coming)) {          // (a request of the player's is his own until it is done: a Jelbie let go by a come-here does not rejoin the huddle mid-walk)
            var m = Member(mode: .gather); m.phase = Float(j.id) * 1.7
            members[j.id] = m
            if !assignLate(j.id, care: care) { members[j.id] = nil }
        }
    }

    /// A spot beside the cluster for a latecomer (a gap from everybody, a floor the resolver accepts); appended to `slots`.
    private func assignLate(_ id: Int, care: GameCare?) -> Bool {
        guard let j = jellies.first(where: { $0.id == id }) else { return false }
        let gap = MelonController.jellyGap * StormTuning.gapFactor
        let anchors = jellies.filter { members[$0.id] != nil && $0.id != id && members[$0.id]?.slot ?? -1 >= 0 }.map { GameCare.floorPos($0.brain, $0.sim) }
        let everyone = jellies.filter { $0.id != id }.map { GameCare.floorPos($0.brain, $0.sim) }
        let here = GameCare.floorPos(j.brain, j.sim)
        guard !anchors.isEmpty else {
            // nobody huddles yet: he trembles where he stands
            members[id]?.inPlace = true; members[id]?.mode = .huddle; members[id]?.slot = -1
            return true
        }
        var best: (d: Float, p: SIMD2<Float>)?
        for a in anchors { for k in 0..<16 {
            let ang = Float(k) * (.pi / 8)
            let p = a + SIMD2(cosf(ang), sinf(ang)) * gap
            let q = j.brain.resolve(SIMD3(p.x, 0, p.y), j.brain.footprint)
            guard simd_distance(SIMD2(q.x, q.z), p) < 0.05, everyone.allSatisfy({ simd_distance($0, p) >= gap * 0.99 }) else { continue }
            let d = simd_distance(here, p)
            if best == nil || d < best!.d { best = (d, p) }
        } }
        guard let b = best else {
            members[id]?.inPlace = true; members[id]?.mode = .huddle; members[id]?.slot = -1
            return true
        }
        slots.append(b.p)
        members[id]?.slot = slots.count - 1; slotOf[id] = slots.count - 1
        members[id]?.mode = .gather; members[id]?.asked = -1; members[id]?.inPlace = false
        return true
    }

    // MARK: relief

    private func reliefBegin(care: GameCare?) {
        gatherAt = nil
        shakeTicked = false
        // the comfort: a hold that is on finishes (then they cheer); an arc that has not got there is cancelled (the one who had calmed stays calm, a still scared one gets today's relief)
        for i in arcs.indices {
            if arcs[i].stage == .holding || arcs[i].stage == .together { arcs[i].closing = true }
            else { cancelArc(arcs[i], why: "the storm is clearing"); arcs[i].stage = .done }
        }
        arcs.removeAll { $0.stage == .done }
        let ids = members.keys.sorted()
        guard !ids.isEmpty else { huddleOn = false; return }
        var centre = SIMD2<Float>.zero, n: Float = 0
        for id in ids { if let j = jellies.first(where: { $0.id == id }) { centre += GameCare.floorPos(j.brain, j.sim); n += 1 } }
        centre /= max(n, 1)
        for (k, id) in ids.enumerated() {
            guard var m = members[id], let j = jellies.first(where: { $0.id == id }) else { continue }
            if m.mode == .comforted { j.brain.face(.happy, hold: 2.0); continue }
            if m.mode == .arc { continue }          // (a hold that is on: finishArc sends them to cheer)
            if m.mode == .calm {          // comforted: no frantic shake-off, a stretch and a happy hop (cheerStep), then free
                m.mode = .cheer; m.t = 0; m.cheerStage = 0; m.shakeAt = StormComfortTuning.cheerStagger * Float(k); m.flinch = -1
                members[id] = m
                continue
            }
            j.brain.hurry = false
            m.mode = .shaking; m.t = 0; m.shook = false; m.shakeAt = Float(k) * StormTuning.shakeStagger; m.inPlace = false
            // the scatter: away from the cluster, each in his own direction, onto floor the resolver accepts
            let here = GameCare.floorPos(j.brain, j.sim)
            var dir = here - centre
            if simd_length(dir) < 0.05 { let a = Float(k) * 2.1; dir = SIMD2(cosf(a), sinf(a)) }
            dir = simd_normalize(dir)
            var spot = here
            for r: Float in [2.4, 1.9, 1.4, 1.0] {
                let p = here + dir * r
                let q = j.brain.resolve(SIMD3(p.x, 0, p.y), j.brain.footprint)
                if simd_distance(SIMD2(q.x, q.z), p) < 0.15 { spot = p; break }
            }
            m.spot = spot
            members[id] = m
        }
        huddleOn = false
        note("relief: shake off and scatter")
    }

    // MARK: release

    /// He is a free Jelbie again.
    @discardableResult
    private func release(_ j: Jelly, care: GameCare?) -> Bool {
        letGo(j, lying: members[j.id]?.lying ?? false)
        committed.remove(j.id); slotOf[j.id] = nil
        return false
    }

    /// Everything back (a lock started, the storm ended): every storm pose, the comfort arcs and the side-by-side emotes they started, the lying one gets up.
    func releaseAll(note why: String = "") {
        for (id, m) in members {
            guard let j = jellies.first(where: { $0.id == id }) else { continue }
            letGo(j, lying: m.lying)
            if let k = j.brain.socialKind, k == .swayHug || k == .cuddleLean || k == .sitTogether { j.brain.stop() }
        }
        members = [:]; slots = []; committed = []; slotOf = [:]; gatherAt = nil; replans = 0
        arcs = []; relean = nil
        if !why.isEmpty { note(why) }
    }

    /// Back to nothing (the app left the room, a scene change, tests).
    func reset() {
        releaseAll(); stormOn = false; peakOn = false; huddleOn = false; firstCloseDone = false; noticer = nil; noticeFace = 0; plan = nil; jellies = []; log = []
        clock = 0; joinClock = 0; replanClock = 0; seenSleep = []
        arcs = []; arcLog = []; calmAt = [:]; planClock = 0; lastRelean = -999
    }

    private func note(_ s: String) { log.append(s); if log.count > 80 { log.removeFirst() } }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
