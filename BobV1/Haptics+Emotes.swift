//
//  Haptics+Emotes.swift
//  The room's haptic cues (2026-11-02): ONE engine, ONE owner. Every move a Jelbie makes (each IdleKind, each SocialKind, the landings / squishes / boops, the solo and group
//  emotes' key frames) has its OWN small pattern here, played through the single `HapticDriver` that also gives the touch / cuddle haptics (the earlier second engine in
//  RoomHaptics.swift was removed: two CHHapticEngines in one process fought over the haptic server and the touch haptics went quiet).
//    ENERGY   the caller says how big the move is (a hop's landing speed, an SFX volume); intensity scales with it, +-15 % jitter on every play so it never feels robotic
//    SOFT     jelly feel = rounded: sharpness stays <= 0.3 for nearly everything, pulses decay like a squish (`decay`)
//    GUARDS   Haptics off in Settings (HapticSettings, default ON for any save); not while the driver is warm (focus mode / the wash give their own);
//             not during a race / volleyball / bath (`HapticDriver.roomBusy`); at most `roomMinGap` s between two cues (2 a second) across all Jelbies
//    LIFETIME the engine starts at the first cue (when not already warm for focus) and shuts down `roomIdleShutdown` s after the last one
//  Tuning lives in the tables below. A new IdleKind / SocialKind / SFX cue without a pattern does not compile (exhaustive switches), and HapticCueTests enumerates them all.
//

import Foundation
import QuartzCore

/// One pattern: `n` soft pulses `gap` seconds apart, each `decay` x the one before. (intensity, sharpness at energy 1.)
struct CueSpec: Equatable {
    var i: Float, s: Float, n: Int = 1, gap: Double = 0.1, decay: Float = 0.7
    func pulses(energy: Float, jitter: Float) -> [(delay: Double, i: Float, s: Float)] {
        let e = min(1.6, max(0.3, energy))
        return (0..<n).map { k in
            (Double(k) * gap, min(0.85, i * e * jitter * powf(decay, Float(k))), min(0.45, s * (0.9 + 0.1 * e)))
        }
    }
}

/// Key frames the emotes ask for, and the group emotes' tags.
enum EmoteCue: String, CaseIterable, Sendable {
    case hic, sneezeBuild, sneezeBump, dizzyWobble, bowTick, patA, patB, flourish
}
enum GroupCue: String, CaseIterable, Sendable {
    case highFiveBump = "highFive.bump", congaForm = "congaLine.form", congaScatter = "congaLine.scatter", ringForm = "ringDance.form", ringScatter = "ringDance.scatter"
}
/// Sounds that carry a haptic (the landing, the squish, the boop ...). The footstep carries none; the emote clips have their own key-frame cues.
enum SFXCue: String, CaseIterable, Sendable { case setdown, squish, boop, wobble, zoomies }          // (no `jump`: a hop's push-off is the move's own start cue; ~0.4 hops a second would keep the phone buzzing)

enum HapticCue: Hashable, Sendable {
    case idle(IdleKind), social(SocialKind), emote(EmoteCue), group(GroupCue), sfx(SFXCue), beat(String)          // beat: a batch-2 move's key frame, EmoteTreats.haptics["move.beat"]
    var name: String {
        switch self {
        case .idle(let k): return "idle.\(k.rawValue)"
        case .social(let k): return "social.\(k.rawValue)"
        case .emote(let c): return "emote.\(c.rawValue)"
        case .group(let c): return "group.\(c.rawValue)"
        case .sfx(let c): return "sfx.\(c.rawValue)"
        case .beat(let k): return "beat.\(k)"
        }
    }
    var spec: CueSpec {
        switch self {
        case .idle(let k): return Self.idleSpec(k)
        case .social(let k): return Self.socialSpec(k)
        case .emote(let c): return Self.emoteSpec(c)
        case .group(let c): return Self.groupSpec(c)
        case .sfx(let c): return Self.sfxSpec(c)
        case .beat: return CueSpec(i: 0.2, s: 0.15)          // (unused: a beat carries its own pulses)
        }
    }
    /// The pulses of one play. Beats come from the batch-2 table; every other cue from its `CueSpec`.
    func pulses(energy: Float, jitter: Float) -> [(delay: Double, i: Float, s: Float)] {
        if case .beat(let k) = self {
            let e = min(1.6, max(0.3, energy))
            return (EmoteTreats.haptics[k] ?? []).map { (delay: $0.delay, i: min(0.85, $0.i * e * jitter), s: min(0.45, $0.s)) }
        }
        return spec.pulses(energy: energy, jitter: jitter)
    }

