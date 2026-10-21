//
//  DecorField+Soccer.swift
//  The soccer ball's physics and the goal, on the decor field (Room/DecorModel.swift):
//    roll      decays by e^-1.15 t (soccerball.json), stops below 0.05 u/s; sub-stepped so no step moves it more than a third of its radius (no tunnelling),
//              then pushed out of every obstacle: the room's floor edges and walls (restitution 0.6), the sofa and the room's cylinders, every solid piece's footprint,
//              the goal's posts / side nets / back net (the mouth is open), and the Jellies (a gentle bump; never the kicker's own toe as the ball leaves it).
//    goal      a crossing of the mouth plane going in scores once (`SoccerEvents.goal`); the ball runs into the net, the net puffs (`kick` on the goal piece,
//              rendered as the bulge), and the ball rolls gently back out to about 0.6 in front of the goal. A pass just outside a post is a near miss.
//    stuck     at rest against a wall, in a corner or under furniture for 20 s the ball is "stuck": the Jellies' scheduler favours a rescue dribble
//              (BlobBrain+Soccer.swift); at 28 s a boundary nudge rolls it toward open floor whatever they do.
//  All of it is deterministic given the field (no randomness here: the kicks' spread is the kicker's).
//

import Foundation
import simd

/// The soccer round's bookkeeping across the pieces: rest / stuck timers per ball, the goals scored, what each kick has already reported.
@MainActor
final class SoccerState {
    static let shared = SoccerState()
    /// Seconds a ball has rested in a stuck spot (by uid).
    private(set) var stuckT: [Int: Float] = [:]
    /// Goals scored since launch / `reset()`, and the last one (ball uid, goal uid, scorer, the field's clock when it happened).
    private(set) var goals = 0
    private(set) var lastGoal: (ball: Int, goal: Int, scorer: Int, at: Float)?
    /// The field's clock (seconds of `tick`).
    private(set) var clock: Float = 0
    /// Per ball: the Jellies this kick has already rolled past, and whether this kick's near miss was reported.
    private var passed: [Int: Set<Int>] = [:]
    private var missNoted: Set<Int> = []
    /// A ball met the back of a net this step (ball uid -> goal uid, the speed it arrived with): the field puffs the net. `inNet`: it has met the net and not left the mouth yet.
    private var netHits: [Int: (goal: Int, speed: Float)] = [:]
    private(set) var inNet: Set<Int> = []
    nonisolated deinit {}

    func reset() { stuckT = [:]; goals = 0; lastGoal = nil; clock = 0; passed = [:]; missNoted = []; netHits = [:]; inNet = [] }
    func noteNetHit(ball: Int, goal: Int, speed: Float) { if netHits[ball] == nil, !inNet.contains(ball) { netHits[ball] = (goal, speed) }; inNet.insert(ball) }
    func takeNetHit(_ ball: Int) -> (goal: Int, speed: Float)? { let h = netHits[ball]; netHits[ball] = nil; return h }
    func leftNet(_ ball: Int) { inNet.remove(ball) }
    func advance(_ dt: Float) { clock += dt }
    /// A ball has rested in a stuck spot for `SoccerTuning.stuckAfter`.
    func isStuck(_ uid: Int) -> Bool { (stuckT[uid] ?? 0) >= SoccerTuning.stuckAfter }
    var anyStuck: Bool { stuckT.values.contains { $0 >= SoccerTuning.stuckAfter } }
    func setStuck(_ uid: Int, _ t: Float) { if t <= 0 { stuckT[uid] = nil } else { stuckT[uid] = t } }
    func newKick(_ uid: Int) { passed[uid] = []; missNoted.remove(uid) }
    func notePass(_ uid: Int, jelly: Int) -> Bool { if passed[uid, default: []].contains(jelly) { return false }; passed[uid, default: []].insert(jelly); return true }
    func noteMiss(_ uid: Int) -> Bool { if missNoted.contains(uid) { return false }; missNoted.insert(uid); return true }
    func scored(ball: Int, goal: Int, scorer: Int) { goals += 1; lastGoal = (ball, goal, scorer, clock) }
}

