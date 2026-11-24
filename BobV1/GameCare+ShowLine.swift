//
//  GameCare+ShowLine.swift
//  show-line-r1 (2026-11-24, the owner: "They still get very stuck when getting back in line during show that can not happen ever"): where every body of the Trick round is MEANT to stand
//  right now (`showSeat`), and the capture probe that measures it (`[showline]` lines, dev arguments on the simulator only).
//

import Foundation
import simd
import QuartzCore

extension GameCare {
    /// Where actor `aid` is meant to stand in the Trick round right now, nil when it has no seat (not a stage body, or not the Trick round).
    /// Player: the middle, except while the entrants take their turn (the aside seat, then the middle again for `.playerBack`). A rival: the middle while she walks in and performs, else her rest seat.
    func showSeat(_ aid: Int) -> SIMD2<Float>? {
        guard show.onStage, showBook.trickSet else { return nil }
        let sideways = GameCamera.aspect > 1
        if aid == show.playerID {
            if show.trickStage == .rivals { return show.rivalStep == .playerBack ? ShowStage.playerSpot : ShowStage.playerAside(sideways: sideways) }
            return ShowStage.playerSpot
        }
        guard let k = showBook.rivalBody.first(where: { $0.value == aid })?.key else { return nil }
        if show.trickStage == .rivals, show.rivalTurn == k, show.rivalStep == .walkIn || show.rivalStep == .perform { return ShowStage.playerSpot }
        return ShowStage.rivalRest(k, sideways: sideways)
    }

    #if targetEnvironment(simulator)
    /// The probe's state: when each body began a return (seat changed under it), and which violations are on now.
    final class ShowLineProbe { var returnStart: [Int: Double] = [:]; var clock: Double = 0; var lastPrint: Double = -1; var overlap = false; var hidden = false; var lastStage = ""; var notFormedLogged = false }
    nonisolated(unsafe) static let showLineProbe = ShowLineProbe()

    /// A line at 10 Hz for the Trick round: every body's place and seat; a `VIOL` line the moment two bodies are closer than 1.0, one is hidden behind another, a return took over 2 s, or a turn began with the line not formed.
    func showLineProbeTick(dt: Float) {
        guard DevArgs.enabled, UserDefaults.standard.integer(forKey: "ShowLineLog") != 0, show.onStage, showBook.trickSet else { return }
        let p = Self.showLineProbe
        p.clock += Double(dt)
        let book = showBook
        let bodies: [JellyActor] = (book.performers.first.flatMap { book.actors.indices.contains($0) ? book.actors[$0] : nil }.map { [$0] } ?? []) + book.extra
        guard bodies.count > 1 else { return }
        func floorOf(_ a: JellyActor) -> SIMD2<Float> { let c = a.sim.centroid(); return SIMD2(c.x, c.z) }
        var ov = false, hid = false
        for i in bodies.indices { for j in bodies.indices where j > i {
            if simd_distance(floorOf(bodies[i]), floorOf(bodies[j])) < 1.0 { ov = true }
            for (a, b) in [(bodies[i], bodies[j]), (bodies[j], bodies[i])] { let d = floorOf(a) - floorOf(b); if d.y > 0 && d.y < 1.1 && abs(d.x) < 1.0 && abs(floorOf(a).x) < 3 && abs(floorOf(b).x) < 3 { hid = true } }
        } }
        func line() -> String { bodies.map { a in String(format: "[%d (%.2f,%.2f) -> %@]", a.id, floorOf(a).x, floorOf(a).y, showSeat(a.id).map { String(format: "(%.2f,%.2f)", $0.x, $0.y) } ?? "-") }.joined(separator: " ") }
        let st = "\(show.trickStage)/\(show.rivalStep)/\(String(describing: show.rivalTurn))"
        if ov && !p.overlap { print(String(format: "[showline] VIOL overlap t=%.2f r%d %@ %@", p.clock, show.rivalRound, st, line())) }
        if hid && !p.hidden { print(String(format: "[showline] VIOL hidden t=%.2f r%d %@ %@", p.clock, show.rivalRound, st, line())) }
        p.overlap = ov; p.hidden = hid
        for a in bodies {
            let there = showSeat(a.id).map { simd_distance(floorOf(a), $0) < 0.5 } ?? true
            if !there, p.returnStart[a.id] == nil, !show.trickEntering { p.returnStart[a.id] = p.clock }
            if there, let t0 = p.returnStart[a.id] {
                p.returnStart[a.id] = nil
                print(String(format: "[showline] RETURN body %d %.2f s%@", a.id, p.clock - t0, p.clock - t0 > 2 ? " VIOL slow" : ""))
            }
        }
        let key = "\(show.trickStage)/\(show.rivalStep)"
        if key != p.lastStage {
            let opens = (show.trickStage == .pick && p.lastStage.hasPrefix("rivals") && show.round == .trick) || (show.trickStage == .rivals && show.rivalStep == .perform && !p.lastStage.hasSuffix("perform"))
            p.lastStage = key
            if opens {
                let formed = bodies.allSatisfy { a in showSeat(a.id).map { simd_distance(floorOf(a), $0) < 0.5 } ?? true }
                print(String(format: "[showline] TURN t=%.2f %@ formed=%d%@", p.clock, st, formed ? 1 : 0, formed ? "" : " VIOL notformed " + line()))
            }
        }
        if p.clock - p.lastPrint >= 0.1 { p.lastPrint = p.clock; print(String(format: "[showline] t=%.1f w=%.2f r%d %@ ", p.clock, CACurrentMediaTime(), show.rivalRound, st) + line()) }
    }
    #endif
}

