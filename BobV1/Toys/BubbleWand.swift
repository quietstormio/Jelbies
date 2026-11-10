//
//  BubbleWand.swift
//  The bubble wand, a play-mode toy (registered through PlayToyRegistry; bought once in the shop). The wand sits at the bottom of the screen. TAP AND HOLD the wand (also the VoiceOver
//  action; no microphone, user 2026-11-06): bubbles stream out, rise, drift into the room and pop on their own after a few seconds.
//  The Jelbies play: some WATCH a bubble (turn and look), some CHASE one (walk under it, hop, pop it with the head: a soft pop, a sparkle, a giggle),
//  at most two chase at once so it never looks like a drill; now and then two want the same bubble and one gets there first. A drifting bubble that
//  touches a body pops too. Three pops in a row (within 8 s) give hearts. Bubbles draw in Toys/BubbleOverlay.swift (a CALayer overlay, no blur/material).
//  Pure part: BubbleField (the sim). All time is the wand's own clock (steps of the fixed tick), so tests are deterministic.
//

import Foundation
import Observation
import simd
import QuartzCore
import CoreGraphics

/// One Jelbie as the wand sees him.
@MainActor
struct BubbleJelly {
    var id: Int
    var brain: BlobBrain
    var sim: SoftBody
    /// A park visitor: chases and pops bubbles but is not given a spot on the leash line.
    var free = false
}

nonisolated enum BubbleTuning {
    /// Heart (attention) gained per bubble a Jelbie pops: a slight lift (~30 pops fill a whole empty heart).
    static let attentionPerPop: Float = 0.03
    static let spawnPerSecond: ClosedRange<Float> = 1.5...6.5
    static let holdStrength: Float = 0.6
    static let contactRadius: Float = 0.62          // a body touching a drifting bubble
    static let contactMaxY: Float = 1.7
    nonisolated(unsafe) static var contactPopChance: Float = 0.12          // (var: tests set 1; 2026-11-07: rare, a pop should be a Jelbie's deliberate hop, not a bubble brushing a body)
    static let hopReach: Float = 0.33              // how far (floor distance) the bubble may be from him when he starts the hop: the hop is on the spot, so the bubble must be over his head
    static let contactSlack: Float = 0.24          // crown-to-bubble-centre distance for the pop = bubble radius * 0.95 + this (the bubble touches the crown)
    static let hopMinY: Float = 0.9
    static let chaseMaxY: Float = 1.75
    static let popGap: Float = 0.4                 // seconds between two hop starts anywhere: every pop is readable on its own (0.7 before 2026-11-09)
    static let classicPopGap: Float = 0.7
    static let chaseRoll: Float = 0.85             // (0.72 before)
    static let classicChaseRoll: Float = 0.72
    static let walkSpeed: Float = 0.7
    /// Test switches: `classic` restores the old targeting and moves (the BEFORE numbers); `forceMove` makes every chase use that move (the feet scenarios).
    nonisolated(unsafe) static var classic = false
    nonisolated(unsafe) static var forceMove: BubblePopMove?
    /// The crown's rise above its standing height in each move (measured by BubblePlayTests.testApexTable; the bubble waits at crown + apex, the aim band is around it). The skip pops with the body (it waits at belly height, 1.0).
    static let apex: [BubblePopMove: Float] = [.header: 0.24, .leap: 0.19, .bounce: 0.21, .flap: 0.35, .skip: 0.15]
    /// How far from the bubble (floor) he stands before the move: 0 = under it.
    static let standoff: [BubblePopMove: Float] = [.header: 0, .leap: 0.6, .bounce: 0, .flap: 0.25, .skip: 0.65]
    static let leapRange: ClosedRange<Float> = 0.35...0.9
    static let lightBeat: Float = 0.18
    static let aimMax: Float = 3.5                 // how long he waits under a bubble for it to be in reach
    static let maxChasers = 3          // (2026-11-07: all of them want in)
    static let thinkEvery: ClosedRange<Float> = 0.3...0.7
    static let streakWindow: Float = 8
    static let streakForHearts = 2
    static let fxLife: Float = 0.36
    static let price = 40
}

@MainActor
@Observable
final class BubbleWand: PlayToy {
    static let shared = BubbleWand()

    nonisolated let toyID = "bubbleWand"
    let title = "Bubble wand"
    let symbol = "bubbles.and.sparkles"
    var price: Int { StoreCatalog.item(storeID)?.price ?? BubbleTuning.price }
    var storeID: String { "toy-bubbleWand" }

    // MARK: state

    private(set) var active = false
    /// Tap-and-hold on the wand (set by the overlay's gesture / the VoiceOver action).
    var holding = false
    /// 0...1 how hard the player is blowing right now (mic, hold or demo): the wand's meter.
    private(set) var strength: Float = 0
    /// The view size the overlay draws in (points); the mouth and the pixel scale follow it.
    @ObservationIgnored var viewSize = CGSize(width: 440, height: 956) { didSet { if viewSize != oldValue { mouthCache = nil } } }

