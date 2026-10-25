//
//  RaceModel.swift
//  Jelly Circuit, "Waddle Sprint" v1: the rules of one race as a pure model (no bodies, no screen), so it runs headless in tests.
//
//    RaceTuning      the track, the stat -> speed mapping, the countdown, the payout table.
//    RivalSource     where the other racers come from. v1 = LocalRivalSource (made up per race from a seed); a Game Center ghost source plugs in later.
//    RaceTapModel    the two foot buttons: alternate taps commit ONE step each (at most one ahead), the same foot twice is a stumble.
//    RaceSim         the race itself: countdown, running, finishing, results; rivals' AI taps; focus pauses; placings; Drops.
//
//  The race runs along +z, toward the camera: lanes side by side in x, start line far, finish line near.
//  Its speed has its OWN parameters (stride and step rate from the `waddle` stat); the roaming walk's walkBoost / runStrideMul are never read.
//

import Foundation
import simd

nonisolated enum RaceTuning {
    // MARK: track (world units; z grows toward the camera)
    static let startZ: Float = -7.0
    static let finishZ: Float = 5.5
    static var length: Float { finishZ - startZ }
    static let laneSpacing: Float = 1.6
    /// Lane x for lane `i` of `n` (centred).
    static func laneX(_ i: Int, of n: Int = 3) -> Float { (Float(i) - Float(n - 1) / 2) * laneSpacing }
    /// The player's lane (the middle one).
    static let playerLane = 1

    // MARK: stat -> speed
    /// Stride of one step (world units) for a waddle stat: 0.27 ... 0.32. (The roaming walk's is 0.305 x 1.143 = 0.348; the run's 0.366.) The top is the
    /// longest stride whose feet stay inside the feet-attached limit over the whole step-rate range (measured: worst foot overlap -0.0208 at 0.32,
    /// -0.0186 at 0.34); the speed comes from the step RATE as much as from the stride.
    static func stride(waddle: Float) -> Float { 0.27 + 0.05 * clamp01(waddle) }
    /// The quickest step rate (steps per second) he trains to: 3.0 ... 4.2 (the roam walk's is 3.75, the run's 4.2). Tapping faster does not help.
    static func maxRate(waddle: Float) -> Float { 3.0 + 1.2 * clamp01(waddle) }
    /// Ground speed (u/s) of steady stepping at the trained rate.
    static func speed(waddle: Float) -> Float { stride(waddle: waddle) * maxRate(waddle: waddle) }
    /// The first step of a race is half a stride (the feet start square).
    static let firstStepFraction: Float = 0.5
    /// Seconds of the stumble after the same foot is tapped twice (no steps; the body rocks).
    static let stumbleTime: Float = 0.6
    /// No step for this long = stalled (the hint shows; he has stopped).
    static let stallAfter: Float = 0.7

    // MARK: flow
    static let countdownBeat: Float = 0.85          // seconds per 3 / 2 / 1
    static let goFlash: Float = 0.6
    /// After the first racer finishes the others get this long to cross, then the placings are made from where they are.
    static let finishGrace: Float = 5.0
    /// A player who has not stepped for this long once someone has finished is not racing any more: the window is the plain 2 x finishGrace,
    /// not the course's longer one (RaceCourse.stragglerGrace). Longer than a trip (0.6 s) or a look-around (1.3 s).
    static let stragglerStall: Float = 2.5
    /// The race is called off this long after GO (a Jelly that never moves).
    static let timeout: Float = 45
    /// The final-stretch music starts when the leader is this close to the line (world units).
    static let finalStretch: Float = 4.0
    /// Steps a finished racer takes on his own to slow to a stop, each shorter and slower than the last.
    static let coastSteps = 3
    static func coastStride(_ k: Int) -> Float { [0.75, 0.5, 0.3][min(max(k, 0), 2)] }

    // MARK: focus pauses (a racer stops to look around)
    /// Hazard (per second of running) of a look-around for a focus: 0 at focus 1, 0.28 at focus 0, squared in between.
    static func pauseHazard(focus: Float) -> Float { 0.28 * (1 - clamp01(focus)) * (1 - clamp01(focus)) }
    static let pauseTime: Float = 1.3
    static let pauseCooldown: Float = 3.0
    /// No pause in the first seconds after GO, and none once the line is near.
    static let pauseFreeStart: Float = 1.5
    static let pauseFreeFinish: Float = 2.0

    // MARK: trips (a racer who has not practised much stumbles over his own feet)
    /// Chance, per step, of a trip (a stumble of `stumbleTime`, no tap needed): `skill` is 60% waddle and 40% focus. A new Jelly (about 0.45 / 0.5)
    /// trips about once a race, a trained one (0.8 / 0.7 and up) hardly ever, a fully trained one never. The same for rivals.
    static func tripChance(waddle: Float, focus: Float) -> Float {
        let skill = 0.6 * clamp01(waddle) + 0.4 * clamp01(focus)
        let u = 1 - skill
        return 0.2 * u * u * u
    }
    /// No trip in the first steps, and none once the line is near (the pause rule).
    static let tripFreeSteps = 2

    // MARK: payout
    /// Drops by place (1-based) on the Puddle. Races pay the most: 1st 12, 2nd 7, 3rd 4 (care pays 1 at a time).
    static func drops(place: Int) -> Int { drops(place: place, tier: .puddle) }
    /// Drops by place and course: Puddle 12 / 7 / 4, Ripple 15 / 9 / 5, Splash 18 / 11 / 7, Wave 22 / 13 / 8, Tsunami 28 / 16 / 10.
    static func drops(place: Int, tier: CourseTier) -> Int {
        let table: [Int]
        switch tier {
        case .puddle: table = [12, 7, 4]
        case .ripple: table = [15, 9, 5]
        case .splash: table = [18, 11, 7]
        case .wave: table = [22, 13, 8]
        case .tsunami: table = [28, 16, 10]
        }
        return table[min(max(place, 1), 3) - 1]
    }

    static func clamp01(_ v: Float) -> Float { min(max(v, 0), 1) }
}

