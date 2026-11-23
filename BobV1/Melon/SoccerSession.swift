//
//  SoccerSession.swift
//  soccer-room-r1: SOCCER SESSIONS. The owner (2026-11-22): "when I just put the soccer ball out they really start playing mini games and passing to each other and shooting".
//  One small director per room, INERT when no soccer ball is placed (nothing here runs, draws a random number or changes a field before the ball check).
//    kick-off   a ball put out (or already out when the room opens: 20...40 s in) starts a session at once; every awake, free Jelmiko plays.
//    recurring  35...60 s after a session ended the next one starts (while the ball stays out).
//    a session  a playlist of games (kick-off 40...75 s, recurring 20...40 s). Built only from the existing moves: the walk, the turn steps, the stomp kick (`.soccerKick`), the bounce.
//    pass       two: back and forth; three: a ring A -> B -> C -> A. Each turn is a DIRECTED stomp kick: the friend walks out to a spot 2...3.4 u from the ball along a clear line
//               (`mixPassPlan`), the kicker walks behind the ball, the ball rolls the whole way and stops a body-length short of the friend, who takes the next turn.
//    alone      one Jelmiko at home: kicks of his own (dribbles / shots when a goal is placed).
//  The director never touches a body: it gives a member an ORDER (`SessOrder`: stand at a spot / kick) that the member carries out in his own tick (`mixSessionTick`), where he has his own sim.
//  Members stand where they are put, facing the ball (`socialFree` is false for them: no emote, hug or pair roll picks them), and leave cleanly when they become busy.
//

import Foundation
import simd
import UIKit

/// A directed kick: the line (unit) and how far the ball should roll.
struct SessKick { var dir: SIMD2<Float>; var roll: Float }

/// A director's order to one member.
struct SessOrder {
    enum Kind { case none, station, kick, cheer }
    var kind: Kind = .none
    var spot = SIMD2<Float>.zero
    var kick: SessKick?
    var force: Int?
    var shoot = false
    var fetch = false
    var dribbleTo: SIMD2<Float>?
    /// 0 waiting to start, 1 walking, 2 done (arrived / the kick began), -1 failed.
    var state = 0
    var walks = 0
    var beckoned = false
    var waited: Float = 0
    var cheered = false
    var turned = false
    var turnT: Float = 0
    var logged = false
    /// A station is reached within this of the spot (a receiver or a spectator already near it does not walk).
    var tolerance: Float = 0.45
}

nonisolated enum SoccerSessionTuning {
    nonisolated(unsafe) static var on: Bool = {
        guard DevArgs.enabled, let v = UserDefaults.standard.string(forKey: "SoccerSessions") else { return true }
        return !["0", "no", "false", "old", "off"].contains(v.lowercased())
    }()
    static let kickoffLen: ClosedRange<Float> = 55...80
    static let recurLen: ClosedRange<Float> = 32...50
    static let gap: ClosedRange<Float> = 65...95          // (round 3: the ball is about a third of their time, not almost half)
    static let openingWait: ClosedRange<Float> = 20...40
    static let kickoffWait: ClosedRange<Float> = 0.3...0.8
    static let passKicks: ClosedRange<Float> = 5...8
    nonisolated(unsafe) static var roomShots = false          // (tests turn it on)
}

@MainActor
final class SoccerSession {
    static let shared = SoccerSession()
    nonisolated deinit {}

    enum Game { case pass, dribblePass, shots, solo }
    enum Phase { case plan, walking, kicking, rolling, fetch }

    private var stamp: [Int: Float] = [:]
    private var clock: Float = 0
    private var lastNow: Float = -1
    private var firstTick = true
    private var ballAtFirstTick = false
    private var seenUID: Int?
    private var nextStart: Float = .infinity
    private var active = false
    private var kickoffSession = false
    private var endsAt: Float = 0
    private var members: [Int] = []
    private var game: Game = .pass
    private var lastGame: Game?
    private var gameEnds: Float = 0
    // pass state
    private var phase: Phase = .plan
    private var kIdx = 0, rIdx = 1
    private var kicks = 0, kickTarget = 6
    private var failures = 0
    private var planAt: Float = -9
    private var phaseAt: Float = 0
    private var ballAtPlan = SIMD2<Float>.zero
    private var restSince: Float = -1
    private var soloNextAt: Float = 0
    private var soloWaiting = false
    private var blockedSince: [Int: Float] = [:]
    private var firstOfSession = false
    private var fetchFails = 0
    private var startWaitSince: Float = -1
    private(set) var kickoffDirects = 0
    private var kickoffDirectTried = false
    private var pendingOrder: (who: Int, after: Int, order: SessOrder)?          // (two walks that would cross go one after the other: the second waits where he is)
    private var kickoffTurn = false          // (the first turn of a kick-off: the two nearest the ball, a short pass)
    private(set) var gamesEndedNotAll = 0
    private var gameKick: [Int: Int] = [:], prevK = -1
    private var failStreak = 0, awaitRest = false, awaitedRoll = false
    /// Tests: play this game first.
    var forceGame: Game?
    private var restAt: Float = 0
    private var dribbled = false, turnWasDribble = false, replans = 0
    private var eventSerial = 0, lastGoals = 0
    private var goalAt: Float = -99, goalCheerers: [Int] = [], goalReported = true
    private(set) var shots = 0, goals = 0, nearMisses = 0, cheersDone = 0, goalsFullyCheered = 0
    private var lastWhy: Float = -9
    // stats (logged)
    private(set) var sessions = 0, passKicks = 0, fetches = 0, selfRolls = 0
    private func b0(_ k: BlobBrain) -> Float { k.variety.now }

    /// Dev / tests: forget everything.
    func reset() { stamp = [:]; clock = 0; lastNow = -1; firstTick = true; ballAtFirstTick = false; seenUID = nil; nextStart = .infinity; active = false; members = []; phase = .plan; kicks = 0; failures = 0; sessions = 0; passKicks = 0 }
    var isActive: Bool { active }
    var gameName: String { active ? "\(game)" : "" }
    var memberIDs: [Int] { members }

    private func log(_ s: @autoclosure () -> String) { if EmoteSpot.logOn { NSLog("[session] t=%.1f %@", clock, s()) } }

    // MARK: the tick (called from every brain's socialTick; one of them, the lowest awake id, drives)

