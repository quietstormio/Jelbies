//
//  VolleySim.swift
//  The rules and the ball of Jelly Volleyball (v2) as one pure model (no bodies, no screen): a big floaty beach ball (slow gravity, gentle drag) that flies in x, y AND z
//  (the court has depth now), four players (the human's team of two, two visitors), rally scoring to 11 (win by 2, cap 15), the real three-touch structure (BUMP, SET,
//  SPIKE, a fourth touch is a fault), the timing ring and its Perfect window, the combo, the body block, control switching (double-tap, auto-switch), the computer
//  players' decisions (smart teammate, tiered opponents), and the four training drills.
//
//  The sim never moves a body. Each step the glue gives it where the bodies ARE (x, z, lift, the surface points of the soft body) and takes back EVENTS to put on them:
//  jump / spike / dive / block for a body to perform, `contact` when the ball met a body (the glue dents the soft body there), points and the rest.
//  The ball bounces off the bodies' real soft surfaces; what it does after a hit (where it is sent) is decided here from the kind of hit (the touch count and the move),
//  its timing quality and the hitter's stats. Every hit is still a body move: belly or head bump, belly-flop spike, dig dive, body block.
//

import Foundation
import simd

/// What a hit was. The touch count and the body's move decide it: a first touch is a BUMP, a second a SET, a spike is the belly-flop smash, a dig is a dive, a free ball is
/// sent over early, a block is the wall at the net.
nonisolated enum VolleyHit: Equatable, Sendable { case bump, set, spike, dig, serve, free, block }

/// How the tap met the ball: the timing ring.
nonisolated enum VolleyQuality: Equatable, Sendable { case perfect, good, early, late }

nonisolated enum VolleyEvent: Equatable, Sendable {
    case jump(player: Int, dx: Float, dz: Float, apex: Float, block: Bool)
    case spike(player: Int)
    case dive(player: Int, dir: Float)
    case serveToss(player: Int)
    case contact(player: Int, kind: VolleyHit, quality: VolleyQuality, point: SIMD2<Float>, normal: SIMD2<Float>, speed: Float)
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
    /// Control moved to this player of the human's team (`auto`: the sim did it).
    case switched(to: Int, auto: Bool)
    /// A computer teammate is calling for the ball ("!" and a chirp).
    case call(player: Int)
    /// Floating text: tone 0 nice, 1 perfect, 2 weak, 3 big.
    case feedback(text: String, tone: Int)
    case combo(team: Int)
    /// A match-point spike: the slow-motion beat.
    case slowMo
    case touchCount(team: Int, count: Int)
    case fault(team: Int)
    /// The human's tap was graded Perfect: a tick and a haptic.
    case perfectTap(player: Int)
}

nonisolated enum VolleyAct: Equatable, Sendable { case stand, jump, spike, dive, block }

/// What a computer player means to do with its next hit.
nonisolated enum VolleyPlan: Equatable, Sendable { case auto, free, tip }

nonisolated struct VolleyPlayer: Sendable {
    var team: Int
    var human: Bool
    var stats: VolleyStats
    /// 0...1 how well the computer plays.
    var skill: Float
    var x: Float
    var z: Float = 0
    /// Height of the body's centre above its resting height (0 on the sand), the crown's height, and the real soft-body surface in the x/y plane.
    var lift: Float = 0
    var top: Float = VolleyTuning.bodyTop
    var samples: [SIMD2<Float>] = []
    var grounded = true
    /// What the body is doing (the sim sets it when it commands a move; the glue says when the body is done).
    var act: VolleyAct = .stand
    var actT: Float = 0
    var wantX: Float
    var wantZ: Float = 0
    var cooldown: Float = 0
    var wait: Float = 0
    var hits = 0
    var vx: Float = 0, vz: Float = 0
    /// This jump leans into a spike once it is airborne.
    var spikePlanned = false
    var plan: VolleyPlan = .auto
    var aim: SIMD2<Float>?
    var aimT: Float = -9
    var tapQ: VolleyQuality = .good
    var tapT: Float = -9
    var calledSerial = -1
    /// The computer's misjudgement of this ball's landing (sideways, metres), rolled once per touch.
    var readSerial = -1
    var readErr: Float = 0
    var lastX: Float = 0, lastZ: Float = 0
}

nonisolated struct VolleyBall: Sendable {
    var pos = SIMD2<Float>(0, 3)
    var vel = SIMD2<Float>(0, 0)
    var spin: Float = 0
    var z: Float = 0
    var vz: Float = 0
}

/// Where the ball will land, when the controlled player's tap would be ideal, and the Perfect window: the timing ring and its marker.
nonisolated struct VolleyRing: Equatable, Sendable {
    var x: Float, z: Float
    /// Seconds until the ball is at the hit height, the ideal lead for a tap, and the Perfect half window.
    var tau: Float, lead: Float, perfect: Float, good: Float
    var dig: Bool
}

nonisolated struct VolleyTiming: Sendable { var tau: Float, lead: Float, dig: Bool, x: Float, z: Float }

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