extension DecorField {
    /// The goal pieces in the room.
    var goals: [DecorFoot] { feet.filter { $0.kind == .minigoal } }
    /// The soccer balls in the room.
    var soccerBalls: [DecorFoot] { feet.filter { $0.kind == .soccerball } }
    /// A stuck soccer ball (at rest in a corner / against a wall / under furniture for 20 s), nearest `p` first.
    func stuckBall(near p: SIMD2<Float> = .zero) -> DecorFoot? {
        soccerBalls.filter { SoccerState.shared.isStuck($0.uid) && occupant[$0.uid] == nil && $0.uid != held }.min { simd_distance(position($0), p) < simd_distance(position($1), p) }
    }
    /// Piece-local coordinates of a world point for a goal (the goals are not rotated: a translation).
    func goalLocal(_ g: DecorFoot, _ p: SIMD2<Float>) -> SIMD2<Float> { p - g.centre }
    /// A goal's kick spots in the world: the ball's spot, the stand, the aim (the mouth's centre).
    func kickSpots(_ g: DecorFoot) -> [(ball: SIMD2<Float>, stand: SIMD2<Float>, aim: SIMD2<Float>)] {
        GoalGeometry.kickSpots.map { (g.centre + $0.ball, g.centre + $0.stand, g.centre + $0.aim) }
    }
    /// The world point the ball comes to rest at after a goal (0.6 in front of the mouth, on the ball's line).
    func rollOutSpot(_ g: DecorFoot, x: Float) -> SIMD2<Float> { SIMD2(g.centre.x + max(-0.5, min(0.5, x - g.centre.x)), g.centre.y + GoalGeometry.mouthZ + SoccerTuning.rollOutStop) }

    // MARK: the roll

    /// The floor the ball may roll on (as `roll`): the visible floor between the walls.
    static func soccerFloor(z: Float) -> (zlo: Float, zhi: Float, xlim: Float) {
        let zlo: Float = -2.4, zhi: Float = max(3.0, GameCamera.roamFloor?.maxZ ?? 3.0)
        return (zlo, zhi, DecorPlacement.visibleHalf(z: z) - SoccerTuning.radius)
    }

    /// One step of the soccer ball (called from `tick` while it moves).
    static func rollSoccer(_ a: inout DecorAnim, dt: Float, uid: Int, feet: [DecorFoot], bodies: [(id: Int, pos: SIMD2<Float>)]) {
        let r = SoccerTuning.radius
        a.kickAge += dt
        a.vel *= expf(-SoccerTuning.linearDecayPerS * dt)
        let speed = simd_length(a.vel)
        if speed < SoccerTuning.stopSpeed { a.vel = .zero; return }
        // sub-steps: never more than a third of the radius per move
        let n = max(1, Int((speed * dt / SoccerTuning.maxSubStep).rounded(.up)))
        let h = dt / Float(n)
        let start = a.pos
        for _ in 0..<n {
            let before = a.pos, vBefore = a.vel
            var p = a.pos + a.vel * h
            collide(&p, &a, r: r, uid: uid, feet: feet, bodies: bodies)
            // met the back of the net: the net puffs (the field reads it in `soccerRestTick`)
            if a.inGoal >= 0, let g = feet.first(where: { $0.uid == a.inGoal }), vBefore.y < -0.2, a.vel.y >= 0, (p - g.centre).y < GoalGeometry.backZ + r + 0.03 {
                SoccerState.shared.noteNetHit(ball: uid, goal: g.uid, speed: simd_length(vBefore))
            }
            // the goal: a crossing of a mouth plane going in scores; the net stops the ball and sends it gently back out
            for g in feet where g.kind == .minigoal {
                let lb = before - g.centre, la = p - g.centre
                if a.inGoal == g.uid {
                    if la.y > GoalGeometry.mouthZ + r { a.inGoal = -1; SoccerState.shared.leftNet(uid) }          // rolled back out of the mouth
                    continue
                }
                guard lb.y >= GoalGeometry.mouthZ, la.y < GoalGeometry.mouthZ, a.vel.y < 0 else { continue }
                let t = (lb.y - GoalGeometry.mouthZ) / max(lb.y - la.y, 1e-6)
                let xAt = lb.x + (la.x - lb.x) * t
                if abs(xAt) < GoalGeometry.mouthHalfWidth - r {
                    a.inGoal = g.uid
                    SoccerState.shared.scored(ball: uid, goal: g.uid, scorer: a.kicker)
                    SoccerEvents.emit(.goal(scorer: a.kicker, goal: g.uid))
                } else if abs(xAt) < GoalGeometry.outerHalfX + 0.6, SoccerState.shared.noteMiss(uid) {
                    SoccerEvents.emit(.nearMiss(jelly: a.kicker, goal: g.uid))
                }
            }
            a.pos = p
            if simd_length_squared(a.vel) < SoccerTuning.stopSpeed * SoccerTuning.stopSpeed { a.vel = .zero; break }
        }
        // rolled past a Jelly (not the kicker's own, not one it bumped)
        for b in bodies where b.id != a.kicker || a.kickAge > 1.5 {
            if simd_distance(a.pos, b.pos) < SoccerTuning.bodyRadius + r + 0.35, SoccerState.shared.notePass(uid, jelly: b.id) { SoccerEvents.emit(.rolledPast(jelly: b.id, kicker: a.kicker)) }
        }
        // the roll angle
        let step = a.pos - start
        let dist = simd_length(step)
        if dist > 1e-6 {
            let dir = step / dist
            a.rot = simd_normalize(simd_quatf(angle: dist / r, axis: SIMD3<Float>(dir.y, 0, -dir.x)) * a.rot)
        }
    }

