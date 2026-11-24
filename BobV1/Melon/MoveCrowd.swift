//
//  MoveCrowd.swift
//  move-crowd-r1 (owner 11-24: "The collisions and crowding is killing the game"). Fewer bumps BY CONSTRUCTION for free, autonomous walkers (no job, no command, no social, no choreography).
//  ONE master switch: `MoveCrowd.on` (DevArgs `-MoveCrowd 0` or env MOVECROWD=0 = exactly the old steering). Parts, each its own sub-switch (env MOVECROWD_OFF=part,goal,... turns parts off
//  for a measurement; every number below has an env seam so a headless iteration needs no rebuild):
//    gap    one constant `gap` (1.45, just outside the 1.4 push radius) for the look-ahead trigger and the detour point (each walker clears the other's predicted spot by it alone)
//    goal   a roam goal is rejected if another body stands within `gap` of it or is walking to a spot within `gap` of it
//    yield  symmetric give-way: the one who is slower to the meeting / has less far to go waits (was always the lower id)
//    look   a walker on a waypoint leg looks ahead too
//    part   after a pair / group moment the members leave to different sides, staggered
//  The gait and the run are untouched (heading, route and start / stop timing only).
//

import Foundation
import simd

nonisolated enum MoveCrowd {
    private static let env = ProcessInfo.processInfo.environment
    private static func master() -> Bool {
        if let e = env["MOVECROWD"] { return e != "0" }
        guard DevArgs.enabled, let v = UserDefaults.standard.string(forKey: "MoveCrowd") else { return defaultOn }
        return !["0", "no", "false", "old", "off"].contains(v.lowercased())
    }
    static let defaultOn = false
    nonisolated(unsafe) static var on: Bool = master()
    private static let offParts = Set((env["MOVECROWD_OFF"] ?? "").split(separator: ",").map { String($0) })
    private static func part(_ k: String) -> Bool { !offParts.contains(k) }
    nonisolated(unsafe) static var gapOn = part("gap")
    nonisolated(unsafe) static var goalOn = part("goal")
    nonisolated(unsafe) static var yieldOn = part("yield")
    nonisolated(unsafe) static var lookOn = part("look")
    nonisolated(unsafe) static var partOn = part("part")
    nonisolated(unsafe) static var speedOn = part("speed")
    nonisolated(unsafe) static var allOn = part("all")
    private static func num(_ k: String, _ d: Float) -> Float { Float(env[k] ?? "") ?? d }

    /// The one clearance (u, centre to centre): trigger, detour offset, goal rejection.
    nonisolated(unsafe) static var gap = num("MOVECROWD_GAP", 1.45)

    static var text: String { "MoveCrowd on=\(on) gap=\(gapOn) goal=\(goalOn) yield=\(yieldOn) look=\(lookOn) part=\(partOn) speed=\(speedOn) all=\(allOn) gapU=\(gap)" }
}

/// Read by the scoreboard (tests): the switches as they stand.
enum MoveCrowdInfo { static var text: String { MoveCrowd.text } }

struct CrowdBook {
    var lookClock: Float = -10
}

extension MoveCrowd {
    /// part: the extra wait (s) per earlier-leaving mate after a moment, and the least angle between two strollers' directions (cos: below this).
    nonisolated(unsafe) static var partStagger = num("MOVECROWD_PART_STAGGER", 1.0)
    nonisolated(unsafe) static var partSplitCos = num("MOVECROWD_PART_SPLIT", -0.2)
    /// look: how often (s) a walker on a waypoint leg looks ahead.
    nonisolated(unsafe) static var lookEvery = num("MOVECROWD_LOOK_EVERY", 0.5)
    /// yield: the head-on walker with the right of way still veers by this share of `gap` to his right (the other clears by the whole gap alone).
    nonisolated(unsafe) static var headOnKeep = num("MOVECROWD_HEADON_KEEP", 0.25)
}

extension BlobBrain {
    /// A free, autonomous walker at home or on a park visit (no job, no command, no social, no toy / ball game, no race): the only bodies MoveCrowd steers.
    /// Meals never qualify (`homeRoom` is false while the tray is out), nor the café, the Show, the race or any choreographed walk.
    var crowdLive: Bool {
        MoveCrowd.on && (homeRoom || outingPlay) && roomFree && social == nil && !race.active && !volley.active && toy.waitUID < 0 && toy.chaseSpot == nil && bubbleLeash == nil && !tossBusy
    }
    /// goal: nobody stands within `gap` of the spot, and nobody is walking to a spot within `gap` of it.
    func crowdGoalFree(_ p: SIMD2<Float>) -> Bool {
        let g = MoveCrowd.gap
        for o in socialOthers() where o !== self {
            if simd_distance(o.position, p) < g { return false }
            if case .walk(let t, _) = o.script, simd_distance(t, p) < g { return false }
        }
        return true
    }
    /// yield: at a crossing, do I give way? The one who reaches the meeting second gives way (`roomAhead`); too close to call: the one with less far to go; then the lower id.
    func crowdGiveWay(his id: Int, at pos: SIMD2<Float>, vel: SIMD2<Float>, root: SIMD2<Float>, dir: SIMD2<Float>, vSelf: Float, myLeft: Float) -> Bool {
        let s = roomAhead(of: id, at: pos, vel: vel, root: root, dir: dir, vSelf: vSelf)
        if abs(s) > RoomTraffic.tieBand { return s > 0 }
        if let o = socialBrain(id), case .walk(let t, _) = o.script {
            let hisLeft = simd_distance(t, pos)
            if abs(hisLeft - myLeft) > 0.5 { return myLeft < hisLeft }
        }
        return steerID < id
    }
}

extension BlobBrain {
    /// look (from `steerTarget` while a waypoint is ahead): every `lookEvery` s the leg to the waypoint is looked at like a plain leg. nil = carry on to the waypoint;
    /// .some(nil) = stand this beat (give way); .some(w2) = a detour point put in front of the waypoint.
    func crowdWaypointLook(_ root: SIMD2<Float>, _ w: SIMD2<Float>) -> SIMD2<Float>?? {
        guard MoveCrowd.lookOn, crowdLive else { return nil }
        if yieldT > 0 {          // (already giving way on this leg: keep asking every step until clear)
        } else { guard peerClock - crowd.lookClock >= MoveCrowd.lookEvery else { return nil } }
        crowd.lookClock = peerClock
        switch lookAhead(root, w) {
        case .via(let w2):
            guard route.count < 4, simd_distance(w2, w) > 0.3 else { return nil }
            route.insert(w2, at: 0)
            return .some(w2)
        case .wait: return .some(nil)
        case .clear: return nil
        }
    }
}

extension BlobBrain {
    /// all: a detour point `w` is at least `gap` x 0.9 from every other body (but `except`, the one being passed), at its position now and where it will be when I get to `w`.
    func crowdDetourFree(_ w: SIMD2<Float>, root: SIMD2<Float>, vSelf: Float, except: Int) -> Bool {
        let t = min(simd_distance(root, w) / max(vSelf, 0.3), ContactTuning.lookTime)
        let r = MoveCrowd.gap * 0.9
        for p in steerPeers() where p.id != except {
            if simd_distance(p.pos, w) < r { return false }
            if p.id < Int.max / 4, let v = peerVel[p.id], simd_distance(p.pos + v * t, w) < r { return false }
        }
        return true
    }
}