    func tick(by b: BlobBrain, _ dt: Float) {
        guard SoccerSessionTuning.on, MoveMix.on, !b.outingPlay else { return }
        let field = DecorField.shared
        let ball = field.feet.first { $0.kind == .soccerball }
        let now = b.variety.now
        if now < 0.5, clock > 3 { return }          // (a second, hidden brain with no clock of its own also ticks the social layer: it never drives a room)
        stamp[b.steerID] = now
        if ball == nil, !active, seenUID == nil, !firstTick { return }          // (nothing to do and nothing to undo: the cheap exit)
        let lead = stamp.filter { $0.value >= now - 0.5 }.keys.min() ?? b.steerID
        guard b.steerID == lead else { return }
        clock += dt
        let all = [b] + b.socialOthers()
        roster = all
        if firstTick { firstTick = false; ballAtFirstTick = ball != nil }
        guard let ball else {
            if active || seenUID != nil { endSession(all, why: "ball gone"); seenUID = nil; nextStart = .infinity }
            return
        }
        if seenUID != ball.uid {          // a ball has come out
            seenUID = ball.uid
            let opening = ballAtFirstTick && sessions == 0 && !active
            nextStart = clock + (opening ? b.rand(SoccerSessionTuning.openingWait.lowerBound, SoccerSessionTuning.openingWait.upperBound) : b.rand(SoccerSessionTuning.kickoffWait.lowerBound, SoccerSessionTuning.kickoffWait.upperBound))
            kickoffSession = true
            ballAtFirstTick = false
            let serial = field.toys.news.last?.serial ?? 0
            MoveMix.soccerNextAt = max(MoveMix.soccerNextAt, now + 40)          // (the old once-a-minute soccer moment keeps out of the kick-off)
            for m in all { m.toy.handled = max(m.toy.handled, serial); m.toy.noticeUID = -1; m.toy.waitUID = -1; m.toy.chaseSpot = nil }          // (the toy news "a new ball" would send the nearest ones to it by themselves: the session is the kick-off)
            log("ball out uid=\(ball.uid) opening=\(opening) first session at +\(String(format: "%.1f", nextStart - clock))")
        }
        for m in all where m.mix.sess && !members.contains(m.steerID) { m.sessRelease(); log("stale member \(m.steerID) released") }          // (nobody may be left holding an order for a session that is not running)
        if field.held == ball.uid { return }          // (picked up in arrange mode: wait until it is put down)
        if !active {
            guard clock >= nextStart else { return }
            startSession(b, all, ball)
            return
        }
        // keep the members that are still free to play
        var gone = false
        for id in members {
            guard let m = all.first(where: { $0.steerID == id }) else { gone = true; continue }
            if let why = m.sessBlock(inSession: true) {
                let since = blockedSince[id] ?? clock; blockedSince[id] = since
                if clock - since < 2.0, ["antics", "autonomy", "attached"].contains(why) { continue }          // (a blink of a flag is not a reason to leave)
                m.sessRelease(); log("member \(id) leaves (\(why))"); members.removeAll { $0 == id }; gone = true; blockedSince[id] = nil
            } else { blockedSince[id] = nil }
        }
        _ = gone
        for m in all where !m.mix.sess && clock < endsAt - 3 && m.sessEligible(inSession: false) {          // (everyone awake and free joins, whenever they become so)
            m.mix.sess = true; m.mix.order = SessOrder(); members.append(m.steerID)
            m.sessSpectate(ball: field.position(ball), avoid: [])
            log("member \(m.steerID) joins")
        }
        let ms = members.compactMap { id in all.first { $0.steerID == id } }
        if ms.isEmpty { endSession(all, why: "nobody left"); return }
        watchGoals(ms, field)
        let ringOpen = (game == .pass || game == .dribblePass) && ms.count >= 2 && !ms.allSatisfy { (gameKick[$0.steerID] ?? 0) >= 1 } && clock < endsAt + 25
        if clock >= endsAt, !ringOpen, goalReported, phase == .plan || game == .solo { endSession(all, why: "time"); return }
        let wanted = gamesFor(ms.count, !field.goals.isEmpty)
        if !wanted.contains(game) { chooseGame(ms); return }
        switch game {
        case .pass, .dribblePass: stepPass(ms, ball)
        case .shots: stepShots(ms, ball)
        case .solo: stepSolo(ms[0], ball)
        }
    }

    // MARK: sessions

    private func startSession(_ b: BlobBrain, _ all: [BlobBrain], _ ball: DecorFoot) {
        let ready = all.filter { $0.sessEligible(inSession: false) }
        guard !ready.isEmpty, b.freeBall() != nil else {
            if clock - lastWhy > 3 { lastWhy = clock; log("waiting: ready=\(ready.count) why=\(all.map { "\($0.steerID):\($0.sessBlock(inSession: false) ?? "ok")" }) ballFree=\(b.freeBall() != nil)") }
            nextStart = clock + 0.5; return
        }
        // a session with company: when others are only a moment from free (a launch job, an emote running out) wait a few seconds rather than open with a solo game
        if ready.count < all.filter({ $0.enabled }).count {
            if startWaitSince < 0 { startWaitSince = clock }
            if clock - startWaitSince < 5, ready.count < 2 { nextStart = clock + 0.5; return }
        }
        startWaitSince = -1
        active = true; sessions += 1
        let len = kickoffSession ? SoccerSessionTuning.kickoffLen : SoccerSessionTuning.recurLen
        endsAt = clock + b.rand(len.lowerBound, len.upperBound)
        members = ready.map { $0.steerID }.sorted()
        let serial = DecorField.shared.toys.news.last?.serial ?? 0
        for m in ready { m.mix.sess = true; m.mix.order = SessOrder(); m.toy.handled = max(m.toy.handled, serial); m.toy.noticeUID = -1; m.toy.chaseSpot = nil }
        if !kickoffSession { for m in ready { m.sessSpectate(ball: DecorField.shared.position(ball), avoid: []) } }          // (everybody comes over and spreads out, 2.2 or more apart, before the first turn is planned; at a kick-off the turn is planned at once: the two nearest walk straight to their places)
        log("start #\(sessions) kickoff=\(kickoffSession) members=\(members) len=\(String(format: "%.0f", endsAt - clock)) floorZ=\(String(format: "%.1f", b.roamProvider?()?.minZ ?? 0))...\(String(format: "%.1f", b.roamProvider?()?.maxZ ?? 0))")
        if kickoffSession, ready.count >= 2, forceGame == nil { forceGame = .pass }          // (the kick-off is a pass: the simplest game first)
        let kickoffSessionWas = kickoffSession
        kickoffSession = false
        firstOfSession = true
        kickoffTurn = kickoffSessionWas; kickoffDirectTried = false; pendingOrder = nil
        lastGame = nil
        chooseGame(ready)
    }

