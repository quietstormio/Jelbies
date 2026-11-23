//
//  PlayNet.swift
//  The soccer NET of Play mode (owner 2026-11-23: "make the indoor soccer really good ... it gets better with a net as well, put the net in the toy selector ... they can
//  play with or without net"). A temporary mini goal, drawn 1.6 times its size at the back of the play area, mouth toward the player:
//    TossNet          the net as the ball sees it (pure data): the posts and side nets, the back, the crossbar, the open mouth, the lid. `resolve` runs inside `TossBall.sub`.
//    PlayNetPlacement where it stands (clear of the furniture, inside the visible back row, never nearer than 1.6 to the line), pure and tested.
//    PlayToss+Net     the controller's side: the net's state, the goal (the ball is held in the net, a puff, the roll-out), the celebration, and the API for the Jelmiko's
//                     shots (`netUp`, `netMouth`, `shotAim`, `shotSpot`, `onNetGoal`).
//  Nothing here is saved: the piece reaches `DecorField` through `GameCare.syncDecor` (a fixed negative uid) only while `PlayToss.netUp`, so every way out of Play removes it.
//  With the net not up (`TossWorld.net == nil`, `PlayToss.netUp == false`) none of this runs.
//

import Foundation
import simd

nonisolated enum PlayNetTuning {
    /// The mini goal's size in Play: a goal the size of a Jelmiko (2.6 wide, about 1.4 tall).
    static let scale: Float = 1.6
    /// The piece's uid in `DecorField` (the park's fixed uids are -70xx too: this one is free).
    static let uid = -7101
    /// The crossbar in the model (decor_minigoal.bin: the frame's top is 0.915; its tube about 0.03 thick, along the front edge z 0.335): the ball goes under 0.855.
    static let barUnder: Float = 0.855, barTop: Float = 0.915, barRadius: Float = 0.03, barZ: Float = 0.335
    /// A ball bounces off the posts, the side nets and the back softly; off the bar a little livelier.
    static let netRestitution: Float = 0.35, barRestitution: Float = 0.45
    /// Inside the net the ball's speed dies (per second): it is caught against the back.
    static let netDrag: Float = 4.5
    /// After a goal: the ball lies in the net this long, then rolls out to this far in front of the mouth.
    static let holdTime: Float = 0.9          // (the old short roll-out's hold; `returnsToPlayer` false)
    /// Round 3: the ball is held while the cheer runs: at least this long, until every cheer has ended, at most `holdCheerMax`.
    static let holdCheer: Float = 1.6, holdCheerMax: Float = 2.6
    static let rollOutStop: Float = 0.9
    /// A goal's longest hold (the roll-out is forced after it).
    static let holdMax: Float = 3.0
    /// The Jelmiko's line stays this far from the mouth, at least.
    static let minLineGap: Float = 1.6
    /// How many seconds a celebration waits for a busy Jelmiko before it is given up.
    static let cheerWait: Float = 3.0
    /// Keep-out round: no body is sent into the goal's footprint plus this margin; a stand there is moved to this far in front of the mouth line.
    static let keepOutMargin: Float = 0.35, standFront: Float = 0.6
    /// A ball at rest, or on its second floor contact, in the keep-out or up to this far in front of the mouth line (anywhere across the floor) without having scored is returned by the net (no cheer).
    static let deadFront: Float = 0.85
}

nonisolated enum TossNetEvent: Equatable, Sendable {
    case goal(speed: Float), post(speed: Float), bar(speed: Float), lid
}

