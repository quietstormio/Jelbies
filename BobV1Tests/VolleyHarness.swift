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
    init(x: Float, z: Float, side: Float) { self.x = x; self.z = z; wantX = x; wantZ = z; self.side = side }

    func ownSide(_ v: Float) -> Float { side > 0 ? min(v, -VolleyTuning.netMargin) : max(v, VolleyTuning.netMargin) }
    func ownZ(_ v: Float) -> Float { min(max(v, -VolleyTuning.zLimit), VolleyTuning.zLimit) }
    func ease(_ v: Float) -> Float { let k = min(1, max(0, v)); return k * k * (3 - 2 * k) }

    mutating func jump(dx: Float, dz: Float, apex a: Float) {
        guard ph == .ground || ph == .land else { return }
        ph = .crouch; t = 0
        from = SIMD2(x, z); to = from + SIMD2(dx, dz); to.x = ownSide(to.x); to.y = ownZ(to.y)
        apex = a; airT = VolleyTuning.airTime(apex: a)
    }
    mutating func dive(dir: Float) {
        guard ph == .ground || ph == .land else { return }
        ph = .diveCrouch; t = 0; from = SIMD2(x, z)
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
        case .crouch:
            if t >= VolleyTuning.crouch { ph = .air; t = 0 }
        case .air:
            let u = min(1, t / airT)
            lift = apex * 4 * u * (1 - u)
            let e = ease(u)
            x = ownSide(from.x + (to.x - from.x) * e); z = ownZ(from.y + (to.y - from.y) * e)
            if t >= airT { ph = .land; t = 0; lift = 0 }
        case .land:
            lift = 0
            if t >= 0.52 { ph = .ground; t = 0; finished = true }
        case .diveCrouch:
            if t >= 0.10 { ph = .dive; t = 0; to = from + SIMD2(diveDir * 1.0, 0) }
        case .dive:
            tilted = true
            let u = min(1, t / 0.32)
            let e = 1 - (1 - u) * (1 - u)
            x = ownSide(from.x + (to.x - from.x) * e); z = from.y
            lift = 0.20 * 4 * u * (1 - u)
            if t >= 0.32 { ph = .slide; t = 0; from = SIMD2(x, z); to = from + SIMD2(diveDir * 0.3, 0) }
        case .slide:
            let u = min(1, t / 0.26)
            let e = 1 - (1 - u) * (1 - u)
            x = ownSide(from.x + (to.x - from.x) * e); lift = 0
            if t >= 0.26 { ph = .peel; t = 0; from = SIMD2(x, z) }
        case .peel:
            let u = min(1, t / 0.38)
            lift = 0.10 * sinf(.pi * min(1, u * 1.1))
            if t >= 0.38 { ph = .land; t = 0; tilted = false; to = from }
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
            if s.servingPlayer == c, !tapped, now >= serveAt { s.tap(); tapped = true; taps += 1 }
            return
        }
        guard s.phase == .rally else { s.setStick(.zero); lastKey = -3; return }
        if s.touchSerial != lastKey || c != lastControlled { lastKey = s.touchSerial; lastControlled = c; newTouch(now: now) }
        let me = s.players[c]
        // my own serve: the second tap near the top of the toss
        if s.hitLabel == "Serve!", s.servingPlayer == c {
            s.setStick(.zero)
            if let r = s.ring, !tapped, r.tau - r.lead <= off * 0.5 { s.tap(); tapped = true; taps += 1 }
            return
        }
        guard now >= perceiveAt, let tm = s.timing(for: c) else { s.setStick(.zero); return }
        let tgt = SIMD2(tm.x, tm.z) + err
        let d = tgt - SIMD2(me.x, me.z)
        let dl = simd_length(d)
        if dl > 0.12 { s.setStick(d / max(dl, 0.9)) } else { s.setStick(.zero) }
        if let r = s.ring, !tapped, me.act == .stand, dl < 0.85, r.tau - r.lead <= off { s.tap(); tapped = true; taps += 1 }
    }
}

struct VolleyMatchResult { var win: Bool; var score: [Int]; var seconds: Float; var spikesByComputer = 0; var rallyMax = 0; var serveErrors = 0; var autoSwitches = 0, manualSwitches = 0 }

enum VolleyHarness {
    static func play(tier: VolleyTier, seed: UInt64, profile: VolleyScriptProfile, mine: [VolleyStats] = [VolleyStats(), VolleyStats()], autoSwitch: Bool = true, maxSeconds: Float = 400, manualSwitchAt: Float? = nil) -> VolleyMatchResult {
        var s = VolleySim(mode: .match(tier), mine: mine, seed: seed, firstServe: 0)
        s.autoSwitch = autoSwitch
        var bodies = (0..<4).map { VolleyKBody(x: VolleyTuning.startX[$0], z: VolleyTuning.startZ[$0], side: $0 < 2 ? 1 : -1) }
        for i in 0..<4 { bodies[i].speed = s.players[i].stats.speed }
        var script = VolleyScript(profile, seed: seed)
        let dt: Float = 1.0 / 60
        var res = VolleyMatchResult(win: false, score: [0, 0], seconds: 0)
        var ticks = 0
        while s.phase != .over, Float(ticks) * dt < maxSeconds {
            ticks += 1
            for i in 0..<4 {
                bodies[i].step(dt)
                s.setBody(i, x: bodies[i].x, z: bodies[i].z, lift: bodies[i].lift, top: bodies[i].top, grounded: bodies[i].grounded)
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
                case .jump(let i, let dx, let dz, let apex, _): bodies[i].jump(dx: dx, dz: dz, apex: apex)
                case .dive(let i, let dir): bodies[i].dive(dir: dir)
                case .contact(let i, let kind, _, _, _, _): if i >= 2, kind == .spike { res.spikesByComputer += 1 }
                case .switched(_, let auto): if auto { res.autoSwitches += 1 } else { res.manualSwitches += 1 }
                default: break
                }
            }
            for i in 0..<4 { bodies[i].wantX = s.players[i].wantX; bodies[i].wantZ = s.players[i].wantZ }
            res.rallyMax = max(res.rallyMax, s.rallyHits)
        }
        res.win = s.winner == 0
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