    private func endSession(_ all: [BlobBrain], why: String) {
        for m in all where m.mix.sess { m.sessRelease() }
        if active { log("end why=\(why) kicks=\(passKicks)") }
        active = false; members = []
        nextStart = clock + (all.first?.rand(SoccerSessionTuning.gap.lowerBound, SoccerSessionTuning.gap.upperBound) ?? 45)
        if why == "nobody left" { nextStart = clock + 6 }
    }

    private func gamesFor(_ n: Int, _ goal: Bool) -> [Game] {
        var g: [Game] = []
        if n >= 2 { g += [.pass, .dribblePass] }
        if goal, SoccerSessionTuning.roomShots, goalPlayable() { g.append(.shots) }          // (owner 11-23: no goal in the room; the shots game waits for the Play view's bought net)
        if n == 1 && (!goal || !SoccerSessionTuning.roomShots) { g.append(.solo) }
        return g
    }

    /// A goal with at least one kick spot the Jelmiko can use (a goal pushed into a corner has none).
    private func goalPlayable() -> Bool {
        guard let b = roster.first(where: { $0.roamProvider != nil }) else { return true }
        let f = DecorField.shared
        return f.goals.contains { g in f.kickSpots(g).contains { b.sessKickSpotUsable($0) } }
    }

    private func chooseGame(_ ms: [BlobBrain]) {
        let all = gamesFor(ms.count, !DecorField.shared.goals.isEmpty)
        let pool = all.filter { $0 != lastGame }
        game = (pool.isEmpty ? all : pool)[Int(ms[0].rand() * Float(pool.isEmpty ? all.count : pool.count)) % (pool.isEmpty ? all.count : pool.count)]
        if forceGame == nil, firstOfSession, ms.count >= 3, all.contains(.pass) { forceGame = .pass }          // (with three the session opens with the ring: everybody kicks)
        firstOfSession = false
        if let fg = forceGame, all.contains(fg) { game = fg; forceGame = nil }
        lastGame = game
        dribbled = false; turnWasDribble = false; gameKick = [:]; prevK = -1; fetchFails = 0
        for m in ms { m.mix.sessFace = nil }
        phase = .plan; kIdx = 0; rIdx = 1 % max(ms.count, 1); kicks = 0; failures = 0; planAt = -9; restSince = -1
        kickTarget = Int(ms[0].rand(SoccerSessionTuning.passKicks.lowerBound, SoccerSessionTuning.passKicks.upperBound))          // (shots: 3...6 of them)
        if game == .pass || game == .dribblePass { kickTarget = ms.count + Int(ms[0].rand(0, 2)) }          // (a ring: one kick each and up to two more; the next game follows sooner)
        soloNextAt = clock + 0.8; soloWaiting = false
        gameEnds = clock + max(Float(max(ms.count, 2)) * 9, (endsAt - clock) * 0.6)          // (long enough for a whole ring: each kick takes about 8 s)          // (each game of the playlist gets its share of the session)
        for m in ms { m.mix.order = SessOrder() }
        log("game \(game) members=\(ms.map { $0.steerID })")
    }

    // MARK: pass around