// MARK: - Rivals

/// What a racer brings to the line.
nonisolated struct RacerStats: Equatable, Sendable {
    var waddle: Float
    var focus: Float
}

/// Another person's Jelly (v1: made up).
nonisolated struct Rival: Equatable, Sendable {
    var name: String
    /// sRGB 0...1 body tint (a pastel, not the player's).
    var tint: SIMD3<Float>
    var stats: RacerStats
}

nonisolated protocol RivalSource: Sendable {
    /// `count` rivals for a race against a player with `player` stats and body tint `playerTint`. Deterministic for one `seed`.
    func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64) -> [Rival]
    /// The same for a course: higher courses field better-trained rivals (rank-scaled stats). Defaults to the plain rivals.
    func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64, tier: CourseTier) -> [Rival]
}

extension RivalSource {
    func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64, tier: CourseTier) -> [Rival] {
        rivals(count: count, player: player, playerTint: playerTint, seed: seed)
    }
}

/// v1 rivals: names and pastel tints from small pools, stats near the player's.
nonisolated struct LocalRivalSource: RivalSource {
    static let names = ["Biscuit", "Pebble", "Noodle", "Mochi", "Sprout", "Waffles", "Dumpling", "Tofu", "Pudding", "Bean", "Maple", "Fizz"]
    /// Hues (0...1) the pastel tints are drawn from: pink, peach, lilac, aqua, lavender-blue, lime.
    static let hues: [Float] = [0.93, 0.05, 0.76, 0.50, 0.68, 0.22]
    /// How far (waddle / focus) a rival may be from the player.
    static let waddleSpread: Float = 0.12, focusSpread: Float = 0.18
    /// The least waddle / focus a rival brings to each course (the field is better trained up the ranks; none on the Puddle).
    static func floor(_ tier: CourseTier) -> RacerStats {
        switch tier {
        case .puddle: return RacerStats(waddle: 0, focus: 0)
        case .ripple: return RacerStats(waddle: 0.45, focus: 0.40)
        case .splash: return RacerStats(waddle: 0.60, focus: 0.55)
        case .wave: return RacerStats(waddle: 0.72, focus: 0.65)
        case .tsunami: return RacerStats(waddle: 0.80, focus: 0.72)
        }
    }

    func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64) -> [Rival] {
        rivals(count: count, player: player, playerTint: playerTint, seed: seed, tier: .puddle)
    }

    func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64, tier: CourseTier) -> [Rival] {
        var g = RaceRNG(seed: seed &* 0x9E3779B97F4A7C15 &+ 0x51ED)
        let playerHue = Self.hue(of: playerTint)
        var hues = Self.hues.filter { abs($0 - playerHue) > 0.09 && abs($0 - playerHue) < 0.91 }
        var names = Self.names
        var out: [Rival] = []
        let fl = Self.floor(tier)
        for _ in 0..<max(count, 0) {
            let name = names.remove(at: Int(g.next() * Float(names.count)) % names.count)
            let hue = hues.remove(at: Int(g.next() * Float(hues.count)) % hues.count)
            let w = RaceTuning.clamp01(player.waddle + (g.next() * 2 - 1) * Self.waddleSpread)
            let f = RaceTuning.clamp01(player.focus + (g.next() * 2 - 1) * Self.focusSpread)
            out.append(Rival(name: name, tint: Self.hsv(hue, 0.34, 0.96), stats: RacerStats(waddle: max(min(max(w, 0.1), 0.95), fl.waddle), focus: max(min(max(f, 0.15), 0.95), fl.focus))))
        }
        return out
    }

    static func hsv(_ h: Float, _ s: Float, _ v: Float) -> SIMD3<Float> {
        let k = h * 6, i = floorf(k), f = k - i
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch Int(i) % 6 {
        case 0: return SIMD3(v, t, p)
        case 1: return SIMD3(q, v, p)
        case 2: return SIMD3(p, v, t)
        case 3: return SIMD3(p, q, v)
        case 4: return SIMD3(t, p, v)
        default: return SIMD3(v, p, q)
        }
    }
    static func hue(of c: SIMD3<Float>) -> Float {
        let mx = max(c.x, c.y, c.z), mn = min(c.x, c.y, c.z), d = mx - mn
        guard d > 1e-5 else { return 0 }
        var h: Float
        if mx == c.x { h = (c.y - c.z) / d } else if mx == c.y { h = 2 + (c.z - c.x) / d } else { h = 4 + (c.x - c.y) / d }
        h /= 6
        return h < 0 ? h + 1 : h
    }

    /// The body palette a rival tint makes (same soft matte treatment as the roster's Moss).
    static func palette(for tint: SIMD3<Float>, name: String) -> Palette {
        let h = hue(of: tint)
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        return JellyPalettes.matte(Palette(name: name, flesh: hsv(h, 0.36, 0.87), fleshDeep: hsv(h, 0.55, 0.65), pale: unused, skin: unused, stripe: unused,
                                           seed: PaletteKey.blue.palette.seed, shadowTint: hsv(h, 0.33, 0.745), uiFlesh: hsv(h, 0.41, 0.80)))
    }
}

