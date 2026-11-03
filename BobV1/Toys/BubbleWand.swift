//
//  BubbleWand.swift
//  The bubble wand, a play-mode toy (registered through PlayToyRegistry; bought once in the shop). The wand sits at the bottom of the screen. BLOW into
//  the microphone (Audio/BlowDetector.swift, fed from Ears' single input tap) or TAP AND HOLD the wand (the always-available fallback, also for VoiceOver
//  and when the mic is refused): bubbles stream out, rise, drift into the room and pop on their own after a few seconds.
//  The Jelbies play: some WATCH a bubble (turn and look), some CHASE one (walk under it, hop, pop it with the head: a soft pop, a sparkle, a giggle),
//  at most two chase at once so it never looks like a drill; now and then two want the same bubble and one gets there first. A drifting bubble that
//  touches a body pops too. Three pops in a row (within 8 s) give hearts. Bubbles draw in Toys/BubbleOverlay.swift (a CALayer overlay, no blur/material).
//  Pure parts: BubbleField (the sim), BlowDetector (the sound). All time is the wand's own clock (steps of the fixed tick), so tests are deterministic.
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
}

nonisolated enum BubbleTuning {
    static let spawnPerSecond: ClosedRange<Float> = 1.5...6.5
    static let holdStrength: Float = 0.6
    static let contactRadius: Float = 0.62          // a body touching a drifting bubble
    static let contactMaxY: Float = 1.7
    nonisolated(unsafe) static var contactPopChance: Float = 0.35          // (var: tests set 1)
    static let hopReach: Float = 2.0               // horizontal reach of a hop's top
    static let hopMaxY: Float = 2.2
    static let chaseMaxY: Float = 2.0
    static let maxChasers = 2
    static let thinkEvery: ClosedRange<Float> = 0.5...1.1
    static let streakWindow: Float = 8
    static let streakForHearts = 3
    static let fxLife: Float = 0.5
    static let price = 35
}

@MainActor
@Observable
final class BubbleWand: PlayToy {
    static let shared = BubbleWand()

    nonisolated let toyID = "bubbleWand"
    let title = "Bubble wand"
    let symbol = "bubbles.and.sparkles"
    var price: Int { BubbleTuning.price }

    // MARK: state

    private(set) var active = false
    /// Tap-and-hold on the wand (set by the overlay's gesture / the VoiceOver action).
    var holding = false
    /// 0...1 how hard the player is blowing right now (mic, hold or demo): the wand's meter.
    private(set) var strength: Float = 0
    /// True when the microphone path is unavailable (refused, or no engine): the wand then says "hold to blow".
    var micUnavailable: Bool { ears.wandMicDenied || !ears.micReadyForBlow }
    /// The view size the overlay draws in (points); the mouth and the pixel scale follow it.
    @ObservationIgnored var viewSize = CGSize(width: 440, height: 956) { didSet { if viewSize != oldValue { mouthCache = nil } } }

    @ObservationIgnored private(set) var field = BubbleField()
    struct PopFX: Equatable { var pos: SIMD3<Float>; var born: Float; var size: Float }
    @ObservationIgnored private(set) var fx: [PopFX] = []
    @ObservationIgnored private(set) var clock: Float = 0
    @ObservationIgnored var ears: Ears = .shared
    /// Simulated blow for captures / tests: strength by time since `start` (nil = off).
    @ObservationIgnored var demo: ((Float) -> Float)?
    @ObservationIgnored private var demoStart: Float = 0
    @ObservationIgnored private var holdT: Float = 0
    @ObservationIgnored private var burstUntil: Float = -1
    @ObservationIgnored private var spawnAcc: Float = 0
    @ObservationIgnored private var bloopAt: Float = -9
    @ObservationIgnored private var mouthCache: SIMD3<Float>?
    @ObservationIgnored private var states: [Int: JState] = [:]
    @ObservationIgnored private weak var care: GameCare?
    /// Totals (tests, report).
    @ObservationIgnored private(set) var popsByJelly: [Int: Int] = [:]
    @ObservationIgnored private(set) var chases = 0
    @ObservationIgnored private(set) var watches = 0
    @ObservationIgnored private(set) var bumps = 0
    @ObservationIgnored private(set) var nudges = 0
    @ObservationIgnored private(set) var hopPops = 0
    @ObservationIgnored private(set) var contactPops = 0
    @ObservationIgnored private(set) var heartBursts = 0

    private enum Mode { case idle, chase, hop }
    private struct JState {
        var mode: Mode = .idle
        var bubble = -1
        var until: Float = 0
        var hopAt: Float = 0
        var thinkAt: Float = 0
        var retargetAt: Float = 0
        var chaseStart: Float = 0
        var streak = 0
        var lastPop: Float = -99
    }