    @ObservationIgnored private(set) var field = BubbleField()
    struct PopFX: Equatable { var pos: SIMD3<Float>; var born: Float; var size: Float }
    @ObservationIgnored private(set) var fx: [PopFX] = []
    @ObservationIgnored private(set) var clock: Float = 0
    /// Simulated blow for captures / tests: strength by time since `start` (nil = off).
    @ObservationIgnored var demo: ((Float) -> Float)?
    @ObservationIgnored private var demoStart: Float = 0
    @ObservationIgnored private var holdT: Float = 0
    @ObservationIgnored private var burstUntil: Float = -1
    @ObservationIgnored private var spawnAcc: Float = 0
    @ObservationIgnored private var bloopAt: Float = -9
    @ObservationIgnored private var mouthCache: SIMD3<Float>?
    @ObservationIgnored private var mouthBlend: Float = -1
    @ObservationIgnored private var states: [Int: JState] = [:]
    @ObservationIgnored private weak var care: GameCare?
    /// The play area (2026-11-07): the floor the play camera shows above the HUD; every awake Jelbie keeps a spot in it for the whole mode (BlobBrain.bubbleLeash).
    @ObservationIgnored private var areaCache: (size: CGSize, lo: SIMD2<Float>, hi: SIMD2<Float>)?
    @ObservationIgnored private var slots: [Int: SIMD2<Float>] = [:]
    @ObservationIgnored private var slotKey: [Int] = []
    @ObservationIgnored private var slotSize = CGSize.zero
    /// The happy reaction after a pop, once he has landed: when, and whether it also gives hearts.
    @ObservationIgnored private var cheers: [Int: (at: Float, hearts: Bool)] = [:]
    @ObservationIgnored private var lastHopStart: Float = -9
    @ObservationIgnored private var leashed: [BlobBrain] = []
    @ObservationIgnored private var superviseAt: Float = 0
    /// Totals (tests, report).
    @ObservationIgnored private(set) var popsByJelly: [Int: Int] = [:]
    @ObservationIgnored private(set) var chases = 0
    @ObservationIgnored private(set) var watches = 0
    @ObservationIgnored private(set) var bumps = 0
    @ObservationIgnored private(set) var nudges = 0
    @ObservationIgnored private(set) var hopPops = 0
    @ObservationIgnored private(set) var contactPops = 0
    @ObservationIgnored private(set) var heartBursts = 0
    /// Per-chase records and per-move counts (tests, report): the outcome, claim -> end seconds, seconds of it spent walking.
    struct ChaseRecord { var popped: Bool; var seconds: Float; var walking: Float; var move: BubblePopMove }
    @ObservationIgnored private(set) var chaseRecords: [ChaseRecord] = []
    @ObservationIgnored private(set) var claimToPop: [Float] = []
    @ObservationIgnored private(set) var movePops: [BubblePopMove: Int] = [:]
    @ObservationIgnored private(set) var moveStarts: [BubblePopMove: Int] = [:]
    @ObservationIgnored private(set) var extraPops = 0
    /// Why chases ended and which fallbacks ran (tests, report).
    @ObservationIgnored private(set) var diag: [String: Int] = [:]
    private func note(_ k: String) { diag[k, default: 0] += 1 }
    /// Test/debug: one line per Jelbie (mode, move, bubble, script).
    func debugLine(_ js: [BubbleJelly]) -> String {
        js.map { j in
            let st = states[j.id]
            let bub = st.flatMap { field.bubble($0.bubble) }
            return "J\(j.id) \(st.map { "\($0.mode)/\($0.move)" } ?? "-") b=\(bub.map { String(format: "(%.2f,%.2f,%.2f)", $0.pos.x, $0.pos.y, $0.pos.z) } ?? "-") at(\(String(format: "%.2f,%.2f", j.brain.position.x, j.brain.position.y))) \(j.brain.scriptKindName) idle=\(j.brain.idleState.kind.map { $0.rawValue } ?? "-") crown \(String(format: "%.2f", j.sim.centroid().y + BobShape.H * 0.5))"
        }.joined(separator: " | ")
    }
    /// The bubble ids somebody is going for now (a test checks nobody shares one).
    var activeTargets: [Int] { states.values.filter { $0.mode != .idle }.map(\.bubble) }

    private enum Mode { case idle, spot, chase, aim, hop }
    private struct JState {
        var mode: Mode = .idle
        var bubble = -1
        var until: Float = 0
        var hopAt: Float = 0
        var thinkAt: Float = 0
        var retargetAt: Float = 0
        var chaseStart: Float = 0
        var hopStart: Float = 0
        var tries = 0
        var streak = 0
        var lastPop: Float = -99
        var move: BubblePopMove = .header
        var lookUntil: Float = 0
        var goal: SIMD2<Float>?
        var goalTries = 0
        var aimAt: Float = 0
        var claimAt: Float = 0
        var walkTime: Float = 0
        var done = false          // the target is popped (a bounce goes on for its extras)
        var extra = 0
        var startFails = 0
    }

    nonisolated deinit {}
    init() {}

    // MARK: PlayToy

    /// The picker's call: Play mode on with the wand (GameCare.beginPlay(wand:) -> `begin`).
    func activate(care: GameCare) { care.beginPlay(wand: self) }
    /// Play mode is up (or a test): the wand comes out.
    func begin(care: GameCare) { activate(care: Optional(care)) }          // (the optional overload: the plain one is the picker's entry and would re-enter beginPlay)
    func activate(care: GameCare?) {
        self.care = care
        guard !active else { return }
        active = true
        reset()
    }
    func deactivate() {
        if let c = care, c.play.active { c.endPlay() }          // (Done / the picker's put-away: Play mode goes too; endPlay calls back, then `active` is already false)
        releaseLeash()
        guard active else { return }
        active = false
        holding = false
        reset()
        states.removeAll()
    }
    /// Test seam: back to a fresh, put-away wand (counters too).
    func resetForTests() {
        BubbleTuning.contactPopChance = 0.12
        deactivate(); active = false; clock = 0; demo = nil; burstUntil = -1; states.removeAll(); cheers = [:]; lastHopStart = -9; field = BubbleField()
        popsByJelly = [:]; diag = [:]; chaseRecords = []; claimToPop = []; movePops = [:]; moveStarts = [:]; extraPops = 0; nudges = 0; hopPops = 0; chases = 0; watches = 0; bumps = 0; contactPops = 0; heartBursts = 0; lastQuietPop = -9
    }
    /// Test seam: a bubble right there.
    @discardableResult func insertBubble(at p: SIMD3<Float>, radius: Float = 0.2) -> Int? { field.insert(at: p, radius: radius) }
    func clearBubbles() { field.clear() }
    private func reset() {
        field.clear(); fx.removeAll(); spawnAcc = 0; strength = 0; holdT = 0
    }

    /// `-BubbleDemo 1`: the wand comes out by itself and a simulated blow plays (pulses of 2.5 s every 4 s). `2` blows without pause.
    func startDemo(mode: Int, care: GameCare?) {
        if let care, care.canPlay { care.beginPlay(wand: self) } else { activate(care: care) }
        demoStart = clock
        demo = mode == 2 ? { _ in 0.7 } : { t in t.truncatingRemainder(dividingBy: 4) < 2.5 ? 0.45 + 0.4 * sinf(t * 2.1).magnitude : 0 }
    }

    /// VoiceOver / switch control: a stream of bubbles for `seconds` without holding.
    func burst(seconds: Float) { burstUntil = clock + seconds }
    /// The Done chip: put the wand away.
    func stop() { deactivate() }

    // MARK: the mouth