/// The net as the ball sees it, in world coordinates (the piece faces the player: yaw 0).
nonisolated struct TossNet: Equatable, Sendable {
    var centre: SIMD2<Float>
    var k: Float = PlayNetTuning.scale

    var mouthZ: Float { centre.y + GoalGeometry.mouthZ * k }
    var innerHalf: Float { GoalGeometry.mouthHalfWidth * k }
    var outerHalf: Float { GoalGeometry.outerHalfX * k }
    var frontZ: Float { centre.y + GoalGeometry.frontZ * k }
    var rearZ: Float { centre.y + GoalGeometry.rearZ * k }
    /// The height under the bar, and the top of the frame.
    var barBottom: Float { PlayNetTuning.barUnder * k }
    var barTop: Float { PlayNetTuning.barTop * k }
    var rodR: Float { PlayNetTuning.barRadius * k }
    /// The crossbar's tube in (z, y).
    var rod: SIMD2<Float> { SIMD2(centre.y + PlayNetTuning.barZ * k, (PlayNetTuning.barTop - PlayNetTuning.barRadius) * k) }
    /// The solid boxes (xz): the two posts with their side nets, and the back.
    var boxes: [(c: SIMD2<Float>, half: SIMD2<Float>)] {
        GoalGeometry.solids.map { (SIMD2(centre.x + $0.centre.x * k, centre.y + $0.centre.y * k), $0.half * k) }
    }
    /// Where the ball comes to rest after a goal: 0.9 in front of the mouth on its line (kept off the posts).
    func rollOutSpot(from p: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(centre.x + max(-0.5 * k, min(0.5 * k, p.x - centre.x)), mouthZ + PlayNetTuning.rollOutStop)
    }
    /// A world point inside the footprint (the frame's outline).
    func contains(_ p: SIMD2<Float>, margin: Float = 0) -> Bool {
        abs(p.x - centre.x) < outerHalf + margin && p.y > rearZ - margin && p.y < frontZ + margin
    }

    /// One physics sub-step's collisions with the net (`before` = where the ball was at the start of it): the posts, side nets and back (soft), the crossbar, the lid
    /// (a ball that comes down onto the net rolls off its front), the goal (the ball crossed the mouth going in under the bar, between the posts) and the drag inside.
    func resolve(_ b: inout TossBall, before: SIMD3<Float>, h: Float, _ ev: inout [TossEvent]) {
        let r = b.radius
        let e = PlayNetTuning.netRestitution
        if b.inNet { let kd = expf(-PlayNetTuning.netDrag * h); b.vel.x *= kd; b.vel.z *= kd }
        // the lid: a ball that comes down onto the frame's top rolls off the front (never rests up there)
        if !b.inNet, contains(SIMD2(b.pos.x, b.pos.z)), b.vel.y < 0, before.y - r >= barTop - 0.02, b.pos.y - r < barTop {
            b.pos.y = barTop + r
            let vy = -b.vel.y
            b.vel.y = vy > 0.5 ? vy * e : 0
            b.vel.z = max(b.vel.z, 1.2)
            ev.append(.net(.lid))
        }
        // the posts and side nets and the back
        if b.pos.y - r < barTop {
            for (i, bx) in boxes.enumerated() {
                let box = RoomLayout.FlatBox(centre: bx.c, half: bx.half, height: 1, radius: 0.02)
                let p = SIMD2(b.pos.x, b.pos.z)
                let d = RoomLayout.boxDistanceXZ(p, box)
                guard d < r else { continue }
                let eps: Float = 1e-3
                let g = SIMD2(RoomLayout.boxDistanceXZ(p + SIMD2(eps, 0), box) - RoomLayout.boxDistanceXZ(p - SIMD2(eps, 0), box),
                              RoomLayout.boxDistanceXZ(p + SIMD2(0, eps), box) - RoomLayout.boxDistanceXZ(p - SIMD2(0, eps), box))
                let n = simd_length(g) > 1e-6 ? simd_normalize(g) : SIMD2<Float>(0, 1)
                b.pos.x += n.x * (r - d); b.pos.z += n.y * (r - d)
                let vn = b.vel.x * n.x + b.vel.z * n.y
                if vn < 0 {
                    b.vel.x -= n.x * vn * (1 + e); b.vel.z -= n.y * vn * (1 + e)
                    if i < 2, !b.inNet, -vn > 0.8 { ev.append(.net(.post(speed: -vn))) }
                }
            }
        }
        // the crossbar: a tube along the mouth's top between the posts
        if !b.inNet, abs(b.pos.x - centre.x) < innerHalf + 0.05 {
            let dz = b.pos.z - rod.x, dy = b.pos.y - rod.y
            let d = (dz * dz + dy * dy).squareRoot()
            if d < r + rodR, d > 1e-5 {
                let n = SIMD2(dz, dy) / d
                b.pos.z += n.x * (r + rodR - d); b.pos.y += n.y * (r + rodR - d)
                let vn = b.vel.z * n.x + b.vel.y * n.y
                if vn < 0 {
                    let f = 1 + PlayNetTuning.barRestitution
                    b.vel.z -= n.x * vn * f; b.vel.y -= n.y * vn * f
                    if -vn > 0.8 { ev.append(.net(.bar(speed: -vn))) }
                }
            }
        }
        // the goal: the centre crosses the mouth plane going in, between the posts, with the whole ball under the bar
        if !b.inNet, before.z >= mouthZ, b.pos.z < mouthZ, b.vel.z < 0 {
            let t = (before.z - mouthZ) / max(before.z - b.pos.z, 1e-6)
            let xAt = before.x + (b.pos.x - before.x) * t - centre.x, yAt = before.y + (b.pos.y - before.y) * t
            if abs(xAt) < innerHalf - r + 0.02, yAt + r < barBottom + 0.02 {
                b.inNet = true
                ev.append(.net(.goal(speed: simd_length(b.vel))))
            }
        }
    }
}

// MARK: - where it stands

nonisolated enum PlayNetPlacement {
    /// The net's centre, or nil when there is no room. Starts with the back of the net at `zBack` and x 0; if the footprint is not clear it slides along x to the nearest clear
    /// spot inside the visible back row (`reach(z)` = the half width there); none: forward in steps of 0.3, the mouth never nearer than `minLineGap` to `lineZ`.
    /// `blocked(p)` = a solid piece / the sofa / a body is at world point p.
    static func place(zBack: Float, lineZ: Float, reach: (Float) -> Float, blocked: (SIMD2<Float>) -> Bool) -> SIMD2<Float>? {
        let k = PlayNetTuning.scale
        let z0 = zBack - GoalGeometry.backZ * k
        var dz: Float = 0
        while true {
            let cz = z0 + dz
            let probe = TossNet(centre: SIMD2(0, cz))
            guard probe.mouthZ <= lineZ - PlayNetTuning.minLineGap + 1e-4 else { return nil }
            let maxSlide = max(0, min(reach(probe.rearZ), reach(probe.frontZ)) - probe.outerHalf)
            var cands: [Float] = [0]
            var s: Float = 0.1
            while s <= maxSlide + 1e-4 { cands.append(s); cands.append(-s); s += 0.1 }
            for cx in cands where fits(TossNet(centre: SIMD2(cx, cz)), reach: reach, blocked: blocked) { return SIMD2(cx, cz) }
            dz += 0.3
        }
    }

    /// Is the whole outline inside the visible row and clear of everything?
    static func fits(_ n: TossNet, reach: (Float) -> Float, blocked: (SIMD2<Float>) -> Bool) -> Bool {
        for z in [n.rearZ, n.frontZ] where reach(z) < abs(n.centre.x) + n.outerHalf { return false }
        var x = n.centre.x - n.outerHalf
        while x <= n.centre.x + n.outerHalf + 1e-4 {
            var z = n.rearZ
            while z <= n.frontZ + 1e-4 {
                if blocked(SIMD2(x, z)) { return false }
                z += 0.12
            }
            if blocked(SIMD2(x, n.frontZ)) { return false }
            x += 0.12
        }
        return true
    }
}

