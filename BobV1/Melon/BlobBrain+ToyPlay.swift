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
    var checkAt: Float = 0
    var lookAt: Float = 0
    var bored: [Int: Float] = [:]
    /// The piece of his last toy session (the next choice leans away from it: variety across the toys that are out).
    var lastUID = -1
    var burstHandled = 0
    var chaseSpot: SIMD2<Float>?
    var chaseUntil: Float = 0
    /// Counters (tests / the report).
    var noticed = 0, queued = 0, tookTurn = 0, gaveUp = 0, chased = 0
}

extension BlobBrain {
    private var toyPeers: [BlobBrain] { socialOthers().filter { $0 !== self } }

    /// Nothing owns him: a toy may take him now.
    private var toyFree: Bool {
        anticsEnabled && !sleepLocked && reactFree && scriptIsNone && idleState.kind == nil && !race.active && idleMood != .grumpy && idleNight < 0.6
    }

    /// Does the toy take several players at once (so everyone present joins at once)?
    static func toyTakesMany(_ k: DecorKind) -> Bool { k.sitPoints.count > 1 || k.isBallLike || k == .bubblemachine }

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
        return Int((2 * best).rounded())
    }

    // MARK: the tick (idleGate, no behaviour running)

    func toyTick(_ sim: SoftBody) {
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
        // 3. waiting for a turn
        if toy.waitUID >= 0 { toyWaitTick(sim, f, clock) }
    }

    private func toyClear() { toy.noticeUID = -1; toy.waitUID = -1; toy.chaseSpot = nil }

    private func toyShouldNotice(_ n: ToyNews) -> Bool {
        let f = DecorField.shared
        guard let foot = f.foot(n.uid) else { return false }
        // the goal stands for its ball
        var uid = n.uid, kind = foot.kind
        if kind == .minigoal, let ball = f.feet.first(where: { $0.kind == .soccerball }) { uid = ball.uid; kind = .soccerball }
        guard kind.activeInteraction != nil else { return false }
        if let until = toy.bored[uid], until > f.toys.clock { return false }
        let p = f.foot(uid).map { f.position($0) } ?? n.pos
        var ranked = toyPeers.filter { $0.toyFree }
        ranked.append(self)
        ranked.sort { simd_distance($0.position, p) < simd_distance($1.position, p) }
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
            if decorStart(mv, sim, only: nil, uid: id) { idleState.cooldown = max(idleState.cooldown, 3); return }
            toy.bored[id] = f.toys.clock + 45          // (no stand / no way there)
            return
        }
        toyQueue(foot, sim)
    }

    /// A free ball and a free friend: the pass social (they kick it to each other); true = started.
    private func toyTryPass(_ sim: SoftBody) -> Bool {
        guard socialBook.enabled, rand() < 0.75 else { return false }
        let friends = toyPeers.filter { $0.socialFree && $0.reactFree && $0.react.pending == nil }.sorted { simd_distance($0.position, position) < simd_distance($1.position, position) }
        for o in friends where socialStart(.pass, with: o, sim) { return true }
        return false
    }

    private func toyQueue(_ foot: DecorFoot, _ sim: SoftBody) {
        let f = DecorField.shared
        let uid = foot.uid
        let waiting = toyPeers.filter { $0.toy.waitUID == uid }.count
        guard waiting < ToyTuning.queueMax, let spot = toyWatchSpot(foot) else { toy.bored[uid] = f.toys.clock + 25; return }
        toy.waitUID = uid; toy.waitSince = f.toys.clock; toy.waitDeadline = f.toys.clock + ToyTuning.queueTimeout
        toy.checkAt = f.toys.clock + 0.6; toy.lookAt = f.toys.clock + rand(1.0, 2.0)
        toy.queued += 1
        if simd_distance(position, spot) > 0.5 { requestNow(.goTo(spot)) }
    }

    private func toyWaitTick(_ sim: SoftBody, _ f: DecorField, _ clock: Float) {
        guard let foot = f.foot(toy.waitUID), clock < toy.waitDeadline, toyFreeForQueue else {
            if toy.waitUID >= 0, clock >= toy.waitDeadline { toy.bored[toy.waitUID] = clock + ToyTuning.boredFor; toy.gaveUp += 1; idleState.cooldown = max(idleState.cooldown, rand(2, 4)) }
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
                else { toy.bored[uid] = clock + 30 }
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
    private var toyFreeForQueue: Bool { attached && !held && !commanded && social == nil && job == nil && !sleepLocked && !race.active && commandedIdle == nil }

    /// The oldest waiter at this piece goes first (ties by id).
    private func toyFirstInQueue(_ uid: Int) -> Bool {
        for o in toyPeers where o.toy.waitUID == uid {
            if o.toy.waitSince < toy.waitSince - 1e-4 || (abs(o.toy.waitSince - toy.waitSince) <= 1e-4 && o.steerID < steerID) { return false }
        }
        return true
    }

    /// A spot outside the piece to watch from: on the side he comes from, 1.1+ from its edge, clear of the user's spot and of the other waiter.
    func toyWatchSpot(_ foot: DecorFoot) -> SIMD2<Float>? {
        let f = DecorField.shared
        let c = f.position(foot)
        var keepOut: [SIMD2<Float>] = []
        for o in toyPeers {
            if o.idleState.decorUID == foot.uid { keepOut.append(o.position); keepOut.append(o.idleState.target) }
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
            while t < 5, g.distance(c + u * t) < 1.15 { t += 0.05 }
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
