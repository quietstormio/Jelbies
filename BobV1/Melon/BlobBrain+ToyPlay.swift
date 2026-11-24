//
//  BlobBrain+ToyPlay.swift
//  Toys matter (2026-10-25): the loop is   put a toy down -> the nearest one or two notice within 1...2 s and go and play -> later they wander off and do other
//  things -> come back now and then -> the player puts it away.
//    NOTICE   a piece placed, turned or put down again is news (Room/DecorField+Toys.swift). The nearest `noticeNearest` awake free Jelbies (all of them for a
//             toy that takes several players) look at it with an excited face, and 1...2 s later walk over and use it (`decorStart(..., uid:)`).
//    PULL     every decor behaviour's idle weight is scaled by the pull of the best piece for it (fresh = high, decays over minutes to a lower but non-zero
//             baseline; x0.08 right after a play, back over ~2.5 min), and the shuffle-bag gives the decor family more turns while a toy has pull.
//    TURNS    a single-user toy that is busy: the next Jelbie walks to a WATCH SPOT outside it (clear of the user's spot and of the other waiter), looks,
//             cheers now and then, and goes in when the toy is free and he is first in the queue (oldest waiter). 16 s without a turn: he gives up and the toy is
//             off his list for 90 s. At most two wait.
//    TOGETHER a seat piece with two seats (loveseat, swing, dining set, cushion pile) takes both; a free ball is passed between two (the pass social); a boop of
//             the bubble machine sends the others to hop under the bubbles.
//  Built from the existing moves only (look, joy, bounce, the decor sits / boops / kicks); the arms stay thumbs and the feet stay attached.
//

import Foundation
import simd

/// One brain's toy-play state (no per-frame allocation: scalars; the boredom dictionary only grows when he gives a toy up).
struct ToyBrain {
    var handled = 0
    var noticeUID = -1
    var noticeAt: Float = 0
    var noticeLooked = false
    var waitUID = -1
    var waitSince: Float = 0
    var waitDeadline: Float = 0
    /// A waiter who was moved on before his deadline (asked to step aside, a touch) goes back to the queue when he is free again.
    var retryUID = -1
    var retryUntil: Float = 0
    var checkAt: Float = 0
    var lookAt: Float = 0
    var bored: [Int: Float] = [:]
    /// The piece of his last toy session (the next choice leans away from it: variety across the toys that are out).
    var lastUID = -1
    /// Variety clock of his last direct toy start.
    var lastDirect: Float = -999
    /// Park only (ParkPlayTuning): the toy clock before which he does not pick this big toy again by himself (the slide, the hopscotch court).
    var parkCool: [DecorKind: Float] = [:]
    var burstHandled = 0
    var chaseSpot: SIMD2<Float>?
    var chaseUntil: Float = 0
    /// toy-audit-r1 audience (drum dance, top watch, hoop cheer, mat queue): the piece, who plays, 0 none / 1 walking / 2 there, the spot, deadline, next move, cool-down, shows handled, state flags.
    var audUID = -1, audBy = -1, audStage = 0
    var audSpot = SIMD2<Float>.zero
    var audUntil: Float = 0, audNext: Float = 0, audCool: Float = 0, audPoll: Float = 0
    var audShown: [Int: Float] = [:]
    var audReacted = false, audTurn = false
    var audBeat: Float = 0
    var shared = 0, joined = 0
    /// Counters (tests / the report).
    var noticed = 0, queued = 0, tookTurn = 0, gaveUp = 0, chased = 0
}

extension BlobBrain {
    var toyPeers: [BlobBrain] { socialOthers().filter { $0 !== self } }          // (was private: the seesaw's invitation, Park/SeesawRide.swift, ranks the free Jelbies)

    /// Nothing owns him: a toy may take him now.
    var toyFree: Bool {          // (was private: same reason)
        anticsEnabled && !decorLocked && reactFree && scriptIsNone && idleState.kind == nil && !race.active && idleMood != .grumpy && idleNight < 0.6
    }

