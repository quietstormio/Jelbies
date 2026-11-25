//
//  VolleyHarness.swift
//  A measuring rig for Jelly Volleyball: whole matches of the pure VolleySim played by a SCRIPTED player against the computer team, with a kinematic stand-in for the soft bodies
//  (walk, crouch / air / land, dive, the same timings as BlobBrain+Volley). The scripted players only use what a finger has: the stick (`setStick`) and the Hit button (`tap`).
//  Used by VolleyFixesTests (win-rate table per level) and, compiled alone, by the tuning loop. No XCTest in here.
//

import Foundation
import simd
#if !STANDALONE
@testable import BobV1
#endif

/// A kinematic stand-in for one soft body.
struct VolleyKBody {
    enum Ph { case ground, crouch, air, land, diveCrouch, dive, slide, peel }
    var ph = Ph.ground
    var t: Float = 0
    var x: Float, z: Float
    var lift: Float = 0
    var from = SIMD2<Float>.zero, to = SIMD2<Float>.zero
    var apex: Float = 0.5, airT: Float = 0.8
    var diveDir: Float = 1
    var wantX: Float, wantZ: Float
    var speed: Float = 0.35
    var side: Float
    var finished = false
    var tilted = false
    /// Heading (as BlobBrain+Volley turns the body): rest 3/4 toward the camera and the net; a jump turns to `faceYaw` (the sim's `.face`), a spike or block to the net, a dive along the sand.
    var yaw: Float = 0, yaw0: Float = 0, faceYaw: Float?, spikeT: Float = -1, block = false
    var goal: Float?
    var restYaw: Float { goal ?? side * VolleyTuning.restYaw }
    func wrap(_ a: Float) -> Float { var v = a; while v > .pi { v -= 2 * .pi }; while v < -.pi { v += 2 * .pi }; return v }
    init(x: Float, z: Float, side: Float) { self.x = x; self.z = z; wantX = x; wantZ = z; self.side = side; yaw = side * VolleyTuning.restYaw }

    func ownSide(_ v: Float) -> Float { side > 0 ? min(v, -VolleyTuning.netMargin) : max(v, VolleyTuning.netMargin) }
    func ownZ(_ v: Float) -> Float { min(max(v, -VolleyTuning.zLimit), VolleyTuning.zLimit) }
    func ease(_ v: Float) -> Float { let k = min(1, max(0, v)); return k * k * (3 - 2 * k) }

    mutating func jump(dx: Float, dz: Float, apex a: Float, block b: Bool = false) {
        guard ph == .ground || ph == .land else { return }
        ph = .crouch; t = 0; yaw0 = yaw; spikeT = -1; block = b
        from = SIMD2(x, z); to = from + SIMD2(dx, dz); to.x = ownSide(to.x); to.y = ownZ(to.y)
        apex = a; airT = VolleyTuning.airTime(apex: a)
    }
    mutating func dive(dir: Float) {
        guard ph == .ground || ph == .land else { return }
        ph = .diveCrouch; t = 0; from = SIMD2(x, z); yaw0 = yaw; faceYaw = nil
        let netDir: Float = side > 0 ? 1 : -1
        let room = side > 0 ? -VolleyTuning.netMargin - x : x - VolleyTuning.netMargin
        diveDir = (dir == netDir && room < 0.5) ? -dir : dir
    }

