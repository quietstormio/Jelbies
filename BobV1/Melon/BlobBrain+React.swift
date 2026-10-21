//
//  BlobBrain+React.swift
//  The reaction system (user 2026-10-20: "Add more interactions where a Jelbie is reacting to another Jelbie doing something else sometimes. We need more interaction and movement.").
//
//  An EVENT BUS lives on the roster (`SocialRoster.bus`). A brain (or the decor field) posts an event; every other awake Jelly that is free, not held (`reserved` / bath / focus),
//  not racing and within ~5 u MAY react: a chance of 35...60 % by event, a reaction cooldown of ~8 s per observer, at most two reactors per event. A reaction is a pending
//  intent with a short delay (0.4...1.6 s) that starts when the observer is free (standing, or between two steps of a plain wander leg for the in-place ones) and is
//  dropped after a few seconds. The reactions are built from the existing moves + the expression layer + the blush:
//    watch      turn and look, a curious brow            cheer      a jump for joy, excited brows, a blush
//    giggle     a quick squash bounce, "^^"              comfort    walk over and nuzzle (after a trip)
//    copycat    do the same: boop the same toy, ride the slide, a jump, kick it (a busy slide: wait and look first)
//    join       run along with a zoomies                 startle    a little hop and a surprised face (also: a ball or car rolling past within 0.8 u)
//    yawn       a contagious yawn (evening)              admire     look at a friend's new outfit / shine and blush
//    wantSome   look at the eater, hopeful (never leaves the spot: the meal lock stays)
//  Adding an event (the soccer round will): add a `BusEventKind` case, a rule row in `ReactionRules.options`, and call `postEvent(...)` where it happens.
//

import Foundation
import simd

enum ReactionKind: String, CaseIterable, Sendable { case watch, cheer, giggle, comfort, copycat, join, startle, yawn, admire, wantSome, hmph }

enum BusEventKind: String, CaseIterable, Sendable {
    case zoomies, scoredGoal, missedKick, tripped, slid, booped, towerToppled, ateTreat, wokeUp, fellAsleep, petted, newOutfit, joyJump, yawned, shined
}

struct BusEvent {
    var kind: BusEventKind
    /// The emitter's steer id (-1 = the room: the decor).
    var source: Int
    var pos: SIMD2<Float>
    var piece: DecorKind?
    var t: Float = 0
}

enum ReactionRules {
    /// Tests: switch the reactions off to find which behaviour a measurement belongs to.
    nonisolated(unsafe) static var enabled = true
    /// Per event: the chance that an observer reacts at all, and the weighted reactions to choose from.
    static func options(_ e: BusEventKind) -> (chance: Float, options: [(ReactionKind, Float)]) {
        switch e {
        case .zoomies: return (0.55, [(.cheer, 2), (.join, 2), (.watch, 2), (.giggle, 1.5), (.startle, 1), (.copycat, 1.5)])
        case .scoredGoal: return (0.60, [(.cheer, 4), (.giggle, 1), (.watch, 1)])
        case .missedKick: return (0.40, [(.giggle, 2), (.watch, 1)])
        case .tripped: return (0.55, [(.giggle, 3), (.comfort, 2), (.watch, 1)])
        case .slid: return (0.55, [(.cheer, 3), (.copycat, 3), (.watch, 1), (.giggle, 1)])
        case .booped: return (0.50, [(.copycat, 3), (.watch, 2), (.giggle, 1)])
        case .towerToppled: return (0.60, [(.giggle, 3), (.watch, 2), (.startle, 1)])
        case .ateTreat: return (0.50, [(.wantSome, 3), (.watch, 1)])
        case .wokeUp: return (0.35, [(.watch, 2), (.yawn, 1)])
        case .fellAsleep: return (0.35, [(.watch, 2), (.yawn, 2)])
        case .petted: return (0.35, [(.watch, 2), (.admire, 1)])
        case .newOutfit: return (0.60, [(.admire, 3), (.watch, 1)])
        case .shined: return (0.60, [(.admire, 3), (.watch, 1)])
        case .joyJump: return (0.55, [(.cheer, 3), (.copycat, 2), (.watch, 1), (.giggle, 1.5)])
        case .yawned: return (0.45, [(.yawn, 1)])
        }
    }
    static let reach: Float = 5
    static let cooldown: Float = 8
    static let maxReactors = 2
    static let expiry: Float = 9
}

