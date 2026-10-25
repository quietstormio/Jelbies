//
//  VolleySim.swift
//  The rules and the ball of Jelly Volleyball as one pure model (no bodies, no screen): a big floaty beach ball (slow gravity, gentle drag), four players
//  (the human, his partner, two visitors), rally scoring to 7, the computer players' decisions, and the three training drills.
//
//  The sim never moves a body. Each step the glue gives it where the bodies ARE (x, lift, the surface points of the soft body) and takes back EVENTS to put on them:
//  jump / spike / dive for a body to perform, `contact` when the ball met a body (the glue dents the soft body there), points and the rest.
//  The ball bounces off the bodies' real soft surfaces; what it does after a hit (where it is sent) is decided here from the kind of hit and the hitter's stats.
//

import Foundation
import simd

nonisolated enum VolleyHit: Equatable, Sendable { case bonk, spike, dig, serve }

nonisolated enum VolleyEvent: Equatable, Sendable {
    case jump(player: Int, dx: Float, apex: Float)
    case spike(player: Int)
    case dive(player: Int, dir: Float)
    case serveToss(player: Int)
    case contact(player: Int, kind: VolleyHit, point: SIMD2<Float>, normal: SIMD2<Float>, speed: Float)
    case bounce(x: Float)
    case net
    case point(team: Int, out: Bool)
    case serveReady(player: Int)
    case cheer(team: Int)
    case matchOver(winner: Int)
    case drillBall(Int)
    case drillHit(Bool)
    case flag(Int)
    case drillOver
}

nonisolated enum VolleyAct: Equatable, Sendable { case stand, jump, spike, dive }

nonisolated struct VolleyPlayer: Sendable {
    var team: Int
    var human: Bool
    var stats: VolleyStats
    /// 0...1 how well the computer plays (a human with assists reads it too).
    var skill: Float
    var x: Float
    /// Height of the body's centre above its resting height (0 on the sand), the crown's height, and the real soft-body surface in the x/y plane.
    var lift: Float = 0
    var top: Float = VolleyTuning.bodyTop
    var samples: [SIMD2<Float>] = []
    var grounded = true
    /// What the body is doing (the sim sets it when it commands a move; the glue says when the body is done).
    var act: VolleyAct = .stand
    var actT: Float = 0
    var wantX: Float
    var cooldown: Float = 0
    var wait: Float = 0
    var hits = 0
    var jumpAt: Float = -1
    var vx: Float = 0
}

nonisolated struct VolleyBall: Sendable {
    var pos = SIMD2<Float>(0, 3)
    var vel = SIMD2<Float>(0, 0)
    var spin: Float = 0
    var z: Float = VolleyTuning.ballZ
}

nonisolated enum VolleyPhase: Equatable, Sendable { case intro, serveWait, rally, pointPause, over }
nonisolated enum VolleyMode: Equatable, Sendable { case match(VolleyTier), drill(VolleyDrillKind) }

nonisolated struct VolleyRng: Sendable {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Float {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return Float(s >> 40) / Float(1 << 24)
    }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
}