    /// Does the toy take several players at once (so everyone present joins at once)?
    static func toyTakesMany(_ k: DecorKind) -> Bool { k == .hopscotch || k.sitPoints.count > 1 || k.isBallLike || k == .bubblemachine }

    /// Weight multiplier of a decor behaviour: the pull of the best piece that offers it (1 when the room has none).
    func toyWeight(_ k: IdleKind) -> Float {
        guard Self.decorKinds.contains(k) else { return 1 }
        let f = DecorField.shared
        var best: Float = -1
        for p in f.feet where p.kind.activeInteraction == k && f.available(p) {
            if let until = toy.bored[p.uid], until > f.toys.clock { continue }
            best = max(best, f.toyPull(p.uid))
        }
        if best < 0 { return 1 }
        return 0.7 + ToyTuning.weightGain * best
    }
    /// Extra turns of the decor family in the shuffle-bag (0...2) while a toy has pull.
    func toyBagBonus() -> Int {
        let f = DecorField.shared
        var best: Float = 0
        for p in f.feet where p.kind.activeInteraction != nil && f.available(p) { best = max(best, f.toyPull(p.uid)) }
        return Int((2 * best).rounded()) + (outingPlay ? ParkPlayTuning.bagBonus : 0)
    }

    // MARK: the tick (idleGate, no behaviour running)

    func toyTick(_ sim: SoftBody) {
        let probe = PerfProbe.begin(); defer { PerfProbe.end("toyTick", probe) }
        let f = DecorField.shared
        if f.feet.isEmpty || !anticsEnabled || !autonomy || held {
            if toy.waitUID >= 0 || toy.noticeUID >= 0 || toy.chaseSpot != nil { toyClear() }
            return
        }
        let clock = f.toys.clock
        // 1. news: a new toy is looked at, then played with
        if toy.noticeUID < 0, toy.waitUID < 0, toyFree, let n = f.toys.news.first(where: { $0.serial > toy.handled }) {
            toy.handled = n.serial
            if toyShouldNotice(n) {
                toy.noticeUID = n.uid; toy.noticeAt = clock + rand(ToyTuning.noticeDelay.lowerBound, ToyTuning.noticeDelay.upperBound); toy.noticeLooked = false
                toy.noticed += 1
            }
        }
        if toy.noticeUID >= 0 {
            guard let foot = f.foot(toy.noticeUID) else { toy.noticeUID = -1; return }
            guard reactFree, scriptIsNone, pending == nil else { if clock > toy.noticeAt + 6 { toy.noticeUID = -1 }; return }
            if !toy.noticeLooked {
                toy.noticeLooked = true
                _ = beginLook(at: f.position(foot), hold: max(0.8, toy.noticeAt - clock + 0.3), resume: nil, face: .excited, kind: .watch)
                return
            }
            if clock >= toy.noticeAt { let uid = toy.noticeUID; toy.noticeUID = -1; toyGo(uid, sim) }
            return
        }
        // 2. a bubble burst: everyone hops under the bubbles
        if f.toys.burstSerial > toy.burstHandled, clock - f.toys.burstT < 2.0 {
            if toyFree, toy.waitUID < 0 {
                toy.burstHandled = f.toys.burstSerial
                if f.toys.burstBy != steerID, rand() < 0.85, simd_distance(position, f.toys.burstPos) < 7 { toyChase(around: f.toys.burstPos) }
            }
        }
        if let spot = toy.chaseSpot {
            guard toyFree, pending == nil, clock < toy.chaseUntil else { if clock >= toy.chaseUntil || held { toy.chaseSpot = nil }; return }
            if simd_distance(position, spot) < 0.7 {
                toy.chaseSpot = nil
                face(.excited, hold: 1.2)
                _ = idleStart(rand() < 0.5 ? .bounce : .skipHop, sim)
            } else if scriptIsNone, toy.chaseUntil - clock > 0.5 { requestNow(.goTo(spot)) }
            return
        }
        // 2a. toy-audit-r1: a housemate watches / dances / cheers at a toy someone else is playing
        if toyAudienceTick(sim, f, clock) { return }
        // 2b. moved on from the queue before his deadline: back in line once he is free
        if toy.retryUID >= 0 {
            if clock > toy.retryUntil || f.foot(toy.retryUID) == nil { toy.retryUID = -1 }
            else if toyFree, pending == nil, toy.noticeUID < 0 { let u = toy.retryUID; toy.retryUID = -1; toyGo(u, sim); return }
        }
        // 3. waiting for a turn
        if toy.waitUID >= 0 { toyWaitTick(sim, f, clock) }
    }

