//
//  VolleySim.swift
//  The rules and the ball of Jelly Volleyball (v2) as one pure model (no bodies, no screen): a big floaty beach ball (slow gravity, gentle drag) that flies in x, y AND z
//  (the court has depth now), four players (the human's team of two, two visitors), rally scoring to 3 (no win-by-2), the real three-touch structure (BUMP, SET,
//  SPIKE, a fourth touch is a fault), the timing ring and its Perfect window, the combo, the body block, control switching (double-tap, auto-switch), the computer
//  players' decisions (smart teammate, tiered opponents). 
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
    /// The body turns to this heading (radians, 0 = toward the camera, +pi/2 = toward +x) while it jumps for the ball: it faces what it hits.
    case face(player: Int, yaw: Float)
    case dive(player: Int, dir: Float)
    case serveToss(player: Int)
    case contact(player: Int, kind: VolleyHit, quality: VolleyQuality, point: SIMD2<Float>, normal: SIMD2<Float>, speed: Float)
    case bounce(x: Float)
    case net
    case point(team: Int, out: Bool)
    case serveReady(player: Int)
    case cheer(team: Int)
    case matchOver(winner: Int)
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
    /// The top of the head (or of the hat on it) in the world: x, y, z. nil until the glue says (then the crown is taken as (x, top, z)).
    var crown: SIMD3<Float>?
    /// Where the body is facing now (radians, as the body reports it); nil until the glue says (then the rest heading, 3/4 toward the camera and the net).
    var yaw: Float?
    /// Where he is told to look (radians): at the ball while it is his to play; nil = the rest heading. The body turns to it on the ground and in the air.
    var faceGoal: Float?
    var crownPoint: SIMD3<Float> { crown ?? SIMD3(x, top, z) }
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
nonisolated enum VolleyMode: Equatable, Sendable { case match(VolleyTier) }

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
    /// 2026-11-17 (the owner: "make the computer a little less competitive especially in the beginning levels"): the early levels play like friendly visitors.
    /// `mishit` the chance a hit of theirs is an honest mistake (a serve or return into the net or past the line, a pass the partner cannot reach); `easy` the chance a return
    /// is aimed at the nearer of your Jelmiko (easy to reach) instead of the emptiest spot; `loft` seconds added to every flight (higher and softer); `slip` how far (u) they
    /// misjudge where the ball lands (nil: the old `1 - read`); `smash` whether they spike at all; `reactSpread` the random extra of the reaction time.
    var mishit: Float = 0
    var easy: Float = 0
    var loft: Float = 0
    var slip: Float? = nil
    var smash = true
    var reactSpread: Float = 0
    /// Spike flight time multiplier (below 1: faster, harder to dig).
    var spikeFast: Float = 1
    /// Serve flight time multiplier (below 1: a quicker serve).
    var serveFast: Float = 1
    /// Settles who takes the ball once per touch and keeps to it.
    var sticky = false
    /// How well the team notices that the human keeps putting the ball in the same part of the court (2026-11-24: 'I won every set the same way'): 0 never, 1 always. Once two
    /// hits in a row went to the same ninth of the court, one defender waits there and neither loses time reacting or misjudging it.
    var adapt: Float = 0
    static func tier(_ t: VolleyTier) -> VolleyAIParams { tierBase(t) }
    static func tierBase(_ t: VolleyTier) -> VolleyAIParams {
        if VolleyTuning.old { return oldTier(t) }
        if !VolleyTuning.hard { return installTenT(t) }
        // 2026-11-24 (the owner: "slightly increase difficulty of volleyball opponents ... I won every set the same way"): the numbers after the harness round (VolleyHarness bots, 40 to 100
        // matches a cell): the visitors make fewer honest mistakes, start running sooner, smash a little faster and notice a placement the player keeps using (`adapt`).
        switch t {
        case .sandcastle: return VolleyAIParams(attack: 0, set: 0.30, perfect: 0.02, block: 0, tip: 0, read: 0.0, react: 0.40, mishit: 0.20, easy: 0.35, loft: 0.25, slip: 0.9, smash: false, reactSpread: 0.25, adapt: 0)
        case .shore: return VolleyAIParams(attack: 0.55, set: 0.80, perfect: 0.18, block: 0.20, tip: 0, read: 0.25, react: 0.20, mishit: 0.10, easy: 0.25, loft: 0.12, slip: 0.50, smash: true, reactSpread: 0.10, adapt: 0.9)
        case .reef: return VolleyAIParams(attack: 0.90, set: 0.95, perfect: 0.55, block: 0.35, tip: 0.10, read: 0.75, react: 0.06, mishit: 0.02, easy: 0.10, loft: 0.05, slip: 0.30, smash: true, reactSpread: 0.08, sticky: true, adapt: 1.0)
        case .tidal: return VolleyAIParams(attack: 0.97, set: 1.0, perfect: 0.65, block: 0.45, tip: 0.30, read: 1.0, react: 0.04, mishit: 0.02, easy: 0, loft: 0, slip: 0.05, smash: true, reactSpread: 0.03, serveFast: 0.55, sticky: true, adapt: 1)
        }
    }
    /// The computer team as installed on the phone at 10t (`-VolleyHard 0`).
    static func installTenT(_ t: VolleyTier) -> VolleyAIParams {
        switch t {
        case .sandcastle: return VolleyAIParams(attack: 0, set: 0.30, perfect: 0.02, block: 0, tip: 0, read: 0.0, react: 0.60, mishit: 0.50, easy: 0.90, loft: 0.55, slip: 1.40, smash: false, reactSpread: 0.25)
        case .shore: return VolleyAIParams(attack: 0.40, set: 0.70, perfect: 0.12, block: 0.25, tip: 0, read: 0.25, react: 0.40, mishit: 0.27, easy: 0.50, loft: 0.25, slip: 0.85, smash: true, reactSpread: 0.15)
        case .reef: return VolleyAIParams(attack: 0.80, set: 0.95, perfect: 0.30, block: 0.55, tip: 0.10, read: 0.75, react: 0.24, mishit: 0.10, easy: 0.10, loft: 0.05, slip: 0.40, smash: true, reactSpread: 0.08, sticky: true)
        case .tidal: return VolleyAIParams(attack: 0.92, set: 1.0, perfect: 0.35, block: 0.80, tip: 0.30, read: 1.0, react: 0.10, mishit: 0.08, easy: 0, loft: 0, slip: 0.05, smash: true, reactSpread: 0.03, spikeFast: 0.8, serveFast: 0.55, sticky: true)
        }
    }
    /// The play before 2026-11-17 (`-VolleyOld 1`).
    static func oldTier(_ t: VolleyTier) -> VolleyAIParams {
        switch t {
        case .sandcastle: return VolleyAIParams(attack: 0.08, set: 0.30, perfect: 0.04, block: 0, tip: 0, read: 0.0, react: 0.42)
        case .shore: return VolleyAIParams(attack: 0.45, set: 0.75, perfect: 0.18, block: 0.35, tip: 0, read: 0.25, react: 0.28)
        case .reef: return VolleyAIParams(attack: 0.90, set: 0.98, perfect: 0.38, block: 0.65, tip: 0.10, read: 0.75, react: 0.16)
        case .tidal: return VolleyAIParams(attack: 0.95, set: 1.0, perfect: 0.62, block: 0.85, tip: 0.35, read: 1.0, react: 0.08)
        }
    }
    static let teammate = VolleyAIParams(attack: 0.88, set: 1.0, perfect: 0.30, block: 0.55, tip: 0.05, read: 0.6, react: 0.10)
}