    /// Pushes `p` out of everything the ball may not enter and reflects the velocity's normal part with the surface's restitution.
    private static func collide(_ p: inout SIMD2<Float>, _ a: inout DecorAnim, r: Float, uid: Int, feet: [DecorFoot], bodies: [(id: Int, pos: SIMD2<Float>)]) {
        func bounce(_ sd: Float, _ grad: SIMD2<Float>, e: Float) {
            guard sd < r else { return }
            let n = simd_length(grad) > 1e-6 ? simd_normalize(grad) : SIMD2<Float>(0, 1)
            p += n * (r - sd)
            let vn = simd_dot(a.vel, n)
            if vn < 0 { a.vel -= n * vn * (1 + e) }
        }
        let eps: Float = 1e-3
        func grad(_ f: (SIMD2<Float>) -> Float) -> SIMD2<Float> { SIMD2(f(p + SIMD2(eps, 0)) - f(p - SIMD2(eps, 0)), f(p + SIMD2(0, eps)) - f(p - SIMD2(0, eps))) }
        // the floor's edges and the walls
        let fl = soccerFloor(z: p.y)
        let eW = SoccerTuning.wallRestitution
        if p.y < fl.zlo + r { p.y = fl.zlo + r; if a.vel.y < 0 { a.vel.y = -a.vel.y * eW } }
        if p.y > fl.zhi - r { p.y = fl.zhi - r; if a.vel.y > 0 { a.vel.y = -a.vel.y * eW } }
        let lim = DecorPlacement.visibleHalf(z: p.y) - r
        if p.x < -lim { p.x = -lim; if a.vel.x < 0 { a.vel.x = -a.vel.x * eW } }
        if p.x > lim { p.x = lim; if a.vel.x > 0 { a.vel.x = -a.vel.x * eW } }
        // the sofa, the room's cylinders, the solid pieces (the goal by its own parts: the mouth is open)
        let eF = SoccerTuning.furnitureRestitution
        bounce(RoomLayout.sofaDistanceXZ(p), grad(RoomLayout.sofaDistanceXZ), e: eF)
        for c in RoomLayout.cylinders {
            let d = p - c.centre, len = simd_length(d)
            bounce(len - c.radius, len > 1e-6 ? d / len : SIMD2(0, 1), e: eF)
        }
        for c in feet where c.uid != uid && c.spec.solid {
            if c.kind == .minigoal {
                for s in GoalGeometry.solids {
                    let box = RoomLayout.FlatBox(centre: c.centre + s.centre, half: s.half, height: 1, radius: 0.02)
                    bounce(RoomLayout.boxDistanceXZ(p, box), grad { RoomLayout.boxDistanceXZ($0, box) }, e: 0.35)
                }
                continue
            }
            bounce(c.distance(p), grad { c.distance($0) }, e: eF)
        }
        // the Jellies: a gentle bump (not the kicker while the ball leaves his toe)
        for b in bodies where b.id != a.kicker || a.kickAge > 0.6 {
            let d = p - b.pos, len = simd_length(d)
            bounce(len - SoccerTuning.bodyRadius, len > 1e-6 ? d / len : SIMD2(0, 1), e: SoccerTuning.bodyRestitution)
        }
    }

    // MARK: at rest: in the net, stuck