// MARK: - the controller's side

/// What the controller keeps about the net (owned by `PlayToss.net`).
struct PlayNetState {
    var spec: TossNet?
    struct Hold { var t: Float = 0; var rolled = false; var scorer: Int? }
    var hold: Hold?
    /// The last Jelmiko who headed or kicked the ball since the throw (nil = nobody: the player's own throw).
    var lastToucher: Int?
    /// Who still has to start a cheer: id -> (does the 3-rep bounce, give-up time).
    var pending: [Int: (scorer: Bool, until: Float)] = [:]
    /// Round 3: after a goal the net sends the ball back to the player (a roll through the widest gap on the line, or a low lob); false = the old short roll-out 0.9 in front of the mouth, handed back as a loose ball (for goals scored inside the Jelmiko's own shooting game). Survives start / end.
    var returnsToPlayer = true
    var cheering: Set<Int> = []
    var cheerStart: [Int: Float] = [:]
    var returning = false
    var retT: Float = 0
    var goalPos: [Int: SIMD2<Float>] = [:]
    var nearLogged: Set<Int> = []
    var rescuesAtGoal = 0
    /// When the last goal was scored (the clock), the next sample of the cheer log, and when a body in the net was last logged.
    var goalAt: Float = -99
    var sampleAt: Float = 0
    var bodyLogT: [Int: Float] = [:]
    var awaitHand = false
    /// Keep-out round: the closest any body came to the footprint (0 = inside), the ball's floor contacts inside the dead zone, and the dead returns.
    var minBodyDist: Float = 99
    var floorHits = 0, prevVy: Float = 0, deadReturns = 0
    var goals = 0
    /// Bodies that stay where they are while the net is up (sleepers): the net is placed clear of them.
    var blockers: [SIMD2<Float>] = []
    var rng: UInt64 = 0x2545F4914F6CDD1D
    /// The goal callback (the Jelmiko's shot logic and the tests): who scored (nil = the player's throw).
    var onGoal: ((Int?) -> Void)?
    /// Capture / test aid: what the first collider did since `resetShot`.
    var first: String?
    var over = false
    var log: [String] = []
}

extension PlayToss {
    // MARK: keep-out (no body in the goal; the net returns what lands in it)

    /// play-net keep-out: the goal's footprint plus `keepOutMargin` (the posts, the mouth, and everything behind the mouth line back to the wall). False without the net.
    func netKeepOut(_ p: SIMD2<Float>) -> Bool {
        guard netUp, let n = net.spec else { return false }
        return abs(p.x - n.centre.x) < n.outerHalf + PlayNetTuning.keepOutMargin && p.y < n.frontZ + PlayNetTuning.keepOutMargin
    }

    /// play-net keep-out: a stand / walk target in the keep-out is moved to the nearest spot outside: in front of the mouth (at least `standFront` from the mouth line), or to the side when that is nearer.
    func netStand(_ p: SIMD2<Float>) -> SIMD2<Float> {
        guard netKeepOut(p), let n = net.spec else { return p }
        let fwd = SIMD2(p.x, n.mouthZ + PlayNetTuning.standFront)
        let edge = n.outerHalf + PlayNetTuning.keepOutMargin + 0.05
        let side = SIMD2(n.centre.x + (p.x >= n.centre.x ? edge : -edge), p.y)
        if p.y >= n.rearZ, abs(side.x - p.x) < fwd.y - p.y, abs(side.x) < Self.bodyReach(side.y) { return side }
        return fwd
    }

    /// Distance from the goal's footprint to a point on the floor (0 inside).
    func netDistance(_ p: SIMD2<Float>) -> Float {
        guard let n = net.spec else { return 99 }
        let dx = max(abs(p.x - n.centre.x) - n.outerHalf, 0), dz = max(n.rearZ - p.y, p.y - n.frontZ, 0)
        return (dx * dx + dz * dz).squareRoot()
    }

