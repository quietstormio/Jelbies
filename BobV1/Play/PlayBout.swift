//
//  PlayBout.swift
//  The beach ball bounced between the Jelmiko (beach-volley-r1; owner 2026-11-23: "they play bouncing the beach ball back and forth together standing wherever in the room").
//  Beach ball only, two or three Jelmiko awake. About 6 throws in 10 start a BOUT: the first header goes to another Jelmiko instead of the player, and they keep it up between them from wherever
//  they stand: each steps under the ball when it comes to him, the aim varies a little so they move, bodies stay 1.3 apart, they face the one the ball is coming from. With three it goes round all three
//  (the next header prefers the one who has touched it least in this bout). It ends when the ball touches the floor (a small "oops" from the one who missed, no point), after 12 touches (the last header
//  goes to the player) or on "Pass it back" (the next touch goes to the player). Every strike still goes through `header(by:)` and the ball's own physics: the wish "to him" is produced BY the strike.
//  The numbers are pure functions in `BoutMath` (tests call them); the `PlayToss` extension is the controller's glue.
//

import Foundation
import simd

nonisolated enum BoutMath {
    /// The most touches in one bout; after them the last header goes to the player. One header in this many is aimed out of reach (the ball comes down).
    nonisolated(unsafe) static var touchCap = 12
    nonisolated(unsafe) static var missEvery: Float = 6
    /// A spot nobody else stands nearer than this to (bodies keep apart).
    static let keepAway: Float = 1.75

    /// A spot `0.6...1.2` from where the receiver stands (`miss`: 2.2...2.8, out of reach), inside the floor, at least `keepAway` from everybody else.
    static func pickFree(near c: SIMD2<Float>, keepOff: [SIMD2<Float>], miss: Bool, reach: (Float) -> Float, zlo: Float, zhi: Float, rnd: () -> Float) -> SIMD2<Float> {
        var best: (Float, SIMD2<Float>)?
        for _ in 0..<60 {
            let a = rnd() * 2 * .pi, rad = miss ? 2.2 + 0.6 * rnd() : 0.6 + 0.6 * rnd()
            let p = c + SIMD2(cosf(a), sinf(a)) * rad
            guard p.y >= zlo, p.y <= zhi, abs(p.x) <= reach(p.y) - 0.17 else { continue }
            let clear = keepOff.map { simd_distance($0, p) }.min() ?? 9
            if clear >= keepAway { return p }
            if best == nil || clear > best!.0 { best = (clear, p) }
        }
        return best?.1 ?? c
    }

    /// Who gets it: of the others, the one who has touched it least in this bout (a tie: not the one it came from, then drawn).
    static func nextReceiver(others: [Int], touches: [Int: Int], sender: Int?, rnd: () -> Float) -> Int? {
        guard !others.isEmpty else { return nil }
        let least = others.map { touches[$0] ?? 0 }.min() ?? 0
        var pool = others.filter { (touches[$0] ?? 0) == least }
        if pool.count > 1, let s = sender, pool.contains(s) { pool.removeAll { $0 == s } }
        return pool[min(Int(rnd() * Float(pool.count)), pool.count - 1)]
    }

    /// The velocity of a header from `p` to come down through `(xz, y)` after `T` seconds.
    static func launch(from p: SIMD3<Float>, to xz: SIMD2<Float>, y: Float, T: Float) -> SIMD3<Float> {
        let g = TossTuning.gravity
        return SIMD3((xz.x - p.x) / T, (y - p.y + 0.5 * g * T * T) / T, (xz.y - p.z) / T)
    }
}

nonisolated struct BoutState {
    /// Rolled at the throw (the first header starts it) / the bout is on.
    var planned = false
    var on = false
    var active: Bool { planned || on }
    var touches = 0                    // headers in this bout (the first one included)
    var touched: [Int: Int] = [:]      // headers per Jelmiko in this bout
    var lookAt: SIMD2<Float>?          // where the ball was last struck from: everybody faces it
    var lastToucher: Int?
    var receiver: Int?
    var aim = SIMD2<Float>.zero
    var aimMode = ""
    var toPlayer = false               // the next strike goes to the player (the button was pressed)
    var startedAt: Float = 0
    var endedAt: Float = -99
}