    /// Every step for a soccer ball (moving or not): the roll-out after a goal, the stuck timer and the fallback nudge.
    func soccerRestTick(_ uid: Int, dt: Float) {
        guard var a = anim[uid], let f = foot(uid) else { return }
        if let hit = SoccerState.shared.takeNetHit(uid) { kick(hit.goal, min(1, 0.4 + hit.speed / 3.4)) }          // the net bulges with the shot's pace
        // it has met the net and lost its pace (or a soft one stopped in the mouth): it drops and rolls gently back out, to about 0.6 in front of the mouth
        let speed = simd_length(a.vel)
        if a.inGoal >= 0, let g = foot(a.inGoal), (SoccerState.shared.inNet.contains(uid) && speed < 0.9) || speed < SoccerTuning.stopSpeed, goalLocal(g, a.pos).y < GoalGeometry.mouthZ - 0.05 {
            let out = rollOutSpot(g, x: a.pos.x)
            let d = out - a.pos, L = simd_length(d)
            if L > 0.05 {
                // v / decay = distance (plus the little it loses under the stop speed): it stops right there
                a.vel = d / L * min(L * SoccerTuning.linearDecayPerS + SoccerTuning.stopSpeed, 1.6)
                a.kickAge = 0.61          // (the scorer may be bumped by it on the way out: it is not his kick any more)
                SoccerState.shared.leftNet(uid)
                setAnim(uid, a)
                return
            }
        }
        if a.moving { SoccerState.shared.setStuck(uid, 0); return }
        // at rest: against a wall / in a corner / under or against furniture?
        let p = a.pos, r = SoccerTuning.radius
        let fl = Self.soccerFloor(z: p.y)
        var stuck = p.y < fl.zlo + r + 0.06 || p.y > fl.zhi - r - 0.06 || abs(p.x) > fl.xlim - 0.06
        if !stuck { for c in feet where c.uid != uid && c.spec.solid && c.kind != .minigoal && c.distance(p) < r + 0.08 { stuck = true; break } }
        if !stuck, RoomLayout.sofaDistanceXZ(p) < r + 0.08 { stuck = true }
        if !stuck, a.inGoal >= 0 { stuck = true }          // (left in the net: it is retrieved like a ball under a table)
        guard stuck, held != uid else { SoccerState.shared.setStuck(uid, 0); return }
        let t = (SoccerState.shared.stuckT[uid] ?? 0) + dt
        SoccerState.shared.setStuck(uid, t)
        if t >= SoccerTuning.nudgeAfter, occupant[uid] == nil {
            // the fallback: a soft roll to the nearest open floor (not into the piece it is wedged against)
            let open = nearestOpenFloor(to: p) ?? SIMD2<Float>(0, 0.6)
            var d = open - p; let L = simd_length(d); d = L > 1e-3 ? d / L : SIMD2(0, 1)
            kickBall(uid, direction: d, speed: min(max(L * SoccerTuning.linearDecayPerS + SoccerTuning.stopSpeed, 0.8), 1.6))
            SoccerState.shared.setStuck(uid, 0)
            SoccerState.shared.newKick(uid)
        }
        _ = f
    }

    /// Is a world point open floor for the ball (`margin` clear of the walls, the sofa, every solid piece and the room's cylinders)?
    func openFloor(_ p: SIMD2<Float>, margin: Float = 0.3) -> Bool {
        let r = SoccerTuning.radius
        let fl = Self.soccerFloor(z: p.y)
        guard p.y > fl.zlo + r + margin, p.y < fl.zhi - r - margin, abs(p.x) < fl.xlim - margin else { return false }
        if RoomLayout.sofaDistanceXZ(p) < r + margin { return false }
        for c in feet where c.spec.solid && c.distance(p) < r + margin { return false }
        for c in RoomLayout.cylinders where simd_distance(p, c.centre) < c.radius + r + margin { return false }
        return true
    }
    /// Can the ball roll straight from `a` to `b` (sampled every 0.15, from a little way out: it may start wedged against the very thing it leaves)?
    func clearRoll(from a: SIMD2<Float>, to b: SIMD2<Float>) -> Bool {
        let L = simd_distance(a, b)
        guard L > 1e-3 else { return true }
        var s: Float = 0.3
        while s < L { if !openFloor(a + (b - a) * (s / L), margin: 0.02) { return false }; s += 0.15 }
        return true
    }
    /// The nearest open-floor spot to `p` the ball can roll straight to, with room to spare (0.5 clear), searched outward and leaning toward the middle of the floor (nil = none within 4 u).
    func nearestOpenFloor(to p: SIMD2<Float>, toward centre: SIMD2<Float> = SIMD2(0, 0.6)) -> SIMD2<Float>? {
        var best: (SIMD2<Float>, Float)?
        var d: Float = 0.5
        while d <= 4 {
            for k in 0..<16 {
                let a = Float(k) / 16 * 2 * .pi
                let q = p + SIMD2(sinf(a), cosf(a)) * d
                if openFloor(q, margin: 0.5), clearRoll(from: p, to: q) {
                    let cost = d + 0.35 * simd_distance(q, centre)
                    if best == nil || cost < best!.1 { best = (q, cost) }
                }
            }
            if best != nil { return best!.0 }
            d += 0.3
        }
        return nil
    }
}
