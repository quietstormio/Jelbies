//
//  BlobBrain+Ears.swift
//  "Ears on": what the Jellies DO when they hear something. Two parts:
//    EarsPose    a small additive channel on the brain's pose (pitch / roll about his facing, squash), like the touch and social channels, so
//                a dance bounce, a giggle, a startle flinch or a curious tilt ride on top of whatever he is doing without a new script. Eased
//                toward its wants; the dance writes it directly so the bounce lands exactly on the beat.
//    EarsReactor dispatches detector events to the Jellies in the room with the locks (meal, close-up approach, bath, voice, training, race) and
//                drives the dance. THE DANCE (ears-sway-r1, ears-dance-r2) is a cycle while the music plays: they sway side to side on the beat WHERE THEY STAND
//                (Audio/EarsSway.swift: a free-running clock steered by the tempo tracker, so the pose never pops) with a small bob; after a random 5-8 s every awake
//                Jelly walks to a row facing the camera (EarsRow: spaced well apart, on free floor; the one Music Ears exception to "no line-ups in Play"), sways
//                there a bar, then does a SIMPLE stepped routine (EarsRoutine: side step, step forward and back, bounce with the arms up; each 2 bars of 4 beats,
//                repeated for 8 bars) with real foot steps through the Show's step engine (`danceLaunch`: feet never slide or cross), every plant on the beat of the
//                sway clock; then 8 bars of sway in the row, then the next routine, and so on. With no beat (yet, or lost) the clock keeps going (it coasts) and
//                there are no steps, only the sway. Sleeping Jellies only stir unless it is very loud. Cooldowns are the detector's. The music-note thought bubble
//                above each dancer is drawn by Needs/MusicBubbleView.swift (from `Ears.dancingIDs`). When the music stops they go back to normal life.
//  Body, face and the walk are untouched: the pose channel is applied in `drivePose` next to the touch channel (`BlobBrain.ears`).
//

import Foundation
import simd
import CoreGraphics

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
    /// The sway (rad of roll, one side to the other) and the small bob (squash at each extreme of the sway).
    static let sway: Float = 0.14
    static let bob: Float = 0.06
    /// They keep dancing this long after the music stopped, the last `fade` seconds of it easing the sway out.
    static let tail: Double = 2.5
    static let fade: Double = 0.8
    /// The sway grows in over this many seconds once a Jelly stands in his place.
    static let grow: Float = 0.8
    /// A walk to the row that has not arrived after this long gives up (he sways where he stands); a turn likewise.
    static let walkGiveUp: Float = 14
    static let turnGiveUp: Float = 3
    /// ears-dance-r2: how long they sway where they stand before the walk to the row (a random time in this range), a bar is 4 beats, a routine runs 8 bars
    /// (two-bar phrases, repeated), the sway in the row between two routines 8 bars; the first routine follows one bar of sway after they have all arrived.
    static let rowWait: ClosedRange<Double> = 5...8
    static let beatsPerBar = 4
    static let routineBars = 8, swayBars = 8, firstSwayBars = 1
    /// A beat shorter than this (fast songs: above ~143 BPM) is stepped on every second beat; the steps are never longer than `maxStep` seconds.
    static let fastBeat: Double = 0.42
    static let maxStep: Float = 0.75
    /// The sway fades out over this long as a routine begins (the step pose takes over).
    static let fadeToSteps: Float = 0.35
    /// The stepped routines start at least this many beats ahead (the first step's foot leaves the floor `swingFrac` of a step before its beat).
    static let leadBeats: Double = 2
}