    private func toyClear() { toy.noticeUID = -1; toy.waitUID = -1; toy.chaseSpot = nil; toy.retryUID = -1; toy.audUID = -1; toy.audStage = 0 }

    private func toyShouldNotice(_ n: ToyNews) -> Bool {
        let f = DecorField.shared
        guard let foot = f.foot(n.uid) else { return false }
        if SeesawRide.shared.isInvite(n.serial) { return seesawJoinRoll(n) }          // (a lone seesaw rider asks for company: one roll, the nearest free Jelbie: Park/SeesawRide.swift)
        if foot.kind == .hopscotch { return HopscotchLine.shared.invitation(foot.uid, steerID, roll: rand()) }          // (a line started: each free Jelbie rolls once for joining it)
        // the goal stands for its ball
        var uid = n.uid, kind = foot.kind
        if kind == .minigoal, let ball = f.feet.first(where: { $0.kind == .soccerball }) { uid = ball.uid; kind = .soccerball }
        guard kind.activeInteraction != nil else { return false }
        if let until = toy.bored[uid], until > f.toys.clock { return false }
        let p = f.foot(uid).map { f.position($0) } ?? n.pos
        var ranked = toyPeers.filter { $0.toyFree }
        ranked.append(self)
        ranked.sort { simd_distance($0.position, p) < simd_distance($1.position, p) }
        ranked = BondPairing.friendsFirst(ranked, at: uid)          // (best-friend-r1: whose best friend is already there goes first)
        let limit = Self.toyTakesMany(kind) ? ranked.count : ToyTuning.noticeNearest
        guard let i = ranked.firstIndex(where: { $0 === self }), i < limit else { return false }
        return true
    }

    // MARK: going to a toy

    /// Walk to the piece and use it now; a busy piece: take a place in the queue.
    func toyGo(_ uid: Int, _ sim: SoftBody) {
        let f = DecorField.shared
        var foot = f.foot(uid)
        if foot?.kind == .minigoal, let ball = f.feet.first(where: { $0.kind == .soccerball }) { foot = ball }
        guard let foot, let mv = foot.kind.activeInteraction else { return }
        let id = foot.uid
        if f.available(foot) {
            if foot.kind.isBallLike, toyTryPass(sim) { return }
            parkGateRejected = -1
            if decorStart(mv, sim, only: nil, uid: id) { idleState.cooldown = max(idleState.cooldown, 3); return }
            if parkGateRejected == id { return }          // (the park's pick roll said "not now": he does not queue at it)
            toyQueue(foot, sim)          // (no way in right now - the one before him is still stepping off, a friend stands in the way: wait nearby, he tries again; the deadline ends it)
            return
        }
        toyQueue(foot, sim)
    }

    /// A free ball and a free friend: the pass social (they kick it to each other); true = started.
    private func toyTryPass(_ sim: SoftBody) -> Bool {
        guard socialBook.enabled, rand() < 0.75 else { return false }
        let friends = toyPeers.filter { $0.socialFree && $0.reactFree && $0.react.pending == nil }.sorted { simd_distance($0.position, position) < simd_distance($1.position, position) }
        for o in BondPairing.bestFirst(friends, chooser: self) where socialStart(.pass, with: o, sim) { return true }
        return false
    }