    mutating func step(_ dt: Float) {
        finished = false
        t += dt
        switch ph {
        case .ground:
            tilted = false
            let dv = SIMD2(wantX - x, wantZ - z), dl = simd_length(dv)
            if dl > 0.06 {
                let sp = VolleyTuning.walkSpeed(speed: speed) * 0.9          // (steps are discrete: a little under the nominal speed)
                let l = min(dl, sp * dt)
                x += dv.x / dl * l; z += dv.y / dl * l
            }
            lift = 0
            yaw += max(-3.0 * dt, min(3.0 * dt, wrap(restYaw - yaw)))
        case .crouch:
            if t >= VolleyTuning.crouch { ph = .air; t = 0 }
        case .air:
            let u = min(1, t / airT)
            lift = apex * 4 * u * (1 - u)
            if spikeT >= 0 { spikeT += dt; yaw = yaw0 + wrap(side * .pi / 2 - yaw0) * ease(spikeT / 0.16) }
            else if block { yaw = yaw0 + wrap(side * .pi / 2 - yaw0) * ease(t / 0.16) }
            else { yaw = yaw0 + wrap((faceYaw ?? restYaw) - yaw0) * ease(t / 0.4) }
            let e = ease(u)
            x = ownSide(from.x + (to.x - from.x) * e); z = ownZ(from.y + (to.y - from.y) * e)
            if t >= airT { ph = .land; t = 0; lift = 0; yaw0 = yaw }
        case .land:
            lift = 0
            yaw = yaw0 + wrap(restYaw - yaw0) * ease(t / 0.30)
            if t >= 0.52 { ph = .ground; t = 0; finished = true; faceYaw = nil; block = false }
        case .diveCrouch:
            if t >= 0.10 { ph = .dive; t = 0; to = from + SIMD2(diveDir * 1.0, 0) }
        case .dive:
            tilted = true
            let u = min(1, t / 0.32)
            yaw = yaw0 + wrap(diveDir * .pi / 2 - yaw0) * ease(u / 0.5)
            let e = 1 - (1 - u) * (1 - u)
            x = ownSide(from.x + (to.x - from.x) * e); z = from.y
            lift = 0.20 * 4 * u * (1 - u)
            if t >= 0.32 { ph = .slide; t = 0; from = SIMD2(x, z); to = from + SIMD2(diveDir * 0.3, 0) }
        case .slide:
            let u = min(1, t / 0.26)
            let e = 1 - (1 - u) * (1 - u)
            x = ownSide(from.x + (to.x - from.x) * e); lift = 0
            if t >= 0.26 { ph = .peel; t = 0; from = SIMD2(x, z); yaw0 = yaw }
        case .peel:
            let u = min(1, t / 0.38)
            lift = 0.10 * sinf(.pi * min(1, u * 1.1))
            yaw = yaw0 + wrap(restYaw - yaw0) * ease(u)
            if t >= 0.38 { ph = .land; t = 0; tilted = false; to = from; yaw0 = yaw }
        }
    }

    /// The surface in the x / y plane (an ellipse; a diving body lies on its front).
    func samples() -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        let rx: Float = tilted ? 0.68 : 0.55, ry: Float = tilted ? 0.52 : 0.675
        let cy: Float = (tilted ? 0.50 : 0.675) + lift
        for k in 0..<28 {
            let a = Float(k) / 28 * 2 * .pi
            out.append(SIMD2(x + rx * cosf(a), cy + ry * sinf(a)))
        }
        return out
    }
    var top: Float { (tilted ? 1.02 : 1.35) + lift }
    var grounded: Bool { ph != .air }
}

/// How a scripted player plays.
struct VolleyScriptProfile {
    var name: String
    /// Seconds between the ball being hit toward him and his first move.
    var react: ClosedRange<Float>
    /// Chance a hit's tap is off by 0.14...0.35 s (early or late).
    var mistime: Float
    /// Spread (sd, in u) of where he thinks the ball will land.
    var posError: Float
    /// Spread (sd, s) of a normal tap.
    var tapJitter: Float
    /// His own serve: the pause before the toss and the spread of the second tap.
    var serveDelay: ClosedRange<Float>
    /// A habit the scripted player repeats every time (the dominant-strategy bots): `aim` a fixed swipe on the Hit button, `aimCycle` a swipe that changes every hit, `alwaysSpike` a second tap in
    /// the air, `noMove` never touches the stick, `spam` taps the button every 0.25 s whatever the ball does.
    var aim: SIMD2<Float>? = nil
    var aimCycle = false
    var aimEvery = 1
    /// The aim is only used for the smash (the third touch of his team), the way a person places a spike and just plays the first two touches.
    var aimSpikeOnly = false
    var alwaysSpike = false
    var noMove = false
    var spam = false
    func with(_ name: String, _ f: (inout VolleyScriptProfile) -> Void) -> VolleyScriptProfile { var c = self; c.name = name; f(&c); return c }
    static let ordinary = VolleyScriptProfile(name: "ordinary", react: 0.35...0.5, mistime: 0.25, posError: 0.30, tapJitter: 0.045, serveDelay: 0.7...1.3)
    static let skilled = VolleyScriptProfile(name: "skilled", react: 0.12...0.2, mistime: 0.05, posError: 0.08, tapJitter: 0.02, serveDelay: 0.5...0.8)
}