    private func stepPass(_ ms: [BlobBrain], _ ballFoot: DecorFoot) {
        let field = DecorField.shared
        let n = ms.count
        kIdx %= n
        if phase == .plan {
            if kickoffTurn, n >= 2 {          // (kick-off: the one nearest the ball kicks it to the next nearest)
                let cc = field.position(ballFoot)
                let order = (0..<n).sorted { simd_distance(ms[$0].position, cc) < simd_distance(ms[$1].position, cc) }
                kIdx = order[0]; rIdx = order[1]
            } else { rIdx = pickReceiver(ms) }
        }
        rIdx %= n
        let K = ms[kIdx], R = ms[rIdx]
        let c = field.position(ballFoot)
        let moving = field.anim[ballFoot.uid]?.moving == true
        switch phase {
        case .plan:
            guard !moving, field.occupant[ballFoot.uid] == nil, clock - planAt >= 0.5 else { return }
            planAt = clock
            if kickoffTurn, !kickoffDirectTried, n >= 2 {          // round 3: the first kick of a kick-off: the nearest member goes straight to the ball and kicks it to the nearest other where he stands; nobody walks to a station first
                kickoffDirectTried = true
                if let (ki, ri) = kickoffPair(ms, c) {
                    let Kk = ms[ki], Rr = ms[ri]
                    let v = Rr.position - c, L = simd_length(v)
                    kIdx = ki; rIdx = ri
                    Kk.mix.order = SessOrder(kind: .kick); Kk.mix.order.kick = SessKick(dir: v / L, roll: max(L - 1.0, 0.45))
                    Rr.mix.order = SessOrder(kind: .station, spot: Rr.position); Rr.mix.order.tolerance = 1.0
                    for m in ms where m !== Kk && m !== Rr { m.mix.order = SessOrder() }
                    ballAtPlan = c; turnWasDribble = false; kickoffTurn = false; kickoffDirects += 1
                    phase = .kicking; phaseAt = clock
                    log("kick-off: K=\(Kk.steerID) straight to the ball, R=\(Rr.steerID) only turns to it line=\(String(format: "%.2f", L))")
                    return
                }
            }
            // both must be standing free (a walking one is asked to stop once); an emote in progress runs out
            var ready = true
            for m in [K, R] where !m.socialFreeBase {
                if kickoffTurn, m.scriptIsWalking || m.socialWandering { continue }          // (a kick-off: a walker is simply given his place; the order stops him first)
                ready = false
                if !m.mix.order.beckoned, m.socialWandering || m.scriptIsWalking { m.mix.order.beckoned = true; _ = m.socialBeckonStop() }
            }
            if !ready { failures += 1; if failures > 40 { gameDone("not ready") }; return }
            if game == .dribblePass, !dribbled, let to = dribbleSpot(K, ball: c, ms: ms) {
                K.mix.order = SessOrder(kind: .kick); K.mix.order.dribbleTo = to
                for m in ms where m !== K { m.sessSpectate(ball: c, avoid: [to]) }
                ballAtPlan = c; turnWasDribble = true; phase = .kicking; phaseAt = clock
                log("dribble K=\(K.steerID) to=(\(String(format: "%.2f,%.2f", to.x, to.y)))")
                return
            }
            turnWasDribble = false
            let rf0 = K.roamProvider?()
            let restOK: (SIMD2<Float>) -> Bool = { p in          // (where the ball will stop must be open floor: 0.9 from the walls, clear of furniture and the goal)
                guard let rf = rf0 else { return true }
                return K.sessRestFloor(rf, p) && field.openFloor(p, margin: 0.6) && field.goals.allSatisfy { simd_distance($0.centre, p) > 1.3 }
            }
            let kd: [Float]? = kickoffTurn ? [2.0, 2.2, 2.4, 2.6, 3.0] : nil
            guard let plan = K.mixPassPlan(ball: c, with: R, restOK: restOK, bodyGap: 1.6, dists: kd, strict: true) ?? K.mixPassPlan(ball: c, with: R, restOK: restOK, dists: kd, strict: true) ?? K.mixPassPlan(ball: c, with: R, restOK: restOK, bodyGap: 1.6, dists: kd) ?? K.mixPassPlan(ball: c, with: R, restOK: restOK, dists: kd) else {
                failures += 1
                log("no line K=\(K.steerID) R=\(R.steerID) why=\(K.mix.passWhy)")
                if failures == 1 || failures == 4 {          // (the ball lies where no line fits: one of them dribbles it out toward the middle, then the turn is planned again)
                    startFetch(ms, ball: c)
                } else if failures >= 8 { gameDone("no line") }
                return
            }
            let v = plan.pr - c; let L = simd_length(v)
            guard L > 0.5 else { failures += 1; return }
            let dir = v / L
            var kOrder = SessOrder(kind: .station, spot: plan.pk)
            var rOrder = SessOrder(kind: .station, spot: plan.pr); rOrder.tolerance = 0.8
            kOrder.kick = SessKick(dir: dir, roll: max(L - 1.0, 0.45))
            K.mix.order = kOrder; R.mix.order = rOrder
            pendingOrder = nil
            // round 3: walks that would cross go one after the other (the one whose way is blocked waits where he is until the other has arrived)
            if K.sessPathNear(K.position, plan.pk, [R.position]), simd_distance(R.position, plan.pr) > 0.8 {
                pendingOrder = (K.steerID, R.steerID, kOrder); K.mix.order = SessOrder()
            } else if R.sessPathNear(R.position, plan.pr, [K.position]), simd_distance(K.position, plan.pk) > 0.8 {
                pendingOrder = (R.steerID, K.steerID, rOrder); R.mix.order = SessOrder()
            }
            for m in ms where m !== K && m !== R { m.sessSpectate(ball: c, avoid: [plan.pk, plan.pr, K.position, R.position]) }
            kickoffTurn = false
            ballAtPlan = c; phase = .walking; phaseAt = clock; awaitRest = false; awaitedRoll = false; restAt = clock
            log("turn K=\(K.steerID) R=\(R.steerID) ball=(\(String(format: "%.2f,%.2f", c.x, c.y))) line=\(String(format: "%.2f", L))")
        case .walking:
            if let p = pendingOrder, let who = ms.first(where: { $0.steerID == p.who }), let after = ms.first(where: { $0.steerID == p.after }), after.mix.order.state == 2 || clock - phaseAt > 6 { who.mix.order = p.order; pendingOrder = nil }
            let kOK = K.mix.order.state == 2, rOK = R.mix.order.state == 2
            if moving { if awaitRest || clock - restAt < 8 { return } } else { restAt = clock; if awaitRest { awaitRest = false; awaitedRoll = true; phaseAt = clock } }
            if simd_distance(c, ballAtPlan) > (awaitedRoll ? 1.6 : 1.0) {          // (somebody brushed the ball on the way: the line is planned again from where it lies, not a failure)
                replans += 1; awaitRest = false
                for m in ms { m.mix.order = SessOrder() }
                phase = .plan; planAt = clock; log("ball moved: replan (\(replans))")
                if replans > 8 { replans = 0; gameDone("ball keeps moving") }
                return
            }
            if K.mix.order.state == -1 || R.mix.order.state == -1 || clock - phaseAt > 9 { failTurn(ms, "walk K\(K.mix.order.state) R\(R.mix.order.state) dK=\(String(format: "%.1f", simd_distance(K.position, K.mix.order.spot))) dR=\(String(format: "%.1f", simd_distance(R.position, R.mix.order.spot))) t=\(String(format: "%.1f", clock - phaseAt))"); return }
            if kOK, rOK {
                let v = R.mix.order.spot - c; let L = simd_length(v)          // (from where the ball lies now: it may have been brushed on the way)
                guard L > 1.4 else { for m in ms { m.mix.order = SessOrder() }; phase = .plan; planAt = clock; return }
                K.mix.order = SessOrder(kind: .kick); K.mix.order.kick = SessKick(dir: v / L, roll: max(L - 1.0, 0.45))
                ballAtPlan = c
                phase = .kicking; phaseAt = clock
            }
        case .fetch:
            stepFetch(ms, c: c, moving: moving) { rest in          // (the last resort: they walk to their places while the ball rolls, the first kick is not held up by the walk)
                if let plan = K.mixPassPlan(ball: rest, with: R) {
                    K.mix.order = SessOrder(kind: .station, spot: plan.pk); R.mix.order = SessOrder(kind: .station, spot: plan.pr)
                    for m in ms where m !== K && m !== R { m.sessSpectate(ball: rest, avoid: [plan.pk, plan.pr]) }
                    self.ballAtPlan = rest; self.phase = .walking; self.phaseAt = self.clock; self.awaitRest = true; self.awaitedRoll = false; self.restAt = self.clock
                    self.log("places taken while the ball rolls to (\(String(format: "%.2f,%.2f", rest.x, rest.y)))")
                }
            }
        case .kicking:
            if K.mix.order.state == 2 { phase = .rolling; phaseAt = clock; restSince = -1 }
            else if K.mix.order.state == -1 || clock - phaseAt > 8 {
                if turnWasDribble { turnWasDribble = false; dribbled = true; K.mix.order = SessOrder(); phase = .plan; planAt = clock; log("dribble not possible here: straight to the pass"); return }          // (no room to stand behind the ball for a dribble: the pass is the turn)
                failTurn(ms, "kick")
            }
        case .rolling:
            let kDone = K.idleState.kind != .soccerKick
            if moving || !kDone { restSince = -1; if clock - phaseAt > 14 { failTurn(ms, "roll") }; return }
            if restSince < 0 { restSince = clock; return }
            guard clock - restSince > 0.4 else { return }
            let travelled = simd_distance(c, ballAtPlan)
            if turnWasDribble {
                turnWasDribble = false
                if travelled > 0.8 { dribbled = true; log("dribbled K=\(K.steerID) travelled=\(String(format: "%.2f", travelled))") } else { dribbled = true; failures += 1 }
                K.mix.order = SessOrder(); phase = .plan; planAt = clock - 0.3
                return
            }
            if travelled > 1.0 { dribbled = false; gameKick[K.steerID, default: 0] += 1; prevK = kIdx; kicks += 1; passKicks += 1; failures = 0; replans = 0; log("kick \(kicks) K=\(K.steerID) -> R=\(R.steerID) travelled=\(String(format: "%.2f", travelled))") ; kIdx = rIdx }
            else { failures += 1; log("kick missed K=\(K.steerID) travelled=\(String(format: "%.2f", travelled))") }
            K.mix.order = SessOrder()
            phase = .plan; planAt = clock - 0.3
            let allKicked = ms.allSatisfy { (gameKick[$0.steerID] ?? 0) >= 1 }
            if ((kicks >= kickTarget || clock > gameEnds) && allKicked) || clock > gameEnds + 25 || failures >= 3 { gameDone(kicks >= kickTarget ? "done" : "enough") }          // (a ring does not end until each of them has kicked)
        }
    }