    /// play-net keep-out: a ball that has not scored but lies in the goal's footprint (over the bar and down the back, off a post into the side, rolled in from the side) and comes to rest or touches the floor a second
    /// time there is returned by the net exactly as after a goal (no cheer, no goal sound): put inside the mouth, held no longer than the cheer's minimum, then the roll / lob to the player.
    func netDeadTick() {
        guard let n = net.spec, net.hold == nil, !net.returning, phase == .loose || phase == .flying else { net.floorHits = 0; net.prevVy = 0; return }
        let p = SIMD2(ball.pos.x, ball.pos.z)
        guard p.y < n.mouthZ + PlayNetTuning.deadFront else { net.floorHits = 0; net.prevVy = ball.vel.y; return }          // (the keep-out and the strip in front of it a stand cannot serve from behind, and the pockets beside / behind the goal)
        if ball.pos.y < ball.radius + 0.08, net.prevVy < -0.4, ball.vel.y > 0 { net.floorHits += 1 }          // (a real floor bounce, not only a settled ball)
        net.prevVy = ball.vel.y
        guard ball.pos.y < ball.radius + 0.08, net.floorHits >= 2 || (ball.onFloor && ball.speedXZ < 0.3) else { return }
        net.floorHits = 0; net.prevVy = 0; net.deadReturns += 1
        net.goalAt = clock; net.awaitHand = true; net.rescuesAtGoal = rescues
        phase = .loose; looseT = 0; restT = 0; returnAim = nil; bumper = nil
        for j in jellies {          // (nobody fetches a ball from there: a body in his own kick / header plan or on a walk to it is stopped, as at a goal; one in the air lands first)
            let b = j.brain
            if b.tossHeaderApproach { b.tossHeaderRelease(j.sim, j.skinner) }
            if (b.idleState.kind == .tossBump || b.idleState.kind == .tossHeader), !b.tossAirborne(j.sim) { b.abortAll(j.sim, j.skinner); b.tossFaceYaw = nil; b.tossFire = nil; b.tossFireReady = nil }
            else if b.idleState.kind == nil, !b.isSleeping, !b.isNapping { if case .none = b.script {} else { b.abortAll(j.sim, j.skinner) } }
        }
        netClearFoot()
        if n.contains(p) {          // inside the frame (over the bar and down into it, a side net): the net rolls / lobs it out of the mouth exactly as after a goal, no cheer
            let at = SIMD2(min(max(p.x, n.centre.x - 0.5 * n.k), n.centre.x + 0.5 * n.k), min(p.y, n.mouthZ - 0.3))
            ball.pos = SIMD3(at.x, ball.radius, at.y); ball.vel = .zero; ball.inNet = true
            net.hold = .init(t: PlayNetTuning.holdCheer, rolled: false, scorer: nil)
            NSLog("[playnet] return reason=dead (in the frame) from %.2f,%.2f", p.x, p.y)
        } else {          // beside / in front of / behind the goal where nobody may stand: the same lob to the catch zone, from where it lies (the safety lob), no walk to the ball
            NSLog("[playnet] return reason=dead (beside or in front) from %.2f,%.2f", p.x, p.y)
            netDeadLob()
        }
    }

    // MARK: the API for the shots

    /// The net's mouth: its centre on the floor line, and the clear half width between the posts.
    var netMouth: SIMD2<Float>? { net.spec.map { SIMD2($0.centre.x, $0.mouthZ) } }
    var netCentre: SIMD2<Float>? { net.spec?.centre }
    var netInnerHalfWidth: Float? { net.spec?.innerHalf }
    var netSpec: TossNet? { net.spec }

    private func netRand() -> Float {
        net.rng ^= net.rng << 13; net.rng ^= net.rng >> 7; net.rng ^= net.rng << 17
        return Float(net.rng >> 40) / Float(1 << 24)
    }
    func netSeed(_ s: UInt64) { net.rng = s | 1 }

    /// A point on the mouth line to shoot at. `spread` (0...1) is how much of the mouth's half width the aim wanders over; a quarter of the shots are aimed just wide of a post
    /// on purpose (as the room's shots are). A zero point when there is no net.
    func shotAim(spread: Float) -> SIMD2<Float> {
        guard let n = net.spec else { return .zero }
        let s = min(max(spread, 0), 1)
        if netRand() < 0.25 {
            let side: Float = netRand() < 0.5 ? -1 : 1
            return SIMD2(n.centre.x + side * (n.innerHalf + 0.08 + 0.2 * netRand()), n.mouthZ)
        }
        return SIMD2(n.centre.x + (netRand() * 2 - 1) * n.innerHalf * 0.85 * s, n.mouthZ)
    }

    /// Where a Jelmiko stands to shoot with the ball at `ball`: `SoccerTuning.standBack` behind it on the line to the mouth (the ball between him and the net), his `dir` the
    /// shot's direction. Nil when the ball is not in front of the net, or no stand is clear (never inside the net, off the floor, or on another Jelmiko; `ignoring` = the shooter).
    func shotSpot(ball: SIMD2<Float>, ignoring: Int? = nil) -> (stand: SIMD2<Float>, dir: SIMD2<Float>)? {
        guard let n = net.spec, ball.y > n.mouthZ + 0.25 else { return nil }
        let aim = SIMD2(min(max(ball.x, n.centre.x - n.innerHalf * 0.5), n.centre.x + n.innerHalf * 0.5), n.mouthZ)
        let d = aim - ball
        let L = simd_length(d)
        guard L > 1e-3 else { return nil }
        let base = d / L
        let back = SoccerTuning.standBack
        for a in [Float(0), 0.35, -0.35, 0.7, -0.7] {
            let c = cosf(a), s = sinf(a)
            let u = SIMD2(base.x * c - base.y * s, base.x * s + base.y * c)
            let stand = ball - u * back
            guard !n.contains(stand, margin: 0.35), !netKeepOut(stand), abs(stand.x) < Self.bodyReach(stand.y), Self.bodyZ().contains(stand.y) else { continue }
            if jellies.contains(where: { $0.id != ignoring && simd_distance($0.pos, stand) < 0.9 }) { continue }
            return (stand, u)
        }
        return nil
    }