    private func toyQueue(_ foot: DecorFoot, _ sim: SoftBody) {
        let f = DecorField.shared
        let uid = foot.uid
        let waiting = toyPeers.filter { $0.toy.waitUID == uid }.count
        guard waiting < ToyTuning.queueMax, let spot = toyWatchSpot(foot) else { toy.bored[uid] = f.toys.clock + 25; return }
        toy.waitUID = uid; toy.waitSince = f.toys.clock; toy.waitDeadline = f.toys.clock + foot.kind.queueTimeout
        toy.checkAt = f.toys.clock + 0.6; toy.lookAt = f.toys.clock + rand(1.0, 2.0)
        toy.queued += 1
        if simd_distance(position, spot) > 0.5 { requestNow(.goTo(spot)) }
    }

    private func toyWaitTick(_ sim: SoftBody, _ f: DecorField, _ clock: Float) {
        guard let foot = f.foot(toy.waitUID), clock < toy.waitDeadline, toyFreeForQueue else {
            if toy.waitUID >= 0, clock >= toy.waitDeadline { toy.bored[toy.waitUID] = clock + ToyTuning.boredFor; toy.gaveUp += 1; idleState.cooldown = max(idleState.cooldown, rand(2, 4)) }
            else if toy.waitUID >= 0, clock < toy.waitDeadline, f.foot(toy.waitUID) != nil { toy.retryUID = toy.waitUID; toy.retryUntil = toy.waitDeadline }
            toy.waitUID = -1
            return
        }
        guard scriptIsNone, pending == nil else { return }
        let uid = foot.uid
        if clock >= toy.checkAt {
            toy.checkAt = clock + 0.4
            if f.available(foot), toyFirstInQueue(uid) {
                toy.waitUID = -1
                if let mv = foot.kind.activeInteraction, decorStart(mv, sim, only: nil, uid: uid) { toy.tookTurn += 1; idleState.cooldown = max(idleState.cooldown, 3) }
                else { toy.waitUID = uid; toy.checkAt = clock + 0.8 }          // (his way in is not free yet - the one before him is still stepping off: keep waiting; the deadline ends it)
                return
            }
        }
        if clock >= toy.lookAt {
            toy.lookAt = clock + rand(2.6, 4.5)
            let busy = f.occupant[uid] != nil
            if busy, rand() < 0.3 { face(.excited, hold: 1.2); _ = idleStart(.joy, sim) }          // a cheer for the one having his go
            else { _ = beginLook(at: f.position(foot), hold: rand(1.4, 2.2), resume: nil, face: busy ? .hopeful : .curious, kind: .watch) }
        }
    }
    /// A waiter is only dropped by a real owner (a touch, a meal, a request); a look or the walk to the spot is his own.
    private var toyFreeForQueue: Bool { attached && !held && !commanded && social == nil && job == nil && !decorLocked && !race.active && commandedIdle == nil }

    /// The oldest waiter at this piece goes first (ties by id).
    private func toyFirstInQueue(_ uid: Int) -> Bool {
        for o in toyPeers where o.toy.waitUID == uid {
            if o.toy.waitSince < toy.waitSince - 1e-4 || (abs(o.toy.waitSince - toy.waitSince) <= 1e-4 && o.steerID < steerID) { return false }
        }
        return true
    }