    static func sfxSpec(_ c: SFXCue) -> CueSpec {
        switch c {
        case .setdown: return CueSpec(i: 0.42, s: 0.12, n: 3, gap: 0.08, decay: 0.5)         // the landing: a full squish and its settle
        case .squish: return CueSpec(i: 0.30, s: 0.15, n: 2, gap: 0.07, decay: 0.6)
        case .boop: return CueSpec(i: 0.26, s: 0.28, n: 1)
        case .wobble: return CueSpec(i: 0.16, s: 0.08, n: 4, gap: 0.075, decay: 0.75)
        case .zoomies: return CueSpec(i: 0.22, s: 0.10, n: 3, gap: 0.11, decay: 0.85)
        }
    }

    static func emoteSpec(_ c: EmoteCue) -> CueSpec {
        switch c {
        case .hic: return CueSpec(i: 0.36, s: 0.25, n: 2, gap: 0.07, decay: 0.4)
        case .sneezeBuild: return CueSpec(i: 0.14, s: 0.20, n: 2, gap: 0.14, decay: 1.3)
        case .sneezeBump: return CueSpec(i: 0.42, s: 0.15, n: 3, gap: 0.06, decay: 0.5)
        case .dizzyWobble: return CueSpec(i: 0.17, s: 0.09, n: 5, gap: 0.12, decay: 0.8)
        case .bowTick: return CueSpec(i: 0.21, s: 0.20, n: 2, gap: 0.2, decay: 0.5)
        case .patA: return CueSpec(i: 0.27, s: 0.21, n: 1)
        case .patB: return CueSpec(i: 0.19, s: 0.19, n: 1)
        case .flourish: return CueSpec(i: 0.25, s: 0.14, n: 3, gap: 0.1, decay: 0.7)
        }
    }

    static func groupSpec(_ c: GroupCue) -> CueSpec {
        switch c {
        case .highFiveBump: return CueSpec(i: 0.33, s: 0.22, n: 2, gap: 0.06, decay: 0.45)
        case .congaForm: return CueSpec(i: 0.24, s: 0.15, n: 3, gap: 0.12, decay: 0.9)
        case .congaScatter: return CueSpec(i: 0.26, s: 0.17, n: 2, gap: 0.1, decay: 0.6)
        case .ringForm: return CueSpec(i: 0.22, s: 0.13, n: 4, gap: 0.13, decay: 0.85)
        case .ringScatter: return CueSpec(i: 0.25, s: 0.16, n: 3, gap: 0.09, decay: 0.55)
        }
    }