    // MARK: start / end / each step

    /// Play started with the net: it is placed (or not: no room) once the line is known. `blockers` = bodies that stay where they are (sleepers).
    func netStart(blockers: [SIMD2<Float>]) {
        let cb = net.onGoal, rtp = net.returnsToPlayer          // (a goal callback and the return mode registered once survive every game)
        net = PlayNetState()
        net.onGoal = cb; net.returnsToPlayer = rtp
        net.blockers = blockers
        netUp = false
        if let c = netPlacement(blockers: blockers) {
            net.spec = TossNet(centre: c); netUp = true
        } else {
            GameMessageCenter.shared.post("No room for the net here", identifier: "play-net-none")
        }
    }

    /// The net's place now (nil = none): clear of the placed furniture, the sofa, the room's posts and the sleepers.
    func netPlacement(blockers: [SIMD2<Float>]) -> SIMD2<Float>? {
        let solids = DecorField.shared.feet.filter { $0.spec.solid && $0.kind != .minigoal }
        let cyl = RoomLayout.cylinders
        let line = jellies.filter { !$0.free }
        let lineZ = line.isEmpty ? Float.greatestFiniteMagnitude : (spots.values.map(\.y).min() ?? line.map { $0.pos.y }.min() ?? 0)
        return PlayNetPlacement.place(zBack: TossTuning.zBack, lineZ: lineZ, reach: { Self.ballReach($0) }, blocked: { p in
            if RoomLayout.sofaDistanceXZ(p) < 0.04 { return true }
            for f in solids where f.distance(p) < 0.04 { return true }
            for c in cyl where simd_distance(p, c.centre) < c.radius + 0.04 { return true }
            for b in blockers where simd_distance(p, b) < TossTuning.bodyRadius { return true }
            return false
        })
    }

    /// Play ended (Done or any way out): the net and everything it was doing are gone.
    func netEnd() {
        let cb = net.onGoal, rtp = net.returnsToPlayer
        for j in jellies { j.brain.cheerFaceYaw = nil }
        net = PlayNetState()
        net.onGoal = cb; net.returnsToPlayer = rtp
        netUp = false
    }

    /// The view was turned: the net's place is worked out again for the new frame (the line has new spots).
    func netReframe() {
        guard netUp, net.hold == nil else { return }
        if let c = netPlacement(blockers: net.blockers) { if net.spec?.centre != c { net.spec = TossNet(centre: c) } }
    }

    /// Every step while the game is on: the cheers that are waiting for a free (or a turned) Jelmiko, the cheer log, and a Jelmiko inside the net (logged).
    func netTick(dt: Float) {
        guard netUp else { return }
        if net.returning, phase == .catching || phase == .inHand { net.returning = false; NSLog("[playnet] return caught %@ t=%.1f", rescues > net.rescuesAtGoal ? "AFTER RESCUE" : "at the hand", net.retT) }
        if net.awaitHand, phase == .inHand { net.awaitHand = false; NSLog("[playnet] goal-to-hand %.1f s", clock - net.goalAt) }
        for (id, p) in net.pending {
            guard let j = jellies.first(where: { $0.id == id }) else { net.pending[id] = nil; continue }
            if netCelebrate(j, scorer: p.scorer) { net.pending[id] = nil }
            else if clock > p.until { net.pending[id] = nil; NSLog("[playnet] cheer id=%d started=0 kind=none reason=gave-up idle=%@ script=%@ feet=%d", id, String(describing: j.brain.idleState.kind), String(describing: j.brain.script), j.brain.feet.active ? 1 : 0) }
        }
        for id in net.cheering {          // (a cheer's end: the body is released from the turn-to-the-player heading; a cheer cut short is logged)
            guard let j = jellies.first(where: { $0.id == id }) else { net.cheering.remove(id); continue }
            if j.brain.idleState.kind != .joy, j.brain.idleState.kind != .bounce {
                let dur = clock - (net.cheerStart[id] ?? clock)
                j.brain.cheerFaceYaw = nil; net.cheering.remove(id)
                NSLog("[playnet] cheer-end id=%d dur=%.2f%@", id, dur, dur < 1.0 ? " CUT SHORT" : "")
            }
        }
        if clock - net.goalAt < 5, let n = net.spec {          // (nobody walks to the net after a goal)
            let m = SIMD2(n.centre.x, n.mouthZ)
            for j in jellies where !j.free && !net.nearLogged.contains(j.id) {
                if let p0 = net.goalPos[j.id], simd_distance(p0, m) - simd_distance(j.pos, m) > 0.35 { net.nearLogged.insert(j.id); NSLog("[playnet] BODY WALKED TOWARD NET id=%d from %.2f,%.2f to %.2f,%.2f", j.id, p0.x, p0.y, j.pos.x, j.pos.y) }
            }
        }
        netDeadTick()          // (play-net keep-out)
        for j in jellies where !j.free {          // (the closest any body came to the footprint: the keep-out's proof)
            let d = netDistance(j.pos)
            if d < net.minBodyDist - 0.03 { net.minBodyDist = d; NSLog("[playnet] closest body to the footprint: %.2f (id %d at %.2f,%.2f) clock=%.1f", d, j.id, j.pos.x, j.pos.y, clock) }
        }
        if let n = net.spec {
            for j in jellies where n.contains(j.pos, margin: 0.1) { if clock - (net.bodyLogT[j.id] ?? -9) > 1 { net.bodyLogT[j.id] = clock; NSLog("[playnet] BODY IN NET id=%d at %.2f,%.2f", j.id, j.pos.x, j.pos.y) } }
        }
        #if targetEnvironment(simulator)
        if DevArgs.enabled, clock - net.goalAt < 2.2, clock >= net.sampleAt {
            net.sampleAt = clock + 0.2
            for j in jellies where !j.free { NSLog("[playnet] cheerstate t=+%.1f id=%d idle=%@ lift=%.2f facing=%.0f", clock - net.goalAt, j.id, String(describing: j.brain.idleState.kind), j.sim.centroid().y - j.sim.restCentroid.y, netFacing(j)) }
        }
        #endif
    }
    /// The angle (degrees) between where he looks and the player.
    func netFacing(_ j: PlayJelly) -> Float {
        // (what the eye sees: the soft body's own heading; in a hop the attractor's, as `touchLog` reads it)
        let af = j.sim.attractor.rotation.act(SIMD3<Float>(0, 0, 1))
        let vy = j.brain.idleState.kind == nil ? j.brain.yaw : atan2f(af.x, af.z)
        return abs(wrapAngle(j.brain.yawTo(playerPoint()) - vy)) * 180 / .pi
    }

