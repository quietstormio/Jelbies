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
    static let popGap: Float = 0.7                 // seconds between two hop starts anywhere: every pop is readable on its own
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

    private enum Mode { case idle, chase, aim, hop }
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
        clock += dt
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
            let b = j.brain
            switch st.mode {
            case .idle:
                guard clock >= st.thinkAt else { continue }
                st.thinkAt = clock + Float.random(in: BubbleTuning.thinkEvery)
                guard b.bubbleFree, !field.bubbles.isEmpty else { continue }
                let roll = Float.random(in: 0..<1)
                if roll < 0.72, chasing < BubbleTuning.maxChasers, let target = pickTarget(for: j) {
                    st.mode = .chase; st.bubble = target.id; st.until = clock + 6.5; st.retargetAt = 0; st.chaseStart = clock; st.tries = 0
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
                    endChase(&st, j); continue }
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
                guard let bub = field.bubble(st.bubble), clock < st.until, b.bubbleStillMine else { endChase(&st, j); continue }
                guard b.scriptIsNone, b.pending == nil, b.idleState.kind == nil else { continue }          // (still turning / walking a correction)
                // where the bubble will be when the top of a hop comes (BlobBrain.tossHeaderLead): over his head, at the height of the crown at the top of the hop?
                let pp = bub.pos + bub.vel * BlobBrain.tossHeaderLead
                let pxz = SIMD2(pp.x, pp.z)
                let apexY = crownY(j) + BlobBrain.tossApex
                let band = 0.12 + 0.5 * bub.radius
                if simd_distance(pxz, b.position) > BubbleTuning.hopReach {
                    if clock >= st.retargetAt { st.retargetAt = clock + 0.4; b.bubbleGo(clampToArea(pxz)) }          // (a small step to stand right under it)
                } else if abs(pp.y - apexY) <= band + 0.08, pp.y >= BubbleTuning.hopMinY, clock - lastHopStart >= BubbleTuning.popGap {
                    if b.bubbleHeaderHop(j.sim) {
                        st.mode = .hop; st.hopStart = clock; lastHopStart = clock
                        trace("jelly \(j.id) hops at bubble \(bub.id) y=\(String(format: "%.2f", bub.pos.y)) apex \(String(format: "%.2f", apexY))")
                    }
                }          // (else: it is still above / below the reach of a hop: he waits under it, looking up)
            case .hop:
                guard let bub = field.bubble(st.bubble), b.attached, !b.held, b.social == nil else { endChase(&st, j); continue }          // (it popped on its own, or somebody else got it)
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
                        endChase(&st, j); continue
                    }
                }
                if age > 0.7 {          // missed (it drifted): a hopeful look, one more try
                    b.face(.hopeful, hold: 1.0)
                    st.tries += 1
                    if st.tries < 2, !b.tossBusy { st.mode = .aim; st.until = clock + 2.0; st.retargetAt = clock + 0.3 } else { endChase(&st, j) }
                }
            }
        }
    }

    /// The crown's height now (the body's centre + half the height: the squash, the hop and the wobble are in the centroid).
    private func crownY(_ j: BubbleJelly) -> Float { j.sim.centroid().y + BobShape.H * 0.5 }

    @ObservationIgnored private(set) var log: [String] = []
    @ObservationIgnored private var lastTrace: Float = -9
    private func trace(_ s: String) { if log.count < 120 { log.append(s) } }

    private func endChase(_ st: inout JState, _ j: BubbleJelly) {
        field.release(jelly: j.id)
        j.brain.bubbleHold = false
        st.mode = .idle; st.bubble = -1; st.thinkAt = clock + Float.random(in: 0.3...0.9)
    }

    /// The bubble a Jelbie goes for: nearest in reach of the room, preferring ones nobody is after (now and then he takes one that is claimed).
    private func pickTarget(for j: BubbleJelly) -> Bubble? {
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
        var zLo = max(back.y, RoomLayout.minZ + 1.6)
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
        let awake = js.filter { !$0.brain.isSleeping && !$0.brain.isNapping && $0.brain.enabled }
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
    private func popBubble(_ id: Int, by j: BubbleJelly, hopped: Bool) {
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
        if hopped || b.pos.z > 0.8, let h = haptics { h.transient(now: CACurrentMediaTime(), intensity: 0.25, sharpness: 0.5) }
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