    /// A spot outside the piece to watch from: on the side he comes from, 1.1+ from its edge, clear of the user's spot and of the other waiter.
    func toyWatchSpot(_ foot: DecorFoot) -> SIMD2<Float>? {
        let probe = PerfProbe.begin(); defer { PerfProbe.end("toyWatchSpot", probe) }
        let f = DecorField.shared
        let c = f.position(foot)
        var keepOut: [SIMD2<Float>] = []
        for o in toyPeers {
            if o.idleState.decorUID == foot.uid { keepOut.append(o.position); keepOut.append(o.idleState.target) }
            if foot.kind == .slide, o.idleState.decorUID == foot.uid { keepOut.append(c + foot.turned(SIMD2(0, Self.slideAt(Self.slideLength).z))) }          // (and the floor where a rider comes off the end)
            if o.toy.waitUID == foot.uid { keepOut.append(o.position) }
        }
        let base = simd_length(position - c) > 1e-3 ? simd_normalize(position - c) : SIMD2<Float>(0, 1)
        let a0 = atan2f(base.x, base.y)
        var g = foot; g.centre = c
        for k in 0..<13 {
            let step = Float((k + 1) / 2) * 0.5
            let a = a0 + step * (k % 2 == 0 ? 1 : -1)
            let u = SIMD2(sinf(a), cosf(a))
            var t: Float = 0.3
            let clear: Float = foot.kind == .kickscooter ? 2.0 : 1.15          // (the scooter's loop sweeps the floor round it: they watch from outside it)
            while t < 6, g.distance(c + u * t) < clear { t += 0.05 }
            let p = c + u * t
            let q = fixed(p)
            guard simd_distance(p, q) < 0.08, peerFree(q) else { continue }
            if keepOut.contains(where: { simd_distance($0, q) < 1.5 }) { continue }
            if f.feet.contains(where: { $0.uid != foot.uid && $0.spec.solid && $0.distance(q) < footprint * $0.spec.reach + 0.1 }) { continue }
            return q
        }
        return nil
    }

    // MARK: the bubble chase

    private func toyChase(around c: SIMD2<Float>) {
        let f = DecorField.shared
        // spread by id so three do not stand on one spot
        for k in 0..<8 {
            let a = Float(steerID % 3) * 2.1 + Float(k) * 0.7 + rand(-0.2, 0.2)
            let r = 1.3 + 0.25 * Float(k % 3)
            let p = c + SIMD2(sinf(a), cosf(a)) * r
            let q = fixed(p)
            guard simd_distance(p, q) < 0.08, peerFree(q), reachable(position, q) else { continue }
            if f.feet.contains(where: { $0.spec.solid && $0.distance(q) < footprint * $0.spec.reach + 0.1 }) { continue }
            toy.chaseSpot = q; toy.chaseUntil = f.toys.clock + 7; toy.chased += 1
            requestNow(.goTo(q))
            return
        }
    }
}

// MARK: the audience (toy-audit-r1)
//  Shared play from existing motions only (the walk, look, bounce, skip-hop, joy, giggle, startle):
//    drum        while one drums, a free housemate walks to a spot 1.6...2.2 from the drummer and dances (bounce / skip-hop / joy) until the drumming stops (about half the times one is free)
//    spinning top  up to two free housemates stand 1.6...2.2 from it (never within 1.3 of each other), watch it and giggle / startle when it falls
//    hoop        a watcher stands 1.6...2.2 from the shooter and cheers (the joy bounce) after the shot; half the time he then takes the next turn
//    bouncy mat  the next one waits 1.4...1.8 beside the mat, bobs while the first bounces and gets on when the first gets off
//  Only a free housemate (`toyFree`, not owned by a touch / a meal / a command): a sleeping, eating or busy one is never pulled in. Spots keep 1.3 from every body and
//  the walk there keeps 1.3 from every standing body. With nobody else at home nothing here runs.

extension BlobBrain {
    /// The audience switch: OFF by default (shared play was built but not delivered as visible moments, toy-audit-r1); dev `-ToyAudience 1` (tests: ToyAuditTests TOYAUDIENCE=1) turns it on for later work.
    nonisolated(unsafe) static var audienceOn: Bool = (DevArgs.enabled && UserDefaults.standard.integer(forKey: "ToyAudience") == 1)
    static let audienceKinds: Set<DecorKind> = [.drum, .spintop, .hoop, .bouncymat]
    static func audienceChance(_ k: DecorKind) -> Float { switch k { case .drum: return 0.4; case .spintop: return 0.45; case .hoop: return 0.4; default: return 0.2 } }
    static func audienceLimit(_ k: DecorKind) -> Int { k == .spintop ? 2 : 1 }