    /// A Jelmiko touched the ball (header / kick): he is the one who scores if it goes in.
    func netNoteToucher(_ id: Int) { if netUp { net.lastToucher = id } }
    /// A new throw / a rescue lob: nobody has touched it since.
    func netThrowReset() { if netUp { net.lastToucher = nil; net.hold = nil; net.returning = false; ball.inNet = false; resetShot() } }
    func resetShot() { net.first = nil; net.over = false }

    // MARK: the ball and the net

    /// A collider event from the ball's step (`live`).
    func netEvent(_ n: TossNetEvent) {
        switch n {
        case .goal(let speed):
            net.goals += 1
            if net.first == nil { net.first = "goal" }
            let scorer = touched ? net.lastToucher : nil
            net.hold = .init(t: 0, rolled: false, scorer: scorer)
            net.goalAt = clock; net.sampleAt = clock; net.awaitHand = true
            net.cheering = []; net.cheerStart = [:]; net.nearLogged = []; net.returning = false
            net.goalPos = Dictionary(uniqueKeysWithValues: jellies.map { ($0.id, $0.pos) })
            phase = .loose; looseT = 0; restT = 0; returnAim = nil; bumper = nil; passTo = nil
            for j in jellies where j.brain.tossHeaderApproach { j.brain.tossHeaderRelease(j.sim, j.skinner) }
            netClearFoot()
            DecorField.shared.kick(PlayNetTuning.uid, min(1, 0.4 + speed / 3.4))
            onEvent?(.goal(scorer: scorer))
            celebrateGoal(scorer: scorer)
            net.onGoal?(scorer)
            NSLog("[playnet] goal speed=%.2f scorer=%@", speed, scorer.map(String.init) ?? "none")
        case .post(let s):
            NSLog("[playnet] net hit post speed=%.1f", s)
            if net.first == nil { net.first = "post" }
            onEvent?(.netHit(speed: s))
        case .bar(let s):
            NSLog("[playnet] net hit bar speed=%.1f", s)
            if net.first == nil { net.first = "bar" }
            onEvent?(.netHit(speed: s))
        case .lid:
            if net.first == nil { net.first = "over" }
        }
    }