    nonisolated deinit {}
    init() {}

    // MARK: PlayToy

    func activate(care: GameCare?) { activate(care: care, listen: true) }
    /// `listen: false` = no microphone (the capture demo, so no permission prompt covers the screen).
    func activate(care: GameCare?, listen: Bool) {
        self.care = care
        guard !active else { return }
        active = true
        reset()
        if listen { ears.setWandListening(true) }
    }
    func deactivate() {
        guard active else { return }
        active = false
        holding = false
        reset()
        ears.setWandListening(false)
        states.removeAll()
    }
    /// Test seam: back to a fresh, put-away wand (counters too).
    func resetForTests() {
        BubbleTuning.contactPopChance = 0.35
        deactivate(); active = false; clock = 0; demo = nil; burstUntil = -1; states.removeAll(); field = BubbleField()
        popsByJelly = [:]; nudges = 0; hopPops = 0; chases = 0; watches = 0; bumps = 0; contactPops = 0; heartBursts = 0; lastQuietPop = -9
    }
    /// Test seam: a bubble right there.
    @discardableResult func insertBubble(at p: SIMD3<Float>, radius: Float = 0.2) -> Int? { field.insert(at: p, radius: radius) }
    func clearBubbles() { field.clear() }
    private func reset() {
        field.clear(); fx.removeAll(); spawnAcc = 0; strength = 0; holdT = 0
    }