    /// Every solo move. Intensity = how big the move is (a sway is barely there, a flip-sized hop or a stomp is fuller).
    static func idleSpec(_ k: IdleKind) -> CueSpec {
        switch k {
        case .wander: return CueSpec(i: 0.05, s: 0.10)
        case .run: return CueSpec(i: 0.20, s: 0.15, n: 3, gap: 0.12, decay: 0.8)
        case .stumble: return CueSpec(i: 0.40, s: 0.20, n: 3, gap: 0.07, decay: 0.55)
        case .jacks: return CueSpec(i: 0.27, s: 0.18, n: 4, gap: 0.16, decay: 0.9)
        case .sit: return CueSpec(i: 0.17, s: 0.10, n: 2, gap: 0.08, decay: 0.5)
        case .slump: return CueSpec(i: 0.15, s: 0.07, n: 2, gap: 0.10, decay: 0.45)
        case .look: return CueSpec(i: 0.06, s: 0.12)
        case .yawn: return CueSpec(i: 0.10, s: 0.06, n: 3, gap: 0.15, decay: 0.8)
        case .zoomies: return CueSpec(i: 0.24, s: 0.14, n: 5, gap: 0.10, decay: 0.9)
        case .slide: return CueSpec(i: 0.21, s: 0.08, n: 5, gap: 0.09, decay: 0.8)
        case .scoot: return CueSpec(i: 0.19, s: 0.17, n: 2, gap: 0.12, decay: 0.7)
        case .sleep: return CueSpec(i: 0.09, s: 0.05, n: 2, gap: 0.2, decay: 0.5)
        case .tail: return CueSpec(i: 0.22, s: 0.16, n: 3, gap: 0.13, decay: 0.85)
        case .flop: return CueSpec(i: 0.38, s: 0.10, n: 3, gap: 0.09, decay: 0.55)
        case .window: return CueSpec(i: 0.07, s: 0.08)
        case .peek: return CueSpec(i: 0.11, s: 0.13, n: 2, gap: 0.18, decay: 0.7)
        case .stretch: return CueSpec(i: 0.12, s: 0.06, n: 3, gap: 0.14, decay: 0.9)
        case .bounce: return CueSpec(i: 0.30, s: 0.17, n: 3, gap: 0.14, decay: 0.8)
        case .sway: return CueSpec(i: 0.08, s: 0.05, n: 3, gap: 0.22, decay: 0.9)
        case .decorSit: return CueSpec(i: 0.19, s: 0.09, n: 2, gap: 0.09, decay: 0.5)
        case .decorBoop: return CueSpec(i: 0.20, s: 0.24, n: 1)
        case .decorKick: return CueSpec(i: 0.31, s: 0.26, n: 2, gap: 0.06, decay: 0.4)
        case .decorHop: return CueSpec(i: 0.28, s: 0.12, n: 4, gap: 0.15, decay: 0.85)
        case .decorPeek: return CueSpec(i: 0.10, s: 0.12, n: 2, gap: 0.16, decay: 0.7)
        case .decorHopscotch: return CueSpec(i: 0.24, s: 0.12, n: 3, gap: 0.2, decay: 0.85)
        case .decorSlide: return CueSpec(i: 0.23, s: 0.07, n: 6, gap: 0.09, decay: 0.85)
        case .skipHop: return CueSpec(i: 0.25, s: 0.18, n: 2, gap: 0.2, decay: 0.9)
        case .hopscotch: return CueSpec(i: 0.26, s: 0.19, n: 3, gap: 0.18, decay: 0.9)
        case .legSpin: return CueSpec(i: 0.23, s: 0.11, n: 4, gap: 0.08, decay: 0.8)
        case .trot: return CueSpec(i: 0.15, s: 0.14, n: 3, gap: 0.15, decay: 0.9)
        case .stopLook: return CueSpec(i: 0.08, s: 0.14)
        case .joy: return CueSpec(i: 0.34, s: 0.16, n: 3, gap: 0.12, decay: 0.7)
        case .giggle: return CueSpec(i: 0.16, s: 0.20, n: 4, gap: 0.09, decay: 0.85)
        case .startle: return CueSpec(i: 0.38, s: 0.28, n: 2, gap: 0.06, decay: 0.5)
        case .sigh: return CueSpec(i: 0.09, s: 0.04, n: 3, gap: 0.2, decay: 0.7)
        case .hmph: return CueSpec(i: 0.29, s: 0.25, n: 2, gap: 0.1, decay: 0.45)
        case .flapHop: return CueSpec(i: 0.27, s: 0.15, n: 4, gap: 0.07, decay: 0.7)
        case .tailThump: return CueSpec(i: 0.32, s: 0.20, n: 3, gap: 0.2, decay: 0.95)
        case .tailHug: return CueSpec(i: 0.13, s: 0.07, n: 2, gap: 0.2, decay: 0.8)
        case .shake: return CueSpec(i: 0.21, s: 0.20, n: 6, gap: 0.05, decay: 0.85)
        case .lieDown: return CueSpec(i: 0.33, s: 0.09, n: 3, gap: 0.1, decay: 0.45)
        case .chirp: return CueSpec(i: 0.12, s: 0.22, n: 2, gap: 0.1, decay: 0.7)
        case .soccerKick: return CueSpec(i: 0.35, s: 0.27, n: 2, gap: 0.07, decay: 0.45)
        case .tossHeader: return CueSpec(i: 0.30, s: 0.22, n: 2, gap: 0.08, decay: 0.5)          // the crown meets the ball
        case .tossBump: return CueSpec(i: 0.33, s: 0.25, n: 2, gap: 0.09, decay: 0.45)          // the stomp-bump
        // batch 2 (BlobBrain+Emotes2.swift): the move's start; its key frames are the `.beat` cues from EmoteTreats.haptics
        case .stargazing: return CueSpec(i: 0.07, s: 0.30)
        case .proudStrut: return CueSpec(i: 0.15, s: 0.14, n: 2, gap: 0.2, decay: 0.9)
        case .sing: return CueSpec(i: 0.08, s: 0.20, n: 3, gap: 0.38, decay: 0.8)          // (a soft tick per phrase: the voice carries it)
        case .superSpring: return CueSpec(i: 0.32, s: 0.20, n: 4, gap: 0.2, decay: 0.7)          // (the wind-up tremble, the launch, the big landing)
        case .corkscrew: return CueSpec(i: 0.30, s: 0.18, n: 3, gap: 0.22, decay: 0.7)          // (the take-off, the landing, the settle)
        case .oneLegSpin: return CueSpec(i: 0.22, s: 0.12, n: 5, gap: 0.12, decay: 0.8)          // (the rise, a ripple through the turn, the landing)
        case .hula: return CueSpec(i: 0.10, s: 0.16, n: 8, gap: 0.22, decay: 0.95)          // (a soft roll round the hips, a tick per swing)
        case .moonwalk: return CueSpec(i: 0.08, s: 0.10, n: 4, gap: 0.55, decay: 0.9)          // (a soft tick at each switch of the feet: the glide itself is smooth)
        case .backBounce: return CueSpec(i: 0.34, s: 0.22, n: 3, gap: 0.30, decay: 0.7)          // (the thump onto his back, the bounce, the spring up)
        case .headstand: return CueSpec(i: 0.26, s: 0.18, n: 3, gap: 0.45, decay: 0.7)          // (onto his head, the held kick, the pop back over)
        case .floorNapFlop: return CueSpec(i: 0.10, s: 0.06, n: 2, gap: 0.25, decay: 0.7)
        case .tapTilt: return CueSpec(i: 0.075, s: 0.20)
        case .welcomeWiggle: return CueSpec(i: 0.14, s: 0.17, n: 2, gap: 0.13, decay: 0.8)
        case .checkIn: return CueSpec(i: 0.085, s: 0.19)
        case .hiccup: return CueSpec(i: 0.18, s: 0.22, n: 1)
        case .sneeze: return CueSpec(i: 0.12, s: 0.18, n: 1)
        case .dizzyWobble: return CueSpec(i: 0.11, s: 0.08, n: 2, gap: 0.2, decay: 0.8)
        case .politeBow: return CueSpec(i: 0.10, s: 0.15, n: 1)
        case .bellyDrum: return CueSpec(i: 0.14, s: 0.19, n: 2, gap: 0.12, decay: 0.8)
        case .signatureFlourish: return CueSpec(i: 0.13, s: 0.12, n: 2, gap: 0.15, decay: 0.8)
        }
    }