extension PlayToss {
    // MARK: who do I face

    /// The way `j` faces while the ball game goes: the player (the camera) as always, or, in a bout, the one the ball is coming from (the one who sent it faces who it goes to).
    func faceVec(_ j: PlayJelly) -> SIMD2<Float> {
        if bout.active {
            let at = (j.id == bout.lastToucher ? bout.aim : bout.lookAt) ?? playerPoint()
            let d = at - j.pos
            return simd_length(d) > 1e-3 ? d : SIMD2(0, 1)
        }
        return playerPoint() - j.pos
    }
    func faceUnit(_ j: PlayJelly) -> SIMD2<Float> { let v = faceVec(j); return simd_length(v) > 1e-3 ? simd_normalize(v) : SIMD2(0, 1) }
    func faceTarget(_ j: PlayJelly) -> SIMD2<Float> { bout.active ? j.pos + faceVec(j) : playerPoint() }

    // MARK: the throw

    /// The seeded roll at a throw: does this one start a bout? (Beach ball, two or more Jelmiko on the play floor of the room; one Jelmiko rolls nothing.)
    func rollBout() -> Bool {
        guard !PlayTuning.ballReturnOld, !PlayTuning.old, !PlayTuning.boutOff, GameCamera.playFrame, GameCamera.roamFloor != nil else { return false }
        let st = PlayTuning.style(ballKind)
        guard st.boutChance > 0, jellies.filter({ !$0.free }).count >= 2 else { return false }
        return rand() < st.boutChance
    }

    // MARK: a strike