/// How the computer team of a tier plays (the human's AI teammate plays like a Reef team).
nonisolated struct VolleyAIParams: Sendable {
    var attack: Float      // chance of a spike (not a free ball) on the third touch
    var set: Float         // chance of a proper set (not a free ball over) on the second touch
    var perfect: Float     // chance a hit is Perfect
    var block: Float       // chance to put up a block against a set
    var tip: Float         // chance an attack is a soft tip over the block
    var read: Float        // how well it aims away from the people it plays
    var react: Float       // seconds before it starts running
    static func tier(_ t: VolleyTier) -> VolleyAIParams {
        switch t {
        case .sandcastle: return VolleyAIParams(attack: 0.08, set: 0.30, perfect: 0.04, block: 0, tip: 0, read: 0.0, react: 0.42)
        case .shore: return VolleyAIParams(attack: 0.45, set: 0.75, perfect: 0.18, block: 0.35, tip: 0, read: 0.25, react: 0.28)
        case .reef: return VolleyAIParams(attack: 0.90, set: 0.98, perfect: 0.38, block: 0.65, tip: 0.10, read: 0.75, react: 0.16)
        case .tidal: return VolleyAIParams(attack: 0.95, set: 1.0, perfect: 0.62, block: 0.85, tip: 0.35, read: 1.0, react: 0.08)
        }
    }
    static let teammate = VolleyAIParams(attack: 0.88, set: 1.0, perfect: 0.30, block: 0.55, tip: 0.05, read: 0.6, react: 0.10)
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
    private var serveRot = [0, 0]
    private(set) var lastHit = -1               // player index
    private(set) var touches = [0, 0]
    private(set) var clock: Float = 0
    private(set) var phaseT: Float = 0
    private(set) var winner: Int?
    private(set) var events: [VolleyEvent] = []
    var rng: VolleyRng
    /// Accessibility: a slower ball, one-button play (the sim walks him under the ball and switches control), hits at Good timing for him, a wider Perfect window.
    var ballSpeedScale: Float = 1
    var autoMove = false
    var autoJump = false
    var wideWindow = false
    /// When the ball crosses to your side, control jumps to the nearer teammate (a double-tap holds it for 2 s).
    var autoSwitch = true
    /// The last point's story (for the cards and announcements).
    private(set) var lastPointTeam = -1
    private(set) var rallyHits = 0
    private(set) var longestRally = 0

    // control
    private(set) var controlled = 0
    private(set) var stick = SIMD2<Float>.zero
    private var lastManualSwitch: Float = -9
    // touches, timing, combo
    private(set) var possession = -1
    private(set) var touchLog: [VolleyQuality] = []
    private(set) var chain = [0, 0]
    private(set) var touchSerial = 0
    private(set) var ring: VolleyRing?
    private(set) var serveMeter: Float?
    private var servePending = false
    private(set) var fxSerial = 0
    private(set) var fxText = ""
    private(set) var fxTone = 0
    private var blockWanted = [false, false]
    private var crossedFor = -1
    private(set) var comboFlash: Float = 0

    // drills
    private(set) var drillCount = 0, drillGood = 0, drillFeeds = 0, drillPerfect = 0
    private(set) var cushions: [Float] = []
    private(set) var targetCushion = 0
    private(set) var flags: [SIMD2<Float>] = []
    private(set) var flagIndex = 0
    private(set) var drillTime: Float = 0
    private var feedWait: Float = 0
    private var blockHang: Float = 0
    private var blockedNow = false
    private var hangZ: Float = 0
    static let spikeFeeds = 6, blockFeeds = 6, sprintFlags = 8, sprintTime: Float = 28, bonkCap = 26, bonkTime: Float = 70

    var tier: VolleyTier? { if case .match(let t) = mode { return t }; return nil }
    var isDrill: Bool { if case .drill = mode { return true }; return false }
    var drillKind: VolleyDrillKind? { if case .drill(let k) = mode { return k }; return nil }
    var human: Int { controlled }
    static func side(_ team: Int) -> Float { team == 0 ? -1 : 1 }
    func isHuman(_ i: Int) -> Bool { players.indices.contains(i) && i == controlled && players[i].team == 0 }

    init(mode: VolleyMode, mine: [VolleyStats], seed: UInt64, firstServe: Int = 0) {
        self.mode = mode
        rng = VolleyRng(seed)
        switch mode {
        case .match(let tier):
            let opp = VolleyStats.team(tier)
            let m0 = mine.first ?? VolleyStats(), m1 = mine.count > 1 ? mine[1] : VolleyStats.team(tier.below ?? .sandcastle)
            let skills: [Float] = [1, 0.75, tier.skill, max(0, tier.skill - 0.05)]
            let st = [m0, m1, opp, VolleyStats.avg(opp, VolleyStats.team(tier.below ?? tier))]
            for i in 0..<4 {
                players.append(VolleyPlayer(team: i / 2, human: i == 0, stats: st[i], skill: skills[i], x: T.startX[i], z: T.startZ[i], wantX: T.startX[i], wantZ: T.startZ[i]))
            }
            server = firstServe
        case .drill(let k):
            let m0 = mine.first ?? VolleyStats()
            let x: Float = k == .block ? -1.2 : -1.5
            players = [VolleyPlayer(team: 0, human: true, stats: m0, skill: 1, x: x, z: 0, wantX: x, wantZ: 0)]
            cushions = [0.9, 1.7, 2.4]
            if k == .sprint {
                var pts: [SIMD2<Float>] = [], last = SIMD2<Float>(-1.5, 0)
                for _ in 0..<Self.sprintFlags {
                    var p = SIMD2<Float>(rng.range(-2.4, -0.55), rng.range(-1.0, 1.0))
                    var tries = 0
                    while simd_distance(p, last) < 1.3, tries < 12 { p = SIMD2(rng.range(-2.4, -0.55), rng.range(-1.0, 1.0)); tries += 1 }
                    pts.append(p); last = p
                }
                flags = pts
            }
        }
        serverIndex = server * 2
    }

    mutating func takeEvents() -> [VolleyEvent] { let e = events; events.removeAll(keepingCapacity: true); return e }
    var servingPlayer: Int { serverIndex }
    var waitingToServe: Bool { phase == .serveWait }
    var humanTeamWon: Bool { winner == 0 }
    var closeLoss: Bool { winner == 1 && score[0] >= score[1] - 2 }
    private var params: [VolleyAIParams] { [.teammate, tier.map(VolleyAIParams.tier) ?? .teammate] }

    private mutating func fx(_ text: String, _ tone: Int) {
        fxSerial += 1; fxText = text; fxTone = tone
        events.append(.feedback(text: text, tone: tone))
    }

    // MARK: control

    /// The floating stick in court terms: x toward the net (screen up), y across the court (+z, screen right); `VolleyView.stick` maps a thumb to it. Magnitude 0...1.
    mutating func setStick(_ s: SIMD2<Float>) {
        let m = simd_length(s)
        stick = m > 1 ? s / m : s
    }

    /// Double-tap on a Jelbie of the human's team: take control of him.
    mutating func switchTo(_ i: Int, manual: Bool = true) {
        guard !isDrill, players.indices.contains(i), players[i].team == 0, i != controlled else { return }
        controlled = i
        for k in players.indices { players[k].human = (k == i) }
        stick = .zero
        if manual { lastManualSwitch = clock }
        events.append(.switched(to: i, auto: !manual))
    }

    /// A swipe on the Hit button: where on the other court the next hit is aimed (x: -1 short ... +1 deep, y: across the court, +1 = the screen's right; `VolleyView.aim` maps a swipe to it). nil clears it.
    mutating func setAim(_ a: SIMD2<Float>?) {
        guard players.indices.contains(controlled) else { return }
        players[controlled].aim = a
        players[controlled].aimT = clock
    }

    /// The Hit button went down. Serves when it is his serve (a second tap at the top of the toss is the power serve); otherwise it hits, in a way the situation decides.
    /// `lag`: seconds the sim state is behind the touch (positive: the touch came after the last step); the grade is taken at the touch, not at the next step.
    mutating func tap(lag: Float = 0) {
        guard players.indices.contains(controlled) else { return }
        tapLag = max(-0.1, min(0.1, lag)); defer { tapLag = 0 }
        if phase == .serveWait {
            if !isDrill, serverIndex == controlled { toss(controlled) }
            return
        }
        if phase == .rally, servePending, serverIndex == controlled, lastHit < 0, !isDrill {
            serveJump(controlled, quality: judge(timing(for: controlled), controlled))
            return
        }
        guard phase == .rally || (isDrill && phase != .over) else { return }
        action(controlled, ai: false)
    }

    // MARK: the action: what a tap (or a computer player's decision) does

    private func ballOnMySide(_ team: Int) -> Bool { ball.pos.x * Self.side(team) > 0 }

    /// The opponents have it and are about to attack near the net: a jump here is a block.
    private func blockSituation(_ i: Int) -> Bool {
        let p = players[i], opp = 1 - p.team
        guard !ballOnMySide(p.team) || abs(ball.pos.x) < 0.4, abs(p.x) < 1.85, abs(ball.pos.x) < 2.6, ball.pos.y > 0.9 else { return false }
        if touches[opp] >= 2 { return true }
        return players.contains { $0.team == opp && !$0.grounded && ($0.act == .jump || $0.act == .spike) && abs($0.x) < 2.4 }
    }

    /// Should this jump lean into a spike? The third touch always; any touch at the net with a high ball is an attack.
    private func spikeIntent(_ i: Int, timing tm: VolleyTiming?) -> Bool {
        let p = players[i], t = touches[p.team]
        guard let tm, !tm.dig else { return false }
        if t >= 2 { return true }
        let nearNet = abs(tm.x) < 1.75
        let highEnough = ball.pos.y > T.netTop + 0.5 || (timeToHeight(T.netTop + 0.8).map { $0 < 2.5 } ?? false)
        return nearNet && highEnough && t >= 1
    }

    /// What the next tap would do, for the button label.
    var hitLabel: String {
        guard players.indices.contains(controlled) else { return "Hit" }
        if phase == .serveWait, serverIndex == controlled { return "Toss" }
        if servePending, serverIndex == controlled { return "Serve!" }
        guard phase == .rally else { return "Hit" }
        let p = players[controlled]
        if p.act == .jump, !p.grounded { return "Spike" }
        if blockSituation(controlled) { return "Block" }
        if let tm = timing(for: controlled) {
            if tm.dig, ball.pos.y < 1.4 { return "Dig" }
            if spikeIntent(controlled, timing: tm) { return "Spike" }
            return touches[p.team] == 1 ? "Set" : touches[p.team] >= 2 ? "Send" : "Bump"
        }
        return "Jump"
    }

    private mutating func action(_ i: Int, ai: Bool) {
        let p = players[i]
        let s = Self.side(p.team)
        if p.act == .jump, !p.grounded {
            // a second tap in the air: lean into the spike right now
            if !p.spikePlanned, p.actT > T.crouch + 0.02 { players[i].spikePlanned = true; players[i].act = .spike; players[i].actT = 0; events.append(.spike(player: i)) }
            return
        }
        guard p.act == .stand else { return }
        let tm = timing(for: i)
        if blockSituation(i) {
            let apex = T.blockApex(hops: p.stats.hops)
            players[i].act = .block; players[i].actT = 0; players[i].spikePlanned = false
            players[i].tapQ = .good; players[i].tapT = clock
            events.append(.jump(player: i, dx: 0, dz: max(-0.5, min(0.5, (p.wantZ - p.z) * 0.9)), apex: apex, block: true))
            return
        }
        let q: VolleyQuality = ai ? rollQuality(i) : judge(tm, i)
        players[i].tapQ = q; players[i].tapT = clock
        if !ai, q == .perfect { events.append(.perfectTap(player: i)) }
        // a low ball is a dig: a dive at it
        let low = ball.pos.y < 1.05 + 0.35 && ball.vel.y < 1.0
        let reach = ball.pos.x - p.x
        if low, abs(reach) > 0.35, abs(reach) < T.diveReach + 0.35, ball.pos.x * s > -0.2, abs(ball.z - p.z) < 0.9 {
            players[i].act = .dive; players[i].actT = 0
            events.append(.dive(player: i, dir: reach > 0 ? 1 : -1))
            return
        }
        let spike = ai ? players[i].plan != .free && players[i].plan != .tip && spikeIntent(i, timing: tm) && aiAttacks(i) : spikeIntent(i, timing: tm)
        players[i].spikePlanned = spike
        if !ai { players[i].plan = (!spike && players[i].aim != nil && clock - players[i].aimT < 1.2) ? .free : .auto }
        let apex = T.apex(hops: p.stats.hops)
        let dx = max(-0.5, min(0.5, (p.wantX - p.x) * 0.9)), dz = max(-0.5, min(0.5, (p.wantZ - p.z) * 0.9))
        players[i].act = .jump; players[i].actT = 0
        events.append(.jump(player: i, dx: dx, dz: dz, apex: apex, block: false))
    }

    /// Does this computer player attack (spike) with its coming third touch?
    private mutating func aiAttacks(_ i: Int) -> Bool { true }

    // MARK: timing

    func timing(for i: Int) -> VolleyTiming? {
        guard players.indices.contains(i) else { return nil }
        let p = players[i], s = Self.side(p.team)
        guard let tl = timeToHeight(T.ballR) else { return nil }
        let lx = xAfter(tl), lz = zAfter(tl)
        guard lx * s > -0.25 else { return nil }
        let apex = T.apex(hops: p.stats.hops)
        let hitH = T.bodyTop + apex * 0.9 + 0.3
        if let t = timeToHeight(hitH) { return VolleyTiming(tau: t, lead: T.crouch + 0.5 * T.airTime(apex: apex), dig: false, x: lx, z: lz) }
        return VolleyTiming(tau: timeToHeight(0.6) ?? tl, lead: 0.28, dig: true, x: lx, z: lz)
    }

    /// Set while a tap is graded (see `tap(lag:)`).
    private var tapLag: Float = 0
    /// What the player saw was about a frame old by the time the glass showed it: the grade allows for it.
    static let displayLatency: Float = 1.0 / 60

    private func judge(_ tm: VolleyTiming?, _ i: Int) -> VolleyQuality {
        guard let tm, players.indices.contains(i) else { return .good }
        let st = players[i].stats.timing
        let pw = T.perfectWindow(timing: st, wide: wideWindow), gw = T.goodWindow(timing: st, wide: wideWindow)
        let e = tm.tau - tapLag + Self.displayLatency - tm.lead
        if abs(e) <= pw { return .perfect }
        if abs(e) <= gw { return .good }
        return e > 0 ? .early : .late
    }

    private mutating func rollQuality(_ i: Int) -> VolleyQuality {
        let pr = players[i].team == 0 ? params[0].perfect : params[1].perfect
        let r = rng.next()
        if r < pr { return .perfect }
        if r < pr + (1 - pr) * 0.8 { return .good }
        return rng.next() < 0.5 ? .early : .late
    }

    // MARK: serve

    private mutating func toss(_ i: Int) {
        guard phase == .serveWait else { return }
        ball.vel = SIMD2(0, 2.3)
        phase = .rally; phaseT = 0
        lastHit = -1; touches = [0, 0]; rallyHits = 0; possession = -1; touchLog = []; chain = [0, 0]; touchSerial += 1
        servePending = true
        events.append(.serveToss(player: i))
    }

    private mutating func serveJump(_ i: Int, quality q: VolleyQuality) {
        guard servePending, players[i].act == .stand else { return }
        servePending = false
        let p = players[i]
        players[i].act = .jump; players[i].actT = 0; players[i].spikePlanned = false
        players[i].tapQ = q; players[i].tapT = clock
        if isHuman(i), q == .perfect { events.append(.perfectTap(player: i)) }
        events.append(.jump(player: i, dx: Self.side(p.team) * 0.25, dz: 0, apex: T.apex(hops: p.stats.hops), block: false))
    }

    private mutating func startServe() {
        phase = .serveWait; phaseT = 0
        serverIndex = server * 2 + serveRot[server]
        if isDrill { serverIndex = 0 }
        touches = [0, 0]; lastHit = -1; possession = -1; touchLog = []; ring = nil; serveMeter = nil; servePending = false
        events.append(.serveReady(player: serverIndex))
        if serverIndex < players.count {
            players[serverIndex].wait = T.serveWaitAI
            // a human team serves with the server in hand: control moves to him
            if players[serverIndex].team == 0, serverIndex != controlled { switchTo(serverIndex, manual: false) }
        }
    }

    // MARK: step

    mutating func tick(dt: Float) {
        clock += dt; phaseT += dt
        comboFlash = max(0, comboFlash - dt)
        for i in players.indices {
            players[i].cooldown = max(0, players[i].cooldown - dt)
            players[i].actT += dt
            if players[i].act != .stand, players[i].actT > 2.5 { players[i].act = .stand; players[i].spikePlanned = false }      // stuck-state guard: no move lasts this long
        }
        switch phase {
        case .intro:
            hover(dt: dt)
            runAI(dt: dt)
            if phaseT >= T.introSeconds {
                if case .drill(let k) = mode {
                    phase = .rally; phaseT = 0; drillTime = 0
                    if k == .bonk { drop(x: -1.4, y: 3.2) }
                    if k == .spike { feed() }
                    if k == .block { feed() }
                } else { startServe() }
            }
        case .serveWait:
            hover(dt: dt)
            if !isHuman(serverIndex), players[serverIndex].wait > 0 {
                players[serverIndex].wait -= dt
                if players[serverIndex].wait <= 0 { toss(serverIndex) }
            }
            runAI(dt: dt)
        case .rally:
            if let k = drillKind { tickDrill(k, dt: dt); return }
            stepBall(dt: dt)
            // soft-lock guard: a rally that somehow never ends is called for whoever did not touch last
            if phase == .rally, !isDrill, phaseT > 60 { awardPoint(lastHit >= 0 ? 1 - players[lastHit].team : 1 - server, out: false); return }
            if phase == .rally {
                updateRing()
                runAI(dt: dt)
                fireSpikes()
                serverJump()
                autoSwitchTick()
            }
        case .pointPause:
            restBall(dt: dt)
            runAI(dt: dt)
            ring = nil; serveMeter = nil
            if phaseT >= T.pointPause {
                if let w = winner { phase = .over; events.append(.matchOver(winner: w)) } else { startServe() }
            }
        case .over:
            ring = nil
        }
    }

    private mutating func restBall(dt: Float) {
        ball.vel.y -= T.gravity * dt
        ball.pos += ball.vel * dt
        ball.z += ball.vz * dt
        ball.vel.x *= 0.99; ball.vz *= 0.99
        if ball.pos.y <= T.ballR { ball.pos.y = T.ballR; ball.vel.y = abs(ball.vel.y) > 0.6 ? abs(ball.vel.y) * 0.45 : 0; ball.vel.x *= 0.85; ball.vz *= 0.85 }
    }

    private mutating func hover(dt: Float) {
        guard !isDrill, players.indices.contains(serverIndex) else { return }
        let p = players[serverIndex]
        ball.pos = SIMD2(p.x + Self.side(p.team) * 0.1, p.top + 0.75 + 0.06 * sinf(clock * 3))
        ball.z = p.z
        ball.vel = .zero; ball.vz = 0
    }

    private mutating func drop(x: Float, y: Float, z: Float = 0) { ball.pos = SIMD2(x, y); ball.z = z; ball.vel = .zero; ball.vz = 0; touches = [0, 0]; lastHit = -1 }

    /// Fires the leans: a spike-planned jump tips onto its belly once it is a little way up.
    private mutating func fireSpikes() {
        for i in players.indices where players[i].act == .jump && players[i].spikePlanned && !players[i].grounded && players[i].actT >= T.crouch + 0.10 {
            players[i].act = .spike; players[i].actT = 0
            events.append(.spike(player: i))
        }
    }

    /// The server's jump: the human's second tap does it; with no second tap (or for a computer server) it goes at the ideal moment.
    private mutating func serveJumpTick() {}
    private mutating func serverJump() {
        guard !isDrill, servePending, lastHit < 0, players.indices.contains(serverIndex) else { serveMeter = nil; return }
        let i = serverIndex, p = players[i]
        let apex = T.apex(hops: p.stats.hops), lead = T.crouch + 0.5 * T.airTime(apex: apex)
        let hitH = T.bodyTop + apex * 0.9 + 0.3
        guard let t = timeToHeight(hitH) else { serveMeter = nil; return }
        let pw = T.perfectWindow(timing: p.stats.timing, wide: wideWindow)
        if isHuman(i) {
            serveMeter = min(1, max(0, (1 - max(-0.25, min(1, t - lead))) / 1.25))   // 0.8 is exactly the ideal moment (t == lead)
            _ = pw
            if t <= lead - 0.24, p.act == .stand { serveJump(i, quality: .late) }
        } else {
            serveMeter = nil
            if t <= lead + 0.02, p.act == .stand { serveJump(i, quality: rollQuality(i)) }
        }
    }

    var serveSweet: (center: Float, half: Float) {
        guard players.indices.contains(serverIndex) else { return (0.8, 0.05) }
        let pw = T.perfectWindow(timing: players[serverIndex].stats.timing, wide: wideWindow)
        return (0.8, max(0.025, pw / 1.25))      // meter units are seconds / 1.25, the same scale the grade uses
    }

    // MARK: ball

    /// Seconds until the (descending) ball centre reaches height `y`, nil if it never does.
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
    func zAfter(_ t: Float) -> Float { let tb = t * ballSpeedScale; return ball.z + ball.vz * (1 - 0.5 * T.drag * tb) * tb }

    private mutating func stepBall(dt: Float) {
        let h = dt * ballSpeedScale
        let sideBefore = ball.pos.x
        ball.vel.y -= T.gravity * h
        ball.vel.x *= max(0, 1 - T.drag * h)
        ball.vz *= max(0, 1 - T.drag * h)
        ball.vel.y *= max(0, 1 - 0.5 * T.drag * h)
        ball.pos += ball.vel * h
        ball.z += ball.vz * h
        ball.spin += ball.vel.x * 2.2 * h
        let R = T.ballR
        // the net (it runs the width of the court)
        if abs(ball.pos.x) < R, abs(ball.z) < T.netDepth, ball.pos.y < T.netTop + R * 0.5 {
            if ball.pos.y > T.netTop - 0.05 {         // the top tape: a little bounce up
                ball.vel.y = max(ball.vel.y, 0.8 * abs(ball.vel.x) + 0.8)
            } else {
                let s: Float = sideBefore >= 0 ? 1 : -1
                ball.pos.x = s * R
                ball.vel.x = abs(ball.vel.x) * 0.4 * s
                events.append(.net)
            }
        }
        // side walls (beyond the playing sand: a soft fence of the beach)
        if abs(ball.pos.x) > 4.2 { ball.pos.x = 4.2 * (ball.pos.x > 0 ? 1 : -1); ball.vel.x *= -0.5 }
        if abs(ball.z) > 3.2 { ball.z = 3.2 * (ball.z > 0 ? 1 : -1); ball.vz *= -0.5 }
        if ball.pos.y > 7 { ball.pos.y = 7; ball.vel.y = -abs(ball.vel.y) * 0.3 }
        // crossing to the human's side hands control to the nearer teammate
        if lastHit >= 0, players[lastHit].team == 1, sideBefore >= 0, ball.pos.x < 0, crossedFor != touchSerial {
            crossedFor = touchSerial
            autoSwitchNow(reason: .crossed)
        }
        // bodies
        for i in players.indices { contact(i) }
        // the sand
        if phase == .rally, ball.pos.y <= R {
            ball.pos.y = R
            events.append(.bounce(x: ball.pos.x))
            landed()
        }
    }

    private mutating func landed() {
        let x = ball.pos.x, zb = ball.z
        let out = abs(x) > T.outLine || abs(zb) > T.outZ
        // who loses the point
        var loser: Int
        if lastHit < 0 { loser = server }
        else if out { loser = players[lastHit].team }
        else { loser = x < 0 ? 0 : 1 }
        if let k = drillKind {
            switch k {
            case .bonk: phase = .over; events.append(.drillOver)
            case .spike:
                let good = lastHit >= 0 && abs(x - cushions[min(targetCushion, cushions.count - 1)]) < 0.6 && abs(zb) < 0.95
                if good { drillGood += 1 }
                events.append(.drillHit(good))
                ball.vel = .zero; ball.vz = 0
                if drillFeeds >= Self.spikeFeeds { phase = .over; events.append(.drillOver) } else { feedWait = 1.0 }
            case .block:
                let good = blockedNow && x > 0
                if good { drillGood += 1 }
                events.append(.drillHit(good))
                ball.vel = .zero; ball.vz = 0
                if drillFeeds >= Self.blockFeeds { phase = .over; events.append(.drillOver) } else { feedWait = 1.0 }
            case .sprint: break
            }
            return
        }
        awardPoint(1 - loser, out: out)
    }

    private func wins(_ team: Int) -> Bool {
        let s = score[team], o = score[1 - team]
        return (s >= T.pointsToWin && s - o >= T.winBy) || s >= T.scoreCap
    }

    private mutating func awardPoint(_ team: Int, out: Bool) {
        guard phase == .rally else { return }
        score[team] += 1
        lastPointTeam = team
        if team != server { serveRot[team] ^= 1 }          // side out: the other server of the winning team
        server = team
        longestRally = max(longestRally, rallyHits)
        phase = .pointPause; phaseT = 0
        ring = nil; serveMeter = nil; servePending = false
        events.append(.point(team: team, out: out))
        events.append(.cheer(team: team))
        ball.vel = SIMD2(ball.vel.x * 0.2, 1.4); ball.vz *= 0.2
        if wins(team) { winner = team }
    }

    /// Would this team win the match with one more point?
    private func matchPoint(_ team: Int) -> Bool {
        let s = score[team] + 1, o = score[1 - team]
        return (s >= T.pointsToWin && s - o >= T.winBy) || s >= T.scoreCap
    }

    // MARK: contact

    private mutating func contact(_ i: Int) {
        let p = players[i]
        guard phase == .rally, p.cooldown <= 0, !p.samples.isEmpty, abs(ball.z - p.z) < T.zReach else { return }
        let human = isHuman(i)
        let R = T.ballR + T.contactPad(timing: p.stats.timing) * (human ? 1 : 0.6)
        var sum = SIMD2<Float>.zero, n: Float = 0
        for s in p.samples where simd_length(s - ball.pos) < R { sum += s; n += 1 }
        if n == 0, p.act == .spike, p.actT > 0.06, p.actT < 0.55 {
            // the leaning body's round front reaches a little further than its sampled surface: a generous zone in front of the belly
            let front = SIMD2<Float>(p.x - Self.side(p.team) * 0.5, p.top - 0.15)
            if simd_length(front - ball.pos) < 0.78 { sum = front; n = 1 }
        }
        guard n > 0 else { return }
        let c = sum / n
        var nrm = ball.pos - c
        let L = simd_length(nrm)
        nrm = L > 1e-4 ? nrm / L : SIMD2(0, 1)
        let rel = c.y - (T.bodyTop * 0.5 + p.lift)
        let team = p.team
        let isServe = lastHit < 0 && i == serverIndex && !isDrill
        let before = touches[team]
        // what kind of hit: the body's move first, then the touch count
        var kind: VolleyHit
        switch p.act {
        case .spike: kind = p.actT < 0.06 ? .bump : .spike
        case .dive: kind = .dig
        case .block: kind = .block
        default: kind = rel > -0.1 ? .bump : .dig
        }
        if kind == .bump { kind = contextual(i, before: before, human: human) }
        if kind == .dig, before >= T.maxTouches - 1 { kind = .free }
        if isServe { kind = .serve }
        if let k = drillKind {
            switch k {
            case .bonk: kind = drillCount % 2 == 0 ? .bump : .set
            case .spike: if kind != .spike { kind = .free }
            case .block: if kind != .block { kind = .dig }
            case .sprint: break
            }
        }
        let fresh = clock - p.tapT < 1.3
        var q: VolleyQuality = fresh ? p.tapQ : .good
        if kind == .block { q = .good }
        // the combo: a Perfect bump, set and spike in one rally
        var combo = false
        if !isDrill {
            if q == .perfect, kind == .bump || kind == .dig { chain[team] = 1 }
            else if q == .perfect, kind == .set, chain[team] == 1 { chain[team] = 2 }
            else if q == .perfect, kind == .spike, chain[team] == 2 { combo = true; chain[team] = 0 }
            else if kind != .block { chain[team] = 0 }
        }
        let v = outgoing(i, kind: kind, quality: q, combo: combo, at: c, normal: nrm)
        ball.vel = SIMD2(v.x, v.y); ball.vz = v.z
        ball.pos = c + nrm * (T.ballR + 0.02)
        if ball.pos.y < T.ballR { ball.pos.y = T.ballR }
        players[i].cooldown = 0.35
        players[i].hits += 1
        players[i].aim = nil
        players[i].tapT = -9
        if players[i].act == .jump { players[i].spikePlanned = false }
        rallyHits += 1
        touchSerial += 1
        servePending = false
        // the touch count
        let prevPossession = possession
        if kind == .block {
            touches[team] = 0; touches[1 - team] = 0; possession = -1; touchLog = []
        } else if isServe {
            touches[team] = 0; touches[1 - team] = 0; possession = team; touchLog = []
        } else {
            if prevPossession != team { touchLog = [] }
            touches[team] += 1; touches[1 - team] = 0; possession = team
            touchLog.append(q)
        }
        lastHit = i
        events.append(.contact(player: i, kind: kind, quality: q, point: c, normal: nrm, speed: simd_length(v)))
        if !isServe, kind != .block { events.append(.touchCount(team: team, count: touches[team])) }
        // feedback text (for the human's team)
        if team == 0, !isDrill || drillKind == .bonk {
            if combo { fx("Combo!", 3) }
            else if kind == .block { fx("Block!", 3) }
            else if q == .perfect { fx("Perfect!", 1) }
            else if q == .early { fx("Early", 2) }
            else if q == .late { fx("Late", 2) }
            else if kind == .spike || kind == .set { fx("Nice!", 0) }
        } else if kind == .block, team == 1 { fx("Blocked!", 2) }
        if combo { comboFlash = 1.2; events.append(.combo(team: team)) }
        // a match-point spike gets the slow beat
        if kind == .spike, !isDrill, matchPoint(team) { events.append(.slowMo) }
        if isDrill { drillContact(i, kind, q) }
        // roll a block for the other side when a set goes up
        if !isDrill, kind == .set || (kind == .bump && before == 1) {
            blockWanted[1 - team] = rng.next() < params[1 - team].block
        }
        // control follows the ball after a hit by the controlled player
        if team == 0, !isDrill { autoSwitchNow(reason: .touched) }
        // a fourth touch is a fault
        if !isDrill, kind != .block, !isServe, touches[team] > T.maxTouches {
            events.append(.fault(team: team))
            fx("4 touches", 2)
            awardPoint(1 - team, out: false)
        }
    }

    /// A plain body hit's name from the touch count (and what the hitter means to do).
    private func contextual(_ i: Int, before: Int, human: Bool) -> VolleyHit {
        let p = players[i]
        if p.plan != .auto, !human || (clock - p.aimT < 1.2) { return .free }
        if human, p.aim != nil, clock - p.aimT < 1.2 { return .free }
        switch before {
        case 0: return .bump
        case 1: return .set
        default: return .free
        }
    }

    // MARK: where the hit sends the ball

    private func openSpot(from team: Int, read: Float) -> SIMD2<Float> {
        // the opponents' court in nine cells; the emptiest one
        let o = Self.side(1 - team)
        var best = SIMD2<Float>(o * 1.7, 0), bestScore: Float = -.infinity
        let opp = players.filter { $0.team == 1 - team }
        var salt = rng
        for cx: Float in [0.95, 1.75, 2.45] {
            for cz: Float in [-0.85, 0, 0.85] {
                let pt = SIMD2<Float>(o * cx, cz)
                var d: Float = 9
                for q in opp { d = min(d, simd_distance(pt, SIMD2(q.x + q.vx * 0.3 * read, q.z + q.vz * 0.3 * read))) }
                let sc = d + salt.range(0, 1.2 * (1 - read))
                if sc > bestScore { bestScore = sc; best = pt }
            }
        }
        return best
    }

    private func aimTarget(_ a: SIMD2<Float>, team: Int) -> SIMD2<Float> {
        let o = Self.side(1 - team)
        return SIMD2(o * 1.7 + 0.95 * a.x, 0.9 * a.y)
    }

    private mutating func chooseTarget(_ i: Int) -> SIMD2<Float> {
        let p = players[i]
        if isHuman(i) {
            if let a = p.aim, clock - p.aimT < 1.4 { return aimTarget(a, team: p.team) }
            return openSpot(from: p.team, read: 0.8)
        }
        _ = rng.next()
        return openSpot(from: p.team, read: params[p.team].read)
    }

    private mutating func outgoing(_ i: Int, kind: VolleyHit, quality q: VolleyQuality, combo: Bool, at c: SIMD2<Float>, normal n: SIMD2<Float>) -> SIMD3<Float> {
        let p = players[i]
        let s = Self.side(p.team), opp = -s
        let g = T.gravity
        let qf: Float = q == .perfect ? 0.25 : q == .good ? 1 : 1.8
        var err = (isHuman(i) ? T.aimError(timing: p.stats.timing) : (1 - p.skill) * 0.9 + 0.08) * qf
        if combo { err = 0 }
        var tgt: SIMD2<Float>
        var tf: Float
        var over = true
        let partner: VolleyPlayer? = players.indices.contains(p.team * 2 + (1 - i % 2)) && p.team * 2 + (1 - i % 2) != i ? players[p.team * 2 + (1 - i % 2)] : nil
        let slow: Float = q == .early || q == .late ? 1.12 : 1
        if let k = drillKind {
            switch k {
            case .bonk:
                tgt = SIMD2(rng.range(-2.3, -0.7), rng.range(-0.6, 0.6)); tf = kind == .set ? 2.25 : 1.9; over = false
            case .spike:
                if kind == .spike {
                    let cx = cushions[min(targetCushion, cushions.count - 1)]
                    if let a = p.aim, clock - p.aimT < 1.4 { tgt = aimTarget(a, team: 0) } else { tgt = SIMD2(1.7, 0) }
                    _ = cx
                    tf = T.spikeTime(power: p.stats.power) * (q == .perfect ? 0.9 : slow)
                } else { tgt = SIMD2(-1.2, 0); tf = 1.8; over = false }
            case .block:
                tgt = SIMD2(rng.range(0.9, 1.8), ball.z); tf = 0.85
            case .sprint: tgt = SIMD2(-1.5, 0); tf = 1.8; over = false
            }
            err *= 0.6
        } else {
            switch kind {
            case .serve:
                tgt = chooseTarget(i)
                tf = T.flightTime(power: p.stats.power, over: true) + 0.1 - (q == .perfect ? 0.3 : 0) + (q == .early || q == .late ? 0.2 : 0)
            case .spike:
                tgt = p.plan == .tip ? SIMD2(opp * rng.range(0.5, 0.85), rng.range(-0.8, 0.8)) : chooseTarget(i)
                tf = p.plan == .tip ? 1.4 : T.spikeTime(power: p.stats.power) * (q == .perfect ? 0.88 : slow) * (combo ? 0.72 : 1)
            case .free:
                if p.plan == .tip { tgt = SIMD2(opp * rng.range(0.5, 0.85), rng.range(-0.8, 0.8)); tf = 1.4 }
                else { tgt = chooseTarget(i); tf = T.flightTime(power: p.stats.power, over: true) + 0.15 }
            case .block:
                tgt = SIMD2(opp * rng.range(0.8, 1.9), ball.z); tf = 0.8
            case .bump, .dig:
                if touches[p.team] >= 2 { tgt = chooseTarget(i); tf = 2.0 }
                else {
                    // up and toward the teammate's spot (clamped to the front half so a set can follow)
                    let px = partner.map { s * min(max(abs($0.x), 1.15), 2.1) } ?? s * 1.3
                    tgt = SIMD2(px, max(-0.9, min(0.9, (partner?.z ?? 0) * 0.7)))
                    tf = kind == .dig ? 2.05 : 1.95
                }
                over = tgt.x * s < 0
            case .set:
                // high and soft near the net, for the spike
                let sz = max(-0.8, min(0.8, (partner?.z ?? 0) * 0.5))
                tgt = SIMD2(s * 1.05, sz); tf = 2.15 * (q == .perfect ? 0.97 : slow); over = false
            }
        }
        tgt.x += rng.range(-1, 1) * err
        tgt.y += rng.range(-1, 1) * err * 0.7
        if q == .early || q == .late { tgt += SIMD2(rng.range(-0.35, 0.35), rng.range(-0.25, 0.25)) }
        // solve the launch for the landing spot; lift it until it clears the net when it must cross
        var vx: Float = 0, vy: Float = 0
        for _ in 0..<8 {
            vx = (tgt.x - c.x) / (tf * (1 - 0.5 * T.drag * tf))
            vy = (T.ballR - c.y) / tf + 0.5 * g * tf
            if !over || abs(c.x) < 0.02 { break }
            let tc = -c.x / vx
            if tc <= 0 || tc > tf { break }
            let yc = c.y + vy * tc - 0.5 * g * tc * tc
            if yc >= T.netTop + T.ballR + (kind == .spike || kind == .block ? 0.02 : 0.16) { break }
            tf *= 1.12
        }
        let vz = (tgt.y - ball.z) / (tf * (1 - 0.5 * T.drag * tf))
        // off-centre hits steer a little
        if (kind == .bump || kind == .dig), q != .perfect { vx += n.x * 0.45 }
        return SIMD3(vx, vy, vz)
    }

    // MARK: control switching

    private enum SwitchReason { case crossed, touched }

    private mutating func autoSwitchNow(reason: SwitchReason) {
        guard !isDrill, players.count >= 4, autoSwitch || autoMove, clock - lastManualSwitch > 2.0 || phase == .serveWait else { return }
        var target = controlled
        switch reason {
        case .touched:
            // the ball goes to the partner of the one who just hit it
            guard lastHit >= 0, players[lastHit].team == 0, lastHit == controlled, touches[0] >= 1, touches[0] < T.maxTouches else { return }
            target = 1 - controlled
        case .crossed:
            guard let tl = timeToHeight(1.55) ?? timeToHeight(T.ballR) else { return }
            let lx = xAfter(tl), lz = zAfter(tl)
            let t0 = walkTime(0, lx, lz), t1 = walkTime(1, lx, lz)
            target = t0 <= t1 ? 0 : 1
            if abs(t0 - t1) < 0.15 { target = controlled }
        }
        if target != controlled { switchTo(target, manual: false) }
    }

    private mutating func autoSwitchTick() {}

    private func walkTime(_ i: Int, _ x: Float, _ z: Float) -> Float {
        let p = players[i]
        return simd_length(SIMD2(p.x - x, p.z - z)) / max(T.walkSpeed(p), 0.3)
    }

    // MARK: the ring

    private mutating func updateRing() {
        guard players.indices.contains(controlled), controlled < players.count else { ring = nil; return }
        let p = players[controlled]
        if isDrill, drillKind == .sprint || drillKind == .block { ring = nil; return }
        // not while the team's three touches are spent
        if !isDrill, touches[p.team] >= T.maxTouches { ring = nil; return }
        guard let tm = timing(for: controlled), tm.x * Self.side(p.team) > -0.2 || isDrill else { ring = nil; return }
        let pw = T.perfectWindow(timing: p.stats.timing, wide: wideWindow), gw = T.goodWindow(timing: p.stats.timing, wide: wideWindow)
        ring = VolleyRing(x: tm.x, z: tm.z, tau: tm.tau, lead: tm.lead, perfect: pw, good: gw, dig: tm.dig)
    }

    // MARK: computer players (and the helper for the human when assists are on)

    private mutating func runAI(dt: Float) {
        for i in players.indices {
            let p = players[i]
            let human = isHuman(i)
            let helped = human && (autoMove || autoJump)
            if human && !helped {
                let m = simd_length(stick)
                if m > 0.12 { players[i].wantX = p.x + stick.x * 0.9; players[i].wantZ = p.z + stick.y * 0.9 } else { players[i].wantX = p.x; players[i].wantZ = p.z }
                continue
            }
            ai(i, dt: dt, moveToo: !human || autoMove, hitToo: !human || autoJump)
            if human, autoMove, !autoJump, simd_length(stick) > 0.12 { players[i].wantX = p.x + stick.x * 0.9; players[i].wantZ = p.z + stick.y * 0.9 }
        }
        // the wishes stay on the court, then teammates are kept apart: the human on the stick (else the one whose wish is nearer the ball) keeps his spot and the other steps aside,
        // clear of both his wish and his body (a body is ~1.1 wide: they never merge)
        for i in players.indices { players[i].wantX = clampX(players[i].wantX, team: players[i].team); players[i].wantZ = min(max(players[i].wantZ, -T.zLimit), T.zLimit) }
        for team in 0..<2 where players.count >= 4 && !T.keepApart {          // (the old rule, for the A/B: the wishes alone, and the court's walls could undo it)
            let a = team * 2, b = a + 1
            let wa = SIMD2(players[a].wantX, players[a].wantZ), wb = SIMD2(players[b].wantX, players[b].wantZ)
            let d = simd_distance(wa, wb)
            if d < T.minGap {
                let dir: SIMD2<Float> = d > 1e-3 ? (wb - wa) / d : SIMD2(0, 1)
                let push = (T.minGap - d) / 2
                if isHuman(a) { players[b].wantX += dir.x * push * 2; players[b].wantZ += dir.y * push * 2 }
                else if isHuman(b) { players[a].wantX -= dir.x * push * 2; players[a].wantZ -= dir.y * push * 2 }
                else {
                    players[a].wantX -= dir.x * push; players[a].wantZ -= dir.y * push
                    players[b].wantX += dir.x * push; players[b].wantZ += dir.y * push
                }
            }
            players[a].wantX = clampX(players[a].wantX, team: team); players[b].wantX = clampX(players[b].wantX, team: team)
            players[a].wantZ = min(max(players[a].wantZ, -T.zLimit), T.zLimit); players[b].wantZ = min(max(players[b].wantZ, -T.zLimit), T.zLimit)
        }
        for team in 0..<2 where players.count >= 4 && T.keepApart {
            let a = team * 2, b = a + 1
            var ballP = SIMD2(ball.pos.x, ball.z)
            if phase == .rally, let tH = timeToHeight(1.55) ?? timeToHeight(T.ballR) { ballP = SIMD2(xAfter(tH), zAfter(tH)) }          // (where it will be at head height: whoever is going for it keeps his spot)
            let da = simd_distance(SIMD2(players[a].wantX, players[a].wantZ), ballP), db = simd_distance(SIMD2(players[b].wantX, players[b].wantZ), ballP)
            let assisted = autoMove || autoJump          // (a thumb on the stick keeps his spot; with the move assist he is a computer player)
            let keeper = isHuman(a) && !assisted ? a : isHuman(b) && !assisted ? b : (da <= db ? a : b), mover = keeper == a ? b : a
            var w = SIMD2(players[mover].wantX, players[mover].wantZ)
            let lane: Float = players[mover].z >= players[keeper].z ? 1 : -1          // (dead on the same spot: step to the side he is already on)
            w = clear(w, of: SIMD2(players[keeper].wantX, players[keeper].wantZ), gap: T.partnerGap, team: team, lane: lane)
            w = clear(w, of: SIMD2(players[keeper].x, players[keeper].z), gap: T.minCentreGap, team: team, lane: lane)
            players[mover].wantX = w.x; players[mover].wantZ = w.y
        }
    }

    private func clampX(_ x: Float, team: Int) -> Float {
        let s = Self.side(team)
        return min(max(x, s < 0 ? -T.halfCourt - 0.2 : T.netMargin), s < 0 ? -T.netMargin : T.halfCourt + 0.2)
    }

    /// `w` moved to the nearest point at least `gap` from `centre` that is still on the team's half of the court (it keeps `w` when it is clear already).
    private func clear(_ w: SIMD2<Float>, of centre: SIMD2<Float>, gap: Float, team: Int, lane: Float) -> SIMD2<Float> {
        if simd_distance(w, centre) >= gap - 1e-4 { return w }
        func onCourt(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(clampX(p.x, team: team), min(max(p.y, -T.zLimit), T.zLimit)) }
        var out = w - centre
        if simd_length(out) < 1e-3 { out = SIMD2(0, lane) }
        let direct = onCourt(centre + simd_normalize(out) * gap)
        if simd_distance(direct, centre) >= gap - 1e-3 { return direct }
        var best: SIMD2<Float>?
        for k in 0..<24 {          // (against a wall: the nearest clear point round the circle)
            let a = Float(k) / 24 * 2 * .pi
            let p = centre + SIMD2(cosf(a), sinf(a)) * gap
            guard simd_distance(onCourt(p), p) < 1e-3 else { continue }
            if best == nil || simd_distance(p, w) < simd_distance(best!, w) { best = p }
        }
        if let best { return best }
        // the keeper stands where no clear point is left (mid-court, the court being ~2 wide): the farthest corner
        let xs = [clampX(-100, team: team), clampX(100, team: team)], zs = [-T.zLimit, T.zLimit]
        var far = w
        for x in xs { for z in zs where simd_distance(SIMD2(x, z), centre) > simd_distance(far, centre) { far = SIMD2(x, z) } }
        return far
    }

    /// The teammate who should take the ball: after a touch, the other one; otherwise the nearer in time (the human a little favoured).
    private func designated(team: Int, landX: Float, landZ: Float) -> Int {
        let a = team * 2, b = a + 1
        guard players.indices.contains(b) else { return a }
        if lastHit >= 0, players[lastHit].team == team, touches[team] >= 1, touches[team] < T.maxTouches { return lastHit == a ? b : a }
        let ta = walkTime(a, landX, landZ) - (isHuman(a) ? 0.25 : 0), tb = walkTime(b, landX, landZ) - (isHuman(b) ? 0.25 : 0)
        return ta <= tb + 0.1 ? a : b
    }

    private mutating func ai(_ i: Int, dt: Float, moveToo: Bool, hitToo: Bool) {
        var p = players[i]
        let s = Self.side(p.team), team = p.team
        let backX = s * T.backX, frontX = s * T.frontX
        let roleBack = i % 2 == 0
        let homeX = roleBack ? backX : frontX
        let homeZ = T.startZ[min(i, 3)]
        let pr = params[team]
        if phase == .serveWait || phase == .intro {
            if moveToo { p.wantX = (i == serverIndex) ? backX : frontX; p.wantZ = (i == serverIndex) ? 0 : homeZ }
            players[i] = p
            return
        }
        guard phase == .rally, !isDrill || drillKind != .sprint else {
            if moveToo, phase != .rally { p.wantX = homeX; p.wantZ = homeZ }
            players[i] = p
            return
        }
        // where will the ball be when it comes down to head height (or the sand)?
        guard let tH = timeToHeight(1.55) ?? timeToHeight(T.ballR) else { players[i] = p; return }
        let landX = xAfter(tH), landZ = zAfter(tH)
        let mine = landX * s > -0.35 && (ballOnMySide(team) || ball.vel.x * s > 0.3 || lastHit < 0 || isDrill)
        if servePending, i == serverIndex {          // the server waits under his toss
            players[i] = p
            return
        }
        guard mine else {
            // the ball is with the others: be ready, and put up a block against a set
            p.wait = pr.react
            if !isDrill { aiBlock(&p, i: i, pr: pr) }
            if moveToo, p.act == .stand {
                let blocking = blockWanted[team] && touches[1 - team] >= 2 && abs(p.x) < 2.2 && (players.indices.contains(team * 2 + 1) ? abs(p.x) <= abs(players[team * 2 + (i % 2 == 0 ? 1 : 0)].x) : true)
                if !blocking {
                    // the partner (the human too) is front or back: take the other job, and stagger across the court
                    let mate = players.indices.contains(team * 2 + (i % 2 == 0 ? 1 : 0)) ? players[team * 2 + (i % 2 == 0 ? 1 : 0)] : nil
                    var hx = homeX, hz = homeZ + max(-0.5, min(0.5, ball.z * 0.3))
                    if let mate { hx = abs(mate.x) < 1.7 ? backX : frontX; hz = max(-0.9, min(0.9, -mate.z * 0.6 + ball.z * 0.2)) }
                    p.wantX = hx; p.wantZ = hz
                }
            }
            players[i] = p
            return
        }
        let d = designated(team: team, landX: landX, landZ: landZ)
        let t0 = touches[team]
        if d == i {
            let apex = T.apex(hops: p.stats.hops)
            let lead = T.crouch + 0.5 * T.airTime(apex: apex)
            let hitH = T.bodyTop + apex * 0.9 + 0.3
            // a lower-tier player misjudges the landing now and then (a miss that is the ball's fault, never an impossible save)
            if p.readSerial != touchSerial {
                p.readSerial = touchSerial
                let slip = (1 - pr.read) * 1.0
                p.readErr = (rng.next() - 0.5) * 2 * slip
                if !isDrill, rng.next() < 0.5 { p.readErr *= 0.3 }
            }
            var tx = landX + p.readErr
            if t0 >= 2 { tx = landX + s * 0.45 + p.readErr }
            if moveToo {
                p.wait = max(0, p.wait - dt)
                if p.wait <= 0 { p.wantX = tx; p.wantZ = landZ }
            }
            // a teammate calls for it
            if team == 0, !isHuman(i), !isDrill, p.calledSerial != touchSerial, tH < 2.4, lastHit >= 0 || tH < 1.6 {
                p.calledSerial = touchSerial
                events.append(.call(player: i))
            }
            let dist = simd_length(SIMD2(landX - p.x, landZ - p.z))
            if hitToo, p.act == .stand, p.grounded, p.cooldown <= 0 {
                if let tJ = timeToHeight(hitH), tJ <= lead, dist < 0.6, ball.pos.x * s > -0.2 {
                    decideAttack(&p, t0: t0, pr: pr, near: abs(landX) < 1.95)
                    players[i] = p
                    action(i, ai: true)
                    return
                }
                if let tL = timeToHeight(T.ballR + 0.3), tL < 0.62, tL > 0.25, abs(landX - p.x) > 0.45, abs(landX - p.x) < T.diveReach, abs(landZ - p.z) < 0.7, ball.vel.y < 0.5 {
                    players[i] = p
                    players[i].act = .dive; players[i].actT = 0
                    players[i].tapQ = .good; players[i].tapT = clock
                    events.append(.dive(player: i, dir: landX > p.x ? 1 : -1))
                    return
                }
            }
        } else if moveToo {
            // the other one covers or gets ready to attack
            let recv = players[d]
            p.wait = pr.react * 0.5
            switch t0 {
            case 0:
                let recvFront = abs(recv.x) < 1.45
                p.wantX = s * (recvFront ? T.backX : T.frontX)
                p.wantZ = max(-0.9, min(0.9, -recv.z * 0.7 + (recvFront ? 0 : 0.3)))
            case 1:
                // I just bumped: go to the net to attack the set
                p.wantX = s * 1.55; p.wantZ = max(-0.7, min(0.7, landZ * 0.6))
            default:
                // I just set: cover behind the spiker
                p.wantX = s * T.backX; p.wantZ = max(-0.8, min(0.8, -recv.z * 0.8))
            }
        }
        players[i] = p
    }

    /// The computer decides what its coming hit is: a spike, a tip, or a free ball over (by tier).
    private mutating func decideAttack(_ p: inout VolleyPlayer, t0: Int, pr: VolleyAIParams, near: Bool) {
        p.plan = .auto
        switch t0 {
        case 0:
            // the first touch: a bump to the partner, unless the ball is a gift near the net
            if ball.pos.y > T.netTop + 0.7, near, rng.next() < pr.attack * 0.5 { p.plan = .auto } else { p.plan = .auto }
        case 1:
            if rng.next() >= pr.set { p.plan = .free }
        default:
            if rng.next() >= pr.attack || !near { p.plan = .free }
            else if rng.next() < pr.tip { p.plan = .tip }
        }
        // a tip is a jump that pushes the ball over softly (no lean)
    }

    /// Blocks: the front player jumps when the attacker goes up.
    private mutating func aiBlock(_ p: inout VolleyPlayer, i: Int, pr: VolleyAIParams) {
        let team = p.team
        guard blockWanted[team], touches[1 - team] >= 2, p.act == .stand, p.grounded, abs(p.x) < 2.2 else { return }
        // only the front-most of the pair blocks
        let mate = team * 2 + (i % 2 == 0 ? 1 : 0)
        if players.indices.contains(mate), abs(players[mate].x) < abs(p.x) - 0.05 { return }
        // walk to the net opposite the attack
        if let tl = timeToHeight(1.8) {
            p.wantX = Self.side(team) * (T.netMargin + 0.05)
            p.wantZ = max(-T.zLimit, min(T.zLimit, zAfter(tl)))
        }
        guard !(isHuman(i) && !autoJump) else { return }
        // go up when the attacker does (after a human-sized reaction)
        let react = 0.04 + (1 - p.skill) * 0.25
        if players.contains(where: { $0.team == 1 - team && !$0.grounded && ($0.act == .jump || $0.act == .spike) && $0.actT > react && abs($0.x) < 2.4 }) {
            if abs(p.z - p.wantZ) < 0.7 { players[i].act = .block; players[i].actT = 0; p.act = .block
                players[i].tapQ = .good; players[i].tapT = clock
                events.append(.jump(player: i, dx: 0, dz: max(-0.5, min(0.5, (p.wantZ - p.z) * 0.9)), apex: T.blockApex(hops: p.stats.hops), block: true)) }
        }
    }

    // MARK: drills

    private mutating func feed() {
        drillFeeds += 1
        blockedNow = false
        if drillKind == .block {
            hangZ = rng.range(-0.7, 0.7)
            blockHang = 1.1
            ball.pos = SIMD2(1.25, 2.7); ball.z = hangZ; ball.vel = .zero; ball.vz = 0
            touches = [0, 2]; lastHit = -1
            events.append(.drillBall(drillFeeds))
            return
        }
        targetCushion = Int(rng.next() * Float(cushions.count)) % cushions.count
        ball.pos = SIMD2(-0.55, 3.0); ball.z = rng.range(-0.4, 0.4); ball.vel = SIMD2(-0.15, 0); ball.vz = 0
        touches = [2, 0]; lastHit = -1
        events.append(.drillBall(drillFeeds))
    }

    private mutating func tickDrill(_ k: VolleyDrillKind, dt: Float) {
        drillTime += dt
        switch k {
        case .bonk:
            stepBall(dt: dt)
            if drillTime > Self.bonkTime || drillCount >= Self.bonkCap { phase = .over; events.append(.drillOver) }
        case .spike:
            if feedWait > 0 { feedWait -= dt; if feedWait <= 0 { feed() }; runAI(dt: dt); updateRing(); return }
            stepBall(dt: dt)
            if phase == .rally { updateRing() }
        case .block:
            if feedWait > 0 { feedWait -= dt; if feedWait <= 0 { feed() }; runAI(dt: dt); return }
            if blockHang > 0 {
                blockHang -= dt
                ball.pos = SIMD2(1.25, 2.7 + 0.05 * sinf(clock * 6)); ball.z = hangZ; ball.vel = .zero; ball.vz = 0
                if blockHang <= 0 {
                    // the spike: a slow lob-spike down toward the player's court
                    let tx = -rng.range(1.5, 2.1), tz = hangZ + rng.range(-0.25, 0.25), tf: Float = 1.05
                    ball.vel = SIMD2((tx - 1.25) / (tf * (1 - 0.5 * T.drag * tf)), (T.ballR - 2.7) / tf + 0.5 * T.gravity * tf)
                    ball.vz = (tz - hangZ) / (tf * (1 - 0.5 * T.drag * tf))
                    touches = [0, 2]; lastHit = -1
                }
            } else { stepBall(dt: dt) }
        case .sprint:
            let p = players[0]
            if flagIndex < flags.count, simd_distance(SIMD2(p.x, p.z), flags[flagIndex]) < 0.28 {
                events.append(.flag(flagIndex)); flagIndex += 1; drillCount += 1
            }
            if flagIndex >= flags.count || drillTime > Self.sprintTime { phase = .over; events.append(.drillOver) }
        }
        if phase == .rally { runAI(dt: dt) }
    }

    private mutating func drillContact(_ i: Int, _ kind: VolleyHit, _ q: VolleyQuality) {
        switch drillKind {
        case .bonk?: drillCount += 1; if q == .perfect { drillPerfect += 1 }
        case .block?: if kind == .block { blockedNow = true }
        default: break
        }
    }

    /// Accuracy of a finished drill, 0...1.
    var drillAccuracy: Float {
        switch drillKind {
        case .bonk?: return min(1, (Float(drillCount) + 1.5 * Float(drillPerfect)) / 22)
        case .spike?: return min(1, Float(drillGood) / Float(Self.spikeFeeds))
        case .block?: return min(1, Float(drillGood) / Float(Self.blockFeeds))
        case .sprint?:
            let done = Float(flagIndex) / Float(Self.sprintFlags)
            return done * (flagIndex >= flags.count ? min(1, 0.55 + 0.45 * max(0, (Self.sprintTime - drillTime) / (Self.sprintTime * 0.6))) : 0.8)
        case nil: return 0
        }
    }

    // MARK: sync from the bodies

    mutating func setBody(_ i: Int, x: Float, z: Float = 0, lift: Float, top: Float, grounded: Bool) {
        guard players.indices.contains(i) else { return }
        players[i].vx = (x - players[i].x) / (1.0 / 60); players[i].vz = (z - players[i].z) / (1.0 / 60)
        players[i].x = x; players[i].z = z; players[i].lift = lift; players[i].top = top; players[i].grounded = grounded
    }
    mutating func setSamples(_ i: Int, _ f: (inout [SIMD2<Float>]) -> Void) { if players.indices.contains(i) { f(&players[i].samples) } }
    /// The body says its move has finished (landed and settled).
    mutating func bodyDone(_ i: Int) {
        guard players.indices.contains(i) else { return }
        players[i].act = .stand; players[i].actT = 0; players[i].spikePlanned = false
    }
    mutating func forcePoint(team: Int) { awardPoint(team, out: false) }
    mutating func debugBall(pos: SIMD2<Float>, vel: SIMD2<Float>, z: Float = 0) { ball.pos = pos; ball.vel = vel; ball.z = z; ball.vz = 0 }
    mutating func debugTouches(_ t: [Int], last: Int) { touches = t; lastHit = last }
    /// Capture aid: a rally in progress, with a few touches already in.
    mutating func debugRally(possession team: Int, touches count: Int) {
        phase = .rally; phaseT = 0; touches = [0, 0]; touches[team] = count; self.possession = team
        touchLog = Array(repeating: .good, count: count); servePending = false
    }
}

nonisolated extension VolleyTuning {
    static func walkSpeed(_ p: VolleyPlayer) -> Float { walkSpeed(speed: p.stats.speed) }
}
