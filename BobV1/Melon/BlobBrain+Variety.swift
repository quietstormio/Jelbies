//
//  BlobBrain+Variety.swift
//  The variety layer (2026-10-24, "when it's three they repeat themselves"): sits on top of the idle / social weights, which stay the base score.
//    1 RECENCY      each kind (idle, decor, social) has a recovery curve after it was done: x0.05 right after, back to 1 over ~3.5 min (longer for big specials);
//                   the same FAMILY twice in a row is penalised too;
//    2 SHUFFLE-BAG  the next family (movement / spot play / rest / decor / social) is drawn from a refilling bag, so every family comes before any repeats;
//    3 ANTI-SYNC    a kind a friend is doing or began lately is x0.25; nobody starts a friend's special within 10 s; timers get +-35 % jitter and a start offset;
//    4 PERSONALITY  one table per character (`VarietyTuning.personality`);
//    5 DURATIONS    fixed holds are drawn +-30 % (`vDur`);
//    6 CROWD        plain wander x0.6 with three in the room.
//  Everything is off unless `anticsEnabled` (the room); it uses the brain's own seeded RNG, so a replay is the same.
//

import Foundation

enum VarietyFamily: Int, CaseIterable, Sendable { case movement, spot, rest, decor, social }

enum VarietyTuning {
    /// Seconds for a kind to come back to full weight (x floor right after); the big specials take longer.
    static let recover: Float = 210, bigRecover: Float = 360, floor: Float = 0.05
    static let bigKinds: Set<IdleKind> = [.zoomies, .slide, .cartwheel, .soccerKick, .flapHop, .lieDown, .tail]          // (the decor moves are not here: a toy that is out recovers at the ordinary pace, so the slide is not shut for 6 minutes after a ride)
    static let socialRecover: Float = 150
    /// A friend did / is doing the same lately.
    static let syncWindow: Float = 20, syncMul: Float = 0.25, startGap: Float = 10
    static let familyRepeat: Float = 0.4
    static let timerJitter: Float = 0.35, durJitter: Float = 0.30
    /// Plain wander's share with three in the room.
    static let crowdWander: Float = 0.6
    /// Shuffle-bag counts per family (rest grows at night).
    static let bag: [(VarietyFamily, Int)] = [(.movement, 3), (.spot, 3), (.rest, 1), (.decor, 3), (.social, 2)]          // (decor 1 -> 3: toys that are out are played with ~35-50 % of the time; the family only counts while a toy is out)
    static let socialBoost: Float = 2.5, socialBoostFor: Float = 15

    /// Personality per CHARACTER (the roster's feature: none = Bob, spines = Pip, daisy = Moss, wings = Lavender). Edit here.
    struct Personality {
        var idle: [(Set<IdleKind>, Float)] = []
        var social: [(Set<SocialKind>, Float)] = []
        var socialChance: Float = 1
    }
    static let personality: [JellyFeature: Personality] = [
        .none: Personality(),
        .spines: Personality(     // Pip: energetic
            idle: [([.run, .zoomies, .slide, .scoot, .bounce, .skipHop, .hopscotch, .joy, .jacks, .cartwheel, .decorHop, .decorKick, .soccerKick], 1.6), ([.sit, .lieDown, .flop, .slump, .sigh, .yawn], 0.6)],
            social: [([.chase, .zoomies, .bump, .keepAway], 1.6)]),
        .daisy: Personality(      // Moss: calm
            idle: [([.look, .window, .flop, .sit, .stretch, .sway, .decorSit, .decorBoop, .decorPeek], 1.6), ([.zoomies], 0.6)],
            social: [([.sitTogether, .bagSit, .cuddle], 1.6)]),
        .wings: Personality(      // Lavender: playful-floaty
            idle: [([.flapHop, .tail, .legSpin, .skipHop, .chirp], 1.6)],
            social: [([.nuzzle, .dance, .cuddle, .greet], 1.6)], socialChance: 1.6),
    ]
}

struct VarietyBook {
    var now: Float = 0
    var started = false
    var last: [IdleKind: Float] = [:]
    var lastSocial: [SocialKind: Float] = [:]
    var lastSocialAny: Float = -999
    var lastFamily: VarietyFamily?
    var bag: [VarietyFamily] = []
    var socialUntil: Float = -1
}

extension BlobBrain {
    static func varietyFamily(_ k: IdleKind) -> VarietyFamily {
        switch k {
        case .decorSit, .decorBoop, .decorKick, .decorHop, .decorPeek, .decorSlide, .soccerKick: return .decor
        case .sit, .slump, .yawn, .flop, .lieDown, .sigh, .sleep, .stretch: return .rest
        case .wander, .run, .stumble, .zoomies, .slide, .scoot, .skipHop, .hopscotch, .trot, .flapHop, .cartwheel, .rollTrip, .stopLook: return .movement
        default: return .spot
        }
    }