    /// Where bubbles leave the wand: the floor under the bottom of the screen, low and in front.
    var mouth: SIMD3<Float> {
        if mouthBlend != GameCamera.playBlend { mouthBlend = GameCamera.playBlend; mouthCache = nil }          // (the play camera is easing in)
        if let m = mouthCache { return m }
        let s = viewSize
        var p = SIMD2<Float>(0, 4.2)
        if s.width > 1, let f = GameCamera.floorPoint(screen: CGPoint(x: s.width * 0.5, y: s.height * 0.94), size: s) { p = f }
        p.y = min(p.y, 5.6)
        let m = SIMD3<Float>(p.x, 0.35, p.y)
        mouthCache = m
        return m
    }

    // MARK: the step (once per fixed step; MelonStage.hopTick)

    func tick(jellies: [BubbleJelly], dt: Float, haptics: HapticDriver? = nil) {
        guard active else { return }
        clock += dt; dtNow = dt
        // 1. how hard is he blowing?
        var s: Float = 0
        if let d = demo { s = d(clock - demoStart) }
        if clock < burstUntil { s = max(s, BubbleTuning.holdStrength) }
        if holding { holdT += dt; s = max(s, min(BubbleTuning.holdStrength + 0.3 * holdT, 0.9)) } else { holdT = 0 }
        strength = s
        // 2. bubbles out
        if s > 0.05 {
            let rate = BubbleTuning.spawnPerSecond.lowerBound + (BubbleTuning.spawnPerSecond.upperBound - BubbleTuning.spawnPerSecond.lowerBound) * s
            spawnAcc += rate * dt
            while spawnAcc >= 1 { spawnAcc -= 1; field.spawn(strength: s, at: mouth) }
            if clock - bloopAt > 0.45 { bloopAt = clock; AudioHub.shared.play(.bubbleBloop, x: 0, volume: 0.6 + 0.4 * s) }
        } else { spawnAcc = 0 }
        // 3. they float; the ones that run out of time pop alone (softer, no sparkle credit)
        for b in field.step(dt: dt) { addFX(b, quiet: true) }
        fx.removeAll { clock - $0.born > BubbleTuning.fxLife }
        // 4. the Jelbies: first they stay in view, then they play
        leashTick(jellies)
        cheerTick(jellies)
        jelliesTick(jellies)
        // 5. a soft purr under the thumbs while blowing
        if let h = haptics {
            h.setWarm(true)
            let i: Float = s > 0.05 ? 0.10 + 0.22 * s : 0
            h.update(now: CACurrentMediaTime(), petIntensity: i, petSharpness: 0.08, squishIntensity: 0, squishSharpness: 0.5)
        }
        self.haptics = haptics
    }
    @ObservationIgnored private var haptics: HapticDriver?
    @ObservationIgnored private var dtNow: Float = 1.0 / 60
    /// The stage keeps the haptic engine warm exactly while the wand is blowing.
    var hapticsWanted: Bool { active }

    // MARK: Jelbies

    private func floorPos(_ b: Bubble) -> SIMD2<Float> { SIMD2(b.pos.x, b.pos.z) }

    private func jelliesTick(_ js: [BubbleJelly]) {
        guard !field.bubbles.isEmpty || states.values.contains(where: { $0.mode != .idle }) else { return }
        // passive contact: a drifting bubble that really touches a body mostly just bounces off (rarely pops); a bubble somebody is going for is left alone, his hop pops it
        for j in js {
            let p = j.brain.position
            for b in field.bubbles where b.pos.y < BubbleTuning.contactMaxY && !b.touched && b.claimedBy < 0 {
                if simd_distance(floorPos(b), p) < BubbleTuning.contactRadius + b.radius * 0.5 {
                    if Float.random(in: 0..<1) < BubbleTuning.contactPopChance { contactPops += 1; popBubble(b.id, by: j, hopped: false) }
                    else { field.nudge(b.id, awayFrom: p); nudges += 1 }          // (most just bounce off him and float on)
                }
            }
        }
        let chasers = states.values.filter { $0.mode != .idle }.count
        var chasing = chasers
        for j in js {
            var st = states[j.id] ?? JState(thinkAt: clock + Float.random(in: 0.2...0.8))
            defer { states[j.id] = st }
            if st.mode != .idle, case .walk = j.brain.script { st.walkTime += dtNow }
            if BubbleTuning.classic { classicTick(j, &st, &chasing, js) } else { playTick(j, &st, &chasing, js) }
        }
    }