    /// While the net holds the ball after a goal the controller's loose-ball logic waits and nobody goes for it. `returnsToPlayer` (the default): the ball is held while the cheer runs (at least
    /// `holdCheer`, until every cheer has ended, at most `holdCheerMax`), then the net sends it back to the player (`netReturnLaunch`). False: after `holdTime` it rolls out to 0.9 in front
    /// of the mouth and is handed back as a loose ball (the old behaviour). True = the rest of this step is skipped.
    func netHoldTick(dt: Float) -> Bool {
        guard var h = net.hold, let n = net.spec else { return false }
        h.t += dt
        let toPlayer = net.returnsToPlayer
        let cheersOn = !net.pending.isEmpty || jellies.contains { net.cheering.contains($0.id) && ($0.brain.idleState.kind == .joy || $0.brain.idleState.kind == .bounce) }
        let ready = toPlayer ? (h.t >= PlayNetTuning.holdCheer && !cheersOn || h.t >= PlayNetTuning.holdCheerMax) : h.t >= PlayNetTuning.holdTime
        if !h.rolled, ready, ball.pos.y <= ball.radius + 0.05 || h.t >= (toPlayer ? PlayNetTuning.holdCheerMax : PlayNetTuning.holdTime) + 0.9 {          // (a ball still bouncing in the net waits to lie on the floor)
            if toPlayer {
                if netReturnLaunch(n) { net.hold = nil; return false }
                NSLog("[playnet] return blocked: the old short roll-out")          // (a body stands right in front of the mouth: no way past him; the ball comes out 0.9 and the loose-ball handling has it)
            }
            h.rolled = true
            ball.inNet = false
            let out = n.rollOutSpot(from: SIMD2(ball.pos.x, ball.pos.z))
            var d = out - SIMD2(ball.pos.x, ball.pos.z)
            let L = simd_length(d)
            d = L > 1e-3 ? d / L : SIMD2(0, 1)
            let sp = min(max(L * TossTuning.rollDecayPerS + 0.35, 1.0), 2.6)
            ball.vel = SIMD3(d.x * sp, 0, d.y * sp)
            ball.pos.y = max(ball.pos.y, ball.radius)
        }
        // out of the mouth (or given up): the normal handling takes over
        if h.rolled, ball.pos.z > n.mouthZ + ball.radius + 0.1 || h.t > PlayNetTuning.holdMax + 2 {
            if h.t > PlayNetTuning.holdMax + 2 { NSLog("[playnet] hold forced out") }
            if h.t > PlayNetTuning.holdMax + 2, ball.pos.z <= n.mouthZ { ball.pos = SIMD3(n.rollOutSpot(from: SIMD2(ball.pos.x, ball.pos.z)).x, ball.radius, n.mouthZ + PlayNetTuning.rollOutStop); ball.vel = .zero }
            net.hold = nil
            phase = .loose; looseT = 0; restT = 0
            return false
        }
        net.hold = h
        phase = .loose; looseT = 0; restT = 0          // (frozen while it is in the net)
        return true
    }

    // MARK: the net gives the ball back

    /// The ball leaves the net toward the player's catch zone (the target `rescue()` uses): rolled firmly along the floor through the widest gap between the bodies on the line (a gap needs
    /// a ball's width plus 0.3 clear), else a low lob over the line (as the rescue lob clears shoulders). It is then a normal return flight: `phase` .flying, `returnAim` set, `touched`, so
    /// `caught()` fires at the hand.
    private func netReturnLaunch(_ n: TossNet) -> Bool {
        let r = ball.radius
        let hand = handWorld()
        let tz = catchZ() + 0.6
        let lim = Self.ballReach(tz) - 0.9
        let target = SIMD2<Float>(min(max(hand.x * 0.5, -lim), lim), tz)
        let S = SIMD2(ball.pos.x, ball.pos.z)
        let bodies = jellies.filter { !$0.free }.map(\.pos)
        func clearance(_ T: SIMD2<Float>) -> Float {
            let d = T - S, L2 = max(simd_dot(d, d), 1e-6)
            var c = Float.infinity
            for b in bodies { let t = min(max(simd_dot(b - S, d) / L2, 0), 1); c = min(c, simd_distance(S + d * t, b) - (TossTuning.bodyRadius + r)) }
            return c
        }
        func exitsMouth(_ T: SIMD2<Float>) -> Bool {
            let d = T - S
            guard d.y > 1e-3, S.y < n.mouthZ else { return true }
            let x = S.x + d.x * ((n.mouthZ - S.y) / d.y)
            return abs(x - n.centre.x) < n.innerHalf - r - 0.05
        }
        var best: (T: SIMD2<Float>, c: Float)?, any: (T: SIMD2<Float>, c: Float)?
        var x = -lim
        while x <= lim + 1e-4 {
            let T = SIMD2<Float>(x, tz)
            if exitsMouth(T) {
                let c = clearance(T)
                if any == nil || c > any!.c + 0.05 || (abs(c - any!.c) <= 0.05 && abs(x - target.x) < abs(any!.T.x - target.x)) { any = (T, c) }
                if c >= 0.15, best == nil || c > best!.c + 0.05 || (abs(c - best!.c) <= 0.05 && abs(x - target.x) < abs(best!.T.x - target.x)) { best = (T, c) }
            }
            x += 0.1
        }
        ball.inNet = false; ball.ignoring = nil
        ball.pos.y = max(ball.pos.y, r + 0.02)
        let g = TossTuning.gravity, y0 = ball.pos.y
        // the lob's rise: the smallest from a list that goes under the bar at the mouth and over every head on the way (nil = none does: a body stands right in front of the net)
        func lobPlan(_ T: SIMD2<Float>) -> (vy: Float, flight: Float)? {
            let L = simd_length(T - S)
            guard L > 1e-3, S.y < n.mouthZ - 0.4 || S.y > n.mouthZ else { return nil }          // (a ball lying on the mouth line would meet the bar going up)
            let dir = (T - S) / L
            for vy in stride(from: Float(4.0), through: 7.5, by: 0.5) {
                let flight = (vy + (vy * vy + 2 * g * max(y0 - r, 0)).squareRoot()) / g
                let hs = L / flight
                var ok = true
                var sD: Float = 0
                while sD <= L, ok {
                    let q = S + dir * sD, t = sD / hs, y = y0 + vy * t - 0.5 * g * t * t
                    if S.y < n.mouthZ, abs(q.y - (n.mouthZ + 0.04)) < 0.1, y + r > n.barBottom - 0.12 { ok = false }          // (the bar)
                    for b in bodies where simd_distance(q, b) < TossTuning.bodyRadius + r + 0.1 && y - r < TossTuning.bodyTop + 0.1 { ok = false }          // (a head)
                    sD += 0.05
                }
                if ok { return (vy, flight) }
            }
            return nil
        }
        func roll(_ b: (T: SIMD2<Float>, c: Float), _ tag: String) -> String {
            let d = b.T - S, D = simd_length(d)
            let v0 = min(D * TossTuning.rollDecayPerS + 1.6, 11)          // (it arrives still rolling at about 1.6)
            ball.vel = SIMD3(d.x / D * v0, 0, d.y / D * v0)
            returnAim = b.T
            return String(format: "%@ gap=%.2f", tag, b.c)
        }
        let mode: String
        if let b = best {
            mode = roll(b, "roll")
        } else {
            var T = target
            if !exitsMouth(T) { T.x = n.centre.x }
            if let lp = lobPlan(T) {
                ball.vel = SIMD3((T.x - S.x) / lp.flight, lp.vy, (T.y - S.y) / lp.flight)
                returnAim = T
                mode = String(format: "lob vy=%.1f", lp.vy)
            } else if let b = any, b.c >= -0.25 {
                mode = roll(b, "roll-squeeze")          // (a body close in front of the net: through the least tight way, a soft brush at worst)
            } else {
                return false          // (a body right in front of the mouth: no return; the old short roll-out)
            }
        }
        touched = true
        phase = .flying; looseT = 0; restT = 0
        net.returning = true; net.retT = 0; net.rescuesAtGoal = rescues
        NSLog("[playnet] return %@ from %.2f,%.2f speed %.1f", mode, S.x, S.y, simd_length(ball.vel))
        return true
    }