    /// Every tick (idleGate): the clock, and a one-time start offset so the three do not decide on the same frame.
    func varietyTick(_ dt: Float) {
        guard anticsEnabled else { return }
        variety.now += dt
        if !variety.started {
            variety.started = true
            idleState.cooldown += Float(steerID % 3) * 2.3 + rand(0, 2.5)
            restTimer += Float(steerID % 3) * 0.7 + rand(0, 1.2)
        }
    }
    /// +-35 % on a gap; +-30 % on a hold. Both are 1 outside the room (no RNG drawn).
    func vJit() -> Float { anticsEnabled ? rand(1 - VarietyTuning.timerJitter, 1 + VarietyTuning.timerJitter) : 1 }
    func vDur(_ x: Float) -> Float { anticsEnabled ? x * rand(1 - VarietyTuning.durJitter, 1 + VarietyTuning.durJitter) : x }

    /// A behaviour began (idleBegin).
    func varietyNote(_ k: IdleKind) {
        guard anticsEnabled, k != .wander, k != .sleep else { return }
        variety.last[k] = variety.now
        variety.lastFamily = Self.varietyFamily(k)
    }
    /// A social session began (both sides).
    func varietyNoteSocial(_ k: SocialKind, with o: BlobBrain?) {
        guard anticsEnabled else { return }
        for b in [self, o].compactMap({ $0 }) { b.variety.lastSocial[k] = b.variety.now; b.variety.lastSocialAny = b.variety.now; b.variety.lastFamily = .social }
        variety.socialUntil = -1
    }

    private var variedPeers: [BlobBrain] { socialOthers().filter { $0 !== self } }

    /// The weight multiplier of an idle kind: recovery x family repeat x personality x friends x crowd.
    func varietyScale(_ k: IdleKind) -> Float {
        var m: Float = 1
        if k == .wander { return variedPeers.count >= 2 ? VarietyTuning.crowdWander : 1 }
        if let t = variety.last[k] {
            let T = VarietyTuning.bigKinds.contains(k) ? VarietyTuning.bigRecover : VarietyTuning.recover
            m *= VarietyTuning.floor + (1 - VarietyTuning.floor) * min(1, max(0, (variety.now - t) / T))
        }
        if variety.lastFamily == Self.varietyFamily(k) { m *= VarietyTuning.familyRepeat }
        if let p = VarietyTuning.personality[personalityKey] { for (s, x) in p.idle where s.contains(k) { m *= x } }
        for o in variedPeers where k != .look {
            if o.idleState.kind == k { m *= VarietyTuning.syncMul; continue }
            if let t = o.variety.last[k] {
                let ago = o.variety.now - t
                if ago < VarietyTuning.startGap { m *= 0.02 } else if ago < VarietyTuning.syncWindow { m *= VarietyTuning.syncMul }
            }
        }
        if anticsEnabled { m *= toyWeight(k) }          // (a fresh toy pulls; a long-standing one less; just played, hardly: BlobBrain+ToyPlay.swift)
        return max(0.01, m)
    }
    /// A friend began this very special within the start gap (the scheduler turns such a pick into a wander).
    func varietyPeerJustStarted(_ k: IdleKind) -> Bool {
        guard anticsEnabled, k != .wander, k != .look, k != .sleep else { return false }
        return variedPeers.contains { o in o.variety.last[k].map { o.variety.now - $0 < VarietyTuning.startGap } ?? false }
    }

    /// Next family out of the shuffle-bag (refilled, shuffled with the brain's RNG, when empty). Families that cannot happen now are left out of the refill.
    func varietyDrawFamily(decorOffered: Bool) -> VarietyFamily? {
        guard anticsEnabled else { return nil }
        if variety.bag.isEmpty {
            for (f, n0) in VarietyTuning.bag {
                var n = n0
                if f == .social, variedPeers.isEmpty || !socialBook.enabled { continue }
                if f == .decor, !decorOffered { continue }
                if f == .rest { n += Int((2 * idleNight).rounded()) }
                if f == .decor { n += toyBagBonus() + (DecorField.shared.feet.filter { $0.kind.activeInteraction != nil }.count >= 2 ? 1 : 0) }
                variety.bag += Array(repeating: f, count: n)
            }
            var i = variety.bag.count - 1
            while i > 0 { let j = min(i, Int(rand() * Float(i + 1))); variety.bag.swapAt(i, j); i -= 1 }
        }
        return variety.bag.popLast()
    }

    /// The social pick's chance multiplier (personality, the bag's turn, and a recovery since the last session of any kind).
    var varietySocialMul: Float {
        guard anticsEnabled else { return 1 }
        var m = VarietyTuning.personality[personalityKey]?.socialChance ?? 1
        if variety.now < variety.socialUntil { m *= VarietyTuning.socialBoost }
        else { m *= 0.35 + 0.65 * min(1, (variety.now - variety.lastSocialAny) / VarietyTuning.socialRecover) }
        return m
    }
    /// Social kinds: personality and recovery (own and the partner's).
    func varietyScaleSocial(_ w: inout [(SocialKind, Float)], partner o: BlobBrain) {
        guard anticsEnabled else { return }
        let p = VarietyTuning.personality[personalityKey]
        for i in w.indices {
            let k = w[i].0
            var m: Float = 1
            for b in [self, o] { if let t = b.variety.lastSocial[k] { m *= VarietyTuning.floor + (1 - VarietyTuning.floor) * min(1, (b.variety.now - t) / VarietyTuning.socialRecover) } }
            if let p { for (s, x) in p.social where s.contains(k) { m *= x } }
            w[i].1 *= max(0.01, m)
        }
    }
}