    /// Every pair move: the start (the heart of it plays through the SFX cues, the emotes' key frames and the boops).
    static func socialSpec(_ k: SocialKind) -> CueSpec {
        switch k {
        case .look: return CueSpec(i: 0.07, s: 0.11)
        case .boop: return CueSpec(i: 0.24, s: 0.27)
        case .follow: return CueSpec(i: 0.12, s: 0.12, n: 2, gap: 0.2)
        case .zoomies: return CueSpec(i: 0.24, s: 0.13, n: 4, gap: 0.1, decay: 0.9)
        case .greet: return CueSpec(i: 0.17, s: 0.20, n: 2, gap: 0.12, decay: 0.7)
        case .squabble: return CueSpec(i: 0.28, s: 0.28, n: 3, gap: 0.09, decay: 0.7)
        case .chase: return CueSpec(i: 0.22, s: 0.16, n: 4, gap: 0.11, decay: 0.9)
        case .nuzzle: return CueSpec(i: 0.09, s: 0.05, n: 3, gap: 0.2, decay: 0.9)
        case .sitTogether: return CueSpec(i: 0.15, s: 0.09, n: 2, gap: 0.09, decay: 0.5)
        case .dance: return CueSpec(i: 0.24, s: 0.15, n: 4, gap: 0.15, decay: 0.9)
        case .sneak: return CueSpec(i: 0.10, s: 0.20, n: 2, gap: 0.3, decay: 1.4)
        case .keepAway: return CueSpec(i: 0.20, s: 0.17, n: 3, gap: 0.14, decay: 0.85)
        case .line: return CueSpec(i: 0.16, s: 0.12, n: 3, gap: 0.16, decay: 0.9)
        case .pass: return CueSpec(i: 0.25, s: 0.24, n: 2, gap: 0.1, decay: 0.5)
        case .bagSit: return CueSpec(i: 0.18, s: 0.08, n: 2, gap: 0.1, decay: 0.5)
        case .cuddle: return CueSpec(i: 0.11, s: 0.04, n: 3, gap: 0.25, decay: 0.95)
        case .chestBump: return CueSpec(i: 0.39, s: 0.14, n: 3, gap: 0.07, decay: 0.5)
        case .highFive: return CueSpec(i: 0.30, s: 0.23, n: 1)
        case .cheekSquish: return CueSpec(i: 0.21, s: 0.10, n: 2, gap: 0.2, decay: 0.9)
        case .twirl: return CueSpec(i: 0.19, s: 0.12, n: 4, gap: 0.09, decay: 0.8)
        case .hopAlong: return CueSpec(i: 0.26, s: 0.17, n: 2, gap: 0.22, decay: 0.95)
        case .littleRace: return CueSpec(i: 0.23, s: 0.15, n: 4, gap: 0.1, decay: 0.95)
        case .tag: return CueSpec(i: 0.23, s: 0.19, n: 3, gap: 0.12, decay: 0.8)
        case .leapfrog: return CueSpec(i: 0.32, s: 0.13, n: 3, gap: 0.12, decay: 0.6)
        case .peekaboo: return CueSpec(i: 0.12, s: 0.21, n: 2, gap: 0.25, decay: 1.2)
        case .bellyBounce: return CueSpec(i: 0.34, s: 0.11, n: 4, gap: 0.1, decay: 0.7)
        case .mirrorDance: return CueSpec(i: 0.21, s: 0.13, n: 4, gap: 0.14, decay: 0.9)
        case .backToBack: return CueSpec(i: 0.14, s: 0.09, n: 2, gap: 0.12, decay: 0.7)
        case .cuddleLean: return CueSpec(i: 0.10, s: 0.05, n: 2, gap: 0.2, decay: 0.8)
        case .ringAround: return CueSpec(i: 0.20, s: 0.12, n: 5, gap: 0.12, decay: 0.9)
        case .swayHug: return CueSpec(i: 0.09, s: 0.05, n: 4, gap: 0.2, decay: 0.9)
        case .danceOff: return CueSpec(i: 0.25, s: 0.17, n: 3, gap: 0.16, decay: 0.85)
        case .whisperGiggle: return CueSpec(i: 0.13, s: 0.21, n: 3, gap: 0.1, decay: 0.8)
        case .shyWave: return CueSpec(i: 0.08, s: 0.13, n: 2, gap: 0.2, decay: 0.8)
        case .groupHug: return CueSpec(i: 0.19, s: 0.06, n: 4, gap: 0.14, decay: 0.85)
        case .groupCheer: return CueSpec(i: 0.30, s: 0.18, n: 3, gap: 0.12, decay: 0.7)
        case .conga: return CueSpec(i: 0.22, s: 0.15, n: 4, gap: 0.17, decay: 0.95)
        case .circleDance: return CueSpec(i: 0.21, s: 0.14, n: 5, gap: 0.13, decay: 0.9)
        case .congaLine: return CueSpec(i: 0.15, s: 0.11, n: 3, gap: 0.19, decay: 0.95)
        case .ringDance: return CueSpec(i: 0.16, s: 0.10, n: 4, gap: 0.16, decay: 0.95)
        case .spinHug: return CueSpec(i: 0.12, s: 0.07, n: 3, gap: 0.18, decay: 0.95)
        }
    }
}