/// Small xorshift64* generator, 0..<1 floats. Deterministic.
nonisolated struct RaceRNG: Sendable {
    private var s: UInt64
    init(seed: UInt64) { s = seed == 0 ? 0x2545F4914F6CDD1D : seed }
    mutating func next() -> Float {
        s ^= s >> 12; s ^= s << 25; s ^= s >> 27
        return Float((s &* 0x2545F4914F6CDD1D) >> 40) / Float(1 << 24)
    }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
}

// MARK: - The two foot buttons

/// The tap rules. Each ALTERNATING tap commits one step (kept in a buffer of one: a second tap before the step is taken is dropped, so tapping
/// faster than the trained step rate does not help). The same foot twice in a row is a stumble: the buffer is lost and he cannot step for
/// `stumbleTime`. Taps during a stumble or a look-around pause are ignored (no penalty).
nonisolated struct RaceTapModel: Equatable, Sendable {
    enum Outcome: Equatable, Sendable { case queued, ignored, stumble }

    /// The foot of the previous tap (the finger sequence: what an immediate repeat is judged by). 0 = left, 1 = right.
    private(set) var lastTap: Int?
    /// The foot that stepped last; the next step is the other one (the first step is the tapped foot).
    private(set) var lastStepFoot: Int?
    /// The buffered step (at most one).
    private(set) var pending: Int?
    private(set) var stumbleLeft: Float = 0
    private(set) var steps = 0, stumbles = 0, ignored = 0, trips = 0
    /// The current stumble is a trip (not a double tap): the hint differs.
    private(set) var tripped = false
    /// A repeated foot within this many seconds of the last tap is forgiven (ignored, no stumble): the focus snack's wider window. 0 = none.
    var grace: Float = 0
    private var sinceTap: Float = .infinity

    var stumbling: Bool { stumbleLeft > 0 }
    /// The foot the next step uses.
    var nextFoot: Int { lastStepFoot.map { 1 - $0 } ?? 0 }
    /// The foot a one-button player's next press counts as: always the OTHER one than the last tap (a stumble is impossible).
    var alternateFoot: Int { lastTap.map { 1 - $0 } ?? 0 }

    mutating func tap(_ foot: Int, canStep: Bool = true) -> Outcome {
        let f = foot == 0 ? 0 : 1
        defer { lastTap = f }
        if !canStep || stumbleLeft > 0 { ignored += 1; return .ignored }          // paused / stumbling: not a fault
        if lastTap == f, grace > 0, sinceTap <= grace { ignored += 1; return .ignored }     // a bounce of the same finger, forgiven
        sinceTap = 0
        if lastTap == f {
            tripped = false
            stumbles += 1; stumbleLeft = RaceTuning.stumbleTime; pending = nil
            return .stumble
        }
        if pending != nil { ignored += 1; return .ignored }                        // one step ahead is all there is
        pending = lastStepFoot == nil ? f : 1 - lastStepFoot!
        return .queued
    }

    /// He trips over his own feet: the buffer is lost and he cannot step for `stumbleTime`.
    mutating func trip() { trips += 1; stumbleLeft = RaceTuning.stumbleTime; pending = nil; tripped = true }

    /// The body is free to step: takes the buffered step (the foot to swing).
    mutating func takeStep() -> Int? {
        guard let f = pending else { return nil }
        pending = nil; lastStepFoot = f; steps += 1
        return f
    }

    /// A coasting body (past the line) steps with the alternate foot without a tap.
    mutating func forceStep() -> Int { let f = nextFoot; lastStepFoot = f; steps += 1; return f }

    mutating func tick(dt: Float) { sinceTap += dt; if stumbleLeft > 0 { stumbleLeft = max(0, stumbleLeft - dt); if stumbleLeft == 0 { tripped = false } } }
    mutating func dropBuffer() { pending = nil }
}