    /// The BEFORE behaviour, verbatim (BubbleTuning.classic).
    private func classicTick(_ j: BubbleJelly, _ st: inout JState, _ chasing: inout Int, _ js: [BubbleJelly]) {
        let b = j.brain
        switch st.mode {
        case .idle, .spot:
            guard clock >= st.thinkAt else { return }
            st.thinkAt = clock + Float.random(in: BubbleTuning.thinkEvery)
            guard b.bubbleFree, !field.bubbles.isEmpty else { return }
            let roll = Float.random(in: 0..<1)
            if roll < BubbleTuning.classicChaseRoll, chasing < BubbleTuning.maxChasers, let target = classicPick(for: j) {
                st.mode = .chase; st.bubble = target.id; st.until = clock + 6.5; st.retargetAt = 0; st.chaseStart = clock; st.tries = 0; st.claimAt = clock; st.walkTime = 0; st.done = false; st.move = .header
                field.claim(target.id, by: j.id)
                chasing += 1; chases += 1
            } else if roll < 0.92, let t = nearest(to: b.position) {
                watches += 1
                _ = b.bubbleWatch(t, hold: Float.random(in: 1.0...2.2), excited: Float.random(in: 0..<1) < 0.7)
                st.thinkAt = clock + Float.random(in: 0.9...1.8)
            } else {
                st.thinkAt = clock + Float.random(in: 0.6...1.4)          // not every bubble needs a Jelbie
            }
        case .chase:
            // 1. walk under it (a little ahead of a drifting bubble)
            guard let bub = field.bubble(st.bubble), clock < st.until, b.bubbleStillMine, bub.pos.y < BubbleTuning.chaseMaxY + 0.3 else {
                trace("jelly \(j.id) gives up chase t=\(String(format: "%.1f", clock))")
                endChase(&st, j); return }
            let d = simd_distance(floorPos(bub), b.position)
            if clock - lastTrace > 1 { lastTrace = clock; trace("jelly \(j.id) chasing d=\(String(format: "%.2f", d)) script none \(b.scriptIsNone) pending \(b.pending != nil) idle \(String(describing: b.idleState.kind))") }
            if d < 1.0, b.scriptIsNone, b.pending == nil, b.idleState.kind == nil {
                // 2. he is there: stop, turn and look at it (the anticipation); the leash's idle moves are held off while he aims
                st.mode = .aim; st.until = clock + BubbleTuning.aimMax; st.retargetAt = clock + 0.5
                b.bubbleHold = true
                _ = b.bubbleWatch(floorPos(bub), hold: 0.45, excited: false)
            } else if clock >= st.retargetAt {
                st.retargetAt = clock + 0.45
                b.bubbleGo(clampToArea(floorPos(bub) + SIMD2(bub.vel.x, bub.vel.z) * 0.6))
            }
        case .aim:
            guard let bub = field.bubble(st.bubble), clock < st.until, b.bubbleStillMine else { endChase(&st, j); return }
            guard b.scriptIsNone, b.pending == nil, b.idleState.kind == nil else { return }          // (still turning / walking a correction)
            // where the bubble will be when the top of a hop comes (BlobBrain.tossHeaderLead): over his head, at the height of the crown at the top of the hop?
            let pp = bub.pos + bub.vel * BlobBrain.tossHeaderLead
            let pxz = SIMD2(pp.x, pp.z)
            let apexY = crownY(j) + BlobBrain.tossApex
            let band = 0.12 + 0.5 * bub.radius
            if simd_distance(pxz, b.position) > BubbleTuning.hopReach {
                if clock >= st.retargetAt { st.retargetAt = clock + 0.4; b.bubbleGo(clampToArea(pxz)) }          // (a small step to stand right under it)
            } else if abs(pp.y - apexY) <= band + 0.08, pp.y >= BubbleTuning.hopMinY, clock - lastHopStart >= BubbleTuning.classicPopGap {
                if b.bubbleHeaderHop(j.sim) {
                    st.mode = .hop; st.hopStart = clock; lastHopStart = clock
                    trace("jelly \(j.id) hops at bubble \(bub.id) y=\(String(format: "%.2f", bub.pos.y)) apex \(String(format: "%.2f", apexY))")
                }
            }          // (else: it is still above / below the reach of a hop: he waits under it, looking up)
        case .hop:
            guard let bub = field.bubble(st.bubble), b.attached, !b.held, b.social == nil else { endChase(&st, j); return }          // (it popped on its own, or somebody else got it)
            let age = clock - st.hopStart
            // the pop happens at the top of the hop, when the bubble is on the crown (never from a distance)
            if age >= 0.14 {
                let c = SIMD3<Float>(b.position.x, crownY(j), b.position.y)
                if simd_distance(c, bub.pos) <= bub.radius * 0.95 + BubbleTuning.contactSlack {
                    for o in js where o.id != j.id {          // two after the same one: the other gets a bump instead
                        if var os = states[o.id], os.mode != .idle, os.bubble == bub.id {
                            os.mode = .idle; os.thinkAt = clock + 2; states[o.id] = os; o.brain.bubbleHold = false
                            o.brain.face(.hopeful, hold: 1.4); bumps += 1
                            AudioHub.shared.play(.boop, jelly: o.id, x: o.brain.px, volume: 0.25)
                        }
                    }
                    popBubble(bub.id, by: j, hopped: true)
                    st.done = true; claimToPop.append(clock - st.claimAt); movePops[.header, default: 0] += 1
                    endChase(&st, j); return
                }
            }
            if age > 0.7 {          // missed (it drifted): a hopeful look, one more try
                b.face(.hopeful, hold: 1.0)
                st.tries += 1
                if st.tries < 2, !b.tossBusy { st.mode = .aim; st.until = clock + 2.0; st.retargetAt = clock + 0.3 } else { endChase(&st, j) }
            }
        }
    }

    // MARK: the play (2026-11-09: one particular bubble, spot it, go, hop to pop)

    /// The crown's height standing still: the bubble waits at this + the move's apex.
    private func crownRest(_ j: BubbleJelly) -> Float { j.sim.restCentroid.y + j.sim.floorY + BobShape.H * 0.5 }

    /// Which move for this bubble: by its height against his crown, the species, and a little chance. `BubbleTuning.forceMove` overrides (tests).
    private func planMove(_ j: BubbleJelly, _ bub: Bubble) -> BubblePopMove {
        if let f = BubbleTuning.forceMove { return f }
        let crown = crownRest(j)
        let winged = j.brain.feature == .wings && !j.brain.wingsFolded
        var w: [(BubblePopMove, Float)] = []
        if bub.pos.y < crown + 0.15 { w = [(.skip, 3), (.leap, 1.5), (.bounce, 0.5)] }          // (at or below the crown: a skip into it)
        else if bub.pos.y > crown + 0.2 && winged { w = [(.flap, 3), (.leap, 1.5), (.bounce, 1)] }
        else { w = [(.leap, 3), (.header, 1.5), (.bounce, 1.5)] + (winged ? [(.flap, 1)] : []) }
        let total = w.reduce(0) { $0 + $1.1 }
        var r = Float.random(in: 0..<total)
        for (m, x) in w { if r < x { return m }; r -= x }
        return .header
    }
    private func reachHeight(_ m: BubblePopMove, _ j: BubbleJelly) -> Float {
        m == .skip ? 1.0 : crownRest(j) + (BubbleTuning.apex[m] ?? 0.12)
    }
    /// Where he stands for the move: `standoff` from the bubble along the way an idle Jelbie faces (toward the camera), so the travelling hop that follows goes at the bubble without a turn.
    private func idealStand(_ j: BubbleJelly, _ bub: Bubble, _ off: Float) -> SIMD2<Float> {
        let yaw = j.brain.faceCameraYaw()
        return floorPos(bub) - SIMD2(sinf(yaw), cosf(yaw)) * off
    }
    private func standPoint(_ j: BubbleJelly, _ bub: Bubble, _ m: BubblePopMove) -> SIMD2<Float> {
        let off = BubbleTuning.standoff[m] ?? 0
        return clampToArea(off > 0 ? idealStand(j, bub, off) : floorPos(bub))
    }
    private func standOK(_ j: BubbleJelly, _ bub: Bubble, _ m: BubblePopMove) -> Bool {
        let off = BubbleTuning.standoff[m] ?? 0
        guard off > 0 else { return true }
        let ideal = idealStand(j, bub, off)
        guard simd_distance(clampToArea(ideal), ideal) < 0.15 else { return false }
        if m == .skip {          // the skip's two hops end 0.7 u from the stand-off: that must still be floor he can stand on
            let yaw = j.brain.faceCameraYaw()
            let end = ideal + SIMD2(sinf(yaw), cosf(yaw)) * 0.7
            return simd_distance(j.brain.fixed(end), end) < 0.1
        }
        return true
    }