/// The simple stepped routines (ears-dance-r2). Every one is a two-bar phrase of 8 beats that returns to where it began: all dancers do the same steps on the
/// same beats, so the gaps between them stay constant. Small and smooth: no spins, no jumps, nothing above the Show's own step height.
nonisolated enum EarsRoutine: Int, CaseIterable, Sendable {
    case sideStep         // step-touch: the body shifts onto the standing foot, left and right, a lean into it
    case forwardBack      // two steps toward the front, two steps back
    case bounce           // springy steps on the spot, the arms up with the stomp on each bar's downbeat

    var title: String {
        switch self { case .sideStep: return "side step"; case .forwardBack: return "forward and back"; case .bounce: return "bounce" }
    }

    /// Step `n` of the routine (`per` steps to the 8-beat phrase): which foot, how the body moves, and whether it is a bar's stomp (arms up).
    /// `off`: how far the body is from its mark (world x, z), `yaw`: its heading relative to the front.
    static func spec(_ r: EarsRoutine, n: Int, perPhrase per: Int, st: Float, off: SIMD2<Float>, yaw: Float) -> (spec: DanceStepSpec, accent: Bool) {
        var p = DanceStepSpec()
        p.side = n % 2
        let k = n % max(per, 1)
        var accent = false
        switch r {
        case .sideStep:
            let sched = ScheduledDanceStep(plant: 0, side: p.side, bar: 0, j: k, n: per, st: st, prompt: false)
            return (ShowDancePlan.spec(.stepTouch, step: sched, off: off.x, yaw: yaw, lively: false, final: false), false)
        case .forwardBack:
            let dir: Float = (k * 4 / max(per, 1)) % 2 == 0 ? 1 : -1          // (the first half of the phrase forward, the second back: net zero)
            p.rootD = SIMD2(-off.x * 0.5, dir * 0.09); p.inPlace = false
            p.peak = 0.08; p.sway = 0.07; p.bob = 0.06; p.rock = 0.3
        case .bounce:
            accent = k % max(per / 2, 1) == 0          // (beat 1 of each bar)
            p.rootD = SIMD2(-off.x * 0.5, 0)
            p.peak = accent ? 0.06 : 0.07; p.sway = 0.05; p.bob = 0.10; p.rock = 0.3
        }
        let e = wrapAngle(0 - yaw)
        p.dyaw = max(-0.5, min(0.5, e * 0.35))          // (square up to the front a little with every step)
        if abs(p.rootD.x) > 0.004 || abs(p.rootD.y) > 0.004 || abs(p.dyaw) > 0.004 { p.inPlace = false }
        p.peak *= max(0.6, min(1, st / 0.45))
        return (p, accent)
    }
}

/// Where the Music Ears row stands: abreast on one line facing the camera, spaced well apart (never closer than `minGap`), on free floor (clear of
/// the furniture, the sofa and the other solids), inside the visible floor. Pure placement; the reactor walks them there.
enum EarsRow {
    /// Centre-to-centre spacings tried (widest first) and the least any two may be apart.
    static let spacings: [Float] = [2.0, 1.9, 1.8, 1.7, 1.6]
    static let minGap: Float = 1.6
    /// Row depths tried (z; the call spot is 2.4): the front of the room first.
    static let depths: [Float] = [2.0, 1.8, 1.6, 2.2, 1.4, 1.2, 0.8, 0.4]
    /// How far the row may slide sideways to clear something.
    /// The middle band of the floor, nearest the middle first.
    static let middle: [Float] = [1.8, 2.0, 1.6, 2.2, 1.4]
    static let slides: [Float] = [0, -0.4, 0.4, -0.8, 0.8]
    static let bodyRadius: Float = 0.8

    /// `n` spots, left to right; empty when nothing fits (they sway where they stand).
    static func spots(count n: Int, free: (SIMD2<Float>) -> Bool, halfWidth: (Float) -> Float) -> [SIMD2<Float>] {
        guard n > 0 else { return [] }
        func fit(_ sp: Float, _ z: Float) -> [SIMD2<Float>]? {
            let hw = halfWidth(z) - 0.7
            for cx in slides {
                let xs = (0..<n).map { cx + (Float($0) - Float(n - 1) / 2) * sp }
                guard xs.allSatisfy({ abs($0) <= hw }) else { continue }
                let ps = xs.map { SIMD2<Float>($0, z) }
                if ps.allSatisfy(free) { return ps }
            }
            return nil
        }
        let sps = n == 1 ? [Float(0)] : spacings
        // the widest spacing (2.0 down to `minGap`) that fits in the middle band of the floor, nearest the middle first ...
        for sp in sps { for z in middle { if let r = fit(sp, z) { return r } } }
        // ... else the nearest depth at all that takes a row of at least `minGap`
        for z in depths { for sp in sps { if let r = fit(sp, z) { return r } } }
        return []
    }