/// One brain's reaction state.
struct ReactState {
    struct Pending { var kind: ReactionKind; var event: BusEvent; var delay: Float; var expires: Float }
    var pending: Pending?
    var cool: Float = 0
    var rollCheck: Float = 0
    var started: [ReactionKind: Int] = [:]
}


/// The room's event bus (one per roster).
final class ReactionBus {
    /// Every brain in the room (the roster's, or the stage's).
    var brains: () -> [BlobBrain] = { [] }
    var clock: Float = 0
    var rng: UInt64 = 0xD1B54A32D192ED03
    /// What happened (tests / the log).
    var posted: [BusEvent] = []
    var log: [(t: Float, event: BusEventKind, reactor: Int, kind: ReactionKind)] = []
    /// Tests: called when a reaction starts (the observer, what it is) so a suite can check the observer's state at that instant.
    var onStart: ((BlobBrain, ReactionKind) -> Void)?
    var eventCount: Int { posted.count }
    nonisolated deinit {}

    func rnd() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(rng >> 40) / Float(1 << 24)
    }

    func post(_ e: BusEvent) {
        var e = e
        e.t = clock
        posted.append(e)
        let brains = self.brains()
        let (chance, options) = ReactionRules.options(e.kind)
        var cands = brains.filter { $0.steerID != e.source && $0.canObserve(e) }
        // nearest first, then a shuffle among the near ones so it is not always the same Jelly
        cands.sort { simd_distance($0.position, e.pos) < simd_distance($1.position, e.pos) }
        var taken = 0
        var takenKinds: [ReactionKind] = []
        for b in cands {
            if taken >= ReactionRules.maxReactors { break }
            // (a mood tilts the chance: a happy Jelly joins in more, a grumpy one hardly at all)
            let mood: Float = b.idleMood == .happy ? 1.15 : (b.idleMood == .grumpy ? 0.4 : 1)
            var p = chance * mood
            if e.kind == .yawned || e.kind == .fellAsleep { p *= 0.4 + 1.6 * max(b.idleNight, 0.25) }          // a yawn spreads in the evening
            guard rnd() < p else { continue }
            // the second reactor to one event picks among the reactions the first did not take (two different answers to one thing; the same one would only wait its turn)
            var opts = options.filter { !takenKinds.contains($0.0) }
            if opts.isEmpty { opts = options }
            let total = opts.reduce(0) { $0 + $1.1 }
            var x = rnd() * total
            var kind = opts[0].0
            for (k, w) in opts { if x < w { kind = k; break }; x -= w }
            // a grumpy Jelly huffs at somebody else's fun (a ball kicked away, a dash, a hop, a slide)
            if b.idleMood == .grumpy, [.booped, .zoomies, .joyJump, .slid].contains(e.kind) { kind = .hmph }
            if b.accept(kind, e, delay: 0.4 + 1.2 * rnd()) { taken += 1; takenKinds.append(kind) }
        }
    }
}

extension SocialRoster {
    /// The roster's bus (created with it; the brains post through `BlobBrain.postEvent`).
    var eventBus: ReactionBus { if let b = _bus { return b }; let b = ReactionBus(); b.brains = { [weak self] in self?.brains ?? [] }; _bus = b; return b }
}

extension BlobBrain {
    /// Post an event from this brain (nothing happens when he has no roster / bus).
    func postEvent(_ kind: BusEventKind, piece: DecorKind? = nil, at pos: SIMD2<Float>? = nil) {
        if startingReaction { return }          // (a reaction posts nothing: no chains)
        bus?.post(BusEvent(kind: kind, source: steerID, pos: pos ?? position, piece: piece))
    }

    // MARK: observing

    /// Awake, free, not held, not racing, near enough: may react to `e`.
    func canObserve(_ e: BusEvent) -> Bool {
        guard ReactionRules.enabled, react.cool <= 0, react.pending == nil else { return false }
        guard reactFree, idleState.kind != .sleep else { return false }
        return simd_distance(position, e.pos) <= ReactionRules.reach
    }