    /// A header in a bout. True = the bout sent the ball on to another Jelmiko; false = the bout is over (the touch cap, the button) and the ordinary header to the player follows.
    func boutStrike(by j: PlayJelly) -> Bool {
        let wasPlanned = bout.planned
        if wasPlanned { bout.planned = false; bout.on = true; setOwn(.bout); NSLog("[bout] begin clock=%.3f throw=%d", clock, throwSerial) }
        let id = j.id
        bout.touches += 1; bout.touched[id, default: 0] += 1
        noteRecallStrike()
        if bout.toPlayer || bout.touches >= BoutMath.touchCap {
            boutFinish(bout.toPlayer ? "recall" : "cap", oops: false)
            return false
        }
        let others = jellies.filter { !$0.free && $0.id != id }
        guard !others.isEmpty else { boutFinish("alone", oops: false); return false }
        let zr = Self.bodyZ()
        let zs = jellies.filter { !$0.free }.compactMap { home[$0.id]?.y }
        let zc = zs.isEmpty ? j.pos.y : zs.reduce(0, +) / Float(zs.count)
        let zlo = max(zr.lowerBound + 0.25, TossTuning.zBack + 2.5, zc - 1.6)          // (a ball on the floor needs room behind it for the one who sends it back)
        let zhi = max(min(zr.upperBound - 0.25, catchZ() - 1.3, zc + 1.4), zlo + 0.5)          // (the row's own depth: the ball is never aimed into the far back or the front band)
        let r = ball.radius, g = TossTuning.gravity
        var from = ball.pos
        from.y = max(from.y, j.headTop + r * 0.8)
        // who: the one who has touched it least (with three it goes round all three)
        let rid = BoutMath.nextReceiver(others: others.map(\.id), touches: bout.touched, sender: bout.lastToucher, rnd: { self.rand() }) ?? others[0].id
        let rj = jelly(rid)!
        var miss = false, T: Float = 1.2, spot = rj.pos, vel = SIMD3<Float>.zero
        for attempt in 0..<8 {          // (a ball that is not struck on its way goes on to the floor: aim so that it comes down inside the floor, not against the back wall or past a side line)
            miss = rand() < 1 / BoutMath.missEvery
            spot = BoutMath.pickFree(near: rj.pos, keepOff: others.filter { $0.id != rid }.map(\.pos) + [j.pos], miss: miss, reach: { Self.bodyReach($0) }, zlo: zlo, zhi: zhi, rnd: { self.rand() })
            let run = simd_distance(rj.pos, spot)
            let H = miss ? r + 0.02 : rj.sim.restCentroid.y + BobShape.H * 0.5 + BlobBrain.tossCrownRise + r * 0.9
            T = miss ? 0.95 : 1.05 + 0.12 * rand() + 0.2 * min(run, 1.4)
            vel = BoutMath.launch(from: from, to: spot, y: H, T: T)
            let vEnd = vel.y - g * T
            let tf = H > r + 0.05 ? (vEnd + (vEnd * vEnd + 2 * g * (H - r)).squareRoot()) / g : 0
            let land = spot + SIMD2(vel.x, vel.z) * tf
            let out = max(0, (TossTuning.zBack + 2.2) - land.y, land.y - (zhi + 0.1), abs(land.x) - (Self.bodyReach(min(max(land.y, zlo), zhi)) - 0.5))
            if out < 0.01 || attempt == 7 { break }
        }
        ball.vel = vel
        ball.pos.y = from.y
        ball.ignoring = id; ball.ignoreT = 0.45
        bout.lastToucher = id; bout.lookAt = j.pos
        bout.receiver = rid; bout.aim = spot; bout.aimMode = miss ? "miss" : "keep"
        returnAim = nil; passTo = nil
        rally += 1; headers += 1; touched = true; headChoice = nil
        phase = .flying; looseT = 0
        interceptAt[rid] = nil
        touchLog("header", j)
        NSLog("[bout] strike clock=%.3f throw=%d n=%d id=%d mode=%@ pos=(%.2f,%.2f) to=(%.2f,%.2f) T=%.2f receiver=%d recvPos=(%.2f,%.2f) run=%.2f touched=%@", clock, throwSerial, bout.touches, id, miss ? "miss" : "keep", j.pos.x, j.pos.y,
              spot.x, spot.y, T, rid, rj.pos.x, rj.pos.y, simd_distance(rj.pos, spot), bout.touched.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))
        j.brain.jellyKick = max(j.brain.jellyKick, 2.2)
        if !j.brain.tossBusy, Self.canHop(j.brain) {
            let P = faceVec(j); if simd_length(P) > 1e-3 { j.brain.tossFaceYaw = atan2f(P.x, P.y) }
            j.brain.tossHeaderStart(j.sim, j.skinner, jump: true)
        }
        onEvent?(.header(id: id, quality: .good))
        boutDispatch()
        return true
    }

    /// The one the ball is sent to goes now (no waiting for the ball to near him): he steps to the spot, turns to the one it comes from, and waits for the go of `boutIntercepts`.
    func boutDispatch() {
        guard let rid = bout.receiver, let j = jelly(rid) else { return }
        let S = bout.aim
        j.brain.tossFire = nil
        if j.brain.tossBumpStart(j.sim, j.skinner, stand: S, dir: faceUnit(j), header: true) { interceptAt[rid] = (S, clock) }
        else if simd_distance(j.pos, S) > 0.3 { j.brain.requestNow(.goTo(S)); interceptAt[rid] = (S, clock) }
    }

    /// The one who is to head the ball keeps getting ready (the part of `intercepts` that matters here, for this one only): his go, the late fallback, the ease of the ball's last bit onto his crown.
    func boutIntercepts() {
        guard bout.on, let rid = bout.receiver, let j = jelly(rid) else { return }
        guard let a = arrival(j) else { return }
        let busy = j.brain.tossBusy
        let mt = meetTime(j)
        let meetT = mt?.t ?? a.t
        let meetXZ: SIMD2<Float> = mt != nil ? SIMD2(ball.pos.x + ball.vel.x * meetT, ball.pos.z + ball.vel.z * meetT) : a.xz
        if !busy {
            let late = simd_distance(j.pos, a.xz) < Self.lateWalk && a.t <= BlobBrain.tossHeaderLead + 0.10
            if late, Self.canHop(j.brain) {
                let P = faceVec(j); if simd_length(P) > 1e-3 { j.brain.tossFaceYaw = atan2f(P.x, P.y) }
                j.brain.tossHeaderStart(j.sim, j.skinner, jump: true)          // (a late receiver still jumps and heads where he stands)
            } else if a.t > 0.18, clock - (interceptAt[rid]?.t ?? -9) > 0.35 {
                j.brain.tossFire = nil
                var stand = bout.aim
                if simd_distance(a.xz, stand) > 0.6 { stand = a.xz }          // (the ball is not going where it was meant: he goes where it is going)
                let zr = Self.bodyZ()
                stand.y = min(max(stand.y, zr.lowerBound), zr.upperBound)
                stand.x = min(max(stand.x, -Self.bodyReach(stand.y)), Self.bodyReach(stand.y))
                if j.brain.tossBumpStart(j.sim, j.skinner, stand: stand, dir: faceUnit(j), header: true) { interceptAt[rid] = (stand, clock) }
                else if simd_distance(j.pos, stand) > 0.3 { j.brain.requestNow(.goTo(stand)); interceptAt[rid] = (stand, clock) }
            }
        } else if j.brain.tossHeaderApproach, j.brain.idleState.toss.stage < 3, let last = interceptAt[rid], simd_distance(j.brain.idleState.toss.stand, meetXZ) > Self.steerReach + 0.4, clock - last.t > 0.3 {
            j.brain.tossHeaderRelease(j.sim, j.skinner)          // (the ball moved on: he is released and sent to the new place next step)
            interceptAt[rid] = (meetXZ, clock - 0.2)
        }
        steerOntoCrown(j, arriveIn: meetT)
        if busy, j.brain.tossHeaderApproach, j.brain.idleState.toss.stage == 3, let m = mt, m.t <= BlobBrain.tossCrouch + Self.riseTime(m.rise) + Self.goEarly { j.brain.idleState.toss.go = true }
    }

    // MARK: the end

    /// The bout's ball came down on the floor: it is over. A small "oops" from the one who missed, no cheer, no point; the nearest sends the ball back to the player as always.
    func boutFloor() {
        guard bout.on else { boutAbort("floor-before-first-strike"); return }
        ball.vel.x *= 0.12; ball.vel.z *= 0.12          // (it comes down with a soft thud and stays about where it landed: never rolled on to a side wall)
        boutFinish("floor", oops: true)
    }

    func boutFinish(_ reason: String, oops: Bool) {
        NSLog("[bout] end clock=%.3f throw=%d reason=%@ touches=%d dur=%.2f touched=%@", clock, throwSerial, reason, bout.touches, clock - bout.startedAt, bout.touched.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))
        if oops, let rid = bout.receiver, let j = jelly(rid), !j.brain.tossBusy { j.brain.face(.surprised, hold: 1.0) }
        bout.on = false; bout.planned = false; bout.receiver = nil; bout.toPlayer = false; bout.endedAt = clock
        setOwn(.none); pendingPasses = 0
        for j in jellies where !j.free { j.brain.tossFaceYaw = nil }
    }

    /// Drops the bout without a result (Done, a new throw, the view turned, the ball went where no bout is).
    func boutAbort(_ why: String) {
        guard bout.active else { return }
        NSLog("[bout] abort clock=%.3f why=%@ touches=%d", clock, why, bout.touches)
        bout.on = false; bout.planned = false; bout.receiver = nil; bout.toPlayer = false
        setOwn(.none)
        for j in jellies where !j.free { j.brain.tossFaceYaw = nil }
    }
}