struct VolleyScript {
    var p: VolleyScriptProfile
    var rng: VolleyRng
    var lastKey = -1, lastControlled = -1
    var perceiveAt: Float = 0
    var err = SIMD2<Float>.zero
    var off: Float = 0
    var tapped = false
    var serveAt: Float = -1
    var servePhaseT: Float = 0
    var taps = 0
    var spikeSent = false, lastSpam: Float = -9, cycle = 0

    init(_ p: VolleyScriptProfile, seed: UInt64) { self.p = p; rng = VolleyRng(seed &* 31 &+ 7) }

    mutating func gauss() -> Float { (rng.next() + rng.next() + rng.next() + rng.next() - 2) * 1.7320508 }
    mutating func newTouch(now: Float) {
        perceiveAt = now + rng.range(p.react.lowerBound, p.react.upperBound)
        err = SIMD2(gauss() * p.posError, gauss() * p.posError * 0.6)
        if rng.next() < p.mistime { off = (rng.next() < 0.5 ? 1 : -1) * rng.range(0.14, 0.35) } else { off = gauss() * p.tapJitter }
        tapped = false
    }

    mutating func drive(_ s: inout VolleySim, dt: Float) {
        let c = s.controlled
        let now = s.clock
        if s.phase == .serveWait {
            if lastKey != -2 { lastKey = -2; serveAt = now + rng.range(p.serveDelay.lowerBound, p.serveDelay.upperBound); tapped = false }
            s.setStick(.zero)
            if let a = p.aim { s.setAim(a) }
            if s.servingPlayer == c, !tapped, now >= serveAt { s.tap(); tapped = true; taps += 1 }
            return
        }
        guard s.phase == .rally else { s.setStick(.zero); lastKey = -3; return }
        if s.touchSerial != lastKey || c != lastControlled { lastKey = s.touchSerial; lastControlled = c; newTouch(now: now); spikeSent = false; cycle += 1 }
        let me = s.players[c]
        if let a = p.aim, !p.aimSpikeOnly || s.touches[0] >= 2 { s.setAim(a) }
        if p.aimCycle, cycle % p.aimEvery == 0, !p.aimSpikeOnly || s.touches[0] >= 2 { let ang = Float(cycle) * 2.399963; s.setAim(SIMD2(cosf(ang), sinf(ang)) * 0.95) }
        if p.alwaysSpike, me.act == .jump, !me.grounded, !spikeSent, me.actT > VolleyTuning.crouch + 0.04 { s.tap(); spikeSent = true; taps += 1 }
        if p.spam, now - lastSpam >= 0.25 { lastSpam = now; s.tap(); taps += 1 }
        // my own serve: the second tap near the top of the toss
        if s.hitLabel == "Serve!", s.servingPlayer == c {
            s.setStick(.zero)
            if let r = s.ring, !tapped, r.tau - r.lead <= off * 0.5 { s.tap(); tapped = true; taps += 1 }
            return
        }
        guard now >= perceiveAt, let tm = s.timing(for: c) else { s.setStick(.zero); return }
        let tgt = SIMD2(tm.x, tm.z) + err
        if p.noMove {
            s.setStick(.zero)
            if let r = s.ring, !tapped, me.act == .stand, r.tau - r.lead <= off { s.tap(); tapped = true; taps += 1 }
            return
        }
        let d = tgt - SIMD2(me.x, me.z)
        let dl = simd_length(d)
        if dl > 0.12 { s.setStick(d / max(dl, 0.9)) } else { s.setStick(.zero) }
        if let r = s.ring, !tapped, me.act == .stand, dl < 0.85, r.tau - r.lead <= off { s.tap(); tapped = true; taps += 1 }
    }
}

