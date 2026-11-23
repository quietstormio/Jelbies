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
    static let holdTime: Float = 0.9
    static let rollOutStop: Float = 0.9
    /// A goal's longest hold (the roll-out is forced after it).
    static let holdMax: Float = 3.0
    /// The Jelmiko's line stays this far from the mouth, at least.
    static let minLineGap: Float = 1.6
    /// How many seconds a celebration waits for a busy Jelmiko before it is given up.
    static let cheerWait: Float = 3.0
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
            guard !n.contains(stand, margin: 0.35), abs(stand.x) < Self.bodyReach(stand.y), Self.bodyZ().contains(stand.y) else { continue }
            if jellies.contains(where: { $0.id != ignoring && simd_distance($0.pos, stand) < 0.9 }) { continue }
            return (stand, u)
        }
        return nil
    }

    // MARK: start / end / each step

    /// Play started with the net: it is placed (or not: no room) once the line is known. `blockers` = bodies that stay where they are (sleepers).
    func netStart(blockers: [SIMD2<Float>]) {
        net = PlayNetState()
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
        net = PlayNetState()
        netUp = false
    }

    /// The view was turned: the net's place is worked out again for the new frame (the line has new spots).
    func netReframe() {
        guard netUp, net.hold == nil else { return }
        if let c = netPlacement(blockers: net.blockers) { if net.spec?.centre != c { net.spec = TossNet(centre: c) } }
    }

    /// Every step while the game is on: the cheers that are waiting for a free Jelmiko.
    func netTick(dt: Float) {
        guard !net.pending.isEmpty else { return }
        for (id, p) in net.pending {
            guard let j = jellies.first(where: { $0.id == id }) else { net.pending[id] = nil; continue }
            if netCelebrate(j, scorer: p.scorer) || clock > p.until { net.pending[id] = nil }
        }
    }

    /// A Jelmiko touched the ball (header / kick): he is the one who scores if it goes in.
    func netNoteToucher(_ id: Int) { if netUp { net.lastToucher = id } }
    /// A new throw / a rescue lob: nobody has touched it since.
    func netThrowReset() { if netUp { net.lastToucher = nil; net.hold = nil; ball.inNet = false; resetShot() } }
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
            phase = .loose; looseT = 0; restT = 0; returnAim = nil; bumper = nil; passTo = nil
            for j in jellies where j.brain.tossHeaderApproach { j.brain.tossHeaderRelease(j.sim, j.skinner) }
            DecorField.shared.kick(PlayNetTuning.uid, min(1, 0.4 + speed / 3.4))
            onEvent?(.goal(scorer: scorer))
            celebrateGoal(scorer: scorer)
            net.onGoal?(scorer)
            NSLog("[playnet] goal speed=%.2f scorer=%@", speed, scorer.map(String.init) ?? "none")
        case .post(let s):
            if net.first == nil { net.first = "post" }
            onEvent?(.netHit(speed: s))
        case .bar(let s):
            if net.first == nil { net.first = "bar" }
            onEvent?(.netHit(speed: s))
        case .lid:
            if net.first == nil { net.first = "over" }
        }
    }

    /// While the net holds the ball after a goal: the controller's loose-ball logic waits (nobody goes to kick a ball lying in the net); after `holdTime` the ball rolls out to
    /// 0.9 in front of the mouth, where the game's normal handling sends it back. True = the rest of this step is skipped.
    func netHoldTick(dt: Float) -> Bool {
        guard var h = net.hold, let n = net.spec else { return false }
        h.t += dt
        if !h.rolled, h.t >= PlayNetTuning.holdTime {
            h.rolled = true
            ball.inNet = false
            let out = n.rollOutSpot(from: SIMD2(ball.pos.x, ball.pos.z))
            var d = out - SIMD2(ball.pos.x, ball.pos.z)
            let L = simd_length(d)
            d = L > 1e-3 ? d / L : SIMD2(0, 1)
            let sp = min(L * TossTuning.rollDecayPerS + TossTuning.stopSpeed, 2.6)
            ball.vel = SIMD3(d.x * sp, 0, d.y * sp)
            ball.pos.y = max(ball.pos.y, ball.radius)
        }
        // out of the mouth (or given up): the normal handling takes over
        if h.rolled, ball.pos.z > n.mouthZ + ball.radius + 0.1 || h.t > PlayNetTuning.holdMax {
            if h.t > PlayNetTuning.holdMax, ball.pos.z <= n.mouthZ { ball.pos = SIMD3(n.rollOutSpot(from: SIMD2(ball.pos.x, ball.pos.z)).x, ball.radius, n.mouthZ + PlayNetTuning.rollOutStop); ball.vel = .zero }
            net.hold = nil
            phase = .loose; looseT = 0; restT = 0
            return false
        }
        net.hold = h
        phase = .loose; looseT = 0; restT = 0          // (frozen while it is in the net)
        return true
    }

    // MARK: the celebration

    /// A goal: the scorer (if a Jelmiko kicked it) does the 3-rep bounce, every other Jelmiko on the line cheers, each where he stands. A goal from the player's own throw makes all of
    /// them cheer. Each starts as soon as his body is free (a Jelmiko still in his header or bump finishes it first), within `cheerWait`.
    func celebrateGoal(scorer: Int?) {
        for j in jellies where !j.free {
            let sc = scorer == j.id
            if !netCelebrate(j, scorer: sc) { net.pending[j.id] = (sc, clock + PlayNetTuning.cheerWait) }
        }
    }

    /// Starts one Jelmiko's cheer the way the ball game starts its own motions (`commanded`, as `tossHeaderStart` does: in Play the Jelmiko are held). False = his body is busy.
    private func netCelebrate(_ j: PlayJelly, scorer: Bool) -> Bool {
        let b = j.brain
        guard b.idleState.kind == nil, !b.isSleeping, !b.isNapping, !b.feet.active else { return false }
        if case .none = b.script {} else { b.abortAll(j.sim, j.skinner) }
        if scorer {
            guard b.idleStart(.bounce, j.sim) else { return false }
            b.commanded = true
            b.idleState.reps = 3
            b.face(.excited, hold: 1.4); b.blushBump(hold: 2.6, peak: 0.75)
        } else {
            guard b.idleStart(.joy, j.sim) else { return false }
            b.commanded = true
            b.face(.excited, hold: 1.1); b.blushBump(hold: 2.4, peak: 0.7)
        }
        return true
    }
}