    /// `-BubbleDemo 1`: the wand comes out by itself and a simulated blow plays (pulses of 2.5 s every 4 s). `2` blows without pause.
    func startDemo(mode: Int, care: GameCare?) {
        activate(care: care, listen: false)
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
        clock += dt
        // 1. how hard is he blowing?
        var s: Float = 0
        if let d = demo { s = d(clock - demoStart) }
        if clock < burstUntil { s = max(s, BubbleTuning.holdStrength) }
        if holding { holdT += dt; s = max(s, min(BubbleTuning.holdStrength + 0.3 * holdT, 0.9)) } else { holdT = 0 }
        if !ears.wandMicDenied, ears.micReadyForBlow { s = max(s, ears.blowStrength) }
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
        // 4. the Jelbies
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
    /// The stage keeps the haptic engine warm exactly while the wand is blowing.
    var hapticsWanted: Bool { active }

    // MARK: Jelbies

    private func floorPos(_ b: Bubble) -> SIMD2<Float> { SIMD2(b.pos.x, b.pos.z) }

    private func jelliesTick(_ js: [BubbleJelly]) {
        guard !field.bubbles.isEmpty || states.values.contains(where: { $0.mode != .idle }) else { return }
        // passive contact: a drifting bubble that touches a body pops
        for j in js {
            let p = j.brain.position
            for b in field.bubbles where b.pos.y < BubbleTuning.contactMaxY && !b.touched {
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
            let b = j.brain
            switch st.mode {
            case .idle:
                guard clock >= st.thinkAt else { continue }
                st.thinkAt = clock + Float.random(in: BubbleTuning.thinkEvery)
                guard b.bubbleFree, !field.bubbles.isEmpty else { continue }
                let roll = Float.random(in: 0..<1)
                if roll < 0.42, chasing < BubbleTuning.maxChasers, let target = pickTarget(for: j) {
                    st.mode = .chase; st.bubble = target.id; st.until = clock + 6.5; st.retargetAt = 0; st.chaseStart = clock
                    field.claim(target.id, by: j.id)
                    chasing += 1; chases += 1
                } else if roll < 0.75, let t = nearest(to: b.position) {
                    watches += 1
                    _ = b.bubbleWatch(t, hold: Float.random(in: 1.0...2.2), excited: Float.random(in: 0..<1) < 0.4)
                    st.thinkAt = clock + Float.random(in: 1.4...2.6)
                } else {
                    st.thinkAt = clock + Float.random(in: 1.2...2.4)          // not every bubble needs a Jelbie
                }
            case .chase:
                guard let bub = field.bubble(st.bubble), clock < st.until, b.bubbleStillMine else {
                    trace("jelly \(j.id) gives up chase t=\(String(format: "%.1f", clock)) bubble gone \(field.bubble(st.bubble) == nil) timeout \(clock >= st.until) mine \(b.bubbleStillMine)")
                    endChase(&st, j); continue }
                let d = simd_distance(floorPos(bub), b.position)
                if clock - lastTrace > 1 { lastTrace = clock; trace("jelly \(j.id) chasing d=\(String(format: "%.2f", d)) script none \(b.scriptIsNone) pending \(b.pending != nil) idle \(String(describing: b.idleState.kind))") }
                if d < 1.25 || (d < 1.9 && b.scriptIsNone && clock - st.chaseStart > 1.0), bub.pos.y < BubbleTuning.hopMaxY {
                    if b.scriptIsNone, b.pending == nil, b.idleState.kind == nil {
                        if b.bubbleHop(j.sim) { st.mode = .hop; st.hopAt = clock + 0.3; st.until = clock + 1.4 }
                        else { st.hopAt = clock + 0.15; st.mode = .hop; st.until = clock + 1.0 }          // (cannot hop right now: a head bump instead)
                    }
                } else if clock >= st.retargetAt {
                    st.retargetAt = clock + 0.45
                    b.bubbleGo(floorPos(bub) + SIMD2(bub.vel.x, bub.vel.z) * 0.6)          // (a little ahead of a drifting bubble)
                }
                if bub.pos.y > BubbleTuning.chaseMaxY + 0.3 { endChase(&st, j) }
            case .hop:
                guard clock >= st.hopAt else { continue }
                if let bub = field.bubble(st.bubble), simd_distance(floorPos(bub), b.position) < BubbleTuning.hopReach, bub.pos.y < BubbleTuning.hopMaxY {
                    // two after the same one: the other gets a bump instead
                    for o in js where o.id != j.id {
                        if var os = states[o.id], os.mode != .idle, os.bubble == bub.id {
                            os.mode = .idle; os.thinkAt = clock + 2; states[o.id] = os
                            o.brain.face(.hopeful, hold: 1.4); bumps += 1
                            AudioHub.shared.play(.boop, jelly: o.id, x: o.brain.px, volume: 0.25)
                        }
                    }
                    popBubble(bub.id, by: j, hopped: true)
                }
                endChase(&st, j)
            }
        }
    }

    @ObservationIgnored private(set) var log: [String] = []
    @ObservationIgnored private var lastTrace: Float = -9
    private func trace(_ s: String) { if log.count < 120 { log.append(s) } }

    private func endChase(_ st: inout JState, _ j: BubbleJelly) {
        field.release(jelly: j.id)
        st.mode = .idle; st.bubble = -1; st.thinkAt = clock + Float.random(in: 0.8...1.8)
    }

    /// The bubble a Jelbie goes for: nearest in reach of the room, preferring ones nobody is after (now and then he takes one that is claimed).
    private func pickTarget(for j: BubbleJelly) -> Bubble? {
        let p = j.brain.position
        let ok = field.bubbles.filter { $0.pos.y < BubbleTuning.chaseMaxY && simd_distance(floorPos($0), p) < 6 && $0.age > 0.6 && simd_distance(j.brain.fixed(floorPos($0)), floorPos($0)) < 0.45 }          // (only bubbles over floor he can stand on)
        let free = ok.filter { $0.claimedBy < 0 }
        let pool = (!free.isEmpty && Float.random(in: 0..<1) > 0.12) ? free : ok
        return pool.min { simd_distance(floorPos($0), p) < simd_distance(floorPos($1), p) }
    }
    private func nearest(to p: SIMD2<Float>) -> SIMD2<Float>? {
        field.bubbles.filter { $0.pos.y < 2.4 }.min { simd_distance(floorPos($0), p) < simd_distance(floorPos($1), p) }.map { floorPos($0) }
    }

    // MARK: pops

    private func popBubble(_ id: Int, by j: BubbleJelly, hopped: Bool) {
        guard let b = field.pop(id) else { return }
        addFX(b, quiet: false)
        var st = states[j.id] ?? JState()
        st.streak = clock - st.lastPop < BubbleTuning.streakWindow ? st.streak + 1 : 1
        st.lastPop = clock
        popsByJelly[j.id, default: 0] += 1
        if hopped { hopPops += 1 }
        j.brain.face(.excited, hold: 1.4)
        let a = AudioHub.shared
        a.play(.bubblePop, jelly: j.id, x: j.brain.px, volume: 1)
        if Float.random(in: 0..<1) < 0.5 { a.chirp(jelly: j.id, .happy, x: j.brain.px) } else if Float.random(in: 0..<1) < 0.5 { a.play(.bubbleChirp, jelly: j.id, x: j.brain.px, volume: 1) }
        if b.pos.z > 0.8, let h = haptics { h.transient(now: CACurrentMediaTime(), intensity: 0.2, sharpness: 0.3) }
        if st.streak >= BubbleTuning.streakForHearts {
            st.streak = 0; heartBursts += 1
            if let c = care {
                let now = CACurrentMediaTime()
                if j.id == 0 { c.touchPlay?.spawnHeart(now: now) } else { c.bubbleHub.spawnHeart(for: j.id, now: now) }
            }
        }
        states[j.id] = st
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