nonisolated enum FlightCap {
    static var passScale: Float = {
        #if STANDALONE
        if let v = ProcessInfo.processInfo.environment["PASSSCALE"], let f = Float(v) { return f }
        #endif
        return 1.0
    }()
    static var maxSmash: Float = {
        #if STANDALONE
        if let v = ProcessInfo.processInfo.environment["MAXSMASH"], let f = Float(v) { return f }
        #endif
        return 2.0
    }()
}

nonisolated struct VolleySim: Sendable {
    typealias T = VolleyTuning
    let mode: VolleyMode
    private(set) var players: [VolleyPlayer] = []
    private(set) var ball = VolleyBall()
    var phase: VolleyPhase = .intro
    var score = [0, 0]
    private(set) var server = 0                 // team serving
    private(set) var serverIndex = 0            // the player who serves
    private var serveRot = [0, 0]
    private(set) var lastHit = -1               // player index
    private(set) var touches = [0, 0]
    private(set) var clock: Float = 0
    /// How many times the human actually played: Hit taps, fresh stick pushes and manual switches. An idle (AFK) player stays near 0.
    private(set) var humanInputs = 0
    private(set) var phaseT: Float = 0
    var winner: Int?
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
    private var desigSerial = [-1, -1], desigFor = [0, 0]
    /// The serve ball: it rests ON the server's head (`restT` = seconds since it settled there, for the little settle wobble) and, after a point, travels to the next server's head by a short arc (`carry`).
    private(set) var restT: Float = 0
    private var carried = false
    private(set) var carry: (from: SIMD3<Float>, t: Float, dur: Float)?
    /// The ball sits on the server's head right now (not travelling, not in play).
    var ballOnHead: Bool { !VolleyTuning.old && (phase == .intro || phase == .serveWait) && carry == nil }
    static let carryLead: Float = 1.0, carryDur: Float = 0.85
    private var crossedFor = -1
    /// The player whose hit the ball is still leaving: it bounces off his body (no touch) until it has cleared it (a spiker never hits his own slow ball again: no fourth-touch faults).
    private var guardPlayer = -1
    /// The computer team misses reading a smash of the player's until this clock (see `digMiss`): it cannot start running for the ball.
    private var blindUntil: Float = -1
    /// A short ball the computer has read (where it is going, and until when): its nearer player goes in at once.
    private var shortRead: (spot: SIMD2<Float>, until: Float)?
    /// Measuring aids: how many balls rolled off a back turned to them, and where (x, y, z) the ball was when the last touch began.
    private(set) var turnedAway = 0
    /// Measuring aid: smashes played and how many fell back to a lob, per team.
    private(set) var smashCount = [0, 0], smashLobbed = [0, 0]
    private(set) var contactBall = SIMD3<Float>.zero
    /// The ninths of the computer's court the human team's last shots were sent to (see `VolleyAIParams.adapt`), and the last outgoing target.
    private var humanCells: [Int] = []
    private var lastTgt = SIMD2<Float>.zero
    private var lastKind: VolleyHit = .bump
    private(set) var comboFlash: Float = 0

    var tier: VolleyTier? { if case .match(let t) = mode { return t }; return nil }
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
        }
        serverIndex = server * 2
        if players.indices.contains(serverIndex) {          // (the first frames, under the fade: the ball is already on the first server's head)
            let c = players[serverIndex].crownPoint
            ball.pos = SIMD2(c.x, c.y + T.ballR); ball.z = c.z
        }
    }

    mutating func takeEvents() -> [VolleyEvent] { let e = events; events.removeAll(keepingCapacity: true); return e }
    var servingPlayer: Int { serverIndex }
    var waitingToServe: Bool { phase == .serveWait }
    var humanTeamWon: Bool { winner == 0 }
    /// Enough real input that the match counts as played (an idle loss pays nothing, gives no points and no close-loss credit).
    static let minInputsToCount = 3
    var humanPlayed: Bool { humanInputs >= Self.minInputsToCount }
    var closeLoss: Bool { winner == 1 && score[0] >= score[1] - 1 }          // (lost by one point: at first-to-3 that is 2-3)
    private var params: [VolleyAIParams] { [.teammate, tier.map(VolleyAIParams.tier) ?? .teammate] }

    private mutating func fx(_ text: String, _ tone: Int) {
        fxSerial += 1; fxText = text; fxTone = tone
        events.append(.feedback(text: text, tone: tone))
    }

    // MARK: control

    /// The floating stick: x is toward the screen's right (+x on the court), y toward the camera (+z). Magnitude 0...1.
    mutating func setStick(_ s: SIMD2<Float>) {
        let m = simd_length(s)
        if m > 0.3, simd_length(stick) <= 0.3 { humanInputs += 1 }          // (a fresh push, not a held stick)
        stick = m > 1 ? s / m : s
    }

    /// Double-tap on a Jelbie of the human's team: take control of him.
    mutating func switchTo(_ i: Int, manual: Bool = true) {
        guard players.indices.contains(i), players[i].team == 0, i != controlled else { return }
        controlled = i
        for k in players.indices { players[k].human = (k == i) }
        stick = .zero
        if manual { humanInputs += 1 }
        if manual { lastManualSwitch = clock }
        events.append(.switched(to: i, auto: !manual))
    }

    /// A swipe on the Hit button: where on the other court the next hit is aimed (x: -1 short ... +1 deep, y: -1 far ... +1 near the camera). nil clears it.
    mutating func setAim(_ a: SIMD2<Float>?) {
        guard players.indices.contains(controlled) else { return }
        players[controlled].aim = a
        players[controlled].aimT = clock
    }

    /// The Hit button went down. Serves when it is his serve (a second tap at the top of the toss is the power serve); otherwise it hits, in a way the situation decides.
    /// `lag`: seconds the sim state is behind the touch (positive: the touch came after the last step); the grade is taken at the touch, not at the next step.
    mutating func tap(lag: Float = 0) {
        guard players.indices.contains(controlled) else { return }
        humanInputs += 1
        tapLag = max(-0.1, min(0.1, lag)); defer { tapLag = 0 }
        if phase == .serveWait {
            if serverIndex == controlled, carry == nil { toss(controlled) }
            return
        }
        if phase == .rally, servePending, serverIndex == controlled, lastHit < 0 {
            serveJump(controlled, quality: judge(timing(for: controlled), controlled))
            return
        }
        guard phase == .rally else { return }
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
        // a smash is struck square to the net: only with the ball in front of that heading (a ball that will pass behind him is played, not smashed)
        if T.facing, !ballInFront(i, at: SIMD2(xAfter(tm.tau), zAfter(tm.tau)), yaw: -Self.side(p.team) * .pi / 2) { return false }
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
        if low, abs(reach) > 0.35, abs(reach) < T.diveReach + 0.35, ball.pos.x * s > -0.2, abs(ball.z - p.z) < 0.9, !T.facing || ballInFront(i, at: SIMD2(ball.pos.x, ball.z), yaw: reach > 0 ? .pi / 2 : -.pi / 2) {
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
        if !spike, let y = faceForBall(i, landing: tm.map { SIMD2(xAfter($0.tau), zAfter($0.tau)) }) { events.append(.face(player: i, yaw: y)) }          // (toward where the ball will be when it is at his hitting height)
        events.append(.jump(player: i, dx: dx, dz: dz, apex: apex, block: false))
    }

    /// Does this computer player attack (spike) with its coming third touch?
    private mutating func aiAttacks(_ i: Int) -> Bool { players[i].team == 0 || params[1].smash }

    /// A repeatable 0...1 from two integers (no random-stream draw: the computer's reaction jitter must not shift the match's seed).
    private func unit(_ a: Int, _ b: Int) -> Float {
        var h = UInt64(truncatingIfNeeded: a) &* 0x9E3779B97F4A7C15 ^ UInt64(truncatingIfNeeded: b) &* 0xBF58476D1CE4E5B9
        h ^= h >> 29; h = h &* 0x94D049BB133111EB; h ^= h >> 32
        return Float(h >> 40) / Float(1 << 24)
    }

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
        var pr = players[i].team == 0 ? params[0].perfect : params[1].perfect
        if T.hard, players[i].team == 1, readsHabit() { pr += 0.25 * params[1].adapt }
        let r = rng.next()
        if r < pr { return .perfect }
        if r < pr + (1 - pr) * 0.8 { return .good }
        return rng.next() < 0.5 ? .early : .late
    }

    // MARK: serve

    private mutating func toss(_ i: Int) {
        guard phase == .serveWait else { return }
        if VolleyTuning.old { ball.vel = SIMD2(0, 2.3) }
        else {
            // the ball pops up off the head. Its flight from the old hover (0.75 above the crown, 2.3 up) is the serve's timing: the pop speed is solved so the ball comes back down
            // to the serve height at the very same moment, whatever height it starts from (a hat raises it).
            let g = T.gravity, p = players[i]
            let hitH = T.bodyTop + T.apex(hops: p.stats.hops) * 0.9 + 0.3
            let y0 = p.top + 0.75
            let tOld = (2.3 + max(2.3 * 2.3 + 2 * g * (y0 - hitH), 0).squareRoot()) / g
            ball.vel = SIMD2(0, (hitH - ball.pos.y + 0.5 * g * tOld * tOld) / tOld)
            carry = nil
        }
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
        phase = .serveWait; phaseT = 0; carried = false
        serverIndex = server * 2 + serveRot[server]
        touches = [0, 0]; lastHit = -1; possession = -1; touchLog = []; ring = nil; serveMeter = nil; servePending = false; guardPlayer = -1
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
        if phase != .rally { for i in players.indices { players[i].faceGoal = nil } }          // (nobody keeps staring at a ball that is not in play)
        switch phase {
        case .intro:
            hover(dt: dt)
            runAI(dt: dt)
            if phaseT >= T.introSeconds { startServe() }
        case .serveWait:
            hover(dt: dt)
            if !isHuman(serverIndex), carry == nil, players[serverIndex].wait > 0 {
                players[serverIndex].wait -= dt
                if players[serverIndex].wait <= 0 { toss(serverIndex) }
            }
            runAI(dt: dt)
        case .rally:
            stepBall(dt: dt)
            // soft-lock guard: a rally that somehow never ends is called for whoever did not touch last
            if phase == .rally, phaseT > 60 { awardPoint(lastHit >= 0 ? 1 - players[lastHit].team : 1 - server, out: false); return }
            if phase == .rally {
                updateRing()
                runAI(dt: dt)
                updateFacing()
                fireSpikes()
                serverJump()
                autoSwitchTick()
            }
        case .pointPause:
            if carry == nil, VolleyTuning.old || winner != nil || phaseT < T.pointPause - Self.carryLead { restBall(dt: dt) } else { hover(dt: dt, toNext: true) }
            runAI(dt: dt)
            ring = nil; serveMeter = nil
            if phaseT >= T.pointPause {
                if let w = winner { phase = .over; events.append(.matchOver(winner: w)) } else { startServe() }
            }
        case .over:
            ring = nil
            if !VolleyTuning.old { restBall(dt: dt) }          // (the ball always comes to rest on the sand: never left hanging)
        }
    }

    private mutating func restBall(dt: Float) {
        ball.vel.y -= T.gravity * dt
        ball.pos += ball.vel * dt
        ball.z += ball.vz * dt
        ball.vel.x *= 0.99; ball.vz *= 0.99
        if ball.pos.y <= T.ballR { ball.pos.y = T.ballR; ball.vel.y = abs(ball.vel.y) > 0.6 ? abs(ball.vel.y) * 0.45 : 0; ball.vel.x *= 0.85; ball.vz *= 0.85 }
    }

    /// The ball before a serve. Old: hovering above the server. Now: ON the server's crown (skin gap 0, following the head), with a tiny settle wobble; after a point it first travels to the next
    /// server's head by a short arc (`toNext`: it starts from where it lies and is homed on the tracked head every step, so it lands on it with no jump).
    private mutating func hover(dt: Float, toNext: Bool = false) {
        guard players.indices.contains(serverIndex) else { return }
        let p = players[serverIndex]
        if VolleyTuning.old {
            ball.pos = SIMD2(p.x + Self.side(p.team) * 0.1, p.top + 0.75 + 0.06 * sinf(clock * 3))
            ball.z = p.z
            ball.vel = .zero; ball.vz = 0
            return
        }
        let nextIdx = toNext ? server * 2 + serveRot[server] : serverIndex
        guard players.indices.contains(nextIdx) else { return }
        let c = players[nextIdx].crownPoint
        let target = SIMD3(c.x, c.y + T.ballR, c.z)
        if toNext, carry == nil, !carried {
            carry = (SIMD3(ball.pos.x, ball.pos.y, ball.z), 0, Self.carryDur)
        }
        if var k = carry {
            k.t += dt
            let u = min(1, k.t / k.dur)
            let e = u * u * (3 - 2 * u)
            let dist = simd_length(SIMD2(target.x - k.from.x, target.z - k.from.z))
            let h = (0.8 + 0.12 * dist) * 4 * u * (1 - u)
            ball.pos = SIMD2(k.from.x + (target.x - k.from.x) * e, k.from.y + (target.y - k.from.y) * u + h)
            ball.z = k.from.z + (target.z - k.from.z) * e
            ball.vel = .zero; ball.vz = 0
            ball.spin += 3 * dt
            if u >= 1 { carry = nil; carried = true; restT = 0 } else { carry = k }
            return
        }
        restT += dt
        let wob = 0.014 * expf(-restT * 3.5) * 0.5 * (1 - cosf(2 * .pi * 4 * restT))          // (a settle: it only ever rises off the head, never sinks into it)
        ball.pos = SIMD2(target.x, target.y + wob)
        ball.z = target.z
        ball.vel = .zero; ball.vz = 0
    }

    /// Fires the leans: a spike-planned jump tips onto its belly once it is a little way up.
    private mutating func fireSpikes() {
        for i in players.indices where players[i].act == .jump && players[i].spikePlanned && !players[i].grounded && players[i].actT >= T.crouch + 0.10 {
            // he tips onto his belly square to the net only when the ball really is in front of that heading by now (a ball that has drifted behind him is played with the head, facing it)
            if T.facing, !ballInFront(i, at: SIMD2(xAfter(0.25), zAfter(0.25)), yaw: -Self.side(players[i].team) * .pi / 2) { players[i].spikePlanned = false; continue }
            players[i].act = .spike; players[i].actT = 0
            events.append(.spike(player: i))
        }
    }

    /// The server's jump: the human's second tap does it; with no second tap (or for a computer server) it goes at the ideal moment.
    private mutating func serveJumpTick() {}
    private mutating func serverJump() {
        guard servePending, lastHit < 0, players.indices.contains(serverIndex) else { serveMeter = nil; return }
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
                if T.hard { ball.vel.x = (ball.vel.x >= 0 ? 1 : -1) * max(abs(ball.vel.x) * 0.6, 0.7) }          // (it rolls over the tape, it is not thrown on at full speed; never slower than a roll, or it would sit on the tape)
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
        if T.hard, guardPlayer >= 0 {
            let g = players[guardPlayer]
            var near = abs(ball.z - g.z) < T.zReach + 0.2 && g.samples.contains { simd_length($0 - ball.pos) < R + 0.4 }
            if g.act == .spike, abs(ball.z - g.z) < T.zReach + 0.2, simd_length(SIMD2(g.x - Self.side(g.team) * 0.5, g.top - 0.15) - ball.pos) < 0.78 + 0.4 { near = true }          // (the leaning belly's generous zone, see `contact`)
            if !near { guardPlayer = -1 }
        }
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
        awardPoint(1 - loser, out: out)
    }

    private func wins(_ team: Int) -> Bool {
        score[team] >= T.pointsToWin
    }

    private mutating func awardPoint(_ team: Int, out: Bool) {
        guard phase == .rally else { return }
        score[team] += 1
        lastPointTeam = team
        if team != server { serveRot[team] ^= 1 }          // side out: the other server of the winning team
        server = team
        longestRally = max(longestRally, rallyHits)
        phase = .pointPause; phaseT = 0; carry = nil; carried = false
        ring = nil; serveMeter = nil; servePending = false
        events.append(.point(team: team, out: out))
        events.append(.cheer(team: team))
        ball.vel = SIMD2(ball.vel.x * 0.2, 1.4); ball.vz *= 0.2
        if wins(team) { winner = team }
    }

    /// Would this team win the match with one more point?
    private func matchPoint(_ team: Int) -> Bool {
        score[team] + 1 >= T.pointsToWin
    }

    // MARK: contact

    private mutating func contact(_ i: Int) {
        let p = players[i]
        guard phase == .rally, p.cooldown <= 0, !p.samples.isEmpty, abs(ball.z - p.z) < T.zReach else { return }
        if !VolleyTuning.old, lastHit < 0, i == serverIndex, phaseT < 0.3 { return }          // (the toss pops off the server's own crown: that is no touch)
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
        contactBall = SIMD3(ball.pos.x, ball.pos.y, ball.z)
        if T.facing, !(lastHit < 0 && i == serverIndex), !ballInFront(i, at: SIMD2(ball.pos.x, ball.z)) {          // (the server's own toss is always over his head)
            // behind his back: he has not turned to it, so it is not his ball. It rolls off him (no touch)
            turnedAway += 1
            rollOff(i, at: c)
            return
        }
        if T.hard, i == guardPlayer, lastKind != .block {
            // still inside the body it was just hit off: it rolls off him, no touch
            rollOff(i, at: c)
            return
        }
        var nrm = ball.pos - c
        let L = simd_length(nrm)
        nrm = L > 1e-4 ? nrm / L : SIMD2(0, 1)
        let rel = c.y - (T.bodyTop * 0.5 + p.lift)
        let team = p.team
        let isServe = lastHit < 0 && i == serverIndex
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
        let fresh = clock - p.tapT < 1.3
        var q: VolleyQuality = fresh ? p.tapQ : .good
        if kind == .block { q = .good }
        // the combo: a Perfect bump, set and spike in one rally
        var combo = false
        if q == .perfect, kind == .bump || kind == .dig { chain[team] = 1 }
        else if q == .perfect, kind == .set, chain[team] == 1 { chain[team] = 2 }
        else if q == .perfect, kind == .spike, chain[team] == 2 { combo = true; chain[team] = 0 }
        else if kind != .block { chain[team] = 0 }
        let v = outgoing(i, kind: kind, quality: q, combo: combo, at: c, normal: nrm)
        ball.vel = SIMD2(v.x, v.y); ball.vz = v.z
        if T.hard, team == 0, kind == .spike, unit(touchSerial, 55) < Self.digMiss(tier) { blindUntil = clock + 2.2 }
        if T.hard, team == 0, kind == .free || kind == .serve, abs(lastTgt.x) < 1.5, lastTgt.x * Self.side(1) > 0, unit(touchSerial, 33) < (params[1].read) { shortRead = (lastTgt, clock + 2.4) } else if T.hard, team == 0 { shortRead = nil }
        if T.hard, team == 0, kind != .block, lastTgt.x * Self.side(1) > 0 { humanCells.append(Self.cell(lastTgt)); if humanCells.count > 4 { humanCells.removeFirst() } }
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
        lastHit = i; lastKind = kind; guardPlayer = i
        events.append(.contact(player: i, kind: kind, quality: q, point: c, normal: nrm, speed: simd_length(v)))
        if !isServe, kind != .block { events.append(.touchCount(team: team, count: touches[team])) }
        // feedback text (for the human's team)
        if team == 0 {
            if combo { fx("Combo!", 3) }
            else if kind == .block { fx("Block!", 3) }
            else if q == .perfect { fx("Perfect!", 1) }
            else if q == .early { fx("Early", 2) }
            else if q == .late { fx("Late", 2) }
            else if kind == .spike || kind == .set { fx("Nice!", 0) }
        } else if kind == .block, team == 1 { fx("Blocked!", 2) }
        if combo { comboFlash = 1.2; events.append(.combo(team: team)) }
        // a match-point spike gets the slow beat
        if kind == .spike, matchPoint(team) { events.append(.slowMo) }
        // roll a block for the other side when a set goes up
        if kind == .set || (kind == .bump && before == 1) {
            blockWanted[1 - team] = rng.next() < params[1 - team].block
        }
        // control follows the ball after a hit by the controlled player
        if team == 0 { autoSwitchNow(reason: .touched) }
        // a fourth touch is a fault
        if kind != .block, !isServe, touches[team] > T.maxTouches {
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
        let pr = params[p.team]
        if !VolleyTuning.old, p.team == 1, pr.easy > 0, rng.next() < pr.easy {
            // an easy ball: toward the nearer of the human's two Jelmiko (it lands where he can get to it), a little short of him
            let mates = players.indices.filter { players[$0].team == 0 }
            if let m = mates.min(by: { abs(players[$0].x - 1.7 * Self.side(0)) < abs(players[$1].x - 1.7 * Self.side(0)) }) {
                let q = players[m]
                return SIMD2(max(-2.4, min(-0.9, q.x + rng.range(-0.25, 0.25))), max(-0.9, min(0.9, q.z + rng.range(-0.25, 0.25))))
            }
        }
        return openSpot(from: p.team, read: pr.read)
    }

    private mutating func outgoing(_ i: Int, kind: VolleyHit, quality q: VolleyQuality, combo: Bool, at c: SIMD2<Float>, normal n: SIMD2<Float>) -> SIMD3<Float> {
        let p = players[i]
        let s = Self.side(p.team), opp = -s
        let g = T.gravity
        let qf: Float = q == .perfect ? 0.25 : q == .good ? 1 : 1.8
        var err = (isHuman(i) ? T.aimError(timing: p.stats.timing) : (1 - p.skill) * 0.9 + 0.08) * qf
        if combo { err = 0 }
        if T.hard, p.team == 1, tier != .sandcastle {
            // the visitors above the first level pass and set to each other much more truly than they smash (the aim scatter is for the big shots; the honest misses are `mishit`)
            err *= (kind == .bump || kind == .dig || kind == .set) ? 0.40 : 0.75
        }
        let focused = T.hard && p.team == 1 && readsHabit()          // (it has seen the same placement again and again: it plays this rally tight)
        if focused { err *= 0.6 }
        var tgt: SIMD2<Float>
        var tf: Float
        var over = true
        var missed = false
        let partner: VolleyPlayer? = players.indices.contains(p.team * 2 + (1 - i % 2)) && p.team * 2 + (1 - i % 2) != i ? players[p.team * 2 + (1 - i % 2)] : nil
        let slow: Float = q == .early || q == .late ? 1.12 : 1
        do {
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
        if T.hard, kind == .bump || kind == .dig || kind == .set || kind == .free { tf *= FlightCap.passScale }          // (every pass and set is a little quicker: the rallies keep to about their old length)
        if !VolleyTuning.old, p.team == 1, !combo {
            let pr = params[1]
            if kind != .block, kind != .set { tf += pr.loft * (kind == .bump || kind == .dig ? (touches[1] >= 2 ? 1 : 0) : 1) }          // (higher and softer over the net)
            if kind == .spike, p.plan != .tip { tf *= pr.spikeFast }
            if kind == .serve { tf *= pr.serveFast }
            if kind != .block, pr.mishit > 0, rng.next() < pr.mishit * (focused ? 0.3 : 1) * (q == .perfect ? 0.3 : 1) * ((kind == .bump || kind == .dig || kind == .set) ? 0.5 : 1) {
                switch kind {
                case .serve, .spike, .free:
                    missed = true
                    if rng.next() < 0.5 { tgt = rng.next() < 0.5 ? SIMD2(opp * rng.range(3.4, 3.9), tgt.y) : SIMD2(tgt.x, (rng.next() < 0.5 ? -1 : 1) * rng.range(2.0, 2.4)) }          // long, or wide
                    else { tgt = SIMD2(opp * rng.range(0.15, 0.4), tgt.y); over = false; tf *= 0.75 }          // into the net
                case .bump, .dig, .set:
                    missed = true
                    tgt += SIMD2(rng.range(-1.7, 1.7), rng.range(-1.1, 1.1))          // a wild pass the partner cannot reach
                default: break
                }
            }
        }
        lastTgt = tgt          // (where he MEANT it to go: the habit the computer notices is the aim, not the scatter)
        tgt.x += rng.range(-1, 1) * err
        tgt.y += rng.range(-1, 1) * err * 0.7
        if q == .early || q == .late { tgt += SIMD2(rng.range(-0.35, 0.35), rng.range(-0.25, 0.25)) }
        // solve the launch for the landing spot; lift it until it clears the net when it must cross
        var vx: Float = 0, vy: Float = 0
        let lp = T.hard ? c + n * (T.ballR + 0.02) : c          // (where the ball really starts: its centre, out from the body's surface point, see `contact`)
        if T.hard, over, kind != .block {
            // a shot is only played where it can be: a ball in play lands on the court (the computer's deliberate misses aside), and a spike that cannot clear the net from where it is
            // struck goes deeper first (a steeper ball needs room), then is slowed, and last of all becomes a plain lob: never a ball pushed into the tape that pops out the far side
            let aimedOut = missed || abs(tgt.x) > T.outLine || abs(tgt.y) > T.outZ          // (a deliberate miss, or the human's own aim: left as it is)
            if !aimedOut, p.team == 1, tier != .sandcastle {          // (the computer's shots from Shore up land on the court unless it means to miss: no stray balls from the aim error)
                tgt.x = opp * min(abs(tgt.x), T.outLine - 0.45); tgt.y = max(-T.outZ + 0.45, min(T.outZ - 0.45, tgt.y))
            }
            if !aimedOut { tgt.x = opp * max(abs(tgt.x), 0.6) }
            // the net's top band: the ball must be above it (its centre over `netTop + R / 2`, with a margin) at BOTH edges of the band, the far one being the lowest for a falling ball
            let need = T.netTop + T.ballR * 0.5 + (kind == .spike ? 0.14 : 0.24)          // (a little over the band: the real ball sags under its drag)
            func clears(_ tg: SIMD2<Float>, _ f: Float) -> Bool {
                if abs(lp.x) < T.ballR + 0.02 { return true }
                let vx0 = (tg.x - lp.x) / (f * (1 - 0.5 * T.drag * f)), vy0 = (T.ballR - lp.y) / f + 0.5 * g * f
                for e: Float in [-opp * T.ballR, opp * T.ballR] {
                    let te = (e - lp.x) / vx0
                    if te <= 0 || te > f { continue }
                    if lp.y + vy0 * te - 0.5 * g * te * te < need + 0.08 * f { return false }          // (a long flight sags more under its drag)
                }
                return true
            }
            if kind == .spike, p.plan != .tip { smashCount[p.team] += 1 }
            if !clears(tgt, tf) {
                var done = false
                if !aimedOut { for k in 0..<6 { var t2 = tgt; t2.x = opp * min(abs(tgt.x) + 0.25 * Float(k + 1), T.outLine - 0.45); if clears(t2, tf) { tgt = t2; done = true; break } } }
                if !done { var f = tf; for _ in 0..<60 { f *= 1.05; if f > FlightCap.maxSmash { break }; if clears(tgt, f) { tf = f; done = true; break } } }
                if !done {
                    if kind == .spike { smashLobbed[p.team] += 1 }
                    if !aimedOut { tgt.x = opp * max(abs(tgt.x), 1.6) }
                    tf = max(tf, T.flightTime(power: p.stats.power, over: true) + 0.1)
                    for _ in 0..<6 where !clears(tgt, tf) { tf *= 1.12 }
                }
            }
        }
        if T.hard, over, kind != .block {
            vx = (tgt.x - lp.x) / (tf * (1 - 0.5 * T.drag * tf))
            vy = (T.ballR - lp.y) / tf + 0.5 * g * tf
        } else {
        for _ in 0..<8 {
            vx = (tgt.x - lp.x) / (tf * (1 - 0.5 * T.drag * tf))
            vy = (T.ballR - lp.y) / tf + 0.5 * g * tf
            if !over || abs(lp.x) < 0.02 { break }
            let tc = -lp.x / vx
            if tc <= 0 || tc > tf { break }
            let yc = lp.y + vy * tc - 0.5 * g * tc * tc
            if yc >= T.netTop + T.ballR + (kind == .spike || kind == .block ? 0.02 : 0.16) { break }
            tf *= 1.12
        }
        }
        let vz = (tgt.y - ball.z) / (tf * (1 - 0.5 * T.drag * tf))
        // off-centre hits steer a little
        if (kind == .bump || kind == .dig), q != .perfect { vx += n.x * 0.45 }
        return SIMD3(vx, vy, vz)
    }

    // MARK: facing: nobody hits a ball behind his back

    /// A ball that met a body without being hit (his back is to it, or it is still leaving him): it glances off the surface and is nudged sideways along the sand, off his body, so it falls
    /// clear instead of sliding along him.
    private mutating func rollOff(_ i: Int, at c: SIMD2<Float>) {
        let p = players[i]
        var o = ball.pos - c
        let lo = simd_length(o)
        o = lo > 1e-4 ? o / lo : SIMD2(0, 1)
        let vn = simd_dot(ball.vel, o)
        if vn < 0 { ball.vel -= 1.5 * vn * o }
        ball.pos = c + o * (T.ballR + 0.02)
        var h = SIMD2(ball.pos.x - p.x, ball.z - p.z)
        let lh = simd_length(h)
        h = lh > 1e-3 ? h / lh : SIMD2(0, 1)
        let away = ball.vel.x * h.x + ball.vz * h.y
        if lh < 0.8, away < 1.0 { ball.vel.x += h.x * (1.0 - away); ball.vz += h.y * (1.0 - away) }          // (up to a gentle 1 u/s away from him, never more)
    }

    /// The heading a team's body rests at (3/4 toward the camera, facing the net): the brain's `restYaw`.
    static func restYaw(team: Int) -> Float { -side(team) * VolleyTuning.restYaw }
    static func forward(_ yaw: Float) -> SIMD2<Float> { SIMD2(sinf(yaw), cosf(yaw)) }
    /// The heading that looks from `p` at `target` (x, z).
    static func bearing(from p: SIMD2<Float>, to target: SIMD2<Float>) -> Float { atan2f(target.x - p.x, target.y - p.y) }
    /// Is the ball in the front of this body (inside `facingHalfAngle` of where he looks), or right over him (inside `overheadRadius`, where the notion of front does not apply)?
    func ballInFront(_ i: Int, at ballXZ: SIMD2<Float>, yaw: Float? = nil) -> Bool {
        let p = players[i]
        let d = ballXZ - SIMD2(p.x, p.z)
        let l = simd_length(d)
        if l < T.overheadRadius { return true }
        let f = Self.forward(yaw ?? p.yaw ?? Self.restYaw(team: p.team))
        return simd_dot(f, d / l) >= cosf(T.facingHalfAngle)
    }
    /// The heading to jump with so the coming ball is in front of him: nil (keep the rest heading) when it already is.
    private func faceForBall(_ i: Int, landing: SIMD2<Float>?) -> Float? {
        guard T.facing, let landing else { return nil }
        let p = players[i]
        if ballInFront(i, at: landing, yaw: Self.restYaw(team: p.team)) { return nil }
        let want = Self.bearing(from: SIMD2(p.x, p.z), to: landing)
        // face it, but never past the net: the heading stays within a quarter turn of the rest heading toward the camera / net side
        return want
    }

    /// Everybody keeps his eyes on the ball while it is on his side of the net (or coming over it) and near him: he turns to it before it gets to him, and a hit never starts behind his back.
    private mutating func updateFacing() {
        guard T.facing else { return }
        for i in players.indices {
            let p = players[i]
            var goal: Float?
            let near = SIMD2(ball.pos.x - p.x, ball.z - p.z)
            if ball.pos.x * Self.side(p.team) > -0.6 || (lastHit >= 0 && players[lastHit].team != p.team && ball.vel.x * Self.side(p.team) > 0), simd_length(near) > T.overheadRadius, simd_length(near) < 3.2 {
                goal = atan2f(near.x, near.y)
            }
            players[i].faceGoal = goal
        }
    }

    /// The share of the player's smashes the computer team does not read in time, by tier (the dig rate of the harness bots is about 1 - this over the natural 0.9).
    static func digMiss(_ t: VolleyTier?) -> Float {
        #if STANDALONE
        if let v = ProcessInfo.processInfo.environment["DIGMISS"] { let a = v.split(separator: ",").compactMap { Float($0) }; if a.count == 4, let t { return a[t.index] } }
        #endif
        switch t { case .sandcastle?: return 0.60; case .shore?: return 0.30; case .reef?: return 0.15; case .tidal?: return 0.0; default: return 0 }
    }
    private var computerBlind: Bool { T.hard && clock < blindUntil }

    // MARK: the computer notices a habit

    /// The ninth of the court (x in three bands from the net, z in three) a point is in, 0...8.
    static func cell(_ p: SIMD2<Float>) -> Int {
        let ix = abs(p.x) < 1.35 ? 0 : abs(p.x) < 2.1 ? 1 : 2
        let iz = p.y < -0.45 ? 0 : p.y < 0.45 ? 1 : 2
        return ix * 3 + iz
    }
    /// The middle of ninth `c` on the computer's side.
    static func cellCentre(_ c: Int) -> SIMD2<Float> { SIMD2([Float(0.95), 1.75, 2.45][c / 3] * side(1), [Float(-0.85), 0, 0.85][c % 3]) }
    /// The ninth the human keeps using (his last two shots went there), if the computer team is the sort to notice.
    private var habitCell: Int? {
        guard T.hard, params[1].adapt > 0, humanCells.count >= 2, humanCells[humanCells.count - 1] == humanCells[humanCells.count - 2] else { return nil }
        return humanCells[humanCells.count - 1]
    }
    /// Whether this ball is one the computer is ready for: a habit it noticed, and it is paying attention (a repeatable draw per touch, see `unit`).
    private func readsHabit() -> Bool { habitCell != nil && unit(touchSerial, 77) < params[1].adapt }

    // MARK: control switching

    private enum SwitchReason { case crossed, touched }

    private mutating func autoSwitchNow(reason: SwitchReason) {
        guard players.count >= 4, autoSwitch || autoMove, clock - lastManualSwitch > 2.0 || phase == .serveWait else { return }
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
        // a body that is off the ground (a block, a jump, a dive) cannot take a step for a good while yet: the partner on his feet is nearer in time
        let busy: Float = T.hard ? (p.act == .stand && p.grounded ? 0 : max(0.3, 1.3 - p.actT)) : 0
        return simd_length(SIMD2(p.x - x, p.z - z)) / max(T.walkSpeed(p), 0.3) + busy
    }

    // MARK: the ring

    private mutating func updateRing() {
        guard players.indices.contains(controlled), controlled < players.count else { ring = nil; return }
        let p = players[controlled]
        // not while the team's three touches are spent
        if touches[p.team] >= T.maxTouches { ring = nil; return }
        guard let tm = timing(for: controlled), tm.x * Self.side(p.team) > -0.2 else { ring = nil; return }
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
            let busyA = T.hard && (players[a].act != .stand || !players[a].grounded), busyB = T.hard && (players[b].act != .stand || !players[b].grounded)          // (a body off the ground keeps nothing: his partner on his feet keeps his spot)
            let keeper = isHuman(a) && !assisted ? a : isHuman(b) && !assisted ? b : busyA != busyB ? (busyA ? b : a) : (da <= db ? a : b), mover = keeper == a ? b : a
            var w = SIMD2(players[mover].wantX, players[mover].wantZ)
            let lane = Self.side(team)          // (dead on the same spot: step back, away from the net)
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
        if simd_length(out) < 1e-3 { out = SIMD2(lane, 0) }
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
        guard phase == .rally else {
            if moveToo, phase != .rally { p.wantX = homeX; p.wantZ = homeZ }
            players[i] = p
            return
        }
        // where will the ball be when it comes down to head height (or the sand)?
        guard let tH = timeToHeight(1.55) ?? timeToHeight(T.ballR) else { players[i] = p; return }
        let landX = xAfter(tH), landZ = zAfter(tH)
        if computerBlind, team == 1, moveToo, p.act == .stand {
            // wrong-footed: it read the smash to the other side of the court and goes there; the ball comes down where nobody is
            p.wantX = s * (abs(landX) < 1.7 ? 2.4 : 1.0); p.wantZ = landZ > 0 ? -0.8 : 0.8
            players[i] = p
            return
        }
        let mine = landX * s > -0.35 && (ballOnMySide(team) || ball.vel.x * s > 0.3 || lastHit < 0)
        if servePending, i == serverIndex {          // the server waits under his toss
            players[i] = p
            return
        }
        guard mine else {
            // the ball is with the others: be ready, and put up a block against a set
            p.wait = pr.react + pr.reactSpread * unit(touchSerial, i)
            if team == 1, readsHabit() { p.wait = 0 }
            aiBlock(&p, i: i, pr: pr)
            if moveToo, p.act == .stand {
                let blocking = blockWanted[team] && touches[1 - team] >= 2 && abs(p.x) < 2.2 && (players.indices.contains(team * 2 + 1) ? abs(p.x) <= abs(players[team * 2 + (i % 2 == 0 ? 1 : 0)].x) : true)
                if !blocking {
                    // the partner (the human too) is front or back: take the other job, and stagger across the court
                    let mate = players.indices.contains(team * 2 + (i % 2 == 0 ? 1 : 0)) ? players[team * 2 + (i % 2 == 0 ? 1 : 0)] : nil
                    var hx = homeX, hz = homeZ + max(-0.5, min(0.5, ball.z * 0.3))
                    if let mate { hx = abs(mate.x) < 1.7 ? backX : frontX; hz = max(-0.9, min(0.9, -mate.z * 0.6 + ball.z * 0.2)) }
                    p.wantX = hx; p.wantZ = hz
                    if T.hard, team == 1, let sr = shortRead, clock < sr.until, players.indices.contains(team * 2 + 1) {
                        let a = team * 2, b = a + 1
                        let nearer = simd_distance(SIMD2(players[a].x, players[a].z), sr.spot) <= simd_distance(SIMD2(players[b].x, players[b].z), sr.spot) ? a : b
                        if i == nearer { p.wantX = max(T.netMargin + 0.15, sr.spot.x * s * s); p.wantZ = max(-T.zLimit, min(T.zLimit, sr.spot.y)); p.wait = 0 }
                    }
                    if T.hard, team == 1, touches[0] >= 2, lastHit >= 0, players[lastHit].team == 0, players.indices.contains(team * 2 + 1), unit(touchSerial, 91) < pr.read {
                        // the human team has set the ball up: the nearer defender goes to the emptiest part of the court (where a smash would go), and the other keeps the rest
                        let spot = openSpot(from: 0, read: 0)
                        let a = team * 2, b = a + 1
                        let nearer = simd_distance(SIMD2(players[a].x, players[a].z), spot) <= simd_distance(SIMD2(players[b].x, players[b].z), spot) ? a : b
                        if i == nearer { p.wantX = spot.x; p.wantZ = spot.y }
                    }
                    if team == 1, readsHabit(), let hc = habitCell, players.indices.contains(team * 2 + 1) {
                        // one defender (the nearer) goes to wait where the last two balls went
                        let ctr = Self.cellCentre(hc)
                        let a = team * 2, b = a + 1
                        let nearer = simd_distance(SIMD2(players[a].x, players[a].z), ctr) <= simd_distance(SIMD2(players[b].x, players[b].z), ctr) ? a : b
                        if i == nearer { p.wantX = ctr.x; p.wantZ = ctr.y }
                    }
                }
            }
            players[i] = p
            return
        }
        var d = designated(team: team, landX: landX, landZ: landZ)
        if !VolleyTuning.old, team == 1, pr.sticky {
            // the stronger teams settle who takes the ball at the touch and keep to it (no two players dithering over who goes)
            if desigSerial[team] == touchSerial { d = desigFor[team] } else { desigSerial[team] = touchSerial; desigFor[team] = d }
        }
        let t0 = touches[team]
        if d == i {
            let apex = T.apex(hops: p.stats.hops)
            let lead = T.crouch + 0.5 * T.airTime(apex: apex)
            let hitH = T.bodyTop + apex * 0.9 + 0.3
            // a lower-tier player misjudges the landing now and then (a miss that is the ball's fault, never an impossible save)
            if p.readSerial != touchSerial {
                p.readSerial = touchSerial
                let slip = pr.slip ?? (1 - pr.read) * 1.0
                p.readErr = (rng.next() - 0.5) * 2 * slip
                if rng.next() < 0.5 { p.readErr *= 0.3 }
                if team == 1, readsHabit() { p.readErr *= 0.15 }
                if T.hard, team == 1, tier != .sandcastle, lastHit >= 0, players[lastHit].team == team { p.readErr *= 0.2 }          // (the pass of his own partner: he knows where it is going)
            }
            var tx = landX + p.readErr
            if t0 >= 2 { tx = landX + s * 0.45 + p.readErr }
            if moveToo {
                p.wait = max(0, p.wait - dt)
                if computerBlind, team == 1 { p.wait = max(p.wait, blindUntil - clock) }
                if p.wait <= 0 { p.wantX = tx; p.wantZ = landZ }
            }
            // a teammate calls for it
            if team == 0, !isHuman(i), p.calledSerial != touchSerial, tH < 2.4, lastHit >= 0 || tH < 1.6 {
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
                if let tL = timeToHeight(T.ballR + 0.3), tL < 0.62, tL > 0.25, abs(landX - p.x) > 0.45, abs(landX - p.x) < T.diveReach, abs(landZ - p.z) < (T.hard && team == 1 ? 0.7 + 0.25 * pr.read : 0.7), ball.vel.y < 0.5, !(computerBlind && team == 1), !T.hard || (ball.pos.x * s > -0.3 && !(landX * s < p.x * s && abs(p.x) - T.netMargin < 0.25)),          // (never a dive at a ball that is between him and the net: the body would be turned away from it)
                   
                   !T.facing || ballInFront(i, at: SIMD2(landX, landZ), yaw: landX > p.x ? .pi / 2 : -.pi / 2) {
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

    // MARK: sync from the bodies

    mutating func setBody(_ i: Int, x: Float, z: Float = 0, lift: Float, top: Float, grounded: Bool, yaw: Float? = nil) {
        guard players.indices.contains(i) else { return }
        if let yaw { players[i].yaw = yaw }
        players[i].vx = (x - players[i].x) / (1.0 / 60); players[i].vz = (z - players[i].z) / (1.0 / 60)
        players[i].x = x; players[i].z = z; players[i].lift = lift; players[i].top = top; players[i].grounded = grounded
    }
    /// Puts the ball on the server's head now (the fade-in frames, before the match steps).
    mutating func placeBallOnHead() { if ballOnHead { hover(dt: 0) } }
    /// The glue says where the top of the head (or of the hat) is.
    mutating func setCrown(_ i: Int, _ c: SIMD3<Float>) { if players.indices.contains(i) { players[i].crown = c } }
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