    /// While the net's return is on the ball stays a flying return (a roll along the floor would otherwise turn into a loose ball the Jelmiko go to fetch) until `caught()` takes it.
    func netReturnTick(dt: Float) {
        guard net.returning else { return }
        net.retT += dt
        if phase == .catching || phase == .inHand || phase == .off { net.returning = false; NSLog("[playnet] return caught %@ t=%.1f", rescues > net.rescuesAtGoal ? "AFTER RESCUE" : "at the hand", net.retT); return }
        if net.retT > 7 || (ball.onFloor && ball.speedXZ < 0.3 && net.retT > 0.6) { net.returning = false; phase = .loose; looseT = 0; NSLog("[playnet] return ended without a catch t=%.1f at %.2f,%.2f", net.retT, ball.pos.x, ball.pos.z); return }
        phase = .flying
    }

    // MARK: the celebration

    /// A goal: EVERY Jelmiko on the line cheers, facing the player (the audience), with the joy bounce, the excited face and the blush: the scorer (if a Jelmiko kicked it) the bigger 3-rep bounce,
    /// the others 2 reps; a goal from the player's own throw is cheered by all. The cheer starts at once (a walker is given 0.2 s to land a step, one in his own kick / header is stopped; a header
    /// jump in the air lands first) and its hops turn the body toward the player in the air (`cheerFaceYaw`). The ball is held in the net until the cheers have ended. Gives up after `cheerWait`, logged.
    func celebrateGoal(scorer: Int?) {
        for j in jellies where !j.free {
            let sc = scorer == j.id
            if !netCelebrate(j, scorer: sc) { net.pending[j.id] = (sc, net.pending[j.id]?.until ?? clock + PlayNetTuning.cheerWait) }
        }
    }

    /// Starts one Jelmiko's cheer the way the ball game starts its own motions (`commanded`, as `tossHeaderStart` does: in Play the Jelmiko are held). False = not yet.
    private func netCelebrate(_ j: PlayJelly, scorer: Bool) -> Bool {
        let b = j.brain
        guard !b.isSleeping, !b.isNapping else { return false }
        if b.idleState.kind == .tossBump || b.idleState.kind == .tossHeader {          // (his own kick / header plan: the ball is in the net, there is nothing to kick)
            if b.tossAirborne(j.sim) { return false }
            b.abortAll(j.sim, j.skinner); b.tossFaceYaw = nil; b.tossFire = nil; b.tossFireReady = nil
        }
        guard b.idleState.kind == nil else { return false }
        if b.feet.active, clock - net.goalAt < 0.2 { return false }
        if case .none = b.script {} else { b.abortAll(j.sim, j.skinner) }
        let was = netFacing(j)
        b.cheerFaceYaw = b.yawTo(playerPoint())
        let started: Bool
        if scorer {
            started = b.idleStart(.bounce, j.sim)
            if started { b.commanded = true; b.idleState.reps = 3; b.face(.excited, hold: 2.2); b.blushBump(hold: 3.0, peak: 0.8) }
        } else {
            started = b.idleStart(.joy, j.sim)
            if started { b.commanded = true; b.idleState.reps = 2; b.face(.excited, hold: 1.8); b.blushBump(hold: 2.8, peak: 0.7) }
        }
        if started { net.cheering.insert(j.id); net.cheerStart[j.id] = clock } else { b.cheerFaceYaw = nil }
        NSLog("[playnet] cheer id=%d started=%d kind=%@ facing=%.0f was=%.0f dt=%.2f", j.id, started ? 1 : 0, scorer ? "bounce3" : "joy2", netFacing(j), was, clock - net.goalAt)
        return started
    }
}