    // MARK: fetch (round 2: a ball that lies where nobody can stand behind it)

    private var fetcherID = -1
    /// The member nearest the ball (the next nearest on the second try) walks to it from the open side and nudges it out; only after two failed fetches may the ball roll itself.
    private func startFetch(_ ms: [BlobBrain], ball c: SIMD2<Float>) {
        let byDist = ms.sorted { simd_distance($0.position, c) < simd_distance($1.position, c) }
        let F = byDist[min(fetchFails, byDist.count - 1)]
        fetcherID = F.steerID
        for m in ms { m.mix.order = SessOrder() }
        F.mix.order = SessOrder(kind: .kick); F.mix.order.fetch = true
        phase = .fetch; phaseAt = clock; fetches += 1; ballAtPlan = c
        log("fetch by \(F.steerID)")
    }

    private func stepFetch(_ ms: [BlobBrain], c: SIMD2<Float>, moving: Bool, afterRoll: (SIMD2<Float>) -> Void) {
        guard let F = ms.first(where: { $0.steerID == fetcherID }) else { phase = .plan; planAt = clock; return }
        let fetchedOK = F.mix.order.state == 2 && F.idleState.kind != .soccerKick && !moving
        if fetchedOK, simd_distance(c, ballAtPlan) > 0.5 { F.mix.order = SessOrder(); phase = .plan; planAt = clock; fetchFails = 0; log("fetched"); return }
        guard F.mix.order.state == -1 || clock - phaseAt > 20 || fetchedOK else { return }
        F.mix.order = SessOrder(); phase = .plan; planAt = clock + 0.5
        fetchFails += 1
        if fetchFails < 2 { failures = 0; planAt = clock + 1.5; log("fetch did not work, once more (the next nearest)"); return }
        fetchFails = 0
        if let rest = F.sessRollOut() {
            selfRolls += 1; planAt = clock + 3; log("fetch failed twice: the ball rolls itself out")
            afterRoll(rest)
        }
    }

    /// Round 3: the kick-off pair: the member nearest the ball (the kicker) and the nearest other one 1.6...3.9 from it with nobody on the line and open floor where the ball will stop (a standing one first).
    private func kickoffPair(_ ms: [BlobBrain], _ c: SIMD2<Float>) -> (Int, Int)? {
        let field = DecorField.shared
        let order = (0..<ms.count).sorted { simd_distance(ms[$0].position, c) < simd_distance(ms[$1].position, c) }
        guard let ki = order.first, let rf = ms[ki].roamProvider?() else { return nil }
        let K = ms[ki]
        var good: [Int] = []
        for ri in order.dropFirst() {
            let R = ms[ri]
            let v = R.position - c, L = simd_length(v)
            guard L >= 1.6, L <= 3.9 else { continue }
            let dir = v / L
            let rest = c + dir * max(L - 1.0, 0.45)
            guard rf.contains(rest), rf.stopOK(rest), field.openFloor(rest, margin: 0.4) else { continue }
            var clear = true
            var d: Float = 0.4
            while d < L - 0.3 { let p = c + dir * d; if !field.openFloor(p) || ms.contains(where: { $0 !== K && $0 !== R && simd_distance($0.position, p) < 0.9 }) { clear = false; break }; d += 0.4 }
            if clear { good.append(ri) }
        }
        guard let ri = good.first(where: { !ms[$0].scriptIsWalking }) ?? good.first else { return nil }
        return (ki, ri)
    }

    /// The one who gets the ball next: the one with the fewest kicks in this game (the one who has just kicked last of all).
    private func pickReceiver(_ ms: [BlobBrain]) -> Int {
        let n = ms.count
        let cands = (0..<n).filter { $0 != kIdx }.sorted { a, b in
            let ca = gameKick[ms[a].steerID] ?? 0, cb = gameKick[ms[b].steerID] ?? 0
            if ca != cb { return ca < cb }
            if (a == prevK) != (b == prevK) { return b == prevK }
            return a < b
        }
        guard !cands.isEmpty else { return 0 }
        return cands[(failures % 2 == 1 && cands.count > 1) ? 1 : 0]
    }

    private func failTurn(_ ms: [BlobBrain], _ why: String) {
        log("turn failed (\(why))")
        for m in ms { m.mix.order = SessOrder() }
        failures += 1
        phase = .plan; planAt = clock
        if failures >= 4 { gameDone("failed") }
    }