// MARK: - The race

nonisolated enum RacePhase: Equatable, Sendable {
    case countdown, running, finishing, results
}

nonisolated enum RaceEvent: Equatable, Sendable {
    case countdown(Int)                 // 3, 2, 1
    case go
    case step(racer: Int, foot: Int, stride: Float, rate: Float, final: Bool)
    case stumble(racer: Int)
    /// He tripped over his own feet (not a double tap): the stumble body move, no hint about tapping.
    case trip(racer: Int)
    case pauseBegan(racer: Int), pauseEnded(racer: Int)
    /// The racer takes off for a hurdle (the body does its existing hop; Race/Hurdles.swift), clears the bar he is over, or hits it (a `.trip` follows).
    case jump(racer: Int), hurdleCleared(racer: Int), hurdleHit(racer: Int)
    case finished(racer: Int, place: Int)
    case results
}

extension RaceEvent {
    /// The racer an event is about (nil = the whole race).
    var racer: Int? {
        switch self {
        case .step(let r, _, _, _, _), .stumble(let r), .trip(let r), .pauseBegan(let r), .pauseEnded(let r), .finished(let r, _), .jump(let r), .hurdleCleared(let r), .hurdleHit(let r): return r
        default: return nil
        }
    }
}

nonisolated struct RacePlacing: Equatable, Sendable {
    var racer: Int
    var name: String
    var place: Int
    /// Seconds from GO to the line; nil = did not finish.
    var time: Float?
    var isPlayer: Bool
}