    private func startPlayChase(_ j: BubbleJelly, _ st: inout JState, _ target: Bubble) {
        st.mode = .spot; st.bubble = target.id; st.until = clock + 6.5; st.retargetAt = 0; st.chaseStart = clock; st.claimAt = clock
        st.tries = 0; st.walkTime = 0; st.done = false; st.extra = 0; st.goal = nil; st.goalTries = 0; st.startFails = 0
        st.move = planMove(j, target)
        if (st.move == .leap || st.move == .skip || st.move == .flap), !standOK(j, target, st.move) { note("fallback standNotOK \(st.move)"); st.move = BubbleTuning.forceMove ?? .header }          // (no floor to stand off on: a header under it)
        field.claim(target.id, by: j.id)
        field.setReach(target.id, y: reachHeight(st.move, j))
        // spot it: turn and look at that bubble with the excited face, then go
        let hold = Float.random(in: 0.35...0.5)
        st.lookUntil = clock + hold
        _ = j.brain.bubbleWatch(floorPos(target), hold: hold, excited: true)
    }

    private func playTick(_ j: BubbleJelly, _ st: inout JState, _ chasing: inout Int, _ js: [BubbleJelly]) {
        let b = j.brain
        switch st.mode {
        case .idle:
            guard clock >= st.thinkAt else { return }
            st.thinkAt = clock + Float.random(in: BubbleTuning.thinkEvery)
            guard b.bubbleFree, !field.bubbles.isEmpty else { return }
            let roll = Float.random(in: 0..<1)
            if roll < BubbleTuning.chaseRoll, chasing < BubbleTuning.maxChasers, let target = pickTarget(for: j, among: js) {
                startPlayChase(j, &st, target)
                chasing += 1; chases += 1
            } else if roll < 0.97, let t = nearest(to: b.position) {
                watches += 1
                _ = b.bubbleWatch(t, hold: Float.random(in: 1.0...2.2), excited: Float.random(in: 0..<1) < 0.7)
                st.thinkAt = clock + Float.random(in: 0.9...1.8)
            } else {
                st.thinkAt = clock + Float.random(in: 0.6...1.4)
            }
        case .spot:
            guard field.bubble(st.bubble) != nil, clock < st.until, b.bubbleStillMine else { endChase(&st, j); return }
            if clock >= st.lookUntil { st.mode = .chase; st.retargetAt = 0 }
        case .chase:
            guard let bub = field.bubble(st.bubble), clock < st.until, b.bubbleStillMine, bub.pos.y < BubbleTuning.chaseMaxY + 0.3 else { endChase(&st, j); return }
            let stand = standPoint(j, bub, st.move)
            let quiet = b.scriptIsNone && b.pending == nil && b.idleState.kind == nil
            let ds = simd_distance(stand, b.position)
            let arrive: Float = (BubbleTuning.standoff[st.move] ?? 0) > 0 ? 0.14 : 0.3
            if quiet, ds < arrive || (st.goalTries >= 3 && simd_distance(floorPos(bub), b.position) < 1.3) {
                st.mode = .aim; st.aimAt = clock; st.until = clock + BubbleTuning.aimMax; st.retargetAt = clock + 0.3
                b.bubbleHold = true
            } else if clock >= st.retargetAt {
                // go: only when the goal moved more than 0.35 from the last one issued (the walk is not restarted twice a second), or the walk ended short of it
                if st.goal == nil || simd_distance(st.goal!, stand) > 0.35 || (quiet && ds >= arrive) {
                    st.retargetAt = clock + 0.5
                    if quiet { st.goalTries += 1 }
                    st.goal = stand
                    b.bubbleGo(stand)
                }
            }
        case .aim:
            guard let bub = field.bubble(st.bubble), clock < st.until, b.bubbleStillMine else {
                note("aimEnd \(field.bubble(st.bubble) == nil ? "bubbleGone" : clock >= st.until ? "timeout" : "notMine") \(st.move)"); endChase(&st, j); return }
            guard b.scriptIsNone, b.pending == nil, b.idleState.kind == nil else { return }
            let pp = bub.pos + bub.vel * BlobBrain.tossHeaderLead
            let pxz = SIMD2(pp.x, pp.z)
            let dh = simd_distance(pxz, b.position)
            let crown = crownY(j)
            let band = 0.12 + 0.5 * bub.radius + 0.08
            let faceErr = b.bubbleYawError(to: pxz)
            func fits(_ m: BubblePopMove) -> Bool {
                let apexY = crown + (BubbleTuning.apex[m] ?? 0.1)
                switch m {
                case .header, .bounce: return dh <= BubbleTuning.hopReach && abs(pp.y - apexY) <= band && pp.y >= BubbleTuning.hopMinY
                case .flap: return b.flapHopAllowed && dh <= BubbleTuning.hopReach + 0.2 && abs(pp.y - apexY) <= band + 0.1
                case .leap: return BubbleTuning.leapRange.contains(dh) && abs(pp.y - apexY) <= band && pp.y >= BubbleTuning.hopMinY
                case .skip: return dh >= 0.3 && dh <= 0.85 && pp.y < crown - 0.05 && pp.y >= 0.7
                }
            }
            func travels(_ m: BubblePopMove) -> Bool { m == .leap || m == .skip || m == .flap }
            var order: [BubblePopMove] = [st.move]
            for m in [BubblePopMove.header, .leap, .bounce, .skip, .flap] where m != st.move && BubbleTuning.forceMove == nil { order.append(m) }
            guard let m = order.first(where: fits) else {
                if clock - st.hopStart > 0 { }
                if clock - st.chaseStart > 0 { note("noFit \(st.move) dh\(dh > 0.33 ? ">" : "<") dy\(String(format: "%+.1f", pp.y - crown))") }
                let stand = standPoint(j, bub, st.move)
                if simd_distance(stand, b.position) > 0.25, clock >= st.retargetAt { st.retargetAt = clock + 0.5; st.goal = stand; b.bubbleGo(stand) }
                return
            }
            if travels(m), faceErr > 0.45 {
                if clock - st.aimAt < 0.8 { return }          // (he turns toward the camera by himself: wait for it)
                note("fallback faceErr \(m) err \(String(format: "%.1f", faceErr)) yaw \(String(format: "%.1f", b.yaw)) cam \(String(format: "%.1f", b.faceCameraYaw())) toBubble \(String(format: "%.1f", b.yawTo(pxz)))")          // the travelling moves go the way he faces: not lined up, so under it for a header instead
                if BubbleTuning.forceMove == nil { st.move = .header; field.setReach(st.bubble, y: reachHeight(.header, j)); st.mode = .chase; st.goal = nil; st.goalTries = 0; st.retargetAt = 0 }
                else if clock >= st.retargetAt { st.retargetAt = clock + 0.5; _ = b.bubbleWatch(pxz, hold: 0.3, excited: true) }
                return
            }
            guard clock - lastHopStart >= BubbleTuning.popGap, b.bubbleCanHop else { return }          // (the feet may still be settling from the walk: wait, that is not a failed start)
            var ok = false
            var used = m
            switch m {
            case .header: ok = b.bubbleHeaderHop(j.sim)
            case .leap: ok = b.bubbleLeap(j.sim, distance: min(max(dh, BubbleTuning.leapRange.lowerBound), BubbleTuning.leapRange.upperBound))
            case .bounce: ok = b.bubbleBounce(j.sim)
            case .flap: ok = b.bubbleFlap(j.sim)
            case .skip: ok = b.bubbleSkip(j.sim)
            }
            if !ok, m != .header, dh <= BubbleTuning.hopReach, fits(.header) { ok = b.bubbleHeaderHop(j.sim); used = .header }
            if ok {
                st.move = used
                st.mode = .hop; st.hopStart = clock; lastHopStart = clock; st.done = false; st.extra = 0
                moveStarts[used, default: 0] += 1
                trace("jelly \(j.id) \(used) at bubble \(bub.id) y=\(String(format: "%.2f", bub.pos.y)) crown \(String(format: "%.2f", crown)) dh \(String(format: "%.2f", dh))")
            } else {
                st.startFails += 1
                note("startFail \(m) \(m == .skip ? b.bubbleSkipProbe() : "")")
                st.retargetAt = clock + 0.4
                if travels(m), BubbleTuning.forceMove == nil {          // (no room / a friend ahead for the travelling move: under it for a header instead)
                    st.move = .header; field.setReach(st.bubble, y: reachHeight(.header, j)); st.mode = .chase; st.goal = nil; st.goalTries = 0; st.retargetAt = 0
                } else if st.startFails >= 3 { endChase(&st, j) }
            }
        case .hop:
            guard b.attached, !b.held, b.social == nil else { endChase(&st, j); return }
            let age = clock - st.hopStart
            let crown = crownY(j)
            let c = SIMD3<Float>(b.position.x, crown, b.position.y)
            func touches(_ bub: Bubble) -> Bool {
                if st.move == .skip {          // the body touches it: beside his belly, from the floor to the crown
                    return simd_distance(floorPos(bub), b.position) <= 0.4 + 0.6 * bub.radius && bub.pos.y >= crown - BobShape.H - bub.radius * 0.5 && bub.pos.y <= crown + bub.radius * 0.5
                }
                return simd_distance(c, bub.pos) <= bub.radius * 0.95 + BubbleTuning.contactSlack
            }
            func popped(_ bub: Bubble, light: Bool) {
                popBubble(bub.id, by: j, hopped: true, light: light)
                if let n = states[j.id] { st.streak = n.streak; st.lastPop = n.lastPop }
                movePops[st.move, default: 0] += 1
            }
            if !st.done {
                guard let bub = field.bubble(st.bubble) else { endChase(&st, j); return }          // (it popped on its own)
                if age >= 0.1, touches(bub) {
                    for o in js where o.id != j.id {          // (claims are exclusive: only a rare leftover gets the bump)
                        if var os = states[o.id], os.mode != .idle, os.bubble == bub.id {
                            os.mode = .idle; os.thinkAt = clock + 2; states[o.id] = os; o.brain.bubbleHold = false
                            o.brain.face(.hopeful, hold: 1.4); bumps += 1
                            AudioHub.shared.play(.boop, jelly: o.id, x: o.brain.px, volume: 0.25)
                        }
                    }
                    popped(bub, light: false)
                    claimToPop.append(clock - st.claimAt)
                    st.done = true
                    if st.move != .bounce { endChase(&st, j); return }
                }
            } else if st.extra < 2, st.move == .bounce {
                // a later hop of the same bounce: another unclaimed bubble on the crown is claimed and popped (a lighter beat)
                if let o = field.bubbles.first(where: { $0.claimedBy < 0 && touches($0) }) {
                    field.claim(o.id, by: j.id)
                    popped(o, light: true); st.extra += 1; extraPops += 1
                }
            }
            let over = b.idleState.kind == nil && b.scriptIsNone && age > 0.2
            if st.done { if over || age > 3 { endChase(&st, j) }; return }
            if over || age > 3 {          // missed (it drifted): a hopeful look, one more try
                b.face(.hopeful, hold: 1.0)
                st.tries += 1
                if st.tries < 2, !b.bubbleHopBusy { st.mode = .aim; st.aimAt = clock; st.until = clock + 2.0; st.retargetAt = clock + 0.3 } else { endChase(&st, j) }
            }
        }
    }