    /// `toyFree` without the mood clause: a grumpy one may watch too (the audience rolls at half the chance and keeps to looks: no dance, no cheer, no bounce).
    private var toyFreeAnyMood: Bool { anticsEnabled && !decorLocked && reactFree && scriptIsNone && idleState.kind == nil && !race.active && idleNight < 0.6 }
    private var audienceEligible: Bool { toyFreeAnyMood && toyFreeForQueueA && toy.waitUID < 0 && toy.noticeUID < 0 && toy.retryUID < 0 && toy.chaseSpot == nil && pending == nil }
    private var toyFreeForQueueA: Bool { attached && !held && !commanded && social == nil && job == nil && !decorLocked && !race.active && commandedIdle == nil }

    /// true = the audience owns this tick.
    func toyAudienceTick(_ sim: SoftBody, _ f: DecorField, _ clock: Float) -> Bool {
        if toy.audUID >= 0 { return toyAudienceRun(sim, f, clock) }
        guard Self.audienceOn else { return false }
        guard clock >= toy.audCool, clock >= toy.audPoll, !f.toys.shows.isEmpty else { return false }
        toy.audPoll = clock + 0.4
        guard audienceEligible else { return false }
        for uid in f.toys.shows.keys.sorted() {
            guard let show = f.toys.shows[uid], show.by != steerID, clock - show.t < 2.5, (toy.audShown[uid] ?? -1) < show.t else { continue }
            guard let foot = f.foot(uid), Self.audienceKinds.contains(foot.kind), let user = toyPeers.first(where: { $0.steerID == show.by }), user.idleState.decorUID == uid else { continue }
            toy.audShown[uid] = show.t
            let c = f.position(foot)
            if simd_distance(position, c) > 7 { continue }
            var ranked = toyPeers.filter { $0.audienceEligible && $0.toy.audCool <= clock && $0.steerID != show.by }
            ranked.append(self)
            ranked.sort { simd_distance($0.position, c) < simd_distance($1.position, c) }
            let taken = toyPeers.filter { $0.toy.audUID == uid }.count
            guard let i = ranked.firstIndex(where: { $0 === self }), i + taken < Self.audienceLimit(foot.kind) else { continue }
            guard rand() < Self.audienceChance(foot.kind) * (idleMood == .grumpy ? (ToyTuning.grumpyPlay ? 0.5 : 0) : 1) else { continue }
            // he stays where he is until the player has ARRIVED at the toy (stage 3): then the spot is chosen against where everybody really stands and he walks there (stage 1): two walkers never cross on the way in
            toy.joined += 1; toy.audUID = uid; toy.audBy = show.by; toy.audStage = 3; toy.audUntil = clock + 14
            toy.audNext = clock; toy.audReacted = false; toy.audTurn = false
            idleState.cooldown = max(idleState.cooldown, 5)
            if EmoteSpot.logOn { NSLog("[toyshare] t=%.1f id=%d joins %@ uid=%d by=%d", variety.now, steerID, foot.kind.rawValue, uid, show.by) }
            return true
        }
        return false
    }

    private func toyAudienceEnd(_ clock: Float, cool: Float = 40) {
        toy.audUID = -1; toy.audStage = 0; toy.audCool = clock + cool
        // (watching counts as his toy moment: no other toy pick at once, and a short breather before the next idle: toys are not used more overall)
        toy.lastDirect = max(toy.lastDirect, variety.now); idleState.cooldown = max(idleState.cooldown, rand(3, 6))
    }