    private func gameDone(_ why: String) {
        if (game == .pass || game == .dribblePass), members.count >= 2, why == "done" || why == "enough", !members.allSatisfy({ (gameKick[$0] ?? 0) >= 1 }) { gamesEndedNotAll += 1 }
        log("game over (\(why)) kicks=\(kicks)")
        let bad = why == "failed" || why == "no line" || why == "not ready" || why == "ball keeps moving"
        failStreak = bad ? failStreak + 1 : 0
        phase = .plan; kicks = 0; failures = 0; planAt = clock + (bad ? 2.5 : 0.4)
        if failStreak >= 3 { failStreak = 0; endsAt = clock; log("three games in a row would not start: the session ends") }
        for id in members { if let m = lookup(id) { m.mix.order = SessOrder() } }
        if clock >= endsAt - 3 { endsAt = clock } else { chooseGame(members.compactMap { lookup($0) }) }          // (the next game of the playlist: never the same twice running while there is another)
    }
    private var roster: [BlobBrain] = []
    private func lookup(_ id: Int) -> BlobBrain? { roster.first { $0.steerID == id } }

    // MARK: dribble and pass

    /// Where the ball is dribbled to: 1.7...2.2 u from where it lies, toward the middle of the floor, on open floor clear of bodies.
    private func dribbleSpot(_ K: BlobBrain, ball c: SIMD2<Float>, ms: [BlobBrain]) -> SIMD2<Float>? {
        guard let rf = K.roamProvider?() else { return nil }
        let field = DecorField.shared
        let mid = SIMD2<Float>(0, (rf.minZ + rf.maxZ) / 2)
        let base = mid - c; let L = simd_length(base)
        let u = L > 0.3 ? base / L : SIMD2<Float>(0, 1)
        var best: (SIMD2<Float>, Float)?
        for r in [Float(2.0), 1.7, 2.2] {
            for k in 0..<9 {
                let a = (k % 2 == 0 ? 1 : -1) * Float((k + 1) / 2) * 0.5
                let v = SIMD2(u.x * cosf(a) - u.y * sinf(a), u.x * sinf(a) + u.y * cosf(a))
                let p = c + v * r
                guard K.sessRestFloor(rf, p), field.openFloor(p, margin: 0.6), simd_distance(K.fixed(p), p) < 0.08, !K.mixBallSpotBad(p),
                      !ms.contains(where: { $0 !== K && simd_distance($0.position, p) < 1.4 }) else { continue }
                var clear = true
                var d: Float = 0.4
                while d < r { if !field.openFloor(c + v * d) { clear = false; break }; d += 0.4 }
                guard clear else { continue }
                let sc = -simd_distance(p, mid) - 0.3 * abs(a)
                if best == nil || sc > best!.1 { best = (p, sc) }
            }
            if best != nil { break }
        }
        return best?.0
    }

    // MARK: shots at the goal

    private func stepShots(_ ms: [BlobBrain], _ ballFoot: DecorFoot) {
        let field = DecorField.shared
        let n = ms.count
        kIdx %= n
        let S = ms[kIdx]
        let c = field.position(ballFoot)
        let moving = field.anim[ballFoot.uid]?.moving == true
        guard let goal = S.nearestGoal(to: c) else { return }
        let gc = goal.centre
        switch phase {
        case .plan:
            guard !moving, field.occupant[ballFoot.uid] == nil, clock - planAt >= 0.5, goalReported else { return }
            planAt = clock
            if !S.socialFreeBase {
                if !S.mix.order.beckoned, S.socialWandering || S.scriptIsWalking { S.mix.order.beckoned = true; _ = S.socialBeckonStop() }
                failures += 1; if failures > 40 { gameDone("not ready") }
                return
            }
            for m in ms where m !== S { m.mix.sessFace = gc; m.sessSpectate(ball: c, avoid: [gc], line: (c, gc)) }
            S.mix.sessFace = nil
            S.mix.order = SessOrder(kind: .kick); S.mix.order.shoot = true
            ballAtPlan = c; phase = .kicking; phaseAt = clock
            log("shooter \(S.steerID) ball=(\(String(format: "%.2f,%.2f", c.x, c.y)))")
        case .kicking:
            if S.mix.order.state == 2 { phase = .rolling; phaseAt = clock; restSince = -1 }
            else if S.mix.order.state == -1 || clock - phaseAt > 8 {
                S.mix.order = SessOrder(); failures += 1; phase = .plan; planAt = clock + 1
                if failures == 2 || failures == 5 { startFetch(ms, ball: c) }
                if failures >= 7 { gameDone("failed") }
            }
        case .rolling:
            let kDone = S.idleState.kind != .soccerKick
            let cheering = clock - goalAt < 5.0 && !goalReported
            if moving || !kDone || cheering { restSince = -1; if clock - phaseAt > 18 { S.mix.order = SessOrder(); phase = .plan; planAt = clock; failures += 1 }; return }
            if restSince < 0 { restSince = clock; return }
            guard clock - restSince > 0.5 else { return }
            S.mix.order = SessOrder()
            kicks += 1; failures = 0
            kIdx = (kIdx + 1) % n
            phase = .plan; planAt = clock - 0.3
            if kicks >= kickTarget - 2 || clock > gameEnds { gameDone("done") }
        case .fetch:
            stepFetch(ms, c: c, moving: moving) { _ in }
        default: phase = .plan
        }
    }

    // MARK: goals and near misses (everyone cheers, every time)

    private func watchGoals(_ ms: [BlobBrain], _ field: DecorField) {
        for e in SoccerEvents.since(eventSerial) {
            switch e {
            case .kick(let j, _, let shot): if shot { shots += 1; log("shot by \(j)") }
            case .nearMiss(let j, _):
                nearMisses += 1
                if let w = ms.first(where: { $0.steerID != j }) { w.face(.oh, hold: 1.2) }          // (one watcher: "ooh")
                log("near miss by \(j)")
            default: break
            }
        }
        eventSerial = SoccerEvents.serial
        // a goal checked after the cheers have had their time
        if !goalReported, clock - goalAt > 4.5 {
            goalReported = true
            let done = goalCheerers.filter { id in ms.first { $0.steerID == id }?.mix.order.cheered == true }.count
            cheersDone += done
            if done == goalCheerers.count { goalsFullyCheered += 1 }
            log("goal cheered by \(done) of \(goalCheerers.count)")
            for m in ms where m.mix.order.kind == .cheer { m.mix.order = SessOrder() }
        }
        let g = SoccerState.shared.goals
        if g != lastGoals {
            lastGoals = g
            guard let lg = SoccerState.shared.lastGoal else { return }
            if lg.scorer < 0 { log("a ball rolled in by itself: no cheer"); return }          // (nobody kicked it: nothing to cheer)
            goals += 1; goalAt = clock; goalReported = false
            AudioHub.shared.play(.volleyPoint); AudioHub.shared.play(.cheerSmall, volume: 0.6)          // (the volleyball's point sound + a small cheer: no new audio)
            Haptic.impact(.medium)
            goalCheerers = ms.filter { $0.steerID != lg.scorer }.map { $0.steerID }
            for m in ms where m.steerID != lg.scorer { m.mix.order = SessOrder(kind: .cheer) }
            log("GOAL by \(lg.scorer): cheerers \(goalCheerers)")
        }
    }