    /// The bubble a Jelbie goes for: unclaimed, really reachable (walk time + 1 s fits its life), low and slow and near him, left to a clearly closer Jelbie, not behind another one; a little jitter.
    private func pickTarget(for j: BubbleJelly, among js: [BubbleJelly]) -> Bubble? {
        let p = j.brain.position
        var best: (Bubble, Float)?
        for b in field.bubbles where b.claimedBy < 0 {
            let fp = floorPos(b)
            let rest = fp + SIMD2(b.vel.x, b.vel.z) / BubbleField.claimedDrag          // (where it stops once somebody is after it: he must be able to stand under it, inside the play area)
            guard b.pos.y < BubbleTuning.chaseMaxY, b.pos.y > BubbleTuning.hopMinY - 0.25, b.age > 0.6, inArea(fp), simd_distance(clampToArea(rest), rest) < 0.25 else { continue }
            let d = simd_distance(fp, p)
            guard d < 4.5, simd_distance(j.brain.fixed(fp), fp) < 0.45 else { continue }
            let tArrive = d / BubbleTuning.walkSpeed + 1.0
            guard tArrive <= b.life - b.age + 2.0 else { continue }          // (a claimed bubble waits: up to 3 s more life, 2 of them counted)
            let predY = b.pos.y < 1.0 ? min(1.5, b.pos.y + 0.3 * tArrive) : b.pos.y
            guard predY >= BubbleTuning.hopMinY, predY <= BubbleTuning.chaseMaxY else { continue }
            var pen: Float = 0
            var lost = false
            for o in js where o.id != j.id {
                let op = o.brain.position
                if (states[o.id]?.mode ?? .idle) == .idle, simd_distance(op, fp) < d - 0.5 { lost = true; break }          // (somebody is clearly closer and free: his)
                if segmentDistance(op, p, fp) < 0.6 { pen += 1.5 }
            }
            if lost { continue }
            let score = d + 0.8 * max(0, b.pos.y - 1.0) + 0.6 * simd_length(SIMD2(b.vel.x, b.vel.z)) + pen + Float.random(in: 0..<0.3)
            if best == nil || score < best!.1 { best = (b, score) }
        }
        return best?.0
    }
    private func segmentDistance(_ q: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a, l2 = simd_dot(ab, ab)
        let t = l2 > 1e-6 ? min(max(simd_dot(q - a, ab) / l2, 0), 1) : 0
        return simd_distance(q, a + ab * t)
    }