    private func toyAudienceRun(_ sim: SoftBody, _ f: DecorField, _ clock: Float) -> Bool {
        guard let foot = f.foot(toy.audUID), toyFreeForQueueA, clock < toy.audUntil else { toyAudienceEnd(clock, cool: 20); return false }
        let uid = foot.uid
        let user = toyPeers.first { $0.steerID == toy.audBy }
        let playing = f.occupant[uid] == toy.audBy
        let arrived = user.map { !$0.idleState.decorGo && $0.idleState.decorUID == uid } ?? false
        if toy.audStage == 3 {
            guard arrived else { return true }
            guard let user, let spot = toyAudienceSpot(foot, user: user) else { toyAudienceEnd(clock, cool: 20); return false }
            toy.audSpot = spot; toy.audStage = 1
            if foot.kind == .drum { user.idleState.hold += 3 }          // (the drummer keeps the beat going for his audience: +3 s once)
            else if foot.kind == .hoop { user.idleState.hold += 2 }
            requestNow(.goTo(spot))
            return true
        }
        if toy.audStage == 1 {
            if scriptIsNone, pending == nil {
                if simd_distance(position, toy.audSpot) < 0.6 { toy.audStage = 2; toy.audNext = clock + 0.3 }
                else if clock < toy.audUntil - 4 { requestNow(.goTo(toy.audSpot)) }
                else { toyAudienceEnd(clock, cool: 20); return false }
            }
            if foot.kind != .spintop, !playing, clock - (f.toys.shows[uid]?.t ?? clock) > 1.0 { toyAudienceEnd(clock, cool: 20); return false }
            return true
        }
        // standing at the spot
        guard toyFreeAnyMood, pending == nil, scriptIsNone else { return true }
        let grump = idleMood == .grumpy
        let c = f.position(foot)
        switch foot.kind {
        case .drum:
            guard playing else { toyAudienceEnd(clock, cool: 45); return false }
            guard arrived else { return true }
            // the drummer keeps the beat going a little longer for his audience (once, +3 s on his own hold) and thumps it every 0.8 s: the same thump + sound as his own
            if !toy.audReacted { toy.audReacted = true; toy.audBeat = clock + 0.4 }
            if let user, clock >= toy.audBeat, user.idleState.kind == .decorBoop, user.idleState.decorBooped {
                toy.audBeat = clock + 0.8
                user.jellyKick = max(user.jellyKick, 1.2)
                f.kick(uid, 0.8)
                AudioHub.shared.play(.boop, jelly: user.steerID, x: user.px, volume: 0.8, rate: Float(0.5 + 0.08 * Double(Int(rand() * 4))))
            }
            guard clock >= toy.audNext else { return true }
            toy.audNext = clock + 0.5
            if !grump { face(.excited, hold: 1.4) }
            let moves: [IdleKind] = [.bounce, .skipHop, .joy, .bounce]
            if grump { _ = beginLook(at: c, hold: 1.6, resume: nil, face: .curious, kind: .watch) }
            else if idleStart(moves[toy.shared % moves.count], sim) { toy.shared += 1 } else { _ = beginLook(at: c, hold: 1.2, resume: nil, face: .excited, kind: .watch) }
        case .spintop:
            let a = f.anim[uid]
            if toy.audReacted { toyAudienceEnd(clock, cool: 45); return false }
            if let a, a.fallT >= 0, a.fallT < 1.2 {
                toy.audReacted = true; toy.shared += 1
                if !grump { face(.excited, hold: 1.4) }
                if !idleStart(grump || rand() >= 0.65 ? .startle : .giggle, sim) { _ = beginLook(at: c, hold: 1.0, resume: nil, face: .excited, kind: .watch) }
            } else if clock >= toy.audNext {
                toy.audNext = clock + rand(1.6, 2.6)
                _ = beginLook(at: c, hold: rand(1.2, 1.8), resume: nil, face: .curious, kind: .watch)
            } else if clock > (f.toys.shows[uid]?.t ?? clock) + 10 { toyAudienceEnd(clock, cool: 30); return false }
        case .hoop:
            if toy.audReacted {
                toyAudienceEnd(clock, cool: 45)
                if toy.audTurn, rand() < 0.5 { toyGo(uid, sim) }
                return false
            }
            guard playing else { toyAudienceEnd(clock, cool: 30); return false }
            if user?.idleState.decorBooped == true {
                toy.audReacted = true; toy.audTurn = true; toy.shared += 1
                if grump { _ = beginLook(at: c, hold: 1.4, resume: nil, face: .curious, kind: .watch) } else { face(.excited, hold: 1.4); _ = idleStart(.joy, sim) }
            } else if clock >= toy.audNext {
                toy.audNext = clock + rand(1.4, 2.2)
                _ = beginLook(at: c, hold: rand(1.0, 1.6), resume: nil, face: .hopeful, kind: .watch)
            }
        default:          // bouncy mat: bob while the first bounces, take the turn as he gets off
            if !playing {
                // the first one is off the mat's pad AND out of the waiter's way before the next steps on (never two bodies on one spot)
                if let user, simd_distance(user.position, c) < 2.4 || simd_distance(user.position, position) < 1.6 { return true }          // (the first is well off the mat: bodies never closer than 1.2 on the way on)
                toyAudienceEnd(clock, cool: 60)
                toy.shared += 1
                if rand() < 0.5 { toyGo(uid, sim) }          // (half the time he takes the turn: the mat is not used more overall)
                return false
            }
            if clock >= toy.audNext, arrived {
                toy.audNext = clock + rand(1.6, 2.4)
                if grump { _ = beginLook(at: c, hold: 1.4, resume: nil, face: .curious, kind: .watch) } else { face(.excited, hold: 1.2); _ = idleStart(.bounce, sim) }
            }
        }
        return true
    }