/// One body's place in the line: how long it has been off its seat on this leg, how long the leg may take, and whether the keeper is carrying it there.
struct ShowSeatKeep {
    var seat: SIMD2<Float>?
    var off: Float = 0
    var budget: Float = 1
    var gliding = false
    /// Seconds off the seat, not walking and not waiting its turn for the gate / the middle: a body that is merely STOPPED away from its seat.
    var stalled: Float = 0
    var asked = false
    /// Seconds spent waiting its turn for the gate / the middle on this leg.
    var waited: Float = 0
}

extension GameCare {
    /// A leg may take its walk at this pace (u/s; the stage walk is measured at ~1.4-1.6 u/s on a straight leg) plus `grace` seconds for the turn to the camera and the one in front.
    static let lineWalkPace: Float = 0.8, lineGrace: Float = 1.5, lineMaxLeg: Float = 9.0, lineStall: Float = 1.0, lineWaitMax: Float = 6.0
    /// A body this close to its seat is in it. A body that stands closer to another than `lineTouch` for `lineTouchHold` seconds is carried to its seat too.
    static let lineAt: Float = 0.3, lineTouch: Float = 1.15, lineTouchHold: Float = 0.5, glideSpeed: Float = 3.2

    /// Off only for a capture that wants the old behaviour (`-ShowLineKeepOff 1`, dev arguments): the baseline measurement.
    static var lineKeeperOn: Bool { !(DevArgs.enabled && UserDefaults.standard.object(forKey: "ShowLineKeepOff") != nil) }
    private func lineBodies() -> [JellyActor] {
        let book = showBook
        let p = book.performers.first.flatMap { book.actors.indices.contains($0) ? book.actors[$0] : nil }
        return (p.map { [$0] } ?? []) + book.extra
    }
    private func lineFloor(_ a: JellyActor) -> SIMD2<Float> { let c = a.sim.centroid(); return SIMD2(c.x, c.z) }

    /// Every body that has a seat stands in it and nobody is being carried: the line is formed. (The flow waits for this before a turn opens.)
    func showLineFormed() -> Bool {
        guard Self.lineKeeperOn, show.onStage, showBook.trickSet else { return true }
        return lineBodies().allSatisfy { a in
            guard let seat = showSeat(a.id) else { return true }
            return !(showBook.keep[a.id]?.gliding ?? false) && simd_distance(lineFloor(a), seat) < Self.lineAt
        }
    }