    /// The crown's height now (the body's centre + half the height: the squash, the hop and the wobble are in the centroid).
    private func crownY(_ j: BubbleJelly) -> Float { j.sim.centroid().y + BobShape.H * 0.5 }

    @ObservationIgnored private(set) var log: [String] = []
    @ObservationIgnored private var lastTrace: Float = -9
    private func trace(_ s: String) { if log.count < 120 { log.append(s) } }

    private func endChase(_ st: inout JState, _ j: BubbleJelly) {
        if st.mode != .idle { note("end \(st.mode) \(st.move) \(st.done ? "popped" : "no")"); chaseRecords.append(ChaseRecord(popped: st.done, seconds: clock - st.claimAt, walking: st.walkTime, move: st.move)) }
        st.done = false; st.extra = 0; st.goal = nil; st.goalTries = 0; st.startFails = 0
        field.release(jelly: j.id)
        j.brain.bubbleHold = false
        st.mode = .idle; st.bubble = -1; st.thinkAt = clock + Float.random(in: 0.3...0.9)
    }

    /// The bubble a Jelbie goes for: nearest in reach of the room, preferring ones nobody is after (now and then he takes one that is claimed).
    private func classicPick(for j: BubbleJelly) -> Bubble? {
        let p = j.brain.position
        let ok = field.bubbles.filter { $0.pos.y < BubbleTuning.chaseMaxY && $0.pos.y > BubbleTuning.hopMinY - 0.25 && simd_distance(floorPos($0), p) < 4.5 && $0.age > 0.6 && inArea(floorPos($0)) && simd_distance(j.brain.fixed(floorPos($0)), floorPos($0)) < 0.45 }          // (only bubbles over floor he can stand on)
        let free = ok.filter { $0.claimedBy < 0 }
        let pool = (!free.isEmpty && Float.random(in: 0..<1) > 0.12) ? free : ok
        return pool.min { simd_distance(floorPos($0), p) < simd_distance(floorPos($1), p) }
    }
    private func nearest(to p: SIMD2<Float>) -> SIMD2<Float>? {
        field.bubbles.filter { $0.pos.y < 2.4 }.min { simd_distance(floorPos($0), p) < simd_distance(floorPos($1), p) }.map { floorPos($0) }
    }

    // MARK: the play area (stay in view)

    /// The floor rectangle the play camera shows between the top of the room and the HUD (pill + wand): the Jelbies' bodies stay inside it. nil until the overlay knows the view size.
    private func playArea() -> (lo: SIMD2<Float>, hi: SIMD2<Float>)? {
        let size = viewSize
        guard size.width > 1, size.height > 1 else { return nil }
        if let c = areaCache, c.size == size { return (c.lo, c.hi) }
        let was = GameCamera.playBlend
        GameCamera.playBlend = 1; defer { GameCamera.playBlend = was }          // (the area of the settled play view, whatever the camera's ease is now)
        let land = size.width > size.height
        let xl: CGFloat = land ? 0.24 : 0.17, xr = 1 - xl
        let yTop: CGFloat = 0.40, yBot: CGFloat = land ? 0.68 : 0.70
        guard let back = GameCamera.floorPoint(screen: CGPoint(x: size.width * 0.5, y: size.height * yTop), size: size),
              let front = GameCamera.floorPoint(screen: CGPoint(x: size.width * 0.5, y: size.height * yBot), size: size),
              let l = GameCamera.floorPoint(screen: CGPoint(x: size.width * xl, y: size.height * yBot), size: size),
              let r = GameCamera.floorPoint(screen: CGPoint(x: size.width * xr, y: size.height * yBot), size: size) else { return nil }
        let hx = max(min(abs(l.x), abs(r.x)) - 0.8, 1.2)          // (a body's half width inside the near edge)
        var zHi = min(front.y, GameCamera.roamMaxZ - 0.1)
        var zLo = max(back.y, GameCamera.parkRoamMaxZ != nil ? GameCamera.roamRect.min.y : RoomLayout.minZ + 1.6)          // (the park: its roam rect's back edge)
        if zHi - zLo < 1.6 { zLo = zHi - 1.6 }
        zHi = max(zHi, zLo + 0.5)
        areaCache = (size, SIMD2(-hx, zLo), SIMD2(hx, zHi))
        return (SIMD2(-hx, zLo), SIMD2(hx, zHi))
    }
    private func inArea(_ p: SIMD2<Float>) -> Bool {
        guard let a = playArea() else { return true }
        return p.x >= a.lo.x - 1 && p.x <= a.hi.x + 1 && p.y >= a.lo.y - 1 && p.y <= a.hi.y + 1
    }
    private func clampToArea(_ p: SIMD2<Float>) -> SIMD2<Float> {
        guard let a = playArea() else { return p }
        return SIMD2(min(max(p.x, a.lo.x), a.hi.x), min(max(p.y, a.lo.y), a.hi.y))
    }