    // MARK: alone

    private func stepSolo(_ m: BlobBrain, _ ballFoot: DecorFoot) {
        let field = DecorField.shared
        let moving = field.anim[ballFoot.uid]?.moving == true
        switch m.mix.order.kind {
        case .kick:
            if m.mix.order.state == 2 || m.mix.order.state == -1 { if m.mix.order.state == 2 { passKicks += 1; log("solo kick by \(m.steerID)") }; m.mix.order = SessOrder(); soloNextAt = clock + m.rand(1.0, 2.4) }
        default:
            guard clock >= soloNextAt, !moving, m.socialFreeBase, m.idleState.kind != .soccerKick, field.occupant[ballFoot.uid] == nil else { return }
            m.mix.order = SessOrder(kind: .kick)
            if !field.goals.isEmpty { m.mix.order.force = m.rand() < 0.6 ? 1 : nil }
        }
    }

    func rosterUpdate(_ all: [BlobBrain]) { roster = all }
}

extension BlobBrain {
    /// Last resort after a failed fetch (nobody can stand behind the ball): it gets a roll toward the middle of the floor. Returns where it should come to rest (nil = it did not roll).
    @discardableResult
    func sessRollOut() -> SIMD2<Float>? {
        let f = DecorField.shared
        guard let rf = roamProvider?(), let sb = f.soccerBalls.first, f.occupant[sb.uid] == nil, sb.uid != f.held, f.anim[sb.uid]?.moving != true else { return nil }
        let c = f.position(sb)
        let mid = SIMD2<Float>(0, (rf.minZ + rf.maxZ) / 2 + 0.5)
        var best: (SIMD2<Float>, Float)?
        for r in [Float(2.0), 3.0, 4.0] { for k in 0..<16 { let a = Float(k) * .pi / 8; let p = c + SIMD2(sinf(a), cosf(a)) * r; if rf.contains(p), rf.halfWidth(at: p.y) - abs(p.x) > 1.6, rf.stopOK(p), f.openFloor(p) { let sc = -simd_distance(p, mid); if best == nil || sc > best!.1 { best = (p, sc) } } } }
        let tgt = best?.0 ?? mid
        let d = tgt - c, L = simd_length(d)
        let dir = L > 0.05 ? d / L : SIMD2<Float>(0, -1)
        if EmoteSpot.logOn { NSLog("[ballrescue] t=%.1f ball=(%.2f,%.2f) rolled toward (%.2f,%.2f) (session)", variety.now, c.x, c.y, tgt.x, tgt.y) }
        f.kickBall(sb.uid, direction: dir, speed: min(max(1.15 * L + 0.2, 0.8), 3.2), by: -1)
        return c + dir * (L * 0.7)          // (about where it comes to rest: measured, the ball stops at about 0.7 of the distance asked for)
    }
    var scriptIsWalking: Bool { if case .walk = script { return true }; return false }

    /// May he play now? `inSession`: already one of the players (only a real interruption drops him). Mood does not matter: hungry and thirsty ones play too; only sleep, a bedtime, a meal, a bath, a hand, a command, the close-up keep one out.
    func sessEligible(inSession: Bool) -> Bool { sessBlock(inSession: inSession) == nil }
    func sessBlock(inSession: Bool) -> String? {
        if !anticsEnabled { return "antics" }
        if !(autonomy || idleForced) { return "autonomy" }
        if !attached { return "attached" }
        if held { return "held" }
        if commanded { return "commanded" }
        if pending != nil { return "pending" }
        if job != nil { return "job" }
        if reserved { return "reserved" }
        if bubbleLeash != nil { return "bubble" }
        if commandedIdle != nil || commandedFlip || commandedNameHop || interruptScript { return "command" }
        if sleepLocked { return "sleepLocked" }
        if bedtimeLocked { return "bedtime" }
        if idleDeepNight >= 0.5 { return "night" }
        if idleState.kind == .sleep { return "asleep" }
        if race.active || volley.active { return "race" }
        if onSlideFoot { return "slide" }
        if !socialBook.enabled { return "socialOff" }
        if activity == .touched || activity == .recovering { return "touched" }
        if social != nil { return "social" }
        if !inSession && mix.sess { return "member" }
        return nil
    }

    /// Leaves the session cleanly: nothing of the order is left, he faces the camera again and picks for himself.
    func sessRelease() {
        mix.sess = false; mix.order = SessOrder(); mix.sessKick = nil; mix.sessFace = nil; mix.sessShoot = false; mix.sessDribbleTo = nil; soccerModeForce = nil
        if social == nil, socialBook.hold { socialBook.hold = false; socialBook.faceYaw = nil }
        if scriptIsNone { restTimer = min(restTimer, rand(0.3, 1.2)) }
    }

    /// Round 3: does the straight walk a -> b pass within `gap` of any of `bodies` (the first 0.6 of it is ignored: he walks AWAY from whoever he starts beside)?
    func sessPathNear(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ bodies: [SIMD2<Float>], gap: Float = 1.3) -> Bool {
        let ab = b - a, L = simd_length(ab)
        guard L > 0.6 else { return false }
        var d: Float = 0.6
        while d <= L { let q = a + ab * (d / L); if bodies.contains(where: { simd_distance($0, q) < gap }) { return true }; d += 0.15 }
        return false
    }