    /// The body (and a little either side) is inside the picture and clear of the HUD rails, as the room camera sees the floor.
    static func onScreenClear(_ p: SIMD2<Float>) -> Bool {
        let asp = GameCamera.aspect
        let size = CGSize(width: CGFloat(1000 * asp), height: 1000)
        let rails = HUDLayout.railRects(aspect: asp)
        for dx: Float in [-0.6, 0, 0.6] {
            guard let sp = GameCamera.screenPoint(floor: SIMD2(p.x + dx, p.y), size: size) else { return false }
            let f = CGPoint(x: sp.x / size.width, y: sp.y / size.height)
            if f.x < 0.03 || f.x > 0.97 || f.y < 0.2 || f.y > 0.92 { return false }
            for r in rails where r.insetBy(dx: -0.01, dy: -0.03).contains(f) { return false }
        }
        return true
    }

    /// Floor test and floor width as the game has them.
    static func gameSpots(count n: Int, resolver: BlobBrain?) -> [SIMD2<Float>] {
        func base(_ p: SIMD2<Float>) -> Bool {
            guard FreeFloor.isFree(p, radius: bodyRadius) else { return false }
            return p.y <= (GameCamera.roamFloor?.maxZ ?? 5) - 0.3 && p.y >= (GameCamera.roamFloor?.minZ ?? -2) + 0.3          // (inside the roam floor; other bodies standing there walk off on their own)
        }
        let hw: (Float) -> Float = { z in GameCamera.roamFloor?.halfWidth(at: z) ?? 2.6 }
        // in the picture and clear of the HUD first; a narrow view (portrait phone) that has no such row for 3 gets the free-floor one
        let strict = spots(count: n, free: { base($0) && onScreenClear($0) }, halfWidth: hw)
        return strict.isEmpty ? spots(count: n, free: base, halfWidth: hw) : strict
    }
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
        /// The beat as last heard (nil = none / lost).
        var beat: EarBeat?
        var started: Double
        var endAt: Double?
    }
    /// One dancer's place in the row and how far along he is.
    struct RowStep {
        enum Phase { case walking, turning, swaying }
        var spot: SIMD2<Float>?
        var phase: Phase = .walking
        var t: Float = 0
        var lastAsk: Float = -10
        var asks = 0
        var gain: Float = 0
        var turned = false
    }
    enum Anim: Equatable { case perk, giggle, startle(level: Float), curious, tilt, stir }
    /// The cycle while the music plays (ears-dance-r2): sway where they stand, walk to the row after `rowWait`, sway there, a routine, sway, the next routine ...
    /// Everything in the routine is timed on the sway clock's `u` (side changes), `unit` of them to the beat (latched when the routine is planned).
    struct Cycle {
        enum Stage: Equatable { case inPlace, toRow, rowSway, routine }
        var stage: Stage = .inPlace
        var rowWait: Double = 6
        var swayUntilU: Double = 0
        var routine: EarsRoutine = .sideStep
        var routines = 0
        var startU: Double = 0, stepU: Double = 1, unit: Double = 1
        var steps = 0, perPhrase = 8
        var endU: Double { startU + Double(steps) * stepU }
        /// The steps of the routine are going on (the lead-in included).
        var stepping: Bool { stage == .routine }
    }
    /// One dancer's stepping state in a routine.
    struct Stepper {
        var mark: SIMD2<Float>
        var next = 0
        var wasSwinging = false
        var lastPlant: Double = 0
    }

    var locks = Locks()
    /// Another worker's lock (the race): read every tick.
    var extraLock: () -> Bool = { false }
    /// Care hooks (GameCare.comeHere / comeHereEveryone); tests count them.
    var comeHere: (Int) -> Void = { _ in }
    var comeEveryone: () -> Void = {}
    /// The dance started / ended (the hub fades its own music down while they dance to someone else's).
    var onDance: (Bool) -> Void = { _ in }
    private(set) var dance: Dance?
    /// Ears sets this while a dance that the mic HOLD started is running (the voice lock is the hold itself, not a reason to stop).
    var voiceExempt = false
    /// The sway clock all dancers share, and where each one stands in the row.
    private(set) var sway = EarsSway()
    private(set) var rows: [Int: RowStep] = [:]
    private(set) var cycle = Cycle()
    private var steppers: [Int: Stepper] = [:]
    /// The wait before the walk to the row (random in `EarsDance.rowWait`; tests pin it).
    var rowWaitRange = EarsDance.rowWait
    /// Routines run (set false to keep them out: the plain sway in the row).
    var routinesOn = true
    /// How many times the safety net sent a dancer back to his spot (should stay 0).
    private(set) var walkBacks = 0
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
        l.voice = care.voice.mode.phase != .idle && !voiceExempt
        l.training = false
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
        // (ears-dance-r2: a Jelly who is dancing keeps dancing: no clap / whistle calls him, nothing startles, perks or hops him out of his place; a dance that
        // the room's other Jellies (not dancing) hear still gets the reactions)
        let react = dance != nil ? awake.filter { !$0.brain.ears.dancing } : awake
        switch e {
        case .heard(.clap), .heard(.snap):
            for j in asleep { start(.stir, j) }
            guard !locks.blocksBig else { for j in react { start(.giggle, j) }; return }
            for j in react { start(.perk, j) }
            if let near = nearestToFront(react) { come(near); note("clap: \(near.id) comes") }
        case .doubleClap:
            for j in asleep { start(.stir, j) }
            guard !locks.blocksBig else { for j in react { start(.giggle, j) }; return }
            if !asleep.isEmpty || dance != nil {          // sleepers in the room (or a dance on: nobody is called away from it): a double clap is only a clap (nobody calls everyone and wakes them)
                for j in react { start(.perk, j) }
                if let near = nearestToFront(react) { come(near); note("double clap (sleepers): \(near.id) comes") }
                return
            }
            for j in react { start(.perk, j); j.brain.hurry = true; hurrying.insert(j.id) }
            comeEveryone(); note("double clap: everyone comes")
        case .musicStarted(let b):
            guard !locks.blocksBig else { return }
            if dance == nil {
                dance = Dance(beat: b, started: now); sway.reset(); onDance(true); note("dance on \(b.map { "\($0.bpm) bpm" } ?? "no beat")")
                cycle = Cycle(); cycle.rowWait = Double.random(in: rowWaitRange); cycle.routine = EarsRoutine.allCases.randomElement() ?? .sideStep
                steppers.removeAll(); rows.removeAll()
                if Self.stepLog { NSLog("[ears] CYCLE start rowWait=%.2f", cycle.rowWait) }
            }
            else { dance?.endAt = nil; dance?.beat = b ?? dance?.beat }
            if let b { sway.hear(b, now: now) }
            for j in awake {
                j.brain.ears.dancing = true; j.brain.face(.joyArc, hold: 1.6); j.brain.blushBump(hold: 2.4, peak: 0.5)          // the dance: "^^" eyes and a blush
                // he sways where he stands: an idle move he is in finishes by itself (as the Show's dancers' do), nothing else starts (`held`)
                if j.brain.idleState.kind != nil, !j.brain.idleState.yielding { j.brain.idleState.yielding = true; j.brain.idleState.yieldT = 0 }
            }
            for j in asleep { start(.stir, j) }
        case .musicBeat(let b):
            dance?.beat = b
            if dance != nil { sway.hear(b, now: now) }
        case .musicBeatLost:
            dance?.beat = nil
            sway.lost()
        case .musicStopped:
            if dance != nil, dance?.endAt == nil { dance?.endAt = now + EarsDance.tail; note("music stopped: dance ends in \(EarsDance.tail) s") }
        case .heard(.laugh):
            for j in react { start(.giggle, j) }
            for j in asleep { start(.stir, j) }
        case .heard(.whistle):
            for j in react { start(.tilt, j) }
            for j in asleep { start(.stir, j) }
            if !locks.blocksBig { whistleComeAt = now + 2.4 }
        case .heard(.dogBark), .heard(.doorbell):
            for j in react { start(.startle(level: 0.5), j) }
            for j in asleep { start(.stir, j) }
        case .heard(.catMeow), .heard(.babyCry):
            for j in react { start(.curious, j) }
        case .bang(let level):
            for j in react { start(.startle(level: level), j) }
            for j in asleep {
                if level >= SleepTuning.earsWakeLevel { j.brain.sleepWake(groggy: true, fast: true, slow: true); start(.startle(level: level), j); note("bang woke \(j.id)") }
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
            else { driveDance(jellies, dt: dt, now: now) }
        }
        if let t = whistleComeAt, now >= t {
            whistleComeAt = nil
            if !locks.blocksBig, let near = nearestToFront(jellies.filter { !$0.brain.isSleeping && !$0.brain.ears.dancing }) { come(near); note("whistle: \(near.id) comes") }
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

    /// The row for the dancers (`awake` = the Jellies that dance now): their places, left to right by where they stand now.
    private func placeRow(_ awake: [Jelly]) {
        let dancers = awake.filter { !$0.brain.isNapping }
        guard !dancers.isEmpty else { return }
        let spots = EarsRow.gameSpots(count: dancers.count, resolver: dancers.first?.brain)
        let order = dancers.sorted { GameCare.floorPos($0.brain, $0.sim).x < GameCare.floorPos($1.brain, $1.sim).x }
        for (k, j) in order.enumerated() {
            var st = RowStep()
            st.gain = rows[j.id]?.gain ?? 0          // (the sway he is in fades out as he sets off, it does not stop at once)
            st.spot = k < spots.count ? spots[k] : nil
            if st.spot == nil { st.phase = .swaying }          // (no room for a row: he sways where he stands)
            rows[j.id] = st
        }
        note("row: \(spots.count) spots for \(dancers.count)")
        if UserDefaults.standard.bool(forKey: "EarsLog") { NSLog("[ears] row spots=%@ from=%@", spots.map { String(format: "(%.2f,%.2f)", $0.x, $0.y) }.joined(separator: " "), order.map { String(format: "%d(%.2f,%.2f)", $0.id, GameCare.floorPos($0.brain, $0.sim).x, GameCare.floorPos($0.brain, $0.sim).y) }.joined(separator: " ")) }
    }

    /// `-EarsLog 1`: the roll the render is given each sim step; the largest step between two steps is printed once a second.
    static let stepLog = UserDefaults.standard.bool(forKey: "EarsLog")
    private var gapMin = Float.infinity, gapWalkMin = Float.infinity, gapDanceMin = Float.infinity, gapAt: Double = 0
    private var stepPrev: [Int: Float] = [:]
    private var stepMax: Float = 0, stepAt: Double = 0, rollMaxSeen: Float = 0
    private func logStep(_ id: Int, _ roll: Float, now: Double) {
        if let p = stepPrev[id] { stepMax = max(stepMax, abs(roll - p)) }
        stepPrev[id] = roll; rollMaxSeen = max(rollMaxSeen, abs(roll))
        if now - stepAt >= 1 { stepAt = now; NSLog("[ears] roll step max %.4f rad/step, |roll| max %.3f", stepMax, rollMaxSeen); stepMax = 0 }
    }

    private func driveDance(_ jellies: [Jelly], dt: Float, now: Double) {
        guard let d = dance else { return }
        if Self.stepLog {          // capture aid: the closest two dancers each second (walking in / swaying)
            let dn = jellies.filter { $0.brain.ears.dancing }
            var m = Float.infinity
            for a in 0..<dn.count { for b in (a + 1)..<max(dn.count, a + 1) { m = min(m, simd_distance(GameCare.floorPos(dn[a].brain, dn[a].sim), GameCare.floorPos(dn[b].brain, dn[b].sim))) } }
            gapMin = min(gapMin, m)
            if rows.values.contains(where: { $0.phase != .swaying }) { gapWalkMin = min(gapWalkMin, m) } else { gapDanceMin = min(gapDanceMin, m) }
            if now - gapAt >= 1 { gapAt = now; NSLog("[ears] gap now-min=%.2f walkin-min=%.2f dance-min=%.2f", gapMin, gapWalkMin, gapDanceMin); gapMin = .infinity }
        }
        sway.tick(dt: Double(dt))
        updateCycle(jellies, now: now)
        // the last `fade` seconds of the tail ease the sway out
        let tailK = Float(d.endAt.map { min(1, max(0, ($0 - now) / EarsDance.fade)) } ?? 1)
        for j in jellies where j.brain.ears.dancing {
            let brain = j.brain
            if brain.isNapping || brain.reserved || anims[j.id] != nil { continue }
            // stay for the song: no wander legs or idle specials start while dancing
            brain.restTimer = max(brain.restTimer, 1.5)
            brain.idleState.cooldown = max(brain.idleState.cooldown, 1.5)
            var st = rows[j.id] ?? { var r = RowStep(); r.phase = .swaying; return r }()
            st.t += dt
            let free: Bool = { if case .none = brain.script, brain.pending == nil, !brain.gait.isBusy { return true } else { return false } }()
            // safety net only (a dancer is `held`, so the idle / social / reaction walks do not start): pushed off his place by something else, back to the row. Counted.
            if st.phase != .walking, let spot = st.spot, free, st.asks < 4, st.t > 0.5, simd_distance(GameCare.floorPos(brain, j.sim), spot) > 1.0 {
                walkBacks += 1; note("row: \(j.id) walked back (\(walkBacks))"); if Self.stepLog { NSLog("[ears] WALKBACK %d count=%d", j.id, walkBacks) }
                st.phase = .walking; st.t = 0; st.lastAsk = -10; st.turned = false; st.gain = 0
            }
            switch st.phase {
            case .walking:
                fadeSway(brain, &st, dt: dt, tailK: tailK)
                guard let spot = st.spot else { st.phase = .swaying; break }
                let here = GameCare.floorPos(brain, j.sim)
                if simd_distance(here, spot) < 0.3 && free { st.phase = .turning; st.t = 0 }
                else if free, st.t - st.lastAsk >= 1.0, st.asks < 12 { st.lastAsk = st.t; st.asks += 1; brain.requestNow(.goTo(spot)) }
                else if st.t > EarsDance.walkGiveUp { st.phase = .swaying; st.spot = nil; note("row: \(j.id) gave up the walk") }
            case .turning:
                fadeSway(brain, &st, dt: dt, tailK: tailK)
                let off = abs(wrapAngle(brain.yaw - brain.faceCameraYaw()))
                if !st.turned, free {
                    st.turned = true
                    if off > 0.3 { brain.startTurn(to: brain.faceCameraYaw(), sim: j.sim) } else { st.phase = .swaying }
                } else if st.turned, free, off < 0.4 || st.t > EarsDance.turnGiveUp { st.phase = .swaying }
                else if st.t > EarsDance.turnGiveUp + 2 { st.phase = .swaying }
            case .swaying:
                break
            }
            if st.phase == .swaying {
                let g0 = tailK, amp = brain.amplitude
                if cycle.stepping, st.spot != nil, brain.ears.dancing {
                    // the routine: the sway fades out under the first steps, the feet do the dance (the Show's step engine; the walk is not touched)
                    st.gain = max(0, st.gain - dt / EarsDance.fadeToSteps)
                    brain.ears.write(pitch: 0, roll: sway.roll(maxRoll: EarsDance.sway) * st.gain * g0 * amp, squash: 1 - (1 - sway.squash(depth: EarsDance.bob)) * st.gain * g0 * amp)
                    driveSteps(j, now: now)
                } else {
                    if brain.danceDrive != nil { stopSteps(brain); steppers[j.id] = nil }
                    if free {
                        st.gain = min(1, st.gain + dt / EarsDance.grow)
                        let g = st.gain * g0
                        let sq = 1 - (1 - sway.squash(depth: EarsDance.bob)) * g
                        brain.ears.write(pitch: 0, roll: sway.roll(maxRoll: EarsDance.sway) * g * amp, squash: 1 - (1 - sq) * amp)
                        if Self.stepLog { logStep(j.id, brain.ears.roll, now: now) }
                    } else if brain.danceDrive == nil { brain.ears.clear() }          // (still walking off a leg / finishing a step: the sway waits until he stands)
                }
            }
            if UserDefaults.standard.bool(forKey: "EarsLog"), rows[j.id]?.phase != st.phase { NSLog("[ears] %d -> %@ at (%.2f,%.2f) t=%.1f", j.id, String(describing: st.phase), GameCare.floorPos(brain, j.sim).x, GameCare.floorPos(brain, j.sim).y, st.t) }
            if Self.stepLog, Int(now) != Int(now - Double(dt)) { NSLog("[ears] pos %d %@ (%.2f,%.2f) spot=%@ script=%@ pending=%@", j.id, String(describing: st.phase), GameCare.floorPos(brain, j.sim).x, GameCare.floorPos(brain, j.sim).y, st.spot.map { String(format: "(%.2f,%.2f)", $0.x, $0.y) } ?? "-", String(describing: brain.script).prefix(40) as CVarArg, String(describing: brain.pending).prefix(40) as CVarArg) }
            rows[j.id] = st
        }
    }

    // MARK: the cycle (ears-dance-r2)

    /// The dancers in the row are all in their places (arrived, standing, the sway on) and every one of them has a spot: a routine may run.
    private func rowReady(_ dancers: [Jelly]) -> Bool {
        guard !dancers.isEmpty else { return false }
        return dancers.allSatisfy { j in
            guard let st = rows[j.id], st.phase == .swaying, let spot = st.spot else { return false }
            return simd_distance(GameCare.floorPos(j.brain, j.sim), spot) < 0.5
        }
    }

    /// Where the dance is in its cycle. The sway clock is the one clock: the routine's steps are `stepU` apart on it (an integer number of beats), so they land
    /// where the sway lands. Without a locked beat there is no routine (only the sway, in the row); a lost beat or the end of the music ends one at once.
    private func updateCycle(_ jellies: [Jelly], now: Double) {
        guard let d = dance else { return }
        let dancers = jellies.filter { $0.brain.ears.dancing && !$0.brain.isNapping }
        let ending = d.endAt != nil
        let beatU = max(sway.unit, 0.25)
        switch cycle.stage {
        case .inPlace:
            if !ending, now - d.started >= cycle.rowWait {
                placeRow(dancers.filter { !$0.brain.reserved })
                cycle.stage = .toRow
                note("walk to the row after \(String(format: "%.1f", cycle.rowWait)) s")
                if Self.stepLog { NSLog("[ears] CYCLE toRow t=%.2f", now - d.started) }
            }
        case .toRow:
            if rowReady(dancers) {
                cycle.stage = .rowSway; cycle.swayUntilU = sway.u + Double(EarsDance.firstSwayBars * EarsDance.beatsPerBar) * beatU
                note("in the row")
                if Self.stepLog { NSLog("[ears] CYCLE rowSway t=%.2f", now - d.started) }
            } else if rows.isEmpty { cycle.stage = .rowSway; cycle.swayUntilU = sway.u + 1e9 }          // (nobody to place)
        case .rowSway:
            guard routinesOn, !ending, sway.locked, !sway.isCoasting, sway.u >= cycle.swayUntilU, rowReady(dancers) else { break }
            // the next routine, different from the last: the whole phrase on the beats of the clock as it is now
            let rate = max(sway.ratePerSecond, 0.1)
            let beatSec = beatU / rate
            let every = beatSec < EarsDance.fastBeat ? 2.0 : 1.0
            let stepU = every * beatU
            cycle.unit = beatU; cycle.stepU = stepU
            cycle.perPhrase = Int(Double(2 * EarsDance.beatsPerBar) / every)
            cycle.steps = Int(Double(EarsDance.routineBars * EarsDance.beatsPerBar) / every)
            cycle.startU = ((sway.u / beatU).rounded(.up) + EarsDance.leadBeats) * beatU
            if cycle.routines > 0 { cycle.routine = EarsRoutine(rawValue: (cycle.routine.rawValue + 1) % EarsRoutine.allCases.count) ?? .sideStep }
            cycle.routines += 1
            cycle.stage = .routine
            steppers.removeAll()
            note("routine \(cycle.routine.title): \(cycle.steps) steps, one per \(Int(every)) beat(s)")
            if Self.stepLog { NSLog("[ears] CYCLE routine %@ steps=%d every=%d startU=%.2f beat=%.3f s", cycle.routine.title, cycle.steps, Int(every), cycle.startU, beatSec) }
        case .routine:
            if ending || !sway.locked || sway.isCoasting || sway.u >= cycle.endU {
                cycle.stage = .rowSway
                cycle.swayUntilU = sway.u + Double(EarsDance.swayBars * EarsDance.beatsPerBar) * beatU
                note("routine over")
                if Self.stepLog { NSLog("[ears] CYCLE routine over t=%.2f ending=%d", now - d.started, ending ? 1 : 0) }
            }
        }
    }

    /// The dancer's steps of the routine: each foot leaves the floor `swingFrac` of a step before its beat on the sway clock and plants ON it (the Show's step engine,
    /// `danceLaunch`: the feet never slide or cross). A step that came too late is skipped, never played late.
    private func driveSteps(_ j: Jelly, now: Double) {
        let b = j.brain
        if b.danceDrive == nil {
            guard case .none = b.script, b.idleState.kind == nil, b.pending == nil, !b.gait.isBusy else { return }
            b.danceDrive = DanceStepDrive()
            b.startStepping(seconds: 1e9, sim: j.sim)
            steppers[j.id] = Stepper(mark: b.position)
        }
        guard case .stepInPlace = b.script, var sr = steppers[j.id] else { return }
        defer { steppers[j.id] = sr }
        // a plant that just happened (logged against the beat grid the tracker last sent, and the clock's)
        if sr.wasSwinging, !b.feet.swinging {
            plantLog(id: j.id, side: b.feet.side, now: now)
        }
        sr.wasSwinging = b.feet.swinging
        guard sr.next < cycle.steps else { return }
        let rate = max(sway.ratePerSecond, 0.1)
        let st = Float(min(cycle.stepU / rate / Double(ShowDancePlan.rateFactor), Double(EarsDance.maxStep)))
        let plantU = cycle.startU + Double(sr.next) * cycle.stepU
        if sway.u > plantU + 0.12 * rate { sr.next += 1; return }          // (a late frame: that step's moment has gone by)
        guard sway.u >= plantU - Double(ShowDancePlan.swingFrac * st) * rate else { return }
        let off = b.position - sr.mark
        let (spec, accent) = EarsRoutine.spec(cycle.routine, n: sr.next, perPhrase: cycle.perPhrase, st: st, off: off, yaw: wrapAngle(b.yaw - b.faceCameraYaw()))
        if b.danceLaunch(spec, st: st, accent: accent) { sr.next += 1; sr.lastPlant = plantU }
    }

    /// The sway he is in eases out over `fadeToSteps` (he walks off to the row / turns): no pop.
    private func fadeSway(_ brain: BlobBrain, _ st: inout RowStep, dt: Float, tailK: Float) {
        st.gain = max(0, st.gain - dt / EarsDance.fadeToSteps)
        if st.gain > 0 {
            let g = st.gain * tailK, amp = brain.amplitude
            brain.ears.write(pitch: 0, roll: sway.roll(maxRoll: EarsDance.sway) * g * amp, squash: 1 - (1 - sway.squash(depth: EarsDance.bob)) * g * amp)
        } else { brain.ears.clear() }
    }

    /// His stepping script ends once the step in the air has landed (the normal end of a step-in-place: feet together, heading where it was).
    private func stopSteps(_ b: BlobBrain) {
        guard b.danceDrive != nil else { return }
        b.danceDrive = nil; b.armDirW = 0; b.armWalkWant = 0
        if case .stepInPlace = b.script { b.script = .stepInPlace(t: 1, dur: 0) }
    }

    /// `-EarsLog 1`: each plant of a routine step. `gridErr`: milliseconds from the nearest beat of the grid the tracker sent (anchor + k * period); `uErr`: from the
    /// nearest beat of the sway clock (integers of `u` / unit); `rate`: the clock's side changes a second.
    private func plantLog(id: Int, side: Int, now: Double) {
        guard Self.stepLog else { return }
        var gridErr = Double.nan
        if let bt = dance?.beat {
            let period = 60 / Double(bt.bpm)
            gridErr = (now - bt.anchor - ((now - bt.anchor) / period).rounded() * period) * 1000
        }
        let bu = sway.u / max(cycle.unit, 0.25)
        let uErr = (bu - bu.rounded()) * (cycle.unit / max(sway.ratePerSecond, 0.1)) * 1000
        NSLog("[ears] PLANT id=%d side=%d routine=%@ host=%.4f gridErr=%+.0f ms uErr=%+.0f ms", id, side, cycle.routine.title, now, gridErr, uErr)
    }

    private func endDance(_ jellies: [Jelly]) {
        dance = nil
        rows.removeAll(); steppers.removeAll(); cycle = Cycle()
        for j in jellies { stopSteps(j.brain); j.brain.ears.dancing = false; if anims[j.id] == nil { j.brain.ears.clear() } }
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