    /// His spots: one each, abreast across the area (the middle one of three a step further back so nobody hides anybody), left to right by where they stand now.
    private func assignSlots(_ awake: [BubbleJelly], _ a: (lo: SIMD2<Float>, hi: SIMD2<Float>)) {
        let hx = a.hi.x, span = a.hi.y - a.lo.y
        let front = a.lo.y + 0.72 * span, back = a.lo.y + 0.38 * span, mid = a.lo.y + 0.58 * span
        let spots: [SIMD2<Float>]
        switch awake.count {
        case 0: spots = []
        case 1: spots = [SIMD2(0, mid)]
        case 2: spots = [SIMD2(-0.5 * hx, mid), SIMD2(0.5 * hx, mid)]
        default: spots = [SIMD2(-0.72 * hx, front), SIMD2(0, back), SIMD2(0.72 * hx, front)] + (3..<awake.count).map { SIMD2(Float($0 % 2 == 0 ? -1 : 1) * 0.35 * hx, a.lo.y + 0.9 * span) }
        }
        slots = [:]
        for (k, j) in awake.sorted(by: { $0.brain.position.x < $1.brain.position.x }).enumerated() where k < spots.count { slots[j.id] = spots[k] }
    }

    /// Every step: awake Jelbies get their leash (area, spot, the wand to look at); when the set changes or the view is new they walk in to their spots; every half second a
    /// straggler outside the area (a social, a dash that was already running) is called back. Sleepers are left asleep.
    private func leashTick(_ js: [BubbleJelly]) {
        for j in js where (j.brain.isSleeping || j.brain.isNapping) && j.brain.bubbleLeash != nil { j.brain.bubbleLeash = nil; j.brain.trackPoint = nil; j.brain.bubbleHold = false }
        guard let a = playArea() else { return }
        let awake = js.filter { !$0.free && !$0.brain.isSleeping && !$0.brain.isNapping && $0.brain.enabled }
        let key = awake.map(\.id).sorted()
        let gather = key != slotKey || slotSize != viewSize
        if gather { slotKey = key; slotSize = viewSize; assignSlots(awake, a) }
        let m = mouth, look = SIMD2(m.x, m.z)
        for j in awake {
            guard let slot = slots[j.id] else { continue }
            let b = j.brain
            if b.bubbleLeash == nil, !leashed.contains(where: { $0 === b }) { leashed.append(b) }
            b.bubbleLeash = BubbleLeash(lo: a.lo, hi: a.hi, slot: slot, look: look)
            let walkIn = gather && simd_distance(b.position, slot) > 1.0
            let strayed = clock >= superviseAt && !b.bubbleLeash!.contains(b.position, margin: 0.6) && (states[j.id]?.mode ?? .idle) == .idle && b.idleState.kind == nil
            if walkIn || strayed {
                if b.attached, !b.commanded, b.social == nil, b.pending == nil || walkIn {
                    if case .walk(let t, _) = b.script, !walkIn, b.bubbleLeash!.contains(t) { continue }
                    b.requestNow(.goTo(slot))
                }
            }
        }
        if clock >= superviseAt { superviseAt = clock + 0.5 }
    }
    private func releaseLeash() {
        for b in leashed { b.bubbleLeash = nil; b.trackPoint = nil; b.bubbleHold = false }
        leashed.removeAll(); slots = [:]; slotKey = []; areaCache = nil
    }

    // MARK: pops

    /// The pop, at the frame the bubble meets his crown: the burst, the pop sound and a light haptic tick right now; the voice (one, not two) comes after he lands (`cheerTick`).
    private func popBubble(_ id: Int, by j: BubbleJelly, hopped: Bool, light: Bool = false) {
        guard let b = field.pop(id) else { return }
        addFX(b, quiet: false)
        var st = states[j.id] ?? JState()
        st.streak = clock - st.lastPop < BubbleTuning.streakWindow ? st.streak + 1 : 1
        st.lastPop = clock
        popsByJelly[j.id, default: 0] += 1
        care?.needs(for: j.id).gain(.attention, BubbleTuning.attentionPerPop)
        if hopped { hopPops += 1 }
        j.brain.face(.excited, hold: 1.6)
        AudioHub.shared.play(.bubblePop, jelly: j.id, x: j.brain.px, volume: 1)
        if hopped || b.pos.z > 0.8, let h = haptics { h.transient(now: CACurrentMediaTime(), intensity: light ? BubbleTuning.lightBeat : 0.25, sharpness: 0.5) }
        var hearts = false
        if st.streak >= BubbleTuning.streakForHearts { st.streak = 0; heartBursts += 1; hearts = true }
        cheers[j.id] = (clock + (hopped ? 0.4 : 0.15), hearts)          // (the hop's landing is ~0.25 s after its top)
        states[j.id] = st
    }

    /// After the landing: the happy reaction, one voice (the happy chirp or the pop's own giggle), then the hearts of a streak.
    private func cheerTick(_ js: [BubbleJelly]) {
        guard !cheers.isEmpty else { return }
        for (id, c) in cheers where clock >= c.at {
            cheers[id] = nil
            guard let j = js.first(where: { $0.id == id }) else { continue }
            let a = AudioHub.shared
            let r = Float.random(in: 0..<1)
            if r < 0.6 { a.chirp(jelly: id, .happy, x: j.brain.px) } else { a.play(.bubbleChirp, jelly: id, x: j.brain.px, volume: 1) }
            if c.hearts, let care {
                let now = CACurrentMediaTime()
                if id == 0 { care.touchPlay?.spawnHeart(now: now) } else { care.bubbleHub.spawnHeart(for: id, now: now) }
            }
        }
    }

    private func addFX(_ b: Bubble, quiet: Bool) {
        if fx.count >= 16 { fx.removeFirst() }
        fx.append(PopFX(pos: b.pos, born: clock, size: b.radius * (quiet ? 0.6 : 1)))
        if quiet, clock - lastQuietPop > 0.25 { lastQuietPop = clock; AudioHub.shared.play(.bubblePop, x: b.pos.x, volume: 0.35) }
    }
    @ObservationIgnored private var lastQuietPop: Float = -9

    // MARK: drawing helpers (BubbleOverlay)

    /// Age of an fx 0...1.
    func fxAge(_ f: PopFX) -> Float { min(max((clock - f.born) / BubbleTuning.fxLife, 0), 1) }
}