    /// A spot for one who waits: 2.6 or more from the two passers' spots, about 3 from the ball, on floor that can be used.
    func sessSpectate(ball c: SIMD2<Float>, avoid: [SIMD2<Float>], line: (SIMD2<Float>, SIMD2<Float>)? = nil) {
        func offLine(_ p: SIMD2<Float>) -> Bool {
            guard let (a, b) = line else { return true }
            let ab = b - a, L2 = max(simd_dot(ab, ab), 1e-4)
            let t = min(max(simd_dot(p - a, ab) / L2, 0), 1)
            return simd_distance(p, a + ab * t) >= 1.4
        }
        let peers = socialOthers().filter { $0 !== self && $0.mix.sess }.map { $0.position }
        func okHere(_ p: SIMD2<Float>) -> Bool { peers.allSatisfy { simd_distance($0, p) >= 2.2 } && avoid.allSatisfy { simd_distance($0, p) >= (line != nil ? 1.8 : 2.6) } && simd_distance(p, c) < 4.2 && simd_distance(p, c) > 1.5 && offLine(p) }
        if okHere(position) { mix.order = SessOrder(); return }
        guard let rf = roamProvider?() else { return }
        let others = socialOthers().filter { $0 !== self }
        var best: (SIMD2<Float>, Float)?
        for r in [Float(3.0), 3.4, 2.6, 3.8] {
            for k in 0..<16 {
                let a = Float(k) * .pi / 8
                let p = c + SIMD2(sinf(a), cosf(a)) * r
                guard rf.contains(p), rf.halfWidth(at: p.y) - abs(p.x) > 0.45, rf.stopOK(p), simd_distance(fixed(p), p) < 0.08, okHere(p), !mixBallSpotBad(p), !sessPathNear(position, p, others.map { $0.position }),
                      !others.contains(where: { simd_distance($0.position, p) < 1.2 }), DecorField.shared.openFloor(p), reachable(position, p) else { continue }
                let sc = -simd_distance(position, p)
                if best == nil || sc > best!.1 { best = (p, sc) }
            }
            if best != nil { break }
        }
        if let b = best { mix.order = SessOrder(kind: .station, spot: b.0) } else { mix.order = SessOrder() }
    }

    /// Every tick of a member (and of anybody still holding an order): carry out what the director asked, or stand facing the ball.
    func mixSessionTick(_ sim: SoftBody) {
        guard social == nil else { return }
        let ballPos = DecorField.shared.soccerBalls.first.map { DecorField.shared.position($0) }
        func faceIt() { if let b = mix.sessFace ?? ballPos { socialBook.hold = true; socialBook.faceYaw = yawTo(b) } }
        var o = mix.order
        defer { mix.order = o }
        if o.kind != .none, o.state == 0 { o.waited += 1.0 / 60; if o.waited > 1.0, !o.logged, EmoteSpot.logOn { o.logged = true; NSLog("[session] id=%d order %@ blocked: scriptNone=%d idle=%@ activity=%@ hurry=%d interrupt=%d", steerID, String(describing: o.kind), scriptIsNone ? 1 : 0, String(describing: idleState.kind), String(describing: activity), hurry ? 1 : 0, interruptScript ? 1 : 0) } }
        switch o.kind {
        case .none:
            if mix.sess, scriptIsNone, idleState.kind == nil { faceIt() }
        case .station:
            guard o.state >= 0, o.state < 2 else { if o.state == 2 { faceIt() }; return }
            if socialFreeBase || (scriptIsNone && idleState.kind == nil) {
                let d = simd_distance(position, o.spot)
                if d < o.tolerance && !feet.active { o.state = 2; faceIt(); return }
                if o.state == 1, o.walks >= 3 { o.state = d < 1.0 ? 2 : -1; return }
                socialBook.hold = false; socialBook.faceYaw = nil
                socialWalk(to: o.spot, sim); o.state = 1; o.walks += 1
            } else if scriptIsWalking, !o.beckoned, o.state == 0 {
                if case .walk(let t, _) = script, simd_distance(t, o.spot) > 0.3 { o.beckoned = true; _ = socialBeckonStop() }
            }
        case .kick:
            guard o.state == 0 else { return }
            guard socialFreeBase else { if scriptIsWalking, !o.beckoned { o.beckoned = true; _ = socialBeckonStop() }; return }
            socialBook.hold = false; socialBook.faceYaw = nil
            mix.sessKick = o.kick; soccerModeForce = o.force; mix.sessShoot = o.shoot; mix.sessDribbleTo = o.dribbleTo; mix.sessFetch = o.fetch
            if o.fetch { MoveMix.ballNeedsRoom = true }
            let ok = decorStart(.soccerKick, sim, only: .soccerball)
            soccerModeForce = nil; mix.sessKick = nil; mix.sessShoot = false; mix.sessDribbleTo = nil; mix.sessFetch = false; MoveMix.ballNeedsRoom = false
            o.state = ok ? 2 : -1
            if !ok, EmoteSpot.logOn, let bf = DecorField.shared.soccerBalls.first {
                let f = DecorField.shared, c = f.position(bf)
                var probe = o.kick.map { sessStandProbe(c - $0.dir * SoccerTuning.standBack) } ?? (o.dribbleTo.map { _ in "dribble" } ?? "free")
                mix.sessKick = o.kick; mix.sessDribbleTo = o.dribbleTo
                let st = decorStand(.soccerKick, bf, from: position); mix.sessKick = nil; mix.sessDribbleTo = nil
                probe += " decorStand=" + (st.map { String(format: "(%.2f,%.2f) reach=%d", $0.x, $0.y, reachable(position, $0) ? 1 : 0) } ?? "nil") + " tumbling=\(f.anim[bf.uid]?.tumbling == true) decorIgnore=\(decorIgnore)"
                NSLog("[session] id=%d kick order failed: avail=%d moving=%d occ=%d dist=%.2f stand[%@] dribbleTo=%d shoot=%d", steerID, f.available(bf) ? 1 : 0, f.anim[bf.uid]?.moving == true ? 1 : 0, f.occupant[bf.uid] ?? -1, simd_distance(position, c), probe, o.dribbleTo == nil ? 0 : 1, o.shoot ? 1 : 0)
            }
        case .cheer:
            guard o.state == 0 else { if o.state == 2 { o.cheered = true }; return }
            if o.waited > 6 { o.state = -1; return }
            guard socialFreeBase else { return }
            if !o.turned {          // (the player is the audience: turn to the camera first, then jump)
                o.turnT += 1.0 / 60
                socialBook.hold = true; socialBook.faceYaw = faceCameraYaw()
                let dy = atan2f(sinf(yaw - faceCameraYaw()), cosf(yaw - faceCameraYaw()))
                if abs(dy) > 0.3, o.turnT < 1.2 { return }
                o.turned = true
            }
            socialBook.hold = false; socialBook.faceYaw = nil
            face(.excited, hold: 1.1); blushBump(hold: 2.4, peak: 0.7)
            let ok = idleStart(.bounce, sim)          // (the happy bounce, off the ground: the same one the scorer does)
            o.state = ok ? 2 : -1; o.cheered = ok
        }
    }
}