    /// A spot for a watcher: round the player (drum, hoop) or the piece (top, mat), 1.6...2.2 (the mat: 1.4...1.8 from its edge), 1.3 from every body, the walk 1.3 clear of every standing body.
    func toyAudienceSpot(_ foot: DecorFoot, user: BlobBrain) -> SIMD2<Float>? {
        let f = DecorField.shared
        let c = f.position(foot)
        let aroundUser = foot.kind == .drum || foot.kind == .hoop
        let centre = aroundUser ? user.idleState.target : c
        let userSpot = user.idleState.target
        var bodies: [SIMD2<Float>] = [userSpot]
        for o in toyPeers { bodies.append(o.position); if o.toy.audUID >= 0 { bodies.append(o.toy.audSpot) } }
        let base = simd_length(position - centre) > 1e-3 ? simd_normalize(position - centre) : SIMD2<Float>(0, 1)
        let a0 = atan2f(base.x, base.y)
        for k in 0..<18 {
            let off = Float((k + 1) / 2) * 0.35 * (k % 2 == 0 ? 1 : -1)
            let a = a0 + off
            let u = SIMD2(sinf(a), cosf(a))
            let r: Float = foot.kind == .bouncymat ? 0 : 1.6 + 0.3 * Float(k % 3)
            var p = centre + u * r
            if foot.kind == .bouncymat { var t: Float = 0.3; while t < 6, foot.distance(c + u * t) < 1.4 { t += 0.05 }; p = c + u * t }
            let q = fixed(p)
            guard simd_distance(p, q) < 0.08, peerFree(q) else { continue }
            if foot.kind != .bouncymat, foot.distance(q) < 0.9 { continue }
            if bodies.contains(where: { simd_distance($0, q) < 1.3 }) || simd_distance(userSpot, q) < 1.6 { continue }
            if f.feet.contains(where: { $0.uid != foot.uid && $0.spec.solid && $0.distance(q) < footprint * $0.spec.reach + 0.1 }) { continue }
            // the walk keeps as far from every standing body as it already is, and at least 1.3 where it can
            var clear = true
            for o in toyPeers {
                let d = Self.segDist(o.position, position, q)
                if d < min(1.3, simd_distance(position, o.position)) - 0.05 { clear = false; break }
            }
            guard clear, reachable(position, q) else { continue }
            return q
        }
        return nil
    }
    static func segDist(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a, l2 = simd_dot(ab, ab)
        if l2 < 1e-6 { return simd_distance(p, a) }
        let t = min(1, max(0, simd_dot(p - a, ab) / l2))
        return simd_distance(p, a + ab * t)
    }
}