struct VolleyMatchResult { var win: Bool; var score: [Int]; var seconds: Float; var spikesByComputer = 0; var rallyMax = 0; var serveErrors = 0; var autoSwitches = 0, manualSwitches = 0
    /// Why each point ended: "<winner team> <how>" counts (how: the last contact's kind of the team that hit last, `out`, `drop` (landed in), `fault`).
    var reasons: [String: Int] = [:]
    var outSpots: [SIMD2<Float>] = []
    /// Touches of the ball that started with it outside the front 60 degrees of the hitter's heading (and not right over him), and all touches.
    var backTurned = 0, touches = 0, turnedAway = 0
    var smashes = [0, 0], smashesLobbed = [0, 0]
    /// A player touching the ball twice running (not after a block): the double hit that used to end in a fourth-touch fault.
    var doubleHits = 0, faults = 0
    /// The human team's smashes, and how many the visitors touched (dug or blocked) before they landed.
    var humanSpikes = 0, humanSpikesDug = 0
    var dbgLines: [String] = []
    var spikeLand: [SIMD3<Float>] = [] }

enum VolleyHarness {
    static func play(tier: VolleyTier, seed: UInt64, profile: VolleyScriptProfile, mine: [VolleyStats] = [VolleyStats(), VolleyStats()], autoSwitch: Bool = true, maxSeconds: Float = 400, manualSwitchAt: Float? = nil, traceFrom: Float = -1) -> VolleyMatchResult {
        var s = VolleySim(mode: .match(tier), mine: mine, seed: seed, firstServe: 0)
        s.autoSwitch = autoSwitch
        var bodies = (0..<4).map { VolleyKBody(x: VolleyTuning.startX[$0], z: VolleyTuning.startZ[$0], side: $0 < 2 ? 1 : -1) }
        for i in 0..<4 { bodies[i].speed = s.players[i].stats.speed }
        var script = VolleyScript(profile, seed: seed)
        let dt: Float = 1.0 / 60
        var res = VolleyMatchResult(win: false, score: [0, 0], seconds: 0)
        var ticks = 0
        var lastDbg = ""
        var hist: [String] = []
        var lastTA = 0
        var pendingSpike = false
        var spikeAt: Float = 0, spikeSnap = ""
        var prevHitter = -1, prevKind = VolleyHit.bump
        var prevHitT: Float = -9
        var lastKind = VolleyHit.bump, lastTeam = 0, touchesNow = 0
        while s.phase != .over, Float(ticks) * dt < maxSeconds {
            ticks += 1
            for i in 0..<4 {
                bodies[i].step(dt)
                #if BASESIM
                s.setBody(i, x: bodies[i].x, z: bodies[i].z, lift: bodies[i].lift, top: bodies[i].top, grounded: bodies[i].grounded)
                #else
                s.setBody(i, x: bodies[i].x, z: bodies[i].z, lift: bodies[i].lift, top: bodies[i].top, grounded: bodies[i].grounded, yaw: bodies[i].yaw)
                #endif
                let smp = bodies[i].samples()
                s.setSamples(i) { $0 = smp }
                if bodies[i].finished { s.bodyDone(i) }
                else if bodies[i].ph == .ground, s.players[i].act != .stand, s.players[i].actT > 0.3 { s.bodyDone(i) }
            }
            if let m = manualSwitchAt, s.clock >= m, res.manualSwitches == 0 { s.switchTo(1 - s.controlled, manual: true) }
            script.drive(&s, dt: dt)
            s.tick(dt: dt)
            for e in s.takeEvents() {
                switch e {
                case .jump(let i, let dx, let dz, let apex, let blk): bodies[i].jump(dx: dx, dz: dz, apex: apex, block: blk)
                #if !BASESIM
                case .face(let i, let y): bodies[i].faceYaw = y
                #endif
                case .spike(let i): if bodies[i].ph == .air || bodies[i].ph == .crouch { bodies[i].spikeT = 0 }
                case .dive(let i, let dir): bodies[i].dive(dir: dir)
                case .contact(let i, let kind, _, let pt, _, _):
                    if pendingSpike { if i >= 2, kind != .block { res.humanSpikesDug += 1 }; pendingSpike = false }
                    if i < 2, kind == .spike { res.humanSpikes += 1; pendingSpike = true; spikeAt = s.clock; spikeSnap = String(format: "C2(%.2f,%.2f) C3(%.2f,%.2f) tgt?", s.players[2].x, s.players[2].z, s.players[3].x, s.players[3].z) }
                    if i == prevHitter, prevKind != .block, kind != .block, kind != .serve, s.clock - prevHitT < 0.8 { res.doubleHits += 1; res.dbgLines.append(String(format: "DOUBLE p%d %@ then %@ gap %.2f act %@", i, "\(prevKind)", "\(kind)", s.clock - prevHitT, "\(s.players[i].act)")) }          // (the ball that has only just left his body, touched by him again)
                    prevHitter = i; prevKind = kind; prevHitT = s.clock
                    do {
                        #if BASESIM
                        let cb = SIMD2(pt.x, s.ball.z)
                        #else
                        let cb = SIMD2(s.contactBall.x, s.contactBall.z)
                        #endif
                        let d = cb - SIMD2(bodies[i].x, bodies[i].z), l = simd_length(d); let f = SIMD2(sinf(bodies[i].yaw), cosf(bodies[i].yaw)); res.touches += 1; if kind != .block, l >= 0.45, simd_dot(f, d / l) < cosf(.pi / 3) { res.backTurned += 1 } }
                    if traceFrom >= 0, s.clock >= traceFrom - 1, s.clock < traceFrom + 3 { print("CONTACT p\(i) \(kind) t=\(s.clock)") }; if i >= 2, kind == .spike { res.spikesByComputer += 1 }; lastKind = kind; lastTeam = i / 2
                    hist.append(String(format: "p%d %@ t=%.2f x=%.2f z=%.2f act=%@ q=%@", i, "\(kind)", s.clock, s.players[i].x, s.players[i].z, "\(s.players[i].act)", "\(s.players[i].tapQ)")); if hist.count > 5 { hist.removeFirst() }
                    if i >= 2, kind == .spike, let tl = s.timeToHeight(VolleyTuning.ballR) { res.spikeLand.append(SIMD3(s.xAfter(tl), s.zAfter(tl), tl)) }
                case .touchCount(_, let c): touchesNow = c
                case .fault(let team): res.faults += 1; res.dbgLines.append("FAULT team \(team): " + hist.joined(separator: " | "))
                case .point(let team, let out):
                    prevHitter = -1; pendingSpike = false
                    let who = team == 0 ? "H" : "C", hit = lastTeam == 0 ? "H" : "C"
                    let how = out ? "out(\(hit) \(lastKind))" : (lastTeam == team ? "landed(\(lastKind))" : "dropped(\(lastKind))")
                    res.reasons[who + " " + how, default: 0] += 1
                    if who == "H", lastTeam == 1, lastKind == .bump { res.dbgLines.append(String(format: "CBUMP out=%d t=%.2f ball(%.2f,%.2f) | ", out ? 1 : 0, s.clock, s.ball.pos.x, s.ball.z) + hist.suffix(3).joined(separator: " | ")) }
                    if who == "H", lastTeam == 0, lastKind == .spike, !out { res.dbgLines.append(String(format: "KILL t=%.2f flight %.2f ball(%.2f,%.2f) C2(%.2f,%.2f %@ w%.2f) C3(%.2f,%.2f %@ w%.2f) at spike: %@", s.clock, s.clock - spikeAt, s.ball.pos.x, s.ball.z, s.players[2].x, s.players[2].z, "\(s.players[2].act)", s.players[2].wait, s.players[3].x, s.players[3].z, "\(s.players[3].act)", s.players[3].wait, spikeSnap)) }
                    if who == "H", lastTeam == 0, lastKind == .serve || lastKind == .free, !out { res.dbgLines.append(String(format: "ACE \(lastKind) t=%.2f ball(%.2f,%.2f) C2(%.2f,%.2f %@ wait %.2f) C3(%.2f,%.2f %@ wait %.2f)", s.clock, s.ball.pos.x, s.ball.z, s.players[2].x, s.players[2].z, "\(s.players[2].act)", s.players[2].wait, s.players[3].x, s.players[3].z, "\(s.players[3].act)", s.players[3].wait)) }
                    if lastTeam == 1, lastKind == .spike, team == 0 { res.dbgLines.append((out ? "OUT " : "NET ") + String(format: "t=%.2f ", s.clock) + lastDbg + String(format: " end(%.2f,%.2f)", s.ball.pos.x, s.ball.z)) }
                    if out, lastTeam == 1, lastKind == .spike { res.outSpots.append(SIMD2(s.ball.pos.x, s.ball.z)) }
                case .switched(_, let auto): if auto { res.autoSwitches += 1 } else { res.manualSwitches += 1 }
                default: break
                }
            }
            #if !BASESIM
            if traceFrom >= 0, s.turnedAway != lastTA, s.clock >= traceFrom, s.clock < traceFrom + 3 { print(String(format: "TURNEDAWAY t=%.2f ball(%.2f,%.2f,%.2f) players: ", s.clock, s.ball.pos.x, s.ball.pos.y, s.ball.z) + (0..<4).map { String(format: "p%d(%.2f,%.2f yaw %.2f %@)", $0, s.players[$0].x, s.players[$0].z, s.players[$0].yaw ?? 9, "\(s.players[$0].act)") }.joined(separator: " ")) }
            lastTA = s.turnedAway
            #endif
            if traceFrom >= 0, s.clock >= traceFrom, s.clock < traceFrom + 3 { print(String(format: "t=%.2f ball(%.2f,%.2f,z %.2f) v(%.2f,%.2f,%.2f) ph %@", s.clock, s.ball.pos.x, s.ball.pos.y, s.ball.z, s.ball.vel.x, s.ball.vel.y, s.ball.vz, "\(s.phase)") + (2...3).map { String(format: " | p%d (%.2f,%.2f)->(%.2f,%.2f) w%.2f %@ body %@ goal %.2f yaw %.2f", $0, s.players[$0].x, s.players[$0].z, s.players[$0].wantX, s.players[$0].wantZ, s.players[$0].wait, "\(s.players[$0].act)", "\(bodies[$0].ph)", s.players[$0].goalForTrace, bodies[$0].yaw) }.joined()) }
            #if !BASESIM
            for i in 0..<4 { bodies[i].goal = s.players[i].faceGoal }
            #endif
            for i in 0..<4 { bodies[i].wantX = s.players[i].wantX; bodies[i].wantZ = s.players[i].wantZ }
            res.rallyMax = max(res.rallyMax, s.rallyHits)
        }
        res.win = s.winner == 0
        #if !BASESIM
        res.turnedAway = s.turnedAway
        res.smashes = s.smashCount; res.smashesLobbed = s.smashLobbed
        #endif
        res.score = s.score
        res.seconds = Float(ticks) * dt
        return res
    }

    /// Win rate of `profile` against every tier over `n` matches each (seeds `seed0 ..< seed0 + n`).
    static func table(profile: VolleyScriptProfile, n: Int, seed0: UInt64 = 1000) -> [VolleyTier: (rate: Float, secs: Float, spikes: Float)] {
        var out: [VolleyTier: (Float, Float, Float)] = [:]
        for t in VolleyTier.allCases {
            var w = 0, secs: Float = 0, sp = 0
            for k in 0..<n {
                let r = play(tier: t, seed: seed0 + UInt64(k) * 7919, profile: profile)
                if r.win { w += 1 }; secs += r.seconds; sp += r.spikesByComputer
            }
            out[t] = (Float(w) / Float(n), secs / Float(n), Float(sp) / Float(n))
        }
        return out
    }
}

extension VolleyPlayer {
    /// Where he is told to look, for the trace lines (9 = nowhere); the old sim has no such thing.
    var goalForTrace: Float {
        #if BASESIM
        return 9
        #else
        return faceGoal ?? 9
        #endif
    }
}