nonisolated struct RaceRacer: Sendable {
    var name: String
    var stats: RacerStats
    var isPlayer: Bool
    var lane: Int
    var tap = RaceTapModel()
    /// Metres run (the progress from the start line): the sim's own count, replaced by the body's measured one when `measured` is set.
    var dist: Float = 0
    var measured: Float?
    var stepLeft: Float = 0
    var stepCount = 0
    var sinceStep: Float = 0
    var paused = false
    var pauseWanted = false
    var pauseLeft: Float = 0
    var pauseCooldown: Float = RaceTuning.pauseFreeStart
    var finishTime: Float?
    var place: Int?
    var coast = 0
    /// Trips taken in a turn (of `tap.trips`).
    var cornerTrips = 0
    // AI
    var aiTimer: Float = 0
    var effort: Float = 0.9
    var effortLeft: Float = 0
    var aiFoot = 0
    var rng = RaceRNG(seed: 1)

    // hurdles (Race/Hurdles.swift)
    /// Seconds the player's Jump press is still waiting for his feet to be planted.
    var jumpWant: Float = 0
    /// Seconds since take-off while he is in the air (nil = on the ground), and the landing recovery left after it.
    var airT: Float?
    var recover: Float = 0
    var nextHurdle = 0
    var hurdlesCleared = 0, hurdlesHit = 0
    /// Seconds of slowed steps left after a hit.
    var slow: Float = 0
    /// A rival's plan for the hurdle ahead: which one it is for, whether he will jump it, and how far ahead of the contact point he takes off.
    var planFor = -1
    var planJump = false
    var planLead: Float = 0.55
    var inJump: Bool { airT != nil || recover > 0 }

    /// The player's perk boost (never a rival's); capped at the fully trained stride / rate (RaceBoost.apply).
    var boost = RaceBoost.none
    var stride: Float { boost.apply(stride: RaceTuning.stride(waddle: stats.waddle), rate: 0).stride }
    var rate: Float { boost.apply(stride: 0, rate: RaceTuning.maxRate(waddle: stats.waddle)).rate }
    var finished: Bool { finishTime != nil }
    var stalled: Bool { !finished && sinceStep > RaceTuning.stallAfter }
}