    /// Nothing owns him: a reaction may be taken now (or soon).
    var reactFree: Bool {
        attached && autonomy && !held && !commanded && !race.active && !isNapping && idleState.kind != .sleep && social == nil && pending == nil && job == nil
            && activity != .touched && activity != .recovering && !interruptScript && commandedIdle == nil && !commandedFlip && !commandedNameHop && !hurry
    }

    func accept(_ kind: ReactionKind, _ e: BusEvent, delay: Float) -> Bool {
        react.pending = ReactState.Pending(kind: kind, event: e, delay: delay, expires: ReactionRules.expiry)
        react.cool = ReactionRules.cooldown
        return true
    }

    // MARK: ticking

    func reactTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        react.cool = max(0, react.cool - dt)
        guard let bus else { return }
        bus.clock = max(bus.clock, expr.clock)
        // a ball or car rolling past close by: a startle (a poll, not an event: nobody posts it)
        react.rollCheck -= dt
        if react.rollCheck <= 0 {
            react.rollCheck = 0.2
            if ReactionRules.enabled, react.pending == nil, react.cool <= 0, reactFree, anticsEnabled, idleState.kind == nil {
                for o in socialOthers() where o !== self && (o.runW > 0.3 || o.zoomW > 0.3) && simd_distance(o.position, position) < 1.3 && react.pending == nil {
                    // a friend dashes right past
                    _ = accept(.startle, BusEvent(kind: .zoomies, source: o.steerID, pos: o.position, t: bus.clock), delay: 0.05)
                }
                for f in DecorField.shared.feet where f.kind.rolls {
                    guard let a = DecorField.shared.anim[f.uid], simd_length(a.vel) > 0.7 else { continue }
                    let d = simd_distance(a.pos, position)
                    if d < 0.8 && d > 0.2 && idleState.decorUID != f.uid {
                        _ = accept(.startle, BusEvent(kind: .zoomies, source: -1, pos: a.pos, piece: f.kind, t: bus.clock), delay: 0.05)
                        break
                    }
                }
            }
        }
        guard var p = react.pending else { return }
        p.delay -= dt; p.expires -= dt
        if p.expires <= 0 || held || race.active || isNapping || idleState.kind == .sleep || !autonomy { react.pending = nil; return }
        react.pending = p
        if !reactFree || p.delay > 0 { return }
        if startReaction(p, sim, skinner) { react.pending = nil }
    }

    /// Between two steps of a plain wander leg: the walk's goal (the in-place reactions interrupt the leg and resume it).
    private var midWalkGoal: SIMD2<Float>? {
        guard job == nil, idleState.kind == nil, route.isEmpty, !walkFinal, !feet.active, case .walk(let t, let then) = script else { return nil }
        if case .none = then { return t }
        return nil
    }

    private var standing: Bool { if case .none = script { return idleState.kind == nil }; return false }

    /// Start the reaction now if the moves allow it. True = started (or dropped for good); false = try again next tick.
    private func startReaction(_ p: ReactState.Pending, _ sim: SoftBody, _ skinner: Skinner) -> Bool {
        startingReaction = true; defer { startingReaction = false }
        let e = p.event
        let resume = midWalkGoal
        let canInPlace = standing || resume != nil
        // never the same move as a friend is in right now: the second reactor to one event follows once the first is done, and a copycat copies AFTER the friend has finished
        // (the join is the one deliberate run-along; the comfort is a social session with its own rules)
        if let move = Self.reactionMove(p.kind, e), othersDoing(move) { return false }
        var started = false
        switch p.kind {
        case .watch:
            guard canInPlace else { return false }
            started = beginLook(at: e.pos, hold: rand(1.5, 2.5), resume: resume, face: .curious, kind: .watch)
        case .admire:
            guard canInPlace else { return false }
            started = beginLook(at: e.pos, hold: rand(2.0, 3.0), resume: resume, face: .happy, kind: .admire)
            if started { blushBump(hold: 3.2, peak: 0.85) }
        case .wantSome:
            guard canInPlace else { return false }
            started = beginLook(at: e.pos, hold: rand(2.0, 3.0), resume: resume, face: .hopeful, kind: .wantSome)
        case .cheer:
            guard canInPlace, fastOthers() < 2, kindCool[.joy] == nil else { return false }
            started = idleStart(.joy, sim)
            if started { idleState.resume = resume; idleState.reaction = .cheer; kindCooldownStart(.joy); face(.excited, hold: 1.1); blushBump(hold: 2.4, peak: 0.7) }          // (a reaction posts nothing: no chains of cheers)
        case .giggle:
            guard canInPlace else { return false }
            started = idleStart(.giggle, sim)
            if started { idleState.resume = resume; idleState.reaction = .giggle; kindCooldownStart(.giggle) }
        case .startle:
            guard canInPlace, fastOthers() < 2 else { return false }
            let away = position - e.pos
            let l = simd_length(away)
            let dir = l > 1e-3 ? away / l : -SIMD2(sinf(yaw), cosf(yaw))
            let spot = fixed(position + dir * 0.25)
            started = idleStart(.startle, sim, goal: spot)
            if started { idleState.resume = resume; idleState.reaction = .startle; kindCooldownStart(.startle); face(.surprised, hold: 1.3) }
        case .hmph:
            guard standing else { return false }
            started = idleStart(.hmph, sim)
            if started { idleState.reaction = .hmph }
        case .yawn:
            guard standing, !commanded else { return false }
            started = idleStart(.yawn, sim)
            if started { idleState.reaction = .yawn }
        case .comfort:
            guard standing, let victim = socialBrain(e.source) else { return p.expires > 1 ? false : true }
            guard victim.socialFree else { return false }
            started = socialStart(.nuzzle, with: victim, sim)
            if started { face(.worried, hold: 1.5) }
        case .join:
            guard standing, fastOthers() < 2 else { return false }
            started = idleStart(.zoomies, sim)
            if started { idleState.reaction = .join; kindCooldownStart(.zoomies) }
        case .copycat:
            guard standing, fastOthers() < 2 else { return false }
            switch e.kind {
            case .booped, .towerToppled:
                started = decorStart(e.piece == .blocks ? .decorKick : .decorBoop, sim, only: e.piece)
            case .slid:
                started = decorStart(.decorSlide, sim)
                if !started, !DecorField.shared.kinds(.slide).isEmpty, p.expires > 2.5 {
                    // the slide is busy: wait beside it, looking, hopeful; then take a turn
                    if beginLook(at: e.pos, hold: 2.6, resume: nil, face: .hopeful, kind: .copycat) {
                        react.pending = ReactState.Pending(kind: .copycat, event: e, delay: 3.0, expires: p.expires - 0.2)
                    }
                    return false
                }
            case .joyJump, .scoredGoal:
                started = idleStart(.joy, sim)
                if started { kindCooldownStart(.joy); face(.excited, hold: 1.1) }
            case .zoomies:
                started = idleStart(.run, sim)
            default: started = false
            }
            if started { idleState.reaction = .copycat }
        }
        if started {
            react.started[p.kind, default: 0] += 1
            bus?.log.append((bus?.clock ?? 0, e.kind, steerID, p.kind))
            bus?.onStart?(self, p.kind)
        }
        return started
    }

    /// The idle move a reaction starts (nil: a social session or the deliberate run-along).
    static func reactionMove(_ k: ReactionKind, _ e: BusEvent) -> IdleKind? {
        switch k {
        case .watch, .admire, .wantSome: return .stopLook
        case .cheer: return .joy
        case .giggle: return .giggle
        case .startle: return .startle
        case .hmph: return .hmph
        case .yawn: return .yawn
        case .join, .comfort: return nil
        case .copycat:
            switch e.kind {
            case .booped, .towerToppled: return e.piece == .blocks ? .decorKick : .decorBoop
            case .slid: return .decorSlide
            case .joyJump, .scoredGoal: return .joy
            case .zoomies: return .run
            default: return nil
            }
        }
    }

    /// Turn to `pos` and look (a flourish-class look: resumes the walk it interrupted).
    func beginLook(at pos: SIMD2<Float>, hold: Float, resume: SIMD2<Float>?, face f: FaceKind, kind: ReactionKind) -> Bool {
        guard idleState.kind == nil else { return false }
        idleBegin(.stopLook)
        idleState.reaction = kind
        idleState.resume = resume
        idleState.baseYaw = resume.map { yawTo($0) } ?? yaw
        idleState.hold = hold
        idleState.goalYaw = clampedLook(yawTo(pos))
        script = .idle; activity = .lookingAround
        face(f, hold: hold + 1.2)
        kindCooldownStart(.stopLook)
        return true
    }
}