    /// Once per tick while the Trick round's stage is up: each body is on its way to its seat within its allowance, or the keeper carries it there (a short glide at `glideSpeed`, never a pop).
    /// A body pushed off its seat (the floor rules press bodies apart) is also carried back after `lineGrace` s; two bodies closer than `lineTouch` for `lineTouchHold` s are untangled the same way.
    func tickShowLine(dt: Float) {
        let book = showBook
        guard Self.lineKeeperOn, show.onStage, book.trickSet else { book.keep = [:]; return }
        let bodies = lineBodies()
        for a in bodies {
            guard let b = a.brain else { continue }
            var k = book.keep[a.id] ?? ShowSeatKeep()
            guard let seat = showSeat(a.id) else { book.keep[a.id] = nil; continue }
            let here = lineFloor(a)
            if k.seat == nil || simd_distance(k.seat!, seat) > 0.01 {          // a new leg: its allowance
                k.seat = seat; k.off = 0; k.waited = 0; k.gliding = false
                k.budget = min(Self.lineGrace + showLegLength(here, seat) / Self.lineWalkPace, Self.lineMaxLeg); k.stalled = 0
            }
            let d = simd_distance(here, seat)
            if d < Self.lineAt, !k.gliding { k.off = 0; book.keep[a.id] = k; continue }
            if !k.gliding {
                let waiting = book.pendingWalks.contains { $0.id == a.id } || book.via[a.id] != nil
                if waiting { k.waited += dt; if k.waited > Self.lineWaitMax { k.off = max(k.off, k.budget + 1) } } else { k.off += dt }          // (a body waiting its turn for the gate or the middle is not late: the wait is bounded by the one it waits for, who is kept to his own allowance)
                let moving = a.isWalking || b.pending != nil || { if case .none = b.script { return false }; return true }()
                if moving || waiting { k.stalled = 0; k.asked = false } else { k.stalled += dt }
                // a walk the brain dropped (it gives up a walk it cannot steer): one fresh ask at 0.4 s for a seat that is not the middle (the middle walks have their own retry), then the carry
                if k.stalled > 0.4, !k.asked, simd_distance(seat, ShowStage.playerSpot) > 0.01 { k.asked = true; showRoute(a, to: seat) }
                if k.stalled > Self.lineStall { k.off = max(k.off, k.budget + 1) }          // (stopped short of the seat with nothing to wait for: carried at once)
                // a body that has been in its seat and is pushed out of it has no leg: it gets the grace only
                if k.off > k.budget { k.gliding = true; showLineBegin(a, b) }
            }
            if k.gliding {
                let speed = min(Self.glideSpeed, 0.6 + d * 4)
                let step = min(d, speed * dt)
                if d <= 0.02 {
                    k.gliding = false; k.off = 0; showLineEnd(a, b)
                } else {
                    let dir = (seat - here) / d
                    a.sim.shift(byXZ: dir * step)
                    b.currentPose(a.sim)
                }
            }
            book.keep[a.id] = k
        }
    }
    /// The walk's length: a leg between the back row and the front goes through the gate (GameCare+Show.swift `showRoute`).
    private func showLegLength(_ here: SIMD2<Float>, _ seat: SIMD2<Float>) -> Float {
        let backHere = here.y < Self.backRowLine, backThere = seat.y < Self.backRowLine
        guard backHere != backThere else { return simd_distance(here, seat) }
        return simd_distance(here, ShowStage.gate) + simd_distance(ShowStage.gate, seat)
    }
    static let backRowLine: Float = -0.7
    private func showLineBegin(_ a: JellyActor, _ b: BlobBrain) {
        let book = showBook
        #if targetEnvironment(simulator)
        let why = "script=\(b.scriptKindName) activity=\(b.activity) pending=\(b.pending != nil) idle=\(String(describing: b.idleState.kind)) commanded=\(b.commanded) waitedFor=\(book.pendingWalks.contains { $0.id == a.id }) via=\(book.via[a.id] != nil)"
        #endif
        b.abortAll(a.sim, a.skinner)
        b.commandedIdle = nil; b.commandedFlip = false
        book.goals[a.id] = nil; book.heading[a.id] = nil; book.via[a.id] = nil; book.flops[a.id] = nil
        book.pendingWalks.removeAll { $0.id == a.id }
        book.placements += 1
        #if targetEnvironment(simulator)
        if DevArgs.enabled { let c = a.sim.centroid(); print(String(format: "[showline] PLACED body %d from (%.2f,%.2f) to seat %@ ", a.id, c.x, c.z, showSeat(a.id).map { String(format: "(%.2f,%.2f)", $0.x, $0.y) } ?? "-") + why) }
        #endif
    }
    private func showLineEnd(_ a: JellyActor, _ b: BlobBrain) {
        b.currentPose(a.sim)
        a.skinner.jelly.reset()
        b.restTimer = 0.4
        if abs(b.yaw) > 0.25 { b.startTurn(to: 0, sim: a.sim) }
    }
}