nonisolated struct VolleySim: Sendable {
    typealias T = VolleyTuning
    let mode: VolleyMode
    private(set) var players: [VolleyPlayer] = []
    private(set) var ball = VolleyBall()
    private(set) var phase: VolleyPhase = .intro
    private(set) var score = [0, 0]
    private(set) var server = 0                 // team serving
    private(set) var serverIndex = 0            // the player who serves
    private(set) var lastHit = -1               // player index
    private(set) var touches = [0, 0]
    private(set) var clock: Float = 0
    private(set) var phaseT: Float = 0
    private(set) var winner: Int?
    private(set) var events: [VolleyEvent] = []
    var rng: VolleyRng
    /// Accessibility: a slower ball, one-button play (the sim walks him under the ball), and a jump for him.
    var ballSpeedScale: Float = 1
    var autoMove = false
    var autoJump = false
    /// The last point's story (for the cards and announcements).
    private(set) var lastPointTeam = -1
    private(set) var rallyHits = 0
    private(set) var longestRally = 0

    // drills
    private(set) var drillCount = 0, drillGood = 0, drillFeeds = 0
    private(set) var cushions: [Float] = []
    private(set) var targetCushion = 0
    private(set) var flags: [Float] = []
    private(set) var flagIndex = 0
    private(set) var drillTime: Float = 0
    private var feedWait: Float = 0
    static let spikeFeeds = 6, sprintFlags = 8, sprintTime: Float = 26, bonkCap = 25, bonkTime: Float = 70

    var tier: VolleyTier? { if case .match(let t) = mode { return t }; return nil }
    var isDrill: Bool { if case .drill = mode { return true }; return false }
    var drillKind: VolleyDrillKind? { if case .drill(let k) = mode { return k }; return nil }
    var human: Int { 0 }
    static func side(_ team: Int) -> Float { team == 0 ? -1 : 1 }

    init(mode: VolleyMode, mine: [VolleyStats], seed: UInt64, firstServe: Int = 0) {
        self.mode = mode
        rng = VolleyRng(seed)
        switch mode {
        case .match(let tier):
            let opp = VolleyStats.team(tier)
            let m0 = mine.first ?? VolleyStats(), m1 = mine.count > 1 ? mine[1] : VolleyStats.team(tier.below ?? .sandcastle)
            let skills: [Float] = [1, 0.5 + 0.2 * tier.skill, tier.skill, max(0, tier.skill - 0.05)]
            let st = [m0, m1, opp, VolleyStats.avg(opp, VolleyStats.team(tier.below ?? tier))]
            for i in 0..<4 {
                players.append(VolleyPlayer(team: i / 2, human: i == 0, stats: st[i], skill: skills[i], x: T.startX[i], wantX: T.startX[i]))
            }
            server = firstServe
        case .drill(let k):
            let m0 = mine.first ?? VolleyStats()
            players = [VolleyPlayer(team: 0, human: true, stats: m0, skill: 1, x: -1.5, wantX: -1.5)]
            cushions = [0.9, 1.7, 2.4]
            if k == .sprint {
                var xs: [Float] = [], last: Float = -1.5
                for i in 0..<Self.sprintFlags {
                    var x = rng.range(-2.4, -0.45)
                    if abs(x - last) < 1.1 { x = last < -1.4 ? rng.range(-0.9, -0.45) : rng.range(-2.4, -1.8) }
                    xs.append(x); last = x
                    _ = i
                }
                flags = xs
            }
        }
        serverIndex = server * 2
    }

    mutating func takeEvents() -> [VolleyEvent] { let e = events; events.removeAll(keepingCapacity: true); return e }
    var servingPlayer: Int { serverIndex }
    var waitingToServe: Bool { phase == .serveWait }
    var humanTeamWon: Bool { winner == 0 }
    var closeLoss: Bool { winner == 1 && score[0] >= score[1] - 2 }

    // MARK: player input (the human is player 0)

    mutating func setMove(_ dir: Float) {
        guard players.indices.contains(0), !autoMove || phase != .rally else { return }
        let p = players[0]
        let lo: Float = -T.halfCourt - 0.2, hi: Float = -T.netMargin
        players[0].wantX = min(max(p.x + dir * 0.9, lo), hi)
    }

    /// The Jump / action button. Serves when it is his serve; otherwise a jump (a dive at a low ball, a spike when already in the air).
    mutating func tap() {
        guard players.indices.contains(0) else { return }
        if phase == .serveWait {
            if !isDrill, serverIndex == 0 { toss(0) }
            return
        }
        guard phase == .rally || (isDrill && phase != .over) else { return }
        action(0)
    }

    private mutating func action(_ i: Int) {
        let p = players[i]
        if p.act == .jump, !p.grounded {
            players[i].act = .spike; players[i].actT = 0
            events.append(.spike(player: i))
        } else if p.act == .stand {
            let s = Self.side(p.team)
            let low = ball.pos.y < 1.05 + 0.35 && ball.vel.y < 1.0
            let reach = ball.pos.x - p.x
            if low, abs(reach) > 0.35, abs(reach) < T.diveReach + 0.35, ball.pos.x * s > -0.2 {
                players[i].act = .dive; players[i].actT = 0
                events.append(.dive(player: i, dir: reach > 0 ? 1 : -1))
            } else {
                // travel a little the way he is heading
                let dx = max(-0.5, min(0.5, (p.wantX - p.x) * 0.9))
                players[i].act = .jump; players[i].actT = 0
                events.append(.jump(player: i, dx: dx, apex: T.apex(hops: p.stats.hops)))
            }
        }
    }

    /// The body says its move has finished (landed and settled).
    mutating func bodyDone(_ i: Int) {
        guard players.indices.contains(i) else { return }
        players[i].act = .stand; players[i].actT = 0
    }

    // MARK: serve

    private mutating func toss(_ i: Int) {
        guard phase == .serveWait else { return }
        ball.vel = SIMD2(0, 2.3)
        phase = .rally; phaseT = 0
        lastHit = -1; touches = [0, 0]; rallyHits = 0
        events.append(.serveToss(player: i))
        // the server jumps so that his crown meets the ball on its way down
        players[i].jumpAt = 1.45
    }

    private mutating func startServe() {
        phase = .serveWait; phaseT = 0
        serverIndex = server * 2 + (score[server] + score[1 - server]) % 2
        if isDrill { serverIndex = 0 }
        touches = [0, 0]; lastHit = -1
        events.append(.serveReady(player: serverIndex))
        if serverIndex < players.count { players[serverIndex].wait = T.serveWaitAI }
    }

    // MARK: step

    mutating func tick(dt: Float) {
        clock += dt; phaseT += dt
        for i in players.indices {
            players[i].cooldown = max(0, players[i].cooldown - dt)
            players[i].actT += dt
        }
        switch phase {
        case .intro:
            hover(dt: dt)
            if phaseT >= T.introSeconds {
                if case .drill(let k) = mode {
                    phase = .rally; phaseT = 0; drillTime = 0
                    if k == .bonk { drop(x: -1.4, y: 3.2) }
                    if k == .spike { feed() }
                } else { startServe() }
            }
        case .serveWait:
            hover(dt: dt)
            if !players[serverIndex].human, players[serverIndex].wait > 0 {
                players[serverIndex].wait -= dt
                if players[serverIndex].wait <= 0 { toss(serverIndex) }
            }
            runAI(dt: dt)
        case .rally:
            if let k = drillKind { tickDrill(k, dt: dt); return }
            stepBall(dt: dt)
            runAI(dt: dt)
            serverJump()
        case .pointPause:
            restBall(dt: dt)
            runAI(dt: dt)
            if phaseT >= T.pointPause {
                if let w = winner { phase = .over; events.append(.matchOver(winner: w)) } else { startServe() }
            }
        case .over:
            break
        }
    }

    private mutating func restBall(dt: Float) {
        ball.vel.y -= T.gravity * dt
        ball.pos += ball.vel * dt
        ball.vel.x *= 0.99
        if ball.pos.y <= T.ballR { ball.pos.y = T.ballR; ball.vel.y = abs(ball.vel.y) > 0.6 ? abs(ball.vel.y) * 0.45 : 0; ball.vel.x *= 0.85 }
    }

    private mutating func hover(dt: Float) {
        guard !isDrill, players.indices.contains(serverIndex) else { return }
        let p = players[serverIndex]
        ball.pos = SIMD2(p.x + Self.side(p.team) * 0.1, p.top + 0.75 + 0.06 * sinf(clock * 3))
        ball.vel = .zero
    }

    private mutating func drop(x: Float, y: Float) { ball.pos = SIMD2(x, y); ball.vel = .zero; touches = [0, 0]; lastHit = -1 }

    /// A server whose toss is up jumps to meet it.
    private mutating func serverJump() {
        guard !isDrill, lastHit < 0, players.indices.contains(serverIndex), players[serverIndex].jumpAt >= 0 else { return }
        let i = serverIndex
        var p = players[i]
        p.jumpAt -= 0  // (kept for clarity)
        // the toss peaks at ~1.1 s after the throw; the crown meets the falling ball a little after the peak
        let apex = T.apex(hops: p.stats.hops), lead = T.crouch + 0.5 * T.airTime(apex: apex)
        if let t = timeToHeight(p.top + apex * 0.9 + 0.3), t <= lead + 0.02, p.act == .stand {
            players[i].jumpAt = -1
            players[i].act = .jump; players[i].actT = 0
            events.append(.jump(player: i, dx: Self.side(p.team) * 0.25, apex: apex))
        }
    }

    // MARK: ball

    /// Seconds until the (descending) ball centre reaches height `y`, nil if it never does within 4 s.
    func timeToHeight(_ y: Float, from b: VolleyBall? = nil) -> Float? {
        let b = b ?? ball
        let g = T.gravity
        // y(t) = y0 + vy t - g t^2 / 2 (drag ignored): the later root, in ball time
        let a = -0.5 * g, bb = b.vel.y, c = b.pos.y - y
        let disc = bb * bb - 4 * a * c
        guard disc >= 0 else { return nil }
        let r = (-bb - disc.squareRoot()) / (2 * a)          // a < 0: this is the later root
        guard r >= 0 else { return nil }
        return r / max(ballSpeedScale, 0.05)
    }

    func xAfter(_ t: Float) -> Float { let tb = t * ballSpeedScale; return ball.pos.x + ball.vel.x * (1 - 0.5 * T.drag * tb) * tb }

    private mutating func stepBall(dt: Float) {
        let h = dt * ballSpeedScale
        ball.vel.y -= T.gravity * h
        ball.vel.x *= max(0, 1 - T.drag * h)
        ball.vel.y *= max(0, 1 - 0.5 * T.drag * h)
        ball.pos += ball.vel * h
        ball.spin += ball.vel.x * 2.2 * h
        let R = T.ballR
        // the net
        if abs(ball.pos.x) < R, ball.pos.y < T.netTop + R * 0.5 {
            if ball.pos.y > T.netTop - 0.05 {         // the top tape: a little bounce up
                ball.vel.y = max(ball.vel.y, 0.8 * abs(ball.vel.x) + 0.8)
            } else {
                let s: Float = ball.pos.x >= 0 ? 1 : -1
                ball.pos.x = s * R
                ball.vel.x = abs(ball.vel.x) * 0.4 * s
                events.append(.net)
            }
        }
        // side walls (beyond the playing sand: a soft fence of the beach)
        if abs(ball.pos.x) > 4.2 { ball.pos.x = 4.2 * (ball.pos.x > 0 ? 1 : -1); ball.vel.x *= -0.5 }
        if ball.pos.y > 7 { ball.pos.y = 7; ball.vel.y = -abs(ball.vel.y) * 0.3 }
        // bodies
        for i in players.indices { contact(i) }
        // the sand
        if ball.pos.y <= R {
            ball.pos.y = R
            events.append(.bounce(x: ball.pos.x))
            landed()
        }
    }

    private mutating func landed() {
        let x = ball.pos.x
        let out = abs(x) > T.outLine
        // who loses the point
        var loser: Int
        if lastHit < 0 { loser = server }
        else if out { loser = players[lastHit].team }
        else { loser = x < 0 ? 0 : 1 }
        if let k = drillKind {
            switch k {
            case .bonk: phase = .over; events.append(.drillOver)
            case .spike:
                let good = lastHit >= 0 && abs(x - cushions[min(targetCushion, cushions.count - 1)]) < 0.6
                if good { drillGood += 1 }
                events.append(.drillHit(good))
                ball.vel = .zero
                if drillFeeds >= Self.spikeFeeds { phase = .over; events.append(.drillOver) } else { feedWait = 1.0 }
            case .sprint: break
            }
            return
        }
        let winnerTeam = 1 - loser
        awardPoint(winnerTeam, out: out)
    }

    private mutating func awardPoint(_ team: Int, out: Bool) {
        guard phase == .rally else { return }
        score[team] += 1
        lastPointTeam = team
        server = team
        longestRally = max(longestRally, rallyHits)
        phase = .pointPause; phaseT = 0
        events.append(.point(team: team, out: out))
        events.append(.cheer(team: team))
        ball.vel = SIMD2(ball.vel.x * 0.2, 1.4)
        if score[team] >= T.pointsToWin { winner = team }
    }

    // MARK: contact

    private mutating func contact(_ i: Int) {
        let p = players[i]
        guard p.cooldown <= 0, !p.samples.isEmpty else { return }
        let R = T.ballR + T.contactPad(timing: p.stats.timing) * (p.human ? 1 : 0.6)
        var sum = SIMD2<Float>.zero, n: Float = 0, best: Float = .infinity
        var bestPt = SIMD2<Float>.zero
        for s in p.samples {
            let d = simd_length(s - ball.pos)
            if d < R { sum += s; n += 1 }
            if d < best { best = d; bestPt = s }
        }
        var spikeZone = false
        if n == 0, p.act == .spike, p.actT > 0.06, p.actT < 0.55 {
            // the leaning body's round front reaches a little further than its sampled surface: a generous zone in front of the belly
            let front = SIMD2<Float>(p.x - Self.side(p.team) * 0.5, p.top - 0.15)
            if simd_length(front - ball.pos) < 0.78 { sum = front; n = 1; spikeZone = true }
        }
        guard n > 0 else { return }
        _ = spikeZone
        let c = sum / n
        var nrm = ball.pos - c
        let L = simd_length(nrm)
        nrm = L > 1e-4 ? nrm / L : SIMD2(0, 1)
        let rel = c.y - (T.bodyTop * 0.5 + p.lift)
        var kind: VolleyHit
        switch p.act {
        case .spike: kind = .spike
        case .dive: kind = .dig
        default: kind = rel > -0.1 ? .bonk : .dig
        }
        if lastHit < 0, i == serverIndex, !isDrill { kind = .serve }
        if p.act == .spike, p.actT < 0.06 { kind = .bonk }
        // a spike from a body that is not tipped (the ball met the crown early) is a bonk
        _ = bestPt
        let s = Self.side(p.team)
        let v = outgoing(i, kind: kind, at: c, normal: nrm)
        ball.vel = v
        ball.pos = c + nrm * (T.ballR + 0.02)
        if ball.pos.y < T.ballR { ball.pos.y = T.ballR }
        players[i].cooldown = 0.35
        players[i].hits += 1
        if lastHit != i || true { rallyHits += 1 }
        touches[p.team] += 1
        touches[1 - p.team] = 0
        lastHit = i
        events.append(.contact(player: i, kind: kind, point: c, normal: nrm, speed: simd_length(v)))
        if isDrill { drillContact(i, kind) }
        _ = s
    }

    /// Where the hit sends the ball: a landing spot chosen by the kind of hit and who hits, reached in a flight time set by the hitter's Power.
    private mutating func outgoing(_ i: Int, kind: VolleyHit, at c: SIMD2<Float>, normal n: SIMD2<Float>) -> SIMD2<Float> {
        let p = players[i]
        let s = Self.side(p.team), opp = -s
        let g = T.gravity
        let err = p.human ? T.aimError(timing: p.stats.timing) : (1 - p.skill) * 0.9 + 0.08
        var targetX: Float
        var tf: Float
        let tchs = touches[p.team]
        var over = true
        if let k = drillKind {
            switch k {
            case .bonk: targetX = rng.range(-2.3, -0.7); tf = 1.9; over = false
            case .spike:
                if kind == .spike { targetX = cushions[min(targetCushion, cushions.count - 1)] + rng.range(-1, 1) * err * 0.6; tf = T.spikeTime(power: p.stats.power) }
                else { targetX = -1.2; tf = 1.8; over = false }
            case .sprint: targetX = -1.5; tf = 1.8; over = false
            }
        } else {
            switch kind {
            case .serve: targetX = opp * rng.range(1.2, 2.3); tf = T.flightTime(power: p.stats.power, over: true) + 0.1
            case .spike: targetX = opp * rng.range(1.2, 2.5); tf = T.spikeTime(power: p.stats.power)
            case .dig:
                if tchs <= 1 { targetX = s * 0.95; tf = 1.95; over = false } else { targetX = opp * rng.range(0.8, 2.0); tf = 2.0 }
            case .bonk:
                if tchs <= 1, !(p.human && ball.pos.x * s < 0.9 && c.y > 1.9 && false) {
                    // a first touch sets the ball up for the partner (or sends it over when it is the second)
                    if tchs == 1 { targetX = opp * rng.range(0.8, 2.2); tf = T.flightTime(power: p.stats.power, over: true) }
                    else { targetX = s * 0.95; tf = 1.85; over = false }
                } else { targetX = opp * rng.range(0.8, 2.2); tf = T.flightTime(power: p.stats.power, over: true) }
            }
        }
        targetX += rng.range(-1, 1) * err
        // solve the launch for the landing spot; lift it until it clears the net when it must cross
        var vx: Float = 0, vy: Float = 0
        for _ in 0..<8 {
            vx = (targetX - c.x) / (tf * (1 - 0.5 * T.drag * tf))
            vy = (T.ballR - c.y) / tf + 0.5 * g * tf
            if !over || abs(c.x) < 0.02 { break }
            // height when the ball passes x = 0
            let tc = -c.x / vx
            if tc <= 0 || tc > tf { break }
            let yc = c.y + vy * tc - 0.5 * g * tc * tc
            if yc >= T.netTop + T.ballR + (kind == .spike ? 0.02 : 0.16) { break }
            tf *= 1.12
        }
        // off-centre hits steer a little
        if kind == .bonk || kind == .dig { vx += n.x * 0.45 }
        return SIMD2(vx, vy)
    }

    // MARK: computer players (and the helper for the human when assists are on)

    private mutating func runAI(dt: Float) {
        for i in players.indices {
            let p = players[i]
            let helped = p.human && (autoMove || autoJump)
            if p.human && !helped {
                if phase == .serveWait, serverIndex == i { players[i].wantX = Self.side(p.team) * T.backX }
                continue
            }
            ai(i, dt: dt, moveToo: !p.human || autoMove, jumpToo: !p.human || autoJump)
        }
        // keep teammates apart
        for team in 0..<2 where players.count >= 4 {
            let a = team * 2, b = a + 1
            if abs(players[a].wantX - players[b].wantX) < T.minGap {
                let mid = (players[a].wantX + players[b].wantX) / 2
                let d = players[a].wantX <= players[b].wantX ? 1 : -1
                players[a].wantX = mid - Float(d) * T.minGap / 2; players[b].wantX = mid + Float(d) * T.minGap / 2
            }
        }
        for i in players.indices {
            let s = Self.side(players[i].team)
            let lo: Float = s < 0 ? -T.halfCourt - 0.2 : T.netMargin, hi: Float = s < 0 ? -T.netMargin : T.halfCourt + 0.2
            players[i].wantX = min(max(players[i].wantX, lo), hi)
        }
    }

    private func designated(team: Int, landX: Float) -> Int {
        let a = team * 2, b = a + 1
        guard players.indices.contains(b) else { return a }
        // the nearer (in time) takes it; the human is only picked when helped or when he is clearly nearer
        let da = abs(players[a].x - landX) / max(T.walkSpeed(players[a]), 0.3), db = abs(players[b].x - landX) / max(T.walkSpeed(players[b]), 0.3)
        return da <= db + 0.12 ? a : b
    }

    private mutating func ai(_ i: Int, dt: Float, moveToo: Bool, jumpToo: Bool) {
        var p = players[i]
        let s = Self.side(p.team)
        let base: [Float] = i % 2 == 0 ? [1.95, 1.0] : [1.0, 1.95]
        _ = base
        let homeX = s * (i % 2 == 0 ? T.backX : T.frontX)
        if phase == .serveWait || phase == .intro {
            if moveToo { p.wantX = s * ((i == serverIndex) ? T.backX : T.frontX) }
            players[i] = p
            return
        }
        guard phase == .rally, ball.pos.x * s > -0.6 || ball.vel.x * s > 0.4 || lastHit < 0 else {
            if moveToo { p.wantX = homeX }
            players[i] = p
            return
        }
        // where will the ball be when it comes down to head height (or the sand)?
        let tH = timeToHeight(1.55) ?? timeToHeight(T.ballR) ?? 0
        let landX = xAfter(tH)
        let myTeamBall = landX * s > -0.35
        guard myTeamBall else { if moveToo { p.wantX = homeX }; players[i] = p; return }
        let d = designated(team: p.team, landX: landX)
        let reactDelay = (1 - p.skill) * 0.35
        if d == i {
            if moveToo {
                // brief reaction delay when the ball has just crossed
                p.wait = max(0, p.wait - dt)
                if p.wait <= 0 { p.wantX = landX }
            }
            // the decision to jump / dive
            let dist = abs(landX - p.x)
            let apex = T.apex(hops: p.stats.hops)
            let lead = T.crouch + 0.5 * T.airTime(apex: apex)
            if jumpToo, p.act == .stand, p.grounded {
                let attack = touches[p.team] >= 1 && abs(landX) < 1.9
                if let tJ = timeToHeight(p.top + apex * 0.85 + 0.25), attack || landX * s > 1.2 || ball.pos.y > 2.6 {
                    if tJ <= lead, dist < 0.55, ball.pos.x * s > -0.2 {
                        p.act = .jump; p.actT = 0
                        events.append(.jump(player: i, dx: max(-0.45, min(0.45, landX - p.x)), apex: apex))
                    }
                }
                if let tL = timeToHeight(T.ballR + 0.3), tL < 0.62, tL > 0.25, dist > 0.45, dist < T.diveReach, p.act == .stand, ball.vel.y < 0.5 {
                    p.act = .dive; p.actT = 0
                    events.append(.dive(player: i, dir: landX > p.x ? 1 : -1))
                }
            }
            if p.act == .jump, !p.grounded, p.actT > 0.05, jumpToo || !p.human {
                // spike: ball in front of the belly, on my side, near the net, and this is the 2nd+ touch
                let toBall = ball.pos - SIMD2(p.x, p.top - 0.5)
                if touches[p.team] >= 1, simd_length(toBall) < 1.15, toBall.x * s > -0.1, ball.pos.x * s > 0.1, ball.pos.y > T.netTop - 0.2 {
                    p.act = .spike; p.actT = 0
                    events.append(.spike(player: i))
                }
            }
            _ = reactDelay
        } else if moveToo {
            // the other one covers: back if the receiver is in front, else in front
            let recvFront = abs(players[d].x) < 1.45
            p.wantX = s * (recvFront ? T.backX : T.frontX)
            p.wait = reactDelay
        }
        players[i] = p
    }

    // MARK: drills

    private mutating func feed() {
        drillFeeds += 1
        targetCushion = Int(rng.next() * Float(cushions.count)) % cushions.count
        ball.pos = SIMD2(-0.55, 3.0); ball.vel = SIMD2(-0.15, 0)
        touches = [0, 0]; lastHit = -1
        events.append(.drillBall(drillFeeds))
    }

    private mutating func tickDrill(_ k: VolleyDrillKind, dt: Float) {
        drillTime += dt
        switch k {
        case .bonk:
            stepBall(dt: dt)
            if drillTime > Self.bonkTime || drillCount >= Self.bonkCap { phase = .over; events.append(.drillOver) }
        case .spike:
            if feedWait > 0 { feedWait -= dt; if feedWait <= 0 { feed() }; runAI(dt: dt); return }
            stepBall(dt: dt)
        case .sprint:
            let p = players[0]
            if flagIndex < flags.count, abs(p.x - flags[flagIndex]) < 0.22 {
                events.append(.flag(flagIndex)); flagIndex += 1; drillCount += 1
            }
            if flagIndex >= flags.count || drillTime > Self.sprintTime { phase = .over; events.append(.drillOver) }
        }
        runAI(dt: dt)
    }

    private mutating func drillContact(_ i: Int, _ kind: VolleyHit) {
        if drillKind == .bonk { drillCount += 1 }
    }

    /// Called when the drill's ball touches the sand (the landed() hook for drills).
    private mutating func drillLanded() {}

    /// Accuracy of a finished drill, 0...1.
    var drillAccuracy: Float {
        switch drillKind {
        case .bonk?: return min(1, Float(drillCount) / 14)
        case .spike?: return min(1, Float(drillGood) / Float(Self.spikeFeeds))
        case .sprint?:
            let done = Float(flagIndex) / Float(Self.sprintFlags)
            return done * (flagIndex >= flags.count ? min(1, 0.55 + 0.45 * max(0, (Self.sprintTime - drillTime) / (Self.sprintTime * 0.6))) : 0.8)
        case nil: return 0
        }
    }

    // MARK: sync from the bodies

    mutating func setBody(_ i: Int, x: Float, lift: Float, top: Float, grounded: Bool) {
        guard players.indices.contains(i) else { return }
        players[i].vx = (x - players[i].x) / (1.0 / 60)
        players[i].x = x; players[i].lift = lift; players[i].top = top; players[i].grounded = grounded
    }
    mutating func setSamples(_ i: Int, _ f: (inout [SIMD2<Float>]) -> Void) { if players.indices.contains(i) { f(&players[i].samples) } }
    mutating func forcePoint(team: Int) { awardPoint(team, out: false) }
    mutating func debugBall(pos: SIMD2<Float>, vel: SIMD2<Float>) { ball.pos = pos; ball.vel = vel }
}

nonisolated extension VolleyTuning {
    static func walkSpeed(_ p: VolleyPlayer) -> Float { walkSpeed(speed: p.stats.speed) }
}