nonisolated struct RaceSim: Sendable {
    private(set) var phase: RacePhase = .countdown
    private(set) var racers: [RaceRacer]
    /// Seconds since GO (0 during the countdown).
    private(set) var clock: Float = 0
    private(set) var countdownLeft: Float
    private(set) var beat = 3
    private var beatSent = false
    private(set) var firstFinishAt: Float?
    private(set) var placings: [RacePlacing] = []
    private(set) var events: [RaceEvent] = []
    let seed: UInt64
    /// The course (Race/RaceCourse.swift): `dist` is an arc length along it. The Puddle by default: the straight, exactly the race before courses.
    let course: RaceCourse
    /// The player's racer (always index 0).
    static let playerIndex = 0
    /// The auto-run assist jumps every hurdle for the player.
    var autoJumpPlayer = false

    var player: RaceRacer { racers[0] }
    var countdownTotal: Float { 3 * RaceTuning.countdownBeat }
    /// The GO flash is on for this long after GO.
    var goFlashing: Bool { phase != .countdown && clock < RaceTuning.goFlash }
    /// 3, 2, 1, then 0 = GO (the view shows the number or GO).
    var countdownNumber: Int { phase == .countdown ? beat : 0 }
    /// The racer is in a turn (the HUD's "ease off" hint).
    func inTurn(_ i: Int) -> Bool { racers.indices.contains(i) && course.turnRadius(at: racers[i].dist) != nil }

    init(player: RacerStats, playerName: String, rivals: [Rival], seed: UInt64, playerBoost: RaceBoost = .none, course: RaceCourse = .puddle) {
        self.seed = seed
        self.course = course
        var rs = [RaceRacer(name: playerName, stats: player, isPlayer: true, lane: RaceTuning.playerLane)]
        rs[0].boost = playerBoost; rs[0].tap.grace = playerBoost.grace
        // lanes: the player in the middle, the rivals either side
        let lanes = [0, 2, 3, 4].filter { $0 != RaceTuning.playerLane }
        for (k, r) in rivals.enumerated() { rs.append(RaceRacer(name: r.name, stats: r.stats, isPlayer: false, lane: lanes[min(k, lanes.count - 1)])) }
        for i in rs.indices {
            rs[i].rng = RaceRNG(seed: seed &* 6364136223846793005 &+ UInt64(i + 1) &* 1442695040888963407)
            rs[i].aiFoot = Int(rs[i].rng.next() * 2) % 2
            rs[i].aiTimer = rs[i].rng.range(0.02, 0.2)
        }
        racers = rs
        countdownLeft = 3 * RaceTuning.countdownBeat
    }

    mutating func takeEvents() -> [RaceEvent] { let e = events; events.removeAll(keepingCapacity: true); return e }

    /// The player's repeated-foot forgiveness window (accessibility assist; never lowers a boost's own).
    mutating func setPlayerGrace(_ g: Float) { racers[0].tap.grace = max(racers[0].tap.grace, g) }

    /// A tap of the player's foot button. Only meaningful while racing.
    @discardableResult
    mutating func playerTap(foot: Int) -> RaceTapModel.Outcome {
        guard phase == .running || phase == .finishing, !racers[0].finished else { return .ignored }
        let o = racers[0].tap.tap(foot, canStep: !racers[0].paused)
        if o == .stumble { events.append(.stumble(racer: 0)) }
        return o
    }

    /// A press of the Jump button: the take-off waits (up to `HurdleTuning.jumpBuffer`) for his feet to be planted. Only on a course with hurdles.
    @discardableResult
    mutating func playerJump() -> Bool {
        guard course.hasHurdles, phase == .running || phase == .finishing, !racers[0].finished, racers[0].airT == nil else { return false }          // (a press during the landing waits for the next take-off)
        racers[0].jumpWant = HurdleTuning.jumpBuffer
        return true
    }

    /// The body's measured progress (units from the start line), replacing the sim's own count for that racer.
    mutating func setMeasured(_ racer: Int, dist: Float) { if racers.indices.contains(racer) { racers[racer].measured = dist } }

    /// One fixed step. `bodyFree(i)`: racer i's body can take one more committed step (its buffer is empty; always true headless). `bodyBetween(i)`: his feet are
    /// planted between two steps, so a look-around can start. `bodyReady(i)`: his body is back on the track after a look-around.
    mutating func tick(dt: Float, bodyFree: (Int) -> Bool = { _ in true }, bodyReady: (Int) -> Bool = { _ in true }, bodyBetween: (Int) -> Bool = { _ in true }) {
        switch phase {
        case .countdown:
            countdownLeft = max(0, countdownLeft - dt)
            let n = max(1, Int((countdownLeft / RaceTuning.countdownBeat).rounded(.up)))        // 3, 2, 1
            if n != beat || !beatSent { beat = n; beatSent = true; if countdownLeft > 0 { events.append(.countdown(n)) } }
            if countdownLeft <= 0 { phase = .running; clock = 0; beat = 0; events.append(.go) }
            return
        case .results: return
        case .running, .finishing: break
        }
        clock += dt
        for i in racers.indices { tickRacer(i, dt: dt, free: bodyFree(i), ready: bodyReady(i), between: bodyBetween(i)) }
        if phase == .running, racers.contains(where: { $0.finished }) { phase = .finishing; firstFinishAt = clock }
        if phase == .finishing {
            let since = clock - (firstFinishAt ?? clock)
            // the stragglers' window: the course's (a tapping player always gets to finish), or the old 10 s when the player has stopped tapping
            let window = racers[0].sinceStep > RaceTuning.stragglerStall ? 2 * RaceTuning.finishGrace : course.stragglerGrace
            if racers.allSatisfy({ $0.finished }) || (racers[0].finished && since >= RaceTuning.finishGrace) || since >= window { endRace() }
        }
        if phase != .results, clock >= course.timeout { endRace() }
    }

    private mutating func tickRacer(_ i: Int, dt: Float, free: Bool, ready: Bool, between: Bool) {
        var r = racers[i]
        defer { racers[i] = r }
        r.tap.tick(dt: dt)
        r.sinceStep += dt
        if r.stepLeft > 0 { r.stepLeft = max(0, r.stepLeft - dt) }
        if r.slow > 0 { r.slow = max(0, r.slow - dt) }
        if r.jumpWant > 0 { r.jumpWant = max(0, r.jumpWant - dt) }
        // distance: the body's own measurement when it has one
        let before = r.measured ?? r.dist
        if let m = r.measured { r.dist = m }
        if !r.finished, r.dist >= course.length { cross(&r, i, before: before, dt: dt) }
        if r.finished { coastTick(&r, i, free: free); return }
        // hurdles: the flight and the landing (no steps meanwhile), the bar he reaches, a jump he starts
        if course.hasHurdles {
            hurdleTick(&r, i, dt: dt, free: free, between: between)
            if r.inJump { return }
        }

        // focus pause
        if r.paused {
            r.pauseLeft -= dt
            if r.pauseLeft <= 0 && ready { r.paused = false; r.pauseCooldown = RaceTuning.pauseCooldown; events.append(.pauseEnded(racer: i)) }
            return
        }
        r.pauseCooldown -= dt
        // a look-around comes up at random (by focus) and begins at the next moment the body is between steps
        if !r.pauseWanted, r.pauseCooldown <= 0, clock > RaceTuning.pauseFreeStart, r.dist < course.length - RaceTuning.pauseFreeFinish,
           r.rng.next() < RaceTuning.pauseHazard(focus: r.stats.focus) * dt { r.pauseWanted = true }
        if r.pauseWanted {
            // no new step is taken: the one under way ends, then he stops (the feet start a committed step the tick the last one ends, so a pause
            // can only begin between steps if none is being added)
            if r.stepLeft <= 0, free, between {
                r.pauseWanted = false
                r.paused = true; r.pauseLeft = RaceTuning.pauseTime; r.tap.dropBuffer()
                events.append(.pauseBegan(racer: i))
            }
            return
        }
        // rivals tap on their own
        if !r.isPlayer { aiTap(&r, dt: dt) }
        // take the buffered step when the body is free; first the trip roll: his own feet, plus the corner he is in at the pace he is going
        // (stride over the time since his last step: slower taps are safer) and any bump underfoot. One draw, so the straight rolls as it always did.
        if r.stepLeft <= 0, !r.tap.stumbling, free, r.tap.pending != nil {
            let pace = r.stride / max(r.sinceStep, 1 / r.rate)
            if r.stepCount >= RaceTuning.tripFreeSteps, r.dist < course.length - RaceTuning.pauseFreeFinish,
               r.rng.next() < RaceTuning.tripChance(waddle: r.stats.waddle, focus: r.stats.focus) + CourseTuning.hazard(course: course, at: r.dist, pace: pace, stats: r.stats) {
                if course.turnRadius(at: r.dist) != nil { r.cornerTrips += 1 }
                r.tap.trip(); r.sinceStep = 0
                events.append(.trip(racer: i))
                return
            }
        }
        if r.stepLeft <= 0, !r.tap.stumbling, free, let foot = r.tap.takeStep() {
            let k: Float = r.slow > 0 ? HurdleTuning.slowFactor : 1          // (after a hit on a hurdle: shorter, slower steps for a moment)
            r.stepLeft = 1 / (r.rate * k); r.sinceStep = 0; r.stepCount += 1
            if r.measured == nil { r.dist += r.stride * k * (r.stepCount == 1 ? RaceTuning.firstStepFraction : 1) }
            events.append(.step(racer: i, foot: foot, stride: r.stride * k, rate: r.rate * k, final: false))
        }
    }

    /// The hurdles of one racer for one step: flight and landing, the bar he has reached (cleared in the air, else hit), a take-off (the player's Jump press,
    /// a rival's plan, or the auto-run assist). Only called on a course with hurdles, so the straight courses draw nothing new.
    private mutating func hurdleTick(_ r: inout RaceRacer, _ i: Int, dt: Float, free: Bool, between: Bool) {
        let hs = course.hurdles
        if var t = r.airT {
            let before = t
            t += dt
            if r.measured == nil { r.dist += HurdleTuning.hopDistance * (min(max(t, 0), HurdleTuning.airTime) - min(max(before, 0), HurdleTuning.airTime)) / HurdleTuning.airTime }          // (headless: the hop carries him; with a body it is measured)
            if t >= HurdleTuning.airTime { r.airT = nil; r.recover = HurdleTuning.recover } else { r.airT = t }
        } else if r.recover > 0 { r.recover = max(0, r.recover - dt) }
        // the bar: his front reaches it `contactLead` before his centre does
        while r.nextHurdle < hs.count, r.dist >= hs[r.nextHurdle] - HurdleTuning.contactLead {
            r.nextHurdle += 1
            if let t = r.airT, t >= 0, HurdleTuning.clearWindow.contains(t / HurdleTuning.airTime) {
                r.hurdlesCleared += 1
                events.append(.hurdleCleared(racer: i))
            } else {
                r.hurdlesHit += 1; r.slow = HurdleTuning.slowTime; r.jumpWant = 0
                r.tap.trip(); r.sinceStep = 0
                events.append(.hurdleHit(racer: i))
                events.append(.trip(racer: i))
            }
        }
        guard r.nextHurdle < hs.count, !r.inJump, !r.tap.stumbling else { return }
        var go = r.jumpWant > 0
        if !r.isPlayer || autoJumpPlayer {
            // a rival looks at the bar once it is near, decides by skill whether he will jump it, and takes off a little ahead of it
            if r.planFor != r.nextHurdle, hs[r.nextHurdle] - r.dist < HurdleTuning.lookAhead {
                r.planFor = r.nextHurdle
                let skill = 0.5 * RaceTuning.clamp01(r.stats.focus) + 0.5 * RaceTuning.clamp01(r.stats.waddle)
                r.planJump = r.isPlayer || r.rng.next() < HurdleTuning.rivalSuccess(skill: skill)
                r.planLead = r.rng.range(0.5, 0.6)
            }
            if r.planFor == r.nextHurdle, r.planJump, r.dist >= hs[r.nextHurdle] - HurdleTuning.contactLead - r.planLead { go = true }
        }
        if go, r.stepLeft <= 0, free, between, !r.paused {
            r.airT = -HurdleTuning.crouch; r.jumpWant = 0          // (the crouch first, then the flight)
            events.append(.jump(racer: i))
        }
    }

    /// A rival's finger: alternating taps at the trained rate times an effort that wanders (0.82 ... 1.0), a little irregular.
    private func aiTap(_ r: inout RaceRacer, dt: Float) {
        r.effortLeft -= dt
        if r.effortLeft <= 0 { r.effortLeft = r.rng.range(0.6, 1.4); r.effort = r.rng.range(0.82, 1.0) }
        r.aiTimer -= dt
        if r.aiTimer <= 0 {
            _ = r.tap.tap(r.aiFoot, canStep: !r.paused)
            r.aiFoot = 1 - r.aiFoot
            // a focused rival eases off for a bend (the step period stretches toward his safe speed); on a straight the period is as it always was
            let brake = CourseTuning.rivalBrake(course: course, at: r.dist, stats: r.stats, nominal: r.stride * r.rate * r.effort)
            let period = brake == 1 ? 1 / (r.rate * r.effort) : brake / (r.rate * r.effort)
            r.aiTimer += period * r.rng.range(0.92, 1.12)
        }
    }

    private mutating func cross(_ r: inout RaceRacer, _ i: Int, before: Float, dt: Float) {
        let span = max(r.dist - before, 1e-4)
        let f = min(max((course.length - before) / span, 0), 1)
        r.finishTime = clock - dt * (1 - f)
        r.place = racers.compactMap(\.place).count + 1
        r.coast = 0
        r.tap.dropBuffer()
        events.append(.finished(racer: i, place: r.place!))
    }

    /// A finished racer slows to a stop with a few steps of his own.
    private mutating func coastTick(_ r: inout RaceRacer, _ i: Int, free: Bool) {
        if r.coast < RaceTuning.coastSteps, r.stepLeft <= 0, free {
            let k = r.coast
            r.coast += 1
            r.stepLeft = 1 / (r.rate * 0.8); r.stepCount += 1
            if r.measured == nil { r.dist += r.stride * RaceTuning.coastStride(k) }
            events.append(.step(racer: i, foot: r.tap.forceStep(), stride: r.stride * RaceTuning.coastStride(k), rate: r.rate * 0.8, final: k == RaceTuning.coastSteps - 1))
        }
    }

    private mutating func endRace() {
        // unfinished racers take the places after the finishers, by distance
        let order = racers.indices.sorted { a, b in
            switch (racers[a].finishTime, racers[b].finishTime) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return racers[a].dist > racers[b].dist
            }
        }
        placings = order.enumerated().map { k, i in
            racers[i].place = k + 1
            return RacePlacing(racer: i, name: racers[i].name, place: k + 1, time: racers[i].finishTime, isPlayer: racers[i].isPlayer)
        }
        phase = .results
        events.append(.results)
    }

    // MARK: results

    var playerPlace: Int? { placings.first(where: \.isPlayer)?.place }
    /// Drops the player earns on this course (0 until the results are in).
    var playerDrops: Int { playerPlace.map { RaceTuning.drops(place: $0, tier: course.tier) } ?? 0 }
    var playerWon: Bool { playerPlace == 1 }
}