extension HapticDriver {
    /// Test seams: the clock, the delayed-pulse scheduler, the jitter (+-15 %), and every accepted cue.
    nonisolated(unsafe) static var clock: () -> Double = { CACurrentMediaTime() }
    nonisolated(unsafe) static var after: (Double, @escaping @MainActor () -> Void) -> Void = { d, f in DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated { f() } } }
    nonisolated(unsafe) static var jitter: () -> Float = { 1 + Float.random(in: -0.15...0.15) }
    nonisolated(unsafe) static var cueTap: ((HapticCue) -> Void)?
    /// The one driver the room's cues go through (the stage's touch driver; nil in headless suites that set none).
    nonisolated(unsafe) static weak var room: HapticDriver?
    /// A race / volleyball / bath gives its own haptics: the stage sets this.
    nonisolated(unsafe) static var roomBusy: (() -> Bool)?
    static let roomMinGap: Double = 0.5
    static let roomIdleShutdown: Double = 30

    /// Play a cue. True = accepted. Cheap when refused (one flag / one defaults read).
    @discardableResult
    func cue(_ c: HapticCue, energy: Float = 1) -> Bool {
        guard !warm, HapticSettings.enabled, !(Self.roomBusy?() ?? false) else { return false }
        let now = Self.clock()
        guard now - roomLast >= Self.roomMinGap else { roomDropped += 1; return false }
        roomLast = now; roomRequests += 1
        Self.cueTap?(c)
        let pulses = c.pulses(energy: energy, jitter: Self.jitter())
        guard !sinks.isEmpty else { return true }
        holdRoomEngine()
        for p in pulses {
            if p.delay == 0 { for k in sinks { k.transient(intensity: p.i, sharpness: p.s) } }
            else { Self.after(p.delay) { [weak self] in guard let self, self.roomEngineHeld || self.warm else { return }; for k in self.sinks { k.transient(intensity: p.i, sharpness: p.s) } } }
        }
        return true
    }

    /// Engine up for the room (when focus mode has it warm already, nothing to do); down again `roomIdleShutdown` s after the last use.
    func holdRoomEngine() {
        if !warm, !roomEngineHeld { for s in sinks { s.start() }; roomEngineHeld = true; roomEngineStarts += 1 }
        roomShutdown?.cancel()
        guard !warm else { return }
        roomShutdown = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.roomIdleShutdown))
            guard !Task.isCancelled, let self, !self.warm, self.roomEngineHeld else { return }
            for s in self.sinks { s.stop() }; self.roomEngineHeld = false
        }
    }
}

extension BlobBrain {
    /// A move's haptic (not while this Jelbie races or plays volleyball: they give their own; the global guards are in `HapticDriver.cue`).
    func roomCue(_ c: HapticCue, energy: Float = 1) {
        guard !race.active, !volley.active else { return }
        HapticDriver.room?.cue(c, energy: energy)
    }
    func emoteHaptic(_ p: EmoteCue, energy: Float = 1) { roomCue(.emote(p), energy: energy) }
}
